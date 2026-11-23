import ArgenticCore
import CoreGraphics
import XCTest
@testable import Argentic

final class StartupSizingTests: XCTestCase {
    func testMacWindowUsesMostOfUsableScreenWithoutExceedingIt() {
        XCTAssertEqual(StartupSizing.windowSize(availableSize: CGSize(width: 1600, height: 1000)),
                       CGSize(width: 1440, height: 900))
        let small = StartupSizing.windowSize(availableSize: CGSize(width: 500, height: 370))
        XCTAssertLessThanOrEqual(small.width, 500)
        XCTAssertLessThanOrEqual(small.height, 370)
        XCTAssertGreaterThanOrEqual(small.width, 480)
        XCTAssertGreaterThanOrEqual(small.height, 360)
        XCTAssertEqual(StartupSizing.windowSize(availableSize: .zero), CGSize(width: 1024, height: 768))
    }

    func testInitialResolutionUsesBackingPixelsAndPreservesAspectRatio() {
        let size = StartupSizing.imageSize(availableSize: CGSize(width: 640, height: 480), displayScale: 2, aspectRatio: 4 / 3)
        XCTAssertEqual(size, CGSize(width: 1280, height: 960))
    }

    func testPhoneAndSplitViewSizingUsesActualCanvasNotWholeDevice() {
        let phone = StartupSizing.imageSize(availableSize: CGSize(width: 400, height: 600), displayScale: 3, aspectRatio: 4 / 3)
        XCTAssertEqual(phone, CGSize(width: 1200, height: 900))
        let split = StartupSizing.imageSize(availableSize: CGSize(width: 500, height: 900), displayScale: 2, aspectRatio: 4 / 3)
        XCTAssertEqual(split, CGSize(width: 1000, height: 750))
    }

    func testHugeScreensStayWithinInitialPixelAndDimensionBudgets() {
        for aspect: CGFloat in [4 / 3, 16 / 9, 0.75, 5] {
            let size = StartupSizing.imageSize(availableSize: CGSize(width: 10_000, height: 10_000), displayScale: 3, aspectRatio: aspect)
            XCTAssertLessThanOrEqual(size.width, StartupSizing.maximumImageDimension)
            XCTAssertLessThanOrEqual(size.height, StartupSizing.maximumImageDimension)
            XCTAssertLessThanOrEqual(size.width * size.height, StartupSizing.maximumImagePixels)
            XCTAssertEqual(size.width / size.height, aspect, accuracy: 0.01)
        }
    }

    func testInvalidMetricsHaveSafeFallbacks() {
        XCTAssertEqual(StartupSizing.imageSize(availableSize: .zero, displayScale: 0, aspectRatio: .nan),
                       CGSize(width: 640, height: 480))
        XCTAssertEqual(StartupSizing.imageSize(availableSize: CGSize(width: 640, height: 480), displayScale: .nan, aspectRatio: 0),
                       CGSize(width: 640, height: 480))
    }

    func testAutomaticSizingNeverUsesTinyNonZeroStartupProposal() {
        let size = StartupSizing.imageSize(availableSize: CGSize(width: 77, height: 58), displayScale: 2, aspectRatio: 4 / 3)
        XCTAssertGreaterThanOrEqual(max(size.width, size.height), StartupSizing.minimumLongEdge)
        XCTAssertEqual(size.width / size.height, 4 / 3, accuracy: 0.01)
        XCTAssertNotEqual(size, CGSize(width: 154, height: 116))
    }

    @MainActor
    func testTransientSmallLayoutIsCancelledBeforeFinalLayoutDeterminesResolution() async throws {
        let model = FractalModel(defaults: nil)
        model.renderingBackend = .cpu
        model.parameters.maxIterations = 4
        let transient = Task {
            await model.drawInitialImageAfterLayoutSettles(availableSize: CGSize(width: 77, height: 58), displayScale: 2)
        }
        try await Task.sleep(for: .milliseconds(20))
        transient.cancel()
        await transient.value
        XCTAssertFalse(model.isRendering)
        XCTAssertNil(model.image)
        let finalSize = CGSize(width: 400, height: 300)
        let expected = StartupSizing.imageSize(availableSize: finalSize, displayScale: 2,
            aspectRatio: CGFloat(model.parameters.viewport.width / model.parameters.viewport.height))
        await model.drawInitialImageAfterLayoutSettles(availableSize: finalSize, displayScale: 2)
        try await waitForRender(model)
        XCTAssertEqual(model.parameters.width, Int(expected.width))
        XCTAssertEqual(model.parameters.height, Int(expected.height))
        XCTAssertGreaterThan(model.parameters.width, 640)
    }

    @MainActor
    func testFreshStartupSizesOnlyOnceAndWaitsForValidLayout() async throws {
        let model = FractalModel(defaults: nil)
        model.renderingBackend = .cpu
        model.parameters.maxIterations = 4
        let originalView = model.parameters.viewport
        model.drawInitialImage(availableSize: .zero, displayScale: 2)
        XCTAssertFalse(model.isRendering)
        XCTAssertNil(model.image)
        let available = CGSize(width: 80, height: 60)
        let expected = StartupSizing.imageSize(availableSize: available, displayScale: 2,
            aspectRatio: CGFloat(originalView.width / originalView.height))
        model.drawInitialImage(availableSize: available, displayScale: 2)
        try await waitForRender(model)
        XCTAssertEqual(model.parameters.width, Int(expected.width))
        XCTAssertEqual(model.parameters.height, Int(expected.height))
        XCTAssertEqual(model.parameters.antiAlias, 1)
        XCTAssertEqual(model.parameters.viewport, originalView)
        let before = model.parameters
        model.drawInitialImage(availableSize: CGSize(width: 2000, height: 1000), displayScale: 3)
        XCTAssertEqual(model.parameters, before)
        XCTAssertFalse(model.isRendering, "Ordinary resizing or rotation must not restart rendering")
    }

    @MainActor
    func testSavedImageSizeAndAntiAliasingOverrideDeviceDefaults() async throws {
        let suite = "ArgenticStartupSize.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let seed = FractalModel(defaults: defaults)
        seed.savedSettingGroups = [.size]
        seed.parameters.width = 96
        seed.parameters.height = 64
        seed.parameters.antiAlias = 2
        let model = FractalModel(defaults: defaults)
        model.renderingBackend = .cpu
        model.parameters.maxIterations = 4
        model.drawInitialImage(availableSize: CGSize(width: 1000, height: 800), displayScale: 2)
        try await waitForRender(model)
        XCTAssertEqual(model.parameters.width, 96)
        XCTAssertEqual(model.parameters.height, 64)
        XCTAssertEqual(model.parameters.antiAlias, 2)
    }

    @MainActor
    func testExplicitSizeChosenBeforeFirstLayoutIsPreserved() async throws {
        let model = FractalModel(defaults: nil)
        model.renderingBackend = .cpu
        model.parameters.width = 48
        model.parameters.height = 32
        model.parameters.antiAlias = 2
        model.parameters.maxIterations = 4
        model.drawInitialImage(availableSize: CGSize(width: 1000, height: 800), displayScale: 3)
        try await waitForRender(model)
        XCTAssertEqual(model.parameters.width, 48)
        XCTAssertEqual(model.parameters.height, 32)
        XCTAssertEqual(model.parameters.antiAlias, 2)
    }

    @MainActor
    private func waitForRender(_ model: FractalModel) async throws {
        let deadline = Date().addingTimeInterval(15)
        while model.isRendering && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isRendering)
        XCTAssertNotNil(model.image)
    }
}
