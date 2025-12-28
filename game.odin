package main

import "core:fmt"
import "core:log"
import "core:mem"

ExampleLayer := Layer {
	ingest_events = _events,
	update = _update,
}

_events :: proc(input: ^WindowInput) {
	if key_went_down(input, .E) {
		fmt.println("Pressed E LayerOne")
	}
}

b: Buffer
bi: Buffer

_update :: proc(delta: f32) {
    cmd_update_renderpass_descriptors(&cmd_buffer, Update_Renderpass_Desc{
        renderpass_descriptor=render_pass_3d.renderpass_descriptor,
        msaa_texture = render_pass_3d.msaa_render_target_texture,
        depth_texture = render_pass_3d.depth_texture,
    })

    cmd_begin_pass(&cmd_buffer, "Test", render_pass_3d.renderpass_descriptor)

    cmd_set_pipeline(&cmd_buffer, render_pass_3d.pipeline)

    cmd_bind_vertex_buffer(&cmd_buffer, b)
    cmd_bind_index_buffer(&cmd_buffer, bi)

    cmd_draw_indexed(&cmd_buffer, len(TriangleIndices), bi)

    cmd_end_pass(&cmd_buffer)
}

TriangleVertices := []Vertex {
    {position={-0.5, -0.5, 0}, normal={1,1,1}, color={1,1,0.2,1}, uvs={1,1}},
    {position={ 0.5, -0.5, 0}, normal={1,1,1}, color={0.2,0.2,1,1}, uvs={1,1}},
    {position={ 0.5,  0.5, 0}, normal={1,1,1}, color={0.2,1,0.2,1}, uvs={1,1}},
    {position={-0.5,  0.5, 0}, normal={1,1,1}, color={1,0.2,0.2,1}, uvs={1,1}},
}

TriangleIndices := []u32 {
    0, 1, 2, 2, 3, 0
}

main :: proc() {
    
    default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)
	defer reset_tracking_allocator(&tracking_allocator)

    context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

    init(1280, 720, "Hellope")

    app_window := create_window(1280, 720, "Hellope", context.allocator, {.MainWindow})

    add_layer(app_window, ExampleLayer)


    run()
}