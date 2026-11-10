import SwiftUI
import Charts

struct HomeView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var state: HubState?
    @State private var error: String?
    @State private var loading = false
    @State private var path = NavigationPath()
    @State private var ruleBusy = false
    @State private var ruleError: String?
    @State private var confirmPauseAll = false
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
                        HeroCard(state: state, buckets: ChartData.hourly(state.runs))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    nowSection(state)

                    if !state.cards.isEmpty {
                        Section("需要你决定") {
                            ForEach(state.cards) { card in
                                NavigationLink(value: card) { CardRow(card: card) }
                            }
                        }
                    }

                    recentSection(state)
                    agentSection(state)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("首页")
            .navigationDestination(for: HubRun.self) { RunDetailView(run: $0) }
            .navigationDestination(for: HubCard.self) { CardDetailView(card: $0) }
            .refreshable { await load() }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        confirmPauseAll = true
                    } label: {
                        Image(systemName: "pause.circle")
                    }
                    .tint(.orange)
                    .disabled(ruleBusy || ruleCount == 0 || pausedRuleCount == ruleCount)
                    .accessibilityLabel("暂停全部规则")

                    Button {
                        Task { await resumeAllRules() }
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .tint(.green)
                    .disabled(ruleBusy || pausedRuleCount == 0)
                    .accessibilityLabel("恢复全部规则")

                    NavigationLink {
                        StatisticsView(state: state, runs: runs)
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    .disabled(state == nil)
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
                await poll()
            }
        }
    }

    // MARK: - 现在

    @ViewBuilder
    private func nowSection(_ state: HubState) -> some View {
        let t = state.totals
        let active = state.runs
            .filter { ["claimed", "queued", "unknown"].contains($0.state) }
            .sorted { ($0.state == "claimed" ? 0 : 1, -$0.id) < ($1.state == "claimed" ? 0 : 1, -$1.id) }
            .prefix(4)
        let nextBatch = (state.lines ?? [])
            .filter { $0.paused == nil }
            .compactMap { line in HubRun.date(line.next).map { (line.name, $0) } }
            .min { $0.1 < $1.1 }
        Section {
            HStack(spacing: 0) {
                NowStat(value: t.running, label: "在跑", color: .blue)
                Divider().frame(height: 28)
                NowStat(value: t.queued + t.retrying, label: "排队", color: .orange)
                Divider().frame(height: 28)
                NowStat(value: t.attention, label: "等你", color: t.attention > 0 ? .orange : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: active.isEmpty ? 8 : 2, trailing: 16))

            ForEach(Array(active)) { run in
                NavigationLink(value: run) {
                    HStack(spacing: 8) {
                        Text("#\(run.id)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                        Text(run.rule)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        StateBadge(state: run.state)
                    }
                    .padding(.vertical, 5)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }

            if state.runs.filter({ ["claimed", "queued", "unknown"].contains($0.state) }).count > 4 {
                Text("还有 \(state.runs.filter { ["claimed", "queued", "unknown"].contains($0.state) }.count - 4) 轮，进「统计」看全部")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            HStack {
                Text("现在")
                Spacer()
                if let nextBatch {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("下一批 \(countdown(to: nextBatch.1, now: context.date))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                } else if ruleCount > 0 && pausedRuleCount == ruleCount {
                    Text("已全部暂停")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
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
                ForEach(recent) { item in
                    NavigationLink(value: item.run) {
                        RunRowView(run: item.run, repeatCount: item.count)
                    }
                }
            }
        } header: {
            HStack {
                Text("最新处理")
                Spacer()
                Text("近 5 轮").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Agent

    @ViewBuilder
    private func agentSection(_ state: HubState) -> some View {
        Section("Agent") {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日完成")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(state.totals.doneToday)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("时间", bucket.hour, unit: .hour),
                    y: .value("轮次", bucket.count)
                )
                .foregroundStyle(Color.accentColor.opacity(0.75))
                .cornerRadius(2)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 46)

            HStack(spacing: 14) {
                Label("累计 \(state.totals.done)", systemImage: "checkmark.circle")
                Label(money(state.totals.usage.cost), systemImage: "creditcard")
                Label(tokens(state.totals.usage.tokens), systemImage: "text.word.spacing")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func money(_ value: Double) -> String {
        value >= 100 ? String(format: "$%.0f", value) : String(format: "$%.2f", value)
    }

    private func tokens(_ value: Int) -> String {
        value >= 1_000_000 ? String(format: "%.1fM", Double(value) / 1_000_000)
            : value >= 1000 ? "\(value / 1000)k" : "\(value)"
    }
}

// MARK: - 小部件

struct NowStat: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(value > 0 ? color : Color.secondary)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

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
                StateBadge(state: run.state)
            }
            let prose = ChangeParser.prose(run.summary)
            if !prose.isEmpty {
                Text(prose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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

    var body: some View {
        let (text, color): (String, Color) = {
            switch state {
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
