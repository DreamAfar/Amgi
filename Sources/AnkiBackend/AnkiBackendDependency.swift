public import Dependencies

private enum AnkiBackendKey: DependencyKey {
    static let liveValue: AnkiBackend = {
        do {
            return try AnkiBackend(preferredLangs: ["en"])
        } catch {
            fatalError("Failed to initialize AnkiBackend liveValue: \(error)")
        }
    }()

    static let testValue: AnkiBackend = {
        do {
            return try AnkiBackend(preferredLangs: ["en"])
        } catch {
            fatalError("Failed to initialize AnkiBackend testValue: \(error)")
        }
    }()
}

extension DependencyValues {
    public var ankiBackend: AnkiBackend {
        get { self[AnkiBackendKey.self] }
        set { self[AnkiBackendKey.self] = newValue }
    }
}
