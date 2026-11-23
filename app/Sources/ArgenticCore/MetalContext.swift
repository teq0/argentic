import Foundation
import Metal

/// Owns the Metal device, the compiled shader library and the specialised pipelines.
///
/// The library is compiled from source on first use (a second or two for all 50 formulas); each
/// field pipeline is then specialised with function constants so it only contains the chosen
/// formula, render mode and transform.
public final class MetalContext: @unchecked Sendable {
    public enum SetupError: Error, LocalizedError {
        case noDevice
        case compile(String)

        public var errorDescription: String? {
            switch self {
            case .noDevice: return "No Metal device is available."
            case .compile(let message): return "Shader compilation failed: \(message)"
            }
        }
    }

    struct PipelineKey: Hashable {
        let formula: Int
        let render: Int
        let transform: Int
    }

    public static let shared: Result<MetalContext, Error> = Result { try MetalContext() }

    /// Starts compiling the shaders on a background thread so the first draw is not delayed.
    public static func warmUp() {
        DispatchQueue.global(qos: .utility).async { _ = shared }
    }

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let colorPipeline: MTLComputePipelineState

    private let lock = NSLock()
    private var fieldPipelines: [PipelineKey: MTLComputePipelineState] = [:]

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw SetupError.noDevice
        }
        self.device = device
        self.queue = queue

        let options = MTLCompileOptions()
        // Accurate sin/cos/exp matter more than speed: the colour stage rounds their results.
        if #available(macOS 15.0, iOS 18.0, *) {
            options.mathMode = .safe
        } else {
            options.fastMathEnabled = false
        }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: MetalShaderSource.source, options: options)
        } catch {
            throw SetupError.compile(error.localizedDescription)
        }
        self.library = library

        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else { throw SetupError.compile("missing function \(name)") }
            return try device.makeComputePipelineState(function: function)
        }
        colorPipeline = try pipeline("colorKernel")
    }

    func fieldPipeline(formula: Int, render: Int, transform: Int) throws -> MTLComputePipelineState {
        let key = PipelineKey(formula: formula, render: render, transform: transform)
        lock.lock()
        if let cached = fieldPipelines[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let constants = MTLFunctionConstantValues()
        var values = [Int32(formula), Int32(render), Int32(transform)]
        for index in 0..<3 {
            constants.setConstantValue(&values[index], type: .int, index: index)
        }
        let function = try library.makeFunction(name: "fieldKernel", constantValues: constants)
        let state = try device.makeComputePipelineState(function: function)

        lock.lock()
        fieldPipelines[key] = state
        lock.unlock()
        return state
    }
}
