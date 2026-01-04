package main

import "core:log"
import "core:mem"
import "core:math"


// DebugLayerData :: struct {
//     vertex_buf: Buffer,
//     index_buf: Buffer,
//     instance_buf: Buffer,

//     grid_texture: Texture,
// }

// _debug_attach :: proc(layer: ^Layer) {
//     data := cast(^DebugLayerData)layer.data

//     data^ = {
//         vertex_buf = init_buffer_with_size(size_of(Vertex) * 4, .Vertex, .Static),
//         index_buf = init_buffer_with_size(size_of(u32) * 6, .Vertex, .Static),
//         instance_buf = init_buffer_with_size(size_of(InstanceData), .Vertex, .Dynamic),
//         grid_texture = load_texture({
//             filepath = "textures/PNG/Dark/texture_01.png",
//             format = .RGBA8_UNorm
//         })
//     }
// }

// _debug_render :: proc(layer: ^Layer, command_buffer: ^CommandBuffer) {
//     data := cast(^DebugLayerData)layer.data
// }


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
    d := cast(^TestLayerData)layer.data
    d^ = {
        default_renderer = init_default_renderer(),
        vertex_buf = init_buffer_with_size(size_of(Vertex) * 1000, .Vertex, .Dynamic),
        instance_buf = init_buffer_with_size(size_of(InstanceData) * 1000, .Vertex, .Dynamic),
        index_buf = init_buffer_with_size(size_of(u32) * 1000, .Index, .Dynamic),
        instance_data = make([dynamic]InstanceData),
    }

    entities = make(map[EntityType][dynamic]^Entity)
}

_detach :: proc(layer: ^Layer) {
    d := cast(^TestLayerData)layer.data

    for k, &e in entities {
        for i in e {
            free(i)
        }
        delete(e)
    }
    delete(entities)

    free(d.default_renderer.pipeline.handle)
    release_buffer(&d.vertex_buf)
    release_buffer(&d.instance_buf)
    release_buffer(&d.index_buf)
    delete(d.instance_data)
    free(d)
}


import "core:math/rand"
_update :: proc(layer: ^Layer, delta: f32) {
    for k, ents in entities {
        for &e in ents {
            e.rotation.z += rand.float32() * delta
        }
    }
}

_render :: proc(layer: ^Layer, renderer: ^Renderer, command_buffer: ^CommandBuffer) {

    main_camera.aspect = f32(renderer.msaa_texture.desc.width) / f32(renderer.msaa_texture.desc.height)

    data := cast(^TestLayerData)layer.data
    cmd_update_renderpass_descriptors(command_buffer, Update_Renderpass_Desc{
        msaa_texture = renderer.msaa_texture,
        depth_texture = renderer.depth_texture,
    })

    cmd_begin_pass(command_buffer, "Test")
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
                aspect=main_camera.aspect,
                near=main_camera.near,
                far=main_camera.far,
            )
    }
    
    scene_uniforms := SceneUniformData {
        view = view,
        projection = proj,
    }

    InstanceBatch :: struct {
        offset: int,    
        count: int,     
    }

    cmd_set_uniform(command_buffer, scene_uniforms, 1, .Vertex)
    clear(&data.instance_data)
    batches := make(map[EntityType]InstanceBatch, context.temp_allocator)
    
    {
        for entity_type, ents in entities {
            if len(ents) == 0 do continue
            offset := len(data.instance_data)
            for e in ents {
                model := mat4_model(e.position, e.rotation, e.scale)
                append(&data.instance_data, InstanceData{model, {1, 1}, {0, 0}})
            }
            batches[entity_type] = InstanceBatch{
                offset = offset,
                count = len(ents),
            }
        }

        fill_buffer(
            &data.instance_buf,
            raw_data(data.instance_data),
            size_of(InstanceData) * len(data.instance_data),
            0,
        )

        for entity_type, ents in entities {
            batch := batches[entity_type]
            if batch.count == 0 do continue

            fill_buffer(&data.vertex_buf, raw_data(vertices_of(entity_type)), size_of(Vertex) * len(vertices_of(entity_type)), 0)
            fill_buffer(&data.index_buf, raw_data(indices_of(entity_type)), size_of(u32) * len(indices_of(entity_type)), 0)
            
            cmd_bind_vertex_buffer(command_buffer, data.vertex_buf, 0, 0)
            cmd_bind_vertex_buffer(command_buffer, data.instance_buf, batch.offset * size_of(InstanceData), 2)
            cmd_bind_index_buffer(command_buffer, data.index_buf, 0)
            
            cmd_bind_texture(command_buffer, data.default_renderer.custom_texture, 0, .Fragment)
            cmd_bind_sampler(command_buffer, data.default_renderer.default_sampler, 0, .Fragment)
            
            cmd_draw_indexed_with_instances(
                command_buffer,
                len(indices_of(entity_type)),
                data.index_buf,
                batch.count,  
            )

        }
        cmd_end_pass(command_buffer)
    }
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
        log.debug("E")        
        for i in 0..<5 {

            quad := new_entity(Quad)
            quad.mesh = &quad_mesh
            quad.position = random_unit_vector_spherical() + VECTOR_RIGHT * 2
            quad.rotation = {}
            quad.scale = {1, 1, 1}


            if raw_data(entities[.Quad]) == nil {
                entities[.Quad] = make([dynamic]^Entity)
            }

            append(&entities[.Quad], quad)          
        }
	}

    if input_key_went_down(.Q) {
        log.debug("E")        
        for i in 0..<5 {

            triangle := new_entity(Triangle)
            triangle.mesh = &triangle_mesh
            triangle.position = random_unit_vector_spherical() + VECTOR_RIGHT * -2
            triangle.rotation = {}
            triangle.scale = {1, 1, 1}


            if raw_data(entities[.Triangle]) == nil {
                entities[.Triangle] = make([dynamic]^Entity)
            }

            append(&entities[.Triangle], triangle)          
        }
	}
}

EntityType :: enum {
    Quad,
    Triangle,
}

vertices_of :: proc(e: EntityType) -> []Vertex {

    switch e {
        case .Quad:
            return quad_mesh.verteces
        case .Triangle:
            return triangle_mesh.verteces
    }
    log.panic("")
}

indices_of :: proc(e: EntityType) -> []u32 {

    switch e {
        case .Quad:
            return quad_mesh.indices
        case .Triangle:
            return triangle_mesh.indices

    }
    log.panic("")
}

entities: map[EntityType][dynamic]^Entity

new_entity :: proc($T: typeid) -> ^Entity {
    t := new(T)
    t.derived = t^
    return t
}

Quad :: struct {
    using _ : Entity,
    vel: Vector3,
}

Triangle :: struct {
    using _ : Entity,
}

Entity :: struct {
    using transform: Transform,
    mesh: ^Mesh,
    derived: any,
}

Transform :: struct {
    position: Vector3,
    rotation: Vector3,
    scale:    Vector3,
}

Mesh :: struct {
    verteces: []Vertex,
    indices: []u32,
    material: Material,
}

BaseMaterial :: Material {
    scale = {1, 1},
    offset = {0, 0},
    tex_indices = 1 << 0,
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
    material = BaseMaterial,
}
@(rodata)
quad_mesh := QuadMesh

TriangleMesh :: Mesh {
    verteces = []Vertex {
        {position={-0.5, -0.5, 0}, normal={0,0,1}, color={1,1,1,1}, uvs={0,0}},
        {position={ 0.5, -0.5, 0}, normal={0,0,1}, color={1,1,1,1}, uvs={1,0}},
        {position={ 0.5,  0.5, 0}, normal={0,0,1}, color={1,1,1,1}, uvs={1,1}},
    },
    indices = []u32 {
        0, 1, 2
    },
}
triangle_mesh := TriangleMesh


InstanceData :: struct #align(16) {
    model:      matrix[4, 4]f32,
    texture_scale: [2]f32,
    texture_offset: [2]f32,
}

SceneUniformData :: struct #align(16) {
    view:        matrix[4, 4]f32,
    projection:  matrix[4, 4]f32,
}

MaterialUniformData :: struct #align(16) {

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

