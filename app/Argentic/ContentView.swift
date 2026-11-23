import ArgenticCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Bindable var model: FractalModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var imageMagnification: CGFloat?

    var body: some View {
        FractalCanvas(model: model)
            .onPreferenceChange(ImageMagnificationPreferenceKey.self) { imageMagnification = $0 }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.12))
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(model: model, magnification: imageMagnification) }
            .toolbar { toolbarContent }
            .sheet(isPresented: $model.showingSavedSettings) { SavedSettingsView(model: model) }
            #if os(iOS)
            .sheet(isPresented: $model.showingHelp) { HelpView() }
            #endif
            .inspector(isPresented: $model.showInspector) {
                InspectorView(model: model)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            }
            .fileExporter(
                isPresented: $model.showingImageExporter,
                document: ImageDocument(data: model.imageExportData),
                contentType: model.imageFormat.type,
                defaultFilename: "fractal"
            ) { result in
                if case .failure(let error) = result { model.message = "Could not save the image: \(error.localizedDescription)" }
            }
            .fileExporter(
                isPresented: $model.showingParametersExporter,
                document: ParametersDocument(data: model.parametersData()),
                contentType: .json,
                defaultFilename: "fractal-parameters"
            ) { _ in }
            .fileExporter(
                isPresented: $model.showingLooExporter,
                document: LooDocument(data: model.looData()),
                contentType: .sterlingParameters,
                defaultFilename: "fractal"
            ) { _ in }
            // Any file is allowed: .loo is not a registered type, and the file is identified by its content.
            .fileImporter(isPresented: $model.showingImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                model.open(urls: urls)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { model.saveSettings() }
            }
            #if os(macOS)
            .background(FullScreenWindowObserver(model: model).allowsHitTesting(false))
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                model.saveSettings()
            }
            .frame(minWidth: 480, minHeight: 360)
            #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.draw() } label: { Label("Draw", systemImage: "play.fill") }
                .disabled(model.isRendering)
                .help("Draw — render the current fractal (⌘D)")
            Button { model.abort() } label: { Label("Abort", systemImage: "stop.fill") }
                .disabled(!model.isRendering)
                .help("Abort — stop rendering and keep the partial image")
            Button { model.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                .disabled(!model.canGoBack)
                .help("Back — restore the previous zoom exactly (⌘[)")
            Button { model.resetCoordinates() } label: { Label("Reset Coordinates", systemImage: "house") }
                .help("Reset Coordinates — return to the standard full view (⌘0)")

            Toggle(isOn: Binding(
                get: { model.imageDisplayMode == .fitToWindow },
                set: { model.imageDisplayMode = $0 ? .fitToWindow : .actualPixels }
            )) {
                Label("Fit Image to Window", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help(model.imageDisplayMode == .fitToWindow
                ? "Fit Image to Window — on; click to view actual pixels at 100% without stretching"
                : "Fit Image to Window — off; click to scale the entire image to the available area")

            ControlGroup {
                Button { model.smallZoom(inward: false) } label: { Label("Small Zoom Out", systemImage: "minus.magnifyingglass") }
                    .disabled(!model.canZoom)
                    .help("Small Zoom Out — zoom out one \(model.smallZoomStep.rawValue)% magnification step around the current centre")
                SmallZoomStepPicker(model: model).labelsHidden()
                    .help("Small Zoom Step — choose the percentage used by the adjacent zoom buttons")
                Button { model.smallZoom(inward: true) } label: { Label("Small Zoom In", systemImage: "plus.magnifyingglass") }
                    .disabled(!model.canZoom)
                    .help("Small Zoom In — zoom in one \(model.smallZoomStep.rawValue)% magnification step around the current centre")
            }
            .labelStyle(.iconOnly)

            Menu {
                ZoomModeMenuContent(model: model)
            } label: {
                Label(model.zoomMode.rawValue, systemImage: model.zoomMode == .rectangle
                    ? "rectangle.dashed"
                    : model.zoomOutOnClick ? "minus.magnifyingglass" : "plus.magnifyingglass")
            }
            .labelStyle(.titleAndIcon)
            .help(model.zoomMode == .rectangle
                ? "Zoom Mode — rectangle selection is active; choose Zoom In or Zoom Out in this menu for picture clicks"
                : "Zoom Mode — picture clicks zoom \(model.zoomOutOnClick ? "out" : "in"); change direction in the Zoom In/Out section")

            if model.zoomMode == .rectangle {
                Button { model.zoomToSelection() } label: { Label("Zoom to Selection", systemImage: "plus.magnifyingglass") }
                    .disabled(model.selection == nil)
                    .help("Zoom to Selection — render the region inside the selected rectangle")
            }

            Toggle(isOn: Binding(get: { model.parameters.juliaMode }, set: { model.setJuliaMode($0) })) {
                Label("Julia Sets", systemImage: "j.square")
            }
            .help(model.parameters.juliaMode
                ? "Julia Sets — turn off Julia mode and return to non-Julia rendering"
                : "Julia Sets — turn on Julia mode and reset its view. Set Julia X/Y in Controls → Fractal")

            #if os(iOS)
            Menu { AllMenusContent(model: model) } label: { Label("Menu", systemImage: "line.3.horizontal") }
                .help("Menu — open file, example, image, formula, render, colour, settings and Help actions")
            #endif

            Toggle(isOn: $model.showInspector) { Label("Controls", systemImage: "slider.horizontal.3") }
                .help(model.showInspector
                    ? "Controls — hide the Colour, Fractal and Size inspector"
                    : "Controls — show the Colour, Fractal and Size inspector")
        }
    }
}

private struct StatusBar: View {
    var model: FractalModel
    var magnification: CGFloat?

    var body: some View {
        HStack(spacing: 12) {
            if model.isRendering {
                ProgressView(value: model.progress).frame(width: 120)
            }
            if let message = model.message {
                Text(message).foregroundStyle(.orange)
            } else if let size = model.imageSize {
                let v = model.renderedViewport
                Text(model.renderingBackend == .metal ? "Metal GPU" : "CPU")
                Text("\(Int(size.width)) × \(Int(size.height))")
                if let magnification {
                    Text("\(model.imageDisplayMode == .fitToWindow ? "Fit · " : "")\(Double(magnification).formatted(.percent.precision(.fractionLength(0...1))))")
                        .help("Display magnification only; rendered image resolution is unchanged")
                }
                Text(String(format: "x %.6g … %.6g   y %.6g … %.6g", v.xMin, v.xMax, v.yMin, v.yMax))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

private struct ImageMagnificationPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() }
}

/// A changed layout cancels an obsolete pending startup render.
private struct InitialCanvasMetrics: Equatable, Sendable {
    let size: CGSize
    let displayScale: CGFloat
}

/// Display scaling and scrolling never modify the fractal's render parameters.
private struct FractalCanvas: View {
    @Bindable var model: FractalModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let metrics = InitialCanvasMetrics(size: geo.size, displayScale: displayScale)
            Group {
                if let image = model.image, let size = model.imageSize {
                    let layout = ImageDisplayLayout(imageSize: size, availableSize: geo.size,
                        mode: model.imageDisplayMode, displayScale: displayScale)
                    Group {
                        if model.imageDisplayMode == .actualPixels {
                            ScrollView([.horizontal, .vertical]) {
                                picture(image, layout: layout)
                            }
                            .defaultScrollAnchor(.center)
                            .scrollIndicators(.automatic)
                            #if os(iOS)
                            // A one-finger rectangle drag must not also pan the picture.
                            // Switch back to click/tap mode to swipe-pan an oversized image.
                            .scrollDisabled(model.zoomMode == .rectangle)
                            #endif
                        } else {
                            picture(image, layout: layout)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                    }
                    .preference(key: ImageMagnificationPreferenceKey.self, value: layout.magnification)
                } else {
                    ProgressView().position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            // Non-zero layout proposals can still be temporary. Cancel the pending initial draw
            // on every size/scale change, then render once after layout has settled.
            .task(id: metrics) {
                await model.drawInitialImageAfterLayoutSettles(availableSize: metrics.size, displayScale: metrics.displayScale)
            }
        }
    }

    private func picture(_ image: CGImage, layout: ImageDisplayLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: displayScale)
                .resizable()
                .interpolation(model.imageDisplayMode == .actualPixels ? .none : .high)
                .frame(width: layout.displayedSize.width, height: layout.displayedSize.height)

            if let selection = model.selection {
                let rect = layout.displayedRect(from: selection)
                Rectangle()
                    .strokeBorder(.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .background(Color.white.opacity(0.1))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: layout.displayedSize.width, height: layout.displayedSize.height)
        .contentShape(Rectangle())
        .gesture(gesture(layout: layout))
    }

    private func gesture(layout: ImageDisplayLayout) -> AnyGesture<Void> {
        func clamp(_ p: CGPoint) -> CGPoint {
            layout.imagePoint(from: p) ?? .zero
        }
        switch model.zoomMode {
        case .click:
            return AnyGesture(
                SpatialTapGesture().onEnded { value in
                    model.zoom(atImagePoint: clamp(value.location), factor: model.zoomOutOnClick ? 0.5 : 2)
                }
                .map { _ in () }
            )
        case .rectangle:
            let drag = DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let a = clamp(value.startLocation)
                    let b = clamp(value.location)
                    model.selection = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                }
            let doubleTap = SpatialTapGesture(count: 2)
                .onEnded { value in
                    if let rect = model.selection, rect.contains(clamp(value.location)) { model.zoomToSelection() }
                }
            return AnyGesture(drag.simultaneously(with: doubleTap).map { _ in () })
        }
    }
}
