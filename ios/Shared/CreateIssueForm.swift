import SwiftUI

/// 建一条 GitHub Issue：标题、正文（Markdown）、标签。
/// 分享扩展和主 App 共用：extension 传 onCreated/onCancel 管生命周期；主 App 里 onCancel 直接 dismiss。
struct CreateIssueForm: View {
    let initialTitle: String
    let initialText: String
    let initialImages: [URL]
    var initialCategory: IssueCategory? = nil
    let onCreated: (Bool) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var category: IssueCategory = .bug
    @State private var subject = ""
    @State private var detail = ""
    @State private var busy = false
    @State private var error: String?

    init(initialTitle: String = "", initialText: String = "", initialImages: [URL] = [],
         initialCategory: IssueCategory? = nil,
         onCreated: @escaping (Bool) -> Void, onCancel: @escaping () -> Void) {
        self.initialTitle = initialTitle
        self.initialText = initialText
        self.initialImages = initialImages
        self.initialCategory = initialCategory
        self.onCreated = onCreated
        self.onCancel = onCancel
    }

    private var attachmentNames: [String] { initialImages.map(\.lastPathComponent) }

    private var client: GitHubClient? {
        guard SharedConfig.configured else { return nil }
        return GitHubClient(owner: SharedConfig.owner, repo: SharedConfig.repo, token: SharedConfig.token)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题（一句话说清问题和影响）", text: $subject, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.body.weight(.semibold))
                }

                Section {
                    TextField("现象、复现步骤、预期结果…", text: $detail, axis: .vertical)
                        .lineLimit(6...12)
                        .font(.body)
                } header: {
                    Text("描述（支持 Markdown）")
                }

                Section {
                    Picker("标签", selection: $category) {
                        ForEach(IssueCategory.allCases) { Text($0.label).tag($0) }
                    }
                } footer: {
                    if !attachmentNames.isEmpty {
                        Text("分享带来的 \(attachmentNames.count) 个附件暂不支持上传，已在正文里列出文件名。")
                    }
                }
            }
            .navigationTitle("新建 Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView().controlSize(.small) }
                    else {
                        Button("创建") { Task { await submit() } }
                            .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client == nil)
                    }
                }
            }
            .overlay {
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .onAppear {
                if subject.isEmpty { subject = initialTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
                if detail.isEmpty { detail = initialText.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let c = initialCategory { category = c }
            }
        }
    }

    private func submit() async {
        guard let client else {
            error = "还没配置 GitHub（「设置 → GitHub」里填令牌）"
            return
        }
        busy = true
        defer { busy = false }
        var body = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !attachmentNames.isEmpty {
            let names = attachmentNames.map { "- \($0)" }.joined(separator: "\n")
            body += (body.isEmpty ? "" : "\n\n") + "**附件（暂未上传）**：\n" + names
        }
        do {
            _ = try await client.createIssue(category: category, subject: subject, description: body)
            // 分享扩展带来的收件箱附件清一下，避免堆积
            for url in initialImages where url.path.contains("ShareInbox") {
                try? FileManager.default.removeItem(at: url)
            }
            onCreated(true)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CreateIssueError: LocalizedError {
    static let emptyTitle = CreateIssueError(errorDescription: "先写个标题")
    static let notConfigured = CreateIssueError(errorDescription: "还没配置 GitHub")
    let errorDescription: String?
}
