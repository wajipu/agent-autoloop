import SwiftUI
import WebKit
import MarkdownUI

/// 包一层以便当 sheet item。
struct WebSheet: Identifiable {
    let id = UUID()
    let url: URL
}

/// 底部弹出的内嵌浏览器，不离开 App。
struct SafariSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SafariView(url: url)
            .ignoresSafeArea(edges: .bottom)
            .presentationDragIndicator(.visible)
    }
}

struct SafariView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct IssueDetailView: View {
    @State var item: Workitem
    @StateObject private var settings = AppSettings.shared
    @State private var detail: WorkitemDetail?
    @State private var error: String?
    @State private var web: WebSheet?
    @State private var statuses: [(id: String, name: String)] = []
    @State private var changingTo: String?
    @State private var flowError: String?
    @State private var comments: [YunxiaoClient.Comment] = []
    @State private var activities: [YunxiaoClient.Activity] = []
    @State private var children: [Workitem] = []
    @State private var commentDraft = ""
    @State private var postingComment = false

    /// 从轮次详情跳进来时只有编号，先拉完整数据再展示。
    private var resolved: Workitem? {
        if let full = detail {
            return Workitem(id: full.id, serialNumber: full.serialNumber, subject: full.subject,
                            status: full.status, assignedTo: full.assignedTo,
                            workitemType: full.workitemType, gmtModified: full.gmtModified,
                            categoryId: full.categoryId)
        }
        return item
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: StatusStyle.symbol(item.statusName))
                            .foregroundStyle(StatusStyle.color(item.statusName))
                        Text(item.serialNumber)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(item.statusName)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Text(item.subject ?? "(无标题)")
                        .font(.title3.weight(.semibold))
                }
                .padding(.vertical, 4)
            }

            Section("属性") {
                LabeledContent("类型", value: item.typeName ?? "—")
                LabeledContent("负责人", value: detail?.assignedTo?.name ?? item.assigneeName ?? "—")
                if let created = detail?.created {
                    LabeledContent("创建", value: StatusStyle.stamp(created))
                }
                if let updated = detail?.updated ?? item.updated {
                    LabeledContent("更新", value: StatusStyle.stamp(updated))
                }
                if let labels = detail?.labels, !labels.isEmpty {
                    LabeledContent("标签", value: labels.compactMap(\.name).joined(separator: "、"))
                }
            }

            Section("正文") {
                if let detail {
                    if detail.body.isEmpty {
                        Text("这条工作项没有正文")
                            .foregroundStyle(.secondary)
                    } else {
                        Markdown(detail.body)
                            .markdownTheme(.gitHub)
                    }
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }

            if statuses.isEmpty && detail != nil && error == nil {
                Section {
                    Button {
                        Task { await loadStatuses() }
                    } label: {
                        Label("换状态", systemImage: "arrow.triangle.branch")
                    }
                }
            } else if !statuses.isEmpty {
                Section("换状态") {
                    ForEach(statuses, id: \.id) { status in
                        if status.id == (detail?.status?.id ?? "") || status.name == item.statusName {
                            Label(status.name, systemImage: "checkmark")
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                changingTo = status.id
                            } label: {
                                Text(status.name)
                            }
                            .disabled(changingTo != nil)
                        }
                    }
                }
                if let flowError {
                    Section {
                        Label(flowError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("评论（\(comments.count)）") {
                if comments.isEmpty && detail != nil {
                    Text("还没有评论").foregroundStyle(.secondary)
                }
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(comment.user).font(.caption.weight(.medium))
                            if let at = comment.at {
                                Text(StatusStyle.relative(at)).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Text(comment.content)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("写评论…", text: $commentDraft, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.subheadline)
                    Button {
                        Task { await postComment() }
                    } label: {
                        if postingComment { ProgressView().controlSize(.small) }
                        else { Image(systemName: "paperplane.fill") }
                    }
                    .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || postingComment)
                }
                .padding(.top, 2)
            }

            if !activities.isEmpty {
                Section("动态") {
                    ForEach(activities) { activity in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.text).font(.caption)
                            if let at = activity.at {
                                Text(StatusStyle.stamp(at)).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            if !children.isEmpty {
                Section("子单（\(children.count)）") {
                    ForEach(children) { child in
                        NavigationLink {
                            IssueDetailView(item: child)
                        } label: {
                            IssueRow(item: child)
                        }
                    }
                }
            }

            if let url = settings.workitemURL(item.id) {
                Section {
                    Button {
                        web = WebSheet(url: url)
                    } label: {
                        Label("在云效打开", systemImage: "safari")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.serialNumber)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $web) { web in
            SafariSheet(url: web.url)
        }
        .task {
            await load()
            await loadTalk()
            await loadChildren()
        }
    }

    private func loadTalk() async {
        guard settings.configured else { return }
        let client = YunxiaoClient(orgId: settings.orgId, projectId: settings.projectId, token: settings.token)
        do {
            comments = try await client.comments(issueID: item.identifier)
            activities = try await client.activities(issueID: item.identifier)
        } catch {
            // 评论拉不到不拦着详情
        }
    }

    private func loadChildren() async {
        guard settings.configured else { return }
        let client = YunxiaoClient(orgId: settings.orgId, projectId: settings.projectId, token: settings.token)
        do {
            // 树形搜索拿全量，筛出本单的直接子单
            let all = try await client.searchTree(category: item.category.rawValue)
            children = all.filter { $0.parentIdentifier == item.id }
        } catch {
            // 拉不到子单不拦着详情
        }
    }

    private func loadStatuses() async {
        guard settings.configured else { return }
        let client = YunxiaoClient(orgId: settings.orgId, projectId: settings.projectId, token: settings.token)
        do {
            statuses = try await client.workflowStatuses(category: item.category)
        } catch {
            flowError = error.localizedDescription
        }
    }

    private func changeStatus(_ id: String) async {
        changingTo = id
        defer { changingTo = nil }
        guard settings.configured else { return }
        let client = YunxiaoClient(orgId: settings.orgId, projectId: settings.projectId, token: settings.token)
        do {
            try await client.updateStatus(issueID: item.identifier, statusID: id)
            flowError = nil
        } catch {
            flowError = error.localizedDescription
        }
    }

    private func postComment() async {
        let content = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, settings.configured else { return }
        postingComment = true
        defer { postingComment = false }
        let client = YunxiaoClient(orgId: settings.orgId, projectId: settings.projectId, token: settings.token)
        do {
            try await client.addComment(issueID: item.identifier, content: content)
            commentDraft = ""
            comments = try await client.comments(issueID: item.identifier)
        } catch {
            flowError = error.localizedDescription
        }
    }

    private func load() async {
        guard settings.configured else {
            error = "还没填云效令牌"
            return
        }
        let client = YunxiaoClient(orgId: settings.orgId, projectId: settings.projectId, token: settings.token)
        do {
            detail = try await client.detail(serialNumber: item.serialNumber)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
