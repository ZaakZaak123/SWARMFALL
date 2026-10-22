--!nonstrict
-- «УЗЕЛ-7»: the compact physical base between operations (GDD §11.3, DD-011). Built once from parts,
-- far from the arena. Terminals carry ProximityPrompts; the client opens the same menus the quick
-- interface uses. Trophy pedestals are lit per player on the client from their own profile.

local Hub = {}

local ORIGIN = Vector3.new(0, 0, 640)
Hub.Origin = ORIGIN
Hub.Spawn = ORIGIN + Vector3.new(0, 3.2, -14)

local function part(parent: Instance, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Color = props.Color or Color3.fromRGB(28, 36, 48)
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Name = props.Name or "Part"
	p.CanCollide = props.CanCollide ~= false
	p.CastShadow = props.CastShadow ~= false
	p.Transparency = props.Transparency or 0
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = parent
	return p
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

local function sign(parent: BasePart, text: string, color: Color3)
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(220, 40)
	g.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	g.LightInfluence = 0
	g.MaxDistance = 60
	g.Parent = parent
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.4
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.Parent = g
end

local function terminal(root: Instance, name: string, label: string, action: string, cf: CFrame, color: Color3)
	local base = part(root, { Name = name, Size = Vector3.new(4, 3.4, 2.4), CFrame = cf * CFrame.new(0, 1.7, 0), Color = Color3.fromRGB(34, 44, 58), Material = Enum.Material.Metal })
	local screen = part(root, { Name = name .. "Screen", Size = Vector3.new(3.4, 2.2, 0.2), CFrame = cf * CFrame.new(0, 3.9, -0.6) * CFrame.Angles(math.rad(-20), 0, 0), Color = color, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false })
	light(screen, color, 14, 1.6)
	sign(screen, label, color)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = label
	prompt.ObjectText = "УЗЕЛ-7"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("Terminal", action)
	prompt.Parent = base
	return base
end

local function pedestal(root: Instance, name: string, cf: CFrame, color: Color3)
	local p = part(root, { Name = name .. "Base", Size = Vector3.new(3, 2.4, 3), CFrame = cf * CFrame.new(0, 1.2, 0), Color = Color3.fromRGB(40, 50, 64), Material = Enum.Material.Metal })
	local trophy = part(root, { Name = name, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = cf * CFrame.new(0, 3.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color = color, Material = Enum.Material.Neon, Transparency = 0.85, CanCollide = false })
	trophy:SetAttribute("Trophy", name)
	light(trophy, color, 12, 0).Name = "Glow"
	return p
end

function Hub.build()
	local old = workspace:FindFirstChild("Node7")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = "Node7"
	local o = CFrame.new(ORIGIN)
	-- Shell: 64 × 48 room, a long observation window to the north (the swarm is out there).
	part(root, { Name = "Floor", Size = Vector3.new(64, 1, 48), CFrame = o * CFrame.new(0, -0.5, 0), Color = Color3.fromRGB(58, 70, 88), Material = Enum.Material.DiamondPlate })
	-- Fill lights: the base reads calm and bright against the night outside.
	for ix = -1, 1 do
		for iz = -1, 1 do
			local anchor = part(root, { Name = "FillLight", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = o * CFrame.new(ix * 20, 9, iz * 15), Transparency = 1, CanCollide = false, CastShadow = false })
			light(anchor, Color3.fromRGB(200, 225, 255), 34, 2.2)
		end
	end
	part(root, { Name = "Ceiling", Size = Vector3.new(64, 1, 48), CFrame = o * CFrame.new(0, 16, 0), Color = Color3.fromRGB(16, 20, 28), CastShadow = false })
	part(root, { Name = "WallS", Size = Vector3.new(64, 16, 1), CFrame = o * CFrame.new(0, 8, -24), Color = Color3.fromRGB(52, 62, 80) })
	part(root, { Name = "WallE", Size = Vector3.new(1, 16, 48), CFrame = o * CFrame.new(32, 8, 0), Color = Color3.fromRGB(52, 62, 80) })
	part(root, { Name = "WallW", Size = Vector3.new(1, 16, 48), CFrame = o * CFrame.new(-32, 8, 0), Color = Color3.fromRGB(52, 62, 80) })
	part(root, { Name = "WallNLow", Size = Vector3.new(64, 3, 1), CFrame = o * CFrame.new(0, 1.5, 24), Color = Color3.fromRGB(52, 62, 80) })
	part(root, { Name = "WallNHigh", Size = Vector3.new(64, 3, 1), CFrame = o * CFrame.new(0, 14.5, 24), Color = Color3.fromRGB(52, 62, 80) })
	part(root, { Name = "Window", Size = Vector3.new(64, 10, 0.4), CFrame = o * CFrame.new(0, 8, 24), Color = Color3.fromRGB(80, 160, 200), Material = Enum.Material.Glass, Transparency = 0.75 })
	-- Distant hive glow beyond the window.
	local glow = part(root, { Name = "HiveGlow", Size = Vector3.new(120, 30, 1), CFrame = o * CFrame.new(0, 6, 70), Color = Color3.fromRGB(120, 40, 160), Material = Enum.Material.Neon, Transparency = 0.6, CanCollide = false, CastShadow = false })
	light(glow, Color3.fromRGB(160, 60, 220), 60, 1.2)
	-- Light strips
	for i = -2, 2 do
		local strip = part(root, { Name = "Strip", Size = Vector3.new(0.4, 0.2, 40), CFrame = o * CFrame.new(i * 12, 15.4, 0), Color = Color3.fromRGB(84, 238, 255), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
		light(strip, Color3.fromRGB(150, 220, 255), 26, 1.1)
	end
	-- Command table (В БОЙ) in the centre, arsenal west, laboratory east.
	local table_ = part(root, { Name = "CommandTable", Size = Vector3.new(10, 2.6, 6), CFrame = o * CFrame.new(0, 1.3, 6), Color = Color3.fromRGB(36, 46, 62), Material = Enum.Material.Metal })
	local holo = part(root, { Name = "Holo", Size = Vector3.new(8, 0.2, 4.4), CFrame = o * CFrame.new(0, 2.7, 6), Color = Color3.fromRGB(84, 238, 255), Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false })
	light(holo, Color3.fromRGB(84, 238, 255), 16, 1.4)
	sign(table_, "КОМАНДНЫЙ ЗАЛ", Color3.fromRGB(84, 238, 255))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "В БОЙ"
	prompt.ObjectText = "Операции"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("Terminal", "play")
	prompt.Parent = table_
	terminal(root, "ArsenalTerminal", "АРСЕНАЛ", "arsenal", o * CFrame.new(-22, 0, 4) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 200, 60))
	terminal(root, "LabTerminal", "ЛАБОРАТОРИЯ", "lab", o * CFrame.new(22, 0, 4) * CFrame.Angles(0, math.rad(-90), 0), Color3.fromRGB(170, 255, 80))
	-- Weapon racks along the west wall (lit by ownership on the client).
	for i, wid in { "W_ARC_RIFLE", "W_SCATTERGUN", "W_PLASMA_BEAM", "W_RAILGUN" } do
		local rack = part(root, { Name = "Rack_" .. wid, Size = Vector3.new(1, 5, 3.4), CFrame = o * CFrame.new(-30.8, 3, -14 + i * 5), Color = Color3.fromRGB(44, 54, 70), Material = Enum.Material.Metal })
		local lamp = part(root, { Name = "RackLamp_" .. wid, Size = Vector3.new(0.2, 4, 2.8), CFrame = o * CFrame.new(-30.2, 3, -14 + i * 5), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Neon, Transparency = 0.9, CanCollide = false })
		lamp:SetAttribute("Weapon", wid)
		rack:SetAttribute("Weapon", wid)
	end
	-- Trophies along the east wall: Storm Core (O01 carrier), Broodmother (O04), Devourer (O06).
	pedestal(root, "TrophyStormCore", o * CFrame.new(28, 0, -10), Color3.fromRGB(140, 220, 255))
	pedestal(root, "TrophyBroodmother", o * CFrame.new(28, 0, -2), Color3.fromRGB(255, 80, 120))
	pedestal(root, "TrophyDevourer", o * CFrame.new(28, 0, 6), Color3.fromRGB(190, 120, 255))
	-- Transport pad to the south (decorative launch zone)
	local pad = part(root, { Name = "LaunchPad", Size = Vector3.new(12, 0.3, 8), CFrame = o * CFrame.new(0, 0.15, -18), Color = Color3.fromRGB(255, 140, 50), Material = Enum.Material.Neon, Transparency = 0.6, CanCollide = false })
	light(pad, Color3.fromRGB(255, 140, 50), 14, 0.8)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Enabled = false
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Size = Vector3.new(4, 1, 4)
	spawn.CFrame = CFrame.new(Hub.Spawn - Vector3.new(0, 2.7, 0))
	spawn.Parent = root
	root.Parent = workspace
	return root
end

return Hub
