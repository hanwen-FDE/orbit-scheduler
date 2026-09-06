import SwiftUI

/// 使用说明页面
struct UsageGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("① 输入方式", """
文字：在底部输入框直接打字，点箭头发送。

语音：点右侧麦克风开始说话，再点红色按钮结束，识别后自动发送。

图片：点左侧 ＋ 选择「照片」或「相机」，选取含日程信息的图片（课程表、会议通知等）。

批量录入：多行文字一次粘贴，每行写一项日程，例如：
9月10日 8:30 开幕式
9月10日 10:00 专题报告
9月10日 14:00 分组讨论
会逐项识别，每项生成一张卡片并写入日历。

整场会议：直接说「XX会议，9月10日 8点到18点」，会生成一项完整日程。
""")
                section("② 日程卡片", """
识别成功后自动写入默认日历，并出现一张日程卡片：

• 点卡片：修改标题、时间、地点，或删除
• 🔔 开关：要不要提醒
• 点橙色时长：准时 / 提前 5、15、30、60、120 分钟 / 提前 1 天
• 「修改日程」：把这项日程换到别的日历
""")
                section("③ 设置默认日历", """
点左上角头像 → 「默认日历与提醒」：

• 默认日历：新日程自动写入哪个日历（家庭、工作等）
• 默认提醒：新日程默认提前多久提醒
""")
                section("④ 设置 API Key", """
AI 识别需要大模型的 API Key：

1. 打开 open.bigmodel.cn 注册智谱账号
2. 控制台 → API Keys → 创建并复制
3. 回到本 App：左上角头像 → 「AI 识别（API）」→ 粘贴 Key → 点「测试连接」，显示 ✓ 即成功

也支持 OpenAI 及任意 OpenAI 兼容接口（DeepSeek、Kimi 等）：切换服务商后填写接口地址和模型名。
""")
                section("⑤ 日程管理", """
主页右上角「日程」：按时间查看全部日程，点击修改，左滑删除（同步删除日历事件）。
""")
                section("⑥ 常见问题", """
• 换图标：左上角头像 → App 图标，6 套可选。

• 提醒不弹出：检查系统「设置 → 通知 → Orbit」是否允许通知，以及日历账户的提醒是否开启。

• 本 App 通过免费开发者签名安装，有效期 7 天；到期后用电脑 Sideloadly 重新安装一次即可（聊天记录和日程都在）。

• 日程同时存在于系统日历 App 中，可随时在系统日历查看、编辑。
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
