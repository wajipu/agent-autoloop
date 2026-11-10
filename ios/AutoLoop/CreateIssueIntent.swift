import AppIntents
import Foundation

/// 快捷指令 / Siri / 操作按钮 / 控制中心：直接建一条工作项，不用先打开 App。
struct CreateIssueIntent: AppIntent {
    static var title: LocalizedStringResource = "新建工作项"
    static var description = IntentDescription("在 KoKLam 云效建一条工作项")
    static var openAppWhenRun = false

    @Parameter(title: "标题", requestValueDialog: "要建什么？")
    var title: String

    @Parameter(title: "描述")
    var detail: String?

    @Parameter(title: "大类")
    var category: IssueCategory?

    static var parameterSummary: some ParameterSummary {
        Summary("新建 \(\.$title)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let subject = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else { throw CreateIssueError.emptyTitle }
        guard let client else { throw CreateIssueError.notConfigured }

        let kind = category ?? .task
        let typeID = try await client.workitemTypeID(category: kind)
        var values: [String: String] = [:]
        for field in try await client.requiredFields(typeID: typeID) {
            if let value = field.defaultValue ?? field.options.first?.id {
                values[field.id] = value
            }
        }
        let id = try await client.createIssue(category: kind,
                                             subject: subject,
                                             description: detail ?? "",
                                             customValues: values,
                                             typeID: typeID)
        let serial = (try? await client.serialNumber(issueID: id)) ?? subject
        return .result(dialog: "已创建 \(serial)")
    }

    private var client: YunxiaoClient? {
        let defaults = UserDefaults.standard
        let token = SharedConfig.token.isEmpty ? (Keychain.get("yunxiao.token") ?? "") : SharedConfig.token
        let org = SharedConfig.orgId.isEmpty
            ? (defaults.string(forKey: "yunxiao.org") ?? "68359a6af957ee9df431ecaa")
            : SharedConfig.orgId
        let project = SharedConfig.projectId.isEmpty
            ? (defaults.string(forKey: "yunxiao.project") ?? "854d2f7e0a466c8d4e3dd69c85")
            : SharedConfig.projectId
        guard !token.isEmpty else { return nil }
        return YunxiaoClient(orgId: org, projectId: project, token: token)
    }
}

enum CreateIssueError: LocalizedError {
    case notConfigured
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .notConfigured: "还没配云效令牌，先在 AutoLoop 的「设置 → 云效」里填一下"
        case .emptyTitle: "标题不能为空"
        }
    }
}

extension IssueCategory: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "工作项大类" }

    static var caseDisplayRepresentations: [IssueCategory: DisplayRepresentation] {
        [
            .bug: "缺陷",
            .task: "任务",
            .req: "需求",
            .topic: "主题",
            .risk: "风险",
        ]
    }
}

/// 装好后不用自己搭快捷指令，Siri 和「快捷指令」里直接就有。
struct AutoLoopShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CreateIssueIntent(),
                    phrases: ["用 \(.applicationName) 新建工作项",
                              "在 \(.applicationName) 建个工作项"],
                    shortTitle: "新建工作项",
                    systemImageName: "plus.circle.fill")
    }
}
