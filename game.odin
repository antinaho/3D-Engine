package main

import "core:log"
import "core:mem"
import "core:math"
import "core:fmt"

// _render :: proc(layer: ^Layer, renderer: ^Renderer, command_buffer: ^CommandBuffer) {

    // ortho_camera.aspect = f32(renderer.msaa_texture.desc.width) / f32(renderer.msaa_texture.desc.height)

    // data := cast(^TestLayerData)layer.data
    // cmd_update_renderpass_descriptors(command_buffer, Update_Renderpass_Desc{
    //     msaa_texture = renderer.msaa_texture,
    //     depth_texture = renderer.depth_texture,
    // })

    // cmd_begin_pass(command_buffer, "Test")
    // cmd_set_pipeline(command_buffer, data.default_renderer.pipeline)

    // view: matrix[4,4]f32
    // proj: matrix[4,4]f32
    
    // view = mat4_view(
    //             eye=ortho_camera.position,
    //             target=ortho_camera.position + VECTOR_FORWARD,
    //             up=VECTOR_UP
    //         )
    // proj = mat4_ortho_fixed_height(10, ortho_camera.aspect)

    //         // proj = mat4_perspective_projection(
    //         //     fov_y_radians=DEG_TO_RAD*main_camera.fov,
    //         //     aspect=main_camera.aspect,
    //         //     near=main_camera.near,
    //         //     far=main_camera.far,
    //         // )
    
    // scene_uniforms := SceneUniformData {
    //     view = view,
    //     projection = proj,
    // }

    // cmd_set_uniform(command_buffer, scene_uniforms, 1, .Vertex)
    // clear(&data.instance_data)

    // InstanceBatch :: struct {
    //     offset: int,    
    //     count: int,     
    // }
    // batches := make(map[EntityType]InstanceBatch, context.temp_allocator)
    
    // {
    //     for entity_type, ents in entities {
    //         if len(ents) == 0 do continue
    //         offset := len(data.instance_data)
    //         for e in ents {
    //             model := mat4_model(e.position, e.rotation, e.scale)
    //             append(&data.instance_data, InstanceData{model, {1, 1}, {0, 0}})
    //         }
    //         batches[entity_type] = InstanceBatch{
    //             offset = offset,
    //             count = len(ents),
    //         }
    //     }

    //     fill_buffer(
    //         &data.instance_buf,
    //         raw_data(data.instance_data),
    //         size_of(InstanceData) * len(data.instance_data),
    //         0,
    //     )

    //     for entity_type, ents in entities {
    //         batch := batches[entity_type]
    //         if batch.count == 0 do continue

    //         fill_buffer(&data.vertex_buf, raw_data(vertices_of(entity_type)), size_of(Vertex) * len(vertices_of(entity_type)), 0)
    //         fill_buffer(&data.index_buf, raw_data(indices_of(entity_type)), size_of(u32) * len(indices_of(entity_type)), 0)
            
    //         cmd_bind_vertex_buffer(command_buffer, data.vertex_buf, 0, 0)
    //         cmd_bind_vertex_buffer(command_buffer, data.instance_buf, batch.offset * size_of(InstanceData), 2)
    //         cmd_bind_index_buffer(command_buffer, data.index_buf, 0)
            
    //         cmd_bind_texture(command_buffer, data.default_renderer.custom_texture, 0, .Fragment)
    //         cmd_bind_sampler(command_buffer, data.default_renderer.default_sampler, 0, .Fragment)
            
    //         cmd_draw_indexed_with_instances(
    //             command_buffer,
    //             len(indices_of(entity_type)),
    //             data.index_buf,
    //             batch.count,  
    //         )

    //     }
    //     cmd_end_pass(command_buffer)
    // }
// }

EntityType :: enum {
    Quad,
    Triangle,
}

Transform :: struct {
    position: Vector3,
    rotation: Vector3,
    scale:    Vector3,
}

//

import p "pohja"
import r "huuru"

import "core:math/rand"
import "core:time"

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
        width = 1280,
        height = 920,
        title = "Hellope",
    })

    r.init(1)
    r_id := r.init_renderer(
        r.Window_Provider{
            window_id = rawptr(uintptr(id)),
            get_size = proc(id: rawptr) -> [2]int {
                wid := p.Window_ID(uintptr(id))
                return p.PLATFORM_API.get_window_size(wid)
            },
            get_native_handle = proc(id: rawptr) -> rawptr {
                return rawptr(p.get_native_window_handle(p.Window_ID(uintptr(id))))
            },
            is_visible = proc(id: rawptr) -> bool {return true},
            is_minimized =  proc(window_id: rawptr) -> bool { return false },
        })

    pipeline := r.create_pipeline(r_id, r.Pipeline_Desc{
        type = r.Pipeline_Desc_Metal{
            vertex_entry   = "basic_vertex",
            fragment_entry = "basic_fragment",
        },
        layouts = {
            r.Vertex_Layout{
                stride    = size_of(r.Sprite_Vertex),
                step_rate = .PerVertex,
            },
        },
        attributes = {
            r.Vertex_Attribute{ format = .Float2, offset = offset_of(r.Sprite_Vertex, position), binding = 0 },
            r.Vertex_Attribute{ format = .Float2, offset = offset_of(r.Sprite_Vertex, uv), binding = 0 },
            r.Vertex_Attribute{ format = .UByte4, offset = offset_of(r.Sprite_Vertex, color), binding = 0 },
        },
        blend = r.OpaqueBlend,
    })

    pipeline_2 := r.create_pipeline(r_id, r.Pipeline_Desc{
        type = r.Pipeline_Desc_Metal{
            vertex_entry   = "font_vertex",
            fragment_entry = "font_fragment",
        },
        layouts = {
            r.Vertex_Layout{
                stride    = size_of(r.Sprite_Vertex),
                step_rate = .PerVertex,
            },
        },
        attributes = {
            r.Vertex_Attribute{ format = .Float2, offset = offset_of(r.Sprite_Vertex, position), binding = 0 },
            r.Vertex_Attribute{ format = .Float2, offset = offset_of(r.Sprite_Vertex, uv), binding = 0 },
            r.Vertex_Attribute{ format = .UByte4, offset = offset_of(r.Sprite_Vertex, color), binding = 0 },
        },
        blend = r.OpaqueBlend,
    })

    tex_data, w, h := r.load_tex("textures/face.jpg")
    t_id := r.create_texture(r_id, r.Texture_Desc {
        data = tex_data,
        width = w,
        height = h,
        bytes_per_row = 0,
        format = .RGBA8,
    })
    s_id := r.create_sampler(r_id, {
        mag_filter = .Linear,
        min_filter = .Linear,
        wrap_s = .Repeat,
        wrap_t = .Repeat,
    })
    
    sprite_batch := r.sprite_batch_init(r_id, t_id, 0)

    uniform_buffer := r.create_buffer_zeros(
        r_id,
        size_of(r.Uniforms),
        .Vertex,
        .Dynamic,
    )

    camera := r.Camera {
        position = {0, 0, 1},
        aspect_ratio = 16.0 / 9.0,
        zoom = 920,
    }

    f : int = 0
    last_rot_p: Vector3
    last_rot_n: Vector3
    previous_time := time.tick_now()
    runtime: f32

    for !p.platform_should_close() {
        p.platform_update()

        r.renderer.render_command_c = 0

        view := mat4_view(camera.position, camera.position + r.VECTOR3_FORWARD, r.VECTOR3_UP)
        proj := mat4_ortho_fixed_height(camera.zoom, camera.aspect_ratio)
        uniforms := r.Uniforms{ view_projection = proj * view }
        r.push_buffer(r_id, uniform_buffer, &uniforms, 0, size_of(r.Uniforms), .Dynamic)


        r.cmd_begin_frame({r_id})

        r.cmd_bind_pipeline({r_id, pipeline})

        r.cmd_bind_vertex_buffer(r.Render_Command_Bind_Vertex_Buffer{
            id = r_id,
            buffer_id = uniform_buffer,
            index = 1,
            offset = 0
        })

        r.cmd_bind_sampler({id =r_id, sampler =s_id, slot=0})

        full_uv := r.UV_Rect{
            min = {0, 0},
            max = {1, 1}
        }
        // Faces
        delta_time := f32(time.duration_seconds(time.tick_since(previous_time)))
        runtime += delta_time
        previous_time = time.tick_now()


        for x := -600; x <= 600; x += 100 {
            for y := -500; y <= 500; y += 100 {
                
                last_rot_p.z += 0.00006
                last_rot_n.z -= 0.0001
                rotation := last_rot_n if (x / 100 + y / 100) % 2 == 0 else last_rot_p

                pulse := 1.0 + 0.39 * math.sin_f32(runtime * 3 + f32(x + y) * 0.011)
                scale_factor := 64.0 * pulse

                phase := runtime * 1.5 + f32(x) * 0.05 + f32(y) * 0.02
                offset_y := 100 * math.sin_f32(phase)
                offset_x := 20 * math.sin_f32(phase * 1.3 + 1.4)

                r.draw_batched(sprite_batch, r.Draw_Batched{
                    texture  = t_id,
                    position = {f32(x) + offset_x, f32(y) + offset_y, 0},
                    rotation = rotation,
                    uv_rect = full_uv,
                    scale    = {scale_factor, scale_factor, 1},
                    color    = {255, 255, 255, 255},
                })
            }
        }

        r.draw_batched(sprite_batch, r.Draw_Batched{
            texture  = t_id,
            position = {0, 0, -0.1},
            uv_rect = full_uv,
            scale    = {64, 64, 1},
            color    = {255, 255, 255, 255},
        })
        

        f += 1
        
        r.flush(sprite_batch)

        r.cmd_end_frame({r_id})

        r.present()
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

