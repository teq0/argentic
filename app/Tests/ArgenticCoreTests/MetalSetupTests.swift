import XCTest
@testable import ArgenticCore

final class MetalSetupTests: XCTestCase {
    func testShaderLibraryCompiles() throws {
        switch MetalContext.shared {
        case .success: break
        case .failure(let error): XCTFail("\(error)")
        }
    }

    func testEveryFormulaSpecialises() throws {
        let context = try MetalContext.shared.get()
        for formula in GeneratedFormulas.implemented + [classicMandelbrotFormulaID] {
            XCTAssertNoThrow(try context.fieldPipeline(formula: formula, render: 1, transform: 0), "formula \(formula)")
        }
    }

    /// Every render reduces orbits in its own code path (streaming, or array mode for 3 and 6...32); each must
    /// compile all the way to GPU code, with and without a transform, for DLL formulas and Lyapunov ones.
    func testEveryRenderSpecialises() throws {
        let context = try MetalContext.shared.get()
        for render in 0...32 {
            for formula in [0, 28, classicMandelbrotFormulaID, 101, 120] {
                for transform in [0, 3] {
                    XCTAssertNoThrow(try context.fieldPipeline(formula: formula, render: render, transform: transform),
                                     "formula \(formula) render \(render) transform \(transform)")
                }
            }
        }
    }
}
