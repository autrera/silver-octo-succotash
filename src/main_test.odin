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
	}
	jupiter_base_timer = 0
	enemy_base_hp = ENEMY_BASE_HP
	base_counts = [PLANET_COUNT]int{1, 1, 0}
	base_build_planet = -1
	base_build_progress = 0
	minerals = 350
	enemy_wave_timer = 0
	selected_planet = 0
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
	testing.expect(t, units[0].target_planet == 0, "miner targets Earth")
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
		testing.expect(t, units[i].target_planet == 1 && units[i].affiliation == 1, "enemy targets Mars")
		testing.expect(t, distance(units[i].position, jump_off) < 3, "wave lifts off from Jupiter")
	}
	selected_planet = 1
	testing.expect(t, roster_count(.COMBAT) == 0, "enemies never appear in the player roster")
}

@(test)
wave_timer_triggers_every_120_seconds :: proc(t: ^testing.T) {
	reset_world()
	enemy_wave_timer = WAVE_INTERVAL - 0.1
	update_enemy_waves(0.2)
	testing.expect(t, unit_count == WAVE_SIZE, "wave spawned on timer")
	testing.expect(t, enemy_wave_timer < 0.2, "timer reset after wave")
	update_enemy_waves(1.0)
	testing.expect(t, unit_count == WAVE_SIZE, "no extra wave before interval elapses")
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
dispatched_fighters_break_the_garrison :: proc(t: ^testing.T) {
	reset_world()
	add_guarding_fighter(1, true)
	add_guarding_fighter(1, true)
	add_guarding_fighter(1, false)
	// 1 player fighter vs 2 enemies: each 2s tick both sides lose one, so the
	// lone defender trades for one enemy before falling.
	update_enemy_waves(f32(COMBAT_TICK))
	defenders, attackers := planet_combatants(1)
	testing.expect(t, defenders == 0 && attackers == 1, "defender killed, one enemy survives")
	// Player dispatches reinforcements mid-occupation: a new defender arriving
	// resumes the fight and the garrison falls.
	add_guarding_fighter(1, false)
	update_enemy_waves(f32(COMBAT_TICK))
	defenders, attackers = planet_combatants(1)
	testing.expect(t, defenders == 0 && attackers == 0, "reinforcement clears the garrison")
}

@(test)
jupiter_starts_as_enemy_stronghold :: proc(t: ^testing.T) {
	reset_world()
	initialize_game()
	players, enemies := planet_combatants(2)
	testing.expect(t, enemies == GARRISON_FIGHTERS, "40 enemy fighters garrison Jupiter")
	testing.expect(t, players == 0, "no player fighters on Jupiter")
	testing.expect(t, enemy_miner_count(2) == GARRISON_MINERS, "enemy mining drones garrison Jupiter")
	testing.expect(t, enemy_base_hp == ENEMY_BASE_HP, "enemy base intact")
	testing.expect(t, base_counts[2] == 0, "no player base on Jupiter")
	testing.expect(t, !jupiter_liberated(), "Jupiter starts occupied")
}

@(test)
jupiter_garrison_trades_with_invading_fleet :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<5 { add_guarding_fighter(2, false) }
	for i in 0..<5 { add_guarding_fighter(2, true) }
	update_enemy_waves(f32(COMBAT_TICK))
	players, enemies := planet_combatants(2)
	testing.expect(t, players == 4 && enemies == 4, "2s attrition applies at Jupiter too")
}

@(test)
jupiter_liberation_requires_clearing_garrison_miners_and_base :: proc(t: ^testing.T) {
	reset_world()
	// An invading fleet arrives; the garrison is already whittled to 1 fighter.
	for i in 0..<5 { add_guarding_fighter(2, false) }
	add_guarding_fighter(2, true)
	for i in 0..<GARRISON_MINERS { add_enemy_miner(2) }
	// The last garrison fighter trades 1:1.
	update_enemy_waves(f32(COMBAT_TICK))
	players, enemies := planet_combatants(2)
	testing.expect(t, players == 4 && enemies == 0, "last garrison fighter traded 1:1")
	testing.expect(t, !jupiter_liberated(), "enemy miners and base still stand")
	// Player fighters sweep the enemy mining drones, one per 2s tick.
	for i in 0..<GARRISON_MINERS { update_enemy_waves(f32(COMBAT_TICK)) }
	testing.expect(t, enemy_miner_count(2) == 0, "enemy mining drones destroyed")
	testing.expect(t, !jupiter_liberated(), "enemy base still stands")
	// The enemy base then takes 1 HP per 2s tick per player fighter.
	before := enemy_base_hp
	update_enemy_waves(f32(COMBAT_TICK))
	testing.expect(t, enemy_base_hp == before - 4, "base damaged by the occupying fleet")
	for enemy_base_hp > 0 { update_enemy_waves(f32(COMBAT_TICK)) }
	testing.expect(t, jupiter_liberated(), "Jupiter liberated once the base falls")
}

@(test)
occupied_jupiter_blocks_base_construction :: proc(t: ^testing.T) {
	reset_world()
	selected_planet = 2
	start_base_construction()
	testing.expect(t, base_build_planet != 2, "base construction blocked while Jupiter is occupied")
	enemy_base_hp = 0
	start_base_construction()
	testing.expect(t, base_build_planet == 2, "base construction allowed once liberated")
}

@(test)
representational_rendering_one_cube_per_ten :: proc(t: ^testing.T) {
	reset_world()
	testing.expect(t, rep_count(0) == 0, "empty fleet renders nothing")
	for n in 1..=10 { testing.expect(t, rep_count(n) == 1, "1-10 render as 1 cube") }
	for n in 11..=20 { testing.expect(t, rep_count(n) == 2, "11-20 render as 2 cubes") }
	testing.expect(t, rep_count(GARRISON_FIGHTERS) == 4, "40 garrison fighters render as 4 cubes")
}

@(test)
enemy_fighters_guard_and_orbit_after_arriving :: proc(t: ^testing.T) {
	reset_world()
	spawn_enemy_wave()
	// One long update: everyone reaches Mars this frame.
	for i in 0..<unit_count { update_combat(&units[i], 10.0) }
	for i in 0..<unit_count {
		testing.expect(t, units[i].state == .GUARDING, "enemy fighters guard Mars after arriving")
	}
	first := units[0].position
	update_combat(&units[0], 1.0)
	testing.expect(t, distance(first, units[0].position) > 0.01, "guarding fighters keep orbiting while fighting")
}
