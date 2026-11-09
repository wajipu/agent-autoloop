import Foundation

/// 从一轮的结论里抠出「改了哪些项目」。
/// 认两种写法：
///   **改动**
///   - koklam-plus: 3a91f2c 修菜单权限（2 个文件）
/// 以及机器可读的围栏：
///   ```agent-autoloop-changes
///   {"items":[{"repo":"koklam-plus","commit":"3a91f2c","subject":"...","files":2}]}
///   ```
struct ChangeItem: Identifiable, Hashable {
    let id = UUID()
    let repo: String
    let commit: String?
    let subject: String
    let files: Int?
    let none: Bool
}

enum ChangeParser {
    /// 结论里去掉改动块之后剩下的正文（改动块单独渲染，别重复贴一遍）。
    static func prose(_ text: String?) -> String {
        guard var out = text else { return "" }
        for marker in ["**改动**", "\n改动：", "\n改动:"] {
            if let range = out.range(of: marker) { out = String(out[..<range.lowerBound]) }
        }
        if let range = out.range(of: "```agent-autoloop-changes") { out = String(out[..<range.lowerBound]) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ text: String?) -> [ChangeItem] {
        guard let text, !text.isEmpty else { return [] }
        let json = parseJSON(text)
        return json.isEmpty ? parseLines(text) : json
    }

    // MARK: 机器可读块

    private static func parseJSON(_ text: String) -> [ChangeItem] {
        guard let start = text.range(of: "```agent-autoloop-changes"),
              let end = text.range(of: "```", range: start.upperBound..<text.endIndex)
        else { return [] }
        let body = String(text[start.upperBound..<end.lowerBound])
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]]
        else { return [] }
        return items.compactMap { item in
            guard let repo = item["repo"] as? String else { return nil }
            return ChangeItem(repo: repo,
                              commit: item["commit"] as? String,
                              subject: item["subject"] as? String ?? "",
                              files: item["files"] as? Int,
                              none: false)
        }
    }

    // MARK: 人写的清单

    private static func parseLines(_ text: String) -> [ChangeItem] {
        var out: [ChangeItem] = []
        var inSection = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("**改动**") || line == "改动：" || line == "改动:" {
                inSection = true
                continue
            }
            if inSection && line.isEmpty { continue }
            if inSection && !line.hasPrefix("-") { break }
            guard inSection, line.hasPrefix("-") else { continue }

            let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
            if body.hasSuffix("没有提交") {
                let repo = body.components(separatedBy: ":").first ?? body
                out.append(ChangeItem(repo: repo.trimmingCharacters(in: .whitespaces),
                                      commit: nil, subject: "这一轮没有提交", files: 0, none: true))
                continue
            }
            // - repo: abc1234 说明（N 个文件）
            guard let colon = body.firstIndex(of: ":") else { continue }
            let repo = String(body[..<colon]).trimmingCharacters(in: .whitespaces)
            var rest = String(body[body.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            var files: Int?
            if let open = rest.range(of: "（", options: .backwards),
               let close = rest.range(of: "个文件）", options: .backwards),
               open.upperBound <= close.lowerBound {
                files = Int(rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces))
                rest = String(rest[..<open.lowerBound]).trimmingCharacters(in: .whitespaces)
            }

            var commit: String?
            let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if let first = parts.first, first.count >= 7, first.count <= 40,
               first.allSatisfy({ $0.isHexDigit }) {
                commit = String(first)
                rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            }
            out.append(ChangeItem(repo: repo, commit: commit, subject: rest, files: files, none: false))
        }
        return out
    }
}
