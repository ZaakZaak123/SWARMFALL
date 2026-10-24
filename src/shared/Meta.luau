--!strict
-- SPOREFALL long-term meta (DD-037…DD-041): the outpost around our extractor, the siege ladder, the
-- player's own swarm (DNA, strains, mutations), asynchronous raids on other players' outposts, daily
-- anomalies. Pure data + rules: the server validates every change here and the tests run it in Lune.
-- Numbers are TUNABLE.

local Meta = {}

-- Outpost ---------------------------------------------------------------------------------------------
-- Ten sockets around the extractor (world coords, extractor at 0,0): four inner, six outer.
Meta.Sockets = {}
for i, deg in { 45, 135, 225, 315 } do
	local a = math.rad(deg)
	Meta.Sockets[i] = { x = math.cos(a) * 17, z = math.sin(a) * 17, ring = 1 }
end
for i, deg in { 0, 60, 120, 180, 240, 300 } do
	local a = math.rad(deg)
	Meta.Sockets[4 + i] = { x = math.cos(a) * 30, z = math.sin(a) * 30, ring = 2 }
end
Meta.SocketCount = #Meta.Sockets

export type StructureDef = {
	id: string,
	name: string,
	short: string,
	text: string,
	icon: string,
	color: Color3,
	kind: string, -- "turret" | "chain" | "mortar" | "slow" | "acid" | "shield" | "harvest"
	cost: { number },
	dna: { number }, -- runner DNA needed per level (0 = none)
	range: number?,
	every: { number }?, -- seconds between shots / pulses
	damage: { number }?,
	targets: { number }?,
	radius: { number }?,
	slow: { number }?,
	shield: { number }?,
	perHour: { number }?,
	enemyIndex: number?, -- hostile version in raids (Defs.Enemies index)
	unlock: string, -- operation whose first win opens it
}

local rgb = Color3.fromRGB
Meta.Structures = {
	STING = {
		id = "STING",
		name = "ЖАЛО",
		short = "Автотурель",
		text = "Быстрые выстрелы по ближайшей цели.",
		icon = "crosshair",
		color = rgb(255, 196, 70),
		kind = "turret",
		cost = { 120, 350, 700 },
		dna = { 0, 0, 10 },
		range = 34,
		every = { 0.34, 0.27, 0.21 },
		damage = { 9, 12, 16 },
		enemyIndex = 13,
		unlock = "O01", -- the first hunt's loot buys it (DD-052)
	},
	ARC = {
		id = "ARC",
		name = "РАЗРЯДНИК",
		short = "Цепная молния",
		text = "Разряд перескакивает по толпе.",
		icon = "chain",
		color = rgb(86, 238, 230),
		kind = "chain",
		cost = { 300, 650, 1200 },
		dna = { 0, 0, 15 },
		range = 30,
		every = { 1.6, 1.3, 1.0 },
		damage = { 26, 36, 50 },
		targets = { 3, 4, 6 },
		enemyIndex = 14,
		unlock = "O02",
	},
	MORTAR = {
		id = "MORTAR",
		name = "СПОРОМЁТ",
		short = "Навесной залп",
		text = "Медленно, далеко и по площади.",
		icon = "boom",
		color = rgb(255, 120, 56),
		kind = "mortar",
		cost = { 400, 800, 1400 },
		dna = { 0, 5, 20 },
		range = 54,
		every = { 2.6, 2.2, 1.8 },
		damage = { 40, 58, 85 },
		radius = { 6, 7, 8.5 },
		enemyIndex = 15,
		unlock = "O03",
	},
	CRYO = {
		id = "CRYO",
		name = "КРИОПОЛЕ",
		short = "Ловушка",
		text = "Замедляет всё, что в него входит.",
		icon = "snow",
		color = rgb(150, 220, 255),
		kind = "slow",
		cost = { 200, 450, 800 },
		dna = { 0, 0, 10 },
		radius = { 7, 8, 10 },
		slow = { 0.35, 0.45, 0.55 },
		unlock = "O03",
	},
	ACID = {
		id = "ACID",
		name = "КИСЛОТНАЯ ЯМА",
		short = "Ловушка",
		text = "Разъедает всех, кто проходит.",
		icon = "drop",
		color = rgb(170, 255, 70),
		kind = "acid",
		cost = { 250, 550, 950 },
		dna = { 0, 0, 10 },
		radius = { 6, 7, 8 },
		damage = { 16, 26, 40 }, -- per second
		unlock = "O03",
	},
	SHIELD = {
		id = "SHIELD",
		name = "ЩИТ-ПИЛОН",
		short = "Защита бура",
		text = "Раз в 15 секунд закрывает бур щитом.",
		icon = "shield",
		color = rgb(120, 176, 255),
		kind = "shield",
		cost = { 350, 700, 1200 },
		dna = { 0, 0, 15 },
		every = { 15, 15, 15 },
		shield = { 60, 100, 160 },
		enemyIndex = 16,
		unlock = "O04",
	},
	HARVEST = {
		id = "HARVEST",
		name = "СБОРЩИК",
		short = "Утиль, пока тебя нет",
		text = "Добывает утиль даже офлайн (до 12 часов).",
		icon = "star",
		color = rgb(255, 86, 198),
		kind = "harvest",
		cost = { 200, 450, 900 },
		dna = { 0, 0, 0 },
		perHour = { 40, 70, 110 },
		unlock = "O02",
	},
}
Meta.StructureOrder = { "STING", "ARC", "MORTAR", "CRYO", "ACID", "SHIELD", "HARVEST" }
Meta.HarvestCapHours = 12
Meta.SellRefund = 0.5
-- Home (DD-057) ----------------------------------------------------------------------------------------
-- The shelter in the green grove: a safe place, far from the crater. It grows through prepared spots
-- that are restored once and stay restored (no upkeep, no decay). Each opens something real.
-- unlock = the hunt whose first win makes the spot available; free = restored by that win itself.
Meta.HomeOrigin = Vector3.new(0, 0, 1500) -- world position of the shelter's courtyard centre
Meta.HomeOrder = { "GENERATOR", "WORKBENCH", "RADIO", "LAB", "GARDEN" }
Meta.Home = {
	GENERATOR = { id = "GENERATOR", name = "ГЕНЕРАТОР", text = "Свет в убежище и прожекторы во дворе.", icon = "sun", cost = 0, unlock = "O01", free = true },
	WORKBENCH = { id = "WORKBENCH", name = "МАСТЕРСКАЯ", text = "Верстак для оборудования бура: турели, ловушки, щиты.", icon = "gear", cost = 120, unlock = "O01" },
	RADIO = { id = "RADIO", name = "РАДИОСТАНЦИЯ", text = "Ловит сигналы роя у бура: открывает оборону бура по уровням.", icon = "coil", cost = 250, unlock = "O02" },
	LAB = { id = "LAB", name = "ЛАБОРАТОРИЯ", text = "Резервуар с образцами роя: исследования видов и свой рой.", icon = "hive", cost = 400, unlock = "O03" },
	GARDEN = { id = "GARDEN", name = "ОГОРОД", text = "Грядки, гирлянды и скамья: в убежище становится уютно.", icon = "heart", cost = 300, unlock = "O02" },
}

-- Onboarding (DD-052): the socket the first turret goes to (inner ring, south-east: in view from the base
-- spawn) and the payout of «Первый натиск».
Meta.FirstSocket = 4
Meta.StrikeReward = 40

-- Hostile turrets in raids hit players this much softer than they hit the swarm.
Meta.RaidTurretPlayerMult = 0.3

-- Swarm (DNA, strains, mutations) ----------------------------------------------------------------------
-- DNA is earned from lifetime personal kills of a species (profile `research`): kills / per.
Meta.Species = {
	EN_RUNNER = { per = 20, unlock = 5, points = 1, name = "БЕГУН" },
	EN_STALKER = { per = 5, unlock = 8, points = 3, name = "ПРЫГУН" },
	EN_SPITTER = { per = 5, unlock = 8, points = 3, name = "ПЛЕВУН" },
	EN_BOMBER = { per = 4, unlock = 8, points = 3, name = "ВЗРЫВУН" },
	EN_BULWARK = { per = 2, unlock = 12, points = 6, name = "БРОНЕНОСЕЦ" },
}
Meta.SpeciesOrder = { "EN_RUNNER", "EN_STALKER", "EN_SPITTER", "EN_BOMBER", "EN_BULWARK" }

Meta.Mutations = {
	CARAPACE = { name = "ПАНЦИРЬ", text = "+60% здоровья, чуть медленнее", icon = "shield", color = rgb(255, 176, 60), dna = 6 },
	FRENZY = { name = "БЕШЕНСТВО", text = "+35% скорости", icon = "dash", color = rgb(255, 80, 120), dna = 6 },
	ACID_BLOOD = { name = "КИСЛОТНАЯ КРОВЬ", text = "Оставляет лужу кислоты при гибели", icon = "drop", color = rgb(170, 255, 70), dna = 8 },
	VOLATILE = { name = "НЕСТАБИЛЬНОСТЬ", text = "Взрывается при гибели", icon = "boom", color = rgb(255, 140, 50), dna = 8 },
	REGEN = { name = "РЕГЕНЕРАЦИЯ", text = "Затягивает раны: 3% здоровья в секунду", icon = "plus", color = rgb(110, 255, 140), dna = 10 },
}
Meta.MutationOrder = { "CARAPACE", "FRENZY", "ACID_BLOOD", "VOLATILE", "REGEN" }
Meta.MaxStrains = 3
Meta.MaxMutationsPerStrain = 2
Meta.WavePoints = 24 -- budget of one brood wave in a raid

function Meta.dnaEarned(kind: string, kills: number?): number
	local s = Meta.Species[kind]
	if not s then
		return 0
	end
	return math.floor((kills or 0) / s.per)
end

-- data: profile table (research, dnaSpent)
function Meta.dna(data, kind: string): number
	return Meta.dnaEarned(kind, data.research and data.research[kind]) - ((data.dnaSpent or {})[kind] or 0)
end

-- Units of one strain per brood wave.
function Meta.strainUnits(strain): number
	local s = Meta.Species[strain.kind]
	if not s then
		return 0
	end
	local per = s.points + #(strain.muts or {})
	return math.max(1, math.floor(Meta.WavePoints / Meta.MaxStrains / per + 0.5))
end

-- Mutation effects applied to a spawned enemy record (server).
function Meta.applyMutations(e, muts: { string }?)
	if not muts or #muts == 0 then
		return
	end
	e.muts = {}
	for _, m in muts do
		e.muts[m] = true
	end
	e.mutant = true
	if e.muts.CARAPACE then
		e.hp *= 1.6
		e.maxHp = e.hp
		e.speedMult = (e.speedMult or 1) * 0.9
	end
	if e.muts.FRENZY then
		e.speedMult = (e.speedMult or 1) * 1.35
	end
end

-- Anomalies (one per UTC day) ----------------------------------------------------------------------
Meta.Anomalies = {
	{ id = "ACID_RAIN", name = "КИСЛОТНЫЙ ДОЖДЬ", text = "С неба капает кислота — не стой на месте", color = rgb(170, 255, 70), icon = "drop", acidRain = true, reward = 1.2 },
	{ id = "FERTILE", name = "ПЛОДОВИТЫЙ РОЙ", text = "Врагов на треть больше, опыта тоже", color = rgb(255, 196, 70), icon = "users", spawn = 1.3, xp = 1.3, reward = 1.15 },
	{ id = "GLASS", name = "СТЕКЛЯННЫЕ ПАНЦИРИ", text = "Враги хрупкие, но их вдвое больше", color = rgb(150, 220, 255), icon = "burst", hp = 0.6, spawn = 1.7, reward = 1.15 },
	{ id = "ELITE", name = "ЭЛИТНАЯ СТАЯ", text = "Особых тварей больше обычного", color = rgb(255, 80, 120), icon = "elite", specials = 1.8, reward = 1.25 },
	{ id = "HASTE", name = "ГОЛОДНЫЙ РОЙ", text = "Рой быстрее на 20%", color = rgb(255, 120, 56), icon = "dash", speed = 1.2, reward = 1.2 },
	{ id = "BLOOD_MOON", name = "КРОВАВАЯ ЛУНА", text = "Больше утиля за всё", color = rgb(255, 86, 198), icon = "star", reward = 1.4 },
}

function Meta.dayIndex(now: number): number
	return math.floor(now / 86400)
end

function Meta.anomalyFor(day: number)
	local n = #Meta.Anomalies
	return Meta.Anomalies[(day * 7919 + 3) % n + 1]
end

-- Squads earn more: playing together is the point (DD-040).
function Meta.squadMult(players: number): number
	return 1 + 0.1 * math.max(0, math.min(players, 4) - 1)
end

-- Siege ladder ---------------------------------------------------------------------------------------
function Meta.siegeReward(level: number, victory: boolean): number
	return if victory then 120 + 35 * level else 25 + 5 * level
end

function Meta.siegeScale(level: number): (number, number)
	-- enemy hp, spawn rate
	return 1 + 0.14 * (level - 1), 1 + 0.07 * (level - 1)
end

-- Raids ------------------------------------------------------------------------------------------------
Meta.StartRating = 1000

function Meta.raidReward(targetRating: number, victory: boolean): number
	return if victory then math.floor(160 + math.max(0, targetRating - 900) * 0.12) else 30
end

-- Rating change for attacker (win/lose) and defender (inverse), Elo-like with K = 32.
function Meta.ratingDelta(attacker: number, defender: number, attackerWon: boolean): number
	local expect = 1 / (1 + 10 ^ ((defender - attacker) / 400))
	local score = if attackerWon then 1 else 0
	return math.floor(32 * (score - expect) + 0.5)
end

Meta.DefenseReward = 40 -- xenite to the owner for every raid their outpost stopped

-- Outpost validation & power ---------------------------------------------------------------------------
-- slots: { [socket] = { id = string, lvl = number } } -> sanitized copy
function Meta.cleanOutpost(slots): { [number]: { id: string, lvl: number } }
	local out = {}
	if type(slots) ~= "table" then
		return out
	end
	for i = 1, Meta.SocketCount do
		local s = slots[i] or slots[tostring(i)]
		if type(s) == "table" and Meta.Structures[s.id] and type(s.lvl) == "number" then
			out[i] = { id = s.id, lvl = math.clamp(math.floor(s.lvl), 1, 3) }
		end
	end
	return out
end

function Meta.cleanBrood(strains): { { kind: string, muts: { string } } }
	local out = {}
	if type(strains) ~= "table" then
		return out
	end
	for i = 1, Meta.MaxStrains do
		local s = strains[i]
		if type(s) == "table" and Meta.Species[s.kind] then
			local muts = {}
			for _, m in (if type(s.muts) == "table" then s.muts else {}) do
				if Meta.Mutations[m] and not table.find(muts, m) and #muts < Meta.MaxMutationsPerStrain then
					table.insert(muts, m)
				end
			end
			table.insert(out, { kind = s.kind, muts = muts })
		end
	end
	return out
end

-- Defence rating of an outpost (matchmaking / UI): sum of build cost.
function Meta.outpostPower(slots): number
	local p = 0
	for _, s in Meta.cleanOutpost(slots) do
		local def = Meta.Structures[s.id]
		for l = 1, s.lvl do
			p += def.cost[l]
		end
	end
	return p
end

-- Offline harvest since `since` (os.time) at `now`.
function Meta.harvest(slots, since: number, now: number): number
	local hours = math.clamp((now - since) / 3600, 0, Meta.HarvestCapHours)
	local rate = 0
	for _, s in Meta.cleanOutpost(slots) do
		if s.id == "HARVEST" then
			rate += Meta.Structures.HARVEST.perHour[s.lvl]
		end
	end
	return math.floor(rate * hours)
end

-- Rivals ------------------------------------------------------------------------------------------------
-- When the shared pool is empty (new game, Studio, DataStore outage) raids still have targets: rival
-- outposts generated deterministically around the attacker's rating.
local RIVAL_NAMES = { "Гнилой Зуб", "Северный Шрам", "Ржавая Корона", "Тихий Улей", "Последний Рубеж", "Чёрная Жила", "Кислый Ветер", "Костяной Пост" }

function Meta.rival(seed: number, rating: number)
	local function r(n: number): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n
	end
	local tier = math.clamp(math.floor((rating - 800) / 150), 0, 6)
	local slots = {}
	local pool = { "STING", "STING", "ARC", "MORTAR", "CRYO", "ACID", "SHIELD" }
	local count = math.clamp(3 + tier, 3, 9)
	for k = 1, count do
		local socket = (k * 3 + r(10)) % Meta.SocketCount + 1
		while slots[socket] do
			socket = socket % Meta.SocketCount + 1
		end
		slots[socket] = { id = pool[r(#pool) + 1], lvl = math.clamp(1 + r(2) + math.floor(tier / 3), 1, 3) }
	end
	local kinds = { "EN_RUNNER", "EN_STALKER", "EN_SPITTER", "EN_BOMBER", "EN_BULWARK" }
	local strains = {}
	for k = 1, math.clamp(1 + math.floor(tier / 2), 1, 3) do
		local muts = {}
		for _ = 1, math.min(2, r(3)) do
			local m = Meta.MutationOrder[r(#Meta.MutationOrder) + 1]
			if not table.find(muts, m) then
				table.insert(muts, m)
			end
		end
		table.insert(strains, { kind = kinds[math.min(#kinds, 1 + r(2 + tier))], muts = muts })
	end
	return {
		uid = -1 - (seed % 100000),
		name = "Аванпост «" .. RIVAL_NAMES[r(#RIVAL_NAMES) + 1] .. "»",
		rating = math.floor(rating + (r(200) - 100)),
		slots = slots,
		brood = strains,
		rival = true,
	}
end

return Meta
