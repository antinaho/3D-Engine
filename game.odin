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

vertex_buf: Buffer
index_buf: Buffer
uniform_buf: Buffer
instance_buf: Buffer

import "core:math"

RAD_TO_DEG :: math.RAD_PER_DEG

Vector2 :: [2]f32
Vector3 :: [3]f32

VECTOR_RIGHT   :: Vector3{1, 0,  0}
VECTOR_UP      :: Vector3{0, 1,  0}
VECTOR_FORWARD :: Vector3{0, 0, -1}

Position :: Vector3
Rotation :: Vector3
Scale    :: Vector3

Transform :: struct {
    position: Position,
    rotation: Rotation,
    scale:    Scale,
}

Entity :: struct {
    using transform: Transform,
}

quadA := Entity {
    position = {0, 0, 0},
    rotation = {0, 20, 0},
    scale = {1, 1, 1},
}

quadB := Entity {
    position = {2, 0, 0},
    rotation = {0, 0, 10},
    scale = {1, 1, 1},
}


quadC := Entity {
    position = {-2, -1, 0},
    rotation = {0, 0, 20},
    scale = {1, 1, 1},
}

quads := [?]Entity {
    quadA,
    quadB,
    quadC
}

_update :: proc(delta: f32) {
    cmd_update_renderpass_descriptors(&cmd_buffer, Update_Renderpass_Desc{
        renderpass_descriptor=render_pass_3d.renderpass_descriptor,
        msaa_texture = render_pass_3d.msaa_render_target_texture,
        depth_texture = render_pass_3d.depth_texture,
    })

    cmd_begin_pass(&cmd_buffer, "Test", render_pass_3d.renderpass_descriptor)
    cmd_set_pipeline(&cmd_buffer, render_pass_3d.pipeline)

    // Frame uniform
    view := matrix_look_at(
            camera.position,
            camera.target,
            VECTOR_UP
        )

    proj := get_orthographic_projection(camera)
    
    uniforms := U {
        view = view,
        projection = proj,
    }

    fill_buffer(&uniform_buf, &uniforms, size_of(U))
    fill_buffer(&vertex_buf, raw_data(QuadVertices[:]), size_of(Vertex) * len(QuadVertices))
    // Per entity
    for quad, i in quads {
        model := matrix_model(
            quad.position,
            quad.rotation * RAD_TO_DEG,
            quad.scale
        )

        instance_data := I{model = model}
        // Fill all instances at the same time? [dynamic]Instances -> fill
        fill_buffer(&instance_buf, &instance_data, size_of(I), size_of(I) * i)
        
    }

    cmd_bind_vertex_buffer(&cmd_buffer, vertex_buf, 0, 0)
    cmd_bind_vertex_buffer(&cmd_buffer, uniform_buf, 0, 1)
    cmd_bind_vertex_buffer(&cmd_buffer, instance_buf, 0, 2)

    cmd_bind_index_buffer(&cmd_buffer, index_buf)
    cmd_bind_texture(&cmd_buffer, render_pass_3d.custom_texture, 0, .Fragment)

    cmd_draw_indexed_with_instances(&cmd_buffer, len(QuadIndeces), index_buf, len(quads))

    cmd_end_pass(&cmd_buffer)
}

I :: struct #align(16) {
    model:      matrix[4, 4]f32,
}

U :: struct #align(16) {
    view:        matrix[4, 4]f32,
    projection:  matrix[4, 4]f32,
}

QuadVertices := []Vertex {
    {position={-0.5, -0.5, 0}, normal={1,1,1}, color={1,1,0.2,1},   uvs={0,0}},
    {position={ 0.5, -0.5, 0}, normal={1,1,1}, color={0.2,0.2,1,1}, uvs={1,0}},
    {position={ 0.5,  0.5, 0}, normal={1,1,1}, color={0.2,1,0.2,1}, uvs={1,1}},
    {position={-0.5,  0.5, 0}, normal={1,1,1}, color={1,0.2,0.2,1}, uvs={0,1}},
}

QuadIndeces := []u32 {
    0, 1, 2, 2, 3, 0,
    4, 5, 6, 6, 7, 4,
}

main :: proc() {
    
    when ODIN_DEBUG {
        default_allocator := context.allocator
        tracking_allocator: mem.Tracking_Allocator
        mem.tracking_allocator_init(&tracking_allocator, default_allocator)
        context.allocator = mem.tracking_allocator(&tracking_allocator)
        defer reset_tracking_allocator(&tracking_allocator)
    }

    context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

    init(1280, 720, "Hellope")

    app_window := create_window(1280, 720, "Hellope", context.allocator, {.MainWindow})

    add_layer(app_window, ExampleLayer)

    run()
}