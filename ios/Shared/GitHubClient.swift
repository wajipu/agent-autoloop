import Foundation

/// GitHub Issues 客户端：对外暴露与旧云效客户端一致的模型（Workitem/WorkitemDetail/Comment/Activity），
/// 视图层无需感知 REST 细节。issue 的 number 就是 serialNumber。
struct GitHubClient {
    let owner: String
    let repo: String
    let token: String

    private let base = URL(string: "https://api.github.com")!

    enum GitHubError: LocalizedError, Decodable {
        case api(String)
        case notFound

        var errorDescription: String? {
            switch self {
            case .api(let message): return message
            case .notFound: return "Issue 不存在（或没有权限）"
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let message = (try? container.decode(String.self)) ?? "请求失败"
            self = message == "Not Found" ? .notFound : .api(message)
        }
    }

    struct Comment: Identifiable, Decodable {
        let id: String
        let user: String
        let at: Date?
        let content: String
    }

    struct Activity: Identifiable {
        let id: String
        let user: String
        let at: Date?
        let text: String
        let isComment = false
    }

    struct WorkflowStatus: Identifiable, Hashable {
        let id: String
        let name: String
    }


    private func request(path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: base.absoluteString + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { throw GitHubError.notFound }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw GitHubError.api(message ?? "HTTP \(http.statusCode)")
        }
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data, dateDecoding: JSONDecoder.DateDecodingStrategy = .iso8601) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecoding
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - 模型

    struct RawIssue: Decodable {
        let id: Int
        let number: Int
        let title: String
        let body: String?
        let state: String
        let createdAt: String
        let updatedAt: String
        let htmlURL: String
        let user: Login
        let labels: [RawLabel]?
        let assignee: Login?
        let comments: Int?

        enum CodingKeys: String, CodingKey {
            case id, number, title, body, state, user, labels, assignee, comments
            case htmlURL = "html_url"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    struct Login: Decodable { let login: String }
    struct RawLabel: Decodable { let name: String }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func decodeIssue(_ raw: RawIssue) -> Workitem {
        let stateName = raw.state == "closed" ? "关闭" : "打开"
        let label = raw.labels?.first?.name
        return Workitem(
            id: String(raw.number),
            serialNumber: "#\(raw.number)",
            subject: raw.title,
            status: Named(name: stateName, id: raw.state),
            assignedTo: raw.assignee.map { Named(name: $0.login, id: $0.login) },
            workitemType: label.map { Named(name: $0, id: $0) },
            gmtModified: isoDate(raw.updatedAt)?.timeIntervalSince1970,
            categoryId: label)
    }

    private static func isoDate(_ text: String) -> Date? {
        isoFormatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func workitemDetail(_ raw: RawIssue) -> WorkitemDetail {
        let stateName = raw.state == "closed" ? "关闭" : "打开"
        let label = raw.labels?.first?.name
        return WorkitemDetail(
            id: String(raw.number),
            serialNumber: "#\(raw.number)",
            subject: raw.title,
            status: Named(name: stateName, id: raw.state),
            assignedTo: raw.assignee.map { Named(name: $0.login, id: $0.login) },
            gmtCreate: isoDate(raw.createdAt)?.timeIntervalSince1970,
            gmtModified: isoDate(raw.updatedAt)?.timeIntervalSince1970,
            description: plainRichText(raw.body ?? ""),
            labels: raw.labels?.map { Named(name: $0.name, id: $0.name) },
            categoryId: label,
            workitemType: label.map { Named(name: $0, id: $0) })
    }

    private static func plainRichText(_ text: String) -> RichText {
        RichText(plain: text)
    }

    // MARK: - 列表 / 详情

    /// 兼容旧 searchTree 调用：返回该仓库全部 Issue（含关闭），按 label 过滤。
    func searchTree(category: String) async throws -> [Workitem] {
        let label = IssueCategory(rawValue: category)?.githubLabel
        let query = label.map { "repos/\(owner)/\(repo)/issues?state=all&per_page=100&labels=\($0)" }
            ?? "repos/\(owner)/\(repo)/issues?state=all&per_page=100"
        let data = try await request(path: query)
        let raws = try Self.decode([RawIssue].self, from: data)
        return raws.map(Self.decodeIssue)
    }

    func detail(serialNumber: String) async throws -> WorkitemDetail {
        guard let number = Int(serialNumber.replacingOccurrences(of: "#", with: "")) else {
            throw GitHubError.api("编号格式不对：\(serialNumber)")
        }
        let data = try await request(path: "/repos/\(owner)/\(repo)/issues/\(number)")
        return Self.workitemDetail(try Self.decode(RawIssue.self, from: data))
    }

    /// 按编号或标题关键字找关联 Issue。
    func findWorkitem(serialNumber: String) async throws -> Workitem? {
        let serial = serialNumber.replacingOccurrences(of: "#", with: "")
        if let number = Int(serial) {
            let data = try await request(path: "/repos/\(owner)/\(repo)/issues/\(number)")
            return Self.decodeIssue(try Self.decode(RawIssue.self, from: data))
        }
        let escaped = serial.replacingOccurrences(of: "\"", with: "")
        let data = try await request(path: "/search/issues?q=repo:\(owner)/\(repo)+\(escaped)+in:title&per_page=1")
        struct SearchResult: Decodable { let items: [RawIssue] }
        let result = try Self.decode(SearchResult.self, from: data)
        return result.items.first.map(Self.decodeIssue)
    }

    func issueURL(number: Int) -> URL? {
        URL(string: "https://github.com/\(owner)/\(repo)/issues/\(number)")
    }

    // MARK: - 状态 / 标签

    func workflowStatuses(category: IssueCategory) async throws -> [WorkflowStatus] {
        [WorkflowStatus(id: "open", name: "打开"), WorkflowStatus(id: "closed", name: "关闭")]
    }

    func updateStatus(issueID: String, statusID: String) async throws {
        guard let number = Int(issueID) else { throw GitHubError.api("编号格式不对") }
        let state = statusID == "closed" ? "closed" : "open"
        _ = try await request(path: "/repos/\(owner)/\(repo)/issues/\(number)", method: "PATCH",
                              body: ["state": state])
    }

    func addLabel(number: Int, label: String) async throws {
        _ = try await request(path: "/repos/\(owner)/\(repo)/issues/\(number)/labels", method: "POST",
                              body: ["labels": [label]])
    }

    // MARK: - 评论 / 动态

    struct RawComment: Decodable {
        let id: Int
        let body: String
        let createdAt: String
        let user: Login
        enum CodingKeys: String, CodingKey {
            case id, body, user
            case createdAt = "created_at"
        }
    }

    func comments(issueID: String) async throws -> [Comment] {
        guard let number = Int(issueID) else { return [] }
        let data = try await request(path: "/repos/\(owner)/\(repo)/issues/\(number)/comments?per_page=100")
        let raws = try Self.decode([RawComment].self, from: data)
        return raws.map {
            Comment(id: String($0.id), user: $0.user.login,
                    at: Self.isoDate($0.createdAt), content: $0.body)
        }
    }

    func addComment(issueID: String, content: String) async throws {
        guard let number = Int(issueID) else { throw GitHubError.api("编号格式不对") }
        _ = try await request(path: "/repos/\(owner)/\(repo)/issues/\(number)/comments", method: "POST",
                              body: ["body": content])
    }

    /// GitHub 没有云效那种动态流；给一条“创建于”占位，时间线不至于空。
    func activities(issueID: String) async throws -> [Activity] {
        guard let number = Int(issueID),
              let data = try? await request(path: "/repos/\(owner)/\(repo)/issues/\(number)")
        else { return [] }
        let raw = try Self.decode(RawIssue.self, from: data)
        guard let at = Self.isoDate(raw.createdAt) else { return [] }
        return [Activity(id: "created-\(raw.number)", user: raw.user.login, at: at, text: "创建了 Issue")]
    }

    // MARK: - 建单

    @discardableResult
    func createIssue(category: IssueCategory, subject: String, description: String) async throws -> Workitem {
        let data = try await request(path: "/repos/\(owner)/\(repo)/issues", method: "POST",
                              body: ["title": subject, "body": description,
                                     "labels": [category.githubLabel]])
        return Self.decodeIssue(try Self.decode(RawIssue.self, from: data))
    }

    func currentUser() async throws -> String {
        let data = try await request(path: "/user")
        return try Self.decode(Login.self, from: data).login
    }
}
