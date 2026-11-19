//
//  ReviewInputMapping.swift
//  AppCore
//

public import Foundation

// MARK: - Actions

/// Something a tap, swipe, controller button or key can do while reviewing —
/// AnkiMobile's study actions, plus its User Actions that call a function the
/// card's template defines (`var userJs1 = revealNext;`).
public enum ReviewInputAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case none
    case showAnswer
    case again, hard, good, easy
    case undo
    case replayAudio
    case stopAudio
    case scrollUp, scrollDown
    case lookUp
    case editNote
    case editTemplate
    case mark
    case flag1, flag2, flag3, flag4, flag5, flag6, flag7
    case buryCard, buryNote
    case suspendCard, suspendNote
    case close
    case userAction1, userAction2, userAction3, userAction4, userAction5
    case userAction6, userAction7, userAction8, userAction9

    public var id: String { rawValue }

    /// The flag a flag action toggles, 1–7.
    public var flag: UInt32? {
        switch self {
        case .flag1: 1
        case .flag2: 2
        case .flag3: 3
        case .flag4: 4
        case .flag5: 5
        case .flag6: 6
        case .flag7: 7
        default: nil
        }
    }

    /// The template function a User Action calls: `userJs1` … `userJs9`.
    public var userAction: Int? {
        switch self {
        case .userAction1: 1
        case .userAction2: 2
        case .userAction3: 3
        case .userAction4: 4
        case .userAction5: 5
        case .userAction6: 6
        case .userAction7: 7
        case .userAction8: 8
        case .userAction9: 9
        default: nil
        }
    }

    public var title: String {
        if let flag {
            return String(localized: "Flag \(CardFlag.name(flag))", bundle: .module)
        }
        if let userAction {
            return String(localized: "User Action \(userAction)", bundle: .module)
        }
        switch self {
        case .none: return String(localized: "None", bundle: .module)
        case .showAnswer: return String(localized: "Show Answer", bundle: .module)
        case .again: return String(localized: "Again", bundle: .module)
        case .hard: return String(localized: "Hard", bundle: .module)
        case .good: return String(localized: "Good", bundle: .module)
        case .easy: return String(localized: "Easy", bundle: .module)
        case .undo: return String(localized: "Undo", bundle: .module)
        case .replayAudio: return String(localized: "Replay Audio", bundle: .module)
        case .stopAudio: return String(localized: "Stop Audio", bundle: .module)
        case .scrollUp: return String(localized: "Scroll Up", bundle: .module)
        case .scrollDown: return String(localized: "Scroll Down", bundle: .module)
        case .lookUp: return String(localized: "Look Up", bundle: .module)
        case .editNote: return String(localized: "Edit Note", bundle: .module)
        case .editTemplate: return String(localized: "Edit Template", bundle: .module)
        case .mark: return String(localized: "Mark Note", bundle: .module)
        case .buryCard: return String(localized: "Bury Card", bundle: .module)
        case .buryNote: return String(localized: "Bury Note", bundle: .module)
        case .suspendCard: return String(localized: "Suspend Card", bundle: .module)
        case .suspendNote: return String(localized: "Suspend Note", bundle: .module)
        case .close: return String(localized: "Close Review", bundle: .module)
        default: return rawValue
        }
    }

    /// The actions in the order a picker lists them, in groups.
    public static let groups: [[ReviewInputAction]] = [
        [.none],
        [.showAnswer, .again, .hard, .good, .easy],
        [.undo, .replayAudio, .stopAudio, .scrollUp, .scrollDown, .lookUp, .close],
        [.editNote, .editTemplate, .mark, .buryCard, .buryNote, .suspendCard, .suspendNote],
        [.flag1, .flag2, .flag3, .flag4, .flag5, .flag6, .flag7],
        [.userAction1, .userAction2, .userAction3, .userAction4, .userAction5,
         .userAction6, .userAction7, .userAction8, .userAction9],
    ]
}

/// Which side of the card is showing: as in AnkiMobile, every input can do one
/// thing on the question and another on the answer.
public enum ReviewInputSide: String, CaseIterable, Codable, Sendable, Identifiable {
    case question, answer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .question: String(localized: "Question", bundle: .module)
        case .answer: String(localized: "Answer", bundle: .module)
        }
    }
}

// MARK: - Map

/// Input → action, for each side of the card. Inputs are named by string
/// (`ReviewGesture.id`, `ReviewGamepadButton.rawValue`, `ReviewKeyChord.id`) so
/// one type stores all three kinds, and an input this version doesn't know
/// survives a round trip.
public struct ReviewInputMap: Codable, Equatable, Sendable {
    public var question: [String: ReviewInputAction]
    public var answer: [String: ReviewInputAction]

    public init(question: [String: ReviewInputAction] = [:], answer: [String: ReviewInputAction] = [:]) {
        self.question = question
        self.answer = answer
    }

    public subscript(side: ReviewInputSide) -> [String: ReviewInputAction] {
        get { side == .question ? question : answer }
        set {
            if side == .question { question = newValue } else { answer = newValue }
        }
    }

    public func action(for input: String, side: ReviewInputSide) -> ReviewInputAction {
        self[side][input] ?? .none
    }

    /// Sets an input's action; `.none` removes it, so a cleared input takes no
    /// room and doesn't fall back to a default.
    public mutating func set(_ action: ReviewInputAction, for input: String, side: ReviewInputSide) {
        if action == .none {
            self[side].removeValue(forKey: input)
        } else {
            self[side][input] = action
        }
    }

    // MARK: Storage

    /// The map as stored in user defaults; an empty string means "never set",
    /// so the caller's default applies.
    public var json: String {
        guard let data = try? JSONEncoder.sorted.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public init(json: String, default fallback: ReviewInputMap) {
        guard !json.isEmpty,
              let map = try? JSONDecoder().decode(ReviewInputMap.self, from: Data(json.utf8)) else {
            self = fallback
            return
        }
        self = map
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}

public extension ReviewPreferences.Keys {
    static let gestureMap = "review_pref_input_gesture_map"
    static let gamepadMap = "review_pref_input_gamepad_map"
    static let keyboardMap = "review_pref_input_keyboard_map"
    static let doubleTapPrevention = "review_pref_input_double_tap_prevention"
}

// MARK: - Gestures

/// A tap in one of nine zones of the card, or a swipe, as AnkiMobile divides
/// the study screen.
public enum ReviewGesture: Hashable, Sendable, Identifiable {
    /// Zones count left to right, top to bottom: 0 is top left, 8 bottom right.
    case tap(zone: Int)
    case swipe(SwipeDirection)

    public enum SwipeDirection: String, CaseIterable, Sendable {
        case left, right, up, down
    }

    public static let zones = Array(0..<9)

    public var id: String {
        switch self {
        case .tap(let zone): "tap.\(zone)"
        case .swipe(let direction): "swipe.\(direction.rawValue)"
        }
    }

    public var title: String {
        switch self {
        case .tap(let zone):
            Self.zoneTitles[min(max(zone, 0), 8)]
        case .swipe(.left): String(localized: "Swipe Left", bundle: .module)
        case .swipe(.right): String(localized: "Swipe Right", bundle: .module)
        case .swipe(.up): String(localized: "Swipe Up", bundle: .module)
        case .swipe(.down): String(localized: "Swipe Down", bundle: .module)
        }
    }

    private static var zoneTitles: [String] {
        [
            String(localized: "Top Left", bundle: .module), String(localized: "Top", bundle: .module),
            String(localized: "Top Right", bundle: .module), String(localized: "Left", bundle: .module),
            String(localized: "Center", bundle: .module), String(localized: "Right", bundle: .module),
            String(localized: "Bottom Left", bundle: .module), String(localized: "Bottom", bundle: .module),
            String(localized: "Bottom Right", bundle: .module),
        ]
    }
}

public extension ReviewInputMap {
    /// Gestures start empty: tapping a card looked words up before gestures
    /// existed, and an update shouldn't start answering cards on a tap.
    static let defaultGestures = ReviewInputMap()

    /// AnkiMobile's defaults: on the question a tap anywhere shows the answer;
    /// on the answer the left third is Again and the right third Good, with
    /// the middle left alone.
    static let ankiMobileGestures: ReviewInputMap = {
        var map = ReviewInputMap()
        for zone in ReviewGesture.zones {
            map.set(.showAnswer, for: ReviewGesture.tap(zone: zone).id, side: .question)
            switch zone % 3 {
            case 0: map.set(.again, for: ReviewGesture.tap(zone: zone).id, side: .answer)
            case 2: map.set(.good, for: ReviewGesture.tap(zone: zone).id, side: .answer)
            default: break
            }
        }
        return map
    }()
}

/// How long after the card changes side a tap is ignored, so a quick double
/// tap doesn't show the answer and then answer it. AnkiMobile's "Double Tap
/// Prevention".
public enum ReviewDoubleTapPrevention: Int, CaseIterable, Sendable, Identifiable {
    case off = 0
    case short = 250
    case normal = 500
    case long = 1000

    public var id: Int { rawValue }

    public var interval: Duration { .milliseconds(rawValue) }

    public var title: String {
        switch self {
        case .off: String(localized: "Off", bundle: .module)
        case .short: String(localized: "Short", bundle: .module)
        case .normal: String(localized: "Normal", bundle: .module)
        case .long: String(localized: "Long", bundle: .module)
        }
    }
}

// MARK: - Game controller

/// The buttons of an extended game controller. The thumbsticks aren't here:
/// as in AnkiMobile, they always scroll the card.
public enum ReviewGamepadButton: String, CaseIterable, Sendable, Identifiable {
    case a, b, x, y
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case leftShoulder, rightShoulder
    case leftTrigger, rightTrigger
    case leftThumbstick, rightThumbstick
    case menu, options

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .dpadUp: String(localized: "D-pad Up", bundle: .module)
        case .dpadDown: String(localized: "D-pad Down", bundle: .module)
        case .dpadLeft: String(localized: "D-pad Left", bundle: .module)
        case .dpadRight: String(localized: "D-pad Right", bundle: .module)
        case .leftShoulder: String(localized: "Left Shoulder", bundle: .module)
        case .rightShoulder: String(localized: "Right Shoulder", bundle: .module)
        case .leftTrigger: String(localized: "Left Trigger", bundle: .module)
        case .rightTrigger: String(localized: "Right Trigger", bundle: .module)
        case .leftThumbstick: String(localized: "Left Stick Press", bundle: .module)
        case .rightThumbstick: String(localized: "Right Stick Press", bundle: .module)
        case .menu: String(localized: "Menu", bundle: .module)
        case .options: String(localized: "Options", bundle: .module)
        }
    }
}

public extension ReviewInputMap {
    /// A controller is only ever connected on purpose, so it works out of the
    /// box: A shows the answer and then answers Good, the face buttons answer,
    /// the shoulders undo and replay, the d-pad scrolls.
    static let defaultGamepad: ReviewInputMap = {
        var map = ReviewInputMap()
        for side in ReviewInputSide.allCases {
            map.set(.undo, for: ReviewGamepadButton.leftShoulder.id, side: side)
            map.set(.replayAudio, for: ReviewGamepadButton.rightShoulder.id, side: side)
            map.set(.scrollUp, for: ReviewGamepadButton.dpadUp.id, side: side)
            map.set(.scrollDown, for: ReviewGamepadButton.dpadDown.id, side: side)
        }
        map.set(.showAnswer, for: ReviewGamepadButton.a.id, side: .question)
        map.set(.showAnswer, for: ReviewGamepadButton.b.id, side: .question)
        map.set(.good, for: ReviewGamepadButton.a.id, side: .answer)
        map.set(.again, for: ReviewGamepadButton.b.id, side: .answer)
        map.set(.hard, for: ReviewGamepadButton.x.id, side: .answer)
        map.set(.easy, for: ReviewGamepadButton.y.id, side: .answer)
        return map
    }()
}

// MARK: - Keyboard

/// A key with any modifiers held, by USB HID usage — what `GCKeyCode` holds —
/// so the model needs no GameController import.
public struct ReviewKeyChord: Hashable, Sendable, Identifiable {
    public var key: Int
    public var modifiers: Modifiers

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public init(key: Int, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Stored form: `"<modifiers>:<usage>"`, e.g. `"8:29"` for ⌘Z.
    public var id: String { "\(modifiers.rawValue):\(key)" }

    public init?(id: String) {
        let parts = id.split(separator: ":")
        guard parts.count == 2, let mods = Int(parts[0]), let key = Int(parts[1]) else { return nil }
        self.init(key: key, modifiers: Modifiers(rawValue: mods))
    }

    /// Keys that are modifiers themselves, which can't be a shortcut alone.
    public static let modifierKeys: ClosedRange<Int> = 0xE0...0xE7

    /// "⌃⌥⇧⌘" then the key, as macOS menus write shortcuts.
    public var title: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Self.keyName(key)
    }

    public static func keyName(_ usage: Int) -> String {
        switch usage {
        case 0x04...0x1D: return String(UnicodeScalar(UInt8(65 + usage - 0x04)))
        case 0x1E...0x26: return String(usage - 0x1D)
        case 0x27: return "0"
        case 0x28: return String(localized: "Return", bundle: .module)
        case 0x29: return "Esc"
        case 0x2A: return "⌫"
        case 0x2B: return "⇥"
        case 0x2C: return String(localized: "Space", bundle: .module)
        case 0x2D: return "-"
        case 0x2E: return "="
        case 0x2F: return "["
        case 0x30: return "]"
        case 0x31: return "\\"
        case 0x33: return ";"
        case 0x34: return "'"
        case 0x35: return "`"
        case 0x36: return ","
        case 0x37: return "."
        case 0x38: return "/"
        case 0x3A...0x45: return "F\(usage - 0x39)"
        case 0x4A: return "↖"
        case 0x4B: return "⇞"
        case 0x4C: return "⌦"
        case 0x4D: return "↘"
        case 0x4E: return "⇟"
        case 0x4F: return "→"
        case 0x50: return "←"
        case 0x51: return "↓"
        case 0x52: return "↑"
        default: return String(format: "0x%02X", usage)
        }
    }

    // Usages the defaults use.
    public static let space = 0x2C
    public static let returnKey = 0x28
    public static func digit(_ value: Int) -> Int { value == 0 ? 0x27 : 0x1D + value }
    public static func letter(_ value: Character) -> Int {
        Int(value.uppercased().unicodeScalars.first!.value) - 65 + 0x04
    }
}

public extension ReviewInputMap {
    /// Anki's desktop shortcuts, which AnkiMobile keeps: Space or Return shows
    /// the answer and then answers Good, 1–4 answer, R replays, E edits, ⌃1–7
    /// flag, * marks, - buries, @ suspends, ⌘Z undoes.
    static let defaultKeyboard: ReviewInputMap = {
        var map = ReviewInputMap()
        let space = ReviewKeyChord(key: ReviewKeyChord.space).id
        let enter = ReviewKeyChord(key: ReviewKeyChord.returnKey).id
        map.set(.showAnswer, for: space, side: .question)
        map.set(.showAnswer, for: enter, side: .question)
        map.set(.good, for: space, side: .answer)
        map.set(.good, for: enter, side: .answer)
        let ratings: [ReviewInputAction] = [.again, .hard, .good, .easy]
        for (index, rating) in ratings.enumerated() {
            map.set(rating, for: ReviewKeyChord(key: ReviewKeyChord.digit(index + 1)).id, side: .answer)
        }
        var common: [(chord: ReviewKeyChord, action: ReviewInputAction)] = [
            (ReviewKeyChord(key: ReviewKeyChord.letter("r")), .replayAudio),
            (ReviewKeyChord(key: ReviewKeyChord.letter("e")), .editNote),
            (ReviewKeyChord(key: ReviewKeyChord.letter("z"), modifiers: .command), .undo),
            (ReviewKeyChord(key: ReviewKeyChord.digit(8), modifiers: .shift), .mark),
            (ReviewKeyChord(key: 0x2D), .buryCard),
            (ReviewKeyChord(key: ReviewKeyChord.digit(2), modifiers: .shift), .suspendCard),
        ]
        let flags: [ReviewInputAction] = [.flag1, .flag2, .flag3, .flag4, .flag5, .flag6, .flag7]
        for (index, flag) in flags.enumerated() {
            common.append((ReviewKeyChord(key: ReviewKeyChord.digit(index + 1), modifiers: .control), flag))
        }
        for side in ReviewInputSide.allCases {
            for item in common {
                map.set(item.action, for: item.chord.id, side: side)
            }
        }
        return map
    }()
}
