-- Operation playtests: the bot plays operations end to end and checks objective rules.
-- Usage (repo root):  lune run tests/ops_run [op|all] [weapon] [seed]
-- O01 checks (DD-024: ~3 min first run): carrier kill grants Ядро Бури, finale ends in victory, defended reactor survives,
-- an undefended reactor falls (strike groups are real), only Runners/Spitters/Carrier appear.

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
	print("=== O01 ПЕРВЫЙ КОНТАКТ")
	-- Defending bot: orbits the reactor and prioritises strike groups.
	-- New profile (no S01 yet): the encirclement must teach S01 with a pause the bot's press ends.
	local out = Bot.run(weapon, 1, seed, false, nil, 1, nil, { op = "O01", orbit = 32, s01 = false })
	report("defend", out)
	local me = out.result.players[1]
	local tut = out.milestones.s01Tutorial
	check(tut ~= nil and tut >= 80 and tut <= 100, "S01 tutorial at the encirclement (" .. (if tut then fmt(tut) else "never") .. ")")
	check(me.s01Unlocked and me.s01.casts >= 1 and me.s01.best >= 4, string.format("S01 unlocked, tutorial strike hits a crowd (casts %d, hits %d, kills %d, best %d)", me.s01.casts, me.s01.hits, me.s01.kills, me.s01.best))
	check(out.result ~= nil, "run finishes")
	check(out.milestones.firstKill ~= nil and out.milestones.firstKill < 15, "first kill within 15 s")
	check((out.milestones.assaults or 0) >= 2, "reactor strike groups announced")
	check(out.result.victory, "a defending newcomer wins the first operation")
	if out.result.victory then
		check(out.result.eliteKilled and table.find(out.result.components, "CMP_STORM_CORE") ~= nil, "carrier kill grants Ядро Бури")
		check(out.result.time > 150 and out.result.time < 240, "victory lands in the 2:30–4:00 window (DD-024)")
	else
		print("  NOTE defending bot lost: " .. out.result.reason)
	end
	check(out.result.reactor ~= nil, "reactor reported in result")

	-- Undefended reactor: bot hides in the far south corner and ignores strike groups.
	local away = Bot.run(weapon, 1, seed, false, nil, 1, nil, { op = "O01", anchor = { -120, -110 }, orbit = 12, ignoreReactor = true })
	report("ignore", away)
	check(not away.result.victory and away.result.reason == "РЕАКТОР УНИЧТОЖЕН", "undefended reactor falls")

	-- Roster: O01 never spawns species beyond Runner / Spitter / Carrier (GDD §4.3).
	local seen = {}
	local probe = Bot.run(weapon, 1, seed + 1, false, nil, 1, nil, { op = "O01", orbit = 32, onSpawn = function(kind)
		seen[kind] = true
	end })
	report("roster", probe)
	local extra = {}
	for kind in seen do
		if kind ~= "EN_RUNNER" and kind ~= "EN_SPITTER" and kind ~= "ELITE_CARRIER" then
			table.insert(extra, kind)
		end
	end
	check(#extra == 0, "O01 roster is Runner/Spitter/Carrier only" .. (if #extra > 0 then " (saw " .. table.concat(extra, ",") .. ")" else ""))
end

-- The rest of the chapter: each operation must resolve (no softlock), report a sane outcome and, when
-- the defending bot wins, have met its objective.
local CHAPTER = { "O02", "O03", "O04", "O05", "O06", "CA01" }
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
			if id == "O02" then
				check(m.relay and m.relay.charge >= m.relay.need, "O02 relay charged before the win")
			elseif id == "O03" then
				check(m.destroyed >= 2, "O03 two of three nests destroyed (" .. m.destroyed .. ")")
			elseif id == "O05" or id == "CA01" then
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
