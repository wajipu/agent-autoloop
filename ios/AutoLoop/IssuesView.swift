import SwiftUI

struct IssuesView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var category: IssueCategory = AppSettings.shared.defaultCategory
    @State private var items: [Workitem] = []
    @State private var allItems: [Workitem] = []
    @State private var statuses: [String] = []
    @State private var statusFilter: String?
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?
    @State private var path = NavigationPath()
    @State private var creating = ProcessInfo.processInfo.environment["OPEN_CREATE"] == "1"
    @State private var shared: ShareInboxReader.Payload?
    @State private var didRestoreCategory = false

    private var shown: [Workitem] {
        items.filter { item in
            (statusFilter == nil || item.statusName == statusFilter) &&
            (query.isEmpty
                || (item.subject ?? "").localizedCaseInsensitiveContains(query)
                || item.serialNumber.localizedCaseInsensitiveContains(query))
        }
    }

    private func childCount(_ item: Workitem) -> Int {
        items.filter { $0.parentIdentifier == item.id }.count
    }

    private var groups: [(String, [Workitem])] {
        Dictionary(grouping: shown, by: \.statusName)
            .sorted { StatusStyle.order($0.key) < StatusStyle.order($1.key) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("类型", selection: $category) {
                        ForEach(IssueCategory.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                    .onChange(of: category) {
                        statusFilter = nil
                        settings.defaultCategory = category
                        Task { await load() }
                    }
                }

                if settings.configured && !(loading && items.isEmpty) && shown.isEmpty && error == nil {
                    ContentUnavailableView("没有\(category.label)", systemImage: "tray")
                        .listRowBackground(Color.clear)
                }
                ForEach(groups, id: \.0) { status, list in
                    Section {
                        ForEach(list) { item in
                            NavigationLink(value: item) {
                                IssueRow(item: item)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(StatusStyle.color(status))
                                .frame(width: 7, height: 7)
                            Text(status)
                            Text("\(list.count)")
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("工作项")
            .navigationDestination(for: Workitem.self) { item in
                IssueDetailView(item: item)
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜标题或编号")
            .refreshable { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .issuesShouldReload)) { _ in
                Task { await load() }
            }
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $creating) {
                NavigationStack {
                    CreateIssueForm(initialText: shared?.text ?? "",
                                    initialImages: shared?.files ?? []) { _ in
                        if let shared { ShareInboxReader.clean(shared.files) }
                        shared = nil
                        creating = false
                        Task { await load() }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("状态", selection: $statusFilter) {
                            Text("全部状态").tag(String?.none)
                            ForEach(statuses, id: \.self) { status in
                                Text(status).tag(String?.some(status))
                            }
                        }
                    } label: {
                        Image(systemName: statusFilter == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .overlay {
                if !settings.configured {
                    ContentUnavailableView("还没配云效令牌",
                                           systemImage: "key",
                                           description: Text("去「设置」填一下令牌"))
                } else if loading && items.isEmpty {
                    ProgressView("读取中…")
                } else if let error, items.isEmpty {
                    ContentUnavailableView("读不到工作项",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                }
            }
            .task {
                if let inbox = ShareInboxReader.take() {
                    shared = inbox
                    creating = true
                }
                if !didRestoreCategory {
                    didRestoreCategory = true
                    category = settings.defaultCategory
                }
                await load()
                // 演示/截图用：SIMCTL_CHILD_OPEN_SERIAL=MGMF-40 直接打开某一条
                if let serial = ProcessInfo.processInfo.environment["OPEN_SERIAL"],
                   let target = items.first(where: { $0.serialNumber == serial }) {
                    path.append(target)
                }
            }
        }
    }

    private func load() async {
        guard settings.configured else { return }
        loading = true
        defer { loading = false }
        let client = YunxiaoClient(orgId: settings.orgId, projectId: settings.projectId, token: settings.token)
        do {
            let all = try await client.searchTree(category: category.rawValue)
            // 列表只显示主单；子单在主单详情里看
            let parents = Set(all.map(\.id))
            let fresh = all.filter { item in
                guard let pid = item.parentIdentifier, pid != Workitem.emptyParent, !pid.isEmpty else { return true }
                return !parents.contains(pid)   // 父单不存在（被删/无权限）时也当主单显示
            }
            items = fresh
            allItems = all
            statuses = Array(Set(fresh.map(\.statusName))).sorted { StatusStyle.order($0) < StatusStyle.order($1) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct IssueRow: View {
    let item: Workitem
    var childCount = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: StatusStyle.symbol(item.statusName))
                .font(.system(size: 15))
                .foregroundStyle(StatusStyle.color(item.statusName))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.subject ?? "(无标题)")
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.serialNumber).monospacedDigit()
                    if let who = item.assigneeName {
                        Text("·")
                        Text(who)
                    }
                    if childCount > 0 {
                        Text("·")
                        Text("\(childCount) 个子单")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let updated = item.updated {
                Text(StatusStyle.relative(updated))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

enum StatusStyle {
    static func color(_ status: String) -> Color {
        if status.contains("完成") || status.contains("关闭") || status.contains("已解决") { return .green }
        if status.contains("进行") || status.contains("开发") || status.contains("处理中") || status.contains("测试") { return .blue }
        if status.contains("拒绝") || status.contains("取消") || status.contains("挂起") { return .gray }
        return .orange
    }

    static func symbol(_ status: String) -> String {
        if status.contains("完成") || status.contains("关闭") || status.contains("已解决") {
            return "checkmark.circle.fill"
        }
        if status.contains("进行") || status.contains("开发") || status.contains("处理中") || status.contains("测试") {
            return "circle.lefthalf.filled"
        }
        return "circle"
    }

    /// 待办在前，进行中其次，结束的沉底。
    static func order(_ status: String) -> Int {
        if status.contains("待") || status.contains("未开始") { return 0 }
        if status.contains("进行") || status.contains("处理中") || status.contains("测试") { return 1 }
        if status.contains("完成") || status.contains("关闭") || status.contains("已解决") { return 3 }
        if status.contains("拒绝") || status.contains("取消") { return 4 }
        return 2
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter
    }()

    static func stamp(_ date: Date) -> String { stampFormatter.string(from: date) }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func relative(_ date: Date) -> String {
        let gap = Date.now.timeIntervalSince(date)
        if gap < 60 { return "刚刚" }
        if gap < 3600 { return "\(Int(gap / 60)) 分钟前" }
        if gap < 86_400 { return "\(Int(gap / 3600)) 小时前" }
        if gap < 7 * 86_400 { return "\(Int(gap / 86_400)) 天前" }
        return relativeFormatter.localizedString(for: date, relativeTo: .now)
    }
}
