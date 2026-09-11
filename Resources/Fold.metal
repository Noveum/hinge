#include <metal_stdlib>
using namespace metal;

struct FoldParameters {
    float progress;
    float opacity;
    float blurInset;
    float blurSpan;
};

struct FoldVertex {
    float4 position [[position]];
    float2 uv;
};

vertex FoldVertex foldVertex(uint id [[vertex_id]], constant FoldParameters &p [[buffer(0)]]) {
    constexpr float2 coordinates[] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    float2 uv = coordinates[id];
    FoldVertex out;
    out.position = float4(uv.x * 2.0 - 1.0, 1.0 - 2.0 * uv.y, 0.0, 1.0);
    out.uv = uv;
    return out;
}

fragment float4 foldFragment(FoldVertex in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> soft [[texture(1)]],
    texture2d<float> medium [[texture(2)]],
    texture2d<float> broad [[texture(3)]],
    texture2d<float> sides [[texture(4)]],
    constant FoldParameters &p [[buffer(0)]]) {
    constexpr sampler sampleMode(coord::normalized, address::clamp_to_edge, filter::linear);
    float q = (1.0 + 0.30 * p.progress) / (1.0 + 0.30 * p.progress * in.uv.y);
    float2 uv = float2((in.uv.x - 0.5) * q + 0.5, in.uv.y * q);
    float edge = min(uv.x, 1.0 - uv.x);
    float2 blurUV = float2(p.blurInset + uv.x * p.blurSpan, uv.y);
    float feather = smoothstep(0.0, max(0.0001, p.progress * 0.012 * (1.0 - uv.y)), edge);
    float3 sharp = mix(sides.sample(sampleMode, blurUV).rgb, source.sample(sampleMode, uv).rgb, feather);
    float amount = 36.0 * p.progress * (1.0 - smoothstep(0.0, 0.9, uv.y));
    float3 color;
    if (amount < 6.0) {
        color = mix(sharp, soft.sample(sampleMode, blurUV).rgb, amount / 6.0);
    } else if (amount < 16.0) {
        color = mix(soft.sample(sampleMode, blurUV).rgb, medium.sample(sampleMode, blurUV).rgb, (amount - 6.0) / 10.0);
    } else {
        color = mix(medium.sample(sampleMode, blurUV).rgb, broad.sample(sampleMode, blurUV).rgb, (amount - 16.0) / 20.0);
    }
    float upper = 1.0 - smoothstep(0.0, 0.85, uv.y);
    float corners = (1.0 - smoothstep(0.0, 0.19, edge)) * upper;
    color *= 1.0 - p.progress * (0.50 * corners + 0.10 * upper);
    return float4(color * p.opacity, p.opacity);
}
