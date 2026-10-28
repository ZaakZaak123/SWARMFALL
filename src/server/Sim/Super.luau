--!nonstrict
-- DD-105: the weapon's super, the main skill (Defs.Supers). Pure sim, no Instances.
--   charge  — Combat.damage adds the hero's damage dealt (not the super's own); full at Defs.Super.Seconds of
--             the bare weapon's fire;
--   cast    — World:super (aim from the client: the gun's own target on a tap, the pointed way on a drag);
--   update  — the ball's flight, the wide beam's ticks, the rail's burning strips.
-- The super's own damage carries DF.SUPER and never charges it.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Codec = require(Shared:WaitForChild("Codec"))
local Combat = require(script.Parent.Combat)

local E, C, DF, ST = Codec.E, Codec.C, Codec.DF, Codec.State

local Super = {}

local buf = {}

-- How much damage fills the bar for this weapon (its bare full fire for Defs.Super.Seconds).
function Super.need(weaponDef): number
	return weaponDef.damage * weaponDef.rate * (weaponDef.pellets or 1) * Defs.Super.Seconds
end

-- Bosses and heavies take less (as from the Громобой): a super is for the swarm, not a boss-skip.
-- (Combat.damage already gives a boss 0.6 of any depth-1 hit: 0.36 in all, near the hammer's 0.35.)
local function hit(w, p, e, amount: number, flags: number, x: number, z: number)
	local mult = if e.def.boss then Defs.Super.BossMult elseif e.def.big then Defs.Super.BigMult else 1
	return Combat.damage(w, p, e, amount * mult, 1, flags, x, z)
end

local function stun(w, e, seconds: number)
	if not e.def.big then
		e.stunUntil = math.max(e.stunUntil, w.t + seconds)
	elseif not e.def.boss and e.state == ST.WINDUP then
		e.state = ST.RECOVER -- heavies only lose a windup
		e.stateUntil = w.t + 0.5
	end
end

local function push(w, e, fromX: number, fromZ: number, dist: number)
	if e.def.boss or e.def.static then
		return
	end
	local dx, dz = e.x - fromX, e.z - fromZ
	local m = math.sqrt(dx * dx + dz * dz)
	if m < 0.01 then
		return
	end
	local d = if e.def.big then dist * 0.2 else dist
	e.x, e.z = w.nav.resolve(e.x + dx / m * d, e.z + dz / m * d, e.def.radius)
end

-- Every live enemy within halfWidth of the segment (ox, oz) + (dx, dz) * len, calling fn(e, along).
local function alongLine(w, ox: number, oz: number, dx: number, dz: number, len: number, halfWidth: number, fn)
	for _, e in w:query(ox + dx * len / 2, oz + dz * len / 2, len / 2 + halfWidth + 3, buf) do
		if e.alive and not e.invulnerable then
			local cx, cz = e.x - ox, e.z - oz
			local along = cx * dx + cz * dz
			if along > -e.def.radius and along < len + e.def.radius then
				if math.abs(cx * dz - cz * dx) < halfWidth + e.def.radius then
					fn(e, along)
				end
			end
		end
	end
end

local function ballBurst(w, p, b)
	local S = Defs.Supers.W_ARC_RIFLE
	local struck = {}
	for _, e in w:query(b.x, b.z, S.radius + 3, buf) do
		if e.alive and not e.invulnerable and (e.x - b.x) ^ 2 + (e.z - b.z) ^ 2 <= (S.radius + e.def.radius) ^ 2 then
			struck[e] = true
			stun(w, e, S.stun)
			hit(w, p, e, S.damage, bit32.bor(DF.ARC, DF.SUPER), b.x, b.z)
		end
	end
	-- arcs on to the nearest ones it did not touch
	local list = w:query(b.x, b.z, S.arcRange, {})
	for _ = 1, S.arcs do
		local best, bd = nil, math.huge
		for _, e in list do
			if e.alive and not struck[e] and not e.invulnerable then
				local d = (e.x - b.x) ^ 2 + (e.z - b.z) ^ 2
				if d < bd then
					best, bd = e, d
				end
			end
		end
		if not best then
			break
		end
		struck[best] = true
		w:emit(E.ARC, b.x, b.z, best.x, best.z, C.BLUE)
		stun(w, best, S.stun * 0.5)
		hit(w, p, best, S.arcDamage, bit32.bor(DF.ARC, DF.SUPER), b.x, b.z)
	end
	w:emit(E.SUPER, p.id, p.weaponDef.index, 2, b.x, b.z, b.dx, b.dz, S.radius)
end

function Super.cast(w, p, dx: number, dz: number)
	local id = p.weaponDef.id
	local S = Defs.Supers[id]
	if not S then
		return
	end
	p.super = 0
	p.superCasts = (p.superCasts or 0) + 1
	local ox, oz = p.x + dx * 1.2, p.z + dz * 1.2
	w:emit(E.SUPER, p.id, p.weaponDef.index, 1, p.x, p.z, dx, dz, 0)
	if id == "W_ARC_RIFLE" then
		p.superBall = { x = ox, z = oz, dx = dx, dz = dz, left = S.range }
	elseif id == "W_SCATTERGUN" then
		local cosHalf = math.cos(math.rad(S.halfAngle))
		p.iframeUntil = math.max(p.iframeUntil, w.t + S.iframes)
		for _, e in w:query(p.x, p.z, S.reach + 3, buf) do
			if e.alive and not e.invulnerable then
				local cx, cz = e.x - p.x, e.z - p.z
				local d = math.sqrt(cx * cx + cz * cz)
				local edge = d - e.def.radius
				if edge <= S.reach and (d < 2.5 or (cx * dx + cz * dz) / d >= cosHalf) then
					stun(w, e, S.stun)
					push(w, e, p.x, p.z, S.knock)
					hit(w, p, e, S.damage, bit32.bor(DF.BLAST, DF.SUPER), p.x, p.z)
				end
			end
		end
	elseif id == "W_PLASMA_BEAM" then
		p.superBeamUntil = w.t + S.duration
		p.superBeamT = 0
		p.heat = 0
		p.overheatT = 0
	elseif id == "W_RAILGUN" then
		local len = w.nav.ray(ox, oz, dx, dz, S.range)
		alongLine(w, ox, oz, dx, dz, len, S.halfWidth, function(e)
			hit(w, p, e, S.damage, DF.SUPER, ox, oz)
		end)
		table.insert(w.superStrips, {
			owner = p,
			x = ox,
			z = oz,
			dx = dx,
			dz = dz,
			len = len,
			untilT = w.t + S.strip,
			tickT = 0,
		})
		w:emit(E.SUPER, p.id, p.weaponDef.index, 2, ox, oz, dx, dz, len)
	end
end

function Super.update(w, p, dt: number)
	local b = p.superBall
	if b then
		local S = Defs.Supers.W_ARC_RIFLE
		local step = math.min(S.speed * dt, b.left)
		local nx, nz = b.x + b.dx * step, b.z + b.dz * step
		local wall = w.nav.ray(b.x, b.z, b.dx, b.dz, step + 0.5)
		local hit = wall < step
		if not hit then
			for _, e in w:query(nx, nz, 4, buf) do
				if e.alive and not e.invulnerable and (e.x - nx) ^ 2 + (e.z - nz) ^ 2 <= (e.def.radius + 1.2) ^ 2 then
					hit = true
					break
				end
			end
		end
		b.x, b.z = if wall < step then b.x + b.dx * wall else nx, if wall < step then b.z + b.dz * wall else nz
		b.left -= step
		if hit or b.left <= 0 then
			p.superBall = nil
			ballBurst(w, p, b)
		end
	end
	if p.superBeamUntil then
		local S = Defs.Supers.W_PLASMA_BEAM
		if w.t >= p.superBeamUntil then
			p.superBeamUntil = nil
			w:emit(E.SUPER, p.id, p.weaponDef.index, 3, p.x, p.z, p.aimX, p.aimZ, 0)
		else
			p.heat = 0
			p.superBeamT -= dt
			while p.superBeamT <= 0 do
				p.superBeamT += S.tick
				local dx, dz = p.aimX, p.aimZ
				local ox, oz = p.x + dx * 1.2, p.z + dz * 1.2
				local len = w.nav.ray(ox, oz, dx, dz, p.stats.range)
				alongLine(w, ox, oz, dx, dz, len, S.halfWidth, function(e)
					hit(w, p, e, S.tickDamage, DF.SUPER, ox, oz)
				end)
			end
		end
	end
end

-- The rail's burning strips: whoever stands in one burns (the burn refreshed while inside).
function Super.updateStrips(w, dt: number)
	local list = w.superStrips
	local S = Defs.Supers.W_RAILGUN
	for i = #list, 1, -1 do
		local s = list[i]
		if w.t >= s.untilT or not w.players[s.owner.id] then
			table.remove(list, i)
		else
			s.tickT -= dt
			if s.tickT <= 0 then
				s.tickT = 0.25
				alongLine(w, s.x, s.z, s.dx, s.dz, s.len, S.halfWidth + 0.6, function(e)
					if not e.def.static then
						e.burnSuperUntil = w.t + 1 -- (the strip's burn does not charge the super back)
						e.burnDps = math.max(if w.t < e.burnUntil then e.burnDps else 0, S.burnDps)
						e.burnOwner = s.owner
						e.burnUntil = math.max(e.burnUntil, w.t + 1)
					end
				end)
			end
		end
	end
end

return Super
