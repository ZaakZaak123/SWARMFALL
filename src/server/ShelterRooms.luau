--!strict
-- Safe, lightweight rooms inside one public settlement. Every client renders only its current
-- owner's shelter on the shared terrain. Membership is authoritative; only people in the same room
-- see each other. No extra world copies, physics assemblies or persistent resources are needed.
local Rooms = {}
Rooms.__index = Rooms

function Rooms.new()
	return setmetatable({ members = {} :: { [number]: number } }, Rooms)
end

function Rooms:add(id: number)
	self.members[id] = self.members[id] or id
end

function Rooms:visit(id: number, owner: number): boolean
	if self.members[id] == nil or self.members[owner] == nil then
		return false
	end
	self.members[id] = owner
	return true
end

function Rooms:owner(id: number): number
	return self.members[id] or id
end

function Rooms:remove(id: number): { number }
	self.members[id] = nil
	local returned = {}
	for guest, owner in self.members do
		if owner == id then
			self.members[guest] = guest
			table.insert(returned, guest)
		end
	end
	return returned
end

return Rooms
