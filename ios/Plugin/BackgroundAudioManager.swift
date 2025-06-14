import AVFoundation
import Capacitor

class BackgroundAudioManager: NSObject {
    static let shared = BackgroundAudioManager()

    private var scheduledAlarms: Set<Int> = []
    private var silentAudioPlayer: AVAudioPlayer?

    override private init() {
        super.init()
    }

    func start() {
        if self.silentAudioPlayer != nil {
            CAPLog.print("[AlarmPlugin] Silent player already running.")
            return
        }

        // In Capacitor, we need to include a silent audio file in the www/assets folder
        // or create one programmatically
        guard let audioUrl = createSilentAudioFile() else {
            CAPLog.print("[AlarmPlugin] Could not create silent audio file.")
            return
        }

        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: audioUrl)
        } catch {
            CAPLog.print("[AlarmPlugin] Could not create and play silent audio player: \(error.localizedDescription)")
            return
        }

        self.mixOtherAudios()
        player.numberOfLoops = -1
        player.volume = 0.01
        player.play()
        self.silentAudioPlayer = player
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)

        CAPLog.print("[AlarmPlugin] Started silent player.")
    }

    func refresh() {
        guard let player = self.silentAudioPlayer else {
            CAPLog.print("[AlarmPlugin] Cannot refresh silent player since it's not running. Starting it.")
            self.start()
            return
        }

        self.mixOtherAudios()
        player.pause()
        player.play()
        CAPLog.print("[AlarmPlugin] Refreshed silent player.")
    }

    func stop() {
        guard let player = self.silentAudioPlayer else {
            CAPLog.print("[AlarmPlugin] Silent player already stopped.")
            return
        }

        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        player.stop()
        self.silentAudioPlayer = nil
        CAPLog.print("[AlarmPlugin] Stopped silent player.")
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

    @objc private func handleInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
            case .began:
                CAPLog.print("[AlarmPlugin] Interruption began.")
                self.silentAudioPlayer?.play()
            case .ended:
                CAPLog.print("[AlarmPlugin] Interruption ended.")
                self.silentAudioPlayer?.play()
            default:
                break
        }
    }

    private func createSilentAudioFile() -> URL? {
        // First, try to load from bundle (if included in www/sounds)
        if let audioPath = Bundle.main.path(forResource: "www/sounds/long_blank.mp3", ofType: nil) {
            return URL(fileURLWithPath: audioPath)
        }
        
        // Fallback: Create a silent audio file programmatically
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let silentAudioURL = documentsPath.appendingPathComponent("silent_audio.m4a")
        
        // Check if file already exists
        if FileManager.default.fileExists(atPath: silentAudioURL.path) {
            return silentAudioURL
        }
        
        // Create silent audio file
        do {
            let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
            let audioFile = try AVAudioFile(forWriting: silentAudioURL, settings: audioFormat.settings)
            
            // Create 10 seconds of silence
            let frameCount = AVAudioFrameCount(audioFormat.sampleRate * 10.0)
            let silentBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)!
            silentBuffer.frameLength = frameCount
            
            // Buffer is already filled with zeros (silence)
            try audioFile.write(from: silentBuffer)
            
            CAPLog.print("[AlarmPlugin] Created silent audio file at: \(silentAudioURL.path)")
            return silentAudioURL
        } catch {
            CAPLog.print("[AlarmPlugin] Error creating silent audio file: \(error.localizedDescription)")
            return nil
        }
    }
}
