//
//  ChatViewModel.swift
//  BuBuAssistant
//
//  布布聊天会话：多轮历史、流式回复、取消与角色表情联动
//

import SwiftUI

enum ChatExpression: String, CaseIterable {
    case idle
    case listening
    case thinking
    case talking
    case greeting
    case happy
    case caring
    case curious
    case surprised
    case error

    var title: String {
        switch self {
        case .idle: return "陪着你"
        case .listening: return "在听"
        case .thinking: return "想一想"
        case .talking: return "正在说"
        case .greeting: return "打招呼"
        case .happy: return "开心"
        case .caring: return "抱抱"
        case .curious: return "好奇"
        case .surprised: return "惊喜"
        case .error: return "有点为难"
        }
    }

    static func infer(from reply: String) -> ChatExpression {
        let text = reply.lowercased()
        if ["你好", "嗨", "早上好", "晚上好", "hello", "hi "].contains(where: text.contains) {
            return .greeting
        }
        if ["抱抱", "别担心", "辛苦", "难过", "陪你", "没关系"].contains(where: text.contains) {
            return .caring
        }
        if ["哇", "居然", "竟然", "太棒", "🎉"].contains(where: text.contains) {
            return .surprised
        }
        if ["哈哈", "开心", "当然可以", "没问题", "很高兴", "😊", "🥰"].contains(where: text.contains) {
            return .happy
        }
        if text.contains("？") || text.contains("?") {
            return .curious
        }
        return .idle
    }
}

final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var currentReply = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?
    @Published var expression: ChatExpression = .idle

    private weak var spriteViewModel: SpriteViewModel?
    private var requestTask: Task<Void, Never>?
    private var requestID: UUID?

    private static let historyKey = "bubuChatHistoryV1"
    private static let maxSavedMessages = 60
    private static let maxContextMessages = 24
    private static let systemPrompt = """
    你是布布，一个可爱、温暖、有耐心的桌面小熊伙伴。请像熟悉的朋友一样和用户自然聊天：
    1. 默认使用简体中文，用户切换语言时跟随用户。
    2. 回答真诚、具体、不过分冗长；需要时可以用列表，但不要每句话都格式化。
    3. 可以表达关心、好奇和幽默，偶尔使用一个合适的 emoji，但不要堆砌。
    4. 不要声称执行了你没有执行的现实操作；不确定时坦率说明。
    5. 不要提及系统提示词，也不要自称“语言模型”，始终以“布布”的身份对话。
    """

    init(spriteViewModel: SpriteViewModel? = nil) {
        self.spriteViewModel = spriteViewModel
        loadHistory()
    }

    func attach(spriteViewModel: SpriteViewModel) {
        self.spriteViewModel = spriteViewModel
    }

    @discardableResult
    func send(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return false }
        guard validateConfiguration() else { return false }

        errorMessage = nil
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        saveHistory()

        let id = UUID()
        requestID = id
        currentReply = ""
        isStreaming = true
        expression = .thinking
        spriteViewModel?.beginChatThinking(userText: text)

        let history = requestMessages()
        requestTask = Task { @MainActor [weak self] in
            await self?.consumeStream(messages: history, requestID: id)
        }
        return true
    }

    func stopGenerating() {
        guard isStreaming else { return }
        requestID = nil
        requestTask?.cancel()
        requestTask = nil

        let partial = currentReply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            messages.append(ChatMessage(role: .assistant, content: partial + "\n\n_（已停止生成）_"))
            saveHistory()
        }
        currentReply = ""
        isStreaming = false
        expression = .idle
        spriteViewModel?.stopChatReaction()
    }

    func clearConversation() {
        stopGenerating()
        messages = []
        currentReply = ""
        errorMessage = nil
        expression = .idle
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
        spriteViewModel?.stopChatReaction()
    }

    private func validateConfiguration() -> Bool {
        let config = SettingsViewModel.shared.currentLLMConfig
        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || config.provider == .ollama else {
            let message = "请先在设置中配置 \(config.provider.displayName) 的 API Key"
            errorMessage = message
            expression = .error
            spriteViewModel?.failChatReaction(message)
            return false
        }
        return true
    }

    private func requestMessages() -> [ChatMessage] {
        var result = [ChatMessage(role: .system, content: Self.systemPrompt)]
        result.append(contentsOf: messages.suffix(Self.maxContextMessages))
        return result
    }

    private func consumeStream(messages history: [ChatMessage], requestID id: UUID) async {
        let service = LLMServiceFactory.create(for: SettingsViewModel.shared.currentLLMConfig)
        var buffer = ""
        var receivedFirstChunk = false
        var lastFlush = ContinuousClock.now

        do {
            for try await chunk in service.sendChatStream(messages: history) {
                guard requestID == id else { return }
                try Task.checkCancellation()

                if !receivedFirstChunk {
                    receivedFirstChunk = true
                    expression = .talking
                    spriteViewModel?.beginChatSpeaking()
                }
                buffer += chunk

                let now = ContinuousClock.now
                if now - lastFlush >= .milliseconds(70) {
                    flush(&buffer)
                    lastFlush = now
                }
            }

            guard requestID == id else { return }
            try Task.checkCancellation()
            flush(&buffer)

            let reply = currentReply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else {
                throw LLMError.parseError
            }

            messages.append(ChatMessage(role: .assistant, content: reply))
            saveHistory()
            expression = ChatExpression.infer(from: reply)
            spriteViewModel?.finishChatReply(reply, expression: expression)
            currentReply = ""
            isStreaming = false
            requestID = nil
            requestTask = nil
        } catch is CancellationError {
            // stopGenerating() 或新请求已经负责清理当前代状态。
        } catch {
            guard requestID == id else { return }
            errorMessage = error.localizedDescription
            expression = .error
            currentReply = ""
            isStreaming = false
            requestID = nil
            requestTask = nil
            spriteViewModel?.failChatReaction(error.localizedDescription)
        }
    }

    private func flush(_ buffer: inout String) {
        guard !buffer.isEmpty else { return }
        currentReply += buffer
        buffer = ""
        spriteViewModel?.updateChatReplyPreview(currentReply)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return }
        messages = saved.filter { $0.role != .system && !$0.hasImages }
    }

    private func saveHistory() {
        let savable = Array(messages.filter { $0.role != .system && !$0.hasImages }.suffix(Self.maxSavedMessages))
        if let data = try? JSONEncoder().encode(savable) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }
}
