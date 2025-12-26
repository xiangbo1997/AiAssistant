//
//  BuBuTheme.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-20.
//  布布助手主题 - 柔和、温暖、童趣的视觉风格
//

import SwiftUI
import MarkdownUI

// MARK: - 主题颜色

struct BuBuColors {
    // 主色调 - 来自布布的配色
    static let skyBlue = Color(red: 0.55, green: 0.78, blue: 0.94)        // 天蓝色（恐龙帽衫）
    static let warmBeige = Color(red: 0.87, green: 0.76, blue: 0.68)      // 暖米色（身体）
    static let peachBlush = Color(red: 1.0, green: 0.82, blue: 0.60)      // 桃腮红
    static let chocolateBrown = Color(red: 0.30, green: 0.22, blue: 0.20) // 巧克力棕（轮廓）

    // 背景色
    static let creamWhite = Color(red: 0.99, green: 0.97, blue: 0.94)     // 奶油白
    static let softCloud = Color(red: 0.96, green: 0.94, blue: 0.98)      // 柔云紫

    // 功能色
    static let mintGreen = Color(red: 0.70, green: 0.92, blue: 0.85)      // 薄荷绿（成功）
    static let coralPink = Color(red: 1.0, green: 0.70, blue: 0.70)       // 珊瑚粉（提醒）
    static let lavender = Color(red: 0.80, green: 0.75, blue: 0.95)       // 薰衣草紫

    // 渐变
    static let skyGradient = LinearGradient(
        colors: [skyBlue.opacity(0.3), softCloud],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmGradient = LinearGradient(
        colors: [peachBlush.opacity(0.4), creamWhite],
        startPoint: .top,
        endPoint: .bottom
    )

    static let bubbleGradient = LinearGradient(
        colors: [.white, creamWhite],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - 主题字体

struct BuBuFonts {
    // 使用圆润的系统字体
    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let largeTitle = rounded(28, weight: .bold)
    static let title = rounded(20, weight: .semibold)
    static let headline = rounded(16, weight: .semibold)
    static let body = rounded(14, weight: .regular)
    static let caption = rounded(12, weight: .medium)
    static let tiny = rounded(10, weight: .regular)
}

// MARK: - 主题阴影

struct BuBuShadows {
    static let soft = ShadowStyle(
        color: BuBuColors.chocolateBrown.opacity(0.08),
        radius: 12,
        x: 0,
        y: 4
    )

    static let floating = ShadowStyle(
        color: BuBuColors.skyBlue.opacity(0.2),
        radius: 20,
        x: 0,
        y: 8
    )

    static let subtle = ShadowStyle(
        color: Color.black.opacity(0.05),
        radius: 4,
        x: 0,
        y: 2
    )
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - 主题形状

struct BuBuShapes {
    static let bubbleRadius: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 12
    static let smallRadius: CGFloat = 8
}

// MARK: - 视图修饰器

extension View {
    /// 柔和卡片样式
    func bubuCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.cardRadius)
                    .fill(Color.white)
                    .shadow(
                        color: BuBuColors.chocolateBrown.opacity(0.06),
                        radius: 12,
                        x: 0,
                        y: 4
                    )
            )
    }

    /// 气泡样式
    func bubuBubble() -> some View {
        self
            .background(
                BubbleShape()
                    .fill(BuBuColors.bubbleGradient)
                    .shadow(
                        color: BuBuColors.skyBlue.opacity(0.15),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            )
    }

    /// 柔和按钮样式
    func bubuButton(isActive: Bool = false) -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                    .fill(isActive ? BuBuColors.skyBlue : BuBuColors.creamWhite)
            )
            .foregroundColor(isActive ? .white : BuBuColors.chocolateBrown)
    }

    /// 浮动效果
    func bubuFloating() -> some View {
        self
            .shadow(
                color: BuBuColors.chocolateBrown.opacity(0.12),
                radius: 16,
                x: 0,
                y: 8
            )
    }
}

// MARK: - 气泡形状

struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 16
        let arrowSize: CGFloat = 10
        let arrowOffset: CGFloat = rect.width / 2

        // 主体圆角矩形
        let mainRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - arrowSize
        )

        path.addRoundedRect(in: mainRect, cornerSize: CGSize(width: radius, height: radius))

        // 底部箭头
        path.move(to: CGPoint(x: arrowOffset - arrowSize, y: mainRect.maxY))
        path.addLine(to: CGPoint(x: arrowOffset, y: rect.maxY))
        path.addLine(to: CGPoint(x: arrowOffset + arrowSize, y: mainRect.maxY))

        return path
    }
}

// MARK: - 装饰元素

/// 柔和的圆形装饰
struct SoftCircleDecoration: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.6), color.opacity(0.1)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: size * 0.1)
    }
}

/// 漂浮的小星星
struct FloatingStars: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<5) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: CGFloat.random(in: 8...14)))
                    .foregroundColor(BuBuColors.skyBlue.opacity(Double.random(in: 0.3...0.7)))
                    .offset(
                        x: CGFloat.random(in: -50...50),
                        y: CGFloat.random(in: -50...50)
                    )
                    .scaleEffect(animate ? 1.2 : 0.8)
                    .opacity(animate ? 1 : 0.5)
                    .animation(
                        .easeInOut(duration: Double.random(in: 1.5...2.5))
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.2),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

/// 可爱的波浪背景
struct WavyBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 底层渐变
                BuBuColors.skyGradient

                // 波浪层
                WaveShape(amplitude: 20, frequency: 1.5)
                    .fill(BuBuColors.creamWhite.opacity(0.5))
                    .frame(height: geo.size.height * 0.4)
                    .offset(y: geo.size.height * 0.3)

                WaveShape(amplitude: 15, frequency: 2)
                    .fill(BuBuColors.creamWhite.opacity(0.3))
                    .frame(height: geo.size.height * 0.3)
                    .offset(y: geo.size.height * 0.4)
            }
        }
        .ignoresSafeArea()
    }
}

struct WaveShape: Shape {
    var amplitude: CGFloat
    var frequency: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))

        for x in stride(from: 0, through: rect.width, by: 1) {
            let relativeX = x / rect.width
            let y = rect.midY + sin(relativeX * .pi * 2 * frequency) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()

        return path
    }
}

// MARK: - MarkdownUI 自定义主题

extension Theme {
    /// 布布助手 Markdown 主题 - 柔和温暖的风格
    static let bubuTheme = Theme()
        // 基础文本样式
        .text {
            ForegroundColor(BuBuColors.chocolateBrown)
            FontSize(14)
        }
        // 一级标题
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(20)
                    ForegroundColor(BuBuColors.chocolateBrown)
                }
                .markdownMargin(top: 16, bottom: 8)
        }
        // 二级标题
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(17)
                    ForegroundColor(BuBuColors.chocolateBrown)
                }
                .markdownMargin(top: 12, bottom: 6)
        }
        // 三级标题
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(15)
                    ForegroundColor(BuBuColors.chocolateBrown.opacity(0.9))
                }
                .markdownMargin(top: 10, bottom: 4)
        }
        // 代码块
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(12)
                        ForegroundColor(BuBuColors.chocolateBrown)
                    }
            }
            .padding(12)
            .background(BuBuColors.softCloud)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .markdownMargin(top: 8, bottom: 8)
        }
        // 行内代码
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(13)
            ForegroundColor(BuBuColors.chocolateBrown)
            BackgroundColor(BuBuColors.softCloud)
        }
        // 粗体
        .strong {
            FontWeight(.bold)
        }
        // 斜体
        .emphasis {
            FontStyle(.italic)
        }
        // 链接
        .link {
            ForegroundColor(BuBuColors.skyBlue)
        }
        // 引用块
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(BuBuColors.lavender)
                    .frame(width: 4)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(BuBuColors.chocolateBrown.opacity(0.8))
                        FontStyle(.italic)
                    }
                    .padding(.leading, 12)
            }
            .markdownMargin(top: 8, bottom: 8)
        }
        // 列表项
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 4, bottom: 4)
        }
        // 段落
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 4, bottom: 4)
        }
}
