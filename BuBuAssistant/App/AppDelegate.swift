//
//  AppDelegate.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  应用代理 - 管理菜单栏、悬浮窗口和应用生命周期
//

import SwiftUI
import Combine
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    // 菜单栏状态项
    private var statusItem: NSStatusItem?

    // 悬浮精灵窗口
    private var spriteWindow: SpriteWindow?

    // 主功能面板窗口
    private var mainPanelWindow: NSWindow?

    // 设置窗口
    private var settingsWindow: NSWindow?

    // 悬浮指导窗口
    private var guidanceWindow: GuidanceWindow?

    // 视图模型
    private var spriteViewModel = SpriteViewModel()
    private var notesViewModel = NotesViewModel()
    @MainActor private lazy var guidanceViewModel = GuidanceViewModel()
    private lazy var chatViewModel = ChatViewModel(spriteViewModel: spriteViewModel)
    private var settingsViewModel: SettingsViewModel { SettingsViewModel.shared }

    // 订阅存储
    private var cancellables = Set<AnyCancellable>()

    // 全局快捷键监听器
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置菜单栏
        setupStatusBar()

        // 创建悬浮精灵窗口
        setupSpriteWindow()

        // 设置全局快捷键
        setupGlobalHotkeys()

        // 监听设置通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettings),
            name: .showSettings,
            object: nil
        )

        // 监听指导窗口通知（精灵右键菜单触发）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showGuidance),
            name: .showGuidance,
            object: nil
        )

        // 隐藏 Dock 图标（可选，根据用户设置）
        if settingsViewModel.hideDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }

        // 监听设置变化
        observeSettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 移除全局快捷键监听
        removeGlobalHotkeys()

        // 保存精灵位置
        if let window = spriteWindow {
            UserDefaults.standard.set(window.frame.origin.x, forKey: "spriteWindowX")
            UserDefaults.standard.set(window.frame.origin.y, forKey: "spriteWindowY")
        }
    }

    // MARK: - 全局快捷键设置

    private func setupGlobalHotkeys() {
        // 全局监听器（应用不在前台时）
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }

        // 本地监听器（应用在前台时）
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleGlobalKeyEvent(event) == true {
                return nil  // 消费事件
            }
            return event
        }
    }

    private func removeGlobalHotkeys() {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    /// 处理全局快捷键事件
    /// - Returns: 是否消费了该事件
    @discardableResult
    private func handleGlobalKeyEvent(_ event: NSEvent) -> Bool {
        // 长按按键时不重复创建窗口或反复启动动作。
        guard !event.isARepeat else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        // 从设置中读取快捷键配置
        let noteShortcut = settingsViewModel.globalNoteShortcut
        let searchShortcut = settingsViewModel.globalSearchShortcut
        let translateShortcut = settingsViewModel.globalTranslateShortcut

        // 主功能快捷键（Command + Shift）
        if matchShortcut(modifiers: modifiers, keyCode: keyCode, shortcut: AppShortcuts.chat, defaultMods: [.command, .shift], defaultKey: kVK_ANSI_C) {
            DispatchQueue.main.async { [weak self] in
                self?.showPanel(type: .chat)
            }
            return true
        }

        if matchShortcut(modifiers: modifiers, keyCode: keyCode, shortcut: noteShortcut, defaultMods: [.command, .shift], defaultKey: kVK_ANSI_N) {
            DispatchQueue.main.async { [weak self] in
                self?.showPanel(type: .notes)
            }
            return true
        }

        if matchShortcut(modifiers: modifiers, keyCode: keyCode, shortcut: searchShortcut, defaultMods: [.command, .shift], defaultKey: kVK_ANSI_F) {
            DispatchQueue.main.async { [weak self] in
                self?.showPanel(type: .search)
            }
            return true
        }

        if matchShortcut(modifiers: modifiers, keyCode: keyCode, shortcut: translateShortcut, defaultMods: [.command, .shift], defaultKey: kVK_ANSI_T) {
            // 先尝试获取选中的文字
            SelectionService.shared.getSelectedTextAsync { [weak self] selectedText in
                self?.showPanel(type: .translation)

                // 如果有选中文字，发送通知让翻译视图处理
                if let text = selectedText, !text.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(
                            name: .translateSelectedText,
                            object: text
                        )
                    }
                }
            }
            return true
        }

        if matchShortcut(modifiers: modifiers, keyCode: keyCode, shortcut: AppShortcuts.memo, defaultMods: [.command, .shift], defaultKey: kVK_ANSI_M) {
            DispatchQueue.main.async { [weak self] in
                self?.showPanel(type: .memo)
            }
            return true
        }

        if matchShortcut(modifiers: modifiers, keyCode: keyCode, shortcut: AppShortcuts.guidance, defaultMods: [.command, .shift], defaultKey: kVK_ANSI_G) {
            DispatchQueue.main.async { [weak self] in
                self?.showGuidance()
            }
            return true
        }

        // 角色能力快捷键（Command + Control）
        let spriteShortcuts: [(String, Int, () -> Void)] = [
            (AppShortcuts.quickChat, kVK_ANSI_C, { [weak self] in self?.showSpriteQuickChat() }),
            (AppShortcuts.screenshotTranslation, kVK_ANSI_T, { [weak self] in self?.translateScreenshot() }),
            (AppShortcuts.toggleSprite, kVK_ANSI_B, { [weak self] in self?.toggleSpriteWindow() }),
            (AppShortcuts.toggleDimension, kVK_ANSI_5, { [weak self] in self?.toggleSpriteDimension() }),
            (AppShortcuts.walk, kVK_ANSI_1, { [weak self] in self?.playWalking() }),
            (AppShortcuts.run, kVK_ANSI_2, { [weak self] in self?.playRunning() }),
            (AppShortcuts.jump, kVK_ANSI_3, { [weak self] in self?.playJumping() }),
            (AppShortcuts.wave, kVK_ANSI_4, { [weak self] in self?.playWaving() }),
            (AppShortcuts.stopAction, kVK_ANSI_0, { [weak self] in self?.stopSpriteAction() })
        ]

        for (shortcut, defaultKey, action) in spriteShortcuts
        where matchShortcut(
            modifiers: modifiers,
            keyCode: keyCode,
            shortcut: shortcut,
            defaultMods: [.command, .control],
            defaultKey: defaultKey
        ) {
            DispatchQueue.main.async(execute: action)
            return true
        }

        return false
    }

    /// 匹配快捷键
    private func matchShortcut(modifiers: NSEvent.ModifierFlags, keyCode: UInt16, shortcut: String, defaultMods: NSEvent.ModifierFlags, defaultKey: Int) -> Bool {
        // 空配置才回退默认值；非空字符串统一按同一解析器精确匹配。
        if shortcut.isEmpty {
            return modifiers == defaultMods && keyCode == defaultKey
        }

        // 解析自定义快捷键
        var expectedMods: NSEvent.ModifierFlags = []
        var expectedKey: Character?

        for char in shortcut {
            switch char {
            case "⌘":
                expectedMods.insert(.command)
            case "⇧":
                expectedMods.insert(.shift)
            case "⌥":
                expectedMods.insert(.option)
            case "⌃":
                expectedMods.insert(.control)
            default:
                if char.isLetter || char.isNumber {
                    expectedKey = char
                }
            }
        }

        guard let key = expectedKey, let expectedKeyCode = keyCodeForCharacter(key) else {
            return modifiers == defaultMods && keyCode == defaultKey
        }

        return modifiers == expectedMods && keyCode == expectedKeyCode
    }

    /// 获取字符对应的键码
    private func keyCodeForCharacter(_ char: Character) -> UInt16? {
        let keyCodeMap: [Character: UInt16] = [
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

    // MARK: - 菜单栏设置

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // 使用 SF Symbol 作为菜单栏图标
            if let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "布布助手") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true  // 设置为模板图像，自动适应深色/浅色模式
                button.image = image
            }
            button.toolTip = "布布助手"
        }

        // 创建菜单
        let menu = NSMenu()

        // 和布布聊天
        let chatItem = NSMenuItem(title: "💬 和布布聊天", action: #selector(showChatPanel), keyEquivalent: "c")
        chatItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(chatItem)

        let quickChatItem = NSMenuItem(title: "⌨️ 角色旁快聊", action: #selector(showSpriteQuickChat), keyEquivalent: "c")
        quickChatItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(quickChatItem)

        menu.addItem(NSMenuItem.separator())

        // 便签管理
        let notesItem = NSMenuItem(title: "📝 便签管理", action: #selector(showNotesPanel), keyEquivalent: "n")
        notesItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(notesItem)

        // 智能搜索
        let searchItem = NSMenuItem(title: "🔍 智能搜索", action: #selector(showSearchPanel), keyEquivalent: "f")
        searchItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(searchItem)

        // 翻译
        let translateItem = NSMenuItem(title: "🌐 翻译", action: #selector(showTranslationPanel), keyEquivalent: "t")
        translateItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(translateItem)

        let screenshotTranslationItem = NSMenuItem(title: "🔎 截图翻译", action: #selector(translateScreenshot), keyEquivalent: "t")
        screenshotTranslationItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(screenshotTranslationItem)

        // 备忘
        let memoItem = NSMenuItem(title: "🔐 备忘", action: #selector(showMemoPanel), keyEquivalent: "m")
        memoItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(memoItem)

        menu.addItem(NSMenuItem.separator())

        // 截图求指导
        let guidanceItem = NSMenuItem(title: "📸 截图求指导", action: #selector(showGuidance), keyEquivalent: "g")
        guidanceItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(guidanceItem)

        // 角色动作
        let actionsItem = NSMenuItem(title: "🎬 角色动作", action: nil, keyEquivalent: "")
        let actionsMenu = NSMenu()
        let actionItems: [(String, Selector, String)] = [
            ("走路", #selector(playWalking), "1"),
            ("跑步", #selector(playRunning), "2"),
            ("跳跃", #selector(playJumping), "3"),
            ("挥手", #selector(playWaving), "4"),
            ("停止动作", #selector(stopSpriteAction), "0")
        ]
        for (title, selector, key) in actionItems {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = [.command, .control]
            actionsMenu.addItem(item)
        }
        actionsItem.submenu = actionsMenu
        menu.addItem(actionsItem)

        // 显示/隐藏精灵
        let toggleSpriteItem = NSMenuItem(title: "👁 显示/隐藏精灵", action: #selector(toggleSpriteWindow), keyEquivalent: "b")
        toggleSpriteItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(toggleSpriteItem)

        let toggleDimensionItem = NSMenuItem(title: "🧊 切换 2D/3D", action: #selector(toggleSpriteDimension), keyEquivalent: "5")
        toggleDimensionItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(toggleDimensionItem)

        // 设置
        let settingsItem = NSMenuItem(title: "⚙️ 设置", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 帮助
        let helpItem = NSMenuItem(title: "❓ 帮助", action: #selector(showHelp), keyEquivalent: "")
        menu.addItem(helpItem)

        // 退出
        let quitItem = NSMenuItem(title: "🚪 退出", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - 悬浮窗口设置

    private func setupSpriteWindow() {
        spriteWindow = SpriteWindow(
            spriteViewModel: spriteViewModel,
            notesViewModel: notesViewModel,
            chatViewModel: chatViewModel,
            onShowPanel: { [weak self] panelType in
                self?.showPanel(type: panelType)
            }
        )

        // 恢复上次位置
        let savedX = UserDefaults.standard.double(forKey: "spriteWindowX")
        let savedY = UserDefaults.standard.double(forKey: "spriteWindowY")

        var useDefaultPosition = true

        // 检查保存的位置是否在当前可用屏幕范围内
        if savedX != 0 || savedY != 0 {
            let savedPoint = NSPoint(x: savedX, y: savedY)
            // 检查该点是否在任一屏幕的可见区域内
            for screen in NSScreen.screens {
                if screen.visibleFrame.contains(savedPoint) {
                    spriteWindow?.setFrameOrigin(savedPoint)
                    useDefaultPosition = false
                    break
                }
            }
        }

        // 使用默认位置：主屏幕右下角
        if useDefaultPosition {
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowSize = spriteWindow?.frame.size ?? NSSize(width: 280, height: 400)
                let x = screenFrame.maxX - windowSize.width - 50
                let y = screenFrame.minY + 100
                spriteWindow?.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        spriteWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 设置监听

    private func observeSettings() {
        // 监听角色变化
        settingsViewModel.$currentCharacter
            .receive(on: RunLoop.main)
            .sink { [weak self] character in
                self?.spriteViewModel.currentCharacter = character
            }
            .store(in: &cancellables)

        // 外观设置必须持续同步；此前只在启动时赋值，滑块变化只能等重启后生效。
        settingsViewModel.$spriteScale
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] scale in
                self?.spriteViewModel.scale = CGFloat(min(max(scale, 0.5), 2.0))
            }
            .store(in: &cancellables)

        settingsViewModel.$spriteOpacity
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] opacity in
                self?.spriteViewModel.opacity = min(max(opacity, 0.3), 1.0)
            }
            .store(in: &cancellables)

        settingsViewModel.$enableAnimation
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.spriteViewModel.isAnimating = enabled
            }
            .store(in: &cancellables)

        settingsViewModel.$sleepDelay
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] delay in
                self?.spriteViewModel.setSleepDelay(delay)
            }
            .store(in: &cancellables)
    }

    // MARK: - 菜单操作

    @objc private func showChatPanel() {
        showPanel(type: .chat)
    }

    @objc private func showNotesPanel() {
        showPanel(type: .notes)
    }

    @objc private func showSearchPanel() {
        showPanel(type: .search)
    }

    @objc private func showTranslationPanel() {
        showPanel(type: .translation)
    }

    @objc private func showMemoPanel() {
        showPanel(type: .memo)
    }

    @objc private func showSpriteQuickChat() {
        revealSpriteWindow()
        NotificationCenter.default.post(name: .showSpriteQuickChat, object: nil)
    }

    @objc private func translateScreenshot() {
        revealSpriteWindow()
        spriteViewModel.translateScreenshot()
    }

    @objc private func toggleSpriteDimension() {
        revealSpriteWindow()
        settingsViewModel.use3DSprite.toggle()
    }

    @objc private func playWalking() {
        revealSpriteWindow()
        spriteViewModel.playWalking()
    }

    @objc private func playRunning() {
        revealSpriteWindow()
        spriteViewModel.playRunning()
    }

    @objc private func playJumping() {
        revealSpriteWindow()
        spriteViewModel.showHappy()
    }

    @objc private func playWaving() {
        revealSpriteWindow()
        spriteViewModel.playWaving()
    }

    @objc private func stopSpriteAction() {
        revealSpriteWindow()
        spriteViewModel.stopCurrentAction()
    }

    private func revealSpriteWindow() {
        if spriteWindow == nil {
            setupSpriteWindow()
        }
        spriteWindow?.orderFrontRegardless()
    }

    @objc private func toggleSpriteWindow() {
        if let window = spriteWindow {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            setupSpriteWindow()
        }
    }

    // MARK: - 指导窗口

    @MainActor @objc private func showGuidance() {
        if guidanceWindow == nil {
            guidanceWindow = GuidanceWindow(viewModel: guidanceViewModel)
        }
        guidanceWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showSettings() {
        // 如果设置窗口已存在，直接显示
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 创建设置窗口
        let settingsView = SettingsView()
            .environmentObject(settingsViewModel)
            .environmentObject(spriteViewModel)
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "设置"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showHelp() {
        if let url = URL(string: "https://github.com/your-repo/BuBuAssistant") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - 面板显示

    private func showPanel(type: PanelType) {
        // 如果窗口已存在，直接显示
        if let window = mainPanelWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // 通知切换到对应面板
            NotificationCenter.default.post(name: .switchPanel, object: type)
            return
        }

        // 创建新窗口
        let contentView = MainPanelView(initialPanel: type)
            .environmentObject(notesViewModel)
            .environmentObject(spriteViewModel)
            .environmentObject(settingsViewModel)
            .environmentObject(chatViewModel)
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "布布助手"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("MainPanel")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 500)
        // 主面板保持在其它应用普通窗口之上；角色使用更高的 statusBar 层级，
        // 因而仍会自然显示在主面板前方。
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 设置窗口外观
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear

        mainPanelWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 面板类型

enum PanelType {
    case chat
    case notes
    case search
    case translation
    case memo
    case guidance
}

// MARK: - 通知名称

extension Notification.Name {
    static let switchPanel = Notification.Name("switchPanel")
    static let translateSelectedText = Notification.Name("translateSelectedText")
    static let showSettings = Notification.Name("showSettings")
    static let showGuidance = Notification.Name("showGuidance")
    static let showSpriteQuickChat = Notification.Name("showSpriteQuickChat")
}
