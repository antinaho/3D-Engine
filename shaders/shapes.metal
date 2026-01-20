#include <metal_stdlib>
using namespace metal;

struct Shape_Uniforms {
    float4x4 view_projection;
};

struct Shape_Vertex {
    float2 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};

struct Shape_Instance {
    float2 position [[attribute(2)]];
    float2 scale    [[attribute(3)]];
    float4 params   [[attribute(4)]];
    float  rotation [[attribute(5)]];
    uint   kind     [[attribute(6)]];
    uchar4 color    [[attribute(7)]];
};

struct Shape_Out {
    float4 position [[position]];
    float2 uv;
    float4 color;
    uint kind;
    float4 params;
};

constant uint SHAPE_RECT   = 0;
constant uint SHAPE_CIRCLE = 1;

vertex Shape_Out shape_vertex(
    Shape_Vertex          vert     [[stage_in]],
    constant Shape_Instance* instances [[buffer(1)]],
    uint                     instID    [[instance_id]],
    constant Shape_Uniforms& uniforms [[buffer(0)]]
) {
    Shape_Instance inst = instances[instID];
    Shape_Out out;

    // Apply rotation
    float c = cos(inst.rotation);
    float s = sin(inst.rotation);
    float2 rotated = float2(
        vert.position.x * c - vert.position.y * s,
        vert.position.x * s + vert.position.y * c
    );

    // Apply scale and translation
    float2 world_pos = rotated * inst.scale + inst.position;

    out.position = uniforms.view_projection * float4(world_pos, 0.0, 1.0);
    out.uv       = vert.uv;
    out.color    = float4(inst.color) / 255.0;
    out.kind     = inst.kind;
    out.params   = inst.params;

    return out;
}

fragment float4 shape_fragment(
    Shape_Out            in             [[stage_in]],
    texture2d<float>     colorTexture   [[texture(0)]],
    sampler              textureSampler [[sampler(0)]]
) {
    float4 color = in.color;

    if (in.kind == SHAPE_CIRCLE) {
        // SDF circle: uv is [0,1], center at 0.5
        float2 centered = in.uv - 0.5;
        float dist = length(centered);
        float radius = 0.5;
        
        // Anti-aliased edge
        float aa = fwidth(dist);
        float alpha = 1.0 - smoothstep(radius - aa, radius, dist);
        
        color.a *= alpha;
    }
    // SHAPE_RECT: no modification needed, quad is already a rectangle

    // Sample texture and multiply
    float4 texColor = colorTexture.sample(textureSampler, in.uv);
    return texColor * color;
}
