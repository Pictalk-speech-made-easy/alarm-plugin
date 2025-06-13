import Foundation

struct AlarmSettings: Codable {
    let id: Int
    let dateTime: Date
    let assetAudioPath: String
    let volumeSettings: VolumeSettings
    let notificationSettings: NotificationSettings
    let loopAudio: Bool
    let vibrate: Bool
    let warningNotificationOnKill: Bool
    let androidFullScreenIntent: Bool
    let allowAlarmOverlap: Bool
    let iOSBackgroundAudio: Bool
    let androidStopAlarmOnTermination: Bool
    let payload: String?
    
    static func fromDictionary(_ dict: [String: Any]) throws -> AlarmSettings {
        // Parse dateTime
        guard let dateTimeString = dict["dateTime"] as? String,
              let dateTime = ISO8601DateFormatter().date(from: dateTimeString) else {
            throw AlarmError.invalidDateTime
        }
        
        // Parse required fields
        guard let id = dict["id"] as? Int,
              let assetAudioPath = dict["assetAudioPath"] as? String else {
            throw AlarmError.missingRequiredFields
        }
        
        // Parse volume settings
        let volumeSettingsDict = dict["volumeSettings"] as? [String: Any] ?? [:]
        let volumeSettings = try VolumeSettings.fromDictionary(volumeSettingsDict)
        
        // Parse notification settings
        guard let notificationSettingsDict = dict["notificationSettings"] as? [String: Any] else {
            throw AlarmError.missingNotificationSettings
        }
        let notificationSettings = try NotificationSettings.fromDictionary(notificationSettingsDict)
        
        return AlarmSettings(
            id: id,
            dateTime: dateTime,
            assetAudioPath: assetAudioPath,
            volumeSettings: volumeSettings,
            notificationSettings: notificationSettings,
            loopAudio: dict["loopAudio"] as? Bool ?? true,
            vibrate: dict["vibrate"] as? Bool ?? true,
            warningNotificationOnKill: dict["warningNotificationOnKill"] as? Bool ?? true,
            androidFullScreenIntent: dict["androidFullScreenIntent"] as? Bool ?? true,
            allowAlarmOverlap: dict["allowAlarmOverlap"] as? Bool ?? false,
            iOSBackgroundAudio: dict["iOSBackgroundAudio"] as? Bool ?? true,
            androidStopAlarmOnTermination: dict["androidStopAlarmOnTermination"] as? Bool ?? true,
            payload: dict["payload"] as? String
        )
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "dateTime": ISO8601DateFormatter().string(from: dateTime),
            "assetAudioPath": assetAudioPath,
            "volumeSettings": volumeSettings.toDictionary(),
            "notificationSettings": notificationSettings.toDictionary(),
            "loopAudio": loopAudio,
            "vibrate": vibrate,
            "warningNotificationOnKill": warningNotificationOnKill,
            "androidFullScreenIntent": androidFullScreenIntent,
            "allowAlarmOverlap": allowAlarmOverlap,
            "iOSBackgroundAudio": iOSBackgroundAudio,
            "androidStopAlarmOnTermination": androidStopAlarmOnTermination
        ]
        
        if let payload = payload {
            dict["payload"] = payload
        }
        
        return dict
    }
}

struct VolumeSettings: Codable {
    let volume: Double?
    let fadeDuration: TimeInterval?
    let fadeSteps: [VolumeFadeStep]
    let volumeEnforced: Bool
    
    static func fromDictionary(_ dict: [String: Any]) throws -> VolumeSettings {
        let volume = dict["volume"] as? Double
        let fadeDuration = dict["fadeDuration"] as? TimeInterval
        let volumeEnforced = dict["volumeEnforced"] as? Bool ?? false
        
        var fadeSteps: [VolumeFadeStep] = []
        if let fadeStepsArray = dict["fadeSteps"] as? [[String: Any]] {
            fadeSteps = try fadeStepsArray.map { try VolumeFadeStep.fromDictionary($0) }
        }
        
        return VolumeSettings(
            volume: volume,
            fadeDuration: fadeDuration,
            fadeSteps: fadeSteps,
            volumeEnforced: volumeEnforced
        )
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "volumeEnforced": volumeEnforced,
            "fadeSteps": fadeSteps.map { $0.toDictionary() }
        ]
        
        if let volume = volume {
            dict["volume"] = volume
        }
        
        if let fadeDuration = fadeDuration {
            dict["fadeDuration"] = fadeDuration
        }
        
        return dict
    }
}

struct VolumeFadeStep: Codable {
    let time: TimeInterval
    let volume: Double
    
    static func fromDictionary(_ dict: [String: Any]) throws -> VolumeFadeStep {
        guard let time = dict["time"] as? TimeInterval,
              let volume = dict["volume"] as? Double else {
            throw AlarmError.invalidFadeStep
        }
        
        return VolumeFadeStep(time: time, volume: volume)
    }
    
    func toDictionary() -> [String: Any] {
        return ["time": time, "volume": volume]
    }
}

struct NotificationSettings: Codable {
    let title: String
    let body: String
    let stopButton: String?
    let icon: String?
    let iconColor: String?
    
    static func fromDictionary(_ dict: [String: Any]) throws -> NotificationSettings {
        guard let title = dict["title"] as? String,
              let body = dict["body"] as? String else {
            throw AlarmError.missingNotificationFields
        }
        
        return NotificationSettings(
            title: title,
            body: body,
            stopButton: dict["stopButton"] as? String,
            icon: dict["icon"] as? String,
            iconColor: dict["iconColor"] as? String
        )
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "title": title,
            "body": body
        ]
        
        if let stopButton = stopButton {
            dict["stopButton"] = stopButton
        }
        
        if let icon = icon {
            dict["icon"] = icon
        }
        
        if let iconColor = iconColor {
            dict["iconColor"] = iconColor
        }
        
        return dict
    }
}

enum AlarmError: Error, LocalizedError {
    case invalidDateTime
    case missingRequiredFields
    case missingNotificationSettings
    case missingNotificationFields
    case invalidFadeStep
    
    var errorDescription: String? {
        switch self {
        case .invalidDateTime:
            return "Invalid date time format"
        case .missingRequiredFields:
            return "Missing required alarm fields"
        case .missingNotificationSettings:
            return "Missing notification settings"
        case .missingNotificationFields:
            return "Missing notification title or body"
        case .invalidFadeStep:
            return "Invalid fade step configuration"
        }
    }
}
