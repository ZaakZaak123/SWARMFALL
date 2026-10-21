--!nonstrict
-- Persistent player profile (СКРАП, perks, unlocks). Server-only, DataStore-backed with retries.
-- If the DataStore is unavailable (e.g. Studio without API access) the profile runs in session-only
-- "offline" mode: nothing is ever written, so a failed load can never wipe real data.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Maps = require(Shared:WaitForChild("Maps"))

local Profile = {}

local STORE_NAME = "SWARMFALL_Profile_v1"
local VERSION = 1
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
		threat = { MAP_REACTOR_YARD = 1 }, -- max unlocked threat per map; absent = map locked
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
	return { scrap = d.scrap, perks = d.perks, weapons = d.weapons, threat = d.threat, runs = d.runs, wins = d.wins, offline = e.offline }
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
	if not d or not def or d.weapons[id] or d.scrap < def.cost then
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

function Profile.maxThreat(player: Player, mapId: string): number
	local d = Profile.get(player)
	return d and d.threat[mapId] or 0
end

-- Idempotent per runId. Returns the reward breakdown for the results screen.
function Profile.grantRun(player: Player, runId: string, result, mapId: string, threat: number)
	local d = Profile.get(player)
	if not d then
		return nil
	end
	local reward = Defs.runReward(result, threat, d.perks.PK_SALVAGE or 0)
	if d.lastRun == runId then
		return reward
	end
	d.lastRun = runId
	d.scrap += reward.total
	d.runs += 1
	d.kills += result.kills
	local unlocked = {}
	if result.victory then
		d.wins += 1
		local cur = d.threat[mapId] or 1
		if threat >= cur and cur < Defs.Threat.Max then
			d.threat[mapId] = cur + 1
			table.insert(unlocked, { "threat", cur + 1 })
		end
		local map = Maps.get(mapId)
		local nextId = Maps.Order[map.index + 1]
		if nextId and not d.threat[nextId] then
			d.threat[nextId] = 1
			table.insert(unlocked, { "map", nextId })
		end
	end
	reward.unlocked = unlocked
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
