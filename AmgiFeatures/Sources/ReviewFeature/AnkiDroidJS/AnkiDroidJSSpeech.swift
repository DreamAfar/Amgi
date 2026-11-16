//
//  AnkiDroidJSSpeech.swift
//  ReviewFeature
//

import AVFoundation
import Foundation

/// Text to speech for the `ankiTts*` calls, separate from the speech of
/// `{{tts}}` fields so a card script can't cut those off or be cut off by
/// them. Return codes follow Android's `TextToSpeech`, which AnkiDroid
/// passes through: 0 for success, -2 for an unsupported language.
@MainActor
final class AnkiDroidJSSpeech {
    private let synthesizer = AVSpeechSynthesizer()
    private var language: String?
    private var pitch: Float = 1
    private var rate: Float = 1

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func setLanguage(_ code: String) -> Int {
        let code = code.replacingOccurrences(of: "_", with: "-").trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty, AVSpeechSynthesisVoice(language: code) != nil else { return -2 }
        language = code
        return 0
    }

    /// 1 is normal, as on Android.
    func setPitch(_ value: Float) -> Int {
        guard value > 0 else { return -1 }
        pitch = min(max(value, 0.5), 2)
        return 0
    }

    /// 1 is normal, as on Android.
    func setSpeechRate(_ value: Float) -> Int {
        guard value > 0 else { return -1 }
        rate = value
        return 0
    }

    /// `queueMode` 0 interrupts whatever is being spoken (Android's
    /// QUEUE_FLUSH); 1 waits for it (QUEUE_ADD).
    func speak(_ text: String, queueMode: Int) -> Int {
        if queueMode == 0 { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        if let language { utterance.voice = AVSpeechSynthesisVoice(language: language) }
        utterance.pitchMultiplier = pitch
        utterance.rate = min(
            max(AVSpeechUtteranceDefaultSpeechRate * rate, AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )
        synthesizer.speak(utterance)
        return 0
    }

    func stop() -> Int {
        synthesizer.stopSpeaking(at: .immediate)
        return 0
    }
}
