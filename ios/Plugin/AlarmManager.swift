import Foundation
import Capacitor

enum AlarmState {
    case scheduled
    case ringing
    case stopped
}

struct AlarmConfig {
    let settings: AlarmSettings
    var state: AlarmState
    var timer: Timer?
}

@MainActor
class AlarmManager: NSObject {
    private weak var plugin: AlarmPlugin?
    private var alarms: [Int: AlarmConfig] = [:]
    
    init(plugin: AlarmPlugin) {
        self.plugin = plugin
        super.init()
    }
    
    func setAlarm(alarmSettings: AlarmSettings) async {
        let id = alarmSettings.id
        
        // Stop existing alarm with same ID
        await stopAlarm(id: id, cancelNotif: false)
        
        // Validate alarm time
        guard alarmSettings.dateTime > Date() else {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Alarm time must be in the future for ID %d", id)
            return
        }
        
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Setting alarm %d for %@", id, alarmSettings.dateTime.description)
        
        // Create timer for alarm
        let timer = Timer(fireAt: alarmSettings.dateTime, interval: 0, target: self, selector: #selector(timerFired(_:)), userInfo: id, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        
        // Store alarm config
        alarms[id] = AlarmConfig(settings: alarmSettings, state: .scheduled, timer: timer)
        
        // Schedule notification
        await NotificationManager.shared.scheduleNotification(for: alarmSettings)
        
        updateState()
        
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Alarm %d scheduled successfully", id)
    }
    
    func stopAlarm(id: Int, cancelNotif: Bool) async {
        guard let config = alarms[id] else {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Alarm %d not found", id)
            return
        }
        
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Stopping alarm %d", id)
        
        let wasRinging = config.state == .ringing
        
        // Invalidate timer
        config.timer?.invalidate()
        
        // Remove from active alarms
        alarms.removeValue(forKey: id)
        
        // Cancel notification if requested
        if cancelNotif {
            await NotificationManager.shared.cancelNotification(id: id)
        }
        
        // Stop ring manager if this alarm was ringing
        if wasRinging {
            await AlarmRingManager.shared.stop()
        }
        
        updateState()
        
        // Notify plugin if alarm was ringing
        if wasRinging {
            await plugin?.notifyAlarmStopped(alarmId: id)
        }
        
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Alarm %d stopped", id)
    }
    
    
    func stopAll() async {
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Stopping all alarms")
        
        let alarmIds = Array(alarms.keys)
        for id in alarmIds {
            await stopAlarm(id: id, cancelNotif: true)
        }
        
        CAPLog.print("[", AlarmPlugin.tag, "] ", "All alarms stopped")
    }
    
    func isRinging(id: Int?) -> Bool {
        if let id = id {
            return alarms[id]?.state == .ringing
        } else {
            return alarms.contains { $0.value.state == .ringing }
        }
    }
    
    func getAlarms() -> [AlarmSettings] {
        return alarms.values.map { $0.settings }
    }
    
    func checkAlarms() async {
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Checking alarms for validity")
        
        let now = Date()
        let expiredAlarmIds = alarms.compactMap { (id, config) in
            config.state == .scheduled && config.settings.dateTime <= now ? id : nil
        }
        
        for id in expiredAlarmIds {
            await stopAlarm(id: id, cancelNotif: true)
        }
        
        updateState()
        
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Alarm check completed")
    }
    
    @objc private func timerFired(_ timer: Timer) {
        guard let id = timer.userInfo as? Int else { return }
        
        Task {
            await ringAlarm(id: id)
        }
    }
    
    private func ringAlarm(id: Int) async {
        guard var config = alarms[id] else {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Alarm config not found for %d", id)
            return
        }
        
        if !config.settings.allowAlarmOverlap && alarms.contains(where: { $1.state == .ringing }) {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Ignoring alarm %d because another alarm is already ringing", id)
            await stopAlarm(id: id, cancelNotif: true)
            return
        }
        
        if config.state == .ringing {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Alarm %d is already ringing", id)
            return
        }
        
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Ringing alarm %d", id)
        
        config.state = .ringing
        config.timer?.invalidate()
        config.timer = nil
        alarms[id] = config
        
        // Show notification
        await NotificationManager.shared.showNotification(id: id, notificationSettings: config.settings.notificationSettings)
        
        // Stop background audio before ringing
        BackgroundAudioManager.shared.stop()
        
        // Start ring manager
        await AlarmRingManager.shared.start(
            assetAudioPath: config.settings.assetAudioPath,
            loopAudio: config.settings.loopAudio,
            volumeSettings: config.settings.volumeSettings,
            onComplete: config.settings.loopAudio ? nil : { [weak self] in
                Task {
                    await self?.stopAlarm(id: id, cancelNotif: false)
                }
            }
        )
        
        updateState()
        
        // Notify plugin
        await plugin?.notifyAlarmRang(alarmId: id)
        
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Ring alarm for ID=%d complete", id)
    }
    
    private func updateState() {
        // Update app terminate manager
        if alarms.contains(where: { $1.state == .scheduled && $1.settings.warningNotificationOnKill }) {
            AppTerminateManager.shared.startMonitoring()
        } else {
            AppTerminateManager.shared.stopMonitoring()
        }
        
        // Update background audio manager
        if !alarms.contains(where: { $1.state == .ringing }) &&
           alarms.contains(where: { $1.state == .scheduled && $1.settings.iOSBackgroundAudio }) {
            BackgroundAudioManager.shared.start()
        } else {
            BackgroundAudioManager.shared.stop()
        }
        
        // Update background task manager
        if alarms.contains(where: { $1.state == .scheduled }) {
            BackgroundTaskManager.enable()
        } else {
            BackgroundTaskManager.disable()
        }
        
        // Update vibration manager
        if alarms.contains(where: { $1.state == .ringing && $1.settings.vibrate }) {
            VibrationManager.shared.start()
        } else {
            VibrationManager.shared.stop()
        }
        
        CAPLog.print("[", AlarmPlugin.tag, "] ", "State updated")
    }
}
