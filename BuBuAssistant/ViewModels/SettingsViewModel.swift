//
//  SettingsViewModel.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  设置视图模型 - 管理应用设置和 LLM 配置
//

import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    // 单例
    static let shared = SettingsViewModel()

    // MARK: - 通用设置

    @Published var launchAtLogin: Bool = false {
        didSet {
            LaunchAtLoginService.shared.isEnabled = launchAtLogin
        }
    }
    @AppStorage("hideDockIcon") var hideDockIcon: Bool = true
    @AppStorage("appLanguage") var appLanguage: String = "zh-Hans"

    // MARK: - 主题设置

    @Published var colorScheme: ColorSchemeOption = .system {
        didSet { saveColorScheme() }
    }

    // MARK: - 精灵设置

    @Published var currentCharacter: SpriteCharacter = .bubu {
        didSet { saveCurrentCharacter() }
    }

    @AppStorage("spriteScale") var spriteScale: Double = 1.0
    @AppStorage("spriteOpacity") var spriteOpacity: Double = 1.0
    @AppStorage("enableAnimation") var enableAnimation: Bool = true
    @AppStorage("sleepDelay") var sleepDelay: Double = 300 // 秒
    @AppStorage("use3DSprite") var use3DSprite: Bool = false // 是否使用 3D 模式

    // MARK: - LLM 设置

    @Published var currentProvider: LLMProviderType = .openai {
        didSet { saveCurrentProvider() }
    }

    @Published var llmConfigs: [LLMProviderType: LLMConfig] = [:] {
        didSet { saveLLMConfigs() }
    }

    // MARK: - 快捷键设置

    @AppStorage("globalSearchShortcut") var globalSearchShortcut: String = "⌘⇧F"
    @AppStorage("globalTranslateShortcut") var globalTranslateShortcut: String = "⌘⇧T"
    @AppStorage("globalNoteShortcut") var globalNoteShortcut: String = "⌘⇧N"

    // MARK: - 初始化

    init() {
        loadSettings()
    }

    // MARK: - 加载设置

    private func loadSettings() {
        // 加载开机自启状态
        launchAtLogin = LaunchAtLoginService.shared.isEnabled

        // 加载颜色方案
        if let rawValue = UserDefaults.standard.string(forKey: "colorScheme"),
           let scheme = ColorSchemeOption(rawValue: rawValue) {
            colorScheme = scheme
        }

        // 加载当前角色
        if let data = UserDefaults.standard.data(forKey: "currentCharacter"),
           let character = try? JSONDecoder().decode(SpriteCharacter.self, from: data) {
            currentCharacter = character
        }

        // 加载当前 LLM 提供商
        if let rawValue = UserDefaults.standard.string(forKey: "currentProvider"),
           let provider = LLMProviderType(rawValue: rawValue) {
            currentProvider = provider
        }

        // 加载 LLM 配置
        loadLLMConfigs()
    }

    // MARK: - 保存设置

    private func saveColorScheme() {
        UserDefaults.standard.set(colorScheme.rawValue, forKey: "colorScheme")
    }

    private func saveCurrentCharacter() {
        if let data = try? JSONEncoder().encode(currentCharacter) {
            UserDefaults.standard.set(data, forKey: "currentCharacter")
        }
    }

    private func saveCurrentProvider() {
        UserDefaults.standard.set(currentProvider.rawValue, forKey: "currentProvider")
    }

    // MARK: - LLM 配置管理

    private func loadLLMConfigs() {
        // 初始化默认配置
        for provider in LLMProviderType.allCases {
            llmConfigs[provider] = LLMConfig(provider: provider)
        }

        // 从 Keychain 加载 API Keys
        for provider in LLMProviderType.allCases {
            if let apiKey = KeychainService.shared.getAPIKey(for: provider) {
                llmConfigs[provider]?.apiKey = apiKey
            }
            if provider == .wenxin,
               let secretKey = KeychainService.shared.getSecretKey(for: provider) {
                llmConfigs[provider]?.secretKey = secretKey
            }
        }

        // 从 UserDefaults 加载其他配置
        if let data = UserDefaults.standard.data(forKey: "llmConfigsMetadata"),
           let metadata = try? JSONDecoder().decode([String: LLMConfigMetadata].self, from: data) {
            for (key, meta) in metadata {
                if let provider = LLMProviderType(rawValue: key) {
                    if !meta.baseURL.trimmingCharacters(in: .whitespaces).isEmpty {
                        llmConfigs[provider]?.baseURL = meta.baseURL
                    }
                    // 模型为空时保留默认模型，避免发出空 model 的无效请求
                    if !meta.model.trimmingCharacters(in: .whitespaces).isEmpty {
                        llmConfigs[provider]?.model = meta.model
                    }
                    llmConfigs[provider]?.temperature = meta.temperature
                    llmConfigs[provider]?.maxTokens = meta.maxTokens
                }
            }
        }
    }

    private func saveLLMConfigs() {
        // 保存 API Keys 到 Keychain
        for (provider, config) in llmConfigs {
            KeychainService.shared.saveAPIKey(config.apiKey, for: provider)
            if provider == .wenxin, let secretKey = config.secretKey {
                KeychainService.shared.saveSecretKey(secretKey, for: provider)
            }
        }

        // 保存其他配置到 UserDefaults（不包含敏感信息）
        var metadata: [String: LLMConfigMetadata] = [:]
        for (provider, config) in llmConfigs {
            metadata[provider.rawValue] = LLMConfigMetadata(
                baseURL: config.baseURL,
                model: config.model,
                temperature: config.temperature,
                maxTokens: config.maxTokens
            )
        }

        if let data = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(data, forKey: "llmConfigsMetadata")
        }
    }

    /// 获取当前 LLM 配置（已净化：空模型/空地址回落默认值）
    var currentLLMConfig: LLMConfig {
        sanitized(llmConfigs[currentProvider] ?? LLMConfig(provider: currentProvider))
    }

    /// 更新 LLM 配置
    func updateLLMConfig(_ config: LLMConfig) {
        llmConfigs[config.provider] = config
    }

    /// 净化配置：模型/地址留空时回落到该服务的默认值，避免发出空 model 的无效请求
    private func sanitized(_ config: LLMConfig) -> LLMConfig {
        var result = config
        if result.model.trimmingCharacters(in: .whitespaces).isEmpty {
            result.model = config.provider.defaultModel
        }
        if result.baseURL.trimmingCharacters(in: .whitespaces).isEmpty {
            result.baseURL = config.provider.defaultBaseURL
        }
        return result
    }

    /// 测试 LLM 连接
    func testLLMConnection(for provider: LLMProviderType) async -> Result<String, Error> {
        guard let config = llmConfigs[provider] else {
            return .failure(LLMError.configNotFound)
        }

        // 这里调用 LLM 服务进行测试
        // 简单发送一个测试消息
        do {
            let service = LLMServiceFactory.create(for: sanitized(config))
            let response = try await service.sendMessage("你好，请回复'连接成功'")
            return .success(response)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 数据管理

    /// 导出所有数据（设置 + 便签）
    func exportData() -> Data? {
        // 收集设置数据（不含敏感 API Key）
        let settingsData = AppSettingsExport(
            colorScheme: colorScheme.rawValue,
            spriteScale: spriteScale,
            spriteOpacity: spriteOpacity,
            enableAnimation: enableAnimation,
            sleepDelay: sleepDelay,
            currentProvider: currentProvider.rawValue,
            globalSearchShortcut: globalSearchShortcut,
            globalTranslateShortcut: globalTranslateShortcut,
            globalNoteShortcut: globalNoteShortcut,
            llmConfigsMetadata: llmConfigs.mapValues { config in
                LLMConfigMetadata(
                    baseURL: config.baseURL,
                    model: config.model,
                    temperature: config.temperature,
                    maxTokens: config.maxTokens
                )
            }.reduce(into: [:]) { result, pair in
                result[pair.key.rawValue] = pair.value
            }
        )

        // 获取便签数据
        let notesViewModel = NotesViewModel()
        let notesData = notesViewModel.notes

        // 组合导出数据
        let exportData = AppExportData(
            version: "1.0",
            exportDate: Date(),
            settings: settingsData,
            notes: notesData
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            return try encoder.encode(exportData)
        } catch {
            return nil
        }
    }

    /// 导出数据到文件
    func exportToFile() -> URL? {
        guard let data = exportData() else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "BuBuAssistant_Backup_\(dateFormatter.string(from: Date())).json"

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    /// 导入数据
    func importData(_ data: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let importData = try decoder.decode(AppExportData.self, from: data)

            // 恢复设置
            if let scheme = ColorSchemeOption(rawValue: importData.settings.colorScheme) {
                colorScheme = scheme
            }
            spriteScale = importData.settings.spriteScale
            spriteOpacity = importData.settings.spriteOpacity
            enableAnimation = importData.settings.enableAnimation
            sleepDelay = importData.settings.sleepDelay

            if let provider = LLMProviderType(rawValue: importData.settings.currentProvider) {
                currentProvider = provider
            }

            globalSearchShortcut = importData.settings.globalSearchShortcut
            globalTranslateShortcut = importData.settings.globalTranslateShortcut
            globalNoteShortcut = importData.settings.globalNoteShortcut

            // 恢复 LLM 配置元数据（不含 API Key）
            for (key, meta) in importData.settings.llmConfigsMetadata {
                if let provider = LLMProviderType(rawValue: key) {
                    llmConfigs[provider]?.baseURL = meta.baseURL
                    llmConfigs[provider]?.model = meta.model
                    llmConfigs[provider]?.temperature = meta.temperature
                    llmConfigs[provider]?.maxTokens = meta.maxTokens
                }
            }

            // 导入便签
            let notesViewModel = NotesViewModel()
            for note in importData.notes {
                // 检查是否已存在
                if !notesViewModel.notes.contains(where: { $0.id == note.id }) {
                    notesViewModel.createNote(note)
                }
            }

            return true
        } catch {
            return false
        }
    }

    /// 从文件导入数据
    func importFromFile(_ url: URL) -> Bool {
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            return importData(data)
        } catch {
            return false
        }
    }

    /// 清除所有数据
    func clearAllData() {
        // 清除 UserDefaults
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)

        // 清除 Keychain
        for provider in LLMProviderType.allCases {
            KeychainService.shared.deleteAPIKey(for: provider)
            KeychainService.shared.deleteSecretKey(for: provider)
        }

        // 清除 Core Data
        PersistenceController.shared.clearAllData()

        // 重新加载默认设置
        loadSettings()
    }
}

// MARK: - 颜色方案选项

enum ColorSchemeOption: String, CaseIterable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

// MARK: - LLM 配置元数据（不含敏感信息）

struct LLMConfigMetadata: Codable {
    var baseURL: String
    var model: String
    var temperature: Double
    var maxTokens: Int
}

// MARK: - LLM 错误

enum LLMError: LocalizedError {
    case configNotFound
    case invalidAPIKey
    case networkError(Error)
    case parseError
    case rateLimited
    case serverError(String)
    case visionNotSupported

    var errorDescription: String? {
        switch self {
        case .configNotFound: return "未找到 LLM 配置"
        case .invalidAPIKey: return "API Key 无效"
        case .networkError(let error): return "网络错误: \(error.localizedDescription)"
        case .parseError: return "解析响应失败"
        case .rateLimited: return "请求过于频繁，请稍后重试"
        case .serverError(let message): return "服务器错误: \(message)"
        case .visionNotSupported: return "当前 AI 服务不支持图片理解，请在设置中切换到 OpenAI、Claude 或通义千问"
        }
    }
}

// MARK: - 应用导出数据结构

/// 应用设置导出结构（不含敏感信息）
struct AppSettingsExport: Codable {
    var colorScheme: String
    var spriteScale: Double
    var spriteOpacity: Double
    var enableAnimation: Bool
    var sleepDelay: Double
    var currentProvider: String
    var globalSearchShortcut: String
    var globalTranslateShortcut: String
    var globalNoteShortcut: String
    var llmConfigsMetadata: [String: LLMConfigMetadata]
}

/// 完整应用导出数据
struct AppExportData: Codable {
    let version: String
    let exportDate: Date
    let settings: AppSettingsExport
    let notes: [NoteDTO]
}
