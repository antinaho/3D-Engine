package main

import "core:log"
import "core:mem"
import "core:math"
import "core:fmt"


import p "pohja"
import r "huuru"

import "core:math/rand"
import "core:time"

Vec3 :: [3]f32

Vec2i :: [2]int

Transform :: struct {
    position: Vec3,
    rotation: Vec3,
    scale:    Vec3,
}

Entity :: struct {
    using transform: Transform,
    color: r.Color,
}

Background_Tile :: struct {
    using _ : Entity,
}

Shape :: struct {
    using _ : Entity,
    kind: r.Shape_Kind,
    ratio: f32,
}

main :: proc() {
    
    // --
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

    p.platform_init(1)
    window_id := p.open_window(1280, 720, "Jeejee")

    r.init(1)
    r_id := r.init_renderer(
        r.Window_Provider {
            data = rawptr(uintptr(window_id)),
            get_size = proc(data: rawptr) -> Vec2i {
                id := p.Window_ID(uintptr(data))
                return p.get_window_size(id)
            },
            get_native_handle = proc(data: rawptr) -> rawptr {
                id := p.Window_ID(uintptr(data))
                return p.get_window_handle(id)
            },
            is_minimized = proc(data: rawptr) -> bool {
                id := p.Window_ID(uintptr(data))
                return p.is_window_minimized(id)
            },
            is_visible = proc(data: rawptr) -> bool {
                id := p.Window_ID(uintptr(data))
                return p.is_window_visible(id)
            },
            sample_count = 1
        }
    )

    shape_pipeline := r.shape_pipeline(r_id)
    r.shape_batcher_init(r_id, context.allocator)
    
    pipeline := r.shape_pipeline(r_id)
    sampler := r.shape_sampler(r_id)
    
    uniform_buffer := r.create_buffer_zeros(
        r_id,
        size_of(r.Uniforms),
        .Vertex,
        .Dynamic,
    )

    s := p.get_window_size(window_id)
    camera := r.Camera {
        position = {0, 0, 1},
        aspect_ratio = f32(s.x) / f32(s.y),
        zoom = 144,
    }

    Shape :: struct {
        using _ : Transform,
        kind: uint,
        ratio: f32,
        alive: bool,
        vel: r.Vec2,
        color: r.Color,
        current: f32,
        delay: f32,
    }

    shapes := make([]Shape, 50_000)

    for &s in shapes {
        s.kind = rand.uint_range(0, 6)
        s.ratio = rand.float32_range(0.01, 1)
        s.vel   = random_unit_vector2() * rand.float32_range(50, 175)
        s.color = {u8(rand.uint32_range(0, 255)), u8(rand.uint32_range(0, 255)), u8(rand.uint32_range(0, 255)), 255}
        s.delay = rand.float32_range(0, 6)
        s.current = s.delay
    }

    cols := 80
    start := -32 * (cols/2)
    cell_size := 32
    bg_tiles: [80 * 80]Background_Tile
    for &tile, i in bg_tiles {
        row := i / cols
        col := i % cols
        x := start + col * cell_size
        y := start + row * cell_size
        is_even := (row + col) % 2 == 0
        
        tile.color = r.Color {80, 80, 80, 255} if is_even else r.Color {120, 120, 120, 255}
        tile.position = {f32(x), f32(y), 0} 
    }
    
    f : int = 0

    for p.platform_update() {
        f += 1
        r.clear_commands()
        r.shape_batch_begin_frame()

        update_camera(&camera)


        
        r.cmd_begin_frame({r_id})

        view := r.mat4_view(camera.position, camera.position + r.VECTOR3_FORWARD, r.VECTOR3_UP)
        proj := r.mat4_ortho_fixed_height(camera.zoom, camera.aspect_ratio)
        uniforms := r.Uniforms{ view_projection = proj * view }
        r.push_buffer(r_id, uniform_buffer, &uniforms, 0, size_of(r.Uniforms), .Dynamic)
        
        
        r.cmd_bind_pipeline({r_id, shape_pipeline})
        r.cmd_bind_sampler({r_id, sampler, 0})

        r.cmd_bind_vertex_buffer(r.Render_Command_Bind_Vertex_Buffer{
            id = r_id,
            buffer_id = uniform_buffer,
            index = 2,
            offset = 0
        })

        //r.draw_rect({0, 0}, 0, {16, 16}, {255, 100, 100, 255})      // Red rectangle
        //r.draw_circle({-60, 0}, 16, {100, 255, 100, 255})             // Green circle
        //r.draw_triangle({0, 50}, 0, 60, {100, 100, 255, 255})           // Blue triangle
        //r.draw_donut({0, -20}, 20, 0.5, {255, 255, 100, 255})          // Yellow donut
        //r.draw_hollow_rect({0, 20}, 0, {60, 60}, 0.1, {255, 100, 255, 255})  // Pink hollow rect



        for tile in bg_tiles {
            r.draw_rect(
                position = tile.position.xy,
                rotation = 0,
                size     = {32, 32},
                color    = tile.color
            )
        }
        
        for &s in shapes {
            
            if f > 2000 {
                s.kind = rand.uint_range(0, 6)
                s.ratio = rand.float32_range(0, 1)
                s.vel   = random_unit_vector2() * rand.float32_range(70, 150)
                s.color = {u8(rand.uint32_range(0, 255)), u8(rand.uint32_range(0, 255)), u8(rand.uint32_range(0, 255)), 255}
                s.position = {0, 0, 0}
                s.current = s.delay
            }

            s.current -=  ns_to_f32(p.get_deltatime_ns())
            if s.current > 0 {
                continue
            }

            s.position.xy += ns_to_f32(p.get_deltatime_ns()) * s.vel
            s.rotation.z += ns_to_f32(p.get_deltatime_ns()) * s.ratio * 1.3
            switch s.kind {
                case 0:
                    r.draw_rect(
                        position = s.position.xy,
                        rotation = s.rotation.z,
                        size     = {32, 32},
                        color    = s.color
                    )
                case 1:
                    r.draw_circle(
                        position = s.position.xy,
                        radius = 16,
                        color = s.color
                    )
                case 2:
                    r.draw_donut(
                        position = s.position.xy,
                        radius = 16,
                        inner_radius_ratio = s.ratio,
                        color = s.color
                    )
                case 3:
                    r.draw_triangle(
                        position = s.position.xy,
                        rotation = s.rotation.z,
                        size = 32,
                        color = s.color
                    )
                case 4:
                    r.draw_hollow_rect(
                        position = s.position.xy,
                        rotation = s.rotation.z,
                        size = {32, 32},
                        thickness = s.ratio,
                        color = s.color
                    )
                case 5:
                    r.draw_hollow_triangle(
                        position = s.position.xy,
                        rotation = s.rotation.z,
                        size = 32,
                        thickness = s.ratio,
                        color = s.color
                    )

            }
        }

        if f > 2000 {
            f = 0
        }

        // p.set_window_title(0, fmt.tprintf("FPS: %.2f", 1 / ns_to_f32(p.get_deltatime_ns())) )
     

        r.flush_shapes_batch()        
        r.cmd_end_frame({r_id})
        r.present()
        
        f += 1
    }

    p.cleanup()
}

Vector2 :: [2]f32
random_unit_vector2 :: proc() -> Vector2 {
    theta := rand.float32() * (2.0 * math.PI)
    return { math.cos(theta), math.sin(theta) }
}

ns_to_f32 :: proc(t: i64) -> f32 {
    return f32(t) / 1_000_000_000
}

update_camera :: proc(camera: ^r.Camera) {
    camera_ms: f32 = 450
    if p.input_key_is_held(.A) {
        camera.position.x -= ns_to_f32(p.get_deltatime_ns()) * camera_ms
    }
    if p.input_key_is_held(.D) {
        camera.position.x += ns_to_f32(p.get_deltatime_ns()) * camera_ms
    }

    if p.input_key_is_held(.W) {
        camera.position.y += ns_to_f32(p.get_deltatime_ns()) * camera_ms
    }
    if p.input_key_is_held(.S) {
        camera.position.y -= ns_to_f32(p.get_deltatime_ns()) * camera_ms
    }

    zoom_speed: f32 = 500
    if p.input_key_is_held(.Q) {
        camera.zoom += ns_to_f32(p.get_deltatime_ns()) * zoom_speed
    }
    if p.input_key_is_held(.E) {
        camera.zoom -= ns_to_f32(p.get_deltatime_ns()) * zoom_speed
    }

    camera.aspect_ratio = f32(p.get_window_size(0).x) / f32(p.get_window_size(0).y)
    
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

