import SwiftUI
import Charts

struct HomeView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var state: HubState?
    @State private var error: String?
    @State private var loading = false
    @State private var path = NavigationPath()

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
                ToolbarItem(placement: .topBarTrailing) {
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
            .task {
                await load()
                // 截图/调试用：OPEN_RUN=1351 直接打开某一轮
                if let raw = ProcessInfo.processInfo.environment["OPEN_RUN"], let id = Int(raw),
                   let run = state?.runs.first(where: { $0.id == id }) {
                    path.append(run)
                }
                await poll()
            }
        }
    }

    // MARK: - 现在

    @ViewBuilder
    private func nowSection(_ state: HubState) -> some View {
        let t = state.totals
        Section("现在") {
            HStack(spacing: 0) {
                NowStat(value: t.running, label: "在跑", color: .blue)
                Divider().frame(height: 28)
                NowStat(value: t.queued + t.retrying, label: "排队", color: .orange)
                Divider().frame(height: 28)
                NowStat(value: t.attention, label: "等你", color: t.attention > 0 ? .orange : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
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
            if let options = card.options, !options.isEmpty {
                Text(options.joined(separator: " / "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
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
