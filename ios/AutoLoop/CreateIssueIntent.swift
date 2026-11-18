import AppIntents
import Foundation

/// 快捷指令 / Siri / 操作按钮 / 控制中心：直接建一条 GitHub Issue，不用先打开 App。
struct CreateIssueIntent: AppIntent {
    static var title: LocalizedStringResource = "新建 Issue"
    static var description = IntentDescription("在 Koklam 的 GitHub 仓库建一条 Issue")
    static var openAppWhenRun = false

    @Parameter(title: "标题", requestValueDialog: "要建什么？")
    var title: String

    @Parameter(title: "描述")
    var detail: String?

    @Parameter(title: "标签", default: "任务")
    var categoryLabel: String?

    static var parameterSummary: some ParameterSummary {
        Summary("新建 \(\.$title)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let subject = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else { throw CreateIssueError.emptyTitle }
        let settings = AppSettings.shared
        guard settings.configured else { throw CreateIssueError.notConfigured }
        let client = GitHubClient(owner: settings.owner, repo: settings.repo, token: settings.token)
        let category = IssueCategory(rawValue: categoryLabel ?? "Task") ?? .task
        let issue = try await client.createIssue(category: category,
                                                 subject: subject,
                                                 description: detail ?? "")
        return .result(dialog: "已创建 \(issue.serialNumber)")
    }
}
