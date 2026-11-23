import ArgenticCore
import SwiftUI

/// A native checked menu item. An image in a Button label does not set macOS menu-item state.
private struct MenuChoice: View {
    let title: String
    let selected: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Toggle(title, isOn: Binding(get: { selected }, set: { _ in action() }))
        .disabled(!enabled)
    }
}

private func numbered(_ entry: CatalogEntry) -> String {
    "\(entry.id).) \(entry.title)"
}

private func groupTitle(_ title: String, range: ClosedRange<Int>, selected: Int) -> String {
    range.contains(selected) ? "\(title) — \(selected)" : title
}

struct FileMenuContent: View {
    var model: FractalModel

    var body: some View {
        Button("Open Picture or Parameters…") { model.showingImporter = true }
            .keyboardShortcut("o")
        Divider()
        Menu("Save Image As") {
            ForEach(ImageFormat.allCases) { format in
                Button("\(format.rawValue)\(format.supportsSettings ? "" : " (Image Only)")…") { model.saveImage(as: format) }
            }
        }
        .disabled(model.image == nil)
        Button("Save Sterling Parameters (.loo)…") { model.showingLooExporter = true }
        Button("Save Parameters As JSON…") { model.showingParametersExporter = true }
    }
}

struct EditMenuContent: View {
    var model: FractalModel

    var body: some View {
        Button("Copy Image") { model.copyImage() }
            .keyboardShortcut("c")
            .disabled(model.image == nil)
    }
}

struct SmallZoomStepPicker: View {
    @Bindable var model: FractalModel

    var body: some View {
        Picker("Small Zoom Step — \(model.smallZoomStep.rawValue)%", selection: $model.smallZoomStep) {
            ForEach(SmallZoomStep.allCases) { step in
                Text("\(step.rawValue)%").tag(step)
            }
        }
        .pickerStyle(.menu)
    }
}

struct ViewMenuContent: View {
    @Bindable var model: FractalModel

    var body: some View {
        Picker("Image Display", selection: $model.imageDisplayMode) {
            ForEach(ImageDisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
    }
}

struct ZoomModeMenuContent: View {
    var model: FractalModel

    var body: some View {
        Section("Zoom In/Out") {
            MenuChoice(title: "Zoom In", selected: model.zoomMode == .click && !model.zoomOutOnClick) {
                model.zoomMode = .click
                model.zoomOutOnClick = false
            }
            MenuChoice(title: "Zoom Out", selected: model.zoomMode == .click && model.zoomOutOnClick) {
                model.zoomMode = .click
                model.zoomOutOnClick = true
            }
        }
        Section("Rectangle") {
            MenuChoice(title: "Select Rectangle", selected: model.zoomMode == .rectangle) {
                model.zoomMode = .rectangle
            }
        }
    }
}

struct ImageMenuContent: View {
    var model: FractalModel

    var body: some View {
        Button("Draw") { model.draw() }
            .keyboardShortcut("d")
        Toggle("Use Metal GPU Rendering", isOn: Binding(
            get: { model.renderingBackend == .metal }, set: { model.setUseMetal($0) }
        ))
        Button("Back") { model.goBack() }
            .keyboardShortcut("[")
            .disabled(!model.canGoBack)
        Button("Small Zoom In (\(model.smallZoomStep.rawValue)%)") { model.smallZoom(inward: true) }
            .disabled(!model.canZoom)
        Button("Small Zoom Out (\(model.smallZoomStep.rawValue)%)") { model.smallZoom(inward: false) }
            .disabled(!model.canZoom)
        SmallZoomStepPicker(model: model)
        Picker("Click Zoom Behaviour", selection: Binding(
            get: { model.clickZoomBehavior }, set: { model.clickZoomBehavior = $0 }
        )) {
            ForEach(ClickZoomBehavior.allCases) { behavior in
                Text(behavior.title).tag(behavior)
            }
        }
        Button("Clear Rectangle") { model.selection = nil }
            .disabled(model.selection == nil)
        Toggle("Julia Mode", isOn: Binding(get: { model.parameters.juliaMode }, set: { model.setJuliaMode($0) }))
        Toggle("Inside Out", isOn: Binding(get: { model.parameters.insideOut }, set: { model.setInsideOut($0) }))
        Button("Reset Coordinates") { model.resetCoordinates() }
            .keyboardShortcut("0")
        Divider()
        // These change the coordinates fed to the formulas, as in the original; they do not turn the finished picture.
        ForEach([(1, "Rotate90"), (2, "Rotate90Mirror"), (3, "Mirror")], id: \.0) { flag, title in
            Toggle(title, isOn: Binding(
                get: { model.parameters.coordinateFlag == flag },
                set: { _ in model.toggleCoordinateFlag(flag) }
            ))
        }
        Divider()
        ForEach([1, 2, 3, 4], id: \.self) { k in
            MenuChoice(title: k == 1 ? "Anti-Alias Off" : "Anti-Alias \(k):1", selected: model.parameters.antiAlias == k) {
                model.setAntiAlias(k)
            }
        }
    }
}

struct FormulaMenuContent: View {
    var model: FractalModel

    var body: some View {
        ForEach(Catalog.formulaGroups, id: \.title) { group in
            Menu(groupTitle(group.title, range: group.range, selected: model.parameters.formula)) {
                ForEach(Catalog.formulas.filter { group.range.contains($0.id) }) { entry in
                    MenuChoice(title: numbered(entry), selected: model.parameters.formula == entry.id, enabled: FractalImage.isFormulaAvailable(entry.id)) {
                        model.chooseFormula(entry.id)
                    }
                }
            }
        }
    }
}

struct RenderMenuContent: View {
    var model: FractalModel

    var body: some View {
        ForEach(Catalog.renderGroups, id: \.title) { group in
            Menu(groupTitle(group.title, range: group.range, selected: model.parameters.render)) {
                ForEach(Catalog.renders.filter { group.range.contains($0.id) }) { entry in
                    MenuChoice(title: numbered(entry), selected: model.parameters.render == entry.id, enabled: FractalImage.userRenders.contains(entry.id)) {
                        model.chooseRender(entry.id)
                    }
                }
            }
        }
        Menu(groupTitle("Lyapunov", range: 1...20, selected: model.parameters.formula - 100)) {
            Button("Clear") {
                model.clearLyapunovSettings()
            }
            .disabled(!model.isLyapunovEnabled)
            Divider()
            Menu(groupTitle("Map", range: 1...20, selected: model.parameters.formula - 100)) {
                ForEach(Catalog.lyapunovMaps) { entry in
                    MenuChoice(title: numbered(entry), selected: model.parameters.formula == 100 + entry.id) {
                        model.chooseLyapunovMap(entry.id)
                    }
                }
            }
            Menu(model.isLyapunovEnabled ? "Derivative — \(model.parameters.lyapunovDerivative)" : "Derivative") {
                ForEach(Catalog.lyapunovDerivatives) { entry in
                    MenuChoice(title: numbered(entry), selected: model.isLyapunovEnabled && model.parameters.lyapunovDerivative == entry.id) {
                        model.chooseLyapunovDerivative(entry.id)
                    }
                }
            }
            .disabled(!model.isLyapunovEnabled)
            Menu(model.isLyapunovEnabled ? "Mapping — \(model.parameters.lyapunovMapping)" : "Mapping") {
                ForEach(Catalog.lyapunovMappings) { entry in
                    MenuChoice(title: numbered(entry), selected: model.isLyapunovEnabled && model.parameters.lyapunovMapping == entry.id) {
                        model.chooseLyapunovMapping(entry.id)
                    }
                }
            }
            .disabled(!model.isLyapunovEnabled)
        }
    }
}

struct ColorMenuContent: View {
    var model: FractalModel

    var body: some View {
        ForEach(Catalog.blendGroups, id: \.title) { group in
            Menu(groupTitle(group.title, range: group.range, selected: model.parameters.blend)) {
                ForEach(Array(group.range), id: \.self) { id in
                    MenuChoice(title: String(format: "%02d.)", id), selected: model.parameters.blend == id) {
                        model.chooseBlend(id)
                    }
                }
            }
        }
        Menu("RGB — \(model.parameters.rgbOrder)") {
            ForEach(Array(Catalog.rgbOrders.enumerated()), id: \.offset) { index, name in
                MenuChoice(title: "\(index + 1).) \(name)", selected: model.parameters.rgbOrder == index + 1) {
                    model.chooseRGBOrder(index + 1)
                }
            }
        }
        Menu("Transform — \(model.parameters.orbitTransform)") {
            ForEach(Catalog.transforms) { entry in
                MenuChoice(title: String(format: "%02d.) ", entry.id) + entry.title, selected: model.parameters.orbitTransform == entry.id) {
                    model.chooseTransform(entry.id)
                }
            }
        }
    }
}

struct DialogsMenuContent: View {
    var model: FractalModel

    var body: some View {
        ForEach(InspectorTab.allCases) { tab in
            Button(tab.rawValue) {
                model.inspectorTab = tab
                model.showInspector = true
            }
        }
        Divider()
        Button("Saved Settings…") { model.showingSavedSettings = true }
    }
}

/// Everything in one place for the iOS toolbar.
struct AllMenusContent: View {
    var model: FractalModel

    var body: some View {
        Menu("File") { FileMenuContent(model: model) }
        Menu("Edit") { EditMenuContent(model: model) }
        Menu("View") { ViewMenuContent(model: model) }
        Menu("Examples") { ExamplesMenuContent(model: model) }
        Menu("Image") { ImageMenuContent(model: model) }
        Menu("Formula") { FormulaMenuContent(model: model) }
        Menu("Render") { RenderMenuContent(model: model) }
        Menu("Colour") { ColorMenuContent(model: model) }
        Menu("Dialogs") { DialogsMenuContent(model: model) }
        Divider()
        HelpMenuContent(model: model)
    }
}
