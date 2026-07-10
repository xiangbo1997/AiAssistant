//
//  ScreenshotService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-07-10.
//  截图服务 - 调用系统 screencapture 完成交互式框选截图，并处理屏幕录制权限
//

import AppKit

class ScreenshotService {
    static let shared = ScreenshotService()
    private init() {}

    // MARK: - 权限

    /// 是否已授予屏幕录制权限
    func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 请求屏幕录制权限（首次调用触发系统弹窗；授权后需重启应用才能生效）
    @discardableResult
    func requestScreenCapturePermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// 打开系统设置的「屏幕录制」权限页
    func openScreenRecordingSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 截图

    /// 交互式框选截图（体验与 Cmd+Shift+4 一致，按空格可切换整窗截取）。
    /// 返回压缩后的 JPEG 数据（适合发给视觉 LLM）；用户按 Esc 取消时返回 nil。
    func captureInteractive() async -> Data? {
        guard let rawData = await captureInteractiveRaw(),
              let image = NSImage(data: rawData) else {
            return nil
        }

        // 压缩后再返回：截图仅在内存中使用，用完即删，不做持久化
        return image.compressedForLLM()
    }

    /// 交互式框选截图，返回原始 PNG 数据。
    /// 本地 OCR 对压缩和缩放敏感，识别场景使用此方法拿全分辨率原图
    func captureInteractiveRaw() async -> Data? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", tempURL.path]

        let launched: Bool = await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume(returning: true)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }

        // 用户取消时 screencapture 正常退出但不产生文件
        guard launched else { return nil }
        return try? Data(contentsOf: tempURL)
    }
}
