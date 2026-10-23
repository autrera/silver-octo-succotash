package main

capture_scenario :: proc(step: int) -> (done: bool) {
	switch step {
	case 0:
		capture_shot("start_menu", .FULL)
	case 1:
		capture_enter_game()
		selected_planet = EARTH
		minerals = 6000
		base_counts[EARTH] = MAX_BASES
		capture_shot("earth_panel", .PANEL, {height = 520})
		capture_shot("dock", .RECT, capture_dock_rect())
	case 2:
		capture_hover(miner_button_rect(capture_panel_x()))
		capture_shot("earth_hover_miner", .PANEL, {height = 520})
	case 3:
		capture_park_mouse()
		capture_liberate(MARS)
		selected_planet = MARS
		capture_shot("mars_panel", .PANEL, {height = 520})
	case 4:
		toggle_pause()
		capture_shot("pause_menu", .FULL)
	case:
		return true
	}
	return false
}
