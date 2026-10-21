--!nonstrict
-- Detailed part-built 3D models for weapons (all 4 + evolved forms) and creature previews.
-- Specs are pure data ({shape, size, cf, color, mat, name}) so they can be rendered offline
-- (tools/render_models.py) and instantiated in-game (character gear, UI viewports).
-- Weapon space: grip at origin, barrel toward -Z, up = +Y. Muzzle spec is named "Muzzle".

local Creatures = require(script.Parent.Creatures)

local rgb = Color3.fromRGB
local M = Enum.Material
local P = CFrame.new
local A = CFrame.Angles
local ALONG_Z = A(0, math.pi / 2, 0) -- cylinder axis (X) -> Z
local ALONG_Y = A(0, 0, math.pi / 2) -- cylinder axis (X) -> Y

local Models = {}

local GUN = rgb(46, 54, 66)
local GUN2 = rgb(86, 96, 112)
local STEEL = rgb(120, 128, 140)

-- Specs added while `currentGroup` is set belong to a movable sub-assembly (pump, magazine, barrel…),
-- driven in-game by a Motor6D so weapons can animate their mechanisms.
local currentGroup: string? = nil
local function spec(list, shape, size, cf, color, mat, name)
	table.insert(list, { shape = shape, size = size, cf = cf, color = color, mat = mat or M.Metal, name = name, group = currentGroup })
end
local function group(name: string?)
	currentGroup = name
end

local function box(list, size, cf, color, mat, name)
	spec(list, "Block", size, cf, color, mat, name)
end
local function cylZ(list, len, d, cf, color, mat, name)
	spec(list, "Cylinder", Vector3.new(len, d, d), cf * ALONG_Z, color, mat, name)
end
local function cylY(list, len, d, cf, color, mat, name)
	spec(list, "Cylinder", Vector3.new(len, d, d), cf * ALONG_Y, color, mat, name)
end
local function cylX(list, len, d, cf, color, mat, name)
	spec(list, "Cylinder", Vector3.new(len, d, d), cf, color, mat, name)
end
local function ball(list, d, cf, color, mat, name)
	spec(list, "Ball", Vector3.one * d, cf, color, mat, name)
end

local function gripAndStock(s, accent)
	box(s, Vector3.new(0.32, 0.75, 0.38), P(0, -0.2, 0.1) * A(-0.35, 0, 0), GUN, M.SmoothPlastic)
	box(s, Vector3.new(0.36, 0.42, 1.05), P(0, 0.22, 0.95), GUN2)
	box(s, Vector3.new(0.4, 0.66, 0.16), P(0, 0.12, 1.5), GUN, M.SmoothPlastic)
	box(s, Vector3.new(0.38, 0.06, 0.8), P(0, 0.45, 0.95), accent, M.Neon)
	box(s, Vector3.new(0.12, 0.3, 0.42), P(0, -0.05, -0.25), GUN2) -- trigger guard
end

local BUILDERS = {}

BUILDERS.W_ARC_RIFLE = function(evolved)
	local s = {}
	local accent = if evolved then rgb(150, 215, 255) else rgb(84, 238, 255)
	box(s, Vector3.new(0.56, 0.72, 2.3), P(0, 0.35, -0.65), GUN)
	box(s, Vector3.new(0.24, 0.12, 2.1), P(0, 0.77, -0.7), GUN2)
	for k = 0, 6 do
		box(s, Vector3.new(0.28, 0.06, 0.12), P(0, 0.85, -0.05 - k * 0.3), GUN)
	end
	box(s, Vector3.new(0.5, 0.56, 1.5), P(0, 0.33, -2.45), GUN2)
	for k = 0, 2 do
		box(s, Vector3.new(0.52, 0.09, 0.28), P(0, 0.42, -2.0 - k * 0.42), accent, M.Neon)
	end
	cylZ(s, 1.4, 0.22, P(0, 0.4, -3.85), STEEL)
	cylZ(s, 0.38, 0.4, P(0, 0.4, -4.6), GUN)
	cylZ(s, 0.06, 0.42, P(0, 0.4, -4.42), accent, M.Neon)
	-- Arc coils around the handguard (spin up while firing)
	group("coil")
	for k = 0, (if evolved then 2 else 1) do
		cylZ(s, 0.12, 0.78, P(0, 0.33, -2.15 - k * 0.5), if evolved then accent else rgb(200, 120, 60), if evolved then M.Neon else M.Metal)
	end
	group(nil)
	-- Magazine with energy window
	group("mag")
	box(s, Vector3.new(0.34, 0.85, 0.52), P(0, -0.25, -1.0) * A(0.15, 0, 0), GUN)
	box(s, Vector3.new(0.36, 0.3, 0.14), P(0, -0.2, -1.2) * A(0.15, 0, 0), accent, M.Neon)
	group(nil)
	-- Scope
	cylZ(s, 0.9, 0.3, P(0, 1.05, -0.75), GUN)
	cylZ(s, 0.06, 0.32, P(0, 1.05, -1.2), accent, M.Neon)
	box(s, Vector3.new(0.12, 0.22, 0.12), P(0, 0.9, -0.45), GUN2)
	box(s, Vector3.new(0.12, 0.22, 0.12), P(0, 0.9, -1.05), GUN2)
	gripAndStock(s, accent)
	if evolved then
		for _, x in { -0.22, 0.22 } do
			box(s, Vector3.new(0.08, 0.08, 1.0), P(x, 0.62, -4.5) * A(0, -math.sign(x) * 0.12, 0), accent, M.Neon)
		end
		ball(s, 0.42, P(0, 0.4, -5.0), accent, M.Neon)
		cylZ(s, 1.1, 0.36, P(0.38, 0.3, -1.4), GUN2)
		cylZ(s, 0.9, 0.2, P(0.4, 0.3, -1.4), accent, M.Neon)
	end
	box(s, Vector3.new(0.1, 0.1, 0.1), P(0, 0.4, if evolved then -5.25 else -4.85), accent, M.Neon, "Muzzle")
	return s, { grip = Vector3.new(0, -0.22, 0.1), fore = Vector3.new(0, 0.02, -1.5), eject = Vector3.new(0.32, 0.62, -0.55), mag = Vector3.new(0, -0.55, -1.05) }
end

BUILDERS.W_SCATTERGUN = function(evolved)
	local s = {}
	local accent = if evolved then rgb(255, 100, 30) else rgb(255, 150, 60)
	box(s, Vector3.new(0.8, 0.85, 1.7), P(0, 0.35, -0.45), GUN)
	box(s, Vector3.new(0.82, 0.12, 1.2), P(0, 0.65, -0.45), accent, M.Metal)
	for _, x in { -0.21, 0.21 } do
		cylZ(s, 2.5, 0.38, P(x, 0.47, -2.45), if evolved then rgb(120, 40, 20) else STEEL)
		cylZ(s, 0.1, 0.32, P(x, 0.47, -3.7), accent, M.Neon)
	end
	box(s, Vector3.new(0.3, 0.16, 1.9), P(0, 0.76, -2.3), GUN2)
	for k = 0, 3 do
		box(s, Vector3.new(0.34, 0.08, 0.16), P(0, 0.86, -1.6 - k * 0.45), accent, M.Neon)
	end
	group("pump")
	box(s, Vector3.new(0.74, 0.45, 0.95), P(0, 0.05, -2.05), accent, M.Metal)
	for k = 0, 3 do
		box(s, Vector3.new(0.76, 0.47, 0.06), P(0, 0.05, -1.7 - k * 0.22), GUN)
	end
	group(nil)
	cylX(s, 0.55, 0.95, P(0, -0.3, -0.85), GUN2)
	cylX(s, 0.57, 0.5, P(0, -0.3, -0.85), accent, M.Neon)
	gripAndStock(s, accent)
	if evolved then
		for _, x in { -0.55, 0.55 } do
			cylZ(s, 1.3, 0.42, P(x, 0.32, -0.85), rgb(90, 30, 20))
			cylZ(s, 1.32, 0.2, P(x, 0.32, -0.85), accent, M.Neon)
		end
		for k = 0, 2 do
			box(s, Vector3.new(0.2, 0.25, 0.2), P(0, 1.0, -1.7 - k * 0.5), rgb(255, 200, 80), M.Neon)
		end
	end
	box(s, Vector3.new(0.1, 0.1, 0.1), P(0, 0.47, -3.85), accent, M.Neon, "Muzzle")
	return s, { grip = Vector3.new(0, -0.22, 0.1), fore = Vector3.new(0, -0.2, -1.65), eject = Vector3.new(0.44, 0.45, -0.55), mag = Vector3.new(0, -0.15, -1.0) }
end

BUILDERS.W_PLASMA_BEAM = function(evolved)
	local s = {}
	local accent = if evolved then rgb(150, 70, 255) else rgb(196, 110, 255)
	box(s, Vector3.new(0.85, 0.9, 1.9), P(0, 0.35, -0.55), GUN)
	-- crystal chamber with cage
	group("crystal")
	ball(s, 0.8, P(0, 1.05, -0.6), accent, M.Neon)
	group(nil)
	for _, o in { { -0.38, -0.25 }, { 0.38, -0.25 }, { -0.38, -0.95 }, { 0.38, -0.95 } } do
		box(s, Vector3.new(0.08, 0.7, 0.08), P(o[1], 1.0, o[2]), STEEL)
	end
	box(s, Vector3.new(0.86, 0.08, 0.86), P(0, 1.38, -0.6), GUN2)
	-- cooling fins
	for k = 0, 3 do
		for _, x in { -0.46, 0.46 } do
			box(s, Vector3.new(0.06, 0.55, 0.14), P(x, 0.35, -0.1 - k * 0.32), GUN2)
		end
	end
	cylZ(s, 1.9, 0.28, P(0, 0.4, -2.3), STEEL)
	for k, d in { 1.05, 0.85, 0.65 } do
		cylZ(s, 0.12, d, P(0, 0.4, -1.7 - k * 0.45), accent, M.Neon)
		cylZ(s, 0.16, d - 0.25, P(0, 0.4, -1.7 - k * 0.45), GUN)
	end
	cylZ(s, 0.7, 0.62, P(0, 0.35, 0.75), GUN2)
	cylZ(s, 0.5, 0.3, P(0, 0.35, 0.75), accent, M.Neon)
	box(s, Vector3.new(0.32, 0.75, 0.38), P(0, -0.25, 0.05) * A(-0.35, 0, 0), GUN, M.SmoothPlastic)
	box(s, Vector3.new(0.36, 0.38, 0.8), P(0, -0.05, -1.1), GUN2)
	if evolved then
		for k = 1, 3 do
			cylZ(s, 0.08, 0.7 + k * 0.12, P(0, 0.4, -3.1 - k * 0.35), accent, M.Neon)
		end
		ball(s, 0.5, P(0, 0.4, -3.0), rgb(20, 0, 30), M.SmoothPlastic)
	end
	box(s, Vector3.new(0.1, 0.1, 0.1), P(0, 0.4, if evolved then -4.3 - 0.2 else -3.35), accent, M.Neon, "Muzzle")
	return s, { grip = Vector3.new(0, -0.25, 0.05), fore = Vector3.new(0, -0.26, -1.15), eject = Vector3.new(0.5, 0.35, -0.4), mag = Vector3.new(0, 1.05, -0.6) }
end

BUILDERS.W_RAILGUN = function(evolved)
	local s = {}
	local accent = if evolved then rgb(255, 230, 120) else rgb(255, 210, 90)
	local railColor = if evolved then rgb(200, 160, 60) else STEEL
	box(s, Vector3.new(0.85, 0.95, 1.7), P(0, 0.35, -0.3), GUN)
	group("barrel")
	for _, x in { -0.24, 0.24 } do
		box(s, Vector3.new(0.16, 0.34, 3.8), P(x, 0.42, -2.9), railColor)
		box(s, Vector3.new(0.18, 0.1, 3.6), P(x, 0.62, -2.9), GUN)
	end
	box(s, Vector3.new(0.12, 0.12, 3.6), P(0, 0.42, -2.9), accent, M.Neon, "Charge")
	group(nil)
	for k = 0, 3 do
		box(s, Vector3.new(0.7, 0.12, 0.14), P(0, 0.2, -1.6 - k * 0.8), GUN2)
	end
	for k = 0, 2 do
		cylY(s, 0.55, 0.3, P(0, 1.02, 0.1 - k * 0.4), GUN2)
		cylY(s, 0.3, 0.32, P(0, 1.0, 0.1 - k * 0.4), accent, M.Neon)
	end
	cylZ(s, 1.3, 0.3, P(0.48, 0.85, -0.6), GUN)
	cylZ(s, 0.05, 0.32, P(0.48, 0.85, -1.27), accent, M.Neon)
	gripAndStock(s, accent)
	if evolved then
		ball(s, 0.55, P(0, 0.42, -2.6), rgb(255, 250, 200), M.Neon)
		for _, x in { -0.42, 0.42 } do
			box(s, Vector3.new(0.08, 0.08, 1.2), P(x, 0.42, -4.6) * A(0, math.sign(x) * 0.15, 0), accent, M.Neon)
		end
	end
	box(s, Vector3.new(0.1, 0.1, 0.1), P(0, 0.42, -4.85), accent, M.Neon, "Muzzle")
	return s, { grip = Vector3.new(0, -0.22, 0.1), fore = Vector3.new(0, 0.1, -1.55), eject = Vector3.new(0.46, 0.72, -0.3), mag = Vector3.new(0, 1.05, -0.25) }
end

-- Returns specs and hold metadata (gun space: grip = right hand, fore = left hand, eject port, magazine).
function Models.weaponSpec(id: string, evolved: boolean)
	local b = BUILDERS[id] or BUILDERS.W_ARC_RIFLE
	local specs, meta = b(evolved)
	group(nil)
	for _, sp in specs do
		if sp.name == "Muzzle" then
			meta.muzzle = sp.cf.Position
		end
	end
	return specs, meta
end

function Models.creatureSpec(kind: number)
	local specs = Creatures.Blueprints[kind]()
	local out = {}
	for _, sp in specs do
		local cf = sp.cf
		if sp.seg then
			-- curve the tail sideways for a readable preview silhouette
			local p = cf.Position
			cf = P(math.sin(sp.seg * 0.5) * 3.5, p.Y, p.Z) * cf.Rotation
		end
		table.insert(out, {
			shape = if sp.shape == Enum.PartType.Ball then "Ball" elseif sp.shape == Enum.PartType.Cylinder then "Cylinder" else "Block",
			size = sp.size,
			cf = cf,
			color = sp.color,
			mat = sp.mat,
			transparency = sp.transparency,
		})
	end
	return out
end

-- Instantiation --------------------------------------------------------------------------------------
local SHAPES = { Block = Enum.PartType.Block, Ball = Enum.PartType.Ball, Cylinder = Enum.PartType.Cylinder }

-- Unanchored builds weld everything to an invisible Root; grouped specs weld to a per-group root that
-- is attached with a Motor6D named "Motor_<group>" (animate via Motor6D.Transform).
function Models.build(specs, anchored: boolean, scale: number?): Model
	local k = scale or 1
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Anchored = anchored
	root.CFrame = CFrame.identity
	root.Parent = model
	model.PrimaryPart = root
	local groupRoots = {}
	for _, sp in specs do
		local p = Instance.new("Part")
		p.Shape = SHAPES[sp.shape] or Enum.PartType.Block
		p.Size = sp.size * k
		p.CFrame = CFrame.new(sp.cf.Position * k) * sp.cf.Rotation
		p.Color = sp.color
		p.Material = sp.mat or M.SmoothPlastic
		p.Transparency = sp.transparency or 0
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.Anchored = anchored
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if sp.name then
			p.Name = sp.name
		end
		if not anchored then
			local base = root
			if sp.group then
				base = groupRoots[sp.group]
				if not base then
					base = Instance.new("Part")
					base.Name = "Group_" .. sp.group
					base.Size = Vector3.one * 0.2
					base.Transparency = 1
					base.CanCollide = false
					base.CanQuery = false
					base.CanTouch = false
					base.Massless = true
					base.CFrame = CFrame.identity
					base.Parent = model
					local motor = Instance.new("Motor6D")
					motor.Name = "Motor_" .. sp.group
					motor.Part0 = root
					motor.Part1 = base
					motor.Parent = root
					groupRoots[sp.group] = base
				end
			end
			local w = Instance.new("WeldConstraint")
			w.Part0 = base
			w.Part1 = p
			w.Parent = p
		end
		p.Parent = model
	end
	return model
end

function Models.weapon(id: string, evolved: boolean, anchored: boolean?, scale: number?): (Model, any)
	local specs, meta = Models.weaponSpec(id, evolved)
	local m = Models.build(specs, anchored ~= false, scale)
	m.Name = id
	return m, meta
end

function Models.creature(kind: number): Model
	local m = Models.build(Models.creatureSpec(kind), true)
	m.Name = "Creature" .. kind
	return m
end

return Models
