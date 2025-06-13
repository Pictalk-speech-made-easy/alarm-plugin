import Foundation
import AVFAudio
import Capacitor
import MediaPlayer

class AlarmRingManager: NSObject {
    static let shared = AlarmRingManager()
    
    private var previousVolume: Float?
    private var volumeEnforcementTimer: Timer?
    private var audioPlayer: AVAudioPlayer?
    
    override private init() {
        super.init()
    }
    
    func start(assetAudioPath: String, loopAudio: Bool, volumeSettings: VolumeSettings, onComplete: (() -> Void)?) async {
        let start = Date()
        
        duckOtherAudios()
        
        let targetSystemVolume: Float
        if let systemVolume = volumeSettings.volume.map({ Float($0) }) {
            targetSystemVolume = systemVolume
            previousVolume = await setSystemVolume(volume: systemVolume)
        } else {
            targetSystemVolume = getSystemVolume()
        }
        
        if volumeSettings.volumeEnforced {
            volumeEnforcementTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                AlarmRingManager.shared.enforcementTimerTriggered(targetSystemVolume: targetSystemVolume)
            }
        }
        
        guard let audioPlayer = loadAudioPlayer(assetAudioPath: assetAudioPath) else {
            await stop()
            return
        }
        
        if loopAudio {
            audioPlayer.numberOfLoops = -1
        }
        
        audioPlayer.prepareToPlay()
        audioPlayer.volume = 0.0
        audioPlayer.play()
        self.audioPlayer = audioPlayer
        
        if !volumeSettings.fadeSteps.isEmpty {
            fadeVolume(steps: volumeSettings.fadeSteps)
        } else if let fadeDuration = volumeSettings.fadeDuration {
            fadeVolume(steps: [
                VolumeFadeStep(time: 0, volume: 0),
                VolumeFadeStep(time: fadeDuration, volume: 1.0)
            ])
        } else {
            audioPlayer.volume = 1.0
        }
        
        if !loopAudio {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(audioPlayer.duration * 1_000_000_000))
                onComplete?()
            }
        }
        
        let runDuration = Date().timeIntervalSince(start)
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Alarm ring started in %.2fs", runDuration)
    }
    
    func stop() async {
        if volumeEnforcementTimer == nil && previousVolume == nil && audioPlayer == nil {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Alarm ringer already stopped")
            return
        }
        
        let start = Date()
        
        mixOtherAudios()
        
        volumeEnforcementTimer?.invalidate()
        volumeEnforcementTimer = nil
        
        if let previousVolume = previousVolume {
            await setSystemVolume(volume: previousVolume)
            self.previousVolume = nil
        }
        
        audioPlayer?.stop()
        audioPlayer = nil
        
        let runDuration = Date().timeIntervalSince(start)
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Alarm ring stopped in %.2fs", runDuration)
    }
    
    private func duckOtherAudios() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Stopped other audio sources")
        } catch {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Error setting up audio session with option duckOthers: %@", error.localizedDescription)
        }
    }
    
    private func mixOtherAudios() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Play concurrently with other audio sources")
        } catch {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Error setting up audio session with option mixWithOthers: %@", error.localizedDescription)
        }
    }
    
    private func getSystemVolume() -> Float {
        return AVAudioSession.sharedInstance().outputVolume
    }
    
    @discardableResult
    @MainActor
    private func setSystemVolume(volume: Float) async -> Float? {
        let volumeView = MPVolumeView()
        
        try? await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))
        
        guard let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider else {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Volume slider could not be found")
            return nil
        }
        
        let previousVolume = slider.value
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Setting system volume to %f", volume)
        slider.value = volume
        volumeView.removeFromSuperview()
        
        return previousVolume
    }
    
    @objc private func enforcementTimerTriggered(targetSystemVolume: Float) {
        Task {
            let currentSystemVolume = getSystemVolume()
            if abs(currentSystemVolume - targetSystemVolume) > 0.01 {
                CAPLog.print("[", AlarmPlugin.tag, "] ", "System volume changed. Restoring to %f", targetSystemVolume)
                await setSystemVolume(volume: targetSystemVolume)
            }
        }
    }
    
    private func loadAudioPlayer(assetAudioPath: String) -> AVAudioPlayer? {
        let audioURL: URL
        
        if assetAudioPath.hasPrefix("assets/") || assetAudioPath.hasPrefix("asset/") {
            let filename = String(assetAudioPath.dropFirst(7))
            guard let bundleURL = Bundle.main.url(forResource: filename, withExtension: nil) else {
                CAPLog.print("[", AlarmPlugin.tag, "] ", "Audio file not found: %@", assetAudioPath)
                return nil
            }
            audioURL = bundleURL
        } else {
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                CAPLog.print("[", AlarmPlugin.tag, "] ", "Document directory not found")
                return nil
            }
            audioURL = documentsDirectory.appendingPathComponent(assetAudioPath)
        }
        
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Audio player loaded from: %@", assetAudioPath)
            return audioPlayer
        } catch {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Error loading audio player: %@", error.localizedDescription)
            return nil
        }
    }
    
    private func fadeVolume(steps: [VolumeFadeStep]) {
        guard let audioPlayer = audioPlayer else {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Cannot fade volume because audioPlayer is nil")
            return
        }
        
        if !audioPlayer.isPlaying {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Cannot fade volume because audioPlayer isn't playing")
            return
        }
        
        audioPlayer.volume = Float(steps[0].volume)
        
        for i in 0..<steps.count - 1 {
            let startTime = steps[i].time
            let nextStep = steps[i + 1]
            let fadeDuration = nextStep.time - startTime - 0.05
            let targetVolume = Float(nextStep.volume)
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(startTime * 1_000_000_000))
                if !audioPlayer.isPlaying {
                    return
                }
                CAPLog.print("[", AlarmPlugin.tag, "] ", "Fading volume to %f over %f seconds", targetVolume, fadeDuration)
                audioPlayer.setVolume(targetVolume, fadeDuration: fadeDuration)
            }
        }
    }
}
