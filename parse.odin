package harp

import "core:fmt"
import "core:os"
import "core:strings"

read_bindings :: proc(s: ^State) {
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
	for b in s.bindings {
		delete(string(b.bundle_id))
	}
	clear(&s.bindings)

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
		append(&s.bindings, Binding{key = keys[i], bundle_id = strings.clone_to_cstring(trimmed)})
		i += 1
	}
	if skipped > 0 {
		fmt.printf("[harp] warning: %d binding(s) ignored (max %d)\n", skipped, MAX_BINDINGS)
	}
}
