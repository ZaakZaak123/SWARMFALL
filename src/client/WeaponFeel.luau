--!nonstrict
-- Weapon feel profiles: everything that makes a gun *feel* like itself, as data. One table per weapon
-- (+ evolution overrides) drives the character hold pose, recoil springs, mechanism animation, muzzle
-- flash, projectile style, impacts, shells, camera response and sound. Adding a weapon = adding a
-- profile here + a model in Models; Rig / Shots / Fx interpret the styles.

local Feel = {}

local PROFILES = {
	-- W01 arc rifle: fast, precise; a crisp electric crack, snappy light kick that builds a little over a
	-- long burst, an arc jumping between the emitter prongs, bright bolts that streak to the target.
	W_ARC_RIFLE = {
		scale = 0.66,
		hold = Vector3.new(-0.75, -0.36, -1.05), -- grip offset from the right shoulder (aim space)
		lowReady = 0.3, -- gun dips by this angle (rad) when not firing
		sway = 0.6,
		recoil = { back = 0.3, rise = 0.08, side = 0.035, roll = 0.05, freq = 8, damp = 0.45, torso = 0.03, build = 0.6 },
		cam = { kick = 0.6, shake = 0.035, push = 0.2, fov = 0.5, reticle = 4 },
		flash = { style = "star", size = 1.0, light = 10, life = 0.045, arc = true },
		tracer = { style = "bolt", speed = 320, length = 8, width = 0.26 },
		impact = { style = "spark", size = 1.0, knock = 0.35, wallSound = "wallHit" },
		shell = { kind = "cell", delay = 0 },
		action = "coil",
		reload = "cell",
		sound = { "rifleZap", "rifle", "rifleClick" },
		lowAmmo = 0.25, -- below this fraction the shot gains a dry "tick" layer
		-- animation beats (Rig) -> sound cues; magOut also drops the spent cell
		beats = { equip = "equip", magOut = "magOut", magIn = "magIn", bolt = "boltRack", evolve = "evolveStorm" },
		dry = "dryFire",
	},
	-- Close-range pump shotgun: huge shove, cone of pellets, fire, pump + ejected shell.
	W_SCATTERGUN = {
		scale = 0.66,
		hold = Vector3.new(-0.72, -0.45, -1.0),
		lowReady = 0.35,
		sway = 0.9,
		recoil = { back = 0.75, rise = 0.42, side = 0.06, roll = 0.12, freq = 5.5, damp = 0.42, torso = 0.14 },
		cam = { kick = 3.8, shake = 0.17, push = 1.0, fov = 3.5, reticle = 18 },
		flash = { style = "blast", size = 1.9, light = 18, life = 0.07, smoke = 3 },
		tracer = { style = "pellet", speed = 240, length = 3.6, width = 0.19 },
		impact = { style = "pellet", size = 0.8, knock = 0.8 },
		shell = { kind = "shell", delay = 0.2 },
		action = "pump",
		actionTime = 0.4,
		actionSound = { "pump", 0.12 },
		reload = "shells",
		sound = { "shotgun" },
	},
	-- Continuous plasma: no per-shot kick, a living vibrating beam and a spinning crystal.
	W_PLASMA_BEAM = {
		scale = 0.66,
		hold = Vector3.new(-0.72, -0.45, -1.05),
		lowReady = 0.3,
		sway = 0.7,
		recoil = { back = 0.04, rise = 0.015, side = 0.01, roll = 0.01, freq = 14, damp = 0.3, torso = 0.01, buzz = 0.035 },
		cam = { kick = 0, shake = 0.015, push = 0, fov = 0, reticle = 3 },
		flash = { style = "beam", size = 1.0, light = 12 },
		beam = { width = 0.9, helix = 0.45, spin = 18 },
		impact = { style = "beam", size = 1.0, knock = 0.15 },
		action = "spin",
		reload = "vent",
		sound = {},
	},
	-- Heavy rail: charge glow between shots, violent shove, barrel slide, helix trail that lingers.
	W_RAILGUN = {
		scale = 0.66,
		hold = Vector3.new(-0.7, -0.42, -0.95),
		lowReady = 0.25,
		sway = 1.1,
		recoil = { back = 1.0, rise = 0.3, side = 0.04, roll = 0.08, freq = 4.2, damp = 0.5, torso = 0.18 },
		cam = { kick = 4.5, shake = 0.24, push = 1.3, fov = 5, reticle = 22 },
		flash = { style = "rail", size = 2.3, light = 24, life = 0.09, smoke = 2 },
		tracer = { style = "rail", width = 0.55 },
		impact = { style = "rail", size = 1.3, knock = 1.2 },
		shell = { kind = "slug", delay = 0.12 },
		action = "slide",
		actionTime = 0.5,
		actionSound = { "railCharge", 0.3 },
		charge = true,
		reload = "breech",
		sound = { "rail" },
	},
}

-- Evolution overrides (merged one level deep over the base profile).
local EVOLVED = {
	-- Громовержец: storm bolts — a forked lightning tracer riding a fast bolt, heavier crack + thunder.
	W_ARC_RIFLE = {
		tracer = { style = "lightning", speed = 600, length = 12, width = 0.3 },
		flash = { style = "star", size = 1.3, light = 14, life = 0.05, arc = true },
		impact = { style = "shock", size = 1.2, knock = 0.45, wallSound = "wallHit" },
		recoil = { back = 0.34, rise = 0.1, side = 0.04, roll = 0.06, freq = 7.5, damp = 0.45, torso = 0.04, build = 0.6 },
		cam = { kick = 0.75, shake = 0.05, push = 0.25, fov = 0.7, reticle = 5 },
		sound = { "stormZap", "thunder", "rifleClick" },
	},
	W_SCATTERGUN = {
		tracer = { style = "pellet", speed = 230, length = 4.2, width = 0.22, fire = true },
		flash = { style = "blast", size = 2.4, light = 22, life = 0.08, smoke = 4, fire = true },
		impact = { style = "pellet", size = 1.0, knock = 0.9, fire = true },
	},
	W_PLASMA_BEAM = {
		beam = { width = 1.3, helix = 0.7, spin = 26 },
	},
	W_RAILGUN = {
		tracer = { style = "rail", width = 0.75, stars = true },
		impact = { style = "rail", size = 1.6, knock = 1.4 },
	},
}

local cache = {}

function Feel.get(weapon: string, evolved: boolean)
	local key = weapon .. (if evolved then "+" else "")
	local hit = cache[key]
	if hit then
		return hit
	end
	local base = PROFILES[weapon] or PROFILES.W_ARC_RIFLE
	local out = table.clone(base)
	if evolved and EVOLVED[weapon] then
		for k, v in EVOLVED[weapon] do
			out[k] = v
		end
	end
	out.id = weapon
	out.evolved = evolved
	cache[key] = out
	return out
end

return Feel
