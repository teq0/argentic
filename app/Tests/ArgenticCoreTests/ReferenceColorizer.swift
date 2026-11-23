import ArgenticCore
import Foundation

/// CPU reference implementation of the colour stage. The shipping implementation is the Metal
/// `colorKernel`; the tests render the same values through both and compare.
///
/// Ported from STERLING2.EXE:
///  - FUN_004a8ecc  blend modes 1...26 ("Color'" / "Color''" menus)
///  - FUN_004ab6d4  shared tail used by blends 13...26
///  - FUN_004ab520  RGB channel ordering and the "A == B == 0 is black" rule
///
/// Control slots: the Delphi code stores each colour control as three doubles at
/// 0x6b8/0x6c0/0x6c8 (step), 0x6d0/0x6d8/0x6e0 (start), 0x688/0x690/0x698 (saturation)
/// and 0x6a0/0x6a8/0x6b0 (offset). `ColorControls` keeps them in that memory order, and the
/// blends deliberately mix slots 0, 2, 1 for their first/second/third value, as the original does.
enum ReferenceColorizer {
    struct RGB: Equatable {
        var r: UInt8
        var g: UInt8
        var b: UInt8
    }

    static let blendCount = 26

    private static let twoPi = 2 * Double.pi
    private static let epsilon = 1e-20

    /// x87 `fistp` semantics: round to nearest even, out-of-range gives the "integer indefinite" value.
    @inline(__always)
    private static func fround(_ v: Double) -> Int {
        guard v.isFinite, abs(v) < 2_147_483_647 else { return Int(Int32.min) }
        return Int(v.rounded(.toNearestOrEven))
    }

    /// 9-bit triangle fold used by blends 1...7: values 256...511 reflect back into 0...255.
    @inline(__always)
    private static func fold(_ v: Int) -> Int {
        (v & 0x1ff) > 0xff ? (~v & 0xff) : v
    }

    public static func color(a rawA: Double, b rawB: Double, pixel: (x: Double, y: Double), parameters p: FractalParameters) -> RGB {
        let a = rawA * p.renderScale
        let b = rawB * p.renderScale
        if a == 0 && b == 0 { return RGB(r: 0, g: 0, b: 0) }

        let c = p.colors
        let blend = min(max(p.blend, 1), blendCount)
        var o0 = 0, o1 = 0, o2 = 0

        switch blend {
        case 1...7:
            (o0, o1, o2) = trigBlend(blend, a, b, c)
        case 8...12:
            (o0, o1, o2) = normalisedBlend(blend, a, b, c)
        default:
            (o0, o1, o2) = angleBlend(blend, a, b, pixel, c)
        }

        let v0 = UInt8(truncatingIfNeeded: o0)
        let v1 = UInt8(truncatingIfNeeded: o1)
        let v2 = UInt8(truncatingIfNeeded: o2)
        switch p.rgbOrder {
        case 2: return RGB(r: v0, g: v2, b: v1)
        case 3: return RGB(r: v1, g: v2, b: v0)
        case 4: return RGB(r: v1, g: v0, b: v2)
        case 5: return RGB(r: v2, g: v0, b: v1)
        case 6: return RGB(r: v2, g: v1, b: v0)
        default: return RGB(r: v0, g: v1, b: v2)
        }
    }

    // MARK: Blends 1...7

    private static func trigBlend(_ blend: Int, _ a: Double, _ b: Double, _ c: ColorControls) -> (Int, Int, Int) {
        let ta = a * twoPi
        let tb = b * twoPi
        let v0: Double
        let v1: Double
        switch blend {
        case 1: v0 = sin(ta); v1 = cos(tb)
        case 2: v0 = cos(ta); v1 = -cos(tb)
        case 3: v0 = cos(ta); v1 = sin(tb)
        case 4, 6: v0 = cos(ta); v1 = cos(tb)
        default: v0 = sin(ta); v1 = sin(tb)
        }
        let v2 = (v0 + v1) * 0.5

        let s0 = fround(v0 * c.step[0] + c.start[0])
        let s1 = fround(v1 * c.step[1] + c.start[1])
        let s2 = fround(v2 * c.step[2] + c.start[2])

        var o0 = fround(Double(s0) * c.saturation[0] + c.offset[0]) & 0x1ff
        var o1 = fround(Double(s1) * c.saturation[1] + c.offset[1]) & 0x1ff
        var o2 = fround(Double(s2) * c.saturation[2] + c.offset[2]) & 0x1ff

        if blend == 6 || blend == 7 {
            o2 = fround(0.33 * Double(o0 + o1 + o2))
        }
        o0 = fold(o0)
        o1 = fold(o1)
        o2 = fold(o2)
        return (o0, o1, o2)
    }

    // MARK: Blends 8...12

    private static func normalisedBlend(_ blend: Int, _ a: Double, _ b: Double, _ c: ColorControls) -> (Int, Int, Int) {
        let m = (a + b) * 0.5
        var f0: Double
        var f1: Double
        var f2: Double
        switch blend {
        case 8:
            f0 = sin(twoPi * (a + m) * 0.5)
            f1 = -sin(twoPi * b)
            f2 = cos(twoPi * m)
        case 9:
            let g0 = -cos(a)
            let g1 = sin(b)
            let g2 = sin(m)
            f0 = sin(twoPi * g0)
            f1 = -sin(twoPi * g1)
            f2 = sin(twoPi * g2)
        case 10:
            f0 = sin(twoPi * a)
            f1 = -sin(twoPi * (b + m) * 0.5)
            f2 = sin(twoPi * m)
        case 11:
            f0 = sin(twoPi * a)
            f1 = -cos(twoPi * (m + b) * 0.5)
            f2 = -sin(twoPi * m)
        default:
            f0 = sin(twoPi * a)
            f1 = sin(twoPi * (m + b) * 0.5)
            f2 = sin(twoPi * m)
        }

        f0 = (f0 * c.step[0] + c.start[0]) * c.saturation[0] + c.offset[0]
        f1 = (f1 * c.step[1] + c.start[1]) * c.saturation[1] + c.offset[1]
        f2 = (f2 * c.step[2] + c.start[2]) * c.saturation[2] + c.offset[2]
        f0 /= 255
        f1 /= 255
        f2 /= 255

        let o0: Double
        let o1: Double
        let o2: Double
        switch blend {
        case 8: o0 = -sin(twoPi * f0); o1 = sin(twoPi * f1); o2 = -cos(twoPi * f2)
        case 9: o0 = sin(twoPi * f0); o1 = cos(twoPi * f1); o2 = sin(twoPi * f2)
        case 10: o0 = -sin(twoPi * f0); o1 = sin(twoPi * f1); o2 = sin(twoPi * f2)
        case 11: o0 = -cos(twoPi * f0); o1 = cos(twoPi * f1); o2 = sin(twoPi * f2)
        default: o0 = cos(twoPi * f0); o1 = cos(twoPi * f1); o2 = cos(twoPi * f2)
        }
        return (fround(o0 * 127) + 0x7f, fround(o1 * 127) + 0x7f, fround(o2 * 127) + 0x7f)
    }

    // MARK: Blends 13...26

    private static func angleBlend(_ blend: Int, _ a: Double, _ b: Double, _ pixel: (x: Double, y: Double), _ c: ColorControls) -> (Int, Int, Int) {
        var d0 = 0.0
        var d1 = 0.0
        var d2 = 0.0

        func nonZero(_ v: Double) -> Double { abs(v) < epsilon ? epsilon : v }

        switch blend {
        case 13:
            d0 = (b * b + a * a).squareRoot()
            d1 = (a + d0) * 0.5
            d2 = (b + d0) * 0.5
        case 14, 18:
            d0 = 0.707 * b + a
            d1 = 0.707 * a + b
            d2 = 0.707 * (d0 + d1)
        case 15:
            d0 = 0.707 * b + a
            d1 = -0.707 * a + b
            d2 = 0.707 * (d0 + d1)
        case 16:
            d0 = 0.707 * b
            d1 = 0.707 * a
            d2 = 0.707 * (d0 + d1)
        case 17:
            d0 = 0.707 * b * b
            d1 = 0.707 * a * a
            d2 = 0.707 * (d0 + d1)
        case 19:
            d0 = (b * b + a * a).squareRoot()
            d1 = a + d0
            d2 = b + d0
        case 20:
            d0 = b * b + a * a
            d1 = a * a
            d2 = b * b
        case 21:
            d0 = a + b
            d1 = a + d0
            d2 = b + d0
        case 22:
            let px = nonZero(pixel.x)
            let py = nonZero(pixel.y)
            d2 = a + b + atan(abs(px / py))
            d1 = b + a + atan(abs(py / px))
            d0 = (d2 + d1) * 0.5
        case 23:
            let ca = nonZero(a)
            let cb = nonZero(b)
            d0 = ca + cb
            d2 = sin(abs(pixel.x * pixel.x + ca)) + d0
            d1 = sin(abs(pixel.y * pixel.y + cb)) + d0
        case 24:
            d0 = abs(b)
            d1 = a + d0
            d2 = b + d0
            d0 = (d1 + d2) * 0.5
        case 25:
            let px = nonZero(pixel.x)
            let py = nonZero(pixel.y)
            d0 = abs(atan(abs(px / py)) + atan(abs(py / px)))
            d1 = a * d0
            d2 = b * d0
        default: // 26: the original rounds these products to single precision
            d0 = a + b
            d1 = Double(Float(d0) * 0.5 * Float(a))
            d2 = Double(Float(d0) * 0.5 * Float(b))
        }

        // The original scales by 360 degrees and converts back, so the offset is in degrees.
        let deg0 = d0 * 360 * c.saturation[0] + c.offset[0]
        let deg1 = d1 * 360 * c.saturation[1] + c.offset[1]
        let deg2 = d2 * 360 * c.saturation[2] + c.offset[2]
        let toRadians = Double.pi / 180

        let s0 = sin(deg0 * toRadians)
        let s1 = (sin(deg1 * toRadians) + s0) * 0.5
        let s2 = 0.33 * (cos(deg2 * toRadians) + s0 + s1)

        return (
            fround(s0 * c.step[0] + c.start[0]),
            fround(s1 * c.step[1] + c.start[1]),
            fround(s2 * c.step[2] + c.start[2])
        )
    }
}
