package main

Vertex_Format :: enum {
    Float,
    Float2,
    Float3,
    Float4,
    UInt,
    UInt2,
    UInt3,
    UInt4,
}

Vertex_Attribute :: struct {
    format: Vertex_Format,
    offset: int,
    binding: int, 
}

Vertex_Layout :: struct {
    stride: int,
    step_rate: Vertex_Step_Rate,
}

Vertex_Step_Rate :: enum {
    PerVertex,
    PerInstance,
}

Blend_Factor :: enum {
    Zero,
    One,
    SrcColor,
    OneMinusSrcColor,
    SrcAlpha,
    OneMinusSrcAlpha,
    DstColor,
    OneMinusDstColor,
    DstAlpha,
    OneMinusDstAlpha,
}

Blend_Op :: enum {
    Add,
    Subtract,
    ReverseSubtract,
    Min,
    Max,
}

Blend_State :: struct {
    enabled: bool,
    src_color: Blend_Factor,
    dst_color: Blend_Factor,
    color_op: Blend_Op,
    src_alpha: Blend_Factor,
    dst_alpha: Blend_Factor,
    alpha_op: Blend_Op,
}

Depth_State :: struct {
    test_enabled: bool,
    write_enabled: bool,
    compare_op: Compare_Op,
}

Compare_Op :: enum {
    Never,
    Less,
    Equal,
    LessOrEqual,
    Greater,
    NotEqual,
    GreaterOrEqual,
    Always,
}

Cull_Mode :: enum {
    None,
    Front,
    Back,
}

Winding_Order :: enum {
    Clockwise,
    CounterClockwise,
}

Primitive_Topology :: enum {
    PointList,
    LineList,
    LineStrip,
    TriangleList,
    TriangleStrip,
}

Pixel_Format :: enum {
    RGBA8_UNorm,
    RGBA8_UNorm_sRGB,
    BGRA8_UNorm,
    BGRA8_UNorm_sRGB,
    RGBA16_Float,
    RGBA32_Float,
    Depth32_Float,
    Depth24_Stencil8,
}

Shader_Stage :: enum {
    Vertex,
    Fragment,
    Compute,
}

Pipeline_Desc :: struct {
    // Shaders
    vertex_shader: Shader,
    fragment_shader: Shader,
    
    // Vertex input
    vertex_attributes: []Vertex_Attribute,
    vertex_layouts: []Vertex_Layout,
    
    // Rasterization
    primitive_topology: Primitive_Topology,
    cull_mode: Cull_Mode,
    front_face: Winding_Order,
    
    // Depth/Stencil
    depth_state: Depth_State,
    
    // Color attachments
    //color_formats: []Pixel_Format,
    blend_states: []Blend_State,  // One per color attachment
    
    // Optional
    depth_format: Pixel_Format,
    sample_count: int,  // MSAA
    
    // Debug
    label: string,
}

Pipeline :: struct {
    handle: rawptr,  // Backend-specific pipeline
    desc: Pipeline_Desc,  // Keep for debugging
}

// Create pipeline
create_pipeline :: proc(desc: Pipeline_Desc) -> Pipeline {
    when RENDERER == .Metal {
        return metal_create_pipeline(desc)
    } else when RENDERER == .Vulkan {
        return vulkan_create_pipeline(desc)
    } else when RENDERER == .D3D12 {
        return d3d12_create_pipeline(desc)
    }
}

destroy_pipeline :: proc(pipeline: ^Pipeline) {
    when RENDERER == .Metal {
        metal_destroy_pipeline(pipeline)
    } else when RENDERER == .Vulkan {
        vulkan_destroy_pipeline(pipeline)
    } else when RENDERER == .D3D12 {
        d3d12_destroy_pipeline(pipeline)
    }
}
