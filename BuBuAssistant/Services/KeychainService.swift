//
//  KeychainService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  Keychain 服务 - 安全存储 API Keys
//

import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.bubuassistant.apikeys"

    private init() {}

    // MARK: - API Key 操作

    /// 保存 API Key
    func saveAPIKey(_ apiKey: String, for provider: LLMProviderType) {
        let key = "apiKey_\(provider.rawValue)"
        save(value: apiKey, forKey: key)
    }

    /// 获取 API Key
    func getAPIKey(for provider: LLMProviderType) -> String? {
        let key = "apiKey_\(provider.rawValue)"
        return get(forKey: key)
    }

    /// 删除 API Key
    func deleteAPIKey(for provider: LLMProviderType) {
        let key = "apiKey_\(provider.rawValue)"
        delete(forKey: key)
    }

    // MARK: - Secret Key 操作（文心一言）

    /// 保存 Secret Key
    func saveSecretKey(_ secretKey: String, for provider: LLMProviderType) {
        let key = "secretKey_\(provider.rawValue)"
        save(value: secretKey, forKey: key)
    }

    /// 获取 Secret Key
    func getSecretKey(for provider: LLMProviderType) -> String? {
        let key = "secretKey_\(provider.rawValue)"
        return get(forKey: key)
    }

    /// 删除 Secret Key
    func deleteSecretKey(for provider: LLMProviderType) {
        let key = "secretKey_\(provider.rawValue)"
        delete(forKey: key)
    }

    // MARK: - 通用 Keychain 操作

    private func save(value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }

        // 先删除已存在的
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // Keychain 保存失败，静默处理
        }
    }

    private func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    /// 清除所有存储的密钥
    func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]

        SecItemDelete(query as CFDictionary)
    }
}
