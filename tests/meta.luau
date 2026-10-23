-- Long-term meta (DD-037…DD-041): outpost rules, siege ladder, raids on outposts, the player's swarm,
-- anomalies. `lune run tests/meta` (sim runs take ~1–2 min); `lune run tests/meta quick` skips them.
local process = require("@lune/process")
local H = require("./harness")
local Meta = H.require("src/shared/Meta")
local Ops = H.require("src/shared/Ops")
local Maps = H.require("src/shared/Maps")
local Nav = H.require("src/server/Sim/Nav")
local World = H.require("src/server/Sim/World")
local Bot = require("./bot")

local quick = process.args[1] == "quick"
local failures = 0
local function check(ok, msg)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end
local function fmt(t)
	return string.format("%d:%02d", t // 60, math.floor(t % 60))
end

print("=== rules")
local nav = Nav.new(Maps.get("MAP_REACTOR_YARD"))
local freeAll = true
for i, s in Meta.Sockets do
	if not nav.free(s.x, s.z, 2.5) then
		freeAll = false
		print("    socket " .. i .. " blocked")
	end
end
check(freeAll, "all " .. Meta.SocketCount .. " outpost sockets stand on open ground")
local clean = Meta.cleanOutpost({ [1] = { id = "STING", lvl = 9 }, [2] = { id = "NUKE", lvl = 1 }, ["3"] = { id = "ARC", lvl = 2 } })
check(clean[1].lvl == 3 and clean[2] == nil and clean[3].id == "ARC", "outpost sanitizer clamps levels and drops unknown pieces")
check(Meta.harvest({ [1] = { id = "HARVEST", lvl = 1 } }, 0, 3600 * 30) == 40 * Meta.HarvestCapHours, "harvest caps at " .. Meta.HarvestCapHours .. " h")
local d = { research = { EN_RUNNER = 205 }, dnaSpent = { EN_RUNNER = 3 } }
check(Meta.dna(d, "EN_RUNNER") == 7, "DNA = kills / rate − spent")
local brood = Meta.cleanBrood({ { kind = "EN_RUNNER", muts = { "FRENZY", "FRENZY", "REGEN", "VOLATILE" } }, { kind = "X" } })
check(#brood == 1 and #brood[1].muts == 2, "brood sanitizer: valid species, ≤2 distinct mutations")
check(Meta.ratingDelta(1000, 1000, true) == 16 and Meta.ratingDelta(1000, 1000, false) == -16, "rating: even match ±16")
local okRivals = true
for seed = 1, 30 do
	local r = Meta.rival(seed, 900 + seed * 40)
	if Meta.outpostPower(r.slots) <= 0 or #Meta.cleanBrood(r.brood) == 0 then
		okRivals = false
	end
end
check(okRivals, "generated rivals always have defences and a brood")
local seen = {}
for day = 0, 30 do
	seen[Meta.anomalyFor(day).id] = true
end
local n = 0
for _ in seen do
	n += 1
end
check(n == #Meta.Anomalies, "every anomaly comes up within a month (" .. n .. ")")
local op = Ops.makeSiege(3)
local ordered = true
for i = 2, #op.beats do
	ordered = ordered and op.beats[i].at >= op.beats[i - 1].at
end
check(ordered and op.hardLimit > op.deadline, "siege script: ordered beats, room for the finale")

do -- anomaly hooks: glass shells halve hp, haste speeds up
	local glass = Meta.Anomalies[3]
	local w = World.new({ seed = 3, op = "O03", players = { { id = 1, weapon = "W_ARC_RIFLE" } }, anomaly = glass })
	local plain = World.new({ seed = 3, op = "O03", players = { { id = 1, weapon = "W_ARC_RIFLE" } } })
	local a = w:spawnEnemy("EN_RUNNER", 50, 50, 0)
	local b = plain:spawnEnemy("EN_RUNNER", 50, 50, 0)
	check(math.abs(a.hp - b.hp * glass.hp) < 1e-6, "anomaly «Стеклянные панцири» lowers enemy hp")
end

do -- mutations change the body and leave something behind
	local w = World.new({ seed = 4, op = "O03", players = { { id = 1, weapon = "W_ARC_RIFLE" } } })
	w.phase = "ACTIVE"
	local e = w:spawnEnemy("EN_RUNNER", 30, 30, 0)
	local base = e.hp
	Meta.applyMutations(e, { "CARAPACE", "ACID_BLOOD" })
	check(e.hp > base * 1.5 and e.speedMult < 1, "Панцирь: more hp, a little slower")
	local before = #w.hazards
	w:kill(e, nil, 0, 0)
	check(#w.hazards == before + 1, "Кислотная кровь leaves an acid pool")
end

if not quick then
	print("=== siege")
	local function siege(level, slots, seed)
		local out = Bot.run("W_ARC_RIFLE", 1, seed, false, nil, 1, nil, { opDef = Ops.makeSiege(level), structures = slots, orbit = 26, s01 = true })
		local r = out.result
		local turretKills = 0
		print(string.format("  L%d %s: %s (%s) at %s  kills %d  bur %s", level, if next(slots) then "outpost" else "bare", if r.victory then "VICTORY" else "DEFEAT", r.reason, fmt(r.time), r.kills, if r.reactor then math.floor(r.reactor * 100) .. "%" else "-"))
		return out
	end
	local basic = { [1] = { id = "STING", lvl = 1 }, [3] = { id = "STING", lvl = 1 }, [5] = { id = "ARC", lvl = 1 }, [8] = { id = "CRYO", lvl = 1 } }
	local s1 = siege(1, basic, 11)
	check(s1.result.victory, "siege 1 with a starter outpost is won by a bot")
	local strong = {}
	for i = 1, 10 do
		strong[i] = { id = ({ "STING", "ARC", "MORTAR", "ACID", "STING", "MORTAR", "CRYO", "SHIELD", "ARC", "HARVEST" })[i], lvl = 2 }
	end
	local s6 = siege(6, strong, 12)
	check(s6.result.victory, "siege 6 with a full level-2 outpost is won by a bot")
	local bare6 = siege(6, {}, 12)
	check(not bare6.result.victory or (bare6.result.reactor or 0) < (s6.result.reactor or 1), "the outpost matters: siege 6 is harder without it")

	print("=== raid")
	local lowWins = 0
	for seed = 1, 3 do
		local target = Meta.rival(seed * 13, 900)
		local out = Bot.run("W_ARC_RIFLE", 1, 500 + seed, false, nil, 1, nil, { opDef = Ops.makeRaid(target), orbit = 30, s01 = true })
		print(string.format("  low #%d vs %d (power %d): %s at %s", seed, target.rating, Meta.outpostPower(target.slots), if out.result.victory then "VICTORY" else "DEFEAT (" .. out.result.reason .. ")", fmt(out.result.time)))
		if out.result.victory then
			lowWins += 1
		end
	end
	check(lowWins >= 2, "a bot breaks low-rated outposts (" .. lowWins .. "/3)")
	for _, rating in { 900, 1200 } do
		local target = Meta.rival(rating, rating)
		local out = Bot.run("W_ARC_RIFLE", 1, rating + 1, false, nil, 1, nil, { opDef = Ops.makeRaid(target), orbit = 30, s01 = true })
		local r = out.result
		print(string.format("  vs %s (%d, power %d): %s (%s) at %s  kills %d  hp low %d", target.name, target.rating, Meta.outpostPower(target.slots), if r.victory then "VICTORY" else "DEFEAT", r.reason, fmt(r.time), r.kills, out.lowestHp))
		check(r.mode == "raid" and r.raid and r.raid.name == target.name, "raid result names the target")
		check(out.lowestHp < 100, "hostile turrets and brood actually hurt the raiders")
	end
	local duo = Bot.run("W_ARC_RIFLE", 2, 77, false, nil, 1, nil, { opDef = Ops.makeRaid(Meta.rival(1300, 1300)), orbit = 30, s01 = true })
	print(string.format("  duo vs 1300: %s at %s", if duo.result.victory then "VICTORY" else "DEFEAT", fmt(duo.result.time)))
	check(duo.result ~= nil, "a squad raid resolves")
end

if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL META CHECKS PASSED")
