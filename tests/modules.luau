-- Weapon module checks (D03 §3 / DD-010): 36 modules, loadout rules, virtual card ranks in the sim.
-- Usage (repo root):  lune run tests/modules
local process = require("@lune/process")
local H = require("./harness")
local Modules = H.require("src/shared/Modules")
local Defs = H.require("src/shared/Defs")
local World = H.require("src/server/Sim/World")
local Combat = H.require("src/server/Sim/Combat")

local failures = 0
local function check(ok: boolean, msg: string)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

local count = 0
for _, m in Modules.All do
	count += 1
	for k in m.ranks do
		assert(Defs.Upgrades[k], m.id .. ": unknown card family " .. k)
	end
end
check(count == 36, "36 modules (4 weapons × 3 branches × 3 tiers)")

check(Modules.validLoadout("W_ARC_RIFLE", "MOD_ARC_RIFLE_A3", "MOD_ARC_RIFLE_B2"), "CORE III + ADAPTER II from another branch is valid")
check(not Modules.validLoadout("W_ARC_RIFLE", "MOD_ARC_RIFLE_A1", "MOD_ARC_RIFLE_A2"), "ADAPTER from the same branch is rejected")
check(not Modules.validLoadout("W_ARC_RIFLE", "MOD_ARC_RIFLE_A1", "MOD_ARC_RIFLE_B3"), "tier III ADAPTER is rejected")
check(not Modules.validLoadout("W_ARC_RIFLE", "MOD_RAILGUN_A1", nil), "module of another weapon is rejected")

-- Sim: a chain module gives effective UPG_CHAIN without using a card slot; the family caps at III.
local w = World.new({ seed = 3, op = "O01", players = { { id = 1, weapon = "W_ARC_RIFLE", loadout = { core = "MOD_ARC_RIFLE_B3", adapter = "MOD_ARC_RIFLE_C2" } } } })
local p = w.playerList[1]
check(Combat.rank(p, "UPG_CHAIN") == 2 and Combat.cardRank(p, "UPG_CHAIN") == 0 and p.slots == 0, "module chain rank 2, no slot used")
check(
	math.abs(p.stats.rate - Defs.Weapons.W_ARC_RIFLE.rate * 1.1 * 1.1) < 1e-6,
	"adapter stat tweaks applied, its branch's tiers add up (C1 + C2: +10% rate each, DD-112)"
)
-- DD-112: a tier II keeps tier I's effect, and every fitted module adds raw power by its tier
do
	local w2 = World.new({ seed = 3, op = "O01", players = { { id = 1, weapon = "W_ARC_RIFLE", loadout = { core = "MOD_ARC_RIFLE_A2" } } } })
	local p2 = w2.playerList[1]
	check(Combat.rank(p2, "UPG_MULTISHOT") == 1, "«Фокусировка II» keeps the second bolt of «Двойная катушка I»")
	local want = Defs.Weapons.W_ARC_RIFLE.damage * (1 + Modules.Power[2]) * 1.1
	check(math.abs(p2.stats.damage - want) < 1e-6, "tier II power and its own +10% damage")
end
p.ranks.UPG_CHAIN = 1
p.slots = 1
check(Combat.rank(p, "UPG_CHAIN") == 3, "card + module ranks add up to the cap")
p.ranks.UPG_CHAIN = 2
check(Combat.rank(p, "UPG_CHAIN") == 3, "never above the shared cap III")
for _ = 1, 30 do
	Combat.makeOffer(w, p)
	assert(not table.find(p.offer.choices, "UPG_CHAIN"), "capped family offered")
end
check(true, "a family at the cap is never offered")

if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL MODULE CHECKS PASSED")
