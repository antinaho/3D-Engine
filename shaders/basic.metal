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

float2 uv_klems( float2 uv, int2 texture_size ) {
    float2 texSize = float2(texture_size);
    float2 pixels = uv * texSize + 0.5;
    
    // tweak fractional value of the texture coordinate
    float2 fl = floor(pixels);
    float2 fr = fract(pixels);
    float2 aa = fwidth(pixels) * 0.75;

    fr = smoothstep( float2(0.5) - aa, float2(0.5) + aa, fr);
    
    return (fl + fr - 0.5) / texSize;
}

vertex VSOut basic_vertex(Sprite_Vertex in [[stage_in]],
                          constant Uniforms& uniforms [[buffer(1)]]
                          )
{
    VSOut out;
    out.position = uniforms.view_projection * float4(in.position, 1.0);
    out.uv   = in.uv;
    out.uv.y = 1.0 - out.uv.y;
    out.color = float4(in.color) / 255.0;
    return out;
}

fragment float4 basic_fragment(VSOut in [[stage_in]],
                               texture2d<float> colorTexture [[texture(0)]],
                               sampler textureSampler [[sampler(0)]])
{
    float4 colorSample = colorTexture.sample(textureSampler, uv_klems(in.uv, int2(colorTexture.get_width(), colorTexture.get_height())));
    return colorSample * in.color;
}