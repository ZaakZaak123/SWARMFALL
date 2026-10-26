--!nonstrict
-- The authoritative SWARMFALL run. Pure Luau (no Instances): the server glue feeds player positions and
-- validated intents in, and drains state + events out. tests/sim_run.luau drives this headlessly.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Maps = require(Shared:WaitForChild("Maps"))
local Ops = require(Shared:WaitForChild("Ops"))
local Codec = require(Shared:WaitForChild("Codec"))
local Nav = require(script.Parent.Nav)
local Rng = require(script.Parent.Rng)
local Combat = require(script.Parent.Combat)
local AI = require(script.Parent.AI)
local Mission = require(script.Parent.Mission)
local Outpost = require(script.Parent.Outpost)
local Modules = require(Shared:WaitForChild("Modules"))

local E, C = Codec.E, Codec.C
local ST = Codec.State
local STEP = Defs.Run.SimStep
local GRID = 8

local World = {}
World.__index = World

local function perk(info, id: string): number
	return math.clamp(info.perks and info.perks[id] or 0, 0, Defs.Perks[id].max)
end

local function newPlayer(map, info, index: number, count: number)
	local weapon = Defs.Weapons[info.weapon] or Defs.Weapons.W_ARC_RIFLE
	local angle = (index - 1) / math.max(1, count) * math.pi * 2
	local maxHp = Defs.Player.Health + 8 * perk(info, "PK_VITALITY")
	local p = {
		id = info.id,
		name = info.name or ("P" .. index),
		x = map.playerStart.x + math.sin(angle) * (if count > 1 then 6 else 0),
		z = map.playerStart.z + math.cos(angle) * (if count > 1 then 6 else 0),
		alive = true,
		hp = maxHp,
		maxHp = maxHp,
		magnet = Defs.Player.Magnet * (1 + 0.2 * perk(info, "PK_MAGNET")),
		dashMult = 1 - 0.08 * perk(info, "PK_DASH"),
		rerolls = perk(info, "PK_REROLL"),
		banishes = perk(info, "PK_BANISH"),
		banished = {},
		cards = if perk(info, "PK_INSIGHT") > 0 then 4 else 3,
		shield = 0,
		weaponDef = weapon,
		-- A crafted, equipped permanent form is active from the first shot (no in-run recipe).
		evolved = if info.form
				and Defs.Evolutions[info.form]
				and Defs.Evolutions[info.form].weapon == weapon.id
			then info.form
			else nil,
		hasCore = false,
		canEvolve = false,
		ammo = weapon.magazine,
		reloadT = 0,
		reloadDur = weapon.reload,
		reloadEmpty = false,
		spread = weapon.spreadMin or weapon.spread,
		heat = 0,
		overheatT = 0,
		cool = 0,
		aimX = 0,
		aimZ = 1,
		firing = false,
		dashReady = 0,
		dashUntil = -1,
		dashX = 0,
		dashZ = 1,
		dashHit = {},
		iframeUntil = 0,
		graceUntil = 0,
		od = 0, -- legacy overdrive (retired by S01, DD-006)
		odUntil = -1,
		-- S01 Gravihammer: unlocked forever after the first own cast (O01 event); locked profiles
		-- get it at the O01 encirclement. Tests/legacy callers default to unlocked.
		s01 = info.s01 ~= false,
		s01Ready = 0,
		s01Cd = Defs.S01.Cooldown
			* (1 - Defs.S01.PerkCut * perk(info, "PK_OVERDRIVE"))
			* (if info.s01Spec and info.s01Spec.branch == "A" and info.s01Spec.tier >= 3 then 0.85 else 1),
		s01Spec = info.s01Spec, -- { branch = "A"|"B"|"C", tier = 1..3 } or nil
		hammerFollow = nil,
		hammerAt = nil,
		hammerEmergency = false,
		s01Stats = { casts = 0, hits = 0, kills = 0, crowds = 0, best = 0 },
		tech = info.tech or {}, -- owned starter technologies (Defs.Tech)
		-- Equipped modules (validated by the server before the run): virtual card ranks + stat tweaks.
		modRanks = if info.loadout then Modules.ranksFor(info.loadout.core, info.loadout.adapter) else nil,
		modMods = nil,
		loadout = info.loadout,
		weaponKills = 0, -- personal lethal kills credited to this run's weapon (mastery M1–M20)
		feats = { arcKills = 0, burnKills = 0, heavyKills = 0, line4 = 0 }, -- M20 feat counters
		lineShots = 0, -- railgun trial shots (>= 2 normal enemies in one line)
		species = {}, -- personal confirmed kills per species (research)
		ranks = {},
		slots = 0,
		offer = nil,
		offerSeq = 0,
		pending = 0,
		offersMade = 0,
		kills = 0,
		damage = 0,
		bigDamage = 0, -- to elites and bosses (squad awards, DD-054)
		guardKills = 0, -- kills close to the drill (squad awards)
		chainCount = 0,
		killCount = 0,
		shieldKills = 0,
		pyreReady = 0,
		voidPulseT = 0,
		procBudget = 24,
		bestCombo = 0,
		combo = 0,
		comboT = 0,
		beamEndX = 0,
		beamEndZ = 0,
		beamFxT = 0,
		hitsTaken = 0,
		causeKills = {}, -- kills per cause (Codec.Cause), for results and the style tests
		synergies = {}, -- synergies already announced this run
		novaReady = 0,
		newbie = info.s01 == false, -- first-ever O01 (soft tutorial draft, 02.4 §4)
		firstHunt = info.firstHunt == true, -- has never won O01: the first card is the guided «Расщепление» (DD-051)
		seenMulti = false,
	}
	if info.loadout then
		local mods = {}
		for _, id in { info.loadout.core, info.loadout.adapter } do
			local m = Modules.get(id)
			if m and m.weapon == weapon.id then
				for k, v in m.mods do
					if k:sub(-4) == "Mult" then
						mods[k] = (mods[k] or 1) * v
					else
						mods[k] = (mods[k] or 0) + v
					end
				end
			end
		end
		p.modMods = mods
	end
	-- An equipped M20 form works through the same path (its ranks and tweaks stack under the cap).
	local form = p.evolved and Defs.Evolutions[p.evolved]
	if form and form.m20 then
		p.modRanks = p.modRanks or {}
		for k, v in form.ranks do
			p.modRanks[k] = (p.modRanks[k] or 0) + v
		end
		p.modMods = p.modMods or {}
		for k, v in form.mods do
			if k:sub(-4) == "Mult" then
				p.modMods[k] = (p.modMods[k] or 1) * v
			else
				p.modMods[k] = (p.modMods[k] or 0) + v
			end
		end
	end
	Combat.recompute(p)
	return p
end

export type Options = {
	seed: number?,
	op: string?, -- operation id (Ops); defaults from map for legacy callers
	map: string?,
	threat: number?,
	players: { { id: number, name: string?, weapon: string?, perks: { [string]: number }? } },
	replay: boolean?, -- a repeat of an operation already won: 1–2 whitelisted changes (D02 §11.2)
	opDef: any?, -- generated operation (siege / raid)
	structures: any?, -- siege: the host's outpost slots
	anomaly: any?, -- Meta anomaly of the day
}

function World.new(opts: Options)
	local seed = opts.seed or 1337
	local self = setmetatable({}, World)
	self.seed = seed
	self.rng = Rng.new(seed)
	local opId = opts.op
	if not opId then
		opId = if opts.map == "MAP_HIVE_DEPTHS" then "O07" else "O05"
	end
	self.op = opts.opDef or Ops.get(opId)
	self.anomaly = opts.anomaly
	self.structures = Outpost.allied(opts.structures)
	self.shells = {}
	self.core = nil
	self.acidRainT = 20
	self.map = Maps.get(self.op.map)
	self.nav = Nav.new(self.map)
	self.threat = math.clamp(math.floor(opts.threat or 1), 1, Defs.Threat.Max)
	self.phase = "COUNTDOWN"
	self.countdown = Defs.Run.Countdown
	self.t = 0
	self.acc = 0
	self.paused = nil -- "CHOOSE" | "EVOLVE"
	self.pauseClock = 0
	self.pauseUntil = 0
	self.players = {}
	self.playerList = {}
	for i, info in opts.players do
		local p = newPlayer(self.map, info, i, #opts.players)
		self.players[p.id] = p
		table.insert(self.playerList, p)
	end
	self.solo = #self.playerList <= 1
	self.enemies = {}
	self.enemyById = {}
	self.nextEnemyId = 0
	self.grid = {}
	self.gridPool = {}
	self.field = self.nav.newField()
	self.fieldT = 0
	self.orbs = {}
	self.orbCount = 0
	self.nextOrbId = 0
	self.hazards = {}
	self.events = {}
	self.level = 1
	self.xp = 0
	self.xpNeed = self:xpFor(1)
	self.phaseIndex = 0
	self.phaseLabel = "ВЫХОД"
	self.spawnAcc = 0
	self.elitesDone = {}
	self.hive = { state = "idle", remaining = 0, total = 0 }
	self.boss = nil
	self.enraged = false
	self.coils = {}
	for i = 1, #self.map.coils do
		self.coils[i] = Defs.Coil.FirstReady
	end
	self.result = nil
	self.stats = { spawned = 0, killed = 0, peak = 0, maxTickMs = 0 }
	self.queryBuf = {}
	self.hitBuf = {}
	self.dead = {}
	self.teamKills = 0
	self.teamSpecies = {} -- species -> kills by anyone (turrets included): the squad's research
	self.replay = opts.replay == true
	-- Mirrored approach on repeats: the heavier side of the swarm swaps east/west.
	self.dirMap = nil
	if self.replay and self.rng:chance(0.5) then
		self.dirMap = { E = "W", W = "E", NE = "NW", NW = "NE", SE = "SW", SW = "SE" }
	end
	self.mission = Mission.new(self, self.op)
	return self
end

-- Events --------------------------------------------------------------------------------------------
-- Quantize a coordinate for the wire (0.1 stud); nil stays nil.
local function q(v: number?): number?
	return if v then math.floor(v * 10 + 0.5) / 10 else nil
end

function World:emit(...)
	table.insert(self.events, { ... })
end

function World:drainEvents()
	local ev = self.events
	self.events = {}
	return ev
end

function World:banner(text: string, sub: string, color: number, duration: number?, visual: string?)
	self:emit(E.BANNER, text, sub, color, duration or 3, visual or "")
end

-- Players -------------------------------------------------------------------------------------------
function World:alivePlayers()
	local n = 0
	for _, p in self.playerList do
		if p.alive then
			n += 1
		end
	end
	return n
end

function World:nearestPlayer(x: number, z: number)
	local best, bd = nil, math.huge
	for _, p in self.playerList do
		if p.alive then
			local dx, dz = p.x - x, p.z - z
			local d = dx * dx + dz * dz
			if d < bd then
				best, bd = p, d
			end
		end
	end
	return best, math.sqrt(bd)
end

function World:setPlayerPosition(id: number, x: number, z: number)
	local p = self.players[id]
	if p and p.alive then
		local nx, nz = self.nav.resolve(x, z, 0.5)
		if (nx - p.x) ^ 2 + (nz - p.z) ^ 2 > 0.04 and self.phase == "COUNTDOWN" and self.countdown <= 0 then
			self.gotInput = true
		end
		p.x, p.z = nx, nz
	end
end

function World:setAim(id: number, dx: number, dz: number, firing: boolean)
	local p = self.players[id]
	if not p then
		return
	end
	local m = math.sqrt(dx * dx + dz * dz)
	if m > 1e-3 then
		p.aimX, p.aimZ = dx / m, dz / m
	end
	p.firing = firing == true
	if p.firing then
		self.gotInput = true
	end
end

function World:reload(id: number)
	local p = self.players[id]
	if p and p.alive and self.phase == "ACTIVE" then
		Combat.startReload(self, p)
	end
end

function World:dash(id: number, dx: number, dz: number): boolean
	local p = self.players[id]
	if not p or not p.alive or self.phase ~= "ACTIVE" or self.paused or self.t < p.dashReady then
		return false
	end
	local m = math.sqrt(dx * dx + dz * dz)
	if m < 1e-3 then
		dx, dz, m = p.aimX, p.aimZ, 1
	end
	local rank = Combat.rank(p, "UPG_DASH_SHOCK")
	p.dashReady = self.t
		+ Defs.Player.DashCooldown * p.dashMult
		- (if rank > 0 then Defs.rankValue(rank, Defs.UpgradeValues.UPG_DASH_SHOCK.cooldown) else 0)
	p.dashUntil = self.t + Defs.Player.DashTime
	p.iframeUntil = math.max(p.iframeUntil, self.t + Defs.Player.DashIFrames)
	p.dashX, p.dashZ = dx / m, dz / m
	table.clear(p.dashHit)
	self:emit(E.DASH, p.id, p.x, p.z, p.dashX, p.dashZ)
	return true
end

-- S01 Gravihammer ----------------------------------------------------------------------------------
function World:gravihammer(id: number): boolean
	local p = self.players[id]
	if not p or not p.alive or self.phase ~= "ACTIVE" or not p.s01 or p.hammerAt then
		return false
	end
	local tutorial = self.paused == "S01" and self.s01Tutee == id
	if self.paused and not tutorial then
		return false
	end
	if not tutorial and self.t < p.s01Ready then
		return false
	end
	if tutorial then
		-- The world resumes exactly as the player's own strike begins (GDD §5, S01 §3).
		self.paused = nil
		self.s01Tutee = nil
		p.hammerEmergency = true
	end
	p.hammerAt = self.t + Defs.S01.Windup
	p.iframeUntil = math.max(p.iframeUntil, self.t + Defs.S01.IFrames)
	p.s01Ready = self.t + p.s01Cd
	p.s01Stats.casts += 1
	local radius = if p.hammerEmergency then Defs.S01.Emergency.Radius else Defs.S01.Radius
	self:emit(E.HAMMER, p.id, p.x, p.z, radius, 1, if p.hammerEmergency then 1 else 0, 0)
	return true
end

function World:hammerImpact(p)
	local S = Defs.S01
	local emergency = p.hammerEmergency
	p.hammerAt = nil
	p.hammerEmergency = false
	local radius = if emergency then S.Emergency.Radius else S.Radius
	local reach = if emergency then S.Emergency.Outer else radius
	local cap = if emergency then S.Emergency.Targets else S.Targets
	local dmg = if emergency then S.Emergency.Damage else S.Damage
	local knock = if emergency then S.Emergency.Knock else S.Knock
	local stun = S.Stun
	-- Specialization (only on the portable strike, not the one-time emergency overload).
	local spec = if emergency then nil else p.s01Spec
	local br, tier = spec and spec.branch, spec and spec.tier or 0
	if br == "A" then
		radius *= 1.15
		reach = radius
		if tier >= 3 then
			dmg *= 1.3
		end
	elseif br == "B" then
		knock *= 1.4
		stun += 0.5
	elseif br == "C" and tier >= 2 then
		knock = -knock -- pull toward the player
	end
	local list = self:query(p.x, p.z, reach + 4, {})
	local px, pz = p.x, p.z
	table.sort(list, function(a, b)
		return (a.x - px) ^ 2 + (a.z - pz) ^ 2 < (b.x - px) ^ 2 + (b.z - pz) ^ 2
	end)
	local hits = 0
	for _, e in list do
		if not e.alive or e.def.static then
			continue
		end
		local dx, dz = e.x - px, e.z - pz
		local d = math.sqrt(dx * dx + dz * dz)
		local edge = d - e.def.radius
		if edge > reach then
			continue
		end
		if d < 1e-3 then
			dx, dz, d = 0, 1, 1
		end
		local inner = edge <= radius
		if inner and hits >= cap then
			continue
		end
		local big = e.def.big
		local push = if big then S.BigKnock elseif inner then knock else knock * 0.6
		if push < 0 then
			push = math.max(push, -(d - 3)) -- a pull stops short of the player
		end
		if not e.def.boss then
			e.x, e.z = self.nav.resolve(e.x + dx / d * push, e.z + dz / d * push, e.def.radius)
		end
		if inner then
			hits += 1
			if not big then
				e.stunUntil = math.max(e.stunUntil, self.t + stun)
			elseif not e.def.boss and e.state == ST.WINDUP then
				-- Heavy enemies only lose a windup (no boss stun-lock).
				e.state = ST.RECOVER
				e.stateUntil = self.t + 0.5
			end
			local mult = if e.def.boss then S.BossMult elseif big then S.BigMult else 1
			Combat.damage(self, p, e, dmg * mult, 1, bit32.bor(Codec.DF.BLAST, Codec.DF.GRAV), px, pz)
		elseif emergency then
			e.slow = math.max(if self.t < e.slowUntil then e.slow else 0, S.Emergency.OuterSlow)
			e.slowUntil = math.max(e.slowUntil, self.t + 2)
		end
	end
	-- Specialization follow-ups.
	if br == "B" and tier >= 2 and hits > 0 then
		local gain = math.min(30, hits * 4)
		if gain > p.shield then
			p.shield = gain
			self:emit(E.SHIELD, p.id, gain)
		end
		Combat.frostNova(self, p)
	end
	if br == "B" and tier >= 3 then
		p.iframeUntil = math.max(p.iframeUntil, self.t + 1)
		self:heal(p, 10)
	end
	if br == "C" then
		for _, e in self:query(px, pz, radius + 6, {}) do
			if e.alive and not e.def.boss and not e.def.static then
				e.slow = math.max(if self.t < e.slowUntil then e.slow else 0, 0.4)
				e.slowUntil = math.max(e.slowUntil, self.t + 3)
			end
		end
	end
	if (br == "A" and tier >= 2) or (br == "C" and tier >= 3) then
		-- One follow-up wave per cast; it never schedules another (no recursive procs).
		p.hammerFollow = {
			at = self.t + (if br == "A" then 0.35 else 0.6),
			x = px,
			z = pz,
			radius = if br == "A" then radius + 3 else radius,
			dmg = dmg * (if br == "A" then 0.5 else 0.6),
		}
	end
	local st = p.s01Stats
	st.hits += hits
	st.best = math.max(st.best, hits)
	if hits >= S.CrowdHits then
		st.crowds += 1
	end
	self:emit(E.HAMMER, p.id, px, pz, radius, 2, if emergency then 1 else 0, hits)
	if emergency then
		self:banner(
			"АВАРИЙНАЯ ПЕРЕГРУЗКА",
			"Гравимолот S01 открыт навсегда · поражено " .. hits,
			C.CYAN,
			3.5,
			"hammer"
		)
	end
end

-- O01 encirclement: a profile without S01 receives it here. Solo gets a safe tutorial pause that the
-- player's own button press ends. Squads never pause the server (S01 §3).
function World:s01Event()
	for _, p in self.playerList do
		if p.alive and not p.s01 then
			p.s01 = true
			p.s01Ready = 0
			if self.solo and not self.paused then
				self.paused = "S01"
				self.pauseClock = 0
				self.s01Tutee = p.id
			end
			self:emit(E.HAMMER, p.id, p.x, p.z, Defs.S01.Emergency.Radius, 0, 1, 0)
			self:banner(
				"ГРАВИМОЛОТ",
				"Враги окружили — нанеси гравитационный удар",
				C.CYAN,
				4,
				"hammer"
			)
		end
	end
end

function World:hurtPlayer(p, amount: number, fromX: number, fromZ: number, src): boolean
	-- Крио-патроны: a chilled attacker hits softer — players, the reactor and the relay alike.
	if src and src.chill > 0 and self.t < src.slowUntil then
		amount *= 1 - src.chill
	end
	if p.isReactor then
		return self.mission:hurtReactor(amount, fromX, fromZ, false, p)
	end
	if not p.alive or self.t < Defs.Run.SafeSeconds or self.t < p.graceUntil or self.t < p.iframeUntil then
		return false
	end
	p.graceUntil = self.t + Defs.Player.Grace
	p.hitsTaken += 1
	amount *= Defs.Threat.damage(self.threat) * (1 - (p.weaponDef.guard or 0)) * (self.op.playerDamageMult or 1)
	local absorbed = math.min(p.shield, amount)
	p.shield -= absorbed
	amount -= absorbed
	if absorbed > 0 then
		Combat.frostNova(self, p)
	end
	p.hp = math.max(0, p.hp - amount)
	p.combo = 0
	self:emit(E.HURT, p.id, math.floor(amount + absorbed + 0.5), fromX, fromZ)
	local story = self.op.id == "O01" or self.op.id == "O02" -- DD-076: the second sortie saves once too
	if p.hp <= 0 and p.newbie and story and (not p.secondWind or (p.firstHunt and self.op.id == "O01")) then
		-- A newcomer's first run must not end in the first minute while they learn the controls (DD-024).
		-- DD-075: the very first sortie cannot be lost to the swarm at all — only to the clock.
		local again = p.secondWind
		p.secondWind = true
		p.hp = math.floor(p.maxHp * 0.6)
		p.iframeUntil = self.t + 2.5
		self:banner(
			"АВАРИЙНЫЙ ЩИТ",
			if again then "Держись! Убей Альфу — и рой рассыплется" else "Двигайся и стреляй — рой не даёт стоять",
			C.CYAN,
			3,
			"shield"
		)
		return true
	end
	if p.hp <= 0 then
		p.alive = false
		p.firing = false
		p.offer = nil
		p.pending = 0
		if self.solo then
			self:banner("СИГНАЛ ПОТЕРЯН", "", C.RED, 2.5, "skull")
		else
			p.downedUntil = self.t + Defs.Coop.BleedOut
			p.reviveT = 0
			self:banner(
				p.name .. " РАНЕН",
				"Встань рядом, чтобы поднять",
				C.RED,
				2.5,
				"skull"
			)
		end
		if self:alivePlayers() == 0 then
			self:finish(false, "РОЙ ПРОРВАЛСЯ")
		end
	end
	return true
end

-- Squad revives (DD-012).
function World:updateRevives(dt: number)
	local C2 = Defs.Coop
	for _, p in self.playerList do
		if not p.alive and p.downedUntil then
			local helper = nil
			for _, o in self.playerList do
				if o ~= p and o.alive and (o.x - p.x) ^ 2 + (o.z - p.z) ^ 2 <= C2.ReviveRadius ^ 2 then
					helper = o
					break
				end
			end
			if helper then
				p.reviveT += dt
			else
				p.reviveT = math.max(0, p.reviveT - dt * C2.Drain)
			end
			if p.reviveT >= C2.ReviveTime then
				p.alive = true
				p.downedUntil = nil
				p.reviveT = 0
				p.hp = math.ceil(p.maxHp * C2.ReviveHp)
				p.iframeUntil = self.t + C2.ReviveIFrames
				-- The rescuer earns the deed, not the survivor who was lying on the ground.
				if helper then
					helper.revives = (helper.revives or 0) + 1
				end
				self:emit(E.HEAL, p.id, p.hp)
				self:banner(p.name .. " В СТРОЮ", "", C.LIME, 2, "plus")
			elseif self.t >= p.downedUntil then
				p.downedUntil = nil
				self:banner(
					p.name .. " ВЫБЫЛ",
					"До конца операции наблюдает за отрядом",
					C.RED,
					2.5,
					"skull"
				)
			end
		end
	end
end

-- Result entry for one player (shared by finish and an early leave).
function World:playerResult(p)
	local upgrades = {}
	for _, id in Defs.UpgradeOrder do
		if p.ranks[id] then
			table.insert(upgrades, { id, p.ranks[id] })
		end
	end
	return {
		id = p.id,
		name = p.name,
		kills = p.kills,
		damage = math.floor(p.damage),
		weapon = p.weaponDef.id,
		evolved = p.evolved or "",
		upgrades = upgrades,
		bestCombo = p.bestCombo,
		alive = p.alive,
		s01 = table.clone(p.s01Stats),
		s01Unlocked = p.s01,
		weaponKills = p.weaponKills,
		lineShots = p.lineShots,
		species = table.clone(p.species),
		level = self.level,
		revives = p.revives or 0,
		bigDamage = math.floor(p.bigDamage),
		guardKills = p.guardKills,
		feats = table.clone(p.feats),
		causes = table.clone(p.causeKills),
		hitsTaken = p.hitsTaken,
	}
end

-- A player leaving mid-operation keeps what they personally earned (D03: progress is never lost), but
-- the operation counts as a defeat for them.
function World:leaveResult(id: number)
	local p = self.players[id]
	if not p then
		return nil
	end
	return {
		victory = false,
		reason = "ПОКИНУЛ БОЙ",
		time = self.t,
		level = self.level,
		kills = self.teamKills,
		players = { self:playerResult(p) },
		hive = "idle",
		map = self.map.id,
		op = self.op.id,
		threat = self.threat,
		components = table.clone(self.mission.components),
		eliteKilled = self.mission.eliteKilled,
	}
end

function World:heal(p, amount: number)
	if not p.alive then
		return
	end
	local before = p.hp
	p.hp = math.min(p.maxHp, p.hp + amount)
	if p.hp > before then
		self:emit(E.HEAL, p.id, math.floor(p.hp - before + 0.5))
	end
end

function World:removePlayer(id: number)
	local p = self.players[id]
	if not p then
		return
	end
	p.alive = false
	p.offer = nil
	p.pending = 0
	self.players[id] = nil
	table.remove(self.playerList, table.find(self.playerList, p))
	self.solo = #self.playerList <= 1
	if self.phase ~= "RESULTS" and self:alivePlayers() == 0 then
		self:finish(false, "ОТРЯД ПОКИНУЛ БОЙ")
	end
end

-- Enemies -------------------------------------------------------------------------------------------
function World:spawnEnemy(kind: string, x: number, z: number, spawnTime: number?)
	local def = Defs.Enemies[kind]
	local n = #self.playerList
	local hp = def.hp
	if def.scaleHp then
		hp *= Defs.hpScale(self.t)
	end
	if def.boss or def.elite or def.static then
		hp *= 1 + 0.5 * math.max(0, n - 1)
	end
	hp *= Defs.Threat.hp(self.threat)
	if not def.static then
		hp *= (self.op.enemyHpMult or 1) * (if self.anomaly and self.anomaly.hp then self.anomaly.hp else 1)
	end
	self.nextEnemyId += 1
	local e = {
		id = self.nextEnemyId,
		def = def,
		kind = kind,
		x = x,
		z = z,
		fx = 0,
		fz = -1,
		hp = hp,
		maxHp = hp,
		alive = true,
		state = ST.SPAWN,
		stateUntil = self.t + (spawnTime or 0.8),
		cd = self.t + 0.5,
		cd2 = self.t + 3,
		slow = 0,
		slowUntil = 0,
		chill = 0, -- damage reduction while slowed (Крио-патроны)
		frail = 0, -- extra damage taken while slowed (Крио-патроны)
		burnDps = 0,
		burnUntil = 0,
		burnOwner = nil,
		burnAcc = 0,
		vuln = 0,
		vulnUntil = 0,
		stunUntil = 0,
		dmgAcc = 0,
		dmgFlags = 0,
		netFlags = 0,
		losT = 0,
		los = false,
		aimX = 0,
		aimZ = 1,
		struck = false,
		invulnerable = false,
		lastX = x,
		lastZ = z,
		stuckT = 0,
		speedMult = if self.anomaly and self.anomaly.speed then self.anomaly.speed else 1,
	}
	local target = self:nearestPlayer(x, z)
	if target then
		local dx, dz = target.x - x, target.z - z
		local m = math.sqrt(dx * dx + dz * dz)
		if m > 1e-3 then
			e.fx, e.fz = dx / m, dz / m
		end
	end
	table.insert(self.enemies, e)
	self.enemyById[e.id] = e
	self.stats.spawned += 1
	if #self.enemies > self.stats.peak then
		self.stats.peak = #self.enemies
	end
	return e
end

-- Spawns near a point (e.g. a breach), scattered within `spread`, never on top of a player.
function World:spawnAtPoint(kind: string, cx: number, cz: number, spread: number, spawnTime: number?)
	local def = Defs.Enemies[kind]
	for _ = 1, 6 do
		local x, z =
			self.nav.resolve(cx + self.rng:range(-spread, spread), cz + self.rng:range(-spread, spread), def.radius)
		if self.nav.free(x, z, def.radius) then
			local ok = true
			for _, p in self.playerList do
				if p.alive and (p.x - x) ^ 2 + (p.z - z) ^ 2 < 30 * 30 then
					ok = false
					break
				end
			end
			if ok then
				return self:spawnEnemy(kind, x, z, spawnTime)
			end
		end
	end
	return nil
end

function World:damage(p, e, amount: number, depth: number, flags: number, fromX: number, fromZ: number)
	return Combat.damage(self, p, e, amount, depth, flags, fromX, fromZ)
end

function World:kill(e, p, depth: number, cause: number)
	if not e.alive then
		return
	end
	e.alive = false
	e.hp = 0
	table.insert(self.dead, e)
	if e.dmgAcc > 0 then
		self:emit(E.DMG, e.id, math.floor(e.dmgAcc + 0.5), e.dmgFlags, q(e.dmgFromX), q(e.dmgFromZ))
		e.dmgAcc, e.dmgFlags = 0, 0
	end
	self:emit(E.KILL, e.id, e.def.index, e.x, e.z, if p then p.id else 0, cause, q(e.dmgFromX), q(e.dmgFromZ))
	self.stats.killed += 1
	Outpost.onDeath(self, e)
	self.mission:onKill(e, p)
	if self.phase == "RESULTS" then
		return
	end
	local kind = e.kind
	-- research credit is the squad's (DD-059): every member studies every kill, nobody races for the
	-- last shot; personal kills still drive weapon mastery
	self.teamSpecies[kind] = (self.teamSpecies[kind] or 0) + 1
	if e.def.boss then
		self.boss = nil
		self:emit(E.BOSS, 4)
		self:finish(true, e.def.name .. " ПОВЕРЖЕН" .. (if e.def.id == "BOSS_BROODMOTHER" then "А" else ""))
		return
	end
	self.teamKills += 1
	if kind == "EN_BOMBER" and not e.blasted then
		AI.bomberBlast(self, e, p, false)
	end
	-- XP drops
	local xp = e.def.xp
	if e.def.elite then
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2
			self:dropOrb(e.x + math.cos(a) * 5, e.z + math.sin(a) * 5, 0, math.ceil(xp / 8))
		end
		if e.carrier then
			self.mission:onEliteKilled(e)
		elseif self.op.runEvolution then
			self:grantCores(e.x, e.z)
		end
	elseif xp > 0 then
		self:dropOrb(e.x, e.z, 0, xp)
	end
	if not e.def.static and not e.def.elite then
		if self.rng:chance(Defs.Drops.HealChance) then
			self:dropOrb(e.x + 1.5, e.z, 1, Defs.Drops.HealAmount)
		elseif self.rng:chance(Defs.Drops.MagnetChance) then
			self:dropOrb(e.x - 1.5, e.z, 2, 0)
		end
	end
	if kind == "HIVE" and not e.objective then
		self.hive.remaining -= 1
		if self.hive.remaining <= 0 and self.hive.state == "active" then
			self.hive.state = "cleared"
			self:banner(
				"УЛЕЙ ЗАЧИЩЕН",
				"Гнёзда уничтожены: лечение и опыт",
				C.LIME,
				3,
				"hive"
			)
			for _, pl in self.playerList do
				self:heal(pl, Defs.Hive.RewardHeal)
			end
			self:gainXp(Defs.Hive.RewardXp)
		end
	end
	if p then
		Combat.onKill(self, p, e, depth, cause)
	end
end

function World:grantCores(x: number, z: number)
	for _, p in self.playerList do
		if not p.hasCore and p.alive then
			p.hasCore = true
			local evo = Defs.Evolutions[p.weaponDef.evolution]
			self:emit(E.CORE, x, z, p.id)
			self:banner(
				evo.coreName .. " ПОЛУЧЕНО",
				"Собери оба ключа, чтобы получить " .. evo.name,
				C.GOLD,
				3.5,
				"core"
			)
			Combat.checkEvolve(self, p)
		end
	end
end

-- Orbs & pickups ------------------------------------------------------------------------------------
function World:dropOrb(x: number, z: number, kind: number, value: number)
	x, z = self.nav.resolve(x, z, 0.5)
	if kind == 0 and self.orbCount >= Defs.Drops.OrbCap then
		-- Merge into the nearest XP orb instead of growing unbounded.
		local best, bd = nil, math.huge
		for _, o in self.orbs do
			if o.kind == 0 then
				local d = (o.x - x) ^ 2 + (o.z - z) ^ 2
				if d < bd then
					best, bd = o, d
				end
			end
		end
		if best then
			best.value += value
			return
		end
	end
	self.nextOrbId += 1
	local o = { id = self.nextOrbId, x = x, z = z, kind = kind, value = value }
	self.orbs[o.id] = o
	self.orbCount += 1
	self:emit(E.ORB, o.id, x, z, kind, value)
end

function World:collectOrb(o, p)
	self.orbs[o.id] = nil
	self.orbCount -= 1
	self:emit(E.ORB_GET, o.id, p.id)
	if o.kind == 0 then
		self:gainXp(o.value)
	elseif o.kind == 1 then
		self:heal(p, o.value)
	elseif o.kind == 2 then
		self:emit(E.MAGNET, p.id)
		for _, other in self.orbs do
			if other.kind == 0 then
				self.orbs[other.id] = nil
				self.orbCount -= 1
				self:gainXp(other.value)
			end
		end
	end
end

function World:updateOrbs()
	for _, o in self.orbs do
		for _, p in self.playerList do
			if p.alive then
				local dx, dz = p.x - o.x, p.z - o.z
				local r = if o.kind == 1 and p.hp >= p.maxHp then 0 else p.magnet
				if dx * dx + dz * dz < r * r then
					self:collectOrb(o, p)
					break
				end
			end
		end
	end
end

-- Progression ---------------------------------------------------------------------------------------
-- An operation can fix its own level curve (O01: exactly three cards, DD-051). Past the table the bar is
-- full and stays there (math.huge never fills).
function World:xpFor(level: number): number
	local table_ = self.op.xpTable
	if table_ then
		return table_[level] or math.huge
	end
	return Defs.xpToNext(level)
end

function World:gainXp(amount: number)
	if self.anomaly and self.anomaly.xp then
		amount *= self.anomaly.xp
	end
	if self.xpNeed == math.huge then
		return
	end
	self.xp += amount
	while self.xp >= self.xpNeed do
		self.xp -= self.xpNeed
		self.level += 1
		self.xpNeed = self:xpFor(self.level)
		self:emit(E.LEVEL, self.level)
		for _, p in self.playerList do
			if p.alive then
				p.pending += 1
			end
		end
	end
	self:openOffers()
end

function World:openOffers()
	local any = false
	for _, p in self.playerList do
		if p.alive and p.pending > 0 and not p.offer then
			Combat.makeOffer(self, p)
		end
		if p.offer then
			any = true
		end
	end
	if any and self.phase == "ACTIVE" and self.paused ~= "EVOLVE" then
		if self.paused ~= "CHOOSE" then
			self.pauseClock = 0
		end
		self.paused = "CHOOSE"
	end
end

-- Re-deal the current offer (perk-limited).
function World:reroll(id: number): boolean
	local p = self.players[id]
	if not p or not p.offer or p.rerolls <= 0 or p.offer.lock then
		return false
	end
	p.rerolls -= 1
	p.offersMade -= 1
	Combat.makeOffer(self, p)
	return true
end

-- Remove a card from the pool for the rest of the run and re-deal. Evolution keys can't be banished.
function World:banish(id: number, offerId: number, index: number): boolean
	local p = self.players[id]
	if not p or not p.offer or p.offer.id ~= offerId or p.banishes <= 0 or p.offer.lock then
		return false
	end
	local choice = p.offer.choices[index]
	if not choice or not Defs.Upgrades[choice] or (p.ranks[choice] or 0) > 0 or Combat.isKey(p, choice) then
		return false
	end
	p.banishes -= 1
	p.banished[choice] = true
	p.offersMade -= 1
	Combat.makeOffer(self, p)
	return true
end

function World:choose(id: number, offerId: number, index: number): boolean
	local p = self.players[id]
	if not p or not p.offer or p.offer.id ~= offerId then
		return false
	end
	local choice = p.offer.choices[index]
	if not choice or (p.offer.lock and p.offer.lock ~= index) then
		return false
	end
	p.offer = nil
	p.pending = math.max(0, p.pending - 1)
	Combat.applyChoice(self, p, choice)
	if p.pending > 0 and p.alive then
		Combat.makeOffer(self, p)
	end
	self:resumeIfDone()
	return true
end

function World:resumeIfDone()
	if self.paused ~= "CHOOSE" then
		return
	end
	for _, p in self.playerList do
		if p.offer then
			return
		end
	end
	self.paused = nil
	for _, p in self.playerList do
		p.iframeUntil = math.max(p.iframeUntil, self.t + 0.6)
	end
end

function World:evolve(id: number): boolean
	local p = self.players[id]
	if not p or not p.alive or not p.canEvolve or p.evolved or self.phase ~= "ACTIVE" or self.paused then
		return false
	end
	local evo = Defs.Evolutions[p.weaponDef.evolution]
	p.evolved = evo.id
	p.canEvolve = false
	Combat.recompute(p)
	if p.weaponDef.kind ~= "beam" then
		p.ammo = p.stats.magazine
		p.reloadT = 0
	end
	self:emit(E.EVOLVE, p.id, evo.id)
	self:banner(evo.name, p.name .. ": эволюция оружия", C.GOLD, 3, "evolve")
	for _, pl in self.playerList do
		pl.iframeUntil = math.max(pl.iframeUntil, self.t + 2)
	end
	Combat.blast(self, p, p.x, p.z, 20, 90, C.GOLD, 9)
	if self.solo then
		self.paused = "EVOLVE"
		self.pauseUntil = 1.5
		self.pauseClock = 0
	end
	return true
end

-- Director ------------------------------------------------------------------------------------------
function World:currentPhaseDef()
	local override = self.mission and self.mission:phaseOverride()
	if override then
		return 1000, override
	end
	local phases = self.op.phases
	local i = 1
	for k = 1, #phases do
		if phases[k].at <= self.t then
			i = k
		end
	end
	return i, phases[i]
end

local KIND_ORDER = { "EN_RUNNER", "EN_STALKER", "EN_SPITTER", "EN_BULWARK", "EN_BOMBER" }

local function beatAt(op, at: number): boolean
	for _, b in op.beats do
		if b.at == at and b.type ~= "assault" and b.type ~= "banner" then
			return true
		end
	end
	return false
end

function World:director(dt: number)
	local index, ph = self:currentPhaseDef()
	if index ~= self.phaseIndex then
		self.phaseIndex = index
		self.phaseLabel = ph.label
		local scripted = ph.quiet or beatAt(self.op, ph.at)
		if index > 1 and index < 1000 and not scripted then
			local calm = ph.rate < 2
			self:banner(
				ph.label,
				if calm
					then "Затишье — подлечись и соберись"
					else "Прорывы: " .. #ph.dirs .. " направлений",
				if calm then C.CYAN else C.ORANGE,
				2.6,
				if calm then "timer" else "threat"
			)
		end
	end
	local n = math.max(1, #self.playerList)
	local cap = math.min(ph.cap * (1 + 0.45 * (n - 1)), Defs.Run.MaxActive * (1 + 0.45 * (n - 1)))
	local anomalySpawn = if self.anomaly and self.anomaly.spawn then self.anomaly.spawn else 1
	self.spawnAcc += ph.rate * (1 + 0.4 * (n - 1)) * Defs.Threat.spawn(self.threat) * (self.op.spawnMult or 1) * anomalySpawn * dt
	local active, specials = 0, 0
	for _, e in self.enemies do
		if not e.def.boss and not e.def.static then
			active += 1
			if e.kind ~= "EN_RUNNER" then
				specials += 1
			end
		end
	end
	local guard = 0
	while self.spawnAcc >= 1 and guard < 8 do
		guard += 1
		self.spawnAcc -= 1
		if active >= cap then
			self.spawnAcc = math.min(self.spawnAcc, 1)
			break
		end
		local kind = self.rng:weighted(ph.w, KIND_ORDER) or "EN_RUNNER"
		local specialShare = 0.32 * (if self.anomaly and self.anomaly.specials then self.anomaly.specials else 1)
		if self.anomaly and self.anomaly.specials and kind == "EN_RUNNER" and self.rng:chance(0.12) then
			kind = KIND_ORDER[self.rng:int(2, 3)]
		end
		if kind ~= "EN_RUNNER" and specials >= math.max(3, active * specialShare) then
			kind = "EN_RUNNER"
		end
		if self:spawnAtBreach(kind, ph.dirs) then
			active += 1
			if kind ~= "EN_RUNNER" then
				specials += 1
			end
		end
	end
	-- Scripted beats and the objective
	self.mission:update(dt)
	if self.phase ~= "ACTIVE" then
		return
	end
	if self.hive.state == "active" and self.t >= self.hive.endsAt then
		self.hive.state = "failed"
		for _, e in self.enemies do
			if e.alive and e.kind == "HIVE" then
				e.alive = false
				table.insert(self.dead, e)
				self:emit(E.KILL, e.id, e.def.index, e.x, e.z, 0, 9)
			end
		end
		self:banner("ГНЁЗДА УШЛИ", "Рой становится сильнее", C.RED, 2.5, "hive")
	end
	local limit = self.op.hardLimit or Defs.Run.HardLimit
	if self.t >= limit and self.phase == "ACTIVE" then
		self:finish(false, if self.op.mode == "raid" then "ОБОРОНА ВЫСТОЯЛА" else "ВРЕМЯ ВЫШЛО — РОЙ ПОБЕДИЛ")
	end
	if self.op.objective == "boss" and self.t >= 385 and not self.breatherHeal then
		self.breatherHeal = true
		self:dropOrb(8, -4, 1, 40)
		self:dropOrb(-8, -4, 1, 40)
	end
end

-- Legacy scripted beats (boss operations) ----------------------------------------------------------
function World:legacyElite()
	self.legacyElites = (self.legacyElites or 0) + 1
	local e = self:spawnAtBreach(self.map.elite, self.map.spawnOrder, 1.6)
	if e then
		self:banner(
			if self.legacyElites == 1 then "ЭЛИТА НА ПОДХОДЕ" else "ВТОРАЯ ЭЛИТА",
			if self.op.runEvolution
				then "Убей элиту — она несёт ядро эволюции"
				else "Опасная цель — сосредоточь огонь",
			C.GOLD,
			3.5,
			"@" .. e.def.index
		)
	end
end

function World:startHive()
	if self.hive.state ~= "idle" then
		return
	end
	self.hive.state = "active"
	self.hive.total = #self.map.hiveSites
	self.hive.remaining = #self.map.hiveSites
	self.hive.endsAt = self.t + 55
	for _, s in self.map.hiveSites do
		self:spawnEnemy("HIVE", s.x, s.z, 1.5)
	end
	self:banner(
		"ПРОРЫВ УЛЬЯ",
		"Уничтожь 3 гнезда, пока они не ушли под землю",
		C.LIME,
		3.5,
		"@6"
	)
end

function World:spawnBoss()
	if self.bossSpawned then
		return
	end
	self.bossSpawned = true
	local b = self:spawnEnemy(self.map.boss, self.map.bossEntry.x, self.map.bossEntry.z, 0.1)
	b.hp *= self.op.bossHpMult or 1
	b.maxHp = b.hp
	b.state = ST.ENTER
	b.stateUntil = self.t + 3.5
	b.invulnerable = true
	self.boss = b
	self:emit(E.BOSS, 1, b.x, b.z)
	self:revealGrace(Codec.REVEAL_TIME + 0.4)
	self:banner(
		b.def.name,
		if b.kind == "BOSS_DEVOURER"
			then "Земля дрожит. Он идёт снизу."
			else "Королева роя прорвалась через северные ворота",
		C.RED,
		4,
		"@" .. b.def.index
	)
end

-- The boss / leader entrance (DD-082) turns every camera to it for Codec.REVEAL_TIME: players can't
-- be hurt meanwhile (the swarm keeps coming, so the fight resumes where it was).
function World:revealGrace(seconds: number)
	for _, pl in self.playerList do
		pl.iframeUntil = math.max(pl.iframeUntil, self.t + seconds)
	end
end

function World:enrageBoss()
	if self.boss and not self.enraged then
		self.enraged = true
		self:emit(E.BOSS, 3)
		local limit = self.op.hardLimit or Defs.Run.HardLimit
		self:banner(
			"ЯРОСТЬ",
			string.format("Убей босса до %d:%02d", limit // 60, limit % 60),
			C.RED,
			3,
			"skull"
		)
	end
end

function World:spawnAtBreach(kind: string, dirs: { string }, spawnTime: number?)
	local def = Defs.Enemies[kind]
	for _ = 1, 6 do
		local key = dirs[self.rng:int(1, #dirs)]
		key = self.dirMap and self.dirMap[key] or key
		local s = self.map.spawns[key]
		local x = s.x + self.rng:range(-9, 9)
		local z = s.z + self.rng:range(-9, 9)
		x, z = self.nav.resolve(x, z, def.radius)
		local ok = self.nav.free(x, z, def.radius)
		if ok then
			for _, p in self.playerList do
				if p.alive and (p.x - x) ^ 2 + (p.z - z) ^ 2 < 42 * 42 then
					ok = false
					break
				end
			end
		end
		if ok then
			return self:spawnEnemy(kind, x, z, spawnTime)
		end
	end
	return nil
end

-- Grid ----------------------------------------------------------------------------------------------
local function gridKey(cx: number, cz: number): number
	return (cx + 64) * 256 + (cz + 64)
end

function World:rebuildGrid()
	local grid = self.grid
	for k, cell in grid do
		table.clear(cell)
		table.insert(self.gridPool, cell)
		grid[k] = nil
	end
	for _, e in self.enemies do
		if e.alive then
			local k = gridKey(e.x // GRID, e.z // GRID)
			local cell = grid[k]
			if not cell then
				cell = table.remove(self.gridPool) or {}
				grid[k] = cell
			end
			table.insert(cell, e)
		end
	end
end

-- Fills and returns self.queryBuf with live enemies within r of (x,z). Callers must not hold it.
function World:query(x: number, z: number, r: number, out: { any }?)
	local buf = out or self.queryBuf
	table.clear(buf)
	local r2 = r * r
	for cx = (x - r) // GRID, (x + r) // GRID do
		for cz = (z - r) // GRID, (z + r) // GRID do
			local cell = self.grid[gridKey(cx, cz)]
			if cell then
				for _, e in cell do
					if e.alive then
						local dx, dz = e.x - x, e.z - z
						local rr = r + e.def.radius
						if dx * dx + dz * dz <= math.max(r2, rr * rr) then
							table.insert(buf, e)
						end
					end
				end
			end
		end
	end
	return buf
end

-- Hazards (spitter puddles, boss acid lanes) --------------------------------------------------------
function World:addHazard(h)
	h.lastHit = {}
	table.insert(self.hazards, h)
end

local function inShape(h, x: number, z: number, pad: number): boolean
	local dx, dz = x - h.x, z - h.z
	if h.shape == Codec.Shape.CIRCLE then
		return dx * dx + dz * dz < (h.a + pad) ^ 2
	elseif h.shape == Codec.Shape.LINE then
		local s = dx * h.dx + dz * h.dz
		local perp = math.abs(dx * h.dz - dz * h.dx)
		return s >= -pad and s <= h.a + pad and perp <= h.b / 2 + pad
	end
	return false
end
World.inShape = inShape

function World:updateHazards()
	local t = self.t
	local i = 1
	while i <= #self.hazards do
		local h = self.hazards[i]
		if t >= h.untilT then
			table.remove(self.hazards, i)
		else
			if t >= h.activeFrom then
				for _, p in self.playerList do
					if p.alive and inShape(h, p.x, p.z, 0.8) then
						if h.slow then
							p.slowUntil = t + 0.35
							p.slowAmt = h.slow
						end
						if h.damage > 0 and t >= (h.lastHit[p.id] or -99) + h.tick then
							h.lastHit[p.id] = t
							self:hurtPlayer(p, h.damage, h.x, h.z)
						end
					end
				end
				self.mission:hazardTick(h, inShape)
			end
			i += 1
		end
	end
end

function World:countHazards(source: string): number
	local n = 0
	for _, h in self.hazards do
		if h.source == source then
			n += 1
		end
	end
	return n
end

-- Siege structures for the client (static per run: positions, levels).
function World:structureState()
	if #self.structures == 0 then
		return nil
	end
	if not self.structureCache then
		local list = {}
		for _, s in self.structures do
			table.insert(list, { s.slot, s.id, s.lvl })
		end
		self.structureCache = list
	end
	return self.structureCache
end

-- Anomaly «Кислотный дождь»: telegraphed acid drops land near the hunters.
function World:acidRain(dt: number)
	if not (self.anomaly and self.anomaly.acidRain) then
		return
	end
	self.acidRainT -= dt
	if self.acidRainT > 0 then
		return
	end
	self.acidRainT = 3.2 + self.rng:range(0, 1.5)
	for _, p in self.playerList do
		if p.alive then
			local x, z = self.nav.resolve(p.x + self.rng:range(-14, 14), p.z + self.rng:range(-14, 14), 1)
			local r = 5
			self:addHazard({
				source = "rain",
				shape = Codec.Shape.CIRCLE,
				x = x,
				z = z,
				dx = 0,
				dz = 1,
				a = r,
				b = 0,
				activeFrom = self.t + 1.3,
				untilT = self.t + 4.3,
				damage = 6,
				tick = 0.5,
			})
			self:emit(E.TELE, Codec.Shape.CIRCLE, x, z, 0, 1, r, 0, 1.3, C.LIME, 3)
		end
	end
end

-- Coils ---------------------------------------------------------------------------------------------
function World:updateCoils()
	for i, c in self.map.coils do
		if self.t >= self.coils[i] then
			for _, p in self.playerList do
				if p.alive and (p.x - c.x) ^ 2 + (p.z - c.z) ^ 2 < Defs.Coil.Radius ^ 2 then
					self.coils[i] = self.t + Defs.Coil.Cooldown
					self:emit(E.COIL, i, p.id)
					local targets = self:query(c.x, c.z, Defs.Coil.Range, {})
					table.sort(targets, function(a, b)
						return (a.x - c.x) ^ 2 + (a.z - c.z) ^ 2 < (b.x - c.x) ^ 2 + (b.z - c.z) ^ 2
					end)
					for k = 1, math.min(#targets, Defs.Coil.Targets) do
						local e = targets[k]
						self:emit(E.ARC, c.x, c.z, e.x, e.z, C.CYAN)
						local dmg = if e.def.big then Defs.Coil.Damage * 0.6 else Defs.Coil.Damage
						e.stunUntil = math.max(e.stunUntil, self.t + 0.8)
						self:damage(p, e, dmg, 1, bit32.bor(Codec.DF.ARC, Codec.DF.ENV), c.x, c.z)
					end
					break
				end
			end
		end
	end
end

-- Main loop -----------------------------------------------------------------------------------------
function World:finish(victory: boolean, reason: string)
	if self.phase == "RESULTS" then
		return
	end
	self.phase = "RESULTS"
	self.paused = nil
	local list = {}
	for _, p in self.playerList do
		table.insert(list, self:playerResult(p))
	end
	local hiveState = self.hive.state
	if self.op.objective == "nests" and #self.mission.targets > 0 and self.mission:targetsLeft() == 0 then
		hiveState = "cleared"
	end
	self.result = {
		victory = victory,
		reason = reason,
		time = self.t,
		level = self.level,
		kills = self.teamKills,
		players = list,
		hive = hiveState,
		map = self.map.id,
		op = self.op.id,
		threat = self.threat,
		components = table.clone(self.mission.components),
		objectives = self.mission.destroyed,
		chapterEnd = self.op.chapterEnd == true,
		eliteKilled = self.mission.eliteKilled,
		reactor = if self.mission.reactor then self.mission.reactor.hp / self.mission.reactor.maxHp else nil,
		mode = self.op.mode or "hunt",
		siege = self.op.siege,
		raid = if self.op.target
			then {
				uid = self.op.target.uid,
				name = self.op.target.name,
				rating = self.op.target.rating,
				rival = self.op.target.rival,
				power = Outpost.power(self.op.target.slots),
				t = self.op.target.t,
				revenge = self.op.target.revenge,
			}
			else nil,
		core = if self.core then math.max(0, self.core.hp / self.core.maxHp) else nil,
		anomaly = if self.anomaly then self.anomaly.id else nil,
		squad = #self.playerList,
		species = table.clone(self.teamSpecies),
	}
	for _, p in self.playerList do
		p.firing = false
		p.offer = nil
	end
	if victory then
		for _, e in self.enemies do
			if e.alive then
				e.alive = false
				table.insert(self.dead, e)
				self:emit(E.KILL, e.id, e.def.index, e.x, e.z, 0, 8)
			end
		end
		self:banner(if self.op.mode == "raid" then "ВТОРЖЕНИЕ УСПЕШНО" elseif self.op.mode == "siege" then "БУР ВЫСТОЯЛ" else "ВЫЛАЗКА УДАЛАСЬ", reason, C.GOLD, 5, "crown")
	else
		self:banner("ПОРАЖЕНИЕ", reason, C.RED, 5, "skull")
	end
end

function World:step(dt: number)
	if self.phase == "RESULTS" then
		return
	end
	if self.phase == "COUNTDOWN" then
		self.countdown -= dt
		-- A solo newcomer's first run waits for their first move or shot (DD-024): still loading or
		-- reading the controls must not cost them the run.
		-- DD-075: the first defence waits too (its arrival scene shows the new turret first).
		local waiting = false
		if self.countdown <= 0 and self.solo and (self.op.id == "O01" or self.op.id == "STRIKE" or self.op.id == "O02" or self.op.id == "O03" or self.op.id == "O04" or self.op.id == "O05" or self.op.id == "O06" or self.op.id == "O07") and not self.gotInput then
			waiting = true
			for _, p in self.playerList do
				if not p.newbie and self.op.id == "O01" then
					waiting = false
				end
			end
		end
		self.waiting = waiting
		if self.countdown <= 0 and not waiting then
			self.phase = "ACTIVE"
			self:banner(self.op.name, self.op.goal, C.LIME, 3, "")
			if self.anomaly then
				self:banner("АНОМАЛИЯ: " .. self.anomaly.name, self.anomaly.text, C.GOLD, 3.5, self.anomaly.icon)
			end
		end
		return
	end
	if self.paused then
		self.pauseClock += dt
		if self.paused == "EVOLVE" and self.pauseClock >= self.pauseUntil then
			self.paused = nil
			self:openOffers()
		elseif self.paused == "CHOOSE" and not self.solo and self.pauseClock >= Defs.Run.ChoiceTimeoutCoop then
			for _, p in self.playerList do
				while p.offer do
					-- The first tutorial offer can lock slot 2/3. Picking 1 repeatedly never
					-- consumed it and froze the whole server. Always honor the server's lock,
					-- and stop if an invalid offer still cannot be consumed.
					if not self:choose(p.id, p.offer.id, p.offer.lock or 1) then
						break
					end
				end
			end
		end
		return
	end
	self.acc = math.min(self.acc + dt, STEP * 4)
	while self.acc >= STEP and self.phase == "ACTIVE" and not self.paused do
		self.acc -= STEP
		self:tick(STEP)
	end
end

function World:tick(dt: number)
	local clock = os.clock()
	self.t += dt
	self:director(dt)
	if self.phase ~= "ACTIVE" then
		return
	end
	self.fieldT -= dt
	if self.fieldT <= 0 then
		self.fieldT = 0.3
		local sources = {}
		for _, p in self.playerList do
			if p.alive then
				table.insert(sources, { p.x, p.z })
			end
		end
		self.nav.buildField(self.field, sources)
	end
	self:rebuildGrid()
	for _, p in self.playerList do
		if p.alive then
			if p.hammerAt and self.t >= p.hammerAt then
				self:hammerImpact(p)
			end
			local f = p.hammerFollow
			if f and self.t >= f.at then
				p.hammerFollow = nil
				for _, e in self:query(f.x, f.z, f.radius + 2, {}) do
					if
						e.alive
						and not e.def.static
						and (e.x - f.x) ^ 2 + (e.z - f.z) ^ 2 <= (f.radius + e.def.radius) ^ 2
					then
						Combat.damage(
							self,
							p,
							e,
							f.dmg * (if e.def.boss then Defs.S01.BossMult elseif e.def.big then Defs.S01.BigMult else 1),
							1,
							bit32.bor(Codec.DF.BLAST, Codec.DF.GRAV),
							f.x,
							f.z
						)
					end
				end
				self:emit(E.HAMMER, p.id, f.x, f.z, f.radius, 3, 0, 0)
			end
			Combat.updatePlayer(self, p, dt)
		end
	end
	AI.update(self, dt)
	if #self.structures > 0 then
		Outpost.update(self, dt)
	else
		Outpost.updateShells(self)
	end
	self:acidRain(dt)
	if not self.solo then
		self:updateRevives(dt)
	end
	self:updateHazards()
	self:updateOrbs()
	self:updateCoils()
	-- Flush aggregated damage numbers.
	for _, e in self.enemies do
		if e.dmgAcc > 0 then
			self:emit(E.DMG, e.id, math.floor(e.dmgAcc + 0.5), e.dmgFlags, q(e.dmgFromX), q(e.dmgFromZ))
			e.dmgAcc, e.dmgFlags = 0, 0
		end
	end
	-- Compact the dead.
	if #self.dead > 0 then
		local i = 1
		local list = self.enemies
		while i <= #list do
			if not list[i].alive then
				self.enemyById[list[i].id] = nil
				list[i] = list[#list]
				list[#list] = nil
			else
				i += 1
			end
		end
		table.clear(self.dead)
	end
	local ms = (os.clock() - clock) * 1000
	if ms > self.stats.maxTickMs then
		self.stats.maxTickMs = ms
	end
	self.stats.lastTickMs = ms
end

-- Replication -----------------------------------------------------------------------------------------
function World:encodeEnemies(): buffer
	local list = self.enemies
	local t = self.t
	for _, e in list do
		local f = 0
		if t < e.burnUntil then
			f += Codec.Flag.BURN
		end
		if t < e.slowUntil then
			f += Codec.Flag.SLOW
		end
		if t < e.vulnUntil and e.vuln > 0 then
			f += Codec.Flag.CORRODE
		end
		if e.state == ST.EXPOSED then
			f += Codec.Flag.EXPOSED
		end
		if e.mutant then
			f += Codec.Flag.MUTANT
		end
		e.netFlags = f
	end
	return Codec.encodeEnemies(list, #list)
end

function World:publicState()
	local players = {}
	for _, p in self.playerList do
		local s = p.stats
		table.insert(players, {
			id = p.id,
			name = p.name,
			alive = p.alive,
			hp = math.ceil(p.hp),
			maxHp = p.maxHp,
			shield = math.ceil(p.shield),
			weapon = p.weaponDef.id,
			evolved = p.evolved or "",
			core = p.hasCore,
			canEvolve = p.canEvolve,
			ammo = p.ammo,
			mag = s.magazine,
			reload = if p.reloadT > 0 then 1 - p.reloadT / p.reloadDur else 0,
			reloadEmpty = p.reloadEmpty,
			spread = math.floor(p.spread * 100 + 0.5) / 100,
			pierce = s.pierce,
			multi = s.multi,
			heat = math.floor(p.heat),
			overheated = p.overheatT > 0,
			rate = s.rate,
			dash = math.max(0, p.dashReady - self.t),
			s01 = p.s01,
			s01Left = math.max(0, p.s01Ready - self.t),
			s01Cd = p.s01Cd,
			s01Casting = p.hammerAt ~= nil,
			s01Tutorial = self.paused == "S01" and self.s01Tutee == p.id,
			downed = p.downedUntil ~= nil,
			bleed = if p.downedUntil then math.max(0, math.ceil(p.downedUntil - self.t)) else nil,
			revive = if p.downedUntil then math.floor(p.reviveT / Defs.Coop.ReviveTime * 100) else nil,
			ranks = p.ranks,
			offer = p.offer,
			pending = p.pending,
			rerolls = p.rerolls,
			banishes = p.banishes,
			dashMax = Defs.Player.DashCooldown * p.dashMult,
			kills = p.kills,
			combo = p.combo,
			slow = if self.t < (p.slowUntil or 0) then p.slowAmt else nil,
		})
	end
	local boss = nil
	if self.boss and self.boss.alive then
		boss = {
			kind = self.boss.def.index,
			hp = self.boss.hp / self.boss.maxHp,
			exposed = self.boss.state == ST.EXPOSED,
			enraged = self.enraged,
			invulnerable = self.boss.invulnerable,
		}
	end
	local coils = {}
	for i = 1, #self.coils do
		coils[i] = math.max(0, self.coils[i] - self.t)
	end
	return {
		phase = self.phase,
		t = self.t,
		countdown = math.max(0, self.countdown),
		waiting = self.waiting == true,
		paused = self.paused or "",
		pauseClock = self.pauseClock,
		solo = self.solo,
		level = self.level,
		xp = self.xp,
		xpNeed = if self.xpNeed == math.huge then 0 else self.xpNeed, -- 0 = level cap (bar stays full)
		label = self.phaseLabel,
		boss = boss,
		hive = if self.hive.state == "active" then self.hive.remaining else nil,
		hiveEnds = if self.hive.state == "active" then self.hive.endsAt - self.t else nil,
		coils = coils,
		players = players,
		map = self.map.id,
		op = self.op.id,
		runEvolution = self.op.runEvolution,
		hardLimit = self.op.hardLimit or Defs.Run.HardLimit,
		mission = self.mission:publicState(),
		mode = self.op.mode or "hunt",
		structures = self:structureState(),
		core = if self.core and self.core.alive then { hp = self.core.hp / self.core.maxHp, name = self.op.name } else nil,
		anomaly = if self.anomaly then self.anomaly.id else nil,
		threat = self.threat,
		result = self.result,
		kills = self.teamKills,
		enemyCount = #self.enemies,
	}
end

return World
