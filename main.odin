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
	window: ^Window,
	renderer: ^Renderer,
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

	flags: WindowFlags,
	layers: [dynamic]Layer,
}

Application :: struct {
	using input: Input,
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
	flags: WindowFlags,
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

application_new_window :: proc(config: WindowConfig) -> (application_window: ^ApplicationWindow, success: bool) {

	for &app_window in application.windows {
		if app_window.is_active {
			continue
		}

		when ODIN_OS == .Darwin {
			window := window_create_mac(
				application_window = &app_window,
				width = config.width,
				height = config.height,
				title = config.title,
				flags = config.flags,
			)
		}
		app_window.window = window


		when RENDERER_KIND == .Metal {
			renderer := metal_init(&app_window)
		}
		app_window.renderer = renderer

		app_window.is_active = true
		app_window.is_focused = true
		app_window.flags = config.flags

		return &app_window, true
	}

	return
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
    render: proc(layer: ^Layer, renderer: ^Renderer, command_buffer: ^CommandBuffer),

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

	app_window.renderer.cleanup(app_window)
	app_window.window.close(app_window)
	
	app_window.is_active = false

	delete(app_window.window_arena.data)
	mem.arena_free_all(&app_window.window_arena)
	
	for &aw in application.windows {
		if !aw.is_active do continue
		aw.is_focused = true
	}
}

run :: proc() {
	defer application_shutdown()
	
	previous_time := time.tick_now()
	for !application.shutdown_requested {

		free_all(context.temp_allocator)

		delta_time := f32(time.duration_seconds(time.tick_since(previous_time)))
		application.runtime += delta_time
		application.delta_time = delta_time
		previous_time = time.tick_now()

		input_reset_state()
		process_events()
		input_update_state()
		defer input_clear_events()

		// Window close requested?
		#reverse for &app_window in application.windows {
			if !app_window.is_active || !app_window.close_requested do continue
			close_window(&app_window)			
		}



		// for app_window in application.windows[:application.window_count] {
		// 	if app_window.window.is_focused {
		// 		#reverse for &layer in app_window.layers {
		// 			if layer.on_event != nil {
		// 				layer->on_event()
		// 			}
		// 		}
		// 	}

		// 	for &layer in app_window.layers {
		// 		if layer.update != nil {
		// 			layer->update(delta_time)
		// 		}
		// 	}
		// }

		// // Clean this up
		// render_cmd_buffer := init_command_buffer()
		// defer destroy_command_buffer(&render_cmd_buffer)

		// for app_window in application.windows[:application.window_count] {
		// 	if len(app_window.layers) == 0 do continue
			
		// 	set_render_state(app_window.renderer.platform)

		// 	for &layer in app_window.layers {
		// 		if layer.render != nil {
		// 			layer->render(app_window.renderer, &render_cmd_buffer)
		// 		}
		// 	}
			
		// 	app_window.renderer.draw(app_window.window, app_window.renderer, &render_cmd_buffer)
		// 	clear_command_buffer(&render_cmd_buffer)
		// }
	}
	
	set_render_state :: proc(platform: _Platform) {
		when ODIN_OS == .Darwin {
			render_state = cast(^MetalPlatform)platform
		} else {
			assert(false)
		}
	}
}

/////////////////////////////////
// INPUT

MAX_INPUT_EVENTS_PER_FRAME :: 64

Input :: struct {
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

input_clear_events :: #force_inline proc() {
	application.event_count = 0
}

input_get_events :: #force_inline proc()  -> []Event {
	return application.events[:application.event_count]
}

process_events :: proc() {
	when ODIN_OS == .Darwin {
		_mac_process_events()
	}
}

input_reset_state :: proc() {
	application.keys_press_started = {}
	application.keys_released = {}
	
	application.mouse_press_started = {}
	application.mouse_released = {}
	
	application.mouse_scroll_delta = {}
	application.mouse_move_delta = {}
}

input_new_event :: proc (event: Event) {
	if application.event_count == MAX_INPUT_EVENTS_PER_FRAME - 1 {
		log.warn("Capped input events")
		return
	}

	application.events[application.event_count] = event
	application.event_count += 1
}

input_update_state :: proc() {
	events := input_get_events()

	for event in events {
		switch e in event {
			case WindowEventCloseRequested:
				e.application_window.close_requested = true

			case KeyPressedEvent:
				
				application.keys_press_started[e.key] = application.keys_held[e.key] ~ true
				application.keys_held[e.key] = true
			case KeyReleasedEvent:
				
				application.keys_released[e.key] = true
				application.keys_held[e.key] = false
			case WindowResizeEvent:
				e.application_window.did_resize = true
				e.application_window.width = e.width
				e.application_window.height = e.height
			
			case WindowMinimizeStartEvent:
				e.application_window.is_minimized = true
			case WindowMinimizeEndEvent:
				e.application_window.is_minimized = false
				

			case WindowBecameVisibleEvent:
				e.application_window.is_visible = true
			case WindowBecameHiddenEvent:
				e.application_window.is_visible = false
			
			case WindowEnterFullscreenEvent:
			case WindowExitFullscreenEvent:
			case WindowMoveEvent:

			case WindowDidBecomeKey:
				e.application_window.is_focused = true
			case WindowDidResignKey:
				e.application_window.is_focused = false

			case MousePressedEvent:
				
				application.mouse_press_started[e.button] = application.mouse_held[e.button] ~ true
				application.mouse_held[e.button] = true
			case MouseReleasedEvent:
				
				application.mouse_released[e.button] = true
				application.mouse_held[e.button] = false
			case MousePositionEvent:
				
				application.mouse_move_delta = {f32(e.x) - application.mouse_position.x, f32(e.y) - application.mouse_position.y}
				application.mouse_position = {f32(e.x), f32(e.y)}

			case MouseScrollEvent:
				
				application.mouse_scroll_delta = {f32(e.x), f32(e.y)}
		}
	}
}

input_key_went_down :: proc(key: InputKeyboardKey) -> bool {
	return application.keys_press_started[key]
}

input_key_went_up :: proc(key: InputKeyboardKey) -> bool {
	return application.keys_released[key]
}

input_key_is_held :: proc(key: InputKeyboardKey) -> bool {
	return application.keys_held[key]
}

InputScrollDirection :: enum {
	X,
	Y,
	Both,
}

input_scroll_magnitude :: proc(direction: InputScrollDirection) -> f32 {
	if direction == .X {
		return f32(application.mouse_scroll_delta.x)
	} else if direction == .Y {
		return f32(application.mouse_scroll_delta.y)
	} else {
		return f32(application.mouse_scroll_delta.x) + f32(application.mouse_scroll_delta.y)
	}
}

input_scroll_vector2 :: proc(direction: InputScrollDirection) -> Vector2 {
	if direction == .X {
		return {1, 0} * f32(application.mouse_scroll_delta.x)
	} else if direction == .Y {
		return {0, 1} * f32(application.mouse_scroll_delta.y)
	} else {
		return {f32(application.mouse_scroll_delta.x), f32(application.mouse_scroll_delta.y)}
	}	
}

input_mouse_position :: proc() -> Vector2 {
	return {f32(application.mouse_position.x), f32(application.mouse_position.y)}
}

input_mouse_delta :: proc(direction: InputScrollDirection) -> f32 {
	if direction == .X {
		return f32(application.mouse_move_delta.x)
	} else if direction == .Y {
		return f32(application.mouse_move_delta.y)
	} else {
		return f32(application.mouse_move_delta.x) + f32(application.mouse_move_delta.y)
	}	
}

input_mouse_delta_vector :: proc(direction: InputScrollDirection) -> Vector2 {
	if direction == .X {
		return {1, 0} * f32(application.mouse_move_delta.x)
	} else if direction == .Y {
		return {0, 1} * f32(application.mouse_move_delta.y)
	} else {
		return {f32(application.mouse_move_delta.x), f32(application.mouse_move_delta.y)}
	}
}

input_mouse_button_went_down :: proc(button: InputMouseButton) -> bool {
	return application.mouse_press_started[button]
}

input_mouse_button_went_up :: proc(button: InputMouseButton) -> bool {
	return application.mouse_released[button]
}

input_mouse_button_is_held :: proc(button: InputMouseButton) -> bool {
	return application.mouse_held[button]
}

InputMouseButton :: enum {
	Left 	= 0,
	Right 	= 1,
	Middle 	= 2,

	MouseOther_1  = 3,
	MouseOther_2  = 4,
	MouseOther_3  = 5,
	MouseOther_4  = 6,
	MouseOther_5  = 7,
	MouseOther_6  = 8,
	MouseOther_7  = 9,
	MouseOther_8  = 10,
	MouseOther_9  = 11,
	MouseOther_10 = 12,
	MouseOther_11 = 13,
	MouseOther_12 = 14,
	MouseOther_13 = 15,
	MouseOther_14 = 16,
	MouseOther_15 = 17,
	MouseOther_16 = 18,
	MouseOther_17 = 19,
	MouseOther_18 = 20,
	MouseOther_19 = 21,
	MouseOther_20 = 22,
	MouseOther_21 = 23,
	MouseOther_22 = 24,
	MouseOther_23 = 25,
	MouseOther_24 = 26,
	MouseOther_25 = 27,
	MouseOther_26 = 28,
	MouseOther_27 = 29,
	MouseOther_28 = 30,
	MouseOther_29 = 31
}

InputKeyboardKey :: enum {
	None				= 0x00,
	N0					= 0x01,
	N1					= 0x02,
	N2					= 0x03,
	N3					= 0x04,
	N4					= 0x05,
	N5					= 0x06,
	N6					= 0x07,
	N7					= 0x08,
	N8					= 0x09,
	N9					= 0x0A,
	A					= 0x0B,
	B					= 0x0C,
	C					= 0x0D,
	D					= 0x0E,
	E					= 0x0F,
	F					= 0x10,
	G					= 0x11,
	H					= 0x12,
	I					= 0x13,
	J					= 0x14,
	K					= 0x15,
	L					= 0x16,
	M					= 0x17,
	N					= 0x18,
	O					= 0x19,
	P					= 0x1A,
	Q					= 0x1B,
	R					= 0x1C,
	S					= 0x1D,
	T					= 0x1E,
	U					= 0x1F,
	V					= 0x20,
	W					= 0x21,
	X					= 0x22,
	Y					= 0x23,
	Z					= 0x24,
	F1					= 0x25,
	F2					= 0x26,
	F3					= 0x27,
	F4					= 0x28,
	F5					= 0x29,
	F6					= 0x2A,
	F7					= 0x2B,
	F8					= 0x2C,
	F9					= 0x2D,
	F10					= 0x2E,
	F11					= 0x2F,
	F12					= 0x30,
	F13					= 0x31,
	F14					= 0x32,
	F16					= 0x33,
	F17					= 0x34,
	F18					= 0x35,
	F19					= 0x36,
	F15					= 0x37,
	F20					= 0x38,
	LeftArrow			= 0x39,
	RightArrow			= 0x3A,
	UpArrow				= 0x3B,
	DownArrow			= 0x3C,
	NPad0				= 0x3D,
	NPad1				= 0x3E,
	NPad2				= 0x3F,
	NPad3				= 0x40,
	NPad4				= 0x41,
	NPad5				= 0x42,
	NPad6				= 0x43,
	NPad7				= 0x44,
	NPad8				= 0x45,
	NPad9				= 0x46,
	NPadDecimal			= 0x47,
	NPadDivide			= 0x48,
	NPadMultiply		= 0x49,
	NPadMinus			= 0x4A,
	NPadPlus			= 0x4B,
	NPadEnter			= 0x4C,
	NPadEquals			= 0x4D,
	LeftShift			= 0x4E,
	LeftControl			= 0x4F,
	LeftAlt				= 0x50,
	LeftSuper			= 0x51,
	RightShift			= 0x52,
	RightControl		= 0x53,
	RightAlt			= 0x54,
	RightSuper			= 0x55,
	Apostrophe			= 0x56,
	Comma				= 0x57,
	Minus				= 0x58,
	Period				= 0x59,
	Slash				= 0x5A,
	Semicolon			= 0x5B,
	Equal				= 0x5C,
	LeftBracket			= 0x5D,
	Backslash			= 0x5E,
	RightBracket		= 0x5F,
	GraveAccent			= 0x60,
	Space				= 0x61,
	Escape				= 0x62,
	Enter				= 0x63,
	Tab					= 0x64,
	Backspace			= 0x65,
	PageUp				= 0x66,
	PageDown			= 0x67,
	Home				= 0x68,
	End					= 0x69,
	CapsLock			= 0x6A,
	VolumeUp			= 0x6B,
	VolumeDown			= 0x6C,
	Mute				= 0x6D,

	// Windows
	Insert				= 0x6E,
	Scroll_Lock			= 0x70,
	Num_Lock			= 0x71,
	Print_Screen		= 0x72,
	Pause				= 0x73,
	
	// Mac
	NPadClear			= 0x74,
	ForwardDelete		= 0x75,
	Function			= 0x76,
	Help				= 0x77,
	JIS_Yen				= 0x78,
	JIS_Underscore		= 0x79,
	JIS_KeypadComma		= 0x7A,
	JIS_Eisu			= 0x7B,
	JIS_Kana			= 0x7C,
	ISO_Section			= 0x7D,
}

