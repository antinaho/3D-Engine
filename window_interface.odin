package main

WindowAPI :: struct {
	close: proc(window: ^Window),
	process_events: proc(window: ^Window),
	get_events: proc(window: ^Window) -> []Event,
	clear_events: proc(window: ^Window),
}

Window :: struct {
	using api : WindowAPI,
	platform: Platform,
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
	MouseScrollEvent,

	WindowResizeEvent,

	WindowMinimizeStartEvent,
	WindowMinimizeEndEvent,

	WindowEnterFullscreenEvent,
	WindowExitFullscreenEvent,

	WindowMoveEvent,

	WindowDidBecomeKey,
	WindowDidResignKey,
}

WindowEventCloseRequested :: struct {}

KeyPressedEvent :: struct { key: KeyboardKey }
KeyReleasedEvent :: struct { key: KeyboardKey }

MousePressedEvent :: struct { button: MouseButton }
MouseReleasedEvent :: struct { button: MouseButton }
MousePositionEvent :: struct { x, y: f64 }
MouseScrollEvent :: struct { x, y: f64 }

WindowResizeEvent :: struct { width, height: int}

WindowMinimizeStartEvent :: struct { }
WindowMinimizeEndEvent :: struct { }

WindowEnterFullscreenEvent :: struct { }
WindowExitFullscreenEvent :: struct { }

WindowMoveEvent :: struct { x, y: int }

WindowDidBecomeKey :: struct { }
WindowDidResignKey :: struct { }