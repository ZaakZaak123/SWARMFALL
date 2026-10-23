--!nonstrict
-- Cross-server outposts (DD-039/DD-041). The owner never has to be online:
--   pool      one DataStore key with the latest snapshots of published outposts (slots + brood + rating);
--             raids load a snapshot, build it on the attacker's server and fight it there
--   raid log  per-owner key the attacker's server appends to; the owner's server claims it on join
--             (defence rewards, rating) and shows it in the lobby with a «revenge» button
--   boards    OrderedDataStores: raid rating and best siege level
-- Without DataStore access (Studio, outage) everything degrades to generated rivals and a session log:
-- nothing is written, nothing real can be lost.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Meta = require(Shared:WaitForChild("Meta"))
local Profile = require(script.Parent.Profile)

local Outposts = {}

local POOL_SIZE = 150
local LOG_SIZE = 20
local poolStore, logStore, ratingBoard, siegeBoard
pcall(function()
	poolStore = DataStoreService:GetDataStore("SPOREFALL_OutpostPool_v1")
	logStore = DataStoreService:GetDataStore("SPOREFALL_RaidLog_v1")
	ratingBoard = DataStoreService:GetOrderedDataStore("SPOREFALL_RaidRating_v1")
	siegeBoard = DataStoreService:GetOrderedDataStore("SPOREFALL_SiegeBest_v1")
end)

local online = true -- flips off on the first DataStore failure for this server's lifetime
local poolCache, poolAt = {}, -1e9
local boardsCache, boardsAt = { rating = {}, siege = {} }, -1e9
local publishAt: { [number]: number } = {}

local function safe(fn)
	if not online then
		return false, nil
	end
	local ok, res = pcall(fn)
	if not ok then
		online = false
		warn("[SPOREFALL] outposts offline:", res)
	end
	return ok, res
end

local function snapshot(player: Player, d)
	return {
		uid = player.UserId,
		name = "Аванпост " .. player.DisplayName,
		rating = d.raid.rating,
		slots = d.outpost.slots,
		brood = d.brood,
		t = os.time(),
	}
end

-- Publish this player's outpost to the pool (throttled; only once they have something to defend).
function Outposts.publish(player: Player, force: boolean?)
	local d = Profile.get(player)
	if not d or not poolStore or Meta.outpostPower(d.outpost.slots) <= 0 then
		return
	end
	local now = os.clock()
	if not force and now - (publishAt[player.UserId] or -1e9) < 60 then
		return
	end
	publishAt[player.UserId] = now
	local snap = snapshot(player, d)
	task.spawn(function()
		safe(function()
			poolStore:UpdateAsync("pool", function(list)
				list = if type(list) == "table" then list else {}
				for i = #list, 1, -1 do
					if list[i].uid == snap.uid then
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
		safe(function()
			ratingBoard:SetAsync(tostring(player.UserId), d.raid.rating)
			if (d.outpost.best or 0) > 0 then
				siegeBoard:SetAsync(tostring(player.UserId), d.outpost.best)
			end
		end)
	end)
end

local function pool()
	if os.clock() - poolAt > 45 and poolStore then
		poolAt = os.clock()
		local ok, list = safe(function()
			return poolStore:GetAsync("pool")
		end)
		if ok and type(list) == "table" then
			poolCache = list
		end
	end
	return poolCache
end

-- Three raid targets near the attacker's rating: real outposts first, generated rivals fill the rest.
function Outposts.candidates(player: Player)
	local d = Profile.get(player)
	local rating = if d then d.raid.rating else Meta.StartRating
	local list = {}
	for _, s in pool() do
		if s.uid ~= player.UserId and Meta.outpostPower(s.slots) > 0 then
			table.insert(list, s)
		end
	end
	table.sort(list, function(a, b)
		return math.abs(a.rating - rating) < math.abs(b.rating - rating)
	end)
	local out = {}
	for i = 1, math.min(3, #list) do
		out[i] = list[i]
	end
	local seed = player.UserId % 9973 + Meta.dayIndex(os.time()) * 31 + (if d then d.raid.wins + d.raid.losses else 0) * 7
	local k = 0
	while #out < 3 do
		k += 1
		table.insert(out, Meta.rival(seed + k * 101, rating + (k - 2) * 120))
	end
	return out
end

-- A specific outpost (revenge / a friend's base) from the pool.
function Outposts.find(uid: number)
	for _, s in pool() do
		if s.uid == uid then
			return s
		end
	end
	return nil
end

-- Report a finished raid to the owner (appended to their log; they claim it when they come back).
function Outposts.report(target, attackers: { Player }, won: boolean, delta: number)
	if not target or target.rival or not logStore then
		return
	end
	local names = {}
	for _, p in attackers do
		table.insert(names, p.DisplayName)
	end
	local entry = {
		attacker = if attackers[1] then attackers[1].UserId else 0,
		name = table.concat(names, ", "),
		won = won,
		delta = delta,
		t = os.time(),
		claimed = false,
	}
	task.spawn(function()
		safe(function()
			logStore:UpdateAsync("u_" .. target.uid, function(log)
				log = if type(log) == "table" then log else {}
				table.insert(log, 1, entry)
				while #log > LOG_SIZE do
					table.remove(log)
				end
				return log
			end)
		end)
		-- The owner may be on this very server or online elsewhere later: claim happens on their join.
		local owner = Players:GetPlayerByUserId(target.uid)
		if owner then
			Outposts.claim(owner)
		end
	end)
end

-- On join: settle every unclaimed raid on this player's outpost and keep the log for the lobby.
function Outposts.claim(player: Player)
	if not logStore then
		Profile.setRaidLog(player, {})
		return
	end
	local fresh = {}
	local ok, log = safe(function()
		return logStore:UpdateAsync("u_" .. player.UserId, function(log)
			log = if type(log) == "table" then log else {}
			for _, entry in log do
				if not entry.claimed then
					entry.claimed = true
					table.insert(fresh, entry)
				end
			end
			return log
		end)
	end)
	if #fresh > 0 then
		Profile.applyDefense(player, fresh)
	end
	Profile.setRaidLog(player, if ok and type(log) == "table" then log else {})
end

-- Top 10 boards (cached a minute). Never yields: the refresh runs in the background.
local function refreshBoards()
		for key, store in { rating = ratingBoard, siege = siegeBoard } do
			local ok, page = safe(function()
				return store:GetSortedAsync(false, 10):GetCurrentPage()
			end)
			if ok and page then
				local rows = {}
				for _, row in page do
					local uid = tonumber(row.key)
					local name = "?"
					pcall(function()
						name = Players:GetNameFromUserIdAsync(uid)
					end)
					table.insert(rows, { name = name, value = row.value })
				end
				boardsCache[key] = rows
			end
		end
end

function Outposts.boards()
	if os.clock() - boardsAt > 60 and ratingBoard and online then
		boardsAt = os.clock()
		task.spawn(refreshBoards)
	end
	return boardsCache
end

function Outposts.online(): boolean
	return online and poolStore ~= nil
end

return Outposts
