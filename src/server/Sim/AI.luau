--!nonstrict
-- Enemy behaviours. Lightweight data agents: flow-field + line-of-sight steering, soft separation via
-- the spatial grid, and readable telegraph -> attack -> recover cycles. Every attack is telegraphed.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Outpost = require(script.Parent.Outpost)
local Codec = require(Shared:WaitForChild("Codec"))
local Combat = require(script.Parent.Combat)

local E, C, SH = Codec.E, Codec.C, Codec.Shape
local ST = Codec.State
local PLAYER_R = Defs.Player.Radius

local AI = {}

local sepBuf = {}

local function turnToward(e, tx: number, tz: number, rate: number, dt: number)
	local m = math.sqrt(tx * tx + tz * tz)
	if m < 1e-4 then
		return
	end
	tx, tz = tx / m, tz / m
	if rate <= 0 then
		e.fx, e.fz = tx, tz
		return
	end
	local a = math.atan2(e.fx, e.fz)
	local b = math.atan2(tx, tz)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	local step = rate * dt
	a += math.clamp(d, -step, step)
	e.fx, e.fz = math.sin(a), math.cos(a)
end

local function speedOf(w, e): number
	local s = e.def.speed * (e.speedMult or 1)
	if w.t < e.slowUntil then
		s *= 1 - e.slow
	end
	return s
end

-- Steers toward p (or away when flee), with separation and obstacle resolution.
local function steer(w, e, p, dist: number, dt: number, standoff: number, turnRate: number, flee: boolean?)
	local t = w.t
	local dx, dz = p.x - e.x, p.z - e.z
	if t >= e.losT then
		e.losT = t + 0.22 + w.rng:next() * 0.12
		e.los = dist < 80 and w.nav.clear(e.x, e.z, p.x, p.z, math.min(e.def.radius, 2))
	end
	local mx, mz = 0, 0
	if flee then
		local fx, fz = w.nav.flow(w.field, e.x, e.z)
		mx, mz = -dx / dist * 0.8 - fx * 0.2, -dz / dist * 0.8 - fz * 0.2
	elseif dist > standoff then
		if e.los and dist > 0.01 then
			mx, mz = dx / dist, dz / dist
		else
			mx, mz = w.nav.flow(e.flow or w.field, e.x, e.z)
		end
	end
	-- Separation
	local r = e.def.radius
	local sx, sz = 0, 0
	for _, o in w:query(e.x, e.z, r + 3, sepBuf) do
		if o ~= e and not o.def.static then
			local ox, oz = e.x - o.x, e.z - o.z
			local d = math.sqrt(ox * ox + oz * oz)
			local min = r + o.def.radius
			if d < min and d > 1e-3 then
				local push = (min - d) / min * math.min(2, o.def.radius / r)
				sx += ox / d * push
				sz += oz / d * push
			end
		end
	end
	local vx, vz = mx + sx * 1.3, mz + sz * 1.3
	local m = math.sqrt(vx * vx + vz * vz)
	if m > 1 then
		vx, vz = vx / m, vz / m
	end
	local speed = speedOf(w, e)
	e.x += vx * speed * dt
	e.z += vz * speed * dt
	e.x, e.z = w.nav.resolve(e.x, e.z, r)
	if flee then
		turnToward(e, dx, dz, turnRate, dt)
	elseif mx ~= 0 or mz ~= 0 then
		turnToward(e, if dist < 30 then dx else mx, if dist < 30 then dz else mz, turnRate, dt)
	end
	-- Unstick: if barely moving while far from target for a while, jitter sideways.
	if dist > standoff + 4 and not flee then
		local moved = (e.x - e.lastX) ^ 2 + (e.z - e.lastZ) ^ 2
		if moved < (speed * dt * 0.15) ^ 2 then
			e.stuckT += dt
			if e.stuckT > 1.2 then
				e.stuckT = 0
				e.x, e.z = w.nav.resolve(e.x + w.rng:range(-3, 3), e.z + w.rng:range(-3, 3), r)
			end
		else
			e.stuckT = 0
		end
	end
	e.lastX, e.lastZ = e.x, e.z
end

local function setState(w, e, state: number, duration: number)
	e.state = state
	e.stateUntil = w.t + duration
end

local function contact(e, p, pad: number): boolean
	local dx, dz = p.x - e.x, p.z - e.z
	local r = e.def.radius + PLAYER_R + pad
	return dx * dx + dz * dz < r * r
end

local function inCone(e, p, radius: number, cosHalf: number): boolean
	local dx, dz = p.x - e.x, p.z - e.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > radius + PLAYER_R then
		return false
	end
	if d < e.def.radius + PLAYER_R then
		return true
	end
	return (dx * e.aimX + dz * e.aimZ) / d >= cosHalf
end

-- Behaviours ------------------------------------------------------------------------------------------
local B = {}

function B.EN_RUNNER(w, e, p, dist, dt)
	if e.state == ST.MOVE then
		steer(w, e, p, dist, dt, e.def.radius + PLAYER_R + 0.2, 0)
		if w.t >= e.cd and contact(e, p, 0.7) then
			e.cd = w.t + e.def.cooldown
			w:hurtPlayer(p, e.def.damage, e.x, e.z, e)
		end
	end
end

function B.EN_STALKER(w, e, p, dist, dt)
	local S = Defs.Stalker
	local t = w.t
	if e.state == ST.MOVE then
		steer(w, e, p, dist, dt, e.def.radius + PLAYER_R + 0.2, 0)
		if dist < S.Trigger and t >= e.cd and e.los then
			e.cd = t + e.def.cooldown
			e.aimX, e.aimZ = (p.x - e.x) / dist, (p.z - e.z) / dist
			e.fx, e.fz = e.aimX, e.aimZ
			setState(w, e, ST.WINDUP, S.Windup)
			w:emit(E.TELE, SH.LINE, e.x, e.z, e.aimX, e.aimZ, S.LungeSpeed * S.LungeTime + 2, 3.4, S.Windup, C.RED, 0)
		end
	elseif e.state == ST.WINDUP then
		if t >= e.stateUntil then
			e.struck = false
			setState(w, e, ST.ATTACK, S.LungeTime)
		end
	elseif e.state == ST.ATTACK then
		e.x += e.aimX * S.LungeSpeed * dt
		e.z += e.aimZ * S.LungeSpeed * dt
		e.x, e.z = w.nav.resolve(e.x, e.z, e.def.radius)
		if not e.struck then
			for _, pl in w.playerList do
				if pl.alive and contact(e, pl, 0.8) then
					e.struck = true
					w:hurtPlayer(pl, e.def.damage, e.x, e.z, e)
				end
			end
		end
		if t >= e.stateUntil then
			setState(w, e, ST.RECOVER, S.Recover)
		end
	elseif e.state == ST.RECOVER and t >= e.stateUntil then
		e.state = ST.MOVE
	end
end

function B.EN_SPITTER(w, e, p, dist, dt)
	local S = Defs.Spitter
	local t = w.t
	if e.state == ST.MOVE then
		if dist > S.MaxRange or not e.los then
			steer(w, e, p, dist, dt, S.MinRange + 4, 0)
		elseif dist < S.MinRange then
			steer(w, e, p, dist, dt, 0, 0, true)
		else
			-- Hold range: only separation moves it.
			steer(w, e, p, dist, dt, dist + 1, 0)
			turnToward(e, p.x - e.x, p.z - e.z, 0, dt)
		end
		if
			t >= e.cd
			and e.los
			and dist <= S.MaxRange + 4
			and dist >= S.MinRange - 10
			and w:countHazards("spit") < 6
		then
			e.cd = t + e.def.cooldown
			setState(w, e, ST.WINDUP, S.Windup)
		end
	elseif e.state == ST.WINDUP then
		turnToward(e, p.x - e.x, p.z - e.z, 0, dt)
		if t >= e.stateUntil then
			local tx, tz = w.nav.resolve(p.x, p.z, 1)
			w:addHazard({
				source = "spit",
				shape = SH.CIRCLE,
				x = tx,
				z = tz,
				dx = 0,
				dz = 1,
				a = S.Radius,
				b = 0,
				activeFrom = t + S.Telegraph,
				untilT = t + S.Telegraph + S.Active,
				damage = e.def.damage,
				tick = S.Tick,
			})
			w:emit(E.SPIT, e.x, e.z, tx, tz, S.Telegraph * 0.85)
			w:emit(E.TELE, SH.CIRCLE, tx, tz, 0, 1, S.Radius, 0, S.Telegraph, C.LIME, S.Active)
			setState(w, e, ST.RECOVER, 0.45)
		end
	elseif e.state == ST.RECOVER and t >= e.stateUntil then
		e.state = ST.MOVE
	end
end

local function slam(w, e, reach: number, damage: number)
	for _, pl in w.playerList do
		if pl.alive and inCone(e, pl, reach, math.cos(math.rad(55))) then
			w:hurtPlayer(pl, damage, e.x, e.z, e)
		end
	end
	w:emit(E.BOOM, e.x + e.aimX * reach * 0.5, e.z + e.aimZ * reach * 0.5, reach * 0.6, C.RED)
end

function B.EN_BULWARK(w, e, p, dist, dt)
	local K = Defs.Bulwark
	local t = w.t
	local reach = K.Reach + e.def.radius
	if e.state == ST.MOVE then
		steer(w, e, p, dist, dt, e.def.radius + PLAYER_R, 1.7)
		if dist < reach - 1 and t >= e.cd then
			e.cd = t + e.def.cooldown
			e.aimX, e.aimZ = e.fx, e.fz
			setState(w, e, ST.WINDUP, K.Windup)
			w:emit(E.TELE, SH.CONE, e.x, e.z, e.aimX, e.aimZ, reach, 110, K.Windup, C.RED, 0)
		end
	elseif e.state == ST.WINDUP then
		if t >= e.stateUntil then
			slam(w, e, reach, e.def.damage)
			setState(w, e, ST.RECOVER, 0.6)
		end
	elseif e.state == ST.RECOVER and t >= e.stateUntil then
		e.state = ST.MOVE
	end
end

function B.ELITE_BULWARK(w, e, p, dist, dt)
	local K, L = Defs.Bulwark, Defs.Elite
	local t = w.t
	local reach = K.Reach + e.def.radius + 2
	if e.state == ST.MOVE then
		steer(w, e, p, dist, dt, e.def.radius + PLAYER_R, 1.4)
		if dist < reach - 1 and t >= e.cd then
			e.cd = t + e.def.cooldown
			e.mode = "slam"
			e.aimX, e.aimZ = e.fx, e.fz
			setState(w, e, ST.WINDUP, K.Windup + 0.15)
			w:emit(E.TELE, SH.CONE, e.x, e.z, e.aimX, e.aimZ, reach, 110, K.Windup + 0.15, C.RED, 0)
		elseif dist > 16 and dist < 48 and t >= e.cd2 and e.los then
			e.cd2 = t + L.ChargeCooldown
			e.mode = "charge"
			e.aimX, e.aimZ = (p.x - e.x) / dist, (p.z - e.z) / dist
			e.fx, e.fz = e.aimX, e.aimZ
			setState(w, e, ST.WINDUP, L.ChargeWindup)
			w:emit(
				E.TELE,
				SH.LINE,
				e.x,
				e.z,
				e.aimX,
				e.aimZ,
				L.ChargeSpeed * L.ChargeTime + 4,
				e.def.radius * 2 + 2,
				L.ChargeWindup,
				C.RED,
				0
			)
		end
	elseif e.state == ST.WINDUP then
		if t >= e.stateUntil then
			if e.mode == "slam" then
				slam(w, e, reach, e.def.damage)
				setState(w, e, ST.RECOVER, 0.7)
			else
				e.hitSet = {}
				setState(w, e, ST.ATTACK, L.ChargeTime)
			end
		end
	elseif e.state == ST.ATTACK then
		local px, pz = e.x, e.z
		e.x += e.aimX * L.ChargeSpeed * dt
		e.z += e.aimZ * L.ChargeSpeed * dt
		e.x, e.z = w.nav.resolve(e.x, e.z, e.def.radius)
		for _, pl in w.playerList do
			if pl.alive and not e.hitSet[pl] and contact(e, pl, 1) then
				e.hitSet[pl] = true
				w:hurtPlayer(pl, e.def.damage + 4, e.x, e.z, e)
			end
		end
		local blocked = (e.x - px) ^ 2 + (e.z - pz) ^ 2 < (L.ChargeSpeed * dt * 0.3) ^ 2
		if t >= e.stateUntil or blocked then
			if blocked then
				w:emit(E.BOOM, e.x, e.z, 7, C.ORANGE)
			end
			setState(w, e, ST.RECOVER, 1.0)
		end
	elseif e.state == ST.RECOVER and t >= e.stateUntil then
		e.state = ST.MOVE
	end
end

function B.HIVE(w, e, p, dist, dt)
	if e.state == ST.MOVE or e.state == ST.IDLE then
		e.state = ST.IDLE
		turnToward(e, math.cos(w.t * 0.5), math.sin(w.t * 0.5), 0, dt)
		-- Power nodes and acid sources are structures: they never hatch runners.
		if w.t >= e.cd and not e.noSpawn then
			e.cd = w.t + Defs.Enemies.HIVE.cooldown
			if #w.enemies < Defs.Run.MaxActive * (1 + 0.45 * (#w.playerList - 1)) + 12 then
				local a = w.rng:range(0, math.pi * 2)
				local x, z = w.nav.resolve(e.x + math.cos(a) * 7, e.z + math.sin(a) * 7, 1.6)
				w:spawnEnemy("EN_RUNNER", x, z, 0.5)
			end
		end
	end
end

-- Broodmother ---------------------------------------------------------------------------------------
local function bossPhase(e): number
	local f = e.hp / e.maxHp
	return if f > 0.65 then 1 elseif f > 0.3 then 2 else 3
end

function B.BOSS_BROODMOTHER(w, e, p, dist, dt)
	local K = Defs.Boss
	local t = w.t
	local enr = w.enraged
	local wind = if enr then 0.8 else 1
	if e.state == ST.ENTER then
		local dz = 108 - e.z
		e.z += math.clamp(dz, -10 * dt, 10 * dt)
		e.fx, e.fz = 0, -1
		if t >= e.stateUntil then
			e.invulnerable = false
			e.state = ST.MOVE
			e.cd = t + 2
			e.summonT = t + 5
		end
		return
	end
	local phase = bossPhase(e)
	if e.state == ST.MOVE then
		steer(w, e, p, dist, dt, 12, 1.5)
		if t >= (e.summonT or 0) then
			e.summonT = t + K.SummonEvery * (if enr then 0.7 else 1)
			local count = 5 + phase * 2
			for i = 1, count do
				local a = i / count * math.pi * 2
				local x, z =
					w.nav.resolve(e.x + math.cos(a) * (e.def.radius + 4), e.z + math.sin(a) * (e.def.radius + 4), 1.6)
				w:spawnEnemy("EN_RUNNER", x, z, 0.6)
			end
			w:emit(E.BOOM, e.x, e.z, e.def.radius + 6, C.LIME)
		end
		if t >= e.cd then
			e.aimX, e.aimZ = (p.x - e.x) / dist, (p.z - e.z) / dist
			e.fx, e.fz = e.aimX, e.aimZ
			local roll = w.rng:next()
			if dist < K.SweepRadius + 1 and (phase == 1 or roll < 0.5) then
				e.mode = "sweep"
				setState(w, e, ST.WINDUP, K.SweepWindup * wind)
				w:emit(
					E.TELE,
					SH.CONE,
					e.x,
					e.z,
					e.aimX,
					e.aimZ,
					K.SweepRadius,
					K.SweepAngle,
					K.SweepWindup * wind,
					C.RED,
					0
				)
			elseif phase >= 3 and roll < 0.75 and dist > 14 then
				e.mode = "charge"
				setState(w, e, ST.WINDUP, K.ChargeWindup * wind)
				w:emit(
					E.TELE,
					SH.LINE,
					e.x,
					e.z,
					e.aimX,
					e.aimZ,
					K.ChargeSpeed * K.ChargeTime + 6,
					e.def.radius * 2 + 2,
					K.ChargeWindup * wind,
					C.RED,
					0
				)
			elseif phase >= 2 then
				e.mode = "lanes"
				setState(w, e, ST.WINDUP, K.LaneWindup * wind)
				local px, pz = -e.aimZ, e.aimX
				for k = -1, 1 do
					local lx, lz = e.x + px * k * 11, e.z + pz * k * 11
					w:addHazard({
						source = "lane",
						shape = SH.LINE,
						x = lx,
						z = lz,
						dx = e.aimX,
						dz = e.aimZ,
						a = K.LaneLength,
						b = K.LaneWidth,
						activeFrom = t + K.LaneWindup * wind,
						untilT = t + K.LaneWindup * wind + K.LaneActive,
						damage = K.LaneDamage,
						tick = 0.6,
					})
					w:emit(
						E.TELE,
						SH.LINE,
						lx,
						lz,
						e.aimX,
						e.aimZ,
						K.LaneLength,
						K.LaneWidth,
						K.LaneWindup * wind,
						C.LIME,
						K.LaneActive
					)
				end
			else
				e.cd = t + 0.8 -- approach a bit more
			end
		end
	elseif e.state == ST.WINDUP then
		if t >= e.stateUntil then
			if e.mode == "sweep" then
				for _, pl in w.playerList do
					if pl.alive and inCone(e, pl, K.SweepRadius, math.cos(math.rad(K.SweepAngle / 2))) then
						w:hurtPlayer(pl, K.SweepDamage, e.x, e.z, e)
					end
				end
				w:emit(E.BOOM, e.x + e.aimX * 12, e.z + e.aimZ * 12, 14, C.RED)
				setState(w, e, ST.RECOVER, K.Recover)
				e.cd = t + K.Recover + (if enr then 1.4 else 2.2)
			elseif e.mode == "charge" then
				e.hitSet = {}
				setState(w, e, ST.ATTACK, K.ChargeTime)
			else
				setState(w, e, ST.EXPOSED, K.ExposedTime * 0.6)
				w:emit(E.BOSS, 2)
			end
		end
	elseif e.state == ST.ATTACK then
		local px, pz = e.x, e.z
		e.x += e.aimX * K.ChargeSpeed * dt
		e.z += e.aimZ * K.ChargeSpeed * dt
		e.x, e.z = w.nav.resolve(e.x, e.z, e.def.radius)
		for _, pl in w.playerList do
			if pl.alive and not e.hitSet[pl] and contact(e, pl, 1) then
				e.hitSet[pl] = true
				w:hurtPlayer(pl, K.ChargeDamage, e.x, e.z, e)
			end
		end
		local blocked = (e.x - px) ^ 2 + (e.z - pz) ^ 2 < (K.ChargeSpeed * dt * 0.3) ^ 2
		if t >= e.stateUntil or blocked then
			w:emit(E.BOOM, e.x, e.z, 12, C.ORANGE)
			setState(w, e, ST.EXPOSED, K.ExposedTime)
			w:emit(E.BOSS, 2)
		end
	elseif e.state == ST.EXPOSED then
		if t >= e.stateUntil then
			e.state = ST.MOVE
			e.cd = t + (if enr then 0.9 else 1.4)
		end
	elseif e.state == ST.RECOVER then
		if t >= e.stateUntil then
			e.state = ST.MOVE
		end
	end
end

-- Bomber: sprints in, fuses (telegraphed circle), detonates — hurting players AND nearby swarm.
function AI.bomberBlast(w, e, killer, hurtPlayers: boolean)
	local K = Defs.Bomber
	if e.blasted then
		return
	end
	e.blasted = true
	w:emit(E.BOOM, e.x, e.z, K.Radius, C.ORANGE)
	if hurtPlayers then
		for _, pl in w.playerList do
			if pl.alive and (pl.x - e.x) ^ 2 + (pl.z - e.z) ^ 2 < (K.Radius + PLAYER_R) ^ 2 then
				w:hurtPlayer(pl, e.def.damage, e.x, e.z, e)
			end
		end
	end
	for _, o in w:query(e.x, e.z, K.Radius, {}) do
		if o ~= e and o.alive then
			Combat.damage(
				w,
				killer,
				o,
				K.EnemyDamage * (if o.def.boss then 0.3 else 1),
				1,
				bit32.bor(Codec.DF.BLAST, Codec.DF.ENV),
				e.x,
				e.z
			)
		end
	end
end

function B.EN_BOMBER(w, e, p, dist, dt)
	local K = Defs.Bomber
	local t = w.t
	if e.state == ST.MOVE then
		steer(w, e, p, dist, dt, 0.5, 0)
		if dist < K.Trigger then
			setState(w, e, ST.WINDUP, K.Fuse)
			w:emit(E.TELE, SH.CIRCLE, e.x, e.z, 0, 1, K.Radius, 0, K.Fuse, C.ORANGE, 0)
		end
	elseif e.state == ST.WINDUP then
		if t >= e.stateUntil then
			AI.bomberBlast(w, e, nil, true)
			w:kill(e, nil, 1, 2)
		end
	end
end

-- Devourer -------------------------------------------------------------------------------------------
local function devourerPhase(e): number
	local f = e.hp / e.maxHp
	return if f > 0.6 then 1 elseif f > 0.25 then 2 else 3
end

function B.BOSS_DEVOURER(w, e, p, dist, dt)
	local K = Defs.Devourer
	local t = w.t
	local enr = w.enraged
	local wind = if enr then 0.8 else 1
	if e.state == ST.ENTER then
		e.fx, e.fz = 0, -1
		if t >= e.stateUntil then
			e.invulnerable = false
			e.state = ST.MOVE
			e.cd = t + 1.5
			e.summonT = t + 6
		end
		return
	end
	local phase = devourerPhase(e)
	if e.state == ST.MOVE then
		steer(w, e, p, dist, dt, 9, 2.2)
		if t >= (e.summonT or 0) then
			e.summonT = t + K.SummonEvery * (if enr then 0.7 else 1)
			for i = 1, 3 + phase do
				local a = i / (3 + phase) * math.pi * 2
				local x, z = w.nav.resolve(e.x + math.cos(a) * 12, e.z + math.sin(a) * 12, 1.7)
				w:spawnEnemy("EN_BOMBER", x, z, 0.7)
			end
		end
		if t >= e.cd then
			e.aimX, e.aimZ = (p.x - e.x) / dist, (p.z - e.z) / dist
			e.fx, e.fz = e.aimX, e.aimZ
			local roll = w.rng:next()
			if dist < K.BiteRadius + 1 and roll < 0.6 then
				e.mode = "bite"
				setState(w, e, ST.WINDUP, K.BiteWindup * wind)
				w:emit(
					E.TELE,
					SH.CONE,
					e.x,
					e.z,
					e.aimX,
					e.aimZ,
					K.BiteRadius,
					K.BiteAngle,
					K.BiteWindup * wind,
					C.RED,
					0
				)
			elseif phase >= 2 and roll < (if phase == 3 then 0.75 else 0.5) then
				e.mode = "burrow"
				e.invulnerable = true
				setState(w, e, ST.IDLE, K.BurrowTime)
				w:emit(E.BOSS, 5)
			else
				e.mode = "ring"
				setState(w, e, ST.WINDUP, K.RingWindup * wind)
				local n = K.RingCount + (if phase == 3 then 4 else 0)
				local offset = w.rng:next() * math.pi * 2
				for i = 1, n do
					local a = offset + i / n * math.pi * 2
					local d = K.RingDistance + (i % 2) * 7
					local x, z = w.nav.resolve(e.x + math.cos(a) * d, e.z + math.sin(a) * d, 1)
					w:addHazard({
						source = "ring",
						shape = SH.CIRCLE,
						x = x,
						z = z,
						dx = 0,
						dz = 1,
						a = K.RingRadius,
						b = 0,
						activeFrom = t + K.RingWindup * wind,
						untilT = t + K.RingWindup * wind + K.RingActive,
						damage = K.RingDamage,
						tick = 0.6,
					})
					w:emit(E.TELE, SH.CIRCLE, x, z, 0, 1, K.RingRadius, 0, K.RingWindup * wind, C.LIME, K.RingActive)
				end
			end
		end
	elseif e.state == ST.IDLE then
		-- Burrowed: tunnel toward the target, then telegraph the eruption right under them.
		local speed = 34
		local m = math.max(dist, 0.01)
		e.x, e.z = w.nav.resolve(
			e.x + (p.x - e.x) / m * math.min(speed * dt, dist),
			e.z + (p.z - e.z) / m * math.min(speed * dt, dist),
			e.def.radius
		)
		if t >= e.stateUntil then
			e.mode = "erupt"
			setState(w, e, ST.WINDUP, K.EruptWindup * wind)
			w:emit(E.TELE, SH.CIRCLE, e.x, e.z, 0, 1, K.EruptRadius, 0, K.EruptWindup * wind, C.RED, 0)
		end
	elseif e.state == ST.WINDUP then
		if t >= e.stateUntil then
			if e.mode == "bite" then
				for _, pl in w.playerList do
					if pl.alive and inCone(e, pl, K.BiteRadius, math.cos(math.rad(K.BiteAngle / 2))) then
						w:hurtPlayer(pl, K.BiteDamage, e.x, e.z, e)
					end
				end
				w:emit(E.BOOM, e.x + e.aimX * 8, e.z + e.aimZ * 8, 9, C.RED)
				setState(w, e, ST.RECOVER, 1.2)
				e.cd = t + 1.2 + (if enr then 1.2 else 2)
			elseif e.mode == "erupt" then
				e.invulnerable = false
				for _, pl in w.playerList do
					if pl.alive and (pl.x - e.x) ^ 2 + (pl.z - e.z) ^ 2 < (K.EruptRadius + PLAYER_R) ^ 2 then
						w:hurtPlayer(pl, K.EruptDamage, e.x, e.z, e)
					end
				end
				w:emit(E.BOOM, e.x, e.z, K.EruptRadius + 3, C.LIME)
				w:emit(E.BOSS, 2)
				setState(w, e, ST.EXPOSED, K.ExposedTime)
			else
				setState(w, e, ST.RECOVER, 0.8)
				e.cd = t + 0.8 + (if enr then 1 else 1.8)
			end
		end
	elseif e.state == ST.EXPOSED or e.state == ST.RECOVER then
		if t >= e.stateUntil then
			e.state = ST.MOVE
			e.cd = math.max(e.cd, t + 1)
		end
	end
end

-- Objective kinds reuse proven behaviours: the carrier fights like the elite Bulwark, structures idle.
B.ELITE_CARRIER = B.ELITE_BULWARK
-- Raid outposts: turrets act, the core just stands there.
B.TUR_STING = function(w, e, _p, _dist, dt)
	Outpost.hostile(w, e, dt)
end
B.TUR_ARC = B.TUR_STING
B.TUR_MORTAR = B.TUR_STING
B.TUR_SHIELD = B.TUR_STING
B.OUTPOST_CORE = function(_w, e)
	e.state = 8
end
B.NODE = B.HIVE
B.ACID_SOURCE = B.HIVE

-- Update ----------------------------------------------------------------------------------------------
function AI.update(w, dt: number)
	local t = w.t
	for _, e in w.enemies do
		if not e.alive then
			continue
		end
		if e.burnDps > 0 and t < e.burnUntil then
			Combat.burn(w, e, dt)
			if not e.alive then
				continue
			end
		end
		local p, dist = w:nearestPlayer(e.x, e.z)
		if e.role then
			p, dist = w.mission:targetFor(e, p, dist)
		end
		if not p then
			continue
		end
		dist = math.max(dist, 0.01)
		if e.state == ST.SPAWN then
			if t >= e.stateUntil then
				e.state = if e.def.static then ST.IDLE else ST.MOVE
			end
			continue
		end
		if t < e.stunUntil and not e.def.big then
			e.state = ST.STUN
			continue
		elseif e.state == ST.STUN then
			e.state = ST.MOVE
		end
		if e.muts then
			Outpost.regen(w, e, dt)
		end
		local behaviour = B[e.kind]
		if behaviour then
			behaviour(w, e, p, dist, dt)
		end
	end
end

return AI
