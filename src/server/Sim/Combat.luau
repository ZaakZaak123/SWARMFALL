--!nonstrict
-- Damage pipeline: Fire -> Trace (analytic, server positions only) -> Hit (crit/status/procs) -> Damage
-- (armor/vulnerability) -> Kill (rewards/on-kill procs). Secondary damage (depth 1) never triggers hit
-- procs, so chains, ricochets and explosions are always finite. A per-player proc budget caps spam.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Codec = require(Shared:WaitForChild("Codec"))

local E, C, DF = Codec.E, Codec.C, Codec.DF
local ST = Codec.State
local UV = Defs.UpgradeValues
local pick = Defs.rankValue
local band, bor = bit32.band, bit32.bor

local Combat = {}

-- Effective rank of a card family: cards picked this run + virtual ranks from equipped modules, capped
-- at the shared limit (DD-010). Offers and slots use cardRank (only what was picked in this run).
function Combat.rank(p, id: string): number
	local m = p.modRanks and p.modRanks[id] or 0
	return math.min(Defs.Run.MaxRank, (p.ranks[id] or 0) + m)
end
local rank = Combat.rank

function Combat.cardRank(p, id: string): number
	return p.ranks[id] or 0
end
local cardRank = Combat.cardRank

local function rv(p, id: string, values)
	local r = rank(p, id)
	if r <= 0 then
		return 0
	end
	return pick(r, values)
end

function Combat.recompute(p)
	local wd = p.weaponDef
	local s = p.stats or {}
	p.stats = s
	local fireBonus = rv(p, "UPG_FIRERATE", UV.UPG_FIRERATE.bonus)
	s.damage = wd.damage
	s.rate = wd.rate * (1 + fireBonus)
	s.range = wd.range
	s.magazine = wd.magazine
	s.reload = wd.reload / (1 + 0.6 * fireBonus)
	s.reloadEmpty = (wd.reloadEmpty or wd.reload) / (1 + 0.6 * fireBonus)
	-- TECH_PIERCE_CORE: one extra pierce (downstream hits keep the weapon falloff).
	s.pierce = wd.pierce
		+ rv(p, "UPG_PIERCE", UV.UPG_PIERCE.extra)
		+ (if p.tech and p.tech.TECH_PIERCE_CORE then 1 else 0)
	s.pellets = wd.pellets
	s.spread = wd.spread
	s.spreadMin = wd.spreadMin or wd.spread
	s.spreadMax = wd.spreadMax or wd.spread
	s.bloom = wd.bloom or 0
	s.recover = wd.recover or 0
	s.critChance = rv(p, "UPG_CRIT", UV.UPG_CRIT.chance)
	s.critMult = if s.critChance > 0 then pick(rank(p, "UPG_CRIT"), UV.UPG_CRIT.mult) else 1
	s.multi = rv(p, "UPG_MULTISHOT", UV.UPG_MULTISHOT.extra)
	s.multiMult = if s.multi > 0 then pick(rank(p, "UPG_MULTISHOT"), UV.UPG_MULTISHOT.mult) else 0
	s.knock = wd.knockback * (if wd.kind == "shotgun" then 0.3 else 1)
	s.falloff = wd.falloff
	local evo = p.evolved
	if evo and Defs.Evolutions[evo] and Defs.Evolutions[evo].m20 then
		evo = nil -- M20 forms apply through modRanks / modMods (World.newPlayer)
	end
	if evo == "EV_THUNDERLORD" then
		local m = Defs.Evolutions.EV_THUNDERLORD.mods
		s.damage += m.damageAdd
		s.rate *= m.rateMult
		s.magazine = m.magazine
	elseif evo == "EV_INFERNO_GRINDER" then
		s.pellets += 4
		s.magazine = 9
	elseif evo == "EV_STARBREAKER" then
		s.pierce = 12
		s.falloff = 0.92
		s.rate *= 1.2
		s.magazine = 8
	elseif evo == "EV_VOID_LANCE" then
		s.damage *= 1.3
		s.range *= 1.4
		s.pierce = 12
		s.falloff = 1
	end
	if p.odFlag then
		s.rate *= 1 + Defs.Overdrive.RateBonus
		s.pierce += Defs.Overdrive.Pierce
	end
	-- Equipped module stat tweaks (Modules.luau).
	local mods = p.modMods
	if mods then
		s.damage *= mods.damageMult or 1
		s.rate *= mods.rateMult or 1
		s.range *= mods.rangeMult or 1
		s.pierce += mods.pierceAdd or 0
		s.pellets += mods.pelletsAdd or 0
		s.falloff = math.min(1, s.falloff + (mods.falloffAdd or 0))
		s.knock *= mods.knockMult or 1
		local sm = mods.spreadMult or 1
		s.spread *= sm
		s.spreadMin *= sm
		s.spreadMax *= sm
	end
	s.heatMult = if mods then mods.heatMult or 1 else 1
	-- Style synergies (DD-017); module virtual ranks count, like every other card effect.
	s.lineFire = rank(p, "UPG_PIERCE") > 0 and rank(p, "UPG_CRIT") > 0
	s.frostShell = rank(p, "UPG_FREEZE") > 0 and rank(p, "UPG_SHIELD") > 0
	s.iceBreak = rank(p, "UPG_FREEZE") > 0 and rank(p, "UPG_DASH_SHOCK") > 0
	s.sidePierce = if rank(p, "UPG_MULTISHOT") >= 3 then 1 else 0
	s.brittle = rank(p, "UPG_FREEZE") > 0 and rank(p, "UPG_CORRODE") > 0
end

function Combat.synergyActive(p, id: string): boolean
	local keys = Defs.Synergies[id].keys
	return rank(p, keys[1]) > 0 and rank(p, keys[2]) > 0
end

-- Tactical reload (rounds left) is a quick cell swap; an empty magazine also needs the bolt racked.
function Combat.startReload(w, p)
	if p.weaponDef.kind == "beam" or p.reloadT > 0 or p.ammo >= p.stats.magazine then
		return
	end
	p.reloadEmpty = p.ammo <= 0
	p.reloadT = if p.reloadEmpty then p.stats.reloadEmpty else p.stats.reload
	p.reloadDur = p.reloadT
end

-- Tracing ---------------------------------------------------------------------------------------------
local hitE: { any } = {}
local hitT: { number } = {}

-- Returns end distance. Applies primary hits to up to (pierce + 1) enemies along the ray.
local function trace(w, p, ox: number, oz: number, dx: number, dz: number, dmg: number, pierce: number, range: number)
	local wall = w.nav.ray(ox, oz, dx, dz, range)
	local n = 0
	for _, e in w.enemies do
		if e.alive then
			local rad = e.def.radius + 0.45
			local cx, cz = e.x - ox, e.z - oz
			local along = cx * dx + cz * dz
			if along > -rad and along < wall + rad then
				local perp2 = cx * cx + cz * cz - along * along
				if perp2 < rad * rad then
					local entry = along - math.sqrt(rad * rad - perp2)
					if entry < wall then
						n += 1
						hitE[n] = e
						hitT[n] = entry
					end
				end
			end
		end
	end
	local endT = wall
	local remaining = pierce + 1
	local scale = 1
	local normals = 0
	local k = 0
	local lineFire = p.stats.lineFire
	while remaining > 0 and n > 0 do
		local bi, bt = 1, hitT[1]
		for i = 2, n do
			if hitT[i] < bt then
				bi, bt = i, hitT[i]
			end
		end
		local e = hitE[bi]
		hitE[bi], hitT[bi] = hitE[n], hitT[n]
		hitE[n] = nil
		n -= 1
		if e.invulnerable then
			endT = math.max(0, bt)
			remaining = 0
			break
		end
		k += 1
		-- ЛИНИЯ ОГНЯ: from the 3rd target on, every pierced enemy takes a crit and the falloff stops.
		Combat.hit(w, p, e, dmg * scale, dx, dz, lineFire and k >= 3)
		if not e.def.big then
			normals += 1
		end
		remaining -= 1
		if not (lineFire and k >= 2) then
			scale *= p.stats.falloff
		end
		if remaining == 0 then
			endT = math.max(0, bt)
		end
	end
	for i = 1, n do
		hitE[i] = nil
	end
	-- Railgun trial «Пробой линии»: one shot damaging >= 2 normal enemies in a line.
	if normals >= Defs.LineTrial.MinHits and p.weaponDef.id == "W_RAILGUN" then
		p.lineShots += 1
		if normals >= 4 then
			p.feats.line4 += 1
		end
	end
	return endT
end
Combat.trace = trace

local function shoot(w, p, angle: number, dmg: number, pierce: number, range: number)
	local dx, dz = math.sin(angle), math.cos(angle)
	local ox, oz = p.x + dx * 1.2, p.z + dz * 1.2
	local d = trace(w, p, ox, oz, dx, dz, dmg, pierce, range)
	w:emit(E.SHOT, p.id, ox, oz, ox + dx * d, oz + dz * d, p.weaponDef.index, if p.evolved then 1 else 0)
end

function Combat.fire(w, p)
	local s = p.stats
	local rng = w.rng
	local base = math.atan2(p.aimX, p.aimZ)
	local half = math.rad(s.spread) / 2
	if p.weaponDef.kind == "shotgun" then
		for _ = 1, s.pellets do
			shoot(w, p, base + rng:range(-half, half), s.damage, s.pierce, s.range * rng:range(0.85, 1))
		end
		for k = 1, s.multi do
			local side = if k % 2 == 1 then 1 else -1
			local center = base + side * (half + math.rad(6))
			for _ = 1, 3 do
				shoot(
					w,
					p,
					center + rng:range(-0.12, 0.12),
					s.damage * s.multiMult,
					s.pierce + s.sidePierce,
					s.range * 0.9
				)
			end
		end
	else
		if s.bloom > 0 then
			-- accuracy bloom: the cone opens with sustained fire and closes when the trigger is released
			half = math.rad(p.spread) / 2
			p.spread = math.min(s.spreadMax, p.spread + s.bloom)
		end
		shoot(w, p, base + rng:range(-half, half), s.damage, s.pierce, s.range)
		for k = 1, s.multi do
			local side = if k % 2 == 1 then 1 else -1
			shoot(
				w,
				p,
				base + side * math.rad(9) * math.ceil(k / 2),
				s.damage * s.multiMult,
				s.pierce + s.sidePierce,
				s.range * 0.9
			)
		end
	end
end

local function beam(w, p, angle: number, dmg: number, sideBeam: boolean)
	local s = p.stats
	local dx, dz = math.sin(angle), math.cos(angle)
	local ox, oz = p.x + dx * 1.2, p.z + dz * 1.2
	local d = trace(w, p, ox, oz, dx, dz, dmg, s.pierce, s.range * (if sideBeam then 0.8 else 1))
	return ox, oz, ox + dx * d, oz + dz * d
end

function Combat.beamTick(w, p)
	local s = p.stats
	local base = math.atan2(p.aimX, p.aimZ)
	local ox, oz, ex, ez = beam(w, p, base, s.damage, false)
	p.beamFxT -= 1
	if p.beamFxT <= 0 then
		-- Beam visuals for teammates every other tick (owner renders locally).
		p.beamFxT = 2
		w:emit(E.BEAM, p.id, ox, oz, ex, ez, if p.evolved then 1 else 0)
	end
	for k = 1, s.multi do
		local side = if k % 2 == 1 then 1 else -1
		beam(w, p, base + side * math.rad(10) * math.ceil(k / 2), s.damage * s.multiMult, true)
	end
	if p.evolved == "EV_VOID_LANCE" and w.t >= p.voidPulseT then
		p.voidPulseT = w.t + 1.2
		local dx, dz = math.sin(base), math.cos(base)
		local len = w.nav.ray(p.x, p.z, dx, dz, s.range)
		w:emit(E.BOOM, ex, ez, 6, C.VIOLET)
		w:emit(E.TELE, Codec.Shape.LINE, p.x, p.z, dx, dz, len, 5, 0.25, C.VIOLET, 0)
		for _, e in w:query(p.x + dx * len / 2, p.z + dz * len / 2, len / 2 + 3, {}) do
			local cx, cz = e.x - p.x, e.z - p.z
			local along = cx * dx + cz * dz
			if along > 0 and along < len and math.abs(cx * dz - cz * dx) < 2.5 + e.def.radius then
				Combat.damage(w, p, e, 70, 1, DF.ARC, p.x, p.z)
			end
		end
	end
end

-- Hits & procs ----------------------------------------------------------------------------------------
local function spend(p, cost: number): boolean
	if p.procBudget < cost then
		return false
	end
	p.procBudget -= cost
	return true
end

local nearBuf = {}
-- Nearest live enemy to (x,z) within r that is not in `skip`.
local function nearest(w, x: number, z: number, r: number, skip)
	local best, bd = nil, math.huge
	for _, e in w:query(x, z, r, nearBuf) do
		if not skip[e] and not e.invulnerable then
			local d = (e.x - x) ^ 2 + (e.z - z) ^ 2
			if d < bd then
				best, bd = e, d
			end
		end
	end
	return best
end

local visited = {}

function Combat.hit(w, p, e, dmg: number, dx: number, dz: number, forceCrit: boolean?)
	local s = p.stats
	local t = w.t
	local flags = 0
	if forceCrit or (s.critChance > 0 and w.rng:next() < s.critChance) then
		dmg *= s.critMult
		flags = DF.CRIT
	end
	local ex, ez = e.x, e.z
	Combat.damage(w, p, e, dmg, 0, flags, p.x, p.z)
	if e.alive then
		if not e.def.big and s.knock > 0 then
			e.x, e.z = w.nav.resolve(e.x + dx * s.knock, e.z + dz * s.knock, e.def.radius)
		end
		local ig = rank(p, "UPG_IGNITE")
		if ig > 0 or p.evolved == "EV_INFERNO_GRINDER" then
			local dps = (if ig > 0 then pick(ig, UV.UPG_IGNITE.dps) else 6)
				* (if p.evolved == "EV_INFERNO_GRINDER" then 2 else 1)
			if dps >= e.burnDps or t >= e.burnUntil then
				e.burnDps = dps
				e.burnOwner = p
			end
			e.burnUntil = t + UV.UPG_IGNITE.duration
		end
		local co = rank(p, "UPG_CORRODE")
		if co > 0 then
			local cap = pick(co, UV.UPG_CORRODE.cap)
			if p.evolved == "EV_VOID_LANCE" then
				cap += 0.12
			end
			local per = UV.UPG_CORRODE.perHit
			-- ХРУПКОСТЬ: slowed enemies corrode twice as fast and deeper.
			if s.brittle and t < e.slowUntil and e.slow > 0 then
				per *= Defs.Brittle.RateMult
				cap += Defs.Brittle.CapAdd
			end
			if t >= e.vulnUntil then
				e.vuln = 0
			end
			e.vuln = math.min(cap, e.vuln + per)
			e.vulnUntil = t + UV.UPG_CORRODE.duration
		end
		local fr = rank(p, "UPG_FREEZE")
		if fr > 0 then
			local slow = pick(fr, UV.UPG_FREEZE.slow)
			if e.def.boss then
				slow = math.min(slow, UV.UPG_FREEZE.bossCap)
			end
			e.slow = math.max(if t < e.slowUntil then e.slow else 0, slow)
			e.slowUntil = t + UV.UPG_FREEZE.duration
			e.chill = math.max(e.chill, pick(fr, UV.UPG_FREEZE.weaken))
			e.frail = math.max(e.frail, pick(fr, UV.UPG_FREEZE.frail))
		end
	end
	if p.evolved == "EV_STARBREAKER" and spend(p, 1) then
		Combat.blast(w, p, ex, ez, 6, dmg * 0.4, C.GOLD, 1.5)
	end
	table.clear(visited)
	visited[e] = true
	-- Thunderlord: every hit forks through up to 3 more targets (damage share per hop from Defs).
	if p.evolved == "EV_THUNDERLORD" then
		local fromX, fromZ = ex, ez
		local m = Defs.Evolutions.EV_THUNDERLORD.mods
		for _, mult in m.forks do
			if not spend(p, 1) then
				break
			end
			local target = nearest(w, fromX, fromZ, m.forkRadius, visited)
			if not target then
				break
			end
			visited[target] = true
			w:emit(E.ARC, fromX, fromZ, target.x, target.z, C.BLUE)
			fromX, fromZ = target.x, target.z
			Combat.damage(w, p, target, s.damage * mult, 1, DF.ARC, fromX, fromZ)
		end
	end
	-- Chain Arc
	local ch = rank(p, "UPG_CHAIN")
	if ch > 0 then
		p.chainCount += 1
		if p.chainCount >= pick(ch, UV.UPG_CHAIN.every) then
			p.chainCount = 0
			Combat.chain(w, p, ex, ez, pick(ch, UV.UPG_CHAIN.targets), s.damage * UV.UPG_CHAIN.mult * 1.5)
		end
	end
	-- Ricochet (+ DOUBLE ARC synergy: a ricochet onto a fresh target charges Chain Arc once per shot)
	local rc = rank(p, "UPG_RICOCHET")
	if rc > 0 then
		local fromX, fromZ = ex, ez
		local charged = false
		for _ = 1, pick(rc, UV.UPG_RICOCHET.bounces) do
			if not spend(p, 1) then
				break
			end
			local target = nearest(w, fromX, fromZ, UV.UPG_RICOCHET.radius, visited)
			if not target then
				break
			end
			visited[target] = true
			w:emit(E.ARC, fromX, fromZ, target.x, target.z, C.WHITE)
			fromX, fromZ = target.x, target.z
			Combat.damage(w, p, target, dmg * pick(rc, UV.UPG_RICOCHET.mult), 1, 0, fromX, fromZ)
			if ch > 0 and not charged then
				charged = true
				p.chainCount += 1
			end
		end
	end
end

local chainBuf = {}
function Combat.chain(w, p, x: number, z: number, count: number, dmg: number)
	local list = w:query(x, z, UV.UPG_CHAIN.radius, chainBuf)
	-- Partial selection of the `count` nearest that were not already struck.
	for _ = 1, count do
		local best, bd, bi = nil, math.huge, 0
		for i, e in list do
			if e.alive and not visited[e] and not e.invulnerable then
				local d = (e.x - x) ^ 2 + (e.z - z) ^ 2
				if d < bd then
					best, bd, bi = e, d, i
				end
			end
		end
		if not best or not spend(p, 1) then
			break
		end
		visited[best] = true
		list[bi] = list[#list]
		list[#list] = nil
		w:emit(E.ARC, x, z, best.x, best.z, C.CYAN)
		Combat.damage(w, p, best, dmg, 1, DF.ARC, x, z)
	end
end

function Combat.blast(w, p, x: number, z: number, radius: number, dmg: number, color: number, knock: number?)
	w:emit(E.BOOM, x, z, radius, color)
	for _, e in w:query(x, z, radius, {}) do
		if e.alive then
			if knock and not e.def.big then
				local dx, dz = e.x - x, e.z - z
				local m = math.sqrt(dx * dx + dz * dz)
				if m > 0.01 then
					e.x, e.z = w.nav.resolve(e.x + dx / m * knock, e.z + dz / m * knock, e.def.radius)
				end
			end
			Combat.damage(w, p, e, dmg, 1, DF.BLAST, x, z)
		end
	end
end

-- Крио-патроны: a slowed enemy killed by the weapon shatters; shards strike and chill its neighbours.
-- Shard kills are depth 1, so they never shatter again (no cascades).
local shardBuf = {}
function Combat.shatter(w, p, x: number, z: number, fr: number, skip)
	local count = pick(fr, UV.UPG_FREEZE.shards)
	local list = w:query(x, z, UV.UPG_FREEZE.shardRadius, shardBuf)
	local t = w.t
	for _ = 1, count do
		local best, bd, bi = nil, math.huge, 0
		for i, e in list do
			if e.alive and e ~= skip and not e.invulnerable and not e.def.static then
				local d = (e.x - x) ^ 2 + (e.z - z) ^ 2
				if d < bd then
					best, bd, bi = e, d, i
				end
			end
		end
		if not best or not spend(p, 1) then
			break
		end
		list[bi] = list[#list]
		list[#list] = nil
		w:emit(E.ARC, x, z, best.x, best.z, C.BLUE)
		local slow = if best.def.boss then UV.UPG_FREEZE.bossCap else pick(fr, UV.UPG_FREEZE.slow)
		best.slow = math.max(if t < best.slowUntil then best.slow else 0, slow)
		best.slowUntil = math.max(best.slowUntil, t + UV.UPG_FREEZE.duration)
		best.chill = math.max(best.chill, pick(fr, UV.UPG_FREEZE.weaken))
		best.frail = math.max(best.frail, pick(fr, UV.UPG_FREEZE.frail))
		Combat.damage(w, p, best, p.stats.damage * UV.UPG_FREEZE.shardMult, 1, 0, x, z)
	end
end

-- ЛЕДЯНОЙ ПАНЦИРЬ: a frost burst around the player when the shield takes a hit or is refilled.
function Combat.frostNova(w, p)
	if not p.stats.frostShell or w.t < p.novaReady then
		return
	end
	local F = Defs.FrostShell
	local t = w.t
	p.novaReady = t + F.Cooldown
	w:emit(E.BOOM, p.x, p.z, F.Radius, C.BLUE)
	for _, e in w:query(p.x, p.z, F.Radius, nearBuf) do
		if e.alive and not e.def.static then
			if not e.def.big then
				e.stunUntil = math.max(e.stunUntil, t + F.Stun)
			end
			local slow = if e.def.boss then UV.UPG_FREEZE.bossCap else F.Slow
			e.slow = math.max(if t < e.slowUntil then e.slow else 0, slow)
			e.slowUntil = math.max(e.slowUntil, t + F.SlowTime)
			e.chill = math.max(e.chill, UV.UPG_FREEZE.weaken[1])
			Combat.damage(w, p, e, F.Damage, 1, DF.CARD, p.x, p.z)
		end
	end
end

-- Damage ----------------------------------------------------------------------------------------------
function Combat.damage(w, p, e, amount: number, depth: number, flags: number, fromX: number, fromZ: number): boolean
	if not e.alive or e.invulnerable then
		return false
	end
	local t = w.t
	local mult = 1
	if p and t < p.odUntil then
		mult *= 1 + Defs.Overdrive.DamageBonus
	end
	local vuln = if t < e.vulnUntil then e.vuln else 0
	mult *= 1 + vuln
	-- Крио-патроны: a slowed enemy is brittle for the whole squad.
	if e.frail > 0 and t < e.slowUntil then
		mult *= 1 + e.frail
	end
	local kind = e.kind
	if (kind == "EN_BULWARK" or e.def.elite) and vuln <= 0 and band(flags, DF.BURN) == 0 then
		local ax, az = fromX - e.x, fromZ - e.z
		local m = math.sqrt(ax * ax + az * az)
		if m > 0.01 and (ax * e.fx + az * e.fz) / m > Defs.Bulwark.FrontCos then
			mult *= Defs.Bulwark.FrontArmor
			flags = bor(flags, DF.ARMOR)
		end
	end
	if e.def.boss then
		if e.state == ST.EXPOSED then
			mult *= if kind == "BOSS_DEVOURER" then Defs.Devourer.ExposedMult else Defs.Boss.ExposedMult
		end
		if depth > 0 then
			mult *= 0.6
		end
	end
	amount *= mult
	e.hp -= amount
	e.dmgAcc += amount
	e.dmgFlags = bor(e.dmgFlags, flags)
	e.dmgFromX, e.dmgFromZ = fromX, fromZ
	if p then
		p.damage += amount
	end
	if e.hp <= 0 then
		local cause = if band(flags, DF.GRAV) ~= 0
			then 4
			elseif band(flags, DF.ENV) ~= 0 then 6
			elseif band(flags, DF.CARD) ~= 0 then 5
			elseif band(flags, DF.BLAST) ~= 0 then 2
			elseif band(flags, DF.BURN) ~= 0 then 3
			elseif band(flags, DF.ARC) ~= 0 then 1
			else 0
		w:kill(e, p, depth, cause)
		return true
	end
	return false
end

function Combat.burn(w, e, dt: number)
	local p = e.burnOwner
	if p and not w.players[p.id] then
		p = nil
	end
	Combat.damage(w, p, e, e.burnDps * dt, 1, DF.BURN, e.x, e.z)
end

function Combat.onKill(w, p, e, depth: number, cause: number)
	local t = w.t
	p.kills += 1
	p.combo += 1
	p.comboT = 2.5
	if p.combo > p.bestCombo then
		p.bestCombo = p.combo
	end
	-- Attribution: exactly one credited kill per death (World:kill guards e.alive).
	p.species[e.kind] = (p.species[e.kind] or 0) + 1
	p.causeKills[cause] = (p.causeKills[cause] or 0) + 1
	if cause == 4 then
		p.s01Stats.kills += 1
	elseif cause <= 3 then
		p.weaponKills += 1
		-- M20 feat counters (thematic, deterministic).
		local wid = p.weaponDef.id
		if cause == 1 and wid == "W_ARC_RIFLE" then
			p.feats.arcKills += 1
		elseif cause == 3 and wid == "W_SCATTERGUN" then
			p.feats.burnKills += 1
		elseif wid == "W_PLASMA_BEAM" and e.def.big and not e.def.static then
			p.feats.heavyKills += 1
		end
	end
	local sh = rank(p, "UPG_SHIELD")
	if sh > 0 then
		p.shieldKills += 1
		if p.shieldKills >= pick(sh, UV.UPG_SHIELD.every) then
			p.shieldKills = 0
			local amount = pick(sh, UV.UPG_SHIELD.amount)
			if amount > p.shield then
				p.shield = amount
				w:emit(E.SHIELD, p.id, amount)
			end
			Combat.frostNova(w, p)
			if w.mission then
				w.mission:shieldReactor(pick(sh, UV.UPG_SHIELD.reactor))
			end
		end
	end
	local fz = rank(p, "UPG_FREEZE")
	if fz > 0 and depth == 0 and cause <= 1 and t < e.slowUntil and e.slow > 0 then
		Combat.shatter(w, p, e.x, e.z, fz, e)
	end
	local dt = rank(p, "UPG_DETONATE")
	if dt > 0 and depth == 0 then
		p.killCount += 1
		if p.killCount >= pick(dt, UV.UPG_DETONATE.every) then
			p.killCount = 0
			Combat.blast(w, p, e.x, e.z, UV.UPG_DETONATE.radius, pick(dt, UV.UPG_DETONATE.damage), C.ORANGE, 3)
		end
	end
	-- PYRE synergy / Inferno Grinder: burning enemies erupt (never from blast kills, so no cascades).
	local inferno = p.evolved == "EV_INFERNO_GRINDER"
	local pyre = inferno or (dt > 0 and rank(p, "UPG_IGNITE") > 0)
	if pyre and cause ~= 2 and t < e.burnUntil and (depth == 0 or inferno) and t >= p.pyreReady then
		p.pyreReady = t + (if inferno then 0.08 else 0.25)
		local dmg = if dt > 0 then pick(dt, UV.UPG_DETONATE.damage) else 45
		Combat.blast(w, p, e.x, e.z, UV.UPG_DETONATE.radius * 1.25, dmg * (if inferno then 1.2 else 0.8), C.ORANGE, 2)
	end
end

-- Player update ---------------------------------------------------------------------------------------
function Combat.updatePlayer(w, p, dt: number)
	local t = w.t
	local s = p.stats
	local od = t < p.odUntil
	if od ~= (p.odFlag == true) then
		p.odFlag = od
		Combat.recompute(p)
		s = p.stats
	end
	p.procBudget = math.min(30, p.procBudget + 90 * dt)
	if p.comboT > 0 then
		p.comboT -= dt
		if p.comboT <= 0 then
			p.combo = 0
		end
	end
	-- Shock Dash
	local sd = rank(p, "UPG_DASH_SHOCK")
	if sd > 0 and t <= p.dashUntil + 0.05 then
		for _, e in w:query(p.x, p.z, UV.UPG_DASH_SHOCK.radius, nearBuf) do
			if not p.dashHit[e] then
				p.dashHit[e] = true
				e.stunUntil = math.max(e.stunUntil, t + UV.UPG_DASH_SHOCK.stun)
				-- ЛЕДОЛОМ: slowed enemies shatter for double damage.
				local shatter = s.iceBreak and t < e.slowUntil and e.slow > 0
				w:emit(E.ARC, p.x, p.z, e.x, e.z, if shatter then C.BLUE else C.LIME)
				local dmg = pick(sd, UV.UPG_DASH_SHOCK.damage) * (if shatter then Defs.IceBreakMult else 1)
				Combat.damage(w, p, e, dmg, 1, bor(DF.ARC, DF.CARD, if shatter then DF.CRIT else 0), p.x, p.z)
			end
		end
	end
	local wd = p.weaponDef
	if wd.kind == "beam" then
		if p.overheatT > 0 then
			p.overheatT -= dt
			p.heat = math.max(0, p.heat - Defs.Beam.CoolPerSecond * 1.5 * dt)
			if p.overheatT <= 0 then
				p.overheatT = 0
				p.heat = 0
			end
			p.cool = 0
		elseif p.firing then
			local heatRate = Defs.Beam.HeatPerSecond
				* (if od then 0.5 else 1)
				* (if p.evolved then 0.8 else 1)
				* (s.heatMult or 1)
			p.heat += heatRate * dt
			p.cool -= dt
			local guard = 0
			while p.cool <= 0 and guard < 4 do
				guard += 1
				p.cool += 1 / s.rate
				Combat.beamTick(w, p)
			end
			if p.heat >= 100 then
				p.heat = 100
				p.overheatT = s.reload
			end
		else
			p.heat = math.max(0, p.heat - Defs.Beam.CoolPerSecond * dt)
			p.cool = math.max(0, p.cool - dt)
		end
	else
		if p.reloadT > 0 then
			p.reloadT -= dt
			if p.reloadT <= 0 then
				p.reloadT = 0
				p.ammo = s.magazine
			end
		end
		if not p.firing or p.reloadT > 0 then
			p.spread = math.max(s.spreadMin, (p.spread or s.spreadMin) - s.recover * dt)
		end
		if p.firing and p.reloadT <= 0 then
			p.cool -= dt
			local guard = 0
			while p.cool <= 0 and p.ammo > 0 and guard < 4 do
				guard += 1
				p.cool += 1 / s.rate
				p.ammo -= 1
				Combat.fire(w, p)
			end
			if p.ammo <= 0 then
				Combat.startReload(w, p)
			end
		else
			p.cool = math.max(0, p.cool - dt)
		end
	end
end

-- Offers & evolution ----------------------------------------------------------------------------------
function Combat.isKey(p, id: string): boolean
	if p.evolved then
		return false
	end
	return table.find(Defs.Evolutions[p.weaponDef.evolution].keys, id) ~= nil
end

function Combat.makeOffer(w, p)
	local evo = Defs.Evolutions[p.weaponDef.evolution]
	local isKey = {}
	local missingKeys = 0
	-- Card keys only matter in legacy runs that still evolve from an elite core.
	local legacyEvo = w.op.runEvolution and not p.evolved
	if legacyEvo then
		for _, k in evo.keys do
			isKey[k] = true
			if cardRank(p, k) == 0 then
				missingKeys += 1
			end
		end
	end
	local freeSlots = Defs.Run.MaxSlots - p.slots
	local weights = {}
	local pool = {}
	for _, id in Defs.UpgradeOrder do
		local r = cardRank(p, id)
		local eligible = rank(p, id) < Defs.Run.MaxRank and (r > 0 or freeSlots > 0) and not p.banished[id]
		-- Never let filler upgrades lock the player out of their evolution.
		if r == 0 and not isKey[id] and freeSlots <= missingKeys then
			eligible = false
		end
		if eligible then
			local weight = 1
			if isKey[id] then
				weight = if p.hasCore then 4 else 1.8
			end
			if r > 0 then
				weight *= 1.25
			end
			-- Lean towards finishing a synergy the player has started (DD-017).
			if r == 0 then
				for _, sid in Defs.SynergyOrder do
					local keys = Defs.Synergies[sid].keys
					local other = if keys[1] == id then keys[2] elseif keys[2] == id then keys[1] else nil
					if other and rank(p, other) > 0 then
						weight *= 1.8
						break
					end
				end
			end
			weights[id] = weight
			table.insert(pool, id)
		end
	end
	local choices = {}
	local cards = p.cards or 3
	-- First offer of a run: one card of each style, so the choice is between ways of fighting.
	if p.offersMade == 0 and not legacyEvo then
		for _, style in Defs.StyleOrder do
			local sw, sp = {}, {}
			for _, id in pool do
				if weights[id] and Defs.Upgrades[id].style == style then
					sw[id] = weights[id]
					table.insert(sp, id)
				end
			end
			local id = w.rng:weighted(sw, sp)
			if id then
				weights[id] = nil
				table.insert(choices, id)
			end
		end
	end
	-- 02.4 §4.2: a new profile's second offer in O01 shows «Расщепление» (shown, never forced).
	if p.newbie and p.offersMade == 1 and w.op.id == "O01" and weights.UPG_MULTISHOT and not p.seenMulti then
		weights.UPG_MULTISHOT = nil
		table.insert(choices, "UPG_MULTISHOT")
	end
	while #choices < cards do
		local id = w.rng:weighted(weights, pool)
		if not id then
			break
		end
		weights[id] = nil
		table.insert(choices, id)
	end
	if table.find(choices, "UPG_MULTISHOT") then
		p.seenMulti = true
	end
	-- Guarantees: the first offer and every post-core offer contain a missing evolution key.
	if legacyEvo and (p.offersMade == 0 or p.hasCore) then
		for _, k in evo.keys do
			if cardRank(p, k) == 0 and not table.find(choices, k) and (freeSlots > 0) then
				if #choices < cards then
					table.insert(choices, k)
				else
					-- Replace the first non-key choice.
					for i, c in choices do
						if not isKey[c] then
							choices[i] = k
							break
						end
					end
				end
				if p.offersMade == 0 then
					break
				end
			end
		end
	end
	if #choices < cards then
		table.insert(choices, "FB_REPAIR")
	end
	if #choices < cards then
		table.insert(choices, "FB_CHARGE")
	end
	p.offerSeq += 1
	p.offersMade += 1
	p.offer = { id = p.offerSeq, choices = choices }
end

function Combat.applyChoice(w, p, choice: string)
	if choice == "FB_REPAIR" then
		w:heal(p, 35)
	elseif choice == "FB_CHARGE" then
		p.s01Ready = w.t
	elseif Defs.Upgrades[choice] then
		local r = cardRank(p, choice)
		if r == 0 then
			if p.slots >= Defs.Run.MaxSlots then
				return
			end
			p.slots += 1
		end
		p.ranks[choice] = math.min(Defs.Run.MaxRank, r + 1)
		Combat.recompute(p)
		Combat.checkEvolve(w, p)
		for _, sid in Defs.SynergyOrder do
			if not p.synergies[sid] and Combat.synergyActive(p, sid) then
				p.synergies[sid] = true
				local syn = Defs.Synergies[sid]
				w:banner(
					"СИНЕРГИЯ: " .. syn.name,
					(if w.solo then "" else p.name .. " · ") .. syn.text,
					C.VIOLET,
					3,
					"evolve"
				)
			end
		end
	end
end

function Combat.checkEvolve(w, p)
	if p.evolved or p.canEvolve or not p.hasCore then
		return
	end
	local evo = Defs.Evolutions[p.weaponDef.evolution]
	for _, k in evo.keys do
		if rank(p, k) == 0 then
			return
		end
	end
	p.canEvolve = true
	w:banner(
		"ЭВОЛЮЦИЯ ГОТОВА",
		evo.name .. " — нажми F или кнопку ЭВО",
		C.GOLD,
		4,
		"evolve"
	)
end

return Combat
