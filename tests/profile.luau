-- Profile settlement tests (no DataStore: the profile runs in offline mode, nothing is written).
-- Usage (repo root):  lune run tests/profile
-- Checks D03 invariants: idempotent rewards per runId, permanent progress kept on defeat, unique
-- components, first-win grant once, operation unlocks only on victory, v1 -> v2 migration.

local process = require("@lune/process")
local H = require("./harness")

local function signal()
	return { Connect = function() end }
end
H.stubs.DataStoreService = {
	GetDataStore = function()
		error("no DataStore in tests")
	end,
}
H.stubs.Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function()
	return {}
end }
H.stubs.RunService = { IsStudio = function()
	return true
end }

local Profile = H.require("src/server/Profile")
local Defs = H.require("src/shared/Defs")

local failures = 0
local function check(ok: boolean, msg: string)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

local function player(id: number)
	return { UserId = id, Name = "T" .. id, Parent = true }
end

local function result(victory: boolean, opts)
	opts = opts or {}
	return {
		victory = victory,
		reason = if victory then "ЗОНА УДЕРЖАНА" else "РЕАКТОР УНИЧТОЖЕН",
		time = 470,
		level = 13,
		kills = 900,
		hive = "idle",
		op = "O01",
		threat = 1,
		components = opts.components or {},
		players = {
			{
				id = opts.id or 1,
				name = "T",
				kills = 700,
				weapon = "W_ARC_RIFLE",
				weaponKills = opts.weaponKills or 640,
				species = opts.species or { EN_RUNNER = 650, EN_SPITTER = 49, ELITE_BULWARK = 1 },
				s01 = { casts = 3, hits = 30, kills = 18, crowds = 2, best = 16 },
				s01Unlocked = true,
				bestCombo = 10,
				alive = victory,
			},
		},
	}
end

print("=== profile settlement")
local p = player(1)
Profile.load(p)
local d = Profile.get(p)
check(d ~= nil and d.v == 3 and d.ops.O01 == 1 and not d.ops.O02, "fresh v3 profile: only O01 open")

-- Defeat: progress kept, no story rights, component granted for the deed.
local r1 = Profile.grantRun(p, "run-1", result(false, { components = { "CMP_STORM_CORE" } }), "O01", 1)
check(d.mastery.W_ARC_RIFLE == 640, "defeat keeps weapon mastery")
check(d.research.EN_RUNNER == 650 and d.research.EN_SPITTER == 49, "defeat keeps research")
check(d.components.CMP_STORM_CORE == true, "Ядро Бури granted for the carrier kill even on defeat")
check(d.s01 == true and d.s01Stats.kills == 18, "S01 unlocked and its kills counted separately")
check(not d.ops.O02 and not d.ops.O04, "defeat does not open the next operation")
check(r1.grant == nil, "no first-win grant on defeat")
local scrapAfter1 = d.scrap

-- Same runId again: nothing is applied twice.
Profile.grantRun(p, "run-1", result(false, { components = { "CMP_STORM_CORE" } }), "O01", 1)
check(d.mastery.W_ARC_RIFLE == 640 and d.scrap == scrapAfter1 and d.runs == 1, "rewards are idempotent per runId")

-- Victory: unlocks, threat, grant up to 180 once.
d.scrap = 40
local r2 = Profile.grantRun(p, "run-2", result(true, { components = { "CMP_STORM_CORE" } }), "O01", 1)
check(d.ops.O02 == 1 and d.ops.O04 == nil, "O01 win opens O02 (and nothing further)")
check(Profile.hasBlueprint(p, "W_SCATTERGUN") == false, "Вулкан blueprint needs the O02 win")
check(d.ops.O01 == 2, "O01 win opens threat 2")
check(d.firstWinGrantUsed and d.scrap >= Defs.FirstWinGrant, string.format("first-win grant tops up to %d (balance %d, grant %s)", Defs.FirstWinGrant, d.scrap, tostring(r2.grant)))
local count = 0
for _, u in r2.unlocked do
	if u[1] == "component" then
		count += 1
	end
end
check(count == 0, "component is unique (not re-granted)")
check(d.mastery.W_ARC_RIFLE == 1280, "mastery accumulates across runs")
local rank = Defs.masteryRank("W_ARC_RIFLE", d.mastery.W_ARC_RIFLE)
check(rank == 4, "1280 rifle kills = M4 (M5 needs 1300; rank " .. rank .. ")")
local scrapBefore3 = d.scrap
local r3 = Profile.grantRun(p, "run-3", result(true), "O01", 1)
check(r3.grant == nil and d.scrap == scrapBefore3 + r3.total, "grant is never paid twice")

-- Reward uses personal kills, not team kills.
local rr = Defs.runReward({ kills = 2000, level = 13, victory = true, time = 400, hive = "idle" }, 1, 0, 700)
check(rr.lines[1][2] == math.floor(700 / 12), "Ксенит counts personal kills")

-- Mastery ladder sanity.
check(Defs.masteryNeed("W_RAILGUN", 20) == 16800 and Defs.masteryNeed("W_SCATTERGUN", 2) == 90, "mastery thresholds match 03_GAME_DATA")

-- v1 -> v2 migration: a player who beat the Matka keeps the boss operations and gets S01.
do
	local q = player(2)
	Profile.load(q)
	local e = Profile.get(q)
	-- Simulate reconcile of a v1 record by loading through the module's private path: rebuild.
	e.v = 1
	e.ops = { O01 = 1 }
	e.threat = { MAP_REACTOR_YARD = 3, MAP_HIVE_DEPTHS = 1 }
	e.runs = 12
	e.s01 = false
	Profile._reconcile(e)
	check(e.ops.O05 == 3 and e.ops.O07 == 1 and e.s01 == true and e.v == 3, "v1 veterans keep the boss hunts (O05/O07) and get S01")
end

if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL PROFILE CHECKS PASSED")
