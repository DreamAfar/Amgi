//
//  ReviewInputSettingsView.swift
//  SettingsFeature
//

import SwiftUI
import AppCore
import Theme
import UI
import Sharing
import ReviewFeature
import Combine
import GameController

// MARK: - Shared pieces

/// Every action, grouped as `ReviewInputAction.groups` orders them, for a
/// picker's options.
private struct ReviewInputActionOptions: View {
    var body: some View {
        ForEach(Array(ReviewInputAction.groups.enumerated()), id: \.offset) { _, group in
            Section {
                ForEach(group) { action in
                    Text(action.title).tag(action)
                }
            }
        }
    }
}

/// The Question / Answer switch at the top of each page: every input can do
/// one thing on each side, as in AnkiMobile.
private struct ReviewInputSidePicker: View {
    @Binding var side: ReviewInputSide

    var body: some View {
        Picker(String(localized: "Card side", bundle: .module), selection: $side) {
            ForEach(ReviewInputSide.allCases) { side in
                Text(side.title).tag(side)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, AmgiSpacing.lg)
        .padding(.top, AmgiSpacing.lg)
    }
}

/// A stored map as an editable value: decoded from its JSON in user defaults,
/// falling back to the defaults until first changed.
private struct StoredInputMap {
    let shared: Shared<String>
    let fallback: ReviewInputMap

    var map: ReviewInputMap { ReviewInputMap(json: shared.wrappedValue, default: fallback) }

    func binding(for input: String, side: ReviewInputSide) -> Binding<ReviewInputAction> {
        Binding(
            get: { map.action(for: input, side: side) },
            set: { action in
                var map = map
                map.set(action, for: input, side: side)
                save(map)
            }
        )
    }

    func save(_ map: ReviewInputMap) {
        shared.withLock { $0 = map.json }
    }
}

// MARK: - Gestures

struct ReviewGestureSettingsView: View {
    @Shared(.appStorage(ReviewPreferences.Keys.gestureMap)) private var gestureMap: String = ""
    @Shared(.appStorage(ReviewPreferences.Keys.doubleTapPrevention))
    private var doubleTapPrevention: Int = ReviewDoubleTapPrevention.normal.rawValue
    @State private var side: ReviewInputSide = .question
    @Environment(\.palette) private var palette

    private var stored: StoredInputMap { StoredInputMap(shared: $gestureMap, fallback: .defaultGestures) }

    var body: some View {
        SettingsPage {
            ReviewInputSidePicker(side: $side)

            SettingsSectionHeader(title: String(localized: "Tap Zones", bundle: .module))
            SettingsGroup {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<3, id: \.self) { row in
                        GridRow {
                            ForEach(0..<3, id: \.self) { column in
                                zoneCell(ReviewGesture.tap(zone: row * 3 + column))
                            }
                        }
                    }
                }
            }
            SettingsFootnote(String(localized: "The card is split into nine zones. With tap to look up on, tapping a word still looks it up; links, buttons and audio keep working.", bundle: .module))

            SettingsSectionHeader(title: String(localized: "Swipes", bundle: .module))
            SettingsGroup {
                ForEach(Array(ReviewGesture.SwipeDirection.allCases.enumerated()), id: \.offset) { index, direction in
                    if index > 0 { SettingsSeparator() }
                    SettingsPickerRow(
                        title: ReviewGesture.swipe(direction).title,
                        systemImage: Self.symbol(direction),
                        tone: .accent,
                        selection: stored.binding(for: ReviewGesture.swipe(direction).id, side: side)
                    ) {
                        ReviewInputActionOptions()
                    }
                }
            }
            SettingsFootnote(String(localized: "Swipe up or down starting at the left or right edge of the screen; elsewhere a vertical drag scrolls the card.", bundle: .module))

            SettingsSectionHeader(title: String(localized: "Options", bundle: .module))
            SettingsGroup {
                SettingsPickerRow(
                    title: String(localized: "Double tap prevention", bundle: .module),
                    systemImage: "hand.tap",
                    tone: .info,
                    selection: Binding($doubleTapPrevention)
                ) {
                    ForEach(ReviewDoubleTapPrevention.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            }
            SettingsFootnote(String(localized: "Ignores a tap that comes right after the card turns over, so a quick double tap doesn't show the answer and grade it at once.", bundle: .module))

            ReviewInputResetGroup(
                presetTitle: String(localized: "Use AnkiMobile Defaults", bundle: .module),
                onPreset: { stored.save(.ankiMobileGestures) },
                onClear: { stored.save(ReviewInputMap()) }
            )
        }
        .navigationTitle(String(localized: "Gestures", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func zoneCell(_ gesture: ReviewGesture) -> some View {
        let selection = stored.binding(for: gesture.id, side: side)
        let action = selection.wrappedValue
        return Menu {
            Picker(gesture.title, selection: selection) {
                ReviewInputActionOptions()
            }
        } label: {
            VStack(spacing: AmgiSpacing.xxs) {
                Text(gesture.title)
                    .amgiFont(.micro)
                    .foregroundStyle(palette.textTertiary)
                Text(action == .none ? "—" : action.title)
                    .amgiFont(.captionBold)
                    .foregroundStyle(action == .none ? palette.textTertiary : palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(AmgiSpacing.xs)
            .contentShape(Rectangle())
        }
        .overlay {
            Rectangle().stroke(palette.separator, lineWidth: 0.5)
        }
        .accessibilityLabel(gesture.title)
        .accessibilityValue(action.title)
    }

    private static func symbol(_ direction: ReviewGesture.SwipeDirection) -> String {
        switch direction {
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .up: "arrow.up"
        case .down: "arrow.down"
        }
    }
}

// MARK: - Game controller

struct ReviewGamepadSettingsView: View {
    @Shared(.appStorage(ReviewPreferences.Keys.gamepadMap)) private var gamepadMap: String = ""
    @State private var side: ReviewInputSide = .question
    @State private var controllers: [String] = []

    private var stored: StoredInputMap { StoredInputMap(shared: $gamepadMap, fallback: .defaultGamepad) }

    var body: some View {
        SettingsPage {
            ReviewInputSidePicker(side: $side)

            SettingsSectionHeader(title: String(localized: "Controller", bundle: .module))
            SettingsGroup {
                SettingsValueRow(
                    title: String(localized: "Connected", bundle: .module),
                    value: controllers.isEmpty
                        ? String(localized: "None", bundle: .module)
                        : controllers.joined(separator: ", "),
                    systemImage: "gamecontroller",
                    tone: .review,
                    isMuted: controllers.isEmpty
                )
            }
            SettingsFootnote(String(localized: "Needs a controller iOS supports with a full button layout, such as an Xbox, PlayStation or 8BitDo controller in its Xbox or macOS mode. The thumbsticks always scroll the card.", bundle: .module))

            SettingsSectionHeader(title: String(localized: "Buttons", bundle: .module))
            SettingsGroup {
                ForEach(Array(ReviewGamepadButton.allCases.enumerated()), id: \.offset) { index, button in
                    if index > 0 { SettingsSeparator() }
                    SettingsPickerRow(
                        title: button.title,
                        systemImage: Self.symbol(button),
                        tone: .neutral,
                        selection: stored.binding(for: button.id, side: side)
                    ) {
                        ReviewInputActionOptions()
                    }
                }
            }

            ReviewInputResetGroup(
                presetTitle: String(localized: "Restore Defaults", bundle: .module),
                onPreset: { stored.save(.defaultGamepad) },
                onClear: { stored.save(ReviewInputMap()) }
            )
        }
        .navigationTitle(String(localized: "Game Controller", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { controllers = ReviewKeyRecorder.controllerNames }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in
            controllers = ReviewKeyRecorder.controllerNames
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in
            controllers = ReviewKeyRecorder.controllerNames
        }
    }

    private static func symbol(_ button: ReviewGamepadButton) -> String {
        switch button {
        case .a: "a.circle"
        case .b: "b.circle"
        case .x: "x.circle"
        case .y: "y.circle"
        case .dpadUp: "dpad.up.filled"
        case .dpadDown: "dpad.down.filled"
        case .dpadLeft: "dpad.left.filled"
        case .dpadRight: "dpad.right.filled"
        case .leftShoulder: "l1.rectangle.roundedbottom"
        case .rightShoulder: "r1.rectangle.roundedbottom"
        case .leftTrigger: "l2.rectangle.roundedtop"
        case .rightTrigger: "r2.rectangle.roundedtop"
        case .leftThumbstick: "l.joystick.press.down"
        case .rightThumbstick: "r.joystick.press.down"
        case .menu: "line.3.horizontal.circle"
        case .options: "ellipsis.circle"
        }
    }
}

// MARK: - Keyboard

struct ReviewKeyboardSettingsView: View {
    @Shared(.appStorage(ReviewPreferences.Keys.keyboardMap)) private var keyboardMap: String = ""
    @State private var side: ReviewInputSide = .question
    @State private var isRecording = false

    private var stored: StoredInputMap { StoredInputMap(shared: $keyboardMap, fallback: .defaultKeyboard) }

    /// This side's shortcuts, in key order.
    private var chords: [ReviewKeyChord] {
        stored.map[side].keys
            .compactMap(ReviewKeyChord.init(id:))
            .sorted { ($0.modifiers.rawValue, $0.key) < ($1.modifiers.rawValue, $1.key) }
    }

    var body: some View {
        SettingsPage {
            ReviewInputSidePicker(side: $side)

            SettingsSectionHeader(title: String(localized: "Shortcuts", bundle: .module))
            SettingsGroup {
                ForEach(Array(chords.enumerated()), id: \.element.id) { index, chord in
                    if index > 0 { SettingsSeparator() }
                    SettingsPickerRow(
                        title: chord.title,
                        systemImage: "keyboard",
                        tone: .neutral,
                        selection: stored.binding(for: chord.id, side: side)
                    ) {
                        ReviewInputActionOptions()
                    }
                }
                if !chords.isEmpty { SettingsSeparator() }
                SettingsButtonRow(
                    title: String(localized: "Add Shortcut", bundle: .module),
                    systemImage: "plus",
                    tone: .accent
                ) {
                    isRecording = true
                }
            }
            SettingsFootnote(String(localized: "Set a shortcut to None to remove it. Shortcuts work with any hardware keyboard, including keyboard-mode remotes, and pause while you type an answer.", bundle: .module))

            ReviewInputResetGroup(
                presetTitle: String(localized: "Restore Anki Shortcuts", bundle: .module),
                onPreset: { stored.save(.defaultKeyboard) },
                onClear: { stored.save(ReviewInputMap()) }
            )
        }
        .navigationTitle(String(localized: "Keyboard", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isRecording) {
            ReviewKeyRecordingSheet(side: side) { chord, action in
                var map = stored.map
                map.set(action, for: chord.id, side: side)
                stored.save(map)
            }
        }
    }
}

/// "Press a key", then an action for it.
private struct ReviewKeyRecordingSheet: View {
    let side: ReviewInputSide
    let onSave: (ReviewKeyChord, ReviewInputAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 44
    @State private var recorder = ReviewKeyRecorder()
    @State private var chord: ReviewKeyChord?
    @State private var action: ReviewInputAction = .showAnswer

    var body: some View {
        NavigationStack {
            VStack(spacing: AmgiSpacing.lg) {
                Spacer()
                Image(systemName: "keyboard")
                    .font(.system(size: glyphSize))
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                if let chord {
                    Text(chord.title)
                        .amgiFont(.sectionHeading)
                        .foregroundStyle(palette.textPrimary)
                    Picker(String(localized: "Action", bundle: .module), selection: $action) {
                        ReviewInputActionOptions()
                    }
                    .pickerStyle(.menu)
                    Text("Press another key to change it.", bundle: .module)
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    Text("Press a key on your keyboard", bundle: .module)
                        .amgiFont(.bodyEmphasis)
                        .foregroundStyle(palette.textPrimary)
                    Text(ReviewKeyRecorder.isKeyboardConnected
                         ? String(localized: "Modifiers such as ⌘ and ⌃ can be held with it.", bundle: .module)
                         : String(localized: "No hardware keyboard is connected.", bundle: .module))
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .multilineTextAlignment(.center)
            .padding(AmgiSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(palette.background)
            .navigationTitle(side == .question
                             ? String(localized: "Shortcut on the Question", bundle: .module)
                             : String(localized: "Shortcut on the Answer", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", bundle: .module)) {
                        if let chord { onSave(chord, action) }
                        dismiss()
                    }
                    .disabled(chord == nil || action == .none)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { recorder.start { chord = $0 } }
        .onDisappear { recorder.stop() }
    }
}

// MARK: - Reset

private struct ReviewInputResetGroup: View {
    let presetTitle: String
    let onPreset: () -> Void
    let onClear: () -> Void

    @State private var confirmClear = false

    var body: some View {
        SettingsSectionHeader(title: String(localized: "Reset", bundle: .module))
        SettingsGroup {
            SettingsButtonRow(title: presetTitle, systemImage: "arrow.counterclockwise", tone: .accent, action: onPreset)
            SettingsSeparator()
            SettingsButtonRow(
                title: String(localized: "Clear All", bundle: .module),
                systemImage: "trash",
                tone: .danger,
                isDestructive: true
            ) {
                confirmClear = true
            }
        }
        .confirmationDialog(
            String(localized: "Clear every mapping on both sides?", bundle: .module),
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear All", bundle: .module), role: .destructive, action: onClear)
        }
    }
}

#if DEBUG
#Preview("Gestures") {
    NavigationStack { ReviewGestureSettingsView() }
}

#Preview("Keyboard") {
    NavigationStack { ReviewKeyboardSettingsView() }
}
#endif
