//
//  LLMService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  LLM 服务层 - 与各种 AI 服务进行交互
//

import Foundation

// MARK: - LLM 服务协议

protocol LLMService {
    var config: LLMConfig { get }

    /// 发送消息并获取回复
    func sendMessage(_ message: String) async throws -> String

    /// 发送消息并获取流式回复
    func sendMessageStream(_ message: String) -> AsyncThrowingStream<String, Error>

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
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !config.apiKey.isEmpty else {
                        continuation.finish(throwing: LLMError.invalidAPIKey)
                        return
                    }

                    let url = URL(string: "\(config.baseURL)/chat/completions")!

                    let body: [String: Any] = [
                        "model": config.model,
                        "messages": [
                            ["role": "user", "content": message]
                        ],
                        "temperature": config.temperature,
                        "max_tokens": config.maxTokens,
                        "stream": true
                    ]

                    var request = self.buildRequest(url: url, body: try JSONSerialization.data(withJSONObject: body))
                    request.setValue("Bearer \(self.config.apiKey)", forHTTPHeaderField: "Authorization")

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: LLMError.serverError("请求失败"))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" {
                                break
                            }

                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
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

        let url = URL(string: "\(config.baseURL)/services/aigc/text-generation/generation")!

        let body: [String: Any] = [
            "model": config.model,
            "input": [
                "messages": [
                    ["role": "user", "content": message]
                ]
            ],
            "parameters": [
                "temperature": config.temperature,
                "max_tokens": config.maxTokens
            ]
        ]

        var request = buildRequest(url: url, body: try JSONSerialization.data(withJSONObject: body))
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.serverError("请求失败")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let text = output["text"] as? String else {
            throw LLMError.parseError
        }

        return text
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
            Task {
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
        }
    }
}
