import XCTest
@testable import ArgenticCore

/// Compares the GPU render stage and Lyapunov engine with the double-precision oracle, which compiles the
/// very same source (app/Shaders/render_shared.h). Orbits are short (6-8 iterations) so float32 and double
/// still agree; what is checked is the GPU's arithmetic, control flow and buffer handling.
final class RenderTests: XCTestCase {
    struct Case: Decodable {
        let formula: Int
        let render: Int
        let mapping: Int
        let derivative: Int
        let maxit: Int
        let a: [Double?]
        let b: [Double?]
    }

    struct Fixture: Decodable {
        let width: Int
        let height: Int
        let trapRadius: Double
        let cases: [Case]
    }

    static func loadFixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "renders", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testRendersAgainstOracle() throws {
        let fixture = try Self.loadFixture()
        var report: [String] = []
        var failures: [String] = []
        var rates: [Double] = []

        for c in fixture.cases {
            var p = FractalParameters()
            p.width = fixture.width
            p.height = fixture.height
            p.maxIterations = c.maxit
            p.trapRadius = fixture.trapRadius
            p.viewport = Viewport(xMin: -2.5, xMax: 1.5, yMin: -1.5, yMax: 1.5)
            p.formula = c.formula
            p.render = c.render
            p.lyapunovMapping = c.mapping
            p.lyapunovDerivative = c.derivative
            p.scaleFactor = 1.0
            p.coordinateFlag = 0   // the oracle runs the renders on the raw pixel coordinates

            let image = try XCTUnwrap(FractalImage(parameters: p))
            XCTAssertTrue(image.compute(rows: 0..<p.height, cancel: CancelToken()),
                          "formula \(c.formula) render \(c.render): \(image.lastError.map(String.init(describing:)) ?? "")")

            var compared = 0
            var matched = 0
            for i in 0..<(p.width * p.height) {
                let v = image.fieldValue(x: i % p.width, y: i / p.width)
                for (gpu, oracle) in [(Double(v.a), c.a[i]), (Double(v.b), c.b[i])] {
                    guard let oracle else { continue }
                    compared += 1
                    if abs(gpu - oracle) <= 5e-3 * max(1, abs(oracle)) + 1e-4 { matched += 1 }
                }
            }
            let rate = compared == 0 ? 1 : Double(matched) / Double(compared)
            let name = "formula \(c.formula) render \(c.render) mapping \(c.mapping) derivative \(c.derivative)"
            report.append(String(format: "%@  %3.0f%% of %d", name, 100 * rate, compared))
            rates.append(rate)
            // Lyapunov exponents are chaotic by construction (and mappings 3-5 divide by values near zero or take a
            // tangent), so float32 and double drift apart within a few iterations in a minority of pixels. Render 21
            // forms X/Y with a zero floored to 1e-24, so its variance sums reach 1e48, beyond float32's 3e38.
            let required = c.formula >= 100 ? 0.80 : (c.render == 21 ? 0.90 : 0.95)
            if rate < required { failures.append("\(name): \(Int(100 * rate))%") }
        }
        print("RENDER REPORT\n" + report.joined(separator: "\n"))
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of \(fixture.cases.count) cases below their threshold:\n" + failures.joined(separator: "\n"))
        XCTAssertGreaterThan(rates.reduce(0, +) / Double(rates.count), 0.98, "mean agreement over all cases")
    }
}
