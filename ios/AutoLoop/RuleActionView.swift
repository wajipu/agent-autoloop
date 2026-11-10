import SwiftUI

struct RuleOperation: Identifiable {
    let name: String
    let agent: String
    let action: RuleAction
    let needsSubject: Bool
    var id: String { name + "-" + action.rawValue }
}

struct RuleActionView: View {
    let operation: RuleOperation
    let onComplete: (String) async -> Void
    @StateObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var subject = ""
    @State private var autoResume = false
    @State private var until = Date().addingTimeInterval(3600)
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("规则", value: operation.name)
                LabeledContent("派给", value: operation.agent)
            }
            if operation.action == .pause {
                Section {
                    TextField("暂停原因（可选）", text: $reason, axis: .vertical)
                    Toggle("到时自动恢复", isOn: $autoResume)
                    if autoResume {
                        DatePicker("恢复时间", selection: $until, in: Date()...)
                    }
                } footer: {
                    Text("暂停后不再派发新任务，已在运行的任务继续。暂停期间的触发不会在恢复后自动补跑；已排队的任务会保留。")
                }
            } else if operation.action == .run {
                Section {
                    if operation.needsSubject {
                        TextField("对象编号", text: $subject)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    TextField("运行说明（可选）", text: $reason, axis: .vertical)
                } footer: {
                    Text(operation.needsSubject
                         ? "填写要处理的对象编号，例如工作项编号。确认后进入正常队列，可能产生模型费用和实际业务操作。"
                         : "确认后进入正常队列，可能产生模型费用和实际业务操作。")
                }
            } else {
                Section {
                    Text("恢复后继续派发已排队的任务，并接收之后的新触发；暂停期间错过的触发不会自动补跑。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(saving)
        .navigationTitle(operation.action.title)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(saving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }.disabled(saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await submit() }
                } label: {
                    if saving { ProgressView() } else { Text("确认") }
                }
                .disabled(saving || (operation.needsSubject && subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                          || (operation.action == .pause && autoResume && until <= Date()))
            }
        }
    }

    private func submit() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            let result = try await HubClient(baseURL: settings.hubURL, key: settings.hubKey)
                .controlRule(name: operation.name, action: operation.action,
                             reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                             subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                             until: operation.action == .pause && autoResume ? until : nil)
            let message: String
            switch operation.action {
            case .pause: message = "规则已暂停"
            case .resume: message = "规则已恢复"
            case .run: message = result.run.map { "已提交到第 \($0) 轮，执行状态请到首页查看" } ?? "已提交，执行状态请到首页查看"
            }
            await onComplete(message)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
