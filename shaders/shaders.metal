using namespace metal;

struct Uniforms {
    float4x4 projection; 
    float4x4 view;
    float4x4 model;
    float4 lightPosition;
    float4 lightDirection;
    float4 time_data;
};

struct DirectionalLight {
    float3 direction;
    float3 color;
    float intensity;
};

struct PointLight {
    float3 position;
    float3 color;
    float intensity;
    float constant_;
    float linear;
    float quadratic;
    float radius;
    
    float pad_;
    float pad1_;
    float pad2_;
};

struct LightingData { 
    PointLight point_lights[16];
    DirectionalLight direction_light;


    float3 camera_position;
    
    float3 ambient_color;
    
    float ambient_intensity;
};

struct VertexIn {
    float4 position;
    float4 color;
    float2 textureCoordinate;
    float3 normal;
};

struct VertexOut {
    float4 position [[position]];
    float4 world_position;
    float4 color;
    float3 normal;
    float2 textureCoordinate;
};



// Blinn-Phong directional light
float3 calculate_directional_light(
    DirectionalLight light,
    float3 normal,
    float3 view_dir,
    float3 surface_color
)
{
    float3 light_dir = normalize(-light.direction);
    
    // Diffuse
    float diff = max(dot(normal, light_dir), 0.0);
    float3 diffuse = diff * light.color * light.intensity;
    
    // Specular (Blinn-Phong)
    float3 halfway_dir = normalize(light_dir + view_dir);
    float spec = pow(max(dot(normal, halfway_dir), 0.0), 32.0);  // 32 = shininess
    float3 specular = spec * light.color * light.intensity * 0.5;  // 0.5 = specular strength
    
    return (diffuse + specular) * surface_color;
}

// Point light with attenuation
float3 calculate_point_light(
    PointLight light,
    float3 normal,
    float3 frag_pos,
    float3 view_dir,
    float3 surface_color
)
{

    float3 light_dir = light.position - frag_pos;
    float distance = length(light_dir);

    // Early exit if beyond radius
    if (distance > light.radius) {
        return float3(0.0);
    }
    
    light_dir = normalize(light_dir);
    
    // Attenuation
    float attenuation = 1.0 / (light.constant_ + 
                               light.linear * distance + 
                               light.quadratic * distance * distance);
    

    // Diffuse
    float diff = max(dot(normal, light_dir), 0.0);
    float3 diffuse = diff * light.color * light.intensity;
    
    // Specular
    float3 halfway_dir = normalize(light_dir + view_dir);
    float spec = pow(max(dot(normal, halfway_dir), 0.0), 32.0);
    float3 specular = spec * light.color * light.intensity * 0.5;
    
    return (diffuse + specular) * surface_color * attenuation;
}

vertex VertexOut vertex_main(
    const device VertexIn* vertices [[buffer(0)]],
    constant Uniforms& uniforms     [[buffer(1)]],
    uint vid                        [[vertex_id]]
) {
    
    VertexOut out;
    VertexIn in = vertices[vid];

    float3 light_pos = uniforms.lightPosition.xyz;
    float3 light_dir = uniforms.lightDirection.xyz;
    float rtime = uniforms.time_data.x;
    float delta = uniforms.time_data.y;

    out.color = in.color;
    float scroll_speed = 0.1;
    float offset = rtime * scroll_speed;
    
    out.textureCoordinate = 1.0 - in.textureCoordinate;
    out.textureCoordinate += offset;

    float4 world_pos = uniforms.model * in.position;
    out.world_position = world_pos;
    
    float4 view_pos = uniforms.view * world_pos;
    out.position = uniforms.projection * view_pos;
    
    float3x3 normal_matrix = float3x3(
        uniforms.model[0].xyz,
        uniforms.model[1].xyz,
        uniforms.model[2].xyz
    );
    out.normal = normalize(normal_matrix * in.normal);

    return out;
}

fragment float4 fragment_main(
    VertexOut               vert            [[stage_in]],
    texture2d<float>        colorTexture    [[texture(0)]],
    sampler                 textureSampler  [[sampler(0)]],
    constant Uniforms&      uniforms        [[buffer(0)]],
    constant LightingData&  lighting        [[buffer(1)]] 
) {
    const float4 tex_color = colorTexture.sample(textureSampler, vert.textureCoordinate);
    
    float3 frag_pos = vert.world_position.xyz;
    float3 normal = normalize(vert.normal);
    float3 view_dir = normalize(lighting.camera_position - frag_pos);

    // Debug: Show normals
    //return float4(normal * 0.5 + 0.5, 1.0);  // Should show colorful cube
    
    // Debug: Show texture
    //return tex_color;  // Should show your texture
    
    // Debug: Show ambient only
    //return float4(lighting.ambient_color * lighting.direction_light.intensity, 1.0);

    float3 result = lighting.ambient_color * lighting.ambient_intensity * tex_color.rgb;

    //num directional
    DirectionalLight light = lighting.direction_light;
    result += calculate_directional_light(light, normal, view_dir, tex_color.rgb);

    // // num point
    for (uint i = 0; i < 16; i++) {
        PointLight point_light = lighting.point_lights[i];
        result += calculate_point_light(point_light, normal, frag_pos, view_dir, tex_color.rgb);
    }
    
    return float4(result, tex_color.a);
}



