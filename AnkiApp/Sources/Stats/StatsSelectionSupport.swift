import UIKit

@MainActor
enum StatsSelectionSupport {
    private static let selectionFeedbackGenerator = UISelectionFeedbackGenerator()

    static func selectionChanged() {
        selectionFeedbackGenerator.selectionChanged()
        selectionFeedbackGenerator.prepare()
    }

    static func isHorizontalDrag(_ translation: CGSize, threshold: CGFloat = 12) -> Bool {
        abs(translation.width) > max(abs(translation.height), threshold)
    }
}
