//
//  ReviewInputMonitor.swift
//  ReviewFeature
//

package import AppCore
import Foundation
import GameController

/// Game controller and hardware keyboard input for the reviewer, through
/// the GameController framework.
///
/// Keys come from `GCKeyboard` rather than `UIKeyCommand` or `.keyboardShortcut`:
/// those only reach the first responder's chain, and the card's web view takes
/// first responder as soon as it's tapped, after which shortcuts went dead
/// until the screen was reopened.
///
/// Everything here is global to the app, so `stop()` must run when the
/// reviewer goes away — a handler left behind kept answering cards from the
/// deck list.
@MainActor
final class ReviewInputMonitor {
    enum Input: Equatable {
        case button(ReviewGamepadButton)
        case key(ReviewKeyChord)
    }

    /// A press, already on the main actor.
    var onInput: ((Input) -> Void)?
    /// Points to scroll the card by, while a thumbstick is held.
    var onScroll: ((Double) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var stickY: Float = 0
    private var stickValues: [Float] = [0, 0]
    private var scrollTask: Task<Void, Never>?

    /// Below this a thumbstick is resting, not pushed: worn sticks drift.
    private static let deadzone: Float = 0.25
    /// Points per tick at full deflection; ticks run at about 60 Hz.
    private static let scrollSpeed: Double = 22

    func start() {
        stop()
        // The notifications are posted on the main queue; rescanning rather
        // than taking the controller out of the notification keeps a
        // non-Sendable GCController from crossing into the main actor.
        for name in [Notification.Name.GCControllerDidConnect, .GCKeyboardDidConnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.connect() }
            })
        }
        connect()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        scrollTask?.cancel()
        scrollTask = nil
        stickY = 0
        stickValues = [0, 0]
        for controller in GCController.controllers() {
            Self.clearHandlers(controller)
        }
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
    }

    private func connect() {
        for controller in GCController.controllers() {
            configure(controller)
        }
        configureKeyboard()
    }

    // MARK: Controller

    private func configure(_ controller: GCController) {
        // AnkiMobile needs the extended profile too: a micro gamepad (a Siri
        // remote, a one-handed pad) has too few buttons to review with.
        guard let pad = controller.extendedGamepad else { return }
        controller.handlerQueue = .main
        let buttons: [(GCControllerButtonInput?, ReviewGamepadButton)] = [
            (pad.buttonA, .a), (pad.buttonB, .b), (pad.buttonX, .x), (pad.buttonY, .y),
            (pad.dpad.up, .dpadUp), (pad.dpad.down, .dpadDown),
            (pad.dpad.left, .dpadLeft), (pad.dpad.right, .dpadRight),
            (pad.leftShoulder, .leftShoulder), (pad.rightShoulder, .rightShoulder),
            (pad.leftTrigger, .leftTrigger), (pad.rightTrigger, .rightTrigger),
            (pad.leftThumbstickButton, .leftThumbstick), (pad.rightThumbstickButton, .rightThumbstick),
            (pad.buttonMenu, .menu), (pad.buttonOptions, .options),
        ]
        for (input, button) in buttons {
            // `pressedChangedHandler`, not `valueChangedHandler`: a trigger is
            // analog, and its value handler fired dozens of times per pull.
            input?.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated { self?.onInput?(.button(button)) }
            }
        }
        // Either stick scrolls, as in AnkiMobile; the one pushed further wins.
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, _, y in
            MainActor.assumeIsolated { self?.stickMoved(y, stick: 0) }
        }
        pad.rightThumbstick.valueChangedHandler = { [weak self] _, _, y in
            MainActor.assumeIsolated { self?.stickMoved(y, stick: 1) }
        }
    }

    private static func clearHandlers(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let inputs: [GCControllerButtonInput?] = [
            pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY,
            pad.dpad.up, pad.dpad.down, pad.dpad.left, pad.dpad.right,
            pad.leftShoulder, pad.rightShoulder, pad.leftTrigger, pad.rightTrigger,
            pad.leftThumbstickButton, pad.rightThumbstickButton, pad.buttonMenu, pad.buttonOptions,
        ]
        for input in inputs { input?.pressedChangedHandler = nil }
        pad.leftThumbstick.valueChangedHandler = nil
        pad.rightThumbstick.valueChangedHandler = nil
    }

    private func stickMoved(_ y: Float, stick: Int) {
        stickValues[stick] = y
        let strongest = stickValues.max { abs($0) < abs($1) } ?? 0
        stickY = abs(strongest) < Self.deadzone ? 0 : strongest
        guard stickY != 0, scrollTask == nil else { return }
        scrollTask = Task { @MainActor [weak self] in
            while let self, self.stickY != 0, !Task.isCancelled {
                let push = Double((abs(self.stickY) - Self.deadzone) / (1 - Self.deadzone))
                // Up on the stick is positive y, and scrolls toward the top.
                let direction: Double = self.stickY > 0 ? -1 : 1
                self.onScroll?(direction * push * Self.scrollSpeed)
                try? await Task.sleep(for: .milliseconds(16))
            }
            self?.scrollTask = nil
        }
    }

    // MARK: Keyboard

    private func configureKeyboard() {
        guard let device = GCKeyboard.coalesced, let keyboard = device.keyboardInput else { return }
        device.handlerQueue = .main
        keyboard.keyChangedHandler = { [weak self] input, _, keyCode, pressed in
            guard pressed else { return }
            let usage = Int(keyCode.rawValue)
            guard !ReviewKeyChord.modifierKeys.contains(usage) else { return }
            let chord = ReviewKeyChord(key: usage, modifiers: Self.modifiers(of: input))
            MainActor.assumeIsolated { self?.onInput?(.key(chord)) }
        }
    }

    nonisolated static func modifiers(of keyboard: GCKeyboardInput) -> ReviewKeyChord.Modifiers {
        func held(_ left: GCKeyCode, _ right: GCKeyCode) -> Bool {
            (keyboard.button(forKeyCode: left)?.isPressed ?? false)
                || (keyboard.button(forKeyCode: right)?.isPressed ?? false)
        }
        var modifiers: ReviewKeyChord.Modifiers = []
        if held(.leftControl, .rightControl) { modifiers.insert(.control) }
        if held(.leftAlt, .rightAlt) { modifiers.insert(.option) }
        if held(.leftShift, .rightShift) { modifiers.insert(.shift) }
        if held(.leftGUI, .rightGUI) { modifiers.insert(.command) }
        return modifiers
    }
}

/// Captures the next key pressed, for adding a shortcut in settings.
@MainActor
package final class ReviewKeyRecorder {
    private var onKey: ((ReviewKeyChord) -> Void)?
    private var observer: NSObjectProtocol?

    package init() {}

    package func start(_ onKey: @escaping (ReviewKeyChord) -> Void) {
        stop()
        self.onKey = onKey
        attach()
        observer = NotificationCenter.default.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.attach() }
        }
    }

    package func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        onKey = nil
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
    }

    private func attach() {
        guard let device = GCKeyboard.coalesced, let keyboard = device.keyboardInput else { return }
        device.handlerQueue = .main
        keyboard.keyChangedHandler = { [weak self] input, _, keyCode, pressed in
            guard pressed else { return }
            let usage = Int(keyCode.rawValue)
            guard !ReviewKeyChord.modifierKeys.contains(usage) else { return }
            let chord = ReviewKeyChord(key: usage, modifiers: ReviewInputMonitor.modifiers(of: input))
            MainActor.assumeIsolated { self?.onKey?(chord) }
        }
    }

    /// Whether a hardware keyboard is connected now.
    package static var isKeyboardConnected: Bool { GCKeyboard.coalesced != nil }

    /// The connected controllers that can be used, by name.
    package static var controllerNames: [String] {
        GCController.controllers()
            .filter { $0.extendedGamepad != nil }
            .map { $0.vendorName ?? String(localized: "Game Controller", bundle: .module) }
    }
}
