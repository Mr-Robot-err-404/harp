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

MAX_BINDINGS :: 36
MAX_APPS :: 1024
EMPTY_BINDING :: "<empty>"

Item_State :: enum i32 {
	None     = 0,
	Moving   = 1,
	Deleting = 2,
}
Open :: enum {
	None,
	Overlay,
	Search,
}
Overlay :: struct {
	active: i32,
	keys:   [MAX_BINDINGS]cstring,
	names:  [MAX_BINDINGS]cstring,
	states: [MAX_BINDINGS]i32,
	prev:   CG_Key_Code,
}
App :: struct {
	name:      cstring,
	bundle_id: cstring,
}
Search :: struct {
	query:   strings.Builder,
	results: [dynamic]App,
	active:  i32,
}
State :: struct {
	bindings: [dynamic]Binding,
	overlay:  Overlay,
	search:   Search,
	modal:    Open,
}
app_names: [MAX_APPS]cstring
app_bundle_ids: [MAX_APPS]cstring
app_count := platform_get_all_apps(&app_names[0], &app_bundle_ids[0], MAX_APPS)

g_tap: CF_Mach_Port_Ref

main :: proc() {
	state := State {
		bindings = make([dynamic]Binding),
		search = Search{results = make([dynamic]App), query = strings.Builder{}},
	}
	fill_search_results(&state.search.results)
	defer {
		for b in state.bindings do delete(string(b.bundle_id))
		delete(state.bindings)
		delete(state.search.results)
		strings.builder_destroy(&state.search.query)
	}
	if !is_setup() {setup()}

	read_bindings(&state)
	build_overlay_data(&state)

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
		&state,
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
	s := (^State)(refcon)

	if kind == kCGEventTapDisabledByTimeout || kind == kCGEventTapDisabledByUserInput {
		if g_tap != nil do CGEventTapEnable(g_tap, true)
		return event
	}
	keycode := CG_Key_Code(CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode))
	defer s.overlay.prev = keycode

	switch s.modal {
	case .Overlay:
		if keycode != kVK_ANSI_X {clear_deleting_items(s)}

		n := i32(len(s.bindings))
		switch keycode {
		case kVK_Return:
			s.modal = .None
			platform_hide_overlay()
			switch_to(s.bindings[s.overlay.active].bundle_id)

		case kVK_ANSI_X:
			defer refresh_overlay(s)

			if Item_State(s.overlay.states[s.overlay.active]) != .Deleting {
				clear_overlay_state(s)
				set_item_state(s, .Deleting, s.overlay.active)
				break
			}
			switch s.overlay.prev {
			case kVK_ANSI_X:
				remove_item(s, s.overlay.active)
				clear_overlay_state(s)
				write_bindings(s)
			case:
				set_item_state(s, .Deleting, s.overlay.active)
			}

		case kVK_Space:
			overlay_state := derive_overlay_state(s)

			switch Item_State(s.overlay.states[s.overlay.active]) {
			case .None:
				set_item_state(s, .Moving, s.overlay.active)
				if overlay_state != .Moving {break}

				idx, ok := find_target_idx(s, s.overlay.active, .Moving)
				if !ok {panic("WTF")}
				swap_bindings(s, s.overlay.active, idx)
				clear_overlay_state(s)
				sync_overlay(s)
				write_bindings(s)

			case .Moving:
				set_item_state(s, .None, s.overlay.active)
			case .Deleting:
				set_item_state(s, .Moving, s.overlay.active)
			}
			refresh_overlay(s)

		case kVK_Escape:
			if s.overlay.prev == kVK_ANSI_X && derive_overlay_state(s) != Item_State.None {
				refresh_overlay(s)
				break
			}
			s.modal = .None
			platform_hide_overlay()
		case kVK_ANSI_J:
			s.overlay.active = (s.overlay.active + 1) % n
			refresh_overlay(s)
		case kVK_ANSI_K:
			s.overlay.active = (s.overlay.active - 1 + n) % n
			refresh_overlay(s)
		}
		return nil
	case .Search:
		flags := CGEventGetFlags(event)
		switch keycode {
		case kVK_DownArrow, kVK_ANSI_N:
			if flags & kCGEventFlagMaskControl != 0 || keycode == kVK_DownArrow {
				s.search.active = (s.search.active + 1) % i32(len(s.search.results))
				refresh_search(s)
				return nil
			}
		case kVK_UpArrow, kVK_ANSI_P:
			if flags & kCGEventFlagMaskControl != 0 || keycode == kVK_UpArrow {
				n := i32(len(s.search.results))
				s.search.active = (s.search.active - 1 + n) % n
				refresh_search(s)
				return nil
			}
		case kVK_Return:
			s.modal = .None
			platform_hide_search()
			switch_to(s.search.results[s.search.active].bundle_id)
			clear_search_state(s)
			return nil
		}
		s.search.active = 0

		switch keycode {
		case kVK_Escape:
			s.modal = .None
			platform_hide_search()
			return nil

		case kVK_Delete:
			if len(strings.to_string(s.search.query)) == 0 {break}
			strings.pop_rune(&s.search.query)

			if len(strings.to_string(s.search.query)) == 0 {
				fill_search_results(&s.search.results)
			} else {
				search_query(s, strings.to_string(s.search.query))
			}
			refresh_search(s)
		case:
			buf: [4]u16
			len: CF_Index
			CGEventKeyboardGetUnicodeString(event, 4, &len, &buf[0])
			if len == 1 && buf[0] >= 32 && buf[0] < 127 {
				strings.write_rune(&s.search.query, rune(buf[0]))
			}
			search_query(s, strings.to_string(s.search.query))
			refresh_search(s)
		}
		return nil
	case .None:
		flags := CGEventGetFlags(event)
		if !is_leader_key(flags) {return event}

		switch keycode {
		case kVK_ANSI_Comma:
			s.modal = .Search
			refresh_search(s)
			return nil
		case kVK_ANSI_Y:
			defer write_bindings(s)

			app := platform_frontmost_app()
			for b in s.bindings {
				if b.bundle_id == app {return nil}
			}
			for i in 0 ..< len(s.bindings) {
				if s.bindings[i].bundle_id == EMPTY_BINDING {
					s.bindings[i].bundle_id = strings.clone_to_cstring(string(app))
					return nil
				}
			}
			if len(s.bindings) >= MAX_BINDINGS {return nil}
			idx := len(s.bindings)
			append(
				&s.bindings,
				Binding{key = keys[idx], bundle_id = strings.clone_to_cstring(string(app))},
			)
			switch_to(s.bindings[idx].bundle_id)
			return nil

		case kVK_ANSI_Semicolon:
			s.overlay.active = active_binding_idx(s)
			s.modal = .Overlay
			refresh_overlay(s)
			return nil
		}
		for b in s.bindings {
			if b.bundle_id == EMPTY_BINDING {continue}
			if keycode == b.key {
				switch_to(b.bundle_id)
				return nil
			}
		}
	}
	return event
}

fill_search_results :: proc(results: ^[dynamic]App) {
	for i in 0 ..< app_count {
		append(results, App{name = app_names[i], bundle_id = app_bundle_ids[i]})
	}
}

remove_item :: proc(s: ^State, idx: i32) {
	if idx < 4 {
		s.bindings[idx].bundle_id = EMPTY_BINDING
		return
	}
	ordered_remove(&s.bindings, idx)
	rekey_bindings(s)
}

is_leader_key :: proc(flags: CG_Event_Flags) -> bool {
	return(
		(flags & kCGEventFlagMaskCommand) != 0 &&
		(flags & kCGEventFlagMaskShift) == 0 &&
		(flags & kCGEventFlagMaskControl) == 0 &&
		(flags & kCGEventFlagMaskAlternate) == 0 \
	)
}

swap_bindings :: proc(s: ^State, a, b: i32) {
	tmp := s.bindings[a].bundle_id
	s.bindings[a].bundle_id = s.bindings[b].bundle_id
	s.bindings[b].bundle_id = tmp
}

find_target_idx :: proc(s: ^State, current: i32, state: Item_State) -> (i32, bool) {
	for i: i32; i < i32(len(s.bindings)); i += 1 {
		if i == current {continue}
		if state == Item_State(s.overlay.states[i]) {return i, true}
	}
	return -1, false
}

set_item_state :: proc(s: ^State, state: Item_State, idx: i32) {
	s.overlay.states[idx] = i32(state)
}
clear_overlay_state :: proc(s: ^State) {
	for i in 0 ..< len(s.overlay.states) {
		set_item_state(s, .None, i32(i))
	}
}
clear_search_state :: proc(s: ^State) {
	clear(&s.search.results)
	fill_search_results(&s.search.results)
	strings.builder_reset(&s.search.query)
}
clear_deleting_items :: proc(s: ^State) {
	for i in 0 ..< len(s.overlay.states) {
		if Item_State(s.overlay.states[i]) != .Deleting {continue}
		set_item_state(s, .None, i32(i))
	}
}

derive_overlay_state :: proc(s: ^State) -> Item_State {
	for n in s.overlay.states {
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

rekey_bindings :: proc(s: ^State) {
	for i in 0 ..< len(s.bindings) {
		s.bindings[i].key = keys[i]
	}
}

sync_overlay :: proc(s: ^State) {
	for i in 0 ..< len(s.bindings) {
		s.overlay.keys[i] = LABELS[i]
		s.overlay.names[i] =
			s.bindings[i].bundle_id == EMPTY_BINDING ? "no binding" : platform_app_name(s.bindings[i].bundle_id)
	}
}

all_empty :: proc(s: ^State) -> bool {
	for b in s.bindings {
		if b.bundle_id != EMPTY_BINDING {return false}
	}
	return true
}

refresh_search :: proc(s: ^State) {
	names := make([]cstring, len(s.search.results), context.temp_allocator)
	for r, i in s.search.results {
		names[i] = r.name
	}
	platform_show_search(
		strings.to_cstring(&s.search.query),
		raw_data(names),
		i32(len(s.search.results)),
		s.search.active,
	)
}

refresh_overlay :: proc(s: ^State) {
	sync_overlay(s)
	count := all_empty(s) ? 0 : i32(len(s.bindings))
	platform_show_overlay(
		&s.overlay.keys[0],
		&s.overlay.names[0],
		&s.overlay.states[0],
		count,
		s.overlay.active,
	)
}

build_overlay_data :: proc(s: ^State) {
	for i in 0 ..< len(s.bindings) {
		s.overlay.keys[i] = LABELS[i]
		s.overlay.names[i] = platform_app_name(s.bindings[i].bundle_id)
		s.overlay.states[i] = i32(Item_State.None)
	}
}

active_binding_idx :: proc(s: ^State) -> i32 {
	id := platform_frontmost_app()
	for i in 0 ..< len(s.bindings) {
		if string(s.bindings[i].bundle_id) == string(id) {
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
