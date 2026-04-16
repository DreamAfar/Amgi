public import Dependencies
import DependenciesMacros

@DependencyClient
public struct ImageOcclusionClient: Sendable {
    /// Copies the image at the given URL into the Anki media folder and creates
    /// an image occlusion note with the provided mask occlusions string.
    public var addNote: @Sendable (
        _ imageURL: URL,
        _ occlusions: String,
        _ header: String,
        _ backExtra: String,
        _ tags: [String]
    ) throws -> Void

    /// Ensures the image-occlusion notetype exists in the collection.
    /// Safe to call multiple times — Anki skips creation if it already exists.
    public var ensureNotetype: @Sendable () throws -> Void

    /// Fetches an existing image occlusion note for editing.
    /// Returns (imageData, imageName, occlusions, header, backExtra, tags).
    public var getNote: @Sendable (_ noteId: Int64) throws -> ImageOcclusionNoteData

    /// Updates an existing image occlusion note.
    public var updateNote: @Sendable (
        _ noteId: Int64,
        _ occlusions: String,
        _ header: String,
        _ backExtra: String,
        _ tags: [String]
    ) throws -> Void
}

public struct ImageOcclusionNoteData: Sendable {
    public var imageData: Data
    public var imageName: String
    public var occlusions: String
    public var header: String
    public var backExtra: String
    public var tags: [String]
}

extension ImageOcclusionClient: TestDependencyKey {
    public static let testValue = ImageOcclusionClient()
}

extension DependencyValues {
    public var imageOcclusionClient: ImageOcclusionClient {
        get { self[ImageOcclusionClient.self] }
        set { self[ImageOcclusionClient.self] = newValue }
    }
}
