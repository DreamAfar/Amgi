import XCTest
@testable import AnkiApp

final class ReviewSelectionActionsTests: XCTestCase {
    func testLookupPresetStorePersistsMigratedLegacyPresetID() {
        let suiteName = "ReviewSelectionActionsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected dedicated test defaults suite")
            return
        }
        defaults.set(
            "app://lookup?text={text}",
            forKey: ReviewPreferences.Keys.selectionMenuLookupTemplate
        )

        let firstLoad = ReviewSelectionLookupPresetStore.load(defaults: defaults)
        let secondLoad = ReviewSelectionLookupPresetStore.load(defaults: defaults)

        XCTAssertEqual(firstLoad.selectedPresetID, secondLoad.selectedPresetID)
        XCTAssertEqual(secondLoad.activePreset.template, "app://lookup?text={text}")

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testResolveTemplateUsesEncodingForTextPlaceholderByDefault() {
        let resolved = ReviewSelectionURLBuilder.resolveTemplate(
            template: "app://lookup?text={text}",
            selection: "hello world"
        )

        XCTAssertEqual(resolved, "app://lookup?text=hello%20world")
    }

    func testResolveTemplateSupportsRawAndEncodedPlaceholdersSeparately() {
        let resolved = ReviewSelectionURLBuilder.resolveTemplate(
            template: "app://lookup?text={text}&raw={text_raw}&encoded={text_encoded}",
            selection: "hello world",
            shouldEncodeSelection: false
        )

        XCTAssertEqual(
            resolved,
            "app://lookup?text=hello world&raw=hello world&encoded=hello%20world"
        )
    }

    func testResolveRejectsTemplateWithoutScheme() {
        let url = ReviewSelectionURLBuilder.resolve(
            template: "{text}",
            selection: "hello"
        )

        XCTAssertNil(url)
    }
}
