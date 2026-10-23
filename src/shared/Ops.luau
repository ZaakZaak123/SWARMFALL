--!strict
-- Operations ("ОПЕРАЦИИ"): the scenario layer on top of a map. A map is geometry; an operation is what
-- happens on it — spawn phases, scripted beats, the objective and what the first win unlocks.
-- Canon: design/handoff/02_GAME_SPECS/SWARMFALL_D02_OPERATIONS_SPEC_v0.3.md. Numbers are TUNABLE;
-- tests/ops_run.luau checks that every operation is winnable by a defending bot with the start rifle.

local Maps = require(script.Parent.Maps)

local Ops = {}

export type Phase = {
	at: number,
	label: string,
	rate: number,
	cap: number,
	dirs: { string },
	w: { [string]: number },
	quiet: boolean?, -- no banner when the phase starts
}

-- Beat types:
--   "assault"   strike group on the reactor (or `target = "relay"`)       count, kind?, dir?
--   "ring"      encirclement around the player (O01: S01 lesson)            count
--   "elite"     objective elite (O01 carrier) or a legacy elite
--   "hive"      optional nests (boss operations)
--   "nests"     three objective nests, any two win (O03)
--   "guard"     a Bulwark escort at an objective nest                      index?
--   "relay"     activate the outer relay coil (O02)
--   "nodes"     two power nodes to destroy (O05)
--   "acid"      two acid sources to destroy (C-A01)
--   "boss", "enrage", "banner"
export type Beat = {
	at: number,
	type: string,
	count: number?,
	kind: string?,
	dir: string?,
	target: string?,
	index: number?,
	title: string?,
	sub: string?,
}

export type OpDef = {
	id: string,
	index: number,
	code: string,
	name: string,
	map: string,
	brief: string,
	goal: string, -- one-line HUD objective at start
	objective: string, -- "carrier" | "relay" | "nests" | "nodes" | "acid" | "boss"
	reactor: { hp: number, radius: number?, name: string? }?,
	eliteName: string?,
	eliteHpMult: number?,
	eliteGoal: string?,
	finale: Phase?, -- final pressure after the objective is done (non-boss operations, D02 §3)
	finaleTime: number?,
	deadline: number?, -- objectiveDeadline: the objective must be done by then (D02 §3.1)
	hardLimit: number?, -- absoluteTerminalCap
	s01Event: boolean?,
	runEvolution: boolean,
	relay: { need: number, radius: number, hp: number, primary: number, backup: number }?,
	nests: { need: number, hp: number }?,
	nodes: { hp: number, count: number }?,
	acid: { hp: number, every: number, count: number }?,
	spawnMult: number?,
	bossHpMult: number?,
	playerDamageMult: number?, -- damage the swarm deals to players (O01: forgiving first run)
	phases: { Phase },
	beats: { Beat },
	unlocks: { string },
	requires: string?,
	chapterEnd: boolean?,
}

local ALL = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- O01 «ПЕРВЫЙ КОНТАКТ» — the first three minutes of the game (DD-024 overrides GDD §5 timings). One
-- enemy type, one rule (protect the reactor), one wow moment (S01 at the encirclement ~1:25), one big
-- enemy (the Carrier ~2:10), a short final swarm. Spitters debut in O02.
Ops.O01 = {
	id = "O01",
	index = 1,
	code = "O01",
	name = "ПЕРВЫЙ КОНТАКТ",
	map = "MAP_REACTOR_YARD",
	brief = "Рой идёт к реактору. Отстреливайся, убей Носителя ядра и продержись.",
	goal = "Защити реактор",
	objective = "carrier",
	reactor = { hp = 1500 }, -- the first operation must be forgiving
	playerDamageMult = 0.6,
	eliteName = "НОСИТЕЛЬ ЯДРА",
	eliteGoal = "Убей Носителя ядра",
	eliteHpMult = 0.45, -- first big enemy of the game: a 15–25 s fight, not a sponge
	runEvolution = false,
	s01Event = true, -- the encirclement introduces S01 to profiles that do not have it yet
	finaleTime = 20,
	deadline = 300,
	hardLimit = 360,
	finale = { at = 0, label = "ФИНАЛЬНЫЙ РОЙ", rate = 9.0, cap = 80, dirs = ALL, w = { EN_RUNNER = 1 } },
	phases = {
		{ at = 0, label = "КОНТАКТ", rate = 2.6, cap = 24, dirs = { "N", "NE" }, w = { EN_RUNNER = 1 }, quiet = true },
		{ at = 25, label = "НАРАСТАНИЕ", rate = 4.0, cap = 40, dirs = { "N", "E", "NE", "SE" }, w = { EN_RUNNER = 1 } },
		{ at = 70, label = "ОКРУЖЕНИЕ", rate = 4.8, cap = 56, dirs = ALL, w = { EN_RUNNER = 1 } },
		{ at = 105, label = "ДАВЛЕНИЕ", rate = 6.0, cap = 70, dirs = ALL, w = { EN_RUNNER = 1 } },
		{ at = 125, label = "НОСИТЕЛЬ ЯДРА", rate = 2.6, cap = 36, dirs = ALL, w = { EN_RUNNER = 1 }, quiet = true },
	},
	beats = {
		{ at = 35, type = "assault", count = 6 },
		{ at = 82, type = "ring", count = 26 },
		{ at = 108, type = "assault", count = 9 },
		{ at = 128, type = "elite" },
	},
	unlocks = { "O02" },
}

-- O02 «КЛЕЩИ ПЕРИМЕТРА» — D02 §5. Introduces the Stalker. The outer relay coil charges from kills inside
-- its zone (60; Runner +1, Spitter +2, Stalker +3). Stalker groups hunt the relay; if it falls before it is
-- charged, the backup coil takes over with 100% of the charge. Then hold the reactor.
Ops.O02 = {
	id = "O02",
	index = 2,
	code = "O02",
	name = "КЛЕЩИ ПЕРИМЕТРА",
	map = "MAP_REACTOR_YARD",
	brief = "Прыгуны режут периметр. Заряди внешнюю катушку убийствами рядом с ней, затем удержи реактор.",
	goal = "Защити реактор",
	objective = "relay",
	reactor = { hp = 2100 },
	runEvolution = false,
	relay = { need = 400, radius = 30, hp = 800, primary = 1, backup = 2 }, -- 60 in D02 assumed a far lower kill rate
	finaleTime = 70,
	deadline = 480,
	hardLimit = 580,
	finale = { at = 0, label = "УДЕРЖАНИЕ", rate = 7.6, cap = 90, dirs = ALL, w = { EN_RUNNER = 0.8, EN_STALKER = 0.14, EN_SPITTER = 0.06 } },
	phases = {
		{ at = 0, label = "КОНТАКТ", rate = 2.2, cap = 28, dirs = { "N", "E", "W" }, w = { EN_RUNNER = 0.94, EN_STALKER = 0.06 }, quiet = true },
		{ at = 40, label = "ФЛАНГИ", rate = 3.2, cap = 42, dirs = { "N", "NE", "NW", "E", "W" }, w = { EN_RUNNER = 0.86, EN_STALKER = 0.1, EN_SPITTER = 0.04 } },
		{ at = 140, label = "СИГНАЛ", rate = 3.4, cap = 50, dirs = ALL, w = { EN_RUNNER = 0.84, EN_STALKER = 0.11, EN_SPITTER = 0.05 }, quiet = true },
		{ at = 160, label = "ЗАРЯДКА", rate = 4.6, cap = 64, dirs = ALL, w = { EN_RUNNER = 0.82, EN_STALKER = 0.12, EN_SPITTER = 0.06 } },
		{ at = 270, label = "КЛЕЩИ", rate = 5.6, cap = 76, dirs = ALL, w = { EN_RUNNER = 0.8, EN_STALKER = 0.14, EN_SPITTER = 0.06 } },
		{ at = 380, label = "ДАВЛЕНИЕ", rate = 6.0, cap = 80, dirs = ALL, w = { EN_RUNNER = 0.8, EN_STALKER = 0.14, EN_SPITTER = 0.06 } },
	},
	beats = {
		{ at = 30, type = "banner", title = "ПРЫГУН", sub = "Замирает перед прыжком — уйди в сторону", kind = "EN_STALKER" },
		{ at = 55, type = "assault", count = 7 },
		{ at = 70, type = "banner", title = "ПЛЕВУН", sub = "Плюётся кислотой издалека — уходи из луж", kind = "EN_SPITTER" },
		{ at = 125, type = "assault", count = 9 },
		{ at = 140, type = "relay" },
		{ at = 175, type = "assault", count = 5, kind = "EN_STALKER", target = "relay" },
		{ at = 210, type = "assault", count = 7 },
		{ at = 245, type = "assault", count = 6, kind = "EN_STALKER", target = "relay" },
		{ at = 285, type = "assault", count = 8 },
		{ at = 320, type = "assault", count = 7, kind = "EN_STALKER", target = "relay" },
		{ at = 360, type = "assault", count = 9 },
		{ at = 400, type = "assault", count = 8, kind = "EN_STALKER", target = "relay" },
	},
	unlocks = { "O03", "CA01" },
	requires = "O01",
}

-- O03 «ГНЕЗДОВОЙ ПРОРЫВ» — D02 §6. Three nests open at ~2:00; any two win (3/3 = optional +20 bonus).
-- Introduces the Bulwark, which escorts a nest.
Ops.O03 = {
	id = "O03",
	index = 3,
	code = "O03",
	name = "ГНЕЗДОВОЙ ПРОРЫВ",
	map = "MAP_REACTOR_YARD",
	brief = "Рой пустил корни во дворе. Уничтожь любые два гнезда из трёх, не потеряв реактор.",
	goal = "Защити реактор",
	objective = "nests",
	reactor = { hp = 2000 },
	runEvolution = false,
	nests = { need = 2, hp = 900 },
	finaleTime = 60,
	deadline = 500,
	hardLimit = 610,
	finale = { at = 0, label = "ЗАКЛЮЧИТЕЛЬНЫЙ НАТИСК", rate = 7.4, cap = 88, dirs = ALL, w = { EN_RUNNER = 0.78, EN_STALKER = 0.1, EN_SPITTER = 0.08, EN_BULWARK = 0.04 } },
	phases = {
		{ at = 0, label = "КОНТАКТ", rate = 2.4, cap = 30, dirs = { "N", "E", "W", "S" }, w = { EN_RUNNER = 0.86, EN_SPITTER = 0.07, EN_STALKER = 0.07 }, quiet = true },
		{ at = 50, label = "НАРАСТАНИЕ", rate = 3.4, cap = 46, dirs = ALL, w = { EN_RUNNER = 0.84, EN_SPITTER = 0.08, EN_STALKER = 0.08 } },
		{ at = 120, label = "ГНЁЗДА", rate = 3.6, cap = 56, dirs = ALL, w = { EN_RUNNER = 0.8, EN_SPITTER = 0.08, EN_STALKER = 0.08, EN_BULWARK = 0.04 }, quiet = true },
		{ at = 200, label = "ВЫБОР ЦЕЛИ", rate = 4.6, cap = 66, dirs = ALL, w = { EN_RUNNER = 0.78, EN_SPITTER = 0.09, EN_STALKER = 0.09, EN_BULWARK = 0.04 } },
		{ at = 320, label = "ДАВЛЕНИЕ", rate = 5.6, cap = 76, dirs = ALL, w = { EN_RUNNER = 0.78, EN_SPITTER = 0.09, EN_STALKER = 0.09, EN_BULWARK = 0.04 } },
	},
	beats = {
		{ at = 60, type = "assault", count = 6 },
		{ at = 120, type = "nests" },
		{ at = 135, type = "guard", index = 1 },
		{ at = 136, type = "banner", title = "БРОНЕНОСЕЦ", sub = "Броня спереди — заходи сбоку или со спины", kind = "EN_BULWARK" },
		{ at = 180, type = "assault", count = 7 },
		{ at = 235, type = "guard", index = 2 },
		{ at = 265, type = "assault", count = 8 },
		{ at = 330, type = "assault", count = 8, kind = "EN_SPITTER" },
		{ at = 400, type = "assault", count = 10 },
		{ at = 460, type = "assault", count = 10 },
	},
	unlocks = { "O04" },
	requires = "O02",
}

-- O04 «МАТКА РАЗЛОМА» — D02 §7. Two elites, the peak swarm, optional nests, then the Broodmother. Her
-- death wins at once. Reactor defended throughout.
do
	local yard = Maps.get("MAP_REACTOR_YARD")
	Ops.O04 = {
		id = "O04",
		index = 4,
		code = "O04",
		name = "МАТКА РАЗЛОМА",
		map = "MAP_REACTOR_YARD",
		brief = "Королева роя идёт к реактору. Переживи две элиты и пиковый рой, затем убей Матку.",
		goal = "Защити реактор и убей Матку",
		objective = "boss",
		spawnMult = 0.85,
		bossHpMult = 0.85,
		reactor = { hp = 1600 },
		runEvolution = false,
		hardLimit = 540,
		phases = yard.phases,
		beats = {
			{ at = 70, type = "assault", count = 8 },
			{ at = 150, type = "elite" },
			{ at = 200, type = "assault", count = 10 },
			{ at = 270, type = "elite" },
			{ at = 310, type = "assault", count = 12 },
			{ at = 330, type = "hive" },
			{ at = 420, type = "boss" },
			{ at = 480, type = "enrage" },
		},
		unlocks = { "O05" },
		requires = "O03",
	}
end

-- O05 «ЦЕПНАЯ РЕАКЦИЯ» — D02 §8. Hive Depths, the Bomber, two power nodes (shootable by any weapon;
-- bomber blasts help but are optional). The energy heart is the defended object.
Ops.O05 = {
	id = "O05",
	index = 5,
	code = "O05",
	name = "ЦЕПНАЯ РЕАКЦИЯ",
	map = "MAP_HIVE_DEPTHS",
	brief = "Под реактором пульсирует улей. Разрушь два питающих узла и удержи энергетическую сердцевину.",
	goal = "Защити сердцевину",
	objective = "nodes",
	reactor = { hp = 1500, radius = 6, name = "СЕРДЦЕВИНА" },
	runEvolution = false,
	nodes = { hp = 2400, count = 2 },
	finaleTime = 60,
	deadline = 480,
	hardLimit = 590,
	finale = { at = 0, label = "ПОСЛЕДНИЙ РОЙ", rate = 7.6, cap = 90, dirs = ALL, w = { EN_RUNNER = 0.66, EN_BOMBER = 0.22, EN_STALKER = 0.08, EN_SPITTER = 0.04 } },
	phases = {
		{ at = 0, label = "СПУСК", rate = 2.0, cap = 26, dirs = { "N", "NE", "NW" }, w = { EN_RUNNER = 0.92, EN_BOMBER = 0.08 }, quiet = true },
		{ at = 40, label = "ШЁПОТ УЛЬЯ", rate = 3.2, cap = 42, dirs = { "N", "E", "W", "NE", "NW" }, w = { EN_RUNNER = 0.76, EN_BOMBER = 0.14, EN_STALKER = 0.1 } },
		{ at = 90, label = "ПИТАЮЩИЕ УЗЛЫ", rate = 3.6, cap = 52, dirs = ALL, w = { EN_RUNNER = 0.7, EN_BOMBER = 0.16, EN_STALKER = 0.1, EN_SPITTER = 0.04 }, quiet = true },
		{ at = 210, label = "ДЫМЯЩИЕ ТОННЕЛИ", rate = 4.8, cap = 66, dirs = ALL, w = { EN_RUNNER = 0.66, EN_BOMBER = 0.2, EN_STALKER = 0.1, EN_SPITTER = 0.04 } },
		{ at = 330, label = "ЦЕПНАЯ РЕАКЦИЯ", rate = 6.0, cap = 80, dirs = ALL, w = { EN_RUNNER = 0.64, EN_BOMBER = 0.24, EN_STALKER = 0.08, EN_SPITTER = 0.04 } },
	},
	beats = {
		{ at = 20, type = "banner", title = "ВЗРЫВУН", sub = "Взрывается рядом с тобой — и задевает рой", kind = "EN_BOMBER" },
		{ at = 60, type = "assault", count = 8 },
		{ at = 90, type = "nodes", index = 1 },
		{ at = 140, type = "assault", count = 10 },
		{ at = 200, type = "assault", count = 10, kind = "EN_BOMBER" },
		{ at = 210, type = "nodes", index = 2 },
		{ at = 260, type = "assault", count = 12 },
		{ at = 320, type = "assault", count = 12 },
		{ at = 380, type = "assault", count = 14, kind = "EN_BOMBER" },
	},
	unlocks = { "O06" },
	requires = "O04",
}

-- O06 «СЕРДЦЕ ГЛУБИН» — D02 §9. Chapter finale: two elites, bombers, optional nests, the Devourer. His
-- death wins at once while the heart and the hero live.
do
	local depths = Maps.get("MAP_HIVE_DEPTHS")
	Ops.O06 = {
		id = "O06",
		index = 6,
		code = "O06",
		name = "СЕРДЦЕ ГЛУБИН",
		map = "MAP_HIVE_DEPTHS",
		brief = "Финал главы. Удержи сердцевину, переживи элиты и встреть Пожирателя.",
		goal = "Защити сердцевину и убей Пожирателя",
		objective = "boss",
		spawnMult = 0.85,
		bossHpMult = 0.75, -- the Devourer burrows; keep a viable boss window (D02 §9)
		reactor = { hp = 1700, radius = 6, name = "СЕРДЦЕВИНА" },
		runEvolution = false,
		hardLimit = 570,
		phases = depths.phases,
		beats = {
			{ at = 70, type = "assault", count = 8 },
			{ at = 150, type = "elite" },
			{ at = 200, type = "assault", count = 10, kind = "EN_BOMBER" },
			{ at = 270, type = "elite" },
			{ at = 300, type = "assault", count = 12 },
			{ at = 330, type = "hive" },
			{ at = 375, type = "boss" },
			{ at = 470, type = "enrage" },
		},
		unlocks = {},
		requires = "O05",
		chapterEnd = true,
	}
end

-- C-A01 «КИСЛОТНЫЙ ФРОНТ» — D02 §10. Optional contract after O02: Spitter-heavy yard, two acid sources
-- that keep seeding acid until destroyed by direct fire. Not a story key.
Ops.CA01 = {
	id = "CA01",
	index = 7,
	code = "C-A01",
	name = "КИСЛОТНЫЙ ФРОНТ",
	map = "MAP_REACTOR_YARD",
	brief = "Контракт: Плевуны травят двор кислотой. Уничтожь два кислотных источника и удержи периметр.",
	goal = "Защити реактор",
	objective = "acid",
	reactor = { hp = 1500 },
	runEvolution = false,
	acid = { hp = 2000, every = 3.4, count = 2 },
	finaleTime = 50,
	deadline = 400,
	hardLimit = 480,
	finale = { at = 0, label = "ЗАЩИТА ПЕРИМЕТРА", rate = 6.6, cap = 84, dirs = ALL, w = { EN_RUNNER = 0.74, EN_SPITTER = 0.2, EN_STALKER = 0.06 } },
	phases = {
		{ at = 0, label = "КИСЛОТНЫЙ ДОЖДЬ", rate = 2.4, cap = 32, dirs = ALL, w = { EN_RUNNER = 0.8, EN_SPITTER = 0.2 }, quiet = true },
		{ at = 90, label = "ИСТОЧНИКИ", rate = 3.6, cap = 52, dirs = ALL, w = { EN_RUNNER = 0.76, EN_SPITTER = 0.2, EN_STALKER = 0.04 }, quiet = true },
		{ at = 200, label = "ОТРАВА", rate = 4.8, cap = 66, dirs = ALL, w = { EN_RUNNER = 0.74, EN_SPITTER = 0.22, EN_STALKER = 0.04 } },
	},
	beats = {
		{ at = 50, type = "assault", count = 8, kind = "EN_SPITTER" },
		{ at = 90, type = "acid", index = 1 },
		{ at = 150, type = "assault", count = 10 },
		{ at = 180, type = "acid", index = 2 },
		{ at = 220, type = "assault", count = 10, kind = "EN_SPITTER" },
		{ at = 290, type = "assault", count = 12 },
	},
	unlocks = {},
	requires = "O02",
}

-- Early operations are short (DD-024): the same script, played faster. Scales every timing; objectives
-- measured in kills shrink with it so the pace stays the same.
local function compress(op: OpDef, k: number)
	for _, ph in op.phases do
		ph.at = math.floor(ph.at * k + 0.5)
	end
	for _, b in op.beats do
		b.at = math.floor(b.at * k + 0.5)
	end
	op.deadline = op.deadline and math.floor(op.deadline * k + 0.5)
	op.hardLimit = op.hardLimit and math.floor(op.hardLimit * k + 0.5)
	op.finaleTime = op.finaleTime and math.floor(op.finaleTime * k + 0.5)
	if op.relay then
		op.relay.need = math.floor(op.relay.need * k + 0.5)
	end
	if op.nests then
		op.nests.hp = math.floor(op.nests.hp * k + 0.5)
	end
end
compress(Ops.O02, 0.7)
compress(Ops.O03, 0.75)
Ops.O03.deadline = 420 -- nests are walked to and shot down: keep a margin over the plain ×0.75
Ops.O03.hardLimit = 420 + Ops.O03.finaleTime + 60

Ops.Order = { "O01", "O02", "O03", "O04", "O05", "O06", "CA01" }

function Ops.get(id: string?): OpDef
	return (id and (Ops :: any)[id]) or Ops.O01
end

return Ops
