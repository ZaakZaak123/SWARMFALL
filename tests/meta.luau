-- Long-term meta (DD-037…DD-041): outpost rules, siege ladder, raids on outposts, the player's swarm,
-- anomalies. `lune run tests/meta` (sim runs take ~1–2 min); `lune run tests/meta quick` skips them.
local process = require("@lune/process")
local H = require("./harness")
local Meta = H.require("src/shared/Meta")
local Ops = H.require("src/shared/Ops")
local Goals = H.require("src/shared/Goals")
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

print("=== next goal")
do
	local pub = { winsByOp = {}, ops = { O01 = 1 }, scrap = 0, outpost = { slots = {}, siege = 1 }, tut = {}, home = {} }
	local function step(tag)
		local g = Goals.next(pub)
		print(string.format("  %-14s %s · %s  [%s%s]", tag, g.title, g.text, g.station, if g.spot then " " .. g.spot elseif g.slot then " #" .. g.slot else ""))
		return g
	end
	check(step("new").key == "hunt1", "goal 1: the sortie for the generator")
	pub.winsByOp.O01, pub.ops.O02, pub.scrap, pub.home.GENERATOR, pub.home.WORKBENCH = 1, 1, 180, true, true
	local g = step("won O01")
	check(g.key == "sting" and g.station == "build", "goal 2 (DD-075): right after the first win the first turret is affordable")
	pub.outpost.slots[Meta.FirstSocket] = { id = "STING", lvl = 1 }
	pub.scrap = 30
	g = step("built")
	check(g.key == "strike" and g.station == "launch" and g.mode == "siege", "goal 4: the drill defence is a sortie you choose")
	pub.tut.strike = true
	g = step("defended")
	check(g.key == "op_O02" and g.structure == "ARC" and g.text:find("Разрядник") ~= nil, "goal 5: next sortie opens the Разрядник and the radio")
	pub.winsByOp.O02, pub.ops.O03, pub.scrap, pub.home.RADIO = 1, 1, 400, true
	check(step("won O02").key == "build_ARC", "goal 6 (DD-076): the homecoming's promise first — the Разрядник")
	pub.outpost.slots[1] = { id = "ARC", lvl = 1 }
	pub.scrap = 320
	check(step("arc").key == "home_GARDEN", "goal 7: then the shelter grows (garden)")
	pub.home.GARDEN = true
	pub.outpost.slots[1] = nil
	pub.scrap = 100
	local g8 = step("poor")
	check(g8.key == "op_O03" and g8.structure == "CRYO", "goal 8: otherwise the next sortie (it promises the Криополе)")
	pub.winsByOp.O03, pub.home.LAB, pub.scrap = 1, true, 300
	pub.outpost.slots[1] = { id = "ARC", lvl = 1 }
	check(step("won O03").key == "build_CRYO", "goal 9 (DD-077): the homecoming's promise — the Криополе")
	pub.outpost.slots[2] = { id = "CRYO", lvl = 1 }
	pub.home.GARDEN, pub.ops.O04, pub.scrap = true, 1, 50
	local g10 = step("cryo")
	check(g10.key == "op_O04" and g10.text:find("свой рой") ~= nil, "goal 10 (DD-078): the nest sortie promises the own swarm")
	pub.winsByOp.O04 = 1
	local g11 = step("won O04")
	check(g11.key == "brood" and g11.station == "swarm", "goal 11 (DD-078): breed the first strain in the lab")
	pub.brood = { { kind = "EN_RUNNER", muts = {} } }
	check(step("brood").key ~= "brood", "goal 12: then the story goes on")
	check(Goals.titleCase("РАЗРЯДНИК") == "Разрядник", "Cyrillic title case")
end

print("=== shared research (DD-059)")
do
	local out = Bot.run("W_ARC_RIFLE", 2, 91, false, nil, 1, nil, { op = "O01", orbit = 30, s01 = false })
	local r = out.result
	local team = (r.species or {}).EN_RUNNER or 0
	local personal = 0
	for _, pl in r.players do
		personal += (pl.species or {}).EN_RUNNER or 0
	end
	print(string.format("  runners: squad credit %d, personal kills summed %d", team, personal))
	check(team >= personal and team > 0, "each member is credited with every kill of the squad (no race for the last shot)")
end

print("=== raid settlement (DD-061)")
do
	local st = { attack = 1000, rating = 1000, wins = 0, losses = 0, day = 0, count = 0, pairs = {} }
	local now = 1_000_000
	local weak = Meta.settleRaid(st, { victory = true, uid = 1, power = 0, t = now - 10 * 3600 }, 5, now)
	local strong = Meta.settleRaid(st, { victory = true, uid = 2, power = 5000, t = now - 10 * 3600 }, 5, now)
	print(string.format("  empty outpost pays %d, strong one %d", weak.total, strong.total))
	check(strong.total > weak.total * 4, "rewards scale with the defence power (an empty friend base is worth little)")
	for uid = 3, 5 do
		Meta.settleRaid(st, { victory = true, uid = uid, power = 1000, t = now - 10 * 3600 }, 5, now)
	end
	local sixth = Meta.settleRaid(st, { victory = true, uid = 6, power = 1000, t = now - 10 * 3600 }, 5, now)
	check(sixth.capped == "day" and sixth.total == 0, "at most " .. Meta.RaidDailyCap .. " rewarded raids a day")
	local tomorrow = Meta.settleRaid(st, { victory = true, uid = 1, power = 1000, t = now - 10 * 3600 }, 6, now)
	check(tomorrow.total > 0, "a new day resets the caps")
	local rival = Meta.settleRaid(st, { victory = false, rival = true, power = 900, t = now }, 6, now)
	check(not rival.unrated and rival.delta < 0, "generated rivals always count for the rating")
	local rev = Meta.settleRaid(st, { victory = true, uid = 9, power = 1000, t = now - 10 * 3600, revenge = true }, 6, now)
	check(rev.total == math.floor(Meta.raidRewardFor(1000, true) * Meta.RevengeMult + 0.5), "a revenge raid pays ×" .. Meta.RevengeMult)
end

print("=== first strike")
do
	local first = { [4] = { id = "STING", lvl = 1 } }
	local out = Bot.run("W_ARC_RIFLE", 1, 77, false, nil, 1, nil, { opDef = Ops.makeFirstStrike(), structures = first, orbit = 22, s01 = false })
	local r = out.result
	print(string.format("  strike: %s (%s) at %s  kills %d  level %d  bur %s", if r.victory then "VICTORY" else "DEFEAT", r.reason, fmt(r.time), r.kills, r.level, if r.reactor then math.floor(r.reactor * 100) .. "%" else "-"))
	check(r.victory and r.time >= 45 and r.time <= 75, "«Первый натиск» is a won defence of about a minute (45–75 s)")
	check(r.level == 1, "no cards in «Первый натиск» (it is a scene, not a run)")
	-- A player who just stands at the base spawn: the turret alone must not lose the lesson.
	local w = World.new({ seed = 5, players = { { id = 1, name = "IDLE", weapon = "W_ARC_RIFLE", s01 = false } }, opDef = Ops.makeFirstStrike(), structures = first })
	w:setPlayerPosition(1, 0, -58)
	w.gotInput = true -- the first defence waits for a first move (DD-075); this player moves once, then stands
	local t = 0
	while w.phase ~= "RESULTS" and t < 200 do
		w:step(1 / 30)
		w:drainEvents()
		w:setPlayerPosition(1, 0, -58)
		t += 1 / 30
	end
	local ir = w.result
	print(string.format("  idle: %s (%s) at %s  bur %s", if ir and ir.victory then "VICTORY" else "DEFEAT", ir and ir.reason or "-", fmt(t), if ir and ir.reactor then math.floor(ir.reactor * 100) .. "%" else "-"))
	check(ir ~= nil and (ir.reactor or 0) > 0.3 or (ir ~= nil and ir.victory), "the drill survives a hesitant player for the whole lesson")
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
