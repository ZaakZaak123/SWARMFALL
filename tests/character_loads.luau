-- Reproduce a slow lobby LoadCharacter completing after a sortie already requested its spawn.
local H = require("./harness")
H.task.wait = coroutine.yield
local Loads = H.require("src/server/CharacterLoads")
local loads = Loads.new()
local player = { Parent = true }
local landed, loading, maxLoading = nil, 0, 0
local function request(destination, fail)
	return coroutine.create(function()
		loads:run(player, function(current)
			loading += 1
			maxLoading = math.max(maxLoading, loading)
			coroutine.yield("LoadCharacter")
			loading -= 1
			if fail then
				error("simulated avatar failure")
			end
			if current() then
				landed = destination
			end
		end)
	end)
end
local function step(thread)
	local ok, err = coroutine.resume(thread)
	assert(ok, err)
end
local home, run = request("home"), request("arena")
step(home)
step(run)
step(home)
assert(landed == nil, "stale home load must not move the hero or overwrite movement tracking")
step(run)
step(run)
assert(landed == "arena" and maxLoading == 1, "latest destination wins; avatar loads cannot overlap")
print("PASS slow home load vs sortie spawn")

local stale, superseded, newest = request("old"), request("skipped"), request("latest")
step(stale)
step(superseded)
step(newest)
step(stale)
step(superseded)
assert(coroutine.status(superseded) == "dead", "skip queued requests that were superseded")
step(newest)
step(newest)
assert(landed == "latest")
print("PASS three overlapping destination requests")

local leaving = request("departed")
step(leaving)
loads:cancel(player)
step(leaving)
assert(landed == "latest" and loads.requests[player] == nil and loads.busy[player] == nil)
print("PASS removal cancels pending destination")

local broken, retry = request("broken", true), request("retry")
step(broken)
step(retry)
step(broken)
step(retry)
step(retry)
assert(landed == "retry" and loads.busy[player] == nil)
print("PASS failed avatar load releases the next request")
