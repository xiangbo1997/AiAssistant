//
//  SpriteWindow.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  悬浮精灵窗口 - 透明无边框的悬浮窗口
//

import SwiftUI
import AppKit

class SpriteWindow: NSPanel {
    private var spriteViewModel: SpriteViewModel
    private var notesViewModel: NotesViewModel
    private var onShowPanel: ((PanelType) -> Void)?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    init(
        spriteViewModel: SpriteViewModel,
        notesViewModel: NotesViewModel,
        onShowPanel: ((PanelType) -> Void)?
    ) {
        self.spriteViewModel = spriteViewModel
        self.notesViewModel = notesViewModel
        self.onShowPanel = onShowPanel

        // 窗口大小 - 增加高度以容纳气泡和翻译结果
        let windowSize = NSSize(width: 280, height: 400)

        super.init(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setupWindow()
        setupContentView()
        setupMouseMonitor()
    }

    deinit {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// 设置鼠标监听，在点击发生前缓存前台应用
    private func setupMouseMonitor() {
        // 全局监听器：监听所有应用的鼠标事件，在点击布布窗口之前缓存前台应用
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            // 全局事件发生时，检查鼠标是否在本窗口范围内
            guard let window = self else { return }
            let mouseLocation = NSEvent.mouseLocation
            if window.frame.contains(mouseLocation) {
                // 鼠标在窗口内，缓存当前前台应用（此时还没切换焦点）
                SelectionService.shared.cacheFrontmostApp()
            }
        }

        // 本地监听器：作为备份
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let window = self, event.window == window {
                SelectionService.shared.cacheFrontmostApp()
            }
            return event
        }
    }

    private func setupWindow() {
        // 窗口层级 - 悬浮但不遮挡全屏应用
        level = .floating

        // 透明背景
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // 允许在所有空间显示
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 不显示在任务切换器中
        collectionBehavior.insert(.transient)

        // 允许移动
        isMovable = true
        isMovableByWindowBackground = true

        // 不成为 key window（不抢焦点）
        becomesKeyOnlyIfNeeded = true

        // 窗口关闭时隐藏而不是释放
        isReleasedWhenClosed = false

        // 设置最小/最大尺寸
        minSize = NSSize(width: 100, height: 150)
        maxSize = NSSize(width: 400, height: 600)
    }

    private func setupContentView() {
        let spriteView = SpriteContainerView(
            spriteViewModel: spriteViewModel,
            notesViewModel: notesViewModel,
            onShowPanel: onShowPanel
        )

        let hostingView = NSHostingView(rootView: spriteView)
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]

        contentView = hostingView
    }

    // 允许窗口接收拖拽
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - 精灵容器视图

struct SpriteContainerView: View {
    @ObservedObject var spriteViewModel: SpriteViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    var onShowPanel: ((PanelType) -> Void)?

    var body: some View {
        ZStack {
            // 精灵视图
            SpriteView(viewModel: spriteViewModel)
                .onTapGesture(count: 2) {
                    handleDoubleTap()
                }
                .onTapGesture(count: 1) {
                    handleTap()
                }
                .contextMenu {
                    contextMenuContent
                }

            // 动作选择菜单
            if spriteViewModel.showActionMenu {
                ActionMenuView(
                    droppedText: spriteViewModel.droppedText,
                    onAction: { action in
                        // 对于翻译操作，先保存文字再执行
                        let textToProcess = spriteViewModel.droppedText
                        spriteViewModel.showActionMenu = false

                        if action == .translate {
                            // 翻译操作：直接在气泡中显示结果
                            spriteViewModel.handleDropForTranslation(text: textToProcess)
                        } else {
                            // 其他操作：执行默认行为
                            spriteViewModel.executeAction(action)
                            handleAction(action)
                        }
                    },
                    onCancel: {
                        spriteViewModel.cancelAction()
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 280, height: 400)
        .onDrop(of: [.text, .plainText, .utf8PlainText], isTargeted: $spriteViewModel.isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onChange(of: spriteViewModel.isDragOver) { _, isOver in
            if isOver {
                spriteViewModel.handleDragEnter()
            } else if !spriteViewModel.showActionMenu {
                spriteViewModel.handleDragExit()
            }
        }
        .onAppear {
            // 显示问候
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                spriteViewModel.showGreeting()
            }
        }
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onShowPanel?(.notes)
        } label: {
            Label("便签管理", systemImage: "note.text")
        }

        Button {
            onShowPanel?(.search)
        } label: {
            Label("智能搜索", systemImage: "magnifyingglass")
        }

        Button {
            onShowPanel?(.translation)
        } label: {
            Label("翻译", systemImage: "globe")
        }

        Divider()

        Menu("切换角色") {
            ForEach(spriteViewModel.allCharacters) { character in
                Button {
                    spriteViewModel.currentCharacter = character
                } label: {
                    HStack {
                        Text(character.name)
                        if character.id == spriteViewModel.currentCharacter.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        Button {
            NotificationCenter.default.post(name: .showSettings, object: nil)
        } label: {
            Label("设置", systemImage: "gear")
        }
    }

    // MARK: - 交互处理

    private func handleTap() {
        // 只重置睡眠计时器，不隐藏气泡
        spriteViewModel.resetSleepTimer()
        let showPanel = onShowPanel

        // 尝试获取选中文字（无论权限状态，都尝试通过多种方式获取）
        SelectionService.shared.getSelectedTextAsync { [weak spriteViewModel] selectedText in
            if let text = selectedText, !text.isEmpty {
                // 有选中文字，显示操作菜单
                spriteViewModel?.handleDrop(text: text)
            } else {
                // 没有选中文字，显示主面板
                showPanel?(.notes)
            }
        }
    }

    private func handleDoubleTap() {
        // 只重置睡眠计时器，不隐藏气泡（翻译结果需要保持显示）
        spriteViewModel.resetSleepTimer()

        // 检查权限状态
        let hasPermission = SelectionService.shared.checkAccessibilityPermission()

        // 无论权限状态如何，都尝试获取选中文字（会通过多种方式尝试，包括剪贴板）
        SelectionService.shared.getSelectedTextAsync { [weak spriteViewModel] selectedText in
            if let text = selectedText, !text.isEmpty {
                // 有选中文字，直接翻译
                spriteViewModel?.handleDropForTranslation(text: text)
            } else {
                // 没有选中文字
                if !hasPermission {
                    // 权限未授予，提示用户授权
                    spriteViewModel?.showBubble(
                        message: "需要「辅助功能」权限才能自动获取选中文字~\n\n请在系统设置中授权，或者先复制文字(Cmd+C)再双击我。",
                        type: .greeting,
                        duration: 6
                    )
                    // 打开设置
                    SelectionService.shared.openAccessibilitySettings()
                } else {
                    // 权限已授予但没有选中文字
                    spriteViewModel?.showBubble(
                        message: "没有检测到选中的文字~\n\n请先在其他应用中选中文字，然后双击我进行翻译。\n\n小提示：也可以先复制文字(Cmd+C)，我会自动读取剪贴板内容。",
                        type: .greeting,
                        duration: 6
                    )
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // 尝试加载文本
            if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, error in
                    DispatchQueue.main.async {
                        if let data = data as? Data,
                           let text = String(data: data, encoding: .utf8) {
                            spriteViewModel.handleDrop(text: text)
                        } else if let text = data as? String {
                            spriteViewModel.handleDrop(text: text)
                        }
                    }
                }
                return
            }
        }
    }

    private func handleAction(_ action: DragAction) {
        switch action {
        case .search:
            onShowPanel?(.search)
        case .translate:
            // 直接在气泡中显示翻译结果
            spriteViewModel.handleDropForTranslation(text: spriteViewModel.droppedText)
        case .addNote:
            onShowPanel?(.notes)
        }
    }
}

// MARK: - 动作选择菜单

struct ActionMenuView: View {
    let droppedText: String
    let onAction: (DragAction) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // 预览文本
            Text(droppedText.prefix(50) + (droppedText.count > 50 ? "..." : ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                )

            // 动作按钮
            HStack(spacing: 12) {
                ForEach(DragAction.allCases, id: \.self) { action in
                    ActionButton(action: action) {
                        onAction(action)
                    }
                }
            }

            // 取消按钮
            Button("取消") {
                onCancel()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
    }
}

// MARK: - 动作按钮

struct ActionButton: View {
    let action: DragAction
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isHovered ? .white : .primary)

                Text(action.title.replacingOccurrences(of: "🔍 ", with: "")
                    .replacingOccurrences(of: "🌐 ", with: "")
                    .replacingOccurrences(of: "📝 ", with: ""))
                    .font(.caption2)
                    .foregroundColor(isHovered ? .white : .secondary)
            }
            .frame(width: 60, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
