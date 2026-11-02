import AVFoundation
import Capacitor

/// Says the alarm's text on the alarm's audio session; `done` always runs, also when speech fails.
class AlarmSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    // An engine that never answers must not keep the alarm silent.
    private static let timeout: TimeInterval = 15

    private let settings: SpeechSettings
    private let synthesizer = AVSpeechSynthesizer()
    private var done: (() -> Void)?
    private var timeoutTimer: Timer?

    init(settings: SpeechSettings) {
        self.settings = settings
        super.init()
        synthesizer.delegate = self
    }

    func speak(done: @escaping () -> Void) {
        self.done = done
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.timeout, repeats: false) { [weak self] _ in
            self?.finish()
        }

        let language = settings.locale ?? ""
        let utterance = AVSpeechUtterance(string: settings.text)
        // The chosen voice only if it speaks that language, as the app's utils/voice.ts picks it.
        utterance.voice = settings.voice.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
            .flatMap { $0.language.hasPrefix(language) ? $0 : nil }
            ?? AVSpeechSynthesisVoice(language: language.isEmpty ? nil : language)
        utterance.rate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(settings.rate))
        )
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    private func finish() {
        timeoutTimer?.invalidate()
        guard let done else { return }
        self.done = nil
        done()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.finish() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.finish() }
    }
}
