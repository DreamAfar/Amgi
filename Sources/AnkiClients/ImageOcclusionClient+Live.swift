import AnkiBackend
import AnkiProto
public import Dependencies
import Foundation
import SwiftProtobuf

extension ImageOcclusionClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            addNote: { imageURL, occlusions, header, backExtra, tags in
                // 1. Ensure the notetype exists
                _ = try backend.call(
                    service: AnkiBackend.Service.imageOcclusion,
                    method: AnkiBackend.ImageOcclusionMethod.addImageOcclusionNotetype
                )

                // 2. Copy the image to the media folder
                let mediaPath = try copyImageToMedia(imageURL: imageURL)

                // 3. Add the note
                var req = Anki_ImageOcclusion_AddImageOcclusionNoteRequest()
                req.imagePath = mediaPath
                req.occlusions = occlusions
                req.header = header
                req.backExtra = backExtra
                req.tags = tags
                try backend.callVoid(
                    service: AnkiBackend.Service.imageOcclusion,
                    method: AnkiBackend.ImageOcclusionMethod.addImageOcclusionNote,
                    request: req
                )
            },

            ensureNotetype: {
                _ = try backend.call(
                    service: AnkiBackend.Service.imageOcclusion,
                    method: AnkiBackend.ImageOcclusionMethod.addImageOcclusionNotetype
                )
            },

            getNote: { noteId in
                var req = Anki_ImageOcclusion_GetImageOcclusionNoteRequest()
                req.noteID = noteId
                let resp: Anki_ImageOcclusion_GetImageOcclusionNoteResponse = try backend.call(
                    service: AnkiBackend.Service.imageOcclusion,
                    method: AnkiBackend.ImageOcclusionMethod.getImageOcclusionNote,
                    request: req
                )
                guard case .note(let note) = resp.value else {
                    throw ImageOcclusionError.noteNotFound
                }
                // Reconstruct occlusions string from structured shapes
                let occlusions = note.occlusions.enumerated().map { (i, occ) -> String in
                    let n = occ.ordinal > 0 ? Int(occ.ordinal) : (i + 1)
                    guard let shape = occ.shapes.first else { return "" }
                    let props = Dictionary(uniqueKeysWithValues: shape.properties.map { ($0.name, $0.value) })
                    switch shape.shape {
                    case "ellipse":
                        let l = props["left"] ?? "0"
                        let t = props["top"] ?? "0"
                        let rx = props["rx"] ?? "0"
                        let ry = props["ry"] ?? "0"
                        return "{{c\(n)::image-occlusion:ellipse:left=\(l):top=\(t):rx=\(rx):ry=\(ry)}}"
                    case "polygon":
                        let pts = props["points"] ?? ""
                        return "{{c\(n)::image-occlusion:polygon:points=\(pts)}}"
                    default:
                        let l = props["left"] ?? "0"
                        let t = props["top"] ?? "0"
                        let w = props["width"] ?? "0"
                        let h = props["height"] ?? "0"
                        return "{{c\(n)::image-occlusion:rect:left=\(l):top=\(t):width=\(w):height=\(h)}}"
                    }
                }.filter { !$0.isEmpty }.joined(separator: "\n")

                return ImageOcclusionNoteData(
                    imageData: note.imageData,
                    imageName: note.imageFileName,
                    occlusions: occlusions,
                    header: note.header,
                    backExtra: note.backExtra,
                    tags: note.tags
                )
            },

            updateNote: { noteId, occlusions, header, backExtra, tags in
                var req = Anki_ImageOcclusion_UpdateImageOcclusionNoteRequest()
                req.noteID = noteId
                req.occlusions = occlusions
                req.header = header
                req.backExtra = backExtra
                req.tags = tags
                try backend.callVoid(
                    service: AnkiBackend.Service.imageOcclusion,
                    method: AnkiBackend.ImageOcclusionMethod.updateImageOcclusionNote,
                    request: req
                )
            }
        )
    }()
}

// MARK: - Private helpers

private func copyImageToMedia(imageURL: URL) throws -> String {
    guard let mediaDir = currentMediaDirectoryURL() else {
        throw ImageOcclusionError.noMediaDirectory
    }

    let ext = imageURL.pathExtension.isEmpty ? "jpg" : imageURL.pathExtension
    let filename = "io_\(Int(Date().timeIntervalSince1970)).\(ext)"
    let dest = mediaDir.appendingPathComponent(filename)

    if !FileManager.default.fileExists(atPath: mediaDir.path) {
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
    }

    if !FileManager.default.fileExists(atPath: dest.path) {
        try FileManager.default.copyItem(at: imageURL, to: dest)
    }

    return filename
}

private func currentMediaDirectoryURL() -> URL? {
    let selectedUser = UserDefaults.standard.string(forKey: "amgi.selectedUser") ?? "用户1"
    guard let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first else { return nil }

    let userFolder = sanitizedFolderName(selectedUser)
    return appSupport
        .appendingPathComponent("AnkiCollection", isDirectory: true)
        .appendingPathComponent(userFolder, isDirectory: true)
        .appendingPathComponent("media", isDirectory: true)
}

private func sanitizedFolderName(_ user: String) -> String {
    let trimmed = user.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "default" }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let mapped = trimmed.unicodeScalars.map { scalar -> Character in
        allowed.contains(scalar) ? Character(scalar) : "_"
    }
    let folder = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return folder.isEmpty ? "default" : folder
}

// MARK: - Error

enum ImageOcclusionError: Error {
    case noMediaDirectory
    case noteNotFound
}
