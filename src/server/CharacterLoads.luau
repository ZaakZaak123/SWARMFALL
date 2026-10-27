--!nonstrict
-- LoadCharacter yields. Serialize loads per player and discard superseded destinations.
local CharacterLoads = {}
CharacterLoads.__index = CharacterLoads

function CharacterLoads.new()
	return setmetatable({ requests = {}, busy = {} }, CharacterLoads)
end

function CharacterLoads:cancel(player)
	self.requests[player] = nil
end

function CharacterLoads:run(player, load)
	local request = {}
	self.requests[player] = request
	local function current()
		return player.Parent ~= nil and self.requests[player] == request
	end
	while self.busy[player] do
		if not current() then
			return
		end
		task.wait()
	end
	if not current() then
		return
	end
	self.busy[player] = true
	local ok, err = pcall(load, current)
	self.busy[player] = nil
	if self.requests[player] == request then
		self.requests[player] = nil
	end
	if not ok then
		warn("[SWARMFALL] character preparation failed", err)
	end
end

return CharacterLoads
