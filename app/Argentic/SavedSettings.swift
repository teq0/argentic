import ArgenticCore
import Foundation
import SwiftUI

enum SavedSettingGroup: String, CaseIterable, Identifiable, Codable {
    case zoom, inspector, display, export, fullScreen,rendering, fractal, colour, size, coordinates

    static var availableGroups: [Self] {
        #if os(macOS)
        allCases
        #else
        allCases.filter { $0 != .fullScreen }
        #endif
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .zoom: return "Zoom Controls"
        case .rendering: return "Rendering Backend"
        case .fractal: return "Fractal and Render"
        case .colour: return "Colours"
        case .size: return "Image Size and Anti-Aliasing"
        case .coordinates: return "View Coordinates"
        case .inspector: return "Inspector"
        case .display: return "Image Display"
        case .export: return "Export Format"
        case .fullScreen: return "Full-Screen State"
        }
    }

    var detail: String {
        switch self {
        case .zoom: return "Click behaviour, zoom mode, click-zoom direction and small zoom step."
        case .inspector: return "Visibility and selected panel."
        case .display: return "Fit to Window or Actual Pixels (100%) display mode."
        case .export: return "Last image export format."
        case .fullScreen: return "Remember the main fractal window's full-screen/windowed state on quit (macOS)."
        case .rendering: return "Use Metal GPU rendering or double-precision CPU rendering."
        case .fractal: return "Formula, render, iterations, Julia settings, transforms and mapping."
        case .colour: return "Blend, RGB order, render scale and colour mixing controls."
        case .size: return "Width, height, last custom size and anti-aliasing factor."
        case .coordinates: return "Current complex-plane bounds and aspect fitting."
        }
    }
}

/// Only opted-in values are copied into this snapshot; everything else stays at built-in defaults.
struct SavedAppSettings: Codable {
    var parameters = ExampleCatalog.startupParameters
    var customImageWidth = ExampleCatalog.startupParameters.width
    var customImageHeight = ExampleCatalog.startupParameters.height
    var zoomMode = ZoomMode.click
    var zoomOutOnClick = false
    var clickZoomBehavior = ClickZoomBehavior.defaultBehavior
    var smallZoomStep = SmallZoomStep.five
    var showInspector = false
    var inspectorTab = InspectorTab.color
    var imageFormat = ImageFormat.png
    var renderingBackend = RenderingBackend.metal
    var isFullScreen = false
    var imageDisplayMode = ImageDisplayMode.platformDefault

    private enum CodingKeys: String, CodingKey {
        case parameters, customImageWidth, customImageHeight, zoomMode, zoomOutOnClick, clickZoomBehavior, smallZoomStep, showInspector, inspectorTab, imageFormat, renderingBackend, isFullScreen, imageDisplayMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        parameters = try c.decodeIfPresent(FractalParameters.self, forKey: .parameters) ?? ExampleCatalog.startupParameters
        customImageWidth = try c.decodeIfPresent(Int.self, forKey: .customImageWidth) ?? parameters.width
        customImageHeight = try c.decodeIfPresent(Int.self, forKey: .customImageHeight) ?? parameters.height
        zoomMode = try c.decodeIfPresent(ZoomMode.self, forKey: .zoomMode) ?? .click
        zoomOutOnClick = try c.decodeIfPresent(Bool.self, forKey: .zoomOutOnClick) ?? false
        clickZoomBehavior = try c.decodeIfPresent(ClickZoomBehavior.self, forKey: .clickZoomBehavior) ?? .defaultBehavior
        smallZoomStep = try c.decodeIfPresent(SmallZoomStep.self, forKey: .smallZoomStep) ?? .five
        showInspector = try c.decodeIfPresent(Bool.self, forKey: .showInspector) ?? false
        inspectorTab = try c.decodeIfPresent(InspectorTab.self, forKey: .inspectorTab) ?? .color
        imageFormat = try c.decodeIfPresent(ImageFormat.self, forKey: .imageFormat) ?? .png
        renderingBackend = try c.decodeIfPresent(RenderingBackend.self, forKey: .renderingBackend) ?? .metal
        isFullScreen = try c.decodeIfPresent(Bool.self, forKey: .isFullScreen) ?? false
        imageDisplayMode = try c.decodeIfPresent(ImageDisplayMode.self, forKey: .imageDisplayMode) ?? .platformDefault
    }

    static func filteredParameters(_ source: FractalParameters, groups: Set<SavedSettingGroup>) -> FractalParameters {
        var p = ExampleCatalog.startupParameters
        if groups.contains(.fractal) {
            p.formula = source.formula
            p.render = source.render
            p.maxIterations = source.maxIterations
            p.juliaMode = source.juliaMode
            p.juliaX = source.juliaX
            p.juliaY = source.juliaY
            p.insideOut = source.insideOut
            p.orbitTransform = source.orbitTransform
            p.coordinateFlag = source.coordinateFlag
            p.scaleFactor = source.scaleFactor
            p.lyapunovMapping = source.lyapunovMapping
            p.lyapunovDerivative = source.lyapunovDerivative
            p.trapRadius = source.trapRadius
        }
        if groups.contains(.colour) {
            p.blend = source.blend
            p.rgbOrder = source.rgbOrder
            p.renderScale = source.renderScale
            p.colors = source.colors
        }
        if groups.contains(.size) {
            p.width = source.width
            p.height = source.height
            p.antiAlias = source.antiAlias
        }
        if groups.contains(.coordinates) {
            p.viewport = source.viewport
            p.fitAspect = source.fitAspect
        }
        return p
    }

    @MainActor
    init(model: FractalModel, groups: Set<SavedSettingGroup>) {
        parameters = Self.filteredParameters(model.parameters, groups: groups)
        if groups.contains(.size) {
            customImageWidth = model.customImageWidth
            customImageHeight = model.customImageHeight
        }
        if groups.contains(.zoom) {
            zoomMode = model.zoomMode
            zoomOutOnClick = model.zoomOutOnClick
            clickZoomBehavior = model.clickZoomBehavior
            smallZoomStep = model.smallZoomStep
        }
        if groups.contains(.inspector) {
            showInspector = model.showInspector
            inspectorTab = model.inspectorTab
        }
        if groups.contains(.export) { imageFormat = model.imageFormat }
        if groups.contains(.rendering) { renderingBackend = model.renderingBackend }
        if groups.contains(.fullScreen) { isFullScreen = model.fullScreenStateForSaving }
        if groups.contains(.display) { imageDisplayMode = model.imageDisplayMode }
    }

    @MainActor
    func restore(to model: FractalModel, groups: Set<SavedSettingGroup>) {
        model.parameters = Self.filteredParameters(parameters, groups: groups)
        if groups.contains(.size) {
            model.customImageWidth = customImageWidth
            model.customImageHeight = customImageHeight
        }
        if groups.contains(.zoom) {
            model.zoomMode = zoomMode
            model.zoomOutOnClick = zoomOutOnClick
            model.clickZoomBehavior = clickZoomBehavior
            model.smallZoomStep = smallZoomStep
        }
        if groups.contains(.inspector) {
            model.showInspector = showInspector
            model.inspectorTab = inspectorTab
        }
        if groups.contains(.export) { model.imageFormat = imageFormat }
        if groups.contains(.rendering) { model.renderingBackend = renderingBackend }
        if groups.contains(.fullScreen) { model.isFullScreen = isFullScreen }
        if groups.contains(.display) { model.imageDisplayMode = imageDisplayMode }
    }
}

struct SavedSettingsView: View {
    var model: FractalModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<SavedSettingGroup>

    init(model: FractalModel) {
        self.model = model
        _selected = State(initialValue: model.savedSettingGroups)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Saved Settings").font(.title2.bold())
            Text("Choose what to remember for the next launch. Unchecked groups start with built-in defaults. Changes take effect next launch, not in the current image.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SavedSettingGroup.availableGroups) { group in
                        Toggle(isOn: Binding(
                            get: { selected.contains(group) },
                            set: { if $0 { selected.insert(group) } else { selected.remove(group) } }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.title)
                                Text(group.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Text("Selected settings are saved automatically as they change and when the app closes or enters the background. Images and Back history are not saved.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Select All") { selected = Set(SavedSettingGroup.availableGroups) }
                Button("Select None") { selected.removeAll() }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.savedSettingGroups = selected
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(idealWidth: 520, idealHeight: 620)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }
}
