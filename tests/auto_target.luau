-- DD-103: the simple phone fight's target choice per gun (Shared.AutoTarget).
-- Usage: lune run tests/auto_target
local H = require("./harness")
local AutoTarget = H.require("src/shared/AutoTarget")

local failures = 0
local function check(ok, msg)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

local function e(x, z)
	return { dx = x, dz = z, radius = 1.2 }
end

-- one lone runner close on the left, a knot of five a bit further on the right
local field = { [1] = e(-8, 0) }
for i = 0, 4 do
	field[10 + i] = e(14 + i * 0.6, (i - 2) * 0.8)
end
local id = AutoTarget.pick("shotgun", field, 0, 0, 44, nil)
check(id ~= nil and id >= 10, "shotgun takes the knot over the lone nearer runner (got " .. tostring(id) .. ")")

-- a line of four straight ahead, a lone runner nearer off to the side
local line = { [1] = e(0, 9) }
for i = 0, 3 do
	line[20 + i] = e(12 + i * 4, 0.2 * i)
end
id = AutoTarget.pick("rail", line, 0, 0, 115, nil)
check(id == 20, "rail takes the head of the line over the nearer lone runner (got " .. tostring(id) .. ")")

-- with no crowd, both take the nearest
local two = { [1] = e(5, 0), [2] = e(-20, 0) }
check(AutoTarget.pick("shotgun", two, 0, 0, 44, nil) == 1, "shotgun with no knot takes the nearest")
check(AutoTarget.pick("rail", two, 0, 0, 115, nil) == 1, "rail with no line takes the nearest")

-- the held target stays while a rival is only a little better
local pair = { [1] = e(10, 0), [2] = e(-9.5, 0) }
check(AutoTarget.pick("shotgun", pair, 0, 0, 44, 1) == 1, "the held target holds against a slightly nearer rival")
local far = { [1] = e(30, 0), [2] = e(-5, 0) }
check(AutoTarget.pick("shotgun", far, 0, 0, 44, 1) == 2, "the held target gives way to a much nearer one")

-- out of range: nothing
check(AutoTarget.pick("shotgun", { [1] = e(60, 0) }, 0, 0, 44, nil) == nil, "nothing in range: no target")

-- a full swarm stays cheap: 400 enemies, 200 picks
local swarm = {}
for i = 1, 400 do
	swarm[i] = e(math.cos(i) * (5 + i % 40), math.sin(i * 1.3) * (5 + i % 37))
end
local t0 = os.clock()
for _ = 1, 200 do
	AutoTarget.pick("rail", swarm, 0, 0, 115, nil)
end
local ms = (os.clock() - t0) / 200 * 1000
check(ms < 2, string.format("400 enemies: %.2f ms a pick (under 2)", ms))

print(if failures == 0 then "ALL AUTO TARGET CHECKS PASSED" else failures .. " FAILED")
if failures > 0 then
	error("auto target checks failed")
end
