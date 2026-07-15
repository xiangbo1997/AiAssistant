//
//  ChatView.swift
//  BuBuAssistant
//
//  与布布进行多轮流式聊天的主面板
//

import SwiftUI
import MarkdownUI

struct ChatView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var spriteViewModel: SpriteViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider().opacity(0.55)
            conversation
            composer
        }
        .background(BuBuColors.warmGradient)
        .onAppear {
            viewModel.attach(spriteViewModel: spriteViewModel)
            inputFocused = true
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .shadow(color: BuBuColors.skyBlue.opacity(0.22), radius: 6, x: 0, y: 3)
                Image("bubu")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("和布布聊天")
                    .font(BuBuFonts.headline)
                    .foregroundColor(BuBuColors.chocolateBrown)
                Text(viewModel.isStreaming ? viewModel.expression.title : "\(settingsViewModel.currentProvider.displayName) · \(settingsViewModel.currentLLMConfig.model)")
                    .font(BuBuFonts.tiny)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            if !viewModel.messages.isEmpty || viewModel.isStreaming {
                Button {
                    viewModel.clearConversation()
                } label: {
                    Label("新对话", systemImage: "plus.bubble")
                        .font(BuBuFonts.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(BuBuColors.skyBlue)
                .help("清空当前会话")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(BuBuColors.creamWhite.opacity(0.94))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        welcomeView
                    } else {
                        ForEach(viewModel.messages) { message in
                            ChatMessageRow(message: message)
                                .id(message.id)
                        }
                    }

                    if viewModel.isStreaming {
                        StreamingChatRow(text: viewModel.currentReply)
                        .id("streaming-reply")
                    }

                    if let error = viewModel.errorMessage {
                        errorCard(error)
                            .id("chat-error")
                    }

                    Color.clear.frame(height: 1).id("chat-bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.currentReply) { _, _ in
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: viewModel.errorMessage) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 16)

            BuBuChatAvatar(size: 58)

            Text("嗨，我是布布")
                .font(BuBuFonts.title)
                .foregroundColor(BuBuColors.chocolateBrown)

            Text("想聊心情、工作、灵感，或者只是随便说说都可以。\n我会一边听你说，一边做出回应哦。")
                .font(BuBuFonts.body)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.66))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            VStack(spacing: 8) {
                suggestion("今天过得怎么样？", icon: "sun.max")
                suggestion("陪我聊聊最近的心情", icon: "heart")
                suggestion("给我讲一个轻松的小故事", icon: "book.closed")
            }
            .frame(maxWidth: 330)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }

    private func suggestion(_ text: String, icon: String) -> some View {
        Button {
            draft = text
            sendDraft()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundColor(BuBuColors.skyBlue)
                Text(text)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.82))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.35))
            }
            .font(BuBuFonts.caption)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.88))
                    .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 5, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(BuBuColors.coralPink)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(BuBuFonts.caption)
                    .foregroundColor(BuBuColors.coralPink)
                    .textSelection(.enabled)
                Button("打开设置") {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
                .buttonStyle(.link)
                .font(BuBuFonts.tiny)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BuBuColors.coralPink.opacity(0.10))
        )
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("和布布说点什么…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(BuBuFonts.body)
                .lineLimit(1...4)
                .focused($inputFocused)
                .disabled(viewModel.isStreaming)
                .onSubmit(sendDraft)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.white)
                        .shadow(color: BuBuColors.chocolateBrown.opacity(0.08), radius: 7, x: 0, y: 3)
                )

            Button {
                viewModel.isStreaming ? viewModel.stopGenerating() : sendDraft()
            } label: {
                Image(systemName: viewModel.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle().fill(viewModel.isStreaming ? BuBuColors.coralPink : BuBuColors.skyBlue)
                    )
                    .shadow(
                        color: (viewModel.isStreaming ? BuBuColors.coralPink : BuBuColors.skyBlue).opacity(0.30),
                        radius: 7,
                        x: 0,
                        y: 4
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isStreaming && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(viewModel.isStreaming ? "停止生成" : "发送")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            BuBuColors.creamWhite
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 8, x: 0, y: -3)
        )
    }

    private func sendDraft() {
        let text = draft
        if viewModel.send(text) {
            draft = ""
        }
        inputFocused = true
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 54) }

            if message.role == .assistant {
                assistantAvatar
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Group {
                    if message.role == .assistant {
                        Markdown(message.content)
                            .markdownTheme(.bubuTheme)
                            .textSelection(.enabled)
                    } else {
                        Text(message.content)
                            .font(BuBuFonts.body)
                            .textSelection(.enabled)
                    }
                }
                .foregroundColor(message.role == .user ? .white : BuBuColors.chocolateBrown)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(bubbleBackground)

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(BuBuFonts.tiny)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.35))
            }

            if message.role == .assistant { Spacer(minLength: 34) }
        }
    }

    private var assistantAvatar: some View {
        ZStack {
            Circle().fill(Color.white)
            Image("bubu")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(3)
        }
        .frame(width: 30, height: 30)
        .shadow(color: BuBuColors.chocolateBrown.opacity(0.10), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(message.role == .user ? AnyShapeStyle(BuBuColors.skyBlue) : AnyShapeStyle(Color.white))
            .shadow(color: BuBuColors.chocolateBrown.opacity(0.07), radius: 6, x: 0, y: 3)
    }
}

private struct StreamingChatRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            BuBuChatAvatar(size: 31)

            VStack(alignment: .leading, spacing: 6) {
                if text.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(BuBuColors.skyBlue.opacity(0.75))
                                .frame(width: 6, height: 6)
                                .modifier(ChatTypingDot(delay: Double(index) * 0.16))
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Markdown(text)
                        .markdownTheme(.bubuTheme)
                        .textSelection(.enabled)
                }
            }
            .foregroundColor(BuBuColors.chocolateBrown)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: BuBuColors.skyBlue.opacity(0.12), radius: 7, x: 0, y: 3)
            )

            Spacer(minLength: 34)
        }
    }
}

private struct ChatTypingDot: ViewModifier {
    let delay: Double
    @State private var raised = false

    func body(content: Content) -> some View {
        content
            .offset(y: raised ? -3 : 2)
            .animation(
                .easeInOut(duration: 0.48).repeatForever(autoreverses: true).delay(delay),
                value: raised
            )
            .onAppear { raised = true }
    }
}

private struct BuBuChatAvatar: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.96))
            Image("bubu")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(size * 0.08)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(BuBuColors.skyBlue.opacity(0.22), lineWidth: 1))
        .shadow(color: BuBuColors.chocolateBrown.opacity(0.10), radius: 4, x: 0, y: 2)
        .accessibilityLabel("布布")
    }
}

#Preview {
    ChatView()
        .environmentObject(ChatViewModel())
        .environmentObject(SpriteViewModel())
        .environmentObject(SettingsViewModel())
        .frame(width: 480, height: 600)
}
