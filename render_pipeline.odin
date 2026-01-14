package main

LoadAction :: enum {
    Load,
    Clear,
    DontCare,
}

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
    blend_states: []BlendState,
    
    // Optional
    depth_format: PixelFormat,
    sample_count: int,
    
    // Debug
    label: string,
}

Pipeline :: struct {
    handle: rawptr,
    desc: PipelineDesc,
}