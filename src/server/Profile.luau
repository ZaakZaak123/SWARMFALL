--!nonstrict
-- Persistent player profile (Ксенит — ключ `scrap`, perks, unlocks). Server-only, DataStore-backed with retries.
-- If the DataStore is unavailable (e.g. Studio without API access) the profile runs in session-only
-- "offline" mode: nothing is ever written, so a failed load can never wipe real data.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Ops = require(Shared:WaitForChild("Ops"))
local Modules = require(Shared:WaitForChild("Modules"))
local Showcase = require(Shared:WaitForChild("Showcase"))
local Meta = require(Shared:WaitForChild("Meta"))

local Profile = {}

local STORE_NAME = "SWARMFALL_Profile_v1"
local VERSION = 3
local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local profiles: { [Player]: any } = {}
local listeners = {}

local function defaults()
	local weapons = {}
	for id, w in Defs.Weapons do
		if w.cost == 0 then
			weapons[id] = true
		end
	end
	return {
		v = VERSION,
		scrap = 0,
		runs = 0,
		wins = 0,
		kills = 0,
		perks = {},
		weapons = weapons,
		threat = { MAP_REACTOR_YARD = 1 }, -- v1: max threat per map (kept for migration)
		ops = { O01 = 1 }, -- max unlocked threat per operation; absent = operation locked
		components = {}, -- unique permanent components, e.g. CMP_STORM_CORE = true
		s01 = false, -- Gravihammer known (first own cast in O01)
		s01Stats = { hits = 0, kills = 0, crowds = 0 }, -- S01 mastery counters (never weapon kills)
		s01Branch = nil, -- chosen specialization "A" | "B" | "C" (from S01 M5)
		mastery = {}, -- weaponId -> personal lethal kills with it (M1–M20)
		research = {}, -- species -> confirmed squad kills (permanent collection)
		tech = {}, -- owned technologies
		forms = {}, -- crafted permanent forms (evolution id -> true)
		equip = {}, -- weapon id -> equipped form id
		lineTrial = 0, -- railgun «Пробой линии» qualified shots
		feats = {}, -- M20 feat counters per weapon: { [weaponId] = { arcKills = n, ... } }
		modules = {}, -- crafted modules (moduleId -> true)
		loadout = {}, -- weapon id -> { core = moduleId?, adapter = moduleId? }
		firstWinGrantUsed = false,
		lastRun = "",
		-- v3 meta (DD-037…): outpost, swarm, raids
		outpost = { slots = {}, siege = 1, best = 0, harvestT = 0 },
		dnaSpent = {}, -- species -> DNA spent
		species = { EN_RUNNER = false }, -- unlocked strain species
		mutations = {}, -- "SPECIES:MUT" -> true (unlocked for that species)
		brood = {}, -- up to 3 strains { kind, muts }
		raid = {
			rating = Meta.StartRating,
			wins = 0,
			losses = 0,
			defWins = 0,
			defLosses = 0,
			attack = Meta.StartRating,
			held = 0,
			day = 0,
			count = 0,
			pairs = {},
		},
		lastDay = 0,
		likes = 0, -- «Крутой аванпост» marks from visitors (DD-053)
		liked = {}, -- owner user id (string) -> day index of the last like given
		home = {}, -- restored shelter spots (DD-057): id -> true; never lost
		saves = 0, -- allies raised in runs, lifetime (DD-060)
		title = nil, -- chosen earned title id (Showcase.titles)
		tut = {}, -- one-time onboarding beats (DD-052): drill = victory scene seen, strike = first defence done
		trophyLog = {}, -- DD-087: how each boss trophy was won: op -> { t, threat, team, with = { names } }
		mentor = 0, -- DD-088: fights won as a veteran with a newcomer in the squad
		week = { n = 0, defense = 0, research = 0, help = 0 }, -- DD-088: this week's board values
		laurels = {}, -- DD-088: board -> { n = times in the week's top three, last = week index }
	}
end

local function reconcile(data)
	local base = defaults()
	if type(data) ~= "table" then
		return base
	end
	for k, v in base do
		if data[k] == nil then
			data[k] = v
		end
	end
	for id in base.weapons do
		data.weapons[id] = true
	end
	data.threat.MAP_REACTOR_YARD = math.max(1, data.threat.MAP_REACTOR_YARD or 1)
	data.ops.O01 = math.max(1, data.ops.O01 or 1)
	if (data.v or 1) < 2 then
		-- Veterans already had an active skill (overdrive); they start with S01.
		if (data.runs or 0) > 0 then
			data.s01 = true
		end
		-- v1 -> v2: players keep what they unlocked. Beating the yard boss (threat 2+ or depths open)
		-- keeps the Matka run (O04) and the depths run (O06) available.
		if (data.threat.MAP_REACTOR_YARD or 1) >= 2 or data.threat.MAP_HIVE_DEPTHS then
			data.ops.O05 = math.max(data.ops.O05 or 1, data.threat.MAP_REACTOR_YARD or 1)
		end
		if data.threat.MAP_HIVE_DEPTHS then
			data.ops.O07 = math.max(data.ops.O07 or 1, data.threat.MAP_HIVE_DEPTHS)
		end
	end
	-- v5 (DD-061): the old shared raid rating becomes the raider's own; the defence record starts from
	-- the raids already stopped. (Before the defaults below fill `attack` with the start value.)
	if type(data.raid) == "table" and data.raid.attack == nil then
		data.raid.attack = data.raid.rating or Meta.StartRating
		data.raid.held = data.raid.defWins or 0
	end
	-- v3: nested tables may be missing on older saves
	for _, key in { "outpost", "raid" } do
		for k, v in base[key] do
			if data[key][k] == nil then
				data[key][k] = v
			end
		end
	end
	data.outpost.slots = Meta.cleanOutpost(data.outpost.slots)
	-- v4 (DD-057): the shelter. Players who already had what a spot opens get it restored for free, so
	-- nobody loses access to the outpost, the siege or their swarm.
	local won = data.wins_by_op or {}
	if (won.O01 or 0) > 0 then
		data.home.GENERATOR = true
		data.home.WORKBENCH = true -- DD-075: the first sortie restores the workshop too
	end
	if next(data.outpost.slots) ~= nil or (won.O02 or 0) > 0 then
		data.home.WORKBENCH = true
	end
	if (won.O02 or 0) > 0 then
		data.home.RADIO = true -- DD-076: the second sortie brings the radio's antenna home
	end
	if (won.O03 or 0) > 0 then
		data.home.LAB = true -- DD-077: the third sortie brings the sample home
	end
	data.brood = Meta.cleanBrood(data.brood)
	data.v = VERSION
	return data
end

local function retry(fn)
	local delay = 0.5
	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt == 4 then
			return false, result
		end
		task.wait(delay)
		delay *= 2
	end
	return false, nil
end

local function changed(player: Player)
	for _, fn in listeners do
		task.spawn(fn, player)
	end
end

Profile._reconcile = reconcile -- tests

function Profile.onChanged(fn)
	table.insert(listeners, fn)
end

function Profile.load(player: Player)
	local key = "u_" .. player.UserId
	local ok, data = false, nil
	if store then
		ok, data = retry(function()
			return store:GetAsync(key)
		end)
	end
	if not player.Parent then
		return
	end
	local entry = { data = reconcile(if ok then data else nil), offline = not ok, dirty = false, key = key }
	if not ok then
		warn(`[SWARMFALL] profile offline for {player.Name}: {tostring(data)}`)
	end
	profiles[player] = entry
	changed(player)
end

function Profile.get(player: Player)
	local e = profiles[player]
	return e and e.data
end

function Profile.save(player: Player)
	local e = profiles[player]
	if not e or e.offline or not e.dirty or not store then
		return
	end
	e.dirty = false
	local snapshot = table.clone(e.data)
	local ok, err = retry(function()
		store:UpdateAsync(e.key, function()
			return snapshot
		end)
	end)
	if not ok then
		e.dirty = true
		warn("[SWARMFALL] profile save failed", player.Name, err)
	end
end

local function mark(player: Player)
	local e = profiles[player]
	if e then
		e.dirty = true
	end
	changed(player)
end

-- Public view sent to the owning client.
function Profile.public(player: Player)
	local e = profiles[player]
	if not e then
		return nil
	end
	local d = e.data
	return {
		scrap = d.scrap,
		perks = d.perks,
		weapons = d.weapons,
		threat = d.threat,
		ops = d.ops,
		components = d.components,
		s01 = d.s01,
		s01Stats = d.s01Stats,
		s01Branch = d.s01Branch,
		mastery = d.mastery,
		research = d.research,
		tech = d.tech,
		forms = d.forms,
		equip = d.equip,
		modules = d.modules,
		loadout = d.loadout,
		winsByOp = d.wins_by_op or {},
		lineTrial = d.lineTrial,
		feats = d.feats,
		blueprints = (function()
			local out = {}
			for wid in Defs.Blueprints do
				out[wid] = Profile.hasBlueprint(player, wid)
			end
			return out
		end)(),
		runs = d.runs,
		wins = d.wins,
		offline = e.offline,
		-- meta
		features = Profile.features(d),
		outpost = {
			slots = d.outpost.slots,
			siege = d.outpost.siege,
			best = d.outpost.best,
			harvest = Meta.harvest(d.outpost.slots, d.outpost.harvestT, os.time()),
			harvestT = d.outpost.harvestT,
		},
		dna = (function()
			local out = {}
			for _, kind in Meta.SpeciesOrder do
				out[kind] = Meta.dna(d, kind)
			end
			return out
		end)(),
		species = d.species,
		mutations = d.mutations,
		brood = d.brood,
		raid = d.raid,
		raidLog = e.raidLog,
		tut = d.tut,
		home = d.home,
		saves = d.saves,
		title = d.title,
		trophyLog = d.trophyLog,
		mentor = d.mentor,
		week = Profile.thisWeek(d),
		laurels = d.laurels,
	}
end

function Profile.perkRank(player: Player, id: string): number
	local d = Profile.get(player)
	return d and d.perks[id] or 0
end

function Profile.buyPerk(player: Player, id: string): boolean
	local d = Profile.get(player)
	local def = Defs.Perks[id]
	if not d or not def then
		return false
	end
	local rank = d.perks[id] or 0
	local cost = def.costs[rank + 1]
	if not cost or d.scrap < cost then
		return false
	end
	d.scrap -= cost
	d.perks[id] = rank + 1
	mark(player)
	return true
end

function Profile.buyWeapon(player: Player, id: string): boolean
	local d = Profile.get(player)
	local def = Defs.Weapons[id]
	if not d or not def or d.weapons[id] or d.scrap < def.cost or not Profile.hasBlueprint(player, id) then
		return false
	end
	d.scrap -= def.cost
	d.weapons[id] = true
	mark(player)
	return true
end

function Profile.ownsWeapon(player: Player, id: string): boolean
	local d = Profile.get(player)
	return d ~= nil and d.weapons[id] == true
end

function Profile.maxThreat(player: Player, opId: string): number
	local d = Profile.get(player)
	return d and d.ops[opId] or 0
end

-- Blueprint: first win of the story operation (Defs.Blueprints). An operation that does not exist yet
-- in this build is not a gate (DD-008), so weapons stay obtainable while the campaign is built.
function Profile.hasBlueprint(player: Player, weaponId: string): boolean
	local d = Profile.get(player)
	local opId = Defs.Blueprints[weaponId]
	if not d or not opId then
		return d ~= nil
	end
	if not (Ops :: any)[opId] then
		return true
	end
	return (d.ops[opId] or 0) >= 2 or (d.wins_by_op and d.wins_by_op[opId] or 0) > 0
end

-- Modules (D03 §3): craft once (mastery gate + previous tier of the same branch + Ксенит), then equip as
-- CORE or ADAPTER. Owned and equipped are separate states.
function Profile.craftModule(player: Player, id: string): boolean
	local d = Profile.get(player)
	local m = Modules.get(id)
	if not d or not m or d.modules[id] or not d.weapons[m.weapon] or d.scrap < m.cost then
		return false
	end
	if Defs.masteryRank(m.weapon, d.mastery[m.weapon] or 0) < m.mastery then
		return false
	end
	if m.tier > 1 then
		local prev = string.format("MOD_%s_%s%d", m.weapon:sub(3), m.branch, m.tier - 1)
		if not d.modules[prev] then
			return false
		end
	end
	d.scrap -= m.cost
	d.modules[id] = true
	-- First module of a weapon goes straight into the CORE slot.
	local lo = d.loadout[m.weapon] or {}
	d.loadout[m.weapon] = lo
	if not lo.core then
		lo.core = id
	end
	mark(player)
	task.spawn(Profile.save, player)
	return true
end

-- slot = "core" | "adapter"; id = "" clears the slot.
function Profile.equipModule(player: Player, weaponId: string, slot: string, id: string): boolean
	local d = Profile.get(player)
	if not d or not Defs.Weapons[weaponId] or (slot ~= "core" and slot ~= "adapter") then
		return false
	end
	local lo = table.clone(d.loadout[weaponId] or {})
	if id == "" then
		lo[slot] = nil
	else
		if not d.modules[id] then
			return false
		end
		lo[slot] = id
		-- Moving a module between slots frees the other slot.
		local other = if slot == "core" then "adapter" else "core"
		if lo[other] == id then
			lo[other] = nil
		end
	end
	if not Modules.validLoadout(weaponId, lo.core, lo.adapter) then
		return false
	end
	d.loadout[weaponId] = lo
	mark(player)
	return true
end

function Profile.loadoutFor(player: Player, weaponId: string)
	local d = Profile.get(player)
	local lo = d and d.loadout[weaponId]
	if not lo then
		return nil
	end
	local core = if lo.core and d.modules[lo.core] then lo.core else nil
	local adapter = if lo.adapter and d.modules[lo.adapter] then lo.adapter else nil
	if not Modules.validLoadout(weaponId, core, adapter) then
		return nil
	end
	return { core = core, adapter = adapter }
end

-- S01 specialization: one main branch, free to switch between operations once M5 is reached.
function Profile.setS01Branch(player: Player, branch: string): boolean
	local d = Profile.get(player)
	if not d or not d.s01 or not Defs.S01Branches[branch] then
		return false
	end
	if Defs.s01Rank(Defs.s01Points(d.s01Stats)) < Defs.S01Mastery.BranchAt then
		return false
	end
	d.s01Branch = branch
	mark(player)
	return true
end

function Profile.s01Spec(player: Player)
	local d = Profile.get(player)
	if not d or not d.s01 or not d.s01Branch then
		return nil
	end
	local tier = Defs.s01Tier(Defs.s01Rank(Defs.s01Points(d.s01Stats)))
	if tier < 1 then
		return nil
	end
	return { branch = d.s01Branch, tier = tier }
end

-- Starter technologies: available after the first O01 win (D03 §6).
function Profile.buyTech(player: Player, id: string): boolean
	local d = Profile.get(player)
	local def = Defs.Tech[id]
	if not d or not def or d.tech[id] or d.scrap < def.cost then
		return false
	end
	if not ((d.wins_by_op and (d.wins_by_op.O01 or 0) > 0) or (d.ops.O01 or 1) >= 2) then
		return false
	end
	d.scrap -= def.cost
	d.tech[id] = true
	mark(player)
	task.spawn(Profile.save, player)
	return true
end

-- Permanent form: owned weapon + M10 with it + its component + Ксенит, crafted once.
function Profile.formStatus(player: Player, evoId: string)
	local d = Profile.get(player)
	local evo = Defs.Evolutions[evoId]
	if not d or not evo then
		return nil
	end
	local kills = d.mastery[evo.weapon] or 0
	local rank = Defs.masteryRank(evo.weapon, kills)
	if evo.m20 then
		local f = d.feats[evo.weapon] or {}
		return {
			crafted = d.forms[evoId] == true,
			owned = d.weapons[evo.weapon] == true,
			mastery = rank >= 20,
			component = (f[evo.feat.counter] or 0) >= evo.feat.need,
			afford = d.scrap >= evo.cost,
		}
	end
	return {
		crafted = d.forms[evoId] == true,
		owned = d.weapons[evo.weapon] == true,
		mastery = rank >= Defs.FormMastery,
		component = d.components[evo.component] == true,
		afford = d.scrap >= evo.cost,
	}
end

function Profile.craftForm(player: Player, evoId: string): boolean
	local st = Profile.formStatus(player, evoId)
	if not st or st.crafted or not st.owned or not st.mastery or not st.component or not st.afford then
		return false
	end
	local d = Profile.get(player)
	local evo = Defs.Evolutions[evoId]
	d.scrap -= evo.cost
	d.forms[evoId] = true
	d.equip[evo.weapon] = evoId
	mark(player)
	task.spawn(Profile.save, player)
	return true
end

-- evoId = "" unequips (play the standard form); owned and equipped are separate states.
function Profile.equipForm(player: Player, weaponId: string, evoId: string): boolean
	local d = Profile.get(player)
	if not d or not Defs.Weapons[weaponId] then
		return false
	end
	if evoId == "" then
		d.equip[weaponId] = nil
	elseif d.forms[evoId] and Defs.Evolutions[evoId] and Defs.Evolutions[evoId].weapon == weaponId then
		d.equip[weaponId] = evoId
	else
		return false
	end
	mark(player)
	return true
end

function Profile.equippedForm(player: Player, weaponId: string): string?
	local d = Profile.get(player)
	local id = d and d.equip[weaponId]
	return if id and d.forms[id] then id else nil
end

-- Idempotent per runId. Returns the reward breakdown for the results screen.
-- Meta (DD-037…DD-041) -----------------------------------------------------------------------------------
-- Modes open one at a time with the story (Progressive Discovery).
function Profile.features(d)
	local won = d.wins_by_op or {}
	-- DD-052: the outpost (building) opens with the first hunt won, the siege ladder with the second.
	-- DD-057: what a restored shelter spot opens. The workshop builds the drill's defences, the radio
	-- picks up the swarm at the drill (siege ladder; the first defence is open with the first turret),
	-- the lab holds the samples (own swarm).
	local home = d.home or {}
	local hasTurret = d.outpost ~= nil and next(d.outpost.slots or {}) ~= nil
	return {
		outpost = (won.O01 or 0) > 0 and home.WORKBENCH == true,
		siege = hasTurret and home.RADIO == true, -- the first defence runs from its goal; the tab waits for the radio
		siegeLadder = home.RADIO == true,
		swarm = (won.O03 or 0) > 0 and home.LAB == true,
		raids = (won.O04 or 0) > 0,
	}
end

local function structureUnlocked(d, def): boolean
	return ((d.wins_by_op or {})[def.unlock] or 0) > 0
end

local function spend(d, xenite: number, dnaKind: string?, dna: number?): boolean
	if d.scrap < xenite then
		return false
	end
	if dnaKind and (dna or 0) > 0 and Meta.dna(d, dnaKind) < dna then
		return false
	end
	d.scrap -= xenite
	if dnaKind and (dna or 0) > 0 then
		d.dnaSpent[dnaKind] = (d.dnaSpent[dnaKind] or 0) + dna
	end
	return true
end

-- Collect the harvester first: building or upgrading restarts the clock, nothing earned is lost.
function Profile.collectHarvest(player: Player): number
	local d = Profile.get(player)
	if not d then
		return 0
	end
	local amount = Meta.harvest(d.outpost.slots, d.outpost.harvestT, os.time())
	d.outpost.harvestT = os.time()
	if amount > 0 then
		d.scrap += amount
	end
	mark(player)
	return amount
end

-- Wear an earned title (DD-060): only one the profile actually holds.
function Profile.setTitle(player: Player, id: string): boolean
	local d = Profile.get(player)
	if not d then
		return false
	end
	for _, t in Showcase.titles(d) do
		if t.id == id then
			d.title = id
			mark(player)
			return true
		end
	end
	return false
end

-- Restore a shelter spot (DD-057): once, for its cost, after its hunt is won.
function Profile.restore(player: Player, id: string): boolean
	local d = Profile.get(player)
	local def = Meta.Home[id]
	if not d or not def or d.home[id] or def.free then
		return false
	end
	if ((d.wins_by_op or {})[def.unlock] or 0) == 0 or d.scrap < def.cost then
		return false
	end
	d.scrap -= def.cost
	d.home[id] = true
	mark(player)
	return true
end

-- «Крутой аванпост» (DD-053): one mark per visitor per owner per day; never your own.
function Profile.like(liker: Player, owner: Player, day: number): boolean
	local a, b = Profile.get(liker), Profile.get(owner)
	if not a or not b or liker == owner then
		return false
	end
	local key = tostring(owner.UserId)
	if a.liked[key] == day then
		return false
	end
	for k, v in a.liked do
		if v ~= day then
			a.liked[k] = nil -- only today's marks matter
		end
	end
	a.liked[key] = day
	b.likes = (b.likes or 0) + 1
	mark(liker)
	mark(owner)
	return true
end

-- One-time onboarding flags the client may set (the victory scene was watched).
local CLIENT_TUT = {
	drill = true,
	intro = true,
	go_O02 = true,
	home_O02 = true,
	go_O03 = true,
	home_O03 = true,
	go_O04 = true,
	home_O04 = true,
	go_O05 = true,
	home_O05 = true,
	go_O06 = true,
	home_O06 = true,
	go_O07 = true,
	home_O07 = true,
} -- story scenes watched (DD-075/076)
function Profile.markTut(player: Player, key: string): boolean
	local d = Profile.get(player)
	if not d or not CLIENT_TUT[key] or d.tut[key] then
		return false
	end
	d.tut[key] = true
	mark(player)
	return true
end

function Profile.build(player: Player, slot: number, id: string): boolean
	local d = Profile.get(player)
	local def = Meta.Structures[id]
	if not d or not def or not Profile.features(d).outpost or not Meta.Sockets[slot] or d.outpost.slots[slot] then
		return false
	end
	if not structureUnlocked(d, def) or not spend(d, def.cost[1], "EN_RUNNER", def.dna[1]) then
		return false
	end
	if id == "HARVEST" then
		Profile.collectHarvest(player)
	end
	d.outpost.slots[slot] = { id = id, lvl = 1 }
	mark(player)
	return true
end

function Profile.upgrade(player: Player, slot: number): boolean
	local d = Profile.get(player)
	local s = d and d.outpost.slots[slot]
	if not s or s.lvl >= 3 then
		return false
	end
	local def = Meta.Structures[s.id]
	if not spend(d, def.cost[s.lvl + 1], "EN_RUNNER", def.dna[s.lvl + 1]) then
		return false
	end
	if s.id == "HARVEST" then
		Profile.collectHarvest(player)
	end
	s.lvl += 1
	mark(player)
	return true
end

function Profile.sell(player: Player, slot: number): boolean
	local d = Profile.get(player)
	local s = d and d.outpost.slots[slot]
	if not s then
		return false
	end
	if s.id == "HARVEST" then
		Profile.collectHarvest(player)
	end
	local def = Meta.Structures[s.id]
	local spent = 0
	for l = 1, s.lvl do
		spent += def.cost[l]
	end
	d.scrap += math.floor(spent * Meta.SellRefund)
	d.outpost.slots[slot] = nil
	mark(player)
	return true
end

function Profile.unlockSpecies(player: Player, kind: string): boolean
	local d = Profile.get(player)
	local sp = Meta.Species[kind]
	if not d or not sp or not Profile.features(d).swarm or d.species[kind] then
		return false
	end
	if not spend(d, 0, kind, sp.unlock) then
		return false
	end
	d.species[kind] = true
	mark(player)
	return true
end

function Profile.unlockMutation(player: Player, kind: string, mut: string): boolean
	local d = Profile.get(player)
	local m = Meta.Mutations[mut]
	local key = kind .. ":" .. mut
	if not d or not m or not d.species[kind] or d.mutations[key] then
		return false
	end
	if not spend(d, 0, kind, m.dna) then
		return false
	end
	d.mutations[key] = true
	mark(player)
	return true
end

-- strain = { kind, muts } for slot 1..3; nil clears the slot.
function Profile.setStrain(player: Player, index: number, kind: string?, muts: { string }?): boolean
	local d = Profile.get(player)
	if not d or not Profile.features(d).swarm or index < 1 or index > Meta.MaxStrains then
		return false
	end
	local list = table.clone(d.brood)
	if kind == nil then
		table.remove(list, index)
	else
		if not d.species[kind] then
			return false
		end
		local ok = {}
		for _, m in muts or {} do
			if d.mutations[kind .. ":" .. m] then
				table.insert(ok, m)
			end
		end
		list[math.min(index, #list + 1)] = { kind = kind, muts = ok }
	end
	d.brood = Meta.cleanBrood(list)
	mark(player)
	return true
end

-- A finished raid on this player's outpost, reported by the attacker's server (Outposts service).
function Profile.applyDefense(player: Player, entries): number
	local d = Profile.get(player)
	if not d then
		return 0
	end
	local gained = 0
	for _, entry in entries do
		-- DD-061: a raid the owner did not take part in never costs them anything — no rating, no
		-- resources, no buildings. A stopped raid adds to the defence record and pays from the system.
		if entry.won then
			d.raid.defLosses += 1
		else
			d.raid.defWins += 1
			d.raid.held = (d.raid.held or 0) + 1
			gained += Meta.DefenseReward
		end
	end
	d.scrap += gained
	mark(player)
	return gained
end

function Profile.setRaidLog(player: Player, log)
	local e = profiles[player]
	if e then
		e.raidLog = log
		changed(player)
	end
end

-- The week's board values, started afresh on a new week (DD-088).
local function thisWeek(d)
	local n = Meta.weekIndex(os.time())
	if type(d.week) ~= "table" or d.week.n ~= n then
		d.week = { n = n, defense = 0, research = 0, help = 0 }
	end
	return d.week
end
Profile.thisWeek = thisWeek

-- A place in last week's top three (DD-088): once per board and week.
function Profile.addLaurel(player: Player, board: string, week: number): boolean
	local d = Profile.get(player)
	if not d or not table.find(Meta.WeeklyBoards, board) then
		return false
	end
	local l = d.laurels[board] or { n = 0, last = -1 }
	if l.last >= week then
		return false
	end
	d.laurels[board] = { n = l.n + 1, last = week }
	mark(player)
	return true
end

-- extra (DD-088): { mentor = { newcomer names } } — this veteran won the fight with newcomers.
function Profile.grantRun(player: Player, runId: string, result, opId: string, threat: number, extra)
	local d = Profile.get(player)
	if not d then
		return nil
	end
	local mine = nil
	for _, entry in result.players or {} do
		if entry.id == player.UserId then
			mine = entry
		end
	end
	local reward = Defs.runReward(result, threat, d.perks.PK_SALVAGE or 0, if mine then mine.kills else nil)
	if d.lastRun == runId then
		return d.lastReward or reward
	end
	-- «Первый натиск» (DD-052): a one-time scene with a small fixed payout; won or lost, it is done.
	if opId == "STRIKE" then
		reward = {
			total = Meta.StrikeReward,
			lines = { { if result.victory then "crown" else "timer", Meta.StrikeReward } },
			mult = 1,
		}
		d.tut.strike = true
		d.lastRun = runId
		d.lastReward = reward
		d.scrap += reward.total
		d.kills += result.kills
		mark(player)
		return reward
	end
	-- Mode rewards (DD-038/039): sieges and raids pay by their own rules; anomalies and squads add on top.
	local mode = result.mode or "hunt"
	if mode == "siege" then
		local level = result.siege or 1
		reward.lines = { { if result.victory then "crown" else "timer", Meta.siegeReward(level, result.victory) } }
		reward.total = Meta.siegeReward(level, result.victory)
		if result.victory and level >= (d.outpost.siege or 1) then
			d.outpost.siege = level + 1
			reward.siegeUp = level + 1
		end
		d.outpost.best = math.max(d.outpost.best or 0, if result.victory then level else 0)
	elseif mode == "raid" and result.raid then
		local raid = result.raid
		local s = Meta.settleRaid(d.raid, {
			victory = result.victory,
			uid = raid.uid,
			rival = raid.rival,
			power = raid.power or 0,
			t = raid.t,
			revenge = raid.revenge,
		}, Meta.dayIndex(os.time()), os.time())
		reward.lines = { { if result.victory then "crown" else "timer", s.total } }
		reward.total = s.total
		reward.capped = s.capped
		reward.rating = { delta = s.delta, now = d.raid.attack, unrated = s.unrated }
	end
	local bonus = Meta.squadMult(result.squad or 1)
	local week = thisWeek(d)
	local mentored = result.victory and extra and type(extra.mentor) == "table" and #extra.mentor > 0
	if mentored then
		bonus *= Meta.MentorBonus
		d.mentor = (d.mentor or 0) + 1
		week.help += 3
		reward.mentor = extra.mentor
	end
	if mode == "siege" and result.victory then
		week.defense = math.max(week.defense, result.siege or 1)
	end
	if result.anomaly then
		for _, a in Meta.Anomalies do
			if a.id == result.anomaly then
				bonus *= a.reward
			end
		end
	end
	if bonus > 1.001 then
		reward.total = math.floor(reward.total * bonus + 0.5)
		reward.bonus = bonus
	end
	d.lastRun = runId
	d.scrap += reward.total
	d.runs += 1
	d.kills += result.kills
	local unlocked = {}
	-- Permanent progress is kept on defeat too (D03 §6): mastery, S01, research, components.
	if mine and mine.lineShots and mine.weapon == "W_RAILGUN" and d.weapons.W_RAILGUN then
		d.lineTrial = (d.lineTrial or 0) + mine.lineShots
		if d.lineTrial >= Defs.LineTrial.Shots and not d.components.CMP_LINE_BREACH then
			d.components.CMP_LINE_BREACH = true
			table.insert(unlocked, { "component", "CMP_LINE_BREACH" })
		end
	end
	if mine then
		d.saves = (d.saves or 0) + (mine.revives or 0)
		week.help += mine.revives or 0
		local wid = mine.weapon
		local before = Defs.masteryRank(wid, d.mastery[wid] or 0)
		d.mastery[wid] = (d.mastery[wid] or 0) + (mine.weaponKills or 0)
		local after, into, need = Defs.masteryRank(wid, d.mastery[wid])
		if after > before then
			table.insert(unlocked, { "mastery", wid, after })
		end
		reward.progress = { weapon = wid, added = mine.weaponKills or 0, rank = after, into = into, need = need }
		local f = d.feats[wid] or {}
		d.feats[wid] = f
		for k, v in mine.feats or {} do
			f[k] = (f[k] or 0) + v
		end
		-- research is shared by the squad (DD-059); a partial result (left early) only has own kills
		for kind, n in result.species or mine.species or {} do
			local discovered = (d.research[kind] or 0) == 0 and n > 0 and Defs.Research[kind] ~= nil
			local was = Defs.researchStage(kind, d.research[kind] or 0)
			d.research[kind] = (d.research[kind] or 0) + n
			local now = Defs.researchStage(kind, d.research[kind])
			if now > was then
				week.research += now - was
				table.insert(unlocked, { "research", kind, now })
			elseif discovered then
				table.insert(unlocked, { "specimen", kind })
			end
		end
	end
	if mine and mine.s01Unlocked and mine.s01 and mine.s01.casts > 0 then
		if not d.s01 then
			d.s01 = true
			table.insert(unlocked, { "s01", "S01" })
		end
		d.s01Stats.hits += mine.s01.hits
		d.s01Stats.kills += mine.s01.kills
		d.s01Stats.crowds += mine.s01.crowds
	end
	-- Components are earned by the deed (e.g. killing the Core Carrier), win or lose, and are unique.
	for _, id in result.components or {} do
		if not d.components[id] then
			d.components[id] = true
			table.insert(unlocked, { "component", id })
		end
	end
	if result.victory then
		d.wins += 1
		d.wins_by_op = d.wins_by_op or {}
		d.wins_by_op[opId] = (d.wins_by_op[opId] or 0) + 1
		-- DD-087: the trophy remembers when and with whom (shown on its plaque in the grove)
		if (opId == "O01" or opId == "O05" or opId == "O07") and not d.trophyLog[opId] then
			local with = {}
			for _, entry in result.players or {} do
				if entry.id ~= player.UserId and type(entry.name) == "string" and #with < 3 then
					table.insert(with, entry.name)
				end
			end
			d.trophyLog[opId] = { t = os.time(), threat = threat, team = result.squad or 1, with = with }
		end
		-- DD-057: a spot the hunt itself restores (the generator from the first sortie)
		for _, hid in Meta.HomeOrder do
			local hdef = Meta.Home[hid]
			if hdef.free and hdef.unlock == opId and not d.home[hid] then
				d.home[hid] = true
				table.insert(unlocked, { "home", hid })
			end
		end
		-- First-win story components (D03 §3).
		local firstWin = { O06 = "CMP_FLAME_HEART", O07 = "CMP_VOID_HEART" }
		local comp = firstWin[opId]
		if comp and not d.components[comp] then
			d.components[comp] = true
			table.insert(unlocked, { "component", comp })
		end
		local cur = d.ops[opId] or 1
		if threat >= cur and cur < Defs.Threat.Max then
			d.ops[opId] = cur + 1
			table.insert(unlocked, { "threat", cur + 1 })
		end
		for _, nextId in Ops.get(opId).unlocks do
			if (Ops :: any)[nextId] and not d.ops[nextId] then
				d.ops[nextId] = 1
				table.insert(unlocked, { "op", nextId })
			end
		end
	end
	-- First O01 win: top the balance up to one starter technology (only if none is owned yet).
	if result.victory and opId == "O01" and not d.firstWinGrantUsed then
		d.firstWinGrantUsed = true
		local ownsTech = false
		for _, id in Defs.TechOrder do
			if d.tech[id] then
				ownsTech = true
			end
		end
		if not ownsTech and d.scrap < Defs.FirstWinGrant then
			local grant = Defs.FirstWinGrant - d.scrap
			d.scrap += grant
			reward.grant = grant
		end
	end
	reward.unlocked = unlocked
	d.lastReward = reward
	mark(player)
	task.spawn(Profile.save, player)
	return reward
end

Players.PlayerAdded:Connect(function(player)
	Profile.load(player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(Profile.load, player)
end

Players.PlayerRemoving:Connect(function(player)
	Profile.save(player)
	profiles[player] = nil
end)

game:BindToClose(function()
	local threads = {}
	for player in profiles do
		table.insert(threads, task.spawn(Profile.save, player))
	end
	task.wait(if RunService:IsStudio() then 1 else 3)
end)

task.spawn(function()
	while true do
		task.wait(120)
		for player in profiles do
			task.spawn(Profile.save, player)
		end
	end
end)

return Profile
