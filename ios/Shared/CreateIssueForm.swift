import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 新建工作项：大类下拉（五种）→ 类型下拉（接口拉取，含「线上故障」「技术类需求」等）→ 填表。
struct CreateIssueForm: View {
    var initialText: String = ""
    var initialImages: [URL] = []
    var showAttachmentPickers = true
    var onCreated: (String) -> Void
    var onCancel: (() -> Void)?

    @State private var category: IssueCategory = .bug
    @State private var types: [WorkItemType] = []
    @State private var selectedTypeID: String = ""
    @State private var subject = ""
    @State private var detail = ""
    @State private var fields: [YunxiaoClient.FieldDef] = []
    @State private var values: [String: String] = [:]
    @State private var busy = false
    @State private var loadingFields = false
    @State private var error: String?
    @State private var attachmentImages: [(name: String, data: Data)] = []
    @State private var attachmentFiles: [(name: String, data: Data)] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var showCamera = false
    var showCameraButton = true
    @FocusState private var typing: Bool

    private var selectedType: WorkItemType? {
        types.first(where: { $0.id == selectedTypeID })
    }

    private var client: YunxiaoClient {
        YunxiaoClient(orgId: SharedConfig.orgId, projectId: SharedConfig.projectId, token: SharedConfig.token)
    }

    var body: some View {
        Form {
            if !SharedConfig.configured {
                Section {
                    SecureField("粘贴云效令牌（pt-...）", text: $tokenInput)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($typing)
                    Button("保存令牌") { saveToken() }
                        .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("云效令牌")
                } footer: {
                    Text("和 App「设置 → 云效」里那串一样，这里填一次就记住了。")
                }
            }

            Section {
                Picker("大类", selection: $category) {
                    ForEach(IssueCategory.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: category) {
                    selectedTypeID = ""
                    Task { await loadTypesAndFields() }
                }

                if types.isEmpty && loadingTypes {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                } else if types.isEmpty {
                    Text("该项目没有这类工作项").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Picker("类型", selection: $selectedTypeID) {
                        ForEach(types) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: selectedTypeID) {
                        Task { await loadFields() }
                    }
                }
            } header: {
                Text("类型")
            } footer: {
                Text("「线上故障」「技术类需求」这类细分类型也会列出来。")
            }

            Section("标题") {
                TextField("一句话说清问题", text: $subject, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($typing)
            }

            Section("描述") {
                ZStack(alignment: .topLeading) {
                    if detail.isEmpty {
                        Text("补充复现步骤、现场信息或截图说明…")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $detail)
                        .frame(minHeight: 140)
                        .font(.subheadline)
                        .focused($typing)
                }
            }

            if showAttachmentPickers {
                Section("附件") {
                    AttachmentPicker(images: $attachmentImages,
                                     files: $attachmentFiles,
                                     pickerItems: $pickerItems,
                                     showPhotoPicker: $showPhotoPicker,
                                     showFilePicker: $showFilePicker,
                                     showCamera: $showCamera,
                                     showCameraButton: showCameraButton) { item in
                        Task { await loadPicked(item) }
                    }
                }
            }

            if loadingFields {
                Section { HStack { Spacer(); ProgressView().controlSize(.small); Spacer() } }
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
                        .disabled(!SharedConfig.configured || selectedTypeID.isEmpty || subject.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { typing = false }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.pngData() {
                    attachmentImages.append(("camera-\(Int(Date().timeIntervalSince1970)).png", data))
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItems, maxSelectionCount: 9, matching: .images)
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if let urls = try? result.get() {
                for url in urls {
                    let secured = url.startAccessingSecurityScopedResource()
                    defer { if secured { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        attachmentFiles.append((url.lastPathComponent, data))
                    }
                }
            }
        }
        .task { await loadTypesAndFields() }
    }

    // MARK: - 数据

    @State private var tokenInput = ""
    @State private var loadingTypes = false

    private func loadTypesAndFields() async {
        loadingTypes = true
        defer { loadingTypes = false }
        guard SharedConfig.configured else { return }
        do {
            types = try await client.workitemTypes(category: category)
            selectedTypeID = (types.first(where: { $0.isDefault }) ?? types.first)?.id ?? ""
            await loadFields()
            error = nil
        } catch {
            types = WorkItemType.fallback
            selectedTypeID = ""
            self.error = error.localizedDescription
        }
    }

    private func saveToken() {
        let value = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        SharedConfig.token = value
        if SharedConfig.orgId.isEmpty { SharedConfig.orgId = "68359a6af957ee9df431ecaa" }
        if SharedConfig.projectId.isEmpty { SharedConfig.projectId = "854d2f7e0a466c8d4e3dd69c85" }
        tokenInput = ""
        Task { await loadTypesAndFields() }
    }

    private func binding(for field: YunxiaoClient.FieldDef) -> Binding<String> {
        Binding(
            get: { values[field.id] ?? field.defaultValue ?? field.options.first?.id ?? "" },
            set: { values[field.id] = $0 }
        )
    }

    private func loadFields() async {
        guard !selectedTypeID.isEmpty else { return }
        loadingFields = true
        defer { loadingFields = false }
        do {
            fields = try await client.requiredFields(typeID: selectedTypeID)
            var initial: [String: String] = [:]
            for field in fields {
                initial[field.id] = field.defaultValue ?? field.options.first?.id
            }
            values = initial
        } catch {
            fields = []
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let name = item.itemIdentifier ?? "photo-\(Int(Date().timeIntervalSince1970)).png"
        attachmentImages.append((name, data))
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let subjectValue = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = try await client.createIssue(
                category: category,
                subject: subjectValue,
                description: composedDetail(),
                customValues: values,
                typeID: selectedTypeID
            )
            var embeds: [String] = []
            for (name, data) in attachmentImages {
                let embed = try await client.uploadAttachment(issueID: id, name: name, data: data)
                embeds.append("<img src=\"\(embed)\" />")
            }
            for (name, data) in attachmentFiles {
                let embed = try await client.uploadAttachment(issueID: id, name: name, data: data)
                embeds.append("附件：[\(name)](\(embed))")
            }
            for url in initialImages {
                let raw = (try? Data(contentsOf: url)) ?? Data()
                guard !raw.isEmpty else { continue }
                let embed = try await client.uploadAttachment(issueID: id, name: url.lastPathComponent, data: raw)
                embeds.append("<img src=\"\(embed)\" />")
            }
            if !embeds.isEmpty {
                try await client.appendDescription(issueID: id, addition: embeds.joined(separator: "\n"))
            }
            attachmentImages = []
            attachmentFiles = []
            onCreated(id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 分享进来的图片内联进描述。
    private func composedDetail() -> String {
        guard attachmentImages.isEmpty else { return detail }
        var parts = [detail]
        for url in initialImages {
            guard let raw = try? Data(contentsOf: url),
                  let image = UIImage(data: raw),
                  let png = image.pngData() else { continue }
            parts.append("<img src=\"data:image/png;base64,\(png.base64EncodedString())\" />")
        }
        return parts.joined(separator: "\n\n")
    }
}
