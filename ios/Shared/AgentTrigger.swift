import Foundation

/// 「交给 Agent」：每个大类对应一个轮询会认的触发状态。
///
/// 轮询只认「状态刚变成这个状态」的一次变化，所以如果单子已经在这个状态，
/// 先退回 idle 再转回来，制造一次新的状态变化，才能再触发一轮。
struct AgentTrigger {
    let targetName: String
    let idleName: String?

    static func of(_ category: IssueCategory) -> AgentTrigger? {
        switch category {
        case .bug:
            // 缺陷新建就在「待确认」，重新触发时先经过「处理中」。
            AgentTrigger(targetName: "待确认", idleName: "处理中")
        case .task, .risk:
            AgentTrigger(targetName: "处理中", idleName: "待处理")
        case .req:
            AgentTrigger(targetName: "开发中", idleName: "待处理")
        case .topic:
            // 主题没有工作项类型，也没有工作流。
            nil
        }
    }
}
