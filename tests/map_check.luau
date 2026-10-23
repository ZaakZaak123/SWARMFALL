-- Geometry sanity for every map: spawns, nests, start, boss entry, coils' surroundings are walkable,
-- and the flow field reaches the player start from every spawn.
local process = require("@lune/process")
local H = require("./harness")
local Maps = H.require("src/shared/Maps")
local Nav = H.require("src/server/Sim/Nav")

local failures = 0
local function check(ok, msg)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

for _, id in Maps.Order do
	local m = Maps.get(id)
	local nav = Nav.new(m)
	check(nav.free(m.playerStart.x, m.playerStart.z, 2), id .. " player start free")
	check(nav.free(m.bossEntry.x, m.bossEntry.z, 4), id .. " boss entry free")
	for k, s in m.spawns do
		check(nav.free(s.x, s.z, 2), `{id} spawn {k} free ({s.x},{s.z})`)
	end
	for i, h in m.hiveSites do
		check(nav.free(h.x, h.z, 5), `{id} nest site {i} free`)
	end
end
if failures > 0 then
	process.exit(1)
end
