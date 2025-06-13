import ObjectiveC
import Capacitor
import UIKit
import Foundation

class AppTerminateManager: NSObject {
    static let shared = AppTerminateManager()
    
    private var notificationTitleOnKill: String?
    private var notificationBodyOnKill: String?
    private var observerAdded = false
    
    override private init() {
        super.init()
    }
    
    func setWarningNotification(title: String, body: String) {
        notificationTitleOnKill = title
        notificationBodyOnKill = body
    }
    
    func startMonitoring() {
        if observerAdded {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "App terminate monitoring already active")
            return
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        observerAdded = true
        CAPLog.print("[", AlarmPlugin.tag, "] ", "App terminate monitoring started")
    }
    
    func stopMonitoring() {
        if !observerAdded {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "App terminate monitoring already inactive")
            return
        }
        
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        observerAdded = false
        CAPLog.print("[", AlarmPlugin.tag, "] ", "App terminate monitoring stopped")
    }
    
    @objc private func appWillTerminate(notification: Notification) {
        CAPLog.print("[", AlarmPlugin.tag, "] ", "App is going to terminate")
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await sendWarningNotification()
            semaphore.signal()
        }
        semaphore.wait()
    }
    
    private func sendWarningNotification() async {
        let title = notificationTitleOnKill ?? "Your alarms may not ring"
        let body = notificationBodyOnKill ?? "You killed the app. Please reopen so your alarms can be rescheduled."
        await NotificationManager.shared.sendWarningNotification(title: title, body: body)
    }
}
