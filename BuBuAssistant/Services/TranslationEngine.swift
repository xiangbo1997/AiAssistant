//
//  TranslationEngine.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-07-10.
//  翻译引擎 - 面板翻译与精灵快速翻译共用的核心：
//  统一提示词、翻译专用 LLM 参数、历史缓存命中与历史写入
//

import Foundation

final class TranslationEngine {
    static let shared = TranslationEngine()

    private init() {}

    // MARK: - 错误

    enum EngineError: LocalizedError {
        case missingAPIKey

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "请先在设置中配置 AI 服务的 API Key"
            }
        }
    }

    // MARK: - 历史缓存

    /// 查翻译历史做精确命中：相同原文 + 相同目标语言直接复用，省一次 API 调用。
    /// 不比对源语言——同一段文本翻到同一目标语言，结果与声明的源语言无关
    func cachedTranslation(text: String, target: Language) -> String? {
        TranslationHistoryService.shared.translationHistory.first {
            $0.sourceText == text && $0.targetLanguage == target.displayName
        }?.targetText
    }

    // MARK: - 流式翻译

    /// 创建流式翻译请求。抛出 EngineError.missingAPIKey 表示未配置密钥
    func stream(
        text: String,
        source: Language = .auto,
        target: Language
    ) throws -> AsyncThrowingStream<String, Error> {
        var config = SettingsViewModel.shared.currentLLMConfig

        // Ollama 走本地服务，不需要 API Key
        guard !config.apiKey.isEmpty || config.provider == .ollama else {
            throw EngineError.missingAPIKey
        }

        // 翻译要求确定性输出，不复用聊天的发散参数；
        // maxTokens 按原文长度放大，避免长文译文被用户的聊天配置截断
        config.temperature = 0.2
        config.maxTokens = max(config.maxTokens, min(8192, text.count * 2 + 256))

        let service = LLMServiceFactory.create(for: config)
        return service.sendChatStream(messages: [
            ChatMessage(role: .system, content: Self.systemPrompt(source: source, target: target)),
            ChatMessage(role: .user, content: text)
        ])
    }

    /// 词典模式：单词/短语返回音标、词性、释义与例句（Markdown 卡片）
    func dictionaryStream(word: String, target: Language) throws -> AsyncThrowingStream<String, Error> {
        var config = SettingsViewModel.shared.currentLLMConfig

        guard !config.apiKey.isEmpty || config.provider == .ollama else {
            throw EngineError.missingAPIKey
        }

        config.temperature = 0.2
        config.maxTokens = max(config.maxTokens, 1024)

        let systemPrompt = """
        你是精炼的双语词典。用户给出一个单词或短语，用\(target.promptName)输出词典卡片，Markdown 格式：
        第一行：**原词** 与音标（如适用）；
        随后每行一个词性及其释义；
        最后给 1~2 条例句，附\(target.promptName)翻译。
        内容精炼，不要输出任何其他说明。
        """

        let service = LLMServiceFactory.create(for: config)
        return service.sendChatStream(messages: [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: word)
        ])
    }

    /// 视觉直翻：把截图直接交给视觉模型识别并翻译（本地 OCR 失败时的兜底路径）。
    /// imageData 应为压缩后的 JPEG（控制 token 消耗）
    func visionStream(imageData: Data, target: Language) throws -> AsyncThrowingStream<String, Error> {
        var config = SettingsViewModel.shared.currentLLMConfig

        guard !config.apiKey.isEmpty || config.provider == .ollama else {
            throw EngineError.missingAPIKey
        }

        config.temperature = 0.2
        config.maxTokens = max(config.maxTokens, 4096)

        let systemPrompt = """
        你是专业的翻译引擎。识别用户图片中的全部文字，将其翻译成\(target.promptName)。
        要求：只输出译文本身，保留原文的行文结构；不要输出原文、解释或任何前后缀。
        """

        let service = LLMServiceFactory.create(for: config)
        return service.sendChatStream(messages: [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: "请翻译图片中的文字。", imagesData: [imageData])
        ])
    }

    /// 翻译系统提示词：约束只输出译文并保留原文格式
    static func systemPrompt(source: Language, target: Language) -> String {
        let sourcePart = source == .auto
            ? "自动识别源语言"
            : "源语言为\(source.promptName)"
        return """
        你是专业的翻译引擎。\(sourcePart)，将用户消息中的全部文本翻译成\(target.promptName)。
        要求：只输出译文本身；保留原文的换行、Markdown 标记、代码块与占位符；\
        不要添加任何解释、引号或前后缀。
        """
    }

    // MARK: - 历史写入

    /// 写入翻译历史（去重与容量清理由 TranslationHistoryService 内部处理）
    func saveRecord(sourceText: String, targetText: String, source: Language, target: Language) {
        guard !sourceText.isEmpty, !targetText.isEmpty else { return }
        TranslationHistoryService.shared.addRecord(
            sourceText: sourceText,
            targetText: targetText,
            sourceLanguage: source.displayName,
            targetLanguage: target.displayName
        )
    }
}
