import AVFoundation
import Observation
import TodayCore

/// Reads the brief aloud with the best English voice on the phone: a
/// Premium or Enhanced download if there is one (Settings › Accessibility ›
/// Spoken Content › Voices), never a novelty voice.
@MainActor
@Observable
final class BriefSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    /// The last brief, shown as a card under the header until closed.
    private(set) var text: String?
    /// The day the brief is about, so its card shows on that day's page.
    private(set) var date: LocalDate?

    // Kept for the app's lifetime: a synthesizer that's released mid-sentence stops.
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String, for date: LocalDate) {
        if isSpeaking, self.date == date {
            stop()
        } else {
            if isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
            speak(text, for: date)
        }
    }

    func speak(_ text: String, for date: LocalDate) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice()
        synthesizer.speak(utterance)
        self.text = text
        self.date = date
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .word)
        finished()
    }

    /// Hides the brief's card (and stops reading it).
    func dismiss() {
        if isSpeaking { stop() }
        text = nil
        date = nil
    }

    private func finished() {
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedIfIdle() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedIfIdle() }
    }

    private func finishedIfIdle() {
        if !synthesizer.isSpeaking { finished() }
    }

    /// The highest-quality US English voice, then any English one.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
            switch voice.quality {
            case .premium: 3
            case .enhanced: 2
            default: 1
            }
        }
        let usable = AVSpeechSynthesisVoice.speechVoices().filter {
            !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        let american = usable.filter { $0.language == "en-US" }
        let english = usable.filter { $0.language.hasPrefix("en") }
        let pool = american.isEmpty ? english : american
        return pool.max { (rank($0), $1.name) < (rank($1), $0.name) } ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}
