#include <metal_stdlib>
using namespace metal;

struct FoldParameters {
    float progress;
};

struct FoldVertex {
    float4 position [[position]];
    float2 uv;
};

vertex FoldVertex foldVertex(uint id [[vertex_id]], constant FoldParameters &p [[buffer(0)]]) {
    constexpr float2 coordinates[] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    float2 uv = coordinates[id];
    float q = 1.0 + 0.30 * p.progress * (1.0 - uv.y);
    FoldVertex out;
    out.position = float4(uv.x * 2.0 - 1.0, (1.0 - 2.0 * uv.y) * q, 0.0, q);
    out.uv = uv;
    return out;
}

fragment float4 foldFragment(FoldVertex in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> soft [[texture(1)]],
    texture2d<float> medium [[texture(2)]],
    texture2d<float> broad [[texture(3)]],
    constant FoldParameters &p [[buffer(0)]]) {
    constexpr sampler sampleMode(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;
    float amount = 36.0 * p.progress * (1.0 - smoothstep(0.0, 0.9, uv.y));
    float3 color;
    if (amount < 6.0) {
        color = mix(source.sample(sampleMode, uv).rgb, soft.sample(sampleMode, uv).rgb, amount / 6.0);
    } else if (amount < 16.0) {
        color = mix(soft.sample(sampleMode, uv).rgb, medium.sample(sampleMode, uv).rgb, (amount - 6.0) / 10.0);
    } else {
        color = mix(medium.sample(sampleMode, uv).rgb, broad.sample(sampleMode, uv).rgb, (amount - 16.0) / 20.0);
    }
    float edge = min(uv.x, 1.0 - uv.x);
    float upper = 1.0 - smoothstep(0.0, 0.85, uv.y);
    float corners = (1.0 - smoothstep(0.0, 0.19, edge)) * upper;
    color *= 1.0 - p.progress * (0.50 * corners + 0.10 * upper);
    float feather = smoothstep(0.0, max(0.0001, p.progress * 0.012 * (1.0 - uv.y)), edge);
    return float4(color * feather, 1.0);
}
