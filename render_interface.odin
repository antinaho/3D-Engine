package main

RendererType :: enum {
    Metal = 1
}

when ODIN_OS == .Darwin {
    RENDERER_KIND :: RendererType.Metal
} else {
    RENDERER_KIND :: 0
}

Renderer :: struct {
    using api: RendererAPI,
    platform: _Platform,


    msaa_texture: Texture,
    depth_texture: Texture,
}

RendererAPI :: struct {
    draw: proc(application_window: ^ApplicationWindow, command_buffer: ^CommandBuffer),
    cleanup: proc(application_window: ^ApplicationWindow),
}

DefaultRenderer :: struct {
    pipeline: Pipeline,

    default_sampler: TextureSampler,
    custom_texture: Texture,
}

Color :: [4]u8
Material :: struct {
    albedo_tex: Texture,
    albedo_color: Color,

    texture_scale: [2]f32,
    texture_offset: [2]f32,
}

DEFAULT_MSAA_SAMPLE_COUNT :: 4
create_opaque_pipeline :: proc() -> Pipeline {

    vertex_shader, v_ok := load_shader("shaders/shaders.metal", .Vertex, "vertex_m")
    fragment_shader, f_ok := load_shader("shaders/shaders.metal", .Fragment, "fragment_m")
    
    attributes := []VertexAttribute {
        {format = .Float3, offset=offset_of(Vertex, position),  binding = 0},
        {format = .Float3, offset=offset_of(Vertex, normal), binding = 0},
        {format = .Float4, offset=offset_of(Vertex, color), binding = 0},
        {format = .Float2, offset=offset_of(Vertex, uvs), binding = 0},
    }

    layouts := []VertexLayout {
        {stride = size_of(Vertex), step_rate = .PerVertex}
    }

    return create_pipeline(PipelineDesc{
        label = "3D Rendering Pipeline",
        
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        
        vertex_attributes = attributes[:],
        vertex_layouts = layouts[:],
        

        primitive_topology = .TriangleList,
        cull_mode = .Back,
        front_face = .CounterClockwise,
        
        color_formats = {.BGRA8_UNorm},
        blend_states = {alpha_blend},

        depth_state = {
            test_enabled = true,
            write_enabled = true,
            compare_op = .LessOrEqual,
        },

        depth_format = .Depth32_Float,
        sample_count = DEFAULT_MSAA_SAMPLE_COUNT, 
    })
}

alpha_blend :: BlendState{
    enabled = true,
    
    // RGB: src.rgb * src.a + dst.rgb * (1 - src.a)
    src_color = .SrcAlpha,
    dst_color = .OneMinusSrcAlpha,
    color_op  = .Add,
    
    // Alpha: src.a * 1 + dst.a * (1 - src.a)
    src_alpha = .One,
    dst_alpha = .OneMinusSrcAlpha,
    alpha_op  = .Add,
}

init_default_renderer :: proc() -> (renderer: DefaultRenderer) {
    
    // Pipeline
    renderer.pipeline = create_opaque_pipeline()

    // Load texture
    renderer.custom_texture = load_texture(TextureLoadDesc{
        filepath = "textures/splash.png",
        format = .RGBA8_UNorm
    })
        
    // Create sampler
    renderer.default_sampler = create_sampler(TextureSamplerDesc{
        min_filter = .Linear,
        mag_filter = .Linear,
        mip_filter = .Linear,
        address_mode_u = .Repeat,
        address_mode_v = .Repeat,
        address_mode_w = .Repeat,
        max_anisotropy = 1,
    })

    return renderer
}
