package main

RendererType :: enum {
    Metal = 1
}

when ODIN_OS == .Darwin {
    RENDERER :: RendererType.Metal
} else {
    RENDERER :: 0
}


Renderer :: struct {
    using api: RendererAPI,
    platform: Platform,
    clear_color: Color,
}

RendererAPI :: struct {
    draw: proc(window: ^Window, renderer: ^Renderer),
    cleanup: proc(window: ^Window, renderer: ^Renderer),
}

Color :: [4]u8

PINK :: Color {255, 203, 196, 255}
PEACH :: Color {255, 203, 165, 255}
APINK :: Color {255, 152, 153, 255}
DARKPURP :: Color {30, 25, 35, 255}


Camera :: struct {
    position: [3]f32,
    target: [3]f32,
    fov: f32,
    zoom: f32,
    aspect: f32,
    near: f32,
    far: f32,
}

camera := Camera {
    position = {0, 0, 1},
    target = {0, 0, 0},
    aspect = 1280.0 / 720.0,
    zoom = 5,
    near = 0.1,
    far = 100,
    fov = 90,
}

Renderer_3D :: struct {
    pipeline: Pipeline,
    
    // Render targets
    msaa_render_target_texture: Texture,
    depth_texture: Texture,
    
    // Resources
    default_sampler: Sampler,
    renderpass_descriptor: rawptr,
    custom_texture: Texture,
    
    // Per-frame
    vertex_buffer: Buffer,
    index_buffer: Buffer,
}

create_default_pipeline :: proc() -> Pipeline {

    vertex_shader, v_ok := load_shader("shaders/shaders.metal", .Vertex, "vertex_m")
    fragment_shader, f_ok := load_shader("shaders/shaders.metal", .Fragment, "fragment_m")
    
    attributes := make([dynamic]VertexAttribute)
    append(&attributes, VertexAttribute{format = .Float3, offset=offset_of(Vertex, position),  binding = 0})
    append(&attributes, VertexAttribute{format = .Float3, offset=offset_of(Vertex, normal), binding = 0})
    append(&attributes, VertexAttribute{format = .Float4, offset=offset_of(Vertex, color), binding = 0})
    append(&attributes, VertexAttribute{format = .Float2, offset=offset_of(Vertex, uvs), binding = 0})
    
    layouts := make([dynamic]VertexLayout)
    append(&layouts, VertexLayout{stride = size_of(Vertex), step_rate = .PerVertex})

    MSAA_SAMPLE_COUNT :: 4



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
        sample_count = MSAA_SAMPLE_COUNT,  // MSAA
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

import "core:log"
import "core:fmt"
init_renderer_3d :: proc(
    width: int,
    height: int,
) -> (renderer: Renderer_3D) {
    
    // Create pipeline with MSAA
    renderer.pipeline = create_default_pipeline()

    // Create MSAA color target
    renderer.msaa_render_target_texture = create_texture(Texture_Desc{
        format = .BGRA8_UNorm,
        usage = .RenderTarget,
        type = .Texture2DMultisample,
        sample_count = 4,  // 4x MSAA
        mip_levels = 1,
    })

    renderer.custom_texture = load_texture(TextureLoadDesc{
        filepath = "textures/face.jpg",
        format = .RGBA8_UNorm
    })
    
    // Create depth buffer
    renderer.depth_texture = create_texture(Texture_Desc{
        format = .Depth32_Float,
        usage = .Depth,
        type = .Texture2DMultisample,
        sample_count = 4,  // Match MSAA
        mip_levels = 1,
    })
    
    // Create default sampler
    renderer.default_sampler = create_sampler(Sampler_Desc{
        min_filter = .Linear,
        mag_filter = .Linear,
        mip_filter = .Linear,
        address_mode_u = .Repeat,
        address_mode_v = .Repeat,
        address_mode_w = .Repeat,
        max_anisotropy = 1,
    })

    renderer.renderpass_descriptor = create_renderpass_descriptor(RenderPassDescriptor {
        name="Test",
        clear_color = {235 / 255.0, 177 / 255.0 , 136 / 255.0,1.0},
        load_action =.Clear,
        msaa_texture=renderer.msaa_render_target_texture,
        depth_texture=renderer.depth_texture,
    })

    return renderer
}

RenderPassDescriptor :: struct {
    name: string,
    clear_color: [4]f32,
    //clear_depth: f32,
    load_action: Load_Action,
    
    // Optional: For MSAA
    msaa_texture: Texture,
    depth_texture: Texture,
}

create_renderpass_descriptor :: proc(desc: RenderPassDescriptor) -> rawptr {
    when RENDERER == .Metal {
        return metal_create_renderpass_descriptor(desc)
    } else when RENDERER == .Vulkan {
        
    }
}

resize_renderer_3d :: proc(renderer: ^Renderer_3D, width: int, height: int) {
    // Destroy old textures
    destroy_texture(&renderer.msaa_render_target_texture)
    destroy_texture(&renderer.depth_texture)
    
    // Recreate with new size
    renderer.msaa_render_target_texture = create_texture(Texture_Desc{
        width = width,
        height = height,
        format = .BGRA8_UNorm_sRGB,
        usage = .RenderTarget,
        type = .Texture2D,
        sample_count = 4,
        mip_levels = 1,
    })
    
    renderer.depth_texture = create_texture(Texture_Desc{
        width = width,
        height = height,
        format = .Depth32_Float,
        usage = .Depth,
        type = .Texture2D,
        sample_count = 4,
        mip_levels = 1,
    })
}

destroy_renderer_3d :: proc(renderer: ^Renderer_3D) {
    destroy_pipeline(&renderer.pipeline)
    destroy_texture(&renderer.msaa_render_target_texture)
    destroy_texture(&renderer.depth_texture)
    destroy_sampler(&renderer.default_sampler)
}