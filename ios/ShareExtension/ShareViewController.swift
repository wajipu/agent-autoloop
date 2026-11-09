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
        let name = "\(prefix)-\(UUID().uuidString).\(prefix == "image" ? "png" : "dat")"
        let target = folder.appendingPathComponent(name)

        let data: Data? = await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: provider.registeredTypeIdentifiers.first ?? UTType.data.identifier) { url, _ in
                guard let url, let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
        guard let data, (try? data.write(to: target)) != nil else { return nil }
        return ["name": name, "kind": prefix]
    }
}

/// 主 App 和分享扩展共用的收件箱（App Group 容器）。
enum ShareInbox {
    static let group = "group.com.wajipu.autoloop"

    static var folder: URL? {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        let dir = root.appendingPathComponent("Shared", isDirectory: true)
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
