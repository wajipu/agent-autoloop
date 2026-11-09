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
    let item: Workitem
    @StateObject private var settings = AppSettings.shared
    @State private var detail: WorkitemDetail?
    @State private var error: String?
    @State private var web: WebSheet?
    @State private var statuses: [(id: String, name: String)] = []
    @State private var changingTo: String?
    @State private var flowError: String?

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
        .task { await load() }
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
