-- The Last Grove (DD-087): the ring of plots must not overlap, the square and the roads stay clear, and
-- the plot rules (own plot back, next to friends, holds, eviction) hold.
-- Usage: lune run tests/grove
local H = require("./harness")
local Grove = H.require("src/shared/Grove")
local Layout = H.require("src/shared/ShelterLayout")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local failures = 0
local function check(ok, msg)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

-- Everything that stands in a shelter, as discs { x, z, radius, what } in shelter coordinates.
local DECOR_R = { SHELTER = 12, OAK = 7, BIRCH = 4, BUSH = 2, RUIN_WALL = 4, CAR_WRECK = 4, CRATES = 2 }
local function footprint()
	local out = {}
	local function add(x, z, r, what)
		table.insert(out, { x = x, z = z, r = r, what = what })
	end
	for key, s in Layout.Stations do
		add(s.x, s.z, 5, "station " .. key)
	end
	for id, s in Layout.Spots do
		add(s.x, s.z, 5, "spot " .. id)
	end
	for i, l in Layout.Lamps do
		add(l[1], l[2], 1.5, "lamp " .. i)
	end
	for _, d in Layout.Decor do
		add(d[3], d[4], DECOR_R[d[1]] or 3, d[1])
	end
	add(Layout.Terminal.x, Layout.Terminal.z, 5, "terminal")
	add(Layout.Cave.x, Layout.Cave.z, 15, "cave")
	for i in Layout.Trophies do
		add(Layout.trophyX(i), Layout.ShowZ, 3, "trophy " .. i)
	end
	add(-2, Layout.ShowZ, 3, "gun stand")
	add(Layout.SiegeX, Layout.ShowZ, 3, "siege")
	add(Layout.RangeMark.x, Layout.RangeMark.z, 5, "range")
	for i, d in Layout.RangeDummies do
		add(d[1], d[2], 2, "dummy " .. i)
	end
	add(Layout.Sign.x, Layout.Sign.z, 2, "sign")
	local lab, deck = Layout.Spots.LAB, Layout.GalleryDeck
	for _, cx in { -0.5, 0, 0.5 } do
		for _, cz in { -0.5, 0, 0.5 } do
			add(lab.x + deck.x + cx * deck.sx, lab.z + deck.z + cz * deck.sz, 4, "gallery")
		end
	end
	return out
end
local FOOT = footprint()

local function world(i, p)
	local w = Grove.at(Grove.frame(i), p.x, 0, p.z)
	return Vector3.new(w.X, 0, w.Z)
end

print("=== layout")
local f1 = Grove.frame(1)
local c = Vector3.new(Grove.Center.X, 0, Grove.Center.Z)
local gate = Grove.at(f1, 0, 0, -30)
check((gate - c).Magnitude < (f1.Position - c).Magnitude, "the gate faces the Tree")
check(math.abs((f1.Position - c).Magnitude - Grove.Radius) < 0.01, "plots stand on the ring")

local worst, worstWhat = math.huge, ""
for i = 1, Grove.Plots do
	for j = i + 1, Grove.Plots do
		for _, a in FOOT do
			local wa = world(i, a)
			for _, b in FOOT do
				local gap = (wa - world(j, b)).Magnitude - a.r - b.r
				if gap < worst then
					worst = gap
					worstWhat = string.format("plot %d %s / plot %d %s", i, a.what, j, b.what)
				end
			end
		end
	end
end
print(string.format("    closest neighbours: %.1f studs (%s)", worst, worstWhat))
check(worst >= 6, "neighbouring plots keep at least 6 studs apart")

local square = math.huge
for i = 1, Grove.Plots do
	for _, a in FOOT do
		square = math.min(square, (world(i, a) - c).Magnitude - a.r - Grove.PlazaRadius)
	end
end
check(square >= 4, string.format("nothing of a plot stands on the square (clear by %.1f)", square))

-- the road from each gate to the square: no other plot's things on it
local blocked = nil
for i = 1, Grove.Plots do
	local g = world(i, { x = 0, z = -30 })
	local dir = (c - g).Unit
	local len = (c - g).Magnitude - Grove.PlazaRadius
	for j = 1, Grove.Plots do
		if j ~= i then
			for _, a in FOOT do
				local p = world(j, a) - g
				local along = p:Dot(dir)
				local side = (p - dir * along).Magnitude
				if along > 0 and along < len and side < 7 + a.r then
					blocked = string.format("plot %d road / plot %d %s", i, j, a.what)
				end
			end
		end
	end
end
check(blocked == nil, "every road to the square is clear" .. (if blocked then " (" .. blocked .. ")" else ""))
check(
	Grove.plotAt(Grove.frame(3).Position) == 3 and Grove.plotAt(Grove.Center) == nil,
	"plotAt finds a plot, not the square"
)
check(Grove.onSquare(Grove.Fire) and Grove.onSquare(Grove.Board), "fire and chronicle stand on the square")

print("=== plot rules")
local plots = Grove.newPlots()
local a = Grove.assign(plots, 101, nil, 0)
local b = Grove.assign(plots, 102, nil, 0)
check(a == 1 and Grove.ringDistance(a, b) == 1, "the second hunter moves in next door (" .. tostring(b) .. ")")
local cc = Grove.assign(plots, 103, nil, 0)
check(Grove.ringDistance(cc, a) == 1 or Grove.ringDistance(cc, b) == 1, "the third one joins the row")
local friendPlot = Grove.assign(plots, 104, { 101 }, 0)
check(Grove.ringDistance(friendPlot, a) <= 2, "a friend lands near their friend (" .. friendPlot .. ")")
check(Grove.assign(plots, 101, nil, 5) == a, "coming back gives the same plot")
Grove.release(plots, 102, 10, true)
check(plots[b].uid == 102 and plots[b].away == 10, "out on a fight: the plot is held")
check(Grove.assign(plots, 102, nil, 100) == b and plots[b].away == nil, "back from the fight: same plot")
Grove.release(plots, 102, 200, true)
local gone = Grove.expire(plots, 200 + Grove.Hold + 1)
check(#gone == 1 and gone[1] == 102 and plots[b].uid == nil, "a hold that runs out frees the plot")
Grove.release(plots, 103, 300, false)
check(Grove.plotOf(plots, 103) == nil, "leaving the game frees the plot at once")
-- a full ring: the one away longest gives way
local full = Grove.newPlots()
for i = 1, Grove.Plots do
	Grove.assign(full, 200 + i, nil, 0)
end
Grove.release(full, 203, 50, true)
Grove.release(full, 205, 40, true)
local took = Grove.assign(full, 999, nil, 60)
check(
	took == Grove.plotOf(full, 999) and full[took].uid == 999 and Grove.plotOf(full, 205) == nil,
	"full: the longest away gives way"
)
local none = Grove.newPlots()
for i = 1, Grove.Plots do
	Grove.assign(none, 300 + i, nil, 0)
end
check(Grove.assign(none, 777, nil, 1) == nil, "full and nobody away: a lodger, no plot")

print("=== chronicle")
local Chronicle = H.require("src/shared/Chronicle")
local before = Chronicle.summary({ wins_by_op = {}, research = {}, outpost = { best = 0 }, home = {} })
local after = Chronicle.summary({
	wins_by_op = { O01 = 1, O05 = 1 },
	research = { EN_RUNNER = 99999 },
	outpost = { best = 3 },
	home = { GARDEN = true, GENERATOR = true },
})
local lines = Chronicle.diff(before, after, "Аня")
local text = {}
for _, l in lines do
	table.insert(text, l.text)
end
local all = table.concat(text, " / ")
print("    " .. all)
check(all:find("первая Альфа") ~= nil and all:find("Мать роя") ~= nil, "boss wins make the chronicle")
check(all:find("уровне 3") ~= nil, "a better drill defence makes it")
check(
	all:find("эталон") ~= nil and all:find("полный образец") == nil,
	"a jump to an exemplar says the exemplar only"
)
check(
	all:find("Огород") ~= nil and all:find("Генератор") == nil,
	"a bought spot is news, a free one is not"
)
check(#Chronicle.diff(after, after, "Аня") == 0, "nothing new, nothing written")
local m4 = table.clone(after)
m4.mentor = 4
local m5 = table.clone(after)
m5.mentor = 5
local ml = Chronicle.diff(m4, m5, "Аня")
check(
	#ml == 1 and ml[1].text:find("Наставник рощи") ~= nil and ml[1].big,
	"the fifth fight with a newcomer makes a mentor (DD-088)"
)
local k1 = Chronicle.status({ away = "«Мать роя»", open = true })
local k2 = Chronicle.status({ open = true, squadWith = "Костя" })
local k3, t3 = Chronicle.status({})
check(k1 == "away" and k2 == "open" and k3 == "home" and t3 == "Дома", "status priority: away > open > … > home")
local now = 1800000000
check(
	Chronicle.provenance({ t = now - 60, team = 1, with = {} }, now)
		== "Добыт сегодня · в одиночку",
	"provenance: today, alone"
)
check(
	Chronicle.provenance({ t = now - 3 * 86400, team = 2, with = { "Костя" } }, now)
		:find("в отряде: Костя") ~= nil,
	"provenance names the squad"
)
check(Chronicle.provenance(nil, now) == "Трофей добыт", "an old trophy without a log still reads")

print(if failures == 0 then "ALL PASS" else string.format("%d FAILURE(S)", failures))
if failures > 0 then
	error("grove failed")
end
