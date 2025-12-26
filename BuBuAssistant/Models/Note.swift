//
//  Note.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  便签模型 - 定义便签属性和状态
//

import Foundation
import SwiftUI

// MARK: - 便签状态

enum NoteStatus: Int16, CaseIterable, Codable {
    case todo = 0       // 待办
    case inProgress = 1 // 进行中
    case completed = 2  // 已完成

    var title: String {
        switch self {
        case .todo: return "待办"
        case .inProgress: return "进行中"
        case .completed: return "已完成"
        }
    }

    var icon: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .todo: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        }
    }
}

// MARK: - 优先级

enum NotePriority: Int16, CaseIterable, Codable {
    case low = 0      // 低
    case medium = 1   // 中
    case high = 2     // 高
    case urgent = 3   // 紧急

    var title: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        case .urgent: return "紧急"
        }
    }

    var icon: String {
        switch self {
        case .low: return "flag"
        case .medium: return "flag.fill"
        case .high: return "flag.2.crossed"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

// MARK: - 重复类型

enum RepeatType: Int16, CaseIterable, Codable {
    case none = 0     // 不重复
    case daily = 1    // 每天
    case weekly = 2   // 每周
    case monthly = 3  // 每月

    var title: String {
        switch self {
        case .none: return "不重复"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }

    var icon: String {
        switch self {
        case .none: return "arrow.counterclockwise"
        case .daily: return "sun.max"
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar"
        }
    }
}

// MARK: - 便签数据传输对象

struct NoteDTO: Identifiable, Codable {
    var id: UUID
    var title: String
    var content: String
    var status: NoteStatus
    var priority: NotePriority
    var tags: [String]
    var reminderDate: Date?
    var repeatType: RepeatType
    var sortOrder: Int32
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        content: String = "",
        status: NoteStatus = .todo,
        priority: NotePriority = .medium,
        tags: [String] = [],
        reminderDate: Date? = nil,
        repeatType: RepeatType = .none,
        sortOrder: Int32 = 0
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.status = status
        self.priority = priority
        self.tags = tags
        self.reminderDate = reminderDate
        self.repeatType = repeatType
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - 便签筛选

struct NoteFilter {
    var searchText: String = ""
    var status: NoteStatus?
    var priority: NotePriority?
    var tags: [String] = []

    var isEmpty: Bool {
        searchText.isEmpty && status == nil && priority == nil && tags.isEmpty
    }
}

// MARK: - 便签排序

enum NoteSortOption: String, CaseIterable {
    case createdAt = "创建时间"
    case updatedAt = "更新时间"
    case priority = "优先级"
    case status = "状态"
    case manual = "手动排序"

    var icon: String {
        switch self {
        case .createdAt: return "clock"
        case .updatedAt: return "clock.arrow.circlepath"
        case .priority: return "flag"
        case .status: return "checklist"
        case .manual: return "hand.draw"
        }
    }
}

// MARK: - 便签视图模式

enum NoteViewMode: String, CaseIterable {
    case list = "列表"
    case card = "卡片"
    case kanban = "看板"

    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .card: return "square.grid.2x2"
        case .kanban: return "rectangle.split.3x1"
        }
    }
}
