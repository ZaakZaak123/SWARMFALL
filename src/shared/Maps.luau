--!strict
-- Map definitions: geometry (single source of truth for builder, simulation, client) + run script.
-- Plane is XZ, floor top at Y = 0. Data is authored as a map (east = +X); X is mirrored once at the end
-- so that "east" renders on screen-right with our camera (Roblox is right-handed).
--
-- SPOREFALL has one world: the Bloom Crater (DD-030). Both map ids share its geometry; they differ in
-- the hour (dusk / blood night) and the run script. Ids are data keys (profile migration) — keep them.

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

-- THE BLOOM CRATER --------------------------------------------------------------------------------------
-- A rounded crater ~270 studs across. North: the bones of a fallen titan — its skull sits in the rim and
-- the swarm pours out of its jaws, ribs arch over the northern approach. South: our dropship, where every
-- hunt starts. East: a grove of pink xenite crystals. West: a forest of glowing mushrooms. Centre: the
-- extractor drilling the mother crystal. Corners: cliff masses with spore wounds the swarm crawls out of.
local function crater(): ({ Obstacle }, { { x: number, z: number } })
	local list, box, round = builder()
	round("ReactorCore", 0, 0, 12, 16, "reactor")
	-- titan ribs: pairs of feet; the arches above are decor (Arena)
	for i, z in { 70, 88, 106 } do
		round("RibW" .. i, -22, z, 5, 5, "ribfoot")
		round("RibE" .. i, 22, z, 5, 5, "ribfoot")
	end
	box("Dropship", 0, -104, 34, 16, 10, "dropship")
	-- xenite grove (east)
	round("XeniteA", 100, 22, 12, 16, "crystal")
	round("XeniteB", 92, -18, 9, 11, "crystal")
	round("XeniteC", 114, -6, 7, 9, "crystal")
	round("XeniteD", 84, 42, 6, 7, "crystal")
	-- mushroom forest (west)
	round("ShroomA", -100, 24, 6, 22, "mushroom")
	round("ShroomB", -92, -22, 5, 16, "mushroom")
	round("ShroomC", -114, -4, 4, 12, "mushroom")
	round("ShroomD", -80, 46, 3.5, 9, "mushroom")
	-- basalt boulders: mid-ring cover
	round("BoulderNE", 40, 62, 10, 7, "boulder")
	round("BoulderSW", -40, -62, 10, 7, "boulder")
	round("BoulderSE", 64, -46, 8, 6, "boulder")
	round("BoulderNW", -64, 40, 8, 6, "boulder")
	-- spore pylons (the old relay coils): zap the swarm coming down the diagonals
	local coils = { { x = 38, z = 38 }, { x = -38, z = 38 }, { x = 38, z = -38 }, { x = -38, z = -38 } }
	for i, c in coils do
		round("Coil" .. i, c.x, c.z, 4, 12, "coil")
	end
	-- cliff masses close the corners into a rounded bowl
	for _, s in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		round("Cliff", 150 * s[1], 150 * s[2], 150, 40, "cliff")
	end
	return list, coils
end

local CRATER_SPAWNS = function()
	return {
		N = { x = 0, z = 126 },
		NE = { x = 86, z = 86 },
		E = { x = 126, z = 0 },
		SE = { x = 86, z = -86 },
		S = { x = 0, z = -128 },
		SW = { x = -86, z = -86 },
		W = { x = -126, z = 0 },
		NW = { x = -86, z = 86 },
	}
end

do
	local list, coils = crater()
	local def: MapDef = {
		id = "MAP_REACTOR_YARD",
		index = 1,
		name = "ВОРОНКА У СТАНЦИИ",
		subtitle = "Воронка у старой буровой станции. Рой гнездится в останках гиганта.",
		theme = "dusk",
		unlock = "",
		halfX = 140,
		halfZ = 140,
		wall = 4,
		playerStart = { x = 0, z = -26 },
		obstacles = list,
		coils = coils,
		spawns = CRATER_SPAWNS(),
		spawnOrder = SPAWN_ORDER,
		hiveSites = { { x = -60, z = 80 }, { x = 72, z = -70 }, { x = -70, z = -30 } },
		bossEntry = { x = 0, z = 116 },
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
			{ at = 420, label = "МАТЬ РОЯ", rate = 1.5, cap = 26, dirs = { "E", "W", "S" }, w = { EN_RUNNER = 0.8, EN_STALKER = 0.2 } },
			{ at = 480, label = "ЯРОСТЬ", rate = 2.4, cap = 34, dirs = { "E", "W", "S", "SE", "SW" }, w = { EN_RUNNER = 0.7, EN_STALKER = 0.3 } },
		},
		events = { elites = { 150, 270 }, hiveStart = 330, hiveEnd = 385 },
	}
	mirror(def)
	Maps.MAP_REACTOR_YARD = def
end

do
	local list, coils = crater()
	local def: MapDef = {
		id = "MAP_HIVE_DEPTHS",
		index = 2,
		name = "КРОВАВАЯ НОЧЬ",
		subtitle = "Та же воронка после заката. Взрывуны. Из-под земли идёт Пожиратель.",
		theme = "night",
		unlock = "Победи Мать роя",
		halfX = 140,
		halfZ = 140,
		wall = 4,
		playerStart = { x = 0, z = -26 },
		obstacles = list,
		coils = coils,
		spawns = CRATER_SPAWNS(),
		spawnOrder = SPAWN_ORDER,
		hiveSites = { { x = -60, z = 80 }, { x = 72, z = -70 }, { x = -70, z = -30 } },
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
