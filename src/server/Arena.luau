--!nonstrict
-- World builder: the drill's funnel (DD-030, art direction DD-091). Replicates to every client.
--
-- A crater the drill opened in a buried city, at a golden dusk: layered earth walls with a forest on
-- top, the old streets in the floor, the dead city on the horizon. The world is dust, concrete, rust and
-- green; ember is the swarm, pink is xenite, cyan is our machines. Landmarks give a compass without a
-- minimap: the metro breach the swarm pours out of to the north, the drill station's camp to the south,
-- xenite in the rubble east, an overgrown square west, the drill in the middle (ArenaScene).
--
-- Solid geometry: invisible parts that match the shared nav geometry exactly (Arena.Solid, CanQuery —
-- client shot rays and camera collision). Everything visible is decor: terrain, ruins, trees, the rig.
-- Tall decor that can hide the hero is tagged `Fade` (the client fades it when it blocks the view).

local Lighting = game:GetService("Lighting")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local ArtLoader = require(script.Parent.ArtLoader)
local ArenaArt = require(script.Parent.ArenaArt)
local ArenaScene = require(script.Parent.ArenaScene)

local rgb = Color3.fromRGB
local M = Enum.Material
local terrain = workspace.Terrain

local PAL = {
	bone = rgb(222, 208, 186),
	boneDark = rgb(150, 132, 120),
	plum = rgb(42, 32, 58),
	basalt = rgb(30, 24, 44),
	teal = rgb(60, 245, 210),
	tealDeep = rgb(20, 120, 120),
	pink = rgb(255, 70, 190),
	pinkDeep = rgb(150, 30, 120),
	violet = rgb(150, 90, 255),
	ember = rgb(255, 120, 50),
	hull = rgb(214, 218, 226),
	hullDark = rgb(52, 56, 66),
	stripe = rgb(255, 150, 40),
	stem = rgb(205, 190, 230),
	cap = rgb(130, 64, 196),
}

local Arena = {}
Arena.onClear = nil :: (() -> ())? -- set by Main: rebuilds the shelter ground right after the terrain clear

-- Map coordinates (east = +X) -> world (east renders on screen-right, so X is mirrored like Maps).
local function W(x: number, y: number, z: number): Vector3
	return Vector3.new(-x, y, z)
end

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

local function ball(parent, pos: Vector3, d: number, color: Color3, material, props)
	local p = part(parent, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * d,
		CFrame = CFrame.new(pos),
		Color = color,
		Material = material or M.SmoothPlastic,
	})
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return p
end

-- Ellipsoid (a Ball part is always a sphere; a block with a sphere mesh can be squashed).
local function ellipsoid(parent, cf: CFrame, size: Vector3, color: Color3, material, props)
	local p = part(parent, { Size = size, CFrame = cf, Color = color, Material = material or M.SmoothPlastic })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return p
end

-- Cylinder between two points.
local function rod(parent, a: Vector3, b: Vector3, d: number, color: Color3, material, props)
	local len = (b - a).Magnitude
	local axis = (b - a).Unit
	-- any vector not parallel to the axis builds the frame (a vertical lookAt is degenerate)
	local ref = if math.abs(axis.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local side = axis:Cross(ref).Unit
	local p = part(parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(len, d, d),
		CFrame = CFrame.fromMatrix((a + b) / 2, axis, side:Cross(axis), side),
		Color = color,
		Material = material or M.SmoothPlastic,
	})
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return p
end

-- Flat disc lying on the floor.
local function disc(parent, pos: Vector3, d: number, thick: number, color: Color3, material, transparency)
	return part(parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thick, d, d),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = material or M.SmoothPlastic,
		Transparency = transparency or 0,
	})
end

local function light(parent, pos: Vector3, color: Color3, range: number, brightness: number, shadows: boolean?)
	local holder =
		part(parent, { Name = "Light", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = shadows == true
	l.Parent = holder
	return l
end

local function fade(p: Instance)
	p:SetAttribute("Fade", true)
	return p
end

-- Spores: soft glowing motes drifting up from a part.
local function spores(parent: BasePart, color: Color3, rate: number, size: number?, speed: number?)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Spores"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, size or 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(4, 7)
	e.Rate = rate
	e.Speed = NumberRange.new(speed or 1, (speed or 1) * 2)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Acceleration = Vector3.new(0, 0.6, 0)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Parent = parent
	return e
end

-- Deterministic noise for decor placement (same crater on every server).
local seed = 7
local function rnd(a: number?, b: number?): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	local r = seed / 2147483648
	if a and b then
		return a + (b - a) * r
	end
	return r
end

-- Walkable boundary of the crater at angle `a` (radians, world): rectangle clipped by the corner cliffs.
local function boundary(map, a: number): number
	local dx, dz = math.cos(a), math.sin(a)
	local lim = map.halfX - map.wall
	local r = math.min(lim / math.max(1e-4, math.abs(dx)), lim / math.max(1e-4, math.abs(dz)))
	for _, o in map.obstacles do
		if o.style == "cliff" then
			local proj = dx * o.x + dz * o.z
			local c2 = o.x * o.x + o.z * o.z
			local rr = o.w / 2
			local disc_ = proj * proj - (c2 - rr * rr)
			if proj > 0 and disc_ >= 0 then
				r = math.min(r, proj - math.sqrt(disc_))
			end
		end
	end
	return r
end

-- Obstacles avoided by scattered decor.
local function clearOf(map, x: number, z: number, pad: number): boolean
	if math.abs(x) > map.halfX - map.wall - pad or math.abs(z) > map.halfZ - map.wall - pad then
		return false
	end
	for _, o in map.obstacles do
		local dx, dz = x - o.x, z - o.z
		if o.shape == "round" then
			local rr = o.w / 2 + pad
			if dx * dx + dz * dz < rr * rr then
				return false
			end
		elseif math.abs(dx) < o.w / 2 + pad and math.abs(dz) < o.d / 2 + pad then
			return false
		end
	end
	return true
end

-- Terrain -------------------------------------------------------------------------------------------------
-- DD-091: a crater the drill opened in a buried city. The floor stays one calm surface for the fight
-- (DD-047), with the old streets showing through it; the walls are layered earth with grass and forest
-- on top; hills and the dead city's towers close every view (no bare plane past the rim).
local function paintTerrain(map)
	terrain:Clear()
	-- the clear wipes the shelter's ground too: put it back before the first yield, or anyone standing
	-- at home falls through while the crater is painted
	if Arena.onClear then
		Arena.onClear()
	end
	-- Ground/Grass carry generated variants (Art.Materials): tint only shades. LeafyGrass, Concrete and
	-- Pavement are the grove's (Home sets their colours): the crater's green is its own Grass, an olive
	-- moss, and its concrete is the grove's as it is. Basalt and Slate carry the retired alien variants:
	-- not used.
	terrain:SetMaterialColor(M.Ground, rgb(190, 178, 162)) -- ash and dust
	terrain:SetMaterialColor(M.Mud, rgb(96, 80, 66))
	terrain:SetMaterialColor(M.Grass, rgb(168, 170, 110))
	terrain:SetMaterialColor(M.Sandstone, rgb(164, 128, 94))
	terrain:SetMaterialColor(M.Rock, rgb(116, 106, 96))
	terrain:SetMaterialColor(M.Asphalt, rgb(82, 78, 76))
	terrain:SetMaterialColor(M.Salt, rgb(110, 104, 100))
	pcall(function()
		-- animated grass blades shimmer under a top-down camera
		terrain.Decoration = false
	end)
	terrain.WaterColor = rgb(70, 96, 92)
	-- Bedrock floor, surface exactly at Y = 0. Smooth terrain draws a voxel's surface at
	-- centre + 4 * (occupancy - 0.5): a block filled up to 0 makes the -4..0 voxel full and the surface
	-- appears at +2, sinking every creature, pickup and prop by 2 studs. Filling to -2 leaves that voxel
	-- half full, which puts the surface on 0 (measured with a downward ray). (1200 wide: the hills past
	-- the rim stand on it; the grove's ground starts at z 1120.)
	terrain:FillBlock(CFrame.new(0, -7, 0), Vector3.new(1200, 10, 1200), M.Ground)
	task.wait()
	-- Floor materials: rewrites only the top voxel layer's material (fills would change occupancy and
	-- raise bumps), cell by cell over a rectangle; `pick(x, z)` returns the material or nil.
	local function paint(x0: number, z0: number, x1: number, z1: number, pick)
		local region = Region3.new(Vector3.new(x0, -4, z0), Vector3.new(x1, 0, z1)):ExpandToGrid(4)
		local mats, occs = terrain:ReadVoxels(region, 4)
		local size = mats.Size
		local corner = region.CFrame.Position - region.Size / 2
		for i = 1, size.X do
			for k = 1, size.Z do
				local px, pz = corner.X + (i - 0.5) * 4, corner.Z + (k - 0.5) * 4
				local mat = pick(px, pz)
				if mat then
					for j = 1, size.Y do
						if occs[i][j][k] > 0 then
							mats[i][j][k] = mat
						end
					end
				end
			end
		end
		terrain:WriteVoxels(region, 4, mats, occs)
	end
	local lim = map.halfX - map.wall
	paint(-lim - 4, -lim - 4, lim + 4, lim + 4, function(x, z)
		local r = math.sqrt(x * x + z * z)
		local edge = boundary(map, math.atan2(z, x))
		local n = math.noise(x / 13, z / 13, 3.7)
		-- the breach's apron: trampled dark earth where the swarm pours out
		if math.abs(x) < 20 + n * 6 and z > 118 + n * 6 then
			return M.Mud
		end
		-- grass creeping out from the foot of the wall
		if r > edge - 6 - n * 5 then
			return if n > -0.25 then M.Grass else M.Mud
		end
		-- the old square's lawn (west)
		local pk = ArenaScene.Park
		local dp = math.sqrt((x - pk.x) ^ 2 + (z - pk.z) ^ 2)
		if dp < pk.r + n * 10 then
			return if n > -0.35 then M.Grass else M.Ground
		end
		-- the old streets: asphalt with broken edges, a pavement strip either side, gaps under the dust
		for i, road in ArenaScene.Roads do
			local d, t = ArenaScene.roadDistance(road, x, z)
			if not ArenaScene.roadGap(i, t) then
				local ragged = math.noise(x / 6, z / 6, i) * 2.4
				if d < road.w / 2 + ragged then
					return M.Asphalt
				end
			end
		end
		return nil
	end)
	task.wait()
	-- The walls: earth columns stepping up from the walkable boundary (front row low, back rows tall):
	-- dark soil at the foot, layered ochre sandstone above it (its own texture carries the strata: bands
	-- of other materials broke into blotches where the columns bulge), grass along the top.
	local bands = {
		{ 0, 5, M.Mud },
		{ 5, 200, M.Sandstone },
	}
	local steps = 150
	for i = 0, steps - 1 do
		local a = i / steps * math.pi * 2 + rnd(-0.01, 0.01)
		local rb = boundary(map, a) + 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local wave = math.abs(math.sin(a * 2.5 + 0.7))
		for row = 0, 3 do
			local r = rb + 4 + row * 8 + rnd(-1.5, 1.5)
			local h = 6 + row * 9 + wave * (8 + row * 10) + rnd(-3, 4)
			local rad = rnd(3.6, 5.2) + row * 0.6
			local pos = dir * r
			terrain:FillCylinder(CFrame.new(pos.X, -2, pos.Z), 8, rad, M.Mud)
			for _, b in bands do
				local y0, y1 = b[1], math.min(b[2], h)
				if y1 > y0 then
					terrain:FillCylinder(CFrame.new(pos.X, (y0 + y1) / 2, pos.Z), y1 - y0, rad, b[3])
				end
			end
			-- grass only on the back row's top: caps on the lower steps read as stains down the face
			if row == 3 then
				terrain:FillCylinder(CFrame.new(pos.X, h + 0.6, pos.Z), 1.8, rad + 0.4, M.Grass)
			end
		end
		-- fallen blocks at the foot
		if rnd() < 0.35 then
			terrain:FillBall(
				dir * (rb + 3) + Vector3.new(0, 1, 0),
				rnd(2.5, 4),
				if rnd() < 0.5 then M.Sandstone else M.Rock
			)
		end
		if i % 10 == 0 then
			task.wait()
		end
	end
	-- The land behind the walls: earth rising to a grassy top where the forest stands (ArenaScene).
	for i = 0, 47 do
		local a = i / 48 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local r = boundary(map, a) + 48
		local h = 30 + math.abs(math.sin(a * 2.5 + 0.7)) * 26
		terrain:FillBall(dir * (r + 14) + Vector3.new(0, h * 0.35, 0), h * 0.75, M.Sandstone)
		terrain:FillBall(dir * (r + 40) + Vector3.new(0, h * 0.5, 0), h * 0.85, M.Ground)
		terrain:FillBall(dir * (r + 14) + Vector3.new(0, h * 0.35 + 2, 0), h * 0.72, M.Grass)
		terrain:FillBall(dir * (r + 40) + Vector3.new(0, h * 0.5 + 2, 0), h * 0.82, M.Grass)
		if i % 8 == 0 then
			task.wait()
		end
	end
	-- Rolling hills out to the horizon, under the dead city.
	for i = 0, 71 do
		local a = i / 72 * math.pi * 2 + rnd(-0.03, 0.03)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local r = rnd(250, 330)
		local size = rnd(44, 70)
		terrain:FillBall(dir * r + Vector3.new(0, -size * 0.2, 0), size, M.Grass)
		local far = rnd(380, 470)
		local big = rnd(60, 90)
		terrain:FillBall(dir * far + Vector3.new(0, -big * 0.35, 0), big, if i % 4 == 0 then M.Rock else M.Grass)
		if i % 12 == 0 then
			task.wait()
		end
	end
	task.wait()
	-- Boulders (nav: round obstacles).
	for _, o in map.obstacles do
		if o.style == "boulder" and not ArtLoader.get("BOULDER") then
			local r = o.w / 2
			terrain:FillBall(Vector3.new(o.x, r * 0.35, o.z), r * 0.95, M.Rock)
			terrain:FillBall(Vector3.new(o.x + r * 0.3, r * 0.75, o.z - r * 0.2), r * 0.6, M.Sandstone)
		end
	end
end

-- Solid collision, exactly the nav geometry -------------------------------------------------------------
local function buildSolid(map, solidF)
	part(solidF, {
		Name = "Floor",
		Size = Vector3.new(600, 2, 600),
		CFrame = CFrame.new(0, -1, 0),
		Transparency = 1,
		CanCollide = true,
	})
	local lim = map.halfX - map.wall
	for _, s in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local p = part(solidF, {
			Name = "Wall",
			Size = if s[1] ~= 0 then Vector3.new(4, 60, lim * 2 + 8) else Vector3.new(lim * 2 + 8, 60, 4),
			CFrame = CFrame.new(s[1] * (lim + 2), 30, s[2] * (lim + 2)),
			Transparency = 1,
			CanCollide = true,
			CanQuery = true,
		})
		p:SetAttribute("Bound", true)
	end
	for _, o in map.obstacles do
		local p
		if o.shape == "round" then
			p = part(solidF, {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(o.h, o.w, o.w),
				CFrame = CFrame.new(o.x, o.h / 2, o.z) * CFrame.Angles(0, 0, math.pi / 2),
			})
		else
			p = part(solidF, { Size = Vector3.new(o.w, o.h, o.d), CFrame = CFrame.new(o.x, o.h / 2, o.z) })
		end
		p.Name = o.name
		p.Transparency = 1
		p.CanCollide = true
		p.CanQuery = true
	end
end

-- Landmarks ----------------------------------------------------------------------------------------------

-- Centre: the extractor. A tripod rig drilling into the mother crystal. Named parts drive client
-- animation (HaloRing1..3 spin, Core pulses) and the reactor hit flash.
local function buildExtractor(o, decor)
	local model = Instance.new("Model")
	model.Name = "Reactor"
	model.Parent = decor
	local c = Vector3.new(o.x, 0, o.z)
	-- cracked pit glowing pink
	disc(decor, c + Vector3.new(0, 0.03, 0), 30, 0.06, PAL.pinkDeep, M.Neon, 0.55)
	disc(decor, c + Vector3.new(0, 0.05, 0), 25, 0.06, rgb(24, 18, 34), M.Basalt, 0)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2 + rnd(-0.2, 0.2)
		local len = rnd(7, 13)
		part(decor, {
			Size = Vector3.new(len, 0.08, rnd(0.4, 0.8)),
			CFrame = CFrame.new(c + Vector3.new(math.cos(a) * (13 + len / 2), 0.04, math.sin(a) * (13 + len / 2)))
				* CFrame.Angles(0, -a, 0),
			Color = PAL.pink,
			Material = M.Neon,
			Transparency = 0.2,
		})
	end
	-- the mother crystal: a cluster of tall faceted spikes
	local core = part(model, {
		Name = "Core",
		Size = Vector3.new(5.5, 17, 5.5),
		CFrame = CFrame.new(c + Vector3.new(0, 7.5, 0)) * CFrame.Angles(0, math.rad(45), math.rad(5)),
		Color = PAL.pink,
		Material = M.Neon,
		Transparency = 0.45,
	})
	fade(core)
	part(model, {
		Name = "CoreTip",
		Size = Vector3.one * 3.9,
		CFrame = core.CFrame * CFrame.new(0, 8.5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = rgb(255, 190, 235),
		Material = M.Neon,
	})
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2 + rnd(-0.2, 0.2)
		local h = rnd(6, 12)
		fade(part(model, {
			Name = "Shard",
			Size = Vector3.new(2.6, h, 2.6),
			CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 3.6, h / 2 - 0.8, math.sin(a) * 3.6))
				* CFrame.Angles(0, -a, 0)
				* CFrame.Angles(0, 0, math.rad(rnd(16, 30)))
				* CFrame.Angles(0, math.rad(45), 0),
			Color = PAL.pinkDeep,
			Material = M.Glass,
			Transparency = 0.1,
		}))
	end
	light(model, c + Vector3.new(0, 8, 0), PAL.pink, 28, 1.8, true)
	-- the drill rig: three legs, a cross-head over the crystal, hazard-orange feet
	local top = c + Vector3.new(0, 21, 0)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + math.rad(30)
		local foot = c + Vector3.new(math.cos(a) * 7.5, 0, math.sin(a) * 7.5)
		fade(rod(model, foot, top, 1.2, PAL.hullDark, M.Metal))
		part(model, {
			Size = Vector3.new(2.6, 1.2, 2.6),
			CFrame = CFrame.new(foot + Vector3.new(0, 0.6, 0)),
			Color = PAL.stripe,
			Material = M.Metal,
		}).CastShadow =
			true
		ball(model, foot + (top - foot) * 0.55, 0.9, PAL.stripe, M.Neon)
	end
	fade(part(model, {
		Name = "DrillHead",
		Size = Vector3.new(5, 3, 5),
		CFrame = CFrame.new(top),
		Color = PAL.hull,
		Material = M.Metal,
	}))
	fade(rod(model, top, c + Vector3.new(0, 17, 0), 1.6, PAL.stripe, M.Metal))
	-- halo rings (spun by the client)
	for i = 1, 3 do
		local ring = disc(model, c + Vector3.new(0, 3 + i * 4, 0), 17 - i * 2.6, 0.3, PAL.teal, M.Neon, 0.62)
		ring.Name = "HaloRing" .. i
		fade(ring)
	end
	spores(core, PAL.pink, 6, 0.6, 1.5)
end

-- East: the xenite grove. Faceted pink crystals of every size, corruption seeping into the ground.
local function crystal(parent, pos: Vector3, h: number, w: number, tilt: number, yaw: number, solid: boolean?)
	local p = part(parent, {
		Name = "Xenite",
		Size = Vector3.new(w, h, w),
		CFrame = CFrame.new(pos + Vector3.new(0, h / 2 - 0.6, 0))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(tilt, math.rad(45), 0),
		Color = if solid then PAL.pinkDeep else PAL.pink,
		Material = if solid then M.Glass else M.Neon,
		Transparency = if solid then 0.1 else 0.2,
	})
	p.CastShadow = solid == true
	if solid then
		part(parent, {
			Name = "Heart",
			Size = Vector3.new(w * 0.45, h * 0.85, w * 0.45),
			CFrame = p.CFrame,
			Color = PAL.pink,
			Material = M.Neon,
		})
	end
	-- a bright cap facet
	part(parent, {
		Name = "Tip",
		Size = Vector3.new(w * 0.7, w * 0.7, w * 0.7),
		CFrame = p.CFrame * CFrame.new(0, h / 2, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = rgb(255, 170, 230),
		Material = M.Neon,
	})
	return p
end

local function buildGrove(map, decor)
	local model = Instance.new("Model")
	model.Name = "Grove"
	model.Parent = decor
	for _, o in map.obstacles do
		if o.style == "crystal" then
			local c = Vector3.new(o.x, 0, o.z)
			local r = o.w / 2
			fade(crystal(model, c, o.h * 1.4, r * 0.9, rnd(-0.12, 0.12), rnd(0, 6.28), true))
			for k = 1, 6 do
				local a = k / 5 * math.pi * 2 + rnd(-0.3, 0.3)
				local d = r * rnd(0.55, 0.95)
				local h = o.h * rnd(0.35, 0.7)
				crystal(
					model,
					c + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d),
					h,
					r * rnd(0.3, 0.5),
					rnd(0.25, 0.55),
					a,
					k % 2 == 0
				)
			end
			light(model, c + Vector3.new(0, o.h * 0.6, 0), PAL.pink, o.h * 2, 1.6)
		end
	end
	-- loose shards scattered through the east
	for i = 1, 40 do
		local x, z = rnd(55, 132), rnd(-70, 75)
		local wx = -x
		if clearOf(map, wx, z, 2) then
			crystal(model, Vector3.new(wx, 0, z), rnd(1, 3.5), rnd(0.5, 1.1), rnd(0.2, 0.7), rnd(0, 6.28), false)
		end
	end
	-- giant background crystal spires on the east rim (beyond the bounds)
	for i = 1, 5 do
		local a = math.rad(rnd(-40, 40))
		local r = rnd(160, 185)
		local pos = W(math.cos(a) * r, 0, math.sin(a) * r)
		crystal(model, pos, rnd(50, 80), rnd(7, 12), rnd(-0.25, 0.25), rnd(0, 6.28), i % 2 == 0)
	end
end

-- Spore pylons (relay coils): crystal flowers on a stalk. Client colours Ring / Orb / Pad by cooldown.
local function buildPylon(o, decor, index)
	local model = Instance.new("Model")
	model.Name = "Coil" .. index
	model:SetAttribute("CoilIndex", index)
	model.Parent = decor
	local c = Vector3.new(o.x, 0, o.z)
	-- basalt pedestal, a teal crystal spire, two charge rings floating around it (spun by the client)
	ball(model, c + Vector3.new(0, -1.2, 0), 6.5, PAL.plum, M.Basalt)
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2
		part(model, {
			Size = Vector3.new(1.2, 3.2, 1.2),
			CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 1.9, 1.2, math.sin(a) * 1.9))
				* CFrame.Angles(0, -a, 0)
				* CFrame.Angles(0, 0, math.rad(-18))
				* CFrame.Angles(0, math.rad(45), 0),
			Color = PAL.tealDeep,
			Material = M.Glass,
			Transparency = 0.1,
		})
	end
	local spire = part(model, {
		Name = "Ring",
		Size = Vector3.new(1.8, o.h - 3, 1.8),
		CFrame = CFrame.new(c + Vector3.new(0, (o.h - 3) / 2 + 0.5, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = PAL.teal,
		Material = M.Neon,
		Transparency = 0.15,
	})
	spire.CastShadow = false
	for k = 1, 2 do
		local ring =
			disc(model, c + Vector3.new(0, o.h * (0.35 + k * 0.22), 0), 4.6 - k * 0.8, 0.3, PAL.teal, M.Neon, 0.25)
		ring.Name = "Ring"
	end
	local orb = ball(model, c + Vector3.new(0, o.h - 1, 0), 2.4, PAL.teal, M.Neon)
	local l = Instance.new("PointLight")
	l.Name = "Glow"
	l.Color = PAL.teal
	l.Range = 12 -- a halo on the pylon, not a pool across the lane
	l.Brightness = 1.1
	l.Parent = orb
	local pad = disc(model, c + Vector3.new(0, 0.05, 0), Defs.Coil.Radius * 2, 0.06, PAL.teal, M.Neon, 0.75)
	pad.Name = "Pad"
end

-- Ground dressing: rubble along the foot of the wall, dust in the air.
local function buildDressing(map, decor)
	local model = Instance.new("Model")
	model.Name = "Dressing"
	model.Parent = decor
	-- rubble: only along the edge, framing the floor instead of dotting it
	for i = 1, 40 do
		local a = rnd(0, 6.28)
		local r = boundary(map, a) - rnd(2, 10)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if clearOf(map, x, z, 2) then
			local s = rnd(0.6, 2.4)
			if ArtLoader.get("BOULDER") then
				local rock = ArtLoader.place(
					"BOULDER",
					model,
					CFrame.new(x, -s * 0.12, z) * CFrame.Angles(0, rnd(0, 6.28), 0),
					s * 0.22
				)
				if rock then
					rock.TextureID = ""
					rock.Material = Enum.Material.Rock -- (Slate carries the retired violet variant)
					rock.Color = rgb(150, 138, 122)
					rock.CastShadow = s > 1.6
				end
				continue
			end
			part(model, {
				Size = Vector3.new(s * rnd(1, 1.8), s * rnd(0.5, 1), s * rnd(1, 1.6)),
				CFrame = CFrame.new(x, s * 0.25, z) * CFrame.Angles(rnd(-0.4, 0.4), rnd(0, 6.28), rnd(-0.4, 0.4)),
				Color = rgb(150, 138, 122),
				Material = M.Rock,
			})
		end
	end
	-- dust drifting over the bowl: few, dim and lit by the scene (bright motes read as pickups)
	local air =
		part(model, { Name = "Air", Size = Vector3.new(260, 1, 260), CFrame = CFrame.new(0, 3, 0), Transparency = 1 })
	local e = spores(air, rgb(240, 222, 196), 5, 0.3, 0.3)
	e.LightEmission = 0.1
	e.LightInfluence = 1
	e.Lifetime = NumberRange.new(6, 10)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- Lighting ----------------------------------------------------------------------------------------------
-- DD-091: a golden, dusty dusk over our own world — a low warm sun, soft clouds, a warm haze that
-- swallows the horizon behind the hills. The blood night keeps its red.
function Arena.lighting(theme: string)
	local night = theme == "night"
	-- Skies are dimmed by sun elevation, so the night theme keeps a just-set sun (hidden, weak) and gets
	-- its darkness from the lighting colours.
	Lighting.ClockTime = if night then 17.9 else 16.1 -- low enough to glow gold, high enough to light the floor over the walls
	Lighting.GeographicLatitude = 20
	Lighting.Brightness = if night then 0.9 else 2.8
	Lighting.Ambient = if night then rgb(84, 46, 58) else rgb(106, 96, 90)
	Lighting.OutdoorAmbient = if night then rgb(140, 84, 96) else rgb(172, 156, 140)
	Lighting.ColorShift_Top = if night then rgb(255, 120, 140) else rgb(255, 200, 152)
	Lighting.ColorShift_Bottom = if night then rgb(40, 6, 20) else rgb(44, 34, 28)
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.ExposureCompensation = if night then 0.5 else 0.25
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") or c:IsA("Clouds") then
			c:Destroy()
		end
	end
	for _, c in workspace.Terrain:GetChildren() do
		if c:IsA("Clouds") then
			c:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = if night then 0.15 else 0.2
	atmosphere.Color = if night then rgb(128, 40, 46) else rgb(236, 172, 122)
	atmosphere.Decay = if night then rgb(34, 12, 20) else rgb(156, 100, 76)
	atmosphere.Glare = if night then 0.2 else 0.6
	atmosphere.Haze = if night then 0.7 else 1.8
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.StarCount = if night then 1500 else 0
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = if night then 0 else 14
	sky.MoonAngularSize = if night then 9 else 0
	sky.Parent = Lighting
	local clouds = Instance.new("Clouds")
	clouds.Cover = if night then 0.45 else 0.5
	clouds.Density = if night then 0.4 else 0.45
	clouds.Color = if night then rgb(120, 52, 60) else rgb(255, 222, 190)
	clouds.Parent = workspace.Terrain
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	bloom.Intensity = 0.55
	bloom.Size = 24
	bloom.Threshold = 1.4 -- only emissive (neon, lights) blooms; pale concrete and skin stay readable
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Brightness = 0.02
	cc.Contrast = 0.1
	cc.Saturation = if night then 0.02 else 0.06
	cc.TintColor = if night then rgb(255, 225, 235) else rgb(255, 244, 232)
	cc.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.07
	rays.Spread = 0.6
	rays.Parent = Lighting
end

-- Helpers handed to the mesh art pass.
local H = {
	W = W,
	part = part,
	ball = ball,
	ellipsoid = ellipsoid,
	rod = rod,
	disc = disc,
	light = light,
	fade = fade,
	spores = spores,
	rnd = rnd,
	boundary = boundary,
	clearOf = clearOf,
}

function Arena.build(map)
	seed = 7
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
	Arena.lighting(map.theme)
	paintTerrain(map)
	buildSolid(map, solidF)
	root.Parent = workspace
	-- Decor is parented in small chunks so the server never stalls on one huge insert. The drill, the
	-- pylons, the xenite and the boulders prefer the generated mesh art (ArenaArt) and fall back to
	-- primitives; the rest of the place is ArenaScene (DD-091).
	local coilIndex = 0
	for _, o in map.obstacles do
		if o.style == "reactor" then
			if not ArenaArt.extractor(o, decor, H) then
				buildExtractor(o, decor)
			end
		elseif o.style == "coil" then
			coilIndex += 1
			if not ArenaArt.pylon(o, decor, coilIndex, H, Defs.Coil.Radius) then
				buildPylon(o, decor, coilIndex)
			end
		end
	end
	task.wait()
	ArenaScene.breach(map, decor, H)
	task.wait()
	ArenaScene.station(map, decor, H)
	if not ArenaArt.grove(map, decor, H) then
		buildGrove(map, decor)
	end
	task.wait()
	ArenaScene.park(map, decor, H)
	ArenaArt.boulders(map, decor, H)
	task.wait()
	ArenaScene.drains(map, decor, H)
	task.wait()
	ArenaScene.rim(map, decor, H)
	task.wait()
	ArenaScene.skyline(map, decor, H)
	ArenaScene.streets(map, decor, H)
	ArenaArt.ruins(map, decor, H)
	buildDressing(map, decor)
	return root
end

return Arena
