import Foundation
import Capacitor
import AVFoundation
import UserNotifications
import UIKit

@objc(AlarmPlugin)
public class AlarmPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AlarmPlugin"
    public let jsName = "Alarm"
    
    private var implementation: AlarmManager?

    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "initialize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setAlarm", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopAlarm", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopAll", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isRinging", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAlarms", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setWarningNotificationOnKill", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkAlarm", returnType: CAPPluginReturnPromise)
    ]

    public override func load() {
        super.load()
        implementation = AlarmManager()
        implementation.delegate = self
    }
    
    @objc func initialize(_ call: CAPPluginCall) {
        Task {
            do {
                try await implementation.initialize()
                call.resolve()
            } catch {
                call.reject("Failed to initialize alarm manager: \(error.localizedDescription)")
            }
        }
    }
    
    @objc func setAlarm(_ call: CAPPluginCall) {
        guard let alarmSettingsDict = call.getObject("alarmSettings") else {
            call.reject("alarmSettings is required")
            return
        }
        
        Task {
            do {
                let alarmSettings = try parseAlarmSettings(from: alarmSettingsDict)
                try await implementation.setAlarm(alarmSettings)
                call.resolve()
            } catch {
                call.reject("Failed to set alarm: \(error.localizedDescription)")
            }
        }
    }
    
    @objc func stopAlarm(_ call: CAPPluginCall) {
        guard let alarmId = call.getInt("alarmId") else {
            call.reject("alarmId is required")
            return
        }
        
        Task {
            do {
                try await implementation.stopAlarm(id: alarmId)
                call.resolve()
            } catch {
                call.reject("Failed to stop alarm: \(error.localizedDescription)")
            }
        }
    }
    
    @objc func stopAll(_ call: CAPPluginCall) {
        Task {
            do {
                try await implementation.stopAll()
                call.resolve()
            } catch {
                call.reject("Failed to stop all alarms: \(error.localizedDescription)")
            }
        }
    }
    
    @objc func isRinging(_ call: CAPPluginCall) {
        let alarmId = call.getInt("alarmId")
        let isRinging = implementation.isRinging(id: alarmId)
        
        call.resolve([
            "isRinging": isRinging
        ])
    }
    
    @objc func getAlarms(_ call: CAPPluginCall) {
        Task {
            do {
                let alarms = try await implementation.getAlarms()
                let alarmsArray = alarms.map { alarmSettingsToDict($0) }
                
                call.resolve([
                    "alarms": alarmsArray
                ])
            } catch {
                call.reject("Failed to get alarms: \(error.localizedDescription)")
            }
        }
    }
    
    @objc func setWarningNotificationOnKill(_ call: CAPPluginCall) {
        guard let title = call.getString("title"),
              let body = call.getString("body") else {
            call.reject("title and body are required")
            return
        }
        
        implementation.setWarningNotificationOnKill(title: title, body: body)
        call.resolve()
    }
    
    @objc func checkAlarm(_ call: CAPPluginCall) {
        Task {
            do {
                try await implementation.checkAlarms()
                call.resolve()
            } catch {
                call.reject("Failed to check alarms: \(error.localizedDescription)")
            }
        }
    }
    
    private func parseAlarmSettings(from dict: [String: Any]) throws -> AlarmSettings {
        guard let id = dict["id"] as? Int,
              let dateTimeString = dict["dateTime"] as? String,
              let assetAudioPath = dict["assetAudioPath"] as? String,
              let volumeSettingsDict = dict["volumeSettings"] as? [String: Any],
              let notificationSettingsDict = dict["notificationSettings"] as? [String: Any] else {
            throw AlarmError.invalidArguments("Missing required alarm settings")
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let dateTime = formatter.date(from: dateTimeString) else {
            throw AlarmError.invalidArguments("Invalid dateTime format")
        }
        
        let volumeSettings = try parseVolumeSettings(from: volumeSettingsDict)
        let notificationSettings = try parseNotificationSettings(from: notificationSettingsDict)
        
        return AlarmSettings(
            id: id,
            dateTime: dateTime,
            assetAudioPath: assetAudioPath,
            volumeSettings: volumeSettings,
            notificationSettings: notificationSettings,
            loopAudio: dict["loopAudio"] as? Bool ?? true,
            vibrate: dict["vibrate"] as? Bool ?? true,
            warningNotificationOnKill: dict["warningNotificationOnKill"] as? Bool ?? true,
            allowAlarmOverlap: dict["allowAlarmOverlap"] as? Bool ?? false,
            iOSBackgroundAudio: dict["iOSBackgroundAudio"] as? Bool ?? true,
            payload: dict["payload"] as? String
        )
    }
    
    private func parseVolumeSettings(from dict: [String: Any]) throws -> VolumeSettings {
        let fadeSteps: [VolumeFadeStep] = (dict["fadeSteps"] as? [[String: Any]])?.compactMap { stepDict in
            guard let time = stepDict["time"] as? Int,
                  let volume = stepDict["volume"] as? Double else {
                return nil
            }
            return VolumeFadeStep(time: time, volume: Float(volume))
        } ?? []
        
        return VolumeSettings(
            volume: (dict["volume"] as? Double).map { Float($0) },
            fadeDuration: dict["fadeDuration"] as? Int,
            fadeSteps: fadeSteps,
            volumeEnforced: dict["volumeEnforced"] as? Bool ?? false
        )
    }
    
    private func parseNotificationSettings(from dict: [String: Any]) throws -> NotificationSettings {
        guard let title = dict["title"] as? String,
              let body = dict["body"] as? String else {
            throw AlarmError.invalidArguments("Missing notification title or body")
        }
        
        return NotificationSettings(
            title: title,
            body: body,
            stopButton: dict["stopButton"] as? String
        )
    }
    
    private func alarmSettingsToDict(_ alarm: AlarmSettings) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var dict: [String: Any] = [
            "id": alarm.id,
            "dateTime": formatter.string(from: alarm.dateTime),
            "assetAudioPath": alarm.assetAudioPath,
            "loopAudio": alarm.loopAudio,
            "vibrate": alarm.vibrate,
            "warningNotificationOnKill": alarm.warningNotificationOnKill,
            "allowAlarmOverlap": alarm.allowAlarmOverlap,
            "iOSBackgroundAudio": alarm.iOSBackgroundAudio,
            "volumeSettings": [
                "volume": alarm.volumeSettings.volume as Any,
                "fadeDuration": alarm.volumeSettings.fadeDuration as Any,
                "volumeEnforced": alarm.volumeSettings.volumeEnforced,
                "fadeSteps": alarm.volumeSettings.fadeSteps.map { step in
                    ["time": step.time, "volume": step.volume]
                }
            ],
            "notificationSettings": [
                "title": alarm.notificationSettings.title,
                "body": alarm.notificationSettings.body,
                "stopButton": alarm.notificationSettings.stopButton as Any
            ]
        ]
        
        if let payload = alarm.payload {
            dict["payload"] = payload
        }
        
        return dict
    }
}

// MARK: - AlarmManagerDelegate
extension AlarmPlugin: AlarmManagerDelegate {
    func alarmDidRing(id: Int) {
        notifyListeners("alarmRang", data: ["alarmId": id])
    }
    
    func alarmDidStop(id: Int) {
        notifyListeners("alarmStopped", data: ["alarmId": id])
    }
}
