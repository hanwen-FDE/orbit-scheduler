import SwiftUI

/// iCloud 同步单独放在“我的”分组中：设置与手动同步在同一处，避免抽屉首页膨胀。
struct ICloudSyncSettingsView: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var service = ICloudSyncService.shared

    var body: some View {
        List {
            Section {
                Toggle(isOn: $app.icloudSyncEnabled) {
                    Label("开启 iCloud 同步", systemImage: "icloud")
                        .foregroundStyle(orbitAccent())
                }
                .tint(orbitAccent())
                .onChange(of: app.icloudSyncEnabled) { enabled in
                    if enabled { Task { await service.syncNow() } }
                }

                if app.icloudSyncEnabled {
                    Button {
                        Task { await service.syncNow() }
                    } label: {
                        HStack {
                            Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(orbitAccent())
                            Spacer()
                            if service.isSyncing { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(service.isSyncing)
                }
            } header: {
                Text("iCloud 同步")
            } footer: {
                Text(app.icloudSyncEnabled
                     ? "对话与消息记录通过 iCloud 在你的设备间保持一致；日程始终存放在系统日历中。"
                     : "开启后，对话与消息记录会通过 iCloud 在你的设备间同步。")
            }

            if !service.lastResultText.isEmpty {
                Section("状态") {
                    Text(service.lastResultText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("iCloud 同步")
        .navigationBarTitleDisplayMode(.inline)
        .tint(orbitAccent())
    }
}
