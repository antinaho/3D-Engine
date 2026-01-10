package main

// Choose platform
when ODIN_OS == .Darwin {
	DEFAULT_PLATFORM_API :: MAC_PLATFORM_API
} else when ODIN_OS == .Windows {
	DEFAULT_PLATFORM_API :: nil
}

PLATFORM_API :: DEFAULT_PLATFORM_API

@(private="file")
platform: Platform

Platform :: struct {
	window_states: []byte,
	state_size: int,
	max_windows: int,

	keys_press_started: #sparse [InputKeyboardKey]bool,
	keys_held: #sparse [InputKeyboardKey]bool,
	keys_released: #sparse [InputKeyboardKey]bool,

	mouse_press_started: #sparse [InputMouseButton]bool,
	mouse_held: #sparse [InputMouseButton]bool,
	mouse_released: #sparse [InputMouseButton]bool,

	mouse_position: Vector2,
	mouse_move_delta: Vector2,
	mouse_scroll_delta: Vector2,

	events: [MAX_INPUT_EVENTS_PER_FRAME]Event,
	event_count: int,
}

init :: proc(max_windows: int = 1) {
	assert(max_windows >= 1)

	state_size := PLATFORM_API.window_state_size()
    platform.window_states = make([]byte, state_size * max_windows)
    platform.state_size = state_size
    platform.max_windows = max_windows
    
    // Initialize all states as "not alive"
    PLATFORM_API.init_window_states(platform.window_states, state_size, max_windows)
}

PlatformAPI :: struct {
	window_state_size: proc() -> int,
	init_window_states: proc(states: []byte, state_size, windows: int),

	window_open:  proc(desc: WindowDescription) -> WindowID,
	window_close: proc(id: WindowID),
	
	get_native_window_handle: proc(id: WindowID) -> WindowHandle,
	
	set_window_position: proc(id: WindowID, x, y: int),
	set_window_size: proc(id: WindowID, w, h: int),

	process_events: proc(),
	get_events: proc() -> []Event,
	clear_events: proc(),

	get_window_width: proc(id: WindowID) -> int,
	get_window_height: proc(id: WindowID) -> int,
}

WindowID :: distinct u32
WindowHandle :: distinct uintptr
WindowDescription :: struct {
	x: int,
	y: int,
	width: int,
	height: int,
	title: string
}
WindowStateHeader :: struct {
	is_alive: bool,
}





is_state_alive :: proc(state: rawptr) -> bool {
    header := cast(^WindowStateHeader)state
    return header.is_alive
}

get_first_alive :: proc() -> (state: rawptr, id: WindowID) {
	for i in 0..<platform.max_windows {
        state_ptr := get_state(WindowID(i))
        if is_state_alive(state_ptr) {
        	return state_ptr, WindowID(i)
        }
    }
    panic("All window states are dead!")
}

get_free_state :: proc() -> (state: rawptr, id: WindowID) {
    for i in 0..<platform.max_windows {
        state_ptr := get_state(WindowID(i))
        if !is_state_alive(state_ptr) {
            return state_ptr, WindowID(i)
        }
    }
    panic("All window states are in use!")
}

get_state :: proc(id: WindowID) -> rawptr {
    assert(int(id) < platform.max_windows, "Invalid WindowID")
    offset := platform.state_size * int(id)
    return raw_data(platform.window_states[offset:])
}






import NS "core:sys/darwin/Foundation"

import "core:mem"
MAC_PLATFORM_API :: PlatformAPI {
	window_state_size = window_state_size_mac,
	init_window_states = init_window_states_mac,


	get_native_window_handle = get_native_window_handle_mac,
	set_window_position = set_window_position_mac,
	set_window_size = set_window_size_mac,
	
	process_events = process_events_mac,
	get_events = proc() -> []Event {
		return application.events[:application.event_count]
	},
	clear_events = proc() {
		application.event_count = 0
	},

	get_window_width = get_window_width_mac,
	get_window_height = get_window_height_mac,

	window_open = window_open_mac,
	window_close = window_close_mac,
}

get_window_width_mac :: proc(id: WindowID) -> int {
	state := cast(^MacWindowState)get_state(id)
	frame := state.window->frame()
	return int(frame.width)
}

get_window_height_mac :: proc(id: WindowID) -> int {
	state := cast(^MacWindowState)get_state(id)
	frame := state.window->frame()
	return int(frame.height)
}

process_events_mac :: proc() {
	event: ^NS.Event
	alive_state, id := get_first_alive()
	state := cast(^MacWindowState)alive_state

	for {
		event = state.application->nextEventMatchingMask(NS.EventMaskAny, NS.Date_distantPast(), NS.DefaultRunLoopMode, true)
		if event == nil { break }
		
		#partial switch event->type() {
			case .KeyDown:
				input_new_event(KeyPressedEvent{key=code_to_keyboard_key[event->keyCode()]})
			case .KeyUp:
				input_new_event(KeyReleasedEvent{key=code_to_keyboard_key[event->keyCode()]})
			
			case .LeftMouseDown:
				input_new_event(MousePressedEvent{button=code_to_mouse_button[InputMouseButton.Left]})
			case .LeftMouseUp, .RightMouseUp, .OtherMouseUp:
				btn_n := event->buttonNumber()
				input_new_event(MouseReleasedEvent{button=code_to_mouse_button[int(btn_n)]})
			case .RightMouseDown:
				input_new_event(MousePressedEvent{button=code_to_mouse_button[InputMouseButton.Right]})


			case .OtherMouseDown:
				btn_n := event->buttonNumber()
				input_new_event(MousePressedEvent{button=code_to_mouse_button[int(btn_n)]})

			
			case .MouseMoved, .LeftMouseDragged, .RightMouseDragged, .OtherMouseDragged:
				position := event->locationInWindow()				
				input_new_event(MousePositionEvent{x=f64(position.x), y=f64(position.y)})
			case .ScrollWheel:
				scroll_x, scroll_y := event->scrollingDelta()
				input_new_event(MouseScrollEvent{x=f64(scroll_x), y=f64(scroll_y)})
		}
		state.application->sendEvent(event)
	}
}

set_window_position_mac :: proc(id: WindowID, x, y: int) {
	state := cast(^MacWindowState)get_state(id)
	state.x = x
	state.y = y

	point := NS.Point {
		x = NS.Float(x),
		y = NS.Float(y)
	}

	state.window->setFrameOrigin(point)
} 


set_window_size_mac :: proc(id: WindowID, w, h: int) {
	state := cast(^MacWindowState)get_state(id)

	frame := state.window->frame()
	frame.size = {
		width = NS.Float(w),
		height = NS.Float(h),
	}

	state.window->setFrame(frame, false)
} 

get_native_window_handle_mac :: proc(id: WindowID) -> WindowHandle {
	state := cast(^MacWindowState)get_state(id)
	return cast(WindowHandle)state.window
}

init_window_states_mac :: proc(states: []byte, state_size, count: int) {
	for i in 0..<count {
        offset := state_size * i
        state := cast(^MacWindowState)raw_data(states[offset:])
        state.is_alive = false
    }
}

window_close_mac :: proc(id: WindowID) {
    state := cast(^MacWindowState)get_state(id)
    
    
    
    state.is_alive = false
}

MacWindowState :: struct {
	using header : WindowStateHeader,

	application: ^NS.Application,
	window: ^NS.Window,

	width: int,
	height: int,
	title: string,
	x: int,
	y: int,
}


window_state_size_mac :: proc() -> int {
	return size_of(MacWindowState)
}

window_open_mac :: proc(desc: WindowDescription) -> WindowID {
    state, id := get_free_state()
    mac_state := cast(^MacWindowState)state

	mac_state^ = MacWindowState {
		application = NS.Application.sharedApplication(),
		window = NS.Window_alloc(),
		x = desc.x,
		y = desc.y,
		width = desc.width,
		height = desc.height,
		title = desc.title,
	}
	
	mac_state.application->setActivationPolicy(.Regular)
	mac_state.window->setReleasedWhenClosed(true)
	
	rect := NS.Rect {
		origin = {NS.Float(desc.x), NS.Float(desc.y)},
		size = {NS.Float(desc.width), NS.Float(desc.height)}
	}

	mac_state.window->initWithContentRect(rect, {.Resizable, .Closable, .Titled, .Miniaturizable}, .Buffered, false)

	w_title := NS.alloc(NS.String)->initWithOdinString(desc.title)
	defer w_title->release()
	mac_state.window->setTitle(w_title)
	mac_state.window->setBackgroundColor(NS.Color_purpleColor())

	mac_state.window->makeKeyAndOrderFront(nil)
	//mac_state.window->makeMainWindow()
	// state.window->center()
	// Set delegates like window_resize, move etc.

	mac_state.application->activate()

	return id
}







WindowAPI :: struct {
	close: proc(application_window: ^ApplicationWindow),
	get_window_handle: proc(window: ^Window) -> WindowHandle,
}

Window :: struct {
	using api : WindowAPI,
	platform: _Platform,	
}

WindowFlag :: enum {
	MainWindow,
	SecondaryWindow,
}
WindowFlags :: bit_set[WindowFlag]

_Platform :: distinct uintptr

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

WindowEventCloseRequested :: struct { application_window: ^ApplicationWindow }
WindowResizeEvent :: struct { application_window: ^ApplicationWindow, width, height: int}
WindowMinimizeStartEvent :: struct { application_window: ^ApplicationWindow }
WindowMinimizeEndEvent :: struct { application_window: ^ApplicationWindow }
WindowEnterFullscreenEvent :: struct { application_window: ^ApplicationWindow }
WindowExitFullscreenEvent :: struct { application_window: ^ApplicationWindow }
WindowMoveEvent :: struct { application_window: ^ApplicationWindow, x, y: int }
WindowDidBecomeKey :: struct { application_window: ^ApplicationWindow }
WindowDidResignKey :: struct { application_window: ^ApplicationWindow }
WindowBecameVisibleEvent :: struct { application_window: ^ApplicationWindow }
WindowBecameHiddenEvent :: struct { application_window: ^ApplicationWindow }

KeyPressedEvent :: struct { key: InputKeyboardKey }
KeyReleasedEvent :: struct { key: InputKeyboardKey }
MousePressedEvent :: struct { button: InputMouseButton }
MouseReleasedEvent :: struct { button: InputMouseButton }
MousePositionEvent :: struct { x, y: f64 }
MouseScrollEvent :: struct { x, y: f64 }
