import Foundation

/// 读分享扩展留下的收件箱；读走就清掉，只处理一次。
enum ShareInboxReader {
    static let group = "group.com.wajipu.autoloop"

    struct Payload {
        let text: String
        let files: [URL]
    }

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("Shared", isDirectory: true)
    }

    static func take() -> Payload? {
        guard let folder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              let manifestName = names.filter({ $0.hasPrefix("inbox-") }).sorted().last,
              let data = try? Data(contentsOf: folder.appendingPathComponent(manifestName)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let text = object["text"] as? String ?? ""
        let files = (object["files"] as? [[String: String]] ?? []).compactMap { entry -> URL? in
            guard let name = entry["name"] else { return nil }
            let url = folder.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        // 清掉这次的清单（文件留给创建流程用完再删）
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(manifestName))
        guard !text.isEmpty || !files.isEmpty else { return nil }
        return Payload(text: text, files: files)
    }

    static func clean(_ files: [URL]) {
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}
