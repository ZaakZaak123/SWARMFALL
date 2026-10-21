--!nonstrict
-- Builds the selected map from shared Maps (replicates to every client). Two themes: industrial
-- "yard" and organic "depths".
-- Night industrial look: dark steel + concrete, cyan engineering neon, orange hazard, red breach vents.
-- Solid geometry lives in Arena.Solid (CanQuery, used by client raycasts); everything else is decor.

local Lighting = game:GetService("Lighting")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local L = nil -- current map def (set by Arena.build)
local Defs = require(Shared:WaitForChild("Defs"))

local rgb = Color3.fromRGB
local M = Enum.Material

local PAL = {
	floor = rgb(30, 38, 48),
	floorAlt = rgb(36, 45, 56),
	seam = rgb(18, 23, 30),
	steel = rgb(52, 62, 74),
	steelDark = rgb(26, 32, 40),
	concrete = rgb(88, 92, 98),
	cyan = rgb(70, 230, 255),
	cyanDim = rgb(30, 120, 140),
	orange = rgb(255, 140, 40),
	hazard = rgb(250, 190, 40),
	red = rgb(255, 50, 60),
	lime = rgb(150, 255, 70),
	containerA = rgb(170, 70, 40),
	containerB = rgb(34, 110, 120),
	containerC = rgb(80, 86, 96),
	containerD = rgb(150, 120, 50),
}

local Arena = {}

local function part(parent: Instance, props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = M.SmoothPlastic
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function solid(parent: Instance, props): Part
	local p = part(parent, props)
	p.CanCollide = true
	p.CanQuery = true
	p.CastShadow = true
	return p
end

local function vcyl(parent, x, y, z, height, diameter, color, material, isSolid)
	local fn = if isSolid then solid else part
	return fn(parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = material or M.SmoothPlastic,
	})
end

local function light(parent, pos: Vector3, color: Color3, range: number, brightness: number)
	local holder = part(parent, { Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = holder
	return l
end

local function hazardStripes(parent, cx, y, cz, length, alongX: boolean, width)
	local n = math.floor(length / 2)
	for i = 0, n - 1 do
		local off = -length / 2 + 1 + i * 2
		part(parent, {
			Size = if alongX then Vector3.new(1, 0.06, width) else Vector3.new(width, 0.06, 1),
			CFrame = CFrame.new(cx + (if alongX then off else 0), y, cz + (if alongX then 0 else off)),
			Color = if i % 2 == 0 then PAL.hazard else PAL.steelDark,
		})
	end
end

-- Obstacles -----------------------------------------------------------------------------------------
local containerColors = { PAL.containerA, PAL.containerB, PAL.containerC, PAL.containerD }
local styleIndex = 0

local BUILD = {}

function BUILD.container(o, solidF, decor)
	styleIndex += 1
	local color = containerColors[(styleIndex - 1) % #containerColors + 1]
	local body = solid(solidF, {
		Name = o.name,
		Size = Vector3.new(o.w, o.h, o.d),
		CFrame = CFrame.new(o.x, o.h / 2, o.z),
		Color = color,
		Material = M.CorrodedMetal,
	})
	body.CastShadow = true
	local long = math.max(o.w, o.d)
	local alongX = o.w >= o.d
	local ribs = math.floor(long / 2.2)
	for i = 1, ribs - 1 do
		local off = -long / 2 + i * long / ribs
		part(decor, {
			Size = if alongX then Vector3.new(0.25, o.h - 0.4, o.d + 0.12) else Vector3.new(o.w + 0.12, o.h - 0.4, 0.25),
			CFrame = CFrame.new(o.x + (if alongX then off else 0), o.h / 2, o.z + (if alongX then 0 else off)),
			Color = color:Lerp(Color3.new(0, 0, 0), 0.35),
			Material = M.Metal,
		})
	end
	-- Top trim + small beacon
	part(decor, { Size = Vector3.new(o.w + 0.2, 0.3, o.d + 0.2), CFrame = CFrame.new(o.x, o.h + 0.15, o.z), Color = PAL.steelDark, Material = M.Metal })
	part(decor, {
		Size = Vector3.new(0.6, 0.4, 0.6),
		CFrame = CFrame.new(o.x + o.w / 2 - 0.8, o.h + 0.5, o.z + o.d / 2 - 0.8),
		Color = PAL.orange,
		Material = M.Neon,
	})
end

function BUILD.crate(o, solidF, decor)
	solid(solidF, {
		Name = o.name,
		Size = Vector3.new(o.w, o.h * 0.55, o.d),
		CFrame = CFrame.new(o.x, o.h * 0.275, o.z),
		Color = rgb(92, 76, 58),
		Material = M.WoodPlanks,
	})
	local top = solid(solidF, {
		Name = o.name .. "Top",
		Size = Vector3.new(o.w * 0.62, o.h * 0.45, o.d * 0.62),
		CFrame = CFrame.new(o.x - o.w * 0.12, o.h * 0.55 + o.h * 0.225, o.z + o.d * 0.1) * CFrame.Angles(0, math.rad(12), 0),
		Color = PAL.steel,
		Material = M.DiamondPlate,
	})
	top.CanCollide = false
	for _, s in { -1, 1 } do
		part(decor, {
			Size = Vector3.new(o.w + 0.1, 0.35, 0.3),
			CFrame = CFrame.new(o.x, o.h * 0.4, o.z + s * o.d * 0.3),
			Color = PAL.hazard,
			Material = M.Metal,
		})
	end
end

function BUILD.barrier(o, solidF, decor)
	solid(solidF, {
		Name = o.name,
		Size = Vector3.new(o.w, o.h, o.d),
		CFrame = CFrame.new(o.x, o.h / 2, o.z),
		Color = PAL.concrete,
		Material = M.Concrete,
	})
	hazardStripes(decor, o.x, o.h + 0.03, o.z, math.max(o.w, o.d), o.w >= o.d, math.min(o.w, o.d) + 0.05)
	part(decor, {
		Size = Vector3.new(o.w + 0.1, 0.25, o.d + 0.1),
		CFrame = CFrame.new(o.x, o.h * 0.35, o.z),
		Color = PAL.cyan,
		Material = M.Neon,
	})
end

function BUILD.railcar(o, solidF, decor)
	solid(solidF, {
		Name = o.name,
		Size = Vector3.new(o.w, o.h - 1, o.d),
		CFrame = CFrame.new(o.x, (o.h - 1) / 2 + 1, o.z),
		Color = rgb(60, 66, 74),
		Material = M.Metal,
	})
	part(decor, { Size = Vector3.new(o.w + 0.1, 0.6, o.d + 0.1), CFrame = CFrame.new(o.x, o.h * 0.6, o.z), Color = PAL.hazard, Material = M.Metal })
	part(decor, { Size = Vector3.new(o.w - 2, 0.2, o.d - 2), CFrame = CFrame.new(o.x, o.h + 0.1, o.z), Color = PAL.steelDark, Material = M.Metal })
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local wheel = part(decor, {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.6, 2, 2),
				CFrame = CFrame.new(o.x + sx * (o.w / 2 - 3), 1, o.z + sz * (o.d / 2 + 0.3)) * CFrame.Angles(0, math.pi / 2, 0),
				Color = PAL.steelDark,
				Material = M.Metal,
			})
			wheel.CastShadow = false
		end
	end
end

function BUILD.tank(o, solidF, decor)
	local r = o.w / 2
	vcyl(solidF, o.x, o.h / 2, o.z, o.h, o.w, rgb(150, 155, 160), M.Metal, true).Name = o.name
	vcyl(decor, o.x, o.h + 0.4, o.z, 0.8, o.w - 1.2, rgb(110, 115, 120), M.Metal)
	vcyl(decor, o.x, o.h * 0.65, o.z, 0.5, o.w + 0.15, PAL.orange, M.Neon)
	vcyl(decor, o.x, o.h * 0.3, o.z, 0.9, o.w + 0.1, PAL.hazard, M.Metal)
	-- Ladder
	for i = 1, math.floor(o.h / 1.2) do
		part(decor, { Size = Vector3.new(1.4, 0.15, 0.15), CFrame = CFrame.new(o.x, i * 1.2, o.z - r - 0.15), Color = PAL.steelDark, Material = M.Metal })
	end
	-- Acid spill decal ring for refinery tanks
	if o.name:find("Refinery") then
		local spill = vcyl(decor, o.x + r * 0.6, 0.03, o.z - r - 2, 0.05, 6, PAL.lime, M.Neon)
		spill.Transparency = 0.55
	end
end

function BUILD.pylon(o, solidF, decor)
	vcyl(solidF, o.x, o.h / 2, o.z, o.h, o.w, PAL.steel, M.Metal, true).Name = o.name
	vcyl(decor, o.x, o.h + 0.6, o.z, 1.2, o.w * 0.6, PAL.cyan, M.Neon)
	for i = 1, 3 do
		vcyl(decor, o.x, i * o.h / 4, o.z, 0.3, o.w + 0.2, PAL.cyanDim, M.Neon)
	end
	light(decor, Vector3.new(o.x, o.h + 2, o.z), PAL.cyan, 22, 1.2)
end

function BUILD.coil(o, solidF, decor, index)
	vcyl(solidF, o.x, o.h / 2, o.z, o.h, o.w, PAL.steelDark, M.Metal, true).Name = o.name
	local model = Instance.new("Model")
	model.Name = "Coil" .. index
	model:SetAttribute("CoilIndex", index)
	model.Parent = decor
	vcyl(model, o.x, 0.6, o.z, 1.2, o.w + 3, PAL.steel, M.DiamondPlate)
	for i = 1, 6 do
		local ring = vcyl(model, o.x, 1.5 + i * 1.35, o.z, 0.45, o.w + 1.4 - i * 0.12, PAL.cyan, M.Neon)
		ring.Name = "Ring"
	end
	local orb = part(model, { Name = "Orb", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.4, CFrame = CFrame.new(o.x, o.h + 1.4, o.z), Color = PAL.cyan, Material = M.Neon })
	local l = Instance.new("PointLight")
	l.Name = "Glow"
	l.Color = PAL.cyan
	l.Range = 18
	l.Brightness = 1.5
	l.Parent = orb
	-- Activation pad ring on the floor
	local pad = vcyl(model, o.x, 0.04, o.z, 0.06, Defs.Coil.Radius * 2, PAL.cyan, M.Neon)
	pad.Name = "Pad"
	pad.Transparency = 0.75
	local inner = vcyl(model, o.x, 0.05, o.z, 0.07, Defs.Coil.Radius * 2 - 0.8, PAL.floor, M.SmoothPlastic)
	inner.Name = "PadInner"
end

function BUILD.reactor(o, solidF, decor)
	local r = o.w / 2
	vcyl(solidF, o.x, o.h / 2, o.z, o.h, o.w, PAL.steelDark, M.Metal, true).Name = o.name
	local model = Instance.new("Model")
	model.Name = "Reactor"
	model.Parent = decor
	-- Glowing core visible through ribs
	local core = vcyl(model, o.x, o.h / 2 + 1, o.z, o.h + 2, o.w - 2.5, rgb(40, 170, 200), M.Neon)
	core.Name = "Core"
	core.Transparency = 0.35
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		part(model, {
			Name = "Rib",
			Size = Vector3.new(1.2, o.h + 1, 1.2),
			CFrame = CFrame.new(o.x + math.cos(a) * r, o.h / 2 + 0.5, o.z + math.sin(a) * r),
			Color = PAL.steel,
			Material = M.Metal,
		})
	end
	vcyl(model, o.x, o.h + 1.5, o.z, 1, o.w + 2, PAL.steel, M.Metal)
	vcyl(model, o.x, 1, o.z, 2, o.w + 4, PAL.steel, M.DiamondPlate)
	-- Floating rings (animated client-side)
	for i = 1, 3 do
		local ring = vcyl(model, o.x, o.h + 3 + i * 2.2, o.z, 0.4, o.w + 6 - i * 2, PAL.cyan, M.Neon)
		ring.Name = "HaloRing" .. i
		ring.Color = rgb(40, 170, 200)
		ring.Transparency = 0.45
	end
	-- Sky beam
	local beam = vcyl(model, o.x, o.h + 150, o.z, 300, 3, PAL.cyan, M.Neon)
	beam.Name = "SkyBeam"
	beam.Transparency = 0.82
	light(model, Vector3.new(o.x, o.h + 4, o.z), PAL.cyan, 40, 2.4)
	-- Floor halo
	for i, size in { 34, 30, 22 } do
		local ring = vcyl(decor, o.x, 0.02 + i * 0.005, o.z, 0.04, size, if i == 2 then PAL.floor else PAL.cyanDim, if i == 2 then M.SmoothPlastic else M.Neon)
		ring.Transparency = if i == 2 then 0 else 0.7
	end
end

-- Arena shell ---------------------------------------------------------------------------------------
local function buildFloor(root)
	local floor = Instance.new("Folder")
	floor.Name = "Floor"
	floor.Parent = root
	local hx, hz = L.halfX, L.halfZ
	solid(floor, {
		Name = "ArenaFloor",
		Size = Vector3.new(hx * 2, 2, hz * 2),
		CFrame = CFrame.new(0, -1, 0),
		Color = PAL.floor,
		Material = M.Concrete,
	}).CastShadow = false
	-- Outer ground so the camera never sees the void
	part(floor, { Name = "Outer", Size = Vector3.new(2048, 2, 2048), CFrame = CFrame.new(0, -1.6, 0), Color = rgb(14, 17, 22), Material = M.Ground })
	-- Panel seams
	for x = -hx + 20, hx - 20, 20 do
		part(floor, { Size = Vector3.new(0.2, 0.04, hz * 2 - 8), CFrame = CFrame.new(x, 0.02, 0), Color = PAL.seam })
	end
	for z = -hz + 20, hz - 20, 20 do
		part(floor, { Size = Vector3.new(hx * 2 - 8, 0.04, 0.2), CFrame = CFrame.new(0, 0.02, z), Color = PAL.seam })
	end
	-- Alternating panel tint for a checker of large slabs
	for x = -hx + 10, hx - 10, 40 do
		for z = -hz + 10, hz - 10, 40 do
			part(floor, { Size = Vector3.new(19.6, 0.03, 19.6), CFrame = CFrame.new(x, 0.015, z), Color = PAL.floorAlt, Material = M.Concrete })
		end
	end
	-- North conduit grating + cable runs
	part(floor, { Size = Vector3.new(84, 0.05, 86), CFrame = CFrame.new(0, 0.03, 88), Color = rgb(44, 52, 62), Material = M.DiamondPlate })
	for _, x in { -40, 40 } do
		part(floor, { Size = Vector3.new(1, 0.2, 86), CFrame = CFrame.new(x, 0.1, 88), Color = PAL.cyan, Material = M.Neon }).Transparency = 0.2
	end
	-- East rails
	for _, z in { -6, 6 } do
		part(floor, { Size = Vector3.new(124, 0.35, 0.8), CFrame = CFrame.new(108, 0.18, z), Color = rgb(150, 160, 170), Material = M.Metal })
	end
	for x = 50, 168, 6 do
		part(floor, { Size = Vector3.new(1.4, 0.15, 17), CFrame = CFrame.new(x, 0.07, 0), Color = rgb(40, 34, 30), Material = M.Wood })
	end
	-- South refinery: hazard border
	hazardStripes(floor, 0, 0.04, -46, 104, true, 1.2)
	-- West hangar: painted bay lines
	for _, z in { -46, 0, 46 } do
		part(floor, { Size = Vector3.new(100, 0.04, 0.6), CFrame = CFrame.new(-100, 0.03, z), Color = PAL.hazard })
	end
	-- Two loop rings (readable routes)
	for _, span in { 46, 140 } do
		for _, s in { -1, 1 } do
			part(floor, { Size = Vector3.new(span * 2, 0.04, 0.5), CFrame = CFrame.new(0, 0.035, s * span), Color = PAL.cyanDim, Material = M.Neon }).Transparency = 0.55
			part(floor, { Size = Vector3.new(0.5, 0.04, span * 2), CFrame = CFrame.new(s * span, 0.035, 0), Color = PAL.cyanDim, Material = M.Neon }).Transparency = 0.55
		end
	end
end

local function buildWalls(root, solidF)
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = root
	local hx, hz, t = L.halfX, L.halfZ, L.wall
	local H = 12
	local sides = {
		{ "WestWall", -hx + t / 2, 0, t, hz * 2 },
		{ "EastWall", hx - t / 2, 0, t, hz * 2 },
		{ "NorthWall", 0, hz - t / 2, hx * 2, t },
		{ "SouthWall", 0, -hz + t / 2, hx * 2, t },
	}
	for _, s in sides do
		local w = solid(solidF, { Name = s[1], Size = Vector3.new(s[4], H, s[5]), CFrame = CFrame.new(s[2], H / 2, s[3]), Color = PAL.steelDark, Material = M.Metal })
		w.CastShadow = false
		part(walls, { Size = Vector3.new(s[4] + 0.2, 0.5, s[5] + 0.2), CFrame = CFrame.new(s[2], H - 1.5, s[3]), Color = PAL.cyan, Material = M.Neon }).Transparency = 0.1
		part(walls, { Size = Vector3.new(s[4] + 0.3, 1, s[5] + 0.3), CFrame = CFrame.new(s[2], H + 0.5, s[3]), Color = PAL.steel, Material = M.Metal })
		part(walls, { Size = Vector3.new(s[4] + 0.15, 1.2, s[5] + 0.15), CFrame = CFrame.new(s[2], 0.6, s[3]), Color = PAL.hazard, Material = M.Metal })
	end
	-- Wall buttresses
	for x = -hx + 20, hx - 20, 30 do
		for _, z in { -hz + t + 0.8, hz - t - 0.8 } do
			part(walls, { Size = Vector3.new(2.5, 13, 1.6), CFrame = CFrame.new(x, 6.5, z), Color = PAL.steel, Material = M.Metal })
		end
	end
	for z = -hz + 20, hz - 20, 30 do
		for _, x in { -hx + t + 0.8, hx - t - 0.8 } do
			part(walls, { Size = Vector3.new(1.6, 13, 2.5), CFrame = CFrame.new(x, 6.5, z), Color = PAL.steel, Material = M.Metal })
		end
	end
	-- Breach vents at every spawn: red-lit torn openings in the wall face
	for name, s in L.spawns do
		local nx, nz = 0, 0
		if math.abs(s.x) > L.halfX - 20 then
			nx = math.sign(s.x)
		end
		if math.abs(s.z) > L.halfZ - 20 then
			nz = math.sign(s.z)
		end
		local wx = if nx ~= 0 then nx * (L.halfX - t - 0.3) else s.x
		local wz = if nz ~= 0 then nz * (L.halfZ - t - 0.3) else s.z
		if nx ~= 0 and nz ~= 0 then
			wx, wz = s.x, nz * (L.halfZ - t - 0.3) -- corner spawns use the north/south wall
			nx = 0
		end
		local alongX = nz ~= 0
		local vent = Instance.new("Model")
		vent.Name = "Breach_" .. name
		vent.Parent = walls
		part(vent, {
			Name = "Glow",
			Size = if alongX then Vector3.new(14, 8, 0.4) else Vector3.new(0.4, 8, 14),
			CFrame = CFrame.new(wx, 4, wz),
			Color = PAL.red,
			Material = M.Neon,
		}).Transparency = 0.25
		for i = -2, 2 do
			part(vent, {
				Size = if alongX then Vector3.new(1.2, 9, 0.8) else Vector3.new(0.8, 9, 1.2),
				CFrame = CFrame.new(wx + (if alongX then i * 3 else 0), 4.5, wz + (if alongX then 0 else i * 3)) * CFrame.Angles(0, 0, if alongX then math.rad(i * 4) else 0),
				Color = PAL.steelDark,
				Material = M.Metal,
			})
		end
		local floorGlow = part(vent, {
			Name = "FloorGlow",
			Size = Vector3.new(16, 0.05, 16),
			CFrame = CFrame.new(s.x, 0.03, s.z),
			Color = PAL.red,
			Material = M.Neon,
		})
		floorGlow.Transparency = 0.85
		light(vent, Vector3.new(wx - nx * 3, 5, wz - nz * 3), PAL.red, 24, 1.6)
	end
end

local function buildSkyline(root)
	local sky = Instance.new("Folder")
	sky.Name = "Skyline"
	sky.Parent = root
	local rng = Random.new(42)
	local towers = 0
	for a = 0, 359, 9 do
		local rad = math.rad(a + rng:NextNumber(-3, 3))
		local dist = rng:NextNumber(240, 340)
		local x, z = math.cos(rad) * dist * 1.1, math.sin(rad) * dist
		local w = rng:NextNumber(14, 34)
		local h = rng:NextNumber(30, 110)
		part(sky, { Size = Vector3.new(w, h, rng:NextNumber(14, 30)), CFrame = CFrame.new(x, h / 2 - 2, z) * CFrame.Angles(0, rad, 0), Color = rgb(18, 22, 29), Material = M.Metal })
		if rng:NextNumber() < 0.6 then
			part(sky, { Size = Vector3.new(1.4, 1.4, 1.4), CFrame = CFrame.new(x, h + 0.5, z), Color = PAL.red, Material = M.Neon })
		end
		if rng:NextNumber() < 0.35 then
			-- lit windows strip
			part(sky, { Size = Vector3.new(w * 0.7, 0.6, 0.2), CFrame = CFrame.new(x, h * 0.6, z) * CFrame.Angles(0, rad + math.pi / 2, 0), Color = PAL.cyanDim, Material = M.Neon })
		end
		towers += 1
	end
	-- Smoke stacks
	for i = 1, 5 do
		local a = math.rad(i * 72 + 20)
		vcyl(sky, math.cos(a) * 260, 60, math.sin(a) * 230, 120, 12, rgb(24, 28, 34), M.Concrete)
		vcyl(sky, math.cos(a) * 260, 118, math.sin(a) * 230, 2, 12.6, PAL.red, M.Neon)
	end
end

local function buildProps(root)
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = root
	-- Lamp posts along the loop
	local lamps = { { 46, 46 }, { -46, 46 }, { 46, -46 }, { -46, -46 }, { 140, 100 }, { -140, 100 }, { 140, -100 }, { -140, -100 } }
	for _, l in lamps do
		vcyl(props, l[1], 6, l[2], 12, 0.8, PAL.steel, M.Metal)
		part(props, { Size = Vector3.new(3, 0.5, 1.2), CFrame = CFrame.new(l[1], 12, l[2]), Color = PAL.steelDark, Material = M.Metal })
		part(props, { Size = Vector3.new(2.6, 0.2, 0.9), CFrame = CFrame.new(l[1], 11.7, l[2]), Color = rgb(255, 230, 190), Material = M.Neon })
		light(props, Vector3.new(l[1], 11, l[2]), rgb(255, 220, 180), 30, 0.9)
	end
	-- Cable bundles hanging between conduit containers (decor, high and non-colliding)
	for _, z in { 66, 110 } do
		part(props, { Size = Vector3.new(52, 0.5, 0.5), CFrame = CFrame.new(0, 7.5, z + 5), Color = rgb(20, 20, 24), Material = M.Rubber })
		part(props, { Size = Vector3.new(52, 0.3, 0.3), CFrame = CFrame.new(0, 7.2, z - 4), Color = PAL.cyan, Material = M.Neon })
	end
	-- Hive sites: scorched organic stains so players learn the locations
	for _, h in L.hiveSites do
		local stain = vcyl(props, h.x, 0.025, h.z, 0.05, 14, rgb(60, 30, 70), M.Slate)
		stain.Transparency = 0.2
	end
	-- Corner pipe runs on walls
	for _, c in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		for k = 0, 2 do
			part(props, {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(60, 1.2, 1.2),
				CFrame = CFrame.new(c[1] * (L.halfX - 40), 3 + k * 1.6, c[2] * (L.halfZ - L.wall - 1)),
				Color = if k == 1 then PAL.orange else PAL.steel,
				Material = M.Metal,
			})
		end
	end
end

-- Depths theme ----------------------------------------------------------------------------------------
local DP = {
	floor = rgb(30, 22, 36),
	floorAlt = rgb(38, 27, 44),
	rock = rgb(44, 34, 50),
	rockDark = rgb(24, 18, 28),
	flesh = rgb(110, 46, 90),
	fleshDark = rgb(64, 24, 54),
	moss = rgb(150, 255, 90),
	vein = rgb(255, 70, 190),
	metal = rgb(70, 74, 82),
}

local function taper(parent, x, z, baseD, h, segments, color, material, solidF)
	if solidF then
		vcyl(solidF, x, h / 2, z, h, baseD * 0.85, color, material, true).Transparency = 1
	end
	for i = 0, segments - 1 do
		local k = i / segments
		local d = baseD * (1 - k * 0.75)
		local seg = h / segments
		local c = vcyl(parent, x + math.sin(i * 1.7) * 0.4, seg * (i + 0.5), z + math.cos(i * 1.3) * 0.4, seg + 0.2, d, color:Lerp(Color3.new(0, 0, 0), k * 0.25), material)
		c.CastShadow = i == 0
	end
end

function BUILD.spire(o, solidF, decor)
	taper(decor, o.x, o.z, o.w, o.h, 6, DP.rock, M.Rock, solidF)
	local heart = part(decor, { Name = "Heart", Shape = Enum.PartType.Ball, Size = Vector3.one * 5, CFrame = CFrame.new(o.x, o.h + 2.5, o.z), Color = DP.vein, Material = M.Neon })
	heart.Transparency = 0.1
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		part(decor, {
			Size = Vector3.new(0.4, o.h * 0.8, 0.4),
			CFrame = CFrame.new(o.x + math.cos(a) * o.w * 0.42, o.h * 0.42, o.z + math.sin(a) * o.w * 0.42) * CFrame.Angles(math.sin(a) * 0.12, 0, math.cos(a) * 0.12),
			Color = DP.vein,
			Material = M.Neon,
		})
	end
	light(decor, Vector3.new(o.x, o.h + 4, o.z), DP.vein, 46, 2.2)
	for i, size in { 30, 26 } do
		local ring = vcyl(decor, o.x, 0.03 + i * 0.005, o.z, 0.04, size, if i == 1 then DP.vein else DP.floor, if i == 1 then M.Neon else M.Slate)
		ring.Transparency = if i == 1 then 0.5 else 0
	end
end

function BUILD.stalagmite(o, solidF, decor)
	taper(decor, o.x, o.z, o.w, o.h, 5, DP.rock, M.Rock, solidF)
	part(decor, { Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = CFrame.new(o.x, o.h + 0.4, o.z), Color = DP.moss, Material = M.Neon })
	local glow = vcyl(decor, o.x, 0.04, o.z, 0.05, o.w + 6, DP.moss, M.Neon)
	glow.Transparency = 0.8
end

function BUILD.mound(o, solidF, decor)
	vcyl(solidF, o.x, o.h / 2, o.z, o.h, o.w, DP.flesh, M.Slate, true).Transparency = 1
	local main = part(decor, { Shape = Enum.PartType.Ball, Size = Vector3.one * o.w * 1.15, CFrame = CFrame.new(o.x, o.h - o.w * 0.5, o.z), Color = DP.fleshDark, Material = M.Slate })
	main.CastShadow = true
	part(decor, { Shape = Enum.PartType.Ball, Size = Vector3.one * o.w * 0.7, CFrame = CFrame.new(o.x + o.w * 0.15, o.h - o.w * 0.15, o.z - o.w * 0.1), Color = DP.flesh, Material = M.SmoothPlastic })
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2 + o.x
		part(decor, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (1 + (i % 3) * 0.5),
			CFrame = CFrame.new(o.x + math.cos(a) * o.w * 0.42, o.h * 0.55 + (i % 2), o.z + math.sin(a) * o.w * 0.42),
			Color = if i % 2 == 0 then DP.moss else DP.vein,
			Material = M.Neon,
		})
	end
end

function BUILD.rig(o, solidF, decor)
	solid(solidF, { Name = o.name, Size = Vector3.new(o.w, 2.5, o.d), CFrame = CFrame.new(o.x, 1.25, o.z), Color = DP.metal, Material = M.CorrodedMetal })
	local col = solid(solidF, { Name = o.name .. "Mast", Size = Vector3.new(o.w * 0.6, o.h, o.d * 0.6), CFrame = CFrame.new(o.x, o.h / 2, o.z), Color = DP.metal, Material = M.CorrodedMetal })
	col.Transparency = 1
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(decor, {
				Size = Vector3.new(0.5, o.h + 6, 0.5),
				CFrame = CFrame.new(o.x + sx * o.w * 0.25, (o.h + 6) / 2, o.z + sz * o.d * 0.25) * CFrame.Angles(sz * 0.08, 0, -sx * 0.08),
				Color = rgb(150, 110, 40),
				Material = M.Metal,
			})
		end
	end
	part(decor, { Size = Vector3.new(o.w * 0.7, 0.6, o.d * 0.7), CFrame = CFrame.new(o.x, o.h + 6, o.z), Color = rgb(150, 110, 40), Material = M.Metal })
	vcyl(decor, o.x, o.h * 0.5, o.z, o.h + 4, 1.2, rgb(90, 90, 96), M.Metal)
	hazardStripes(decor, o.x, 2.55, o.z, math.max(o.w, o.d), o.w >= o.d, math.min(o.w, o.d))
	part(decor, { Size = Vector3.new(0.8, 0.8, 0.8), CFrame = CFrame.new(o.x, o.h + 6.8, o.z), Color = rgb(255, 60, 50), Material = M.Neon })
end

local function buildDepths(root, solidF)
	local floor = Instance.new("Folder")
	floor.Name = "Floor"
	floor.Parent = root
	local hx, hz, t = L.halfX, L.halfZ, L.wall
	solid(floor, { Name = "ArenaFloor", Size = Vector3.new(hx * 2, 2, hz * 2), CFrame = CFrame.new(0, -1, 0), Color = DP.floor, Material = M.Slate }).CastShadow = false
	part(floor, { Name = "Outer", Size = Vector3.new(2048, 2, 2048), CFrame = CFrame.new(0, -1.6, 0), Color = rgb(12, 8, 14), Material = M.Ground })
	local rng = Random.new(7)
	for _ = 1, 26 do
		local x, z = rng:NextNumber(-hx + 10, hx - 10), rng:NextNumber(-hz + 10, hz - 10)
		vcyl(floor, x, 0.02, z, 0.03, rng:NextNumber(12, 30), DP.floorAlt, M.Slate)
	end
	for _ = 1, 34 do
		local x, z = rng:NextNumber(-hx + 8, hx - 8), rng:NextNumber(-hz + 8, hz - 8)
		local m = vcyl(floor, x, 0.04, z, 0.03, rng:NextNumber(3, 8), DP.moss, M.Neon)
		m.Transparency = 0.75
	end
	for _ = 1, 22 do
		local x, z = rng:NextNumber(-hx + 10, hx - 10), rng:NextNumber(-hz + 10, hz - 10)
		local len = rng:NextNumber(10, 28)
		part(floor, { Size = Vector3.new(0.35, 0.04, len), CFrame = CFrame.new(x, 0.05, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Color = DP.vein, Material = M.Neon }).Transparency = 0.45
	end
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = root
	local H = 16
	for _, sd in { { -hx + t / 2, 0, t, hz * 2 }, { hx - t / 2, 0, t, hz * 2 }, { 0, hz - t / 2, hx * 2, t }, { 0, -hz + t / 2, hx * 2, t } } do
		solid(solidF, { Size = Vector3.new(sd[3], H, sd[4]), CFrame = CFrame.new(sd[1], H / 2, sd[2]), Color = DP.rockDark, Material = M.Rock }).CastShadow = false
	end
	local perimeter = 4 * (hx + hz)
	for i = 0, math.floor(perimeter / 9) do
		local d = i * 9
		local x, z
		if d < hx * 2 then
			x, z = -hx + d, hz
		elseif d < hx * 2 + hz * 2 then
			x, z = hx, hz - (d - hx * 2)
		elseif d < hx * 4 + hz * 2 then
			x, z = hx - (d - hx * 2 - hz * 2), -hz
		else
			x, z = -hx, -hz + (d - hx * 4 - hz * 2)
		end
		local size = rng:NextNumber(10, 20)
		part(walls, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			CFrame = CFrame.new(x + math.sign(x) * size * 0.25, size * 0.3, z + math.sign(z) * size * 0.25),
			Color = DP.rock:Lerp(DP.rockDark, rng:NextNumber()),
			Material = M.Rock,
		})
	end
	for name, sp in L.spawns do
		local hole = Instance.new("Model")
		hole.Name = "Breach_" .. name
		hole.Parent = walls
		vcyl(hole, sp.x, 0.06, sp.z, 0.06, 14, rgb(6, 4, 8), M.SmoothPlastic)
		local rim = vcyl(hole, sp.x, 0.05, sp.z, 0.05, 16, DP.moss, M.Neon)
		rim.Name = "FloorGlow"
		rim.Transparency = 0.5
		for k = 1, 5 do
			local a = k / 5 * math.pi * 2
			part(hole, { Shape = Enum.PartType.Ball, Size = Vector3.one * 2.5, CFrame = CFrame.new(sp.x + math.cos(a) * 8, 0.4, sp.z + math.sin(a) * 8), Color = DP.rock, Material = M.Rock })
		end
		light(hole, Vector3.new(sp.x, 3, sp.z), DP.moss, 20, 1.2)
	end
	for _, h in L.hiveSites do
		vcyl(floor, h.x, 0.03, h.z, 0.05, 14, rgb(70, 30, 70), M.Slate).Transparency = 0.1
	end
	local sky = Instance.new("Folder")
	sky.Name = "Skyline"
	sky.Parent = root
	for a = 0, 359, 10 do
		local r = math.rad(a + rng:NextNumber(-4, 4))
		local dist = rng:NextNumber(200, 280)
		local x, z = math.cos(r) * dist, math.sin(r) * dist * 0.95
		taper(sky, x, z, rng:NextNumber(20, 40), rng:NextNumber(40, 120), 4, DP.rockDark, M.Rock)
		if rng:NextNumber() < 0.3 then
			part(sky, { Shape = Enum.PartType.Ball, Size = Vector3.one * 3, CFrame = CFrame.new(x, rng:NextNumber(20, 60), z), Color = DP.moss, Material = M.Neon })
		end
	end
end

function Arena.lighting(theme: string)
	local depths = theme == "depths"
	Lighting.ClockTime = if depths then 0 else 0.4
	Lighting.Brightness = if depths then 1.2 else 1.6
	Lighting.Ambient = if depths then rgb(70, 50, 84) else rgb(66, 76, 98)
	Lighting.OutdoorAmbient = if depths then rgb(96, 72, 116) else rgb(112, 124, 150)
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.7
	Lighting.ExposureCompensation = if depths then 0.4 else 0.25
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.GeographicLatitude = 30
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
			c:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = if depths then 0.42 else 0.3
	atmosphere.Offset = 0.08
	atmosphere.Color = if depths then rgb(90, 50, 110) else rgb(70, 100, 130)
	atmosphere.Decay = if depths then rgb(30, 60, 30) else rgb(40, 28, 60)
	atmosphere.Glare = 0.15
	atmosphere.Haze = if depths then 2.2 else 1.4
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.StarCount = if depths then 0 else 4000
	sky.CelestialBodiesShown = not depths
	sky.MoonAngularSize = 14
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	bloom.Intensity = if depths then 1 else 0.85
	bloom.Size = 30
	bloom.Threshold = 1.2
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Brightness = 0.02
	cc.Contrast = 0.14
	cc.Saturation = 0.12
	cc.TintColor = if depths then rgb(245, 228, 255) else rgb(232, 244, 255)
	cc.Parent = Lighting
end

function Arena.build(map)
	L = map
	local old = workspace:FindFirstChild("Arena")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = "Arena"
	root:SetAttribute("Map", map.id)
	local solidF = Instance.new("Folder")
	solidF.Name = "Solid"
	solidF.Parent = root
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = root
	if map.theme == "depths" then
		buildDepths(root, solidF)
	else
		buildFloor(root)
		buildWalls(root, solidF)
	end
	local coilIndex = 0
	for _, o in L.obstacles do
		local builder = BUILD[o.style]
		if o.style == "coil" then
			coilIndex += 1
			builder(o, solidF, decor, coilIndex)
		elseif builder then
			builder(o, solidF, decor)
		end
	end
	if map.theme ~= "depths" then
		buildProps(root)
		buildSkyline(root)
	end
	Arena.lighting(map.theme)
	root.Parent = workspace
	return root
end

return Arena
