//
//  ReviewInputController.swift
//  ReviewFeature
//

import AppCore
import SwiftUI
import WebKit

/// Turns taps, swipes, controller buttons and keys into review actions, by
/// the maps set in Settings › Review. Resolution only: the reviewer performs
/// the action, since it owns the session, the card menu and the sheets.
@MainActor
final class ReviewInputController {
    var gestures = ReviewInputMap.defaultGestures
    var gamepad = ReviewInputMap.defaultGamepad
    var keyboard = ReviewInputMap.defaultKeyboard
    var doubleTapPrevention = ReviewDoubleTapPrevention.normal

    /// Which side is showing, read at the moment of the input.
    var side: () -> ReviewInputSide = { .question }
    /// Whether the reviewer takes input now: not while a sheet, alert or
    /// menu prompt is up.
    var acceptsInput: () -> Bool = { true }
    /// Whether keys may act: not while a text field is taking them.
    var acceptsKeys: () -> Bool = { true }
    var perform: (ReviewInputAction) -> Void = { _ in }

    private let monitor = ReviewInputMonitor()
    private var sideChangedAt = ContinuousClock.now - .seconds(60)

    func start(commands: ReviewCardCommands) {
        monitor.onInput = { [weak self] input in self?.handle(input) }
        monitor.onScroll = { [weak self, weak commands] points in
            guard self?.acceptsInput() == true else { return }
            commands?.scroll(by: points, animated: false)
        }
        monitor.start()
    }

    func stop() {
        monitor.stop()
        monitor.onInput = nil
        monitor.onScroll = nil
    }

    /// The card turned over or a new one came up.
    func sideChanged() {
        sideChangedAt = .now
    }

    /// A gesture from the card: `"tap.<zone>"` or `"swipe.<direction>"`.
    func gesture(_ id: String) {
        guard acceptsInput() else { return }
        // A second tap right after the card turns over is the first tap
        // landing twice, not a decision about the answer.
        if id.hasPrefix("tap."), doubleTapPrevention != .off,
           ContinuousClock.now - sideChangedAt < doubleTapPrevention.interval {
            return
        }
        run(gestures.action(for: id, side: side()))
    }

    private func handle(_ input: ReviewInputMonitor.Input) {
        guard acceptsInput() else { return }
        switch input {
        case .button(let button):
            run(gamepad.action(for: button.id, side: side()))
        case .key(let chord):
            guard acceptsKeys() else { return }
            run(keyboard.action(for: chord.id, side: side()))
        }
    }

    private func run(_ action: ReviewInputAction) {
        guard action != .none else { return }
        perform(action)
    }
}

/// Requests the reviewer sends to the card on screen: scrolling and User
/// Actions. Imperative rather than through view state, because a held
/// thumbstick scrolls sixty times a second and a SwiftUI update would
/// coalesce all but the last.
@MainActor
final class ReviewCardCommands {
    weak var webView: WKWebView?

    func scroll(by points: Double, animated: Bool) {
        guard let scrollView = webView?.scrollView else { return }
        let top = -scrollView.adjustedContentInset.top
        let bottom = max(top, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let y = min(max(scrollView.contentOffset.y + points, top), bottom)
        guard y != scrollView.contentOffset.y else { return }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: animated)
    }

    /// Most of a screen, leaving a few lines of overlap to read on from.
    func scrollPage(_ direction: Double) {
        guard let height = webView?.scrollView.bounds.height else { return }
        scroll(by: direction * height * 0.8, animated: true)
    }

    func runUserAction(_ index: Int) {
        webView?.evaluateJavaScript("window.amgiRunUserAction && window.amgiRunUserAction(\(index));")
    }
}
