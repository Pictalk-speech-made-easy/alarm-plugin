import Foundation
import Capacitor
import UserNotifications

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(AlarmPlugin)
public class AlarmPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AlarmPlugin"
    public let jsName = "Alarm"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setAlarm", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopAlarm", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopAll", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isRinging", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAlarms", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getRingingAlarms", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setWarningNotificationOnKill", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestFullScreenIntentPermission", returnType: CAPPluginReturnPromise)
    ]
    public static let tag = "AlarmPlugin"

    private var manager: AlarmManager?

    override public func load() {
        self.manager = AlarmManager(plugin: self)
        
        // Setup managers with plugin reference
        NotificationManager.shared.setPlugin(self)
        BackgroundTaskManager.setPlugin(self)
        
        // Setup background task handling
        BackgroundTaskManager.setup()
        UNUserNotificationCenter.current().delegate = NotificationManager.shared

        CAPLog.print("[AlarmPlugin] Plugin loaded successfully.")
    }
    
    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        Task { @MainActor in
            let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
            let notificationState: String
            
            switch notificationSettings.authorizationStatus {
            case .notDetermined:
                notificationState = "prompt"
            case .denied:
                notificationState = "denied"
            case .authorized, .provisional, .ephemeral:
                notificationState = "granted"
            @unknown default:
                notificationState = "prompt"
            }
            
            call.resolve([
                "notifications": notificationState,
                "fullScreen": "granted"
            ])
        }
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    call.reject("Permission request failed: \(error.localizedDescription)")
                    return
                }
                
                // Return the current permission status after requesting
                self?.checkPermissions(call)
            }
        }
    }
    
    @objc func requestFullScreenIntentPermission(_ call: CAPPluginCall) {
        call.reject("Not used in iOS")
    }

    @objc func setAlarm(_ call: CAPPluginCall) {
        guard let manager = self.manager else {
            self.rejectCall(call, AlarmError.unknownError)
            return
        }

        do {
            let alarmSettings = try AlarmSettings.from(call: call)
            CAPLog.print("[AlarmPlugin] Set alarm called with ID: \(alarmSettings.id)")

            Task { @MainActor in
                await manager.setAlarm(alarmSettings: alarmSettings)
                call.resolve()
            }
        } catch {
            self.rejectCall(call, error)
        }
    }

    @objc func stopAlarm(_ call: CAPPluginCall) {
        guard let manager = self.manager else {
            self.rejectCall(call, AlarmError.unknownError)
            return
        }

        guard let alarmId = call.getInt("alarmId") else {
            self.rejectCall(call, AlarmError.invalidAlarmId)
            return
        }

        CAPLog.print("[AlarmPlugin] Stop alarm called with ID: \(alarmId)")

        Task { @MainActor in
            await manager.stopAlarm(id: alarmId, cancelNotif: true)
            call.resolve()
        }
    }

    @objc func stopAll(_ call: CAPPluginCall) {
        guard let manager = self.manager else {
            self.rejectCall(call, AlarmError.unknownError)
            return
        }

        CAPLog.print("[AlarmPlugin] Stop all alarms called")

        Task { @MainActor in
            await manager.stopAll()
            call.resolve()
        }
    }

    @objc func isRinging(_ call: CAPPluginCall) {
        guard let manager = self.manager else {
            self.rejectCall(call, AlarmError.unknownError)
            return
        }

        let alarmId = call.getInt("alarmId")
        let isRinging = manager.isRinging(id: alarmId)
        call.resolve(["isRinging": isRinging])
    }

    @objc func getAlarms(_ call: CAPPluginCall) {
        guard let manager = self.manager else {
            self.rejectCall(call, AlarmError.unknownError)
            return
        }

        let alarms = manager.getAlarms()
        let alarmsData = alarms.map { $0.toDictionary() }
        call.resolve(["alarms": alarmsData])
    }

    @objc func getRingingAlarms(_ call: CAPPluginCall) {
        guard let manager = self.manager else {
            self.rejectCall(call, AlarmError.unknownError)
            return
        }

        let alarms = manager.getRingingAlarms()
        let alarmsData = alarms.map { $0.toDictionary() }
        call.resolve(["alarms": alarmsData])
    }

    @objc func setWarningNotificationOnKill(_ call: CAPPluginCall) {
        guard let title = call.getString("title") else {
            self.rejectCall(call, AlarmError.invalidNotificationTitle)
            return
        }
        
        guard let body = call.getString("body") else {
            self.rejectCall(call, AlarmError.invalidNotificationBody)
            return
        }

        AppTerminateManager.shared.setWarningNotification(title: title, body: body)
        self.resolveCall(call)
    }

    // MARK: - Internal Methods for Background Tasks
    
    internal func checkAlarms() async {
        await self.manager?.checkAlarms()
    }

    internal func appRefresh() async {
        BackgroundAudioManager.shared.refresh()
        await self.manager?.checkAlarms()
    }

    internal func stopAlarmInternal(alarmId: Int) async {
        await self.manager?.stopAlarm(id: alarmId, cancelNotif: true)
        CAPLog.print("[AlarmPlugin] Alarm \(alarmId) stopped internally")
    }

    // MARK: - Helper Methods

    private func rejectCall(_ call: CAPPluginCall, _ error: Error) {
        CAPLog.print("[AlarmPlugin] Error: \(error.localizedDescription)")
        call.reject(error.localizedDescription)
    }

    private func resolveCall(_ call: CAPPluginCall) {
        call.resolve()
    }
}
