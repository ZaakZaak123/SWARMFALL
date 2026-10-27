--!nonstrict
-- SPOREFALL full-screen flows (DD-031), rebuilt from scratch:
--   lobby     — the crater behind, the logo, the next hunt, one big В БОЙ. Everything else appears only
--               once it means something (Progressive Discovery: xenite and upgrades after the first
--               hunt, weapons when the second gun is in sight, threat after a first win).
--   upgrades  — permanent perks bought with xenite.
--   settings  — four toggles.
--   cards     — the level-up choice: three big cards, one decision.
--   results   — victory / defeat, what you earned, what opened, one button.

local Lighting = game:GetService("Lighting")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Ops = require(Shared:WaitForChild("Ops"))
local Theme = require(script.Parent.Theme)
local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.Audio)
local Icons = require(script.Parent.Icons)
local Xenite = require(script.Parent.Xenite)
local Preview = require(script.Parent.Preview)
local MetaMenus = require(script.Parent.MetaMenus)
local Meta = require(Shared:WaitForChild("Meta"))
local Goals = require(Shared:WaitForChild("Goals"))
local Showcase = require(Shared:WaitForChild("Showcase"))

local new, label, tween = Theme.new, Theme.label, Theme.tween
local C, F = Theme.C, Theme.F

local Menus = {}

local send
local gui
local ui = {}
local myId = 0
local profile = nil
local MODE_COLOR = { hunt = C.lime, siege = C.orange, raid = C.red } -- DD-082: one colour per mode
local lobbyState = nil
local device = "pc"
local selectedWeapon = "W_ARC_RIFLE"
local currentOfferId = nil
local offerFocus = 1
local banishMode = false
local offerLock: number? = nil -- DD-051: the only card that can be taken (first card of the first hunt)
local blur
local amReady = false

-- Weapons the reboot presents. Other guns stay in the data and appear only if a profile owns them.
local SHOWN_WEAPONS = { "W_ARC_RIFLE", "W_SCATTERGUN" }

local function icon(name: string, size: number, color: Color3, props)
	local i = Icons.new(name, size, color, C.ink)
	for k, v in props or {} do
		i[k] = v
	end
	return i
end

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if
			not (
				c:IsA("UIListLayout")
				or c:IsA("UIPadding")
				or c:IsA("UIGridLayout")
				or c:IsA("UIScale")
				or c:IsA("UICorner")
				or c:IsA("UIStroke")
				or c:IsA("UIGradient")
			)
		then
			c:Destroy()
		end
	end
end

local function viewportScale(base: Vector2): number
	local vs = if gui and gui.AbsoluteSize.X > 0 then gui.AbsoluteSize else workspace.CurrentCamera.ViewportSize
	return math.clamp(math.min(vs.X / base.X, vs.Y / base.Y), 0.3, 1.25)
end

-- The results body: on a phone only the centre column is laid out, so it fits a narrower base.
local function resultsScale(): number
	if Theme.phone() then
		-- the centre column is 740 wide from x = 230: scale so that it fills the width, then shift it
		return viewportScale(Vector2.new(780, 730))
	end
	return viewportScale(Vector2.new(1240, 780))
end

local function setBlur(size: number)
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = "MenuBlur"
		blur.Size = 0
		blur.Parent = Lighting
	end
	tween(blur, 0.3, { Size = size })
end

-- Xenite amount pill (the emblem + number, DD-095).
local function xenitePill(parent, props)
	local p = new("Frame", {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.2,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.pink, Transparency = 0.5, Thickness = 1.5 },
		Parent = parent,
	})
	for k, v in props or {} do
		p[k] = v
	end
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 16), Parent = p })
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = p,
	})
	Xenite.icon(34, { LayoutOrder = 1, Parent = p })
	local amount = label("0", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		FontFace = F.numHeavy,
		TextSize = 18,
		LayoutOrder = 2,
		Parent = p,
	})
	return p, amount
end

local modalWindows = {}
local lastMenuSize = Vector2.zero
local function modal(name: string, w: number, h: number, title: string, accent: Color3)
	local shade = new("TextButton", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.35,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 40,
		Parent = gui,
	})
	local panel = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 0.06,
		CornerRadius = 22,
		ZIndex = 41,
		Parent = shade,
	}, accent)
	local scale = new("UIScale", { Parent = panel })
	label(title, {
		Name = "ModalTitle",
		Position = UDim2.fromOffset(28, 22),
		Size = UDim2.new(1, -120, 0, 36),
		FontFace = F.display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 42,
		Parent = panel,
	})
	local close = new("TextButton", {
		Name = "ModalClose",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 18),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.9,
		Text = "",
		Corner = UDim.new(1, 0),
		ZIndex = 42,
		Parent = panel,
	})
	label("×", { Size = UDim2.fromScale(1, 1), FontFace = F.bodyBold, TextSize = 26, ZIndex = 43, Parent = close })
	local function hide()
		shade.Visible = false
		Audio.play("ui", 0.8, 0.9)
	end
	close.Activated:Connect(hide)
	local m = { shade = shade, panel = panel, scale = scale, hide = hide }
	m.baseSize = Vector2.new(w + 40, h + 40)
	table.insert(modalWindows, m)
	function m.show()
		shade.Visible = true
		if m.resize then
			m.resize(gui.AbsoluteSize)
		else
			scale.Scale = viewportScale(m.baseSize) * 0.9
			tween(scale, 0.3, { Scale = viewportScale(m.baseSize) }, Enum.EasingStyle.Back)
		end
		Audio.play("ui")
	end
	return m
end

-- Lobby -------------------------------------------------------------------------------------------------
local function buildLobby()
	local l = new("Frame", { Name = "Lobby", Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	ui.lobby = l
	-- legibility scrims: left column and bottom
	new("Frame", {
		Size = UDim2.fromScale(0.62, 1),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0,
		Parent = l,
		Gradient = {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
		},
	})
	new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.32),
		BackgroundColor3 = C.bg,
		Parent = l,
		Gradient = {
			Rotation = -90,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		},
	})
	local safe = new("Frame", { Name = "Safe", Size = UDim2.fromScale(1, 1), Parent = l })
	ui.lobbySafe = safe
	ui.lobbyScale = new("UIScale", { Parent = safe })
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 48),
		PaddingRight = UDim.new(0, 40),
		PaddingTop = UDim.new(0, 70),
		PaddingBottom = UDim.new(0, 36),
		Parent = safe,
	})
	-- Logo
	local logo = label("THE LAST GROVE", {
		Size = UDim2.fromOffset(640, 84),
		FontFace = F.display,
		TextSize = 60,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = safe,
	})
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.white),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(226, 255, 150)),
			ColorSequenceKeypoint.new(1, C.lime),
		}),
		Parent = logo,
	})
	new("UIStroke", { Color = C.ink, Thickness = 3, Transparency = 0.2, Parent = logo })
	ui.logoScale = new("UIScale", { Parent = logo })
	label("ВЕРНИ ЖИЗНЬ СВОЕМУ УГЛУ МИРА.", {
		Position = UDim2.fromOffset(4, 86),
		Size = UDim2.fromOffset(640, 22),
		FontFace = F.head,
		TextSize = 16,
		TextColor3 = C.pink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = safe,
	})
	-- Mode tabs (DD-037): hunts always; the outpost siege and raids appear once opened
	ui.tabs = new("Frame", {
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.fromOffset(460, 40),
		Parent = safe,
		List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) },
	})
	ui.tabButtons = {}
	for i, t in
		{ { "hunt", "ВЫЛАЗКИ" }, { "siege", "ОБОРОНА БУРА" }, { "raid", "ВТОРЖЕНИЕ" } }
	do
		local b, bl = Theme.button(
			t[2],
			{ Name = "Tab_" .. t[1], Size = UDim2.fromOffset(146, 40), TextSize = 13, LayoutOrder = i }
		)
		b.Parent = ui.tabs
		b.Activated:Connect(function()
			send("mode", t[1])
			Audio.play("uiHover")
		end)
		ui.tabButtons[t[1]] = { button = b, label = bl }
	end
	-- Hunt card
	local hunt = Theme.panel({
		Name = "Hunt",
		Position = UDim2.fromOffset(0, 176),
		Size = UDim2.fromOffset(460, 214),
		CornerRadius = 20,
		Parent = safe,
	})
	ui.hunt = hunt
	ui.huntTag = label("ВЫЛАЗКА 1", {
		Position = UDim2.fromOffset(24, 18),
		Size = UDim2.fromOffset(300, 16),
		FontFace = F.head,
		TextSize = 12,
		TextColor3 = C.lime,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = hunt,
	})
	ui.huntName = label("", {
		Position = UDim2.fromOffset(24, 36),
		Size = UDim2.new(1, -48, 0, 40),
		FontFace = F.display,
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		Parent = hunt,
	})
	new("UITextSizeConstraint", { MaxTextSize = 32, Parent = ui.huntName })
	ui.huntBrief = label("", {
		Position = UDim2.fromOffset(24, 82),
		Size = UDim2.new(1, -48, 0, 60),
		FontFace = F.body,
		TextSize = 17,
		TextColor3 = C.dim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = hunt,
	})
	-- why every sortie happens (DD-065): the same sentence the shelter's cableway tells in space
	ui.huntWhy = label(
		"Бур в центре воронки вскрывает погребённый город — ксенит с него идёт по канатке в твоё убежище. Рой лезет на шум бура.",
		{
			Position = UDim2.fromOffset(24, 148),
			Size = UDim2.new(1, -48, 0, 50),
			FontFace = F.bodyBold,
			TextSize = 13,
			TextColor3 = C.lime,
			TextTransparency = 0.15,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = hunt,
		}
	)
	ui.anomaly = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.gold,
		BackgroundTransparency = 0.82,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.gold, Transparency = 0.45 },
		Visible = false,
		Parent = hunt,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = ui.anomaly })
	ui.anomalyText = label("", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		FontFace = F.head,
		TextSize = 10,
		TextColor3 = C.gold,
		Parent = ui.anomaly,
	})
	ui.modeRow = new("Frame", {
		Position = UDim2.fromOffset(24, 156),
		Size = UDim2.new(1, -48, 0, 40),
		Visible = false,
		Parent = hunt,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		},
	})
	-- hunt navigation and threat
	ui.huntPrev =
		Theme.button("‹", { Position = UDim2.fromOffset(24, 156), Size = UDim2.fromOffset(42, 38), TextSize = 22 })
	ui.huntPrev.Parent = hunt
	ui.huntNext =
		Theme.button("›", { Position = UDim2.fromOffset(72, 156), Size = UDim2.fromOffset(42, 38), TextSize = 22 })
	ui.huntNext.Parent = hunt
	ui.threat = new("Frame", { Position = UDim2.fromOffset(132, 156), Size = UDim2.fromOffset(300, 38), Parent = hunt })
	ui.threatLabel = label("УГРОЗА", {
		Size = UDim2.fromOffset(70, 38),
		FontFace = F.head,
		TextSize = 11,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ui.threat,
	})
	ui.threatDots = {}
	for i = 1, Defs.Threat.Max do
		local d = new("TextButton", {
			Position = UDim2.fromOffset(70 + (i - 1) * 40, 2),
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = C.white,
			BackgroundTransparency = 0.9,
			Text = "",
			Corner = UDim.new(1, 0),
			Stroke = { Color = C.orange, Transparency = 0.6 },
			Parent = ui.threat,
		})
		local t = label(tostring(i), { Size = UDim2.fromScale(1, 1), FontFace = F.numHeavy, TextSize = 14, Parent = d })
		d.Activated:Connect(function()
			send("threat", i)
			Audio.play("ui")
		end)
		ui.threatDots[i] = { button = d, text = t }
	end
	-- Weapons
	ui.weaponsTitle = label("ОРУЖИЕ", {
		Position = UDim2.fromOffset(4, 366),
		Size = UDim2.fromOffset(200, 16),
		FontFace = F.head,
		TextSize = 12,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = safe,
	})
	ui.weapons = new("Frame", {
		Position = UDim2.fromOffset(0, 388),
		Size = UDim2.fromOffset(700, 150),
		Parent = safe,
		List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14) },
	})
	-- Top right: xenite, settings, squad
	local tr = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -50),
		Size = UDim2.fromOffset(400, 300),
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
	icon(
		"gear",
		24,
		C.text,
		{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = ui.gear }
	)
	ui.gear.Activated:Connect(function()
		ui.settings.show()
	end)
	ui.xenite, ui.xeniteAmount = xenitePill(tr, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -56, 0, 2) })
	-- Play together (DD-040): one tap to the Roblox invite sheet.
	ui.invite = Theme.button("ПОЗВАТЬ ДРУЗЕЙ", {
		Name = "Invite",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -56, 0, 50),
		Size = UDim2.fromOffset(200, 40),
		TextSize = 12,
	})
	ui.invite.Parent = tr
	ui.invite.Activated:Connect(function()
		Audio.play("ui")
		task.spawn(function()
			local SocialService = game:GetService("SocialService")
			local lp = game:GetService("Players").LocalPlayer
			local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, lp)
			if ok and can then
				pcall(SocialService.PromptGameInvite, SocialService, lp)
			end
		end)
	end)
	label("+10% ксенита за каждого в отряде", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -56, 0, 92),
		Size = UDim2.fromOffset(240, 14),
		FontFace = F.body,
		TextSize = 11,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = tr,
	})
	ui.harvest = Theme.button("СОБРАТЬ", {
		Name = "Harvest",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -56, 0, 112),
		Size = UDim2.fromOffset(200, 40),
		TextSize = 12,
	}, "primary")
	ui.harvest.Parent = tr
	ui.harvest.Visible = false
	ui.harvest.Activated:Connect(function()
		send("harvest")
		Audio.play("orb", 1, 0.9)
		Audio.play("level", 0.6, 1.4)
	end)
	-- «Пока тебя не было»: a one-time summary of raids on your outpost
	ui.toast = Theme.panel({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -40),
		Size = UDim2.fromOffset(520, 72),
		CornerRadius = 18,
		Visible = false,
		Parent = safe,
	}, C.orange)
	ui.toastTitle = label("ПОКА ТЕБЯ НЕ БЫЛО", {
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(1, -40, 0, 18),
		FontFace = F.head,
		TextSize = 12,
		TextColor3 = C.orange,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ui.toast,
	})
	ui.toastText = label("", {
		Position = UDim2.fromOffset(20, 30),
		Size = UDim2.new(1, -40, 0, 30),
		FontFace = F.bodyBold,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ui.toast,
	})
	ui.squad = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 60),
		Size = UDim2.fromOffset(260, 220),
		Parent = tr,
		List = { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right },
	})
	-- Bottom left: upgrades, swarm, outpost log, boards
	ui.metaRow = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(760, 58),
		Parent = safe,
		List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) },
	})
	ui.upgradesBtn = Theme.button("УЛУЧШЕНИЯ", {
		Name = "Upgrades",
		Size = UDim2.fromOffset(230, 58),
		TextSize = 17,
		LayoutOrder = 1,
	})
	ui.upgradesBtn.Parent = ui.metaRow
	local function metaButton(name: string, text: string, iconName: string, color: Color3, order: number, onClick)
		local b, bl =
			Theme.button(text, { Name = name, Size = UDim2.fromOffset(150, 58), TextSize = 14, LayoutOrder = order })
		b.Parent = ui.metaRow
		bl.Position = UDim2.fromOffset(18, 0)
		icon(
			iconName,
			22,
			color,
			{ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), ZIndex = 3, Parent = b }
		)
		b.Activated:Connect(onClick)
		return b
	end
	ui.swarmBtn = metaButton("Swarm", "РОЙ", "hive", C.violet, 2, function()
		MetaMenus.showSwarm()
	end)
	ui.logBtn = metaButton("Log", "ЖУРНАЛ", "shield", C.orange, 3, function()
		MetaMenus.showLog()
	end)
	ui.boardsBtn = metaButton("Boards", "РЕЙТИНГ", "crown", C.gold, 4, function()
		MetaMenus.showBoards()
	end)
	ui.upgradesBtn.Label.Position = UDim2.fromOffset(22, 0)
	icon(
		"level",
		24,
		C.lime,
		{ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 20, 0.5, 0), ZIndex = 3, Parent = ui.upgradesBtn }
	)
	ui.upgradesBadge = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = C.pink,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.ink, Thickness = 2 },
		ZIndex = 5,
		Visible = false,
		Parent = ui.upgradesBtn,
	})
	ui.upgradesBtn.Activated:Connect(function()
		Menus.showUpgrades()
	end)
	-- Bottom right: PLAY
	ui.play, ui.playLabel = Theme.button("В БОЙ", {
		Name = "Play",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, -26),
		Size = UDim2.fromOffset(330, 92),
		TextSize = 34,
	}, "primary")
	ui.play.Parent = safe
	ui.playLabel.Position = UDim2.fromOffset(26, 0)
	ui.playIcon = icon(
		"play",
		34,
		C.ink,
		{ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 34, 0.5, 0), ZIndex = 3, Parent = ui.play }
	)
	ui.playGlow = new("UIStroke", {
		Color = C.lime,
		Thickness = 6,
		Transparency = 0.6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = ui.play,
	})
	ui.playStatus = label("", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, 0),
		Size = UDim2.fromOffset(330, 20),
		FontFace = F.bodyBold,
		TextSize = 16,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = safe,
	})
	ui.play.Activated:Connect(function()
		if amReady then
			send("unready")
			Audio.play("ui", 0.8, 0.85)
		else
			send("ready", selectedWeapon)
			Audio.play("level", 0.7, 1.1)
		end
	end)
	-- DD-052: this panel is the launch pad of the base; back to walking the base
	ui.back, ui.backLabel = Theme.button("‹  НА БАЗУ", {
		Name = "Back",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -346, 1, -36),
		Size = UDim2.fromOffset(190, 64),
		TextSize = 16,
	})
	ui.back.Parent = safe
	ui.back.Activated:Connect(function()
		Audio.play("ui", 0.8, 0.9)
		Menus.closeLaunch()
	end)
	ui.huntPrev.Activated:Connect(function()
		Menus.stepHunt(-1)
	end)
	ui.huntNext.Activated:Connect(function()
		Menus.stepHunt(1)
	end)
end

local function unlockedOps(): { string }
	local out = {}
	for _, id in Ops.Order do
		if profile and (profile.ops[id] or 0) >= 1 then
			table.insert(out, id)
		end
	end
	if #out == 0 then
		out = { "O01" }
	end
	return out
end

function Menus.stepHunt(delta: number)
	if not lobbyState then
		return
	end
	local list = unlockedOps()
	local i = table.find(list, lobbyState.op) or 1
	local nextId = list[(i - 1 + delta) % #list + 1]
	if nextId and nextId ~= lobbyState.op then
		send("op", nextId)
		Audio.play("uiHover")
	end
end

local function weaponState(id: string): (string, number?)
	-- "owned" | "buy" (blueprint, price) | "locked"
	if profile and profile.weapons[id] then
		return "owned"
	end
	if profile and profile.blueprints and profile.blueprints[id] then
		return "buy", Defs.Weapons[id].cost
	end
	return "locked"
end

local function weaponCard(id: string, order: number)
	local w = Defs.Weapons[id]
	local state, price = weaponState(id)
	local selected = selectedWeapon == id
	local card = new("TextButton", {
		Name = id,
		Size = UDim2.fromOffset(250, 146),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = if selected then 0.05 else 0.3,
		Text = "",
		Corner = 18,
		LayoutOrder = order,
		Stroke = {
			Color = if selected then C.lime else C.white,
			Transparency = if selected then 0 else 0.85,
			Thickness = if selected then 2.5 else 1,
		},
		Parent = ui.weapons,
	})
	local scale = new("UIScale", { Parent = card })
	local vpHolder = new("Frame", { Position = UDim2.fromOffset(6, 2), Size = UDim2.new(1, -12, 0, 88), Parent = card })
	local vp = Preview.weapon(vpHolder, id, false, { spin = selected, zoom = 0.62, pitch = 0.18 })
	if state ~= "owned" then
		vp.ImageTransparency = 0.55
		vp.ImageColor3 = Color3.fromRGB(120, 110, 150)
	end
	label(w.name, {
		Position = UDim2.fromOffset(16, 92),
		Size = UDim2.new(1, -32, 0, 22),
		FontFace = F.display,
		TextSize = 14,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if state == "owned" then C.text else C.dim,
		Parent = card,
	}).Parent =
		card
	local sub = if state == "owned"
		then w.tagline or ""
		elseif state == "buy" then "Чертёж получен"
		else "Откроется: победа в «" .. Ops.get(Defs.Blueprints[id] or "O02").name .. "»"
	label(sub, {
		Position = UDim2.fromOffset(16, 114),
		Size = UDim2.new(1, -32, 0, 26),
		FontFace = F.body,
		TextSize = 11,
		TextWrapped = true,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	if state == "locked" then
		icon("lock", 22, C.dim, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Parent = card })
	elseif state == "buy" then
		local affordable = profile and profile.scrap >= price
		local buy, buyLabel = Theme.button("КУПИТЬ  " .. price, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 10),
			Size = UDim2.fromOffset(130, 34),
			TextSize = 13,
		}, if affordable then "primary" else "ghost")
		buy.Parent = card
		if not affordable then
			buyLabel.TextColor3 = C.dim
		end
		buy.Activated:Connect(function()
			if affordable then
				send("buyWeapon", id)
				Audio.play("level", 0.8, 1.2)
			else
				Audio.play("warn", 0.5)
			end
		end)
	elseif selected then
		local tag = new("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = C.lime,
			Corner = UDim.new(1, 0),
			Parent = card,
		})
		icon(
			"check",
			18,
			C.ink,
			{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = tag }
		)
	end
	card.MouseEnter:Connect(function()
		tween(scale, 0.15, { Scale = 1.03 })
	end)
	card.MouseLeave:Connect(function()
		tween(scale, 0.2, { Scale = 1 })
	end)
	card.Activated:Connect(function()
		if state == "owned" and selectedWeapon ~= id then
			selectedWeapon = id
			send("weapon", id)
			Audio.play("equip", 0.7)
			Menus.refreshLobby()
		end
	end)
end

function Menus.refreshLobby()
	if not lobbyState or not ui.lobby.Visible then
		return
	end
	local info = lobbyState
	local prof = profile
	local runs = prof and prof.runs or 0
	local op = Ops.get(info.op)
	local mode = info.mode or "hunt"
	local features = prof and prof.features or {}
	ui.huntTag.Text = if op.code == "C-A01" then "КОНТРАКТ" else "ВЫЛАЗКА " .. op.index
	ui.huntName.Text = op.name
	ui.huntBrief.Text = op.brief
	local list = unlockedOps()
	local isHost = info.host == myId
	-- tabs
	local tabCount = 1 + (if features.siege then 1 else 0) + (if features.raids then 1 else 0)
	ui.tabs.Visible = tabCount > 1
	ui.tabButtons.siege.button.Visible = features.siege == true
	ui.tabButtons.raid.button.Visible = features.raids == true
	-- DD-082 (owner playtest): every mode wears its own colour — tab, card edge and tag — so a defence
	-- never reads as another sortie
	for key, t in ui.tabButtons do
		local on = key == mode
		local col = MODE_COLOR[key] or C.lime
		t.button.BackgroundColor3 = if on then col else C.ink
		t.button.BackgroundTransparency = if on then 0 else 0.25
		t.label.TextColor3 = if on then C.ink else col
		t.button.Active = isHost
	end
	local modeCol = MODE_COLOR[mode] or C.lime
	ui.huntTag.TextColor3 = modeCol
	local stroke = ui.hunt:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = modeCol
		stroke.Transparency = 0.2
		stroke.Thickness = 2.5
	end
	ui.hunt.Position = UDim2.fromOffset(0, if ui.tabs.Visible then 176 else 134)
	-- anomaly of the day (hunts from the third one on, sieges)
	local anomaly = nil
	for _, a in Meta.Anomalies do
		if a.id == info.anomaly then
			anomaly = a
		end
	end
	local showAnomaly = anomaly ~= nil and ((mode == "hunt" and op.index >= 3) or mode == "siege")
	ui.anomaly.Visible = showAnomaly
	if showAnomaly then
		ui.anomalyText.Text = "АНОМАЛИЯ: " .. anomaly.name .. string.format("  ·  ×%.2f", anomaly.reward)
		ui.anomaly.BackgroundColor3 = anomaly.color
		ui.anomalyText.TextColor3 = anomaly.color
	end
	ui.modeRow.Visible = mode ~= "hunt"
	ui.huntWhy.Visible = mode == "hunt"
	-- Rebuild the action row only when its content changes: lobby state arrives 4×/s and a rebuilt
	-- button swallows the click in progress.
	local rowKey = mode .. "|" .. tostring(isHost) .. "|" .. tostring(info.target and info.target.uid) .. "|"
	for _, c in info.candidates or {} do
		rowKey ..= tostring(c.uid) .. ","
	end
	for slot in info.outpost or {} do
		rowKey ..= "s" .. tostring(slot)
	end
	local rebuildRow = rowKey ~= ui.modeRowKey
	ui.modeRowKey = rowKey
	if rebuildRow then
		clear(ui.modeRow)
	end
	if mode == "siege" then
		local slots = info.outpost or {}
		local built = 0
		for _ in slots do
			built += 1
		end
		ui.huntTag.Text = "ОБОРОНА БУРА"
		ui.huntName.Text = "УРОВЕНЬ " .. (info.siege or 1)
		ui.huntBrief.Text = string.format(
			"Рой идёт на шум бура: пять волн. Пока бур цел, канатка везёт ксенит в убежище. Турели из мастерской: %d/%d.",
			built,
			Meta.SocketCount
		)
		if rebuildRow then
			local b, bl = Theme.button("СТРОИТЬ", { Size = UDim2.fromOffset(150, 40), TextSize = 13 }, "primary")
			b.Parent = ui.modeRow
			b.Activated:Connect(function()
				MetaMenus.showOutpost()
			end)
			if built == 0 then
				bl.Text = "ПОСТРОИТЬ ПЕРВОЕ"
				b.Size = UDim2.fromOffset(200, 40)
			end
		end
	elseif mode == "raid" then
		local t = info.target
		ui.huntTag.Text = "ВТОРЖЕНИЕ  ·  РЕЙТИНГ НАЛЁТЧИКА "
			.. (if prof and prof.raid then (prof.raid.attack or prof.raid.rating) else "—")
		ui.huntName.Text = if t then t.name else "Ищем аванпосты…"
		ui.huntBrief.Text = if t
			then string.format(
				"Чужой бур: пробей оборону и разрушь его за 4 минуты — ксенит с его канатки твой (мощь обороны %d, до %d ксенита). Хозяин ничего не теряет: это копия.",
				t.power or 0,
				Meta.raidRewardFor(t.power or 0, true)
			)
			else ""
		if rebuildRow and isHost and info.candidates and #info.candidates > 1 then
			for i, c in info.candidates do
				local on = t and c.uid == t.uid
				local b, bl = Theme.button(
					"мощь " .. tostring(c.power or 0),
					{ Size = UDim2.fromOffset(84, 40), TextSize = 13 },
					if on then "primary" else "ghost"
				)
				b.Parent = ui.modeRow
				b.Activated:Connect(function()
					send("raidPick", i)
					Audio.play("uiHover")
				end)
			end
			local r = Theme.button("ДРУГИЕ", { Size = UDim2.fromOffset(96, 40), TextSize = 12 })
			r.Parent = ui.modeRow
			r.Activated:Connect(function()
				send("raidRefresh")
			end)
		end
	end
	ui.huntPrev.Visible = mode == "hunt" and #list > 1 and isHost
	ui.huntNext.Visible = mode == "hunt" and #list > 1 and isHost
	local maxT = prof and prof.ops[info.op] or 1
	ui.threat.Visible = mode == "hunt" and maxT >= 2
	ui.threat.Position = UDim2.fromOffset(if #list > 1 and isHost then 132 else 24, 156)
	for i, d in ui.threatDots do
		d.button.Visible = i <= maxT
		local on = i == info.threat
		d.button.BackgroundColor3 = if on then C.orange else C.white
		d.button.BackgroundTransparency = if on then 0 else 0.9
		d.text.TextColor3 = if on then C.ink else C.text
	end
	ui.hunt.Size =
		UDim2.fromOffset(460, if ui.huntPrev.Visible or ui.threat.Visible or ui.modeRow.Visible then 214 else 160)
	-- Xenite + upgrades: after the first hunt
	ui.xenite.Visible = runs > 0 or (prof and prof.scrap > 0)
	ui.xeniteAmount.Text = Theme.commas(prof and prof.scrap or 0)
	ui.upgradesBtn.Visible = runs > 0
	ui.swarmBtn.Visible = features.swarm == true
	ui.logBtn.Visible = features.siege == true
	ui.boardsBtn.Visible = features.siege == true
	local harvest = prof and prof.outpost and prof.outpost.harvest or 0
	ui.harvest.Visible = harvest > 0
	ui.harvest.Label.Text = "СОБРАТЬ  +" .. harvest
	-- one summary of raids on the outpost per session
	if prof and prof.raidLog and #prof.raidLog > 0 and not ui.toastShown then
		ui.toastShown = true
		local held, lost = 0, 0
		for _, entry in prof.raidLog do
			if os.time() - (entry.t or 0) < 3 * 86400 then
				if entry.won then
					lost += 1
				else
					held += 1
				end
			end
		end
		if held + lost > 0 then
			ui.toastText.Text = string.format(
				"Налётов на бур: %d  ·  отбито %d (+%d ксенита)  ·  прорвано %d — ты ничего не потерял",
				held + lost,
				held,
				held * Meta.DefenseReward,
				lost
			)
			ui.toast.Visible = true
			task.delay(9, function()
				ui.toast.Visible = false
			end)
		end
	end
	local affordable = false
	if prof then
		for _, id in Defs.PerkOrder do
			local def = Defs.Perks[id]
			local r = prof.perks[id] or 0
			if id == "PK_OVERDRIVE" and not prof.s01 then
				continue
			end
			if def.costs[r + 1] and prof.scrap >= def.costs[r + 1] then
				affordable = true
			end
		end
	end
	ui.upgradesBadge.Visible = affordable
	-- Weapons: from the moment the second gun is on the horizon (after the first win)
	local shown = {}
	for _, id in SHOWN_WEAPONS do
		table.insert(shown, id)
	end
	for _, id in Defs.WeaponOrder do
		if prof and prof.weapons[id] and not table.find(shown, id) then
			table.insert(shown, id)
		end
	end
	local showWeapons = prof ~= nil and ((prof.ops.O02 or 0) >= 1 or #shown > 2 or prof.weapons.W_SCATTERGUN)
	ui.weapons.Visible = showWeapons
	ui.weaponsTitle.Visible = showWeapons
	if not (prof and prof.weapons[selectedWeapon]) then
		selectedWeapon = "W_ARC_RIFLE"
	end
	local y = ui.hunt.Position.Y.Offset + ui.hunt.Size.Y.Offset + 18
	ui.weaponsTitle.Position = UDim2.fromOffset(4, y)
	ui.weapons.Position = UDim2.fromOffset(0, y + 22)
	if showWeapons then
		local key = selectedWeapon .. "|" .. (prof and prof.scrap or 0) .. "|" .. table.concat(shown, ",")
		for _, id in shown do
			key ..= "|" .. weaponState(id)
		end
		if ui.weaponsKey ~= key then
			ui.weaponsKey = key
			clear(ui.weapons)
			for i, id in shown do
				weaponCard(id, i)
			end
		end
	end
	-- Squad
	local n = #info.players
	ui.squad.Visible = n > 1
	clear(ui.squad)
	local readyCount = 0
	for _, p in info.players do
		if p.ready then
			readyCount += 1
		end
		if n > 1 then
			local row = new("Frame", {
				Size = UDim2.fromOffset(250, 40),
				BackgroundColor3 = C.ink,
				BackgroundTransparency = 0.25,
				Corner = UDim.new(1, 0),
				Stroke = { Color = if p.ready then C.lime else C.white, Transparency = if p.ready then 0.3 else 0.85 },
				Parent = ui.squad,
			})
			label(p.name .. (if p.id == info.host then "  ★" else ""), {
				Position = UDim2.fromOffset(16, 0),
				Size = UDim2.new(1, -60, 1, 0),
				FontFace = F.bodyBold,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = row,
			})
			if p.ready then
				icon(
					"check",
					18,
					C.lime,
					{ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Parent = row }
				)
			end
		end
	end
	-- Play button
	ui.playLabel.Text = if amReady then "ОТМЕНА" else "В БОЙ"
	ui.play.BackgroundColor3 = if amReady then C.ink else C.lime
	ui.playLabel.TextColor3 = if amReady then C.text else C.ink
	Icons.recolor(ui.playIcon, if amReady then C.text else C.ink)
	ui.playStatus.Text = if info.countdown
		then string.format(
			"Выход через %d…  ·  готовы %d/%d",
			math.ceil(info.countdown),
			readyCount,
			n
		)
		elseif n > 1 then string.format("Отряд: %d  ·  готовы %d/%d", n, readyCount, n)
		elseif runs == 0 then "Соло  ·  до 4 игроков"
		else "Соло"
end

function Menus.showLobby(info, id: number, dev: string)
	lobbyState = info
	myId = id
	device = dev
	amReady = false
	for _, p in info.players do
		if p.id == id then
			amReady = p.ready
			if p.weapon and profile and profile.weapons[p.weapon] then
				selectedWeapon = p.weapon
			end
		end
	end
	MetaMenus.setLobby(info)
	if ui.lobby.Visible then
		local k = math.max(if Theme.phone() then 0.52 else 0.72, viewportScale(Vector2.new(1280, 760)))
		ui.lobbyScale.Scale = k
		ui.lobbySafe.Size = UDim2.fromScale(1 / k, 1 / k)
		Menus.refreshLobby()
	end
end

-- The launch pad (hunt choice, weapons, В БОЙ): opened from the base station or button (DD-052).
function Menus.openLaunch()
	if ui.lobby.Visible or not lobbyState then
		return
	end
	ui.lobby.Visible = true
	ui.lobbySafe.Position = UDim2.fromOffset(-40, 0)
	tween(ui.lobbySafe, 0.6, { Position = UDim2.fromOffset(0, 0) })
	ui.logoScale.Scale = 1.15
	tween(ui.logoScale, 0.8, { Scale = 1 }, Enum.EasingStyle.Back)
	ui.weaponsKey = nil
	setBlur(0)
	Menus.showLobby(lobbyState, myId, device)
end

function Menus.closeLaunch()
	ui.lobby.Visible = false
end

-- Any full-screen window over the base (the player should not walk behind it).
function Menus.modalOpen(): boolean
	return ui.lobby.Visible
		or (ui.upgrades ~= nil and ui.upgrades.shade.Visible)
		or (ui.settings ~= nil and ui.settings.shade.Visible)
		or MetaMenus.anyVisible()
end

-- Window helpers for the camp menus (same look as every other window).
function Menus.lobbyState()
	return lobbyState
end

function Menus.helpers()
	return { send = send, modal = modal, clear = clear, gui = gui }
end

function Menus.selectedWeapon(): string
	return selectedWeapon
end

function Menus.showSettings()
	ui.settings.show()
end

function Menus.hideLobby()
	ui.lobby.Visible = false
	MetaMenus.hideAll()
	if ui.upgrades then
		ui.upgrades.shade.Visible = false
	end
	if ui.settings then
		ui.settings.shade.Visible = false
	end
end

function Menus.lobbyVisible(): boolean
	return ui.lobby.Visible
end

-- Upgrades (perks) ---------------------------------------------------------------------------------------
local function buildUpgrades()
	local m = modal("Upgrades", 860, 560, "УЛУЧШЕНИЯ", nil)
	ui.upgrades = m
	label(
		"Навсегда. Покупаются за Ксенит, который приносит каждая вылазка.",
		{
			Position = UDim2.fromOffset(28, 60),
			Size = UDim2.new(1, -56, 0, 20),
			FontFace = F.body,
			TextSize = 14,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 42,
			Parent = m.panel,
		}
	)
	ui.upgradesXenite, ui.upgradesXeniteAmount =
		xenitePill(m.panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -74, 0, 20), ZIndex = 42 })
	for _, d in ui.upgradesXenite:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 43
		end
	end
	ui.upgradesGrid = new("Frame", {
		Position = UDim2.fromOffset(28, 96),
		Size = UDim2.new(1, -56, 1, -120),
		ZIndex = 42,
		Parent = m.panel,
	})
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(190, 210),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.upgradesGrid,
	})
end

function Menus.refreshUpgrades()
	if not ui.upgrades or not profile then
		return
	end
	ui.upgradesXeniteAmount.Text = Theme.commas(profile.scrap)
	clear(ui.upgradesGrid)
	for i, id in Defs.PerkOrder do
		local def = Defs.Perks[id]
		local rank = profile.perks[id] or 0
		-- Progressive discovery: the Gravihammer perk appears once the Gravihammer itself is known.
		if id == "PK_OVERDRIVE" and not profile.s01 and rank == 0 then
			continue
		end
		local cost = def.costs[rank + 1]
		local maxed = cost == nil
		local can = not maxed and profile.scrap >= cost
		local tile = new("Frame", {
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = 0.35,
			Corner = 16,
			LayoutOrder = i,
			ZIndex = 42,
			Stroke = { Color = if can then def.color else C.white, Transparency = if can then 0.3 else 0.88 },
			Parent = ui.upgradesGrid,
		})
		local disc = Icons.disc(def.icon, 60, def.color, 43)
		disc.AnchorPoint = Vector2.new(0.5, 0)
		disc.Position = UDim2.new(0.5, 0, 0, 14)
		disc.Parent = tile
		label(def.name, {
			Position = UDim2.fromOffset(8, 80),
			Size = UDim2.new(1, -16, 0, 20),
			FontFace = F.display,
			TextSize = 14,
			ZIndex = 43,
			Parent = tile,
		})
		for k = 1, def.max do
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, (k - (def.max + 1) / 2) * 16, 0, 104),
				Size = UDim2.fromOffset(12, 5),
				BackgroundColor3 = if k <= rank then def.color else C.white,
				BackgroundTransparency = if k <= rank then 0 else 0.8,
				Corner = UDim.new(1, 0),
				ZIndex = 43,
				Parent = tile,
			})
		end
		local statText = if maxed
			then def.stat(rank)
			elseif rank > 0 then def.stat(rank) .. "  →  " .. def.stat(rank + 1)
			else def.stat(1)
		label(statText, {
			Position = UDim2.fromOffset(10, 116),
			Size = UDim2.new(1, -20, 0, 36),
			FontFace = F.bodyBold,
			TextSize = 13,
			TextWrapped = true,
			TextColor3 = if maxed then C.dim else C.text,
			ZIndex = 43,
			Parent = tile,
		})
		local b, bl = Theme.button(if maxed then "МАКС" else "◆ " .. cost, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -28, 0, 40),
			ZIndex = 43,
			TextSize = 15,
		}, if can then "primary" else "ghost")
		b.Parent = tile
		bl.ZIndex = 44
		Xenite.inline(bl)
		if not can then
			bl.TextColor3 = if maxed then C.lime else C.dim
		end
		b.Activated:Connect(function()
			if can then
				send("buyPerk", id)
				Audio.play("level", 0.8, 1.3)
			else
				Audio.play("warn", 0.4)
			end
		end)
	end
end

function Menus.showUpgrades()
	Menus.refreshUpgrades()
	ui.upgrades.show()
end

-- Settings -----------------------------------------------------------------------------------------------
local function buildSettings()
	local m = modal("Settings", 520, 466, "НАСТРОЙКИ", nil)
	ui.settings = m
	local names = { "НИЗКО", "СРЕДНЕ", "ВЫСОКО" }
	local rows = {
		{
			"Графика",
			"eye",
			function()
				return names[Settings.quality]
			end,
			function()
				Settings.set("quality", Settings.quality % 3 + 1)
			end,
		},
		{
			"Тряска экрана",
			"boom",
			function()
				return if Settings.shake then "ВКЛ" else "ВЫКЛ"
			end,
			function()
				Settings.set("shake", not Settings.shake)
			end,
		},
		{
			"Цифры урона",
			"burst",
			function()
				return if Settings.numbers then "ВКЛ" else "ВЫКЛ"
			end,
			function()
				Settings.set("numbers", not Settings.numbers)
			end,
		},
		-- DD-098: on a phone the row is the auto-aim (aim and fire at the nearest enemy by itself)
		{
			if Settings.touch then "Автоприцел и огонь" else "Помощь в прицеливании",
			"crosshair",
			function()
				local on = if Settings.touch then Settings.autoAim else Settings.aimAssist
				return if on then "ВКЛ" else "ВЫКЛ"
			end,
			function()
				if Settings.touch then
					Settings.set("autoAim", not Settings.autoAim)
				else
					Settings.set("aimAssist", not Settings.aimAssist)
				end
			end,
		},
		{
			"Музыка на базе",
			"note",
			function()
				return if Settings.homeMusic then "ВКЛ" else "ВЫКЛ"
			end,
			function()
				Settings.set("homeMusic", not Settings.homeMusic)
			end,
		},
	}
	for i, r in rows do
		local y = 84 + (i - 1) * 66
		local row = new("Frame", {
			Position = UDim2.fromOffset(24, y),
			Size = UDim2.new(1, -48, 0, 56),
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = 0.4,
			Corner = 14,
			ZIndex = 42,
			Parent = m.panel,
		})
		icon(
			r[2],
			24,
			C.dim,
			{ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), ZIndex = 43, Parent = row }
		)
		label(r[1], {
			Position = UDim2.fromOffset(54, 0),
			Size = UDim2.new(1, -200, 1, 0),
			FontFace = F.bodyBold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
			Parent = row,
		})
		local b, bl = Theme.button(r[3](), {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(130, 38),
			ZIndex = 43,
			TextSize = 13,
		})
		b.Parent = row
		bl.ZIndex = 44
		bl.TextColor3 = C.lime
		b.Activated:Connect(function()
			r[4]()
			bl.Text = r[3]()
			Audio.play("ui")
		end)
		Settings.onChanged(function()
			bl.Text = r[3]() -- the cabin's gramophone turns the music too
		end)
	end
end

-- Level-up cards ----------------------------------------------------------------------------------------
local CARD_W, CARD_H, CARD_GAP, ART_H = 256, 360, 22, 168

local function cardInfo(me, id: string)
	local def = Defs.Upgrades[id]
	if def then
		local rank = (me.ranks[id] or 0) + 1
		return def.name,
			def.icon,
			def.color,
			def.describe(rank),
			rank,
			(if rank > 1 then def.stat(rank - 1) .. "  →  " else "") .. def.stat(rank)
	end
	local fb = Defs.Fallbacks[id]
	return fb.name, fb.icon, fb.color, "", 0, fb.text
end

local function synergyFor(me, id: string)
	for _, sid in Defs.SynergyOrder do
		local syn = Defs.Synergies[sid]
		local a, b = syn.keys[1], syn.keys[2]
		if (id == a and me.ranks[b] and not me.ranks[a]) or (id == b and me.ranks[a] and not me.ranks[b]) then
			return syn
		end
	end
	return nil
end

local function buildOffer()
	local o = new("Frame", { Name = "Offer", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10, Parent = gui })
	ui.offer = o
	ui.offerShade = new(
		"Frame",
		{ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.bg, BackgroundTransparency = 0.4, ZIndex = 10, Parent = o }
	)
	local body = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1200, 640),
		ZIndex = 11,
		Parent = o,
	})
	ui.offerBody = body
	ui.offerScale = new("UIScale", { Parent = body })
	ui.offerTitle = label("НОВЫЙ УРОВЕНЬ", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.fromOffset(900, 56),
		FontFace = F.display,
		TextSize = 48,
		TextColor3 = C.gold,
		ZIndex = 12,
		Parent = body,
	})
	new("UIStroke", { Color = C.ink, Thickness = 3, Transparency = 0.3, Parent = ui.offerTitle })
	ui.offerTitleScale = new("UIScale", { Parent = ui.offerTitle })
	ui.offerSub = label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(900, 22),
		FontFace = F.bodyBold,
		TextSize = 16,
		TextColor3 = C.dim,
		ZIndex = 12,
		Parent = body,
	})
	ui.offerCards = {}
	for i = 1, 4 do
		local card = new("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(CARD_W, CARD_H),
			BackgroundColor3 = C.white,
			BackgroundTransparency = 0.02,
			Text = "",
			Corner = 20,
			ClipsDescendants = false,
			ZIndex = 12,
			Parent = body,
		})
		-- body: dark, washed with the upgrade colour at the top
		local cardGrad = new("UIGradient", { Rotation = 90, Parent = card })
		local stroke = new(
			"UIStroke",
			{ Thickness = 2.5, Color = C.white, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card }
		)
		local strokeGrad = new("UIGradient", { Rotation = 90, Parent = stroke })
		local scale = new("UIScale", { Parent = card })
		-- outer glow behind the card (a sibling under it), follows the card and grows with focus
		local aura = new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(CARD_W + 220, CARD_H + 200),
			Image = Icons.Tex.glow,
			ImageTransparency = 1,
			ZIndex = 11,
			Parent = body,
		})
		-- art panel: colour wash + hex cells + glow + ring + big icon
		local art = new("Frame", {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 0, ART_H),
			BackgroundColor3 = C.white,
			Corner = 15,
			ClipsDescendants = true,
			ZIndex = 12,
			Parent = card,
		})
		local artGrad = new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(0.7, 0.85),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = art,
		})
		local hex = new("ImageLabel", {
			Size = UDim2.new(1, 0, 0, 240),
			Image = Icons.Tex.hex,
			ScaleType = Enum.ScaleType.Crop,
			ImageTransparency = 0.55,
			ZIndex = 12,
			Parent = art,
		})
		local glow = new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, ART_H * 0.48),
			Size = UDim2.fromOffset(250, 250),
			Image = Icons.Tex.glow,
			ImageTransparency = 0.2,
			ZIndex = 12,
			Parent = art,
		})
		local core = new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, ART_H * 0.48),
			Size = UDim2.fromOffset(120, 120),
			Image = Icons.Tex.glow,
			ImageTransparency = 0.55,
			ZIndex = 12,
			Parent = art,
		})
		local halo = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 6 + ART_H * 0.48),
			Size = UDim2.fromOffset(126, 126),
			BackgroundTransparency = 1,
			Corner = UDim.new(1, 0),
			ZIndex = 13,
			Parent = card,
		})
		local haloStroke = new("UIStroke", { Thickness = 2, Transparency = 0.35, Parent = halo })
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.6),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Parent = haloStroke,
		})
		local iconHolder = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(96, 96),
			ZIndex = 14,
			Parent = halo,
		})
		local badge = new("Frame", {
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.lime,
			Corner = UDim.new(1, 0),
			ZIndex = 15,
			Parent = card,
		})
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = badge })
		local badgeText = label("НОВОЕ", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			FontFace = F.head,
			TextSize = 11,
			TextColor3 = C.ink,
			ZIndex = 16,
			Parent = badge,
		})
		local key = Theme.key(
			tostring(i),
			{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), ZIndex = 15 }
		)
		key.Parent = card
		for _, d in key:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 16
			end
		end
		-- rank pips: diamonds on the bottom edge of the art panel
		local pips = {}
		for k = 1, 3 do
			pips[k] = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, (k - 2) * 20, 0, ART_H - 6),
				Size = UDim2.fromOffset(11, 11),
				Rotation = 45,
				Corner = 2,
				Stroke = { Color = C.ink, Thickness = 1.5, Transparency = 0.2 },
				ZIndex = 15,
				Parent = card,
			})
		end
		local name = label("", {
			Position = UDim2.fromOffset(14, ART_H + 12),
			Size = UDim2.new(1, -28, 0, 30),
			FontFace = F.display,
			TextSize = 22,
			TextScaled = true,
			ZIndex = 13,
			Parent = card,
		})
		new("UITextSizeConstraint", { MaxTextSize = 22, Parent = name })
		new("UIStroke", { Color = C.ink, Thickness = 1.5, Transparency = 0.3, Parent = name })
		local divider = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, ART_H + 46),
			Size = UDim2.new(1, -40, 0, 2),
			ZIndex = 13,
			Parent = card,
		})
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = divider,
		})
		local statPill = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, ART_H + 56),
			Size = UDim2.new(1, -28, 0, 30),
			BackgroundTransparency = 0.82,
			Corner = UDim.new(1, 0),
			ZIndex = 13,
			Parent = card,
		})
		local statStroke = new("UIStroke", { Thickness = 1, Transparency = 0.55, Parent = statPill })
		local stat = label("", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -18, 1, -6),
			FontFace = F.display,
			TextSize = 17,
			TextScaled = true,
			ZIndex = 14,
			Parent = statPill,
		})
		new("UITextSizeConstraint", { MaxTextSize = 17, Parent = stat })
		local desc = label("", {
			Position = UDim2.fromOffset(16, ART_H + 96),
			Size = UDim2.new(1, -32, 1, -(ART_H + 104)),
			FontFace = F.body,
			TextSize = 15,
			TextWrapped = true,
			TextColor3 = C.dim,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 13,
			Parent = card,
		})
		local banOverlay = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.red,
			BackgroundTransparency = 0.6,
			Corner = 20,
			Visible = false,
			ZIndex = 20,
			Parent = card,
		})
		icon("banish", 64, C.white, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.4),
			ZIndex = 21,
			Parent = banOverlay,
		})
		label("ИЗГНАТЬ", {
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 40),
			FontFace = F.display,
			TextSize = 26,
			ZIndex = 21,
			Parent = banOverlay,
		})
		-- DD-051 guided first card: the others are shown but closed this once
		local lockShade = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.bg,
			BackgroundTransparency = 0.3,
			Corner = 20,
			Visible = false,
			ZIndex = 20,
			Parent = card,
		})
		icon("lock", 44, C.dim, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.36),
			ZIndex = 21,
			Parent = lockShade,
		})
		label("В СЛЕДУЮЩИЙ РАЗ", {
			Position = UDim2.fromScale(0, 0.47),
			Size = UDim2.new(1, 0, 0, 22),
			FontFace = F.head,
			TextSize = 14,
			TextColor3 = C.dim,
			ZIndex = 21,
			Parent = lockShade,
		})
		-- ribbon + bouncing pointer over the guided card
		local guide = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 16),
			Size = UDim2.fromOffset(CARD_W + 30, 30),
			BackgroundColor3 = C.gold,
			Corner = UDim.new(1, 0),
			Visible = false,
			ZIndex = 22,
			Parent = card,
		})
		label("ВОЗЬМИ ЭТО", {
			Size = UDim2.fromScale(1, 1),
			FontFace = F.head,
			TextSize = 15,
			TextColor3 = C.ink,
			ZIndex = 23,
			Parent = guide,
		})
		local guideArrow = label("▲", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(30, 20),
			FontFace = F.head,
			TextSize = 18,
			TextColor3 = C.gold,
			ZIndex = 23,
			Parent = guide,
		})
		local c = {
			card = card,
			cardGrad = cardGrad,
			stroke = stroke,
			strokeGrad = strokeGrad,
			scale = scale,
			aura = aura,
			art = art,
			artGrad = artGrad,
			hex = hex,
			glow = glow,
			core = core,
			halo = halo,
			haloStroke = haloStroke,
			iconHolder = iconHolder,
			badge = badge,
			badgeText = badgeText,
			key = key,
			name = name,
			pips = pips,
			divider = divider,
			statPill = statPill,
			statStroke = statStroke,
			stat = stat,
			desc = desc,
			banOverlay = banOverlay,
			lockShade = lockShade,
			guide = guide,
			guideArrow = guideArrow,
			lift = 0,
		}
		card.MouseEnter:Connect(function()
			offerFocus = i
			Audio.play("uiHover")
		end)
		card.Activated:Connect(function()
			Menus.pick(i)
		end)
		ui.offerCards[i] = c
	end
	-- build row + reroll / banish
	ui.offerBuild = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 500),
		Size = UDim2.fromOffset(800, 44),
		ZIndex = 12,
		Parent = body,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		},
	})
	local actions = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 560),
		Size = UDim2.fromOffset(600, 46),
		ZIndex = 12,
		Parent = body,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
		},
	})
	ui.rerollBtn, ui.rerollLabel =
		Theme.button("ПЕРЕБРОС", { Size = UDim2.fromOffset(200, 46), ZIndex = 12, TextSize = 14 })
	ui.rerollBtn.Parent = actions
	ui.rerollLabel.ZIndex = 13
	ui.banishBtn, ui.banishLabel =
		Theme.button("ИЗГНАТЬ", { Size = UDim2.fromOffset(200, 46), ZIndex = 12, TextSize = 14 })
	ui.banishBtn.Parent = actions
	ui.banishLabel.ZIndex = 13
	ui.rerollBtn.Activated:Connect(function()
		if currentOfferId then
			send("reroll")
			Audio.play("uiHover", 1, 0.8)
		end
	end)
	ui.banishBtn.Activated:Connect(function()
		banishMode = not banishMode
		Menus.refreshOfferModes()
		Audio.play("ui")
	end)
end

function Menus.refreshOfferModes()
	local me = ui.offerMe
	if not me then
		return
	end
	ui.rerollBtn.Visible = (me.rerolls or 0) > 0 and not offerLock
	ui.rerollLabel.Text = "ПЕРЕБРОС  " .. (me.rerolls or 0)
	ui.banishBtn.Visible = (me.banishes or 0) > 0 and not offerLock
	ui.banishLabel.Text = if banishMode then "ОТМЕНА" else "ИЗГНАТЬ  " .. (me.banishes or 0)
	for i, c in ui.offerCards do
		local id = me.offer and me.offer.choices[i]
		local allowed = id and Defs.Upgrades[id] and not me.ranks[id]
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
	if offerLock and index ~= offerLock then
		-- closed this once: nudge toward the guided card
		Audio.play("warn", 0.5, 1.4)
		c.scale.Scale = 0.96
		tween(c.scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		offerFocus = offerLock
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
	c.scale.Scale = 1.12
	tween(c.scale, 0.25, { Scale = 1.06 }, Enum.EasingStyle.Back)
	for j, other in ui.offerCards do
		if j ~= index and other.card.Visible then
			tween(other.card, 0.2, { BackgroundTransparency = 0.6 })
		end
	end
	currentOfferId = nil
end

function Menus.focusMove(delta: number)
	if ui.offer.Visible then
		offerFocus = if offerLock then offerLock else math.clamp(offerFocus + delta, 1, ui.offerCount or 3)
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
	ui.offerSub.Text = if run.solo
		then "Выбери одно  ·  время остановлено"
		else string.format(
			"Выбери одно  ·  отряд ждёт  ·  %d с",
			math.max(0, math.ceil(Defs.Run.ChoiceTimeoutCoop - run.pauseClock))
		)
	if offer.lock then
		-- DD-075: the first hunt's three guided cards, each with what the player will see at once
		local guide = {
			UPG_MULTISHOT = "Пуль станет три — бери «Расщепление»",
			UPG_DETONATE = "Убитые враги будут взрываться и задевать соседей — бери «Детонатор»",
			UPG_SHIELD = "За убийства — энергощит: рой не пробьёт тебя сразу — бери «Барьер»",
		}
		local id = offer.choices[offer.lock]
		ui.offerSub.Text = (guide[id] or "Бери отмеченное улучшение")
			.. ". В следующих боях выбираешь сам"
	end
	if offer.id == ui.shownOfferId and ui.offer.Visible then
		Menus.refreshOfferModes()
		return
	end
	local fresh = not ui.offer.Visible
	ui.shownOfferId = offer.id
	currentOfferId = offer.id
	offerLock = offer.lock
	offerFocus = offerLock or 1
	banishMode = false
	ui.offer.Visible = true
	setBlur(16)
	ui.offerScale.Scale = viewportScale(if Theme.phone() then Vector2.new(880, 610) else Vector2.new(1200, 660))
	ui.offerSub.TextSize = if Theme.phone() then 21 else 16
	-- DD-085: on a phone the card words grow back to a readable size
	for _, c in ui.offerCards do
		local phone = Theme.phone()
		c.desc.TextSize = if phone then 20 else 15
		c.stat.TextSize = if phone then 21 else 17
		local cap = c.stat:FindFirstChildOfClass("UITextSizeConstraint")
		if cap then
			cap.MaxTextSize = c.stat.TextSize
		end
	end
	ui.offerTitle.Text = "УРОВЕНЬ "
		.. run.level
		.. (
			if me.pending > 1
				then string.format('  <font size="22" color="#B8A6DA">ещё +%d</font>', me.pending - 1)
				else ""
		)
	if fresh then
		ui.offerTitleScale.Scale = 1.5
		tween(ui.offerTitleScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		ui.offerShade.BackgroundTransparency = 1
		tween(ui.offerShade, 0.25, { BackgroundTransparency = 0.4 })
	end
	local count = #offer.choices
	ui.offerCount = count
	local simple = run.op == "O01"
	for i, c in ui.offerCards do
		local id = offer.choices[i]
		c.card.Visible = id ~= nil
		c.aura.Visible = id ~= nil
		if id then
			local name, iconName, color, text, rank, stat = cardInfo(me, id)
			c.name.Text = name
			clear(c.iconHolder)
			icon(iconName, 96, color, { ZIndex = 15, Parent = c.iconHolder })
			local deep = C.ink:Lerp(color, 0.16)
			c.cardGrad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, deep),
				ColorSequenceKeypoint.new(0.55, C.ink),
				ColorSequenceKeypoint.new(1, C.ink),
			})
			c.strokeGrad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color:Lerp(C.white, 0.45)),
				ColorSequenceKeypoint.new(0.45, color),
				ColorSequenceKeypoint.new(1, color:Lerp(C.ink, 0.6)),
			})
			c.art.BackgroundColor3 = color
			c.hex.ImageColor3 = color
			c.glow.ImageColor3 = color
			c.core.ImageColor3 = color:Lerp(C.white, 0.6)
			c.aura.ImageColor3 = color
			c.haloStroke.Color = color
			c.divider.BackgroundColor3 = color
			c.statPill.BackgroundColor3 = color
			c.statStroke.Color = color
			c.stat.Text = stat
			c.stat.TextColor3 = color:Lerp(C.white, 0.25)
			c.statPill.Visible = stat ~= ""
			c.desc.Text = text
			c.key.Visible = device == "pc"
			c.badgeText.Text = if rank == 0 then "БОНУС" elseif rank == 1 then "НОВОЕ" else "РАНГ " .. rank
			c.badge.BackgroundColor3 = if rank == 0 then C.dim elseif rank == 1 then C.lime else C.gold
			for k = 1, 3 do
				c.pips[k].Visible = rank > 0
				c.pips[k].BackgroundColor3 = if k <= rank then color:Lerp(C.white, 0.2) else C.ink
				c.pips[k].BackgroundTransparency = if k <= rank then 0 else 0.2
			end
			local syn = if simple then nil else synergyFor(me, id)
			if syn then
				c.desc.Text = text .. '\n<font color="#C9A2FF"><b>+ ' .. syn.name .. ":</b> " .. syn.text .. "</font>"
			end
			c.lockShade.Visible = offerLock ~= nil and i ~= offerLock
			c.guide.Visible = offerLock == i
			local x = (i - (count + 1) / 2) * (CARD_W + CARD_GAP)
			c.card.BackgroundTransparency = 0.04
			c.card.Position = UDim2.new(0.5, x, 0, 170)
			c.scale.Scale = 0.7
			c.lift = 0
			task.delay((i - 1) * 0.07, function()
				tween(c.scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
				tween(c.card, 0.35, { Position = UDim2.new(0.5, x, 0, 128) })
			end)
		end
	end
	ui.offerBuild.Position = UDim2.new(0.5, 0, 0, 128 + CARD_H + 60) -- below the guided card's «ВОЗЬМИ ЭТО» ribbon
	clear(ui.offerBuild)
	for _, id in Defs.UpgradeOrder do
		if me.ranks[id] then
			local def = Defs.Upgrades[id]
			local slot = new("Frame", {
				Size = UDim2.fromOffset(40, 40),
				BackgroundColor3 = C.ink,
				BackgroundTransparency = 0.2,
				Corner = 10,
				Stroke = { Color = def.color, Transparency = 0.4 },
				ZIndex = 12,
				Parent = ui.offerBuild,
			})
			icon(def.icon, 24, def.color, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.45),
				ZIndex = 13,
				Parent = slot,
			})
			label(tostring(me.ranks[id]), {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -3, 1, 0),
				Size = UDim2.fromOffset(12, 12),
				FontFace = F.num,
				TextSize = 10,
				TextColor3 = def.color,
				ZIndex = 13,
				Parent = slot,
			})
		end
	end
	Menus.refreshOfferModes()
	if fresh then
		Audio.play("level")
		task.delay(0.08, function()
			Audio.play("level", 0.8, 1.26)
		end)
		task.delay(0.16, function()
			Audio.play("level", 0.8, 1.5)
		end)
	end
end

function Menus.hideOffer()
	if ui.offer.Visible then
		ui.offer.Visible = false
		ui.shownOfferId = nil
		currentOfferId = nil
		offerLock = nil
		banishMode = false
		if not (ui.results and ui.results.Visible) then
			setBlur(0)
		end
	end
end

function Menus.offerVisible(): boolean
	return ui.offer.Visible
end

-- Splash and flash ---------------------------------------------------------------------------------------
local function buildSplash()
	local s =
		new("Frame", { Name = "Splash", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 30, Parent = gui })
	ui.splash = s
	ui.flash = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BackgroundColor3 = C.white,
		ZIndex = 30,
		Parent = s,
	})
	ui.splashModel = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(420, 220),
		ZIndex = 31,
		Parent = s,
	})
	ui.splashTitle = label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(1, 0, 0, 80),
		FontFace = F.display,
		TextSize = 64,
		TextColor3 = C.gold,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = C.ink,
		ZIndex = 31,
		Parent = s,
	})
	ui.splashSub = label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.new(0.6, 0, 0, 60),
		FontFace = F.bodyBold,
		TextSize = 20,
		TextWrapped = true,
		ZIndex = 31,
		Parent = s,
	})
	ui.splashScale = new("UIScale", { Parent = ui.splashTitle })
end

function Menus.evolveSplash(evoId: string)
	local evo = Defs.Evolutions[evoId]
	if not evo then
		return
	end
	ui.splash.Visible = true
	ui.splashEvolving = true
	clear(ui.splashModel)
	Preview.weapon(ui.splashModel, evo.weapon, true, { spin = true, zoom = 0.55, pitch = 0.2 }).ZIndex = 31
	ui.splashModel.Visible = true
	ui.flash.BackgroundTransparency = 0
	tween(ui.flash, 0.6, { BackgroundTransparency = 1 })
	ui.splashTitle.Text = evo.name
	ui.splashTitle.TextColor3 = evo.color
	ui.splashSub.Text = evo.text
	ui.splashScale.Scale = 2.2
	ui.splashTitle.TextTransparency = 1
	tween(ui.splashScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(ui.splashTitle, 0.3, { TextTransparency = 0 })
	ui.splashSub.TextTransparency = 1
	tween(ui.splashSub, 0.6, { TextTransparency = 0 })
	task.delay(2.4, function()
		tween(ui.splashTitle, 0.4, { TextTransparency = 1 })
		tween(ui.splashSub, 0.4, { TextTransparency = 1 })
		task.wait(0.42)
		ui.splashModel.Visible = false
		ui.splash.Visible = false
		ui.splashEvolving = false
	end)
end

function Menus.whiteFlash(amount: number)
	ui.splash.Visible = true
	if not ui.splashEvolving then
		ui.splashTitle.TextTransparency = 1
		ui.splashSub.TextTransparency = 1
		ui.splashModel.Visible = false
	end
	ui.flash.BackgroundTransparency = 1 - amount
	tween(ui.flash, 0.4, { BackgroundTransparency = 1 })
	task.delay(0.42, function()
		if not ui.splashEvolving then
			ui.splash.Visible = false
		end
	end)
end

-- Results ---------------------------------------------------------------------------------------------------
local function buildResults()
	local r =
		new("Frame", { Name = "Results", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, Parent = gui })
	ui.results = r
	ui.resShade = new(
		"Frame",
		{ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.bg, BackgroundTransparency = 0.3, ZIndex = 20, Parent = r }
	)
	local body = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1200, 740),
		ZIndex = 21,
		Parent = r,
	})
	ui.resScale = new("UIScale", { Parent = body })
	-- DD-082 (owner playtest: «много всего, непонятно куда смотреть»): the centre column keeps what
	-- matters — the verdict, the loot, what opened, what to do next; the numbers sit in a side column.
	ui.resList = new("Frame", {
		Position = UDim2.fromOffset(230, 0),
		Size = UDim2.new(0, 740, 1, -110),
		ZIndex = 21,
		Parent = body,
		List = { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 14) },
	})
	ui.resTag = label("", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = F.head,
		TextSize = 14,
		TextColor3 = C.dim,
		ZIndex = 22,
		Parent = ui.resList,
	})
	ui.resTitle = label("", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 80),
		FontFace = F.display,
		TextSize = 70,
		ZIndex = 22,
		Parent = ui.resList,
	})
	new("UIStroke", { Color = C.ink, Thickness = 4, Transparency = 0.25, Parent = ui.resTitle })
	ui.resTitleScale = new("UIScale", { Parent = ui.resTitle })
	ui.resReason = label("", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = F.bodyBold,
		TextSize = 17,
		ZIndex = 22,
		Parent = ui.resList,
	})
	-- the side column: the run's numbers, then the build (weapon + every card with its rank)
	ui.resSide = new("Frame", {
		Position = UDim2.fromOffset(0, 130),
		Size = UDim2.fromOffset(200, 560),
		ZIndex = 22,
		Parent = body,
		List = { Padding = UDim.new(0, 8) },
	})
	label("ИТОГИ", {
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 16),
		FontFace = F.head,
		TextSize = 12,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = ui.resSide,
	})
	ui.resStats = new("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 22,
		Parent = ui.resSide,
		List = { Padding = UDim.new(0, 6) },
	})
	ui.resBuild = new("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 22,
		Parent = ui.resSide,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			Wraps = true,
		},
	})
	ui.resReward = Theme.panel(
		{ LayoutOrder = 6, Size = UDim2.fromOffset(560, 92), CornerRadius = 20, ZIndex = 22, Parent = ui.resList },
		C.pink
	)
	-- the emblem either side of the amount: the reward is the currency, at a glance
	for _, side in { 0, 1 } do
		Xenite.icon(64, {
			AnchorPoint = Vector2.new(side, 0.5),
			Position = UDim2.new(side, if side == 0 then 18 else -18, 0.5, 0),
			ZIndex = 23,
			Parent = ui.resReward,
		})
	end
	ui.resRewardAmount = label("", {
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 46),
		FontFace = F.display,
		TextSize = 40,
		TextColor3 = C.pink,
		ZIndex = 23,
		Parent = ui.resReward,
	})
	-- where it goes: the cableway from the drill to the shelter (DD-065)
	ui.resRewardTag = label("С БУРА ПО КАНАТКЕ → В УБЕЖИЩЕ", {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(300, 14),
		FontFace = F.head,
		TextSize = 10,
		TextColor3 = C.lime,
		TextTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = ui.resReward,
	})
	ui.resRewardLines = label("", {
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = F.body,
		TextSize = 13,
		TextColor3 = C.dim,
		ZIndex = 23,
		Parent = ui.resReward,
	})
	ui.resUnlocks = new("Frame", {
		LayoutOrder = 7,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 22,
		Parent = ui.resList,
	})
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(320, 96),
		CellPadding = UDim2.fromOffset(12, 12),
		FillDirectionMaxCells = 2,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.resUnlocks,
	})
	ui.resGoal = Theme.panel(
		{ LayoutOrder = 8, Size = UDim2.fromOffset(560, 84), CornerRadius = 18, ZIndex = 22, Parent = ui.resList },
		C.lime
	)
	ui.resGoalIcon = new(
		"Frame",
		{ Position = UDim2.fromOffset(14, 20), Size = UDim2.fromOffset(44, 44), ZIndex = 23, Parent = ui.resGoal }
	)
	ui.resGoalHead = label("ДАЛЬШЕ", {
		Position = UDim2.fromOffset(70, 8),
		Size = UDim2.fromOffset(120, 14),
		FontFace = F.head,
		TextSize = 10,
		TextColor3 = C.lime,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = ui.resGoal,
	})
	ui.resGoalTitle = label("", {
		Position = UDim2.fromOffset(70, 22),
		Size = UDim2.new(1, -84, 0, 20),
		FontFace = F.display,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = ui.resGoal,
	})
	ui.resGoalText = label("", {
		Position = UDim2.fromOffset(70, 43),
		Size = UDim2.new(1, -84, 0, 34),
		FontFace = F.body,
		TextSize = 13,
		TextColor3 = C.dim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 23,
		Parent = ui.resGoal,
	})
	ui.resButton, ui.resButtonLabel = Theme.button("НА БАЗУ", {
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(320, 76),
		ZIndex = 22,
		TextSize = 26,
	}, "primary")
	ui.resButton.Parent = body
	ui.resButtonLabel.ZIndex = 23
	-- DD-053: back to the public camp instead of the squad's base
	ui.resCamp, ui.resCampLabel = Theme.button("В ЛАГЕРЬ", {
		Name = "ToCamp",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 176, 1, -32),
		Size = UDim2.fromOffset(170, 60),
		ZIndex = 22,
		TextSize = 16,
	})
	ui.resCamp.Parent = body
	ui.resCampLabel.ZIndex = 23
	ui.resCamp.Visible = false
	ui.resCamp.Activated:Connect(function()
		if not ui.resClicked then
			ui.resClicked = true
			send("camp")
			Audio.play("ui")
			ui.resCampLabel.Text = "ЛЕТИМ…"
		end
	end)
	-- squad contribution: everyone's part, not just kills
	ui.resSquad = new("Frame", {
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 34),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 22,
		Visible = false,
		Parent = ui.resList,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			Wraps = true,
		},
	})
	ui.resVotes = label("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(400, 18),
		FontFace = F.bodyBold,
		TextSize = 13,
		TextColor3 = C.dim,
		ZIndex = 22,
		Parent = body,
	})
	ui.resButton.Activated:Connect(function()
		if not ui.resClicked then
			ui.resClicked = true
			send("continue")
			Audio.play("ui")
			ui.resButtonLabel.Text = "ЖДЁМ ОТРЯД…"
		end
	end)
end

local function statTile(iconName: string, title: string, value: string, color: Color3, order: number)
	local t = Theme.panel({
		Size = UDim2.new(1, 0, 0, 46),
		CornerRadius = 14,
		LayoutOrder = order,
		ZIndex = 22,
		Parent = ui.resStats,
	})
	icon(
		iconName,
		20,
		color,
		{ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), ZIndex = 23, Parent = t }
	)
	local v = label(value, {
		Position = UDim2.fromOffset(42, 4),
		Size = UDim2.new(1, -50, 0, 22),
		FontFace = F.display,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = t,
	})
	label(title, {
		Position = UDim2.fromOffset(42, 26),
		Size = UDim2.new(1, -50, 0, 14),
		FontFace = F.head,
		TextSize = 10,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = t,
	})
	return v
end

local function unlockCard(iconName: string, tag: string, text: string, color: Color3, order: number)
	local t = Theme.panel({
		Size = UDim2.fromOffset(320, 96),
		CornerRadius = 20,
		LayoutOrder = order,
		ZIndex = 22,
		Parent = ui.resUnlocks,
	}, color)
	local disc = Icons.disc(iconName, 62, color, 23)
	disc.AnchorPoint = Vector2.new(0, 0.5)
	disc.Position = UDim2.new(0, 16, 0.5, 0)
	disc.Parent = t
	label(tag, {
		Position = UDim2.fromOffset(92, 18),
		Size = UDim2.new(1, -104, 0, 16),
		FontFace = F.head,
		TextSize = 12,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = t,
	})
	label(text, {
		Position = UDim2.fromOffset(92, 38),
		Size = UDim2.new(1, -104, 0, 44),
		FontFace = F.display,
		TextSize = 20,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 23,
		Parent = t,
	})
	local s = new("UIScale", { Scale = 0.6, Parent = t })
	task.delay(0.5 + order * 0.12, function()
		tween(s, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		Audio.play("level", 0.6, 1.4)
	end)
end

-- A chip in the results build strip: icon disc + short text; pops in after the stats.
local function buildChip(iconName: string, text: string, color: Color3, order: number)
	local chip = new("Frame", {
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.25,
		Corner = UDim.new(1, 0),
		Stroke = { Color = color, Transparency = 0.45, Thickness = 1.5 },
		LayoutOrder = order,
		ZIndex = 22,
		Parent = ui.resBuild,
	})
	new(
		"UIPadding",
		{ PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, if text ~= "" then 14 else 6), Parent = chip }
	)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chip,
	})
	local disc = new("Frame", {
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.8,
		Corner = UDim.new(1, 0),
		LayoutOrder = 1,
		ZIndex = 23,
		Parent = chip,
	})
	icon(
		iconName,
		20,
		color,
		{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 24, Parent = disc }
	)
	if text ~= "" then
		label(text, {
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			FontFace = F.head,
			TextSize = 13,
			TextColor3 = color,
			LayoutOrder = 2,
			ZIndex = 23,
			Parent = chip,
		})
	end
	local sc = new("UIScale", { Scale = 0, Parent = chip })
	task.delay(0.35 + order * 0.05, function()
		tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
end

-- After a loss (DD-082): what would have helped, from what the player can do right now.
local function defeatTip(result): (string, string, string)
	local scrap = profile and profile.scrap or 0
	local best = nil
	for _, id in Defs.PerkOrder do
		local def = Defs.Perks[id]
		local rank = (profile and profile.perks and profile.perks[id]) or 0
		local cost = def.costs[rank + 1]
		if cost and cost <= scrap and (not best or cost < best.cost) then
			best = { def = def, cost = cost, rank = rank }
		end
	end
	if best then
		return "heart",
			"В ОРУЖЕЙНОЙ: «" .. best.def.name .. "»",
			string.format(
				"Хватает ксенита (%d): %s — навсегда, в каждой вылазке.",
				best.cost,
				best.def.stat(best.rank + 1)
			)
	end
	if (result.mode or "hunt") == "siege" or result.op == "STRIKE" then
		return "crosshair",
			"ПОСТАВЬ ЕЩЁ ТУРЕЛЕЙ",
			"Каждая турель у бура стреляет вместе с тобой. Верстак в убежище."
	end
	return "burst",
		"НЕ СТОЙ НА МЕСТЕ",
		if Theme.phone()
			then "Рой окружает того, кто стоит. Рывок (кнопка » справа) — сквозь толпу; бери карты урона по площади."
			else "Рой окружает того, кто стоит. Рывок (ПРОБЕЛ) — сквозь толпу; бери карты урона по площади."
end

-- Count a label up from 0 for the "earned" feeling.
local function countUp(lbl: TextLabel, target: number, fmt: string, duration: number)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			local k = (os.clock() - t0) / duration
			k = 1 - (1 - k) ^ 3
			lbl.Text = string.format(fmt, Theme.commas(target * k))
			task.wait()
		end
		lbl.Text = string.format(fmt, Theme.commas(target))
	end)
end

function Menus.showResults(result, votes, id: number, reward, canCamp: boolean?)
	local n = #result.players
	local voted = 0
	for _, v in votes do
		if v then
			voted += 1
		end
	end
	ui.resVotes.Text = if n > 1 then string.format("Готовы %d/%d", voted, n) else ""
	-- The server re-sends the result table with every snapshot: compare by content, not identity.
	local resultKey = string.format("%s|%.2f|%d|%s", result.op, result.time, result.kills, tostring(result.victory))
	local rewardKey = if reward then tostring(reward.total) .. "|" .. tostring(reward.grant) else ""
	if ui.results.Visible and ui.shownResult == resultKey and ui.shownReward == rewardKey then
		return
	end
	local first = ui.shownResult ~= resultKey
	ui.shownResult = resultKey
	ui.shownReward = rewardKey
	Menus.hideOffer()
	ui.results.Visible = true
	setBlur(18)
	ui.resScale.Scale = resultsScale()
	-- DD-085: a phone keeps the centre column only (the numbers would be too small to read)
	local phone = Theme.phone()
	ui.resSide.Visible = not phone
	ui.resGoalText.TextSize = if phone then 18 else 13
	ui.resGoalTitle.TextSize = if phone then 21 else 17
	ui.resGoalText.Size = UDim2.new(1, -84, 0, if phone then 44 else 34)
	ui.resRewardLines.TextSize = if phone then 17 else 13
	ui.resReason.TextSize = if phone then 21 else 17
	ui.resGoal.Size = UDim2.fromOffset(if phone then 680 else 560, if phone then 104 else 84)
	local op = Ops.get(result.op)
	if first then
		ui.resClicked = false
		ui.resButtonLabel.Text = if n > 1 then "НА БАЗУ ОТРЯДА" else "НА БАЗУ"
		ui.resCampLabel.Text = "В ЛАГЕРЬ"
		ui.resTitleScale.Scale = 1.6
		tween(ui.resTitleScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
		ui.resShade.BackgroundTransparency = 1
		tween(ui.resShade, 0.5, { BackgroundTransparency = 0.3 })
		Audio.play(if result.victory then "evolve" else "warn", 0.7, if result.victory then 1.1 else 0.8)
	end
	local mode = result.mode or "hunt"
	if result.op == "STRIKE" then
		ui.resTag.Text = "ОБОРОНА БУРА  ·  ПЕРВЫЙ НАТИСК"
		ui.resTitle.Text = if result.victory then "НАТИСК ОТБИТ" else "БУР ПОВРЕЖДЁН"
	elseif mode == "siege" then
		ui.resTag.Text = "ОБОРОНА БУРА  ·  УРОВЕНЬ " .. (result.siege or 1)
		ui.resTitle.Text = if result.victory then "БУР ВЫСТОЯЛ" else "БУР ПАЛ"
	elseif mode == "raid" then
		ui.resTag.Text = "ВТОРЖЕНИЕ  ·  " .. (if result.raid then result.raid.name else "")
		ui.resTitle.Text = if result.victory
			then "ВТОРЖЕНИЕ УСПЕШНО"
			else "ОБОРОНА ВЫСТОЯЛА"
	else
		ui.resTag.Text = (if op.code == "C-A01" then "КОНТРАКТ" else "ВЫЛАЗКА " .. op.index)
			.. "  ·  "
			.. op.name
			.. (if (result.threat or 1) > 1 then "  ·  УГРОЗА " .. result.threat else "")
		ui.resTitle.Text = if result.victory then "ВЫЛАЗКА УДАЛАСЬ" else "ТЫ ПАЛ"
	end
	ui.resTitle.TextColor3 = if result.victory then C.lime else C.red
	ui.resReason.Text = if result.chapterEnd and result.victory
		then "Глава завершена. " .. result.reason
		else result.reason
	ui.resReason.TextColor3 = C.text
	-- stats
	clear(ui.resStats)
	local mine = nil
	for _, p in result.players do
		if p.id == id then
			mine = p
		end
	end
	local tv = statTile("timer", "ВРЕМЯ", Theme.fmtTime(result.time), C.cyan, 1)
	local kv = statTile("skull", if n > 1 then "ТВОИ УБИЙСТВА" else "УБИТО", "0", C.orange, 2)
	local dv = statTile("boom", "УРОН", "0", C.pink, 3)
	statTile(
		"burst",
		"ЛУЧШЕЕ КОМБО",
		if mine and (mine.bestCombo or 0) > 1 then "×" .. mine.bestCombo else "—",
		C.gold,
		4
	)
	statTile("level", "УРОВЕНЬ", tostring(result.level), C.lime, 5)
	countUp(kv, if mine then mine.kills else result.kills, "%s", 1.1)
	countUp(dv, if mine then mine.damage or 0 else 0, "%s", 1.3)
	tv.Text = Theme.fmtTime(result.time)
	ui.resCamp.Visible = canCamp == true
	-- squad contribution (DD-053): damage, kills and rescues of everyone
	clear(ui.resSquad)
	ui.resSquad.Visible = n > 1
	local awards = Showcase.awards(result.players)
	if n > 1 then
		for i, p in result.players do
			local chip = new("Frame", {
				Size = UDim2.fromOffset(0, 32),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = C.ink,
				BackgroundTransparency = 0.2,
				Corner = UDim.new(1, 0),
				Stroke = {
					Color = if p.id == id then C.lime else C.white,
					Transparency = if p.id == id then 0.4 else 0.85,
				},
				LayoutOrder = i,
				ZIndex = 23,
				Parent = ui.resSquad,
			})
			new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = chip })
			local parts = {
				tostring(p.name or "?"),
				Theme.commas(p.damage or 0) .. " урона",
				tostring(p.kills or 0) .. " убийств",
			}
			if (p.revives or 0) > 0 then
				table.insert(parts, tostring(p.revives) .. " спасений")
			end
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = chip,
			})
			label(table.concat(parts, "  ·  "), {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 32),
				FontFace = F.bodyBold,
				TextSize = 13,
				ZIndex = 24,
				Parent = chip,
			})
			for k, a in awards[p.id] or {} do
				icon(a[1], 16, C.gold, { LayoutOrder = k * 2, ZIndex = 24, Parent = chip })
				label(a[2], {
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 32),
					FontFace = F.head,
					TextSize = 12,
					TextColor3 = C.gold,
					LayoutOrder = k * 2 + 1,
					ZIndex = 24,
					Parent = chip,
				})
			end
		end
	end
	-- build strip
	clear(ui.resBuild)
	ui.resBuild.Visible = mine ~= nil
	if mine then
		local wdef = Defs.Weapons[mine.weapon]
		if wdef then
			local evo = mine.evolved ~= "" and Defs.Evolutions and Defs.Evolutions[mine.evolved]
			buildChip("star", if evo then evo.name else wdef.name, if evo then C.gold else C.text, 0)
		end
		for i, u in mine.upgrades or {} do
			local def = Defs.Upgrades[u[1]]
			if def then
				buildChip(def.icon, if u[2] > 1 then tostring(u[2]) else "", def.color, i)
			end
		end
	end
	-- reward
	ui.resReward.Visible = reward ~= nil
	if reward then
		countUp(ui.resRewardAmount, reward.total + (reward.grant or 0), "+%s КСЕНИТ", 1.3)
		local parts = {}
		local names = {
			skull = "за убийства",
			level = "за уровни",
			crown = "за победу",
			timer = "за стойкость",
			hive = "ульи",
		}
		for _, line in reward.lines or {} do
			if line[2] > 0 then
				table.insert(parts, "+" .. line[2] .. " " .. (names[line[1]] or ""))
			end
		end
		if reward.mult and reward.mult > 1.001 then
			table.insert(parts, string.format("×%.2f", reward.mult))
		end
		if reward.grant then
			table.insert(parts, "+" .. reward.grant .. " бонус первой победы")
		end
		if reward.bonus and reward.bonus > 1.001 then
			table.insert(parts, string.format("бонусы ×%.2f", reward.bonus))
		end
		if reward.light and reward.light > 0 then
			table.insert(parts, string.format("Свет Древа +%d%%", math.floor(reward.light * 5 + 0.5)))
		end
		if type(reward.mentor) == "table" and #reward.mentor > 0 then
			-- DD-088: a veteran who won beside a newcomer
			table.insert(parts, "наставник для " .. table.concat(reward.mentor, ", "))
		end
		ui.resRewardLines.Text = table.concat(parts, "   ·   ")
	end
	-- unlocks
	clear(ui.resUnlocks)
	local k = 0
	local decor = reward and Meta.decorById(reward.decor)
	if decor then
		-- DD-090: the week's decoration came home with this win
		k += 1
		unlockCard(decor.icon, "СЕЗОННОЕ УКРАШЕНИЕ", decor.name, C.gold, k)
	end
	for _, u in reward and reward.unlocked or {} do
		local kind = u[1]
		if kind == "op" then
			k += 1
			local nop = Ops.get(u[2])
			unlockCard(
				"pin",
				if nop.code == "C-A01" then "НОВЫЙ КОНТРАКТ" else "НОВАЯ ВЫЛАЗКА",
				nop.name,
				C.lime,
				k
			)
		elseif kind == "s01" then
			k += 1
			unlockCard("hammer", "НАВСЕГДА", "Громобой", C.cyan, k)
		elseif
			(kind == "research" or kind == "specimen")
			and Defs.Enemies[u[2]]
			-- DD-075: the first win keeps to what matters next (the shelter, the turret); the collection
			-- shows itself later
			and not (result.op == "O01" and (((profile and profile.winsByOp) or {}).O01 or 0) <= 1)
		then
			k += 1
			local stages = {
				"СИЛУЭТ В ПРОБИРКЕ",
				"ПОЛНЫЙ ЭКЗЕМПЛЯР",
				"ЭТАЛОН КОЛЛЕКЦИИ",
			}
			unlockCard(
				"hive",
				if kind == "specimen" then "НОВЫЙ ВИД В КОЛЛЕКЦИИ" else stages[u[3]],
				Defs.Enemies[u[2]].name,
				if u[3] == 3 then C.gold else C.lime,
				k
			)
		end
	end
	if reward and reward.siegeUp then
		k += 1
		unlockCard("threat", "ОБОРОНА БУРА", "Открыт уровень " .. reward.siegeUp, C.orange, k)
	end
	if reward and reward.capped then
		k += 1
		unlockCard(
			"timer",
			"БЕЗ НАГРАДЫ",
			if reward.capped == "pair"
				then "Этот бур уже приносил тебе ксенит сегодня"
				else "Лимит налётов с наградой на сегодня: " .. Meta.RaidDailyCap,
			C.dim,
			k
		)
	elseif reward and reward.rating then
		k += 1
		local d = reward.rating.delta
		unlockCard(
			"crown",
			"РЕЙТИНГ НАЛЁТЧИКА",
			if reward.rating.unrated
				then "Свежий снимок обороны — без рейтинга"
				else string.format("%s%d  →  %d", if d >= 0 then "+" else "", d, reward.rating.now),
			if d >= 0 then C.gold else C.red,
			k
		)
	end
	-- A first story win that opens a meta mode (the next hunt unlocking is the signal).
	local newly = {
		O02 = { "gear", "В УБЕЖИЩЕ", "Мастерская: оборона бура" },
		O03 = { "coil", "В УБЕЖИЩЕ", "Радиостанция и огород" },
		O04 = { "hive", "В УБЕЖИЩЕ", "Лаборатория с образцами" },
		O05 = { "skull", "НОВЫЙ РЕЖИМ", "Вторжения на чужие буры" },
	}
	for _, u in reward and reward.unlocked or {} do
		local f = u[1] == "op" and newly[u[2]]
		if f then
			k += 1
			unlockCard(f[1], f[2], f[3], C.violet, k)
		end
	end
	if result.victory then
		for wid, opId in Defs.Blueprints do
			if
				opId == result.op
				and table.find(SHOWN_WEAPONS, wid)
				and profile
				and not profile.weapons[wid]
				and first
			then
				k += 1
				unlockCard("star", "ЧЕРТЁЖ ОРУЖИЯ", Defs.Weapons[wid].name, C.gold, k)
			end
		end
	end
	ui.resUnlocks.Visible = k > 0
	-- DD-052: one nearest goal under the loot, so the next step is obvious before leaving the screen;
	-- after a loss, how to come back stronger instead (DD-082)
	local g = if result.victory then Goals.next(profile) else nil
	ui.resGoal.Visible = g ~= nil or not result.victory
	ui.resGoalHead.Text = if result.victory then "ДАЛЬШЕ" else "КАК СТАТЬ СИЛЬНЕЕ"
	if not result.victory then
		local ic, title, text = defeatTip(result)
		ui.resGoalTitle.Text = title
		ui.resGoalText.Text = text
		clear(ui.resGoalIcon)
		Icons.disc(ic, 44, C.gold, 23).Parent = ui.resGoalIcon
	elseif g then
		ui.resGoalTitle.Text = g.title
		ui.resGoalText.Text = g.text
		clear(ui.resGoalIcon)
		local col = if g.structure then Meta.Structures[g.structure].color else C.lime
		local d = Icons.disc(g.icon, 44, col, 23)
		d.Parent = ui.resGoalIcon
	end
end

function Menus.hideResults()
	if ui.results.Visible then
		ui.results.Visible = false
		setBlur(0)
	end
end

-- Notes: one short status line (countdown, waiting for first input, spectating, pause) -------------------
local function buildNotes()
	ui.note = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.2,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.lime, Transparency = 0.5, Thickness = 1.5 },
		Visible = false,
		ZIndex = 8,
		Parent = gui,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24), Parent = ui.note })
	ui.noteText = label("", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		FontFace = F.display,
		TextSize = 22,
		ZIndex = 9,
		Parent = ui.note,
	})
	ui.noteScale = new("UIScale", { Parent = ui.note })
end

function Menus.note(text: string?)
	ui.note.Visible = text ~= nil
	if text then
		ui.noteText.Text = text
		ui.noteScale.Scale = viewportScale(Vector2.new(1100, 760))
	end
end

-- Profile ------------------------------------------------------------------------------------------------
function Menus.setProfile(pub)
	profile = pub
	MetaMenus.setProfile(pub)
	if ui.upgrades and ui.upgrades.shade.Visible then
		Menus.refreshUpgrades()
	end
	ui.weaponsKey = nil
	Menus.refreshLobby()
end

function Menus.profile()
	return profile
end

-- Kept for callers from the old hub flow.
function Menus.setTab(_name: string) end

function Menus.init(playerGui: PlayerGui, sender)
	send = sender
	gui = new("ScreenGui", {
		Name = "SporeMenus",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets, -- (alone: IgnoreGuiInset beside it could undo it)
		DisplayOrder = 10,
		Parent = playerGui,
	})
	buildLobby()
	buildOffer()
	buildSplash()
	buildResults()
	buildNotes()
	buildUpgrades()
	buildSettings()
	MetaMenus.init({ send = send, modal = modal, icon = icon, clear = clear, xenitePill = xenitePill })
end

function Menus.update(dt: number)
	local now = os.clock()
	if gui.AbsoluteSize ~= lastMenuSize then
		lastMenuSize = gui.AbsoluteSize
		for _, m in modalWindows do
			if m.resize then
				m.resize(lastMenuSize)
			else
				m.scale.Scale = viewportScale(m.baseSize)
			end
		end
		ui.offerScale.Scale = viewportScale(if Theme.phone() then Vector2.new(880, 610) else Vector2.new(1200, 660))
		ui.resScale.Scale = resultsScale()
	end
	if ui.lobby.Visible then
		ui.playGlow.Transparency = 0.45 + math.sin(now * 3) * 0.25
		ui.playGlow.Thickness = 4 + math.sin(now * 3) * 2
	end
	if ui.offer.Visible then
		for i, c in ui.offerCards do
			if c.card.Visible then
				local target = if i == offerFocus and currentOfferId then 1 else 0
				if c.guide.Visible then
					target = 0.8 + math.sin(now * 4) * 0.2
					c.guideArrow.Position = UDim2.new(0.5, 0, 0, 4 - math.abs(math.sin(now * 5)) * 8)
				end
				c.lift += (target - c.lift) * math.min(1, dt * 14)
				c.stroke.Thickness = 2.5 + c.lift * 1.5
				c.stroke.Transparency = 0.3 - c.lift * 0.3
				c.aura.ImageTransparency = 1 - c.lift * 0.6
				c.aura.Position = c.card.Position + UDim2.fromOffset(0, CARD_H * 0.45)
				c.halo.Rotation = math.sin(now * 2 + i) * 4 * c.lift
				c.haloStroke.Transparency = 0.45 - c.lift * 0.35 + math.sin(now * 5 + i) * 0.08
				c.iconHolder.Position = UDim2.new(0.5, 0, 0.5, math.sin(now * 2.2 + i * 1.3) * (2 + c.lift * 2))
				c.glow.ImageTransparency = 0.3 - c.lift * 0.2 + math.sin(now * 3 + i) * 0.05
				c.core.ImageTransparency = 0.6 - c.lift * 0.25
			end
		end
	end
end

return Menus
