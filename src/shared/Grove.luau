--!strict
-- The Last Grove (DD-087): one settlement per public server. The old Tree and its square in the middle,
-- eight plots in a ring round it, every shelter's gate facing the Tree and a road from the gate to the
-- square; a hill with the old metro's mouth between each two plots (the plot's cableway comes out of
-- it). A plot is only a place on this server: the home belongs to the profile, and a hunter who flies
-- out to a fight keeps the plot for a while (Grove.Hold) so they come back to the same spot.
-- Pure: the layout and the plot rules are walked by tests/grove in Lune.

local Meta = require(script.Parent.Meta)

local Grove = {}

Grove.Center = Meta.HomeOrigin -- the Tree
Grove.Plots = 8
Grove.Radius = 185 -- plot centre (courtyard) from the Tree
Grove.PlazaRadius = 36
Grove.Reach = 64 -- how far a plot's own things stand from its courtyard centre (its area)
Grove.Hold = 360 -- seconds a plot waits for an owner out on a fight

-- The square's posts (DD-087), around the Tree: the gathering fire (squads) and the chronicle board.
-- Angles count from plot 1's road, the way the plots do.
local function onSquare(angle: number, r: number): Vector3
	return Grove.Center + Vector3.new(math.sin(angle), 0, -math.cos(angle)) * r
end
Grove.Fire = onSquare(math.rad(22.5), 24)
Grove.Board = onSquare(math.rad(-22.5), 25)
Grove.WeekBoard = onSquare(math.rad(-67.5), 25) -- DD-088: the week's best, beside the chronicle

-- The shelter frame of plot i: the courtyard centre, local -Z towards the Tree (the gate side).
function Grove.frame(i: number): CFrame
	local a = (i - 1) / Grove.Plots * math.pi * 2
	local p = Grove.Center + Vector3.new(math.sin(a), 0, -math.cos(a)) * Grove.Radius
	-- LookVector (-Z) = (-sin a, 0, cos a): straight at the Tree (an explicit yaw: Lune's lookAt differs)
	return CFrame.new(p) * CFrame.Angles(0, math.pi - a, 0)
end

-- The yaw of plot i's frame (what CFrame.Angles(0, yaw, 0) turns shelter coordinates by).
function Grove.yaw(i: number): number
	return math.pi - (i - 1) / Grove.Plots * math.pi * 2
end

-- Shelter coordinates (ShelterLayout) -> world, for plot frame `f`.
function Grove.at(f: CFrame, x: number, y: number, z: number): Vector3
	return f:PointToWorldSpace(Vector3.new(x, y, z))
end

-- Which plot's area a world point is in (nil: the square, the roads between, the woods).
function Grove.plotAt(pos: Vector3): number?
	for i = 1, Grove.Plots do
		local p = Grove.frame(i).Position
		if Vector3.new(pos.X - p.X, 0, pos.Z - p.Z).Magnitude < Grove.Reach then
			return i
		end
	end
	return nil
end

function Grove.onSquare(pos: Vector3): boolean
	return Vector3.new(pos.X - Grove.Center.X, 0, pos.Z - Grove.Center.Z).Magnitude < Grove.PlazaRadius + 6
end

-- Steps round the ring between two plots (1 = next door).
function Grove.ringDistance(a: number, b: number): number
	local d = math.abs(a - b) % Grove.Plots
	return math.min(d, Grove.Plots - d)
end

-- Plot rules -------------------------------------------------------------------------------------------
export type Plot = { uid: number?, since: number, away: number? } -- away: os time the owner flew out

function Grove.newPlots(): { Plot }
	local plots = {}
	for i = 1, Grove.Plots do
		plots[i] = { uid = nil, since = 0, away = nil }
	end
	return plots
end

function Grove.plotOf(plots: { Plot }, uid: number): number?
	for i, p in plots do
		if p.uid == uid then
			return i
		end
	end
	return nil
end

local function neighboursTaken(plots: { Plot }, i: number): number
	local n = 0
	for j, p in plots do
		if p.uid and Grove.ringDistance(i, j) == 1 then
			n += 1
		end
	end
	return n
end

-- A plot for a hunter who just arrived (DD-087 §3): their own if they are coming back; next to a friend;
-- else a free plot beside the most people (a lively ring rather than lonely corners); with nothing free,
-- the plot of whoever has been out on a fight longest. friends: user ids on this server who are friends.
-- Returns the plot index, or nil (no room at all: a lodger until one frees up).
function Grove.assign(plots: { Plot }, uid: number, friends: { number }?, now: number): number?
	local own = Grove.plotOf(plots, uid)
	if own then
		plots[own].away = nil
		return own
	end
	local free = {}
	for i, p in plots do
		if not p.uid then
			table.insert(free, i)
		end
	end
	local pick = nil
	if #free > 0 then
		local best = -math.huge
		for _, i in free do
			local score = neighboursTaken(plots, i) * 10 - i * 0.01
			for _, f in friends or {} do
				local fi = Grove.plotOf(plots, f)
				if fi then
					score += (Grove.Plots - Grove.ringDistance(i, fi)) * 100
				end
			end
			if score > best then
				best, pick = score, i
			end
		end
	else
		local oldest = math.huge
		for i, p in plots do
			if p.away and p.away < oldest then
				oldest, pick = p.away, i
			end
		end
	end
	if not pick then
		return nil
	end
	plots[pick] = { uid = uid, since = now, away = nil }
	return pick
end

-- The owner leaves the server: out to a fight (hold the plot) or gone (free it).
function Grove.release(plots: { Plot }, uid: number, now: number, hold: boolean)
	local i = Grove.plotOf(plots, uid)
	if not i then
		return
	end
	if hold then
		plots[i].away = now
	else
		plots[i] = { uid = nil, since = now, away = nil }
	end
end

-- Holds that ran out are freed. Returns the user ids that lost their plot.
function Grove.expire(plots: { Plot }, now: number): { number }
	local out = {}
	for i, p in plots do
		if p.away and now - p.away > Grove.Hold then
			table.insert(out, p.uid :: number)
			plots[i] = { uid = nil, since = now, away = nil }
		end
	end
	return out
end

return Grove
