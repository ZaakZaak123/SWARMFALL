-- Operation playtests: the bot plays operations end to end and checks objective rules.
-- Usage (repo root):  lune run tests/ops_run [op|all] [weapon] [seed]
-- O01 (DD-075): ~1:00 first hunt with exactly three guided cards, ends with the Alpha, nothing to guard, the Alpha, Runners only. O02: the S01 lesson.
-- O03+: each hunt resolves and, when the bot wins, its objective was met.

local process = require("@lune/process")
local Bot = require("./bot")

local args = process.args
local opArg = args[1] or "O01"
local weapon = args[2] or "W_ARC_RIFLE"
local seed = tonumber(args[3]) or 20261023

local fmt = Bot.fmt
local failures = 0
local function check(ok: boolean, msg: string)
	if ok then
		print("  PASS " .. msg)
	else
		failures += 1
		print("  FAIL " .. msg)
	end
end

local function report(tag: string, out)
	local r, m = out.result, out.milestones
	print(string.format(
		"%s: %s (%s) at %s  kills %d  level %d  reactor %s  assaults %d  component %s  tick avg %.2f ms",
		tag, if r.victory then "VICTORY" else "DEFEAT", r.reason, fmt(r.time), r.kills, r.level,
		if r.reactor then string.format("%d%%", math.floor(r.reactor * 100)) else "-",
		m.assaults or 0, if m.component then fmt(m.component) else "-", out.avgTickMs
	))
end

if opArg == "O01" or opArg == "all" then
	print("=== O01 ВЫСАДКА")
	-- DD-032: the first hunt has no objective to guard and no S01 lesson — shoot, cards, the Alpha.
	local out = Bot.run(weapon, 1, seed, false, nil, 1, nil, { op = "O01", orbit = 32, s01 = false, firstHunt = true })
	report("newcomer", out)
	local lv = {}
	for _, t in out.milestones.levels or {} do
		table.insert(lv, fmt(t))
	end
	print("  level-ups at " .. table.concat(lv, ", "))
	check(#lv == 3, "exactly three cards in the first hunt (" .. #lv .. ")")
	local locked = table.concat(out.milestones.lockedCards or {}, ",")
	check(locked == "UPG_MULTISHOT,UPG_DETONATE,UPG_SHIELD", "guided cards in order: Расщепление, Детонатор, Барьер (" .. locked .. ")")
	check(out.milestones.levels and out.milestones.levels[3] and out.milestones.levels[3] < 40, "all three cards before the Alpha (~0:38)")
	local me = out.result.players[1]
	check(out.result ~= nil, "run finishes")
	check(out.milestones.firstKill ~= nil and out.milestones.firstKill < 15, "first kill within 15 s")
	check(out.milestones.s01Tutorial == nil and not me.s01Unlocked, "no Gravihammer lesson in the first hunt")
	check(out.result.reactor == nil, "nothing to guard in the first hunt")
	check(out.result.victory, "a newcomer bot wins the first hunt")
	if out.result.victory then
		check(out.result.eliteKilled, "the Alpha is killed")
		check(out.result.time > 45 and out.result.time < 75, "victory lands in the 0:45–1:15 window (DD-075)")
		check(out.result.reason == "Рой отброшен", "the Alpha's death ends the run (no last wave)")
	else
		print("  NOTE newcomer bot lost: " .. out.result.reason)
	end
	-- Roster: O01 is Runners and the Alpha only.
	local seen = {}
	local probe = Bot.run(weapon, 1, seed + 1, false, nil, 1, nil, { op = "O01", orbit = 32, onSpawn = function(kind)
		seen[kind] = true
	end })
	report("roster", probe)
	local extra = {}
	for kind in seen do
		if kind ~= "EN_RUNNER" and kind ~= "ELITE_CARRIER" then
			table.insert(extra, kind)
		end
	end
	check(#extra == 0, "O01 roster is Runner/Alpha only" .. (if #extra > 0 then " (saw " .. table.concat(extra, ",") .. ")" else ""))
end

if opArg == "O02" or opArg == "all" or opArg == "chapter" then
	print("=== O02 ОКРУЖЕНИЕ")
	-- A profile without S01 learns it when the ring closes (~1:15) and the bot's press ends the pause.
	local out = Bot.run(weapon, 1, seed + 2, false, nil, 1, nil, { op = "O02", orbit = 32, s01 = false })
	report("O02", out)
	local me = out.result.players[1]
	local tut = out.milestones.s01Tutorial
	check(tut ~= nil and tut >= 70 and tut <= 95, "S01 lesson at the ring (" .. (if tut then fmt(tut) else "never") .. ")")
	check(me.s01Unlocked and me.s01.casts >= 1 and me.s01.best >= 4, string.format("S01 unlocked, lesson strike hits a crowd (casts %d, best %d)", me.s01.casts, me.s01.best))
	check(out.result.victory, "O02 won by a bot with the start rifle")
	check(out.result.time < 330, "O02 ends within ~5:30")
end

-- The rest of the chapter: each operation must resolve (no softlock), report a sane outcome and, when
-- the defending bot wins, have met its objective.
local CHAPTER = { "O03", "O04", "O05", "O06", "O07", "CA01" }
for _, id in CHAPTER do
	if opArg == id or opArg == "all" or opArg == "chapter" then
		print("=== " .. id)
		local out = Bot.run(weapon, 1, seed + #id, false, nil, 1, nil, { op = id, orbit = 34 })
		report(id, out)
		local r = out.result
		check(r ~= nil, id .. " resolves")
		if r.victory then
			local w = out.world
			local m = w.mission
			if id == "O03" then
				check(m.relay and m.relay.charge >= m.relay.need, "O03 pylon charged before the win")
			elseif id == "O04" then
				check(m.destroyed >= 2, "O04 two of three nests destroyed (" .. m.destroyed .. ")")
			elseif id == "O06" or id == "CA01" then
				check(m.destroyed >= 2, id .. " both targets destroyed")
			else
				check(w.boss == nil and w.bossSpawned, id .. " boss killed")
			end
		else
			print("  NOTE " .. id .. " defending bot lost: " .. r.reason)
		end
	end
end

if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL OPS CHECKS PASSED")
