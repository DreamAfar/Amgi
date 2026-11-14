//
//  ChangeNotetypeTypes.swift
//  AnkiKit
//

/// What the backend reports for moving notes from one notetype to another
/// (Browse › Change Note Type), with its suggested mapping in `input`.
public struct ChangeNotetypeInfo: Sendable, Equatable {
    public var oldNotetypeName: String
    public var oldFieldNames: [String]
    public var oldTemplateNames: [String]
    public var newFieldNames: [String]
    public var newTemplateNames: [String]
    public var input: ChangeNotetypeInput

    public init(
        oldNotetypeName: String,
        oldFieldNames: [String],
        oldTemplateNames: [String],
        newFieldNames: [String],
        newTemplateNames: [String],
        input: ChangeNotetypeInput
    ) {
        self.oldNotetypeName = oldNotetypeName
        self.oldFieldNames = oldFieldNames
        self.oldTemplateNames = oldTemplateNames
        self.newFieldNames = newFieldNames
        self.newTemplateNames = newTemplateNames
        self.input = input
    }
}

/// The change to apply. `newFields[i]` is the index of the old field that
/// fills new field `i`, or nil to leave it empty; `newTemplates[i]` is the
/// old card template whose cards (and review history) become new template
/// `i`'s, or nil. Templates are ignored when the target is a cloze type.
public struct ChangeNotetypeInput: Sendable, Equatable {
    public var noteIDs: [NoteID]
    public var newFields: [Int?]
    public var newTemplates: [Int?]
    public var oldNotetypeID: NotetypeID
    public var newNotetypeID: NotetypeID
    /// The collection's schema modification time, so the backend can refuse
    /// a change prepared against an older schema.
    public var currentSchema: Int64
    public var oldNotetypeName: String
    public var isCloze: Bool

    public init(
        noteIDs: [NoteID],
        newFields: [Int?],
        newTemplates: [Int?],
        oldNotetypeID: NotetypeID,
        newNotetypeID: NotetypeID,
        currentSchema: Int64,
        oldNotetypeName: String,
        isCloze: Bool
    ) {
        self.noteIDs = noteIDs
        self.newFields = newFields
        self.newTemplates = newTemplates
        self.oldNotetypeID = oldNotetypeID
        self.newNotetypeID = newNotetypeID
        self.currentSchema = currentSchema
        self.oldNotetypeName = oldNotetypeName
        self.isCloze = isCloze
    }
}
