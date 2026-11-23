// Render stage and Lyapunov engine, shared between the Metal kernel (real = float) and the C++ oracle
// (real = double): the same text is compiled both ways, so the oracle checks the GPU's arithmetic, not a
// second hand transcription.
//
// Ported from STERLING2.EXE (addresses are the decompiled function names):
//   FUN_0049d158  render dispatcher (cases 1...32), FUN_004a0078 ... FUN_004a2474 its helpers
//   FUN_0049b4d0  per-pixel driver; the Lyapunov branch (formula >= 100) is lyapunovRun
//   FUN_0049be8c  Lyapunov map P := f(P, K)         (formulas 101...120)
//   FUN_0049c488  Lyapunov derivative term          (LDerivative 1...21)
//
// The original keeps everything in file-level globals named by their address (g786c = _DAT_004d786c ...).
// Those names are kept so every line can be compared with the decompilation. Variables that the original
// never reset between pixels are treated as zero.
//
// Provided by the platform prelude: real, rAbs rSin rCos rLog rSqrt rAtan, rRound (x87 fistp), and `Orbit`
// with X(i) / Y(i) / set(i, x, y).

#define TINY 1e-24
#define BIGV 1e24
#define EPS15 1e-15

struct RS {
    real g786c, g7874, g787c, g7884, g788c, g7894, g789c, g78a4, g78ac, g78b4, g78d4;
    real g78e0, g78e8, g78f0, g78f8;
    real g7900, g7908, g7910, g7928;
    real g7940, g7948, g7950, g7960, g7968, g7970, g7978;
    real g79a8, g79b0, g79b8, g79c0, g79c8, g79d0, g79d8, g79e0, g79e8, g79f0;
    real g7a30, g7a38;
    real radius;   // *(double *)(g7868 + 0x108): "Stalks & Bubbles Radius"
    real scale;    // *(double *)(g7868 + 0xf8): "Scale Factor 4"
    real maxit;    // *(int *)(g7868 + 0x1b8)
    int count;     // *(int *)(g7868 + 0x1bc): Iteration
    real outA, outB; // *(double *)(g7868 + 0xd0) and + 0xd8
};

// Start-of-pixel state: FUN_0049b4d0 sets the Lyapunov variables, FUN_0049d158 then clears the rest.
inline RS rsInit(real radius, real scale, int maxit) {
    RS s{};
    s.radius = radius;
    s.scale = scale;
    s.maxit = (real)maxit;
    s.g79a8 = scale;
    s.g79b0 = 0.35;
    s.g79c0 = 1.0;
    s.g79d0 = 1.0;
    s.g79d8 = 1.0;
    s.g78e0 = -BIGV;
    s.g78e8 = BIGV;
    s.g78f0 = -BIGV;
    s.g78f8 = BIGV;
    return s;
}

// ---------------------------------------------------------------------------------------------------------
// Orbit-trap renders 2...5 (FUN_0049d158 cases 2-5). `trapPoint` is also what the streaming kernel path uses.
// ---------------------------------------------------------------------------------------------------------

inline void trapPoint(int render, real radius, real px, real py, thread real &sumA, thread real &sumB) {
    real sx;
    real sy;
    if (render == 3) {
        real x = rAbs(px);
        real y = rAbs(py);
        if (x < TINY) x = TINY;
        if (y < TINY) y = TINY;
        real x2 = x * x;
        real y2 = y * y;
        sx = rAbs((rAbs(2.0 * x2) - rAbs(y2)) - rSin(y2 * y2));
        sy = rAbs((rAbs(2.0 * y2) - rAbs(x2)) - rSin(x2 * x2));
    } else if (render == 5) {
        real x = rAbs(px);
        real y = rAbs(py);
        sx = rLog(rAbs(rSin(6.28318530718 * x) + x) + 1.0);
        sy = rLog(rAbs(rSin(6.28318530718 * y) + y) + 1.0);
    } else {
        real x2 = px * px;
        real y2 = py * py;
        if (x2 < TINY) x2 = TINY;
        if (y2 < TINY) y2 = TINY;
        if (render == 2) {
            sx = rAbs(x2 * x2 - rAbs(y2 - rSin(x2)));
            sy = rAbs(y2 * y2 - rAbs(x2 - rSin(y2)));
        } else {
            sx = rAbs(rSin(y2) - rSin(x2));
            sy = rAbs(rSin(x2) - rSin(y2));
        }
    }
    if (sx < radius) sumA += 1.0 - sx / radius;
    if (sy < radius) sumB += 1.0 - sy / radius;
}

// ---------------------------------------------------------------------------------------------------------
// Statistics helpers
// ---------------------------------------------------------------------------------------------------------

inline void rsMean(thread RS &s, thread Orbit &o) {                         // FUN_004a0260
    if (-1 < s.count) {
        for (int i = 0; i < s.count; i++) {
            s.g788c = s.g788c + o.X(i);
            s.g7894 = s.g7894 + o.Y(i);
        }
        s.g788c = s.g788c / (s.count + TINY);
        s.g7894 = s.g7894 / (s.count + TINY);
    }
}

inline void rsStd(thread RS &s, thread Orbit &o) {                          // FUN_004a0178
    if (-1 < s.count) {
        for (int i = 0; i < s.count; i++) {
            s.g787c = o.X(i) - s.g788c;
            s.g7884 = o.Y(i) - s.g7894;
            s.g789c = s.g787c * s.g787c + s.g789c;
            s.g78a4 = s.g7884 * s.g7884 + s.g78a4;
        }
        s.g789c = rSqrt(s.g789c * 2.0 / (s.count + TINY) + TINY);
        s.g78a4 = rSqrt(s.g78a4 * 2.0 / (s.count + TINY) + TINY);
    }
}

inline void rsMinMax(thread RS &s, thread Orbit &o) {                       // FUN_004a0078
    if (-1 < s.count) {
        for (int i = 0; i < s.count; i++) {
            real x = o.X(i);
            real y = o.Y(i);
            if (s.g78e0 < x) s.g78e0 = x;
            if (x < s.g78e8) s.g78e8 = x;
            if (s.g78f0 < y) s.g78f0 = y;
            if (y < s.g78f8) s.g78f8 = y;
        }
        s.g786c = s.g78e0 - s.g78e8;
        s.g7874 = s.g78f0 - s.g78f8;
    }
}

// FUN_004a116c (reciprocal = true) and FUN_004a1278 (reciprocal = false)
inline void rsDimension(thread RS &s, bool reciprocal) {
    s.g78ac = 0.0;
    s.g78b4 = 0.0;
    if (0 < s.count) {
        s.g78d4 = rAbs(rLog(s.count + TINY) + TINY);
        if (TINY < rAbs(s.g78e0 - s.g78e8)) {
            real q = rAbs(s.g786c) / ((s.count + TINY) * s.g789c);
            s.g78ac = rAbs(rLog(rAbs(reciprocal ? 1.0 / q : q))) / s.g78d4;
        }
        if (TINY < rAbs(s.g78f0 - s.g78f8)) {
            real q = rAbs(s.g7874) / ((s.count + TINY) * s.g78a4);
            s.g78b4 = rAbs(rLog(rAbs(reciprocal ? 1.0 / q : q))) / s.g78d4;
        }
    }
}

// Shared prelude of the lattice renders: |x|, |y| clamped to [1e-24, 100].
#define CLAMP_XY(s, o, i) \
    s.g787c = rAbs(o.X(i)); \
    s.g7884 = rAbs(o.Y(i)); \
    if (100.0 < s.g787c) s.g787c = 100.0; \
    if (100.0 < s.g7884) s.g7884 = 100.0; \
    if (s.g787c < TINY) s.g787c = TINY; \
    if (s.g7884 < TINY) s.g7884 = TINY;

// FUN_004a1374 (render 19)
inline void rsGaussian2(thread RS &s, thread Orbit &o) {
    if (1 < s.count) {
        for (int i = 1; i < s.count; i++) {
            CLAMP_XY(s, o, i)
            s.g7908 = (real)rRound(s.g787c);
            real r2 = (real)rRound(s.g7884);
            s.g7908 = s.g7908 - s.g787c;
            real dy = r2 - s.g7884;
            s.g7928 = dy * dy + s.g7908 * s.g7908;
            s.g7908 = s.g7908 * s.g7908 + s.g7928;
            s.g7910 = dy * dy + s.g7928;
            if (s.g78e0 < s.g7908) s.g78e0 = s.g7908;
            if (s.g78f0 < s.g7910) s.g78f0 = s.g7910;
            if (s.g7908 < s.g78e8 && TINY < s.g7908) s.g78e8 = s.g7908;
            if (s.g7910 < s.g78f8 && TINY < s.g7910) s.g78f8 = s.g7910;
        }
    }
}

// FUN_004a1558 (render 20)
inline void rsGaussian3(thread RS &s, thread Orbit &o) {
    if (0 < s.count) {
        for (int i = 0; i < s.count; i++) {
            CLAMP_XY(s, o, i)
            real dx = (real)rRound(s.g787c) - s.g787c;
            real dy = (real)rRound(s.g7884) - s.g7884;
            s.g7908 = rAbs(dx * dx - dy * dy);
            if (s.g78e0 < s.g7908) s.g78e0 = s.g7908;
            if (s.g78f0 < s.g7908) s.g78f0 = s.g7908;
            s.g7910 = s.g7908;
            s.g7928 = s.g7908;
        }
    }
}

// FUN_004a16ec (render 22)
inline void rsGaussian5(thread RS &s, thread Orbit &o) {
    if (0 < s.count) {
        for (int i = 0; i < s.count; i++) {
            CLAMP_XY(s, o, i)
            s.g7908 = (real)rRound(s.g787c * s.scale) - s.g787c * s.scale;
            real dy = (real)rRound(s.g7884 * s.scale) - s.g7884 * s.scale;
            s.g7928 = dy * dy + s.g7908 * s.g7908;
            s.g7908 = s.g7928 * s.g787c;
            s.g7910 = s.g7928 * s.g7884;
            if (s.g7908 < s.g78e8) s.g78e8 = s.g7908;
            if (s.g78e0 < s.g7908) s.g78e0 = s.g7908;
            if (s.g7910 < s.g78f8) s.g78f8 = s.g7910;
            if (s.g78f0 < s.g7910) s.g78f0 = s.g7910;
            s.g7960 = s.g7960 + s.g7908;
            s.g7968 = s.g7908 * s.g7908 + s.g7968;
            s.g7970 = s.g7970 + s.g7910;
            s.g7978 = s.g7910 * s.g7910 + s.g7978;
        }
        real inv = 1.0 / s.maxit;
        s.g7900 = inv;
        if (TINY < s.g78e0 - s.g78e8) {
            s.g78ac = rLog(2.0 * s.g7968 - (s.g7960 * s.g7950) / rAbs(s.g78e0 - s.g78e8)) * inv;
        }
        if (TINY < s.g78f0 - s.g78f8) {
            s.g78b4 = rLog(2.0 * s.g7978 - (s.g7970 * s.g7950) / rAbs(s.g78f0 - s.g78f8)) * inv;
        }
    }
}

// FUN_004a1a14 (render 23)
inline void rsGaussian6(thread RS &s, thread Orbit &o) {
    if (0 < s.count) {
        for (int i = 0; i < s.count; i++) {
            s.g787c = o.X(i);
            s.g7884 = o.Y(i);
            if (100.0 < rAbs(s.g787c)) s.g787c = 100.0;
            if (100.0 < rAbs(s.g7884)) s.g7884 = 100.0;
            if (rAbs(s.g787c) < TINY) s.g787c = TINY;
            if (rAbs(s.g7884) < TINY) s.g7884 = TINY;
            s.g787c = s.g787c * s.g787c - s.g7884;
            s.g7884 = s.g7884 * s.g7884 - s.g787c;
            real r1 = (real)rRound(s.g787c);
            real r2 = (real)rRound(s.g7884);
            s.g7908 = ((EPS15 + r1) - s.g787c) * s.scale;
            s.g7910 = ((EPS15 + r2) - s.g7884) * s.scale;
            s.g7908 = s.g7908 * s.g7908;
            s.g7910 = s.g7910 * s.g7910;
            if (s.g7908 < s.g78e8) s.g78e8 = s.g7908;
            if (s.g78e0 < s.g7908) { s.g78e0 = s.g7908; s.g7940 = s.g7908; s.g7960 = s.g7908; }
            if (s.g7910 < s.g78f8) s.g78f8 = s.g7910;
            if (s.g78f0 < s.g7910) { s.g78f0 = s.g7910; s.g7948 = s.g7910; s.g7970 = s.g7910; }
        }
    }
}

// FUN_004a1c8c (render 21 pre-pass): X, Y := X/Y, Y/X
inline void rsRatio(thread RS &s, thread Orbit &o) {
    for (int i = 0; i < s.count; i++) {
        real x = o.X(i);
        real y = o.Y(i);
        if (100.0 < x) x = 100.0;
        if (rAbs(x) < TINY) x = TINY;
        if (100.0 < y) y = 100.0;
        if (rAbs(y) < TINY) y = TINY;
        o.set(i, x / y, y / x);
    }
}

// FUN_004a1d70, 1fa8, 220c, 2474 (renders 10...13): "gaussian" lattice sums. `kind` selects the formula that
// differs between them; the rest (round, weighted sum, *3) is common.
inline void rsGaussianSum(thread RS &s, thread Orbit &o, int kind) {
    if (0 < s.count) {
        for (int i = 0; i < s.count; i++) {
            if (kind == 10) {
                s.g787c = o.X(i);
                s.g7884 = o.Y(i);
                if (100.0 < rAbs(s.g787c)) s.g787c = 100.0;
                if (100.0 < rAbs(s.g7884)) s.g7884 = 100.0;
                s.g7900 = s.g7884 * s.g7884 + s.g787c * s.g787c;
                if (s.g7900 < TINY) s.g7900 = TINY;
                s.g7908 = rSin(rAbs(s.g7900) * s.scale);
                s.g7910 = rSin(rAbs(s.g7900) * s.scale);
            } else {
                s.g787c = rAbs(o.X(i));
                s.g7884 = rAbs(o.Y(i));
                if (100.0 < s.g787c) s.g787c = 100.0;
                if (100.0 < s.g7884) s.g7884 = 100.0;
                if (kind == 11) {
                    s.g7908 = rSin((s.g787c + TINY) * s.g787c);
                    s.g7910 = rSin((s.g7884 + TINY) * s.g7884);
                    if (s.g7908 < TINY) s.g7908 = TINY;
                    if (s.g7910 < TINY) s.g7910 = TINY;
                    s.g7908 = rSin(rAbs(s.g7908) * s.scale);
                    s.g7910 = rSin(rAbs(s.g7910) * s.scale);
                } else if (kind == 12) {
                    s.g7908 = rAbs(rSin(s.g787c + TINY));
                    s.g7910 = rAbs(rSin(s.g7884 + TINY));
                    if (s.g7908 < TINY) s.g7908 = TINY;
                    if (s.g7910 < TINY) s.g7910 = TINY;
                    s.g7908 = rSin(rAbs(s.g7910 + TINY + s.g7908) * s.scale);
                    s.g7910 = rSin(rAbs(s.g7908 + TINY + s.g7910) * s.scale);
                } else {
                    s.g7908 = rSin(s.g787c * s.g7884 + TINY);
                    s.g7910 = rCos(s.g787c * s.g7884 + TINY);
                    if (s.g7908 < TINY) s.g7908 = TINY;
                    if (s.g7910 < TINY) s.g7910 = TINY;
                    s.g7908 = rSin(rAbs(s.g7908) * s.scale);
                    s.g7910 = rSin(rAbs(s.g7910) * s.scale);
                }
            }
            s.g787c = (real)rRound(s.g7908);
            real r2 = (real)rRound(s.g7910);
            real w = i + rLog(EPS15 + (i + 2));
            s.g788c = rAbs(s.g7908 - s.g787c) / w + s.g788c;
            s.g7894 = rAbs(s.g7910 - r2) / w + s.g7894;
            s.g7884 = r2;
        }
        s.g788c = (s.g788c / rLog(EPS15 + (s.count + 1))) * 3.0;
        s.g7894 = (s.g7894 / rLog(EPS15 + (s.count + 1))) * 3.0;
    }
}

// FUN_004a0d68 (render 26)
inline void rsSineDim8(thread RS &s, thread Orbit &o) {
    if (0 < s.count) {
        for (int i = 0; i < s.count; i++) {
            CLAMP_XY(s, o, i)
            s.g7908 = rSin(s.g787c * s.g787c);
            s.g7910 = rSin(s.g7884 * s.g7884);
            s.g7928 = rSqrt(s.g7910 * s.g7910 + s.g7908 * s.g7908);
            s.g7908 = rSin(s.g787c) + s.g7928;
            s.g7910 = rSin(s.g7884) + s.g7928;
            if (s.g78e0 < s.g7908) s.g78e0 = s.g7908;
            if (s.g78f0 < s.g7910) s.g78f0 = s.g7910;
            if (s.g7908 < s.g78e8 && TINY < rAbs(s.g7908)) s.g78e8 = s.g7908;
            if (s.g7910 < s.g78f8 && TINY < rAbs(s.g7910)) s.g78f8 = s.g7910;
            s.g788c = s.g7908 / (EPS15 + i);
            s.g7894 = s.g7910 / (EPS15 + i);
            s.g7960 = s.g7908 + s.g788c;
            s.g7970 = s.g7910 + s.g7894;
            s.g789c = s.g7960 * s.g7960 + s.g789c;
            s.g78a4 = s.g7970 * s.g7970 + s.g78a4;
        }
        real a = rSqrt(s.g789c * 2.0 / (s.count + TINY) + TINY);
        real b = rSqrt(s.g78a4 * 2.0 / (s.count + TINY) + TINY);
        s.g789c = a;
        s.g78a4 = b;
        s.g78d4 = rAbs(rLog(s.count + TINY) + TINY);
        s.g78e0 = rAbs(s.g78e0);
        s.g78e8 = rAbs(s.g78e8);
        if (s.g78e0 - s.g78e8 < TINY) s.g78e0 = s.g78e0 + TINY;
        s.g78f0 = rAbs(s.g78f0);
        s.g78f8 = rAbs(s.g78f8);
        if (s.g78f0 - s.g78f8 < TINY) s.g78f0 = s.g78f0 + TINY;
        s.g786c = s.g78e0 - s.g78e8;
        s.g7874 = s.g78f0 - s.g78f8;
        if (TINY < rAbs(s.g786c)) {
            s.g78ac = rAbs(rLog(rAbs(s.g786c) / ((s.count + TINY) * a))) / s.g78d4;
        }
        if (TINY < rAbs(s.g7874)) {
            s.g78b4 = rAbs(rLog(rAbs(s.g7874) / ((s.count + TINY) * b))) / s.g78d4;
        }
    }
}

// FUN_004a0900 (render 27)
inline void rsSineDim9(thread RS &s, thread Orbit &o) {
    if (0 < s.count) {
        s.g78ac = 0.0;
        s.g78b4 = 0.0;
        for (int i = 0; i < s.count; i++) {
            CLAMP_XY(s, o, i)
            s.g7908 = (real)rRound(s.g787c);
            real r2 = (real)rRound(s.g7884);
            s.g7908 = s.g7908 - s.g787c;
            s.g7910 = r2 - s.g7884;
            s.g7928 = s.g7910 * s.g7910 + s.g7908 * s.g7908;
            s.g7908 = rSin(s.g7928 * s.g787c * s.g787c);
            s.g7910 = rSin(s.g7928 * s.g7884 * s.g7884);
            if (s.g78e0 < s.g7908) s.g78e0 = s.g7908;
            if (s.g78f0 < s.g7910) s.g78f0 = s.g7910;
            if (s.g7908 < s.g78e8 && TINY < rAbs(s.g7908)) s.g78e8 = s.g7908;
            if (s.g7910 < s.g78f8 && TINY < rAbs(s.g7910)) s.g78f8 = s.g7910;
            s.g788c = s.g7908 / (EPS15 + i);
            s.g7894 = s.g7910 / (EPS15 + i);
            s.g7960 = s.g7908 + s.g788c;
            s.g7968 = s.g788c * s.g788c + s.g7968;
            s.g7970 = s.g7910 + s.g7894;
            s.g7978 = s.g7894 * s.g7894 + s.g7978;
            if (BIGV < rAbs(s.g7960)) s.g7960 = BIGV;
            if (BIGV < rAbs(s.g7970)) s.g7970 = BIGV;
            s.g789c = s.g7960 * s.g7960 + s.g789c;
            s.g78a4 = s.g7970 * s.g7970 + s.g78a4;
        }
        s.g789c = rSqrt(s.g789c * 2.0 / (s.count + TINY) + TINY);
        s.g78a4 = rSqrt(s.g78a4 * 2.0 / (s.count + TINY) + TINY);
        s.g78d4 = rAbs(rLog(s.count + TINY) + TINY);
        real inv = 1.0 / s.maxit;
        s.g7900 = inv;
        if (TINY < s.g78e0 - s.g78e8) {
            s.g78ac = rLog(2.0 * s.g7968 - (s.g7960 * s.g7950) / rAbs(s.g78e0 - s.g78e8)) * inv;
        }
        if (TINY < s.g78f0 - s.g78f8) {
            s.g78b4 = rLog(2.0 * s.g7978 - (s.g7970 * s.g7950) / rAbs(s.g78f0 - s.g78f8)) * inv;
        }
    }
}

// FUN_004a0620 (render 28)
inline void rsSineDim10(thread RS &s, thread Orbit &o) {
    if (0 < s.count) {
        real minX = s.g78e8;
        real minY = s.g78f8;
        for (int i = 0; i < s.count; i++) {
            s.g787c = rAbs(o.X(i)) * rAbs(o.X(i));
            s.g7884 = rAbs(o.Y(i)) * rAbs(o.Y(i));
            if (s.g78e0 < s.g787c) s.g78e0 = s.g787c;
            if (s.g78f0 < s.g7884) s.g78f0 = s.g7884;
            if (s.g787c < minX && TINY < rAbs(s.g787c)) minX = s.g787c;
            if (s.g7884 < minY && TINY < rAbs(s.g7884)) minY = s.g7884;
            s.g788c = rAbs(s.g7908) / (EPS15 + i);
            s.g7894 = rAbs(s.g7910) / (EPS15 + i);
            s.g7960 = s.g787c + s.g788c;
            s.g7970 = s.g7884 + s.g7894;
            s.g789c = s.g7960 * s.g7960 + s.g789c;
            s.g78a4 = s.g7970 * s.g7970 + s.g78a4;
        }
        s.g789c = rSqrt(s.g789c * 2.0 / (s.count + TINY) + TINY);
        s.g78a4 = rSqrt(s.g78a4 * 2.0 / (s.count + TINY) + TINY);
        s.g78d4 = rAbs(rLog(s.count + TINY) + TINY);
        real inv = 1.0 / s.maxit;
        s.g7900 = inv;
        s.g786c = s.g78e0 - minX;
        s.g7874 = s.g78f0 - minY;
        if (s.g786c < TINY) s.g786c = TINY;
        if (s.g7874 < TINY) s.g7874 = TINY;
        s.g78ac = rLog(rAbs(EPS15 + s.g7960) / s.g786c) * inv;
        s.g78b4 = rLog(rAbs(EPS15 + s.g7970) / s.g7874) * inv;
        s.g78e8 = minX;
        s.g78f8 = minY;
    }
}

// FUN_004a02fc (render 29)
inline void rsSineDim11(thread RS &s, thread Orbit &o) {
    if (0 < s.count) {
        real minX = s.g78e8;
        real minY = s.g78f8;
        for (int i = 0; i < s.count; i++) {
            real dx = rAbs(o.X(i));
            real dy = rAbs(o.Y(i));
            s.g7928 = dy * dy + dx * dx;
            s.g7908 = rAbs(s.g7928 / (dx * dx + 1.0));
            s.g7910 = rAbs(s.g7928 / (dy * dy + 1.0));
            if (s.g78e0 < s.g7908) s.g78e0 = s.g7908;
            if (s.g78f0 < s.g7910) s.g78f0 = s.g7910;
            if (s.g7908 < minX) minX = s.g7908;
            if (s.g7910 < minY) minY = s.g7910;
            s.g788c = rAbs(s.g7908) / (EPS15 + (i + 1));
            s.g7894 = rAbs(s.g7910) / (EPS15 + (i + 1));
            s.g7960 = s.g7908 + s.g788c;
            s.g7970 = s.g7910 + s.g7894;
            s.g789c = s.g7960 * s.g7960 + s.g789c;
            s.g78a4 = s.g7970 * s.g7970 + s.g78a4;
        }
        real a = rSqrt(s.g789c * 2.0 / (s.count + TINY) + TINY);
        real b = rSqrt(s.g78a4 * 2.0 / (s.count + TINY) + TINY);
        s.g789c = a;
        s.g78a4 = b;
        s.g78d4 = rAbs(rLog(s.count + TINY) + TINY);
        s.g786c = s.g78e0 - minX;
        s.g7874 = s.g78f0 - minY;
        if (s.g786c < TINY) s.g786c = TINY;
        if (s.g7874 < TINY) s.g7874 = TINY;
        if (TINY < rAbs(s.g786c)) {
            s.g78ac = rAbs(rLog(rAbs(s.g786c) / ((s.count + TINY) * a))) / s.g78d4;
        }
        if (TINY < rAbs(s.g7874)) {
            s.g78b4 = rAbs(rLog(rAbs(s.g7874) / ((s.count + TINY) * b))) / s.g78d4;
        }
        s.g78e8 = minX;
        s.g78f8 = minY;
    }
}

// Sine-trap renders 14...17 (cases 0xe...0x11). Shared tail: the decaying average g79d0 / g79d8.
inline void rsSineTrap(thread RS &s, thread Orbit &o, int render) {
    s.g79d0 = 0.0;
    s.g79d8 = 0.0;
    s.g79e0 = 0.0;
    s.g79e8 = 0.0;
    for (int i = 1; i < s.count; i++) {
        real x = rAbs(o.X(i));
        real y = rAbs(o.Y(i));
        real a;
        real b;
        real tA;
        real tB;
        if (render == 14) {
            a = x * y - x + rSin(x) - rSin(x * x);
            b = x * y - x + rSin(y) - rSin(y * y);
            tA = s.radius;
            tB = s.radius;
        } else if (render == 15) {
            a = 2.0 - 1.0 / (((y * x + 0.5) - y) - rSin(y * y));
            b = 2.0 - 1.0 / (((y * a + 0.5) - a) - rSin(a * a));
            tA = s.radius;
            tB = s.radius;
        } else if (render == 16) {
            tA = rSin(x * x) + TINY;
            tB = rSin(y * y) + TINY;
            a = 2.0 - 1.0 / (((y * x + 0.5) - y) - rSin(y * y));
            b = 2.0 - 1.0 / (((y * x + 0.5) - x) - rSin(x * x));
        } else {
            tA = rSin(x * x) + TINY;
            tB = rSin(y * y) + TINY;
            a = ((y * y - x) + (1.0 - rSin(x * x) * y));
            b = ((x * x - y) + (1.0 - rSin(y * y) * x));
        }
        if (a < tA) s.g79e0 = 1.0 - a / tA;
        if (b < tB) s.g79e8 = 1.0 - b / tB;
        if (render <= 15) {
            s.g79d0 = 0.2 * s.g79d0 + (2.0 - 1.0 / (rAbs(s.g79e0) + 0.5));
            s.g79d8 = 0.2 * s.g79d8 + (2.0 - 1.0 / (rAbs(s.g79e8) + 0.5));
        } else {
            s.g79d0 = 0.2 * s.g79d0 + 1.0 / (rAbs(s.g79e0) + 1.0);
            s.g79d8 = 0.2 * s.g79d8 + 1.0 / (rAbs(s.g79e8) + 1.0);
        }
    }
    if (s.g79e0 != 0.0) s.g79d0 = s.g79e0;
    if (s.g79e8 != 0.0) s.g79d8 = s.g79e8;
    if (s.g79d0 == 100.0) s.g79d0 = 0.0;
    if (s.g79d8 == 100.0) s.g79d8 = 0.0;
    if (render <= 15) {
        s.outA = 1.0 - 1.0 / (s.g79d0 + 1.0);
        s.outB = 1.0 - 1.0 / (s.g79d8 + 1.0);
    } else {
        if (s.g79e0 != 0.0) s.outA = 1.0 - 1.0 / (s.g79d0 + 1.0);
        if (s.g79e8 != 0.0) s.outB = 1.0 - 1.0 / (s.g79d8 + 1.0);
    }
}

// Render 24, "Triangle Inequality Variation" (case 0x18). (cx, cy) is the c parameter.
inline void rsTriangle(thread RS &s, thread Orbit &o, real cx, real cy) {
    s.g7950 = 0.0;
    real g7a48 = 0.0;
    const real g7a58 = 1.0 / rLog(2.0);
    const real g7a60 = rLog(rLog(1e24) * 0.5);
    if (3 < s.count) {
        real len2 = 0.0;
        for (int i = 2; i < s.count; i++) {
            g7a48 = s.g7950;
            real x = o.X(i);
            real y = o.Y(i);
            real g7980 = rSqrt(y * y + x * x);
            real g7a50 = rSqrt(cy * cy + cx * cx);
            real g7a68 = rSqrt(rAbs(cx - x) * rAbs(cx - x) + rAbs(cy - y) * rAbs(cy - y));
            if (rAbs(g7a68) < TINY) g7a68 = 1e-24;
            if (BIGV < rAbs(g7a68)) g7a68 = BIGV;
            real g7a70 = rAbs(g7a68 - g7a50);
            real g78bc = g7980 - g7a70;
            real g78d4 = (g7a68 + g7a50) - g7a70;
            if (rAbs(g78bc) < TINY) g78bc = TINY;
            if (rAbs(g78d4) < TINY) g78d4 = TINY;
            if (BIGV < rAbs(g78bc)) g78bc = BIGV;
            if (BIGV < rAbs(g78d4)) g78d4 = BIGV;
            real g79f8 = g78bc / g78d4;
            s.g7950 = g79f8 * g79f8 + s.g7950;
            len2 = g7980;
        }
        real x = o.X(s.count - 1);
        real y = o.Y(s.count - 1);
        real g7980 = y * y + x * x;
        s.g7950 = s.g7950 / s.count;
        g7a48 = g7a48 / (s.count - 1);
        // The original substitutes 1 + 1e-15 for an exact 1; float32 cannot hold that, so the logarithm
        // (1e-15 either way) is substituted instead.
        real lnNearOne = (rAbs(1.0 - g7980) < TINY) ? 1e-15 : rLog(g7980);
        real g78bc = rLog(rAbs(lnNearOne)) * g7a58;
        real g7a78 = g7a58 * g7a60 - g78bc;
        s.outA = (g7a78 + 1.0) * (s.g7950 - g7a48) + g7a48;
        s.outA = s.outA * s.outA;
        s.outB = s.outA;
        (void)len2;
    }
}

// Render 25, "log counting" (case 0x19)
inline void rsLogCounting(thread RS &s, thread Orbit &o) {
    s.g7950 = 0.0;
    s.g7960 = 0.0;
    s.g7970 = 0.0;
    if (0 < s.count) {
        for (int i = 1; i < s.count; i++) {
            real x = o.X(i);
            real y = o.Y(i);
            if (rAbs(x) < TINY) x = TINY;
            if (rAbs(y) < TINY) y = TINY;
            real g7988 = (x * x) / (y * y);
            // ln(x^2 / y^2) computed from logs: after the 1e-24 floor, x^2 is 1e-48, which underflows in float32.
            // The original also substitutes 1 + 1e-15 for a ratio of exactly 1; here the logarithm (1e-15) is
            // substituted, because float32 cannot hold 1 + 1e-15.
            real lg = 2.0 * (rLog(rAbs(x)) - rLog(rAbs(y)));
            real l1 = (rAbs(lg) <= EPS15) ? 1e-15 : lg;
            real l2 = (rAbs(lg) <= EPS15) ? 1e-15 : -lg;
            (void)g7988;
            real g78c4 = rLog(rAbs(l1));
            s.g7960 = s.g7960 - 1.0 / (rAbs(rLog(rAbs(g78c4))) + 1.0);
            real g78cc = rLog(rAbs(l2));
            s.g7970 = s.g7970 - 1.0 / (rAbs(rLog(rAbs(g78cc))) + 1.0);
        }
        if (1 < s.count) {
            s.g7960 = s.g7960 / (s.count + rLog((real)(s.count + 2)));
            s.outA = s.g7960;
            s.g7970 = s.g7970 / (s.count + rLog((real)(s.count + 2)));
            s.outB = s.g7970;
        }
    }
}

// Render 18, "x/y; y/x; stalks" pre-pass (case 0x12): folds X, Y into a stalk profile in place.
inline void rsStalks(thread RS &s, thread Orbit &o) {
    for (int i = 0; i < s.count; i++) {
        CLAMP_XY(s, o, i)
        real x = s.g787c;
        real y = s.g7884;
        o.set(i, s.radius <= x ? 0.0 : (1.0 / (x / s.radius + 1.0)) * 100.0,
                 s.radius <= y ? 0.0 : (1.0 / (y / s.radius + 1.0)) * 100.0);
    }
}

// ---------------------------------------------------------------------------------------------------------
// Lyapunov (formula >= 100): FUN_0049b4d0's Lyapunov branch, FUN_0049be8c and FUN_0049c488
// ---------------------------------------------------------------------------------------------------------

// P := f(P, K) for Lyapunov formulas 101...120 (FUN_0049be8c)
inline void lyMap(thread RS &s, int formula) {
    real P = s.g79b0;
    real K = s.g79b8;
    real B = s.g79a8;
    if (rAbs(P) < 100.0 && TINY < rAbs(P)) {
        switch (formula) {
        case 101: P = (K * P - K * P * P) * B; break;
        case 102: P = rSin(P + K) * B * rSin(P + K); break;
        case 103: P = ((((B * 0.25 * P + (K * P - K * P * P)) - B * 2.0) - P) + 2.0) * B; break;
        case 104: P = (K * P - rSin(P)) * B; break;
        case 105: P = (K * P - rSin(1.0 - P)) * B; break;
        case 106: P = ((1.0 - (1.0 - P) * P * K) * (1.0 - rSin(P)) * B); break;
        case 107: P = rAbs((P * P - K * K) - rSin(rAbs(K)) / rAbs(P)) * B; break;
        case 108: P = (1.0 - P) * B * K * rSin(K + P) * rSin(K + P); break;
        case 109: P = (1.0 - P) * B * K * rSin(K); break;
        case 110: P = (1.0 - P) * B * K * rSin(K + P) * rSin(K + P); break;
        case 111: P = (1.0 - P) * B * K * (P - rCos(K)); break;
        case 112: P = rSin(P + K) * B * rSin(P + K); break;
        case 113: P = rSin(P + K) * 2.0 * B * rSin(P + K); break;
        case 114: P = rSin(P + K) * B * rSin(P + K); P = P * P; break;
        case 115: P = (1.0 - P) * rSin(P + K) * B * rCos(P + K); break;
        case 116: P = (1.0 - P) * rSin(P - K) * B * rCos(P - K); break;
        case 117: P = rSin(P - K) * B * rCos(P - K); break;
        case 118: P = rCos(P * K) * B * rSin(P * K); break;
        case 119: P = rSin(1.0 - K) * B * rCos(P * K) * rCos(P + K); break;
        case 120: P = B * K * rSin(P + K) * rCos(P + K); break;
        default: break;
        }
    }
    s.g79b0 = P;
}

// L := L * dP'(P, K) and the two auxiliary sums (FUN_0049c488). `which` is the LDerivative menu number.
inline void lyDeriv(thread RS &s, int which) {
    real P = s.g79b0;
    real K = s.g79b8;
    real B = s.g79a8;
    if (rAbs(P) < 100.0 && TINY < rAbs(P) && s.g79c0 < BIGV &&
        rAbs(K) < 100.0 && TINY < rAbs(K) && s.g79d0 < BIGV && s.g79d8 < BIGV) {
        real L = s.g79c0;
        real x = s.g7a30;
        real y = s.g7a38;
        real d0 = s.g79d0;
        real d8 = s.g79d8;
        bool same = true; // most variants set both auxiliary sums to L
        switch (which) {
        case 1:
            L = (K - K * 2.0 * P) * L;
            d0 = ((y * y + x * x) - rAbs(x)) * d0;
            d8 = ((y * y + x * x) - rAbs(y)) * d8;
            same = false;
            break;
        case 2:
            L = 2.0 * B * rSin(P + K) * rCos(P + K) * L;
            d0 = ((rAbs(x * y) - rAbs(y)) + rSin(rAbs(y * y))) * d0;
            d8 = ((rAbs(x * y) - rAbs(x)) + rSin(rAbs(x * x))) * d8;
            same = false;
            break;
        case 3:
            L = ((((B * 0.25 * P + (P - K * 2.0 * P)) - B * 2.0) - P) + 2.0) * L * B;
            d0 = ((rAbs(y * y) - rSin(rAbs(x))) * d0);
            d8 = ((rAbs(x * x) - rSin(rAbs(y))) * d8);
            same = false;
            break;
        case 4:
            L = L * B * (K - rSin(P * P));
            d0 = (((x * x) / (y - rSin(y * y))) * d0);
            d8 = (((y * y) / (x - rSin(x * x))) * d8);
            same = false;
            break;
        case 5: L = L * B * (K - rSin(1.0 - P * P)); break;
        case 6: L = L * B * (rAbs(rSin(P)) - rAbs(P) * rAbs(rSin(P) * K)); break;
        case 7: L = L * B * rAbs((P * P - K * K) - rSin(rAbs(K)) / rAbs(P)); break;
        case 8: L = L * B * rAbs((P * P - K * K) - rCos(rAbs(K)) / rAbs(rSin(K * P))); break;
        case 9: L = L * B * (1.0 - P) * rSin(K * K) * P * K; break;
        case 10: L = L * B * (1.0 - P) * rSin(K + P) * rSin(K + P) * K; break;
        case 11: L = L * B * (1.0 - P) * (P - rCos(K)) * K; break;
        case 12: L = L * B * rSin(P + K) * rSin(P + K); break;
        case 13: L = L * B * rSin(P + K) * 2.0 * rSin(P + K); break;
        case 14: L = L * B * rSin(P + K) * rSin(P + K); break;
        case 15: L = L * B * (1.0 - P) * rSin(P + K) * rCos(P + K); break;
        case 16: L = L * B * (1.0 - P) * rSin(P - K) * rCos(P - K); break;
        case 17: L = L * B * rSin(P - K) * rCos(P - K); break;
        case 18: L = L * B * rSin(1.0 - K) * rCos(P * K) * rCos(P + K); break;
        case 19: L = L * B * rSin(P + K) * K * rCos(P + K); break;
        case 20: L = L * B * rSin(1.0 - K) * rCos(P * K) * rCos(P + K); break;
        case 21: L = L * B * ((K * K + P) - rSin(1.0 - P * P)); break;
        default:
            L = ((rAbs(K) - rAbs(P)) - rSin(rAbs(P) - rSin(K))) * L;
            break;
        }
        s.g79c0 = L;
        if (same) {
            s.g79d0 = L;
            s.g79d8 = L;
        } else {
            s.g79d0 = d0;
            s.g79d8 = d8;
        }
    }
}

// K for iteration `it`: the LMapping menu (FUN_0049b4d0's switch). c = (cx, cy), len2 = |c|^2 + 1e-24.
inline real lyK(int mapping, int it, real cx, real cy, real len2) {
    bool even = (it & 1) == 0;
    switch (mapping) {
    case 1: return TINY + (even ? cy : cx);
    case 2: return rAbs(TINY + (even ? cx : cy));
    case 3: return rAbs(len2 / rAbs(TINY + (even ? cx : cy)) + TINY);
    case 4: return rAbs(len2 / rAbs((1.0 - rSin(even ? cx : cy)) + TINY) + TINY);
    case 5: { real v = even ? cx : cy; return rAbs(rSin(v) / rCos(v) + TINY); }
    case 6: { real v = even ? cx : cy; return rAbs(rAbs(rAbs(v) + TINY + rSin(v * v))); }
    case 7: return even ? rAtan(rAbs(cx / (TINY + cy))) * len2 : rAtan(rAbs(cy / (TINY + cx))) * len2;
    case 8: return even ? rAbs(rAbs(cx + cy) + TINY) : rAbs(rAbs(cy - cx) + TINY);
    default: { real v = even ? cx : cy; return rAbs((rAbs(v) + TINY) - rSin(v * v)); }
    }
}

// The Lyapunov branch of FUN_0049b4d0. Fills the orbit with (K, P) for renders 30 and 32 and with the
// running exponent term otherwise, and returns the number of stored entries (Iteration).
inline int lyapunovRun(thread RS &s, thread Orbit &o, int formula, int mapping, int derivative, int render,
                       real cx, real cy, bool insideOut, int maxit) {
    real len2 = cy * cy + cx * cx + TINY;
    if (insideOut && formula > 100) {
        cx = 1.0 / (TINY + cx);
        cy = 1.0 / (TINY + cy);
    }
    int it = 0;
    do {
        s.g79b8 = lyK(mapping, it, cx, cy, len2);
        lyMap(s, formula);
        if (render == 30 || render == 32) {
            o.set(it, s.g79b8, s.g79b0);
        } else {
            lyDeriv(s, derivative);
            s.g79c8 = rAbs(rLog(rAbs(TINY + s.g79c0)));
            s.g79c0 = (s.g79b8 - s.g79b8 * 2.0 * s.g79b0) * s.g79c0;
            o.set(it, s.g79c8, s.g79c8);
        }
        it += 1;
    } while (it <= maxit && rAbs(s.g79c0) <= BIGV && TINY <= rAbs(s.g79c0));
    return it;
}

// ---------------------------------------------------------------------------------------------------------
// The render dispatcher: reduces the orbit (already transformed) to the two values A and B.
// ---------------------------------------------------------------------------------------------------------

inline void renderArrays(int render, thread RS &s, thread Orbit &o, real cx, real cy, int derivative) {
    switch (render) {
    case 1:
        s.outA = rAbs(rLog(1.0 / s.count));
        s.outB = s.outA;
        break;
    case 2: case 3: case 4: case 5: {
        real a = 0.0;
        real b = 0.0;
        for (int i = 0; i < s.count; i++) trapPoint(render, s.radius, o.X(i), o.Y(i), a, b);
        s.outA = rSqrt(a);
        s.outB = rSqrt(b);
        break;
    }
    case 6:
        rsMean(s, o); rsStd(s, o);
        s.outA = s.g789c; s.outB = s.g78a4;
        break;
    case 7:
        rsMean(s, o); rsStd(s, o); rsMinMax(s, o);
        s.outA = s.g786c; s.outB = s.g7874;
        break;
    case 8:
        rsMean(s, o); rsStd(s, o); rsMinMax(s, o); rsDimension(s, true);
        s.outA = s.g78ac * 2.0; s.outB = s.g78b4 * 2.0;
        break;
    case 9:
        rsMean(s, o);
        s.outA = 1.0 - 1.0 / (rAbs(s.g788c) + 1.0);
        s.outB = 1.0 - 1.0 / (rAbs(s.g7894) + 1.0);
        break;
    case 10: case 11: case 12: case 13:
        rsGaussianSum(s, o, render);
        s.outA = s.g788c; s.outB = s.g7894;
        break;
    case 14: case 15: case 16: case 17:
        rsSineTrap(s, o, render);
        break;
    case 18:
        rsStalks(s, o);
        rsMean(s, o); rsStd(s, o); rsMinMax(s, o); rsDimension(s, true);
        s.outA = s.g78ac; s.outB = s.g78b4;
        break;
    case 19:
        rsGaussian2(s, o);
        s.outA = s.g7908; s.outB = s.g7910;
        break;
    case 20:
        rsGaussian3(s, o);
        s.outA = s.g7908; s.outB = s.g7910;
        break;
    case 21:
        rsRatio(s, o);
        rsMean(s, o); rsStd(s, o); rsMinMax(s, o); rsDimension(s, false);
        s.outA = s.g78ac; s.outB = s.g78b4;
        break;
    case 22:
        rsGaussian5(s, o);
        s.outA = s.g78ac; s.outB = s.g78b4;
        break;
    case 23:
        rsGaussian6(s, o);
        s.outA = s.g7940; s.outB = s.g7948;
        break;
    case 24:
        rsTriangle(s, o, cx, cy);
        break;
    case 25:
        rsLogCounting(s, o);
        break;
    case 26:
        rsSineDim8(s, o);
        s.outA = s.g78ac; s.outB = s.g78b4;
        break;
    case 27:
        rsSineDim9(s, o);
        s.outA = s.g78ac * 2.0; s.outB = s.g78b4 * 2.0;
        break;
    case 28:
        rsSineDim10(s, o);
        s.outA = s.g78ac; s.outB = s.g78b4;
        break;
    case 29:
        rsSineDim11(s, o);
        s.outA = s.g78ac; s.outB = s.g78b4;
        break;
    case 30: case 32: {
        s.g7950 = 0.0;
        if (0 < s.count) {
            s.g79c0 = 1.0;
            s.g79c8 = 0.0;
            for (int i = 1; i < s.count; i++) {
                s.g79b8 = o.X(i);
                s.g79b0 = o.Y(i);
                s.g79c8 = rAbs(rLog(rAbs(TINY + s.g79c0)));
                if (render == 30) s.g7950 = 1.0 / (s.g79c8 + 1.0) + TINY + s.g7950;
                else s.g7950 = rSqrt(s.g7950 + TINY + s.g79c8);
                lyDeriv(s, derivative);
                real stored = render == 30 ? s.g79c8 : rSqrt(TINY + s.g79c8);
                o.set(i, stored, stored);
            }
        }
        if (rAbs(s.g79c8) < TINY) s.g79c8 = TINY;
        if (rAbs(s.g79c8) < BIGV && TINY < rAbs(s.g79c8)) {
            if (BIGV <= rAbs(s.g79c0)) s.outA = 0.0;
            else s.outA = rAbs(s.g7950 / rLog((real)s.count));
            if (rAbs(s.outA) < TINY) s.outA = TINY;
            s.outB = s.outA;
        }
        break;
    }
    case 31: {
        real minA = s.g78e8;
        real minB = s.g78f8;
        if (0 < s.count) {
            s.g79c0 = 1.0;
            s.g79c8 = TINY;
            for (int i = 2; i < s.count; i++) {
                s.g79b0 = o.X(i);
                s.g7a30 = s.g79b0;
                s.g79b8 = o.Y(i);
                s.g7a38 = s.g79b8;
                s.g79d0 = rAbs(s.g79d0);
                s.g79d8 = rAbs(s.g79d8);
                lyDeriv(s, derivative);
                s.g79e0 = rAbs(s.g79d0) + TINY;
                s.g79e8 = rAbs(s.g79d8) + TINY;
                if (rAbs(s.g79e0) < minA) minA = s.g79e0;
                if (rAbs(s.g79e8) < minB) minB = s.g79e8;
            }
        }
        s.outA = rAbs(rLog(rAbs(TINY + minA)) / s.count);
        s.outB = rAbs(rLog(rAbs(TINY + minB)) / s.count);
        break;
    }
    default:
        break;
    }
}
