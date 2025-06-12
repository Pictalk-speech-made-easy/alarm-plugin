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
    let allowAlarmOverlap: Bool
    let iOSBackgroundAudio: Bool
    let payload: String?
    
    init(id: Int, dateTime: Date, assetAudioPath: String, volumeSettings: VolumeSettings, notificationSettings: NotificationSettings, loopAudio: Bool = true, vibrate: Bool = true, warningNotificationOnKill: Bool = true, allowAlarmOverlap: Bool = false, iOSBackgroundAudio: Bool = true, payload: String? = nil) {
        self.id = id
        self.dateTime = dateTime
        self.assetAudioPath = assetAudioPath
        self.volumeSettings = volumeSettings
        self.notificationSettings = notificationSettings
        self.loopAudio = loopAudio
        self.vibrate = vibrate
        self.warningNotificationOnKill = warningNotificationOnKill
        self.allowAlarmOverlap = allowAlarmOverlap
        self.iOSBackgroundAudio = iOSBackgroundAudio
        self.payload = payload
    }
}

struct VolumeSettings: Codable {
    let volume: Float?
    let fadeDuration: Int?
    let fadeSteps: [VolumeFadeStep]
    let volumeEnforced: Bool
    
    init(volume: Float? = nil, fadeDuration: Int? = nil, fadeSteps: [VolumeFadeStep] = [], volumeEnforced: Bool = false) {
        self.volume = volume
        self.fadeDuration = fadeDuration
        self.fadeSteps = fadeSteps
        self.volumeEnforced = volumeEnforced
    }
}

struct VolumeFadeStep: Codable {
    let time: Int
    let volume: Float
}

struct NotificationSettings: Codable {
    let title: String
    let body: String
    let stopButton: String?
    
    init(title: String, body: String, stopButton: String? = nil) {
        self.title = title
        self.body = body
        self.stopButton = stopButton
    }
}

enum AlarmError: Error, LocalizedError {
    case invalidArguments(String)
    case audioFileNotFound(String)
    case notificationPermissionDenied
    case alarmNotFound(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .audioFileNotFound(let path):
            return "Audio file not found: \(path)"
        case .notificationPermissionDenied:
            return "Notification permission denied"
        case .alarmNotFound(let id):
            return "Alarm not found: \(id)"
        }
    }
}
