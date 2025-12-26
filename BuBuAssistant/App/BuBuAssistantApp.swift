//
//  BuBuAssistantApp.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  布布助手 - macOS 桌面精灵应用入口
//

import SwiftUI

@main
struct BuBuAssistantApp: App {
    // 应用代理，处理菜单栏和生命周期
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // 持久化控制器
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        // 使用 WindowGroup 但不显示任何窗口（主要功能由 AppDelegate 管理）
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)
    }
}
