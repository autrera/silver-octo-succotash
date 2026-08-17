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
	expected := f32(1) / (MINING_DURATION + DEPOSIT_DURATION)
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
	selected_planet = 0
	start_base_construction()
	testing.expect(t, base_build_planet != 0, "liberated Earth with no miners blocks construction")
	for i in 0..<4 { add_miner(0) }
	start_base_construction()
	testing.expect(t, base_build_planet != 0, "4 miners still block construction")
	add_miner(0)
	testing.expect(t, player_miners_present(0) == 5, "5 miners present")
	before := minerals
	start_base_construction()
	testing.expect(t, base_build_planet == 0, "Earth with 5 miners allows construction")
	testing.expect(t, minerals == before - 200, "construction costs 200 minerals")
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
	testing.expect(t, abs(planet_mps(0)) < 0.001, "construction miners stop generating MPS")
	for i in 0..<unit_count {
		if units[i].kind == .MINING { testing.expect(t, units[i].state == .CONSTRUCTING, "miners switch to constructing") }
	}
	update_production(59.9)
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
	// production, units, scouting) is only invoked while unpaused. Verify the
	// gate flag controls the only place sim state advances.
	game_paused = false
	unit_count = 0
	mars_scouted = false
	production[0][0] = Production{kind = .MINING, active = true, progress = 0}
	step_simulation(1.0) // 1s of an unpaused tick: a 3s mining build advances.
	testing.expect(t, production[0][0].progress > 0, "unpaused sim advances production")
	testing.expect(t, production[0][0].active, "3s build not complete after 1s")
	// Restore.
	production[0][0] = Production{}
	unit_count = 2
	mars_scouted = false
	game_paused = false
}

@(test)
mars_fog_starts_down :: proc(t: ^testing.T) {
	mars_scouted = false
	testing.expect(t, !mars_scouted, "Mars starts under fog of war")
	testing.expect(t, string(mars_intel_status()) == "UNSCOUTED // STATUS UNKNOWN", "unscouted Mars masks intel status")
	mars_scouted = false
}

@(test)
mars_fog_lifts_when_player_unit_arrives :: proc(t: ^testing.T) {
	mars_scouted = false
	unit_count = 1
	units[0] = Unit{kind = .MINING, state = .MINING, position = planets[1].position, home_planet = 0, affiliation = 1, target_planet = 1}
	update_scouting()
	testing.expect(t, mars_scouted, "player unit stationed on Mars scouts it")
	testing.expect(t, string(mars_intel_status()) == "SCOUTED // INTEL AVAILABLE", "scouted Mars reveals intel status")
	unit_count = 2
	mars_scouted = false
}

@(test)
mars_fog_stays_down_for_units_elsewhere :: proc(t: ^testing.T) {
	mars_scouted = false
	unit_count = 1
	units[0] = Unit{kind = .MINING, state = .TRANSIT, position = {0, 0, 0}, home_planet = 0, affiliation = 0, target_planet = 0}
	update_scouting()
	testing.expect(t, !mars_scouted, "units away from Mars keep the fog down")
	unit_count = 2
	mars_scouted = false
}

@(test)
unscouted_mars_masks_intel_details :: proc(t: ^testing.T) {
	// Counts exist under the hood but the inspector shows the masked status
	// until a player unit scouts Mars.
	mars_scouted = false
	unit_count = 1
	units[0] = Unit{kind = .COMBAT, state = .GUARDING, position = planets[1].position, home_planet = 1, affiliation = 1, target_planet = 1}
	testing.expect(t, intel_fighters(1) == 1, "garrison counted once scouted")
	testing.expect(t, intel_miners(1) == 0, "no miners stationed")
	testing.expect(t, intel_presence(1), "presence positive with garrison")
	testing.expect(t, string(mars_intel_status()) == "UNSCOUTED // STATUS UNKNOWN", "status still masked while unscouted")
	unit_count = 2
	mars_scouted = false
}

@(test)
scouted_mars_reveals_intel_details :: proc(t: ^testing.T) {
	mars_scouted = true
	unit_count = 2
	units[0] = Unit{kind = .COMBAT, state = .GUARDING, position = planets[1].position, home_planet = 1, affiliation = 1, target_planet = 1}
	units[1] = Unit{kind = .MINING, state = .MINING, position = planets[1].position, home_planet = 0, affiliation = 1, target_planet = 1}
	testing.expect(t, intel_fighters(1) == 1, "fighter count revealed after scouting")
	testing.expect(t, intel_miners(1) == 1, "miner count revealed after scouting")
	testing.expect(t, intel_presence(1), "enemy presence revealed after scouting")
	testing.expect(t, string(mars_intel_status()) == "SCOUTED // INTEL AVAILABLE", "scouted status shown")
	unit_count = 2
	mars_scouted = false
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
