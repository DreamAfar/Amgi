import Foundation
import AVFAudio

enum MediaAudioPreview {
    @MainActor
    private static let sequencer = AudioSequencer()

    static func firstAudioFileName(in text: String) -> String? {
        audioFileNames(in: text).first
    }

    static func audioFileNames(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[sound:([^\]]+)\]"#) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let fileRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            let value = String(text[fileRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    static func isLikelyAudioFieldName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let keywords = ["audio", "sound", "voice", "pronunciation", "音频", "声音", "发音", "朗读"]
        return keywords.contains { lowered.contains($0) }
    }

    @MainActor
    static func playAudioTags(in text: String) throws {
        let fileNames = audioFileNames(in: text)
        guard !fileNames.isEmpty else {
            throw PreviewError.noAudioTag
        }

        let selectedUser = AppUserStore.loadSelectedUser()
        let mediaDir = AppUserStore.collectionURLs(for: selectedUser).mediaDirectory
        let fileURLs = try fileNames.map { fileName in
            let fileURL = mediaDir.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw PreviewError.fileNotFound(fileName)
            }
            return fileURL
        }

        sequencer.play(fileURLs: fileURLs)
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

@MainActor
private final class AudioSequencer: NSObject, @preconcurrency AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var queuedFileURLs: [URL] = []
    private var currentIndex = 0

    func play(fileURLs: [URL]) {
        stop()
        queuedFileURLs = fileURLs
        currentIndex = 0
        playCurrentIfNeeded()
    }

    func stop() {
        player?.stop()
        player = nil
        queuedFileURLs = []
        currentIndex = 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        currentIndex += 1
        playCurrentIfNeeded()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        currentIndex += 1
        playCurrentIfNeeded()
    }

    private func playCurrentIfNeeded() {
        guard currentIndex < queuedFileURLs.count else {
            stop()
            return
        }

        let player = try? AVAudioPlayer(contentsOf: queuedFileURLs[currentIndex])
        player?.delegate = self
        player?.prepareToPlay()
        player?.play()
        self.player = player
    }
}
