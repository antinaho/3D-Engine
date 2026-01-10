
package main

import NS "core:sys/darwin/Foundation"

import "base:intrinsics"
import "base:runtime"

import "core:fmt"

MacWindowAPI :: WindowAPI {
	close = _mac_close_window,
	get_window_handle = _mac_get_window_handle,
}

MacPlatform :: struct {
	window: ^NS.Window,
}

@(private="file")
ns_app: ^NS.Application

_mac_process_events :: proc() {
	event: ^NS.Event
	for {
		event = ns_app->nextEventMatchingMask(NS.EventMaskAny, NS.Date_distantPast(), NS.DefaultRunLoopMode, true)
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
		ns_app->sendEvent(event)
	}
}

_mac_get_window_handle :: proc(w: ^Window) -> WindowHandle {
	platform := cast(^MacPlatform)w.platform
	return cast(WindowHandle)platform.window
}

_mac_close_window :: proc(application_window: ^ApplicationWindow) {
	platform := cast(^MacPlatform)application_window.window.platform
	platform.window->close()
}

window_create_mac :: proc(application_window: ^ApplicationWindow, width, height: int, title: string, flags: WindowFlags) -> ^Window {
	window := new(Window, application_window.window_allocator)
	platform := new(MacPlatform, application_window.window_allocator)

	ns_app = NS.Application.sharedApplication()
	ns_app->setActivationPolicy(.Regular)
	
	platform.window = NS.Window_alloc()
	platform.window->setReleasedWhenClosed(true)

	application_window.width = width
	application_window.height = height
	application_window.title = title

	rect := NS.Rect{
		size = {NS.Float(width), NS.Float(height)},
    }

	platform.window->initWithContentRect(rect, { .Resizable, .Closable, .Titled, .Miniaturizable }, .Buffered, false)

	window_title := NS.alloc(NS.String)->initWithOdinString(title)
	defer window_title->release()
	platform.window->setTitle(window_title)
	platform.window->setBackgroundColor(NS.Color_whiteColor())

	if .MainWindow in flags {
		platform.window->makeKeyAndOrderFront(nil)
		//platform.window->makeMainWindow()	
	} else {
		platform.window->makeKeyAndOrderFront(nil)
	}
	
    platform.window->center()

	if WindowDelegate == nil {
		WindowDelegate = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "WindowEventsAPI", 0)

		windowShouldClose :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
			del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
			context = application.ctx
			del.window_should_close(del.application_window, notification)
		}
		NS.class_addMethod(WindowDelegate, intrinsics.objc_find_selector("windowShouldClose:"), auto_cast windowShouldClose, "v@:@")
		
		windowWillClose :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
			del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
			context = application.ctx
			del.window_will_close(notification)
		}
		NS.class_addMethod(WindowDelegate, intrinsics.objc_find_selector("windowWillClose:"), auto_cast windowWillClose, "v@:@")
		
		windowDidResize :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
			del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
			context = application.ctx
			del.window_did_resize(del.application_window, notification)
		}
		NS.class_addMethod(WindowDelegate, intrinsics.objc_find_selector("windowDidResize:"), auto_cast windowDidResize, "v@:@")
		
		windowDidMiniaturize :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
			del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
			context = application.ctx
			del.window_did_miniaturize(del.application_window, notification)
		}
		NS.class_addMethod(WindowDelegate, intrinsics.objc_find_selector("windowDidMiniaturize:"), auto_cast windowDidMiniaturize, "v@:@")
		
		windowDidDeminiaturize :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
			del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
			context = application.ctx
			del.window_did_deminiaturize(del.application_window, notification)
		}
		NS.class_addMethod(WindowDelegate, intrinsics.objc_find_selector("windowDidDeminiaturize:"), auto_cast windowDidDeminiaturize, "v@:@")

		windowDidEnterFullScreen :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
			del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
			context = application.ctx
			del.window_did_enter_fullscreen(del.application_window, notification)
		}
		NS.class_addMethod(WindowDelegate, intrinsics.objc_find_selector("windowDidEnterFullScreen:"), auto_cast windowDidEnterFullScreen, "v@:@")
		
		windowDidExitFullScreen :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
			del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
			context = application.ctx
			del.window_did_exit_fullscreen(del.application_window, notification)
		}
		NS.class_addMethod(WindowDelegate, intrinsics.objc_find_selector("windowDidExitFullScreen:"), auto_cast windowDidExitFullScreen, "v@:@")

		windowDidMove :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
			del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
			context = application.ctx
			del.window_did_move(del.application_window, notification)
		}
		NS.class_addMethod(WindowDelegate, intrinsics.objc_find_selector("windowDidMove:"), auto_cast windowDidMove, "v@:@")
		
		windowDidBecomeKey :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
			del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
			context = application.ctx
			del.window_did_become_key(del.application_window, notification)
		}
		NS.class_addMethod(WindowDelegate, intrinsics.objc_find_selector("windowDidBecomeKey:"), auto_cast windowDidBecomeKey, "v@:@")
		
		windowDidResignKey :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
			del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
			context = application.ctx
			del.window_did_resign_key(del.application_window, notification)
		}
		NS.class_addMethod(WindowDelegate, intrinsics.objc_find_selector("windowDidResignKey:"), auto_cast windowDidResignKey, "v@:@")

		windowDidChangeOcclusionState :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
			del := cast(^WindowEventsAPI)NS.object_getIndexedIvars(self)
			context = application.ctx
			del.window_did_change_occlusion_state(del.application_window, notification)
		}
		NS.class_addMethod(WindowDelegate, intrinsics.objc_find_selector("windowDidChangeOcclusionState:"), auto_cast windowDidChangeOcclusionState, "v@:@")

		NS.objc_registerClassPair(WindowDelegate)
	}

	del := NS.class_createInstance(WindowDelegate, size_of(WindowEventsAPI))

	del_internal := cast(^WindowEventsAPI)NS.object_getIndexedIvars(del)
	del_internal^ = {
		application_window = application_window,
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
		window_did_change_occlusion_state = window_did_change_occlusion_state,
	}
			
	window_delegate := cast(^GameWindowDelegate)del
	
	platform.window->setDelegate(window_delegate)

	window.api = MacWindowAPI
	window.platform = cast(_Platform)platform

	ns_app->activate()
	return window
}

// Cursed swamp

@(private)
WindowDelegate: ^intrinsics.objc_class
		
WindowEventsAPI :: struct {
	application_window				  : ^ApplicationWindow,
	window_should_close		          : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_will_close                 : proc(notification: ^NS.Notification),
	window_will_start_live_resize     : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_end_live_resize        : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_resize                 : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_miniaturize            : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_deminiaturize          : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_enter_fullscreen       : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_exit_fullscreen        : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_move               	  : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_become_key             : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_resign_key             : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_become_main            : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_resign_main            : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
	window_did_change_occlusion_state : proc(application_window: ^ApplicationWindow, notification: ^NS.Notification),
}

code_to_mouse_button := [64]InputMouseButton {
	0  = .Left,
	1  = .Right,
	2  = .Middle,
	3  = .MouseOther_1,
	4  = .MouseOther_2,
	5  = .MouseOther_3,
	6  = .MouseOther_4,
	7  = .MouseOther_5,
	8  = .MouseOther_6,
	9  = .MouseOther_7,
	10 = .MouseOther_8,
	11 = .MouseOther_9,
	12 = .MouseOther_10,
	13 = .MouseOther_11,
	14 = .MouseOther_12,
	15 = .MouseOther_13,
	16 = .MouseOther_14,
	17 = .MouseOther_15,
	18 = .MouseOther_16,
	19 = .MouseOther_17,
	20 = .MouseOther_18,
	21 = .MouseOther_19,
	22 = .MouseOther_20,
	23 = .MouseOther_21,
	24 = .MouseOther_22,
	25 = .MouseOther_23,
	26 = .MouseOther_24,
	27 = .MouseOther_25,
	28 = .MouseOther_26,
	29 = .MouseOther_27,
	30 = .MouseOther_28,
	31 = .MouseOther_29
}

code_to_keyboard_key := [255]InputKeyboardKey {
	NS.kVK.ANSI_1 				= .N1,
	NS.kVK.ANSI_2 				= .N2,
	NS.kVK.ANSI_3 				= .N3,
	NS.kVK.ANSI_4 				= .N4,
	NS.kVK.ANSI_5 				= .N5,
	NS.kVK.ANSI_6 				= .N6,
	NS.kVK.ANSI_7 				= .N7,
	NS.kVK.ANSI_8 				= .N8,
	NS.kVK.ANSI_9 				= .N9,
	NS.kVK.ANSI_0 				= .N0,
	NS.kVK.ANSI_Keypad1 		= .NPad1,
	NS.kVK.ANSI_Keypad2 		= .NPad2,
	NS.kVK.ANSI_Keypad3 		= .NPad3,
	NS.kVK.ANSI_Keypad4 		= .NPad4,
	NS.kVK.ANSI_Keypad5 		= .NPad5,
	NS.kVK.ANSI_Keypad6 		= .NPad6,
	NS.kVK.ANSI_Keypad7 		= .NPad7,
	NS.kVK.ANSI_Keypad8 		= .NPad8,
	NS.kVK.ANSI_Keypad9 		= .NPad9,
	NS.kVK.ANSI_Keypad0 		= .NPad0,
	NS.kVK.ANSI_KeypadClear 	= .NPadClear,
	NS.kVK.ANSI_KeypadDecimal 	= .NPadDecimal,
	NS.kVK.ANSI_KeypadDivide 	= .NPadDivide,
	NS.kVK.ANSI_KeypadMultiply 	= .NPadMultiply,
	NS.kVK.ANSI_KeypadMinus 	= .NPadMinus,
	NS.kVK.ANSI_KeypadPlus 		= .NPadPlus,
	NS.kVK.ANSI_KeypadEnter 	= .NPadEnter,
	NS.kVK.ANSI_KeypadEquals 	= .NPadEquals,
	NS.kVK.ANSI_A 				= .A,
	NS.kVK.ANSI_S 				= .S,
	NS.kVK.ANSI_D 				= .D,
	NS.kVK.ANSI_F 				= .F,
	NS.kVK.ANSI_H 				= .H,
	NS.kVK.ANSI_G 				= .G,
	NS.kVK.ANSI_Z 				= .Z,
	NS.kVK.ANSI_X 				= .X,
	NS.kVK.ANSI_C 				= .C,
	NS.kVK.ANSI_V 				= .V,
	NS.kVK.ANSI_B 				= .B,
	NS.kVK.ANSI_Q 				= .Q,
	NS.kVK.ANSI_W 				= .W,
	NS.kVK.ANSI_E 				= .E,
	NS.kVK.ANSI_R 				= .R,
	NS.kVK.ANSI_Y 				= .Y,
	NS.kVK.ANSI_T 				= .T,
	NS.kVK.ANSI_O 				= .O,
	NS.kVK.ANSI_U 				= .U,
	NS.kVK.ANSI_I 				= .I,
	NS.kVK.ANSI_P 				= .P,
	NS.kVK.ANSI_L 				= .L,
	NS.kVK.ANSI_J 				= .J,
	NS.kVK.ANSI_K 				= .K,
	NS.kVK.ANSI_N 				= .N,
	NS.kVK.ANSI_M 				= .M,
	NS.kVK.F1 					= .F1,
	NS.kVK.F2 					= .F2,
	NS.kVK.F3 					= .F3,
	NS.kVK.F4 					= .F4,
	NS.kVK.F5 					= .F5,
	NS.kVK.F6 					= .F6,
	NS.kVK.F7 					= .F7,
	NS.kVK.F8 					= .F8,
	NS.kVK.F9 					= .F9,
	NS.kVK.F10 					= .F10,
	NS.kVK.F11 					= .F11,
	NS.kVK.F12 					= .F12,
	NS.kVK.F13 					= .F13,
	NS.kVK.F14 					= .F14,
	NS.kVK.F15 					= .F15,
	NS.kVK.F16 					= .F16,
	NS.kVK.F17 					= .F17,
	NS.kVK.F18 					= .F18,
	NS.kVK.F19 					= .F19,
	NS.kVK.F20 					= .F20,
	NS.kVK.LeftArrow  			= .LeftArrow,
	NS.kVK.RightArrow 			= .RightArrow,
	NS.kVK.DownArrow  			= .DownArrow,
	NS.kVK.UpArrow    			= .UpArrow,
	NS.kVK.Shift 				= .LeftShift,
	NS.kVK.Control 				= .LeftControl,
	NS.kVK.Option 				= .LeftAlt,
	NS.kVK.Command 				= .LeftSuper,
	NS.kVK.RightShift 			= .RightShift,
	NS.kVK.RightControl 		= .RightControl,
	NS.kVK.RightOption 			= .RightAlt,
	NS.kVK.RightCommand			= .RightSuper,
	NS.kVK.ANSI_Quote 			= .Apostrophe,
	NS.kVK.ANSI_Comma 			= .Comma,
	NS.kVK.ANSI_Minus 			= .Minus,
	NS.kVK.ANSI_Period 			= .Period,
	NS.kVK.ANSI_Slash 			= .Slash,
	NS.kVK.ANSI_Semicolon 		= .Semicolon,
	NS.kVK.ANSI_Equal 			= .Equal,
	NS.kVK.ANSI_LeftBracket 	= .LeftBracket,
	NS.kVK.ANSI_Backslash 		= .Backslash,
	NS.kVK.ANSI_RightBracket 	= .RightBracket,
	NS.kVK.ANSI_Grave 			= .GraveAccent,
	NS.kVK.Space 				= .Space,
	NS.kVK.Escape 				= .Escape,
	NS.kVK.Return 				= .Enter,
	NS.kVK.Tab 					= .Tab,
	NS.kVK.Delete				= .Backspace,
	NS.kVK.ForwardDelete 		= .ForwardDelete,
	NS.kVK.Home 				= .Home,
	NS.kVK.PageUp 				= .PageUp,
	NS.kVK.End 					= .End,
	NS.kVK.PageDown 			= .PageDown,
	NS.kVK.CapsLock 			= .CapsLock,
	NS.kVK.Function 			= .Function,
	NS.kVK.VolumeUp 			= .VolumeUp,
	NS.kVK.VolumeDown 			= .VolumeDown,
	NS.kVK.Mute 				= .Mute,
	NS.kVK.Help 				= .Help,
	NS.kVK.JIS_Yen				= .JIS_Yen,
	NS.kVK.JIS_Underscore 		= .JIS_Underscore,
	NS.kVK.JIS_KeypadComma 		= .JIS_KeypadComma,
	NS.kVK.JIS_Eisu 			= .JIS_Eisu,
	NS.kVK.JIS_Kana 			= .JIS_Kana,
	NS.kVK.ISO_Section 			= .ISO_Section,
}

@(objc_class="GameWindowDelegate", objc_superclass=NS.Object, objc_implement=true)
GameWindowDelegate :: struct {
    using _ : NS.WindowDelegate,
}

///////////////////
// Closing window

//User requested close
window_should_close :: proc (application_window: ^ApplicationWindow, notification: ^NS.Notification) {
    input_new_event(WindowEventCloseRequested{ application_window })
}

window_will_close :: proc (notification: ^NS.Notification) { }

///////////////////
// Resizing window
window_did_resize :: proc (application_window: ^ApplicationWindow, notification: ^NS.Notification) {
	platform := cast(^MacPlatform)application_window.window.platform
	frame := platform.window->frame()
	input_new_event(WindowResizeEvent{ application_window, int(frame.width), int(frame.height) })
}

///////////////////////
// Minimizing window

window_did_miniaturize :: proc (application_window: ^ApplicationWindow, notification: ^NS.Notification) {
	input_new_event(WindowMinimizeStartEvent{ application_window })
}

window_did_deminiaturize :: proc (application_window: ^ApplicationWindow, notification: ^NS.Notification) {
	input_new_event(WindowMinimizeEndEvent{ application_window })
}

///////////////////////
// Fullscreen window

window_did_enter_fullscreen :: proc (application_window: ^ApplicationWindow, notification: ^NS.Notification) {
	input_new_event(WindowEnterFullscreenEvent{ application_window })
}

window_did_exit_fullscreen :: proc (application_window: ^ApplicationWindow, notification: ^NS.Notification) {
	input_new_event(WindowExitFullscreenEvent{ application_window })
}

///////////////////////
// Moving window

window_did_move :: proc (application_window: ^ApplicationWindow, notification: ^NS.Notification) {
	platform := cast(^MacPlatform)application_window.window.platform
    frame := platform.window->frame()
	x := frame.x
	y := frame.y

	input_new_event(WindowMoveEvent{ application_window, int(x), int(y) })
}

///////////////////////
// Focusing window

window_did_become_key :: proc (application_window: ^ApplicationWindow, notification: ^NS.Notification) {
	input_new_event(WindowDidBecomeKey{ application_window })
}

window_did_resign_key :: proc (application_window: ^ApplicationWindow, notification: ^NS.Notification) {
	input_new_event(WindowDidResignKey{ application_window })
}

//////////////////////
// Occlusion state

window_did_change_occlusion_state :: proc (application_window: ^ApplicationWindow, notification: ^NS.Notification) {
	platform := cast(^MacPlatform)application_window.window.platform

	visible := platform.window->occlusionStateVisible()

	if visible {
		input_new_event(WindowBecameVisibleEvent{ application_window })
	} else if !visible {
		input_new_event(WindowBecameHiddenEvent{ application_window })
	}
}