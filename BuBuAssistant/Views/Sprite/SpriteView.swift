//
//  SpriteView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  精灵视图 - 显示角色图像和动画效果
//

import SwiftUI
import MarkdownUI

struct SpriteView: View {
    @ObservedObject var viewModel: SpriteViewModel
    var onBodyPartTap: ((SpriteBodyPart) -> Void)? = nil
    var onBackgroundTap: (() -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil

    // 动画状态
    @State private var floatOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var scaleEffect: CGFloat = 1.0
    @State private var interactionOffset: CGSize = .zero
    @State private var interactionRotation: Double = 0
    @State private var interactionScaleX: CGFloat = 1
    @State private var interactionScaleY: CGFloat = 1

    // 缓存图片避免重复加载
    @State private var cachedSpriteImage: NSImage?
    @State private var lastCharacterId: UUID?
    @State private var spriteImageAspect: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // 气泡区域 - 紧贴精灵上方，内容自动撑开高度
            if viewModel.showBubble, let bubble = viewModel.currentBubble {
                BubbleView(bubble: bubble, onDismiss: {
                    viewModel.hideBubble()
                }, onRetranslate: { lang in
                    viewModel.retranslate(to: lang)
                })
                // 从尾巴处弹出，像对白框从嘴边冒出来
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.1, anchor: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .padding(.horizontal, 8)
            }

            // 精灵区域（底部固定）
            ZStack {
                spriteLayer
                sleepingLayer
                thinkingLayer
            }
            .frame(height: 150)
        }
        .onAppear {
            reloadSpriteImage()
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: viewModel.currentCharacter.id) { _, _ in
            reloadSpriteImage()
        }
        .onChange(of: viewModel.animationState) { _, newState in
            updateAnimation(for: newState)
        }
        .onChange(of: viewModel.latestInteraction?.id) { _, _ in
            guard let interaction = viewModel.latestInteraction else { return }
            playInteraction(interaction)
        }
        .onChange(of: viewModel.isAnimating) { _, isAnimating in
            if isAnimating {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }

    // MARK: - 视图层

    @ViewBuilder
    private var spriteLayer: some View {
        spriteImageView
            .frame(width: 100 * viewModel.scale, height: 100 * viewModel.scale)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(viewModel.currentCharacter.name)角色")
            .accessibilityHint(
                ["bubu", "yier_phone"].contains(viewModel.currentCharacter.imageName)
                    ? "点击手机和布布聊天；点击其他部位会有不同反应"
                    : "点击角色互动"
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                let hasPhone = ["bubu", "yier_phone"].contains(viewModel.currentCharacter.imageName)
                onBodyPartTap?(hasPhone ? .phone : .head)
            }
            .overlay {
                SpriteClickCaptureView(
                    onSingleClick: handleSpriteClick,
                    onDoubleClick: { onDoubleTap?() }
                )
            }
            .opacity(viewModel.opacity)
            .offset(
                x: interactionOffset.width + sleepOffset.width,
                y: floatOffset + interactionOffset.height + sleepOffset.height
            )
            .rotationEffect(Angle(degrees: rotationAngle + interactionRotation + sleepRotation))
            .scaleEffect(
                x: -scaleEffect * interactionScaleX * sleepScale.width * viewModel.facingDirection,
                y: scaleEffect * interactionScaleY * sleepScale.height,
                anchor: .bottom
            )
            .animation(.easeInOut(duration: 0.28), value: viewModel.facingDirection)
            .animation(.spring(response: 0.62, dampingFraction: 0.78), value: viewModel.animationState == .sleeping)
            .overlay(dragHighlight)
    }

    @ViewBuilder
    private var dragHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(BuBuColors.skyBlue, lineWidth: 3)
            .opacity(viewModel.isDragOver ? 1 : 0)
            .scaleEffect(viewModel.isDragOver ? 1.1 : 1)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isDragOver)
    }

    @ViewBuilder
    private var sleepingLayer: some View {
        if viewModel.animationState == .sleeping {
            ZzzView()
                .offset(x: -38 * viewModel.scale, y: -25 * viewModel.scale)
        }
    }

    @ViewBuilder
    private var thinkingLayer: some View {
        if viewModel.animationState == .thinking {
            ThinkingDotsView()
                .offset(x: 50, y: 0)
        }
    }

    // MARK: - 精灵图像（带缓存）

    @ViewBuilder
    private var spriteImageView: some View {
        if usesDedicatedSleepPose {
            Image("bubu_sleep")
                .resizable()
                .aspectRatio(contentMode: .fit)
        // 自定义角色：使用缓存图片，磁盘加载只在角色切换时发生（见 reloadSpriteImage）
        } else if let nsImage = cachedSpriteImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // 预设角色：直接使用 SwiftUI Image 从 Asset Catalog 加载
            Image(viewModel.currentCharacter.imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    private var usesDedicatedSleepPose: Bool {
        viewModel.animationState == .sleeping && viewModel.currentCharacter.imageName == "bubu"
    }

    private var sleepRotation: Double {
        guard viewModel.animationState == .sleeping else { return 0 }
        return usesDedicatedSleepPose ? 0 : -8
    }

    private var sleepOffset: CGSize {
        guard viewModel.animationState == .sleeping else { return .zero }
        return usesDedicatedSleepPose
            ? CGSize(width: 0, height: 11 * viewModel.scale)
            : CGSize(width: 10 * viewModel.scale, height: 28 * viewModel.scale)
    }

    private var sleepScale: CGSize {
        guard viewModel.animationState == .sleeping else { return CGSize(width: 1, height: 1) }
        return usesDedicatedSleepPose
            ? CGSize(width: 1, height: 1)
            : CGSize(width: 1.12, height: 0.72)
    }

    /// 角色切换时重新加载自定义图片；在 body 里直接 NSImage(contentsOfFile:)
    /// 会导致每次视图刷新都做磁盘 I/O
    private func reloadSpriteImage() {
        guard viewModel.currentCharacter.id != lastCharacterId else { return }
        lastCharacterId = viewModel.currentCharacter.id

        let image: NSImage?
        if viewModel.currentCharacter.isCustom,
           let path = viewModel.currentCharacter.customImagePath {
            image = NSImage(contentsOfFile: path)
            cachedSpriteImage = image
        } else {
            image = NSImage(named: viewModel.currentCharacter.imageName)
            cachedSpriteImage = nil
        }

        if let size = image?.size, size.height > 0 {
            spriteImageAspect = size.width / size.height
        } else {
            spriteImageAspect = 1
        }
    }

    // MARK: - 部位命中与局部反馈

    private func handleSpriteClick(_ point: CGPoint, _ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let activeAspect = usesDedicatedSleepPose ? 512.0 / 416.0 : spriteImageAspect
        let fittedSize: CGSize
        if activeAspect >= size.width / size.height {
            fittedSize = CGSize(width: size.width, height: size.width / max(activeAspect, 0.01))
        } else {
            fittedSize = CGSize(width: size.height * activeAspect, height: size.height)
        }
        let fittedOrigin = CGPoint(
            x: (size.width - fittedSize.width) / 2,
            y: (size.height - fittedSize.height) / 2
        )
        let topLeftPoint = CGPoint(x: point.x, y: size.height - point.y)
        let fittedRect = CGRect(origin: fittedOrigin, size: fittedSize)

        guard fittedRect.contains(topLeftPoint) else {
            onBackgroundTap?()
            return
        }

        let normalized = CGPoint(
            x: (topLeftPoint.x - fittedRect.minX) / fittedRect.width,
            y: (topLeftPoint.y - fittedRect.minY) / fittedRect.height
        )
        if let part = SpriteBodyPart.hitTest(normalized: normalized, character: viewModel.currentCharacter) {
            onBodyPartTap?(part)
        } else {
            onBackgroundTap?()
        }
    }

    private func playInteraction(_ interaction: SpriteInteraction) {
        interactionOffset = .zero
        interactionRotation = 0
        interactionScaleX = 1
        interactionScaleY = 1

        let spring = Animation.spring(response: 0.22, dampingFraction: 0.48)
        withAnimation(spring) {
            switch interaction.part {
            case .head:
                interactionOffset.height = -5
                interactionRotation = -5
            case .ear:
                interactionRotation = 8
            case .eyes:
                interactionScaleY = 0.78
            case .cheek:
                interactionOffset.width = viewModel.facingDirection * 4
                interactionRotation = 4
            case .belly:
                interactionScaleX = 1.08
                interactionScaleY = 0.92
            case .arm:
                interactionRotation = -4
            case .foot:
                interactionOffset.height = -6
            case .phone:
                interactionScaleX = 1.045
                interactionScaleY = 1.045
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard viewModel.latestInteraction?.id == interaction.id else { return }
            if interaction.part == .ear {
                withAnimation(.easeInOut(duration: 0.12)) {
                    interactionRotation = -8
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            guard viewModel.latestInteraction?.id == interaction.id else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                interactionOffset = .zero
                interactionRotation = 0
                interactionScaleX = 1
                interactionScaleY = 1
            }
        }
    }

    @ViewBuilder
    private var defaultSpriteIcon: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [BuBuColors.skyBlue.opacity(0.8), BuBuColors.lavender.opacity(0.6)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 40
                    )
                )

            Image(systemName: "face.smiling.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(20)
                .foregroundColor(.white)
        }
        .bubuFloating()
    }

    // MARK: - 动画控制

    private func startAnimation() {
        guard viewModel.isAnimating else { return }
        updateAnimation(for: viewModel.animationState)
    }

    private func stopAnimation() {
        resetAnimationState()
    }

    private func resetAnimationState() {
        withAnimation(.easeInOut(duration: 0.3)) {
            floatOffset = 0
            rotationAngle = 0
            scaleEffect = 1.0
        }
    }

    private func updateAnimation(for state: SpriteAnimationState) {
        resetAnimationStateImmediately()
        switch state {
        case .idle:
            startIdleAnimation()
        case .thinking:
            startThinkingAnimation()
        case .talking:
            startTalkingAnimation()
        case .happy:
            startHappyAnimation()
        case .walking:
            startWalkingAnimation()
        case .running:
            startRunningAnimation()
        case .waving:
            startWavingAnimation()
        case .sleeping:
            startSleepingAnimation()
        }
    }

    private func resetAnimationStateImmediately() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            floatOffset = 0
            rotationAngle = 0
            scaleEffect = 1
        }
    }

    // MARK: - 各状态动画

    /// 待机动画 - 轻微上下浮动
    private func startIdleAnimation() {
        withAnimation(
            .easeInOut(duration: 2)
            .repeatForever(autoreverses: true)
        ) {
            floatOffset = -8
        }
    }

    /// 思考动画 - 左右摇摆
    private func startThinkingAnimation() {
        withAnimation(
            .easeInOut(duration: 0.5)
            .repeatForever(autoreverses: true)
        ) {
            rotationAngle = 5
        }
    }

    /// 说话动画 - 轻微缩放
    private func startTalkingAnimation() {
        withAnimation(
            .easeInOut(duration: 0.3)
            .repeatForever(autoreverses: true)
        ) {
            scaleEffect = 1.05
        }
    }

    /// 开心动画 - 跳跃
    private func startHappyAnimation() {
        withAnimation(
            .interpolatingSpring(stiffness: 200, damping: 10)
            .repeatCount(3, autoreverses: true)
        ) {
            floatOffset = -20
            scaleEffect = 1.1
        }

        // 动画结束后恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if viewModel.animationState == .happy {
                viewModel.startIdleAnimation()
            }
        }
    }

    private func startWalkingAnimation() {
        withAnimation(.easeInOut(duration: 0.24).repeatForever(autoreverses: true)) {
            floatOffset = -4
            rotationAngle = 3
        }
    }

    private func startRunningAnimation() {
        withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) {
            floatOffset = -8
            rotationAngle = 6
            scaleEffect = 1.03
        }
    }

    private func startWavingAnimation() {
        withAnimation(.easeInOut(duration: 0.22).repeatCount(6, autoreverses: true)) {
            rotationAngle = 4
            floatOffset = -3
        }
    }

    /// 睡眠动画 - 趴睡姿态持续呼吸、身体轻轻起伏。
    private func startSleepingAnimation() {
        withAnimation(
            .easeInOut(duration: 2.4)
            .repeatForever(autoreverses: true)
        ) {
            floatOffset = -3
            scaleEffect = 1.035
            rotationAngle = usesDedicatedSleepPose ? 0.7 : 1.2
        }
    }
}

/// AppKit 双击优先于单击，避免“双击翻译”同时误触身体互动；
/// `delaysPrimaryMouseButtonEvents = false` 保持透明窗口原有拖拽手感。
private struct SpriteClickCaptureView: NSViewRepresentable {
    let onSingleClick: (CGPoint, CGSize) -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> SpriteClickCaptureNSView {
        SpriteClickCaptureNSView(
            onSingleClick: onSingleClick,
            onDoubleClick: onDoubleClick
        )
    }

    func updateNSView(_ nsView: SpriteClickCaptureNSView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
}

private final class SpriteClickCaptureNSView: NSView {
    var onSingleClick: (CGPoint, CGSize) -> Void
    var onDoubleClick: () -> Void

    init(
        onSingleClick: @escaping (CGPoint, CGSize) -> Void,
        onDoubleClick: @escaping () -> Void
    ) {
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
        super.init(frame: .zero)

        let single = SpriteSingleClickGestureRecognizer(target: self, action: #selector(handleSingle(_:)))
        single.numberOfClicksRequired = 1
        single.delaysPrimaryMouseButtonEvents = false

        let double = NSClickGestureRecognizer(target: self, action: #selector(handleDouble(_:)))
        double.numberOfClicksRequired = 2
        double.delaysPrimaryMouseButtonEvents = false

        addGestureRecognizer(double)
        addGestureRecognizer(single)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func handleSingle(_ recognizer: NSClickGestureRecognizer) {
        onSingleClick(recognizer.location(in: self), bounds.size)
    }

    @objc private func handleDouble(_ recognizer: NSClickGestureRecognizer) {
        onDoubleClick()
    }
}

private final class SpriteSingleClickGestureRecognizer: NSClickGestureRecognizer {
    override func shouldRequireFailure(of otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        guard let click = otherGestureRecognizer as? NSClickGestureRecognizer else { return false }
        return click.numberOfClicksRequired > numberOfClicksRequired
    }
}

// MARK: - 气泡视图

struct BubbleView: View {
    let bubble: SpriteBubble
    var onDismiss: (() -> Void)? = nil
    /// 切换目标语言重译（仅翻译结果气泡使用）
    var onRetranslate: ((Language) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            bubbleContent
            bubbleArrow
        }
    }

    private var bubbleContent: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                // 点击文本区域关闭气泡；手势只挂在内容上，
                // 避免与操作按钮行、语言菜单的点击竞争
                Group {
                    if bubble.type == .response {
                        if bubble.isStreaming {
                            // 打字机进行中：纯文本渲染，避免半截 Markdown 反复重排闪烁
                            streamingTextView
                        } else {
                            // 响应式高度：内容少时自适应，内容多时显示滚动
                            responsiveMarkdownView
                        }
                    } else {
                        // 普通文本：高度自适应，无需 ScrollView
                        Text(bubble.message)
                            .font(BuBuFonts.body)
                            .foregroundColor(bubbleTextColor)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss?()
                }

                actionRow
            }
            .frame(minWidth: bubble.type == .response ? 100 : 60,
                   maxWidth: bubble.type == .response ? 260 : 240)
            .background(bubbleBackground)

            // 翻译结果显示关闭按钮
            if bubble.type == .response {
                Button(action: {
                    onDismiss?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
    }

    // MARK: - 操作按钮行

    /// 翻译结果的内置操作（复制/朗读/切换语言）+ 气泡自带的自定义按钮
    @ViewBuilder
    private var actionRow: some View {
        let showBuiltins = bubble.type == .response && !bubble.isStreaming
        if showBuiltins || !bubble.actions.isEmpty {
            HStack(spacing: 12) {
                ForEach(bubble.actions) { action in
                    bubbleActionButton(title: action.title, icon: action.icon, color: BuBuColors.skyBlue) {
                        action.handler()
                    }
                }

                if showBuiltins {
                    Spacer(minLength: 0)

                    bubbleActionButton(title: "复制", icon: "doc.on.doc", color: BuBuColors.skyBlue) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(bubble.message, forType: .string)
                    }

                    bubbleActionButton(title: "朗读", icon: "speaker.wave.2", color: BuBuColors.lavender) {
                        if SpeechService.shared.isSpeaking {
                            SpeechService.shared.stopSpeaking()
                        } else {
                            SpeechService.shared.speak(bubble.message)
                        }
                    }

                    if onRetranslate != nil {
                        Menu {
                            ForEach(Language.allCases.filter { $0 != .auto }, id: \.self) { lang in
                                Button(lang.displayName) {
                                    onRetranslate?(lang)
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "globe")
                                Text("语言")
                            }
                            .font(BuBuFonts.tiny)
                            .foregroundColor(BuBuColors.skyBlue)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func bubbleActionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                Text(title)
            }
            .font(BuBuFonts.tiny)
            .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 打字机文本视图
    /// 与 Markdown 视图同样的自适应策略；超高后切滚动并自动跟随底部

    @ViewBuilder
    private var streamingTextView: some View {
        ViewThatFits(in: .vertical) {
            streamingText
                .fixedSize(horizontal: false, vertical: true)

            ScrollViewReader { proxy in
                ScrollView {
                    streamingText
                    Color.clear
                        .frame(height: 1)
                        .id("bubble-bottom")
                }
                .frame(maxHeight: 300)
                .onChange(of: bubble.message) { _, _ in
                    proxy.scrollTo("bubble-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var streamingText: some View {
        Text(bubble.message + "▌")
            .font(BuBuFonts.body)
            .foregroundColor(BuBuColors.chocolateBrown)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 响应式 Markdown 视图
    /// 内容少时自适应高度，内容多时最大 300 并显示滚动
    @ViewBuilder
    private var responsiveMarkdownView: some View {
        // 使用 ViewThatFits 自动选择合适的布局
        ViewThatFits(in: .vertical) {
            // 优先：内容可完全显示时，自适应高度（无滚动）
            markdownContent
                .fixedSize(horizontal: false, vertical: true)

            // 备选：内容超出时，使用 ScrollView 限制最大高度
            ScrollView {
                markdownContent
            }
            .frame(maxHeight: 300)
        }
    }

    private var markdownContent: some View {
        Markdown(bubble.message)
            .markdownTheme(.bubuTheme)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bubbleTextColor: Color {
        switch bubble.type {
        case .error:
            return BuBuColors.coralPink
        case .thinking:
            return BuBuColors.chocolateBrown.opacity(0.7)
        default:
            return BuBuColors.chocolateBrown
        }
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: BuBuShapes.bubbleRadius)
            .fill(BuBuColors.bubbleGradient)
            .shadow(color: BuBuColors.skyBlue.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    private var bubbleArrow: some View {
        Triangle()
            .fill(BuBuColors.creamWhite)
            .frame(width: 14, height: 10)
            .rotationEffect(.degrees(180))
    }
}

// MARK: - 三角形

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Zzz 动画视图

struct ZzzView: View {
    @State private var opacity1: Double = 0
    @State private var opacity2: Double = 0
    @State private var opacity3: Double = 0
    @State private var offset1: CGFloat = 0
    @State private var offset2: CGFloat = 0
    @State private var offset3: CGFloat = 0

    var body: some View {
        ZStack {
            Text("z")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .opacity(opacity1)
                .offset(y: offset1)

            Text("z")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .opacity(opacity2)
                .offset(x: 10, y: -15 + offset2)

            Text("Z")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .opacity(opacity3)
                .offset(x: 22, y: -35 + offset3)
        }
        .foregroundColor(BuBuColors.lavender)
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        // 第一个 z
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            opacity1 = 1
            offset1 = -8
        }

        // 第二个 z（延迟）
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.3)) {
            opacity2 = 1
            offset2 = -8
        }

        // 第三个 Z（更大延迟）
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.6)) {
            opacity3 = 1
            offset3 = -8
        }
    }
}

// MARK: - 思考点动画

struct ThinkingDotsView: View {
    @State private var scale1: CGFloat = 1
    @State private var scale2: CGFloat = 1
    @State private var scale3: CGFloat = 1

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(BuBuColors.skyBlue)
                .frame(width: 8, height: 8)
                .scaleEffect(scale1)

            Circle()
                .fill(BuBuColors.skyBlue)
                .frame(width: 8, height: 8)
                .scaleEffect(scale2)

            Circle()
                .fill(BuBuColors.skyBlue)
                .frame(width: 8, height: 8)
                .scaleEffect(scale3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
            scale1 = 1.4
        }

        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(0.15)) {
            scale2 = 1.4
        }

        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(0.3)) {
            scale3 = 1.4
        }
    }
}

// MARK: - 预览

#Preview {
    SpriteView(viewModel: SpriteViewModel())
        .frame(width: 220, height: 320)
        .background(BuBuColors.softCloud)
}
