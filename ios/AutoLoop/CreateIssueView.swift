import SwiftUI

/// 新建工作项：选类型、写标题和正文，直接建到云效。
struct CreateIssueView: View {
    let onCreated: (String) -> Void

    @StateObject private var settings = AppSettings.shared
    @State private var category: IssueCategory = .bug
    @State private var subject = ""
    @State private var detail = ""
    @State private var busy = false
    @State private var error: String?
    @State private var images: [URL] = []
    @Environment(\.dismiss) private var dismiss

    init(prefill: ShareInboxReader.Payload? = nil, onCreated: @escaping (String) -> Void) {
        self.onCreated = onCreated
        if let prefill {
            let firstLine = prefill.text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first.map(String.init) ?? ""
            _subject = State(initialValue: String(firstLine.prefix(80)))
            _detail = State(initialValue: prefill.text)
            _images = State(initialValue: prefill.files)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("类型", selection: $category) {
                    ForEach(IssueCategory.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("标题") {
                TextField("一句话说清问题", text: $subject, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section("描述") {
                TextEditor(text: $detail)
                    .frame(minHeight: 160)
                    .font(.subheadline)
            }

            if !images.isEmpty {
                Section("附件") {
                    ForEach(images, id: \.self) { url in
                        HStack(spacing: 10) {
                            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 42, height: 42)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "doc")
                                    .frame(width: 42, height: 42)
                            }
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Text("建好后在「工作项」里下拉刷新就能看到。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("新建工作项")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if busy {
                    ProgressView()
                } else {
                    Button("创建") { Task { await create() } }
                        .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { endEditing() }
            }
        }
    }

    /// 分享进来的图片直接塞进描述里（云效支持 data URL 内联图片）。
    private func composedDetail() -> String {
        guard !images.isEmpty else { return detail }
        var parts = [detail]
        for url in images {
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = url.pathExtension.lowercased() == "jpg" ? "jpeg" : "png"
            parts.append("<img src=\"data:image/\(mime);base64,\(data.base64EncodedString())\" />")
        }
        return parts.joined(separator: "\n\n")
    }

    private func create() async {
        busy = true
        error = nil
        defer { busy = false }
        let client = YunxiaoClient(orgId: settings.orgId, projectId: settings.projectId, token: settings.token)
        do {
            let id = try await client.createIssue(category: category,
                                                  subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  description: composedDetail())
            onCreated(id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

func endEditing() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
