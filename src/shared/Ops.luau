--!strict
-- Operations ("ОПЕРАЦИИ"): the scenario layer on top of a map. A map is geometry; an operation is what
-- happens on it — spawn phases, scripted beats, the objective and what the first win unlocks.
-- Canon: design/handoff/02_GAME_SPECS/SWARMFALL_D02_OPERATIONS_SPEC_v0.3.md. Numbers are TUNABLE;
-- tests/ops_run.luau checks that every operation is winnable by a defending bot with the start rifle.

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
	winOnElite: boolean?, -- the elite's death ends the run: the leaderless swarm scatters (O01, first defence)
	winOnObjective: boolean?, -- the objective done ends the run at once (O03: the charged pylon's song)
	winBanner: { string }?, -- { title, sub } of that win (O04)
	winFx: number?, -- BOSS event action of that win: 7 the pylon's cyan song (default), 6 a golden blast
	homeText: string?, -- what the first win brings home, for the goal line before the sortie (O04)
	guidedCards: { string }?, -- first offers in order, only that card can be taken (O01 for a newcomer)
}

local ALL = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
-- O01 levels: three cards in the first ~35 s, before the Alpha (TUNABLE against tests/ops_run O01).
local XP_O01 = { 4, 17, 26 }
-- O02: four cards, the last before the Alpha (~0:58).
local XP_O02 = { 6, 20, 34, 50 }
-- O05: six cards — the boss at ~0:30 needs a build, not a starter rifle.
local XP_O05 = { 4, 10, 16, 24, 34, 46 }

-- SPOREFALL hunts (DD-032): one new idea per hunt.
--   O01 ВЫСАДКА       shoot, level up, pick cards; one big enemy at the end. No objective to guard.
--   O02 ОКРУЖЕНИЕ     the Gravihammer (S01) is learned when the swarm closes a ring; the Leaper.
--   O03 ПОЮЩИЙ ПИЛОН  guard the extractor (БУР) and charge a spore pylon; the Spitter.
--   O04 ГНЁЗДА        destroy two of three nests; the Bulwark.
--   O05 МАТЬ РОЯ      the Broodmother.
--   O06 КРОВАВАЯ НОЧЬ the crater after dark, power nodes, the Bomber.
--   O07 ПОЖИРАТЕЛЬ    chapter finale.
-- Ids are profile keys; their meaning shifted in the reboot (old O02..O06 became O03..O07).

-- O01 «ГЕНЕРАТОР» — the first minute of the game (DD-075): a sortie for the generator the shelter needs.
-- One enemy type, one rule (stay alive), three guided cards in a row («Расщепление», «Детонатор»,
-- «Барьер»: one per style, each visible at once), the Alpha at ~0:38 and the run ends with her death —
-- the leaderless swarm scatters. Winning it restores the generator and the workshop; the loot buys the
-- first turret for the drill.
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
	eliteHpMult = 0.18, -- first big enemy of the game: a ~15 s fight, not a sponge
	runEvolution = false,
	winOnElite = true,
	finaleTime = 2.5, -- the victory moment: the swarm scatters, then the results
	deadline = 150,
	hardLimit = 200,
	xpTable = XP_O01,
	guidedCards = { "UPG_MULTISHOT", "UPG_DETONATE", "UPG_SHIELD" },
	finale = { at = 0, label = "РОЙ РАССЫПАЛСЯ", rate = 0, cap = 0, dirs = ALL, w = { EN_RUNNER = 1 } },
	phases = {
		{ at = 0, label = "КОНТАКТ", rate = 3.6, cap = 30, dirs = { "N", "NE", "NW" }, w = { EN_RUNNER = 1 }, quiet = true },
		{ at = 12, label = "НАРАСТАНИЕ", rate = 5.0, cap = 46, dirs = { "N", "E", "NE", "W", "NW" }, w = { EN_RUNNER = 1 } },
		{ at = 24, label = "СО ВСЕХ СТОРОН", rate = 6.0, cap = 60, dirs = ALL, w = { EN_RUNNER = 1 } },
		{ at = 36, label = "АЛЬФА", rate = 2.6, cap = 36, dirs = ALL, w = { EN_RUNNER = 1 }, quiet = true },
	},
	beats = {
		{ at = 38, type = "elite" },
	},
	unlocks = { "O02" },
}

-- O02 «РАДИОМАЯК» (was «ОКРУЖЕНИЕ», DD-076) — the second sortie, ~1:20: the antenna the shelter's radio
-- needs fell into the funnel. One new idea: the swarm closes a ring (~0:26) and the Gravihammer is learned
-- on the spot. Leapers debut with a warning. Four cards, free choice. The Alpha's death ends it; the win
-- restores the radio (the drill defence ladder) and the loot buys the «Разрядник».
Ops.O02 = {
	id = "O02",
	index = 2,
	code = "O02",
	name = "РАДИОМАЯК",
	map = "MAP_REACTOR_YARD",
	brief = "Антенна для радио упала в воронку. Рой сомкнёт кольцо — пробей его Гравимолотом и убей Альфу.",
	goal = "Продержись",
	objective = "carrier",
	playerDamageMult = 0.75,
	eliteName = "АЛЬФА",
	eliteGoal = "Убей Альфу",
	eliteHpMult = 0.3,
	runEvolution = false,
	s01Event = true, -- the ring teaches S01 to profiles that do not have it yet
	winOnElite = true,
	finaleTime = 2.5,
	deadline = 200,
	hardLimit = 260,
	xpTable = XP_O02,
	finale = { at = 0, label = "РОЙ РАССЫПАЛСЯ", rate = 0, cap = 0, dirs = ALL, w = { EN_RUNNER = 1 } },
	phases = {
		{ at = 0, label = "КОНТАКТ", rate = 3.4, cap = 30, dirs = { "N", "E", "W" }, w = { EN_RUNNER = 1 }, quiet = true },
		{ at = 10, label = "ПРЫГУНЫ", rate = 4.2, cap = 40, dirs = { "N", "NE", "NW", "E", "W" }, w = { EN_RUNNER = 0.88, EN_STALKER = 0.12 } },
		{ at = 24, label = "КОЛЬЦО", rate = 4.6, cap = 52, dirs = ALL, w = { EN_RUNNER = 0.9, EN_STALKER = 0.1 }, quiet = true },
		{ at = 40, label = "ДАВЛЕНИЕ", rate = 6.0, cap = 66, dirs = ALL, w = { EN_RUNNER = 0.86, EN_STALKER = 0.14 } },
		{ at = 56, label = "АЛЬФА", rate = 3.0, cap = 44, dirs = ALL, w = { EN_RUNNER = 0.88, EN_STALKER = 0.12 }, quiet = true },
	},
	beats = {
		{ at = 10, type = "banner", title = "ПРЫГУН", sub = "Замирает перед прыжком — уйди в сторону", kind = "EN_STALKER" },
		{ at = 26, type = "ring", count = 26 },
		{ at = 58, type = "elite" },
	},
	unlocks = { "O03" },
	requires = "O01",
}

-- O03 «ОБРАЗЕЦ» (was «ПОЮЩИЙ ПИЛОН», DD-077) — the third sortie, ~1:30: the shelter's lab needs a live
-- sample of the swarm. One idea: the spore pylon on the funnel's diagonal charges from kills inside its
-- circle; charged, its song stuns the whole swarm and a Spitter is taken alive — that is the win. Spitters
-- debut (acid from afar), Leaper groups go for the pylon; if it falls, the backup takes the charge over.
-- Nothing else to guard. The win restores the lab; the loot buys the «Криополе».
Ops.O03 = {
	id = "O03",
	index = 3,
	code = "O03",
	name = "ОБРАЗЕЦ",
	map = "MAP_REACTOR_YARD",
	brief = "Лаборатории нужен живой образец роя. Заряди споровый пилон убийствами в его круге — его песня оглушит рой.",
	goal = "Заряди пилон",
	objective = "relay",
	playerDamageMult = 0.85,
	runEvolution = false,
	relay = { need = 190, radius = 30, hp = 900, primary = 1, backup = 2 },
	winOnObjective = true,
	finaleTime = 2.5,
	deadline = 200,
	hardLimit = 260,
	xpTable = XP_O02,
	finale = { at = 0, label = "ПИЛОН ЗАПЕЛ", rate = 0, cap = 0, dirs = ALL, w = { EN_RUNNER = 1 } },
	phases = {
		{ at = 0, label = "КОНТАКТ", rate = 3.4, cap = 30, dirs = { "N", "E", "W" }, w = { EN_RUNNER = 0.94, EN_STALKER = 0.06 }, quiet = true },
		{ at = 20, label = "ПЛЕВУНЫ", rate = 4.4, cap = 44, dirs = { "N", "NE", "NW", "E", "W" }, w = { EN_RUNNER = 0.84, EN_STALKER = 0.08, EN_SPITTER = 0.08 }, quiet = true },
		{ at = 45, label = "ДАВЛЕНИЕ", rate = 5.6, cap = 60, dirs = ALL, w = { EN_RUNNER = 0.82, EN_STALKER = 0.1, EN_SPITTER = 0.08 } },
		{ at = 70, label = "КЛЕЩИ", rate = 6.4, cap = 70, dirs = ALL, w = { EN_RUNNER = 0.8, EN_STALKER = 0.12, EN_SPITTER = 0.08 } },
	},
	beats = {
		{ at = 4, type = "relay" },
		{ at = 20, type = "banner", title = "ПЛЕВУН", sub = "Плюётся кислотой издалека — уходи из луж", kind = "EN_SPITTER" },
		{ at = 32, type = "assault", count = 5, kind = "EN_STALKER", target = "relay" },
		{ at = 55, type = "assault", count = 6, kind = "EN_STALKER", target = "relay" },
		{ at = 78, type = "assault", count = 7, kind = "EN_STALKER", target = "relay" },
	},
	unlocks = { "O04", "CA01" },
	requires = "O02",
}

-- O04 «СЕРДЦЕ ГНЕЗДА» (was «ГНЁЗДА», DD-078) — the fourth sortie, ~1:30: the swarm has rooted in the
-- funnel. One idea: three nests open at once; burn any two (a Bulwark guards one: hit it from the side or
-- the back). The second nest down is the win — the swarm loses its roots and a nest's heart is taken home
-- to the lab: the own swarm breeds from it and raids on other drills open. Nothing else to guard.
Ops.O04 = {
	id = "O04",
	index = 4,
	code = "O04",
	name = "СЕРДЦЕ ГНЕЗДА",
	map = "MAP_REACTOR_YARD",
	brief = "Рой пустил корни в воронке. Выжги любые два гнезда из трёх — и забери сердце гнезда.",
	goal = "Выжги 2 гнезда из 3",
	objective = "nests",
	playerDamageMult = 0.8,
	runEvolution = false,
	nests = { need = 2, hp = 850 },
	winOnObjective = true,
	winBanner = { "ГНЁЗДА ВЫЖЖЕНЫ", "Рой лишился корней — сердце гнезда твоё" },
	winFx = 6,
	homeText = "Вернёшься — в лаборатории заведётся свой рой, и откроются вторжения на чужие буры.",
	finaleTime = 2.5,
	deadline = 210,
	hardLimit = 270,
	xpTable = XP_O02,
	finale = { at = 0, label = "КОРНИ ВЫЖЖЕНЫ", rate = 0, cap = 0, dirs = ALL, w = { EN_RUNNER = 1 } },
	phases = {
		{ at = 0, label = "КОНТАКТ", rate = 3.4, cap = 32, dirs = { "N", "E", "W", "S" }, w = { EN_RUNNER = 0.86, EN_SPITTER = 0.07, EN_STALKER = 0.07 }, quiet = true },
		{ at = 25, label = "НАРАСТАНИЕ", rate = 4.6, cap = 48, dirs = ALL, w = { EN_RUNNER = 0.82, EN_SPITTER = 0.08, EN_STALKER = 0.08, EN_BULWARK = 0.02 } },
		{ at = 50, label = "ДАВЛЕНИЕ", rate = 5.6, cap = 62, dirs = ALL, w = { EN_RUNNER = 0.8, EN_SPITTER = 0.08, EN_STALKER = 0.09, EN_BULWARK = 0.03 } },
		{ at = 75, label = "КЛЕЩИ", rate = 5.8, cap = 66, dirs = ALL, w = { EN_RUNNER = 0.8, EN_SPITTER = 0.08, EN_STALKER = 0.09, EN_BULWARK = 0.03 } },
	},
	beats = {
		{ at = 5, type = "nests" },
		{ at = 14, type = "guard", index = 1 },
		{ at = 15, type = "banner", title = "БРОНЕНОСЕЦ", sub = "Броня спереди — заходи сбоку или со спины", kind = "EN_BULWARK" },
		{ at = 45, type = "guard", index = 2 },
	},
	unlocks = { "O05" },
	requires = "O03",
}

-- O05 «МАТЬ РОЯ» (DD-079) — the fifth sortie and the chapter's first boss, ~2:00. One idea: the queen comes
-- out of the titan's remains at ~0:30 and goes for the drill; her death wins at once (the rest of the swarm
-- dies with her). A short build-up with every kind met so far, four cards, the drill as the stake. The win
-- puts her golden statue on the shelter's trophy row and opens the Рельсотрон blueprint.
Ops.O05 = {
	id = "O05",
	index = 5,
	code = "O05",
	name = "МАТЬ РОЯ",
	map = "MAP_REACTOR_YARD",
	brief = "Королева роя выходит из останков гиганта и идёт на бур. Убей Мать роя.",
	goal = "Защити бур",
	objective = "boss",
	bossHpMult = 0.5,
	playerDamageMult = 0.6,
	reactor = { hp = 2600, name = "БУР" },
	runEvolution = false,
	deadline = 240,
	hardLimit = 300,
	xpTable = XP_O05,
	homeText = "Вернёшься с трофеем — и в гнезде найдётся чертёж «Рельсотрона».",
	phases = {
		{ at = 0, label = "КОНТАКТ", rate = 3.4, cap = 32, dirs = { "N", "E", "W" }, w = { EN_RUNNER = 0.84, EN_STALKER = 0.08, EN_SPITTER = 0.08 }, quiet = true },
		{ at = 14, label = "НАРАСТАНИЕ", rate = 4.6, cap = 48, dirs = ALL, w = { EN_RUNNER = 0.8, EN_STALKER = 0.09, EN_SPITTER = 0.08, EN_BULWARK = 0.03 } },
		{ at = 28, label = "МАТЬ РОЯ", rate = 2.8, cap = 36, dirs = ALL, w = { EN_RUNNER = 0.9, EN_STALKER = 0.1 }, quiet = true },
	},
	beats = {
		{ at = 18, type = "assault", count = 8 },
		{ at = 30, type = "boss" },
		{ at = 110, type = "enrage" },
	},
	unlocks = { "O06" },
	requires = "O04",
}

-- O06 «КРОВАВАЯ НОЧЬ» (DD-080) — the sixth sortie, ~1:30–2:00, the funnel after dark. One idea: two power
-- nodes feed the swarm (both open in the first 25 s, any weapon hurts them) and Bombers — new — blow up next
-- to whatever is near, nodes included. The second node down is the win: the hive goes dark and the flame
-- heart (the Адская мельница component) rides home to the armory. Nothing else to guard.
Ops.O06 = {
	id = "O06",
	index = 6,
	code = "O06",
	name = "КРОВАВАЯ НОЧЬ",
	map = "MAP_HIVE_DEPTHS",
	brief = "Ночью воронка краснеет: два питающих узла кормят рой. Разрушь оба — взрывуны рвутся рядом и помогают.",
	goal = "Разрушь питающие узлы",
	objective = "nodes",
	playerDamageMult = 0.7,
	runEvolution = false,
	nodes = { hp = 1600, count = 2 },
	winOnObjective = true,
	winBanner = { "УЗЛЫ РАЗРУШЕНЫ", "Улей обесточен — сердце пламени твоё" },
	winFx = 6,
	homeText = "Вернёшься с сердцем пламени — «Вулкан» сможет стать «Адской мельницей».",
	finaleTime = 2.5,
	deadline = 240,
	hardLimit = 300,
	xpTable = XP_O05,
	finale = { at = 0, label = "УЛЕЙ ОБЕСТОЧЕН", rate = 0, cap = 0, dirs = ALL, w = { EN_RUNNER = 1 } },
	phases = {
		{ at = 0, label = "СПУСК", rate = 3.4, cap = 32, dirs = { "N", "NE", "NW" }, w = { EN_RUNNER = 0.86, EN_BOMBER = 0.14 }, quiet = true },
		{ at = 20, label = "ШЁПОТ УЛЬЯ", rate = 4.6, cap = 48, dirs = { "N", "E", "W", "NE", "NW" }, w = { EN_RUNNER = 0.74, EN_BOMBER = 0.16, EN_STALKER = 0.1 } },
		{ at = 45, label = "ДЫМЯЩИЕ ТОННЕЛИ", rate = 5.6, cap = 62, dirs = ALL, w = { EN_RUNNER = 0.68, EN_BOMBER = 0.18, EN_STALKER = 0.1, EN_SPITTER = 0.04 } },
		{ at = 70, label = "ЦЕПНАЯ РЕАКЦИЯ", rate = 6.2, cap = 70, dirs = ALL, w = { EN_RUNNER = 0.64, EN_BOMBER = 0.22, EN_STALKER = 0.1, EN_SPITTER = 0.04 } },
	},
	beats = {
		{ at = 5, type = "nodes", index = 1 },
		{ at = 9, type = "banner", title = "ВЗРЫВУН", sub = "Взрывается рядом с тобой — и задевает рой и узлы", kind = "EN_BOMBER" },
		{ at = 25, type = "nodes", index = 2 },
	},
	unlocks = { "O07" },
	requires = "O05",
}

-- O07 «ПОЖИРАТЕЛЬ» (DD-081) — the chapter finale, ~2:30, at night. One idea: the Devourer rises from under
-- the funnel at ~0:35 and goes for the drill; it burrows and resurfaces, and its death wins at once. A short
-- build-up with every kind of the chapter (Bombers included), six cards before it, the drill as the stake.
-- The win ends the chapter: the Devourer's statue turns gold and the void heart (Копьё пустоты) rides home.
Ops.O07 = {
	id = "O07",
	index = 7,
	code = "O07",
	name = "ПОЖИРАТЕЛЬ",
	map = "MAP_HIVE_DEPTHS",
	brief = "Финал главы. Из-под воронки поднимается Пожиратель и идёт на бур. Убей его.",
	goal = "Защити бур",
	objective = "boss",
	bossHpMult = 0.38, -- it burrows: a short boss window, not a sponge
	playerDamageMult = 0.6,
	reactor = { hp = 3000, name = "БУР" },
	runEvolution = false,
	deadline = 300,
	hardLimit = 360,
	xpTable = XP_O05,
	homeText = "Его смерть закроет главу — и сердце пустоты сделает из «Рельсотрона» «Копьё пустоты».",
	phases = {
		{ at = 0, label = "СПУСК", rate = 3.6, cap = 34, dirs = { "N", "E", "W" }, w = { EN_RUNNER = 0.78, EN_BOMBER = 0.08, EN_STALKER = 0.08, EN_SPITTER = 0.06 }, quiet = true },
		{ at = 16, label = "ДРОЖЬ ЗЕМЛИ", rate = 4.8, cap = 50, dirs = ALL, w = { EN_RUNNER = 0.74, EN_BOMBER = 0.1, EN_STALKER = 0.08, EN_SPITTER = 0.05, EN_BULWARK = 0.03 } },
		{ at = 32, label = "ПОЖИРАТЕЛЬ", rate = 2.8, cap = 36, dirs = ALL, w = { EN_RUNNER = 0.86, EN_BOMBER = 0.14 }, quiet = true },
	},
	beats = {
		{ at = 20, type = "assault", count = 8 },
		{ at = 35, type = "boss" },
		{ at = 130, type = "enrage" },
	},
	unlocks = {},
	requires = "O06",
	chapterEnd = true,
}

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

-- «ПЕРВЫЙ НАТИСК» (DD-052, DD-075): the first defence of the drill with the first turret — about a minute.
-- Three strike groups from the north, straight into the new turret's field of fire, then the leader; his
-- death ends it. Cannot be replayed (Profile `tut.strike`), pays a little and shows what the turret is for.
function Ops.makeFirstStrike(): OpDef
	return {
		id = "STRIKE",
		index = 0,
		code = "ОБОРОНА",
		name = "ПЕРВЫЙ НАТИСК",
		map = "MAP_REACTOR_YARD",
		brief = "Рой вернулся к буру. Держись у турели — она стреляет вместе с тобой.",
		goal = "Защити бур",
		objective = "carrier",
		reactor = { hp = 4000, name = "БУР" }, -- a lesson, not a test: the drill holds even if the player hesitates
		playerDamageMult = 0.4,
		eliteName = "ВОЖАК",
		eliteGoal = "Убей вожака",
		eliteHpMult = 0.12,
		runEvolution = false,
		winOnElite = true,
		finaleTime = 2.5,
		deadline = 140,
		hardLimit = 170,
		xpTable = { 5, 16 }, -- two cards: the run is short, but a fight without a choice felt broken
		finale = { at = 0, label = "РОЙ ОТБИТ", rate = 0, cap = 0, dirs = { "N" }, w = { EN_RUNNER = 1 } },
		phases = {
			{ at = 2, label = "РОЙ ИДЁТ НА БУР", rate = 3.4, cap = 34, dirs = { "N", "NE", "NW" }, w = { EN_RUNNER = 1 } },
			{ at = 22, label = "НАТИСК КРЕПНЕТ", rate = 4.4, cap = 44, dirs = { "N", "NE", "NW", "E", "W" }, w = { EN_RUNNER = 1 } },
		},
		beats = {
			{ at = 6, type = "assault", count = 6 },
			{ at = 16, type = "assault", count = 8 },
			{ at = 26, type = "assault", count = 10 },
			{ at = 30, type = "elite" },
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
