--!nonstrict
-- The grove's people (DD-087). Who lives on which plot of this settlement (shared/Grove), who is out on
-- a fight (their plot waits for them), the grove's chronicle (shared/Chronicle), «попроситься» requests,
-- quick signals, and the homes of survivors from other groves that stand on free plots: a pool of public
-- showcases (one DataStore key, the latest 48). Without DataStore (Studio) the free plots get a few demo
-- neighbours marked as such, so the grove can be looked at; nothing is written.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Grove = require(Shared:WaitForChild("Grove"))
local Chronicle = require(Shared:WaitForChild("Chronicle"))
local Showcase = require(Shared:WaitForChild("Showcase"))
local Collection = require(Shared:WaitForChild("Collection"))

local Neighbors = {}

local POOL_SIZE = 48
local FEED_SIZE = 12
local ASK_TTL = 60
local IDLE_AFTER = 180

local plots = Grove.newPlots()
local away: { [number]: { op: string, t: number } } = {} -- out on a fight (shown on the held plot's sign)
local seen: { [number]: any } = {} -- user id -> Chronicle summary at the last look
local named: { [number]: string } = {} -- user id -> display name (for held plots and the chronicle)
local shown: { [number]: any } = {} -- user id -> their last showcase (a held plot keeps drawing it)
local everHere: { [number]: boolean } = {}
local feed = {} -- newest first: { t, icon, text, uid, big }
local asks: { [number]: { [number]: number } } = {} -- owner -> asker -> os.clock()
local saidAt: { [number]: number } = {}
local moved: { [number]: { pos: Vector3, t: number } } = {}

local poolStore = nil
pcall(function()
	poolStore = DataStoreService:GetDataStore("TLG_ShelterPool_v1")
end)
local online = poolStore ~= nil and not RunService:IsStudio()
local pool = {} -- showcase entries of survivors from other groves
local poolAt = -1e9
local publishedAt: { [number]: number } = {}

-- Plots -----------------------------------------------------------------------------------------------
function Neighbors.plots()
	return plots
end

-- A hunter arrives on this server: a plot (theirs again, next to a friend, or beside the most people).
function Neighbors.arrive(player: Player): number?
	local friends = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and Grove.plotOf(plots, other.UserId) then
			local ok, yes = pcall(player.IsFriendsWith, player, other.UserId)
			if ok and yes then
				table.insert(friends, other.UserId)
			end
		end
	end
	away[player.UserId] = nil
	named[player.UserId] = player.DisplayName
	return Grove.assign(plots, player.UserId, friends, os.time())
end

-- Gone: out on a fight (hold the plot, show where they are) or out of the game.
function Neighbors.leave(player: Player, fightName: string?)
	local uid = player.UserId
	Grove.release(plots, uid, os.time(), fightName ~= nil)
	if fightName then
		away[uid] = { op = fightName, t = os.time() }
	end
	asks[uid] = nil
	saidAt[uid] = nil
	moved[uid] = nil
end

function Neighbors.plotOf(uid: number): number?
	return Grove.plotOf(plots, uid)
end

-- The frame a survivor's shelter stands in on this server (plot 1 for a lodger).
function Neighbors.frameOf(uid: number): CFrame
	return Grove.frame(Grove.plotOf(plots, uid) or 1)
end

function Neighbors.tick()
	for _, uid in Grove.expire(plots, os.time()) do
		away[uid] = nil
	end
	if online and os.clock() - poolAt > 300 then
		poolAt = os.clock()
		task.spawn(function()
			local ok, list = pcall(poolStore.GetAsync, poolStore, "pool")
			if ok and type(list) == "table" then
				pool = list
			end
		end)
	end
end

-- Movement (for «Отошёл»): call with each survivor's position now and then.
function Neighbors.moved(uid: number, pos: Vector3)
	local m = moved[uid]
	if not m or (m.pos - pos).Magnitude > 2 then
		moved[uid] = { pos = pos, t = os.clock() }
	end
end

function Neighbors.idle(uid: number): boolean
	local m = moved[uid]
	return m ~= nil and os.clock() - m.t > IDLE_AFTER
end

-- Chronicle -------------------------------------------------------------------------------------------
function Neighbors.note(icon: string, text: string, uid: number?, big: boolean?)
	local entry = { t = os.time(), icon = icon, text = text, uid = uid, big = big == true }
	table.insert(feed, 1, entry)
	while #feed > FEED_SIZE do
		table.remove(feed)
	end
	return entry
end

function Neighbors.feed()
	return feed
end

-- Compare a survivor's profile with the last look: new deeds become chronicle lines. The first look on
-- this server only remembers (and greets a newcomer). Returns the new entries.
function Neighbors.look(player: Player, d): { any }
	local uid = player.UserId
	local now = Chronicle.summary(d)
	local before = seen[uid]
	seen[uid] = now
	local out = {}
	if not before then
		if not everHere[uid] then
			everHere[uid] = true
			if not now.won.O01 then
				table.insert(
					out,
					Neighbors.note(
						"users",
						"Новый житель рощи: " .. player.DisplayName .. ". Скажи «Привет!»",
						uid,
						true
					)
				)
			end
		end
		return out
	end
	for _, line in Chronicle.diff(before, now, player.DisplayName) do
		table.insert(out, Neighbors.note(line.icon, line.text, uid, line.big))
	end
	return out
end

function Neighbors.seen(uid: number): boolean
	return seen[uid] ~= nil
end

-- Remember the last showcase (a held plot keeps showing the home while its owner fights).
function Neighbors.remember(uid: number, entry)
	shown[uid] = entry
end

-- Asks and signals ------------------------------------------------------------------------------------
function Neighbors.ask(askerUid: number, ownerUid: number): boolean
	local list = asks[ownerUid] or {}
	asks[ownerUid] = list
	local last = list[askerUid]
	if last and os.clock() - last < 8 then
		return false -- no spamming the same neighbour
	end
	list[askerUid] = os.clock()
	return true
end

function Neighbors.take(ownerUid: number, askerUid: number): boolean
	local list = asks[ownerUid]
	local at = list and list[askerUid]
	if not at or os.clock() - at > ASK_TTL then
		return false
	end
	list[askerUid] = nil
	return true
end

function Neighbors.canSay(uid: number): boolean
	local last = saidAt[uid]
	if last and os.clock() - last < Chronicle.SignalGap then
		return false
	end
	saidAt[uid] = os.clock()
	return true
end

-- Homes from other groves -----------------------------------------------------------------------------
-- A survivor's public showcase goes to the pool now and then (only once there is a home to show).
function Neighbors.publish(player: Player, entry)
	if not online or not entry or not (entry.home and entry.home.GENERATOR) then
		return
	end
	local uid = player.UserId
	if os.clock() - (publishedAt[uid] or -1e9) < 180 then
		return
	end
	publishedAt[uid] = os.clock()
	local snap = table.clone(entry)
	snap.slots = nil -- the drill's defences are not part of the home
	snap.t = os.time()
	task.spawn(function()
		pcall(poolStore.UpdateAsync, poolStore, "pool", function(list)
			list = if type(list) == "table" then list else {}
			for i = #list, 1, -1 do
				if type(list[i]) ~= "table" or list[i].id == uid then
					table.remove(list, i)
				end
			end
			table.insert(list, 1, snap)
			while #list > POOL_SIZE do
				table.remove(list)
			end
			return list
		end)
	end)
end

-- Studio: a few neighbours to look at, clearly demo (no DataStore, nobody real).
local DEMO = {
	{
		name = "Демо · Вера",
		won = { "O01", "O02", "O03", "O04", "O05" },
		home = { "GENERATOR", "WORKBENCH", "RADIO", "LAB", "GARDEN" },
		research = 900,
		siege = 6,
		mastery = 4000,
	},
	{
		name = "Демо · Тимур",
		won = { "O01" },
		home = { "GENERATOR", "WORKBENCH" },
		research = 20,
		siege = 0,
		mastery = 200,
	},
	{
		name = "Демо · Лис",
		won = { "O01", "O02", "O03" },
		home = { "GENERATOR", "WORKBENCH", "RADIO", "LAB" },
		research = 160,
		siege = 2,
		mastery = 1200,
	},
	{
		name = "Демо · Ника",
		won = { "O01", "O02", "O03", "O04", "O05", "O06", "O07" },
		home = { "GENERATOR", "WORKBENCH", "RADIO", "LAB", "GARDEN" },
		research = 6000,
		siege = 12,
		mastery = 9000,
	},
}
local function demoEntries()
	local out = {}
	for i, d in DEMO do
		local prof = {
			wins_by_op = {},
			home = {},
			research = {},
			outpost = { slots = {}, best = d.siege },
			mastery = { W_ARC_RIFLE = d.mastery },
			wins = #d.won * 3,
			likes = i * 3,
			saves = i * 4,
			scrap = d.research * 2,
			raid = {},
		}
		for _, op in d.won do
			prof.wins_by_op[op] = 1
		end
		for _, h in d.home do
			prof.home[h] = true
		end
		for k, kind in Collection.Order do
			prof.research[kind] = math.floor(d.research / k)
		end
		local e = Showcase.build(-1000 - i, d.name, prof, "W_ARC_RIFLE", nil)
		e.slots = nil
		e.demo = true
		table.insert(out, e)
	end
	return out
end

local lastGhosts: { [number]: number } = {} -- user id -> plot of a home from another grove (last look)

-- The plot an absent owner's home stands on here (a home from another grove, or a plot held while the
-- owner fights): ♥ and visits for it go to their guestbook (DD-089).
function Neighbors.awayPlot(uid: number): number?
	if lastGhosts[uid] then
		return lastGhosts[uid]
	end
	for i, pl in plots do
		if pl.uid == uid and pl.away then
			return i
		end
	end
	return nil
end

-- Free plots and what stands on them: { [plot] = entry } for survivors from other groves (or demo).
function Neighbors.ghosts(): { [number]: any }
	local present = {}
	for _, p in Players:GetPlayers() do
		present[p.UserId] = true
	end
	for _, pl in plots do
		if pl.uid then
			present[pl.uid] = true
		end
	end
	local list = if online then pool elseif RunService:IsStudio() then demoEntries() else {}
	-- the free plots nearest to people first: the homes from other groves fill in round the living
	local free = {}
	for i, pl in plots do
		if not pl.uid then
			local near = Grove.Plots
			for j, other in plots do
				if other.uid then
					near = math.min(near, Grove.ringDistance(i, j))
				end
			end
			table.insert(free, { i = i, near = near })
		end
	end
	table.sort(free, function(a, b)
		if a.near ~= b.near then
			return a.near < b.near
		end
		return a.i < b.i
	end)
	local out = {}
	local k = 1
	table.clear(lastGhosts)
	for _, fp in free do
		while list[k] and present[list[k].id] do
			k += 1
		end
		if list[k] then
			local e = table.clone(list[k])
			e.ghost = true
			out[fp.i] = e
			lastGhosts[e.id] = fp.i
			k += 1
		end
	end
	return out
end

-- Fights out of the grove (DD-088) ----------------------------------------------------------------------
-- A squad's server reports its fight now and then (MessagingService, server/Main); the grove keeps the
-- latest word per hunter and the way in (the reserved server's access code, from the launch).
local FIGHT_STALE = 45
local fights: { [number]: any } = {} -- user id -> { host, mode, name, p, result, at }
local ways: { [number]: { code: string, at: number } } = {} -- host user id -> the fight's access code

function Neighbors.launched(hostUid: number, code: string?)
	if code then
		ways[hostUid] = { code = code, at = os.clock() }
	end
end

function Neighbors.progress(data)
	if type(data) ~= "table" or not tonumber(data.host) or type(data.members) ~= "table" then
		return
	end
	local word = {
		host = tonumber(data.host),
		mode = if type(data.mode) == "string" then data.mode else "hunt",
		name = if type(data.name) == "string" then string.sub(data.name, 1, 40) else "бой",
		p = if type(data.p) == "table" then data.p else {},
		result = if data.result == "win" or data.result == "loss" then data.result else nil,
		at = os.clock(),
	}
	for _, uid in data.members do
		if tonumber(uid) then
			fights[tonumber(uid) :: number] = word
		end
	end
end

-- The fight a hunter is in, if the word is fresh.
function Neighbors.fight(uid: number)
	local f = fights[uid]
	if f and os.clock() - f.at > FIGHT_STALE then
		fights[uid] = nil
		return nil
	end
	return f
end

-- The way into a host's defence: the access code, if it can still take a hunter (DD-088).
function Neighbors.wayIn(hostUid: number): string?
	local f = Neighbors.fight(hostUid)
	local w = ways[hostUid]
	if not f or not w or f.mode ~= "siege" or f.result then
		return nil
	end
	local p = f.p or {}
	if (p.squad or 4) >= 4 or ((p.wave or 5) >= 5 and not p.joinable) then
		return nil
	end
	return w.code
end

-- The line a fight puts on the sign: «Оборона бура · ВОЛНА 3/5 · 2:14 · бур 80%».
function Neighbors.fightLine(f): string
	if f.result == "win" then
		return "Возвращается с победой"
	elseif f.result == "loss" then
		return "Бой окончен · возвращается"
	end
	local p = f.p or {}
	local parts = { f.name }
	if type(p.label) == "string" and #p.label > 0 then
		table.insert(parts, p.label)
	end
	if tonumber(p.t) then
		table.insert(parts, string.format("%d:%02d", p.t // 60, p.t % 60))
	end
	if tonumber(p.drill) then
		table.insert(parts, "бур " .. p.drill .. "%")
	end
	return table.concat(parts, " · ")
end

-- What the held plots show: the owner's last showcase and where they are (and how it goes there).
function Neighbors.held(): { [number]: any }
	local out = {}
	for i, pl in plots do
		if pl.uid and pl.away and shown[pl.uid] then
			local e = table.clone(shown[pl.uid])
			e.away = away[pl.uid] and away[pl.uid].op or "бой"
			local f = Neighbors.fight(pl.uid)
			if f then
				e.fightLine = Neighbors.fightLine(f)
				e.fightHost = f.host
				e.canJoin = Neighbors.wayIn(f.host) ~= nil and (f.p or {}).joinable == true
				e.canQueue = Neighbors.wayIn(f.host) ~= nil
			end
			out[i] = e
		end
	end
	return out
end

function Neighbors.name(uid: number): string?
	return named[uid]
end

return Neighbors
