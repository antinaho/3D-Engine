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
    Draw_Mesh_Command,
    Render_Pass_MSAA_Desc,
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
    clear_color: [4]f32,
    clear_depth: f32,
    load_action: Load_Action,
    
    // Optional: For MSAA
    msaa_texture: Texture,
    depth_texture: Texture,
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
    stage: Shader_Stage,  // Vertex or Fragment
}

Set_Uniform_Command :: struct {
    data: rawptr,
    size: int,
    slot: int,
    stage: Shader_Stage,
}

// ===== Draw Calls =====
Draw_Command :: struct {
    vertex_count: int,
    first_vertex: int,
}

Draw_Indexed_Command :: struct {
    index_count: int,
    instance_count: int,
    first_index: int,
    vertex_offset: int,
    first_instance: int,
}

Render_Pass_MSAA_Desc :: struct {
    name: string,
    clear_color: [4]f32,
    clear_depth: f32,
    msaa_texture: Texture,      // MSAA render target
    resolve_texture: Texture,   // Where to resolve (can be swapchain)
    depth_texture: Texture,
}

Draw_Mesh_Command :: struct {
    vertex_buffer: Buffer,
    index_buffer: Buffer,
    index_count: int,
    material: Material,  // Textures + uniforms
    transform: matrix[4, 4]f32,
}


///////////////////////////////////////

// Helper functions to add commands

cmd_begin_pass :: proc(cb: ^Command_Buffer, name: string, clear_color: [4]f32, msa_tex, depth_tex: Texture, renderpass_descriptor: rawptr, clear_depth: f32 = 1.0) {
    append(&cb.commands, Begin_Pass_Command{
        name = name,
        clear_color = clear_color,
        clear_depth = clear_depth,
        load_action = .Clear,
        msaa_texture = msa_tex,
        depth_texture = depth_tex,
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

cmd_bind_texture :: proc(cb: ^Command_Buffer, texture: Texture, slot: int, stage: Shader_Stage) {
    append(&cb.commands, Bind_Texture_Command{texture, slot, stage})
}

cmd_set_uniform :: proc(cb: ^Command_Buffer, data: $T, slot: int, stage: Shader_Stage) {
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

cmd_draw_indexed :: proc(cb: ^Command_Buffer, index_count: int, instance_count: int = 1) {
    append(&cb.commands, Draw_Indexed_Command{
        index_count = index_count,
        instance_count = instance_count,
        first_index = 0,
        vertex_offset = 0,
        first_instance = 0,
    })
}

cmd_draw_mesh :: proc(
    cb: ^Command_Buffer,
    vertex_buffer: Buffer,
    index_buffer: Buffer,
    index_count: int,
    material: Material,
    transform: matrix[4, 4]f32,
) {
    append(&cb.commands, Draw_Mesh_Command{
        vertex_buffer = vertex_buffer,
        index_buffer = index_buffer,
        index_count = index_count,
        material = material,
        transform = transform,
    })
}

cmd_begin_msaa_pass :: proc(cb: ^Command_Buffer, desc: Render_Pass_MSAA_Desc) {
    append(&cb.commands, desc)
}

Update_Renderpass_Desc :: struct {
    renderpass_descriptor: rawptr,
    msaa_texture: Texture,
    depth_texture: Texture,
}

cmd_update_renderpass_descriptors :: proc(cb: ^Command_Buffer, desc: Update_Renderpass_Desc) {
    append(&cb.commands, desc)
}