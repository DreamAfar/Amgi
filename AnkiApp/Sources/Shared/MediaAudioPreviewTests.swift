import XCTest
@testable import AnkiApp

final class MediaAudioPreviewTests: XCTestCase {
    func testAudioFileNamesReturnsAllMatchesInOrder() {
        let text = """
        hello
        [sound: first.mp3]
        world [sound:second.wav]
        [sound: third .ogg ]
        """

        XCTAssertEqual(
            MediaAudioPreview.audioFileNames(in: text),
            ["first.mp3", "second.wav", "third .ogg"]
        )
    }

    func testFirstAudioFileNameReturnsFirstMatch() {
        XCTAssertEqual(
            MediaAudioPreview.firstAudioFileName(in: "[sound:a.mp3] [sound:b.mp3]"),
            "a.mp3"
        )
    }

    func testAudioFileNamesIgnoresEmptyMatches() {
        XCTAssertEqual(
            MediaAudioPreview.audioFileNames(in: "[sound:   ] text [sound:valid.mp3]"),
            ["valid.mp3"]
        )
    }
}
