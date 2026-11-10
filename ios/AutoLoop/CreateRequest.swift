import SwiftUI
import UIKit

/// 从 App 外面发起的「新建工作项」：图标快捷操作、autoloop://create、快捷指令、小组件。
final class CreateRequest: ObservableObject {
    static let shared = CreateRequest()
    static let shortcutType = "com.wajipu.autoloop.create"
    static let link = URL(string: "autoloop://create")!

    struct Draft: Identifiable {
        let id = UUID()
        var title = ""
        var text = ""
        var category: IssueCategory?
    }

    @Published var draft: Draft?

    /// 页面还没出来时先记下，等 RootView 出现再弹，否则 SwiftUI 会漏掉这次展示。
    private var pending = false
    private var ready = false

    func request() {
        pending = true
        flush()
    }

    /// 页面出现或回到前台时调用。
    func markReady() {
        ready = true
        flush()
    }

    func flush() {
        guard pending, ready else { return }
        pending = false
        guard draft == nil else { return }
        draft = Draft()
    }

    @discardableResult
    func handleShortcut(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == Self.shortcutType else { return false }
        request()
        return true
    }

    func open(title: String = "", text: String = "", category: IssueCategory? = nil) {
        pending = false
        draft = Draft(title: title, text: text, category: category)
    }

    /// 链接里的大类：英文 bug/task/req/topic/risk 或中文「缺陷/任务/需求/主题/风险」。
    static func category(_ value: String?) -> IssueCategory? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let match = IssueCategory.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(value) == .orderedSame || $0.label == value
        }) {
            return match
        }
        return nil
    }
}
