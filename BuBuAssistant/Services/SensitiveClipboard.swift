//
//  SensitiveClipboard.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-07-11.
//  敏感剪贴板：复制密码等敏感内容时标记为「保密」并定时自动清空，
//  避免密码长期驻留系统剪贴板被其他应用读取
//

import AppKit

enum SensitiveClipboard {
    /// 自动清空延迟（秒）
    private static let clearDelay: TimeInterval = 60

    /// 待清空的内容快照，用于到期时确认剪贴板未被用户改写才清空
    private static var pendingSnapshot: String?

    /// 复制敏感文本：标记 ConcealedType（部分剪贴板管理器据此不记录历史），
    /// 并在 clearDelay 后自动清空（若期间用户复制了别的内容则不清空）
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // org.nspasteboard.ConcealedType 是社区约定的敏感内容标记
        pasteboard.setString(text, forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.setString(text, forType: .string)

        pendingSnapshot = text
        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay) {
            clearIfUnchanged()
        }
    }

    /// 到期清空：仅当剪贴板仍是我们写入的敏感内容时才清空，
    /// 避免抹掉用户后续复制的其他内容
    private static func clearIfUnchanged() {
        guard let snapshot = pendingSnapshot else { return }
        if NSPasteboard.general.string(forType: .string) == snapshot {
            NSPasteboard.general.clearContents()
        }
        pendingSnapshot = nil
    }
}
