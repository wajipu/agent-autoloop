// Prevent rich descriptions from losing their markup and plain text from being mistaken for HTML.
import Foundation

enum IssueCategory: String {
    case bug = "Bug"
    case task = "Task"
    case req = "Req"
}

@main
struct RichTextTests {
    static func main() throws {
        func decode(_ value: Any) throws -> RichText {
            let data = try JSONSerialization.data(withJSONObject: ["value": value])
            return try JSONDecoder().decode(Wrapper.self, from: data).value
        }

        let markdown = "# 标题\n- 第一项\n- 第二项\n\n`chanceCount < 3`"
        let plain = try decode(markdown)
        precondition(!plain.isHTML && plain.html == markdown)
        let inlineTag = try decode("# 标题\n请检查 `<span>` 标签")
        precondition(!inlineTag.isHTML)

        let html = "<article><h2>标题</h2><ul><li><strong>第一项</strong></li></ul></article>"
        let object = try decode(["htmlValue": html, "jsonMLValue": ["root", ["p", "text"]]])
        precondition(object.isHTML && object.html == html)

        let wrapped = try decode(String(data: JSONSerialization.data(withJSONObject: ["htmlValue": html]), encoding: .utf8)!)
        precondition(wrapped.isHTML && wrapped.html == html)
        print("RichText tests passed")
    }

    private struct Wrapper: Decodable {
        let value: RichText
    }
}
