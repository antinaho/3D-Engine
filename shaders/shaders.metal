using namespace metal;

struct Uniforms {
    float4x4 perspective;
    float4x4 view;
    float4x4 model;
    float time;
    float delta;
};


struct VertexIn {
    float4 position;
    float4 color;
    float2 textureCoordinate;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 textureCoordinate;
};

vertex VertexOut vertex_main(
    const device VertexIn* vertices [[buffer(0)]],
    constant Uniforms& uniforms     [[buffer(1)]],
    uint vid                        [[vertex_id]]
) {
    
    VertexOut vert;
    vert.position          = uniforms.perspective 
                                * uniforms.view 
                                * uniforms.model 
                                * vertices[vid].position;
    vert.color             = vertices[vid].color;

    float scroll_speed = 0.1;
    float offset = uniforms.time * scroll_speed;
    
    vert.textureCoordinate = 1.0 - vertices[vid].textureCoordinate;
    vert.textureCoordinate += offset;

    return vert;
}

fragment float4 fragment_main(
    VertexOut           vert            [[stage_in]],
    texture2d<float>    colorTexture    [[texture(0)]],
    constant Uniforms&  uniforms        [[buffer(0)]],
    sampler    textureSampler  [[sampler(0)]] 
) {
    const float4 colorSample = colorTexture.sample(textureSampler, vert.textureCoordinate);
    
    float pulse = abs(sin(uniforms.time));
    
    return vert.color * colorSample * pulse;
}
