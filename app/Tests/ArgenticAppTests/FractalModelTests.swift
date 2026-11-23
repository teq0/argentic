import XCTest
import ArgenticCore
import ImageIO
@testable import Argentic

final class FractalModelTests: XCTestCase {
    @MainActor
    private func renderedModel() async throws -> FractalModel {
        let model = FractalModel(defaults: nil)
        model.parameters.width = 32
        model.parameters.height = 24
        model.parameters.maxIterations = 8
        model.draw()
        try await waitForRender(model)
        XCTAssertNotNil(model.image)
        return model
    }

    @MainActor
    private func waitForRender(_ model: FractalModel) async throws {
        let deadline = Date().addingTimeInterval(30)
        while model.isRendering && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isRendering, "Render timed out")
    }

    @MainActor
    func testClickZoomBackRestoresExactViewsInOrder() async throws {
        let model = try await renderedModel()
        model.parameters.viewport.xMin = -2.123456789012345
        model.draw()
        try await waitForRender(model)
        let original = model.parameters.viewport
        let originalRendered = model.renderedViewport
        XCTAssertFalse(model.canGoBack)

        model.zoom(atImagePoint: CGPoint(x: 9, y: 7), factor: 2)
        try await waitForRender(model)
        let firstZoom = model.parameters.viewport
        let firstRendered = model.renderedViewport
        XCTAssertTrue(model.canGoBack)

        model.zoom(atImagePoint: CGPoint(x: 21, y: 16), factor: 2)
        try await waitForRender(model)
        model.parameters.colors.offset = [3, 7, 11]
        model.goBack()
        try await waitForRender(model)
        XCTAssertEqual(model.parameters.viewport, firstZoom)
        XCTAssertEqual(model.renderedViewport, firstRendered)

        model.goBack()
        try await waitForRender(model)
        XCTAssertEqual(model.parameters.viewport, original)
        XCTAssertEqual(model.renderedViewport, originalRendered)
        XCTAssertEqual(model.parameters.colors.offset, [3, 7, 11])
        XCTAssertFalse(model.canGoBack)
        model.goBack()
        XCTAssertEqual(model.parameters.viewport, original)
    }

    @MainActor
    func testRectangleAndZoomOutAlsoRecordHistory() async throws {
        let model = try await renderedModel()
        model.clickZoomBehavior = .centerClickedPoint
        model.parameters.fitAspect = false
        model.draw()
        try await waitForRender(model)
        let original = model.renderedViewport

        model.selection = CGRect(x: 3, y: 4, width: 17, height: 11)
        model.zoomToSelection()
        try await waitForRender(model)
        let rectangle = model.renderedViewport
        XCTAssertNil(model.selection)

        model.zoom(atImagePoint: CGPoint(x: 8, y: 10), factor: 0.5)
        try await waitForRender(model)
        model.goBack()
        try await waitForRender(model)
        XCTAssertEqual(model.renderedViewport, rectangle)
        model.goBack()
        try await waitForRender(model)
        XCTAssertEqual(model.renderedViewport, original)
        XCTAssertFalse(model.parameters.fitAspect)
    }

    @MainActor
    func testInvalidAndInProgressZoomsDoNotAddHistory() async throws {
        let model = try await renderedModel()
        let original = model.parameters.viewport
        for factor in [0, -1, 1, .infinity, .nan] {
            model.zoom(atImagePoint: .zero, factor: factor)
        }
        model.selection = CGRect(x: 0, y: 0, width: 1, height: 1)
        model.zoomToSelection()
        model.isRendering = true
        model.zoom(atImagePoint: .zero, factor: 2)
        model.isRendering = false
        XCTAssertFalse(model.canGoBack)
        XCTAssertEqual(model.parameters.viewport, original)
    }

    @MainActor
    func testResetAndJuliaModeClearHistory() async throws {
        let model = try await renderedModel()
        model.zoom(atImagePoint: CGPoint(x: 9, y: 7), factor: 2)
        try await waitForRender(model)
        model.resetCoordinates()
        try await waitForRender(model)
        XCTAssertFalse(model.canGoBack)

        model.zoom(atImagePoint: CGPoint(x: 9, y: 7), factor: 2)
        try await waitForRender(model)
        model.setJuliaMode(true)
        try await waitForRender(model)
        XCTAssertFalse(model.canGoBack)
    }

    @MainActor
    func testOpeningParametersClearsHistory() async throws {
        let model = try await renderedModel()
        let data = model.parametersData()
        model.zoom(atImagePoint: CGPoint(x: 9, y: 7), factor: 2)
        try await waitForRender(model)
        XCTAssertTrue(model.canGoBack)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        model.open(urls: [url])
        try await waitForRender(model)
        XCTAssertFalse(model.canGoBack)
    }

    @MainActor
    func testPNGAndJPEGEmbedExactSettingsAndReopenForZooming() async throws {
        let model = try await renderedModel()
        model.parameters.viewport.xMin = -2.123456789012345
        model.parameters.title1 = "Fractal <settings> & café 🌈"
        model.parameters.antiAlias = 2
        model.parameters.colors.offset = [3, 7, 11]
        model.draw()
        try await waitForRender(model)
        let expected = model.parameters

        for format in [ImageFormat.png, .jpeg] {
            let data = try XCTUnwrap(model.imageData(as: format))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(ImageSettings.parameters(from: source), expected, "\(format)")

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).image")
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let reopened = FractalModel(defaults: nil)
            reopened.open(urls: [url])
            XCTAssertNotNil(reopened.image)
            XCTAssertTrue(reopened.pictureHasParameters)
            XCTAssertEqual(reopened.parameters, expected)
            XCTAssertFalse(reopened.isRendering, "Opening must preserve the saved picture")
            reopened.zoom(atImagePoint: CGPoint(x: 9, y: 7), factor: 2)
            try await waitForRender(reopened)
            XCTAssertTrue(reopened.canGoBack)
            reopened.goBack()
            try await waitForRender(reopened)
            XCTAssertEqual(reopened.parameters, expected)
        }
    }

    @MainActor
    func testExportUsesDisplayedSettingsNotUnappliedEdits() async throws {
        let model = try await renderedModel()
        // Let the final asynchronous recolour settle before making un-applied edits.
        try await Task.sleep(for: .milliseconds(100))
        let expected = model.parameters
        model.parameters.viewport = .default.zoomed(about: (x: 0, y: 0), factor: 8)
        model.parameters.formula = 1
        model.parameters.width = 100
        let data = try XCTUnwrap(model.imageData(as: .png))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(ImageSettings.parameters(from: source), expected)
    }

    @MainActor
    func testPlainPicturesDoNotAcquireInventedSettings() async throws {
        let model = try await renderedModel()
        let data = try XCTUnwrap(model.imageData(as: .bmp))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).bmp")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let reopened = FractalModel(defaults: nil)
        reopened.open(urls: [url])
        XCTAssertFalse(reopened.pictureHasParameters)
        XCTAssertFalse(reopened.canZoom)
        reopened.smallZoom(inward: true)
        XCTAssertFalse(reopened.canGoBack)
        let png = try XCTUnwrap(reopened.imageData(as: .png))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        XCTAssertNil(ImageSettings.parameters(from: source))
    }

    @MainActor
    func testSmallZoomStepsKeepCentreAndWorkWithBackHistory() async throws {
        for step in SmallZoomStep.allCases {
            for behavior in ClickZoomBehavior.allCases {
                let model = try await renderedModel()
                model.smallZoomStep = step
                model.clickZoomBehavior = behavior
                model.zoomMode = .rectangle
                model.selection = CGRect(x: 3, y: 4, width: 12, height: 10)
                let original = model.parameters.viewport
                let view = model.renderedViewport
                XCTAssertTrue(model.canZoom)

                model.smallZoom(inward: true)
                try await waitForRender(model)
                let zoomed = model.parameters.viewport
                let zoomedView = model.renderedViewport
                XCTAssertEqual(zoomedView.width, view.width / step.factor, accuracy: 1e-12)
                XCTAssertEqual(zoomedView.height, view.height / step.factor, accuracy: 1e-12)
                XCTAssertEqual((zoomedView.xMin + zoomedView.xMax) / 2, (view.xMin + view.xMax) / 2, accuracy: 1e-12)
                XCTAssertEqual((zoomedView.yMin + zoomedView.yMax) / 2, (view.yMin + view.yMax) / 2, accuracy: 1e-12)
                XCTAssertNil(model.selection)

                model.smallZoom(inward: false)
                try await waitForRender(model)
                XCTAssertEqual(model.renderedViewport.width, view.width, accuracy: 1e-12)
                XCTAssertEqual(model.renderedViewport.height, view.height, accuracy: 1e-12)
                model.goBack()
                try await waitForRender(model)
                XCTAssertEqual(model.parameters.viewport, zoomed)
                model.goBack()
                try await waitForRender(model)
                XCTAssertEqual(model.parameters.viewport, original)
                XCTAssertFalse(model.canGoBack)
            }
        }
    }

    @MainActor
    func testSmallZoomDoesNothingWithoutAnImageOrWhileRendering() async throws {
        let empty = FractalModel(defaults: nil)
        XCTAssertFalse(empty.canZoom)
        empty.smallZoom(inward: true)
        XCTAssertFalse(empty.canGoBack)

        let model = try await renderedModel()
        let original = model.parameters.viewport
        model.isRendering = true
        XCTAssertFalse(model.canZoom)
        model.smallZoom(inward: true)
        model.smallZoom(inward: false)
        model.isRendering = false
        XCTAssertEqual(model.parameters.viewport, original)
        XCTAssertFalse(model.canGoBack)
    }

    @MainActor
    func testClickZoomBehaviorsForZoomInAndOut() async throws {
        for behavior in ClickZoomBehavior.allCases {
            for factor in [2.0, 0.5] {
                let model = try await renderedModel()
                model.clickZoomBehavior = behavior
                let original = model.parameters.viewport
                let viewport = model.renderedViewport
                let point = CGPoint(x: 8, y: 6)
                let x = viewport.xMin + viewport.width * 0.25
                let y = viewport.yMin + viewport.height * 0.25

                model.zoom(atImagePoint: point, factor: factor)
                try await waitForRender(model)
                let zoomed = model.renderedViewport
                XCTAssertEqual(zoomed.width, viewport.width / factor, accuracy: 1e-12)
                XCTAssertEqual(zoomed.height, viewport.height / factor, accuracy: 1e-12)
                switch behavior {
                case .keepPosition:
                    XCTAssertEqual((x - zoomed.xMin) / zoomed.width, 0.25, accuracy: 1e-12)
                    XCTAssertEqual((y - zoomed.yMin) / zoomed.height, 0.25, accuracy: 1e-12)
                case .centerClickedPoint:
                    XCTAssertEqual((zoomed.xMin + zoomed.xMax) / 2, x, accuracy: 1e-12)
                    XCTAssertEqual((zoomed.yMin + zoomed.yMax) / 2, y, accuracy: 1e-12)
                }
                model.goBack()
                try await waitForRender(model)
                XCTAssertEqual(model.parameters.viewport, original)
            }
        }
    }

    @MainActor
    func testClickZoomPreferencePersistsBetweenModels() throws {
        let suite = "ArgenticTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = FractalModel(defaults: defaults)
        XCTAssertEqual(model.clickZoomBehavior, .centerClickedPoint)
        model.clickZoomBehavior = .centerClickedPoint
        XCTAssertEqual(FractalModel(defaults: defaults).clickZoomBehavior, .centerClickedPoint)
        model.clickZoomBehavior = .keepPosition
        XCTAssertEqual(FractalModel(defaults: defaults).clickZoomBehavior, .keepPosition)
        defaults.set("unknown-future-value", forKey: "clickZoomBehavior")
        XCTAssertEqual(FractalModel(defaults: defaults).clickZoomBehavior, .keepPosition)
    }

    @MainActor
    func testMissingAndInvalidLegacyClickPreferencesDefaultToCenter() throws {
        let suite = "ArgenticDefaultClickZoom.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(FractalModel(defaults: nil).clickZoomBehavior, .centerClickedPoint)
        XCTAssertEqual(FractalModel(defaults: defaults).clickZoomBehavior, .centerClickedPoint)
        defaults.set("unknown-future-value", forKey: "clickZoomBehavior")
        XCTAssertEqual(FractalModel(defaults: defaults).clickZoomBehavior, .centerClickedPoint)

        let model = FractalModel(defaults: nil)
        let data = try JSONEncoder().encode(SavedAppSettings(model: model, groups: [.zoom]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "clickZoomBehavior")
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "savedAppSettings")
        XCTAssertEqual(FractalModel(defaults: defaults).clickZoomBehavior, .centerClickedPoint)
    }

    @MainActor
    func testSwitchingBetweenCPUAndMetalPreservesParametersAndZoomHistory() async throws {
        let model = try await renderedModel()
        let original = model.parameters
        model.setUseMetal(false)
        try await waitForRender(model)
        XCTAssertEqual(model.renderingBackend, .cpu)
        XCTAssertEqual(model.parameters, original)
        XCTAssertNotNil(model.image)
        model.zoom(atImagePoint: CGPoint(x: 9, y: 7), factor: 2)
        try await waitForRender(model)
        XCTAssertTrue(model.canGoBack)
        model.setUseMetal(true)
        try await waitForRender(model)
        XCTAssertEqual(model.renderingBackend, .metal)
        model.goBack()
        try await waitForRender(model)
        XCTAssertEqual(model.parameters, original)
    }

    @MainActor
    func testExplicitParametersOverrideEmbeddedSettingsInEitherSelectionOrder() async throws {
        let model = try await renderedModel()
        let data = try XCTUnwrap(model.imageData(as: .png))
        let pictureURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        let settingsURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        try data.write(to: pictureURL)
        var override = model.parameters
        override.formula = 1
        try JSONEncoder().encode(override).write(to: settingsURL)
        defer {
            try? FileManager.default.removeItem(at: pictureURL)
            try? FileManager.default.removeItem(at: settingsURL)
        }
        for urls in [[pictureURL, settingsURL], [settingsURL, pictureURL]] {
            let reopened = FractalModel(defaults: nil)
            reopened.open(urls: urls)
            XCTAssertEqual(reopened.parameters, override)
            XCTAssertTrue(reopened.pictureHasParameters)
        }
    }
}
