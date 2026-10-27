--!nonstrict
-- «Громобой» (S01, ex-«Гравимолот», DD-092): a giant spectral hammer swung by nobody, the size of the
-- strike's circle, lightning-blue, translucent and shimmering (ForceField shell over a dim neon core). It
-- rears up behind the hero, comes down with a vicious, accelerating swing and slams flat onto the circle,
-- kicks back a little, then melts away. Built from a handful of primitives (no mesh to upload, ~20 parts):
-- a squared head with heavier striking faces, a rune band, a long haft with grip wraps and a pommel.
--
-- Hammer.swing(center, radius, windup, opts) -> handle
--   center   world point of the strike (the circle's centre, ground level)
--   radius   the circle's radius: the head's length is its diameter
--   windup   seconds from now to the impact (the swing is timed to land then)
--   opts.slow  a long, cinematic rear-up (the first strike) instead of the quick one
-- handle.impact()  call when the server's impact arrives (snaps the swing to the ground if it is late)

local RunService = game:GetService("RunService")

local Hammer = {}

local rgb = Color3.fromRGB
local SHELL = rgb(70, 160, 255) -- lightning blue
local CORE = rgb(120, 200, 255)
local BAND = rgb(255, 236, 150)

local function part(parent: Instance, props): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- The model in its own space: the head along X centred on the origin, the haft along +Y from it.
-- Returns the model, its parts with their local offsets and base transparencies.
local function build(L: number)
	local model = Instance.new("Model")
	model.Name = "Gromoboy"
	local pieces = {}
	local function add(shape, size: Vector3, offset: CFrame, color: Color3, material, alpha: number)
		local p = part(model, {
			Shape = shape or Enum.PartType.Block,
			Size = size,
			Color = color,
			Material = material,
			Transparency = alpha,
		})
		table.insert(pieces, { p, offset, alpha })
		return p
	end
	local B, Cyl, Ball = Enum.PartType.Block, Enum.PartType.Cylinder, Enum.PartType.Ball
	local FF, NEON = Enum.Material.ForceField, Enum.Material.Neon
	local h = L * 0.36 -- the head's cross-section
	-- the head: a shell, a dim core inside it, heavier striking faces with a bevelled rim
	add(B, Vector3.new(L * 0.8, h, h), CFrame.identity, SHELL, FF, 0.05)
	add(B, Vector3.new(L * 0.74, h * 0.72, h * 0.72), CFrame.identity, CORE, NEON, 0.86)
	for _, s in { -1, 1 } do
		add(B, Vector3.new(L * 0.1, h * 1.18, h * 1.18), CFrame.new(s * L * 0.45, 0, 0), SHELL, FF, 0.0)
		add(B, Vector3.new(L * 0.04, h * 1.02, h * 1.02), CFrame.new(s * L * 0.5, 0, 0), CORE, NEON, 0.45)
		-- the rim's four bevels (a chamfer on the face's edges)
		for k = 0, 3 do
			local a = k * math.pi / 2
			add(
				B,
				Vector3.new(L * 0.1, h * 0.2, h * 1.05),
				CFrame.new(s * L * 0.43, 0, 0)
					* CFrame.Angles(a, 0, 0)
					* CFrame.new(0, h * 0.58, 0)
					* CFrame.Angles(0, 0, s * 0.35),
				SHELL,
				FF,
				0.1
			)
		end
	end
	-- the rune band round the middle, two studs on each side
	add(B, Vector3.new(L * 0.14, h * 1.08, h * 1.08), CFrame.identity, BAND, NEON, 0.55)
	for _, sz in { -1, 1 } do
		for _, sx in { -1, 1 } do
			add(Ball, Vector3.one * h * 0.16, CFrame.new(sx * L * 0.22, 0, sz * h * 0.52), CORE, NEON, 0.3)
		end
	end
	-- the haft: a collar at the head, the shaft, three grip wraps, the pommel
	local haft = L * 1.15
	add(
		Cyl,
		Vector3.new(h * 0.4, h * 0.5, h * 0.5),
		CFrame.new(0, h * 0.62, 0) * CFrame.Angles(0, 0, math.pi / 2),
		SHELL,
		FF,
		0.05
	)
	add(
		Cyl,
		Vector3.new(haft, h * 0.26, h * 0.26),
		CFrame.new(0, h * 0.5 + haft / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		SHELL,
		FF,
		0.08
	)
	add(
		Cyl,
		Vector3.new(haft * 0.96, h * 0.12, h * 0.12),
		CFrame.new(0, h * 0.5 + haft / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		CORE,
		NEON,
		0.5
	)
	for k = 0, 2 do
		local y = h * 0.5 + haft * (0.72 + k * 0.08)
		add(
			Cyl,
			Vector3.new(haft * 0.04, h * 0.32, h * 0.32),
			CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
			BAND,
			NEON,
			0.6
		)
	end
	add(Ball, Vector3.one * h * 0.46, CFrame.new(0, h * 0.5 + haft + h * 0.12, 0), SHELL, FF, 0.05)
	local glow = Instance.new("PointLight")
	glow.Color = SHELL
	glow.Range = math.min(60, L * 2.2)
	glow.Brightness = 0
	glow.Shadows = false
	glow.Parent = pieces[2][1]
	return model, pieces, glow, haft + h * 0.6
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function Hammer.swing(center: Vector3, radius: number, windup: number, opts)
	opts = opts or {}
	local L = radius * 2 * 0.95
	local model, pieces, glow, reach = build(L)
	-- the pose: the head lies across the screen (world X), the haft leans away from the camera (+Z) and
	-- up; it swings about the X axis through the pommel's end
	local headY = L * 0.36 * 0.5
	local lean = math.rad(48)
	local up = Vector3.new(0, math.cos(lean), math.sin(lean)) -- along the haft at impact
	local headAt = center + Vector3.new(0, headY, 0)
	local pivot = headAt + up * reach
	-- the haft's rest frame at impact: Y along `up`, X world X
	local rest = CFrame.fromMatrix(headAt, Vector3.xAxis, up)
	local function pose(angle: number): CFrame
		-- rotate the whole hammer about the world X axis through the pivot (positive: the head rises
		-- over the pivot, reared up)
		local turn = CFrame.new(pivot) * CFrame.Angles(angle, 0, 0) * CFrame.new(-pivot)
		return turn * rest
	end
	local slow = opts.slow == true
	local REAR = math.rad(if slow then 150 else 125) -- reared up, the head high over the haft
	local t0 = os.clock()
	local impactAt = t0 + windup
	local landed = false
	local done = false
	local alphaMul = 1
	local function place(cf: CFrame)
		for _, pc in pieces do
			local p, off, a = pc[1], pc[2], pc[3]
			p.CFrame = cf * off
			p.Transparency = 1 - (1 - a) * alphaMul
		end
	end
	place(pose(REAR))
	model.Parent = workspace
	local handle = {}
	function handle.impact()
		if not landed then
			impactAt = math.min(impactAt, os.clock())
		end
	end
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local angle
		if now < impactAt then
			local span = impactAt - t0
			local k = math.clamp((now - t0) / math.max(0.01, span), 0, 1)
			alphaMul = smooth(math.min(1, (now - t0) / (if slow then 0.6 else 0.12)))
			if slow then
				-- a slow rear-up with a breath at the top, then the strike in its last 0.28 s
				local strike = math.max(0, (span - 0.28) / span)
				if k < strike then
					local r = k / strike
					angle = REAR * (0.82 + 0.18 * smooth(r)) + math.sin(now * 9) * 0.01 * r
				else
					local s = (k - strike) / (1 - strike)
					angle = REAR * (1 - s * s * s)
				end
			else
				-- a short pull back, then the head comes down accelerating
				local s = k
				angle = REAR * (1 + 0.08 * math.sin(math.min(1, s * 2.2) * math.pi)) * (1 - s * s * s)
			end
			glow.Brightness = 1.5 + 3 * k
		else
			if not landed then
				landed = true
			end
			local after = now - impactAt
			-- a kick back off the ground, settling, then the hammer melts away into the dust
			angle = math.sin(math.min(1, after / 0.22) * math.pi) * math.rad(9) * math.exp(-after * 3)
			glow.Brightness = math.max(0, 5 * (1 - after / 0.6))
			local fadeFrom = if slow then 0.7 else 0.3
			alphaMul = 1 - smooth((after - fadeFrom) / 0.45)
			if after > fadeFrom + 0.5 then
				done = true
			end
		end
		place(pose(angle) * CFrame.new(0, if landed then -smooth((now - impactAt - 0.3) / 0.8) * 2 else 0, 0))
		if done then
			conn:Disconnect()
			model:Destroy()
		end
	end)
	-- the head's centre in the air (for the lightning that gathers on it)
	function handle.head(): Vector3
		local first = pieces[1][1]
		return first.Position
	end
	return handle
end

return Hammer
