package harp

import "core:fmt"
import "core:os"
import "core:strings"

Binding :: struct {
	key:       CG_Key_Code,
	bundle_id: cstring,
}
DefaultBindings :: "com.mitchellh.ghostty\ncom.google.Chrome\ncom.spotify.client\n"

MAX_BINDINGS :: 9
keys := [MAX_BINDINGS]CG_Key_Code {
	kVK_ANSI_1,
	kVK_ANSI_2,
	kVK_ANSI_3,
	kVK_ANSI_4,
	kVK_ANSI_5,
	kVK_ANSI_6,
	kVK_ANSI_7,
	kVK_ANSI_8,
	kVK_ANSI_9,
}
bindings: [dynamic]Binding
g_tap: CF_Mach_Port_Ref


main :: proc() {
	if !is_setup() {setup()}

	bindings = make([dynamic]Binding)
	defer {
		for b in bindings do delete(string(b.bundle_id))
		delete(bindings)
	}
	read_bindings()
	if len(bindings) == 0 {use_default_bindings(&bindings)}

	if platform_check_accessibility() == 0 {
		fmt.println("[harp] Accessibility permission required.")
		fmt.println("       System Settings → Privacy & Security → Accessibility")
		fmt.println("       Then relaunch.")
		return
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

read_bindings :: proc() {
	home := os.get_env("HOME")
	defer delete(home)
	if home == "" {
		fmt.println("[harp] HOME not set")
		return
	}
	dir := strings.join({home, "/.config/harp"}, "")
	path := strings.join({dir, "/bindings"}, "")
	defer delete(dir)
	defer delete(path)

	if !os.exists(dir) {
		err := os.make_directory(dir)
		if err != nil {panic("failed to make harp directory")}
	}
	if !os.exists(path) {
		ok := os.write_entire_file(path, transmute([]byte)string(DefaultBindings))
		if !ok {panic("failed to create bindings file")}
		fmt.println("[harp] created default config at", path)
	}
	data, ok := os.read_entire_file(path)
	if !ok {
		fmt.println("[harp] no config found at", path)
		return
	}
	defer delete(data)

	for b in bindings {
		delete(string(b.bundle_id))
	}
	clear(&bindings)

	str := string(data)
	i := 0
	skipped := 0

	for line in strings.split_lines_iterator(&str) {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 {continue}
		if i >= MAX_BINDINGS {
			skipped += 1
			continue
		}
		append(&bindings, Binding{key = keys[i], bundle_id = strings.clone_to_cstring(trimmed)})
		i += 1
	}
	if skipped > 0 {
		fmt.printf("[harp] warning: %d binding(s) ignored (max %d)\n", skipped, MAX_BINDINGS)
	}
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
	flags := CGEventGetFlags(event)
	keycode := CG_Key_Code(CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode))

	cmd_only :=
		(flags & kCGEventFlagMaskCommand) != 0 &&
		(flags & kCGEventFlagMaskShift) == 0 &&
		(flags & kCGEventFlagMaskControl) == 0 &&
		(flags & kCGEventFlagMaskAlternate) == 0

	if !cmd_only do return event

	for b in bindings {
		if keycode == b.key {
			fmt.printf("[harp] key 0x%x matched -> %s\n", keycode, b.bundle_id)
			switch_to(b.bundle_id)
			return nil
		}
	}
	fmt.printf("[harp] cmd+0x%x (no binding)\n", keycode)
	return event
}


use_default_bindings :: proc(bindings: ^[dynamic]Binding) {
	append(
		bindings,
		Binding{key = kVK_ANSI_1, bundle_id = strings.clone_to_cstring("com.mitchellh.ghostty")},
	)
	append(
		bindings,
		Binding{key = kVK_ANSI_2, bundle_id = strings.clone_to_cstring("com.google.Chrome")},
	)
	append(
		bindings,
		Binding{key = kVK_ANSI_3, bundle_id = strings.clone_to_cstring("com.spotify.client")},
	)
}
