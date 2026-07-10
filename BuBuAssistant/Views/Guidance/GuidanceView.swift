//
//  GuidanceView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-07-10.
//  指导视图 - 悬浮指导窗内容：截图提问、步骤展示、多轮追问
//

import SwiftUI
import MarkdownUI

struct GuidanceView: View {
    @ObservedObject var viewModel: GuidanceViewModel
    var onClose: () -> Void

    @State private var inputText = ""
    @State private var hasPermission = true

    var body: some View {
        VStack(spacing: 0) {
            header
            if !viewModel.goal.isEmpty {
                goalChip
            }
            if !hasPermission {
                permissionBanner
            }
            conversationArea
            footer
        }
        .frame(width: 360, height: 560)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.bubbleRadius)
                .fill(BuBuColors.creamWhite)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.18), radius: 20, x: 0, y: 10)
        )
        .onAppear {
            hasPermission = ScreenshotService.shared.hasScreenCapturePermission()
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image("bubu")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)

            Text("布布指导")
                .font(BuBuFonts.headline)
                .foregroundColor(BuBuColors.chocolateBrown)

            Spacer()

            // 朗读控制：播放中点击停止；否则切换自动朗读开关
            Button {
                if viewModel.speech.isSpeaking {
                    viewModel.speech.stopSpeaking()
                } else {
                    viewModel.autoSpeak.toggle()
                }
            } label: {
                Image(systemName: speakerIconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(
                        viewModel.speech.isSpeaking || viewModel.autoSpeak
                            ? BuBuColors.skyBlue
                            : BuBuColors.chocolateBrown.opacity(0.4)
                    )
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .help(viewModel.speech.isSpeaking ? "停止朗读" : (viewModel.autoSpeak ? "关闭自动朗读" : "开启自动朗读"))

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - 目标 chip

    private var goalChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "flag.fill")
                .font(.system(size: 10))
            Text("目标：\(viewModel.goal)")
                .font(BuBuFonts.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.smallRadius)
                .fill(BuBuColors.mintGreen.opacity(0.25))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - 权限提示

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(BuBuColors.coralPink)
            VStack(alignment: .leading, spacing: 2) {
                Text("需要「屏幕录制」权限才能截图")
                    .font(BuBuFonts.caption)
                Text("授权后需重启布布生效")
                    .font(BuBuFonts.tiny)
                    .opacity(0.6)
            }
            .foregroundColor(BuBuColors.chocolateBrown)
            Spacer()
            Button("去授权") {
                ScreenshotService.shared.requestScreenCapturePermission()
                ScreenshotService.shared.openScreenRecordingSettings()
            }
            .font(BuBuFonts.caption)
            .buttonStyle(.plain)
            .foregroundColor(BuBuColors.skyBlue)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.smallRadius)
                .fill(BuBuColors.coralPink.opacity(0.12))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - 对话区

    private var conversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !viewModel.hasSession && !viewModel.isStreaming {
                        emptyState
                    }

                    ForEach(viewModel.entries) { entry in
                        entryView(entry)
                    }

                    if viewModel.isStreaming {
                        streamingView
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(BuBuFonts.caption)
                            .foregroundColor(BuBuColors.coralPink)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: BuBuShapes.smallRadius)
                                    .fill(BuBuColors.coralPink.opacity(0.10))
                            )
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.currentReply) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: viewModel.entries.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image("bubu")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
            Text("遇到不会的操作？截图问布布")
                .font(BuBuFonts.headline)
                .foregroundColor(BuBuColors.chocolateBrown)
            Text("布布看得懂你的屏幕，一步步教你操作")
                .font(BuBuFonts.caption)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func entryView(_ entry: GuidanceEntry) -> some View {
        if entry.role == .user {
            HStack {
                Spacer(minLength: 40)
                HStack(spacing: 5) {
                    if entry.hasScreenshot {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10))
                            .opacity(0.7)
                    }
                    Text(entry.text)
                        .font(BuBuFonts.caption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                        .fill(BuBuColors.skyBlue)
                )
            }
        } else {
            Markdown(entry.text)
                .markdownTheme(.bubuTheme)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .bubuCard()
        }
    }

    private var streamingView: some View {
        Group {
            if viewModel.currentReply.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("布布正在观察截图…")
                        .font(BuBuFonts.caption)
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
                }
                .padding(12)
            } else {
                Markdown(viewModel.currentReply)
                    .markdownTheme(.bubuTheme)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .bubuCard()
            }
        }
    }

    // MARK: - 底部操作区

    private var footer: some View {
        VStack(spacing: 8) {
            // 输入行：补充说明 + 文字追问
            HStack(spacing: 8) {
                TextField(
                    viewModel.hasSession ? "补充说明或追问…" : "你想做什么？（可选）",
                    text: $inputText
                )
                .textFieldStyle(.plain)
                .font(BuBuFonts.body)
                .foregroundColor(BuBuColors.chocolateBrown)
                .bubuInput()
                .onSubmit { sendFollowUp() }

                // 语音输入：点击开始识别（实时转文字到输入框），再点停止
                Button {
                    toggleVoiceInput()
                } label: {
                    Image(systemName: viewModel.speech.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 13))
                        .foregroundColor(viewModel.speech.isRecording ? .white : BuBuColors.chocolateBrown.opacity(0.6))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(
                                viewModel.speech.isRecording
                                    ? BuBuColors.coralPink
                                    : Color.white
                            )
                        )
                        .shadow(
                            color: viewModel.speech.isRecording
                                ? BuBuColors.coralPink.opacity(0.45)
                                : BuBuColors.chocolateBrown.opacity(0.08),
                            radius: viewModel.speech.isRecording ? 8 : 4,
                            x: 0, y: 2
                        )
                }
                .buttonStyle(.plain)
                .help(viewModel.speech.isRecording ? "停止语音输入" : "语音输入")

                if viewModel.hasSession {
                    Button {
                        sendFollowUp()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(BuBuColors.skyBlue))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isStreaming || inputText.isEmpty)
                    .opacity(viewModel.isStreaming || inputText.isEmpty ? 0.5 : 1)
                }
            }

            // 主操作：截图提问 / 看下一步
            Button {
                captureAndAsk()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                    Text(viewModel.hasSession ? "完成了，看下一步" : "截图提问")
                }
                .font(BuBuFonts.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                        .fill(BuBuColors.skyBlue)
                        .shadow(color: BuBuColors.skyBlue.opacity(0.35), radius: 10, x: 0, y: 5)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isStreaming || viewModel.isCapturing)
            .opacity(viewModel.isStreaming || viewModel.isCapturing ? 0.6 : 1)

            // 次要操作与隐私提示
            HStack {
                if viewModel.hasSession {
                    Button("结束指导") {
                        viewModel.reset()
                    }
                    .buttonStyle(.plain)
                    .font(BuBuFonts.caption)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.55))
                }
                Spacer()
                Text("截图仅用于本次提问，不会保存")
                    .font(BuBuFonts.tiny)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
            }
        }
        .padding(16)
    }

    // MARK: - 计算属性

    private var speakerIconName: String {
        if viewModel.speech.isSpeaking {
            return "speaker.wave.2.fill"
        }
        return viewModel.autoSpeak ? "speaker.wave.2" : "speaker.slash"
    }

    // MARK: - 动作

    private func toggleVoiceInput() {
        Task {
            await viewModel.toggleVoiceInput { text in
                inputText = text
            }
        }
    }

    private func captureAndAsk() {
        let question = inputText
        inputText = ""
        Task {
            await viewModel.askWithScreenshot(question: question)
        }
    }

    private func sendFollowUp() {
        let question = inputText
        inputText = ""
        Task {
            await viewModel.askFollowUp(question: question)
        }
    }
}

// MARK: - 预览

#Preview {
    GuidanceView(viewModel: GuidanceViewModel(), onClose: {})
        .padding(20)
        .background(Color.gray.opacity(0.2))
}
