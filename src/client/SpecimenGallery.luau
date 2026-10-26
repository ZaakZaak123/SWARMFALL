--!nonstrict
-- Discovered species get their own large tank. Undiscovered species do not leave a wall of locks
-- in the grove. One shared, low-poly frame; static specimens; animation is capped at ten updates/s.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Collection = require(Shared:WaitForChild("Collection"))
local Defs = require(Shared:WaitForChild("Defs"))
local Models = require(script.Parent.Models)
local Theme = require(script.Parent.Theme)
local Settings = require(script.Parent.Settings)
local Gallery = {}
Gallery.__index = Gallery

local function part(parent, name, size, cf, color, material, transparency)
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = name, true, false, false, false, false
	p.Shape, p.Size, p.CFrame = Enum.PartType.Cylinder, size, cf
	p.Color, p.Material, p.Transparency = color, material, transparency or 0
	p.Parent = parent
	return p
end

function Gallery.new(base, parent, artModel, onInspect)
	local deck = Instance.new("Part")
	deck.Name, deck.Anchored, deck.CanCollide, deck.CanQuery, deck.CanTouch, deck.CastShadow =
		"GalleryDeck", true, false, false, false, false
	deck.Size = Vector3.new(28, 0.16, 42)
	deck.CFrame = base * CFrame.new(16, 0.1 - base.Y, 24) -- DD-087: turned with the plot
	deck.Color, deck.Material, deck.Parent = Color3.fromRGB(85, 94, 76), Enum.Material.WoodPlanks, parent
	return setmetatable(
		{ base = base, parent = parent, artModel = artModel, inspect = onInspect, tanks = {}, clock = 0, deck = deck },
		Gallery
	)
end

function Gallery:makeTank(kind, index)
	local model = Instance.new("Model")
	model.Name = "Tank_" .. kind
	model.Parent = self.parent
	-- First tank remains at the lab's prepared site; the gallery grows into the clearing behind it.
	local offset = if index == 1
		then Vector3.zero
		else Vector3.new(8 + ((index - 2) % 3) * 8, 0, 8 + math.floor((index - 2) / 3) * 10)
	local base = self.base * CFrame.new(offset)
	local frame = self.artModel("SPECIMEN_FRAME", 8.34, base, model)
	local function cyl(name, h, d, y, color, mat, transparency)
		return part(
			model,
			name,
			Vector3.new(h, d, d),
			base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
			color,
			mat,
			transparency
		)
	end
	if not frame then
		cyl("Plinth", 1.2, 4.6, 0.6, Color3.fromRGB(70, 74, 80), Enum.Material.Metal)
		cyl("Cap", 0.9, 4.3, 7.4, Color3.fromRGB(70, 74, 80), Enum.Material.Metal)
	end
	local glass = cyl("Glass", 5.4, 3.8, 4.1, Color3.fromRGB(200, 236, 228), Enum.Material.Glass, 0.72)
	local liquid = cyl("Liquid", 0.3, 3.5, 1.6, Color3.fromRGB(120, 255, 170), Enum.Material.Neon, 0.8)
	local board = Theme.new("BillboardGui", {
		Name = "SpecimenLabel",
		Size = UDim2.fromOffset(180, 46),
		StudsOffsetWorldSpace = Vector3.new(0, -3.25, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 45,
		Parent = glass,
		Adornee = glass,
	})
	local title = Theme.label(
		Defs.Enemies[kind].name,
		{ Size = UDim2.new(1, 0, 0, 23), TextSize = 15, FontFace = Theme.F.head, Parent = board }
	)
	local sub = Theme.label("", {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 13,
		TextColor3 = Theme.C.lime,
		Parent = board,
	})
	for _, l in { title, sub } do
		Theme.new("UIStroke", { Color = Theme.C.ink, Thickness = 2, Parent = l })
	end
	local prompt = Theme.new("ProximityPrompt", {
		ActionText = "Коллекция",
		ObjectText = Defs.Enemies[kind].name,
		KeyboardKeyCode = Enum.KeyCode.E,
		GamepadKeyCode = Enum.KeyCode.ButtonX,
		MaxActivationDistance = 7,
		RequiresLineOfSight = false,
		Parent = glass,
	})
	prompt.Triggered:Connect(function()
		self.inspect(kind)
	end)
	local tank = {
		model = model,
		base = base,
		glass = glass,
		liquid = liquid,
		sub = sub,
		prompt = prompt,
		stage = -1,
		index = index,
	}
	self.tanks[kind] = tank
	return tank
end

function Gallery:update(research, visible)
	local index = 0
	for _, kind in Collection.Order do
		local n = Collection.count(research, kind)
		local tank = self.tanks[kind]
		if visible and n > 0 then
			index += 1
			if tank and tank.index ~= index then
				tank.model:Destroy()
				self.tanks[kind] = nil
				tank = nil
			end
			tank = tank or self:makeTank(kind, index)
			if tank.count == n then
				continue
			end
			tank.count = n
			local p = Collection.progress(kind, n)
			local height = 4.9 * p.fill
			tank.liquid.Size = Vector3.new(height, 3.5, 3.5)
			tank.liquid.CFrame = tank.base * CFrame.new(0, 1.45 + height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			tank.sub.Text = p.name .. (if p.nextNeed then " · " .. n .. "/" .. p.nextNeed else " · " .. n)
			tank.model:SetAttribute("Research", n)
			tank.model:SetAttribute("Stage", p.stage)
			if tank.stage ~= p.stage then
				tank.stage = p.stage
				if tank.content then
					tank.content:Destroy()
					tank.content = nil
				end
				tank.specimen = nil
				local content = Instance.new("Model")
				content.Name, content.Parent = "Specimen", tank.model
				tank.content = content
				if p.stage == 1 then
					for i = 1, 4 do
						local blob = part(
							content,
							"Sample",
							Vector3.one * (0.4 + i * 0.1),
							CFrame.new(
								tank.glass.Position
									+ Vector3.new(math.cos(i * 2) * 0.7, i * 0.45 - 1.2, math.sin(i * 2) * 0.7)
							),
							Theme.C.lime,
							Enum.Material.Neon,
							0.25
						)
						blob.Shape = Enum.PartType.Ball
					end
				elseif p.stage >= 2 then
					local specimen = Models.creature(Defs.Enemies[kind].index)
					for _, d in specimen:GetDescendants() do
						if d:IsA("BasePart") then
							d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow =
								true, false, false, false, false
							if p.stage == 2 then
								d.Color, d.Material = Color3.fromRGB(16, 24, 18), Enum.Material.SmoothPlastic
								if d:IsA("MeshPart") then
									d.TextureID = ""
								end
							end
						elseif
							(d:IsA("SurfaceAppearance") and p.stage == 2)
							or d:IsA("Light")
							or d:IsA("ParticleEmitter")
						then
							d:Destroy()
						end
					end
					local _, size = specimen:GetBoundingBox()
					specimen:ScaleTo(specimen:GetScale() * 3.1 / math.max(size.X, size.Y, size.Z, 0.1))
					specimen.WorldPivot = specimen:GetBoundingBox()
					specimen:PivotTo(CFrame.new(tank.glass.Position))
					specimen.Parent = content
					tank.specimen = specimen
				end
				if p.stage == 4 then
					for _, y in { 1.3, 6.8 } do
						part(
							content,
							"GoldBand",
							Vector3.new(0.2, 4, 4),
							tank.base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
							Theme.C.gold,
							Enum.Material.Metal
						)
					end
				end
				tank.liquid.Transparency = if p.stage == 2 then 0.62 else 0.8
			end
		elseif tank then
			tank.model:Destroy()
			self.tanks[kind] = nil
		end
	end
	if self.shown ~= index then
		self.shown = index
		self.deck.Transparency = if index > 1 then 0 else 1
		local cols, rows = math.min(3, math.max(1, index - 1)), math.max(1, math.ceil((index - 1) / 3))
		self.deck.Size = Vector3.new(cols * 8 + 4, 0.16, (rows - 1) * 10 + 8)
		self.deck.CFrame = self.base * CFrame.new(8 + (cols - 1) * 4, 0.1 - self.base.Y, 8 + (rows - 1) * 5)
	end
end

function Gallery:step(dt, active, root)
	self.clock += dt
	if self.clock < 0.1 then
		return
	end
	local now = os.clock()
	self.clock = 0
	for _, t in self.tanks do
		local near = not root or (root - t.glass.Position).Magnitude < 55
		t.prompt.Enabled = active and near
		if t.specimen and t.specimen.Parent and near and Settings.quality > 1 then
			t.specimen:PivotTo(
				CFrame.new(t.glass.Position + Vector3.new(0, math.sin(now * 0.6) * 0.2, 0))
					* CFrame.Angles(0, now * 0.1, 0)
			)
		end
	end
end

return Gallery
