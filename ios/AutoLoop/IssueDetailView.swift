import SwiftUI
import MarkdownUI

struct IssueDetailView: View {
    let item: Workitem
    @StateObject private var settings = AppSettings.shared
    @State private var detail: WorkitemDetail?
    @State private var error: String?

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

            if let url = settings.workitemURL(item.id) {
                Section {
                    Link(destination: url) {
                        Label("在云效打开", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.serialNumber)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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
