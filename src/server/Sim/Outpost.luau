--!nonstrict
-- Outposts in the simulation (DD-038/DD-039). Pure Luau on the World record.
--   siege: the host's structures stand on their sockets and fight the swarm with the squad
--   raid:  another player's outpost — its turrets are static enemies that shoot hunters, its traps are
--          permanent hazards, its brood strains arrive in waves, its extractor core is the objective
-- Mutations (the owner's swarm) change spawned enemies and add death effects.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Codec = require(Shared:WaitForChild("Codec"))
local Meta = require(Shared:WaitForChild("Meta"))

local E, C, SH = Codec.E, Codec.C, Codec.Shape
local DF = Codec.DF

local Outpost = {}

local KIND_CODE = { turret = 1, chain = 2, mortar = 3, shield = 4 }

-- Allied structures (siege) ------------------------------------------------------------------------------
-- A snapshot's defence strength (raid rewards and the raider's rating scale with it, DD-061).
function Outpost.power(slots): number
	return Meta.outpostPower(slots or {})
end

function Outpost.allied(slots)
	local list = {}
	for i, s in Meta.cleanOutpost(slots) do
		local sock = Meta.Sockets[i]
		local def = Meta.Structures[s.id]
		table.insert(list, { slot = i, id = s.id, lvl = s.lvl, x = sock.x, z = sock.z, def = def, cd = 1.5 + i * 0.2, tick = 0 })
	end
	return list
end

local function nearestEnemy(w, x: number, z: number, range: number, minRange: number?)
	local best, bd = nil, range * range
	local min2 = (minRange or 0) ^ 2
	for _, e in w:query(x, z, range, w.hitBuf) do
		if e.alive and not e.def.static and e.state ~= 0 then
			local d = (e.x - x) ^ 2 + (e.z - z) ^ 2
			if d < bd and d >= min2 then
				best, bd = e, d
			end
		end
	end
	return best
end

function Outpost.update(w, dt: number)
	local t = w.t
	for _, s in w.structures do
		local def, lvl = s.def, s.lvl
		local kind = def.kind
		if kind == "slow" or kind == "acid" then
			s.tick -= dt
			if s.tick <= 0 then
				s.tick = 0.25
				local r = def.radius[lvl]
				for _, e in w:query(s.x, s.z, r + 2, w.hitBuf) do
					if e.alive and not e.def.static and (e.x - s.x) ^ 2 + (e.z - s.z) ^ 2 < (r + e.def.radius) ^ 2 then
						if kind == "slow" then
							e.slow = math.max(if t < e.slowUntil then e.slow else 0, def.slow[lvl])
							e.slowUntil = t + 0.4
						else
							w:damage(nil, e, def.damage[lvl] * 0.25, 1, bit32.bor(DF.BURN, DF.ENV), s.x, s.z)
						end
					end
				end
			end
		elseif kind == "harvest" then
			continue
		elseif t >= s.cd then
			if kind == "shield" then
				s.cd = t + def.every[lvl]
				if w.mission.reactor and w.mission.reactor.alive then
					w.mission:shieldReactor(def.shield[lvl])
					w:emit(E.TURRET, s.slot, s.x, s.z, 0, 0, KIND_CODE.shield)
				end
			elseif kind == "turret" then
				local e = nearestEnemy(w, s.x, s.z, def.range)
				if e then
					s.cd = t + def.every[lvl]
					w:emit(E.TURRET, s.slot, s.x, s.z, e.x, e.z, KIND_CODE.turret)
					w:damage(nil, e, def.damage[lvl], 0, DF.ENV, s.x, s.z)
				else
					s.cd = t + 0.2
				end
			elseif kind == "chain" then
				local first = nearestEnemy(w, s.x, s.z, def.range)
				if first then
					s.cd = t + def.every[lvl]
					local targets = {}
					for _, e in w:query(s.x, s.z, def.range, {}) do
						if e.alive and not e.def.static then
							table.insert(targets, e)
						end
					end
					table.sort(targets, function(a, b)
						return (a.x - s.x) ^ 2 + (a.z - s.z) ^ 2 < (b.x - s.x) ^ 2 + (b.z - s.z) ^ 2
					end)
					local fx, fz = s.x, s.z
					w:emit(E.TURRET, s.slot, s.x, s.z, first.x, first.z, KIND_CODE.chain)
					for k = 1, math.min(#targets, def.targets[lvl]) do
						local e = targets[k]
						w:emit(E.ARC, fx, fz, e.x, e.z, C.CYAN)
						fx, fz = e.x, e.z
						e.stunUntil = math.max(e.stunUntil, t + 0.25)
						w:damage(nil, e, def.damage[lvl], 1, bit32.bor(DF.ARC, DF.ENV), s.x, s.z)
					end
				else
					s.cd = t + 0.25
				end
			elseif kind == "mortar" then
				local e = nearestEnemy(w, s.x, s.z, def.range, 8)
				if e then
					s.cd = t + def.every[lvl]
					local r = def.radius[lvl]
					local flight = 0.9
					w:emit(E.TURRET, s.slot, s.x, s.z, e.x, e.z, KIND_CODE.mortar)
					w:emit(E.TELE, SH.CIRCLE, e.x, e.z, 0, 1, r, 0, flight, C.ORANGE, 0)
					table.insert(w.shells, { at = t + flight, x = e.x, z = e.z, r = r, dmg = def.damage[lvl], hostile = false })
				else
					s.cd = t + 0.3
				end
			end
		end
	end
	Outpost.updateShells(w)
end

-- Mortar shells in flight (both sides).
function Outpost.updateShells(w)
	local t = w.t
	local i = 1
	while i <= #w.shells do
		local sh = w.shells[i]
		if t >= sh.at then
			table.remove(w.shells, i)
			w:emit(E.BOOM, sh.x, sh.z, sh.r, C.ORANGE)
			if sh.hostile then
				for _, p in w.playerList do
					if p.alive and (p.x - sh.x) ^ 2 + (p.z - sh.z) ^ 2 < (sh.r + Defs.Player.Radius) ^ 2 then
						w:hurtPlayer(p, sh.dmg, sh.x, sh.z)
					end
				end
			else
				for _, e in w:query(sh.x, sh.z, sh.r + 4, {}) do
					if e.alive and not e.def.static and (e.x - sh.x) ^ 2 + (e.z - sh.z) ^ 2 < (sh.r + e.def.radius) ^ 2 then
						w:damage(nil, e, sh.dmg * (if e.def.boss then 0.4 else 1), 1, bit32.bor(DF.BLAST, DF.ENV), sh.x, sh.z)
					end
				end
			end
		else
			i += 1
		end
	end
end

-- Raid: deploy the target's outpost ----------------------------------------------------------------------
local TURRET_KIND = { STING = "TUR_STING", ARC = "TUR_ARC", MORTAR = "TUR_MORTAR", SHIELD = "TUR_SHIELD" }

function Outpost.deployHostile(w, target)
	local core = w:spawnEnemy("OUTPOST_CORE", 0, 0, 0.1)
	-- a squad brings more guns, but the core should not turn into a sponge: +30% per extra raider
	core.hp = Defs.Enemies.OUTPOST_CORE.hp * (1 + 0.3 * (#w.playerList - 1))
	core.maxHp = core.hp
	core.objective = "core"
	core.state = 8
	w.core = core
	for i, s in Meta.cleanOutpost(target.slots) do
		local sock = Meta.Sockets[i]
		local def = Meta.Structures[s.id]
		local kind = TURRET_KIND[s.id]
		if kind then
			local e = w:spawnEnemy(kind, sock.x, sock.z, 0.1)
			e.lvl = s.lvl
			e.sdef = def
			e.hp *= 1 + 0.35 * (s.lvl - 1)
			e.maxHp = e.hp
			e.cd = w.t + 2 + i * 0.3
			e.slot = i
		elseif def.kind == "slow" or def.kind == "acid" then
			local r = def.radius[s.lvl]
			w:addHazard({
				source = "trap",
				shape = SH.CIRCLE,
				x = sock.x,
				z = sock.z,
				dx = 0,
				dz = 1,
				a = r,
				b = 0,
				activeFrom = w.t,
				untilT = math.huge,
				damage = if def.kind == "acid" then math.ceil(def.damage[s.lvl] * 0.25) else 0,
				tick = 0.5,
				slow = if def.kind == "slow" then def.slow[s.lvl] else nil,
			})
			w:emit(E.TELE, SH.CIRCLE, sock.x, sock.z, 0, 1, r, 0, 0.1, if def.kind == "acid" then C.LIME else C.ICE, 600)
		end
	end
	w:banner(target.name or "ЧУЖОЙ АВАНПОСТ", "Разрушь вражеский бур в центре", C.ORANGE, 3.5, "@17")
end

-- One wave of the owner's brood: each strain, its unit count, its mutations.
function Outpost.broodWave(w, target)
	local strains = Meta.cleanBrood(target.brood)
	if #strains == 0 then
		strains = { { kind = "EN_RUNNER", muts = {} } }
	end
	w.broodWaves = (w.broodWaves or 0) + 1
	local order = w.map.spawnOrder
	for k, strain in strains do
		local n = Meta.strainUnits(strain) * (1 + 0.4 * (#w.playerList - 1)) * (1 + 0.08 * (w.broodWaves - 1))
		local dir = order[(w.broodWaves * 3 + k * 2) % #order + 1]
		local sp = w.map.spawns[dir]
		for _ = 1, math.floor(n + 0.5) do
			local e = w:spawnAtPoint(strain.kind, sp.x, sp.z, 9, 1.0)
			if e then
				Meta.applyMutations(e, strain.muts)
			end
		end
	end
	if w.broodWaves == 1 then
		w:banner("РОЙ ХОЗЯИНА", "Его штаммы идут волнами — смотри на мутации", C.VIOLET, 3, "@1")
	end
end

-- Hostile turret behaviours (AI hook) ---------------------------------------------------------------------
local PLAYER_R = Defs.Player.Radius

local function nearestPlayer(w, e, range: number)
	local best, bd = nil, range * range
	for _, p in w.playerList do
		if p.alive then
			local d = (p.x - e.x) ^ 2 + (p.z - e.z) ^ 2
			if d < bd then
				best, bd = p, d
			end
		end
	end
	return best, math.sqrt(bd)
end

function Outpost.hostile(w, e, dt: number)
	e.state = 8
	local def, lvl = e.sdef, e.lvl or 1
	if not def or w.t < e.cd then
		return
	end
	local mult = Meta.RaidTurretPlayerMult
	if def.kind == "shield" then
		e.cd = w.t + def.every[lvl]
		local core = w.core
		if core and core.alive then
			core.hp = math.min(core.maxHp, core.hp + def.shield[lvl] * 2)
			w:emit(E.TURRET, -e.id, e.x, e.z, core.x, core.z, KIND_CODE.shield)
		end
		return
	end
	local p, dist = nearestPlayer(w, e, def.range)
	if not p then
		e.cd = w.t + 0.3
		return
	end
	if not w.nav.clear(e.x, e.z, p.x, p.z, 0.5) then
		e.cd = w.t + 0.3
		return
	end
	local dx, dz = p.x - e.x, p.z - e.z
	e.fx, e.fz = dx / math.max(dist, 0.01), dz / math.max(dist, 0.01)
	if def.kind == "turret" then
		e.cd = w.t + def.every[lvl] * 1.4
		w:emit(E.TURRET, -e.id, e.x, e.z, p.x, p.z, KIND_CODE.turret)
		w:hurtPlayer(p, def.damage[lvl] * mult, e.x, e.z, e)
	elseif def.kind == "chain" then
		e.cd = w.t + def.every[lvl]
		w:emit(E.TURRET, -e.id, e.x, e.z, p.x, p.z, KIND_CODE.chain)
		w:emit(E.ARC, e.x, e.z, p.x, p.z, C.CYAN)
		w:hurtPlayer(p, def.damage[lvl] * mult, e.x, e.z, e)
	elseif def.kind == "mortar" then
		e.cd = w.t + def.every[lvl] * 1.2
		local r = def.radius[lvl]
		local flight = 1.15
		w:emit(E.TURRET, -e.id, e.x, e.z, p.x, p.z, KIND_CODE.mortar)
		w:emit(E.TELE, SH.CIRCLE, p.x, p.z, 0, 1, r, 0, flight, C.RED, 0)
		table.insert(w.shells, { at = w.t + flight, x = p.x, z = p.z, r = r, dmg = def.damage[lvl] * mult, hostile = true })
	end
end

-- Mutation effects ----------------------------------------------------------------------------------------
function Outpost.regen(w, e, dt: number)
	if e.muts and e.muts.REGEN and e.hp < e.maxHp then
		e.hp = math.min(e.maxHp, e.hp + e.maxHp * 0.03 * dt)
	end
end

function Outpost.onDeath(w, e)
	local m = e.muts
	if not m then
		return
	end
	if m.ACID_BLOOD then
		local r = 4.5
		w:addHazard({
			source = "mutant",
			shape = SH.CIRCLE,
			x = e.x,
			z = e.z,
			dx = 0,
			dz = 1,
			a = r,
			b = 0,
			activeFrom = w.t + 0.4,
			untilT = w.t + 3.4,
			damage = 5,
			tick = 0.5,
		})
		w:emit(E.TELE, SH.CIRCLE, e.x, e.z, 0, 1, r, 0, 0.4, C.LIME, 3)
	end
	if m.VOLATILE then
		local r = 5
		w:emit(E.BOOM, e.x, e.z, r, C.ORANGE)
		for _, p in w.playerList do
			if p.alive and (p.x - e.x) ^ 2 + (p.z - e.z) ^ 2 < (r + PLAYER_R) ^ 2 then
				w:hurtPlayer(p, 14, e.x, e.z, e)
			end
		end
	end
end

return Outpost
