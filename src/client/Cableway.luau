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
Cableway.ARENA_SIDE = Vector3.new(-104, 20, 34) -- post inside the funnel, west of the drill
Cableway.MOUTH_A = Vector3.new(-120, 0, 84) -- the cave in the funnel wall (floor centre)
Cableway.FACING_A = Vector3.new(0.42, 0, -0.91).Unit -- out of the cave, into the funnel
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

-- A cave mouth (DD-082): a timbered opening into darkness in a heap of rock, the rails running out of it
-- and a lamp over it. `at` is the floor centre, `facing` points out of the cave.
function Cableway.cave(parent: Instance, at: Vector3, facing: Vector3): Folder
	local folder = Instance.new("Folder")
	folder.Name = "CaveMouth"
	local frame = CFrame.lookAt(at, at + Vector3.new(facing.X, 0, facing.Z)) -- -Z = out of the cave
	local rock, timber = rgb(138, 128, 116), rgb(110, 80, 52)
	local function at3(x, y, z)
		return frame * CFrame.new(x, y, -z)
	end
	-- the darkness: what you see into the hill (and what a crate rides into)
	part({ Name = "Dark", Size = Vector3.new(16, 16, 1), CFrame = at3(0, 8, -1.6), Color = rgb(5, 5, 7) }, folder)
	-- the timbering
	for _, x in { -7.6, 7.6 } do
		part({
			Size = Vector3.new(1.3, 16.6, 1.3),
			CFrame = at3(x, 8.3, 0),
			Color = timber,
			Material = Enum.Material.WoodPlanks,
		}, folder)
	end
	part({
		Size = Vector3.new(17.6, 1.5, 1.5),
		CFrame = at3(0, 16.6, 0),
		Color = timber,
		Material = Enum.Material.WoodPlanks,
	}, folder)
	-- the rock heaped round it
	local rng = Random.new(math.floor(at.X * 7 + at.Z * 3))
	local rocks = {
		{ -11, 3, 7 },
		{ -12, 9, 8 },
		{ -11, 15, 7 },
		{ 11, 3, 7 },
		{ 12, 9, 8 },
		{ 11, 15, 7 },
		{ -7, 20, 8 },
		{ 0, 21, 9 },
		{ 7, 20, 8 },
		{ -15, 1, 6 },
		{ 15, 1, 6 },
		{ 0, 25, 7 },
	}
	for _, r in rocks do
		local d = r[3] * rng:NextNumber(1.1, 1.6)
		local p = part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * d,
			CFrame = at3(r[1] + rng:NextNumber(-1, 1), r[2], rng:NextNumber(-3, -0.5)),
			Color = rock:Lerp(rgb(104, 96, 88), rng:NextNumber()),
			Material = Enum.Material.Rock,
		}, folder)
		p.CastShadow = true
	end
	-- the rails out of the tunnel and a lamp over the opening
	for _, x in { -2.4, 2.4 } do
		part({
			Size = Vector3.new(0.35, 0.3, 10),
			CFrame = at3(x, 0.15, 4.5),
			Color = rgb(70, 62, 56),
			Material = Enum.Material.Metal,
		}, folder)
	end
	local lamp = part({
		Size = Vector3.new(0.9, 0.7, 0.9),
		CFrame = at3(0, 15, 1.2),
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
