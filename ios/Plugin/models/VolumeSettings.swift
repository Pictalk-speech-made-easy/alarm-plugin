import Foundation

struct VolumeSettings: Codable {
    var volume: Double?
    var fadeDuration: TimeInterval?
    var fadeSteps: [VolumeFadeStep]
    var volumeEnforced: Bool

    enum CodingKeys: String, CodingKey {
        case volume, fadeDuration, fadeSteps, volumeEnforced
    }

    /// Custom initializer with defaults
    init(
        volume: Double? = nil,
        fadeDuration: TimeInterval? = nil,
        fadeSteps: [VolumeFadeStep] = [],
        volumeEnforced: Bool = false
    ) {
        self.volume = volume
        self.fadeDuration = fadeDuration
        self.fadeSteps = fadeSteps
        self.volumeEnforced = volumeEnforced
    }

    /// Custom decoder for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        volume = try container.decodeIfPresent(Double.self, forKey: .volume)
        fadeDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .fadeDuration)
        fadeSteps = try container.decodeIfPresent([VolumeFadeStep].self, forKey: .fadeSteps) ?? []
        volumeEnforced = try container.decodeIfPresent(Bool.self, forKey: .volumeEnforced) ?? false
    }

    /// Converts from Capacitor data dictionary to VolumeSettings
    static func from(data: [String: Any]) throws -> VolumeSettings {
        let volume = data["volume"] as? Double
        let fadeDurationMs = data["fadeDuration"] as? Double
        let fadeDuration = fadeDurationMs.map { $0 / 1000.0 } // Convert milliseconds to seconds
        let volumeEnforced = data["volumeEnforced"] as? Bool ?? false
        
        var fadeSteps: [VolumeFadeStep] = []
        if let fadeStepsData = data["fadeSteps"] as? [[String: Any]] {
            fadeSteps = try fadeStepsData.map { stepData in
                try VolumeFadeStep.from(data: stepData)
            }
        }
        
        return VolumeSettings(
            volume: volume,
            fadeDuration: fadeDuration,
            fadeSteps: fadeSteps,
            volumeEnforced: volumeEnforced
        )
    }
    
    /// Converts VolumeSettings to dictionary for JavaScript return
    func toDictionary() -> [String: Any] {
        var result: [String: Any] = [
            "volumeEnforced": volumeEnforced,
            "fadeSteps": fadeSteps.map { $0.toDictionary() }
        ]
        
        if let volume = volume {
            result["volume"] = volume
        }
        
        if let fadeDuration = fadeDuration {
            result["fadeDuration"] = fadeDuration * 1000.0 // Convert seconds to milliseconds
        }
        
        return result
    }
}

struct VolumeFadeStep: Codable {
    var time: TimeInterval
    var volume: Double

    enum CodingKeys: String, CodingKey {
        case time, volume
    }

    /// Custom initializer
    init(time: TimeInterval, volume: Double) {
        self.time = time
        self.volume = volume
    }

    /// Converts from Capacitor data dictionary to VolumeFadeStep
    static func from(data: [String: Any]) throws -> VolumeFadeStep {
        guard let timeMs = data["time"] as? Double else {
            throw AlarmError.invalidFadeStepTime
        }
        
        guard let volume = data["volume"] as? Double else {
            throw AlarmError.invalidFadeStepVolume
        }
        
        return VolumeFadeStep(
            time: timeMs / 1000.0, // Convert milliseconds to seconds
            volume: volume
        )
    }
    
    /// Converts VolumeFadeStep to dictionary for JavaScript return
    func toDictionary() -> [String: Any] {
        return [
            "time": time * 1000.0, // Convert seconds to milliseconds
            "volume": volume
        ]
    }
}