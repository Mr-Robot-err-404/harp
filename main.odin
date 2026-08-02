package harp

import "base:runtime"
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

Item_State :: enum i32 {
	None     = 0,
	Moving   = 1,
	Deleting = 2,
}
Overlay :: struct {
	open:   bool,
	active: i32,
	keys:   [MAX_BINDINGS]cstring,
	names:  [MAX_BINDINGS]cstring,
	states: [MAX_BINDINGS]i32,
	prev:   CG_Key_Code,
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
	context = runtime.default_context()

	if kind == kCGEventTapDisabledByTimeout || kind == kCGEventTapDisabledByUserInput {
		if g_tap != nil do CGEventTapEnable(g_tap, true)
		return event
	}
	keycode := CG_Key_Code(CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode))
	defer overlay.prev = keycode

	if keycode != kVK_ANSI_X {clear_deleting_items()}

	if overlay.open {
		n := i32(len(bindings))
		switch keycode {
		case kVK_Return:
			overlay.open = false
			platform_hide_overlay()
			switch_to(bindings[overlay.active].bundle_id)

		case kVK_ANSI_X:
			defer refresh_overlay()

			if Item_State(overlay.states[overlay.active]) != .Deleting {
				clear_overlay_state()
				set_item_state(.Deleting, overlay.active)
				break
			}
			switch overlay.prev {
			case kVK_ANSI_X:
				ordered_remove(&bindings, overlay.active)
				clear_overlay_state()
				rekey_bindings()
			case:
				set_item_state(.Deleting, overlay.active)
			}

		case kVK_Space:
			overlay_state := derive_overlay_state()

			switch Item_State(overlay.states[overlay.active]) {
			case .None:
				set_item_state(.Moving, overlay.active)
				if overlay_state != .Moving {break}

				idx, ok := find_target_idx(overlay.active, .Moving)
				if !ok {panic("WTF")}
				swap_bindings(overlay.active, idx)
				clear_overlay_state()
				sync_overlay()

			case .Moving:
				set_item_state(.None, overlay.active)
			case .Deleting:
				set_item_state(.Moving, overlay.active)
			}
			refresh_overlay()
			log_overlay_state()

		case kVK_Escape:
			if overlay.prev == kVK_ANSI_X && derive_overlay_state() != Item_State.None {
				refresh_overlay()
				break
			}
			overlay.open = false
			platform_hide_overlay()
		case kVK_ANSI_J:
			overlay.active = (overlay.active + 1) % n
			refresh_overlay()
		case kVK_ANSI_K:
			overlay.active = (overlay.active - 1 + n) % n
			refresh_overlay()
		}
		return nil
	}
	flags := CGEventGetFlags(event)
	if !is_leader_key(flags) {return event}

	switch keycode {
	case kVK_ANSI_Slash:
		results := []cstring{"Ghostty", "Ghost Browser"}
		platform_show_search("ghost", raw_data(results[:]), 2, 0)
	case kVK_ANSI_Y:
		app := platform_frontmost_app()
		for b in bindings {
			if b.bundle_id == app {return nil}
		}
		if len(bindings) >= MAX_BINDINGS {return nil}
		idx := len(bindings)
		append(
			&bindings,
			Binding{key = keys[idx], bundle_id = strings.clone_to_cstring(string(app))},
		)
		switch_to(bindings[idx].bundle_id)
		return nil

	case kVK_ANSI_Semicolon:
		idx := active_binding_idx()
		overlay.active = idx
		overlay.open = true
		refresh_overlay()
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

swap_bindings :: proc(a, b: i32) {
	tmp := bindings[a].bundle_id
	bindings[a].bundle_id = bindings[b].bundle_id
	bindings[b].bundle_id = tmp
}

find_target_idx :: proc(current: i32, state: Item_State) -> (i32, bool) {
	for i: i32; i < i32(len(bindings)); i += 1 {
		if i == current {continue}
		if state == Item_State(overlay.states[i]) {return i, true}
	}
	return -1, false
}

set_item_state :: proc(state: Item_State, idx: i32) {
	overlay.states[idx] = i32(state)
}
clear_overlay_state :: proc() {
	for i in 0 ..< len(overlay.states) {
		set_item_state(.None, i32(i))
	}
}
clear_deleting_items :: proc() {
	for i in 0 ..< len(overlay.states) {
		if Item_State(overlay.states[i]) != .Deleting {continue}
		set_item_state(.None, i32(i))
	}
}

derive_overlay_state :: proc() -> Item_State {
	for n in overlay.states {
		state := Item_State(n)
		switch state {
		case .None:
			continue
		case .Moving, .Deleting:
			return state
		}
	}
	return .None
}

rekey_bindings :: proc() {
	for i in 0 ..< len(bindings) {
		bindings[i].key = keys[i]
	}
}

sync_overlay :: proc() {
	for i in 0 ..< len(bindings) {
		overlay.keys[i] = LABELS[i]
		overlay.names[i] = platform_app_name(bindings[i].bundle_id)
	}
}

refresh_overlay :: proc() {
	sync_overlay()
	platform_show_overlay(
		&overlay.keys[0],
		&overlay.names[0],
		&overlay.states[0],
		i32(len(bindings)),
		overlay.active,
	)
}

build_overlay_data :: proc() {
	for i in 0 ..< len(bindings) {
		overlay.keys[i] = LABELS[i]
		overlay.names[i] = platform_app_name(bindings[i].bundle_id)
		overlay.states[i] = i32(Item_State.None)
	}
}

active_binding_idx :: proc() -> i32 {
	id := platform_frontmost_app()
	for i in 0 ..< len(bindings) {
		if string(bindings[i].bundle_id) == string(id) {
			return i32(i)
		}
	}
	return 0
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
