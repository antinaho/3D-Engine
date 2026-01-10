package main

import "core:c"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import NS "core:sys/darwin/Foundation"
import stbi "vendor:stb/image"

import "base:runtime"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:math/linalg"

render_state: ^MetalPlatform

MetalAPI :: RendererAPI {
    draw = _metal_draw,
    cleanup = _cleanup,
}

MetalPlatform :: struct {
    device: ^MTL.Device,
    swapchain: ^CA.MetalLayer,
    command_queue: ^MTL.CommandQueue,
    drawable: ^CA.MetalDrawable,
    render_pass_descriptor: ^MTL.RenderPassDescriptor,

    encoder: ^MTL.RenderCommandEncoder,
}

metal_init :: proc(application_window: ^ApplicationWindow) -> ^Renderer {
    renderer := new(Renderer, application_window.window_allocator)
    platform := new(MetalPlatform, application_window.window_allocator)

    renderer.platform = cast(_Platform)platform
    metalWindow := cast(^NS.Window)application_window.window.get_window_handle(application_window.window)
    platform.device = MTL.CreateSystemDefaultDevice()
    assert(platform.device != nil, "Metal not supported")

    platform.swapchain = CA.MetalLayer.layer()
    platform.swapchain->setDevice(platform.device)
    platform.swapchain->setPixelFormat(.BGRA8Unorm)
    platform.swapchain->setDrawableSize({NS.Float(application_window.width), NS.Float(application_window.height)})

    metalWindow->contentView()->setLayer(platform.swapchain)
    metalWindow->contentView()->setWantsLayer(true)

    platform.command_queue = platform.device->newCommandQueue()
    platform.drawable = platform.swapchain->nextDrawable()
    
    renderer.api = MetalAPI

    render_state = platform
    render_state.render_pass_descriptor = MTL.RenderPassDescriptor.alloc()->init()
    create_depth_and_msaa_textures(renderer)


    return renderer
}

create_depth_and_msaa_textures :: proc(renderer: ^Renderer) {
    renderer.msaa_texture = metal_create_texture({
        format = .RGBA8_UNorm,
        width = int(render_state.swapchain->drawableSize().width),
        height = int(render_state.swapchain->drawableSize().height),
        mip_levels = 1,
        storage = .Private,
        sample_count = samples,
        type = .Texture2DMultisample,
        usage = .RenderTarget,
    })

    renderer.depth_texture = metal_create_texture({
        format = .Depth32_Float,
        width = int(render_state.swapchain->drawableSize().width),
        height = int(render_state.swapchain->drawableSize().height),
        mip_levels = 1,
        storage = .Private,
        sample_count = samples,
        type = .Texture2DMultisample,
        usage = .Depth,
    })
}

samples := DEFAULT_MSAA_SAMPLE_COUNT

_cleanup :: proc(application_window: ^ApplicationWindow) {
    platform := cast(^MetalPlatform)application_window.renderer.platform

    platform.swapchain->release()
    platform.device->release()
}

resize_framebuffer :: proc(application_window: ^ApplicationWindow) {
    renderer := application_window.renderer
    render_state.swapchain->setDrawableSize({NS.Float(application_window.width), NS.Float(application_window.height)})
    
    msaa_tex := cast(^MTL.Texture)renderer.msaa_texture.handle
    if msaa_tex != nil {
        msaa_tex->release()
        msaa_tex = nil
    }

    depth_tex := cast(^MTL.Texture)renderer.depth_texture.handle
    if depth_tex != nil {
        depth_tex->release()
        depth_tex = nil
    }

    create_depth_and_msaa_textures(renderer)

    render_state.drawable = render_state.swapchain->nextDrawable()

    msaa := cast(^MTL.Texture)renderer.msaa_texture.handle
    msaa_width := msaa->width()
    msaa_height := msaa->height()
    msaa_samples := msaa->sampleCount()

    depth := cast(^MTL.Texture)renderer.depth_texture.handle
    depth_width := depth->width()
    depth_height := depth->height()
    depth_samples := depth->sampleCount()

    drawable_width := render_state.drawable->texture()->width()
    drawable_height := render_state.drawable->texture()->height()

    // Validate sizes match
    assert(msaa_width == depth_width, fmt.tprintf("MSAA and depth width mismatch: %v : %v", msaa_width, depth_width))
    assert(msaa_height == depth_height, fmt.tprintf("MSAA and depth height mismatch: %v : %v", msaa_height, depth_height))
    assert(msaa_width == drawable_width, fmt.tprintf("MSAA and drawable width mismatch: %v : %v", msaa_width, drawable_width))
    assert(msaa_height == drawable_height, fmt.tprintf("MSAA and drawable height mismatch: %v : %v", msaa_height, drawable_height))
    
    // Validate sample counts match
    assert(msaa_samples == depth_samples, fmt.tprintf("MSAA and depth sample count mismatch: %v : %v", msaa_samples, depth_samples))
    
    log.debugf("Resize validation passed: %dx%d @ %dx MSAA", msaa_width, msaa_height, msaa_samples)


}

_metal_draw :: proc(window: ^ApplicationWindow, command_buffer: ^CommandBuffer) {
    NS.scoped_autoreleasepool()

    renderer := window.renderer

    platform := cast(^MetalPlatform)renderer.platform
    
    if !window.is_visible || window.is_minimized {
        return
    }

    platform.drawable = platform.swapchain->nextDrawable()
    if platform.drawable == nil {
        log.warn("Warning: No drawable, skipping frame")
        return
    }

    if window.did_resize {
        resize_framebuffer(window)
        window.did_resize = false
        return
    }

    dtex := platform.drawable->texture()
    if dtex == nil {
        log.warn("Warning: Drawable texture is nil, skipping frame")
        return
    }

    execute_commands(command_buffer)  
}

//TODO move to other file(s)
DirectionalLight :: struct #align(16) {
    direction: [3]f32,  
    _: f32,

    color: [3]f32,      
    _: f32,

    intensity: f32, 
    _: [3]f32,
}

PointLight :: struct #align(16) {
    position: [3]f32,
    _: f32,
    color: [3]f32,
    _: f32,

    intensity: f32,
    constant: f32,  
    linear: f32,    
    quadratic: f32, 
    
    radius: f32, 
    _: [3]f32,
}

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

///////////////////////////////////////////////////////////////////////////////

MACOS :: #config(MACOS, true) 

metal_init_buffer :: proc(
    size: int,
    usage: BufferKind,
    access: BufferAccess,
) -> Buffer {
    assert(render_state.device != nil, "Metal device not initialized")
    
    storage_mode: MTL.ResourceOptions
    switch access {
    case .Static:
        storage_mode = {.StorageModePrivate}
    case .Dynamic:
        storage_mode = {.StorageModeManaged}
    }
    
    // Create Metal buffer
    metal_buffer := render_state.device->newBuffer(
        NS.UInteger(size),
        storage_mode,
    )
    assert(metal_buffer != nil, "Failed to create buffer")
    
    // Set debug label
    when ODIN_DEBUG {
        label: string
        switch usage {
        case .Vertex:  label = "Vertex Buffer"
        case .Index:   label = "Index Buffer"
        case .Uniform: label = "Uniform Buffer"
        }
        metal_buffer->setLabel(NS.alloc(NS.String)->initWithOdinString(label))
    }
    
    return Buffer{
        handle = metal_buffer,
        size   = size,
        usage  = usage,
        access = access,
    }
}

metal_fill_buffer :: proc(buffer: ^Buffer, data: rawptr, size: int, offset: int) {
    assert(buffer != nil, "Trying to fill null buffer.")

    metal_buffer := cast(^MTL.Buffer)buffer.handle
    assert(metal_buffer != nil, "Invalid Metal buffer")
    
    contents := metal_buffer->contents()
    dest := mem.ptr_offset(raw_data(contents), offset)
    mem.copy(dest, data, size)
    
    // On MacOS, Shared buffers need manual sync. Not in iOS
    when MACOS {
        if buffer.access == .Dynamic {
            metal_buffer->didModifyRange(NS.Range{
                location = NS.UInteger(offset),
                length   = NS.UInteger(size),
            })
        }
    }
}

metal_release_buffer :: proc(buffer: ^Buffer) {
    assert(buffer != nil, "Trying to release null buffer.")
    
    metal_buffer := cast(^MTL.Buffer)buffer.handle
    metal_buffer->release()
}

///////////////////////////////////////////////////////////////////////////////

metal_create_sampler :: proc(desc: TextureSamplerDesc) -> TextureSampler {
    metal_address_mode := [TextureSamplerAddressMode]MTL.SamplerAddressMode {
        .Repeat         = .Repeat,
        .MirrorRepeat   = .MirrorRepeat,
        .ClampToEdge    = .ClampToEdge,
        .ClampToBorder  = .ClampToBorderColor
    }

    sampler_desc := MTL.SamplerDescriptor.alloc()->init()
    defer sampler_desc->release()
    
    // Filters
    sampler_desc->setMinFilter(desc.min_filter == .Linear ? .Linear : .Nearest)
    sampler_desc->setMagFilter(desc.mag_filter == .Linear ? .Linear : .Nearest)
    sampler_desc->setMipFilter(desc.mip_filter == .Linear ? .Linear : .Nearest)
    
    // Address modes
    sampler_desc->setSAddressMode(metal_address_mode[desc.address_mode_u])
    sampler_desc->setTAddressMode(metal_address_mode[desc.address_mode_v])
    sampler_desc->setRAddressMode(metal_address_mode[desc.address_mode_w])
    
    // Anisotropy
    if desc.max_anisotropy > 1 {
        sampler_desc->setMaxAnisotropy(NS.UInteger(desc.max_anisotropy))
    }
    
    metal_sampler := render_state.device->newSamplerState(sampler_desc)
    
    return TextureSampler {
        handle = metal_sampler
    }
}

metal_destroy_sampler :: proc(sampler: ^TextureSampler) {
    assert(sampler.handle != nil, "Trying to destroy null sampler.")
    metal_sampler := cast(^MTL.SamplerState)sampler.handle
    metal_sampler->release()
    sampler.handle = nil
}

////////////////////////////////

metal_compile_shader :: proc(desc: ShaderDesc) -> (Shader, bool) {
    assert(render_state.device != nil)
    assert(desc.shader_language == .MSL, "Metal backend requires MSL shaders!")
    
    library_desc := NS.new(MTL.CompileOptions)
    defer library_desc->release()

    source := NS.String.alloc()->initWithOdinString(desc.source)
    defer source->release()
    
    library, err := render_state.device->newLibraryWithSource(
        source,
        library_desc,
    )

    if err != nil {
        log.panicf("Shader compilation error: %v", err->localizedDescription()->odinString())
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

metal_create_pipeline :: proc(desc: PipelineDesc) -> Pipeline {
    log.infof("Creating pipeline: %s", fmt.tprintf(desc.label))
    assert(render_state.device != nil, "Device not initialized")
    
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
    
    log.info("-- Shaders set --")

    // Vertex descriptor
    if len(desc.vertex_attributes) > 0 {
        vertex_desc := MTL.VertexDescriptor.alloc()->init()
        
        for attr, i in desc.vertex_attributes {
            mtl_attr := vertex_desc->attributes()->object(NS.UInteger(i))
            mtl_attr->setFormat(metal_vertex_format[attr.format])
            mtl_attr->setOffset(NS.UInteger(attr.offset))
            mtl_attr->setBufferIndex(NS.UInteger(attr.binding))

            log.infof("Attribute %d: format=%v, offset=%d, binding=%d", i, attr.format, attr.offset, attr.binding)
        }
        
        for layout, i in desc.vertex_layouts {
            mtl_layout := vertex_desc->layouts()->object(NS.UInteger(i))
            mtl_layout->setStride(NS.UInteger(layout.stride))
            mtl_layout->setStepFunction(
                layout.step_rate == .PerVertex ? .PerVertex : .PerInstance
            )

            log.infof("Layout %d: stride=%d, step_rate=%v", i, layout.stride, layout.step_rate)
        }
        
        render_pipeline_desc->setVertexDescriptor(vertex_desc)
        log.info("-- Vertex descriptor set --")
    }

    assert(len(desc.color_formats) > 0, "No color formats specified")
    
    color_attachment := render_pipeline_desc->colorAttachments()->object(0)
    color_attachment->setPixelFormat(render_state.swapchain->pixelFormat())

    // Color attachments
    for format, i in desc.color_formats { 
        if i < len(desc.blend_states) {
            blend := desc.blend_states[i]
            color_attachment->setBlendingEnabled(blend.enabled)
            
            if blend.enabled {
                color_attachment->setSourceRGBBlendFactor(metal_blend_factor[blend.src_color])
                color_attachment->setDestinationRGBBlendFactor(metal_blend_factor[blend.dst_color])
                color_attachment->setRgbBlendOperation(metal_blend_operation[blend.color_op])
                
                color_attachment->setSourceAlphaBlendFactor(metal_blend_factor[blend.src_alpha])
                color_attachment->setDestinationAlphaBlendFactor(metal_blend_factor[blend.dst_alpha])
                color_attachment->setAlphaBlendOperation(metal_blend_operation[blend.alpha_op])
            }
        }
    }
    log.info("-- Color attachments set --")

    render_pipeline_desc->setSampleCount(NS.UInteger(desc.sample_count))
    render_pipeline_desc->setTessellationOutputWindingOrder(.Clockwise)

    // Depth attachment
    if desc.depth_format != .RGBA8_UNorm { 
        render_pipeline_desc->setDepthAttachmentPixelFormat(metal_pixel_format[desc.depth_format])
    }
        
    // Create pipeline state
    pipeline_state, err := render_state.device->newRenderPipelineState(render_pipeline_desc)
    assert(pipeline_state != nil, fmt.tprintf("Failed to create Metal pipeline: %v", err->localizedDescription()->odinString()))

    log.info("-- Pipeline created successfully --")

    depth_state: ^MTL.DepthStencilState
    if desc.depth_state.test_enabled {
        depth_desc := MTL.DepthStencilDescriptor.alloc()->init()
        depth_desc->setDepthCompareFunction(metal_compare_operation[desc.depth_state.compare_op])
        depth_desc->setDepthWriteEnabled(desc.depth_state.write_enabled)
        depth_state = render_state.device->newDepthStencilState(depth_desc)
    }
    
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

metal_vertex_format := [VertexFormat]MTL.VertexFormat {
    .Float  = .Float,
    .Float2 = .Float2,
    .Float3 = .Float3,
    .Float4 = .Float4,
    .UInt   = .UInt,
    .UInt2  = .UInt2,
    .UInt3  = .UInt3,
    .UInt4  = .UInt4,
}

metal_pixel_format := [PixelFormat]MTL.PixelFormat {
    .RGBA8_UNorm      = .RGBA8Unorm,
    .RGBA8_UNorm_sRGB = .RGBA8Unorm_sRGB,
    .BGRA8_UNorm      = .BGRA8Unorm,
    .BGRA8_UNorm_sRGB = .BGRA8Unorm_sRGB,
    .RGBA16_Float     = .RGBA16Float,
    .RGBA32_Float     = .RGBA32Float,
    .Depth32_Float    = .Depth32Float,
    .Depth24_Stencil8 = .Depth24Unorm_Stencil8,
}

metal_blend_factor := [BlendFactor]MTL.BlendFactor {
    .Zero             = .Zero,
    .One              = .One,
    .SrcColor         = .SourceColor,
    .OneMinusSrcColor = .OneMinusSourceColor,
    .SrcAlpha         = .SourceAlpha,
    .OneMinusSrcAlpha = .OneMinusSourceAlpha,
    .DstColor         = .DestinationColor,
    .OneMinusDstColor = .OneMinusDestinationColor,
    .DstAlpha         = .DestinationAlpha,
    .OneMinusDstAlpha = .OneMinusDestinationAlpha,
}

metal_blend_operation := [BlendOperation]MTL.BlendOperation {
    .Add             = .Add,
    .Subtract        = .Subtract,
    .ReverseSubtract = .ReverseSubtract,
    .Min             = .Min,
    .Max             = .Max,
}

metal_cull_mode := [CullMode]MTL.CullMode {
    .None  = .None,
    .Front = .Front,
    .Back  = .Back,
}

metal_compare_operation := [CompareOperation]MTL.CompareFunction {
    .Never          = .Never,
    .Less           = .Less,
    .Equal          = .Equal,
    .LessOrEqual    = .LessEqual,
    .Greater        = .Greater,
    .NotEqual       = .NotEqual,
    .GreaterOrEqual = .GreaterEqual,
    .Always         = .Always,
}

//////////////////////////////////////////

metal_create_texture :: proc(desc: TextureDesc) -> Texture {
    assert(render_state.device != nil, "Device not initialized")
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
    
    // Format
    texture_desc->setPixelFormat(metal_pixel_format[desc.format])
    

    texture_desc->setWidth(NS.UInteger(desc.width))
    texture_desc->setHeight(NS.UInteger(desc.height))
        
    // Sample count (MSAA)
    texture_desc->setSampleCount(NS.UInteger(desc.sample_count))
    
    // Mip levels
    texture_desc->setMipmapLevelCount(NS.UInteger(max(desc.mip_levels, 1)))
    
    // Storage
    texture_desc->setStorageMode(metal_storage_modes[desc.storage])

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

    metal_texture := render_state.device->newTexture(texture_desc)
    
    if metal_texture == nil {
        log.panic("Failed to create texture")
    }
    
    return Texture{
        handle = metal_texture,
        desc = desc,
    }
}

metal_storage_modes := [TextureStorage]MTL.StorageMode {
    .Private = .Private
}

metal_load_texture :: proc(desc: TextureLoadDesc) -> (texture: Texture) {
    w, h, c: i32

    pixels := stbi.load(strings.clone_to_cstring(desc.filepath, context.temp_allocator), &w, &h, &c, 4)
    assert(pixels != nil, fmt.tprintf("Can't load texture from: %v", desc.filepath))
    defer stbi.image_free(pixels)

    texture.desc.width = int(w)
    texture.desc.height = int(h)

    texture_descriptor := NS.new(MTL.TextureDescriptor)
    defer texture_descriptor->release()
    texture_descriptor->setPixelFormat(metal_pixel_format[desc.format])
    texture_descriptor->setWidth(NS.UInteger(w))
    texture_descriptor->setHeight(NS.UInteger(h))
    
    tex := render_state.device->newTextureWithDescriptor(texture_descriptor)
    region := MTL.Region{origin={0,0,0}, size={NS.Integer(w), NS.Integer(h), 1}}
    bytes_per_row := 4 * w

    tex->replaceRegion(region, 0, pixels, NS.UInteger(bytes_per_row))
    texture.handle = tex

    return
}

metal_destroy_texture :: proc(texture: ^Texture) {
    assert(texture.handle != nil, "Trying to release null texture.")
    metal_texture := cast(^MTL.Texture)texture.handle
    metal_texture->release()
    texture.handle = nil
}

////////////////////////////////////////////////////////////////

execute_commands :: proc(
    cb: ^CommandBuffer,
) {
    command_buffer := render_state.command_queue->commandBuffer()
    assert(command_buffer != nil, "Failed to create command buffer")

    for cmd in cb {
        switch c in cmd {
            case Update_Renderpass_Desc:
                execute_update_renderpass_descriptor(c)

            case BeginPassCommand:
                execute_begin_pass(command_buffer, c)
                
            case EndPassCommand:
                execute_end_pass()

            case SetPipelineCommand:
                execute_set_pipeline(c)
                
            case SetViewportCommand:
                execute_set_viewport(c)
                
            case BindVertexBufferCommand:
                execute_bind_vertex_buffer(c)
                
            case BindIndexBufferCommand:
                execute_bind_index_buffer(c)
                
            case BindTextureCommand:
                execute_bind_texture(c)
            
            case BindSamplerCommand:
                execute_bind_sampler(c)
                
            case SetUniformCommand:
                execute_set_uniform(c)
                
            case DrawCommand:
                execute_draw(c)
                
            case DrawIndexedCommand:
                execute_draw_indexed(c)

            case DrawIndexedInstancedCommand:
                execute_draw_indexed_instanced(c)
                
            case SetScissorCommand:
                execute_set_scissor(c)
        }
    }
    command_buffer->presentDrawable(render_state.drawable)
    command_buffer->commit()
}

@(private)
execute_begin_pass :: proc(
    command_buffer: ^MTL.CommandBuffer,
    cmd: BeginPassCommand,
) {    
    render_state.encoder = command_buffer->renderCommandEncoderWithDescriptor(render_state.render_pass_descriptor)
    label := NS.String.alloc()->initWithOdinString(cmd.name)
    render_state.encoder->setLabel(label)
}

@(private)
execute_end_pass :: proc() {
    render_state.encoder->endEncoding()
    render_state.encoder = nil
}

@(private)
execute_set_pipeline :: proc(cmd: SetPipelineCommand) {
    metal_pipeline := cast(^Metal_Pipeline)cmd.pipeline.handle
    render_state.encoder->setRenderPipelineState(metal_pipeline.render_state)
    
    render_state.encoder->setCullMode(metal_cull_mode[cmd.pipeline.desc.cull_mode])
    render_state.encoder->setFrontFacingWinding(
        cmd.pipeline.desc.front_face == .Clockwise ? .Clockwise : .CounterClockwise
    )
    render_state.encoder->setTriangleFillMode(.Fill)
    
    if metal_pipeline.depth_state != nil {
        render_state.encoder->setDepthStencilState(metal_pipeline.depth_state)
    }
}

@(private)
execute_update_renderpass_descriptor :: proc(desc: Update_Renderpass_Desc) {    
    clear_color := MTL.ClearColor{70.0/255.0, 55.0/255.0, 60.0/255.0, 1.0}

    color_attachment := render_state.render_pass_descriptor->colorAttachments()->object(0)
    color_attachment->setTexture(cast(^MTL.Texture)desc.msaa_texture.handle);
    color_attachment->setResolveTexture(render_state.drawable->texture());
    color_attachment->setClearColor(clear_color)
    color_attachment->setLoadAction(.Clear)
    color_attachment->setStoreAction(.MultisampleResolve)
    
    depth_attachment := render_state.render_pass_descriptor->depthAttachment()
    depth_attachment->setTexture(cast(^MTL.Texture)desc.depth_texture.handle)
    depth_attachment->setClearDepth(1.0)
    depth_attachment->setLoadAction(.Clear)
    depth_attachment->setStoreAction(.DontCare)
}

@(private)
execute_set_viewport :: proc(cmd: SetViewportCommand) {
    render_state.encoder->setViewport(MTL.Viewport{
        originX = f64(cmd.x),
        originY = f64(cmd.y),
        width   = f64(cmd.width),
        height  = f64(cmd.height),
        znear   = 0,
        zfar    = 1,
    })
}

@(private)
execute_bind_vertex_buffer :: proc(cmd: BindVertexBufferCommand) {
    metal_buffer := cast(^MTL.Buffer)cmd.buffer.handle

    render_state.encoder->setVertexBuffer(
        metal_buffer,
        NS.UInteger(cmd.offset),
        NS.UInteger(cmd.binding),
    )
}

@(private)
execute_bind_index_buffer :: proc(cmd: BindIndexBufferCommand) {
    // Not needed in Metal
}

@(private)
execute_bind_texture :: proc(cmd: BindTextureCommand) {
    metal_texture := cast(^MTL.Texture)cmd.texture.handle
    
    switch cmd.stage {
    case .Vertex:
        render_state.encoder->setVertexTexture(metal_texture, NS.UInteger(cmd.slot))
    case .Fragment:
        render_state.encoder->setFragmentTexture(metal_texture, NS.UInteger(cmd.slot))
    case .Compute:
        assert(false)
    }
}

@(private)
execute_bind_sampler :: proc(cmd: BindSamplerCommand) {
    metal_sampler := cast(^MTL.SamplerState)cmd.sampler.handle
    render_state.encoder->setFragmentSamplerState(metal_sampler, NS.UInteger(cmd.slot))
}

@(private)
execute_set_uniform :: proc(cmd: SetUniformCommand) {
    b := make([]byte, cmd.size, context.temp_allocator)
    switch cmd.stage {
    case .Vertex:
        
        mem.copy(raw_data(b), cmd.data, cmd.size)
        render_state.encoder->setVertexBytes(
            b,
            NS.UInteger(cmd.slot),
        )
    case .Fragment:
        mem.copy(raw_data(b), cmd.data, cmd.size)
        render_state.encoder->setFragmentBytes(
            b,
            NS.UInteger(cmd.slot),
        )
    case .Compute:
        assert(false, "Trying to set uniform for Compute buffer")
    }
}

@(private)
execute_draw :: proc(cmd: DrawCommand) {
    render_state.encoder->drawPrimitives(
        .Triangle,
        NS.UInteger(cmd.first_vertex),
        NS.UInteger(cmd.vertex_count),
    )
}

@(private)
execute_draw_indexed :: proc(cmd: DrawIndexedCommand) {
    // Assumes index buffer was bound earlier
    render_state.encoder->drawIndexedPrimitives(
        .Triangle,
        NS.UInteger(cmd.index_count),
        .UInt32,  // Assuming 32-bit indices
        cast(^MTL.Buffer)cmd.index_buffer.handle,
        NS.UInteger(cmd.vertex_offset)
    )
}

@(private)
execute_draw_indexed_instanced :: proc(cmd: DrawIndexedInstancedCommand) {
    // Assumes index buffer was bound earlier
    render_state.encoder->drawIndexedPrimitivesWithInstanceCount(
        .Triangle,
        NS.UInteger(cmd.index_count),
        .UInt32,  // Assuming 32-bit indices
        cast(^MTL.Buffer)cmd.index_buffer.handle,
        NS.UInteger(cmd.vertex_offset),
        NS.UInteger(cmd.instance_count)
    )
}

@(private)
execute_set_scissor :: proc(cmd: SetScissorCommand) {
    render_state.encoder->setScissorRect(MTL.ScissorRect{
        x = NS.Integer(cmd.x),
        y = NS.Integer(cmd.y),
        width = NS.Integer(cmd.width),
        height = NS.Integer(cmd.height),
    })
}
