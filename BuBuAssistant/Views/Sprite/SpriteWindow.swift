//
//  SpriteWindow.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  悬浮精灵窗口 - 透明无边框的悬浮窗口
//

import SwiftUI
import AppKit
import Combine

class SpriteWindow: NSPanel {
    private var spriteViewModel: SpriteViewModel
    private var notesViewModel: NotesViewModel
    private var chatViewModel: ChatViewModel
    private var onShowPanel: ((PanelType) -> Void)?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var movementCancellable: AnyCancellable?
    private var movementTimer: Timer?
    private var isUserDragging = false
    private var isTurningAtEdge = false
    private var movementPauseUntil = Date.distantPast

    init(
        spriteViewModel: SpriteViewModel,
        notesViewModel: NotesViewModel,
        chatViewModel: ChatViewModel,
        onShowPanel: ((PanelType) -> Void)?
    ) {
        self.spriteViewModel = spriteViewModel
        self.notesViewModel = notesViewModel
        self.chatViewModel = chatViewModel
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
        setupMovementObserver()
    }

    deinit {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        movementTimer?.invalidate()
        movementCancellable?.cancel()
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
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]
        ) { [weak self] event in
            if let window = self, event.window == window {
                switch event.type {
                case .leftMouseDown:
                    SelectionService.shared.cacheFrontmostApp()
                case .leftMouseDragged:
                    window.isUserDragging = true
                case .leftMouseUp:
                    window.isUserDragging = false
                case .rightMouseDown:
                    // 角色正在移动时先停住，给右键菜单留出稳定的点击时间。
                    window.movementPauseUntil = Date().addingTimeInterval(6)
                default:
                    break
                }
            }
            return event
        }
    }

    /// 走路/跑步不仅原地踏步，还会驱动透明悬浮窗在桌面上移动。
    private func setupMovementObserver() {
        movementCancellable = spriteViewModel.$animationState
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                switch state {
                case .walking:
                    self?.startWindowMovement(pointsPerSecond: 72)
                case .running:
                    self?.startWindowMovement(pointsPerSecond: 175)
                default:
                    self?.stopWindowMovement()
                }
            }
    }

    private func startWindowMovement(pointsPerSecond: CGFloat) {
        movementTimer?.invalidate()
        movementPauseUntil = .distantPast
        faceDirectionWithMoreSpace()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.advanceWindow(pointsPerSecond: pointsPerSecond)
        }
        movementTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopWindowMovement() {
        movementTimer?.invalidate()
        movementTimer = nil
        isTurningAtEdge = false
    }

    private func advanceWindow(pointsPerSecond: CGFloat) {
        guard !isUserDragging, !isTurningAtEdge, Date() >= movementPauseUntil else { return }

        let activeScreen = screen ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main
        guard let visibleFrame = activeScreen?.visibleFrame else { return }

        let minX = visibleFrame.minX
        let maxX = max(visibleFrame.maxX - frame.width, minX)
        var nextX = frame.origin.x + spriteViewModel.facingDirection * pointsPerSecond / 60.0

        if nextX >= maxX {
            nextX = maxX
            turnAtEdge(toward: -1)
        } else if nextX <= minX {
            nextX = minX
            turnAtEdge(toward: 1)
        }

        setFrameOrigin(NSPoint(x: nextX, y: frame.origin.y))
    }

    private func faceDirectionWithMoreSpace() {
        let activeScreen = screen ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main
        guard let visibleFrame = activeScreen?.visibleFrame else { return }
        let leftSpace = frame.minX - visibleFrame.minX
        let rightSpace = visibleFrame.maxX - frame.maxX
        spriteViewModel.facingDirection = rightSpace >= leftSpace ? 1 : -1
    }

    private func turnAtEdge(toward direction: CGFloat) {
        guard !isTurningAtEdge else { return }
        isTurningAtEdge = true
        spriteViewModel.facingDirection = direction
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            self?.isTurningAtEdge = false
        }
    }

    private func setupWindow() {
        // 角色必须稳定显示在其它应用之上；statusBar 高于普通 floating 窗口，
        // 同时低于系统级 screenSaver 层，避免遮挡锁屏和关键系统界面。
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false

        // 透明背景
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // 允许在所有空间显示
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

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
            chatViewModel: chatViewModel,
            onRequestChatFocus: { [weak self] in
                self?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            },
            onShowPanel: onShowPanel
        )

        let hostingView = NSHostingView(rootView: spriteView)
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]

        // 确保宿主视图图层完全透明，不绘制任何窗口背景
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

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
    @ObservedObject var chatViewModel: ChatViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel = SettingsViewModel.shared
    var onRequestChatFocus: (() -> Void)?
    var onShowPanel: ((PanelType) -> Void)?

    @State private var isQuickChatPresented = false
    @State private var quickChatDraft = ""

    var body: some View {
        ZStack {
            // 根据设置选择 2D 或 3D 精灵视图
            if settingsViewModel.use3DSprite {
                // 3D 模式单击由场景内命中检测接管：点到身体部位触发互动，
                // 未命中角色时回落到原有单击行为（取词/打开面板）
                Sprite3DView(viewModel: spriteViewModel, onBackgroundTap: {
                    handleTap()
                }, onBodyPartTap: { part in
                    handleBodyPartTap(part)
                }, onDoubleTap: {
                    handleDoubleTap()
                })
                .contextMenu {
                    contextMenuContent
                }
            } else {
                SpriteView(viewModel: spriteViewModel, onBodyPartTap: { part in
                    handleBodyPartTap(part)
                }, onBackgroundTap: {
                    handleTap()
                }, onDoubleTap: {
                    handleDoubleTap()
                })
                    .contextMenu {
                        contextMenuContent
                    }
            }

            // 动作选择菜单
            if spriteViewModel.showActionMenu {
                ActionMenuView(
                    droppedText: spriteViewModel.droppedText,
                    onAction: { action in
                        // 对于翻译操作，先保存文字再执行
                        let textToProcess = spriteViewModel.droppedText
                        withAnimation(.easeOut(duration: 0.15)) {
                            spriteViewModel.showActionMenu = false
                        }

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
                // 从精灵处弹出，与说话气泡同一套动效语言
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5, anchor: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            if !spriteViewModel.showActionMenu, isQuickChatPresented {
                quickChatOverlay
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
        .onReceive(NotificationCenter.default.publisher(for: .showSpriteQuickChat)) { _ in
            // 全局快捷键只发出意图，实际仍复用手机点击的完整快聊状态流。
            presentQuickChat()
        }
        .onAppear {
            // 首次升级只提示一次入口，随后完全由模型本体承载聊天，不常驻额外按钮。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let hintKey = "didShowPhoneChatHintV1"
                let hasPhone = ["bubu", "yier_phone"].contains(spriteViewModel.currentCharacter.imageName)
                if hasPhone, !UserDefaults.standard.bool(forKey: hintKey) {
                    spriteViewModel.showBubble(
                        message: "点点我手里的手机，就能直接和我聊天啦~",
                        type: .greeting,
                        duration: 5
                    )
                    UserDefaults.standard.set(true, forKey: hintKey)
                } else {
                    spriteViewModel.showGreeting()
                }
            }
        }
    }

    // MARK: - 角色旁快速聊天

    @ViewBuilder
    private var quickChatOverlay: some View {
        VStack {
            Spacer()
            SpriteQuickChatComposer(
                draft: $quickChatDraft,
                chatViewModel: chatViewModel,
                onSent: dismissQuickChat,
                onClose: dismissQuickChat,
                onOpenFullChat: {
                    dismissQuickChat()
                    onShowPanel?(.chat)
                }
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 132)
            .transition(.scale(scale: 0.82, anchor: .bottom).combined(with: .opacity))
        }
    }

    private func presentQuickChat() {
        if spriteViewModel.animationState == .sleeping {
            spriteViewModel.wakeUp()
        }
        if spriteViewModel.animationState == .walking || spriteViewModel.animationState == .running {
            spriteViewModel.stopCurrentAction()
        }
        if !chatViewModel.isStreaming {
            spriteViewModel.hideBubble()
        }
        spriteViewModel.setQuickChatPresented(true)
        onRequestChatFocus?()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            isQuickChatPresented = true
        }
    }

    private func dismissQuickChat() {
        spriteViewModel.setQuickChatPresented(false)
        withAnimation(.easeOut(duration: 0.18)) {
            isQuickChatPresented = false
        }
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onShowPanel?(.chat)
        } label: {
            Label("和布布聊天", systemImage: "bubble.left.and.bubble.right")
        }

        Divider()

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

        Button {
            spriteViewModel.translateScreenshot()
        } label: {
            Label("截图翻译", systemImage: "text.viewfinder")
        }

        Button {
            onShowPanel?(.memo)
        } label: {
            Label("备忘", systemImage: "key.fill")
        }

        Button {
            NotificationCenter.default.post(name: .showGuidance, object: nil)
        } label: {
            Label("截图求指导", systemImage: "camera.viewfinder")
        }

        Divider()

        Menu("动作") {
            Button {
                spriteViewModel.playWalking()
            } label: {
                Label("走路", systemImage: "figure.walk")
            }

            Button {
                spriteViewModel.playRunning()
            } label: {
                Label("跑步", systemImage: "figure.run")
            }

            Button {
                spriteViewModel.showHappy()
            } label: {
                Label("跳跃", systemImage: "arrow.up")
            }

            Button {
                spriteViewModel.playWaving()
            } label: {
                Label("挥手", systemImage: "hand.wave")
            }

            Divider()

            Button {
                spriteViewModel.stopCurrentAction()
            } label: {
                Label("停止动作", systemImage: "stop.fill")
            }
        }

        Divider()

        Menu("切换角色") {
            ForEach(spriteViewModel.allCharacters) { character in
                Button {
                    // 走 SettingsViewModel 持久化（重启保持），经 AppDelegate 管道同步回精灵
                    settingsViewModel.currentCharacter = character
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

        // 切换 2D/3D 模式
        Button {
            settingsViewModel.use3DSprite.toggle()
        } label: {
            Label(
                settingsViewModel.use3DSprite ? "切换到 2D 模式" : "切换到 3D 模式",
                systemImage: settingsViewModel.use3DSprite ? "square" : "cube"
            )
        }

        Divider()

        Button {
            NotificationCenter.default.post(name: .showSettings, object: nil)
        } label: {
            Label("设置", systemImage: "gear")
        }
    }

    // MARK: - 交互处理

    private func handleBodyPartTap(_ part: SpriteBodyPart) {
        spriteViewModel.react(to: part)
        if part == .phone {
            presentQuickChat()
        }
    }

    private func handleTap() {
        if spriteViewModel.animationState == .walking || spriteViewModel.animationState == .running {
            spriteViewModel.stopCurrentAction()
            return
        }

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
                // 取词失败时提供「截图翻译」直达入口，避免走进死胡同
                let screenshotAction = BubbleAction(
                    title: "截图翻译",
                    icon: "text.viewfinder"
                ) { [weak spriteViewModel] in
                    spriteViewModel?.translateScreenshot()
                }

                if !hasPermission {
                    // 权限未授予，提示用户授权
                    spriteViewModel?.showBubble(
                        message: "需要「辅助功能」权限才能自动获取选中文字~\n\n请在系统设置中授权，或复制文字(Cmd+C)再双击我，也可以点下面的「截图翻译」。",
                        type: .greeting,
                        duration: 8,
                        actions: [screenshotAction]
                    )
                    // 打开设置
                    SelectionService.shared.openAccessibilitySettings()
                } else {
                    // 权限已授予但没有选中文字
                    spriteViewModel?.showBubble(
                        message: "没有检测到选中的文字~\n\n可以先选中或复制(Cmd+C)文字再双击我；复制不了的内容（图片、视频字幕等），点下面的「截图翻译」框选就行。",
                        type: .greeting,
                        duration: 8,
                        actions: [screenshotAction]
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
        case .memo:
            onShowPanel?(.memo)
        case .guidance:
            // 截图指导是独立窗口，已由 executeAction 发通知打开，此处无需切面板
            break
        }
    }
}

// MARK: - 角色旁紧凑聊天输入

private struct SpriteQuickChatComposer: View {
    @Binding var draft: String
    @ObservedObject var chatViewModel: ChatViewModel

    let onSent: () -> Void
    let onClose: () -> Void
    let onOpenFullChat: () -> Void

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("和布布说话")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(BuBuColors.chocolateBrown)
                    Text(chatViewModel.isStreaming ? chatViewModel.expression.title : "我在听呀")
                        .font(BuBuFonts.tiny)
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.52))
                }

                Spacer()

                Button(action: onOpenFullChat) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .help("打开完整聊天")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .help("收起")
            }
            .buttonStyle(.plain)
            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.55))

            if chatViewModel.isStreaming {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("布布正在回复…")
                        .font(BuBuFonts.caption)
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.65))
                    Spacer()
                    Button {
                        chatViewModel.stopGenerating()
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                            .font(BuBuFonts.tiny)
                            .foregroundColor(BuBuColors.coralPink)
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 36)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("和布布说点什么…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(BuBuFonts.caption)
                        .lineLimit(1...3)
                        .focused($inputFocused)
                        .onSubmit(sendDraft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11)
                                        .stroke(BuBuColors.skyBlue.opacity(0.24), lineWidth: 1)
                                )
                        )

                    Button(action: sendDraft) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(BuBuColors.skyBlue))
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("发送")
                }
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(BuBuColors.creamWhite.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                )
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.20), radius: 14, x: 0, y: 7)
        )
        .overlay(alignment: .bottom) {
            Triangle()
                .fill(BuBuColors.creamWhite)
                .frame(width: 16, height: 10)
                .rotationEffect(.degrees(180))
                .offset(y: 9)
        }
        .onAppear(perform: focusInput)
        .onChange(of: chatViewModel.isStreaming) { _, isStreaming in
            if !isStreaming {
                focusInput()
            }
        }
    }

    private func sendDraft() {
        let text = draft
        if chatViewModel.send(text) {
            draft = ""
            onSent()
        } else {
            focusInput()
        }
    }

    private func focusInput() {
        guard !chatViewModel.isStreaming else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            inputFocused = true
        }
    }
}

// MARK: - 动作选择菜单

struct ActionMenuView: View {
    let droppedText: String
    let onAction: (DragAction) -> Void
    let onCancel: () -> Void

    /// 预览文本：折叠连续空白与换行为单个空格，截断到 50 字，避免多空白显得像空框
    private var previewText: String {
        let collapsed = droppedText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.count > 50 ? String(collapsed.prefix(50)) + "…" : collapsed
    }

    var body: some View {
        VStack(spacing: 12) {
            // 预览文本（内容为空白时不显示，避免出现空框）
            if !previewText.isEmpty {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 11))
                        .foregroundColor(BuBuColors.skyBlue)

                    Text(previewText)
                        .font(BuBuFonts.tiny)
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.65))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: BuBuShapes.smallRadius)
                        .fill(Color.white)
                )
            }

            // 动作按钮（5 项需在 280pt 窗口内排开，间距收紧）
            HStack(spacing: 2) {
                ForEach(DragAction.allCases, id: \.self) { action in
                    ActionButton(action: action) {
                        onAction(action)
                    }
                }
            }

            // 取消按钮
            Button {
                onCancel()
            } label: {
                Text("取消")
                    .font(BuBuFonts.caption)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(BuBuColors.chocolateBrown.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.cardRadius)
                .fill(BuBuColors.creamWhite)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.18), radius: 14, x: 0, y: 7)
        )
        .padding(.horizontal, 4)
    }
}

// MARK: - 动作按钮

struct ActionButton: View {
    let action: DragAction
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(isHovered ? action.themeColor : action.themeColor.opacity(0.14))
                        .frame(width: 34, height: 34)

                    Image(systemName: action.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isHovered ? .white : action.themeColor)
                }

                Text(action.title)
                    .font(BuBuFonts.tiny)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(isHovered ? 0.9 : 0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 48, height: 58)
            .contentShape(Rectangle())
            .scaleEffect(isHovered ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

// 动作按钮的主题色映射（表现层职责，不进模型）
private extension DragAction {
    var themeColor: Color {
        switch self {
        case .search: return BuBuColors.skyBlue
        case .translate: return BuBuColors.mintGreen
        case .addNote: return BuBuColors.peachBlush
        case .memo: return BuBuColors.lavender
        case .guidance: return BuBuColors.coralPink
        }
    }
}
