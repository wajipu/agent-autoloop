import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var path = NavigationPath()

    enum Route: Hashable {
        case hub, yunxiao, rules, agents
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

                    NavigationLink(value: Route.yunxiao) {
                        LabeledContent {
                            Text(settings.enterprise.name)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("云效", systemImage: "square.stack.3d.up")
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
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    LabeledContent("令牌存放", value: "本机钥匙串")
                } footer: {
                    Text("密钥只留在这台手机上，不会同步。")
                }
            }
            .navigationTitle("设置")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .hub: HubSettingsView()
                case .yunxiao: YunxiaoSettingsView()
                case .rules: RulesView()
                case .agents: AgentsView()
                }
            }
            .onAppear {
                // 截图/调试用：OPEN_SETTINGS_PAGE=hub|yunxiao 直接打开对应页
                switch ProcessInfo.processInfo.environment["OPEN_SETTINGS_PAGE"] {
                case "hub": path.append(Route.hub)
                case "yunxiao": path.append(Route.yunxiao)
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

// MARK: - 云效

struct YunxiaoSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section {
                Picker("企业", selection: Binding(
                    get: { settings.enterprise },
                    set: { settings.enterprise = $0 }
                )) {
                    ForEach(Enterprise.allCases) { Text($0.name).tag($0) }
                }
            } footer: {
                Text("两家企业各用各的令牌，切换后回「工作项」下拉刷新。")
            }

            Section {
                SecureField("pt-...", text: $settings.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("令牌")
            } footer: {
                Text("云效个人访问令牌，存在本机钥匙串里。")
            }

            Section {
                Picker("默认类型", selection: $settings.defaultCategory) {
                    ForEach(IssueCategory.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                DisclosureGroup("高级", isExpanded: $showAdvanced) {
                    LabeledContent("企业 id") {
                        Text(settings.orgId)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    LabeledContent("项目 id") {
                        Text(settings.projectId)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } footer: {
                Text("一般不用改；换项目时才需要手动填。")
            }
        }
        .navigationTitle("云效")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 企业

enum Enterprise: String, CaseIterable, Identifiable {
    case koklam = "68359a6af957ee9df431ecaa"
    case zhongliu = "63043643cb9d006848793bd7"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .koklam: "KoKLam"
        case .zhongliu: "众流"
        }
    }

    var projectId: String {
        switch self {
        case .koklam: "854d2f7e0a466c8d4e3dd69c85"
        case .zhongliu: "f21386955bbb352a491b704af2"
        }
    }

    var defaultCategory: IssueCategory {
        switch self {
        case .koklam: .task
        case .zhongliu: .bug
        }
    }
}
