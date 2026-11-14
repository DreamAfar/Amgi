//
//  ImageOcclusionTypes.swift
//  AnkiKit
//

public import Foundation

/// An image occlusion note as the backend returns it for editing.
public struct ImageOcclusionNoteData: Sendable, Equatable {
    public var imageData: Data
    public var imageName: String
    /// One entry per cloze ordinal. An entry with several shapes is a group;
    /// ordinal 0 holds text labels, which never become cards.
    public var occlusions: [ImageOcclusionData]
    public var header: String
    public var backExtra: String
    public var tags: [String]
    /// "Hide all, guess one": every shape carries `oi=1`.
    public var occludeInactive: Bool

    public init(
        imageData: Data,
        imageName: String,
        occlusions: [ImageOcclusionData],
        header: String,
        backExtra: String,
        tags: [String],
        occludeInactive: Bool
    ) {
        self.imageData = imageData
        self.imageName = imageName
        self.occlusions = occlusions
        self.header = header
        self.backExtra = backExtra
        self.tags = tags
        self.occludeInactive = occludeInactive
    }
}

/// The shapes that share one cloze ordinal.
public struct ImageOcclusionData: Sendable, Equatable {
    public var ordinal: Int
    public var shapes: [ImageOcclusionShapeData]

    public init(ordinal: Int, shapes: [ImageOcclusionShapeData]) {
        self.ordinal = ordinal
        self.shapes = shapes
    }
}

/// One stored shape: its type ("rect", "ellipse", "polygon", "text") and
/// its `key=value` properties, already unescaped by the backend.
public struct ImageOcclusionShapeData: Sendable, Equatable {
    public var kind: String
    public var properties: [ImageOcclusionProperty]

    public init(kind: String, properties: [ImageOcclusionProperty]) {
        self.kind = kind
        self.properties = properties
    }
}

public struct ImageOcclusionProperty: Sendable, Equatable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}
