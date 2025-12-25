package main

import "core:fmt"
import "core:log"
import "core:mem"

ExampleLayer :: Layer {
	ingest_events = _events,
	update = _update,
}

_events :: proc(input: ^WindowInput) {
	if key_went_down(input, .E) {
		fmt.println("Pressed E LayerOne")
	}
}

_update :: proc(delta: f32) {
}

main :: proc() {
    
    default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)
	defer reset_tracking_allocator(&tracking_allocator)

    context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

    init(1280, 720, "Hellope")


    app_window := create_window(1280, 720, "Hellope", context.allocator, {.MainWindow})

    add_layer(app_window, ExampleLayer)

    run()
}