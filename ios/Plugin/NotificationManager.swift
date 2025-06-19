import Foundation
import Capacitor
import UserNotifications

class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private static let categoryWithoutActionIdentifier = "ALARM_CATEGORY_NO_ACTION"
    private static let categoryWithActionIdentifierPrefix = "ALARM_CATEGORY_WITH_ACTION_"
    private static let notificationIdentifierPrefix = "ALARM_NOTIFICATION_"
    private static let stopActionIdentifier = "ALARM_STOP_ACTION"
    private static let userInfoAlarmIdKey = "ALARM_ID"

    private var plugin: AlarmPlugin?

    override private init() {
        super.init()
        Task {
            await self.setupDefaultNotificationCategory()
        }
    }

    func setPlugin(_ plugin: AlarmPlugin) {
        self.plugin = plugin
    }

    private func setupDefaultNotificationCategory() async {
        let categoryWithoutAction = UNNotificationCategory(identifier: NotificationManager.categoryWithoutActionIdentifier, actions: [], intentIdentifiers: [], options: [])
        let existingCategories = await UNUserNotificationCenter.current().notificationCategories()
        var categories = existingCategories
        categories.insert(categoryWithoutAction)
        UNUserNotificationCenter.current().setNotificationCategories(categories)

        let categoryIdentifiers = categories.map { $0.identifier }.joined(separator: ", ")
        CAPLog.print("[AlarmPlugin] Setup notification categories: \(categoryIdentifiers)")
    }

    private func registerCategoryIfNeeded(forActionTitle actionTitle: String) async {
        let categoryIdentifier = "\(NotificationManager.categoryWithActionIdentifierPrefix)\(actionTitle)"

        let existingCategories = await UNUserNotificationCenter.current().notificationCategories()
        if existingCategories.contains(where: { $0.identifier == categoryIdentifier }) {
            return
        }

        let action = UNNotificationAction(identifier: NotificationManager.stopActionIdentifier, title: actionTitle, options: [.foreground, .destructive])
        let category = UNNotificationCategory(identifier: categoryIdentifier, actions: [action], intentIdentifiers: [], options: [.hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle])

        var categories = existingCategories
        categories.insert(category)
        UNUserNotificationCenter.current().setNotificationCategories(categories)

        // Without this delay the action does not register/appear.
        try? await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))

        let categoryIdentifiers = categories.map { $0.identifier }.joined(separator: ", ")
        CAPLog.print("[AlarmPlugin] Added new category \(categoryIdentifier). Notification categories are now: \(categoryIdentifiers)")
    }
    
    private func makeImageAttachment(from imagePath: String, withId attachmentId: String = "image") -> UNNotificationAttachment? {
            guard let webURL = URL(string: imagePath),
                  let bridge = plugin?.bridge,
                  let localURL = bridge.localURL(fromWebURL: webURL) else {
                CAPLog.print("[AlarmPlugin] Failed to create URL from image path: \(imagePath)")
                return nil
            }
            
            do {
                let attachment = try UNNotificationAttachment(
                    identifier: attachmentId,
                    url: localURL,
                    options: [
                        UNNotificationAttachmentOptionsThumbnailHiddenKey: false
                    ]
                )
                CAPLog.print("[AlarmPlugin] Created notification attachment successfully for: \(imagePath)")
                return attachment
            } catch {
                CAPLog.print("[AlarmPlugin] Error creating notification attachment: \(error.localizedDescription)")
                return nil
            }
        }

    func showNotification(id: Int, notificationSettings: NotificationSettings) async {
        let notifSettings = await UNUserNotificationCenter.current().notificationSettings()
        guard notifSettings.authorizationStatus == .authorized else {
            CAPLog.print("[AlarmPlugin] Notification permission not granted. Cannot schedule alarm notification. Please request permission first.")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = notificationSettings.title
        content.body = notificationSettings.body
        content.sound = nil
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }
        content.userInfo = [NotificationManager.userInfoAlarmIdKey: id]
        
        if let imagePath = notificationSettings.image {
            if let attachment = makeImageAttachment(from: imagePath, withId: "alarm_image_\(id)") {
                content.attachments = [attachment]
                CAPLog.print("[AlarmPlugin] Added image attachment to notification for alarm ID=\(id)")
            } else {
                CAPLog.print("[AlarmPlugin] Failed to create image attachment for alarm ID=\(id)")
            }
        }
        
        if let stopButtonTitle = notificationSettings.stopButton {
            let categoryIdentifier = "\(NotificationManager.categoryWithActionIdentifierPrefix)\(stopButtonTitle)"
            await registerCategoryIfNeeded(forActionTitle: stopButtonTitle)
            content.categoryIdentifier = categoryIdentifier
        } else {
            content.categoryIdentifier = NotificationManager.categoryWithoutActionIdentifier
        }

        let request = UNNotificationRequest(identifier: "\(NotificationManager.notificationIdentifierPrefix)\(id)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            CAPLog.print("[AlarmPlugin] Notification shown for alarm ID=\(id)")
        } catch {
            CAPLog.print("[AlarmPlugin] Error when showing alarm ID=\(id) notification: \(error.localizedDescription)")
        }
    }

    func cancelNotification(id: Int) {
        let notificationIdentifier = "\(NotificationManager.notificationIdentifierPrefix)\(id)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        CAPLog.print("[AlarmPlugin] Cancelled notification: \(notificationIdentifier)")
    }

    func dismissNotification(id: Int) {
        let notificationIdentifier = "\(NotificationManager.notificationIdentifierPrefix)\(id)"
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
        CAPLog.print("[AlarmPlugin] Dismissed notification: \(notificationIdentifier)")
    }

    /// Remove all notifications scheduled by this plugin.
    func removeAllNotifications() async {
        let center = UNUserNotificationCenter.current()

        let pendingNotifs = await center.pendingNotificationRequests()
        let toCancel = pendingNotifs.filter { isAlarmNotificationContent($0.content) }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: toCancel)
        CAPLog.print("[AlarmPlugin] Cancelled \(toCancel.count) notifications.")

        let deliveredNotifs = await center.deliveredNotifications()
        let toDismiss = deliveredNotifs.filter { isAlarmNotification($0) }.map { $0.request.identifier }
        center.removeDeliveredNotifications(withIdentifiers: toDismiss)
        CAPLog.print("[AlarmPlugin] Dismissed \(toDismiss.count) notifications.")
    }

    private func handleAction(withIdentifier identifier: String, for notification: UNNotification) {
        guard let id = notification.request.content.userInfo[NotificationManager.userInfoAlarmIdKey] as? Int else { return }

        switch identifier {
        case NotificationManager.stopActionIdentifier:
            CAPLog.print("[AlarmPlugin] Stop action triggered for notification: \(notification.request.identifier)")
            guard let plugin = self.plugin else {
                CAPLog.print("[AlarmPlugin] Alarm plugin not available.")
                return
            }
            
            // Stop the alarm directly through internal method
            Task {
                await plugin.stopAlarmInternal(alarmId: id)
            }
        default:
            break
        }
    }

    private func isAlarmNotification(_ notification: UNNotification) -> Bool {
        return isAlarmNotificationContent(notification.request.content)
    }

    private func isAlarmNotificationContent(_ content: UNNotificationContent) -> Bool {
        return content.userInfo[NotificationManager.userInfoAlarmIdKey] != nil
    }

    func sendWarningNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        content.userInfo = [NotificationManager.userInfoAlarmIdKey: 0]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "notification on app kill immediate", content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            CAPLog.print("[AlarmPlugin] Warning notification scheduled.")
        } catch {
            CAPLog.print("[AlarmPlugin] Error when scheduling warning notification: \(error.localizedDescription)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if !isAlarmNotification(response.notification) {
            completionHandler()
            return
        }
        handleAction(withIdentifier: response.actionIdentifier, for: response.notification)
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if !isAlarmNotification(notification) {
            completionHandler([])
            return
        }
        completionHandler([.badge, .sound, .alert])
    }
}
