import SwiftUI
import PhotosUI
import Combine

/// 聊天主界面
struct ChatView: View {
    @EnvironmentObject private var chat: ChatStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var speech = SpeechService()
    @StateObject private var briefing = DailyBriefingStore()
    @ObservedObject private var app = AppSettings.shared
    var onClose: (() -> Void)? = nil

    private enum InputMode { case voice, keyboard }
    @State private var inputMode: InputMode = .voice
    @State private var inputText = ""
    @State private var showPlusPanel = false
    @State private var showDrawer = false
    @State private var showNotifications = false
    @State private var editingMessage: ChatMessage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var hasScrolledToRestoredMessages = false
    @State private var discardCurrentRecording = false
    @State private var recordingStartedAt: Date?
    @State private var recordingSeconds = 0
    @FocusState private var inputFocused: Bool

    private static let chatBottomAnchor = "orbit-chat-bottom"

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                messageList
                inputBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        if let onClose {
                            Button(action: onClose) {
                                Image(systemName: "chevron.backward")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(orbitAccent())
                            }
                            .accessibilityLabel("回到今天")
                        }
                        Button { showDrawer = true } label: {
                            OrbitBrandMark()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBellButton(isPresented: $showNotifications)
                }
            }
        }
        .orbitEdgeSwipeBack { onClose?() }
        .sheet(isPresented: $showDrawer) { SideDrawerView() }
        .sheet(isPresented: $showNotifications) { OrbitNotificationCenterView() }
        .sheet(isPresented: $showPlusPanel) { plusPanel }
        .sheet(isPresented: $showCamera) { CameraPicker { sendImage($0) } }
        .sheet(item: $editingMessage) { msg in
            if let snap = msg.event {
                EventDetailSheet(messageId: msg.id, snapshot: snap)
            }
        }
        .onAppear {
            refreshBriefingAndHandleShortcut()
            openPendingFocusIfNeeded()
        }
        .onChange(of: chat.pendingFocusMessageId) { _, _ in
            openPendingFocusIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshBriefingAndHandleShortcut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .orbitShortcutRequested)) { _ in
            handleShortcutRequest()
        }
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(chat.messages) { msg in
                        MessageRow(
                            message: msg,
                            onTapCard: { editingMessage = msg },
                            onOpenToday: { onClose?() }
                        )
                        .id(msg.id)
                    }
                    // 用固定锚点而不是最后一条消息本身，确保最后一条消息
                    // 可以完整露出在输入栏上方。
                    Color.clear
                        .frame(height: 1)
                        .id(Self.chatBottomAnchor)
                }
                .padding()
                .padding(.bottom, 92)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                // 持久化的消息在 ChatStore 初始化时已经载入，因此不会触发
                // onChange。延迟到首个布局周期后再滚到底部。
                guard !hasScrolledToRestoredMessages else { return }
                hasScrolledToRestoredMessages = true
                DispatchQueue.main.async {
                    proxy.scrollTo(Self.chatBottomAnchor, anchor: .bottom)
                }
            }
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation { proxy.scrollTo(Self.chatBottomAnchor, anchor: .bottom) }
            }
            .onChange(of: scenePhase) { _, phase in
                // 从后台回到 App 时，SwiftUI 可能会恢复到 ScrollView 的起点；
                // 此处保证用户回到的是最近一段对话。
                guard phase == .active else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(Self.chatBottomAnchor, anchor: .bottom)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .onTapGesture { inputFocused = false }
    }

    // MARK: - 底部输入栏（纯白三分区胶囊：＋ / 主输入 / 键盘或语音）

    private var inputBar: some View {
        HStack(spacing: 0) {
            Button {
                inputFocused = false
                showPlusPanel = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(orbitAccent())
                    .frame(width: 54, height: 62)
            }
            .buttonStyle(.plain)

            inputDivider
            if inputMode == .voice {
                voiceSegment
            } else {
                keyboardSegment
            }
            inputDivider
            modeToggle
        }
        .frame(minHeight: 62)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        )
        .clipShape(Capsule(style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onChange(of: speech.isRecording) { old, new in
            if old && !new {
                let transcript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !discardCurrentRecording && !transcript.isEmpty {
                    chat.send(voiceTranscript: transcript, duration: TimeInterval(recordingSeconds))
                }
                recordingStartedAt = nil
            }
        }
    }

    /// 语音态中间长条：点按开始/结束录音；录音中显示时长与转写。
    private var voiceSegment: some View {
        HStack(spacing: 10) {
            Button {
                if speech.isRecording {
                    speech.stop()
                } else {
                    discardCurrentRecording = false
                    recordingStartedAt = Date()
                    recordingSeconds = 0
                    speech.start()
                }
            } label: {
                if speech.isRecording {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(orbitAccent())
                        Text(String(format: "%d:%02d", recordingSeconds / 60, recordingSeconds % 60))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(orbitAccent())
                        Text(speech.transcript.isEmpty ? "正在聆听…" : speech.transcript)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(orbitAccent())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            if speech.isRecording {
                Button {
                    discardCurrentRecording = true
                    speech.stop()
                } label: {
                    Image(systemName: "trash")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.trailing, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: recordingStartedAt) {
            while speech.isRecording {
                try? await Task.sleep(for: .seconds(1))
                if speech.isRecording { recordingSeconds += 1 }
            }
        }
    }

    /// 键盘态中间长条：文本框 + 发送。
    private var keyboardSegment: some View {
        HStack(spacing: 8) {
            TextField("安排点什么？", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(sendText)
            if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: sendText) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(orbitAccent())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 62)
    }

    /// 右侧模式按钮：语音态显示键盘、键盘态显示麦克风。
    private var modeToggle: some View {
        Button {
            inputFocused = false
            if speech.isRecording { discardCurrentRecording = true; speech.stop() }
            inputMode = (inputMode == .voice) ? .keyboard : .voice
        } label: {
            Image(systemName: inputMode == .voice ? "keyboard" : "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(orbitAccent())
                .frame(width: 54, height: 62)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(inputMode == .voice ? "切换到键盘输入" : "切换到语音输入")
    }

    private var inputDivider: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.45))
            .frame(width: 1, height: 28)
    }

    // MARK: - ＋ 面板

    private var plusPanel: some View {
        VStack(spacing: 0) {
            Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 5)
                .padding(.top, 8)
            HStack(spacing: 28) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(orbitAccent())
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                        Text("照片").font(.footnote).foregroundStyle(orbitAccent())
                    }
                }
                Button {
                    showPlusPanel = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showCamera = true
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "camera")
                            .font(.system(size: 24))
                            .foregroundStyle(orbitAccent())
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                        Text("相机").font(.footnote).foregroundStyle(orbitAccent())
                    }
                }
            }
            .padding(.vertical, 26)
        }
        .presentationDetents([.height(170)])
        .background(Color(.systemBackground))
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            showPlusPanel = false
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    sendImage(ui)
                }
                photoItem = nil
            }
        }
    }

    // MARK: - 发送

    private func sendText() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        chat.send(text: trimmed)
    }

    private func sendImage(_ image: UIImage) {
        chat.send(image: image)
    }

    private func refreshBriefingAndHandleShortcut() {
        briefing.refresh()
        if app.morningBriefingEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                chat.upsertDailyBriefing(from: briefing)
            }
        }
        chat.upsertEveningBriefingIfDue(from: briefing)
        handleShortcutRequest()
    }

    /// Today/消息页可能在 ChatView 出现前就已指定目标卡片，因此 onAppear 也要主动消费。
    private func openPendingFocusIfNeeded() {
        guard let messageId = chat.pendingFocusMessageId,
              let target = chat.messages.first(where: { $0.id == messageId }) else { return }
        chat.pendingFocusMessageId = nil
        guard target.event != nil else { return }
        editingMessage = target
    }

    private func handleShortcutRequest() {
        guard let destination = OrbitShortcutRequest.consume() else { return }
        switch destination {
        case .compose:
            DispatchQueue.main.async { inputFocused = true }
        case .today:
            onClose?()
        }
    }
}

/// 相机拍照
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(_ onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
