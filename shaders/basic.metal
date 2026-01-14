#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 view_projection;
};

struct Sprite_Vertex {
    float3 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
    uchar4 color    [[attribute(2)]];
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex VSOut basic_vertex(Sprite_Vertex in [[stage_in]],
                          constant Uniforms& uniforms [[buffer(1)]])
{
    VSOut out;
    out.position = uniforms.view_projection * float4(in.position, 1.0);
    out.uv = 1.0 - in.uv;
    out.color = float4(in.color) / 255.0;
    return out;
}

fragment float4 basic_fragment(VSOut in [[stage_in]],
                               texture2d<float> colorTexture [[texture(0)]],
                               sampler textureSampler [[sampler(0)]])
{
    float4 colorSample = colorTexture.sample(textureSampler, in.uv);
    return colorSample * in.color;
}