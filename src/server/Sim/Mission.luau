--!nonstrict
-- Operation objectives: the reactor and the mission state machine (pure Luau, driven by World).
-- The reactor (or the depths' energy heart) is a defendable object with HP. Strike groups are announced
-- with a direction before they can reach it; it is only hurt by contact or acid next to it (DD-004).
-- Objective types (D02): carrier (O01), relay (O02), nests (O03), boss (O04/O06), nodes (O05), acid (C-A01).
-- Non-boss operations: objective done -> separate final pressure phase -> WIN (D02 §3); boss operations
-- win on the boss kill (World:kill).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Outpost = require(script.Parent.Outpost)
local Codec = require(Shared:WaitForChild("Codec"))

local E, C, SH = Codec.E, Codec.C, Codec.Shape

local Mission = {}
Mission.__index = Mission

local DIR_NAME = { N = "С", NE = "СВ", E = "В", SE = "ЮВ", S = "Ю", SW = "ЮЗ", W = "З", NW = "СЗ" }
Mission.DirName = DIR_NAME

-- Enemies on objective duty switch to a player who comes this close (they defend themselves).
local RETALIATE = 10
-- Relay charge per kill inside the zone (D02 §5.1, TUNABLE).
local RELAY_CHARGE = { EN_RUNNER = 1, EN_SPITTER = 2, EN_STALKER = 3, EN_BULWARK = 3, EN_BOMBER = 1 }

local function ringField(w, cx: number, cz: number, r: number)
	local field = w.nav.newField()
	w.nav.buildField(field, { { cx + r, cz }, { cx - r, cz }, { cx, cz + r }, { cx, cz - r } })
	return field
end

function Mission.new(w, op)
	local self = setmetatable({}, Mission)
	self.w = w
	self.op = op
	self.state = "FIGHT" -- FIGHT -> FINALE -> DONE
	self.goal = op.goal
	self.beatIndex = 1
	self.eliteKilled = false
	self.eliteSpawned = false
	self.finaleUntil = nil
	self.components = {}
	self.assaults = 0
	self.reactor = nil
	self.targets = {} -- objective entities (nests / nodes / acid sources): enemy records
	self.destroyed = 0
	self.marks = {}
	-- Repeat variant (D02 §11.2): which relay coil starts, which nest the Bulwark guards.
	self.relayPrimary = op.relay and op.relay.primary
	self.relayBackup = op.relay and op.relay.backup
	self.guardShift = 0
	if w.replay then
		if op.relay then
			local coils = #w.map.coils
			self.relayPrimary = w.rng:int(1, coils)
			self.relayBackup = (self.relayPrimary % coils) + 1
		end
		self.guardShift = w.rng:int(0, 2)
	end
	if op.reactor then
		local hp = op.reactor.hp * Defs.Reactor.hpScale(w.threat, #w.playerList)
		local radius = op.reactor.radius or Defs.Reactor.Radius
		self.reactor = {
			obj = "reactor",
			name = op.reactor.name or "БУР",
			x = 0,
			z = 0,
			r = radius,
			hp = hp,
			maxHp = hp,
			alive = true,
			warned = {},
			lastHitT = -99,
			damageTaken = 0,
			shield = 0, -- «Барьер» covers the reactor too (DD-017); refilled, never stacked
		}
		self.reactor.field = ringField(w, 0, 0, radius + 3)
	end
	return self
end

-- Objectives as targets -----------------------------------------------------------------------------
local function proxyFor(e, obj, rim: number, key: string)
	local dx, dz = e.x - obj.x, e.z - obj.z
	local m = math.sqrt(dx * dx + dz * dz)
	if m < 1e-3 then
		dx, dz, m = 0, 1, 1
	end
	local t = e[key]
	if not t then
		t = { isReactor = true, alive = true, id = 0, r = Defs.Player.Radius }
		e[key] = t
	end
	t.obj = obj
	t.x, t.z = obj.x + dx / m * rim, obj.z + dz / m * rim
	return t, math.max(0.01, m - rim)
end

-- Enemies with role "R" walk to the reactor's rim on the side they come from; role "Y" hunt the relay.
function Mission:targetFor(e, p, dist)
	local obj = nil
	if e.role == "R" then
		obj = self.reactor
	elseif e.role == "Y" then
		obj = self.relay and self.relay.coil
	end
	if not obj or not obj.alive then
		e.flow = nil
		return p, dist
	end
	if p and dist < RETALIATE then
		e.flow = nil
		return p, dist
	end
	-- Aim point just outside the hull, so line-of-sight checks and acid throws resolve on open floor.
	e.flow = obj.field
	return proxyFor(e, obj, obj.r + 2.5, "rtarget")
end

-- Damage routed from AI attacks on a proxy (World:hurtPlayer) and acid puddles.
function Mission:hurtObject(obj, amount: number, fromX: number, fromZ: number, acid: boolean?): boolean
	local w = self.w
	if not obj or not obj.alive or w.phase ~= "ACTIVE" or w.t < Defs.Run.SafeSeconds then
		return false
	end
	amount *= Defs.Threat.damage(w.threat) * (if acid then 1 else Defs.Reactor.ContactMult)
	if (obj.shield or 0) > 0 then
		local absorbed = math.min(obj.shield, amount)
		obj.shield -= absorbed
		amount -= absorbed
		if amount <= 0 then
			obj.lastShieldT = w.t
			return true
		end
	end
	obj.hp = math.max(0, obj.hp - amount)
	obj.lastHitT = w.t
	if obj.obj == "relay" then
		w:emit(E.REACTOR, 4, math.floor(amount + 0.5), fromX, fromZ, obj.x, obj.z)
		if obj.hp <= 0 then
			obj.alive = false
			self:relayLost()
		end
		return true
	end
	obj.damageTaken += amount
	w:emit(E.REACTOR, 1, math.floor(amount + 0.5), fromX, fromZ)
	local pct = obj.hp / obj.maxHp
	for _, mark in Defs.Reactor.Warnings do
		if pct <= mark and not obj.warned[mark] then
			obj.warned[mark] = true
			w:emit(E.REACTOR, 2, math.floor(mark * 100))
			w:banner(
				`{obj.name} {math.floor(mark * 100)}%`,
				"Вернись и перехвати штурм",
				C.RED,
				3,
				"reactor"
			)
		end
	end
	-- TECH_EMERGENCY_CAP: once per operation, the hull discharges when it first drops below half.
	if pct <= 0.5 and not self.capUsed then
		for _, pl in w.playerList do
			if pl.tech.TECH_EMERGENCY_CAP then
				self.capUsed = true
				local T = Defs.Tech.TECH_EMERGENCY_CAP
				w:emit(E.REACTOR, 5, 0, obj.x, obj.z)
				w:banner(
					"АВАРИЙНЫЙ КОНДЕНСАТОР",
					"Импульс корпуса отбросил штурм",
					C.CYAN,
					2.5,
					"reactor"
				)
				for _, e in w:query(obj.x, obj.z, T.radius, {}) do
					if e.alive and not e.def.boss then
						local dx, dz = e.x - obj.x, e.z - obj.z
						local m = math.max(0.1, math.sqrt(dx * dx + dz * dz))
						if not e.def.big then
							e.x, e.z = w.nav.resolve(e.x + dx / m * T.knock, e.z + dz / m * T.knock, e.def.radius)
							e.stunUntil = math.max(e.stunUntil, w.t + 1)
						end
						w:damage(pl, e, T.damage, 1, bit32.bor(Codec.DF.BLAST, Codec.DF.ENV), obj.x, obj.z)
					end
				end
				break
			end
		end
	end
	if obj.hp <= 0 then
		obj.alive = false
		w:emit(E.REACTOR, 3)
		w:finish(false, obj.name .. " УНИЧТОЖЕН" .. (if obj.name == "СЕРДЦЕВИНА" then "А" else ""))
	end
	return true
end

-- «Барьер»: a refill tops the reactor's shield up to `amount` (no stacking across players or refills).
function Mission:shieldReactor(amount: number)
	local rc = self.reactor
	if rc and rc.alive and amount > rc.shield then
		rc.shield = amount
		self.w:emit(E.REACTOR, 6, amount, rc.x, rc.z)
	end
end

function Mission:hurtReactor(amount: number, fromX: number, fromZ: number, acid: boolean?, target): boolean
	return self:hurtObject(if target and target.obj then target.obj else self.reactor, amount, fromX, fromZ, acid)
end

-- Acid puddles that overlap the reactor (or the relay coil) eat into it.
function Mission:hazardTick(h, inShape)
	local w = self.w
	for _, obj in { self.reactor, self.relay and self.relay.coil } do
		if obj and obj.alive and inShape(h, obj.x, obj.z, obj.r) and w.t >= (h.lastHit[obj] or -99) + h.tick then
			h.lastHit[obj] = w.t
			self:hurtObject(obj, h.damage * Defs.Reactor.AcidMult, h.x, h.z, true)
		end
	end
end

-- Objective completion --------------------------------------------------------------------------------
function Mission:objectiveDone(title: string, sub: string)
	local w = self.w
	if self.state ~= "FIGHT" then
		return
	end
	self.state = "FINALE"
	self.finaleUntil = w.t + (self.op.finaleTime or 50)
	self.goal = "Переживи финальную фазу"
	w:banner(title, sub, C.GOLD, 4, "crown")
end

-- Relay (O02) -----------------------------------------------------------------------------------------
function Mission:activateRelay(index: number, carried: number)
	local w = self.w
	local cfg = self.op.relay
	local c = w.map.coils[index]
	local hp = cfg.hp * Defs.Reactor.hpScale(w.threat, #w.playerList)
	local coil = {
		obj = "relay",
		name = "ПИЛОН",
		x = c.x,
		z = c.z,
		r = 3.5,
		hp = hp,
		maxHp = hp,
		alive = true,
		lastHitT = -99,
	}
	coil.field = ringField(w, c.x, c.z, 6)
	self.relay = self.relay or { charge = 0, need = cfg.need, used = {} }
	self.relay.coil = coil
	self.relay.index = index
	self.relay.used[index] = true
	self.relay.charge = carried
	self.goal = "Заряди пилон: убивай рядом с ним"
	w:emit(E.OBJECTIVE, 1, c.x, c.z, cfg.radius, carried, cfg.need)
end

function Mission:relayLost()
	local w = self.w
	if self.relay.charge >= self.relay.need then
		return -- a charged relay stays done (D02 §5.1)
	end
	if not self.relay.used[self.relayBackup] then
		-- Backup coil takes over with 100% of the confirmed charge.
		local carried = self.relay.charge
		self:activateRelay(self.relayBackup, carried)
		w:banner(
			"ПИЛОН ПОТЕРЯН",
			`Запасной пилон активен · заряд сохранён {carried}/{self.relay.need}`,
			C.ORANGE,
			4,
			"reactor"
		)
		return
	end
	w:finish(false, "ОБА ПИЛОНА ПОТЕРЯНЫ")
end

-- Nests / nodes / acid sources (O03 / O05 / C-A01) --------------------------------------------------
local TARGET_KIND = { nest = "HIVE", node = "NODE", acid = "ACID_SOURCE" }

function Mission:spawnTargets(kind: string, sites, hp: number, flags)
	local w = self.w
	for i, s in sites do
		local e = w:spawnEnemy(TARGET_KIND[kind] or "HIVE", s.x, s.z, 1.5)
		e.objective = kind
		e.objIndex = i
		e.hp = hp * Defs.Threat.hp(w.threat) * (1 + 0.5 * (#w.playerList - 1))
		e.maxHp = e.hp
		for k, v in flags do
			e[k] = v
		end
		table.insert(self.targets, e)
		w:emit(E.OBJECTIVE, 2, s.x, s.z, i, 0, 0)
	end
end

function Mission:targetsLeft(): number
	local n = 0
	for _, e in self.targets do
		if e.alive then
			n += 1
		end
	end
	return n
end

-- Targets required to complete the objective (nests: any 2 of 3; nodes / acid: all planned).
function Mission:need(): number
	local o = self.op.objective
	if o == "nests" then
		return self.op.nests.need
	elseif o == "nodes" then
		return self.op.nodes.count
	elseif o == "acid" then
		return self.op.acid.count
	end
	return #self.targets
end

-- Called by World:kill for every death.
function Mission:onKill(e, p)
	local w = self.w
	if e.objective == "core" then
		w:finish(true, "Вражеский бур разрушен")
		return
	end
	if self.relay and self.relay.coil and self.relay.coil.alive and self.state == "FIGHT" and p then
		local c = self.relay.coil
		local r = self.op.relay.radius
		if (e.x - c.x) ^ 2 + (e.z - c.z) ^ 2 <= r * r then
			local before = self.relay.charge
			self.relay.charge = math.min(self.relay.need, before + (RELAY_CHARGE[e.kind] or 1))
			if self.relay.charge >= self.relay.need and before < self.relay.need then
				w:emit(E.OBJECTIVE, 3, c.x, c.z, 0, self.relay.charge, self.relay.need)
				self:objectiveDone(
					"ПИЛОН ЗАРЯЖЕН",
					"Периметр закрыт. Вернись к буру и удержи его!"
				)
			end
		end
	end
	if e.objective then
		self.destroyed += 1
		w:emit(E.OBJECTIVE, 4, e.x, e.z, e.objIndex or 0, self.destroyed, #self.targets)
		local need = self:need()
		local names = { nest = "ГНЕЗДО", node = "УЗЕЛ", acid = "ИСТОЧНИК" }
		if self.destroyed >= need and self.state == "FIGHT" then
			if e.objective == "nest" then
				self:objectiveDone(
					"ПРОРЫВ ОСТАНОВЛЕН",
					"Два гнезда уничтожены. Третье — по желанию. Держись!"
				)
			elseif e.objective == "node" then
				self:objectiveDone(
					"УЗЛЫ РАЗРУШЕНЫ",
					"Улей теряет питание. Удержи сердцевину!"
				)
			else
				self:objectiveDone(
					"ИСТОЧНИКИ УНИЧТОЖЕНЫ",
					"Новая кислота не появится. Удержи периметр!"
				)
			end
		elseif self.state == "FIGHT" then
			w:banner(
				names[e.objective] .. " УНИЧТОЖЕН" .. (if e.objective == "nest" then "О" else ""),
				`{self.destroyed}/{need}`,
				C.LIME,
				2.5,
				"hive"
			)
		elseif e.objective == "nest" and self.destroyed == #self.targets then
			w:banner("ВСЕ ГНЁЗДА", "3/3 — бонус Утиля", C.LIME, 2.5, "hive")
		end
	end
end

-- Acid source (C-A01): seeds a readable puddle near the defended yard every few seconds.
function Mission:acidTick(e)
	local w = self.w
	if w.t < (e.acidT or 0) then
		return
	end
	e.acidT = w.t + self.op.acid.every
	local S = Defs.Spitter
	local tx, tz
	local p = w:nearestPlayer(e.x, e.z)
	if p and w.rng:chance(0.5) then
		tx, tz = p.x + w.rng:range(-6, 6), p.z + w.rng:range(-6, 6)
	else
		local a = w.rng:range(0, math.pi * 2)
		tx, tz = math.cos(a) * w.rng:range(12, 40), math.sin(a) * w.rng:range(12, 40)
	end
	tx, tz = w.nav.resolve(tx, tz, 1)
	w:addHazard({
		source = "acid",
		shape = SH.CIRCLE,
		x = tx,
		z = tz,
		dx = 0,
		dz = 1,
		a = S.Radius,
		b = 0,
		activeFrom = w.t + S.Telegraph * 1.3,
		untilT = w.t + S.Telegraph * 1.3 + S.Active,
		damage = 7,
		tick = S.Tick,
	})
	w:emit(E.SPIT, e.x, e.z, tx, tz, S.Telegraph)
	w:emit(E.TELE, SH.CIRCLE, tx, tz, 0, 1, S.Radius, 0, S.Telegraph * 1.3, C.LIME, S.Active)
end

-- Beats ---------------------------------------------------------------------------------------------
local function pickDir(w, dirs)
	return dirs[w.rng:int(1, #dirs)]
end

function Mission:assault(beat)
	local w = self.w
	local toRelay = beat.target == "relay"
	local obj = if toRelay then (self.relay and self.relay.coil) else self.reactor
	if not obj or not obj.alive or (toRelay and self.state ~= "FIGHT") then
		return
	end
	local _, ph = w:currentPhaseDef()
	local key = beat.dir or pickDir(w, ph.dirs)
	key = w.dirMap and w.dirMap[key] or key
	local s = w.map.spawns[key]
	local n = math.max(1, math.floor((beat.count or 8) * (1 + 0.35 * (#w.playerList - 1))))
	local spawned = 0
	for i = 1, n do
		local kind = beat.kind or "EN_RUNNER"
		-- Mixed groups: a specialist strike still brings runners as escort.
		if beat.kind and beat.kind ~= "EN_RUNNER" and i > math.ceil(n / 2) then
			kind = "EN_RUNNER"
		end
		local e = w:spawnAtPoint(kind, s.x, s.z, 12, 1.2 + i * 0.08)
		if e then
			e.role = if toRelay then "Y" else "R"
			spawned += 1
		end
	end
	if spawned == 0 then
		return
	end
	self.assaults += 1
	local dist = math.sqrt((s.x - obj.x) ^ 2 + (s.z - obj.z) ^ 2)
	local eta = dist / Defs.Enemies.EN_RUNNER.speed
	w:emit(E.ASSAULT, s.x, s.z, spawned, math.floor(eta + 0.5), obj.x, obj.z)
	if toRelay then
		w:banner(
			"АТАКА НА ПИЛОН",
			`Прыгуны идут с направления {DIR_NAME[key] or key} — защити заряд`,
			C.ORANGE,
			3,
			"reactor"
		)
	else
		w:banner(
			"ШТУРМ: " .. obj.name,
			`Группа идёт с направления {DIR_NAME[key] or key} — перехвати`,
			C.ORANGE,
			3,
			"reactor"
		)
	end
end

function Mission:ring(beat)
	local w = self.w
	local p = w.playerList[1]
	if not p then
		return
	end
	local n = math.floor((beat.count or 24) * (1 + 0.4 * (#w.playerList - 1)))
	for i = 1, n do
		local a = i / n * math.pi * 2
		local rr = 11 + (i % 3) * 2 -- inside the emergency strike (14 + body radius)
		local x, z = p.x + math.cos(a) * rr, p.z + math.sin(a) * rr
		if w.nav.free(x, z, 1.6) then
			w:spawnEnemy("EN_RUNNER", x, z, 1.1)
		end
	end
	w:banner("ОКРУЖЕНИЕ", "Рой сомкнулся — пробей кольцо", C.RED, 3, "threat")
end

function Mission:elite()
	local w = self.w
	local e = w:spawnAtBreach("ELITE_CARRIER", w.map.spawnOrder, 1.8)
	if not e then
		return
	end
	e.objective = nil
	e.carrier = true
	e.hp *= self.op.eliteHpMult or 1
	e.maxHp = e.hp
	self.eliteSpawned = true
	self.goal = self.op.eliteGoal or ("Убей " .. (self.op.eliteName or "элиту"))
	w:banner(
		self.op.eliteName or "ЭЛИТА",
		"Вожак стаи. Убей его!",
		C.GOLD,
		4,
		"@" .. e.def.index
	)
end

function Mission:onEliteKilled(e)
	local w = self.w
	if self.op.objective ~= "carrier" or self.eliteKilled then
		return
	end
	self.eliteKilled = true
	-- Permanent component: granted for the kill itself, even if the run is lost afterwards (GDD §5).
	table.insert(self.components, "CMP_STORM_CORE")
	w:emit(E.COMPONENT, e.x, e.z, "CMP_STORM_CORE")
	w:banner(
		"АЛЬФА ПОВЕРЖЕНА",
		"Стая в ярости. Переживи последнюю волну!",
		C.GOLD,
		4,
		"core"
	)
	self.state = "FINALE"
	self.finaleUntil = w.t + (self.op.finaleTime or 50)
	self.goal = "Переживи последнюю волну"
end

function Mission:guard(beat)
	local w = self.w
	local nest = self.targets[((beat.index or 1) - 1 + self.guardShift) % math.max(1, #self.targets) + 1]
	if not nest or not nest.alive then
		-- Escort the first nest still standing.
		for _, e in self.targets do
			if e.alive then
				nest = e
				break
			end
		end
	end
	if not nest then
		return
	end
	local b = w:spawnAtPoint("EN_BULWARK", nest.x, nest.z, 10, 1.4)
	if b then
		b.guardX, b.guardZ = nest.x, nest.z
	end
end

function Mission:runBeat(beat)
	local w = self.w
	local t = beat.type
	if t == "assault" then
		self:assault(beat)
	elseif t == "ring" then
		self:ring(beat)
		if self.op.s01Event then
			-- Teach S01 once the ring has actually closed in (see update), not while it is forming.
			self.s01At = w.t + 0.1 -- the ring is emerging around the player: pause before a dash can leave it
		end
	elseif t == "elite" then
		if self.op.objective == "carrier" then
			self:elite()
		else
			w:legacyElite()
		end
	elseif t == "relay" then
		self:activateRelay(self.relayPrimary, 0)
		local c = w.map.coils[self.relayPrimary]
		w:emit(E.ASSAULT, c.x, c.z, 0, 0, 0, 0)
		w:banner(
			"ПОЮЩИЙ ПИЛОН",
			"Убивай врагов в его зоне, чтобы зарядить",
			C.CYAN,
			4,
			"reactor"
		)
	elseif t == "nests" then
		self:spawnTargets("nest", w.map.hiveSites, self.op.nests.hp, {})
		self.goal = "Уничтожь 2 из 3 гнёзд"
		w:banner(
			"ГНЁЗДА РАСКРЫТЫ",
			"Уничтожь любые два из трёх. Третье — бонус",
			C.LIME,
			4,
			"@6"
		)
	elseif t == "guard" then
		self:guard(beat)
	elseif t == "nodes" then
		local i = beat.index or 1
		self:spawnTargets("node", { w.map.hiveSites[i] }, self.op.nodes.hp, { noSpawn = true })
		self.goal = "Разрушь питающие узлы"
		w:banner(
			if i == 1 then "ПИТАЮЩИЙ УЗЕЛ" else "ВТОРОЙ УЗЕЛ",
			"Уязвим для любого оружия. Взрывуны помогают",
			C.VIOLET,
			4,
			"@6"
		)
	elseif t == "acid" then
		local i = beat.index or 1
		self:spawnTargets("acid", { w.map.hiveSites[i] }, self.op.acid.hp, { noSpawn = true, acidSource = true })
		self.goal = "Уничтожь кислотные источники"
		w:banner(
			if i == 1 then "КИСЛОТНЫЙ ИСТОЧНИК" else "ВТОРОЙ ИСТОЧНИК",
			"Стреляй по источнику — он травит воронку",
			C.LIME,
			4,
			"@6"
		)
	elseif t == "outpost" then
		Outpost.deployHostile(w, self.op.target)
	elseif t == "brood" then
		Outpost.broodWave(w, self.op.target)
	elseif t == "hive" then
		w:startHive()
	elseif t == "boss" then
		w:spawnBoss()
	elseif t == "enrage" then
		w:enrageBoss()
	elseif t == "banner" then
		w:banner(
			beat.title or "",
			beat.sub or "",
			C.CYAN,
			3.5,
			if beat.kind then "@" .. Defs.Enemies[beat.kind].index else ""
		)
	end
end

-- Update --------------------------------------------------------------------------------------------
function Mission:update(dt: number)
	local w = self.w
	local beats = self.op.beats
	-- Scripted beats keep coming during the final phase only if they belong to the reactor defence.
	while self.beatIndex <= #beats and w.t >= beats[self.beatIndex].at do
		local beat = beats[self.beatIndex]
		self.beatIndex += 1
		if self.state == "FIGHT" or beat.type == "assault" then
			self:runBeat(beat)
		end
		if w.phase ~= "ACTIVE" then
			return
		end
	end
	if self.s01At and w.t >= self.s01At then
		-- Trigger when >= 10 enemies are within 16 studs of a player who still lacks S01, or after a
		-- 3 s fallback (teach on a smaller group rather than wait for an impossible ring, S01 §3).
		local crowded = false
		for _, p in w.playerList do
			if p.alive and not p.s01 then
				local n = 0
				for _, e in w:query(p.x, p.z, 16, {}) do
					if e.alive then
						n += 1
					end
				end
				crowded = crowded or n >= 10
			end
		end
		if crowded or w.t >= self.s01At + 3 then
			self.s01At = nil
			w:s01Event()
		end
	end
	for _, e in self.targets do
		if e.alive and e.acidSource then
			self:acidTick(e)
		end
	end
	-- objectiveDeadline (D02 §3.3): only while the objective is still open.
	local deadline = self.op.deadline
	if self.state == "FIGHT" and deadline and self.op.objective ~= "boss" and w.t >= deadline then
		w:finish(false, "ЦЕЛЬ НЕ ВЫПОЛНЕНА ВОВРЕМЯ")
		return
	end
	if self.state == "FINALE" and w.t >= self.finaleUntil then
		self.state = "DONE"
		w:finish(true, if self.op.mode == "siege" then "Бур выстоял" else "Рой отброшен")
	end
end

-- The phase the director should use right now (finale overrides the timeline).
function Mission:phaseOverride()
	if self.state == "FINALE" then
		return self.op.finale
	end
	return nil
end

function Mission:goalText(): string
	local g = self.goal
	if self.state == "FIGHT" then
		if self.relay and self.relay.coil then
			g = `Заряди пилон {self.relay.charge}/{self.relay.need}`
		elseif #self.targets > 0 then
			g = self.goal .. ` · {self.destroyed}/{self:need()}`
		end
	end
	return g
end

function Mission:publicState()
	local rc = self.reactor
	local w = self.w
	local deadlineLeft = nil
	if self.state == "FIGHT" and self.op.deadline and self.op.objective ~= "boss" then
		deadlineLeft = math.max(0, math.ceil(self.op.deadline - w.t))
	end
	local relay = nil
	if self.relay and self.relay.coil then
		local c = self.relay.coil
		relay = {
			x = c.x,
			z = c.z,
			hp = math.ceil(c.hp),
			max = math.ceil(c.maxHp),
			charge = self.relay.charge,
			need = self.relay.need,
			radius = self.op.relay.radius,
			alive = c.alive,
			hitT = c.lastHitT,
		}
	end
	local marks = nil
	if #self.targets > 0 then
		marks = {}
		for _, e in self.targets do
			if e.alive then
				table.insert(marks, { e.x, e.z, e.objective, math.floor(e.hp / e.maxHp * 100) })
			end
		end
	end
	return {
		goal = self:goalText(),
		state = self.state,
		finaleLeft = if self.finaleUntil then math.max(0, math.ceil(self.finaleUntil - w.t)) else nil,
		deadlineLeft = deadlineLeft,
		reactor = if rc
			then {
				hp = math.ceil(rc.hp),
				max = math.ceil(rc.maxHp),
				hitT = rc.lastHitT,
				name = rc.name,
				shield = math.ceil(rc.shield),
			}
			else nil,
		relay = relay,
		marks = marks,
	}
end

return Mission
