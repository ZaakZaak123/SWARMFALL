-- Squad rules (DD-012): downed -> revive by a nearby teammate, bleed-out, solo has no revive,
-- leaving keeps personal progress, a 2-player O01 run resolves.
-- Usage (repo root):  lune run tests/coop
local process = require("@lune/process")
local H = require("./harness")
local Bot = require("./bot")
local World = H.require("src/server/Sim/World")
local Defs = H.require("src/shared/Defs")

local failures = 0
local function check(ok: boolean, msg: string)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

local function squad(n)
	local list = {}
	for i = 1, n do
		table.insert(list, { id = i, name = "P" .. i, weapon = "W_ARC_RIFLE" })
	end
	return World.new({ seed = 9, op = "O01", players = list })
end

do
	local w = squad(2)
	w:step(5)
	w.t = 20
	local a, b = w.playerList[1], w.playerList[2]
	a.x, a.z, b.x, b.z = 0, -20, 3, -20
	w:hurtPlayer(a, 10000, 0, 0)
	check(not a.alive and a.downedUntil ~= nil and w.phase == "ACTIVE", "teammate at 0 HP is downed, run continues")
	for _ = 1, 70 do
		w:updateRevives(0.05)
	end
	check(a.alive and math.abs(a.hp - math.ceil(a.maxHp * Defs.Coop.ReviveHp)) < 1e-6, "teammate standing close revives in ~3 s")
	w:hurtPlayer(b, 0, 0, 0)
	b.iframeUntil = 0
	a.iframeUntil = 0
	a.graceUntil = 0
	w:hurtPlayer(a, 10000, 0, 0)
	b.x = 60 -- far away: no revive, bleed-out
	for _ = 1, math.ceil(Defs.Coop.BleedOut / 0.05) + 2 do
		w.t += 0.05
		w:updateRevives(0.05)
	end
	check(not a.alive and a.downedUntil == nil, "bleed-out without help: out until the end of the operation")
	local partial = w:leaveResult(2)
	check(partial ~= nil and partial.victory == false and #partial.players == 1 and partial.players[1].id == 2, "leaving builds a personal defeat result")
end

do
	local w = squad(1)
	w:step(5)
	w.t = 20
	local a = w.playerList[1]
	w:hurtPlayer(a, 10000, 0, 0)
	check(w.phase == "RESULTS" and a.downedUntil == nil, "solo: 0 HP ends the run (no revive)")
end

-- Two bots play O01 together: the run must resolve and both get personal results.
local out = Bot.run("W_ARC_RIFLE", 2, 424242, false, nil, 1, nil, { op = "O01", orbit = 32 })
local r = out.result
print(string.format("  duo O01: %s (%s) at %s  kills %d", if r.victory then "VICTORY" else "DEFEAT", r.reason, Bot.fmt(r.time), r.kills))
check(r ~= nil and #r.players == 2, "duo O01 resolves with two personal results")
check(r.players[1].kills + r.players[2].kills <= r.kills, "personal kills never exceed team kills")

if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL COOP CHECKS PASSED")
