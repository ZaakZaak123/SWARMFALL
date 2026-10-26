--!nonstrict
-- Story scenes (DD-075): the first minute is one journey on one cable. The shelter in the grove and the
-- drill in the funnel are ~1.3 km apart and the cableway joins them (Cableway.ARENA_* / HOME_*): the hero
-- rides it out to the drill in the intro and rides it home with the generator after the first win. The
-- wasteland between them exists only while a scene crosses it.
--
-- Story.init(playerGui, deps)      deps: { base = Base, onIntroDone = fn }
-- Story.cover(on)                  black title screen (up from the first frame until we know who joined)
-- Story.profile(pub)               profile arrived: a returning player's cover fades at once
-- Story.intro(onDone)              the newcomer's intro, ends on the hero at the spawn
-- Story.arrival(pos, onDone)       before the first defence: the camera finds the new turret at the drill
-- Story.returnHome(onDone)         after the first win: the generator rides home and the shelter wakes up
-- Story.camera(dt) -> CFrame?      the scene's camera this frame
-- Story.active() -> boolean

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local Audio = require(script.Parent.Audio)
local Fx = require(script.Parent.Fx)
local Cableway = require(script.Parent.Cableway)
local Meta = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Meta"))

local new, C, F = Theme.new, Theme.C, Theme.F
local label, tween = Theme.label, Theme.tween
local rgb = Color3.fromRGB

local Story = {}

local player = Players.LocalPlayer
local deps = {}
local gui: ScreenGui
local ui = {}
local scene = nil -- { t, step(dt) -> CFrame, finish() }
local coverDeadline = 0

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- GUI -------------------------------------------------------------------------------------------------------
local function buildGui(playerGui: PlayerGui)
	gui = new("ScreenGui", {
		Name = "SporeStory",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 60,
		Parent = playerGui,
	})
	ui.top = new("Frame", {
		Size = UDim2.new(1, 0, 0.1, 0),
		Position = UDim2.fromScale(0, -0.1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = gui,
	})
	ui.bottom = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(1, 0, 0.1, 0),
		Position = UDim2.fromScale(0, 1.1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = gui,
	})
	ui.cap = label("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.84, 0),
		Size = UDim2.new(0.9, 0, 0, 44),
		FontFace = F.display,
		TextSize = 36,
		TextTransparency = 1,
		Parent = gui,
	})
	new("UIStroke", { Color = C.ink, Thickness = 3, Transparency = 0.15, Parent = ui.cap })
	ui.sub = label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.84, 6),
		Size = UDim2.new(0.8, 0, 0, 46),
		FontFace = F.bodyBold,
		TextSize = 19,
		TextWrapped = true,
		TextColor3 = C.text,
		TextTransparency = 1,
		Parent = gui,
	})
	new("UIStroke", { Color = C.ink, Thickness = 2, Transparency = 0.15, Parent = ui.sub })
	ui.flash = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = gui,
	})
	-- the cover: a black title card over everything (no camp UI flashes past a newcomer)
	ui.cover = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb(6, 5, 8),
		BorderSizePixel = 0,
		ZIndex = 10,
		Visible = false,
		Parent = gui,
	})
	ui.coverTitle = label("SPOREFALL", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.new(0.9, 0, 0, 80),
		FontFace = F.display,
		TextSize = 72,
		TextColor3 = rgb(226, 214, 190),
		ZIndex = 11,
		Parent = ui.cover,
	})
	ui.coverLine = label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.new(0.8, 0, 0, 60),
		FontFace = F.bodyBold,
		TextSize = 20,
		TextWrapped = true,
		TextColor3 = rgb(196, 186, 168),
		TextTransparency = 1,
		ZIndex = 11,
		Parent = ui.cover,
	})
	local skip, skipLabel = Theme.button("ПРОПУСТИТЬ  ›", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.95, 0),
		Size = UDim2.fromOffset(190, 44),
		TextSize = 13,
		Visible = false,
		ZIndex = 12,
	})
	skip.Parent = gui
	skipLabel.ZIndex = 13
	ui.skip = skip
	skip.Activated:Connect(function()
		if scene and scene.finish then
			scene.finish()
		end
	end)
end

local function caption(text: string, subText: string?, color: Color3?)
	ui.cap.Text = text
	ui.cap.TextColor3 = color or C.text
	ui.sub.Text = subText or ""
	ui.cap.TextTransparency = 1
	ui.sub.TextTransparency = 1
	tween(ui.cap, 0.4, { TextTransparency = 0 })
	tween(ui.sub, 0.6, { TextTransparency = 0 })
end

local function letterbox(on: boolean)
	tween(ui.top, 0.5, { Position = UDim2.fromScale(0, if on then 0 else -0.1) })
	tween(ui.bottom, 0.5, { Position = UDim2.fromScale(0, if on then 1 else 1.1) })
	ui.skip.Visible = on
	if not on then
		tween(ui.cap, 0.3, { TextTransparency = 1 })
		tween(ui.sub, 0.3, { TextTransparency = 1 })
		-- the text's outline (UIStroke) does not fade with it: clear the words once they are gone
		task.delay(0.35, function()
			if not scene then
				ui.cap.Text = ""
				ui.sub.Text = ""
			end
		end)
	end
end

local function flash(amount: number, time: number?)
	ui.flash.BackgroundTransparency = 1 - amount
	tween(ui.flash, time or 0.5, { BackgroundTransparency = 1 })
end

-- Movement off while a scene plays: the run waits for the first move, and a move would start it.
local function setControls(on: boolean)
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	end)
	if ok and module then
		local controls = module:GetControls()
		if on then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

local function heroVisible(on: boolean)
	local char = player.Character
	if not char then
		return
	end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = if on then 0 else 1
		end
	end
end

-- The dead shelter is shown at nightfall: a local grade for the home shots of the intro. The exact values
-- the server set are put back afterwards (a client-side change stays until the server changes it again).
local Lighting = game:GetService("Lighting")
local LIGHT_KEYS = { "ClockTime", "Brightness", "ExposureCompensation", "OutdoorAmbient", "Ambient" }
local ATMO_KEYS = { "Density", "Haze", "Color" }
local function lightSnapshot()
	local snap = { light = {}, atmo = {} }
	for _, k in LIGHT_KEYS do
		snap.light[k] = Lighting[k]
	end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		snap.atmoInst = atmo
		for _, k in ATMO_KEYS do
			snap.atmo[k] = atmo[k]
		end
	end
	return snap
end
local function lightRestore(snap, time: number?)
	if time then
		tween(Lighting, time, snap.light)
	else
		for k, v in snap.light do
			Lighting[k] = v
		end
	end
	if snap.atmoInst and snap.atmoInst.Parent then
		if time then
			tween(snap.atmoInst, time, snap.atmo)
		else
			for k, v in snap.atmo do
				snap.atmoInst[k] = v
			end
		end
	end
end
local function nightfall()
	Lighting.ClockTime = 18.35
	Lighting.Brightness = 1.2
	Lighting.ExposureCompensation = -0.1
	Lighting.OutdoorAmbient = rgb(112, 98, 116)
	Lighting.Ambient = rgb(70, 62, 78)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		atmo.Density = 0.3
		atmo.Haze = 1.6
		atmo.Color = rgb(196, 120, 108)
	end
end

-- The route and the wasteland ----------------------------------------------------------------------------------
local function homeWorld(rel: Vector3): Vector3
	return Meta.HomeOrigin + rel
end

-- Masts across the wasteland, from the funnel's rim to the grove's edge (fixed jitter: the same every time).
local function transitAnchors(): { Vector3 }
	local a, b = Cableway.ARENA_RIM, homeWorld(Cableway.HOME_FAR)
	local list = { a }
	local n = 7
	local rng = Random.new(1306)
	for i = 1, n do
		local p = a:Lerp(b, i / (n + 1))
		table.insert(list, Vector3.new(p.X + rng:NextNumber(-10, 10), 30 + rng:NextNumber(-3, 4), p.Z))
	end
	table.insert(list, b)
	return list
end

-- The whole ride from the post inside the funnel to the terminal in the courtyard (the cable's own sag).
local function routeTrack(terminal: Vector3): ({ Vector3 }, number, number)
	local track = {}
	local function add(points)
		for i, p in points do
			if i > 1 or #track == 0 then
				table.insert(track, p)
			end
		end
	end
	add(Cableway.track({ Cableway.ARENA_SIDE, Cableway.ARENA_RIM }))
	local arenaEnd = #track
	add(Cableway.track(transitAnchors()))
	local transitEnd = #track
	add(Cableway.track({ homeWorld(Cableway.HOME_FAR), homeWorld(Cableway.HOME_POST), terminal }))
	return track, arenaEnd, transitEnd
end

local function makePath(track: { Vector3 })
	local dist = { 0 }
	for k = 2, #track do
		dist[k] = dist[k - 1] + (track[k] - track[k - 1]).Magnitude
	end
	local path = { track = track, dist = dist, length = dist[#dist] }
	function path.at(s: number): (Vector3, Vector3)
		s = math.clamp(s, 0, path.length)
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
		local dir = track[hi] - track[lo]
		return track[lo]:Lerp(track[hi], t), if dir.Magnitude > 1e-3 then dir.Unit else Vector3.zAxis
	end
	return path
end

local function reversed(list)
	local out = {}
	for i = #list, 1, -1 do
		table.insert(out, list[i])
	end
	return out
end

-- Monotone cubic through (time, distance) keys: the rider eases out, speeds over the wasteland, eases in.
local function motion(keys)
	local n = #keys
	local m = {}
	for i = 1, n do
		if i == 1 or i == n then
			m[i] = 0
		else
			local d0 = (keys[i][2] - keys[i - 1][2]) / (keys[i][1] - keys[i - 1][1])
			local d1 = (keys[i + 1][2] - keys[i][2]) / (keys[i + 1][1] - keys[i][1])
			m[i] = if d0 * d1 <= 0 then 0 else 2 / (1 / d0 + 1 / d1)
		end
	end
	return function(t: number): number
		if t <= keys[1][1] then
			return keys[1][2]
		elseif t >= keys[n][1] then
			return keys[n][2]
		end
		for i = 1, n - 1 do
			local a, b = keys[i], keys[i + 1]
			if t <= b[1] then
				local h = b[1] - a[1]
				local u = (t - a[1]) / h
				local u2, u3 = u * u, u * u * u
				return (2 * u3 - 3 * u2 + 1) * a[2]
					+ (u3 - 2 * u2 + u) * h * m[i]
					+ (-2 * u3 + 3 * u2) * b[2]
					+ (u3 - u2) * h * m[i + 1]
			end
		end
		return keys[n][2]
	end
end

local function block(parent, size: Vector3, cf: CFrame, color: Color3, material, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = size.Magnitude > 8
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- The wasteland under the cable: ash and dust by the funnel turning to grass by the grove, dead trees,
-- broken walls, rusted cars, the stumps of towers on the horizon, and the cable's masts.
local function buildWasteland(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "StoryWasteland"
	local anchors = transitAnchors()
	local a, b = anchors[1], anchors[#anchors]
	local cx = (a.X + b.X) / 2
	local z0, z1 = a.Z + 14, b.Z + 24
	local slabs = 7
	for i = 0, slabs - 1 do
		local k = i / (slabs - 1)
		local len = (z1 - z0) / slabs
		block(
			folder,
			Vector3.new(1100, 2, len + 2),
			CFrame.new(cx, -1.02, z0 + len * (i + 0.5)),
			rgb(112, 96, 78):Lerp(rgb(92, 122, 62), k * k),
			if k < 0.6 then Enum.Material.Ground else Enum.Material.Grass
		)
	end
	local rng = Random.new(2075)
	local function lineX(z: number): number
		local t = math.clamp((z - a.Z) / (b.Z - a.Z), 0, 1)
		return a.X + (b.X - a.X) * t
	end
	local function spot(minOff: number, maxOff: number): (number, number, number)
		local z = rng:NextNumber(z0 + 10, z1 - 30)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x = lineX(z) + side * rng:NextNumber(minOff, maxOff)
		local green = math.clamp((z - z0) / (z1 - z0), 0, 1)
		return x, z, green
	end
	-- dead trees (greener and leafier towards the grove)
	for _ = 1, 70 do
		local x, z, green = spot(14, 260)
		local h = rng:NextNumber(8, 17)
		local w = rng:NextNumber(0.7, 1.3)
		local bark = rgb(64, 56, 50):Lerp(rgb(80, 66, 48), green)
		block(
			folder,
			Vector3.new(w, h, w),
			CFrame.new(x, h / 2, z) * CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(-0.08, 0.08)),
			bark,
			Enum.Material.Wood
		)
		for j = 1, 2 do
			local bl = h * rng:NextNumber(0.25, 0.4)
			block(
				folder,
				Vector3.new(w * 0.5, bl, w * 0.5),
				CFrame.new(x, h * (0.55 + j * 0.15), z)
					* CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(0.5, 0.9) * (if j == 1 then 1 else -1))
					* CFrame.new(0, bl / 2, 0),
				bark,
				Enum.Material.Wood
			)
		end
		if green > 0.55 and rng:NextNumber() < green then
			block(
				folder,
				Vector3.one * h * 0.55,
				CFrame.new(x, h * 0.95, z),
				rgb(78, 120, 54):Lerp(rgb(96, 142, 60), rng:NextNumber()),
				Enum.Material.Grass,
				Enum.PartType.Ball
			)
		end
	end
	-- broken walls of the old city
	for _ = 1, 30 do
		local x, z = spot(18, 240)
		local w, h = rng:NextNumber(10, 26), rng:NextNumber(5, 18)
		local cf = CFrame.new(x, h / 2, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		local concrete = rgb(124, 118, 108):Lerp(rgb(96, 90, 84), rng:NextNumber())
		block(folder, Vector3.new(w, h, 1.8), cf, concrete, Enum.Material.Concrete)
		block(
			folder,
			Vector3.new(w * 0.45, h * 0.5, 1.8),
			cf * CFrame.new(w * 0.4, h * 0.6, 0) * CFrame.Angles(0, 0, 0.3),
			concrete,
			Enum.Material.Concrete
		)
	end
	-- rusted cars
	for _ = 1, 14 do
		local x, z = spot(12, 200)
		local cf = CFrame.new(x, 1.5, z) * CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(-0.2, 0.2))
		local rust = rgb(120, 70, 44):Lerp(rgb(86, 60, 48), rng:NextNumber())
		block(folder, Vector3.new(4.4, 2.4, 9), cf, rust, Enum.Material.CorrodedMetal)
		block(folder, Vector3.new(3.8, 1.8, 4.6), cf * CFrame.new(0, 2, -0.6), rust, Enum.Material.CorrodedMetal)
	end
	-- rocks
	for _ = 1, 26 do
		local x, z = spot(10, 280)
		local r = rng:NextNumber(3, 9)
		block(
			folder,
			Vector3.new(r * 1.4, r, r * 1.2),
			CFrame.new(x, r * 0.25, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			rgb(100, 94, 86),
			Enum.Material.Slate,
			Enum.PartType.Ball
		)
	end
	-- the stumps of towers far off: the skyline of the city that was
	for _ = 1, 12 do
		local x, z = spot(200, 420)
		local w, h = rng:NextNumber(20, 36), rng:NextNumber(36, 90)
		block(
			folder,
			Vector3.new(w, h, w * rng:NextNumber(0.7, 1.2)),
			CFrame.new(x, h / 2 - 2, z) * CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(-0.06, 0.06)),
			rgb(92, 88, 86),
			Enum.Material.Concrete
		)
	end
	-- the cable itself, mast by mast
	local posts = {}
	for i, p in anchors do
		if i > 1 and i < #anchors then
			posts[i] = Vector3.new(p.X, 0, p.Z)
		end
	end
	Cableway.new(folder, anchors, { posts = posts })
	folder.Parent = workspace
	return folder
end

-- The rider: a pallet on four chains under a trolley; on it the hero (a still copy of the own avatar)
-- and, on the way home, the generator.
local function buildRider(withGenerator: boolean)
	local model = Instance.new("Model")
	model.Name = "StoryRider"
	local metal, wood, lime = rgb(52, 48, 44), rgb(150, 106, 62), rgb(176, 236, 60)
	local parts = {} -- { part, offset }
	local function add(size: Vector3, offset: CFrame, color: Color3, material)
		local p = block(model, size, offset, color, material)
		table.insert(parts, { p, offset })
		return p
	end
	local deck = -5.2 -- the pallet's top under the cable
	add(Vector3.new(1.2, 0.9, 1.8), CFrame.new(0, -0.3, 0), metal, Enum.Material.Metal)
	add(Vector3.new(0.18, 2.6, 0.18), CFrame.new(0, -2, 0), metal, Enum.Material.Metal)
	for _, c in { { -2.4, -1.7 }, { 2.4, -1.7 }, { -2.4, 1.7 }, { 2.4, 1.7 } } do
		local top, bottom = Vector3.new(0, -3.3, 0), Vector3.new(c[1], deck, c[2])
		local len = (bottom - top).Magnitude
		add(Vector3.new(0.1, 0.1, len), CFrame.lookAt((top + bottom) / 2, bottom), metal, Enum.Material.Metal)
	end
	add(Vector3.new(5.4, 0.45, 3.8), CFrame.new(0, deck - 0.22, 0), wood, Enum.Material.WoodPlanks)
	add(Vector3.new(5.46, 0.2, 3.86), CFrame.new(0, deck - 0.3, 0), lime, Enum.Material.SmoothPlastic)
	local cargo = nil
	if withGenerator then
		local f = ReplicatedStorage:FindFirstChild("ArtTemplates")
		local t = f and f:FindFirstChild("GENERATOR")
		if t and t:IsA("MeshPart") then
			cargo = t:Clone()
			cargo.Anchored = true
			cargo.CanCollide = false
			cargo.Size = t.Size * (3.8 / t.Size.Y)
			cargo.Parent = model
			table.insert(
				parts,
				{ cargo, CFrame.new(1.2, deck + cargo.Size.Y / 2, 0) * CFrame.Angles(0, math.pi / 2, 0) }
			)
		else
			add(Vector3.new(2.6, 2.4, 2.6), CFrame.new(1.2, deck + 1.2, 0), rgb(200, 160, 60), Enum.Material.Metal)
		end
	end
	-- the hero: a still copy of the own avatar standing on the pallet
	local hero, heroOffset = nil, nil
	local char = player.Character
	if char then
		local okClone, clone = pcall(function()
			char.Archivable = true
			return char:Clone()
		end)
		if okClone and clone then
			for _, d in clone:GetDescendants() do
				if
					d:IsA("LuaSourceContainer")
					or d:IsA("ProximityPrompt")
					or d:IsA("BillboardGui")
					or d:IsA("Highlight")
				then
					d:Destroy()
				elseif d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.LocalTransparencyModifier = 0
				elseif d:IsA("Decal") then
					d.LocalTransparencyModifier = 0
				end
			end
			local hum = clone:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
			clone.Name = "StoryHero"
			clone.Parent = model
			local cf, size = clone:GetBoundingBox()
			local feet = clone:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
			hero = clone
			heroOffset = CFrame.new(if withGenerator then -1.3 else 0, deck + feet, 0)
		end
	end
	model.Parent = workspace
	local rider = { model = model }
	function rider.place(pos: Vector3, dir: Vector3, sway: number)
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude < 1e-3 then
			flat = Vector3.zAxis
		end
		local frame = CFrame.lookAt(pos, pos + flat) * CFrame.Angles(0, 0, sway)
		for _, row in parts do
			row[1].CFrame = frame * row[2]
		end
		if hero then
			hero:PivotTo(frame * heroOffset)
		end
	end
	function rider.deckPosition(): Vector3
		return parts[1][1].Position + Vector3.new(0, deck, 0)
	end
	function rider.destroy()
		model:Destroy()
	end
	return rider
end

-- Scenes ---------------------------------------------------------------------------------------------------------
-- A scene is a list of shots ({ from, to, cam(k, t) -> CFrame }) and cues ({ at, fn }).
local function play(def)
	if scene then
		scene.finish()
	end
	local fired = {}
	local s = { t = 0 }
	scene = s
	letterbox(def.letterbox ~= false)
	setControls(false)
	local done = false
	function s.finish()
		if done then
			return
		end
		done = true
		if scene == s then
			scene = nil
		end
		letterbox(false)
		if def.cleanup then
			def.cleanup()
		end
		setControls(true)
		if def.onDone then
			def.onDone()
		end
	end
	function s.step(dt: number): CFrame?
		if s.frozen then
			dt = 0
		end
		s.t += dt
		local t = s.t
		for i, cue in def.cues do
			if t >= cue[1] and not fired[i] then
				fired[i] = true
				local ok, err = pcall(cue[2])
				if not ok then
					warn("[Story] cue", cue[1], err)
				end
			end
		end
		if def.update then
			def.update(t, dt)
		end
		if t >= def.length then
			task.defer(s.finish)
		end
		local shot = def.shots[#def.shots]
		for _, sh in def.shots do
			if t < sh.to then
				shot = sh
				break
			end
		end
		return shot.cam(smooth((t - shot.from) / math.max(0.01, shot.to - shot.from)), t)
	end
	return s
end

-- The camera behind and above the rider, looking down the cable ahead.
local function chase(riderPos: Vector3, dir: Vector3, back: number, up: number, side: number): CFrame
	local flat = Vector3.new(dir.X, 0, dir.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local right = flat:Cross(Vector3.yAxis)
	local eye = riderPos - flat * back + Vector3.yAxis * up + right * side
	return CFrame.lookAt(eye, riderPos + flat * 26 - Vector3.yAxis * 4)
end

-- The newcomer's intro, ~21 s: title → the dead shelter → the hero rides the cable out over the
-- wasteland → the funnel, the swarm, the Alpha → the hero at the spawn.
function Story.intro(onDone)
	local base = deps.base
	base.sceneBegin()
	heroVisible(false)
	local track, arenaEnd, transitEnd = routeTrack(base.point("TERMINAL"))
	local forward = makePath(track)
	local path = makePath(reversed(track))
	local L = path.length
	-- the same marks counted from the terminal: the grove's edge, the funnel's rim
	local grove, rim = L - forward.dist[transitEnd], L - forward.dist[arenaEnd]
	local wasteland = buildWasteland()
	local rider = buildRider(false)
	local snap = lightSnapshot()
	local ride = motion({ { 8.4, 0 }, { 10.8, grove }, { 14.8, rim }, { 18.4, L } })
	local s = 0
	local shelter = base.point("SHELTER")
	local term = base.point("TERMINAL")
	local drill = Vector3.new(0, 8, 0)
	local sp = player.Character and player.Character:GetPivot().Position or Vector3.new(0, 3, -26)
	ui.cover.Visible = true
	ui.cover.BackgroundTransparency = 0
	ui.coverTitle.TextTransparency = 0
	ui.coverLine.Text =
		"Двадцать лет после Падения. Города заросли лесом, в руинах живёт рой."
	ui.coverLine.TextTransparency = 1
	tween(ui.coverLine, 1.2, { TextTransparency = 0 })
	coverDeadline = 0
	play({
		length = 19.2,
		shots = {
			{
				from = 0,
				to = 7.4,
				cam = function(k)
					local a = CFrame.lookAt(shelter + Vector3.new(30, 30, -66), shelter + Vector3.new(0, 4, 0))
					local b = CFrame.lookAt(shelter + Vector3.new(12, 17, -40), shelter + Vector3.new(0, 5, 0))
					return a:Lerp(b, k)
				end,
			},
			{
				from = 7.4,
				to = 10.6,
				cam = function(k)
					local eye = term + Vector3.new(16, -2, 10)
					local pos = path.at(s)
					return CFrame.lookAt(eye:Lerp(eye + Vector3.new(-2, 3, -4), k), pos + Vector3.new(0, -3, 0))
				end,
			},
			{
				from = 10.6,
				to = 14.8,
				cam = function()
					local pos, dir = path.at(s)
					return chase(pos, dir, 22, 9, 8)
				end,
			},
			{
				from = 14.8,
				to = 17.2,
				cam = function(k)
					-- the funnel from above: the drill, the rim, the hero coming over it on the cable
					local pos = path.at(s)
					local eye = Vector3.new(-6, 66, -84):Lerp(Vector3.new(-18, 56, -66), k)
					return CFrame.lookAt(eye, drill:Lerp(pos, 0.4))
				end,
			},
			{
				from = 17.2,
				to = 19.2,
				cam = function(k)
					-- close: the hero slides down to the post inside the funnel
					local pos = path.at(s)
					local side = Cableway.ARENA_SIDE
					local eye = (side + Vector3.new(18, 8, -26)):Lerp(side + Vector3.new(14, 5, -20), k)
					return CFrame.lookAt(eye, pos + Vector3.new(0, -4, 0))
				end,
			},
		},
		update = function(t)
			s = ride(t)
			local pos, dir = path.at(s)
			rider.place(pos, dir, math.sin(t * 1.7) * 0.04)
		end,
		cues = {
			{
				0.1,
				function()
					Audio.sting("intro", 22)
					base.sceneLights(false)
					nightfall()
				end,
			},
			{
				10.6,
				function()
					lightRestore(snap, 2.5) -- dusk lifts over the wasteland into the funnel's sunset
				end,
			},
			{
				3.0,
				function()
					tween(ui.cover, 0.9, { BackgroundTransparency = 1 })
					tween(ui.coverTitle, 0.7, { TextTransparency = 1 })
					tween(ui.coverLine, 0.7, { TextTransparency = 1 })
				end,
			},
			{
				3.9,
				function()
					ui.cover.Visible = false
					caption(
						"ТВОЁ УБЕЖИЩЕ",
						"Генератор умер: ни света, ни тока. Без него роща не укроет"
					)
				end,
			},
			{
				7.6,
				function()
					caption(
						"КАНАТКА ВЕДЁТ К СТАРОМУ БУРУ",
						"Там, в руинах буровой станции, — новый генератор",
						C.lime
					)
				end,
			},
			{
				8.4,
				function()
					Audio.play("dash", 0.6, 0.8)
				end,
			},
			{
				11.2,
				function()
					caption(
						"ЧЕРЕЗ ПУСТОШЬ",
						"Километр мёртвого города. Канатка — единственная дорога"
					)
				end,
			},
			{
				15.0,
				function()
					caption(
						"ВОРОНКА У БУРА",
						"Шум бура разбудил рой. Их вожак — Альфа: она гнездится на генераторе",
						C.gold
					)
					Audio.play("roar", 0.45, 0.7)
					for i = 1, 6 do
						task.delay(i * 0.35, function()
							local a = math.rad(50 + i * 14)
							Fx.pod(math.cos(a) * 95, math.sin(a) * 95, i % 3 == 0)
						end)
					end
				end,
			},
			{
				18.6,
				function()
					flash(0.7, 0.6)
				end,
			},
		},
		cleanup = function()
			Audio.stopStings()
			lightRestore(snap)
			rider.destroy()
			wasteland:Destroy()
			ui.cover.Visible = false
			heroVisible(true)
			base.sceneEnd()
			Fx.ring(Vector3.new(sp.X, 0.4, sp.Z), 6, C.lime, 0.6)
			Fx.emitWith("dust", Vector3.new(sp.X, 0.5, sp.Z), 10, 1.4)
			Audio.play("boom", 0.4, 1.3)
			caption("", "")
		end,
		onDone = onDone,
	})
end

-- Before the first defence: the camera finds the new turret at the drill, then settles behind the hero.
function Story.arrival(turret: Vector3, onDone)
	local hero = player.Character and player.Character:GetPivot().Position or Vector3.new(0, 3, -26)
	play({
		length = 5.6,
		shots = {
			{
				from = 0,
				to = 5.6,
				cam = function(k)
					local a = CFrame.lookAt(turret + Vector3.new(26, 22, -30), turret + Vector3.new(0, 2, 0))
					local b = CFrame.lookAt(turret + Vector3.new(14, 9, -18), turret + Vector3.new(0, 3, 0))
					return a:Lerp(b, k)
				end,
			},
		},
		cues = {
			{
				0.3,
				function()
					caption(
						"«ЖАЛО» У БУРА",
						"Оно стреляет само. Держись рядом — рой идёт с севера",
						C.gold
					)
					Fx.ring(Vector3.new(turret.X, 0.4, turret.Z), 7, C.gold, 0.8)
					Audio.play("level", 0.6, 1.2)
				end,
			},
			{
				3.2,
				function()
					caption(
						"ПЕРВЫЙ НАТИСК",
						"Убей вожака — и рой отступит",
						C.orange
					)
				end,
			},
		},
		cleanup = function()
			caption("", "")
			Fx.ring(Vector3.new(hero.X, 0.4, hero.Z), 5, C.lime, 0.5)
		end,
		onDone = onDone,
	})
end

-- After the first win, ~18 s: the generator and the hero leave the funnel on the cable, cross the
-- wasteland, arrive at the courtyard's terminal; the generator lights the shelter, the workshop wakes up,
-- and the turret for the drill is what the loot buys next.
function Story.returnHome(onDone)
	local base = deps.base
	base.sceneBegin()
	local track, arenaEnd, transitEnd = routeTrack(base.point("TERMINAL"))
	local path = makePath(track)
	local L = path.length
	local wasteland = buildWasteland()
	local rider = buildRider(true)
	local ride = motion({ { 1.4, 0 }, { 3.8, path.dist[arenaEnd] }, { 8.6, path.dist[transitEnd] }, { 11.2, L } })
	local s = 0
	local term = base.point("TERMINAL")
	local gen = base.point("GENERATOR")
	local wb = base.point("WORKBENCH")
	local side = Cableway.ARENA_SIDE
	-- close on the pallet at the post: the hero and the generator, the funnel behind them
	local nearEye = side + Vector3.new(15, -6, -13)
	local sting = Meta.Structures.STING
	play({
		length = 18.8,
		shots = {
			{
				from = 0,
				to = 3.4,
				cam = function(k)
					local pos = path.at(s)
					return CFrame.lookAt(
						nearEye:Lerp(nearEye + Vector3.new(4, 3, -6), k),
						pos + Vector3.new(0, -4.5, 0)
					)
				end,
			},
			{
				from = 3.4,
				to = 9.0,
				cam = function()
					local pos, dir = path.at(s)
					return chase(pos, dir, 22, 9, -8)
				end,
			},
			{
				from = 9.0,
				to = 11.6,
				cam = function(k)
					-- from the courtyard side: the pallet comes in over the grove to the frame
					local eye = term + Vector3.new(17, -3, 11)
					return CFrame.lookAt(eye:Lerp(eye + Vector3.new(-2, 1, 2), k), term + Vector3.new(-9, -4, -7))
				end,
			},
			{
				from = 11.6,
				to = 14.6,
				cam = function(k)
					local a = CFrame.lookAt(gen + Vector3.new(12, 10, -17), gen + Vector3.new(0, 2.5, 0))
					local b = CFrame.lookAt(gen + Vector3.new(9, 7, -13), gen + Vector3.new(0, 2.5, 0))
					return a:Lerp(b, k)
				end,
			},
			{
				from = 14.6,
				to = 18.8,
				cam = function(k)
					local a = CFrame.lookAt(wb + Vector3.new(4, 10, -18), wb + Vector3.new(0, 2.5, 0))
					local b = CFrame.lookAt(wb + Vector3.new(3, 7, -14), wb + Vector3.new(0, 3, 0))
					return a:Lerp(b, k)
				end,
			},
		},
		update = function(t)
			s = ride(t)
			local pos, dir = path.at(s)
			if rider.model.Parent then
				rider.place(pos, dir, math.sin(t * 1.9) * 0.05)
			end
		end,
		cues = {
			{
				0.3,
				function()
					caption(
						"ГЕНЕРАТОР ДОБЫТ",
						"Канатка с бура увезёт его домой — в убежище в роще",
						C.gold
					)
				end,
			},
			{
				1.4,
				function()
					Audio.play("dash", 0.5, 0.8)
				end,
			},
			{
				4.2,
				function()
					caption(
						"ЧЕРЕЗ ПУСТОШЬ — ДОМОЙ",
						"Тем же тросом утиль с бура будет приезжать в убежище"
					)
				end,
			},
			{
				9.2,
				function()
					caption("ДОМА", "")
					Audio.sting("home", 12)
				end,
			},
			{
				11.2,
				function()
					local deck = rider.deckPosition()
					Fx.emitWith("dust", deck, 12, 1.4)
					Audio.play("boom", 0.35, 1.4)
					rider.destroy()
				end,
			},
			{
				11.9,
				function()
					base.sceneRestore("GENERATOR")
					caption("УБЕЖИЩЕ ОЖИВАЕТ", "Генератор дал свет и ток", C.gold)
				end,
			},
			{
				14.9,
				function()
					base.sceneRestore("WORKBENCH")
					caption(
						"МАСТЕРСКАЯ ЗАРАБОТАЛА",
						"Ток пошёл на верстак",
						C.cyan
					)
				end,
			},
			{
				16.2,
				function()
					base.sceneMarker(
						"WORKBENCH",
						"СОБЕРИ «ЖАЛО»",
						"Турель для бура · ◆ " .. sting.cost[1]
					)
					Audio.play("level", 0.7, 1.5)
					caption(
						"ХВАТАЕТ НА ПЕРВУЮ ТУРЕЛЬ",
						"Рой вернётся к буру. «Жало» встанет рядом с ним и будет стрелять вместе с тобой",
						C.lime
					)
				end,
			},
		},
		cleanup = function()
			rider.destroy()
			wasteland:Destroy()
			base.sceneEnd()
		end,
		onDone = onDone,
	})
end

function Story.camera(dt: number): CFrame?
	if scene then
		return scene.step(dt)
	end
	return nil
end

-- Studio checks: hold the scene at time t (nil = let it run and finish).
function Story.seek(t: number?)
	if not scene then
		return
	end
	if t then
		scene.t = t
		scene.frozen = true
	else
		scene.finish()
	end
end

function Story.active(): boolean
	return scene ~= nil
end

function Story.cover(on: boolean)
	if on then
		ui.cover.Visible = true
		ui.cover.BackgroundTransparency = 0
		ui.coverTitle.TextTransparency = 0
		coverDeadline = os.clock() + 25
	elseif ui.cover.Visible and not scene then
		tween(ui.cover, 0.8, { BackgroundTransparency = 1 })
		tween(ui.coverTitle, 0.6, { TextTransparency = 1 })
		task.delay(0.85, function()
			if not scene then
				ui.cover.Visible = false
			end
		end)
		coverDeadline = 0
	end
end

function Story.covered(): boolean
	return ui.cover.Visible
end

-- A returning player's cover lifts as soon as we know them; a newcomer's waits for the intro.
function Story.profile(pub)
	local won = pub and pub.winsByOp and (pub.winsByOp.O01 or 0) > 0
	if won or (pub and pub.tut and pub.tut.intro) then
		Story.cover(false)
	end
end

-- Safety: a cover never outlives a stuck join.
function Story.update()
	if coverDeadline > 0 and os.clock() > coverDeadline then
		Story.cover(false)
	end
end

-- The same black card during a teleport between servers.
function Story.teleportGui(): ScreenGui
	local g = new("ScreenGui", { Name = "SporeTeleport", IgnoreGuiInset = true })
	local f =
		new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(6, 5, 8), BorderSizePixel = 0, Parent = g })
	label("SPOREFALL", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.new(0.9, 0, 0, 80),
		FontFace = F.display,
		TextSize = 72,
		TextColor3 = rgb(226, 214, 190),
		Parent = f,
	})
	return g
end

function Story.init(playerGui: PlayerGui, d)
	deps = d or {}
	buildGui(playerGui)
end

return Story
