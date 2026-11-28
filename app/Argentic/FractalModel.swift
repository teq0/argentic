import ArgenticCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum ZoomMode: String, CaseIterable, Identifiable, Codable {
    case click = "Zoom In/Out"
    case rectangle = "Rectangle"
    var id: String { rawValue }
}

enum SmallZoomStep: Int, CaseIterable, Identifiable, Codable {
    case one = 1
    case five = 5
    case ten = 10
    case twentyFive = 25

    var id: Int { rawValue }
    var factor: Double { 1 + Double(rawValue) / 100 }
}

enum ClickZoomBehavior: String, CaseIterable, Identifiable, Codable, Sendable {
    case keepPosition
    case centerClickedPoint

    static let defaultBehavior: Self = .centerClickedPoint

    var id: String { rawValue }
    var title: String {
        switch self {
        case .keepPosition: return "Keep Clicked Point in Place"
        case .centerClickedPoint: return "Centre Clicked Point"
        }
    }
}

/// Picture formats the image can be saved in. Sterling2 itself wrote BMP and JPEG.
enum ImageFormat: String, CaseIterable, Identifiable, Codable {
    case png = "PNG"
    case jpeg = "JPEG"
    case bmp = "BMP"

    var id: String { rawValue }

    var type: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .bmp: return .bmp
        }
    }

    var supportsSettings: Bool { self != .bmp }
}

enum InspectorTab: String, CaseIterable, Identifiable, Codable {
    case color = "Colour"
    case fractal = "Fractal"
    case size = "Size"
    var id: String { rawValue }
}

@MainActor
@Observable
final class FractalModel {
    var parameters = ExampleCatalog.startupParameters {
        didSet {
            // Remember ordinary choices even when a file or saved settings enters Lyapunov mode.
            if (1...20).contains(oldValue.formula - 100) {
                lastLyapunovMap = oldValue.formula - 100
            } else if FractalImage.isFormulaAvailable(oldValue.formula) {
                lastNonLyapunovFormula = oldValue.formula
            }
            if (1...29).contains(oldValue.render) { lastNonLyapunovRender = oldValue.render }
            saveSettings()
        }
    }
    private var lastNonLyapunovFormula = FractalParameters().formula
    private var lastNonLyapunovRender = FractalParameters().render
    private var lastLyapunovMap = 1

    var isLyapunovEnabled: Bool {
        (101...120).contains(parameters.formula) || (30...32).contains(parameters.render)
    }

    var selectedLyapunovMap: Int {
        (101...120).contains(parameters.formula) ? parameters.formula - 100 : lastLyapunovMap
    }
    var renderingBackend: RenderingBackend = .metal { didSet { saveSettings() } }
    var image: CGImage?
    var isRendering = false
    var progress = 0.0
    var message: String?

    var zoomMode: ZoomMode = .click { didSet { saveSettings() } }
    var zoomOutOnClick = false { didSet { saveSettings() } }
    var smallZoomStep: SmallZoomStep = .five { didSet { saveSettings() } }
    var canZoom: Bool { !isRendering && image != nil && (current != nil || pictureHasParameters) }
    var clickZoomBehavior: ClickZoomBehavior = .defaultBehavior {
        didSet { saveSettings() }
    }
    /// Rectangle selection in image-pixel coordinates.
    var selection: CGRect?

    private struct ZoomState {
        let viewport: Viewport
        let fitAspect: Bool
    }

    private var zoomHistory: [ZoomState] = []
    var canGoBack: Bool { !zoomHistory.isEmpty && !isRendering }

    var showInspector = false { didSet { saveSettings() } }
    var imageDisplayMode: ImageDisplayMode = .platformDefault { didSet { saveSettings() } }
    var isFullScreen = false { didSet { if isFullScreen != oldValue { saveSettings() } } }
    /// The native window is authoritative when capturing settings, even if a notification was missed.
    @ObservationIgnored var fullScreenStateProvider: (() -> Bool?)?
    var fullScreenStateForSaving: Bool { fullScreenStateProvider?() ?? isFullScreen }
    var inspectorTab: InspectorTab = .color { didSet { saveSettings() } }
    var showingSavedSettings = false
    var showingHelp = false
    var savedSettingGroups: Set<SavedSettingGroup> = [.zoom, .inspector, .display, .export] { didSet { saveSettings() } }
    var customImageWidth = ExampleCatalog.startupParameters.width
    var customImageHeight = ExampleCatalog.startupParameters.height
    var showingImageExporter = false
    var imageFormat: ImageFormat = .png { didSet { saveSettings() } }
    var imageExportData = Data()
    var showingParametersExporter = false
    var showingLooExporter = false
    var showingImporter = false
    /// A picture needs embedded settings or an accompanying parameter file to be zoomed.
    var pictureHasParameters = false

    @ObservationIgnored private var current: FractalImage?
    /// Settings that produced the displayed pixels, rather than un-applied inspector edits.
    @ObservationIgnored private var imageParameters: FractalParameters?
    @ObservationIgnored private var token: CancelToken?
    @ObservationIgnored private var colorBusy = false
    @ObservationIgnored private var colorDirty = false
    @ObservationIgnored private let colorQueue = DispatchQueue(label: "argentic.color", qos: .userInitiated)
    @ObservationIgnored private var defaults: UserDefaults?
    @ObservationIgnored private var restoredImageSize = false
    @ObservationIgnored private var preparedInitialImage = false
    private static let clickZoomBehaviorKey = "clickZoomBehavior"
    private static let savedGroupsKey = "savedSettingGroups"
    private static let savedSettingsKey = "savedAppSettings"

    init(defaults: UserDefaults? = .standard) {
        // Keep persistence off until restoration is complete, including assignments made by restore().
        if let groups = defaults?.stringArray(forKey: Self.savedGroupsKey) {
            savedSettingGroups = Set(groups.compactMap(SavedSettingGroup.init(rawValue:)))
        }
        if let data = defaults?.data(forKey: Self.savedSettingsKey),
           let saved = try? JSONDecoder().decode(SavedAppSettings.self, from: data) {
            saved.restore(to: self, groups: savedSettingGroups)
            restoredImageSize = savedSettingGroups.contains(.size)
        } else if savedSettingGroups.contains(.zoom) {
            clickZoomBehavior = defaults?.string(forKey: Self.clickZoomBehaviorKey)
                .flatMap(ClickZoomBehavior.init(rawValue:)) ?? .defaultBehavior
        }
        if !savedSettingGroups.contains(.size) {
            customImageWidth = parameters.width
            customImageHeight = parameters.height
        }
        self.defaults = defaults
    }

    func saveSettings() {
        guard let defaults else { return }
        defaults.set(savedSettingGroups.map(\.rawValue).sorted(), forKey: Self.savedGroupsKey)
        let saved = SavedAppSettings(model: self, groups: savedSettingGroups)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.savedSettingsKey) }
        // The legacy key must not resurrect an opted-out zoom preference.
        defaults.removeObject(forKey: Self.clickZoomBehaviorKey)
    }

    var imageSize: CGSize? {
        guard let image else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    var renderedViewport: Viewport {
        current?.renderedViewport ?? parameters.renderViewport
    }

    // MARK: Drawing

    func drawInitialImageAfterLayoutSettles(availableSize: CGSize, displayScale: CGFloat) async {
        guard !preparedInitialImage else { return }
        // The view's task is cancelled/replaced whenever its canvas size or backing scale changes.
        do {
            try await Task.sleep(for: .milliseconds(200))
            try Task.checkCancellation()
        } catch { return }
        drawInitialImage(availableSize: availableSize, displayScale: displayScale)
    }

    /// Prepare once, from the real canvas rather than an assumed full-screen device size.
    /// In particular, this respects iPad multitasking and the screen's Retina backing scale.
    func drawInitialImage(availableSize: CGSize, displayScale: CGFloat) {
        guard !preparedInitialImage, availableSize.width.isFinite, availableSize.height.isFinite,
              availableSize.width > 0, availableSize.height > 0 else { return }
        preparedInitialImage = true
        guard image == nil, !isRendering else { return }
        let startup = ExampleCatalog.startupParameters
        let outputUnchanged = parameters.width == startup.width && parameters.height == startup.height
            && parameters.antiAlias == startup.antiAlias
        if !restoredImageSize && outputUnchanged {
            let size = StartupSizing.imageSize(availableSize: availableSize, displayScale: displayScale,
                aspectRatio: CGFloat(parameters.viewport.width / parameters.viewport.height))
            customImageWidth = Int(size.width)
            customImageHeight = Int(size.height)
            var p = parameters
            p.width = customImageWidth
            p.height = customImageHeight
            p.antiAlias = 1
            parameters = p
        }
        draw()
    }

    func draw() {
        guard FractalImage.isFormulaAvailable(parameters.formula) else {
            message = "Formula \(parameters.formula) is not available."
            return
        }
        guard FractalImage.userRenders.contains(parameters.render) else {
            message = "Render \(parameters.render) has not been ported to the GPU yet."
            return
        }
        guard FractalImage.precisionIsAdequate(for: parameters, backend: renderingBackend) else {
            message = renderingBackend == .metal
                ? "Zoom is beyond single-precision GPU accuracy; try CPU rendering for deeper zooms."
                : "Zoom is beyond double-precision CPU accuracy; the image will look blocky."
            return drawAfterWarning()
        }
        message = nil
        startRender()
    }

    /// Still draws, but keeps the precision warning visible in the status bar.
    private func drawAfterWarning() {
        let warning = message
        startRender()
        message = warning
    }

    private func startRender() {
        selection = nil
        token?.cancel()
        let token = CancelToken()
        self.token = token
        let p = parameters
        let backend = renderingBackend
        isRendering = true
        progress = 0

        let model = self
        Task.detached(priority: .userInitiated) {
            guard let img = FractalImage(parameters: p, backend: backend) else {
                await MainActor.run {
                    guard model.token === token else { return }
                    model.isRendering = false
                    model.message = backend == .metal
                        ? "Metal is not available, or the image is too large for GPU memory. Try disabling Use Metal GPU Rendering in the Image menu."
                        : "The image is too large for CPU memory."
                }
                return
            }
            let isCurrent = await MainActor.run { () -> Bool in
                guard model.token === token else { return false }
                model.current = img
                return true
            }
            guard isCurrent else { return }

            let band = max(4, img.height / 24)
            var done = 0
            var finished = true
            while done < img.height {
                let rows = done..<min(img.height, done + band)
                guard img.compute(rows: rows, cancel: token) else { finished = false; break }
                img.colorize(rows: rows, with: p)
                done = rows.upperBound
                let cg = img.makeCGImage()
                let fraction = Double(done) / Double(img.height)
                let keepGoing = await MainActor.run { () -> Bool in
                    guard model.token === token else { return false }
                    model.image = cg
                    model.imageParameters = p
                    model.progress = fraction
                    return true
                }
                if !keepGoing { finished = false; break }
            }
            let completed = finished
            let failure = img.lastError?.localizedDescription
            await MainActor.run {
                guard model.token === token else { return }
                model.isRendering = false
                if completed { model.progress = 1 }
                if let failure, !completed { model.message = failure }
                model.recolor()
            }
        }
    }

    func abort() {
        token?.cancel()
        token = nil
        isRendering = false
    }

    /// Re-applies colour settings to the stored field without iterating again.
    func recolor() {
        guard let img = current, !isRendering else { return }
        if colorBusy { colorDirty = true; return }
        colorBusy = true
        colorDirty = false
        let p = parameters
        colorQueue.async { [weak self] in
            img.colorizeAll(with: p)
            let cg = img.makeCGImage()
            Task { @MainActor in
                guard let self else { return }
                if self.current === img {
                    self.image = cg
                    var displayed = img.parameters
                    displayed.blend = p.blend
                    displayed.rgbOrder = p.rgbOrder
                    displayed.renderScale = p.renderScale
                    displayed.colors = p.colors
                    self.imageParameters = displayed
                }
                self.colorBusy = false
                if self.colorDirty { self.recolor() }
            }
        }
    }

    // MARK: Menu actions

    func chooseExample(_ example: BundledExample) {
        do {
            var p = try example.parameters()
            // Examples choose the fractal, not the user's output resolution or quality setting.
            p.width = parameters.width
            p.height = parameters.height
            p.antiAlias = parameters.antiAlias
            guard FractalImage.isFormulaAvailable(p.formula), FractalImage.userRenders.contains(p.render) else {
                message = "\(example.title) uses a formula or render that is not available."
                return
            }
            abort()
            zoomHistory.removeAll()
            selection = nil
            current = nil
            image = nil
            imageParameters = nil
            pictureHasParameters = false
            parameters = p
            draw()
        } catch {
            message = "Could not load \(example.title): \(error.localizedDescription)"
        }
    }

    func setUseMetal(_ enabled: Bool) {
        let backend: RenderingBackend = enabled ? .metal : .cpu
        guard backend != renderingBackend else { return }
        renderingBackend = backend
        draw()
    }

    func chooseFormula(_ id: Int) {
        guard FractalImage.isFormulaAvailable(id) else { return }
        parameters.formula = id
        if id == classicMandelbrotFormulaID { parameters.fitAspect = true }
        draw()
    }

    func chooseRender(_ id: Int) {
        guard FractalImage.userRenders.contains(id) else { return }
        parameters.render = id
        draw()
    }

    func chooseTransform(_ id: Int) {
        parameters.orbitTransform = id
        draw()
    }

    /// Lyapunov maps are formulas 101...120 and only make sense with renders 30...32, so the render follows.
    func chooseLyapunovMap(_ id: Int) {
        guard Catalog.lyapunovMaps.contains(where: { $0.id == id }) else { return }
        var p = parameters
        p.formula = 100 + id
        if !(30...32).contains(p.render) { p.render = 30 }
        parameters = p
        draw()
    }

    func setLyapunovEnabled(_ enabled: Bool) {
        guard enabled != isLyapunovEnabled else { return }
        if enabled {
            chooseLyapunovMap(selectedLyapunovMap)
            return
        }
        // Only replace Lyapunov components; preserve any ordinary choice made in the meantime.
        var p = parameters
        if (101...120).contains(p.formula) { p.formula = lastNonLyapunovFormula }
        if (30...32).contains(p.render) { p.render = lastNonLyapunovRender }
        parameters = p
        draw()
    }

    func clearLyapunovSettings() {
        guard isLyapunovEnabled else { return }
        var p = parameters
        if (101...120).contains(p.formula) { p.formula = lastNonLyapunovFormula }
        if (30...32).contains(p.render) { p.render = lastNonLyapunovRender }
        p.lyapunovDerivative = FractalParameters().lyapunovDerivative
        p.lyapunovMapping = FractalParameters().lyapunovMapping
        parameters = p
        lastLyapunovMap = 1
        draw()
    }

    func chooseLyapunovDerivative(_ id: Int) {
        parameters.lyapunovDerivative = id
        draw()
    }

    func chooseLyapunovMapping(_ id: Int) {
        parameters.lyapunovMapping = id
        draw()
    }

    func chooseBlend(_ id: Int) {
        parameters.blend = id
        recolor()
    }

    func chooseRGBOrder(_ id: Int) {
        parameters.rgbOrder = id
        recolor()
    }

    func setJuliaMode(_ on: Bool) {
        zoomHistory.removeAll()
        parameters.juliaMode = on
        if on { parameters.viewport = Viewport(xMin: -2, xMax: 2, yMin: -1.5, yMax: 1.5) }
        draw()
    }

    func setInsideOut(_ on: Bool) {
        parameters.insideOut = on
        draw()
    }

    func resetCoordinates() {
        zoomHistory.removeAll()
        parameters.fitAspect = true
        parameters.viewport = parameters.juliaMode
            ? Viewport(xMin: -2, xMax: 2, yMin: -1.5, yMax: 1.5)
            : .default
        draw()
    }

    func setSize(width: Int, height: Int) {
        customImageWidth = min(max(width, 16), 8192)
        customImageHeight = min(max(height, 16), 8192)
        parameters.width = customImageWidth
        parameters.height = customImageHeight
        draw()
    }

    func setPresetSize(width: Int, height: Int) {
        parameters.width = min(max(width, 16), 8192)
        parameters.height = min(max(height, 16), 8192)
        draw()
    }

    func setAntiAlias(_ factor: Int) {
        parameters.antiAlias = factor
        draw()
    }

    /// Image menu Rotate90 (1), Rotate90Mirror (2), Mirror (3): selecting the active one clears it, as in the original.
    func toggleCoordinateFlag(_ flag: Int) {
        parameters.coordinateFlag = parameters.coordinateFlag == flag ? 0 : flag
        draw()
    }

    func setCoordinateFlag(_ flag: Int) {
        parameters.coordinateFlag = flag
        draw()
    }

    // MARK: Zooming

    private func rememberZoom() {
        // Save the original bounds, not the aspect-fitted ones, so restoring them does not accumulate rounding.
        let p = current?.parameters ?? parameters
        zoomHistory.append(ZoomState(viewport: p.viewport, fitAspect: p.fitAspect))
    }

    func goBack() {
        guard canGoBack, let previous = zoomHistory.popLast() else { return }
        parameters.viewport = previous.viewport
        parameters.fitAspect = previous.fitAspect
        draw()
    }

    /// Complex-plane coordinate under a point of the displayed picture, whether it was just rendered or loaded
    /// from a file together with its parameters.
    private func coordinate(atImagePoint point: CGPoint) -> (x: Double, y: Double)? {
        if let current { return current.coordinate(x: point.x, y: point.y) }
        guard pictureHasParameters, let size = imageSize else { return nil }
        let v = parameters.renderViewport
        return (v.xMin + point.x / size.width * v.width, v.yMin + point.y / size.height * v.height)
    }

    func zoom(atImagePoint point: CGPoint, factor: Double) {
        guard !isRendering, factor.isFinite, factor > 0, factor != 1 else { return }
        guard let c = coordinate(atImagePoint: point) else {
            message = image == nil ? nil : "This picture has no parameter file, so it cannot be zoomed."
            return
        }
        rememberZoom()
        let viewport = renderedViewport
        switch clickZoomBehavior {
        case .keepPosition:
            parameters.viewport = viewport.zoomed(about: c, factor: factor)
        case .centerClickedPoint:
            let halfWidth = viewport.width / factor / 2
            let halfHeight = viewport.height / factor / 2
            parameters.viewport = Viewport(
                xMin: c.x - halfWidth, xMax: c.x + halfWidth,
                yMin: c.y - halfHeight, yMax: c.y + halfHeight
            )
        }
        draw()
    }

    /// Small changes in magnification around the current centre, independent of the click-zoom mode.
    func smallZoom(inward: Bool) {
        guard canZoom, let size = imageSize else { return }
        zoom(atImagePoint: CGPoint(x: size.width / 2, y: size.height / 2),
             factor: inward ? smallZoomStep.factor : 1 / smallZoomStep.factor)
    }

    func zoomToSelection() {
        guard !isRendering, let rect = selection, rect.width > 2, rect.height > 2,
              let p0 = coordinate(atImagePoint: CGPoint(x: rect.minX, y: rect.minY)),
              let p1 = coordinate(atImagePoint: CGPoint(x: rect.maxX, y: rect.maxY)) else { return }
        rememberZoom()
        parameters.viewport = Viewport(xMin: p0.x, xMax: p1.x, yMin: p0.y, yMax: p1.y)
        draw()
    }

    // MARK: Files

    /// PNG and JPEG carry the displayed picture's settings as XMP; BMP has no portable metadata support.
    func imageData(as format: ImageFormat) -> Data? {
        guard let image else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else { return nil }
        var options: [CFString: Any] = [:]
        if format == .jpeg { options[kCGImageDestinationLossyCompressionQuality] = 0.95 }
        if format.supportsSettings, let imageParameters {
            guard let metadata = ImageSettings.metadata(for: imageParameters) else { return nil }
            CGImageDestinationAddImageAndMetadata(dest, image, metadata, options as CFDictionary)
        } else {
            CGImageDestinationAddImage(dest, image, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    func saveImage(as format: ImageFormat) {
        guard let data = imageData(as: format) else {
            message = "Could not encode the image and its settings."
            return
        }
        imageFormat = format
        imageExportData = data
        if !format.supportsSettings {
            message = "BMP saves pixels only. Use PNG or JPEG to include settings, or export a .loo file separately."
        }
        showingImageExporter = true
    }

    func parametersData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(parameters)) ?? Data()
    }

    /// The parameters in Sterling's own .loo format.
    func looData() -> Data {
        Data(LooFile.serialize(parameters).utf8)
    }

    /// Opens any mix of picture, Sterling .loo and JSON files. A picture is shown as it is; parameters, whether they
    /// come from embedded metadata, a .loo or JSON picked with it, or a .loo next to it, are loaded so that Draw
    /// re-renders it. Parameters alone are drawn straight away.
    func open(urls: [URL]) {
        var accessed: [URL] = []
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
        func read(_ url: URL) -> Data? {
            if url.startAccessingSecurityScopedResource() { accessed.append(url) }
            return try? Data(contentsOf: url)
        }

        var loadedParameters: FractalParameters?
        var embeddedParameters: FractalParameters?
        var picture: CGImage?
        var pictureURL: URL?
        var problems: [String] = []

        for url in urls {
            guard let data = read(url) else {
                problems.append("Could not read \(url.lastPathComponent).")
                continue
            }
            switch FileKind(data: data) {
            case .sterling(let text):
                do { loadedParameters = try LooFile.parse(text, base: parameters) }
                catch { problems.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            case .json:
                do { loadedParameters = try JSONDecoder().decode(FractalParameters.self, from: data) }
                catch { problems.append("\(url.lastPathComponent) is not a parameter file this app can read.") }
            case .picture(let cg, let settings):
                if picture == nil { picture = cg; pictureURL = url; embeddedParameters = settings }
            case .unknown:
                problems.append("\(url.lastPathComponent) is not a picture or a parameter file.")
            }
        }

        // An explicitly selected parameter file overrides embedded settings; embedded settings beat a sibling file.
        let usingEmbedded = loadedParameters == nil && embeddedParameters != nil
        if loadedParameters == nil { loadedParameters = embeddedParameters }

        // The original opens a picture and then looks for a .loo with the same name beside it. A sandboxed app only
        // sees that file if it was granted, so this is best effort; picking both files together always works.
        var foundBeside = false
        if picture != nil, loadedParameters == nil, let pictureURL {
            for ext in ["loo", "LOO"] {
                let sibling = pictureURL.deletingPathExtension().appendingPathExtension(ext)
                if let data = try? Data(contentsOf: sibling), case .sterling(let text) = FileKind(data: data),
                   let parsed = try? LooFile.parse(text, base: parameters) {
                    loadedParameters = parsed
                    foundBeside = true
                    break
                }
            }
        }

        if picture != nil || loadedParameters != nil { zoomHistory.removeAll() }

        if var p = loadedParameters {
            if let picture {
                // A .loo does not store the image size; the picture's own size is the natural one.
                p.width = picture.width
                p.height = picture.height
            }
            parameters = p
        }

        if let picture {
            abort()
            current = nil
            image = picture
            selection = nil
            pictureHasParameters = loadedParameters != nil
            imageParameters = loadedParameters.map { _ in parameters }
            if loadedParameters != nil {
                message = (usingEmbedded ? "Loaded the picture and its embedded settings. " :
                    foundBeside ? "Loaded the picture and the parameter file beside it. " : "Loaded the picture and its parameters. ")
                    + "Press Draw to render it again."
            } else {
                message = "Loaded a picture with no parameters (pick its .loo file together with it, or use File > Open on the .loo). Draw replaces it."
            }
        } else if loadedParameters != nil {
            message = nil
            draw()
        }
        if !problems.isEmpty { message = problems.joined(separator: " ") }
    }
}

/// What a picked file turned out to be.
private enum FileKind {
    case sterling(String)
    case json
    case picture(CGImage, FractalParameters?)
    case unknown

    init(data: Data) {
        let prefix = String(decoding: data.prefix(64), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if LooFile.looksLike(prefix) {
            self = .sterling(String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? "")
        } else if prefix.hasPrefix("{") {
            self = .json
        } else if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            self = .picture(cg, ImageSettings.parameters(from: source))
        } else {
            self = .unknown
        }
    }
}
