import Foundation
import AVFoundation
import UserNotifications
import UIKit

protocol AlarmManagerDelegate: AnyObject {
    func alarmDidRing(id: Int)
    func alarmDidStop(id: Int)
}

class AlarmManager: NSObject {
    
    weak var delegate: AlarmManagerDelegate?
    
    private var audioSession: AVAudioSession = AVAudioSession.sharedInstance()
    private var backgroundAudioPlayer: AVAudioPlayer?
    private var alarmPlayers: [Int: AVAudioPlayer] = [:]
    private var activeAlarms: [Int: AlarmRuntimeInfo] = [:]
    private var scheduledAlarms: [Int: Timer] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let alarmsKey = "stored_alarms"
    private let warningTitleKey = "warning_title"
    private let warningBodyKey = "warning_body"
    
    struct AlarmRuntimeInfo {
        let settings: AlarmSettings
        var isRinging: Bool
        let originalVolume: Float?
        var fadeTimer: Timer?
    }
    
    override init() {
        super.init()
        setupAudioSession()
        setupNotifications()
    }
    
    func initialize() async throws {
        try await requestNotificationPermissions()
        try await loadStoredAlarms()
        startBackgroundAudio()
    }
    
    func setAlarm(_ alarmSettings: AlarmSettings) async throws {
        // Store alarm persistently
        storeAlarm(alarmSettings)
        
        // Schedule local notification
        try await scheduleNotification(for: alarmSettings)
        
        // Schedule timer for alarm execution
        scheduleAlarmTimer(for: alarmSettings)
    }
    
    func stopAlarm(id: Int) async throws {
        // Cancel scheduled timer
        scheduledAlarms[id]?.invalidate()
        scheduledAlarms.removeValue(forKey: id)
        
        // Stop ringing alarm
        stopRingingAlarm(id: id)
        
        // Cancel notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [String(id)])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [String(id)])
        
        // Remove from storage
        removeStoredAlarm(id: id)
    }
    
    func stopAll() async throws {
        let alarms = try await getAlarms()
        for alarm in alarms {
            try await stopAlarm(id: alarm.id)
        }
    }
    
    func isRinging(id: Int?) -> Bool {
        if let id = id {
            return activeAlarms[id]?.isRinging ?? false
        } else {
            return activeAlarms.values.contains { $0.isRinging }
        }
    }
    
    func getAlarms() async throws -> [AlarmSettings] {
        guard let data = userDefaults.data(forKey: alarmsKey) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AlarmSettings].self, from: data)
    }
    
    func setWarningNotificationOnKill(title: String, body: String) {
        userDefaults.set(title, forKey: warningTitleKey)
        userDefaults.set(body, forKey: warningBodyKey)
    }
    
    func checkAlarms() async throws {
        let currentTime = Date()
        let alarms = try await getAlarms()
        var alarmsToKeep: [AlarmSettings] = []
        
        for alarm in alarms {
            if alarm.dateTime > currentTime {
                // Reschedule future alarms
                try await setAlarm(alarm)
                alarmsToKeep.append(alarm)
            } else if alarm.dateTime > currentTime.addingTimeInterval(-60) {
                // Alarm should be ringing (within last minute)
                startRingingAlarm(alarm)
            }
        }
        
        // Update stored alarms
        storeAlarms(alarmsToKeep)
    }
    
    // MARK: - Private Methods
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    private func requestNotificationPermissions() async throws {
        let center = UNUserNotificationCenter.current()
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    
    private func scheduleNotification(for alarm: AlarmSettings) async throws {
        let content = UNMutableNotificationContent()
        content.title = alarm.notificationSettings.title
        content.body = alarm.notificationSettings.body
        content.sound = .default
        content.categoryIdentifier = "ALARM_CATEGORY"
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alarm.dateTime),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: String(alarm.id),
            content: content,
            trigger: trigger
        )
        
        try await UNUserNotificationCenter.current().add(request)
    }
    
    private func scheduleAlarmTimer(for alarm: AlarmSettings) {
        let timer = Timer(fireAt: alarm.dateTime, interval: 0, target: self, selector: #selector(alarmTimerFired(_:)), userInfo: alarm, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        scheduledAlarms[alarm.id] = timer
    }
    
    @objc private func alarmTimerFired(_ timer: Timer) {
        guard let alarm = timer.userInfo as? AlarmSettings else { return }
        startRingingAlarm(alarm)
        removeStoredAlarm(id: alarm.id)
    }
    
    private func startRingingAlarm(_ alarm: AlarmSettings) {
        if !alarm.allowAlarmOverlap && activeAlarms.values.contains(where: { $0.isRinging }) {
            return
        }
        
        do {
            // Set volume if specified
            let originalVolume = setVolumeIfNeeded(alarm.volumeSettings.volume)
            
            // Create and start audio player
            let audioPlayer = try createAudioPlayer(for: alarm)
            alarmPlayers[alarm.id] = audioPlayer
            
            // Start vibration if enabled
            if alarm.vibrate {
                startVibration()
            }
            
            // Update runtime info
            activeAlarms[alarm.id] = AlarmRuntimeInfo(
                settings: alarm,
                isRinging: true,
                originalVolume: originalVolume,
                fadeTimer: nil
            )
            
            // Handle volume effects
            handleVolumeEffects(for: alarm, player: audioPlayer)
            
            audioPlayer.play()
            
            // Notify delegate
            delegate?.alarmDidRing(id: alarm.id)
            
        } catch {
            print("Failed to start ringing alarm: \(error)")
        }
    }
    
    private func stopRingingAlarm(id: Int) {
        guard let runtimeInfo = activeAlarms[id] else { return }
        
        // Stop audio player
        alarmPlayers[id]?.stop()
        alarmPlayers.removeValue(forKey: id)
        
        // Stop fade timer
        runtimeInfo.fadeTimer?.invalidate()
        
        // Restore original volume
        if let originalVolume = runtimeInfo.originalVolume {
            try? audioSession.setOutputVolume(originalVolume)
        }
        
        // Remove from active alarms
        activeAlarms.removeValue(forKey: id)
        
        // Notify delegate
        delegate?.alarmDidStop(id: id)
    }
    
    private func createAudioPlayer(for alarm: AlarmSettings) throws -> AVAudioPlayer {
        let url: URL
        
        if alarm.assetAudioPath.hasPrefix("http") {
            url = URL(string: alarm.assetAudioPath)!
        } else {
            // Handle local asset
            let fileName = alarm.assetAudioPath.replacingOccurrences(of: "assets/", with: "")
            let nameWithoutExtension = (fileName as NSString).deletingPathExtension
            let fileExtension = (fileName as NSString).pathExtension.isEmpty ? "mp3" : (fileName as NSString).pathExtension
            
            guard let assetURL = Bundle.main.url(forResource: nameWithoutExtension, withExtension: fileExtension) else {
                throw AlarmError.audioFileNotFound("Audio file not found: \(fileName)")
            }
            url = assetURL
        }
        
        let player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = alarm.loopAudio ? -1 : 0
        player.prepareToPlay()
        
        return player
    }
    
    private func setVolumeIfNeeded(_ volume: Float?) -> Float? {
        guard let targetVolume = volume else { return nil }
        
        let originalVolume = audioSession.outputVolume
        try? audioSession.setOutputVolume(targetVolume)
        return originalVolume
    }
    
    private func handleVolumeEffects(for alarm: AlarmSettings, player: AVAudioPlayer) {
        let volumeSettings = alarm.volumeSettings
        
        // Handle fade duration
        if let fadeDuration = volumeSettings.fadeDuration, fadeDuration > 0 {
            let steps = 20
            let stepDuration = Double(fadeDuration) / 1000.0 / Double(steps)
            let targetVolume = volumeSettings.volume ?? 1.0
            
            var currentStep = 0
            let fadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { timer in
                currentStep += 1
                let volume = Float(currentStep) / Float(steps) * targetVolume
                player.volume = volume
                
                if currentStep >= steps {
                    timer.invalidate()
                }
            }
            
            activeAlarms[alarm.id]?.fadeTimer = fadeTimer
        }
        
        // Handle custom fade steps
        for step in volumeSettings.fadeSteps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step.time) / 1000.0) {
                if self.activeAlarms[alarm.id]?.isRinging == true {
                    player.volume = step.volume
                }
            }
        }
        
        // Handle volume enforcement
        if volumeSettings.volumeEnforced, let targetVolume = volumeSettings.volume {
            let enforceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if self.activeAlarms[alarm.id]?.isRinging == true {
                    if abs(self.audioSession.outputVolume - targetVolume) > 0.01 {
                        try? self.audioSession.setOutputVolume(targetVolume)
                    }
                }
            }
            
            activeAlarms[alarm.id]?.fadeTimer = enforceTimer
        }
    }
    
    private func startVibration() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        
        // Continue vibrating
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.activeAlarms.values.contains(where: { $0.isRinging }) {
                self.startVibration()
            }
        }
    }
    
    private func startBackgroundAudio() {
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "mp3") else {
            print("Warning: silence.mp3 not found. Background audio may not work.")
            return
        }
        
        do {
            backgroundAudioPlayer = try AVAudioPlayer(contentsOf: url)
            backgroundAudioPlayer?.numberOfLoops = -1
            backgroundAudioPlayer?.volume = 0.01
            backgroundAudioPlayer?.play()
        } catch {
            print("Failed to start background audio: \(error)")
        }
    }
    
    private func storeAlarm(_ alarm: AlarmSettings) {
        var alarms = (try? getAlarms()) ?? []
        alarms.removeAll { $0.id == alarm.id }
        alarms.append(alarm)
        storeAlarms(alarms)
    }
    
    private func removeStoredAlarm(id: Int) {
        var alarms = (try? getAlarms()) ?? []
        alarms.removeAll { $0.id == id }
        storeAlarms(alarms)
    }
    
    private func storeAlarms(_ alarms: [AlarmSettings]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(alarms)
            userDefaults.set(data, forKey: alarmsKey)
        } catch {
            print("Failed to store alarms: \(error)")
        }
    }
    
    private func loadStoredAlarms() async throws {
        try await checkAlarms()
    }
    
    @objc private func appWillTerminate() {
        // Show warning notification if enabled
        let title = userDefaults.string(forKey: warningTitleKey)
        let body = userDefaults.string(forKey: warningBodyKey)
        
        if let title = title, let body = body {
            showWarningNotification(title: title, body: body)
        }
    }
    
    @objc private func appDidEnterBackground() {
        // Continue background audio
        if let backgroundPlayer = backgroundAudioPlayer {
            backgroundPlayer.play()
        }
    }
    
    @objc private func appWillEnterForeground() {
        Task {
            try await checkAlarms()
        }
    }
    
    private func showWarningNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "alarm_warning",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}
