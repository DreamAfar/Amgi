import Foundation
import UniformTypeIdentifiers

enum CardAssetPath {
    static let scheme = "amgi-asset"
    static let cardBaseURL = URL(string: "amgi-asset://card/")!
    static let mediaBaseURL = URL(string: "amgi-asset://media/")!
    static let mathJaxScriptURLString = "amgi-asset://assets/mathjax/tex-svg.js"

    static func mediaBaseTag() -> String {
        #"<base href="amgi-asset://media/">"#
    }

    static func resolve(url: URL, mediaRoot: URL?, bundleRoot: URL?) -> URL? {
        guard url.scheme?.lowercased() == scheme,
              let host = url.host?.lowercased() else {
            return nil
        }

        let relativePath = normalizedRelativePath(from: url)
        switch host {
        case "media":
            guard let mediaRoot else { return nil }
            return resolved(root: mediaRoot, relativePath: relativePath)
        case "assets":
            guard let bundleRoot, relativePath.hasPrefix("mathjax/") else { return nil }
            return resolved(root: bundleRoot, relativePath: relativePath)
        default:
            return nil
        }
    }

    static func mimeType(for fileURL: URL) -> String {
        if let type = UTType(filenameExtension: fileURL.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }

        switch fileURL.pathExtension.lowercased() {
        case "js":
            return "application/javascript"
        case "css":
            return "text/css"
        case "svg":
            return "image/svg+xml"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        default:
            return "application/octet-stream"
        }
    }

    private static func normalizedRelativePath(from url: URL) -> String {
        var path = url.path(percentEncoded: true)
        if path.hasPrefix("/") {
            path.removeFirst()
        }
        return path.removingPercentEncoding ?? path
    }

    private static func resolved(root: URL, relativePath: String) -> URL? {
        guard !relativePath.isEmpty else { return nil }

        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = rootURL
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let candidatePath = candidate.path
        guard candidatePath == rootURL.path || candidatePath.hasPrefix(rootPath) else {
            return nil
        }

        return candidate
    }
}