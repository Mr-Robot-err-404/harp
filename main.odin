package harp

import "core:fmt"
import "core:os/os2"
import "core:strings"
import "core:time"

Binding :: struct {
	key:       CG_Key_Code,
	bundle_id: cstring,
}
DefaultBindings :: "com.mitchellh.ghostty\ncom.google.Chrome\ncom.spotify.client\ncom.hnc.discord\n"

MAX_BINDINGS :: 36
bindings: [dynamic]Binding
g_tap: CF_Mach_Port_Ref

Overlay :: struct {
	open:   bool,
	active: i32,
	keys:   [MAX_BINDINGS]cstring,
	names:  [MAX_BINDINGS]cstring,
}
overlay: Overlay


main :: proc() {
	if !is_setup() {setup()}

	bindings = make([dynamic]Binding)
	defer {
		for b in bindings do delete(string(b.bundle_id))
		delete(bindings)
	}
	read_bindings()
	if len(bindings) == 0 {use_default_bindings(&bindings)}
	build_overlay_data()

	if platform_request_accessibility() == 0 {
		fmt.println("[harp] waiting for accessibility permission...")
		fmt.println("       System Settings → Privacy & Security → Accessibility")
		for platform_check_accessibility() == 0 {
			time.sleep(2 * time.Second)
		}
	}
	g_tap = CGEventTapCreate(
		kCGSessionEventTap,
		kCGHeadInsertEventTap,
		kCGEventTapOptionDefault,
		cg_event_mask_bit(kCGEventKeyDown),
		on_key,
		nil,
	)
	if g_tap == nil {
		fmt.println("[harp] failed to create event tap.")
		return
	}
	src := CFMachPortCreateRunLoopSource(kCFAllocatorDefault, g_tap, 0)
	CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes)
	CGEventTapEnable(g_tap, true)

	fmt.println("[harp] running.")
	CFRunLoopRun()
}

switch_to :: proc(bundle_id: cstring) {
	pid := platform_find_app(bundle_id)

	if pid == -1 {
		fmt.println("[harp] launching", bundle_id)
		pid = platform_launch_app(bundle_id)
		if pid == -1 {
			fmt.println("[harp] failed to launch", bundle_id)
			return
		}
	}
	platform_fill_window(pid, platform_screen_rect())
}

on_key :: proc "c" (
	proxy: CG_Event_Tap_Proxy,
	kind: CG_Event_Type,
	event: CG_Event_Ref,
	refcon: rawptr,
) -> CG_Event_Ref {
	context = {}

	if kind == kCGEventTapDisabledByTimeout || kind == kCGEventTapDisabledByUserInput {
		if g_tap != nil do CGEventTapEnable(g_tap, true)
		return event
	}
	keycode := CG_Key_Code(CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode))

	if overlay.open {
		n := i32(len(bindings))
		switch keycode {
		case kVK_Return:
			overlay.open = false
			platform_hide_overlay()
			switch_to(bindings[overlay.active].bundle_id)

		case kVK_Escape:
			overlay.open = false
			platform_hide_overlay()
		case kVK_ANSI_J:
			overlay.active = (overlay.active + 1) % n
			platform_set_overlay_active(overlay.active)
		case kVK_ANSI_K:
			overlay.active = (overlay.active - 1 + n) % n
			platform_set_overlay_active(overlay.active)
		}
		return nil
	}
	flags := CGEventGetFlags(event)
	if !is_leader_key(flags) {return event}

	if keycode == kVK_ANSI_Semicolon {
		overlay.open = true
		overlay.active = 0
		platform_show_overlay(&overlay.keys[0], &overlay.names[0], i32(len(bindings)), 0)
		return nil
	}
	for b in bindings {
		if keycode == b.key {
			switch_to(b.bundle_id)
			return nil
		}
	}
	return event
}

is_leader_key :: proc(flags: CG_Event_Flags) -> bool {
	return(
		(flags & kCGEventFlagMaskCommand) != 0 &&
		(flags & kCGEventFlagMaskShift) == 0 &&
		(flags & kCGEventFlagMaskControl) == 0 &&
		(flags & kCGEventFlagMaskAlternate) == 0 \
	)
}

build_overlay_data :: proc() {
	for i in 0 ..< len(bindings) {
		overlay.keys[i] = LABELS[i]
		overlay.names[i] = bindings[i].bundle_id
	}
}

disable_stage_manager :: proc() {
	_, err := os2.process_start(
		{
			command = {
				"defaults",
				"write",
				"com.apple.WindowManager",
				"GloballyEnabled",
				"-bool",
				"false",
			},
		},
	)
	switch err {
	case os2.ERROR_NONE:
	case:
		panic("failed to disable macos stage manager")
	}
}

use_default_bindings :: proc(bindings: ^[dynamic]Binding) {
	append(
		bindings,
		Binding{key = kVK_ANSI_H, bundle_id = strings.clone_to_cstring("com.mitchellh.ghostty")},
	)
	append(
		bindings,
		Binding{key = kVK_ANSI_B, bundle_id = strings.clone_to_cstring("com.google.Chrome")},
	)
	append(
		bindings,
		Binding{key = kVK_ANSI_J, bundle_id = strings.clone_to_cstring("com.spotify.client")},
	)
	append(
		bindings,
		Binding{key = kVK_ANSI_K, bundle_id = strings.clone_to_cstring("com.hnc.discord")},
	)
}
