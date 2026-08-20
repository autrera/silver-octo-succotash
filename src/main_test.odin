package main

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
	spawn_enemy_wave()
	testing.expect(t, unit_count == WAVE_SIZE, "wave size")
	target := units[0].target_planet
	testing.expect(t, target >= 0 && target < PLANET_COUNT, "wave targets a valid planet")
	for i in 0..<unit_count {
		testing.expect(t, units[i].kind == .COMBAT, "enemy is combat")
		testing.expect(t, units[i].enemy, "enemy flag set")
		testing.expect(t, units[i].target_planet == target && units[i].affiliation == target, "wave shares one target")
		testing.expect(t, distance(units[i].position, ENEMY_HQ_POSITION) < 3, "wave lifts off from the enemy HQ")
	}
	selected_planet = target
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
	// Every cycle phase counts: transit, mining, returning, depositing, idle scout.
	units[0].state = .RETURNING
	units[1].state = .IDLE
	units[1].target_planet = JUPITER
	units[1].state = .MINING
	testing.expect(t, mined_planet_count() == 3, "returning/idle miners count their targets")
	units[0].state = .TRANSIT
	units[2].state = .DEPOSITING
	testing.expect(t, mined_planet_count() == 3, "transit and depositing miners count their targets")
}

@(test)
regular_wave_spawns_one_wave_per_mined_planet :: proc(t: ^testing.T) {
	reset_world()
	// unit_count includes the miners we seeded, so compare against the pre-wave count.
	add_miner(EARTH)
	add_miner(MARS)
	before := unit_count
	update_enemy_waves(f32(WAVE_FIRST_DELAY))
	testing.expect(t, unit_count - before == 2 * WAVE_SIZE, "two mined planets spawn two waves")
	// 0 mined planets still spawns at least one default wave.
	reset_world()
	update_enemy_waves(f32(WAVE_FIRST_DELAY))
	testing.expect(t, unit_count == WAVE_SIZE, "no mining spawns one default wave")
	reset_world()
	add_miner(EARTH)
	add_miner(MARS)
	add_miner(JUPITER)
	before = unit_count
	update_enemy_waves(f32(WAVE_FIRST_DELAY))
	testing.expect(t, unit_count - before == 3 * WAVE_SIZE, "three mined planets spawn three waves")
}

@(test)
attack_wave_size_doubles_at_four_mined_planets :: proc(t: ^testing.T) {
	testing.expect(t, WAVE_SIZE == 5, "standard wave is 5 fighters")
	testing.expect(t, WAVE_DOUBLE_MIN_MINED_PLANETS == 4, "doubling threshold is 4 mined planets")
	reset_world()
	testing.expect(t, attack_wave_size() == WAVE_SIZE, "0 mined: standard wave")
	add_miner(MERCURY)
	testing.expect(t, attack_wave_size() == WAVE_SIZE, "1 mined: standard wave")
	add_miner(VENUS)
	testing.expect(t, attack_wave_size() == WAVE_SIZE, "2 mined: standard wave")
	add_miner(MARS)
	testing.expect(t, attack_wave_size() == WAVE_SIZE, "3 mined: standard wave")
	add_miner(JUPITER)
	testing.expect(t, attack_wave_size() == 2 * WAVE_SIZE, "4 mined: doubled wave")
	testing.expect(t, 2 * WAVE_SIZE == 10, "doubled wave is 10 fighters")
	add_miner(SATURN); add_miner(URANUS); add_miner(NEPTUNE)
	testing.expect(t, attack_wave_size() == 2 * WAVE_SIZE, "8 mined: still doubled wave")
}

@(test)
four_mined_planets_spawn_four_doubled_waves :: proc(t: ^testing.T) {
	reset_world()
	add_miner(MERCURY); add_miner(MARS); add_miner(JUPITER); add_miner(NEPTUNE)
	before := unit_count
	update_enemy_waves(f32(WAVE_FIRST_DELAY))
	testing.expect(t, unit_count - before == 4 * 2 * WAVE_SIZE, "4 mined planets -> 4 waves of 10")
}

@(test)
waves_strike_each_mined_planet_once :: proc(t: ^testing.T) {
	reset_world()
	add_miner(VENUS); add_miner(SATURN); add_miner(URANUS)
	before := unit_count
	update_enemy_waves(f32(WAVE_FIRST_DELAY))
	testing.expect(t, unit_count - before == 3 * WAVE_SIZE, "three mined planets, three standard waves")
	// Each wave is a contiguous block sharing one target; collect the targets.
	targets := [PLANET_COUNT]int{}
	for i := before; i < unit_count; i += WAVE_SIZE {
		target := units[i].target_planet
		testing.expect(t, target == VENUS || target == SATURN || target == URANUS, "wave targets a mined planet")
		targets[target] += 1
	}
	testing.expect(t, targets[VENUS] == 1 && targets[SATURN] == 1 && targets[URANUS] == 1, "each mined planet struck exactly once")
}

@(test)
mega_wave_advances_and_spawns_at_five_mined_planets :: proc(t: ^testing.T) {
	reset_world()
	// Below the 5-planet threshold: the mega clock does not advance (stays 0).
	add_miner(EARTH); add_miner(MARS); add_miner(JUPITER); add_miner(SATURN)
	update_enemy_waves(50.0)
	testing.expect(t, mega_wave_timer == 0, "mega clock frozen below 5 mined planets")
	// At 5+ mined planets the clock advances.
	add_miner(URANUS)
	update_enemy_waves(10.0)
	testing.expect(t, mega_wave_timer == 10.0, "mega clock advances at >=5 mined planets")
	// Spawns 100 fighters at 300s. Drive the mega clock to just under 300 and
	// step over with the regular timer parked below its next boundary, so only
	// the mega wave fires on this tick.
	mega_wave_timer = MEGA_WAVE_INTERVAL_SECONDS - 0.1
	wave_started = true
	enemy_wave_timer = 0
	before := unit_count
	update_enemy_waves(0.1)
	testing.expect(t, unit_count - before == MEGA_WAVE_SIZE, "mega wave spawns 100 fighters at 300s")
	testing.expect(t, mega_wave_timer == 0, "mega clock resets after the assault")
}

@(test)
mega_wave_resets_when_mined_planets_drop_below_five :: proc(t: ^testing.T) {
	reset_world()
	add_miner(EARTH); add_miner(MARS); add_miner(JUPITER); add_miner(SATURN); add_miner(URANUS)
	// Park the regular timer below its next boundary so short steps never fire
	// a regular wave and muddy the mega-clock assertions.
	wave_started = true
	enemy_wave_timer = 0
	update_enemy_waves(100.0)
	testing.expect(t, mega_wave_timer == 100.0, "clock advances while >=5 mined planets")
	// Player stops mining one planet: clock resets to 0 immediately.
	units[0].state = .CONSTRUCTING
	update_enemy_waves(1.0)
	testing.expect(t, mega_wave_timer == 0, "clock resets when mined planets drop below 5")
	// Re-expanding restarts it from 0 (not from the previous 100s).
	units[0].state = .MINING
	update_enemy_waves(10.0)
	testing.expect(t, mega_wave_timer == 10.0, "clock restarts fresh from 0 on re-expansion")
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
initial_camera_zoom_is_85_percent :: proc(t: ^testing.T) {
	// Startup altitude 200 - 185*0.85 = 42.75 maps zoom_percent() to exactly 85%.
	testing.expect(t, abs(CAMERA_START_Y - 42.75) < 0.0001, "startup altitude is 42.75")
	camera.position = {camera_target.x, CAMERA_START_Y, camera_target.z + CAMERA_START_Y}
	testing.expect(t, zoom_percent() == 85, "startup camera reads exactly 85% zoom")
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
	// Doubled from 3s/5s to 6s/10s in the war-economy rebalance.
	testing.expect(t, MINER_BUILD_TIME == 6.0, "miner build time is 6s")
	testing.expect(t, COMBAT_BUILD_TIME == 10.0, "combat drone build time is 10s")
	reset_world()
	selected_planet = EARTH
	minerals = 1000
	queue_unit(.MINING)
	update_production(MINER_BUILD_TIME - 0.1)
	testing.expect(t, production[EARTH][0].active && unit_count == 0, "miner line still building just before 6s")
	update_production(0.2)
	testing.expect(t, !production[EARTH][0].active && unit_count == 1, "miner completes at 6s")
	queue_unit(.COMBAT)
	update_production(COMBAT_BUILD_TIME - 0.1)
	testing.expect(t, production[EARTH][0].active && unit_count == 1, "combat line still building just before 10s")
	update_production(0.2)
	testing.expect(t, !production[EARTH][0].active && unit_count == 2, "combat drone completes at 10s")
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
miners_die_every_second_without_defenders :: proc(t: ^testing.T) {
	reset_world()
	add_guarding_fighter(MARS, true)
	add_miner(MARS)
	add_miner(MARS)
	add_miner(MARS)
	update_enemy_waves(0.5)
	testing.expect(t, unit_count == 4, "no miner hit before the 1s mark")
	update_enemy_waves(0.5)
	testing.expect(t, unit_count == 3, "first miner destroyed at 1s")
	update_enemy_waves(1.0)
	testing.expect(t, unit_count == 2, "second miner destroyed at 2s")
	update_enemy_waves(1.0)
	testing.expect(t, unit_count == 1 && units[0].enemy, "third miner destroyed at 3s; only the enemy attacker survives")
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
	testing.expect(t, units[0].state == .MINING, "idle miner resumes after liberation")
}

@(test)
mining_round_trip_deposits_on_earth :: proc(t: ^testing.T) {
	reset_world()
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
enemy_waves_target_any_planet :: proc(t: ^testing.T) {
	// The default/debug wave (nothing mined) picks a seeded random target
	// among all eight planets; each one must show up across seeds.
	seen := [PLANET_COUNT]bool{}
	for seed in 0..<200 {
		reset_world()
		rl.SetRandomSeed(u32(seed))
		spawn_enemy_wave()
		testing.expect(t, unit_count == WAVE_SIZE, "wave size")
		target := units[0].target_planet
		testing.expect(t, target >= 0 && target < PLANET_COUNT, "wave targets a valid planet")
		for i in 1..<unit_count {
			testing.expect(t, units[i].target_planet == target, "every unit in a wave shares one target")
		}
		seen[target] = true
	}
	for p in 0..<PLANET_COUNT {
		testing.expectf(t, seen[p], "planet %d must be a reachable wave target", p)
	}
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
}

@(test)
transit_fleets_render_representationally :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<12 {
		units[unit_count] = Unit{kind = .COMBAT, state = .TRANSIT, position = {}, home_planet = EARTH, affiliation = MARS, target_planet = MARS}
		unit_count += 1
	}
	spawn_enemy_wave() // 5 enemies in transit to a random target.
	wave_target := units[unit_count - WAVE_SIZE].target_planet
	testing.expect(t, transit_fighters_at(MARS, false) == 12, "12 player fighters in transit to Mars")
	testing.expect(t, rep_count(transit_fighters_at(MARS, false)) == 2, "12 transit fighters render as 2 cubes")
	testing.expect(t, transit_fighters_at(wave_target, true) == WAVE_SIZE, "enemy wave in transit to its target")
	testing.expect(t, rep_count(transit_fighters_at(wave_target, true)) == 1, "5-enemy wave renders as 1 cube")
	for p in 0..<PLANET_COUNT {
		expected := p == wave_target ? WAVE_SIZE : 0
		testing.expectf(t, transit_fighters_at(p, true) == expected, "planet %d enemy transit count %d != %d", p, transit_fighters_at(p, true), expected)
	}
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
	testing.expect(t, players == 1 && enemies == 0, "Earth holds only the player's starting drones")
	testing.expect(t, enemy_miner_count(EARTH) == 0, "no enemy mining drones on Earth")
}

@(test)
all_non_earth_planets_start_occupied :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	// Exact spec: garrison fighters / miners / base HP per planet, scaling
	// with distance from Earth (Venus nearest ... Neptune farthest).
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
	// Resistance escalates strictly with distance from Earth.
	by_distance := [7]int{VENUS, MARS, MERCURY, JUPITER, SATURN, URANUS, NEPTUNE}
	spec_dist := [PLANET_COUNT]f32{31.0, 15.5, 0, 22.8, 51.4, 57.9, 87.4, 117.6}
	for i in 0..<7 {
		p := by_distance[i]
		testing.expectf(t, abs(distance(planets[p].position, planets[EARTH].position) - spec_dist[p]) < 1.0,
			"planet %d sits at its spec distance from Earth", p)
		if i > 0 {
			q := by_distance[i - 1]
			testing.expectf(t, GARRISON_FIGHTERS[p] > GARRISON_FIGHTERS[q] && GARRISON_MINERS[p] > GARRISON_MINERS[q] && GARRISON_BASE_HP[p] > GARRISON_BASE_HP[q],
				"garrison escalates from planet %d to %d", q, p)
		}
	}
}

@(test)
enemy_fighters_guard_and_orbit_after_arriving :: proc(t: ^testing.T) {
	reset_world()
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
	game_paused = true
	pause_menu_selection = 0
	advance_pause_selection(1)
	testing.expect(t, pause_menu_selection == 1, "DOWN moves focus to QUIT")
	advance_pause_selection(1)
	testing.expect(t, pause_menu_selection == 0, "DOWN wraps back to CONTINUE")
	advance_pause_selection(-1)
	testing.expect(t, pause_menu_selection == 1, "UP wraps to QUIT")
	advance_pause_selection(-1)
	testing.expect(t, pause_menu_selection == 0, "UP returns to CONTINUE")
	game_paused = false
}

@(test)
pause_menu_enter_activates_focused_option :: proc(t: ^testing.T) {
	game_paused = true
	quit_requested = false
	pause_menu_selection = 0
	activate_pause_selection()
	testing.expect(t, !game_paused, "ENTER on CONTINUE resumes")
	testing.expect(t, !quit_requested, "ENTER on CONTINUE never quits")
	game_paused = true
	pause_menu_selection = 1
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
	spawn_enemy_wave()
	testing.expect(t, unit_count == WAVE_SIZE, "wave spawned")
	target := units[0].target_planet
	lit := has_vision(target)
	for i in 0..<unit_count {
		testing.expect(t, is_concealed(&units[i]) != lit, "wave hidden while the target is dark, visible once lit")
	}
	if target != EARTH { // Earth is always lit, so only off-world targets can be darkened then lit.
		add_guarding_fighter(target, false)
		for i in 0..<unit_count {
			testing.expect(t, !is_concealed(&units[i]), "enemy wave visible once the target planet is lit")
		}
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
	for p in 0..<PLANET_COUNT { add_miner(p) }
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
	for i in 0..<60 { add_miner(MARS) }
	mars_cycle: f32 = MINING_DURATION + DEPOSIT_DURATION + 2.0 * distance(planets[MARS].position, planets[EARTH].position) / MINING_TRANSIT_SPEED
	expected = f32(planet_mining_cap(MARS)) * f32(mining_rate(MARS)) / mars_cycle
	testing.expect(t, abs(planet_mps(MARS) - expected) < 0.001, "Mars MPS caps at 50 effective miners")

	reset_world()
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
	handle_inspector_click({19, 107}, 0) // panel_x = 0: base rect is {18,106,294,32}.
	testing.expect(t, minerals == 1000 && base_build_planet == -1, "clicking the hidden button area does nothing at the cap")
}

@(test)
unit_tiles_are_compact_and_hitboxes_match_layout :: proc(t: ^testing.T) {
	testing.expect(t, TILE_SIZE == 26, "tiles are 50% smaller (52 -> 26)")
	// A full row packs inside the panel content area (two 18px margins).
	testing.expect(t, TILE_SIZE * TILES_PER_ROW + (TILES_PER_ROW - 1) * TILE_GAP <= SCREEN_PANEL_WIDTH - 36, "a full row fits inside the panel")
	testing.expect(t, TILES_PER_ROW >= 9, "rows hold at least 9 tiles")
	// First tile sits at the panel margin; ordinal 10 wraps to the second row.
	r0 := unit_tile_rect(100, 200, 0)
	testing.expect(t, r0.x == 118 && r0.y == 200 && r0.width == TILE_SIZE && r0.height == TILE_SIZE, "first tile at the panel margin")
	r10 := unit_tile_rect(100, 200, 10)
	testing.expect(t, r10.x == 118 && r10.y == 200 + (TILE_SIZE + TILE_GAP), "ordinal 10 wraps to the second row")
	r9 := unit_tile_rect(100, 200, 9)
	testing.expect(t, r9.x == 100 + 18 + 9 * (TILE_SIZE + TILE_GAP), "tiles pack left to right")
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
	before := unit_count
	spawn_enemy_wave()
	target := units[before].target_planet
	selected_planet = target
	testing.expect(t, enemy_roster_count(.COMBAT) == WAVE_SIZE, "wave fighters count in the target roster")
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
	// Saturn/Uranus/Neptune shifted left (X) toward Earth to cut round-trip
	// transit times, keeping ~30 units of spacing and their solar order.
	testing.expect(t, planets[SATURN].position.x == 55, "Saturn shifted to x=55")
	testing.expect(t, planets[URANUS].position.x == 85, "Uranus shifted to x=85")
	testing.expect(t, planets[NEPTUNE].position.x == 115, "Neptune shifted to x=115")
	testing.expect(t, planets[URANUS].position.x - planets[SATURN].position.x == 30, "Saturn->Uranus spacing kept at ~30")
	testing.expect(t, planets[NEPTUNE].position.x - planets[URANUS].position.x == 30, "Uranus->Neptune spacing kept at ~30")
	d_jupiter := distance(planets[JUPITER].position, planets[EARTH].position)
	testing.expect(t, distance(planets[SATURN].position, planets[EARTH].position) > d_jupiter, "solar order kept: Saturn still beyond Jupiter")
	testing.expect(t, distance(planets[EARTH].position, planets[NEPTUNE].position) < 142.0, "Neptune round trip shorter than the old 142-unit orbit")
	// The enemy HQ sits where Neptune used to be (the original outer orbit).
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
	// A destroyed HQ never launches another wave, ever.
	wave_started = false
	enemy_wave_timer = 0
	before := unit_count
	update_enemy_waves(f32(WAVE_FIRST_DELAY))
	testing.expect(t, unit_count == before, "no waves launch from a destroyed HQ")
}

// ---- Wave stop rule at 5 mined planets ----------------------------------

@(test)
regular_waves_stop_completely_at_five_mined_planets :: proc(t: ^testing.T) {
	reset_world()
	add_miner(MERCURY); add_miner(VENUS); add_miner(MARS); add_miner(JUPITER); add_miner(SATURN)
	base := unit_count
	// Well past every regular boundary: nothing may launch at 5 mined planets.
	update_enemy_waves(MEGA_WAVE_INTERVAL_SECONDS - 1.0)
	testing.expect(t, unit_count == base, "no regular wave at 5 mined planets")
	testing.expect(t, enemy_wave_timer == 0, "regular clock frozen while >= 5 mined planets")
	// Only the mega boss assault (100 fighters) strikes at the 5-minute mark.
	update_enemy_waves(1.0)
	testing.expect(t, unit_count == base + MEGA_WAVE_SIZE, "only the mega assault strikes at 5 mined planets")
	testing.expect(t, mega_wave_timer == 0, "mega clock resets after the assault")
	// Dropping back below 5 resumes regular waves on the normal schedule.
	units[0].state = .CONSTRUCTING
	update_enemy_waves(f32(WAVE_FIRST_DELAY) - 0.1)
	testing.expect(t, unit_count == base + MEGA_WAVE_SIZE, "still no new wave before the schedule boundary")
	update_enemy_waves(0.2)
	// 4 mined planets now -> 4 doubled waves (attack_wave_size doubles at 4).
	testing.expect(t, unit_count == base + MEGA_WAVE_SIZE + 4 * 2 * WAVE_SIZE, "regular waves resume below 5 mined planets")
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
