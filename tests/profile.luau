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
H.stubs.Players = {
	PlayerAdded = signal(),
	PlayerRemoving = signal(),
	GetPlayers = function()
		return {}
	end,
}
H.stubs.RunService = {
	IsStudio = function()
		return true
	end,
}

local Meta = H.require("src/shared/Meta")
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
check(table.find(
	(function()
		local kinds = {}
		for _, u in r1.unlocked do
			if u[1] == "research" then
				table.insert(kinds, u[2])
			end
		end
		return kinds
	end)(),
	"EN_SPITTER"
) ~= nil, "research milestone is returned for the results screen")
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
check(
	d.firstWinGrantUsed and d.scrap >= Defs.FirstWinGrant,
	string.format(
		"first-win grant tops up to %d (balance %d, grant %s)",
		Defs.FirstWinGrant,
		d.scrap,
		tostring(r2.grant)
	)
)
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
check(
	Defs.masteryNeed("W_RAILGUN", 20) == 16800 and Defs.masteryNeed("W_SCATTERGUN", 2) == 90,
	"mastery thresholds match 03_GAME_DATA"
)

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
	check(
		e.ops.O05 == 3 and e.ops.O07 == 1 and e.s01 == true and e.v == 3,
		"v1 veterans keep the boss hunts (O05/O07) and get S01"
	)
end

-- DD-061 raids: the raider's rating and the defence record are separate; nothing is taken from owners.
do
	print("=== raids (DD-061)")
	local q = player(3)
	Profile.load(q)
	local e = Profile.get(q)
	e.raid = { rating = 1234, wins = 3, losses = 1, defWins = 4, defLosses = 2 }
	Profile._reconcile(e)
	check(
		e.raid.attack == 1234 and e.raid.held == 4 and e.raid.pairs ~= nil,
		"migration: old rating becomes the raider rating, stopped raids the defence record"
	)
	local scrap, attack = e.scrap, e.raid.attack
	Profile.applyDefense(q, { { won = true, delta = 20 } })
	check(
		e.raid.attack == attack and e.scrap == scrap and e.raid.held == 4,
		"a breached defence costs the owner nothing (rating, utility, record)"
	)
	Profile.applyDefense(q, { { won = false, delta = 0 } })
	check(
		e.raid.held == 5 and e.scrap == scrap + Meta.DefenseReward,
		"a held raid adds to the record and pays from the system"
	)
	local function raidResult(uid, power, ageHours, victory)
		local r = result(victory, { id = 3 })
		r.mode = "raid"
		r.raid = { uid = uid, name = "X", power = power, t = os.time() - ageHours * 3600 }
		return r
	end
	local a = Profile.grantRun(q, "raid-1", raidResult(99, 3000, 5, true), "RAID", 1)
	check(
		a.total > 0 and a.rating.delta ~= 0 and not a.capped,
		"a won raid on an old snapshot pays and moves the raider rating"
	)
	local b = Profile.grantRun(q, "raid-2", raidResult(99, 3000, 5, true), "RAID", 1)
	check(b.total == 0 and b.capped == "pair", "the same owner pays once a day")
	local c = Profile.grantRun(q, "raid-3", raidResult(77, 3000, 0.5, true), "RAID", 1)
	check(c.total > 0 and c.rating.unrated and c.rating.delta == 0, "a fresh snapshot pays but leaves the rating alone")
end

print("=== mentors and the week (DD-088)")
do
	local v = player(501)
	Profile.load(v)
	local dv = Profile.get(v)
	dv.wins = 9
	dv.wins_by_op = { O01 = 3, O02 = 3, O03 = 3 }
	check(Meta.isVeteran(dv) and not Meta.isNewcomer(dv), "nine wins and the third sortie: a veteran")
	local plain = Profile.grantRun(v, "m-0", result(true, { id = 501 }), "O01", 1)
	local before = dv.mentor
	local helped = Profile.grantRun(v, "m-1", result(true, { id = 501 }), "O01", 1, { mentor = { "Новичок" } })
	check(
		dv.mentor == before + 1 and helped.mentor[1] == "Новичок",
		"a win beside a newcomer counts for the mentor"
	)
	check(
		helped.total > plain.total,
		string.format("the mentor's ксенит is higher (%d > %d)", helped.total, plain.total)
	)
	local week = Profile.thisWeek(dv)
	check(week.n == Meta.weekIndex(os.time()) and week.help >= 3, "the week's help counts the mentored fight")
	local lost = Profile.grantRun(v, "m-2", result(false, { id = 501 }), "O01", 1, { mentor = { "Новичок" } })
	check(lost.mentor == nil and dv.mentor == before + 1, "a lost fight mentors no one")
	dv.week = { n = week.n - 1, defense = 9, research = 9, help = 9 }
	check(Profile.thisWeek(dv).help == 0 and dv.week.n == week.n, "a new week starts from zero")
	check(
		Profile.addLaurel(v, "help", week.n - 1) and not Profile.addLaurel(v, "help", week.n - 1),
		"one laurel per board and week"
	)
	local r = Profile.grantRun(v, "m-3", result(true, { id = 501, species = { HIVE = 60 } }), "O01", 1)
	check(Profile.thisWeek(dv).research >= 3 and r ~= nil, "research stages raised count for the week")
	local lit = Profile.grantRun(v, "m-4", result(true, { id = 501 }), "O01", 1, { light = 2 })
	local dark = Profile.grantRun(v, "m-5", result(true, { id = 501 }), "O01", 1, { light = 0 })
	check(lit.light == 2 and lit.total > dark.total, "the Light of the Tree pays more (DD-089)")
	check(not Profile.setBanner(v, 3, "crown"), "an emblem needs its deed (the chapter is not done)")
	check(Profile.setBanner(v, 3, "skull") and dv.banner.emblem == "skull", "an earned emblem goes on the flag")
	check(not Profile.setBanner(v, 99, "pin"), "no colour outside the eight")
	local day = Meta.dayIndex(os.time())
	check(Profile.likeAway(v, 777, day) and not Profile.likeAway(v, 777, day), "♥ for an absent home: once a day")
	-- DD-090: the week's decoration
	dv.decor, dv.decorOn = {}, nil
	local dim = Profile.grantRun(v, "d-1", result(true, { id = 501 }), "O01", 1, { light = 1 })
	check(dim.decor == nil and next(dv.decor) == nil, "a dim Tree brings no decoration")
	local bright = Profile.grantRun(v, "d-2", result(true, { id = 501 }), "O01", 1, { light = Meta.DecorTier })
	local wk = Meta.decorOfWeek(Meta.weekIndex(os.time())).id
	check(bright.decor == wk and dv.decorOn == wk, "a win under a bright Tree brings the week's decoration, up at once")
	check(not Profile.earnDecor(v, 5), "each decoration once")
	check(
		Profile.setDecor(v, false) and dv.decorOn == nil and not Profile.setDecor(v, "FLOWERS_X"),
		"take it down; no unknown ones"
	)
	dv.week.wins = 0
	dv.decor = {}
	check(not Profile.earnDecor(v, 5), "no win this week, no decoration")
end

if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL PROFILE CHECKS PASSED")
