package main

import "core:c"
import "core:time"
import rl "vendor:raylib"

// =========================================================================
// Layout & UI Metrics
// =========================================================================

SCREEN_PANEL_WIDTH :: 330
PANEL_PAD_X        :: 20
PANEL_CONTENT_W    :: SCREEN_PANEL_WIDTH - 2 * PANEL_PAD_X
CARD_INSET         :: 10
BTN_GAP            :: 12
BUILD_BTN_W        :: 139
BUILD_BTN_H        :: 36
BASE_BTN_H         :: 36
QUEUE_SLOT_W       :: 50
QUEUE_SLOT_H       :: 20
QUEUE_SLOT_GAP     :: 10
GRID_PITCH         :: 24
PROD_PITCH         :: 34
PANEL_SUB_Y        :: 60
OUTPOST_CARD_Y     :: PANEL_SUB_Y
SECTION_TOP        :: PANEL_SUB_Y
CARD_H             :: 54
SECTION_PAD_Y      :: 26
PROD_BAR_W         :: PANEL_CONTENT_W
BAR_H              :: 8

CARD_LINE_1        :: OUTPOST_CARD_Y + 14
CARD_LINE_2        :: OUTPOST_CARD_Y + 33
REFINERY_BTN_Y     :: SECTION_TOP
ORBITAL_DEFENSE_BTN_Y :: 104
BASE_PROGRESS_Y    :: SECTION_TOP + BASE_BTN_H + 4
PROD_TITLE_Y       :: 150
PROD_FIRST_Y       :: 173
PROD_BAR_DY        :: 16
ORDERS_BASE_Y      :: 244
BASE_COLLAPSE_Y    :: BASE_BTN_H + 8
UPGRADE_DY         :: 48
UPGRADE_H          :: 36
QUEUE_DY           :: 108
QUEUE_LABEL_GAP    :: 23
DIALOG_PAD         :: 28
DIALOG_BTN_H       :: 44
HUD_PAD            :: 16
BADGE_PAD          :: 8
BADGE_GAP          :: 8
BADGE_Y            :: 72
BADGE_H            :: 20
BOTTOM_DOCK_H      :: 36
ROSTER_BASE_Y      :: 150
ROSTER_BELOW_QUEUE :: 206

MAX_PENDING        :: 25
TILE_SIZE          :: 20
TILE_GAP           :: 10
TILES_PER_ROW      :: 10
DOUBLE_CLICK_TIME  :: 0.35 // seconds: maximum time interval between clicks to register a double-click

// Camera framing
CAMERA_START_Y     :: 200.0 - 185.0 * 0.60

// =========================================================================
// Sci-Fi Cyberpunk HUD Palette
// =========================================================================

SCIFI_CYAN        :: rl.Color{0, 240, 216, 255}    // Primary vibrant laser cyan (#00F0D8)
SCIFI_MINT        :: rl.Color{140, 255, 235, 255}  // Bright highlight & glow (#8CFFEB)
SCIFI_BLUE        :: rl.Color{0, 200, 245, 255}    // Combat / wing blue (#00C8F5)
SCIFI_AMBER       :: rl.Color{255, 128, 36, 255}   // Tactical amber / warning accent (#FF8024)
SCIFI_AMBER_DIM   :: rl.Color{140, 65, 18, 255}    // Dim amber (#8C4112)
SCIFI_RED         :: rl.Color{255, 60, 75, 255}    // Hostile / alert red (#FF3C4B)
SCIFI_RED_DIM     :: rl.Color{120, 30, 40, 255}    // Dim hostile red (#781E28)
SCIFI_STEEL       :: rl.Color{18, 110, 122, 255}   // Active framing & border (#126E7A)
SCIFI_DIM         :: rl.Color{6, 58, 68, 255}      // Inactive grid & frames (#063A44)
SCIFI_PANEL       :: rl.Color{6, 16, 22, 240}      // Translucent deep teal glass (#061016)
SCIFI_PANEL_SOLID :: rl.Color{8, 22, 30, 255}      // Solid dark teal backing (#08161E)
SCIFI_TEXT        :: rl.Color{215, 245, 245, 255}  // Primary crisp text (#D7F5F5)
SCIFI_MUTED       :: rl.Color{85, 145, 155, 255}   // Secondary muted tech text (#55919B)

// =========================================================================
// System & Sector Topology Constants
// =========================================================================

MAX_BASES   :: 5
MAX_UNITS   :: 2560
PLANET_COUNT :: 8

MERCURY :: 0
VENUS   :: 1
EARTH   :: 2
MARS    :: 3
JUPITER :: 4
SATURN  :: 5
URANUS  :: 6
NEPTUNE :: 7

Planet_Index :: enum {
	MERCURY = 0,
	VENUS   = 1,
	EARTH   = 2,
	MARS    = 3,
	JUPITER = 4,
	SATURN  = 5,
	URANUS  = 6,
	NEPTUNE = 7,
}

SECTOR_COUNT :: PLANET_COUNT + 1
ENEMY_HOME   :: PLANET_COUNT
NO_RALLY     :: -1

Sector_Index :: enum {
	MERCURY  = 0,
	VENUS    = 1,
	EARTH    = 2,
	MARS     = 3,
	JUPITER  = 4,
	SATURN   = 5,
	URANUS   = 6,
	NEPTUNE  = 7,
	ENEMY_HQ = 8,
}

// =========================================================================
// Gameplay Configuration & Wave Constants
// =========================================================================

MINER_COST          :: 50
COMBAT_COST         :: 125
BATCH_BUILD_COUNT   :: 5
BATCH_MINER_COST    :: MINER_COST * BATCH_BUILD_COUNT
BATCH_COMBAT_COST   :: COMBAT_COST * BATCH_BUILD_COUNT

ENEMY_HQ_RADIUS     :: 4.8
ENEMY_HQ_GARRISON   :: 500
ENEMY_HQ_BASE_HP    :: 500

COMBAT_TICK          :: 0.2
HQ_COMBAT_TICK       :: COMBAT_TICK / 5
COMBAT_TICK_HQ       :: HQ_COMBAT_TICK
ENEMY_HQ_COMBAT_TICK :: HQ_COMBAT_TICK
COMBAT_TICK_ENEMY_HQ :: HQ_COMBAT_TICK
BASE_SIEGE_TIME      :: 2.0

WAVE_FIRST_DELAY            :: 180
WAVE_INTERVAL               :: 180
WAVE_MIN_LIBERATED_PLANETS  :: 2
WAVE_MIN_MINING_PLANETS     :: 2
WAVE_FIGHTERS_PER_LIBERATED :: 15

MINOR_WAVE_INTERVAL :: 75.0
MINOR_WAVE_SIZE     :: 10

MINER_BUILD_TIME          :: 4.0
COMBAT_BUILD_TIME         :: 8.0
BASE_COST                 :: 500
DRONE_SPEED_UPGRADE_COST  :: 5000
DRONE_SPEED_UPGRADE_MAX   :: 5
DRONE_SPEED_UPGRADE_FACTOR:: 0.8
BASE_CONSTRUCT_MINERS     :: 5
BASE_CONSTRUCT_TIME       :: 60.0

REFINERY_BUILD_TIME       :: 60.0
REFINERY_CONSTRUCT_MINERS :: 10

COMBAT_TRANSIT_SPEED :: 2.5
MINING_TRANSIT_SPEED :: 1.3125
MINING_DURATION      :: 4.0
DEPOSIT_DURATION     :: 0.5
SCOUT_SURVIVAL       :: 3.5
COMBAT_VISION_LINGER :: 3.0

LASER_BOLT_SPEED     :: 14.0
LASER_BOLT_LEN       :: 0.65

ORBITAL_DEFENSE_COST                  :: 1000
ORBITAL_DEFENSE_MAX_LEVEL             :: 10
ORBITAL_DEFENSE_BUILD_TIME            :: 60.0
ORBITAL_DEFENSE_CONSTRUCT_MINERS      :: 10
ORBITAL_DEFENSE_HP_PER_LEVEL          :: 100
ORBITAL_DEFENSE_KILLS_PER_LEVEL       :: 10
ORBITAL_DEFENSE_SCAN_SPEED            :: 0.8
ORBITAL_DEFENSE_TRACK_SPEED           :: 3.8
ORBITAL_DEFENSE_ELEV_SPEED            :: 2.4
ORBITAL_DEFENSE_IDLE_ELEV             :: 38.0 * rl.DEG2RAD
ORBITAL_DEFENSE_PARK_ELEV             :: 16.0 * rl.DEG2RAD
ORBITAL_DEFENSE_TARGET_RANGE          :: 6.0
ORBITAL_DEFENSE_WAVE_RESET_DELAY      :: 10.0

ORBITAL_DEFENSE_AMMO_MAX              :: 10
ORBITAL_DEFENSE_START_AMMO            :: 5
ORBITAL_DEFENSE_AMMO_COST             :: 200
ORBITAL_DEFENSE_AMMO_BUILD_TIME       :: 20.0
ORBITAL_DEFENSE_AMMO_CONSTRUCT_MINERS :: 1
ORBITAL_DEFENSE_KILLS_PER_SHOT        :: 10
ORBITAL_DEFENSE_FIRE_COOLDOWN         :: 0.5

MAX_ORBITAL_BLASTS :: 32

// =========================================================================
// Core Domain Enums
// =========================================================================

Unit_Type :: enum {
	MINING,
	COMBAT,
}

Unit_State :: enum {
	IDLE,
	TRANSIT,
	MINING,
	RETURNING,
	DEPOSITING,
	GUARDING,
	CONSTRUCTING,
}

Build_Target :: enum {
	NONE,
	BASE,
	REFINERY,
	ORBITAL_DEFENSE,
	ORBITAL_DEFENSE_AMMO,
}

Drone_Model_Kind :: enum {
	PLAYER_MINER,
	ENEMY_MINER,
	PLAYER_FIGHTER,
	ENEMY_FIGHTER,
}

Auto_Build_Mode :: enum {
	OFF,
	MINERS,
	COMBAT,
}

// =========================================================================
// Domain Structs
// =========================================================================

Planet :: struct {
	name:     cstring,
	position: rl.Vector3,
	radius:   f32,
	color:    rl.Color,
}

Production :: struct {
	kind:     Unit_Type,
	progress: f32,
	active:   bool,
}

INTEL_UNIT_CAP :: 200

Intel_Unit :: struct {
	kind:  Unit_Type,
	state: Unit_State,
	enemy: bool,
}

Intel :: struct {
	fighters:   int,
	miners:     int,
	base_hp:    int,
	units:      [INTEL_UNIT_CAP]Intel_Unit,
	unit_count: int,
}

Unit :: struct {
	kind:          Unit_Type,
	state:         Unit_State,
	position:      rl.Vector3,
	home_planet:   int,
	affiliation:   int,
	target_planet: int,
	enemy:         bool,
	progress:      f32,
	orbit_angle:   f32,
	squad:         int,
	build_target:  Build_Target,
	mining_active: bool,
}

Orbital_Defense_Blast :: struct {
	active:   bool,
	planet:   int,
	from:     rl.Vector3,
	to:       rl.Vector3,
	elapsed:  f32,
	duration: f32,
}

World_Sector_Spots :: struct {
	player_combat: [256]rl.Vector3,
	enemy_combat:  [256]rl.Vector3,
	player_miners: [256]rl.Vector3,
	enemy_miners:  [256]rl.Vector3,
	pc:            int,
	ec:            int,
	pmc:           int,
	emc:           int,
}

// =========================================================================
// Sector Safety Helpers
// =========================================================================

is_valid_planet :: proc(p: int) -> bool {
	return p >= 0 && p < PLANET_COUNT
}

is_valid_sector :: proc(s: int) -> bool {
	return s >= 0 && s < SECTOR_COUNT
}
