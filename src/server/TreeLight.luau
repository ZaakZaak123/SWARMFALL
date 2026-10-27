--!nonstrict
-- The Light of the Tree (DD-089): one number for every grove — the victories of all survivors this
-- week. Each server adds its own wins in a batch now and then (DataStore IncrementAsync on one key per
-- week) and reads the total back; the tier (Meta.treeTier) lights the Tree's lanterns in every grove and
-- gives everyone +5% ксенита per tier until Monday. Without DataStore (Studio) it counts this server.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Meta = require(Shared:WaitForChild("Meta"))

local TreeLight = {}

local SYNC = 45
local store = nil
pcall(function()
	store = DataStoreService:GetDataStore("TLG_TreeLight_v1")
end)
local online = store ~= nil and not RunService:IsStudio()

local week = Meta.weekIndex(os.time())
local total = 0 -- the last total read (plus what this server added since)
local unsent = 0

local function roll()
	local now = Meta.weekIndex(os.time())
	if now ~= week then
		week, total, unsent = now, 0, 0
	end
end

function TreeLight.add(wins: number)
	roll()
	if wins > 0 then
		total += wins
		unsent += wins
	end
end

function TreeLight.sync()
	roll()
	if not online then
		return
	end
	local send = unsent
	unsent = 0
	local key = "w" .. week
	local ok, value = pcall(function()
		if send > 0 then
			return store:IncrementAsync(key, send)
		end
		return store:GetAsync(key)
	end)
	if ok and tonumber(value) then
		total = math.max(total, tonumber(value) :: number)
	elseif not ok then
		unsent += send -- try again next time
	end
end

-- { wins, tier, need (the next tier's wins, nil at the top), bonus, week }
function TreeLight.state()
	roll()
	local tier = Meta.treeTier(total)
	return {
		wins = total,
		tier = tier,
		need = Meta.TreeTiers[tier + 1],
		bonus = tier * Meta.TreeBonus,
		week = week,
	}
end

task.spawn(function()
	TreeLight.sync()
	while true do
		task.wait(SYNC)
		TreeLight.sync()
	end
end)

return TreeLight
