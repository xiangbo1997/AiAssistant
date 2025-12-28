//
//  Memo.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-27.
//  备忘录模型 - 用于存储命令、账号密码等敏感信息
//

import Foundation
import SwiftUI

// MARK: - 备忘录类型

enum MemoType: String, CaseIterable, Codable {
    case command = "command"       // 常用命令
    case credential = "credential" // 账号密码
    case snippet = "snippet"       // 代码片段
    case note = "note"             // 普通备注

    var title: String {
        switch self {
        case .command: return "命令"
        case .credential: return "账号"
        case .snippet: return "代码"
        case .note: return "备注"
        }
    }

    var icon: String {
        switch self {
        case .command: return "terminal"
        case .credential: return "key.fill"
        case .snippet: return "chevron.left.forwardslash.chevron.right"
        case .note: return "doc.text"
        }
    }

    var color: Color {
        switch self {
        case .command: return BuBuColors.mintGreen
        case .credential: return BuBuColors.coralPink
        case .snippet: return BuBuColors.lavender
        case .note: return BuBuColors.skyBlue
        }
    }
}

// MARK: - 备忘录数据模型

struct MemoItem: Identifiable, Codable {
    var id: UUID
    var type: MemoType
    var title: String
    var content: String           // 主内容（命令/密码/代码等）
    var username: String?         // 用户名（仅账号类型）
    var url: String?              // 关联URL
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var useCount: Int             // 使用次数

    init(
        id: UUID = UUID(),
        type: MemoType,
        title: String,
        content: String,
        username: String? = nil,
        url: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.content = content
        self.username = username
        self.url = url
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastUsedAt = nil
        self.useCount = 0
    }
}

// MARK: - 备忘录分组

struct MemoGroup: Identifiable {
    let id = UUID()
    let type: MemoType
    let items: [MemoItem]
}
