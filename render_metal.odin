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
    cleanup = _cleanup,
}

_cleanup :: proc(window: ^Window, renderer: ^Renderer) {
    platform := cast(^MetalPlatform)renderer.platform

    platform.msaa_render_target_texture->release()
    platform.depth_texture->release()
    platform.renderPassDescriptor->release()
    platform.swapchain->release()

    
    for _, value in asset_library.primitive_meshes {
        free(value)
    }
    delete(asset_library.primitive_meshes)

    delete(models)
    grass_tex.mtl_tex->release()

    platform.device->release()

    free(platform)
    free(renderer)
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


        for i in 1..=5 {
            DrawPrimitive(platform, .Cube, {0,0,-1}, {0,1,0}, 1)
        }

        for i in 1..=2 {
            DrawPrimitive(platform, .Cube, {0,0,-1}, {0,1,0}, 0.2)
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

    lighting_buffer = platform.device->newBuffer(
        size_of(LightingData),
        MTL.ResourceStorageModeShared
    )


    return renderer
}
lighting_buffer :^MTL.Buffer
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

AssetLibrary :: struct {
    primitive_meshes: map[Primitive]^Mesh,
}
asset_library: AssetLibrary

DrawPrimitive :: proc(platform: ^MetalPlatform, primitive: Primitive, position, rotation, scale: [3]f32) {
    mesh := GetPrimitiveMesh(platform, primitive)

    model := ModelM {
        mesh = mesh,
        position = position,
        rotation_axis = rotation,
        scale = scale,
    }

    append(&models, model)
}

GetPrimitiveMesh :: proc(platform: ^MetalPlatform, primitive: Primitive) -> ^Mesh {

    if primitive in asset_library.primitive_meshes {
        return asset_library.primitive_meshes[primitive]
    }

    mesh := new(Mesh)

    #partial switch primitive {
        case .Cube:
            mesh.vertex_buffer = platform.device->newBufferWithSlice(CUBE_VERTICES, MTL.ResourceStorageModeShared)
            mesh.vertex_count = u32(len(CUBE_VERTICES))
    }
    
    asset_library.primitive_meshes[primitive] = mesh
    
    return mesh
}

CUBE_VERTICES :: []Vertex {
     // Front face (normal pointing towards +Z)
    {{-0.5, -0.5,  0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, { 0,  0,  1}},  // 0
    {{ 0.5, -0.5,  0.5, 1.0}, {1, 1, 1, 1}, {1.0, 0.0}, { 0,  0,  1}},  // 1
    {{ 0.5,  0.5,  0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, { 0,  0,  1}},  // 2
    {{ 0.5,  0.5,  0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, { 0,  0,  1}},  // 3
    {{-0.5,  0.5,  0.5, 1.0}, {1, 1, 1, 1}, {0.0, 1.0}, { 0,  0,  1}},  // 4
    {{-0.5, -0.5,  0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, { 0,  0,  1}},  // 5

    // Back face (normal pointing towards -Z)
    {{ 0.5, -0.5, -0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, { 0,  0, -1}},  // 6
    {{-0.5, -0.5, -0.5, 1.0}, {1, 1, 1, 1}, {1.0, 0.0}, { 0,  0, -1}},  // 7
    {{-0.5,  0.5, -0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, { 0,  0, -1}},  // 8
    {{-0.5,  0.5, -0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, { 0,  0, -1}},  // 9
    {{ 0.5,  0.5, -0.5, 1.0}, {1, 1, 1, 1}, {0.0, 1.0}, { 0,  0, -1}},  // 10
    {{ 0.5, -0.5, -0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, { 0,  0, -1}},  // 11

    // Left face (normal pointing towards -X)
    {{-0.5, -0.5, -0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, {-1,  0,  0}},  // 12
    {{-0.5, -0.5,  0.5, 1.0}, {1, 1, 1, 1}, {1.0, 0.0}, {-1,  0,  0}},  // 13
    {{-0.5,  0.5,  0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, {-1,  0,  0}},  // 14
    {{-0.5,  0.5,  0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, {-1,  0,  0}},  // 15
    {{-0.5,  0.5, -0.5, 1.0}, {1, 1, 1, 1}, {0.0, 1.0}, {-1,  0,  0}},  // 16
    {{-0.5, -0.5, -0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, {-1,  0,  0}},  // 17

    // Right face (normal pointing towards +X)
    {{ 0.5, -0.5,  0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, { 1,  0,  0}},  // 18
    {{ 0.5, -0.5, -0.5, 1.0}, {1, 1, 1, 1}, {1.0, 0.0}, { 1,  0,  0}},  // 19
    {{ 0.5,  0.5, -0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, { 1,  0,  0}},  // 20
    {{ 0.5,  0.5, -0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, { 1,  0,  0}},  // 21
    {{ 0.5,  0.5,  0.5, 1.0}, {1, 1, 1, 1}, {0.0, 1.0}, { 1,  0,  0}},  // 22
    {{ 0.5, -0.5,  0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, { 1,  0,  0}},  // 23

    // Top face (normal pointing towards +Y)
    {{-0.5,  0.5,  0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, { 0,  1,  0}},  // 24
    {{ 0.5,  0.5,  0.5, 1.0}, {1, 1, 1, 1}, {1.0, 0.0}, { 0,  1,  0}},  // 25
    {{ 0.5,  0.5, -0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, { 0,  1,  0}},  // 26
    {{ 0.5,  0.5, -0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, { 0,  1,  0}},  // 27
    {{-0.5,  0.5, -0.5, 1.0}, {1, 1, 1, 1}, {0.0, 1.0}, { 0,  1,  0}},  // 28
    {{-0.5,  0.5,  0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, { 0,  1,  0}},  // 29

    // Bottom face (normal pointing towards -Y)
    {{-0.5, -0.5, -0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, { 0, -1,  0}},  // 30
    {{ 0.5, -0.5, -0.5, 1.0}, {1, 1, 1, 1}, {1.0, 0.0}, { 0, -1,  0}},  // 31
    {{ 0.5, -0.5,  0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, { 0, -1,  0}},  // 32
    {{ 0.5, -0.5,  0.5, 1.0}, {1, 1, 1, 1}, {1.0, 1.0}, { 0, -1,  0}},  // 33
    {{-0.5, -0.5,  0.5, 1.0}, {1, 1, 1, 1}, {0.0, 1.0}, { 0, -1,  0}},  // 34
    {{-0.5, -0.5, -0.5, 1.0}, {1, 1, 1, 1}, {0.0, 0.0}, { 0, -1,  0}},  // 35

}

Primitive :: enum {
    Quad,
    Cube,
    Sphere,
    Cylinder,
    Circle,
    Tube,
    Cone,
    Torus,
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

    lighting := LightingData{
        directional_light = DirectionalLight{
            direction = linalg.normalize([3]f32{0.3, -1, -0.5}),
            color = {1.0, 0.95, 0.8},  // Slight warm sun
            intensity = 1.2,
        },

        camera_position = camera.position,
        ambient_color = {0.4, 0.5, 0.6},  // Slight blue ambient
        ambient_intensity = 0.25,
    }

    lighting.point_lights[0] = PointLight{
            position = {
                1.25,                           // X: static
                0.2,                           // Y: static  
                -3 + math.sin(runtime_app) * 4,    // Z: oscillates between -7 and -3
            },
            color = {0, 1, 0},  
            intensity = 3.0,
            constant = 1.0,
            linear = 0.09,
            quadratic = 0.032,
            radius = 5.0,
        }

    lighting.point_lights[1] = PointLight{
            position = {
                -1.25,                           // X: static
                0.2,                           // Y: static  
                -3 - math.sin(runtime_app) * 4,    // Z: oscillates between -7 and -3
            },
            color = {0, 0, 1},  
            intensity = 3.0,
            constant = 1.0,
            linear = 0.09,
            quadratic = 0.032,
            radius = 5.0,
        }
    


    contents := lighting_buffer->contentsAsSlice([]LightingData)[:1]
    contents[0] = lighting

    render_encoder->setFragmentBuffer(lighting_buffer, 0, 1)

    for &model, i in models[:len(models)-2] {
        orbit_radius := f32(1.0) + f32(i) * 0.3  // Orbit gets bigger
        orbit_speed := f32(2.0)
        angle := runtime_app * orbit_speed
        
        // Each cube offset in angle (spiral)
        phase_offset := f32(i) * (2 * math.PI / f32(len(models)))
        
        model.position.x = 0 //math.cos(angle + phase_offset) * orbit_radius
        model.position.y = math.sin(angle + phase_offset) * orbit_radius
        model.position.z = -1.0 - f32(i) * 2.0  // Farther back
        
        // 3. Update rotation (spin around Y-axis)
        spin_speed := f32(0.1)  // Radians per second
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
            projection_matrix = projection_matrix,
            light_position = {0,0,0,0},
            light_direction = {0,0,0,0},
            time_data = {runtime_app, delta, 0, 0},
        }

        uniform_bytes := mem.ptr_to_bytes(&ubo)
        
        render_encoder->setVertexBytes(uniform_bytes, 1)
        render_encoder->setVertexBuffer(model.mesh.vertex_buffer, 0, 0)
        render_encoder->setFragmentBytes(uniform_bytes, 0)
        render_encoder->setFragmentTexture(grass_tex.mtl_tex, 0)

        render_encoder->setFragmentSamplerState(platform.texture_sampler, 0)

        render_encoder->drawPrimitives(.Triangle, 0, NS.UInteger(model.mesh.vertex_count))
    }

    for &model, i in models[len(models)-2:] {
        model.position = lighting.point_lights[i].position

        model_matrix := 
            linalg.matrix4_translate_f32(model.position) *
            linalg.matrix4_rotate_f32(model.rotation_angle, model.rotation_axis) *
            linalg.matrix4_scale_f32(model.scale)
            
        translation_matrix := linalg.matrix4_translate_f32(linalg.Vector3f32{0,0, -1.0})
        
        ubo := Uniforms {
            model_matrix = model_matrix,
            view_matrix = view_matrix,
            projection_matrix = projection_matrix,
            light_position = {0,0,0,0},
            light_direction = {0,0,0,0},
            time_data = {runtime_app, delta, 0, 0},
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


Mesh :: struct {
    vertex_buffer: ^MTL.Buffer,
    vertex_count: u32,
    index_buffer: ^MTL.Buffer,
    index_count: u32,
    ref_count: int,
}

ModelM :: struct {
    mesh: ^Mesh,
    rotation_angle: f32,  // Radians
    rotation_axis: linalg.Vector3f32,
    position, scale: [3]f32,
}

import "core:mem"

Uniforms :: struct #align(16) {
    projection_matrix: linalg.Matrix4x4f32,
    view_matrix: linalg.Matrix4x4f32,
    model_matrix: linalg.Matrix4x4f32,
    
    light_position: [4]f32,
    light_direction: [4]f32,
    time_data: [4]f32,
}

// Directional light (sun, moon)
DirectionalLight :: struct #align(16) {
    direction: [3]f32,  // Direction the light points
    _: f32,
    color: [3]f32,      // RGB color
    _: f32,
    intensity: f32,           // Brightness multiplier
    _: [3]f32,
}

// Point light (lamp, torch)
PointLight :: struct #align(16) {
    position: [3]f32,
    _: f32,
    color: [3]f32,
    _: f32,

    intensity: f32,
    constant: f32,    // Usually 1.0
    linear: f32,      // Usually 0.09
    quadratic: f32,   // Usually 0.032
    
    radius: f32,      // Max distance
    _: [3]f32,
}

// Lighting data to pass to shaders
LightingData :: struct #align(16) {
    // Directional lights
    point_lights: [16]PointLight,
    directional_light: DirectionalLight,

    //point_light: PointLight,

    
    // Camera/view position for specular
    camera_position: [3]f32,
    _: f32,
    
    // Ambient lighting
    ambient_color: [3]f32,
    _: f32,
    ambient_intensity: f32,
}






import "core:math"
import "core:math/rand"

clean_up :: proc(renderer: ^Renderer) {
    platform := cast(^MetalPlatform)renderer.platform

    platform.msaa_render_target_texture->release()
    platform.depth_texture->release()
    
    
    //renderPassDescriptor->release();
    

    platform.device->release()
}