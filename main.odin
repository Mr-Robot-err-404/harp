package harp

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

Binding :: struct {
	key:       CG_Key_Code,
	bundle_id: cstring,
}
DefaultBindings :: "com.mitchellh.ghostty\ncom.google.Chrome\ncom.spotify.client\n"

keys := [?]CG_Key_Code{kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3}
bindings: [dynamic]Binding
g_tap: CF_Mach_Port_Ref

main :: proc() {
	bindings = make([dynamic]Binding)
	read_bindings()

	if len(bindings) == 0 {
		fmt.println("[harp] no bindings loaded, using defaults")
		append(&bindings, Binding{key = kVK_ANSI_1, bundle_id = "com.mitchellh.ghostty"})
		append(&bindings, Binding{key = kVK_ANSI_2, bundle_id = "com.google.Chrome"})
		append(&bindings, Binding{key = kVK_ANSI_3, bundle_id = "com.spotify.client"})
	}

	if platform_check_accessibility() == 0 {
		fmt.println("[harp] Accessibility permission required.")
		fmt.println("       System Settings → Privacy & Security → Accessibility")
		fmt.println("       Then relaunch.")
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
	if home == "" {
		fmt.println("[harp] HOME not set")
		return
	}
	dir := strings.join({home, "/.config/harp"}, "")
	path := strings.join({dir, "/bindings"}, "")

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

	clear(&bindings)
	str := string(data)
	i := 0

	for line in strings.split_lines_iterator(&str) {
		defer i += 1
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || i >= len(keys) {continue}
		append(&bindings, Binding{key = keys[i], bundle_id = strings.clone_to_cstring(trimmed)})
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
		time.sleep(500 * time.Millisecond)
	}

	platform_activate_app(pid)
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
			switch_to(b.bundle_id)
			return nil
		}
	}
	return event
}
