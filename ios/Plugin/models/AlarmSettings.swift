import Foundation
import Capacitor

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

    enum CodingKeys: String, CodingKey {
        case id, dateTime, assetAudioPath, volumeSettings, notificationSettings,
             loopAudio, vibrate, warningNotificationOnKill, androidFullScreenIntent,
             allowAlarmOverlap, iOSBackgroundAudio, androidStopAlarmOnTermination, payload
    }

    /// Custom initializer to handle backward compatibility for older models
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode mandatory fields
        id = try container.decode(Int.self, forKey: .id)
        dateTime = try container.decode(Date.self, forKey: .dateTime)
        assetAudioPath = try container.decode(String.self, forKey: .assetAudioPath)
        notificationSettings = try container.decode(NotificationSettings.self, forKey: .notificationSettings)
        loopAudio = try container.decode(Bool.self, forKey: .loopAudio)
        vibrate = try container.decode(Bool.self, forKey: .vibrate)
        warningNotificationOnKill = try container.decode(Bool.self, forKey: .warningNotificationOnKill)
        androidFullScreenIntent = try container.decode(Bool.self, forKey: .androidFullScreenIntent)

        // Decode fields with defaults for backward compatibility
        allowAlarmOverlap = try container.decodeIfPresent(Bool.self, forKey: .allowAlarmOverlap) ?? false
        iOSBackgroundAudio = try container.decodeIfPresent(Bool.self, forKey: .iOSBackgroundAudio) ?? true
        androidStopAlarmOnTermination = try container.decodeIfPresent(Bool.self, forKey: .androidStopAlarmOnTermination) ?? true
        payload = try container.decodeIfPresent(String.self, forKey: .payload)

        // Decode volume settings (with backward compatibility)
        volumeSettings = try container.decode(VolumeSettings.self, forKey: .volumeSettings)
    }

    /// Encode method to support `Encodable` protocol
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(dateTime, forKey: .dateTime)
        try container.encode(assetAudioPath, forKey: .assetAudioPath)
        try container.encode(volumeSettings, forKey: .volumeSettings)
        try container.encode(notificationSettings, forKey: .notificationSettings)
        try container.encode(loopAudio, forKey: .loopAudio)
        try container.encode(vibrate, forKey: .vibrate)
        try container.encode(warningNotificationOnKill, forKey: .warningNotificationOnKill)
        try container.encode(androidFullScreenIntent, forKey: .androidFullScreenIntent)
        try container.encode(allowAlarmOverlap, forKey: .allowAlarmOverlap)
        try container.encode(iOSBackgroundAudio, forKey: .iOSBackgroundAudio)
        try container.encode(androidStopAlarmOnTermination, forKey: .androidStopAlarmOnTermination)
        try container.encodeIfPresent(payload, forKey: .payload)
    }

    /// Memberwise initializer
    init(
        id: Int,
        dateTime: Date,
        assetAudioPath: String,
        volumeSettings: VolumeSettings,
        notificationSettings: NotificationSettings,
        loopAudio: Bool = true,
        vibrate: Bool = true,
        warningNotificationOnKill: Bool = true,
        androidFullScreenIntent: Bool = true,
        allowAlarmOverlap: Bool = false,
        iOSBackgroundAudio: Bool = true,
        androidStopAlarmOnTermination: Bool = true,
        payload: String? = nil
    ) {
        self.id = id
        self.dateTime = dateTime
        self.assetAudioPath = assetAudioPath
        self.volumeSettings = volumeSettings
        self.notificationSettings = notificationSettings
        self.loopAudio = loopAudio
        self.vibrate = vibrate
        self.warningNotificationOnKill = warningNotificationOnKill
        self.androidFullScreenIntent = androidFullScreenIntent
        self.allowAlarmOverlap = allowAlarmOverlap
        self.iOSBackgroundAudio = iOSBackgroundAudio
        self.androidStopAlarmOnTermination = androidStopAlarmOnTermination
        self.payload = payload
    }

    /// Converts from Capacitor plugin call to AlarmSettings
    static func from(call: CAPPluginCall) throws -> AlarmSettings {
        guard let alarmSettingsData = call.getObject("alarmSettings") else {
            throw AlarmError.missingAlarmSettings
        }
        
        guard let id = alarmSettingsData["id"] as? Int else {
            throw AlarmError.invalidAlarmId
        }
        
        guard let dateTimeString = alarmSettingsData["dateTime"] as? String else {
            throw AlarmError.invalidDateTime
        }
        
        // Parse date format: 'YYYY-MM-DDTHH:mm:ss.SSS[Z]'
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        // Try with timezone first, then without
        var dateTime: Date?
        if dateTimeString.hasSuffix("Z") {
            dateTime = dateFormatter.date(from: dateTimeString)
        } else {
            // Try without timezone
            let fallbackFormatter = DateFormatter()
            fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
            fallbackFormatter.timeZone = TimeZone.current
            dateTime = fallbackFormatter.date(from: dateTimeString)
        }
        
        guard let validDateTime = dateTime else {
            throw AlarmError.invalidDateTimeFormat
        }
        
        guard let assetAudioPath = alarmSettingsData["assetAudioPath"] as? String else {
            throw AlarmError.invalidAssetAudioPath
        }
        
        guard let volumeSettingsData = alarmSettingsData["volumeSettings"] as? [String: Any] else {
            throw AlarmError.invalidVolumeSettings
        }
        
        guard let notificationSettingsData = alarmSettingsData["notificationSettings"] as? [String: Any] else {
            throw AlarmError.invalidNotificationSettings
        }
        
        let volumeSettings = try VolumeSettings.from(data: volumeSettingsData)
        let notificationSettings = try NotificationSettings.from(data: notificationSettingsData)
        
        return AlarmSettings(
            id: id,
            dateTime: validDateTime,
            assetAudioPath: assetAudioPath,
            volumeSettings: volumeSettings,
            notificationSettings: notificationSettings,
            loopAudio: alarmSettingsData["loopAudio"] as? Bool ?? true,
            vibrate: alarmSettingsData["vibrate"] as? Bool ?? true,
            warningNotificationOnKill: alarmSettingsData["warningNotificationOnKill"] as? Bool ?? true,
            androidFullScreenIntent: alarmSettingsData["androidFullScreenIntent"] as? Bool ?? true,
            allowAlarmOverlap: alarmSettingsData["allowAlarmOverlap"] as? Bool ?? false,
            iOSBackgroundAudio: alarmSettingsData["iOSBackgroundAudio"] as? Bool ?? true,
            androidStopAlarmOnTermination: alarmSettingsData["androidStopAlarmOnTermination"] as? Bool ?? true,
            payload: alarmSettingsData["payload"] as? String
        )
    }
    
    /// Converts AlarmSettings to dictionary for JavaScript return
    func toDictionary() -> [String: Any] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        return [
            "id": id,
            "dateTime": dateFormatter.string(from: dateTime),
            "assetAudioPath": assetAudioPath,
            "volumeSettings": volumeSettings.toDictionary(),
            "notificationSettings": notificationSettings.toDictionary(),
            "loopAudio": loopAudio,
            "vibrate": vibrate,
            "warningNotificationOnKill": warningNotificationOnKill,
            "androidFullScreenIntent": androidFullScreenIntent,
            "allowAlarmOverlap": allowAlarmOverlap,
            "iOSBackgroundAudio": iOSBackgroundAudio,
            "androidStopAlarmOnTermination": androidStopAlarmOnTermination,
            "payload": payload as Any
        ]
    }
}