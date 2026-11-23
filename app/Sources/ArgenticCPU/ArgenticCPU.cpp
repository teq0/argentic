#include "ArgenticCPU.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace {
using namespace std;
using uint = unsigned int;
template <typename T> struct Vec2 {
    T x{}, y{};
    Vec2() = default;
    Vec2(T a, T b): x(a), y(b) {}
};
template <typename T> struct Vec3 {
    T x{}, y{}, z{};
    Vec3() = default;
    explicit Vec3(T a): x(a), y(a), z(a) {}
    Vec3(T a, T b, T c): x(a), y(b), z(c) {}
    Vec3 &operator&=(int mask) { x &= mask; y &= mask; z &= mask; return *this; }
    Vec3 &operator+=(Vec3 v) { x += v.x; y += v.y; z += v.z; return *this; }
    Vec3 operator/(int d) const { return Vec3(x / d, y / d, z / d); }
};
struct float4 { double x{}, y{}, z{}, w{}; };
using float2 = Vec2<double>;
using float3 = Vec3<double>;
using int3 = Vec3<int>;
using uint2 = Vec2<uint>;

struct Cancelled {};
thread_local ArgenticCPUCancel cancellation = nullptr;
thread_local void *cancellationContext = nullptr;
thread_local unsigned int pollCount = 0;
void pollCancellation() {
    if ((++pollCount & 255) == 0 && cancellation && cancellation(cancellationContext)) throw Cancelled{};
}

#include "Algorithms.hpp"
}

struct ArgenticCPUImage {
    int width, height, sampling, fieldWidth;
    vector<float2> field;
    vector<uint32_t> pixels;
    ArgenticCPUImage(int w, int h, int k): width(w), height(h), sampling(k), fieldWidth(w * k),
        field(size_t(w) * h * k * k), pixels(size_t(w) * h, 0xff000000) {}
};

ArgenticCPUImage *ArgenticCPUCreate(int width, int height, int sampling) {
    if (width < 1 || height < 1 || width > 8192 || height > 8192 || sampling < 1 || sampling > 4) return nullptr;
    try { return new ArgenticCPUImage(width, height, sampling); }
    catch (...) { return nullptr; }
}

void ArgenticCPUDestroy(ArgenticCPUImage *image) { delete image; }

bool ArgenticCPUComputeRow(ArgenticCPUImage *image, int row, ArgenticCPUFieldParams p,
                          ArgenticCPUCancel cancel, void *context) {
    cancellation = cancel;
    cancellationContext = context;
    pollCount = 0;
    kFormula = p.formula;
    kRender = p.render;
    kTransform = p.transform;
    kUseOrbit = kFormula >= 100 || kRender == 3 || kRender >= 6;
    try {
        vector<float2> orbit(kUseOrbit ? size_t(p.maxIterations) + 2 : 0);
        FieldParams params{p.xMin, p.yMin, p.dx, p.dy, image->fieldWidth, row, 1, p.maxIterations,
            p.juliaX, p.juliaY, p.trapRadius, p.juliaMode, p.insideOut, p.scale,
            p.mapping, p.derivative, p.coordinateFlag, 1};
        for (int x = 0; x < image->fieldWidth; ++x) {
            if (cancel && cancel(context)) throw Cancelled{};
            fieldKernel(params, image->field.data(), orbit.data(), uint2(x, 0));
        }
        cancellation = nullptr;
        cancellationContext = nullptr;
        return true;
    } catch (...) {
        cancellation = nullptr;
        cancellationContext = nullptr;
        return false;
    }
}

void ArgenticCPUColorizeRow(ArgenticCPUImage *image, int row, ArgenticCPUColorParams p) {
    // Metal's slot() converts its R/B/G storage back into the public R/G/B control order.
    auto slots = [](const double *v) { return float4{v[0], v[2], v[1], 0}; };
    ColorParams params{slots(p.step), slots(p.start), slots(p.saturation), slots(p.offset),
        p.renderScale, p.xMin, p.yMin, p.dx, p.dy, p.blend, p.rgbOrder,
        image->sampling, image->fieldWidth, image->width, row, 1};
    for (int x = 0; x < image->width; ++x)
        colorKernel(params, image->field.data(), image->pixels.data(), uint2(x, 0));
}

const uint8_t *ArgenticCPUPixels(const ArgenticCPUImage *image) {
    return reinterpret_cast<const uint8_t *>(image->pixels.data());
}

void ArgenticCPUFieldValue(const ArgenticCPUImage *image, int x, int y, double *a, double *b) {
    auto value = image->field[size_t(y) * image->fieldWidth + x];
    *a = value.x;
    *b = value.y;
}

void ArgenticCPUSetFieldValue(ArgenticCPUImage *image, int index, double a, double b) {
    image->field[index] = float2(a, b);
}
