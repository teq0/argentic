import XCTest
@testable import ArgenticCore

/// Compares the Metal port of every formula against the double-precision oracle
/// (the original C++ compiled with clang; see app/Tools/oracle).
final class OracleTests: XCTestCase {
    struct Case: Decodable {
        let formula: Int
        let julia: Int
        let insideOut: Int
        let iterations: [Int]
        let a: [Double]
        let b: [Double]
        let shortIterations: [Int]
        let lastX: [Double?]
        let lastY: [Double?]
    }

    struct Fixture: Decodable {
        let width: Int
        let height: Int
        let maxIterations: Int
        let trapRadius: Double
        let cases: [Case]
    }

    /// Formulas whose intermediate terms exceed float32's range (~3e38) for part of the plane.
    static let rangeLimited: Set<Int> = [7, 29]

    static func loadFixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "oracle", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    static func parameters(for fixture: Fixture, case c: Case, render: Int) -> FractalParameters {
        var p = FractalParameters()
        p.width = fixture.width
        p.height = fixture.height
        p.maxIterations = fixture.maxIterations
        p.trapRadius = fixture.trapRadius
        p.viewport = Viewport(xMin: -2.5, xMax: 1.5, yMin: -1.5, yMax: 1.5)
        p.formula = c.formula
        p.juliaMode = c.julia == 1
        p.insideOut = c.insideOut == 1
        p.coordinateFlag = 0   // the oracle runs the formulas on the raw pixel coordinates
        p.juliaX = -0.7
        p.juliaY = 0.27015
        p.render = render
        return p
    }

    func field(_ p: FractalParameters) throws -> [(a: Float, b: Float)] {
        let image = try XCTUnwrap(FractalImage(parameters: p))
        XCTAssertTrue(image.compute(rows: 0..<p.height, cancel: CancelToken()), "\(image.lastError.map(String.init(describing:)) ?? "")")
        return (0..<p.height).flatMap { y in (0..<p.width).map { x in image.fieldValue(x: x, y: y) } }
    }

    /// Strict check of the translation: the orbit after at most 4 iterations must match the double-precision
    /// original to float tolerance. Short enough that chaotic divergence has not set in.
    func testShortOrbitMatchesOracle() throws {
        let fixture = try Self.loadFixture()
        var report: [String] = []
        var failures: [String] = []

        for c in fixture.cases {
            var p = Self.parameters(for: fixture, case: c, render: 0)
            p.maxIterations = 4
            let values = try field(p)

            var compared = 0
            var matched = 0
            for i in 0..<values.count {
                guard let ox = c.lastX[i], let oy = c.lastY[i] else { continue }
                // Beyond ~1e4 the high-degree formulas overflow float32 internally: a documented precision
                // limit, not a translation error.
                if abs(ox) > 1e4 || abs(oy) > 1e4 { continue }
                compared += 1
                let tolerance = 2e-3 * max(1, abs(ox), abs(oy))
                if abs(Double(values[i].a) - ox) <= tolerance && abs(Double(values[i].b) - oy) <= tolerance { matched += 1 }
            }
            let rate = compared == 0 ? 1 : Double(matched) / Double(compared)
            let name = "formula \(c.formula) julia \(c.julia) inside \(c.insideOut)"
            report.append(String(format: "%@  short-orbit %3.0f%% of %d", name, 100 * rate, compared))
            // Formulas 7 (c*exp(z)*z^4 * ...) and 29 (z^15 terms) run into float32's range even below 1e4.
            let required = Self.rangeLimited.contains(c.formula) ? 0.90 : 0.97
            if rate < required { failures.append("\(name): \(Int(100 * rate))%") }
        }
        print("SHORT ORBIT REPORT\n" + report.joined(separator: "\n"))
        XCTAssertTrue(failures.isEmpty, "Translation mismatches:\n" + failures.joined(separator: "\n"))
    }

    func testAgainstOracle() throws {
        let fixture = try Self.loadFixture()
        var report: [String] = []
        var worst: [(String, Double)] = []

        for c in fixture.cases {
            let iterField = try field(Self.parameters(for: fixture, case: c, render: 1))
            let renderField = try field(Self.parameters(for: fixture, case: c, render: 2))

            var sameIterations = 0
            var closeValues = 0
            for i in 0..<c.iterations.count {
                let gpuIterations = Int((exp(Double(iterField[i].a))).rounded())
                if gpuIterations == c.iterations[i] { sameIterations += 1 }
                let da = abs(Double(renderField[i].a) - c.a[i])
                let db = abs(Double(renderField[i].b) - c.b[i])
                if da <= 0.02 * max(1, c.a[i]) && db <= 0.02 * max(1, c.b[i]) { closeValues += 1 }
            }
            let n = Double(c.iterations.count)
            let name = "formula \(c.formula) julia \(c.julia) inside \(c.insideOut)"
            report.append(String(format: "%@  iterations %3.0f%%  render2 %3.0f%%", name, 100 * Double(sameIterations) / n, 100 * Double(closeValues) / n))
            worst.append((name, Double(sameIterations) / n))
        }
        print("ORACLE REPORT\n" + report.joined(separator: "\n"))
        let mean = worst.map(\.1).reduce(0, +) / Double(worst.count)
        // Iteration counts of chaotic maps diverge between float32 and double, so this is only a loose guard
        // against gross regressions; testShortOrbitMatchesOracle is the strict check.
        XCTAssertGreaterThan(mean, 0.5, "mean iteration-count agreement with the double-precision oracle")
    }
}
