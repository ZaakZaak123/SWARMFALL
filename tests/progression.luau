-- Late progression checks: S01 specializations (DD-013) and M20 alternative forms (DD-014).
-- Usage (repo root):  lune run tests/progression
local process = require("@lune/process")
local H = require("./harness")

local function signal()
	return { Connect = function() end }
end
H.stubs.DataStoreService = { GetDataStore = function()
	error("no DataStore in tests")
end }
H.stubs.Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function()
	return {}
end }
H.stubs.RunService = { IsStudio = function()
	return true
end }

local Defs = H.require("src/shared/Defs")
local World = H.require("src/server/Sim/World")
local Combat = H.require("src/server/Sim/Combat")
local Profile = H.require("src/server/Profile")

local failures = 0
local function check(ok: boolean, msg: string)
	print((if ok then "  PASS " else "  FAIL " ) .. msg)
	if not ok then
		failures += 1
	end
end

local function ring(w, p, n, r)
	local list = {}
	for i = 1, n do
		local a = i / n * math.pi * 2
		table.insert(list, w:spawnEnemy("EN_RUNNER", p.x + math.cos(a) * r, p.z + math.sin(a) * r, 0.05))
	end
	return list
end

local function world(spec, form)
	local w = World.new({ seed = 4, op = "O01", players = { { id = 1, weapon = "W_ARC_RIFLE", s01Spec = spec, form = form } } })
	w:step(5)
	w.t = 120
	return w, w.playerList[1]
end

-- S01 points ladder
check(Defs.s01Rank(Defs.s01Points({ hits = 0, kills = 0, crowds = 0 })) == 1, "S01 starts at M1")
check(Defs.s01Rank(550) == 5 and Defs.s01Tier(5) == 1 and Defs.s01Tier(8) == 2 and Defs.s01Tier(12) == 3, "S01 M5 opens tier I, M8 II, M12 III")

do -- A3: cooldown −15% and a follow-up wave
	local w, p = world({ branch = "A", tier = 3 })
	check(math.abs(p.s01Cd - Defs.S01.Cooldown * 0.85) < 1e-6, "Катаклизм III: −15% cooldown")
	ring(w, p, 10, 7)
	w:step(0.2)
	w:gravihammer(1)
	for _ = 1, 7 do
		w:step(0.05)
	end
	check(p.hammerFollow ~= nil, "Катаклизм II+: follow-up wave scheduled")
	for _ = 1, 12 do
		w:step(0.05)
	end
	check(p.hammerFollow == nil, "follow-up wave resolves once")
end

do -- C2: pull instead of push
	local w, p = world({ branch = "C", tier = 2 })
	for _, e in w.enemies do
		e.alive = false
	end
	local list = ring(w, p, 6, 8)
	for _, e in list do
		e.hp = 1e6
		e.maxHp = 1e6
	end
	w:step(0.2)
	w:gravihammer(1)
	for _ = 1, 8 do
		w:step(0.05)
	end
	local closer = 0
	for _, e in list do
		if math.sqrt((e.x - p.x) ^ 2 + (e.z - p.z) ^ 2) < 7.5 then
			closer += 1
		end
	end
	check(closer >= 4, "Сингулярность II: enemies pulled inward (" .. closer .. "/6)")
end

do -- B2: shield on hits
	local w, p = world({ branch = "B", tier = 2 })
	ring(w, p, 8, 6)
	w:step(0.2)
	w:gravihammer(1)
	for _ = 1, 8 do
		w:step(0.05)
	end
	check(p.shield > 0, "Бастион II: hits charge the shield (" .. p.shield .. ")")
end

do -- M20 form in the sim
	local w, p = world(nil, "EV_M20_STORM")
	check(p.evolved == "EV_M20_STORM" and Combat.rank(p, "UPG_CHAIN") == 3, "Гроза: chain at the cap from the form")
	check(math.abs(p.stats.damage - Defs.Weapons.W_ARC_RIFLE.damage * 0.8) < 1e-6, "Гроза trade-off: −20% damage per bolt")
end

do -- M20 craft gate in the profile
	local pl = { UserId = 7, Name = "T7", Parent = true }
	Profile.load(pl)
	local d = Profile.get(pl)
	d.scrap = 10000
	d.mastery.W_ARC_RIFLE = Defs.masteryNeed("W_ARC_RIFLE", 20)
	check(not Profile.craftForm(pl, "EV_M20_STORM"), "M20 needs its feat")
	d.feats.W_ARC_RIFLE = { arcKills = 1500 }
	check(Profile.craftForm(pl, "EV_M20_STORM") and d.equip.W_ARC_RIFLE == "EV_M20_STORM", "M20 crafted and equipped with M20 + feat + Ксенит")
	check(Profile.equipForm(pl, "W_ARC_RIFLE", "") and d.equip.W_ARC_RIFLE == nil, "form can be unequipped (owned ≠ equipped)")
	d.s01 = true
	d.s01Stats = { hits = 600, kills = 0, crowds = 0 }
	check(Profile.setS01Branch(pl, "C") and Profile.s01Spec(pl).branch == "C" and Profile.s01Spec(pl).tier == 1, "S01 branch selectable at M5")
end

if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL PROGRESSION CHECKS PASSED")
