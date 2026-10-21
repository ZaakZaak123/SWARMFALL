--!strict
-- Map definitions: geometry (single source of truth for builder, simulation, client) + run script.
-- Plane is XZ, floor top at Y = 0. Data is authored as a map (east = +X); X is mirrored once at the end
-- so that "east" renders on screen-right with our camera (Roblox is right-handed).

export type Obstacle = {
	name: string,
	shape: string, -- "box" | "round"
	x: number,
	z: number,
	w: number,
	d: number,
	h: number,
	style: string,
}

export type Phase = { at: number, label: string, rate: number, cap: number, dirs: { string }, w: { [string]: number } }

export type MapDef = {
	id: string,
	index: number,
	name: string,
	subtitle: string,
	theme: string,
	unlock: string, -- human readable unlock rule
	halfX: number,
	halfZ: number,
	wall: number,
	playerStart: { x: number, z: number },
	obstacles: { Obstacle },
	coils: { { x: number, z: number } },
	spawns: { [string]: { x: number, z: number } },
	spawnOrder: { string },
	hiveSites: { { x: number, z: number } },
	bossEntry: { x: number, z: number },
	boss: string,
	elite: string,
	phases: { Phase },
	events: { elites: { number }, hiveStart: number, hiveEnd: number },
}

local Maps = {}

local SPAWN_ORDER = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function builder()
	local list: { Obstacle } = {}
	local function box(name: string, x: number, z: number, w: number, d: number, h: number, style: string)
		table.insert(list, { name = name, shape = "box", x = x, z = z, w = w, d = d, h = h, style = style })
	end
	local function round(name: string, x: number, z: number, diameter: number, h: number, style: string)
		table.insert(list, { name = name, shape = "round", x = x, z = z, w = diameter, d = diameter, h = h, style = style })
	end
	return list, box, round
end

local function mirror(def: MapDef)
	for _, o in def.obstacles do
		o.x = -o.x
	end
	for _, c in def.coils do
		c.x = -c.x
	end
	for _, h in def.hiveSites do
		h.x = -h.x
	end
	for _, s in def.spawns do
		s.x = -s.x
	end
	def.bossEntry.x = -def.bossEntry.x
	def.playerStart.x = -def.playerStart.x
end

-- MAP 1: REACTOR YARD ---------------------------------------------------------------------------------
do
	local list, box, round = builder()
	round("ReactorCore", 0, 0, 12, 14, "reactor")
	box("CoreBarrierW", -24, 0, 3, 10, 4, "barrier")
	box("CoreBarrierE", 24, 0, 3, 10, 4, "barrier")
	box("CoreBarrierN", 0, 25, 10, 3, 4, "barrier")
	box("CoreBarrierS", 0, -27, 10, 3, 4, "barrier")
	box("ConduitW1", -30, 66, 8, 18, 8, "container")
	box("ConduitE1", 30, 66, 8, 18, 8, "container")
	box("ConduitW2", -30, 110, 8, 18, 8, "container")
	box("ConduitE2", 30, 110, 8, 18, 8, "container")
	box("RailsNorth", 112, 32, 22, 8, 6, "railcar")
	box("RailsSouth", 112, -32, 22, 8, 6, "railcar")
	round("RailsPylon", 150, 0, 6, 10, "pylon")
	round("RefineryW", -34, -94, 18, 12, "tank")
	round("RefineryE", 34, -94, 18, 12, "tank")
	round("RefineryValve", 0, -126, 8, 6, "tank")
	box("HangarNW", -125, 32, 18, 8, 9, "container")
	box("HangarSW", -125, -32, 18, 8, 9, "container")
	box("HangarCargo", -102, 0, 8, 18, 6, "crate")
	box("YardNE", 96, 98, 18, 8, 8, "container")
	box("YardNW", -96, 98, 8, 18, 8, "container")
	round("YardSE", 96, -98, 12, 9, "tank")
	box("YardSW", -96, -98, 18, 8, 8, "crate")
	box("BlockN", 70, 128, 8, 8, 5, "crate")
	box("BlockS", -70, -128, 8, 8, 5, "crate")
	box("BlockE", 140, 66, 8, 8, 5, "crate")
	box("BlockW", -140, -66, 8, 8, 5, "crate")
	round("Coil1", 62, 58, 4, 11, "coil")
	round("Coil2", -62, 58, 4, 11, "coil")
	round("Coil3", 62, -58, 4, 11, "coil")
	round("Coil4", -62, -58, 4, 11, "coil")

	local def: MapDef = {
		id = "MAP_REACTOR_YARD",
		index = 1,
		name = "РЕАКТОРНЫЙ ДВОР",
		subtitle = "Промзона под открытым небом. Матка рвётся с севера.",
		theme = "yard",
		unlock = "",
		halfX = 180,
		halfZ = 160,
		wall = 4,
		playerStart = { x = 0, z = -16 },
		obstacles = list,
		coils = { { x = 62, z = 58 }, { x = -62, z = 58 }, { x = 62, z = -58 }, { x = -62, z = -58 } },
		spawns = {
			N = { x = 0, z = 148 },
			NE = { x = 132, z = 136 },
			E = { x = 168, z = 0 },
			SE = { x = 132, z = -136 },
			S = { x = 0, z = -148 },
			SW = { x = -132, z = -136 },
			W = { x = -168, z = 0 },
			NW = { x = -132, z = 136 },
		},
		spawnOrder = SPAWN_ORDER,
		hiveSites = { { x = -82, z = 74 }, { x = 104, z = -70 }, { x = 0, z = -62 } },
		bossEntry = { x = 0, z = 150 },
		boss = "BOSS_BROODMOTHER",
		elite = "ELITE_BULWARK",
		phases = {
			{ at = 0, label = "КОНТАКТ", rate = 1.7, cap = 22, dirs = { "N", "E", "NE" }, w = { EN_RUNNER = 1 } },
			{ at = 30, label = "НАРАСТАНИЕ", rate = 2.8, cap = 36, dirs = { "N", "E", "NE", "SE" }, w = { EN_RUNNER = 0.84, EN_STALKER = 0.16 } },
			{ at = 90, label = "КИСЛОТНЫЙ ДОЖДЬ", rate = 3.5, cap = 46, dirs = { "N", "E", "W", "S", "NE" }, w = { EN_RUNNER = 0.66, EN_STALKER = 0.18, EN_SPITTER = 0.16 } },
			{ at = 150, label = "ЭЛИТА", rate = 3.2, cap = 46, dirs = { "N", "E", "W", "S", "SW", "NW" }, w = { EN_RUNNER = 0.66, EN_STALKER = 0.16, EN_SPITTER = 0.12, EN_BULWARK = 0.06 } },
			{ at = 210, label = "ПРОРЫВ", rate = 4.8, cap = 62, dirs = SPAWN_ORDER, w = { EN_RUNNER = 0.6, EN_STALKER = 0.18, EN_SPITTER = 0.12, EN_BULWARK = 0.1 } },
			{ at = 270, label = "ВТОРАЯ ЭЛИТА", rate = 5.2, cap = 72, dirs = SPAWN_ORDER, w = { EN_RUNNER = 0.6, EN_STALKER = 0.18, EN_SPITTER = 0.12, EN_BULWARK = 0.1 } },
			{ at = 300, label = "РОЙ", rate = 8.5, cap = 96, dirs = SPAWN_ORDER, w = { EN_RUNNER = 0.84, EN_STALKER = 0.1, EN_SPITTER = 0.03, EN_BULWARK = 0.03 } },
			{ at = 330, label = "ПРОРЫВ УЛЬЯ", rate = 3.0, cap = 60, dirs = { "N", "S", "E", "W" }, w = { EN_RUNNER = 0.75, EN_STALKER = 0.15, EN_SPITTER = 0.1 } },
			{ at = 380, label = "ПЕРЕДЫШКА", rate = 1.0, cap = 18, dirs = { "N", "S" }, w = { EN_RUNNER = 0.8, EN_STALKER = 0.2 } },
			{ at = 420, label = "МАТКА", rate = 1.5, cap = 26, dirs = { "E", "W", "S" }, w = { EN_RUNNER = 0.8, EN_STALKER = 0.2 } },
			{ at = 480, label = "ЯРОСТЬ", rate = 2.4, cap = 34, dirs = { "E", "W", "S", "SE", "SW" }, w = { EN_RUNNER = 0.7, EN_STALKER = 0.3 } },
		},
		events = { elites = { 150, 270 }, hiveStart = 330, hiveEnd = 385 },
	}
	mirror(def)
	Maps.MAP_REACTOR_YARD = def
end

-- MAP 2: HIVE DEPTHS ----------------------------------------------------------------------------------
do
	local list, box, round = builder()
	round("HeartSpire", 0, 0, 10, 18, "spire")
	for i = 0, 5 do
		local a = math.rad(30 + i * 60)
		round("Pillar" .. i, math.cos(a) * 45, math.sin(a) * 45, if i % 2 == 0 then 9 else 7, 14, "stalagmite")
	end
	for i = 0, 7 do
		local a = math.rad(22.5 + i * 45)
		round("Mound" .. i, math.cos(a) * 96, math.sin(a) * 96, if i % 2 == 0 then 18 else 14, 7, "mound")
	end
	box("RigS", 60, -112, 16, 8, 7, "rig")
	box("RigN", -70, 108, 8, 16, 7, "rig")
	box("RigE", 122, 44, 10, 10, 6, "rig")
	box("RigW", -122, -44, 10, 10, 6, "rig")
	round("Coil1", 0, 76, 4, 11, "coil")
	round("Coil2", 0, -76, 4, 11, "coil")
	round("Coil3", 80, 0, 4, 11, "coil")
	round("Coil4", -80, 0, 4, 11, "coil")

	local def: MapDef = {
		id = "MAP_HIVE_DEPTHS",
		index = 2,
		name = "ГЛУБИНЫ УЛЬЯ",
		subtitle = "Пещера под реактором. Взрывуны. Из-под земли идёт Пожиратель.",
		theme = "depths",
		unlock = "Победи Матку на Реакторном дворе",
		halfX = 160,
		halfZ = 150,
		wall = 4,
		playerStart = { x = 0, z = -18 },
		obstacles = list,
		coils = { { x = 0, z = 76 }, { x = 0, z = -76 }, { x = 80, z = 0 }, { x = -80, z = 0 } },
		spawns = {
			N = { x = 0, z = 138 },
			NE = { x = 112, z = 112 },
			E = { x = 148, z = 0 },
			SE = { x = 112, z = -112 },
			S = { x = 0, z = -138 },
			SW = { x = -112, z = -112 },
			W = { x = -148, z = 0 },
			NW = { x = -112, z = 112 },
		},
		spawnOrder = SPAWN_ORDER,
		hiveSites = { { x = 56, z = 56 }, { x = -60, z = -50 }, { x = 70, z = -62 } },
		bossEntry = { x = 0, z = 100 },
		boss = "BOSS_DEVOURER",
		elite = "ELITE_BULWARK",
		phases = {
			{ at = 0, label = "СПУСК", rate = 1.9, cap = 24, dirs = { "N", "NE", "NW" }, w = { EN_RUNNER = 0.9, EN_BOMBER = 0.1 } },
			{ at = 30, label = "ШЁПОТ УЛЬЯ", rate = 3.0, cap = 38, dirs = { "N", "E", "W", "NE", "NW" }, w = { EN_RUNNER = 0.7, EN_STALKER = 0.15, EN_BOMBER = 0.15 } },
			{ at = 90, label = "ДЫМЯЩИЕ ТОННЕЛИ", rate = 3.7, cap = 48, dirs = SPAWN_ORDER, w = { EN_RUNNER = 0.55, EN_STALKER = 0.15, EN_SPITTER = 0.12, EN_BOMBER = 0.18 } },
			{ at = 150, label = "ЭЛИТА", rate = 3.4, cap = 48, dirs = SPAWN_ORDER, w = { EN_RUNNER = 0.55, EN_STALKER = 0.15, EN_SPITTER = 0.1, EN_BOMBER = 0.14, EN_BULWARK = 0.06 } },
			{ at = 210, label = "ОБВАЛ", rate = 5.0, cap = 64, dirs = SPAWN_ORDER, w = { EN_RUNNER = 0.5, EN_STALKER = 0.16, EN_SPITTER = 0.1, EN_BOMBER = 0.16, EN_BULWARK = 0.08 } },
			{ at = 270, label = "ВТОРАЯ ЭЛИТА", rate = 5.4, cap = 74, dirs = SPAWN_ORDER, w = { EN_RUNNER = 0.5, EN_STALKER = 0.16, EN_SPITTER = 0.1, EN_BOMBER = 0.16, EN_BULWARK = 0.08 } },
			{ at = 300, label = "ЦЕПНАЯ РЕАКЦИЯ", rate = 8.5, cap = 96, dirs = SPAWN_ORDER, w = { EN_RUNNER = 0.62, EN_BOMBER = 0.3, EN_STALKER = 0.08 } },
			{ at = 330, label = "ПРОРЫВ УЛЬЯ", rate = 3.0, cap = 60, dirs = SPAWN_ORDER, w = { EN_RUNNER = 0.6, EN_BOMBER = 0.25, EN_SPITTER = 0.15 } },
			{ at = 380, label = "ТИШИНА", rate = 1.0, cap = 18, dirs = { "S", "E", "W" }, w = { EN_RUNNER = 0.8, EN_BOMBER = 0.2 } },
			{ at = 420, label = "ПОЖИРАТЕЛЬ", rate = 1.4, cap = 24, dirs = { "E", "W", "S" }, w = { EN_RUNNER = 0.7, EN_BOMBER = 0.3 } },
			{ at = 480, label = "ЯРОСТЬ", rate = 2.2, cap = 32, dirs = SPAWN_ORDER, w = { EN_RUNNER = 0.6, EN_BOMBER = 0.4 } },
		},
		events = { elites = { 150, 270 }, hiveStart = 330, hiveEnd = 385 },
	}
	mirror(def)
	Maps.MAP_HIVE_DEPTHS = def
end

Maps.Order = { "MAP_REACTOR_YARD", "MAP_HIVE_DEPTHS" }

function Maps.get(id: string?): MapDef
	return (id and (Maps :: any)[id]) or Maps.MAP_REACTOR_YARD
end

return Maps
