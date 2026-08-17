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
	enemy_base_hp = [PLANET_COUNT]int{0, MARS_BASE_HP, JUPITER_BASE_HP}
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
	testing.expect(t, abs(planet_mps(0) - f32(1) / 3) < 0.001, "Earth MPS reflects the miner immediately")
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
base_construction_requires_liberated_planet_and_five_miners :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = 1
	// Occupied planet: blocked even with miners present.
	for i in 0..<5 { add_miner(1) }
	start_base_construction()
	testing.expect(t, base_build_planet != 1, "occupied planet blocks base construction even with miners present")

	reset_world()
	selected_planet = 1
	enemy_base_hp[1] = 0
	start_base_construction()
	testing.expect(t, base_build_planet != 1, "liberated planet with no miners blocks construction")
	for i in 0..<4 { add_miner(1) }
	start_base_construction()
	testing.expect(t, base_build_planet != 1, "4 miners still block construction")
	add_miner(1)
	testing.expect(t, player_miners_present(1) == 5, "5 miners present")
	before := minerals
	start_base_construction()
	testing.expect(t, base_build_planet == 1, "liberated planet with 5 miners allows construction")
	testing.expect(t, minerals == before - 200, "construction costs 200 minerals")
}

@(test)
construction_miners_stop_mining_and_resume :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = 1
	enemy_base_hp[1] = 0
	for i in 0..<5 { add_miner(1) }
	full_mps := f32(5) * f32(mining_rate(1)) / 3.0
	testing.expect(t, abs(planet_mps(1) - full_mps) < 0.001, "5 miners mine at full rate before construction")
	start_base_construction()
	testing.expect(t, abs(planet_mps(1)) < 0.001, "construction miners stop generating MPS")
	for i in 0..<unit_count {
		if units[i].kind == .MINING { testing.expect(t, units[i].state == .CONSTRUCTING, "miners switch to constructing") }
	}
	update_production(59.9)
	testing.expect(t, base_counts[1] == 0 && base_build_planet == 1, "construction still in progress before 60s")
	update_production(0.2)
	testing.expect(t, base_counts[1] == 1 && base_build_planet == -1, "base completes after one full minute")
	for i in 0..<unit_count {
		if units[i].kind == .MINING { testing.expect(t, units[i].state == .MINING, "miners resume mining") }
	}
	testing.expect(t, abs(planet_mps(1) - full_mps) < 0.001, "MPS restored after construction")
}

@(test)
jupiter_base_construction_also_requires_five_miners :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = 2
	enemy_base_hp[2] = 0
	start_base_construction()
	testing.expect(t, base_build_planet != 2, "Jupiter needs 5 miners before construction")
	for i in 0..<5 { add_miner(2) }
	start_base_construction()
	testing.expect(t, base_build_planet == 2, "Jupiter construction unlocks with 5 miners present")
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
mars_and_jupiter_start_occupied :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	players, enemies := planet_combatants(1)
	testing.expect(t, enemies == MARS_GARRISON_FIGHTERS && players == 0, "enemy fighters garrison Mars")
	testing.expect(t, enemy_miner_count(1) == MARS_GARRISON_MINERS, "enemy mining drones garrison Mars")
	testing.expect(t, enemy_base_hp[1] == MARS_BASE_HP, "enemy base on Mars intact")
	players, enemies = planet_combatants(2)
	testing.expect(t, enemies == JUPITER_GARRISON_FIGHTERS && players == 0, "enemy fighters garrison Jupiter")
	testing.expect(t, enemy_miner_count(2) == JUPITER_GARRISON_MINERS, "enemy mining drones garrison Jupiter")
	testing.expect(t, enemy_base_hp[2] == JUPITER_BASE_HP, "enemy base on Jupiter intact")
	testing.expect(t, base_counts[1] == 0 && base_counts[2] == 0, "no player bases on occupied planets")
	testing.expect(t, !planet_liberated(1) && !planet_liberated(2), "both planets start occupied")
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
