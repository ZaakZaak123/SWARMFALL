--!strict
-- SWARMFALL content definitions (RU). Pure data shared by server sim, client UI and offline tests.
-- Every number is a tuning target, validated by tests/sim_run.luau (headless full-run bot).

local Defs = {}

Defs.Version = "SPOREFALL-1.0"

Defs.Run = {
	Countdown = 4,
	SafeSeconds = 6,
	BossAt = 420,
	EnrageAt = 480,
	HardLimit = 540,
	MaxActive = 96, -- solo cap; coop multiplies (see Director)
	MaxSlots = 6,
	MaxRank = 3,
	ChoiceTimeoutCoop = 15,
	SimStep = 1 / 20,
}

Defs.Player = {
	Health = 100,
	Speed = 18,
	Radius = 1.6,
	Grace = 0.4,
	DashDistance = 17,
	DashTime = 0.2,
	DashCooldown = 3.2,
	DashIFrames = 0.3,
	Magnet = 10,
	OverdriveDuration = 7,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
Defs.rgb = rgb

export type WeaponDef = {
	id: string,
	index: number,
	name: string,
	short: string,
	tagline: string,
	kind: string,
	damage: number,
	rate: number,
	range: number,
	magazine: number,
	reload: number,
	reloadEmpty: number?, -- full reload from an empty magazine (cell swap + bolt rack); defaults to reload
	spread: number,
	spreadMin: number?, -- accuracy bloom (degrees, full cone): first-shot cone, sustained-fire cap,
	spreadMax: number?, -- growth per shot and recovery per second while the trigger is released
	bloom: number?,
	recover: number?,
	pellets: number,
	pierce: number,
	falloff: number,
	knockback: number,
	color: Color3,
	evolution: string,
	cost: number,
	stats: { power: number, rate: number, range: number, control: number },
}

Defs.Weapons = {
	W_ARC_RIFLE = {
		id = "W_ARC_RIFLE",
		index = 1,
		name = "ДУГОВАЯ ВИНТОВКА",
		short = "ДУГА",
		tagline = "Точная и неумолимая. Превращается в грозу.",
		kind = "rifle",
		damage = 14,
		rate = 7,
		range = 82,
		magazine = 42,
		reload = 1.25,
		reloadEmpty = 1.6,
		spread = 2,
		spreadMin = 0.6,
		spreadMax = 3.4,
		bloom = 0.2,
		recover = 8,
		pellets = 1,
		pierce = 0,
		falloff = 0.72,
		knockback = 0.35,
		color = rgb(84, 238, 255),
		evolution = "EV_THUNDERLORD",
		cost = 0,
		stats = { power = 0.5, rate = 0.8, range = 0.8, control = 0.5 },
	},
	W_SCATTERGUN = {
		id = "W_SCATTERGUN",
		index = 2,
		name = "ДРОБОВИК «ВУЛКАН»",
		short = "ВУЛКАН",
		tagline = "В упор. Стена свинца. Тяжёлый корпус: −30% урона.",
		kind = "shotgun",
		guard = 0.3, -- heavy frame: incoming damage −30% while wielded (close-range weapon, DD-019)
		damage = 11,
		rate = 1.7,
		range = 44,
		magazine = 7,
		reload = 1.5,
		spread = 26,
		pellets = 8,
		pierce = 1, -- «стена свинца»: a pellet passes through the first runner (DD-019)
		falloff = 0.72,
		knockback = 2.2,
		color = rgb(255, 150, 60),
		evolution = "EV_INFERNO_GRINDER",
		cost = 650,
		stats = { power = 0.95, rate = 0.3, range = 0.35, control = 0.9 },
	},
	W_PLASMA_BEAM = {
		id = "W_PLASMA_BEAM",
		index = 3,
		name = "ЛУЧЕМЁТ «РАЗЛОМ»",
		short = "РАЗЛОМ",
		tagline = "Непрерывная плазма. Режет шеренги. Следи за нагревом.",
		kind = "beam",
		damage = 7.5,
		rate = 12,
		range = 64,
		magazine = 100,
		reload = 1.7,
		spread = 0,
		pellets = 1,
		pierce = 1,
		falloff = 0.72,
		knockback = 0,
		color = rgb(196, 110, 255),
		evolution = "EV_VOID_LANCE",
		cost = 1150,
		stats = { power = 0.65, rate = 1, range = 0.65, control = 0.6 },
	},
	W_RAILGUN = {
		id = "W_RAILGUN",
		index = 4,
		name = "РЕЛЬСОТРОН",
		short = "РЕЛЬСА",
		tagline = "Медленно. Насквозь. Один выстрел — целая колонна.",
		kind = "rail",
		damage = 66,
		rate = 1.7,
		range = 115,
		magazine = 8,
		reload = 1.8,
		spread = 0.5,
		pellets = 1,
		pierce = 5,
		falloff = 0.85,
		knockback = 1.6,
		color = rgb(255, 220, 110),
		evolution = "EV_STARBREAKER",
		cost = 1750,
		stats = { power = 1, rate = 0.15, range = 1, control = 0.55 },
	},
} :: { [string]: WeaponDef }

Defs.WeaponOrder = { "W_ARC_RIFLE", "W_SCATTERGUN", "W_PLASMA_BEAM", "W_RAILGUN" }
Defs.WeaponByIndex = {} :: { [number]: string }
for id, w in Defs.Weapons do
	Defs.WeaponByIndex[w.index] = id
end

Defs.Beam = { HeatPerSecond = 22, CoolPerSecond = 38 }

Defs.Evolutions = {
	EV_THUNDERLORD = {
		id = "EV_THUNDERLORD",
		name = "ГРОМОВЕРЖЕЦ",
		weapon = "W_ARC_RIFLE",
		keys = { "UPG_CHAIN", "UPG_RICOCHET" },
		coreName = "ЯДРО БУРИ",
		component = "CMP_STORM_CORE",
		cost = 900,
		color = rgb(140, 220, 255),
		text = "Каждое попадание бьёт молнией ещё по 3 целям. +15% скорострельность, ячейка на 60.",
		-- Single source for the server rule (Combat) and the dossier UI.
		mods = { damageAdd = 2, rateMult = 1.15, magazine = 60, forks = { 0.72, 0.48, 0.32 }, forkRadius = 22 },
	},
	EV_INFERNO_GRINDER = {
		id = "EV_INFERNO_GRINDER",
		name = "АДСКАЯ МЕЛЬНИЦА",
		weapon = "W_SCATTERGUN",
		keys = { "UPG_IGNITE", "UPG_DETONATE" },
		coreName = "ЯДРО ПЛАМЕНИ",
		component = "CMP_FLAME_HEART",
		cost = 1050,
		color = rgb(255, 110, 40),
		text = "+4 дробины, двойной поджог. Горящие враги взрываются при смерти.",
	},
	EV_VOID_LANCE = {
		id = "EV_VOID_LANCE",
		name = "КОПЬЁ ПУСТОТЫ",
		weapon = "W_PLASMA_BEAM",
		keys = { "UPG_PIERCE", "UPG_CORRODE" },
		coreName = "ЯДРО ПУСТОТЫ",
		component = "CMP_VOID_HEART",
		cost = 1200,
		color = rgb(150, 70, 255),
		text = "Пробивает всех. +40% дальность, +30% урон. Импульсы пустоты вдоль луча.",
	},
	EV_STARBREAKER = {
		id = "EV_STARBREAKER",
		name = "ЗВЕЗДОЛОМ",
		weapon = "W_RAILGUN",
		keys = { "UPG_CRIT", "UPG_DETONATE" },
		coreName = "ЗВЁЗДНОЕ ЯДРО",
		component = "CMP_LINE_BREACH",
		cost = 1450,
		color = rgb(255, 230, 120),
		text = "Пробивает всех. Каждое попадание взрывается. +20% скорострельность.",
	},
}

-- M20 alternative forms (D03 §3, DD-014): a different style with a trade-off, not more DPS. Gate: M20 with
-- the weapon + a thematic feat (a deterministic personal counter, no RNG) + one Ксенит craft. Effects use the
-- module path (virtual card ranks capped at III + stat tweaks). Never required for the campaign.
Defs.Evolutions.EV_M20_STORM = {
	id = "EV_M20_STORM",
	name = "ГРОЗА",
	weapon = "W_ARC_RIFLE",
	m20 = true,
	cost = 2400,
	color = rgb(120, 200, 255),
	text = "Сеть контроля: цепь и замедление на каждом попадании. −20% урона одной цели.",
	feat = { counter = "arcKills", need = 1500, text = "1500 убийств цепными разрядами" },
	ranks = { UPG_CHAIN = 3, UPG_FREEZE = 1 },
	mods = { damageMult = 0.8, rateMult = 1.1 },
	keys = {},
	coreName = "",
}
Defs.Evolutions.EV_M20_FIRE_RAM = {
	id = "EV_M20_FIRE_RAM",
	name = "ОГНЕННЫЙ ТАРАН",
	weapon = "W_SCATTERGUN",
	m20 = true,
	cost = 2600,
	color = rgb(255, 120, 50),
	text = "Узкий концентрированный термозалп: +40% урона и поджог, конус вдвое уже, −2 дробины.",
	feat = { counter = "burnKills", need = 800, text = "800 убийств поджогом из Вулкана" },
	ranks = { UPG_IGNITE = 3 },
	mods = { spreadMult = 0.5, damageMult = 1.4, pelletsAdd = -2 },
	keys = {},
	coreName = "",
}
Defs.Evolutions.EV_M20_VOID_PRISM = {
	id = "EV_M20_VOID_PRISM",
	name = "ПРИЗМА ПУСТОТЫ",
	weapon = "W_PLASMA_BEAM",
	m20 = true,
	cost = 2800,
	color = rgb(170, 90, 255),
	text = "Расщеплённый луч: два боковых луча и дальность, −15% урона основного.",
	feat = { counter = "heavyKills", need = 120, text = "120 тяжёлых целей лучом" },
	ranks = { UPG_MULTISHOT = 2 },
	mods = { damageMult = 0.85, rangeMult = 1.1 },
	keys = {},
	coreName = "",
}
Defs.Evolutions.EV_M20_STAR_TUNNEL = {
	id = "EV_M20_STAR_TUNNEL",
	name = "ЗВЁЗДНЫЙ ТУННЕЛЬ",
	weapon = "W_RAILGUN",
	m20 = true,
	cost = 3000,
	color = rgb(255, 235, 150),
	text = "Длинная заряженная линия: +8 пробитий, +30% дальности и +25% урона, но −20% скорострельности.",
	feat = { counter = "line4", need = 150, text = "150 выстрелов, пробивших 4+ врагов" },
	ranks = {},
	mods = { pierceAdd = 8, falloffAdd = 0.1, rangeMult = 1.3, damageMult = 1.25, rateMult = 0.8 },
	keys = {},
	coreName = "",
}
Defs.M20ByWeapon = {
	W_ARC_RIFLE = "EV_M20_STORM",
	W_SCATTERGUN = "EV_M20_FIRE_RAM",
	W_PLASMA_BEAM = "EV_M20_VOID_PRISM",
	W_RAILGUN = "EV_M20_STAR_TUNNEL",
}

export type UpgradeDef = {
	id: string,
	name: string,
	icon: string,
	color: Color3,
	stat: (rank: number) -> string,
	describe: (rank: number) -> string,
}

local function pick<T>(rank: number, values: { T }): T
	return values[math.clamp(rank, 1, #values)]
end
Defs.rankValue = pick

Defs.UpgradeValues = {
	UPG_CHAIN = { every = { 6, 5, 4 }, targets = { 2, 3, 4 }, mult = 0.45, radius = 18 },
	UPG_RICOCHET = { bounces = { 1, 1, 2 }, mult = { 0.45, 0.6, 0.6 }, radius = 26 },
	UPG_PIERCE = { extra = { 1, 2, 3 }, falloff = 0.72 },
	UPG_IGNITE = { dps = { 5, 8, 12 }, duration = 3 },
	UPG_DETONATE = { every = { 8, 6, 4 }, damage = { 40, 55, 75 }, radius = 13 },
	UPG_CORRODE = { perHit = 0.06, cap = { 0.24, 0.36, 0.48 }, duration = 4 },
	UPG_FREEZE = {
		slow = { 0.22, 0.32, 0.42 },
		weaken = { 0.25, 0.35, 0.45 },
		frail = { 0.12, 0.18, 0.25 },
		shards = { 3, 4, 5 },
		shardMult = 0.7,
		shardRadius = 10,
		pointBlank = { 0.25, 0.4, 0.55 }, -- Вулкан adaptation: point-blank volleys stun (≤ 12 studs)
		pointBlankRange = 12,
		duration = 2,
		bossCap = 0.1,
	},
	UPG_MULTISHOT = { extra = { 1, 2, 2 }, mult = { 0.45, 0.45, 0.6 } },
	UPG_FIRERATE = { bonus = { 0.14, 0.27, 0.4 } },
	UPG_CRIT = { chance = { 0.1, 0.18, 0.26 }, mult = { 1.6, 1.8, 2.1 } },
	UPG_DASH_SHOCK = { damage = { 35, 60, 90 }, radius = 5, stun = 0.7, cooldown = { 0, 0.4, 0.8 } },
	UPG_SHIELD = { every = { 22, 17, 12 }, amount = { 20, 30, 40 }, reactor = { 40, 60, 80 } },
}

local V = Defs.UpgradeValues
local function pct(n: number): string
	return tostring(math.floor(n * 100 + 0.5)) .. "%"
end

-- stat(rank) is the headline value shown as "before → after" on cards.
Defs.Upgrades = {
	UPG_CHAIN = {
		id = "UPG_CHAIN",
		style = "CROWD",
		name = "ЦЕПНАЯ ДУГА",
		icon = "chain",
		color = rgb(84, 238, 255),
		stat = function(r)
			return `{pick(r, V.UPG_CHAIN.targets)} цели`
		end,
		describe = function(r)
			return `Каждое {pick(r, V.UPG_CHAIN.every)}-е попадание бьёт молнией по соседям.`
		end,
	},
	UPG_RICOCHET = {
		id = "UPG_RICOCHET",
		style = "CROWD",
		name = "РИКОШЕТ",
		icon = "ricochet",
		color = rgb(120, 200, 255),
		stat = function(r)
			return `{pick(r, V.UPG_RICOCHET.bounces)}× по {pct(pick(r, V.UPG_RICOCHET.mult))}`
		end,
		describe = function(r)
			return "Пуля отскакивает в соседнюю цель."
		end,
	},
	UPG_PIERCE = {
		id = "UPG_PIERCE",
		style = "LINE",
		name = "ПРОБОЙ",
		icon = "pierce",
		color = rgb(200, 160, 255),
		stat = function(r)
			return `+{pick(r, V.UPG_PIERCE.extra)} насквозь`
		end,
		describe = function(r)
			return "Выстрел прошивает врагов насквозь."
		end,
	},
	UPG_IGNITE = {
		id = "UPG_IGNITE",
		style = "CROWD",
		name = "ПОДЖОГ",
		icon = "fire",
		color = rgb(255, 140, 50),
		stat = function(r)
			return `{pick(r, V.UPG_IGNITE.dps)} урона/с`
		end,
		describe = function(r)
			return "Попадания поджигают врагов на 3 с."
		end,
	},
	UPG_DETONATE = {
		id = "UPG_DETONATE",
		style = "CROWD",
		name = "ДЕТОНАТОР",
		icon = "burst",
		color = rgb(255, 90, 60),
		stat = function(r)
			return `{pick(r, V.UPG_DETONATE.damage)} урона`
		end,
		describe = function(r)
			return `Каждое {pick(r, V.UPG_DETONATE.every)}-е убийство взрывается.`
		end,
	},
	UPG_CORRODE = {
		id = "UPG_CORRODE",
		style = "CONTROL",
		name = "КОРРОЗИЯ",
		icon = "drop",
		color = rgb(170, 255, 80),
		stat = function(r)
			return `+{pct(pick(r, V.UPG_CORRODE.cap))} урона`
		end,
		describe = function(r)
			return "Разъедает броню и щиты врагов."
		end,
	},
	UPG_FREEZE = {
		id = "UPG_FREEZE",
		style = "CONTROL",
		name = "КРИО-ПАТРОНЫ",
		icon = "snow",
		color = rgb(150, 230, 255),
		stat = function(r)
			return `−{pct(pick(r, V.UPG_FREEZE.slow))} скорости`
		end,
		describe = function(r)
			return `Замедленные: +{pct(pick(r, V.UPG_FREEZE.frail))} урона к ним, −{pct(
				pick(r, V.UPG_FREEZE.weaken)
			)} их урона. Гибель — {pick(r, V.UPG_FREEZE.shards)} ледяных осколка.`
		end,
	},
	UPG_MULTISHOT = {
		id = "UPG_MULTISHOT",
		style = "CROWD",
		name = "РАСЩЕПЛЕНИЕ",
		icon = "fan",
		color = rgb(255, 220, 90),
		stat = function(r)
			return `+{pick(r, V.UPG_MULTISHOT.extra)} снаряд`
		end,
		describe = function(r)
			return `Боковые снаряды, {pct(pick(r, V.UPG_MULTISHOT.mult))} урона.`
				.. (if r >= 3 then " Боковые пробивают ещё 1 цель." else "")
		end,
	},
	UPG_FIRERATE = {
		id = "UPG_FIRERATE",
		style = "LINE",
		name = "РАЗГОН",
		icon = "chevrons",
		color = rgb(255, 240, 160),
		stat = function(r)
			return `+{pct(pick(r, V.UPG_FIRERATE.bonus))} темп`
		end,
		describe = function(r)
			return "Быстрее стрельба и перезарядка."
		end,
	},
	UPG_CRIT = {
		id = "UPG_CRIT",
		style = "LINE",
		name = "ТОЧНЫЙ УДАР",
		icon = "crosshair",
		color = rgb(255, 80, 120),
		stat = function(r)
			return `{pct(pick(r, V.UPG_CRIT.chance))} · ×{pick(r, V.UPG_CRIT.mult)}`
		end,
		describe = function(r)
			return "Шанс критического попадания: урон ×"
				.. pick(r, V.UPG_CRIT.mult)
				.. "."
		end,
	},
	UPG_DASH_SHOCK = {
		id = "UPG_DASH_SHOCK",
		style = "CONTROL",
		name = "ШОКОВЫЙ РЫВОК",
		icon = "dashbolt",
		color = rgb(110, 255, 210),
		stat = function(r)
			return `{pick(r, V.UPG_DASH_SHOCK.damage)} урона`
		end,
		describe = function(r)
			return "Рывок бьёт током и оглушает."
				.. (if r >= 2 then " Рывок чаще." else "")
		end,
	},
	UPG_SHIELD = {
		id = "UPG_SHIELD",
		style = "CONTROL",
		name = "БАРЬЕР",
		icon = "shield",
		color = rgb(120, 160, 255),
		stat = function(r)
			return `щит {pick(r, V.UPG_SHIELD.amount)}`
		end,
		describe = function(r)
			return `Каждые {pick(r, V.UPG_SHIELD.every)} убийств — энергощит тебе и буру.`
		end,
	},
} :: { [string]: UpgradeDef }

Defs.UpgradeOrder = {
	"UPG_CHAIN",
	"UPG_RICOCHET",
	"UPG_PIERCE",
	"UPG_IGNITE",
	"UPG_DETONATE",
	"UPG_CORRODE",
	"UPG_FREEZE",
	"UPG_MULTISHOT",
	"UPG_FIRERATE",
	"UPG_CRIT",
	"UPG_DASH_SHOCK",
	"UPG_SHIELD",
}

Defs.Fallbacks = {
	FB_REPAIR = {
		id = "FB_REPAIR",
		name = "ПОЛЕВОЙ РЕМОНТ",
		icon = "plus",
		color = rgb(110, 255, 140),
		text = "+35 здоровья",
	},
	FB_CHARGE = {
		id = "FB_CHARGE",
		name = "ГРАВИЗАРЯД",
		icon = "battery",
		color = rgb(84, 238, 255),
		text = "Громобой готов сразу",
	},
}

-- Build styles (DD-017): every card belongs to one way of fighting. The first offer of a run shows one
-- card of each style, and the draft leans towards finishing a synergy you started.
Defs.Styles = {
	CROWD = {
		name = "РАЗГРОМ",
		color = rgb(255, 150, 60),
		icon = "burst",
		text = "Зачистка толпы: цепи, отскоки, взрывы",
	},
	LINE = {
		name = "ЛИНИЯ",
		color = rgb(200, 160, 255),
		icon = "pierce",
		text = "Пробой колонн, криты и темп",
	},
	CONTROL = {
		name = "КОНТРОЛЬ",
		color = rgb(130, 220, 255),
		icon = "shield",
		text = "Замедление, коррозия, щит: держи позицию",
	},
}
Defs.StyleOrder = { "CROWD", "LINE", "CONTROL" }

Defs.Synergies = {
	SYN_CHAIN_RICOCHET = {
		keys = { "UPG_CHAIN", "UPG_RICOCHET" },
		name = "ДВОЙНАЯ ДУГА",
		text = "Рикошеты заряжают цепную дугу.",
	},
	SYN_IGNITE_DETONATE = {
		keys = { "UPG_IGNITE", "UPG_DETONATE" },
		name = "ПОГРЕБАЛЬНЫЙ КОСТЁР",
		text = "Горящие враги взрываются при гибели.",
	},
	SYN_PIERCE_CRIT = {
		keys = { "UPG_PIERCE", "UPG_CRIT" },
		name = "ЛИНИЯ ОГНЯ",
		text = "С 3-й цели пробоя — крит без ослабления.",
	},
	SYN_FREEZE_SHIELD = {
		keys = { "UPG_FREEZE", "UPG_SHIELD" },
		name = "ЛЕДЯНОЙ ПАНЦИРЬ",
		text = "Щит при ударе и пополнении замораживает всех рядом.",
	},
	SYN_DASH_FREEZE = {
		keys = { "UPG_DASH_SHOCK", "UPG_FREEZE" },
		name = "ЛЕДОЛОМ",
		text = "Рывок раскалывает замедленных: ×2 урона.",
	},
	SYN_FREEZE_CORRODE = {
		keys = { "UPG_FREEZE", "UPG_CORRODE" },
		name = "ХРУПКОСТЬ",
		text = "Замедленные разъедаются вдвое быстрее, предел +15%.",
	},
}
Defs.SynergyOrder = {
	"SYN_CHAIN_RICOCHET",
	"SYN_IGNITE_DETONATE",
	"SYN_PIERCE_CRIT",
	"SYN_FREEZE_SHIELD",
	"SYN_DASH_FREEZE",
	"SYN_FREEZE_CORRODE",
}
Defs.Brittle = { RateMult = 2, CapAdd = 0.15 }
Defs.FrostShell = { Radius = 9, Stun = 0.8, Slow = 0.45, SlowTime = 2.2, Damage = 12, Cooldown = 2 }
Defs.IceBreakMult = 2

export type EnemyDef = {
	id: string,
	index: number,
	name: string,
	hp: number,
	speed: number,
	radius: number,
	damage: number,
	cooldown: number,
	xp: number,
	big: boolean,
	boss: boolean,
	scaleHp: boolean,
}

Defs.Enemies = {
	EN_RUNNER = {
		id = "EN_RUNNER",
		index = 1,
		name = "БЕГУН",
		hp = 24,
		speed = 15.5,
		radius = 1.6,
		damage = 7,
		cooldown = 1.0,
		xp = 1,
		big = false,
		boss = false,
		scaleHp = true,
	},
	EN_STALKER = {
		id = "EN_STALKER",
		index = 2,
		name = "ПРЫГУН",
		hp = 40,
		speed = 17,
		radius = 1.8,
		damage = 12,
		cooldown = 2.8,
		xp = 2,
		big = false,
		boss = false,
		scaleHp = true,
	},
	EN_SPITTER = {
		id = "EN_SPITTER",
		index = 3,
		name = "ПЛЕВУН",
		hp = 60,
		speed = 9,
		radius = 2.2,
		damage = 7,
		cooldown = 4.2,
		xp = 3,
		big = false,
		boss = false,
		scaleHp = true,
	},
	EN_BULWARK = {
		id = "EN_BULWARK",
		index = 4,
		name = "БРОНЕНОСЕЦ",
		hp = 210,
		speed = 7.5,
		radius = 3.2,
		damage = 16,
		cooldown = 2.4,
		xp = 6,
		big = true,
		boss = false,
		scaleHp = true,
	},
	ELITE_BULWARK = {
		id = "ELITE_BULWARK",
		index = 5,
		name = "ЭЛИТНЫЙ БРОНЕНОСЕЦ",
		hp = 1150,
		speed = 9.5,
		radius = 4.3,
		damage = 22,
		cooldown = 2.2,
		xp = 45,
		big = true,
		boss = false,
		scaleHp = true,
		elite = true,
	},
	HIVE = {
		id = "HIVE",
		index = 6,
		name = "ГНЕЗДО",
		hp = 480,
		speed = 0,
		radius = 5,
		damage = 0,
		cooldown = 2.4,
		xp = 20,
		big = true,
		boss = false,
		scaleHp = true,
		static = true,
	},
	BOSS_BROODMOTHER = {
		id = "BOSS_BROODMOTHER",
		index = 7,
		name = "МАТЬ РОЯ",
		hp = 7200,
		speed = 7,
		radius = 8.5,
		damage = 26,
		cooldown = 0,
		xp = 0,
		big = true,
		boss = true,
		scaleHp = false,
	},
	EN_BOMBER = {
		id = "EN_BOMBER",
		index = 8,
		name = "ВЗРЫВУН",
		hp = 30,
		speed = 17.5,
		radius = 1.7,
		damage = 18,
		cooldown = 0,
		xp = 2,
		big = false,
		boss = false,
		scaleHp = true,
	},
	-- Objective kinds (stage 8): the O01 elite and the O05 / C-A01 structures get their own bodies.
	ELITE_CARRIER = {
		id = "ELITE_CARRIER",
		index = 10,
		name = "АЛЬФА",
		hp = 1150,
		speed = 9.5,
		radius = 4.3,
		damage = 22,
		cooldown = 2.2,
		xp = 45,
		big = true,
		boss = false,
		scaleHp = true,
		elite = true,
	},
	NODE = {
		id = "NODE",
		index = 11,
		name = "ПИТАЮЩИЙ УЗЕЛ",
		hp = 1000,
		speed = 0,
		radius = 4.5,
		damage = 0,
		cooldown = 99,
		xp = 30,
		big = true,
		boss = false,
		scaleHp = false,
		static = true,
	},
	ACID_SOURCE = {
		id = "ACID_SOURCE",
		index = 12,
		name = "КИСЛОТНЫЙ ИСТОЧНИК",
		hp = 900,
		speed = 0,
		radius = 4.5,
		damage = 0,
		cooldown = 99,
		xp = 30,
		big = true,
		boss = false,
		scaleHp = false,
		static = true,
	},
	-- Raids (DD-039): another player's outpost. Its turrets are static enemies that shoot the hunters;
	-- the extractor core is the objective.
	TUR_STING = {
		id = "TUR_STING",
		index = 13,
		name = "ТУРЕЛЬ",
		hp = 260,
		speed = 0,
		radius = 2.2,
		damage = 0,
		cooldown = 99,
		xp = 12,
		big = true,
		boss = false,
		scaleHp = false,
		static = true,
		structure = "STING",
	},
	TUR_ARC = {
		id = "TUR_ARC",
		index = 14,
		name = "РАЗРЯДНИК",
		hp = 320,
		speed = 0,
		radius = 2.2,
		damage = 0,
		cooldown = 99,
		xp = 14,
		big = true,
		boss = false,
		scaleHp = false,
		static = true,
		structure = "ARC",
	},
	TUR_MORTAR = {
		id = "TUR_MORTAR",
		index = 15,
		name = "СПОРОМЁТ",
		hp = 360,
		speed = 0,
		radius = 2.4,
		damage = 0,
		cooldown = 99,
		xp = 16,
		big = true,
		boss = false,
		scaleHp = false,
		static = true,
		structure = "MORTAR",
	},
	TUR_SHIELD = {
		id = "TUR_SHIELD",
		index = 16,
		name = "ЩИТ-ПИЛОН",
		hp = 300,
		speed = 0,
		radius = 2.2,
		damage = 0,
		cooldown = 99,
		xp = 14,
		big = true,
		boss = false,
		scaleHp = false,
		static = true,
		structure = "SHIELD",
	},
	OUTPOST_CORE = {
		id = "OUTPOST_CORE",
		index = 17,
		name = "ВРАЖЕСКИЙ БУР",
		hp = 8000,
		speed = 0,
		radius = 8,
		damage = 0,
		cooldown = 99,
		xp = 80,
		big = true,
		boss = false,
		scaleHp = false,
		static = true,
	},
	BOSS_DEVOURER = {
		id = "BOSS_DEVOURER",
		index = 9,
		name = "ПОЖИРАТЕЛЬ",
		hp = 6600,
		speed = 9.5,
		radius = 7,
		damage = 28,
		cooldown = 0,
		xp = 0,
		big = true,
		boss = true,
		scaleHp = false,
	},
} :: { [string]: EnemyDef }

Defs.EnemyByIndex = {} :: { [number]: EnemyDef }
for _, def in Defs.Enemies do
	Defs.EnemyByIndex[def.index] = def
end

Defs.Stalker = { Trigger = 24, Windup = 0.65, LungeSpeed = 58, LungeTime = 0.32, Recover = 0.6 }
Defs.Spitter = { MinRange = 28, MaxRange = 50, Windup = 0.5, Telegraph = 1.05, Active = 1.5, Radius = 8, Tick = 0.5 }
Defs.Bulwark = { Windup = 0.7, Reach = 8, FrontArmor = 0.35, FrontCos = 0.34 }
Defs.Elite = { ChargeWindup = 1.0, ChargeSpeed = 48, ChargeTime = 0.85, ChargeCooldown = 7 }
Defs.Bomber = { Trigger = 6, Fuse = 0.75, Radius = 7, EnemyDamage = 70 }
Defs.Hive = { SpawnEvery = 2.4, RewardHeal = 40, RewardXp = 60 }
Defs.Boss = {
	SweepWindup = 1.1,
	SweepRadius = 26,
	SweepAngle = 110,
	SweepDamage = 24,
	LaneWindup = 1.5,
	LaneLength = 95,
	LaneWidth = 7,
	LaneDamage = 18,
	LaneActive = 1.6,
	ChargeWindup = 1.3,
	ChargeSpeed = 62,
	ChargeTime = 1.0,
	ChargeDamage = 30,
	ExposedTime = 3.2,
	ExposedMult = 1.75,
	SummonEvery = 13,
	Recover = 1.6,
}
Defs.Devourer = {
	BiteWindup = 0.9,
	BiteRadius = 17,
	BiteAngle = 90,
	BiteDamage = 22,
	BurrowTime = 1.6,
	EruptWindup = 1.3,
	EruptRadius = 11,
	EruptDamage = 30,
	RingWindup = 1.1,
	RingCount = 10,
	RingDistance = 17,
	RingRadius = 5,
	RingActive = 2.2,
	RingDamage = 14,
	ExposedTime = 3.0,
	ExposedMult = 1.8,
	SummonEvery = 15,
}

-- Enemy HP scales with run time; DPS scales with your build.
function Defs.hpScale(t: number): number
	return 1 + (t / 60) * 0.24
end

function Defs.xpToNext(level: number): number
	return math.floor(7 + level * 5 + level ^ 1.75)
end

-- DD-105: the weapon's super — the main skill. It charges from the damage the hero deals (not from a
-- timer): `Seconds` of the bare weapon's full fire fill it, so cards that add damage charge it faster.
-- A run starts half charged. Tap: at the gun's own target; drag (phone) or aim (PC): where you point.
-- Numbers are TUNABLE.
Defs.Super = {
	Seconds = 12,
	Start = 0.5,
}
Defs.Supers = {
	-- a slow ball of lightning: bursts on the first enemy (or at its range), stuns, arcs on to more
	W_ARC_RIFLE = {
		name = "ШАРОВАЯ МОЛНИЯ",
		short = "МОЛНИЯ",
		icon = "chain",
		text = "Шар молнии взрывается в толпе, оглушает и бьёт разрядами ещё по шести",
		tip = "шар молнии: взрыв, оглушение, разряды",
		speed = 42,
		range = 70,
		radius = 9,
		damage = 120,
		stun = 0.7,
		arcs = 6,
		arcRange = 22,
		arcDamage = 70,
	},
	-- a point-blank wall of shot: a wide cone that throws the swarm back — the way out of a ring
	W_SCATTERGUN = {
		name = "ОТБОЙНЫЙ ЗАЛП",
		short = "ЗАЛП",
		icon = "burst",
		text = "Широкий залп в упор отбрасывает рой — путь из окружения",
		tip = "залп в упор отбрасывает рой",
		halfAngle = 42,
		reach = 17,
		damage = 90,
		knock = 13,
		stun = 0.6,
		iframes = 0.35,
	},
	-- three seconds of a wide beam that pierces everything and never overheats
	W_PLASMA_BEAM = {
		name = "ПРОЖИГ",
		short = "ПРОЖИГ",
		icon = "fire",
		text = "Три секунды широкий луч прошивает всех насквозь и не перегревается",
		tip = "3 с широкий луч насквозь, без перегрева",
		duration = 3,
		tick = 0.1,
		halfWidth = 2.8,
		tickDamage = 12,
	},
	-- one charged slug through the whole line to the wall, leaving a burning strip
	W_RAILGUN = {
		name = "РАЗГОН",
		short = "РАЗГОН",
		icon = "pierce",
		text = "Заряженный выстрел прошивает всю линию до стены и оставляет горящую полосу",
		tip = "выстрел через всю линию, полоса огня",
		range = 200,
		halfWidth = 2.2,
		damage = 260,
		strip = 4,
		burnDps = 30,
	},
}

-- S01 «ГРОМОБОЙ» (ex-«Гравимолот», DD-006, renamed DD-092): the one active skill. 360° gravity strike around the player, separate from
-- weapons and cards. The first cast in O01 is the reactor-fed Emergency Overload (bigger, two waves).
Defs.S01 = {
	Windup = 0.3, -- stable window before impact (brief i-frames cover it)
	Cinematic = 1.5, -- DD-092: the first (tutorial) strike holds the world this long while the hammer rears
	IFrames = 0.4,
	Cooldown = 32,
	Radius = 9.5,
	Damage = 75,
	Targets = 12,
	Knock = 9,
	Stun = 0.7,
	BigMult = 0.5, -- damage vs heavy / elite
	BossMult = 0.35,
	BigKnock = 2,
	CrowdHits = 8, -- "массовый удар" for mastery
	Emergency = { Radius = 14, Outer = 18, Damage = 160, Targets = 28, Knock = 14, OuterSlow = 0.5 }, -- catches the scripted ring
	PerkCut = 0.06, -- PK_OVERDRIVE rank: −6% cooldown each
}

-- S01 mastery and specializations (DD-013, Gravihammer doc §6). Points = hits + 2×kills + 10×crowd strikes
-- (never weapon kills). A branch is chosen from M5; its tiers open at M5 / M8 / M12. One branch active.
Defs.S01Mastery = {
	Ladder = {
		0,
		100,
		200,
		350,
		550,
		800,
		1100,
		1500,
		2000,
		2600,
		3300,
		4100,
		5000,
		6000,
		7100,
		8300,
		9600,
		11000,
		12500,
		15000,
	},
	BranchAt = 5,
	TierAt = { 5, 8, 12 },
}
Defs.S01Branches = {
	A = {
		id = "A",
		name = "КАТАКЛИЗМ",
		color = rgb(255, 140, 50),
		tiers = {
			"Расширенный фронт: радиус +15%",
			"Сейсмический отклик: вторая волна 50% урона",
			"Грозовой разлом: урон +30%, перезарядка −15%",
		},
	},
	B = {
		id = "B",
		name = "БАСТИОН",
		color = rgb(84, 238, 255),
		tiers = {
			"Отражающий импульс: отброс ×1.4, оглушение +0.5 с",
			"Обратная зарядка: +4 щита за цель (до 30)",
			"Неприступный шаг: +1 с неуязвимости и +10 HP",
		},
	},
	C = {
		id = "C",
		name = "СИНГУЛЯРНОСТЬ",
		color = rgb(190, 120, 255),
		tiers = {
			"Грозовой след: замедление 40% вокруг",
			"Сжатие: враги стягиваются к тебе, а не разлетаются",
			"Коллапс: через 0.6 с повторный удар 60%",
		},
	},
}

function Defs.s01Points(stats: any): number
	if not stats then
		return 0
	end
	return (stats.hits or 0) + 2 * (stats.kills or 0) + 10 * (stats.crowds or 0)
end

function Defs.s01Rank(points: number): number
	local rank = 1
	for r, need in Defs.S01Mastery.Ladder do
		if points >= need then
			rank = r
		end
	end
	return rank
end

function Defs.s01Tier(rank: number): number
	local tier = 0
	for i, at in Defs.S01Mastery.TierAt do
		if rank >= at then
			tier = i
		end
	end
	return tier
end

-- Permanent unique components ("КОМПОНЕНТЫ"): earned by deeds in operations, spent on crafting forms.
Defs.Components = {
	CMP_STORM_CORE = {
		id = "CMP_STORM_CORE",
		name = "ЯДРО БУРИ",
		icon = "core",
		text = "Сердце Громовержца. Добыто с Носителя ядра (O01).",
	},
	CMP_FLAME_HEART = {
		id = "CMP_FLAME_HEART",
		name = "СЕРДЦЕ ПЛАМЕНИ",
		icon = "core",
		text = "Сердце Адской мельницы. Первая победа в «Кровавой ночи» (O06).",
	},
	CMP_VOID_HEART = {
		id = "CMP_VOID_HEART",
		name = "СЕРДЦЕ ПУСТОТЫ",
		icon = "core",
		text = "Сердце Копья Пустоты. Первая победа над Пожирателем (O07).",
	},
	CMP_LINE_BREACH = {
		id = "CMP_LINE_BREACH",
		name = "ПРОБОЙ ЛИНИИ",
		icon = "core",
		text = "Сердце Звездолома. Испытание рельсотрона: выстрелы, пробившие 2+ врагов.",
	},
}

-- Weapon mastery M1–M20 (D03 §3, 03_GAME_DATA mastery thresholds, BALANCE_CANDIDATE). Personal lethal
-- kills with that weapon. Other weapons scale the arc-rifle ladder by their kill rate.
Defs.Mastery = {
	Ladder = {
		0,
		150,
		400,
		800,
		1300,
		2000,
		2800,
		3800,
		5000,
		6400,
		8000,
		9800,
		12000,
		14500,
		17000,
		20500,
		24500,
		29400,
		35000,
		42000,
	},
	Scale = { W_ARC_RIFLE = 1, W_SCATTERGUN = 0.6, W_PLASMA_BEAM = 0.7, W_RAILGUN = 0.4 },
	Milestones = {
		[2] = "Модуль I",
		[4] = "Характерный узел",
		[8] = "Модуль II",
		[10] = "Постоянная форма",
		[15] = "Модуль III",
		[20] = "Высшая форма",
	},
}

function Defs.masteryNeed(weaponId: string, rank: number): number
	local ladder = Defs.Mastery.Ladder
	local r = math.clamp(rank, 1, #ladder)
	return math.floor(ladder[r] * (Defs.Mastery.Scale[weaponId] or 1) + 0.5)
end

-- Returns rank (1..20), kills into the current rank, kills needed for the next (nil at M20).
function Defs.masteryRank(weaponId: string, kills: number): (number, number, number?)
	local rank = 1
	for r = 2, #Defs.Mastery.Ladder do
		if kills >= Defs.masteryNeed(weaponId, r) then
			rank = r
		end
	end
	if rank >= #Defs.Mastery.Ladder then
		return rank, 0, nil
	end
	local lo, hi = Defs.masteryNeed(weaponId, rank), Defs.masteryNeed(weaponId, rank + 1)
	return rank, kills - lo, hi - lo
end

-- Research ("ИССЛЕДОВАНИЕ ВИДОВ", D03 §2): personal confirmed kills per species. Common species have
-- higher thresholds. Stage I reveals the species card, II unlocks its lab item, III completes it.
Defs.Research = {
	EN_RUNNER = { 200, 1200, 5000 },
	EN_SPITTER = { 30, 140, 600 },
	EN_STALKER = { 40, 200, 800 },
	EN_BULWARK = { 15, 80, 300 },
	EN_BOMBER = { 40, 200, 800 },
	ELITE_BULWARK = { 1, 5, 20 },
	ELITE_CARRIER = { 1, 3, 10 },
	HIVE = { 3, 15, 50 },
	NODE = { 3, 15, 50 },
	ACID_SOURCE = { 3, 15, 50 },
	BOSS_BROODMOTHER = { 1, 3, 10 },
	BOSS_DEVOURER = { 1, 3, 10 },
}

function Defs.researchStage(kind: string, kills: number): number
	local t = Defs.Research[kind]
	if not t then
		return 0
	end
	local s = 0
	for i, need in t do
		if kills >= need then
			s = i
		end
	end
	return s
end

-- Starter technologies (O01 first win). Grant tops the balance up to one of them (D03 §6).
Defs.Tech = {
	TECH_PIERCE_CORE = {
		id = "TECH_PIERCE_CORE",
		name = "ПРОБИВНОЙ СЕРДЕЧНИК",
		cost = 180,
		text = "Первое попадание каждого выстрела пробивает цель",
	},
	TECH_EMERGENCY_CAP = {
		id = "TECH_EMERGENCY_CAP",
		name = "АВАРИЙНЫЙ КОНДЕНСАТОР",
		cost = 180,
		text = "Раз за операцию: при 50% реактор бьёт импульсом",
		radius = 22,
		damage = 90,
		knock = 12,
	},
}
Defs.TechOrder = { "TECH_PIERCE_CORE", "TECH_EMERGENCY_CAP" }
Defs.FirstWinGrant = 180
Defs.FormMastery = 10 -- M10 opens the permanent form craft

-- Railgun trial «Пробой линии» (D03 §3): N charged shots that each damage >= 2 normal enemies in one
-- line. Counted across runs once the railgun is owned; the first completion grants the component.
Defs.LineTrial = { Shots = 60, MinHits = 2 }

-- Story blueprints (D03 §1): O02 → Вулкан, O03 → Разлом, O04 → Рельсотрон. Blueprint ≠ owned.
Defs.Blueprints = { W_SCATTERGUN = "O02", W_PLASMA_BEAM = "O04", W_RAILGUN = "O05" }

-- Squad rules (DD-012): a player at 0 HP is downed, not dead. A teammate standing close fills the revive
-- ring; nobody close = it slowly drains. Bleed-out ends the operation for that player (spectate).
Defs.Coop = { ReviveRadius = 6.5, ReviveTime = 3, ReviveHp = 0.4, ReviveIFrames = 2, BleedOut = 30, Drain = 0.5 }

-- Squad rules (DD-012): a player at 0 HP is downed, not dead. A teammate standing close fills the revive
-- ring; nobody close = it slowly drains. Bleed-out ends the operation for that player (spectate).
Defs.Coop =
	{ ReviveRadius = 6.5, ReviveTime = 3, ReviveHp = 0.4, ReviveIFrames = 2, BleedOut = 30, Drain = 0.5, JoinMax = 4 } -- JoinMax (DD-088): catch-up cards for a hunter joining a drill defence

-- Reactor (DD-004): a defendable objective. HP per operation (Ops), scaled for squads.
Defs.Reactor = {
	Radius = 7,
	Warnings = { 0.5, 0.25 },
	AcidMult = 0.6, -- spitter acid vs the hull (a spitter strike is a threat, not a wipe)
	ContactMult = 0.5, -- melee contact damage vs the hull (a strike group must be stopped, not one runner)
	hpScale = function(_threat: number, players: number): number
		return 1 + 0.25 * math.max(0, players - 1)
	end,
}

Defs.Overdrive = {
	PerKill = 0.65,
	PerElite = 20,
	RateBonus = 0.3,
	DamageBonus = 0.15,
	Pierce = 1,
	BlastRadius = 15,
	BlastDamage = 45,
}
Defs.Coil = { Radius = 7, Range = 34, Damage = 160, Targets = 14, Cooldown = 40, FirstReady = 45 }
Defs.Drops = { HealChance = 0.012, MagnetChance = 0.004, HealAmount = 25, OrbCap = 220 }

-- Threat levels ("УГРОЗА"): unlocked per map by winning the previous level.
Defs.Threat = {
	Max = 5,
	hp = function(t: number): number
		return 1 + 0.25 * (t - 1)
	end,
	damage = function(t: number): number
		return 1 + 0.12 * (t - 1)
	end,
	spawn = function(t: number): number
		return 1 + 0.1 * (t - 1)
	end,
	reward = function(t: number): number
		return 1 + 0.35 * (t - 1)
	end,
}

-- Meta progression ("МАСТЕРСКАЯ"): small, choice-widening perks bought with Ксенит (stored as `scrap`).
Defs.Perks = {
	PK_VITALITY = {
		id = "PK_VITALITY",
		name = "ЖИВУЧЕСТЬ",
		icon = "heart",
		color = rgb(255, 90, 110),
		max = 5,
		costs = { 60, 110, 170, 240, 320 },
		stat = function(r: number): string
			return `+{r * 8} здоровья`
		end,
	},
	PK_MAGNET = {
		id = "PK_MAGNET",
		name = "МАГНИТ",
		icon = "magnet",
		color = rgb(84, 238, 255),
		max = 3,
		costs = { 50, 100, 160 },
		stat = function(r: number): string
			return `+{r * 20}% радиус сбора`
		end,
	},
	PK_REROLL = {
		id = "PK_REROLL",
		name = "ПЕРЕБРОС",
		icon = "reroll",
		color = rgb(255, 200, 60),
		max = 3,
		costs = { 80, 150, 240 },
		stat = function(r: number): string
			return `{r} переброс карт за забег`
		end,
	},
	PK_BANISH = {
		id = "PK_BANISH",
		name = "ИЗГНАНИЕ",
		icon = "banish",
		color = rgb(255, 80, 80),
		max = 2,
		costs = { 120, 220 },
		stat = function(r: number): string
			return `{r} изгнание карт за забег`
		end,
	},
	PK_DASH = {
		id = "PK_DASH",
		name = "ФОРСАЖ",
		icon = "dash",
		color = rgb(110, 255, 210),
		max = 3,
		costs = { 70, 130, 200 },
		stat = function(r: number): string
			return `−{r * 8}% перезарядка рывка`
		end,
	},
	PK_OVERDRIVE = {
		id = "PK_OVERDRIVE",
		name = "ГРАВИТАЦИЯ",
		icon = "hammer",
		color = rgb(84, 238, 255),
		max = 3,
		costs = { 70, 130, 200 },
		stat = function(r: number): string
			return `−{r * 6}% перезарядка Громобоя`
		end,
	},
	PK_INSIGHT = {
		id = "PK_INSIGHT",
		name = "ПРОЗРЕНИЕ",
		icon = "eye",
		color = rgb(190, 120, 255),
		max = 1,
		costs = { 400 },
		stat = function(r: number): string
			return "4 карты на выбор"
		end,
	},
	PK_SALVAGE = {
		id = "PK_SALVAGE",
		name = "ДОБЫЧА",
		icon = "gear",
		color = rgb(200, 210, 220),
		max = 3,
		costs = { 90, 160, 250 },
		stat = function(r: number): string
			return `+{r * 12}% Ксенита`
		end,
	},
}
Defs.PerkOrder =
	{ "PK_VITALITY", "PK_MAGNET", "PK_REROLL", "PK_BANISH", "PK_DASH", "PK_OVERDRIVE", "PK_INSIGHT", "PK_SALVAGE" }

-- Scrap reward for a finished run. lines = { {icon, amount}, ... } for the results screen.
-- Ксенит for a run (D03 §6): personal credited kills / 12 + 3 per combat level + outcome (+ nests),
-- × threat × salvage. `kills` is the player's own kill count (team kills only as a fallback).
function Defs.runReward(result: any, threat: number, salvageRank: number, kills: number?)
	local lines = {}
	local base = math.floor((kills or result.kills) / 12)
	table.insert(lines, { "skull", base })
	local levels = (result.level - 1) * 3
	table.insert(lines, { "level", levels })
	local outcome = if result.victory then 120 elseif result.time >= 180 then 35 else 10
	table.insert(lines, { if result.victory then "crown" else "timer", outcome })
	if result.hive == "cleared" then
		table.insert(lines, { "hive", 20 })
	end
	local sum = 0
	for _, l in lines do
		sum += l[2]
	end
	local mult = Defs.Threat.reward(threat) * (1 + 0.12 * salvageRank)
	return { total = math.floor(sum * mult + 0.5), lines = lines, mult = mult }
end

return Defs
