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
        on_event = _events,
        update = _update,
        render = _render,
        data = cast(uintptr)data,
    }
}

_attach :: proc(layer: ^Layer) {

    d := cast(^TestLayerData)layer.data
    d^ = {
        default_renderer = init_default_renderer(1280, 720),
        vertex_buf = init_buffer_with_size(size_of(Vertex) * 1000, .Vertex, .Dynamic),
        instance_buf = init_buffer_with_size(size_of(InstanceData) * 1000, .Vertex, .Dynamic),
        index_buf = init_buffer_with_size(size_of(u32) * 1000, .Index, .Dynamic),
        instance_data = make([dynamic]InstanceData),
    }
}


_update :: proc(layer: ^Layer, delta: f32) {
    update_camera_vectors(&main_camera)    
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
    if main_camera.projection == .Orthographic {
        view = matrix_look_at(
            main_camera.position,
            main_camera.position + VECTOR_FORWARD,
            VECTOR_UP
        )
    } else {
        view = matrix_look_at(
            main_camera.position,
            main_camera.position + main_camera.forward,
            main_camera.up
        )
    }
    
    proj: matrix[4, 4]f32
    if main_camera.projection == .Orthographic {
        proj = get_orthographic_projection(main_camera)
    } else {
        proj = get_perspective_projection(main_camera)
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

    m: f32 = 3.33
    if key_is_held(.LeftArrow) {
        main_camera.position.x -= delta_time() * m
    }
    else if key_is_held(.RightArrow) {
        main_camera.position.x += delta_time() * m    
    }

    if key_is_held(.UpArrow) {
        main_camera.position.y += delta_time() * m
    }
    else if key_is_held(.DownArrow) {
        main_camera.position.y -= delta_time() * m    
    }
    
    if v := scroll_directional_vector(.Y); vector_length(v) > 0 {
        main_camera.position.z -= v.y * 0.2
    }

    if mouse_button_is_held(.Middle) {
        main_camera.rotation.y += mouse_directional(.X) * 0.4 * delta_time()
        main_camera.rotation.x += mouse_directional(.Y) * 0.4 * delta_time()
    }

	if key_went_down(.E) {
		//fmt.println("Pressed E LayerOne")
        
        for i in 0..<5 {
            append(&data.instance_data, InstanceData {
                matrix_model(
                quad.position + random_unit_vector_spherical(),
                quad.rotation * RAD_TO_DEG,
                quad.scale
            )})            
        }        
	}

    if key_went_down(.W) {
        main_camera.projection = .Perspective
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
    
    application_new_window(launch_config, SecondaryWindow)
    layer_n := create_test_layer()
    add_layer(&layer_n, 1)

    run()
}
