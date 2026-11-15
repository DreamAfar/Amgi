//
//  HTMLSourceField.swift
//  BrowseFeature
//

#if canImport(UIKit)
import SwiftUI
import Theme
import UIKit

/// A field's raw HTML in a monospaced, self-sizing text view.
///
/// UIKit rather than a SwiftUI `TextField`: SwiftUI can't turn off smart
/// quotes and dashes, which would turn `src="a.jpg"` into `src=“a.jpg”`
/// and break the markup as it's typed.
struct HTMLSourceField: View {
    @Binding var htmlText: String
    var focusOnAppear = false

    @Environment(\.palette) private var palette

    var body: some View {
        SourceTextView(
            text: $htmlText,
            textColor: UIColor(palette.textPrimary),
            tintColor: UIColor(palette.accent),
            focusOnAppear: focusOnAppear
        )
        .padding(.horizontal, AmgiSpacing.sm)
        .padding(.vertical, AmgiSpacing.xs)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: AmgiRadius.small))
        .accessibilityLabel(Text("HTML source", bundle: .module))
    }
}

private struct SourceTextView: UIViewRepresentable {
    @Binding var text: String
    let textColor: UIColor
    let tintColor: UIColor
    let focusOnAppear: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        view.adjustsFontForContentSizeCategory = true
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.dataDetectorTypes = []
        view.text = text
        view.textColor = textColor
        view.tintColor = tintColor
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if focusOnAppear {
            Task { @MainActor in view.becomeFirstResponder() }
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        if view.text != text { view.text = text }
        view.textColor = textColor
        view.tintColor = tintColor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: max(height, 20))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            if text.wrappedValue != textView.text { text.wrappedValue = textView.text }
        }
    }
}
#endif
