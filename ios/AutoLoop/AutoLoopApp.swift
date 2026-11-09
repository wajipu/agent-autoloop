import SwiftUI

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
    @State private var tab = ProcessInfo.processInfo.environment["OPEN_TAB"] ?? "home"

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
                .tag("home")
            IssuesView()
                .tabItem { Label("工作项", systemImage: "square.stack.3d.up") }
                .tag("issues")
            SettingsView()
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
                .tag("settings")
        }
    }
}
