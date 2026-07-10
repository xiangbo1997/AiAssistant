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

    // 动画状态
    @State private var floatOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var scaleEffect: CGFloat = 1.0

    // 缓存图片避免重复加载
    @State private var cachedSpriteImage: NSImage?
    @State private var lastCharacterId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // 气泡区域 - 紧贴精灵上方，内容自动撑开高度
            if viewModel.showBubble, let bubble = viewModel.currentBubble {
                BubbleView(bubble: bubble, onDismiss: {
                    viewModel.hideBubble()
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
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
            .opacity(viewModel.opacity)
            .offset(y: floatOffset)
            .rotationEffect(Angle(degrees: rotationAngle))
            .scaleEffect(scaleEffect)
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
                .offset(x: 40, y: -20)
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
        // 自定义角色：使用缓存图片，磁盘加载只在角色切换时发生（见 reloadSpriteImage）
        if let nsImage = cachedSpriteImage {
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

    /// 角色切换时重新加载自定义图片；在 body 里直接 NSImage(contentsOfFile:)
    /// 会导致每次视图刷新都做磁盘 I/O
    private func reloadSpriteImage() {
        guard viewModel.currentCharacter.id != lastCharacterId else { return }
        lastCharacterId = viewModel.currentCharacter.id

        if viewModel.currentCharacter.isCustom,
           let path = viewModel.currentCharacter.customImagePath {
            cachedSpriteImage = NSImage(contentsOfFile: path)
        } else {
            cachedSpriteImage = nil
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
        switch state {
        case .idle:
            startIdleAnimation()
        case .thinking:
            startThinkingAnimation()
        case .talking:
            startTalkingAnimation()
        case .happy:
            startHappyAnimation()
        case .sleeping:
            startSleepingAnimation()
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

    /// 睡眠动画 - 缓慢呼吸
    private func startSleepingAnimation() {
        withAnimation(
            .easeInOut(duration: 3)
            .repeatForever(autoreverses: true)
        ) {
            scaleEffect = 0.95
        }
    }
}

// MARK: - 气泡视图

struct BubbleView: View {
    let bubble: SpriteBubble
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            bubbleContent
            bubbleArrow
        }
        .onTapGesture {
            onDismiss?()
        }
    }

    private var bubbleContent: some View {
        ZStack(alignment: .topTrailing) {
            // 使用 MarkdownUI 渲染（适用于翻译/搜索结果）
            if bubble.type == .response {
                // 响应式高度：内容少时自适应，内容多时显示滚动
                responsiveMarkdownView
                    .frame(minWidth: 100, maxWidth: 260)
                    .background(bubbleBackground)
            } else {
                // 普通文本：高度自适应，无需 ScrollView
                Text(bubble.message)
                    .font(BuBuFonts.body)
                    .foregroundColor(bubbleTextColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minWidth: 60, maxWidth: 240)
                    .background(bubbleBackground)
            }

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
        .background(Color.gray.opacity(0.1))
}
