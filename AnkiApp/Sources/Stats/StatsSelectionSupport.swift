import UIKit

@MainActor
enum StatsSelectionSupport {
    private static let selectionFeedbackGenerator = UISelectionFeedbackGenerator()

    static func selectionChanged() {
        selectionFeedbackGenerator.selectionChanged()
        selectionFeedbackGenerator.prepare()
    }
}
