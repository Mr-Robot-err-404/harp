package harp

import "core:fmt"

log_overlay_state :: proc(s: ^State) {
	fmt.println("[overlay] state:")
	for i in 0 ..< len(s.bindings) {
		state := Item_State(s.overlay.states[i])
		cursor := i32(i) == s.overlay.active
		fmt.printf(
			"  %s %s -> %v%s\n",
			s.overlay.keys[i],
			s.overlay.names[i],
			state,
			cursor ? " <--" : "",
		)
	}
}
