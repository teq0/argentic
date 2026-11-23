import ArgenticCore
import Foundation
import ImageIO

/// Versioned JSON in a private XMP namespace. Both PNG and JPEG retain this through ImageIO.
enum ImageSettings {
    private static let namespace = "https://teq0.github.io/argentic/metadata/1.0/"
    private static let prefix = "argentic"
    private static let path = "argentic:settings"

    private struct Payload: Codable {
        let version: Int
        let parameters: FractalParameters
    }

    static func metadata(for parameters: FractalParameters) -> CGImageMetadata? {
        guard let data = try? JSONEncoder().encode(Payload(version: 1, parameters: parameters)),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let metadata = CGImageMetadataCreateMutable()
        guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace as CFString, prefix as CFString, nil),
              CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, json as CFString) else { return nil }
        return metadata
    }

    static func parameters(from source: CGImageSource) -> FractalParameters? {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
              CGImageMetadataTagCopyNamespace(tag) as String? == namespace,
              let json = CGImageMetadataTagCopyValue(tag) as? String,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)),
              payload.version == 1 else { return nil }
        return payload.parameters
    }
}
