import SwiftUI

struct SettingsView: View {
    /// 代理设置与 URLSession.app 共用这个键；直接存 standard defaults，改动立即生效。
    @AppStorage("network.proxy") private var proxySetting = ""
    @StateObject private var settings = AppSettings.shared
    @State private var path = NavigationPath()

    enum Route: Hashable {
        case hub, github, rules, agents
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    NavigationLink(value: Route.hub) {
                        LabeledContent {
                            Text(settings.hubConfigured ? "已配置" : "未配置")
                                .foregroundStyle(settings.hubConfigured ? .green : .secondary)
                        } label: {
                            Label("中台", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }

                    NavigationLink(value: Route.github) {
                        LabeledContent {
                            Text(settings.configured ? "已配置" : "未配置")
                                .foregroundStyle(settings.configured ? .green : .secondary)
                        } label: {
                            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                }

                Section("外观") {
                    Picker("主题", selection: $settings.appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("例：127.0.0.1:7897", text: $proxySetting)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("网络代理（可选）")
                } footer: {
                    Text("GitHub 连不上时填代理地址；留空跟随系统。改完立即生效。")
                }

                Section {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    LabeledContent("令牌存放", value: "本机钥匙串")
                } footer: {
                    Text("密钥只留在这台手机上，不会同步。")
                }
            }
            .scrollDismissesKeyboard(.interactively)
        .navigationTitle("设置")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .hub: HubSettingsView()
                case .github: GitHubSettingsView()
                case .rules: RulesView()
                case .agents: AgentsView()
                }
            }
            .onAppear {
                // 截图/调试用：OPEN_SETTINGS_PAGE=hub|github 直接打开对应页
                switch ProcessInfo.processInfo.environment["OPEN_SETTINGS_PAGE"] {
                case "hub": path.append(Route.hub)
                case "github": path.append(Route.github)
                case "rules":
                    path.append(Route.hub)
                    path.append(Route.rules)
                case "agents":
                    path.append(Route.hub)
                    path.append(Route.agents)
                default: break
                }
            }
        }
    }
}

// MARK: - 中台

struct HubSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var status: Status = .idle

    enum Status {
        case idle, checking, ok, failed(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("http://…:28081", text: $settings.hubURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.body.monospaced())
            } header: {
                Text("地址")
            } footer: {
                Text("中台跑在哪台电脑上就填哪台的地址，带端口。")
            }

            Section {
                SecureField("本人的密钥", text: $settings.hubKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("本人密钥")
            } footer: {
                Text("就是能看全局的那把 owner 密钥，首页的指标和在跑、排队都靠它。")
            }

            Section {
                NavigationLink {
                    RulesView()
                } label: {
                    Label("规则", systemImage: "list.bullet.rectangle.portrait")
                }
                NavigationLink {
                    AgentsView()
                } label: {
                    Label("Agent", systemImage: "cpu")
                }
            } footer: {
                Text("增删改规则不用登录服务器，改完自动校验，校验不过会退回原样。")
            }

            Section {
                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        Text("测试连接")
                        Spacer()
                        switch status {
                        case .idle:
                            EmptyView()
                        case .checking:
                            ProgressView()
                        case .ok:
                            Label("通了", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        case let .failed(message):
                            Text(message)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                }
                .disabled(!settings.hubConfigured || isChecking)
            }
        }
        .navigationTitle("中台")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isChecking: Bool {
        if case .checking = status { return true }
        return false
    }

    private func check() async {
        status = .checking
        do {
            _ = try await HubClient(baseURL: settings.hubURL, key: settings.hubKey).state()
            status = .ok
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

// MARK: - GitHub

struct GitHubSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    /// 与 GitHubClient.requestBase() 共用此键；默认关（直连 GitHub）。
    @AppStorage("github.via_hub") private var viaHub = true

    var body: some View {
        Form {
            Section {
                TextField("koklam-saas", text: $settings.owner)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("组织 / 用户")
            } footer: {
                Text("Issue 建在这个账号下的仓库里，比如 koklam-saas。")
            }

            Section {
                TextField("koklam-plus", text: $settings.repo)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("默认仓库")
            } footer: {
                Text("新建 Issue 的目标仓库，换仓库时才需要改。")
            }

            Section {
                Picker("默认标签", selection: $settings.defaultCategory) {
                    ForEach(IssueCategory.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                SecureField("ghp_… / github_pat_…", text: $settings.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("令牌")
            } footer: {
                Text("GitHub 个人访问令牌（需要 repo 权限），存在本机钥匙串里。")
            }

            Section {
                Toggle("经中台转发", isOn: $viaHub)
            } footer: {
                Text("GitHub 直连不稳定时可打开：请求改道中台服务器转发，令牌仍然只存在本机。默认直连。")
            }
        }
        .navigationTitle("GitHub")
        .navigationBarTitleDisplayMode(.inline)
    }
}
