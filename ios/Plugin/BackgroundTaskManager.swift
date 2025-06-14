import BackgroundTasks
import Capacitor

class BackgroundTaskManager: NSObject {
    // Use a Capacitor-specific identifier for background tasks
    private static let backgroundTaskIdentifier: String = "com.capacitor.alarm.refresh"

    private static var enabled: Bool = false
    private static var plugin: AlarmPlugin?

    static func setPlugin(_ plugin: AlarmPlugin) {
        self.plugin = plugin
    }

    static func setup() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            // Schedule the next task:
            self.enable()

            // Run the task:
            Task {
                await self.appRefresh()
                task.setTaskCompleted(success: true)
                CAPLog.print("[AlarmPlugin] App refresh task executed.")
            }
        }
        CAPLog.print("[AlarmPlugin] App refresh task listener registered.")
    }

    static func enable() {
        if enabled {
            CAPLog.print("[AlarmPlugin] App refresh task already active.")
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        // 15 minutes
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(15 * 60))

        do {
            try BGTaskScheduler.shared.submit(request)
            CAPLog.print("[AlarmPlugin] App refresh task submitted.")
        } catch {
            CAPLog.print("[AlarmPlugin] Could not schedule app refresh task: \(error.localizedDescription)")
        }

        enabled = true
    }

    static func disable() {
        if !enabled {
            CAPLog.print("[AlarmPlugin] App refresh task already inactive.")
            return
        }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
        enabled = false
        CAPLog.print("[AlarmPlugin] App refresh task cancelled.")
    }

    private static func appRefresh() async {
        guard let plugin = self.plugin else {
            CAPLog.print("[AlarmPlugin] Plugin not available for app refresh.")
            return
        }

        // Check and reschedule alarms when app refreshes in background
        await plugin.checkAlarms()
        CAPLog.print("[AlarmPlugin] App refresh completed - alarms checked.")
    }
}
