-- DD-105: the weapon supers (Sim/Super): charge, each weapon's effect, no self-charging.
-- Usage: lune run tests/supers
local H = require("./harness")
local World = H.require("src/server/Sim/World")
local Defs = H.require("src/shared/Defs")

local failures = 0
local function check(ok, msg)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

local DT = 1 / 30

-- A started O02 run with one hero at the centre, nothing else of note close by.
local function world(weapon: string)
	local w = World.new({
		seed = 4242,
		players = { { id = 1, name = "T", weapon = weapon, s01 = true } },
		op = "O02",
		threat = 1,
	})
	w:setAim(1, 0, 1, true)
	local guard = 0
	while w.phase ~= "ACTIVE" and guard < 600 do
		w:step(DT)
		guard += 1
	end
	w:setAim(1, 0, 1, false)
	local p = w.players[1]
	p.iframeUntil = math.huge -- (the test hero is not the subject)
	for _, e in w.enemies do
		e.alive = false
	end
	return w, p
end

-- A tough, still runner `ahead` of the hero (along +X: open ground at the O02 spawn, +Z has the drill
-- 20 studs off) and `side` to its left.
local function dummy(w, p, side: number, ahead: number)
	local e = w:spawnEnemy("EN_RUNNER", p.x + ahead, p.z + side)
	e.hp, e.maxHp = 1e6, 1e6
	e.speedMult = 0
	return e
end

local function run(w, seconds: number)
	for _ = 1, math.floor(seconds / DT) do
		w:step(DT)
	end
end

local function hurt(e): number
	return 1e6 - e.hp
end

-- charge
do
	local w, p = world("W_ARC_RIFLE")
	check(math.abs(p.super - Defs.Super.Start) < 1e-6, "a run starts half charged")
	check(not w:super(1, 1, 0), "a half-charged super does not fire")
	local e = dummy(w, p, 0, 15)
	p.super = 0
	w:setAim(1, 1, 0, true)
	run(w, 3)
	w:setAim(1, 1, 0, false)
	check(p.super > 0.1 and p.super < 1, string.format("firing charges it (%.2f after 3 s)", p.super))
	local _ = e
end

-- rifle: the ball bursts on the first enemy ahead, stuns, arcs on
do
	local w, p = world("W_ARC_RIFLE")
	local front = dummy(w, p, 0, 20)
	local side = dummy(w, p, 4, 22)
	local far = dummy(w, p, 14, 26)
	local behind = dummy(w, p, 0, -20)
	p.super = 1
	check(w:super(1, 1, 0), "a full super fires")
	check(p.super == 0, "casting empties the bar")
	run(w, 1)
	check(hurt(front) >= Defs.Supers.W_ARC_RIFLE.damage * 0.99, "МОЛНИЯ: the enemy it hits takes the burst")
	check(hurt(side) > 0, "МОЛНИЯ: the burst catches the one beside it")
	check(hurt(far) > 0, "МОЛНИЯ: an arc jumps on to one further off")
	check(hurt(behind) == 0, "МОЛНИЯ: nothing behind the hero is touched")
	check(p.super < 0.01, "the super's own damage does not charge it")
end

-- shotgun: a wide cone in front throws the swarm back
do
	local w, p = world("W_SCATTERGUN")
	local front = dummy(w, p, 3, 8)
	local behind = dummy(w, p, 0, -8)
	run(w, 1.5) -- (they climb out first: a spawning enemy is not in the spatial grid yet)
	local d0 = math.sqrt((front.x - p.x) ^ 2 + (front.z - p.z) ^ 2)
	p.super = 1
	w:super(1, 1, 0)
	local d1 = math.sqrt((front.x - p.x) ^ 2 + (front.z - p.z) ^ 2)
	check(hurt(front) >= Defs.Supers.W_SCATTERGUN.damage * 0.99, "ЗАЛП: the enemy in the cone takes it")
	check(d1 > d0 + 5, string.format("ЗАЛП: and is thrown back (%.1f → %.1f)", d0, d1))
	check(hurt(behind) == 0, "ЗАЛП: the one behind is not")
	check(p.iframeUntil > w.t, "ЗАЛП: the hero is untouchable for a moment")
end

-- beam: three seconds of a wide piercing beam with no heat
do
	local w, p = world("W_PLASMA_BEAM")
	local a, b, c = dummy(w, p, 0, 10), dummy(w, p, 2, 25), dummy(w, p, -2, 40)
	local off = dummy(w, p, 12, 20)
	run(w, 1.5) -- (they climb out first: a spawning enemy is not in the spatial grid yet)
	p.super = 1
	w:super(1, 1, 0)
	run(w, 1.5)
	check(
		hurt(a) > 0 and hurt(b) > 0 and hurt(c) > 0,
		string.format("ПРОЖИГ: every enemy along the beam burns (%d %d %d)", hurt(a), hurt(b), hurt(c))
	)
	check(hurt(off) == 0, "ПРОЖИГ: one off the line does not")
	check(p.heat < 5 and p.overheatT <= 0, "ПРОЖИГ: no heat")
	run(w, 2)
	check(p.superBeamUntil == nil, "ПРОЖИГ: it ends after its three seconds")
end

-- rail: the whole line to the wall, then a burning strip
do
	local w, p = world("W_RAILGUN")
	local hit = {}
	for i = 1, 4 do
		hit[i] = dummy(w, p, 0, i * 12)
	end
	local off = dummy(w, p, 8, 30)
	run(w, 1.5) -- (they climb out first: a spawning enemy is not in the spatial grid yet)
	p.super = 1
	w:super(1, 1, 0)
	local all = true
	for _, e in hit do
		all = all and hurt(e) >= Defs.Supers.W_RAILGUN.damage * 0.99
	end
	check(all, "РАЗГОН: all four in the line take the full shot")
	check(hurt(off) == 0, "РАЗГОН: one off the line does not")
	check(#w.superStrips == 1, "РАЗГОН: it leaves a burning strip")
	local late = dummy(w, p, 0.5, 20)
	run(w, 2)
	check(late.burnUntil > w.t, "РАЗГОН: an enemy walking onto the strip catches fire")
	check(p.super < 0.01, "the strip's burn does not charge the super back")
	run(w, Defs.Supers.W_RAILGUN.strip)
	check(#w.superStrips == 0, "РАЗГОН: the strip burns out")
end

print(if failures == 0 then "ALL SUPER CHECKS PASSED" else failures .. " FAILED")
if failures > 0 then
	error("super checks failed")
end
