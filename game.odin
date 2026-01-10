package main

import "core:log"
import "core:mem"
import "core:math"
import "core:fmt"

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

_update :: proc(layer: ^Layer, delta: f32) {
    for k, ents in entities {

        for &e in ents {
            //e.rotation.y += delta * 10
        }
    }
}

_render :: proc(layer: ^Layer, renderer: ^Renderer, command_buffer: ^CommandBuffer) {

    ortho_camera.aspect = f32(renderer.msaa_texture.desc.width) / f32(renderer.msaa_texture.desc.height)

    data := cast(^TestLayerData)layer.data
    cmd_update_renderpass_descriptors(command_buffer, Update_Renderpass_Desc{
        msaa_texture = renderer.msaa_texture,
        depth_texture = renderer.depth_texture,
    })

    cmd_begin_pass(command_buffer, "Test")
    cmd_set_pipeline(command_buffer, data.default_renderer.pipeline)

    view: matrix[4,4]f32
    proj: matrix[4,4]f32
    
    view = mat4_view(
                eye=ortho_camera.position,
                target=ortho_camera.position + VECTOR_FORWARD,
                up=VECTOR_UP
            )
    proj = mat4_ortho_fixed_height(10, ortho_camera.aspect)

            // proj = mat4_perspective_projection(
            //     fov_y_radians=DEG_TO_RAD*main_camera.fov,
            //     aspect=main_camera.aspect,
            //     near=main_camera.near,
            //     far=main_camera.far,
            // )
    
    scene_uniforms := SceneUniformData {
        view = view,
        projection = proj,
    }

    cmd_set_uniform(command_buffer, scene_uniforms, 1, .Vertex)
    clear(&data.instance_data)

    InstanceBatch :: struct {
        offset: int,    
        count: int,     
    }
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

ortho_camera := Camera {
    position = {0, 0, 1},
    aspect = 16.0 / 9.0,
    zoom = 20,
}


_events :: proc(layer: ^Layer) {
    data := cast(^TestLayerData)layer.data

    m: f32 = 2.75
    if input_key_is_held(.A) {
        ortho_camera.position -= right_from_euler(ortho_camera.rotation*DEG_TO_RAD) * delta_time() * m
    }
    if input_key_is_held(.D) {
        ortho_camera.position += right_from_euler(ortho_camera.rotation*DEG_TO_RAD) * delta_time() * m
    }

    if input_key_is_held(.W) {
        ortho_camera.position += up_from_euler(ortho_camera.rotation*DEG_TO_RAD) * delta_time() * m
    }
    if input_key_is_held(.S) {
        ortho_camera.position -= up_from_euler(ortho_camera.rotation*DEG_TO_RAD) * delta_time() * m
    }

	if input_key_went_down(.E) {
        log.debug("E")        
        for i in 0..<5 {

            quad := new_entity(Quad)
            quad.mesh = &quad_mesh
            quad.position = random_unit_vector_spherical()// + VECTOR_RIGHT * 2
            quad.rotation = {0, 0, 0} // {0, 270, 0}
            quad.scale = {1, 1, 1}


            if raw_data(entities[.Quad]) == nil {
                entities[.Quad] = make([dynamic]^Entity)
            }

            append(&entities[.Quad], quad)          
        }
	}

    if input_key_went_down(.Q) {
        log.debug("Q")        
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
    texture_scale = {1, 1},
    texture_offset = {0, 0},
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
    material = BaseMaterial,
}
@(rodata)
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

//






//









import p "pohja"
import r "huuru"

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

    p.init(1)

    id := p.open_window(p.Window_Description {
        flags = {.MainWindow, .CenterOnOpen},
        width = 600,
        height = 600,
        title = "Hellope",
    })


    r.init(1)
    r_id := r.init_renderer(r.Window_Provider{
        window_id = rawptr(uintptr(id)),
        get_size = proc(id: rawptr) -> [2]int {
            wid := p.Window_ID(uintptr(id))
            return p.PLATFORM_API.get_window_size(wid)
        },
        get_native_handle = proc(id: rawptr) -> rawptr {
            return rawptr(p.get_native_window_handle(p.Window_ID(uintptr(id))))
        },
    })
    r.set_clear_color(r_id, {50.0 / 255, 40.0 / 255, 70.0 / 255, 1})

    pipeline := r.create_pipeline(r_id, r.Pipeline_Desc{
        vertex_shader = `
            using namespace metal;
            vertex float4 vertex_main(uint vid [[vertex_id]],
                                    const device float4* positions [[buffer(0)]]) {
                return float4(positions[vid].xyz, 1.0);
            }
        `,
        fragment_shader = `

            using namespace metal;
            fragment float4 fragment_main() {
                return float4(1.0, 0.0, 0.0, 1.0);
            }
        `,
        vertex_layout = r.Vertex_Layout{
            stride = size_of([4]f32),
            attributes = []r.Vertex_Attribute{
                {format = .Float4, offset = 0},
            },
        },
    })

    vertices := [?][4]f32{
        { 0.0,  0.5, 0.0, 0.0},  // top
        {-0.5, -0.5, 0.0, 0.0},  // bottom left
        { 0.5, -0.5, 0.0, 0.0},  // bottom right
    }

    a := cast(^r.Renderer_State_Header)r.get_state_from_id(r_id)
    r.push_buffer(r_id, a.vertex_buffer, &vertices, 0, size_of(vertices))

    for !p.platform_should_close() {
        p.platform_update()
        r.begin_frame(r_id)
        r.bind_pipeline(r_id, pipeline)
        r.draw(r_id, a.vertex_buffer, 3)
        r.end_frame(r_id)
    }

    p.cleanup()
}


reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> (err: bool) {
	fmt.println("Tracking allocator: ")

	for _, val in a.allocation_map {
		fmt.printfln("%v: Leaked %v bytes", val.location, val.size)
		err = true
	}

	mem.tracking_allocator_clear(a)

	return
}

