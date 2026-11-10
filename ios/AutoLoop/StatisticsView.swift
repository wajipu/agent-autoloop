import SwiftUI
import Charts

/// 首页放不下的统计都收在这里：流程、活跃度、构成、花费。
struct StatisticsView: View {
    let state: HubState?
    var runs: [HubRun] = []
    @State private var latestState: HubState?
    @State private var refreshError: String?
    @State private var refreshing = false
    @StateObject private var settings = AppSettings.shared

    private var displayedState: HubState? { latestState ?? state }

    var body: some View {
        List {
            if !settings.hubConfigured {
                ContentUnavailableView("还没配中台", systemImage: "antenna.radiowaves.left.and.right",
                                       description: Text("去「设置」填中台地址和本人密钥"))
            } else if let state = displayedState {
                if let refreshError {
                    Section {
                        Label(refreshError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                currentRuns(state)
                flow(state)
                activity(state)
                composition(state)
                cost(state)
            } else {
                if let refreshError {
                    ContentUnavailableView("读不到中台状态", systemImage: "wifi.exclamationmark", description: Text(refreshError))
                } else {
                    ProgressView("读取中…")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    @ViewBuilder
    private func currentRuns(_ state: HubState) -> some View {
        let active = state.runs.filter { ["claimed", "unknown", "queued"].contains($0.state) }
        if active.isEmpty {
            Section("当前轮次") {
                Text("没有正在执行或排队的轮次").font(.subheadline).foregroundStyle(.secondary)
            }
        } else {
            if active.contains(where: { $0.state == "claimed" }) {
                Section("在跑 · \(active.filter { $0.state == "claimed" }.count)") {
                    ForEach(active.filter { $0.state == "claimed" }) { run in
                        NavigationLink { RunDetailView(run: run) } label: { RunRowView(run: run) }
                    }
                }
            }
            if active.contains(where: { $0.state == "unknown" }) {
                Section("状态未知 · \(active.filter { $0.state == "unknown" }.count)") {
                    ForEach(active.filter { $0.state == "unknown" }) { run in
                        NavigationLink { RunDetailView(run: run) } label: { RunRowView(run: run) }
                    }
                }
            }
            if active.contains(where: { $0.state == "queued" }) {
                Section("排队 · \(active.filter { $0.state == "queued" }.count)") {
                    ForEach(active.filter { $0.state == "queued" }) { run in
                        NavigationLink { RunDetailView(run: run) } label: { RunRowView(run: run) }
                    }
                }
            }
        }
    }

    private func refresh() async {
        guard settings.hubConfigured else {
            refreshError = "去「设置」填中台地址和本人密钥"
            return
        }
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            latestState = try await HubClient(baseURL: settings.hubURL, key: settings.hubKey).state()
            refreshError = nil
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            refreshError = error.localizedDescription
        }
    }

    // MARK: 流程

    @ViewBuilder
    private func flow(_ state: HubState) -> some View {
        let t = state.totals
        let stages = [
            FlowStage(label: "拍板", count: t.attention, color: .orange),
            FlowStage(label: "排队", count: t.queued + t.retrying, color: .orange),
            FlowStage(label: "在跑", count: t.running, color: .blue),
            FlowStage(label: "今日完成", count: t.doneToday, color: .green),
        ]
        Section {
            Chart(stages) { stage in
                BarMark(x: .value("数量", stage.count), y: .value("阶段", stage.label))
                    .foregroundStyle(stage.color.gradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(stage.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading) { _ in
                    AxisValueLabel().font(.caption)
                }
            }
            .frame(height: 118)
        } header: {
            Text("流程")
        } footer: {
            Text("事件进来 → 规则派活 → 排队 → 接单程序领走在跑 → 完成；需要你决定时会停在「拍板」。")
        }
    }

    // MARK: 活跃度

    @ViewBuilder
    private func activity(_ state: HubState) -> some View {
        let buckets = ChartData.hourly(runs.isEmpty ? state.runs : runs)
        Section {
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("时间", bucket.hour, unit: .hour),
                    y: .value("轮次", bucket.count)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(Self.hourLabel(date)).font(.caption2)
                        }
                    }
                    AxisGridLine().foregroundStyle(.clear)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 120)
        } header: {
            Text("最近 12 小时")
        } footer: {
            Text("按完成时间统计，取自中台返回的最近 60 轮。")
        }
    }

    // MARK: 构成

    @ViewBuilder
    private func composition(_ state: HubState) -> some View {
        let t = state.totals
        let slices = [
            Slice(label: "完成", count: t.done, color: .green),
            Slice(label: "无事", count: t.nothing, color: .gray),
            Slice(label: "未知", count: t.unknown, color: .orange),
            Slice(label: "在跑", count: t.running, color: .blue),
            Slice(label: "排队", count: t.queued + t.retrying, color: .orange),
        ].filter { $0.count > 0 }

        Section("累计构成") {
            if slices.isEmpty {
                Text("还没有轮次").foregroundStyle(.secondary)
            } else {
                Chart(slices) { slice in
                    SectorMark(angle: .value("轮次", slice.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(slice.color.gradient)
                        .cornerRadius(3)
                }
                .chartLegend(.hidden)
                .frame(height: 150)
                .overlay {
                    VStack(spacing: 1) {
                        Text("\(t.done + t.nothing + t.unknown + t.running + t.queued + t.retrying)")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("轮次").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    ForEach(slices) { slice in
                        HStack(spacing: 4) {
                            Circle().fill(slice.color).frame(width: 6, height: 6)
                            Text(slice.label).font(.caption2).foregroundStyle(.secondary)
                            Text("\(slice.count)").font(.caption2.weight(.medium)).monospacedDigit()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: 花费

    @ViewBuilder
    private func cost(_ state: HubState) -> some View {
        if let spending = state.spending {
            Section {
                ForEach([("今日", spending.today), ("近 7 天", spending.week)], id: \.0) { title, amount in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(title)
                            Spacer()
                            Text(amount?.estimateText ?? "未估算")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        Text(amount?.estimateCoverage ?? "估算情况未知")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("参考费用（估算）")
            } footer: {
                Text("Codex 按官方 Standard API 单价估算，分别计算普通输入、缓存读取、30 分钟缓存写入及输出；超过 272K 的请求按长上下文价计算。不含工具调用费用、加速及地域附加费。已有程序上报金额作为参考费用保留；不是实际账单。")
            }
        }
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "H时"
        return formatter
    }()

    private static func hourLabel(_ date: Date) -> String { hourFormatter.string(from: date) }
}

struct FlowStage: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
    let color: Color
}

struct Slice: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
    let color: Color
}
