//
//  SpriteCharacter.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  精灵角色模型 - 定义角色属性和动画状态
//

import SwiftUI

// MARK: - 角色模型

struct SpriteCharacter: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var imageName: String        // 资源名称或自定义路径
    var isCustom: Bool           // 是否为自定义角色
    var customImagePath: String? // 自定义图片路径

    // 预设角色
    static let bubu = SpriteCharacter(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "布布",
        imageName: "bubu",
        isCustom: false,
        customImagePath: nil
    )

    static let yier = SpriteCharacter(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "伊尔",
        imageName: "yier",
        isCustom: false,
        customImagePath: nil
    )

    // 所有预设角色
    static let presets: [SpriteCharacter] = [bubu, yier]
}

// MARK: - 动画状态

enum SpriteAnimationState: String, CaseIterable {
    case idle       // 待机 - 轻微浮动
    case thinking   // 思考中 - 左右摇摆
    case talking    // 说话中 - 嘴巴动画
    case happy      // 开心 - 跳跃
    case sleeping   // 睡眠 - 闭眼 + Zzz

    var description: String {
        switch self {
        case .idle: return "待机"
        case .thinking: return "思考中"
        case .talking: return "说话中"
        case .happy: return "开心"
        case .sleeping: return "睡眠"
        }
    }
}

// MARK: - 消息气泡

struct SpriteBubble: Identifiable {
    let id = UUID()
    var message: String
    var type: BubbleType
    var duration: TimeInterval // 显示时长，0 表示手动关闭
    var isStreaming: Bool = false      // 打字机进行中（流式输出未结束）
    var actions: [BubbleAction] = []   // 底部操作按钮（如「截图翻译」）

    enum BubbleType {
        case greeting   // 问候
        case reminder   // 提醒
        case response   // AI 回复
        case thinking   // 思考中
        case error      // 错误
    }
}

/// 气泡内的操作按钮
struct BubbleAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let handler: () -> Void
}

// MARK: - 拖拽动作

enum DragAction: String, CaseIterable {
    case search      // 智能搜索
    case translate   // 翻译
    case addNote     // 添加便签
    case memo        // 备忘
    case guidance    // 截图指导

    var title: String {
        switch self {
        case .search: return "智能搜索"
        case .translate: return "翻译"
        case .addNote: return "添加便签"
        case .memo: return "备忘"
        case .guidance: return "截图指导"
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .translate: return "globe"
        case .addNote: return "note.text.badge.plus"
        case .memo: return "key.fill"
        case .guidance: return "camera.viewfinder"
        }
    }
}
