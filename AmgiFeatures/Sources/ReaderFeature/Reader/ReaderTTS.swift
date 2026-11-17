//
//  ReaderTTS.swift
//  ReaderFeature
//
//  Created by Vladimir Gusev on 05.05.2026.
//

import AVFoundation
import Foundation

/// Singleton wrapper around `AVSpeechSynthesizer`. Lookup popup and reader
/// "speak this" buttons both call into the same synthesizer so a new
/// utterance preempts whatever was playing — there's only one voice in
/// the room. Language hint comes from the book's metadata when available;
/// when missing, we sniff the text for Hangul/Kana/Han characters and
/// pick a sensible voice.
/// `AVSpeechSynthesizer` is not documented thread-safe and is
/// main-thread-affine in practice, so this is isolated rather than
/// `@unchecked Sendable`.
@MainActor
final class ReaderTTS {
    static let shared = ReaderTTS()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    /// Speaks `text` using the best voice we can pick for `languageHint`.
    /// Stops any in-flight utterance first so rapid taps don't queue up.
    func speak(_ text: String, languageHint: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        if let bcp47 = Self.resolvedLanguage(hint: languageHint, fallbackText: trimmed),
           let voice = Self.bestVoice(for: bcp47) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    /// Speaks a dictionary entry. A reading written in kana settles two
    /// things the headword alone can't: that the word is Japanese — 紙 on
    /// its own is as much Chinese, and was read by a Chinese voice — and
    /// which of its readings is meant, so the kana is what gets spoken.
    func speak(term: String, reading: String?, languageHint: String?) {
        if let reading = reading?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reading.isEmpty, Self.isKana(reading) {
            speak(reading, languageHint: "ja")
        } else {
            speak(term, languageHint: languageHint)
        }
    }

    /// The voice for a language: the system's own choice, unless the user
    /// has downloaded a better-sounding one (enhanced or premium) for the
    /// same language in Settings. Only a strictly better voice replaces the
    /// default — the list also holds novelty voices of the default quality.
    static func bestVoice(for bcp47: String) -> AVSpeechSynthesisVoice? {
        guard let standard = AVSpeechSynthesisVoice(language: bcp47) else { return nil }
        let better = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == standard.language && $0.quality.rawValue > standard.quality.rawValue }
            .max { $0.quality.rawValue < $1.quality.rawValue }
        return better ?? standard
    }

    static func isKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains(Int($0.value)) }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// Maps a loose language hint (`"ko"`, `"ja-JP"`, `"english"`) to a
    /// BCP-47 tag iOS recognises. Falls back to script sniffing the text
    /// itself when no hint is supplied — Hangul → `ko-KR`, Hiragana/Katakana
    /// → `ja-JP`, Han ideographs → `zh-CN`.
    static func resolvedLanguage(hint: String?, fallbackText: String) -> String? {
        if let trimmed = hint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !trimmed.isEmpty {
            switch trimmed {
            case "ko", "ko-kr", "kor", "korean": return "ko-KR"
            case "ja", "ja-jp", "jpn", "japanese": return "ja-JP"
            case "zh", "zh-cn", "zh-hans", "chi", "chinese": return "zh-CN"
            case "zh-tw", "zh-hant": return "zh-TW"
            case "en", "en-us", "eng", "english": return "en-US"
            case "en-gb": return "en-GB"
            case "fr", "fr-fr", "french": return "fr-FR"
            case "de", "de-de", "german": return "de-DE"
            case "es", "es-es", "spanish": return "es-ES"
            case "it", "it-it", "italian": return "it-IT"
            case "pt", "pt-pt", "portuguese": return "pt-PT"
            case "ru", "ru-ru", "russian": return "ru-RU"
            default: return hint
            }
        }

        return scriptSniff(fallbackText)
    }
}

private extension ReaderTTS {
    static func scriptSniff(_ text: String) -> String? {
        for scalar in text.unicodeScalars {
            let v = Int(scalar.value)
            if (0xAC00...0xD7AF).contains(v) { return "ko-KR" }       // Hangul
            if (0x3040...0x30FF).contains(v) { return "ja-JP" }       // Kana
            if (0x3400...0x9FFF).contains(v) { return "zh-CN" }       // Han
        }
        return nil
    }
}
