#pragma once
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ArgenticCPUImage ArgenticCPUImage;
typedef bool (*ArgenticCPUCancel)(void *context);

typedef struct {
    double xMin, yMin, dx, dy, juliaX, juliaY, trapRadius, scale;
    int formula, render, transform, maxIterations, juliaMode, insideOut;
    int mapping, derivative, coordinateFlag;
} ArgenticCPUFieldParams;

typedef struct {
    double step[3], start[3], saturation[3], offset[3];
    double renderScale, xMin, yMin, dx, dy;
    int blend, rgbOrder;
} ArgenticCPUColorParams;

ArgenticCPUImage *ArgenticCPUCreate(int width, int height, int sampling);
void ArgenticCPUDestroy(ArgenticCPUImage *image);
bool ArgenticCPUComputeRow(ArgenticCPUImage *image, int row, ArgenticCPUFieldParams params,
                          ArgenticCPUCancel cancel, void *context);
void ArgenticCPUColorizeRow(ArgenticCPUImage *image, int row, ArgenticCPUColorParams params);
const uint8_t *ArgenticCPUPixels(const ArgenticCPUImage *image);
void ArgenticCPUFieldValue(const ArgenticCPUImage *image, int x, int y, double *a, double *b);
void ArgenticCPUSetFieldValue(ArgenticCPUImage *image, int index, double a, double b);

#ifdef __cplusplus
}
#endif
