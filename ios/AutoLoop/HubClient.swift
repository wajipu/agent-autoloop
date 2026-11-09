import Foundation

struct HubTotals: Decodable {
    let running: Int
    let queued: Int
    let retrying: Int
    let unknown: Int
    let done: Int
    let doneToday: Int
    let nothing: Int
    let attention: Int
    let usage: HubUsage
}

struct HubUsage: Decodable {
    let input: Int
    let output: Int
    let cost: Double

    var tokens: Int { input + output }
}

struct HubCard: Decodable, Identifiable, Hashable {
    let id: Int
    let kind: String
    let title: String
    let text: String?
    let options: [String]?
    let rule: String?
    let createdAt: String?
    let lane: String?
}

struct HubAgent: Decodable, Identifiable {
    let id: String
    let name: String
    let use: String
    let worker: String
    let online: Bool
    let seenAt: String?
}

struct HubChannel: Decodable, Identifiable {
    let id: String
    let name: String
    let online: Bool
}

struct HubRun: Decodable, Identifiable, Hashable {
    let id: Int
    let rule: String
    let agent: String?
    let state: String
    let attempts: Int
    let createdAt: String?
    let finishedAt: String?
    let summary: String?
    let error: String?
    let link: String?
    let session: String?
    let events: [HubEvent]?

    var created: Date? { HubRun.date(createdAt) }
    var finished: Date? { HubRun.date(finishedAt) }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain = ISO8601DateFormatter()

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return iso.date(from: text) ?? isoPlain.date(from: text)
    }
}

struct HubEvent: Decodable, Hashable {
    let source: String
    let type: String
    let subject: String?
    let summary: String?
    let link: String?
}

struct HubSpending: Decodable {
    let rounds: Int
    let tokens: Int
    let cost: Double
}

struct HubState: Decodable {
    let now: String?
    let timezone: String?
    let totals: HubTotals
    let cards: [HubCard]
    let agents: [HubAgent]
    let channels: [HubChannel]
    let runs: [HubRun]
    let spending: Spending?
    let hasMore: Bool?
    let nextBefore: Int?

    struct Spending: Decodable {
        let today: HubSpending?
        let week: HubSpending?
    }
}

enum HubError: LocalizedError {
    case notConfigured
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "去「设置」填中台地址和本人密钥"
        case let .http(code, body): "中台返回 \(code)：\(body)"
        }
    }
}

struct HubClient {
    let baseURL: String
    let key: String

    func state(before: Int? = nil) async throws -> HubState {
        let suffix = before.map { "?before=\($0)" } ?? ""
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/v1/state" + suffix) else {
            throw HubError.notConfigured
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return try decode(data) }
        guard http.statusCode == 200 else {
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw HubError.http(http.statusCode, body)
        }
        return try decode(data)
    }

    /// 一轮的时间线：/v1/runs/<id>/why 返回的原始事实，交给 Timeline 归并成人话。
    func why(runID: Int) async throws -> [[String: Any]] {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/v1/runs/\(runID)/why") else {
            throw HubError.notConfigured
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw HubError.http(code, String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        if let list = object as? [[String: Any]] { return list }
        if let wrapper = object as? [String: Any], let list = wrapper["facts"] as? [[String: Any]] { return list }
        return []
    }

    /// 回答一张卡片；choice 是选项下标（0 起）。
    func answer(cardID: Int, choice: Int) async throws {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/v1/cards/\(cardID)/answer") else {
            throw HubError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["choice": choice])
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw HubError.http(code, String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
    }

    private func decode(_ data: Data) throws -> HubState {
        try JSONDecoder().decode(HubState.self, from: data)
    }
}

enum RunStyle {
    static func label(_ state: String) -> String {
        switch state {
        case "claimed": "在跑"
        case "queued": "排队"
        case "unknown": "未知"
        case "done": "完成"
        case "cancelled": "已停止"
        case "nothing": "无事"
        default: state
        }
    }
}
