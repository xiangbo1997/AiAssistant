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

    // MARK: - 外观设置

    @Published var scale: CGFloat = 1.0
    @Published var opacity: Double = 1.0

    // MARK: - 气泡消息

    @Published var currentBubble: SpriteBubble?
    @Published var showBubble: Bool = false

    // MARK: - 拖拽状态

    @Published var isDragOver: Bool = false
    @Published var showActionMenu: Bool = false
    @Published var droppedText: String = ""

    // MARK: - 睡眠计时

    private var sleepTimer: Timer?
    private var sleepDelay: TimeInterval = 300 // 5分钟无操作进入睡眠

    // MARK: - 订阅

    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    init() {
        loadCustomCharacters()
        startIdleAnimation()
        setupSleepTimer()
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

    /// 删除自定义角色
    func removeCustomCharacter(_ character: SpriteCharacter) {
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
        guard isAnimating else { return }
        animationState = .idle
    }

    /// 切换到思考状态
    func startThinking() {
        resetSleepTimer()
        animationState = .thinking
        showBubble(message: "思考中...", type: .thinking, duration: 0)
    }

    /// 切换到说话状态
    func startTalking() {
        resetSleepTimer()
        animationState = .talking
    }

    /// 显示开心动画
    func showHappy() {
        resetSleepTimer()
        animationState = .happy

        // 2秒后恢复待机
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startIdleAnimation()
        }
    }

    /// 进入睡眠状态
    func enterSleep() {
        animationState = .sleeping
        showBubble(message: "Zzz...", type: .greeting, duration: 0)
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

    func resetSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: sleepDelay, repeats: false) { [weak self] _ in
            self?.enterSleep()
        }
    }

    func setSleepDelay(_ delay: TimeInterval) {
        sleepDelay = delay
        resetSleepTimer()
    }

    // MARK: - 气泡消息

    /// 气泡自动隐藏的工作项（用于取消）
    private var bubbleHideWorkItem: DispatchWorkItem?

    /// 显示气泡消息
    func showBubble(message: String, type: SpriteBubble.BubbleType, duration: TimeInterval = 3) {
        // 取消之前的自动隐藏定时器
        bubbleHideWorkItem?.cancel()
        bubbleHideWorkItem = nil

        currentBubble = SpriteBubble(message: message, type: type, duration: duration)
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

    /// 隐藏气泡
    func hideBubble() {
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
        showActionMenu = true
        animationState = .happy

        // 显示提示气泡
        showBubble(message: "收到啦！要做什么呢？", type: .greeting, duration: 0)
    }

    /// 快速翻译模式 - 拖拽后直接翻译
    func handleDropForTranslation(text: String) {
        isDragOver = false
        droppedText = text
        animationState = .thinking

        // 显示原文气泡
        let previewText = text.count > 30 ? String(text.prefix(30)) + "..." : text
        showBubble(message: "翻译中: \(previewText)", type: .thinking, duration: 0)

        // 执行翻译
        performQuickTranslation(text: text)
    }

    /// 执行快速翻译
    private func performQuickTranslation(text: String) {
        Task {
            do {
                let config = SettingsViewModel.shared.currentLLMConfig

                // 检查 API Key
                guard !config.apiKey.isEmpty else {
                    await MainActor.run {
                        showBubble(message: "请先配置 API Key", type: .error, duration: 3)
                        startIdleAnimation()
                    }
                    return
                }

                let service = LLMServiceFactory.create(for: config)

                // 检测语言并翻译
                let targetLang = detectTargetLanguage(text)
                let result = try await service.translate(text: text, from: "自动检测", to: targetLang)

                await MainActor.run {
                    // 显示翻译结果（持久显示，duration: 0 表示不自动消失）
                    animationState = .happy
                    showBubble(message: result, type: .response, duration: 0)

                    // 保存到翻译历史
                    TranslationHistoryService.shared.addRecord(
                        sourceText: text,
                        targetText: result,
                        sourceLanguage: "自动检测",
                        targetLanguage: targetLang
                    )

                    // 恢复待机动画（但保持气泡显示）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.startIdleAnimation()
                    }
                }
            } catch {
                await MainActor.run {
                    showBubble(message: "翻译失败: \(error.localizedDescription)", type: .error, duration: 3)
                    startIdleAnimation()
                }
            }
        }
    }

    /// 检测目标语言（中文翻译成英文，其他翻译成中文）
    private func detectTargetLanguage(_ text: String) -> String {
        // 简单检测：如果包含中文字符，翻译成英文；否则翻译成中文
        let chineseRange = text.range(of: "\\p{Han}", options: .regularExpression)
        return chineseRange != nil ? "英语" : "中文"
    }

    /// 执行拖拽动作
    func executeAction(_ action: DragAction) {
        showActionMenu = false
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
        }

        droppedText = ""
        startIdleAnimation()
    }

    /// 取消动作
    func cancelAction() {
        showActionMenu = false
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
}
