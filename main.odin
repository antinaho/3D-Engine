package main

import "core:flags"
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

@(private="package")
application: ^Application


ApplicationWindow :: struct {
	is_active: bool,

	window_context: runtime.Context,
	window_arena: mem.Arena,
	window_allocator: runtime.Allocator,
	

	width: int,
	height: int,
	title: string,
	close_requested: bool,
	did_move: bool,
	did_resize: bool,

	is_visible: bool,
	is_minimized: bool,
	is_focused: bool,

	layers: [dynamic]Layer,
}

Application :: struct {
	windows: []ApplicationWindow,
	ctx: runtime.Context,
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


application_init :: proc(reserve_window_count := 1) {
	assert(application == nil, "Only one application can be created at a time!")
	assert(reserve_window_count >= 1)
	
	application = new(Application)

	application.ctx = context
	application.start_time = time.tick_now()
	application.windows = make([]ApplicationWindow, reserve_window_count)
	
	for &w in application.windows {
		arena_mem := make([]byte, mem.Megabyte * 1)
		mem.arena_init(&w.window_arena, arena_mem)
		w.window_allocator = mem.arena_allocator(&w.window_arena)
	}
}

application_shutdown :: #force_inline proc() {
	for &aw in application.windows {
		if !aw.is_active do continue
		delete(aw.window_arena.data)
	}
	delete(application.windows)
	free(application)
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

	data: uintptr,
}

application_request_shutdown :: #force_inline proc() {
	application.shutdown_requested = true
}

delta_time :: #force_inline proc() -> f32 {
	return application.delta_time
}
