import Foundation

/// Metal Shading Language source for every computational stage.
///
/// It is compiled at run time (`MTLDevice.makeLibrary(source:)`) rather than at build time so the same
/// code works from `swift build`/`swift test` and Xcode, and so formula code can be generated later.
///
/// Stages (the tests compare each with a CPU reference):
///  - `fieldKernel`   iterate a formula and reduce the orbit to (A, B)
///  - `colorKernel`   (A, B) -> RGB with anti-alias averaging
///
/// MSL has no `double`, so everything here is float32; `FractalImage.precisionIsAdequate` flags views too deep for it.
enum MetalShaderSource {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    constant float kTwoPi = 6.28318530717958647692f;
    constant float kPi = 3.14159265358979323846f;
    constant int kClassicMandelbrotFormulaID = \(classicMandelbrotFormulaID);

    // x87 fsin/fcos leave an operand of magnitude 2^63 or more unchanged; the original relies on it when orbits blow up.
    inline float sn(float x) { return fabs(x) >= 9.223372e18f ? x : precise::sin(x); }
    inline float cs(float x) { return fabs(x) >= 9.223372e18f ? x : precise::cos(x); }

    // MARK: Field (iteration + orbit reduction)

    // Selected per pipeline (MTLFunctionConstantValues), so each compiled kernel contains one
    // formula, one render mode and one transform instead of all of them.
    constant int kFormula [[function_constant(0)]];
    constant int kRender [[function_constant(1)]];
    constant int kTransform [[function_constant(2)]];
    // The streaming path reduces each orbit point as it is produced. Renders that read the whole orbit
    // (3, 6...32) and the Lyapunov formulas (>= 100) instead store it in a per-thread scratch array.
    constant bool kUseOrbit = (kFormula >= 100) || kRender == 3 || kRender >= 6;

    struct FieldParams {
        float xMin;
        float yMin;
        float dx;
        float dy;
        int fieldWidth;
        int rowStart;
        int rowCount;
        int maxIterations;
        float juliaX;
        float juliaY;
        float trapRadius;
        int juliaMode;
        int insideOut;
        float scale;       // "Scale Factor 4"
        int lyMapping;     // LMapping menu, 1...9
        int lyDerivative;  // LDerivative menu, 1...21
        int coordFlag;     // 0 none, 1 swap x/y, 2 swap and negate, 3 negate (Image menu Rotate90/Rotate90Mirror/Mirror)
        uint orbitStride;  // threads per band: element i of thread t lives at i * orbitStride + t
    };

    // Loop tolerances compiled into the DLL's formulas (1e-25 and 1e+20).
    constant float zerotol = 1e-25f;
    constant float dMAX = 1e20f;

    // MARK: Complex numbers

    struct cplx {
        float x;
        float y;
        cplx() : x(0.0f), y(0.0f) {}
        cplx(float r) : x(r), y(0.0f) {}
        cplx(float r, float i) : x(r), y(i) {}
    };

    inline cplx operator-(cplx a) { return cplx(-a.x, -a.y); }
    inline cplx operator+(cplx a, cplx b) { return cplx(a.x + b.x, a.y + b.y); }
    inline cplx operator-(cplx a, cplx b) { return cplx(a.x - b.x, a.y - b.y); }
    inline cplx operator*(cplx a, cplx b) { return cplx(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
    inline cplx operator+(cplx a, float b) { return cplx(a.x + b, a.y); }
    inline cplx operator+(float a, cplx b) { return cplx(a + b.x, b.y); }
    inline cplx operator-(cplx a, float b) { return cplx(a.x - b, a.y); }
    inline cplx operator-(float a, cplx b) { return cplx(a - b.x, -b.y); }
    inline cplx operator*(cplx a, float b) { return cplx(a.x * b, a.y * b); }
    inline cplx operator*(float a, cplx b) { return cplx(a * b.x, a * b.y); }
    inline cplx operator/(cplx a, float b) { return cplx(a.x / b, a.y / b); }

    // The DLL divides with the textbook (a*conj(b))/|b|^2. That squares |b|, which overflows float32 once
    // |b| > ~1.8e19 (formulas 7 and 9 divide by sin(z)^3 with Im(z) ~ 26) or underflows below ~1e-19, so outside a
    // safe range Smith's algorithm is used instead. Inside it the textbook form is kept because it reproduces
    // the original's signed zeros, which decide atan2 branches on the real axis.
    inline cplx operator/(cplx a, cplx b) {
        float d = b.x * b.x + b.y * b.y;
        if (d >= 1e-30f && d <= 1e30f) {
            return cplx((a.y * b.y + a.x * b.x) / d, (a.y * b.x - a.x * b.y) / d);
        }
        if (fabs(b.x) >= fabs(b.y)) {
            float r = b.y / b.x;
            float s = b.x + b.y * r;
            return cplx((a.x + a.y * r) / s, (a.y - a.x * r) / s);
        }
        float r = b.x / b.y;
        float s = b.x * r + b.y;
        return cplx((a.x * r + a.y) / s, (a.y * r - a.x) / s);
    }
    inline cplx operator/(float a, cplx b) { return cplx(a, 0.0f) / b; }

    inline thread cplx& operator+=(thread cplx &a, cplx b) { a = a + b; return a; }

    // MARK: Helpers (ports of the DLL's sine_cosine, csin_z, cexp_z, clog_z, ctan_z)
    // The originals also clamp the global z in place; here they are pure functions of their argument.

    inline float clamp50(float v) { return fabs(v) > 50.0f ? (v > 0.0f ? 50.0f : -50.0f) : v; }
    // The DLL clamps Im(z) to +-50 before sinh/cosh. In float32 sinh(50)^3 overflows (max ~3e38), which turns the
    // quotients in formulas such as 7 and 9 into NaN and ends the loop early; +-30 keeps cubes finite and still
    // leaves the quotient negligible, so the orbit behaves as it does in double precision.
    inline float clampIm(float v) { return fabs(v) > 30.0f ? (v > 0.0f ? 30.0f : -30.0f) : v; }
    inline float guardTiny(float v) { return fabs(v) < 1e-25f ? (v > 0.0f ? 1e-25f : -1e-25f) : v; }

    inline void sine_cosine(cplx z, thread cplx &zsin, thread cplx &zcos) {
        float y = guardTiny(clampIm(z.y));
        float ey = precise::exp(y);
        float ch = (1.0f / ey + ey) * 0.5f;
        float sh = (ey - 1.0f / ey) * 0.5f;
        float sx = sn(z.x);
        float cx = cs(z.x);
        zsin = cplx(ch * sx, cx * sh);
        zcos = cplx(ch * cx, -sx * sh);
    }

    inline cplx csin_z(cplx z) {
        float x = guardTiny(clamp50(z.x));
        float y = guardTiny(clampIm(z.y));
        float ey = precise::exp(y);
        return cplx((1.0f / ey + ey) * 0.5f * sn(x), (ey - 1.0f / ey) * 0.5f * cs(x));
    }

    inline cplx cexp_z(cplx z) {
        float ex = precise::exp(clampIm(z.x)); // 30, not 50: e^50 times z^4 times a second factor overflows float32
        float y = clamp50(z.y);
        return cplx(ex * cs(y), ex * sn(y));
    }

    // C99 atan2 for a zero y: +-0 for x >= +0, +-pi for x <= -0 (the sign of y is kept).
    inline float atan2c(float y, float x) {
        if (y == 0.0f) return (x < 0.0f || signbit(x)) ? copysign(kPi, y) : copysign(0.0f, y);
        return precise::atan2(y, x);
    }

    inline cplx clog_z(cplx z) {
        float x = clamp50(z.x);
        float y = clamp50(z.y);
        return cplx(precise::log(sqrt(y * y + x * x)), atan2c(y, x));
    }

    inline cplx ctan_z(cplx z) {
        float x = guardTiny(clamp50(z.x));
        float y = guardTiny(clampIm(z.y));
        float ey = precise::exp(y);
        float ch = (1.0f / ey + ey) * 0.5f;
        float sh = (ey - 1.0f / ey) * 0.5f;
        cplx s(ch * sn(x), sh * cs(x));
        cplx c(ch * cs(x), sh * -sn(x));
        return s / c;
    }

    inline float sum_sqrs(cplx zd) { return zd.y * zd.y + zd.x * zd.x; }

    // The "Transform" menu, applied to each orbit point.
    inline float2 applyTransform(int t, float2 p) {
        const float e = 1e-15f;
        float x = p.x;
        float y = p.y;
        float nx;
        float ny;
        switch (t) {
        case 1:
            nx = e + sn(x - (e + sn(y)));
            ny = e + cs(y - (e + sn(nx)));
            break;
        case 2:
            nx = e + sn(e + sn(y) + x);
            ny = e + cs(e + sn(nx) + y);
            break;
        case 3:
            nx = e + atan(y / (e + x));
            ny = e + atan(nx / (e + y));
            break;
        case 4:
            nx = e + sn((e + sn(y)) * x);
            ny = e + cs((e + sn(nx)) * y);
            break;
        default:
            return p;
        }
        return float2(nx, ny);
    }

    // MARK: Platform prelude for the shared render code (SharedRenderSource, also compiled by the C++ oracle)

    typedef float real;
    inline real rAbs(real x) { return fabs(x); }
    inline real rSin(real x) { return sn(x); }
    inline real rCos(real x) { return cs(x); }
    inline real rLog(real x) { return precise::log(x); }
    inline real rSqrt(real x) { return sqrt(x); }
    inline real rAtan(real x) { return precise::atan(x); }
    // x87 fistp: round to nearest even; out-of-range gives the "integer indefinite" value.
    inline int rRound(real v) {
        if (!isfinite(v) || fabs(v) >= 2147483647.0f) return -2147483647 - 1;
        return int(rint(v));
    }

    // One thread's orbit array (the original's pXTemp / pYTemp), interleaved across threads for coalescing.
    struct Orbit {
        device float2 *base;
        uint stride;
        uint tid;
        real X(int i) { return base[uint(i) * stride + tid].x; }
        real Y(int i) { return base[uint(i) * stride + tid].y; }
        void set(int i, real x, real y) { base[uint(i) * stride + tid] = float2(x, y); }
    };

    \(SharedRenderSource.source)

    // Receives every orbit point as the formula produces it (the DLL's pXTemp/pYTemp stores). Without
    // `kUseOrbit` it reduces them on the fly, so no per-pixel orbit array is needed; with it, it stores them.
    struct OrbitAcc {
        float radius;
        float sumA;
        float sumB;
        cplx last; // most recent orbit point; render mode 0 (tests only) outputs it
        Orbit orb;

        void add(cplx p, int index) {
            last = p;
            if (kUseOrbit) {
                orb.set(index, p.x, p.y);
                return;
            }
            if (kRender == 1) return;
            float2 q = applyTransform(kTransform, float2(p.x, p.y));
            trapPoint(kRender, radius, q.x, q.y, sumA, sumB);
        }
    };

    #define ORBIT(p) S.add(p, it)

    // MARK: Formulas (generated from sterling2-formulae.cpp by app/Tools/translate_formulae.py)

    \(GeneratedFormulas.source)

    // Argentic's formula 56: the classic quadratic escape-time map, separate from legacy Formula_00.
    // Orbit 0 is initialized by the caller. Return stored orbit count (iterations + 1), except that
    // render 1 uses count 0 for non-escaping points so every colour blend produces a black interior.
    inline int classicMandelbrot(thread OrbitAcc &S, cplx initial, cplx parameter, int maxit, int jul) {
        cplx z = jul != 0 ? initial : cplx(0.0f, 0.0f);
        float escapeSquared = jul != 0 ? max(4.0f, sum_sqrs(parameter)) : 4.0f;
        if (jul == 0 && kRender == 1 && fabs(parameter.x) <= 2.0f && fabs(parameter.y) <= 2.0f) {
            // Analytic interior tests for the main cardioid and period-2 bulb avoid long bounded loops.
            float x = parameter.x - 0.25f;
            float y2 = parameter.y * parameter.y;
            float q = x * x + y2;
            float bulbX = parameter.x + 1.0f;
            if (q * (q + x) <= 0.25f * y2 || bulbX * bulbX + y2 <= 0.0625f) return 0;
        }
        for (int it = 1; it <= maxit; ++it) {
            z = z * z + parameter;
            S.add(z, it);
            if (!isfinite(z.x) || !isfinite(z.y) || sum_sqrs(z) > escapeSquared) return it + 1;
        }
        return kRender == 1 ? 0 : maxit + 1;
    }

    inline int evaluateFormula(int formula, thread OrbitAcc &S, cplx vz, cplx vc, int maxit, int jul, float radius) {
        if (formula == kClassicMandelbrotFormulaID) return classicMandelbrot(S, vz, vc, maxit, jul);
        return runFormula(formula, S, vz, vc, maxit, jul, radius);
    }

    kernel void fieldKernel(constant FieldParams &p [[buffer(0)]],
                            device float2 *field [[buffer(1)]],
                            device float2 *orbitBase [[buffer(2)]],
                            uint2 gid [[thread_position_in_grid]]) {
        if (int(gid.x) >= p.fieldWidth || int(gid.y) >= p.rowCount) return;
        int col = int(gid.x);
        int row = p.rowStart + int(gid.y);

        cplx z0(p.xMin + float(col) * p.dx, p.yMin + float(row) * p.dy);
        cplx c0 = p.juliaMode != 0 ? cplx(p.juliaX, p.juliaY) : z0;
        // FUN_0049b4d0 transforms the starting z and c of every pixel before running the formula.
        if (p.coordFlag == 1) {
            z0 = cplx(z0.y, z0.x);
            c0 = cplx(c0.y, c0.x);
        } else if (p.coordFlag == 2) {
            z0 = cplx(-z0.y, -z0.x);
            c0 = cplx(-c0.y, -c0.x);
        } else if (p.coordFlag == 3) {
            z0 = cplx(-z0.x, -z0.y);
            c0 = cplx(-c0.x, -c0.y);
        }
        if (p.insideOut != 0 && kFormula < 100) {
            // formula() in the DLL inverts both z and c, with exactly this expression order: it matters
            // for the sign of a zero imaginary part, which clog_z's atan2 then sees.
            float zd = z0.y * z0.y + z0.x * z0.x;
            z0 = cplx((z0.y * 0.0f + z0.x * 1.0f) / zd, (z0.x * 0.0f - z0.y * 1.0f) / zd);
            float cd = c0.y * c0.y + c0.x * c0.x;
            c0 = cplx((c0.y * 0.0f + c0.x * 1.0f) / cd, (c0.x * 0.0f - c0.y * 1.0f) / cd);
        }

        float2 result;
        if (kUseOrbit) {
            Orbit orb;
            orb.base = orbitBase;
            orb.stride = p.orbitStride;
            orb.tid = uint(gid.y) * uint(p.fieldWidth) + gid.x;
            RS rs = rsInit(p.trapRadius, p.scale, p.maxIterations);
            int count;
            if (kFormula >= 100) {
                count = lyapunovRun(rs, orb, kFormula, p.lyMapping, p.lyDerivative, kRender,
                                    c0.x, c0.y, p.insideOut != 0, p.maxIterations);
            } else {
                OrbitAcc S;
                S.radius = p.trapRadius;
                S.sumA = 0.0f;
                S.sumB = 0.0f;
                S.orb = orb;
                cplx start = kFormula == kClassicMandelbrotFormulaID && p.juliaMode != 0 ? z0 : cplx(0.0f, 0.0f);
                orb.set(0, start.x, start.y);
                count = evaluateFormula(kFormula, S, z0, c0, p.maxIterations, p.juliaMode, p.trapRadius);
            }
            rs.count = count;
            if (kTransform != 0) {
                for (int i = 0; i < count; i++) {
                    float2 q = applyTransform(kTransform, float2(orb.X(i), orb.Y(i)));
                    orb.set(i, q.x, q.y);
                }
            }
            renderArrays(kRender, rs, orb, c0.x, c0.y, p.lyDerivative);
            result = float2(rs.outA, rs.outB);
        } else {
            OrbitAcc S;
            S.radius = p.trapRadius;
            S.sumA = 0.0f;
            S.sumB = 0.0f;
            // pXTemp[0] / pYTemp[0] are always (0, 0) and the render stage reads them.
            S.add(kFormula == kClassicMandelbrotFormulaID && p.juliaMode != 0 ? z0 : cplx(0.0f, 0.0f), 0);

            int it = evaluateFormula(kFormula, S, z0, c0, p.maxIterations, p.juliaMode, p.trapRadius);

            if (kRender == 0) {
                result = float2(S.last.x, S.last.y);
            } else if (kRender == 1) {
                float v = fabs(log(1.0f / float(max(it, 1))));
                result = float2(v, v);
            } else {
                result = float2(sqrt(S.sumA), sqrt(S.sumB));
            }
        }
        field[row * p.fieldWidth + col] = result;
    }

    // MARK: Colour

    struct ColorParams {
        float4 step;
        float4 start;
        float4 saturation;
        float4 offset;
        float renderScale;
        float xMin;
        float yMin;
        float dx;
        float dy;
        int blend;
        int rgbOrder;
        int sampling;
        int fieldWidth;
        int width;
        int rowStart;
        int rowCount;
    };

    // x87 fistp: round to nearest even; out-of-range gives the "integer indefinite" value.
    inline int fround(float v) {
        if (!isfinite(v) || fabs(v) >= 2147483647.0f) return -2147483647 - 1;
        return int(rint(v));
    }

    // 9-bit triangle fold: values 256...511 reflect back into 0...255.
    inline int fold(int v) { return (v & 0x1ff) > 0xff ? (~v & 0xff) : v; }

    // The original mixes its three per-channel slots in memory order R, B, G.
    inline float3 slot(float4 v) { return float3(v.x, v.z, v.y); }

    inline int3 trigBlend(int blend, float a, float b, float3 st, float3 sa, float3 sat, float3 off) {
        float ta = a * kTwoPi;
        float tb = b * kTwoPi;
        float v0;
        float v1;
        switch (blend) {
        case 1: v0 = sn(ta); v1 = cs(tb); break;
        case 2: v0 = cs(ta); v1 = -cs(tb); break;
        case 3: v0 = cs(ta); v1 = sn(tb); break;
        case 4:
        case 6: v0 = cs(ta); v1 = cs(tb); break;
        default: v0 = sn(ta); v1 = sn(tb); break;
        }
        float v2 = (v0 + v1) * 0.5f;
        int s0 = fround(v0 * st.x + sa.x);
        int s1 = fround(v1 * st.y + sa.y);
        int s2 = fround(v2 * st.z + sa.z);
        int o0 = fround(float(s0) * sat.x + off.x) & 0x1ff;
        int o1 = fround(float(s1) * sat.y + off.y) & 0x1ff;
        int o2 = fround(float(s2) * sat.z + off.z) & 0x1ff;
        if (blend == 6 || blend == 7) {
            o2 = fround(0.33f * float(o0 + o1 + o2));
        }
        return int3(fold(o0), fold(o1), fold(o2));
    }

    inline int3 normalisedBlend(int blend, float a, float b, float3 st, float3 sa, float3 sat, float3 off) {
        float m = (a + b) * 0.5f;
        float f0;
        float f1;
        float f2;
        switch (blend) {
        case 8:
            f0 = sn(kTwoPi * (a + m) * 0.5f);
            f1 = -sn(kTwoPi * b);
            f2 = cs(kTwoPi * m);
            break;
        case 9:
            f0 = sn(kTwoPi * (-cs(a)));
            f1 = -sn(kTwoPi * sn(b));
            f2 = sn(kTwoPi * sn(m));
            break;
        case 10:
            f0 = sn(kTwoPi * a);
            f1 = -sn(kTwoPi * (b + m) * 0.5f);
            f2 = sn(kTwoPi * m);
            break;
        case 11:
            f0 = sn(kTwoPi * a);
            f1 = -cs(kTwoPi * (m + b) * 0.5f);
            f2 = -sn(kTwoPi * m);
            break;
        default:
            f0 = sn(kTwoPi * a);
            f1 = sn(kTwoPi * (m + b) * 0.5f);
            f2 = sn(kTwoPi * m);
            break;
        }
        f0 = ((f0 * st.x + sa.x) * sat.x + off.x) / 255.0f;
        f1 = ((f1 * st.y + sa.y) * sat.y + off.y) / 255.0f;
        f2 = ((f2 * st.z + sa.z) * sat.z + off.z) / 255.0f;

        float o0;
        float o1;
        float o2;
        switch (blend) {
        case 8: o0 = -sn(kTwoPi * f0); o1 = sn(kTwoPi * f1); o2 = -cs(kTwoPi * f2); break;
        case 9: o0 = sn(kTwoPi * f0); o1 = cs(kTwoPi * f1); o2 = sn(kTwoPi * f2); break;
        case 10: o0 = -sn(kTwoPi * f0); o1 = sn(kTwoPi * f1); o2 = sn(kTwoPi * f2); break;
        case 11: o0 = -cs(kTwoPi * f0); o1 = cs(kTwoPi * f1); o2 = sn(kTwoPi * f2); break;
        default: o0 = cs(kTwoPi * f0); o1 = cs(kTwoPi * f1); o2 = cs(kTwoPi * f2); break;
        }
        return int3(fround(o0 * 127.0f) + 0x7f, fround(o1 * 127.0f) + 0x7f, fround(o2 * 127.0f) + 0x7f);
    }

    inline float nonZero(float v) { return fabs(v) < 1e-20f ? 1e-20f : v; }

    inline int3 angleBlend(int blend, float a, float b, float2 pixel, float3 st, float3 sa, float3 sat, float3 off) {
        float d0 = 0.0f;
        float d1 = 0.0f;
        float d2 = 0.0f;
        switch (blend) {
        case 13:
            d0 = sqrt(b * b + a * a);
            d1 = (a + d0) * 0.5f;
            d2 = (b + d0) * 0.5f;
            break;
        case 14:
        case 18:
            d0 = 0.707f * b + a;
            d1 = 0.707f * a + b;
            d2 = 0.707f * (d0 + d1);
            break;
        case 15:
            d0 = 0.707f * b + a;
            d1 = -0.707f * a + b;
            d2 = 0.707f * (d0 + d1);
            break;
        case 16:
            d0 = 0.707f * b;
            d1 = 0.707f * a;
            d2 = 0.707f * (d0 + d1);
            break;
        case 17:
            d0 = 0.707f * b * b;
            d1 = 0.707f * a * a;
            d2 = 0.707f * (d0 + d1);
            break;
        case 19:
            d0 = sqrt(b * b + a * a);
            d1 = a + d0;
            d2 = b + d0;
            break;
        case 20:
            d0 = b * b + a * a;
            d1 = a * a;
            d2 = b * b;
            break;
        case 21:
            d0 = a + b;
            d1 = a + d0;
            d2 = b + d0;
            break;
        case 22: {
            float px = nonZero(pixel.x);
            float py = nonZero(pixel.y);
            d2 = a + b + atan(fabs(px / py));
            d1 = b + a + atan(fabs(py / px));
            d0 = (d2 + d1) * 0.5f;
            break;
        }
        case 23: {
            float ca = nonZero(a);
            float cb = nonZero(b);
            d0 = ca + cb;
            d2 = sn(fabs(pixel.x * pixel.x + ca)) + d0;
            d1 = sn(fabs(pixel.y * pixel.y + cb)) + d0;
            break;
        }
        case 24:
            d0 = fabs(b);
            d1 = a + d0;
            d2 = b + d0;
            d0 = (d1 + d2) * 0.5f;
            break;
        case 25: {
            float px = nonZero(pixel.x);
            float py = nonZero(pixel.y);
            d0 = fabs(atan(fabs(px / py)) + atan(fabs(py / px)));
            d1 = a * d0;
            d2 = b * d0;
            break;
        }
        default:
            d0 = a + b;
            d1 = d0 * 0.5f * a;
            d2 = d0 * 0.5f * b;
            break;
        }

        // The original scales by 360 degrees and converts back, so the offset is in degrees.
        float deg0 = d0 * 360.0f * sat.x + off.x;
        float deg1 = d1 * 360.0f * sat.y + off.y;
        float deg2 = d2 * 360.0f * sat.z + off.z;
        const float toRadians = kPi / 180.0f;
        float s0 = sn(deg0 * toRadians);
        float s1 = (sn(deg1 * toRadians) + s0) * 0.5f;
        float s2 = 0.33f * (cs(deg2 * toRadians) + s0 + s1);
        return int3(fround(s0 * st.x + sa.x), fround(s1 * st.y + sa.y), fround(s2 * st.z + sa.z));
    }

    inline int3 colorAt(constant ColorParams &p, float rawA, float rawB, float2 pixel) {
        float a = rawA * p.renderScale;
        float b = rawB * p.renderScale;
        if (a == 0.0f && b == 0.0f) return int3(0);

        float3 st = slot(p.step);
        float3 sa = slot(p.start);
        float3 sat = slot(p.saturation);
        float3 off = slot(p.offset);
        int blend = clamp(p.blend, 1, 26);

        int3 o;
        if (blend <= 7) {
            o = trigBlend(blend, a, b, st, sa, sat, off);
        } else if (blend <= 12) {
            o = normalisedBlend(blend, a, b, st, sa, sat, off);
        } else {
            o = angleBlend(blend, a, b, pixel, st, sa, sat, off);
        }
        o &= 0xff;

        switch (p.rgbOrder) {
        case 2: return int3(o.x, o.z, o.y);
        case 3: return int3(o.y, o.z, o.x);
        case 4: return int3(o.y, o.x, o.z);
        case 5: return int3(o.z, o.x, o.y);
        case 6: return int3(o.z, o.y, o.x);
        default: return o;
        }
    }

    kernel void colorKernel(constant ColorParams &p [[buffer(0)]],
                            const device float2 *field [[buffer(1)]],
                            device uint *out [[buffer(2)]],
                            uint2 gid [[thread_position_in_grid]]) {
        if (int(gid.x) >= p.width || int(gid.y) >= p.rowCount) return;
        int col = int(gid.x);
        int row = p.rowStart + int(gid.y);
        int k = p.sampling;

        int3 sum = int3(0);
        for (int sy = 0; sy < k; sy++) {
            for (int sx = 0; sx < k; sx++) {
                int fr = row * k + sy;
                int fc = col * k + sx;
                float2 ab = field[fr * p.fieldWidth + fc];
                float2 pixel = float2(p.xMin + float(fc) * p.dx, p.yMin + float(fr) * p.dy);
                sum += colorAt(p, ab.x, ab.y, pixel);
            }
        }
        int3 avg = sum / (k * k);
        out[row * p.width + col] = uint(avg.x) | (uint(avg.y) << 8) | (uint(avg.z) << 16) | 0xff000000u;
    }
    """
}
