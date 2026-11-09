import Foundation

struct CardTrace {
    let run: HubRun
    let serial: String?

    static func lookup(
        card: HubCard,
        page: (Int?) async throws -> HubState,
        facts: (Int) async throws -> [[String: Any]]
    ) async throws -> CardTrace? {
        guard let created = HubRun.date(card.createdAt), let rule = card.rule else { return nil }
        var before: Int?
        repeat {
            let state = try await page(before)
            for run in state.runs where run.rule == rule && run.finished == created {
                let records = try await facts(run.id)
                for fact in records {
                    for change in fact["changes"] as? [[String: Any]] ?? [] {
                        guard change["table"] as? String == "cards",
                              let row = change["row"] as? [String: Any],
                              row["id"] as? Int == card.id,
                              row["run_id"] as? Int == run.id else { continue }
                        let lane = row["lane"] as? String
                        let subject = run.events?.first(where: { $0.source == "yunxiao" })?.subject
                        let serial = [lane, subject].compactMap { $0 }.first(where: isSerial)
                        return CardTrace(run: run, serial: serial)
                    }
                }
            }
            guard state.hasMore == true, let next = state.nextBefore, next != before else { return nil }
            before = next
        } while true
    }

    private static func isSerial(_ value: String) -> Bool {
        value.range(of: "^[A-Z]{2,8}-[0-9]+$", options: .regularExpression) != nil
    }
}
