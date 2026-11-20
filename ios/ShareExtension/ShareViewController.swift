import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 从其它 App 分享进来：把文字和图片存到 App Group，主 App 打开时接着用。
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        label.text = "正在交给 AutoLoop…"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await collectAndFinish() }
    }

    private func collectAndFinish() async {
        var text: [String] = []
        var files: [[String: String]] = []

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let value = await loadText(provider) {
                    text.append(value)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let value = await loadURL(provider) {
                    text.append(value)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                          let saved = await saveFile(provider, prefix: "image") {
                    files.append(saved)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier),
                          let saved = await saveFile(provider, prefix: "movie") {
                    files.append(saved)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier),
                          let saved = await saveFile(provider, prefix: "file") {
                    files.append(saved)
                }
            }
        }

        let payloadText = text.joined(separator: "\n")
        let urls = files.compactMap { entry -> URL? in
            guard let name = entry["name"], let folder = ShareInbox.folder else { return nil }
            return folder.appendingPathComponent(name)
        }
        await MainActor.run {
            let form = CreateIssueForm(initialText: payloadText, initialImages: urls, onCreated: { _ in
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }, onCancel: {
                self.extensionContext?.cancelRequest(withError: NSError(domain: "autoloop", code: 0))
            })
            let host = UIHostingController(rootView: NavigationStack { form })
            self.addChild(host)
            host.view.frame = self.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let text = item as? NSAttributedString {
                    continuation.resume(returning: text.string)
                } else if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func saveFile(_ provider: NSItemProvider, prefix: String) async -> [String: String]? {
        guard let folder = ShareInbox.folder else { return nil }
        let candidates = [UTType.image.identifier, UTType.movie.identifier, UTType.data.identifier]
        for type in candidates where provider.hasItemConformingToTypeIdentifier(type) {
            let temp: URL? = await withCheckedContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                    guard let url else {
                        continuation.resume(returning: nil)
                        return
                    }
                    // 这个 URL 回调结束就没了，立刻拷到临时目录
                    let copy = FileManager.default.temporaryDirectory
                        .appendingPathComponent("share-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "dat" : url.pathExtension)")
                    try? FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: FileManager.default.fileExists(atPath: copy.path) ? copy : nil)
                }
            }
            guard let temp else { continue }
            let name = "\(prefix)-\(UUID().uuidString).\(temp.pathExtension)"
            let target = folder.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: target)
            if (try? FileManager.default.copyItem(at: temp, to: target)) != nil {
                try? FileManager.default.removeItem(at: temp)
                return ["name": name, "kind": prefix]
            }
        }
        return nil
    }
}

/// 主 App 和分享扩展共用的收件箱（App Group 容器）。
enum ShareInbox {
    static let group = "group.com.wajipu.autoloop"

    static var folder: URL? {
        // 有 App Group 就放共享区；没有（通配 profile）就放扩展自己的临时目录，够本进程用
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Shared", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func write(text: String, files: [[String: String]]) {
        guard let folder else { return }
        let payload: [String: Any] = ["text": text, "files": files, "at": Date().timeIntervalSince1970]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: folder.appendingPathComponent("inbox-\(Int(Date().timeIntervalSince1970 * 1000)).json"))
    }
}
