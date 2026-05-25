import AnkiBackend

extension AnkiBackend.CardRenderingMethod {
    static let extractAvTags: UInt32 = 3
    static let stripAvTags: UInt32 = 9
    static let renderMarkdown: UInt32 = 10
    static let encodeIriPaths: UInt32 = 11
    static let decodeIriPaths: UInt32 = 12
}
