import CoreGraphics
import Foundation
import Metal

public enum RenderingBackend: String, Codable, CaseIterable, Sendable {
    case metal
    case cpu
}

/// Thread-safe flag used to abort an in-flight render ("Abort" toolbar button).
public final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

// These mirror the structs in MetalShaderSource field-for-field (scalars only, so no padding surprises).
private struct FieldParams {
    var xMin: Float
    var yMin: Float
    var dx: Float
    var dy: Float
    var fieldWidth: Int32
    var rowStart: Int32
    var rowCount: Int32
    var maxIterations: Int32
    var juliaX: Float
    var juliaY: Float
    var trapRadius: Float
    var juliaMode: Int32
    var insideOut: Int32
    var scale: Float
    var lyMapping: Int32
    var lyDerivative: Int32
    var coordFlag: Int32
    var orbitStride: UInt32
}

private struct ColorParams {
    var step: SIMD4<Float>
    var start: SIMD4<Float>
    var saturation: SIMD4<Float>
    var offset: SIMD4<Float>
    var renderScale: Float
    var xMin: Float
    var yMin: Float
    var dx: Float
    var dy: Float
    var blend: Int32
    var rgbOrder: Int32
    var sampling: Int32
    var fieldWidth: Int32
    var width: Int32
    var rowStart: Int32
    var rowCount: Int32
}

public struct RGB: Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
}

/// One rendered image, using either Metal compute kernels or the double-precision CPU backend.
///
/// Iteration is the expensive step, so the field is kept: changing blend, RGB order, colour
/// controls or render scale only re-runs `colorize`, never `compute`.
public final class FractalImage: @unchecked Sendable {
    public enum RenderError: Error, LocalizedError {
        case unsupported(String)
        case gpu(String)
        case cpu(String)

        public var errorDescription: String? {
            switch self {
            case .unsupported(let message), .gpu(let message), .cpu(let message): return message
            }
        }
    }

    public static let maxFieldPixels = 24_000_000

    /// Keeps one GPU command well under the OS watchdog (~ a few seconds): pixels × iterations per command.
    private static let workBudget = 400_000_000.0

    public let parameters: FractalParameters
    public let backend: RenderingBackend
    public let width: Int
    public let height: Int
    /// Super-sampling factor actually used (the requested value, reduced to fit memory).
    public let sampling: Int
    public private(set) var lastError: Error?

    private let context: MetalContext?
    private let cpu: CPUImage?
    private let fieldWidth: Int
    private let fieldHeight: Int
    private let viewport: Viewport
    private let fieldBuffer: MTLBuffer?
    private let pixelBuffer: MTLBuffer?

    /// Render 0 is an internal debug mode that outputs the last orbit point; it is not a user render.
    public static func supports(formula: Int, render: Int) -> Bool {
        isFormulaAvailable(formula) && (0...32).contains(render)
    }

    /// DLL formulas 0...55, Classic Mandelbrot 56, and Lyapunov maps 101...120.
    public static func isFormulaAvailable(_ formula: Int) -> Bool {
        GeneratedFormulas.implemented.contains(formula) || formula == classicMandelbrotFormulaID || (101...120).contains(formula)
    }

    /// Renders that read the whole orbit, and every Lyapunov formula, need a per-thread orbit array.
    public static func usesOrbit(formula: Int, render: Int) -> Bool {
        formula >= 100 || render == 3 || render >= 6
    }

    /// Scratch memory for orbit arrays; bands are shrunk to fit.
    private static let orbitBudget = 192 * 1024 * 1024

    /// The renders offered in the UI: all of the original's 1...32.
    public static let userRenders: Set<Int> = Set(1...32)

    public static func effectiveSampling(for p: FractalParameters) -> Int {
        var k = max(1, min(p.antiAlias, 4))
        while k > 1 && p.width * p.height * k * k > maxFieldPixels { k -= 1 }
        return k
    }

    /// Flags views whose pixel pitch approaches the spacing of the selected backend's floating-point type.
    public static func precisionIsAdequate(for p: FractalParameters, backend: RenderingBackend = .metal) -> Bool {
        let v = p.renderViewport
        let pitch = v.width / Double(max(p.width, 1) * effectiveSampling(for: p))
        let magnitude = max(abs(v.xMin), abs(v.xMax), abs(v.yMin), abs(v.yMax), Double.leastNormalMagnitude)
        let epsilon = backend == .metal ? Double(Float.ulpOfOne) : Double.ulpOfOne
        return pitch > magnitude * epsilon * 8
    }

    public init?(parameters: FractalParameters, backend: RenderingBackend = .metal) {
        guard (1...8192).contains(parameters.width), (1...8192).contains(parameters.height),
              parameters.maxIterations > 0, parameters.maxIterations <= Int(Int32.max) - 2 else { return nil }
        self.parameters = parameters
        self.backend = backend
        width = max(1, parameters.width)
        height = max(1, parameters.height)
        sampling = FractalImage.effectiveSampling(for: parameters)
        fieldWidth = width * sampling
        fieldHeight = height * sampling
        viewport = parameters.renderViewport

        if backend == .cpu {
            guard let cpu = CPUImage(width: width, height: height, sampling: sampling) else { return nil }
            self.cpu = cpu
            context = nil
            fieldBuffer = nil
            pixelBuffer = nil
            return
        }
        guard case .success(let context) = MetalContext.shared else { return nil }
        self.context = context
        cpu = nil

        guard let field = context.device.makeBuffer(length: fieldWidth * fieldHeight * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
              let pixels = context.device.makeBuffer(length: width * height * 4, options: .storageModeShared)
        else { return nil }
        fieldBuffer = field
        pixelBuffer = pixels
        memset(field.contents(), 0, field.length)
        memset(pixels.contents(), 0, pixels.length)
    }

    /// The fitted viewport that was actually rendered.
    public var renderedViewport: Viewport { viewport }

    /// Complex-plane coordinate at a position in output-pixel units.
    public func coordinate(x: Double, y: Double) -> (x: Double, y: Double) {
        (
            viewport.xMin + x / Double(width) * viewport.width,
            viewport.yMin + y / Double(height) * viewport.height
        )
    }

    // MARK: Dispatch helper

    private static func dispatch(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let w = pipeline.threadExecutionWidth
        let h = max(1, min(8, pipeline.maxTotalThreadsPerThreadgroup / w))
        let groups = MTLSize(width: (width + w - 1) / w, height: (height + h - 1) / h, depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
    }

    // MARK: Iteration

    private var orbitBuffer: MTLBuffer?

    /// A private (GPU-only) scratch buffer of at least `bytes`, reused between bands and calls.
    private func orbitScratch(bytes: Int) -> MTLBuffer? {
        if let existing = orbitBuffer, existing.length >= bytes { return existing }
        orbitBuffer = context?.device.makeBuffer(length: bytes, options: .storageModePrivate)
        return orbitBuffer
    }

    /// Iterates output rows `rows`. Returns false if cancelled or if the GPU reported an error.
    @discardableResult
    public func compute(rows: Range<Int>, cancel: CancelToken) -> Bool {
        let p = parameters
        guard FractalImage.supports(formula: p.formula, render: p.render) else {
            lastError = RenderError.unsupported("Formula \(p.formula) with render \(p.render) is not available.")
            return false
        }
        if let cpu {
            let ok = cpu.compute(rows: rows, parameters: p, cancel: cancel)
            if !ok && !cancel.isCancelled { lastError = RenderError.cpu("CPU rendering failed; try lowering the iterations or image size.") }
            return ok
        }
        guard let context, let fieldBuffer else { return false }
        let pipeline: MTLComputePipelineState
        do {
            pipeline = try context.fieldPipeline(formula: p.formula, render: p.render, transform: p.orbitTransform)
        } catch {
            lastError = error
            return false
        }

        let k = sampling
        let firstRow = rows.lowerBound * k
        let endRow = rows.upperBound * k
        let perRow = Double(fieldWidth) * Double(max(p.maxIterations, 1))
        var bandRows = max(1, Int(FractalImage.workBudget / perRow))

        // Renders that read the whole orbit keep it in a scratch buffer: element i of thread t at i * stride + t.
        let usesOrbit = FractalImage.usesOrbit(formula: p.formula, render: p.render)
        let orbitBytesPerRow = fieldWidth * (max(p.maxIterations, 1) + 2) * MemoryLayout<SIMD2<Float>>.stride
        if usesOrbit { bandRows = min(bandRows, max(1, FractalImage.orbitBudget / orbitBytesPerRow)) }
        guard let scratch = orbitScratch(bytes: usesOrbit ? bandRows * orbitBytesPerRow : 16) else {
            lastError = RenderError.gpu("Not enough GPU memory for the orbit scratch buffer; lower the iterations or the image size.")
            return false
        }

        var row = firstRow
        while row < endRow {
            if cancel.isCancelled { return false }
            let count = min(bandRows, endRow - row)
            var params = FieldParams(
                xMin: Float(viewport.xMin),
                yMin: Float(viewport.yMin),
                dx: Float(viewport.width / Double(fieldWidth)),
                dy: Float(viewport.height / Double(fieldHeight)),
                fieldWidth: Int32(fieldWidth),
                rowStart: Int32(row),
                rowCount: Int32(count),
                maxIterations: Int32(p.maxIterations),
                juliaX: Float(p.juliaX),
                juliaY: Float(p.juliaY),
                trapRadius: Float(p.trapRadius),
                juliaMode: p.juliaMode ? 1 : 0,
                insideOut: p.insideOut ? 1 : 0,
                scale: Float(p.scaleFactor),
                lyMapping: Int32(p.lyapunovMapping),
                lyDerivative: Int32(p.lyapunovDerivative),
                coordFlag: Int32(p.coordinateFlag),
                orbitStride: UInt32(count * fieldWidth)
            )
            guard let cmd = context.queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else {
                lastError = RenderError.gpu("Could not create a Metal command buffer.")
                return false
            }
            enc.setComputePipelineState(pipeline)
            enc.setBytes(&params, length: MemoryLayout<FieldParams>.stride, index: 0)
            enc.setBuffer(fieldBuffer, offset: 0, index: 1)
            enc.setBuffer(scratch, offset: 0, index: 2)
            FractalImage.dispatch(enc, pipeline, width: fieldWidth, height: count)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            if let error = cmd.error {
                lastError = RenderError.gpu("GPU error: \(error.localizedDescription)")
                return false
            }
            row += count
        }
        return !cancel.isCancelled
    }

    // MARK: Colouring

    /// Colours output rows `rows` from the stored field using `colorParameters`.
    public func colorize(rows: Range<Int>, with colorParameters: FractalParameters) {
        if let cpu {
            cpu.colorize(rows: rows, parameters: colorParameters, viewport: viewport)
            return
        }
        guard let context, let fieldBuffer, let pixelBuffer else { return }
        let c = colorParameters.colors
        // ColorControls is in R, G, B blend order; the shader's slot() undoes the original's R, B, G memory order.
        func vec(_ v: [Double]) -> SIMD4<Float> { SIMD4(Float(v[0]), Float(v[2]), Float(v[1]), 0) }
        var params = ColorParams(
            step: vec(c.step),
            start: vec(c.start),
            saturation: vec(c.saturation),
            offset: vec(c.offset),
            renderScale: Float(colorParameters.renderScale),
            xMin: Float(viewport.xMin),
            yMin: Float(viewport.yMin),
            dx: Float(viewport.width / Double(fieldWidth)),
            dy: Float(viewport.height / Double(fieldHeight)),
            blend: Int32(colorParameters.blend),
            rgbOrder: Int32(colorParameters.rgbOrder),
            sampling: Int32(sampling),
            fieldWidth: Int32(fieldWidth),
            width: Int32(width),
            rowStart: Int32(rows.lowerBound),
            rowCount: Int32(rows.count)
        )
        guard !rows.isEmpty, let cmd = context.queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(context.colorPipeline)
        enc.setBytes(&params, length: MemoryLayout<ColorParams>.stride, index: 0)
        enc.setBuffer(fieldBuffer, offset: 0, index: 1)
        enc.setBuffer(pixelBuffer, offset: 0, index: 2)
        FractalImage.dispatch(enc, context.colorPipeline, width: width, height: rows.count)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    public func colorizeAll(with colorParameters: FractalParameters) {
        colorize(rows: 0..<height, with: colorParameters)
    }

    // MARK: Output

    public func makeCGImage() -> CGImage? {
        let data: Data
        if let cpu { data = cpu.pixelData() }
        else if let pixelBuffer { data = Data(bytes: pixelBuffer.contents(), count: width * height * 4) }
        else { return nil }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: Inspection (tests)

    public func pixel(x: Int, y: Int) -> RGB {
        if let cpu { return cpu.pixel(x: x, y: y) }
        guard let pixelBuffer else { return RGB(r: 0, g: 0, b: 0) }
        let p = pixelBuffer.contents().assumingMemoryBound(to: UInt8.self)
        let o = (y * width + x) * 4
        return RGB(r: p[o], g: p[o + 1], b: p[o + 2])
    }

    /// Stored (A, B) at a field position.
    public func fieldValue(x: Int, y: Int) -> (a: Float, b: Float) {
        if let cpu {
            let value = cpu.fieldValue(x: x, y: y)
            return (Float(value.a), Float(value.b))
        }
        guard let fieldBuffer else { return (0, 0) }
        let f = fieldBuffer.contents().assumingMemoryBound(to: SIMD2<Float>.self)
        let v = f[y * fieldWidth + x]
        return (v.x, v.y)
    }

    /// Inspect CPU results without narrowing large or high-precision values to float32.
    func preciseFieldValue(x: Int, y: Int) -> (a: Double, b: Double) {
        if let cpu { return cpu.fieldValue(x: x, y: y) }
        let value = fieldValue(x: x, y: y)
        return (Double(value.a), Double(value.b))
    }

    /// Overwrites the field with explicit values so the colour stage can be tested on its own.
    func loadField(_ values: [SIMD2<Float>]) {
        precondition(values.count == fieldWidth * fieldHeight)
        if let cpu { cpu.loadField(values); return }
        guard let fieldBuffer else { return }
        _ = values.withUnsafeBytes { memcpy(fieldBuffer.contents(), $0.baseAddress!, $0.count) }
    }
}
