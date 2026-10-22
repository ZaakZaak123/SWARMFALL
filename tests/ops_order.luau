-- Static data checks for operations: beats are time-ordered, every op is reachable through unlocks,
-- deadlines leave room for the final phase (D02 §3.1 invariant).
local process = require("@lune/process")
local H = require("./harness")
local Ops = H.require("src/shared/Ops")
local Maps = H.require("src/shared/Maps")

local failures = 0
local function check(ok, msg)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

local reachable = { O01 = true }
for _ = 1, #Ops.Order do
	for _, id in Ops.Order do
		if reachable[id] then
			for _, nxt in Ops.get(id).unlocks do
				reachable[nxt] = true
			end
		end
	end
end
for _, id in Ops.Order do
	local op = Ops.get(id)
	local last = -1
	local ordered = true
	for _, b in op.beats do
		if b.at < last then
			ordered = false
		end
		last = b.at
	end
	check(ordered, id .. " beats are in time order")
	check(reachable[id] == true, id .. " reachable through first-win unlocks")
	check(Maps.get(op.map).id == op.map, id .. " map exists")
	if op.objective ~= "boss" then
		local cap = op.hardLimit or 0
		check(op.deadline ~= nil and op.finale ~= nil and cap >= op.deadline + (op.finaleTime or 0), id .. " hardLimit >= deadline + finale")
	else
		check(op.hardLimit ~= nil, id .. " boss operation has a hard limit")
	end
	if op.requires then
		local req = Ops.get(op.requires)
		check(table.find(req.unlocks, id) ~= nil, id .. " is unlocked by its requirement " .. op.requires)
	end
end
if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL OPS DATA CHECKS PASSED")
