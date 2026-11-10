import SwiftUI

// MARK: - 轮次详情

struct RunDetailView: View {
    @State private var run: HubRun
    @StateObject private var settings = AppSettings.shared
    @State private var steps: [TimelineStep]?
    @State private var web: WebSheet?
    @State private var error: String?
    @State private var statusError: String?
    @State private var operationError: String?
    @State private var operationMessage: String?
    @State private var statusLoaded = false
    @State private var canActOnLatest = false
    @State private var operationBusy = false
    @State private var confirmCancel = false

    init(run: HubRun) {
        _run = State(initialValue: run)
    }

    private var isActive: Bool { ["queued", "claimed", "unknown"].contains(run.state) }
    private var canRequestCancel: Bool {
        statusLoaded && canActOnLatest && !operationBusy && run.stopping != true && ["queued", "claimed"].contains(run.state)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("#\(run.id)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        StateBadge(state: run.state, stopping: run.state == "claimed" && run.stopping == true)
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

            if let operationMessage {
                Section {
                    Label(operationMessage, systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            if run.state == "claimed" || !(run.progress ?? []).isEmpty {
                Section("Agent执行步骤") {
                    RunProgressView(run: run, showSteps: true)
                }
            }

            if isActive {
                Section("任务操作") {
                    if statusLoaded && !canActOnLatest, let statusError {
                        Text(statusError).font(.footnote).foregroundStyle(.orange)
                    } else if run.state == "unknown" {
                        Label("状态未知，请检查接单程序连接。", systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else if run.state == "claimed" && run.stopping == true {
                        Label("停止请求已提交，等待接单程序确认。", systemImage: "stop.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else if canRequestCancel {
                        Button(run.state == "queued" ? "取消排队任务" : "请求停止这一轮", role: .destructive) {
                            confirmCancel = true
                        }
                        .disabled(operationBusy)
                    } else if let statusError {
                        Text(statusError).font(.footnote).foregroundStyle(.orange)
                    } else {
                        HStack { ProgressView(); Text("正在确认最新状态…").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
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
                        if isWorkitemSerial(subject) {
                            NavigationLink {
                                IssueDetailView(item: Workitem.preview(serialNumber: subject, subject: run.summary ?? ""))
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "target")
                                    Text(subject).font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text("查看工单").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        } else {
                            Label(subject, systemImage: "target")
                                .font(.subheadline.weight(.medium))
                                .textSelection(.enabled)
                        }
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
                            if let link = event.link, let url = URL(string: link), url.scheme?.hasPrefix("http") == true {
                                Button {
                                    web = WebSheet(url: url)
                                } label: {
                                    Label("打开来源", systemImage: "safari").font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let link = run.link, !link.isEmpty {
                Section("会话") {
                    if let url = URL(string: link), link.hasPrefix("http") {
                        Button {
                            web = WebSheet(url: url)
                        } label: {
                            Label("查看这一轮的会话", systemImage: "safari")
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
        .refreshable { await load() }
        .navigationTitle("第 \(run.id) 轮")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $web) { web in
            SafariSheet(url: web.url)
        }
        .confirmationDialog(run.state == "queued" ? "取消这个排队任务？" : "请求停止这一轮？",
                            isPresented: $confirmCancel, titleVisibility: .visible) {
            Button(run.state == "queued" ? "取消排队" : "请求停止", role: .destructive) {
                Task { await cancelRun() }
            }
            Button("返回", role: .cancel) {}
        }
        .alert("操作失败", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(operationError ?? "")
        }
        .task {
            await load()
            while !Task.isCancelled && isActive {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refreshRunState(using: HubClient(baseURL: settings.hubURL, key: settings.hubKey))
            }
        }
    }

    private func load() async {
        guard settings.hubConfigured else {
            error = "还没配中台"
            statusError = "去「设置」填中台地址和本人密钥"
            statusLoaded = true
            canActOnLatest = false
            return
        }
        let client = HubClient(baseURL: settings.hubURL, key: settings.hubKey)
        await refreshRunState(using: client)
        do {
            let facts = try await client.why(runID: run.id)
            steps = Timeline.build(facts: facts, runID: run.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshRunState(using client: HubClient) async {
        do {
            let latest = try await client.state()
            if let found = latest.runs.first(where: { $0.id == run.id }) {
                run = found
                canActOnLatest = true
                statusError = nil
            } else {
                canActOnLatest = false
                statusError = "当前状态列表里没有这一轮，请刷新后再操作。"
            }
            statusLoaded = true
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            canActOnLatest = false
            statusLoaded = true
            statusError = "无法确认最新状态：\(error.localizedDescription)"
        }
    }

    private func cancelRun() async {
        guard !operationBusy else { return }
        operationBusy = true
        defer { operationBusy = false }
        operationMessage = nil
        operationError = nil
        let client = HubClient(baseURL: settings.hubURL, key: settings.hubKey)
        await refreshRunState(using: client)
        guard canActOnLatest, ["queued", "claimed"].contains(run.state), run.stopping != true else { return }
        do {
            try await client.cancelRun(id: run.id)
            operationMessage = "请求已提交。"
            await refreshRunState(using: client)
        } catch {
            operationError = error.localizedDescription
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

/// 看起来像云效工单号：ABC-123 / MGMF-40。
func isWorkitemSerial(_ text: String) -> Bool {
    let pattern = "^[A-Z]{2,8}-[0-9]+$"
    return text.range(of: pattern, options: .regularExpression) != nil
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
    @State private var trace: CardTrace?
    @State private var traceLoading = true
    @State private var traceError = false
    @State private var relatedItem: Workitem?
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

            Section("来源") {
                if let serial = trace?.serial ?? card.lane, isWorkitemSerial(serial) {
                    NavigationLink {
                        IssueDetailView(item: relatedItem ?? Workitem.preview(serialNumber: serial, subject: ""))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(serial, systemImage: "doc.text")
                            if let subject = relatedItem?.subject, !subject.isEmpty {
                                Text(subject).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let trace {
                    NavigationLink {
                        RunDetailView(run: trace.run)
                    } label: {
                        Label("查看第 \(trace.run.id) 轮", systemImage: "clock.arrow.circlepath")
                    }
                } else if traceLoading {
                    ProgressView("查找来源…")
                } else if traceError {
                    Text("来源暂时读不到，请稍后重试")
                        .foregroundStyle(.secondary)
                } else if card.lane == nil || !isWorkitemSerial(card.lane ?? "") {
                    Text("没有找到关联的工作项或轮次")
                        .foregroundStyle(.secondary)
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
        .task {
            defer { traceLoading = false }
            guard settings.hubConfigured else { traceError = true; return }
            let client = HubClient(baseURL: settings.hubURL, key: settings.hubKey)
            do {
                trace = try await CardTrace.lookup(card: card, page: { try await client.state(before: $0) },
                                                   facts: { try await client.why(runID: $0) })
            } catch {
                traceError = true
            }
            if settings.configured, let serial = trace?.serial ?? card.lane, isWorkitemSerial(serial) {
                let yunxiao = YunxiaoClient(orgId: settings.orgId, projectId: settings.projectId, token: settings.token)
                relatedItem = try? await yunxiao.findWorkitem(serialNumber: serial)
            }
        }
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
