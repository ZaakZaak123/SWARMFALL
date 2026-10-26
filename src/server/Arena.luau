--!nonstrict
-- SPOREFALL world builder: the Bloom Crater (DD-030). Replicates to every client.
--
-- Art direction: an alien crater at dusk. Cold world (plum basalt, teal bioluminescent moss, violet
-- haze) against a warm swarm (orange-red monsters) and pink xenite crystals — every hostile thing reads
-- warm, the world reads cool. Landmarks give the player a compass without a minimap: titan skull and
-- ribs to the north, our dropship to the south, the xenite grove east, the mushroom forest west, the
-- extractor rig in the middle.
--
-- Solid geometry: invisible parts that match the shared nav geometry exactly (Arena.Solid, CanQuery —
-- client shot rays and camera collision). Everything visible is decor: terrain, bones, flora, rig.
-- Tall decor that can hide the hero is tagged `Fade` (the client fades it when it blocks the view).

local Lighting = game:GetService("Lighting")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local ArtLoader = require(script.Parent.ArtLoader)
local ArenaArt = require(script.Parent.ArenaArt)

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
	local p = part(parent, { Shape = Enum.PartType.Ball, Size = Vector3.one * d, CFrame = CFrame.new(pos), Color = color, Material = material or M.SmoothPlastic })
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
	local holder = part(parent, { Name = "Light", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
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
local function paintTerrain(map)
	terrain:Clear()
	-- the clear wipes the shelter's ground too: put it back before the first yield, or anyone standing
	-- at home falls through while the crater is painted
	if Arena.onClear then
		Arena.onClear()
	end
	-- Readability first (DD-047): the walkable floor is one calm, mid-value, low-saturation surface so
	-- the warm swarm, pickups and telegraphs own the colour; the rim is clearly darker so the edge of
	-- the arena reads at a glance. Ground/Grass/Basalt/Slate carry generated variants: tint only shades.
	terrain:SetMaterialColor(M.Ground, rgb(188, 180, 170)) -- DD-058: ash and dust, not alien lavender
	terrain:SetMaterialColor(M.Grass, rgb(206, 214, 192))
	terrain:SetMaterialColor(M.Mud, rgb(72, 62, 58))
	terrain:SetMaterialColor(M.Basalt, rgb(90, 82, 80))
	terrain:SetMaterialColor(M.Slate, rgb(94, 86, 86))
	terrain:SetMaterialColor(M.Rock, rgb(66, 60, 58))
		terrain:SetMaterialColor(M.Salt, rgb(110, 104, 100))
	terrain:SetMaterialColor(M.Asphalt, rgb(44, 40, 40))
	pcall(function()
		-- animated grass blades shimmer under a top-down camera
		terrain.Decoration = false
	end)
	terrain.WaterColor = PAL.teal
	-- Bedrock floor, surface exactly at Y = 0. Smooth terrain draws a voxel's surface at
	-- centre + 4 * (occupancy - 0.5): a block filled up to 0 makes the -4..0 voxel full and the surface
	-- appears at +2, sinking every creature, pickup and prop by 2 studs. Filling to -2 leaves that voxel
	-- half full, which puts the surface on 0 (measured with a downward ray).
	terrain:FillBlock(CFrame.new(0, -7, 0), Vector3.new(760, 10, 760), M.Ground)
	task.wait()
	-- Floor patches (replace the top layer only).
	-- Recolours the top voxel layer in a disc. Fill calls would also change occupancy and raise bumps;
	-- this only rewrites the material, so the surface stays on 0.
	local function patch(x: number, z: number, r: number, material)
		local c = W(x, 0, z)
		local region = Region3.new(Vector3.new(c.X - r, -4, c.Z - r), Vector3.new(c.X + r, 0, c.Z + r)):ExpandToGrid(4)
		local mats, occs = terrain:ReadVoxels(region, 4)
		local size = mats.Size
		local corner = region.CFrame.Position - region.Size / 2
		for i = 1, size.X do
			for k = 1, size.Z do
				local px, pz = corner.X + (i - 0.5) * 4, corner.Z + (k - 0.5) * 4
				local dx, dz = px - c.X, pz - c.Z
				for j = 1, size.Y do
					if dx * dx + dz * dz <= r * r and occs[i][j][k] > 0 then
						mats[i][j][k] = material
					end
				end
			end
		end
		terrain:WriteVoxels(region, 4, mats, occs)
	end
	-- Zones are a few large, soft patches near the rim; the middle of the bowl stays one clean floor.
	-- north: the titan's shadow — darker ash under the ribs
	for i = 1, 6 do
		patch(rnd(-30, 30), rnd(90, 135), rnd(16, 24), M.Mud)
	end
	-- West and east read through their landmarks (mushrooms, xenite) and the moss on the rim columns;
	-- coloured floor patches there looked like stains from the gameplay camera.
	task.wait()
	-- The rim: basalt columns stepping up from the walkable boundary (front row low, back rows tall),
	-- with moss crowns. Reads as a deliberate formation rather than random rock.
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
			terrain:FillCylinder(CFrame.new(pos.X, h / 2 - 4, pos.Z), h + 8, rad, if row % 2 == 0 then M.Basalt else M.Slate)
			if row >= 2 and rnd() < 0.55 then
				terrain:FillCylinder(CFrame.new(pos.X, h + 0.6, pos.Z), 1.6, rad + 0.6, M.Grass)
			end
		end
		-- fallen blocks at the foot
		if rnd() < 0.35 then
			terrain:FillBall(dir * (rb + 3) + Vector3.new(0, 1, 0), rnd(2.5, 4), M.Rock)
		end
		if i % 10 == 0 then
			task.wait()
		end
	end
	-- Rising plateau behind the columns.
	for i = 0, 47 do
		local a = i / 48 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local r = boundary(map, a) + 48
		local h = 30 + math.abs(math.sin(a * 2.5 + 0.7)) * 26
		terrain:FillBall(dir * (r + 14) + Vector3.new(0, h * 0.35, 0), h * 0.75, M.Slate)
		terrain:FillBall(dir * (r + 40) + Vector3.new(0, h * 0.5, 0), h * 0.85, M.Rock)
		terrain:FillBall(dir * (r + 6) + Vector3.new(0, h * 0.7, 0), h * 0.32, M.Grass)
		if i % 8 == 0 then
			task.wait()
		end
	end
	-- Distant mesas: silhouettes against the sky.
	for i = 0, 17 do
		local a = i / 18 * math.pi * 2 + rnd(-0.12, 0.12)
		local r = rnd(260, 330)
		local h = rnd(40, 110)
		terrain:FillBlock(
			CFrame.new(math.cos(a) * r, h / 2 - 4, math.sin(a) * r) * CFrame.Angles(0, rnd(0, 6.28), 0),
			Vector3.new(rnd(40, 90), h, rnd(40, 90)),
			M.Slate
		)
		terrain:FillBall(Vector3.new(math.cos(a) * r, h, math.sin(a) * r), rnd(20, 40), M.Rock)
	end
	task.wait()
	-- Boulders (nav: round obstacles).
	for _, o in map.obstacles do
		if o.style == "boulder" and not ArtLoader.get("BOULDER") then
			local r = o.w / 2
			terrain:FillBall(Vector3.new(o.x, r * 0.35, o.z), r * 0.95, M.Basalt)
			terrain:FillBall(Vector3.new(o.x + r * 0.3, r * 0.75, o.z - r * 0.2), r * 0.6, M.Rock)
			terrain:FillBall(Vector3.new(o.x - r * 0.4, 0.5, o.z + r * 0.4), r * 0.5, M.Grass)
		end
	end
end

-- Solid collision, exactly the nav geometry -------------------------------------------------------------
local function buildSolid(map, solidF)
	part(solidF, { Name = "Floor", Size = Vector3.new(600, 2, 600), CFrame = CFrame.new(0, -1, 0), Transparency = 1, CanCollide = true })
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

-- North: the titan. Skull half-buried in the rim, jaws open toward the arena; ribs arch over the approach.
local function buildTitan(map, decor)
	local model = Instance.new("Model")
	model.Name = "Titan"
	model.Parent = decor
	-- Ribs: each a chain of bone segments rising from the feet into a high arch, slightly twisted.
	for _, o in map.obstacles do
		if o.name:match("^RibW") then
			local z = o.z
			local x0 = o.x
			local x1 = -x0
			local h = 30 + (110 - z) * 0.2
			local prev
			local n = 14
			for k = 0, n do
				local t = k / n
				local x = x0 + (x1 - x0) * t
				local y = math.sin(t * math.pi) * h + 1
				local zz = z + math.sin(t * math.pi) * 6
				local pos = Vector3.new(x, y, zz)
				if prev then
					local d = 3.4 - math.sin(t * math.pi) * 1.2
					fade(rod(model, prev, pos, d, PAL.bone, M.Limestone))
				end
				prev = pos
			end
			-- knuckled feet sunk into the ground
			for _, fx in { x0, x1 } do
				ball(model, Vector3.new(fx, 1.2, z), 5.6, PAL.boneDark, M.Limestone)
				ball(model, Vector3.new(fx, 3.2, z + 0.6), 3.6, PAL.bone, M.Limestone)
			end
		end
	end
	-- Spine: vertebrae on the ground along the axis, leading into the skull.
	for k = 0, 12 do
		local z = 62 + k * 5.4
		local pos = W(0, 0.7, z)
		ball(model, pos, 3.2 - k * 0.05, PAL.bone, M.Limestone)
		part(model, { Size = Vector3.new(5.5, 0.9, 1.2), CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)), Color = PAL.boneDark, Material = M.Limestone })
	end
	-- Skull: a long beast skull lying in the rim, snout toward the arena. Upper jaw and fangs hang over
	-- the north wound; the lower jaw lies split on the ground. Deep sockets glow teal.
	local bone, dark = PAL.bone, PAL.boneDark
	fade(ellipsoid(model, CFrame.new(W(0, 20, 170)), Vector3.new(50, 38, 50), bone, M.Limestone))
	fade(ellipsoid(model, CFrame.new(W(0, 17, 148)) * CFrame.Angles(math.rad(-8), 0, 0), Vector3.new(34, 18, 40), bone, M.Limestone))
	fade(ellipsoid(model, CFrame.new(W(0, 14, 133)) * CFrame.Angles(math.rad(-14), 0, 0), Vector3.new(24, 9, 16), dark, M.Limestone))
	-- nasal ridge and brow plates
	fade(ellipsoid(model, CFrame.new(W(0, 26, 150)) * CFrame.Angles(math.rad(-10), 0, 0), Vector3.new(8, 6, 34), dark, M.Limestone))
	for _, s in { -1, 1 } do
		-- eye socket: dark hollow with a glowing core
		local eye = W(s * 14, 25, 158)
		fade(ellipsoid(model, CFrame.new(eye) * CFrame.Angles(0, math.rad(s * 25), 0), Vector3.new(13, 10, 9), rgb(16, 10, 26), M.SmoothPlastic))
		fade(ball(model, eye + W(s * 0.5, 0, -4), 4.5, PAL.teal, M.Neon))
		light(model, eye + Vector3.new(0, 0, -10), PAL.teal, 34, 2.4)
		fade(ellipsoid(model, CFrame.new(W(s * 15, 31, 158)) * CFrame.Angles(0, 0, math.rad(s * 18)), Vector3.new(16, 4, 12), dark, M.Limestone))
		-- horns sweeping back and up
		local base = W(s * 18, 32, 168)
		local prev = base
		for k = 1, 7 do
			local p = base + W(s * k * 2.6, k * 4 - k * k * 0.2, k * 3.6)
			fade(rod(model, prev, p, 6 - k * 0.7, if k % 2 == 0 then bone else dark, M.Limestone))
			prev = p
		end
		-- lower jaw: a mandible lying open on the ground
		fade(rod(model, W(s * 16, 2, 160), W(s * 11, 2, 128), 4, dark, M.Limestone))
		ball(model, W(s * 11, 2, 128), 4.6, bone, M.Limestone)
		for k = 0, 3 do
			local p = W(s * (11.5 + k * 1.2), 3.5, 131 + k * 6)
			part(model, { Size = Vector3.new(1.4, 4, 1.4), CFrame = CFrame.new(p) * CFrame.Angles(0, 0, math.rad(s * 12)), Color = bone, Material = M.Limestone })
		end
	end
	-- upper fangs hanging over the mouth
	for k = -3, 3 do
		local len = 8 - math.abs(k) * 0.9
		fade(part(model, {
			Size = Vector3.new(1.8, len, 1.8),
			CFrame = CFrame.new(W(k * 3.4, 10 - len / 2, 127 + math.abs(k) * 1.4)) * CFrame.Angles(math.rad(-6), math.rad(45), math.rad(k * 3)),
			Color = bone,
			Material = M.Limestone,
		}))
	end
	-- The wound in the jaws: a pulsing ember membrane the swarm tears through.
	local wound = part(model, {
		Name = "Wound",
		Size = Vector3.new(20, 9, 1),
		CFrame = CFrame.new(W(0, 4.5, 138)),
		Color = PAL.ember,
		Material = M.Neon,
		Transparency = 0.15,
	})
	disc(model, W(0, 0.05, 130), 18, 0.05, rgb(110, 24, 30), M.Neon, 0.5)
	light(model, W(0, 5, 126), PAL.ember, 40, 3)
	spores(wound, PAL.ember, 8, 0.8, 2)
	-- Bone debris scattered in the north
	for i = 1, 18 do
		local x, z = rnd(-60, 60), rnd(55, 128)
		if clearOf(map, -x, z, 4) and math.abs(x) > 6 then
			local a = W(x, 0.4, z)
			local b = a + Vector3.new(rnd(-4, 4), rnd(0.4, 1.5), rnd(-4, 4))
			rod(model, a, b, rnd(0.6, 1.3), PAL.boneDark, M.Limestone)
		end
	end
end

-- South: the dropship, a warm hard-surface counterpoint to the organic world. Ramp down, lights on.
local function buildDropship(map, decor)
	local o
	for _, ob in map.obstacles do
		if ob.style == "dropship" then
			o = ob
		end
	end
	if not o then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Dropship"
	model.Parent = decor
	local c = Vector3.new(o.x, 0, o.z)
	local function blk(size, cf, color, mat, name)
		local p = part(model, { Size = size, CFrame = CFrame.new(c) * cf, Color = color, Material = mat or M.SmoothPlastic, Name = name or "Hull" })
		p.CastShadow = true
		return p
	end
	-- Long axis east-west, nose to the west (screen-left), ramp lowered to the north.
	blk(Vector3.new(24, 6.5, 11), CFrame.new(W(1, 5.6, 0)), PAL.hull)
	blk(Vector3.new(20, 2.4, 7), CFrame.new(W(2, 9.9, 0)), PAL.hull)
	ellipsoid(model, CFrame.new(c + W(-11, 5.6, 0)), Vector3.new(14, 6.5, 11), PAL.hull, M.SmoothPlastic, { CastShadow = true })
	ellipsoid(model, CFrame.new(c + W(-13.5, 7.6, 0)), Vector3.new(7, 3.2, 7), rgb(70, 220, 255), M.Glass, { Transparency = 0.1 })
	-- orange livery and a dark belly
	blk(Vector3.new(24.2, 1, 11.2), CFrame.new(W(1, 3.9, 0)), PAL.stripe)
	blk(Vector3.new(24.4, 1.6, 11.4), CFrame.new(W(1, 2.6, 0)), PAL.hullDark, M.Metal)
	blk(Vector3.new(3, 6.6, 11.2), CFrame.new(W(-4, 5.6, 0)), PAL.stripe)
	-- tail: twin fins and engines glowing east
	for _, s in { -1, 1 } do
		blk(Vector3.new(6, 5, 0.6), CFrame.new(W(11, 12.4, s * 3)) * CFrame.Angles(math.rad(s * 12), 0, math.rad(-20)), PAL.hull)
		local eng = rod(model, c + W(8, 6, s * 4.4), c + W(17, 6, s * 4.4), 3.8, PAL.hullDark, M.Metal)
		eng.CastShadow = true
		local nozzle = disc(model, c + W(17.2, 6, s * 4.4), 3, 0.3, rgb(80, 200, 255), M.Neon)
		nozzle.CFrame = CFrame.new(c + W(17.2, 6, s * 4.4))
		-- swept wings above head height
		blk(Vector3.new(11, 0.8, 7), CFrame.new(W(4, 6.6, s * 8.5)) * CFrame.Angles(0, math.rad(s * 18), math.rad(s * 3)), PAL.hullDark, M.Metal)
		blk(Vector3.new(3, 0.85, 7.05), CFrame.new(W(8.5, 6.65, s * 9.6)) * CFrame.Angles(0, math.rad(s * 18), math.rad(s * 3)), PAL.stripe)
		-- landing struts
		rod(model, c + W(-6, 2.5, s * 4), c + W(-7, 0, s * 5.5), 1, PAL.hullDark, M.Metal)
		rod(model, c + W(9, 2.5, s * 4), c + W(10, 0, s * 5.5), 1, PAL.hullDark, M.Metal)
	end
	-- ramp down toward the arena (north)
	local ramp = blk(Vector3.new(8, 0.6, 9), CFrame.new(W(2, 2.2, 9)) * CFrame.Angles(math.rad(-16), 0, 0), PAL.hullDark, M.DiamondPlate, "Ramp")
	ramp.CastShadow = false
	part(model, { Size = Vector3.new(7, 4.5, 0.2), CFrame = CFrame.new(c + W(2, 5.2, 5.55)), Color = rgb(255, 214, 160), Material = M.Neon })
	light(model, c + W(2, 4, 9), rgb(255, 210, 150), 24, 2.2, true)
	-- running lights
	for k = -2, 2 do
		ball(model, c + W(k * 5, 11.3, 0), 0.7, if k % 2 == 0 then PAL.stripe else rgb(80, 200, 255), M.Neon)
	end
	-- floodlights on poles aimed at the plaza
	for _, s in { -1, 1 } do
		local base = c + W(s * 22, 0, 10)
		rod(model, base, base + Vector3.new(0, 9, 0), 0.7, PAL.hullDark, M.Metal)
		local head = part(model, { Size = Vector3.new(2.4, 1.2, 1.2), CFrame = CFrame.lookAt(base + Vector3.new(0, 9.4, 0), Vector3.new(0, 0, o.z + 60)), Color = rgb(255, 235, 200), Material = M.Neon })
		local sl = Instance.new("SpotLight")
		sl.Angle = 60
		sl.Range = 60
		sl.Brightness = 3
		sl.Color = rgb(255, 225, 190)
		sl.Face = Enum.NormalId.Front
		sl.Shadows = true
		sl.Parent = head
	end
	-- landing pad markings
	disc(decor, Vector3.new(0, 0.03, o.z + 14), 26, 0.05, PAL.stripe, M.Neon, 0.85)
	disc(decor, Vector3.new(0, 0.04, o.z + 14), 24, 0.05, rgb(40, 34, 52), M.Asphalt, 0)
	for k = -2, 2 do
		part(decor, { Size = Vector3.new(1.4, 0.06, 4), CFrame = CFrame.new(k * 3.4, 0.06, o.z + 30 + math.abs(k) * 0.5), Color = PAL.stripe, Material = M.Neon, Transparency = 0.25 })
	end
	-- cargo crates beside the ship
	for i, p in { { 22, -2 }, { 24, 3 }, { -22, 2 } } do
		local cf = CFrame.new(c + W(p[1], 1.5, p[2])) * CFrame.Angles(0, rnd(-0.4, 0.4), 0)
		local crate = part(model, { Size = Vector3.new(4, 3, 3), CFrame = cf, Color = if i == 2 then PAL.stripe else PAL.hullDark, Material = M.Metal })
		crate.CastShadow = true
	end
end

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
			CFrame = CFrame.new(c + Vector3.new(math.cos(a) * (13 + len / 2), 0.04, math.sin(a) * (13 + len / 2))) * CFrame.Angles(0, -a, 0),
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
		part(model, { Size = Vector3.new(2.6, 1.2, 2.6), CFrame = CFrame.new(foot + Vector3.new(0, 0.6, 0)), Color = PAL.stripe, Material = M.Metal }).CastShadow = true
		ball(model, foot + (top - foot) * 0.55, 0.9, PAL.stripe, M.Neon)
	end
	fade(part(model, { Name = "DrillHead", Size = Vector3.new(5, 3, 5), CFrame = CFrame.new(top), Color = PAL.hull, Material = M.Metal }))
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
		CFrame = CFrame.new(pos + Vector3.new(0, h / 2 - 0.6, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, math.rad(45), 0),
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
				crystal(model, c + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), h, r * rnd(0.3, 0.5), rnd(0.25, 0.55), a, k % 2 == 0)
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

-- West: the mushroom forest. Pale stems, violet caps with glowing teal gills, spores drifting.
local function mushroom(parent, pos: Vector3, h: number, stemD: number, capD: number, tall: boolean)
	local lean = Vector3.new(rnd(-1, 1), 0, rnd(-1, 1)) * h * 0.06
	local top = pos + Vector3.new(0, h, 0) + lean
	local stem = rod(parent, pos, top, stemD, PAL.stem, M.SmoothPlastic)
	rod(parent, pos, pos + Vector3.new(0, h * 0.2, 0), stemD * 1.35, PAL.stem, M.SmoothPlastic)
	local cap = ellipsoid(parent, CFrame.new(top + Vector3.new(0, capD * 0.1, 0)), Vector3.new(capD, capD * 0.42, capD), PAL.cap, M.SmoothPlastic, { Name = "Cap" })
	local gills = ellipsoid(parent, CFrame.new(top + Vector3.new(0, capD * 0.02, 0)), Vector3.new(capD * 0.94, capD * 0.16, capD * 0.94), PAL.teal, M.Neon, { Transparency = 0.05 })
	gills.Name = "Gills"
	-- glowing dots on the cap
	for k = 1, math.floor(capD / 2.5) do
		local a = rnd(0, 6.28)
		local d = rnd(0.1, 0.38) * capD
		ball(parent, top + Vector3.new(math.cos(a) * d, capD * 0.18 + 0.1, math.sin(a) * d), rnd(0.4, 0.9), PAL.teal, M.Neon)
	end
	if tall then
		fade(stem)
		fade(cap)
		fade(gills)
		light(parent, top - Vector3.new(0, 1.5, 0), PAL.teal, capD * 1.6, 1.8)
		spores(gills, PAL.teal, 3, 0.4, 0.5)
	end
	return cap
end

local function buildForest(map, decor)
	local model = Instance.new("Model")
	model.Name = "Forest"
	model.Parent = decor
	for _, o in map.obstacles do
		if o.style == "mushroom" then
			mushroom(model, Vector3.new(o.x, 0, o.z), o.h, o.w, o.w * 3.2, true)
		end
	end
	-- undergrowth: clusters of small glowing mushrooms
	for i = 1, 70 do
		local x, z = rnd(-135, -50), rnd(-75, 85)
		if i > 50 then
			x, z = rnd(-120, 120), rnd(-120, 120)
		end
		local wx = -x
		if clearOf(map, wx, z, 3) and (math.abs(wx) > 30 or math.abs(z) > 30) then
			local n = math.floor(rnd(1, 4))
			for k = 1, n do
				local p = Vector3.new(wx + rnd(-1.5, 1.5), 0, z + rnd(-1.5, 1.5))
				local h = rnd(0.6, 2.2)
				rod(model, p, p + Vector3.new(0, h, 0), 0.25 + h * 0.08, PAL.stem, M.SmoothPlastic)
				ball(model, p + Vector3.new(0, h, 0), h * 0.9, if rnd() < 0.5 then PAL.teal else PAL.violet, M.Neon).Size =
					Vector3.new(h * 0.9, h * 0.4, h * 0.9)
			end
		end
	end
	-- giant background mushrooms on the west rim
	for i = 1, 6 do
		local a = math.rad(rnd(-50, 50))
		local r = rnd(165, 200)
		local pos = W(-math.cos(a) * r, 0, math.sin(a) * r)
		local h = rnd(50, 72)
		mushroom(model, pos, h, rnd(5, 8), rnd(34, 50), false)
		light(model, pos + Vector3.new(0, h - 4, 0), PAL.teal, 60, 1.4)
	end
end

-- Mega-flora on the rim: giant bloom flowers — the "bloom" the crater is named after. They frame every
-- view of the crater and give the skyline its silhouette.
local function bloomFlower(parent, base: Vector3, h: number, petal: Color3, heart: Color3)
	local bend = Vector3.new(rnd(-1, 1), 0, rnd(-1, 1)).Unit * h * 0.12
	local mid = base + Vector3.new(0, h * 0.55, 0) + bend * 0.5
	local top = base + Vector3.new(0, h, 0) + bend
	rod(parent, base, mid, h * 0.06, rgb(60, 110, 90), M.SmoothPlastic)
	rod(parent, mid, top, h * 0.045, rgb(70, 130, 105), M.SmoothPlastic)
	local n = 6
	for k = 0, n - 1 do
		local a = k / n * math.pi * 2
		ellipsoid(
			parent,
			CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.new(0, h * 0.1, -h * 0.13) * CFrame.Angles(math.rad(-50), 0, 0),
			Vector3.new(h * 0.17, h * 0.36, h * 0.04),
			petal,
			M.Neon,
			{ Name = "Petal", Transparency = 0.2 }
		)
	end
	ball(parent, top + Vector3.new(0, h * 0.04, 0), h * 0.12, heart, M.Neon)
	light(parent, top + Vector3.new(0, h * 0.06, 0), heart, h * 1.1, 1.6)
	-- hanging glow tendrils
	for k = 1, 4 do
		local a = rnd(0, 6.28)
		local from = top + Vector3.new(math.cos(a) * h * 0.12, 0, math.sin(a) * h * 0.12)
		rod(parent, from, from - Vector3.new(0, h * rnd(0.15, 0.3), 0), 0.5, heart, M.Neon)
	end
end

local function buildRimFlora(map, decor)
	local model = Instance.new("Model")
	model.Name = "RimFlora"
	model.Parent = decor
	-- north-west and north-east: blooms beside the titan; south: blooms flanking the landing zone
	local spots = {
		{ 112, 0.7, PAL.pink, rgb(255, 210, 120) },
		{ 68, 1.0, PAL.violet, PAL.teal },
		{ 128, 0.85, PAL.violet, PAL.teal },
		{ 52, 0.75, PAL.pink, rgb(255, 210, 120) },
		{ 236, 0.9, PAL.pink, PAL.teal },
		{ 304, 0.8, PAL.violet, rgb(255, 210, 120) },
		{ 270 + 28, 0.6, PAL.pink, PAL.teal },
		{ 200, 0.7, PAL.violet, rgb(255, 210, 120) },
		{ 340, 0.75, PAL.pink, PAL.teal },
	}
	for _, s in spots do
		local a = math.rad(s[1])
		local r = boundary(map, a) + rnd(26, 40)
		bloomFlower(model, Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), 62 * s[2], s[3], s[4])
	end
	-- giant mushrooms leaning over the rim on the south and north-east too
	for _, deg in { 160, 190, 250, 20, 320 } do
		local a = math.rad(deg + rnd(-6, 6))
		local r = boundary(map, a) + rnd(30, 44)
		local h = rnd(44, 64)
		mushroom(model, Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), h, rnd(5, 7), rnd(28, 40), false)
		light(model, Vector3.new(math.cos(a) * r, h - 4, math.sin(a) * r), PAL.teal, 50, 1.2)
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
			CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 1.9, 1.2, math.sin(a) * 1.9)) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-18)) * CFrame.Angles(0, math.rad(45), 0),
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
		local ring = disc(model, c + Vector3.new(0, o.h * (0.35 + k * 0.22), 0), 4.6 - k * 0.8, 0.3, PAL.teal, M.Neon, 0.25)
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

-- Spore wounds: glowing fleshy slits in the rim at every swarm entrance (north is the titan's jaw).
local function buildWounds(map, decor)
	local model = Instance.new("Model")
	model.Name = "Wounds"
	model.Parent = decor
	for key, s in map.spawns do
		if key == "N" then
			continue
		end
		local a = math.atan2(s.z, s.x)
		local rb = boundary(map, a)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local at = dir * (rb + 3.5)
		local cf = CFrame.lookAt(at, Vector3.new(0, 0, 0))
		-- membrane slit
		local slit = part(model, { Name = "Wound", Size = Vector3.new(7, 10, 0.6), CFrame = cf * CFrame.new(0, 5, 0), Color = PAL.ember, Material = M.Neon, Transparency = 0.1 })
		-- fleshy lips
		for k = -2, 2 do
			ball(model, (cf * CFrame.new(-4.4, 5 + k * 2.2, 0.4)).Position, 3 - math.abs(k) * 0.4, rgb(120, 34, 50), M.SmoothPlastic)
			ball(model, (cf * CFrame.new(4.4, 5 + k * 2.2, 0.4)).Position, 3 - math.abs(k) * 0.4, rgb(120, 34, 50), M.SmoothPlastic)
		end
		-- veins creeping onto the floor
		for k = 1, 5 do
			local ang = rnd(-0.9, 0.9)
			local len = rnd(6, 14)
			local base = at - dir * 1.5
			local d2 = (-dir * math.cos(ang) + Vector3.new(-dir.Z, 0, dir.X) * math.sin(ang))
			part(model, { Size = Vector3.new(0.5, 0.08, len), CFrame = CFrame.lookAt(base + d2 * len / 2 + Vector3.new(0, 0.05, 0), base + d2 * len + Vector3.new(0, 0.05, 0)), Color = PAL.ember, Material = M.Neon, Transparency = 0.3 })
		end
		disc(model, at - dir * 4 + Vector3.new(0, 0.04, 0), 10, 0.05, rgb(90, 20, 30), M.Neon, 0.6)
		light(model, at - dir * 4 + Vector3.new(0, 4, 0), PAL.ember, 22, 1.8)
		spores(slit, PAL.ember, 3, 0.6, 1.5)
	end
end

-- Ground dressing: glowing pools, rocks, light motes over the bowl.
local function buildDressing(map, decor)
	local model = Instance.new("Model")
	model.Name = "Dressing"
	model.Parent = decor
	-- bioluminescent pools (flat, walkable)
	-- (the glowing pools are gone: they always sat under the old raised terrain, and once the floor
	-- came down to 0 they read as solid teal buttons on the field, DD-049)
	-- basalt rubble: only along the edge, framing the floor instead of dotting it
	for i = 1, 40 do
		local a = rnd(0, 6.28)
		local r = boundary(map, a) - rnd(2, 10)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if clearOf(map, x, z, 2) then
			local s = rnd(0.6, 2.4)
			if ArtLoader.get("BOULDER") then
				local rock = ArtLoader.place("BOULDER", model, CFrame.new(x, -s * 0.12, z) * CFrame.Angles(0, rnd(0, 6.28), 0), s * 0.22)
				if rock then
					rock.TextureID = ""
					rock.Material = Enum.Material.Slate
					rock.Color = rgb(140, 132, 124)
				end
				rock.CastShadow = s > 1.6
				continue
			end
			part(model, {
				Size = Vector3.new(s * rnd(1, 1.8), s * rnd(0.5, 1), s * rnd(1, 1.6)),
				CFrame = CFrame.new(x, s * 0.25, z) * CFrame.Angles(rnd(-0.4, 0.4), rnd(0, 6.28), rnd(-0.4, 0.4)),
				Color = PAL.plum,
				Material = M.Basalt,
			})
		end
	end
	-- drifting motes over the whole bowl
	local air = part(model, { Name = "Air", Size = Vector3.new(260, 1, 260), CFrame = CFrame.new(0, 2, 0), Transparency = 1 })
	-- sparse and faint: bright motes over the floor read as pickups or bullets
	local e = spores(air, PAL.teal, 6, 0.3, 0.4)
	e.Lifetime = NumberRange.new(6, 10)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.6), NumberSequenceKeypoint.new(1, 1) })
end

-- Lighting ----------------------------------------------------------------------------------------------
local SKY = {
	dusk = { Ft = "86856141666347", Bk = "139944741204062", Lf = "97884626847303", Rt = "137347809792227", Up = "134115742236340", Dn = "90449782940747" },
	night = { Ft = "78103046101805", Bk = "108175351376516", Lf = "127960814993421", Rt = "97184413821010", Up = "94364693298950", Dn = "79055482839356" },
}

function Arena.lighting(theme: string)
	local night = theme == "night"
	-- Skyboxes are dimmed by sun elevation, so the night theme keeps a just-set sun (hidden, weak) and
	-- gets its darkness from the painted night sky and the lighting colours.
	Lighting.ClockTime = if night then 17.9 else 17.75
	Lighting.GeographicLatitude = 20
	Lighting.Brightness = if night then 0.9 else 3
	Lighting.Ambient = if night then rgb(96, 54, 70) else rgb(114, 102, 100)
	Lighting.OutdoorAmbient = if night then rgb(156, 96, 112) else rgb(186, 172, 160)
	Lighting.ColorShift_Top = if night then rgb(255, 120, 140) else rgb(255, 170, 140)
	Lighting.ColorShift_Bottom = if night then rgb(40, 6, 20) else rgb(50, 30, 30)
	Lighting.EnvironmentDiffuseScale = 0.8
	Lighting.EnvironmentSpecularScale = 0.35 -- the painted pink sky otherwise mirrors in the floor
	Lighting.ExposureCompensation = if night then 0.5 else 0.35
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") or c:IsA("Clouds") then
			c:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = if night then 0.24 else 0.16
	atmosphere.Offset = 0.12
	atmosphere.Color = if night then rgb(150, 50, 60) else rgb(226, 150, 120)
	atmosphere.Decay = if night then rgb(40, 14, 30) else rgb(110, 70, 100)
	atmosphere.Glare = if night then 0.2 else 0.6
	atmosphere.Haze = if night then 0.6 else 0.25
	atmosphere.Parent = Lighting
	-- DD-058: our own world's sky over a smoky sunset (the painted alien sky with its ringed planet
	-- is retired; SKY keeps its ids for reference). The haze carries the colour.
	local _ = SKY
	local sky = Instance.new("Sky")
	sky.StarCount = if night then 1500 else 0
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = if night then 0 else 16
	sky.MoonAngularSize = if night then 9 else 0
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	bloom.Intensity = 0.7
	bloom.Size = 24
	bloom.Threshold = 1.3 -- only emissive (neon, lights) blooms; white skin and bone stay readable
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Brightness = 0.02
	cc.Contrast = 0.12
	cc.Saturation = 0.02
	cc.TintColor = if night then rgb(255, 225, 235) else rgb(255, 238, 250)
	cc.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
end

-- Helpers handed to the mesh art pass.
local H = { W = W, part = part, ball = ball, rod = rod, disc = disc, light = light, fade = fade, spores = spores, rnd = rnd, boundary = boundary, clearOf = clearOf }

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
	-- Decor is parented in small chunks so the server never stalls on one huge insert.
	-- Each landmark prefers the generated mesh art (ArenaArt) and falls back to its primitive build.
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
	if not ArenaArt.titan(map, decor, H) then
		buildTitan(map, decor)
	end
	task.wait()
	if not ArenaArt.dropship(map, decor, H) then
		buildDropship(map, decor)
	end
	if not ArenaArt.grove(map, decor, H) then
		buildGrove(map, decor)
	end
	task.wait()
	if not ArenaArt.forest(map, decor, H) then
		buildForest(map, decor)
	end
	task.wait()
	ArenaArt.boulders(map, decor, H)
	if not ArenaArt.wounds(map, decor, H) then
		buildWounds(map, decor)
	end
	if not ArenaArt.rim(map, decor, H) then
		buildRimFlora(map, decor)
	end
	ArenaArt.ruins(map, decor, H)
	buildDressing(map, decor)
	return root
end

return Arena
