import Foundation

/// 规则配置走控制台（28090）的 /config/rules，鉴权用本人密钥。
struct RulesClient {
    let baseURL: String
    let key: String

    struct Payload {
        var rules: [[String: Any]]
        var disabled: [[String: Any]]
        var agents: [String: Any]
        var sources: [String: Any]
    }

    func load() async throws -> Payload {
        let data = try await request(path: "/config/rules", method: "GET", body: nil)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HubError.http(500, "配置返回的不是 JSON")
        }
        return Payload(
            rules: object["rules"] as? [[String: Any]] ?? [],
            disabled: object["disabled"] as? [[String: Any]] ?? [],
            agents: object["agents"] as? [String: Any] ?? [:],
            sources: object["sources"] as? [String: Any] ?? [:]
        )
    }

    func save(rules: [[String: Any]], disabled: [[String: Any]], agents: [String: Any]? = nil) async throws -> String {
        var payload: [String: Any] = ["rules": rules, "disabled": disabled]
        if let agents { payload["agents"] = agents }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await request(path: "/config/rules", method: "PUT", body: body)
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["check"] as? String ?? "已保存"
    }

    private func request(path: String, method: String, body: Data?) async throws -> Data {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + path) else {
            throw HubError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = body
        }
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = object?["error"] as? String ?? String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw HubError.http(http.statusCode, message)
        }
        return data
    }
}

/// 一条规则的只读视图；写回时只动 name / when / prompt / to，其余字段原样保留。
struct RuleItem: Identifiable {
    var raw: [String: Any]
    var enabled: Bool

    var id: String { (raw["name"] as? String ?? "?") + (enabled ? "" : "-off") }
    var name: String { raw["name"] as? String ?? "(未命名)" }
    var to: String { raw["to"] as? String ?? "—" }
    var prompt: String { raw["prompt"] as? String ?? "" }
    var cron: String? { (raw["when"] as? [String: Any])?["cron"] as? String }

    var trigger: String {
        if let cron { return "定时 \(cron)" }
        let when = raw["when"] as? [String: Any] ?? [:]
        let source = when["source"] as? String ?? "事件"
        let types = (when["types"] as? [String])?.joined(separator: "、") ?? ""
        return types.isEmpty ? "事件 · \(source)" : "事件 · \(source) · \(types)"
    }

    static func list(_ payload: RulesClient.Payload) -> [RuleItem] {
        payload.rules.map { RuleItem(raw: $0, enabled: true) }
            + payload.disabled.map { RuleItem(raw: $0, enabled: false) }
    }
}
