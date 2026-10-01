#include <metal_stdlib>

using namespace metal;

struct HeatmapEnvelope {
    float4 geometry;
};

struct HeatmapParameters {
    float4 domainAndRSSI;
    uint4 raster;
    float4 field;
};

inline float heatmapSmoothstep(float value) {
    float clamped = clamp(value, 0.0f, 1.0f);
    return clamped * clamped * (3.0f - 2.0f * clamped);
}

inline float gaussianValue(float x, float4 geometry) {
    float leftX = geometry.x;
    float rightX = geometry.y;
    float peakRSSI = geometry.z;
    float baselineRSSI = geometry.w;
    float amplitude = max(0.0f, peakRSSI - baselineRSSI);
    if (amplitude <= 0.0f) {
        return baselineRSSI;
    }

    float center = (leftX + rightX) * 0.5f;
    float halfWidth = max(0.0f, rightX - leftX) * 0.5f;
    float sigma = halfWidth * 0.25f;
    if (sigma <= 0.0f) {
        return baselineRSSI;
    }

    float normalizedDistance = (x - center) / sigma;
    return baselineRSSI + amplitude * exp(-0.5f * normalizedDistance * normalizedDistance);
}

kernel void heatmapFieldKernel(
    device const HeatmapEnvelope *envelopes [[buffer(0)]],
    device float *output [[buffer(1)]],
    constant HeatmapParameters &parameters [[buffer(2)]],
    uint2 position [[thread_position_in_grid]]) {
    uint width = parameters.raster.x;
    uint height = parameters.raster.y;
    if (position.x >= width || position.y >= height) {
        return;
    }

    float minX = parameters.domainAndRSSI.x;
    float maxX = parameters.domainAndRSSI.y;
    float rssiMin = parameters.domainAndRSSI.z;
    float rssiMax = parameters.domainAndRSSI.w;
    float span = maxX - minX;
    float rssiSpan = rssiMax - rssiMin;
    uint index = position.y * width + position.x;

    if (span <= 0.0f || rssiSpan <= 0.0f) {
        output[index] = 0.0f;
        return;
    }

    float x = minX + ((float(position.x) + 0.5f) / float(width)) * span;
    float rssi = rssiMin + ((float(height) - (float(position.y) + 0.5f)) / float(height)) * rssiSpan;
    float density = 0.0f;
    uint envelopeCount = parameters.raster.z;
    float decayTau = parameters.field.x;
    float bodyFloor = parameters.field.y;
    float edgeFade = parameters.field.z;

    for (uint envelopeIndex = 0; envelopeIndex < envelopeCount; ++envelopeIndex) {
        float4 geometry = envelopes[envelopeIndex].geometry;
        if (x < geometry.x || x > geometry.y) {
            continue;
        }

        float curve = gaussianValue(x, geometry);
        float amplitude = max(0.0f, geometry.z - geometry.w);
        if (amplitude <= 0.0f) {
            continue;
        }

        float horizontalSupport = clamp((curve - geometry.w) / amplitude, 0.0f, 1.0f);
        if (horizontalSupport <= 0.0f) {
            continue;
        }

        float depth = curve - rssi;
        if (depth >= 0.0f) {
            float decay = exp(-depth / decayTau);
            float profile = bodyFloor + (1.0f - bodyFloor) * decay;
            density += horizontalSupport * profile;
        } else if (depth >= -edgeFade) {
            float edge = (depth + edgeFade) / edgeFade;
            density += horizontalSupport * heatmapSmoothstep(edge);
        }
    }

    float normalized = sqrt(clamp(density / parameters.field.w, 0.0f, 1.0f));
    output[index] = clamp(normalized, 0.0f, 1.0f);
}

kernel void heatmapSmoothKernel(
    device const float *input [[buffer(0)]],
    device float *output [[buffer(1)]],
    constant HeatmapParameters &parameters [[buffer(2)]],
    uint2 position [[thread_position_in_grid]]) {
    uint width = parameters.raster.x;
    uint height = parameters.raster.y;
    if (position.x >= width || position.y >= height) {
        return;
    }

    float sum = 0.0f;
    float count = 0.0f;
    int centerX = int(position.x);
    int centerY = int(position.y);
    for (int sampleY = max(0, centerY - 1); sampleY <= min(int(height) - 1, centerY + 1); ++sampleY) {
        for (int sampleX = max(0, centerX - 2); sampleX <= min(int(width) - 1, centerX + 2); ++sampleX) {
            sum += input[uint(sampleY) * width + uint(sampleX)];
            count += 1.0f;
        }
    }

    output[position.y * width + position.x] = clamp(sum / max(count, 1.0f), 0.0f, 1.0f);
}
