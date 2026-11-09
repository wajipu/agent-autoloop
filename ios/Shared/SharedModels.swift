import Foundation

/// 工作项大类。App 和分享扩展共用。
enum IssueCategory: String, CaseIterable, Identifiable {
    case bug = "Bug"
    case task = "Task"
    case req = "Req"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .bug: "缺陷"
        case .task: "任务"
        case .req: "需求"
        }
    }
}

/// 主 App 写、分享扩展读的配置（App Group 里），避免扩展拿不到钥匙串。
enum SharedConfig {
    private static let suite = "group.com.wajipu.autoloop"

    static var defaults: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }

    static var token: String {
        get { defaults.string(forKey: "yunxiao.token") ?? "" }
        set { defaults.set(newValue, forKey: "yunxiao.token") }
    }
    static var orgId: String {
        get { defaults.string(forKey: "yunxiao.org") ?? "" }
        set { defaults.set(newValue, forKey: "yunxiao.org") }
    }
    static var projectId: String {
        get { defaults.string(forKey: "yunxiao.project") ?? "" }
        set { defaults.set(newValue, forKey: "yunxiao.project") }
    }
    static var configured: Bool { !token.isEmpty && !orgId.isEmpty && !projectId.isEmpty }
}
