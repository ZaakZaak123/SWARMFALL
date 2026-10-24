-- Camp squads and the showcase (DD-053): pure rules, no Instances.
-- Usage: lune run tests/hub
local H = require("./harness")
local Squads = H.require("src/server/Squads")
local Showcase = H.require("src/shared/Showcase")

local failures = 0
local function check(ok, msg)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

local function P(id)
	return { UserId = id, Name = "P" .. id }
end
local a, b, c, d, e = P(1), P(2), P(3), P(4), P(5)

print("=== squads")
local s = Squads.new()
local sa = s:solo(a, "O02")
s:solo(b, "O01")
s:solo(c, "O01")
check(#s:board() == 0, "solo squads are not on the board")
local ok, why = s:join(b, sa.id)
check(not ok and why == "Набор закрыт", "a closed squad can't be joined uninvited")
sa.invited[b.UserId] = true
ok = s:join(b, sa.id)
check(ok and #sa.members == 2 and s:squadOf(b) == sa, "an invited hunter joins; their solo squad dissolves")
check(#s:all() == 2, "two squads left (a+b, c)")
sa.open = true
check(#s:board() == 1, "an open squad is on the board")
local res, joined = s:match(c, function()
	return true
end)
check(res == "joined" and joined == sa and #sa.members == 3, "«Подобрать отряд» joins the open squad")
s:solo(d, "O01")
s:join(d, sa.id)
check(#sa.members == 4 and #s:board() == 0, "a full squad leaves the board")
s:solo(e, "O01")
local r2 = s:match(e, function()
	return true
end)
check(r2 == "opened" and s:squadOf(e).open, "no room anywhere: own recruitment opens")
s:remove(a)
check(sa.host == b and #sa.members == 3, "the host leaves: the next member leads")
s:leave(c, "O01")
check(#sa.members == 2 and s:squadOf(c) ~= sa and #s:squadOf(c).members == 1, "leaving gives a fresh solo squad")
sa.launching = true
local ok3 = s:join(c, sa.id)
check(not ok3, "a launching squad takes no one")

print("=== showcase")
local prof = {
	wins = 7,
	wins_by_op = { O01 = 2, O02 = 1, O03 = 1, O05 = 1 },
	mastery = { W_ARC_RIFLE = 900 },
	outpost = { slots = { [4] = { id = "STING", lvl = 2 } }, best = 4 },
	raid = { rating = 1100, wins = 2 },
	likes = 3,
}
local entry = Showcase.build(1, "Ann", prof, "W_ARC_RIFLE", nil)
print("  title: " .. entry.title .. "  trophies: " .. #entry.trophies .. "  M" .. entry.mastery)
check(entry.title == "Победил Мать роя", "title is the hardest deed")
check(entry.slots["4"] ~= nil and entry.slots["4"].id == "STING", "outpost slots travel with string keys")
check(entry.power > 0 and entry.likes == 3 and not entry.newbie, "power, likes, veteran")
local fresh =
	Showcase.build(2, "New", { wins_by_op = {}, mastery = {}, outpost = { slots = {}, best = 0 } }, "W_ARC_RIFLE", nil)
check(
	fresh.title == "Новобранец" and fresh.newbie and #fresh.trophies == 0,
	"a newcomer is «Новобранец», no trophies"
)
check(
	Showcase.squadTitle("siege", "", 0, 4) == "Защитить мой аванпост · осада 4",
	"board line for a siege"
)

print("=== awards")
local aw = Showcase.awards({
	{ id = 1, damage = 9000, kills = 300, revives = 0, bigDamage = 100, guardKills = 3, bestCombo = 9, alive = true },
	{ id = 2, damage = 2000, kills = 80, revives = 2, bigDamage = 900, guardKills = 40, bestCombo = 3, alive = true },
	{ id = 3, damage = 500, kills = 20, revives = 0, bigDamage = 0, guardKills = 1, bestCombo = 2, alive = false },
})
for id = 1, 3 do
	local names = {}
	for _, a in aw[id] or {} do
		table.insert(names, a[2])
	end
	print("  " .. id .. ": " .. table.concat(names, ", "))
end
check(aw[2] and aw[2][1][2] == "Спаситель · 2" and aw[2][2][2] == "Защитник бура", "help comes first: rescues and guarding the drill")
check(aw[1] and aw[1][1][2] == "Главный калибр", "the top gun is noticed")
check(aw[3] ~= nil and #aw[3] == 1, "everyone is noticed for something")
check(next(Showcase.awards({ { id = 1, damage = 1 } })) == nil, "no awards in a solo run")

if failures > 0 then
	print(failures .. " FAILURE(S)")
else
	print("ALL HUB CHECKS PASSED")
end
