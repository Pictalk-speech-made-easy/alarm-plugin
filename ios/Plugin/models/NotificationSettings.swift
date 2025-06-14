import Foundation

struct NotificationSettings: Codable {
    var title: String
    var body: String
    var stopButton: String?
    var icon: String? // Ignored on iOS but kept for compatibility
    var iconColor: String? // Ignored on iOS but kept for compatibility

    enum CodingKeys: String, CodingKey {
        case title, body, stopButton, icon, iconColor
    }

    /// Custom initializer
    init(
        title: String,
        body: String,
        stopButton: String? = nil,
        icon: String? = nil,
        iconColor: String? = nil
    ) {
        self.title = title
        self.body = body
        self.stopButton = stopButton
        self.icon = icon
        self.iconColor = iconColor
    }

    /// Custom decoder for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        stopButton = try container.decodeIfPresent(String.self, forKey: .stopButton)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        iconColor = try container.decodeIfPresent(String.self, forKey: .iconColor)
    }

    /// Converts from Capacitor data dictionary to NotificationSettings
    static func from(data: [String: Any]) throws -> NotificationSettings {
        guard let title = data["title"] as? String else {
            throw AlarmError.invalidNotificationTitle
        }
        
        guard let body = data["body"] as? String else {
            throw AlarmError.invalidNotificationBody
        }
        
        return NotificationSettings(
            title: title,
            body: body,
            stopButton: data["stopButton"] as? String,
            icon: data["icon"] as? String,
            iconColor: data["iconColor"] as? String
        )
    }
    
    /// Converts NotificationSettings to dictionary for JavaScript return
    func toDictionary() -> [String: Any] {
        var result: [String: Any] = [
            "title": title,
            "body": body
        ]
        
        if let stopButton = stopButton {
            result["stopButton"] = stopButton
        }
        
        if let icon = icon {
            result["icon"] = icon
        }
        
        if let iconColor = iconColor {
            result["iconColor"] = iconColor
        }
        
        return result
    }
}