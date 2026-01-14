#include <metal_stdlib>
using namespace metal;

struct Font_Vertex {
    float2 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
    uchar4 color    [[attribute(2)]];
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex VSOut font_vertex(Font_Vertex in [[stage_in]])
{
    VSOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    out.color = float4(in.color) / 255.0;
    return out;
}

fragment float4 font_fragment(VSOut in [[stage_in]],
                              texture2d<float> fontTexture [[texture(0)]],
                              sampler textureSampler [[sampler(0)]])
{
    float4 texSample = fontTexture.sample(textureSampler, in.uv);
    
    // For white-on-black font textures: use luminance of RGB as alpha
    // White pixels (1,1,1) -> keep, Black pixels (0,0,0) -> discard
    float luminance = max(max(texSample.r, texSample.g), texSample.b);
    
    // Discard black pixels
    if (luminance < 0.1) {
        discard_fragment();
    }
    
    // Use luminance as alpha, tinted by vertex color
    return float4(in.color.rgb, in.color.a * luminance);
}
