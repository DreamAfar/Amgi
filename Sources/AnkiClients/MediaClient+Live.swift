import AnkiBackend
public import Dependencies
import DependenciesMacros
import Foundation

extension MediaClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            localURL: { filename in
                backend.currentMediaFolderURL?
                    .appendingPathComponent(filename, isDirectory: false)
            },
            save: { data, filename in
                try backend.addMediaFile(data: data, desiredName: filename)
            },
            delete: { filename in
                try backend.trashMediaFiles([filename])
            }
        )
    }()
}
