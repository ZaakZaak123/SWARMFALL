--!nonstrict
-- The shelter (DD-052 → DD-057): a green grove far from the crater where the survivor lives between
-- sorties. You walk it: the old bunker, the gate out to the wasteland (ВЫЛАЗКА), the armory, and the
-- prepared spots you bring back to life one by one (generator, workshop, radio, lab, garden) — each
-- restored spot changes the place and opens something. The same functions are buttons on the HUD, so
-- the walk is a pleasure and never a chore. Also owns the first-victory scene: the return home, the
-- generator starts, the lights come on, the camera finds the broken workshop.
-- Each client draws its current shelter room: the same owner's home for everyone visiting it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Meta = require(Shared:WaitForChild("Meta"))
local Ops = require(Shared:WaitForChild("Ops"))
local Goals = require(Shared:WaitForChild("Goals"))
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local Audio = require(script.Parent.Audio)
local Fx = require(script.Parent.Fx)
local Structures = require(script.Parent.Structures)
local Models = require(script.Parent.Models)
local Defs = require(Shared:WaitForChild("Defs"))
local Settings = require(script.Parent.Settings)
local Cableway = require(script.Parent.Cableway)
local Collection = require(Shared:WaitForChild("Collection"))
local SpecimenGallery = require(script.Parent.SpecimenGallery)
local Layout = require(Shared:WaitForChild("ShelterLayout"))
local Grove = require(Shared:WaitForChild("Grove"))
local Chronicle = require(Shared:WaitForChild("Chronicle"))
local PlotDecor = require(script.Parent.PlotDecor)

local new, C, F = Theme.new, Theme.C, Theme.F
local label, tween = Theme.label, Theme.tween

local Base = {}

-- Layout, in shelter coordinates (shared/ShelterLayout: the courtyard centre is the origin, the bunker at
-- +Z, the gate at -Z). DD-087: the shelter stands on its plot in the grove, so every point goes through
-- the plot's frame (position and the turn that faces the gate to the Tree). Spawn (0, -4) facing the bunker.
local frame: CFrame = Grove.frame(1)
local function W(x: number, y: number, z: number): Vector3
	return frame:PointToWorldSpace(Vector3.new(x, y, z))
end
-- a CFrame in shelter coordinates (turned with the plot)
local function WC(x: number, y: number, z: number): CFrame
	return frame * CFrame.new(x, y, z)
end
local L = Layout.Stations
local STATIONS = {
	{
		key = "armory",
		art = L.armory.art,
		h = L.armory.h,
		name = "ОРУЖЕЙНАЯ",
		sub = "Оружие и улучшения",
		icon = "swords",
		color = C.gold,
		x = L.armory.x,
		z = L.armory.z,
	},
	{
		key = "launch",
		art = L.launch.art,
		h = L.launch.h,
		name = "ВЫЛАЗКА",
		sub = "Ворота в пустошь · к буру",
		icon = "play",
		color = C.lime,
		x = L.launch.x,
		z = L.launch.z,
	},
}
-- Prepared spots of the shelter (Meta.Home): rubble until restored, then the thing itself. A restored
-- spot is also a station: the workshop builds the drill's defences, the radio picks the drill defence,
-- the lab shows the samples.
local SPOT_LOOK = {
	GENERATOR = { color = C.gold },
	WORKBENCH = {
		color = C.cyan,
		station = "build",
		stationName = "МАСТЕРСКАЯ",
		stationSub = "Оборона бура: турели, ловушки",
	},
	RADIO = {
		color = C.orange,
		station = "radio",
		stationName = "РАДИОСТАНЦИЯ",
		stationSub = "Оборона бура по уровням",
	},
	LAB = {
		color = C.violet,
		station = "swarm",
		stationName = "ЛАБОРАТОРИЯ",
		stationSub = "Образцы роя",
	},
	GARDEN = { color = C.lime },
}
local SPOTS = {}
for id, s in Layout.Spots do
	SPOTS[id] = table.clone(s)
	for k, v in SPOT_LOOK[id] or {} do
		SPOTS[id][k] = v
	end
end
local LAMPS = Layout.Lamps
-- The grove itself: the bunker, trees, old ruins, a wreck by the gate.
local DECOR = Layout.Decor -- { art, height, x, z, yaw }

local send, actions -- set in init
local folder: Folder
local gui: ScreenGui
local ui = {}
local stationParts = {} -- key -> { pad, ring, beam, board, prompt, light, def }
local lamps = {} -- { head, light }
local goalMarker = nil -- { model, ring, beam, board, slot, structure }
local profile = nil
local lobby = nil
local myId = 0
local active = false
local lampsOn = false
local goal = nil
local scene = nil -- running victory scene
local camp = nil -- camp state (squads + hunters) while in a public camp server
local visitHome = nil -- the restored spots of the shelter being visited (drawn here, on this screen)
local visitSlots = nil -- and that survivor's drill defences (for the workshop shelf)
local visitStock = nil
local lastVisit = nil

local function part(props): BasePart
	local p = new("Part", props)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- A glowing ring lying on the floor: a thin invisible plate with the FX ring texture on top. Its
-- "Transparency" drives the decal (callers animate ring.Transparency through setRing).
local function ringPart(name: string, radius: number, color: Color3, y: number, parent): BasePart
	local r = part({
		Name = name,
		Size = Vector3.new(radius * 2, 0.05, radius * 2),
		Transparency = 1,
		Parent = parent,
	})
	r.CFrame = CFrame.new(0, y, 0)
	new("Decal", {
		Name = "Glow",
		Face = Enum.NormalId.Top,
		Texture = Fx.Tex.ring,
		Color3 = color,
		Transparency = 0.2,
		Parent = r,
	})
	return r
end

local function setRing(r: BasePart, transparency: number, radius: number?)
	local d = r:FindFirstChild("Glow")
	if d then
		d.Transparency = transparency
	end
	if radius then
		r.Size = Vector3.new(radius * 2, 0.05, radius * 2)
	end
end

-- DD-091: the shelter's labels show only near the hero, plus the current goal's (always), and never in a
-- story scene. All of them on at once (twelve always-on-top cards up to 160 studs off) buried the first
-- walk through the yard and the intro's shots under text. { gui, at = world point }.
local NEAR_SHOW, NEAR_HIDE = 24, 30
local nearBoards = {}
local function nearOnly(gui: BillboardGui, at: Vector3)
	table.insert(nearBoards, { gui = gui, at = at })
	gui.Enabled = false
	return gui
end
local function nearEnough(gui: BillboardGui, at: Vector3, root: Vector3?): boolean
	if not root then
		return false
	end
	local d = Vector3.new(at.X - root.X, 0, at.Z - root.Z).Magnitude
	return d < (if gui.Enabled then NEAR_HIDE else NEAR_SHOW)
end

local function board(
	parent: BasePart,
	iconName: string,
	title: string,
	sub: string,
	color: Color3,
	height: number
): BillboardGui
	local b = new("BillboardGui", {
		Size = UDim2.fromOffset(260, 74),
		StudsOffsetWorldSpace = Vector3.new(0, height, 0),
		LightInfluence = 0,
		AlwaysOnTop = true,
		MaxDistance = 160,
		Adornee = parent,
		Parent = parent,
	})
	local d = Icons.disc(iconName, 52, color, 2)
	d.AnchorPoint = Vector2.new(0, 0.5)
	d.Position = UDim2.new(0, 4, 0.5, 0)
	d.Parent = b
	local t = label(title, {
		Name = "Title",
		Position = UDim2.fromOffset(64, 10),
		Size = UDim2.new(1, -64, 0, 28),
		FontFace = F.display,
		TextSize = 24,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = b,
	})
	new("UIStroke", { Color = C.ink, Thickness = 2.5, Transparency = 0.1, Parent = t })
	local s = label(sub, {
		Name = "Sub",
		Position = UDim2.fromOffset(64, 38),
		Size = UDim2.new(1, -64, 0, 20),
		FontFace = F.bodyBold,
		TextSize = 15,
		TextColor3 = color:Lerp(C.white, 0.35),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = b,
	})
	new("UIStroke", { Color = C.ink, Thickness = 2, Transparency = 0.2, Parent = s })
	return b
end

local function prompt(parent: BasePart, actionText: string, objectText: string, onTrigger): ProximityPrompt
	local p = new("ProximityPrompt", {
		ActionText = actionText,
		ObjectText = objectText,
		KeyboardKeyCode = Enum.KeyCode.E,
		GamepadKeyCode = Enum.KeyCode.ButtonX,
		HoldDuration = 0,
		MaxActivationDistance = 10,
		RequiresLineOfSight = false,
		Enabled = false,
		Parent = parent,
	})
	p.Triggered:Connect(onTrigger)
	return p
end

-- World ---------------------------------------------------------------------------------------------------
local function buildWorld()
	folder = new("Folder", { Name = "BaseView", Parent = workspace })
	for _, def in STATIONS do
		local holder = new("Model", { Name = "Station_" .. def.key, Parent = folder })
		local pad = part({
			Name = "Pad",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 9, 9),
			Color = C.ink:Lerp(def.color, 0.12),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.15,
			Parent = holder,
		})
		pad.CFrame = WC(def.x, 0.12, def.z) * CFrame.Angles(0, 0, math.rad(90))
		local ring = ringPart("Ring", 4.8, def.color, 0.3, holder)
		ring.CFrame = WC(def.x, 0.3, def.z)
		local beam = part({
			Name = "Beam",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(14, 0.5, 0.5),
			Color = def.color,
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			Parent = holder,
		})
		beam.CFrame = WC(def.x, 7, def.z) * CFrame.Angles(0, 0, math.rad(90))
		local light =
			new("PointLight", { Color = def.color, Range = 14, Brightness = 1.2, Shadows = false, Parent = pad })
		local bb = board(pad, def.icon, def.name, def.sub, def.color, (def.h or 6) + 2.5)
		local pr = prompt(pad, def.name, def.sub, function()
			if actions and actions[def.key] then
				actions[def.key]()
			end
		end)
		stationParts[def.key] =
			{ holder = holder, pad = pad, ring = ring, beam = beam, board = bb, prompt = pr, light = light, def = def }
	end
	-- floodlights over the yard (dark until the crater is ours)
	for i, xz in LAMPS do
		local m = new("Model", { Name = "Lamp" .. i, Parent = folder })
		local pole = part({
			Name = "Pole",
			Size = Vector3.new(0.7, 11, 0.7),
			Color = Color3.fromRGB(46, 40, 60),
			Material = Enum.Material.Metal,
			Parent = m,
		})
		pole.CFrame = WC(xz[1], 5.5, xz[2])
		pole.CastShadow = true
		local toward = Vector3.new(0, 0, 0) - Vector3.new(xz[1], 0, xz[2])
		local yaw = math.atan2(-toward.X, -toward.Z)
		local head = part({
			Name = "Head",
			Size = Vector3.new(1.6, 0.5, 0.9),
			Color = Color3.fromRGB(70, 64, 86),
			Material = Enum.Material.Neon,
			Parent = m,
		})
		head.CFrame = WC(xz[1], 11.2, xz[2]) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-35), 0, 0)
		local spot = new("SpotLight", {
			Face = Enum.NormalId.Front,
			Angle = 75,
			Range = 40,
			Brightness = 0,
			Color = Color3.fromRGB(255, 236, 200),
			Shadows = false,
			Parent = head,
		})
		lamps[i] = { head = head, light = spot, pole = pole, yaw = yaw }
	end
end

-- Generated models for the stations, lamps and plinths (DD-056). The art templates replicate from the
-- server a moment after join; until then (or if an asset fails) the primitive base stands in.
local function artTemplate(key: string): MeshPart?
	local f = game:GetService("ReplicatedStorage"):FindFirstChild("ArtTemplates")
	local t = f and f:FindFirstChild(key)
	return if t and t:IsA("MeshPart") then t else nil
end

local function artModel(key: string, height: number, cf: CFrame, parent: Instance): MeshPart?
	local t = artTemplate(key)
	if not t then
		return nil
	end
	local m = t:Clone()
	m.Size = t.Size * (height / t.Size.Y)
	m.CFrame = cf * CFrame.new(0, m.Size.Y / 2, 0)
	m.CastShadow = true
	m.CanCollide = true -- DD-091: the shelter's models are solid (the hero walked through them); bushes opt out
	m.Parent = parent
	return m
end

-- The grove (trees, ruins, the bunker) and each station's model at the back of its pad, front to the
-- camera; the bare beam goes away once the model is there.
local decorDone = false
local spotParts = {} -- id -> { holder, ring, board, prompt, light, model, rubble, restored }
local restoredShown = {} -- spots whose restored look is on screen (to animate only real changes)
local bulbs = {} -- courtyard string lights (on with the generator)

local function dressStations()
	for _, sp in stationParts do
		local def = sp.def
		if def.art and not sp.model then
			local yaw = math.clamp(-def.x / 60, -0.35, 0.35)
			local m = artModel(def.art, def.h, WC(def.x, 0.25, def.z + 1.6) * CFrame.Angles(0, yaw, 0), sp.holder)
			if m then
				sp.model = m
				sp.beam.Transparency = 1
				sp.beam.Parent = nil
			end
		end
	end
	if not decorDone then
		decorDone = true
		local grove = new("Folder", { Name = "Grove", Parent = folder })
		for _, d in DECOR do
			local m = artModel(d[1], d[2], WC(d[3], 0, d[4]) * CFrame.Angles(0, d[5], 0), grove)
			if m then
				m.CanCollide = d[1] ~= "BUSH"
			end
		end
	end
	for _, l in lamps do
		if not l.model then
			local pos = l.head.Position
			local m = artModel(
				"FLOODLIGHT",
				11,
				CFrame.new(pos.X, 0, pos.Z) * frame.Rotation * CFrame.Angles(0, l.yaw + math.pi, 0),
				l.head.Parent
			)
			if m then
				l.model = m
				l.pole.Transparency = 1
				l.head.Transparency = 1
				l.head.CFrame = CFrame.new(pos.X, 10.4, pos.Z)
					* frame.Rotation
					* CFrame.Angles(0, l.yaw, 0)
					* CFrame.Angles(math.rad(-35), 0, 0)
			end
		end
	end
	-- a spot that was waiting for its model gets it now
	for id in spotParts do
		restoredShown[id] = nil
	end
end

-- Spots ----------------------------------------------------------------------------------------------------
local function buildSpots()
	for _, id in Meta.HomeOrder do
		local def = Meta.Home[id]
		local sd = SPOTS[id]
		local holder = new("Model", { Name = "Spot_" .. id, Parent = folder })
		local ring = ringPart("Ring", 4, sd.color, 0.3, holder)
		ring.CFrame = WC(sd.x, 0.3, sd.z)
		local light = new(
			"PointLight",
			{ Color = Color3.fromRGB(255, 214, 160), Range = 12, Brightness = 0, Shadows = false, Parent = ring }
		)
		local bb = board(ring, def.icon, def.name, "", sd.color, (sd.h or 5) + 2.5)
		local pr = prompt(ring, "Восстановить", def.name, function()
			if actions and actions.spot then
				actions.spot(id)
			end
		end)
		pr.MaxActivationDistance = 9
		spotParts[id] = { holder = holder, ring = ring, board = bb, prompt = pr, light = light, def = def, sd = sd }
	end
	-- string lights across the courtyard, from the bunker's corners to the front lamps
	local runs =
		{ { W(-7, 7, 21.5), W(-32, 10, -20) }, { W(7, 7, 21.5), W(32, 10, -22) }, { W(-7, 7, 21.5), W(7, 7, 21.5) } }
	for _, r in runs do
		local a, b = r[1], r[2]
		local n = math.floor((b - a).Magnitude / 3)
		local prev = nil
		for k = 0, n do
			local t = k / n
			local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * 2.2, 0)
			if prev then
				-- the wire the bulbs hang on
				local wire = part({
					Name = "Wire",
					Size = Vector3.new(0.06, 0.06, (p - prev).Magnitude),
					Color = Color3.fromRGB(30, 28, 26),
					Material = Enum.Material.SmoothPlastic,
					Parent = folder,
				})
				wire.CFrame = CFrame.lookAt((p + prev) / 2, p)
			end
			prev = p
			local bulb = part({
				Name = "Bulb",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.34, 0.34, 0.34),
				Color = Color3.fromRGB(90, 80, 70),
				Material = Enum.Material.SmoothPlastic,
				Parent = folder,
			})
			bulb.CFrame = CFrame.new(p)
			table.insert(bulbs, bulb)
		end
	end
end

-- The cableway terminal (DD-065) ------------------------------------------------------------------------
-- At the courtyard's edge, in sight of the camp camera: the end of the cable from the drill in the funnel. Utility arrives here in the same crates
-- that leave the drill in a fight; the stack beside the frame grows with the utility on hand.
local TERMINAL = Layout.Terminal
local cable = nil
local pileShown = -1
local pileFolder = nil
local pendingDelivery = 0
local lastScrap = nil

local function buildTerminal()
	local t = TERMINAL
	local holder = new("Model", { Name = "Terminal", Parent = folder })
	local metal = Color3.fromRGB(84, 78, 70)
	part({
		Name = "Slab",
		Size = Vector3.new(7, 0.5, 10),
		CFrame = WC(t.x, 0.25, t.z),
		Color = Color3.fromRGB(122, 118, 110),
		Material = Enum.Material.Concrete,
		Parent = holder,
	})
	-- the frame stands across the cable, which comes in from the east beyond the trees
	for _, s in { -1, 1 } do
		part({
			Size = Vector3.new(0.6, 8.8, 0.6),
			CFrame = WC(t.x, 4.4, t.z + s * 2.8),
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = holder,
		})
	end
	local beam = part({
		Name = "Beam",
		Size = Vector3.new(0.8, 0.6, 6.8),
		CFrame = WC(t.x, 8.9, t.z),
		Color = metal,
		Material = Enum.Material.Metal,
		Parent = holder,
	})
	-- the shelter's lime: the same mark as on every crate that leaves the drill
	part({
		Size = Vector3.new(0.85, 0.25, 6.9),
		CFrame = WC(t.x, 8.5, t.z),
		Color = Color3.fromRGB(176, 236, 60),
		Material = Enum.Material.SmoothPlastic,
		Parent = holder,
	})
	nearOnly(
		board(
			beam,
			"reactor",
			"КАНАТКА С БУРА",
			"Ксенит из воронки — в убежище",
			C.lime,
			3.2
		),
		beam.Position
	)
	-- out of the cave at the foot of the hill (the tunnel from the funnel, DD-082) to the frame
	local mouth = Layout.Cave
	Cableway.cave(folder, W(mouth.x, 0, mouth.z), frame:VectorToWorldSpace(Vector3.new(mouth.fx, 0, mouth.fz)))
	cable = Cableway.new(folder, { W(mouth.x, Cableway.CABLE_H, mouth.z), W(t.x, 8.4, t.z) }, {})
end

-- The stack of crates beside the terminal: more utility on hand, more crates.
local function setPile(scrap: number)
	local n = if scrap <= 0 then 0 elseif scrap < 300 then 1 elseif scrap < 1000 then 2 elseif scrap < 3000 then 3 else 4
	if n == pileShown then
		return
	end
	pileShown = n
	if pileFolder then
		pileFolder:Destroy()
	end
	pileFolder = new("Folder", { Name = "Pile", Parent = folder })
	local t = TERMINAL
	-- stacks of the very crates the cable brings (wood, the lime band), two or three high
	for i, o in { { 3.6, 2.6, 0.3, 2 }, { 3.4, -2.4, -0.4, 3 }, { 6.4, 0.4, 1.1, 2 }, { 6.6, 4.2, 2.2, 1 } } do
		if i > n then
			break
		end
		local base = WC(t.x + o[1], 0.5, t.z + o[2]) * CFrame.Angles(0, o[3], 0)
		for k = 0, o[4] - 1 do
			Cableway.crate(pileFolder, base * CFrame.new(0, k * 1.95, 0) * CFrame.Angles(0, k * 0.35, 0))
		end
	end
end

-- A floating "+N КСЕНИТ" over the terminal as the last crate of a delivery lands.
local function deliveryPop(amount: number)
	local at = new("Attachment", { Parent = workspace.Terrain })
	at.WorldPosition = W(TERMINAL.x, 11, TERMINAL.z)
	local b = new(
		"BillboardGui",
		{ Size = UDim2.fromOffset(240, 44), AlwaysOnTop = true, LightInfluence = 0, Adornee = at, Parent = at }
	)
	local l = label(
		"+" .. Theme.commas(amount) .. " КСЕНИТ",
		{ Size = UDim2.fromScale(1, 1), FontFace = F.display, TextSize = 28, TextColor3 = C.pink, Parent = b }
	)
	new("UIStroke", { Color = C.ink, Thickness = 2.5, Parent = l })
	tween(b, 1.6, { StudsOffsetWorldSpace = Vector3.new(0, 4, 0) })
	task.delay(0.9, function()
		tween(l, 0.7, { TextTransparency = 1 })
	end)
	task.delay(1.7, function()
		at:Destroy()
	end)
end

-- Utility that came in (a reward, a harvest) arrives as crates along the cable.
local function deliver(amount: number)
	if not cable or amount <= 0 then
		return
	end
	local n = math.clamp(math.ceil(amount / 60), 1, 6)
	cable:send(n, function(i, total)
		Fx.ring(W(TERMINAL.x, 0.6, TERMINAL.z), 4, C.lime, 0.5)
		Audio.play("orb", 0.6, 0.8 + i * 0.05)
		if i == total then
			deliveryPop(amount)
			setPile(profile and profile.scrap or 0)
		end
	end, 46)
end

local labResearch, labOwner, labOwn = {}, nil, true
local gallery = nil
local updateTank

-- The look of a spot: rubble until restored; restored = its model, warm light, and (animate) a burst.
local function showSpot(id: string, restored: boolean, animate: boolean)
	local sp = spotParts[id]
	if not sp then
		return
	end
	local sd = sp.sd
	local base = WC(sd.x, 0.25, sd.z + 0.8) * CFrame.Angles(0, sd.yaw, 0)
	if restored then
		if sp.rubble then
			sp.rubble:Destroy()
			sp.rubble = nil
		end
		if not sp.model or not sp.model.Parent then
			if id == "LAB" then
				sp.model = new("Model", { Name = "Laboratory", Parent = sp.holder })
				gallery = SpecimenGallery.new(base, sp.model, artModel, function(kind)
					if actions and actions.collection then
						actions.collection(labResearch, labOwner, kind, labOwn)
					end
				end)
				gallery:update(labResearch, true)
			else
				sp.model = artModel(sd.art, sd.h, base, sp.holder)
				if sp.model then
					sp.model.CanCollide = true
				end
			end
		end
		sp.light.Brightness = if id == "GENERATOR" or id == "GARDEN" or id == "WORKBENCH" then 1.4 else 0.8
		if animate and sp.model then
			local pos = sp.model:GetPivot().Position
			Fx.emitWith("dust", pos, 14, 1.6)
			for k = 1, 6 do
				local a = k / 6 * math.pi * 2
				Fx.emitWith(
					"streak",
					pos + Vector3.yAxis,
					3,
					0.8,
					sd.color,
					Vector3.new(math.cos(a), 1.2, math.sin(a)).Unit
				)
			end
			Fx.ring(W(sd.x, 0.4, sd.z), 7, sd.color, 0.8)
			Fx.light(pos + Vector3.yAxis * 3, Color3.fromRGB(255, 220, 170), 24, 1.2)
			Audio.play("evolve", 0.5, 1.3)
			if sp.model:IsA("BasePart") then
				local final = sp.model.CFrame
				sp.model.CFrame = final * CFrame.new(0, -sd.h * 0.6, 0)
				tween(sp.model, 0.9, { CFrame = final }, Enum.EasingStyle.Back)
			end
		end
	else
		if sp.model then
			if id == "LAB" then
				gallery = nil
			end
			sp.model:Destroy()
			sp.model = nil
		end
		if not sp.rubble or not sp.rubble.Parent then
			sp.rubble = artModel("RUBBLE", 1.9, base, sp.holder)
		end
		sp.light.Brightness = 0
	end
end

-- Each discovered species owns a permanent tank; consumable DNA is a separate system.
updateTank = function()
	if gallery then
		gallery:update(labResearch, true)
	end
end

local function labText(): string
	local summary = Collection.summary(labResearch)
	return string.format(
		"Видов %d/%d · полных %d · эталонов %d",
		summary.found,
		summary.total,
		summary.complete,
		summary.exemplary
	)
end

-- The workshop shelf (DD-062): every defence made on the workbench stands here as a small model, so
-- the home shows what guards the drill out in the danger zone. Rebuilt only when the set changes.
local shelfKey = nil
local shelfFolder = nil
local function setShelf(slots, workshop: boolean)
	local list = {}
	for _, s in slots or {} do
		table.insert(list, { id = s.id, lvl = s.lvl })
	end
	table.sort(list, function(a, b)
		if a.id ~= b.id then
			return a.id < b.id
		end
		return a.lvl > b.lvl
	end)
	local key = tostring(workshop)
	for _, it in list do
		key ..= it.id .. it.lvl
	end
	if key == shelfKey then
		return
	end
	shelfKey = key
	if shelfFolder then
		shelfFolder:Destroy()
		shelfFolder = nil
	end
	if not workshop then
		return
	end
	local sd = SPOTS.WORKBENCH
	local at = W(sd.x + 7.5, 0, sd.z + 2.5)
	shelfFolder = new("Model", { Name = "Shelf", Parent = folder })
	local shelf = artModel("SHELF", 4.6, CFrame.new(at) * frame.Rotation * CFrame.Angles(0, -0.25, 0), shelfFolder)
	local anchor = shelf
		or part({
			Name = "ShelfAnchor",
			Size = Vector3.new(6, 0.4, 1.6),
			Color = Color3.fromRGB(110, 80, 50),
			Material = Enum.Material.Wood,
			Parent = shelfFolder,
		})
	if not shelf then
		anchor.CFrame = CFrame.new(at + Vector3.new(0, 2, 0))
	end
	local base = CFrame.new(at) * frame.Rotation * CFrame.Angles(0, -0.25, 0)
	for i, it in list do
		local row = (i - 1) // 4 -- three shelves, four places each
		local col = (i - 1) % 4
		local ok, m = pcall(Structures.model, it.id, it.lvl, false)
		if ok and m then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CastShadow = false
				elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
					d:Destroy()
				end
			end
			local _, size = m:GetBoundingBox()
			pcall(m.ScaleTo, m, m:GetScale() * (0.95 / math.max(size.X, size.Y, size.Z, 0.1)))
			local cf, sz = m:GetBoundingBox()
			m.WorldPivot = CFrame.new(cf.X, cf.Y - sz.Y / 2, cf.Z)
			m:PivotTo(
				base
					* CFrame.new(-1.4 + col * 0.93, ({ 3.05, 1.65, 0.3 })[row + 1] or 0.3, 0)
					* CFrame.Angles(0, math.pi, 0)
			)
			m.Parent = shelfFolder
		end
	end
	local holder = shelf or anchor
	-- the label sits at the shelf's foot, on the camera side: above it the workshop's own sign covers it
	local at = new("Attachment", { Name = "Label", Parent = holder })
	at.WorldCFrame = WC(sd.x + 7.5, 0.6, sd.z - 0.6)
	local b = nearOnly(
		new("BillboardGui", {
			Size = UDim2.fromOffset(190, 36),
			LightInfluence = 0,
			AlwaysOnTop = true,
			MaxDistance = 100,
			Adornee = at,
			Parent = holder,
		}),
		at.WorldPosition
	)
	local t = label(
		string.format("ДЛЯ БУРА · %d/%d", #list, Meta.SocketCount),
		{ Size = UDim2.new(1, 0, 0, 20), FontFace = F.display, TextSize = 16, TextColor3 = C.cyan, Parent = b }
	)
	new("UIStroke", { Color = C.ink, Thickness = 2, Parent = t })
	local s2 = label(
		if #list == 0
			then "Собери первую турель на верстаке"
			else "Стоит у бура в опасной зоне",
		{
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, 0, 0, 16),
			FontFace = F.bodyBold,
			TextSize = 12,
			TextColor3 = C.dim,
			Parent = b,
		}
	)
	new("UIStroke", { Color = C.ink, Thickness = 1.5, Parent = s2 })
end

local function setBulbs(on: boolean)
	for i, b in bulbs do
		b.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		b.Color = if on
			then (if i % 3 == 0 then Color3.fromRGB(230, 140, 70) else Color3.fromRGB(220, 170, 90))
			else Color3.fromRGB(90, 80, 70)
	end
end

local function setLamps(on: boolean, instant: boolean?)
	lampsOn = on
	for i, l in lamps do
		local function apply()
			l.light.Brightness = if on then 2.2 else 0
			l.head.Color = if on then Color3.fromRGB(190, 170, 140) else Color3.fromRGB(70, 64, 86)
			if on and not instant then
				Fx.light(l.head.Position, Color3.fromRGB(255, 240, 210), 18, 0.3)
				Audio.play("ui", 0.5, 0.7 + i * 0.05)
			end
		end
		if instant or not on then
			apply()
		else
			task.delay((i - 1) * 0.28, apply)
		end
	end
end

-- The lit socket of a build goal: a hologram of the structure, a pulsing ring and a beam over it.
local function clearGoalMarker()
	if goalMarker then
		goalMarker.holder:Destroy()
		goalMarker = nil
	end
end

-- The lit spot of the current goal: a pulsing ring and a beam over a place in the shelter.
local function showGoalMarker(pos: Vector3, color: Color3, title: string, sub: string, _iconName: string)
	local key = tostring(pos) .. "|" .. title .. "|" .. sub
	if goalMarker and goalMarker.key == key then
		return
	end
	clearGoalMarker()
	local holder = new("Model", { Name = "GoalMarker", Parent = folder })
	local ring = ringPart("Ring", 4.6, color, 0.34, holder)
	ring.CFrame = CFrame.new(pos.X, 0.34, pos.Z)
	-- (owner, DD-091: no pillar of light into the sky over the goal — the ring, the sign and the chevron
	-- at the hero's feet lead the way)
	goalMarker = { holder = holder, ring = ring, key = key }
end

-- Leading the player (DD-082, owner playtest: «каждый шаг подсвечивать и вести игрока к действию»).
-- Where the current goal happens in the shelter.
local function goalTarget(): Vector3?
	if not goal then
		return nil
	end
	if (goal.station == "home" or goal.station == "swarm") and goal.spot and SPOTS[goal.spot] then
		local sd = SPOTS[goal.spot]
		return W(sd.x, 0, sd.z)
	elseif goal.station == "build" then
		return W(SPOTS.WORKBENCH.x, 0, SPOTS.WORKBENCH.z)
	elseif goal.station == "launch" then
		return W(0, 0, -30)
	elseif goal.station == "armory" then
		return W(STATIONS[1].x, 0, STATIONS[1].z)
	end
	return nil
end

-- A lime chevron on the ground by the hero, pointing the way to the goal.
local arrow = nil
local function arrowModel(): Model
	if arrow and arrow.Parent then
		return arrow
	end
	arrow = new("Model", { Name = "GoalArrow" })
	for k = 0, 1 do
		for _, side in { -1, 1 } do
			local p = part({
				Name = "Arm",
				Size = Vector3.new(0.45, 0.2, 2.2),
				Color = C.lime,
				Material = Enum.Material.Neon,
				Transparency = 0.1 + k * 0.35,
				Parent = arrow,
			})
			p:SetAttribute("Off", Vector3.new(side * 0.62, 0, 0.45 + k * 1.9))
			p:SetAttribute("Yaw", side * math.rad(34))
		end
	end
	arrow.Parent = folder
	return arrow
end

local revealedKey = nil -- the goal the camera last flew to
local activeFor = 0 -- seconds the player has been walking the shelter (a fly-over waits for them to settle)
local revealGui = nil
local function revealCaption(title: string, sub: string, show: boolean)
	if not revealGui then
		revealGui = new("ScreenGui", {
			Name = "SporeGoalReveal",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			DisplayOrder = 40,
			Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"),
		})
		local plate = new("Frame", {
			Name = "Plate",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.8),
			Size = UDim2.new(1, 0, 0, 140),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = revealGui,
		})
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.25, 0.3),
				NumberSequenceKeypoint.new(0.75, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = plate,
		})
		label("ДАЛЬШЕ", {
			Name = "Tag",
			Position = UDim2.new(0, 0, 0, 14),
			Size = UDim2.new(1, 0, 0, 20),
			FontFace = F.head,
			TextSize = 16,
			TextColor3 = C.lime,
			TextTransparency = 1,
			Parent = plate,
		})
		label("", {
			Name = "Title",
			Position = UDim2.new(0, 0, 0, 36),
			Size = UDim2.new(1, 0, 0, 44),
			FontFace = F.display,
			TextSize = 38,
			TextTransparency = 1,
			Parent = plate,
		})
		label("", {
			Name = "Sub",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 84),
			Size = UDim2.new(0.7, 0, 0, 48),
			FontFace = F.bodyBold,
			TextSize = 20,
			TextWrapped = true,
			TextTransparency = 1,
			Parent = plate,
		})
	end
	local plate = revealGui:FindFirstChild("Plate") :: Frame
	if show then
		(plate:FindFirstChild("Title") :: TextLabel).Text = title;
		(plate:FindFirstChild("Sub") :: TextLabel).Text = sub
	end
	local k = if show then 0 else 1
	tween(plate, 0.35, { BackgroundTransparency = if show then 0.2 else 1 })
	for _, n in { "Tag", "Title", "Sub" } do
		tween(plate:FindFirstChild(n), 0.35, { TextTransparency = k })
	end
end

-- The camera flies to the place of a new goal, holds while its title reads, and flies back.
local REVEAL_TIME = 4.6
local function startReveal(target: Vector3, hero: Vector3)
	local cam = workspace.CurrentCamera
	local from = cam.CFrame
	local flat = Vector3.new(target.X - hero.X, 0, target.Z - hero.Z)
	local dir = if flat.Magnitude > 1 then flat.Unit else Vector3.zAxis
	local right = dir:Cross(Vector3.yAxis)
	local eye = target - dir * 20 + right * 8 + Vector3.new(0, 13, 0)
	local shot = CFrame.lookAt(eye, target + Vector3.new(0, 3, 0))
	local t = 0
	revealCaption(goal and goal.title or "", goal and goal.text or "", true)
	Audio.play("level", 0.7, 1.3)
	scene = {
		step = function(dt: number): CFrame?
			t += dt
			if game:GetService("RunService"):IsStudio() and workspace:GetAttribute("SwarmHoldScene") then
				t = math.min(t, 2) -- Studio checks: hold the shot for a screenshot
			end
			if t >= REVEAL_TIME then
				scene = nil
				revealCaption("", "", false)
				return nil
			end
			if t > REVEAL_TIME - 0.9 and t - dt <= REVEAL_TIME - 0.9 then
				revealCaption("", "", false)
			end
			local k = 1
			if t < 1 then
				k = t
			elseif t > REVEAL_TIME - 0.9 then
				k = (REVEAL_TIME - t) / 0.9
			end
			k = k * k * (3 - 2 * k)
			return from:Lerp(shot * CFrame.new(0, 0, -t * 0.6), k)
		end,
	}
end

-- Showcase row (DD-054) -----------------------------------------------------------------------------------
-- In front of the drill: the favourite gun on a stand and one pedestal per boss. A beaten boss stands in
-- gold; one not yet beaten is a faint hologram with the hunt that earns it — a goal you can walk up to.
-- Shows the base's owner: yours, or the hunter you are visiting.
local TROPHIES = Layout.Trophies
local SHOW_Z = Layout.ShowZ -- shelter coordinates
local showFolder = nil
local showKey = nil
local showEntry = nil -- the last showcase entry (a story scene can light a trophy on it, DD-079)
local spinners = {} -- { model, cf, height }

-- Scale to a height and move the pivot to the bottom centre, so it stands and spins in place.
local function fitTo(model: Model, height: number, longest: boolean?)
	local _, size = model:GetBoundingBox()
	local k = if longest
		then height / math.max(size.X, size.Y, size.Z, 0.1)
		else height / math.max(size.Y, size.X * 0.6, size.Z * 0.6, 0.1)
	pcall(model.ScaleTo, model, model:GetScale() * k)
	local cf, sz = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(cf.X, cf.Y - sz.Y / 2, cf.Z)
end

local function pedestal(x: number, color: Color3, lit: boolean): BasePart
	local plinth = artModel("PLINTH", 1.3, WC(x, 0, SHOW_Z), showFolder)
	local base = part({
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 5.6, 5.6),
		Color = Color3.fromRGB(34, 28, 48),
		Material = Enum.Material.Slate,
		Parent = showFolder,
	})
	base.CFrame = WC(x, 0.6, SHOW_Z) * CFrame.Angles(0, 0, math.rad(90))
	base.CastShadow = true
	if plinth then
		base.Transparency = 1 -- the generated plinth carries the look; this part stays as the anchor
		plinth.Size = Vector3.new(5.6, plinth.Size.Y, 5.6)
		plinth.CFrame = WC(x, plinth.Size.Y / 2, SHOW_Z)
	end
	local ring = ringPart("Ring", 3.2, color, 1.24, showFolder)
	ring.CFrame = WC(x, 1.24, SHOW_Z)
	setRing(ring, if lit then 0.1 else 0.7)
	if lit then
		new("PointLight", { Color = color, Range = 9, Brightness = 1.2, Shadows = false, Parent = base })
	end
	return base
end

local function plaque(base: BasePart, title: string, sub: string, color: Color3)
	-- the pedestal is a cylinder lying on its side, so an offset from it would go sideways: hang the
	-- plaque from a point above it instead
	local at = new("Attachment", { Name = "Plaque", Parent = base })
	at.WorldCFrame = CFrame.new(base.Position + Vector3.new(0, 7.5, 0))
	local b = nearOnly(
		new("BillboardGui", {
			Size = UDim2.fromOffset(190, 42),
			LightInfluence = 0,
			AlwaysOnTop = true, -- the statues stand in front of it from the camp camera
			MaxDistance = 90,
			Adornee = at,
			Parent = base,
		}),
		at.WorldPosition
	)
	local t = label(
		title,
		{ Size = UDim2.new(1, 0, 0, 22), FontFace = F.display, TextSize = 17, TextColor3 = color, Parent = b }
	)
	new("UIStroke", { Color = C.ink, Thickness = 2, Parent = t })
	local s2 = label(sub, {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 16),
		FontFace = F.bodyBold,
		TextSize = 13,
		TextColor3 = C.dim,
		Parent = b,
	})
	new("UIStroke", { Color = C.ink, Thickness = 1.5, Parent = s2 })
end

local function statue(model: Model, gold: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = gold
			if gold then
				d.Material = Enum.Material.Metal
				d.Color = Color3.fromRGB(232, 182, 72)
			else
				-- not beaten yet: a pale stone silhouette, a goal rather than an alien hologram
				d.Material = Enum.Material.SmoothPlastic
				d.Color = Color3.fromRGB(150, 162, 170)
				d.Transparency = math.max(d.Transparency, 0.6)
			end
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
		elseif
			d:IsA("Decal")
			or d:IsA("Texture")
			or d:IsA("SurfaceAppearance")
			or d:IsA("Light")
			or d:IsA("ParticleEmitter")
		then
			d:Destroy()
		end
	end
end

-- entry: a Showcase entry (or the same fields built from the own profile); nil hides the row.
local decorFolder, decorKey = nil, nil -- DD-090: the seasonal decoration up in the yard
function Base.setShowcase(entry)
	showEntry = entry
	local want = entry and entry.decor or nil
	if want ~= decorKey or (decorFolder and not decorFolder.Parent) then
		decorKey = want
		if decorFolder then
			decorFolder:Destroy()
		end
		decorFolder = PlotDecor.build(want, frame, folder)
	end
	labResearch = (entry and entry.collection) or (if entry then { EN_SPITTER = entry.sample or 0 } else {})
	labOwner = entry and entry.name
	labOwn = entry ~= nil and entry.id == Players.LocalPlayer.UserId
	updateTank()
	local key = if entry
		then table.concat(
			{ entry.id, entry.weapon, tostring(entry.form), entry.mastery, entry.siege, tostring(entry.trophyKey) },
			"|"
		)
		else "none"
	if key == showKey then
		return
	end
	showKey = key
	if showFolder then
		showFolder:Destroy()
	end
	table.clear(spinners)
	if not entry then
		showFolder = nil
		return
	end
	showFolder = new("Folder", { Name = "Showcase", Parent = folder })
	-- the gun
	local wdef = Defs.Weapons[entry.weapon]
	if wdef then
		local evo = entry.form and Defs.Evolutions[entry.form]
		local base = pedestal(-2, C.cyan, true)
		local ok, gun = pcall(Models.weapon, entry.weapon, evo ~= nil, true)
		if ok and gun then
			for _, d in gun:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
				end
			end
			fitTo(gun, 5, true)
			gun.Parent = showFolder
			table.insert(spinners, { model = gun, cf = WC(-2, 2.2, SHOW_Z), speed = 0.6 })
		end
		plaque(
			base,
			if evo then evo.name else wdef.name,
			string.format("Любимое оружие · M%d", entry.mastery or 1),
			C.cyan
		)
	end
	-- the trophies
	for i, t in TROPHIES do
		local x = Layout.trophyX(i)
		local won = entry.won and entry.won[t.op]
		local base = pedestal(x, if won then C.gold else C.dim, won)
		local ok, m = pcall(Models.creature, t.kind)
		if ok and m then
			statue(m, won)
			fitTo(m, if t.kind == 10 then 5 else 6, t.kind == 9) -- the Devourer is long: fit its length
			m.Parent = showFolder
			table.insert(spinners, { model = m, cf = WC(x, 1.3, SHOW_Z), speed = if won then 0.25 else 0.1 })
		end
		plaque(
			base,
			t.name,
			if won then Chronicle.provenance((entry.trophyLog or {})[t.op], os.time()) else t.hunt .. " · трофей",
			if won then C.gold else C.dim
		)
	end
	-- the siege record on the drill-side
	if (entry.siege or 0) > 0 then
		local base = pedestal(Layout.SiegeX, C.orange, true)
		plaque(
			base,
			"ОБОРОНА " .. entry.siege,
			"Лучший удержанный уровень бура",
			C.orange
		)
	end
end

-- HUD -----------------------------------------------------------------------------------------------------
local function stationButton(parent, key: string, text: string, iconName: string, color: Color3, order: number)
	local b, bl =
		Theme.button(text, { Name = key, Size = UDim2.fromOffset(176, 56), TextSize = 14, LayoutOrder = order })
	b.Parent = parent
	bl.Position = UDim2.fromOffset(20, 0)
	local ic = Icons.new(iconName, 24, color)
	ic.AnchorPoint = Vector2.new(0, 0.5)
	ic.Position = UDim2.new(0, 16, 0.5, 0)
	ic.ZIndex = 3
	ic.Parent = b
	b.Activated:Connect(function()
		Audio.play("ui")
		if actions and actions[key] then
			actions[key]()
		end
	end)
	return b
end

local function buildHud(playerGui: PlayerGui)
	gui = new("ScreenGui", {
		Name = "SporeBase",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 8,
		Enabled = false,
		Parent = playerGui,
	})
	local safe = new("Frame", { Name = "Safe", Size = UDim2.fromScale(1, 1), Parent = gui })
	ui.scale = new("UIScale", { Parent = safe })
	ui.safe = safe
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 24),
		PaddingRight = UDim.new(0, 24),
		PaddingTop = UDim.new(0, 16),
		PaddingBottom = UDim.new(0, 20),
		Parent = safe,
	})
	-- top-left: whose outpost
	ui.tag = label("АВАНПОСТ", {
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.fromOffset(420, 16),
		FontFace = F.head,
		TextSize = 12,
		TextColor3 = C.lime,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = safe,
	})
	ui.owner = label("", {
		Position = UDim2.fromOffset(2, 16),
		Size = UDim2.fromOffset(520, 40),
		FontFace = F.display,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = safe,
	})
	new("UIStroke", { Color = C.ink, Thickness = 3, Transparency = 0.2, Parent = ui.owner })
	-- tap your name: your own card (titles to wear, what others see)
	local ownerBtn = new("TextButton", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(420, 58),
		BackgroundTransparency = 1,
		Text = "",
		Parent = safe,
	})
	ownerBtn.Activated:Connect(function()
		Audio.play("ui")
		if actions and actions.card then
			actions.card()
		end
	end)
	ui.ownerNote = label("", {
		Position = UDim2.fromOffset(4, 246),
		Size = UDim2.fromOffset(440, 30),
		FontFace = F.body,
		TextSize = 12,
		TextColor3 = C.dim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = safe,
	})
	-- goal card
	local card = Theme.panel(
		{ Name = "Goal", Position = UDim2.fromOffset(0, 68), Size = UDim2.fromOffset(440, 168), CornerRadius = 18 },
		C.lime
	)
	card.Parent = safe
	ui.goal = card
	ui.goalTag = label("СЛЕДУЮЩАЯ ЦЕЛЬ", {
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.fromOffset(260, 14),
		FontFace = F.head,
		TextSize = 11,
		TextColor3 = C.lime,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	ui.goalIcon = new("Frame", { Position = UDim2.fromOffset(16, 34), Size = UDim2.fromOffset(46, 46), Parent = card })
	ui.goalTitle = label("", {
		Position = UDim2.fromOffset(72, 32),
		Size = UDim2.new(1, -184, 0, 24),
		FontFace = F.display,
		TextSize = 19,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	new("UITextSizeConstraint", { MaxTextSize = 19, Parent = ui.goalTitle })
	ui.goalText = label("", {
		Position = UDim2.fromOffset(72, 58),
		Size = UDim2.new(1, -184, 0, 66),
		FontFace = F.body,
		TextSize = 13,
		TextColor3 = C.dim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	-- the structure this goal is about, turning slowly
	ui.goalView = new("ViewportFrame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(100, 100),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 140, 180),
		LightColor = Color3.fromRGB(255, 240, 230),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		Parent = card,
	})
	ui.goalCam = new("Camera", { FieldOfView = 32, Parent = ui.goalView })
	ui.goalView.CurrentCamera = ui.goalCam
	ui.goalBtn, ui.goalBtnLabel = Theme.button("", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 72, 1, -12),
		Size = UDim2.fromOffset(170, 34),
		TextSize = 13,
	}, "primary")
	ui.goalBtn.Parent = card
	ui.goalBtn.Activated:Connect(function()
		Audio.play("ui")
		if actions and actions.goal then
			actions.goal()
		end
	end)
	-- top-right: xenite, settings, invite, squad
	local tr = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(420, 360),
		Parent = safe,
	})
	ui.gear = new("TextButton", {
		Name = "Settings",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.2,
		Text = "",
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.white, Transparency = 0.8 },
		Parent = tr,
	})
	local g = Icons.new("gear", 24, C.text)
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromScale(0.5, 0.5)
	g.Parent = ui.gear
	ui.gear.Activated:Connect(function()
		if actions and actions.settings then
			actions.settings()
		end
	end)
	ui.xenite = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -56, 0, 2),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.2,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.pink, Transparency = 0.5, Thickness = 1.5 },
		Parent = tr,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		},
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 16), Parent = ui.xenite })
	new("Frame", {
		Size = UDim2.fromOffset(15, 15),
		Rotation = 45,
		BackgroundColor3 = C.pink,
		Corner = 3,
		LayoutOrder = 1,
		Parent = ui.xenite,
	})
	ui.xeniteAmount = label("0", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		FontFace = F.numHeavy,
		TextSize = 18,
		LayoutOrder = 2,
		Parent = ui.xenite,
	})
	ui.invite = Theme.button("ПОЗВАТЬ ДРУГА", {
		Name = "Invite",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 54),
		Size = UDim2.fromOffset(212, 40),
		TextSize = 12,
	})
	ui.invite.Parent = tr
	ui.invite.Activated:Connect(function()
		Audio.play("ui")
		Base.invite()
	end)
	ui.inviteSub = label("Отбейте бур вместе", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 96),
		Size = UDim2.fromOffset(260, 14),
		FontFace = F.body,
		TextSize = 11,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = tr,
	})
	ui.harvest = Theme.button("СОБРАТЬ", {
		Name = "Harvest",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 118),
		Size = UDim2.fromOffset(212, 40),
		TextSize = 12,
	}, "primary")
	ui.harvest.Parent = tr
	ui.harvest.Visible = false
	ui.harvest.Activated:Connect(function()
		send("harvest")
		Audio.play("orb", 1, 0.9)
		Audio.play("level", 0.6, 1.4)
	end)
	ui.squad = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 170),
		Size = UDim2.fromOffset(260, 190),
		Parent = tr,
		List = { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right },
	})
	-- bottom-left: stations
	ui.stations = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(760, 56),
		Parent = safe,
		List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) },
	})
	ui.stArmory = stationButton(ui.stations, "armory", "ОРУЖЕЙНАЯ", "swords", C.gold, 1)
	ui.stBuild = stationButton(ui.stations, "build", "МАСТЕРСКАЯ", "gear", C.cyan, 2)
	ui.stLaunch = stationButton(ui.stations, "launch", "ВЫЛАЗКА", "play", C.lime, 3)
	ui.stBoard = stationButton(ui.stations, "board", "ОТРЯДЫ", "users", C.orange, 4)
	ui.stOutposts = stationButton(ui.stations, "outposts", "ЖИТЕЛИ", "eye", C.pink, 5)
	ui.stSwarm = stationButton(ui.stations, "swarm", "ЛАБОРАТОРИЯ", "hive", C.violet, 6)
	for _, b in { ui.stArmory, ui.stBuild, ui.stLaunch, ui.stBoard, ui.stOutposts, ui.stSwarm } do
		b.Size = UDim2.fromOffset(156, 56)
	end
	-- session base: back to the public camp
	ui.toCamp, ui.toCampLabel = Theme.button("В ЛАГЕРЬ", {
		Name = "ToCamp",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -224, 0, 54),
		Size = UDim2.fromOffset(150, 40),
		TextSize = 12,
	})
	ui.toCamp.Parent = tr
	ui.toCamp.Visible = false
	ui.toCamp.Activated:Connect(function()
		Audio.play("ui")
		if actions and actions.camp then
			actions.camp()
		end
	end)
	-- bottom-right: go
	ui.play, ui.playLabel = Theme.button("В БОЙ", {
		Name = "Play",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, -24),
		Size = UDim2.fromOffset(300, 84),
		TextSize = 32,
	}, "primary")
	ui.play.Parent = safe
	ui.playLabel.Position = UDim2.fromOffset(22, -8)
	ui.playIcon = Icons.new("play", 30, C.ink)
	ui.playIcon.AnchorPoint = Vector2.new(0, 0.5)
	ui.playIcon.Position = UDim2.new(0, 30, 0.5, 0)
	ui.playIcon.ZIndex = 3
	ui.playIcon.Parent = ui.play
	ui.playSub = label("", {
		Position = UDim2.new(0, 22, 1, -30),
		Size = UDim2.new(1, -22, 0, 18),
		FontFace = F.head,
		TextSize = 12,
		TextColor3 = C.ink,
		TextTransparency = 0.25,
		ZIndex = 3,
		Parent = ui.play,
	})
	ui.playGlow = new("UIStroke", {
		Color = C.lime,
		Thickness = 5,
		Transparency = 0.6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = ui.play,
	})
	ui.play.Activated:Connect(function()
		if actions and actions.play then
			actions.play()
		end
	end)
	ui.status = label("", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, 0),
		Size = UDim2.fromOffset(420, 20),
		FontFace = F.bodyBold,
		TextSize = 15,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = safe,
	})
	ui.hold, ui.holdLabel = Theme.button("ЖДАТЬ ДРУЗЕЙ", {
		Name = "Hold",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -310, 1, -24),
		Size = UDim2.fromOffset(170, 44),
		TextSize = 12,
	})
	ui.hold.Parent = safe
	-- how to turn the free camera (DD-066): until the player has turned or zoomed it once
	local UIS = game:GetService("UserInputService")
	ui.camHint = label(
		if UIS.TouchEnabled and not UIS.MouseEnabled
			then "Проведи пальцем — повернуть камеру  ·  щипок — ближе/дальше  ·  кнопка — прыжок"
			else "Зажми ПКМ — повернуть камеру  ·  колесо — ближе/дальше  ·  ПРОБЕЛ — прыжок",
		{
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.fromOffset(560, 20),
			FontFace = F.bodyBold,
			TextSize = 14,
			TextColor3 = C.text,
			TextTransparency = 0.15,
			Parent = safe,
		}
	)
	-- small text straight over the bright grass needs an outline to be read
	for _, l in { ui.status, ui.inviteSub, ui.ownerNote, ui.tag, ui.camHint } do
		new("UIStroke", { Color = C.ink, Thickness = 1.6, Transparency = 0.25, Parent = l })
	end
	ui.hold.Visible = false
	ui.hold.Activated:Connect(function()
		Audio.play("ui")
		send("hold", not (lobby and lobby.hold))
	end)
	-- centre: the swarm is coming (first turret built)
	ui.strike = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(640, 110),
		Visible = false,
		Parent = gui,
	})
	ui.strikeTitle = label(
		"РОЙ УСЛЫШАЛ БУР",
		{ Size = UDim2.new(1, 0, 0, 64), FontFace = F.display, TextSize = 54, TextColor3 = C.red, Parent = ui.strike }
	)
	new("UIStroke", { Color = C.ink, Thickness = 4, Transparency = 0.15, Parent = ui.strikeTitle })
	ui.strikeSub = label("", {
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 26),
		FontFace = F.head,
		TextSize = 20,
		Parent = ui.strike,
	})
	new("UIStroke", { Color = C.ink, Thickness = 3, Transparency = 0.2, Parent = ui.strikeSub })
end

local function squadRow(p, isHost: boolean)
	local row = new("Frame", {
		Size = UDim2.fromOffset(240, 36),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.25,
		Corner = UDim.new(1, 0),
		Stroke = { Color = if p.ready then C.lime else C.white, Transparency = if p.ready then 0.3 else 0.85 },
		Parent = ui.squad,
	})
	label(p.name .. (if isHost then "  ★" else ""), {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -56, 1, 0),
		FontFace = F.bodyBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	if p.ready then
		local ic = Icons.new("check", 18, C.lime)
		ic.AnchorPoint = Vector2.new(1, 0.5)
		ic.Position = UDim2.new(1, -12, 0.5, 0)
		ic.Parent = row
	end
end

local viewModelKey = nil
local function setGoalView(structureId: string?)
	if viewModelKey == structureId then
		return
	end
	viewModelKey = structureId
	for _, c in ui.goalView:GetChildren() do
		if c:IsA("Model") then
			c:Destroy()
		end
	end
	ui.goalView.Visible = structureId ~= nil
	if structureId then
		local m = Structures.model(structureId, 1, false)
		m:PivotTo(CFrame.new())
		m.Parent = ui.goalView
		local _, size = m:GetBoundingBox()
		local r = math.max(size.X, size.Y, size.Z)
		ui.goalModel = m
		ui.goalRadius = r
	else
		ui.goalModel = nil
	end
end

-- Refresh ---------------------------------------------------------------------------------------------------
local function features()
	return (profile and profile.features) or {}
end

function Base.goal()
	return goal
end

function Base.refresh()
	if not profile then
		return
	end
	local f = features()
	goal = if visitHome then nil else Goals.next(profile)
	local home = visitHome or profile.home or {}
	local switched = lastVisit ~= visitHome
	lastVisit = visitHome
	local won = profile.winsByOp or {}
	stationParts.armory.holder.Parent = if (profile.runs or 0) > 0 then folder else nil
	-- the generator brings the light: floodlights, string lights, the bunker's windows
	local powered = home.GENERATOR == true
	if powered ~= lampsOn and not scene then
		setLamps(powered, true)
		setBulbs(powered)
	end
	-- the prepared spots: rubble or restored, a prompt to restore when it is open
	for id, sp in spotParts do
		local def = sp.def
		local restored = home[id] == true
		-- a story scene (DD-075) restores spots on its own cues; the profile catches up after it
		if restoredShown[id] ~= restored and not (scene and scene.story) then
			local animate = restoredShown[id] == false and restored and not scene and not switched
			restoredShown[id] = restored
			showSpot(id, restored, animate)
		end
		local open = ((won[def.unlock] or 0) > 0)
		local affordable = (profile.scrap or 0) >= def.cost
		local title = sp.board:FindFirstChild("Title", true)
		local sub = sp.board:FindFirstChild("Sub", true)
		local sd = sp.sd
		if title then
			title.Text = if restored and sd.stationName then sd.stationName else def.name
		end
		if sub then
			sub.Text = if restored and id == "LAB"
				then labText()
				elseif restored then (sd.stationSub or "Восстановлено")
				elseif def.free then "Заработает после вылазки 1"
				elseif not open then "Откроется после вылазки " .. tostring(
					tonumber(def.unlock:sub(2)) or ""
				)
				else string.format(
					"Починить · ◆ %d%s",
					def.cost,
					if affordable then "" else " (не хватает)"
				)
		end
		sp.canRestore = visitHome == nil and not restored and open and not def.free
		sp.isStation = visitHome == nil and restored and sd.station ~= nil
	end
	local slotsShown = if visitHome then visitSlots else (profile.outpost and profile.outpost.slots)
	setShelf(slotsShown, home.WORKBENCH == true)
	setPile(if visitHome then visitStock or 0 else profile.scrap or 0)
	-- a harvester at the drill keeps the line busy: a crate now and then, even between sorties
	if cable then
		local harvester = false
		for _, sl in (profile.outpost and profile.outpost.slots) or {} do
			if sl.id == "HARVEST" then
				harvester = true
			end
		end
		cable.every = if harvester and not visitHome then 8 else nil
	end
	-- the goal: a beam over the place where it happens (a story scene places its own)
	if scene and scene.story then
		local _ = goalMarker
	elseif goal and goal.station == "home" and goal.spot and spotParts[goal.spot] then
		local sd = SPOTS[goal.spot]
		local def = Meta.Home[goal.spot]
		showGoalMarker(W(sd.x, 0, sd.z), sd.color, def.name, "Починить · ◆ " .. def.cost, def.icon)
	elseif goal and goal.station == "swarm" and goal.spot and SPOTS[goal.spot] then
		local sd = SPOTS[goal.spot]
		showGoalMarker(W(sd.x, 0, sd.z), sd.color, "СВОЙ РОЙ", "Выведи первую стаю", "hive")
	elseif goal and goal.station == "launch" then
		-- DD-082: the sortie gate is a place to walk to as well, not only a button
		local op = goal.op and Ops.get(goal.op)
		showGoalMarker(
			W(0, 0, -30),
			if goal.mode == "siege" then C.orange else C.lime,
			if goal.mode == "siege"
				then "ОБОРОНА БУРА"
				elseif op then "ВЫЛАЗКА " .. op.index
				else "ВЫЛАЗКА",
			if op then op.name else "",
			"play"
		)
	elseif goal and goal.station == "armory" then
		showGoalMarker(Base.point("ARMORY"), C.gold, "ОРУЖЕЙНАЯ", "", "swords")
	elseif goal and goal.station == "build" and f.outpost then
		local sd = SPOTS.WORKBENCH
		local def = goal.structure and Meta.Structures[goal.structure]
		showGoalMarker(
			W(sd.x, 0, sd.z),
			C.cyan,
			if def then "СОБРАТЬ: " .. def.name else "МАСТЕРСКАЯ",
			if def then "Для бура · ◆ " .. def.cost[1] else "",
			if def then def.icon else "gear"
		)
	else
		clearGoalMarker()
	end
	local isHost = lobby ~= nil and lobby.host == myId
	local ownsBase = visitHome == nil
	local slots = (profile.outpost and profile.outpost.slots) or {}
	local _ = slots
	if not gui then
		return
	end
	-- HUD
	local players = lobby and lobby.players or {}
	local hostName = ""
	for _, p in players do
		if lobby and p.id == lobby.host then
			hostName = p.name
		end
	end
	if camp then
		-- DD-087: the grove — your plot among the neighbours'
		local plot, open = nil, false
		for _, h in camp.hunters or {} do
			if h.id == myId then
				plot, open = h.plot, h.statusKey == "open"
			end
		end
		local cap = camp.grove and camp.grove.capacity
		ui.tag.Text = string.format(
			"ПОСЛЕДНЯЯ РОЩА  ·  ЖИТЕЛЕЙ: %d%s%s",
			#(camp.hunters or {}),
			if cap and cap > 0 then "/" .. cap else "",
			if plot then "  ·  УЧАСТОК " .. plot else ""
		)
		ui.owner.Text = if #players > 1
			then "ОТРЯД " .. hostName:upper() .. string.format("  %d/4", #players)
			else "ТВОЙ ДОМ"
		ui.ownerNote.Text = if open
			then "Фонарь у таблички горит: соседи видят, что ты ищешь напарника."
			else "Соседи видят твой дом. Зажги фонарь у таблички — позовёшь их с собой. G — сигнал."
	else
		ui.tag.Text = if isHost or hostName == ""
			then "ТВОЁ УБЕЖИЩЕ"
			else "УБЕЖИЩЕ КОМАНДИРА"
		ui.owner.Text = if visitHome then hostName else Players.LocalPlayer.DisplayName
		ui.ownerNote.Text = if visitHome
			then "Общий привал отряда. Оружие и добыча у каждого свои."
			else ""
	end
	ui.toCamp.Visible = lobby ~= nil and lobby.camp == true
	ui.stBoard.Visible = camp ~= nil
	ui.stOutposts.Visible = camp ~= nil
	if goal then
		ui.goal.Visible = true
		ui.goalTitle.Text = goal.title
		ui.goalText.Text = goal.text
		for _, c in ui.goalIcon:GetChildren() do
			c:Destroy()
		end
		local col = if goal.structure
			then Meta.Structures[goal.structure].color
			elseif goal.spot and SPOTS[goal.spot] then SPOTS[goal.spot].color
			else C.lime
		local d = Icons.disc(goal.icon, 46, col, 2)
		d.Parent = ui.goalIcon
		setGoalView(goal.structure)
		local btn = nil
		if goal.station == "build" then
			local def = goal.structure and Meta.Structures[goal.structure]
			local affordable = def and (profile.scrap or 0) >= def.cost[if goal.key == "upgrade" then 2 else 1]
			btn = if goal.key == "upgrade"
				then "УЛУЧШИТЬ"
				elseif affordable then "СОБРАТЬ"
				else "МАСТЕРСКАЯ"
		elseif goal.station == "launch" then
			btn = if goal.mode == "siege" then "К ОБОРОНЕ БУРА" else "НА ВЫЛАЗКУ"
		elseif goal.station == "home" then
			local h = goal.spot and Meta.Home[goal.spot]
			btn = if h and (profile.scrap or 0) >= h.cost then "ПОЧИНИТЬ" else nil
		elseif goal.station == "swarm" then
			btn = "В ЛАБОРАТОРИЮ"
		end
		ui.goalBtn.Visible = btn ~= nil and (goal.station ~= "build" or ownsBase)
		ui.goalBtnLabel.Text = btn or ""
	else
		ui.goal.Visible = false
	end
	ui.xeniteAmount.Text = Theme.commas(profile.scrap or 0)
	ui.xenite.Visible = (profile.runs or 0) > 0 or (profile.scrap or 0) > 0
	local harvest = profile.outpost and profile.outpost.harvest or 0
	ui.harvest.Visible = harvest > 0
	ui.harvest.Label.Text = "СОБРАТЬ  +" .. harvest
	ui.stArmory.Visible = (profile.runs or 0) > 0
	-- choosing a sortie only makes sense once there is more than one; before that «В БОЙ» is the way out
	ui.stLaunch.Visible = (profile.winsByOp and (profile.winsByOp.O01 or 0) > 0) == true
	ui.stBuild.Visible = f.outpost == true
	ui.stSwarm.Visible = f.swarm == true
	-- squad and the go button
	for _, c in ui.squad:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local n = #players
	local ready, amReady = 0, false
	for _, p in players do
		if p.ready then
			ready += 1
		end
		if p.id == myId then
			amReady = p.ready
		end
		if n > 1 then
			squadRow(p, lobby ~= nil and p.id == lobby.host)
		end
	end
	ui.amReady = amReady
	local op = lobby and Ops.get(lobby.op)
	local modeName = if lobby and lobby.mode == "siege"
		then "ОБОРОНА БУРА · " .. (if profile.tut and profile.tut.strike
			then "УРОВЕНЬ " .. (lobby.siege or 1)
			else "ПЕРВЫЙ НАТИСК")
		elseif lobby and lobby.mode == "raid" then "ВТОРЖЕНИЕ"
		elseif op then "ВЫЛАЗКА " .. op.index .. " · " .. op.name
		else ""
	ui.playLabel.Text = if amReady then "ОТМЕНА" else "В БОЙ"
	ui.playSub.Text = if amReady then "ждём отряд" else modeName
	-- DD-075: until the first defence is done the big button is the next step itself, not another sortie
	if not amReady and goal and not visitHome then
		if goal.key == "sting" and goal.station == "build" then
			ui.playLabel.Text = "СОБРАТЬ"
			ui.playSub.Text = "ТУРЕЛЬ ДЛЯ БУРА · ◆ " .. Meta.Structures.STING.cost[1]
		elseif goal.key == "strike" then
			ui.playSub.Text = "ЗАЩИТИ БУР · ПЕРВЫЙ НАТИСК"
		end
	end
	ui.play.BackgroundColor3 = if amReady then C.ink else C.lime
	ui.playLabel.TextColor3 = if amReady then C.text else C.ink
	ui.playSub.TextColor3 = if amReady then C.dim else C.ink
	Icons.recolor(ui.playIcon, if amReady then C.text else C.ink)
	local cd = lobby and lobby.countdown
	ui.status.Text = if cd and lobby.hold
		then string.format("Ждём друзей  ·  готовы %d/%d", ready, n)
		elseif cd then string.format("Выход через %d  ·  готовы %d/%d", math.ceil(cd), ready, n)
		elseif n > 1 then string.format("Отряд %d  ·  готовы %d/%d", n, ready, n)
		else "Соло  ·  до 4 игроков"
	ui.status.TextColor3 = if cd and not amReady then C.gold else C.dim
	ui.hold.Visible = cd ~= nil and n > 1 and isHost
	ui.holdLabel.Text = if lobby and lobby.hold then "ВЫЛЕТАЕМ" else "ЖДАТЬ ДРУЗЕЙ"
	-- strike
	ui.strike.Visible = lobby ~= nil and lobby.strike ~= nil
	if lobby and lobby.strike then
		ui.strikeSub.Text = string.format("К ТУРЕЛИ!  ·  %d", math.ceil(lobby.strike))
	end
end

-- Quality (DD-057): the shelter is calm, but it is not free on a phone. Low: no decorative lights and
-- no tree shadows; Medium: the pads' glow lights off; High: everything.
local function applyQuality()
	local q = Settings.quality
	for _, d in folder:GetDescendants() do
		if d:IsA("Light") then
			local isLamp = d:IsA("SpotLight")
			local isPad = d.Parent and d.Parent.Name == "Pad"
			d.Enabled = if q <= 1 then false elseif q == 2 then not isPad else true
			if isLamp and q <= 1 then
				d.Enabled = false
			end
		elseif d:IsA("MeshPart") and d.Parent and d.Parent.Name == "Grove" then
			d.CastShadow = q >= 2
		end
	end
end
Settings.onChanged(function(key)
	if key == "quality" then
		applyQuality()
	end
end)

-- API --------------------------------------------------------------------------------------------------------
local bindOrbitInput -- the free camera's input (defined with the camera below)

local artReady = false
function Base.init(playerGui: PlayerGui, sender, acts)
	send = sender
	actions = acts
	buildWorld()
	buildSpots()
	buildTerminal()
	buildHud(playerGui)
	bindOrbitInput()
	task.spawn(function()
		local rs = game:GetService("ReplicatedStorage")
		local f = rs:WaitForChild("ArtTemplates", 30)
		local t0 = os.clock()
		while f and not f:GetAttribute("Ready") and os.clock() - t0 < 30 do
			task.wait(0.5)
		end
		artReady = true
		dressStations()
		applyQuality()
	end)
end

-- DD-087: the shelter stands on the player's plot in the grove. A new plot (another server, a plot
-- given out again) moves the whole home: it is rebuilt in the new frame, the look kept.
function Base.setFrame(cf: CFrame)
	if cf == frame then
		return
	end
	frame = cf
	if not folder then
		return
	end
	local parent = folder.Parent
	folder:Destroy()
	table.clear(stationParts)
	table.clear(lamps)
	table.clear(spotParts)
	table.clear(restoredShown)
	table.clear(bulbs)
	table.clear(spinners)
	decorDone = false
	goalMarker, cable, gallery, arrow = nil, nil, nil, nil
	pileShown, pileFolder = -1, nil
	shelfKey, shelfFolder = nil, nil
	showFolder, showKey = nil, nil
	decorFolder, decorKey = nil, nil
	lampsOn = false
	buildWorld()
	buildSpots()
	buildTerminal()
	folder.Parent = parent
	if artReady then
		dressStations()
		applyQuality()
	end
	Base.setShowcase(showEntry)
	Base.refresh()
end

-- The frame of the shelter on screen (story scenes and the range place themselves by it).
function Base.frame(): CFrame
	return frame
end

function Base.setProfile(pub)
	local scrap = pub and pub.scrap or 0
	if lastScrap and scrap > lastScrap then
		-- it rides the cable in when the shelter is on screen (after the results, not behind them)
		pendingDelivery += scrap - lastScrap
	end
	lastScrap = scrap
	profile = pub
	Base.refresh()
	if active and pendingDelivery > 0 and not visitHome then
		deliver(pendingDelivery) -- collected while standing at home (the drill's harvester)
		pendingDelivery = 0
	end
end

function Base.setLobby(info, id: number)
	lobby = info
	myId = id
	Base.refresh()
end

-- Visiting another survivor's shelter in the camp: their restored spots replace ours on this screen.
function Base.setVisitHome(home, slots, stock)
	visitHome = home
	visitSlots = slots
	visitStock = stock
	Base.refresh()
end

function Base.setCamp(info)
	camp = info
end

function Base.collection()
	return labResearch, labOwner, nil, labOwn
end

function Base.leaveLobby()
	lobby = nil
end

-- Active = the player is on the base (lobby mode, no full-screen menu): HUD on, prompts on.
function Base.setActive(on: boolean)
	if active == on then
		return
	end
	active = on
	if gui then
		gui.Enabled = on
	end
	if on then
		Base.refresh()
		if pendingDelivery > 0 and not visitHome then
			deliver(pendingDelivery)
			pendingDelivery = 0
		end
	end
end

-- The base's own buildings (stations, lamps, showcase, markers) are not part of the battlefield: they
-- leave the world for the run and come back on the base (and for the victory scene).
function Base.setWorldVisible(on: boolean)
	local want = if on then workspace else nil
	if folder.Parent ~= want then
		folder.Parent = want
	end
end

function Base.isActive(): boolean
	return active
end

function Base.ready(): boolean
	return ui.amReady == true
end

function Base.invite()
	task.spawn(function()
		local lp = Players.LocalPlayer
		local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, lp)
		if ok and can then
			local options = Instance.new("ExperienceInviteOptions")
			options.PromptMessage = "Отобьём мой бур вместе!"
			pcall(SocialService.PromptGameInvite, SocialService, lp, options)
		end
	end)
end

-- Something was made on the workbench for the drill: sparks and a hammer ring over the bench.
function Base.crafted(color: Color3)
	local sd = SPOTS.WORKBENCH
	local pos = W(sd.x, 3, sd.z)
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2
		Fx.emitWith("streak", pos, 2, 0.7, color, Vector3.new(math.cos(a), 1.5, math.sin(a)).Unit)
	end
	Fx.ring(W(sd.x, 0.4, sd.z), 6, color, 0.7)
	Fx.light(pos, color, 18, 0.8)
	Audio.play("evolve", 0.5, 1.5)
end

-- A structure that just appeared on the base: it rises out of the ground in a shower of sparks.
function Base.buildAnim(model: Model, cf: CFrame, color: Color3)
	local t0 = os.clock()
	local dur = 1.3
	local pos = cf.Position
	Fx.ring(pos + Vector3.yAxis * 0.3, 5, color, 0.9)
	Fx.light(pos + Vector3.yAxis * 3, color, 22, 1.2)
	Audio.play("evolve", 0.5, 1.4)
	model:PivotTo(cf * CFrame.new(0, -4, 0))
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / dur, 0, 1)
		if not model.Parent then
			conn:Disconnect()
			return
		end
		local e = 1 - (1 - k) ^ 3
		model:PivotTo(cf * CFrame.new(0, -4 * (1 - e), 0) * CFrame.Angles(0, (1 - e) * 1.2, 0))
		if math.random() < 0.6 then
			Fx.emitWith(
				"streak",
				pos + Vector3.new(math.random() * 3 - 1.5, 0.4, math.random() * 3 - 1.5),
				2,
				0.6,
				color,
				Vector3.yAxis
			)
		end
		if k >= 1 then
			conn:Disconnect()
			Fx.ring(pos + Vector3.yAxis * 0.3, 8, color, 0.6)
			Fx.emitWith("flash", pos + Vector3.yAxis * 2, 1, 1.4, color)
			Audio.play("level", 0.6, 1.3)
		end
	end)
end

-- Per frame: prompts only while walking the base; markers breathe.
function Base.update(dt: number, _root: Vector3?)
	local now = os.clock()
	if cable and folder.Parent then
		cable:update(dt)
	end
	local calm = active and scene == nil
	local goalSpot = if goal and (goal.station == "home" or goal.station == "swarm")
		then goal.spot
		elseif goal and goal.station == "build" then "WORKBENCH"
		else nil
	for _, s in stationParts do
		s.prompt.Enabled = active
		local hot = goal and goal.station == s.def.key and active
		s.board.Enabled = calm and (hot or nearEnough(s.board, s.pad.Position, _root))
		local pulse = if hot then math.sin(now * 4) else 0
		setRing(s.ring, (if active then 0.15 else 0.7) + math.sin(now * 2 + s.def.x) * 0.1, 4.8 + pulse * 0.4)
		s.beam.Transparency = if active then 0.62 + math.sin(now * 1.6 + s.def.z) * 0.08 else 0.85
		s.light.Brightness = if hot then 2 + pulse else 1
	end
	for id, sp in spotParts do
		local usable = active and (sp.canRestore or sp.isStation)
		sp.prompt.Enabled = usable == true
		sp.prompt.ActionText = if sp.isStation
			then (sp.sd.stationName or sp.def.name)
			else "Починить · ◆ " .. sp.def.cost
		sp.board.Enabled = calm and (id == goalSpot or nearEnough(sp.board, sp.ring.Position, _root))
		local glow = if sp.canRestore
			then 0.25 + math.sin(now * 3 + sp.sd.x) * 0.15
			elseif sp.isStation then 0.45
			else 0.85
		setRing(sp.ring, glow)
	end
	for i = #nearBoards, 1, -1 do
		local nb = nearBoards[i]
		if not nb.gui.Parent then
			table.remove(nearBoards, i)
		else
			nb.gui.Enabled = calm and nearEnough(nb.gui, nb.at, _root)
		end
	end
	if gallery then
		gallery:step(dt, active, _root)
	end
	for _, sp in spinners do
		if sp.model.Parent then
			sp.model:PivotTo(sp.cf * CFrame.Angles(0, now * sp.speed, 0))
		end
	end
	-- the way to the goal: a new goal gets a camera fly-over, then a chevron at the hero's feet points
	local target = goalTarget()
	activeFor = if active and not scene then activeFor + dt else 0
	if activeFor > 1.2 and _root and goal and target and (profile and (profile.runs or 0) > 0) then
		if goal.key ~= revealedKey and not visitHome then
			revealedKey = goal.key
			startReveal(target, _root)
		end
	end
	local flat = if _root and target then Vector3.new(target.X - _root.X, 0, target.Z - _root.Z) else nil
	if active and flat and flat.Magnitude > 10 and not scene and not visitHome then
		local m = arrowModel()
		local dir = flat.Unit
		local base = CFrame.lookAt(
			Vector3.new(_root.X, 0, _root.Z) + dir * (3.2 + math.sin(now * 4) * 0.4),
			Vector3.new(_root.X, 0, _root.Z) + dir * 10
		)
		for _, a in m:GetChildren() do
			local off = a:GetAttribute("Off") :: Vector3
			a.CFrame = base * CFrame.new(off.X, 0.3, -off.Z) * CFrame.Angles(0, a:GetAttribute("Yaw") :: number, 0)
		end
	elseif arrow then
		for _, a in arrow:GetChildren() do
			a.CFrame = CFrame.new(0, -500, 0)
		end
	end
	if goalMarker then
		local pulse = 0.5 + math.sin(now * 3.2) * 0.5
		setRing(goalMarker.ring, pulse * 0.4, 3.6 + pulse * 0.8)
	end
	if gui and gui.Enabled then
		ui.playGlow.Transparency = 0.45 + math.sin(now * 3) * 0.25
		ui.playGlow.Thickness = 3 + math.sin(now * 3) * 2
		if ui.goalModel then
			local r = ui.goalRadius or 6
			local a = now * 0.6
			ui.goalCam.CFrame = CFrame.lookAt(
				Vector3.new(math.sin(a) * r * 1.6, r * 0.9, math.cos(a) * r * 1.6),
				Vector3.new(0, r * 0.32, 0)
			)
		end
		ui.scale.Scale = math.clamp(
			math.min(workspace.CurrentCamera.ViewportSize.X / 1280, workspace.CurrentCamera.ViewportSize.Y / 720),
			0.62,
			1.2
		)
		ui.safe.Size = UDim2.fromScale(1 / ui.scale.Scale, 1 / ui.scale.Scale)
		-- DD-085: on a phone Roblox's own thumbstick (bottom left) and jump button (bottom right) own
		-- the corners: the station buttons go up under the goal card, the big button steps left of jump
		local phone = Theme.phone()
		if phone ~= ui.phoneLayout then
			ui.phoneLayout = phone
			ui.stations.AnchorPoint = if phone then Vector2.new(0, 0) else Vector2.new(0, 1)
			ui.stations.Position = if phone then UDim2.fromOffset(0, 246) else UDim2.fromScale(0, 1)
			ui.play.Position = if phone then UDim2.new(1, -190, 1, -18) else UDim2.new(1, 0, 1, -24)
			ui.goalText.TextSize = if phone then 17 else 13
			ui.goal.Size = UDim2.fromOffset(440, if phone then 178 else 168)
		end
		if ui.strike.Visible then
			ui.strikeTitle.TextTransparency = math.abs(math.sin(now * 5)) * 0.35
		end
	end
end

-- Base camera: a high three-quarter view that follows the hero, the drill ahead (north is up).
local camPos = nil
-- Free camera on the shelter (DD-066): it orbits the hero. Right mouse drag / Z and X (or , and .) / a finger dragged
-- on the right part of the screen / the right stick turn it; the wheel / a pinch bring it closer or
-- further.
-- It starts at the old fixed framing (high three-quarters from the gate side). Walking stays relative
-- to where the camera looks (the default controls read the current camera).
local ORBIT_PITCH = math.atan2(46, 36)
local ORBIT_DIST = math.sqrt(46 * 46 + 36 * 36)
local orbit =
	{ yaw = 0, pitch = ORBIT_PITCH, dist = ORBIT_DIST, wantYaw = 0, wantPitch = ORBIT_PITCH, wantDist = ORBIT_DIST }
local orbitDrag = nil -- the mouse button or touch turning the camera
local orbitStick = Vector2.zero
local pinchFrom = nil

local function orbitTurn(dx: number, dy: number)
	orbit.wantYaw -= dx
	orbit.wantPitch = math.clamp(orbit.wantPitch + dy, math.rad(22), math.rad(80))
end

function bindOrbitInput()
	local UIS = game:GetService("UserInputService")
	UIS.InputBegan:Connect(function(input, processed)
		if processed or not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbitDrag = input
		elseif input.UserInputType == Enum.UserInputType.Touch and not orbitDrag then
			-- the left part of the screen is the movement thumbstick
			local cam = workspace.CurrentCamera
			if cam and input.Position.X > cam.ViewportSize.X * 0.4 then
				orbitDrag = input
			end
		end
	end)
	UIS.InputChanged:Connect(function(input, processed)
		if not active then
			return
		end
		local t = input.UserInputType
		if
			t == Enum.UserInputType.MouseMovement
			and orbitDrag
			and orbitDrag.UserInputType == Enum.UserInputType.MouseButton2
		then
			orbitTurn(input.Delta.X * 0.006, input.Delta.Y * 0.005)
		elseif t == Enum.UserInputType.Touch and input == orbitDrag and not pinchFrom then
			orbitTurn(input.Delta.X * 0.008, input.Delta.Y * 0.006)
		elseif t == Enum.UserInputType.MouseWheel and not processed then
			orbit.wantDist = math.clamp(orbit.wantDist * (1 - input.Position.Z * 0.12), 22, 110)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local v = Vector2.new(input.Position.X, input.Position.Y)
			orbitStick = if v.Magnitude > 0.2 then v else Vector2.zero
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input == orbitDrag then
			orbitDrag = nil
		end
	end)
	UIS.TouchPinch:Connect(function(_, scale: number, _, state, processed)
		if processed or not active then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchFrom = orbit.wantDist
		elseif state == Enum.UserInputState.Change and pinchFrom then
			orbit.wantDist = math.clamp(pinchFrom / math.max(scale, 0.1), 22, 110)
		else
			pinchFrom = nil
		end
	end)
end

function Base.camera(dt: number, hero: Vector3): CFrame
	local UIS = game:GetService("UserInputService")
	-- the mouse stays put while it turns the camera (set after the run's own mouse handling this frame)
	local mouseTurn = orbitDrag ~= nil and orbitDrag.UserInputType == Enum.UserInputType.MouseButton2
	UIS.MouseBehavior = if mouseTurn then Enum.MouseBehavior.LockCurrentPosition else Enum.MouseBehavior.Default
	if orbitStick.Magnitude > 0 then
		orbitTurn(orbitStick.X * dt * 2.2, -orbitStick.Y * dt * 1.4)
	end
	if active and not UIS:GetFocusedTextBox() then
		-- E is the stations' key, Q the fight's: Z / X here, and , / . as in Roblox's own camera
		local left = UIS:IsKeyDown(Enum.KeyCode.Z) or UIS:IsKeyDown(Enum.KeyCode.Comma)
		local right = UIS:IsKeyDown(Enum.KeyCode.X) or UIS:IsKeyDown(Enum.KeyCode.Period)
		if left ~= right then
			orbitTurn((if left then -1 else 1) * dt * 1.8, 0)
		end
	end
	if
		ui.camHint
		and ui.camHint.Visible
		and (math.abs(orbit.wantYaw) > 0.4 or math.abs(orbit.wantDist - ORBIT_DIST) > 6)
	then
		ui.camHint.Visible = false -- learned
	end
	local k = math.min(1, dt * 10)
	orbit.yaw += (orbit.wantYaw - orbit.yaw) * k
	orbit.pitch += (orbit.wantPitch - orbit.pitch) * k
	orbit.dist += (orbit.wantDist - orbit.dist) * math.min(1, dt * 8)
	local focus = hero + Vector3.new(0, 2, 0)
	camPos = if camPos then camPos:Lerp(focus, math.min(1, dt * 6)) else focus
	local dir = Vector3.new(
		math.sin(orbit.yaw) * math.cos(orbit.pitch),
		math.sin(orbit.pitch),
		-math.cos(orbit.yaw) * math.cos(orbit.pitch)
	)
	-- a little ahead of the hero, as the fixed view had it
	local ahead = Vector3.new(-math.sin(orbit.yaw), 0, math.cos(orbit.yaw)) * 4
	return CFrame.lookAt(camPos + dir * orbit.dist + ahead, camPos + ahead)
end

-- The base walks with the Roblox camera now (owner playtest: «свободный бег, как в обычном роблоксе»).
-- This only retires the hint once the player has had time to use it.
local hintT = 0
function Base.freeCamera(dt: number)
	hintT += dt
	if ui.camHint and ui.camHint.Visible and (hintT > 14 or Theme.phone()) then -- a phone knows how to swipe
		ui.camHint.Visible = false
	end
end

-- Back to the opening framing (a new visit to the shelter starts from the familiar view).
function Base.resetCamera()
	camPos = nil
	orbit.yaw, orbit.wantYaw = 0, 0
	orbit.pitch, orbit.wantPitch = ORBIT_PITCH, ORBIT_PITCH
	orbit.dist, orbit.wantDist = ORBIT_DIST, ORBIT_DIST
end

-- Story scenes (DD-075, client/Story) ---------------------------------------------------------------------
-- The intro and the first return borrow the shelter: while one plays the shelter keeps the look the scene
-- gives it (spots are restored on the scene's cues, not when the profile arrives) and is in the world even
-- during a run.
function Base.sceneActive(): boolean
	return scene ~= nil
end

function Base.sceneBegin()
	if scene and not scene.story then
		revealCaption("", "", false) -- a goal fly-over gives way to a story scene
	end
	scene = { story = true }
	if cable then
		cable:clearCrates() -- the scene's own pallet rides this cable
	end
end

function Base.sceneEnd()
	if not scene then
		return
	end
	scene = nil
	clearGoalMarker()
	Base.refresh()
	revealedKey = goal and goal.key -- the scene ended on the next step itself: no second fly-over
end

-- Named places of the shelter in world space.
function Base.point(name: string): Vector3
	local sd = SPOTS[name]
	if sd then
		return W(sd.x, 0, sd.z)
	elseif name == "TERMINAL" then
		return W(TERMINAL.x, 8.4, TERMINAL.z)
	elseif name == "SHELTER" then
		return W(0, 0, 29)
	elseif name == "GATE" then
		return W(0, 0, -30)
	elseif name == "ARMORY" then
		return W(STATIONS[1].x, 0, STATIONS[1].z)
	elseif string.sub(name, 1, 7) == "TROPHY_" then
		for i, t in TROPHIES do
			if "TROPHY_" .. t.op == name then
				return W(Layout.trophyX(i), 0, SHOW_Z)
			end
		end
	end
	return W(0, 0, 0)
end

-- A trophy on the showcase row turns gold on cue (the boss the scene's sortie has just beaten).
local function sceneTrophy(opId: string)
	if not showEntry then
		return
	end
	local entry = table.clone(showEntry)
	entry.won = table.clone(entry.won or {})
	entry.won[opId] = true
	entry.trophyKey = tostring(entry.trophyKey) .. "+" .. opId
	Base.setShowcase(entry)
	local at = Base.point("TROPHY_" .. opId)
	Fx.ring(at + Vector3.new(0, 0.4, 0), 7, C.gold, 0.9)
	Fx.light(at + Vector3.new(0, 4, 0), C.gold, 26, 1.4)
	Fx.emitWith("streak", at + Vector3.new(0, 3, 0), 14, 1, C.gold)
	Audio.play("evolve", 0.6, 1.2)
end

-- The courtyard dark (the intro: the generator is dead) or lit.
function Base.sceneLights(on: boolean)
	setLamps(on, not on)
	setBulbs(on)
end

-- A spot comes back to life on cue: its model rises with sparks; the generator also lights the yard.
function Base.sceneRestore(id: string)
	if string.sub(id, 1, 7) == "TROPHY_" then
		sceneTrophy(string.sub(id, 8))
		return
	elseif not SPOTS[id] then
		-- a station (the armory): what came home lands there with a flash
		local at = Base.point(id)
		Fx.ring(at + Vector3.new(0, 0.4, 0), 7, C.orange, 0.9)
		Fx.light(at + Vector3.new(0, 4, 0), C.orange, 26, 1.4)
		Fx.emitWith("streak", at + Vector3.new(0, 3, 0), 14, 1, C.orange)
		Audio.play("evolve", 0.6, 1.1)
		return
	end
	if id == "LAB" and ((labResearch or {}).EN_SPITTER or 0) <= 0 then
		-- DD-077: the sample that rode home is in its tank even before the showcase catches up
		labResearch = table.clone(labResearch or {})
		labResearch.EN_SPITTER = math.max(1, labResearch.EN_SPITTER or 0)
	end
	restoredShown[id] = true
	showSpot(id, true, true)
	if id == "GENERATOR" then
		Base.sceneLights(true)
	end
end

-- The beam over a spot with a short title (what to do there next).
function Base.sceneMarker(id: string, title: string, sub: string)
	local sd = SPOTS[id]
	local at = Base.point(id)
	local color = if sd then sd.color else C.gold
	showGoalMarker(at, color, title, sub, "gear")
	Fx.ring(at + Vector3.new(0, 0.4, 0), 6, color, 0.8)
end

-- The shelter's end of the cable (crates arrive here).
function Base.cable()
	return cable
end

function Base.sceneCamera(dt: number): CFrame?
	if scene and scene.step then
		return scene.step(dt)
	end
	return nil
end

return Base
