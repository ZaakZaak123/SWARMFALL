--!nonstrict
-- The Last Grove on screen (DD-087). The own home is client/Base (full, with its stations); this draws
-- everything around it:
--   the square    the old Tree with the settlers' lanterns, the gathering fire (squads), the chronicle board
--   the signs     one by every plot's road: name, title, what they are up to, ♥, a lantern on top (lit =
--                 looking for company); its prompts join, ask to come along, open the card, light the own one
--   the neighbours  their homes as their showcases say (restored spots, lights, trophies with where they
--                 came from, the specimen tanks, the gun on its stand), static; details only up close
--   the signals   speech bubbles over the heads (fixed phrases, shared/Chronicle.Signals)
--   the chronicle a quiet line at the left when something happens in the grove
-- Everything is rebuilt only when what it shows changes (a key per plot).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Grove = require(Shared:WaitForChild("Grove"))
local Layout = require(Shared:WaitForChild("ShelterLayout"))
local Chronicle = require(Shared:WaitForChild("Chronicle"))
local Collection = require(Shared:WaitForChild("Collection"))
local Defs = require(Shared:WaitForChild("Defs"))
local Meta = require(Shared:WaitForChild("Meta"))
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local Audio = require(script.Parent.Audio)
local Fx = require(script.Parent.Fx)
local Models = require(script.Parent.Models)
local Cableway = require(script.Parent.Cableway)
local SpecimenGallery = require(script.Parent.SpecimenGallery)
local Cabin = require(script.Parent.Cabin)
local PlotDecor = require(script.Parent.PlotDecor)
local Settings = require(script.Parent.Settings)

local new, C, F = Theme.new, Theme.C, Theme.F
local label, tween = Theme.label, Theme.tween
local rgb = Color3.fromRGB

local Settlement = {}

local DETAIL_NEAR = 150 -- a neighbour's trophies, gun, tanks and crates are built inside this
local LANTERN = {
	open = rgb(198, 255, 66),
	home = rgb(255, 196, 120),
	off = rgb(60, 56, 52),
}
local STATUS_COLOR = {
	open = C.lime,
	go = C.gold,
	ready = C.gold,
	away = C.orange,
	squad = C.cyan,
	guest = C.cyan,
	square = C.text,
	idle = C.dim,
	home = C.text,
}
Settlement.StatusColor = STATUS_COLOR

local acts = {} -- card(uid, entry?), join(squadId), ask(uid), lantern(on), board(), residents(), collection(...)
local folder: Folder? = nil
local square: Folder? = nil
local myId = 0
local myPlot: number? = nil
local hub = nil -- the last camp state
local plots = {} -- i -> { kind, entry, key, home = Folder?, near = Folder?, gallery, sign = {...} }
local feedKey = nil
local visible = true
local treeLamps = {} -- { part, light } — lit by the Light of the Tree (DD-089)
local treeLine: TextLabel? = nil
local treeDecor: TextLabel? = nil -- DD-090: this week's decoration and how it is earned
local pending = {} -- chronicle lines waiting for a calm moment
local calm = false
local tell -- shows a chronicle line (defined with the chronicle below)
local applyQuality -- lights by the quality setting (defined below)

-- Helpers ------------------------------------------------------------------------------------------------
local function part(props): BasePart
	local p = new("Part", props)
	p.Anchored = true
	p.CanCollide = props.CanCollide == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = props.CastShadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function artTemplate(key: string): MeshPart?
	local f = ReplicatedStorage:FindFirstChild("ArtTemplates")
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
	m.CastShadow = Settings.quality >= 2
	m.Parent = parent
	return m
end

local function fitTo(model: Model, height: number, longest: boolean?)
	local _, size = model:GetBoundingBox()
	local k = if longest
		then height / math.max(size.X, size.Y, size.Z, 0.1)
		else height / math.max(size.Y, size.X * 0.6, size.Z * 0.6, 0.1)
	pcall(model.ScaleTo, model, model:GetScale() * k)
	local cf, sz = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(cf.X, cf.Y - sz.Y / 2, cf.Z)
end

local function statue(model: Model, gold: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = false
			if gold then
				d.Material = Enum.Material.Metal
				d.Color = rgb(232, 182, 72)
			else
				d.Material = Enum.Material.SmoothPlastic
				d.Color = rgb(150, 162, 170)
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

local function stroke(t: Instance, thick: number?)
	new("UIStroke", { Color = C.ink, Thickness = thick or 2, Transparency = 0.1, Parent = t })
end

local function billboard(parent: Instance, adornee: Instance, size: UDim2, offset: Vector3, maxDist: number)
	return new("BillboardGui", {
		Size = size,
		StudsOffsetWorldSpace = offset,
		LightInfluence = 0,
		AlwaysOnTop = true,
		MaxDistance = maxDist,
		Adornee = adornee,
		Parent = parent,
	})
end

local function prompt(parent: BasePart, key: Enum.KeyCode, pad: Enum.KeyCode, onTrigger): ProximityPrompt
	local p = new("ProximityPrompt", {
		KeyboardKeyCode = key,
		GamepadKeyCode = pad,
		HoldDuration = 0,
		MaxActivationDistance = 11,
		RequiresLineOfSight = false,
		Enabled = false,
		Parent = parent,
	})
	p.Triggered:Connect(onTrigger)
	return p
end

local function myRoot(): BasePart?
	local char = Players.LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The square ---------------------------------------------------------------------------------------------
local fireLight: PointLight? = nil
local boardGui: SurfaceGui? = nil
local squarePrompts = {}

local function buildTree(parent: Instance)
	local c = Grove.Center
	local holder = new("Model", { Name = "OldTree", Parent = parent })
	local oak = artModel("OAK", 58, CFrame.new(c) * CFrame.Angles(0, 0.7, 0), holder)
	if oak then
		oak.CanCollide = true
		oak.CastShadow = true
	else
		-- a plain giant: trunk and crowns
		part({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(30, 9, 9),
			CFrame = CFrame.new(c + Vector3.new(0, 15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(96, 70, 48),
			Material = Enum.Material.Wood,
			CanCollide = true,
			CastShadow = true,
			Parent = holder,
		})
		local rng = Random.new(7)
		for i = 1, 9 do
			local a = i / 9 * math.pi * 2
			local r = if i == 9 then 0 else rng:NextNumber(9, 15)
			part({
				Name = "Crown",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * rng:NextNumber(18, 26),
				CFrame = CFrame.new(c + Vector3.new(math.cos(a) * r, rng:NextNumber(32, 42), math.sin(a) * r)),
				Color = rgb(86, 140, 60):Lerp(rgb(120, 168, 70), rng:NextNumber()),
				Material = Enum.Material.Grass,
				CastShadow = true,
				Parent = holder,
			})
		end
	end
	-- roots over the paving
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2 + 0.3
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		part({
			Name = "Root",
			Size = Vector3.new(2.6, 1.6, 12),
			CFrame = CFrame.lookAt(c + dir * 8 + Vector3.new(0, 0.3, 0), c + dir * 20 + Vector3.new(0, -1.5, 0)),
			Color = rgb(92, 68, 46),
			Material = Enum.Material.Wood,
			CanCollide = true,
			Parent = holder,
		})
	end
	-- the settlers' lanterns hang from the lowest branches, one ring of warm light
	local rng = Random.new(11)
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local r = rng:NextNumber(11, 19)
		local top = c + Vector3.new(math.cos(a) * r, rng:NextNumber(24, 30), math.sin(a) * r)
		local hang = rng:NextNumber(3, 6)
		part({
			Name = "String",
			Size = Vector3.new(0.08, hang, 0.08),
			CFrame = CFrame.new(top - Vector3.new(0, hang / 2, 0)),
			Color = rgb(40, 34, 30),
			Material = Enum.Material.SmoothPlastic,
			Parent = holder,
		})
		local lamp = part({
			Name = "Lantern",
			Size = Vector3.new(0.9, 1.2, 0.9),
			CFrame = CFrame.new(top - Vector3.new(0, hang + 0.6, 0)) * CFrame.Angles(0, a, 0),
			Color = rgb(255, 190, 110),
			Material = Enum.Material.Neon,
			Parent = holder,
		})
		local light = nil
		if i % 3 == 0 then
			light = new(
				"PointLight",
				{ Color = rgb(255, 186, 120), Range = 16, Brightness = 0.9, Shadows = false, Parent = lamp }
			)
		end
		table.insert(treeLamps, { part = lamp, light = light })
	end
	local plaque =
		part({ Name = "TreeSign", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(c), Parent = holder })
	local b = billboard(plaque, plaque, UDim2.fromOffset(320, 56), Vector3.new(0, 11, 0), 220)
	local t = label("ПОСЛЕДНЯЯ РОЩА", {
		Size = UDim2.new(1, 0, 0, 30),
		FontFace = F.display,
		TextSize = 26,
		TextColor3 = rgb(226, 214, 190),
		Parent = b,
	})
	stroke(t, 2.5)
	treeLine = label("Старое древо: споры к нему не садятся", {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = F.bodyBold,
		TextSize = 14,
		TextColor3 = C.dim,
		Parent = b,
	})
	stroke(treeLine)
	treeDecor = label("", {
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, 18),
		FontFace = F.bodyBold,
		TextSize = 13,
		TextColor3 = C.gold,
		Parent = b,
	})
	stroke(treeDecor)
	b.Size = UDim2.fromOffset(460, 74)
end

-- The Light of the Tree (DD-089): the settlers' lanterns light up with every grove's wins this week.
local lightKey = nil
local function setTreeLight(light)
	if not light then
		return
	end
	local key = light.tier .. ":" .. light.wins
	if key == lightKey then
		return
	end
	lightKey = key
	local lit = 4 + math.floor(light.tier * 12 / #Meta.TreeTiers + 0.5)
	for k, l in treeLamps do
		local on = k <= lit
		l.part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		l.part.Color = if on then rgb(255, 190, 110) else rgb(80, 70, 58)
		if l.light then
			l.light.Enabled = on and Settings.quality > 1
		end
	end
	if treeLine then
		treeLine.Text = if light.need
			then string.format(
				"Свет Древа %d/%d · побед всех рощ за неделю: %d из %d%s",
				light.tier,
				#Meta.TreeTiers,
				light.wins,
				light.need,
				if light.tier > 0
					then string.format(" · +%d%% ксенита всем", math.floor(light.bonus * 100 + 0.5))
					else ""
			)
			else string.format(
				"Древо горит во всю силу · +%d%% ксенита всем до понедельника",
				math.floor(light.bonus * 100 + 0.5)
			)
		treeLine.TextColor3 = if light.tier > 0 then rgb(255, 214, 140) else C.dim
	end
	if treeDecor then
		local def = Meta.decorOfWeek(light.week or Meta.weekIndex(os.time()))
		treeDecor.Text = if light.tier >= Meta.DecorTier
			then string.format(
				"Украшение недели «%s» — за любую победу до понедельника",
				def.name
			)
			else string.format(
				"Украшение недели «%s» — когда Древо загорится на %d/5",
				def.name,
				Meta.DecorTier
			)
	end
end

local function buildFire(parent: Instance)
	local at = Grove.Fire
	local holder = new("Model", { Name = "GatheringFire", Parent = parent })
	for i = 1, 9 do
		local a = i / 9 * math.pi * 2
		part({
			Name = "Stone",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.4,
			CFrame = CFrame.new(at + Vector3.new(math.cos(a) * 2.6, 0.35, math.sin(a) * 2.6)),
			Color = rgb(110, 104, 98),
			Material = Enum.Material.Slate,
			Parent = holder,
		})
	end
	for i = 1, 3 do
		part({
			Name = "Log",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3.6, 0.6, 0.6),
			CFrame = CFrame.new(at + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, i / 3 * math.pi, math.rad(12)),
			Color = rgb(80, 56, 36),
			Material = Enum.Material.Wood,
			Parent = holder,
		})
	end
	local core = part({
		Name = "Embers",
		Size = Vector3.new(1.6, 0.4, 1.6),
		CFrame = CFrame.new(at + Vector3.new(0, 0.6, 0)),
		Color = rgb(255, 120, 40),
		Material = Enum.Material.Neon,
		Parent = holder,
	})
	new("Fire", { Size = 5, Heat = 9, Color = rgb(255, 140, 50), SecondaryColor = rgb(255, 60, 20), Parent = core })
	fireLight =
		new("PointLight", { Color = rgb(255, 150, 70), Range = 24, Brightness = 2, Shadows = false, Parent = core })
	-- log benches round it: a place to sit down and wait for company
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local p = at + Vector3.new(math.cos(a) * 7, 0.7, math.sin(a) * 7)
		part({
			Name = "Bench",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(5, 1.3, 1.3),
			CFrame = CFrame.lookAt(p, at + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, math.pi / 2, 0),
			Color = rgb(112, 80, 52),
			Material = Enum.Material.Wood,
			CanCollide = true,
			Parent = holder,
		})
	end
	local b = billboard(core, core, UDim2.fromOffset(280, 60), Vector3.new(0, 7.5, 0), 140)
	local d = Icons.disc("users", 44, C.orange, 2)
	d.AnchorPoint = Vector2.new(0, 0.5)
	d.Position = UDim2.new(0, 0, 0.5, 0)
	d.Parent = b
	local t = label("КОСТЁР СБОРА", {
		Position = UDim2.fromOffset(54, 6),
		Size = UDim2.new(1, -54, 0, 26),
		FontFace = F.display,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = b,
	})
	stroke(t, 2.5)
	local s = label("Встань у огня — тебя увидят как «ищу напарника»", {
		Position = UDim2.fromOffset(54, 32),
		Size = UDim2.new(1, -54, 0, 18),
		FontFace = F.bodyBold,
		TextSize = 12,
		TextColor3 = C.orange:Lerp(C.white, 0.4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = b,
	})
	stroke(s)
	local p = prompt(core, Enum.KeyCode.E, Enum.KeyCode.ButtonX, function()
		if acts.board then
			acts.board()
		end
	end)
	p.ActionText = "Отряды у костра"
	p.ObjectText = "Найти напарников"
	p.MaxActivationDistance = 14
	table.insert(squarePrompts, p)
end

local function buildBoard(parent: Instance)
	local at = Grove.Board
	local holder = new("Model", { Name = "Chronicle", Parent = parent })
	-- its front looks away from the Tree, at the roads people come in by
	local face = CFrame.lookAt(at, Vector3.new(Grove.Center.X, 0, Grove.Center.Z)) * CFrame.Angles(0, math.pi, 0)
	for _, x in { -4.6, 4.6 } do
		part({
			Name = "Post",
			Size = Vector3.new(0.6, 8, 0.6),
			CFrame = face * CFrame.new(x, 4, 0),
			Color = rgb(96, 70, 48),
			Material = Enum.Material.Wood,
			CanCollide = true,
			Parent = holder,
		})
	end
	local plank = part({
		Name = "Plank",
		Size = Vector3.new(9.6, 5.2, 0.4),
		CFrame = face * CFrame.new(0, 4.8, 0),
		Color = rgb(132, 98, 64),
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
		Parent = holder,
	})
	part({
		Name = "Roof",
		Size = Vector3.new(10.6, 0.4, 1.6),
		CFrame = face * CFrame.new(0, 7.7, 0) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = rgb(80, 58, 40),
		Material = Enum.Material.Wood,
		Parent = holder,
	})
	boardGui = new("SurfaceGui", {
		Face = Enum.NormalId.Front,
		CanvasSize = Vector2.new(480, 260),
		LightInfluence = 0.3,
		MaxDistance = 90,
		Parent = plank,
	})
	label("ЛЕТОПИСЬ РОЩИ", {
		Size = UDim2.new(1, 0, 0, 40),
		FontFace = F.display,
		TextSize = 30,
		TextColor3 = rgb(250, 236, 200),
		Parent = boardGui,
	})
	new("Frame", {
		Name = "Lines",
		Position = UDim2.fromOffset(14, 44),
		Size = UDim2.new(1, -28, 1, -50),
		BackgroundTransparency = 1,
		Parent = boardGui,
		List = { Padding = UDim.new(0, 4) },
	})
	local p = prompt(plank, Enum.KeyCode.E, Enum.KeyCode.ButtonX, function()
		if acts.residents then
			acts.residents()
		end
	end)
	p.ActionText = "Жители рощи"
	p.ObjectText = "Летопись"
	p.MaxActivationDistance = 12
	table.insert(squarePrompts, p)
end

-- The week's board (DD-088): the three boards' top three, beside the chronicle.
local weekGui: SurfaceGui? = nil
local weekly = nil
local weekKey = nil
local WEEK_COLOR = { defense = C.orange, research = C.violet, help = C.pink }
local function buildWeekBoard(parent: Instance)
	local at = Grove.WeekBoard
	local holder = new("Model", { Name = "WeekBoard", Parent = parent })
	local face = CFrame.lookAt(at, Vector3.new(Grove.Center.X, 0, Grove.Center.Z)) * CFrame.Angles(0, math.pi, 0)
	for _, x in { -5.2, 5.2 } do
		part({
			Name = "Post",
			Size = Vector3.new(0.6, 8, 0.6),
			CFrame = face * CFrame.new(x, 4, 0),
			Color = rgb(96, 70, 48),
			Material = Enum.Material.Wood,
			CanCollide = true,
			Parent = holder,
		})
	end
	local plank = part({
		Name = "Plank",
		Size = Vector3.new(10.8, 5.4, 0.4),
		CFrame = face * CFrame.new(0, 4.9, 0),
		Color = rgb(70, 60, 54),
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
		Parent = holder,
	})
	part({
		Name = "Trim",
		Size = Vector3.new(11.2, 0.35, 0.6),
		CFrame = face * CFrame.new(0, 7.75, 0),
		Color = rgb(214, 170, 70),
		Material = Enum.Material.Metal,
		Parent = holder,
	})
	weekGui = new("SurfaceGui", {
		Face = Enum.NormalId.Front,
		CanvasSize = Vector2.new(540, 270),
		LightInfluence = 0.3,
		MaxDistance = 90,
		Parent = plank,
	})
	label("НЕДЕЛЯ РОЩИ", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 38),
		FontFace = F.display,
		TextSize = 34,
		TextColor3 = rgb(255, 222, 140),
		Parent = weekGui,
	})
	label("", {
		Name = "Left",
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = F.bodyBold,
		TextSize = 15,
		TextColor3 = rgb(220, 206, 180),
		Parent = weekGui,
	})
	new("Frame", {
		Name = "Cols",
		Position = UDim2.fromOffset(10, 62),
		Size = UDim2.new(1, -20, 1, -68),
		BackgroundTransparency = 1,
		Parent = weekGui,
		List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) },
	})
	local p = prompt(plank, Enum.KeyCode.E, Enum.KeyCode.ButtonX, function()
		if acts.weekly then
			acts.weekly()
		end
	end)
	p.ActionText = "Недельные доски"
	p.ObjectText = "Неделя рощи"
	p.MaxActivationDistance = 12
	table.insert(squarePrompts, p)
end

local function setWeekBoard(w)
	if not weekGui or not w then
		return
	end
	local key = tostring(math.floor((w.endsIn or 0) / 3600))
	for _, board in Meta.WeeklyBoards do
		for _, row in w[board] or {} do
			key ..= board .. row.uid .. ":" .. row.value
		end
	end
	if key == weekKey then
		return
	end
	weekKey = key
	local d, h = math.floor((w.endsIn or 0) / 86400), math.floor((w.endsIn or 0) % 86400 / 3600)
	weekGui.Left.Text = string.format(
		"новая неделя через %s",
		if d > 0 then d .. " д " .. h .. " ч" else math.max(1, h) .. " ч"
	)
	local cols = weekGui.Cols
	for _, c in cols:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, board in Meta.WeeklyBoards do
		local col = new("Frame", {
			Size = UDim2.new(1 / 3, -6, 1, 0),
			BackgroundColor3 = rgb(40, 34, 30),
			BackgroundTransparency = 0.3,
			Corner = 10,
			LayoutOrder = i,
			Parent = cols,
		})
		label(Meta.WeeklyNames[board], {
			Size = UDim2.new(1, 0, 0, 28),
			FontFace = F.head,
			TextSize = 18,
			TextColor3 = WEEK_COLOR[board],
			Parent = col,
		})
		local rows = w[board] or {}
		if #rows == 0 then
			label("пока никого", {
				Position = UDim2.fromOffset(0, 40),
				Size = UDim2.new(1, 0, 0, 22),
				FontFace = F.bodyBold,
				TextSize = 15,
				TextColor3 = rgb(170, 160, 150),
				Parent = col,
			})
		end
		for k = 1, math.min(3, #rows) do
			local row = rows[k]
			label(string.format("%d. %s — %d", k, row.name, row.value), {
				Position = UDim2.fromOffset(6, 34 + (k - 1) * 32),
				Size = UDim2.new(1, -12, 0, 30),
				FontFace = if k == 1 then F.bodyHeavy else F.bodyBold,
				TextSize = 20,
				TextColor3 = if row.uid == myId then C.lime else rgb(240, 228, 206),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = col,
			})
		end
	end
end

function Settlement.weekly()
	return weekly
end

local function setBoardLines(list)
	if not boardGui then
		return
	end
	local lines = boardGui:FindFirstChild("Lines")
	for _, c in lines:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	if #list == 0 then
		label("Пока тихо. Первая победа — и о тебе напишут здесь.", {
			Size = UDim2.new(1, 0, 0, 26),
			FontFace = F.bodyBold,
			TextSize = 18,
			TextColor3 = rgb(230, 214, 180),
			TextWrapped = true,
			Parent = lines,
		})
	end
	for i, e in list do
		if i > 6 then
			break
		end
		label("• " .. e.text, {
			Size = UDim2.new(1, 0, 0, 30),
			FontFace = if e.big then F.bodyHeavy else F.bodyBold,
			TextSize = 17,
			TextColor3 = if e.big then rgb(255, 226, 150) else rgb(236, 222, 196),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			LayoutOrder = i,
			Parent = lines,
		})
	end
end

-- The woods between the plots and round the edge (the plots keep only their own trees, ShelterLayout).
local function buildWoods(parent: Instance)
	local holder = new("Folder", { Name = "Woods", Parent = parent })
	local rng = Random.new(87)
	local c = Grove.Center
	local function tree(a: number, r: number)
		local kind = if rng:NextNumber() < 0.55 then "OAK" else "BIRCH"
		local h = if kind == "OAK" then rng:NextNumber(18, 26) else rng:NextNumber(14, 19)
		local at = c + Vector3.new(math.sin(a), 0, -math.cos(a)) * r
		local m = artModel(kind, h, CFrame.new(at.X, 0, at.Z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), holder)
		if m then
			m.CanCollide = true
		end
	end
	for i = 1, Grove.Plots do
		local between = ((i - 1) + 0.5) / Grove.Plots * math.pi * 2 -- the bisector behind the metro hill
		for _, r in { 214, 236, 258 } do
			tree(between + rng:NextNumber(-0.05, 0.05), r + rng:NextNumber(-6, 6))
		end
	end
	for k = 1, 40 do
		tree(k / 40 * math.pi * 2 + rng:NextNumber(-0.04, 0.04), rng:NextNumber(266, 300))
	end
end

-- Signs --------------------------------------------------------------------------------------------------
local function buildSign(i: number)
	local f = Grove.frame(i)
	local at = Grove.at(f, Layout.Sign.x, 0, Layout.Sign.z)
	local holder = new("Model", { Name = "Sign" .. i, Parent = square })
	local turn = CFrame.new(at) * f.Rotation -- its face to the road from the square (the plot's -Z)
	local post = part({
		Name = "Post",
		Size = Vector3.new(0.5, 6, 0.5),
		CFrame = turn * CFrame.new(0, 3, 0),
		Color = rgb(96, 70, 48),
		Material = Enum.Material.Wood,
		CanCollide = true,
		Parent = holder,
	})
	part({
		Name = "Board",
		Size = Vector3.new(4.4, 2.2, 0.3),
		CFrame = turn * CFrame.new(0, 4, -0.35),
		Color = rgb(140, 104, 66),
		Material = Enum.Material.WoodPlanks,
		Parent = holder,
	})
	part({
		Name = "Arm",
		Size = Vector3.new(0.3, 0.3, 1.4),
		CFrame = turn * CFrame.new(0, 6.1, -0.6),
		Color = rgb(60, 52, 46),
		Material = Enum.Material.Metal,
		Parent = holder,
	})
	local lamp = part({
		Name = "Lantern",
		Size = Vector3.new(0.8, 1.1, 0.8),
		CFrame = turn * CFrame.new(0, 5.5, -1.2),
		Color = LANTERN.off,
		Material = Enum.Material.SmoothPlastic,
		Parent = holder,
	})
	local light =
		new("PointLight", { Color = LANTERN.home, Range = 14, Brightness = 0, Shadows = false, Parent = lamp })
	local gui = billboard(post, post, UDim2.fromOffset(260, 78), Vector3.new(0, 8.6, 0), 160)
	local name = label("", {
		Size = UDim2.new(1, 0, 0, 28),
		FontFace = F.display,
		TextSize = 24,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = gui,
	})
	stroke(name, 2.5)
	local title = label("", {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 18),
		FontFace = F.head,
		TextSize = 13,
		TextColor3 = C.gold,
		Parent = gui,
	})
	stroke(title)
	local status = label("", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = F.bodyHeavy,
		TextSize = 16,
		Parent = gui,
	})
	stroke(status)
	local main = prompt(post, Enum.KeyCode.E, Enum.KeyCode.ButtonX, function()
		local pl = plots[i]
		if not pl or not pl.entry then
			return
		end
		if pl.kind == "me" then
			if acts.lantern then
				acts.lantern()
			end
		elseif pl.kind == "held" then
			if pl.entry.fightHost and acts.joinFight then
				acts.joinFight(pl.entry.fightHost)
			end
		elseif pl.kind == "online" then
			local sq = Settlement.squadOf(pl.entry.id)
			if sq and sq.open and acts.join then
				acts.join(sq.id)
			elseif acts.ask then
				acts.ask(pl.entry.id)
			end
		end
	end)
	local card = prompt(post, Enum.KeyCode.F, Enum.KeyCode.ButtonY, function()
		local pl = plots[i]
		if pl and pl.entry and acts.card then
			acts.card(pl.entry.id, if pl.kind == "online" or pl.kind == "me" then nil else pl.entry)
		end
	end)
	card.ActionText = "Карточка"
	-- DD-089: the plot's flag beside the sign (its owner's colour and emblem) and the third prompt: ♥ for
	-- a neighbour's home, the flag for the own one
	local pole = part({
		Name = "FlagPole",
		Size = Vector3.new(0.35, 11, 0.35),
		CFrame = turn * CFrame.new(-3.4, 5.5, 0),
		Color = rgb(70, 62, 56),
		Material = Enum.Material.Metal,
		Parent = holder,
	})
	local cloth = part({
		Name = "Flag",
		Size = Vector3.new(3.6, 2.4, 0.1),
		CFrame = turn * CFrame.new(-5.2, 9.6, 0),
		Color = rgb(198, 255, 66),
		Material = Enum.Material.Fabric,
		Parent = holder,
	})
	local emblems = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sg = new(
			"SurfaceGui",
			{ Face = face, CanvasSize = Vector2.new(180, 120), LightInfluence = 0.6, MaxDistance = 160, Parent = cloth }
		)
		local ic = Icons.new("pin", 84, rgb(255, 255, 255))
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.Parent = sg
		table.insert(emblems, { gui = sg, icon = ic })
	end
	local third = prompt(post, Enum.KeyCode.R, Enum.KeyCode.ButtonB, function()
		local pl = plots[i]
		if not pl or not pl.entry then
			return
		end
		if pl.kind == "me" then
			if acts.banner then
				acts.banner()
			end
		elseif acts.like then
			acts.like(pl.entry.id)
		end
	end)
	return {
		holder = holder,
		lamp = lamp,
		light = light,
		name = name,
		title = title,
		status = status,
		main = main,
		card = card,
		third = third,
		pole = pole,
		cloth = cloth,
		clothCf = cloth.CFrame,
		emblems = emblems,
	}
end

local function setFlag(sg, banner)
	local show = banner ~= nil
	sg.pole.Transparency = if show then 0 else 1
	sg.cloth.Transparency = if show then 0 else 1
	for _, em in sg.emblems do
		em.gui.Enabled = show
	end
	if not show then
		return
	end
	local c = Meta.BannerColors[banner.color or 1] or Meta.BannerColors[1]
	sg.cloth.Color = rgb(c[1], c[2], c[3])
	if sg.emblemId ~= banner.emblem then
		sg.emblemId = banner.emblem
		for _, em in sg.emblems do
			em.icon = Icons.swap(em.icon, banner.emblem or "pin", rgb(255, 255, 255))
		end
	end
end

local function setSign(i: number)
	local pl = plots[i]
	local sg = pl.sign
	local e = pl.entry
	local kind = pl.kind
	local lit = "off"
	if kind == "free" then
		sg.name.Text = "СВОБОДНЫЙ УЧАСТОК"
		sg.name.TextColor3 = C.dim
		sg.title.Text = ""
		sg.status.Text = "Здесь поселится новый житель"
		sg.status.TextColor3 = C.dim
	elseif kind == "ghost" then
		sg.name.Text = e.name
		sg.name.TextColor3 = C.text:Lerp(C.dim, 0.4)
		sg.title.Text = e.title or ""
		sg.status.Text = if e.demo
			then "Демо-сосед · для проверки в Studio"
			else "Не в сети · живёт в другой роще"
		sg.status.TextColor3 = C.dim
	elseif kind == "held" then
		sg.name.Text = e.name
		sg.name.TextColor3 = C.text
		sg.title.Text = e.title or ""
		-- DD-088: how the fight goes out there, live; a defence in a breather lights the lantern
		sg.status.Text = e.fightLine or ("В вылазке · " .. tostring(e.away or "бой"))
		sg.status.TextColor3 = if e.canJoin then C.lime else STATUS_COLOR.away
		lit = if e.canJoin then "open" else "off"
	else
		sg.name.Text = if kind == "me" then "ТВОЙ ДОМ · " .. e.name else e.name
		sg.name.TextColor3 = if kind == "me" then C.lime else C.text
		sg.title.Text = string.format("%s  ·  ♥ %d", e.title or "", e.likes or 0)
		sg.status.Text = e.status or "Дома"
		sg.status.TextColor3 = STATUS_COLOR[e.statusKey or "home"] or C.text
		lit = if e.statusKey == "open" then "open" else "home"
	end
	setFlag(sg, if e and kind ~= "free" then (e.banner or { color = 1, emblem = "pin" }) else nil)
	sg.third.Enabled = kind ~= "free"
	sg.third.ActionText = if kind == "me" then "Флаг участка" else "♥ Нравится дом"
	sg.third.ObjectText = if kind == "me" then "Цвет и эмблема" elseif e then e.name else ""
	local col = LANTERN[lit]
	sg.lamp.Color = col
	sg.lamp.Material = if lit == "off" then Enum.Material.SmoothPlastic else Enum.Material.Neon
	sg.light.Color = col
	sg.light.Brightness = if lit == "off" then 0 elseif lit == "open" then 2.2 else 1
	-- prompts
	sg.main.Enabled = false
	sg.card.Enabled = kind ~= "free" and kind ~= "held"
	if kind == "me" then
		local sq = Settlement.squadOf(myId)
		local host = sq and sq.host == myId
		sg.main.Enabled = host == true
		sg.main.ActionText = if sq and sq.open then "Погасить фонарь" else "Зажечь фонарь"
		sg.main.ObjectText = if sq and sq.open
			then "Набор открыт"
			else "Позвать соседей с собой"
		sg.card.ObjectText = "Твоя карточка"
	elseif kind == "online" then
		local sq = Settlement.squadOf(e.id)
		local mine = Settlement.squadOf(myId)
		local full = sq and #sq.players >= 4
		sg.main.Enabled = sq ~= nil and sq ~= mine and not full and not sq.launching
		sg.main.ActionText = if sq and sq.open
			then "Присоединиться"
			else "Попроситься с ним"
		sg.main.ObjectText = e.name
		sg.card.ObjectText = e.name
	elseif kind == "held" and e.canQueue and e.fightHost then
		sg.main.Enabled = true
		sg.main.ActionText = "Вступить в оборону"
		sg.main.ObjectText = if e.canJoin
			then "Передышка — успеешь к волне"
			else "Войдёшь в ближайшую передышку"
	else
		sg.card.ObjectText = e and e.name or ""
	end
end

-- Neighbours' homes --------------------------------------------------------------------------------------
local function homeKey(e): string
	local parts =
		{ e.id, e.weapon or "", tostring(e.form), e.mastery or 0, e.siege or 0, e.stock or 0, tostring(e.decor) }
	for _, id in Meta.HomeOrder do
		table.insert(parts, if e.home and e.home[id] then "1" else "0")
	end
	for _, t in Layout.Trophies do
		table.insert(parts, if e.won and e.won[t.op] then "1" else "0")
	end
	for _, kind in Collection.Order do
		table.insert(parts, Collection.progress(kind, Collection.count(e.collection, kind)).stage)
	end
	return table.concat(parts, "|")
end

local function buildHome(i: number, e)
	local f = Grove.frame(i)
	local function WC(x: number, y: number, z: number, yaw: number?): CFrame
		return f * CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0)
	end
	local home = new("Folder", { Name = "Home" .. i })
	local powered = e.home and e.home.GENERATOR == true
	for _, d in Layout.Decor do
		local m = artModel(d[1], d[2], WC(d[3], 0, d[4], d[5]), home)
		if m then
			m.CanCollide = d[1] ~= "BUSH"
		end
	end
	for _, s in Layout.Stations do
		local yaw = math.clamp(-s.x / 60, -0.35, 0.35)
		artModel(s.art, s.h, WC(s.x, 0.25, s.z + 1.6, yaw), home)
	end
	for _, xz in Layout.Lamps do
		local toward = -Vector3.new(xz[1], 0, xz[2])
		local yaw = math.atan2(-toward.X, -toward.Z)
		local m = artModel("FLOODLIGHT", 11, WC(xz[1], 0, xz[2], yaw + math.pi), home)
		if m and powered then
			local head = part({
				Name = "LampHead",
				Size = Vector3.one * 0.4,
				Transparency = 1,
				CFrame = WC(xz[1], 10.4, xz[2], yaw) * CFrame.Angles(math.rad(-35), 0, 0),
				Parent = home,
			})
			new("SpotLight", {
				Face = Enum.NormalId.Front,
				Angle = 75,
				Range = 34,
				Brightness = 1.8,
				Color = rgb(255, 236, 200),
				Shadows = false,
				Parent = head,
			})
		end
	end
	local gallery = nil
	for _, id in Meta.HomeOrder do
		local sd = Layout.Spots[id]
		local base = WC(sd.x, 0.25, sd.z + 0.8, sd.yaw)
		if e.home and e.home[id] then
			if id ~= "LAB" then
				local m = artModel(sd.art, sd.h, base, home)
				if m then
					m.CanCollide = true
				end
			end
			if powered then
				local glow = part({
					Name = "Glow",
					Size = Vector3.one * 0.3,
					Transparency = 1,
					CFrame = WC(sd.x, 2, sd.z),
					Parent = home,
				})
				new(
					"PointLight",
					{ Color = rgb(255, 214, 160), Range = 12, Brightness = 1, Shadows = false, Parent = glow }
				)
			end
		else
			artModel("RUBBLE", 1.9, base, home)
		end
	end
	-- DD-090: the seasonal decoration they put up
	PlotDecor.build(e.decor, f, home)
	-- the cableway terminal and the cave its cable comes out of
	local t = Layout.Terminal
	local metal = rgb(84, 78, 70)
	for _, sz in { -1, 1 } do
		part({
			Size = Vector3.new(0.6, 8.8, 0.6),
			CFrame = WC(t.x, 4.4, t.z + sz * 2.8),
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = home,
		})
	end
	part({
		Size = Vector3.new(0.8, 0.6, 6.8),
		CFrame = WC(t.x, 8.9, t.z),
		Color = metal,
		Material = Enum.Material.Metal,
		Parent = home,
	})
	local cave = Layout.Cave
	local mouth, facing = Cableway.mouthB(f)
	Cableway.cave(home, mouth, facing)
	Cableway.new(home, { Vector3.new(mouth.X, Cableway.CABLE_H, mouth.Z), Grove.at(f, t.x, 8.4, t.z) }, {})
	local _ = cave
	-- up close: the showcase, the lab's tanks, the crates
	local near = new("Folder", { Name = "Near" })
	-- DD-093: the neighbour's cabin, its small things only near (you can walk in and sit down)
	local cabin = Cabin.build(WC(Layout.Cabin.x, 0, Layout.Cabin.z), home, { detail = near })
	cabin:setPower(powered)
	cabin:setEntry(e)
	local function pedestal(x: number, lit: boolean, color: Color3)
		local p = artModel("PLINTH", 1.3, WC(x, 0, Layout.ShowZ), near)
		if p then
			p.Size = Vector3.new(5.6, p.Size.Y, 5.6)
			p.CFrame = WC(x, p.Size.Y / 2, Layout.ShowZ)
		else
			p = part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.2, 5.6, 5.6),
				CFrame = WC(x, 0.6, Layout.ShowZ) * CFrame.Angles(0, 0, math.rad(90)),
				Color = rgb(34, 28, 48),
				Material = Enum.Material.Slate,
				Parent = near,
			})
		end
		if lit then
			new("PointLight", { Color = color, Range = 9, Brightness = 1.2, Shadows = false, Parent = p })
		end
		return p
	end
	local function plaque(anchor: BasePart, title: string, sub: string, color: Color3)
		local a = new("Attachment", { Parent = anchor })
		a.WorldCFrame = CFrame.new(anchor.Position + Vector3.new(0, 7, 0))
		local b = billboard(anchor, a, UDim2.fromOffset(230, 42), Vector3.zero, 70)
		local tl = label(
			title,
			{ Size = UDim2.new(1, 0, 0, 22), FontFace = F.display, TextSize = 17, TextColor3 = color, Parent = b }
		)
		stroke(tl)
		local sl = label(sub, {
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 16),
			FontFace = F.bodyBold,
			TextSize = 12,
			TextColor3 = C.dim,
			Parent = b,
		})
		stroke(sl, 1.5)
	end
	local wdef = Defs.Weapons[e.weapon or ""]
	if wdef then
		local evo = e.form and Defs.Evolutions[e.form]
		local base = pedestal(-2, true, C.cyan)
		local ok, gun = pcall(Models.weapon, e.weapon, evo ~= nil, true)
		if ok and gun then
			for _, d in gun:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
				end
			end
			fitTo(gun, 5, true)
			gun:PivotTo(WC(-2, 2.2, Layout.ShowZ, 0.6))
			gun.Parent = near
		end
		plaque(
			base,
			if evo then evo.name else wdef.name,
			string.format("Любимое оружие · M%d", e.mastery or 1),
			C.cyan
		)
	end
	local now = os.time()
	for k, tdef in Layout.Trophies do
		local x = Layout.trophyX(k)
		local won = e.won and e.won[tdef.op]
		local base = pedestal(x, won == true, C.gold)
		local ok, m = pcall(Models.creature, tdef.kind)
		if ok and m then
			statue(m, won == true)
			fitTo(m, if tdef.kind == 10 then 5 else 6, tdef.kind == 9)
			m:PivotTo(WC(x, 1.3, Layout.ShowZ, math.pi + k * 0.3))
			m.Parent = near
		end
		plaque(
			base,
			tdef.name,
			if won
				then Chronicle.provenance((e.trophyLog or {})[tdef.op], now)
				else tdef.hunt .. " · ещё впереди",
			if won then C.gold else C.dim
		)
	end
	if (e.siege or 0) > 0 then
		local base = pedestal(Layout.SiegeX, true, C.orange)
		plaque(
			base,
			"ОБОРОНА " .. e.siege,
			"Лучший удержанный уровень бура",
			C.orange
		)
	end
	if e.home and e.home.LAB then
		local sd = Layout.Spots.LAB
		local labModel = new("Model", { Name = "Laboratory", Parent = near })
		gallery = SpecimenGallery.new(WC(sd.x, 0.25, sd.z + 0.8, sd.yaw), labModel, artModel, function(kind)
			if acts.collection then
				acts.collection(e.collection or {}, e.name, kind, false)
			end
		end)
		gallery:update(e.collection or { EN_SPITTER = e.sample or 0 }, true)
	end
	local n = if (e.stock or 0) <= 0
		then 0
		elseif e.stock < 300 then 1
		elseif e.stock < 1000 then 2
		elseif e.stock < 3000 then 3
		else 4
	for k, o in { { 3.6, 2.6, 0.3, 2 }, { 3.4, -2.4, -0.4, 3 }, { 6.4, 0.4, 1.1, 2 }, { 6.6, 4.2, 2.2, 1 } } do
		if k > n then
			break
		end
		local base = WC(t.x + o[1], 0.5, t.z + o[2], o[3])
		for h = 0, o[4] - 1 do
			Cableway.crate(near, base * CFrame.new(0, h * 1.95, 0) * CFrame.Angles(0, h * 0.35, 0))
		end
	end
	return home, near, gallery, cabin
end

local function clearHome(pl)
	if pl.home then
		pl.home:Destroy()
	end
	if pl.near then
		pl.near:Destroy()
	end
	pl.home, pl.near, pl.gallery, pl.homeKey, pl.cabin = nil, nil, nil, nil, nil
end

-- State --------------------------------------------------------------------------------------------------
local function ensureBuilt()
	if folder then
		return
	end
	folder = new("Folder", { Name = "Grove", Parent = workspace })
	square = new("Folder", { Name = "Square", Parent = folder })
	buildTree(square)
	buildWoods(square)
	buildFire(square)
	buildBoard(square)
	buildWeekBoard(square)
	for i = 1, Grove.Plots do
		plots[i] = { kind = "free", entry = nil, sign = buildSign(i) }
	end
end

function Settlement.init(actions)
	acts = actions
	task.spawn(function()
		-- the square's meshes come with the art templates
		local f = ReplicatedStorage:WaitForChild("ArtTemplates", 30)
		local t0 = os.clock()
		while f and not f:GetAttribute("Ready") and os.clock() - t0 < 30 do
			task.wait(0.5)
		end
		if folder then
			folder:Destroy()
			folder = nil
			for _, pl in plots do
				clearHome(pl)
			end
			table.clear(squarePrompts)
			feedKey, weekKey, lightKey = nil, nil, nil
			table.clear(treeLamps)
		end
		ensureBuilt()
		if hub then
			Settlement.setHub(hub, myId)
		end
	end)
end

function Settlement.squadOf(uid: number)
	for _, sq in (hub and hub.squads) or {} do
		for _, p in sq.players do
			if p.id == uid then
				return sq
			end
		end
	end
	return nil
end

function Settlement.myPlot(): number?
	return myPlot
end

-- The plot a survivor (online, out on a fight, or from another grove) stands on.
function Settlement.plotOf(uid: number): number?
	for i, pl in plots do
		if pl.entry and pl.entry.id == uid then
			return i
		end
	end
	return nil
end

function Settlement.entry(uid: number)
	local i = Settlement.plotOf(uid)
	return i and plots[i].entry
end

-- info: the camp state (squads, hunters with plot and status, grove = { ghosts, held, feed }).
function Settlement.setHub(info, id: number)
	hub = info
	myId = id
	ensureBuilt()
	myPlot = nil
	local want = {}
	for _, h in info.hunters or {} do
		if h.plot then
			want[h.plot] = { kind = if h.id == id then "me" else "online", entry = h }
			if h.id == id then
				myPlot = h.plot
			end
		end
	end
	local grove = info.grove or {}
	for k, e in grove.held or {} do
		local i = tonumber(k)
		if i and not want[i] then
			want[i] = { kind = "held", entry = e }
		end
	end
	for k, e in grove.ghosts or {} do
		local i = tonumber(k)
		if i and not want[i] then
			want[i] = { kind = "ghost", entry = e }
		end
	end
	for i = 1, Grove.Plots do
		local pl = plots[i]
		local w = want[i] or { kind = "free" }
		pl.kind, pl.entry = w.kind, w.entry
		-- the home: the own one is client/Base; a free plot stays a clearing
		local key = if w.entry and w.kind ~= "me" then homeKey(w.entry) else nil
		if key ~= pl.homeKey then
			clearHome(pl)
			if key then
				pl.home, pl.near, pl.gallery, pl.cabin = buildHome(i, w.entry)
				pl.homeKey = key
				pl.home.Parent = folder
				if Settings.quality <= 1 then
					applyQuality()
				end
			end
		end
		setSign(i)
	end
	if grove.weekly then
		weekly = grove.weekly
		setWeekBoard(weekly)
	end
	setTreeLight(grove.light)
	local fk = ""
	for _, e in grove.feed or {} do
		fk ..= e.t .. e.text
	end
	if fk ~= feedKey then
		feedKey = fk
		setBoardLines(grove.feed or {})
	end
end

-- A session server (live) has no grove state: what the grove looked like at launch (teleport data).
function Settlement.setSnapshot(plotsByUid, groveList, id: number)
	local hunters = {}
	for k, e in groveList or {} do
		local i = tonumber(k)
		if i and type(e) == "table" then
			local c = table.clone(e)
			c.plot = i
			table.insert(hunters, c)
		end
	end
	local mine = plotsByUid and tonumber(plotsByUid[tostring(id)])
	if mine then
		table.insert(hunters, { id = id, name = Players.LocalPlayer.DisplayName, plot = mine, title = "", likes = 0 })
	end
	Settlement.setHub({ squads = {}, hunters = hunters, grove = {} }, id)
end

-- Quality (as client/Base): low drops the neighbours' decorative lights; the fire and the lanterns stay.
function applyQuality()
	if not folder then
		return
	end
	local low = Settings.quality <= 1
	for _, d in folder:GetDescendants() do
		if d:IsA("Light") and d.Parent and d.Parent.Name ~= "Embers" and d.Parent.Name ~= "Lantern" then
			d.Enabled = not low
		end
	end
end
Settings.onChanged(function(key)
	if key == "quality" then
		applyQuality()
	end
end)

function Settlement.setVisible(on: boolean)
	if visible == on or not folder then
		return
	end
	visible = on
	folder.Parent = if on then workspace else nil
end

-- The first walk through the grove (DD-089): one quiet hint at a time, each once, when the hero comes
-- to the thing it is about. Marked done on the server (profile tut) so it never repeats.
local COACH = {
	{
		key = "groveSign",
		icon = "pin",
		title = "ТВОЯ ТАБЛИЧКА",
		text = "Зажги фонарь (E) — соседи увидят, что ты ищешь напарника. R — флаг участка.",
	},
	{
		key = "groveNeighbor",
		icon = "eye",
		title = "ДОМ СОСЕДА",
		text = "У постаментов написано, как добыты трофеи. У таблички: F — карточка, R — ♥ дому.",
	},
	{
		key = "groveSignal",
		icon = "users",
		title = "РЯДОМ ЖИТЕЛЬ",
		text = "Нажми G и скажи «Привет!» — без чата. А у его таблички можно попроситься с ним.",
	},
	{
		key = "groveFire",
		icon = "users",
		title = "КОСТЁР СБОРА",
		text = "Встань у огня — фонарь у твоей таблички загорится, и тебя позовут с собой.",
	},
}
local profile = nil -- the own public profile (for the hints' tut flags)
local coachGui = nil
local coachOn = nil -- { key, until }
local coachDone = {} -- keys shown this session (the server flag may lag)

function Settlement.setProfile(pub)
	profile = pub
end

local function coachPanel()
	if coachGui then
		return coachGui
	end
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local g = new(
		"ScreenGui",
		{ Name = "GroveCoach", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 12, Parent = pg }
	)
	local panel = Theme.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(560, 74),
		CornerRadius = 22,
		Visible = false,
		Parent = g,
	}, C.lime)
	local d = Icons.disc("pin", 46, C.lime, 2)
	d.Name = "Disc"
	d.AnchorPoint = Vector2.new(0, 0.5)
	d.Position = UDim2.new(0, 14, 0.5, 0)
	d.Parent = panel
	label("", {
		Name = "Title",
		Position = UDim2.fromOffset(72, 10),
		Size = UDim2.new(1, -86, 0, 22),
		FontFace = F.display,
		TextSize = 19,
		TextColor3 = C.lime,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	label("", {
		Name = "Text",
		Position = UDim2.fromOffset(72, 32),
		Size = UDim2.new(1, -86, 0, 36),
		FontFace = F.bodyBold,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = panel,
	})
	coachGui = g
	return g
end

local function showCoach(c)
	local g = coachPanel()
	local panel = g.Panel
	panel.Title.Text = c.title
	panel.Text.Text = c.text
	local old = panel:FindFirstChild("Disc")
	if old then
		old:Destroy()
	end
	local d = Icons.disc(c.icon, 46, C.lime, 2)
	d.Name = "Disc"
	d.AnchorPoint = Vector2.new(0, 0.5)
	d.Position = UDim2.new(0, 14, 0.5, 0)
	d.Parent = panel
	panel.Visible = true
	panel.Position = UDim2.new(0.5, 0, 0, -6)
	tween(panel, 0.35, { Position = UDim2.new(0.5, 0, 0, 14) }, Enum.EasingStyle.Back)
	Audio.play("ui", 0.5, 1.3)
	coachOn = { key = c.key, untilT = os.clock() + 9 }
	coachDone[c.key] = true
	if acts.tut then
		acts.tut(c.key)
	end
end

local function coach(pos: Vector3?)
	if coachOn then
		if os.clock() > coachOn.untilT then
			coachOn = nil
			if coachGui then
				coachGui.Panel.Visible = false
			end
		end
		return
	end
	local tut = profile and profile.tut or {}
	if not pos or not profile or ((profile.winsByOp or {}).O01 or 0) == 0 then
		return -- the first sortie and its scenes come first
	end
	local function due(key: string): boolean
		return not tut[key] and not coachDone[key]
	end
	local function near(at: Vector3, r: number): boolean
		return Vector3.new(at.X - pos.X, 0, at.Z - pos.Z).Magnitude < r
	end
	if due("groveSign") and myPlot then
		local f = Grove.frame(myPlot)
		if near(Grove.at(f, Layout.Sign.x, 0, Layout.Sign.z), 26) then
			return showCoach(COACH[1])
		end
	end
	if due("groveNeighbor") then
		for i, pl in plots do
			if pl.entry and pl.kind ~= "me" and pl.kind ~= "free" and near(Grove.frame(i).Position, 70) then
				return showCoach(COACH[2])
			end
		end
	end
	if due("groveSignal") then
		for _, other in Players:GetPlayers() do
			local r = other ~= Players.LocalPlayer
				and other.Character
				and other.Character:FindFirstChild("HumanoidRootPart")
			if r and near(r.Position, 35) then
				return showCoach(COACH[3])
			end
		end
	end
	if due("groveFire") and near(Grove.Fire, 30) then
		return showCoach(COACH[4])
	end
end

-- «Пока тебя не было» (DD-089): what other survivors left at the home while its owner was away.
local bookQueue = {}
function Settlement.guestbook(data)
	table.insert(bookQueue, data)
end

local function showBook(data)
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local g = new(
		"ScreenGui",
		{ Name = "GroveGuestbook", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, Parent = pg }
	)
	local panel = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(480, 230),
		CornerRadius = 26,
		Parent = g,
	}, C.pink)
	new("UIScale", { Scale = 0.6, Parent = panel })
	label("ПОКА ТЕБЯ НЕ БЫЛО", {
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 32),
		FontFace = F.display,
		TextSize = 28,
		Parent = panel,
	})
	local lines = {}
	if (data.likes or 0) > 0 then
		table.insert(
			lines,
			string.format("♥ %d — твоему дому от жителей других рощ", data.likes)
		)
	end
	if (data.visits or 0) > 0 then
		table.insert(lines, string.format("Твой дом осмотрели %d раз", data.visits))
	end
	if type(data.names) == "table" and #data.names > 0 then
		table.insert(lines, "Заходили: " .. table.concat(data.names, ", ", 1, math.min(#data.names, 6)))
	end
	label(table.concat(lines, string.char(10)), {
		Position = UDim2.fromOffset(28, 62),
		Size = UDim2.new(1, -56, 0, 90),
		FontFace = F.bodyBold,
		TextSize = 17,
		TextWrapped = true,
		Parent = panel,
	})
	local ok, okLabel = Theme.button("ОТЛИЧНО", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(200, 50),
		TextSize = 16,
	}, "primary")
	ok.Parent = panel
	local _ = okLabel
	ok.Activated:Connect(function()
		g:Destroy()
	end)
	tween(panel:FindFirstChildOfClass("UIScale"), 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	Audio.play("orb", 0.8, 1.15)
	task.delay(14, function()
		if g.Parent then
			g:Destroy()
		end
	end)
end

-- Per frame: details near the hero, prompts only while walking the grove, the fire flickers.
function Settlement.update(dt: number, active: boolean)
	calm = active
	if active and #pending > 0 then
		local e = table.remove(pending, 1)
		task.delay(0.8, tell, e)
	end
	if active and #bookQueue > 0 then
		showBook(table.remove(bookQueue, 1))
	end
	if active then
		local r = myRoot()
		coach(r and r.Position)
	elseif coachGui and coachOn then
		coachOn = nil
		coachGui.Panel.Visible = false
	end
	if not folder or not visible then
		return
	end
	local root = myRoot()
	local pos = root and root.Position
	for _, p in squarePrompts do
		p.Enabled = active
	end
	for i, pl in plots do
		local sg = pl.sign
		if sg then
			if not active then
				sg.main.Enabled = false
				sg.card.Enabled = false
			elseif pl.kind ~= "free" and pl.kind ~= "held" then
				sg.card.Enabled = true
			end
			sg.third.Enabled = active and pl.kind ~= "free"
			if sg.cloth.Transparency < 1 then
				local t = os.clock() + i * 0.7
				sg.cloth.CFrame = sg.clothCf * CFrame.Angles(0, math.sin(t * 1.6) * 0.12, math.sin(t * 2.3) * 0.03)
			end
			if not active then
				sg.main.Enabled = false
			elseif pl.kind == "held" then
				sg.main.Enabled = pl.entry ~= nil and pl.entry.canQueue == true and pl.entry.fightHost ~= nil
			end
		end
		if pl.near and pos then
			local c = Grove.frame(i).Position
			local close = Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude < DETAIL_NEAR
			local want = if close then pl.home else nil
			if pl.near.Parent ~= want then
				pl.near.Parent = want
			end
			if close and pl.gallery then
				pl.gallery:step(dt, false, pos)
			end
			if close and pl.cabin then
				pl.cabin:step(dt, pos)
			end
		end
	end
	if fireLight then
		local t = os.clock()
		fireLight.Brightness = 1.7 + math.sin(t * 9) * 0.25 + math.sin(t * 23) * 0.15
	end
	local _ = dt
end

-- Signals ------------------------------------------------------------------------------------------------
local WAVE = { R15 = "rbxassetid://507770239", R6 = "rbxassetid://128777973" }
local bubbles = {} -- uid -> gui
function Settlement.say(uid: number, i: number)
	local sig = Chronicle.Signals[i]
	local pl = Players:GetPlayerByUserId(uid)
	local char = pl and pl.Character
	local head = char and char:FindFirstChild("Head")
	if not sig or not head then
		return
	end
	if bubbles[uid] then
		bubbles[uid]:Destroy()
	end
	local g = new("BillboardGui", {
		Name = "SignalBubble",
		Size = UDim2.fromOffset(240, 46),
		StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0),
		LightInfluence = 0,
		AlwaysOnTop = true,
		MaxDistance = 140,
		Adornee = head,
		Parent = head,
	})
	bubbles[uid] = g
	local plate = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = rgb(250, 246, 236),
		Corner = UDim.new(1, 0),
		Parent = g,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		},
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 14), Parent = plate })
	new("UIScale", { Scale = 0.4, Parent = plate })
	local ic = Icons.new(sig.icon, 22, C.ink)
	ic.Parent = plate
	label(sig.text, {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = F.bodyHeavy,
		TextSize = 19,
		TextColor3 = C.ink,
		Parent = plate,
	})
	tween(plate:FindFirstChildOfClass("UIScale"), 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	Audio.play("ui", 0.4, if uid == myId then 1.25 else 1.4)
	if sig.wave and uid == myId then
		local hum = char:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			local a = Instance.new("Animation")
			a.AnimationId = if hum.RigType == Enum.HumanoidRigType.R15 then WAVE.R15 else WAVE.R6
			local ok, track = pcall(animator.LoadAnimation, animator, a)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				track:Play(0.15)
			end
		end
	end
	task.delay(4, function()
		if bubbles[uid] == g then
			bubbles[uid] = nil
			g:Destroy()
		end
	end)
end

-- The chronicle line at the left (DD-087 §9): quiet, a few at a time; held back while a scene or a
-- fight is on screen and told once the hero walks the grove again.
local ticker = nil
function tell(e)
	if not ticker then
		local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local g = new(
			"ScreenGui",
			{ Name = "GroveChronicle", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9, Parent = pg }
		)
		ticker = new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 24, 1, -200),
			Size = UDim2.fromOffset(420, 200),
			BackgroundTransparency = 1,
			Parent = g,
			List = { VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6) },
		})
	end
	local row = Theme.panel(
		{ Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, CornerRadius = 20, Parent = ticker },
		if e.big then C.gold else C.line
	)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = row,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 14), Parent = row })
	local ic = Icons.new(e.icon or "star", 22, if e.big then C.gold else C.dim)
	ic.Parent = row
	label(e.text, {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = F.bodyBold,
		TextSize = 14,
		TextColor3 = if e.big then C.text else C.dim,
		Parent = row,
	})
	if e.big then
		Audio.play("orb", 0.5, 1.1)
	end
	while #ticker:GetChildren() > 4 do -- layout + three rows
		local oldest = nil
		for _, c in ticker:GetChildren() do
			if c:IsA("Frame") then
				oldest = c
				break
			end
		end
		if oldest then
			oldest:Destroy()
		else
			break
		end
	end
	task.delay(7, function()
		if row.Parent then
			row:Destroy()
		end
	end)
end

function Settlement.chronicle(e)
	if calm then
		tell(e)
	else
		table.insert(pending, e)
		while #pending > 3 do
			table.remove(pending, 1)
		end
	end
end

-- The signals button (DD-087 §6): G or the button opens the eight phrases; 1–8 or a tap says one.
local sig = nil
local function buildSignals()
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local g = new("ScreenGui", {
		Name = "GroveSignals",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 9,
		Enabled = false,
		Parent = pg,
	})
	local btn = new("TextButton", {
		Name = "Open",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.52, 0),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.15,
		Text = "",
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.lime, Thickness = 2, Transparency = 0.3 },
		Parent = g,
	})
	local ic = Icons.new("users", 28, C.lime)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.new(0.5, 0, 0.42, 0)
	ic.Parent = btn
	local keyLabel = label("СИГНАЛ · G", {
		Position = UDim2.new(0, -18, 1, 2),
		Size = UDim2.new(1, 36, 0, 16),
		FontFace = F.head,
		TextSize = 11,
		TextColor3 = C.dim,
		Parent = btn,
	})
	stroke(keyLabel, 1.5)
	local list = new("Frame", {
		Name = "List",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -96, 0.52, 0),
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = g,
		List = { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right },
	})
	local function say(i: number)
		list.Visible = false
		if acts.say then
			acts.say(i)
		end
	end
	for i, sgn in Chronicle.Signals do
		local row = new("TextButton", {
			Size = UDim2.fromOffset(250, 40),
			BackgroundColor3 = rgb(250, 246, 236),
			BackgroundTransparency = 0.05,
			Text = "",
			Corner = UDim.new(1, 0),
			LayoutOrder = i,
			Parent = list,
		})
		local k = label(tostring(i), {
			Position = UDim2.fromOffset(8, 6),
			Size = UDim2.fromOffset(28, 28),
			FontFace = F.display,
			TextSize = 16,
			TextColor3 = C.dim,
			Parent = row,
		})
		local _ = k
		local ri = Icons.new(sgn.icon, 20, C.ink)
		ri.Position = UDim2.fromOffset(38, 10)
		ri.Parent = row
		label(sgn.text, {
			Position = UDim2.fromOffset(66, 0),
			Size = UDim2.new(1, -74, 1, 0),
			FontFace = F.bodyHeavy,
			TextSize = 16,
			TextColor3 = C.ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		row.Activated:Connect(function()
			say(i)
		end)
	end
	btn.Activated:Connect(function()
		list.Visible = not list.Visible
		Audio.play("ui", 0.4, 1.2)
	end)
	local UIS = game:GetService("UserInputService")
	UIS.InputBegan:Connect(function(input, processed)
		if processed or not g.Enabled or UIS:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			list.Visible = not list.Visible
		elseif list.Visible then
			local n = input.KeyCode.Value - Enum.KeyCode.One.Value + 1
			if n >= 1 and n <= #Chronicle.Signals then
				say(n)
			end
		end
	end)
	sig = { gui = g, list = list }
end

function Settlement.setSignalsVisible(on: boolean)
	if not sig then
		if not on then
			return
		end
		buildSignals()
	end
	if sig.gui.Enabled ~= on then
		sig.gui.Enabled = on
		if not on then
			sig.list.Visible = false
		end
	end
end

local _ = Fx
local __ = RunService

return Settlement
