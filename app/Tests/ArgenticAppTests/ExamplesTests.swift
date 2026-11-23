import ArgenticCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Argentic
#if os(macOS)
import AppKit
#endif

final class ExamplesTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ArgenticExamples-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeSmallExample(in directory: URL) throws -> BundledExample {
        var p = FractalParameters()
        p.formula = 47
        p.render = 4
        p.maxIterations = 4
        p.blend = 4
        let url = directory.appendingPathComponent("small_example.loo")
        try LooFile.serialize(p).write(to: url, atomically: true, encoding: .utf8)
        let preview = directory.appendingPathComponent("small_example.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8,
            bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(preview as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return BundledExample(url: url, previewURL: preview)
    }

    func testBundledStartupPresetUsesAuthoritativeLoo() throws {
        let example = try XCTUnwrap(ExampleCatalog.bundled.first { $0.id == "example1.loo" })
        XCTAssertEqual(example.title, "Example 1")
        let expected = try LooFile.parse(String(contentsOf: example.url, encoding: .utf8))
        XCTAssertEqual(try example.parameters(), expected)
        XCTAssertEqual(ExampleCatalog.startupParameters, expected)
        XCTAssertFalse(expected.fitAspect)
    }

    @MainActor
    func testFreshDefaultsStartFromExampleAndSavedGroupsOverrideOnlyTheirOwnValues() throws {
        let suite = "ArgenticExampleStartup.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = FractalModel(defaults: defaults)
        XCTAssertEqual(model.parameters, ExampleCatalog.startupParameters)
        XCTAssertNil(model.image, "The main view should render the preset, not load its PNG")
        model.savedSettingGroups = [.colour]
        model.parameters.blend = 8
        model.parameters.formula = 1
        model.parameters.viewport = .default
        var expected = ExampleCatalog.startupParameters
        expected.blend = 8
        XCTAssertEqual(FractalModel(defaults: defaults).parameters, expected)
    }

    func testDiscoveryIsAutomaticNaturallySortedAndMatchesCompanionPNGCaseInsensitively() throws {
        let directory = try temporaryDirectory()
        let source = try XCTUnwrap(ExampleCatalog.bundled.first).url
        let data = try Data(contentsOf: source)
        for name in ["example10.loo", "example2.LOO", ".hidden.loo"] {
            try data.write(to: directory.appendingPathComponent(name))
        }
        try Data().write(to: directory.appendingPathComponent("EXAMPLE2.PNG"))
        try Data().write(to: directory.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("folder.loo"), withIntermediateDirectories: false)
        let examples = ExampleCatalog.examples(in: directory)
        XCTAssertEqual(examples.map(\.id), ["example2.LOO", "example10.loo"])
        XCTAssertEqual(examples.first?.previewURL?.lastPathComponent, "EXAMPLE2.PNG")
        XCTAssertNil(examples.last?.previewURL)
        XCTAssertEqual(try examples[1].parameters().width, FractalParameters().width)
        XCTAssertTrue(ExampleCatalog.examples(in: directory.appendingPathComponent("missing")).isEmpty)
    }

    @MainActor
    func testChoosingExampleRendersItClearsZoomHistoryAndKeepsAppPreferences() async throws {
        let example = try writeSmallExample(in: temporaryDirectory())
        let model = FractalModel(defaults: nil)
        model.renderingBackend = .cpu
        model.parameters.width = 32
        model.parameters.height = 24
        model.parameters.antiAlias = 2
        model.parameters.maxIterations = 4
        model.showInspector = true
        model.clickZoomBehavior = .centerClickedPoint
        model.smallZoomStep = .ten
        model.draw()
        try await waitForRender(model)
        model.zoom(atImagePoint: CGPoint(x: 8, y: 6), factor: 2)
        try await waitForRender(model)
        XCTAssertTrue(model.canGoBack)
        model.selection = CGRect(x: 2, y: 2, width: 12, height: 12)
        model.chooseExample(example)
        try await waitForRender(model)
        var expected = try example.parameters()
        expected.width = 32
        expected.height = 24
        expected.antiAlias = 2
        XCTAssertEqual(model.parameters, expected)
        XCTAssertEqual(model.image?.width, 32)
        XCTAssertEqual(model.image?.height, 24)
        XCTAssertEqual(model.progress, 1)
        XCTAssertFalse(model.canGoBack)
        XCTAssertNil(model.selection)
        XCTAssertEqual(model.renderingBackend, .cpu)
        XCTAssertTrue(model.showInspector)
        XCTAssertEqual(model.clickZoomBehavior, .centerClickedPoint)
        XCTAssertEqual(model.smallZoomStep, .ten)
    }

    func testCompanionPNGDoesNotOverrideExampleOutputSettings() throws {
        let example = try writeSmallExample(in: temporaryDirectory())
        let p = try example.parameters()
        XCTAssertNotNil(example.previewURL)
        XCTAssertEqual(p.width, FractalParameters().width)
        XCTAssertEqual(p.height, FractalParameters().height)
    }

    func testClassicMandelbrotPresetUsesCorrectFormulaAndNaturalCoordinates() throws {
        let example = try XCTUnwrap(ExampleCatalog.bundled.first {
            (try? $0.parameters().formula) == classicMandelbrotFormulaID
        })
        let p = try example.parameters()
        XCTAssertEqual(p.formula, classicMandelbrotFormulaID)
        XCTAssertEqual(p.render, 1)
        XCTAssertEqual(p.maxIterations, 256)
        XCTAssertEqual(p.blend, 1)
        XCTAssertEqual(p.coordinateFlag, 0)
        XCTAssertEqual(p.orbitTransform, 0)
        XCTAssertFalse(p.juliaMode)
        XCTAssertFalse(p.insideOut)
        XCTAssertTrue(p.fitAspect)
        XCTAssertEqual(p.viewport, .default)
        XCTAssertEqual(ExampleCatalog.startupParameters.formula, try ExampleCatalog.bundled.first { $0.id == "example1.loo" }?.parameters().formula)
    }

    @MainActor
    func testInvalidExampleDoesNotReplaceTheCurrentParameters() throws {
        let url = try temporaryDirectory().appendingPathComponent("broken.loo")
        try "Not a Sterling file".write(to: url, atomically: true, encoding: .utf8)
        let model = FractalModel(defaults: nil)
        let before = model.parameters
        model.chooseExample(BundledExample(url: url, previewURL: nil))
        XCTAssertEqual(model.parameters, before)
        XCTAssertNotNil(model.message)
        XCTAssertFalse(model.isRendering)
    }

    @MainActor
    private func waitForRender(_ model: FractalModel) async throws {
        let deadline = Date().addingTimeInterval(15)
        while model.isRendering && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isRendering)
        XCTAssertNotNil(model.image)
    }

    #if os(macOS)
    @MainActor
    func testExamplesMenuContainsBundledPresets() throws {
        let menu = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "Examples" }?.submenu)
        for example in ExampleCatalog.bundled {
            let item = try XCTUnwrap(menu.items.first { $0.title == example.title })
            XCTAssertNotNil(item.action)
        }
    }
    #endif
}
