import ObjectiveC
import UserNotifications
import Foundation
import Capacitor

class NotificationManager: NSObject {
    static let shared = NotificationManager()
    
    override private init() {
        super.init()
    }
    
    func scheduleNotification(for alarmSettings: AlarmSettings) async {
        let content = UNMutableNotificationContent()
        content.title = alarmSettings.notificationSettings.title
        content.body = alarmSettings.notificationSettings.body
        content.sound = .none // We handle sound separately
        
        // Add action button if specified
        if let stopButton = alarmSettings.notificationSettings.stopButton {
            let stopAction = UNNotificationAction(
                identifier: "STOP_ALARM",
                title: stopButton,
                options: [.destructive]
            )
            let category = UNNotificationCategory(
                identifier: "ALARM_CATEGORY",
                actions: [stopAction],
                intentIdentifiers: [],
                options: []
            )
            UNUserNotificationCenter.current().setNotificationCategories([category])
            content.categoryIdentifier = "ALARM_CATEGORY"
        }
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                          from: alarmSettings.dateTime),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "alarm_\(alarmSettings.id)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Notification scheduled for alarm %d", alarmSettings.id)
        } catch {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Failed to schedule notification for alarm %d: %@", alarmSettings.id, error.localizedDescription)
        }
    }
    
    func showNotification(id: Int, notificationSettings: NotificationSettings) async {
        let content = UNMutableNotificationContent()
        content.title = notificationSettings.title
        content.body = notificationSettings.body
        content.sound = .none
        
        let request = UNNotificationRequest(
            identifier: "alarm_ringing_\(id)",
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Ringing notification shown for alarm %d", id)
        } catch {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Failed to show notification for alarm %d: %@", id, error.localizedDescription)
        }
    }
    
    func cancelNotification(id: Int) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "alarm_\(id)",
            "alarm_ringing_\(id)"
        ])
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Notification cancelled for alarm %d", id)
    }
    
    func sendWarningNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "alarm_warning",
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Warning notification sent")
        } catch {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Failed to send warning notification: %@", error.localizedDescription)
        }
    }
}
