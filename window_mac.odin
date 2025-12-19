
package main

import NS "core:sys/darwin/Foundation"

import "base:intrinsics"
import "base:runtime"
import "core:log"

MacWindowAPI :: WindowAPI {
	process_events = _mac_process_events,
	clear_events = _mac_clear_events,
	get_events = _mac_get_events,
	close = _mac_close_window,
}

MacPlatform :: struct {
	window: ^NS.Window,

	ctx: runtime.Context,
	events: [dynamic]Event,
	title: ^NS.String,
	width: int,
	height: int,
}

ns_app: ^NS.Application

_mac_clear_events :: proc(w: ^Window) {
	platform := cast(^MacPlatform)w.platform
	clear(&platform.events)
}

_mac_get_events :: proc(w: ^Window) -> []Event {
	platform := cast(^MacPlatform)w.platform
	return platform.events[:]
}

_mac_process_events :: proc(w: ^Window) {
	event: ^NS.Event
	platform := cast(^MacPlatform)w.platform
	for {
		event = ns_app->nextEventMatchingMask(NS.EventMaskAny, NS.Date_distantPast(), NS.DefaultRunLoopMode, true)
		if event == nil { break }
		
		#partial switch event->type() {
			case .KeyDown:
				append(&platform.events, KeyPressedEvent{key=code_to_keyboard_key[event->keyCode()]})
			case .KeyUp:
				append(&platform.events, KeyReleasedEvent{key=code_to_keyboard_key[event->keyCode()]})
			case .LeftMouseDown:
				append(&platform.events, MousePressedEvent{button=code_to_mouse_button[MouseButton.Left]})
			case .LeftMouseUp:
				append(&platform.events, MouseReleasedEvent{button=code_to_mouse_button[MouseButton.Left]})
			case .RightMouseDown:
				append(&platform.events, MousePressedEvent{button=code_to_mouse_button[MouseButton.Right]})
			case .RightMouseUp:
				append(&platform.events, MouseReleasedEvent{button=code_to_mouse_button[MouseButton.Right]})
			case .MouseMoved:
				position := event->locationInWindow()		
				append(&platform.events, MousePositionEvent{x=f64(position.x), y=f64(position.y)})
			case .ScrollWheel:
				scroll_x, scroll_y := event->scrollingDelta()
				append(&platform.events, MouseScrollEvent{x=f64(scroll_x), y=f64(scroll_y)})
		}
		ns_app->sendEvent(event)
	}
}

_mac_close_window :: proc(w: ^Window) {
	platform := cast(^MacPlatform)w.platform
	platform.window->close()
}

window_create_mac :: proc(width, height: int, title: string, ctx: runtime.Context, allocator: runtime.Allocator, flags: WindowFlags) -> ^Window {
	window := new(Window)
	platform := new(MacPlatform)

	ns_app = NS.Application.sharedApplication()
	ns_app->setActivationPolicy(.Regular)

	platform.title = NS.alloc(NS.String)->initWithOdinString(title)
	platform.width = width
	platform.height = height
	platform.events = make([dynamic]Event, allocator)
	platform.ctx = ctx
	platform.window = NS.Window_alloc()

	rect := NS.Rect{
		size = {NS.Float(width), NS.Float(height)},
    }

	platform.window->initWithContentRect(rect, { .Resizable, .Closable, .Titled, .Miniaturizable }, .Buffered, false)

	platform.window->setTitle(platform.title)
	platform.window->setBackgroundColor(NS.Color_whiteColor())

	if .MainWindow in flags {
		platform.window->makeKeyAndOrderFront(nil)
		platform.window->makeMainWindow()	
	} else {
		platform.window->makeKeyAndOrderFront(nil)
	}
	
    platform.window->center()

	if class == nil {
		class = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "WindowEventsAPI", 0)

		NS.class_addMethod(class, intrinsics.objc_find_selector("windowShouldClose:"), auto_cast windowShouldClose, "v@:@")
		NS.class_addMethod(class, intrinsics.objc_find_selector("windowWillClose:"), auto_cast windowWillClose, "v@:@")
		NS.class_addMethod(class, intrinsics.objc_find_selector("windowDidResize:"), auto_cast windowDidResize, "v@:@")
		NS.class_addMethod(class, intrinsics.objc_find_selector("windowDidMiniaturize:"), auto_cast windowDidMiniaturize, "v@:@")
		NS.class_addMethod(class, intrinsics.objc_find_selector("windowDidDeminiaturize:"), auto_cast windowDidDeminiaturize, "v@:@")
		NS.class_addMethod(class, intrinsics.objc_find_selector("windowDidEnterFullScreen:"), auto_cast windowDidEnterFullScreen, "v@:@")
		NS.class_addMethod(class, intrinsics.objc_find_selector("windowDidExitFullScreen:"), auto_cast windowDidExitFullScreen, "v@:@")
		NS.class_addMethod(class, intrinsics.objc_find_selector("windowDidMove:"), auto_cast windowDidMove, "v@:@")
		NS.class_addMethod(class, intrinsics.objc_find_selector("windowDidBecomeKey:"), auto_cast windowDidBecomeKey, "v@:@")
		NS.class_addMethod(class, intrinsics.objc_find_selector("windowDidResignKey:"), auto_cast windowDidResignKey, "v@:@")
				
		NS.objc_registerClassPair(class)
	}

	del := NS.class_createInstance(class, size_of(WindowEventsAPI))

	del_internal := cast(^WindowEventsAPI)NS.object_getIndexedIvars(del)
	del_internal^ = {
		platform = platform,
		window_should_close = window_should_close,
		window_will_close = window_will_close,
		window_did_resize = window_did_resize,
		window_did_miniaturize = window_did_miniaturize,
		window_did_deminiaturize = window_did_deminiaturize,
		window_did_enter_fullscreen = window_did_enter_fullscreen,
		window_did_exit_fullscreen = window_did_exit_fullscreen,
		window_did_move = window_did_move,
		window_did_become_key = window_did_become_key,
		window_did_resign_key = window_did_resign_key,
	}
			
	wd := cast(^GameWindowDelegate)del

	platform.window->setDelegate(wd)

	window.api = MacWindowAPI
	window.platform = cast(Platform)platform

	ns_app->activate()
	return window
}

// Cursed swamp

class: ^intrinsics.objc_class
		
windowShouldClose :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_should_close(del.platform, notification)
}

windowWillClose :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_will_close(notification)
}

windowDidResize :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_did_resize(del.platform, notification)
}


windowDidMiniaturize :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_did_miniaturize(del.platform, notification)
}

windowDidDeminiaturize :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_did_deminiaturize(del.platform, notification)
}

windowDidEnterFullScreen :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_did_enter_fullscreen(del.platform, notification)
}


windowDidExitFullScreen :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_did_exit_fullscreen(del.platform, notification)
}


windowDidMove :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_did_move(del.platform, notification)
}

	windowDidBecomeKey :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_did_become_key(del.platform, notification)
}

		windowDidResignKey :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_did_resign_key(del.platform, notification)
}

windowDidBecomeMain :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_did_become_main(del.platform, notification)
}

windowDidResignMain :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
	context = del.ctx
	del.window_did_resign_main(del.platform, notification)
}

WindowEventsAPI :: struct {
	using platform : ^MacPlatform,
	window_should_close: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_will_close: proc(notification: ^NS.Notification),
	window_will_start_live_resize: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_did_end_live_resize: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_did_resize: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_did_miniaturize: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_did_deminiaturize: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_did_enter_fullscreen: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_did_exit_fullscreen: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_did_move: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_did_become_key: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_did_resign_key: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_did_become_main: proc(platform: ^MacPlatform, notification: ^NS.Notification),
	window_did_resign_main: proc(platform: ^MacPlatform, notification: ^NS.Notification),
}

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

@(objc_class="GameWindowDelegate", objc_superclass=NS.Object, objc_implement=true)
GameWindowDelegate :: struct {
    using _ : NS.WindowDelegate,
}

///////////////////
// Closing window

//User requested close
window_should_close :: proc (platform: ^MacPlatform, notification: ^NS.Notification) {
	log.debug("Close requested")
    append(&platform.events, WindowEventCloseRequested{})
}

window_will_close :: proc (notification: ^NS.Notification) {
    log.debug("Closing")
}

///////////////////
// Resizing window

window_did_resize :: proc (platform: ^MacPlatform, notification: ^NS.Notification) {
	frame := platform.window->frame()
	platform.width = int(frame.width)
	platform.height = int(frame.height)

	append(&platform.events, WindowResizeEvent{int(frame.width), int(frame.height)})
}

///////////////////////
// Minimizing window

window_did_miniaturize :: proc (platform: ^MacPlatform, notification: ^NS.Notification) {
	append(&platform.events, WindowMinimizeStartEvent{})
}

window_did_deminiaturize :: proc (platform: ^MacPlatform, notification: ^NS.Notification) {
	append(&platform.events, WindowMinimizeEndEvent{})
}

///////////////////////
// Fullscreen window

window_did_enter_fullscreen :: proc (platform: ^MacPlatform, notification: ^NS.Notification) {
	append(&platform.events, WindowEnterFullscreenEvent{})
}

window_did_exit_fullscreen :: proc (platform: ^MacPlatform, notification: ^NS.Notification) {
	append(&platform.events, WindowExitFullscreenEvent{})
}

///////////////////////
// Moving window

window_did_move :: proc (platform: ^MacPlatform, notification: ^NS.Notification) {
    frame := platform.window->frame()
	x := frame.x
	y := frame.y

	append(&platform.events, WindowMoveEvent{int(x), int(y)})
}

///////////////////////
// Focusing window

window_did_become_key :: proc (platform: ^MacPlatform, notification: ^NS.Notification) {
	append(&platform.events, WindowDidBecomeKey{})
}

window_did_resign_key :: proc (platform: ^MacPlatform, notification: ^NS.Notification) {
	append(&platform.events, WindowDidResignKey{})
}