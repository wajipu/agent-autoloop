import SwiftUI

struct RulesView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var items: [RuleItem] = []
    @State private var agents: [String: Any] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var editing: RuleItem?
    @State private var creating = ProcessInfo.processInfo.environment["OPEN_RULES_NEW"] == "1"
    @State private var saving = false
    @State private var sources: [String: Any] = [:]

    private var enabled: [RuleItem] { items.filter(\.enabled) }
    private var disabled: [RuleItem] { items.filter { !$0.enabled } }

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
                ForEach(enabled) { item in
                    row(item)
                        .swipeActions(edge: .trailing) {
                            Button("停用") { Task { await toggle(item) } }
                                .tint(.orange)
                        }
                }
                if enabled.isEmpty && !loading {
                    Text("没有启用的规则").font(.subheadline).foregroundStyle(.secondary)
                }
            } header: {
                Text("启用中")
            } footer: {
                Text("点一条改定时和提示词，左滑停用；改完自动保存，校验不过会退回原样。")
            }

            if !disabled.isEmpty {
                Section("已停用") {
                    ForEach(disabled) { item in
                        row(item)
                            .swipeActions(edge: .trailing) {
                                Button("启用") { Task { await toggle(item) } }
                                    .tint(.green)
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("规则")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loading { ProgressView("读取规则…") }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $creating) {
            NavigationStack {
                RuleNewView(agents: agents, sources: sources, existing: items) { created in
                    items.append(created)
                    Task { await persist() }
                }
            }
        }
        .sheet(item: $editing) { item in
            NavigationStack {
                RuleEditView(item: item, agents: agents) { updated in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index] = updated
                    }
                    Task { await persist() }
                }
            }
        }
    }

    private func row(_ item: RuleItem) -> some View {
        Button {
            editing = item
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(item.enabled ? .primary : .secondary)
                    Spacer()
                    Text(item.to)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(item.trigger)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
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
            items = RuleItem.list(payload)
            agents = payload.agents
            sources = payload.sources
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggle(_ item: RuleItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].enabled.toggle()
        await persist()
    }

    private func persist() async {
        saving = true
        defer { saving = false }
        do {
            _ = try await client().save(rules: items.filter(\.enabled).map(\.raw),
                                        disabled: items.filter { !$0.enabled }.map(\.raw))
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

// MARK: - 编辑一条

struct RuleEditView: View {
    let item: RuleItem
    let agents: [String: Any]
    let onSave: (RuleItem) -> Void

    @State private var name: String
    @State private var to: String
    @State private var cron: String
    @State private var prompt: String
    @State private var cwd: String
    @Environment(\.dismiss) private var dismiss

    init(item: RuleItem, agents: [String: Any], onSave: @escaping (RuleItem) -> Void) {
        self.item = item
        self.agents = agents
        self.onSave = onSave
        _name = State(initialValue: item.name)
        _to = State(initialValue: item.to)
        _cron = State(initialValue: item.cron ?? "")
        _prompt = State(initialValue: item.prompt)
        _cwd = State(initialValue: item.raw["cwd"] as? String ?? "~/Documents/project")
    }

    private var agentNames: [String] {
        agents.keys.sorted()
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        // 没有 skill 的规则必须有提示词
        let hasSkill = (item.raw["skill"] as? String)?.isEmpty == false
        return hasSkill || !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("规则") {
                TextField("名称", text: $name)
                Picker("派给", selection: $to) {
                    ForEach(agentNames, id: \.self) { Text($0).tag($0) }
                }
                TextField("工作目录", text: $cwd)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                if item.cron != nil {
                    TextField("分 时 日 月 周", text: $cron)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    Text(item.trigger).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text(item.cron != nil ? "定时" : "触发")
            } footer: {
                Text(item.cron != nil ? "比如 */5 * * * * 是每 5 分钟。" : "事件规则由来源触发，这里改不了。")
            }

            Section("提示词") {
                TextEditor(text: $prompt)
                    .font(.footnote)
                    .frame(minHeight: 180)
            }

            Section {
                LabeledContent("状态", value: item.enabled ? "启用中" : "已停用")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(item.name)
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
                Button("保存") {
                    var updated = item
                    var raw = item.raw
                    raw["name"] = name.trimmingCharacters(in: .whitespaces)
                    raw["to"] = to
                    raw["cwd"] = cwd.trimmingCharacters(in: .whitespaces)
                    if item.cron != nil {
                        var when = raw["when"] as? [String: Any] ?? [:]
                        when["cron"] = cron.trimmingCharacters(in: .whitespaces)
                        raw["when"] = when
                    }
                    if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        raw.removeValue(forKey: "prompt")
                    } else {
                        raw["prompt"] = prompt
                    }
                    updated.raw = raw
                    onSave(updated)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}
