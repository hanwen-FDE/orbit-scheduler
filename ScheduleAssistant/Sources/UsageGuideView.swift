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
• 点卡片右上角「…」：直接编辑或删除这项日程；删除会同步删除系统日历事件
• 🔔 开关：要不要提醒
• 点橙色时长：准时 / 提前 5、15、30、60、120 分钟 / 提前 1 天
• 「更改目标日历」：把这项日程移到其他日历，也可设定今后新日程的默认日历
• 「同步到系统提醒事项」：为这项日程额外建立一条苹果“提醒事项”，需要时可一键取消同步
• 出现「时间冲突」时：Orbit 不会私自改动你的时间；你可点“采用建议”或进编辑页手动调整
""")
                section("③ 循环日程与习惯", """
日程：说“每周三下午 3 点开组会”或在编辑页设置“循环”，会建立系统日历的循环事件。

习惯：点底部 ＋ →「习惯」，例如“每天 22:30 睡前阅读”。习惯是可勾选完成的循环提醒，会写入苹果“提醒事项”App，而不是 Orbit 内部再造一个待办清单。

删除循环日程时可选择只删当前一次，或删当前及后续；系统日历中已有的后续循环不会被 Orbit 自动移动。
""")
                section("④ 设置默认日历", """
点左上角头像 → 「默认日历与提醒」：

• 默认日历：新日程自动写入哪个日历（家庭、工作等）
• 默认提醒：新日程默认提前多久提醒
""")
                section("⑤ 设置 API Key", """
AI 识别需要大模型的 API Key：

1. 打开 open.bigmodel.cn 注册智谱账号
2. 控制台 → API Keys → 创建并复制
3. 回到本 App：左上角头像 → 「AI 识别（API）」→ 粘贴 Key → 点「测试连接」，显示 ✓ 即成功

也支持 OpenAI 及任意 OpenAI 兼容接口（DeepSeek、Kimi 等）：切换服务商后填写接口地址和模型名。API Key 会保存在本机 iPhone Keychain 中，不会作为普通偏好设置保存。
""")
                section("⑥ 晨间简报、Widget 与快捷指令", """
左上角头像 →「晨间简报」：可设置打开 App 时显示今日安排、主动允许后显示本地天气，以及每天的本地提醒时间。

主屏幕长按 → 编辑 → 添加小组件 → Orbit：添加“快速记录”小组件，一点即可进入输入框。

在「快捷指令」App 中搜索 Orbit，可添加“快速记录日程”和“查看今日日程”，也能用于 Siri 和 Spotlight。
""")
                section("⑦ 日程管理", """
主页右上角「日程」：按时间查看全部日程，点击修改，左滑删除（同步删除日历事件）。
""")
                section("⑧ 常见问题", """
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
