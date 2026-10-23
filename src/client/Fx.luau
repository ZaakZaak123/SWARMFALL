--!nonstrict
-- Pooled combat FX: tracers, lightning arcs, explosions, ground telegraphs with timing fill, acid
-- puddles, particles, splats, damage numbers, XP orbs, spit projectiles. Zero per-shot Instance churn.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Codec = require(Shared:WaitForChild("Codec"))
local Settings = require(script.Parent.Settings)
local Theme = require(script.Parent.Theme)

local SH = Codec.Shape
local rgb = Color3.fromRGB
local HIDDEN = CFrame.new(0, -400, 0)
local CYL_UP = CFrame.Angles(0, 0, math.pi / 2)

local Fx = {}

local folder: Folder
local pools = { block = {}, cyl = {}, ball = {} }
local active = {}
local emitHost: Part
local emitters = {}
local lights = {}
local lightIndex = 0
local numberAnchor: Part
local numberPool = {}
local numberIndex = 0
local orbs = {}
local splats = {}

local function newPart(kind: string): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif kind == "ball" then
		p.Shape = Enum.PartType.Ball
	end
	p.CFrame = HIDDEN
	p.Parent = folder
	return p
end

local function take(kind: string): Part
	local p = table.remove(pools[kind])
	if not p then
		p = newPart(kind)
	end
	return p
end

local function give(kind: string, p: Part)
	p.CFrame = HIDDEN
	p.Material = Enum.Material.Neon
	table.insert(pools[kind], p)
end

-- Effect: { t, life, update(fx, k, dt) -> nil, parts = {{kind, part}} }
local liveParts = 0
local function spawn(life: number, update, parts)
	local e = { t = 0, life = life, update = update, parts = parts }
	table.insert(active, e)
	liveParts += #parts
	return e
end

-- Pooled parts currently driven by effects. Optional / cosmetic effects check Fx.busy() and skip
-- themselves under load, so a long burst into a dense swarm never grows the pool without bound.
function Fx.busy(extra: number?): boolean
	return liveParts + (extra or 0) > Settings.Budget.fxParts[Settings.quality]
end
function Fx.stats()
	return { live = liveParts, effects = #active, pooled = #pools.block + #pools.cyl + #pools.ball }
end

local function flatCyl(p: Part, x: number, y: number, z: number, diameter: number, thickness: number?)
	p.Size = Vector3.new(thickness or 0.05, diameter, diameter)
	p.CFrame = CFrame.new(x, y, z) * CYL_UP
end

-- Round tube between a and b (cylinder axis is X).
local TUBE = CFrame.Angles(0, math.pi / 2, 0)
local function tube(p: Part, a: Vector3, b: Vector3, width: number)
	local d = (b - a).Magnitude
	p.Size = Vector3.new(math.max(0.05, d), width, width)
	p.CFrame = CFrame.lookAt((a + b) / 2, b) * TUBE
end

local function segment(p: Part, a: Vector3, b: Vector3, width: number)
	local d = (b - a).Magnitude
	p.Size = Vector3.new(width, width, math.max(0.05, d))
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
end

-- Init --------------------------------------------------------------------------------------------
local function emitter(name: string, props)
	local att = Instance.new("Attachment")
	att.Name = name
	att.Parent = emitHost
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LockedToPart = false
	e.LightEmission = 1
	e.Rate = 0
	for k, v in props do
		e[k] = v
	end
	e.Parent = att
	emitters[name] = { att = att, e = e }
end

function Fx.init()
	folder = Instance.new("Folder")
	folder.Name = "FxView"
	folder.Parent = workspace
	for _ = 1, 60 do
		table.insert(pools.block, newPart("block"))
	end
	for _ = 1, 20 do
		table.insert(pools.cyl, newPart("cyl"))
		table.insert(pools.ball, newPart("ball"))
	end
	emitHost = Instance.new("Part")
	emitHost.Name = "EmitHost"
	emitHost.Anchored = true
	emitHost.CanCollide = false
	emitHost.CanQuery = false
	emitHost.Transparency = 1
	emitHost.Size = Vector3.one
	emitHost.CFrame = CFrame.new()
	emitHost.Parent = folder
	local P = "rbxasset://textures/particles/"
	local function seq(a, b)
		return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
	end
	local function goo(name, color)
		emitter(name, {
			Texture = P .. "sparkles_main.dds",
			Color = ColorSequence.new(color),
			Size = seq(0.9, 0),
			Lifetime = NumberRange.new(0.25, 0.5),
			Speed = NumberRange.new(14, 30),
			SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(0, -70, 0),
			Drag = 3,
			LightEmission = 0.6,
		})
	end
	local function spark(name, color, size, speed, spread, life)
		emitter(name, {
			Texture = P .. "sparkles_main.dds",
			Color = ColorSequence.new(color),
			Size = seq(size, 0),
			Lifetime = NumberRange.new(life * 0.5, life),
			Speed = NumberRange.new(speed * 0.5, speed),
			SpreadAngle = Vector2.new(spread, spread),
			Acceleration = Vector3.new(0, -50, 0),
			Drag = 5,
		})
	end
	-- Directional impact sparks (aimed with Fx.emit's dir)
	spark("hitCyan", rgb(160, 250, 255), 0.55, 46, 38, 0.28)
	spark("hitOrange", rgb(255, 180, 80), 0.6, 40, 45, 0.3)
	spark("hitViolet", rgb(220, 150, 255), 0.6, 36, 50, 0.3)
	spark("hitGold", rgb(255, 225, 120), 0.8, 60, 30, 0.4)
	spark("hitWhite", rgb(255, 255, 255), 0.45, 40, 55, 0.25)
	emitter("ember", {
		Texture = P .. "sparkles_main.dds",
		Color = ColorSequence.new(rgb(255, 200, 90), rgb(255, 70, 20)),
		Size = seq(0.5, 0),
		Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(6, 18),
		SpreadAngle = Vector2.new(50, 50),
		Acceleration = Vector3.new(0, 10, 0),
		Drag = 2,
	})
	emitter("dust", {
		Texture = P .. "smoke_main.dds",
		Color = ColorSequence.new(rgb(120, 112, 100)),
		Size = seq(1.2, 3.2),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(70, 70),
		Transparency = seq(0.45, 1),
		LightEmission = 0,
		Drag = 4,
		Acceleration = Vector3.new(0, 3, 0),
	})
	emitter("steam", {
		Texture = P .. "smoke_main.dds",
		Color = ColorSequence.new(rgb(225, 225, 240)),
		Size = seq(0.5, 2.2),
		Lifetime = NumberRange.new(0.35, 0.7),
		Speed = NumberRange.new(5, 11),
		SpreadAngle = Vector2.new(18, 18),
		Transparency = seq(0.35, 1),
		LightEmission = 0.1,
		Drag = 3,
		Acceleration = Vector3.new(0, 6, 0),
	})
	emitter("muzzleSmoke", {
		Texture = P .. "smoke_main.dds",
		Color = ColorSequence.new(rgb(150, 150, 160)),
		Size = seq(0.6, 2.6),
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(3, 9),
		SpreadAngle = Vector2.new(25, 25),
		Transparency = seq(0.5, 1),
		LightEmission = 0,
		Drag = 4,
		Acceleration = Vector3.new(0, 5, 0),
	})
	emitter("sparkCyan", {
		Texture = P .. "sparkles_main.dds",
		Color = ColorSequence.new(rgb(140, 250, 255)),
		Size = seq(0.6, 0),
		Lifetime = NumberRange.new(0.12, 0.25),
		Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(70, 70),
		Drag = 6,
	})
	emitter("sparkGold", {
		Texture = P .. "sparkles_main.dds",
		Color = ColorSequence.new(rgb(255, 210, 90)),
		Size = seq(0.9, 0),
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(20, 45),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
	})
	goo("goo1", rgb(255, 120, 50))
	goo("goo2", rgb(220, 90, 255))
	goo("goo3", rgb(170, 255, 80))
	goo("goo4", rgb(120, 160, 220))
	goo("goo5", rgb(255, 200, 60))
	goo("goo6", rgb(200, 120, 230))
	goo("goo7", rgb(170, 255, 80))
	emitter("fire", {
		Texture = P .. "fire_main.dds",
		Color = ColorSequence.new(rgb(255, 170, 60), rgb(255, 60, 20)),
		Size = seq(2.2, 0.4),
		Lifetime = NumberRange.new(0.3, 0.55),
		Speed = NumberRange.new(4, 12),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 18, 0),
		Transparency = seq(0.1, 1),
	})
	emitter("smoke", {
		Texture = P .. "smoke_main.dds",
		Color = ColorSequence.new(rgb(60, 60, 70)),
		Size = seq(3, 7),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180),
		Transparency = seq(0.5, 1),
		LightEmission = 0,
		Acceleration = Vector3.new(0, 4, 0),
	})
	emitter("shock", {
		Texture = P .. "explosion01_shockwave_main.dds",
		Color = ColorSequence.new(rgb(255, 230, 160)),
		Size = seq(2, 16),
		Lifetime = NumberRange.new(0.3, 0.3),
		Speed = NumberRange.new(0, 0),
		Transparency = seq(0.2, 1),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
	})
	for i = 1, 6 do
		local holder = newPart("ball")
		holder.Transparency = 1
		holder.Size = Vector3.one * 0.1
		local l = Instance.new("PointLight")
		l.Range = 0
		l.Brightness = 3
		l.Shadows = false
		l.Parent = holder
		lights[i] = { holder = holder, light = l, t = 1, life = 1 }
	end
	numberAnchor = Instance.new("Part")
	numberAnchor.Name = "NumberAnchor"
	numberAnchor.Anchored = true
	numberAnchor.CanCollide = false
	numberAnchor.CanQuery = false
	numberAnchor.Transparency = 1
	numberAnchor.Size = Vector3.one * 0.1
	numberAnchor.CFrame = CFrame.new()
	numberAnchor.Parent = folder
	for i = 1, 36 do
		local gui = Instance.new("BillboardGui")
		gui.Adornee = numberAnchor
		gui.AlwaysOnTop = true
		gui.Size = UDim2.fromOffset(120, 40)
		gui.LightInfluence = 0
		gui.Enabled = false
		gui.Parent = numberAnchor
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Theme.F.numHeavy
		label.TextScaled = true
		label.TextStrokeTransparency = 0.2
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.Parent = gui
		numberPool[i] = { gui = gui, label = label, t = 1, life = 0, pos = Vector3.zero, vel = Vector3.zero }
	end
end

local UP_TO_DIR = CFrame.Angles(-math.pi / 2, 0, 0)

-- dir (optional) aims the emitter's cone; default is straight up.
function Fx.emit(name: string, pos: Vector3, count: number, dir: Vector3?)
	local q = Settings.quality
	if q == 1 and name ~= "shock" then
		count = math.ceil(count * 0.3)
	elseif q == 2 then
		count = math.ceil(count * 0.6)
	end
	local em = emitters[name]
	if em and count > 0 then
		if dir and dir.Magnitude > 1e-3 then
			em.att.WorldCFrame = CFrame.lookAt(pos, pos + dir) * UP_TO_DIR
		else
			em.att.WorldCFrame = CFrame.new(pos)
		end
		em.e:Emit(count)
	end
end

function Fx.light(pos: Vector3, color: Color3, range: number, life: number)
	if Settings.quality < 2 then
		return
	end
	lightIndex = lightIndex % #lights + 1
	local l = lights[lightIndex]
	l.holder.CFrame = CFrame.new(pos)
	l.light.Color = color
	l.light.Range = range
	l.light.Brightness = 3
	l.t = 0
	l.life = life
	l.range = range
end

-- Tracers & arcs ------------------------------------------------------------------------------------
function Fx.tracer(a: Vector3, b: Vector3, color: Color3, width: number, life: number)
	local p = take("block")
	p.Color = color
	p.Transparency = 0
	segment(p, a, b, width)
	spawn(life, function(_, k)
		p.Transparency = k
		local s = p.Size
		p.Size = Vector3.new(width * (1 - k * 0.7), width * (1 - k * 0.7), s.Z)
	end, { { "block", p } })
end

-- Explosions ----------------------------------------------------------------------------------------
function Fx.boom(pos: Vector3, radius: number, color: Color3)
	local ball = take("ball")
	ball.Color = color
	ball.Transparency = 0.1
	ball.Size = Vector3.one * radius * 0.4
	ball.CFrame = CFrame.new(pos)
	local ring = take("cyl")
	ring.Color = color
	ring.Transparency = 0.2
	flatCyl(ring, pos.X, 0.12, pos.Z, radius * 0.3, 0.1)
	spawn(0.32, function(_, k)
		local e = 1 - (1 - k) ^ 3
		ball.Size = Vector3.one * radius * (0.4 + 1.3 * e)
		ball.Transparency = 0.1 + 0.9 * k
		flatCyl(ring, pos.X, 0.12, pos.Z, radius * 2 * (0.3 + 0.8 * e), 0.1)
		ring.Transparency = 0.2 + 0.8 * k
	end, { { "ball", ball }, { "cyl", ring } })
	Fx.emit("sparkGold", pos + Vector3.yAxis, math.floor(radius * 1.5))
	if radius >= 8 then
		Fx.emit("smoke", pos + Vector3.yAxis * 2, 4)
	end
	Fx.light(pos + Vector3.yAxis * 3, color, radius * 3, 0.3)
end

-- Spore pod (DD-033): a glowing seed falls from the sky on a slant, slams into the ground and bursts.
-- The swarm arrives where pods land; the fall itself (~0.9 s) is the warning. big = elites / bosses.
local POD_SHELL = Color3.fromRGB(255, 120, 60)
local POD_CORE = Color3.fromRGB(255, 220, 140)
function Fx.pod(x: number, z: number, big: boolean?)
	if Fx.busy(4) then
		return
	end
	local size = if big then 5 else 2.6
	local fall = if big then 1.2 else 0.85
	local landing = Vector3.new(x, size * 0.4, z)
	local from = landing + Vector3.new(math.random(-30, 30), 120, math.random(10, 40))
	local shell = take("ball")
	shell.Color = POD_SHELL
	shell.Material = Enum.Material.Neon
	shell.Transparency = 0
	shell.Size = Vector3.one * size
	local trail = take("block")
	trail.Color = POD_CORE
	trail.Transparency = 0.35
	local mark = take("cyl")
	mark.Color = POD_SHELL
	mark.Transparency = 1
	spawn(fall, function(_, k)
		local e = k * k
		local pos = from:Lerp(landing, e)
		shell.CFrame = CFrame.new(pos)
		local back = (from - landing).Unit * (6 + 14 * k)
		segment(trail, pos, pos + back, size * 0.55)
		-- landing mark grows as the pod nears
		flatCyl(mark, x, 0.1, z, size * (1.2 + k * 1.6), 0.06)
		mark.Transparency = 0.9 - 0.55 * k
	end, { { "ball", shell }, { "block", trail }, { "cyl", mark } }).done = function()
		Fx.boom(Vector3.new(x, 0.5, z), if big then 9 else 4.5, POD_SHELL)
		Fx.emit("dust", Vector3.new(x, 0.6, z), if big then 8 else 4)
		if Fx.onPodLanded then
			Fx.onPodLanded(Vector3.new(x, 0, z), big)
		end
	end
end

function Fx.shockwave(pos: Vector3, radius: number, color: Color3, life: number?)
	local ring = take("cyl")
	ring.Color = color
	ring.Transparency = 0.1
	spawn(life or 0.5, function(_, k)
		local e = 1 - (1 - k) ^ 2
		flatCyl(ring, pos.X, 0.15, pos.Z, radius * 2 * e, 0.15)
		ring.Transparency = 0.1 + 0.9 * k
	end, { { "cyl", ring } })
end

-- Telegraphs: outline + fill that completes exactly when the attack lands ----------------------------
function Fx.telegraph(shape: number, x: number, z: number, dx: number, dz: number, a: number, b: number, duration: number, color: Color3, activeTime: number)
	local parts = {}
	local y = 0.09
	local yaw = math.atan2(dx, dz)
	if shape == SH.CIRCLE then
		local outline = take("cyl")
		outline.Color = color
		outline.Transparency = 0.7
		flatCyl(outline, x, y, z, a * 2, 0.04)
		local fill = take("cyl")
		fill.Color = color
		fill.Transparency = 0.45
		local edge = take("cyl")
		edge.Color = color
		edge.Transparency = 0.1
		flatCyl(edge, x, y - 0.01, z, a * 2 + 0.5, 0.03)
		parts = { { "cyl", outline }, { "cyl", fill }, { "cyl", edge } }
		local total = duration + activeTime
		spawn(total, function(_, k, _, t)
			if t < duration then
				local f = t / duration
				flatCyl(fill, x, y + 0.01, z, a * 2 * f, 0.05)
				outline.Transparency = 0.7 - 0.2 * math.sin(t * 20)
			else
				-- active acid pool
				local f = (t - duration) / math.max(0.01, activeTime)
				flatCyl(fill, x, y + 0.01, z, a * 2, 0.05)
				fill.Transparency = 0.3 + 0.15 * math.sin(t * 12) + f * 0.5
				outline.Transparency = 0.5 + f * 0.5
				edge.Transparency = 0.2 + f * 0.8
			end
		end, parts)
	elseif shape == SH.LINE then
		local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
		local outline = take("block")
		outline.Color = color
		outline.Transparency = 0.72
		outline.Size = Vector3.new(b, 0.04, a)
		outline.CFrame = cf * CFrame.new(0, 0, a / 2)
		local fill = take("block")
		fill.Color = color
		fill.Transparency = 0.4
		local edgeL, edgeR = take("block"), take("block")
		for i, e in { edgeL, edgeR } do
			e.Color = color
			e.Transparency = 0.1
			e.Size = Vector3.new(0.25, 0.05, a)
			e.CFrame = cf * CFrame.new((if i == 1 then -1 else 1) * b / 2, 0.01, a / 2)
		end
		parts = { { "block", outline }, { "block", fill }, { "block", edgeL }, { "block", edgeR } }
		spawn(duration + activeTime, function(_, k, _, t)
			if t < duration then
				local f = t / duration
				fill.Size = Vector3.new(b, 0.05, math.max(0.05, a * f))
				fill.CFrame = cf * CFrame.new(0, 0.01, a * f / 2)
			else
				local f = (t - duration) / math.max(0.01, activeTime)
				fill.Size = Vector3.new(b, 0.05, a)
				fill.CFrame = cf * CFrame.new(0, 0.01, a / 2)
				fill.Transparency = 0.3 + 0.15 * math.sin(t * 12) + f * 0.5
				outline.Transparency = 0.5 + f * 0.5
				edgeL.Transparency = 0.2 + f * 0.8
				edgeR.Transparency = edgeL.Transparency
			end
		end, parts)
	elseif shape == SH.CONE then
		local slices = if Settings.quality >= 2 then 11 else 7
		local half = math.rad(b) / 2
		local fills = {}
		for i = 0, slices - 1 do
			local ang = yaw - half + (i + 0.5) / slices * half * 2
			local w = a * (half * 2 / slices) * 1.05
			local o = take("block")
			o.Color = color
			o.Transparency = 0.72
			o.Size = Vector3.new(w, 0.04, a)
			local scf = CFrame.new(x, y, z) * CFrame.Angles(0, ang, 0)
			o.CFrame = scf * CFrame.new(0, 0, a / 2)
			local f = take("block")
			f.Color = color
			f.Transparency = 0.4
			f.CFrame = HIDDEN
			table.insert(parts, { "block", o })
			table.insert(parts, { "block", f })
			table.insert(fills, { f, scf, w })
		end
		spawn(duration, function(_, k)
			for _, entry in fills do
				local len = math.max(0.05, a * k)
				entry[1].Size = Vector3.new(entry[3] * (0.3 + 0.7 * k), 0.05, len)
				entry[1].CFrame = entry[2] * CFrame.new(0, 0.01, len / 2)
			end
		end, parts)
	end
end

-- Spit projectile -------------------------------------------------------------------------------------
function Fx.spit(from: Vector3, to: Vector3, flight: number)
	local ball = take("ball")
	ball.Color = rgb(170, 255, 80)
	ball.Transparency = 0
	ball.Size = Vector3.one * 1.4
	spawn(flight, function(_, k)
		local pos = from:Lerp(to, k) + Vector3.yAxis * (math.sin(k * math.pi) * 14 + 2 * (1 - k))
		ball.CFrame = CFrame.new(pos)
	end, { { "ball", ball } })
end

-- Splats & numbers ----------------------------------------------------------------------------------
function Fx.splat(pos: Vector3, color: Color3, size: number)
	local cap = if Settings.quality >= 3 then 40 elseif Settings.quality == 2 then 18 else 0
	if cap == 0 then
		return
	end
	local p
	if #splats >= cap then
		p = table.remove(splats, 1)
	else
		p = take("cyl")
	end
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = 0.25
	flatCyl(p, pos.X + (math.random() - 0.5), 0.06 + math.random() * 0.01, pos.Z + (math.random() - 0.5), size, 0.03)
	table.insert(splats, p)
	local born = os.clock()
	p:SetAttribute("Born", born)
	task.delay(5, function()
		local idx = table.find(splats, p)
		if idx and p:GetAttribute("Born") == born then
			table.remove(splats, idx)
			give("cyl", p)
		end
	end)
end

function Fx.number(pos: Vector3, amount: number, color: Color3, big: boolean)
	if not Settings.numbers then
		return
	end
	numberIndex = numberIndex % #numberPool + 1
	local n = numberPool[numberIndex]
	n.t = 0
	n.life = if big then 0.75 else 0.55
	n.pos = pos + Vector3.new((math.random() - 0.5) * 1.5, 2, (math.random() - 0.5) * 1.5)
	n.vel = Vector3.new((math.random() - 0.5) * 6, 14, 0)
	n.label.Text = tostring(math.floor(amount + 0.5))
	n.label.TextColor3 = color
	local s = math.clamp(0.7 + amount / 120, 0.7, 1.6) * (if big then 1.5 else 1)
	n.size = s
	n.gui.Size = UDim2.fromOffset(70 * s, 26 * s)
	n.gui.Enabled = true
end

-- Orbs ----------------------------------------------------------------------------------------------
local ORB_COLORS = { [0] = rgb(84, 238, 255), [1] = rgb(110, 255, 140), [2] = rgb(200, 120, 255) }

function Fx.orb(id: number, x: number, z: number, kind: number, value: number)
	local p = take(if kind == 0 then "block" else "ball")
	local color = ORB_COLORS[kind]
	local size = 0.8
	if kind == 0 then
		if value >= 20 then
			color, size = rgb(255, 200, 60), 1.6
		elseif value >= 5 then
			color, size = rgb(190, 120, 255), 1.2
		end
	else
		size = 1.8
	end
	p.Color = color
	p.Transparency = 0
	p.Size = Vector3.one * size
	orbs[id] = { p = p, kind = if kind == 0 then "block" else "ball", x = x, z = z, born = os.clock(), phase = math.random() * 6, y = 0 }
	Fx.emit("sparkCyan", Vector3.new(x, 1, z), 2)
end

function Fx.collectOrb(id: number, target: () -> Vector3?)
	local o = orbs[id]
	if not o then
		return
	end
	orbs[id] = nil
	local start = o.p.Position
	spawn(0.22, function(_, k)
		local goal = target() or start
		o.p.CFrame = CFrame.new(start:Lerp(goal + Vector3.yAxis, k * k)) * CFrame.Angles(k * 6, k * 9, 0)
		o.p.Size = o.p.Size * (1 - k * 0.05)
	end, { { o.kind, o.p } })
end

function Fx.clearOrbs()
	for id, o in orbs do
		give(o.kind, o.p)
		orbs[id] = nil
	end
end

function Fx.orbIds()
	return orbs
end

-- Weapon presentation -----------------------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)

local function rnd(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function basis(dir: Vector3): (Vector3, Vector3)
	local right = dir:Cross(Vector3.yAxis)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
	return right, right:Cross(dir).Unit
end

-- Muzzle flash: cf = muzzle CFrame (barrel along -Z). Styles: star, blast, rail.
function Fx.muzzle(cf: CFrame, style: string, color: Color3, size: number, life: number?)
	life = life or 0.05
	local parts = {}
	local roll = math.random() * math.pi
	local k = size * rnd(0.85, 1.15)
	local core = take("ball")
	core.Color = WHITE
	core.Transparency = 0
	table.insert(parts, { "ball", core })
	local spikes = {}
	local count = if style == "blast" then 5 elseif style == "rail" then 4 else 3
	for i = 1, count do
		local p = take("block")
		p.Color = if i == 1 then WHITE else color
		p.Transparency = 0
		table.insert(parts, { "block", p })
		table.insert(spikes, p)
	end
	local cone = take("block")
	cone.Color = color
	cone.Transparency = 0.1
	table.insert(parts, { "block", cone })
	local ring
	if style == "rail" then
		ring = take("cyl")
		ring.Color = color
		ring.Transparency = 0.2
		table.insert(parts, { "cyl", ring })
	end
	local function draw(f: number)
		local g = 1 - f
		core.Size = Vector3.one * 0.55 * k * (0.6 + 0.6 * g)
		core.CFrame = cf * CFrame.new(0, 0, -0.25 * k)
		core.Transparency = f
		for i, p in spikes do
			local a = roll + i / count * math.pi
			local len = (if style == "blast" then 1.6 else 1.1) * k * g
			p.Size = Vector3.new(0.12 * k, math.max(0.05, len * 2), 0.12 * k)
			p.CFrame = cf * CFrame.new(0, 0, -0.3 * k) * CFrame.Angles(0, 0, a)
			p.Transparency = f * 0.9
		end
		local fl = (if style == "blast" then 3.2 elseif style == "rail" then 4.2 else 2.0) * k * (0.5 + 0.5 * g)
		local fw = (if style == "blast" then 0.7 else 0.32) * k * g
		cone.Size = Vector3.new(math.max(0.05, fw), math.max(0.05, fw), fl)
		cone.CFrame = cf * CFrame.new(0, 0, -fl / 2) * CFrame.Angles(0, 0, roll)
		cone.Transparency = 0.1 + 0.9 * f
		if ring then
			local d = 1.2 * k + 2.8 * k * f
			ring.Size = Vector3.new(0.06, d, d)
			ring.CFrame = cf * CFrame.new(0, 0, -0.6 * k - f * 1.5) * CFrame.Angles(0, math.pi / 2, 0)
			ring.Transparency = 0.2 + 0.8 * f
		end
	end
	draw(0)
	spawn(life, function(_, f)
		draw(f)
	end, parts)
end

-- Travelling streak (bolt / pellet): head flies at `speed`, tail of `length`; onArrive at the end.
function Fx.projectile(from: Vector3, to: Vector3, color: Color3, width: number, speed: number, length: number, onArrive)
	local delta = to - from
	local dist = delta.Magnitude
	if dist < 0.05 then
		if onArrive then
			onArrive()
		end
		return
	end
	local dir = delta / dist
	local glow, core = take("block"), take("block")
	glow.Color = color
	glow.Transparency = 0.25
	core.Color = WHITE
	core.Transparency = 0
	local flight = dist / speed
	local tailTime = length / speed
	local arrived = false
	local function draw(t: number)
		local head = math.min(t * speed, dist)
		local tail = math.clamp(t * speed - length, 0, dist)
		if head - tail < 0.05 then
			glow.CFrame = HIDDEN
			core.CFrame = HIDDEN
			return
		end
		local a, b = from + dir * tail, from + dir * head
		segment(glow, a, b, width)
		segment(core, a:Lerp(b, 0.35), b, width * 0.4)
	end
	draw(0.008)
	spawn(flight + tailTime, function(_, _, _, t)
		draw(t)
		if not arrived and t >= flight then
			arrived = true
			if onArrive then
				onArrive()
			end
		end
	end, { { "block", glow }, { "block", core } })
end

-- Jagged flickering lightning between two points (re-jitters ~30 Hz), with a fork.
function Fx.lightning(a: Vector3, b: Vector3, color: Color3, width: number?, life: number?)
	local w = width or 0.22
	local dir = b - a
	local len = dir.Magnitude
	if len < 0.1 then
		return
	end
	local segs = math.clamp(math.floor(len / 2.2), 3, if Settings.quality >= 2 and not Fx.busy(60) then 10 else 5)
	local parts, main, glows = {}, {}, {}
	for i = 1, segs do
		local p = take("block")
		p.Color = WHITE
		table.insert(parts, { "block", p })
		main[i] = p
		if Settings.quality >= 3 and not Fx.busy(120) then
			local g = take("block")
			g.Color = color
			table.insert(parts, { "block", g })
			glows[i] = g
		end
	end
	local fork = {}
	for i = 1, 2 do
		local p = take("block")
		p.Color = color
		table.insert(parts, { "block", p })
		fork[i] = p
	end
	local right, up = basis(dir / len)
	local acc = 1
	local function jitter()
		local prev = a
		local mid = a
		for i = 1, segs do
			local k = i / segs
			local point = a + dir * k
			if i < segs then
				local amp = len * 0.12 * math.sin(k * math.pi)
				point += right * rnd(-amp, amp) + up * rnd(-amp * 0.6, amp * 0.6)
			end
			segment(main[i], prev, point, w * 0.55)
			if glows[i] then
				segment(glows[i], prev, point, w * 1.8)
			end
			if i == math.ceil(segs / 2) then
				mid = point
			end
			prev = point
		end
		local fprev = mid
		for i = 1, 2 do
			local fp = fprev + (dir / len) * len * 0.12 + right * rnd(-1.6, 1.6) + up * rnd(-0.6, 0.8)
			segment(fork[i], fprev, fp, w * 0.4)
			fprev = fp
		end
	end
	jitter()
	spawn(life or 0.16, function(_, k, dt)
		acc += dt
		if acc > 0.033 then
			acc = 0
			jitter()
		end
		local tr = k * k
		for _, p in main do
			p.Transparency = tr
		end
		for _, g in glows do
			g.Transparency = 0.55 + 0.45 * tr
		end
		for _, p in fork do
			p.Transparency = 0.2 + 0.8 * k
		end
	end, parts)
end

-- Railgun: white core + colored sheath + helix spiral + expanding rings + lingering smoke.
function Fx.rail(a: Vector3, b: Vector3, color: Color3, width: number, stars: boolean?)
	local delta = b - a
	local len = delta.Magnitude
	if len < 0.1 then
		return
	end
	local dir = delta / len
	local right, up = basis(dir)
	local parts = {}
	local core, sheath = take("block"), take("block")
	core.Color = WHITE
	sheath.Color = color
	segment(core, a, b, width * 0.45)
	segment(sheath, a, b, width * 1.4)
	table.insert(parts, { "block", core })
	table.insert(parts, { "block", sheath })
	local helix = {}
	local step = if Settings.quality >= 3 then 1.6 else 3
	local n = math.min(math.floor(len / step), 70)
	local r = width * 1.6
	local prev = a + right * r
	for i = 1, n do
		local s = i * step
		local ang = s * 0.9
		local point = a + dir * s + (right * math.cos(ang) + up * math.sin(ang)) * r
		local p = take("block")
		p.Color = if stars and i % 3 == 0 then WHITE else color
		segment(p, prev, point, 0.16)
		table.insert(parts, { "block", p })
		table.insert(helix, { p = p, s = s })
		prev = point
	end
	local rings = {}
	local ringStep = math.max(6, len / 8)
	local s = ringStep * 0.5
	while s < len and #rings < 10 do
		local ring = take("cyl")
		ring.Color = color
		ring.Transparency = 0.3
		ring.CFrame = CFrame.lookAt(a + dir * s, a + dir * s + dir) * CFrame.Angles(0, math.pi / 2, 0)
		ring.Size = Vector3.new(0.08, width * 2, width * 2)
		table.insert(parts, { "cyl", ring })
		table.insert(rings, ring)
		s += ringStep
	end
	spawn(0.55, function(_, k)
		local w = width * (1 - k) ^ 2
		segment(core, a, b, math.max(0.02, w * 0.45))
		core.Transparency = k
		segment(sheath, a, b, math.max(0.02, width * 1.4 * (1 - k * 0.5)))
		sheath.Transparency = 0.35 + 0.65 * k
		for _, h in helix do
			-- unwinds from the muzzle outward
			local f = math.clamp(k * 1.6 - h.s / len * 0.6, 0, 1)
			h.p.Transparency = 0.1 + 0.9 * f
		end
		for _, ring in rings do
			local d = width * 1.6 + k * 4
			ring.Size = Vector3.new(0.06, d, d)
			ring.Transparency = 0.55 + 0.45 * k
		end
	end, parts)
	if Settings.quality >= 2 then
		local puff = math.max(5, len / 12)
		local t = 2
		while t < len do
			Fx.emit("muzzleSmoke", a + dir * t, 1, up)
			t += puff
		end
	end
	Fx.light(a:Lerp(b, 0.3), color, 30, 0.25)
end

-- Ejected casing with gravity, bounces and fade. kind: "cell" | "shell" | "slug".
local shells = {}
local SHELL_CAP = 24
local onShellClink = nil
function Fx.setShellSound(cb)
	onShellClink = cb
end
function Fx.shell(cf: CFrame, kind: string, color: Color3)
	if Settings.quality < 2 then
		return
	end
	local p
	if #shells >= SHELL_CAP then
		p = table.remove(shells, 1).p
	else
		p = take("block")
	end
	if kind == "shell" then
		p.Size = Vector3.new(0.26, 0.26, 0.6)
		p.Color = Color3.fromRGB(200, 50, 40)
		p.Material = Enum.Material.SmoothPlastic
	elseif kind == "slug" then
		p.Size = Vector3.new(0.3, 0.3, 0.75)
		p.Color = color
		p.Material = Enum.Material.Neon
	elseif kind == "cellMag" then
		-- spent energy cell stripped during a reload: drops (no sideways throw), lingers a little longer
		p.Size = Vector3.new(0.24, 0.52, 0.34)
		p.Color = Color3.fromRGB(86, 96, 112)
		p.Material = Enum.Material.Metal
	else
		p.Size = Vector3.new(0.16, 0.16, 0.3)
		p.Color = color
		p.Material = Enum.Material.Neon
	end
	p.Transparency = 0
	local v = if kind == "cellMag"
		then cf.RightVector * rnd(-1.5, 1.5) + Vector3.yAxis * rnd(-2, 1) + cf.LookVector * rnd(-1, 1)
		else cf.RightVector * rnd(9, 14) + Vector3.yAxis * rnd(9, 15) + cf.LookVector * rnd(-3, 1)
	table.insert(shells, {
		p = p,
		pos = cf.Position,
		v = v,
		rot = cf.Rotation,
		spin = Vector3.new(rnd(-20, 20), rnd(-20, 20), rnd(-20, 20)),
		t = 0,
		life = if kind == "slug" then 1.6 elseif kind == "cellMag" then 2.2 else 1.3,
		kind = kind,
		bounced = false,
		color = if kind == "shell" then p.Color else color,
	})
end

local function updateShells(dt: number)
	local i = 1
	while i <= #shells do
		local s = shells[i]
		s.t += dt
		if s.t >= s.life then
			table.remove(shells, i)
			give("block", s.p)
		else
			s.v += Vector3.new(0, -110 * dt, 0)
			local pos = s.pos + s.v * dt
			if pos.Y < 0.15 then
				pos = Vector3.new(pos.X, 0.15, pos.Z)
				if not s.bounced and onShellClink then
					onShellClink(pos, s.kind)
				end
				s.bounced = true
				s.v = Vector3.new(s.v.X * 0.45, math.abs(s.v.Y) * 0.32, s.v.Z * 0.45)
				s.spin *= 0.5
			end
			s.pos = pos
			s.rot = s.rot * CFrame.Angles(s.spin.X * dt, s.spin.Y * dt, s.spin.Z * dt)
			s.p.CFrame = CFrame.new(pos) * s.rot
			s.p.Transparency = math.max(0, (s.t - (s.life - 0.35)) / 0.35)
			if s.kind ~= "shell" and s.kind ~= "cellMag" and s.t > 0.1 then
				-- glowing casings cool down fast (so they never read as XP orbs)
				local cool = math.clamp((s.t - 0.1) / (if s.kind == "slug" then 0.8 else 0.3), 0, 1)
				s.p.Color = s.color:Lerp(Color3.fromRGB(60, 64, 72), cool)
				if cool >= 1 and s.p.Material == Enum.Material.Neon then
					s.p.Material = Enum.Material.Metal
				end
				if s.kind == "slug" and math.random() < dt * 8 then
					Fx.emit("muzzleSmoke", pos, 1)
				end
			end
			i += 1
		end
	end
end

-- Impact on an enemy. dir = shot travel direction. Styles: spark, shock, pellet, rail, beam.
local IMPACT_EMIT = { spark = "hitCyan", shock = "hitCyan", pellet = "hitOrange", rail = "hitGold", beam = "hitViolet" }
function Fx.impact(style: string, pos: Vector3, dir: Vector3, color: Color3, size: number, fire: boolean?)
	local back = (-dir + Vector3.yAxis * 0.6).Unit
	local flash = take("ball")
	flash.Color = WHITE
	flash.Transparency = 0
	local big = style == "rail"
	spawn(if big then 0.14 else 0.07, function(_, f)
		flash.Size = Vector3.one * (if big then 3.2 else 1.3) * size * (0.6 + 0.6 * f)
		flash.CFrame = CFrame.new(pos)
		flash.Transparency = f
	end, { { "ball", flash } })
	local emitName = IMPACT_EMIT[style] or "hitWhite"
	if big then
		Fx.emit(emitName, pos, 10, (dir + Vector3.yAxis * 0.3).Unit) -- exit spray through the target
		Fx.emit("hitWhite", pos, 5, back)
		local ring = take("cyl")
		ring.Color = color
		spawn(0.22, function(_, f)
			local d = 1.5 + 7 * f
			ring.Size = Vector3.new(0.1, d, d)
			ring.CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, math.pi / 2, 0)
			ring.Transparency = 0.15 + 0.85 * f
		end, { { "cyl", ring } })
		Fx.light(pos, color, 16, 0.15)
	else
		Fx.emit(emitName, pos, if style == "pellet" then 3 else 4, back)
		if style == "shock" and Settings.quality >= 2 then
			Fx.lightning(pos, pos + Vector3.new(rnd(-3, 3), rnd(0, 2), rnd(-3, 3)), color, 0.14, 0.1)
		end
	end
	if fire then
		Fx.emit("ember", pos, 2, back)
	end
end

-- Impact on world geometry: sparks along the surface normal + dust + a fading scorch mark.
local scorches = {}
function Fx.impactWall(pos: Vector3, normal: Vector3, color: Color3, size: number?)
	local n = if normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	Fx.emit("hitWhite", pos + n * 0.1, 3, (n + Vector3.yAxis * 0.3).Unit)
	Fx.emit("dust", pos + n * 0.3, 1, n)
	local cap = if Settings.quality >= 3 then 30 elseif Settings.quality == 2 then 12 else 0
	if cap == 0 then
		return
	end
	local p
	if #scorches >= cap then
		p = table.remove(scorches, 1).p
	else
		p = take("cyl")
	end
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(18, 16, 14)
	p.Transparency = 0.25
	local d = (size or 1) * rnd(0.7, 1.1)
	p.Size = Vector3.new(0.04, d, d)
	-- cylinder axis = X; point it along the normal
	p.CFrame = CFrame.lookAt(pos + n * 0.03, pos + n * 2) * CFrame.Angles(0, math.pi / 2, 0)
	table.insert(scorches, { p = p, t = 0 })
	local glow = take("cyl")
	glow.Color = color
	local glowCF = p.CFrame * CFrame.new(0.01, 0, 0)
	spawn(0.35, function(_, f)
		glow.Size = Vector3.new(0.05, d * 0.7, d * 0.7)
		glow.CFrame = glowCF
		glow.Transparency = 0.1 + 0.9 * f
	end, { { "cyl", glow } })
end

local function updateScorches(dt: number)
	local i = 1
	while i <= #scorches do
		local s = scorches[i]
		s.t += dt
		if s.t > 4 then
			table.remove(scorches, i)
			give("cyl", s.p)
		else
			s.p.Transparency = 0.25 + 0.75 * math.max(0, (s.t - 3) / 1)
			i += 1
		end
	end
end

-- Continuous beams keyed by owner: core + sheath + double helix + end/muzzle glows.
local beams = {}
function Fx.beamDraw(key: any, from: Vector3, to: Vector3, color: Color3, width: number, helixR: number, spin: number)
	local b = beams[key]
	if not b then
		local strands = if Settings.quality >= 3 then 14 elseif Settings.quality == 2 then 8 else 0
		b = { core = take("cyl"), sheath = take("cyl"), outer = take("cyl"), tip = take("ball"), mouth = take("ball"), helix = {} }
		for i = 1, strands * 2 do
			b.helix[i] = take("block")
		end
		beams[key] = b
	end
	local now = os.clock()
	local len = (to - from).Magnitude
	if len < 0.1 then
		return
	end
	local dir = (to - from) / len
	local right, up = basis(dir)
	local w = width * (1 + math.sin(now * 47) * 0.12 + math.sin(now * 23) * 0.08)
	b.core.Color = WHITE
	b.core.Transparency = 0.05
	tube(b.core, from, to, w * 0.22)
	b.sheath.Color = color
	b.sheath.Transparency = 0.35
	tube(b.sheath, from, to, w * 0.55)
	b.outer.Color = color
	b.outer.Transparency = 0.85
	tube(b.outer, from, to, w * 1.2)
	b.tip.Color = color
	b.tip.Transparency = 0.2
	b.tip.Size = Vector3.one * w * (1.6 + math.sin(now * 31) * 0.4)
	b.tip.CFrame = CFrame.new(to)
	b.mouth.Color = WHITE
	b.mouth.Transparency = 0.1
	b.mouth.Size = Vector3.one * w * (0.8 + math.sin(now * 53) * 0.2)
	b.mouth.CFrame = CFrame.new(from)
	local n = #b.helix // 2
	for strand = 0, 1 do
		local prev = nil
		for i = 1, n do
			local s = (i - 1) / math.max(1, n - 1) * len
			local ang = s * 0.55 - now * spin + strand * math.pi
			local r = helixR * (0.6 + 0.4 * math.sin(s * 0.3 + now * 9))
			local point = from + dir * s + (right * math.cos(ang) + up * math.sin(ang)) * r
			local p = b.helix[strand * n + i]
			if prev then
				p.Color = color
				p.Transparency = 0.1
				segment(p, prev, point, 0.1)
			else
				p.CFrame = HIDDEN
			end
			prev = point
		end
	end
end

function Fx.beamHide(key: any)
	local b = beams[key]
	if not b then
		return
	end
	beams[key] = nil
	for _, name in { "core", "sheath", "outer" } do
		give("cyl", b[name])
	end
	give("ball", b.tip)
	give("ball", b.mouth)
	for _, p in b.helix do
		give("block", p)
	end
end

function Fx.beamKeys()
	return beams
end

-- Frame ---------------------------------------------------------------------------------------------
function Fx.update(dt: number)
	updateShells(dt)
	updateScorches(dt)
	local i = 1
	while i <= #active do
		local e = active[i]
		e.t += dt
		local k = math.clamp(e.t / e.life, 0, 1)
		if e.t >= e.life then
			for _, entry in e.parts do
				give(entry[1], entry[2])
			end
			liveParts -= #e.parts
			active[i] = active[#active]
			active[#active] = nil
			if e.done then
				e.done()
			end
		else
			e.update(e, k, dt, e.t)
			i += 1
		end
	end
	for _, l in lights do
		if l.t < l.life then
			l.t += dt
			local k = l.t / l.life
			l.light.Brightness = 3 * (1 - k)
			if k >= 1 then
				l.light.Range = 0
			end
		end
	end
	for _, n in numberPool do
		if n.gui.Enabled then
			n.t += dt
			local k = n.t / n.life
			if k >= 1 then
				n.gui.Enabled = false
			else
				n.vel += Vector3.new(0, -40 * dt, 0)
				n.pos += n.vel * dt
				n.gui.StudsOffsetWorldSpace = n.pos
				n.label.TextTransparency = math.max(0, (k - 0.6) / 0.4)
				n.label.TextStrokeTransparency = 0.2 + 0.8 * math.max(0, (k - 0.6) / 0.4)
			end
		end
	end
	local now = os.clock()
	for _, o in orbs do
		local bob = math.sin(now * 4 + o.phase) * 0.3
		o.p.CFrame = CFrame.new(o.x, 1 + bob, o.z) * CFrame.Angles(0.6, now * 2 + o.phase, 0.6)
	end
end

function Fx.clear()
	for _, e in active do
		for _, entry in e.parts do
			give(entry[1], entry[2])
		end
	end
	table.clear(active)
	liveParts = 0
	Fx.clearOrbs()
	for key in beams do
		Fx.beamHide(key)
	end
	for _, sh in shells do
		give("block", sh.p)
	end
	table.clear(shells)
	for _, sc in scorches do
		give("cyl", sc.p)
	end
	table.clear(scorches)
	for _, p in splats do
		give("cyl", p)
	end
	table.clear(splats)
end

return Fx
