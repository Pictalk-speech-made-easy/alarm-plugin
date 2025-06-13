import Foundation
import Capacitor
import AVFoundation
import UserNotifications
import UIKit

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
        CAPPluginMethod(name: "checkAlarms", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setWarningNotificationOnKill", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise)
    ]
    public static let tag = "AlarmPlugin"
    
    private var alarmManager: AlarmManager?
    
    override public func load() {
        Task { @MainActor in
            self.alarmManager = AlarmManager(plugin: self)
            CAPLog.print("[", AlarmPlugin.tag, "] ", "AlarmPlugin loaded successfully")
        }
    }
    
    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        UNUserNotificationCenter.current().getNotificationSettings(completionHandler: { permission in
            let notificationState: String
            switch permission.authorizationStatus {
            case .authorized, .ephemeral, .provisional:
                notificationState = "authorized"
            case .denied:
                notificationState = "denied"
            case .notDetermined:
                notificationState = "prompt"
            @unknown default:
                notificationState = "unknown"
            }
            call.resolve(["display": notificationState])
        })
    }
    
    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        UNUserNotificationCenter.current().requestAuthorization { granted, error in
                    guard error == nil else {
                        call.reject(error!.localizedDescription)
                        return
                    }
                    call.resolve(["display": granted ? "granted" : "denied"])
                }
    }
    
    @objc func setAlarm(_ call: CAPPluginCall) {
            guard let alarmManager = self.alarmManager else {
                call.reject("AlarmManager not initialized")
                return
            }
            
            guard let alarmData = call.getObject("alarmSettings") else {
                call.reject("Missing alarmSettings parameter")
                return
            }
            
            do {
                let alarmSettings = try parseAlarmSettings(from: alarmData)
                
                Task {
                    await alarmManager.setAlarm(alarmSettings: alarmSettings)
                    call.resolve()
                }
            } catch {
                call.reject("Invalid alarm settings: \(error.localizedDescription)")
            }
        }
    
    @objc func stopAlarm(_ call: CAPPluginCall) {
            guard let alarmManager = self.alarmManager else {
                call.reject("AlarmManager not initialized")
                return
            }
            
            guard let alarmId = call.getInt("id") else {
                call.reject("Missing alarm id parameter")
                return
            }
            
            let cancelNotif = call.getBool("cancelNotification", true)
            
            Task {
                await alarmManager.stopAlarm(id: alarmId, cancelNotif: cancelNotif)
                call.resolve()
            }
        }
    
    @objc func stopAll(_ call: CAPPluginCall) {
            guard let alarmManager = self.alarmManager else {
                call.reject("AlarmManager not initialized")
                return
            }
            
            Task {
                await alarmManager.stopAll()
                call.resolve()
            }
        }
    
    @objc func isRinging(_ call: CAPPluginCall) {
            guard let alarmManager = self.alarmManager else {
                call.reject("AlarmManager not initialized")
                return
            }
            
            let alarmId = call.getInt("id")
            Task {
                @MainActor in
                let isRinging = alarmManager.isRinging(id: alarmId)
                call.resolve(["isRinging": isRinging])
            }
        }
    
    @objc func getAlarms(_ call: CAPPluginCall) {
            guard let alarmManager = self.alarmManager else {
                call.reject("AlarmManager not initialized")
                return
            }
            
            Task { @MainActor in
                let alarms = alarmManager.getAlarms()
                let alarmsArray = alarms.map { alarmSettingsToDict($0) }
                call.resolve(["alarms": alarmsArray])
            }
        }
    
    @objc func checkAlarms(_ call: CAPPluginCall) {
            guard let alarmManager = self.alarmManager else {
                call.reject("AlarmManager not initialized")
                return
            }
            
            Task {
                await alarmManager.checkAlarms()
                call.resolve()
            }
        }
        
        @objc func setWarningNotificationOnKill(_ call: CAPPluginCall) {
            guard let title = call.getString("title"),
                  let body = call.getString("body") else {
                call.reject("Missing title or body parameter")
                return
            }
            
            AppTerminateManager.shared.setWarningNotification(title: title, body: body)
            call.resolve()
        }
    
    @MainActor
        func notifyAlarmRang(alarmId: Int) async {
            self.notifyListeners("alarmRang", data: ["alarmId": alarmId])
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Notified alarmRang for ID: \(alarmId)")
        }
        
        @MainActor
        func notifyAlarmStopped(alarmId: Int) async {
            self.notifyListeners("alarmStopped", data: ["alarmId": alarmId])
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Notified alarmStopped for ID: \(alarmId)")
        }
    
    // MARK: - Helper Methods
    
    private func parseAlarmSettings(from data: [String: Any]) throws -> AlarmSettings {
            guard let id = data["id"] as? Int else {
                throw AlarmPluginError.missingRequiredField("id")
            }
            
            guard let dateTimeString = data["dateTime"] as? String else {
                throw AlarmPluginError.missingRequiredField("dateTime")
            }
            
            guard let dateTime = ISO8601DateFormatter().date(from: dateTimeString) else {
                throw AlarmPluginError.invalidFormat("dateTime")
            }
            
            guard let assetAudioPath = data["assetAudioPath"] as? String else {
                throw AlarmPluginError.missingRequiredField("assetAudioPath")
            }
            
            // Parse volume settings
            let volumeSettings: VolumeSettings
            if let volumeData = data["volumeSettings"] as? [String: Any] {
                volumeSettings = try parseVolumeSettings(from: volumeData)
            } else {
                // Default volume settings
                volumeSettings = VolumeSettings(
                    volume: 0.5,
                    fadeDuration: nil,
                    fadeSteps: [],
                    volumeEnforced: false
                )
            }
            
            // Parse notification settings
            let notificationSettings: NotificationSettings
            if let notificationData = data["notificationSettings"] as? [String: Any] {
                notificationSettings = try parseNotificationSettings(from: notificationData)
            } else {
                // Default notification settings
                notificationSettings = NotificationSettings(
                    title: "Alarm",
                    body: "Your alarm is ringing",
                    stopButton: "Stop",
                    icon: nil,
                    iconColor: nil
                )
            }
            
            let loopAudio = data["loopAudio"] as? Bool ?? true
            let vibrate = data["vibrate"] as? Bool ?? true
            let warningNotificationOnKill = data["warningNotificationOnKill"] as? Bool ?? true
            let androidFullScreenIntent = data["androidFullScreenIntent"] as? Bool ?? true
            let allowAlarmOverlap = data["allowAlarmOverlap"] as? Bool ?? false
            let iOSBackgroundAudio = data["iOSBackgroundAudio"] as? Bool ?? true
            
            return AlarmSettings(
                id: id,
                dateTime: dateTime,
                assetAudioPath: assetAudioPath,
                volumeSettings: volumeSettings,
                notificationSettings: notificationSettings,
                loopAudio: loopAudio,
                vibrate: vibrate,
                warningNotificationOnKill: warningNotificationOnKill,
                androidFullScreenIntent: androidFullScreenIntent,
                allowAlarmOverlap: allowAlarmOverlap,
                iOSBackgroundAudio: iOSBackgroundAudio,
                androidStopAlarmOnTermination: true,
                payload: nil

            )
        }
    
    private func parseVolumeSettings(from data: [String: Any]) throws -> VolumeSettings {
            let volume = data["volume"] as? Double ?? 0.5
            
            let fadeDuration: TimeInterval?
            if let fadeDurationMs = data["fadeDuration"] as? Int {
                fadeDuration = TimeInterval(fadeDurationMs) / 1000.0
            } else {
                fadeDuration = nil
            }
            
            let fadeSteps: [VolumeFadeStep]
            if let fadeStepsData = data["fadeSteps"] as? [[String: Any]] {
                fadeSteps = try fadeStepsData.map { stepData in
                    guard let time = stepData["time"] as? Double,
                          let volumeValue = stepData["volume"] as? Double else {
                        throw AlarmPluginError.invalidFormat("fadeSteps")
                    }
                    return VolumeFadeStep(time: time, volume: volumeValue)
                }
            } else {
                fadeSteps = []
            }
            
            let volumeEnforced = data["volumeEnforced"] as? Bool ?? false
            
            return VolumeSettings(
                volume: volume,
                fadeDuration: fadeDuration,
                fadeSteps: fadeSteps,
                volumeEnforced: volumeEnforced
            )
        }
    
    private func parseNotificationSettings(from data: [String: Any]) throws -> NotificationSettings {
            let title = data["title"] as? String ?? "Alarm"
            let body = data["body"] as? String ?? "Your alarm is ringing"
            let stopButton = data["stopButton"] as? String ?? "Stop"
            let icon = data["icon"] as? String
            let iconColor = data["iconColor"] as? String
            
            return NotificationSettings(
                title: title,
                body: body,
                stopButton: stopButton,
                icon: icon,
                iconColor: iconColor
            )
        }
    
    private func alarmSettingsToDict(_ alarmSettings: AlarmSettings) -> [String: Any] {
            let formatter = ISO8601DateFormatter()
            
            return [
                "id": alarmSettings.id,
                "dateTime": formatter.string(from: alarmSettings.dateTime),
                "assetAudioPath": alarmSettings.assetAudioPath,
                "volumeSettings": volumeSettingsToDict(alarmSettings.volumeSettings),
                "notificationSettings": notificationSettingsToDict(alarmSettings.notificationSettings),
                "loopAudio": alarmSettings.loopAudio,
                "vibrate": alarmSettings.vibrate,
                "warningNotificationOnKill": alarmSettings.warningNotificationOnKill,
                "androidFullScreenIntent": alarmSettings.androidFullScreenIntent,
                "allowAlarmOverlap": alarmSettings.allowAlarmOverlap,
                "iOSBackgroundAudio": alarmSettings.iOSBackgroundAudio
            ]
        }
    private func volumeSettingsToDict(_ volumeSettings: VolumeSettings) -> [String: Any] {
            var result: [String: Any] = [
                "volume": volumeSettings.volume ?? 0.5,
                "volumeEnforced": volumeSettings.volumeEnforced
            ]
            
            if let fadeDuration = volumeSettings.fadeDuration {
                result["fadeDuration"] = Int(fadeDuration * 1000) // Convert to milliseconds
            }
            
            result["fadeSteps"] = volumeSettings.fadeSteps.map { step in
                [
                    "time": step.time,
                    "volume": step.volume
                ]
            }
            
            return result
        }
    
    private func notificationSettingsToDict(_ notificationSettings: NotificationSettings) -> [String: Any] {
            var result: [String: Any] = [
                "title": notificationSettings.title,
                "body": notificationSettings.body,
                "stopButton": notificationSettings.stopButton ?? "stop"
            ]
            
            if let icon = notificationSettings.icon {
                result["icon"] = icon
            }
            
            if let iconColor = notificationSettings.iconColor {
                result["iconColor"] = iconColor
            }
            
            return result
        }
    private func rejectCall(_ call: CAPPluginCall, _ error: Error) {
        CAPLog.print("[", AlarmPlugin.tag, "] ", error)
        call.reject(error.localizedDescription)
    }
    
    private func resolveCall(_ call: CAPPluginCall) {
        call.resolve()
    }
}

enum AlarmPluginError: LocalizedError {
    case missingRequiredField(String)
    case invalidFormat(String)
    case alarmManagerNotInitialized
    
    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidFormat(let field):
            return "Invalid format for field: \(field)"
        case .alarmManagerNotInitialized:
            return "AlarmManager not initialized"
        }
    }
}
