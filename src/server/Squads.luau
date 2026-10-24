--!strict
-- Squads in the camp (DD-053). Every hunter in a hub server is always in exactly one squad: alone by
-- default (closed, not on the board), or with others. A squad carries the same fields as the old
-- single lobby (ready, weapon, op, threat, mode, countdown…), so the lobby handlers run on it as is.
-- Plain tables only (players are any { UserId }), so tests/hub.luau drives it in Lune.

local Squads = {}
Squads.__index = Squads

Squads.Max = 4

export type Squad = {
	id: number,
	host: any,
	members: { any },
	open: boolean, -- listed on the board («набор открыт»)
	invited: { [number]: boolean }, -- user ids invited by the host (may join a closed squad)
	ready: { [any]: boolean },
	weapon: { [any]: string },
	op: string,
	threat: number,
	mode: string,
	countdown: number?,
	hold: boolean,
	launching: boolean,
	target: any?,
	candidates: any?,
	candidateData: any?,
	strikeAt: number?,
}

function Squads.new()
	return setmetatable({ byId = {}, of = {}, nextId = 0 }, Squads)
end

-- A fresh squad of one. `op` is the hunt it starts on (the player's next story hunt).
function Squads:solo(player, op: string): Squad
	self:remove(player)
	self.nextId += 1
	local sq: Squad = {
		id = self.nextId,
		host = player,
		members = { player },
		open = false,
		invited = {},
		ready = {},
		weapon = {},
		op = op,
		threat = 1,
		mode = "hunt",
		countdown = nil,
		hold = false,
		launching = false,
	}
	self.byId[sq.id] = sq
	self.of[player] = sq
	return sq
end

function Squads:get(id: number): Squad?
	return self.byId[id]
end

function Squads:squadOf(player): Squad?
	return self.of[player]
end

-- Take a player out of their squad. A squad left empty disappears; a host who leaves hands it on.
function Squads:remove(player)
	local sq = self.of[player]
	if not sq then
		return
	end
	self.of[player] = nil
	local i = table.find(sq.members, player)
	if i then
		table.remove(sq.members, i)
	end
	sq.ready[player] = nil
	sq.weapon[player] = nil
	if #sq.members == 0 then
		self.byId[sq.id] = nil
	elseif sq.host == player then
		sq.host = sq.members[1]
		sq.ready = {}
		sq.countdown = nil
	end
end

function Squads:canJoin(player, sq: Squad): (boolean, string?)
	if sq.launching then
		return false, "Отряд уже высаживается"
	elseif #sq.members >= Squads.Max then
		return false, "Отряд полон"
	elseif self.of[player] == sq then
		return false, "Ты уже в этом отряде"
	elseif not sq.open and not sq.invited[player.UserId] then
		return false, "Набор закрыт"
	end
	return true, nil
end

-- Join; the old squad is left (and dissolves if it was a solo one). Returns ok, reason.
function Squads:join(player, id: number): (boolean, string?)
	local sq = self.byId[id]
	if not sq then
		return false, "Отряд распущен"
	end
	local ok, why = self:canJoin(player, sq)
	if not ok then
		return false, why
	end
	self:remove(player)
	table.insert(sq.members, player)
	self.of[player] = sq
	sq.invited[player.UserId] = nil
	-- someone new: whoever was ready waits a moment for them
	if sq.countdown then
		sq.countdown = math.max(sq.countdown, 15)
	end
	return true, nil
end

-- Leave for a fresh solo squad.
function Squads:leave(player, op: string): Squad
	return self:solo(player, op)
end

-- Open squads with room, fullest first (they are the closest to launching).
function Squads:board(): { Squad }
	local out = {}
	for _, sq in self.byId do
		if sq.open and not sq.launching and #sq.members < Squads.Max then
			table.insert(out, sq)
		end
	end
	table.sort(out, function(a, b)
		if #a.members ~= #b.members then
			return #a.members > #b.members
		end
		return a.id < b.id
	end)
	return out
end

-- «Подобрать отряд»: the best open squad this player can play with; else open their own recruitment.
-- canPlay(player, squad) -> boolean (the hunt is unlocked for them, etc.).
function Squads:match(player, canPlay): (string, Squad?)
	for _, sq in self:board() do
		if self.of[player] ~= sq and canPlay(player, sq) then
			local ok = self:join(player, sq.id)
			if ok then
				return "joined", sq
			end
		end
	end
	local own = self.of[player]
	if own then
		own.open = true
	end
	return "opened", own
end

function Squads:all(): { Squad }
	local out = {}
	for _, sq in self.byId do
		table.insert(out, sq)
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

return Squads
