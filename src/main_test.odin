package main

import "core:testing"

reset_world :: proc() {
	unit_count = 0
	for i := 0; i < MAX_UNITS; i += 1 {
		units[i] = {}
		selected_units[i] = false
	}
	enemy_wave_timer = 0
	mars_combat_timer = 0
	mars_miner_timer = 0
	selected_planet = 0
}

add_mars_fighter :: proc(enemy: bool) {
	units[unit_count] = Unit{
		kind = .COMBAT, state = .GUARDING, position = planets[1].position,
		home_planet = 1, affiliation = 1, target_planet = 1, enemy = enemy,
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
enemy_wave_spawns_five_attackers :: proc(t: ^testing.T) {
	reset_world()
	spawn_enemy_wave()
	testing.expect(t, unit_count == WAVE_SIZE, "wave size")
	for i in 0..<unit_count {
		testing.expect(t, units[i].kind == .COMBAT, "enemy is combat")
		testing.expect(t, units[i].enemy, "enemy flag set")
		testing.expect(t, units[i].target_planet == 1 && units[i].affiliation == 1, "enemy targets Mars")
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
five_v_five_battle_lasts_five_seconds_1_to_1 :: proc(t: ^testing.T) {
	reset_world()
	for i in 0..<5 { add_mars_fighter(false) }
	for i in 0..<5 { add_mars_fighter(true) }
	testing.expect(t, unit_count == 10, "setup")
	for second in 1..=4 {
		update_enemy_waves(1.0)
		testing.expect(t, unit_count == 10 - second * 2, "one kill per side per second")
	}
	defenders, attackers := mars_combatants()
	testing.expect(t, defenders == 1 && attackers == 1, "one fighter each after 4s")
	update_enemy_waves(1.0)
	defenders, attackers = mars_combatants()
	testing.expect(t, defenders == 0 && attackers == 0, "5v5 trade ends after 5s")
	testing.expect(t, unit_count == 0, "all 10 destroyed in the trade")
}

@(test)
miners_die_every_two_seconds_without_defenders :: proc(t: ^testing.T) {
	reset_world()
	add_mars_fighter(true)
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
	add_mars_fighter(true)
	add_mars_fighter(true)
	add_mars_fighter(false)
	// 1 player fighter vs 2 enemies: each second both sides lose one, so the
	// lone defender trades for one enemy before falling.
	update_enemy_waves(1.0)
	defenders, attackers := mars_combatants()
	testing.expect(t, defenders == 0 && attackers == 1, "defender killed, one enemy survives")
	// Player dispatches reinforcements mid-occupation: a new defender arriving
	// resumes the fight and the garrison falls.
	add_mars_fighter(false)
	update_enemy_waves(1.0)
	defenders, attackers = mars_combatants()
	testing.expect(t, defenders == 0 && attackers == 0, "reinforcement clears the garrison")
}
