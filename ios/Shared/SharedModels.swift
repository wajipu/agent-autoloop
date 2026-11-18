import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Foundation

import Foundation

/// 工作项大类。App 和分享扩展共用。
enum IssueCategory: String, CaseIterable, Identifiable {
    case bug = "Bug"
    case task = "Task"
    case req = "Req"
    case topic = "Topic"
    case risk = "Risk"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .bug: "缺陷"
        case .task: "任务"
        case .req: "需求"
        case .topic: "主题"
        case .risk: "风险"
        }
    }
    /// GitHub 仓库里用的标签名（不存在会在建单时自动创建）。
    var githubLabel: String { label }
}

/// 主 App 写、分享扩展读的配置（App Group 里），避免扩展拿不到钥匙串。
enum SharedConfig {
    private static let suite = "group.com.wajipu.autoloop"

    static var defaults: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }

    static var token: String {
        get { defaults.string(forKey: "github.token") ?? "" }
        set { defaults.set(newValue, forKey: "github.token") }
    }
    static var owner: String {
        get { defaults.string(forKey: "github.owner") ?? "" }
        set { defaults.set(newValue, forKey: "github.owner") }
    }
    static var repo: String {
        get { defaults.string(forKey: "github.repo") ?? "" }
        set { defaults.set(newValue, forKey: "github.repo") }
    }
    static var configured: Bool { !token.isEmpty && !owner.isEmpty && !repo.isEmpty }
}
