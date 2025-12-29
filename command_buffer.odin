package main

Render_Command :: union {
    Begin_Pass_Command,
    End_Pass_Command,

    Set_Pipeline_Command,
    Set_Viewport_Command,
    Set_Scissor_Command,
    
    Bind_Vertex_Buffer_Command,
    Bind_Index_Buffer_Command,
    Bind_Texture_Command,

    Set_Uniform_Command,
    
    Draw_Command,
    Draw_Indexed_Command,
    Draw_Indexed_Instanced_Command,

    Update_Renderpass_Desc
}

Command_Buffer :: struct {
    commands: [dynamic]Render_Command,
}

init_command_buffer :: proc() -> Command_Buffer {
    return Command_Buffer{
        commands = make([dynamic]Render_Command, 0, 128),
    }
}

reset_command_buffer :: proc(cb: ^Command_Buffer) {
    clear(&cb.commands)
}

destroy_command_buffer :: proc(cb: ^Command_Buffer) {
    delete(cb.commands)
}

/////////////////////////////////////////

// Individual command types

// ===== Render Pass =====
Begin_Pass_Command :: struct {
    name: string,
    renderpass_descriptor: rawptr,
}

Load_Action :: enum {
    Load,      // Keep existing content
    Clear,     // Clear to color
    DontCare,  // Undefined (fastest)
}

End_Pass_Command :: struct {}  // Empty marker

// ===== Pipeline State =====
Set_Pipeline_Command :: struct {
    pipeline: Pipeline,
}

Set_Viewport_Command :: struct {
    x, y: f32,
    width, height: f32,
}

Set_Scissor_Command :: struct {
    x, y: int,
    width, height: int,
}

// ===== Resource Binding =====
Bind_Vertex_Buffer_Command :: struct {
    buffer: Buffer,
    offset: int,
    binding: int,  // Binding point (0, 1, 2...)
}

Bind_Index_Buffer_Command :: struct {
    buffer: Buffer,
    offset: int,
}

Bind_Texture_Command :: struct {
    texture: Texture,
    slot: int,  // Texture slot (0-7 typically)
    stage: ShaderStage,  // Vertex or Fragment
}

Set_Uniform_Command :: struct {
    data: rawptr,
    size: int,
    slot: int,
    stage: ShaderStage,
}

// ===== Draw Calls =====
Draw_Command :: struct {
    vertex_count: int,
    first_vertex: int,
}

Draw_Indexed_Command :: struct {
    index_count: int,
    first_index: int,
    vertex_offset: int,
    index_buffer: Buffer,
}

Draw_Indexed_Instanced_Command :: struct {
    index_count: int,
    first_index: int,
    vertex_offset: int,
    index_buffer: Buffer,
    instance_count: int,
}

Render_Pass_MSAA_Desc :: struct {
    name: string,
    clear_color: [4]f32,
    clear_depth: f32,
    msaa_texture: Texture,      // MSAA render target
    resolve_texture: Texture,   // Where to resolve (can be swapchain)
    depth_texture: Texture,
}

///////////////////////////////////////

// Helper functions to add commands

cmd_begin_pass :: proc(cb: ^Command_Buffer, name: string, renderpass_descriptor: rawptr) {
    append(&cb.commands, Begin_Pass_Command{
        name = name,
        renderpass_descriptor = renderpass_descriptor,
    })
}

cmd_end_pass :: proc(cb: ^Command_Buffer) {
    append(&cb.commands, End_Pass_Command{})
}

cmd_set_pipeline :: proc(cb: ^Command_Buffer, pipeline: Pipeline) {
    append(&cb.commands, Set_Pipeline_Command{pipeline})
}

cmd_set_viewport :: proc(cb: ^Command_Buffer, x, y, width, height: f32) {
    append(&cb.commands, Set_Viewport_Command{x, y, width, height})
}

cmd_bind_vertex_buffer :: proc(cb: ^Command_Buffer, buffer: Buffer, offset: int = 0, binding: int = 0) {
    append(&cb.commands, Bind_Vertex_Buffer_Command{buffer, offset, binding})
}

cmd_bind_index_buffer :: proc(cb: ^Command_Buffer, buffer: Buffer, offset: int = 0) {
    append(&cb.commands, Bind_Index_Buffer_Command{buffer, offset})
}

cmd_bind_texture :: proc(cb: ^Command_Buffer, texture: Texture, slot: int, stage: ShaderStage) {
    append(&cb.commands, Bind_Texture_Command{texture, slot, stage})
}

cmd_set_uniform :: proc(cb: ^Command_Buffer, data: $T, slot: int, stage: ShaderStage) {
    // Copy uniform data (don't store pointer)
    uniform_data := new(T)
    uniform_data^ = data
    
    append(&cb.commands, Set_Uniform_Command{
        data = uniform_data,
        size = size_of(T),
        slot = slot,
        stage = stage,
    })
}

cmd_draw :: proc(cb: ^Command_Buffer, vertex_count: int) {
    append(&cb.commands, Draw_Command{
        vertex_count = vertex_count,
        first_vertex = 0,
    })
}

cmd_draw_indexed :: proc(cb: ^Command_Buffer, index_count: int, index_buffer: Buffer) {
    append(&cb.commands, Draw_Indexed_Command{
        index_count = index_count,
        first_index = 0,
        vertex_offset = 0,
        index_buffer = index_buffer,
    })
}

cmd_draw_indexed_with_instances :: proc(cb: ^Command_Buffer, index_count: int, index_buffer: Buffer, instance_count: int) {
    append(&cb.commands, Draw_Indexed_Instanced_Command{
        index_count = index_count,
        first_index = 0,
        vertex_offset = 0,
        index_buffer = index_buffer,
        instance_count = instance_count,
    })
}


Update_Renderpass_Desc :: struct {
    renderpass_descriptor: rawptr,
    msaa_texture: Texture,
    depth_texture: Texture,
}

cmd_update_renderpass_descriptors :: proc(cb: ^Command_Buffer, desc: Update_Renderpass_Desc) {
    append(&cb.commands, desc)
}