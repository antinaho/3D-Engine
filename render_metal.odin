package main

import "base:runtime"
import "core:math/linalg"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import NS "core:sys/darwin/Foundation"

import "core:fmt"
import "core:os"
import stbi "vendor:stb/image"
import "core:log"

import "core:strings"
load_texture :: proc(renderer: ^Renderer, filepath: string) -> Texture {
    platform := cast(^MetalPlatform)renderer.platform

    texture: Texture
    w, h, c: i32

    pixels := stbi.load(strings.clone_to_cstring(filepath, context.temp_allocator), &w, &h, &c, 4)
    assert(pixels != nil, "Can't load")

    texture.desc.width = int(w)
    texture.desc.height = int(h)

    texture_descriptor := NS.new(MTL.TextureDescriptor)
    texture_descriptor->setPixelFormat(.RGBA8Unorm_sRGB)
    texture_descriptor->setWidth(NS.UInteger(w))
    texture_descriptor->setHeight(NS.UInteger(h))

    tex := platform.device->newTextureWithDescriptor(texture_descriptor)

    region := MTL.Region{origin={0,0,0}, size={NS.Integer(w), NS.Integer(h), 1}}
    bytes_per_row := 4 * w

    tex->replaceRegion(region, 0, pixels, NS.UInteger(bytes_per_row))
    texture.handle = tex

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

    //platform.msaa_render_target_texture->release()
    //platform.depth_texture->release()
    //platform.renderPassDescriptor->release()
    platform.swapchain->release()

    

    //grass_tex.mtl_tex->release()

    platform.device->release()

    free(platform)
    free(renderer)
}

MetalPlatform :: struct {
    device: ^MTL.Device,
    swapchain: ^CA.MetalLayer,
    command_queue: ^MTL.CommandQueue,
    metalDrawable: ^CA.MetalDrawable,

    encoder: ^MTL.RenderCommandEncoder,
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

    platform.command_queue = platform.device->newCommandQueue()

    renderer.api = MetalAPI
    
    platform.metalDrawable = platform.swapchain->nextDrawable()

    g_metal_device = platform.device
    drawable = platform.metalDrawable

    return renderer
}

drawable: ^CA.MetalDrawable
lighting_buffer :^MTL.Buffer
create_depth_and_msaa_textures :: proc(platform: ^MetalPlatform) {
    // msaa_texture_descriptor := NS.new(MTL.TextureDescriptor)
    // msaa_texture_descriptor->setTextureType(.Type2DMultisample)
    // msaa_texture_descriptor->setPixelFormat(.BGRA8Unorm)
    // msaa_texture_descriptor->setWidth(NS.UInteger(platform.swapchain->frame().width))
    // msaa_texture_descriptor->setHeight(NS.UInteger(platform.swapchain->frame().height))
    // msaa_texture_descriptor->setSampleCount(4)
    // msaa_texture_descriptor->setUsage({.RenderTarget})
    // defer msaa_texture_descriptor->release()

    // platform.msaa_render_target_texture = platform.device->newTexture(msaa_texture_descriptor);

    // depth_texture_descriptor := NS.new(MTL.TextureDescriptor)
    // depth_texture_descriptor->setTextureType(.Type2DMultisample)
    // depth_texture_descriptor->setPixelFormat(.Depth32Float)
    // depth_texture_descriptor->setWidth(NS.UInteger(platform.swapchain->frame().width))
    // depth_texture_descriptor->setHeight(NS.UInteger(platform.swapchain->frame().height))
    // depth_texture_descriptor->setSampleCount(4)
    // depth_texture_descriptor->setUsage({.RenderTarget})
    // defer depth_texture_descriptor->release()

    // platform.depth_texture = platform.device->newTexture(depth_texture_descriptor);
}

CUBE_INDICES :: []u32 {
    // Front
    0, 1, 2,  2, 3, 0,
    // Back
    4, 5, 6,  6, 7, 4,
    // Right
    8, 9, 10,  10, 11, 8,
    // Left
    12, 13, 14,  14, 15, 12,
    // Top
    16, 17, 18,  18, 19, 16,
    // Bottom
    20, 21, 22,  22, 23, 20,

}

CUBE_VERTICES :: []Vertex {
     // Front face (Z+)
    {position={-0.5, -0.5,  0.5}, normal={ 0,  0,  1}, color={1, 1, 1, 1}, uvs={0.0, 0.0},},  // 0
    {position={ 0.5, -0.5,  0.5}, normal={ 0,  0,  1}, color={1, 1, 1, 1}, uvs={1.0, 0.0},},  // 1
    {position={ 0.5,  0.5,  0.5}, normal={ 0,  0,  1}, color={1, 1, 1, 1}, uvs={1.0, 1.0},},  // 2
    {position={-0.5,  0.5,  0.5}, normal={ 0,  0,  1}, color={1, 1, 1, 1}, uvs={0.0, 1.0},},  // 3
    
    // Back face (Z-)
    {position={ 0.5, -0.5, -0.5}, normal={ 0,  0, -1}, color={1, 1, 1, 1}, uvs={0.0, 0.0}, },  // 4
    {position={-0.5, -0.5, -0.5}, normal={ 0,  0, -1}, color={1, 1, 1, 1}, uvs={1.0, 0.0}, },  // 5
    {position={-0.5,  0.5, -0.5}, normal={ 0,  0, -1}, color={1, 1, 1, 1}, uvs={1.0, 1.0}, },  // 6
    {position={ 0.5,  0.5, -0.5}, normal={ 0,  0, -1}, color={1, 1, 1, 1}, uvs={0.0, 1.0}, },  // 7
    
    // Right face (X+)
    {position={ 0.5, -0.5,  0.5}, normal={ 1,  0,  0}, color={1, 1, 1, 1}, uvs={0.0, 0.0}, },  // 8
    {position={ 0.5, -0.5, -0.5}, normal={ 1,  0,  0}, color={1, 1, 1, 1}, uvs={1.0, 0.0}, },  // 9
    {position={ 0.5,  0.5, -0.5}, normal={ 1,  0,  0}, color={1, 1, 1, 1}, uvs={1.0, 1.0}, },  // 10
    {position={ 0.5,  0.5,  0.5}, normal={ 1,  0,  0}, color={1, 1, 1, 1}, uvs={0.0, 1.0}, },  // 11
    
    // Left face (X-)
    {position={-0.5, -0.5, -0.5}, normal={-1,  0,  0}, color={1, 1, 1, 1}, uvs={0.0, 0.0}, },  // 12
    {position={-0.5, -0.5,  0.5}, normal={-1,  0,  0}, color={1, 1, 1, 1}, uvs={1.0, 0.0}, },  // 13
    {position={-0.5,  0.5,  0.5}, normal={-1,  0,  0}, color={1, 1, 1, 1}, uvs={1.0, 1.0}, },  // 14
    {position={-0.5,  0.5, -0.5}, normal={-1,  0,  0}, color={1, 1, 1, 1}, uvs={0.0, 1.0}, },  // 15
    
    // Top face (Y+)
    {position={-0.5,  0.5,  0.5}, normal={ 0,  1,  0}, color={1, 1, 1, 1}, uvs={0.0, 0.0}, },  // 16
    {position={ 0.5,  0.5,  0.5}, normal={ 0,  1,  0}, color={1, 1, 1, 1}, uvs={1.0, 0.0}, },  // 17
    {position={ 0.5,  0.5, -0.5}, normal={ 0,  1,  0}, color={1, 1, 1, 1}, uvs={1.0, 1.0}, },  // 18
    {position={-0.5,  0.5, -0.5}, normal={ 0,  1,  0}, color={1, 1, 1, 1}, uvs={0.0, 1.0}, },  // 19
    
    // Bottom face (Y-)
    {position={-0.5, -0.5, -0.5}, normal={ 0, -1,  0}, color= {1, 1, 1, 1}, uvs={0.0, 0.0}, },  // 20
    {position={ 0.5, -0.5, -0.5}, normal={ 0, -1,  0}, color= {1, 1, 1, 1}, uvs={1.0, 0.0}, },  // 21
    {position={ 0.5, -0.5,  0.5}, normal={ 0, -1,  0}, color= {1, 1, 1, 1}, uvs={1.0, 1.0}, },  // 22
    {position={-0.5, -0.5,  0.5}, normal={ 0, -1,  0}, color= {1, 1, 1, 1}, uvs={0.0, 1.0}, },  // 23
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

update_render_pass_descriptor :: proc(desc: Update_Renderpass_Desc, platform: ^MetalPlatform) {
    pass_desc := cast(^MTL.RenderPassDescriptor)desc.renderpass_descriptor

    pass_desc->colorAttachments()->object(0)->setTexture(cast(^MTL.Texture)desc.msaa_texture.handle);
    pass_desc->colorAttachments()->object(0)->setResolveTexture(drawable->texture());
    pass_desc->depthAttachment()->setTexture(cast(^MTL.Texture)desc.depth_texture.handle);
    
}

g_metal_device: ^MTL.Device

metal_draw :: proc(window: ^Window, renderer: ^Renderer) {
    NS.scoped_autoreleasepool()

    platform := cast(^MetalPlatform)renderer.platform
    
    if !window.is_visible || window.is_minimized {
        return
    }

    platform.metalDrawable = platform.swapchain->nextDrawable()
    if platform.metalDrawable == nil {
        log.warn("Warning: No drawable, skipping frame")
        return
    }

    dtex := platform.metalDrawable->texture()
    if dtex == nil {
        log.warn("Warning: Drawable texture is nil, skipping frame")
        return
    }

    execute_commands(platform, &cmd_buffer)
    
    

    //update_render_pass_descriptor(platform)

    // // View
    // R := linalg.Vector3f32{1,0,0} // Unit right
    // U := linalg.Vector3f32{0, 1, 0} // Unit up
    // F := linalg.Vector3f32{0, 0, -1} // Unit right
    // P := camera.position // Camera world space position
    // view_matrix := linalg.Matrix4x4f32 {
    //     R.x, R.y, R.z, linalg.dot(-R, P),
    //     U.x, U.y, U.z, linalg.dot(-U, P),
    //     -F.x, -F.y, -F.z, linalg.dot(F, P),
    //     0,0,0,1
    // }

    // // Projection
    // aspect_ratio := platform.swapchain->frame().width / platform.swapchain->frame().height
    // fov := camera.FOV * (math.PI / 180.0)
    // projection_matrix := matrix_perspective_right_hand(camera.near_clip, camera.far_clip, f32(aspect_ratio), fov)

    // lighting := LightingData{
    //     directional_light = DirectionalLight{
    //         direction = linalg.normalize([3]f32{0.3, -1, -0.5}),
    //         color = {1.0, 0.95, 0.8},  // Slight warm sun
    //         intensity = 1.2,
    //     },

    //     camera_position = camera.position,
    //     ambient_color = {0.4, 0.5, 0.6},  // Slight blue ambient
    //     ambient_intensity = 0.25,
    // }

    // lighting.point_lights[0] = PointLight{
    //         position = {
    //             1.25,                           // X: static
    //             0.2,                           // Y: static  
    //             -3 + math.sin(runtime_app) * 4,    // Z: oscillates between -7 and -3
    //         },
    //         color = {0, 1, 0},  
    //         intensity = 3.0,
    //         constant = 1.0,
    //         linear = 0.09,
    //         quadratic = 0.032,
    //         radius = 5.0,
    //     }

    // lighting.point_lights[1] = PointLight{
    //         position = {
    //             -1.25,                           // X: static
    //             0.2,                           // Y: static  
    //             -3 - math.sin(runtime_app) * 4,    // Z: oscillates between -7 and -3
    //         },
    //         color = {0, 0, 1},  
    //         intensity = 3.0,
    //         constant = 1.0,
    //         linear = 0.09,
    //         quadratic = 0.032,
    //         radius = 5.0,
    //     }
    
    // contents := lighting_buffer->contentsAsSlice([]LightingData)[:1]
    // contents[0] = lighting

    // render_encoder->setFragmentBuffer(lighting_buffer, 0, 1)

    // for &model in models {
    //     model_matrix := 
    //     linalg.matrix4_translate_f32(model.position) *
    //     linalg.matrix4_rotate_f32(model.rotation_angle, model.rotation_axis) *
    //     linalg.matrix4_scale_f32(model.scale)
                
    //     ubo := Uniforms {
    //         model_matrix = model_matrix,
    //         view_matrix = view_matrix,
    //         projection_matrix = projection_matrix,
    //         light_position = {0,0,0,0},
    //         light_direction = {0,0,0,0},
    //         time_data = {runtime_app, delta, 0, 0},
    //         mat = {model.material.offset.x, model.material.offset.y, model.material.scale.x, model.material.scale.y},
    //     }

    //     uniform_bytes := mem.ptr_to_bytes(&ubo)
        
    //     render_encoder->setVertexBytes(uniform_bytes, 1)
    //     render_encoder->setVertexBuffer(model.mesh.vertex_buffer, 0, 0)
    //     render_encoder->setFragmentBytes(uniform_bytes, 0)
    //     render_encoder->setFragmentTexture(grass_tex.mtl_tex, 0)

    //     render_encoder->setFragmentSamplerState(platform.texture_sampler, 0)

    //     //render_encoder->drawPrimitives(.Triangle, 0, NS.UInteger(model.mesh.vertex_count))
    //     render_encoder->drawIndexedPrimitives(.Triangle, NS.UInteger(model.mesh.index_count), .UInt32, model.mesh.index_buffer, 0)
    // }

    //render_encoder->setCullMode(.None);
    // ui_begin()
    // ui_add_rect({20, 50, 300, 300},  {0.5, 0.5, 0.5, 1} )
    // ui_end(window, platform.device, render_encoder)
    
    
  
}

import "core:mem"

Uniforms :: struct #align(16) {
    projection_matrix: linalg.Matrix4x4f32,
    view_matrix: linalg.Matrix4x4f32,
    model_matrix: linalg.Matrix4x4f32,
    
    light_position: [4]f32,
    light_direction: [4]f32,
    time_data: [4]f32,

    mat: [4]f32,
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

    //platform.msaa_render_target_texture->release()
    //platform.depth_texture->release()
    
   
    //renderPassDescriptor->release();
    
    platform.device->release()
}

///////////////////////////////////////////////////////////////////////////////

MACOS :: #config(MACOS, true) 

metal_init_buffer :: proc(
    size: int,
    usage: Buffer_Usage,
    access: Buffer_Access,
) -> Buffer {
    assert(g_metal_device != nil, "Metal device not initialized")
    
    storage_mode: MTL.ResourceOptions
    switch access {
    case .Static:
        storage_mode = MTL.ResourceStorageModePrivate // GPU only
    case .Dynamic:
        storage_mode = MTL.ResourceStorageModeShared
    case .Staging:
        storage_mode = MTL.ResourceStorageModeShared
    }
    
    // Create Metal buffer
    metal_buffer := g_metal_device->newBuffer(
        NS.UInteger(size),
        storage_mode,
    )
    
    if metal_buffer == nil {
        log.panicf("Failed to create Metal buffer of size: %v", size)
    }
    
    // Set debug label
    label: string
    switch usage {
    case .Vertex:  label = "Vertex Buffer"
    case .Index:   label = "Index Buffer"
    case .Uniform: label = "Uniform Buffer"
    case .Storage: label = "Storage Buffer"
    }
    metal_buffer->setLabel(NS.alloc(NS.String)->initWithOdinString(label))
    
    return Buffer{
        handle = metal_buffer,
        size   = size,
        usage  = usage,
        access = access,
    }
}

metal_fill_buffer :: proc(buffer: ^Buffer, data: rawptr, size: int, offset: int) {
    metal_buffer := cast(^MTL.Buffer)buffer.handle
    assert(metal_buffer != nil, "Invalid Metal buffer")
    
    contents := metal_buffer->contents()
    
    // Copy data with offset
    dest := mem.ptr_offset(raw_data(contents), offset)
    mem.copy(dest, data, size)
    
    // Synchronize if needed (for Managed storage mode)
    when MACOS {
        // On macOS, Shared buffers need manual sync
        if buffer.access == .Dynamic {
            metal_buffer->didModifyRange(NS.Range{
                location = NS.UInteger(offset),
                length   = NS.UInteger(size),
            })
        }
    }
}

metal_release_buffer :: proc(buffer: ^Buffer) {
    if buffer.handle == nil do return
    
    metal_buffer := cast(^MTL.Buffer)buffer.handle
    metal_buffer->release()
}

///////////////////////////////////////////////////////////////////////////////

metal_create_sampler :: proc(desc: Sampler_Desc) -> Sampler {
    sampler_desc := MTL.SamplerDescriptor.alloc()->init()
    defer sampler_desc->release()
    
    // Filters
    sampler_desc->setMinFilter(desc.min_filter == .Linear ? .Linear : .Nearest)
    sampler_desc->setMagFilter(desc.mag_filter == .Linear ? .Linear : .Nearest)
    sampler_desc->setMipFilter(desc.mip_filter == .Linear ? .Linear : .Nearest)
    
    // Address modes
    sampler_desc->setSAddressMode(metal_address_mode(desc.address_mode_u))
    sampler_desc->setTAddressMode(metal_address_mode(desc.address_mode_v))
    sampler_desc->setRAddressMode(metal_address_mode(desc.address_mode_w))
    
    // Anisotropy
    if desc.max_anisotropy > 1 {
        sampler_desc->setMaxAnisotropy(NS.UInteger(desc.max_anisotropy))
    }
    
    metal_sampler := g_metal_device->newSamplerState(sampler_desc)
    
    return Sampler{handle = metal_sampler}
}

metal_address_mode :: proc(mode: Sampler_Address_Mode) -> MTL.SamplerAddressMode {
    switch mode {
    case .Repeat:       return .Repeat
    case .MirrorRepeat: return .MirrorRepeat
    case .ClampToEdge:  return .ClampToEdge
    case .ClampToBorder: return .ClampToBorderColor
    }
    return .Repeat
}

metal_destroy_sampler :: proc(sampler: ^Sampler) {
    if sampler.handle == nil do return
    metal_sampler := cast(^MTL.SamplerState)sampler.handle
    metal_sampler->release()
    sampler.handle = nil
}

////////////////////////////////

library: ^MTL.Library

metal_compile_shader :: proc(desc: Shader_Desc) -> (Shader, bool) {
    assert(g_metal_device != nil)
    
    // For Metal, we need .metal source or precompiled .metallib
    if desc.source_type != .MSL {
        log.panic("Metal backend requires MSL shaders")
    }
    
    // Compile at runtime

    if library == nil {
        log.info("LOADING SHADER LIB")
        library_desc := NS.new(MTL.CompileOptions)
        source := NS.String.alloc()->initWithOdinString(desc.source)
        defer source->release()
        
        err: ^NS.Error
        library, err = g_metal_device->newLibraryWithSource(
            source,
            library_desc,
        )

        if err != nil {
            log.panicf("Shader compilation error: %v", err->localizedDescription()->odinString())
        }
    }


    function_name := NS.String.alloc()->initWithOdinString(desc.entry_point)
    function := library->newFunctionWithName(function_name)
    if function == nil {
        log.panicf("Shader entry point not found: %v", desc.entry_point)
    }
    
    return Shader{
        handle = function,
        stage = desc.stage,
    }, true
}

///////////////////////////////////////////////

metal_create_pipeline :: proc(desc: Pipeline_Desc) -> Pipeline {
    log.infof("Creating pipeline: %s", fmt.tprintf(desc.label))
    assert(g_metal_device != nil)
    
    render_pipeline_desc := MTL.RenderPipelineDescriptor.alloc()->init()
    pipeline_label := NS.String.alloc()->initWithOdinString(desc.label)
    render_pipeline_desc->setLabel(pipeline_label)
    
    // Shaders
    vertex_shader := cast(^MTL.Function)desc.vertex_shader.handle
    fragment_shader := cast(^MTL.Function)desc.fragment_shader.handle

    assert(vertex_shader != nil, "Vertex shader is nil")
    assert(fragment_shader != nil, "Fragment shader is nil")
    
    render_pipeline_desc->setVertexFunction(vertex_shader)
    render_pipeline_desc->setFragmentFunction(fragment_shader)
    
    log.info("✓ Shaders set")

    // Vertex descriptor
    if len(desc.vertex_attributes) > 0 {
        vertex_desc := MTL.VertexDescriptor.alloc()->init()
        
        for attr, i in desc.vertex_attributes {
            mtl_attr := vertex_desc->attributes()->object(NS.UInteger(i))
            mtl_attr->setFormat(metal_vertex_format(attr.format))
            mtl_attr->setOffset(NS.UInteger(attr.offset))
            mtl_attr->setBufferIndex(NS.UInteger(attr.binding))

            log.infof("  Attribute %d: format=%v, offset=%d, binding=%d", i, attr.format, attr.offset, attr.binding)

        }
        
        for layout, i in desc.vertex_layouts {
            mtl_layout := vertex_desc->layouts()->object(NS.UInteger(i))
            mtl_layout->setStride(NS.UInteger(layout.stride))
            mtl_layout->setStepFunction(
                layout.step_rate == .PerVertex ? .PerVertex : .PerInstance
            )

            log.infof("  Layout %d: stride=%d, step_rate=%v", i, layout.stride, layout.step_rate)
        }
        
        render_pipeline_desc->setVertexDescriptor(vertex_desc)
        log.info("✓ Vertex descriptor set")
    }

    assert(len(desc.color_formats) > 0, "No color formats specified")
    
    // Color attachments
    for format, i in desc.color_formats {
        color_attachment := render_pipeline_desc->colorAttachments()->object(NS.UInteger(i))
        color_attachment->setPixelFormat(metal_pixel_format(format))
        
        // TODO color blend options
        // if i < len(desc.blend_states) {
        //     blend := desc.blend_states[i]
        //     color_attachment->setBlendingEnabled(blend.enabled)
            
        //     if blend.enabled {
        //         color_attachment->setSourceRGBBlendFactor(metal_blend_factor(blend.src_color))
        //         color_attachment->setDestinationRGBBlendFactor(metal_blend_factor(blend.dst_color))
        //         color_attachment->setRgbBlendOperation(metal_blend_op(blend.color_op))
                
        //         color_attachment->setSourceAlphaBlendFactor(metal_blend_factor(blend.src_alpha))
        //         color_attachment->setDestinationAlphaBlendFactor(metal_blend_factor(blend.dst_alpha))
        //         color_attachment->setAlphaBlendOperation(metal_blend_op(blend.alpha_op))
        //     }
        // }
    }
    log.info("✓ Color attachments set")

    render_pipeline_desc->setSampleCount(NS.UInteger(desc.sample_count))
    render_pipeline_desc->setTessellationOutputWindingOrder(.Clockwise)

    // Depth attachment
    if desc.depth_format != .RGBA8_UNorm {  // Has depth
        render_pipeline_desc->setDepthAttachmentPixelFormat(metal_pixel_format(desc.depth_format))
    }
        
    // Create pipeline state
    pipeline_state, err := g_metal_device->newRenderPipelineState(render_pipeline_desc)
    
    if err != nil {
        log.panicf("Failed to create Metal pipeline:", fmt.tprintf(err->localizedDescription()->odinString()))
    }

    log.info("✓ Pipeline created successfully")
    // Depth state (separate object in Metal)
    depth_state: ^MTL.DepthStencilState
    if desc.depth_state.test_enabled {
        depth_desc := MTL.DepthStencilDescriptor.alloc()->init()
        depth_desc->setDepthCompareFunction(metal_compare_op(desc.depth_state.compare_op))
        depth_desc->setDepthWriteEnabled(desc.depth_state.write_enabled)
        depth_state = g_metal_device->newDepthStencilState(depth_desc)
    }
    
    // Store both in handle (need custom struct)
    metal_pipeline := new(Metal_Pipeline)
    metal_pipeline.render_state = pipeline_state
    metal_pipeline.depth_state = depth_state
    
    return Pipeline{
        handle = metal_pipeline,
        desc = desc,
    }
}

Metal_Pipeline :: struct {
    render_state: ^MTL.RenderPipelineState,
    depth_state: ^MTL.DepthStencilState,
}

metal_destroy_pipeline :: proc(pipeline: ^Pipeline) {
    metal_pipeline := cast(^Metal_Pipeline)pipeline.handle
    metal_pipeline.render_state->release()
    if metal_pipeline.depth_state != nil {
        metal_pipeline.depth_state->release()
    }
    free(metal_pipeline)
}

metal_vertex_format :: proc(format: Vertex_Format) -> MTL.VertexFormat {
    switch format {
    case .Float:  return .Float
    case .Float2: return .Float2
    case .Float3: return .Float3
    case .Float4: return .Float4
    case .UInt:   return .UInt
    case .UInt2:  return .UInt2
    case .UInt3:  return .UInt3
    case .UInt4:  return .UInt4
    }
    return .Invalid
}

metal_pixel_format :: proc(format: Pixel_Format) -> MTL.PixelFormat {
    switch format {
    case .RGBA8_UNorm:       return .RGBA8Unorm
    case .RGBA8_UNorm_sRGB:  return .RGBA8Unorm_sRGB
    case .BGRA8_UNorm:       return .BGRA8Unorm
    case .BGRA8_UNorm_sRGB:  return .BGRA8Unorm_sRGB
    case .RGBA16_Float:      return .RGBA16Float
    case .RGBA32_Float:      return .RGBA32Float
    case .Depth32_Float:     return .Depth32Float
    case .Depth24_Stencil8:  return .Depth24Unorm_Stencil8
    }
    return .Invalid
}

metal_blend_factor :: proc(factor: Blend_Factor) -> MTL.BlendFactor {
    switch factor {
    case .Zero:              return .Zero
    case .One:               return .One
    case .SrcColor:          return .SourceColor
    case .OneMinusSrcColor:  return .OneMinusSourceColor
    case .SrcAlpha:          return .SourceAlpha
    case .OneMinusSrcAlpha:  return .OneMinusSourceAlpha
    case .DstColor:          return .DestinationColor
    case .OneMinusDstColor:  return .OneMinusDestinationColor
    case .DstAlpha:          return .DestinationAlpha
    case .OneMinusDstAlpha:  return .OneMinusDestinationAlpha
    }
    return .Zero
}

metal_blend_op :: proc(op: Blend_Op) -> MTL.BlendOperation {
    switch op {
    case .Add:             return .Add
    case .Subtract:        return .Subtract
    case .ReverseSubtract: return .ReverseSubtract
    case .Min:             return .Min
    case .Max:             return .Max
    }
    return .Add
}

metal_cull_mode :: proc(mode: Cull_Mode) -> MTL.CullMode {
    switch mode {
    case .None:  return .None
    case .Front: return .Front
    case .Back:  return .Back
    }
    return .None
}

metal_compare_op :: proc(op: Compare_Op) -> MTL.CompareFunction {
    switch op {
    case .Never:          return .Never
    case .Less:           return .Less
    case .Equal:          return .Equal
    case .LessOrEqual:    return .LessEqual
    case .Greater:        return .Greater
    case .NotEqual:       return .NotEqual
    case .GreaterOrEqual: return .GreaterEqual
    case .Always:         return .Always
    }
    return .Always
}

//////////////////////////////////////////

metal_create_texture :: proc(desc: Texture_Desc) -> Texture {
    assert(g_metal_device != nil)
    
    texture_desc := MTL.TextureDescriptor.alloc()->init()
    defer texture_desc->release()
    
    // Type
    switch desc.type {
    case .Texture2D:
        texture_desc->setTextureType(.Type2D)
    case .TextureCube:
        texture_desc->setTextureType(.TypeCube)
    case .Texture3D:
        texture_desc->setTextureType(.Type3D)
    case .Texture2DMultisample:
        texture_desc->setTextureType(.Type2DMultisample)
    }
    
    // Dimensions
    texture_desc->setWidth(NS.UInteger(desc.width))
    texture_desc->setHeight(NS.UInteger(desc.height))
    texture_desc->setDepth(NS.UInteger(max(desc.depth, 1)))
    
    // Format
    texture_desc->setPixelFormat(metal_pixel_format(desc.format))
    
    // Sample count (MSAA)
    texture_desc->setSampleCount(NS.UInteger(desc.sample_count))
    
    // Mip levels
    //texture_desc->setMipmapLevelCount(NS.UInteger(max(desc.mip_levels, 1)))
    
    // Usage
    usage_flags: MTL.TextureUsage
    switch desc.usage {
    case .RenderTarget:
        usage_flags = {.RenderTarget}
    case .Depth:
        usage_flags = {.RenderTarget}
    case .ShaderRead:
        usage_flags = {.ShaderRead}
    case .ShaderWrite:
        usage_flags = {.ShaderRead, .ShaderWrite}
    }
    texture_desc->setUsage(usage_flags)

    metal_texture := g_metal_device->newTexture(texture_desc)
    
    if metal_texture == nil {
        log.panic("Failed to create texture")
    }
    
    return Texture{
        handle = metal_texture,
        desc = desc,
    }
}

get_drawable :: proc() -> rawptr {
    return drawable
}


metal_destroy_texture :: proc(texture: ^Texture) {
    if texture.handle == nil do return
    metal_texture := cast(^MTL.Texture)texture.handle
    metal_texture->release()
    texture.handle = nil
}

////////////////////////////////////////////////////////////////

// command_executor_metal.odin

Metal_Command_Executor :: struct {
    device: ^MTL.Device,
    command_queue: ^MTL.CommandQueue,
    current_encoder: ^MTL.RenderCommandEncoder,
    
    // Cached state
    current_pipeline: ^MTL.RenderPipelineState,
}

execute_commands :: proc(
    platform: ^MetalPlatform,
    cb: ^Command_Buffer,
) {
    command_buffer := platform.command_queue->commandBuffer()
    assert(command_buffer != nil, "Failed to create command buffer")

    for cmd in cb.commands {
        switch c in cmd {
        case Update_Renderpass_Desc:
            update_render_pass_descriptor(c, platform)

        case Begin_Pass_Command:
            execute_begin_pass(&platform.encoder, command_buffer, c)
            
        case End_Pass_Command:
            execute_end_pass(platform.encoder)

        case Set_Pipeline_Command:
            execute_set_pipeline(platform.encoder, c)
            
        case Set_Viewport_Command:
            execute_set_viewport(platform.encoder, c)
            
        case Bind_Vertex_Buffer_Command:
            execute_bind_vertex_buffer(platform.encoder, c)
            
        case Bind_Index_Buffer_Command:
            execute_bind_index_buffer(nil, c)
            
        case Bind_Texture_Command:
            execute_bind_texture(platform.encoder, c)
            
        case Set_Uniform_Command:
            execute_set_uniform(platform.encoder, c)
            
        case Draw_Command:
            execute_draw(platform.encoder, c)
            
        case Draw_Indexed_Command:
            //execute_draw_indexed(executor, c)
            
        case Set_Scissor_Command:
            //execute_set_scissor(executor, c)

        case Render_Pass_MSAA_Desc:
            metal_begin_msaa_pass(&platform.encoder, platform.device, command_buffer, c, platform.metalDrawable)

        case Draw_Mesh_Command:
            //execute_draw_mesh(executor, c)
        }
    }
    
    command_buffer->presentDrawable(platform.metalDrawable)
    command_buffer->commit()
}

execute_draw_mesh :: proc(executor: ^Metal_Command_Executor, cmd: Draw_Mesh_Command) {
    assert(executor.current_encoder != nil, "No active render pass")
    
    // Bind vertex buffer
    vb := cast(^MTL.Buffer)cmd.vertex_buffer.handle
    executor.current_encoder->setVertexBuffer(vb, 0, 0)
    
    // Set transform uniform (binding 1)
    m := cmd.transform
    tbytes := mem.ptr_to_bytes(&m)
    executor.current_encoder->setVertexBytes(
        tbytes,
        1,
    )
    
    // Bind textures
    if cmd.material.albedo_texture.handle != nil {
        albedo := cast(^MTL.Texture)cmd.material.albedo_texture.handle
        executor.current_encoder->setFragmentTexture(albedo, 0)
    }
    
    if cmd.material.normal_texture.handle != nil {
        normal := cast(^MTL.Texture)cmd.material.normal_texture.handle
        executor.current_encoder->setFragmentTexture(normal, 1)
    }
    
    if cmd.material.metallic_roughness_texture.handle != nil {
        mr := cast(^MTL.Texture)cmd.material.metallic_roughness_texture.handle
        executor.current_encoder->setFragmentTexture(mr, 2)
    }
    
    // Set material uniforms (binding 0)
    material_data := struct {
        albedo_color: [4]f32,
        metallic: f32,
        roughness: f32,
        _padding: [2]f32,
    }{
        albedo_color = cmd.material.albedo_color,
        metallic = cmd.material.metallic,
        roughness = cmd.material.roughness,
    }
    
    fbytes := mem.ptr_to_bytes(&material_data)
    executor.current_encoder->setFragmentBytes(
        fbytes,
        0,
    )
    
    // Bind sampler
    if cmd.material.sampler.handle != nil {
        sampler := cast(^MTL.SamplerState)cmd.material.sampler.handle
        executor.current_encoder->setFragmentSamplerState(sampler, 0)
    }
    
    // Draw indexed
    ib := cast(^MTL.Buffer)cmd.index_buffer.handle
    executor.current_encoder->drawIndexedPrimitives(
        .Triangle,
        NS.UInteger(cmd.index_count),
        .UInt32,
        ib,
        0,
    )
}

Material :: struct {
    albedo_texture: Texture,
    normal_texture: Texture,
    metallic_roughness_texture: Texture,
    
    // PBR parameters
    albedo_color: [4]f32,
    metallic: f32,
    roughness: f32,
    
    // Optional
    sampler: Sampler,
}

Mesh :: struct {
    vertex_buffer: Buffer,
    index_buffer: Buffer,
    index_count: int,
}

metal_begin_msaa_pass :: proc(
    encoder: ^^MTL.RenderCommandEncoder,
    device: ^MTL.Device,
    cmd_buffer: ^MTL.CommandBuffer,
    desc: Render_Pass_MSAA_Desc,
    drawable: ^CA.MetalDrawable,
) {
    render_pass := MTL.RenderPassDescriptor.renderPassDescriptor()
    assert(render_pass != nil, "Failed to create render pass descriptor")
    
    // Color attachment (MSAA)
    color_attachment := render_pass->colorAttachments()->object(0)
    assert(color_attachment != nil, "Failed to get color attachment")
    drawable_texture := drawable->texture()
    assert(drawable_texture != nil, "Drawable has no texture")

    color_attachment->setTexture(drawable_texture)
    color_attachment->setLoadAction(.Clear)
    color_attachment->setClearColor(MTL.ClearColor{
        f64(desc.clear_color.r),
        f64(desc.clear_color.g),
        f64(desc.clear_color.b),
        f64(desc.clear_color.a),
    })
    color_attachment->setStoreAction(.Store)
    
    encoder^ = cmd_buffer->renderCommandEncoderWithDescriptor(render_pass)
    encoder^->setLabel(NS.AT("MSAA encoder"))

    // Resolve to drawable or provided texture
    if desc.resolve_texture.handle != nil {
        resolve_texture := cast(^MTL.Texture)desc.resolve_texture.handle
        color_attachment->setResolveTexture(resolve_texture)
    } else {
        color_attachment->setResolveTexture(drawable->texture())
    }
    msaa_texture := cast(^MTL.Texture)desc.msaa_texture.handle
    
    
    // Depth attachment
    depth_attachment := render_pass->depthAttachment()
    depth_texture := cast(^MTL.Texture)desc.depth_texture.handle
    depth_attachment->setTexture(depth_texture)
    depth_attachment->setLoadAction(.Clear)
    depth_attachment->setClearDepth(f64(desc.clear_depth))
    depth_attachment->setStoreAction(.DontCare)
    

    depth_desc := MTL.DepthStencilDescriptor.alloc()->init()
    depth_desc->setDepthCompareFunction(.Less)
    depth_desc->setDepthWriteEnabled(true)
    
    depth_state := device->newDepthStencilState(depth_desc)
    encoder^->setDepthStencilState(depth_state)
}

metal_create_renderpass_descriptor :: proc(desc: RenderPassDescriptor) -> rawptr {
    render_pass := MTL.RenderPassDescriptor.renderPassDescriptor()
    
    color_attachment := render_pass->colorAttachments()->object(0)
    
    // MSAA or direct rendering

    log.debug("***")
    log.debug(desc.msaa_texture.handle)

    d := cast(^CA.MetalDrawable)desc.drawable
    if desc.msaa_texture.handle != nil {
        log.debug("Set")
        msaa_tex := cast(^MTL.Texture)desc.msaa_texture.handle
        color_attachment->setTexture(msaa_tex)
        color_attachment->setResolveTexture(d->texture())
        color_attachment->setStoreAction(.StoreAndMultisampleResolve)
    } else {
        log.debug("Not set")
        color_attachment->setTexture(d->texture())
        color_attachment->setStoreAction(.Store)
    }
    
    color_attachment->setLoadAction(.Clear)
    
    color_attachment->setClearColor(MTL.ClearColor{
        f64(desc.clear_color.r),
        f64(desc.clear_color.g),
        f64(desc.clear_color.b),
        f64(desc.clear_color.a),
    })
    
    // Depth
    if desc.depth_texture.handle != nil {
        log.debug("Setting depth")
        depth_attachment := render_pass->depthAttachment()
        depth_tex := cast(^MTL.Texture)desc.depth_texture.handle
        depth_attachment->setTexture(depth_tex)
        depth_attachment->setLoadAction(.Clear)
        depth_attachment->setClearDepth(f64(desc.clear_depth))
        depth_attachment->setStoreAction(.DontCare)
    }

    return render_pass
}

@(private)
execute_begin_pass :: proc(
    encoder: ^^MTL.RenderCommandEncoder,
    command_buffer: ^MTL.CommandBuffer,
    cmd: Begin_Pass_Command,
) {
    encoder^ = command_buffer->renderCommandEncoderWithDescriptor(cast(^MTL.RenderPassDescriptor)cmd.renderpass_descriptor)
    
    label := NS.String.alloc()->initWithOdinString(cmd.name)
    encoder^->setLabel(label)
}

@(private)
execute_end_pass :: proc(encoder: ^MTL.RenderCommandEncoder) {
    encoder->endEncoding()
    //Maybe set platform.encoder to nil?
}

@(private)
execute_set_pipeline :: proc(encoder: ^MTL.RenderCommandEncoder, cmd: Set_Pipeline_Command) {
    metal_pipeline := cast(^Metal_Pipeline)cmd.pipeline.handle
    encoder->setRenderPipelineState(metal_pipeline.render_state)
    
    encoder->setCullMode(metal_cull_mode(cmd.pipeline.desc.cull_mode))
    encoder->setFrontFacingWinding(
        cmd.pipeline.desc.front_face == .Clockwise ? .Clockwise : .CounterClockwise
    )
    encoder->setTriangleFillMode(.Fill)
    
    if metal_pipeline.depth_state != nil {
        encoder->setDepthStencilState(metal_pipeline.depth_state)
    }
}

@(private)
execute_set_viewport :: proc(encoder: ^MTL.RenderCommandEncoder, cmd: Set_Viewport_Command) {
    encoder->setViewport(MTL.Viewport{
        originX = f64(cmd.x),
        originY = f64(cmd.y),
        width   = f64(cmd.width),
        height  = f64(cmd.height),
        znear   = 0,
        zfar    = 1,
    })
}

@(private)
execute_bind_vertex_buffer :: proc(encoder: ^MTL.RenderCommandEncoder, cmd: Bind_Vertex_Buffer_Command) {
    metal_buffer := cast(^MTL.Buffer)cmd.buffer.handle

    encoder->setVertexBuffer(
        metal_buffer,
        NS.UInteger(cmd.offset),
        NS.UInteger(cmd.binding),
    )
}

@(private)execute_bind_index_buffer :: proc(executor: ^Metal_Command_Executor, cmd: Bind_Index_Buffer_Command) {
    // Index buffer is bound in draw call in Metal
    // Store for later
}

@(private)
execute_bind_texture :: proc(encoder: ^MTL.RenderCommandEncoder, cmd: Bind_Texture_Command) {
    metal_texture := cast(^MTL.Texture)cmd.texture.handle
    
    switch cmd.stage {
    case .Vertex:
        encoder->setVertexTexture(metal_texture, NS.UInteger(cmd.slot))
    case .Fragment:
        encoder->setFragmentTexture(metal_texture, NS.UInteger(cmd.slot))
    case .Compute:
        // Not applicable for render encoder
    }
}

import "core:slice"

@(private)
execute_set_uniform :: proc(encoder: ^MTL.RenderCommandEncoder, cmd: Set_Uniform_Command) {
    switch cmd.stage {
    case .Vertex:
        b := slice.bytes_from_ptr(cmd.data, cmd.size)
        encoder->setVertexBytes(
            b,
            NS.UInteger(cmd.slot),
        )
    case .Fragment:
        b := slice.bytes_from_ptr(cmd.data, cmd.size)
        encoder->setFragmentBytes(
            b,
            NS.UInteger(cmd.slot),
        )
    case .Compute:
        // Not applicable
    }
    
    // Free the copied data
    free(cmd.data)
}

@(private)
execute_draw :: proc(encoder: ^MTL.RenderCommandEncoder, cmd: Draw_Command) {

    encoder->drawPrimitives(
        .Triangle,
        NS.UInteger(cmd.first_vertex),
        NS.UInteger(cmd.vertex_count),
    )
}

@(private)
execute_draw_indexed :: proc(executor: ^Metal_Command_Executor, cmd: Draw_Indexed_Command) {
    // Assumes index buffer was bound earlier
    executor.current_encoder->drawIndexedPrimitives(
        .Triangle,
        NS.UInteger(cmd.index_count),
        .UInt32,  // Assuming 32-bit indices
        nil,  // Index buffer (should be tracked from bind command)
        NS.UInteger(cmd.vertex_offset)
    )
}

@(private)
execute_set_scissor :: proc(executor: ^Metal_Command_Executor, cmd: Set_Scissor_Command) {
    executor.current_encoder->setScissorRect(MTL.ScissorRect{
        x = NS.Integer(cmd.x),
        y = NS.Integer(cmd.y),
        width = NS.Integer(cmd.width),
        height = NS.Integer(cmd.height),
    })
}