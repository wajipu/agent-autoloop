// A decision must not be attributed to a different run with the same rule and time.
import Foundation

@main
struct CardTraceTests {
    static func main() async throws {
        let card = try JSONDecoder().decode(HubCard.self, from: Data("""
        {"id":25,"kind":"ask","title":"需要决定","rule":"处理云效工作项","createdAt":"2026-11-09T09:17:32.250Z"}
        """.utf8))
        func page(_ runs: String, next: String) throws -> HubState {
            try JSONDecoder().decode(HubState.self, from: Data("""
            {"totals":{"running":0,"queued":0,"retrying":0,"unknown":0,"done":0,"doneToday":0,"nothing":0,"attention":1,"usage":{"input":0,"output":0,"cost":0}},"cards":[],"agents":[],"channels":[],"runs":\(runs),\(next)}
            """.utf8))
        }
        let first = try page("[]", next: "\"hasMore\":true,\"nextBefore\":1402")
        let second = try page("""
        [{"id":1402,"rule":"处理云效工作项","state":"done","attempts":0,"finishedAt":"2026-11-09T09:17:32.250Z","events":[{"source":"yunxiao","type":"workitem.opened","subject":"MGMF-99"}]},
         {"id":1401,"rule":"处理云效工作项","state":"done","attempts":0,"finishedAt":"2026-11-09T09:17:32.250Z","events":[{"source":"yunxiao","type":"card.answered","subject":"MGMF-47"}]}]
        """, next: "\"hasMore\":false")
        let result = try await CardTrace.lookup(card: card, page: { before in
            before == nil ? first : second
        }, facts: { run in
            [["changes": [["table": "cards", "row": ["id": run == 1401 ? 25 : 26, "run_id": run]]]]]
        })
        precondition(result?.run.id == 1401)
        precondition(result?.serial == "MGMF-47")
        print("Card trace tests passed")
    }
}
