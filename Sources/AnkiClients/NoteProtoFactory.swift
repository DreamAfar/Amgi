import AnkiKit
import AnkiProto

public enum NoteProtoFactory {
    public static func makeNote(
        from record: NoteRecord,
        fieldValues: [String]? = nil,
        tags: String? = nil
    ) -> Anki_Notes_Note {
        var note = Anki_Notes_Note()
        note.id = record.id
        note.guid = record.guid
        note.notetypeID = record.mid
        note.mtimeSecs = UInt32(clamping: record.mod)
        note.usn = record.usn
        note.fields = fieldValues ?? splitStoredFields(record.flds)
        note.tags = splitTags(tags ?? record.tags)
        return note
    }

    public static func makeUncommittedNote(
        baseNote: Anki_Notes_Note? = nil,
        notetypeId: Int64,
        fieldValues: [String],
        tags: String,
        fieldCount: Int
    ) -> Anki_Notes_Note {
        var note = baseNote ?? Anki_Notes_Note()
        note.notetypeID = notetypeId
        if baseNote == nil {
            note.usn = -1
        }
        note.fields = paddedFields(fieldValues, count: fieldCount)
        note.tags = splitTags(tags)
        return note
    }

    public static func makeEmptyUncommittedNote(
        notetypeId: Int64,
        fieldCount: Int
    ) -> Anki_Notes_Note {
        makeUncommittedNote(
            notetypeId: notetypeId,
            fieldValues: [],
            tags: "",
            fieldCount: fieldCount
        )
    }

    private static func paddedFields(_ fieldValues: [String], count: Int) -> [String] {
        var fields = Array(repeating: "", count: max(max(count, fieldValues.count), 0))
        for (index, value) in fieldValues.enumerated() where fields.indices.contains(index) {
            fields[index] = value
        }
        return fields
    }

    private static func splitStoredFields(_ storedFields: String) -> [String] {
        storedFields
            .split(separator: "\u{1f}", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func splitTags(_ tags: String) -> [String] {
        tags
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }
}
