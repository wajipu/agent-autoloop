import SwiftUI
import Charts

/// 首页放不下的统计都收在这里：流程、活跃度、构成、花费。
struct StatisticsView: View {
    let state: HubState?
    var runs: [HubRun] = []

    var body: some View {
        List {
            if let state {
                flow(state)
                activity(state)
                composition(state)
                cost(state)
            } else {
                Text("还没有数据").foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.inline)
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
            let today = spending.today?.cost ?? 0
            let week = spending.week?.cost ?? 0
            let bars = [
                Slice(label: "今日", count: Int(today * 100), color: Color.accentColor),
                Slice(label: "近 7 天", count: Int(week * 100), color: Color.accentColor.opacity(0.5)),
            ]
            Section {
                Chart(bars) { bar in
                    BarMark(x: .value("区间", bar.label), y: .value("分", bar.count))
                        .foregroundStyle(bar.color.gradient)
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            Text(money(Double(bar.count) / 100))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                }
                .chartYAxis(.hidden)
                .frame(height: 120)
            } header: {
                Text("花费")
            } footer: {
                Text("今天 \(money(today))，近 7 天 \(money(week))。没有报用量的轮次不计入。")
            }
        }
    }

    private func money(_ value: Double) -> String {
        value >= 100 ? String(format: "$%.0f", value) : String(format: "$%.2f", value)
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
