-- Sim cost profile: four immortal bots stand and shoot through O01 until 5:30; prints ms per tick by system.
-- Usage (repo root):  lune run tests/perf
local H = require("./harness")
local World = H.require("src/server/Sim/World")
local AI = H.require("src/server/Sim/AI")
local Combat = H.require("src/server/Sim/Combat")
local acc = {}
local function wrap(tbl, name, key)
	local f = tbl[name]
	tbl[name] = function(...)
		local t = os.clock()
		local a, b, c = f(...)
		acc[key] = (acc[key] or 0) + os.clock() - t
		return a, b, c
	end
end
wrap(AI, "update", "AI")
local nav = nil
wrap(Combat, "updatePlayer", "players")
wrap(World, "rebuildGrid", "grid")
wrap(World, "updateHazards", "hazards")
wrap(World, "updateOrbs", "orbs")
wrap(World, "director", "director")
local w = World.new({ seed = 5, op = "O01", players = { { id = 1, weapon = "W_ARC_RIFLE" }, { id = 2, weapon = "W_ARC_RIFLE" }, { id = 3, weapon = "W_ARC_RIFLE" }, { id = 4, weapon = "W_ARC_RIFLE" } } })
for _, p in w.playerList do p.maxHp = 1e9 p.hp = 1e9 end
wrap(w.nav, "buildField", "field")
wrap(w.nav, "flow", "flow")
wrap(w.nav, "clear", "los")
wrap(w, "query", "query")
wrap(w, "encodeEnemies", "encode")
local t0 = os.clock()
local ticks = 0
local fieldT = 0
while w.t < 330 and w.phase ~= "RESULTS" do
	for _, p in w.playerList do
		w:setAim(p.id, 0, 1, true)
		if p.offer then w:choose(p.id, p.offer.id, 1) end
	end
	if w.paused == "S01" then w:gravihammer(w.s01Tutee) end
	w:step(1/20)
	ticks += 1
end
local total = os.clock() - t0
print(string.format("ticks %d  avg %.2f ms  enemies now %d peak %d", ticks, total / ticks * 1000, #w.enemies, w.stats.peak))
for k, v in acc do print(string.format("  %-9s %.2f ms/tick", k, v / ticks * 1000)) end
