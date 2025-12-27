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
    clear_background: proc(renderer: ^Renderer, color: Color),
    cleanup: proc(window: ^Window, renderer: ^Renderer),
}

Color :: [4]u8

PINK :: Color {255, 203, 196, 255}
PEACH :: Color {255, 203, 165, 255}
APINK :: Color {255, 152, 153, 255}
DARKPURP :: Color {30, 25, 35, 255}


Camera :: struct {
    position: [3]f32,
    near_clip: f32,
    far_clip: f32,
    FOV: f32,
}

camera := Camera {
    position = {0, 0, 1},
    near_clip = 0.1,
    far_clip = 100,
    FOV = 90,
}

Renderer_3D :: struct {
    pipeline: Pipeline,
    
    // Render targets
    msaa_color_texture: Texture,
    depth_texture: Texture,
    
    // Resources
    default_sampler: Sampler,
    renderpass_descriptor: rawptr,
    
    // Per-frame
    vertex_buffer: Buffer,
    index_buffer: Buffer,
}

create_default_pipeline :: proc() -> Pipeline {

    vertex_shader, v_ok := load_shader("shaders/shaders.metal", .Vertex, "vertex_m")
    fragment_shader, f_ok := load_shader("shaders/shaders.metal", .Fragment, "fragment_m")
    
    attributes := make([dynamic]Vertex_Attribute)
    append(&attributes, Vertex_Attribute{format = .Float3, offset = 0,  binding = 0})
    append(&attributes, Vertex_Attribute{format = .Float3, offset = 16, binding = 0})
    append(&attributes, Vertex_Attribute{format = .Float4, offset = 32, binding = 0})
    append(&attributes, Vertex_Attribute{format = .Float2, offset = 48, binding = 0})
    
    layouts := make([dynamic]Vertex_Layout)
    append(&layouts, Vertex_Layout{stride = size_of(Vertex), step_rate = .PerVertex})

    MSAA_SAMPLE_COUNT :: 4
    pixel_formats := make([dynamic]Pixel_Format)
    append(&pixel_formats, Pixel_Format.BGRA8_UNorm_sRGB)

    return create_pipeline(Pipeline_Desc{
        label = "3D Rendering Pipeline",
        
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        
        vertex_attributes = attributes[:],
        vertex_layouts = layouts[:],
        
        primitive_topology = .TriangleList,
        cull_mode = .Back,
        front_face = .CounterClockwise,
        
        depth_state = {
            test_enabled = true,
            write_enabled = true,
            compare_op = .LessOrEqual,
        },
        
        color_formats = pixel_formats[:],
        depth_format = .Depth32_Float,
        sample_count = MSAA_SAMPLE_COUNT,  // MSAA
    })
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
    renderer.msaa_color_texture = create_texture(Texture_Desc{
        width = width,
        height = height,
        depth = 1,
        format = .BGRA8_UNorm,
        usage = .RenderTarget,
        type = .Texture2DMultisample,
        sample_count = 4,  // 4x MSAA
        mip_levels = 1,
    })
    
    // Create depth buffer
    renderer.depth_texture = create_texture(Texture_Desc{
        width = width,
        height = height,
        depth = 1,
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
        clear_color = {0.1,0.1,0.3,1},
        clear_depth = 1.0,
        load_action =.Clear,
        msaa_texture=renderer.msaa_color_texture,
        depth_texture=renderer.depth_texture,
        drawable = get_drawable(),
    })


    log.debug(renderer.depth_texture)
    log.debug(renderer.msaa_color_texture)
    log.error(renderer.pipeline)
    
    log.debug(renderer.renderpass_descriptor)

    return renderer
}

RenderPassDescriptor :: struct {
    name: string,
    clear_color: [4]f32,
    clear_depth: f32,
    load_action: Load_Action,
    
    // Optional: For MSAA
    msaa_texture: Texture,
    depth_texture: Texture,
    drawable: rawptr,
}

create_renderpass_descriptor :: proc(desc: RenderPassDescriptor) -> rawptr {
    when RENDERER == .Metal {
        return metal_create_renderpass_descriptor(desc)
    } else when RENDERER == .Vulkan {
        
    }
}

resize_renderer_3d :: proc(renderer: ^Renderer_3D, width: int, height: int) {
    // Destroy old textures
    destroy_texture(&renderer.msaa_color_texture)
    destroy_texture(&renderer.depth_texture)
    
    // Recreate with new size
    renderer.msaa_color_texture = create_texture(Texture_Desc{
        width = width,
        height = height,
        depth = 1,
        format = .BGRA8_UNorm_sRGB,
        usage = .RenderTarget,
        type = .Texture2D,
        sample_count = 4,
        mip_levels = 1,
    })
    
    renderer.depth_texture = create_texture(Texture_Desc{
        width = width,
        height = height,
        depth = 1,
        format = .Depth32_Float,
        usage = .Depth,
        type = .Texture2D,
        sample_count = 4,
        mip_levels = 1,
    })
}

destroy_renderer_3d :: proc(renderer: ^Renderer_3D) {
    destroy_pipeline(&renderer.pipeline)
    destroy_texture(&renderer.msaa_color_texture)
    destroy_texture(&renderer.depth_texture)
    destroy_sampler(&renderer.default_sampler)
}