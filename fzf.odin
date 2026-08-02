package harp

import "core:slice"
import "core:strings"

search_query :: proc(s: ^State, query: string) {
	clear(&s.search.results)
	if len(query) == 0 {
		for i in 0 ..< app_count {
			append(&s.search.results, App{name = app_names[i], bundle_id = app_bundle_ids[i]})
		}
		return
	}
	Score_Entry :: struct {
		app:   App,
		score: int,
	}
	scored := make([dynamic]Score_Entry, context.temp_allocator)

	for i in 0 ..< app_count {
		lower := strings.to_lower(string(app_names[i]), context.temp_allocator)
		score := score_match(lower, query)
		if score <= 0 {continue}
		append(
			&scored,
			Score_Entry {
				app = App{name = app_names[i], bundle_id = app_bundle_ids[i]},
				score = score,
			},
		)
	}
	slice.sort_by(scored[:], proc(a, b: Score_Entry) -> bool {
		return a.score > b.score
	})
	for e in scored {
		append(&s.search.results, e.app)
	}
}

score_match :: proc(name, query: string) -> int {
	if len(query) == 0 {return 1}
	if strings.has_prefix(name, query) {return 1000}

	score := 0
	ni := 0
	consecutive := 0

	for qi in 0 ..< len(query) {
		found := false
		for ni < len(name) {
			defer ni += 1
			if name[ni] == query[qi] {
				consecutive += 1
				score += 10 + (consecutive * 5)
				found = true
				break
			}
			consecutive = 0
		}
		if !found {return -1}
	}
	return score
}
