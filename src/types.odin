package main

import rl "vendor:raylib"

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

CARD_LINE_1        :: OUTPOST_CARD_Y + 14
CARD_LINE_2        :: OUTPOST_CARD_Y + 33
REFINERY_BTN_Y     :: SECTION_TOP
ORBITAL_DEFENSE_BTN_Y :: 104
ORDERS_BASE_Y      :: 244
SECTION_BELOW_DY   :: 44
UPGRADE_DY         :: 48
UPGRADE_H          :: 36
QUEUE_DY           :: 108
QUEUE_LABEL_GAP    :: 23
HUD_PAD            :: 16
BADGE_PAD          :: 8
BADGE_GAP          :: 8
RESOURCE_HUD_H     :: 100
BADGE_Y            :: HUD_PAD + RESOURCE_HUD_H + 4
BADGE_H            :: 20
BOTTOM_DOCK_H      :: 36
BUTTON_RADIUS      :: 10
BUTTON_PAD_X       :: 14
BUTTON_LABEL_SIZE  :: 11
BUTTON_DETAIL_SIZE :: 9
BUTTON_KEY_SIZE    :: 10
ROSTER_BASE_Y      :: 150
ROSTER_BELOW_QUEUE :: 206

MAX_PENDING        :: 25
TILE_SIZE          :: 26
TILE_GAP           :: 4
TILES_PER_ROW      :: 10
DOUBLE_CLICK_TIME  :: 0.35

CAMERA_START_Y     :: 200.0 - 185.0 * 0.60
DRONE_LOD_DISTANCE   :: 70.0

SCIFI_GREEN       :: rl.Color{71, 252, 175, 255}
SCIFI_MINT        :: rl.Color{185, 239, 215, 255}
SCIFI_CYAN        :: rl.Color{40, 215, 255, 255}
SCIFI_BLUE        :: rl.Color{0, 200, 245, 255}
SCIFI_AMBER       :: rl.Color{255, 128, 36, 255}
SCIFI_AMBER_DIM   :: rl.Color{140, 65, 18, 255}
SCIFI_RED         :: rl.Color{255, 60, 75, 255}
SCIFI_STEEL       :: rl.Color{24, 128, 84, 255}
SCIFI_DIM         :: rl.Color{10, 62, 40, 255}
SCIFI_PANEL       :: rl.Color{2, 12, 8, 255}
SCIFI_PANEL_SOLID :: rl.Color{4, 20, 13, 255}
SCIFI_TEXT        :: rl.Color{210, 245, 228, 255}
SCIFI_MUTED       :: rl.Color{92, 150, 122, 255}
SCIFI_LABEL       :: rl.Color{60, 215, 140, 255}
SCIFI_FILL        :: rl.Color{52, 192, 130, 255}
SCIFI_INK         :: rl.Color{2, 18, 10, 255}

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

SECTOR_COUNT :: PLANET_COUNT + 1
ENEMY_HOME   :: PLANET_COUNT
NO_RALLY     :: -1

MINER_COST          :: 50
COMBAT_COST         :: 125
BATCH_BUILD_COUNT   :: 5
BATCH_MINER_COST    :: MINER_COST * BATCH_BUILD_COUNT
BATCH_COMBAT_COST   :: COMBAT_COST * BATCH_BUILD_COUNT

ENEMY_HQ_RADIUS     :: 4.8
ENEMY_HQ_GARRISON   :: 500
ENEMY_HQ_BASE_HP    :: 500
HQ_BATTERY_PIVOT    :: rl.Vector3{0.3, 2.77, 0}
HQ_MUZZLE_REACH     :: 3.25
ORBITAL_DEFENSE_PIVOT        :: rl.Vector3{0.03, 0.58, 0}
ORBITAL_DEFENSE_MUZZLE_REACH :: 1.97

COMBAT_TICK          :: 0.2
HQ_COMBAT_TICK       :: COMBAT_TICK / 5
BASE_SIEGE_TIME      :: 2.0

WAVE_FIRST_DELAY            :: 180
WAVE_INTERVAL               :: 180
WAVE_MIN_LIBERATED_PLANETS  :: 2
WAVE_FIGHTERS_PER_LIBERATED :: 15

MINOR_WAVE_INTERVAL :: 75.0
MINOR_WAVE_SIZE     :: 10
ORBIT_SPEED               :: 0.9
ORBIT_EVEN_SPACING_MAX    :: 25
ORBIT_SPACING_CATCHUP     :: 1.25
ORBIT_SPACING_SLOWDOWN    :: 0.85
ORBIT_SPACING_GAIN       :: 3.0
ORBIT_SPACING_SNAP        :: 0.003

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

MAX_ORBITAL_BLASTS    :: 64
ORBITAL_BEAM_DURATION :: 0.24
ORBITAL_BEAM_STAGGER  :: 0.07
ORBITAL_BEAM_EXTEND   :: 0.2

MAX_DRONE_WRECKS     :: 256
DRONE_WRECK_LIFETIME :: 2.4
DRONE_WRECK_FADE     :: 0.5
DRONE_WRECK_GRAY     :: 0.35
DRONE_WRECK_GRAVITY  :: 0.55
DRONE_WRECK_DRAG     :: 0.7
DRONE_WRECK_DRIFT    :: 0.35
DRONE_WRECK_SCATTER  :: 1.5
DRONE_WRECK_POP      :: 0.25
DRONE_WRECK_SPIN     :: 1.3
DRONE_WRECK_FLASH    :: 0.3

Unit_Type :: enum {
	MINING,
	COMBAT,
}

Unit_State :: enum {
	IDLE,
	TRANSIT,
	MINING,
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
	orbit_placed:  bool,
	squad:        int,
	build_target:  Build_Target,
	mining_active: bool,
}

Orbital_Defense_Blast :: struct {
	active:   bool,
	planet:   int,
	from:     rl.Vector3,
	to:       rl.Vector3,
	elapsed:  f32,
	delay:    f32,
	duration: f32,
}

Drone_Wreck :: struct {
	active:    bool,
	kind:      Unit_Type,
	sector:    int,
	position:  rl.Vector3,
	velocity:  rl.Vector3,
	heading:   rl.Vector3,
	kick:      rl.Vector3,
	spin_axis: rl.Vector3,
	spin_rate: f32,
	delay:     f32,
	elapsed:   f32,
	struck:    bool,
}

World_Sector_Spots :: struct {
	player_combat: [MAX_UNITS]rl.Vector3,
	enemy_combat:  [MAX_UNITS]rl.Vector3,
	player_miners: [MAX_UNITS]rl.Vector3,
	enemy_miners:  [MAX_UNITS]rl.Vector3,
	pc:            int,
	ec:            int,
	pmc:           int,
	emc:           int,
}
