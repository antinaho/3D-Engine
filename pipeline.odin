package main

VertexFormat :: enum {
    Float,
    Float2,
    Float3,
    Float4,
    UInt,
    UInt2,
    UInt3,
    UInt4,
}

VertexAttribute :: struct {
    format: VertexFormat,
    offset: uintptr,
    binding: int, 
}

VertexLayout :: struct {
    stride: int,
    step_rate: VertexStepRate,
}

VertexStepRate :: enum {
    PerVertex,
    PerInstance,
}

BlendFactor :: enum {
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

BlendOperation :: enum {
    Add,
    Subtract,
    ReverseSubtract,
    Min,
    Max,
}

BlendState :: struct {
    enabled: bool,
    src_color: BlendFactor,
    dst_color: BlendFactor,
    color_op: BlendOperation,
    src_alpha: BlendFactor,
    dst_alpha: BlendFactor,
    alpha_op: BlendOperation,
}

DepthState :: struct {
    test_enabled: bool,
    write_enabled: bool,
    compare_op: CompareOperation,
}

CompareOperation :: enum {
    Never,
    Less,
    Equal,
    LessOrEqual,
    Greater,
    NotEqual,
    GreaterOrEqual,
    Always,
}

CullMode :: enum {
    None,
    Front,
    Back,
}

WindingOrder :: enum {
    Clockwise,
    CounterClockwise,
}

PrimitiveTopology :: enum {
    PointList,
    LineList,
    LineStrip,
    TriangleList,
    TriangleStrip,
}

PixelFormat :: enum {
    RGBA8_UNorm,
    RGBA8_UNorm_sRGB,
    BGRA8_UNorm,
    BGRA8_UNorm_sRGB,
    RGBA16_Float,
    RGBA32_Float,
    Depth32_Float,
    Depth24_Stencil8,
}

ShaderStage :: enum {
    Vertex,
    Fragment,
    Compute,
}

PipelineDesc :: struct {
    // Shaders
    vertex_shader: Shader,
    fragment_shader: Shader,
    
    // Vertex input
    vertex_attributes: []VertexAttribute,
    vertex_layouts: []VertexLayout,
    
    // Rasterization
    primitive_topology: PrimitiveTopology,
    cull_mode: CullMode,
    front_face: WindingOrder,
    
    // Depth/Stencil
    depth_state: DepthState,
    
    // Color attachments
    color_formats: []PixelFormat,
    blend_states: []BlendState,  // One per color attachment
    
    // Optional
    depth_format: PixelFormat,
    sample_count: int,  // MSAA
    
    // Debug
    label: string,
}

Pipeline :: struct {
    handle: rawptr,  // Backend-specific pipeline
    desc: PipelineDesc,  // Keep for debugging
}

// Create pipeline
create_pipeline :: proc(desc: PipelineDesc) -> Pipeline {
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
