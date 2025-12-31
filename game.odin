package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:math"

TestLayer := Layer {
	ingest_events = _events,
	update = _update,
}

import "core:math/rand"

_events :: proc(input: ^WindowInput) {

    m: f32 = 3.33
    if key_is_held(input, .LeftArrow) {
        main_camera.position.x -= delta * m
    }
    else if key_is_held(input, .RightArrow) {
        main_camera.position.x += delta * m    
    }

    if key_is_held(input, .UpArrow) {
        main_camera.position.y += delta * m
    }
    else if key_is_held(input, .DownArrow) {
        main_camera.position.y -= delta * m    
    }
    




	if key_went_down(input, .E) {
		//fmt.println("Pressed E LayerOne")
        
        for i in 0..<5 {
            append(&instance_data, InstanceData {
                matrix_model(
                quad.position + random_unit_vector_spherical(),
                quad.rotation * RAD_TO_DEG,
                quad.scale
            )})            
        }        
	}

    if key_went_down(input, .W) {
        main_camera.projection = .Perspective
    }
}

vertex_buf: Buffer
index_buf: Buffer
instance_buf: Buffer

RAD_TO_DEG :: math.RAD_PER_DEG
DEG_TO_RAD :: math.DEG_PER_RAD

Vector2 :: [2]f32
Vector3 :: [3]f32

VECTOR_RIGHT   :: Vector3 {1, 0,  0}
VECTOR_UP      :: Vector3 {0, 1,  0}
VECTOR_FORWARD :: Vector3 {0, 0, -1}

Position :: Vector3
Rotation :: Vector3
Scale    :: Vector3

random_unit_vector_spherical :: proc() -> [3]f32 {
    // Random angles
    theta := rand.float32_range(0, math.TAU)          // Azimuth [0, 2π]
    phi := math.acos(rand.float32_range(-1, 1))       // Polar angle via cosine distribution
    
    sin_phi := math.sin(phi)
    
    return [3]f32{
        sin_phi * math.cos(theta),  // X
        sin_phi * math.sin(theta),  // Y
        math.cos(phi),               // Z
    }
}

Entity :: struct {
    using transform: Transform,
    mesh: ^Mesh,
    vel: Vector3,
}

Transform :: struct {
    position: Position,
    rotation: Rotation,
    scale:    Scale,
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

instance_data: [dynamic]InstanceData

get_camera_target :: proc(camera: Camera) -> [3]f32 {

    rad_rotation := camera.rotation * DEG_TO_RAD
    forward := [3]f32{
        math.cos(rad_rotation.y) * math.cos(rad_rotation.x),
        math.sin(rad_rotation.x),                                 
        math.sin(rad_rotation.y) * math.cos(rad_rotation.x),
    }
    
    return camera.position + forward
}
import "core:math/linalg"
update_camera_vectors :: proc(camera: ^Camera) {
    camera.forward = linalg.normalize([3]f32{
        math.cos(camera.rotation.y) * math.cos(camera.rotation.x),
        math.sin(camera.rotation.x),
        math.sin(camera.rotation.y) * math.cos(camera.rotation.x),
    })
    camera.right = linalg.normalize(linalg.cross(camera.forward, VECTOR_UP))
    camera.up = linalg.normalize(linalg.cross(camera.right, camera.forward))
}


_update :: proc(delta: f32) {
    main_camera.rotation.y = -math.PI/2
    update_camera_vectors(&main_camera)

    cmd_update_renderpass_descriptors(&cmd_buffer, Update_Renderpass_Desc{
        renderpass_descriptor=render_pass_3d.renderpass_descriptor,
        msaa_texture = render_pass_3d.msaa_render_target_texture,
        depth_texture = render_pass_3d.depth_texture,
    })

    cmd_begin_pass(&cmd_buffer, "Test", render_pass_3d.renderpass_descriptor)
    cmd_set_pipeline(&cmd_buffer, render_pass_3d.pipeline)

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
    cmd_set_uniform(&cmd_buffer, uniforms, 1, .Vertex)

    if len(instance_data) == 0 {
        cmd_end_pass(&cmd_buffer)
        return
    }

    fill_buffer(&vertex_buf, raw_data(QuadMesh.verteces), size_of(Vertex) * len(QuadMesh.verteces), 0)
    fill_buffer(&index_buf,  raw_data(QuadMesh.indices),  size_of(u32) * len(QuadMesh.indices), 0)
    fill_buffer(&instance_buf, raw_data(instance_data), size_of(InstanceData) * len(instance_data), 0)

    cmd_bind_vertex_buffer(&cmd_buffer, vertex_buf, 0, 0)
    cmd_bind_vertex_buffer(&cmd_buffer, instance_buf, 0, 2)
    cmd_bind_index_buffer(&cmd_buffer, index_buf, 0)
    cmd_bind_texture(&cmd_buffer, render_pass_3d.custom_texture, 0, .Fragment)
    cmd_bind_sampler(&cmd_buffer, render_pass_3d.default_sampler, 0, .Fragment)

    cmd_draw_indexed_with_instances(&cmd_buffer, len(QuadMesh.indices), index_buf, len(instance_data))

    cmd_end_pass(&cmd_buffer)
}

InstanceData :: struct #align(16) {
    model:      matrix[4, 4]f32,
}

UniformData :: struct #align(16) {
    view:        matrix[4, 4]f32,
    projection:  matrix[4, 4]f32,
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

    add_layer(app_window, TestLayer)

    run()
}
