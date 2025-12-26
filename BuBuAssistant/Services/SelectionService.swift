//
//  SelectionService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-21.
//  选中文字服务 - 获取系统中当前选中的文字和位置
//

import AppKit
import Carbon.HIToolbox
import ApplicationServices

/// 选中文字和位置信息
struct SelectionInfo {
    let text: String
    let mouseLocation: NSPoint  // 鼠标位置（屏幕坐标）
}

/// 权限状态枚举
enum PermissionStatus {
    case granted              // 权限已授予
    case accessibilityDenied  // 辅助功能权限未授予
    case unknown              // 未知状态
}

/// 选中文字获取服务
/// 通过辅助功能 API 或模拟 Cmd+C 来获取当前选中的文字
class SelectionService {
    static let shared = SelectionService()

    /// 缓存的前台应用（在点击布布之前记录）
    private var cachedFrontApp: NSRunningApplication?
    private var cacheTime: Date?
    private let cacheTimeout: TimeInterval = 2.0 // 缓存有效期 2 秒

    /// 调试日志开关
    private let debugEnabled = false

    private init() {}

    /// 输出调试日志
    private func debugLog(_ message: String) {
        // 调试日志已禁用
    }

    /// 检查辅助功能权限
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        debugLog("辅助功能权限状态: \(trusted)")
        return trusted
    }

    /// 请求辅助功能权限
    func requestAccessibilityPermission() {
        debugLog("请求辅助功能权限...")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// 获取权限状态
    func getPermissionStatus() -> PermissionStatus {
        if checkAccessibilityPermission() {
            return .granted
        }
        return .accessibilityDenied
    }

    /// 打开系统偏好设置 - 辅助功能页面
    func openAccessibilitySettings() {
        debugLog("打开辅助功能设置...")
        // macOS 13+ 使用新的 URL scheme
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 打开系统偏好设置 - 自动化页面
    func openAutomationSettings() {
        debugLog("打开自动化设置...")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 记录当前前台应用（在点击布布之前调用）
    func cacheFrontmostApp() {
        cachedFrontApp = NSWorkspace.shared.frontmostApplication
        cacheTime = Date()
        debugLog("缓存前台应用: \(cachedFrontApp?.localizedName ?? "nil"), PID: \(cachedFrontApp?.processIdentifier ?? 0)")
    }

    /// 获取有效的前台应用（优先使用缓存）
    private func getEffectiveFrontApp() -> NSRunningApplication? {
        // 如果缓存有效，使用缓存的应用
        if let cached = cachedFrontApp,
           let time = cacheTime,
           Date().timeIntervalSince(time) < cacheTimeout {
            debugLog("使用缓存的前台应用: \(cached.localizedName ?? "nil")")
            return cached
        }

        // 否则使用当前前台应用
        let current = NSWorkspace.shared.frontmostApplication
        debugLog("缓存已过期，使用当前前台应用: \(current?.localizedName ?? "nil")")
        return current
    }

    /// 获取当前选中的文字和鼠标位置
    /// - Returns: 选中信息，包含文字和位置
    func getSelectionInfo() -> SelectionInfo? {
        // 获取当前鼠标位置
        let mouseLocation = NSEvent.mouseLocation

        // 获取选中文字
        guard let text = getSelectedText(), !text.isEmpty else {
            return nil
        }

        return SelectionInfo(text: text, mouseLocation: mouseLocation)
    }

    /// 异步获取选中文字和位置
    /// - Parameter completion: 完成回调
    func getSelectionInfoAsync(completion: @escaping (SelectionInfo?) -> Void) {
        // 先获取鼠标位置（在主线程）
        let mouseLocation = NSEvent.mouseLocation

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = self?.getSelectedText()
            DispatchQueue.main.async {
                if let text = text, !text.isEmpty {
                    completion(SelectionInfo(text: text, mouseLocation: mouseLocation))
                } else {
                    completion(nil)
                }
            }
        }
    }

    /// 获取当前选中的文字
    /// - Returns: 选中的文字，如果没有选中则返回 nil
    func getSelectedText() -> String? {
        debugLog("开始获取选中文字...")

        // 检查辅助功能权限
        if !checkAccessibilityPermission() {
            debugLog("辅助功能权限未授予，请求权限...")
            requestAccessibilityPermission()
        }

        // 首先尝试使用辅助功能 API
        if let text = getSelectedTextViaAccessibility() {
            debugLog("通过辅助功能 API 获取成功: \(text.prefix(50))...")
            return text
        }

        debugLog("辅助功能 API 失败，尝试模拟 Cmd+C...")
        // 如果辅助功能失败，回退到模拟 Cmd+C
        if let text = getSelectedTextViaCopy() {
            debugLog("通过 Cmd+C 获取成功: \(text.prefix(50))...")
            return text
        }

        debugLog("Cmd+C 失败，尝试读取剪贴板...")
        // 直接读取剪贴板内容（用户可能已经复制了）
        if let text = getClipboardText() {
            debugLog("通过剪贴板获取成功: \(text.prefix(50))...")
            return text
        }

        debugLog("剪贴板也没有内容")
        return nil
    }

    /// 直接读取剪贴板内容（备用方案）
    func getClipboardText() -> String? {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return text
        }
        return nil
    }

    /// 异步获取选中文字
    /// - Parameter completion: 完成回调，返回选中的文字
    func getSelectedTextAsync(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = self?.getSelectedText()
            DispatchQueue.main.async {
                completion(text)
            }
        }
    }

    // MARK: - 辅助功能 API 方式

    /// 通过辅助功能 API 获取选中文字
    private func getSelectedTextViaAccessibility() -> String? {
        // 获取有效的前台应用（优先使用缓存）
        guard let frontApp = getEffectiveFrontApp() else {
            debugLog("辅助功能: 无法获取前台应用")
            return nil
        }

        debugLog("辅助功能: 目标应用 = \(frontApp.localizedName ?? "nil"), PID = \(frontApp.processIdentifier)")

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // 获取聚焦的元素
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard focusResult == .success, let element = focusedElement else {
            debugLog("辅助功能: 无法获取聚焦元素, 错误码 = \(focusResult.rawValue)")
            return nil
        }

        debugLog("辅助功能: 成功获取聚焦元素")

        // 尝试获取选中的文字
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)

        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            debugLog("辅助功能: 成功获取选中文字")
            return text
        }

        debugLog("辅助功能: 无法获取选中文字, 错误码 = \(textResult.rawValue)")
        return nil
    }

    // MARK: - 模拟复制方式

    /// 通过模拟 Cmd+C 获取选中文字
    private func getSelectedTextViaCopy() -> String? {
        // 获取目标应用（优先使用缓存的前台应用）
        guard let targetApp = getEffectiveFrontApp() else {
            debugLog("Cmd+C: 无法获取目标应用")
            return nil
        }

        debugLog("Cmd+C: 目标应用 = \(targetApp.localizedName ?? "nil"), PID = \(targetApp.processIdentifier)")

        // 保存当前剪贴板内容
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        debugLog("Cmd+C: 保存原剪贴板内容: \(previousContents?.prefix(20) ?? "nil")...")

        // 清空剪贴板以便检测新内容
        pasteboard.clearContents()

        // 先激活目标应用，然后模拟 Cmd+C
        debugLog("Cmd+C: 激活目标应用并发送 Cmd+C")
        activateAndCopy(app: targetApp)

        // 等待剪贴板更新（多次检查）
        var selectedText: String? = nil
        for i in 1...3 {
            usleep(100000) // 100ms
            selectedText = pasteboard.string(forType: .string)
            if let text = selectedText, !text.isEmpty {
                debugLog("Cmd+C: 第 \(i) 次检查成功获取内容")
                break
            }
        }
        debugLog("Cmd+C: 剪贴板新内容: \(selectedText?.prefix(50) ?? "nil")")

        // 恢复原来的剪贴板内容（仅当获取到新内容时才恢复，避免覆盖用户复制的内容）
        if let text = selectedText, !text.isEmpty {
            // 成功获取到新内容，可以恢复原剪贴板
            if let previous = previousContents {
                // 延迟恢复，给调用方足够时间处理
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(previous, forType: .string)
                }
            }
            return text
        }

        // 没有获取到新内容，恢复原剪贴板
        if let previous = previousContents {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }

        return nil
    }

    /// 激活应用并发送 Cmd+C
    private func activateAndCopy(app: NSRunningApplication) {
        // 激活目标应用
        app.activate(options: [])
        usleep(50000) // 50ms 等待激活

        // 创建按下 C 键事件（带 Cmd 修饰符）
        let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        cDown?.flags = .maskCommand

        // 创建释放 C 键事件
        let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        cUp?.flags = .maskCommand

        // 发送事件到指定进程
        cDown?.postToPid(app.processIdentifier)
        cUp?.postToPid(app.processIdentifier)

        // 给系统一点时间处理复制操作
        usleep(50000) // 50ms
    }

    /// 模拟 Cmd+C 复制操作，发送到指定进程（保留原方法供其他地方使用）
    private func simulateCopy(to pid: pid_t) {
        // 创建按下 C 键事件（带 Cmd 修饰符）
        let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        cDown?.flags = .maskCommand

        // 创建释放 C 键事件
        let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        cUp?.flags = .maskCommand

        // 发送事件到指定进程
        cDown?.postToPid(pid)
        cUp?.postToPid(pid)

        // 给系统一点时间处理复制操作
        usleep(50000) // 50ms
    }

    // MARK: - AppleScript 方式

    /// 通过 AppleScript 获取选中文字（使用系统剪贴板）
    /// 注意：此方法需要「自动化」权限，如果权限未授予会返回 nil
    private func getSelectedTextViaAppleScript() -> String? {
        // 获取目标应用
        guard let targetApp = getEffectiveFrontApp() else {
            debugLog("AppleScript: 无法获取目标应用")
            return nil
        }

        let appName = targetApp.localizedName ?? ""
        debugLog("AppleScript: 目标应用 = \(appName)")

        // 如果目标应用名为空，跳过 AppleScript
        guard !appName.isEmpty else {
            debugLog("AppleScript: 应用名为空，跳过")
            return nil
        }

        // 保存当前剪贴板内容
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        debugLog("AppleScript: 保存原剪贴板内容")

        // 清空剪贴板
        pasteboard.clearContents()

        // 使用简化的脚本，直接发送按键而不激活应用（减少权限需求）
        let script = """
        tell application "System Events"
            keystroke "c" using command down
        end tell
        """

        debugLog("AppleScript: 执行复制脚本")
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                let errorNumber = error["NSAppleScriptErrorNumber"] as? Int ?? 0
                debugLog("AppleScript: 执行错误 - 错误码: \(errorNumber), 详情: \(error)")
                // 错误码 -1743 表示权限被拒绝，恢复剪贴板并返回
                if errorNumber == -1743 {
                    debugLog("AppleScript: 自动化权限被拒绝，跳过此方法")
                    if let previous = previousContents {
                        pasteboard.clearContents()
                        pasteboard.setString(previous, forType: .string)
                    }
                    return nil
                }
            }
        }

        // 等待剪贴板更新
        usleep(200000) // 200ms

        // 读取剪贴板
        let selectedText = pasteboard.string(forType: .string)
        debugLog("AppleScript: 剪贴板内容 = \(selectedText?.prefix(50) ?? "nil")")

        // 恢复原剪贴板内容
        if let previous = previousContents {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }

        if let text = selectedText, !text.isEmpty {
            return text
        }

        return nil
    }
}
