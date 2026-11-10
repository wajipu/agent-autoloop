import SwiftUI

struct AgentsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var agents: [String: Any] = [:]
    @State private var rules: [[String: Any]] = []
    @State private var loading = true
    @State private var error: String?
    @State private var editing: AgentItem?
    @State private var creating = false

    private var items: [AgentItem] {
        agents.keys.sorted().map { key in
            let used = rules.filter { ($0["to"] as? String) == key }.count
            return AgentItem(id: key, raw: agents[key] as? [String: Any] ?? [:], uses: used)
        }
    }

    private var workers: [String] {
        Array(Set(items.compactMap { $0.worker.isEmpty ? nil : $0.worker })).sorted()
    }

    var body: some View {
        List {
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach(items) { item in
                    Button {
                        editing = item
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.name).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(item.id).font(.caption2).foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 6) {
                                Text(item.use).font(.caption)
                                Text("·").foregroundStyle(.tertiary)
                                Text(item.worker).font(.caption)
                                if !item.model.isEmpty {
                                    Text("·").foregroundStyle(.tertiary)
                                    Text(item.model).font(.caption)
                                }
                                if item.uses > 0 {
                                    Text("·").foregroundStyle(.tertiary)
                                    Text("\(item.uses) 条规则").font(.caption)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await remove(item) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .disabled(item.uses > 0)
                    }
                }
            } footer: {
                Text("被规则用着的 Agent 不能删，先把规则改派给别人。改完自动校验，不通过会退回。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
        }
        .overlay { if loading { ProgressView("读取中…") } }
        .task { await load() }
        .sheet(isPresented: $creating) {
            NavigationStack {
                AgentEditView(item: nil, workers: workers) { id, raw in
                    agents[id] = raw
                    Task { await persist() }
                }
            }
        }
        .sheet(item: $editing) { item in
            NavigationStack {
                AgentEditView(item: item, workers: workers) { id, raw in
                    if id != item.id { agents.removeValue(forKey: item.id) }
                    agents[id] = raw
                    Task { await persist() }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        guard settings.hubConfigured else {
            error = "还没配中台密钥"
            return
        }
        do {
            let payload = try await client().load()
            agents = payload.agents
            rules = payload.rules
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ item: AgentItem) async {
        agents.removeValue(forKey: item.id)
        await persist()
    }

    private func persist() async {
        do {
            _ = try await client().save(rules: rules, disabled: [], agents: agents)
            error = nil
        } catch {
            self.error = error.localizedDescription
            await load()
        }
    }

    private func client() -> RulesClient {
        RulesClient(baseURL: settings.consoleURL, key: settings.hubKey)
    }
}

struct AgentItem: Identifiable {
    let id: String
    var raw: [String: Any]
    var uses: Int = 0

    var name: String { raw["name"] as? String ?? id }
    var use: String { raw["use"] as? String ?? "—" }
    var worker: String { raw["worker"] as? String ?? "" }
    var model: String { raw["model"] as? String ?? "" }
    var effort: String { raw["effort"] as? String ?? "" }
    var command: [String] { raw["command"] as? [String] ?? [] }
}

struct AgentEditView: View {
    let original: AgentItem?
    let workers: [String]
    let onSave: (String, [String: Any]) -> Void

    @State private var id: String
    @State private var name: String
    @State private var preset: String
    @State private var plugin: String
    @State private var worker: String
    @State private var access: String
    @State private var model: String
    @State private var effort: String
    @State private var command: String
    @Environment(\.dismiss) private var dismiss

    /// 内置的几种；其余插件用「其他」填标识。
    private static let presets = ["claude", "codex", "acp", "command"]

    private let efforts = ["", "low", "medium", "high", "xhigh"]

    init(item: AgentItem?, workers: [String], onSave: @escaping (String, [String: Any]) -> Void) {
        original = item
        self.workers = workers
        self.onSave = onSave
        let use = item?.use ?? "claude"
        _id = State(initialValue: item?.id ?? "")
        _name = State(initialValue: item?.name ?? "")
        _preset = State(initialValue: Self.presets.contains(use) ? use : "other")
        _plugin = State(initialValue: Self.presets.contains(use) ? "" : use)
        _worker = State(initialValue: item?.worker ?? workers.first ?? "wajipu-mac")
        _access = State(initialValue: (item?.raw["access"] as? String) ?? "edit")
        _model = State(initialValue: item?.model ?? "")
        _effort = State(initialValue: item?.effort ?? "")
        _command = State(initialValue: (item?.command ?? []).joined(separator: "\n"))
    }

    /// 真正写进配置的类型：预设就是它本身，其他插件是填的标识。
    private var use: String {
        preset == "other" ? plugin.trimmingCharacters(in: .whitespaces) : preset
    }

    /// 要不要写启动命令：命令行和 ACP 必须有，其他插件可选。
    private var needsCommand: Bool { preset == "command" || preset == "acp" }

    /// 模型写在哪：ACP 由它自己协商，别的都能传下去。
    private var takesModel: Bool { preset != "acp" }

    var body: some View {
        Form {
            Section {
                if original == nil {
                    TextField("标识（英文，规则里引用）", text: $id)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                } else {
                    LabeledContent("标识", value: id).font(.footnote.monospaced())
                }
                TextField("显示名称", text: $name)
            } header: {
                Text("Agent")
            } footer: {
                Text(original == nil ? "标识建好之后别改，规则按它引用。" : "标识不能改，要换就新建一个再改派规则。")
            }

            Section {
                Picker("类型", selection: $preset) {
                    Text("Claude Code").tag("claude")
                    Text("Codex").tag("codex")
                    Text("第三方 ACP").tag("acp")
                    Text("命令行").tag("command")
                    Text("其他插件").tag("other")
                }
                if preset == "other" {
                    TextField("插件标识（英文）", text: $plugin)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("接单电脑") {
                    TextField("wajipu-mac", text: $worker)
                        .multilineTextAlignment(.trailing)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if workerOptions.count > 1 {
                    Menu("换成已注册的电脑") {
                        ForEach(workerOptions, id: \.self) { name in
                            Button(name) { worker = name }
                        }
                    }
                    .font(.footnote)
                }
                if preset != "command" {
                    Picker("权限", selection: $access) {
                        Text("只读").tag("read")
                        Text("可改").tag("edit")
                    }
                }
            } footer: {
                Text(preset == "command" ? "命令行 Agent 不带会话，每次都是新进程。" : "权限决定这一轮能不能改文件。")
            }

            if takesModel {
                Section {
                    LabeledContent("模型") {
                        TextField(modelPlaceholder, text: $model)
                            .multilineTextAlignment(.trailing)
                            .font(.footnote.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Picker("思考强度", selection: $effort) {
                        ForEach(efforts, id: \.self) { value in
                            Text(value.isEmpty ? "默认" : value).tag(value)
                        }
                    }
                } header: {
                    Text("模型")
                } footer: {
                    Text(modelFooter)
                }
            }

            if needsCommand || preset == "other" {
                Section {
                    TextEditor(text: $command)
                        .font(.footnote.monospaced())
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("命令")
                } footer: {
                    Text(preset == "acp"
                        ? "一行一个参数，第一行是可执行文件：它得说 ACP，比如某个 ACP 版 Agent 的启动命令。"
                        : "一行一个参数，第一行是可执行文件。可用 {prompt} {model} {effort} {cwd} {context} 占位。")
                }
            }
        }
        .navigationTitle(original == nil ? "新增 Agent" : "编辑 Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { endEditing() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }.disabled(!valid)
            }
        }
    }

    private var workerOptions: [String] {
        var list = workers
        if !list.contains(worker) { list.append(worker) }
        return list.isEmpty ? ["wajipu-mac"] : list
    }

    private var modelPlaceholder: String {
        switch preset {
        case "claude": return "留空用默认，如 opus"
        case "codex": return "留空用默认，如 gpt-5-codex"
        case "command": return "留给 {model}"
        default: return "留空用默认"
        }
    }

    private var modelFooter: String {
        preset == "command"
            ? "命令行里用 {model}、{effort} 取到这两个值；命令里没写占位就不起作用。"
            : "填这个 CLI 认的模型名，留空就用它自己配置的默认模型；思考强度空着同样是默认。"
    }

    private var valid: Bool {
        guard !id.trimmingCharacters(in: .whitespaces).isEmpty,
              !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !worker.isEmpty else { return false }
        if preset == "other", plugin.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if needsCommand {
            return !command.split(separator: "\n").isEmpty
        }
        return true
    }

    private func save() {
        var raw: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "worker": worker,
            "use": use,
        ]
        if needsCommand || preset == "other" {
            let lines = command
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty { raw["command"] = lines }
        }
        if preset != "command" {
            raw["access"] = access
        }
        if takesModel {
            let name = model.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { raw["model"] = name }
            if !effort.isEmpty { raw["effort"] = effort }
        }
        // 保留原有其他字段（比如 timeout、program）
        if var old = original?.raw {
            for key in ["name", "worker", "use", "access", "command", "model", "effort"] { old.removeValue(forKey: key) }
            raw.merge(old) { current, _ in current }
        }
        onSave(id.trimmingCharacters(in: .whitespaces), raw)
        dismiss()
    }
}
