-- Chapter difficulty against builds (DD-112 stage 2): from the middle of the chapter a rifle with only its
-- free main module should lose, and the build the chapter's loot can make by then should win.
-- Usage (repo root):  lune run tests/difficulty <op> <bare|ref|evo> [seeds]  one op, one build, prints each seed
--                     lune run tests/difficulty all                         the whole table (slow: run ops in
--                                                                           parallel with the first form)

local process = require("@lune/process")
local Bot = require("./bot")
local H = require("./harness")
local Ops = H.require("src/shared/Ops")
local Defs = H.require("src/shared/Defs")

-- The build the player can have before each sortie: Bot.ChapterBuild (O04: one tier I bought; O05: the
-- first tier II, after the first drill defence; O06–O07: two tier II).
-- `weapon=W_SCATTERGUN` plays another gun with the same shape of build (Bot.buildFor).
local WEAPON = "W_ARC_RIFLE"
for _, a in process.args do
	WEAPON = string.match(a, "^weapon=(W_[%u_]+)$") or WEAPON
end

-- What each build should do over the eight seeds (the bot aims past the screen and kites well, so a player
-- does worse than it): the bare rifle wins at most `bare`, the chapter's build at least `ref`.
local EXPECT = {
	O04 = { bare = 6, ref = 7 }, -- the turn: bare ~5/8 (a player does worse), the build 8/8 by half the time
	O05 = { bare = 5, ref = 7 }, -- the bot dodges the Broodmother better than a player; her limit is 2:05
	O06 = { bare = 5, ref = 7 },
	O07 = { bare = 4, ref = 7 },
}
local SEEDS = { 20261023, 20261101, 20261117, 20261123, 20261129, 20261201, 20261207, 20261213 }

-- Tuning: `key=value` arguments override the op's numbers for this run (enemyHpMult=1.4 bossHpMult=0.7 ...).
local overrides = {}
for _, a in process.args do
	local k, v = string.match(a, "^(%w+)=([%d%.]+)$")
	if k then
		overrides[k] = tonumber(v)
	end
end

-- `weaponDamage=6.8` / `weaponRate=…` tune the gun itself for this run (weapon balance across chapters).
if overrides.weaponDamage then
	Defs.Weapons[WEAPON].damage = overrides.weaponDamage
	overrides.weaponDamage = nil
end
if overrides.weaponRate then
	Defs.Weapons[WEAPON].rate = overrides.weaponRate
	overrides.weaponRate = nil
end

-- `evo`: the chapter's build with the gun's evolution opened (DD-112 stage 3: it fires in the fight).
local function play(op: string, build: string, seed: number)
	local loadout = Bot.buildFor(WEAPON, op, build == "bare")
	local opDef = nil
	local tuned = false
	for k in overrides do
		tuned = tuned or (k ~= "from" and k ~= "threat")
	end
	if tuned then
		opDef = table.clone(Ops.get(op))
		for k, v in overrides do
			if k == "reactorHp" then
				opDef.reactor = table.clone(opDef.reactor or {})
				opDef.reactor.hp = v
			elseif k == "nodesHp" then
				opDef.nodes = table.clone(opDef.nodes)
				opDef.nodes.hp = v
			elseif k == "nestsHp" then
				opDef.nests = table.clone(opDef.nests)
				opDef.nests.hp = v
			elseif k ~= "from" and k ~= "threat" then
				opDef[k] = v
			end
		end
	end
	local out = Bot.run(
		WEAPON,
		1,
		seed,
		false,
		nil,
		overrides.threat or 1,
		nil,
		{ op = op, orbit = 34, loadout = loadout, opDef = opDef, evoOpen = build == "evo" }
	)
	if out.milestones.evolved then
		out.result.evolvedAt = out.milestones.evolved
	end
	return out.result
end

local function runOne(op: string, build: string, n: number): number
	local wins = 0
	for i = 1, n do
		local j = i + (overrides.from or 1) - 1
		local seed = SEEDS[j] or (SEEDS[1] + j * 7919)
		local r = play(op, build, seed)
		if r.victory then
			wins += 1
		end
		print(
			string.format(
				"%s %-4s seed %d: %s (%s) at %s, kills %d, level %d%s",
				op,
				build,
				seed,
				if r.victory then "VICTORY" else "DEFEAT",
				r.reason,
				Bot.fmt(r.time),
				r.kills,
				r.level,
				(if r.reactor then string.format(", drill %d%%", math.floor(r.reactor * 100)) else "")
					.. (if r.evolvedAt then ", evolved at " .. Bot.fmt(r.evolvedAt) else "")
			)
		)
	end
	print(string.format("%s %s %s: %d/%d wins", op, WEAPON, build, wins, n))
	return wins
end

local args = process.args
if args[1] and args[1] ~= "all" then
	local n = tonumber(args[3] or "") or #SEEDS
	runOne(args[1], args[2] or "bare", n)
	return
end

local failures = 0
for _, op in { "O04", "O05", "O06", "O07" } do
	for _, build in { "bare", "ref" } do
		local want = EXPECT[op][build]
		local wins = runOne(op, build, #SEEDS)
		if build == "ref" and wins < want then
			failures += 1
			print(string.format("  FAIL %s: the chapter's build should win (%d/%d)", op, wins, #SEEDS))
		elseif build == "bare" and want and wins > want then
			failures += 1
			print(string.format("  FAIL %s: the bare rifle should lose (%d/%d)", op, wins, #SEEDS))
		end
	end
end
if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL DIFFICULTY CHECKS PASSED")
