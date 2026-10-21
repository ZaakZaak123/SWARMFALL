--!strict
-- SWARMFALL content definitions (RU). Pure data shared by server sim, client UI and offline tests.
-- Every number is a tuning target, validated by tests/sim_run.luau (headless full-run bot).

local Defs = {}

Defs.Version = "SWARMFALL-3.0"

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
	spread: number,
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
		reload = 1.35,
		spread = 2,
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
		tagline = "В упор. Стена свинца. Поджигает рой.",
		kind = "shotgun",
		damage = 9,
		rate = 1.7,
		range = 40,
		magazine = 7,
		reload = 1.5,
		spread = 26,
		pellets = 8,
		pierce = 0,
		falloff = 0.72,
		knockback = 2.2,
		color = rgb(255, 150, 60),
		evolution = "EV_INFERNO_GRINDER",
		cost = 0,
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
		cost = 0,
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
		cost = 350,
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
		color = rgb(140, 220, 255),
		text = "Каждое попадание бьёт молнией ещё по 3 целям. +15% скорострельность.",
	},
	EV_INFERNO_GRINDER = {
		id = "EV_INFERNO_GRINDER",
		name = "АДСКАЯ МЕЛЬНИЦА",
		weapon = "W_SCATTERGUN",
		keys = { "UPG_IGNITE", "UPG_DETONATE" },
		coreName = "ЯДРО ПЛАМЕНИ",
		color = rgb(255, 110, 40),
		text = "+4 дробины, двойной поджог. Горящие враги взрываются при смерти.",
	},
	EV_VOID_LANCE = {
		id = "EV_VOID_LANCE",
		name = "КОПЬЁ ПУСТОТЫ",
		weapon = "W_PLASMA_BEAM",
		keys = { "UPG_PIERCE", "UPG_CORRODE" },
		coreName = "ЯДРО ПУСТОТЫ",
		color = rgb(150, 70, 255),
		text = "Пробивает всех. +40% дальность, +30% урон. Импульсы пустоты вдоль луча.",
	},
	EV_STARBREAKER = {
		id = "EV_STARBREAKER",
		name = "ЗВЕЗДОЛОМ",
		weapon = "W_RAILGUN",
		keys = { "UPG_CRIT", "UPG_DETONATE" },
		coreName = "ЗВЁЗДНОЕ ЯДРО",
		color = rgb(255, 230, 120),
		text = "Пробивает всех. Каждое попадание взрывается. +20% скорострельность.",
	},
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
	UPG_FREEZE = { slow = { 0.22, 0.32, 0.42 }, duration = 2, bossCap = 0.1 },
	UPG_MULTISHOT = { extra = { 1, 2, 2 }, mult = { 0.45, 0.45, 0.6 } },
	UPG_FIRERATE = { bonus = { 0.14, 0.27, 0.4 } },
	UPG_CRIT = { chance = { 0.1, 0.18, 0.26 }, mult = { 1.6, 1.8, 2.1 } },
	UPG_DASH_SHOCK = { damage = { 35, 60, 90 }, radius = 5, stun = 0.7, cooldown = { 0, 0.4, 0.8 } },
	UPG_SHIELD = { every = { 22, 17, 12 }, amount = { 20, 30, 40 } },
}

local V = Defs.UpgradeValues
local function pct(n: number): string
	return tostring(math.floor(n * 100 + 0.5)) .. "%"
end

-- stat(rank) is the headline value shown as "before → after" on cards.
Defs.Upgrades = {
	UPG_CHAIN = {
		id = "UPG_CHAIN",
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
		name = "КРИО-ПАТРОНЫ",
		icon = "snow",
		color = rgb(150, 230, 255),
		stat = function(r)
			return `−{pct(pick(r, V.UPG_FREEZE.slow))} скорости`
		end,
		describe = function(r)
			return "Попадания замедляют врагов на 2 с."
		end,
	},
	UPG_MULTISHOT = {
		id = "UPG_MULTISHOT",
		name = "РАСЩЕПЛЕНИЕ",
		icon = "fan",
		color = rgb(255, 220, 90),
		stat = function(r)
			return `+{pick(r, V.UPG_MULTISHOT.extra)} снаряд`
		end,
		describe = function(r)
			return `Боковые снаряды, {pct(pick(r, V.UPG_MULTISHOT.mult))} урона.`
		end,
	},
	UPG_FIRERATE = {
		id = "UPG_FIRERATE",
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
		name = "МЕТКОСТЬ",
		icon = "crosshair",
		color = rgb(255, 80, 120),
		stat = function(r)
			return `{pct(pick(r, V.UPG_CRIT.chance))} · ×{pick(r, V.UPG_CRIT.mult)}`
		end,
		describe = function(r)
			return "Шанс критического попадания."
		end,
	},
	UPG_DASH_SHOCK = {
		id = "UPG_DASH_SHOCK",
		name = "ШОКОВЫЙ РЫВОК",
		icon = "dashbolt",
		color = rgb(110, 255, 210),
		stat = function(r)
			return `{pick(r, V.UPG_DASH_SHOCK.damage)} урона`
		end,
		describe = function(r)
			return "Рывок бьёт током и оглушает." .. (if r >= 2 then " Рывок чаще." else "")
		end,
	},
	UPG_SHIELD = {
		id = "UPG_SHIELD",
		name = "БАРЬЕР",
		icon = "shield",
		color = rgb(120, 160, 255),
		stat = function(r)
			return `щит {pick(r, V.UPG_SHIELD.amount)}`
		end,
		describe = function(r)
			return `Каждые {pick(r, V.UPG_SHIELD.every)} убийств — энергощит.`
		end,
	},
} :: { [string]: UpgradeDef }

Defs.UpgradeOrder = {
	"UPG_CHAIN", "UPG_RICOCHET", "UPG_PIERCE", "UPG_IGNITE", "UPG_DETONATE", "UPG_CORRODE",
	"UPG_FREEZE", "UPG_MULTISHOT", "UPG_FIRERATE", "UPG_CRIT", "UPG_DASH_SHOCK", "UPG_SHIELD",
}

Defs.Fallbacks = {
	FB_REPAIR = { id = "FB_REPAIR", name = "ПОЛЕВОЙ РЕМОНТ", icon = "plus", color = rgb(110, 255, 140), text = "+35 здоровья" },
	FB_CHARGE = { id = "FB_CHARGE", name = "ЭНЕРГОЯЧЕЙКА", icon = "battery", color = rgb(255, 200, 60), text = "+60 перегрузки" },
}

Defs.Synergies = {
	SYN_CHAIN_RICOCHET = { keys = { "UPG_CHAIN", "UPG_RICOCHET" }, name = "ДВОЙНАЯ ДУГА" },
	SYN_IGNITE_DETONATE = { keys = { "UPG_IGNITE", "UPG_DETONATE" }, name = "ПОГРЕБАЛЬНЫЙ КОСТЁР" },
}

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
	EN_RUNNER = { id = "EN_RUNNER", index = 1, name = "БЕГУН", hp = 24, speed = 15.5, radius = 1.6, damage = 7, cooldown = 1.0, xp = 1, big = false, boss = false, scaleHp = true },
	EN_STALKER = { id = "EN_STALKER", index = 2, name = "ПРЫГУН", hp = 40, speed = 17, radius = 1.8, damage = 12, cooldown = 2.8, xp = 2, big = false, boss = false, scaleHp = true },
	EN_SPITTER = { id = "EN_SPITTER", index = 3, name = "ПЛЕВУН", hp = 60, speed = 9, radius = 2.2, damage = 7, cooldown = 4.2, xp = 3, big = false, boss = false, scaleHp = true },
	EN_BULWARK = { id = "EN_BULWARK", index = 4, name = "БРОНЕНОСЕЦ", hp = 210, speed = 7.5, radius = 3.2, damage = 16, cooldown = 2.4, xp = 6, big = true, boss = false, scaleHp = true },
	ELITE_BULWARK = { id = "ELITE_BULWARK", index = 5, name = "ЭЛИТНЫЙ БРОНЕНОСЕЦ", hp = 1150, speed = 9.5, radius = 4.3, damage = 22, cooldown = 2.2, xp = 45, big = true, boss = false, scaleHp = true },
	HIVE = { id = "HIVE", index = 6, name = "ГНЕЗДО", hp = 480, speed = 0, radius = 5, damage = 0, cooldown = 2.4, xp = 20, big = true, boss = false, scaleHp = true },
	BOSS_BROODMOTHER = { id = "BOSS_BROODMOTHER", index = 7, name = "МАТКА РАЗЛОМА", hp = 7200, speed = 7, radius = 8.5, damage = 26, cooldown = 0, xp = 0, big = true, boss = true, scaleHp = false },
	EN_BOMBER = { id = "EN_BOMBER", index = 8, name = "ВЗРЫВУН", hp = 30, speed = 17.5, radius = 1.7, damage = 18, cooldown = 0, xp = 2, big = false, boss = false, scaleHp = true },
	BOSS_DEVOURER = { id = "BOSS_DEVOURER", index = 9, name = "ПОЖИРАТЕЛЬ", hp = 6600, speed = 9.5, radius = 7, damage = 28, cooldown = 0, xp = 0, big = true, boss = true, scaleHp = false },
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
	SweepWindup = 1.1, SweepRadius = 26, SweepAngle = 110, SweepDamage = 24,
	LaneWindup = 1.5, LaneLength = 95, LaneWidth = 7, LaneDamage = 18, LaneActive = 1.6,
	ChargeWindup = 1.3, ChargeSpeed = 62, ChargeTime = 1.0, ChargeDamage = 30,
	ExposedTime = 3.2, ExposedMult = 1.75, SummonEvery = 13, Recover = 1.6,
}
Defs.Devourer = {
	BiteWindup = 0.9, BiteRadius = 17, BiteAngle = 90, BiteDamage = 22,
	BurrowTime = 1.6, EruptWindup = 1.3, EruptRadius = 11, EruptDamage = 30,
	RingWindup = 1.1, RingCount = 10, RingDistance = 17, RingRadius = 5, RingActive = 2.2, RingDamage = 14,
	ExposedTime = 3.0, ExposedMult = 1.8, SummonEvery = 15,
}

-- Enemy HP scales with run time; DPS scales with your build.
function Defs.hpScale(t: number): number
	return 1 + (t / 60) * 0.24
end

function Defs.xpToNext(level: number): number
	return math.floor(7 + level * 5 + level ^ 1.75)
end

Defs.Overdrive = { PerKill = 0.65, PerElite = 20, RateBonus = 0.3, DamageBonus = 0.15, Pierce = 1, BlastRadius = 15, BlastDamage = 45 }
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

-- Meta progression ("МАСТЕРСКАЯ"): small, choice-widening perks bought with СКРАП.
Defs.Perks = {
	PK_VITALITY = { id = "PK_VITALITY", name = "ЖИВУЧЕСТЬ", icon = "heart", color = rgb(255, 90, 110), max = 5, costs = { 60, 110, 170, 240, 320 }, stat = function(r: number): string return `+{r * 8} здоровья` end },
	PK_MAGNET = { id = "PK_MAGNET", name = "МАГНИТ", icon = "magnet", color = rgb(84, 238, 255), max = 3, costs = { 50, 100, 160 }, stat = function(r: number): string return `+{r * 20}% радиус сбора` end },
	PK_REROLL = { id = "PK_REROLL", name = "ПЕРЕБРОС", icon = "reroll", color = rgb(255, 200, 60), max = 3, costs = { 80, 150, 240 }, stat = function(r: number): string return `{r} переброс карт за забег` end },
	PK_BANISH = { id = "PK_BANISH", name = "ИЗГНАНИЕ", icon = "banish", color = rgb(255, 80, 80), max = 2, costs = { 120, 220 }, stat = function(r: number): string return `{r} изгнание карт за забег` end },
	PK_DASH = { id = "PK_DASH", name = "ФОРСАЖ", icon = "dash", color = rgb(110, 255, 210), max = 3, costs = { 70, 130, 200 }, stat = function(r: number): string return `−{r * 8}% перезарядка рывка` end },
	PK_OVERDRIVE = { id = "PK_OVERDRIVE", name = "РЕАКТОР", icon = "sun", color = rgb(255, 180, 60), max = 3, costs = { 70, 130, 200 }, stat = function(r: number): string return `+{r * 25} перегрузки на старте` end },
	PK_INSIGHT = { id = "PK_INSIGHT", name = "ПРОЗРЕНИЕ", icon = "eye", color = rgb(190, 120, 255), max = 1, costs = { 400 }, stat = function(r: number): string return "4 карты на выбор" end },
	PK_SALVAGE = { id = "PK_SALVAGE", name = "УТИЛЬ", icon = "gear", color = rgb(200, 210, 220), max = 3, costs = { 90, 160, 250 }, stat = function(r: number): string return `+{r * 12}% скрапа` end },
}
Defs.PerkOrder = { "PK_VITALITY", "PK_MAGNET", "PK_REROLL", "PK_BANISH", "PK_DASH", "PK_OVERDRIVE", "PK_INSIGHT", "PK_SALVAGE" }

-- Scrap reward for a finished run. lines = { {icon, amount}, ... } for the results screen.
function Defs.runReward(result: any, threat: number, salvageRank: number)
	local lines = {}
	local base = math.floor(result.kills / 12)
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
