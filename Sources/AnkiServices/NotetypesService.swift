import AnkiBackend
import AnkiProto
public import AnkiKit
public import Dependencies
import DependenciesMacros

@DependencyClient
public struct NotetypesService: Sendable {
    public var getNotetypeNames: @Sendable () throws -> [(id: Int64, name: String)]
    public var getStandardNotetypeNames: @Sendable () throws -> [(id: Int64, name: String)]
    public var getNotetype: @Sendable (_ id: Int64) throws -> NotetypeInfo
    public var getNotetypeFields: @Sendable (_ id: Int64) throws -> [NotetypeFieldInfo]
}

extension NotetypesService: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        func loadRawNotetype(_ id: Int64) throws -> Anki_Notetypes_Notetype {
            var request = Anki_Notetypes_NotetypeId()
            request.ntid = id
            return try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: request
            )
        }

        func loadNotetypeNames() throws -> [Anki_Notetypes_NotetypeNameId] {
            let response: Anki_Notetypes_NotetypeNames = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetypeNames
            )
            return response.entries
        }

        return Self(
            getNotetypeNames: {
                try loadNotetypeNames().map { ($0.id, $0.name) }
            },
            getStandardNotetypeNames: {
                try loadNotetypeNames().compactMap { entry in
                    guard let notetype = try? loadRawNotetype(entry.id) else {
                        return (id: entry.id, name: entry.name)
                    }
                    guard notetype.config.originalStockKind != .imageOcclusion else {
                        return nil
                    }
                    return (id: entry.id, name: entry.name)
                }
            },
            getNotetype: { id in
                let notetype = try loadRawNotetype(id)
                return NotetypeInfo(
                    id: notetype.id,
                    name: notetype.name,
                    fieldNames: notetype.fields.map(\.name)
                )
            },
            getNotetypeFields: { id in
                let notetype = try loadRawNotetype(id)
                return notetype.fields.map { field in
                    NotetypeFieldInfo(
                        name: field.name,
                        ordinal: Int(field.ord.val),
                        fontName: field.config.fontName.isEmpty ? "-apple-system" : field.config.fontName,
                        fontSize: field.config.fontSize == 0 ? 18 : Int(field.config.fontSize)
                    )
                }
            }
        )
    }()
}

extension NotetypesService: TestDependencyKey {
    public static let testValue = NotetypesService()
}

extension DependencyValues {
    public var notetypesService: NotetypesService {
        get { self[NotetypesService.self] }
        set { self[NotetypesService.self] = newValue }
    }
}