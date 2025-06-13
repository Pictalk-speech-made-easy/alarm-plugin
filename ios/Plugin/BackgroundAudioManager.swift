import Capacitor
import Foundation
import AVFAudio

class BackgroundAudioManager: NSObject {
    static let shared = BackgroundAudioManager()
    
    private var silentAudioPlayer: AVAudioPlayer?
    
    override private init() {
        super.init()
    }
    
    func start() {
        if silentAudioPlayer != nil {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Silent player already running")
            return
        }
        
        guard let silentAudioURL = Bundle.main.url(forResource: "silent", withExtension: "mp3") else {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Could not find silent audio file")
            createSilentAudioProgrammatically()
            return
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: silentAudioURL)
            setupSilentPlayer(player)
        } catch {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Could not create silent audio player: %@", error.localizedDescription)
            createSilentAudioProgrammatically()
        }
    }
    
    private func createSilentAudioProgrammatically() {
        let sampleRate = 44100.0
        let duration = 10.0
        let frameCount = Int(sampleRate * duration)
        
        guard let audioBuffer = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Failed to create audio buffer")
            return
        }
        
        audioBuffer.frameLength = AVAudioFrameCount(frameCount)
        
        if let channelData = audioBuffer.floatChannelData {
            for frame in 0..<frameCount {
                channelData[0][frame] = 0.0
            }
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("silent.wav")
        
        do {
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false
            ])
            
            try audioFile.write(from: audioBuffer)
            
            let player = try AVAudioPlayer(contentsOf: tempURL)
            setupSilentPlayer(player)
            
        } catch {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Failed to create silent audio file: %@", error.localizedDescription)
        }
    }
    
    private func setupSilentPlayer(_ player: AVAudioPlayer) {
        mixOtherAudios()
        player.numberOfLoops = -1
        player.volume = 0.01
        player.play()
        silentAudioPlayer = player
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Started silent player")
    }
    
    func refresh() {
        guard let player = silentAudioPlayer else {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Cannot refresh silent player since it's not running. Starting it")
            start()
            return
        }
        
        mixOtherAudios()
        player.pause()
        player.play()
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Refreshed silent player")
    }
    
    func stop() {
        guard let player = silentAudioPlayer else {
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Silent player already stopped")
            return
        }
        
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        player.stop()
        silentAudioPlayer = nil
        CAPLog.print("[", AlarmPlugin.tag, "] ", "Stopped silent player")
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
    
    @objc private func handleInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Interruption began")
            silentAudioPlayer?.play()
        case .ended:
            CAPLog.print("[", AlarmPlugin.tag, "] ", "Interruption ended")
            silentAudioPlayer?.play()
        default:
            break
        }
    }
}
