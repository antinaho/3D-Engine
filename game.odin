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

    bg_tex_data, bg_w, bg_h := r.load_tex("textures/Free/Background/Blue.png")
    bg_tex_id := r.create_texture(r_id, r.Texture_Desc {
        data   = bg_tex_data,
        width  = bg_w,
        height = bg_h,
        format = .RGBA8,
    })

    terrain_tex_data, terrain_w, terrain_h := r.load_tex("textures/Free/Terrain/Terrain (16x16).png")
    terrain_tex_id := r.create_texture(r_id, r.Texture_Desc {
        data   = terrain_tex_data,
        width  = terrain_w,
        height = terrain_h,
        format = .RGBA8,
    })

    dude_tex_data, dude_w, dude_h := r.load_tex("textures/Free/Traps/Sand Mud Ice/Mud Particle.png")
    dude_tex_id := r.create_texture(r_id, r.Texture_Desc {
        data   = dude_tex_data,
        width  = dude_w,
        height = dude_h,
        format = .RGBA8,
    })

    enemy_tex_data, enemy_w, enemy_h := r.load_tex("textures/Free/Traps/Rock Head/Idle.png")
    enemy_tex_id := r.create_texture(r_id, r.Texture_Desc {
        data   = enemy_tex_data,
        width  = enemy_w,
        height = enemy_h,
        format = .RGBA8,
    })

    


    pixel_sampler := r.create_sampler(r_id, r.Sampler_Desc {
        mag_filter = .Linear,
        min_filter = .Linear,
        wrap_s = .ClampToEdge,
        wrap_t = .ClampToEdge,
    })
    
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
        zoom = 900,
    }

    f : int = 0
    last_rot_p: Vec3
    last_rot_n: Vec3
    previous_time := time.tick_now()
    runtime: f32

    
    rock_vel := random_unit_vector2() * 500

    rock := Transform {
        position = {0, 200, 0.1},
        scale = {32 * 4, 32 * 4, 1}
    }

    player_vel := Vector2 {0, 0}
    player := Transform {
        position = {0, -100, 0.1},
        scale = {32 * 4, 32 * 4, 1}
    }

    update_rock :: proc(t: ^Transform, vel: ^Vector2) {
        t.position.xy += ns_to_f32(p.get_deltatime_ns()) * vel^

        if t.position.x < -385 + t.scale.x * 0.5 || t.position.x > 385 - t.scale.x * 0.5 {
            t.position.x = clamp(t.position.x, -385 + t.scale.x * 0.5, 385 - t.scale.x * 0.5)
            vel.x *= -1
        }
    
        if t.position.y < -385 + t.scale.y * 0.5 || t.position.y > 385 - t.scale.y * 0.5 {
            t.position.y = clamp(t.position.y, -385 + t.scale.y * 0.5, 385 - t.scale.y * 0.5)
            vel.y *= -1
        }
    }

    update_player :: proc(t: ^Transform) {
        player_ms: f32 = 425
        if p.input_key_is_held(.A) {
            t.position.x -= ns_to_f32(p.get_deltatime_ns()) * player_ms
        }
        if p.input_key_is_held(.D) {
            t.position.x += ns_to_f32(p.get_deltatime_ns()) * player_ms
        }
    
        if p.input_key_is_held(.W) {
            t.position.y += ns_to_f32(p.get_deltatime_ns()) * player_ms
        }
        if p.input_key_is_held(.S) {
            t.position.y -= ns_to_f32(p.get_deltatime_ns()) * player_ms
        }

        t.position.x = clamp(t.position.x, -385 + t.scale.x * 0.5, 385 - t.scale.x * 0.5)
        t.position.y = clamp(t.position.y, -385 + t.scale.y * 0.5, 385 - t.scale.y * 0.5)
    }

    inside :: proc(t1, t2: ^Transform) -> bool {
        right_p := t1.position + t1.scale.x * 0.25
        left_p :=  t1.position - t1.scale.x * 0.25
        right_r := t2.position + t2.scale.x * 0.4
        left_r :=  t2.position - t2.scale.x * 0.4

        up_p :=   t1.position + t1.scale.y * 0.25
        down_p := t1.position - t1.scale.y * 0.25
        up_r :=   t2.position + t2.scale.y * 0.4
        down_r := t2.position - t2.scale.y * 0.4

        return right_p.x > left_r.x && left_p.x < right_r.x &&
               up_p.y > down_r.y && down_p.y < up_r.y
    }

    lost := false
    opacity: f32 = 1.0
    for p.platform_update() {
        r.clear_commands()
        
        r.shape_batch.instance_offset = 0
        r.shape_batch.instance_count = 0

        update_camera(&camera)

        if inside(&player, &rock) {
            player_vel = 0
            rock_vel = 0
            lost = true
        }

        if !lost {
            update_player(&player)
            //update_rock(&rock, &rock_vel)
            rock.rotation.z += ns_to_f32(p.get_deltatime_ns()) * 0.5
            rock_vel.xy *= 1 + (ns_to_f32(p.get_deltatime_ns()) * 0.11)
        }
        

        view := r.mat4_view(camera.position, camera.position + r.VECTOR3_FORWARD, r.VECTOR3_UP)
        proj := r.mat4_ortho_fixed_height(camera.zoom, camera.aspect_ratio)
        uniforms := r.Uniforms{ view_projection = proj * view }
        r.push_buffer(r_id, uniform_buffer, &uniforms, 0, size_of(r.Uniforms), .Dynamic)


        r.cmd_begin_frame({r_id})

        r.cmd_bind_pipeline({r_id, shape_pipeline})

        r.cmd_bind_vertex_buffer(r.Render_Command_Bind_Vertex_Buffer{
            id = r_id,
            buffer_id = uniform_buffer,
            index = 1,
            offset = 0
        })

        r.cmd_bind_sampler({id =r_id, sampler =pixel_sampler, slot=0})

        full_uv := r.UV_Rect{
            min = {0, 0},
            max = {1, 1}
        }

        for x in -5..=5 {
            for y in -5..=5 {                
                r.draw_rect(
                    position = {f32(x) * 64 , f32(y) * 64},
                    rotation = 0,
                    size     = {64, 64},
                    color    = {255, 255, 255, 255}
                )
                // r.draw_batched(sprite_batch, r.Draw_Batched{
                //     texture  = bg_tex_id,
                //     position = {f32(x) * 64 , f32(y) * 64, 0},
                //     rotation = {0, 0, 0},
                //     uv_rect  = full_uv,
                //     scale    = {64, 64, 1},
                //     color    = {255, 255, 255, 255},
                // })
            }
        }

        // 352 × 176
        terrain_block_uv := r.UV_Rect {
            min = {(12 * 16) / 352.0, 16 / 176.0},
            max = {(13 * 16) / 352.0, 32 / 176.0}
        }

        // for x in -6..=6 {
        //     r.draw_batched(sprite_batch, r.Draw_Batched{
        //         texture  = terrain_tex_id,
        //         position = {64 * f32(x), -64 * 6, 0},
        //         rotation = {0, 0, 0},
        //         uv_rect  = terrain_block_uv,
        //         scale    = {64, 64, 1},
        //         color    = {255, 255, 255, 255},
        //     })

        //     r.draw_batched(sprite_batch, r.Draw_Batched{
        //         texture  = terrain_tex_id,
        //         position = {64 * f32(x), 64 * 6, 0},
        //         rotation = {0, 0, 0},
        //         uv_rect  = terrain_block_uv,
        //         scale    = {64, 64, 1},
        //         color    = {255, 255, 255, 255},
        //     })
        // }

        // for y in -6..=6 {
        //     r.draw_batched(sprite_batch, r.Draw_Batched{
        //         texture  = terrain_tex_id,
        //         position = {-64 * 6, 64 * f32(y), 0},
        //         rotation = {0, 0, 0},
        //         uv_rect  = terrain_block_uv,
        //         scale    = {64, 64, 1},
        //         color    = {255, 255, 255, 255},
        //     })

        //     r.draw_batched(sprite_batch, r.Draw_Batched{
        //         texture  = terrain_tex_id,
        //         position = {64 * 6, 64 * f32(y), 0},
        //         rotation = {0, 0, 0},
        //         uv_rect  = terrain_block_uv,
        //         scale    = {64, 64, 1},
        //         color    = {255, 255, 255, 255},
        //     })
        // }

        // r.draw_batched(sprite_batch, r.Draw_Batched{
        //     texture  = enemy_tex_id,
        //     position = rock.position,
        //     rotation = rock.rotation,
        //     uv_rect  = full_uv,
        //     scale    = rock.scale,
        //     color    = {255, 255, 255, 255},
        // })

        // r.draw_batched(sprite_batch, r.Draw_Batched{
        //     texture  = dude_tex_id,
        //     position = player.position,
        //     uv_rect  = full_uv,
        //     scale    = player.scale,
        //     color    = {255, 255, 255, 255},
        // })
        r.flush_shapes_batch()
        
        
        r.cmd_end_frame({r_id})
        r.present()
        
        f += 1

        if lost {
            p.set_window_opacity(window_id, opacity)
            opacity -= ns_to_f32(p.get_deltatime_ns()) * 0.6
            if opacity <= 0 {
                p.application_request_shutdown()
            }
        }
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
    movement_speed: f32 = 400


    if p.input_key_is_held(.Q) {
        camera.zoom += ns_to_f32(p.get_deltatime_ns()) * 300
    }
    if p.input_key_is_held(.E) {
        camera.zoom -= ns_to_f32(p.get_deltatime_ns()) * 300
    }
    
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

