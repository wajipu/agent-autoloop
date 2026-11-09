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

    /// 当前令牌对应的用户 id，创建工作项时当默认负责人。
    func currentUserID() async throws -> String {
        let data = try await request(path: "/oapi/v1/platform/user", method: "GET", body: nil)
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = object?["id"] as? String else { throw YunxiaoError.decoding("拿不到用户 id") }
        return id
    }

    private func workitemTypeID(category: IssueCategory) async throws -> String {
        let path = "/oapi/v1/projex/organizations/\(orgId)/projects/\(projectId)/workitemTypes?category=\(category.rawValue)"
        let data = try await request(path: path, method: "GET", body: nil)
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let chosen = list.first(where: { $0["defaultType"] as? Bool == true }) ?? list.first,
              let id = chosen["id"] as? String
        else { throw YunxiaoError.decoding("这个项目没有「\(category.label)」类型") }
        return id
    }

    /// 这个类型必填、又不在标准字段里的那些，用默认值补上。
    private func requiredCustomFields(typeID: String) async throws -> [String: String] {
        let path = "/oapi/v1/projex/organizations/\(orgId)/projects/\(projectId)/workitemTypes/\(typeID)/fields"
        let data = try await request(path: path, method: "GET", body: nil)
        guard let fields = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        let standard: Set<String> = ["subject", "description", "assignedTo", "verifier", "participants",
                                     "trackers", "tag", "sprint", "versions", "status", "priority", "seriousLevel"]
        var values: [String: String] = [:]
        for field in fields {
            guard field["required"] as? Bool == true,
                  let id = field["id"] as? String,
                  let options = field["options"] as? [[String: Any]],
                  !options.isEmpty
            else { continue }
            // 优先级、严重程度这类也是自定义字段，标准字段名里没有对应参数，同样要填
            if standard.contains(id), !["priority", "seriousLevel"].contains(id) { continue }
            if let fallback = field["defaultValue"] as? String, !fallback.isEmpty {
                values[id] = fallback
            } else if let first = options.first?["id"] as? String {
                values[id] = first
            }
        }
        return values
    }

    /// 建一条工作项，返回新工单 id。
    func createIssue(category: IssueCategory, subject: String, description: String) async throws -> String {
        let typeID = try await workitemTypeID(category: category)
        let assignee = try await currentUserID()
        let custom = try await requiredCustomFields(typeID: typeID)
        var body: [String: Any] = [
            "subject": subject,
            "spaceId": projectId,
            "workitemTypeId": typeID,
            "assignedTo": assignee,
        ]
        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["description"] = description
        }
        if !custom.isEmpty { body["customFieldValues"] = custom }
        let data = try await request(path: "/oapi/v1/projex/organizations/\(orgId)/workitems",
                                     method: "POST", body: body)
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = object?["id"] as? String else { throw YunxiaoError.decoding("建好了但没拿到 id") }
        return id
    }

    private func request(path: String, method: String, body: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
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
