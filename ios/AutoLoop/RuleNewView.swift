import SwiftUI

/// 新增一条规则：全是下拉和输入框，不用碰 JSON。
struct RuleNewView: View {
    let agents: [String: Any]
    let sources: [String: Any]
    let existing: [RuleItem]
    let onSave: (RuleItem) -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case cron = "定时"
        case event = "事件"
        var id: String { rawValue }
    }

    private struct Preset: Identifiable {
        let id = UUID()
        let label: String
        let cron: String
    }

    private let presets = [
        Preset(label: "每 5 分钟", cron: "*/5 * * * *"),
        Preset(label: "每 15 分钟", cron: "*/15 * * * *"),
        Preset(label: "每小时", cron: "0 * * * *"),
        Preset(label: "每天 9:00", cron: "0 9 * * *"),
        Preset(label: "每天 18:00", cron: "0 18 * * *"),
        Preset(label: "每周一 9:00", cron: "0 9 * * 1"),
    ]

    @State private var name = ""
    @State private var kind: Kind = .cron
    @State private var presetIndex = 0
    @State private var customCron = ""
    @State private var source = ""
    @State private var types = ""
    @State private var to = ""
    @State private var cwd = "~/Documents/project"
    @State private var prompt = ""
    @State private var parallel = 1
    @Environment(\.dismiss) private var dismiss

    private var agentNames: [String] { agents.keys.sorted() }
    private var sourceNames: [String] { sources.keys.sorted() }

    private var cron: String {
        presetIndex >= presets.count ? customCron : presets[presetIndex].cron
    }

    private var typeSuggestions: [String] {
        existing
            .flatMap { ($0.raw["when"] as? [String: Any])?["types"] as? [String] ?? [] }
            .reduce(into: [String]()) { list, value in if !list.contains(value) { list.append(value) } }
    }

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("规则名称", text: $name)
                Picker("派给", selection: $to) {
                    ForEach(agentNames, id: \.self) { Text($0).tag($0) }
                }
                TextField("工作目录", text: $cwd)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
            }

            Section {
                Picker("什么时候跑", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if kind == .cron {
                    Picker("频率", selection: $presetIndex) {
                        ForEach(Array(presets.enumerated()), id: \.offset) { index, preset in
                            Text(preset.label).tag(index)
                        }
                        Text("自定义").tag(presets.count)
                    }
                    if presetIndex >= presets.count {
                        TextField("分 时 日 月 周", text: $customCron)
                            .font(.footnote.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        LabeledContent("cron", value: cron)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("来源", selection: $source) {
                        ForEach(sourceNames, id: \.self) { key in
                            Text((sources[key] as? [String: Any])?["name"] as? String ?? key).tag(key)
                        }
                    }
                    TextField("事件类型，逗号分隔", text: $types)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    if !typeSuggestions.isEmpty {
                        Menu("已有类型") {
                            ForEach(typeSuggestions, id: \.self) { type in
                                Button(type) { types = type }
                            }
                        }
                        .font(.footnote)
                    }
                    Stepper("同时最多 \(parallel) 轮", value: $parallel, in: 1...5)
                }
            } header: {
                Text("触发")
            } footer: {
                Text(kind == .cron ? "到点就派一轮；适合巡检、汇总这类活。" : "来源发出这个类型的事件时派一轮；类型可以用 * 通配，比如 workitem.*")
            }

            Section {
                TextEditor(text: $prompt)
                    .font(.footnote)
                    .frame(minHeight: 140)
            } header: {
                Text("提示词")
            } footer: {
                Text("必填：中台要求每条规则至少有提示词或技能，空着保存会被退回。")
            }

            Section {
                Text("保存后自动校验，不通过会退回去。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("新增规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(!valid)
            }
        }
        .onAppear {
            if to.isEmpty { to = agentNames.first ?? "claude" }
            if source.isEmpty { source = sourceNames.first ?? "app" }
        }
    }

    private var valid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !to.isEmpty else { return false }
        // 中台要求每条规则至少有 skill 或 prompt，这里只做 prompt
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if kind == .cron { return !cron.trimmingCharacters(in: .whitespaces).isEmpty }
        return !source.isEmpty && !types.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        var raw: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "to": to,
            "cwd": cwd.trimmingCharacters(in: .whitespaces),
        ]
        if kind == .cron {
            raw["when"] = ["cron": cron.trimmingCharacters(in: .whitespaces)]
        } else {
            let list = types.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            raw["when"] = ["source": source, "types": list]
            raw["parallel"] = parallel
        }
        if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            raw["prompt"] = prompt
        }
        onSave(RuleItem(raw: raw, enabled: true))
        dismiss()
    }
}
