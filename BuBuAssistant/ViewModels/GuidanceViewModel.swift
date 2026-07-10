//
//  GuidanceViewModel.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-07-10.
//  指导视图模型 - 管理"截图求指导"的多轮会话状态
//

import SwiftUI
import Combine

// MARK: - 指导会话记录

/// 指导会话中展示用的一条记录
struct GuidanceEntry: Identifiable {
    let id = UUID()
    var role: ChatMessage.MessageRole
    var text: String
    var hasScreenshot: Bool
}

// MARK: - 指导视图模型

@MainActor
class GuidanceViewModel: ObservableObject {
    @Published var entries: [GuidanceEntry] = []
    @Published var goal = ""              // 会话目标（首条问题，显示在顶部 chip）
    @Published var currentReply = ""      // 流式生成中的回复
    @Published var isStreaming = false
    @Published var isCapturing = false
    @Published var errorMessage: String?

    /// 是否自动朗读布布的回复
    @Published var autoSpeak: Bool = UserDefaults.standard.object(forKey: "guidanceAutoSpeak") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSpeak, forKey: "guidanceAutoSpeak") }
    }

    /// 截图前后的窗口控制钩子（由 GuidanceWindow 注入：截图时隐藏窗口避免截到自己）
    var onCaptureWillStart: (() -> Void)?
    var onCaptureDidEnd: (() -> Void)?

    /// 语音服务（朗读 + 语音输入）
    let speech = SpeechService.shared

    /// 发送给 LLM 的完整对话历史
    private var history: [ChatMessage] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        // 转发语音服务的状态变化，驱动界面刷新（朗读/录音指示）
        speech.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// 屏幕操作指导专家的系统提示词
    private static let systemPrompt = """
    你是布布，一位耐心的屏幕操作指导专家。用户会发来屏幕截图和想完成的目标，你需要：
    1. 仔细观察截图中的界面元素（菜单、按钮、输入框的位置和文字）
    2. 用编号步骤告诉用户接下来怎么操作，每步指明具体位置（如"左上角菜单栏"、"弹窗右下角"）
    3. 一次只给到下一个关键节点（最多 3-4 步），等用户完成后再继续
    4. 语气友好简洁，像朋友一样鼓励用户
    如果截图信息不足以判断，明确说出你需要看到什么。
    """

    /// 会话是否已开始
    var hasSession: Bool { !entries.isEmpty }

    // MARK: - 交互入口

    /// 截图并提问（新会话首问或"完成了，看下一步"都走这里）
    func askWithScreenshot(question: String) async {
        guard !isStreaming, !isCapturing else { return }
        errorMessage = nil
        isCapturing = true

        // 隐藏指导窗后再截图，等待窗口淡出完成
        onCaptureWillStart?()
        try? await Task.sleep(nanoseconds: 250_000_000)

        let imageData = await ScreenshotService.shared.captureInteractive()

        onCaptureDidEnd?()
        isCapturing = false

        // 用户按 Esc 取消截图
        guard let imageData else { return }

        let effectiveQuestion = question.isEmpty ? "请看截图，告诉我下一步怎么操作" : question
        if goal.isEmpty { goal = effectiveQuestion }

        // 历史图片降级：旧消息去掉图片只留文字，控制 token 消耗与延迟
        history = history.map { message in
            var trimmed = message
            trimmed.imagesData = nil
            return trimmed
        }

        if history.isEmpty {
            history.append(ChatMessage(role: .system, content: Self.systemPrompt))
        }
        history.append(ChatMessage(role: .user, content: effectiveQuestion, imagesData: [imageData]))
        entries.append(GuidanceEntry(role: .user, text: effectiveQuestion, hasScreenshot: true))

        await streamReply()
    }

    /// 纯文字追问（不截图）
    func askFollowUp(question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, !trimmed.isEmpty, hasSession else { return }
        errorMessage = nil

        history.append(ChatMessage(role: .user, content: trimmed))
        entries.append(GuidanceEntry(role: .user, text: trimmed, hasScreenshot: false))

        await streamReply()
    }

    /// 语音输入开关：录音中则停止，否则申请权限并开始识别
    func toggleVoiceInput(onText: @escaping (String) -> Void) async {
        if speech.isRecording {
            speech.stopRecording()
            return
        }

        guard await speech.requestSpeechPermissions() else {
            errorMessage = SpeechError.permissionDenied.errorDescription
            return
        }

        do {
            try speech.startRecording(onPartial: onText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 结束会话，清空全部状态
    func reset() {
        speech.stopSpeaking()
        speech.stopRecording()
        entries = []
        history = []
        goal = ""
        currentReply = ""
        errorMessage = nil
        isStreaming = false
        isCapturing = false
    }

    // MARK: - 流式请求

    private func streamReply() async {
        let config = SettingsViewModel.shared.currentLLMConfig

        guard !config.apiKey.isEmpty || config.provider == .ollama else {
            errorMessage = "请先在设置中配置 \(config.provider.displayName) 的 API Key"
            return
        }

        guard config.provider.supportsVision else {
            errorMessage = LLMError.visionNotSupported.errorDescription
            return
        }

        isStreaming = true
        currentReply = ""

        let service = LLMServiceFactory.create(for: config)
        do {
            for try await chunk in service.sendChatStream(messages: history) {
                currentReply += chunk
            }
            let reply = currentReply
            history.append(ChatMessage(role: .assistant, content: reply))
            entries.append(GuidanceEntry(role: .assistant, text: reply, hasScreenshot: false))

            // 自动朗读：布布把步骤"说"给你听，不用盯着屏幕看文字
            if autoSpeak && !reply.isEmpty {
                speech.speak(reply)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        currentReply = ""
        isStreaming = false
    }
}
