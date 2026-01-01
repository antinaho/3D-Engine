package main

import "base:runtime"

WindowAPI :: struct {
	close: proc(window: ^Window),
	get_window_handle: proc(window: ^Window) -> WindowHandle,
}

WindowHandle :: distinct uintptr

Window :: struct {
	using api : WindowAPI,
	platform: Platform,
	
	ctx: runtime.Context,
	width: int,
	height: int,
	title: string,
	close_requested: bool,
	did_move: bool,
	did_resize: bool,

	is_visible: bool,
	is_minimized: bool,
	is_focused: bool,
	i: int,
}

WindowFlag :: enum {
	MainWindow,
	SecondaryWindow,
}
WindowFlags :: bit_set[WindowFlag]
LaunchWindow :: WindowFlags {.MainWindow}
SecondaryWindow :: WindowFlags {.SecondaryWindow}

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

	WindowBecameVisibleEvent,
	WindowBecameHiddenEvent,
}

WindowEventCloseRequested :: struct { window: ^Window }
WindowResizeEvent :: struct { window: ^Window, width, height: int}
WindowMinimizeStartEvent :: struct { window: ^Window }
WindowMinimizeEndEvent :: struct { window: ^Window }
WindowEnterFullscreenEvent :: struct { window: ^Window }
WindowExitFullscreenEvent :: struct { window: ^Window }
WindowMoveEvent :: struct { window: ^Window, x, y: int }
WindowDidBecomeKey :: struct { window: ^Window }
WindowDidResignKey :: struct { window: ^Window }
WindowBecameVisibleEvent :: struct { window: ^Window }
WindowBecameHiddenEvent :: struct { window: ^Window }

KeyPressedEvent :: struct { key: KeyboardKey }
KeyReleasedEvent :: struct { key: KeyboardKey }
MousePressedEvent :: struct { button: MouseButton }
MouseReleasedEvent :: struct { button: MouseButton }
MousePositionEvent :: struct { x, y: f64 }
MouseScrollEvent :: struct { x, y: f64 }
