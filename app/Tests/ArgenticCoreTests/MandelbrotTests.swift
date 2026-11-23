import XCTest
@testable import ArgenticCore

final class MandelbrotTests: XCTestCase {
    private func parameters() -> FractalParameters {
        var p = FractalParameters()
        p.formula = classicMandelbrotFormulaID
        p.render = 1
        p.coordinateFlag = 0
        p.juliaMode = false
        p.insideOut = false
        p.orbitTransform = 0
        p.maxIterations = 128
        return p
    }

    private func point(_ x: Double, _ y: Double, backend: RenderingBackend, render: Int = 1) throws -> FractalImage {
        var p = parameters()
        p.width = 1
        p.height = 1
        p.fitAspect = false
        p.viewport = Viewport(xMin: x, xMax: x + 1, yMin: y, yMax: y + 1)
        p.render = render
        let image = try XCTUnwrap(FractalImage(parameters: p, backend: backend))
        XCTAssertTrue(image.compute(rows: 0..<1, cancel: CancelToken()))
        return image
    }

    func testKnownInteriorAndExteriorPointsOnBothBackends() throws {
        for backend in RenderingBackend.allCases {
            for c in [(0.0, 0.0), (-1.0, 0.0), (-2.0, 0.0), (0.25, 0.0), (0.0, 1.0)] {
                let image = try point(c.0, c.1, backend: backend)
                XCTAssertEqual(image.preciseFieldValue(x: 0, y: 0).a, 0, "\(backend), \(c)")
            }
            for (c, count) in [((3.0, 0.0), 2.0), ((2.0, 0.0), 3.0), ((1.0, 0.0), 4.0), ((1e20, 1e20), 2.0)] {
                let image = try point(c.0, c.1, backend: backend)
                XCTAssertEqual(image.preciseFieldValue(x: 0, y: 0).a, log(count), accuracy: 1e-6, "\(backend), \(c)")
            }
        }
    }

    func testBlackInteriorForEveryBlend() throws {
        for backend in RenderingBackend.allCases {
            let image = try point(0, 0, backend: backend)
            var p = image.parameters
            for blend in 1...26 {
                p.blend = blend
                image.colorizeAll(with: p)
                XCTAssertEqual(image.pixel(x: 0, y: 0), RGB(r: 0, g: 0, b: 0), "\(backend), blend \(blend)")
            }
        }
    }

    func testOrbitReallyStartsAtZeroAndUsesQuadraticRecurrence() throws {
        for backend in RenderingBackend.allCases {
            // c = 1: 0 -> 1 -> 2 -> 5, escaping strictly beyond |z| = 2.
            let image = try point(1, 0, backend: backend, render: 0)
            XCTAssertEqual(image.preciseFieldValue(x: 0, y: 0).a, 5, accuracy: 1e-12)
            XCTAssertEqual(image.preciseFieldValue(x: 0, y: 0).b, 0, accuracy: 1e-12)
        }
    }

    func testIndependentScalarReferenceAcrossWholeView() throws {
        var p = parameters()
        p.width = 64
        p.height = 48
        p.maxIterations = 64
        let viewport = p.renderViewport
        for backend in RenderingBackend.allCases {
            let image = try XCTUnwrap(FractalImage(parameters: p, backend: backend))
            XCTAssertTrue(image.compute(rows: 0..<p.height, cancel: CancelToken()))
            var matched = 0
            for y in 0..<p.height {
                for x in 0..<p.width {
                    let cx = viewport.xMin + Double(x) * viewport.width / Double(p.width)
                    let cy = viewport.yMin + Double(y) * viewport.height / Double(p.height)
                    let expected = scalar(cx, cy, p: p)
                    let value = image.preciseFieldValue(x: x, y: y).a
                    if abs(value - expected) < 1e-6 { matched += 1 }
                }
            }
            let required = backend == .cpu ? 0.999 : 0.97
            XCTAssertGreaterThanOrEqual(Double(matched) / Double(p.width * p.height), required, "\(backend)")
        }
    }

    func testQuadraticJuliaModeUsesPixelAsInitialZ() throws {
        var p = parameters()
        p.width = 16
        p.height = 12
        p.juliaMode = true
        p.maxIterations = 32
        let v = p.renderViewport
        for backend in RenderingBackend.allCases {
            let image = try XCTUnwrap(FractalImage(parameters: p, backend: backend))
            XCTAssertTrue(image.compute(rows: 0..<p.height, cancel: CancelToken()))
            var matched = 0
            for y in 0..<p.height {
                for x in 0..<p.width {
                    let expected = scalar(v.xMin + Double(x) * v.width / Double(p.width),
                        v.yMin + Double(y) * v.height / Double(p.height), p: p)
                    if abs(image.preciseFieldValue(x: x, y: y).a - expected) < 1e-6 { matched += 1 }
                }
            }
            XCTAssertGreaterThanOrEqual(Double(matched) / Double(p.width * p.height), 0.97)
        }
    }

    func testClassicSupportsOrbitReadingRendersAndCancellation() throws {
        for backend in RenderingBackend.allCases {
            var p = parameters()
            p.width = 8
            p.height = 8
            p.maxIterations = 16
            for render in [3, 6, 14, 29] {
                p.render = render
                let image = try XCTUnwrap(FractalImage(parameters: p, backend: backend))
                XCTAssertTrue(image.compute(rows: 0..<8, cancel: CancelToken()))
                image.colorizeAll(with: p)
                XCTAssertNotNil(image.makeCGImage())
                let cancelled = CancelToken()
                cancelled.cancel()
                XCTAssertFalse(image.compute(rows: 0..<8, cancel: cancelled))
            }
        }
    }

    func testCatalogAndParameterFilesKeepLegacyZeroDistinctFromClassic() throws {
        XCTAssertEqual(Catalog.formulas.first { $0.id == 0 }?.title, "Nova/Newton variation (sin/log/tan)")
        XCTAssertTrue(FractalImage.isFormulaAvailable(0))
        XCTAssertTrue(FractalImage.isFormulaAvailable(classicMandelbrotFormulaID))
        XCTAssertTrue(Catalog.formulas.contains { $0.id == classicMandelbrotFormulaID && $0.title.contains("Classic Mandelbrot") })
        for formula in [0, classicMandelbrotFormulaID] {
            var p = parameters()
            p.formula = formula
            XCTAssertEqual(try LooFile.parse(LooFile.serialize(p)).formula, formula)
            XCTAssertEqual(try JSONDecoder().decode(FractalParameters.self, from: JSONEncoder().encode(p)), p)
        }
    }

    func testClassicGroupIsLastAndSharedIDMatchesShader() throws {
        let group = try XCTUnwrap(Catalog.formulaGroups.last)
        XCTAssertEqual(group.title, "Classic")
        XCTAssertEqual(group.range, classicMandelbrotFormulaID...classicMandelbrotFormulaID)
        XCTAssertTrue(MetalShaderSource.source.contains("constant int kClassicMandelbrotFormulaID = \(classicMandelbrotFormulaID);"))
    }

    /// Independent scalar implementation: no generated formulas, orbit helpers or analytic shortcuts.
    private func scalar(_ x: Double, _ y: Double, p: FractalParameters) -> Double {
        let cx = p.juliaMode ? p.juliaX : x
        let cy = p.juliaMode ? p.juliaY : y
        var zx = p.juliaMode ? x : 0
        var zy = p.juliaMode ? y : 0
        let radiusSquared = p.juliaMode ? max(4, cx * cx + cy * cy) : 4
        for iteration in 1...p.maxIterations {
            let nextX = zx * zx - zy * zy + cx
            zy = zx * zy + zy * zx + cy
            zx = nextX
            if !zx.isFinite || !zy.isFinite || zx * zx + zy * zy > radiusSquared {
                return log(Double(iteration + 1))
            }
        }
        return 0
    }
}
