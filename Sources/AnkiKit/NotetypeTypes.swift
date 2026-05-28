public struct NotetypeInfo: Sendable, Equatable, Hashable, Codable {
    public let id: Int64
    public let name: String
    public let fieldNames: [String]

    public init(id: Int64, name: String, fieldNames: [String]) {
        self.id = id
        self.name = name
        self.fieldNames = fieldNames
    }
}

public struct NotetypeFieldInfo: Sendable, Equatable, Hashable, Codable {
    public let name: String
    public let ordinal: Int
    public let fontName: String
    public let fontSize: Int

    public init(name: String, ordinal: Int, fontName: String, fontSize: Int) {
        self.name = name
        self.ordinal = ordinal
        self.fontName = fontName
        self.fontSize = fontSize
    }
}