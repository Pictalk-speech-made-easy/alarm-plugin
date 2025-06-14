import AVFoundation
import Capacitor

class AppTerminateManager: NSObject {
    static let shared = AppTerminateManager()

    private var notificationTitleOnKill: String? = nil
    private var notificationBodyOnKill: String? = nil
    private var observerAdded: Bool = false

    override private init() {
        super.init()
    }

    func setWarningNotification(title: String, body: String) {
        self.notificationTitleOnKill = title
        self.notificationBodyOnKill = body
    }

    func startMonitoring() {
        if self.observerAdded {
            CAPLog.print("[AlarmPlugin] App terminate monitoring already active.")
            return
        }

        NotificationCenter.default.addObserver(self, selector: #selector(self.appWillTerminate(notification:)), name: UIApplication.willTerminateNotification, object: nil)
        self.observerAdded = true
        CAPLog.print("[AlarmPlugin] App terminate monitoring started.")
    }

    func stopMonitoring() {
        if !self.observerAdded {
            CAPLog.print("[AlarmPlugin] App terminate monitoring already inactive.")
            return
        }

        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        self.observerAdded = false
        CAPLog.print("[AlarmPlugin] App terminate monitoring stopped.")
    }

    @objc private func appWillTerminate(notification: Notification) {
        CAPLog.print("[AlarmPlugin] App is going to terminate.")
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await self.sendWarningNotification()
            semaphore.signal()
        }
        semaphore.wait()
    }

    private func sendWarningNotification() async {
        let title = self.notificationTitleOnKill ?? "Your alarms may not ring"
        let body = self.notificationBodyOnKill ?? "You killed the app. Please reopen so your alarms can be rescheduled."
        await NotificationManager.shared.sendWarningNotification(title: title, body: body)
    }
}
