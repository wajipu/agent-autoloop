import SwiftUI

// MARK: - 模型

/// 一个工作项 + 它的子单（树）。
struct WorkitemNode: Identifiable {
    let item: Workitem
    let children: [WorkitemNode]
    var id: String { item.id }
}

/// 按状态分组。
struct StatusGroup: Identifiable {
    let status: String
    let nodes: [WorkitemNode]
    let items: [Workitem]
    var id: String { status }

    static func buildTree(from nodesDict: [String: [WorkitemNode]]) -> [StatusGroup] {
        let keys = nodesDict.keys.sorted { StatusStyle.order($0) < StatusStyle.order($1) }
        return keys.map { StatusGroup(status: $0, nodes: nodesDict[$0] ?? [], items: []) }
    }

    static func buildFlat(from itemsDict: [String: [Workitem]]) -> [StatusGroup] {
        let keys = itemsDict.keys.sorted { StatusStyle.order($0) < StatusStyle.order($1) }
        return keys.map { StatusGroup(status: $0, nodes: [], items: itemsDict[$0] ?? []) }
    }
}

// MARK: - 列表页

struct IssuesView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var category: IssueCategory = AppSettings.shared.defaultCategory
    @State private var items: [Workitem] = []
    @State private var statuses: [String] = []
    @State private var statusFilter: String?
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?
    @State private var path = NavigationPath()
    @State private var creating = ProcessInfo.processInfo.environment["OPEN_CREATE"] == "1"
    @State private var shared: ShareInboxReader.Payload?
    @State private var treeMode = true
    @State private var expanded: Set<String> = []
    @State private var didRestoreCategory = false

    private var client: YunxiaoClient {
        YunxiaoClient(orgId: settings.orgId, projectId: settings.projectId, token: settings.token)
    }

    /// 树模式：工单全部（含子单）可见，搜索命中的同时带出它的整棵树。
    private var shown: [Workitem] {
        guard query.isEmpty else {
            let hit = items.filter { item in
                (item.subject ?? "").localizedCaseInsensitiveContains(query)
                    || item.serialNumber.localizedCaseInsensitiveContains(query)
            }
            var extra: Set<String> = []
            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for item in hit {
                if !item.isRoot, let pid = item.parentIdentifier, let parent = byID[pid] {
                    extra.insert(parent.id)
                }
                for child in items where child.parentIdentifier == item.id {
                    extra.insert(child.id)
                }
            }
            return items.filter { hit.contains($0) || extra.contains($0.id) }
        }
        return items
    }

    private var showEmptyHint: Bool {
        settings.configured && !loading && shown.isEmpty && error == nil
    }

    private var activeRuns: Int { 0 }

    var body: some View {
        NavigationStack(path: $path) {
            listContent
        }
        .navigationDestination(for: Workitem.self) { item in
            IssueDetailView(item: item)
        }
    }

    // MARK: 列表

    private var listContent: some View {
        List {
            typeSection
            if showEmptyHint {
                emptySection
            }
            if treeMode {
                treeSections
            } else {
                flatSections
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("工作项")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜标题或编号")
        .refreshable { await load() }
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
        .toolbar { toolbarContent }
        .overlay { overlayView }
        .onAppear {
            if !didRestoreCategory {
                didRestoreCategory = true
                category = settings.defaultCategory
            }
        }
        .task { await load() }
    }

    private var typeSection: some View {
        Section {
            Picker("类型", selection: $category) {
                ForEach(IssueCategory.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .listRowBackground(Color.clear)
            .onChange(of: category) {
                statusFilter = nil
                expanded = []
                settings.defaultCategory = category
                Task { await load() }
            }
        }
    }

    private var emptySection: some View {
        ContentUnavailableView("没有\(category.label)", systemImage: "tray")
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var treeSections: some View {
        let treeDict = Dictionary(grouping: treeNodes) { $0.item.statusName }
        ForEach(StatusGroup.buildTree(from: treeDict)) { group in
            Section {
                ForEach(group.nodes) { node in
                    TreeNodeRow(node: node, expanded: $expanded, depth: 0)
                }
            } header: {
                sectionHeader(group.status, count: totalNodes(group.nodes))
            }
        }
    }

    @ViewBuilder
    private var flatSections: some View {
        let flatDict = Dictionary(grouping: shown) { $0.statusName }
        ForEach(StatusGroup.buildFlat(from: flatDict)) { group in
            Section {
                ForEach(group.items) { item in
                    NavigationLink(value: item) {
                        IssueRow(item: item)
                    }
                }
            } header: {
                sectionHeader(group.status, count: group.items.count)
            }
        }
    }

    private func sectionHeader(_ status: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(StatusStyle.color(status))
                .frame(width: 7, height: 7)
            Text(status)
            Text("\(count)")
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private func totalNodes(_ nodes: [WorkitemNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + totalNodes($1.children) }
    }

    // MARK: 工具条

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation { treeMode.toggle() }
                if treeMode && expanded.isEmpty {
                    expanded = defaultExpandedIDs
                }
            } label: {
                Image(systemName: treeMode ? "flowchart" : "list.bullet")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { creating = true } label: { Image(systemName: "plus") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            statusFilterMenu
        }
    }

    private var statusFilterMenu: some View {
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

    private var defaultExpandedIDs: Set<String> {
        var result = Set<String>()
        for parent in items where parent.isRoot {
            for child in items where child.parentIdentifier == parent.id {
                if !StatusStyle.isDone(child.statusName) {
                    result.insert(parent.id)
                    break
                }
            }
        }
        return result
    }

    // MARK: 覆盖层

    @ViewBuilder
    private var overlayView: some View {
        if !settings.configured {
            ContentUnavailableView("还没配云效令牌", systemImage: "key",
                                   description: Text("去「设置」填一下令牌"))
        } else if loading && items.isEmpty {
            ProgressView("读取中…")
        } else if let error, items.isEmpty {
            ContentUnavailableView("读不到工作项", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        }
    }

    // MARK: 树构建

    private var treeNodes: [WorkitemNode] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let childrenMap = Dictionary(grouping: shown.filter { !$0.isRoot }) { $0.parentIdentifier ?? "" }

        func makeNode(_ item: Workitem) -> WorkitemNode {
            let kids = (childrenMap[item.id] ?? [])
                .sorted { $0.serialNumber < $1.serialNumber }
                .map(makeNode)
            return WorkitemNode(item: item, children: kids)
        }

        let roots = shown
            .filter { $0.isRoot || byID[$0.parentIdentifier ?? ""] == nil }
            .sorted { $0.serialNumber < $1.serialNumber }
        return roots.map(makeNode)
    }

    // MARK: 数据

    private func load() async {
        guard settings.configured else { return }
        loading = true
        defer { loading = false }
        do {
            let fresh = try await client.searchTree(category: category.rawValue)
            items = fresh
            statuses = Array(Set(fresh.map(\.statusName))).sorted { StatusStyle.order($0) < StatusStyle.order($1) }
            if treeMode && expanded.isEmpty {
                expanded = defaultExpandedIDs
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 行

struct IssueRow: View {
    let item: Workitem
    var isChild = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isChild {
                Text("└")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
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

    static func isDone(_ status: String) -> Bool {
        status.contains("完成") || status.contains("关闭") || status.contains("已解决")
    }

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

// MARK: - 树行

struct TreeNodeRow: View {
    let node: WorkitemNode
    @Binding var expanded: Set<String>
    let depth: Int

    var body: some View {
        let isOpen = expanded.contains(node.item.id)
        Group {
            if depth == 0 || isOpen {
                NavigationLink(value: node.item) {
                    HStack(alignment: .top, spacing: 8) {
                        if !node.children.isEmpty {
                            Button {
                                if isOpen { expanded.remove(node.item.id) }
                                else { expanded.insert(node.item.id) }
                            } label: {
                                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("").frame(width: 14)
                        }
                        IssueRow(item: node.item, isChild: depth > 0)
                    }
                }
                .padding(.leading, CGFloat(depth) * 16)
            }
            if isOpen {
                ForEach(node.children) { child in
                    TreeNodeRow(node: child, expanded: $expanded, depth: depth + 1)
                }
            }
        }
    }
}
