--!nonstrict
-- The groves' directory (DD-090): every public grove server tells the others, every 30 s, how many
-- survivors it holds, how many it may hold and how many plots are free (MemoryStore sorted map, entries
-- expire in two minutes). A squad that moves together, or comes home to a grove that filled up meanwhile,
-- finds a grove with room for all of them here. Without MemoryStore (Studio) nothing is known and the
-- callers fall back to «any grove».

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Directory = {}

local TTL = 120
local FRESH = 90
local map = nil
pcall(function()
	map = MemoryStoreService:GetSortedMap("TLG_Groves_v1")
end)
local online = map ~= nil and not RunService:IsStudio()

-- This grove now: { players, max, free }.
function Directory.publish(free: number)
	if not online or game.JobId == "" then
		return
	end
	local info = { players = #Players:GetPlayers(), max = Players.MaxPlayers, free = free, t = os.time() }
	task.spawn(function()
		pcall(map.SetAsync, map, game.JobId, info, TTL)
	end)
end

local function fits(v, need: number): boolean
	return type(v) == "table"
		and os.time() - (v.t or 0) < FRESH
		and (v.free or 0) >= need
		and (v.players or 0) + need <= (v.max or 0)
end

-- A grove with room for `need` survivors (plots and seats), not one of `exclude`: the liveliest that
-- still fits (people round you, not an empty field). nil when none is known.
function Directory.find(need: number, exclude: { string }?): string?
	if not online then
		return nil
	end
	local ok, items = pcall(map.GetRangeAsync, map, Enum.SortDirection.Ascending, 100)
	if not ok or type(items) ~= "table" then
		return nil
	end
	local best, bestPlayers = nil, -1
	for _, item in items do
		if not table.find(exclude or {}, item.key) and fits(item.value, need) and item.value.players > bestPlayers then
			best, bestPlayers = item.key, item.value.players
		end
	end
	return best
end

-- Is there still a seat for `need` in grove `job` (its own held plots wait for its squads anyway)?
function Directory.seats(job: string, need: number): boolean?
	if not online then
		return nil
	end
	local ok, v = pcall(map.GetAsync, map, job)
	if not ok then
		return nil
	end
	if type(v) ~= "table" or os.time() - (v.t or 0) >= FRESH then
		return false -- closed (or silent): it is gone
	end
	return (v.players or 0) + need <= (v.max or 0)
end

return Directory
