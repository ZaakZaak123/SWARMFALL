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
	enemyHpMult: number?,
	siege: number?, -- siege level (generated op)
	target: any?, -- raid target snapshot (generated op)
	mode: string?, -- "siege" | "raid" for generated ops
	anomaly: any?, -- Meta anomaly applied to this run
	xpTable: { number }?, -- fixed XP per level; past its end the level is capped (O01: three cards)
}

local ALL = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
-- O01 levels: cards near 0:12, 0:35 and 1:05 (TUNABLE against tests/ops_run O01).
local XP_O01 = { 4, 32, 80 }

-- SPOREFALL hunts (DD-032): one new idea per hunt.
--   O01 ВЫСАДКА       shoot, level up, pick cards; one big enemy at the end. No objective to guard.
--   O02 ОКРУЖЕНИЕ     the Gravihammer (S01) is learned when the swarm closes a ring; the Leaper.
--   O03 ПОЮЩИЙ ПИЛОН  guard the extractor (БУР) and charge a spore pylon; the Spitter.
--   O04 ГНЁЗДА        destroy two of three nests; the Bulwark.
--   O05 МАТЬ РОЯ      the Broodmother.
--   O06 КРОВАВАЯ НОЧЬ the crater after dark, power nodes, the Bomber.
--   O07 ПОЖИРАТЕЛЬ    chapter finale.
-- Ids are profile keys; their meaning shifted in the reboot (old O02..O06 became O03..O07).

-- O01 «ГЕНЕРАТОР» (was «ВЫСАДКА») — the first ninety seconds of the game (DD-051): a sortie for the
-- generator the shelter needs (DD-057). One enemy type, one rule (stay alive),
-- exactly three cards (the first is the guided «Расщепление»), one big enemy (the Alpha, ~0:55) and a
-- short final swarm. Winning it opens the outpost: the first turret is bought with this hunt's loot.
Ops.O01 = {
	id = "O01",
	index = 1,
	code = "O01",
	name = "ГЕНЕРАТОР",
	map = "MAP_REACTOR_YARD",
	brief = "В руинах станции — генератор для убежища. Продержись и убей Альфу, что гнездится на нём.",
	goal = "Продержись",
	objective = "carrier",
	playerDamageMult = 0.6,
	eliteName = "АЛЬФА",
	eliteGoal = "Убей Альфу",
	eliteHpMult = 0.3, -- first big enemy of the game: a 10–20 s fight, not a sponge
	runEvolution = false,
	finaleTime = 12,
	deadline = 200,
	hardLimit = 240,
	xpTable = XP_O01,
	finale = { at = 0, label = "ПОСЛЕДНЯЯ ВОЛНА", rate = 9.0, cap = 70, dirs = ALL, w = { EN_RUNNER = 1 } },
	phases = {
		{ at = 0, label = "КОНТАКТ", rate = 3.0, cap = 26, dirs = { "N", "NE", "NW" }, w = { EN_RUNNER = 1 }, quiet = true },
		{ at = 16, label = "НАРАСТАНИЕ", rate = 4.4, cap = 44, dirs = { "N", "E", "NE", "W", "NW" }, w = { EN_RUNNER = 1 } },
		{ at = 34, label = "СО ВСЕХ СТОРОН", rate = 5.4, cap = 60, dirs = ALL, w = { EN_RUNNER = 1 } },
		{ at = 52, label = "АЛЬФА", rate = 2.6, cap = 36, dirs = ALL, w = { EN_RUNNER = 1 }, quiet = true },
	},
	beats = {
		{ at = 55, type = "elite" },
	},
	unlocks = { "O02" },
}

-- O02 «ОКРУЖЕНИЕ» — the old first operation's best moment, now its own hunt: the swarm closes a ring and
-- the Gravihammer is learned on the spot. Leapers debut. No objective to guard yet.
Ops.O02 = {
	id = "O02",
	index = 2,
	code = "O02",
	name = "ОКРУЖЕНИЕ",
	map = "MAP_REACTOR_YARD",
	brief = "Рой учится окружать. Пробей кольцо Гравимолотом и убей Альфу.",
	goal = "Продержись",
	objective = "carrier",
	playerDamageMult = 0.75,
	eliteName = "АЛЬФА",
	eliteGoal = "Убей Альфу",
	eliteHpMult = 0.6,
	runEvolution = false,
	s01Event = true, -- the ring teaches S01 to profiles that do not have it yet
	finaleTime = 25,
	deadline = 330,
	hardLimit = 400,
	finale = { at = 0, label = "ПОСЛЕДНЯЯ ВОЛНА", rate = 9.0, cap = 86, dirs = ALL, w = { EN_RUNNER = 0.88, EN_STALKER = 0.12 } },
	phases = {
		{ at = 0, label = "КОНТАКТ", rate = 2.8, cap = 28, dirs = { "N", "E", "W" }, w = { EN_RUNNER = 1 }, quiet = true },
		{ at = 30, label = "ПРЫГУНЫ", rate = 3.8, cap = 40, dirs = { "N", "NE", "NW", "E", "W" }, w = { EN_RUNNER = 0.9, EN_STALKER = 0.1 } },
		{ at = 70, label = "КОЛЬЦО", rate = 4.6, cap = 56, dirs = ALL, w = { EN_RUNNER = 0.9, EN_STALKER = 0.1 } },
		{ at = 120, label = "ДАВЛЕНИЕ", rate = 6.0, cap = 72, dirs = ALL, w = { EN_RUNNER = 0.86, EN_STALKER = 0.14 } },
		{ at = 168, label = "АЛЬФА", rate = 3.0, cap = 44, dirs = ALL, w = { EN_RUNNER = 0.88, EN_STALKER = 0.12 }, quiet = true },
	},
	beats = {
		{ at = 30, type = "banner", title = "ПРЫГУН", sub = "Замирает перед прыжком — уйди в сторону", kind = "EN_STALKER" },
		{ at = 74, type = "ring", count = 26 },
		{ at = 170, type = "elite" },
	},
	unlocks = { "O03" },
	requires = "O01",
}

-- O03 «ПОЮЩИЙ ПИЛОН» (was O02, D02 §5). First hunt with something to guard: the extractor. A spore pylon
-- charges from kills inside its zone; Leaper groups hunt it; if it falls the backup takes over.
Ops.O03 = {
	id = "O03",
	index = 3,
	code = "O03",
	name = "ПОЮЩИЙ ПИЛОН",
	map = "MAP_REACTOR_YARD",
	brief = "Рой идёт на наш бур. Убивай врагов у пилона, чтобы зарядить его, и не дай разрушить бур.",
	goal = "Защити бур",
	objective = "relay",
	reactor = { hp = 2100, name = "БУР" },
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
	unlocks = { "O04", "CA01" },
	requires = "O02",
}

-- O04 «ГНЁЗДА» (was O03, D02 §6). Three nests open at ~2:00; any two win (3/3 = optional +20 bonus).
-- Introduces the Bulwark, which escorts a nest.
Ops.O04 = {
	id = "O04",
	index = 4,
	code = "O04",
	name = "ГНЁЗДА",
	map = "MAP_REACTOR_YARD",
	brief = "Рой пустил корни в воронке. Уничтожь любые два гнезда из трёх и сбереги бур.",
	goal = "Защити бур",
	objective = "nests",
	reactor = { hp = 2000, name = "БУР" },
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
	unlocks = { "O05" },
	requires = "O03",
}

-- O05 «МАТЬ РОЯ» (was O04, D02 §7). Two elites, the peak swarm, optional nests, then the Broodmother. Her
-- death wins at once. Reactor defended throughout.
do
	local yard = Maps.get("MAP_REACTOR_YARD")
	Ops.O05 = {
		id = "O05",
		index = 5,
		code = "O05",
		name = "МАТЬ РОЯ",
		map = "MAP_REACTOR_YARD",
		brief = "Королева роя выходит из останков гиганта. Переживи элиту и пиковый рой, затем убей Мать роя.",
		goal = "Защити бур и убей Мать роя",
		objective = "boss",
		spawnMult = 0.85,
		bossHpMult = 0.85,
		reactor = { hp = 1600, name = "БУР" },
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
		unlocks = { "O06" },
		requires = "O04",
	}
end

-- O06 «КРОВАВАЯ НОЧЬ» (was O05, D02 §8). The crater after dark, the Bomber, two power nodes (shootable by any weapon;
-- bomber blasts help but are optional). The energy heart is the defended object.
Ops.O06 = {
	id = "O06",
	index = 6,
	code = "O06",
	name = "КРОВАВАЯ НОЧЬ",
	map = "MAP_HIVE_DEPTHS",
	brief = "Ночью воронка краснеет. Разрушь два питающих узла роя и сбереги бур. Взрывуны рвутся рядом.",
	goal = "Защити бур",
	objective = "nodes",
	reactor = { hp = 1500, name = "БУР" },
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
	unlocks = { "O07" },
	requires = "O05",
}

-- O07 «ПОЖИРАТЕЛЬ» (was O06, D02 §9). Chapter finale: two elites, bombers, optional nests, the Devourer. His
-- death wins at once while the heart and the hero live.
do
	local depths = Maps.get("MAP_HIVE_DEPTHS")
	Ops.O07 = {
		id = "O07",
		index = 7,
		code = "O07",
		name = "ПОЖИРАТЕЛЬ",
		map = "MAP_HIVE_DEPTHS",
		brief = "Финал главы. Из-под воронки поднимается Пожиратель. Сбереги бур и убей его.",
		goal = "Защити бур и убей Пожирателя",
		objective = "boss",
		spawnMult = 0.85,
		bossHpMult = 0.75, -- the Devourer burrows; keep a viable boss window (D02 §9)
		reactor = { hp = 2400, name = "БУР" },
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
		requires = "O06",
		chapterEnd = true,
	}
end

-- C-A01 «КИСЛОТНЫЙ ФРОНТ» — D02 §10. Optional contract after O02: Spitter-heavy yard, two acid sources
-- that keep seeding acid until destroyed by direct fire. Not a story key.
Ops.CA01 = {
	id = "CA01",
	index = 8,
	code = "C-A01",
	name = "КИСЛОТНЫЙ ДОЖДЬ",
	map = "MAP_REACTOR_YARD",
	brief = "Контракт: плевуны травят воронку. Уничтожь два кислотных источника и сбереги бур.",
	goal = "Защити бур",
	objective = "acid",
	reactor = { hp = 1500, name = "БУР" },
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
	requires = "O03",
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
compress(Ops.O03, 0.7)
compress(Ops.O04, 0.75)
Ops.O04.deadline = 420 -- nests are walked to and shot down: keep a margin over the plain ×0.75
Ops.O04.hardLimit = 420 + Ops.O04.finaleTime + 60

Ops.Order = { "O01", "O02", "O03", "O04", "O05", "O06", "O07", "CA01" }

-- Siege ladder (DD-038): defend the extractor of your own outpost through five waves. Endless levels;
-- each level is tougher. Generated, not stored: id "SIEGE", the level travels in the op.
function Ops.makeSiege(level: number): OpDef
	level = math.max(1, math.floor(level))
	local hpMult = 1 + 0.14 * (level - 1)
	local rateMult = 1 + 0.07 * (level - 1)
	local phases = {}
	local beats = {}
	local waveLen, calm = 42, 13
	for k = 1, 5 do
		local at = 6 + (k - 1) * (waveLen + calm)
		local w = { EN_RUNNER = 1 }
		if k >= 2 or level >= 3 then
			w.EN_STALKER = 0.12
		end
		if k >= 3 or level >= 4 then
			w.EN_SPITTER = 0.1
		end
		if k >= 4 or level >= 6 then
			w.EN_BOMBER = 0.1
			w.EN_BULWARK = 0.05
		end
		table.insert(phases, {
			at = at,
			label = "ВОЛНА " .. k .. "/5",
			rate = (2.4 + 0.55 * k) * rateMult,
			cap = math.floor((28 + 9 * k) * math.min(1.6, rateMult)),
			dirs = if k <= 2 then { "N", "NE", "NW", "E", "W" } else ALL,
			w = w,
		})
		table.insert(phases, { at = at + waveLen, label = "ПЕРЕДЫШКА", rate = 0.5, cap = 8, dirs = { "N" }, w = { EN_RUNNER = 1 } })
		table.insert(beats, { at = at + 5, type = "assault", count = 5 + 2 * k + math.floor(level / 2) })
		if k >= 2 then
			table.insert(beats, { at = at + 24, type = "assault", count = 4 + 2 * k + math.floor(level / 2), kind = if k >= 4 then "EN_STALKER" else nil })
		end
	end
	local last = 6 + 4 * (waveLen + calm)
	table.insert(beats, { at = last + 10, type = "elite" })
	table.sort(beats, function(a, b)
		return a.at < b.at
	end)
	return {
		id = "SIEGE",
		index = 0,
		code = "ОБОРОНА",
		name = "ОБОРОНА БУРА · УРОВЕНЬ " .. level,
		map = "MAP_REACTOR_YARD",
		brief = "Пять волн идут на твой бур. Турели из мастерской стреляют вместе с тобой.",
		goal = "Защити бур",
		objective = "carrier",
		reactor = { hp = math.floor(1700 * (1 + 0.05 * (level - 1))), name = "БУР" },
		eliteName = "ВОЖАК НАТИСКА",
		eliteGoal = "Убей вожака натиска",
		eliteHpMult = 0.6 * hpMult,
		enemyHpMult = hpMult,
		runEvolution = false,
		finaleTime = 20,
		deadline = last + 90,
		hardLimit = last + 140,
		finale = { at = 0, label = "ДОБИТЬ", rate = 6 * rateMult, cap = 70, dirs = ALL, w = { EN_RUNNER = 0.85, EN_STALKER = 0.15 } },
		phases = phases,
		beats = beats,
		unlocks = {},
		siege = level,
		mode = "siege",
	}
end

-- «ПЕРВЫЙ НАТИСК» (DD-052): right after the first turret is built the swarm comes for the drill — one
-- short wave from the north, straight into the new turret's field of fire. About 40 seconds, cannot be
-- replayed (Profile `tut.strike`), pays a little and shows what the outpost is for.
function Ops.makeFirstStrike(): OpDef
	return {
		id = "STRIKE",
		index = 0,
		code = "ОБОРОНА",
		name = "ПЕРВЫЙ НАТИСК",
		map = "MAP_REACTOR_YARD",
		brief = "Рой услышал бур. Держись у турели — она стреляет вместе с тобой.",
		goal = "Защити бур",
		objective = "carrier",
		reactor = { hp = 4000, name = "БУР" }, -- a lesson, not a test: the drill holds even if the player hesitates
		playerDamageMult = 0.4,
		eliteName = "ВОЖАК",
		eliteGoal = "Убей вожака",
		eliteHpMult = 0.18,
		runEvolution = false,
		finaleTime = 6,
		deadline = 120,
		hardLimit = 150,
		xpTable = {},
		finale = { at = 0, label = "ДОБИТЬ", rate = 5, cap = 40, dirs = { "N", "NE", "NW" }, w = { EN_RUNNER = 1 } },
		phases = {
			{ at = 2, label = "РОЙ ИДЁТ НА БУР", rate = 3.4, cap = 34, dirs = { "N", "NE", "NW" }, w = { EN_RUNNER = 1 } },
		},
		beats = {
			{ at = 6, type = "assault", count = 6 },
			{ at = 13, type = "assault", count = 8 },
			{ at = 19, type = "elite" },
		},
		unlocks = {},
		siege = 0,
		mode = "siege",
	}
end

-- Raid (DD-039): another player's outpost — their turrets shoot you, their brood comes in waves, the
-- extractor core is the objective. target = snapshot { uid, name, rating, slots, brood }.
function Ops.makeRaid(target): OpDef
	local beats = { { at = 0.2, type = "outpost" } }
	for _, at in { 14, 42, 72, 102, 132, 160, 186, 212 } do
		table.insert(beats, { at = at, type = "brood" })
	end
	return {
		id = "RAID",
		index = 0,
		code = "ВТОРЖЕНИЕ",
		name = target.name or "ЧУЖОЙ АВАНПОСТ",
		map = "MAP_REACTOR_YARD",
		brief = "Пробейся через турели и рой хозяина и разрушь его бур.",
		goal = "Разрушь вражеский бур",
		objective = "core",
		runEvolution = false,
		hardLimit = 240,
		phases = {
			{ at = 0, label = "ВТОРЖЕНИЕ", rate = 1.3, cap = 16, dirs = ALL, w = { EN_RUNNER = 0.9, EN_STALKER = 0.1 }, quiet = true },
			{ at = 90, label = "ОБОРОНА КРЕПНЕТ", rate = 2.0, cap = 24, dirs = ALL, w = { EN_RUNNER = 0.85, EN_STALKER = 0.15 } },
			{ at = 170, label = "ПОСЛЕДНИЙ РУБЕЖ", rate = 3.0, cap = 34, dirs = ALL, w = { EN_RUNNER = 0.8, EN_STALKER = 0.12, EN_SPITTER = 0.08 } },
		},
		beats = beats,
		unlocks = {},
		target = target,
		mode = "raid",
	}
end

function Ops.get(id: string?): OpDef
	return (id and (Ops :: any)[id]) or Ops.O01
end

return Ops
