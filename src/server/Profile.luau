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

local Profile = {}

local STORE_NAME = "SWARMFALL_Profile_v1"
local VERSION = 2
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
		mastery = {}, -- weaponId -> personal lethal kills with it (M1–M20)
		research = {}, -- species -> personal confirmed kills
		tech = {}, -- owned technologies
		forms = {}, -- crafted permanent forms (evolution id -> true)
		equip = {}, -- weapon id -> equipped form id
		lineTrial = 0, -- railgun «Пробой линии» qualified shots
		firstWinGrantUsed = false,
		lastRun = "",
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
			data.ops.O04 = math.max(data.ops.O04 or 1, data.threat.MAP_REACTOR_YARD or 1)
		end
		if data.threat.MAP_HIVE_DEPTHS then
			data.ops.O06 = math.max(data.ops.O06 or 1, data.threat.MAP_HIVE_DEPTHS)
		end
	end
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
		mastery = d.mastery,
		research = d.research,
		tech = d.tech,
		forms = d.forms,
		equip = d.equip,
		lineTrial = d.lineTrial,
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

-- Permanent form: owned weapon + M10 with it + its component + Ксенит, crafted once.
function Profile.formStatus(player: Player, evoId: string)
	local d = Profile.get(player)
	local evo = Defs.Evolutions[evoId]
	if not d or not evo then
		return nil
	end
	local kills = d.mastery[evo.weapon] or 0
	local rank = Defs.masteryRank(evo.weapon, kills)
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
function Profile.grantRun(player: Player, runId: string, result, opId: string, threat: number)
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
		local wid = mine.weapon
		local before = Defs.masteryRank(wid, d.mastery[wid] or 0)
		d.mastery[wid] = (d.mastery[wid] or 0) + (mine.weaponKills or 0)
		local after = Defs.masteryRank(wid, d.mastery[wid])
		if after > before then
			table.insert(unlocked, { "mastery", wid, after })
		end
		for kind, n in mine.species or {} do
			local was = Defs.researchStage(kind, d.research[kind] or 0)
			d.research[kind] = (d.research[kind] or 0) + n
			local now = Defs.researchStage(kind, d.research[kind])
			if now > was then
				table.insert(unlocked, { "research", kind, now })
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
		-- First-win story components (D03 §3).
		local firstWin = { O05 = "CMP_FLAME_HEART", O06 = "CMP_VOID_HEART" }
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
