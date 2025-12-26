//
//  NotificationService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  本地通知服务 - 管理便签提醒通知
//

import Foundation
import UserNotifications

class NotificationService: NSObject {
    static let shared = NotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        notificationCenter.delegate = self
    }

    // MARK: - 权限请求

    /// 请求通知权限
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    /// 检查通知权限状态
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - 提醒管理

    /// 设置提醒
    func scheduleReminder(
        id: String,
        title: String,
        body: String,
        date: Date,
        repeatType: RepeatType = .none
    ) {
        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = "📝 \(title)"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "REMINDER"
        content.userInfo = ["noteId": id]

        // 创建触发器
        let trigger: UNNotificationTrigger

        switch repeatType {
        case .none:
            // 一次性提醒
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        case .daily:
            // 每天重复
            let components = Calendar.current.dateComponents(
                [.hour, .minute],
                from: date
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case .weekly:
            // 每周重复
            let components = Calendar.current.dateComponents(
                [.weekday, .hour, .minute],
                from: date
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case .monthly:
            // 每月重复
            let components = Calendar.current.dateComponents(
                [.day, .hour, .minute],
                from: date
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }

        // 创建请求
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )

        // 添加通知
        notificationCenter.add(request) { _ in
            // 添加失败，静默处理
        }
    }

    /// 取消提醒
    func cancelReminder(id: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [id])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// 取消所有提醒
    func cancelAllReminders() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }

    /// 获取所有待处理的提醒
    func getPendingReminders() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }

    // MARK: - 通知分类设置

    /// 设置通知分类和操作
    func setupNotificationCategories() {
        // 完成操作
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE",
            title: "✅ 完成",
            options: []
        )

        // 稍后提醒操作
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "⏰ 稍后提醒",
            options: []
        )

        // 查看操作
        let viewAction = UNNotificationAction(
            identifier: "VIEW",
            title: "👁 查看",
            options: [.foreground]
        )

        // 创建分类
        let reminderCategory = UNNotificationCategory(
            identifier: "REMINDER",
            actions: [completeAction, snoozeAction, viewAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([reminderCategory])
    }

    // MARK: - 即时通知

    /// 发送即时通知
    func sendInstantNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    /// 前台显示通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 前台也显示通知
        completionHandler([.banner, .sound, .badge])
    }

    /// 处理通知响应
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let noteId = userInfo["noteId"] as? String

        switch response.actionIdentifier {
        case "COMPLETE":
            // 标记便签为完成
            if let noteId = noteId {
                NotificationCenter.default.post(
                    name: .completeNote,
                    object: noteId
                )
            }

        case "SNOOZE":
            // 稍后提醒（10分钟后）
            if let noteId = noteId {
                let snoozeDate = Date().addingTimeInterval(10 * 60)
                scheduleReminder(
                    id: "\(noteId)_snooze",
                    title: response.notification.request.content.title,
                    body: response.notification.request.content.body,
                    date: snoozeDate
                )
            }

        case "VIEW":
            // 打开便签详情
            if let noteId = noteId {
                NotificationCenter.default.post(
                    name: .viewNote,
                    object: noteId
                )
            }

        default:
            // 默认点击打开应用
            if let noteId = noteId {
                NotificationCenter.default.post(
                    name: .viewNote,
                    object: noteId
                )
            }
        }

        completionHandler()
    }
}

// MARK: - 通知名称扩展

extension Notification.Name {
    static let completeNote = Notification.Name("completeNote")
    static let viewNote = Notification.Name("viewNote")
}
