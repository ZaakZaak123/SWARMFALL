-- Joining a running drill defence (DD-088): only in a breather between waves, never into a story sortie,
-- the joiner catches up in cards and the run resolves for everyone.
-- Usage: lune run tests/join
local H = require("./harness")
local Bot = require("./bot")
local World = H.require("src/server/Sim/World")
local Ops = H.require("src/shared/Ops")
local Meta = H.require("src/shared/Meta")

local failures = 0
local function check(ok, msg)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

print("=== story sorties take no one mid-fight")
local hunt = World.new({ seed = 3, op = "O01", players = { { id = 1, name = "A", weapon = "W_ARC_RIFLE" } } })
hunt:step(8)
hunt.t = 60
check(not hunt:canJoin(), "O01: no joining")

print("=== drill defence: a neighbour steps in during a breather")
local slots = { [4] = { id = "STING", lvl = 2 }, [1] = { id = "STING", lvl = 1 } }
local joinedAt, joinedWave, earlyRefused, cards, levelAt = nil, nil, nil, nil, nil
local out = Bot.run("W_ARC_RIFLE", 1, 21, false, nil, 1, nil, {
	opDef = Ops.makeSiege(1),
	structures = slots,
	orbit = 26,
	s01 = true,
	onTick = function(w)
		if w.phase == "ACTIVE" and w.t > 12 and w.t < 20 and earlyRefused == nil then
			earlyRefused = w:addPlayer({ id = 2, name = "JOINER", weapon = "W_ARC_RIFLE", s01 = true }) == nil
		end
		if not joinedAt and w:canJoin() then
			local p = w:addPlayer({ id = 2, name = "JOINER", weapon = "W_ARC_RIFLE", s01 = true })
			if p then
				joinedAt = w.t
				local _, ph = w:currentPhaseDef()
				joinedWave = ph.wave
				cards = p.pending
				levelAt = w.level
			end
		end
	end,
})
local r = out.result
check(earlyRefused == true, "mid-wave (0:12–0:20): refused")
check(
	joinedAt ~= nil,
	string.format("joined in a breather at %s after wave %s", Bot.fmt(joinedAt or 0), tostring(joinedWave))
)
check(
	cards == math.min((levelAt or 1) - 1, 4),
	string.format("catch-up cards: %s at squad level %s", tostring(cards), tostring(levelAt))
)
check(r ~= nil and #r.players == 2, "the result has both hunters")
local joiner = nil
for _, p in r and r.players or {} do
	if p.id == 2 then
		joiner = p
	end
end
check(
	joiner ~= nil and (joiner.kills or 0) > 0,
	"the joiner fought (" .. tostring(joiner and joiner.kills) .. " kills)"
)
check(r ~= nil and r.victory, "the defence still holds (" .. Bot.fmt(r and r.time or 0) .. ")")
local _ = Meta

print(if failures == 0 then "ALL PASS" else string.format("%d FAILURE(S)", failures))
if failures > 0 then
	error("join failed")
end
