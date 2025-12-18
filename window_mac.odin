#+private file

package main

import NS "core:sys/darwin/Foundation"

import "base:runtime"
import "core:log"

@(private="package")
WINDOW_MAC :: WindowInterface {
	init = mac_init,
	state_size = mac_state_size,

	process_events = mac_process_events,
	get_events = mac_get_events,
	clear_events = mac_clear_events,

	shutdown = mac_shutdown,
	window_handle = mac_window_handle,
	get_framebuffer_size = mac_get_framebuffer_size,

	framebuffer_resized = mac_framebuffer_resized,
	set_framebuffer_resized = mac_set_framebuffer_resized,
}

@(private="package")
MacWindowState :: struct {
	title: string,
	width, height: int,
	framebuffer_resized: bool,
	events: [dynamic]Event,
	allocator: runtime.Allocator,
	custom_context: runtime.Context,

	window: ^NS.Window,
    app: ^NS.Application,
}

state: ^MacWindowState

mac_set_framebuffer_resized :: proc(val: bool) {
	state.framebuffer_resized = val
}

mac_framebuffer_resized :: proc() -> bool {
	return state.framebuffer_resized
}

mac_get_framebuffer_size :: proc() -> (width, height: int) {
	frame := state.window->frame()
	width = int(frame.width)
	height = int(frame.height)
	return
}

mac_window_handle :: proc() -> rawptr {
	return state.window
}

mac_state_size :: proc() -> int {
	return size_of(MacWindowState)
}

mac_shutdown :: proc() {
	delete(state.events)
	free(state)
}

mac_clear_events :: proc() {
	runtime.clear(&state.events)
}

mac_init :: proc(window_state: rawptr, width, height: int, title: string, allocator: runtime.Allocator) {	
	state = (^MacWindowState)(window_state)

	state.app = NS.Application.sharedApplication()
    state.app->setActivationPolicy(.Regular)
	rect := NS.Rect{
		origin = {0, 0},
		size = {NS.Float(width), NS.Float(height)},
    }

	state.title = title
	state.width = width
	state.height = height
	state.allocator = allocator
	state.events = make([dynamic]Event, allocator)
	state.custom_context = context

	state.window = NS.Window_alloc()
    state.window->initWithContentRect(rect, { .Resizable, .Closable, .Titled }, .Buffered, NS.NO)

	nstitle := NS.alloc(NS.String)->initWithOdinString(title)
	defer NS.release(nstitle)
    state.window->setTitle(nstitle)
    state.window->setBackgroundColor(NS.Color_whiteColor())
    state.window->makeKeyAndOrderFront(nil)
    state.window->center()

	delegate := NS.alloc(GameWindowDelegate)->init()

    state.window->setDelegate(delegate)

    state.app->activate()
}

mac_process_events :: proc() {
	event: ^NS.Event
	for {
		event = state.app->nextEventMatchingMask(NS.EventMaskAny, NS.Date_distantPast(), NS.DefaultRunLoopMode, NS.YES)
		if event == nil { break }

		#partial switch event->type() {
			case .KeyDown:
				append(&state.events, KeyPressedEvent{key=code_to_keyboard_key[event->keyCode()]})
			case .KeyUp:
				append(&state.events, KeyReleasedEvent{key=code_to_keyboard_key[event->keyCode()]})
			case .LeftMouseDown:
				append(&state.events, MousePressedEvent{button=code_to_mouse_button[MOUSE_LEFT]})
			case .LeftMouseUp:
				append(&state.events, MouseReleasedEvent{button=code_to_mouse_button[MOUSE_LEFT]})
			case .RightMouseDown:
				append(&state.events, MousePressedEvent{button=code_to_mouse_button[MOUSE_RIGHT]})
			case .RightMouseUp:
				append(&state.events, MouseReleasedEvent{button=code_to_mouse_button[MOUSE_RIGHT]})
			case .MouseMoved:
				position := event->locationInWindow()		
				append(&state.events, MousePositionEvent{x=f64(position.x), y=f64(position.y)})
			case .ScrollWheel:
				scroll_x, scroll_y := event->scrollingDelta()
				append(&state.events, MouseScrollEvent{x=f64(scroll_x), y=f64(scroll_y)})
		}
		state.app->sendEvent(event)
	}
}

MOUSE_LEFT :: 0
MOUSE_RIGHT :: 1

code_to_mouse_button := [3]MouseButton {
	0 = .Left,
	1 = .Right,
} 

code_to_keyboard_key := [255]KeyboardKey {
	
	NS.kVK.ANSI_1 = .N1,
	NS.kVK.ANSI_2 = .N2,
	NS.kVK.ANSI_3 = .N3,
	NS.kVK.ANSI_4 = .N4,
	NS.kVK.ANSI_5 = .N5,
	NS.kVK.ANSI_6 = .N6,
	NS.kVK.ANSI_7 = .N7,
	NS.kVK.ANSI_8 = .N8,
	NS.kVK.ANSI_9 = .N9,
	NS.kVK.ANSI_0 = .N0,

	
	NS.kVK.ANSI_Keypad1 = .NPad1,
	NS.kVK.ANSI_Keypad2 = .NPad2,
	NS.kVK.ANSI_Keypad3 = .NPad3,
	NS.kVK.ANSI_Keypad4 = .NPad4,
	NS.kVK.ANSI_Keypad5 = .NPad5,
	NS.kVK.ANSI_Keypad6 = .NPad6,
	NS.kVK.ANSI_Keypad7 = .NPad7,
	NS.kVK.ANSI_Keypad8 = .NPad8,
	NS.kVK.ANSI_Keypad9 = .NPad9,
	NS.kVK.ANSI_Keypad0 = .NPad0,

	NS.kVK.ANSI_KeypadClear = .NPadClear,
	NS.kVK.ANSI_KeypadDecimal = .NPadDecimal,
	NS.kVK.ANSI_KeypadDivide = .NPadDivide,
	NS.kVK.ANSI_KeypadMultiply = .NPadMultiply,
	NS.kVK.ANSI_KeypadMinus = .NPadMinus,
	NS.kVK.ANSI_KeypadPlus = .NPadPlus,
	NS.kVK.ANSI_KeypadEnter = .NPadEnter,
	NS.kVK.ANSI_KeypadEquals = .NPadEquals,
	
	NS.kVK.ANSI_A = .A,
	NS.kVK.ANSI_S = .S,
	NS.kVK.ANSI_D = .D,
	NS.kVK.ANSI_F = .F,
	NS.kVK.ANSI_H = .H,
	NS.kVK.ANSI_G = .G,
	NS.kVK.ANSI_Z = .Z,
	NS.kVK.ANSI_X = .X,
	NS.kVK.ANSI_C = .C,
	NS.kVK.ANSI_V = .V,
	NS.kVK.ANSI_B = .B,
	NS.kVK.ANSI_Q = .Q,
	NS.kVK.ANSI_W = .W,
	NS.kVK.ANSI_E = .E,
	NS.kVK.ANSI_R = .R,
	NS.kVK.ANSI_Y = .Y,
	NS.kVK.ANSI_T = .T,
	NS.kVK.ANSI_O = .O,
	NS.kVK.ANSI_U = .U,
	NS.kVK.ANSI_I = .I,
	NS.kVK.ANSI_P = .P,
	NS.kVK.ANSI_L = .L,
	NS.kVK.ANSI_J = .J,
	NS.kVK.ANSI_K = .K,
	NS.kVK.ANSI_N = .N,
	NS.kVK.ANSI_M = .M,

	NS.kVK.F1 = .F1,
	NS.kVK.F2 = .F2,
	NS.kVK.F3 = .F3,
	NS.kVK.F4 = .F4,
	NS.kVK.F5 = .F5,
	NS.kVK.F6 = .F6,
	NS.kVK.F7 = .F7,
	NS.kVK.F8 = .F8,
	NS.kVK.F9 = .F9,
	NS.kVK.F10 = .F10,
	NS.kVK.F11 = .F11,
	NS.kVK.F12 = .F12,
	NS.kVK.F13 = .F13,
	NS.kVK.F14 = .F14,
	NS.kVK.F15 = .F15,
	NS.kVK.F16 = .F16,
	NS.kVK.F17 = .F17,
	NS.kVK.F18 = .F18,
	NS.kVK.F19 = .F19,
	NS.kVK.F20 = .F20,

	NS.kVK.LeftArrow  = .LeftArrow,
	NS.kVK.RightArrow = .RightArrow,
	NS.kVK.DownArrow  = .DownArrow,
	NS.kVK.UpArrow    = .UpArrow,

	NS.kVK.Shift = .LeftShift,
	NS.kVK.Control = .LeftControl,
	NS.kVK.Option = .LeftAlt,
	NS.kVK.Command = .LeftSuper,
	NS.kVK.RightShift = .RightShift,
	NS.kVK.RightControl = .RightControl,
	NS.kVK.RightOption = .RightAlt,
	NS.kVK.RightCommand = .RightSuper,

	NS.kVK.ANSI_Quote = .Apostrophe,
	NS.kVK.ANSI_Comma = .Comma,
	NS.kVK.ANSI_Minus = .Minus,
	NS.kVK.ANSI_Period = .Period,
	NS.kVK.ANSI_Slash = .Slash,
	NS.kVK.ANSI_Semicolon = .Semicolon,
	NS.kVK.ANSI_Equal = .Equal,
	NS.kVK.ANSI_LeftBracket = .LeftBracket,
	NS.kVK.ANSI_Backslash = .Backslash,
	NS.kVK.ANSI_RightBracket = .RightBracket,
	NS.kVK.ANSI_Grave = .GraveAccent,

	NS.kVK.Space = .Space,
	NS.kVK.Escape = .Escape,
	NS.kVK.Return = .Enter,
	NS.kVK.Tab = .Tab,
	NS.kVK.Delete = .Backspace,


	NS.kVK.ForwardDelete = .ForwardDelete,

	NS.kVK.Home = .Home,
	NS.kVK.PageUp = .PageUp,
	NS.kVK.End = .End,
	NS.kVK.PageDown = .PageDown,
	NS.kVK.CapsLock = .CapsLock,
	NS.kVK.Function = .Function,

	NS.kVK.VolumeUp = .VolumeUp,
	NS.kVK.VolumeDown = .VolumeDown,
	NS.kVK.Mute = .Mute,
	NS.kVK.Help = .Help,

	NS.kVK.JIS_Yen = .JIS_Yen,
	NS.kVK.JIS_Underscore = .JIS_Underscore,
	NS.kVK.JIS_KeypadComma = .JIS_KeypadComma,
	NS.kVK.JIS_Eisu = .JIS_Eisu,
	NS.kVK.JIS_Kana = .JIS_Kana,
	NS.kVK.ISO_Section = .ISO_Section,
}

mac_get_events :: proc() -> []Event {
	return state.events[:]
}

@(objc_class="GameWindowDelegate", objc_superclass=NS.Object, objc_implement=true)
GameWindowDelegate :: struct {
    using _ : NS.WindowDelegate,
}

@(objc_type=GameWindowDelegate, objc_name="windowShouldClose:")
window_should_close :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
    context = state.custom_context
    append(&state.events, WindowEventCloseRequested{})
}

@(objc_type=GameWindowDelegate, objc_name="windowWillClose:")
window_will_close :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
    context = state.custom_context
    log.debug("Closing")
}

@(objc_type=GameWindowDelegate, objc_name="windowDidResize:")
window_did_resize :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
    context = state.custom_context
	
	frame := state.window->frame()
	state.width = int(frame.width)
	state.height = int(frame.height)

	append(&state.events, WindowResizeEvent{int(frame.width), int(frame.height)})
	append(&state.events, WindowFramebufferResizeEvent{width=int(frame.width), height=int(frame.height)})
}

// @(objc_type=GameWindowDelegate, objc_name="windowDidMove:")
// window_did_move :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
//     context = state.custom_context
    
//     frame := state.window->frame()
//     fmt.printf("[DELEGATE] Window moved to: (%.0f, %.0f)\n", frame.x, frame.y)
// }

// @(objc_type=GameWindowDelegate, objc_name="windowDidBecomeKey:")
// window_did_become_key :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
//     context = runtime.default_context()
//     fmt.println("[DELEGATE] Window became key (focused)")
// }

// @(objc_type=GameWindowDelegate, objc_name="windowDidResignKey:")
// window_did_resign_key :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
//     context = runtime.default_context()
//     fmt.println("[DELEGATE] Window resigned key (lost focus)")
// }

// @(objc_type=GameWindowDelegate, objc_name="windowDidMiniaturize:")
// window_did_miniaturize :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
//     context = runtime.default_context()
//     fmt.println("[DELEGATE] Window minimized")
// }

// @(objc_type=GameWindowDelegate, objc_name="windowDidDeminiaturize:")
// window_did_deminiaturize :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
//     context = runtime.default_context()
//     fmt.println("[DELEGATE] Window restored from minimize")
// }

// @(objc_type=GameWindowDelegate, objc_name="windowDidEnterFullScreen:")
// window_did_enter_fullscreen :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
//     context = runtime.default_context()
//     fmt.println("[DELEGATE] Window entered fullscreen")
// }

// @(objc_type=GameWindowDelegate, objc_name="windowDidExitFullScreen:")
// window_did_exit_fullscreen :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
//     context = runtime.default_context()
//     fmt.println("[DELEGATE] Window exited fullscreen")
// }

// @(objc_type=GameWindowDelegate, objc_name="windowWillStartLiveResize:")
// window_will_start_live_resize :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
//     context = runtime.default_context()
//     fmt.println("[DELEGATE] Window will start live resize (user grabbed edge)")
// }

// @(objc_type=GameWindowDelegate, objc_name="windowDidEndLiveResize:")
// window_did_end_live_resize :: proc "c" (self: ^GameWindowDelegate, notification: ^NS.Notification) {
//     context = runtime.default_context()
//     fmt.println("[DELEGATE] Window did end live resize (user released edge)")
// }