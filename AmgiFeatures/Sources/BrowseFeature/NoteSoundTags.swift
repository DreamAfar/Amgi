//
//  NoteSoundTags.swift
//  BrowseFeature
//

import Foundation

/// `[sound:…]` references in a field, in order, without duplicates.
enum NoteSoundTags {
    static func filenames(in field: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        var rest = field[...]
        while let open = rest.range(of: "[sound:") {
            let after = rest[open.upperBound...]
            guard let close = after.firstIndex(of: "]") else { break }
            let name = String(after[..<close]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, seen.insert(name).inserted { result.append(name) }
            rest = after[after.index(after: close)...]
        }
        return result
    }

    static func appending(_ filename: String, to field: String) -> String {
        let marker = "[sound:\(filename)]"
        return field.isEmpty ? marker : field + " " + marker
    }
}
