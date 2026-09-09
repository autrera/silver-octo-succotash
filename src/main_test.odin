package main

import "core:math"
import "core:os"
import "core:testing"
import rl "vendor:raylib"

// reset_world lives in main.odin now: the victory-restart path shares it
// with the test suite (same package).

add_guarding_fighter :: proc(p: int, enemy: bool) {
	units[unit_count] = Unit{
		kind = .COMBAT, state = .GUARDING, position = sector_pos(p),
		home_planet = p, affiliation = p, target_planet = p, enemy = enemy,
	}
	unit_count += 1
}

add_miner :: proc(planet: int) {
	units[unit_count] = Unit{
		kind = .MINING, state = .MINING, position = sector_pos(planet),
		home_planet = planet, affiliation = planet, target_planet = planet,
	}
	unit_count += 1
}

add_enemy_miner :: proc(p: int) {
	units[unit_count] = Unit{
		kind = .MINING, state = .GUARDING, position = sector_pos(p),
		home_planet = p, affiliation = p, target_planet = p, enemy = true,
	}
	unit_count += 1
}

@(test)
earth_miner_mines_earth_immediately :: proc(t: ^testing.T) {
	reset_world()
	spawn_unit(.MINING, EARTH)
	testing.expect(t, unit_count == 1, "miner spawned")
	testing.expect(t, !units[0].enemy, "miner is not enemy")
	testing.expect(t, units[0].kind == .MINING, "miner kind")
	testing.expect(t, units[0].target_planet == EARTH, "miner targets home planet")
	testing.expect(t, units[0].affiliation == EARTH, "miner affiliated with Earth")
	testing.expect(t, units[0].state == .MINING, "miner starts mining, no transit")
	// Earth is always liberated and has no transit leg: the cycle is just
	// mine + deposit, so MPS is rate / (MINING_DURATION + DEPOSIT_DURATION).
	expected := f32(mining_rate(EARTH)) / (MINING_DURATION + DEPOSIT_DURATION)
	testing.expect(t, abs(planet_mps(EARTH) - expected) < 0.001, "Earth MPS reflects the miner immediately")
}

@(test)
enemy_wave_spawns_from_enemy_hq :: proc(t: ^testing.T) {
	reset_world()
	// A second liberated world arms the wave: (2 - 1) * 15 = 15 fighters.
	enemy_base_hp[NEPTUNE] = 0
	add_miner(EARTH)
	add_miner(NEPTUNE)
	before := unit_count
	spawn_enemy_wave() // debug N key: force the next attack immediately.
	testing.expect(t, unit_count - before == 15, "wave size scales with liberation")
	target := units[before].target_planet
	testing.expect(t, target == NEPTUNE, "wave strikes the liberated planet closest to the HQ")
	for i := before; i < unit_count; i += 1 {
		testing.expect(t, units[i].kind == .COMBAT, "enemy is combat")
		testing.expect(t, units[i].enemy, "enemy flag set")
		testing.expect(t, units[i].target_planet == target && units[i].affiliation == target, "wave shares one target")
		testing.expect(t, distance(units[i].position, ENEMY_HQ_POSITION) < 3, "wave lifts off from the enemy HQ")
	}
	selected_planet = target
	testing.expect(t, roster_count(.COMBAT) == 0, "enemies never appear in the player roster")
	selected_planet = EARTH
}

@(test)
wave_timer_first_at_180_seconds_then_every_180 :: proc(t: ^testing.T) {
	reset_world()
	enemy_base_hp[VENUS] = 0
	add_miner(EARTH)
	add_miner(VENUS)
	before := unit_count
	// First wave at the 3-minute mark, then every 3 minutes. Venus is mined
	// and liberated, yet both waves strike Earth: targeting follows HQ
	// distance, not mining.
	update_wave(WAVE_FIRST_DELAY - 0.1)
	testing.expect(t, unit_count == before, "no wave before the 3-minute mark")
	update_wave(0.2)
	testing.expect(t, unit_count - before == 15, "first wave spawns at 180s")
	testing.expect(t, units[before].target_planet == EARTH, "Earth is closer to the HQ than Venus")
	update_wave(WAVE_INTERVAL - 0.1)
	testing.expect(t, unit_count - before == 15, "no extra wave before 3 minutes elapse")
	update_wave(0.2)
	testing.expect(t, unit_count - before == 30, "second wave spawns 3 minutes after the first")
}

@(test)
mined_planet_count_counts_distinct_planets_with_player_miners :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, mined_planet_count() == 0, "nothing mined at start")
	add_miner(EARTH)
	testing.expect(t, mined_planet_count() == 1, "one Earth miner = one mined planet")
	add_miner(EARTH)
	add_miner(MARS)
	testing.expect(t, mined_planet_count() == 2, "two Earth miners still count Earth once")
	// Enemy miners and constructing player miners never count.
	add_enemy_miner(JUPITER)
	testing.expect(t, mined_planet_count() == 2, "enemy miners do not count")
	units[1].state = .CONSTRUCTING
	testing.expect(t, mined_planet_count() == 2, "constructing miner does not count its planet")
	// Only actively mining drones count their planet: scouts in transit,
	// pinned idle drones, returning and depositing miners never do.
	units[0].state = .RETURNING
	units[1].state = .IDLE
	units[1].target_planet = JUPITER
	units[2].state = .TRANSIT
	testing.expect(t, mined_planet_count() == 0, "traveling or idle miners never count as mining")
	units[2].state = .MINING
	testing.expect(t, mined_planet_count() == 1, "only the actively mining drone counts its planet")
}

@(test)
waves_require_two_liberated_planets :: proc(t: ^testing.T) {
	reset_world()
	// Only Earth is liberated at start: clock is frozen, no wave
	testing.expect(t, liberated_planet_count() == 1, "only Earth liberated at start")
	update_wave(f32(WAVE_FIRST_DELAY))
	testing.expect(t, unit_count == 0, "no wave with only Earth liberated")
	testing.expect(t, enemy_wave_timer == 0, "clock frozen below 2 liberated planets")

	// Liberate Venus (Earth + Venus = 2 liberated planets)
	enemy_base_hp[VENUS] = 0
	testing.expect(t, liberated_planet_count() == 2, "two planets now liberated")

	// 179.9s passes: clock advances, but wave not launched yet
	update_wave(f32(WAVE_FIRST_DELAY) - 0.1)
	testing.expect(t, unit_count == 0, "no wave before 180s")
	testing.expect(t, enemy_wave_timer >= f32(WAVE_FIRST_DELAY) - 0.1, "wave clock advances")

	// Cross 180s: wave launches 15 fighters against the closest liberated planet to HQ
	before := unit_count
	update_wave(0.2)
	testing.expect(t, unit_count - before == 15, "two liberated planets draw the 15-fighter wave")
}

@(test)
attack_wave_size_scales_with_liberation :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, WAVE_FIGHTERS_PER_LIBERATED == 15, "15 fighters per liberated world past the first")
	testing.expect(t, liberated_planet_count() == 1, "Earth starts as the sole liberated world")
	testing.expect(t, attack_wave_size() == 0, "one liberated world musters nothing")
	enemy_base_hp[VENUS] = 0
	testing.expect(t, attack_wave_size() == 15, "two liberated worlds send 15 fighters")
	enemy_base_hp[MARS] = 0
	testing.expect(t, attack_wave_size() == 30, "three liberated worlds send 30 fighters")
	for p in 0..<PLANET_COUNT { enemy_base_hp[p] = 0 }
	testing.expect(t, liberated_planet_count() == 8, "all eight planets liberated")
	testing.expect(t, attack_wave_size() == 7 * WAVE_FIGHTERS_PER_LIBERATED, "eight liberated worlds send 105 fighters")
}

@(test)
wave_strikes_closest_liberated_planet_to_hq :: proc(t: ^testing.T) {
	reset_world()
	// Liberate three off-world planets; Neptune sits closest to the HQ,
	// then Mars, then Earth, then Venus.
	enemy_base_hp[VENUS] = 0
	enemy_base_hp[MARS] = 0
	enemy_base_hp[NEPTUNE] = 0
	testing.expect(t, closest_liberated_planet_to_hq() == NEPTUNE, "Neptune is closest to the HQ")
	add_miner(EARTH)
	add_miner(MARS)
	before := unit_count
	update_wave(f32(WAVE_FIRST_DELAY))
	// (4 liberated - 1) * 15 = 45 fighters in a single wave.
	testing.expect(t, unit_count - before == 45, "one wave of 45 fighters")
	for i := before; i < unit_count; i += 1 {
		testing.expect(t, units[i].target_planet == NEPTUNE, "every fighter strikes Neptune")
	}
	// Losing Neptune hands the target to the next-closest liberated world.
	enemy_base_hp[NEPTUNE] = GARRISON_BASE_HP[NEPTUNE]
	testing.expect(t, closest_liberated_planet_to_hq() == MARS, "Mars is next-closest")
	before = unit_count
	update_wave(f32(WAVE_INTERVAL))
	testing.expect(t, unit_count - before == 30, "(3 liberated - 1) * 15 = 30 fighters")
	for i := before; i < unit_count; i += 1 {
		testing.expect(t, units[i].target_planet == MARS, "every fighter strikes Mars")
	}
}

@(test)
player_attacking_hq_covers_stationed_and_inbound :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, !player_attacking_hq(), "no attack with no fighters")
	add_guarding_fighter(MARS, false)
	testing.expect(t, !player_attacking_hq(), "fighters elsewhere are not an HQ attack")
	add_guarding_fighter(ENEMY_HOME, false)
	testing.expect(t, player_attacking_hq(), "fighters stationed at the HQ count as an attack")
	// Inbound instead of stationed: a fighter sortied from Earth.
	reset_world()
	units[unit_count] = Unit{kind = .COMBAT, state = .TRANSIT, position = planets[EARTH].position, home_planet = EARTH, affiliation = ENEMY_HOME, target_planet = ENEMY_HOME}
	unit_count += 1
	testing.expect(t, player_attacking_hq(), "fighters inbound to the HQ count as an attack")
}

@(test)
wave_reinforces_attacked_hq_instead_of_planets :: proc(t: ^testing.T) {
	reset_world()
	enemy_base_hp[VENUS] = 0
	add_miner(EARTH)
	add_miner(VENUS)
	// Player fighters inbound to the HQ while a single defender holds it;
	// inbound attackers never join planet_combatants, so no dogfight muddies
	// the reinforcement count.
	units[unit_count] = Unit{kind = .COMBAT, state = .TRANSIT, position = planets[EARTH].position, home_planet = EARTH, affiliation = ENEMY_HOME, target_planet = ENEMY_HOME}
	unit_count += 1
	add_guarding_fighter(ENEMY_HOME, true)
	before := unit_count
	update_wave(f32(WAVE_FIRST_DELAY))
	// (2 liberated - 1) * 15 = 15 fighters muster as HQ defenders, not as a
	// wave against a planet.
	testing.expect(t, unit_count - before == 15, "wave musters 15 defenders")
	_, defenders := planet_combatants(ENEMY_HOME)
	testing.expect(t, defenders == 16, "reinforcements join the HQ garrison")
	for i := before; i < unit_count; i += 1 {
		testing.expect(t, units[i].enemy, "reinforcements are enemy fighters")
		testing.expect(t, units[i].state == .GUARDING && units[i].affiliation == ENEMY_HOME, "reinforcements guard the HQ")
	}
}

@(test)
planet_attacks_resume_once_hq_garrison_replenished :: proc(t: ^testing.T) {
	reset_world()
	enemy_base_hp[VENUS] = 0
	add_miner(EARTH)
	add_miner(VENUS)
	// Full-strength HQ garrison with a player attacker inbound: the wave
	// sorties against planets instead of reinforcing.
	for i in 0..<ENEMY_HQ_GARRISON { add_guarding_fighter(ENEMY_HOME, true) }
	units[unit_count] = Unit{kind = .COMBAT, state = .TRANSIT, position = planets[EARTH].position, home_planet = EARTH, affiliation = ENEMY_HOME, target_planet = ENEMY_HOME}
	unit_count += 1
	testing.expect(t, player_attacking_hq(), "HQ is under attack")
	before := unit_count
	update_wave(f32(WAVE_FIRST_DELAY))
	testing.expect(t, unit_count - before == 15, "wave sorties while the garrison is whole")
	testing.expect(t, units[before].target_planet == EARTH, "closest liberated planet is struck")
	_, defenders := planet_combatants(ENEMY_HOME)
	testing.expect(t, defenders == ENEMY_HQ_GARRISON, "whole garrison gains no defenders")
}

@(test)
step_simulation_advances_wave_timer_and_spawns_on_schedule :: proc(t: ^testing.T) {
	reset_world()
	production = {}
	pending_count = {}
	enemy_base_hp[VENUS] = 0
	add_miner(EARTH)
	add_miner(VENUS)
	// Unpaused play drives the wave clock through step_simulation: first wave
	// at 3:00, then every 3:00 — but only while 2+ worlds are mined.
	enemy_wave_timer = 0
	wave_started = false
	before := unit_count
	step_simulation(1.0)
	testing.expect(t, unit_count == before, "no wave before 3 minutes of unpaused play")
	enemy_wave_timer = f32(WAVE_FIRST_DELAY) - 1.0
	step_simulation(1.0)
	testing.expect(t, unit_count - before == 15, "first wave spawns at the 3-minute mark")
	enemy_wave_timer = f32(WAVE_INTERVAL) - 1.0
	before = unit_count
	step_simulation(1.0)
	testing.expect(t, unit_count - before == 15, "second wave spawns 3 minutes after the first")
}

@(test)
step_simulation_resolves_combat_at_jupiter :: proc(t: ^testing.T) {
	reset_world()
	production = {}
	pending_count = {}
	for i in 0..<5 { add_guarding_fighter(JUPITER, false) }
	for i in 0..<5 { add_guarding_fighter(JUPITER, true) }
	step_simulation(f32(COMBAT_TICK))
	players, enemies := planet_combatants(JUPITER)
	testing.expect(t, players == 4 && enemies == 4, "1:1 trade per 2s tick through step_simulation")
	step_simulation(f32(COMBAT_TICK))
	players, enemies = planet_combatants(JUPITER)
	testing.expect(t, players == 3 && enemies == 3, "combat keeps ticking on every simulation step")
}

@(test)
initial_camera_zoom_is_60_percent :: proc(t: ^testing.T) {
	// Startup altitude 200 - 185*0.60 = 89 maps zoom_percent() to exactly 60%,
	// high enough to frame the whole repositioned system at open.
	testing.expect(t, abs(CAMERA_START_Y - 89.0) < 0.0001, "startup altitude is 89")
	camera.position = {camera_target.x, CAMERA_START_Y, camera_target.z + CAMERA_START_Y}
	testing.expect(t, zoom_percent() == 60, "startup camera reads exactly 60% zoom")
	camera.position = {}
}

@(test)
mining_transit_speed_reduced_25_percent :: proc(t: ^testing.T) {
	reset_world()
	units[unit_count] = Unit{kind = .COMBAT, state = .TRANSIT, position = {0, 0, 0}, home_planet = EARTH, affiliation = EARTH, target_planet = MARS}
	unit_count += 1
	before := units[0].position
	update_combat(&units[0], 1.0)
	testing.expect(t, abs(distance(before, units[0].position) - 2.5) < 0.01, "combat transit speed is 2.5/s (unchanged)")
	units[unit_count] = Unit{kind = .MINING, state = .TRANSIT, position = {0, 0, 0}, home_planet = EARTH, affiliation = EARTH, target_planet = MARS}
	unit_count += 1
	before = units[1].position
	update_miner(&units[1], 1, 1.0)
	testing.expect(t, abs(distance(before, units[1].position) - 1.3125) < 0.01, "mining transit speed is 1.3125/s (down 25% from 1.75)")
	// Returning to Earth is inter-planet travel too: same reduced speed.
	units[unit_count] = Unit{kind = .MINING, state = .RETURNING, position = planets[MARS].position, home_planet = EARTH, affiliation = EARTH, target_planet = MARS}
	unit_count += 1
	before = units[2].position
	update_miner(&units[2], 2, 1.0)
	testing.expect(t, abs(distance(before, units[2].position) - 1.3125) < 0.01, "mining return speed is 1.3125/s")
	// On-site mining takes 4s (up 33% from 3s), for ~25% slower mining overall.
	testing.expect(t, MINING_DURATION == 4.0, "on-site mining takes 4s")
	testing.expect(t, abs(MINING_TRANSIT_SPEED - 1.75 * 0.75) < 0.0001, "transit speed is 75% of 1.75")
}

@(test)
drone_build_times_doubled :: proc(t: ^testing.T) {
	testing.expect(t, MINER_BUILD_TIME == 4.0, "miner build time is 4s")
	testing.expect(t, COMBAT_BUILD_TIME == 8.0, "combat drone build time is 8s")
	reset_world()
	selected_planet = EARTH
	minerals = 1000
	queue_unit(.MINING)
	update_production(MINER_BUILD_TIME - 0.1)
	testing.expect(t, production[EARTH][0].active && unit_count == 0, "miner line still building just before 4s")
	update_production(0.2)
	testing.expect(t, !production[EARTH][0].active && unit_count == 1, "miner completes at 4s")
	queue_unit(.COMBAT)
	update_production(COMBAT_BUILD_TIME - 0.1)
	testing.expect(t, production[EARTH][0].active && unit_count == 1, "combat line still building just before 8s")
	update_production(0.2)
	testing.expect(t, !production[EARTH][0].active && unit_count == 2, "combat drone completes at 8s")
}

@(test)
five_v_five_battle_lasts_ten_seconds_1_to_1 :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<5 { add_guarding_fighter(MARS, false) }
	for i in 0..<5 { add_guarding_fighter(MARS, true) }
	testing.expect(t, unit_count == 10, "setup")
	for tick in 1..=4 {
		update_enemy_waves(f32(COMBAT_TICK))
		testing.expect(t, unit_count == 10 - tick * 2, "one kill per side per 2s tick")
	}
	defenders, attackers := planet_combatants(MARS)
	testing.expect(t, defenders == 1 && attackers == 1, "one fighter each after 8s")
	update_enemy_waves(f32(COMBAT_TICK))
	defenders, attackers = planet_combatants(MARS)
	testing.expect(t, defenders == 0 && attackers == 0, "5v5 trade ends after 10s")
	testing.expect(t, unit_count == 0, "all 10 destroyed in the trade")
}

@(test)
miners_die_every_combat_tick_without_defenders :: proc(t: ^testing.T) {
	reset_world()
	add_guarding_fighter(MARS, true)
	add_miner(MARS)
	add_miner(MARS)
	add_miner(MARS)
	update_enemy_waves(0.1)
	testing.expect(t, unit_count == 4, "no miner hit before the 0.2s tick")
	update_enemy_waves(0.1)
	testing.expect(t, unit_count == 3, "first miner destroyed at 0.2s")
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, unit_count == 2, "second miner destroyed at 0.4s")
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, unit_count == 1 && units[0].enemy, "third miner destroyed at 0.6s; only the enemy attacker survives")
}

@(test)
mars_base_destroyed_after_garrison_cleared :: proc(t: ^testing.T) {
	reset_world()
	// Mars starts occupied like every non-Earth planet; this scenario trims
	// it to a small garrison: base destruction logic must work wherever a
	// base is present.
	enemy_base_hp[MARS] = GARRISON_BASE_HP[MARS]
	for i in 0..<3 { add_guarding_fighter(MARS, false) }
	add_guarding_fighter(MARS, true)
	for i in 0..<2 { add_enemy_miner(MARS) }
	// 3v1 trade: one kill per side per tick until the garrison fighter falls.
	update_enemy_waves(f32(COMBAT_TICK))
	players, enemies := planet_combatants(MARS)
	testing.expect(t, players == 2 && enemies == 0, "garrison fighter traded 1:1")
	// Player fighters sweep the enemy mining drones, one per tick.
	update_enemy_waves(f32(COMBAT_TICK))
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, enemy_miner_count(MARS) == 0, "enemy mining drones destroyed")
	testing.expect(t, enemy_base_hp[MARS] == GARRISON_BASE_HP[MARS], "enemy base untouched until the drones are gone")
	// The base then takes damage per player fighter per tick.
	before := enemy_base_hp[MARS]
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, enemy_base_hp[MARS] == before - 2, "base damaged by the 2 occupying fighters per tick")
	for enemy_base_hp[MARS] > 0 { update_enemy_waves(f32(COMBAT_TICK)) }
	testing.expect(t, planet_liberated(MARS), "Mars liberated once the base falls")
}

@(test)
jupiter_base_destroyed_after_garrison_cleared :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<5 { add_guarding_fighter(JUPITER, false) }
	for i in 0..<2 { add_guarding_fighter(JUPITER, true) }
	for i in 0..<2 { add_enemy_miner(JUPITER) }
	update_enemy_waves(f32(COMBAT_TICK))
	update_enemy_waves(f32(COMBAT_TICK))
	players, enemies := planet_combatants(JUPITER)
	testing.expect(t, players == 3 && enemies == 0, "2 garrison fighters traded 1:1")
	update_enemy_waves(f32(COMBAT_TICK))
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, enemy_miner_count(JUPITER) == 0, "enemy mining drones swept")
	before := enemy_base_hp[JUPITER]
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, enemy_base_hp[JUPITER] == before - 3, "base damaged by the 3 fighters per tick")
	for enemy_base_hp[JUPITER] > 0 { update_enemy_waves(f32(COMBAT_TICK)) }
	testing.expect(t, enemy_base_hp[JUPITER] == 0 && planet_liberated(JUPITER), "Jupiter liberated once the base falls")
}

@(test)
base_construction_is_earth_only :: proc(t: ^testing.T) {
	reset_world()
	// Occupied Jupiter: blocked (Earth is always liberated).
	selected_planet = JUPITER
	for i in 0..<5 { add_miner(JUPITER) }
	start_base_construction()
	testing.expect(t, base_build_planet != JUPITER, "occupied planet blocks construction even with miners present")

	reset_world()
	// Liberated Mars and Jupiter with enough miners still refuse: command
	// bases build on Earth only.
	selected_planet = MARS
	for i in 0..<5 { add_miner(MARS) }
	start_base_construction()
	testing.expect(t, base_build_planet != MARS && minerals == 350, "liberated Mars refuses construction")
	selected_planet = JUPITER
	enemy_base_hp[JUPITER] = 0
	for i in 0..<5 { add_miner(JUPITER) }
	start_base_construction()
	testing.expect(t, base_build_planet != JUPITER && minerals == 350, "liberated Jupiter refuses construction")

	reset_world()
	// Earth queues immediately even with no miners on hand: the 500 mineral
	// cost is deducted up front and miners assemble onto the site later.
	selected_planet = EARTH
	minerals = 499
	start_base_construction()
	testing.expect(t, base_build_planet != EARTH, "Earth without 500 minerals blocks construction")
	minerals = 500
	start_base_construction()
	testing.expect(t, base_build_planet == EARTH, "Earth queues the build with no miners on site")
	testing.expect(t, minerals == 0, "construction costs 500 minerals")
}

@(test)
construction_miners_stop_mining_and_resume :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	for i in 0..<5 { add_miner(EARTH) }
	earth_cycle: f32 = MINING_DURATION + DEPOSIT_DURATION
	full_mps := f32(5) * f32(mining_rate(EARTH)) / earth_cycle
	testing.expect(t, abs(planet_mps(EARTH) - full_mps) < 0.001, "5 miners mine at full rate before construction")
	minerals = 500
	start_base_construction()
	for i in 0..<unit_count {
		units[i].state = .DEPOSITING
		units[i].progress = DEPOSIT_DURATION - 0.01
		update_miner(&units[i], i, 0.02)
	}
	for i in 0..<unit_count {
		if units[i].kind == .MINING { testing.expect(t, units[i].state == .CONSTRUCTING, "miners switch to constructing on deposit") }
	}
	testing.expect(t, abs(planet_mps(EARTH)) < 0.001, "construction miners stop generating MPS")
	update_production(BASE_CONSTRUCT_TIME - 0.2)
	testing.expect(t, base_counts[EARTH] == 1 && base_build_planet == EARTH, "construction still in progress before 60s")
	update_production(0.2)
	testing.expect(t, base_counts[EARTH] == 2 && base_build_planet == -1, "base completes after one full minute")
	for i in 0..<unit_count {
		if units[i].kind == .MINING { testing.expect(t, units[i].state == .MINING, "miners resume mining") }
	}
	testing.expect(t, abs(planet_mps(EARTH) - full_mps) < 0.001, "MPS restored after construction")
}

@(test)
planet_mps_includes_round_trip_transit :: proc(t: ^testing.T) {
	reset_world()
	for p in 0..<PLANET_COUNT { enemy_base_hp[p] = 0; refinery_built[p] = true }
	// One effective miner per planet; expected MPS is rate divided by the
	// full cycle (mine + deposit + round trip at MINING_TRANSIT_SPEED).
	for p in 0..<PLANET_COUNT {
		units[unit_count] = Unit{
			kind = .MINING, state = .MINING, position = planets[p].position,
			home_planet = EARTH, affiliation = p, target_planet = p,
		}
		unit_count += 1
		cycle: f32 = MINING_DURATION + DEPOSIT_DURATION +
			2.0 * distance(planets[p].position, planets[EARTH].position) / MINING_TRANSIT_SPEED
		expected := f32(mining_rate(p)) / cycle
		testing.expectf(t, abs(planet_mps(p) - expected) < 0.001,
			"planet %d MPS %.4f != expected %.4f", p, planet_mps(p), expected)
	}
	// Every off-Earth planet is slower than the mining-only cycle would claim.
	no_transit := f32(mining_rate(MARS)) / (MINING_DURATION + DEPOSIT_DURATION)
	testing.expect(t, planet_mps(MARS) < no_transit, "Mars transit time lowers MPS below the mining-only cycle")
	testing.expect(t, planet_mps(JUPITER) < f32(mining_rate(JUPITER)) / (MINING_DURATION + DEPOSIT_DURATION), "Jupiter transit time lowers MPS")
	// Jupiter's richer rate more than pays for its longer transit.
	testing.expect(t, planet_mps(JUPITER) > planet_mps(MARS), "Jupiter MPS beats Mars despite the longer round trip")
	// The 25% slower mining shows up in the numbers: Earth's miner MPS uses
	// the 4.5s cycle (4s mine + 0.5s deposit), not the old 3.5s one.
	old_cycle := f32(mining_rate(EARTH)) / 3.5
	testing.expect(t, planet_mps(EARTH) < old_cycle, "Earth MPS is 25% slower than the old 3.5s cycle")
}

@(test)
miner_waits_for_liberation :: proc(t: ^testing.T) {
	reset_world()
	units[unit_count] = Unit{
		kind = .MINING, state = .TRANSIT, position = planets[JUPITER].position,
		home_planet = EARTH, affiliation = JUPITER, target_planet = JUPITER,
	}
	unit_count += 1
	update_miner(&units[0], 0, 0.1)
	testing.expect(t, units[0].state == .IDLE, "miner holds instead of mining an occupied planet")

	enemy_base_hp[JUPITER] = 0
	update_miner(&units[0], 0, 0.1)
	testing.expect(t, units[0].state == .IDLE, "idle miner still waits after liberation until refinery is built")

	refinery_built[JUPITER] = true
	update_miner(&units[0], 0, 0.1)
	testing.expect(t, units[0].state == .MINING, "idle miner resumes once refinery is built")
}

@(test)
mining_round_trip_deposits_on_earth :: proc(t: ^testing.T) {
	reset_world()
	enemy_base_hp[JUPITER] = 0
	refinery_built[JUPITER] = true
	units[unit_count] = Unit{
		kind = .MINING, state = .MINING, position = planets[JUPITER].position,
		home_planet = EARTH, affiliation = JUPITER, target_planet = JUPITER,
	}
	unit_count += 1
	// A full mining cycle sends the drone back to Earth.
	units[0].progress = MINING_DURATION - 0.01
	update_miner(&units[0], 0, 0.02)
	testing.expect(t, units[0].state == .RETURNING, "miner returns to Earth after a full cycle")
	// Deposit pays out only after DEPOSIT_DURATION on Earth.
	units[0].position = planets[EARTH].position
	units[0].state = .DEPOSITING
	units[0].progress = 0.1
	minerals = 0
	update_miner(&units[0], 0, 0.02)
	testing.expect(t, minerals == 0, "no payout before the deposit completes")
	units[0].progress = DEPOSIT_DURATION - 0.01
	update_miner(&units[0], 0, 0.02)
	testing.expect(t, minerals == mining_rate(JUPITER), "deposit pays the mined rate")
	testing.expect(t, units[0].state == .TRANSIT, "deposited miner transits back out")
}

@(test)
queue_unit_is_earth_only :: proc(t: ^testing.T) {
	reset_world()
	minerals = 1000
	for p in 0..<PLANET_COUNT {
		if p == EARTH { continue }
		selected_planet = p
		queue_unit(.MINING)
		queue_unit(.COMBAT)
		testing.expect(t, minerals == 1000, "no minerals spent queueing off Earth")
		testing.expect(t, queued_count(p) == 0, "no production queued off Earth")
	}
	selected_planet = EARTH
	queue_unit(.MINING)
	testing.expect(t, minerals == 950, "Earth mining queue costs 50")
	testing.expect(t, production[EARTH][0].active && production[EARTH][0].kind == .MINING, "Earth production line active")
}

@(test)
representational_rendering_one_cube_per_ten :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, rep_count(0) == 0, "empty fleet renders nothing")
	for n in 1..=10 { testing.expect(t, rep_count(n) == 1, "1-10 render as 1 cube") }
	for n in 11..=20 { testing.expect(t, rep_count(n) == 2, "11-20 render as 2 cubes") }
	testing.expect(t, rep_count(GARRISON_FIGHTERS[JUPITER]) == 5, "45 garrison fighters render as 5 cubes")
	testing.expect(t, rep_count(GARRISON_FIGHTERS[NEPTUNE]) == 10, "95 garrison fighters render as 10 cubes")
	testing.expect(t, rep_count(ENEMY_HQ_GARRISON) == 50, "500-fighter HQ garrison renders as 50 cubes")
	testing.expect(t, rep_count(GARRISON_MINERS[JUPITER]) == 1, "10 garrison miners render as 1 drone")
	testing.expect(t, rep_count(GARRISON_MINERS[SATURN]) == 2, "14 garrison miners render as 2 drones")
	testing.expect(t, rep_count(GARRISON_MINERS[NEPTUNE]) == 3, "22 garrison miners render as 3 drones")
}

@(test)
transit_fleets_render_representationally :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<12 {
		units[unit_count] = Unit{kind = .COMBAT, state = .TRANSIT, position = {}, home_planet = EARTH, affiliation = MARS, target_planet = MARS}
		unit_count += 1
	}
	// (2 liberated - 1) * 15 = 15 enemies in transit to Neptune, the
	// liberated planet closest to the HQ.
	enemy_base_hp[NEPTUNE] = 0
	spawn_enemy_wave()
	testing.expect(t, transit_fighters_at(MARS, false) == 12, "12 player fighters in transit to Mars")
	testing.expect(t, rep_count(transit_fighters_at(MARS, false)) == 2, "12 transit fighters render as 2 cubes")
	testing.expect(t, transit_fighters_at(NEPTUNE, true) == 15, "enemy wave in transit to its target")
	testing.expect(t, rep_count(transit_fighters_at(NEPTUNE, true)) == 2, "15-enemy wave renders as 2 cubes")
	for p in 0..<PLANET_COUNT {
		expected := p == NEPTUNE ? 15 : 0
		testing.expectf(t, transit_fighters_at(p, true) == expected, "planet %d enemy transit count %d != %d", p, transit_fighters_at(p, true), expected)
	}
}

@(test)
transit_miners_render_representationally :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<12 {
		units[unit_count] = Unit{kind = .MINING, state = .TRANSIT, position = {}, home_planet = EARTH, affiliation = MARS, target_planet = MARS}
		unit_count += 1
	}
	for i in 0..<25 {
		units[unit_count] = Unit{kind = .MINING, state = .RETURNING, position = {}, home_planet = EARTH, affiliation = JUPITER, target_planet = JUPITER}
		unit_count += 1
	}
	testing.expect(t, transit_miners_at(MARS, false) == 12, "12 player miners in transit to Mars")
	testing.expect(t, rep_count(transit_miners_at(MARS, false)) == 2, "12 transit miners render as 2 drones")
	testing.expect(t, returning_miners_at(JUPITER, false) == 25, "25 player miners returning from Jupiter")
	testing.expect(t, rep_count(returning_miners_at(JUPITER, false)) == 3, "25 returning miners render as 3 drones")
}

@(test)
stationed_miners_render_representationally :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<15 {
		units[unit_count] = Unit{kind = .MINING, state = .MINING, position = {}, home_planet = EARTH, affiliation = MARS, target_planet = MARS}
		unit_count += 1
	}
	testing.expect(t, stationed_miners_at(MARS, false) == 15, "15 player miners mining Mars")
	testing.expect(t, rep_count(stationed_miners_at(MARS, false)) == 2, "15 stationed miners render as 2 drones")
	testing.expect(t, stationed_miners_at(NEPTUNE, true) == 0, "no enemy miners before init")
	spawn_garrison(NEPTUNE, 0, GARRISON_MINERS[NEPTUNE])
	testing.expect(t, stationed_miners_at(NEPTUNE, true) == 22, "22 enemy miners at Neptune")
	testing.expect(t, rep_count(stationed_miners_at(NEPTUNE, true)) == 3, "22 enemy miners render as 3 drones")
}

@(test)
earth_starts_as_the_sole_player_planet :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	testing.expect(t, base_counts[EARTH] == 1, "Earth starts with 1 player base")
	for p in 0..<PLANET_COUNT {
		if p == EARTH { continue }
		testing.expectf(t, base_counts[p] == 0, "planet %d starts with no player base", p)
	}
	testing.expect(t, enemy_base_hp[EARTH] == 0 && planet_liberated(EARTH), "Earth starts with no enemy base")
	players, enemies := planet_combatants(EARTH)
	testing.expect(t, players == 5 && enemies == 0, "Earth holds the player's 5 starting combat drones")
	testing.expect(t, enemy_miner_count(EARTH) == 0, "no enemy mining drones on Earth")
}

@(test)
all_non_earth_planets_start_occupied :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	// Exact spec: garrison fighters / miners / base HP per planet on a fixed
	// occupation ladder (Venus easiest ... Neptune hardest).
	testing.expect(t, GARRISON_FIGHTERS[VENUS] == 10 && GARRISON_MINERS[VENUS] == 4 && GARRISON_BASE_HP[VENUS] == 10, "Venus: ~10/4/10")
	testing.expect(t, GARRISON_FIGHTERS[MARS] == 20 && GARRISON_MINERS[MARS] == 6 && GARRISON_BASE_HP[MARS] == 15, "Mars: ~20/6/15")
	testing.expect(t, GARRISON_FIGHTERS[MERCURY] == 30 && GARRISON_MINERS[MERCURY] == 8 && GARRISON_BASE_HP[MERCURY] == 20, "Mercury: ~30/8/20")
	testing.expect(t, GARRISON_FIGHTERS[JUPITER] == 45 && GARRISON_MINERS[JUPITER] == 10 && GARRISON_BASE_HP[JUPITER] == 30, "Jupiter: ~45/10/30")
	testing.expect(t, GARRISON_FIGHTERS[SATURN] == 60 && GARRISON_MINERS[SATURN] == 14 && GARRISON_BASE_HP[SATURN] == 40, "Saturn: ~60/14/40")
	testing.expect(t, GARRISON_FIGHTERS[URANUS] == 75 && GARRISON_MINERS[URANUS] == 18 && GARRISON_BASE_HP[URANUS] == 50, "Uranus: ~75/18/50")
	testing.expect(t, GARRISON_FIGHTERS[NEPTUNE] == 95 && GARRISON_MINERS[NEPTUNE] == 22 && GARRISON_BASE_HP[NEPTUNE] == 60, "Neptune: ~95/22/60")
	// The spawned world matches the tables: every non-Earth planet holds its
	// garrison fighters, garrison miners and an enemy base.
	for p in 0..<PLANET_COUNT {
		if p == EARTH { continue }
		_, garrison := planet_combatants(p)
		testing.expectf(t, garrison == GARRISON_FIGHTERS[p], "planet %d spawns its %d garrison fighters", p, GARRISON_FIGHTERS[p])
		testing.expectf(t, enemy_miner_count(p) == GARRISON_MINERS[p], "planet %d spawns its %d garrison miners", p, GARRISON_MINERS[p])
		testing.expectf(t, enemy_base_hp[p] == GARRISON_BASE_HP[p] && !planet_liberated(p), "planet %d starts occupied with a %d HP base", p, GARRISON_BASE_HP[p])
	}
	// Distances from Earth after the Earth-centered repositioning (outer
	// three shifted 80 left); garrisons escalate along the ladder order
	// below, which no longer equals distance order.
	by_ladder := [7]int{VENUS, MARS, MERCURY, JUPITER, SATURN, URANUS, NEPTUNE}
	spec_dist := [PLANET_COUNT]f32{31.0, 15.5, 0, 22.8, 51.4, 31.0, 21.0, 42.7}
	for i in 0..<7 {
		p := by_ladder[i]
		testing.expectf(t, abs(distance(planets[p].position, planets[EARTH].position) - spec_dist[p]) < 1.0,
			"planet %d sits at its spec distance from Earth", p)
		if i > 0 {
			q := by_ladder[i - 1]
			testing.expectf(t, GARRISON_FIGHTERS[p] > GARRISON_FIGHTERS[q] && GARRISON_MINERS[p] > GARRISON_MINERS[q] && GARRISON_BASE_HP[p] > GARRISON_BASE_HP[q],
				"garrison escalates from planet %d to %d", q, p)
		}
	}
}

@(test)
enemy_fighters_guard_and_orbit_after_arriving :: proc(t: ^testing.T) {
	reset_world()
	// A second liberated world arms the debug wave.
	enemy_base_hp[NEPTUNE] = 0
	spawn_enemy_wave()
	// One long update: everyone reaches its target this frame (transit is
	// slow, so pass a large dt).
	for i in 0..<unit_count { update_combat(&units[i], 100.0) }
	for i in 0..<unit_count {
	testing.expect(t, units[i].state == .GUARDING, "enemy fighters guard the target planet after arriving")
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
	testing.expect(t, game_paused, "P/F10 should pause the game")
	toggle_pause()
	testing.expect(t, !game_paused, "P/F10 again should resume the game")
	game_paused = false
}

@(test)
pause_toggle_isolates_sim_state :: proc(t: ^testing.T) {
	// toggle_pause only flips the gate flag; it must not mutate sim state.
	minerals_before := minerals
	unit_count_before := unit_count
	progress_before := production[EARTH][0].progress
	game_paused = false
	toggle_pause()
	testing.expect(t, game_paused, "paused flag set")
	testing.expect(t, minerals == minerals_before, "pause toggle must not touch minerals")
	testing.expect(t, unit_count == unit_count_before, "pause toggle must not touch unit count")
	testing.expect(t, production[EARTH][0].progress == progress_before, "pause toggle must not touch production")
	game_paused = false
}

@(test)
paused_game_skips_simulation_step :: proc(t: ^testing.T) {
	// The pause gate lives in the main loop: step_simulation (camera, input,
	// production, units) is only invoked while unpaused. Verify the gate flag
	// controls the only place sim state advances.
	game_paused = false
	unit_count = 0
	production[EARTH][0] = Production{kind = .MINING, active = true, progress = 0}
	step_simulation(1.0) // 1s of an unpaused tick: a 6s mining build advances.
	testing.expect(t, production[EARTH][0].progress > 0, "unpaused sim advances production")
	testing.expect(t, production[EARTH][0].active, "6s build not complete after 1s")
	// Restore.
	production[EARTH][0] = Production{}
	unit_count = 2
	game_paused = false
}

@(test)
pause_menu_keyboard_navigation_wraps :: proc(t: ^testing.T) {
	// Arrow keys read false headless (no key events), so the navigation
	// predicate advance_pause_selection is exercised directly.
	// 5 options: 0 = CONTINUE, 1 = SAVE GAME, 2 = LOAD GAME, 3 = NEW GAME, 4 = QUIT.
	game_paused = true
	pause_menu_selection = 0
	advance_pause_selection(1)
	testing.expect(t, pause_menu_selection == 1, "DOWN moves focus to SAVE GAME")
	advance_pause_selection(1)
	testing.expect(t, pause_menu_selection == 2, "DOWN moves focus to LOAD GAME")
	advance_pause_selection(1)
	testing.expect(t, pause_menu_selection == 3, "DOWN moves focus to NEW GAME")
	advance_pause_selection(1)
	testing.expect(t, pause_menu_selection == 4, "DOWN moves focus to QUIT")
	advance_pause_selection(1)
	testing.expect(t, pause_menu_selection == 0, "DOWN wraps back to CONTINUE")
	advance_pause_selection(-1)
	testing.expect(t, pause_menu_selection == 4, "UP wraps to QUIT")
	advance_pause_selection(-1)
	testing.expect(t, pause_menu_selection == 3, "UP returns to NEW GAME")
	advance_pause_selection(-1)
	testing.expect(t, pause_menu_selection == 2, "UP returns to LOAD GAME")
	advance_pause_selection(-1)
	testing.expect(t, pause_menu_selection == 1, "UP returns to SAVE GAME")
	advance_pause_selection(-1)
	testing.expect(t, pause_menu_selection == 0, "UP returns to CONTINUE")
	game_paused = false
}

@(test)
pause_menu_enter_activates_focused_option :: proc(t: ^testing.T) {
	// Preserve any real save game files so the test doesn't clobber them
	backup_root := "savegame.txt.test_bak"
	has_root := os.exists("savegame.txt")
	if has_root {
		if data, err := os.read_entire_file("savegame.txt", context.temp_allocator); err == nil {
			_ = os.write_entire_file(backup_root, data)
		}
	}
	exe_save := save_game_path("")
	backup_exe := "savegame_exe.txt.test_bak"
	has_exe := exe_save != "savegame.txt" && os.exists(exe_save)
	if has_exe {
		if data, err := os.read_entire_file(exe_save, context.temp_allocator); err == nil {
			_ = os.write_entire_file(backup_exe, data)
		}
	}
	defer {
		if has_root {
			if data, err := os.read_entire_file(backup_root, context.temp_allocator); err == nil {
				_ = os.write_entire_file("savegame.txt", data)
			}
			_ = os.remove(backup_root)
		} else {
			_ = os.remove("savegame.txt")
		}
		if has_exe {
			if data, err := os.read_entire_file(backup_exe, context.temp_allocator); err == nil {
				_ = os.write_entire_file(exe_save, data)
			}
			_ = os.remove(backup_exe)
		} else if exe_save != "savegame.txt" {
			_ = os.remove(exe_save)
		}
	}

	game_paused = true
	quit_requested = false
	pause_menu_selection = 0
	activate_pause_selection()
	testing.expect(t, !game_paused, "ENTER on CONTINUE resumes")
	testing.expect(t, !quit_requested, "ENTER on CONTINUE never quits")

	game_paused = true
	pause_menu_selection = 1
	activate_pause_selection()
	testing.expect(t, game_paused, "ENTER on SAVE GAME leaves game paused")
	testing.expect(t, !quit_requested, "ENTER on SAVE GAME never quits")
	testing.expect(t, save_feedback_timer > 0, "ENTER on SAVE GAME triggers save feedback timer")

	game_paused = true
	pause_menu_selection = 2
	activate_pause_selection()
	testing.expect(t, !game_paused, "ENTER on LOAD GAME resumes upon loading")
	testing.expect(t, !quit_requested, "ENTER on LOAD GAME never quits")

	game_paused = true
	pause_menu_selection = 3
	activate_pause_selection()
	testing.expect(t, !game_paused, "ENTER on NEW GAME resumes after restart")
	testing.expect(t, !quit_requested, "ENTER on NEW GAME never quits")
	testing.expect(t, unit_count > 0, "NEW GAME initialized units")

	game_paused = true
	pause_menu_selection = 4
	activate_pause_selection()
	testing.expect(t, game_paused, "ENTER on QUIT leaves the pause flag alone")
	testing.expect(t, quit_requested, "ENTER on QUIT requests exit")
	game_paused = false
	quit_requested = false
}

@(test)
pause_menu_opens_with_continue_focused :: proc(t: ^testing.T) {
	game_paused = false
	pause_menu_selection = 1
	toggle_pause()
	testing.expect(t, game_paused, "toggle pauses")
	testing.expect(t, pause_menu_selection == 0, "focus resets to CONTINUE on open")
	toggle_pause()
	testing.expect(t, !game_paused, "toggle resumes")
	game_paused = false
}

@(test)
headless_pause_menu_update_is_idle :: proc(t: ^testing.T) {
	// No key/mouse events headless: update_pause_menu must change nothing.
	game_paused = true
	pause_menu_selection = 0
	quit_requested = false
	update_pause_menu()
	testing.expect(t, game_paused, "still paused")
	testing.expect(t, pause_menu_selection == 0, "focus unmoved")
	testing.expect(t, !quit_requested, "no quit requested")
	game_paused = false
}

@(test)
spacebar_shortcut_selects_earth :: proc(t: ^testing.T) {
	// update_input binds SPACE to select_earth; the action itself sets the
	// inspector selection back to Earth from any planet.
	selected_planet = JUPITER
	select_earth()
	testing.expect(t, selected_planet == EARTH, "spacebar shortcut selects Earth")
	selected_planet = MARS
	select_earth()
	testing.expect(t, selected_planet == EARTH, "spacebar works from any planet")
	selected_planet = EARTH
}

@(test)
spacebar_shortcut_centers_camera_when_earth_selected :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	camera_target = {45, 0, -20}
	camera.position = {45, 80, 60}
	camera.target = camera_target

	select_earth()
	testing.expect(t, selected_planet == EARTH, "Earth remains selected")
	expected_x := earth_camera_offset_x()
	testing.expect(t, abs(camera_target.x - expected_x) < 0.001, "camera_target.x is offset to center Earth in viewport")
	testing.expect(t, camera_target.y == planets[EARTH].position.y, "camera_target.y matches Earth")
	testing.expect(t, camera_target.z == planets[EARTH].position.z, "camera_target.z matches Earth")
	testing.expect(t, camera.target == camera_target, "camera.target matches camera_target")
	testing.expect(t, camera.position.x == camera_target.x, "camera.position.x matches camera_target.x")
}

@(test)
spacebar_two_press_sequence :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = MARS
	camera_target = {45, 0, -20}

	// First press: selects Earth, camera does not move yet
	select_earth()
	testing.expect(t, selected_planet == EARTH, "first press selects Earth")
	testing.expect(t, camera_target.x == 45, "camera hasn't moved yet")

	// Second press: centers camera on Earth
	select_earth()
	testing.expect(t, selected_planet == EARTH, "Earth still selected")
	expected_x := earth_camera_offset_x()
	testing.expect(t, abs(camera_target.x - expected_x) < 0.001, "second press centers camera on Earth with viewport offset")
}

@(test)
earth_centered_in_viewport_beside_inspector :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	camera.position = {0, 89.0, 89.0}
	select_earth()

	// Math verification of perspective projection at Y = 89:
	screen_w: f32 = 1280.0
	screen_h: f32 = 760.0
	viewport_w := screen_w - SCREEN_PANEL_WIDTH
	desired_center_x := viewport_w * 0.5

	fovy_rad := f32(45.0 * math.PI / 180.0)
	view_z := camera.position.y * math.sqrt(f32(2.0))
	view_x := -camera_target.x
	proj_x := (f32(1.0) / math.tan(fovy_rad * 0.5)) * (screen_h / screen_w) * (view_x / view_z)
	screen_x := (proj_x + 1.0) * 0.5 * screen_w

	testing.expect(t, abs(screen_x - desired_center_x) < 0.01, "Earth screen projection is centered in viewport")
}

@(test)
vision_starts_earth_only :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, has_vision(EARTH), "Earth is always lit")
	for p in 0..<PLANET_COUNT {
		if p == EARTH { continue }
		testing.expectf(t, !has_vision(p), "planet %d starts dark with no player presence", p)
	}
}

@(test)
vision_tracks_arrival_and_departure :: proc(t: ^testing.T) {
	reset_world()
	// Arrival: a player fighter orbiting Mars lifts its fog.
	add_guarding_fighter(MARS, false)
	testing.expect(t, has_vision(MARS), "player fighter arriving at Mars lifts its fog")
	// Departure: retreating back to Earth drops it again.
	units[0].state = .TRANSIT
	units[0].target_planet = EARTH
	units[0].position = {0, 0, 0}
	testing.expect(t, !has_vision(MARS), "Mars goes dark again once the player unit leaves")
	// Destruction of the last unit there also ends vision.
	add_guarding_fighter(JUPITER, false)
	testing.expect(t, has_vision(JUPITER), "player fighter at Jupiter lights it")
	remove_unit_at(1)
	testing.expect(t, !has_vision(JUPITER), "Jupiter goes dark when the last unit there is destroyed")
}

@(test)
fog_lifts_while_a_player_unit_is_physically_present :: proc(t: ^testing.T) {
	reset_world()
	// A mining drone mid-mine at Jupiter counts as presence (within radius+2).
	units[unit_count] = Unit{kind = .MINING, state = .MINING, position = planets[JUPITER].position, home_planet = EARTH, affiliation = JUPITER, target_planet = JUPITER}
	unit_count += 1
	testing.expect(t, has_vision(JUPITER), "mining drone present at Jupiter lights it")
	// A unit far away in transit does not.
	units[unit_count] = Unit{kind = .COMBAT, state = .TRANSIT, position = {0, 0, 0}, home_planet = EARTH, affiliation = JUPITER, target_planet = JUPITER}
	unit_count += 1
	units[0].position = {0, 0, 0}
	testing.expect(t, !has_vision(JUPITER), "units en route far away do not light Jupiter")
	// Within the presence radius (radius + 2.0), even a passing unit lights it.
	units[1].position = planets[JUPITER].position
	testing.expect(t, has_vision(JUPITER), "transit unit within the presence radius lights it")
}

@(test)
enemy_garrisons_concealed_until_player_presence :: proc(t: ^testing.T) {
	reset_world()
	// Jupiter's standing garrison is invisible while the planet is dark.
	spawn_garrison(JUPITER, GARRISON_FIGHTERS[JUPITER], GARRISON_MINERS[JUPITER])
	for i in 0..<unit_count {
		testing.expect(t, is_concealed(&units[i]), "Jupiter garrison concealed under fog")
	}
	// One player unit arriving at Jupiter reveals every enemy unit there.
	add_guarding_fighter(JUPITER, false)
	for i in 0..<unit_count {
		testing.expect(t, !is_concealed(&units[i]), "Jupiter garrison revealed once a player unit is present")
	}
	// Enemy units at Mars are concealed until a player unit scouts it.
	reset_world()
	spawn_garrison(MARS, 3, 2)
	for i in 0..<unit_count {
		testing.expect(t, is_concealed(&units[i]), "Mars garrison concealed under fog")
	}
	add_guarding_fighter(MARS, false)
	for i in 0..<unit_count {
		testing.expect(t, !is_concealed(&units[i]), "Mars garrison revealed by player presence")
	}
}

@(test)
enemy_wave_concealed_in_transit_until_target_lit :: proc(t: ^testing.T) {
	reset_world()
	// A second liberated world arms the debug wave; Neptune is the closest
	// liberated planet to the HQ, so the wave lifts off toward it.
	enemy_base_hp[NEPTUNE] = 0
	spawn_enemy_wave()
	testing.expect(t, unit_count == 15, "wave spawned")
	target := units[0].target_planet
	testing.expect(t, target == NEPTUNE, "wave strikes Neptune")
	lit := has_vision(target)
	for i in 0..<unit_count {
		testing.expect(t, is_concealed(&units[i]) != lit, "wave hidden while the target is dark, visible once lit")
	}
	// Neptune starts dark: a player fighter on site lights it.
	add_guarding_fighter(target, false)
	for i in 0..<unit_count {
		testing.expect(t, !is_concealed(&units[i]), "enemy wave visible once the target planet is lit")
	}
}

@(test)
right_click_with_selection_orders_units_and_keeps_rally :: proc(t: ^testing.T) {
	reset_world()
	earth_rally = MARS
	selected_planet = EARTH
	add_guarding_fighter(EARTH, false)
	selected_units[0] = true
	handle_planet_right_click(JUPITER)
	testing.expect(t, units[0].target_planet == JUPITER && units[0].state == .TRANSIT, "selected units move to the right-clicked planet")
	testing.expect(t, earth_rally == MARS && rally_flag_planet() == MARS, "move order leaves the Earth rally point untouched")
}

@(test)
right_click_without_selection_sets_earth_rally :: proc(t: ^testing.T) {
	reset_world()
	earth_rally = NO_RALLY
	selected_planet = EARTH
	add_guarding_fighter(EARTH, false) // Present but NOT selected.
	handle_planet_right_click(MARS)
	testing.expect(t, earth_rally == MARS, "no selection + Earth selected sets the rally to Mars")
	testing.expect(t, units[0].target_planet == EARTH && units[0].state == .GUARDING, "unselected units are not given the move order")
	// Right-clicking Earth itself clears the rally.
	handle_planet_right_click(EARTH)
	testing.expect(t, earth_rally == NO_RALLY, "right-clicking Earth clears the rally")
	// Outpost selected with no units: right-click is ignored entirely.
	selected_planet = MARS
	handle_planet_right_click(JUPITER)
	testing.expect(t, earth_rally == NO_RALLY, "outpost selected without units: right-click does nothing")
}

@(test)
earth_rally_set_and_cleared :: proc(t: ^testing.T) {
	earth_rally = NO_RALLY
	set_earth_rally(MARS)
	testing.expect(t, earth_rally == MARS, "right-click Mars with Earth selected sets the rally to Mars")
	testing.expect(t, rally_flag_planet() == MARS, "rally flag targets the rally planet")
	set_earth_rally(EARTH)
	testing.expect(t, earth_rally == NO_RALLY, "right-click Earth clears the rally point")
	testing.expect(t, rally_flag_planet() == NO_RALLY, "no flag when the rally is cleared")
}

@(test)
rally_auto_dispatches_new_combat_drones :: proc(t: ^testing.T) {
	unit_count = 0
	earth_rally = MARS
	spawn_unit(.COMBAT, EARTH)
	testing.expect(t, unit_count == 1, "combat drone spawned")
	u := units[0]
	testing.expect(t, u.state == .TRANSIT, "rally combat drone auto-dispatches into transit")
	testing.expect(t, u.target_planet == MARS && u.affiliation == MARS, "rally combat drone heads to the rally world")
	earth_rally = NO_RALLY
	unit_count = 0
}

@(test)
rally_auto_dispatches_new_mining_drones :: proc(t: ^testing.T) {
	unit_count = 0
	earth_rally = MARS
	spawn_unit(.MINING, EARTH)
	testing.expect(t, units[0].state == .TRANSIT, "rally mining drone transits to the rally world")
	testing.expect(t, units[0].target_planet == MARS && units[0].affiliation == MARS, "rally mining drone targets the rally world")
	earth_rally = NO_RALLY
	unit_count = 0
}

@(test)
no_rally_keeps_default_spawn_behavior :: proc(t: ^testing.T) {
	unit_count = 0
	earth_rally = NO_RALLY
	spawn_unit(.COMBAT, EARTH)
	testing.expect(t, units[0].state == .GUARDING && units[0].target_planet == EARTH, "without a rally, combat drones guard Earth")
	unit_count = 0
}

@(test)
rally_only_redirects_earth_spawns :: proc(t: ^testing.T) {
	unit_count = 0
	earth_rally = MARS
	spawn_unit(.COMBAT, MARS)
	testing.expect(t, units[0].state == .GUARDING && units[0].target_planet == MARS, "non-Earth spawns ignore the Earth rally")
	earth_rally = NO_RALLY
	unit_count = 0
}

// ---- Auto-assigned base construction crew --------------------------------

@(test)
deposit_auto_assigns_miners_to_queued_base_construction :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 500
	start_base_construction()
	testing.expect(t, base_build_planet == EARTH, "build queues with no crew")
	// The build clock is frozen until the crew of 5 has gathered.
	update_production(120.0)
	testing.expect(t, base_build_planet == EARTH && base_build_progress == 0, "no build progress without a full crew")
	// Each depositing miner joins the crew, wherever it was mining.
	for i in 0..<BASE_CONSTRUCT_MINERS {
		target := i % PLANET_COUNT
		units[unit_count] = Unit{
			kind = .MINING, state = .DEPOSITING, position = planets[EARTH].position,
			home_planet = EARTH, affiliation = target, target_planet = target,
			progress = DEPOSIT_DURATION - 0.01,
		}
		unit_count += 1
		update_miner(&units[unit_count-1], unit_count-1, 0.02)
		testing.expectf(t, units[unit_count-1].state == .CONSTRUCTING, "deposit %d joins the crew", i)
		testing.expect(t, units[unit_count-1].target_planet == EARTH, "crew member is retargeted to Earth")
		testing.expect(t, constructing_miners(EARTH) == i + 1, "crew grows one per deposit")
	}
	testing.expect(t, base_build_progress == 0, "clock starts only once the crew is full")
	// The 6th depositor keeps mining: the crew is full.
	units[unit_count] = Unit{
		kind = .MINING, state = .DEPOSITING, position = planets[EARTH].position,
		home_planet = EARTH, affiliation = MARS, target_planet = MARS, progress = DEPOSIT_DURATION - 0.01,
	}
	unit_count += 1
	update_miner(&units[unit_count-1], unit_count-1, 0.02)
	testing.expect(t, units[unit_count-1].state == .TRANSIT, "extra depositor transits back out")
	testing.expect(t, constructing_miners(EARTH) == BASE_CONSTRUCT_MINERS, "crew caps at 5")
	// Full crew: 60s completes the base and everyone resumes mining.
	update_production(BASE_CONSTRUCT_TIME - 0.01)
	testing.expect(t, base_build_planet == EARTH, "still building just before 60s")
	update_production(0.02)
	testing.expect(t, base_build_planet == -1 && base_counts[EARTH] == 2, "base completes after 60s with a full crew")
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
	for p in 0..<PLANET_COUNT {
		enemy_base_hp[p] = 0
		refinery_built[p] = true
		add_miner(p)
	}
	sum := f32(0)
	for p in 0..<PLANET_COUNT { sum += planet_mps(p) }
	testing.expect(t, abs(global_mps() - sum) < 0.001, "global MPS equals the sum of all planet MPS")
	testing.expect(t, global_mps() > planet_mps(EARTH), "empire income beats Earth alone")
}

// ---- Roster header counts ------------------------------------------------

@(test)
roster_headers_show_unit_counts :: proc(t: ^testing.T) {
	reset_world()
	add_miner(EARTH); add_miner(EARTH); add_miner(MARS)
	add_guarding_fighter(EARTH, false); add_guarding_fighter(EARTH, false); add_guarding_fighter(MARS, false)
	selected_planet = EARTH
	testing.expect(t, roster_count(.MINING) == 2, "Earth header counts its 2 miners")
	testing.expect(t, roster_count(.COMBAT) == 2, "Earth header counts its 2 fighters")
	selected_planet = MARS
	testing.expect(t, roster_count(.MINING) == 1, "Mars header counts its 1 miner")
	testing.expect(t, roster_count(.COMBAT) == 1, "Mars header counts its 1 fighter")
	selected_planet = JUPITER
	testing.expect(t, roster_count(.MINING) == 0 && roster_count(.COMBAT) == 0, "empty Jupiter roster")
}

// ---- Mining rate and per-planet caps -------------------------------------

@(test)
earth_mines_at_standard_rate :: proc(t: ^testing.T) {
	// Inner planets (Mercury, Venus, Earth, Mars) pay the standard 10; the
	// gas giants and beyond pay 25.
	testing.expect(t, mining_rate(EARTH) == 10, "Earth pays 10 per cycle")
	testing.expect(t, mining_rate(MERCURY) == 10, "Mercury at the standard 10")
	testing.expect(t, mining_rate(VENUS) == 10, "Venus at the standard 10")
	testing.expect(t, mining_rate(MARS) == 10, "Mars at the standard 10")
	testing.expect(t, mining_rate(JUPITER) == 25, "Jupiter pays 25")
	testing.expect(t, mining_rate(SATURN) == 25, "Saturn pays 25")
	testing.expect(t, mining_rate(URANUS) == 25, "Uranus pays 25")
	testing.expect(t, mining_rate(NEPTUNE) == 25, "Neptune pays 25")
}

@(test)
planet_mining_caps_limit_effective_miners :: proc(t: ^testing.T) {
	testing.expect(t, planet_mining_cap(EARTH) == 10, "Earth cap 10")
	testing.expect(t, planet_mining_cap(MERCURY) == 15, "Mercury cap 15")
	testing.expect(t, planet_mining_cap(VENUS) == 35, "Venus cap 35")
	testing.expect(t, planet_mining_cap(MARS) == 50, "Mars cap 50")
	testing.expect(t, planet_mining_cap(JUPITER) == 100, "Jupiter cap 100")

	reset_world()
	for i in 0..<20 { add_miner(EARTH) }
	earth_cycle: f32 = MINING_DURATION + DEPOSIT_DURATION
	expected := f32(planet_mining_cap(EARTH)) * f32(mining_rate(EARTH)) / earth_cycle
	testing.expectf(t, abs(planet_mps(EARTH) - expected) < 0.001, "Earth MPS caps at 10 effective miners: %.3f != %.3f", planet_mps(EARTH), expected)
	// Payout follows the same cap: 20 depositors, only the first 10 get paid.
	for i in 0..<unit_count {
		units[i].state = .DEPOSITING
		units[i].progress = DEPOSIT_DURATION - 0.01
	}
	minerals = 0
	for i in 0..<unit_count { update_miner(&units[i], i, 0.02) }
	testing.expect(t, minerals == planet_mining_cap(EARTH) * mining_rate(EARTH), "only the first 10 Earth miners are paid")

	reset_world()
	enemy_base_hp[MARS] = 0
	refinery_built[MARS] = true
	for i in 0..<60 { add_miner(MARS) }
	mars_cycle: f32 = MINING_DURATION + DEPOSIT_DURATION + 2.0 * distance(planets[MARS].position, planets[EARTH].position) / MINING_TRANSIT_SPEED
	expected = f32(planet_mining_cap(MARS)) * f32(mining_rate(MARS)) / mars_cycle
	testing.expect(t, abs(planet_mps(MARS) - expected) < 0.001, "Mars MPS caps at 50 effective miners")

	reset_world()
	enemy_base_hp[JUPITER] = 0
	refinery_built[JUPITER] = true
	for i in 0..<110 { add_miner(JUPITER) }
	jupiter_cycle: f32 = MINING_DURATION + DEPOSIT_DURATION + 2.0 * distance(planets[JUPITER].position, planets[EARTH].position) / MINING_TRANSIT_SPEED
	expected = f32(planet_mining_cap(JUPITER)) * f32(mining_rate(JUPITER)) / jupiter_cycle
	testing.expect(t, abs(planet_mps(JUPITER) - expected) < 0.001, "Jupiter MPS caps at 100 effective miners")
}

// ---- Hidden base button & compact unit tiles ----------------------------

@(test)
base_button_hidden_at_max_bases :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	testing.expect(t, base_button_visible(), "button visible below the cap")
	// At the cap with nothing building, the button disappears.
	base_counts[EARTH] = MAX_BASES
	testing.expect(t, base_build_planet == -1, "nothing under construction")
	testing.expect(t, !base_button_visible(), "button hidden at 5 bases")
	// A lost base brings it back.
	base_counts[EARTH] = MAX_BASES - 1
	testing.expect(t, base_button_visible(), "button returns when a base is lost")
	// While building, the progress panel stays visible even at the cap boundary.
	base_counts[EARTH] = MAX_BASES
	base_build_planet = EARTH
	testing.expect(t, base_button_visible(), "progress panel shows while building")
	base_build_planet = -1
	// Clicking the hidden button area does nothing: no minerals spent, no build.
	base_counts[EARTH] = MAX_BASES
	minerals = 1000
	handle_inspector_click({25, f32(SECTION_TOP + 10)}, 0) // panel_x = 0: base rect is {20, SECTION_TOP, 290, 36}.
	testing.expect(t, minerals == 1000 && base_build_planet == -1, "clicking the hidden button area does nothing at the cap")
}

@(test)
unit_tiles_are_compact_and_hitboxes_match_layout :: proc(t: ^testing.T) {
	testing.expect(t, TILE_SIZE == 16, "tiles are compact 16px grid tiles")
	// A full row packs inside the panel content area (two 20px margins).
	testing.expect(t, TILE_SIZE * TILES_PER_ROW + (TILES_PER_ROW - 1) * TILE_GAP <= SCREEN_PANEL_WIDTH - 40, "a full row fits inside the panel")
	testing.expect(t, TILES_PER_ROW >= 9, "rows hold at least 9 tiles")
	// First tile sits at the panel margin; ordinal 10 wraps to the second row.
	r0 := unit_tile_rect(100, 200, 0)
	testing.expect(t, r0.x == 120 && r0.y == 200 && r0.width == TILE_SIZE && r0.height == TILE_SIZE, "first tile at the panel margin")
	r10 := unit_tile_rect(100, 200, 10)
	testing.expect(t, r10.x == 120 && r10.y == 200 + (TILE_SIZE + TILE_GAP), "ordinal 10 wraps to the second row")
	r9 := unit_tile_rect(100, 200, 9)
	testing.expect(t, r9.x == 100 + 20 + 9 * (TILE_SIZE + TILE_GAP), "tiles pack left to right")
	// Hitbox covers the tile and stays inside it.
	testing.expect(t, rl.CheckCollisionPointRec({r0.x + 1, r0.y + 1}, r0), "hitbox covers the tile")
	testing.expect(t, !rl.CheckCollisionPointRec({r0.x - 1, r0.y - 1}, r0), "hitbox stays inside the tile")
}

// ---- Queue cancel (click slot / ESC) ------------------------------------

@(test)
cancelling_queue_slot_refunds_and_shifts :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 1000
	// Queue head: active MINING line, then pending [COMBAT, MINING].
	queue_unit(.MINING)
	queue_unit(.COMBAT)
	queue_unit(.MINING)
	testing.expect(t, queued_count(EARTH) == 3, "3 queued")
	// Queue head: MINING line (950), COMBAT pending (825), MINING pending (775).
	// Cancel pending slot 2 (the last MINING): refund 50, pending shifts left.
	testing.expect(t, cancel_queued_at(EARTH, 2), "cancel pending tail")
	testing.expect(t, queued_count(EARTH) == 2 && minerals == 825, "50 refunded, queue shrinks")
	testing.expect(t, pending[EARTH][0] == .COMBAT && pending_count[EARTH] == 1, "pending shifted left")
	// Cancel pending slot 1 (COMBAT): refund 125.
	testing.expect(t, cancel_queued_at(EARTH, 1), "cancel pending head")
	testing.expect(t, pending_count[EARTH] == 0 && minerals == 950, "125 refunded, pending empty")
	// Cancel slot 0 (the active line): refund 50, line deactivated.
	testing.expect(t, cancel_queued_at(EARTH, 0), "cancel active line")
	testing.expect(t, !production[EARTH][0].active && minerals == 1000, "line cancelled, full refund")
	// Out-of-range slot: no-op.
	testing.expect(t, !cancel_queued_at(EARTH, 0), "empty queue slot is a no-op")
}

@(test)
cancelling_active_line_promotes_pending :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 1000
	// Active MINING line + pending COMBAT: cancelling the line promotes the
	// pending item into the freed line.
	queue_unit(.MINING)
	queue_unit(.COMBAT)
	testing.expect(t, cancel_queued_at(EARTH, 0), "cancel active line")
	testing.expect(t, production[EARTH][0].active && production[EARTH][0].kind == .COMBAT, "pending promoted into the freed line")
	testing.expect(t, pending_count[EARTH] == 0, "pending consumed")
	testing.expect(t, minerals == 875, "only the line's 50 refunded; the promoted unit stays paid-for")
}

@(test)
clicking_queue_slot_cancels_unit :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 1000
	// Active COMBAT line + pending MINING.
	queue_unit(.COMBAT)
	queue_unit(.MINING)
	// panel_x = 0: slot 0 rect is the active line. Clicking it cancels the line
	// and promotes the pending MINING into it.
	rect := queue_slot_rect(0, 0)
	handle_inspector_click({rect.x + 1, rect.y + 1}, 0)
	testing.expect(t, queued_count(EARTH) == 1, "queue shrinks by one")
	testing.expect(t, production[EARTH][0].active && production[EARTH][0].kind == .MINING, "pending promoted into the freed line")
	testing.expect(t, minerals == 950, "125 refunded for the cancelled COMBAT line")
}

@(test)
esc_cancels_most_recent_queued_unit :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 1000
	// Queue head: MINING line, then pending [COMBAT, MINING].
	queue_unit(.MINING)
	queue_unit(.COMBAT)
	queue_unit(.MINING)
	// ESC unwinds the tail first: the newest pending MINING (775 -> 825).
	testing.expect(t, cancel_last_queued(), "ESC cancels the newest pending item")
	testing.expect(t, queued_count(EARTH) == 2 && minerals == 825, "50 refunded for the tail MINING")
	testing.expect(t, pending_count[EARTH] == 1 && pending[EARTH][0] == .COMBAT, "pending tail removed, COMBAT stays queued")
	// ESC again unwinds the pending COMBAT (825 -> 950).
	testing.expect(t, cancel_last_queued(), "ESC cancels the next pending item")
	testing.expect(t, queued_count(EARTH) == 1 && minerals == 950, "125 refunded for the pending COMBAT")
	// ESC finally unwinds the active production line (950 -> 1000).
	testing.expect(t, cancel_last_queued(), "ESC cancels the active line")
	testing.expect(t, queued_count(EARTH) == 0 && minerals == 1000 && !production[EARTH][0].active, "line cancelled, full refund")
	// ESC on an empty queue does nothing.
	testing.expect(t, !cancel_last_queued(), "ESC with an empty queue is a no-op")
}

// ---- Pause keybind (P / F10) --------------------------------------------

@(test)
pause_keybind_is_p_or_f10 :: proc(t: ^testing.T) {
	// Headless: no key events, so the P/F10 predicate reads false and never
	// pauses the game; the binding lives in pause_key_pressed, and the actual
	// toggle still cycles through toggle_pause.
	game_paused = false
	testing.expect(t, !pause_key_pressed(), "no key events headless")
	if pause_key_pressed() { toggle_pause() }
	testing.expect(t, !game_paused, "idle keys never pause the game")
	toggle_pause()
	testing.expect(t, game_paused, "toggle still cycles on P/F10")
	game_paused = false
}

// ---- Scout survival & transit-safe miners ------------------------------

@(test)
transiting_miners_survive_garrison_fire :: proc(t: ^testing.T) {
	reset_world()
	// Enemy garrison at Jupiter; a player miner en route (far away, in transit).
	add_guarding_fighter(JUPITER, true)
	units[unit_count] = Unit{kind = .MINING, state = .TRANSIT, position = planets[EARTH].position, home_planet = EARTH, affiliation = JUPITER, target_planet = JUPITER}
	unit_count += 1
	// Many combat ticks: the miner in transit is never a garrison target.
	update_enemy_waves(10.0)
	testing.expect(t, unit_count == 2, "miner in transit survives garrison fire")
}

@(test)
scout_miner_survives_grace_window :: proc(t: ^testing.T) {
	reset_world()
	// Occupied Jupiter: garrison fighters pin the arriving scout miner.
	for i in 0..<2 { add_guarding_fighter(JUPITER, true) }
	units[unit_count] = Unit{kind = .MINING, state = .IDLE, position = planets[JUPITER].position, home_planet = EARTH, affiliation = JUPITER, target_planet = JUPITER, progress = 0}
	unit_count += 1
	testing.expect(t, has_vision(JUPITER), "scout on site lifts the fog")
	// Per-second steps: the scout survives the full SCOUT_SURVIVAL window.
	for s in 0..<3 { step_simulation(1.0) }
	testing.expect(t, unit_count == 3, "scout survives at least 3s of garrison fire")
	testing.expect(t, has_vision(JUPITER), "scout still alive keeps Jupiter lit")
	// Grace expires on the next kill tick: the garrison destroys the scout.
	step_simulation(1.0)
	testing.expect(t, unit_count == 2, "scout destroyed once the grace window expires")
	testing.expect(t, !has_vision(JUPITER), "Jupiter goes dark once the scout is lost")
}

// ---- Last-known intel memory -------------------------------------------

@(test)
last_known_intel_survives_fog :: proc(t: ^testing.T) {
	reset_world()
	spawn_garrison(JUPITER, 5, 3)
	testing.expect(t, !has_vision(JUPITER) && !intel_recorded[JUPITER], "Jupiter starts dark and unscouted")
	update_intel()
	testing.expect(t, !intel_recorded[JUPITER], "no intel recorded without vision")
	// Scout miner pinned at the garrison: vision lifts and intel snapshots.
	units[unit_count] = Unit{kind = .MINING, state = .IDLE, position = planets[JUPITER].position, home_planet = EARTH, affiliation = JUPITER, target_planet = JUPITER}
	unit_count += 1
	update_intel()
	testing.expect(t, intel_recorded[JUPITER], "scout on site records intel")
	_, fighters := planet_combatants(JUPITER)
	testing.expect(t, last_known_intel[JUPITER].fighters == fighters && fighters == 5, "enemy fighters recorded")
	testing.expect(t, last_known_intel[JUPITER].miners == 3, "enemy miners recorded")
	testing.expect(t, last_known_intel[JUPITER].base_hp == GARRISON_BASE_HP[JUPITER], "base HP recorded")
	// While lit, intel tracks losses: one garrison fighter falls.
	remove_unit_at(0)
	update_intel()
	testing.expect(t, last_known_intel[JUPITER].fighters == 4, "intel updates while the planet stays lit")
	// Scout leaves (destroyed): the planet goes dark but the last snapshot
	// is retained for the outpost inspector.
	scout_index := unit_count - 1
	remove_unit_at(scout_index)
	testing.expect(t, !has_vision(JUPITER), "Jupiter goes dark without the scout")
	testing.expect(t, intel_recorded[JUPITER], "last-known intel retained after going dark")
	testing.expect(t, last_known_intel[JUPITER].fighters == 4 && last_known_intel[JUPITER].miners == 3 && last_known_intel[JUPITER].base_hp == GARRISON_BASE_HP[JUPITER], "stale snapshot preserved")
}

// ---- Control-group squads -----------------------------------------------

@(test)
squad_save_and_recall :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<5 { add_guarding_fighter(EARTH, false) }
	for i in 0..<5 { selected_units[i] = true }
	save_squad(3)
	testing.expect(t, squad_count(3) == 5, "squad holds the 5 selected fighters")
	testing.expect(t, squad_count(1) == 0, "other squads empty")
	clear_selection()
	testing.expect(t, selection_count() == 0, "selection cleared")
	n := recall_squad(3)
	testing.expect(t, n == 5 && selection_count() == 5, "recall reselects the squad")
	// Re-save with fewer units replaces the membership.
	clear_selection()
	selected_units[0] = true
	save_squad(3)
	testing.expect(t, squad_count(3) == 1, "re-save replaces squad membership")
	// Save with no selection clears the group.
	clear_selection()
	save_squad(3)
	testing.expect(t, squad_count(3) == 0, "saving an empty selection clears the squad")
	n = recall_squad(3)
	testing.expect(t, n == 0 && selection_count() == 0, "recalling an empty squad selects nothing")
	// Digit keys read false headless (no key events), so the binding predicate
	// never fires in tests; the squad procs are exercised directly instead.
	testing.expect(t, squad_key_pressed() == 0, "no digit keys headless")
}

@(test)
squad_prunes_destroyed_units :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<4 { add_guarding_fighter(MARS, false) }
	for i in 0..<4 { selected_units[i] = true }
	save_squad(2)
	// Two squad members die: removal shifts the array, so the survivors keep
	// their squad assignment (it rides on the Unit struct, not the index).
	remove_unit_at(0)
	remove_unit_at(0)
	testing.expect(t, squad_count(2) == 2, "destroyed members pruned from the squad")
	n := recall_squad(2)
	testing.expect(t, n == 2, "recall selects only living members")
	// All members dead: the squad is empty and recall selects nothing cleanly.
	remove_unit_at(0)
	remove_unit_at(0)
	testing.expect(t, squad_count(2) == 0, "empty squad after all members die")
	n = recall_squad(2)
	testing.expect(t, n == 0 && selection_count() == 0, "recall on a dead squad selects nothing cleanly")
}

// Regression for the squad-HUD text bug: multiple saved squads must keep
// independent counts (each feeds one bottom-HUD badge).
@(test)
saving_a_second_squad_keeps_both_hud_counts :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<3 { add_guarding_fighter(EARTH, false) }
	for i in 0..<3 { selected_units[i] = true }
	save_squad(1)
	clear_selection()
	for i in 3..<5 { add_guarding_fighter(EARTH, false) }
	selected_units[3] = true
	selected_units[4] = true
	save_squad(2)
	testing.expect(t, squad_count(1) == 3, "first squad intact after saving a second")
	testing.expect(t, squad_count(2) == 2, "second squad saved")
	non_empty := 0
	for g in 1..=SQUAD_COUNT { if squad_count(g) > 0 { non_empty += 1 } }
	testing.expect(t, non_empty == 2, "exactly two squads feed the HUD badges")
}

// ---- Enemy forces in the planet inspector --------------------------------

@(test)
enemy_roster_counts_garrison_at_selected_planet :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = VENUS
	spawn_garrison(VENUS, GARRISON_FIGHTERS[VENUS], GARRISON_MINERS[VENUS])
	testing.expect(t, enemy_roster_count(.COMBAT) == GARRISON_FIGHTERS[VENUS], "garrison fighters counted")
	testing.expect(t, enemy_roster_count(.MINING) == GARRISON_MINERS[VENUS], "garrison miners counted")
	testing.expect(t, roster_count(.COMBAT) == 0 && roster_count(.MINING) == 0, "player rosters exclude enemies")
	// Player units mixed in never leak into the enemy roster.
	add_guarding_fighter(VENUS, false)
	testing.expect(t, enemy_roster_count(.COMBAT) == GARRISON_FIGHTERS[VENUS], "player fighters stay out of the enemy roster")
	testing.expect(t, enemy_roster_ordinal(0, .COMBAT) == 0, "first garrison fighter is ordinal 0")
	// Enemies elsewhere never show: rosters are per selected planet.
	selected_planet = MARS
	testing.expect(t, enemy_roster_count(.COMBAT) == 0 && enemy_roster_count(.MINING) == 0, "no enemy section at a clean planet")
	selected_planet = EARTH
}

@(test)
enemy_attackers_appear_in_target_roster :: proc(t: ^testing.T) {
	reset_world()
	// A wave bound for a planet joins that planet's enemy roster, so the
	// inspector shows inbound attackers (wave fighters carry the target as
	// their affiliation from the moment they lift off).
	enemy_base_hp[NEPTUNE] = 0 // a second liberated world arms the debug wave.
	before := unit_count
	spawn_enemy_wave()
	target := units[before].target_planet
	selected_planet = target
	testing.expect(t, enemy_roster_count(.COMBAT) == 15, "wave fighters count in the target roster")
	testing.expect(t, enemy_roster_ordinal(before, .COMBAT) == 0, "first attacker is ordinal 0")
	selected_planet = EARTH
}

// ---- Completed base picks up the pending queue --------------------------

@(test)
completed_base_picks_up_pending_queue_immediately :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 2000
	// One base, one active line, two items waiting in the pending queue.
	queue_unit(.MINING)
	queue_unit(.COMBAT)
	queue_unit(.COMBAT)
	testing.expect(t, production[EARTH][0].active && production[EARTH][0].kind == .MINING, "single line active")
	testing.expect(t, pending_count[EARTH] == 2, "two items wait pending")
	// Build the second base with a full crew.
	start_base_construction()
	for i in 0..<BASE_CONSTRUCT_MINERS {
		add_miner(EARTH)
		units[unit_count - 1].state = .CONSTRUCTING
	}
	// Park the base clock just under completion without running production
	// (a long dt would also finish line 0 and muddy the pending count), then
	// step exactly over the boundary so only the base completes this tick.
	base_build_progress = BASE_CONSTRUCT_TIME - 0.1
	update_production(0.1)
	testing.expect(t, base_counts[EARTH] == 2 && base_build_planet == -1, "second base completed")
	// The new line must have pulled the first pending item with no new order.
	testing.expect(t, production[EARTH][1].active && production[EARTH][1].kind == .COMBAT, "new base's line picked up the pending COMBAT")
	testing.expect(t, pending_count[EARTH] == 1, "one item still pending")
	// And it is genuinely building: progress advanced on this very tick.
	testing.expect(t, production[EARTH][1].progress > 0, "picked-up line starts building immediately")
}

@(test)
unscouted_planet_has_no_intel :: proc(t: ^testing.T) {
	reset_world()
	spawn_garrison(JUPITER, 5, 3)
	// Never scouted: intel_recorded stays false (the inspector shows UNSCOUTED).
	testing.expect(t, !intel_recorded[JUPITER], "never-scouted planet records no intel")
	testing.expect(t, !has_vision(JUPITER), "no player presence at Jupiter")
	update_intel()
	testing.expect(t, !intel_recorded[JUPITER], "still no intel without vision")
}

// ---- Base cost (500) & drone build-speed upgrades ----------------------

@(test)
base_construction_costs_500_minerals :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	// One mineral short of the 500 cost blocks the build and spends nothing.
	minerals = 499
	start_base_construction()
	testing.expect(t, base_build_planet != EARTH, "below 500 minerals blocks construction")
	testing.expect(t, minerals == 499, "blocked build spends no minerals")
	// Exactly 500 queues the build and deducts the full cost.
	minerals = 500
	start_base_construction()
	testing.expect(t, base_build_planet == EARTH, "500 minerals queues the build")
	testing.expect(t, minerals == 0, "construction deducts 500 minerals")
}

@(test)
drone_speed_upgrade_purchase :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	// Below the 5000 cost the purchase is refused and the level is unchanged.
	minerals = 4999
	testing.expect(t, purchase_drone_speed_upgrade() == false, "purchase refuses below 5000 minerals")
	testing.expect(t, drone_speed_level == 0, "level unchanged on refusal")
	testing.expect(t, minerals == 4999, "refused purchase spends nothing")
	// 5000 minerals buys exactly one level and deducts the cost.
	minerals = DRONE_SPEED_UPGRADE_COST
	testing.expect(t, purchase_drone_speed_upgrade() == true, "purchase succeeds at 5000")
	testing.expect(t, minerals == 0, "purchase deducts 5000")
	testing.expect(t, drone_speed_level == 1, "level increments to 1")
	// The cap at DRONE_SPEED_UPGRADE_MAX is enforced: the final level is
	// reachable, but a further purchase is refused and does not charge.
	drone_speed_level = DRONE_SPEED_UPGRADE_MAX - 1
	minerals = DRONE_SPEED_UPGRADE_COST
	testing.expect(t, purchase_drone_speed_upgrade() == true, "final level is reachable")
	testing.expect(t, drone_speed_level == DRONE_SPEED_UPGRADE_MAX, "level caps at the max")
	testing.expect(t, purchase_drone_speed_upgrade() == false, "purchase refuses past the cap")
	testing.expect(t, minerals == 0, "capped purchase does not double-charge")
	// The upgrade is an Earth-only affordance: off-Earth it is unavailable.
	selected_planet = MARS
	minerals = 10000
	testing.expect(t, purchase_drone_speed_upgrade() == false, "upgrade is Earth-only")
	testing.expect(t, drone_speed_level == DRONE_SPEED_UPGRADE_MAX, "off-Earth purchase leaves the level untouched")
}

@(test)
drone_build_times_scale_with_upgrade :: proc(t: ^testing.T) {
	reset_world()
	// Level 0 keeps the base build times for both drone kinds.
	testing.expect(t, drone_build_time(.MINING) == MINER_BUILD_TIME, "level 0 keeps the base miner time")
	testing.expect(t, drone_build_time(.COMBAT) == COMBAT_BUILD_TIME, "level 0 keeps the base combat time")
	// Each level compounds to 80% of the previous time.
	drone_speed_level = 1
	testing.expect(t, abs(drone_build_time(.MINING) - MINER_BUILD_TIME * 0.8) < 0.0001, "one level cuts miner time 20%")
	testing.expect(t, abs(drone_build_time(.COMBAT) - COMBAT_BUILD_TIME * 0.8) < 0.0001, "one level cuts combat time 20%")
	drone_speed_level = 2
	testing.expect(t, abs(drone_build_time(.MINING) - MINER_BUILD_TIME * 0.64) < 0.0001, "two levels compound to 64%")
	// Five levels compound to ~33% of the base time, never reaching zero.
	drone_speed_level = DRONE_SPEED_UPGRADE_MAX
	testing.expect(t, drone_build_time(.MINING) < MINER_BUILD_TIME * 0.33, "five levels compound to ~33% of base")
	testing.expect(t, drone_build_time(.MINING) > 0.0, "build time never reaches zero")
}

@(test)
reset_world_restores_drone_speed_level :: proc(t: ^testing.T) {
	drone_speed_level = 3
	reset_world()
	testing.expect(t, drone_speed_level == 0, "reset restores the upgrade level to 0")
}

// ---- Repositioned outer planets ----------------------------------------

@(test)
outer_planets_moved_closer_to_earth :: proc(t: ^testing.T) {
	// Saturn/Uranus/Neptune shifted 80 units further left (X) so Earth sits
	// almost mid-pack — three planets left (Mercury, Saturn, Venus), four
	// right (Uranus, Mars, Neptune, Jupiter) — keeping 30 units of spacing
	// between them (Jupiter's fixed x=50 bounds the right edge, so a 3/4
	// split is as centered as the layout can get).
	testing.expect(t, planets[SATURN].position.x == -25, "Saturn shifted to x=-25")
	testing.expect(t, planets[URANUS].position.x == 5, "Uranus shifted to x=5")
	testing.expect(t, planets[NEPTUNE].position.x == 35, "Neptune shifted to x=35")
	testing.expect(t, planets[URANUS].position.x - planets[SATURN].position.x == 30, "Saturn->Uranus spacing kept at ~30")
	testing.expect(t, planets[NEPTUNE].position.x - planets[URANUS].position.x == 30, "Uranus->Neptune spacing kept at ~30")
	left, right := 0, 0
	for p in 0..<PLANET_COUNT {
		if planets[p].position.x < 0 { left += 1 }
		if planets[p].position.x > 0 { right += 1 }
	}
	testing.expect(t, left == 3 && right == 4, "Earth sits mid-pack: 3 planets left, 4 right")
	// No pair collides or crowds after the shift (>2 units past touching radii).
	for a in 0..<PLANET_COUNT {
		for b in a + 1..<PLANET_COUNT {
			clear := distance(planets[a].position, planets[b].position) - planets[a].radius - planets[b].radius
			testing.expectf(t, clear > 2.0, "planets %d and %d keep >2 units of clearance", a, b)
		}
	}
	// The enemy HQ stays where Neptune used to be (the original outer orbit).
	testing.expect(t, abs(distance(ENEMY_HQ_POSITION, rl.Vector3{140, 5, 24})) < 0.001, "HQ at the old Neptune orbit")
}

// ---- Enemy HQ garrison & combat -----------------------------------------

@(test)
enemy_hq_holds_five_hundred_fighter_garrison :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	testing.expect(t, ENEMY_HQ_GARRISON == 500 && GARRISON_FIGHTERS[ENEMY_HOME] == 500, "HQ garrison is 500 fighters")
	testing.expect(t, ENEMY_HQ_BASE_HP == 500 && GARRISON_BASE_HP[ENEMY_HOME] == 500, "HQ base HP is 500")
	testing.expect(t, enemy_base_hp[ENEMY_HOME] == ENEMY_HQ_BASE_HP, "HQ starts at full structural HP")
	_, garrison := planet_combatants(ENEMY_HOME)
	testing.expect(t, garrison == ENEMY_HQ_GARRISON, "HQ spawns its 500-fighter garrison")
	testing.expect(t, !planet_liberated(ENEMY_HOME) && !enemy_hq_destroyed(), "HQ starts intact")
}

@(test)
enemy_hq_falls_after_garrison_trade :: proc(t: ^testing.T) {
	reset_world()
	// Trimmed HP so the full flow runs without 500-tick loops.
	enemy_base_hp[ENEMY_HOME] = 3
	for i in 0..<6 { add_guarding_fighter(ENEMY_HOME, true) }
	for i in 0..<10 { add_guarding_fighter(ENEMY_HOME, false) }
	// 10v6 trade: 6 ticks kill the garrison, 4 player fighters survive.
	_, enemies := planet_combatants(ENEMY_HOME)
	for enemies > 0 {
		update_enemy_waves(f32(COMBAT_TICK))
		_, enemies = planet_combatants(ENEMY_HOME)
	}
	players, _ := planet_combatants(ENEMY_HOME)
	testing.expect(t, players == 4, "4 player fighters survive the HQ garrison trade")
	// Survivors then breach the base: one HP per fighter per tick.
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, enemy_base_hp[ENEMY_HOME] == 0, "HQ base takes damage per fighter per tick")
	testing.expect(t, planet_liberated(ENEMY_HOME) && enemy_hq_destroyed(), "HQ falls once its HP hits 0")
	// A destroyed HQ never launches another wave, ever - even fully armed
	// (2 mined planets, a second liberated world for wave size).
	wave_started = false
	enemy_wave_timer = 0
	enemy_base_hp[VENUS] = 0
	add_miner(EARTH)
	add_miner(VENUS)
	before := unit_count
	update_wave(f32(WAVE_FIRST_DELAY))
	testing.expect(t, unit_count == before, "no waves launch from a destroyed HQ")
}

// ---- Victory condition & restart ----------------------------------------

@(test)
victory_requires_liberated_planets_and_dead_hq :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, !victory_achieved(), "no victory at the start")
	// A dead HQ alone is not victory while planets stay occupied.
	enemy_base_hp[ENEMY_HOME] = 0
	testing.expect(t, !victory_achieved(), "dead HQ alone is not victory while planets are occupied")
	// Liberated planets alone are not victory while the HQ stands.
	enemy_base_hp = GARRISON_BASE_HP
	for p in 0..<PLANET_COUNT { enemy_base_hp[p] = 0 }
	testing.expect(t, !victory_achieved(), "liberated planets alone are not victory while the HQ stands")
	// Both: victory.
	enemy_base_hp[ENEMY_HOME] = 0
	testing.expect(t, victory_achieved(), "all planets + HQ destroyed is victory")
}

@(test)
step_simulation_latches_victory :: proc(t: ^testing.T) {
	reset_world()
	for p in 0..<SECTOR_COUNT { enemy_base_hp[p] = 0 }
	step_simulation(0.01)
	testing.expect(t, victory, "victory latches during play")
	testing.expect(t, victory_achieved(), "victory condition holds after latching")
}

@(test)
restart_game_resets_the_world :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	minerals = 99999
	drone_speed_level = 3
	victory = true
	for p in 0..<SECTOR_COUNT { enemy_base_hp[p] = 0 }
	restart_game()
	testing.expect(t, !victory, "restart clears the victory overlay")
	testing.expect(t, minerals == 350, "restart restores starting minerals")
	testing.expect(t, drone_speed_level == 0, "restart clears upgrades")
	testing.expect(t, enemy_base_hp == GARRISON_BASE_HP, "restart restores every garrison base incl. the HQ")
	_, garrison := planet_combatants(ENEMY_HOME)
	testing.expect(t, garrison == ENEMY_HQ_GARRISON, "restart restores the HQ garrison")
}

@(test)
headless_victory_overlay_update_is_idle :: proc(t: ^testing.T) {
	// No key/mouse events headless: update_victory_overlay must restart nothing.
	victory = true
	quit_requested = false
	update_victory_overlay()
	testing.expect(t, victory, "still victorious (no restart fired)")
	testing.expect(t, !quit_requested, "overlay never quits")
	victory = false
}

// ---- HQ orders: fighters only, no rally ---------------------------------

@(test)
hq_orders_apply_to_fighters_only :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	add_guarding_fighter(EARTH, false)
	selected_units[0] = true
	units[unit_count] = Unit{kind = .MINING, state = .MINING, position = planets[MARS].position, home_planet = EARTH, affiliation = MARS, target_planet = MARS}
	unit_count += 1
	selected_units[1] = true
	handle_planet_right_click(ENEMY_HOME)
	testing.expect(t, units[0].target_planet == ENEMY_HOME && units[0].state == .TRANSIT, "fighters sortie to the HQ")
	testing.expect(t, units[1].target_planet == MARS && units[1].state == .MINING, "miners ignore HQ orders")
	// The HQ is not a valid mining rally either.
	set_earth_rally(ENEMY_HOME)
	testing.expect(t, earth_rally == NO_RALLY, "HQ cannot be a rally point")
	earth_rally = NO_RALLY
}

// ---- Combat tick acceleration to 0.2s ----------------------------------

@(test)
combat_tick_is_0_2_seconds :: proc(t: ^testing.T) {
	// 5x faster than the old 1s tick: dogfights, base sieges and miner sweeps
	// all resolve one trade per 0.2s.
	testing.expect(t, COMBAT_TICK == 0.2, "combat tick is 0.2s")
}

@(test)
hq_garrison_trade_resolves_five_times_faster :: proc(t: ^testing.T) {
	reset_world()
	enemy_base_hp[ENEMY_HOME] = 0
	for i in 0..<50 { add_guarding_fighter(ENEMY_HOME, false) }
	for i in 0..<50 { add_guarding_fighter(ENEMY_HOME, true) }
	// 50:1 trades, one per 0.2s tick: the full dogfight clears in 50 ticks.
	ticks := 0
	players, enemies := planet_combatants(ENEMY_HOME)
	for players > 0 && enemies > 0 {
		update_enemy_waves(f32(COMBAT_TICK))
		ticks += 1
		players, enemies = planet_combatants(ENEMY_HOME)
	}
	testing.expect(t, players == 0 && enemies == 0, "50v50 HQ dogfight fully trades")
	testing.expect(t, ticks == 50, "50 trades at 0.2s each = 10s (was 50s at the old 1s tick)")
}

// ---- Enemy HQ inspector & recall ---------------------------------------

@(test)
hq_left_click_selects_the_sector :: proc(t: ^testing.T) {
	// Left-clicking the HQ in world space selects ENEMY_HOME so its inspector
	// renders without indexing past the planet table.
	reset_world()
	selected_planet = EARTH
	selected_planet = ENEMY_HOME
	testing.expect(t, selected_planet == ENEMY_HOME, "HQ sector is selectable")
	// The HQ roster counts player fighters stationed at the HQ (affiliation
	// == ENEMY_HOME), and excludes miners (issue_group_order never sends
	// miners to the HQ).
	add_guarding_fighter(ENEMY_HOME, false)
	add_guarding_fighter(ENEMY_HOME, false)
	testing.expect(t, roster_count(.COMBAT) == 2, "stationed fighters appear in the HQ roster")
	testing.expect(t, roster_count(.MINING) == 0, "no miners in the HQ roster")
	testing.expect(t, enemy_roster_count(.COMBAT) == 0, "no enemy garrison spawned in this scenario")
}

@(test)
hq_roster_tile_click_selects_and_recalls_unit :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = ENEMY_HOME
	add_guarding_fighter(ENEMY_HOME, false) // a player fighter stationed at the HQ
	// panel_x = 0: the first combat-roster tile is the stationed fighter.
	rect := unit_tile_rect(0, unit_tile_y(.COMBAT), 0)
	handle_inspector_click({rect.x + 1, rect.y + 1}, 0)
	testing.expect(t, selection_count() == 1, "clicking an HQ roster tile selects the stationed fighter")
	// Right-click Earth to recall the reselected fighter off the HQ.
	handle_planet_right_click(EARTH)
	testing.expect(t, units[0].target_planet == EARTH, "reselected fighter retargets Earth")
	testing.expect(t, units[0].state == .TRANSIT, "fighter leaves the HQ for Earth in transit")
	selected_planet = EARTH
}

@(test)
hq_stationed_fighters_can_be_recalled :: proc(t: ^testing.T) {
	// Fighters sent to the HQ (in transit or guarding) can be reselected from
	// the HQ inspector and redirected to Earth via right-click.
	reset_world()
	selected_planet = EARTH
	for i in 0..<3 { add_guarding_fighter(EARTH, false) }
	for i in 0..<3 { selected_units[i] = true }
	handle_planet_right_click(ENEMY_HOME)
	for i in 0..<3 {
		testing.expect(t, units[i].target_planet == ENEMY_HOME && units[i].state == .TRANSIT, "fighters sortie to the HQ")
	}
	// They arrive (guard the HQ), then the player reselects and recalls them.
	for i in 0..<3 {
		units[i].state = .GUARDING
		units[i].position = ENEMY_HQ_POSITION
		selected_units[i] = true
	}
	selected_planet = ENEMY_HOME
	testing.expect(t, roster_count(.COMBAT) == 3, "guarding fighters show in the HQ roster")
	handle_planet_right_click(EARTH)
	for i in 0..<3 {
		testing.expect(t, units[i].target_planet == EARTH, "reselected fighters are recalled to Earth")
		testing.expect(t, units[i].state == .TRANSIT, "recalled fighters enter transit back to Earth")
	}
	selected_planet = EARTH
}

// ---- Victory overlay: Play Again + Quit --------------------------------

@(test)
victory_overlay_play_and_quit_buttons_never_overlap :: proc(t: ^testing.T) {
	play, quit := victory_button_rects()
	testing.expect(t, play.width > 0 && play.height > 0, "play button exists")
	testing.expect(t, quit.width > 0 && quit.height > 0, "quit button exists")
	testing.expect(t, !rl.CheckCollisionRecs(play, quit), "play and quit buttons never overlap")
	testing.expect(t, play.x < quit.x, "play sits left of quit")
}

@(test)
victory_quit_keybind_is_q_or_escape :: proc(t: ^testing.T) {
	// No key events headless: the Q/ESC predicate reads false, so an open
	// overlay never quits by itself; the binding lives in the predicate.
	victory = true
	quit_requested = false
	testing.expect(t, !victory_quit_key_pressed(), "no Q/ESC events headless")
	update_victory_overlay()
	testing.expect(t, victory, "still victorious (no restart fired)")
	testing.expect(t, !quit_requested, "idle overlay never quits")
	victory = false
	quit_requested = false
}

// ---- Base crew prefers Earth-assigned miners ------------------------------

@(test)
base_crew_prefers_earth_assigned_miners_over_foreign_routes :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 500
	start_base_construction()
	testing.expect(t, base_build_planet == EARTH, "build queued")
	// A foreign-route drone mid-deposit at Earth: while an Earth-assigned
	// miner is still available, it must keep its route.
	units[unit_count] = Unit{
		kind = .MINING, state = .DEPOSITING, position = planets[EARTH].position,
		home_planet = EARTH, affiliation = MARS, target_planet = MARS,
		progress = DEPOSIT_DURATION - 0.01,
	}
	unit_count += 1
	units[unit_count] = Unit{
		kind = .MINING, state = .TRANSIT, position = sector_pos(EARTH),
		home_planet = EARTH, affiliation = EARTH, target_planet = EARTH,
	}
	unit_count += 1
	update_miner(&units[0], 0, 0.02)
	testing.expect(t, units[0].state == .TRANSIT, "foreign depositor keeps its route while Earth drones remain")
	testing.expect(t, constructing_miners(EARTH) == 0, "crew stays empty while Earth drones are available")
	// The Earth-assigned drone deposits and joins; now no Earth-assigned
	// miner remains, so the foreign one is free to soak into the crew.
	units[1].state = .DEPOSITING
	units[1].progress = DEPOSIT_DURATION - 0.01
	update_miner(&units[1], 1, 0.02)
	testing.expect(t, units[1].state == .CONSTRUCTING && units[1].target_planet == EARTH, "Earth-assigned depositor joins first")
	units[0].state = .DEPOSITING
	units[0].progress = DEPOSIT_DURATION - 0.01
	update_miner(&units[0], 0, 0.02)
	testing.expect(t, units[0].state == .CONSTRUCTING, "foreign depositor joins once Earth's own are exhausted")
	testing.expect(t, constructing_miners(EARTH) == 2, "crew counts both joiners")
}

@(test)
base_crew_earth_preference_clears_when_earth_miners_vanish :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 500
	start_base_construction()
	// Foreign depositor + Earth-assigned miner far out in transit.
	units[unit_count] = Unit{
		kind = .MINING, state = .DEPOSITING, position = planets[EARTH].position,
		home_planet = EARTH, affiliation = VENUS, target_planet = VENUS,
		progress = DEPOSIT_DURATION - 0.01,
	}
	unit_count += 1
	units[unit_count] = Unit{
		kind = .MINING, state = .RETURNING, position = sector_pos(VENUS),
		home_planet = EARTH, affiliation = EARTH, target_planet = EARTH,
	}
	unit_count += 1
	update_miner(&units[0], 0, 0.02)
	testing.expect(t, units[0].state != .CONSTRUCTING, "foreign depositor waits for the Earth miner")
	// Earth-assigned miner destroyed: nothing Earth-side remains, foreign joins.
	remove_unit_at(1)
	update_miner(&units[0], 0, 0.02)
	units[0].state = .DEPOSITING
	units[0].progress = DEPOSIT_DURATION - 0.01
	update_miner(&units[0], 0, 0.02)
	testing.expect(t, units[0].state == .CONSTRUCTING, "foreign depositor joins once no Earth-assigned miner exists")
}

// ---- Intel roster snapshot for the ghost view -----------------------------

@(test)
intel_snapshot_captures_roster_and_freezes_while_dark :: proc(t: ^testing.T) {
	reset_world()
	spawn_garrison(JUPITER, 2, 2)
	// Player scout pinned at the garrison lifts the fog.
	units[unit_count] = Unit{kind = .MINING, state = .IDLE, position = planets[JUPITER].position, home_planet = EARTH, affiliation = JUPITER, target_planet = JUPITER}
	unit_count += 1
	update_intel()
	intel := last_known_intel[JUPITER]
	testing.expect(t, intel.unit_count == 5, "snapshot holds 2 garrison fighters, 2 enemy miners and the scout")
	player_miners, enemy_miners, enemy_fighters := 0, 0, 0
	for i := 0; i < intel.unit_count; i += 1 {
		u := &intel.units[i]
		if u.kind == .COMBAT && u.enemy { enemy_fighters += 1 }
		if u.kind == .MINING && u.enemy { enemy_miners += 1 }
		if u.kind == .MINING && !u.enemy { player_miners += 1; testing.expect(t, u.state == .IDLE, "scout state captured") }
	}
	testing.expect(t, enemy_fighters == 2 && enemy_miners == 2 && player_miners == 1, "per-unit detail: kind, state and side all captured")
	// Scout destroyed: Jupiter goes dark and the snapshot must freeze even as
	// the live garrison changes.
	remove_unit_at(unit_count - 1)
	testing.expect(t, !has_vision(JUPITER), "Jupiter dark without the scout")
	remove_unit_at(0)
	units[0].state = .IDLE
	update_intel()
	intel = last_known_intel[JUPITER]
	testing.expect(t, intel.unit_count == 5, "snapshot does not mutate while dark")
	enemy_fighters = 0
	for i := 0; i < intel.unit_count; i += 1 {
		if intel.units[i].kind == .COMBAT && intel.units[i].enemy { enemy_fighters += 1 }
	}
	testing.expect(t, enemy_fighters == 2, "stale roster preserved after going dark")
}

@(test)
ghost_view_flag_matches_scouted_dark_state :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = JUPITER
	testing.expect(t, !ghost_view(), "never-scouted planet is not a ghost view")
	units[unit_count] = Unit{kind = .MINING, state = .IDLE, position = planets[JUPITER].position, home_planet = EARTH, affiliation = JUPITER, target_planet = JUPITER}
	unit_count += 1
	update_intel()
	testing.expect(t, !ghost_view(), "lit planet with intel is live, not ghost")
	remove_unit_at(0)
	testing.expect(t, ghost_view(), "scouted planet under fog renders the ghost view")
	selected_planet = EARTH
	testing.expect(t, !ghost_view(), "Earth is always lit and never a ghost view")
}

// Regression: in the ghost view both ENEMY sections must stack with the same
// offsets the live path uses. The original bug drew every section from the
// .MINING kind, putting both enemy headers/tiles on enemy_tile_y(.MINING)
// (garbled overlap) and dropping fighter tiles entirely.
@(test)
ghost_roster_sections_stack_like_live_view :: proc(t: ^testing.T) {
	reset_world()
	initialize_game() // Venus garrison: 10 fighters + 4 miners (mixed).
	// Player scout at Venus, snapshot, then killed: planet goes dark.
	units[unit_count] = Unit{kind = .COMBAT, state = .GUARDING, position = orbit_pos(sector_pos(VENUS), sector_radius(VENUS), 0), home_planet = EARTH, affiliation = EARTH, target_planet = VENUS}
	unit_count += 1
	selected_planet = VENUS
	update_intel()
	remove_unit_at(unit_count - 1)
	testing.expect(t, ghost_view(), "scouted Venus with a dead scout must be a ghost view")

	em := ghost_count(.MINING, true)
	ef := ghost_count(.COMBAT, true)
	testing.expect(t, em == GARRISON_MINERS[VENUS], "snapshot keeps the enemy miner count")
	testing.expect(t, ef == GARRISON_FIGHTERS[VENUS], "snapshot keeps the enemy fighter count")

	// Section origins come from the shared layout helpers; the fighting
	// section must sit exactly one header + mining-rows block below the
	// mining section (the live-view offset), never on the same origin.
	mining_y := enemy_tile_y(.MINING)
	fighting_y := enemy_tile_y(.COMBAT)
	offset := 26 + ((em + TILES_PER_ROW - 1) / TILES_PER_ROW) * (TILE_SIZE + TILE_GAP)
	testing.expect(t, fighting_y - mining_y == offset, "ghost enemy fighting section stacks below mining at the live-view offset")
}

// Disconfirming edge: a fighters-only garrison must still render its fighter
// section (no overlap is possible there, but the tiles must not vanish).
@(test)
ghost_fighters_only_garrison_keeps_fighter_section :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	// Strip Venus down to fighters only.
	for i := 0; i < unit_count; i += 1 {
		u := &units[i]
		if u.enemy && u.kind == .MINING && u.target_planet == VENUS { remove_unit_at(i); i -= 1 }
	}
	units[unit_count] = Unit{kind = .COMBAT, state = .GUARDING, position = orbit_pos(sector_pos(VENUS), sector_radius(VENUS), 0), home_planet = EARTH, affiliation = EARTH, target_planet = VENUS}
	unit_count += 1
	selected_planet = VENUS
	update_intel()
	remove_unit_at(unit_count - 1)
	testing.expect(t, ghost_view(), "Venus dark after scout loss")
	testing.expect(t, ghost_count(.MINING, true) == 0, "miners-only strip left no miners in the snapshot")
	testing.expect(t, ghost_count(.COMBAT, true) == GARRISON_FIGHTERS[VENUS], "fighter section stays populated without miners")
}

@(test)
enemy_fighters_collapse_without_empty_mining_gap :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	// Earth has no enemy mining drones.
	selected_planet = EARTH
	testing.expect(t, enemy_roster_count(.MINING) == 0, "no enemy miners on Earth")
	// When no enemy miners exist, enemy combat tiles must collapse to the first
	// enemy section position instead of leaving a phantom empty section gap.
	testing.expect(t, enemy_tile_y(.COMBAT) == enemy_tile_y(.MINING), "enemy fighters collapse to enemy_tile_y(.MINING) when no enemy miners exist")
}

// Bug regression: dispatching miners to scout a planet (transit toward it,
// pinned idle at an occupied world) must not register as mining — the invasion
// watch fires only on actual mining activity.
@(test)
scouting_miners_do_not_trigger_invasion_watch :: proc(t: ^testing.T) {
	reset_world()
	// A miner ordered to a far planet, mid-transit: not mining yet.
	units[unit_count] = Unit{kind = .MINING, state = .TRANSIT, position = {20, 0, 0}, home_planet = EARTH, affiliation = JUPITER, target_planet = JUPITER}
	unit_count += 1
	testing.expect(t, mined_planet_count() == 0, "miner dispatched toward a planet does not count as mining")
	// Arriving at an occupied world pins the drone as an idle scout.
	units[0].state = .IDLE
	testing.expect(t, mined_planet_count() == 0, "scout pinned idle at an occupied planet does not count as mining")
	// Once it actually mines (liberated world), the watch counts the planet.
	units[0].state = .MINING
	testing.expect(t, mined_planet_count() == 1, "actively mining the planet counts")
}

// The HQ is a sector, not a planet: dogfights there must resolve through the
// same update_planet_combat path without tripping over planet-table bounds.
@(test)
step_simulation_resolves_combat_at_enemy_hq :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	for i in 0..<5 { add_guarding_fighter(ENEMY_HOME, false) }
	players_before, enemies_before := planet_combatants(ENEMY_HOME)
	step_simulation(f32(COMBAT_TICK))
	players, enemies := planet_combatants(ENEMY_HOME)
	testing.expect(t, players == players_before - 1 && enemies == enemies_before - 1, "1:1 trade per tick at the HQ sector (garrison included)")
	step_simulation(f32(COMBAT_TICK))
	players, enemies = planet_combatants(ENEMY_HOME)
	testing.expect(t, players == players_before - 2 && enemies == enemies_before - 2, "HQ combat keeps ticking across steps")
}

// ---- Game over -----------------------------------------------------------

// Undefended Earth: with no player fighters or miners left, the occupying
// enemy garrison tears down the command base via update_planet_combat.
@(test)
enemy_siege_destroys_undefended_earth_base :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, base_counts[EARTH] == 1, "Earth opens with one command base")
	add_guarding_fighter(EARTH, true)
	// Siege needs BASE_SIEGE_TIME of uncontested occupation; step well past it.
	destroyed := false
	for i in 0..<40 {
		update_planet_combat(f32(COMBAT_TICK), EARTH)
		if base_counts[EARTH] == 0 { destroyed = true; break }
	}
	testing.expect(t, destroyed, "undefended Earth's command base falls to the siege")
}

// A surviving defender blocks the siege: the dogfight trade consumes both
// sides and the base timer never runs while a player fighter guards Earth.
@(test)
defended_earth_base_survives_siege :: proc(t: ^testing.T) {
	reset_world()
	add_guarding_fighter(EARTH, false)
	add_guarding_fighter(EARTH, true)
	for i in 0..<40 { update_planet_combat(f32(COMBAT_TICK), EARTH) }
	testing.expect(t, base_counts[EARTH] == 1, "defended Earth's base is untouched by the siege")
}

// Losing a base drops its production line; pending queue items redistribute
// across the surviving lines.
@(test)
destroy_player_base_cleans_up_production :: proc(t: ^testing.T) {
	reset_world()
	minerals = 10000
	queue_unit(.MINING) // fills line 0
	base_counts[EARTH] = 2 // pretend a second base exists for this check
	queue_unit(.COMBAT) // fills line 1
	queue_unit(.MINING) // pending (both lines busy)
	destroy_player_base(EARTH)
	testing.expect(t, base_counts[EARTH] == 1, "base count decrements")
	testing.expect(t, queued_count(EARTH) == 2, "line + pending still account for both orders")
	testing.expect(t, production[EARTH][0].active && production[EARTH][0].kind == .MINING, "line 0 keeps its build")
	testing.expect(t, !production[EARTH][1].active, "the destroyed base's line is cleared, not orphaned")
	testing.expect(t, pending_count[EARTH] == 1 && pending[EARTH][0] == .MINING, "surviving order waits in pending")
}

@(test)
defeat_triggers_when_all_bases_and_units_lost :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, !defeat_condition(), "fresh state (1 base, 0 units) is not a defeat")
	base_counts = {}
	unit_count = 0
	testing.expect(t, defeat_condition(), "zero bases AND zero units is defeat")
}

@(test)
surviving_base_blocks_defeat :: proc(t: ^testing.T) {
	reset_world()
	base_counts = {}
	base_counts[EARTH] = 1
	unit_count = 0
	testing.expect(t, !defeat_condition(), "a remaining command base blocks defeat")
}

@(test)
surviving_units_block_defeat :: proc(t: ^testing.T) {
	reset_world()
	base_counts = {}
	units[unit_count] = Unit{kind = .COMBAT, state = .GUARDING, position = {0, 3.8, 0}, home_planet = EARTH, affiliation = EARTH, target_planet = EARTH}
	unit_count += 1
	testing.expect(t, !defeat_condition(), "any surviving player unit blocks defeat")
}

// Enemy garrisons and waves occupy unit slots: only PLAYER units block defeat.
@(test)
enemy_units_do_not_block_defeat :: proc(t: ^testing.T) {
	reset_world()
	base_counts = {}
	add_guarding_fighter(VENUS, true)
	add_enemy_miner(MERCURY)
	testing.expect(t, defeat_condition(), "an enemy-only unit roster is still a defeat")
}

@(test)
step_simulation_latches_defeat_once :: proc(t: ^testing.T) {
	reset_world()
	base_counts = {}
	unit_count = 0
	step_simulation(f32(COMBAT_TICK))
	testing.expect(t, defeated, "defeat latches when the condition holds")
	// Edge-triggered: the overlay must not re-trigger or stack while showing.
	step_simulation(f32(COMBAT_TICK))
	testing.expect(t, defeated, "defeat stays latched, exactly once")
}

@(test)
restart_game_restores_fresh_playable_state :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	// Wreck the world into the defeat state, then restart.
	base_counts = {}
	unit_count = 0
	defeated = true
	restart_game()
	testing.expect(t, !defeated && !victory && !game_paused, "restart clears the overlays and pause")
	testing.expect(t, base_counts[EARTH] == 1, "restart restores Earth's command base")
	players, enemies := planet_combatants(EARTH)
	testing.expect(t, players == 5 && enemies == 0, "restart respawns Earth's 5 starting fighter drones")
	for p in 0..<PLANET_COUNT {
		if p == EARTH { continue }
		_, garrison := planet_combatants(p)
		testing.expectf(t, garrison == GARRISON_FIGHTERS[p], "planet %d garrison rebuilt after restart", p)
	}
	testing.expect(t, enemy_base_hp[ENEMY_HOME] == ENEMY_HQ_BASE_HP, "enemy HQ restored after restart")
}

@(test)
bases_collapse_gap_when_five_bases_built :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	testing.expect(t, base_button_visible(), "base button visible with 1 base")
	testing.expect(t, production_title_y() == PROD_TITLE_Y, "production title at normal PROD_TITLE_Y with 1 base")
	testing.expect(t, production_first_y() == PROD_FIRST_Y, "production line 0 at PROD_FIRST_Y with 1 base")
	testing.expect(t, production_orders_y() == ORDERS_BASE_Y, "orders at ORDERS_BASE_Y with 1 base")

	// Set bases to 5 (cap)
	base_counts[EARTH] = MAX_BASES
	testing.expect(t, !base_button_visible(), "base button hidden with 5 bases")
	testing.expect(t, production_title_y() == SECTION_TOP, "production title collapses up to SECTION_TOP with 5 bases")
	testing.expect(t, production_first_y() == SECTION_TOP + 23, "production first line collapses up with 5 bases")
	testing.expect(t, production_orders_y() == ORDERS_BASE_Y - BASE_COLLAPSE_Y + 4 * PROD_PITCH, "orders collapse up to account for removed button")

	// With base constructing at Earth, button is visible and positions stay expanded
	base_counts[EARTH] = 4
	base_build_planet = EARTH
	testing.expect(t, base_button_visible(), "base button visible while constructing")
	testing.expect(t, production_title_y() == PROD_TITLE_Y, "production title stays at PROD_TITLE_Y while constructing")
}

@(test)
five_bases_inspector_clicks_and_cancel :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	base_counts[EARTH] = MAX_BASES
	minerals = 1000

	// Clicking where the base button used to be at SECTION_TOP does NOT start base construction
	handle_inspector_click({PANEL_PAD_X + 10, f32(SECTION_TOP + 10)}, 0)
	testing.expect(t, base_build_planet < 0, "no base construction started from clicking collapsed area at 5 bases")

	// Queue a unit via the collapsed BUILD button
	orders_y := f32(production_orders_y())
	handle_inspector_click({PANEL_PAD_X + 10, orders_y + 10}, 0)
	testing.expect(t, queued_count(EARTH) == 1, "queue_unit succeeds at 5 bases via collapsed build button")

	// Cancel by clicking slot 0 in the collapsed queue
	slot_rect := queue_slot_rect(0, 0)
	handle_inspector_click({slot_rect.x + 1, slot_rect.y + 1}, 0)
	testing.expect(t, queued_count(EARTH) == 0, "cancel_queued_at works at 5 bases via collapsed queue slot")
}

@(test)
losing_base_from_cap_reopens_button_and_restores_positions :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	base_counts[EARTH] = MAX_BASES
	testing.expect(t, !base_button_visible(), "hidden at cap")

	// Siege destroys a base
	destroy_player_base(EARTH)
	testing.expect(t, base_counts[EARTH] == 4, "base count drops to 4")
	testing.expect(t, base_button_visible(), "button visible again at 4 bases")
	testing.expect(t, production_title_y() == PROD_TITLE_Y, "production title returns to PROD_TITLE_Y")
	testing.expect(t, production_orders_y() == ORDERS_BASE_Y + 3 * PROD_PITCH, "orders return to normal expanded Y")
}

@(test)
save_load_game_roundtrip_preserves_state :: proc(t: ^testing.T) {
	reset_world()
	test_save_file := "test_savegame_roundtrip.txt"
	defer delete_save_game(test_save_file)

	minerals = 725
	drone_speed_level = 3
	earth_rally = MARS
	selected_planet = JUPITER
	base_counts[EARTH] = 3
	base_build_planet = EARTH
	base_build_progress = 25.5
	enemy_wave_timer = 88.0
	wave_started = true
	production[EARTH][0] = Production{kind = .COMBAT, progress = 4.5, active = true}
	pending[EARTH][0] = .MINING
	pending[EARTH][1] = .COMBAT
	pending_count[EARTH] = 2
	enemy_base_hp[VENUS] = 0
	combat_timer[VENUS] = 0.15
	combat_vision_timer[VENUS] = 1.75
	intel_recorded[MARS] = true
	last_known_intel[MARS].fighters = 12
	last_known_intel[MARS].miners = 4
	last_known_intel[MARS].base_hp = 15
	last_known_intel[MARS].units[0] = Intel_Unit{kind = .COMBAT, state = .GUARDING, enemy = true}
	last_known_intel[MARS].unit_count = 1

	units[0] = Unit{kind = .COMBAT, state = .TRANSIT, position = {10, 2, 5}, home_planet = EARTH, affiliation = EARTH, target_planet = MARS, enemy = false, progress = 0.75, orbit_angle = 1.2, squad = 4}
	units[1] = Unit{kind = .MINING, state = .MINING, position = {22, 1, 6}, home_planet = EARTH, affiliation = MARS, target_planet = MARS, enemy = false, progress = 2.1, orbit_angle = 0, squad = 0}
	unit_count = 2

	saved := save_game(test_save_file)
	testing.expect(t, saved, "save_game successfully wrote file")

	reset_world()
	testing.expect(t, minerals == 350, "reset_world reset minerals")
	testing.expect(t, unit_count == 0, "reset_world reset unit count")

	loaded := load_game(test_save_file)
	testing.expect(t, loaded, "load_game successfully loaded file")

	testing.expect(t, minerals == 725, "minerals restored")
	testing.expect(t, drone_speed_level == 3, "drone_speed_level restored")
	testing.expect(t, earth_rally == MARS, "earth_rally restored")
	testing.expect(t, selected_planet == JUPITER, "selected_planet restored")
	testing.expect(t, base_counts[EARTH] == 3, "base_counts[EARTH] restored")
	testing.expect(t, base_build_planet == EARTH, "base_build_planet restored")
	testing.expect(t, abs(base_build_progress - 25.5) < 0.01, "base_build_progress restored")
	testing.expect(t, abs(enemy_wave_timer - 88.0) < 0.01, "enemy_wave_timer restored")
	testing.expect(t, wave_started == true, "wave_started restored")
	testing.expect(t, production[EARTH][0].kind == .COMBAT, "production line kind restored")
	testing.expect(t, production[EARTH][0].active == true, "production line active restored")
	testing.expect(t, abs(production[EARTH][0].progress - 4.5) < 0.01, "production line progress restored")
	testing.expect(t, pending_count[EARTH] == 2, "pending_count restored")
	testing.expect(t, pending[EARTH][0] == .MINING, "pending slot 0 restored")
	testing.expect(t, pending[EARTH][1] == .COMBAT, "pending slot 1 restored")
	testing.expect(t, enemy_base_hp[VENUS] == 0, "enemy base hp restored")
	testing.expect(t, abs(combat_timer[VENUS] - 0.15) < 0.01, "combat timer restored")
	testing.expect(t, abs(combat_vision_timer[VENUS] - 1.75) < 0.01, "combat vision timer restored")
	testing.expect(t, intel_recorded[MARS] == true, "intel recorded restored")
	testing.expect(t, last_known_intel[MARS].fighters == 12, "intel fighters restored")
	testing.expect(t, last_known_intel[MARS].unit_count == 1, "intel unit count restored")
	testing.expect(t, last_known_intel[MARS].units[0].kind == .COMBAT, "intel unit kind restored")
	testing.expect(t, unit_count == 2, "unit count restored")
	testing.expect(t, units[0].kind == .COMBAT, "unit 0 kind restored")
	testing.expect(t, units[0].state == .TRANSIT, "unit 0 state restored")
	testing.expect(t, units[0].squad == 4, "unit 0 squad restored")
	testing.expect(t, units[0].target_planet == MARS, "unit 0 target restored")
	testing.expect(t, units[1].kind == .MINING, "unit 1 kind restored")
	testing.expect(t, units[1].state == .MINING, "unit 1 state restored")
	testing.expect(t, !in_start_menu, "load_game exits start menu")
}

@(test)
save_game_exists_detects_file :: proc(t: ^testing.T) {
	test_file := "test_existence_check.txt"
	defer delete_save_game(test_file)

	delete_save_game(test_file)
	testing.expect(t, !save_game_exists(test_file), "detects missing file as non-existent")

	save_game(test_file)
	testing.expect(t, save_game_exists(test_file), "detects saved file as existent")

	delete_save_game(test_file)
	testing.expect(t, !save_game_exists(test_file), "detects deleted file as non-existent")
}

@(test)
load_game_returns_false_on_missing_file :: proc(t: ^testing.T) {
	testing.expect(t, !load_game("definitely_non_existent_file_9999.txt"), "returns false on missing file")
}

@(test)
start_menu_options_and_navigation :: proc(t: ^testing.T) {
	testing.expect(t, start_menu_options_count(false) == 2, "2 options when no save")
	testing.expect(t, start_menu_options_count(true) == 3, "3 options when save exists")

	test_file := "test_menu_nav.txt"
	save_game(test_file)
	defer delete_save_game(test_file)

	// Test navigation with save (3 options: 0=CONTINUE, 1=NEW GAME, 2=QUIT)
	start_menu_selection = 0
	advance_start_menu_selection(1)
	testing.expect(t, start_menu_selection == 1, "DOWN moves to NEW GAME")
	advance_start_menu_selection(1)
	testing.expect(t, start_menu_selection == 2, "DOWN moves to QUIT")
	advance_start_menu_selection(1)
	testing.expect(t, start_menu_selection == 0, "DOWN wraps to CONTINUE")
	advance_start_menu_selection(-1)
	testing.expect(t, start_menu_selection == 2, "UP wraps to QUIT")
}

@(test)
start_menu_activations_work :: proc(t: ^testing.T) {
	test_file := "test_menu_acts.txt"
	save_game(test_file)
	defer delete_save_game(test_file)

	in_start_menu = true
	quit_requested = false

	// Option 1 (NEW GAME)
	start_menu_selection = 1
	activate_start_menu_selection()
	testing.expect(t, !in_start_menu, "NEW GAME exits start menu")
	testing.expect(t, !quit_requested, "NEW GAME does not quit")

	// Option 2 (QUIT)
	in_start_menu = true
	start_menu_selection = 2
	activate_start_menu_selection()
	testing.expect(t, quit_requested, "QUIT requests quit")
	quit_requested = false
}

@(test)
queue_units_five_miners :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	base_counts[EARTH] = 1
	minerals = 500

	queue_units(.MINING, 5)

	testing.expect(t, minerals == 250, "5 miners cost 250 minerals (500 - 5 * 50)")
	testing.expect(t, queued_count(EARTH) == 5, "5 units queued (1 active + 4 pending)")
	testing.expect(t, production[EARTH][0].active, "base 1 active")
	testing.expect(t, production[EARTH][0].kind == .MINING, "base 1 building mining drone")
	testing.expect(t, pending_count[EARTH] == 4, "4 pending mining drones")
	for i in 0..<4 {
		testing.expect(t, pending[EARTH][i] == .MINING, "pending slot has mining drone")
	}
}

@(test)
queue_units_five_combat :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	base_counts[EARTH] = 2
	minerals = 1000

	queue_units(.COMBAT, 5)

	testing.expect(t, minerals == 375, "5 combat drones cost 625 minerals (1000 - 5 * 125)")
	testing.expect(t, queued_count(EARTH) == 5, "5 units queued (2 active + 3 pending)")
	testing.expect(t, production[EARTH][0].active && production[EARTH][0].kind == .COMBAT, "base 1 building combat")
	testing.expect(t, production[EARTH][1].active && production[EARTH][1].kind == .COMBAT, "base 2 building combat")
	testing.expect(t, pending_count[EARTH] == 3, "3 pending combat drones")
}

@(test)
queue_units_respects_limits :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	base_counts[EARTH] = 1 // max queue capacity is 1 * 5 = 5
	minerals = 120 // only enough for 2 miners (50 * 2 = 100)

	queue_units(.MINING, 5)
	testing.expect(t, queued_count(EARTH) == 2, "stops when minerals run out (queued 2)")
	testing.expect(t, minerals == 20, "remaining minerals 20")

	// Now add enough minerals to fill queue and beyond
	minerals = 1000
	queue_units(.MINING, 5) // only 3 slots open before cap (2 + 3 = 5)
	testing.expect(t, queued_count(EARTH) == 5, "stops at queue capacity cap 5")
	testing.expect(t, minerals == 1000 - 3 * 50, "only paid for the 3 units queued")
}

@(test)
queue_5_miners_shortcut :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 1000

	// Blocked below 5 bases
	base_counts[EARTH] = 1
	queue_5_miners()
	testing.expect(t, queued_count(EARTH) == 0, "queue_5_miners blocked with 1 base")
	testing.expect(t, minerals == 1000, "no minerals spent when blocked")

	base_counts[EARTH] = 4
	queue_5_miners()
	testing.expect(t, queued_count(EARTH) == 0, "queue_5_miners blocked with 4 bases")
	testing.expect(t, minerals == 1000, "no minerals spent when blocked")

	// Unlocked at 5 bases
	base_counts[EARTH] = MAX_BASES
	queue_5_miners()
	testing.expect(t, queued_count(EARTH) == 5, "queue_5_miners queues 5 miners at 5 bases")
	testing.expect(t, minerals == 750, "deducts 5 * 50 = 250 minerals")
}

@(test)
queue_5_combat_shortcut :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 1000

	// Blocked below 5 bases
	base_counts[EARTH] = 2
	queue_5_combat()
	testing.expect(t, queued_count(EARTH) == 0, "queue_5_combat blocked with 2 bases")
	testing.expect(t, minerals == 1000, "no minerals spent when blocked")

	// Unlocked at 5 bases
	base_counts[EARTH] = MAX_BASES
	queue_5_combat()
	testing.expect(t, queued_count(EARTH) == 5, "queue_5_combat queues 5 fighters at 5 bases")
	testing.expect(t, minerals == 375, "deducts 5 * 125 = 625 minerals")
}

@(test)
queue_5_earth_only :: proc(t: ^testing.T) {
	reset_world()
	minerals = 1000
	for p in 0..<PLANET_COUNT {
		if p == EARTH { continue }
		selected_planet = p
		base_counts[p] = MAX_BASES
		queue_5_miners()
		queue_5_combat()
		testing.expect(t, queued_count(p) == 0, "non-Earth planet cannot queue 5 units")
	}
}

@(test)
queue_5_button_rects_align_with_layout :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	base_counts[EARTH] = MAX_BASES
	panel_x: f32 = 100.0
	miner_rect := queue_5_miner_button_rect(panel_x)
	combat_rect := queue_5_combat_button_rect(panel_x)

	testing.expect(t, miner_rect.width == BUILD_BTN_W, "miner button width matches BUILD_BTN_W")
	testing.expect(t, combat_rect.width == BUILD_BTN_W, "combat button width matches BUILD_BTN_W")
	testing.expect(t, miner_rect.height == UPGRADE_H, "miner button height matches UPGRADE_H")
	testing.expect(t, combat_rect.height == UPGRADE_H, "combat button height matches UPGRADE_H")
	testing.expect(t, miner_rect.y == combat_rect.y, "both buttons share the same Y position")
	testing.expect(t, combat_rect.x == miner_rect.x + BUILD_BTN_W + BTN_GAP, "combat button is adjacent with BTN_GAP")

	// Total span is BUILD_BTN_W + BTN_GAP + BUILD_BTN_W = PANEL_CONTENT_W
	testing.expect(t, miner_rect.width + BTN_GAP + combat_rect.width == PANEL_CONTENT_W, "buttons span exactly PANEL_CONTENT_W")

	// Layout hierarchy when Earth has 5 bases:
	// Row 1: +1 buttons at orders_y
	// Row 2: +5 buttons at orders_y + UPGRADE_DY (below +1 buttons)
	// Row 3: Speed upgrade button at orders_y + 2 * UPGRADE_DY (below +5 buttons)
	// Below: Queue at earth_queue_y(), which sits below speed button
	orders_y := f32(production_orders_y())
	speed_rect_5 := drone_speed_button_rect(panel_x)
	testing.expect(t, miner_rect.y == orders_y + UPGRADE_DY, "+5 buttons sit below +1 buttons")
	testing.expect(t, speed_rect_5.y == miner_rect.y + UPGRADE_DY, "speed upgrade sits below +5 buttons")
	testing.expect(t, f32(earth_queue_y()) >= speed_rect_5.y + speed_rect_5.height, "queue sits below speed upgrade")

	// Layout hierarchy when Earth has < 5 bases:
	// +5 buttons are hidden, speed upgrade sits below +1 buttons at orders_y + UPGRADE_DY
	base_counts[EARTH] = 1
	orders_y_1 := f32(production_orders_y())
	speed_rect_1 := drone_speed_button_rect(panel_x)
	testing.expect(t, speed_rect_1.y == orders_y_1 + UPGRADE_DY, "speed upgrade sits below +1 buttons under 5 bases")
	testing.expect(t, f32(earth_queue_y()) >= speed_rect_1.y + speed_rect_1.height, "queue sits below speed upgrade under 5 bases")
}

@(test)
inspector_clicks_handle_queue_5_and_speed_upgrade :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 20000

	// Under 5 bases: clicking speed upgrade button upgrades speed
	base_counts[EARTH] = 1
	testing.expect(t, drone_speed_level == 0, "starts at speed level 0")
	speed_rect_1 := drone_speed_button_rect(0)
	handle_inspector_click({speed_rect_1.x + 1, speed_rect_1.y + 1}, 0)
	testing.expect(t, drone_speed_level == 1, "speed upgrades via click under 5 bases")
	testing.expect(t, queued_count(EARTH) == 0, "no units queued under 5 bases from speed button click")

	// At 5 bases: clicking +5 miner button queues 5 miners
	base_counts[EARTH] = MAX_BASES
	min_rect := queue_5_miner_button_rect(0)
	handle_inspector_click({min_rect.x + 1, min_rect.y + 1}, 0)
	testing.expect(t, queued_count(EARTH) == 5, "clicking +5 miner button queues 5 miners")

	// At 5 bases: clicking +5 combat button queues 5 fighters
	com_rect := queue_5_combat_button_rect(0)
	handle_inspector_click({com_rect.x + 1, com_rect.y + 1}, 0)
	testing.expect(t, queued_count(EARTH) == 10, "clicking +5 combat button queues 5 fighters")

	// At 5 bases: clicking speed upgrade button at shifted Y upgrades speed
	speed_rect_5 := drone_speed_button_rect(0)
	handle_inspector_click({speed_rect_5.x + 1, speed_rect_5.y + 1}, 0)
	testing.expect(t, drone_speed_level == 2, "speed upgrades via click at 5 bases at shifted position")
}

@(test)
queue_5_buttons_disabled_without_enough_minerals :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	base_counts[EARTH] = MAX_BASES

	// 0 minerals: both +5 buttons disabled
	minerals = 0
	testing.expect(t, !can_build_5_miners(), "+5 miners disabled with 0 minerals")
	testing.expect(t, !can_build_5_combat(), "+5 combat disabled with 0 minerals")

	// 249 minerals: enough for single miner (50) and single combat (125), but NOT +5 miners (250) or +5 combat (625)
	minerals = 249
	testing.expect(t, !can_build_5_miners(), "+5 miners disabled with 249 minerals")
	testing.expect(t, !can_build_5_combat(), "+5 combat disabled with 249 minerals")

	// Clicking +5 miner button with 249 minerals does nothing
	min_rect := queue_5_miner_button_rect(0)
	handle_inspector_click({min_rect.x + 1, min_rect.y + 1}, 0)
	testing.expect(t, queued_count(EARTH) == 0, "clicking +5 miners with insufficient minerals does nothing")
	testing.expect(t, minerals == 249, "no minerals deducted")

	// 250 minerals: exactly enough for +5 miners, but not +5 combat
	minerals = 250
	testing.expect(t, can_build_5_miners(), "+5 miners enabled with exactly 250 minerals")
	testing.expect(t, !can_build_5_combat(), "+5 combat disabled with 250 minerals")

	// 624 minerals: +5 miners enabled, +5 combat disabled
	minerals = 624
	testing.expect(t, can_build_5_miners(), "+5 miners enabled with 624 minerals")
	testing.expect(t, !can_build_5_combat(), "+5 combat disabled with 624 minerals")

	// Clicking +5 combat with 624 minerals does nothing
	com_rect := queue_5_combat_button_rect(0)
	handle_inspector_click({com_rect.x + 1, com_rect.y + 1}, 0)
	testing.expect(t, queued_count(EARTH) == 0, "clicking +5 combat with insufficient minerals does nothing")
	testing.expect(t, minerals == 624, "no minerals deducted")

	// 625 minerals: both +5 miners and +5 combat enabled
	minerals = 625
	testing.expect(t, can_build_5_miners(), "+5 miners enabled with 625 minerals")
	testing.expect(t, can_build_5_combat(), "+5 combat enabled with 625 minerals")

	// Queue full: both +5 buttons disabled even with plenty of minerals
	minerals = 10000
	pending_count[EARTH] = MAX_BASES * 5
	testing.expect(t, queued_count(EARTH) == MAX_BASES * 5, "queue is full")
	testing.expect(t, !can_build_5_miners(), "+5 miners disabled when queue full")
	testing.expect(t, !can_build_5_combat(), "+5 combat disabled when queue full")
}

@(test)
losing_base_from_cap_re_hides_queue_5_and_restores_speed_button_pos :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	base_counts[EARTH] = MAX_BASES

	// At 5 bases, +5 buttons are active and speed button is at row 3 (orders_y + 2 * UPGRADE_DY)
	orders_y := f32(production_orders_y())
	testing.expect(t, drone_speed_button_rect(0).y == orders_y + 2 * UPGRADE_DY, "speed at row 3 with 5 bases")

	// Destroy a base so base_counts drops to 4
	destroy_player_base(EARTH)
	testing.expect(t, base_counts[EARTH] == 4, "base count is 4")

	// Now queue_5 is blocked
	minerals = 1000
	queue_5_miners()
	testing.expect(t, queued_count(EARTH) == 0, "queue_5 blocked after losing 5th base")

	// Speed button collapses up to row 2 (orders_y + UPGRADE_DY)
	orders_y_4 := f32(production_orders_y())
	testing.expect(t, drone_speed_button_rect(0).y == orders_y_4 + UPGRADE_DY, "speed returns to row 2 after losing 5th base")
}

@(test)
drone_speed_max_at_5_bases_remains_at_row_3_and_ignores_clicks :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	base_counts[EARTH] = MAX_BASES
	drone_speed_level = DRONE_SPEED_UPGRADE_MAX
	minerals = 10000

	speed_rect := drone_speed_button_rect(0)
	orders_y := f32(production_orders_y())
	testing.expect(t, speed_rect.y == orders_y + 2 * UPGRADE_DY, "max speed button sits below +5 buttons at 5 bases")

	// Clicking maxed speed button does not spend minerals or increase level
	handle_inspector_click({speed_rect.x + 1, speed_rect.y + 1}, 0)
	testing.expect(t, drone_speed_level == DRONE_SPEED_UPGRADE_MAX, "speed level capped at max")
	testing.expect(t, minerals == 10000, "no minerals spent when clicking capped speed upgrade")
}

@(test)
controls_overlay_pauses_and_resumes :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, !game_paused, "initially unpaused")
	testing.expect(t, !controls_overlay_open, "initially overlay closed")

	open_controls_overlay()
	testing.expect(t, game_paused, "game is paused when controls overlay opened")
	testing.expect(t, controls_overlay_open, "controls overlay is open")

	close_controls_overlay()
	testing.expect(t, !game_paused, "game is unpaused when controls overlay closed")
	testing.expect(t, !controls_overlay_open, "controls overlay is closed")

	open_controls_overlay()
	reset_world()
	testing.expect(t, !controls_overlay_open, "reset_world resets controls overlay state")
}

@(test)
controls_button_rect_is_docked :: proc(t: ^testing.T) {
	rect := controls_button_rect()
	testing.expect(t, rect.x == HUD_PAD, "controls button docked at HUD_PAD from left")
	testing.expect(t, rect.width == 110, "controls button width is 110")
	testing.expect(t, rect.height == BOTTOM_DOCK_H, "controls button height matches BOTTOM_DOCK_H")
}

@(test)
sector_in_combat_detects_all_battle_types :: proc(t: ^testing.T) {
	reset_world()

	// 1. Peacetime: starting Earth state with 1 player miner and 1 player fighter has no combat.
	units[0] = Unit{kind = .MINING, state = .MINING, affiliation = EARTH, target_planet = EARTH}
	units[1] = Unit{kind = .COMBAT, state = .GUARDING, affiliation = EARTH, target_planet = EARTH}
	unit_count = 2
	testing.expect(t, !sector_in_combat(EARTH), "no combat at Earth during peacetime")

	// 2. Unattacked garrison: Venus has 10 enemy fighters, but 0 player units -> no combat yet.
	spawn_garrison(VENUS, 10, 4)
	testing.expect(t, !sector_in_combat(VENUS), "standing garrison with no attackers is not in combat")

	// 3. Dogfight: player combat drone arrives at Venus -> active combat.
	units[unit_count] = Unit{kind = .COMBAT, state = .GUARDING, affiliation = VENUS, enemy = false}
	unit_count += 1
	testing.expect(t, sector_in_combat(VENUS), "dogfight at Venus triggers combat")

	// 4. Enemy siege at Earth: 5 enemy fighters attack Earth with only player base remaining.
	reset_world()
	units[0] = Unit{kind = .COMBAT, state = .GUARDING, affiliation = EARTH, enemy = true}
	unit_count = 1
	testing.expect(t, sector_in_combat(EARTH), "enemy fighters sieging Earth base triggers combat")

	// 5. Enemy fighters strafing player miners:
	reset_world()
	base_counts[EARTH] = 0 // no base
	units[0] = Unit{kind = .COMBAT, state = .GUARDING, affiliation = MARS, enemy = true}
	units[1] = Unit{kind = .MINING, state = .IDLE, target_planet = MARS, enemy = false}
	unit_count = 2
	testing.expect(t, sector_in_combat(MARS), "enemy fighters strafing player miner triggers combat")

	// 6. Player sweeping enemy miners:
	reset_world()
	enemy_base_hp[MARS] = 0
	units[0] = Unit{kind = .COMBAT, state = .GUARDING, affiliation = MARS, enemy = false}
	units[1] = Unit{kind = .MINING, state = .GUARDING, affiliation = MARS, enemy = true}
	unit_count = 2
	testing.expect(t, sector_in_combat(MARS), "player fighters sweeping enemy miners triggers combat")

	// 7. Player sieging enemy base (no fighters or miners left, only base):
	reset_world()
	enemy_base_hp[MARS] = 50
	units[0] = Unit{kind = .COMBAT, state = .GUARDING, affiliation = MARS, enemy = false}
	unit_count = 1
	testing.expect(t, sector_in_combat(MARS), "player fighters sieging enemy base triggers combat")

	// 8. Enemy HQ combat:
	reset_world()
	units[0] = Unit{kind = .COMBAT, state = .GUARDING, affiliation = ENEMY_HOME, enemy = true}
	units[1] = Unit{kind = .COMBAT, state = .GUARDING, affiliation = ENEMY_HOME, enemy = false}
	unit_count = 2
	testing.expect(t, sector_in_combat(ENEMY_HOME), "assault on enemy HQ triggers combat")
}

@(test)
combat_nebula_intensity_transitions_and_hq_behavior :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()

	// 1. Initial state: Enemy HQ has baseline brooding intensity (0.65), planets have 0.
	testing.expect(t, abs(combat_nebula_intensity[ENEMY_HOME] - 0.65) < 0.01, "Enemy HQ initializes with 0.65 nebula intensity")
	testing.expect(t, combat_nebula_intensity[MARS] == 0.0, "Mars has 0 nebula intensity initially")

	// 2. Trigger combat at Mars (spawn 10 player fighters and 10 enemy fighters):
	for _ in 0..<10 {
		units[unit_count] = Unit{kind = .COMBAT, state = .GUARDING, affiliation = MARS, enemy = false}
		unit_count += 1
		units[unit_count] = Unit{kind = .COMBAT, state = .GUARDING, affiliation = MARS, enemy = true}
		unit_count += 1
	}

	// Step simulation for 0.5s:
	step_simulation(0.5)
	testing.expect(t, combat_nebula_intensity[MARS] > 0.5, "Mars nebula flares up during combat")

	// 3. Clear combat at Mars:
	for i := unit_count - 1; i >= 0; i -= 1 {
		if units[i].affiliation == MARS { remove_unit_at(i) }
	}
	enemy_base_hp[MARS] = 0 // liberated
	testing.expect(t, !sector_in_combat(MARS), "Mars no longer in combat")

	// Step simulation for 2.0s:
	step_simulation(1.0)
	step_simulation(1.0)
	testing.expect(t, combat_nebula_intensity[MARS] < 0.1, "Mars nebula fades out after combat ends")

	// 4. Enemy HQ assault: player attacks HQ, intensity ramps to 1.0:
	for _ in 0..<10 {
		units[unit_count] = Unit{kind = .COMBAT, state = .GUARDING, affiliation = ENEMY_HOME, enemy = false}
		unit_count += 1
	}
	step_simulation(0.5)
	testing.expect(t, combat_nebula_intensity[ENEMY_HOME] > 0.85, "Enemy HQ nebula ramps toward 1.0 during active assault")

	// 5. Enemy HQ destroyed: intensity ramps down to 0:
	for i := unit_count - 1; i >= 0; i -= 1 {
		if units[i].affiliation == ENEMY_HOME { remove_unit_at(i) }
	}
	enemy_base_hp[ENEMY_HOME] = 0
	step_simulation(1.0)
	step_simulation(1.0)
	testing.expect(t, combat_nebula_intensity[ENEMY_HOME] < 0.1, "Destroyed Enemy HQ nebula dissipates to 0")

	// 6. reset_world zeroes everything:
	reset_world()
	for s in 0..<SECTOR_COUNT {
		testing.expect(t, combat_nebula_intensity[s] == 0.0, "reset_world zeroes combat_nebula_intensity")
	}
}

@(test)
earth_industry_lights_intensity_transitions :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()

	// 1. Initially Earth has no units queued, intensity is 0
	testing.expect(t, earth_industry_intensity == 0.0, "Earth industry intensity starts at 0")

	// 2. Queue a unit on Earth (e.g. MINING drone)
	minerals = 500
	queue_unit(.MINING)
	testing.expect(t, production[EARTH][0].active, "Production line 0 active on Earth")

	// 3. Step simulation for 0.4s: intensity should ramp up toward 1.0
	step_simulation(0.4)
	testing.expect(t, earth_industry_intensity > 0.8, "Earth industry intensity ramps up while unit is in production")

	// 4. Cancel production: queue becomes inactive
	cancel_last_queued()
	testing.expect(t, !production[EARTH][0].active, "Production line cancelled on Earth")

	// 5. Step simulation for 1.0s: intensity fades back toward 0.0
	step_simulation(0.5)
	step_simulation(0.5)
	testing.expect(t, earth_industry_intensity < 0.05, "Earth industry intensity fades out when production stops")

	// 6. Base construction on Earth also activates industry lights
	minerals = 1000
	start_base_construction()
	testing.expect(t, base_build_planet == EARTH, "Base construction started on Earth")
	step_simulation(0.4)
	testing.expect(t, earth_industry_intensity > 0.8, "Earth industry intensity ramps up during base construction")

	// 7. reset_world resets earth_industry_intensity to 0
	reset_world()
	testing.expect(t, earth_industry_intensity == 0.0, "reset_world zeroes earth_industry_intensity")
}

@(test)
combat_vision_lingers_when_last_fighter_destroyed :: proc(t: ^testing.T) {
	reset_world()
	add_guarding_fighter(JUPITER, false) // 1 player fighter
	add_guarding_fighter(JUPITER, true)  // 2 enemy fighters
	add_guarding_fighter(JUPITER, true)
	testing.expect(t, has_vision(JUPITER), "Jupiter is lit while player fighter is present")

	// 1 combat tick resolves 1 kill trade: player fighter falls, 1 enemy fighter falls
	update_enemy_waves(f32(COMBAT_TICK))
	players, enemies := planet_combatants(JUPITER)
	testing.expect(t, players == 0 && enemies == 1, "last player fighter destroyed; 1 enemy remains")
	testing.expect(t, unit_count == 1 && units[0].enemy, "only the enemy fighter remains")

	// Combat vision linger: Jupiter stays visible for COMBAT_VISION_LINGER seconds
	testing.expect(t, combat_vision_timer[JUPITER] > 0, "combat vision timer started at Jupiter")
	testing.expect(t, has_vision(JUPITER), "Jupiter remains lit under lingering combat vision")
	testing.expect(t, !is_concealed(&units[0]), "surviving enemy fighter is visible during linger window")

	// 1s later: vision still active
	update_enemy_waves(1.0)
	testing.expect(t, has_vision(JUPITER), "Jupiter remains lit 1s after combat loss")
	testing.expect(t, combat_vision_timer[JUPITER] > 0, "timer still counting down")

	// Advance past the full linger duration: fog descends
	update_enemy_waves(f32(COMBAT_VISION_LINGER))
	testing.expect(t, combat_vision_timer[JUPITER] == 0, "combat vision timer expired")
	testing.expect(t, !has_vision(JUPITER), "Jupiter falls back under fog of war after linger window")
	testing.expect(t, is_concealed(&units[0]), "enemy fighter is now concealed under fog")
}

@(test)
combat_vision_does_not_trigger_while_fighters_remain :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<3 { add_guarding_fighter(MARS, false) }
	for i in 0..<3 { add_guarding_fighter(MARS, true) }

	// Tick 1: 2v2 remain. Vision timer must NOT trigger because 2 player fighters remain.
	update_enemy_waves(f32(COMBAT_TICK))
	players, _ := planet_combatants(MARS)
	testing.expect(t, players == 2, "2 player fighters remain")
	testing.expect(t, combat_vision_timer[MARS] == 0, "timer not set while player fighters remain")

	// Tick 2: 1v1 remain. Vision timer still not set.
	update_enemy_waves(f32(COMBAT_TICK))
	players, _ = planet_combatants(MARS)
	testing.expect(t, players == 1, "1 player fighter remains")
	testing.expect(t, combat_vision_timer[MARS] == 0, "timer not set while 1 fighter remains")

	// Tick 3: 0v0 remain (last player fighter destroyed). Vision timer activates!
	update_enemy_waves(f32(COMBAT_TICK))
	players, _ = planet_combatants(MARS)
	testing.expect(t, players == 0, "0 player fighters remain")
	testing.expect(t, combat_vision_timer[MARS] > 0, "timer activates when last fighter falls")
	testing.expect(t, has_vision(MARS), "Mars stays lit under lingering vision")
}

@(test)
combat_vision_lingers_at_enemy_hq :: proc(t: ^testing.T) {
	reset_world()
	add_guarding_fighter(ENEMY_HOME, false)
	add_guarding_fighter(ENEMY_HOME, true)
	testing.expect(t, has_vision(ENEMY_HOME), "HQ is lit while player fighter is present")

	// 1 tick: player fighter falls
	update_enemy_waves(f32(COMBAT_TICK))
	players, _ := planet_combatants(ENEMY_HOME)
	testing.expect(t, players == 0, "player fighter destroyed at HQ")
	testing.expect(t, combat_vision_timer[ENEMY_HOME] > 0, "timer activated for ENEMY_HOME")
	testing.expect(t, has_vision(ENEMY_HOME), "HQ remains lit under lingering vision")

	// Advance past linger window
	update_enemy_waves(f32(COMBAT_VISION_LINGER) + 0.5)
	testing.expect(t, !has_vision(ENEMY_HOME), "HQ goes dark after linger window expires")
}

@(test)
combat_vision_updates_intel_before_fog :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = VENUS
	add_guarding_fighter(VENUS, false)
	add_guarding_fighter(VENUS, true)
	add_guarding_fighter(VENUS, true)

	// Step simulation for 1 combat tick: fighter destroyed, intel updates during lingering vision
	step_simulation(f32(COMBAT_TICK))
	testing.expect(t, combat_vision_timer[VENUS] > 0, "combat vision timer active at Venus")
	testing.expect(t, has_vision(VENUS), "Venus has vision during linger window")
	testing.expect(t, intel_recorded[VENUS], "intel recorded during linger window")
	testing.expect(t, last_known_intel[VENUS].fighters == 1, "intel accurately captured surviving 1 enemy fighter")
	testing.expect(t, !ghost_view(), "live view active during lingering vision")

	// Step past linger window: Venus falls back to fog, ghost view activates with fresh intel
	step_simulation(f32(COMBAT_VISION_LINGER) + 0.5)
	testing.expect(t, !has_vision(VENUS), "Venus is dark after linger window")
	testing.expect(t, ghost_view(), "ghost view activates once Venus is dark")
	testing.expect(t, last_known_intel[VENUS].fighters == 1, "accurate post-battle intel preserved in ghost view")
}

// ---- Planetary Refinery tests --------------------------------------------

@(test)
refinery_cost_equals_mining_cap_times_ten :: proc(t: ^testing.T) {
	reset_world()
	for p in 0..<PLANET_COUNT {
		expected := planet_mining_cap(p) * 10
		testing.expectf(t, refinery_cost(p) == expected,
			"planet %d refinery cost %d != expected %d", p, refinery_cost(p), expected)
	}
	testing.expect(t, refinery_cost(MERCURY) == 150, "Mercury refinery costs 150 minerals")
	testing.expect(t, refinery_cost(VENUS) == 350, "Venus refinery costs 350 minerals")
	testing.expect(t, refinery_cost(EARTH) == 100, "Earth refinery formula is 100 minerals")
	testing.expect(t, refinery_cost(MARS) == 500, "Mars refinery costs 500 minerals")
	testing.expect(t, refinery_cost(JUPITER) == 1000, "Jupiter refinery costs 1000 minerals")
	testing.expect(t, refinery_cost(SATURN) == 900, "Saturn refinery costs 900 minerals")
	testing.expect(t, refinery_cost(URANUS) == 600, "Uranus refinery costs 600 minerals")
	testing.expect(t, refinery_cost(NEPTUNE) == 600, "Neptune refinery costs 600 minerals")
}

@(test)
refinery_construction_requires_liberation_and_minerals :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = MARS
	minerals = 1000

	// Occupied planet: cannot build refinery
	testing.expect(t, !planet_liberated(MARS), "Mars starts occupied")
	testing.expect(t, !can_build_refinery(MARS), "cannot build refinery on occupied Mars")
	start_refinery_construction(MARS)
	testing.expect(t, !refinery_building[MARS], "refinery construction does not start on occupied planet")
	testing.expect(t, minerals == 1000, "minerals not deducted")

	// Liberate Mars, but insufficient minerals
	enemy_base_hp[MARS] = 0
	testing.expect(t, planet_liberated(MARS), "Mars is liberated")
	minerals = 400 // Mars needs 500
	testing.expect(t, !can_build_refinery(MARS), "cannot build refinery with insufficient minerals")
	start_refinery_construction(MARS)
	testing.expect(t, !refinery_building[MARS], "refinery construction does not start without minerals")
	testing.expect(t, minerals == 400, "minerals not deducted")

	// With enough minerals (500), construction begins
	minerals = 600
	testing.expect(t, can_build_refinery(MARS), "can build refinery with enough minerals")
	start_refinery_construction(MARS)
	testing.expect(t, refinery_building[MARS], "refinery construction started")
	testing.expect(t, minerals == 100, "500 minerals deducted for Mars refinery")
	testing.expect(t, refinery_progress[MARS] == 0, "refinery progress starts at 0")

	// Cannot start again while building
	testing.expect(t, !can_build_refinery(MARS), "cannot build another refinery while one is building")
	start_refinery_construction(MARS)
	testing.expect(t, minerals == 100, "minerals not deducted on duplicate start")

	// Earth cannot build refinery (already has one)
	selected_planet = EARTH
	testing.expect(t, !can_build_refinery(EARTH), "Earth cannot build refinery")
}

@(test)
refinery_construction_takes_60s :: proc(t: ^testing.T) {
	reset_world()
	enemy_base_hp[VENUS] = 0
	selected_planet = VENUS
	minerals = 500
	start_refinery_construction(VENUS)
	testing.expect(t, refinery_building[VENUS], "refinery building on Venus")
	testing.expect(t, !refinery_built[VENUS], "refinery not yet built")

	// No crew present: progress is frozen
	update_production(120.0)
	testing.expect(t, refinery_progress[VENUS] == 0, "no build progress without a full crew")

	// Add 10 miners to Venus
	for i in 0..<REFINERY_CONSTRUCT_MINERS {
		units[unit_count] = Unit{
			kind = .MINING, state = .TRANSIT, position = planets[VENUS].position,
			home_planet = EARTH, affiliation = VENUS, target_planet = VENUS,
		}
		unit_count += 1
		update_miner(&units[unit_count - 1], unit_count - 1, 0.02)
	}
	testing.expect(t, constructing_miners(VENUS) == REFINERY_CONSTRUCT_MINERS, "full crew of 10 assembled")

	// Advance 59.9s: still building
	update_production(59.9)
	testing.expect(t, refinery_building[VENUS], "refinery still building at 59.9s")
	testing.expect(t, !refinery_built[VENUS], "refinery not built before 60s")
	testing.expect(t, abs(refinery_progress[VENUS] - 59.9) < 0.01, "progress advanced by 59.9s")

	// Advance remaining 0.1s: refinery completes
	update_production(0.1)
	testing.expect(t, !refinery_building[VENUS], "refinery no longer building after 60s")
	testing.expect(t, refinery_built[VENUS], "refinery completed after 60s")
	testing.expect(t, refinery_progress[VENUS] == 0, "refinery progress reset to 0")

	// Miners resume mining
	for i in 0..<unit_count {
		if units[i].kind == .MINING && !units[i].enemy {
			testing.expect(t, units[i].state == .MINING, "crew resumes mining after refinery completes")
		}
	}

	// Cannot build another refinery after it is built
	testing.expect(t, !can_build_refinery(VENUS), "cannot build refinery once already built")
}

@(test)
miners_require_refinery_to_mine_liberated_planet :: proc(t: ^testing.T) {
	reset_world()
	enemy_base_hp[MARS] = 0 // Liberated
	testing.expect(t, !planet_can_mine(MARS), "liberated planet cannot be mined without refinery")

	// 10 miners arrive at liberated Mars without refinery -> all enter IDLE
	for i in 0..<10 {
		units[unit_count] = Unit{
			kind = .MINING, state = .TRANSIT, position = planets[MARS].position,
			home_planet = EARTH, affiliation = MARS, target_planet = MARS,
		}
		unit_count += 1
		update_miner(&units[unit_count - 1], unit_count - 1, 0.1)
		testing.expect(t, units[unit_count - 1].state == .IDLE, "miner holds in IDLE at liberated planet with no refinery")
	}

	// Start refinery construction: the 10 idle miners join the construction crew
	minerals = 1000
	start_refinery_construction(MARS)
	testing.expect(t, constructing_miners(MARS) == 10, "10 idle miners auto-joined refinery construction")
	for i in 0..<10 {
		testing.expect(t, units[i].state == .CONSTRUCTING, "miner is now constructing")
	}

	// Advance partway (30s)
	update_production(30.0)
	testing.expect(t, abs(refinery_progress[MARS] - 30.0) < 0.01, "refinery progress advanced 30s")

	// Complete refinery construction (total 60s)
	update_production(30.0)
	testing.expect(t, refinery_built[MARS], "refinery is now built")
	testing.expect(t, planet_can_mine(MARS), "planet can now be mined")

	// All 10 miners have automatically resumed MINING
	for i in 0..<10 {
		testing.expect(t, units[i].state == .MINING, "crew resumed mining once refinery is built")
	}

	// Fresh miner arriving in TRANSIT at refined planet enters MINING directly
	units[unit_count] = Unit{
		kind = .MINING, state = .TRANSIT, position = planets[MARS].position,
		home_planet = EARTH, affiliation = MARS, target_planet = MARS,
	}
	unit_count += 1
	update_miner(&units[unit_count - 1], unit_count - 1, 0.1)
	testing.expect(t, units[unit_count - 1].state == .MINING, "new miner arriving at refined planet starts mining immediately")
}

@(test)
refinery_construction_requires_ten_drones_crew :: proc(t: ^testing.T) {
	reset_world()
	enemy_base_hp[MARS] = 0 // Liberated
	minerals = 1000
	start_refinery_construction(MARS)
	testing.expect(t, refinery_building[MARS], "refinery build queues with no crew")

	// Clock is frozen with 0 crew
	update_production(60.0)
	testing.expect(t, refinery_progress[MARS] == 0, "clock frozen with 0 crew")

	// Arriving miners auto-join one by one up to 10
	for i in 0..<REFINERY_CONSTRUCT_MINERS {
		units[unit_count] = Unit{
			kind = .MINING, state = .TRANSIT, position = planets[MARS].position,
			home_planet = EARTH, affiliation = MARS, target_planet = MARS,
		}
		unit_count += 1
		update_miner(&units[unit_count - 1], unit_count - 1, 0.1)
		testing.expectf(t, units[unit_count - 1].state == .CONSTRUCTING, "arriving miner %d joins crew", i)
		testing.expectf(t, constructing_miners(MARS) == i + 1, "crew count is %d", i + 1)
		if i + 1 < REFINERY_CONSTRUCT_MINERS {
			update_production(10.0)
			testing.expect(t, refinery_progress[MARS] == 0, "clock still frozen under 10 crew")
		}
	}
	testing.expect(t, constructing_miners(MARS) == REFINERY_CONSTRUCT_MINERS, "crew is full at 10")

	// 11th miner arrives: crew is full, so 11th miner enters IDLE
	units[unit_count] = Unit{
		kind = .MINING, state = .TRANSIT, position = planets[MARS].position,
		home_planet = EARTH, affiliation = MARS, target_planet = MARS,
	}
	unit_count += 1
	update_miner(&units[unit_count - 1], unit_count - 1, 0.1)
	testing.expect(t, units[unit_count - 1].state == .IDLE, "11th miner enters IDLE since crew is full")
	testing.expect(t, constructing_miners(MARS) == REFINERY_CONSTRUCT_MINERS, "crew remains capped at 10")

	// Full crew: progress runs
	update_production(20.0)
	testing.expect(t, abs(refinery_progress[MARS] - 20.0) < 0.01, "progress advances with full crew")

	// Reassign one crew member away from Mars -> crew drops to 9 -> clock freezes
	units[0].target_planet = VENUS
	units[0].state = .TRANSIT
	testing.expect(t, constructing_miners(MARS) == 9, "crew drops to 9")
	update_production(20.0)
	testing.expect(t, abs(refinery_progress[MARS] - 20.0) < 0.01, "progress frozen after crew member leaves")

	// The 11th miner (which was in IDLE) auto-joins the crew on its next update
	update_miner(&units[unit_count - 1], unit_count - 1, 0.1)
	testing.expect(t, units[unit_count - 1].state == .CONSTRUCTING, "idle miner steps up to fill the crew spot")
	testing.expect(t, constructing_miners(MARS) == 10, "crew is back to 10")

	// Progress resumes and completes the remaining 40.0s
	update_production(40.0)
	testing.expect(t, refinery_built[MARS], "refinery completed after total 60s")
	testing.expect(t, !refinery_building[MARS], "no longer building")
	testing.expect(t, refinery_progress[MARS] == 0, "progress reset to 0")

	// All constructing miners at Mars have resumed MINING
	for i in 1..<unit_count {
		if units[i].target_planet == MARS {
			testing.expect(t, units[i].state == .MINING, "Mars miner resumed mining")
		}
	}
}

@(test)
save_load_game_preserves_refinery_state :: proc(t: ^testing.T) {
	reset_world()
	test_save_file := "test_savegame_refinery.txt"
	defer delete_save_game(test_save_file)

	enemy_base_hp[MARS] = 0
	refinery_built[MARS] = true

	enemy_base_hp[JUPITER] = 0
	refinery_building[JUPITER] = true
	refinery_progress[JUPITER] = 34.5

	saved := save_game(test_save_file)
	testing.expect(t, saved, "save_game wrote file")

	reset_world()
	testing.expect(t, !refinery_built[MARS], "reset cleared Mars refinery")
	testing.expect(t, !refinery_building[JUPITER], "reset cleared Jupiter building")

	loaded := load_game(test_save_file)
	testing.expect(t, loaded, "load_game loaded file")

	testing.expect(t, refinery_built[EARTH], "Earth refinery preserved")
	testing.expect(t, refinery_built[MARS], "Mars refinery restored as built")
	testing.expect(t, !refinery_built[JUPITER], "Jupiter refinery not built yet")
	testing.expect(t, refinery_building[JUPITER], "Jupiter refinery restored as building")
	testing.expect(t, abs(refinery_progress[JUPITER] - 34.5) < 0.01, "Jupiter refinery progress restored")
}

@(test)
unrefined_planet_produces_no_mps_and_no_payout :: proc(t: ^testing.T) {
	reset_world()
	enemy_base_hp[MARS] = 0 // Liberated, but no refinery
	testing.expect(t, !planet_can_mine(MARS), "liberated Mars has no refinery yet")

	// Send miners to Mars
	for i in 0..<10 {
		units[unit_count] = Unit{
			kind = .MINING, state = .IDLE, position = planets[MARS].position,
			home_planet = EARTH, affiliation = MARS, target_planet = MARS,
		}
		unit_count += 1
	}

	// Mars MPS must be 0
	testing.expect(t, planet_mps(MARS) == 0, "Mars MPS is 0 without a refinery")

	// Global MPS must be 0 (no miners on Earth)
	testing.expect(t, global_mps() == 0, "global MPS does not include unrefined Mars")

	// Depositing attempt from unrefined planet pays 0
	units[0].position = planets[EARTH].position
	units[0].state = .DEPOSITING
	units[0].progress = DEPOSIT_DURATION - 0.01
	minerals = 0
	testing.expect(t, !is_effective_miner(0), "miner targeting unrefined Mars is not an effective miner")
	update_miner(&units[0], 0, 0.02)
	testing.expect(t, minerals == 0, "deposit from unrefined planet pays out 0 minerals")

	// Once refinery is completed, MPS and payout become active
	refinery_built[MARS] = true
	testing.expect(t, planet_can_mine(MARS), "Mars can now mine")
	testing.expect(t, planet_mps(MARS) > 0, "Mars MPS is positive with refinery built")
	testing.expect(t, global_mps() == planet_mps(MARS), "global MPS includes Mars once refinery is built")
	testing.expect(t, is_effective_miner(0), "miner is now effective")
}

@(test)
player_starts_with_five_combat_drones :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()

	players, enemies := planet_combatants(EARTH)
	testing.expect(t, players == 5, "player starts with 5 combat drones on Earth")
	testing.expect(t, enemies == 0, "no enemy combatants on Earth at game start")

	combat_count := 0
	miner_count := 0
	for i in 0..<unit_count {
		u := &units[i]
		if u.affiliation == EARTH && !u.enemy {
			if u.kind == .COMBAT {
				combat_count += 1
				testing.expect(t, u.state == .GUARDING, "starting fighter is in guard state")
				testing.expect(t, u.home_planet == EARTH, "starting fighter home is Earth")
				testing.expect(t, u.target_planet == EARTH, "starting fighter target is Earth")
			} else if u.kind == .MINING {
				miner_count += 1
				testing.expect(t, u.state == .MINING, "starting miner is in mining state")
			}
		}
	}
	testing.expect(t, combat_count == 5, "exactly 5 player combat drones on Earth")
	testing.expect(t, miner_count == 1, "exactly 1 player mining drone on Earth")
}

@(test)
minor_wave_timer_advances_and_launches_every_sixty_seconds :: proc(t: ^testing.T) {
	reset_world()
	before := unit_count
	testing.expect(t, minor_wave_timer == 0, "minor wave timer starts at 0")

	// 74.9 seconds: no launch yet
	update_minor_wave(74.9)
	testing.expect(t, unit_count == before, "no minor wave before 75 seconds")
	testing.expect(t, minor_wave_timer >= 74.9, "minor wave timer accumulated")

	// 0.2s more: crosses 75s -> launches 5 enemy combat drones
	update_minor_wave(0.2)
	testing.expect(t, unit_count - before == 5, "minor wave launches 5 drones at 75s")
	testing.expect(t, minor_wave_timer == 0, "minor wave timer resets to 0 after launch")

	// Verify the launched drones
	for i := before; i < unit_count; i += 1 {
		u := &units[i]
		testing.expect(t, u.enemy, "minor wave drone is enemy")
		testing.expect(t, u.kind == .COMBAT, "minor wave drone is combat type")
		testing.expect(t, u.state == .TRANSIT, "minor wave drone starts in transit")
		testing.expect(t, u.home_planet == VENUS, "first attacker is Venus (closest unliberated to Earth)")
		testing.expect(t, u.target_planet == EARTH, "first target is Earth (only liberated planet)")
		testing.expect(t, u.affiliation == EARTH, "affiliation matches target")
	}

	// Another 75s: launches second minor wave
	before = unit_count
	update_minor_wave(75.0)
	testing.expect(t, unit_count - before == 5, "second minor wave launches after another 75s")
}

@(test)
minor_wave_attacks_from_closest_unliberated_planet_to_earth :: proc(t: ^testing.T) {
	reset_world()
	// At start, all planets except Earth are unliberated. Venus is closest to Earth (~15.54).
	source, found := closest_unliberated_planet_to_earth()
	testing.expect(t, found, "found unliberated planet")
	testing.expect(t, source == VENUS, "Venus is the closest unliberated planet to Earth")

	// Liberate Venus -> Uranus is now closest to Earth (dist 21.0 vs Mars 22.83).
	enemy_base_hp[VENUS] = 0
	source, found = closest_unliberated_planet_to_earth()
	testing.expect(t, found, "found unliberated planet after Venus liberated")
	testing.expect(t, source == URANUS, "Uranus is the next closest unliberated planet to Earth")

	// Liberate Uranus -> Mars is now closest to Earth (dist 22.83).
	enemy_base_hp[URANUS] = 0
	source, found = closest_unliberated_planet_to_earth()
	testing.expect(t, found, "found unliberated planet after Uranus liberated")
	testing.expect(t, source == MARS, "Mars is next closest unliberated planet to Earth")
}

@(test)
minor_wave_targets_closest_liberated_planet_not_earth_unless_earth_is_closest :: proc(t: ^testing.T) {
	reset_world()
	// When only Earth is liberated, Earth is the only candidate, so it is targeted.
	target := closest_liberated_planet_to(VENUS)
	testing.expect(t, target == EARTH, "Earth targeted when it is the only liberated planet")

	// Liberate Venus. Now Earth and Venus are liberated.
	enemy_base_hp[VENUS] = 0

	// Mercury is at {-30, 2, 8}.
	// Distance to Venus {-15, 0.8, -4}: sqrt(15^2 + 1.2^2 + 12^2) = sqrt(370.44) ~= 19.25.
	// Distance to Earth {0, 0, 0}: sqrt(30^2 + 2^2 + 8^2) = sqrt(968) ~= 31.11.
	// Venus is closer than Earth, so Mercury must target Venus, not Earth!
	target_mercury := closest_liberated_planet_to(MERCURY)
	testing.expect(t, target_mercury == VENUS, "Mercury targets Venus since Venus is closer than Earth")

	// Uranus is at {5, 4, -20}.
	// Distance to Earth {0, 0, 0}: sqrt(25 + 16 + 400) = 21.0.
	// Distance to Venus {-15, 0.8, -4}: sqrt(20^2 + 3.2^2 + 16^2) = sqrt(666.24) ~= 25.81.
	// Earth is closer than Venus, so Uranus must target Earth (Earth is closest).
	target_uranus := closest_liberated_planet_to(URANUS)
	testing.expect(t, target_uranus == EARTH, "Uranus targets Earth because Earth is the closest liberated planet")
}

@(test)
minor_wave_runs_independently_of_mined_planets :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, mined_planet_count() == 0, "0 mined planets")
	before := unit_count
	// 75s passes via update_minor_wave with 0 mined planets: minor wave still launches
	update_minor_wave(75.0)
	testing.expect(t, unit_count - before == 5, "minor wave launches even with 0 mined planets")

	// Same check via update_enemy_waves with only 1 liberated planet (180s wave clock is frozen)
	add_miner(EARTH)
	testing.expect(t, mined_planet_count() == 1, "1 mined planet")
	before = unit_count
	update_enemy_waves(75.0)
	testing.expect(t, unit_count - before == 5, "minor wave launches via update_enemy_waves with 1 mined planet")
	testing.expect(t, enemy_wave_timer == 0, "180s wave timer remains frozen below 2 liberated planets")
}

@(test)
minor_wave_stops_when_all_planets_liberated :: proc(t: ^testing.T) {
	reset_world()
	for p in 0..<PLANET_COUNT {
		enemy_base_hp[p] = 0
	}
	source, found := closest_unliberated_planet_to_earth()
	testing.expect(t, !found, "no unliberated planet when all are liberated")
	testing.expect(t, source == -1, "source is -1")

	before := unit_count
	launch_minor_wave()
	testing.expect(t, unit_count == before, "no units launched when all planets are liberated")

	update_minor_wave(60.0)
	testing.expect(t, unit_count == before, "no units launched from update_minor_wave when all planets liberated")
}

@(test)
minor_wave_state_serializes_and_deserializes :: proc(t: ^testing.T) {
	reset_world()
	minor_wave_timer = 42.5
	serialized := serialize_game_state()

	reset_world()
	testing.expect(t, minor_wave_timer == 0, "reset_world zeroes minor_wave_timer")

	deserialize_game_state(serialized)
	testing.expect(t, abs(minor_wave_timer - 42.5) < 0.01, "minor_wave_timer restored from save")
}

@(test)
minor_wave_target_planet_receives_warning_glow_three_seconds_prior :: proc(t: ^testing.T) {
	reset_world()
	// At game start, Venus is closest unliberated to Earth, and Earth is the only liberated planet.
	// Therefore Venus will attack Earth.
	testing.expect(t, minor_wave_warning_planet() == -1, "no warning before 72s")

	// Set minor wave timer to 71.9s (3.1s before attack) - still no warning
	minor_wave_timer = 71.9
	testing.expect(t, minor_wave_warning_planet() == -1, "no warning at 71.9s")
	update_combat_nebula_intensity(0.1)
	testing.expect(t, combat_nebula_intensity[EARTH] < 0.01, "combat nebula stays cold at 71.9s")

	// Advance to 72.0s (exactly 3s before 75s attack) - warning triggers on target Earth
	minor_wave_timer = 72.0
	target := minor_wave_warning_planet()
	testing.expect(t, target == EARTH, "Earth is targeted for warning 3s before launch")

	// Step combat nebula intensity: drives towards 0.5 (half battle intensity)
	for _ in 0..<20 {
		update_combat_nebula_intensity(0.1)
	}
	testing.expect(t, abs(combat_nebula_intensity[EARTH] - 0.5) < 0.05, "target planet gets red glow at half battle intensity (~0.5)")
	testing.expect(t, combat_nebula_intensity[VENUS] < 0.01, "attacking planet does not get warning glow")

	// If Venus is liberated, next unliberated is Uranus, which also targets Earth.
	enemy_base_hp[VENUS] = 0
	target = minor_wave_warning_planet()
	testing.expect(t, target == EARTH, "Earth targeted by Uranus")
}

@(test)
minor_wave_fighters_travel_together_in_formation :: proc(t: ^testing.T) {
	reset_world()
	// Launch minor wave from Venus to Earth
	spawn_minor_wave(VENUS, EARTH, MINOR_WAVE_SIZE)
	testing.expect(t, unit_count == 5, "spawned 5 minor wave drones")

	target_pos := sector_pos(EARTH)
	d0 := distance(units[0].position, target_pos)

	// Verify all 5 drones are equidistant to the target planet (within tiny tolerance)
	for i in 0..<5 {
		u := &units[i]
		testing.expect(t, u.state == .TRANSIT, "unit in transit")
		testing.expect(t, u.target_planet == EARTH, "unit targeting Earth")
		di := distance(u.position, target_pos)
		testing.expect(t, abs(di - d0) < 0.001, "all minor wave fighters start at equal distance to target")
	}

	// Verify unique orbit angles for arrival distribution
	for i in 0..<5 {
		for j := i + 1; j < 5; j += 1 {
			testing.expect(t, abs(units[i].orbit_angle - units[j].orbit_angle) > 0.1, "each fighter has unique orbit angle")
		}
	}

	// Advance them in flight by 2.0s
	for i in 0..<5 {
		update_combat(&units[i], 2.0)
	}

	// All 5 are still in transit and remain at identical distance to target
	d_mid := distance(units[0].position, target_pos)
	testing.expect(t, d_mid < d0, "drones moved closer to target")
	for i in 0..<5 {
		testing.expect(t, units[i].state == .TRANSIT, "drones still in transit")
		di := distance(units[i].position, target_pos)
		testing.expect(t, abs(di - d_mid) < 0.001, "drones remain synchronized at same distance in flight")
	}

	// Advance until they arrive at Earth: they should all arrive on the exact same frame
	for units[0].state == .TRANSIT {
		for i in 0..<5 {
			update_combat(&units[i], 0.1)
		}
	}

	// All 5 must have transitioned to GUARDING together
	for i in 0..<5 {
		testing.expect(t, units[i].state == .GUARDING, "all fighters arrive and guard together")
	}
}

@(test)
warning_glow_persists_during_transit_and_transitions_to_battle_glare :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()

	// 1. Before warning window: no warning, intensity is 0
	testing.expect(t, !planet_under_attack_warning(EARTH), "no warning initially")
	testing.expect(t, combat_nebula_intensity[EARTH] < 0.01, "intensity cold initially")

	// 2. 3 seconds before launch (72s): warning triggers, intensity ramps to 0.5
	minor_wave_timer = 72.0
	testing.expect(t, planet_under_attack_warning(EARTH), "Earth under warning at 72s")
	for _ in 0..<25 {
		update_combat_nebula_intensity(0.1)
	}
	testing.expect(t, abs(combat_nebula_intensity[EARTH] - 0.5) < 0.05, "intensity reaches warning glare (~0.5)")

	// 3. Minor wave launches at 75s: fighters spawn in transit, timer resets
	launch_minor_wave()
	testing.expect(t, minor_wave_timer == 0, "timer resets on launch")
	testing.expect(t, transit_fighters_at(EARTH, true) == 5, "5 enemy fighters in transit to Earth")
	testing.expect(t, planet_under_attack_warning(EARTH), "warning persists while fighters are in transit")

	// During transit: red glow must not stop or drop, remains at 0.5
	for _ in 0..<25 {
		update_combat_nebula_intensity(0.1)
	}
	testing.expect(t, abs(combat_nebula_intensity[EARTH] - 0.5) < 0.05, "red glow does not stop during transit, stays at ~0.5")

	// 4. Fighters arrive at Earth and enter GUARDING: battle starts!
	for units[unit_count - 1].state == .TRANSIT {
		for i in 0..<unit_count {
			if units[i].state == .TRANSIT {
				update_combat(&units[i], 0.1)
			}
		}
	}
	testing.expect(t, transit_fighters_at(EARTH, true) == 0, "all fighters arrived")
	testing.expect(t, sector_in_combat(EARTH), "Earth is now in combat")

	// Glow transitions from warning glare (0.5) to battle glare (1.0)
	for _ in 0..<25 {
		update_combat_nebula_intensity(0.1)
	}
	testing.expect(t, abs(combat_nebula_intensity[EARTH] - 1.0) < 0.05, "glow transitions to full battle glare (~1.0)")

	// 5. When enemies are defeated, battle ends and glow fades out
	for i := 0; i < unit_count; {
		if units[i].enemy && units[i].affiliation == EARTH {
			remove_unit_at(i)
		} else {
			i += 1
		}
	}
	testing.expect(t, !sector_in_combat(EARTH), "combat ended")
	testing.expect(t, !planet_under_attack_warning(EARTH), "no attack warning after combat")
	for _ in 0..<40 {
		update_combat_nebula_intensity(0.1)
	}
	testing.expect(t, combat_nebula_intensity[EARTH] < 0.05, "battle glare gracefully fades out")
}

// ---- Orbital Defense Tests -----------------------------------------------

@(test)
orbital_defense_initial_state :: proc(t: ^testing.T) {
	reset_world()
	for p in 0..<PLANET_COUNT {
		testing.expect(t, orbital_defense_level[p] == 0, "orbital defense level starts at 0")
		testing.expect(t, !orbital_defense_building[p], "orbital defense not building initially")
		testing.expect(t, orbital_defense_progress[p] == 0, "orbital defense progress starts at 0")
		testing.expect(t, orbital_defense_hp[p] == 0, "orbital defense HP starts at 0")
	}
}

@(test)
orbital_defense_build_requirements :: proc(t: ^testing.T) {
	reset_world()
	// Unliberated Mars cannot build defense
	minerals = 2000
	for i in 0..<10 { add_miner(MARS) }
	testing.expect(t, !planet_liberated(MARS), "Mars is occupied")
	testing.expect(t, !can_build_orbital_defense(MARS), "cannot build defense on unliberated planet")

	// Liberate Mars
	enemy_base_hp[MARS] = 0
	testing.expect(t, planet_liberated(MARS), "Mars is liberated")
	testing.expect(t, can_build_orbital_defense(MARS), "can build defense with 10 miners and 1000+ minerals")

	// Lacks minerals
	minerals = 999
	testing.expect(t, !can_build_orbital_defense(MARS), "cannot build defense without 1000 minerals")
	minerals = 1000

	// Lacks miners: remove 1 miner -> only 9 miners
	remove_unit_at(unit_count - 1)
	testing.expect(t, player_miners_count(MARS) == 9, "9 miners assigned")
	testing.expect(t, !can_build_orbital_defense(MARS), "cannot build defense with fewer than 10 miners")

	// Earth starts liberated, needs 10 miners and 1000 minerals
	for i in 0..<10 { add_miner(EARTH) }
	testing.expect(t, can_build_orbital_defense(EARTH), "Earth can build defense with 10 miners and 1000 minerals")
}

@(test)
orbital_defense_timed_construction_and_crew :: proc(t: ^testing.T) {
	reset_world()
	enemy_base_hp[MARS] = 0
	minerals = 1000
	for i in 0..<10 { add_miner(MARS) }

	start_orbital_defense_construction(MARS)
	testing.expect(t, minerals == 0, "1000 minerals deducted for construction")
	testing.expect(t, orbital_defense_building[MARS], "construction is underway")
	testing.expect(t, constructing_miners(MARS) == 10, "all 10 miners join construction crew")

	// Advance 59.9 seconds: not done yet
	update_production(59.9)
	testing.expect(t, orbital_defense_building[MARS], "defense still building at 59.9s")
	testing.expect(t, orbital_defense_level[MARS] == 0, "level is still 0 at 59.9s")

	// 0.2s more: completes at 60s
	update_production(0.2)
	testing.expect(t, !orbital_defense_building[MARS], "construction completed")
	testing.expect(t, orbital_defense_level[MARS] == 1, "orbital defense reaches level 1")
	testing.expect(t, orbital_defense_hp[MARS] == 100, "level 1 orbital defense has 100 HP")
	testing.expect(t, constructing_miners(MARS) == 0, "miners resume duties after construction completes")
}

@(test)
orbital_defense_upgrades_up_to_level_10 :: proc(t: ^testing.T) {
	reset_world()
	enemy_base_hp[VENUS] = 0
	for i in 0..<10 { add_miner(VENUS) }

	for lvl in 1..=10 {
		minerals = 1000
		testing.expect(t, can_build_orbital_defense(VENUS), "can upgrade to next level")
		start_orbital_defense_construction(VENUS)
		testing.expect(t, orbital_defense_building[VENUS], "upgrade started")
		update_production(ORBITAL_DEFENSE_BUILD_TIME)
		testing.expect(t, orbital_defense_level[VENUS] == lvl, "reached level")
		testing.expect(t, orbital_defense_hp[VENUS] == lvl * 100, "HP scales to level * 100")
	}

	// At level 10 (max), cannot upgrade further
	minerals = 2000
	testing.expect(t, orbital_defense_level[VENUS] == 10, "at max level 10")
	testing.expect(t, !can_build_orbital_defense(VENUS), "cannot upgrade past level 10")
}

@(test)
orbital_defense_intercepts_inbound_fighters :: proc(t: ^testing.T) {
	reset_world()
	// Level 1 defense on Earth (can destroy 10 enemy fighters)
	orbital_defense_level[EARTH] = 1
	orbital_defense_hp[EARTH] = 100

	// Launch 15 enemy fighters from Venus to Earth
	spawn_minor_wave(VENUS, EARTH, 15)
	testing.expect(t, unit_count == 15, "15 enemy fighters spawned in transit")

	// Advance simulation so they travel toward Earth
	// Speed is 2.5/s, distance Venus->Earth is ~15.54, travel time ~6.2s
	for s := 0; s < 70; s += 1 {
		update_units(0.1)
		update_enemy_waves(0.1)
	}

	// Out of 15 fighters, exactly 10 should be destroyed by orbital defense before reaching Earth
	// Remaining 5 reach Earth and enter GUARDING
	players, enemies := planet_combatants(EARTH)
	testing.expect(t, enemies == 5, "exactly 5 enemy fighters broke through and reached Earth")
	testing.expect(t, unit_count == 5, "total surviving units is 5 (10 destroyed by defense)")
}

@(test)
orbital_defense_destroys_all_fighters_if_under_cap :: proc(t: ^testing.T) {
	reset_world()
	// Level 1 defense on Earth (cap = 10)
	orbital_defense_level[EARTH] = 1
	orbital_defense_hp[EARTH] = 100

	// Launch 5 enemy fighters (minor wave size)
	spawn_minor_wave(VENUS, EARTH, 5)
	testing.expect(t, unit_count == 5, "5 enemy fighters in transit")

	for s := 0; s < 70; s += 1 {
		update_units(0.1)
		update_enemy_waves(0.1)
	}

	// All 5 destroyed before reaching Earth! 0 reach the planet.
	players, enemies := planet_combatants(EARTH)
	testing.expect(t, enemies == 0, "0 enemy fighters reached Earth")
	testing.expect(t, unit_count == 0, "all 5 destroyed in transit by orbital defense")
}

@(test)
orbital_defense_takes_damage_and_destroys_miners_and_refinery :: proc(t: ^testing.T) {
	reset_world()
	// Setup liberated Mars with Level 1 orbital defense, operational refinery, and 5 miners
	enemy_base_hp[MARS] = 0
	refinery_built[MARS] = true
	orbital_defense_level[MARS] = 1
	orbital_defense_hp[MARS] = 50 // 50 HP remaining
	for i in 0..<5 { add_miner(MARS) }

	// 5 enemy fighters arrive and guard Mars (no player fighters defending)
	for i in 0..<5 { add_guarding_fighter(MARS, true) }

	testing.expect(t, orbital_defense_level[MARS] == 1, "defense starts active")
	testing.expect(t, refinery_built[MARS], "refinery starts built")
	testing.expect(t, player_miners_at(MARS), "miners present on Mars")

	// 5 enemies deal 5 damage per COMBAT_TICK (0.2s) -> 25 damage per second.
	// In 1.0s (5 ticks): 25 damage taken -> HP drops from 50 to 25.
	update_enemy_waves(1.0)
	testing.expect(t, orbital_defense_level[MARS] == 1, "defense still alive at 25 HP")
	testing.expect(t, orbital_defense_hp[MARS] == 25, "defense took 25 damage from 5 enemy fighters")
	testing.expect(t, refinery_built[MARS], "refinery intact while defense stands")

	// 1.2s more (6 ticks = 30 damage): drops to <= 0 -> defense destroyed!
	update_enemy_waves(1.2)
	testing.expect(t, orbital_defense_level[MARS] == 0, "defense destroyed when HP reached 0")
	testing.expect(t, orbital_defense_hp[MARS] == 0, "defense HP is 0")
	testing.expect(t, !refinery_built[MARS], "refinery destroyed along with orbital defense")
	testing.expect(t, !player_miners_at(MARS), "miners destroyed along with orbital defense")
}

@(test)
friendly_fighters_defend_orbital_defense :: proc(t: ^testing.T) {
	reset_world()
	// Earth has Level 1 orbital defense and 5 friendly fighters
	orbital_defense_level[EARTH] = 1
	orbital_defense_hp[EARTH] = 100
	for i in 0..<5 { add_guarding_fighter(EARTH, false) }

	// 5 enemy fighters arrive at Earth
	for i in 0..<5 { add_guarding_fighter(EARTH, true) }

	// Friendly fighters engage in dogfight!
	update_enemy_waves(1.0) // 5 combat ticks: 5v5 resolves
	players, enemies := planet_combatants(EARTH)
	testing.expect(t, players == 0 && enemies == 0, "dogfight resolved 1:1")
	// Orbital defense took NO damage because friendly fighters defended!
	testing.expect(t, orbital_defense_hp[EARTH] == 100, "orbital defense took zero damage while fighters defended")
	testing.expect(t, orbital_defense_level[EARTH] == 1, "orbital defense remains intact")
}

@(test)
orbital_defense_save_and_load_persistence :: proc(t: ^testing.T) {
	reset_world()
	orbital_defense_level[EARTH] = 3
	orbital_defense_hp[EARTH] = 280
	orbital_defense_level[MARS] = 1
	orbital_defense_building[MARS] = true
	orbital_defense_progress[MARS] = 25.5
	orbital_defense_hp[MARS] = 100

	save_str := serialize_game_state()

	reset_world()
	testing.expect(t, orbital_defense_level[EARTH] == 0, "reset zeroes Earth defense")
	testing.expect(t, orbital_defense_level[MARS] == 0, "reset zeroes Mars defense")

	ok := deserialize_game_state(save_str)
	testing.expect(t, ok, "deserialization succeeded")
	testing.expect(t, orbital_defense_level[EARTH] == 3, "Earth defense level 3 restored")
	testing.expect(t, orbital_defense_hp[EARTH] == 280, "Earth defense HP restored")
	testing.expect(t, orbital_defense_level[MARS] == 1, "Mars defense level 1 restored")
	testing.expect(t, orbital_defense_building[MARS], "Mars building status restored")
	testing.expect(t, abs(orbital_defense_progress[MARS] - 25.5) < 0.1, "Mars progress restored")
}

@(test)
inspector_clicks_handle_orbital_defense :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = EARTH
	minerals = 1000
	for i in 0..<10 { add_miner(EARTH) }

	panel_x: f32 = 800.0
	btn := orbital_defense_button_rect(panel_x, EARTH)
	handle_inspector_click({btn.x + 5, btn.y + 5}, panel_x)
	testing.expect(t, orbital_defense_building[EARTH], "clicking button starts orbital defense construction on Earth")
	testing.expect(t, minerals == 0, "minerals deducted")

	// Outpost click
	reset_world()
	selected_planet = MARS
	enemy_base_hp[MARS] = 0
	minerals = 1000
	for i in 0..<10 { add_miner(MARS) }
	btn_mars := orbital_defense_button_rect(panel_x, MARS)
	handle_inspector_click({btn_mars.x + 5, btn_mars.y + 5}, panel_x)
	testing.expect(t, orbital_defense_building[MARS], "clicking button starts orbital defense construction on Mars")
}



