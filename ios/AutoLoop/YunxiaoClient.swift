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
