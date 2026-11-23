import XCTest
@testable import ArgenticCore

final class CPURendererTests: XCTestCase {
    func testShortOrbitsAgainstExistingDoublePrecisionOracle() throws {
        let fixture = try OracleTests.loadFixture()
        var failures: [String] = []
        for c in fixture.cases {
            var p = OracleTests.parameters(for: fixture, case: c, render: 0)
            p.maxIterations = 4
            let image = try XCTUnwrap(FractalImage(parameters: p, backend: .cpu))
            XCTAssertEqual(image.backend, .cpu)
            XCTAssertTrue(image.compute(rows: 0..<p.height, cancel: CancelToken()))
            var compared = 0, matched = 0
            for i in c.lastX.indices {
                guard let x = c.lastX[i], let y = c.lastY[i], abs(x) < 1e4, abs(y) < 1e4 else { continue }
                compared += 1
                let value = image.preciseFieldValue(x: i % p.width, y: i / p.width)
                let tolerance = 2e-5 * max(1, abs(x), abs(y))
                if abs(Double(value.a) - x) <= tolerance && abs(Double(value.b) - y) <= tolerance { matched += 1 }
            }
            if compared > 0 && Double(matched) / Double(compared) < 0.97 {
                failures.append("formula \(c.formula), Julia \(c.julia), inside-out \(c.insideOut): \(matched)/\(compared)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testAllRendersAndLyapunovSettingsAgainstExistingOracle() throws {
        let fixture = try RenderTests.loadFixture()
        var failures: [String] = []
        for c in fixture.cases {
            var p = FractalParameters()
            p.width = fixture.width
            p.height = fixture.height
            p.trapRadius = fixture.trapRadius
            p.maxIterations = c.maxit
            p.formula = c.formula
            p.render = c.render
            p.lyapunovMapping = c.mapping
            p.lyapunovDerivative = c.derivative
            p.coordinateFlag = 0
            let image = try XCTUnwrap(FractalImage(parameters: p, backend: .cpu))
            XCTAssertTrue(image.compute(rows: 0..<p.height, cancel: CancelToken()))
            var compared = 0, matched = 0
            for i in c.a.indices {
                guard let a = c.a[i], let b = c.b[i] else { continue }
                compared += 1
                let value = image.preciseFieldValue(x: i % p.width, y: i / p.width)
                if abs(Double(value.a) - a) <= 1e-5 * max(1, abs(a)) &&
                    abs(Double(value.b) - b) <= 1e-5 * max(1, abs(b)) { matched += 1 }
            }
            if compared > 0 && Double(matched) / Double(compared) < 0.99 {
                failures.append("formula \(c.formula), render \(c.render), mapping \(c.mapping), derivative \(c.derivative): \(matched)/\(compared)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testEveryColourAndRGBOrderAgainstCPUReference() throws {
        var p = FractalParameters()
        p.width = 8
        p.height = 8
        p.colors.step = [100, 120, 90]
        p.colors.start = [127, 100, 140]
        p.colors.saturation = [1.2, 0.9, 1.5]
        p.colors.offset = [10, -20, 30]
        p.renderScale = 1.5
        let image = try XCTUnwrap(FractalImage(parameters: p, backend: .cpu))
        let values = (0..<64).map { i in SIMD2<Float>(Float(i % 13) / 4, Float(i % 7) / 3) }
        image.loadField(values)
        let v = image.renderedViewport
        for blend in 1...26 {
            for order in 1...6 {
                p.blend = blend
                p.rgbOrder = order
                image.colorizeAll(with: p)
                for i in values.indices {
                    let x = i % 8, y = i / 8
                    let expected = ReferenceColorizer.color(a: Double(values[i].x), b: Double(values[i].y),
                        pixel: (v.xMin + Double(x) * v.width / 8, v.yMin + Double(y) * v.height / 8), parameters: p)
                    XCTAssertEqual(image.pixel(x: x, y: y), RGB(r: expected.r, g: expected.g, b: expected.b),
                                   "blend \(blend), order \(order), pixel \(i)")
                }
            }
        }
    }

    func testCPUAntiAliasingAveragesSubsamplesAndRecoloursWithoutComputing() throws {
        var p = FractalParameters()
        p.width = 2
        p.height = 2
        p.antiAlias = 2
        let image = try XCTUnwrap(FractalImage(parameters: p, backend: .cpu))
        let values = (0..<16).map { SIMD2<Float>(Float($0) / 8, Float($0) / 4) }
        image.loadField(values)
        let view = image.renderedViewport
        image.colorizeAll(with: p)
        var r = 0, g = 0, b = 0
        for y in 0..<2 {
            for x in 0..<2 {
                let ab = values[y * 4 + x]
                let c = ReferenceColorizer.color(a: Double(ab.x), b: Double(ab.y),
                    pixel: (view.xMin + Double(x) * view.width / 4, view.yMin + Double(y) * view.height / 4), parameters: p)
                r += Int(c.r); g += Int(c.g); b += Int(c.b)
            }
        }
        let before = image.pixel(x: 0, y: 0)
        XCTAssertEqual(before, RGB(r: UInt8(r / 4), g: UInt8(g / 4), b: UInt8(b / 4)))
        p.rgbOrder = 6
        image.colorizeAll(with: p)
        XCTAssertEqual(image.pixel(x: 0, y: 0), RGB(r: before.b, g: before.g, b: before.r))
        XCTAssertNotNil(image.makeCGImage())
    }

    func testBandRenderingAndTransformsMatchWholeImage() throws {
        for formula in [0, 28, 101] {
            for transform in 0...4 {
                var p = FractalParameters()
                p.width = 8
                p.height = 8
                p.formula = formula
                p.render = 6
                p.maxIterations = 8
                p.orbitTransform = transform
                p.coordinateFlag = 2
                let whole = try XCTUnwrap(FractalImage(parameters: p, backend: .cpu))
                let bands = try XCTUnwrap(FractalImage(parameters: p, backend: .cpu))
                XCTAssertTrue(whole.compute(rows: 0..<8, cancel: CancelToken()))
                for row in 0..<8 { XCTAssertTrue(bands.compute(rows: row..<(row + 1), cancel: CancelToken())) }
                whole.colorizeAll(with: p)
                bands.colorizeAll(with: p)
                XCTAssertEqual(whole.makeCGImage()?.dataProvider?.data as Data?, bands.makeCGImage()?.dataProvider?.data as Data?)
            }
        }
    }

    func testCancellationDuringLongCPUOrbit() throws {
        var p = FractalParameters()
        // Enough work that an optimised renderer cannot finish before the cancellation fires.
        p.width = 64
        p.height = 1
        p.formula = 101
        p.render = 30
        p.maxIterations = 1_000_000
        let image = try XCTUnwrap(FractalImage(parameters: p, backend: .cpu))
        let token = CancelToken()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { token.cancel() }
        let start = Date()
        XCTAssertFalse(image.compute(rows: 0..<1, cancel: token))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertNil(image.lastError)
        XCTAssertFalse(image.compute(rows: 0..<1, cancel: token))
    }

    func testCPUPrecisionWarningUsesDoublePrecision() {
        var p = FractalParameters()
        p.viewport = Viewport(xMin: 1, xMax: 1.00000001, yMin: 1, yMax: 1.00000001)
        XCTAssertFalse(FractalImage.precisionIsAdequate(for: p, backend: .metal))
        XCTAssertTrue(FractalImage.precisionIsAdequate(for: p, backend: .cpu))
    }

    func testInvalidDimensionsAndExcessiveOrbitMemoryFailSafely() throws {
        var p = FractalParameters()
        p.width = Int.max
        XCTAssertNil(FractalImage(parameters: p, backend: .cpu))
        p.width = 1
        p.height = 1
        p.maxIterations = -1
        XCTAssertNil(FractalImage(parameters: p, backend: .cpu))
        p.maxIterations = 20_000_000
        p.render = 6
        let image = try XCTUnwrap(FractalImage(parameters: p, backend: .cpu))
        XCTAssertFalse(image.compute(rows: 0..<1, cancel: CancelToken()))
        XCTAssertNotNil(image.lastError)
    }
}
