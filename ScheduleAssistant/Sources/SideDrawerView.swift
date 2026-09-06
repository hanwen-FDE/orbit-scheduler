import SwiftUI
import EventKit

/// 左上角用户面板（侧边抽屉）
struct SideDrawerView: View {
    @EnvironmentObject private var chat: ChatStore
    @EnvironmentObject private var settings: LLMSettings
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var app = AppSettings.shared

    var body: some View {
        NavigationStack {
            List {
                iconSection
                apiSection
                calendarSection
                Section {
                    NavigationLink("使用说明") { UsageGuideView() }
                }
            }
            .navigationTitle("Orbit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - 图标

    private var iconSection: some View {
        Section("App 图标") {
            let icons = IconService.allIcons
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                ForEach(icons, id: \.name) { icon in
                    Button {
                        IconService.apply(icon.name)
                        app.alternateIcon = icon.name
                    } label: {
                        VStack(spacing: 6) {
                            IconService.previewImage(named: icon.name)
                                .resizable()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            Text(icon.title)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                            if app.alternateIcon == icon.name {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - API

    private var apiSection: some View {
        Section {
            Picker("识别服务商", selection: $settings.activeProviderId) {
                ForEach(settings.providers, id: \.id) { p in
                    Text(p.name).tag(p.id)
                }
            }
            if let active = settings.providers.first(where: { $0.id == settings.activeProviderId }) {
                ProviderConfigView(provider: active)
            }
        } header: {
            Text("AI 识别（API）")
        } footer: {
            Text("智谱 API Key 在 open.bigmodel.cn 申请。")
        }
    }

    // MARK: - 默认日历与提醒

    private var calendarSection: some View {
        Section("默认日历与提醒") {
            Picker("默认日历", selection: $app.defaultCalendarId) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(CalendarService.shared.availableCalendars(), id: \.calendarIdentifier) { cal in
                    Text(cal.title).tag(Optional(cal.calendarIdentifier))
                }
            }
            Picker("默认提醒", selection: $app.defaultReminderMinutes) {
                ForEach(ReminderOption.allCases) { option in
                    Text(option.label).tag(option.minutes ?? 0)
                }
            }
        }
    }
}
