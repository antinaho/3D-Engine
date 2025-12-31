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

Input :: struct {
	keys_press_started: #sparse [KeyboardKey]bool,
	keys_held: #sparse [KeyboardKey]bool,
	keys_released: #sparse [KeyboardKey]bool,

	mouse_press_started: #sparse [MouseButton]bool,
	mouse_held: #sparse [MouseButton]bool,
	mouse_released: #sparse [MouseButton]bool,

	mouse_position: [2]f64,
	mouse_move_delta: [2]f64,
	mouse_scroll_delta: [2]f64,
}
input: ^Input

ApplicationWindow :: struct {
	window: ^Window,
	close_requested: bool,
	flags: WindowFlags,
	renderer: ^Renderer,
	
	layers: [dynamic]Layer,
}
cmd_buffer: CommandBuffer
Application :: struct {
	ctx: runtime.Context,
	windows: [dynamic]ApplicationWindow,
}

init :: proc(width, height: int, title: string, allocator := context.allocator, loc := #caller_location) -> ^Application {
	if application != nil do log.panic("Trying to create more than one application")

	application = new(Application, allocator, loc)
	application.ctx = context
	application.windows = make([dynamic]ApplicationWindow)
	
	return application
}

create_window :: proc(width, height: int, title: string, allocator: runtime.Allocator, flags := WindowFlags{}) -> ^ApplicationWindow {
	window := window_create_mac(width, height, title, allocator, flags)
	renderer := metal_init(window)

	application_window := ApplicationWindow {
		window = window,
		flags = flags,
		renderer = renderer,
		layers = make([dynamic]Layer, allocator)
	}

	append(&application.windows, application_window)
	
	return &application.windows[len(application.windows) - 1]
}

add_layer :: proc(application_window: ^ApplicationWindow, layer: Layer) {
	append(&application_window.layers, layer)
}

close_requested :: proc() -> bool {
	#reverse for &aw, i in application.windows {		
		if .MainWindow not_in aw.flags && aw.close_requested {
			aw.renderer.cleanup(aw.window, aw.renderer)
			aw.window.close(aw.window)
			ordered_remove(&application.windows, i)
		}

		if .MainWindow in aw.flags && aw.close_requested {
			return true
		}
	}

	return false
}

update_window :: proc(aw: ^ApplicationWindow) {
	input.keys_press_started = {}
	input.keys_released = {}
	
	input.mouse_press_started = {}
	input.mouse_released = {}
	
	input.mouse_scroll_delta = {}
	input.mouse_move_delta = {}
	aw.window.process_events(aw.window)
	
	events := aw.window.get_events(aw.window)

	for &event in events {
		switch &e in event {
			case WindowEventCloseRequested:
				aw.close_requested = true

			case KeyPressedEvent:
				input.keys_press_started[e.key] = input.keys_held[e.key] ~ true
				input.keys_held[e.key] = true
			case KeyReleasedEvent:
				input.keys_released[e.key] = true
				input.keys_held[e.key] = false
			case WindowResizeEvent:
				aw.window.did_resize = true

			case WindowMinimizeStartEvent:
				aw.window.is_minimized = true
			case WindowMinimizeEndEvent:
				aw.window.is_minimized = false

			case WindowBecameVisibleEvent:
				aw.window.is_visible = true
			case WindowBecameHiddenEvent:
				aw.window.is_visible = false
			
			case WindowEnterFullscreenEvent:
			case WindowExitFullscreenEvent:
			case WindowMoveEvent:
			case WindowDidBecomeKey:
			case WindowDidResignKey:

			case MousePressedEvent:
				input.mouse_press_started[e.button] = input.mouse_held[e.button] ~ true
				input.mouse_held[e.button] = true
			case MouseReleasedEvent:
				input.mouse_released[e.button] = true
				input.mouse_held[e.button] = false
			case MousePositionEvent:
				input.mouse_position = {e.x, e.y}
			case MousePositionDeltaEvent:
				input.mouse_move_delta = {e.x, e.y}
			case MouseScrollEvent:
				input.mouse_scroll_delta = {e.x, e.y}
		}
	}

	#reverse for &layer in aw.layers {
	
		if layer.ingest_events != nil { 
			layer.ingest_events() 
		}
	}

	aw.window.clear_events(aw.window)

	cmd_buffer = init_command_buffer()
    defer destroy_command_buffer(&cmd_buffer)

	for layer in aw.layers {
		if layer.update != nil { 
			layer.update(delta) 
		}
	}

	if aw.renderer != nil {
		aw.renderer.draw(aw.window, aw.renderer) 
	}
}

Layer :: struct {
	update: proc(delta: f32),
	ingest_events: proc(),
}

render_pass_3d: DefaultRenderer

run :: proc() {
	
	render_pass_3d = init_default_renderer(1280, 720)
	//defer destroy_renderer_3d(&render_pass_3d)

	vertex_buf = init_buffer_with_size(size_of(Vertex) * 1000, .Vertex, .Dynamic)
	instance_buf = init_buffer_with_size(size_of(InstanceData) * 1000, .Vertex, .Dynamic)
	index_buf = init_buffer_with_size(size_of(u32) * 1000, .Index, .Dynamic)
	instance_data = make([dynamic]InstanceData)

	for !close_requested() {
		free_all(context.temp_allocator)
		delta = f32(time.duration_seconds(time.tick_since(prev_time)))
		runtime_app += delta
		prev_time = time.tick_now()
		
		#reverse for &aw in application.windows {

			update_window(&aw)
		}
	}
	
	for &aw in application.windows {
		delete(aw.layers)
		aw.renderer.cleanup(aw.window, aw.renderer)
		aw.window.close(aw.window)
	}

	delete(application.windows)

	free(application)
}

runtime_app: f32
delta: f32
prev_time := time.tick_now()

key_went_down :: proc(key: KeyboardKey) -> bool {
	return input.keys_press_started[key]
}

key_went_up :: proc(key: KeyboardKey) -> bool {
	return input.keys_released[key]
}

key_is_held :: proc(key: KeyboardKey) -> bool {
	return input.keys_held[key]
}

ScrollDirection :: enum {
	X,
	Y,
	Both,
}

scroll_directional :: proc(direction: ScrollDirection) -> f32 {
	if direction == .X {
		return f32(input.mouse_scroll_delta.x)
	} else if direction == .Y {
		return f32(input.mouse_scroll_delta.y)
	} else {
		return f32(input.mouse_scroll_delta.x) + f32(input.mouse_scroll_delta.y)
	}
}

scroll_directional_vector :: proc(direction: ScrollDirection) -> Vector2 {
	if direction == .X {
		return {1, 0} * f32(input.mouse_scroll_delta.x)
	} else if direction == .Y {
		return {0, 1} * f32(input.mouse_scroll_delta.y)
	} else {
		return {f32(input.mouse_scroll_delta.x), f32(input.mouse_scroll_delta.y)}
	}	
}

mouse_position :: proc() -> Vector2 {
	return {f32(input.mouse_position.x), f32(input.mouse_position.y)}
}

mouse_directional :: proc(direction: ScrollDirection) -> f32 {
	//log.debug(input.mouse_move_delta.x)
	if direction == .X {
		return f32(input.mouse_move_delta.x)
	} else if direction == .Y {
		return f32(input.mouse_move_delta.y)
	} else {
		return f32(input.mouse_move_delta.x) + f32(input.mouse_move_delta.y)
	}
	
}

mouse_directional_vector :: proc(direction: ScrollDirection) -> Vector2 {
	if direction == .X {
		return {1, 0} * f32(input.mouse_move_delta.x)
	} else if direction == .Y {
		return {0, 1} * f32(input.mouse_move_delta.y)
	} else {
		return {f32(input.mouse_move_delta.x), f32(input.mouse_move_delta.y)}
	}
}

mouse_button_went_down :: proc(button: MouseButton) -> bool {
	return input.mouse_press_started[button]
}

mouse_button_went_up :: proc(button: MouseButton) -> bool {
	return input.mouse_released[button]
}

mouse_button_is_held :: proc(button: MouseButton) -> bool {
	return input.mouse_held[button]
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

MouseButton :: enum {
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

KeyboardKey :: enum {
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

	// Windows unique
	Insert				= 0x6E,
	Scroll_Lock			= 0x70,
	Num_Lock			= 0x71,
	Print_Screen		= 0x72,
	Pause				= 0x73,
	// Mac unique
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
