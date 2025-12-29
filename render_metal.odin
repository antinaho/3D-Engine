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
import "core:mem"

import "core:strings"
import "core:slice"


@(private="file")
state: ^MetalPlatform

metal_load_texture :: proc(desc: TextureLoadDesc) -> (texture: Texture) {
    w, h, c: i32

    pixels := stbi.load(strings.clone_to_cstring(desc.filepath, context.temp_allocator), &w, &h, &c, 4)
    assert(pixels != nil, fmt.tprintf("Can't load texture from: %v", desc.filepath))

    texture.desc.width = int(w)
    texture.desc.height = int(h)

    texture_descriptor := NS.new(MTL.TextureDescriptor)
    texture_descriptor->setPixelFormat(metal_pixel_format[desc.format])
    texture_descriptor->setWidth(NS.UInteger(w))
    texture_descriptor->setHeight(NS.UInteger(h))
    
    tex := state.device->newTextureWithDescriptor(texture_descriptor)
    region := MTL.Region{origin={0,0,0}, size={NS.Integer(w), NS.Integer(h), 1}}
    bytes_per_row := 4 * w

    tex->replaceRegion(region, 0, pixels, NS.UInteger(bytes_per_row))
    texture.handle = tex

    texture_descriptor->release()
    stbi.image_free(pixels)

    return
}

MetalAPI :: RendererAPI {
    draw = metal_draw,
    cleanup = _cleanup,
}

MetalPlatform :: struct {
    device: ^MTL.Device,
    swapchain: ^CA.MetalLayer,
    command_queue: ^MTL.CommandQueue,
    metalDrawable: ^CA.MetalDrawable,

    encoder: ^MTL.RenderCommandEncoder,
}

_cleanup :: proc(window: ^Window, renderer: ^Renderer) {
    platform := cast(^MetalPlatform)renderer.platform

    //platform.msaa_render_target_texture->release()
    //platform.depth_texture->release()
    //platform.renderPassDescriptor->release()
    platform.swapchain->release()

    platform.device->release()

    free(platform)
    free(renderer)
}

metal_create_renderpass_descriptor :: proc(desc: RenderPassDescriptor) -> rawptr {
    render_pass_descriptor := MTL.RenderPassDescriptor.alloc()->init()
    
    color_attachment := render_pass_descriptor->colorAttachments()->object(0)
    depth_attachment := render_pass_descriptor->depthAttachment()
    
    // MSAA or direct rendering

    if desc.msaa_texture.handle != nil {
        msaa_tex := cast(^MTL.Texture)desc.msaa_texture.handle
        color_attachment->setTexture(msaa_tex)
        color_attachment->setResolveTexture(state.metalDrawable->texture())
        color_attachment->setLoadAction(.Clear)
        color_attachment->setClearColor(MTL.ClearColor{
            f64(desc.clear_color.r),
            f64(desc.clear_color.g),
            f64(desc.clear_color.b),
            f64(desc.clear_color.a),
        })
        color_attachment->setStoreAction(.StoreAndMultisampleResolve)
    } else {
        assert(false, "MSAA Handle not set?")
    }
    
    
    // Depth
    if desc.depth_texture.handle != nil {
        depth_tex := cast(^MTL.Texture)desc.depth_texture.handle
        depth_attachment->setTexture(depth_tex)
        depth_attachment->setLoadAction(.Clear)
        depth_attachment->setStoreAction(.DontCare)
        depth_attachment->setClearDepth(1.0)
    } else {
        assert(false, "Depth Handle not set?")
    }

    return render_pass_descriptor
}

metal_init :: proc(window: ^Window) -> ^Renderer {
    renderer := new(Renderer)
    platform := new(MetalPlatform)
    renderer.platform = cast(Platform)platform

    metalWindow := cast(^NS.Window)window.get_window_handle(window)

    platform.device = MTL.CreateSystemDefaultDevice()
    assert(platform.device != nil, "Metal not supported")

    platform.swapchain = CA.MetalLayer.layer()
    platform.swapchain->setDevice(platform.device)
    platform.swapchain->setPixelFormat(.BGRA8Unorm)
    platform.swapchain->setFramebufferOnly(true)
    platform.swapchain->setFrame(metalWindow->frame())

    metalWindow->contentView()->setLayer(platform.swapchain)
    metalWindow->setOpaque(true)
    metalWindow->setBackgroundColor(nil)
    metalWindow->contentView()->setWantsLayer(true)

    platform.command_queue = platform.device->newCommandQueue()
    platform.metalDrawable = platform.swapchain->nextDrawable()
    
    renderer.api = MetalAPI
    state = platform

    return renderer
}

update_render_pass_descriptor :: proc(desc: Update_Renderpass_Desc) {
    pass_desc := cast(^MTL.RenderPassDescriptor)desc.renderpass_descriptor

    pass_desc->colorAttachments()->object(0)->setTexture(cast(^MTL.Texture)desc.msaa_texture.handle);
    pass_desc->colorAttachments()->object(0)->setResolveTexture(state.metalDrawable->texture());
    pass_desc->depthAttachment()->setTexture(cast(^MTL.Texture)desc.depth_texture.handle);   
}

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

    execute_commands(&cmd_buffer)  
}

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

///////////////////////////////////////////////////////////////////////////////

MACOS :: #config(MACOS, true) 

metal_init_buffer :: proc(
    size: int,
    usage: Buffer_Usage,
    access: Buffer_Access,
) -> Buffer {
    assert(state.device != nil, "Metal device not initialized")
    
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
    metal_buffer := state.device->newBuffer(
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
    sampler_desc->setSAddressMode(metal_address_mode[desc.address_mode_u])
    sampler_desc->setTAddressMode(metal_address_mode[desc.address_mode_v])
    sampler_desc->setRAddressMode(metal_address_mode[desc.address_mode_w])
    
    // Anisotropy
    if desc.max_anisotropy > 1 {
        sampler_desc->setMaxAnisotropy(NS.UInteger(desc.max_anisotropy))
    }
    
    metal_sampler := state.device->newSamplerState(sampler_desc)
    
    return Sampler {
        handle = metal_sampler
    }
}

metal_address_mode := [Sampler_Address_Mode]MTL.SamplerAddressMode {
    .Repeat         = .Repeat,
    .MirrorRepeat   = .MirrorRepeat,
    .ClampToEdge    = .ClampToEdge,
    .ClampToBorder  = .ClampToBorderColor
}

metal_destroy_sampler :: proc(sampler: ^Sampler) {
    if sampler.handle == nil do return
    metal_sampler := cast(^MTL.SamplerState)sampler.handle
    metal_sampler->release()
    sampler.handle = nil
}

////////////////////////////////

metal_compile_shader :: proc(desc: ShaderDesc) -> (Shader, bool) {
    assert(state.device != nil)
    
    // For Metal, we need .metal source or precompiled .metallib
    if desc.shader_language != .MSL {
        log.panic("Metal backend requires MSL shaders")
    }
    
    // Compile at runtime

    log.info("LOADING SHADER LIB")
    library_desc := NS.new(MTL.CompileOptions)
    source := NS.String.alloc()->initWithOdinString(desc.source)
    defer source->release()
    
    library, err := state.device->newLibraryWithSource(
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
    assert(state.device != nil, "Device not initialized")
    
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
        log.info("✓ Vertex descriptor set")
    }

    assert(len(desc.color_formats) > 0, "No color formats specified")
    
    color_attachment := render_pipeline_desc->colorAttachments()->object(0)
    color_attachment->setPixelFormat(state.swapchain->pixelFormat())

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
    log.info("✓ Color attachments set")

    render_pipeline_desc->setSampleCount(NS.UInteger(desc.sample_count))
    //render_pipeline_desc->setTessellationOutputWindingOrder(.Clockwise)

    // Depth attachment
    if desc.depth_format != .RGBA8_UNorm {  // Has depth
        render_pipeline_desc->setDepthAttachmentPixelFormat(metal_pixel_format[desc.depth_format])
    }
        
    // Create pipeline state
    pipeline_state, err := state.device->newRenderPipelineState(render_pipeline_desc)
    assert(pipeline_state != nil, fmt.tprintf("Failed to create Metal pipeline: %v", err->localizedDescription()->odinString()))

    log.info("✓ Pipeline created successfully")
    // Depth state (separate object in Metal)
    depth_state: ^MTL.DepthStencilState
    if desc.depth_state.test_enabled {
        depth_desc := MTL.DepthStencilDescriptor.alloc()->init()
        depth_desc->setDepthCompareFunction(metal_compare_operation[desc.depth_state.compare_op])
        depth_desc->setDepthWriteEnabled(desc.depth_state.write_enabled)
        depth_state = state.device->newDepthStencilState(depth_desc)
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

metal_create_texture :: proc(desc: Texture_Desc) -> Texture {
    assert(state.device != nil, "Device not initialized")
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
    
    // Custom dimensions?
    // Dimensions
    //texture_desc->setWidth(NS.UInteger(desc.width))
    //texture_desc->setHeight(NS.UInteger(desc.height))

    texture_desc->setWidth(NS.UInteger(state.swapchain->drawableSize().width))
    texture_desc->setHeight(NS.UInteger(state.swapchain->drawableSize().height))
    
    //texture_desc->setDepth(NS.UInteger(max(desc.depth, 1)))
    
    
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

    metal_texture := state.device->newTexture(texture_desc)
    
    if metal_texture == nil {
        log.panic("Failed to create texture")
    }
    
    return Texture{
        handle = metal_texture,
        desc = desc,
    }
}

metal_destroy_texture :: proc(texture: ^Texture) {
    if texture.handle == nil do return
    metal_texture := cast(^MTL.Texture)texture.handle
    metal_texture->release()
    texture.handle = nil
}

////////////////////////////////////////////////////////////////

execute_commands :: proc(
    cb: ^Command_Buffer,
) {
    command_buffer := state.command_queue->commandBuffer()
    assert(command_buffer != nil, "Failed to create command buffer")

    for cmd in cb.commands {
        switch c in cmd {
            case Update_Renderpass_Desc:
                update_render_pass_descriptor(c)

            case Begin_Pass_Command:
                execute_begin_pass(command_buffer, c)
                
            case End_Pass_Command:
                execute_end_pass()

            case Set_Pipeline_Command:
                execute_set_pipeline(c)
                
            case Set_Viewport_Command:
                execute_set_viewport(c)
                
            case Bind_Vertex_Buffer_Command:
                execute_bind_vertex_buffer(c)
                
            case Bind_Index_Buffer_Command:
                execute_bind_index_buffer(c)
                
            case Bind_Texture_Command:
                execute_bind_texture(c)
                
            case Set_Uniform_Command:
                execute_set_uniform(c)
                
            case Draw_Command:
                execute_draw(c)
                
            case Draw_Indexed_Command:
                execute_draw_indexed(c)

            case Draw_Indexed_Instanced_Command:
                execute_draw_indexed_instanced(c)
                
            case Set_Scissor_Command:
                execute_set_scissor(c)
        }
    }
    command_buffer->presentDrawable(state.metalDrawable)
    command_buffer->commit()
}

@(private)
execute_begin_pass :: proc(
    command_buffer: ^MTL.CommandBuffer,
    cmd: Begin_Pass_Command,
) {
    state.encoder = command_buffer->renderCommandEncoderWithDescriptor(cast(^MTL.RenderPassDescriptor)cmd.renderpass_descriptor)
    
    label := NS.String.alloc()->initWithOdinString(cmd.name)
    state.encoder->setLabel(label)
}

@(private)
execute_end_pass :: proc() {
    state.encoder->endEncoding()
    //Maybe set platform.encoder to nil?
}

@(private)
execute_set_pipeline :: proc(cmd: Set_Pipeline_Command) {
    metal_pipeline := cast(^Metal_Pipeline)cmd.pipeline.handle
    state.encoder->setRenderPipelineState(metal_pipeline.render_state)
    
    state.encoder->setCullMode(metal_cull_mode[cmd.pipeline.desc.cull_mode])
    state.encoder->setFrontFacingWinding(
        cmd.pipeline.desc.front_face == .Clockwise ? .Clockwise : .CounterClockwise
    )
    state.encoder->setTriangleFillMode(.Fill)
    
    if metal_pipeline.depth_state != nil {
        state.encoder->setDepthStencilState(metal_pipeline.depth_state)
    }
}

@(private)
execute_set_viewport :: proc(cmd: Set_Viewport_Command) {
    state.encoder->setViewport(MTL.Viewport{
        originX = f64(cmd.x),
        originY = f64(cmd.y),
        width   = f64(cmd.width),
        height  = f64(cmd.height),
        znear   = 0,
        zfar    = 1,
    })
}

@(private)
execute_bind_vertex_buffer :: proc(cmd: Bind_Vertex_Buffer_Command) {
    metal_buffer := cast(^MTL.Buffer)cmd.buffer.handle

    state.encoder->setVertexBuffer(
        metal_buffer,
        NS.UInteger(cmd.offset),
        NS.UInteger(cmd.binding),
    )
}

@(private)
execute_bind_index_buffer :: proc(cmd: Bind_Index_Buffer_Command) {
    // Index buffer is bound in draw call in Metal
    // Store for later
}

@(private)
execute_bind_texture :: proc(cmd: Bind_Texture_Command) {
    metal_texture := cast(^MTL.Texture)cmd.texture.handle
    
    switch cmd.stage {
    case .Vertex:
        state.encoder->setVertexTexture(metal_texture, NS.UInteger(cmd.slot))
    case .Fragment:
        state.encoder->setFragmentTexture(metal_texture, NS.UInteger(cmd.slot))
    case .Compute:
        assert(false)
    }
}

@(private)
execute_set_uniform :: proc(cmd: Set_Uniform_Command) {
    switch cmd.stage {
    case .Vertex:
        b := slice.bytes_from_ptr(cmd.data, cmd.size)
        state.encoder->setVertexBytes(
            b,
            NS.UInteger(cmd.slot),
        )
    case .Fragment:
        b := slice.bytes_from_ptr(cmd.data, cmd.size)
        state.encoder->setFragmentBytes(
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
execute_draw :: proc(cmd: Draw_Command) {

    state.encoder->drawPrimitives(
        .Triangle,
        NS.UInteger(cmd.first_vertex),
        NS.UInteger(cmd.vertex_count),
    )
}

@(private)
execute_draw_indexed :: proc(cmd: Draw_Indexed_Command) {
    // Assumes index buffer was bound earlier
    state.encoder->drawIndexedPrimitives(
        .Triangle,
        NS.UInteger(cmd.index_count),
        .UInt32,  // Assuming 32-bit indices
        cast(^MTL.Buffer)cmd.index_buffer.handle,
        NS.UInteger(cmd.vertex_offset)
    )
}

@(private)
execute_draw_indexed_instanced :: proc(cmd: Draw_Indexed_Instanced_Command) {
    // Assumes index buffer was bound earlier
    state.encoder->drawIndexedPrimitivesWithInstanceCount(
        .Triangle,
        NS.UInteger(cmd.index_count),
        .UInt32,  // Assuming 32-bit indices
        cast(^MTL.Buffer)cmd.index_buffer.handle,
        NS.UInteger(cmd.vertex_offset),
        NS.UInteger(cmd.instance_count)
    )
}

@(private)
execute_set_scissor :: proc(cmd: Set_Scissor_Command) {
    state.encoder->setScissorRect(MTL.ScissorRect{
        x = NS.Integer(cmd.x),
        y = NS.Integer(cmd.y),
        width = NS.Integer(cmd.width),
        height = NS.Integer(cmd.height),
    })
}
