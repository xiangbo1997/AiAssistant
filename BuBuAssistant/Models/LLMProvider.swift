//
//  LLMProvider.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  LLM 提供商模型 - 定义支持的 AI 服务配置
//

import Foundation

// MARK: - LLM 提供商

enum LLMProviderType: String, CaseIterable, Codable {
    case openai = "OpenAI"
    case claude = "Claude"
    case qwen = "通义千问"
    case wenxin = "文心一言"
    case deepseek = "DeepSeek"
    case ollama = "Ollama"

    var displayName: String {
        return self.rawValue
    }

    var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .claude: return "https://api.anthropic.com/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/api/v1"
        case .wenxin: return "https://aip.baidubce.com"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .ollama: return "http://localhost:11434"
        }
    }

    var availableModels: [String] {
        switch self {
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        case .claude:
            return ["claude-3-5-sonnet-20241022", "claude-3-haiku-20240307", "claude-3-opus-20240229"]
        case .qwen:
            return ["qwen-turbo", "qwen-plus", "qwen-max", "qwen-max-longcontext"]
        case .wenxin:
            return ["ernie-4.0-8k", "ernie-3.5-8k", "ernie-speed-8k"]
        case .deepseek:
            return ["deepseek-chat", "deepseek-coder"]
        case .ollama:
            return ["llama3.2", "llama3.1", "qwen2.5", "mistral", "codellama"]
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .claude: return "claude-3-5-sonnet-20241022"
        case .qwen: return "qwen-turbo"
        case .wenxin: return "ernie-3.5-8k"
        case .deepseek: return "deepseek-chat"
        case .ollama: return "llama3.2"
        }
    }

    var icon: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .claude: return "sparkles"
        case .qwen: return "cloud"
        case .wenxin: return "wand.and.stars"
        case .deepseek: return "fish"
        case .ollama: return "desktopcomputer"
        }
    }

    var color: String {
        switch self {
        case .openai: return "#10A37F"
        case .claude: return "#D97706"
        case .qwen: return "#6366F1"
        case .wenxin: return "#2563EB"
        case .deepseek: return "#0EA5E9"
        case .ollama: return "#64748B"
        }
    }
}

// MARK: - LLM 配置

struct LLMConfig: Codable, Equatable {
    var provider: LLMProviderType
    var apiKey: String
    var secretKey: String?       // 文心一言需要
    var baseURL: String
    var model: String
    var temperature: Double
    var maxTokens: Int

    init(
        provider: LLMProviderType,
        apiKey: String = "",
        secretKey: String? = nil,
        baseURL: String? = nil,
        model: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.baseURL = baseURL ?? provider.defaultBaseURL
        self.model = model ?? provider.defaultModel
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    // 默认配置
    static let `default` = LLMConfig(provider: .openai)
}

// MARK: - 聊天消息

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date

    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }

    enum MessageRole: String, Codable {
        case system
        case user
        case assistant
    }
}

// MARK: - 流式响应

struct StreamChunk {
    var content: String
    var isFinished: Bool
    var error: Error?
}
