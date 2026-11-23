import Foundation

/// Reader and writer for Sterling's parameter files (".loo").
///
/// A .loo file is plain text, one value per line, written by STERLING2.EXE FUN_004a4f98 and read back by
/// FUN_004a5840. The line order, with the original's field address for each:
///
///      0  "Sterling-Ware v1.7"
///      1  formula                       0x730        2  render                       0x734
///      3  "0"                                        4  title 1          5  title 2
///      6  "reservedtitle"
///      7  zoom extent                   0x608        8  x centre 0x590    9  x max 0x588
///     10  y centre 0x5a8               11  y max 0x5a0
///     12-14  colour offset  R G B       0x6a0 0x6b0 0x6a8
///     15-17  colour saturation R G B    0x688 0x698 0x690
///     18  (unknown, written as 1)       0x740
///     19  max iterations                0x718       20  blend                       0x744
///     21  RGB order                     0x748       22  render scale ("Render")     0x650
///     23  scale factor                  0x658       24  (unknown, "strands")        0x660
///     25  stalks & bubbles radius       0x668       26  bailout (unused)            0x714
///     27  Julia mode                    0x74c       28  Julia applied               0x750
///     29  inside out                    0x754       30  Julia x 0x5f0   31  Julia y 0x5f8
///     32  coordinate flag               0x758
///     33-35  colour step R G B          0x6b8 0x6c8 0x6c0
///     36-38  colour start R G B         0x6d0 0x6e0 0x6d8
///     39  Lyapunov mapping 0x768       40  Lyapunov derivative 0x76c      41  transform 0x770
///
/// Files from older versions stop early; the original fills the missing trailing fields with the defaults
/// used here. The view is stored as centre plus maximum, so the minimum is 2 * centre - maximum.
/// Decimal separators follow the writer's locale, so both "." and "," are accepted.
public enum LooFile {
    public enum ParseError: Error, LocalizedError {
        case notSterling
        case badView

        public var errorDescription: String? {
            switch self {
            case .notSterling: return "This is not a Sterling parameter file."
            case .badView: return "The parameter file has an empty or invalid view."
            }
        }
    }

    public static let header = "Sterling-Ware v1.7"

    /// Whether `text` looks like a parameter file: the first line is the header. Real files write "Sterling-Ware";
    /// the separator is accepted loosely.
    public static func looksLike(_ text: String) -> Bool {
        let start = text.drop(while: { $0 == "\u{FEFF}" || $0.isWhitespace })
        guard start.hasPrefix("Sterling") else { return false }
        return start.dropFirst("Sterling".count).dropFirst().hasPrefix("Ware")
    }

    public static func parse(_ text: String, base: FractalParameters = FractalParameters()) throws -> FractalParameters {
        guard looksLike(text) else { throw ParseError.notSterling }
        // "\r\n" is a single Character in Swift, so normalise it before splitting on "\n".
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = normalised.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            String(line).replacingOccurrences(of: "\u{1A}", with: "")
        }
        // A trailing newline leaves one empty element that is not a line.
        if lines.last == "" { lines.removeLast() }
        guard lines.count >= 7 else { throw ParseError.notSterling }

        func double(_ index: Int, _ fallback: Double) -> Double {
            guard index < lines.count else { return fallback }
            let s = lines[index].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            return Double(s) ?? fallback
        }
        func int(_ index: Int, _ fallback: Int) -> Int {
            guard index < lines.count else { return fallback }
            let s = lines[index].trimmingCharacters(in: .whitespaces)
            if let v = Int(s) { return v }
            return Double(s.replacingOccurrences(of: ",", with: ".")).map { Int($0.rounded()) } ?? fallback
        }
        func string(_ index: Int) -> String { index < lines.count ? lines[index] : "" }

        var p = base
        p.formula = int(1, p.formula)
        p.render = min(max(int(2, p.render), 1), 32)
        p.title1 = string(4)
        p.title2 = string(5)

        let xCentre = double(8, 0)
        let xMax = double(9, 4)
        let yCentre = double(10, 0)
        let yMax = double(11, 4)
        let view = Viewport(xMin: 2 * xCentre - xMax, xMax: xMax, yMin: 2 * yCentre - yMax, yMax: yMax)
        guard view.width > 0, view.height > 0, view.width.isFinite, view.height.isFinite else { throw ParseError.badView }
        p.viewport = view
        p.fitAspect = false

        var colors = ColorControls()
        for channel in 0..<3 {
            colors.offset[channel] = double(12 + channel, 0)
            colors.saturation[channel] = double(15 + channel, 1)
            colors.step[channel] = double(33 + channel, 127)
            colors.start[channel] = double(36 + channel, 127)
        }
        p.colors = colors

        p.maxIterations = max(1, int(19, p.maxIterations))
        let blend = int(20, 1)
        p.blend = (1...26).contains(blend) ? blend : 1   // the original warns and falls back to 1
        let order = int(21, 1)
        p.rgbOrder = (1...6).contains(order) ? order : 1
        p.renderScale = double(22, 2)
        p.scaleFactor = double(23, 2)
        p.trapRadius = double(25, 0.05)
        p.juliaMode = int(27, 0) == 1
        p.insideOut = int(29, 0) != 0
        p.juliaX = double(30, 0)
        p.juliaY = double(31, 0)
        let flag = int(32, 0)
        p.coordinateFlag = (0...3).contains(flag) ? flag : 0
        let mapping = int(39, 1)
        p.lyapunovMapping = (1...9).contains(mapping) ? mapping : 1
        let derivative = int(40, 1)
        p.lyapunovDerivative = (1...21).contains(derivative) ? derivative : 1
        let transform = int(41, 0)
        p.orbitTransform = (0...4).contains(transform) ? transform : 0
        return p
    }

    public static func serialize(_ p: FractalParameters) -> String {
        func d(_ v: Double) -> String { String(format: "%.15g", v) }
        let v = p.viewport
        let extent = (abs(v.width) * 0.5 + abs(v.height) * 0.5) * 0.5
        let c = p.colors
        var lines = [
            header,
            "\(p.formula)", "\(p.render)", "0",
            p.title1, p.title2, "reservedtitle",
            d(extent), d((v.xMin + v.xMax) / 2), d(v.xMax), d((v.yMin + v.yMax) / 2), d(v.yMax),
            d(c.offset[0]), d(c.offset[1]), d(c.offset[2]),
            d(c.saturation[0]), d(c.saturation[1]), d(c.saturation[2]),
            "1", "\(p.maxIterations)", "\(p.blend)", "\(p.rgbOrder)",
            d(p.renderScale), d(p.scaleFactor), d(1), d(p.trapRadius),
            "4", p.juliaMode ? "1" : "0", p.juliaMode ? "1" : "0", p.insideOut ? "1" : "0",
            d(p.juliaX), d(p.juliaY),
            "\(p.coordinateFlag)",
            d(c.step[0]), d(c.step[1]), d(c.step[2]),
            d(c.start[0]), d(c.start[1]), d(c.start[2]),
            "\(p.lyapunovMapping)", "\(p.lyapunovDerivative)", "\(p.orbitTransform)",
        ]
        lines.append("")
        return lines.joined(separator: "\r\n")
    }
}
