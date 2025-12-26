//
//  HotkeyService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-22.
//  全局快捷键服务 - 注册和管理全局热键
//

import Foundation
import AppKit
import Carbon

class HotkeyService: ObservableObject {
    // 单例
    static let shared = HotkeyService()

    // 已注册的热键 ID
    private var registeredHotkeys: [String: EventHotKeyRef] = [:]

    // 热键回调
    private var hotkeyCallbacks: [UInt32: () -> Void] = [:]

    // 热键 ID 计数器
    private var nextHotkeyID: UInt32 = 1

    private init() {
        setupEventHandler()
    }

    // MARK: - 事件处理器设置

    private func setupEventHandler() {
        // 安装热键事件处理器
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                return service.handleHotkeyEvent(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }

    private func handleHotkeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }

        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard status == noErr else { return status }

        // 调用对应的回调
        if let callback = hotkeyCallbacks[hotkeyID.id] {
            DispatchQueue.main.async {
                callback()
            }
        }

        return noErr
    }

    // MARK: - 注册热键

    /// 注册全局热键
    /// - Parameters:
    ///   - key: 热键标识符
    ///   - keyCode: 键码
    ///   - modifiers: 修饰键
    ///   - callback: 热键触发时的回调
    /// - Returns: 是否注册成功
    @discardableResult
    func registerHotkey(
        key: String,
        keyCode: UInt32,
        modifiers: UInt32,
        callback: @escaping () -> Void
    ) -> Bool {
        // 先注销已存在的同名热键
        unregisterHotkey(key: key)

        let hotkeyID = EventHotKeyID(signature: OSType(0x4255_4255), id: nextHotkeyID) // "BUBU"
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let ref = hotkeyRef else {
            return false
        }

        registeredHotkeys[key] = ref
        hotkeyCallbacks[nextHotkeyID] = callback
        nextHotkeyID += 1

        return true
    }

    /// 注销热键
    func unregisterHotkey(key: String) {
        guard let ref = registeredHotkeys[key] else { return }

        UnregisterEventHotKey(ref)
        registeredHotkeys.removeValue(forKey: key)
    }

    /// 注销所有热键
    func unregisterAllHotkeys() {
        for (_, ref) in registeredHotkeys {
            UnregisterEventHotKey(ref)
        }
        registeredHotkeys.removeAll()
        hotkeyCallbacks.removeAll()
    }

    // MARK: - 便捷方法

    /// 从快捷键字符串解析并注册热键
    /// 格式: "⌘⇧F" 或 "Cmd+Shift+F"
    func registerFromString(key: String, shortcut: String, callback: @escaping () -> Void) -> Bool {
        guard let (keyCode, modifiers) = parseShortcut(shortcut) else {
            return false
        }

        return registerHotkey(key: key, keyCode: keyCode, modifiers: modifiers, callback: callback)
    }

    /// 解析快捷键字符串
    private func parseShortcut(_ shortcut: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        var modifiers: UInt32 = 0
        var keyChar: Character?

        for char in shortcut {
            switch char {
            case "⌘", "⌘":
                modifiers |= UInt32(cmdKey)
            case "⇧":
                modifiers |= UInt32(shiftKey)
            case "⌥":
                modifiers |= UInt32(optionKey)
            case "⌃":
                modifiers |= UInt32(controlKey)
            default:
                if char.isLetter || char.isNumber {
                    keyChar = char
                }
            }
        }

        guard let key = keyChar else { return nil }

        // 获取键码
        guard let keyCode = keyCodeForCharacter(key) else { return nil }

        return (keyCode, modifiers)
    }

    /// 获取字符对应的键码
    private func keyCodeForCharacter(_ char: Character) -> UInt32? {
        let keyCodeMap: [Character: UInt32] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
            "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "n": 45, "m": 46, ".": 47, "`": 50, " ": 49
        ]

        return keyCodeMap[Character(char.lowercased())]
    }
}

// MARK: - 快捷键常量

extension HotkeyService {
    static let searchHotkeyKey = "globalSearch"
    static let translateHotkeyKey = "globalTranslate"
    static let noteHotkeyKey = "globalNote"
}
