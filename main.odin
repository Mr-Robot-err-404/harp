package harp

import "core:fmt"
import "core:os"
import "core:os/os2"
import "core:strings"
import "core:time"

Binding :: struct {
	key:       CG_Key_Code,
	bundle_id: cstring,
}
DefaultBindings :: "com.mitchellh.ghostty\ncom.google.Chrome\ncom.spotify.client\ncom.hnc.discord\n"

MAX_BINDINGS :: 36
keys := [MAX_BINDINGS]CG_Key_Code {
	kVK_ANSI_H,
	kVK_ANSI_B,
	kVK_ANSI_J,
	kVK_ANSI_K,
	kVK_ANSI_S,
	kVK_ANSI_Q,
	kVK_ANSI_A,
	kVK_ANSI_C,
	kVK_ANSI_D,
	kVK_ANSI_E,
	kVK_ANSI_F,
	kVK_ANSI_G,
	kVK_ANSI_I,
	kVK_ANSI_L,
	kVK_ANSI_M,
	kVK_ANSI_N,
	kVK_ANSI_O,
	kVK_ANSI_P,
	kVK_ANSI_R,
	kVK_ANSI_T,
	kVK_ANSI_U,
	kVK_ANSI_V,
	kVK_ANSI_W,
	kVK_ANSI_X,
	kVK_ANSI_Y,
	kVK_ANSI_Z,
	kVK_ANSI_0,
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

	// Prompt once, then poll silently until granted.
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
	disable_stage_manager()

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
