import Foundation

/// Per-channel colour mixing controls (Sterling's "Color Mixing Controls" dialog).
/// Channel order is R, G, B, which is also the order of the blend's three values. Defaults are the values
/// Sterling2 loads at start-up (STERLING2.EXE FUN_004a4df0: step/start 127, saturation 1, offset 0).
public struct ColorControls: Codable, Equatable, Sendable {
    public var step: [Double] = [127, 127, 127]
    public var start: [Double] = [127, 127, 127]
    public var saturation: [Double] = [1, 1, 1]
    public var offset: [Double] = [0, 0, 0]

    public init() {}
}

public struct Viewport: Codable, Equatable, Sendable {
    public var xMin: Double
    public var xMax: Double
    public var yMin: Double
    public var yMax: Double

    public init(xMin: Double, xMax: Double, yMin: Double, yMax: Double) {
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
    }

    public static let `default` = Viewport(xMin: -2.5, xMax: 1.5, yMin: -1.5, yMax: 1.5)

    public var width: Double { xMax - xMin }
    public var height: Double { yMax - yMin }

    /// Expands the shorter axis so one pixel covers the same distance in x and y.
    public func fitting(aspect: Double) -> Viewport {
        let cx = (xMin + xMax) / 2
        let cy = (yMin + yMax) / 2
        var w = width
        var h = height
        if w / h < aspect {
            w = h * aspect
        } else {
            h = w / aspect
        }
        return Viewport(xMin: cx - w / 2, xMax: cx + w / 2, yMin: cy - h / 2, yMax: cy + h / 2)
    }

    public func zoomed(about point: (x: Double, y: Double), factor: Double) -> Viewport {
        Viewport(
            xMin: point.x - (point.x - xMin) / factor,
            xMax: point.x + (xMax - point.x) / factor,
            yMin: point.y - (point.y - yMin) / factor,
            yMax: point.y + (yMax - point.y) / factor
        )
    }
}

public struct FractalParameters: Codable, Equatable, Sendable {
    // Image
    public var width = 640
    public var height = 480
    public var antiAlias = 1
    public var viewport = Viewport.default
    /// Widens the view so pixels are square. Parameter files from the original program render stretched
    /// to the image size instead, so loading one turns this off.
    public var fitAspect = true

    // Fractal
    public var formula = 28
    public var maxIterations = 100
    public var juliaMode = false
    public var juliaX = -0.7
    public var juliaY = 0.27015
    public var insideOut = false
    public var orbitTransform = 0
    /// The Image menu's Rotate90 (1), Rotate90Mirror (2) and Mirror (3), 0 for none. Despite the names these are
    /// not bitmap operations: they change the starting z and c of every pixel (1 swaps x and y, 2 swaps and
    /// negates them, 3 negates them). The original starts with 1 selected.
    public var coordinateFlag = 1
    /// "Scale Factor 4" of the original Parameters dialog; several renders and the Lyapunov maps multiply by it.
    public var scaleFactor = 1.0
    /// LMapping menu (1...9) and LDerivative menu (1...21); used by the Lyapunov formulas (101...120) and renders 30...32.
    public var lyapunovMapping = 1
    public var lyapunovDerivative = 1

    // Render (orbit -> two scalar values A and B per pixel)
    public var render = 2
    /// Radius used by the orbit-trap renders ("Stalks & Bubbles Radius").
    public var trapRadius = 0.3
    /// Multiplies A and B before colouring (the "Render" field of the colour dialog).
    public var renderScale = 1.0

    // Colour
    public var blend = 13
    public var rgbOrder = 1
    public var colors = ColorControls()

    /// The two title lines of a parameter file (they are shown nowhere in the original, only stored).
    public var title1 = ""
    public var title2 = ""

    public init() {}

    /// The view that is actually rendered for the current image size.
    public var renderViewport: Viewport {
        fitAspect ? viewport.fitting(aspect: Double(max(width, 1)) / Double(max(height, 1))) : viewport
    }

    /// Parameters that change the per-pixel A/B field. Everything else only needs re-colouring.
    public func fieldDiffers(from other: FractalParameters) -> Bool {
        var a = self
        var b = other
        a.blend = 0; b.blend = 0
        a.rgbOrder = 0; b.rgbOrder = 0
        a.colors = ColorControls(); b.colors = ColorControls()
        a.renderScale = 0; b.renderScale = 0
        return a != b
    }
}
