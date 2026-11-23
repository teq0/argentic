import XCTest
@testable import ArgenticCore

final class ColorKernelTests: XCTestCase {
    /// Feeds identical (A, B) values through the Metal colour kernel and the Swift reference port.
    func testKernelMatchesReference() throws {
        var p = FractalParameters()
        p.width = 48
        p.height = 32
        p.formula = 0
        let image = try XCTUnwrap(FractalImage(parameters: p))

        var generator = SystemRandomNumberGenerator()
        var field: [SIMD2<Float>] = []
        for i in 0..<(p.width * p.height) {
            // A few exact zeros exercise the black rule; the rest cover typical render-stage magnitudes.
            if i % 17 == 0 { field.append(SIMD2(0, 0)) }
            else { field.append(SIMD2(Float.random(in: 0..<4, using: &generator), Float.random(in: 0..<4, using: &generator))) }
        }
        image.loadField(field)

        let view = image.renderedViewport
        let dx = view.width / Double(p.width)
        let dy = view.height / Double(p.height)

        var failures: [String] = []
        for blend in 1...ReferenceColorizer.blendCount {
            for order in 1...6 {
                var q = p
                q.blend = blend
                q.rgbOrder = order
                q.renderScale = 1.5
                q.colors.step = [100, 120, 90]
                q.colors.start = [127, 100, 140]
                q.colors.saturation = [1.2, 0.9, 1.5]
                q.colors.offset = [10, -20, 30]
                image.colorizeAll(with: q)

                var mismatches = 0
                for y in 0..<p.height {
                    for x in 0..<p.width {
                        let v = field[y * p.width + x]
                        let expected = ReferenceColorizer.color(
                            a: Double(v.x), b: Double(v.y),
                            pixel: (view.xMin + Double(x) * dx, view.yMin + Double(y) * dy),
                            parameters: q
                        )
                        let actual = image.pixel(x: x, y: y)
                        let close = abs(Int(actual.r) - Int(expected.r)) <= 3
                            && abs(Int(actual.g) - Int(expected.g)) <= 3
                            && abs(Int(actual.b) - Int(expected.b)) <= 3
                        if !close { mismatches += 1 }
                    }
                }
                // float32 trig of large arguments and rounding at .5 boundaries differ from double occasionally.
                if Double(mismatches) / Double(p.width * p.height) > 0.04 {
                    failures.append("blend \(blend) order \(order): \(mismatches) of \(p.width * p.height)")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testBlackForZeroValues() throws {
        var p = FractalParameters()
        p.width = 8
        p.height = 8
        let image = try XCTUnwrap(FractalImage(parameters: p))
        image.loadField([SIMD2<Float>](repeating: .zero, count: 64))
        for blend in 1...ReferenceColorizer.blendCount {
            p.blend = blend
            image.colorizeAll(with: p)
            XCTAssertEqual(image.pixel(x: 3, y: 3), RGB(r: 0, g: 0, b: 0), "blend \(blend)")
        }
    }

    func testAntiAliasAveragesSubsamples() throws {
        var p = FractalParameters()
        p.width = 4
        p.height = 4
        p.antiAlias = 2
        p.blend = 13
        let image = try XCTUnwrap(FractalImage(parameters: p))
        XCTAssertEqual(image.sampling, 2)
        // All four sub-samples of every pixel identical -> the average equals that colour.
        image.loadField([SIMD2<Float>](repeating: SIMD2(1.0, 0.5), count: 8 * 8))
        image.colorizeAll(with: p)
        let first = image.pixel(x: 0, y: 0)
        XCTAssertEqual(image.pixel(x: 3, y: 3), first)
    }
}

final class ImageTests: XCTestCase {
    func renderedImage(width: Int, height: Int) throws -> FractalImage {
        var p = FractalParameters()
        p.width = width
        p.height = height
        p.maxIterations = 30
        let image = try XCTUnwrap(FractalImage(parameters: p))
        XCTAssertTrue(image.compute(rows: 0..<height, cancel: CancelToken()))
        image.colorizeAll(with: p)
        return image
    }

    func testRecolouringDoesNotNeedANewField() throws {
        let image = try renderedImage(width: 32, height: 32)
        var p = image.parameters
        let before = image.pixel(x: 5, y: 5)
        let field = image.fieldValue(x: 5, y: 5)

        p.rgbOrder = 6
        XCTAssertFalse(p.fieldDiffers(from: image.parameters))
        image.colorizeAll(with: p)
        XCTAssertEqual(image.pixel(x: 5, y: 5), RGB(r: before.b, g: before.g, b: before.r))
        XCTAssertEqual(image.fieldValue(x: 5, y: 5).a, field.a)
    }

    /// Image menu Rotate90 / Rotate90Mirror / Mirror change the starting z and c of each pixel. On a square, grid-aligned
    /// view the result at a pixel must equal the unflagged result at the pixel holding the transformed coordinates,
    /// because the same inputs go through the same arithmetic.
    func testCoordinateFlagTransformsStartingPoints() throws {
        let n = 32
        for formula in [0, 28] {
            func field(flag: Int) throws -> [[Float]] {
                var p = FractalParameters()
                p.width = n
                p.height = n
                p.formula = formula
                p.render = 2
                p.trapRadius = 0.3
                p.viewport = Viewport(xMin: -2, xMax: 2, yMin: -2, yMax: 2)
                p.coordinateFlag = flag
                let image = try XCTUnwrap(FractalImage(parameters: p))
                XCTAssertTrue(image.compute(rows: 0..<n, cancel: CancelToken()))
                return (0..<n).map { y in (0..<n).map { x in image.fieldValue(x: x, y: y).a } }
            }
            let plain = try field(flag: 0)
            let swapped = try field(flag: 1)
            let swappedNegated = try field(flag: 2)
            let negated = try field(flag: 3)
            // Negating 0 gives -0, whose sign shows up in the last digits of a few pixels on the axes.
            for y in 0..<n {
                for x in 0..<n {
                    XCTAssertEqual(swapped[y][x], plain[x][y], accuracy: 1e-4, "flag 1 formula \(formula) at \(x),\(y)")
                }
            }
            for y in 1..<n {
                for x in 1..<n {
                    XCTAssertEqual(negated[y][x], plain[n - y][n - x], accuracy: 1e-4, "flag 3 formula \(formula) at \(x),\(y)")
                    XCTAssertEqual(swappedNegated[y][x], plain[n - x][n - y], accuracy: 1e-4, "flag 2 formula \(formula) at \(x),\(y)")
                }
            }
            XCTAssertNotEqual(plain.flatMap { $0 }, swapped.flatMap { $0 }, "the flag must change something")
        }
    }

    func testLooRoundTrip() throws {
        var p = FractalParameters()
        p.formula = 31
        p.render = 14
        p.maxIterations = 250
        p.blend = 20
        p.rgbOrder = 4
        p.renderScale = 1.75
        p.scaleFactor = 3
        p.trapRadius = 0.125
        p.juliaMode = true
        p.juliaX = -0.8
        p.juliaY = 0.156
        p.insideOut = true
        p.coordinateFlag = 2
        p.orbitTransform = 3
        p.lyapunovMapping = 6
        p.lyapunovDerivative = 12
        p.viewport = Viewport(xMin: -0.76, xMax: -0.74, yMin: 0.09, yMax: 0.11)
        p.colors.step = [100, 110, 120]
        p.colors.start = [10, 20, 30]
        p.colors.saturation = [0.5, 1.5, 2.5]
        p.colors.offset = [-5, 6, -7]
        p.title1 = "first"
        p.title2 = "second"

        let text = LooFile.serialize(p)
        XCTAssertTrue(LooFile.looksLike(text))
        var q = try LooFile.parse(text)
        // The file has no image size or anti-aliasing, and loading switches to the original's stretch-to-fit view.
        XCTAssertFalse(q.fitAspect)
        q.fitAspect = p.fitAspect
        XCTAssertEqual(q.viewport.xMin, p.viewport.xMin, accuracy: 1e-12)
        XCTAssertEqual(q.viewport.yMax, p.viewport.yMax, accuracy: 1e-12)
        q.viewport = p.viewport
        XCTAssertEqual(q, p)
    }

    /// A hand-written file as an older Sterling would have saved it: comma decimals, CRLF, and no fields after
    /// the Julia values, which the loader fills with its own defaults.
    func testLooLoadsOldFileWithDefaults() throws {
        let lines = [
            "Sterling-Ware v1.7", "22", "8", "0", "my title", "", "reservedtitle",
            "0,5", "-0,5", "1,5", "0,25", "0,75",
            "10", "20", "30", "1,1", "1,2", "1,3",
            "1", "300", "12", "3", "2,5", "1,5", "8", "0,07", "4", "1", "1", "0", "-0,7", "0,27",
        ]
        let p = try LooFile.parse(lines.joined(separator: "\r\n") + "\r\n")
        XCTAssertEqual(p.formula, 22)
        XCTAssertEqual(p.render, 8)
        XCTAssertEqual(p.title1, "my title")
        // centre -0.5, max 1.5 -> min -2.5; centre 0.25, max 0.75 -> min -0.25
        XCTAssertEqual(p.viewport, Viewport(xMin: -2.5, xMax: 1.5, yMin: -0.25, yMax: 0.75))
        XCTAssertEqual(p.colors.offset, [10, 20, 30])
        XCTAssertEqual(p.colors.saturation, [1.1, 1.2, 1.3])
        XCTAssertEqual(p.maxIterations, 300)
        XCTAssertEqual(p.blend, 12)
        XCTAssertEqual(p.rgbOrder, 3)
        XCTAssertEqual(p.renderScale, 2.5)
        XCTAssertEqual(p.scaleFactor, 1.5)
        XCTAssertEqual(p.trapRadius, 0.07)
        XCTAssertTrue(p.juliaMode)
        XCTAssertEqual(p.juliaX, -0.7)
        XCTAssertEqual(p.juliaY, 0.27)
        // Missing from this old file: the original's loader defaults.
        XCTAssertEqual(p.coordinateFlag, 0)
        XCTAssertEqual(p.colors.step, [127, 127, 127])
        XCTAssertEqual(p.colors.start, [127, 127, 127])
        XCTAssertEqual(p.lyapunovMapping, 1)
        XCTAssertEqual(p.orbitTransform, 0)
    }

    func testLooRejectsOtherFiles() {
        XCTAssertThrowsError(try LooFile.parse("{\"formula\": 1}"))
        XCTAssertThrowsError(try LooFile.parse("Sterling Ware v1.7\n1\n"))
        XCTAssertFalse(LooFile.looksLike("hello"))
        // Files written by Sterling2 itself use a hyphen; an earlier guess had a space.
        XCTAssertTrue(LooFile.looksLike("Sterling-Ware v1.7\r\n54\r\n"))
        XCTAssertTrue(LooFile.looksLike("Sterling Ware v1.7"))
        XCTAssertFalse(LooFile.looksLike("Sterlingware"))
    }

    func testCancellationStopsRendering() throws {
        var p = FractalParameters()
        p.width = 64
        p.height = 64
        let image = try XCTUnwrap(FractalImage(parameters: p))
        let token = CancelToken()
        token.cancel()
        XCTAssertFalse(image.compute(rows: 0..<64, cancel: token))
    }

    func testPrecisionCheck() {
        var p = FractalParameters()
        XCTAssertTrue(FractalImage.precisionIsAdequate(for: p))
        p.viewport = Viewport(xMin: -0.7500001, xMax: -0.7500000, yMin: 0.1, yMax: 0.1000001)
        XCTAssertFalse(FractalImage.precisionIsAdequate(for: p))
    }

    func testParametersRoundTripThroughJSON() throws {
        var p = FractalParameters()
        p.blend = 20
        p.formula = 9
        p.colors.offset = [1, 2, 3]
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(FractalParameters.self, from: data), p)
    }
}
