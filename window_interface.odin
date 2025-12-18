package main

import "base:runtime"

WindowInterface :: struct {
	state_size: proc() -> int,
	init: proc(window_state: rawptr, width, height: int, title: string, allocator: runtime.Allocator),
	
	process_events: proc(),
	get_events: proc() -> []Event,
	clear_events: proc(),
	
	shutdown: proc(),
	window_handle: proc() -> rawptr,
	get_framebuffer_size: proc() -> (int, int),

	framebuffer_resized: proc() -> bool,
	set_framebuffer_resized: proc(state: bool),
}

Event :: union {
	WindowEventCloseRequested,
	KeyPressedEvent,
	KeyReleasedEvent,
	WindowResizeEvent,
	WindowFramebufferResizeEvent,
	MousePressedEvent,
	MouseReleasedEvent,
	MousePositionEvent,
	MouseScrollEvent,
}

WindowEventCloseRequested :: struct {}

KeyPressedEvent :: struct { key: KeyboardKey }
KeyReleasedEvent :: struct { key: KeyboardKey }

WindowResizeEvent :: struct { width, height: int}
WindowFramebufferResizeEvent :: struct { width, height: int }

MousePressedEvent :: struct { button: MouseButton }
MouseReleasedEvent :: struct { button: MouseButton }
MousePositionEvent :: struct { x, y: f64 }
MouseScrollEvent :: struct { x, y: f64 }
