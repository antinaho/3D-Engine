package main

import "core:math/linalg"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import NS "core:sys/darwin/Foundation"

import "core:fmt"
import "core:os"
import stbi "vendor:stb/image"

Texture :: struct {
    width, height, channels: int,
    mtl_tex: ^MTL.Texture,
}

import "core:strings"
load_texture :: proc(renderer: ^Renderer, filepath: string) -> Texture {
    platform := cast(^MetalPlatform)renderer.platform

    texture: Texture
    w, h, c: i32
    //stbi.set_flip_vertically_on_load(1)
    pixels := stbi.load(strings.clone_to_cstring(filepath, context.temp_allocator), &w, &h, &c, 4)
    assert(pixels != nil, "Cnat load")

    texture.width = int(w)
    texture.height = int(h)
    texture.channels = int(c)

    texture_descriptor := NS.new(MTL.TextureDescriptor)
    texture_descriptor->setPixelFormat(.RGBA8Unorm_sRGB)
    texture_descriptor->setWidth(NS.UInteger(w))
    texture_descriptor->setHeight(NS.UInteger(h))

    texture.mtl_tex = platform.device->newTextureWithDescriptor(texture_descriptor)

    region := MTL.Region{origin={0,0,0}, size={NS.Integer(w), NS.Integer(h), 1}}
    bytes_per_row := 4 * w

    texture.mtl_tex->replaceRegion(region, 0, pixels, NS.UInteger(bytes_per_row))

    texture_descriptor->release()
    stbi.image_free(pixels)

    return texture
}

MetalAPI :: RendererAPI {
    draw = metal_draw,
    clear_background = clear_background,
}

MetalPlatform :: struct {
    device: ^MTL.Device,
    swapchain: ^CA.MetalLayer,

    default_library: ^MTL.Library,

    command_queue: ^MTL.CommandQueue,
    render_pipeline_state: ^MTL.RenderPipelineState,

    depth_stencil_state: ^MTL.DepthStencilState,
    depth_texture: ^MTL.Texture,
    msaa_render_target_texture: ^MTL.Texture,

    renderPassDescriptor: ^MTL.RenderPassDescriptor,

    metalDrawable: ^CA.MetalDrawable,

    texture_sampler: ^MTL.SamplerState,
}

MSAA_SAMPLE_COUNT :: 4

grass_tex: Texture



import "core:slice"

shader_code :: #load("shaders/shaders.metal")

metal_init :: proc(window: ^Window) -> ^Renderer {
    renderer := new(Renderer)
    platform := new(MetalPlatform)
    renderer.platform = cast(Platform)platform

    metalWindow := cast(^NS.Window)window.get_window_handle(window)

    platform.device = MTL.CreateSystemDefaultDevice()
    assert(platform.device != nil, "Metal not supported")

    platform.swapchain = CA.MetalLayer.layer()
    platform.swapchain->setDevice(platform.device)
    platform.swapchain->setPixelFormat(.BGRA8Unorm_sRGB)
    platform.swapchain->setFramebufferOnly(true)
    platform.swapchain->setFrame(metalWindow->frame())

    metalWindow->contentView()->setLayer(platform.swapchain)
    metalWindow->setOpaque(true)
    metalWindow->setBackgroundColor(nil)
    metalWindow->contentView()->setWantsLayer(true)

    { // Triangle to buffer  
        cube_mesh := create_cube_mesh(platform)

        for i in 1..<10 {
            append(&models, ModelM{
                mesh = cube_mesh,
                position={0,0,-1},
                scale={1.0 * 1.0/f32(i), 1.0 * 1.0/f32(i), 1.0 * 1.0/f32(i)},
                rotation_angle=0,
                rotation_axis={0,1,0},
            })
        }

        grass_tex = load_texture(renderer, "textures/candy.jpg")
    }

    {   // Default library
        compile_options := NS.new(MTL.CompileOptions)
	    defer compile_options->release()
        err: ^NS.Error
        platform.default_library, err = platform.device->newLibraryWithSource(NS.AT(cstring(shader_code)), compile_options)
        assert(err == nil)

        // platform.default_library = platform.device->newDefaultLibrary()
        // assert(platform.default_library != nil, "Failed to load default library")
    }

    {   // Command queue
        platform.command_queue = platform.device->newCommandQueue()
    }

    {   // Render pipeline
        vertex_shader := platform.default_library->newFunctionWithName(NS.AT("vertex_main"))
        assert(vertex_shader != nil)

        fragment_shader := platform.default_library->newFunctionWithName(NS.AT("fragment_main"))
        assert(fragment_shader != nil)

        render_pipeline_descriptor := NS.new(MTL.RenderPipelineDescriptor)
        render_pipeline_descriptor->setLabel(NS.AT("Triangle rendering pipeline"))
        render_pipeline_descriptor->setVertexFunction(vertex_shader)
        render_pipeline_descriptor->setFragmentFunction(fragment_shader)
        render_pipeline_descriptor->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)
        render_pipeline_descriptor->setSampleCount(4) // MSAA
        render_pipeline_descriptor->setDepthAttachmentPixelFormat(.Depth32Float) // Depth

        err: ^NS.Error
        platform.render_pipeline_state, err = platform.device->newRenderPipelineState(render_pipeline_descriptor)
        if err != nil {
            fmt.println("Err")
            os.exit(1)
        }

        depth_stencil_descriptor := NS.new(MTL.DepthStencilDescriptor)
        depth_stencil_descriptor->setDepthCompareFunction(.LessEqual)
        depth_stencil_descriptor->setDepthWriteEnabled(true)
        platform.depth_stencil_state = platform.device->newDepthStencilState(depth_stencil_descriptor)

        render_pipeline_descriptor->release()
        vertex_shader->release()
        fragment_shader->release()
    }

    {   // Depth and MSAA textures
        create_depth_and_msaa_textures(platform)
    }

    { // Render pass descriptor
        platform.renderPassDescriptor = NS.new(MTL.RenderPassDescriptor)

        color_attachment := platform.renderPassDescriptor->colorAttachments()->object(0)
        depth_attachment := platform.renderPassDescriptor->depthAttachment()

        color_attachment->setTexture(platform.msaa_render_target_texture)
        color_attachment->setResolveTexture(platform.metalDrawable->texture())
        color_attachment->setLoadAction(.Clear)
        color_attachment->setClearColor(color_to_clear_color(renderer.clear_color))
        color_attachment->setStoreAction(MTL.StoreAction.MultisampleResolve)

        depth_attachment->setTexture(platform.depth_texture)
        depth_attachment->setLoadAction(.Clear)
        depth_attachment->setStoreAction(.DontCare)
        depth_attachment->setClearDepth(1.0)
    }

    {   // Default sampler

        sampler_descriptor := NS.new(MTL.SamplerDescriptor)
        defer sampler_descriptor->release()

        sampler_descriptor->setMinFilter(.Linear)
        sampler_descriptor->setMagFilter(.Linear)
        sampler_descriptor->setMipFilter(.Linear)

        sampler_descriptor->setSAddressMode(.Repeat)
        sampler_descriptor->setTAddressMode(.Repeat)
        sampler_descriptor->setRAddressMode(.Repeat)

        platform.texture_sampler = platform.device->newSamplerState(sampler_descriptor)
    }

    renderer.api = MetalAPI
    
    platform.metalDrawable = platform.swapchain->nextDrawable()

    return renderer
}

create_depth_and_msaa_textures :: proc(platform: ^MetalPlatform) {
    msaa_texture_descriptor := NS.new(MTL.TextureDescriptor)
    msaa_texture_descriptor->setTextureType(.Type2DMultisample)
    msaa_texture_descriptor->setPixelFormat(.BGRA8Unorm)
    msaa_texture_descriptor->setWidth(NS.UInteger(platform.swapchain->frame().width))
    msaa_texture_descriptor->setHeight(NS.UInteger(platform.swapchain->frame().height))
    msaa_texture_descriptor->setSampleCount(4)
    msaa_texture_descriptor->setUsage({.RenderTarget})
    defer msaa_texture_descriptor->release()

    platform.msaa_render_target_texture = platform.device->newTexture(msaa_texture_descriptor);

    depth_texture_descriptor := NS.new(MTL.TextureDescriptor)
    depth_texture_descriptor->setTextureType(.Type2DMultisample)
    depth_texture_descriptor->setPixelFormat(.Depth32Float)
    depth_texture_descriptor->setWidth(NS.UInteger(platform.swapchain->frame().width))
    depth_texture_descriptor->setHeight(NS.UInteger(platform.swapchain->frame().height))
    depth_texture_descriptor->setSampleCount(4)
    depth_texture_descriptor->setUsage({.RenderTarget})
    defer depth_texture_descriptor->release()

    platform.depth_texture = platform.device->newTexture(depth_texture_descriptor);
}

clear_background :: proc(renderer: ^Renderer, color: Color) {
    renderer.clear_color = color
}

color_to_clear_color :: proc(color: Color) -> MTL.ClearColor {
    return MTL.ClearColor {
        f64(color.r) / 255.0,
        f64(color.g) / 255.0,
        f64(color.b) / 255.0,
        f64(color.a) / 255.0,
    }
}

resize_resources :: proc(platform: ^MetalPlatform) {
    if platform.msaa_render_target_texture != nil {
        platform.msaa_render_target_texture->release()
        platform.msaa_render_target_texture = nil
    }

    if platform.depth_texture != nil {
        platform.depth_texture->release()
        platform.depth_texture = nil
    }

    create_depth_and_msaa_textures(platform)
    update_render_pass_descriptor(platform)
}

update_render_pass_descriptor :: proc(platform: ^MetalPlatform) {
    platform.renderPassDescriptor->colorAttachments()->object(0)->setTexture(platform.msaa_render_target_texture);
    platform.renderPassDescriptor->colorAttachments()->object(0)->setResolveTexture(platform.metalDrawable->texture());
    platform.renderPassDescriptor->depthAttachment()->setTexture(platform.depth_texture);
}

metal_draw :: proc(window: ^Window, renderer: ^Renderer) {
    NS.scoped_autoreleasepool()

    platform := cast(^MetalPlatform)renderer.platform
    
    if !window.is_visible || window.is_minimized {
        return
    }

    platform.metalDrawable = platform.swapchain->nextDrawable()
    if platform.metalDrawable == nil {
        fmt.println("No drawable skipping frame")
        return
    }

    dtex := platform.metalDrawable->texture()
    if dtex == nil {
        fmt.println("Warning: Drawable texture is nil, skipping frame")
        return

    } 

    // if window.did_resize {
    //     resize_resources(platform)
    // }

    command_buffer := platform.command_queue->commandBuffer()
    update_render_pass_descriptor(platform)

    render_pass_descriptor := NS.new(MTL.RenderPassDescriptor)
    color_attachment := render_pass_descriptor->colorAttachments()->object(0)

    color_attachment->setTexture(platform.metalDrawable->texture())
    color_attachment->setLoadAction(.Clear)
    color_attachment->setClearColor(color_to_clear_color(renderer.clear_color))
    color_attachment->setStoreAction(.Store)    

    render_encoder := command_buffer->renderCommandEncoderWithDescriptor(render_pass_descriptor)

    render_encoder->setFrontFacingWinding(.CounterClockwise);
    render_encoder->setCullMode(.Back);
    render_encoder->setTriangleFillMode(.Fill)
    render_encoder->setRenderPipelineState(platform.render_pipeline_state)
    render_encoder->setDepthStencilState(platform.depth_stencil_state)

    // View
    R := linalg.Vector3f32{1,0,0} // Unit right
    U := linalg.Vector3f32{0, 1, 0} // Unit up
    F := linalg.Vector3f32{0, 0, -1} // Unit right
    P := camera.position // Camera world space position
    view_matrix := linalg.Matrix4x4f32 {
        R.x, R.y, R.z, linalg.dot(-R, P),
        U.x, U.y, U.z, linalg.dot(-U, P),
        -F.x, -F.y, -F.z, linalg.dot(F, P),
        0,0,0,1
    }

    // Projection
    aspect_ratio := platform.swapchain->frame().width / platform.swapchain->frame().height
    fov := camera.FOV * (math.PI / 180.0)
    projection_matrix := matrix_perspective_right_hand(camera.near_clip, camera.far_clip, f32(aspect_ratio), fov)
    

    for &model, i in models {
        orbit_radius := f32(1.0) + f32(i) * 0.3  // Orbit gets bigger
        orbit_speed := f32(2.0)
        angle := runtime_app * orbit_speed
        
        // Each cube offset in angle (spiral)
        phase_offset := f32(i) * (2 * math.PI / f32(len(models)))
        
        model.position.x = math.cos(angle + phase_offset) * orbit_radius
        model.position.y = math.sin(angle + phase_offset) * orbit_radius
        model.position.z = -1.0 - f32(i) * 2.0  // Farther back
        
        // 3. Update rotation (spin around Y-axis)
        spin_speed := f32(1)  // Radians per second
        model.rotation_angle += delta * spin_speed
        model.rotation_axis = {0, 1, 0}  // Spin around Y
        
        
        model_matrix := 
        linalg.matrix4_translate_f32(model.position) *
        linalg.matrix4_rotate_f32(model.rotation_angle, model.rotation_axis) *
        linalg.matrix4_scale_f32(model.scale)
        
        translation_matrix := linalg.matrix4_translate_f32(linalg.Vector3f32{0,0, -1.0})
        
        ubo := Uniforms {
            model_matrix = model_matrix,
            view_matrix = view_matrix,
            perspective_matrix = projection_matrix,
            time = runtime_app,
            delta = delta,
        }
        
        uniform_bytes := mem.ptr_to_bytes(&ubo)
        
        render_encoder->setVertexBytes(uniform_bytes, 1)
        render_encoder->setVertexBuffer(model.mesh.vertex_buffer, 0, 0)
        render_encoder->setFragmentBytes(uniform_bytes, 0)

        render_encoder->setFragmentTexture(grass_tex.mtl_tex, 0)

        render_encoder->setFragmentSamplerState(platform.texture_sampler, 0)

        render_encoder->drawPrimitives(.Triangle, 0, NS.UInteger(model.mesh.vertex_count))
    }
            
    render_encoder->endEncoding()

    command_buffer->presentDrawable(platform.metalDrawable)
    command_buffer->commit()
    command_buffer->waitUntilCompleted()

}

models: [dynamic]ModelM
// models := [?]ModelM {
//     {position={0,0,-1}, scale={1, 1, 1}, rotation_angle=0, rotation_axis={0,1,0}},
// }

create_cube_mesh :: proc(platform: ^MetalPlatform) -> ^Mesh {
    vertices := [?]Vertex {
        {{-0.5, -0.5, 0.5, 1.0}, {1,1,1,1}, {0.0, 0.0}},
        {{0.5, -0.5, 0.5, 1.0},  {1,1,1,1}, {1.0, 0.0}},
        {{0.5, 0.5, 0.5, 1.0},   {1,1,1,1}, {1.0, 1.0}},
        {{0.5, 0.5, 0.5, 1.0},   {1,1,1,1}, {1.0, 1.0}},
        {{-0.5, 0.5, 0.5, 1.0},  {1,1,1,1}, {0.0, 1.0}},
        {{-0.5, -0.5, 0.5, 1.0}, {1,1,1,1}, {0.0, 0.0}},

        // Back face
        {{0.5, -0.5, -0.5, 1.0}, {1,1,1,1},{0.0, 0.0}},
        {{-0.5, -0.5, -0.5, 1.0}, {1,1,1,1},{1.0, 0.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {1,1,1,1},{1.0, 1.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {1,1,1,1},{1.0, 1.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1,1,1,1},{0.0, 1.0}},
        {{0.5, -0.5, -0.5, 1.0},{1,1,1,1}, {0.0, 0.0}},

        // Top face
        {{-0.5, 0.5, 0.5, 1.0},{1,1,1,1}, {0.0, 0.0}},
        {{0.5, 0.5, 0.5, 1.0}, {1,1,1,1},{1.0, 0.0}},
        {{0.5, 0.5, -0.5, 1.0},{1,1,1,1}, {1.0, 1.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1,1,1,1},{1.0, 1.0}},
        {{-0.5, 0.5, -0.5, 1.0},{1,1,1,1}, {0.0, 1.0}},
        {{-0.5, 0.5, 0.5, 1.0},{1,1,1,1}, {0.0, 0.0}},

        // Bottom face
        {{-0.5, -0.5, -0.5, 1.0},{1,1,1,1}, {0.0, 0.0}},
        {{0.5, -0.5, -0.5, 1.0},{1,1,1,1}, {1.0, 0.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1,1,1,1},{1.0, 1.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1,1,1,1},{1.0, 1.0}},
        {{-0.5, -0.5, 0.5, 1.0},{1,1,1,1}, {0.0, 1.0}},
        {{-0.5, -0.5, -0.5, 1.0},{1,1,1,1}, {0.0, 0.0}},

        // Left face
        {{-0.5, -0.5, -0.5, 1.0}, {1,1,1,1},{0.0, 0.0}},
        {{-0.5, -0.5, 0.5, 1.0},{1,1,1,1}, {1.0, 0.0}},
        {{-0.5, 0.5, 0.5, 1.0},{1,1,1,1}, {1.0, 1.0}},
        {{-0.5, 0.5, 0.5, 1.0},{1,1,1,1}, {1.0, 1.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {1,1,1,1},{0.0, 1.0}},
        {{-0.5, -0.5, -0.5, 1.0},{1,1,1,1},{0.0, 0.0}},

        // Right face
        {{0.5, -0.5, 0.5, 1.0},{1,1,1,1}, {0.0, 0.0}},
        {{0.5, -0.5, -0.5, 1.0},{1,1,1,1}, {1.0, 0.0}},
        {{0.5, 0.5, -0.5, 1.0},{1,1,1,1}, {1.0, 1.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1,1,1,1},{1.0, 1.0}},
        {{0.5, 0.5, 0.5, 1.0},{1,1,1,1}, {0.0, 1.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1,1,1,1},{0.0, 0.0}},
    }

    vertex_buffer := platform.device->newBufferWithSlice(vertices[:], MTL.ResourceStorageModeShared)
    
    mesh := new(Mesh)
    mesh.vertex_buffer = vertex_buffer
    mesh.vertex_count = len(vertices)
        
    return mesh
}


Mesh :: struct {
    vertex_buffer: ^MTL.Buffer,
    vertex_count: u32,
    index_buffer: ^MTL.Buffer,
    index_count: u32,
}

ModelM :: struct {
    mesh: ^Mesh,
    rotation_angle: f32,  // Radians
    rotation_axis: linalg.Vector3f32,
    position, scale: [3]f32,
}

import "core:mem"

Uniforms :: struct #align(16) {
    perspective_matrix: linalg.Matrix4x4f32,
    view_matrix: linalg.Matrix4x4f32,
    model_matrix: linalg.Matrix4x4f32,
    time: f32,
    delta: f32,
    _padding: [2]f32,
}

#assert(size_of(Uniforms) == 208)
#assert(offset_of(Uniforms, perspective_matrix) == 0)
#assert(offset_of(Uniforms, view_matrix) == 64)
#assert(offset_of(Uniforms, model_matrix) == 128)
#assert(offset_of(Uniforms, time) == 192)
#assert(offset_of(Uniforms, delta) == 196)
#assert(offset_of(Uniforms, _padding) == 200)

import "core:math"
import "core:math/rand"

clean_up :: proc(renderer: ^Renderer) {
    platform := cast(^MetalPlatform)renderer.platform

    platform.msaa_render_target_texture->release()
    platform.depth_texture->release()
    
    
    //renderPassDescriptor->release();
    

    platform.device->release()
}