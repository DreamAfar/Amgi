import AVFoundation
import Foundation

struct CardTTSPayload {
    let text: String
    let lang: String
    let voices: [String]
    let speed: Float
    let token: String

    init?(messageBody: Any) {
        guard let payload = messageBody as? [String: Any] else {
            return nil
        }

        self.text = ((payload["text"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.lang = ((payload["lang"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        self.voices = ((payload["voices"] as? String) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.speed = Float((payload["speed"] as? String) ?? "") ?? 1
        self.token = ((payload["token"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class CardTTSPlayer: NSObject, AVSpeechSynthesizerDelegate {
    var onEvent: ((String, String) -> Void)?

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var tokensByUtterance: [ObjectIdentifier: String] = [:]

    var isSpeakingNow: Bool {
        speechSynthesizer.isSpeaking
    }

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    func speak(messageBody: Any, playAudioInSilentMode: Bool) {
        guard let payload = CardTTSPayload(messageBody: messageBody) else {
            return
        }
        guard !payload.text.isEmpty else {
            emitEvent(state: "error", token: payload.token)
            return
        }

        stop()

        do {
            try configureAudioSession(playAudioInSilentMode: playAudioInSilentMode)
        } catch {
            print("[CardTTSPlayer] TTS audio session configure failed: \(error)")
            emitEvent(state: "error", token: payload.token)
            deactivateAudioSession()
            return
        }

        let utterance = AVSpeechUtterance(string: payload.text)
        if !payload.token.isEmpty {
            tokensByUtterance[ObjectIdentifier(utterance)] = payload.token
        }

        if let voice = preferredVoice(lang: payload.lang, preferredNames: payload.voices) {
            utterance.voice = voice
        } else if !payload.lang.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(language: payload.lang)
        }

        let speedMultiplier = max(0.25, min(payload.speed, 2.0))
        let mappedRate = AVSpeechUtteranceDefaultSpeechRate * speedMultiplier
        utterance.rate = min(
            max(mappedRate, AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )
        speechSynthesizer.speak(utterance)
    }

    func stop() {
        if speechSynthesizer.isSpeaking || speechSynthesizer.isPaused {
            speechSynthesizer.stopSpeaking(at: .immediate)
        } else {
            deactivateAudioSession()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.emitDelegateEvent(state: "start", utteranceID: utteranceID, removeToken: false)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.emitDelegateEvent(state: "finish", utteranceID: utteranceID)
            self?.deactivateAudioSession()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.emitDelegateEvent(state: "cancel", utteranceID: utteranceID)
            self?.deactivateAudioSession()
        }
    }

    private func emitDelegateEvent(
        state: String,
        utteranceID: ObjectIdentifier,
        removeToken: Bool = true
    ) {
        let token = tokensByUtterance[utteranceID] ?? ""
        if removeToken {
            tokensByUtterance.removeValue(forKey: utteranceID)
        }
        emitEvent(state: state, token: token)
    }

    private func emitEvent(state: String, token: String) {
        onEvent?(state, token)
    }

    private func configureAudioSession(playAudioInSilentMode: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if playAudioInSilentMode {
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
        } else {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        }
        try session.setActive(true, options: [])
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func preferredVoice(lang: String, preferredNames: [String]) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()

        for preferredName in preferredNames {
            if let voice = voices.first(where: { $0.identifier.caseInsensitiveCompare(preferredName) == .orderedSame }) {
                return voice
            }
            if let voice = voices.first(where: { $0.name.caseInsensitiveCompare(preferredName) == .orderedSame }) {
                return voice
            }
        }

        guard !lang.isEmpty else { return nil }
        return voices.first(where: { $0.language.caseInsensitiveCompare(lang) == .orderedSame })
            ?? voices.first(where: { $0.language.lowercased().hasPrefix(lang.lowercased()) })
    }
}
