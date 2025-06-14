import Foundation
import Capacitor

class AlarmManager: NSObject {
    private var plugin: AlarmPlugin?
    private var alarms: [Int: AlarmConfiguration] = [:]

    init(plugin: AlarmPlugin?) {
        self.plugin = plugin
        super.init()
    }

    func setPlugin(_ plugin: AlarmPlugin) {
        self.plugin = plugin
    }

    func setAlarm(alarmSettings: AlarmSettings) async {
        if self.alarms.keys.contains(alarmSettings.id) {
            CAPLog.print("[AlarmPlugin] Stopping alarm with identical ID=\(alarmSettings.id) before scheduling a new one.")
            await self.stopAlarm(id: alarmSettings.id, cancelNotif: true)
        }

        let config = AlarmConfiguration(settings: alarmSettings)
        self.alarms[alarmSettings.id] = config

        let delayInSeconds = alarmSettings.dateTime.timeIntervalSinceNow
        let ringImmediately = delayInSeconds < 1
        if !ringImmediately {
            let timer = Timer(timeInterval: delayInSeconds,
                              target: self,
                              selector: #selector(self.alarmTimerTriggered(_:)),
                              userInfo: alarmSettings.id,
                              repeats: false)
            RunLoop.main.add(timer, forMode: .common)
            config.timer = timer
        }

        self.updateState()

        if ringImmediately {
            CAPLog.print("[AlarmPlugin] Ringing alarm ID=\(alarmSettings.id) immediately.")
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(delayInSeconds, 0.1) * 1_000_000_000))
                await self.ringAlarm(id: alarmSettings.id)
            }
        }

        CAPLog.print("[AlarmPlugin] Set alarm for ID=\(alarmSettings.id) complete.")
    }

    func stopAlarm(id: Int, cancelNotif: Bool) async {
        if cancelNotif {
            NotificationManager.shared.cancelNotification(id: id)
        }
        NotificationManager.shared.dismissNotification(id: id)

        await AlarmRingManager.shared.stop()

        if let config = self.alarms[id] {
            config.timer?.invalidate()
            config.timer = nil
            self.alarms.removeValue(forKey: id)
        }

        self.updateState()

        await self.notifyAlarmStopped(id: id)

        CAPLog.print("[AlarmPlugin] Stop alarm for ID=\(id) complete.")
    }

    func stopAll() async {
        await NotificationManager.shared.removeAllNotifications()

        await AlarmRingManager.shared.stop()

        let alarmIds = Array(self.alarms.keys)
        self.alarms.forEach { $0.value.timer?.invalidate() }
        self.alarms.removeAll()

        self.updateState()

        for alarmId in alarmIds {
            await self.notifyAlarmStopped(id: alarmId)
        }

        CAPLog.print("[AlarmPlugin] Stop all complete.")
    }

    func isRinging(id: Int? = nil) -> Bool {
        guard let alarmId = id else {
            return self.alarms.values.contains(where: { $0.state == .ringing })
        }
        return self.alarms[alarmId]?.state == .ringing
    }

    func getAlarms() -> [AlarmSettings] {
        return Array(self.alarms.values.map { $0.settings })
    }

    /// Ensures all alarm timers are valid and reschedules them if not.
    func checkAlarms() async {
        var rescheduled = 0
        for (id, config) in self.alarms {
            if config.state == .ringing || config.timer?.isValid ?? false {
                continue
            }

            rescheduled += 1

            config.timer?.invalidate()
            config.timer = nil

            let delayInSeconds = config.settings.dateTime.timeIntervalSinceNow
            if delayInSeconds <= 0 {
                await self.ringAlarm(id: id)
                continue
            }
            if delayInSeconds < 1 {
                try? await Task.sleep(nanoseconds: UInt64(delayInSeconds * 1_000_000_000))
                await self.ringAlarm(id: id)
                continue
            }

            let timer = Timer(timeInterval: delayInSeconds,
                              target: self,
                              selector: #selector(self.alarmTimerTriggered(_:)),
                              userInfo: config.settings.id,
                              repeats: false)
            RunLoop.main.add(timer, forMode: .common)
            config.timer = timer
        }

        CAPLog.print("[AlarmPlugin] Check alarms complete. Rescheduled \(rescheduled) timers.")
    }

    @objc private func alarmTimerTriggered(_ timer: Timer) {
        guard let alarmId = timer.userInfo as? Int else {
            CAPLog.print("[AlarmPlugin] Alarm timer had invalid userInfo: \(String(describing: timer.userInfo))")
            return
        }
        Task {
            await self.ringAlarm(id: alarmId)
        }
    }

    private func ringAlarm(id: Int) async {
        guard let config = self.alarms[id] else {
            CAPLog.print("[AlarmPlugin] Alarm \(id) was not found and cannot be rung.")
            return
        }

        if !config.settings.allowAlarmOverlap && self.alarms.contains(where: { $1.state == .ringing }) {
            CAPLog.print("[AlarmPlugin] Ignoring alarm with id \(id) because another alarm is already ringing.")
            await self.stopAlarm(id: id, cancelNotif: true)
            return
        }

        if config.state == .ringing {
            CAPLog.print("[AlarmPlugin] Alarm \(id) is already ringing.")
            return
        }

        CAPLog.print("[AlarmPlugin] Ringing alarm \(id)...")

        config.state = .ringing
        config.timer?.invalidate()
        config.timer = nil

        await NotificationManager.shared.showNotification(id: config.settings.id, notificationSettings: config.settings.notificationSettings)

        // Ensure background audio is stopped before ringing alarm.
        BackgroundAudioManager.shared.stop()

        await AlarmRingManager.shared.start(
            assetAudioPath: config.settings.assetAudioPath,
            loopAudio: config.settings.loopAudio,
            volumeSettings: config.settings.volumeSettings,
            onComplete: config.settings.loopAudio ? { [weak self] in
                Task {
                    await self?.stopAlarm(id: id, cancelNotif: false)
                }
            } : nil)

        self.updateState()

        await self.notifyAlarmRang(id: id)

        CAPLog.print("[AlarmPlugin] Ring alarm for ID=\(id) complete.")
    }

    @MainActor
    private func notifyAlarmRang(id: Int) async {
        guard let plugin = self.plugin else {
            CAPLog.print("[AlarmPlugin] Plugin not available for alarm rang notification.")
            return
        }

        CAPLog.print("[AlarmPlugin] Informing JavaScript that alarm \(id) has rang...")
        plugin.notifyListeners("alarmRang", data: ["alarmId": id])
        CAPLog.print("[AlarmPlugin] Alarm rang notification for \(id) sent to JavaScript.")
    }

    @MainActor
    private func notifyAlarmStopped(id: Int) async {
        guard let plugin = self.plugin else {
            CAPLog.print("[AlarmPlugin] Plugin not available for alarm stopped notification.")
            return
        }

        CAPLog.print("[AlarmPlugin] Informing JavaScript that alarm \(id) has stopped...")
        plugin.notifyListeners("alarmStopped", data: ["alarmId": id])
        CAPLog.print("[AlarmPlugin] Alarm stopped notification for \(id) sent to JavaScript.")
    }

    private func updateState() {
        if self.alarms.contains(where: { $1.state == .scheduled && $1.settings.warningNotificationOnKill }) {
            AppTerminateManager.shared.startMonitoring()
        } else {
            AppTerminateManager.shared.stopMonitoring()
        }

        if !self.alarms.contains(where: { $1.state == .ringing }) && self.alarms.contains(where: { $1.state == .scheduled && $1.settings.iOSBackgroundAudio }) {
            BackgroundAudioManager.shared.start()
        } else {
            BackgroundAudioManager.shared.stop()
        }

        if self.alarms.contains(where: { $1.state == .scheduled }) {
            BackgroundTaskManager.enable()
        } else {
            BackgroundTaskManager.disable()
        }

        if self.alarms.contains(where: { $1.state == .ringing && $1.settings.vibrate }) {
            VibrationManager.shared.start()
        } else {
            VibrationManager.shared.stop()
        }

        CAPLog.print("[AlarmPlugin] State updated.")
    }
}
