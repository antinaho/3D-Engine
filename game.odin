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

Direction :: enum {
    Up,
    Down,
    Left,
    Right,
}

Worker :: struct {
    using transform: Transform,
    kind: Worked_Kind,
}

Worked_Kind :: enum {
    Farmer,
}

hit_side :: proc(going_dir: Direction, velocity: ^Vector2, kind: Worked_Kind) {
    switch kind {
        case .Farmer:
            switch going_dir {
                case .Up, .Down:
                    velocity.y *= -1
                case .Left, .Right:
                    velocity.x *= -1
            }
    }
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
    start := -16 * (cols/2)
    cell_size := 16
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

    data, w, h := r.load_tex("textures/face.jpg")
    tex_id := r.create_texture(r_id, r.Texture_Desc {
        data = data,
        width = w,
        height = h,
        format = .RGBA8,
    })
    face_id := r.register_shape_texture(tex_id)

    pos: Vector2
    limit_low := Vector2 {-TILE_UNIT * 2 - TILE_UNIT * 0.5, -TILE_UNIT * 2 - TILE_UNIT * 0.5}
    limit_high := Vector2 {TILE_UNIT * 2 + TILE_UNIT * 0.5, TILE_UNIT * 2 + TILE_UNIT * 0.5}
    velocity := random_unit_vector2()

    for p.platform_update() {
        f += 1
        r.clear_commands()
        r.shape_batch_free_all()

        update_camera(&camera)
        
        r.cmd_begin_frame({r_id})

        pixels_vertical: f32 = 144
        ratio := f32(p.get_window_height(window_id)) / pixels_vertical
        

        view := r.mat4_view(camera.position, camera.position + r.VECTOR3_FORWARD, r.VECTOR3_UP)
        proj := r.mat4_ortho_fixed_height(camera.zoom, camera.aspect_ratio)
        r.set_shape_view_projection(proj * view)
        
        r.cmd_bind_pipeline({r_id, shape_pipeline})
        r.cmd_bind_sampler({r_id, sampler, 0})
        

        for tile in bg_tiles {
            r.draw_rect(
                position = tile.position.xy,
                rotation = 0,
                size     = {16, 16},
                color    = tile.color
            )
        }


        r.draw_rect(
            {-6, 3} * TILE_UNIT,
            0,
            {16, 16},
            color = RED,
        )

        r.draw_rect(
            {-6, 1} * TILE_UNIT,
            1e-9 * f32(p.get_runtime_ns()),
            {16, 16},
            color = RED,
        )

        r.draw_hollow_rect(
            {-3, 3} * TILE_UNIT,
            0,
            {16, 16},
            0.45,
            color = RED,
        )

        r.draw_hollow_rect(
            {-3, 1} * TILE_UNIT,
            1e-9 * f32(p.get_runtime_ns()),
            {16, 16},
            0.45,
            color = RED,
        )

        r.draw_triangle(
            {0, 3} * TILE_UNIT,
            1e-9 * f32(p.get_runtime_ns()),
            16,
            color = RED,
        )


        r.draw_hollow_triangle(
            {0, 1} * TILE_UNIT,
            1e-9 * f32(p.get_runtime_ns()),
            16,
            0.45,
            color = RED,
        )

        r.draw_circle(
            {-6, -1} * TILE_UNIT,
            8,
            color = RED,
        )

        r.draw_donut(
            {-6, -3} * TILE_UNIT,
            8,
            0.8,
            color = RED,
        )




        // r.draw_rect(
        //     position = Vector2{1, 1} * TILE_UNIT,
        //     rotation = 0,
        //     size     = {16, 16},
        //     color    = RED
        // )

        // center_pos := Vector2{0, 0} * TILE_UNIT
        // center_size := Vector2{16, 16}
        // r.draw_rect(
        //     position = center_pos,
        //     rotation = 0,
        //     size     = center_size,
        //     color    = GREEN
        // )

        // pos += f32(p.get_deltatime_f64()) * 50 * velocity
        // if pos.x >= limit_high.x - 2 { hit_side(.Right, &velocity, .Farmer) }
        // if pos.y >= limit_high.y - 2 { hit_side(.Up, &velocity, .Farmer) }
        // if pos.x <= limit_low.x + 2  { hit_side(.Left, &velocity, .Farmer) }
        // if pos.y <= limit_low.y + 2  { hit_side(.Down, &velocity, .Farmer) }

        // pos.x = math.clamp(pos.x, limit_low.x + 2, limit_high.x - 2)
        // pos.y = math.clamp(pos.y, limit_low.y + 2, limit_high.y - 2)

        // r.draw_rect(
        //     position = pos,
        //     rotation = 0,
        //     size     = {4, 4},
        //     color    = BLUE
        // )

        l_end := Vector2 { math.sin_f32(1e-9 * f32(p.get_runtime_ns())), math.cos_f32(1e-9 * f32(p.get_runtime_ns())) }
        
        r.draw_line({0,0}, l_end * 64, 0.2, r.WHITE)

        r.draw_bezier_quadratic({0, 0}, {l_end.x * -1, l_end.y} * 64, -l_end * 64, 1, r.BLACK)
        //r.draw_line({0,0}, {0, -64}, 8, r.WHITE)
        
        p.set_window_title(window_id, fmt.tprintf("%.2f", p.get_fps()))


        // uniforms := r.Uniforms{
        //     view_projection = proj * view,
        // }
        // r.push_buffer(r_id, uniform_buffer, &uniforms, 0, size_of(r.Uniforms), .Dynamic)

        r.flush_shapes_batch()        
        r.cmd_end_frame({r_id})
        r.present()
        
        f += 1
    }

    p.cleanup()
}

TILE_UNIT :: 16
RED :: [4]byte{160, 75, 75, 255}
GREEN :: [4]byte{75, 160, 75, 255}
BLUE :: [4]byte{75, 75, 170, 255}

Vector2 :: [2]f32
random_unit_vector2 :: proc() -> Vector2 {
    theta := rand.float32() * (2.0 * math.PI)
    return { math.cos(theta), math.sin(theta) }
}

update_camera :: proc(camera: ^r.Camera) {
    camera_ms: f32 = 450
    if p.input_key_is_held(.A) {
        camera.position.x -= f32(p.get_deltatime_f64()) * camera_ms
    }
    if p.input_key_is_held(.D) {
        camera.position.x += f32(p.get_deltatime_f64()) * camera_ms
    }

    if p.input_key_is_held(.W) {
        camera.position.y += f32(p.get_deltatime_f64()) * camera_ms
    }
    if p.input_key_is_held(.S) {
        camera.position.y -= f32(p.get_deltatime_f64()) * camera_ms
    }

    zoom_speed: f32 = 500
    if p.input_key_is_held(.Q) {
        camera.zoom += f32(p.get_deltatime_f64()) * zoom_speed
    }
    if p.input_key_is_held(.E) {
        camera.zoom -= f32(p.get_deltatime_f64()) * zoom_speed
    }

    if p.input_key_went_down(.N1) {
        camera.zoom = 144
    }
    if p.input_key_went_down(.N2) {
        camera.zoom = 144 * 2
    }

    camera.aspect_ratio = f32(p.get_window_size(0).x) / f32(p.get_window_size(0).y)    
}

Rect :: struct {
    center_position: Vector2,
    extents: Vector2
}

rect_intersect :: proc(rect_one, rect_two: Rect) -> bool {
    return rect_one.center_position.x + rect_one.extents.x > rect_two.center_position.x - rect_two.extents.x &&
           rect_one.center_position.x - rect_one.extents.x < rect_two.center_position.x + rect_two.extents.x &&
           rect_one.center_position.y + rect_one.extents.y > rect_two.center_position.y - rect_two.extents.y &&
           rect_one.center_position.y - rect_one.extents.y < rect_two.center_position.y + rect_two.extents.y
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

