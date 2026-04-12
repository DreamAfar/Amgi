import Foundation
import AVFAudio

enum MediaAudioPreview {
    @MainActor
    private static var player: AVAudioPlayer?

    static func firstAudioFileName(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\[sound:([^\]]+)\]"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 2,
              let fileRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let value = String(text[fileRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func isLikelyAudioFieldName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let keywords = ["audio", "sound", "voice", "pronunciation", "音频", "声音", "发音", "朗读"]
        return keywords.contains { lowered.contains($0) }
    }

    @MainActor
    static func playFirstAudioTag(in text: String) throws {
        guard let fileName = firstAudioFileName(in: text) else {
            throw PreviewError.noAudioTag
        }

        let selectedUser = AppUserStore.loadSelectedUser()
        let mediaDir = AppUserStore.collectionURLs(for: selectedUser).mediaDirectory
        let fileURL = mediaDir.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PreviewError.fileNotFound(fileName)
        }

        player?.stop()
        player = try AVAudioPlayer(contentsOf: fileURL)
        player?.prepareToPlay()
        player?.play()
    }

    enum PreviewError: LocalizedError {
        case noAudioTag
        case fileNotFound(String)

        var errorDescription: String? {
            switch self {
            case .noAudioTag:
                return L("audio_preview_no_file")
            case .fileNotFound(let fileName):
                return L("audio_preview_file_not_found", fileName)
            }
        }
    }
}