//
//  SpriteViewModel.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  精灵视图模型 - 管理精灵状态、动画和交互
//

import SwiftUI
import Combine

class SpriteViewModel: ObservableObject {
    // MARK: - 角色属性

    @Published var currentCharacter: SpriteCharacter = .bubu
    @Published var customCharacters: [SpriteCharacter] = []

    // MARK: - 动画状态

    @Published var animationState: SpriteAnimationState = .idle
    @Published var isAnimating: Bool = true
    @Published var chatExpression: ChatExpression = .idle
    @Published private(set) var latestInteraction: SpriteInteraction?
    /// 桌面移动方向：1 向右，-1 向左；2D/3D 渲染据此同步镜像。
    @Published var facingDirection: CGFloat = 1

    // MARK: - 外观设置

    @Published var scale: CGFloat = 1.0
    @Published var opacity: Double = 1.0

    // MARK: - 气泡消息

    @Published var currentBubble: SpriteBubble?
    @Published var showBubble: Bool = false

    // MARK: - 拖拽状态

    @Published var isDragOver: Bool = false
    @Published var showActionMenu: Bool = false
    var droppedText: String = ""  // 不需要 @Published，不触发视图更新

    // MARK: - 睡眠计时

    private var sleepTimer: Timer?
    private var sleepDelay: TimeInterval = 300 // 5分钟无操作进入睡眠
    private var animationTestSleepDelay: TimeInterval?
    private var boredomTimer: Timer?
    private var boredomActionWorkItem: DispatchWorkItem?
    private var boredomDelayRange: ClosedRange<TimeInterval> = 18...40
    private var isPerformingBoredomAction = false
    private var isQuickChatPresented = false
    private var animationResetWorkItem: DispatchWorkItem?
    private var chatReactionResetWorkItem: DispatchWorkItem?

    // MARK: - 订阅

    private var cancellables = Set<AnyCancellable>()

    // MARK: - 快速翻译状态（流式 + 打字机）

    /// 快速翻译的输入源：选中文字、词典查词或截图（截图存压缩后的 JPEG，供视觉模型重译）
    private enum QuickTranslationInput {
        case text(String)
        case dictionaryWord(String)
        case image(Data)
    }

    /// 单次翻译的会话状态。缓冲按代独立持有：协作式取消不会丢弃在途的流元素，
    /// 被顶替的旧任务恢复后写的是自己的会话对象，不会污染新任务的气泡与历史
    private final class QuickTranslationSession {
        let input: QuickTranslationInput
        let target: Language
        var buffer = ""
        var finished = false

        init(input: QuickTranslationInput, target: Language) {
            self.input = input
            self.target = target
        }
    }

    /// 流式翻译任务
    private var translationTask: Task<Void, Never>?
    /// 打字机任务：按固定节奏把会话缓冲吐进气泡
    private var typewriterTask: Task<Void, Never>?
    /// 截图翻译任务（覆盖框选与 OCR 阶段，睡眠/新翻译可随时中止）
    private var screenshotTask: Task<Void, Never>?
    /// 当前活跃的翻译会话（代际守卫：过期任务据此自行退出）
    private var currentSession: QuickTranslationSession?
    /// 最近一次翻译的输入与目标语言（供「切换目标语言重译」）
    private var lastInput: QuickTranslationInput?
    private var lastTranslationTarget: Language = .chinese

    // MARK: - 初始化

    init() {
        applyAnimationTestOverrides()
        loadCustomCharacters()
        startIdleAnimation()
        setupSleepTimer()
    }

    deinit {
        sleepTimer?.invalidate()
        boredomTimer?.invalidate()
        animationResetWorkItem?.cancel()
        boredomActionWorkItem?.cancel()
        chatReactionResetWorkItem?.cancel()
    }

    // MARK: - 角色管理

    /// 加载自定义角色
    func loadCustomCharacters() {
        if let data = UserDefaults.standard.data(forKey: "customCharacters"),
           let characters = try? JSONDecoder().decode([SpriteCharacter].self, from: data) {
            customCharacters = characters
        }
    }

    /// 保存自定义角色
    func saveCustomCharacters() {
        if let data = try? JSONEncoder().encode(customCharacters) {
            UserDefaults.standard.set(data, forKey: "customCharacters")
        }
    }

    /// 添加自定义角色
    func addCustomCharacter(name: String, imagePath: String) {
        let character = SpriteCharacter(
            id: UUID(),
            name: name,
            imageName: "custom_\(UUID().uuidString)",
            isCustom: true,
            customImagePath: imagePath
        )
        customCharacters.append(character)
        saveCustomCharacters()
    }

    /// 修改自定义角色名称，并同步当前正在使用的角色。
    func renameCustomCharacter(_ character: SpriteCharacter, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard character.isCustom, !trimmedName.isEmpty,
              let index = customCharacters.firstIndex(where: { $0.id == character.id }) else { return }

        customCharacters[index].name = trimmedName
        if currentCharacter.id == character.id {
            currentCharacter = customCharacters[index]
        }
        saveCustomCharacters()
    }

    /// 删除自定义角色
    func removeCustomCharacter(_ character: SpriteCharacter) {
        if character.isCustom, let path = character.customImagePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        customCharacters.removeAll { $0.id == character.id }
        saveCustomCharacters()

        // 如果删除的是当前角色，切换到默认角色
        if currentCharacter.id == character.id {
            currentCharacter = .bubu
        }
    }

    /// 所有可用角色
    var allCharacters: [SpriteCharacter] {
        SpriteCharacter.presets + customCharacters
    }

    // MARK: - 动画控制

    /// 开始待机动画
    func startIdleAnimation() {
        animationResetWorkItem?.cancel()
        guard isAnimating else { return }
        animationState = .idle
    }

    /// 切换到思考状态
    func startThinking() {
        animationResetWorkItem?.cancel()
        resetSleepTimer()
        animationState = .thinking
        showBubble(message: "思考中...", type: .thinking, duration: 0)
    }

    /// 切换到说话状态
    func startTalking() {
        animationResetWorkItem?.cancel()
        resetSleepTimer()
        animationState = .talking
    }

    /// 显示开心动画
    func showHappy() {
        playTemporaryAnimation(.happy, duration: 2.0)
    }

    func playWalking() {
        playContinuousAnimation(.walking)
    }

    func playRunning() {
        playContinuousAnimation(.running)
    }

    func playWaving() {
        playTemporaryAnimation(.waving, duration: 2.8)
    }

    func stopCurrentAction() {
        resetSleepTimer()
        startIdleAnimation()
    }

    // MARK: - 模型部位互动

    /// 统一处理 2D/3D 部位反馈；视图只负责命中和表现局部形变。
    func react(to part: SpriteBodyPart) {
        if animationState == .sleeping {
            wakeUp()
        } else {
            resetSleepTimer()
        }

        if animationState == .walking || animationState == .running {
            startIdleAnimation()
        }

        latestInteraction = SpriteInteraction(part: part)
        chatReactionResetWorkItem?.cancel()

        let reaction: (expression: ChatExpression, line: String?, state: SpriteAnimationState?, duration: TimeInterval)
        switch part {
        case .head:
            reaction = (.caring, ["嘿嘿，摸摸头~", "再摸一下也可以呀"].randomElement(), .happy, 1.35)
        case .ear:
            reaction = (.curious, ["耳朵听到你啦~", "呀，耳朵痒痒的"].randomElement(), .thinking, 1.25)
        case .eyes:
            reaction = (.surprised, ["眨眨眼，看见你啦", "别戳眼睛嘛~"].randomElement(), nil, 0.75)
        case .cheek:
            reaction = (.happy, ["脸都被你戳红啦", "软乎乎的吧~"].randomElement(), .happy, 1.25)
        case .belly:
            reaction = (.surprised, ["咕噜咕噜~", "肚肚不许一直戳！"].randomElement(), .happy, 1.15)
        case .arm:
            reaction = (.greeting, ["嗨呀~", "挥挥手，看到你啦"].randomElement(), .waving, 2.8)
        case .foot:
            reaction = (.curious, ["脚脚要出发啦", "陪我走两步吧~"].randomElement(), .walking, 1.15)
        case .phone:
            reaction = (.listening, nil, nil, 1.2)
        }

        chatExpression = reaction.expression
        if let line = reaction.line, !showBubble {
            showBubble(message: line, type: .greeting, duration: 2.2)
        }
        if let state = reaction.state {
            playTemporaryAnimation(state, duration: reaction.duration)
        }
        scheduleChatExpressionReset(after: max(reaction.duration + 0.35, 1.5))
    }

    /// 聊天输入展开期间暂停自主行为和睡眠；收起后从这次真实互动重新计时。
    func setQuickChatPresented(_ presented: Bool) {
        isQuickChatPresented = presented
        if presented {
            sleepTimer?.invalidate()
            boredomTimer?.invalidate()
            stopBoredomActionIfNeeded()
        } else {
            resetSleepTimer()
        }
    }

    // MARK: - 聊天表情联动

    func beginChatThinking(userText: String) {
        cancelQuickTranslation()
        chatReactionResetWorkItem?.cancel()
        resetSleepTimer()
        chatExpression = .thinking
        animationState = .thinking
        let preview = userText.count > 28 ? String(userText.prefix(28)) + "…" : userText
        showBubble(message: "收到啦，让我想想：\(preview)", type: .thinking, duration: 0)
    }

    func beginChatSpeaking() {
        chatReactionResetWorkItem?.cancel()
        chatExpression = .talking
        animationState = .talking
        showBubble(message: "", type: .response, duration: 0, isStreaming: true)
    }

    func updateChatReplyPreview(_ reply: String) {
        guard animationState == .talking else { return }
        let compact = reply.replacingOccurrences(of: "\n", with: " ")
        currentBubble?.message = compact.count > 120 ? String(compact.prefix(120)) + "…" : compact
        currentBubble?.isStreaming = true
    }

    func finishChatReply(_ reply: String, expression: ChatExpression) {
        chatReactionResetWorkItem?.cancel()
        chatExpression = expression

        let compact = reply.replacingOccurrences(of: "\n", with: " ")
        let preview = compact.count > 150 ? String(compact.prefix(150)) + "…" : compact
        showBubble(message: preview, type: .response, duration: 8, isStreaming: false)

        switch expression {
        case .greeting:
            playWaving()
        case .happy, .caring, .surprised:
            showHappy()
        case .curious:
            animationState = .thinking
        default:
            startIdleAnimation()
        }

        scheduleChatExpressionReset(after: 3.2)
    }

    func failChatReaction(_ message: String) {
        chatReactionResetWorkItem?.cancel()
        chatExpression = .error
        startIdleAnimation()
        showBubble(message: "聊天失败：\(message)", type: .error, duration: 4)
        scheduleChatExpressionReset(after: 2.6)
    }

    func stopChatReaction() {
        chatReactionResetWorkItem?.cancel()
        chatExpression = .idle
        currentBubble?.isStreaming = false
        startIdleAnimation()
    }

    private func scheduleChatExpressionReset(after delay: TimeInterval) {
        let expression = chatExpression
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.chatExpression == expression else { return }
            self.chatExpression = .idle
            if self.animationState != .sleeping {
                self.startIdleAnimation()
            }
        }
        chatReactionResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func playContinuousAnimation(_ state: SpriteAnimationState) {
        guard isAnimating else { return }
        animationResetWorkItem?.cancel()
        resetSleepTimer()
        animationState = state
    }

    private func playTemporaryAnimation(_ state: SpriteAnimationState, duration: TimeInterval) {
        guard isAnimating else { return }
        animationResetWorkItem?.cancel()
        resetSleepTimer()
        animationState = state

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.animationState == state else { return }
            self?.startIdleAnimation()
        }
        animationResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    /// 进入睡眠状态
    func enterSleep() {
        guard !isQuickChatPresented else { return }
        animationResetWorkItem?.cancel()
        boredomTimer?.invalidate()
        boredomActionWorkItem?.cancel()
        isPerformingBoredomAction = false
        animationState = .sleeping
        hideBubble()  // 睡眠时隐藏气泡，用 Zzz 动画代替
    }

    /// 唤醒
    func wakeUp() {
        resetSleepTimer()
        hideBubble()
        startIdleAnimation()
    }

    // MARK: - 睡眠计时器

    private func setupSleepTimer() {
        resetSleepTimer()
    }

    /// 只有真实用户活动会走这里；自主动作必须绕开，保证 5 分钟后仍会睡着。
    func resetSleepTimer() {
        stopBoredomActionIfNeeded()
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: sleepDelay, repeats: false) { [weak self] _ in
            self?.enterSleep()
        }
        scheduleBoredomBehavior()
    }

    func setSleepDelay(_ delay: TimeInterval) {
        // 加速验收值只在显式传入环境变量时生效，避免设置订阅启动后又覆盖回 5 分钟。
        sleepDelay = animationTestSleepDelay ?? delay
        resetSleepTimer()
    }

    // MARK: - 无聊时的自主行为

    private func scheduleBoredomBehavior(after explicitDelay: TimeInterval? = nil) {
        boredomTimer?.invalidate()
        guard isAnimating, !isQuickChatPresented, animationState != .sleeping else { return }

        let delay = explicitDelay ?? TimeInterval.random(in: boredomDelayRange)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.performBoredomBehavior()
        }
        boredomTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func performBoredomBehavior() {
        guard isAnimating, !isQuickChatPresented, animationState == .idle,
              !showBubble, !showActionMenu, !isDragOver else {
            scheduleBoredomBehavior(after: TimeInterval.random(in: 8...14))
            return
        }

        animationResetWorkItem?.cancel()
        boredomActionWorkItem?.cancel()
        isPerformingBoredomAction = true

        let roll = Int.random(in: 0..<100)
        let state: SpriteAnimationState
        let duration: TimeInterval
        switch roll {
        case 0..<44:
            state = .walking
            duration = TimeInterval.random(in: 1.5...2.4)
        case 44..<68:
            state = .running
            duration = TimeInterval.random(in: 0.75...1.25)
        case 68..<84:
            state = .waving
            duration = 2.8
        default:
            state = .happy
            duration = 1.35
        }
        animationState = state

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isPerformingBoredomAction, self.animationState == state else { return }
            self.isPerformingBoredomAction = false
            self.startIdleAnimation()
            self.scheduleBoredomBehavior()
        }
        boredomActionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func stopBoredomActionIfNeeded() {
        boredomTimer?.invalidate()
        boredomActionWorkItem?.cancel()
        guard isPerformingBoredomAction else { return }
        isPerformingBoredomAction = false
        startIdleAnimation()
    }

    /// Debug 验收可通过环境变量加速，正式启动未设置时保持产品时长。
    private func applyAnimationTestOverrides() {
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["BUBU_SLEEP_DELAY"], let delay = TimeInterval(raw), delay > 0 {
            animationTestSleepDelay = delay
            sleepDelay = delay
        }
        if let raw = environment["BUBU_BOREDOM_DELAY"], let delay = TimeInterval(raw), delay > 0 {
            boredomDelayRange = delay...delay
        }
    }

    // MARK: - 气泡消息

    /// 气泡自动隐藏的工作项（用于取消）
    private var bubbleHideWorkItem: DispatchWorkItem?

    /// 显示气泡消息
    func showBubble(
        message: String,
        type: SpriteBubble.BubbleType,
        duration: TimeInterval = 3,
        isStreaming: Bool = false,
        actions: [BubbleAction] = []
    ) {
        // 取消之前的自动隐藏定时器
        bubbleHideWorkItem?.cancel()
        bubbleHideWorkItem = nil

        currentBubble = SpriteBubble(
            message: message,
            type: type,
            duration: duration,
            isStreaming: isStreaming,
            actions: actions
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showBubble = true
        }

        // 自动隐藏（仅当 duration > 0 时）
        if duration > 0 {
            let workItem = DispatchWorkItem { [weak self] in
                self?.hideBubble()
            }
            bubbleHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        }
    }

    /// 隐藏气泡（若翻译流仍在进行，一并中止）
    func hideBubble() {
        cancelQuickTranslation()
        withAnimation(.easeOut(duration: 0.2)) {
            showBubble = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.currentBubble = nil
        }
    }

    // MARK: - 拖拽处理

    /// 处理拖拽进入
    func handleDragEnter() {
        resetSleepTimer()
        isDragOver = true
        animationState = .happy
    }

    /// 处理拖拽离开
    func handleDragExit() {
        isDragOver = false
        startIdleAnimation()
    }

    /// 处理拖拽放下
    func handleDrop(text: String) {
        isDragOver = false
        droppedText = text
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showActionMenu = true
        }
        animationState = .happy

        // 显示提示气泡
        showBubble(message: "收到啦！要做什么呢？", type: .greeting, duration: 0)
    }

    /// 快速翻译模式 - 拖拽后直接翻译
    func handleDropForTranslation(text: String) {
        isDragOver = false
        droppedText = text
        performQuickTranslation(text: text)
    }

    /// 切换目标语言后重译最近一次的输入（文字、单词或截图）
    func retranslate(to target: Language) {
        switch lastInput {
        case .text(let text):
            performQuickTranslation(text: text, target: target)
        case .dictionaryWord(let word):
            runDictionaryLookup(word: word, target: target)
        case .image(let jpegData):
            runVisionTranslation(jpegData: jpegData, target: target)
        case nil:
            break
        }
    }

    /// 中止进行中的快速翻译（流式请求、打字机与截图流程一并取消）
    func cancelQuickTranslation() {
        translationTask?.cancel()
        translationTask = nil
        typewriterTask?.cancel()
        typewriterTask = nil
        screenshotTask?.cancel()
        screenshotTask = nil
        currentSession = nil
    }

    /// 执行快速翻译：流式接收 + 打字机吐字 + 说话动画
    private func performQuickTranslation(text: String, target: Language? = nil) {
        // 单词/短语走词典模式：给音标、词性、释义、例句
        if LanguageDetector.isDictionaryQuery(text) {
            runDictionaryLookup(word: text.trimmingCharacters(in: .whitespacesAndNewlines), target: target)
            return
        }

        cancelQuickTranslation()
        resetSleepTimer()

        let targetLang = target ?? LanguageDetector.quickTargetLanguage(for: text)
        lastInput = .text(text)
        lastTranslationTarget = targetLang

        // 历史缓存命中：直接完整显示，零 API 调用
        if let cached = TranslationEngine.shared.cachedTranslation(text: text, target: targetLang) {
            animationState = .happy
            showBubble(message: cached, type: .response, duration: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.startIdleAnimation()
            }
            return
        }

        animationState = .thinking
        let previewText = text.count > 30 ? String(text.prefix(30)) + "..." : text
        showBubble(message: "翻译中: \(previewText)", type: .thinking, duration: 0)

        let session = QuickTranslationSession(input: .text(text), target: targetLang)
        startStreamingTranslation(session: session) {
            try TranslationEngine.shared.stream(text: text, target: targetLang)
        }
    }

    /// 词典查词：单词/短语返回音标、词性、释义与例句
    private func runDictionaryLookup(word: String, target: Language? = nil) {
        cancelQuickTranslation()
        resetSleepTimer()

        let targetLang = target ?? LanguageDetector.quickTargetLanguage(for: word)
        lastInput = .dictionaryWord(word)
        lastTranslationTarget = targetLang

        animationState = .thinking
        showBubble(message: "查词中: \(word)", type: .thinking, duration: 0)

        let session = QuickTranslationSession(input: .dictionaryWord(word), target: targetLang)
        startStreamingTranslation(session: session) {
            try TranslationEngine.shared.dictionaryStream(word: word, target: targetLang)
        }
    }

    // MARK: - 截图翻译

    /// 截图翻译：框选截图 → 本地 OCR → 翻译；识别不到文字时用视觉模型直翻兜底
    func translateScreenshot() {
        cancelQuickTranslation()
        resetSleepTimer()
        hideBubble()

        screenshotTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // 用户按 Esc 取消截图时直接返回
            guard let rawData = await ScreenshotService.shared.captureInteractiveRaw() else {
                return
            }
            // 框选期间被睡眠或新翻译中止：不再恢复气泡
            guard !Task.isCancelled else { return }

            self.animationState = .thinking
            self.showBubble(message: "正在识别文字...", type: .thinking, duration: 0)

            do {
                let text = try await OCRService.shared.recognizeText(in: rawData)
                guard !Task.isCancelled else { return }
                self.performQuickTranslation(text: text)
            } catch {
                guard !Task.isCancelled else { return }
                // OCR 无结果：能走视觉模型就直翻，否则提示失败
                self.performVisionTranslation(rawData: rawData)
            }
        }
    }

    /// 视觉模型直翻兜底：压缩截图后交给视觉模型识别并翻译
    private func performVisionTranslation(rawData: Data) {
        let config = SettingsViewModel.shared.currentLLMConfig
        guard config.provider.supportsVision,
              let image = NSImage(data: rawData),
              let jpegData = image.compressedForLLM() else {
            showBubble(
                message: "没有识别到文字~ 当前 AI 服务不支持图片理解，换一张文字更清晰的截图试试吧。",
                type: .error,
                duration: 5
            )
            startIdleAnimation()
            return
        }

        runVisionTranslation(jpegData: jpegData, target: .chinese)
    }

    /// 执行视觉直翻（jpegData 为压缩后的图片，可直接用于重译）
    private func runVisionTranslation(jpegData: Data, target: Language) {
        cancelQuickTranslation()
        resetSleepTimer()

        lastInput = .image(jpegData)
        lastTranslationTarget = target

        animationState = .thinking
        showBubble(message: "布布正在看图翻译...", type: .thinking, duration: 0)

        let session = QuickTranslationSession(input: .image(jpegData), target: target)
        startStreamingTranslation(session: session) {
            try TranslationEngine.shared.visionStream(imageData: jpegData, target: target)
        }
    }

    /// 消费翻译流：首个 chunk 到达后切换为打字机说话气泡。
    /// 所有写入都落在本代 session 上，并以 currentSession 恒等作代际守卫
    private func startStreamingTranslation(
        session: QuickTranslationSession,
        makeStream: @escaping () throws -> AsyncThrowingStream<String, Error>
    ) {
        currentSession = session

        translationTask = Task { @MainActor [weak self] in
            do {
                let stream = try makeStream()

                var bubbleStarted = false
                for try await chunk in stream {
                    // 代际守卫：已被新任务顶替时直接退出（取消只是标志位，
                    // 已在途的 chunk 仍会送达一次）
                    guard let self, self.currentSession === session else { return }
                    try Task.checkCancellation()

                    if !bubbleStarted {
                        bubbleStarted = true
                        self.beginSpeakingBubble(session: session)
                    }
                    session.buffer += chunk
                }

                guard let self, self.currentSession === session else { return }
                try Task.checkCancellation()

                guard bubbleStarted else {
                    self.showBubble(message: "翻译失败: 服务返回了空结果", type: .error, duration: 4)
                    self.startIdleAnimation()
                    return
                }
                // 流式接收完毕，打字机吐完剩余文字后收尾（见 finishSpeakingBubble）
                session.finished = true
            } catch is CancellationError {
                // 被新任务顶替或气泡被关闭，静默结束
            } catch {
                guard let self, self.currentSession === session else { return }
                self.typewriterTask?.cancel()
                self.showBubble(message: "翻译失败: \(error.localizedDescription)", type: .error, duration: 4)
                self.startIdleAnimation()
            }
        }
    }

    /// 首个译文 chunk 到达：切换为说话状态，启动打字机气泡
    private func beginSpeakingBubble(session: QuickTranslationSession) {
        animationState = .talking
        showBubble(message: "", type: .response, duration: 0, isStreaming: true)

        let bubbleID = currentBubble?.id
        typewriterTask = Task { @MainActor [weak self] in
            var displayed = 0
            while !Task.isCancelled {
                guard let self else { return }

                // 被新翻译顶替：UI 状态归新任务管，静默退出
                guard self.currentSession === session else { return }

                // 气泡被其他消息顶替：终止打字机，复位遗留的说话动画
                guard self.currentBubble?.id == bubbleID else {
                    if self.animationState == .talking {
                        self.startIdleAnimation()
                    }
                    return
                }

                if displayed < session.buffer.count {
                    // 匀速吐字（约 30 字/秒）；缓冲积压过多时加速追赶，控制展示延迟
                    let buffer = session.buffer
                    let backlog = buffer.count - displayed
                    let advance = min(max(2, backlog / 20), backlog)
                    let start = buffer.index(buffer.startIndex, offsetBy: displayed)
                    let end = buffer.index(start, offsetBy: advance)
                    self.currentBubble?.message += String(buffer[start..<end])
                    displayed += advance
                } else if session.finished {
                    self.finishSpeakingBubble(session: session)
                    return
                }
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
    }

    /// 打字机吐完全部文字：收尾并写入翻译历史。
    /// 历史内容取自本代 session 快照，不受后续任务改写实例状态影响
    private func finishSpeakingBubble(session: QuickTranslationSession) {
        currentBubble?.message = session.buffer
        currentBubble?.isStreaming = false
        animationState = .happy
        currentSession = nil

        // 截图直翻拿不到原文、词典卡片非纯译文，只有文字输入才写历史
        if case .text(let sourceText) = session.input {
            TranslationEngine.shared.saveRecord(
                sourceText: sourceText,
                targetText: session.buffer,
                source: .auto,
                target: session.target
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startIdleAnimation()
        }
    }

    /// 执行拖拽动作
    func executeAction(_ action: DragAction) {
        withAnimation(.easeOut(duration: 0.15)) {
            showActionMenu = false
        }
        hideBubble()

        switch action {
        case .search:
            NotificationCenter.default.post(
                name: .performSearch,
                object: droppedText
            )
        case .translate:
            NotificationCenter.default.post(
                name: .performTranslation,
                object: droppedText
            )
        case .addNote:
            NotificationCenter.default.post(
                name: .addNote,
                object: droppedText
            )
        case .memo:
            NotificationCenter.default.post(
                name: .showMemo,
                object: droppedText
            )
        case .guidance:
            NotificationCenter.default.post(
                name: .showGuidance,
                object: nil
            )
        }

        droppedText = ""
        startIdleAnimation()
    }

    /// 取消动作
    func cancelAction() {
        withAnimation(.easeOut(duration: 0.15)) {
            showActionMenu = false
        }
        droppedText = ""
        hideBubble()
        startIdleAnimation()
    }

    // MARK: - 问候语

    /// 获取随机问候语
    func getGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greetings: [String]

        switch hour {
        case 5..<12:
            greetings = ["早上好呀~", "新的一天开始啦！", "早安，今天也要加油哦~"]
        case 12..<14:
            greetings = ["中午好~", "该吃午饭啦！", "休息一下吧~"]
        case 14..<18:
            greetings = ["下午好~", "下午茶时间~", "继续加油！"]
        case 18..<22:
            greetings = ["晚上好~", "辛苦啦~", "今天过得怎么样？"]
        default:
            greetings = ["夜深了~", "注意休息哦~", "早点睡觉吧~"]
        }

        return greetings.randomElement() ?? "你好呀~"
    }

    /// 显示问候
    func showGreeting() {
        let greeting = getGreeting()
        showBubble(message: greeting, type: .greeting, duration: 5)
    }
}

// MARK: - 通知名称扩展

extension Notification.Name {
    static let performSearch = Notification.Name("performSearch")
    static let performTranslation = Notification.Name("performTranslation")
    static let addNote = Notification.Name("addNote")
    static let showMemo = Notification.Name("showMemo")
}
