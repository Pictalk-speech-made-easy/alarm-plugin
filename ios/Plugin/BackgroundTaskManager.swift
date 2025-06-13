import ObjectiveC
import Foundation
import Capacitor
import BackgroundTasks

class BackgroundTaskManager: NSObject {
    private static let backgroundTaskIdentifier = "com.alarm.fetch"
    private static var enabled = false
    
    static func setup() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            // Schedule next task
            enable()
            
            // Run the task
            Task {
                CAPLog.print("[", AlarmPlugin.tag, "] ", "Background task executing")
                
                // Add your background refresh logic here
                // For example, you might want to check if alarms are still valid
                
                task.setTaskCompleted(success: true)
                CAPLog.print("[", AlarmPlugin.tag, "] ", "Background task completed")
            }
        }
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Background task listener registered")
    }
    
    static func enable() {
        if enabled {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Background task already active")
            return
        }
        
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Background task submitted")
        } catch {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Could not schedule background task: %@", error.localizedDescription)
        }
        
        enabled = true
    }
    
    static func disable() {
        if !enabled {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Background task already inactive")
            return
        }
        
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
        enabled = false
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Background task cancelled")
    }
}
