package main

import "core:log"
import "core:mem"
import "core:math"

TestLayerData :: struct {
    default_renderer: DefaultRenderer,
    vertex_buf: Buffer,
    index_buf: Buffer,
    instance_buf: Buffer,
    instance_data: [dynamic]InstanceData,
}

create_test_layer :: proc() -> Layer {
    data := new(TestLayerData)
    return Layer {
        on_attach = _attach,
        on_detach = _detach,
        on_event = _events,
        update = _update,
        render = _render,
        data = cast(uintptr)data,
    }
}

_attach :: proc(layer: ^Layer) {

    log.debug(65 * DEG_TO_RAD)
    log.debug(70 * DEG_TO_RAD)

    d := cast(^TestLayerData)layer.data
    d^ = {
        default_renderer = init_default_renderer(1280, 720),
        vertex_buf = init_buffer_with_size(size_of(Vertex) * 1000, .Vertex, .Dynamic),
        instance_buf = init_buffer_with_size(size_of(InstanceData) * 1000, .Vertex, .Dynamic),
        index_buf = init_buffer_with_size(size_of(u32) * 1000, .Index, .Dynamic),
        instance_data = make([dynamic]InstanceData),
    }
}

_detach :: proc(layer: ^Layer) {
    d := cast(^TestLayerData)layer.data

    free(d.default_renderer.pipeline.handle)
    release_buffer(&d.vertex_buf)
    release_buffer(&d.instance_buf)
    release_buffer(&d.index_buf)
    delete(d.instance_data)
    free(d)
}


_update :: proc(layer: ^Layer, delta: f32) {
}

_render :: proc(layer: ^Layer, command_buffer: ^CommandBuffer) {
    data := cast(^TestLayerData)layer.data
    cmd_update_renderpass_descriptors(command_buffer, Update_Renderpass_Desc{
        renderpass_descriptor=data.default_renderer.renderpass_descriptor,
        msaa_texture = data.default_renderer.msaa_render_target_texture,
        depth_texture = data.default_renderer.depth_texture,
    })

    cmd_begin_pass(command_buffer, "Test", data.default_renderer.renderpass_descriptor)
    cmd_set_pipeline(command_buffer, data.default_renderer.pipeline)

    view: matrix[4,4]f32
    proj: matrix[4,4]f32
    
    switch v in main_camera.type {
        case Orthographic:
        case Perspective:
            view = mat4_view(
                eye=main_camera.position,
                target=main_camera.position + forward_from_euler(main_camera.type.(Perspective).rotation * DEG_TO_RAD),
                up=VECTOR_UP
            )
            proj = mat4_perspective_projection(
                fov_y_radians=DEG_TO_RAD*main_camera.type.(Perspective).fov,
                aspect=16.0 / 9.0,
                near=0.1,
                far=100
            )
    }
    
    uniforms := UniformData {
        view = view,
        projection = proj,
    }
    cmd_set_uniform(command_buffer, uniforms, 1, .Vertex)

    if len(data.instance_data) == 0 {
        cmd_end_pass(command_buffer)
        return
    }

    fill_buffer(&data.vertex_buf, raw_data(QuadMesh.verteces), size_of(Vertex) * len(QuadMesh.verteces), 0)
    fill_buffer(&data.index_buf,  raw_data(QuadMesh.indices),  size_of(u32) * len(QuadMesh.indices), 0)
    fill_buffer(&data.instance_buf, raw_data(data.instance_data), size_of(InstanceData) * len(data.instance_data), 0)

    cmd_bind_vertex_buffer(command_buffer, data.vertex_buf, 0, 0)
    cmd_bind_vertex_buffer(command_buffer, data.instance_buf, 0, 2)
    cmd_bind_index_buffer(command_buffer, data.index_buf, 0)
    cmd_bind_texture(command_buffer, data.default_renderer.custom_texture, 0, .Fragment)
    cmd_bind_sampler(command_buffer, data.default_renderer.default_sampler, 0, .Fragment)

    cmd_draw_indexed_with_instances(command_buffer, len(QuadMesh.indices), data.index_buf, len(data.instance_data))

    cmd_end_pass(command_buffer)
}

_events :: proc(layer: ^Layer) {
    data := cast(^TestLayerData)layer.data


    if input_mouse_button_is_held(.Middle) {
        if val, ok := &main_camera.type.(Perspective); ok {
            val.rotation.y -= input_mouse_delta(.X) * 20 * delta_time()
            val.rotation.x += input_mouse_delta(.Y) * 20 * delta_time()
        }
    }

    m: f32 = 2.75
    if input_key_is_held(.A) {
        main_camera.position -= right_from_euler(main_camera.type.(Perspective).rotation*DEG_TO_RAD) * delta_time() * m
    }
    if input_key_is_held(.D) {
        main_camera.position += right_from_euler(main_camera.type.(Perspective).rotation*DEG_TO_RAD) * delta_time() * m
    }

    if input_key_is_held(.W) {
        main_camera.position += up_from_euler(main_camera.type.(Perspective).rotation*DEG_TO_RAD) * delta_time() * m
    }
    if input_key_is_held(.S) {
        main_camera.position -= up_from_euler(main_camera.type.(Perspective).rotation*DEG_TO_RAD) * delta_time() * m
    }
    
    if input_mouse_button_is_held(.Left) {
        main_camera.position += forward_from_euler(main_camera.type.(Perspective).rotation*DEG_TO_RAD) * delta_time() * m
    }
    if input_mouse_button_is_held(.Right) {
        main_camera.position -= forward_from_euler(main_camera.type.(Perspective).rotation*DEG_TO_RAD) * delta_time() * m
    }

	if input_key_went_down(.E) {
		//fmt.println("Pressed E LayerOne")
        
        for i in 0..<5 {

            model := mat4_model(
                Vector3{} + random_unit_vector_spherical(),
                Vector3{},
                Vector3{1, 1, 1}
            )

            append(&data.instance_data, InstanceData {
                model
            })            
        }        
	}
}

Entity :: struct {
    using transform: Transform,
    mesh: ^Mesh,
    vel: Vector3,
}

Transform :: struct {
    position: Vector3,
    rotation: Vector3,
    scale:    Vector3,
}

Mesh :: struct {
    verteces: []Vertex,
    indices: []u32,
}

QuadMesh :: Mesh {
    verteces = []Vertex {
        {position={-0.5, -0.5, 0}, normal={0,0,1}, color={1,1,1,1}, uvs={0,0}},
        {position={ 0.5, -0.5, 0}, normal={0,0,1}, color={1,1,1,1}, uvs={1,0}},
        {position={ 0.5,  0.5, 0}, normal={0,0,1}, color={1,1,1,1}, uvs={1,1}},
        {position={-0.5,  0.5, 0}, normal={0,0,1}, color={1,1,1,1}, uvs={0,1}},
    },
    indices = []u32 {
        0, 1, 2, 2, 3, 0,
    },
}

@(rodata)
quad_mesh := QuadMesh

quad := Entity {
    position = {0, 0, 0},
    rotation = {0, 0, 0},
    scale = {1, 1, 1},
    mesh = &quad_mesh,
}

InstanceData :: struct #align(16) {
    model:      matrix[4, 4]f32,
}

UniformData :: struct #align(16) {
    view:        matrix[4, 4]f32,
    projection:  matrix[4, 4]f32,
}

main :: proc() {
    
    // Tracking allocator
    when ODIN_DEBUG {
        default_allocator := context.allocator
        tracking_allocator: mem.Tracking_Allocator
        mem.tracking_allocator_init(&tracking_allocator, default_allocator)
        context.allocator = mem.tracking_allocator(&tracking_allocator)
        defer reset_tracking_allocator(&tracking_allocator)
    }

    context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

    launch_config := WindowConfig {
        width = 1280,
        height = 720,
        title = "Hellope",
    }

    application_init(launch_config)

    layer := create_test_layer()
    add_layer(&layer)
    
    // application_new_window(launch_config, SecondaryWindow)
    // layer_n := create_test_layer()
    // add_layer(&layer_n, 1)

    run()
}

import "core:fmt"
reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> (err: bool) {
	fmt.println("Tracking allocator: ")

	for _, val in a.allocation_map {
		fmt.printfln("%v: Leaked %v bytes", val.location, val.size)
		err = true
	}

	mem.tracking_allocator_clear(a)

	return
}

