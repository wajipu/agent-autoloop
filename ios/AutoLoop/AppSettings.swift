import Foundation
import Security
import SwiftUI

/// 令牌放钥匙串，企业/项目/类型放 UserDefaults。首次启动用 KoKLam 的默认值。
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var token: String {
        didSet {
            Keychain.set(token, for: "yunxiao.token")
            SharedConfig.token = token
        }
    }
    @Published var orgId: String {
        didSet {
            UserDefaults.standard.set(orgId, forKey: "yunxiao.org")
            SharedConfig.orgId = orgId
        }
    }
    @Published var projectId: String {
        didSet {
            UserDefaults.standard.set(projectId, forKey: "yunxiao.project")
            SharedConfig.projectId = projectId
        }
    }
    @Published var defaultCategory: IssueCategory {
        didSet {
            UserDefaults.standard.set(defaultCategory.rawValue, forKey: "yunxiao.category")
            NotificationCenter.default.post(name: .issueCategoryChanged, object: nil)
        }
    }
    @Published var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "app.appearance") }
    }
    @Published var hubURL: String {
        didSet { UserDefaults.standard.set(hubURL, forKey: "hub.url") }
    }
    @Published var hubKey: String {
        didSet { Keychain.set(hubKey, for: "hub.key") }
    }

    private init() {
        let defaults = UserDefaults.standard
        let stored = Keychain.get("yunxiao.token") ?? ""
        let fromEnv = ProcessInfo.processInfo.environment["YUNXIAO_TOKEN"] ?? ""
        token = stored.isEmpty ? fromEnv : stored
        orgId = defaults.string(forKey: "yunxiao.org") ?? "68359a6af957ee9df431ecaa"
        projectId = defaults.string(forKey: "yunxiao.project") ?? "854d2f7e0a466c8d4e3dd69c85"
        defaultCategory = IssueCategory(rawValue: defaults.string(forKey: "yunxiao.category") ?? "Task") ?? .task
        appearance = Appearance(rawValue: defaults.string(forKey: "app.appearance") ?? "system") ?? .system
        hubURL = ProcessInfo.processInfo.environment["HUB_URL"]
            ?? defaults.string(forKey: "hub.url")
            ?? "http://103.236.88.53:28081"
        let storedHub = Keychain.get("hub.key") ?? ""
        let hubFromEnv = ProcessInfo.processInfo.environment["HUB_KEY"] ?? ""
        hubKey = hubFromEnv.isEmpty ? storedHub : hubFromEnv

        // 启动时用环境变量注入过一次，就存进钥匙串，之后不用再带
        if stored.isEmpty, !fromEnv.isEmpty { Keychain.set(fromEnv, for: "yunxiao.token") }
        if storedHub.isEmpty, !hubFromEnv.isEmpty { Keychain.set(hubFromEnv, for: "hub.key") }

        // 分享扩展要用同一份配置，写进 App Group
        SharedConfig.token = token
        SharedConfig.orgId = orgId
        SharedConfig.projectId = projectId
    }

    var hubConfigured: Bool { !hubURL.isEmpty && !hubKey.isEmpty }

    /// 规则配置走控制台（跟中台同一台机器的 28090）。
    var consoleURL: String {
        if let url = URL(string: hubURL.trimmingCharacters(in: .whitespaces)), let host = url.host {
            return "\(url.scheme ?? "http")://\(host):28090"
        }
        return hubURL
    }

    var enterprise: Enterprise {
        get { Enterprise(rawValue: orgId) ?? .koklam }
        set {
            orgId = newValue.rawValue
            projectId = newValue.projectId
            defaultCategory = newValue.defaultCategory
        }
    }

    var configured: Bool { !token.isEmpty && !orgId.isEmpty && !projectId.isEmpty }

    var workitemURL: (String) -> URL? {
        { id in URL(string: "https://devops.aliyun.com/projex/project/\(self.projectId)/workitem/\(id)") }
    }
}

extension Notification.Name {
    static let issueCategoryChanged = Notification.Name("issueCategoryChanged")
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Keychain {
    private static let service = "com.wajipu.autoloop"

    static func set(_ value: String, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
