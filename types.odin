package harp

CG_Float :: f64
CG_Key_Code :: u32
CG_Event_Flags :: u64
CG_Event_Type :: u32
CG_Event_Mask :: u32
CG_Event_Field :: i64
CG_Event_Ref :: rawptr
CG_Event_Tap_Proxy :: rawptr
CG_Event_Tap_Location :: u32
CG_Event_Tap_Placement :: u32
CG_Event_Tap_Options :: u32
CF_Mach_Port_Ref :: rawptr
CF_Run_Loop_Source_Ref :: rawptr
CF_Run_Loop_Ref :: rawptr
CF_Allocator_Ref :: rawptr
CF_String_Ref :: rawptr

CG_Point :: struct {
	x, y: CG_Float,
}
CG_Size :: struct {
	width, height: CG_Float,
}
CG_Rect :: struct {
	origin: CG_Point,
	size:   CG_Size,
}

CG_Event_Tap_Callback :: #type proc "c" (
	proxy: CG_Event_Tap_Proxy,
	kind: CG_Event_Type,
	event: CG_Event_Ref,
	refcon: rawptr,
) -> CG_Event_Ref

kCGSessionEventTap: CG_Event_Tap_Location : 1
kCGHeadInsertEventTap: CG_Event_Tap_Placement : 0
kCGEventTapOptionDefault: CG_Event_Tap_Options : 0
kCGEventKeyDown: CG_Event_Type : 10
kCGEventTapDisabledByTimeout: CG_Event_Type : 0xFFFFFFFE
kCGEventTapDisabledByUserInput: CG_Event_Type : 0xFFFFFFFF
kCGKeyboardEventKeycode: CG_Event_Field : 9

kCGEventFlagMaskCommand: CG_Event_Flags : 0x00100000
kCGEventFlagMaskShift: CG_Event_Flags : 0x00020000
kCGEventFlagMaskControl: CG_Event_Flags : 0x00040000
kCGEventFlagMaskAlternate: CG_Event_Flags : 0x00080000

kVK_ANSI_1: CG_Key_Code : 0x12
kVK_ANSI_2: CG_Key_Code : 0x13
kVK_ANSI_3: CG_Key_Code : 0x14

cg_event_mask_bit :: #force_inline proc(t: CG_Event_Type) -> CG_Event_Mask {
	return CG_Event_Mask(1) << t
}

foreign import cg "system:CoreGraphics.framework"
@(link_prefix = "")
foreign cg {
	CGEventTapCreate :: proc "c" (tap: CG_Event_Tap_Location, place: CG_Event_Tap_Placement, options: CG_Event_Tap_Options, mask: CG_Event_Mask, callback: CG_Event_Tap_Callback, refcon: rawptr) -> CF_Mach_Port_Ref ---
	CGEventTapEnable :: proc "c" (tap: CF_Mach_Port_Ref, enable: bool) ---
	CGEventGetFlags :: proc "c" (event: CG_Event_Ref) -> CG_Event_Flags ---
	CGEventGetIntegerValueField :: proc "c" (event: CG_Event_Ref, field: CG_Event_Field) -> i64 ---
}

foreign import cf "system:CoreFoundation.framework"
@(link_prefix = "")
foreign cf {
	kCFAllocatorDefault: CF_Allocator_Ref
	kCFRunLoopCommonModes: CF_String_Ref
	CFRunLoopGetCurrent :: proc "c" () -> CF_Run_Loop_Ref ---
	CFRunLoopAddSource :: proc "c" (rl: CF_Run_Loop_Ref, src: CF_Run_Loop_Source_Ref, mode: CF_String_Ref) ---
	CFRunLoopRun :: proc "c" () ---
	CFMachPortCreateRunLoopSource :: proc "c" (alloc: CF_Allocator_Ref, port: CF_Mach_Port_Ref, order: i64) -> CF_Run_Loop_Source_Ref ---
}

foreign import platform "platform/macos.o"
@(link_prefix = "")
foreign platform {
	platform_check_accessibility :: proc "c" () -> i32 ---
	platform_find_app :: proc "c" (bundle_id: cstring) -> i32 ---
	platform_launch_app :: proc "c" (bundle_id: cstring) -> i32 ---
	platform_activate_app :: proc "c" (pid: i32) ---
	platform_screen_rect :: proc "c" () -> CG_Rect ---
	platform_fill_window :: proc "c" (pid: i32, rect: CG_Rect) ---
}
