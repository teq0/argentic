// Double-precision oracle for the GPU formulas.
//
// Compiles the original, unmodified docs/design/sterling2-formulae.cpp against re-implementations of the
// helpers that the decompiled DLL provides (sine_cosine, csin_z, cexp_z, clog_z, ctan_z, sum_sqrs_zd) and
// of the formula() dispatcher. It then writes the per-pixel results the Metal port is compared against.
//
// Build and run with app/Tools/oracle/build_oracle.sh.

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

// The original runs on the x87 FPU, where fsin and fcos leave an operand of magnitude 2^63 or more unchanged
// (the C2 flag is set and the Delphi/MSVC wrappers ignore it). Orbits that blow up therefore saturate instead of
// turning into noise, so the oracle reproduces that.
static double x87sin(double x) { return fabs(x) >= 9223372036854775808.0 ? x : sin(x); }
static double x87cos(double x) { return fabs(x) >= 9223372036854775808.0 ? x : cos(x); }
#define sin x87sin
#define cos x87cos

typedef double _Complex cplx;

struct CDATA {
    cplx z;
    cplx c;
    int Iteration;
    int Maxit;
    double *pXTemp;
    double *pYTemp;
    double dStrands;
    int jul;
};

// The original keeps all of these as file-level globals.
static cplx z, z1, z2, z3, z4, z5, z6, z7, z8, zsin, zcos, zd, c, c2;
static double temp;
static const double zerotol = 1e-25;
static const double dMAX = 1e+20;

static double clamp50(double v) { return fabs(v) > 50.0 ? (v > 0.0 ? 50.0 : -50.0) : v; }

static double guardTiny(double v) { return fabs(v) < 1e-25 ? (v > 0.0 ? 1e-25 : -1e-25) : v; }

static cplx make(double re, double im) {
    cplx r;
    __real__ r = re;
    __imag__ r = im;
    return r;
}

// FUN_004119d4. Clamps a copy of Im(z); z itself is unchanged.
static void sine_cosine() {
    double x = __real__ z;
    double y = guardTiny(clamp50(__imag__ z));
    double ey = exp(y);
    double ch = (1.0 / ey + ey) * 0.5;
    double sh = (ey - 1.0 / ey) * 0.5;
    double sx = sin(x);
    double cx = cos(x);
    zsin = make(ch * sx, cx * sh);
    zcos = make(ch * cx, -sx * sh);
}

// FUN_00411e10. Clamps z in place (both parts), then applies the 1e-25 guard in place.
static cplx csin_z() {
    __imag__ z = clamp50(__imag__ z);
    __real__ z = clamp50(__real__ z);
    __imag__ z = guardTiny(__imag__ z);
    __real__ z = guardTiny(__real__ z);
    double x = __real__ z;
    double y = __imag__ z;
    double ey = exp(y);
    return make((1.0 / ey + ey) * 0.5 * sin(x), (ey - 1.0 / ey) * 0.5 * cos(x));
}

// FUN_0041132c. Clamps z in place.
static cplx cexp_z() {
    __imag__ z = clamp50(__imag__ z);
    __real__ z = clamp50(__real__ z);
    double ex = exp(__real__ z);
    return make(ex * cos(__imag__ z), ex * sin(__imag__ z));
}

// FUN_0041171c. Clamps z in place.
static cplx clog_z() {
    __imag__ z = clamp50(__imag__ z);
    __real__ z = clamp50(__real__ z);
    double x = __real__ z;
    double y = __imag__ z;
    return make(log(sqrt(y * y + x * x)), atan2(y, x));
}

// FUN_00410b20. Works on a clamped copy.
static cplx ctan_z() {
    double x = guardTiny(clamp50(__real__ z));
    double y = guardTiny(clamp50(__imag__ z));
    double ey = exp(y);
    double ch = (1.0 / ey + ey) * 0.5;
    double sh = (ey - 1.0 / ey) * 0.5;
    cplx s = make(ch * sin(x), sh * cos(x));
    cplx cc = make(ch * cos(x), sh * -sin(x));
    return s / cc;
}

static double sum_sqrs_zd() { return __real__ zd * __real__ zd + __imag__ zd * __imag__ zd; }

// JSON has no NaN/inf: non-finite orbit values are written as null.
static void num(double v) {
    if (std::isfinite(v)) printf("%.9g", v);
    else printf("null");
}

#include "../../../docs/design/sterling2-formulae.cpp"

typedef void (*FormulaFn)(CDATA *);

static FormulaFn table[56];

static void buildTable() {
#define F(n) table[atoi(#n)] = Formula_##n;
    F(00) F(01) F(02) F(03) F(04) F(05) F(06) F(07) F(08) F(09) F(10) F(11)
    F(18) F(19) F(20) F(21) F(22) F(23) F(24) F(25) F(26) F(27) F(28) F(29) F(30) F(31) F(32) F(33) F(34) F(35)
    F(36) F(37) F(38) F(39) F(40) F(41) F(42) F(43) F(44) F(45) F(46) F(47) F(48) F(49) F(50) F(51) F(52) F(53) F(54) F(55)
#undef F
}

// formula() in the DLL: sets the globals, optionally inverts z and c, then calls the selected formula.
// The globals are cleared first so the oracle does not depend on whichever pixel ran before.
static void runFormula(int index, CDATA *v, bool insideOut) {
    z1 = z2 = z3 = z4 = z5 = z6 = z7 = z8 = zsin = zcos = zd = c2 = make(0, 0);
    temp = 0;
    v->Iteration = 0;
    if (insideOut) {
        double zx = __real__ v->z, zy = __imag__ v->z;
        double d = zy * zy + zx * zx;
        v->z = make((zy * 0.0 + zx * 1.0) / d, (zx * 0.0 - zy * 1.0) / d);
        double cx = __real__ v->c, cy = __imag__ v->c;
        d = cy * cy + cx * cx;
        v->c = make((cy * 0.0 + cx * 1.0) / d, (cx * 0.0 - cy * 1.0) / d);
    }
    z = v->z;
    c = v->c;
    table[index](v);
}

// ---------------------------------------------------------------------------------------------------------
// Render stage and Lyapunov engine: the very same text the Metal kernel compiles (app/Shaders), in double.
// ---------------------------------------------------------------------------------------------------------

#include <climits>

typedef double real;
#define thread
static inline real rAbs(real x) { return fabs(x); }
static inline real rSin(real x) { return sin(x); }
static inline real rCos(real x) { return cos(x); }
static inline real rLog(real x) { return log(x); }
static inline real rSqrt(real x) { return sqrt(x); }
static inline real rAtan(real x) { return atan(x); }
static inline int rRound(real v) {
    if (!std::isfinite(v) || fabs(v) >= 2147483647.0) return INT_MIN;
    return (int)nearbyint(v);
}

struct Orbit {
    std::vector<double> x, y;
    real X(int i) { return x[i]; }
    real Y(int i) { return y[i]; }
    void set(int i, real a, real b) { x[i] = a; y[i] = b; }
};

#include "../../Shaders/render_shared.h"
#undef thread

// `oracle renders`: reductions of short orbits (the orbit itself is chaotic, but over a few iterations double
// and float still agree), for the renders that read the whole orbit and for the Lyapunov engine.
static void numOrNull(double v) {
    if (std::isfinite(v)) printf("%.9g", v);
    else printf("null");
}

struct RenderSpec { int formula, render, mapping, derivative, maxit; };

static void emitRenderCase(const RenderSpec &sp, bool &first) {
    const int W = 16, H = 12;
    const double xMin = -2.5, yMin = -1.5, dx = 4.0 / W, dy = 3.0 / H, radius = 0.3;
    std::vector<double> A, B;
    for (int row = 0; row < H; row++) {
        for (int col = 0; col < W; col++) {
            double x = xMin + col * dx, y = yMin + row * dy;
            Orbit orb;
            orb.x.assign(sp.maxit + 8, 0.0);
            orb.y.assign(sp.maxit + 8, 0.0);
            RS rs = rsInit(radius, 1.0, sp.maxit);
            int count;
            if (sp.formula >= 100) {
                count = lyapunovRun(rs, orb, sp.formula, sp.mapping, sp.derivative, sp.render, x, y, false, sp.maxit);
            } else {
                CDATA v;
                v.z = make(x, y);
                v.c = make(x, y);
                v.Maxit = sp.maxit;
                v.pXTemp = orb.x.data();
                v.pYTemp = orb.y.data();
                v.dStrands = radius;
                v.jul = 0;
                runFormula(sp.formula, &v, false);
                count = v.Iteration;
            }
            rs.count = count;
            renderArrays(sp.render, rs, orb, x, y, sp.derivative);
            A.push_back(rs.outA);
            B.push_back(rs.outB);
        }
    }
    printf("%s{\"formula\":%d,\"render\":%d,\"mapping\":%d,\"derivative\":%d,\"maxit\":%d,\"a\":[", first ? "" : ",",
           sp.formula, sp.render, sp.mapping, sp.derivative, sp.maxit);
    for (size_t i = 0; i < A.size(); i++) { printf("%s", i ? "," : ""); numOrNull(A[i]); }
    printf("],\"b\":[");
    for (size_t i = 0; i < B.size(); i++) { printf("%s", i ? "," : ""); numOrNull(B[i]); }
    printf("]}");
    first = false;
}

static void runRenders() {
    std::vector<RenderSpec> specs;
    // DLL formulas whose short orbits agree between float and double, through every orbit-reading render.
    for (int f : {0, 28, 31}) {
        specs.push_back({f, 3, 1, 1, 6});
        for (int r = 6; r <= 29; r++) specs.push_back({f, r, 1, 1, 6});
    }
    // Lyapunov: each map with its own mapping and derivative, then full sweeps of both menus, through renders 30-32.
    for (int f = 101; f <= 120; f++)
        for (int r = 30; r <= 32; r++) specs.push_back({f, r, 1 + f % 9, 1 + f % 21, 8});
    for (int m = 1; m <= 9; m++)
        for (int r = 30; r <= 32; r++) specs.push_back({101, r, m, 1, 8});
    for (int d = 1; d <= 21; d++)
        for (int r = 30; r <= 32; r++) specs.push_back({101, r, 1, d, 8});
    // The other renders applied to Lyapunov orbits.
    for (int f : {101, 107})
        for (int r : {1, 2, 3, 4, 5, 6, 9, 14, 22}) specs.push_back({f, r, 1, 1, 8});

    printf("{\"width\":16,\"height\":12,\"trapRadius\":0.3,\"cases\":[");
    bool first = true;
    for (const RenderSpec &sp : specs) emitRenderCase(sp, first);
    printf("]}\n");
}

int main(int argc, char **argv) {
    buildTable();
    if (argc == 2 && strcmp(argv[1], "renders") == 0) {
        runRenders();
        return 0;
    }
    if (argc == 5 || argc == 6) { // debug: oracle <formula> <x> <y> <maxit> [inside]  prints the stored orbit
        int f = atoi(argv[1]);
        std::vector<double> dx(512), dy(512);
        CDATA v;
        v.z = make(atof(argv[2]), atof(argv[3]));
        v.c = v.z;
        v.Maxit = atoi(argv[4]);
        v.pXTemp = dx.data();
        v.pYTemp = dy.data();
        v.dStrands = 0.3;
        v.jul = 0;
        runFormula(f, &v, argc == 6);
        printf("Iteration=%d\n", v.Iteration);
        for (int i = 0; i <= v.Iteration; i++) printf("  [%d] (%.9g, %.9g)\n", i, dx[i], dy[i]);
        return 0;
    }
    if (argc == 13 && strcmp(argv[1], "image") == 0) {
        // oracle image <formula> <render> <maxit> <xmin> <xmax> <ymin> <ymax> <W> <H> <flag> <scale>
        // Writes "a b" for each pixel, in double, for comparing a whole view with the GPU.
        int f = atoi(argv[2]), render = atoi(argv[3]), maxit = atoi(argv[4]);
        double x0 = atof(argv[5]), x1 = atof(argv[6]), y0 = atof(argv[7]), y1 = atof(argv[8]);
        int W = atoi(argv[9]), H = atoi(argv[10]), flag = atoi(argv[11]);
        double scale = atof(argv[12]);
        for (int row = 0; row < H; row++) {
            for (int col = 0; col < W; col++) {
                double x = x0 + col * (x1 - x0) / W, y = y0 + row * (y1 - y0) / H;
                double px = x, py = y;
                if (flag == 1) { px = y; py = x; }
                if (flag == 2) { px = -y; py = -x; }
                if (flag == 3) { px = -x; py = -y; }
                Orbit orb;
                orb.x.assign(maxit + 8, 0.0);
                orb.y.assign(maxit + 8, 0.0);
                RS rs = rsInit(0.05, scale, maxit);
                CDATA v;
                v.z = make(px, py);
                v.c = make(px, py);
                v.Maxit = maxit;
                v.pXTemp = orb.x.data();
                v.pYTemp = orb.y.data();
                v.dStrands = 0.05;
                v.jul = 0;
                runFormula(f, &v, false);
                rs.count = v.Iteration;
                if (getenv("TRANSFORM") && atoi(getenv("TRANSFORM")) == 4) {
                    const double e = 1e-15;
                    for (int i = 0; i < rs.count; i++) {
                        double X = orb.x[i], Y = orb.y[i];
                        double nx = e + sin((e + sin(Y)) * X);
                        double ny = e + cos((e + sin(nx)) * Y);
                        orb.x[i] = nx; orb.y[i] = ny;
                    }
                }
                renderArrays(render, rs, orb, px, py, 1);
                printf("%.9g %.9g\n", rs.outA, rs.outB);
            }
        }
        return 0;
    }
    const int W = 16, H = 12, maxit = 100;
    const double xMin = -2.5, yMin = -1.5, dx = 4.0 / W, dy = 3.0 / H;
    const double juliaX = -0.7, juliaY = 0.27015, radius = 0.3;
    const int formulas[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
                            32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55};
    std::vector<double> xs(maxit + 8), ys(maxit + 8);

    printf("{\"width\":%d,\"height\":%d,\"maxIterations\":%d,\"trapRadius\":%g,\"cases\":[", W, H, maxit, radius);
    bool first = true;
    for (int f : formulas) {
        for (int mode = 0; mode < 3; mode++) {
            bool julia = mode == 1, inside = mode == 2;
            std::vector<int> iters, shortIters;
            std::vector<double> A, B, LX, LY;
            for (int row = 0; row < H; row++) {
                for (int col = 0; col < W; col++) {
                    double x = xMin + col * dx, y = yMin + row * dy;
                    std::fill(xs.begin(), xs.end(), 0.0);
                    std::fill(ys.begin(), ys.end(), 0.0);
                    CDATA v;
                    v.z = make(x, y);
                    v.c = julia ? make(juliaX, juliaY) : make(x, y);
                    v.Maxit = maxit;
                    v.pXTemp = xs.data();
                    v.pYTemp = ys.data();
                    v.dStrands = radius;
                    v.jul = julia ? 1 : 0;
                    runFormula(f, &v, inside);

                    // Render 2, exactly as FUN_0049d158 reduces pXTemp/pYTemp[0 ..< Iteration].
                    double a = 0, b = 0;
                    for (int i = 0; i < v.Iteration; i++) {
                        double x2 = fmax(xs[i] * xs[i], 1e-24), y2 = fmax(ys[i] * ys[i], 1e-24);
                        double sx = fabs(x2 * x2 - fabs(y2 - sin(x2)));
                        double sy = fabs(y2 * y2 - fabs(x2 - sin(y2)));
                        if (sx < radius) a += 1 - sx / radius;
                        if (sy < radius) b += 1 - sy / radius;
                    }
                    iters.push_back(v.Iteration);
                    A.push_back(sqrt(a));
                    B.push_back(sqrt(b));

                    // Short horizon: the last stored orbit point after at most 4 iterations. Float rounding has
                    // not amplified yet, so this checks the translation itself, not chaotic divergence.
                    std::fill(xs.begin(), xs.end(), 0.0);
                    std::fill(ys.begin(), ys.end(), 0.0);
                    v.z = make(x, y);
                    v.c = julia ? make(juliaX, juliaY) : make(x, y);
                    v.Maxit = 4;
                    runFormula(f, &v, inside);
                    shortIters.push_back(v.Iteration);
                    LX.push_back(xs[v.Iteration - 1]);
                    LY.push_back(ys[v.Iteration - 1]);
                }
            }
            printf("%s{\"formula\":%d,\"julia\":%d,\"insideOut\":%d,\"iterations\":[", first ? "" : ",", f, julia, inside);
            for (size_t i = 0; i < iters.size(); i++) printf("%s%d", i ? "," : "", iters[i]);
            printf("],\"a\":[");
            for (size_t i = 0; i < A.size(); i++) printf("%s%.5g", i ? "," : "", A[i]);
            printf("],\"b\":[");
            for (size_t i = 0; i < B.size(); i++) printf("%s%.5g", i ? "," : "", B[i]);
            printf("],\"shortIterations\":[");
            for (size_t i = 0; i < shortIters.size(); i++) printf("%s%d", i ? "," : "", shortIters[i]);
            printf("],\"lastX\":[");
            for (size_t i = 0; i < LX.size(); i++) { printf("%s", i ? "," : ""); num(LX[i]); }
            printf("],\"lastY\":[");
            for (size_t i = 0; i < LY.size(); i++) { printf("%s", i ? "," : ""); num(LY[i]); }
            printf("]}");
            first = false;
        }
    }
    printf("]}\n");
    return 0;
}
