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

// Numbers
kVK_ANSI_0: CG_Key_Code : 0x1D
kVK_ANSI_1: CG_Key_Code : 0x12
kVK_ANSI_2: CG_Key_Code : 0x13
kVK_ANSI_3: CG_Key_Code : 0x14
kVK_ANSI_4: CG_Key_Code : 0x15
kVK_ANSI_5: CG_Key_Code : 0x17
kVK_ANSI_6: CG_Key_Code : 0x16
kVK_ANSI_7: CG_Key_Code : 0x1A
kVK_ANSI_8: CG_Key_Code : 0x1C
kVK_ANSI_9: CG_Key_Code : 0x19

// Letters
kVK_ANSI_A: CG_Key_Code : 0x00
kVK_ANSI_B: CG_Key_Code : 0x0B
kVK_ANSI_C: CG_Key_Code : 0x08
kVK_ANSI_D: CG_Key_Code : 0x02
kVK_ANSI_E: CG_Key_Code : 0x0E
kVK_ANSI_F: CG_Key_Code : 0x03
kVK_ANSI_G: CG_Key_Code : 0x05
kVK_ANSI_H: CG_Key_Code : 0x04
kVK_ANSI_I: CG_Key_Code : 0x22
kVK_ANSI_J: CG_Key_Code : 0x26
kVK_ANSI_K: CG_Key_Code : 0x28
kVK_ANSI_L: CG_Key_Code : 0x25
kVK_ANSI_M: CG_Key_Code : 0x2E
kVK_ANSI_N: CG_Key_Code : 0x2D
kVK_ANSI_O: CG_Key_Code : 0x1F
kVK_ANSI_P: CG_Key_Code : 0x23
kVK_ANSI_Q: CG_Key_Code : 0x0C
kVK_ANSI_R: CG_Key_Code : 0x0F
kVK_ANSI_S: CG_Key_Code : 0x01
kVK_ANSI_T: CG_Key_Code : 0x11
kVK_ANSI_U: CG_Key_Code : 0x20
kVK_ANSI_V: CG_Key_Code : 0x09
kVK_ANSI_W: CG_Key_Code : 0x0D
kVK_ANSI_X: CG_Key_Code : 0x07
kVK_ANSI_Y: CG_Key_Code : 0x10
kVK_ANSI_Z: CG_Key_Code : 0x06

// Symbols
kVK_ANSI_Comma:        CG_Key_Code : 0x2B  // ,
kVK_ANSI_Period:       CG_Key_Code : 0x2F  // .
kVK_ANSI_Slash:        CG_Key_Code : 0x2C  // /
kVK_ANSI_Semicolon:    CG_Key_Code : 0x29  // ; :
kVK_ANSI_Quote:        CG_Key_Code : 0x27  // ' "
kVK_ANSI_Minus:        CG_Key_Code : 0x1B  // - _
kVK_ANSI_Equal:        CG_Key_Code : 0x18  // = +

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
	platform_request_accessibility :: proc "c" () -> i32 ---
	platform_find_app :: proc "c" (bundle_id: cstring) -> i32 ---
	platform_launch_app :: proc "c" (bundle_id: cstring) -> i32 ---
	platform_screen_rect :: proc "c" () -> CG_Rect ---
	platform_fill_window :: proc "c" (pid: i32, rect: CG_Rect) ---
	platform_show_overlay :: proc "c" () ---
	platform_hide_overlay :: proc "c" () ---
}
