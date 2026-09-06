import SwiftUI
import PhotosUI

/// 聊天主界面
struct ChatView: View {
    @EnvironmentObject private var chat: ChatStore
    @StateObject private var speech = SpeechService()

    @State private var inputText = ""
    @State private var showPlusPanel = false
    @State private var showDrawer = false
    @State private var showScheduleList = false
    @State private var editingMessage: ChatMessage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                inputBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDrawer = true } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("日程") { showScheduleList = true }
                        .font(.subheadline.bold())
                }
            }
        }
        .sheet(isPresented: $showDrawer) { SideDrawerView() }
        .sheet(isPresented: $showScheduleList) { ScheduleListView() }
        .sheet(isPresented: $showPlusPanel) { plusPanel }
        .sheet(isPresented: $showCamera) { CameraPicker { sendImage($0) } }
        .sheet(item: $editingMessage) { msg in
            if let snap = msg.event {
                EventDetailSheet(messageId: msg.id, snapshot: snap)
            }
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
                            onTapCard: { editingMessage = msg }
                        )
                        .id(msg.id)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .onTapGesture { inputFocused = false }
    }

    // MARK: - 底部输入栏

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button {
                inputFocused = false
                showPlusPanel = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.systemBackground)))
            }

            TextField("安排点什么？", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color(.systemBackground)))
                .focused($inputFocused)
                .onSubmit(sendText)

            if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: sendText) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.blue)
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    speech.toggle()
                } label: {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(speech.isRecording ? .red : .blue)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.15), value: inputText.isEmpty)
        .background {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            if speech.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(speech.transcript.isEmpty ? "正在聆听…点红色按钮结束" : speech.transcript)
                        .lineLimit(1).font(.footnote)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(.thinMaterial))
                .offset(y: -8)
            }
        }
        .onChange(of: speech.isRecording) { old, new in
            if old && !new {
                let transcript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !transcript.isEmpty { chat.send(text: transcript) }
            }
        }
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
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                        Text("照片").font(.footnote).foregroundStyle(.primary)
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
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                        Text("相机").font(.footnote).foregroundStyle(.primary)
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
