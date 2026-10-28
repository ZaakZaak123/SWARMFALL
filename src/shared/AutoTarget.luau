--!strict
-- DD-103: the simple phone fight lets each gun choose its own kind of target. Pure (tested by Lune).
--   shotgun — the nearest thick knot: an enemy with others in the 13° cone behind it counts as closer;
--   rail    — the longest line: an enemy with others lined up behind it counts as closer (it pierces).
-- Other guns take the nearest (EnemyView.autoTarget). Only the CANDIDATES nearest are weighed (each
-- against every enemy in range), so a full swarm stays cheap. The held target (`keepId`) stays until a
-- rival scores clearly better, so the gun does not flick between two equal knots.

export type Enemy = { dx: number, dz: number, radius: number }

local AutoTarget = {}

AutoTarget.CANDIDATES = 12
local KNOT_COS = math.cos(math.rad(13))

function AutoTarget.uses(kind: string?): boolean
	return kind == "shotgun" or kind == "rail"
end

-- Returns id, x, z of the target or nil.
function AutoTarget.pick(
	kind: string,
	enemies: { [number]: Enemy },
	ox: number,
	oz: number,
	range: number,
	keepId: number?
): (number?, number?, number?)
	local near = {}
	for id, rec in enemies do
		local cx, cz = rec.dx - ox, rec.dz - oz
		local d = math.sqrt(cx * cx + cz * cz)
		if d < range and d > 0.1 then
			table.insert(near, { id = id, rec = rec, d = d, ux = cx / d, uz = cz / d })
		end
	end
	if #near == 0 then
		return nil, nil, nil
	end
	table.sort(near, function(a, b)
		return a.d < b.d
	end)
	local best, bestE, keepScore = math.huge, nil, math.huge
	for i = 1, math.min(AutoTarget.CANDIDATES, #near) do
		local e = near[i]
		local count = 0
		for _, o in near do
			if o ~= e and o.d > e.d * 0.6 then
				if kind == "shotgun" then
					if o.ux * e.ux + o.uz * e.uz > KNOT_COS then
						count += 1
					end
				else
					local rx, rz = o.rec.dx - ox, o.rec.dz - oz
					local along = rx * e.ux + rz * e.uz
					local perp = math.abs(rx * e.uz - rz * e.ux)
					if along > 0 and perp < o.rec.radius + 0.45 then
						count += 1
					end
				end
			end
		end
		local score = e.d / (1 + count * (if kind == "rail" then 0.8 else 0.5))
		if e.id == keepId then
			keepScore = score
		end
		if score < best then
			best, bestE = score, e
		end
	end
	if keepId and keepScore < math.huge and best > keepScore * 0.65 then
		local rec = enemies[keepId]
		return keepId, rec.dx, rec.dz
	end
	assert(bestE)
	return bestE.id, bestE.rec.dx, bestE.rec.dz
end

return AutoTarget
