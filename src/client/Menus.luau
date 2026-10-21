--!nonstrict
-- Full-screen flows (RU, icon-first): lobby (В БОЙ / МАСТЕРСКАЯ), settings, upgrade cards with
-- reroll/banish, evolution splash with the evolved weapon model, results with scrap rewards.

local Lighting = game:GetService("Lighting")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Maps = require(Shared:WaitForChild("Maps"))
local Theme = require(script.Parent.Theme)
local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.Audio)
local Icons = require(script.Parent.Icons)
local Preview = require(script.Parent.Preview)
local Models = require(script.Parent.Models)

local new, label, tween = Theme.new, Theme.label, Theme.tween
local C, F = Theme.C, Theme.F

local Menus = {}

local send
local gui
local ui = {}
local myId = 0
local profile = nil
local lobbyState = nil
local selectedWeapon = "W_ARC_RIFLE"
local currentOfferId = nil
local offerFocus = 1
local banishMode = false
local blur
local tab = "play"

local STAT_ICONS = { power = "burst", rate = "chevrons", range = "crosshair", control = "users" }
local STAT_NAMES = { power = "УРОН", rate = "ТЕМП", range = "ДАЛЬНОСТЬ", control = "ТОЛПА" }

local function icon(name: string, size: number, color: Color3, props, cut: Color3?)
	local i = Icons.new(name, size, color, cut or C.panel, props and props.ZIndex)
	for k, v in props or {} do
		if k ~= "ZIndex" then
			i[k] = v
		end
	end
	return i
end

local function button(parent, text: string, props, color: Color3?, iconName: string?)
	local accent = color or C.cyan
	local b = new("TextButton", { BackgroundColor3 = accent, BackgroundTransparency = 0.05, Text = "", Corner = 4, AutoButtonColor = false, Parent = parent })
	for k, v in props do
		b[k] = v
	end
	local z = (props.ZIndex or 1) + 1
	local l = label(text, { Name = "Label", Size = UDim2.fromScale(1, 1), FontFace = F.head, TextSize = 20, TextColor3 = C.bg, ZIndex = z, Parent = b })
	if iconName then
		local h = b.Size.Y.Offset
		icon(iconName, math.floor(h * 0.55), C.bg, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, math.floor(h * 0.3), 0.5, 0), ZIndex = z }, accent).Parent = b
		l.Position = UDim2.fromOffset(math.floor(h * 0.45), 0)
		l.Size = UDim2.new(1, -math.floor(h * 0.45), 1, 0)
	end
	local scale = new("UIScale", { Parent = b })
	b.MouseEnter:Connect(function()
		tween(scale, 0.12, { Scale = 1.04 })
		Audio.play("uiHover")
	end)
	b.MouseLeave:Connect(function()
		tween(scale, 0.12, { Scale = 1 })
	end)
	return b, l
end

local function scrapTag(parent, amount: number, props, color: Color3?)
	local row = new("Frame", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), List = { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5) }, Parent = parent })
	for k, v in props or {} do
		row[k] = v
	end
	icon("xp", 18, color or C.gold, { LayoutOrder = 1, ZIndex = row.ZIndex }).Parent = row
	label(Theme.commas(amount), { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), FontFace = F.num, TextSize = 20, TextColor3 = color or C.gold, ZIndex = row.ZIndex, Parent = row })
	return row
end

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

-- Lobby -------------------------------------------------------------------------------------------
local function buildLobby()
	local lobby = new("Frame", { Name = "Lobby", Size = UDim2.fromScale(1, 1), Parent = gui })
	ui.lobby = lobby
	new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.bg,
		Gradient = { Rotation = 0, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.45), NumberSequenceKeypoint.new(1, 0.7) }) },
		Parent = lobby,
	})
	local content = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1280, 720), Parent = lobby })
	ui.lobbyScale = new("UIScale", { Parent = content })
	ui.lobbyContent = content

	-- Title (chromatic split)
	local title = new("Frame", { Position = UDim2.fromOffset(28, 14), Size = UDim2.fromOffset(470, 64), Parent = content })
	for i, spec in { { C.red, -3, 0.55 }, { C.cyan, 3, 0.55 }, { C.white, 0, 0 } } do
		local t = label("SWARMFALL", { Position = UDim2.fromOffset(spec[2], 0), Size = UDim2.fromScale(1, 1), FontFace = F.title, TextSize = 60, TextColor3 = spec[1], TextTransparency = spec[3], TextXAlignment = Enum.TextXAlignment.Left, ZIndex = i, Parent = title })
		if i < 3 then
			t.Name = "Ghost"
		end
	end
	ui.title = title
	label("ВЫЖИВИ В РОЕ · ЭВОЛЮЦИОНИРУЙ · УБЕЙ БОССА", { Position = UDim2.fromOffset(32, 76), Size = UDim2.fromOffset(500, 18), FontFace = F.title, TextSize = 14, TextColor3 = C.cyan, TextXAlignment = Enum.TextXAlignment.Left, Parent = content })

	-- Scrap + settings (top-right)
	ui.scrapBox = Theme.panel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(1196, 22), Size = UDim2.fromOffset(170, 44), Parent = content }, C.gold)
	icon("xp", 26, C.gold, { Position = UDim2.fromOffset(12, 9) }).Parent = ui.scrapBox
	ui.scrap = label("0", { Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -56, 1, 0), FontFace = F.num, TextSize = 26, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Left, Parent = ui.scrapBox })
	label("СКРАП", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 2), Size = UDim2.fromOffset(60, 12), FontFace = F.title, TextSize = 10, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, Parent = ui.scrapBox })
	local gear = button(content, "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(1252, 22), Size = UDim2.fromOffset(44, 44) }, C.panel2)
	icon("gear", 28, C.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 3 }, C.panel2).Parent = gear
	gear.Activated:Connect(function()
		ui.settings.Visible = not ui.settings.Visible
		Audio.play("ui")
	end)

	-- Tabs
	ui.tabs = {}
	for i, t in { { "play", "В БОЙ", "swords" }, { "workshop", "МАСТЕРСКАЯ", "level" } } do
		local b, l = button(content, t[2], { Position = UDim2.fromOffset(560 + (i - 1) * 210, 24), Size = UDim2.fromOffset(200, 40) }, C.panel2, t[3])
		l.TextColor3 = C.text
		b.Activated:Connect(function()
			tab = t[1]
			Audio.play("ui")
			Menus.refreshLobby()
		end)
		ui.tabs[t[1]] = { button = b, label = l }
	end

	-- PLAY tab -------------------------------------------------------------------------------------
	local play = new("Frame", { Name = "Play", Position = UDim2.fromOffset(0, 104), Size = UDim2.fromOffset(1280, 616), Parent = content })
	ui.playTab = play
	-- Maps (left)
	label("ЗОНА", { Position = UDim2.fromOffset(32, 0), Size = UDim2.fromOffset(300, 18), FontFace = F.title, TextSize = 13, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = play })
	ui.mapCards = {}
	for i, mapId in Maps.Order do
		local map = Maps.get(mapId)
		local card = new("TextButton", { Position = UDim2.fromOffset(28, 24 + (i - 1) * 168), Size = UDim2.fromOffset(330, 158), BackgroundColor3 = C.panel, BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false, Corner = 5, Stroke = { Color = C.line, Thickness = 1, Transparency = 0.3 }, Parent = play })
		local portrait = new("Frame", { Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(120, 146), BackgroundColor3 = if map.theme == "depths" then Color3.fromRGB(30, 16, 36) else Color3.fromRGB(12, 22, 34), BackgroundTransparency = 0, Corner = 4, ClipsDescendants = true, Parent = card })
		Preview.creature(portrait, Defs.Enemies[map.boss].index, { spin = true, zoom = 0.75, pitch = 0.3 })
		label(map.name, { Position = UDim2.fromOffset(136, 10), Size = UDim2.fromOffset(186, 24), FontFace = F.head, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
		label(map.subtitle, { Position = UDim2.fromOffset(136, 36), Size = UDim2.fromOffset(186, 52), FontFace = F.body, TextSize = 13, TextWrapped = true, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
		local bossRow = new("Frame", { Position = UDim2.fromOffset(136, 92), Size = UDim2.fromOffset(186, 22), List = { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6) }, Parent = card })
		icon("crown", 18, C.red, { LayoutOrder = 1 }).Parent = bossRow
		label(Defs.Enemies[map.boss].name, { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), FontFace = F.head, TextSize = 16, TextColor3 = C.red, Parent = bossRow })
		local lock = new("Frame", { Name = "Lock", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.bg, BackgroundTransparency = 0.25, Corner = 5, ZIndex = 5, Visible = false, Parent = card })
		icon("lock", 40, C.dim, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), ZIndex = 6 }).Parent = lock
		label(map.unlock, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 82), Size = UDim2.new(1, -30, 0, 40), FontFace = F.bodyBold, TextSize = 14, TextWrapped = true, TextColor3 = C.dim, ZIndex = 6, Parent = lock })
		local scale = new("UIScale", { Parent = card })
		card.MouseEnter:Connect(function()
			tween(scale, 0.12, { Scale = 1.02 })
		end)
		card.MouseLeave:Connect(function()
			tween(scale, 0.12, { Scale = 1 })
		end)
		card.Activated:Connect(function()
			send("map", mapId)
			Audio.play("ui")
		end)
		ui.mapCards[mapId] = { card = card, stroke = card:FindFirstChildOfClass("UIStroke"), lock = lock }
	end
	-- Threat selector
	label("УГРОЗА", { Position = UDim2.fromOffset(32, 364), Size = UDim2.fromOffset(300, 18), FontFace = F.title, TextSize = 13, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = play })
	ui.threatPips = {}
	for t = 1, Defs.Threat.Max do
		local b = new("TextButton", { Position = UDim2.fromOffset(28 + (t - 1) * 66, 388), Size = UDim2.fromOffset(60, 60), BackgroundColor3 = C.panel, BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false, Corner = 5, Stroke = { Color = C.line, Transparency = 0.3 }, Parent = play })
		local ic = icon("skull", 30, C.dim, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6) })
		ic.Parent = b
		label(tostring(t), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.fromOffset(40, 18), FontFace = F.num, TextSize = 16, TextColor3 = C.dim, Name = "N", Parent = b })
		b.Activated:Connect(function()
			send("threat", t)
			Audio.play("ui")
		end)
		ui.threatPips[t] = { button = b, icon = ic, stroke = b:FindFirstChildOfClass("UIStroke") }
	end
	ui.threatInfo = label("", { Position = UDim2.fromOffset(32, 454), Size = UDim2.fromOffset(330, 40), FontFace = F.bodyBold, TextSize = 14, TextWrapped = true, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = play })
	ui.hostNote = label("", { Position = UDim2.fromOffset(32, 494), Size = UDim2.fromOffset(330, 18), FontFace = F.body, TextSize = 12, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = play })

	-- Weapons (center, 2×2)
	label("ОРУЖИЕ", { Position = UDim2.fromOffset(384, 0), Size = UDim2.fromOffset(300, 18), FontFace = F.title, TextSize = 13, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = play })
	ui.cards = {}
	for i, id in Defs.WeaponOrder do
		local w = Defs.Weapons[id]
		local evo = Defs.Evolutions[w.evolution]
		local col, row = (i - 1) % 2, (i - 1) // 2
		local card = new("TextButton", { Position = UDim2.fromOffset(380 + col * 272, 24 + row * 252), Size = UDim2.fromOffset(262, 244), BackgroundColor3 = C.panel, BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false, Corner = 5, Stroke = { Color = C.line, Thickness = 1, Transparency = 0.3 }, Parent = play })
		local scale = new("UIScale", { Parent = card })
		new("Frame", { Size = UDim2.new(1, 0, 0, 3), BackgroundTransparency = 0, BackgroundColor3 = w.color, Parent = card })
		local view = new("Frame", { Position = UDim2.fromOffset(6, 8), Size = UDim2.new(1, -12, 0, 104), BackgroundColor3 = C.bg, BackgroundTransparency = 0.35, Corner = 4, Parent = card })
		local vp = Preview.weapon(view, id, false, { spin = true, zoom = 0.62, pitch = 0.3 })
		label(w.name, { Position = UDim2.fromOffset(12, 114), Size = UDim2.new(1, -24, 0, 22), FontFace = F.head, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
		-- stat icons with bars
		local k = 0
		for _, stat in { "power", "rate", "range", "control" } do
			local x = 12 + (k % 2) * 122
			local y = 140 + (k // 2) * 24
			icon(STAT_ICONS[stat], 16, w.color, { Position = UDim2.fromOffset(x, y + 2) }).Parent = card
			local back = new("Frame", { Position = UDim2.fromOffset(x + 22, y + 8), Size = UDim2.fromOffset(92, 6), BackgroundTransparency = 0.5, BackgroundColor3 = Color3.new(0, 0, 0), Parent = card })
			for s = 1, 5 do
				new("Frame", { Position = UDim2.fromScale((s - 1) / 5, 0), Size = UDim2.new(0.2, -2, 1, 0), BackgroundTransparency = if s / 5 <= w.stats[stat] + 0.05 then 0 else 0.85, BackgroundColor3 = w.color, Parent = back })
			end
			k += 1
		end
		-- evolution recipe: key icons + core -> name
		local recipe = new("Frame", { Position = UDim2.fromOffset(12, 192), Size = UDim2.new(1, -24, 0, 42), BackgroundColor3 = C.bg, BackgroundTransparency = 0.4, Corner = 4, Parent = card })
		local x = 6
		for _, key in evo.keys do
			local def = Defs.Upgrades[key]
			icon(def.icon, 26, def.color, { Position = UDim2.fromOffset(x, 8) }).Parent = recipe
			x += 30
		end
		icon("core", 26, C.gold, { Position = UDim2.fromOffset(x, 8) }).Parent = recipe
		label("→", { Position = UDim2.fromOffset(x + 28, 0), Size = UDim2.fromOffset(18, 42), FontFace = F.head, TextSize = 20, TextColor3 = C.dim, Parent = recipe })
		label(evo.name, { Position = UDim2.fromOffset(x + 46, 0), Size = UDim2.new(1, -(x + 50), 1, 0), FontFace = F.head, TextSize = 15, TextWrapped = true, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Left, Parent = recipe })
		-- lock overlay
		local lock = new("Frame", { Name = "Lock", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.bg, BackgroundTransparency = 0.3, Corner = 5, ZIndex = 5, Visible = false, Parent = card })
		icon("lock", 36, C.gold, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), ZIndex = 6 }).Parent = lock
		local priceRow = scrapTag(lock, w.cost, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 162), ZIndex = 6 })
		priceRow.ZIndex = 6
		label("НАЖМИ, ЧТОБЫ КУПИТЬ", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 192), Size = UDim2.new(1, 0, 0, 16), FontFace = F.title, TextSize = 11, TextColor3 = C.dim, ZIndex = 6, Parent = lock })
		card.MouseEnter:Connect(function()
			tween(scale, 0.15, { Scale = 1.03 })
			Audio.play("uiHover")
		end)
		card.MouseLeave:Connect(function()
			tween(scale, 0.15, { Scale = 1 })
		end)
		card.Activated:Connect(function()
			if profile and not profile.weapons[id] then
				if (profile.scrap or 0) >= w.cost then
					send("buyWeapon", id)
					Audio.play("level", 1, 1.2)
				else
					Audio.play("warn")
				end
				return
			end
			Menus.selectWeapon(id)
			Audio.play("ui")
		end)
		ui.cards[id] = { card = card, stroke = card:FindFirstChildOfClass("UIStroke"), color = w.color, lock = lock, vp = vp }
	end

	-- Squad + deploy (right)
	label("ОТРЯД", { Position = UDim2.fromOffset(940, 0), Size = UDim2.fromOffset(300, 18), FontFace = F.title, TextSize = 13, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = play })
	ui.squadList = new("Frame", { Position = UDim2.fromOffset(936, 24), Size = UDim2.fromOffset(316, 300), List = { Padding = UDim.new(0, 6) }, Parent = play })
	ui.deploy, ui.deployLabel = button(play, "В БОЙ", { Position = UDim2.fromOffset(936, 420), Size = UDim2.fromOffset(316, 76) }, C.cyan, "play")
	ui.deployLabel.TextSize = 28
	ui.deploy.Activated:Connect(function()
		Audio.play("ui", 1, 1.2)
		if ui.ready then
			send("unready")
		else
			send("ready", selectedWeapon)
		end
	end)
	ui.lobbyStatus = label("", { Position = UDim2.fromOffset(936, 500), Size = UDim2.fromOffset(316, 40), FontFace = F.bodyBold, TextSize = 14, TextWrapped = true, TextColor3 = C.dim, Parent = play })
	ui.controlsHint = label("", { Position = UDim2.fromOffset(936, 548), Size = UDim2.fromOffset(316, 64), FontFace = F.mono, TextSize = 12, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = play })

	-- WORKSHOP tab ---------------------------------------------------------------------------------
	local shop = new("Frame", { Name = "Workshop", Position = UDim2.fromOffset(0, 104), Size = UDim2.fromOffset(1280, 616), Visible = false, Parent = content })
	ui.shopTab = shop
	label("Перки действуют во всех забегах. Они не дают огромной силы — они дают выбор.", { Position = UDim2.fromOffset(32, 0), Size = UDim2.fromOffset(900, 20), FontFace = F.body, TextSize = 15, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = shop })
	ui.perkCards = {}
	for i, id in Defs.PerkOrder do
		local def = Defs.Perks[id]
		local col, row = (i - 1) % 4, (i - 1) // 4
		local card = Theme.panel({ Position = UDim2.fromOffset(28 + col * 306, 32 + row * 276), Size = UDim2.fromOffset(296, 266), Parent = shop }, def.color)
		local badge = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(84, 84), BackgroundColor3 = C.bg, BackgroundTransparency = 0.2, Rotation = 45, Corner = 10, Stroke = { Color = def.color, Thickness = 2 }, Parent = card })
		icon(def.icon, 54, def.color, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 31) }, C.bg).Parent = card
		label(def.name, { Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, 0, 0, 26), FontFace = F.head, TextSize = 22, Parent = card })
		local pips = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 148), Size = UDim2.fromOffset(200, 8), List = { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 5) }, Parent = card })
		local pipList = {}
		for r = 1, def.max do
			pipList[r] = new("Frame", { Size = UDim2.fromOffset(28, 8), BackgroundTransparency = 0, BackgroundColor3 = C.line, Parent = pips })
		end
		local stat = label("", { Position = UDim2.fromOffset(12, 164), Size = UDim2.new(1, -24, 0, 40), FontFace = F.bodyBold, TextSize = 16, TextWrapped = true, Parent = card })
		local buy, buyLabel = button(card, "", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(200, 44) }, def.color)
		buy.Activated:Connect(function()
			send("buyPerk", id)
			Audio.play("level", 1, 1.15)
		end)
		ui.perkCards[id] = { card = card, pips = pipList, stat = stat, buy = buy, buyLabel = buyLabel, def = def }
	end

	Menus.selectWeapon(selectedWeapon)
end

local function buildSettings()
	local panel = Theme.panel({ Name = "Settings", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 320), Visible = false, ZIndex = 50, Parent = gui }, C.cyan)
	panel.BackgroundTransparency = 0.02
	ui.settings = panel
	icon("gear", 26, C.cyan, { Position = UDim2.fromOffset(18, 14), ZIndex = 51 }).Parent = panel
	label("НАСТРОЙКИ", { Position = UDim2.fromOffset(54, 14), Size = UDim2.fromOffset(300, 26), FontFace = F.head, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 51, Parent = panel })
	local names = { "НИЗКО", "СРЕДНЕ", "ВЫСОКО" }
	local rows = {
		{ "ГРАФИКА", "eye", function() return names[Settings.quality] end, function() Settings.set("quality", Settings.quality % 3 + 1) end },
		{ "ТРЯСКА ЭКРАНА", "boom", function() return if Settings.shake then "ВКЛ" else "ВЫКЛ" end, function() Settings.set("shake", not Settings.shake) end },
		{ "ЦИФРЫ УРОНА", "burst", function() return if Settings.numbers then "ВКЛ" else "ВЫКЛ" end, function() Settings.set("numbers", not Settings.numbers) end },
		{ "АВТОНАВЕДЕНИЕ", "crosshair", function() return if Settings.aimAssist then "ВКЛ" else "ВЫКЛ" end, function() Settings.set("aimAssist", not Settings.aimAssist) end },
	}
	for i, r in rows do
		local y = 60 + (i - 1) * 54
		icon(r[2], 24, C.dim, { Position = UDim2.fromOffset(20, y + 6), ZIndex = 51 }).Parent = panel
		label(r[1], { Position = UDim2.fromOffset(54, y), Size = UDim2.fromOffset(220, 36), FontFace = F.title, TextSize = 14, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 51, Parent = panel })
		local b, l = button(panel, r[3](), { Position = UDim2.fromOffset(300, y), Size = UDim2.fromOffset(140, 38), ZIndex = 51 }, C.panel2)
		l.TextColor3 = C.cyan
		l.TextSize = 16
		b.Activated:Connect(function()
			r[4]()
			l.Text = r[3]()
			Audio.play("ui")
		end)
	end
	local close, cl = button(panel, "ЗАКРЫТЬ", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(180, 38), ZIndex = 51 }, C.cyan)
	cl.TextSize = 16
	close.Activated:Connect(function()
		panel.Visible = false
	end)
end

function Menus.selectWeapon(id: string)
	selectedWeapon = id
	for wid, c in ui.cards do
		local on = wid == id
		c.stroke.Color = if on then c.color else C.line
		c.stroke.Thickness = if on then 3 else 1
		c.stroke.Transparency = if on then 0 else 0.3
		c.card.BackgroundTransparency = if on then 0.02 else 0.2
	end
	if send then
		send("weapon", id)
	end
	Menus.refreshLobby()
end

function Menus.setProfile(pub)
	profile = pub
	if profile and not profile.weapons[selectedWeapon] then
		selectedWeapon = "W_ARC_RIFLE"
	end
	Menus.refreshLobby()
end

function Menus.refreshLobby()
	if not ui.lobby then
		return
	end
	ui.playTab.Visible = tab == "play"
	ui.shopTab.Visible = tab == "workshop"
	for id, t in ui.tabs do
		t.button.BackgroundColor3 = if id == tab then C.cyan else C.panel2
		t.label.TextColor3 = if id == tab then C.bg else C.text
		for _, d in t.button:GetDescendants() do
			if d:IsA("Frame") and d.Parent and d.Parent:GetAttribute("Icon") then
				d.BackgroundColor3 = if id == tab then C.bg else C.text
			end
		end
	end
	local scrap = profile and profile.scrap or 0
	ui.scrap.Text = Theme.commas(scrap) .. (if profile and profile.offline then " *" else "")
	-- weapons lock state
	for id, c in ui.cards do
		local owned = profile == nil or profile.weapons[id] == true
		c.lock.Visible = not owned
		if not owned then
			local afford = scrap >= Defs.Weapons[id].cost
			c.lock.Hint.Text = if afford then "НАЖМИ, ЧТОБЫ КУПИТЬ" else "НЕ ХВАТАЕТ СКРАПА"
			c.lock.Hint.TextColor3 = if afford then C.gold else C.dim
		end
	end
	-- maps / threat
	local isHost = lobbyState and lobbyState.host == myId
	for mapId, m in ui.mapCards do
		local unlocked = profile == nil or (profile.threat[mapId] or 0) >= 1
		m.lock.Visible = not unlocked
		local selected = lobbyState and lobbyState.map == mapId
		m.stroke.Color = if selected then C.cyan else C.line
		m.stroke.Thickness = if selected then 3 else 1
		m.stroke.Transparency = if selected then 0 else 0.3
	end
	local mapId = lobbyState and lobbyState.map or "MAP_REACTOR_YARD"
	local threat = lobbyState and lobbyState.threat or 1
	local maxThreat = if profile then (profile.threat[mapId] or 1) else 1
	for t, pip in ui.threatPips do
		local available = t <= maxThreat
		local on = t <= threat
		Icons.recolor(pip.icon, if on then C.red elseif available then C.dim else C.line)
		pip.stroke.Color = if t == threat then C.red else C.line
		pip.stroke.Thickness = if t == threat then 2 else 1
		pip.button.BackgroundTransparency = if available then 0.1 else 0.6
	end
	ui.threatInfo.Text = if threat <= 1
		then "Обычная сложность. Победа откроет следующую угрозу."
		else string.format("Здоровье врагов +%d%%, урон +%d%% · награда ×%.2f", (Defs.Threat.hp(threat) - 1) * 100, (Defs.Threat.damage(threat) - 1) * 100, Defs.Threat.reward(threat))
	ui.hostNote.Text = if isHost or not lobbyState then "" else "Карту и угрозу выбирает лидер отряда"
	-- perks
	for id, pc in ui.perkCards do
		local rank = profile and profile.perks[id] or 0
		local def = pc.def
		for r, pip in pc.pips do
			pip.BackgroundColor3 = if r <= rank then def.color else C.line
		end
		pc.stat.Text = if rank > 0 then def.stat(rank) .. (if rank < def.max then "\n<font color=\"#7E95A6\">след.: " .. def.stat(rank + 1) .. "</font>" else "") else def.stat(1)
		local cost = def.costs[rank + 1]
		if cost then
			pc.buyLabel.Text = "КУПИТЬ · " .. Theme.commas(cost)
			local afford = scrap >= cost
			pc.buy.BackgroundColor3 = if afford then def.color else C.panel2
			pc.buyLabel.TextColor3 = if afford then C.bg else C.dim
		else
			pc.buyLabel.Text = "МАКСИМУМ"
			pc.buy.BackgroundColor3 = C.panel2
			pc.buyLabel.TextColor3 = C.lime
		end
	end
end

function Menus.showLobby(info, id: number, device: string)
	myId = id
	lobbyState = info
	ui.lobby.Visible = true
	ui.results.Visible = false
	local vs = workspace.CurrentCamera.ViewportSize
	ui.lobbyScale.Scale = math.clamp(math.min(vs.X / 1300, vs.Y / 740), 0.4, 1.5)
	ui.controlsHint.Text = if device == "touch"
		then "Левый стик — движение\nПравая площадка — прицел и огонь\nКнопки справа — рывок, перегрузка, эволюция"
		elseif device == "gamepad" then "L-стик движение · R-стик прицел/огонь\nB рывок · Y перегрузка · X эволюция\nA/X/B — выбор карты"
		else "WASD движение · МЫШЬ прицел · ЛКМ огонь\nПРОБЕЛ рывок · Q перегрузка · F эволюция\nR перезарядка · 1-4 выбор улучшения"
	clear(ui.squadList)
	local me = nil
	local readyCount = 0
	for _, p in info.players do
		if p.id == id then
			me = p
		end
		if p.ready then
			readyCount += 1
		end
		local row = Theme.panel({ Size = UDim2.fromOffset(316, 46), Parent = ui.squadList }, if p.ready then C.lime else C.line)
		local wbox = new("Frame", { Position = UDim2.fromOffset(4, 3), Size = UDim2.fromOffset(56, 40), Parent = row })
		Preview.weapon(wbox, p.weapon, false, { zoom = 0.6 })
		label(p.name, { Position = UDim2.fromOffset(66, 4), Size = UDim2.fromOffset(190, 20), FontFace = F.bodyBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		label(Defs.Weapons[p.weapon] and Defs.Weapons[p.weapon].short or "", { Position = UDim2.fromOffset(66, 24), Size = UDim2.fromOffset(190, 16), FontFace = F.title, TextSize = 11, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		if p.id == info.host then
			icon("crown", 20, C.gold, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0.5, 0) }).Parent = row
		end
		icon(if p.ready then "check" else "timer", 22, if p.ready then C.lime else C.dim, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0) }).Parent = row
	end
	ui.ready = me and me.ready
	ui.deployLabel.Text = if ui.ready then "ГОТОВ · ОТМЕНА" else "В БОЙ"
	ui.deploy.BackgroundColor3 = if ui.ready then C.lime else C.cyan
	ui.lobbyStatus.Text = if info.countdown then string.format("Готово %d/%d · высадка через %d", readyCount, #info.players, math.ceil(info.countdown))
		elseif #info.players > 1 then "Готовьтесь вместе или идите в бой — остальные подключатся в следующий раз"
		else "Соло-высадка · до 4 игроков в отряде"
	Menus.refreshLobby()
end

function Menus.hideLobby()
	ui.lobby.Visible = false
	ui.settings.Visible = false
end

-- Upgrade cards -------------------------------------------------------------------------------------
local function cardInfo(me, id: string)
	local def = Defs.Upgrades[id]
	if def then
		local rank = (me.ranks[id] or 0) + 1
		return def.name, def.icon, def.color, def.describe(rank), rank, (if rank > 1 then def.stat(rank - 1) .. "  →  " else "") .. def.stat(rank)
	end
	local fb = Defs.Fallbacks[id]
	return fb.name, fb.icon, fb.color, "", 0, fb.text
end

local function synergyNote(me, id: string): string?
	for _, syn in Defs.Synergies do
		local a, b = syn.keys[1], syn.keys[2]
		if (id == a and me.ranks[b] and not me.ranks[a]) or (id == b and me.ranks[a] and not me.ranks[b]) then
			return "СИНЕРГИЯ: " .. syn.name
		end
	end
	return nil
end

local CARD_W, CARD_GAP = 260, 18

local function buildOffer()
	local o = new("Frame", { Name = "Offer", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10, Parent = gui })
	ui.offer = o
	new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.35, BackgroundColor3 = C.bg, ZIndex = 10, Parent = o })
	local content = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1140, 580), ZIndex = 10, Parent = o })
	ui.offerScale = new("UIScale", { Parent = content })
	icon("level", 40, C.cyan, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), ZIndex = 11 }).Parent = content
	ui.offerTitle = label("НОВЫЙ УРОВЕНЬ", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 44), FontFace = F.head, TextSize = 40, TextColor3 = C.cyan, ZIndex = 11, Parent = content })
	ui.offerSub = label("", { Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 20), FontFace = F.title, TextSize = 14, TextColor3 = C.dim, ZIndex = 11, Parent = content })
	ui.offerCards = {}
	for i = 1, 4 do
		local card = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 116), Size = UDim2.fromOffset(CARD_W, 360), BackgroundColor3 = C.panel, BackgroundTransparency = 0.04, Text = "", AutoButtonColor = false, Corner = 6, Stroke = { Color = C.line, Thickness = 2, Transparency = 0.2 }, ZIndex = 11, Parent = content })
		local scale = new("UIScale", { Parent = card })
		local band = new("Frame", { Size = UDim2.new(1, 0, 0, 150), BackgroundTransparency = 0.1, BackgroundColor3 = C.cyan, Corner = 6, ZIndex = 12, Parent = card })
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 0.95), Parent = band })
		local badge = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CARD_W / 2, 78), Size = UDim2.fromOffset(92, 92), Rotation = 45, BackgroundTransparency = 0, BackgroundColor3 = C.bg, Corner = 12, Stroke = { Color = C.cyan, Thickness = 3 }, ZIndex = 13, Parent = card })
		local iconHolder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CARD_W / 2, 78), Size = UDim2.fromOffset(64, 64), ZIndex = 14, Parent = card })
		local key = label("1", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(28, 28), FontFace = F.numHeavy, TextSize = 18, TextColor3 = C.bg, BackgroundTransparency = 0.1, BackgroundColor3 = C.text, ZIndex = 14, Parent = card })
		new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = key })
		local badgeTag = label("НОВОЕ", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(84, 22), FontFace = F.head, TextSize = 14, TextColor3 = C.bg, BackgroundTransparency = 0, BackgroundColor3 = C.lime, ZIndex = 14, Parent = card })
		new("UICorner", { CornerRadius = UDim.new(0, 3), Parent = badgeTag })
		local name = label("", { Position = UDim2.fromOffset(10, 152), Size = UDim2.new(1, -20, 0, 28), FontFace = F.head, TextSize = 23, ZIndex = 12, Parent = card })
		local pips = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 184), Size = UDim2.fromOffset(120, 8), List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }, ZIndex = 12, Parent = card })
		local pipList = {}
		for k = 1, 3 do
			pipList[k] = new("Frame", { Size = UDim2.fromOffset(32, 8), BackgroundTransparency = 0, BackgroundColor3 = C.line, ZIndex = 12, Parent = pips })
		end
		local stat = label("", { Position = UDim2.fromOffset(10, 200), Size = UDim2.new(1, -20, 0, 34), FontFace = F.num, TextSize = 26, ZIndex = 12, Parent = card })
		local desc = label("", { Position = UDim2.fromOffset(16, 238), Size = UDim2.new(1, -32, 0, 56), FontFace = F.body, TextSize = 15, TextWrapped = true, TextColor3 = C.dim, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 12, Parent = card })
		local tagRow = new("Frame", { Position = UDim2.new(0, 10, 1, -58), Size = UDim2.new(1, -20, 0, 22), List = { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6) }, ZIndex = 12, Parent = card })
		local tagIcon = icon("evolve", 18, C.gold, { LayoutOrder = 1, ZIndex = 12 })
		tagIcon.Parent = tagRow
		local tag = label("", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), FontFace = F.head, TextSize = 15, TextColor3 = C.gold, ZIndex = 12, Parent = tagRow })
		local tag2 = label("", { Position = UDim2.new(0, 10, 1, -32), Size = UDim2.new(1, -20, 0, 20), FontFace = F.head, TextSize = 14, TextColor3 = C.violet, ZIndex = 12, Parent = card })
		local banOverlay = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.red, BackgroundTransparency = 0.8, Corner = 6, ZIndex = 20, Visible = false, Parent = card })
		icon("banish", 80, C.red, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 21 }).Parent = banOverlay
		card.MouseEnter:Connect(function()
			offerFocus = i
			Audio.play("uiHover")
		end)
		card.Activated:Connect(function()
			Menus.pick(i)
		end)
		ui.offerCards[i] = { card = card, scale = scale, band = band, badge = badge, badgeStroke = badge:FindFirstChildOfClass("UIStroke"), iconHolder = iconHolder, key = key, badgeTag = badgeTag, name = name, pips = pipList, stat = stat, desc = desc, tag = tag, tagIcon = tagIcon, tagRow = tagRow, tag2 = tag2, stroke = card:FindFirstChildOfClass("UIStroke"), banOverlay = banOverlay }
	end
	-- bottom bar: build + reroll/banish
	ui.offerBuild = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 500), Size = UDim2.fromOffset(330, 44), List = { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }, ZIndex = 11, Parent = content })
	ui.rerollBtn, ui.rerollLabel = button(content, "", { AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0.5, 190, 0, 500), Size = UDim2.fromOffset(150, 44), ZIndex = 11 }, C.gold, "reroll")
	ui.rerollBtn.Activated:Connect(function()
		if currentOfferId then
			send("reroll")
			Audio.play("ui", 1, 0.8)
		end
	end)
	ui.banishBtn, ui.banishLabel = button(content, "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, -190, 0, 500), Size = UDim2.fromOffset(150, 44), ZIndex = 11 }, C.red, "banish")
	ui.banishBtn.Activated:Connect(function()
		banishMode = not banishMode
		Audio.play("ui", 1, 0.7)
		Menus.refreshOfferModes()
	end)
end

function Menus.refreshOfferModes()
	local me = ui.offerMe
	if not me then
		return
	end
	ui.rerollBtn.Visible = (me.rerolls or 0) > 0
	ui.rerollLabel.Text = "ПЕРЕБРОС " .. (me.rerolls or 0)
	ui.banishBtn.Visible = (me.banishes or 0) > 0
	ui.banishLabel.Text = (if banishMode then "ОТМЕНА" else "ИЗГНАТЬ ") .. (if banishMode then "" else tostring(me.banishes or 0))
	for i, c in ui.offerCards do
		local id = me.offer and me.offer.choices[i]
		local allowed = id and Defs.Upgrades[id] and not me.ranks[id] and not (me.evolved == "" and table.find(Defs.Evolutions[Defs.Weapons[me.weapon].evolution].keys, id))
		c.banOverlay.Visible = banishMode and allowed == true
	end
end

function Menus.pick(index: number)
	if not currentOfferId or not ui.offer.Visible then
		return
	end
	local c = ui.offerCards[index]
	if not c or not c.card.Visible then
		return
	end
	if banishMode then
		if c.banOverlay.Visible then
			send("banish", currentOfferId, index)
			Audio.play("warn")
			banishMode = false
		end
		return
	end
	send("choose", currentOfferId, index)
	Audio.play("level", 1, 1.3)
	tween(c.scale, 0.12, { Scale = 1.12 })
	currentOfferId = nil
end

function Menus.focusMove(delta: number)
	if ui.offer.Visible then
		offerFocus = math.clamp(offerFocus + delta, 1, ui.offerCount or 3)
		Audio.play("uiHover")
	end
end

function Menus.confirm()
	if ui.offer.Visible then
		Menus.pick(offerFocus)
	end
end

function Menus.showOffer(me, run)
	local offer = me.offer
	ui.offerMe = me
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Size = 0
		blur.Parent = Lighting
	end
	ui.offerSub.Text = if run.solo then "ВЫБЕРИ ОДНО · ВРЕМЯ ОСТАНОВЛЕНО" else string.format("ВЫБЕРИ ОДНО · ОТРЯД ЖДЁТ · %d с", math.max(0, math.ceil(Defs.Run.ChoiceTimeoutCoop - run.pauseClock)))
	if offer.id == ui.shownOfferId and ui.offer.Visible then
		Menus.refreshOfferModes()
		return
	end
	ui.shownOfferId = offer.id
	currentOfferId = offer.id
	offerFocus = 1
	banishMode = false
	ui.offer.Visible = true
	tween(blur, 0.25, { Size = 14 })
	local vs = workspace.CurrentCamera.ViewportSize
	ui.offerScale.Scale = math.clamp(math.min(vs.X / 1180, vs.Y / 620), 0.45, 1.3)
	ui.offerTitle.Text = "УРОВЕНЬ " .. run.level .. (if me.pending > 1 then string.format("  <font size=\"20\" color=\"#7E95A6\">ЕЩЁ +%d</font>", me.pending - 1) else "")
	local evo = Defs.Evolutions[Defs.Weapons[me.weapon].evolution]
	local count = #offer.choices
	ui.offerCount = count
	for i, c in ui.offerCards do
		local id = offer.choices[i]
		c.card.Visible = id ~= nil
		if id then
			local name, iconName, color, text, rank, stat = cardInfo(me, id)
			c.name.Text = name
			for _, old in c.iconHolder:GetChildren() do
				old:Destroy()
			end
			local ic = icon(iconName, 64, color, { ZIndex = 14 }, C.bg)
			ic.Parent = c.iconHolder
			c.badgeStroke.Color = color
			c.band.BackgroundColor3 = color
			c.stat.Text = stat
			c.stat.TextColor3 = color
			c.desc.Text = text
			c.key.Text = tostring(i)
			c.badgeTag.Text = if rank == 0 then "БОНУС" elseif rank == 1 then "НОВОЕ" else "РАНГ " .. rank
			c.badgeTag.BackgroundColor3 = if rank == 0 then C.dim elseif rank == 1 then C.lime else C.cyan
			for k = 1, 3 do
				c.pips[k].BackgroundColor3 = if k <= rank then color else C.line
				c.pips[k].BackgroundTransparency = if k == rank then 0 elseif k < rank then 0.3 else 0.6
				c.pips[k].Visible = rank > 0
			end
			local isKey = me.evolved == "" and table.find(evo.keys, id) ~= nil
			c.tag.Text = if isKey then "КЛЮЧ ЭВОЛЮЦИИ" else ""
			c.tagIcon.Visible = isKey
			c.tag2.Text = synergyNote(me, id) or ""
			c.stroke.Color = if isKey then C.gold else color
			local x = (i - (count + 1) / 2) * (CARD_W + CARD_GAP)
			c.scale.Scale = 0.6
			c.card.Position = UDim2.new(0.5, x, 0, 160)
			c.card.BackgroundTransparency = 1
			task.delay((i - 1) * 0.06, function()
				tween(c.scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				tween(c.card, 0.3, { Position = UDim2.new(0.5, x, 0, 116), BackgroundTransparency = 0.04 })
			end)
		end
	end
	-- current build row
	clear(ui.offerBuild)
	for _, id in Defs.UpgradeOrder do
		if me.ranks[id] then
			local def = Defs.Upgrades[id]
			local slot = new("Frame", { Size = UDim2.fromOffset(44, 44), BackgroundColor3 = C.panel2, BackgroundTransparency = 0.1, Corner = 4, Stroke = { Color = def.color, Transparency = 0.3 }, ZIndex = 11, Parent = ui.offerBuild })
			icon(def.icon, 30, def.color, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), ZIndex = 12 }, C.panel2).Parent = slot
			label(tostring(me.ranks[id]), { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -2, 1, 0), Size = UDim2.fromOffset(14, 14), FontFace = F.num, TextSize = 13, TextColor3 = def.color, ZIndex = 12, Parent = slot })
		end
	end
	Menus.refreshOfferModes()
	Audio.play("level")
	task.delay(0.08, function()
		Audio.play("level", 0.8, 1.26)
	end)
	task.delay(0.16, function()
		Audio.play("level", 0.8, 1.5)
	end)
end

function Menus.hideOffer()
	if ui.offer.Visible then
		ui.offer.Visible = false
		ui.shownOfferId = nil
		currentOfferId = nil
		banishMode = false
		if blur then
			tween(blur, 0.2, { Size = 0 })
		end
	end
end

function Menus.offerVisible(): boolean
	return ui.offer.Visible
end

-- Evolution splash ------------------------------------------------------------------------------------
local function buildSplash()
	local s = new("Frame", { Name = "Splash", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 30, Parent = gui })
	ui.splash = s
	ui.flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BackgroundColor3 = C.white, ZIndex = 30, Parent = s })
	ui.splashModel = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(420, 220), ZIndex = 31, Parent = s })
	ui.splashTag = label("ОРУЖИЕ ЭВОЛЮЦИОНИРОВАЛО", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.43), Size = UDim2.new(1, 0, 0, 20), FontFace = F.title, TextSize = 16, TextColor3 = C.text, ZIndex = 31, Parent = s })
	ui.splashTitle = label("", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.new(1, 0, 0, 80), FontFace = F.head, TextSize = 72, TextColor3 = C.gold, TextStrokeTransparency = 0.3, ZIndex = 31, Parent = s })
	ui.splashSub = label("", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.new(0.6, 0, 0, 60), FontFace = F.bodyBold, TextSize = 20, TextWrapped = true, ZIndex = 31, Parent = s })
	ui.splashScale = new("UIScale", { Parent = ui.splashTitle })
end

function Menus.evolveSplash(evoId: string)
	local evo = Defs.Evolutions[evoId]
	if not evo then
		return
	end
	ui.splash.Visible = true
	for _, c in ui.splashModel:GetChildren() do
		c:Destroy()
	end
	Preview.weapon(ui.splashModel, evo.weapon, true, { spin = true, zoom = 0.55, pitch = 0.2 }).ZIndex = 31
	ui.splashModel.Visible = true
	ui.flash.BackgroundTransparency = 0
	tween(ui.flash, 0.6, { BackgroundTransparency = 1 })
	ui.splashTitle.Text = evo.name
	ui.splashTitle.TextColor3 = evo.color
	ui.splashSub.Text = evo.text
	ui.splashScale.Scale = 2.2
	ui.splashTitle.TextTransparency = 1
	ui.splashTag.TextTransparency = 0
	tween(ui.splashScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(ui.splashTitle, 0.3, { TextTransparency = 0 })
	ui.splashSub.TextTransparency = 1
	tween(ui.splashSub, 0.6, { TextTransparency = 0 })
	task.delay(2.4, function()
		tween(ui.splashTitle, 0.4, { TextTransparency = 1 })
		tween(ui.splashSub, 0.4, { TextTransparency = 1 })
		tween(ui.splashTag, 0.4, { TextTransparency = 1 })
		task.wait(0.42)
		ui.splashModel.Visible = false
		ui.splash.Visible = false
	end)
end

function Menus.whiteFlash(amount: number)
	ui.splash.Visible = true
	ui.flash.BackgroundTransparency = 1 - amount
	tween(ui.flash, 0.4, { BackgroundTransparency = 1 })
	task.delay(0.42, function()
		if ui.splashTitle.TextTransparency >= 1 then
			ui.splash.Visible = false
		end
	end)
end

-- Results ---------------------------------------------------------------------------------------------
local function buildResults()
	local r = new("Frame", { Name = "Results", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, Parent = gui })
	ui.results = r
	new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.2, BackgroundColor3 = C.bg, ZIndex = 20, Parent = r })
	local content = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1040, 660), ZIndex = 20, Parent = r })
	ui.resultsScale = new("UIScale", { Parent = content })
	ui.resIcon = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(56, 56), ZIndex = 21, Parent = content })
	ui.resTitle = label("", { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 64), FontFace = F.head, TextSize = 60, ZIndex = 21, Parent = content })
	ui.resReason = label("", { Position = UDim2.fromOffset(0, 120), Size = UDim2.new(1, 0, 0, 22), FontFace = F.title, TextSize = 15, TextColor3 = C.dim, ZIndex = 21, Parent = content })
	ui.resStats = new("Frame", { Position = UDim2.fromOffset(0, 156), Size = UDim2.new(1, 0, 0, 96), List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), HorizontalAlignment = Enum.HorizontalAlignment.Center }, ZIndex = 21, Parent = content })
	ui.resReward = Theme.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 264), Size = UDim2.fromOffset(700, 74), ZIndex = 21, Parent = content }, C.gold)
	ui.resPlayers = new("Frame", { Position = UDim2.fromOffset(0, 350), Size = UDim2.new(1, 0, 0, 220), List = { Padding = UDim.new(0, 8) }, ZIndex = 21, Parent = content })
	ui.resButton, ui.resButtonLabel = button(content, "В ЛОББИ", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(360, 60), ZIndex = 22 }, C.cyan, "play")
	ui.resButtonLabel.TextSize = 24
	ui.resButton.Activated:Connect(function()
		send("continue")
		Audio.play("ui")
		ui.resButtonLabel.Text = "ЖДЁМ ОТРЯД"
	end)
end

local function statTile(parent, iconName: string, title: string, value: string, color: Color3)
	local t = Theme.panel({ Size = UDim2.fromOffset(160, 92), ZIndex = 21, Parent = parent }, color)
	icon(iconName, 24, color, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), ZIndex = 22 }).Parent = t
	label(value, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 36), FontFace = F.num, TextSize = 34, TextColor3 = color, ZIndex = 22, Parent = t })
	label(title, { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 14), FontFace = F.title, TextSize = 10, TextColor3 = C.dim, ZIndex = 22, Parent = t })
end

function Menus.showResults(result, votes, id: number, reward)
	if ui.results.Visible and ui.shownResult == result and ui.shownReward == reward then
		return
	end
	local first = ui.shownResult ~= result
	ui.shownResult = result
	ui.shownReward = reward
	Menus.hideOffer()
	ui.results.Visible = true
	local vs = workspace.CurrentCamera.ViewportSize
	ui.resultsScale.Scale = math.clamp(math.min(vs.X / 1080, vs.Y / 700), 0.45, 1.3)
	clear(ui.resIcon)
	icon(if result.victory then "crown" else "skull", 56, if result.victory then C.gold else C.red, { ZIndex = 22 }).Parent = ui.resIcon
	ui.resTitle.Text = if result.victory then "ЗОНА ЗАЧИЩЕНА" else "ПОРАЖЕНИЕ"
	ui.resTitle.TextColor3 = if result.victory then C.gold else C.red
	local map = Maps.get(result.map)
	ui.resReason.Text = result.reason .. "  ·  " .. map.name .. (if (result.threat or 1) > 1 then "  ·  УГРОЗА " .. result.threat else "")
	clear(ui.resStats)
	statTile(ui.resStats, "timer", "ВРЕМЯ", Theme.fmtTime(result.time), C.text)
	statTile(ui.resStats, "level", "УРОВЕНЬ", tostring(result.level), C.cyan)
	statTile(ui.resStats, "skull", "УБИЙСТВ", Theme.commas(result.kills), C.orange)
	local best = 0
	for _, p in result.players do
		best = math.max(best, p.bestCombo)
	end
	statTile(ui.resStats, "boom", "ЛУЧШАЯ СЕРИЯ", "×" .. best, C.gold)
	statTile(ui.resStats, "hive", "УЛЕЙ", if result.hive == "cleared" then "ЗАЧИЩЕН" elseif result.hive == "failed" then "УШЁЛ" else "—", C.lime)
	-- reward strip
	clear(ui.resReward)
	local row = new("Frame", { Size = UDim2.fromScale(1, 1), List = { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14) }, ZIndex = 22, Parent = ui.resReward })
	if reward then
		for i, l in reward.lines do
			local cell = new("Frame", { LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), List = { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4) }, ZIndex = 22, Parent = row })
			icon(l[1], 22, C.dim, { LayoutOrder = 1, ZIndex = 22 }).Parent = cell
			label("+" .. l[2], { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), FontFace = F.num, TextSize = 20, TextColor3 = C.text, ZIndex = 22, Parent = cell })
		end
		if reward.mult and reward.mult > 1.001 then
			label(string.format("×%.2f", reward.mult), { LayoutOrder = 50, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), FontFace = F.num, TextSize = 20, TextColor3 = C.red, ZIndex = 22, Parent = row })
		end
		label("=", { LayoutOrder = 60, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), FontFace = F.num, TextSize = 22, TextColor3 = C.dim, ZIndex = 22, Parent = row })
		local total = scrapTag(row, reward.total, { LayoutOrder = 70, ZIndex = 22 })
		total.ZIndex = 22
		for k, u in reward.unlocked or {} do
			local cell = new("Frame", { LayoutOrder = 80 + k, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), List = { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4) }, ZIndex = 22, Parent = row })
			icon(if u[1] == "map" then "pin" else "threat", 24, C.lime, { LayoutOrder = 1, ZIndex = 22 }).Parent = cell
			label(if u[1] == "map" then "ОТКРЫТО: " .. Maps.get(u[2]).name else "УГРОЗА " .. u[2] .. " ОТКРЫТА", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), FontFace = F.head, TextSize = 16, TextColor3 = C.lime, ZIndex = 22, Parent = cell })
		end
	else
		label("Подсчёт награды…", { Size = UDim2.fromScale(1, 1), FontFace = F.title, TextSize = 14, TextColor3 = C.dim, ZIndex = 22, Parent = row })
	end
	if not first then
		return
	end
	clear(ui.resPlayers)
	for _, p in result.players do
		local prow = Theme.panel({ Size = UDim2.new(1, 0, 0, 64), ZIndex = 21, Parent = ui.resPlayers }, if p.id == id then C.cyan else C.line)
		local wbox = new("Frame", { Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(84, 56), ZIndex = 22, Parent = prow })
		Preview.weapon(wbox, p.weapon, p.evolved ~= "", { zoom = 0.6 }).ZIndex = 22
		label(p.name, { Position = UDim2.fromOffset(98, 6), Size = UDim2.fromOffset(220, 24), FontFace = F.bodyBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = prow })
		local w = Defs.Weapons[p.weapon]
		label(if p.evolved ~= "" then Defs.Evolutions[p.evolved].name else w.name, { Position = UDim2.fromOffset(98, 32), Size = UDim2.fromOffset(220, 20), FontFace = F.head, TextSize = 14, TextColor3 = if p.evolved ~= "" then C.gold else C.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = prow })
		local ups = new("Frame", { Position = UDim2.fromOffset(330, 10), Size = UDim2.new(1, -560, 0, 44), List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, ZIndex = 22, Parent = prow })
		for _, u in p.upgrades do
			local def = Defs.Upgrades[u[1]]
			local slot = new("Frame", { Size = UDim2.fromOffset(44, 44), BackgroundColor3 = C.panel2, BackgroundTransparency = 0.1, Corner = 4, ZIndex = 22, Parent = ups })
			icon(def.icon, 30, def.color, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), ZIndex = 23 }, C.panel2).Parent = slot
			label(tostring(u[2]), { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -2, 1, 0), Size = UDim2.fromOffset(14, 14), FontFace = F.num, TextSize = 13, TextColor3 = def.color, ZIndex = 23, Parent = slot })
		end
		local stats = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(210, 52), ZIndex = 22, Parent = prow })
		icon("skull", 18, C.orange, { Position = UDim2.fromOffset(0, 4), ZIndex = 23 }).Parent = stats
		label(Theme.commas(p.kills), { Position = UDim2.fromOffset(24, 0), Size = UDim2.fromOffset(180, 24), FontFace = F.num, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = stats })
		icon("burst", 18, C.red, { Position = UDim2.fromOffset(0, 30), ZIndex = 23 }).Parent = stats
		label(Theme.commas(p.damage), { Position = UDim2.fromOffset(24, 26), Size = UDim2.fromOffset(180, 24), FontFace = F.num, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = stats })
	end
	ui.resButtonLabel.Text = "В ЛОББИ"
	ui.resTitle.TextTransparency = 1
	tween(ui.resTitle, 0.6, { TextTransparency = 0 })
end

function Menus.hideResults()
	ui.results.Visible = false
	ui.shownResult = nil
	ui.shownReward = nil
end

-- Notes -------------------------------------------------------------------------------------------
local function buildNotes()
	ui.note = Theme.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(500, 46), Visible = false, ZIndex = 5, Parent = gui }, C.gold)
	ui.noteText = label("", { Size = UDim2.fromScale(1, 1), FontFace = F.head, TextSize = 18, TextColor3 = C.gold, ZIndex = 6, Parent = ui.note })
end

function Menus.note(text: string?)
	ui.note.Visible = text ~= nil
	if text then
		ui.noteText.Text = text
	end
end

function Menus.init(playerGui: PlayerGui, sender)
	send = sender
	gui = new("ScreenGui", { Name = "SwarmMenus", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
	buildSettings()
	buildOffer()
	buildSplash()
	buildResults()
	buildNotes()
	buildLobby()
end

function Menus.update(dt: number)
	if ui.lobby.Visible then
		local now = os.clock()
		for _, g in ui.title:GetChildren() do
			if g.Name == "Ghost" then
				local j = if math.random() < 0.04 then (math.random() - 0.5) * 14 else 0
				g.Position = UDim2.fromOffset((if g.TextColor3 == C.red then -3 else 3) + j, 0)
			end
		end
		ui.deploy.BackgroundTransparency = 0.05 + (math.sin(now * 3) + 1) * 0.04
	end
	if ui.offer.Visible then
		for i, c in ui.offerCards do
			local focused = i == offerFocus
			c.stroke.Thickness = if focused then 3 else 2
			if focused and c.scale.Scale < 1.05 and c.scale.Scale >= 0.99 then
				c.scale.Scale += (1.04 - c.scale.Scale) * math.min(1, dt * 10)
			elseif not focused and c.scale.Scale > 1.0 then
				c.scale.Scale += (1 - c.scale.Scale) * math.min(1, dt * 10)
			end
		end
	end
	Preview.update(dt)
end

return Menus
