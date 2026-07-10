//
//  GuidanceWindow.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-07-10.
//  悬浮指导窗口 - 置顶悬浮、透明无边框，截图时自动隐藏避免截到自己
//

import SwiftUI
import AppKit

class GuidanceWindow: NSPanel {
    private let viewModel: GuidanceViewModel

    init(viewModel: GuidanceViewModel) {
        self.viewModel = viewModel

        let windowSize = NSSize(width: 360, height: 560)

        super.init(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setupWindow()
        setupContentView()
        setupCaptureHooks()
        positionAtRightEdge()
    }

    // 需要接收键盘输入（输入框）
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - 窗口配置

    private func setupWindow() {
        // 置顶悬浮，跟随所有空间，不遮挡全屏应用
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // 透明无边框（阴影由 SwiftUI 卡片绘制，系统阴影会在透明窗口上产生残影）
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        isMovable = true
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }

    private func setupContentView() {
        let guidanceView = GuidanceView(viewModel: viewModel) { [weak self] in
            self?.orderOut(nil)
        }

        let hostingView = NSHostingView(rootView: guidanceView)
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        contentView = hostingView
    }

    /// 截图时隐藏窗口，避免把指导窗截进画面；截图结束后恢复显示
    private func setupCaptureHooks() {
        viewModel.onCaptureWillStart = { [weak self] in
            self?.orderOut(nil)
        }
        viewModel.onCaptureDidEnd = { [weak self] in
            self?.makeKeyAndOrderFront(nil)
        }
    }

    /// 默认位置：主屏幕右侧垂直居中（便利贴位）
    func positionAtRightEdge() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.maxX - frame.width - 24
        let y = visibleFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
