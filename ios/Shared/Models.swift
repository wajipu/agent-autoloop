import Foundation

struct Named: Decodable, Hashable {
    let name: String?
    let id: String?
}

struct Workitem: Identifiable, Decodable, Hashable {
    let id: String
    let serialNumber: String
    let subject: String?
    let status: Named?
    let assignedTo: Named?
    let workitemType: Named?
    let gmtModified: Double?
    let categoryId: String?

    var category: IssueCategory {
        IssueCategory(rawValue: categoryId ?? "") ?? .bug
    }
    var identifier: String { id }

    var statusName: String { status?.name ?? "—" }
    var assigneeName: String? { assignedTo?.name }
    var typeName: String? { workitemType?.name }

    var updated: Date? {
        guard let gmtModified else { return nil }
        return Date(timeIntervalSince1970: gmtModified / 1000)
    }
}

/// 云效的正文可能是纯字符串，也可能是 { htmlValue: "..." }，还可能是包了一层 JSON 的字符串。
struct RichText: Decodable {
    let html: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let plain = try? container.decode(String.self) {
            html = RichText.unwrap(plain)
            return
        }
        if let object = try? container.decode([String: String].self) {
            html = object["htmlValue"] ?? ""
            return
        }
        html = ""
    }

    private static func unwrap(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = object["htmlValue"] as? String
        else { return text }
        return html
    }

    /// 富文本转纯文本：换行、去标签、解实体。
    var text: String {
        guard html.contains("<") else { return html.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result = html
        result = result.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</(p|div|li|h[1-6]|tr|article)>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&amp;": "&"]
        for (key, value) in entities {
            result = result.replacingOccurrences(of: key, with: value)
        }
        result = result.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WorkitemDetail: Decodable {
    let id: String
    let serialNumber: String
    let subject: String?
    let status: Named?
    let assignedTo: Named?
    let gmtCreate: Double?
    let gmtModified: Double?
    let description: RichText?
    let labels: [Named]?

    var created: Date? { gmtCreate.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var updated: Date? { gmtModified.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var body: String { description?.text ?? "" }
}
