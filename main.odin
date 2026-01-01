package main

import "core:mem"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:time"

Vertex :: struct #align(16) {
    position: [3]f32,
	_: f32,

	normal: [3]f32,
	_: f32,

    color: [4]f32,
	
	uvs: [2]f32,
	_: [2]f32,
}

@(private="file")
application: ^Application

ApplicationWindow :: struct {
	window: ^Window,
	flags: WindowFlags,
	renderer: ^Renderer,
	
	layers: [dynamic]^Layer,
}

Application :: struct {
	//ctx: runtime.Context,
	windows: [dynamic]ApplicationWindow,
	shutdown_requested: bool,

	start_time: time.Tick,
	delta_time: f32,
	runtime: f32,
}

WindowConfig :: struct {
    width: int, 
    height: int,
	title: string,
}

application_init :: proc(config: WindowConfig) {
	assert(application == nil, "Only one application can be created at a time!")
	
	application = new(Application)

	g_input = new(Input)
	g_input.mouse_position = {f64(config.width) / 2, f64(config.height) / 2}
	g_input.events = make([dynamic]Event, 0, 64)

	application.shutdown_requested = false
	application.start_time = time.tick_now()

	//application.ctx = context
	application.windows = make([dynamic]ApplicationWindow)

	application_new_window(config, LaunchWindow, true)
}

application_new_window :: proc(config: WindowConfig, flags: WindowFlags, set_key: bool = false) {
	window := window_create_mac(
		width = config.width,
		height = config.height,
		title = config.title,
		flags = flags,
	)
	window.i = _i
	window.is_focused = set_key

	window_renderer := metal_init(window)

	application_window := ApplicationWindow {
		window = window,
		renderer = window_renderer,

		flags = flags,
		layers = make([dynamic]^Layer)
	}

	append(&application.windows, application_window)

	defer { _i += 1}
}
_i : int

add_layer :: proc(layer: ^Layer, index: int = 0) {
	
	if layer.on_attach != nil {
		layer->on_attach()
	}
	
	append(&application.windows[index].layers, layer)
	
}


Layer :: struct {
    on_attach: proc(layer: ^Layer),
    on_detach: proc(layer: ^Layer),

    on_event: proc(layer: ^Layer),
    update: proc(layer: ^Layer, delta_time: f32),
    render: proc(layer: ^Layer, command_buffer: ^CommandBuffer),

	data: uintptr,
}

application_request_shutdown :: proc() {
	application.shutdown_requested = true
}

delta_time :: proc() -> f32 {
	return application.delta_time
}

run :: proc() {
	
	previous_time := time.tick_now()
	for !application.shutdown_requested {

		free_all(context.temp_allocator)
		
		delta_time := f32(time.duration_seconds(time.tick_since(previous_time)))
		application.runtime += delta_time
		application.delta_time = delta_time
		previous_time = time.tick_now()

		reset_input_state()
		defer clear(&g_input.events)

		process_events()
		update_input_state()
	
		// Handle window closing
		#reverse for &app_window, i in application.windows {
			if app_window.window.close_requested {
				if .MainWindow in app_window.flags {
					application_request_shutdown()
				}

				//app_window.renderer.cleanup()
				app_window.window.close(app_window.window)
				ordered_remove(&application.windows, i)

				if len(application.windows) > 0 {
					application.windows[len(application.windows) - 1].window.is_focused = true
				}
			}
		}

		for app_window in application.windows {
			if app_window.window.is_focused {
				#reverse for &layer in app_window.layers {
					if layer.on_event != nil {
						layer->on_event()
					}
				}
			}

			for &layer in app_window.layers {
				if layer.update != nil {
					layer->update(delta_time)
				}
			}
		}

		render_cmd_buffer := init_command_buffer()
		defer destroy_command_buffer(&render_cmd_buffer)

		for app_window in application.windows {
			if len(app_window.layers) == 0 {
				continue
			}
			set_render_target(app_window.renderer.platform)

			for &layer in app_window.layers {
				if layer.render != nil {
					layer->render(&render_cmd_buffer)
				}
			}
			
			app_window.renderer.draw(app_window.window, app_window.renderer, &render_cmd_buffer)
			clear_command_buffer(&render_cmd_buffer)
		}
	}
	
	set_render_target :: proc(platform: Platform) {
		render_state = cast(^MetalPlatform)platform
	}

	// for &aw in application.windows {
	// 	delete(aw.layers)
	// 	aw.renderer.cleanup(aw.window, aw.renderer)
	// 	aw.window.close(aw.window)
	// }

	// delete(application.windows)

	// free(application)
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
