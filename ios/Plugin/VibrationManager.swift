import ObjectiveC
import Capacitor
import Foundation
import AVFoundation

class VibrationManager: NSObject {
    static let shared = VibrationManager()
    
    #if targetEnvironment(simulator)
    private let isSimulator = true
    #else
    private let isSimulator = false
    #endif
    
    private var vibrationTimer: Timer?
    
    override private init() {
        super.init()
    }
    
    func start() {
        if isSimulator {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Simulator does not support vibrations")
            return
        }
        
        if vibrationTimer != nil {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Vibration already active")
            return
        }
        
        let timer = Timer(timeInterval: 1.0, target: self, selector: #selector(vibrationTimerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        vibrationTimer = timer
        timer.fire()
        
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Vibration started")
    }
    
    func stop() {
        if isSimulator {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Simulator does not support vibrations")
            return
        }
        
        guard let timer = vibrationTimer else {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Vibration already inactive")
            return
        }
        
        timer.invalidate()
        vibrationTimer = nil
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Vibration stopped")
    }
    
    @objc private func vibrationTimerFired(_ timer: Timer) {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}
