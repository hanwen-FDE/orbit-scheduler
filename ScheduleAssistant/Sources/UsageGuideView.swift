import SwiftUI

/// 使用说明页面（与新版免确认流程、三行卡片、设置入口保持一致）
struct UsageGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("① 输入方式", """
文字：在“对话”页底部输入框直接打字，点箭头发送。

语音：点右侧麦克风开始说话，再点高亮按钮结束，识别后自动发送。

图片：点左侧 ＋ 选择「照片」或「相机」，选取含日程信息的图片（课程表、会议通知等）。

批量录入：多行文字一次粘贴，每行写一项日程，例如：
9月10日 8:30 开幕式
9月10日 10:00 专题报告
9月10日 14:00 分组讨论
会逐项识别并直接写入日历。

整场会议：直接说「XX会议，9月10日 8点到18点」，会生成一项完整日程。
""")
                section("② 日程卡片", """
说得清楚就直接写入 Apple 日历，无需再次确认：

• 点卡片：修改标题、时间、地点或重复规则
• 点卡片右上角「…」：编辑详情、同步到系统提醒事项、移动日历或删除
• 🔔 第 3 行滑动开关：要不要提醒；点亮后可点橙色时长切换“提前 15 分钟 / 1 小时 / 1 天”等
• 出现「时间重叠」提示时：Orbit 不会私自改动你的时间；可一键点“改为 XX:XX”采用建议，或进编辑页手动调整
""")
                section("③ 重复日程", """
说“每周三下午 3 点开组会”或在编辑页设置“重复”，会建立 Apple 日历的循环事件。

删除循环日程时可选择只删当前一次，或删当前及后续。
""")
                section("④ 主题配色", """
左上角头像 → 「主题配色」：灰+蓝（默认）、石墨+靛蓝、炭灰+松绿等多套配色，App 内按钮和卡片强调色会即时跟随。
""")
                section("⑤ 设置 API Key", """
AI 识别需要大模型的 API Key：

1. 左上角头像 → 设置 → AI 识别
2. 选择服务商（智谱、DeepSeek、Kimi、通义千问、OpenAI 均已预设接口地址和默认模型）
3. 粘贴 API Key → 点「测试连接」，显示 ✓ 即成功

高级用户可在同一页修改接口地址和模型名，或选“自定义（OpenAI 兼容）”。API Key 保存在本机 iPhone Keychain 中。
""")
                section("⑥ 简报设置", """
早报：起床后 30 分钟自动推送到对话窗口，汇总天气（可选）、今天的安排和冲突。

晚报：睡前 30 分钟总结今天有几项任务、还剩几项。

时间都由“默认设置”里的作息自动推算，无需手动设置。开关在头像 → 「简报设置」中。
""")
                section("⑦ 通知与跳转", """
右上角铃铛保存日程提醒、每日简报、时间冲突等信息；点击通知条目可直接跳转到对应的日程卡片进行修改。

对话页右上角日历图标可打开“今天”页，按时间展示 Apple 日历中的当天安排，可左右翻页查看前后几天。
""")
                section("⑧ 常见问题", """
• 提醒不弹出：检查系统「设置 → 通知 → Orbit」是否允许通知，以及日历账户的提醒是否开启。

• 本 App 通过免费开发者签名安装，有效期 7 天；到期后用电脑 Sideloadly 重新安装一次即可（聊天记录和日程都在）。

• 日程同时存在于系统日历 App 中，可随时在系统日历查看、编辑。

• 反馈：头像 → 设置 → 联系我们。
""")
            }
            .padding()
        }
        .navigationTitle("使用说明")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        }
    }
}

/// 首次教学：轮播式提问作息 → 自动推算简报时间 → 输入方式体验 → 开始使用。
struct OnboardingView: View {
    @ObservedObject private var app = AppSettings.shared
    @State private var page = 0
    @State private var demoText: String?
    let onComplete: (String?) -> Void

    private let totalPages = 7

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Orbit").font(.headline)
                Spacer()
                Button("跳过") { onComplete(nil) }
            }
            .padding()

            TabView(selection: $page) {
                // 第 1 页：起床时间（滚轮选择）
                timeQuestionPage(
                    icon: "sun.horizon.fill",
                    title: "你平时几点起床？",
                    subtitle: "用下面的滚轮选好就可以滑到下一页",
                    time: wakeTime
                ).tag(0)

                // 第 2 页：睡觉时间
                timeQuestionPage(
                    icon: "moon.zzz.fill",
                    title: "你平时几点睡觉？",
                    subtitle: "Orbit 会避免在这两段时间之外给出重排建议",
                    time: sleepTime
                ).tag(1)

                // 第 3 页：确认自动推算的简报时间
                VStack(spacing: 22) {
                    onboardingHeader(
                        icon: "newspaper.fill",
                        title: "每天两份简报",
                        detail: "根据你的作息自动安排，不需要手动设置时间"
                    )
                    VStack(spacing: 10) {
                        briefingRow(icon: "sun.max.fill", name: "晨间早报",
                                    time: app.morningBriefingTime,
                                    desc: "起床后 30 分钟，汇总今天的安排")
                        briefingRow(icon: "moon.stars.fill", name: "每日晚报",
                                    time: app.eveningBriefingTime,
                                    desc: "睡前 30 分钟，总结今天完成了几项任务")
                    }
                    .padding(.horizontal, 30)
                }
                .padding(30).tag(2)

                // 第 4 页：文字输入（可一键试用示例）
                VStack(spacing: 22) {
                    onboardingHeader(
                        icon: "text.bubble.fill",
                        title: "打字就能排日程",
                        detail: "说清楚时间做的事就行，识别后直接写进日历，不用再点确认"
                    )
                    Button {
                        demoText = "明天上午10点 门诊随访"
                    } label: {
                        Label(demoText == nil ? "点一下试试这句话" : "已就绪：明天上午10点 门诊随访",
                              systemImage: demoText == nil ? "hand.tap" : "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(orbitAccent().opacity(0.14)))
                            .foregroundStyle(orbitAccent())
                    }
                    Text("开始使用后会自动发送，体验一次完整的识别流程")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(30).tag(3)

                // 第 5 页：语音输入
                onboardingPage(
                    icon: "waveform.circle.fill",
                    title: "语音输入",
                    detail: "对话页点右侧麦克风说话，例如“明天下午三点和王医生开会，提前半小时提醒”，松手即自动识别。"
                ).tag(4)

                // 第 6 页：图片输入
                onboardingPage(
                    icon: "photo.on.rectangle.fill",
                    title: "图片批量录入",
                    detail: "课程表、会议通知拍照或截图，点 ＋ 选「照片 / 相机」，Orbit 会逐行识别成日程。"
                ).tag(5)

                // 第 7 页：日历权限 + 开始
                VStack(spacing: 22) {
                    onboardingHeader(
                        icon: "calendar.badge.checkmark",
                        title: "连接 Apple 日历",
                        detail: "需要完全访问才能展示今天的安排和识别冲突；Orbit 不会建立重复的日历。"
                    )
                    Button("允许日历访问") {
                        Task { _ = await CalendarService.shared.ensureAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(orbitAccent())
                }
                .padding(30).tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(page == totalPages - 1 ? "开始使用 Orbit" : "继续") {
                if page == totalPages - 1 {
                    Task {
                        let morning = app.morningBriefingTime
                        let evening = app.eveningBriefingTime
                        _ = await MorningBriefingScheduler.enable(hour: morning.hour, minute: morning.minute)
                        _ = await EveningBriefingScheduler.enable(hour: evening.hour, minute: evening.minute)
                    }
                    onComplete(demoText)
                } else {
                    withAnimation { page += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(orbitAccent())
            .controlSize(.large)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func timeQuestionPage(icon: String, title: String, subtitle: String, time: Binding<Date>) -> some View {
        VStack(spacing: 18) {
            onboardingHeader(icon: icon, title: title, detail: subtitle)
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: 240)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
        }
        .padding(30)
    }

    private func briefingRow(icon: String, name: String, time: (hour: Int, minute: Int), desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(orbitAccent())
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(name).font(.headline)
                    Text(String(format: "%02d:%02d", time.hour, time.minute))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(orbitAccent())
                }
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground)))
    }

    private func onboardingPage(icon: String, title: String, detail: String) -> some View {
        onboardingHeader(icon: icon, title: title, detail: detail).padding(30)
    }

    private func onboardingHeader(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon).font(.system(size: 56)).foregroundStyle(orbitAccent())
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(detail).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var wakeTime: Binding<Date> {
        Binding(
            get: {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = app.wakeHour
                components.minute = app.wakeMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                app.wakeHour = Calendar.current.component(.hour, from: date)
                app.wakeMinute = Calendar.current.component(.minute, from: date)
            }
        )
    }

    private var sleepTime: Binding<Date> {
        Binding(
            get: {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = app.sleepHour
                components.minute = app.sleepMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                app.sleepHour = Calendar.current.component(.hour, from: date)
                app.sleepMinute = Calendar.current.component(.minute, from: date)
            }
        )
    }
}
