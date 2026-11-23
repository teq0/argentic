import ArgenticCore
import Foundation
import SwiftUI

struct BundledExample: Identifiable, Sendable {
    let url: URL
    let previewURL: URL?

    var id: String { url.lastPathComponent }
    var title: String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "([A-Za-z])([0-9])", with: "$1 $2", options: .regularExpression)
            .localizedCapitalized
    }

    func parameters() throws -> FractalParameters {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        // Each preset starts from deterministic core defaults, not the current picture's settings.
        var p = try LooFile.parse(text, base: FractalParameters())
        // This Argentic-only preset should keep circular features circular at any output aspect.
        if p.formula == classicMandelbrotFormulaID { p.fitAspect = true }
        return p
    }
}

enum ExampleCatalog {
    static let bundled: [BundledExample] = {
        guard let directory = Bundle.main.url(forResource: "examples", withExtension: nil) else { return [] }
        return examples(in: directory)
    }()

    static let startupParameters: FractalParameters = {
        guard let first = bundled.first(where: { $0.id.lowercased() == "example1.loo" }),
              let parameters = try? first.parameters() else { return FractalParameters() }
        return parameters
    }()

    static func examples(in directory: URL) -> [BundledExample] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        let regularFiles = files.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        return regularFiles.filter { $0.pathExtension.lowercased() == "loo" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let stem = url.deletingPathExtension().lastPathComponent
                let preview = regularFiles.first {
                    $0.pathExtension.lowercased() == "png"
                        && $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(stem) == .orderedSame
                }
                return BundledExample(url: url, previewURL: preview)
            }
    }
}

struct ExamplesMenuContent: View {
    var model: FractalModel

    var body: some View {
        if ExampleCatalog.bundled.isEmpty {
            Text("No bundled examples").disabled(true)
        } else {
            ForEach(ExampleCatalog.bundled) { example in
                Button(example.title) { model.chooseExample(example) }
            }
        }
    }
}
