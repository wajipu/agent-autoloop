import SwiftUI
import Charts

private enum HomeDestination: Hashable {
    case statistics
}

struct HomeView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var state: HubState?
    @State private var error: String?
    @State private var loading = false
    @State private var path = NavigationPath()
    @State private var ruleBusy = false
    @State private var ruleError: String?
    @State private var confirmPauseAll = false
    @State private var recentExpanded = false
    @ObservedObject private var deepLink = DeepLink.shared

    /// 已经退役的规则名：历史轮次还留在中台日志里，首页不再展示。
    private static let retiredRules: Set<String> = ["盯 Linear", "处理 Linear issue"]

    private var runs: [HubRun] {
        (state?.runs ?? []).filter { !Self.retiredRules.contains($0.rule) }
    }
    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let state {
                    Section {
                        Button {
                            path.append(HomeDestination.statistics)
                        } label: {
                            HeroCard(state: state, buckets: ChartData.hourly(state.runs.filter { $0.state == "done" }))
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }


                    if !state.cards.isEmpty {
                        Section("待你处理 · \(state.cards.count)") {
                            ForEach(state.cards) { card in
                                NavigationLink(value: card) { CardRow(card: card) }
                            }
                        }
                    }

                    nowSection(state)


                    recentSection(state)
                    agentSection(state)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(16)
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HubRun.self) { RunDetailView(run: $0).id($0.id) }
            .navigationDestination(for: HubCard.self) { CardDetailView(card: $0) }
            .navigationDestination(for: HomeDestination.self) { _ in
                StatisticsView(state: state, runs: runs)
            }
            .refreshable { await load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink {
                            StatisticsView(state: state, runs: runs)
                        } label: {
                            Label("查看统计", systemImage: "chart.bar.xaxis")
                        }
                        .disabled(state == nil)
                        Divider()
                        Button {
                            confirmPauseAll = true
                        } label: {
                            Label("暂停全部规则", systemImage: "pause.circle")
                        }
                        .disabled(ruleBusy || ruleCount == 0 || pausedRuleCount == ruleCount)
                        Button {
                            Task { await resumeAllRules() }
                        } label: {
                            Label("恢复全部规则", systemImage: "play.circle")
                        }
                        .disabled(ruleBusy || pausedRuleCount == 0)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("首页操作")
                }
            }
            .overlay {
                if !settings.hubConfigured {
                    ContentUnavailableView("还没配中台",
                                           systemImage: "antenna.radiowaves.left.and.right",
                                           description: Text("去「设置」填中台地址和本人密钥"))
                } else if state == nil && error == nil {
                    ProgressView("读取中…")
                } else if let error, state == nil {
                    ContentUnavailableView("连不上中台", systemImage: "wifi.exclamationmark", description: Text(error))
                }
            }
            .onChange(of: deepLink.cardID) { openPendingCard() }
            .confirmationDialog("暂停全部规则？", isPresented: $confirmPauseAll, titleVisibility: .visible) {
                Button("暂停全部", role: .destructive) {
                    Task { await pauseAllRules() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("暂停后不再派发新任务，已排队的任务会保留；恢复后不会补跑暂停期间错过的触发。")
            }
            .alert("规则操作失败", isPresented: Binding(
                get: { ruleError != nil },
                set: { if !$0 { ruleError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(ruleError ?? "")
            }
            .task {
                await load()
                // 截图/调试用：OPEN_RUN=1351 直接打开某一轮
                if let raw = ProcessInfo.processInfo.environment["OPEN_RUN"], let id = Int(raw),
                   let run = state?.runs.first(where: { $0.id == id }) {
                    path.append(run)
                }
                openPendingCard()
                openPendingRun()
                await poll()
            }
        }
        .onChange(of: deepLink.run) { openPendingRun() }
    }

    // MARK: - 现在

    @ViewBuilder
    private func nowSection(_ state: HubState) -> some View {
        let t = state.totals
        let allActive = state.runs
            .filter { ["claimed", "queued", "unknown"].contains($0.state) }
            .sorted { ($0.state == "claimed" ? 0 : 1, -$0.id) < ($1.state == "claimed" ? 0 : 1, -$1.id) }
        let active = Array(allActive.prefix(4))
        let nextBatch = (state.lines ?? [])
            .filter { $0.paused == nil }
            .compactMap { line in HubRun.date(line.next).map { (line.name, $0) } }
            .min { $0.1 < $1.1 }
        Section {
            if !allActive.isEmpty {
                HStack(spacing: 14) {
                    Label("执行 \(t.running)", systemImage: "play.circle.fill")
                        .foregroundStyle(.blue)
                    Label("排队 \(t.queued)", systemImage: "clock")
                        .foregroundStyle(.secondary)
                    if t.unknown > 0 {
                        Label("未知 \(t.unknown)", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.subheadline.weight(.medium))
                .padding(.vertical, 4)
            } else {
                Label("暂无执行或排队任务", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            if let nextBatch {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("下次定时执行")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(countdown(to: nextBatch.1, now: context.date))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                    }
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16))
            } else if ruleCount > 0 && pausedRuleCount == ruleCount {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle")
                        .font(.footnote)
                    Text("全部规则已暂停，不派发新任务")
                        .font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(.orange)
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16))
            }

            ForEach(active) { run in
                NavigationLink(value: run) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(run.rule)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            Text("#\(run.id)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            StateBadge(state: run.state, stopping: run.state == "claimed" && run.stopping == true)
                        }
                        if run.state == "claimed" {
                            HStack(spacing: 7) {
                                ProgressView().controlSize(.small)
                                Text(run.progress?.first(where: { $0.status == "running" })?.title ?? "Agent 正在执行")
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if let steps = run.progress, !steps.isEmpty {
                                    Text("\(steps.filter { $0.status == "completed" }.count)/\(steps.count)")
                                        .monospacedDigit()
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else if run.state == "unknown" {
                            Text("请检查接单程序连接")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if allActive.count > 4 {
                NavigationLink {
                    StatisticsView(state: state, runs: runs)
                } label: {
                    Text("查看全部 \(allActive.count) 个任务")
                        .font(.subheadline)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }
        } header: {
            Text("当前任务")
        }
    }

    /// 距离下一批还有多久；到了就显示“即将执行”，等下一次轮询刷新。
    private func countdown(to date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded()))
        if seconds == 0 { return "即将执行" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, rest) }
        return String(format: "%02d:%02d", minutes, rest)
    }

    // MARK: - 规则

    private var ruleCount: Int { state?.lines?.count ?? 0 }
    private var pausedRuleCount: Int { state?.lines?.filter { $0.paused != nil }.count ?? 0 }

    private func pauseAllRules() async {
        guard let lines = state?.lines else { return }
        let targets = lines.filter { $0.paused == nil }
        guard !targets.isEmpty else { return }
        ruleBusy = true
        defer { ruleBusy = false }
        let client = HubClient(baseURL: settings.hubURL, key: settings.hubKey)
        do {
            for line in targets {
                _ = try await client.controlRule(name: line.name, action: .pause)
            }
        } catch {
            ruleError = error.localizedDescription
        }
        await load()
    }

    private func resumeAllRules() async {
        guard let lines = state?.lines else { return }
        let targets = lines.filter { $0.paused != nil }
        guard !targets.isEmpty else { return }
        ruleBusy = true
        defer { ruleBusy = false }
        let client = HubClient(baseURL: settings.hubURL, key: settings.hubKey)
        do {
            for line in targets {
                _ = try await client.controlRule(name: line.name, action: .resume)
            }
        } catch {
            ruleError = error.localizedDescription
        }
        await load()
    }

    // MARK: - 最新处理

    @ViewBuilder
    private func recentSection(_ state: HubState) -> some View {
        let recent = Array(RecentRun.collapse(runs.filter { ["done", "cancelled", "nothing"].contains($0.state) }).prefix(5))
        Section {
            if recent.isEmpty {
                Text("还没有跑完的轮次").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(recent.prefix(recentExpanded ? 5 : 3))) { item in
                    NavigationLink(value: item.run) {
                        RunRowView(run: item.run, repeatCount: item.count)
                    }
                }
                if recent.count > 3 {
                    Button(recentExpanded ? "收起记录" : "展开最近 \(recent.count) 条记录") {
                        recentExpanded.toggle()
                    }
                    .font(.subheadline)
                }
            }
        } header: {
            Text("最近处理")
        }
    }

    // MARK: - Agent

    @ViewBuilder
    private func agentSection(_ state: HubState) -> some View {
        Section {
            DisclosureGroup {
                if state.agents.isEmpty {
                    Text("还没有接单的电脑").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(state.agents) { agent in
                    HStack {
                        Circle()
                            .fill(agent.online ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name).font(.subheadline)
                            Text("\(agent.worker) · \(agent.use)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(agent.online ? "在线" : "离线")
                            .font(.caption2)
                            .foregroundStyle(agent.online ? .green : .secondary)
                    }
                }
            } label: {
                HStack {
                    Label("Agent", systemImage: "desktopcomputer")
                    Spacer()
                    Text("\(state.agents.filter { $0.online }.count)/\(state.agents.count) 在线")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 数据

    private func poll() async {
        guard settings.hubConfigured else { return }
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: .seconds(15))
        }
    }

    private func openPendingRun() {
        guard let run = deepLink.run else { return }
        deepLink.run = nil
        path = NavigationPath()
        path.append(run)
    }

    private func openPendingCard() {
        guard let id = deepLink.cardID,
              let card = state?.cards.first(where: { $0.id == id }) else { return }
        deepLink.cardID = nil
        path.append(card)
    }

    private func load() async {
        guard settings.hubConfigured else { return }
        loading = true
        defer { loading = false }
        let client = HubClient(baseURL: settings.hubURL, key: settings.hubKey)
        do {
            state = try await client.state()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 头号指标

struct HeroCard: View {
    let state: HubState
    let buckets: [HourBucket]
    @ScaledMetric(relativeTo: .largeTitle) private var completionSize = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日完成")
                    .font(.headline)
                Spacer()
                Label("统计", systemImage: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 24) {
                    completedCount
                    trend.frame(minWidth: 130)
                }
                VStack(alignment: .leading, spacing: 12) {
                    completedCount
                    trend
                }
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    metric("累计完成", value: "\(state.totals.done) 轮")
                    metric("今日 Token", value: state.spending?.today.map { tokens($0.tokens) } ?? "—")
                    metric("今日估算", value: state.spending?.today?.estimateText ?? "未估算")
                }
                VStack(alignment: .leading, spacing: 12) {
                    metric("累计完成", value: "\(state.totals.done) 轮")
                    metric("今日 Token", value: state.spending?.today.map { tokens($0.tokens) } ?? "—")
                    metric("今日估算", value: state.spending?.today?.estimateText ?? "未估算")
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    onlineStatus
                    Spacer(minLength: 12)
                    Text("官方价估算 · 仅含已知用量")
                }
                VStack(alignment: .leading, spacing: 4) {
                    onlineStatus
                    Text("官方价估算 · 仅含已知用量")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var onlineStatus: some View {
        Label("\(state.agents.filter { $0.online }.count)/\(state.agents.count) 在线", systemImage: "desktopcomputer")
    }

    private var completedCount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(state.totals.doneToday)")
                .font(.system(size: completionSize, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
                .monospacedDigit()
            Text("轮")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("12 小时完成 · 近 60 轮")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Chart(buckets) { bucket in
                BarMark(x: .value("时间", bucket.hour, unit: .hour), y: .value("完成轮次", bucket.count))
                    .foregroundStyle(Color.green.opacity(0.75))
                    .cornerRadius(2)
            }
            .chartYScale(domain: 0...max(1, buckets.map(\.count).max() ?? 0))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Self.hourFormatter.string(from: date)).font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 48)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "H时"
        return formatter
    }()

    private func tokens(_ value: Int) -> String {
        value >= 1_000_000 ? String(format: "%.1fM", Double(value) / 1_000_000)
            : value >= 1000 ? "\(value / 1000)k" : "\(value)"
    }
}

// MARK: - 小部件

struct CardRow: View {
    let card: HubCard
    @StateObject private var settings = AppSettings.shared
    @State private var trace: CardTrace?
    @State private var relatedItem: Workitem?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: card.kind == "ask" ? "questionmark.bubble.fill" : "bell.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(card.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }
            if let text = card.text, !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let serial = trace?.serial ?? card.lane, isWorkitemSerial(serial) {
                Label([serial, relatedItem?.subject].compactMap { $0 }.joined(separator: " · "), systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let options = card.options, !options.isEmpty {
                Text(options.joined(separator: " / "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .task(id: card.id) {
            guard settings.hubConfigured else { return }
            let client = HubClient(baseURL: settings.hubURL, key: settings.hubKey)
            trace = try? await CardTrace.lookup(card: card, page: { try await client.state(before: $0) },
                                               facts: { try await client.why(runID: $0) })
            if settings.configured, let serial = trace?.serial ?? card.lane, isWorkitemSerial(serial) {
                let yunxiao = YunxiaoClient(orgId: settings.orgId, projectId: settings.projectId, token: settings.token)
                relatedItem = try? await yunxiao.findWorkitem(serialNumber: serial)
            }
        }
    }
}

/// 把连着跑出同样结果的轮次合并成一条，别让定时轮询刷屏。
struct RecentRun: Identifiable {
    let id: Int
    let run: HubRun
    let count: Int

    static func collapse(_ runs: [HubRun]) -> [RecentRun] {
        var out: [RecentRun] = []
        for run in runs {
            let same = out.last.map {
                $0.run.rule == run.rule && ($0.run.summary ?? "") == (run.summary ?? "")
            } ?? false
            if same, let last = out.last {
                out[out.count - 1] = RecentRun(id: last.id, run: last.run, count: last.count + 1)
            } else {
                out.append(RecentRun(id: run.id, run: run, count: 1))
            }
        }
        return out
    }
}

struct RunRowView: View {
    let run: HubRun
    var repeatCount: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("#\(run.id)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                Text(run.rule)
                    .font(.subheadline)
                    .lineLimit(1)
                if repeatCount > 1 {
                    Text("×\(repeatCount)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Spacer()
                StateBadge(state: run.state, stopping: run.state == "claimed" && run.stopping == true)
            }
            let prose = ChangeParser.prose(run.summary)
            if !prose.isEmpty {
                Text(prose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if run.state == "claimed" {
                RunProgressView(run: run, showSteps: false)
            }
            HStack(spacing: 8) {
                if let finished = run.finished {
                    Text(StatusStyle.relative(finished))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                let changes = ChangeParser.parse(run.summary)
                if !changes.isEmpty {
                    Label("\(changes.count) 处改动", systemImage: "hammer")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct StateBadge: View {
    let state: String
    var stopping = false

    var body: some View {
        let (text, color): (String, Color) = {
            if stopping && ["claimed", "queued", "unknown"].contains(state) { return ("停止中", .orange) }
            return switch state {
            case "claimed": ("在跑", .blue)
            case "queued": ("排队", .orange)
            case "unknown": ("未知", .orange)
            case "done": ("完成", .green)
            case "cancelled": ("已停止", .secondary)
            case "nothing": ("无事", .secondary)
            default: (state, .secondary)
            }
        }()
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - 图表数据

enum ChartData {
    static func hourly(_ runs: [HubRun]) -> [HourBucket] {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(bySetting: .minute, value: 0, of: now) ?? now
        let hours: [Date] = (0..<12).reversed().compactMap {
            calendar.date(byAdding: .hour, value: -$0, to: start)
        }
        return hours.map { hour in
            let next = calendar.date(byAdding: .hour, value: 1, to: hour) ?? hour
            let count = runs.filter { run in
                guard let end = run.finished else { return false }
                return end >= hour && end < next
            }.count
            return HourBucket(hour: hour, count: count)
        }
    }
}

struct HourBucket: Identifiable {
    var id: Date { hour }
    let hour: Date
    let count: Int
}

struct RunProgressView: View {
    let run: HubRun
    var showSteps = false

    private var steps: [HubProgressStep] { run.progress ?? [] }
    private var completed: Int { steps.filter { $0.status == "completed" }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if run.state == "claimed" {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    if let current = steps.first(where: { $0.status == "running" }) {
                        Text(current.title)
                            .font(.caption)
                            .lineLimit(2)
                    } else {
                        Text("Agent 正在执行")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
                if !steps.isEmpty {
                    Text("Agent 计划 · 已完成 \(completed)/\(steps.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if showSteps {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 8) {
                        if step.status == "running" && run.state == "claimed" {
                            ProgressView().controlSize(.small)
                        } else {
                            let completed = step.status == "completed"
                            Image(systemName: completed ? "checkmark.circle.fill" : (step.status == "running" ? "play.circle" : "circle"))
                                .foregroundStyle(completed ? .green : .secondary)
                                .frame(width: 12)
                        }
                        Text(step.title)
                            .font(.subheadline)
                            .foregroundStyle(step.status == "completed" ? .secondary : .primary)
                    }
                }
            }
        }
        .padding(.top, 2)
    }
}
