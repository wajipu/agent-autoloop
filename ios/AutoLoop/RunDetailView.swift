import SwiftUI

// MARK: - GitHub 目标解析（轮次 → 仓库 / PR / Issue）

/// 从事件链接解析 GitHub 目标。轮次详情页用它把「github · prs.opened · #2」
/// 还原成用户认识的东西：哪个仓库的哪个 PR、现在什么状态。
struct GitHubRef: Equatable {
    enum Kind {
        case pull, issue
    }

    let owner: String
    let repo: String
    let kind: Kind
    let number: Int
    let url: URL

    var repoFullName: String { "\(owner)/\(repo)" }

    /// 识别 github.com/{owner}/{repo}/pull/{n} 和 /issues/{n}，其余链接返回 nil。
    static func parse(_ link: String?) -> GitHubRef? {
        guard let link,
              let url = URL(string: link),
              let host = url.host, host.hasSuffix("github.com") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 4 else { return nil }
        let kind: Kind
        switch parts[2] {
        case "pull": kind = .pull
        case "issues": kind = .issue
        default: return nil
        }
        guard let number = Int(parts[3]) else { return nil }
        return GitHubRef(owner: parts[0], repo: parts[1], kind: kind, number: number, url: url)
    }
}

/// 把内核事件类型翻译成用户语言，不再暴露 prs.opened 这类机器码。
func humanEventName(source: String, type: String, ref: GitHubRef?) -> String {
    switch (source, type) {
    case ("github", "prs.opened"):
        return ref.map { "\($0.repo) PR #\($0.number) 有更新，自动重审" } ?? "有 PR 更新，自动重审"
    case ("github", "prs.fixrequested"):
        return "评审不通过，等修复"
    case ("github", "issues.opened"):
        return "有新 Issue，等处理"
    case ("github", "issues.labeled"):
        return "有 Issue 被打上交付标记"
    case ("local", "task.submitted"):
        return "手动下发的任务"
    case ("local", "upstream.updated"):
        return "官方中台有新版本，等拍板"
    case ("app", _):
        return "手机上发起了操作"
    default:
        return source == "github" ? type : "定时触发"
    }
}

// MARK: - 轮次详情

/// 页面结构按用户关心的顺序组织：
/// 结论 → 这个轮次在处理 GitHub 上哪个东西（实时状态）→ 改了哪些提交 → 经过 → 附注。
/// 中台内部概念（规则版本、单元领取、事件类型码）一律不出现。
struct RunDetailView: View {
    let run: HubRun
    @StateObject private var settings = AppSettings.shared
    @State private var steps: [TimelineStep]?
    @State private var web: WebSheet?
    @State private var error: String?
    @State private var pull: GitHubClient.PullLite?
    @State private var pullFailed = false

    /// 这一轮处理的 GitHub 目标（从触发事件链接解析，通常只有一个）。
    private var ref: GitHubRef? {
        (run.events ?? []).compactMap { GitHubRef.parse($0.link) }.first
    }

    var body: some View {
        List {
            headerSection
            if let ref { githubSection(ref) }
            changesSection
            journeySection
            footerSection
            if let message = run.error, !message.isEmpty {
                Section("错误") {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(run.rule)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $web) { web in
            SafariSheet(url: web.url)
        }
        .task {
            await load()
            await loadPull()
        }
    }

    // MARK: 头部：结论

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    StateBadge(state: run.state)
                    if run.attempts > 1 {
                        Text("重试过 \(run.attempts) 次")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let created = run.created, let finished = run.finished {
                        Text("用时 " + duration(from: created, to: finished))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                let prose = ChangeParser.prose(run.summary)
                if !prose.isEmpty {
                    Text(prose)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: GitHub 目标 + 实时状态

    private func githubSection(_ ref: GitHubRef) -> some View {
        Section(ref.kind == .pull ? "Pull Request" : "Issue") {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    web = WebSheet(url: ref.url)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(ref.repoFullName) #\(ref.number)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if ref.kind == .pull {
                    if let pull {
                        Text(pull.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label(pull.stateLabel, systemImage: pull.merged ? "arrow.triangle.merge"
                                : (pull.state == "open" ? "circle" : "xmark.circle"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(pull.merged ? Color.purple : (pull.state == "open" ? Color.green : Color.red))
                    } else if pullFailed {
                        Text("读不到 PR 当前状态")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: 改动

    private var changesSection: some View {
        Group {
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
        }
    }

    // MARK: 经过（人话时间线）

    private var journeySection: some View {
        Section("经过") {
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

    // MARK: 附注（调试信息降级到底部）

    private var footerSection: some View {
        Group {
            if run.agent != nil || run.link != nil || run.session != nil {
                Section {
                    if let agent = run.agent {
                        LabeledContent("Agent", value: agent)
                    }
                    if let created = run.created {
                        LabeledContent("开始", value: StatusStyle.stamp(created))
                    }
                    if let link = run.link, !link.isEmpty, link.hasPrefix("http"), let url = URL(string: link) {
                        Button {
                            web = WebSheet(url: url)
                        } label: {
                            Label("看这轮的 agent 会话", systemImage: "safari")
                        }
                    }
                }
            }
        }
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

    /// 拉 PR 当前状态（开放/已合并/已关闭），失败就静默降级，不影响页面其他部分。
    private func loadPull() async {
        guard settings.configured, let ref, ref.kind == .pull else { return }
        let github = GitHubClient(owner: settings.owner, repo: settings.repo, token: settings.token)
        do {
            pull = try await github.pullInfo(fullRepo: ref.repoFullName, number: ref.number)
        } catch {
            pullFailed = true
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

/// 看起来像工单号：ABC-123 / MGMF-40。
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

/// 把中台的 why 流水整理成用户能看懂的「经过」：
/// 触发（事件翻译成人话）→ 开始处理 → 拍板/重试 → 完成。
/// 规则版本号、接单程序领取这类内部动作不展示。
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

            for change in fact["changes"] as? [[String: Any]] ?? [] {
                let table = change["table"] as? String ?? ""
                guard let row = change["row"] as? [String: Any] else { continue }

                if table == "runs", (row["id"] as? Int) == runID {
                    let attempts = String(describing: row["attempts"] ?? 0)
                    if (row["state"] as? String) == "queued", last["attempts"] != nil, last["attempts"] != attempts {
                        let message = row["error"] as? String ?? ""
                        out.append(TimelineStep(at: at, text: "有一次没跑成：\(message)"))
                    }
                    if (row["state"] as? String) == "queued" { last["attempts"] = attempts }
                    if let finished = row["finished_at"] as? String, last["finished"] != finished {
                        last["finished"] = finished
                        // 结论已经在页面顶部展示，时间线只标记完成时间。
                        out.append(TimelineStep(at: date(finished), text: "完成"))
                    }
                }

                if table == "events", let eventID = row["id"] as? Int, !seenEvents.contains(eventID) {
                    seenEvents.add(eventID)
                    let source = row["source"] as? String ?? ""
                    let kind = row["type"] as? String ?? ""
                    let link = row["link"] as? String
                    let ref = GitHubRef.parse(link)
                    out.append(TimelineStep(at: date(row["received_at"]), text: "触发：\(humanEventName(source: source, type: kind, ref: ref))"))
                }

                if table == "cards", (row["run_id"] as? Int) == runID || (row["answer_event"] as? Int) != nil {
                    if let decided = row["decided_at"] as? String, last["card-\(row["id"] ?? 0)"] != decided {
                        let title = row["title"] as? String ?? ""
                        let answer = row["answer"] as? String ?? ""
                        out.append(TimelineStep(at: date(decided), text: "你拍板「\(title)」：\(answer)"))
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
                        Label("查看这一轮的处理过程", systemImage: "clock.arrow.circlepath")
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
        .navigationTitle("待拍板")
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
                let github = GitHubClient(owner: settings.owner, repo: settings.repo, token: settings.token)
                relatedItem = try? await github.findWorkitem(serialNumber: serial)
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
