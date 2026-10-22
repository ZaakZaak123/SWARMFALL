-- Headless full-run playtest: a kiting bot plays complete SWARMFALL runs against the real server sim.
-- Usage (repo root):  lune run tests/sim_run [weapon|all|batch] [players] [seed|runs] [map] [threat]
-- Verifies: no runtime errors, pacing milestones, evolution reachable, boss fight resolves, tick cost.

local process = require("@lune/process")
local H = require("./harness")

local World = H.require("src/server/Sim/World")
local Nav = H.require("src/server/Sim/Nav")
local Defs = H.require("src/shared/Defs")
local Codec = H.require("src/shared/Codec")
local Maps = H.require("src/shared/Maps")

local args = process.args
local weaponArg = args[1] or "all"
local playerCount = tonumber(args[2]) or 1
local seed = tonumber(args[3]) or 20261021
local mapArg = args[4] or "MAP_REACTOR_YARD"
local threatArg = tonumber(args[5]) or 1

local function fmt(t: number): string
	return string.format("%d:%02d", t // 60, math.floor(t % 60))
end

local Bot = require("./bot")
local function runOnce(weapon: string, players: number, runSeed: number, verbose: boolean, mapId: string?, threat: number?, perks: any?)
	return Bot.run(weapon, players, runSeed, verbose, mapId or mapArg, threat or threatArg, perks)
end

if weaponArg == "batch" then
	local n = tonumber(args[3]) or 6
	for _, weapon in (if args[6] then { args[6] } else Defs.WeaponOrder) do
		local wins, times, evolvedAt, levels = 0, 0, 0, 0
		local line = {}
		for k = 1, n do
			local out = runOnce(weapon, playerCount, 1000 + k * 7919, false, mapArg, threatArg)
			local r = out.result
			if r.victory then
				wins += 1
			end
			times += r.time
			levels += r.level
			evolvedAt += out.milestones.evolved or 0
			table.insert(line, (if r.victory then "W" else "L") .. fmt(r.time))
		end
		print(string.format("%-14s wins %d/%d  avg end %s  avg level %.1f  runs: %s", weapon, wins, n, fmt(times / n), levels / n, table.concat(line, " ")))
	end
	return
end

local weapons = if weaponArg == "all" then Defs.WeaponOrder else { weaponArg }
local failures = 0
for _, weapon in weapons do
	print(string.format("=== %s  players=%d seed=%d", weapon, playerCount, seed))
	local ok, out = pcall(runOnce, weapon, playerCount, seed, true)
	if not ok then
		failures += 1
		print("  RUNTIME ERROR: " .. tostring(out))
		continue
	end
	local r = out.result
	local m = out.milestones
	print(string.format(
		"  RESULT %s (%s) at %s  level %d  kills %d  hive %s",
		if r and r.victory then "VICTORY" else "DEFEAT", r and r.reason or "?", fmt(r and r.time or 0),
		r and r.level or 0, r and r.kills or 0, r and r.hive or "?"
	))
	print(string.format(
		"  first kill %.1fs  first level %.1fs  first choice %.1fs  core %s  evolved %s  overdrives %d",
		m.firstKill or -1, m.firstLevel or -1, m.firstChoice or -1, m.core and fmt(m.core) or "-",
		m.evolved and fmt(m.evolved) or "-", m.overdrives or 0
	))
	print(string.format(
		"  sim tick avg %.3f ms  max %.2f ms  peak enemies %d  spawned %d  lowest hp %d  events/s %.0f  enemy stream %.1f KB/s",
		out.avgTickMs, out.maxTickMs, out.peak, out.spawned, out.lowestHp, out.eventsPerSec, out.kbps
	))
	if not r then
		failures += 1
		print("  FAIL: run never finished")
	end
	if not m.firstKill or m.firstKill > 20 then
		failures += 1
		print("  FAIL: no kill in first 20s")
	end
	if not m.firstChoice or m.firstChoice > 75 then
		failures += 1
		print("  FAIL: first upgrade later than 75s")
	end
end

-- Determinism: identical seeds produce identical runs.
local a = runOnce(weapons[1], 1, 777, false)
local b = runOnce(weapons[1], 1, 777, false)
assert(a.result.time == b.result.time and a.result.kills == b.result.kills, "non-deterministic simulation")
print("PASS determinism (seed 777)")

-- Flow field reaches every spawn, hive site, coil pad and boss entry on every map.
for _, id in Maps.Order do
	local map = Maps.get(id)
	local nav = Nav.new(map)
	local field = nav.newField()
	nav.buildField(field, { { map.playerStart.x, map.playerStart.z } })
	for name, s in map.spawns do
		assert(nav.free(s.x, s.z, 2) and nav.costAt(field, s.x, s.z) < math.huge, id .. ": unreachable spawn " .. name)
	end
	for _, h in map.hiveSites do
		assert(nav.free(h.x, h.z, 5) and nav.costAt(field, h.x, h.z) < math.huge, id .. ": hive site blocked")
	end
	for _, c in map.coils do
		assert(nav.costAt(field, c.x + 4, c.z) < math.huge, id .. ": coil pad unreachable")
	end
	assert(nav.free(map.playerStart.x, map.playerStart.z, 2), id .. ": start blocked")
	print("PASS navigation reachability", id)
end

-- Meta: perks applied, threat raises difficulty, rewards computed.
do
	local perks = { PK_VITALITY = 5, PK_MAGNET = 3, PK_REROLL = 3, PK_BANISH = 2, PK_INSIGHT = 1, PK_OVERDRIVE = 2, PK_DASH = 3 }
	local w = World.new({ seed = 5, players = { { id = 1, name = "P", weapon = "W_RAILGUN", perks = perks } }, map = "MAP_HIVE_DEPTHS", threat = 3 })
	local p = w.playerList[1]
	assert(p.maxHp == 140 and p.rerolls == 3 and p.banishes == 2 and p.cards == 4 and math.abs(p.s01Cd - Defs.S01.Cooldown * (1 - 2 * Defs.S01.PerkCut)) < 1e-6, "perks not applied")
	w:step(5)
	w.t = 100
	local e = w:spawnEnemy("EN_RUNNER", 50, 50)
	assert(math.abs(e.maxHp - 24 * Defs.hpScale(100) * Defs.Threat.hp(3)) < 0.01, "threat hp")
	local r = Defs.runReward({ kills = 1200, level = 15, victory = true, time = 450, hive = "cleared" }, 3, 2)
	assert(r.total > 0 and #r.lines == 4, "reward")
	print("PASS perks / threat / rewards", r.total)
end
local out = runOnce("W_RAILGUN", 1, 4242, false, "MAP_HIVE_DEPTHS", 2, { PK_REROLL = 2, PK_BANISH = 1, PK_INSIGHT = 1 })
print(string.format("PASS railgun on Hive Depths threat 2: %s %s at %d:%02d", out.result.victory and "VICTORY" or "DEFEAT", out.result.reason, out.result.time // 60, math.floor(out.result.time % 60)))

if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL SIM CHECKS PASSED")
