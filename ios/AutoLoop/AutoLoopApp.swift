import SwiftUI
import ObjectiveC

/// 从通知点进来时记一下要打开哪张卡片。
final class DeepLink: ObservableObject {
    static let shared = DeepLink()
    @Published var cardID: Int?
}

/// 长按 App 图标选「新建工作项」时接住这个动作。
///
/// 冷启动时快捷操作从 scene 的连接参数进来；App 已在后台时，iOS 只调
/// SceneDelegate 的 `windowScene(_:performActionFor:)`，SwiftUI 不会转给
/// AppDelegate，所以启动后把这一个方法挂到当前 scene delegate 上。
final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let shortcutSelector =
        #selector(UIWindowSceneDelegate.windowScene(_:performActionFor:completionHandler:))

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            _ = handle(item)
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        CreateRequest.shared.flush()
    }

    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(handle(shortcutItem))
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            _ = handle(item)
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    private func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == CreateRequest.shortcutType else { return false }
        CreateRequest.shared.request()
        return true
    }

    /// SwiftUI 自己管 scene，iOS 只把「App 在后台时点的快捷操作」发给 scene delegate。
    /// 页面出现后把这一个方法挂上去，让 UIKit 能调到我们。
    static func installShortcutForwarding() {
        typealias Forward = @convention(c) (AnyObject, Selector, UIWindowScene,
                                            UIApplicationShortcutItem,
                                            @convention(block) (Bool) -> Void) -> Void
        let forward: Forward = { _, _, _, item, completion in
            completion(CreateRequest.shared.handleShortcut(item))
        }
        let imp = unsafeBitCast(forward, to: IMP.self)
        for scene in UIApplication.shared.connectedScenes {
            guard let delegate = scene.delegate, let cls = object_getClass(delegate) else { continue }
            if let method = class_getInstanceMethod(cls, shortcutSelector) {
                if method_getImplementation(method) != imp {
                    method_setImplementation(method, imp)
                }
            } else {
                class_addMethod(cls, shortcutSelector, imp, "v@:@@@?")
            }
        }
    }
}

@main
struct AutoLoopApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .tint(.indigo)
        }
    }
}

struct RootView: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var createRequest = CreateRequest.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = ProcessInfo.processInfo.environment["OPEN_TAB"] ?? "home"

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
                .tag("home")
            IssuesView()
                .tabItem { Label("工作项", systemImage: "square.stack.3d.up") }
                .tag("issues")
            Color.clear
                .tabItem { Label("新建", systemImage: "plus.circle.fill") }
                .tag("create")
            SettingsView()
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
                .tag("settings")
        }
        .onChange(of: tab) { oldValue, newValue in
            // 「新建」是动作不是页面：弹出表单后立刻回到原来的页签。
            if newValue == "create" {
                CreateRequest.shared.open()
                tab = oldValue
            }
        }
        .sheet(item: $createRequest.draft) { draft in
            NavigationStack {
                CreateIssueForm(initialTitle: draft.title,
                                initialText: draft.text,
                                initialCategory: draft.category,
                                onCreated: { _ in
                    createRequest.draft = nil
                    tab = "issues"
                    NotificationCenter.default.post(name: .issuesShouldReload, object: nil)
                }, onCancel: {
                    createRequest.draft = nil
                })
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .onAppear {
            createRequest.markReady()
            AppDelegate.installShortcutForwarding()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                createRequest.markReady()
                AppDelegate.installShortcutForwarding()
            }
        }
        .onOpenURL { url in
            guard url.scheme == "autoloop" else { return }
            if url.host == "create" {
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                CreateRequest.shared.open(
                    title: items.first { $0.name == "title" }?.value ?? "",
                    text: items.first { $0.name == "text" || $0.name == "body" }?.value ?? "",
                    category: CreateRequest.category(items.first { $0.name == "category" }?.value)
                )
                return
            }
            if url.host == "card", let id = Int(url.lastPathComponent) {
                DeepLink.shared.cardID = id
            }
            tab = url.host == "issues" ? "issues" : "home"
        }
    }
}
