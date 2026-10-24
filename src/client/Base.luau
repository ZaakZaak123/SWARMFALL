--!nonstrict
-- The shelter (DD-052 → DD-057): a green grove far from the crater where the survivor lives between
-- sorties. You walk it: the old bunker, the gate out to the wasteland (ВЫЛАЗКА), the armory, and the
-- prepared spots you bring back to life one by one (generator, workshop, radio, lab, garden) — each
-- restored spot changes the place and opens something. The same functions are buttons on the HUD, so
-- the walk is a pleasure and never a chore. Also owns the first-victory scene: the return home, the
-- generator starts, the lights come on, the camera finds the broken workshop.
-- Everything here is drawn by this client: in a public camp every survivor sees their own shelter.

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

local new, C, F = Theme.new, Theme.C, Theme.F
local label, tween = Theme.label, Theme.tween

local Base = {}

-- Layout, in shelter coordinates (Meta.HomeOrigin = courtyard centre; the camera looks north, +Z, so
-- screen-left is +X). Spawn (0, -4) facing the bunker.
local O = Meta.HomeOrigin
local function W(x: number, y: number, z: number): Vector3
	return Vector3.new(O.X + x, y, O.Z + z)
end
local STATIONS = {
	{ key = "armory", art = "ARMORY", h = 6.5, name = "ОРУЖЕЙНАЯ", sub = "Оружие и улучшения", icon = "swords", color = C.gold, x = -26, z = 12 },
	{ key = "launch", art = "BEACON", h = 9, name = "ВЫЛАЗКА", sub = "Ворота в пустошь · в бой", icon = "play", color = C.lime, x = 0, z = -30 },
	-- camp only (DD-053): the settlement's shared posts
	{ key = "board", art = "BOARD", h = 6.5, name = "ДОСКА ОТРЯДОВ", sub = "Найди напарников", icon = "users", color = C.orange, x = -15, z = -27, camp = true },
	{ key = "outposts", art = "RADAR", h = 7.5, name = "УБЕЖИЩА", sub = "Дома других выживших", icon = "eye", color = C.pink, x = 15, z = -27, camp = true },
}
-- Prepared spots of the shelter (Meta.Home): rubble until restored, then the thing itself. A restored
-- spot is also a station: the workshop builds the drill's defences, the radio picks the drill defence,
-- the lab shows the samples.
local SPOTS = {
	GENERATOR = { art = "GENERATOR", h = 4.2, x = -11, z = 19, yaw = 0.3, color = C.gold },
	WORKBENCH = { art = "WORKBENCH", h = 5, x = 13, z = 13, yaw = -0.25, color = C.cyan, station = "build", stationName = "МАСТЕРСКАЯ", stationSub = "Оборона бура: турели, ловушки" },
	RADIO = { art = "RADIO", h = 6.5, x = -24, z = -3, yaw = 0.35, color = C.orange, station = "radio", stationName = "РАДИОСТАНЦИЯ", stationSub = "Оборона бура по уровням" },
	LAB = { art = "TANK_FRAME", h = 7.5, x = 27, z = 9, yaw = -0.3, color = C.violet, station = "swarm", stationName = "ЛАБОРАТОРИЯ", stationSub = "Образцы роя" },
	GARDEN = { art = "GARDEN", h = 4, x = -14, z = -14, yaw = 0.2, color = C.lime },
}
local LAMPS = { { -32, -20 }, { 32, -22 }, { -34, 24 }, { 34, 24 } }
-- The grove itself: the bunker, trees, old ruins, a wreck by the gate.
local DECOR = { -- { art, height, x, z, yaw }
	{ "SHELTER", 14, 0, 29, 0 },
	{ "OAK", 20, -42, 34, 0.4 },
	{ "OAK", 22, 46, 38, 2.1 },
	{ "OAK", 18, -56, -8, 1.2 },
	{ "OAK", 21, 60, 4, 3.3 },
	{ "OAK", 19, -40, -50, 2.6 },
	{ "OAK", 20, 44, -52, 0.9 },
	{ "OAK", 24, 4, 62, 1.7 },
	{ "BIRCH", 15, -26, 40, 0.3 },
	{ "BIRCH", 14, 28, 44, 1.1 },
	{ "BIRCH", 16, -60, 20, 2.2 },
	{ "BIRCH", 15, 62, -26, 0.6 },
	{ "BIRCH", 13, -48, -30, 1.9 },
	{ "BIRCH", 14, 50, -38, 2.8 },
	{ "BIRCH", 17, -18, 56, 0.8 },
	{ "BUSH", 3.2, -20, 26, 0 },
	{ "BUSH", 2.8, 20, 28, 1 },
	{ "BUSH", 3.4, -36, 8, 2 },
	{ "BUSH", 3.0, 38, -6, 0.5 },
	{ "BUSH", 2.6, -30, -34, 1.5 },
	{ "BUSH", 3.0, 30, -36, 2.5 },
	{ "BUSH", 3.6, -8, 40, 0.2 },
	{ "BUSH", 2.8, 12, 42, 1.2 },
	{ "BUSH", 3.2, -44, -16, 2.2 },
	{ "BUSH", 2.9, 46, 18, 0.7 },
	{ "RUIN_WALL", 5, -11, -36, 0 },
	{ "RUIN_WALL", 5, 11, -36, math.pi },
	{ "RUIN_WALL", 4.5, -48, 6, 1.57 },
	{ "RUIN_WALL", 5, 50, -10, -1.57 },
	{ "RUIN_WALL", 4.5, -22, 50, 0.1 },
	{ "RUIN_WALL", 4.2, 26, 52, -0.15 },
	{ "CAR_WRECK", 2.8, 9, -47, 0.5 },
	{ "CRATES", 3, -18, 24, 0.4 },
	{ "CRATES", 2.6, 19, 21, -0.6 },
}

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
	new(
		"Decal",
		{
			Name = "Glow",
			Face = Enum.NormalId.Top,
			Texture = Fx.Tex.ring,
			Color3 = color,
			Transparency = 0.2,
			Parent = r,
		}
	)
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
		pad.CFrame = CFrame.new(W(def.x, 0.12, def.z)) * CFrame.Angles(0, 0, math.rad(90))
		local ring = ringPart("Ring", 4.8, def.color, 0.3, holder)
		ring.CFrame = CFrame.new(W(def.x, 0.3, def.z))
		local beam = part({
			Name = "Beam",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(14, 0.5, 0.5),
			Color = def.color,
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			Parent = holder,
		})
		beam.CFrame = CFrame.new(W(def.x, 7, def.z)) * CFrame.Angles(0, 0, math.rad(90))
		local light =
			new("PointLight", { Color = def.color, Range = 14, Brightness = 1.2, Shadows = false, Parent = pad })
		local bb = board(pad, def.icon, def.name, def.sub, def.color, 8.5)
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
		pole.CFrame = CFrame.new(W(xz[1], 5.5, xz[2]))
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
		head.CFrame = CFrame.new(W(xz[1], 11.2, xz[2])) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-35), 0, 0)
		local spot = new(
			"SpotLight",
			{
				Face = Enum.NormalId.Front,
				Angle = 75,
				Range = 40,
				Brightness = 0,
				Color = Color3.fromRGB(255, 236, 200),
				Shadows = false,
				Parent = head,
			}
		)
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
			local m = artModel(def.art, def.h, CFrame.new(W(def.x, 0.25, def.z + 1.6)) * CFrame.Angles(0, yaw, 0), sp.holder)
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
			local m = artModel(d[1], d[2], CFrame.new(W(d[3], 0, d[4])) * CFrame.Angles(0, d[5], 0), grove)
			if m then
				m.CanCollide = d[1] ~= "BUSH"
			end
		end
	end
	for _, l in lamps do
		if not l.model then
			local pos = l.head.Position
			local m = artModel("FLOODLIGHT", 11, CFrame.new(pos.X, 0, pos.Z) * CFrame.Angles(0, l.yaw + math.pi, 0), l.head.Parent)
			if m then
				l.model = m
				l.pole.Transparency = 1
				l.head.Transparency = 1
				l.head.CFrame = CFrame.new(pos.X, 10.4, pos.Z) * CFrame.Angles(0, l.yaw, 0) * CFrame.Angles(math.rad(-35), 0, 0)
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
		ring.CFrame = CFrame.new(W(sd.x, 0.3, sd.z))
		local light = new("PointLight", { Color = Color3.fromRGB(255, 214, 160), Range = 12, Brightness = 0, Shadows = false, Parent = ring })
		local bb = board(ring, def.icon, def.name, "", sd.color, 7.5)
		local pr = prompt(ring, "Восстановить", def.name, function()
			if actions and actions.spot then
				actions.spot(id)
			end
		end)
		pr.MaxActivationDistance = 9
		spotParts[id] = { holder = holder, ring = ring, board = bb, prompt = pr, light = light, def = def, sd = sd }
	end
	-- string lights across the courtyard, from the bunker's corners to the front lamps
	local runs = { { W(-7, 7, 21.5), W(-32, 10, -20) }, { W(7, 7, 21.5), W(32, 10, -22) }, { W(-7, 7, 21.5), W(7, 7, 21.5) } }
	for _, r in runs do
		local a, b = r[1], r[2]
		local n = math.floor((b - a).Magnitude / 3)
		for k = 0, n do
			local t = k / n
			local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * 2.2, 0)
			local bulb = part({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.34, 0.34, 0.34), Color = Color3.fromRGB(90, 80, 70), Material = Enum.Material.SmoothPlastic, Parent = folder })
			bulb.CFrame = CFrame.new(p)
			table.insert(bulbs, bulb)
		end
	end
end

local labSample, labShown = -1, nil -- the lab tank (defined with the tank below)
local updateTank

-- The look of a spot: rubble until restored; restored = its model, warm light, and (animate) a burst.
local function showSpot(id: string, restored: boolean, animate: boolean)
	local sp = spotParts[id]
	if not sp then
		return
	end
	local sd = sp.sd
	local base = CFrame.new(W(sd.x, 0.25, sd.z + 0.8)) * CFrame.Angles(0, sd.yaw, 0)
	if restored then
		if sp.rubble then
			sp.rubble:Destroy()
			sp.rubble = nil
		end
		if not sp.model or not sp.model.Parent then
			if id == "LAB" then
				-- the specimen tank is built here (a generated mesh would hide its contents): a metal
				-- plinth, a glass column with the liquid, a cap with pipes; DD-059 fills it
				local metal = Color3.fromRGB(70, 74, 80)
				local brass = Color3.fromRGB(196, 150, 70)
				local holder = new("Model", { Name = "Tank", Parent = sp.holder })
				local function cyl(name: string, h: number, d: number, y: number, color: Color3, mat, transparency: number?)
					local c = part({ Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, d, d), Color = color, Material = mat, Transparency = transparency or 0, Parent = holder })
					c.CFrame = base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))
					c.CastShadow = transparency == nil
					return c
				end
				cyl("Plinth", 1.2, 4.6, 0.6, metal, Enum.Material.DiamondPlate)
				cyl("Rim", 0.25, 4.3, 1.3, brass, Enum.Material.Metal)
				local glass = cyl("Glass", 5.4, 3.8, 4.1, Color3.fromRGB(200, 236, 228), Enum.Material.Glass, 0.62)
				local liquid = cyl("Liquid", 4.9, 3.5, 3.9, Color3.fromRGB(120, 255, 170), Enum.Material.Neon, 0.82)
				cyl("RimTop", 0.25, 4.1, 6.9, brass, Enum.Material.Metal)
				cyl("Cap", 0.9, 4.3, 7.4, metal, Enum.Material.Metal)
				cyl("Valve", 0.6, 1.2, 8.1, brass, Enum.Material.Metal)
				for k = 0, 1 do
					local pipe = part({ Name = "Pipe", Size = Vector3.new(0.35, 7.5, 0.35), Color = metal, Material = Enum.Material.Metal, Parent = holder })
					pipe.CFrame = base * CFrame.new(if k == 0 then -2.3 else 2.3, 4.1, 0.6)
				end
				new("PointLight", { Color = Color3.fromRGB(140, 255, 180), Range = 10, Brightness = 1.2, Shadows = false, Parent = liquid })
				holder.PrimaryPart = glass
				sp.model = holder
				sp.tank = { glass = glass, liquid = liquid, base = base }
				labShown = nil
				task.defer(updateTank)
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
				Fx.emitWith("streak", pos + Vector3.yAxis, 3, 0.8, sd.color, Vector3.new(math.cos(a), 1.2, math.sin(a)).Unit)
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
			sp.model:Destroy()
			sp.model = nil
		end
		if not sp.rubble or not sp.rubble.Parent then
			sp.rubble = artModel("RUBBLE", 1.9, base, sp.holder)
		end
		sp.light.Brightness = 0
	end
end

-- The lab's specimen tank (DD-059): one species, the Spitter, studied by the squad's kills. The tank
-- fills as research grows: first samples → a dark silhouette → the full specimen → an exemplary one.
-- It is a collection — nothing here is spent (DNA for the own swarm is counted separately).
local SAMPLE_KIND = "EN_SPITTER"
local SAMPLE_INDEX = 3
local tankBits = {} -- parts to bob

local function sampleStage(n: number): number
	if n <= 0 then
		return 0
	end
	return 1 + Defs.researchStage(SAMPLE_KIND, n) -- 1 samples, 2 silhouette, 3 full, 4 exemplary
end

updateTank = function()
	local sp = spotParts.LAB
	local tank = sp and sp.tank
	if not tank or not tank.glass.Parent then
		labShown = nil
		return
	end
	local stage = sampleStage(labSample)
	if labShown == stage then
		return
	end
	labShown = stage
	if tank.content then
		tank.content:Destroy()
	end
	table.clear(tankBits)
	local content = new("Model", { Name = "Specimen", Parent = sp.holder })
	tank.content = content
	local centre = tank.glass.Position
	local liquidColor = Color3.fromRGB(120, 255, 170)
	if stage == 1 then
		-- first samples: tissue floating in the liquid
		for k = 1, 6 do
			local blob = part({ Name = "Sample", Shape = Enum.PartType.Ball, Size = Vector3.one * (0.35 + k * 0.06), Color = Color3.fromRGB(200, 255, 90), Material = Enum.Material.Neon, Transparency = 0.2, Parent = content })
			blob.CFrame = CFrame.new(centre + Vector3.new(math.cos(k * 1.7) * 0.9, (k - 3.5) * 0.6, math.sin(k * 1.7) * 0.9))
			table.insert(tankBits, { part = blob, base = blob.CFrame, phase = k })
		end
	elseif stage >= 2 then
		local ok, m = pcall(Models.creature, SAMPLE_INDEX)
		if ok and m then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CastShadow = false
					if stage == 2 then
						-- a dark silhouette behind the murk: you can tell what it is, not yet see it
						d.Material = Enum.Material.SmoothPlastic
						d.Color = Color3.fromRGB(16, 24, 18)
						d.Transparency = math.max(d.Transparency, 0.15)
						if d:IsA("MeshPart") then
							d.TextureID = ""
						end
					end
				elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
					d:Destroy()
				end
			end
			local _, size = m:GetBoundingBox()
			pcall(m.ScaleTo, m, m:GetScale() * (3.1 / math.max(size.X, size.Y, size.Z, 0.1)))
			local cf = m:GetBoundingBox()
			m.WorldPivot = cf
			m:PivotTo(CFrame.new(centre))
			m.Parent = content
			table.insert(tankBits, { model = m, phase = 0 })
		end
		if stage >= 4 then
			-- exemplary: gold rings on the tank and a brighter, clearer liquid
			liquidColor = Color3.fromRGB(150, 255, 210)
			for _, dy in { -1, 1 } do
				local ring = part({ Name = "GoldRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 3.9, 3.9), Color = Color3.fromRGB(232, 182, 72), Material = Enum.Material.Metal, Parent = content })
				ring.CFrame = CFrame.new(centre + Vector3.new(0, dy * tank.glass.Size.X * 0.42, 0)) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
	end
	tank.liquid.Color = liquidColor
	tank.liquid.Transparency = if stage == 2 then 0.62 else 0.74
end

local function labText(n: number): string
	local stage = sampleStage(n)
	local t = Defs.Research[SAMPLE_KIND]
	local nextNeed = t[math.min(#t, math.max(1, stage))]
	local names = { "нужны образцы", "первые образцы", "силуэт", "полный экземпляр", "образцовый экземпляр" }
	local base = "Плевун · " .. names[stage + 1]
	if stage < 4 then
		base ..= string.format(" · %d/%d", n, if stage == 0 then t[1] else nextNeed)
	end
	return base
end

local function setBulbs(on: boolean)
	for i, b in bulbs do
		b.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		b.Color = if on then (if i % 3 == 0 then Color3.fromRGB(230, 140, 70) else Color3.fromRGB(220, 170, 90)) else Color3.fromRGB(90, 80, 70)
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
	local beam = part({
		Name = "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(60, 1.2, 1.2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
		Parent = holder,
	})
	beam.CFrame = CFrame.new(pos.X, 30, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	-- the spot under the beam already carries its own sign
	goalMarker = { holder = holder, ring = ring, beam = beam, key = key }
end

-- Showcase row (DD-054) -----------------------------------------------------------------------------------
-- In front of the drill: the favourite gun on a stand and one pedestal per boss. A beaten boss stands in
-- gold; one not yet beaten is a faint hologram with the hunt that earns it — a goal you can walk up to.
-- Shows the base's owner: yours, or the hunter you are visiting.
local TROPHIES = {
	{ op = "O01", kind = 10, name = "АЛЬФА", hunt = "вылазка 1" },
	{ op = "O05", kind = 7, name = "МАТЬ РОЯ", hunt = "вылазка 5" },
	{ op = "O07", kind = 9, name = "ПОЖИРАТЕЛЬ", hunt = "вылазка 7" },
}
local SHOW_Z = -16 -- shelter coordinates
local showFolder = nil
local showKey = nil
local spinners = {} -- { model, cf, height }

-- Scale to a height and move the pivot to the bottom centre, so it stands and spins in place.
local function fitTo(model: Model, height: number, longest: boolean?)
	local _, size = model:GetBoundingBox()
	local k = if longest then height / math.max(size.X, size.Y, size.Z, 0.1) else height / math.max(size.Y, size.X * 0.6, size.Z * 0.6, 0.1)
	pcall(model.ScaleTo, model, model:GetScale() * k)
	local cf, sz = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(cf.X, cf.Y - sz.Y / 2, cf.Z)
end

local function pedestal(x: number, color: Color3, lit: boolean): BasePart
	local plinth = artModel("PLINTH", 1.3, CFrame.new(W(x, 0, SHOW_Z)), showFolder)
	local base = part({
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 5.6, 5.6),
		Color = Color3.fromRGB(34, 28, 48),
		Material = Enum.Material.Slate,
		Parent = showFolder,
	})
	base.CFrame = CFrame.new(W(x, 0.6, SHOW_Z)) * CFrame.Angles(0, 0, math.rad(90))
	base.CastShadow = true
	if plinth then
		base.Transparency = 1 -- the generated plinth carries the look; this part stays as the anchor
		plinth.Size = Vector3.new(5.6, plinth.Size.Y, 5.6)
		plinth.CFrame = CFrame.new(W(x, plinth.Size.Y / 2, SHOW_Z))
	end
	local ring = ringPart("Ring", 3.2, color, 1.24, showFolder)
	ring.CFrame = CFrame.new(W(x, 1.24, SHOW_Z))
	setRing(ring, if lit then 0.1 else 0.7)
	if lit then
		new("PointLight", { Color = color, Range = 9, Brightness = 1.2, Shadows = false, Parent = base })
	end
	return base
end

local function plaque(base: BasePart, title: string, sub: string, color: Color3)
	local b = new("BillboardGui", {
		Size = UDim2.fromOffset(150, 34),
		StudsOffsetWorldSpace = Vector3.new(0, 7.5, 0),
		LightInfluence = 0,
		MaxDistance = 90,
		Adornee = base,
		Parent = base,
	})
	local t = label(title, { Size = UDim2.new(1, 0, 0, 18), FontFace = F.display, TextSize = 13, TextColor3 = color, Parent = b })
	new("UIStroke", { Color = C.ink, Thickness = 2, Parent = t })
	local s2 = label(sub, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 14), FontFace = F.bodyBold, TextSize = 11, TextColor3 = C.dim, Parent = b })
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
				d.Material = Enum.Material.Neon
				d.Color = C.violet
				d.Transparency = math.max(d.Transparency, 0.8)
			end
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") or d:IsA("Light") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
end

-- entry: a Showcase entry (or the same fields built from the own profile); nil hides the row.
function Base.setShowcase(entry)
	local n = if entry and entry.sample then entry.sample else 0
	if n ~= labSample then
		labSample = n
		labShown = nil
		updateTank()
	end
	local key = if entry then table.concat({ entry.id, entry.weapon, tostring(entry.form), entry.mastery, entry.siege, tostring(entry.trophyKey) }, "|") else "none"
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
			table.insert(spinners, { model = gun, cf = CFrame.new(W(-2, 2.2, SHOW_Z)), speed = 0.6 })
		end
		plaque(base, if evo then evo.name else wdef.name, string.format("Любимое оружие · M%d", entry.mastery or 1), C.cyan)
	end
	-- the trophies
	for i, t in TROPHIES do
		local x = 8 + (i - 1) * 9
		local won = entry.won and entry.won[t.op]
		local base = pedestal(x, if won then C.gold else C.violet, won)
		local ok, m = pcall(Models.creature, t.kind)
		if ok and m then
			statue(m, won)
			fitTo(m, if t.kind == 10 then 5 else 6)
			m.Parent = showFolder
			table.insert(spinners, { model = m, cf = CFrame.new(W(x, 1.3, SHOW_Z)), speed = if won then 0.25 else 0.1 })
		end
		plaque(base, t.name, if won then "Повержен · " .. t.hunt else t.hunt .. " · трофей", if won then C.gold else C.dim)
	end
	-- the siege record on the drill-side
	if (entry.siege or 0) > 0 then
		local base = pedestal(-26, C.orange, true)
		plaque(base, "ОБОРОНА " .. entry.siege, "Лучший удержанный уровень бура", C.orange)
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
	new(
		"UIPadding",
		{
			PaddingLeft = UDim.new(0, 24),
			PaddingRight = UDim.new(0, 24),
			PaddingTop = UDim.new(0, 16),
			PaddingBottom = UDim.new(0, 20),
			Parent = safe,
		}
	)
	-- top-left: whose outpost
	ui.tag = label(
		"АВАНПОСТ",
		{
			Position = UDim2.fromOffset(4, 0),
			Size = UDim2.fromOffset(420, 16),
			FontFace = F.head,
			TextSize = 12,
			TextColor3 = C.lime,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = safe,
		}
	)
	ui.owner = label(
		"",
		{
			Position = UDim2.fromOffset(2, 16),
			Size = UDim2.fromOffset(520, 40),
			FontFace = F.display,
			TextSize = 34,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = safe,
		}
	)
	new("UIStroke", { Color = C.ink, Thickness = 3, Transparency = 0.2, Parent = ui.owner })
	ui.ownerNote = label("", { Position = UDim2.fromOffset(4, 246), Size = UDim2.fromOffset(440, 30), FontFace = F.body, TextSize = 12, TextColor3 = C.dim, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = safe })
	-- goal card
	local card = Theme.panel(
		{ Name = "Goal", Position = UDim2.fromOffset(0, 68), Size = UDim2.fromOffset(440, 168), CornerRadius = 18 },
		C.lime
	)
	card.Parent = safe
	ui.goal = card
	ui.goalTag = label(
		"СЛЕДУЮЩАЯ ЦЕЛЬ",
		{
			Position = UDim2.fromOffset(18, 12),
			Size = UDim2.fromOffset(260, 14),
			FontFace = F.head,
			TextSize = 11,
			TextColor3 = C.lime,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		}
	)
	ui.goalIcon = new("Frame", { Position = UDim2.fromOffset(16, 34), Size = UDim2.fromOffset(46, 46), Parent = card })
	ui.goalTitle = label(
		"",
		{
			Position = UDim2.fromOffset(72, 32),
			Size = UDim2.new(1, -184, 0, 24),
			FontFace = F.display,
			TextSize = 19,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		}
	)
	new("UITextSizeConstraint", { MaxTextSize = 19, Parent = ui.goalTitle })
	ui.goalText = label(
		"",
		{
			Position = UDim2.fromOffset(72, 58),
			Size = UDim2.new(1, -184, 0, 66),
			FontFace = F.body,
			TextSize = 13,
			TextColor3 = C.dim,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = card,
		}
	)
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
	ui.goalBtn, ui.goalBtnLabel = Theme.button(
		"",
		{
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 72, 1, -12),
			Size = UDim2.fromOffset(170, 34),
			TextSize = 13,
		},
		"primary"
	)
	ui.goalBtn.Parent = card
	ui.goalBtn.Activated:Connect(function()
		Audio.play("ui")
		if actions and actions.goal then
			actions.goal()
		end
	end)
	-- top-right: xenite, settings, invite, squad
	local tr = new(
		"Frame",
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(420, 360),
			Parent = safe,
		}
	)
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
	new(
		"Frame",
		{
			Size = UDim2.fromOffset(15, 15),
			Rotation = 45,
			BackgroundColor3 = C.pink,
			Corner = 3,
			LayoutOrder = 1,
			Parent = ui.xenite,
		}
	)
	ui.xeniteAmount = label(
		"0",
		{
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
			FontFace = F.numHeavy,
			TextSize = 18,
			LayoutOrder = 2,
			Parent = ui.xenite,
		}
	)
	ui.invite = Theme.button(
		"ПОЗВАТЬ ДРУГА",
		{
			Name = "Invite",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 54),
			Size = UDim2.fromOffset(212, 40),
			TextSize = 12,
		}
	)
	ui.invite.Parent = tr
	ui.invite.Activated:Connect(function()
		Audio.play("ui")
		Base.invite()
	end)
	ui.inviteSub = label(
		"Отбейте бур вместе",
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 96),
			Size = UDim2.fromOffset(260, 14),
			FontFace = F.body,
			TextSize = 11,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = tr,
		}
	)
	ui.harvest = Theme.button(
		"СОБРАТЬ",
		{
			Name = "Harvest",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 118),
			Size = UDim2.fromOffset(212, 40),
			TextSize = 12,
		},
		"primary"
	)
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
	ui.stOutposts = stationButton(ui.stations, "outposts", "УБЕЖИЩА", "eye", C.pink, 5)
	ui.stSwarm = stationButton(ui.stations, "swarm", "ЛАБОРАТОРИЯ", "hive", C.violet, 6)
	for _, b in { ui.stArmory, ui.stBuild, ui.stLaunch, ui.stBoard, ui.stOutposts, ui.stSwarm } do
		b.Size = UDim2.fromOffset(156, 56)
	end
	-- session base: back to the public camp
	ui.toCamp, ui.toCampLabel = Theme.button(
		"В ЛАГЕРЬ",
		{
			Name = "ToCamp",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -224, 0, 54),
			Size = UDim2.fromOffset(150, 40),
			TextSize = 12,
		}
	)
	ui.toCamp.Parent = tr
	ui.toCamp.Visible = false
	ui.toCamp.Activated:Connect(function()
		Audio.play("ui")
		if actions and actions.camp then
			actions.camp()
		end
	end)
	-- bottom-right: go
	ui.play, ui.playLabel = Theme.button(
		"В БОЙ",
		{
			Name = "Play",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 0, 1, -24),
			Size = UDim2.fromOffset(300, 84),
			TextSize = 32,
		},
		"primary"
	)
	ui.play.Parent = safe
	ui.playLabel.Position = UDim2.fromOffset(22, -8)
	ui.playIcon = Icons.new("play", 30, C.ink)
	ui.playIcon.AnchorPoint = Vector2.new(0, 0.5)
	ui.playIcon.Position = UDim2.new(0, 30, 0.5, 0)
	ui.playIcon.ZIndex = 3
	ui.playIcon.Parent = ui.play
	ui.playSub = label(
		"",
		{
			Position = UDim2.new(0, 22, 1, -30),
			Size = UDim2.new(1, -22, 0, 18),
			FontFace = F.head,
			TextSize = 12,
			TextColor3 = C.ink,
			TextTransparency = 0.25,
			ZIndex = 3,
			Parent = ui.play,
		}
	)
	ui.playGlow = new(
		"UIStroke",
		{
			Color = C.lime,
			Thickness = 5,
			Transparency = 0.6,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = ui.play,
		}
	)
	ui.play.Activated:Connect(function()
		if actions and actions.play then
			actions.play()
		end
	end)
	ui.status = label(
		"",
		{
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -8, 1, 0),
			Size = UDim2.fromOffset(420, 20),
			FontFace = F.bodyBold,
			TextSize = 15,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = safe,
		}
	)
	ui.hold, ui.holdLabel = Theme.button(
		"ЖДАТЬ ДРУЗЕЙ",
		{
			Name = "Hold",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -310, 1, -24),
			Size = UDim2.fromOffset(170, 44),
			TextSize = 12,
		}
	)
	ui.hold.Parent = safe
	ui.hold.Visible = false
	ui.hold.Activated:Connect(function()
		Audio.play("ui")
		send("hold", not (lobby and lobby.hold))
	end)
	-- centre: the swarm is coming (first turret built)
	ui.strike = new(
		"Frame",
		{
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 120),
			Size = UDim2.fromOffset(640, 110),
			Visible = false,
			Parent = gui,
		}
	)
	ui.strikeTitle = label(
		"РОЙ УСЛЫШАЛ БУР",
		{ Size = UDim2.new(1, 0, 0, 64), FontFace = F.display, TextSize = 54, TextColor3 = C.red, Parent = ui.strike }
	)
	new("UIStroke", { Color = C.ink, Thickness = 4, Transparency = 0.15, Parent = ui.strikeTitle })
	ui.strikeSub = label(
		"",
		{
			Position = UDim2.fromOffset(0, 66),
			Size = UDim2.new(1, 0, 0, 26),
			FontFace = F.head,
			TextSize = 20,
			Parent = ui.strike,
		}
	)
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
	goal = Goals.next(profile)
	local home = visitHome or profile.home or {}
	local switched = lastVisit ~= visitHome
	lastVisit = visitHome
	local won = profile.winsByOp or {}
	stationParts.armory.holder.Parent = if (profile.runs or 0) > 0 then folder else nil
	stationParts.board.holder.Parent = if camp then folder else nil
	stationParts.outposts.holder.Parent = if camp then folder else nil
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
		if restoredShown[id] ~= restored then
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
			sub.Text = if restored and id == "LAB" and labSample >= 0 then labText(labSample)
				elseif restored then (sd.stationSub or "Восстановлено")
				elseif def.free then "Заработает после вылазки 1"
				elseif not open then "Откроется после вылазки " .. tostring(tonumber(def.unlock:sub(2)) or "")
				else string.format("Починить · ◆ %d%s", def.cost, if affordable then "" else " (не хватает)")
		end
		sp.canRestore = visitHome == nil and not restored and open and not def.free
		sp.isStation = visitHome == nil and restored and sd.station ~= nil
	end
	-- the goal: a beam over the place where it happens
	if goal and goal.station == "home" and goal.spot and spotParts[goal.spot] then
		local sd = SPOTS[goal.spot]
		local def = Meta.Home[goal.spot]
		showGoalMarker(W(sd.x, 0, sd.z), sd.color, def.name, "Починить · ◆ " .. def.cost, def.icon)
	elseif goal and goal.station == "build" and f.outpost then
		local sd = SPOTS.WORKBENCH
		local def = goal.structure and Meta.Structures[goal.structure]
		showGoalMarker(W(sd.x, 0, sd.z), C.cyan, if def then "СОБРАТЬ: " .. def.name else "МАСТЕРСКАЯ", if def then "Для бура · ◆ " .. def.cost[1] else "", if def then def.icon else "gear")
	else
		clearGoalMarker()
	end
	local isHost = lobby ~= nil and lobby.host == myId
	local ownsBase = true -- the shelter is always your own (in a camp every survivor sees theirs)
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
		ui.tag.Text = string.format("ПОСЕЛЕНИЕ ВЫЖИВШИХ  ·  ЗДЕСЬ: %d", #(camp.hunters or {}))
		ui.owner.Text = if #players > 1
			then "ОТРЯД " .. hostName:upper() .. string.format("  %d/4", #players)
			else "ТВОЁ УБЕЖИЩЕ"
		ui.ownerNote.Text = "Убежище у каждого своё: другие выжившие видят здесь своё. Чужое — через «Убежища»."
	else
		ui.tag.Text = if isHost or hostName == "" then "ТВОЁ УБЕЖИЩЕ" else "УБЕЖИЩЕ ОТРЯДА · у каждого своё"
		ui.owner.Text = Players.LocalPlayer.DisplayName
		ui.ownerNote.Text = ""
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
		local col = if goal.structure then Meta.Structures[goal.structure].color
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
		then "ОБОРОНА БУРА · " .. (if profile.tut and profile.tut.strike then "УРОВЕНЬ " .. (lobby.siege or 1) else "ПЕРВЫЙ НАТИСК")
		elseif lobby and lobby.mode == "raid" then "ВТОРЖЕНИЕ"
		elseif op then "ВЫЛАЗКА " .. op.index .. " · " .. op.name
		else ""
	ui.playLabel.Text = if amReady then "ОТМЕНА" else "В БОЙ"
	ui.playSub.Text = if amReady then "ждём отряд" else modeName
	ui.play.BackgroundColor3 = if amReady then C.ink else C.lime
	ui.playLabel.TextColor3 = if amReady then C.text else C.ink
	ui.playSub.TextColor3 = if amReady then C.dim else C.ink
	Icons.recolor(ui.playIcon, if amReady then C.text else C.ink)
	local cd = lobby and lobby.countdown
	ui.status.Text = if cd and lobby.hold
		then string.format("Ждём друзей  ·  готовы %d/%d", ready, n)
		elseif cd then string.format(
			"Выход через %d  ·  готовы %d/%d",
			math.ceil(cd),
			ready,
			n
		)
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
function Base.init(playerGui: PlayerGui, sender, acts)
	send = sender
	actions = acts
	buildWorld()
	buildSpots()
	buildHud(playerGui)
	task.spawn(function()
		local rs = game:GetService("ReplicatedStorage")
		local f = rs:WaitForChild("ArtTemplates", 30)
		local t0 = os.clock()
		while f and not f:GetAttribute("Ready") and os.clock() - t0 < 30 do
			task.wait(0.5)
		end
		dressStations()
		applyQuality()
	end)
end

function Base.setProfile(pub)
	profile = pub
	Base.refresh()
end

function Base.setLobby(info, id: number)
	lobby = info
	myId = id
	Base.refresh()
end

-- Visiting another survivor's shelter in the camp: their restored spots replace ours on this screen.
function Base.setVisitHome(home)
	visitHome = home
	Base.refresh()
end

function Base.setCamp(info)
	camp = info
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
function Base.update(_dt: number, _root: Vector3?)
	local now = os.clock()
	for _, s in stationParts do
		s.prompt.Enabled = active
		s.board.Enabled = active
		local hot = goal and goal.station == s.def.key and active
		local pulse = if hot then math.sin(now * 4) else 0
		setRing(s.ring, (if active then 0.15 else 0.7) + math.sin(now * 2 + s.def.x) * 0.1, 4.8 + pulse * 0.4)
		s.beam.Transparency = if active then 0.62 + math.sin(now * 1.6 + s.def.z) * 0.08 else 0.85
		s.light.Brightness = if hot then 2 + pulse else 1
	end
	for id, sp in spotParts do
		local usable = active and (sp.canRestore or sp.isStation)
		sp.prompt.Enabled = usable == true
		sp.prompt.ActionText = if sp.isStation then (sp.sd.stationName or sp.def.name) else "Починить · ◆ " .. sp.def.cost
		sp.board.Enabled = active or scene ~= nil
		local glow = if sp.canRestore then 0.25 + math.sin(now * 3 + sp.sd.x) * 0.15 elseif sp.isStation then 0.45 else 0.85
		setRing(sp.ring, glow)
		if sp.tank and sp.tank.liquid.Parent then
			sp.tank.liquid.Transparency = (if labShown == 2 then 0.62 else 0.74) + math.sin(now * 1.3) * 0.04
		end
		local _ = id
	end
	for _, b in tankBits do
		if b.part and b.part.Parent then
			b.part.CFrame = b.base * CFrame.new(0, math.sin(now * 0.8 + b.phase) * 0.25, 0)
		elseif b.model and b.model.Parent then
			local c = spotParts.LAB and spotParts.LAB.tank and spotParts.LAB.tank.glass
			if c then
				b.model:PivotTo(CFrame.new(c.Position + Vector3.new(0, math.sin(now * 0.6) * 0.3, 0)) * CFrame.Angles(0, now * 0.15, 0))
			end
		end
	end
	for _, sp in spinners do
		if sp.model.Parent then
			sp.model:PivotTo(sp.cf * CFrame.Angles(0, now * sp.speed, 0))
		end
	end
	if goalMarker then
		local pulse = 0.5 + math.sin(now * 3.2) * 0.5
		setRing(goalMarker.ring, pulse * 0.4, 3.6 + pulse * 0.8)
		goalMarker.beam.Transparency = 0.55 + pulse * 0.25

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
		if ui.strike.Visible then
			ui.strikeTitle.TextTransparency = math.abs(math.sin(now * 5)) * 0.35
		end
	end
end

-- Base camera: a high three-quarter view that follows the hero, the drill ahead (north is up).
local camPos = nil
function Base.camera(dt: number, hero: Vector3): CFrame
	local goalPos = hero + Vector3.new(0, 46, -36)
	camPos = if camPos then camPos:Lerp(goalPos, math.min(1, dt * 6)) else goalPos
	return CFrame.lookAt(camPos, camPos + Vector3.new(0, -46, 36) + Vector3.new(0, 0, 4))
end

function Base.resetCamera()
	camPos = nil
end

-- First victory scene ---------------------------------------------------------------------------------------
local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

function Base.sceneActive(): boolean
	return scene ~= nil
end

local function buildSceneGui()
	local g = new(
		"ScreenGui",
		{ Name = "SporeScene", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, Parent = gui.Parent }
	)
	local top = new(
		"Frame",
		{
			Size = UDim2.new(1, 0, 0.11, 0),
			Position = UDim2.fromScale(0, -0.11),
			BackgroundColor3 = Color3.new(0, 0, 0),
			Parent = g,
		}
	)
	local bottom = new(
		"Frame",
		{
			AnchorPoint = Vector2.new(0, 1),
			Size = UDim2.new(1, 0, 0.11, 0),
			Position = UDim2.fromScale(0, 1.11),
			BackgroundColor3 = Color3.new(0, 0, 0),
			Parent = g,
		}
	)
	local cap = label(
		"",
		{
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0.86, 0),
			Size = UDim2.new(0.9, 0, 0, 44),
			FontFace = F.display,
			TextSize = 34,
			TextTransparency = 1,
			Parent = g,
		}
	)
	new("UIStroke", { Color = C.ink, Thickness = 3, Transparency = 0.2, Parent = cap })
	local sub = label(
		"",
		{
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.86, 4),
			Size = UDim2.new(0.9, 0, 0, 24),
			FontFace = F.bodyBold,
			TextSize = 18,
			TextColor3 = C.dim,
			TextTransparency = 1,
			Parent = g,
		}
	)
	local skip, skipLabel = Theme.button(
		"ПРОПУСТИТЬ  ›",
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -24, 0.945, 0),
			Size = UDim2.fromOffset(190, 40),
			TextSize = 13,
		}
	)
	skip.Parent = g
	skipLabel.ZIndex = 3
	tween(top, 0.5, { Position = UDim2.fromScale(0, 0) })
	tween(bottom, 0.5, { Position = UDim2.fromScale(0, 1) })
	return { gui = g, cap = cap, sub = sub, skip = skip, top = top, bottom = bottom }
end

local function caption(sg, text: string, subText: string?, color: Color3?)
	sg.cap.Text = text
	sg.cap.TextColor3 = color or C.text
	sg.sub.Text = subText or ""
	sg.cap.TextTransparency = 1
	sg.sub.TextTransparency = 1
	tween(sg.cap, 0.35, { TextTransparency = 0 })
	tween(sg.sub, 0.5, { TextTransparency = 0 })
end

-- Plays once after the first hunt is won; onDone runs when it ends or is skipped. Returns false if it
-- cannot play (no camera).
-- The return home after the first sortie: the grove from above, the generator coughs to life, the
-- lights come on, the camera finds the broken workshop the loot will pay for.
function Base.victoryScene(startCf: CFrame, onDone, onReturn)
	if scene then
		return false
	end
	local sg = buildSceneGui()
	local wb = SPOTS.WORKBENCH
	local gen = SPOTS.GENERATOR
	local keys = {
		{ t = 0, cf = startCf },
		{ t = 0.01, cf = CFrame.lookAt(W(0, 70, -110), W(0, 6, 10)) },
		{ t = 2.2, cf = CFrame.lookAt(W(-6, 26, -34), W(-4, 4, 16)) },
		{ t = 4.4, cf = CFrame.lookAt(W(gen.x + 8, 9, gen.z - 14), W(gen.x - 2, 3, gen.z + 4)) },
		{ t = 6.6, cf = CFrame.lookAt(W(wb.x + 4, 9, wb.z - 15), W(wb.x, 2, wb.z)) },
		{ t = 8.0, cf = CFrame.lookAt(W(wb.x + 3, 8, wb.z - 13), W(wb.x, 2, wb.z)) },
	}
	local fired = {}
	local done = false
	scene = { t = 0, keys = keys }
	local function finish()
		if done then
			return
		end
		done = true
		scene = nil
		setLamps(true, true)
		setBulbs(true)
		tween(sg.top, 0.35, { Position = UDim2.fromScale(0, -0.11) })
		tween(sg.bottom, 0.35, { Position = UDim2.fromScale(0, 1.11) })
		task.delay(0.4, function()
			sg.gui:Destroy()
		end)
		onDone()
	end
	sg.skip.Activated:Connect(finish)
	scene.step = function(dt: number): CFrame
		scene.t += dt
		local t = scene.t
		local function at(time: number, fn)
			if t >= time and not fired[time] then
				fired[time] = true
				fn()
			end
		end
		at(0.05, function()
			if onReturn then
				onReturn()
			end
			caption(sg, "ГЕНЕРАТОР ДОБЫТ", "Дорога домой, в зелёную рощу")
		end)
		at(3.0, function()
			-- the generator coughs to life and the shelter wakes up
			restoredShown.GENERATOR = true
			showSpot("GENERATOR", true, true)
			Audio.play("evolve", 0.8, 0.7)
			caption(sg, "УБЕЖИЩЕ ОЖИВАЕТ", "Свет, тепло и гирлянды над двором", C.gold)
		end)
		at(3.6, function()
			setLamps(true)
			setBulbs(true)
		end)
		at(5.0, function()
			local def = Meta.Home.WORKBENCH
			showGoalMarker(W(wb.x, 0, wb.z), wb.color, def.name, "Починить · ◆ " .. def.cost, def.icon)
			Fx.ring(W(wb.x, 0.4, wb.z), 6, wb.color, 0.8)
			Audio.play("level", 0.7, 1.5)
			caption(sg, "ДОБЫЧИ ХВАТИТ НА МАСТЕРСКУЮ", "На верстаке соберёшь оборону для бура", C.cyan)
		end)
		if t >= keys[#keys].t + 0.6 then
			task.defer(finish)
		end
		for k = 1, #keys - 1 do
			local a, b = keys[k], keys[k + 1]
			if t <= b.t then
				local e = ease(math.clamp((t - a.t) / math.max(0.01, b.t - a.t), 0, 1))
				return a.cf:Lerp(b.cf, e)
			end
		end
		return keys[#keys].cf
	end
	return true
end

function Base.sceneCamera(dt: number): CFrame?
	if scene and scene.step then
		return scene.step(dt)
	end
	return nil
end

return Base
