package main

import "base:runtime"

WindowAPI :: struct {
	close: proc(window: ^Window),
	process_events: proc(window: ^Window),
	get_events: proc(window: ^Window) -> []Event,
	clear_events: proc(window: ^Window),
	get_window_handle: proc(window: ^Window) -> WindowHandle,
}

WindowHandle :: distinct uintptr

Window :: struct {
	using api : WindowAPI,
	platform: Platform,
	
	ctx: runtime.Context,
	events: [dynamic]Event,
	width: int,
	height: int,
	title: string,
	did_resize: bool,
	is_visible: bool,
	is_minimized: bool,
}

WindowFlag :: enum {
	MainWindow,
}

WindowFlags :: bit_set[WindowFlag]

Platform :: distinct uintptr

Event :: union {
	WindowEventCloseRequested,

	KeyPressedEvent,
	KeyReleasedEvent,

	MousePressedEvent,
	MouseReleasedEvent,
	MousePositionEvent,
	MousePositionDeltaEvent,
	MouseScrollEvent,

	WindowResizeEvent,

	WindowMinimizeStartEvent,
	WindowMinimizeEndEvent,

	WindowEnterFullscreenEvent,
	WindowExitFullscreenEvent,

	WindowMoveEvent,

	WindowDidBecomeKey,
	WindowDidResignKey,

	WindowBecameVisibleEvent,
	WindowBecameHiddenEvent,
}

WindowEventCloseRequested :: struct {}

KeyPressedEvent :: struct { key: KeyboardKey }
KeyReleasedEvent :: struct { key: KeyboardKey }

MousePressedEvent :: struct { button: MouseButton }
MouseReleasedEvent :: struct { button: MouseButton }
MousePositionEvent :: struct { x, y: f64 }
MousePositionDeltaEvent :: struct { x, y: f64 }
MouseScrollEvent :: struct { x, y: f64 }

WindowResizeEvent :: struct { width, height: int}

WindowMinimizeStartEvent :: struct { }
WindowMinimizeEndEvent :: struct { }

WindowEnterFullscreenEvent :: struct { }
WindowExitFullscreenEvent :: struct { }

WindowMoveEvent :: struct { x, y: int }

WindowDidBecomeKey :: struct { }
WindowDidResignKey :: struct { }

WindowBecameVisibleEvent :: struct {}
WindowBecameHiddenEvent :: struct {}