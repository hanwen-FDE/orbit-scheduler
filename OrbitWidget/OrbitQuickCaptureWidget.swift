import SwiftUI
import WidgetKit

struct OrbitQuickCaptureEntry: TimelineEntry {
    let date: Date
}

struct OrbitQuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> OrbitQuickCaptureEntry {
        OrbitQuickCaptureEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (OrbitQuickCaptureEntry) -> Void) {
        completion(OrbitQuickCaptureEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OrbitQuickCaptureEntry>) -> Void) {
        // 这是一个零数据共享的快速入口 Widget。后续在正式 App Group 签名后，
        // 可扩展为读取共享的“今日日程”摘要，而不会在 Widget 中暴露完整聊天记录。
        let entry = OrbitQuickCaptureEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct OrbitQuickCaptureWidget: Widget {
    private let kind = "OrbitQuickCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OrbitQuickCaptureProvider()) { entry in
            OrbitQuickCaptureWidgetView(entry: entry)
        }
        .configurationDisplayName("Orbit 快速记录")
        .description("一键打开 Orbit，记录新的安排。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct OrbitQuickCaptureWidgetView: View {
    let entry: OrbitQuickCaptureEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Link(destination: URL(string: "orbit://compose")!) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: family == .systemSmall ? 28 : 34, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.indigo.opacity(0.14)))

                if family != .systemSmall {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Orbit")
                            .font(.headline)
                        Text("快速记录一个安排")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("快速")
                        Text("记录")
                    }
                    .font(.headline)
                }
            }
            .padding()
        }
        .containerBackground(for: .widget) {
            Color.indigo.opacity(0.08)
        }
    }
}
