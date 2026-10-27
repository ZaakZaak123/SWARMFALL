--!nonstrict
-- The drill's funnel as a place (DD-091): a crater the drill opened in a buried city, at dusk. The
-- previous dressing (DD-030 … DD-062) mixed an alien crater (neon mushrooms, a horned skull, violet
-- basalt, pink light pools) with our ruined world; the owner asked for a scene you want to come back to
-- and nothing garish or unreadable in it. One story now, told by every piece:
--   the walls — layered earth of the crater, a forest along its top, the stumps of houses sticking out;
--   the floor — the old streets the drill laid bare (broken asphalt, faded lane marks, manholes);
--   north  — the swarm's breach: an old metro portal, a sheared overpass on the old rib feet, rails;
--   south  — the drill station's camp: shipping containers, a site hut, floodlights (the old dropship box);
--   west   — an overgrown square: trees on the old mushroom feet, bushes, a bench, a lamp still burning;
--   east   — xenite growing out of the rubble (the currency stays pink, its light stays on the crystals);
--   the swarm's ways in — storm drains in the wall, dark inside, a warm glow deep in them.
-- Colour has one job each, as in the HUD: the world is dust, concrete, rust and green; ember is the
-- swarm; pink is xenite; cyan is our machines. Nothing here is solid: the nav geometry (Arena.Solid)
-- is unchanged, and every piece stands on or inside a footprint the fight already had.

local ArtLoader = require(script.Parent.ArtLoader)

local Scene = {}

local rgb = Color3.fromRGB
local M = Enum.Material

local P = {
	concrete = rgb(134, 128, 120),
	concreteDark = rgb(98, 93, 88),
	concreteDeep = rgb(62, 58, 56),
	rust = rgb(128, 70, 46),
	steel = rgb(74, 76, 80),
	wood = rgb(98, 74, 52),
	timber = rgb(70, 54, 40),
	flesh = rgb(92, 44, 42),
	fleshDark = rgb(54, 28, 30),
	ember = rgb(255, 120, 50),
	dark = rgb(10, 9, 9),
	paint = rgb(214, 202, 168),
	leaf = rgb(86, 116, 58),
	lamp = rgb(255, 206, 140),
}
Scene.P = P

-- Old streets across the floor (world XZ). Terrain paints them (Arena), the decor marks them.
Scene.Roads = {
	{ a = Vector3.new(-150, 0, 46), b = Vector3.new(150, 0, 28), w = 14 }, -- the avenue
	{ a = Vector3.new(-50, 0, -150), b = Vector3.new(-40, 0, 150), w = 11 }, -- a side street
}

-- Stretches of a road buried under the dust (`t` in studs along it): the same answer for terrain and
-- decor, so lane marks never float over bare ground.
function Scene.roadGap(index: number, t: number): boolean
	return math.noise(t / 24, index * 7.31, 0.5) < -0.28
end

-- Distance from (x, z) to road `r`, and how far along it the closest point is.
function Scene.roadDistance(r, x: number, z: number): (number, number)
	local ab = r.b - r.a
	local len = ab.Magnitude
	local u = ab / len
	local px, pz = x - r.a.X, z - r.a.Z
	local t = math.clamp(px * u.X + pz * u.Z, 0, len)
	local cx, cz = r.a.X + u.X * t, r.a.Z + u.Z * t
	return math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2), t
end

-- The square of the old park (west), the station's yard (south) and the breach (north), world space.
Scene.Park = { x = 96, z = 8, r = 44 }
Scene.Breach = { w = 30, h = 18 }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace.Terrain }

local function groundAt(x: number, z: number): number
	local hit = workspace:Raycast(Vector3.new(x, 260, z), Vector3.new(0, -320, 0), rayParams)
	return if hit then hit.Position.Y else 0
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- A block in a frame: `f` is the piece's centre.
local function block(H, parent, f: CFrame, size: Vector3, color: Color3, material, props)
	local p = H.part(parent, { Size = size, CFrame = f, Color = color, Material = material or M.Concrete })
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return p
end

-- A flattened ellipsoid (organic crust, foliage).
local function blob(H, parent, cf: CFrame, size: Vector3, color: Color3, material)
	local p = H.part(parent, { Size = size, CFrame = cf, Color = color, Material = material or M.Rock })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- The hive's roots: a dark tendril creeping from `a` along `dir` (on a wall, a roof, a lip), in a few
-- bending segments that thin toward the tip. Matte, not neon: the glow belongs to the sacs.
local function root(H, parent, a: Vector3, dir: Vector3, len: number, d: number, bend: Vector3)
	local p = a
	local n = 3
	for k = 1, n do
		local q = p + dir * (len / n) + bend * (H.rnd(-1, 1) * len / n * 0.35)
		H.rod(parent, p, q, d * (1 - (k - 1) / (n + 1)), if k % 2 == 0 then P.flesh else P.fleshDark, M.SmoothPlastic)
		p = q
	end
end

-- A tree from the grove's set (the same oaks and birches as at home), its height `h`.
local function tree(H, parent, at: Vector3, h: number, kind: string?)
	kind = kind or (if H.rnd() < 0.8 then "OAK" else "BIRCH")
	local t = ArtLoader.get(kind)
	if t then
		local p = ArtLoader.place(kind, parent, CFrame.new(at) * CFrame.Angles(0, H.rnd(0, 6.28), 0), h / t.Size.Y)
		p.CastShadow = true
		return p
	end
	H.rod(parent, at, at + Vector3.new(0, h * 0.6, 0), h * 0.07, P.wood, M.Wood)
	return blob(
		H,
		parent,
		CFrame.new(at + Vector3.new(0, h * 0.68, 0)),
		Vector3.new(h * 0.6, h * 0.5, h * 0.6),
		P.leaf,
		M.Grass
	)
end

-- The breach (north) ------------------------------------------------------------------------------------
-- The swarm's main way in is an old metro tunnel the crater cut open: a concrete portal in the wall,
-- dark inside, the hive's warm glow deep in it, rails running out across the floor. What is left of an
-- overpass the crater sheared stands on the old rib feet: broken pillars, one whole bent by the portal
-- (no deck over the lane: seen from the fight's camera a slab is only a brown lid).
function Scene.breach(map, decor, H)
	local m = model(decor, "Breach")
	local terrain = workspace.Terrain
	local face = H.boundary(map, math.pi / 2) + 1
	local bw, bh = Scene.Breach.w, Scene.Breach.h
	-- clear the wall in front of the portal, then dig the tunnel
	terrain:FillBlock(CFrame.new(0, 24, face - 5), Vector3.new(84, 44, 12), M.Air)
	-- (down to -2: a dig that stops at the floor leaves a thin crust of earth rising over the tunnel's own
	-- floor; the tunnel floor part covers the step)
	terrain:FillBlock(CFrame.new(0, -2 + (bh + 8) / 2, face + 30), Vector3.new(bw + 8, bh + 8, 60), M.Air)
	-- the headwall: concrete columns of broken height round the opening
	local cols = 12
	local width = 78
	for k = 0, cols - 1 do
		local x0 = -width / 2 + k * width / cols
		local cx = x0 + width / cols / 2
		local top = H.rnd(22, 36)
		local from = if math.abs(cx) < bw / 2 then bh else 0
		local shade = P.concrete:Lerp(P.concreteDark, H.rnd(0, 0.5))
		local p = block(
			H,
			m,
			CFrame.new(cx, (from + top) / 2, face + 2),
			Vector3.new(width / cols + 0.05, top - from, 4),
			shade
		)
		p.CastShadow = true
		-- a broken top: a smaller chunk askew
		if H.rnd() < 0.5 then
			block(
				H,
				m,
				CFrame.new(cx + H.rnd(-1, 1), top + 0.8, face + 2)
					* CFrame.Angles(H.rnd(-0.2, 0.2), 0, H.rnd(-0.3, 0.3)),
				Vector3.new(width / cols * H.rnd(0.4, 0.8), 1.8, 3.4),
				shade
			)
		end
	end
	-- the portal's frame: pilasters and a lintel, darker and proud of the wall
	for _, s in { -1, 1 } do
		block(H, m, CFrame.new(s * (bw / 2 + 1.2), bh / 2, face - 0.4), Vector3.new(2.6, bh, 2), P.concreteDark)
	end
	block(H, m, CFrame.new(0, bh + 1.4, face - 0.4), Vector3.new(bw + 5, 2.8, 2.4), P.concreteDark)
	-- the metro's red «М» on a rusted plate, hanging askew over the lintel
	local plate = block(
		H,
		m,
		CFrame.new(-6, bh + 6.2, face - 1) * CFrame.Angles(0, 0, math.rad(7)),
		Vector3.new(6, 6, 0.4),
		P.rust,
		M.Metal
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(200, 200)
	gui.LightInfluence = 1
	gui.Parent = plate
	local letter = Instance.new("TextLabel")
	letter.BackgroundTransparency = 1
	letter.Size = UDim2.fromScale(1, 1)
	letter.Font = Enum.Font.GothamBlack
	letter.Text = "М"
	letter.TextScaled = true
	letter.TextColor3 = rgb(196, 56, 44)
	letter.Parent = gui
	-- inside: walls, roof and floor of the tunnel (inside the dug space, or the earth's own faces show
	-- in front of them), and the darkness it runs into
	local depth = 46
	local zc = face + 4 + depth / 2
	-- (they cast shadows, unlike the rest of the decor: the roof is what keeps the sun out)
	for _, s in { -1, 1 } do
		block(H, m, CFrame.new(s * (bw / 2 + 0.5), bh / 2, zc), Vector3.new(1, bh, depth), P.concreteDeep).CastShadow =
			true
	end
	block(H, m, CFrame.new(0, bh + 0.5, zc), Vector3.new(bw + 2, 1, depth), P.concreteDeep).CastShadow = true
	block(H, m, CFrame.new(0, -0.6, zc + 1), Vector3.new(bw + 2, 2.6, depth + 6), P.concreteDeep)
	block(H, m, CFrame.new(0, bh / 2, face + 4 + depth), Vector3.new(bw + 2, bh + 1, 1), P.dark, M.SmoothPlastic)
	-- the hive grown into it: roots creeping out along the walls and roof, a few swollen sacs, a warm
	-- glow far inside
	for i = 1, 18 do
		local side = if i % 3 == 0 then 0 else (if i % 2 == 0 then -1 else 1)
		local z = face + H.rnd(14, depth)
		local len = H.rnd(8, 18)
		local d = H.rnd(0.5, 1.1)
		if side == 0 then
			root(
				H,
				m,
				Vector3.new(H.rnd(-bw / 2 + 2, bw / 2 - 2), bh - 0.3, z),
				Vector3.new(0, 0, -1),
				len,
				d,
				Vector3.xAxis
			)
		else
			local y = H.rnd(1, bh - 1)
			root(H, m, Vector3.new(side * (bw / 2 - 0.3), y, z), Vector3.new(0, 0, -1), len, d, Vector3.yAxis)
		end
	end
	for i = 1, 6 do
		local at = Vector3.new(H.rnd(-bw / 2 + 4, bw / 2 - 4), H.rnd(0.6, 3), face + H.rnd(14, depth - 4))
		H.ball(m, at, H.rnd(1, 1.8), P.ember, M.Neon, { Transparency = 0.25 })
	end
	H.light(m, Vector3.new(0, 6, face + 24), P.ember, 34, 1.6)
	local mouth = H.part(m, {
		Name = "Breath",
		Size = Vector3.new(bw - 6, 1, 6),
		CFrame = CFrame.new(0, 1, face + 6),
		Transparency = 1,
	})
	H.spores(mouth, P.ember, 3, 0.5, 1.2)
	-- rails out of the tunnel to the middle of the floor, broken here and there
	local rail = rgb(84, 76, 70)
	local zEnd = 58
	local zStart = face + depth
	local z = zStart
	while z > zEnd do
		local len = H.rnd(8, 16)
		local z1 = math.max(zEnd, z - len)
		if H.rnd() > 0.22 then
			for _, x in { -2.4, 2.4 } do
				block(H, m, CFrame.new(x, 0.2, (z + z1) / 2), Vector3.new(0.4, 0.3, z - z1), rail, M.Metal)
			end
			for zz = z - 1.5, z1, -3.2 do
				block(
					H,
					m,
					CFrame.new(H.rnd(-0.3, 0.3), 0.08, zz) * CFrame.Angles(0, H.rnd(-0.08, 0.08), 0),
					Vector3.new(7, 0.2, 1),
					P.timber,
					M.Wood
				)
			end
		end
		z = z1 - H.rnd(2, 6)
	end
	-- the overpass: a bent of pillars and a cap beam on every pair of rib feet
	local bents = {}
	for _, o in map.obstacles do
		if o.name:match("^RibW") then
			table.insert(bents, o.z)
		end
	end
	table.sort(bents)
	local ribX = 22
	for _, o in map.obstacles do
		if o.name:match("^Rib") then
			ribX = math.abs(o.x)
		end
	end
	for i, bz in bents do
		local whole = i == #bents
		local beamY = 16.5
		for _, sx in { -1, 1 } do
			local h = if whole then beamY else H.rnd(6, 12)
			local p = block(H, m, CFrame.new(sx * ribX, h / 2, bz), Vector3.new(3.8, h, 3.8), P.concrete)
			p.CastShadow = true
			H.fade(p)
			block(H, m, CFrame.new(sx * ribX, 0.6, bz), Vector3.new(5.4, 1.2, 5.4), P.concreteDark)
			if not whole then
				-- a broken top: a chunk askew and the rebar it hung on
				local top = block(
					H,
					m,
					CFrame.new(sx * ribX + H.rnd(-0.4, 0.4), h + 0.7, bz)
						* CFrame.Angles(H.rnd(-0.3, 0.3), H.rnd(0, 6.28), H.rnd(-0.3, 0.3)),
					Vector3.new(3, 1.6, 2.6),
					P.concreteDark
				)
				H.fade(top)
				for _ = 1, 4 do
					local from = Vector3.new(sx * ribX + H.rnd(-1.4, 1.4), h, bz + H.rnd(-1.4, 1.4))
					H.fade(
						H.rod(
							m,
							from,
							from + Vector3.new(H.rnd(-1, 1), H.rnd(1.5, 3.5), H.rnd(-1, 1)),
							0.22,
							P.rust,
							M.Metal
						)
					)
				end
			end
			-- creepers up the pillar's face toward the floor
			for _ = 1, 2 do
				local len = H.rnd(2, h * 0.6)
				local v = block(
					H,
					m,
					CFrame.new(sx * ribX + H.rnd(-1.4, 1.4), len / 2, bz - 1.95),
					Vector3.new(0.5, len, 0.12),
					P.leaf,
					M.Grass
				)
				H.fade(v)
			end
		end
		if whole then
			local beam = block(H, m, CFrame.new(0, beamY + 1.5, bz), Vector3.new(ribX * 2 + 7, 3, 4.6), P.concrete)
			beam.CastShadow = true
			H.fade(beam)
			for _ = 1, 5 do
				local from = Vector3.new(H.rnd(-ribX + 3, ribX - 3), beamY + 3, bz - 2.3)
				H.fade(
					H.rod(
						m,
						from,
						from + Vector3.new(H.rnd(-1, 1), H.rnd(-1, 2), -H.rnd(1, 2.5)),
						0.22,
						P.rust,
						M.Metal
					)
				)
			end
			for _ = 1, 5 do
				local len = H.rnd(2.5, 6)
				local v = block(
					H,
					m,
					CFrame.new(H.rnd(-ribX, ribX), beamY - len / 2 + 0.2, bz - 2.4),
					Vector3.new(0.6, len, 0.3),
					P.leaf,
					M.Grass
				)
				H.fade(v)
			end
		end
	end
	-- fallen chunks of the headwall either side of the opening (along the wall, off the swarm's lane)
	for i = 1, 10 do
		local s = if i % 2 == 0 then -1 else 1
		local x = s * H.rnd(bw / 2 + 3, 40)
		local sz = H.rnd(1.6, 4)
		block(
			H,
			m,
			CFrame.new(x, sz * 0.3, face - H.rnd(2, 7))
				* CFrame.Angles(H.rnd(-0.4, 0.4), H.rnd(0, 6.28), H.rnd(-0.4, 0.4)),
			Vector3.new(sz * H.rnd(1, 1.6), sz * 0.8, sz),
			P.concrete:Lerp(P.concreteDark, H.rnd(0, 0.6))
		).CastShadow =
			true
	end
end

-- The drill station's camp (south) ----------------------------------------------------------------------
-- The old dropship's footprint: two rows of shipping containers, one more stacked across them, a site
-- hut with a lit window, oil drums and the floodlights that light the floor toward the drill.
local function container(H, parent, cf: CFrame, len: number, color: Color3, label: string?)
	local m = model(parent, "Container")
	local w, h = 8, 8.4
	local body = block(H, m, cf, Vector3.new(len, h, w), color, M.Metal)
	body.CastShadow = true
	H.fade(body)
	local rib = color:Lerp(rgb(30, 26, 24), 0.25)
	for x = -len / 2 + 1, len / 2 - 1, 1.7 do
		for _, s in { -1, 1 } do
			block(H, m, cf * CFrame.new(x, 0, s * (w / 2 + 0.08)), Vector3.new(0.5, h - 0.8, 0.16), rib, M.Metal)
		end
	end
	-- the corner castings and the top rails
	local frame = color:Lerp(rgb(20, 18, 16), 0.45)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block(
				H,
				m,
				cf * CFrame.new(sx * (len / 2 - 0.25), 0, sz * (w / 2 - 0.25)),
				Vector3.new(0.6, h + 0.1, 0.6),
				frame,
				M.Metal
			)
		end
		-- the doors at one end, their lock bars
		if sx == 1 then
			for _, sz in { -1, 1 } do
				block(
					H,
					m,
					cf * CFrame.new(len / 2 + 0.06, 0, sz * w / 4),
					Vector3.new(0.12, h - 0.9, w / 2 - 0.3),
					rib,
					M.Metal
				)
				for _, bz in { 0.25, 0.75 } do
					block(
						H,
						m,
						cf * CFrame.new(len / 2 + 0.18, 0, sz * w * bz / 2),
						Vector3.new(0.12, h - 1.4, 0.14),
						frame,
						M.Metal
					)
				end
			end
		end
	end
	if label then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(600, 220)
		gui.LightInfluence = 1
		gui.Parent = body
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.8, 0.5)
		t.Position = UDim2.fromScale(0.1, 0.25)
		t.Font = Enum.Font.GothamBlack
		t.Text = label
		t.TextScaled = true
		t.TextColor3 = rgb(226, 218, 200)
		t.TextTransparency = 0.25
		t.Parent = gui
	end
	return m
end

function Scene.station(map, decor, H)
	local o
	for _, ob in map.obstacles do
		if ob.style == "dropship" then
			o = ob
		end
	end
	if not o then
		return
	end
	local m = model(decor, "Station")
	local c = Vector3.new(o.x, 0, o.z)
	local len = o.w / 2 - 0.4
	-- the row facing the floor (north), then the back row: a container and the hut
	container(
		H,
		m,
		CFrame.new(c + Vector3.new(-o.w / 4, 4.2, o.d / 4)) * CFrame.Angles(0, math.pi, 0),
		len,
		rgb(126, 66, 48),
		"БУР-7"
	)
	container(
		H,
		m,
		CFrame.new(c + Vector3.new(o.w / 4, 4.2, o.d / 4)) * CFrame.Angles(0, math.pi, 0),
		len,
		rgb(64, 98, 104)
	)
	container(H, m, CFrame.new(c + Vector3.new(-o.w / 4, 4.2, -o.d / 4)), len, rgb(150, 116, 58))
	container(
		H,
		m,
		CFrame.new(c + Vector3.new(-2, 12.6, 0)) * CFrame.Angles(0, math.pi / 2 + 0.06, 0),
		o.d + 1,
		rgb(96, 102, 92)
	)
	-- the site hut: boards, a lit window, a door, a tin roof
	local hut = CFrame.new(c + Vector3.new(o.w / 4, 0, -o.d / 4))
	local walls =
		block(H, m, hut * CFrame.new(0, 3.8, 0), Vector3.new(len - 1, 7.6, 7), rgb(132, 112, 86), M.WoodPlanks)
	walls.CastShadow = true
	H.fade(walls)
	local roof = block(
		H,
		m,
		hut * CFrame.new(0, 8, 0) * CFrame.Angles(math.rad(6), 0, 0),
		Vector3.new(len + 0.6, 0.4, 8.6),
		rgb(96, 92, 88),
		M.Metal
	)
	H.fade(roof)
	local window = block(
		H,
		m,
		hut * CFrame.new(-3, 4.4, -3.56),
		Vector3.new(3.2, 2.2, 0.15),
		P.lamp,
		M.Neon,
		{ Transparency = 0.15 }
	)
	window.Name = "Window"
	block(H, m, hut * CFrame.new(3.6, 3, -3.56), Vector3.new(2.4, 5.6, 0.15), P.timber, M.Wood)
	H.light(m, (hut * CFrame.new(-3, 4.4, -5)).Position, P.lamp, 14, 0.9)
	-- oil drums and crates at the corners (inside the footprint, or hugging it)
	local drums = {
		{ -o.w / 2 - 1.6, o.d / 2 - 1 },
		{ -o.w / 2 - 1.4, o.d / 2 - 3.6 },
		{ o.w / 2 + 1.6, o.d / 2 - 1.4 },
		{ o.w / 2 + 1.5, -o.d / 2 + 2 },
	}
	for i, d in drums do
		local p = c + Vector3.new(d[1], 1.6, d[2])
		local drum = H.part(m, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3.2, 2.4, 2.4),
			CFrame = CFrame.new(p) * CFrame.Angles(0, 0, math.pi / 2),
			Color = if i % 2 == 0 then rgb(58, 88, 112) else rgb(140, 64, 40),
			Material = M.Metal,
		})
		drum.CastShadow = true
	end
	-- floodlights: masts at the front corners, aimed over the floor at the drill
	for _, s in { -1, 1 } do
		local base = c + Vector3.new(s * (o.w / 2 + 5), 0, o.d / 2 + 3)
		H.rod(m, base, base + Vector3.new(0, 12, 0), 0.6, P.steel, M.Metal)
		block(H, m, CFrame.new(base + Vector3.new(0, 0.3, 0)), Vector3.new(2.4, 0.6, 2.4), P.concreteDark)
		local head = block(
			H,
			m,
			CFrame.lookAt(base + Vector3.new(0, 12.4, 0), Vector3.new(0, 0, c.Z + 70)),
			Vector3.new(2.6, 1.4, 1.2),
			rgb(255, 238, 210),
			M.Neon
		)
		local sl = Instance.new("SpotLight")
		sl.Angle = 70
		sl.Range = 64
		sl.Brightness = 1.3
		sl.Color = rgb(255, 228, 196)
		sl.Shadows = false
		sl.Face = Enum.NormalId.Front
		sl.Parent = head
	end
end

-- The overgrown square (west) ---------------------------------------------------------------------------
-- Trees stand on the old mushroom feet (each the height the fight measured for it), the lawn round them
-- is the park's (terrain), bushes along the wall, a bench, a fallen trunk, a lamp still burning.
function Scene.park(map, decor, H)
	local m = model(decor, "Park")
	for _, o in map.obstacles do
		if o.style == "mushroom" then
			local kind = if o.w >= 5 then "OAK" else "BIRCH"
			local t = tree(H, m, Vector3.new(o.x, -0.2, o.z), o.h * 1.25, kind)
			H.fade(t)
		end
	end
	local pk = Scene.Park
	local function free(x, z, pad)
		return H.clearOf(map, x, z, pad)
	end
	-- bushes along the wall behind the square and round the trees
	for i = 1, 22 do
		local a = math.rad(H.rnd(-62, 62))
		local r = H.boundary(map, a) - H.rnd(1, 9)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if free(x, z, 2.5) then
			local k = H.rnd(1.4, 2.6)
			if ArtLoader.get("BUSH") then
				ArtLoader.place("BUSH", m, CFrame.new(x, -0.3, z) * CFrame.Angles(0, H.rnd(0, 6.28), 0), k)
			else
				blob(H, m, CFrame.new(x, k, z), Vector3.new(k * 3.4, k * 2.4, k * 3.4), P.leaf, M.Grass)
			end
		end
	end
	-- a bench and a lamp post by the path, a trunk fallen across the lawn
	local bench = CFrame.new(pk.x - 18, 0, pk.z - 14) * CFrame.Angles(0, math.rad(78), 0)
	if free(bench.X, bench.Z, 2) then
		block(H, m, bench * CFrame.new(0, 1.5, 0), Vector3.new(5, 0.3, 1.5), P.wood, M.WoodPlanks)
		block(
			H,
			m,
			bench * CFrame.new(0, 2.6, 0.7) * CFrame.Angles(math.rad(-12), 0, 0),
			Vector3.new(5, 1.2, 0.25),
			P.wood,
			M.WoodPlanks
		)
		for _, s in { -1, 1 } do
			block(H, m, bench * CFrame.new(s * 2.1, 0.75, 0), Vector3.new(0.3, 1.5, 1.4), P.steel, M.Metal)
		end
	end
	local lamps = { { pk.x - 20, pk.z - 6, true }, { pk.x - 22, pk.z + 22, false }, { pk.x + 2, pk.z - 30, false } }
	for _, l in lamps do
		if free(l[1], l[2], 1.5) then
			local base = Vector3.new(l[1], 0, l[2])
			local lean = if l[3] then Vector3.zero else Vector3.new(H.rnd(-1.6, 1.6), 0, H.rnd(-1.6, 1.6))
			local top = base + Vector3.new(0, 10, 0) + lean
			H.rod(m, base, top, 0.45, rgb(44, 48, 46), M.Metal)
			local head = block(
				H,
				m,
				CFrame.new(top + Vector3.new(0, 0.4, 0)),
				Vector3.new(1.2, 0.9, 1.2),
				if l[3] then P.lamp else rgb(60, 60, 58),
				if l[3] then M.Neon else M.Metal
			)
			if l[3] then
				local pl = Instance.new("PointLight")
				pl.Color = P.lamp
				pl.Range = 18
				pl.Brightness = 1.1
				pl.Parent = head
			end
		end
	end
	for i = 1, 2 do
		local x, z = pk.x + H.rnd(-6, 14), pk.z + H.rnd(-26, 26)
		if free(x, z, 4) then
			local a = Vector3.new(x, 0.8, z)
			local yaw = H.rnd(0, 6.28)
			local b = a + Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * H.rnd(9, 13)
			H.rod(m, a, b, 1.6, P.timber, M.Wood).CastShadow = true
			blob(H, m, CFrame.new(b), Vector3.new(3, 2, 3), P.leaf, M.Grass)
		end
	end
end

-- The rim ------------------------------------------------------------------------------------------------
-- The houses the crater cut through: concrete stumps in the wall, their storeys and dark windows facing
-- the floor, rebar on the broken tops. A forest along the top of the wall, poles with sagging wires.
local function building(H, parent, cf: CFrame, w: number, d: number, h: number)
	local m = model(parent, "Ruin")
	local body =
		block(H, m, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), P.concrete:Lerp(P.concreteDark, H.rnd(0, 0.7)))
	body.CastShadow = true
	local storey = 4.6
	local n = math.floor(h / storey)
	for k = 1, n do
		local y = k * storey - 0.4
		if y < h - 1 then
			block(H, m, cf * CFrame.new(0, y, 0), Vector3.new(w + 0.8, 0.6, d + 0.8), P.concreteDark)
		end
		-- the windows that look at the floor (local -Z)
		local count = math.floor(w / 4)
		for i = 1, count do
			if H.rnd() < 0.75 and y - 2.4 > 0.5 then
				local x = -w / 2 + (i - 0.5) * w / count
				block(
					H,
					m,
					cf * CFrame.new(x, y - 2.3, -d / 2 - 0.02),
					Vector3.new(2.1, 2.5, 0.12),
					P.dark,
					M.SmoothPlastic
				)
			end
		end
	end
	-- the broken top: rebar standing out of it and a lump of the storey above
	for k = 1, math.floor(w / 3) do
		local p = cf * CFrame.new(H.rnd(-w / 2 + 1, w / 2 - 1), h, H.rnd(-d / 2 + 1, d / 2 - 1))
		H.rod(
			m,
			p.Position,
			p.Position + Vector3.new(H.rnd(-0.8, 0.8), H.rnd(1.5, 4), H.rnd(-0.8, 0.8)),
			0.25,
			P.rust,
			M.Metal
		)
	end
	block(
		H,
		m,
		cf * CFrame.new(H.rnd(-w / 4, w / 4), h + 1.2, H.rnd(-d / 4, d / 4)) * CFrame.Angles(0, 0, H.rnd(-0.2, 0.2)),
		Vector3.new(w * 0.4, 2.4, d * 0.6),
		P.concreteDark
	)
	return m
end

-- Directions (degrees, world atan2(z, x)) kept clear of rim dressing: the swarm's eight ways in, the
-- breach, the cableway's cave.
local function blocked(deg: number, pad: number): boolean
	deg = deg % 360
	if deg > 68 and deg < 112 then
		return true
	end
	local cave = math.deg(math.atan2(84, -120)) % 360
	if math.abs((deg - cave + 180) % 360 - 180) < 12 + pad then
		return true
	end
	for k = 0, 7 do
		if math.abs((deg - k * 45 + 180) % 360 - 180) < 8 + pad then
			return true
		end
	end
	return false
end

function Scene.rim(map, decor, H)
	local m = model(decor, "Rim")
	local terrain = workspace.Terrain
	-- stumps of houses in the wall
	for _, deg in { 22, 58, 120, 162, 198, 243, 258, 292, 334, 352 } do
		local a = math.rad(deg + H.rnd(-3, 3))
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local w, d, h = H.rnd(16, 26), H.rnd(12, 16), H.rnd(18, 38)
		local r = H.boundary(map, a) + d / 2 + H.rnd(2, 5)
		local at = dir * r - Vector3.new(0, H.rnd(2, 6), 0)
		local cf = CFrame.lookAt(at, at - dir) * CFrame.Angles(0, 0, H.rnd(-0.08, 0.08))
		-- the house replaces the earth it stands in
		terrain:FillBlock(cf * CFrame.new(0, h / 2 + 1, 0), Vector3.new(w + 1, h + 2, d + 1), M.Air)
		building(H, m, cf, w, d, h)
	end
	-- the forest along the top of the wall
	local trees = model(m, "Forest")
	for i = 1, 90 do
		local deg = H.rnd(0, 360)
		if not blocked(deg, -6) then
			local a = math.rad(deg)
			local r = H.boundary(map, a) + H.rnd(26, 78)
			local x, z = math.cos(a) * r, math.sin(a) * r
			local y = groundAt(x, z)
			if y > 6 then
				tree(H, trees, Vector3.new(x, y - 0.6, z), H.rnd(16, 30))
			end
		end
	end
	-- poles with sagging wires along the north-east top
	local prev = nil
	for deg = 18, 64, 9 do
		local a = math.rad(deg + H.rnd(-1.5, 1.5))
		local r = H.boundary(map, a) + 34
		local x, z = math.cos(a) * r, math.sin(a) * r
		local base = Vector3.new(x, groundAt(x, z) - 0.5, z)
		local top = base + Vector3.new(H.rnd(-1.2, 1.2), 17, H.rnd(-1.2, 1.2))
		H.rod(m, base, top, 0.8, P.timber, M.Wood)
		local arm = CFrame.lookAt(
			top - Vector3.new(0, 1.2, 0),
			top - Vector3.new(0, 1.2, 0) + Vector3.new(-math.sin(a), 0, math.cos(a))
		)
		block(H, m, arm * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.5, 0.5, 5), P.timber, M.Wood)
		local tip = top - Vector3.new(0, 1.2, 0)
		if prev then
			local n = 8
			local last = prev
			for k = 1, n do
				local t = k / n
				local p = prev:Lerp(tip, t) - Vector3.new(0, math.sin(t * math.pi) * 2.2, 0)
				block(
					H,
					m,
					CFrame.lookAt((p + last) / 2, p),
					Vector3.new(0.12, 0.12, (p - last).Magnitude),
					rgb(30, 28, 26),
					M.SmoothPlastic
				)
				last = p
			end
		end
		prev = tip
	end
end

-- The dead city on the horizon: ruined towers and a crane in the haze, beyond the forest.
function Scene.skyline(map, decor, H)
	local m = model(decor, "Skyline")
	local base = rgb(116, 110, 106)
	for i = 0, 17 do
		local a = (i + H.rnd(-0.3, 0.3)) / 18 * math.pi * 2
		local r = H.rnd(440, 560)
		local w, d, h = H.rnd(26, 46), H.rnd(24, 40), H.rnd(50, 130)
		local at = Vector3.new(math.cos(a) * r, -16, math.sin(a) * r)
		local cf = CFrame.new(at) * CFrame.Angles(0, H.rnd(0, 6.28), 0)
		local shade = base:Lerp(rgb(84, 80, 78), H.rnd(0, 1))
		block(H, m, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), shade)
		-- the floors as dark bands, a broken top askew
		for y = 10, h - 8, 12 do
			block(H, m, cf * CFrame.new(0, y, 0), Vector3.new(w + 0.4, 3, d + 0.4), shade:Lerp(rgb(40, 38, 38), 0.5))
		end
		block(
			H,
			m,
			cf * CFrame.new(w * 0.15, h + 5, 0) * CFrame.Angles(0, 0, H.rnd(-0.25, 0.25)),
			Vector3.new(w * 0.55, 12, d * 0.7),
			shade
		)
	end
	-- a tower crane left standing over the city
	local a = math.rad(118)
	local at = Vector3.new(math.cos(a) * 500, -16, math.sin(a) * 500)
	local steel = rgb(110, 78, 52)
	block(H, m, CFrame.new(at + Vector3.new(0, 70, 0)), Vector3.new(4, 140, 4), steel, M.Metal)
	block(
		H,
		m,
		CFrame.new(at + Vector3.new(20, 138, 0)) * CFrame.Angles(0, 0.4, 0),
		Vector3.new(84, 3, 3),
		steel,
		M.Metal
	)
	block(H, m, CFrame.new(at + Vector3.new(0, 144, 0)), Vector3.new(3, 10, 3), steel, M.Metal)
end

-- The swarm's ways in -------------------------------------------------------------------------------------
-- A storm drain at every entrance but the breach: a concrete pipe end in the wall, wing walls, an apron;
-- dark inside, with the hive's roots spilling over its lip and a warm glow deep in it.
function Scene.drains(map, decor, H)
	local m = model(decor, "Drains")
	local terrain = workspace.Terrain
	for key, s in map.spawns do
		if key == "N" then
			continue
		end
		local a = math.atan2(s.z, s.x)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local rb = H.boundary(map, a)
		local R = 6.2
		local cy = 6.4
		local mouth = dir * (rb + 3) + Vector3.new(0, cy, 0)
		local right = dir:Cross(Vector3.yAxis).Unit
		-- the pipe through the earth (a cylinder whose axis runs along dir), dug wider than the pipe: the
		-- earth's rough faces must not show inside the lining
		terrain:FillCylinder(CFrame.fromMatrix(dir * (rb + 16) + Vector3.new(0, cy, 0), right, dir), 30, R + 1.5, M.Air)
		terrain:FillBlock(
			CFrame.lookAt(dir * (rb - 1) + Vector3.new(0, 9, 0), dir * rb + Vector3.new(0, 9, 0)),
			Vector3.new(2 * R + 10, 16, 6),
			M.Air
		)
		local f = CFrame.lookAt(mouth, mouth - dir) -- LookVector: out of the pipe, into the funnel
		local segs = 16
		local chord = 2 * math.pi * (R + 0.8) / segs + 0.25
		for k = 0, segs - 1 do
			local th = k / segs * math.pi * 2
			local p = block(
				H,
				m,
				f * CFrame.Angles(0, 0, th) * CFrame.new(0, R + 0.8, 1),
				Vector3.new(chord, 1.6, 6),
				P.concrete:Lerp(P.concreteDark, 0.3)
			)
			p.CastShadow = true
		end
		-- the inside of the pipe and the dark it leads into
		for k = 0, segs - 1 do
			local th = k / segs * math.pi * 2
			block(
				H,
				m,
				f * CFrame.Angles(0, 0, th) * CFrame.new(0, R - 0.2, 9),
				Vector3.new(chord, 0.4, 12),
				P.concreteDeep
			).CastShadow =
				true
		end
		local back = H.part(m, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 2 * R, 2 * R),
			CFrame = f * CFrame.new(0, 0, 15) * CFrame.Angles(0, math.pi / 2, 0),
			Color = P.dark,
		})
		back.Name = "Dark"
		-- wing walls and the apron
		for _, sd in { -1, 1 } do
			block(
				H,
				m,
				f * CFrame.new(sd * (R + 4.5), -cy + 3.4, -0.6) * CFrame.Angles(0, sd * 0.35, 0),
				Vector3.new(6, 6.8, 1.6),
				P.concrete
			)
		end
		block(H, m, f * CFrame.new(0, -cy + 0.12, -3), Vector3.new(2 * R + 6, 0.3, 6), P.concreteDark)
		-- the hive's roots spilling over the lip and a few sacs glowing in the dark
		for _ = 1, 6 do
			local th = H.rnd(-1.2, 1.2) + math.pi
			local from = (f * CFrame.Angles(0, 0, th) * CFrame.new(0, R - 0.3, H.rnd(6, 12))).Position
			root(H, m, from, -dir, H.rnd(7, 12), H.rnd(0.4, 0.8), right)
		end
		for i = 1, 3 do
			local cf = f * CFrame.new(H.rnd(-R + 2, R - 2), -R + 1.2, H.rnd(5, 12))
			H.ball(m, cf.Position, H.rnd(0.8, 1.3), P.ember, M.Neon, { Transparency = 0.3 })
		end
		H.light(m, (f * CFrame.new(0, -1, 9)).Position, P.ember, 22, 1.4)
		local vent =
			H.part(m, { Size = Vector3.new(6, 1, 6), CFrame = f * CFrame.new(0, -cy + 1, 2), Transparency = 1 })
		H.spores(vent, P.ember, 2, 0.5, 1.2)
	end
end

-- The floor's old streets: faded lane marks, manholes and broken kerbs where the asphalt shows.
function Scene.streets(map, decor, H)
	local m = model(decor, "Streets")
	for i, r in Scene.Roads do
		local ab = r.b - r.a
		local len = ab.Magnitude
		local u = ab / len
		local side = Vector3.new(-u.Z, 0, u.X)
		local yaw = CFrame.lookAt(Vector3.zero, u)
		local manholes = 0
		for t = 4, len - 4, 7 do
			local p = r.a + u * t
			if not Scene.roadGap(i, t) and not Scene.roadGap(i, t + 3) and H.clearOf(map, p.X, p.Z, 1) then
				local edge = H.boundary(map, math.atan2(p.Z, p.X))
				if p.Magnitude < edge - 4 then
					if H.rnd() < 0.8 then
						block(
							H,
							m,
							CFrame.new(p + Vector3.new(0, 0.03, 0)) * yaw.Rotation,
							Vector3.new(0.45, 0.06, 3.2),
							P.paint,
							M.SmoothPlastic,
							{ Transparency = 0.55 }
						)
					end
					if manholes < 4 and H.rnd() < 0.08 then
						manholes += 1
						H.disc(
							m,
							p + side * r.w * 0.25 + Vector3.new(0, 0.04, 0),
							2.6,
							0.08,
							rgb(56, 54, 52),
							M.DiamondPlate,
							0
						)
					end
					for _, sd in { -1, 1 } do
						if H.rnd() < 0.45 then
							block(
								H,
								m,
								CFrame.new(p + side * sd * (r.w / 2 + 0.4) + Vector3.new(0, 0.15, 0))
									* yaw.Rotation
									* CFrame.Angles(0, H.rnd(-0.05, 0.05), 0),
								Vector3.new(0.8, 0.3, H.rnd(3.5, 6.5)),
								P.concreteDark
							)
						end
					end
				end
			end
		end
	end
end

return Scene
