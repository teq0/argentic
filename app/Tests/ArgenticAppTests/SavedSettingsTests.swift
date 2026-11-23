import ArgenticCore
import XCTest
@testable import Argentic

final class SavedSettingsTests: XCTestCase {
    @MainActor
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "ArgenticSavedSettingsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private var customParameters: FractalParameters {
        // Start from app defaults, including metadata carried by the current startup example.
        var p = ExampleCatalog.startupParameters
        p.width = 800
        p.height = 600
        p.antiAlias = 2
        p.viewport = Viewport(xMin: -1, xMax: 0, yMin: -0.5, yMax: 0.5)
        p.fitAspect = false
        p.formula = 1
        p.maxIterations = 250
        p.juliaMode = true
        p.juliaX = 0.1
        p.juliaY = -0.4
        p.insideOut = true
        p.orbitTransform = 2
        p.coordinateFlag = 3
        p.scaleFactor = 2
        p.lyapunovMapping = 2
        p.lyapunovDerivative = 3
        p.render = 6
        p.trapRadius = 0.25
        p.renderScale = 2
        p.blend = 4
        p.rgbOrder = 3
        p.colors.step = [20, 30, 40]
        p.colors.start = [50, 60, 70]
        p.colors.saturation = [0.5, 1.5, 2]
        p.colors.offset = [10, 20, 30]
        return p
    }

    @MainActor
    func testAllSelectedSettingsRestoreWithoutRenderingOrRestoringTransientState() throws {
        try withDefaults { defaults in
            let model = FractalModel(defaults: defaults)
            model.savedSettingGroups = Set(SavedSettingGroup.allCases)
            model.parameters = customParameters
            model.zoomMode = .rectangle
            model.zoomOutOnClick = true
            model.clickZoomBehavior = .centerClickedPoint
            model.smallZoomStep = .ten
            model.showInspector = true
            model.inspectorTab = .size
            model.imageFormat = .jpeg
            model.renderingBackend = .cpu
            model.isFullScreen = true
            model.selection = CGRect(x: 1, y: 2, width: 30, height: 40)
            model.showingSavedSettings = true
            model.showingHelp = true

            let restored = FractalModel(defaults: defaults)
            XCTAssertEqual(restored.savedSettingGroups, Set(SavedSettingGroup.allCases))
            XCTAssertEqual(restored.parameters, customParameters)
            XCTAssertEqual(restored.zoomMode, .rectangle)
            XCTAssertTrue(restored.zoomOutOnClick)
            XCTAssertEqual(restored.clickZoomBehavior, .centerClickedPoint)
            XCTAssertEqual(restored.smallZoomStep, .ten)
            XCTAssertTrue(restored.showInspector)
            XCTAssertEqual(restored.inspectorTab, .size)
            XCTAssertEqual(restored.imageFormat, .jpeg)
            XCTAssertEqual(restored.renderingBackend, .cpu)
            XCTAssertTrue(restored.isFullScreen)
            XCTAssertNil(restored.image)
            XCTAssertNil(restored.selection)
            XCTAssertFalse(restored.canGoBack)
            XCTAssertFalse(restored.isRendering)
            XCTAssertFalse(restored.showingSavedSettings)
            XCTAssertFalse(restored.showingHelp)
        }
    }

    @MainActor
    func testOnlySelectedGroupsRestoreAndNestedEditsAreSaved() throws {
        try withDefaults { defaults in
            let model = FractalModel(defaults: defaults)
            model.savedSettingGroups = [.colour, .size]
            model.parameters = customParameters
            model.parameters.colors.offset[0] = 99
            model.parameters.width = 1024
            model.clickZoomBehavior = .keepPosition
            model.smallZoomStep = .twentyFive
            model.showInspector = true
            model.imageFormat = .bmp
            model.renderingBackend = .cpu
            model.isFullScreen = true

            var expected = ExampleCatalog.startupParameters
            expected.width = 1024
            expected.height = customParameters.height
            expected.antiAlias = customParameters.antiAlias
            expected.blend = customParameters.blend
            expected.rgbOrder = customParameters.rgbOrder
            expected.renderScale = customParameters.renderScale
            expected.colors = customParameters.colors
            expected.colors.offset[0] = 99
            let restored = FractalModel(defaults: defaults)
            XCTAssertEqual(restored.parameters, expected)
            XCTAssertEqual(restored.savedSettingGroups, [.colour, .size])
            XCTAssertEqual(restored.clickZoomBehavior, .centerClickedPoint)
            XCTAssertEqual(restored.smallZoomStep, .five)
            XCTAssertFalse(restored.showInspector)
            XCTAssertEqual(restored.imageFormat, .png)
            XCTAssertEqual(restored.renderingBackend, .metal)
            XCTAssertFalse(restored.isFullScreen)
        }
    }

    @MainActor
    func testOptingOutClearsPreviousDefaultsWithoutChangingCurrentSession() throws {
        try withDefaults { defaults in
            let model = FractalModel(defaults: defaults)
            model.savedSettingGroups = Set(SavedSettingGroup.allCases)
            model.parameters = customParameters
            model.clickZoomBehavior = .keepPosition
            model.savedSettingGroups = []
            XCTAssertEqual(model.parameters, customParameters)
            XCTAssertEqual(model.clickZoomBehavior, .keepPosition)

            let restored = FractalModel(defaults: defaults)
            XCTAssertTrue(restored.savedSettingGroups.isEmpty)
            XCTAssertEqual(restored.parameters, ExampleCatalog.startupParameters)
            XCTAssertEqual(restored.clickZoomBehavior, .centerClickedPoint)
            restored.savedSettingGroups = Set(SavedSettingGroup.allCases)
            XCTAssertEqual(FractalModel(defaults: defaults).parameters, ExampleCatalog.startupParameters)
        }
    }

    @MainActor
    func testDefaultPolicyAndLegacyZoomMigration() throws {
        try withDefaults { defaults in
            defaults.set("keepPosition", forKey: "clickZoomBehavior")
            let model = FractalModel(defaults: defaults)
            XCTAssertEqual(model.savedSettingGroups, [.zoom])
            XCTAssertEqual(model.clickZoomBehavior, .keepPosition)
            model.parameters = customParameters
            model.saveSettings()
            model.smallZoomStep = .one
            XCTAssertNil(defaults.object(forKey: "clickZoomBehavior"))
            let restored = FractalModel(defaults: defaults)
            XCTAssertEqual(restored.clickZoomBehavior, .keepPosition)
            XCTAssertEqual(restored.smallZoomStep, .one)
            XCTAssertEqual(restored.parameters, ExampleCatalog.startupParameters)
        }
    }

    @MainActor
    func testCorruptSnapshotAndUnknownGroupsFallBackSafely() throws {
        try withDefaults { defaults in
            defaults.set(["size", "future-setting"], forKey: "savedSettingGroups")
            defaults.set(Data("not JSON".utf8), forKey: "savedAppSettings")
            let restored = FractalModel(defaults: defaults)
            XCTAssertEqual(restored.savedSettingGroups, [.size])
            XCTAssertEqual(restored.parameters, ExampleCatalog.startupParameters)
        }
    }

    @MainActor
    func testOlderSavedSettingsWithoutBackendStillRestore() throws {
        try withDefaults { defaults in
            let model = FractalModel(defaults: defaults)
            model.savedSettingGroups = [.colour]
            model.parameters.colors.offset = [11, 22, 33]
            let data = try XCTUnwrap(defaults.data(forKey: "savedAppSettings"))
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object.removeValue(forKey: "renderingBackend")
            object.removeValue(forKey: "isFullScreen")
            object.removeValue(forKey: "smallZoomStep")
            defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "savedAppSettings")
            let restored = FractalModel(defaults: defaults)
            XCTAssertEqual(restored.parameters.colors.offset, [11, 22, 33])
            XCTAssertEqual(restored.renderingBackend, .metal)
            XCTAssertFalse(restored.isFullScreen)
            XCTAssertEqual(restored.smallZoomStep, .five)
        }
    }

    @MainActor
    func testFullScreenPreferenceCanBeSavedAndOptedOutIndependently() throws {
        try withDefaults { defaults in
            let model = FractalModel(defaults: defaults)
            model.savedSettingGroups = [.fullScreen]
            model.isFullScreen = true
            XCTAssertTrue(FractalModel(defaults: defaults).isFullScreen)
            model.isFullScreen = false
            XCTAssertFalse(FractalModel(defaults: defaults).isFullScreen)
            model.isFullScreen = true
            model.savedSettingGroups = []
            XCTAssertTrue(model.isFullScreen, "Opting out must not change the current window")
            XCTAssertFalse(FractalModel(defaults: defaults).isFullScreen)
        }
    }
}
