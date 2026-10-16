package main

import "core:os"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:path/filepath"
import rl "vendor:raylib"

save_game_path :: proc(custom_path: string = "", allocator := context.temp_allocator) -> string {
	if len(custom_path) > 0 {
		return custom_path
	}
	exe_dir, err := os.get_executable_directory(allocator)
	if err == nil && len(exe_dir) > 0 {
		p, _ := filepath.join({exe_dir, "savegame.txt"}, allocator)
		return p
	}
	return "savegame.txt"
}

save_game_exists :: proc(custom_path: string = "") -> bool {
	p := save_game_path(custom_path)
	if os.exists(p) {
		return true
	}
	if len(custom_path) == 0 && os.exists("savegame.txt") {
		return true
	}
	return false
}

unit_type_to_string :: proc(k: Unit_Type) -> string {
	switch k {
	case .MINING: return "MINING"
	case .COMBAT: return "COMBAT"
	}
	return "MINING"
}

unit_state_to_string :: proc(s: Unit_State) -> string {
	switch s {
	case .IDLE: return "IDLE"
	case .TRANSIT: return "TRANSIT"
	case .MINING: return "MINING"
	case .RETURNING: return "RETURNING"
	case .DEPOSITING: return "DEPOSITING"
	case .GUARDING: return "GUARDING"
	case .CONSTRUCTING: return "CONSTRUCTING"
	}
	return "IDLE"
}

parse_unit_type :: proc(s: string) -> (Unit_Type, bool) {
	switch s {
	case "MINING": return .MINING, true
	case "COMBAT": return .COMBAT, true
	case: return .MINING, false
	}
}

parse_unit_state :: proc(s: string) -> (Unit_State, bool) {
	switch s {
	case "IDLE": return .IDLE, true
	case "TRANSIT": return .TRANSIT, true
	case "MINING": return .MINING, true
	case "RETURNING": return .RETURNING, true
	case "DEPOSITING": return .DEPOSITING, true
	case "GUARDING": return .GUARDING, true
	case "CONSTRUCTING": return .CONSTRUCTING, true
	case: return .IDLE, false
	}
}

build_target_to_string :: proc(b: Build_Target) -> string {
	switch b {
	case .NONE: return "NONE"
	case .BASE: return "BASE"
	case .REFINERY: return "REFINERY"
	case .ORBITAL_DEFENSE: return "ORBITAL_DEFENSE"
	case .ORBITAL_DEFENSE_AMMO: return "ORBITAL_DEFENSE_AMMO"
	}
	return "NONE"
}

parse_build_target :: proc(s: string) -> (Build_Target, bool) {
	switch s {
	case "NONE": return .NONE, true
	case "BASE": return .BASE, true
	case "REFINERY": return .REFINERY, true
	case "ORBITAL_DEFENSE": return .ORBITAL_DEFENSE, true
	case "ORBITAL_DEFENSE_AMMO": return .ORBITAL_DEFENSE_AMMO, true
	case: return .NONE, false
	}
}

auto_build_mode_to_string :: proc(m: Auto_Build_Mode) -> string {
	switch m {
	case .OFF: return "OFF"
	case .MINERS: return "MINERS"
	case .COMBAT: return "COMBAT"
	}
	return "OFF"
}

parse_auto_build_mode :: proc(s: string) -> (Auto_Build_Mode, bool) {
	switch s {
	case "OFF": return .OFF, true
	case "MINERS": return .MINERS, true
	case "COMBAT": return .COMBAT, true
	case: return .OFF, false
	}
}

serialize_game_state :: proc(allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)

	fmt.sbprintf(&b, "# STARFALL COMMAND SAVE\n")
	fmt.sbprintf(&b, "VERSION 1\n")
	fmt.sbprintf(&b, "MINERALS %d\n", minerals)
	fmt.sbprintf(&b, "DRONE_SPEED_LEVEL %d\n", drone_speed_level)
	fmt.sbprintf(&b, "AUTO_BUILD_MODE %s\n", auto_build_mode_to_string(auto_build_mode))
	fmt.sbprintf(&b, "AUTO_BUILD_LAST_MODE %s\n", auto_build_mode_to_string(auto_build_last_mode))
	fmt.sbprintf(&b, "EARTH_RALLY %d\n", earth_rally)
	fmt.sbprintf(&b, "SELECTED_PLANET %d\n", selected_planet)
	fmt.sbprintf(&b, "BASE_BUILD %d %.4f\n", base_build_planet, base_build_progress)
	fmt.sbprintf(&b, "WAVES %.4f %d\n", enemy_wave_timer, wave_started ? 1 : 0)
	fmt.sbprintf(&b, "MINOR_WAVE %.4f\n", minor_wave_timer)
	fmt.sbprintf(&b, "CAMERA_TARGET %.4f %.4f %.4f\n", camera_target.x, camera_target.y, camera_target.z)
	fmt.sbprintf(&b, "CAMERA_POS %.4f %.4f %.4f\n", camera.position.x, camera.position.y, camera.position.z)

	for p in 0..<PLANET_COUNT {
		fmt.sbprintf(&b, "BASE_COUNT %d %d\n", p, base_counts[p])
		for l in 0..<MAX_BASES {
			prod := production[p][l]
			if prod.active || prod.progress > 0 {
				fmt.sbprintf(&b, "PROD %d %d %s %.4f %d\n",
					p, l,
					unit_type_to_string(prod.kind),
					prod.progress,
					prod.active ? 1 : 0)
			}
		}
		for slot in 0..<pending_count[p] {
			fmt.sbprintf(&b, "PENDING %d %d %s\n",
				p, slot,
				unit_type_to_string(pending[p][slot]))
		}
		if refinery_built[p] || refinery_building[p] || refinery_progress[p] > 0 {
			fmt.sbprintf(&b, "REFINERY %d %d %d %.4f\n",
				p,
				refinery_built[p] ? 1 : 0,
				refinery_building[p] ? 1 : 0,
				refinery_progress[p])
		}
		if orbital_defense_level[p] > 0 || orbital_defense_building[p] || orbital_defense_progress[p] > 0 || orbital_defense_ammo[p] > 0 || orbital_defense_ammo_building[p] {
			fmt.sbprintf(&b, "ORBITAL_DEFENSE %d %d %d %.4f %d %d %d %.4f\n",
				p,
				orbital_defense_level[p],
				orbital_defense_building[p] ? 1 : 0,
				orbital_defense_progress[p],
				orbital_defense_hp[p],
				orbital_defense_ammo[p],
				orbital_defense_ammo_building[p] ? 1 : 0,
				orbital_defense_ammo_progress[p])
		}
	}

	for s in 0..<SECTOR_COUNT {
		if s >= PLANET_COUNT && (orbital_defense_level[s] > 0 || orbital_defense_building[s] || orbital_defense_progress[s] > 0 || orbital_defense_ammo[s] > 0 || orbital_defense_ammo_building[s]) {
			fmt.sbprintf(&b, "ORBITAL_DEFENSE %d %d %d %.4f %d %d %d %.4f\n",
				s,
				orbital_defense_level[s],
				orbital_defense_building[s] ? 1 : 0,
				orbital_defense_progress[s],
				orbital_defense_hp[s],
				orbital_defense_ammo[s],
				orbital_defense_ammo_building[s] ? 1 : 0,
				orbital_defense_ammo_progress[s])
		}
		fmt.sbprintf(&b, "SECTOR %d %d %.4f %.4f %.4f %.4f\n",
			s,
			enemy_base_hp[s],
			combat_timer[s],
			miner_timer[s],
			base_timer[s],
			combat_vision_timer[s])
	}

	for p in 0..<PLANET_COUNT {
		intel := last_known_intel[p]
		if intel_recorded[p] {
			fmt.sbprintf(&b, "INTEL %d %d %d %d %d %d\n",
				p,
				1,
				intel.fighters,
				intel.miners,
				intel.base_hp,
				intel.unit_count)
			for i in 0..<intel.unit_count {
				u := intel.units[i]
				fmt.sbprintf(&b, "INTEL_UNIT %d %s %s %d\n",
					p,
					unit_type_to_string(u.kind),
					unit_state_to_string(u.state),
					u.enemy ? 1 : 0)
			}
		}
	}

	fmt.sbprintf(&b, "UNITS %d\n", unit_count)
	for i in 0..<unit_count {
		u := units[i]
		fmt.sbprintf(&b, "UNIT %s %s %.4f %.4f %.4f %d %d %d %d %.4f %.4f %d %s %d\n",
			unit_type_to_string(u.kind),
			unit_state_to_string(u.state),
			u.position.x, u.position.y, u.position.z,
			u.home_planet, u.affiliation, u.target_planet,
			u.enemy ? 1 : 0,
			u.progress, u.orbit_angle, u.squad,
			build_target_to_string(u.build_target),
			u.mining_active ? 1 : 0)
	}

	return strings.to_string(b)
}

deserialize_game_state :: proc(content: string) -> bool {
	lines := strings.split_lines(content, context.temp_allocator)
	if len(lines) == 0 {
		return false
	}

	reset_world()
	base_counts = {}
	pending_count = {}

	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || trimmed[0] == '#' {
			continue
		}
		fields := strings.fields(trimmed, context.temp_allocator)
		if len(fields) < 2 {
			continue
		}

		switch fields[0] {
		case "MINERALS":
			if val, ok := strconv.parse_int(fields[1]); ok {
				minerals = val
			}
		case "DRONE_SPEED_LEVEL":
			if val, ok := strconv.parse_int(fields[1]); ok {
				drone_speed_level = val
			}
		case "AUTO_BUILD_MODE":
			if mode, ok := parse_auto_build_mode(fields[1]); ok {
				auto_build_mode = mode
				if mode != .OFF {
					auto_build_last_mode = mode
				}
			}
		case "AUTO_BUILD_LAST_MODE":
			if mode, ok := parse_auto_build_mode(fields[1]); ok {
				if mode != .OFF {
					auto_build_last_mode = mode
				}
			}
		case "EARTH_RALLY":
			if val, ok := strconv.parse_int(fields[1]); ok {
				earth_rally = val
			}
		case "SELECTED_PLANET":
			if val, ok := strconv.parse_int(fields[1]); ok {
				selected_planet = val
			}
		case "BASE_BUILD":
			if len(fields) >= 3 {
				p, _ := strconv.parse_int(fields[1])
				prog, _ := strconv.parse_f32(fields[2])
				base_build_planet = p
				base_build_progress = prog
			}
		case "REFINERY":
			if len(fields) >= 5 {
				p, _ := strconv.parse_int(fields[1])
				built := fields[2] == "1"
				bld := fields[3] == "1"
				prog, _ := strconv.parse_f32(fields[4])
				if p >= 0 && p < PLANET_COUNT {
					refinery_built[p] = built
					refinery_building[p] = bld
					refinery_progress[p] = prog
				}
			}
		case "ORBITAL_DEFENSE":
			if len(fields) >= 6 {
				p, _ := strconv.parse_int(fields[1])
				lvl, _ := strconv.parse_int(fields[2])
				bld := fields[3] == "1"
				prog, _ := strconv.parse_f32(fields[4])
				hp, _ := strconv.parse_int(fields[5])
				ammo := ORBITAL_DEFENSE_START_AMMO
				ammo_bld := false
				ammo_prog: f32 = 0
				if len(fields) >= 9 {
					a, _ := strconv.parse_int(fields[6])
					ammo = a
					ammo_bld = fields[7] == "1"
					ap, _ := strconv.parse_f32(fields[8])
					ammo_prog = ap
				} else if lvl > 0 {
					ammo = ORBITAL_DEFENSE_START_AMMO
				}
				if p >= 0 && p < SECTOR_COUNT {
					orbital_defense_level[p] = lvl
					orbital_defense_building[p] = bld
					orbital_defense_progress[p] = prog
					orbital_defense_hp[p] = hp
					orbital_defense_ammo[p] = ammo
					orbital_defense_ammo_building[p] = ammo_bld
					orbital_defense_ammo_progress[p] = ammo_prog
				}
			}
		case "WAVES":
			if len(fields) >= 3 {
				tm, _ := strconv.parse_f32(fields[1])
				st := fields[2] == "1"
				enemy_wave_timer = tm
				wave_started = st
			}
		case "MINOR_WAVE":
			if len(fields) >= 2 {
				tm, _ := strconv.parse_f32(fields[1])
				minor_wave_timer = tm
			}
		case "CAMERA_TARGET":
			if len(fields) >= 4 {
				x, _ := strconv.parse_f32(fields[1])
				y, _ := strconv.parse_f32(fields[2])
				z, _ := strconv.parse_f32(fields[3])
				camera_target = {x, y, z}
				camera.target = camera_target
			}
		case "CAMERA_POS":
			if len(fields) >= 4 {
				x, _ := strconv.parse_f32(fields[1])
				y, _ := strconv.parse_f32(fields[2])
				z, _ := strconv.parse_f32(fields[3])
				camera.position = {x, y, z}
			}
		case "PLANET_MINERALS":
		case "BASE_COUNT":
			if len(fields) >= 3 {
				p, _ := strconv.parse_int(fields[1])
				c, _ := strconv.parse_int(fields[2])
				if p >= 0 && p < PLANET_COUNT {
					base_counts[p] = c
				}
			}
		case "PROD":
			if len(fields) >= 6 {
				p, _ := strconv.parse_int(fields[1])
				l, _ := strconv.parse_int(fields[2])
				kind, _ := parse_unit_type(fields[3])
				prog, _ := strconv.parse_f32(fields[4])
				act := fields[5] == "1"
				if p >= 0 && p < PLANET_COUNT && l >= 0 && l < MAX_BASES {
					production[p][l] = Production{kind = kind, progress = prog, active = act}
				}
			}
		case "PENDING":
			if len(fields) >= 4 {
				p, _ := strconv.parse_int(fields[1])
				slot, _ := strconv.parse_int(fields[2])
				kind, _ := parse_unit_type(fields[3])
				if p >= 0 && p < PLANET_COUNT && slot >= 0 && slot < MAX_PENDING {
					pending[p][slot] = kind
					if slot + 1 > pending_count[p] {
						pending_count[p] = slot + 1
					}
				}
			}
		case "SECTOR":
			if len(fields) >= 6 {
				s, _ := strconv.parse_int(fields[1])
				hp, _ := strconv.parse_int(fields[2])
				ct, _ := strconv.parse_f32(fields[3])
				mt, _ := strconv.parse_f32(fields[4])
				bt, _ := strconv.parse_f32(fields[5])
				if s >= 0 && s < SECTOR_COUNT {
					enemy_base_hp[s] = hp
					combat_timer[s] = ct
					miner_timer[s] = mt
					base_timer[s] = bt
				}
				if len(fields) >= 7 {
					cvt, _ := strconv.parse_f32(fields[6])
					if s >= 0 && s < SECTOR_COUNT {
						combat_vision_timer[s] = cvt
					}
				}
			}
		case "INTEL":
			if len(fields) >= 7 {
				p, _ := strconv.parse_int(fields[1])
				rec := fields[2] == "1"
				f, _ := strconv.parse_int(fields[3])
				m, _ := strconv.parse_int(fields[4])
				hp, _ := strconv.parse_int(fields[5])
				if p >= 0 && p < PLANET_COUNT {
					intel_recorded[p] = rec
					last_known_intel[p].fighters = f
					last_known_intel[p].miners = m
					last_known_intel[p].base_hp = hp
					last_known_intel[p].unit_count = 0
				}
			}
		case "INTEL_UNIT":
			if len(fields) >= 5 {
				p, _ := strconv.parse_int(fields[1])
				kind, _ := parse_unit_type(fields[2])
				state, _ := parse_unit_state(fields[3])
				enemy := fields[4] == "1"
				if p >= 0 && p < PLANET_COUNT {
					cnt := last_known_intel[p].unit_count
					if cnt < INTEL_UNIT_CAP {
						last_known_intel[p].units[cnt] = Intel_Unit{kind = kind, state = state, enemy = enemy}
						last_known_intel[p].unit_count += 1
					}
				}
			}
		case "UNIT":
			if len(fields) >= 13 {
				kind, _ := parse_unit_type(fields[1])
				state, _ := parse_unit_state(fields[2])
				x, _ := strconv.parse_f32(fields[3])
				y, _ := strconv.parse_f32(fields[4])
				z, _ := strconv.parse_f32(fields[5])
				home, _ := strconv.parse_int(fields[6])
				affil, _ := strconv.parse_int(fields[7])
				target, _ := strconv.parse_int(fields[8])
				enemy := fields[9] == "1"
				prog, _ := strconv.parse_f32(fields[10])
				orbit, _ := strconv.parse_f32(fields[11])
				squad, _ := strconv.parse_int(fields[12])
				bt: Build_Target = .NONE
				if len(fields) >= 14 {
					bt, _ = parse_build_target(fields[13])
				} else if state == .CONSTRUCTING && target >= 0 && target < PLANET_COUNT {
					if refinery_building[target] {
						bt = .REFINERY
					} else if orbital_defense_building[target] {
						bt = .ORBITAL_DEFENSE
					} else if base_build_planet == target {
						bt = .BASE
					}
				}
				mining_active := false
				if len(fields) >= 15 {
					mining_active = fields[14] == "1"
				} else if kind == .MINING && !enemy && (state == .MINING || state == .RETURNING || state == .DEPOSITING) {
					mining_active = true
				}
				if unit_count < MAX_UNITS {
					units[unit_count] = Unit{
						kind = kind,
						state = state,
						position = {x, y, z},
						home_planet = home,
						affiliation = affil,
						target_planet = target,
						enemy = enemy,
						progress = prog,
						orbit_angle = orbit,
						squad = squad,
						build_target = bt,
						mining_active = mining_active,
					}
					unit_count += 1
				}
			}
		}
	}

	if !can_use_autobuilder() {
		auto_build_mode = .OFF
	}
	autobuild_retry_timer = 0

	camera.target = camera_target
	camera.up = {0, 1, 0}
	camera.fovy = 45
	camera.projection = .PERSPECTIVE
	in_start_menu = false
	game_paused = false
	controls_overlay_open = false
	planet_unit_cache_dirty = true
	return true
}

save_game :: proc(path: string = "") -> bool {
	content := serialize_game_state(context.temp_allocator)
	if len(path) > 0 {
		err := os.write_entire_file(path, content)
		return err == nil
	}
	err_root := os.write_entire_file("savegame.txt", content)
	exe_target := save_game_path("")
	if exe_target != "savegame.txt" {
		_ = os.write_entire_file(exe_target, content)
	}
	return err_root == nil
}

load_game :: proc(path: string = "") -> bool {
	target_path := path
	if len(target_path) == 0 {
		if os.exists("savegame.txt") {
			target_path = "savegame.txt"
		} else {
			target_path = save_game_path("")
		}
	}
	data, err := os.read_entire_file(target_path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return false
	}
	return deserialize_game_state(string(data))
}

delete_save_game :: proc(custom_path: string = "") -> bool {
	if len(custom_path) > 0 {
		if os.exists(custom_path) {
			return os.remove(custom_path) == nil
		}
		return false
	}
	removed := false
	if os.exists("savegame.txt") {
		if os.remove("savegame.txt") == nil {
			removed = true
		}
	}
	exe_target := save_game_path("")
	if exe_target != "savegame.txt" && os.exists(exe_target) {
		if os.remove(exe_target) == nil {
			removed = true
		}
	}
	return removed
}

