import ArgenticCPU
import Foundation

/// CPU-only storage and work scheduling. No Metal device, buffers, or pipelines are used.
final class CPUImage: @unchecked Sendable {
    private let storage: OpaquePointer
    private let width: Int
    private let height: Int
    private let sampling: Int

    init?(width: Int, height: Int, sampling: Int) {
        guard let storage = ArgenticCPUCreate(Int32(width), Int32(height), Int32(sampling)) else { return nil }
        self.storage = storage
        self.width = width
        self.height = height
        self.sampling = sampling
    }

    deinit { ArgenticCPUDestroy(storage) }

    func compute(rows: Range<Int>, parameters p: FractalParameters, cancel: CancelToken) -> Bool {
        guard !cancel.isCancelled else { return false }
        let viewport = p.renderViewport
        var params = ArgenticCPUFieldParams()
        params.xMin = viewport.xMin
        params.yMin = viewport.yMin
        params.dx = viewport.width / Double(width * sampling)
        params.dy = viewport.height / Double(height * sampling)
        params.juliaX = p.juliaX
        params.juliaY = p.juliaY
        params.trapRadius = p.trapRadius
        params.scale = p.scaleFactor
        params.formula = Int32(p.formula)
        params.render = Int32(p.render)
        params.transform = Int32(p.orbitTransform)
        params.maxIterations = Int32(p.maxIterations)
        params.juliaMode = p.juliaMode ? 1 : 0
        params.insideOut = p.insideOut ? 1 : 0
        params.mapping = Int32(p.lyapunovMapping)
        params.derivative = Int32(p.lyapunovDerivative)
        params.coordinateFlag = Int32(p.coordinateFlag)
        let fieldRows = (rows.lowerBound * sampling)..<(rows.upperBound * sampling)
        guard !fieldRows.isEmpty else { return true }
        // Keep per-worker orbit storage within the same scratch budget as the GPU renderer.
        let orbitBytes = FractalImage.usesOrbit(formula: p.formula, render: p.render)
            ? (max(p.maxIterations, 1) + 2) * 16 : 16
        guard orbitBytes <= 192 * 1024 * 1024 else { return false }
        let workers = min(ProcessInfo.processInfo.activeProcessorCount, fieldRows.count,
                          max(1, 192 * 1024 * 1024 / orbitBytes))
        let lock = NSLock()
        var succeeded = true
        let fieldParams = params
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            for row in stride(from: fieldRows.lowerBound + worker, to: fieldRows.upperBound, by: workers) {
                if cancel.isCancelled { break }
                let ok = ArgenticCPUComputeRow(storage, Int32(row), fieldParams, { context in
                    guard let context else { return false }
                    return Unmanaged<CancelToken>.fromOpaque(context).takeUnretainedValue().isCancelled
                }, Unmanaged.passUnretained(cancel).toOpaque())
                if !ok {
                    lock.lock()
                    succeeded = false
                    lock.unlock()
                    break
                }
            }
        }
        return succeeded && !cancel.isCancelled
    }

    func colorize(rows: Range<Int>, parameters p: FractalParameters, viewport: Viewport) {
        var params = ArgenticCPUColorParams()
        let c = p.colors
        params.step = (c.step[0], c.step[1], c.step[2])
        params.start = (c.start[0], c.start[1], c.start[2])
        params.saturation = (c.saturation[0], c.saturation[1], c.saturation[2])
        params.offset = (c.offset[0], c.offset[1], c.offset[2])
        params.renderScale = p.renderScale
        params.xMin = viewport.xMin
        params.yMin = viewport.yMin
        params.dx = viewport.width / Double(width * sampling)
        params.dy = viewport.height / Double(height * sampling)
        params.blend = Int32(p.blend)
        params.rgbOrder = Int32(p.rgbOrder)
        let colorParams = params
        DispatchQueue.concurrentPerform(iterations: rows.count) { row in
            ArgenticCPUColorizeRow(storage, Int32(rows.lowerBound + row), colorParams)
        }
    }

    func pixelData() -> Data {
        Data(bytes: ArgenticCPUPixels(storage)!, count: width * height * 4)
    }

    func pixel(x: Int, y: Int) -> RGB {
        let pixels = ArgenticCPUPixels(storage)!
        let index = (y * width + x) * 4
        return RGB(r: pixels[index], g: pixels[index + 1], b: pixels[index + 2])
    }

    func fieldValue(x: Int, y: Int) -> (a: Double, b: Double) {
        var a = 0.0, b = 0.0
        ArgenticCPUFieldValue(storage, Int32(x), Int32(y), &a, &b)
        return (a, b)
    }

    func loadField(_ values: [SIMD2<Float>]) {
        for (i, value) in values.enumerated() {
            ArgenticCPUSetFieldValue(storage, Int32(i), Double(value.x), Double(value.y))
        }
    }
}
