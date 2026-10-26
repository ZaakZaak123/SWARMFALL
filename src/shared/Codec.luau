--!strict
-- Network contract. Enemies replicate as a packed buffer (11 bytes each) instead of instances;
-- gameplay events travel as compact numeric arrays batched per server frame.

local Codec = {}

-- User ids are not world coordinates: real accounts exceed both 1e6 and 32-bit ranges.
-- Keep the complete integer range of Luau numbers; negative simulated ids are Studio-only.
function Codec.isUserId(value: any, studio: boolean?): boolean
	return type(value) == "number"
		and value == value
		and math.abs(value) <= 9007199254740991
		and value % 1 == 0
		and (value > 0 or (studio == true and value < 0))
end

Codec.Remotes = {
	Input = "Input", -- C->S  (action: string, ...)
	State = "State", -- S->C  (enemyBuffer, stateTable) ~15 Hz
	Events = "Events", -- S->C  ({event}) batched
	Profile = "Profile", -- S->C  (public profile) on change
	Social = "Social", -- S->C  (kind: string, data) camp toasts: invites, likes, launch errors
}

-- Event type codes: first element of every event array.
Codec.E = {
	SHOT = 1, -- pid, ox, oz, ex, ez, weaponIndex, evolved(0/1)
	DMG = 2, -- enemyId, amount, flags, fromX?, fromZ? (damage source, for hit reactions)
	KILL = 3, -- enemyId, kindIndex, x, z, killerPid, cause, fromX?, fromZ? (last hit source)
	ARC = 4, -- x1, z1, x2, z2, colorCode
	BOOM = 5, -- x, z, radius, colorCode
	TELE = 6, -- shape, x, z, dx, dz, a, b, telegraphSeconds, colorCode, activeSeconds (hazard lingers after)
	ORB = 7, -- orbId, x, z, kind, value
	ORB_GET = 8, -- orbId, pid
	HURT = 9, -- pid, amount, fromX, fromZ
	BANNER = 10, -- text, subtext, colorCode, duration, visual (icon name or "@<enemyIndex>")
	DASH = 11, -- pid, x, z, dx, dz
	OVERDRIVE = 12, -- pid, x, z
	EVOLVE = 13, -- pid, evolutionId
	CORE = 14, -- x, z, pid
	COIL = 15, -- coilIndex, pid
	LEVEL = 16, -- level
	SPAWN = 17, -- x, z, kindIndex (breach burst at spawn point)
	MAGNET = 18, -- pid
	HEAL = 19, -- pid, amount
	SHIELD = 20, -- pid, amount
	BEAM = 21, -- pid, ox, oz, ex, ez, evolved
	BOSS = 23, -- action: 1 roar/enter (x, z), 2 exposed, 3 enrage, 4 death, 5 burrow, 6 leader down (x, z), 8 leader enters (x, z),
	--          7 pylon song (x, z): the run is won (DD-075/077)
	SPIT = 24, -- fromX, fromZ, toX, toZ, flightTime
	REACTOR = 25, -- action: 1 hit (amount, fromX, fromZ), 2 warning (hpPercent), 3 destroyed, 4 relay hit (amount, fromX, fromZ, x, z),
	--             5 emergency capacitor, 6 barrier shield (amount, x, z)
	ASSAULT = 26, -- spawnX, spawnZ, count, etaSeconds, targetX, targetZ (strike group announced)
	COMPONENT = 27, -- x, z, componentId (permanent component dropped — e.g. Ядро Бури)
	HAMMER = 28, -- pid, x, z, radius, phase (0 granted, 1 windup, 2 impact), emergency 0/1, hits
	TURRET = 30, -- ref (+slot allied / -enemyId hostile), fromX, fromZ, toX, toZ, kind (1 gun, 2 arc, 3 mortar, 4 shield)
	OBJECTIVE = 29, -- action, x, z, a, b, c: 1 relay active (radius, charge, need), 2 target revealed (index),
	--                 3 relay charged, 4 target destroyed (index, destroyed, total)
}

-- Color codes shared by FX.
-- How long every camera looks at a boss / leader entering (DD-082); players are untouchable meanwhile.
Codec.REVEAL_TIME = 2.6

Codec.C = { CYAN = 1, ORANGE = 2, VIOLET = 3, RED = 4, LIME = 5, WHITE = 6, GOLD = 7, BLUE = 8, ICE = 9 }

-- Telegraph shapes
Codec.Shape = { CIRCLE = 1, LINE = 2, CONE = 3 }

-- Enemy AI states (fit in 4 bits)
Codec.State = {
	SPAWN = 0,
	MOVE = 1,
	WINDUP = 2,
	ATTACK = 3,
	RECOVER = 4,
	STUN = 5,
	EXPOSED = 6,
	ENTER = 7,
	IDLE = 8,
}
Codec.Flag = { BURN = 1, SLOW = 2, CORRODE = 4, EXPOSED = 8, HIT = 16, MUTANT = 32 }

-- Damage flags
-- GRAV: S01 Gravihammer. CARD: an independent card ability (shock dash). ENV: environment the player
-- triggered (coils, bomber chain blasts). Kill credit: see Combat.onKill / D03 §2.
Codec.DF = { CRIT = 1, BURN = 2, ARC = 4, BLAST = 8, ARMOR = 16, GRAV = 32, CARD = 64, ENV = 128 }
-- Kill causes (KILL event + attribution): 0 shot, 1 arc, 2 blast, 3 burn, 4 S01, 5 card ability, 6 environment
Codec.Cause = { SHOT = 0, ARC = 1, BLAST = 2, BURN = 3, S01 = 4, CARD = 5, ENV = 6 }

local RECORD = 11
local SCALE = 32

export type EnemyRecord = {
	id: number,
	kind: number,
	x: number,
	z: number,
	state: number,
	flags: number,
	facing: number, -- radians
	hp: number, -- 0..1
}

-- Encodes an array of enemies {id, kind (index), x, z, state, flags, fx, fz, hp, maxHp}
function Codec.encodeEnemies(list: { any }, count: number): buffer
	local b = buffer.create(2 + count * RECORD)
	buffer.writeu16(b, 0, count)
	local o = 2
	for i = 1, count do
		local e = list[i]
		buffer.writeu16(b, o, e.id % 65536)
		buffer.writeu8(b, o + 2, e.def.index)
		buffer.writei16(b, o + 3, math.clamp(math.floor(e.x * SCALE + 0.5), -32767, 32767))
		buffer.writei16(b, o + 5, math.clamp(math.floor(e.z * SCALE + 0.5), -32767, 32767))
		buffer.writeu8(b, o + 7, e.state)
		buffer.writeu8(b, o + 8, e.netFlags)
		local angle = math.atan2(e.fx, e.fz) -- 0 = +Z
		buffer.writeu8(b, o + 9, math.floor(((angle / (2 * math.pi)) % 1) * 255 + 0.5))
		buffer.writeu8(b, o + 10, math.clamp(math.floor(e.hp / e.maxHp * 255 + 0.5), 0, 255))
		o += RECORD
	end
	return b
end

-- Decodes into a caller-owned array of reusable records; returns count.
function Codec.decodeEnemies(b: buffer, out: { EnemyRecord }): number
	local count = buffer.readu16(b, 0)
	local o = 2
	for i = 1, count do
		local r = out[i]
		if not r then
			r = { id = 0, kind = 0, x = 0, z = 0, state = 0, flags = 0, facing = 0, hp = 1 }
			out[i] = r
		end
		r.id = buffer.readu16(b, o)
		r.kind = buffer.readu8(b, o + 2)
		r.x = buffer.readi16(b, o + 3) / SCALE
		r.z = buffer.readi16(b, o + 5) / SCALE
		r.state = buffer.readu8(b, o + 7)
		r.flags = buffer.readu8(b, o + 8)
		r.facing = buffer.readu8(b, o + 9) / 255 * 2 * math.pi
		r.hp = buffer.readu8(b, o + 10) / 255
		o += RECORD
	end
	return count
end

return Codec
