--!nonstrict
-- Operation objectives: the reactor and the mission state machine (pure Luau, driven by World).
-- The reactor (or the depths' energy heart) is a defendable object with HP. Strike groups are announced
-- with a direction before they can reach it; it is only hurt by contact or acid next to it (DD-004).
-- Objective types (D02): carrier (O01), relay (O02), nests (O03), boss (O04/O06), nodes (O05), acid (C-A01).
-- Non-boss operations: objective done -> separate final pressure phase -> WIN (D02 §3); boss operations
-- win on the boss kill (World:kill).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
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
	if op.reactor then
		local hp = op.reactor.hp * Defs.Reactor.hpScale(w.threat, #w.playerList)
		local radius = op.reactor.radius or Defs.Reactor.Radius
		self.reactor = {
			obj = "reactor",
			name = op.reactor.name or "РЕАКТОР",
			x = 0,
			z = 0,
			r = radius,
			hp = hp,
			maxHp = hp,
			alive = true,
			warned = {},
			lastHitT = -99,
			damageTaken = 0,
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
			w:banner(`{obj.name} {math.floor(mark * 100)}%`, "Вернись и перехвати штурм", C.RED, 3, "reactor")
		end
	end
	if obj.hp <= 0 then
		obj.alive = false
		w:emit(E.REACTOR, 3)
		w:finish(false, obj.name .. " УНИЧТОЖЕН" .. (if obj.name == "СЕРДЦЕВИНА" then "А" else ""))
	end
	return true
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
	local coil = { obj = "relay", name = "КАТУШКА", x = c.x, z = c.z, r = 3.5, hp = hp, maxHp = hp, alive = true, lastHitT = -99 }
	coil.field = ringField(w, c.x, c.z, 6)
	self.relay = self.relay or { charge = 0, need = cfg.need, used = {} }
	self.relay.coil = coil
	self.relay.index = index
	self.relay.used[index] = true
	self.relay.charge = carried
	self.goal = "Заряди катушку убийствами рядом"
	w:emit(E.OBJECTIVE, 1, c.x, c.z, cfg.radius, carried, cfg.need)
end

function Mission:relayLost()
	local w = self.w
	local cfg = self.op.relay
	if self.relay.charge >= self.relay.need then
		return -- a charged relay stays done (D02 §5.1)
	end
	if not self.relay.used[cfg.backup] then
		-- Backup coil takes over with 100% of the confirmed charge.
		local carried = self.relay.charge
		self:activateRelay(cfg.backup, carried)
		w:banner("КАТУШКА ПОТЕРЯНА", `Запасная катушка активна · заряд сохранён {carried}/{self.relay.need}`, C.ORANGE, 4, "reactor")
		return
	end
	w:finish(false, "ОБЕ КАТУШКИ ПОТЕРЯНЫ")
end

-- Nests / nodes / acid sources (O03 / O05 / C-A01) --------------------------------------------------
function Mission:spawnTargets(kind: string, sites, hp: number, flags)
	local w = self.w
	for i, s in sites do
		local e = w:spawnEnemy("HIVE", s.x, s.z, 1.5)
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

-- Called by World:kill for every death.
function Mission:onKill(e, p)
	local w = self.w
	if self.relay and self.relay.coil and self.relay.coil.alive and self.state == "FIGHT" and p then
		local c = self.relay.coil
		local r = self.op.relay.radius
		if (e.x - c.x) ^ 2 + (e.z - c.z) ^ 2 <= r * r then
			local before = self.relay.charge
			self.relay.charge = math.min(self.relay.need, before + (RELAY_CHARGE[e.kind] or 1))
			if self.relay.charge >= self.relay.need and before < self.relay.need then
				w:emit(E.OBJECTIVE, 3, c.x, c.z, 0, self.relay.charge, self.relay.need)
				self:objectiveDone("КАТУШКА ЗАРЯЖЕНА", "Периметр закрыт. Вернись к реактору и удержи его!")
			end
		end
	end
	if e.objective then
		self.destroyed += 1
		w:emit(E.OBJECTIVE, 4, e.x, e.z, e.objIndex or 0, self.destroyed, #self.targets)
		local need = if e.objective == "nest" then self.op.nests.need else #self.targets
		local names = { nest = "ГНЕЗДО", node = "УЗЕЛ", acid = "ИСТОЧНИК" }
		if self.destroyed >= need and self.state == "FIGHT" then
			if e.objective == "nest" then
				self:objectiveDone("ПРОРЫВ ОСТАНОВЛЕН", "Два гнезда уничтожены. Третье — по желанию. Держись!")
			elseif e.objective == "node" then
				self:objectiveDone("УЗЛЫ РАЗРУШЕНЫ", "Улей теряет питание. Удержи сердцевину!")
			else
				self:objectiveDone("ИСТОЧНИКИ УНИЧТОЖЕНЫ", "Новая кислота не появится. Удержи периметр!")
			end
		elseif self.state == "FIGHT" then
			w:banner(names[e.objective] .. " УНИЧТОЖЕН" .. (if e.objective == "nest" then "О" else ""), `{self.destroyed}/{need}`, C.LIME, 2.5, "hive")
		elseif e.objective == "nest" and self.destroyed == #self.targets then
			w:banner("ВСЕ ГНЁЗДА", "3/3 — бонус Ксенита", C.LIME, 2.5, "hive")
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
		w:banner("АТАКА НА КАТУШКУ", `Прыгуны идут с направления {DIR_NAME[key] or key} — защити заряд`, C.ORANGE, 3, "reactor")
	else
		w:banner("ШТУРМ: " .. obj.name, `Группа идёт с направления {DIR_NAME[key] or key} — перехвати`, C.ORANGE, 3, "reactor")
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
		local rr = 24 + (i % 3) * 3
		local x, z = p.x + math.cos(a) * rr, p.z + math.sin(a) * rr
		if w.nav.free(x, z, 1.6) then
			w:spawnEnemy("EN_RUNNER", x, z, 1.1)
		end
	end
	w:banner("ОКРУЖЕНИЕ", "Рой сомкнулся — пробей кольцо", C.RED, 3, "threat")
end

function Mission:elite()
	local w = self.w
	local e = w:spawnAtBreach("ELITE_BULWARK", w.map.spawnOrder, 1.8)
	if not e then
		return
	end
	e.objective = nil
	e.carrier = true
	self.eliteSpawned = true
	self.goal = "Убей " .. (self.op.eliteName or "элиту")
	w:banner(self.op.eliteName or "ЭЛИТА", "Убей его — он несёт Ядро Бури", C.GOLD, 4, "@" .. e.def.index)
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
	w:banner("ЯДРО БУРИ ПОЛУЧЕНО", "Постоянный компонент сохранён. Переживи финальный рой!", C.GOLD, 4, "core")
	self.state = "FINALE"
	self.finaleUntil = w.t + (self.op.finaleTime or 50)
	self.goal = "Переживи финальный рой"
end

function Mission:guard(beat)
	local w = self.w
	local nest = self.targets[beat.index or 1]
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
			-- Teach S01 when the ring has closed in (~10–15 studs), not while it is still forming.
			self.s01At = w.t + 2.0
		end
	elseif t == "elite" then
		if self.op.objective == "carrier" then
			self:elite()
		else
			w:legacyElite()
		end
	elseif t == "relay" then
		self:activateRelay(self.op.relay.primary, 0)
		local c = w.map.coils[self.op.relay.primary]
		w:emit(E.ASSAULT, c.x, c.z, 0, 0, 0, 0)
		w:banner("ВНЕШНЯЯ КАТУШКА", "Убивай врагов в её зоне, чтобы зарядить ретранслятор", C.CYAN, 4, "reactor")
	elseif t == "nests" then
		self:spawnTargets("nest", w.map.hiveSites, self.op.nests.hp, {})
		self.goal = "Уничтожь 2 из 3 гнёзд"
		w:banner("ГНЁЗДА РАСКРЫТЫ", "Уничтожь любые два из трёх. Третье — бонус", C.LIME, 4, "@6")
	elseif t == "guard" then
		self:guard(beat)
	elseif t == "nodes" then
		local sites = { w.map.hiveSites[1], w.map.hiveSites[2] }
		self:spawnTargets("node", sites, self.op.nodes.hp, { noSpawn = true })
		self.goal = "Разрушь 2 питающих узла"
		w:banner("ПИТАЮЩИЕ УЗЛЫ", "Оба узла уязвимы для любого оружия. Взрывуны помогают", C.VIOLET, 4, "@6")
	elseif t == "acid" then
		local sites = { w.map.hiveSites[1], w.map.hiveSites[2] }
		self:spawnTargets("acid", sites, self.op.acid.hp, { noSpawn = true, acidSource = true })
		self.goal = "Уничтожь 2 кислотных источника"
		w:banner("КИСЛОТНЫЕ ИСТОЧНИКИ", "Стреляй по источникам — они травят двор", C.LIME, 4, "@6")
	elseif t == "hive" then
		w:startHive()
	elseif t == "boss" then
		w:spawnBoss()
	elseif t == "enrage" then
		w:enrageBoss()
	elseif t == "banner" then
		w:banner(beat.title or "", beat.sub or "", C.CYAN, 3.5, if beat.kind then "@" .. Defs.Enemies[beat.kind].index else "")
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
		self.s01At = nil
		w:s01Event()
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
		w:finish(true, "ЗОНА УДЕРЖАНА")
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
			g = `Заряди катушку {self.relay.charge}/{self.relay.need}`
		elseif #self.targets > 0 then
			local need = if self.op.objective == "nest" or self.op.objective == "nests" then self.op.nests.need else #self.targets
			g = self.goal .. ` · {self.destroyed}/{need}`
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
		relay = { x = c.x, z = c.z, hp = math.ceil(c.hp), max = math.ceil(c.maxHp), charge = self.relay.charge, need = self.relay.need, radius = self.op.relay.radius, alive = c.alive, hitT = c.lastHitT }
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
		reactor = if rc then { hp = math.ceil(rc.hp), max = math.ceil(rc.maxHp), hitT = rc.lastHitT, name = rc.name } else nil,
		relay = relay,
		marks = marks,
	}
end

return Mission
