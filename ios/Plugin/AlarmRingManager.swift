import AVFoundation
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

        self.duckOtherAudios()

        let targetSystemVolume: Float
        if let systemVolume = volumeSettings.volume.map({ Float($0) }) {
            targetSystemVolume = systemVolume
            self.previousVolume = await self.setSystemVolume(volume: systemVolume)
        } else {
            targetSystemVolume = self.getSystemVolume()
        }

        if volumeSettings.volumeEnforced {
            self.volumeEnforcementTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                AlarmRingManager.shared.enforcementTimerTriggered(targetSystemVolume: targetSystemVolume)
            }
        }

        guard let audioPlayer = self.loadAudioPlayer(assetAudioPath: assetAudioPath) else {
            await self.stop()
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
            self.fadeVolume(steps: volumeSettings.fadeSteps)
        } else if let fadeDuration = volumeSettings.fadeDuration {
            self.fadeVolume(steps: [VolumeFadeStep(time: 0, volume: 0), VolumeFadeStep(time: fadeDuration, volume: 1.0)])
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
        CAPLog.print("[AlarmPlugin] Alarm ring started in \(String(format: "%.2f", runDuration))s.")
    }

    func stop() async {
        if self.volumeEnforcementTimer == nil && self.previousVolume == nil && self.audioPlayer == nil {
            CAPLog.print("[AlarmPlugin] Alarm ringer already stopped.")
            return
        }

        let start = Date()

        self.mixOtherAudios()

        self.volumeEnforcementTimer?.invalidate()
        self.volumeEnforcementTimer = nil

        if let previousVolume = self.previousVolume {
            await self.setSystemVolume(volume: previousVolume)
            self.previousVolume = nil
        }

        self.audioPlayer?.stop()
        self.audioPlayer = nil

        let runDuration = Date().timeIntervalSince(start)
        CAPLog.print("[AlarmPlugin] Alarm ring stopped in \(String(format: "%.2f", runDuration))s.")
    }

    private func duckOtherAudios() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)
            CAPLog.print("[AlarmPlugin] Stopped other audio sources.")
        } catch {
            CAPLog.print("[AlarmPlugin] Error setting up audio session with option duckOthers: \(error.localizedDescription)")
        }
    }

    private func mixOtherAudios() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            CAPLog.print("[AlarmPlugin] Play concurrently with other audio sources.")
        } catch {
            CAPLog.print("[AlarmPlugin] Error setting up audio session with option mixWithOthers: \(error.localizedDescription)")
        }
    }

    private func getSystemVolume() -> Float {
        let audioSession = AVAudioSession.sharedInstance()
        return audioSession.outputVolume
    }

    @discardableResult
    @MainActor
    private func setSystemVolume(volume: Float) async -> Float? {
        let volumeView = MPVolumeView()

        // We need to pause for 100ms to ensure the slider loads.
        try? await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))

        guard let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider else {
            CAPLog.print("[AlarmPlugin] Volume slider could not be found.")
            return nil
        }

        let previousVolume = slider.value
        CAPLog.print("[AlarmPlugin] Setting system volume to \(volume).")
        slider.value = volume
        volumeView.removeFromSuperview()

        return previousVolume
    }

    @objc private func enforcementTimerTriggered(targetSystemVolume: Float) {
        Task {
            let currentSystemVolume = self.getSystemVolume()
            if abs(currentSystemVolume - targetSystemVolume) > 0.01 {
                CAPLog.print("[AlarmPlugin] System volume changed. Restoring to \(targetSystemVolume).")
                await self.setSystemVolume(volume: targetSystemVolume)
            }
        }
    }

    private func loadAudioPlayer(assetAudioPath: String) -> AVAudioPlayer? {
        let audioURL: URL
        
        // In Capacitor, audio files are stored in App/public/sounds
        // We need to look for them in the main bundle's www/sounds directory
        if assetAudioPath.hasPrefix("public/sounds/") {
            // Remove "public/sounds/" prefix since www folder contains the public content
            let filename = String(assetAudioPath.dropFirst(14))
            guard let audioPath = Bundle.main.path(forResource: "www/sounds/\(filename)", ofType: nil) else {
                CAPLog.print("[AlarmPlugin] Audio file not found in www/sounds folder: \(assetAudioPath)")
                return nil
            }
            audioURL = URL(fileURLWithPath: audioPath)
        } else if assetAudioPath.hasPrefix("sounds/") {
            // Handle direct sounds/ prefix
            let filename = String(assetAudioPath.dropFirst(7))
            guard let audioPath = Bundle.main.path(forResource: "www/sounds/\(filename)", ofType: nil) else {
                CAPLog.print("[AlarmPlugin] Audio file not found in www/sounds folder: \(assetAudioPath)")
                return nil
            }
            audioURL = URL(fileURLWithPath: audioPath)
        } else {
            // Try direct path in www/sounds folder
            if let audioPath = Bundle.main.path(forResource: "www/sounds/\(assetAudioPath)", ofType: nil) {
                audioURL = URL(fileURLWithPath: audioPath)
            } else {
                // Fallback: try in documents directory for user-uploaded files
                guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    CAPLog.print("[AlarmPlugin] Document directory not found.")
                    return nil
                }
                audioURL = documentsDirectory.appendingPathComponent(assetAudioPath)
                
                // Check if file exists in documents
                if !FileManager.default.fileExists(atPath: audioURL.path) {
                    CAPLog.print("[AlarmPlugin] Audio file not found: \(assetAudioPath)")
                    return nil
                }
            }
        }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            CAPLog.print("[AlarmPlugin] Audio player loaded from: \(assetAudioPath)")
            return audioPlayer
        } catch {
            CAPLog.print("[AlarmPlugin] Error loading audio player: \(error.localizedDescription)")
            return nil
        }
    }

    private func fadeVolume(steps: [VolumeFadeStep]) {
        guard let audioPlayer = self.audioPlayer else {
            CAPLog.print("[AlarmPlugin] Cannot fade volume because audioPlayer is nil.")
            return
        }

        if !audioPlayer.isPlaying {
            CAPLog.print("[AlarmPlugin] Cannot fade volume because audioPlayer isn't playing.")
            return
        }

        audioPlayer.volume = Float(steps[0].volume)

        for i in 0 ..< steps.count - 1 {
            let startTime = steps[i].time
            let nextStep = steps[i + 1]
            // Subtract 50ms to avoid weird jumps that might occur when two fades collide.
            let fadeDuration = nextStep.time - startTime - 0.05
            let targetVolume = Float(nextStep.volume)

            // Schedule the fade using setVolume for a smooth transition
            Task {
                try? await Task.sleep(nanoseconds: UInt64(startTime * 1_000_000_000))
                if !audioPlayer.isPlaying {
                    return
                }
                CAPLog.print("[AlarmPlugin] Fading volume to \(targetVolume) over \(fadeDuration) seconds.")
                audioPlayer.setVolume(targetVolume, fadeDuration: fadeDuration)
            }
        }
    }
}
