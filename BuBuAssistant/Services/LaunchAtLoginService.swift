//
//  LaunchAtLoginService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-22.
//  开机自启服务 - 管理应用的登录项设置
//

import Foundation
import ServiceManagement

class LaunchAtLoginService: ObservableObject {
    // 单例
    static let shared = LaunchAtLoginService()

    // 是否开机自启
    @Published var isEnabled: Bool {
        didSet {
            if oldValue != isEnabled {
                setLaunchAtLogin(enabled: isEnabled)
            }
        }
    }

    private init() {
        // 读取当前状态
        isEnabled = Self.checkLaunchAtLoginStatus()
    }

    // MARK: - 检查状态

    /// 检查当前是否已设置开机自启
    private static func checkLaunchAtLoginStatus() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // macOS 12 及更早版本使用 UserDefaults 记录状态
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
    }

    // MARK: - 设置开机自启

    /// 设置开机自启
    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // 设置失败，恢复状态
                DispatchQueue.main.async {
                    self.isEnabled = !enabled
                }
            }
        } else {
            // macOS 12 及更早版本使用 SMLoginItemSetEnabled（已废弃但仍可用）
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
            let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, enabled)

            if success {
                UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
            } else {
                // 设置失败，恢复状态
                DispatchQueue.main.async {
                    self.isEnabled = !enabled
                }
            }
        }
    }

    // MARK: - 便捷方法

    /// 切换开机自启状态
    func toggle() {
        isEnabled.toggle()
    }

    /// 刷新状态
    func refresh() {
        isEnabled = Self.checkLaunchAtLoginStatus()
    }
}
