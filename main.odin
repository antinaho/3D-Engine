package main

import "core:mem"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:time"

vert_shader_code :: #load("shaders/vert.spv")
frag_shader_code :: #load("shaders/frag.spv")

model :: "viking_room.obj"
model_tex :: "viking_room.png"

Vertex :: struct #align(16) {
    position: [3]f32,
	_: f32,

	normal: [3]f32,
	_: f32,

    color: [4]f32,
	
	uvs: [2]f32,
	_: [2]f32,
}

import "core:math"
import "core:math/linalg"
matrix_perspective_right_hand :: proc(nearZ, farZ, aspect, fovy_rad: f32) -> linalg.Matrix4x4f32 {
	ys := 1.0 / math.tan_f32(fovy_rad * 0.5)
	xs := ys / aspect
	zs := farZ / (nearZ - farZ)
	return linalg.Matrix4x4f32 {
		xs,	0,	0,	0,
		0,	ys,	0,	0,
		0,	0,	zs,	nearZ * zs,
		0,	0,	-1,	0
	}
}

import alg "core:math/linalg"

@(private="file")
application: ^Application

WindowInput :: struct {
	keys_press_started: #sparse [KeyboardKey]bool,
	keys_held: #sparse [KeyboardKey]bool,
	keys_released: #sparse [KeyboardKey]bool,
}

ApplicationWindow :: struct {
	window: ^Window,
	close_requested: bool,
	flags: WindowFlags,
	renderer: ^Renderer,
	

	using _ : WindowInput,
	layers: [dynamic]Layer,
}
cmd_buffer: Command_Buffer
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

	renderer.clear_color = DARKPURP

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
	aw.keys_press_started = {}
	aw.keys_released = {}

	aw.window.process_events(aw.window)
	
	events := aw.window.get_events(aw.window)

	for &event in events {
		switch &e in event {
			case WindowEventCloseRequested:
				aw.close_requested = true				
			case KeyPressedEvent:
				aw.keys_press_started[e.key] = aw.keys_held[e.key] ~ true
				aw.keys_held[e.key] = true
			case KeyReleasedEvent:
				aw.keys_released[e.key] = true
				aw.keys_held[e.key] = false
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
			case MouseReleasedEvent:
			case MousePositionEvent:
			case MouseScrollEvent:
		}
	}

	#reverse for &layer in aw.layers {
	
		if layer.ingest_events != nil { 
			layer.ingest_events(aw) 
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
	ingest_events: proc(input: ^WindowInput),
}

render_pass_3d: Renderer_3D

run :: proc() {

	render_pass_3d = init_renderer_3d(1280, 720)
	//defer destroy_renderer_3d(&render_pass_3d)

	b = init_buffer_with_size(size_of(Vertex) * len(TriangleVertices), .Vertex, .Static)
	fill_buffer(&b, raw_data(TriangleVertices[:]), size_of(Vertex) * len(TriangleVertices))

	bi = init_buffer_with_size(size_of(u32) * len(TriangleIndices), .Index, .Static)
	fill_buffer(&bi, raw_data(TriangleIndices[:]), size_of(u32) * len(TriangleIndices))

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

key_went_down :: proc(input: ^WindowInput, key: KeyboardKey) -> bool {
	return input.keys_press_started[key]
}

key_went_up :: proc(input: ^WindowInput, key: KeyboardKey) -> bool {
	return input.keys_released[key]
}

key_is_held :: proc(input: ^WindowInput, key: KeyboardKey) -> bool {
	return input.keys_held[key]
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

MouseButton :: enum u8 {
	Left 	= 0,
	Right 	= 1,
	Middle 	= 2,

	Limit 	= 255,
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
	Delete				= 0x6F,
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
