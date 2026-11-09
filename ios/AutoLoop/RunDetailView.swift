import SwiftUI

// MARK: - 轮次详情

struct RunDetailView: View {
    let run: HubRun
    @StateObject private var settings = AppSettings.shared
    @State private var steps: [TimelineStep]?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("#\(run.id)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        StateBadge(state: run.state)
                        if run.attempts > 0 {
                            Text("第 \(run.attempts + 1) 次")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(run.rule)
                        .font(.title3.weight(.semibold))
                    let prose = ChangeParser.prose(run.summary)
                    if !prose.isEmpty {
                        Text(prose)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            let changes = ChangeParser.parse(run.summary)
            if !changes.isEmpty {
                Section("改动") {
                    ForEach(changes) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.none ? "minus.circle" : "hammer")
                                .font(.caption)
                                .foregroundStyle(item.none ? Color.secondary : Color.accentColor)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.repo).font(.subheadline.weight(.medium))
                                    if let commit = item.commit {
                                        Text(commit)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    if let files = item.files, files > 0 {
                                        Text("\(files) 个文件")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                if !item.subject.isEmpty {
                                    Text(item.subject)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let events = run.events, !events.isEmpty {
                let first = events[0]
                if let subject = first.subject, !subject.isEmpty {
                    Section("在处理") {
                        Label(subject, systemImage: "target")
                            .font(.subheadline.weight(.medium))
                            .textSelection(.enabled)
                    }
                }
            }

            Section("属性") {
                LabeledContent("接单 Agent", value: run.agent ?? "—")
                if let created = run.created {
                    LabeledContent("开始", value: StatusStyle.stamp(created))
                }
                if let finished = run.finished {
                    LabeledContent("结束", value: StatusStyle.stamp(finished))
                    LabeledContent("用时", value: duration(from: run.created, to: finished))
                }
            }

            if let events = run.events, !events.isEmpty {
                Section("触发事件") {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(event.source) · \(event.type)")
                                .font(.subheadline)
                            if let subject = event.subject, !subject.isEmpty {
                                Text(subject).font(.caption).foregroundStyle(.secondary)
                            }
                            if let summary = event.summary, !summary.isEmpty {
                                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                            if let link = event.link, let url = URL(string: link) {
                                Link("打开来源", destination: url).font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let link = run.link, !link.isEmpty {
                Section("会话") {
                    if let url = URL(string: link), link.hasPrefix("http") {
                        Link(destination: url) {
                            Label("打开这一轮的会话", systemImage: "arrow.up.right.square")
                        }
                    } else {
                        Text(link)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    if let session = run.session, !session.isEmpty {
                        LabeledContent("会话 id") {
                            Text(session)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if let message = run.error, !message.isEmpty {
                Section("错误") {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            Section("时间线") {
                if let steps {
                    if steps.isEmpty {
                        Text("没有更多记录").foregroundStyle(.secondary)
                    } else {
                        ForEach(steps) { step in
                            TimelineRow(step: step)
                        }
                    }
                } else if let error {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("第 \(run.id) 轮")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard settings.hubConfigured else {
            error = "还没配中台"
            return
        }
        let client = HubClient(baseURL: settings.hubURL, key: settings.hubKey)
        do {
            let facts = try await client.why(runID: run.id)
            steps = Timeline.build(facts: facts, runID: run.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func duration(from start: Date?, to end: Date) -> String {
        guard let start else { return "—" }
        let gap = max(0, end.timeIntervalSince(start))
        if gap < 60 { return "\(Int(gap)) 秒" }
        if gap < 3600 { return "\(Int(gap / 60)) 分 \(Int(gap.truncatingRemainder(dividingBy: 60))) 秒" }
        return "\(Int(gap / 3600)) 小时 \(Int((gap / 60).truncatingRemainder(dividingBy: 60))) 分"
    }
}

struct TimelineStep: Identifiable {
    let id = UUID()
    let at: Date?
    let text: String
}

struct TimelineRow: View {
    let step: TimelineStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.text)
                    .font(.subheadline)
                if let at = step.at {
                    Text(StatusStyle.stamp(at))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 1)
    }
}

enum Timeline {
    static func build(facts: [[String: Any]], runID: Int) -> [TimelineStep] {
        var out: [TimelineStep] = []
        var last: [String: String] = [:]
        let seenEvents = NSMutableSet()

        for fact in facts {
            let type = fact["type"] as? String ?? ""
            let at = date(fact["at"])

            if type == "started", last["started"] == nil {
                out.append(TimelineStep(at: at, text: "开始处理"))
                last["started"] = "1"
            }
            if type == "rules", last["rules"] == nil {
                out.append(TimelineStep(at: at, text: "规则版本 #\(fact["seq"] as? Int ?? 0)"))
                last["rules"] = "1"
            }

            for change in fact["changes"] as? [[String: Any]] ?? [] {
                let table = change["table"] as? String ?? ""
                guard let row = change["row"] as? [String: Any] else { continue }

                if table == "runs", (row["id"] as? Int) == runID {
                    if let claimed = row["claimed_at"] as? String, last["claimed"] != claimed {
                        out.append(TimelineStep(at: date(claimed), text: "接单程序领取"))
                        last["claimed"] = claimed
                    }
                    if let finished = row["finished_at"] as? String, last["finished"] != finished {
                        let summary = row["summary"] as? String ?? ""
                        let state = row["state"] as? String ?? ""
                        let tail = summary.isEmpty ? (state == "cancelled" ? "已停止" : "没有填写结论") : summary
                        out.append(TimelineStep(at: date(finished), text: "结束：\(tail)"))
                        last["finished"] = finished
                    }
                    let attempts = String(describing: row["attempts"] ?? 0)
                    if (row["state"] as? String) == "queued", last["attempts"] != nil, last["attempts"] != attempts {
                        let message = row["error"] as? String ?? ""
                        out.append(TimelineStep(at: at, text: "本次未完成：\(message)"))
                    }
                    if (row["state"] as? String) == "queued" { last["attempts"] = attempts }
                    if let link = row["link"] as? String, last["link"] != link {
                        out.append(TimelineStep(at: at, text: "会话：\(link)"))
                        last["link"] = link
                    }
                }

                if table == "events", let eventID = row["id"] as? Int, !seenEvents.contains(eventID) {
                    seenEvents.add(eventID)
                    let source = row["source"] as? String ?? ""
                    let kind = row["type"] as? String ?? ""
                    let subject = row["subject"] as? String ?? ""
                    let parts = [source, kind] + (subject.isEmpty ? [] : [subject])
                    out.append(TimelineStep(at: date(row["received_at"]), text: "触发事件：\(parts.joined(separator: " · "))"))
                }

                if table == "cards", (row["run_id"] as? Int) == runID || (row["answer_event"] as? Int) != nil {
                    if let decided = row["decided_at"] as? String, last["card-\(row["id"] ?? 0)"] != decided {
                        let title = row["title"] as? String ?? ""
                        let answer = row["answer"] as? String ?? ""
                        out.append(TimelineStep(at: date(decided), text: "回答「\(title)」：\(answer)"))
                        last["card-\(row["id"] ?? 0)"] = decided
                    }
                }
            }
        }
        return out
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return HubRun.date(text)
    }
}

// MARK: - 卡片详情

struct CardDetailView: View {
    let card: HubCard
    @StateObject private var settings = AppSettings.shared
    @State private var answering = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title)
                        .font(.title3.weight(.semibold))
                    if let text = card.text, !text.isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("来自规则", value: card.rule ?? "—")
                if let created = HubRun.date(card.createdAt) {
                    LabeledContent("发出", value: StatusStyle.stamp(created))
                }
            }

            if let options = card.options, !options.isEmpty {
                Section("选项") {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            Task { await answer(index) }
                        } label: {
                            HStack {
                                Text(option)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if answering {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .disabled(answering)
                    }
                }
            }

            if let error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("第 \(card.id) 张卡片")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func answer(_ index: Int) async {
        guard settings.hubConfigured else {
            error = "还没配中台"
            return
        }
        answering = true
        defer { answering = false }
        do {
            try await HubClient(baseURL: settings.hubURL, key: settings.hubKey).answer(cardID: card.id, choice: index)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
