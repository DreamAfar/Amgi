import AnkiBackend
import AnkiProto

func fetchNotetype(
    backend: AnkiBackend,
    id: Int64
) throws -> Anki_Notetypes_Notetype {
    var request = Anki_Notetypes_NotetypeId()
    request.ntid = id
    return try backend.invoke(
        service: AnkiBackend.Service.notetypes,
        method: AnkiBackend.NotetypesMethod.getNotetype,
        request: request
    )
}

func loadStandardNotetypeEntries(
    backend: AnkiBackend
) throws -> [(id: Int64, name: String)] {
    let response: Anki_Notetypes_NotetypeNames = try backend.invoke(
        service: AnkiBackend.Service.notetypes,
        method: AnkiBackend.NotetypesMethod.getNotetypeNames
    )

    return response.entries.compactMap { entry in
        guard let notetype = try? fetchNotetype(backend: backend, id: entry.id) else {
            return (id: entry.id, name: entry.name)
        }
        guard !notetype.isImageOcclusionNotetype else {
            return nil
        }
        return (id: entry.id, name: entry.name)
    }
}

extension Anki_Notetypes_Notetype {
    var isImageOcclusionNotetype: Bool {
        config.originalStockKind == .imageOcclusion
    }
}