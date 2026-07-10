//
//  LLMService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  LLM 服务层 - 与各种 AI 服务进行交互
//

import Foundation
import AppKit

// MARK: - LLM 服务协议

protocol LLMService {
    var config: LLMConfig { get }

    /// 发送消息并获取回复
    func sendMessage(_ message: String) async throws -> String

    /// 发送消息并获取流式回复
    func sendMessageStream(_ message: String) -> AsyncThrowingStream<String, Error>

    /// 多轮对话流式回复（消息可携带图片，用于截图指导等场景）
    func sendChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>

    /// 翻译文本
    func translate(text: String, from: String, to: String) async throws -> String

    /// 智能搜索
    func search(query: String) async throws -> String
}

// MARK: - LLM 服务工厂

class LLMServiceFactory {
    static func create(for config: LLMConfig) -> LLMService {
        switch config.provider {
        case .openai:
            return OpenAIService(config: config)
        case .claude:
            return ClaudeService(config: config)
        case .wenxin:
            return WenxinService(config: config)
        case .qwen:
            return QwenService(config: config)
        case .deepseek:
            return DeepSeekService(config: config)
        case .ollama:
            return OllamaService(config: config)
        }
    }
}

// MARK: - 基础 LLM 服务

class BaseLLMService: LLMService {
    let config: LLMConfig

    // 共享的 URLSession 配置（优化连接复用）
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30  // 请求超时 30 秒
        configuration.timeoutIntervalForResource = 60 // 资源超时 60 秒
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    var session: URLSession { Self.sharedSession }

    init(config: LLMConfig) {
        self.config = config
    }

    func sendMessage(_ message: String) async throws -> String {
        fatalError("子类必须实现此方法")
    }

    func sendMessageStream(_ message: String) -> AsyncThrowingStream<String, Error> {
        fatalError("子类必须实现此方法")
    }

    func sendChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        // 默认实现：不支持图片；纯文本历史拼接为对话稿走单条消息接口
        if messages.contains(where: { $0.hasImages }) {
            return AsyncThrowingStream { $0.finish(throwing: LLMError.visionNotSupported) }
        }
        return sendMessageStream(Self.plainTranscript(from: messages))
    }

    /// 将多轮消息拼接为纯文本对话稿（供不支持多轮接口的服务降级使用）
    static func plainTranscript(from messages: [ChatMessage]) -> String {
        guard messages.count > 1 else { return messages.first?.content ?? "" }
        return messages.map { message in
            switch message.role {
            case .system: return "【系统】\(message.content)"
            case .user: return "【用户】\(message.content)"
            case .assistant: return "【助手】\(message.content)"
            }
        }.joined(separator: "\n\n")
    }

    func translate(text: String, from: String, to: String) async throws -> String {
        let prompt = """
        请将以下文本从\(from)翻译成\(to)，只返回翻译结果，不要添加任何解释：

        \(text)
        """
        return try await sendMessage(prompt)
    }

    func search(query: String) async throws -> String {
        let prompt = """
        请回答以下问题，提供准确、简洁的信息：

        \(query)
        """
        return try await sendMessage(prompt)
    }

    // MARK: - 辅助方法

    func buildRequest(url: URL, body: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    // MARK: - OpenAI 兼容协议共享实现

    /// 构建 OpenAI 兼容格式的 messages 数组（图片以 base64 data URL 内嵌）
    static func openAIMessages(from messages: [ChatMessage]) -> [[String: Any]] {
        messages.map { message in
            guard let images = message.imagesData, !images.isEmpty else {
                return ["role": message.role.rawValue, "content": message.content]
            }
            var content: [[String: Any]] = [["type": "text", "text": message.content]]
            for imageData in images {
                content.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"]
                ])
            }
            return ["role": message.role.rawValue, "content": content]
        }
    }

    /// OpenAI 兼容协议的多轮流式对话（OpenAI / DeepSeek / 通义千问兼容模式共用）
    func openAICompatibleChatStream(endpoint: URL, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !self.config.apiKey.isEmpty else {
                        continuation.finish(throwing: LLMError.invalidAPIKey)
                        return
                    }

                    // 含图片时解析视觉模型，不支持视觉的服务直接报错
                    var model = self.config.model
                    if messages.contains(where: { $0.hasImages }) {
                        guard let visionModel = self.config.provider.resolveVisionModel(configured: self.config.model) else {
                            continuation.finish(throwing: LLMError.visionNotSupported)
                            return
                        }
                        model = visionModel
                    }

                    let body: [String: Any] = [
                        "model": model,
                        "messages": Self.openAIMessages(from: messages),
                        "temperature": self.config.temperature,
                        "max_tokens": self.config.maxTokens,
                        "stream": true
                    ]

                    var request = self.buildRequest(url: endpoint, body: try JSONSerialization.data(withJSONObject: body))
                    request.setValue("Bearer \(self.config.apiKey)", forHTTPHeaderField: "Authorization")

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: statusCode == 429 ? LLMError.rateLimited : LLMError.serverError("请求失败（HTTP \(statusCode)）"))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        if jsonString == "[DONE]" { break }

                        if let data = jsonString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            continuation.yield(content)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // 消费方提前终止时取消网络任务，避免连接被挂到超时
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - OpenAI 服务

class OpenAIService: BaseLLMService {
    override func sendMessage(_ message: String) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw LLMError.invalidAPIKey
        }

        let url = URL(string: "\(config.baseURL)/chat/completions")!

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": message]
            ],
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]

        var request = buildRequest(url: url, body: try JSONSerialization.data(withJSONObject: body))
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 429 {
            throw LLMError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            throw LLMError.serverError(errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let messageDict = firstChoice["message"] as? [String: Any],
              let content = messageDict["content"] as? String else {
            throw LLMError.parseError
        }

        return content
    }

    override func sendMessageStream(_ message: String) -> AsyncThrowingStream<String, Error> {
        sendChatStream(messages: [ChatMessage(role: .user, content: message)])
    }

    override func sendChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        openAICompatibleChatStream(
            endpoint: URL(string: "\(config.baseURL)/chat/completions")!,
            messages: messages
        )
    }
}

// MARK: - Claude 服务

class ClaudeService: BaseLLMService {
    override func sendMessage(_ message: String) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw LLMError.invalidAPIKey
        }

        let url = URL(string: "\(config.baseURL)/messages")!

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": message]
            ],
            "max_tokens": config.maxTokens
        ]

        var request = buildRequest(url: url, body: try JSONSerialization.data(withJSONObject: body))
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            throw LLMError.serverError(errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw LLMError.parseError
        }

        return text
    }

    override func sendMessageStream(_ message: String) -> AsyncThrowingStream<String, Error> {
        sendChatStream(messages: [ChatMessage(role: .user, content: message)])
    }

    override func sendChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !self.config.apiKey.isEmpty else {
                        continuation.finish(throwing: LLMError.invalidAPIKey)
                        return
                    }

                    let url = URL(string: "\(self.config.baseURL)/messages")!

                    // Claude 的 system 提示词是顶层参数，需从消息列表中拆出
                    let systemText = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n")
                    let chatMessages = messages.filter { $0.role != .system }

                    var body: [String: Any] = [
                        "model": self.config.model,
                        "max_tokens": self.config.maxTokens,
                        "stream": true,
                        "messages": chatMessages.map { Self.claudeMessage(from: $0) }
                    ]
                    if !systemText.isEmpty {
                        body["system"] = systemText
                    }

                    var request = self.buildRequest(url: url, body: try JSONSerialization.data(withJSONObject: body))
                    request.setValue(self.config.apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: statusCode == 429 ? LLMError.rateLimited : LLMError.serverError("请求失败（HTTP \(statusCode)）"))
                        return
                    }

                    // Claude SSE：content_block_delta 事件中的 text_delta 为增量文本
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))

                        if let data = jsonString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let type = json["type"] as? String, type == "content_block_delta",
                           let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // 消费方提前终止时取消网络任务，避免连接被挂到超时
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 构建 Claude 消息（图片使用 base64 content block，置于文本之前以获得更好的视觉理解）
    private static func claudeMessage(from message: ChatMessage) -> [String: Any] {
        guard let images = message.imagesData, !images.isEmpty else {
            return ["role": message.role.rawValue, "content": message.content]
        }
        var content: [[String: Any]] = images.map { imageData in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ]
            ]
        }
        content.append(["type": "text", "text": message.content])
        return ["role": message.role.rawValue, "content": content]
    }
}

// MARK: - 文心一言服务

class WenxinService: BaseLLMService {
    private var accessToken: String?
    private var tokenExpiration: Date?

    override func sendMessage(_ message: String) async throws -> String {
        let token = try await getAccessToken()

        let url = URL(string: "\(config.baseURL)/rpc/2.0/ai_custom/v1/wenxinworkshop/chat/\(config.model)?access_token=\(token)")!

        let body: [String: Any] = [
            "messages": [
                ["role": "user", "content": message]
            ]
        ]

        let request = buildRequest(url: url, body: try JSONSerialization.data(withJSONObject: body))

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.serverError("请求失败")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw LLMError.parseError
        }

        return result
    }

    private func getAccessToken() async throws -> String {
        // 检查缓存的 token
        if let token = accessToken, let expiration = tokenExpiration, Date() < expiration {
            return token
        }

        guard let secretKey = config.secretKey else {
            throw LLMError.invalidAPIKey
        }

        let url = URL(string: "https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials&client_id=\(config.apiKey)&client_secret=\(secretKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw LLMError.parseError
        }

        accessToken = token
        tokenExpiration = Date().addingTimeInterval(TimeInterval(expiresIn - 60))

        return token
    }

    override func sendMessageStream(_ message: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await self.sendMessage(message)
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - 通义千问服务

class QwenService: BaseLLMService {
    override func sendMessage(_ message: String) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw LLMError.invalidAPIKey
        }

        // 统一走 OpenAI 兼容模式端点，与流式路径一致
        //（qwen-vl 系列不支持旧版 text-generation 端点，避免用户选择 VL 模型后搜索/翻译失败）
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": message]
            ],
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]

        var request = buildRequest(url: compatibleEndpoint, body: try JSONSerialization.data(withJSONObject: body))
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            throw LLMError.serverError(errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let messageDict = firstChoice["message"] as? [String: Any],
              let content = messageDict["content"] as? String else {
            throw LLMError.parseError
        }

        return content
    }

    /// OpenAI 兼容模式端点：多轮/视觉/流式统一走该协议（qwen-vl 系列必须使用）
    private var compatibleEndpoint: URL {
        if config.baseURL.contains("dashscope.aliyuncs.com") {
            return URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
        }
        return URL(string: "\(config.baseURL)/chat/completions")!
    }

    override func sendMessageStream(_ message: String) -> AsyncThrowingStream<String, Error> {
        sendChatStream(messages: [ChatMessage(role: .user, content: message)])
    }

    override func sendChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        openAICompatibleChatStream(endpoint: compatibleEndpoint, messages: messages)
    }
}

// MARK: - DeepSeek 服务

class DeepSeekService: BaseLLMService {
    override func sendMessage(_ message: String) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw LLMError.invalidAPIKey
        }

        let url = URL(string: "\(config.baseURL)/chat/completions")!

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": message]
            ],
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]

        var request = buildRequest(url: url, body: try JSONSerialization.data(withJSONObject: body))
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            throw LLMError.serverError(errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let messageDict = firstChoice["message"] as? [String: Any],
              let content = messageDict["content"] as? String else {
            throw LLMError.parseError
        }

        return content
    }

    override func sendMessageStream(_ message: String) -> AsyncThrowingStream<String, Error> {
        sendChatStream(messages: [ChatMessage(role: .user, content: message)])
    }

    override func sendChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        openAICompatibleChatStream(
            endpoint: URL(string: "\(config.baseURL)/chat/completions")!,
            messages: messages
        )
    }
}

// MARK: - Ollama 本地服务

class OllamaService: BaseLLMService {
    override func sendMessage(_ message: String) async throws -> String {
        let url = URL(string: "\(config.baseURL)/api/generate")!

        let body: [String: Any] = [
            "model": config.model,
            "prompt": message,
            "stream": false,
            "options": [
                "temperature": config.temperature,
                "num_predict": config.maxTokens
            ]
        ]

        let request = buildRequest(url: url, body: try JSONSerialization.data(withJSONObject: body))

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.serverError("请求失败，请确保 Ollama 正在运行")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw LLMError.parseError
        }

        return responseText
    }

    override func sendMessageStream(_ message: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = URL(string: "\(self.config.baseURL)/api/generate")!

                    let body: [String: Any] = [
                        "model": self.config.model,
                        "prompt": message,
                        "stream": true,
                        "options": [
                            "temperature": self.config.temperature,
                            "num_predict": self.config.maxTokens
                        ]
                    ]

                    let request = self.buildRequest(url: url, body: try JSONSerialization.data(withJSONObject: body))

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: LLMError.serverError("请求失败"))
                        return
                    }

                    for try await line in bytes.lines {
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let responseText = json["response"] as? String {
                            continuation.yield(responseText)

                            if let done = json["done"] as? Bool, done {
                                break
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // 消费方提前终止时取消网络任务，避免连接被挂到超时
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - 图片压缩

extension NSImage {
    /// 压缩为适合 LLM 视觉输入的 JPEG 数据：长边限制像素尺寸 + 质量压缩，
    /// 控制 token 消耗与网络传输体积（Retina 截图原图可达数十 MB）
    func compressedForLLM(maxDimension: CGFloat = 1568, compressionQuality: CGFloat = 0.7) -> Data? {
        guard size.width > 0, size.height > 0 else { return nil }

        let ratio = min(1.0, maxDimension / max(size.width, size.height))
        let targetWidth = Int(size.width * ratio)
        let targetHeight = Int(size.height * ratio)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        bitmap.size = NSSize(width: targetWidth, height: targetHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(
            in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
