local H = require("./harness")
local Rooms = H.require("src/server/ShelterRooms")
local Showcase = H.require("src/shared/Showcase")
local Codec = H.require("src/shared/Codec")
assert(Codec.isUserId(7999064779) and Codec.isUserId(123456789), "real account ids exceed coordinate limits")
assert(Codec.isUserId(-2, true) and not Codec.isUserId(-2, false), "simulated ids are Studio-only")
for _, id in { 0, 1.5, 0 / 0, math.huge, -math.huge, 9007199254740992, "123" } do
	assert(not Codec.isUserId(id, true), "reject malformed ids")
end
local r = Rooms.new()
for _, id in { 1, 2, 3, 4 } do
	r:add(id)
end
assert(not r:visit(1, 999) and r:owner(1) == 1, "cannot visit an absent owner")
assert(r:visit(2, 1) and r:visit(3, 1))
assert(r:owner(1) == r:owner(2) and r:owner(2) == r:owner(3), "host and guests share one room")
assert(r:owner(4) ~= r:owner(1), "another survivor keeps their own home")
assert(r:visit(2, 2) and r:owner(2) == 2, "return home is independent of the host")
local returned = r:remove(1)
assert(#returned == 1 and returned[1] == 3 and r:owner(3) == 3, "owner leaving returns remaining guests safely")
assert(not r:visit(2, 1), "departed owner is no longer visitable")
local hunters = { { id = 4 }, { id = 3, newbie = true }, { id = 1, newbie = true }, { id = 2 } }
local seen = {}
for rotation = 0, 15 do
	local id = Showcase.featured(hunters, rotation)
	seen[id] = true
	if rotation % 2 == 0 then
		assert(id == 1 or id == 3, "newcomers receive a regular spotlight")
	end
end
for _, h in hunters do
	assert(seen[h.id], "each online hunter receives a spotlight")
end
assert(Showcase.featured({}, 0) == nil)
print("ALL SHELTER ROOM CHECKS PASSED: visits, shared membership, return, departure, absent target, fair discovery")
