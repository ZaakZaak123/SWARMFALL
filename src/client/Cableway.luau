--!nonstrict
-- The cableway (DD-065): the one thing both scenes share. The drill in the funnel digs up the buried
-- city; crates of utility ride a cable from it, over the rim, to the shelter. In the funnel the cable
-- leaves the drill; at home the same cable (same posts, same crates with the shelter's lime band)
-- comes in through the gate to the receiving station. A crate sent here is a crate that left the drill.
--
-- Cableway.new(parent, anchors, opts) -> line
--   anchors   cable heads in order of travel (the first is where crates start)
--   opts.posts  { Vector3 } ground points that get a post up to the matching anchor (index = anchor)
--   opts.every  seconds between crates while idle (nil = only crates that are sent)
-- line:send(n, onArrive?, from?)  n crates, a short gap apart, starting `from` studs short of the end
--                          (nil = from the start); onArrive(i, n) when each reaches the end
-- line:update(dt)          move the crates (call every frame while the line is in the world)
-- line:destroy()

local Layout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ShelterLayout"))

local Cableway = {}
Cableway.__index = Cableway

local rgb = Color3.fromRGB
local CABLE = rgb(38, 34, 30)
local POST = rgb(84, 78, 70)
local WOOD = rgb(150, 106, 62)
local BAND = rgb(176, 236, 60) -- the shelter's lime: the same mark on every crate, here and there
local SPEED = 9 -- studs per second along the cable
local HANG = 1.9 -- the crate hangs this far under the cable

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function rod(parent, a: Vector3, b: Vector3, width: number, color: Color3, material)
	local len = (b - a).Magnitude
	return part({
		Size = Vector3.new(width, width, len),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}, parent)
end

-- One crate on its hook: a wooden box with the lime band, the hook rod above it.
local function crateModel(parent)
	local m = Instance.new("Model")
	m.Name = "Crate"
	local box =
		part({ Name = "Box", Size = Vector3.new(2.3, 1.9, 2.3), Color = WOOD, Material = Enum.Material.WoodPlanks }, m)
	local band = part(
		{ Name = "Band", Size = Vector3.new(2.36, 0.42, 2.36), Color = BAND, Material = Enum.Material.SmoothPlastic },
		m
	)
	local hook = part(
		{ Name = "Hook", Size = Vector3.new(0.12, HANG - 0.7, 0.12), Color = CABLE, Material = Enum.Material.Metal },
		m
	)
	m.PrimaryPart = box
	m.Parent = parent
	return { model = m, box = box, band = band, hook = hook }
end

-- A crate standing on the ground (the stack at the terminal): the same box, the same band.
function Cableway.crate(parent: Instance, cf: CFrame)
	local c = crateModel(parent)
	c.hook:Destroy()
	c.box.CastShadow = true
	c.box.CFrame = cf * CFrame.new(0, c.box.Size.Y / 2, 0)
	c.band.CFrame = c.box.CFrame
	return c.model
end

-- The route (DD-075, DD-082): one cable from the drill to the shelter. It leaves the funnel into a cave
-- in its north-west wall, runs under the dead city along an old metro tunnel and comes out of a cave in
-- the grove's hill, straight to the terminal. (Owner playtest: the open wasteland under the cable
-- looked crooked and the ride was long; underground nothing breaks the picture and the way is short.)
-- World points on the arena's side; the shelter's end goes through the plot's frame (DD-087: every plot
-- has its own cave, in the hill between it and the next plot, shared/ShelterLayout.Cave).
-- The post inside the funnel (DD-093): right beside the hero's spawn (Maps playerStart 0, -26), so a ride in
-- ends with the hero hopping off the pallet onto the spot the fight starts from. The span from the cave
-- stays level (DD-091: a climbing span braked on its slope) and keeps clear of the crystals and the
-- tesla towers; from here the freight goes on to the drill's top.
Cableway.ARENA_SIDE = Vector3.new(-10, 14, -22)
Cableway.MOUTH_A = Vector3.new(Layout.ArenaCave.x, 0, Layout.ArenaCave.z) -- the cave in the funnel wall (floor centre)
Cableway.FACING_A = Vector3.new(Layout.ArenaCave.fx, 0, Layout.ArenaCave.fz).Unit -- out of the cave, into the funnel
Cableway.CABLE_H = 13 -- the cable's height over a cave's / the tunnel's floor
-- DD-087: the long run goes under the whole grove, so it keeps below the ground's floor (-12) entirely:
-- nothing has to be dug out along it, only at the two ends.
Cableway.DEPTH = 34

-- The shelter's cave (floor centre) and the way out of it, in world space, for a plot frame.
function Cableway.mouthB(home: CFrame): (Vector3, Vector3)
	local c = Layout.Cave
	return home:PointToWorldSpace(Vector3.new(c.x, 0, c.z)), home:VectorToWorldSpace(Vector3.new(c.fx, 0, c.fz)).Unit
end

-- The tunnel's floor line from cave A to cave B (world): in, down a ramp, the long run, up, out.
function Cableway.tunnelLine(home: CFrame): { Vector3 }
	local a, fa = Cableway.MOUTH_A, Cableway.FACING_A
	local b, fb = Cableway.mouthB(home)
	local down = Vector3.new(0, -Cableway.DEPTH, 0)
	return { a, a - fa * 40, a - fa * 140 + down, b - fb * 140 + down, b - fb * 40, b }
end

-- The cable heads along the tunnel: under the roof, a hanger every ~140 studs on the long run.
function Cableway.tunnelAnchors(home: CFrame): { Vector3 }
	local line = Cableway.tunnelLine(home)
	local up = Vector3.new(0, Cableway.CABLE_H, 0)
	local out = {}
	for i, p in line do
		if i == 4 then
			local from = line[3]
			local n = math.max(1, math.floor((p - from).Magnitude / 140))
			for k = 1, n - 1 do
				table.insert(out, from:Lerp(p, k / n) + up)
			end
		end
		table.insert(out, p + up)
	end
	return out
end

-- A tunnel mouth (DD-082 → DD-091): an old metro portal set into the ground the server dug for it
-- (server/Portal: the hill behind, a cutting in front, the bore). Owner: "make it a real way under the
-- ground". So: a concrete face whose top follows the earth over it, wing walls lining the cutting and
-- stepping down with the slope, a lined tunnel with steel ribs running in to the dark, rails out of it, a
-- lamp over the opening. `at` is the floor centre of the face, `facing` points out of the tunnel. The
-- lining sits in folder "Inner" (a story ride hides it with "Dark": it rides its own tunnel through here).
local CUT_W, CUT_L = 24, 16 -- server/Portal: the cutting
local BORE_D = 13 -- how deep the lining runs (server/Portal digs 16)
local terrainRay = RaycastParams.new()
terrainRay.FilterType = Enum.RaycastFilterType.Include
terrainRay.FilterDescendantsInstances = { workspace.Terrain }

function Cableway.cave(parent: Instance, at: Vector3, facing: Vector3): Folder
	local folder = Instance.new("Folder")
	folder.Name = "CaveMouth"
	local inner = Instance.new("Folder")
	inner.Name = "Inner"
	inner.Parent = folder
	local frame = CFrame.lookAt(at, at + Vector3.new(facing.X, 0, facing.Z)) -- -Z = out of the cave
	local concrete, dark, deep = rgb(146, 140, 130), rgb(104, 99, 94), rgb(58, 55, 52)
	local steel = rgb(78, 66, 56)
	local function at3(x, y, z)
		return frame * CFrame.new(x, y, -z)
	end
	-- the earth's top over a point (local x, z): what the face and the wings follow (nil off the map)
	local function earth(x: number, z: number): number?
		local p = at3(x, 0, z).Position
		local hit = workspace:Raycast(p + Vector3.new(0, 140, 0), Vector3.new(0, -170, 0), terrainRay)
		return if hit then hit.Position.Y - at.Y else nil
	end
	local function slab(size: Vector3, cf: CFrame, color: Color3, mat, shadow: boolean?, into: Instance?)
		local p =
			part({ Size = size, CFrame = cf, Color = color, Material = mat or Enum.Material.Concrete }, into or folder)
		p.CastShadow = shadow == true
		p.CanCollide = shadow == true -- the walls, the face and the wings are solid (DD-091); trim is not
		return p
	end
	-- the darkness further in (and what a crate rides into)
	-- (solid: you may walk in to the dark, not through it)
	part({
		Name = "Dark",
		Size = Vector3.new(19, 19, 1),
		CFrame = at3(0, 9, -BORE_D),
		Color = rgb(5, 5, 7),
		CanCollide = true,
	}, folder)
	-- the lining: walls, roof and floor, a steel rib every four studs, one dim lamp
	local mid = -BORE_D / 2
	for _, x in { -9.6, 9.6 } do
		slab(Vector3.new(1, 18.6, BORE_D), at3(x, 9.3, mid), deep, nil, true, inner)
	end
	slab(Vector3.new(20.2, 1, BORE_D), at3(0, 18.6, mid), deep, nil, true, inner)
	slab(
		Vector3.new(20.2, 1.2, BORE_D + 2),
		at3(0, -0.1, mid), -- (its top a little over the ground: the earth's last voxel must not show)
		rgb(52, 48, 44),
		Enum.Material.Ground,
		false,
		inner
	)
	for d = 3, BORE_D - 2, 4 do
		for _, x in { -8.7, 8.7 } do
			slab(Vector3.new(0.7, 17.4, 0.7), at3(x, 8.7, -d), steel, Enum.Material.Metal, false, inner)
		end
		slab(Vector3.new(18.1, 0.7, 0.7), at3(0, 17.7, -d), steel, Enum.Material.Metal, false, inner)
	end
	local inLamp =
		slab(Vector3.new(0.6, 0.6, 1), at3(8.9, 12, -9), rgb(255, 196, 120), Enum.Material.Neon, false, inner)
	local inLight = Instance.new("PointLight")
	inLight.Color = rgb(255, 186, 120)
	inLight.Range = 14
	inLight.Brightness = 0.8
	inLight.Parent = inLamp
	-- the portal: pilasters and a lintel, proud of the face
	for _, x in { -9.6, 9.6 } do
		slab(Vector3.new(2.4, 18.6, 2.4), at3(x, 9.3, 0.2), dark, nil, true)
	end
	slab(Vector3.new(21.6, 2.6, 2.8), at3(0, 19.2, 0.2), dark, nil, true)
	-- the face: columns whose tops follow the earth behind them (the hill goes on up over the tunnel)
	local cols, width = 6, 30
	local faceTop = {}
	for k = 0, cols - 1 do
		local cx = -width / 2 + (k + 0.5) * width / cols
		local over = math.abs(cx) < 11
		local e = earth(cx, -4) or 22
		local top = math.clamp(e + 0.6, if over then 21.4 else 2, 30)
		local from = if over then 20.4 else 0
		faceTop[k + 1] = top
		if top > from + 0.3 then
			slab(
				Vector3.new(width / cols + 0.05, top - from, 3),
				at3(cx, (from + top) / 2, -1.3),
				concrete:Lerp(dark, (k % 2) * 0.25),
				nil,
				true
			)
			slab(Vector3.new(width / cols + 0.3, 0.5, 3.4), at3(cx, top + 0.25, -1.2), dark, nil, false)
		end
	end
	-- the metro's red «М» on a plate over the lintel (the arena's breach wears the same)
	local plate = slab(Vector3.new(3.4, 3.4, 0.3), at3(0, 22.6, 0.3), rgb(128, 70, 46), Enum.Material.Metal, false)
	if math.min(faceTop[3], faceTop[4]) < 24.6 then
		plate.CFrame = at3(-5.2, 17.2, 1.75) -- a low face: on the pilaster's side instead
		plate.Size = Vector3.new(2.6, 2.6, 0.3)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- the frame looks out of the tunnel
	gui.CanvasSize = Vector2.new(200, 200)
	gui.LightInfluence = 1
	gui.Parent = plate
	local letter = Instance.new("TextLabel")
	letter.BackgroundTransparency = 1
	letter.Size = UDim2.fromScale(1, 1)
	letter.Font = Enum.Font.GothamBlack
	letter.Text = "М"
	letter.TextScaled = true
	letter.TextColor3 = rgb(200, 58, 46)
	letter.Parent = gui
	-- wing walls lining the cutting's earth sides, stepping down with the slope
	for _, s in { -1, 1 } do
		for k = 0, 3 do
			local z = 2 + k * 4
			local e = earth(s * (CUT_W / 2 + 2.5), z) or 4
			local h = math.clamp(e + 0.4, 1.4, faceTop[if s < 0 then 1 else cols])
			slab(Vector3.new(1.4, h, 4.05), at3(s * (CUT_W / 2 - 0.7), h / 2, z), concrete, nil, true)
			slab(Vector3.new(1.8, 0.4, 4.1), at3(s * (CUT_W / 2 - 0.7), h + 0.2, z), dark, nil, false)
		end
	end
	-- the approach: a worn slab in the cutting, the rails running out of the dark across it
	slab(Vector3.new(CUT_W - 2.8, 0.3, CUT_L - 1), at3(0, 0.35, CUT_L / 2), rgb(118, 112, 104), nil, false)
	for _, x in { -2.4, 2.4 } do
		slab(
			Vector3.new(0.35, 0.3, BORE_D + CUT_L - 2),
			at3(x, 0.8, (CUT_L - BORE_D) / 2 - 1),
			rgb(70, 62, 56),
			Enum.Material.Metal,
			false
		)
	end
	for z = -BORE_D + 2, CUT_L - 2, 3 do
		slab(Vector3.new(6.4, 0.2, 0.9), at3(0, 0.6, z), rgb(70, 52, 38), Enum.Material.Wood, false)
	end
	-- a caged lamp under the lintel
	local lamp = part({
		Size = Vector3.new(0.9, 0.7, 0.9),
		CFrame = at3(0, 16.9, 0.9),
		Color = rgb(255, 196, 120),
		Material = Enum.Material.Neon,
	}, folder)
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 196, 130)
	light.Range = 18
	light.Brightness = 1.6
	light.Parent = lamp
	folder.Parent = parent
	return folder
end

-- Sampled cable through the anchors: every span sags a little. The crates' (and a rider's) track.
function Cableway.track(anchors: { Vector3 }): { Vector3 }
	local track = {}
	for i = 1, #anchors - 1 do
		local a, b = anchors[i], anchors[i + 1]
		local len = (b - a).Magnitude
		local sag = math.min(6, len * 0.035)
		local n = math.max(2, math.floor(len / 4))
		for k = 0, n - (if i < #anchors - 1 then 1 else 0) do
			local t = k / n
			table.insert(track, a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0))
		end
	end
	return track
end

function Cableway.new(parent: Instance, anchors: { Vector3 }, opts)
	opts = opts or {}
	local self = setmetatable({}, Cableway)
	local folder = Instance.new("Folder")
	folder.Name = "Cableway"
	folder.Parent = parent
	self.folder = folder
	-- posts
	for i, base in opts.posts or {} do
		local head = anchors[i]
		if base and head then
			rod(folder, base, head + Vector3.new(0, 1.2, 0), 0.7, POST, Enum.Material.Metal)
			-- crossbar and a wheel the cable runs over
			part({
				Size = Vector3.new(2.6, 0.4, 0.5),
				CFrame = CFrame.new(head + Vector3.new(0, 1.2, 0)),
				Color = POST,
				Material = Enum.Material.Metal,
			}, folder)
			local wheel = part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, 1.1, 1.1),
				Color = rgb(60, 56, 52),
				Material = Enum.Material.Metal,
			}, folder)
			wheel.CFrame = CFrame.new(head + Vector3.new(0, 0.55, 0))
		end
	end
	-- the cable: each span sags a little; the sampled points are the crates' track
	local track = Cableway.track(anchors)
	for k = 1, #track - 1 do
		rod(folder, track[k], track[k + 1], 0.22, CABLE, Enum.Material.Metal)
	end
	local dist = { 0 }
	for k = 2, #track do
		dist[k] = dist[k - 1] + (track[k] - track[k - 1]).Magnitude
	end
	self.track = track
	self.dist = dist
	self.length = dist[#dist]
	self.crates = {}
	self.free = {}
	self.queue = 0
	self.queueT = 0
	self.every = opts.every
	self.idleT = (opts.every or 0) * 0.5
	return self
end

function Cableway:at(s: number): (Vector3, Vector3)
	local track, dist = self.track, self.dist
	local lo, hi = 1, #dist
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if dist[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local seg = dist[hi] - dist[lo]
	local t = if seg > 0 then (s - dist[lo]) / seg else 0
	local p = track[lo]:Lerp(track[hi], math.clamp(t, 0, 1))
	return p, (track[hi] - track[lo])
end

local function place(c, pos: Vector3, dir: Vector3, swing: number)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local yaw = if flat.Magnitude > 1e-3 then math.atan2(-flat.X, -flat.Z) else 0
	local top = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(swing, 0, 0)
	c.hook.CFrame = top * CFrame.new(0, -(HANG - 0.7) / 2, 0)
	local boxCf = top * CFrame.new(0, -HANG, 0)
	c.box.CFrame = boxCf
	c.band.CFrame = boxCf
end

function Cableway:spawnCrate(onArrive, from: number?)
	local c = table.remove(self.free) or crateModel(self.folder)
	c.s = if from then math.max(0, self.length - from) else 0
	c.onArrive = onArrive
	c.swing = 0
	table.insert(self.crates, c)
end

function Cableway:send(n: number, onArrive, from: number?)
	self.queue += n
	self.total = n
	self.onArrive = onArrive
	self.from = from
	self.sent = 0
end

function Cableway:update(dt: number)
	if self.queue > 0 then
		self.queueT -= dt
		if self.queueT <= 0 then
			self.queue -= 1
			self.sent = (self.sent or 0) + 1
			local i, n, cb = self.sent, self.total, self.onArrive
			self:spawnCrate(
				if cb
					then function()
						cb(i, n)
					end
					else nil,
				self.from
			)
			self.queueT = 0.55
		end
	elseif self.every then
		self.idleT -= dt
		if self.idleT <= 0 then
			self.idleT = self.every
			self:spawnCrate(nil)
		end
	end
	local now = os.clock()
	local i = 1
	while i <= #self.crates do
		local c = self.crates[i]
		c.s += SPEED * dt
		if c.s >= self.length then
			c.box.CFrame = CFrame.new(0, -500, 0)
			c.band.CFrame = c.box.CFrame
			c.hook.CFrame = c.box.CFrame
			table.insert(self.free, c)
			self.crates[i] = self.crates[#self.crates]
			self.crates[#self.crates] = nil
			if c.onArrive then
				task.spawn(c.onArrive)
			end
		else
			local pos, dir = self:at(c.s)
			place(c, pos, dir, math.sin(now * 2.2 + c.s * 0.1) * 0.08)
			i += 1
		end
	end
end

-- Crates still on the line leave it at once (a story scene rides this cable, DD-076). Queued ones too.
function Cableway:clearCrates()
	for _, c in self.crates do
		c.box.CFrame = CFrame.new(0, -500, 0)
		c.band.CFrame = c.box.CFrame
		c.hook.CFrame = c.box.CFrame
		table.insert(self.free, c)
	end
	table.clear(self.crates)
	self.queue = 0
end

-- The end of the line (where crates arrive).
function Cableway:last(): Vector3
	return self.track[#self.track]
end

function Cableway:destroy()
	self.folder:Destroy()
	self.crates = {}
	self.free = {}
end

return Cableway
