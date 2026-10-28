--!nonstrict
-- Story scenes (DD-075): the first minute is one journey on one cable. The shelter in the grove and the
-- drill in the funnel are ~1.3 km apart and the cableway joins them (Cableway.ARENA_* / HOME_*): the hero
-- rides it out to the drill in the intro and rides it home with the generator after the first win. The
-- tunnel between them exists only while a scene crosses it.
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
local CameraRig = require(script.Parent.CameraRig)
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

local ID_CF = CFrame.new()
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
		ScreenInsets = Enum.ScreenInsets.None, -- the film bars run edge to edge, past a phone's notch
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
	-- the dip to black while a rider crosses the long dark of the tunnel (under the captions)
	ui.dark = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	})
	-- a dark band behind the words: they must read over any shot (owner playtest, DD-082)
	ui.plate = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.845, 0),
		Size = UDim2.new(1, 0, 0, 130),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	})
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.25),
			NumberSequenceKeypoint.new(0.75, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = ui.plate,
	})
	ui.cap = label("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.84, 0),
		Size = UDim2.new(0.9, 0, 0, 48),
		FontFace = F.display,
		TextSize = 40,
		TextTransparency = 1,
		Parent = gui,
	})
	new("UIStroke", { Color = C.ink, Thickness = 3, Transparency = 0.15, Parent = ui.cap })
	ui.sub = label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.84, 6),
		Size = UDim2.new(0.8, 0, 0, 54),
		FontFace = F.bodyBold,
		TextSize = 23,
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
	ui.coverTitle = label("THE LAST GROVE", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.new(0.9, 0, 0, 80),
		FontFace = F.display,
		TextSize = 56,
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
	-- DD-083 (owner playtest: «отдельная кнопка "дальше", чтобы успевать прочитать»): a scene stops
	-- after what has to be read and waits for this
	local nextB, nextLabel = Theme.button("ДАЛЬШЕ  ›", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -28, 0.95, 0),
		Size = UDim2.fromOffset(220, 54),
		TextSize = 18,
		Visible = false,
		ZIndex = 12,
	}, "primary")
	nextB.Parent = gui
	nextLabel.ZIndex = 13
	ui.next = nextB
	ui.nextScale = new("UIScale", { Parent = nextB })
	nextB.Activated:Connect(function()
		if scene and scene.advance then
			scene.advance()
		end
	end)
	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		local k = input.KeyCode
		if
			not processed
			and scene
			and scene.waiting
			and (
				k == Enum.KeyCode.Return
				or k == Enum.KeyCode.Space
				or k == Enum.KeyCode.ButtonA
				or k == Enum.KeyCode.E
			)
		then
			scene.advance()
		end
	end)
	local skip, skipLabel = Theme.button("ПРОПУСТИТЬ  ›", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.05, 0),
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

-- DD-085: on a phone the words sit a little higher and smaller, clear of the bottom bar.
local function captionLayout()
	local phone = Theme.phone()
	ui.cap.TextSize = if phone then 28 else 40
	ui.cap.Size = UDim2.new(0.9, 0, 0, if phone then 34 else 48)
	ui.cap.Position = UDim2.new(0.5, 0, if phone then 0.76 else 0.84, 0)
	ui.sub.TextSize = if phone then 16 else 23
	ui.sub.Size = UDim2.new(if phone then 0.86 else 0.8, 0, 0, if phone then 40 else 54)
	ui.sub.Position = UDim2.new(0.5, 0, if phone then 0.76 else 0.84, if phone then 4 else 6)
	ui.plate.Position = UDim2.new(0.5, 0, if phone then 0.775 else 0.845, 0)
	ui.plate.Size = UDim2.new(1, 0, 0, if phone then 96 else 130)
end

local function caption(text: string, subText: string?, color: Color3?)
	captionLayout()
	ui.cap.Text = text
	ui.cap.TextColor3 = color or C.text
	ui.sub.Text = subText or ""
	ui.cap.TextTransparency = 1
	ui.sub.TextTransparency = 1
	tween(ui.cap, 0.4, { TextTransparency = 0 })
	tween(ui.sub, 0.6, { TextTransparency = 0 })
	tween(ui.plate, 0.4, { BackgroundTransparency = if text == "" then 1 else 0.3 })
end

local function letterbox(on: boolean)
	tween(ui.top, 0.5, { Position = UDim2.fromScale(0, if on then 0 else -0.1) })
	tween(ui.bottom, 0.5, { Position = UDim2.fromScale(0, if on then 1 else 1.1) })
	ui.skip.Visible = on
	if not on then
		tween(ui.cap, 0.3, { TextTransparency = 1 })
		tween(ui.sub, 0.3, { TextTransparency = 1 })
		tween(ui.plate, 0.3, { BackgroundTransparency = 1 })
		tween(ui.dark, 0.3, { BackgroundTransparency = 1 })
		-- the text's outline (UIStroke) does not fade with it: clear the words once they are gone
		task.delay(0.35, function()
			if not scene then
				ui.cap.Text = ""
				ui.sub.Text = ""
			end
		end)
	end
end

local TUNNEL_TIME = 2.2 -- seconds from one cave mouth to the other (DD-082)

-- Cues for the tunnel leg's dip to black (the rider enters at tIn).
local function tunnelDip(cues, tIn: number)
	table.insert(cues, {
		tIn + 0.85,
		function()
			tween(ui.dark, 0.15, { BackgroundTransparency = 0 })
		end,
	})
	table.insert(cues, {
		tIn + TUNNEL_TIME - 0.85,
		function()
			tween(ui.dark, 0.25, { BackgroundTransparency = 1 })
		end,
	})
	return cues
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

local heroHidden = false
local function heroVisible(on: boolean)
	heroHidden = not on
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

-- The route and the tunnel -------------------------------------------------------------------------------------

-- An offset in shelter coordinates, turned with the plot the shelter stands on (DD-087).
local function rel(x: number, y: number, z: number): Vector3
	return deps.base.frame():VectorToWorldSpace(Vector3.new(x, y, z))
end

-- The whole ride from the post inside the funnel to the terminal in the courtyard (the cable's own sag):
-- into cave A, the tunnel under the dead city, out of cave B (DD-082). arenaEnd / transitEnd are the
-- indices of the two cave mouths.
local function routeTrack(terminal: Vector3): ({ Vector3 }, number, number)
	local track = {}
	local function add(points)
		for i, p in points do
			if i > 1 or #track == 0 then
				table.insert(track, p)
			end
		end
	end
	local up = Vector3.new(0, Cableway.CABLE_H, 0)
	add(Cableway.track({ Cableway.ARENA_SIDE, Cableway.MOUTH_A + up }))
	local arenaEnd = #track
	add(Cableway.track(Cableway.tunnelAnchors(deps.base.frame())))
	local transitEnd = #track
	add(Cableway.track({ (Cableway.mouthB(deps.base.frame())) + up, terminal }))
	return track, arenaEnd, transitEnd
end

-- The leg through the tunnel (DD-082): the rider rides in at a ride's pace, the screen dips to black
-- while it crosses the long dark run, and it comes out the other end at a ride's pace again.
local function tunnelKeys(keys, tIn: number, dIn: number, dOut: number)
	table.insert(keys, { tIn, dIn })
	table.insert(keys, { tIn + 0.8, dIn + 60 })
	table.insert(keys, { tIn + TUNNEL_TIME - 0.8, dOut - 60 })
	table.insert(keys, { tIn + TUNNEL_TIME, dOut })
	return keys
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

-- Monotone cubic through (time, distance) keys: the rider eases out, speeds through the tunnel, eases in.
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

-- The old metro tunnel under the dead city (DD-082): rock walls and roof on rusted ribs, rails and
-- sleepers on the floor, a caged lamp every few ribs. It exists only while a scene rides through it.
local function buildTunnel(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "StoryTunnel"
	local line = Cableway.tunnelLine(deps.base.frame())
	local W, H = 18, 18
	local rockC, floorC, ribC = rgb(58, 54, 50), rgb(44, 40, 36), rgb(92, 64, 46)
	local lampN = 0
	for i = 1, #line - 1 do
		local a, b = line[i], line[i + 1]
		local len = (b - a).Magnitude
		local frame = CFrame.lookAt(a, b) -- -Z along the tunnel
		local function seg(size: Vector3, x: number, y: number, z: number, color: Color3, mat)
			return block(folder, size, frame * CFrame.new(x, y, z), color, mat)
		end
		local mid = -len / 2
		seg(Vector3.new(W + 2, 1, len + 1), 0, -0.5, mid, floorC, Enum.Material.Ground)
		seg(Vector3.new(W + 2, 1.2, len + 1), 0, H + 0.6, mid, rockC, Enum.Material.Slate)
		for _, x in { -(W / 2 + 0.5), W / 2 + 0.5 } do
			seg(Vector3.new(1, H + 1, len + 1), x, H / 2, mid, rockC, Enum.Material.Slate)
		end
		for _, x in { -2.4, 2.4 } do
			seg(Vector3.new(0.35, 0.3, len), x, 0.19, mid, rgb(80, 72, 64), Enum.Material.Metal) -- clear of the floor: no shared faces
		end
		for d = 4, len - 2, 14 do
			-- ribs stand a hair off the walls and the roof (a shared face flickers, owner playtest DD-083)
			seg(Vector3.new(0.8, H - 0.8, 0.8), -(W / 2 - 0.5), H / 2 - 0.4, -d, ribC, Enum.Material.CorrodedMetal)
			seg(Vector3.new(0.8, H - 0.8, 0.8), W / 2 - 0.5, H / 2 - 0.4, -d, ribC, Enum.Material.CorrodedMetal)
			seg(Vector3.new(W - 1.1, 0.8, 0.8), 0, H - 0.5, -d, ribC, Enum.Material.CorrodedMetal)
			seg(Vector3.new(7, 0.3, 0.9), 0, 0.05, -d - 7, rgb(70, 52, 38), Enum.Material.Wood)
			lampN += 1
			if lampN % 3 == 0 then
				local x = if lampN % 2 == 0 then -(W / 2 - 1) else W / 2 - 1
				local lamp = seg(Vector3.new(0.7, 0.7, 1.2), x, 12.5, -d - 1.2, rgb(255, 190, 110), Enum.Material.Neon)
				local light = Instance.new("PointLight")
				light.Color = rgb(255, 186, 120)
				light.Range = 22
				light.Brightness = 1.4
				light.Shadows = false
				light.Parent = lamp
			end
		end
	end
	-- the cable itself, hanger by hanger under the roof
	Cableway.new(folder, Cableway.tunnelAnchors(deps.base.frame()), {})
	-- DD-083: where the tunnel runs through the funnel wall and the grove's hill, the hillside showed
	-- inside it (grass through the walls, flickering). For the scene the terrain is hollowed out along
	-- the tube on this screen only, and put back exactly as it was when the tunnel goes.
	-- DD-087: only the two ends (cave, ramp) cross the ground; the long run is deep under it (below the
	-- ground's floor), and under the grove it must not dig a trench through the square.
	local terrain = workspace.Terrain
	local saved = {}
	local ends = { { 1, 3 }, { 4, 6 } } -- line points of the funnel end and the grove end
	for _, e in ends do
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		for k = e[1], e[2] do
			lo, hi = lo:Min(line[k]), hi:Max(line[k])
		end
		local pad = Vector3.new(W + 20, 0, W + 20)
		local region = Region3.new(lo - pad - Vector3.new(0, 14, 0), hi + pad + Vector3.new(0, H + 40, 0))
			:ExpandToGrid(4)
		local ok, mats, occ = pcall(function()
			return terrain:ReadVoxels(region, 4)
		end)
		if ok then
			table.insert(saved, { region, mats, occ })
		end
	end
	for i = 1, #line - 1 do
		local a, b = line[i], line[i + 1]
		local len = (b - a).Magnitude
		if i == 3 then
			continue -- the long run
		end
		terrain:FillBlock(
			CFrame.lookAt(a, b) * CFrame.new(0, H / 2, -len / 2),
			Vector3.new(W + 12, H + 12, len + 6),
			Enum.Material.Air
		)
	end
	-- the hill is hollow now: the caves' painted darkness steps aside so the way out shows daylight
	-- (DD-091: and so does the mouth's own lining, which would flicker against this tunnel's walls)
	local darks = {}
	for _, d in workspace:GetDescendants() do
		local mouth = d.Parent and (if d.Parent.Name == "Inner" then d.Parent.Parent else d.Parent)
		if
			d:IsA("BasePart")
			and mouth
			and mouth.Name == "CaveMouth"
			and (d.Name == "Dark" or d.Parent.Name == "Inner")
		then
			d.Transparency = 1
			table.insert(darks, d)
		end
	end
	folder.Destroying:Connect(function()
		for _, d in darks do
			d.Transparency = 0
		end
		for _, row in saved do
			pcall(function()
				terrain:WriteVoxels(row[1], 4, row[2], row[3])
			end)
		end
	end)
	folder.Parent = workspace
	return folder
end

-- The rider: a pallet on four chains under a trolley; on it the hero (a still copy of the own avatar)
-- and, on the way home, the generator.
local function buildRider(cargoKey: string?, glowColor: Color3?)
	local model = Instance.new("Model")
	model.Name = "StoryRider"
	local metal, wood, lime = rgb(52, 48, 44), rgb(150, 106, 62), rgb(176, 236, 60)
	local parts = {} -- { part, offset }
	local function add(size: Vector3, offset: CFrame, color: Color3, material)
		local p = block(model, size, offset, color, material)
		table.insert(parts, { p, offset })
		return p
	end
	local deck = -6.1 -- the pallet's top under the cable (the trolley clears the hero's head)
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
	local withCargo = cargoKey ~= nil
	if cargoKey then
		local f = ReplicatedStorage:FindFirstChild("ArtTemplates")
		local t = f and f:FindFirstChild(cargoKey)
		if t and t:IsA("MeshPart") then
			cargo = t:Clone()
			cargo.Anchored = true
			cargo.CanCollide = false
			cargo.Size = t.Size * math.min(3.8 / t.Size.Y, 2.6 / math.max(t.Size.X, t.Size.Z)) -- fits beside the hero
			cargo.Parent = model
			table.insert(
				parts,
				{ cargo, CFrame.new(1.2, deck + cargo.Size.Y / 2, 0) * CFrame.Angles(0, math.pi / 2, 0) }
			)
			if glowColor then
				-- what rides home is alive: the stunned sample in its tank, the nest's beating heart
				local glow =
					block(model, Vector3.one * 1.5, CFrame.new(), glowColor, Enum.Material.Neon, Enum.PartType.Ball)
				table.insert(parts, { glow, CFrame.new(1.2, deck + cargo.Size.Y * 0.45, 0) })
			end
		else
			add(Vector3.new(2.6, 2.4, 2.6), CFrame.new(1.2, deck + 1.2, 0), rgb(200, 160, 60), Enum.Material.Metal)
		end
	end
	-- the hero: a still copy of the own avatar standing on the pallet
	local hero, heroOffset = nil, nil
	local leapFrom = nil
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
			heroOffset = CFrame.new(if withCargo then -1.3 else 0, deck + feet, 0)
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
		if hero and not leapFrom then
			hero:PivotTo(frame * heroOffset)
		end
	end
	-- DD-093: the hero hops off the pallet onto `to` (k 0..1 along a little arc)
	function rider.leap(to: CFrame, k: number)
		if not hero then
			return
		end
		leapFrom = leapFrom or hero:GetPivot()
		local a, b = leapFrom.Position, to.Position
		local e = k * k * (3 - 2 * k)
		local lift = math.sin(k * math.pi) * 3.2 -- the arc over the drop
		hero:PivotTo(
			CFrame.new(a:Lerp(b, e) + Vector3.new(0, lift, 0))
				* leapFrom.Rotation:Lerp(to.Rotation, math.min(1, k * 1.6))
		)
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
local HOLD_READ = 2.0 -- seconds a hold lingers on its caption before the scene goes on (DD-091)
local function play(def)
	if scene then
		scene.finish()
	end
	local fired = {}
	local s = { t = 0 }
	scene = s
	local holds = def.holds or {}
	table.sort(holds)
	local nextHold = 1
	local function showNext(on: boolean)
		ui.next.Visible = on
		if on then
			ui.nextScale.Scale = 0.6
			tween(ui.nextScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	-- DD-086: a hold does not freeze the frame. The camera carries its last motion on, slowing to a slow
	-- push-in with a breath of sway; on «Дальше» it eases back onto the scripted path.
	local camPrev, camVel = nil, Vector3.zero
	local drift, driftT, driftOff, release = CFrame.identity, 0, Vector3.zero, 0
	local heldOff, heldRot = Vector3.zero, CFrame.identity
	function s.advance()
		if s.waiting then
			s.waiting = false
			nextHold += 1
			showNext(false)
			release = 1
			heldOff, heldRot = driftOff, drift
			Audio.play("ui", 0.35, 1.1)
		end
	end
	-- Studio checks: jump to t past the holds before it
	function s.seekTo(t: number)
		s.t = t
		s.waiting = false
		showNext(false)
		nextHold = 1
		while holds[nextHold] and holds[nextHold] < t do
			nextHold += 1
		end
	end
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
		showNext(false)
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
		local realDt = dt
		if s.frozen or s.waiting then
			dt = 0
		end
		s.t += dt
		local h = holds[nextHold]
		if h and s.t >= h and not s.waiting then
			s.t = h
			s.waiting = true
			s.holdAt = os.clock()
			driftT = 0
		end
		-- owner (DD-091): no «Дальше» — a hold is a breath to read the line, then the scene goes on by itself
		if s.waiting and not s.frozen and os.clock() - (s.holdAt or 0) >= HOLD_READ then
			s.advance()
		end
		if s.waiting and ui.next.Visible then
			ui.nextScale.Scale = 1 + math.sin(os.clock() * 4) * 0.04
		end
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
		local cam = shot.cam(smooth((t - shot.from) / math.max(0.01, shot.to - shot.from)), t)
		if s.waiting and not s.frozen then
			-- the motion carried on, dying away (k = 1.6 /s), plus a slow push-in and a breathing sway
			driftT += realDt
			local w = driftT
			local carry = camVel * (1 - math.exp(-1.6 * w)) / 1.6
			driftOff = carry + cam.LookVector * (0.35 * w / (1 + w * 0.06))
			drift = CFrame.Angles(math.sin(w * 0.55) * 0.006, math.sin(w * 0.4) * 0.012, 0)
		elseif release > 0 then
			-- back onto the path over ~0.9 s
			release = math.max(0, release - realDt / 0.9)
			local k = release * release * (3 - 2 * release)
			driftOff = heldOff * k
			drift = ID_CF:Lerp(heldRot, k)
		else
			driftOff, drift = Vector3.zero, CFrame.identity
		end
		local out = CFrame.new(driftOff) * cam * drift
		if not s.waiting and release == 0 and realDt > 0 then
			if camPrev then
				local v = (cam.Position - camPrev.Position) / realDt
				camVel = if v.Magnitude > 8 then v.Unit * 8 else v
			end
			camPrev = cam
		elseif s.waiting then
			camPrev = nil
		end
		return out
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

-- DD-093: the end of a ride into the funnel. The pallet stops at the post beside the spawn, the hero hops
-- off it and lands on the spot the fight starts from; meanwhile the camera swings round behind the hero
-- to the fight's own view (CameraRig.restPose), which then takes over without a cut (CameraRig.handoff).
local LEAP = 0.75
local SPAWN = Vector3.new(0, 3, -26) -- Maps playerStart (every crater map), the root's height
local function landing(rider, _sp: Vector3?, at: number, length: number)
	local spot, to, rest = nil, nil, nil
	-- the spot is read when the leap starts: the run has put the (hidden) character on its spawn by then
	local function settle()
		if spot then
			return
		end
		local char = player.Character
		local p = char and char:GetPivot().Position
		spot = if p and (Vector3.new(p.X, 0, p.Z) - Vector3.new(SPAWN.X, 0, SPAWN.Z)).Magnitude < 40 then p else SPAWN
		to = CFrame.lookAt(spot, spot + Vector3.zAxis) -- facing the drill, as the fight's camera looks
		rest = CameraRig.restPose(spot)
	end
	local shot = {
		from = at,
		to = length,
		cam = function(_, t)
			settle()
			local side = Cableway.ARENA_SIDE
			local start = CFrame.lookAt(side + Vector3.new(14, 11, -20), side + Vector3.new(0, -4, 0))
			local u = math.clamp((t - at) / (length - at), 0, 1)
			u = u * u * (3 - 2 * u)
			return start:Lerp(rest, u)
		end,
	}
	local function update(t)
		if t >= at then
			settle()
			rider.leap(to, math.clamp((t - at) / LEAP, 0, 1))
		end
	end
	local cue = {
		at + LEAP,
		function()
			settle()
			Fx.ring(Vector3.new(spot.X, 0.4, spot.Z), 6, C.lime, 0.6)
			Fx.emitWith("dust", Vector3.new(spot.X, 0.5, spot.Z), 12, 1.4)
			Audio.play("boom", 0.4, 1.3)
		end,
	}
	return shot, update, cue
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
	local tunnel = buildTunnel()
	local rider = buildRider(nil)
	local snap = lightSnapshot()
	local introKeys = tunnelKeys({ { 8.4, 0 } }, 10.2, grove, rim)
	table.insert(introKeys, { 15.0, L })
	local ride = motion(introKeys)
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
	local landShot, landUpdate, landCue = landing(rider, sp, 15.5, 17.2)
	play({
		length = 17.2,
		holds = { 7.0, 8.3, 15.2 }, -- the shelter, the way out, the Alpha (DD-083; DD-086: the title runs on)
		shots = {
			{
				from = 0,
				to = 7.4,
				cam = function(k)
					-- DD-087: from high over the grove (the Tree, the neighbours' lights) down to the own shelter
					local a = CFrame.lookAt(shelter + rel(30, 78, -170), shelter + Vector3.new(0, 4, 0))
					local b = CFrame.lookAt(shelter + rel(12, 17, -40), shelter + Vector3.new(0, 5, 0))
					-- the descent starts as the title card lifts (3.0 s) and settles before the hold (7.0 s)
					local u = math.clamp((k * 7.4 - 3.0) / 3.4, 0, 1)
					return a:Lerp(b, u * u * (3 - 2 * u))
				end,
			},
			{
				from = 7.4,
				to = 10.55,
				cam = function(k)
					-- from the courtyard: the pallet rides off to the cave in the hill
					local eye = term + rel(16, -2, 10)
					local pos = path.at(s)
					return CFrame.lookAt(eye:Lerp(eye + rel(-2, 3, -4), k), pos + Vector3.new(0, -3, 0))
				end,
			},
			{
				from = 10.55,
				to = 12.45,
				cam = function()
					local pos, dir = path.at(s)
					return chase(pos, dir, 13, -1.5, 2.2)
				end,
			},
			{
				from = 12.45,
				to = 14.6,
				cam = function(k)
					-- inside the funnel: the pallet comes out of the wall, the drill and the swarm below
					local pos = path.at(s)
					local m, f = Cableway.MOUTH_A, Cableway.FACING_A
					local right = f:Cross(Vector3.yAxis)
					local eye = (m + f * 62 + right * 24 + Vector3.new(0, 30, 0)):Lerp(
						m + f * 52 + right * 18 + Vector3.new(0, 24, 0),
						k
					)
					return CFrame.lookAt(eye, pos:Lerp(drill, 0.25) + Vector3.new(0, -4, 0))
				end,
			},
			{
				from = 14.6,
				to = 15.5,
				cam = function(k)
					-- close: the hero slides down to the post inside the funnel
					local pos = path.at(s)
					local side = Cableway.ARENA_SIDE
					local eye = (side + Vector3.new(18, 14, -26)):Lerp(side + Vector3.new(14, 11, -20), k) -- (the post came down 6, DD-091)
					return CFrame.lookAt(eye, pos + Vector3.new(0, -4, 0))
				end,
			},
			landShot,
		},
		update = function(t)
			s = ride(t)
			local pos, dir = path.at(s)
			rider.place(pos, dir, math.sin(t * 1.7) * 0.04)
			landUpdate(t)
		end,
		cues = tunnelDip({
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
					lightRestore(snap, 1.5) -- under the city it does not matter; out of it, the funnel's sunset
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
				10.5,
				function()
					caption(
						"ПОД МЁРТВЫМ ГОРОДОМ",
						"Старый тоннель метро — канатка идёт по нему до самой воронки"
					)
				end,
			},
			{
				12.6,
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
			landCue,
		}, 10.2),
		cleanup = function()
			Audio.fadeStings(1)
			lightRestore(snap)
			rider.destroy()
			tunnel:Destroy()
			ui.cover.Visible = false
			heroVisible(true)
			base.sceneEnd()
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
						"ТУРЕЛЬ У БУРА",
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

-- What each story sortie brings home (DD-075/076): the cargo on the pallet, the spots it wakes up in the
-- shelter, and the next step it pays for (a beam over the workbench).
local HOMECOMING = {
	O01 = {
		cargo = "GENERATOR",
		title = "ГЕНЕРАТОР ДОБЫТ",
		sub = "Канатка с бура увезёт его домой — в убежище в роще",
		transit = {
			"ЧЕРЕЗ ПУСТОШЬ — ДОМОЙ",
			"Тем же тросом ксенит с бура будет приезжать в убежище",
		},
		beats = {
			{
				spot = "GENERATOR",
				title = "УБЕЖИЩЕ ОЖИВАЕТ",
				sub = "Генератор дал свет и ток",
				color = C.gold,
			},
			{
				spot = "WORKBENCH",
				title = "МАСТЕРСКАЯ ЗАРАБОТАЛА",
				sub = "Ток пошёл на верстак",
				color = C.cyan,
			},
			-- DD-112: the gun grows first — the rifle's main module comes with the first win
			{
				spot = "ARMORY",
				title = "ВИНТОВКА ДОРАБОТАНА",
				sub = "«Двойная катушка» встала в ядро: второй разряд рядом с основным",
				color = C.cyan,
			},
		},
		next = {
			structure = "STING",
			title = "ХВАТАЕТ НА ПЕРВУЮ ТУРЕЛЬ",
			sub = "Рой вернётся к буру. «Турель» встанет рядом с ним и будет стрелять вместе с тобой",
		},
	},
	O02 = {
		cargo = "RADIO",
		title = "АНТЕННА ДОБЫТА",
		sub = "Её ждёт радиостанция в убежище",
		transit = { "ДОМОЙ", "Рой без вожака притих — до следующей вылазки" },
		beats = {
			{
				spot = "RADIO",
				title = "РАДИО ЗАГОВОРИЛО",
				sub = "Теперь слышно, когда рой идёт к буру: оборона бура по уровням",
				color = C.orange,
			},
		},
		-- DD-112: the second gun is this sortie's prize (the turret «Разрядник» opens too: the base's goal
		-- comes to it after the new gun's first fight)
		next = {
			spot = "ARMORY",
			marker = { "ВУЛКАН", "Новое оружие" },
			title = "В ОРУЖЕЙНОЙ — ДРОБОВИК «ВУЛКАН»",
			sub = "В упор — стена свинца. Он уже с основным модулем: возьми его в следующую вылазку",
		},
	},
	O03 = {
		cargo = "TANK_FRAME",
		glow = rgb(170, 255, 70),
		title = "ОБРАЗЕЦ ПОЙМАН",
		sub = "Оглушённый плевун едет домой в пробирке",
		transit = { "ДОМОЙ", "Вышка остыла — рой придёт в себя не скоро" },
		beats = {
			{
				spot = "LAB",
				title = "ЛАБОРАТОРИЯ ОТКРЫТА",
				sub = "Первые образцы плевуна в пробирке: изучай рой — а потом выводи свой",
				color = C.violet,
			},
		},
		next = {
			structure = "CRYO",
			title = "ХВАТАЕТ НА «КРИОПОЛЕ»",
			sub = "Всё, что войдёт в поле у бура, увязнет и замедлится",
		},
	},
	O04 = {
		cargo = "POD",
		glow = rgb(200, 120, 255),
		title = "СЕРДЦЕ ГНЕЗДА ДОБЫТО",
		sub = "Оно ещё бьётся — его ждёт лаборатория",
		transit = { "ДОМОЙ", "Без корней рой в воронке поредеет" },
		beats = {
			{
				spot = "LAB",
				title = "СВОЙ РОЙ",
				sub = "Из сердца гнезда выводится своя стая: она стережёт твой бур",
				color = C.violet,
			},
			-- DD-112: the third gun
			{
				spot = "ARMORY",
				title = "ЛУЧЕМЁТ «РАЗЛОМ»",
				sub = "Непрерывная плазма режет шеренги — он уже в оружейной, с основным модулем",
				color = C.cyan,
			},
		},
		next = {
			spot = "LAB",
			marker = { "СВОЙ РОЙ", "Выведи первую стаю" },
			title = "ОТКРЫТЫ ВТОРЖЕНИЯ",
			sub = "Веди свою стаю на чужие буры — ксенит с их канатки твой",
		},
	},
	O05 = {
		cargo = "GEM",
		glow = rgb(255, 120, 200),
		title = "МАТЬ РОЯ ПОВЕРЖЕНА",
		sub = "Её ядро — трофей для убежища",
		transit = { "ДОМОЙ", "Без королевы рой в воронке надолго притихнет" },
		beats = {
			{
				spot = "TROPHY_O05",
				title = "ТРОФЕЙ НА ВИТРИНЕ",
				sub = "Её статуя теперь золотая — гости убежища увидят, кого ты победил",
				color = C.gold,
			},
		},
		next = {
			spot = "ARMORY",
			marker = { "РЕЛЬСОТРОН", "Новое оружие" },
			title = "В ГНЕЗДЕ НАШЁЛСЯ РЕЛЬСОТРОН",
			sub = "Один выстрел — целая колонна. Он уже в оружейной, с основным модулем",
		},
	},
	O06 = {
		cargo = "GEM",
		glow = rgb(255, 130, 50),
		title = "УЛЕЙ ОБЕСТОЧЕН",
		sub = "Сердце пламени из питающего узла едет домой",
		transit = { "ДОМОЙ", "Ночь над пустошью — без узлов рой голодает" },
		beats = {
			{
				spot = "ARMORY",
				title = "СЕРДЦЕ ПЛАМЕНИ",
				sub = "Оно горит в оружейной: «Вулкан» сможет стать «Адской мельницей»",
				color = C.orange,
			},
		},
		next = {
			spot = "ARMORY",
			marker = { "АДСКАЯ МЕЛЬНИЦА", "Форма «Вулкана»" },
			title = "ДАЛЬШЕ — ПОЖИРАТЕЛЬ",
			sub = "Последняя вылазка главы: червь, что точит воронку снизу",
		},
	},
	O07 = {
		cargo = "WORM_HEAD",
		glow = rgb(150, 90, 255),
		title = "ПОЖИРАТЕЛЬ ПОВЕРЖЕН",
		sub = "Его клык и сердце пустоты едут домой",
		transit = { "ДОМОЙ", "Земля под воронкой больше не дрожит" },
		beats = {
			{
				spot = "TROPHY_O07",
				title = "ТРОФЕЙ: ПОЖИРАТЕЛЬ",
				sub = "Три золотые статуи — вся глава на витрине убежища",
				color = C.gold,
			},
		},
		next = {
			spot = "ARMORY",
			marker = { "КОПЬЁ ПУСТОТЫ", "Форма «Разлома»" },
			title = "ГЛАВА ПРОЙДЕНА",
			sub = "Воронка затихла. Дальше — оборона бура по уровням, вторжения и «Копьё пустоты»",
			sting = "victory",
		},
	},
}

function Story.hasHomecoming(opId: string?): boolean
	return opId ~= nil and HOMECOMING[opId] ~= nil
end

-- After a story sortie's first win, ~16–19 s: the cargo and the hero leave the funnel on the cable,
-- cross the wasteland and arrive at the courtyard's terminal; the cargo wakes its spots up one by one,
-- and the camera ends on the workbench with what the loot buys next.
function Story.returnHome(opId: string, onDone)
	local cfg = HOMECOMING[opId] or HOMECOMING.O01
	local base = deps.base
	base.sceneBegin()
	local track, arenaEnd, transitEnd = routeTrack(base.point("TERMINAL"))
	local path = makePath(track)
	local L = path.length
	local tunnel = buildTunnel()
	local rider = buildRider(cfg.cargo, cfg.glow)
	local homeKeys = tunnelKeys({ { 2.2, 0 } }, 4.0, path.dist[arenaEnd], path.dist[transitEnd])
	table.insert(homeKeys, { 8.6, L })
	local ride = motion(homeKeys)
	local s = 0
	local term = base.point("TERMINAL")
	local side = Cableway.ARENA_SIDE
	-- close on the pallet at the post: the hero and the cargo, the funnel behind them
	local nearEye = side + Vector3.new(14, 9, -17) -- above the crystals by the post (it came down 6, DD-091)
	local function spotShot(from: number, to: number, spot: string)
		local at = base.point(spot)
		return {
			from = from,
			to = to,
			cam = function(k)
				-- trophies stand by the courtyard lamps: look at them from the gate side
				local trophy = string.sub(spot, 1, 7) == "TROPHY_"
				local a = CFrame.lookAt(
					at + (if trophy then rel(-12, 9, -16) else rel(12, 10, -17)),
					at + Vector3.new(0, 2.5, 0)
				)
				local b =
					CFrame.lookAt(at + (if trophy then rel(-9, 7, -12) else rel(9, 7, -13)), at + Vector3.new(0, 3, 0))
				return a:Lerp(b, k)
			end,
		}
	end
	local shots = {
		{
			from = 0,
			to = 3.0,
			cam = function(k)
				local pos = path.at(s)
				return CFrame.lookAt(nearEye:Lerp(nearEye + Vector3.new(4, 3, -6), k), pos + Vector3.new(0, -4.5, 0))
			end,
		},
		{
			from = 3.0,
			to = 4.35,
			cam = function(k)
				-- the pallet rides into the cave in the funnel wall
				local pos = path.at(s)
				local m, f = Cableway.MOUTH_A, Cableway.FACING_A
				local right = f:Cross(Vector3.yAxis)
				local eye = (m + f * 34 - right * 16 + Vector3.new(0, 12, 0)):Lerp(
					m + f * 30 - right * 13 + Vector3.new(0, 11, 0),
					k
				)
				return CFrame.lookAt(eye, pos:Lerp(m + Vector3.new(0, 8, 0), 0.5))
			end,
		},
		{
			from = 4.35,
			to = 6.25,
			cam = function()
				local pos, dir = path.at(s)
				return chase(pos, dir, 13, -1.5, 2.2)
			end,
		},
		{
			from = 6.25,
			to = 9.0,
			cam = function(k)
				-- from the side of the courtyard: the cave at the hill's foot, the pallet riding out to the frame
				local eye = term + rel(6, 5, 16)
				return CFrame.lookAt(eye:Lerp(eye + rel(-2, 1, 2), k), path.at(s) + Vector3.new(0, -3, 0))
			end,
		},
	}
	-- DD-086: the win's music rides home with the hero and dies away in the tunnel; the shelter's sting
	-- swells in as the pallet comes out at home
	if not Audio.stingPlaying("triumph") and not Audio.stingPlaying("victory") then
		Audio.sting("triumph", 12, { fadeIn = 1.2, from = 12 })
	end
	local cues = {
		{
			0.3,
			function()
				caption(cfg.title, cfg.sub, C.gold)
			end,
		},
		{
			2.2,
			function()
				Audio.play("dash", 0.5, 0.8)
			end,
		},
		{
			4.4,
			function()
				Audio.fadeStings(4.0)
			end,
		},
		{
			4.4,
			function()
				caption(cfg.transit[1], cfg.transit[2])
			end,
		},
		{
			6.6,
			function()
				caption("ДОМА", "")
				Audio.sting("home", 12, { fadeIn = 1.8, keep = true })
			end,
		},
		{
			8.6,
			function()
				local deck = rider.deckPosition()
				Fx.emitWith("dust", deck, 12, 1.4)
				Audio.play("boom", 0.35, 1.4)
				rider.destroy()
			end,
		},
	}
	tunnelDip(cues, 4.0)
	local t = 9.0
	local holds = {}
	for _, beat in cfg.beats do
		table.insert(shots, spotShot(t, t + 3, beat.spot))
		table.insert(cues, {
			t + 0.3,
			function()
				base.sceneRestore(beat.spot)
				caption(beat.title, beat.sub, beat.color)
			end,
		})
		table.insert(holds, t + 2.8)
		t += 3
	end
	-- the next step: what the loot buys, over the workbench (or what it is still short of)
	local def = cfg.next.structure and Meta.Structures[cfg.next.structure]
	local nextSpot = cfg.next.spot or "WORKBENCH"
	if cfg.beats[#cfg.beats].spot ~= nextSpot then
		table.insert(shots, spotShot(t, t + 3.4, nextSpot))
	else
		shots[#shots].to = t + 3.4
	end
	table.insert(cues, {
		t + 0.3,
		function()
			if not def then
				-- a place in the shelter, not something to buy (DD-078: the own swarm in the lab)
				base.sceneMarker(nextSpot, cfg.next.marker[1], cfg.next.marker[2])
				Audio.play("level", 0.7, 1.5)
				if cfg.next.sting then
					Audio.sting(cfg.next.sting, 12) -- the chapter's end sounds like it
				end
				caption(cfg.next.title, cfg.next.sub, C.lime)
				return
			end
			local prof = deps.profile and deps.profile()
			local enough = prof == nil or (prof.scrap or 0) >= def.cost[1]
			base.sceneMarker(
				"WORKBENCH",
				"СОБЕРИ «" .. def.name .. "»",
				"Для бура · ◆ " .. def.cost[1]
			)
			Audio.play("level", 0.7, 1.5)
			if enough then
				caption(cfg.next.title, cfg.next.sub, C.lime)
			else
				caption(
					"СЛЕДУЮЩАЯ ЦЕЛЬ — «" .. def.name .. "»",
					"Ещё немного ксенита — и он встанет у бура",
					C.lime
				)
			end
		end,
	})
	table.insert(holds, t + 3.1)
	play({
		length = t + 3.4,
		holds = holds,
		shots = shots,
		update = function(time)
			s = ride(time)
			local pos, dir = path.at(s)
			if rider.model.Parent then
				rider.place(pos, dir, math.sin(time * 1.9) * 0.05)
			end
		end,
		cues = cues,
		cleanup = function()
			Audio.fadeStings(1.5)
			rider.destroy()
			tunnel:Destroy()
			base.sceneEnd()
		end,
		onDone = onDone,
	})
end

-- A story sortie's departure (DD-076), ~11 s: the lit shelter, the hero rides the cable out over the
-- wasteland, the funnel and what waits there, the hero at the post.
local DEPARTURE = {
	O02 = {
		title = "ВЫЛАЗКА 2 · РАДИОМАЯК",
		sub = "Антенна старой станции упала в воронку. Без неё радио в убежище молчит",
		transit = { "К БУРУ", "Рой запомнил тебя — и стал хитрее" },
		funnel = {
			"РОЙ УЧИТСЯ ОКРУЖАТЬ",
			"Когда кольцо сомкнётся — получишь Громобой. Новый враг: прыгун",
		},
	},
	O03 = {
		title = "ВЫЛАЗКА 3 · ОБРАЗЕЦ",
		sub = "Лаборатории нужен живой образец роя",
		transit = {
			"К БУРУ",
			"В воронке уцелели тесла-вышки старой электростанции",
		},
		funnel = {
			"ЗАРЯДИ ТЕСЛА-ВЫШКУ",
			"Рой в теле несёт ксенит: убивай его в круге вышки — полный заряд даст разряд, он оглушит всех. Новый враг: плевун",
		},
		focus = Vector3.new(38, 4, 38), -- the tesla tower on the north-east diagonal (Maps coils[1])
		electric = true, -- crackle and thunder over it, not the swarm's roar
	},
	O04 = {
		title = "ВЫЛАЗКА 4 · СЕРДЦЕ ГНЕЗДА",
		sub = "Рой пустил корни в воронке",
		transit = {
			"К БУРУ",
			"Гнёзда — то, из чего рой растёт. Без них он поредеет",
		},
		funnel = {
			"ВЫЖГИ ДВА ГНЕЗДА ИЗ ТРЁХ",
			"Одно стережёт броненосец: броня спереди — заходи сбоку или со спины",
		},
		focus = Vector3.new(-60, 4, 80), -- the first nest site (Maps hiveSites[1])
		focusRing = 14,
		focusColor = C.lime,
		-- the nests open with the fight; the scene shows where they will stand (Maps hiveSites)
		preview = {
			art = "NEST",
			h = 8,
			at = { Vector3.new(-60, 0, 80), Vector3.new(72, 0, -70), Vector3.new(-70, 0, -30) },
		},
	},
	O05 = {
		title = "ВЫЛАЗКА 5 · МАТЬ РОЯ",
		sub = "Королева роя проснулась в тоннелях под воронкой",
		transit = { "К БУРУ", "Она выйдет сама — и пойдёт прямо на бур" },
		funnel = {
			"УБЕЙ МАТЬ РОЯ",
			"Она выйдет из провала метро на севере. Её смерть — конец боя",
		},
		focus = Vector3.new(0, 10, 112), -- where she comes out (Maps bossEntry)
		focusRing = 22,
		focusColor = C.pink,
		focusEye = { Vector3.new(6, 62, -96), Vector3.new(4, 48, -78) }, -- in front and above: the overpass blocks the side
	},
	O06 = {
		title = "ВЫЛАЗКА 6 · КРОВАВАЯ НОЧЬ",
		sub = "Ночью воронка краснеет",
		transit = { "К БУРУ", "Ночью рой кормится от питающих узлов" },
		funnel = {
			"РАЗРУШЬ ОБА УЗЛА",
			"Новый враг — взрывун: рвётся рядом и задевает узлы. Подводи их к узлу",
		},
		focus = Vector3.new(-60, 4, 80), -- the first node (Maps hiveSites[1])
		focusRing = 12,
		focusColor = C.violet,
		preview = { art = "NODE", h = 9, at = { Vector3.new(-60, 0, 80), Vector3.new(72, 0, -70) } },
	},
	O07 = {
		title = "ВЫЛАЗКА 7 · ПОЖИРАТЕЛЬ",
		sub = "Финал главы",
		transit = { "К БУРУ", "Земля у воронки дрожит уже третий день" },
		funnel = {
			"УБЕЙ ПОЖИРАТЕЛЯ",
			"Он поднимется из-под земли и пойдёт на бур. Бей, пока он на поверхности",
		},
		focus = Vector3.new(0, 10, 100), -- where it rises (Maps MAP_HIVE_DEPTHS bossEntry)
		focusRing = 24,
		focusColor = C.violet,
		focusEye = { Vector3.new(6, 62, -84), Vector3.new(4, 48, -66) },
	},
}

function Story.hasDeparture(opId: string?): boolean
	return opId ~= nil and DEPARTURE[opId] ~= nil
end

function Story.depart(opId: string, onDone)
	local cfg = DEPARTURE[opId]
	if not cfg then
		onDone()
		return
	end
	local base = deps.base
	base.sceneBegin()
	heroVisible(false)
	local track, arenaEnd, transitEnd = routeTrack(base.point("TERMINAL"))
	local forward = makePath(track)
	local path = makePath(reversed(track))
	local L = path.length
	local grove, rim = L - forward.dist[transitEnd], L - forward.dist[arenaEnd]
	local tunnel = buildTunnel()
	local rider = buildRider(nil)
	local goKeys = tunnelKeys({ { 1.2, 0 } }, 3.0, grove, rim)
	table.insert(goKeys, { 8.2, L })
	local ride = motion(goKeys)
	local s = 0
	local term = base.point("TERMINAL")
	local drill = Vector3.new(0, 8, 0)
	local sp = player.Character and player.Character:GetPivot().Position or Vector3.new(0, 3, -26)
	local preview = Instance.new("Folder")
	preview.Name = "StoryPreview"
	if cfg.preview then
		local f = ReplicatedStorage:FindFirstChild("ArtTemplates")
		local t = f and f:FindFirstChild(cfg.preview.art)
		for _, at in cfg.preview.at do
			if t and t:IsA("MeshPart") then
				local m = t:Clone()
				m.Anchored = true
				m.CanCollide = false
				m.Size = t.Size * (cfg.preview.h / t.Size.Y)
				m.CFrame = CFrame.new(at + Vector3.new(0, m.Size.Y / 2, 0))
				m.Parent = preview
			end
		end
	end
	preview.Parent = workspace
	local landShot, landUpdate, landCue = landing(rider, sp, 8.4, 10.1)
	play({
		length = 10.1,
		holds = { 7.3 }, -- what this sortie is about (DD-083)
		shots = {
			{
				from = 0,
				to = 3.35,
				cam = function(k)
					-- beside the cable just out of the courtyard: the hero rides past to the cave in the hill
					-- (from the yard's side of the cable: the other side is the old oak's crown, DD-091)
					local eye = term + rel(-8, 0, -16)
					local pos = path.at(s)
					return CFrame.lookAt(eye:Lerp(eye + rel(2, 2, -2), k), pos + Vector3.new(0, -3.5, 0))
				end,
			},
			{
				from = 3.35,
				to = 5.25,
				cam = function()
					local pos, dir = path.at(s)
					return chase(pos, dir, 13, -1.5, 2.2)
				end,
			},
			{
				from = 5.25,
				to = 7.6,
				cam = function(k)
					local pos = path.at(s)
					if cfg.focus then
						-- close on what the sortie is about (the pylon and its circle)
						local f = cfg.focus
						local fe = cfg.focusEye or { Vector3.new(-24, 30, -46), Vector3.new(-16, 22, -36) }
						local eye = (f + fe[1]):Lerp(f + fe[2], k)
						return CFrame.lookAt(eye, f)
					end
					local eye = Vector3.new(-6, 66, -84):Lerp(Vector3.new(-18, 56, -66), k)
					return CFrame.lookAt(eye, drill:Lerp(pos, 0.4))
				end,
			},
			{
				from = 7.6,
				to = 8.4,
				cam = function(k)
					local pos = path.at(s)
					local side = Cableway.ARENA_SIDE
					local eye = (side + Vector3.new(18, 14, -26)):Lerp(side + Vector3.new(14, 11, -20), k) -- (the post came down 6, DD-091)
					return CFrame.lookAt(eye, pos + Vector3.new(0, -4, 0))
				end,
			},
			landShot,
		},
		update = function(t)
			s = ride(t)
			local pos, dir = path.at(s)
			rider.place(pos, dir, math.sin(t * 1.7) * 0.04)
			landUpdate(t)
		end,
		cues = tunnelDip({
			{
				0.2,
				function()
					caption(cfg.title, cfg.sub, C.lime)
				end,
			},
			{
				1.2,
				function()
					Audio.play("dash", 0.6, 0.8)
				end,
			},
			{
				3.3,
				function()
					caption(cfg.transit[1], cfg.transit[2])
				end,
			},
			{
				5.4,
				function()
					caption(cfg.funnel[1], cfg.funnel[2], C.gold)
					if cfg.electric then
						Audio.play("thunder", 0.8, 1)
						Audio.play("arc", 1, 0.8)
						local top = cfg.focus + Vector3.new(0, 14, 0)
						for i = 1, 5 do
							task.delay(i * 0.3, function()
								local a = i * 1.3
								Fx.lightning(
									top,
									cfg.focus + Vector3.new(math.cos(a) * 14, -3, math.sin(a) * 14),
									C.cyan,
									0.5,
									0.25
								)
								Audio.play("arc", 0.7, 0.9 + i * 0.05)
							end)
						end
					else
						Audio.play("roar", 0.45, 0.7)
					end
					if cfg.focus then
						local ground = Vector3.new(cfg.focus.X, 0.4, cfg.focus.Z)
						for i = 0, 2 do
							task.delay(i * 0.5, function()
								Fx.ring(ground, cfg.focusRing or 30, cfg.focusColor or C.cyan, 0.9)
							end)
						end
						Fx.light(cfg.focus + Vector3.new(0, 6, 0), cfg.focusColor or C.cyan, 40, 1.8)
					end
				end,
			},
			landCue,
		}, 3.0),
		cleanup = function()
			rider.destroy()
			tunnel:Destroy()
			preview:Destroy()
			heroVisible(true)
			base.sceneEnd()
		end,
		onDone = onDone,
	})
end

local lastCam = nil
function Story.camera(dt: number): CFrame?
	if scene then
		if heroHidden then
			-- DD-093: the run loads a fresh character (and the first-person fade rewrites the body's
			-- transparency) while a ride in still plays: keep it hidden until the hero lands
			heroVisible(false)
		end
		lastCam = scene.step(dt)
		return lastCam
	end
	return nil
end

-- The frame a scene ended on (DD-093: the fight's camera eases on from it).
function Story.lastCamera(): CFrame?
	return lastCam
end

-- Studio checks: hold the scene at time t (nil = let it run and finish).
function Story.seek(t: number?)
	if not scene then
		return
	end
	if t then
		scene.seekTo(t)
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
	label("THE LAST GROVE", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.new(0.9, 0, 0, 80),
		FontFace = F.display,
		TextSize = 56,
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
