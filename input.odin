package main

import "base:runtime"
import "core:mem"
import "core:log"

MAX_INPUT_EVENTS_CAPACITY :: 64

g_input: ^Input

_input_arena: mem.Arena

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

	events: [MAX_INPUT_EVENTS_CAPACITY]Event,
	event_count: int,
}

input_init :: proc() {
	assert(g_input == nil, "Only 1 input object allowed")

	backing := make([]byte, (
		size_of(Input)
	))
	mem.arena_init(&_input_arena, backing)
	input_allocator := mem.arena_allocator(&_input_arena)

	g_input = new(Input, input_allocator)
}

input_destroy :: proc() {
	delete(_input_arena.data)
	mem.arena_free_all(&_input_arena)
}

input_clear_events :: #force_inline proc() {
	g_input.event_count = 0
}

input_get_events :: #force_inline proc()  -> []Event {
	return g_input.events[:g_input.event_count]
}

process_events :: proc() {
	when ODIN_OS == .Darwin {
		_mac_process_events()
	}
}

reset_input_state :: proc() {
	g_input.keys_press_started = {}
	g_input.keys_released = {}
	
	g_input.mouse_press_started = {}
	g_input.mouse_released = {}
	
	g_input.mouse_scroll_delta = {}
	g_input.mouse_move_delta = {}
}

input_new_event :: proc(event: Event) {
	if g_input.event_count == MAX_INPUT_EVENTS_CAPACITY - 1 {
		log.warn("Capped input events")
		return
	}

	g_input.events[g_input.event_count] = event
	g_input.event_count += 1
}

update_input_state :: proc() {
	events := input_get_events()

	for event in events {
		switch e in event {
			case WindowEventCloseRequested:
				e.window.close_requested = true

			case KeyPressedEvent:
				
				g_input.keys_press_started[e.key] = g_input.keys_held[e.key] ~ true
				g_input.keys_held[e.key] = true
			case KeyReleasedEvent:
				
				g_input.keys_released[e.key] = true
				g_input.keys_held[e.key] = false
			case WindowResizeEvent:
				e.window.did_resize = true
				e.window.width = e.width
				e.window.height = e.height
			
			case WindowMinimizeStartEvent:
				e.window.is_minimized = true
			case WindowMinimizeEndEvent:
				e.window.is_minimized = false
				

			case WindowBecameVisibleEvent:
				e.window.is_visible = true
			case WindowBecameHiddenEvent:
				e.window.is_visible = false
			
			case WindowEnterFullscreenEvent:
			case WindowExitFullscreenEvent:
			case WindowMoveEvent:



			case WindowDidBecomeKey:
				e.window.is_focused = true
			case WindowDidResignKey:
				e.window.is_focused = false

			case MousePressedEvent:
				
				g_input.mouse_press_started[e.button] = g_input.mouse_held[e.button] ~ true
				g_input.mouse_held[e.button] = true
			case MouseReleasedEvent:
				
				g_input.mouse_released[e.button] = true
				g_input.mouse_held[e.button] = false
			case MousePositionEvent:
				
				g_input.mouse_move_delta = {f32(e.x) - g_input.mouse_position.x, f32(e.y) - g_input.mouse_position.y}
				g_input.mouse_position = {f32(e.x), f32(e.y)}

			case MouseScrollEvent:
				
				g_input.mouse_scroll_delta = {f32(e.x), f32(e.y)}
		}
	}
}

input_key_went_down :: proc(key: InputKeyboardKey) -> bool {
	return g_input.keys_press_started[key]
}

input_key_went_up :: proc(key: InputKeyboardKey) -> bool {
	return g_input.keys_released[key]
}

input_key_is_held :: proc(key: InputKeyboardKey) -> bool {
	return g_input.keys_held[key]
}

InputScrollDirection :: enum {
	X,
	Y,
	Both,
}

input_scroll_directional :: proc(direction: InputScrollDirection) -> f32 {
	if direction == .X {
		return f32(g_input.mouse_scroll_delta.x)
	} else if direction == .Y {
		return f32(g_input.mouse_scroll_delta.y)
	} else {
		return f32(g_input.mouse_scroll_delta.x) + f32(g_input.mouse_scroll_delta.y)
	}
}

input_scroll_directional_vector :: proc(direction: InputScrollDirection) -> Vector2 {
	if direction == .X {
		return {1, 0} * f32(g_input.mouse_scroll_delta.x)
	} else if direction == .Y {
		return {0, 1} * f32(g_input.mouse_scroll_delta.y)
	} else {
		return {f32(g_input.mouse_scroll_delta.x), f32(g_input.mouse_scroll_delta.y)}
	}	
}

input_mouse_position :: proc() -> Vector2 {
	return {f32(g_input.mouse_position.x), f32(g_input.mouse_position.y)}
}

input_mouse_delta :: proc(direction: InputScrollDirection) -> f32 {
	if direction == .X {
		return f32(g_input.mouse_move_delta.x)
	} else if direction == .Y {
		return f32(g_input.mouse_move_delta.y)
	} else {
		return f32(g_input.mouse_move_delta.x) + f32(g_input.mouse_move_delta.y)
	}	
}

input_mouse_delta_vector :: proc(direction: InputScrollDirection) -> Vector2 {
	if direction == .X {
		return {1, 0} * f32(g_input.mouse_move_delta.x)
	} else if direction == .Y {
		return {0, 1} * f32(g_input.mouse_move_delta.y)
	} else {
		return {f32(g_input.mouse_move_delta.x), f32(g_input.mouse_move_delta.y)}
	}
}

input_mouse_button_went_down :: proc(button: InputMouseButton) -> bool {
	return g_input.mouse_press_started[button]
}

input_mouse_button_went_up :: proc(button: InputMouseButton) -> bool {
	return g_input.mouse_released[button]
}

input_mouse_button_is_held :: proc(button: InputMouseButton) -> bool {
	return g_input.mouse_held[button]
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
