import Foundation

enum YunxiaoError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "还没填云效令牌，去「设置」里填一下"
        case let .http(code, body): "云效返回 \(code)：\(body)"
        case let .decoding(message): "看不懂云效的返回：\(message)"
        }
    }
}

/// 云效 Projex：`x-yunxiao-token` 鉴权，按企业 id 区分。
struct YunxiaoClient {
    let orgId: String
    let projectId: String
    let token: String
    private let base = URL(string: "https://openapi-rdc.aliyuncs.com")!

    func search(category: IssueCategory, page: Int = 1, perPage: Int = 100) async throws -> [Workitem] {
        guard !token.isEmpty else { throw YunxiaoError.notConfigured }
        let body: [String: Any] = [
            "category": category.rawValue,
            "spaceId": projectId,
            "spaceType": "Project",
            "page": page,
            "perPage": perPage,
        ]
        let data = try await request(path: "/oapi/v1/projex/organizations/\(orgId)/workitems:search",
                                     method: "POST", body: body)
        do {
            return try JSONDecoder().decode([Workitem].self, from: data)
        } catch {
            throw YunxiaoError.decoding(String(describing: error))
        }
    }

    func detail(serialNumber: String) async throws -> WorkitemDetail {
        guard !token.isEmpty else { throw YunxiaoError.notConfigured }
        let path = "/oapi/v1/projex/organizations/\(orgId)/workitems/\(serialNumber.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? serialNumber)"
        let data = try await request(path: path, method: "GET", body: nil)
        do {
            return try JSONDecoder().decode(WorkitemDetail.self, from: data)
        } catch {
            throw YunxiaoError.decoding(String(describing: error))
        }
    }

    // MARK: 创建

    struct FieldOption: Identifiable, Hashable {
        let id: String
        let value: String
    }

    struct FieldDef: Identifiable, Hashable {
        let id: String
        let name: String
        let options: [FieldOption]
        let defaultValue: String?
    }

    /// 当前令牌对应的用户 id，创建工作项时当默认负责人。
    func currentUserID() async throws -> String {
        let data = try await request(path: "/oapi/v1/platform/user", method: "GET", body: nil)
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = object?["id"] as? String else { throw YunxiaoError.decoding("拿不到用户 id") }
        return id
    }

    func workitemTypeID(category: IssueCategory) async throws -> String {
        let path = "/oapi/v1/projex/organizations/\(orgId)/projects/\(projectId)/workitemTypes?category=\(category.rawValue)"
        let data = try await request(path: path, method: "GET", body: nil)
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let chosen = list.first(where: { $0["defaultType"] as? Bool == true }) ?? list.first,
              let id = chosen["id"] as? String
        else { throw YunxiaoError.decoding("这个项目没有「\(category.label)」类型") }
        return id
    }

    /// 这个类型必填、而且要在表单里选的字段（优先级、严重程度这类）。
    func requiredFields(typeID: String) async throws -> [FieldDef] {
        let path = "/oapi/v1/projex/organizations/\(orgId)/projects/\(projectId)/workitemTypes/\(typeID)/fields"
        let data = try await request(path: path, method: "GET", body: nil)
        guard let fields = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let skip: Set<String> = ["subject", "description", "assignedTo", "verifier", "participants",
                                 "trackers", "tag", "sprint", "versions", "status"]
        return fields.compactMap { field -> FieldDef? in
            guard field["required"] as? Bool == true,
                  let id = field["id"] as? String, !skip.contains(id),
                  let raw = field["options"] as? [[String: Any]], !raw.isEmpty
            else { return nil }
            let options = raw.compactMap { option -> FieldOption? in
                guard let oid = option["id"] as? String else { return nil }
                return FieldOption(id: oid, value: option["value"] as? String ?? oid)
            }
            return FieldDef(id: id, name: field["name"] as? String ?? id,
                            options: options, defaultValue: field["defaultValue"] as? String)
        }
    }

    /// 把附件的嵌入地址追加到工作项描述末尾。
    func appendDescription(issueID: String, addition: String) async throws {
        let detailPath = "/oapi/v1/projex/organizations/\(orgId)/workitems/\(issueID)"
        let current = try await request(path: detailPath, method: "GET", body: nil)
        let object = try? JSONSerialization.jsonObject(with: current) as? [String: Any]
        guard let raw = object?["description"] else { throw YunxiaoError.decoding("拿不到原描述") }
        var html = ""
        if let text = raw as? String {
            html = text
        } else if let wrapped = raw as? [String: Any], let value = wrapped["htmlValue"] as? String {
            html = value
        }
        if html.trimmingCharacters(in: .whitespaces).hasPrefix("{"),
           let data = html.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = parsed["htmlValue"] as? String {
            html = value
        }
        let merged = (html + "\n" + addition).trimmingCharacters(in: .whitespacesAndNewlines)
        try await request(path: detailPath, method: "PUT",
                          body: ["description": merged.isEmpty ? addition : merged])
    }

    /// 上传附件（任何文件都能传），返回 embedUrl（图片可直接嵌进描述）。
    func uploadAttachment(issueID: String, name: String, data: Data) async throws -> String {
        guard let url = URL(string: base.absoluteString + "/oapi/v1/projex/organizations/\(orgId)/workitems/\(issueID)/attachments") else {
            throw YunxiaoError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "x-yunxiao-token")
        let boundary = "autoloop-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        request.timeoutInterval = 60

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw YunxiaoError.http(code, String(data: responseData.prefix(200), encoding: .utf8) ?? "")
        }
        let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if let embed = object?["embedUrl"] as? String, !embed.isEmpty { return embed }
        if let html = object?["embedHtml"] as? String { return html }
        throw YunxiaoError.decoding("上传成功但没拿到嵌入地址")
    }

    /// 建一条工作项，返回新工单 id。
    func createIssue(category: IssueCategory,
                     subject: String,
                     description: String,
                     customValues: [String: String] = [:],
                     typeID: String? = nil,
                     assignee: String? = nil) async throws -> String {
        let type: String
        if let typeID { type = typeID } else { type = try await workitemTypeID(category: category) }
        let owner: String
        if let assignee { owner = assignee } else { owner = try await currentUserID() }
        var body: [String: Any] = [
            "subject": subject,
            "spaceId": projectId,
            "workitemTypeId": type,
            "assignedTo": owner,
        ]
        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["description"] = description
        }
        if !customValues.isEmpty { body["customFieldValues"] = customValues }
        let data = try await request(path: "/oapi/v1/projex/organizations/\(orgId)/workitems",
                                     method: "POST", body: body)
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = object?["id"] as? String else { throw YunxiaoError.decoding("建好了但没拿到 id") }
        return id
    }

    private func request(path: String, method: String, body: [String: Any]?) async throws -> Data {
        guard let url = URL(string: base.absoluteString + path) else { throw YunxiaoError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "x-yunxiao-token")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            throw YunxiaoError.http(http.statusCode, String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        return data
    }
}
