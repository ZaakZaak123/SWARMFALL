--!nonstrict
-- The base (DD-052): the yard between the dropship and the drill where the squad lives between sorties.
-- You walk it: three stations you can see from the spawn (ОРУЖЕЙНАЯ, ПОСТРОЙКИ, ВЫСАДКА), the outpost
-- sockets around the drill, the one lit socket of the current goal. The same stations are buttons on
-- the HUD, so the walk is a pleasure and never a chore. Also owns the first-victory scene: the drill
-- starts, the floodlights come on, the camera finds the empty socket for the first turret.

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

local new, C, F = Theme.new, Theme.C, Theme.F
local label, tween = Theme.label, Theme.tween

local Base = {}

-- Layout (world). The spawn is (0, -58) facing the drill (north, +Z); the launch pad at the dropship ramp
-- just behind, the outpost terminal on the screen-left next to the first socket, the armory on the right,
-- the drill and its sockets ahead. (The camera looks north from the south: screen-left is world +X.)
local STATIONS = {
	{
		key = "armory",
		art = "ARMORY",
		h = 6.5,
		name = "ОРУЖЕЙНАЯ",
		sub = "Оружие и улучшения",
		icon = "swords",
		color = C.gold,
		x = -20,
		z = -56,
	},
	{
		key = "build",
		art = "BUILDDESK",
		h = 5.5,
		name = "ПОСТРОЙКИ",
		sub = "Турели аванпоста",
		icon = "shield",
		color = C.cyan,
		x = 22,
		z = -44,
	},
	{
		key = "launch",
		art = "BEACON",
		h = 10,
		name = "ВЫСАДКА",
		sub = "Выбор охоты · в бой",
		icon = "play",
		color = C.lime,
		x = 0,
		z = -71,
	},
	-- camp only (DD-053)
	{
		key = "board",
		art = "BOARD",
		h = 6.5,
		name = "ДОСКА ОТРЯДОВ",
		sub = "Найди напарников",
		icon = "users",
		color = C.orange,
		x = -17,
		z = -70,
		camp = true,
	},
	{
		key = "outposts",
		art = "RADAR",
		h = 7.5,
		name = "АВАНПОСТЫ",
		sub = "Базы других охотников",
		icon = "eye",
		color = C.pink,
		x = -24,
		z = -42,
		camp = true,
	},
}
local LAMPS = { { -32, -36 }, { 32, -36 }, { -30, -72 }, { 30, -72 } }

local send, actions -- set in init
local folder: Folder
local gui: ScreenGui
local ui = {}
local stationParts = {} -- key -> { pad, ring, beam, board, prompt, light, def }
local lamps = {} -- { head, light }
local sockets = {} -- index -> { ring, prompt }
local goalMarker = nil -- { model, ring, beam, board, slot, structure }
local profile = nil
local lobby = nil
local myId = 0
local active = false
local lampsOn = false
local goal = nil
local scene = nil -- running victory scene
local camp = nil -- camp state (squads + hunters) while in a public camp server

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
		pad.CFrame = CFrame.new(def.x, 0.12, def.z) * CFrame.Angles(0, 0, math.rad(90))
		local ring = ringPart("Ring", 4.8, def.color, 0.3, holder)
		ring.CFrame = CFrame.new(def.x, 0.3, def.z)
		local beam = part({
			Name = "Beam",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(14, 0.5, 0.5),
			Color = def.color,
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			Parent = holder,
		})
		beam.CFrame = CFrame.new(def.x, 7, def.z) * CFrame.Angles(0, 0, math.rad(90))
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
		pole.CFrame = CFrame.new(xz[1], 5.5, xz[2])
		pole.CastShadow = true
		local toward = Vector3.new(0, 0, -54) - Vector3.new(xz[1], 0, xz[2])
		local yaw = math.atan2(-toward.X, -toward.Z)
		local head = part({
			Name = "Head",
			Size = Vector3.new(1.6, 0.5, 0.9),
			Color = Color3.fromRGB(70, 64, 86),
			Material = Enum.Material.Neon,
			Parent = m,
		})
		head.CFrame = CFrame.new(xz[1], 11.2, xz[2]) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-35), 0, 0)
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
	-- socket markers (empty sockets, once the outpost is open)
	for i, s in Meta.Sockets do
		local holder = new("Model", { Name = "Socket" .. i, Parent = folder })
		local ring = ringPart("Ring", 3, C.cyan, 0.25, holder)
		ring.CFrame = CFrame.new(s.x, 0.25, s.z)
		setRing(ring, 1)
		local pr = prompt(ring, "Строить", "Гнездо " .. i, function()
			if actions and actions.socket then
				actions.socket(i)
			end
		end)
		pr.MaxActivationDistance = 7
		sockets[i] = { ring = ring, prompt = pr }
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

-- Each station: its model at the back of the pad, front to the camera; the bare beam goes away once
-- the model is there.
local function dressStations()
	for _, sp in stationParts do
		local def = sp.def
		if def.art and not sp.model then
			-- generated meshes face -Z: toward the camera; a slight turn toward the middle of the yard
			local at = Vector3.new(def.x, 0.25, def.z)
			local yaw = math.clamp(-def.x / 60, -0.35, 0.35)
			local m = artModel(def.art, def.h, CFrame.new(at + Vector3.new(0, 0, 1.6)) * CFrame.Angles(0, yaw, 0), sp.holder)
			if m then
				sp.model = m
				sp.beam.Transparency = 1
				sp.beam.Parent = nil
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

local function hologram(model: Model, color: Color3)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Material = Enum.Material.Neon
			d.Color = color
			d.Transparency = math.max(d.Transparency, 0.62)
			d.CastShadow = false
			d.CanCollide = false
			d.CanQuery = false
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

local function showGoalMarker(slot: number, structureId: string?, title: string, sub: string, buildable: boolean)
	local key = tostring(slot) .. "|" .. tostring(structureId) .. "|" .. title .. "|" .. sub .. tostring(buildable)
	if goalMarker and goalMarker.key == key then
		return
	end
	clearGoalMarker()
	local s = Meta.Sockets[slot]
	if not s then
		return
	end
	local def = structureId and Meta.Structures[structureId]
	local color = if def then def.color else C.lime
	local holder = new("Model", { Name = "GoalMarker", Parent = folder })
	local ring = ringPart("Ring", 4, color, 0.32, holder)
	ring.CFrame = CFrame.new(s.x, 0.32, s.z)
	local beam = part({
		Name = "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(60, 1.2, 1.2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
		Parent = holder,
	})
	beam.CFrame = CFrame.new(s.x, 30, s.z) * CFrame.Angles(0, 0, math.rad(90))
	new("PointLight", { Color = color, Range = 16, Brightness = 1.6, Shadows = false, Parent = ring })
	local model = nil
	if def then
		model = Structures.model(structureId, 1, false)
		hologram(model, color)
		model:PivotTo(CFrame.new(s.x, 0, s.z) * CFrame.Angles(0, math.atan2(s.x, s.z) + math.pi, 0))
		model.Parent = holder
	end
	local bb = board(ring, if def then def.icon else "pin", title, sub, color, 9)
	local pr = prompt(
		ring,
		if buildable and def then "Поставить" else "Строить",
		if def then def.name else "Гнездо",
		function()
			if actions and actions.goal then
				actions.goal()
			end
		end
	)
	pr.MaxActivationDistance = 9
	goalMarker =
		{ holder = holder, ring = ring, beam = beam, board = bb, prompt = pr, model = model, key = key, slot = slot }
end

-- Showcase row (DD-054) -----------------------------------------------------------------------------------
-- In front of the drill: the favourite gun on a stand and one pedestal per boss. A beaten boss stands in
-- gold; one not yet beaten is a faint hologram with the hunt that earns it — a goal you can walk up to.
-- Shows the base's owner: yours, or the hunter you are visiting.
local TROPHIES = {
	{ op = "O01", kind = 10, name = "АЛЬФА", hunt = "Охота 1" },
	{ op = "O05", kind = 7, name = "МАТЬ РОЯ", hunt = "Охота 5" },
	{ op = "O07", kind = 9, name = "ПОЖИРАТЕЛЬ", hunt = "Охота 7" },
}
local SHOW_Z = -33
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
	local plinth = artModel("PLINTH", 1.3, CFrame.new(x, 0, SHOW_Z), showFolder)
	local base = part({
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 5.6, 5.6),
		Color = Color3.fromRGB(34, 28, 48),
		Material = Enum.Material.Slate,
		Parent = showFolder,
	})
	base.CFrame = CFrame.new(x, 0.6, SHOW_Z) * CFrame.Angles(0, 0, math.rad(90))
	base.CastShadow = true
	if plinth then
		base.Transparency = 1 -- the generated plinth carries the look; this part stays as the anchor
		plinth.Size = Vector3.new(5.6, plinth.Size.Y, 5.6)
		plinth.CFrame = CFrame.new(x, plinth.Size.Y / 2, SHOW_Z)
	end
	local ring = ringPart("Ring", 3.2, color, 1.24, showFolder)
	ring.CFrame = CFrame.new(x, 1.24, SHOW_Z)
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
		local base = pedestal(-13, C.cyan, true)
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
			table.insert(spinners, { model = gun, cf = CFrame.new(-13, 2.2, SHOW_Z), speed = 0.6 })
		end
		plaque(base, if evo then evo.name else wdef.name, string.format("Любимое оружие · M%d", entry.mastery or 1), C.cyan)
	end
	-- the trophies
	for i, t in TROPHIES do
		local x = -1 + (i - 1) * 11
		local won = entry.won and entry.won[t.op]
		local base = pedestal(x, if won then C.gold else C.violet, won)
		local ok, m = pcall(Models.creature, t.kind)
		if ok and m then
			statue(m, won)
			fitTo(m, if t.kind == 10 then 5 else 6)
			m.Parent = showFolder
			table.insert(spinners, { model = m, cf = CFrame.new(x, 1.3, SHOW_Z), speed = if won then 0.25 else 0.1 })
		end
		plaque(base, t.name, if won then "Повержен" else t.hunt .. " · трофей", if won then C.gold else C.dim)
	end
	-- the siege record on the drill-side
	if (entry.siege or 0) > 0 then
		local base = pedestal(-24, C.orange, true)
		plaque(base, "ОСАДА " .. entry.siege, "Лучший удержанный уровень", C.orange)
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
		"Защитите аванпост вместе",
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
	ui.stBuild = stationButton(ui.stations, "build", "ПОСТРОЙКИ", "shield", C.cyan, 2)
	ui.stLaunch = stationButton(ui.stations, "launch", "ВЫСАДКА", "pin", C.lime, 3)
	ui.stBoard = stationButton(ui.stations, "board", "ОТРЯДЫ", "users", C.orange, 4)
	ui.stOutposts = stationButton(ui.stations, "outposts", "АВАНПОСТЫ", "eye", C.pink, 5)
	ui.stSwarm = stationButton(ui.stations, "swarm", "РОЙ", "hive", C.violet, 6)
	ui.stSwarm.Size = UDim2.fromOffset(110, 56)
	for _, b in { ui.stArmory, ui.stBuild, ui.stLaunch, ui.stBoard, ui.stOutposts } do
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
	-- the lights are on once the crater is ours
	local ours = ((profile.winsByOp or {}).O01 or 0) > 0
	if ours ~= lampsOn and not scene then
		setLamps(ours, true)
	end
	-- stations available
	stationParts.build.holder.Parent = if f.outpost then folder else nil
	stationParts.armory.holder.Parent = if (profile.runs or 0) > 0 then folder else nil
	stationParts.board.holder.Parent = if camp then folder else nil
	stationParts.outposts.holder.Parent = if camp then folder else nil
	-- sockets: faint rings on the empty ones while the outpost is open
	local slots = (profile.outpost and profile.outpost.slots) or {}
	if lobby and lobby.outpost then
		slots = lobby.outpost
	end
	local isHost = lobby ~= nil and lobby.host == myId
	local ownsBase = camp ~= nil or isHost -- in the camp every hunter builds their own outpost
	for i, s in sockets do
		local empty = not slots[i] and not slots[tostring(i)]
		-- the first steps light one socket only; the rest of the ring appears after the first defence
		local focused = goal ~= nil and (goal.key == "sting" or goal.key == "strike")
		local show = f.outpost == true
			and empty
			and ownsBase
			and not focused
			and not (goal and goal.slot == i and goal.station == "build")
		s.show = show
	end
	-- the goal socket
	if goal and goal.station == "build" and goal.slot and ownsBase and f.outpost then
		local def = goal.structure and Meta.Structures[goal.structure]
		local affordable = def ~= nil and (profile.scrap or 0) >= def.cost[1]
		local built = slots[goal.slot] or slots[tostring(goal.slot)]
		if built then
			clearGoalMarker()
		else
			showGoalMarker(
				goal.slot,
				goal.structure,
				if def then def.name else "ГНЕЗДО",
				if affordable
					then "Поставить · ◆ " .. def.cost[1]
					else "Нужно ◆ " .. (if def then def.cost[1] else 0),
				affordable
			)
		end
	else
		clearGoalMarker()
	end
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
		ui.tag.Text = string.format("КРАТЕР ЦВЕТЕНИЯ  ·  ОХОТНИКОВ: %d", #(camp.hunters or {}))
		ui.owner.Text = if #players > 1
			then "ОТРЯД " .. hostName:upper() .. string.format("  %d/4", #players)
			else "ЛАГЕРЬ"
	else
		ui.tag.Text = if isHost or hostName == "" then "ТВОЙ АВАНПОСТ" else "АВАНПОСТ ОТРЯДА"
		ui.owner.Text = if hostName ~= "" then hostName else Players.LocalPlayer.DisplayName
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
		local col = if goal.structure then Meta.Structures[goal.structure].color else C.lime
		local d = Icons.disc(goal.icon, 46, col, 2)
		d.Parent = ui.goalIcon
		setGoalView(goal.structure)
		local btn = nil
		if goal.key == "strike" then
			btn = nil
		elseif goal.station == "build" then
			local def = goal.structure and Meta.Structures[goal.structure]
			local affordable = def and (profile.scrap or 0) >= def.cost[if goal.key == "upgrade" then 2 else 1]
			btn = if goal.key == "upgrade"
				then "УЛУЧШИТЬ"
				elseif affordable then "ПОСТАВИТЬ"
				else "ПОСТРОЙКИ"
		elseif goal.station == "launch" then
			btn = if goal.op then "К ВЫСАДКЕ" else "ВЫСАДКА"
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
		then "ОСАДА · УРОВЕНЬ " .. (lobby.siege or 1)
		elseif lobby and lobby.mode == "raid" then "ВТОРЖЕНИЕ"
		elseif op then "ОХОТА " .. op.index .. " · " .. op.name
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
			"Высадка через %d  ·  готовы %d/%d",
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

-- API --------------------------------------------------------------------------------------------------------
function Base.init(playerGui: PlayerGui, sender, acts)
	send = sender
	actions = acts
	buildWorld()
	buildHud(playerGui)
	task.spawn(function()
		local rs = game:GetService("ReplicatedStorage")
		local f = rs:WaitForChild("ArtTemplates", 30)
		local t0 = os.clock()
		while f and not f:GetAttribute("Ready") and os.clock() - t0 < 30 do
			task.wait(0.5)
		end
		dressStations()
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
			options.PromptMessage = "Защитим мой аванпост вместе!"
			pcall(SocialService.PromptGameInvite, SocialService, lp, options)
		end
	end)
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
	for _, s in sockets do
		s.prompt.Enabled = active and s.show == true
		setRing(s.ring, if active and s.show then 0.55 else 1)
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
		goalMarker.prompt.Enabled = active
		goalMarker.board.Enabled = active or scene ~= nil
		if goalMarker.model then
			local s = Meta.Sockets[goalMarker.slot]
			goalMarker.model:PivotTo(
				CFrame.new(s.x, 0.15 + math.sin(now * 2) * 0.15, s.z)
					* CFrame.Angles(0, math.atan2(s.x, s.z) + math.pi + math.sin(now * 0.8) * 0.4, 0)
			)
		end
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
	local goalPos = hero + Vector3.new(0, 40, -30)
	camPos = if camPos then camPos:Lerp(goalPos, math.min(1, dt * 6)) else goalPos
	return CFrame.lookAt(camPos, camPos + Vector3.new(0, -40, 30) + Vector3.new(0, 0, 12))
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
function Base.victoryScene(startCf: CFrame, onDone, onDrill)
	if scene then
		return false
	end
	local sg = buildSceneGui()
	local s = Meta.Sockets[Meta.FirstSocket]
	local keys = {
		{ t = 0, cf = startCf },
		{ t = 1.8, cf = CFrame.lookAt(Vector3.new(30, 34, -44), Vector3.new(0, 6, 0)) },
		{ t = 3.9, cf = CFrame.lookAt(Vector3.new(-22, 24, -92), Vector3.new(4, 2, -56)) },
		{ t = 6.4, cf = CFrame.lookAt(Vector3.new(s.x + 16, 12, s.z - 20), Vector3.new(s.x, 2.5, s.z)) },
		{ t = 7.8, cf = CFrame.lookAt(Vector3.new(s.x + 13, 10, s.z - 17), Vector3.new(s.x, 2.5, s.z)) },
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
		at(0.2, function()
			caption(sg, "КРАТЕР ЗАЧИЩЕН", "Рой отступил в пасть титана")
		end)
		at(1.5, function()
			-- the drill comes alive
			local top = Vector3.new(0, 14, 0)
			Fx.ring(Vector3.new(0, 0.4, 0), 26, C.cyan, 1.2)
			Fx.light(top, C.cyan, 60, 1.6)
			Fx.emitWith("flash", top, 1, 3, C.cyan)
			for i = 1, 6 do
				local a = i / 6 * math.pi * 2
				Fx.emitWith("streak", top, 4, 1.2, C.cyan, Vector3.new(math.cos(a), 1.4, math.sin(a)).Unit)
			end
			Audio.play("evolve", 0.8, 0.8)
			if onDrill then
				onDrill()
			end
			caption(
				sg,
				"БУР ЗАПУЩЕН",
				"Кратер Цветения теперь твой аванпост",
				C.cyan
			)
		end)
		at(3.0, function()
			setLamps(true)
		end)
		at(3.6, function()
			local pad = stationParts.launch
			Fx.ring(pad.pad.Position + Vector3.yAxis * 0.3, 7, C.lime, 0.8)
			Audio.play("level", 0.5, 1.2)
		end)
		at(4.3, function()
			showGoalMarker(
				Meta.FirstSocket,
				"STING",
				"ЖАЛО",
				"Здесь встанет первая турель",
				true
			)
			Fx.ring(Vector3.new(s.x, 0.4, s.z), 6, Meta.Structures.STING.color, 0.8)
			Audio.play("level", 0.7, 1.5)
			caption(
				sg,
				"ДОБЫЧИ ХВАТИТ НА ПЕРВУЮ ТУРЕЛЬ",
				"Поставь «Жало» на базе — и рой пожалеет, что вернулся",
				C.gold
			)
		end)
		if t >= keys[#keys].t + 0.6 then
			task.defer(finish)
		end
		-- camera along the keys
		for i = 1, #keys - 1 do
			local a, b = keys[i], keys[i + 1]
			if t <= b.t then
				local k = ease(math.clamp((t - a.t) / (b.t - a.t), 0, 1))
				return a.cf:Lerp(b.cf, k)
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
