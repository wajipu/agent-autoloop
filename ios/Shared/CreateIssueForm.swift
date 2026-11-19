import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 建一条 GitHub Issue：标题、正文（Markdown）、标签、附件。
/// 附件经中台转存（POST /v1/attachments），链接带能力令牌写进正文，智能体免钥下载。
/// 分享扩展和主 App 共用：extension 传 onCreated/onCancel 管生命周期；主 App 里 onCancel 直接 dismiss。
/// 扩展进程里拍照不可用（UIImagePickerController sourceType .camera 限制），自动隐藏拍照按钮。
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

    @State private var images: [(name: String, data: Data)] = []
    @State private var files: [(name: String, data: Data)] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var showCamera = false
    @State private var inboxLoaded = false

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

    /// 分享扩展进程里没有相机；主 App 正常。
    private var isExtension: Bool { Bundle.main.bundlePath.hasSuffix(".appex") }

    private var attachments: [(name: String, data: Data)] { images + files }

    private var client: GitHubClient? {
        guard SharedConfig.configured else { return nil }
        return GitHubClient(owner: SharedConfig.owner, repo: SharedConfig.repo, token: SharedConfig.token)
    }

    private var hub: (base: URL, key: String)? {
        let raw = UserDefaults.standard.string(forKey: "hub.url")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, let base = URL(string: raw),
              let key = keychainValue("hub.key"), !key.isEmpty else { return nil }
        return (base, key)
    }

    /// 直接读钥匙串（与 AppSettings.Keychain 同 service/account）。
    /// 自包含实现：分享扩展 target 里没有 AppSettings 的 Keychain 符号。
    private func keychainValue(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.wajipu.autoloop",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 附件直传中台（POST /v1/attachments，raw bytes），返回可放进 Issue 正文的绝对链接。
    /// 自包含实现：分享扩展 target 里没有 HubClient。
    private func uploadAttachment(base: URL, key: String, name: String, data: Data) async throws -> String {
        let url = base.appending(path: "v1/attachments")
            .appending(queryItems: [URLQueryItem(name: "name", value: name)])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        let (payload, resp) = try await URLSession.shared.upload(for: request, from: data)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw CreateIssueError(errorDescription: "中台附件上传失败（\((resp as? HTTPURLResponse)?.statusCode ?? -1)）")
        }
        struct Uploaded: Decodable { let url: String }
        return base.absoluteString + (try JSONDecoder().decode(Uploaded.self, from: payload)).url
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
                    AttachmentPicker(images: $images, files: $files, pickerItems: $pickerItems,
                                     showPhotoPicker: $showPhotoPicker,
                                     showFilePicker: $showFilePicker,
                                     showCamera: $showCamera,
                                     showCameraButton: !isExtension,
                                     onPickedPhoto: { _ in })
                        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItems, matching: .images)
                        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item],
                                      allowsMultipleSelection: true) { handleFiles($0) }
                        .sheet(isPresented: $showCamera) {
                            CameraPicker { image in
                                if let data = image.jpegData(compressionQuality: 0.85) {
                                    images.append(("拍照 \(images.count + 1).jpg", data))
                                }
                            }
                            .ignoresSafeArea()
                        }
                } header: {
                    Text("附件（菜单图片 / PDF 等）")
                } footer: {
                    Text("附件经中台转存，智能体可直接查看原图。")
                }

                Section {
                    Picker("标签", selection: $category) {
                        ForEach(IssueCategory.allCases) { Text($0.label).tag($0) }
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
            .onChange(of: pickerItems) { items in
                guard !items.isEmpty else { return }
                Task { @MainActor in
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            images.append(("照片 \(images.count + 1).jpg", data))
                        }
                    }
                    pickerItems = []
                }
            }
            .onAppear {
                if subject.isEmpty { subject = initialTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
                if detail.isEmpty { detail = initialText.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let c = initialCategory { category = c }
                if !inboxLoaded {
                    inboxLoaded = true
                    loadInbox(initialImages)
                }
            }
        }
    }

    /// 分享扩展收件箱里的文件装进附件列表（图片进相册行，其余进文件行）。
    private func loadInbox(_ urls: [URL]) {
        let imageExts = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif"]
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            if imageExts.contains(url.pathExtension.lowercased()) {
                images.append((url.lastPathComponent, data))
            } else {
                files.append((url.lastPathComponent, data))
            }
        }
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                files.append((url.lastPathComponent, data))
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

        // 附件经中台转存；没配中台或个别失败时退回只列文件名，不阻塞建单。
        var uploaded: [(name: String, url: String)] = []
        var failed: [String] = []
        let all = attachments
        if !all.isEmpty {
            if let hub {
                for item in all {
                    do {
                        let link = try await uploadAttachment(base: hub.base, key: hub.key,
                                                             name: item.name, data: item.data)
                        uploaded.append((item.name, link))
                    } catch {
                        failed.append(item.name)
                    }
                }
            } else {
                failed = all.map(\.name)
            }
        }
        if !uploaded.isEmpty {
            let lines = uploaded.map { "- [\($0.name)](\($0.url))" }.joined(separator: "\n")
            body += (body.isEmpty ? "" : "\n\n") + "**附件**：\n" + lines
        }
        if !failed.isEmpty {
            let names = failed.map { "- \($0)" }.joined(separator: "\n")
            body += (body.isEmpty ? "" : "\n\n") + "**附件（未能上传，仅列名）**：\n" + names
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
