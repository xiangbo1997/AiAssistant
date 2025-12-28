//
//  MemoService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-27.
//  备忘录服务 - 管理备忘录的存储、加密和检索
//

import Foundation
import CryptoKit
import Security

class MemoService: ObservableObject {
    static let shared = MemoService()

    @Published var memos: [MemoItem] = []
    @Published var isLocked: Bool = true

    private let storageKey = "bubu_memos_encrypted"
    private let saltKey = "bubu_memos_salt"
    private var encryptionKey: SymmetricKey?

    private init() {
        // 不自动加载，需要解锁后才能访问
    }

    // MARK: - 锁定/解锁

    /// 使用密码解锁备忘录
    func unlock(with password: String) -> Bool {
        guard let key = deriveKey(from: password) else { return false }

        encryptionKey = key

        if loadMemos() {
            isLocked = false
            return true
        } else {
            // 如果没有数据，说明是首次使用，创建空数据
            if UserDefaults.standard.data(forKey: storageKey) == nil {
                memos = []
                saveMemos()
                isLocked = false
                return true
            }
            encryptionKey = nil
            return false
        }
    }

    /// 锁定备忘录
    func lock() {
        encryptionKey = nil
        memos = []
        isLocked = true
    }

    /// 修改密码
    func changePassword(from oldPassword: String, to newPassword: String) -> Bool {
        guard let oldKey = deriveKey(from: oldPassword) else { return false }

        // 验证旧密码
        let testKey = encryptionKey
        encryptionKey = oldKey
        guard loadMemos() else {
            encryptionKey = testKey
            return false
        }

        // 使用新密码重新加密
        guard let newKey = deriveKey(from: newPassword, regenerateSalt: true) else {
            return false
        }

        encryptionKey = newKey
        saveMemos()
        return true
    }

    /// 检查是否已设置密码
    var hasPassword: Bool {
        UserDefaults.standard.data(forKey: saltKey) != nil
    }

    /// 设置初始密码（首次使用）
    func setInitialPassword(_ password: String) -> Bool {
        guard !hasPassword else { return false }
        guard let key = deriveKey(from: password, regenerateSalt: true) else { return false }

        encryptionKey = key
        memos = []
        saveMemos()
        isLocked = false
        return true
    }

    // MARK: - CRUD 操作

    func addMemo(_ memo: MemoItem) {
        memos.append(memo)
        saveMemos()
    }

    func updateMemo(_ memo: MemoItem) {
        if let index = memos.firstIndex(where: { $0.id == memo.id }) {
            var updated = memo
            updated.updatedAt = Date()
            memos[index] = updated
            saveMemos()
        }
    }

    func deleteMemo(_ memo: MemoItem) {
        memos.removeAll { $0.id == memo.id }
        saveMemos()
    }

    func toggleFavorite(_ memo: MemoItem) {
        if let index = memos.firstIndex(where: { $0.id == memo.id }) {
            memos[index].isFavorite.toggle()
            memos[index].updatedAt = Date()
            saveMemos()
        }
    }

    /// 记录使用
    func recordUsage(_ memo: MemoItem) {
        if let index = memos.firstIndex(where: { $0.id == memo.id }) {
            memos[index].useCount += 1
            memos[index].lastUsedAt = Date()
            saveMemos()
        }
    }

    // MARK: - 搜索和筛选

    func search(_ query: String) -> [MemoItem] {
        guard !query.isEmpty else { return memos }

        return memos.filter { memo in
            memo.title.localizedCaseInsensitiveContains(query) ||
            memo.content.localizedCaseInsensitiveContains(query) ||
            (memo.username?.localizedCaseInsensitiveContains(query) ?? false) ||
            (memo.url?.localizedCaseInsensitiveContains(query) ?? false) ||
            memo.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func filterByType(_ type: MemoType?) -> [MemoItem] {
        guard let type = type else { return memos }
        return memos.filter { $0.type == type }
    }

    var favorites: [MemoItem] {
        memos.filter { $0.isFavorite }
    }

    var recentlyUsed: [MemoItem] {
        memos.filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
    }

    var frequentlyUsed: [MemoItem] {
        memos.filter { $0.useCount > 0 }
            .sorted { $0.useCount > $1.useCount }
    }

    // MARK: - 加密存储

    private func deriveKey(from password: String, regenerateSalt: Bool = false) -> SymmetricKey? {
        var salt: Data

        if regenerateSalt {
            // 生成新的盐值
            salt = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            UserDefaults.standard.set(salt, forKey: saltKey)
        } else {
            // 使用已存储的盐值
            guard let storedSalt = UserDefaults.standard.data(forKey: saltKey) else {
                // 首次使用，生成盐值
                salt = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
                UserDefaults.standard.set(salt, forKey: saltKey)
                return nil
            }
            salt = storedSalt
        }

        // 使用 PBKDF2 风格的密钥派生（简化版）
        let passwordData = Data(password.utf8)
        let combined = passwordData + salt

        // 使用 SHA256 多次哈希来增加计算成本
        var hash = SHA256.hash(data: combined)
        for _ in 0..<10000 {
            hash = SHA256.hash(data: Data(hash))
        }

        return SymmetricKey(data: Data(hash))
    }

    private func saveMemos() {
        guard let key = encryptionKey else { return }

        do {
            let data = try JSONEncoder().encode(memos)
            let encrypted = try encrypt(data, using: key)
            UserDefaults.standard.set(encrypted, forKey: storageKey)
        } catch {
            print("保存备忘录失败: \(error)")
        }
    }

    private func loadMemos() -> Bool {
        guard let key = encryptionKey else { return false }
        guard let encrypted = UserDefaults.standard.data(forKey: storageKey) else {
            return false
        }

        do {
            let decrypted = try decrypt(encrypted, using: key)
            memos = try JSONDecoder().decode([MemoItem].self, from: decrypted)
            return true
        } catch {
            print("加载备忘录失败: \(error)")
            return false
        }
    }

    private func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw MemoError.encryptionFailed
        }
        return combined
    }

    private func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
}

// MARK: - 错误类型

enum MemoError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidPassword

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "加密失败"
        case .decryptionFailed: return "解密失败"
        case .invalidPassword: return "密码错误"
        }
    }
}
