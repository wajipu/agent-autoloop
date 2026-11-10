import SwiftUI

/// 从通知点进来时记一下要打开哪张卡片。
final class DeepLink: ObservableObject {
    static let shared = DeepLink()
    @Published var cardID: Int?
}

@main
struct AutoLoopApp: App {
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
    @State private var tab = ProcessInfo.processInfo.environment["OPEN_TAB"] ?? "home"
    @State private var creating = false

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
                creating = true
                tab = oldValue
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                CreateIssueForm(onCreated: { _ in
                    creating = false
                    tab = "issues"
                    NotificationCenter.default.post(name: .issuesShouldReload, object: nil)
                }, onCancel: {
                    creating = false
                })
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .onOpenURL { url in
            guard url.scheme == "autoloop" else { return }
            if url.host == "card", let id = Int(url.lastPathComponent) {
                DeepLink.shared.cardID = id
            }
            tab = url.host == "issues" ? "issues" : "home"
        }
    }
}
