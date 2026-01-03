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
	window_index: int,
	flags: WindowFlags,
	renderer: ^Renderer,
	
	layers: [dynamic]Layer,
}


when ODIN_DEBUG {
MAX_WINDOWS :: 4
} else {
MAX_WINDOWS :: 1
}

Application :: struct {
	//ctx: runtime.Context,
	windows: [MAX_WINDOWS]ApplicationWindow,
	window_count: int,

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

application_arena: mem.Arena

application_init :: proc(config: WindowConfig) {
	assert(application == nil, "Only one application can be created at a time!")
	
	backing := make([]byte, (
		size_of(Application)
	))
	mem.arena_init(&application_arena, backing)
	arena_alloc := mem.arena_allocator(&application_arena)
	
	application = new(Application, arena_alloc)
	application.start_time = time.tick_now()

	input_init()
	g_input.mouse_position = {f32(config.width) / 2, f32(config.height) / 2}
	
	application_new_window(config, LaunchWindow, true)
}

_application_destroy :: #force_inline proc() {
	delete(application_arena.data)
	mem.arena_free_all(&application_arena)
}

_application_shutdown :: #force_inline proc() {
	input_destroy()
	_application_destroy()
}

application_new_window :: proc(config: WindowConfig, flags: WindowFlags, set_key: bool = false) {
	if application.window_count >= MAX_WINDOWS {
		log.warnf("Trying to create more than %v windows", MAX_WINDOWS)
		return
	}
	
	when ODIN_OS == .Darwin {
		window := window_create_mac(
			width = config.width,
			height = config.height,
			title = config.title,
			flags = flags,
		)
	} else {
		window := nil
	}

	window.is_focused = set_key
	
	when RENDERER == .Metal {
		window_renderer := metal_init(window)
	} else {
		window_renderer := nil
	}


	index := application.window_count
	application_window := ApplicationWindow {
		window = window,
		window_index = index,
		renderer = window_renderer,
		flags = flags,
		layers = make([dynamic]Layer)
	}

	application.windows[index] = application_window
	application.window_count += 1
}


add_layer :: proc(layer: ^Layer, index: int = 0) {
	
	if layer.on_attach != nil {
		layer->on_attach()
	}
	
	append(&application.windows[index].layers, layer^)
}


Layer :: struct {
    on_attach: proc(layer: ^Layer),
    on_detach: proc(layer: ^Layer),

    on_event: proc(layer: ^Layer),
    update: proc(layer: ^Layer, delta_time: f32),
    render: proc(layer: ^Layer, command_buffer: ^CommandBuffer),

	data: uintptr,
}

application_request_shutdown :: #force_inline proc() {
	application.shutdown_requested = true
}

delta_time :: #force_inline proc() -> f32 {
	return application.delta_time
}

close_window :: proc(app_window: ^ApplicationWindow) {
	if .MainWindow in app_window.flags {
		application_request_shutdown()
	}

	#reverse for &layer in app_window.layers {
		if layer.on_detach != nil {
			layer->on_detach()
		}
	}
	delete(app_window.layers)

	app_window.renderer.cleanup(app_window.window, app_window.renderer)
	app_window.window.close(app_window.window)
	
	application.window_count -= 1
	index := app_window.window_index
	if index != application.window_count {
		application.windows[index] = application.windows[application.window_count]
	}

	if application.window_count > 0 {
		application.windows[application.window_count].window.is_focused = true
	}
}

run :: proc() {
	defer _application_shutdown()
	
	previous_time := time.tick_now()
	for !application.shutdown_requested {

		free_all(context.temp_allocator)
		
		delta_time := f32(time.duration_seconds(time.tick_since(previous_time)))
		application.runtime += delta_time
		application.delta_time = delta_time
		previous_time = time.tick_now()

		reset_input_state()
		process_events()
		update_input_state()
		defer input_clear_events()
	
		// Handle window closing
		#reverse for &app_window in application.windows[:application.window_count] {
			if !app_window.window.close_requested do continue
			close_window(&app_window)			
		}

		for app_window in application.windows[:application.window_count] {
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

		// Clean this up
		render_cmd_buffer := init_command_buffer()
		defer destroy_command_buffer(&render_cmd_buffer)

		for app_window in application.windows[:application.window_count] {
			if len(app_window.layers) == 0 do continue
			
			set_render_state(app_window.renderer.platform)

			for &layer in app_window.layers {
				if layer.render != nil {
					layer->render(&render_cmd_buffer)
				}
			}
			
			app_window.renderer.draw(app_window.window, app_window.renderer, &render_cmd_buffer)
			clear_command_buffer(&render_cmd_buffer)
		}
	}
	
	set_render_state :: proc(platform: Platform) {
		when ODIN_OS == .Darwin {
			render_state = cast(^MetalPlatform)platform
		} else {
			assert(false)
		}
	}
}

