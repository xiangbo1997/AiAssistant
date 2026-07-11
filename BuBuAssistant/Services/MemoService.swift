//
//  MemoService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-27.
//  备忘录服务 - 管理备忘录的存储、加密和检索
//

import Foundation
import CryptoKit
import CommonCrypto
import Security

class MemoService: ObservableObject {
    static let shared = MemoService()

    @Published var memos: [MemoItem] = []
    @Published var isLocked: Bool = true

    private let storageKey = "bubu_memos_encrypted"
    private let saltKey = "bubu_memos_salt"
    /// KDF 版本标记：区分旧的 SHA256 迭代与新的 PBKDF2，用于无感迁移
    private let kdfVersionKey = "bubu_memos_kdf_version"
    private var encryptionKey: SymmetricKey?

    private init() {
        // 不自动加载，需要解锁后才能访问
    }

    // MARK: - 锁定/解锁

    /// 使用密码解锁备忘录
    func unlock(with password: String) -> Bool {
        guard let salt = UserDefaults.standard.data(forKey: saltKey) else { return false }

        // 数据为空的历史遗留（有盐值但从未存过库）：直接用新算法初始化
        guard let encrypted = UserDefaults.standard.data(forKey: storageKey) else {
            guard let key = Self.pbkdf2Key(password: password, salt: salt, rounds: pbkdf2Rounds) else { return false }
            encryptionKey = key
            memos = []
            UserDefaults.standard.set(kdfVersionCurrent, forKey: kdfVersionKey)
            saveMemos()
            isLocked = false
            return true
        }

        let version = UserDefaults.standard.integer(forKey: kdfVersionKey)
        // version 0 = 旧的 SHA256 迭代格式；version 1 = PBKDF2
        let key: SymmetricKey?
        if version >= kdfVersionCurrent {
            key = Self.pbkdf2Key(password: password, salt: salt, rounds: pbkdf2Rounds)
        } else {
            key = Self.legacySHA256Key(password: password, salt: salt)
        }
        guard let key else { return false }

        encryptionKey = key
        guard loadMemos(from: encrypted) else {
            encryptionKey = nil
            return false
        }

        // 旧格式解锁成功后无感迁移到 PBKDF2（用同一密码重派生新密钥并重加密）
        if version < kdfVersionCurrent {
            migrateToPBKDF2(password: password)
        }

        isLocked = false
        return true
    }

    /// 旧库迁移：重生成盐值 + PBKDF2 密钥，用新密钥重新加密落盘
    private func migrateToPBKDF2(password: String) {
        let newSalt = Self.randomBytes(count: 32)
        guard let newKey = Self.pbkdf2Key(password: password, salt: newSalt, rounds: pbkdf2Rounds) else { return }
        UserDefaults.standard.set(newSalt, forKey: saltKey)
        UserDefaults.standard.set(kdfVersionCurrent, forKey: kdfVersionKey)
        encryptionKey = newKey
        saveMemos()
    }

    /// 锁定备忘录
    func lock() {
        encryptionKey = nil
        memos = []
        isLocked = true
    }

    /// 修改密码
    func changePassword(from oldPassword: String, to newPassword: String) -> Bool {
        // 已解锁状态下改密码：直接用当前内存中的 memos 重加密即可
        guard !isLocked else { return false }

        // 用新密码重新派生（生成新盐值），落盘
        let newSalt = Self.randomBytes(count: 32)
        guard let newKey = Self.pbkdf2Key(password: newPassword, salt: newSalt, rounds: pbkdf2Rounds) else {
            return false
        }

        UserDefaults.standard.set(newSalt, forKey: saltKey)
        UserDefaults.standard.set(kdfVersionCurrent, forKey: kdfVersionKey)
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

        let salt = Self.randomBytes(count: 32)
        guard let key = Self.pbkdf2Key(password: password, salt: salt, rounds: pbkdf2Rounds) else { return false }

        UserDefaults.standard.set(salt, forKey: saltKey)
        UserDefaults.standard.set(kdfVersionCurrent, forKey: kdfVersionKey)
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

    /// PBKDF2 迭代次数（OWASP 对 PBKDF2-HMAC-SHA256 的推荐下限量级）
    private let pbkdf2Rounds: UInt32 = 210_000
    /// 当前 KDF 版本（1 = PBKDF2；0/缺失 = 旧 SHA256 迭代）
    private let kdfVersionCurrent = 1

    /// 旧格式密钥派生：SHA256(password+salt) 迭代 10000 次。仅用于解密迁移旧库
    private static func legacySHA256Key(password: String, salt: Data) -> SymmetricKey? {
        let combined = Data(password.utf8) + salt
        var hash = SHA256.hash(data: combined)
        for _ in 0..<10000 {
            hash = SHA256.hash(data: Data(hash))
        }
        return SymmetricKey(data: Data(hash))
    }

    /// CSPRNG 随机字节
    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// PBKDF2-HMAC-SHA256 派生 32 字节对称密钥
    private static func pbkdf2Key(password: String, salt: Data, rounds: UInt32) -> SymmetricKey? {
        let passwordData = Data(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)

        let status = derived.withUnsafeMutableBytes { derivedBytes -> Int32 in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress, passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress, 32
                    )
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: Data(derived))
    }

    private func saveMemos() {
        guard let key = encryptionKey else { return }

        do {
            let data = try JSONEncoder().encode(memos)
            let encrypted = try encrypt(data, using: key)
            UserDefaults.standard.set(encrypted, forKey: storageKey)
        } catch {
            // 保存失败静默处理，避免日志泄露备忘内容
        }
    }

    private func loadMemos(from encrypted: Data) -> Bool {
        guard let key = encryptionKey else { return false }

        do {
            let decrypted = try decrypt(encrypted, using: key)
            memos = try JSONDecoder().decode([MemoItem].self, from: decrypted)
            return true
        } catch {
            // 解密失败通常意味着密码错误，不打印明文相关信息
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
