package main

RenderCommand :: union {
    BeginPassCommand,
    EndPassCommand,

    SetPipelineCommand,
    SetViewportCommand,
    SetScissorCommand,
    
    BindVertexBufferCommand,
    BindIndexBufferCommand,
    BindTextureCommand,
    BindSamplerCommand,

    SetUniformCommand,
    
    DrawCommand,
    DrawIndexedCommand,
    DrawIndexedInstancedCommand,

    Update_Renderpass_Desc
}

CommandBuffer :: distinct [dynamic]RenderCommand

// Create default CommandBuffer
init_command_buffer :: proc() -> (command_buffer: CommandBuffer) {
    return make(CommandBuffer, 0, 128)
}

// Clear buffer
clear_command_buffer :: proc(cb: ^CommandBuffer) {
    clear(cb)
}

// Free buffer memory
destroy_command_buffer :: proc(cb: ^CommandBuffer) {
    delete(cb^)
}

/////////////////////////////////////////

// Individual command types

// ===== Render Pass =====
BeginPassCommand :: struct {
    name: string,
    renderpass_descriptor: rawptr,
}

EndPassCommand :: struct {}

// ===== Pipeline State =====
SetPipelineCommand :: struct {
    pipeline: Pipeline,
}

SetViewportCommand :: struct {
    x, y: f32,
    width, height: f32,
}

SetScissorCommand :: struct {
    x, y: int,
    width, height: int,
}

// ===== Resource Binding =====
// TODO: Probably just simplify all bindings to 1 struct BindBufferCommand?

BindVertexBufferCommand :: struct {
    buffer: Buffer,
    offset: int,
    binding: int,
}

BindIndexBufferCommand :: struct {
    buffer: Buffer,
    offset: int,
}

BindTextureCommand :: struct {
    texture: Texture,
    slot: int,
    stage: ShaderStage,
}

BindSamplerCommand :: struct {
    sampler: TextureSampler,
    stage: ShaderStage,
    slot: int,
}

SetUniformCommand :: struct {
    data: rawptr,
    size: int,
    slot: int,
    stage: ShaderStage,
}

// ===== Draw Calls =====
// TODO: Only support instance drawing since it seems preferred in Metal/DirectX?
DrawCommand :: struct {
    vertex_count: int,
    first_vertex: int,
}

DrawIndexedCommand :: struct {
    index_count: int,
    first_index: int,
    vertex_offset: int,
    index_buffer: Buffer,
}

DrawIndexedInstancedCommand :: struct {
    index_count: int,
    first_index: int,
    vertex_offset: int,
    index_buffer: Buffer,
    instance_count: int,
}

RenderPassMSAADesc :: struct {
    name: string,
    clear_color: [4]f32,
    clear_depth: f32,
    msaa_texture: Texture,
    resolve_texture: Texture,
    depth_texture: Texture,
}

Update_Renderpass_Desc :: struct {
    renderpass_descriptor: rawptr,
    msaa_texture: Texture,
    depth_texture: Texture,
}

///////////////////////////////////////

cmd_begin_pass :: proc(cb: ^CommandBuffer, name: string, renderpass_descriptor: rawptr) {
    append(cb, BeginPassCommand{
        name = name,
        renderpass_descriptor = renderpass_descriptor,
    })
}

cmd_end_pass :: proc(cb: ^CommandBuffer) {
    append(cb, EndPassCommand{})
}

cmd_set_pipeline :: proc(cb: ^CommandBuffer, pipeline: Pipeline) {
    append(cb, SetPipelineCommand{pipeline})
}

cmd_set_viewport :: proc(cb: ^CommandBuffer, x, y, width, height: f32) {
    append(cb, SetViewportCommand{x, y, width, height})
}

cmd_bind_vertex_buffer :: proc(cb: ^CommandBuffer, buffer: Buffer, offset: int, binding: int) {
    append(cb, BindVertexBufferCommand{buffer, offset, binding})
}

cmd_bind_index_buffer :: proc(cb: ^CommandBuffer, buffer: Buffer, offset: int) {
    append(cb, BindIndexBufferCommand{buffer, offset})
}

cmd_bind_texture :: proc(cb: ^CommandBuffer, texture: Texture, slot: int, stage: ShaderStage) {
    append(cb, BindTextureCommand{texture, slot, stage})
}

cmd_bind_sampler :: proc(cb: ^CommandBuffer, sampler: TextureSampler, slot: int, stage: ShaderStage) {
    append(cb, BindSamplerCommand{sampler, stage, slot})
}

cmd_set_uniform :: proc(cb: ^CommandBuffer, data: $T, slot: int, stage: ShaderStage) {
    uniform_data := new(T, context.temp_allocator)
    uniform_data^ = data
    
    append(cb, SetUniformCommand{
        data = uniform_data,
        size = size_of(T),
        slot = slot,
        stage = stage,
    })
}

cmd_draw :: proc(cb: ^CommandBuffer, vertex_count: int) {
    append(cb, DrawCommand{
        vertex_count = vertex_count,
        first_vertex = 0,
    })
}

cmd_draw_indexed :: proc(cb: ^CommandBuffer, index_count: int, index_buffer: Buffer) {
    append(cb, DrawIndexedCommand{
        index_count = index_count,
        first_index = 0,
        vertex_offset = 0,
        index_buffer = index_buffer,
    })
}

cmd_draw_indexed_with_instances :: proc(cb: ^CommandBuffer, index_count: int, index_buffer: Buffer, instance_count: int) {
    append(cb, DrawIndexedInstancedCommand{
        index_count = index_count,
        first_index = 0,
        vertex_offset = 0,
        index_buffer = index_buffer,
        instance_count = instance_count,
    })
}

cmd_update_renderpass_descriptors :: proc(cb: ^CommandBuffer, desc: Update_Renderpass_Desc) {
    append(cb, desc)
}