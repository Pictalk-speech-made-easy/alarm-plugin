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
        let filename: String
        
        if assetAudioPath.hasPrefix("public/sounds/") {
            filename = assetAudioPath
        } else if assetAudioPath.hasPrefix("sounds/") {
            filename = "public/\(assetAudioPath)"
        } else {
            filename = "public/sounds/\(assetAudioPath)"
        }
        
        CAPLog.print("[AlarmPlugin] Looking for audio file at: \(filename)")
        
        if let audioPath = Bundle.main.path(forResource: filename, ofType: nil) {
            CAPLog.print("[AlarmPlugin] Found audio file at: \(audioPath)")
            return createAudioPlayer(from: URL(fileURLWithPath: audioPath), originalPath: assetAudioPath)
        }
        
        let filenameWithoutExt = (filename as NSString).deletingPathExtension
        let fileExtension = (filename as NSString).pathExtension
        
        if !fileExtension.isEmpty {
            if let audioPath = Bundle.main.path(forResource: filenameWithoutExt, ofType: fileExtension) {
                CAPLog.print("[AlarmPlugin] Found audio file with separated extension at: \(audioPath)")
                return createAudioPlayer(from: URL(fileURLWithPath: audioPath), originalPath: assetAudioPath)
            }
        }
        
        CAPLog.print("[AlarmPlugin] Audio file not found: \(assetAudioPath)")
        return nil
    }

    private func createAudioPlayer(from audioURL: URL, originalPath: String) -> AVAudioPlayer? {
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            CAPLog.print("[AlarmPlugin] Audio player loaded from: \(originalPath) -> \(audioURL.path)")
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