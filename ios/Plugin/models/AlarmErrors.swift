import Foundation

enum AlarmError: Error, LocalizedError {
    case missingAlarmSettings
    case invalidAlarmId
    case invalidDateTime
    case invalidDateTimeFormat
    case invalidAssetAudioPath
    case invalidVolumeSettings
    case invalidNotificationSettings
    case invalidNotificationTitle
    case invalidNotificationBody
    case invalidFadeStepTime
    case invalidFadeStepVolume
    case alarmNotFound
    case alarmAlreadyExists
    case permissionDenied
    case audioFileNotFound
    case audioPlaybackFailed
    case notificationSchedulingFailed
    case backgroundPermissionDenied
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .missingAlarmSettings:
            return "Alarm settings are required"
        case .invalidAlarmId:
            return "Invalid alarm ID provided"
        case .invalidDateTime:
            return "Invalid date time provided"
        case .invalidDateTimeFormat:
            return "Date time must be in ISO 8601 format"
        case .invalidAssetAudioPath:
            return "Invalid asset audio path provided"
        case .invalidVolumeSettings:
            return "Invalid volume settings provided"
        case .invalidNotificationSettings:
            return "Invalid notification settings provided"
        case .invalidNotificationTitle:
            return "Invalid notification title provided"
        case .invalidNotificationBody:
            return "Invalid notification body provided"
        case .invalidFadeStepTime:
            return "Invalid fade step time provided"
        case .invalidFadeStepVolume:
            return "Invalid fade step volume provided"
        case .alarmNotFound:
            return "Alarm not found"
        case .alarmAlreadyExists:
            return "Alarm with this ID already exists"
        case .permissionDenied:
            return "Required permissions not granted"
        case .audioFileNotFound:
            return "Audio file not found"
        case .audioPlaybackFailed:
            return "Audio playback failed"
        case .notificationSchedulingFailed:
            return "Failed to schedule notification"
        case .backgroundPermissionDenied:
            return "Background app refresh permission denied"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}