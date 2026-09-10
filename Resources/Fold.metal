#include <metal_stdlib>
using namespace metal;

struct FoldParameters {
    float progress;
    float perspective;
    float blur;
    float shadow;
    float width;
    float height;
    float frost;
    float padding;
};

struct FoldVertex {
    float4 position [[position]];
    float2 uv;
};

vertex FoldVertex foldVertex(uint id [[vertex_id]], constant FoldParameters &p [[buffer(0)]]) {
    constexpr float2 coordinates[] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    float2 uv = coordinates[id];
    float angle = p.progress * p.perspective * 1.2566370614;
    float k = sin(angle) / max(p.width * 1400.0 / 786.0, 1.0);
    float q = 1.0 + p.height * k * (1.0 - uv.y);
    float y = 1.0 + p.height * k - cos(angle) + uv.y * (cos(angle) - p.height * k);
    FoldVertex out;
    out.position = float4(uv.x * 2.0 - 1.0, q - 2.0 * y, 0.0, q);
    out.uv = uv;
    return out;
}

float3 softSample(texture2d<float> source, sampler sampleMode, float2 uv, float2 radius) {
    float3 color = source.sample(sampleMode, uv).rgb * 0.20;
    constexpr float2 offsets[] = {
        float2(1, 0), float2(-1, 0), float2(0, 1), float2(0, -1),
        float2(0.707, 0.707), float2(-0.707, 0.707), float2(0.707, -0.707), float2(-0.707, -0.707),
        float2(1.7, 0.6), float2(-1.7, -0.6), float2(0.6, -1.7), float2(-0.6, 1.7)
    };
    for (uint i = 0; i < 12; i++) {
        color += source.sample(sampleMode, uv + offsets[i] * radius).rgb * (i < 8 ? 0.075 : 0.05);
    }
    return color;
}

fragment float4 foldFragment(FoldVertex in [[stage_in]], texture2d<float> source [[texture(0)]], constant FoldParameters &p [[buffer(0)]]) {
    constexpr sampler sampleMode(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;
    float3 color = source.sample(sampleMode, uv).rgb;
    float unit = p.width / 786.0;
    float blurAmount = p.blur / 0.65;
    float2 pixel = 1.0 / float2(p.width, p.height);
    float first = 1.0 - smoothstep(0.30, 0.75, uv.y);
    float second = 1.0 - smoothstep(0.15, 0.52, uv.y);
    float third = 1.0 - smoothstep(0.06, 0.34, uv.y);
    if (p.progress * blurAmount > 0.001) {
        color = mix(color, softSample(source, sampleMode, uv, pixel * 6.0 * unit * blurAmount), first * p.progress);
        color = mix(color, softSample(source, sampleMode, uv, pixel * 16.0 * unit * blurAmount), second * p.progress);
        color = mix(color, softSample(source, sampleMode, uv, pixel * 36.0 * unit * blurAmount), third * p.progress);
    }
    float topShade = 0.35 * (1.0 - smoothstep(0.0, 0.45, uv.y));
    float leftShade = 0.55 * (1.0 - smoothstep(0.0, 0.65, length(uv * float2(0.8, 1.65))));
    float rightShade = 0.55 * (1.0 - smoothstep(0.0, 0.65, length(float2(1.0 - uv.x, uv.y) * float2(0.8, 1.65))));
    color *= 1.0 - clamp((topShade + leftShade + rightShade) * p.shadow * p.progress, 0.0, 0.92);
    color = mix(color, float3(0.85, 0.91, 1.0), p.frost * p.progress * third * 0.035);
    float feather = mix(1.0, smoothstep(0.0, max(p.progress * 0.22, 0.0001), uv.y), p.progress);
    float edgeDistance = min(uv.x, 1.0 - uv.x);
    float sideFeather = smoothstep(0.0, max(0.0005, p.progress * 0.008 * (1.0 - uv.y)), edgeDistance);
    return float4(color * feather * sideFeather, 1.0);
}
