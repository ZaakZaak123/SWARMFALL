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
