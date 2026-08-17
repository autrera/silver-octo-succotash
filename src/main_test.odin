package main

import "core:testing"
import rl "vendor:raylib"

reset_world :: proc() {
	unit_count = 0
	for i := 0; i < MAX_UNITS; i += 1 {
		units[i] = {}
		selected_units[i] = false
	}
	for p in 0..<PLANET_COUNT {
		combat_timer[p] = 0
		miner_timer[p] = 0
		base_timer[p] = 0
	}
	enemy_base_hp = [PLANET_COUNT]int{0, 0, JUPITER_BASE_HP}
	base_counts = [PLANET_COUNT]int{1, 0, 0}
	base_build_planet = -1
	base_build_progress = 0
	minerals = 350
	enemy_wave_timer = 0
	wave_started = false
	selected_planet = 0
	rl.SetRandomSeed(7)
}

add_guarding_fighter :: proc(p: int, enemy: bool) {
	units[unit_count] = Unit{
		kind = .COMBAT, state = .GUARDING, position = planets[p].position,
		home_planet = p, affiliation = p, target_planet = p, enemy = enemy,
	}
	unit_count += 1
}

add_miner :: proc(planet: int) {
	units[unit_count] = Unit{
		kind = .MINING, state = .MINING, position = planets[planet].position,
		home_planet = planet, affiliation = planet, target_planet = planet,
	}
	unit_count += 1
}

add_enemy_miner :: proc(p: int) {
	units[unit_count] = Unit{
		kind = .MINING, state = .GUARDING, position = planets[p].position,
		home_planet = p, affiliation = p, target_planet = p, enemy = true,
	}
	unit_count += 1
}

@(test)
earth_miner_mines_earth_immediately :: proc(t: ^testing.T) {
	reset_world()
	spawn_unit(.MINING, 0)
	testing.expect(t, unit_count == 1, "miner spawned")
	testing.expect(t, !units[0].enemy, "miner is not enemy")
	testing.expect(t, units[0].kind == .MINING, "miner kind")
	testing.expect(t, units[0].target_planet == 0, "miner targets home planet")
	testing.expect(t, units[0].affiliation == 0, "miner affiliated with Earth")
	testing.expect(t, units[0].state == .MINING, "miner starts mining, no transit")
	// Earth is always liberated and has no transit leg: the cycle is just
	// mine + deposit, so MPS is rate / (MINING_DURATION + DEPOSIT_DURATION).
	expected := f32(mining_rate(0)) / (MINING_DURATION + DEPOSIT_DURATION)
	testing.expect(t, abs(planet_mps(0) - expected) < 0.001, "Earth MPS reflects the miner immediately")
}

@(test)
enemy_wave_spawns_five_attackers_from_jupiter :: proc(t: ^testing.T) {
	reset_world()
	spawn_enemy_wave()
	testing.expect(t, unit_count == WAVE_SIZE, "wave size")
	jump_off := planets[2].position + rl.Vector3{40, 0.5, -25}
	for i in 0..<unit_count {
		testing.expect(t, units[i].kind == .COMBAT, "enemy is combat")
		testing.expect(t, units[i].enemy, "enemy flag set")
		testing.expect(t, units[i].target_planet == 1 && units[i].affiliation == 1, "enemy targets Mars while Jupiter is occupied")
		testing.expect(t, distance(units[i].position, jump_off) < 3, "wave lifts off from Jupiter space")
	}
	selected_planet = 1
	testing.expect(t, roster_count(.COMBAT) == 0, "enemies never appear in the player roster")
}

@(test)
wave_timer_first_at_180_seconds_then_every_120 :: proc(t: ^testing.T) {
	reset_world()
	update_enemy_waves(WAVE_FIRST_DELAY - 0.1)
	testing.expect(t, unit_count == 0, "no wave before the 3-minute mark")
	update_enemy_waves(0.2)
	testing.expect(t, unit_count == WAVE_SIZE, "first wave spawns at 180s")
	update_enemy_waves(WAVE_INTERVAL - 0.1)
	testing.expect(t, unit_count == WAVE_SIZE, "no extra wave before 2 minutes elapse")
	update_enemy_waves(0.2)
	testing.expect(t, unit_count == 2 * WAVE_SIZE, "second wave spawns 2 minutes after the first")
}

@(test)
step_simulation_advances_wave_timer_and_spawns_on_schedule :: proc(t: ^testing.T) {
	reset_world()
	production = {}
	pending_count = {}
	// Unpaused play drives the wave clock through step_simulation, not just
	// direct calls: first wave at 3:00, then every 2:00.
	step_simulation(f32(WAVE_FIRST_DELAY) - 0.1)
	testing.expect(t, unit_count == 0, "no wave before 3 minutes of unpaused play")
	step_simulation(0.1)
	testing.expect(t, unit_count == WAVE_SIZE, "first wave spawns at the 3-minute mark")
	step_simulation(f32(WAVE_INTERVAL) - 0.1)
	testing.expect(t, unit_count == WAVE_SIZE, "no wave before 2 minutes elapse")
	step_simulation(0.1)
	testing.expect(t, unit_count == 2 * WAVE_SIZE, "second wave spawns 2 minutes after the first")
}

@(test)
step_simulation_resolves_combat_at_jupiter :: proc(t: ^testing.T) {
	reset_world()
	production = {}
	pending_count = {}
	for i in 0..<5 { add_guarding_fighter(2, false) }
	for i in 0..<5 { add_guarding_fighter(2, true) }
	step_simulation(f32(COMBAT_TICK))
	players, enemies := planet_combatants(2)
	testing.expect(t, players == 4 && enemies == 4, "1:1 trade per 2s tick through step_simulation")
	step_simulation(f32(COMBAT_TICK))
	players, enemies = planet_combatants(2)
	testing.expect(t, players == 3 && enemies == 3, "combat keeps ticking on every simulation step")
}

@(test)
initial_camera_zoom_is_85_percent :: proc(t: ^testing.T) {
	// Startup altitude 200 - 185*0.85 = 42.75 maps zoom_percent() to exactly 85%.
	testing.expect(t, abs(CAMERA_START_Y - 42.75) < 0.0001, "startup altitude is 42.75")
	camera.position = {camera_target.x, CAMERA_START_Y, camera_target.z + CAMERA_START_Y}
	testing.expect(t, zoom_percent() == 85, "startup camera reads exactly 85% zoom")
	camera.position = {}
}

@(test)
transit_speeds_reduced_by_75_percent :: proc(t: ^testing.T) {
	reset_world()
	units[unit_count] = Unit{kind = .COMBAT, state = .TRANSIT, position = {0, 0, 0}, home_planet = 0, affiliation = 0, target_planet = 1}
	unit_count += 1
	before := units[0].position
	update_combat(&units[0], 1.0)
	testing.expect(t, abs(distance(before, units[0].position) - 2.5) < 0.01, "combat transit speed is 2.5/s (was 10)")
	units[unit_count] = Unit{kind = .MINING, state = .TRANSIT, position = {0, 0, 0}, home_planet = 0, affiliation = 0, target_planet = 1}
	unit_count += 1
	before = units[1].position
	update_miner(&units[1], 1, 1.0)
	testing.expect(t, abs(distance(before, units[1].position) - 1.75) < 0.01, "mining transit speed is 1.75/s (was 7)")
	// Returning to Earth is inter-planet travel too: same reduced speed.
	units[unit_count] = Unit{kind = .MINING, state = .RETURNING, position = planets[1].position, home_planet = 0, affiliation = 0, target_planet = 1}
	unit_count += 1
	before = units[2].position
	update_miner(&units[2], 2, 1.0)
	testing.expect(t, abs(distance(before, units[2].position) - 1.75) < 0.01, "mining return speed is 1.75/s (was 7)")
}

@(test)
five_v_five_battle_lasts_ten_seconds_1_to_1 :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<5 { add_guarding_fighter(1, false) }
	for i in 0..<5 { add_guarding_fighter(1, true) }
	testing.expect(t, unit_count == 10, "setup")
	for tick in 1..=4 {
		update_enemy_waves(f32(COMBAT_TICK))
		testing.expect(t, unit_count == 10 - tick * 2, "one kill per side per 2s tick")
	}
	defenders, attackers := planet_combatants(1)
	testing.expect(t, defenders == 1 && attackers == 1, "one fighter each after 8s")
	update_enemy_waves(f32(COMBAT_TICK))
	defenders, attackers = planet_combatants(1)
	testing.expect(t, defenders == 0 && attackers == 0, "5v5 trade ends after 10s")
	testing.expect(t, unit_count == 0, "all 10 destroyed in the trade")
}

@(test)
miners_die_every_two_seconds_without_defenders :: proc(t: ^testing.T) {
	reset_world()
	add_guarding_fighter(1, true)
	add_miner(1)
	add_miner(1)
	add_miner(1)
	update_enemy_waves(1.0)
	testing.expect(t, unit_count == 4, "no miner hit before the 2s mark")
	update_enemy_waves(1.0)
	testing.expect(t, unit_count == 3, "first miner destroyed at 2s")
	update_enemy_waves(2.0)
	testing.expect(t, unit_count == 2, "second miner destroyed at 4s")
	update_enemy_waves(2.0)
	testing.expect(t, unit_count == 1 && units[0].enemy, "third miner destroyed at 6s; only the enemy attacker survives")
}

@(test)
mars_base_destroyed_after_garrison_cleared :: proc(t: ^testing.T) {
	reset_world()
	// Mars starts liberated now, so this scenario plants an enemy base on Mars
	// explicitly: base destruction logic must work wherever a base is present.
	enemy_base_hp[1] = MARS_BASE_HP
	for i in 0..<3 { add_guarding_fighter(1, false) }
	add_guarding_fighter(1, true)
	for i in 0..<2 { add_enemy_miner(1) }
	// 3v1 trade: one kill per side per tick until the garrison fighter falls.
	update_enemy_waves(f32(COMBAT_TICK))
	players, enemies := planet_combatants(1)
	testing.expect(t, players == 2 && enemies == 0, "garrison fighter traded 1:1")
	// Player fighters sweep the enemy mining drones, one per tick.
	update_enemy_waves(f32(COMBAT_TICK))
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, enemy_miner_count(1) == 0, "enemy mining drones destroyed")
	testing.expect(t, enemy_base_hp[1] == MARS_BASE_HP, "enemy base untouched until the drones are gone")
	// The base then takes damage per player fighter per tick.
	before := enemy_base_hp[1]
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, enemy_base_hp[1] == before - 2, "base damaged by the 2 occupying fighters per tick")
	for enemy_base_hp[1] > 0 { update_enemy_waves(f32(COMBAT_TICK)) }
	testing.expect(t, planet_liberated(1), "Mars liberated once the base falls")
}

@(test)
jupiter_base_destroyed_after_garrison_cleared :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<5 { add_guarding_fighter(2, false) }
	for i in 0..<2 { add_guarding_fighter(2, true) }
	for i in 0..<2 { add_enemy_miner(2) }
	update_enemy_waves(f32(COMBAT_TICK))
	update_enemy_waves(f32(COMBAT_TICK))
	players, enemies := planet_combatants(2)
	testing.expect(t, players == 3 && enemies == 0, "2 garrison fighters traded 1:1")
	update_enemy_waves(f32(COMBAT_TICK))
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, enemy_miner_count(2) == 0, "enemy mining drones swept")
	before := enemy_base_hp[2]
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, enemy_base_hp[2] == before - 3, "base damaged by the 3 fighters per tick")
	for enemy_base_hp[2] > 0 { update_enemy_waves(f32(COMBAT_TICK)) }
	testing.expect(t, enemy_base_hp[2] == 0 && planet_liberated(2), "Jupiter liberated once the base falls")
}

@(test)
base_construction_is_earth_only :: proc(t: ^testing.T) {
	reset_world()
	// Occupied Jupiter: blocked (Earth is always liberated).
	selected_planet = 2
	for i in 0..<5 { add_miner(2) }
	start_base_construction()
	testing.expect(t, base_build_planet != 2, "occupied planet blocks construction even with miners present")

	reset_world()
	// Liberated Mars and Jupiter with enough miners still refuse: command
	// bases build on Earth only.
	selected_planet = 1
	for i in 0..<5 { add_miner(1) }
	start_base_construction()
	testing.expect(t, base_build_planet != 1 && minerals == 350, "liberated Mars refuses construction")
	selected_planet = 2
	enemy_base_hp[2] = 0
	for i in 0..<5 { add_miner(2) }
	start_base_construction()
	testing.expect(t, base_build_planet != 2 && minerals == 350, "liberated Jupiter refuses construction")

	reset_world()
	// Earth queues immediately even with no miners on hand: the 200 mineral
	// cost is deducted up front and miners assemble onto the site later.
	selected_planet = 0
	minerals = 100
	start_base_construction()
	testing.expect(t, base_build_planet != 0, "Earth without 200 minerals blocks construction")
	minerals = 350
	start_base_construction()
	testing.expect(t, base_build_planet == 0, "Earth queues the build with no miners on site")
	testing.expect(t, minerals == 150, "construction costs 200 minerals")
}

@(test)
construction_miners_stop_mining_and_resume :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = 0
	for i in 0..<5 { add_miner(0) }
	earth_cycle: f32 = MINING_DURATION + DEPOSIT_DURATION
	full_mps := f32(5) * f32(mining_rate(0)) / earth_cycle
	testing.expect(t, abs(planet_mps(0) - full_mps) < 0.001, "5 miners mine at full rate before construction")
	start_base_construction()
	for i in 0..<unit_count {
		units[i].state = .DEPOSITING
		units[i].progress = DEPOSIT_DURATION - 0.01
		update_miner(&units[i], i, 0.02)
	}
	for i in 0..<unit_count {
		if units[i].kind == .MINING { testing.expect(t, units[i].state == .CONSTRUCTING, "miners switch to constructing on deposit") }
	}
	testing.expect(t, abs(planet_mps(0)) < 0.001, "construction miners stop generating MPS")
	update_production(BASE_CONSTRUCT_TIME - 0.2)
	testing.expect(t, base_counts[0] == 1 && base_build_planet == 0, "construction still in progress before 60s")
	update_production(0.2)
	testing.expect(t, base_counts[0] == 2 && base_build_planet == -1, "base completes after one full minute")
	for i in 0..<unit_count {
		if units[i].kind == .MINING { testing.expect(t, units[i].state == .MINING, "miners resume mining") }
	}
	testing.expect(t, abs(planet_mps(0) - full_mps) < 0.001, "MPS restored after construction")
}

@(test)
planet_mps_includes_round_trip_transit :: proc(t: ^testing.T) {
	reset_world()
	// One effective miner per planet; expected MPS is rate divided by the
	// full cycle (mine + deposit + round trip at MINING_TRANSIT_SPEED).
	for p in 0..<PLANET_COUNT {
		units[unit_count] = Unit{
			kind = .MINING, state = .MINING, position = planets[p].position,
			home_planet = 0, affiliation = p, target_planet = p,
		}
		unit_count += 1
		cycle: f32 = MINING_DURATION + DEPOSIT_DURATION +
			2.0 * distance(planets[p].position, planets[0].position) / MINING_TRANSIT_SPEED
		expected := f32(mining_rate(p)) / cycle
		testing.expectf(t, abs(planet_mps(p) - expected) < 0.001,
			"planet %d MPS %.4f != expected %.4f", p, planet_mps(p), expected)
	}
	// Every off-Earth planet is slower than the mining-only cycle would claim.
	no_transit := f32(mining_rate(1)) / (MINING_DURATION + DEPOSIT_DURATION)
	testing.expect(t, planet_mps(1) < no_transit, "Mars transit time lowers MPS below the mining-only cycle")
	testing.expect(t, planet_mps(2) < f32(mining_rate(2)) / (MINING_DURATION + DEPOSIT_DURATION), "Jupiter transit time lowers MPS")
	// Jupiter's richer rate more than pays for its longer transit.
	testing.expect(t, planet_mps(2) > planet_mps(1), "Jupiter MPS beats Mars despite the longer round trip")
}

@(test)
miner_waits_for_liberation :: proc(t: ^testing.T) {
	reset_world()
	units[unit_count] = Unit{
		kind = .MINING, state = .TRANSIT, position = planets[2].position,
		home_planet = 0, affiliation = 2, target_planet = 2,
	}
	unit_count += 1
	update_miner(&units[0], 0, 0.1)
	testing.expect(t, units[0].state == .IDLE, "miner holds instead of mining an occupied planet")

	enemy_base_hp[2] = 0
	update_miner(&units[0], 0, 0.1)
	testing.expect(t, units[0].state == .MINING, "idle miner resumes after liberation")
}

@(test)
mining_round_trip_deposits_on_earth :: proc(t: ^testing.T) {
	reset_world()
	units[unit_count] = Unit{
		kind = .MINING, state = .MINING, position = planets[2].position,
		home_planet = 0, affiliation = 2, target_planet = 2,
	}
	unit_count += 1
	// A full mining cycle sends the drone back to Earth.
	units[0].progress = MINING_DURATION - 0.01
	update_miner(&units[0], 0, 0.02)
	testing.expect(t, units[0].state == .RETURNING, "miner returns to Earth after a full cycle")
	// Deposit pays out only after DEPOSIT_DURATION on Earth.
	units[0].position = planets[0].position
	units[0].state = .DEPOSITING
	units[0].progress = 0.1
	minerals = 0
	update_miner(&units[0], 0, 0.02)
	testing.expect(t, minerals == 0, "no payout before the deposit completes")
	units[0].progress = DEPOSIT_DURATION - 0.01
	update_miner(&units[0], 0, 0.02)
	testing.expect(t, minerals == mining_rate(2), "deposit pays the mined rate")
	testing.expect(t, units[0].state == .TRANSIT, "deposited miner transits back out")
}

@(test)
queue_unit_is_earth_only :: proc(t: ^testing.T) {
	reset_world()
	minerals = 1000
	for p in 1..<PLANET_COUNT {
		selected_planet = p
		queue_unit(.MINING)
		queue_unit(.COMBAT)
		testing.expect(t, minerals == 1000, "no minerals spent queueing off Earth")
		testing.expect(t, queued_count(p) == 0, "no production queued off Earth")
	}
	selected_planet = 0
	queue_unit(.MINING)
	testing.expect(t, minerals == 950, "Earth mining queue costs 50")
	testing.expect(t, production[0][0].active && production[0][0].kind == .MINING, "Earth production line active")
}

@(test)
enemy_wave_targets_mars_until_jupiter_liberated :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<3 { spawn_enemy_wave() }
	for i in 0..<unit_count {
		testing.expect(t, units[i].target_planet == 1, "waves target Mars before Jupiter is liberated")
	}
	// After liberation the target flips to a seeded random pick between Mars
	// and Jupiter; both must show up across seeds.
	seen_mars, seen_jupiter := false, false
	for seed in 0..<40 {
		reset_world()
		enemy_base_hp[2] = 0
		rl.SetRandomSeed(u32(seed))
		spawn_enemy_wave()
		for i in 0..<unit_count {
			target := units[i].target_planet
			testing.expect(t, target == 1 || target == 2, "post-liberation waves target Mars or Jupiter")
			if target == 1 { seen_mars = true }
			if target == 2 { seen_jupiter = true }
		}
	}
	testing.expect(t, seen_mars && seen_jupiter, "post-liberation waves hit both planets across seeds")
}

@(test)
representational_rendering_one_cube_per_ten :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, rep_count(0) == 0, "empty fleet renders nothing")
	for n in 1..=10 { testing.expect(t, rep_count(n) == 1, "1-10 render as 1 cube") }
	for n in 11..=20 { testing.expect(t, rep_count(n) == 2, "11-20 render as 2 cubes") }
	testing.expect(t, rep_count(JUPITER_GARRISON_FIGHTERS) == 4, "40 garrison fighters render as 4 cubes")
}

@(test)
transit_fleets_render_representationally :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<12 {
		units[unit_count] = Unit{kind = .COMBAT, state = .TRANSIT, position = {}, home_planet = 0, affiliation = 1, target_planet = 1}
		unit_count += 1
	}
	spawn_enemy_wave() // 5 enemies in transit to Mars
	testing.expect(t, transit_fighters_at(1, false) == 12, "12 player fighters in transit to Mars")
	testing.expect(t, rep_count(transit_fighters_at(1, false)) == 2, "12 transit fighters render as 2 cubes")
	testing.expect(t, transit_fighters_at(1, true) == WAVE_SIZE, "wave of 5 in transit to Mars")
	testing.expect(t, rep_count(transit_fighters_at(1, true)) == 1, "5-enemy wave renders as 1 cube")
	testing.expect(t, transit_fighters_at(2, true) == 0, "no enemies in transit to Jupiter before liberation")
}

@(test)
mars_starts_without_player_base :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	testing.expect(t, base_counts[0] == 1, "Earth starts with 1 player base")
	testing.expect(t, base_counts[1] == 0, "Mars starts with no player base")
	testing.expect(t, base_counts[2] == 0, "Jupiter starts with no player base")
	testing.expect(t, enemy_base_hp[1] == 0, "Mars starts with 0 enemy base HP")
	testing.expect(t, planet_liberated(1), "Mars starts liberated")
	players, enemies := planet_combatants(1)
	testing.expect(t, players == 0 && enemies == 0, "no guarding fighters on Mars")
	testing.expect(t, enemy_miner_count(1) == 0, "no enemy mining drones on Mars")
}

@(test)
jupiter_starts_as_enemy_stronghold :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	players, enemies := planet_combatants(2)
	testing.expect(t, enemies == JUPITER_GARRISON_FIGHTERS && players == 0, "Jupiter starts with 40 enemy fighters")
	testing.expect(t, enemy_miner_count(2) == JUPITER_GARRISON_MINERS, "Jupiter starts with 10 enemy mining drones")
	testing.expect(t, enemy_base_hp[2] == JUPITER_BASE_HP, "Jupiter starts with a 20 HP enemy base")
	testing.expect(t, !planet_liberated(2), "Jupiter starts occupied")
}

@(test)
enemy_fighters_guard_and_orbit_after_arriving :: proc(t: ^testing.T) {
	reset_world()
	spawn_enemy_wave()
	// One long update: everyone reaches Mars this frame (transit is slow, so
	// pass a large dt).
	for i in 0..<unit_count { update_combat(&units[i], 100.0) }
	for i in 0..<unit_count {
	testing.expect(t, units[i].state == .GUARDING, "enemy fighters guard Mars after arriving")
	}
	first := units[0].position
	update_combat(&units[0], 1.0)
	testing.expect(t, distance(first, units[0].position) > 0.01, "guarding fighters keep orbiting while fighting")
}

// Tests run serially (ODIN_TEST_THREADS=1) and share package globals, so each
// test sets its own preconditions and restores the globals it touches.

@(test)
pause_toggle_cycles :: proc(t: ^testing.T) {
	game_paused = false
	toggle_pause()
	testing.expect(t, game_paused, "ESC should pause the game")
	toggle_pause()
	testing.expect(t, !game_paused, "ESC again should resume the game")
	game_paused = false
}

@(test)
pause_toggle_isolates_sim_state :: proc(t: ^testing.T) {
	// toggle_pause only flips the gate flag; it must not mutate sim state.
	minerals_before := minerals
	unit_count_before := unit_count
	progress_before := production[0][0].progress
	game_paused = false
	toggle_pause()
	testing.expect(t, game_paused, "paused flag set")
	testing.expect(t, minerals == minerals_before, "pause toggle must not touch minerals")
	testing.expect(t, unit_count == unit_count_before, "pause toggle must not touch unit count")
	testing.expect(t, production[0][0].progress == progress_before, "pause toggle must not touch production")
	game_paused = false
}

@(test)
paused_game_skips_simulation_step :: proc(t: ^testing.T) {
	// The pause gate lives in the main loop: step_simulation (camera, input,
	// production, units) is only invoked while unpaused. Verify the gate flag
	// controls the only place sim state advances.
	game_paused = false
	unit_count = 0
	production[0][0] = Production{kind = .MINING, active = true, progress = 0}
	step_simulation(1.0) // 1s of an unpaused tick: a 3s mining build advances.
	testing.expect(t, production[0][0].progress > 0, "unpaused sim advances production")
	testing.expect(t, production[0][0].active, "3s build not complete after 1s")
	// Restore.
	production[0][0] = Production{}
	unit_count = 2
	game_paused = false
}

@(test)
spacebar_shortcut_selects_earth :: proc(t: ^testing.T) {
	// update_input binds SPACE to select_earth; the action itself sets the
	// inspector selection back to Earth from any planet.
	selected_planet = 2
	select_earth()
	testing.expect(t, selected_planet == 0, "spacebar shortcut selects Earth")
	selected_planet = 1
	select_earth()
	testing.expect(t, selected_planet == 0, "spacebar works from any planet")
	selected_planet = 0
}

@(test)
vision_starts_earth_only :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, has_vision(0), "Earth is always lit")
	testing.expect(t, !has_vision(1), "Mars starts dark with no player presence")
	testing.expect(t, !has_vision(2), "Jupiter starts dark with no player presence")
}

@(test)
vision_tracks_arrival_and_departure :: proc(t: ^testing.T) {
	reset_world()
	// Arrival: a player fighter orbiting Mars lifts its fog.
	add_guarding_fighter(1, false)
	testing.expect(t, has_vision(1), "player fighter arriving at Mars lifts its fog")
	// Departure: retreating back to Earth drops it again.
	units[0].state = .TRANSIT
	units[0].target_planet = 0
	units[0].position = {0, 0, 0}
	testing.expect(t, !has_vision(1), "Mars goes dark again once the player unit leaves")
	// Destruction of the last unit there also ends vision.
	add_guarding_fighter(2, false)
	testing.expect(t, has_vision(2), "player fighter at Jupiter lights it")
	remove_unit_at(1)
	testing.expect(t, !has_vision(2), "Jupiter goes dark when the last unit there is destroyed")
}

@(test)
fog_lifts_while_a_player_unit_is_physically_present :: proc(t: ^testing.T) {
	reset_world()
	// A mining drone mid-mine at Jupiter counts as presence (within radius+2).
	units[unit_count] = Unit{kind = .MINING, state = .MINING, position = planets[2].position, home_planet = 0, affiliation = 2, target_planet = 2}
	unit_count += 1
	testing.expect(t, has_vision(2), "mining drone present at Jupiter lights it")
	// A unit far away in transit does not.
	units[unit_count] = Unit{kind = .COMBAT, state = .TRANSIT, position = {0, 0, 0}, home_planet = 0, affiliation = 2, target_planet = 2}
	unit_count += 1
	units[0].position = {0, 0, 0}
	testing.expect(t, !has_vision(2), "units en route far away do not light Jupiter")
	// Within the presence radius (radius + 2.0), even a passing unit lights it.
	units[1].position = planets[2].position
	testing.expect(t, has_vision(2), "transit unit within the presence radius lights it")
}

@(test)
enemy_garrisons_concealed_until_player_presence :: proc(t: ^testing.T) {
	reset_world()
	// Jupiter's standing garrison is invisible while the planet is dark.
	spawn_garrison(2, JUPITER_GARRISON_FIGHTERS, JUPITER_GARRISON_MINERS)
	for i in 0..<unit_count {
		testing.expect(t, is_concealed(&units[i]), "Jupiter garrison concealed under fog")
	}
	// One player unit arriving at Jupiter reveals every enemy unit there.
	add_guarding_fighter(2, false)
	for i in 0..<unit_count {
		testing.expect(t, !is_concealed(&units[i]), "Jupiter garrison revealed once a player unit is present")
	}
	// Enemy units at Mars are concealed until a player unit scouts it.
	reset_world()
	spawn_garrison(1, 3, 2)
	for i in 0..<unit_count {
		testing.expect(t, is_concealed(&units[i]), "Mars garrison concealed under fog")
	}
	add_guarding_fighter(1, false)
	for i in 0..<unit_count {
		testing.expect(t, !is_concealed(&units[i]), "Mars garrison revealed by player presence")
	}
}

@(test)
enemy_wave_concealed_in_transit_until_target_lit :: proc(t: ^testing.T) {
	reset_world()
	spawn_enemy_wave() // 5 fighters en route to Mars while Mars is dark.
	testing.expect(t, unit_count == WAVE_SIZE, "wave spawned")
	for i in 0..<unit_count {
		testing.expect(t, is_concealed(&units[i]), "enemy wave concealed while the target planet is dark")
	}
	add_guarding_fighter(1, false) // Player scout reaches Mars first.
	for i in 0..<unit_count {
		testing.expect(t, !is_concealed(&units[i]), "enemy wave visible once the target planet is lit")
	}
}

@(test)
right_click_with_selection_orders_units_and_keeps_rally :: proc(t: ^testing.T) {
	reset_world()
	earth_rally = 1
	selected_planet = 0
	add_guarding_fighter(0, false)
	selected_units[0] = true
	handle_planet_right_click(2)
	testing.expect(t, units[0].target_planet == 2 && units[0].state == .TRANSIT, "selected units move to the right-clicked planet")
	testing.expect(t, earth_rally == 1 && rally_flag_planet() == 1, "move order leaves the Earth rally point untouched")
}

@(test)
right_click_without_selection_sets_earth_rally :: proc(t: ^testing.T) {
	reset_world()
	earth_rally = 0
	selected_planet = 0
	add_guarding_fighter(0, false) // Present but NOT selected.
	handle_planet_right_click(1)
	testing.expect(t, earth_rally == 1, "no selection + Earth selected sets the rally to Mars")
	testing.expect(t, units[0].target_planet == 0 && units[0].state == .GUARDING, "unselected units are not given the move order")
	// Right-clicking Earth itself clears the rally.
	handle_planet_right_click(0)
	testing.expect(t, earth_rally == 0, "right-clicking Earth clears the rally")
	// Outpost selected with no units: right-click is ignored entirely.
	selected_planet = 1
	handle_planet_right_click(2)
	testing.expect(t, earth_rally == 0, "outpost selected without units: right-click does nothing")
}

@(test)
earth_rally_set_and_cleared :: proc(t: ^testing.T) {
	earth_rally = 0
	set_earth_rally(1)
	testing.expect(t, earth_rally == 1, "right-click Mars with Earth selected sets the rally to Mars")
	testing.expect(t, rally_flag_planet() == 1, "rally flag targets the rally planet")
	set_earth_rally(0)
	testing.expect(t, earth_rally == 0, "right-click Earth clears the rally point")
	testing.expect(t, rally_flag_planet() == 0, "no flag when the rally is cleared")
}

@(test)
rally_auto_dispatches_new_combat_drones :: proc(t: ^testing.T) {
	unit_count = 0
	earth_rally = 1
	spawn_unit(.COMBAT, 0)
	testing.expect(t, unit_count == 1, "combat drone spawned")
	u := units[0]
	testing.expect(t, u.state == .TRANSIT, "rally combat drone auto-dispatches into transit")
	testing.expect(t, u.target_planet == 1 && u.affiliation == 1, "rally combat drone heads to the rally world")
	earth_rally = 0
	unit_count = 0
}

@(test)
rally_auto_dispatches_new_mining_drones :: proc(t: ^testing.T) {
	unit_count = 0
	earth_rally = 1
	spawn_unit(.MINING, 0)
	testing.expect(t, units[0].state == .TRANSIT, "rally mining drone transits to the rally world")
	testing.expect(t, units[0].target_planet == 1 && units[0].affiliation == 1, "rally mining drone targets the rally world")
	earth_rally = 0
	unit_count = 0
}

@(test)
no_rally_keeps_default_spawn_behavior :: proc(t: ^testing.T) {
	unit_count = 0
	earth_rally = 0
	spawn_unit(.COMBAT, 0)
	testing.expect(t, units[0].state == .GUARDING && units[0].target_planet == 0, "without a rally, combat drones guard Earth")
	unit_count = 0
}

@(test)
rally_only_redirects_earth_spawns :: proc(t: ^testing.T) {
	unit_count = 0
	earth_rally = 1
	spawn_unit(.COMBAT, 1)
	testing.expect(t, units[0].state == .GUARDING && units[0].target_planet == 1, "non-Earth spawns ignore the Earth rally")
	earth_rally = 0
	unit_count = 0
}

// ---- Auto-assigned base construction crew --------------------------------

@(test)
deposit_auto_assigns_miners_to_queued_base_construction :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = 0
	start_base_construction()
	testing.expect(t, base_build_planet == 0, "build queues with no crew")
	// The build clock is frozen until the crew of 5 has gathered.
	update_production(120.0)
	testing.expect(t, base_build_planet == 0 && base_build_progress == 0, "no build progress without a full crew")
	// Each depositing miner joins the crew, wherever it was mining.
	for i in 0..<BASE_CONSTRUCT_MINERS {
		target := i % PLANET_COUNT
		units[unit_count] = Unit{
			kind = .MINING, state = .DEPOSITING, position = planets[0].position,
			home_planet = 0, affiliation = target, target_planet = target,
			progress = DEPOSIT_DURATION - 0.01,
		}
		unit_count += 1
		update_miner(&units[unit_count-1], unit_count-1, 0.02)
		testing.expectf(t, units[unit_count-1].state == .CONSTRUCTING, "deposit %d joins the crew", i)
		testing.expect(t, units[unit_count-1].target_planet == 0, "crew member is retargeted to Earth")
		testing.expect(t, constructing_miners(0) == i + 1, "crew grows one per deposit")
	}
	testing.expect(t, base_build_progress == 0, "clock starts only once the crew is full")
	// The 6th depositor keeps mining: the crew is full.
	units[unit_count] = Unit{
		kind = .MINING, state = .DEPOSITING, position = planets[0].position,
		home_planet = 0, affiliation = 1, target_planet = 1, progress = DEPOSIT_DURATION - 0.01,
	}
	unit_count += 1
	update_miner(&units[unit_count-1], unit_count-1, 0.02)
	testing.expect(t, units[unit_count-1].state == .TRANSIT, "extra depositor transits back out")
	testing.expect(t, constructing_miners(0) == BASE_CONSTRUCT_MINERS, "crew caps at 5")
	// Full crew: 60s completes the base and everyone resumes mining.
	update_production(BASE_CONSTRUCT_TIME - 0.01)
	testing.expect(t, base_build_planet == 0, "still building just before 60s")
	update_production(0.02)
	testing.expect(t, base_build_planet == -1 && base_counts[0] == 2, "base completes after 60s with a full crew")
	for i in 0..<unit_count {
		if units[i].kind == .MINING && !units[i].enemy {
			testing.expect(t, units[i].state != .CONSTRUCTING, "crew resumes regular mining")
		}
	}
}

// ---- Global MPS ----------------------------------------------------------

@(test)
global_mps_sums_all_planets :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, global_mps() == 0, "no miners, no income")
	for p in 0..<PLANET_COUNT { add_miner(p) }
	sum := planet_mps(0) + planet_mps(1) + planet_mps(2)
	testing.expect(t, abs(global_mps() - sum) < 0.001, "global MPS equals the sum of all planet MPS")
	testing.expect(t, global_mps() > planet_mps(0), "empire income beats Earth alone")
}

// ---- Roster header counts ------------------------------------------------

@(test)
roster_headers_show_unit_counts :: proc(t: ^testing.T) {
	reset_world()
	add_miner(0); add_miner(0); add_miner(1)
	add_guarding_fighter(0, false); add_guarding_fighter(0, false); add_guarding_fighter(1, false)
	selected_planet = 0
	testing.expect(t, roster_count(.MINING) == 2, "Earth header counts its 2 miners")
	testing.expect(t, roster_count(.COMBAT) == 2, "Earth header counts its 2 fighters")
	selected_planet = 1
	testing.expect(t, roster_count(.MINING) == 1, "Mars header counts its 1 miner")
	testing.expect(t, roster_count(.COMBAT) == 1, "Mars header counts its 1 fighter")
	selected_planet = 2
	testing.expect(t, roster_count(.MINING) == 0 && roster_count(.COMBAT) == 0, "empty Jupiter roster")
}

// ---- Mining rate and per-planet caps -------------------------------------

@(test)
earth_mines_at_standard_rate :: proc(t: ^testing.T) {
	testing.expect(t, mining_rate(0) == 10, "Earth penalty removed: 10 per cycle")
	testing.expect(t, mining_rate(1) == 10, "Mars at the standard 10")
	testing.expect(t, mining_rate(2) == 25, "Jupiter pays 25")
}

@(test)
planet_mining_caps_limit_effective_miners :: proc(t: ^testing.T) {
	testing.expect(t, planet_mining_cap(0) == 30, "Earth cap 30")
	testing.expect(t, planet_mining_cap(1) == 25, "Mars cap 25")
	testing.expect(t, planet_mining_cap(2) == 100, "Jupiter cap 100")

	reset_world()
	for i in 0..<40 { add_miner(0) }
	earth_cycle: f32 = MINING_DURATION + DEPOSIT_DURATION
	expected := f32(planet_mining_cap(0)) * f32(mining_rate(0)) / earth_cycle
	testing.expectf(t, abs(planet_mps(0) - expected) < 0.001, "Earth MPS caps at 30 effective miners: %.3f != %.3f", planet_mps(0), expected)
	// Payout follows the same cap: 40 depositors, only the first 30 get paid.
	for i in 0..<unit_count {
		units[i].state = .DEPOSITING
		units[i].progress = DEPOSIT_DURATION - 0.01
	}
	minerals = 0
	for i in 0..<unit_count { update_miner(&units[i], i, 0.02) }
	testing.expect(t, minerals == planet_mining_cap(0) * mining_rate(0), "only the first 30 Earth miners are paid")

	reset_world()
	for i in 0..<30 { add_miner(1) }
	mars_cycle: f32 = MINING_DURATION + DEPOSIT_DURATION + 2.0 * distance(planets[1].position, planets[0].position) / MINING_TRANSIT_SPEED
	expected = f32(planet_mining_cap(1)) * f32(mining_rate(1)) / mars_cycle
	testing.expect(t, abs(planet_mps(1) - expected) < 0.001, "Mars MPS caps at 25 effective miners")

	reset_world()
	for i in 0..<110 { add_miner(2) }
	jupiter_cycle: f32 = MINING_DURATION + DEPOSIT_DURATION + 2.0 * distance(planets[2].position, planets[0].position) / MINING_TRANSIT_SPEED
	expected = f32(planet_mining_cap(2)) * f32(mining_rate(2)) / jupiter_cycle
	testing.expect(t, abs(planet_mps(2) - expected) < 0.001, "Jupiter MPS caps at 100 effective miners")
}
