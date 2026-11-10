import SwiftUI
import WidgetKit

/// 桌面和锁屏上的「新建工作项」按钮：点一下直接打开 App 的新建表单。
private let createLink = URL(string: "autoloop://create")!

struct CreateEntry: TimelineEntry {
    let date: Date
}

struct CreateProvider: TimelineProvider {
    func placeholder(in context: Context) -> CreateEntry {
        CreateEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CreateEntry) -> Void) {
        completion(CreateEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CreateEntry>) -> Void) {
        completion(Timeline(entries: [CreateEntry(date: .now)], policy: .never))
    }
}

struct CreateWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(createLink)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
        case .accessoryRectangular:
            Label("新建工作项", systemImage: "plus.circle.fill")
                .font(.headline)
        case .accessoryInline:
            Label("新建工作项", systemImage: "plus")
        default:
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.indigo)
                Text("新建工作项")
                    .font(.headline)
                Text("点一下直接填写")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CreateWidget: Widget {
    let kind = "CreateIssueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CreateProvider()) { _ in
            CreateWidgetView()
        }
        .configurationDisplayName("新建工作项")
        .description("点一下打开新建工作项表单。")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct AutoLoopWidgetBundle: WidgetBundle {
    var body: some Widget {
        CreateWidget()
    }
}
