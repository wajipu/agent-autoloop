import SwiftUI

/// 新建工作项的表单，App 里和分享扩展里用的是同一份。
struct CreateIssueForm: View {
    var initialText: String = ""
    var initialImages: [URL] = []
    var onCreated: (String) -> Void
    var onCancel: (() -> Void)?

    @State private var category: IssueCategory = .bug
    @State private var subject = ""
    @State private var detail = ""
    @State private var fields: [YunxiaoClient.FieldDef] = []
    @State private var values: [String: String] = [:]
    @State private var busy = false
    @State private var loadingFields = false
    @State private var error: String?
    @FocusState private var typing: Bool

    private var client: YunxiaoClient {
        YunxiaoClient(orgId: SharedConfig.orgId, projectId: SharedConfig.projectId, token: SharedConfig.token)
    }

    var body: some View {
        Form {
            if !SharedConfig.configured {
                Section {
                    Label("还没配云效令牌，去 App 的「设置 → 云效」填一下", systemImage: "key")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Picker("类型", selection: $category) {
                    ForEach(IssueCategory.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: category) {
                    values = [:]
                    Task { await loadFields() }
                }
            }

            Section("标题") {
                TextField("一句话说清问题", text: $subject, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($typing)
            }

            Section("描述") {
                TextEditor(text: $detail)
                    .frame(minHeight: 140)
                    .font(.subheadline)
                    .focused($typing)
            }

            if loadingFields {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            }

            ForEach(fields) { field in
                Section(field.name) {
                    Picker("", selection: binding(for: field)) {
                        ForEach(field.options) { option in
                            Text(option.value).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            if !initialImages.isEmpty {
                Section("附件") {
                    ForEach(initialImages, id: \.self) { url in
                        HStack(spacing: 10) {
                            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "doc").frame(width: 44, height: 44)
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
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("新建工作项")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if busy {
                    ProgressView()
                } else {
                    Button("创建") { Task { await submit() } }
                        .disabled(!SharedConfig.configured || subject.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { typing = false }
            }
        }
        .task {
            if subject.isEmpty {
                let firstLine = initialText
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .first.map(String.init) ?? ""
                subject = String(firstLine.prefix(80))
                detail = initialText
            }
            await loadFields()
        }
    }

    private func binding(for field: YunxiaoClient.FieldDef) -> Binding<String> {
        Binding(
            get: { values[field.id] ?? field.defaultValue ?? field.options.first?.id ?? "" },
            set: { values[field.id] = $0 }
        )
    }

    private func loadFields() async {
        guard SharedConfig.configured else { return }
        loadingFields = true
        defer { loadingFields = false }
        do {
            let typeID = try await client.workitemTypeID(category: category)
            fields = try await client.requiredFields(typeID: typeID)
            var initial: [String: String] = [:]
            for field in fields {
                initial[field.id] = field.defaultValue ?? field.options.first?.id
            }
            values = initial
            error = nil
        } catch {
            fields = []
            self.error = error.localizedDescription
        }
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let id = try await client.createIssue(
                category: category,
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                description: composedDetail(),
                customValues: values
            )
            onCreated(id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 分享进来的图片内联进描述（云效令牌接口没有附件上传）。
    private func composedDetail() -> String {
        guard !initialImages.isEmpty else { return detail }
        var parts = [detail]
        for url in initialImages {
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = url.pathExtension.lowercased() == "jpg" ? "jpeg" : "png"
            parts.append("<img src=\"data:image/\(mime);base64,\(data.base64EncodedString())\" />")
        }
        return parts.joined(separator: "\n\n")
    }
}
