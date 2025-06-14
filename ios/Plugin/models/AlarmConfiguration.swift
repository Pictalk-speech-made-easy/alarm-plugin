import Foundation

enum AlarmState {
    case scheduled
    case ringing
}

class AlarmConfiguration: NSObject {
    let settings: AlarmSettings
    var state: AlarmState
    var timer: Timer?
    
    init(settings: AlarmSettings) {
        self.settings = settings
        self.state = .scheduled
        self.timer = nil
        super.init()
    }
}
