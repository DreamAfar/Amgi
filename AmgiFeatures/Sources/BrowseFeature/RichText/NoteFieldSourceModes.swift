//
//  NoteFieldSourceModes.swift
//  BrowseFeature
//

import AnkiKit
import Foundation

/// Which note fields open as HTML source, per note type and field name.
/// Kept on this device only: switching a field never touches the note type,
/// so it neither syncs nor changes how Anki desktop opens the field.
@Observable
@MainActor
final class NoteFieldSourceModes {
    static let storageKey = "noteEditor.htmlSourceFields"

    private(set) var enabled: Set<String>
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    func isOn(_ notetype: NotetypeID, field: String) -> Bool {
        enabled.contains(Self.key(notetype, field: field))
    }

    func toggle(_ notetype: NotetypeID, field: String) {
        let key = Self.key(notetype, field: field)
        if enabled.remove(key) == nil { enabled.insert(key) }
        defaults.set(enabled.sorted(), forKey: Self.storageKey)
    }

    static func key(_ notetype: NotetypeID, field: String) -> String {
        "\(notetype.rawValue):\(field)"
    }
}
