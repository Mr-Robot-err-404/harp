package harp

import "core:fmt"

log_overlay_state :: proc() {
	fmt.println("[overlay] state:")
	for i in 0 ..< len(bindings) {
		state := Item_State(overlay.states[i])
		cursor := i32(i) == overlay.active
		fmt.printf(
			"  %s %s -> %v%s\n",
			overlay.keys[i],
			overlay.names[i],
			state,
			cursor ? " <--" : "",
		)
	}
}
