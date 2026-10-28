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
local Modules = require(Shared:WaitForChild("Modules"))
local Evolve = require(Shared:WaitForChild("Evolve"))
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

-- The results body (DD-108): a monitor's column (RES_DESK), a phone's two columns (RES_PHONE) under
-- Roblox's own top bar.
local RES_DESK = Vector2.new(760, 520)
local RES_PHONE = Vector2.new(820, 290) -- (DD-109, DD-110: narrower, so it is drawn bigger: it was width-bound)
local function resultsScale(): number
	if Theme.phone() then
		local vs = if gui and gui.AbsoluteSize.X > 0 then gui.AbsoluteSize else workspace.CurrentCamera.ViewportSize
		local ok, inset = pcall(function()
			return game:GetService("GuiService").TopbarInset.Max.Y
		end)
		local top = (if ok and inset then inset else 60) + 4
		return math.clamp(math.min((vs.X - 48) / RES_PHONE.X, (vs.Y - top - 16) / RES_PHONE.Y), 0.3, 1.25)
	end
	return viewportScale(Vector2.new(RES_DESK.X + 60, RES_DESK.Y + 60))
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
local lobbyPhoneLayout

-- DD-102: on a phone a window fills the screen's width at a readable size and scrolls down, instead of
-- shrinking whole into the screen's height (the owner's phone got 8-point words)
local function fitModal(m)
	local phone = Theme.phone()
	-- DD-107 (owner: «в идеале на один экран, чтоб помещалось на мобильных, без скроллов»): a window
	-- that knows a landscape phone layout (m.phoneSize + m.relayout) is laid out for it and scaled whole
	-- into the space under Roblox's buttons; the rest still fill the width and scroll
	if m.relayout and m.phone ~= phone then
		m.phone = phone
		-- (the header's lift below is undone first: relayout places from the window's own layout)
		for _, c in m.panel:GetChildren() do
			if c:GetAttribute("PhoneX0") ~= nil then
				c.Position = UDim2.new(
					c.Position.X.Scale,
					c:GetAttribute("PhoneX0"),
					c.Position.Y.Scale,
					c:GetAttribute("PhoneY0")
				)
				if c.Size.X.Scale > 0 then
					c.Size = UDim2.new(c.Size.X.Scale, c:GetAttribute("PhoneW0"), c.Size.Y.Scale, c.Size.Y.Offset)
				end
				c:SetAttribute("PhoneX0", nil)
			end
		end
		if m.headBand then
			m.headBand.Visible = false
		end
		m.panel.Size = if phone then UDim2.fromOffset(m.phoneSize.X, m.phoneSize.Y) else UDim2.fromOffset(m.w, m.h)
		m.relayout(phone)
	end
	if phone then
		local vs = if gui.AbsoluteSize.X > 0 then gui.AbsoluteSize else workspace.CurrentCamera.ViewportSize
		local k = math.clamp((vs.X - 16) / m.w, 0.5, 1)
		-- below Roblox's own buttons (top left), which this gui does not step around
		local ok, inset = pcall(function()
			return game:GetService("GuiService").TopbarInset.Max.Y
		end)
		local top = (if ok and inset then inset else 0) + 4
		if m.relayout then
			-- DD-110 (owner, the phone: windows «прижаты к кнопкам»): the window starts under Roblox's top
			-- bar, so its buttons never stand on it; the window's header (title, xenite, ×) goes up into
			-- the bar right of them, and the body moves up into the header's place
			local stripLeft, _, stripH = Theme.topStrip()
			local lift = stripH > 0
			local pw, ph = m.phoneSize.X, m.phoneSize.Y
			local kids = {}
			for _, c in m.panel:GetChildren() do
				if c:IsA("GuiObject") and c.Name ~= "HeadBand" then
					if c:GetAttribute("PhoneX0") == nil then
						c:SetAttribute("PhoneX0", c.Position.X.Offset)
						c:SetAttribute("PhoneY0", c.Position.Y.Offset)
						c:SetAttribute("PhoneW0", c.Size.X.Offset)
					end
					table.insert(kids, c)
				end
			end
			-- the header: what starts in the window's top 56 points; the cut: up to the body's top
			local function isHead(c: GuiObject): boolean
				local y = c:GetAttribute("PhoneY0") - c.AnchorPoint.Y * c.Size.Y.Offset
				return c.Position.Y.Scale == 0 and y < 56
			end
			local cut = 0
			if lift then
				local bodyTop = math.huge
				for _, c in kids do
					if c.Visible and c.Position.Y.Scale == 0 and not isHead(c) then
						bodyTop = math.min(bodyTop, c:GetAttribute("PhoneY0") - c.AnchorPoint.Y * c.Size.Y.Offset)
					end
				end
				cut = if bodyTop < math.huge then math.max(0, bodyTop - 16) else 0
			end
			local y0 = if lift then stripH + 4 else top
			local k = math.min(1, (vs.X - 40) / pw, (vs.Y - y0 - 8) / (ph - cut))
			m.panel.Size = UDim2.fromOffset(pw, ph - cut)
			m.panel.Parent = m.shade
			m.panel.AnchorPoint = Vector2.new(0.5, 0)
			m.panel.Position = UDim2.new(0.5, 0, 0, y0)
			m.scale.Scale = k
			m.scroller.Visible = false
			-- in the window's units: the bar's middle, and the first x right of Roblox's buttons
			local midY = (stripH / 2 - y0) / k
			local needX = (stripLeft + 12 - (vs.X - pw * k) / 2) / k
			for _, c in kids do
				local x0, yy0 = c:GetAttribute("PhoneX0"), c:GetAttribute("PhoneY0")
				local x, y, w = x0, yy0, c:GetAttribute("PhoneW0")
				if lift and isHead(c) then
					local h = c.Size.Y.Offset
					y = midY - h / 2 + c.AnchorPoint.Y * h
					if c.Position.X.Scale == 0 and c.AnchorPoint.X == 0 and x0 < needX then
						x = needX
						w -= needX - x0
					end
				elseif c.Position.Y.Scale == 0 then
					y = yy0 - cut
				end
				c.Position = UDim2.new(c.Position.X.Scale, x, c.Position.Y.Scale, y)
				if c.Size.X.Scale > 0 then
					c.Size = UDim2.new(c.Size.X.Scale, w, c.Size.Y.Scale, c.Size.Y.Offset)
				end
			end
			-- the header's own tab in the bar (what is behind the window showed through it)
			if not m.headBand then
				m.headBand = Theme.panel({
					Name = "HeadBand",
					BackgroundTransparency = 0.06,
					CornerRadius = 18,
					ZIndex = 41,
					Parent = m.panel,
				})
			end
			m.headBand.Visible = lift
			local bandH = (stripH - 6) / k
			m.headBand.Position = UDim2.fromOffset(needX - 14, midY - bandH / 2)
			m.headBand.Size = UDim2.fromOffset(pw - needX + 14, bandH)
			return true
		end
		m.panel.Parent = m.scroller
		m.panel.AnchorPoint = Vector2.new(0.5, 0)
		m.panel.Position = UDim2.new(0.5, 0, 0, top)
		m.scale.Scale = k
		m.scroller.CanvasSize = UDim2.fromOffset(0, math.ceil(m.h * k) + top + 8)
	else
		m.panel.Parent = m.shade
		m.panel.AnchorPoint = Vector2.new(0.5, 0.5)
		m.panel.Position = UDim2.fromScale(0.5, 0.5)
		m.scale.Scale = viewportScale(m.baseSize)
	end
	m.scroller.Visible = phone
	return phone
end
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
	local scroller = new("ScrollingFrame", {
		Name = "PhoneScroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.dim,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
		ZIndex = 40,
		Parent = shade,
	})
	local m = { shade = shade, panel = panel, scale = scale, hide = hide, scroller = scroller, w = w, h = h }
	m.baseSize = Vector2.new(w + 40, h + 40)
	table.insert(modalWindows, m)
	function m.show()
		shade.Visible = true
		if m.resize then
			m.resize(gui.AbsoluteSize)
		elseif fitModal(m) then
			scroller.CanvasPosition = Vector2.zero
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
	ui.lobbyPad = new("UIPadding", {
		PaddingLeft = UDim.new(0, 48),
		PaddingRight = UDim.new(0, 40),
		PaddingTop = UDim.new(0, 70),
		PaddingBottom = UDim.new(0, 36),
		Parent = safe,
	})
	-- Logo
	local logo = label("THE LAST GROVE", {
		Name = "Logo",
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
	ui.logo = logo
	ui.tagline = label("ВЕРНИ ЖИЗНЬ СВОЕМУ УГЛУ МИРА.", {
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
	-- (DD-110: on a phone the brief shrinks to its box instead of running under the buttons)
	ui.huntBriefMax = new("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 11, Parent = ui.huntBrief })
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
	-- DD-107: a phone stands the guns two by two, small, right above В БОЙ
	ui.weaponsGrid = new("UIGridLayout", {
		CellSize = UDim2.fromOffset(212, 92),
		CellPadding = UDim2.fromOffset(10, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	-- Top right: xenite, settings, squad
	local tr = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -50),
		Size = UDim2.fromOffset(400, 300),
		Parent = safe,
	})
	ui.lobbyTopRight = tr
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
	ui.lobbyAlloy, ui.lobbyAlloyAmount = Xenite.alloy(ui.xenite, 40, 24, 18)
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
	ui.inviteNote = label("+10% ксенита за каждого в отряде", {
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
	ui.upgradesBtn = Theme.button("ОРУЖЕЙНАЯ", {
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
	local small = ui.lobbyPhone == true -- DD-107: the phone's small card (the gun, its name, one line)
	local vpHolder = new(
		"Frame",
		{ Position = UDim2.fromOffset(6, 2), Size = UDim2.new(1, -12, 0, if small then 54 else 88), Parent = card }
	)
	local vp = Preview.weapon(vpHolder, id, false, { spin = selected, zoom = 0.62, pitch = 0.18 })
	if state ~= "owned" then
		vp.ImageTransparency = 0.55
		vp.ImageColor3 = Color3.fromRGB(120, 110, 150)
	end
	label(w.name, {
		Position = UDim2.fromOffset(if small then 12 else 16, if small then 54 else 92),
		Size = UDim2.new(1, if small then -24 else -32, 0, if small then 18 else 22),
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
		Position = UDim2.fromOffset(if small then 12 else 16, if small then 73 else 114),
		Size = UDim2.new(1, if small then -24 else -32, 0, if small then 14 else 26),
		FontFace = F.body,
		TextSize = 11,
		TextWrapped = not small,
		TextTruncate = if small then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	if state == "owned" and profile then
		-- DD-112: the gun's mastery rank; its step colours the badge (stage 3) and «ЭВО» marks an opened
		-- evolution
		local rank = Defs.masteryRank(id, (profile.mastery or {})[id] or 0)
		local evo = (profile.evoOpen or {})[id] == true
		local tag = new("Frame", {
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(if evo then 74 else 40, 22),
			BackgroundColor3 = Defs.MasteryTierColor[Defs.masteryTier(rank)] or C.gold,
			Corner = UDim.new(1, 0),
			ZIndex = 3,
			Parent = card,
		})
		label("M" .. rank .. (if evo then " · ЭВО" else ""), {
			Size = UDim2.fromScale(1, 1),
			FontFace = F.numHeavy,
			TextSize = 13,
			TextColor3 = C.ink,
			ZIndex = 4,
			Parent = tag,
		})
	end
	if state == "locked" then
		icon("lock", 22, C.dim, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Parent = card })
	elseif state == "buy" then
		local affordable = profile and profile.scrap >= price
		local buy, buyLabel = Theme.button("КУПИТЬ  " .. price, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.fromOffset(if small then 112 else 130, if small then 30 else 34),
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
	-- (DD-102: a phone has no logo above the tabs)
	ui.hunt.Position = UDim2.fromOffset(0, (if ui.tabs.Visible then 176 else 134) - (if ui.lobbyPhone then 128 else 0))
	-- DD-109: a phone's tabs stand in Roblox's top bar, right of its buttons; the card takes their row
	local stripLeft, _, stripH = Theme.topStrip()
	if ui.lobbyPhone and stripH > 0 then
		local k = ui.lobbyScale.Scale
		local padTop, padLeft = ui.lobbyPad.PaddingTop.Offset, ui.lobbyPad.PaddingLeft.Offset
		local tx, ty = (stripLeft + 8) / k - padLeft, ((stripH - 40 * k) / 2) / k - padTop
		ui.tabs.Position = UDim2.fromOffset(tx, ty)
		ui.hunt.Position = UDim2.fromOffset(0, 0)
		-- the way back right after the tabs (or first, with no tabs)
		local tabW = if ui.tabs.Visible then tabCount * 132 + (tabCount - 1) * 8 + 12 else 0
		ui.back.AnchorPoint = Vector2.zero
		ui.back.Position = UDim2.fromOffset(tx + tabW, ty - 2)
		ui.lobbyTopRight.Position = UDim2.new(1, 0, 0, ((stripH - 44 * k) / 2) / k - padTop)
	else
		ui.lobbyTopRight.Position = UDim2.new(1, 0, 0, -50)
		ui.back.AnchorPoint = Vector2.new(1, 1)
		ui.back.Position = UDim2.new(1, if ui.lobbyPhone then -312 else -346, 1, -36)
		ui.tabs.Position = UDim2.fromOffset(0, if ui.lobbyPhone then 0 else 124)
	end
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
	ui.huntWhy.Visible = mode == "hunt" and not ui.lobbyPhone -- (DD-107: a phone keeps the brief only)
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
	-- DD-102: the hunt's «why» (three lines from y 148) ran under the arrows: the row goes below it
	local rowY = if ui.huntWhy.Visible and ui.huntWhy.Text ~= "" then 204 else 156
	ui.threat.Position = UDim2.fromOffset(if #list > 1 and isHost then 132 else 24, rowY)
	ui.huntPrev.Position = UDim2.fromOffset(24, rowY)
	ui.huntNext.Position = UDim2.fromOffset(72, rowY)
	for i, d in ui.threatDots do
		d.button.Visible = i <= maxT
		local on = i == info.threat
		d.button.BackgroundColor3 = if on then C.orange else C.white
		d.button.BackgroundTransparency = if on then 0 else 0.9
		d.text.TextColor3 = if on then C.ink else C.text
	end
	-- DD-110: a phone's width after its notch insets is ~900 units, not the 1000 of Studio's window: the card
	-- and the guns share what there is (they overlapped on the owner's phone)
	local hw, ww = 460, 434
	if ui.lobbyPhone then
		local pad = ui.lobbyPad
		local avail = gui.AbsoluteSize.X / ui.lobbyScale.Scale - pad.PaddingLeft.Offset - pad.PaddingRight.Offset
		hw = math.clamp(avail - 20 - 434, 380, 460)
		ww = math.max(300, avail - 20 - hw)
		ui.weapons.Size = UDim2.fromOffset(ww, 200)
		ui.weaponsGrid.CellSize = UDim2.fromOffset(math.floor((ww - 10) / 2), 92)
	end
	ui.hunt.Size =
		UDim2.fromOffset(hw, if ui.huntPrev.Visible or ui.threat.Visible or ui.modeRow.Visible then rowY + 58 else 160)
	-- Xenite + upgrades: after the first hunt
	ui.xenite.Visible = runs > 0 or (prof and prof.scrap > 0)
	ui.xeniteAmount.Text = Theme.commas(prof and prof.scrap or 0)
	ui.lobbyAlloy.Visible = prof ~= nil and (prof.alloy or 0) > 0
	ui.lobbyAlloyAmount.Text = Theme.commas(prof and prof.alloy or 0)
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
	ui.weaponsTitle.Visible = showWeapons and not ui.lobbyPhone
	if not (prof and prof.weapons[selectedWeapon]) then
		selectedWeapon = "W_ARC_RIFLE"
	end
	local y = ui.hunt.Position.Y.Offset + ui.hunt.Size.Y.Offset + 18
	if ui.lobbyPhone then -- DD-102: on the right, above В БОЙ; the upgrades under the card (the corner is the thumbstick's)
		ui.weapons.Position = UDim2.new(1, 0, 0, 0) -- (DD-107: from the top, under the xenite)
		ui.metaRow.AnchorPoint = Vector2.zero
		ui.metaRow.Position = UDim2.fromOffset(0, y - 6)
		-- DD-110: the row is the card's width (РЕЙТИНГ ran under В БОЙ); with three buttons or more each
		-- is an icon over its word, as a phone's tab bar
		local btns = {}
		for _, b in ui.metaRow:GetChildren() do
			if b:IsA("GuiButton") and b.Visible then
				table.insert(btns, b)
			end
		end
		local stacked = #btns >= 3
		local bw = math.floor((hw - (#btns - 1) * 10) / math.max(1, #btns))
		for _, b in btns do
			b.Size = if stacked
				then UDim2.fromOffset(bw, 60)
				else UDim2.fromOffset(if b == ui.upgradesBtn then 190 else 140, 52)
			local lbl = b:FindFirstChild("Label")
			for _, c in b:GetChildren() do
				if c.Name:sub(1, 5) == "Icon_" then
					c.AnchorPoint = Vector2.new(if stacked then 0.5 else 0, 0.5)
					c.Position = if stacked then UDim2.new(0.5, 0, 0, 20) else UDim2.new(0, 18, 0.5, 0)
				end
			end
			if lbl then
				lbl.Position = UDim2.fromOffset(if stacked then 0 else 20, if stacked then 14 else 0)
				lbl.TextSize = if stacked then 11 elseif b == ui.upgradesBtn then 15 else 13
			end
		end
	else
		ui.metaRow.AnchorPoint = Vector2.new(0, 1)
		ui.metaRow.Position = UDim2.fromScale(0, 1)
		ui.weaponsTitle.Position = UDim2.fromOffset(4, y)
		ui.weapons.Position = UDim2.fromOffset(0, y + 22)
	end
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
		local phone = Theme.phone()
		lobbyPhoneLayout(phone)
		-- (DD-107: 0.62 → 0.72; DD-109: 0.8 — the tabs and НА БАЗУ moved up into Roblox's top bar)
		local _, _, stripH = Theme.topStrip()
		local strip = phone and stripH > 0
		local k = math.max(if strip then 0.8 else 0.72, viewportScale(Vector2.new(1280, 760)))
		ui.lobbyScale.Scale = k
		ui.lobbySafe.Size = UDim2.fromScale(1 / k, 1 / k)
		ui.lobbyPad.PaddingTop = UDim.new(0, if strip then (stripH + 6) / k elseif phone then 96 else 70)
		Menus.refreshLobby()
	end
end

-- DD-102: a phone drops the logo and moves the weapons to the right above В БОЙ, so the launch pad
-- can be drawn at 0.62 instead of 0.52 (its words were 7 points on the owner's phone); the top stays
-- clear of Roblox's own buttons.
function lobbyPhoneLayout(phone: boolean)
	if ui.lobbyPhone == phone then
		return
	end
	ui.lobbyPhone = phone
	ui.logo.Visible = not phone
	ui.tagline.Visible = not phone
	ui.lobbyPad.PaddingTop = UDim.new(0, if phone then 96 else 70)
	ui.lobbyPad.PaddingBottom = UDim.new(0, if phone then 30 else 36)
	ui.tabs.Position = UDim2.fromOffset(0, if phone then 0 else 124)
	-- (the hunt card and the weapons are placed by refreshLobby, which reads ui.lobbyPhone)
	ui.weaponsTitle.TextXAlignment = Enum.TextXAlignment.Left
	-- DD-107: the guns two by two in the right column (the title would only repeat what they show)
	ui.weaponsTitle.Visible = not phone
	ui.weapons.AnchorPoint = if phone then Vector2.new(1, 0) else Vector2.zero
	ui.weapons.Size = if phone then UDim2.fromOffset(434, 200) else UDim2.fromOffset(700, 150)
	ui.weaponsList = ui.weaponsList or ui.weapons:FindFirstChildOfClass("UIListLayout")
	ui.weaponsList.Parent = if phone then nil else ui.weapons
	ui.weaponsGrid.Parent = if phone then ui.weapons else nil
	ui.weaponsKey = nil
	-- the invite lives in the shelter's menu on a phone; В БОЙ and НА БАЗУ a little smaller
	ui.invite.Visible = not phone
	ui.inviteNote.Visible = not phone
	ui.harvest.Position = UDim2.new(1, -56, 0, if phone then 50 else 112)
	ui.play.Size = UDim2.fromOffset(if phone then 300 else 330, if phone then 80 else 92)
	-- DD-109: a phone's way back is a round ‹ in the top bar, after the tabs (placed by refreshLobby)
	ui.back.Size = if phone then UDim2.fromOffset(44, 44) else UDim2.fromOffset(190, 64)
	ui.backLabel.Text = if phone then "‹" else "‹  НА БАЗУ"
	ui.backLabel.TextSize = if phone then 28 else 16
	ui.backLabel.Position = UDim2.fromOffset(0, if phone then -2 else 0)
	for _, t in ui.tabButtons do
		t.button.Size = UDim2.fromOffset(if phone then 132 else 146, 40)
	end
	-- the meta row stays left of НА БАЗУ (a phone's is sized by refreshLobby, DD-110)
	ui.huntBrief.TextScaled = phone
	ui.huntBriefMax.MaxTextSize = if phone then 15 else 17
	for _, b in ui.metaRow:GetChildren() do
		if b:IsA("GuiButton") and not phone then
			b.Size = UDim2.fromOffset(if b == ui.upgradesBtn then 230 else 150, 58)
			local lbl = b:FindFirstChild("Label")
			for _, c in b:GetChildren() do
				if c.Name:sub(1, 5) == "Icon_" then
					c.AnchorPoint = Vector2.new(0, 0.5)
					c.Position = UDim2.new(0, if b == ui.upgradesBtn then 20 else 16, 0.5, 0)
				end
			end
			if lbl then
				lbl.Position = UDim2.fromOffset(if b == ui.upgradesBtn then 22 else 18, 0)
				lbl.TextSize = if b == ui.upgradesBtn then 17 else 14
			end
		end
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

-- The armory (DD-112): one tab per owned gun — its mastery, its two slots (core + adapter) and the three
-- module branches — and «ГЕРОЙ», the perks. Opens on the gun the player fights with.
local BRANCH_COLORS = { A = C.cyan, B = C.violet, C = C.gold }
local armoryTab = nil -- weapon id or "HERO"

-- The alloy pill: the ingot mark + number, beside the xenite pill.
local function alloyPill(parent, props)
	local p = new("Frame", {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.2,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.orange, Transparency = 0.5, Thickness = 1.5 },
		Parent = parent,
	})
	for k, v in props or {} do
		p[k] = v
	end
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 16), Parent = p })
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = p,
	})
	icon("core", 26, C.orange, { LayoutOrder = 1, Parent = p })
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

local function buildUpgrades()
	local m = modal("Upgrades", 860, 560, "ОРУЖЕЙНАЯ", nil)
	ui.upgrades = m
	-- the purse (top right): сплав, then xenite
	local purse = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -74, 0, 20),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 42,
		Parent = m.panel,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = purse,
	})
	ui.upgradesAlloy, ui.upgradesAlloyAmount = alloyPill(purse, { LayoutOrder = 1 })
	ui.upgradesXenite, ui.upgradesXeniteAmount = xenitePill(purse, { LayoutOrder = 2 })
	for _, d in purse:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 43
		end
	end
	-- tabs: the owned guns, then the hero
	ui.armoryTabs = new("Frame", {
		Position = UDim2.fromOffset(28, 66),
		Size = UDim2.new(1, -56, 0, 38),
		ZIndex = 42,
		Parent = m.panel,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		},
	})
	-- the gun's page
	ui.armoryBody = new("Frame", {
		Position = UDim2.fromOffset(28, 116),
		Size = UDim2.new(1, -56, 0, 424),
		ZIndex = 42,
		Parent = m.panel,
	})
	-- the hero's page (perks)
	ui.upgradesGrid = new("Frame", {
		Position = UDim2.fromOffset(28, 116),
		Size = UDim2.new(1, -56, 0, 424),
		ZIndex = 42,
		Parent = m.panel,
	})
	local grid = new("UIGridLayout", {
		CellSize = UDim2.fromOffset(190, 200),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.upgradesGrid,
	})
	-- DD-107: on a phone the perk cards lie flat (icon and name side by side), two rows of four
	m.phoneSize = Vector2.new(820, 404)
	function m.relayout(phone: boolean)
		local top = if phone then 108 else 116
		ui.armoryTabs.Position = UDim2.fromOffset(28, if phone then 62 else 66)
		ui.armoryBody.Position = UDim2.fromOffset(28, top)
		-- fixed heights: the phone's lifted header shortens the panel and moves these up by the same cut
		local bodyH = if phone then m.phoneSize.Y - top - 10 else m.h - top - 20
		ui.armoryBody.Size = UDim2.new(1, -56, 0, bodyH)
		ui.upgradesGrid.Position = UDim2.fromOffset(28, top)
		ui.upgradesGrid.Size = UDim2.new(1, -56, 0, bodyH)
		grid.CellSize = if phone then UDim2.fromOffset(183, 136) else UDim2.fromOffset(190, 200)
		grid.CellPadding = if phone then UDim2.fromOffset(8, 8) else UDim2.fromOffset(12, 12)
		Menus.refreshUpgrades()
	end
end

-- The perks (the hero tab).
local function refreshPerks()
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
		local flat = ui.upgrades.phone == true -- DD-107: the phone's flat card
		local disc = Icons.disc(def.icon, if flat then 44 else 60, def.color, 43)
		disc.AnchorPoint = if flat then Vector2.zero else Vector2.new(0.5, 0)
		disc.Position = if flat then UDim2.fromOffset(10, 10) else UDim2.new(0.5, 0, 0, 14)
		disc.Parent = tile
		label(def.name, {
			Position = UDim2.fromOffset(if flat then 62 else 8, if flat then 12 else 80),
			Size = UDim2.new(1, if flat then -70 else -16, 0, 20),
			FontFace = F.display,
			TextSize = 14,
			TextXAlignment = if flat then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			ZIndex = 43,
			Parent = tile,
		})
		for k = 1, def.max do
			new("Frame", {
				AnchorPoint = Vector2.new(if flat then 0 else 0.5, 0),
				Position = if flat
					then UDim2.fromOffset(62 + (k - 1) * 16, 38)
					else UDim2.new(0.5, (k - (def.max + 1) / 2) * 16, 0, 104),
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
			Position = UDim2.fromOffset(10, if flat then 56 else 116),
			Size = UDim2.new(1, -20, 0, if flat then 32 else 36),
			FontFace = F.bodyBold,
			TextSize = 13,
			TextWrapped = true,
			TextColor3 = if maxed then C.dim else C.text,
			ZIndex = 43,
			Parent = tile,
		})
		local b, bl = Theme.button(if maxed then "МАКС" else "◆ " .. cost, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, if flat then -8 else -12),
			Size = UDim2.new(1, if flat then -20 else -28, 0, if flat then 34 else 40),
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

-- What a module tile says when it cannot be made yet.
local function whyNot(wid: string, m, why: string?): string
	local w = Defs.Weapons[wid]
	if why == "mastery" then
		local kills = (profile.mastery or {})[wid] or 0
		return string.format(
			"Нужно мастерство M%d: ещё %d убийств «%s».",
			m.mastery,
			math.max(0, Defs.masteryNeed(wid, m.mastery) - kills),
			w.short
		)
	elseif why == "prev" then
		local prev = Modules.get(Modules.id(wid, m.branch, m.tier - 1))
		return "Сначала собери «" .. (if prev then prev.name else "") .. "»."
	elseif why == "scrap" then
		return string.format(
			"Не хватает ксенита: нужно %d, у тебя %d. Ксенит приносят вылазки.",
			m.cost,
			profile.scrap or 0
		)
	elseif why == "alloy" then
		return string.format(
			"Не хватает сплава: нужно %d, у тебя %d. Сплав даёт оборона бура.",
			m.alloy,
			profile.alloy or 0
		)
	end
	return ""
end

-- Put an owned module to work: the core's own branch replaces the core; another fills the adapter.
local function equip(wid: string, id: string)
	local lo = (profile.loadout or {})[wid] or {}
	local out = Modules.placeNew(wid, { core = lo.core, adapter = lo.adapter }, id)
	if out.core == lo.core and out.adapter == lo.adapter then
		-- a lower tier or a third branch: it becomes the core
		local mm = Modules.get(id)
		local a = Modules.get(lo.adapter)
		out = { core = id, adapter = if a and mm and a.branch ~= mm.branch then lo.adapter else nil }
		if not Modules.validLoadout(wid, out.core, out.adapter) then
			out.adapter = nil
		end
	end
	send("equipModule", wid, "adapter", "")
	send("equipModule", wid, "core", out.core or "")
	if out.adapter then
		send("equipModule", wid, "adapter", out.adapter)
	end
end

-- DD-112 stage 3: what the evolution pill says when tapped and nothing can be done yet.
local function evoNote(wid: string, why: string?): string
	local evo = Evolve.of(wid)
	if not evo then
		return ""
	end
	local w = Defs.Weapons[wid]
	local name = "«" .. evo.name .. "»"
	if why == "component" then
		local comp = Defs.Components[evo.component]
		return string.format(
			"%s: нужен компонент «%s» — %s.",
			name,
			comp and comp.name or "",
			Evolve.ComponentFrom[evo.component] or "в вылазках"
		)
	elseif why == "mastery" then
		local kills = (profile.mastery or {})[wid] or 0
		return string.format(
			"%s: нужно мастерство M%d — ещё %d убийств «%s».",
			name,
			Defs.Evolve.OpenMastery,
			math.max(0, Defs.masteryNeed(wid, Defs.Evolve.OpenMastery) - kills),
			w.short
		)
	elseif why == "scrap" or why == "alloy" then
		return string.format(
			"%s: открыть — %d ксенита и %d сплава (у тебя %d и %d). Сплав даёт оборона бура.",
			name,
			Defs.Evolve.OpenCost,
			Defs.Evolve.OpenAlloy,
			profile.scrap or 0,
			profile.alloy or 0
		)
	end
	-- opened: how it fires in the fight (the permanent form is the pill's next step at M10)
	return string.format(
		"%s — в бою с вылазки 3: %d-й уровень + ядро элиты или босса (или с %d:%02d).",
		name,
		Defs.Evolve.Level,
		Defs.Evolve.CoreAt // 60,
		Defs.Evolve.CoreAt % 60
	)
end

-- The pill: «ЭВОЛЮЦИЯ» (locked) → «ЭВО ◆300 ●30» (open it) → «ГРОМОВЕРЖЕЦ» (opened) → «ФОРМА ◆1200 ●100»
-- (make the permanent form) → «В ФОРМЕ» / «БЕЗ ФОРМЫ» (wear it or not).
local function evolutionPill(
	wid: string,
	parent: Instance,
	x: number,
	y: number,
	width: number,
	height: number,
	phone: boolean
)
	local evo = Evolve.of(wid)
	if not evo then
		return
	end
	local canOpen, openWhy = Evolve.canOpen(profile, wid)
	local opened = openWhy == "open"
	local canForm, formWhy = Evolve.canForm(profile, wid)
	local made = formWhy == "made"
	local worn = made and (profile.equip or {})[wid] == evo.id
	local text, fill, fg, price, lock = "ЭВОЛЮЦИЯ", nil, C.dim, nil, true
	if canOpen then
		text, fill, fg, price, lock = "ЭВО", C.lime, C.ink, { Defs.Evolve.OpenCost, Defs.Evolve.OpenAlloy }, false
	elseif made then
		text, fill, fg, lock =
			if worn then "В ФОРМЕ" else "БЕЗ ФОРМЫ",
			if worn then evo.color else nil,
			if worn then C.ink else C.text,
			false
	elseif canForm then
		text, fill, fg, price, lock =
			"ФОРМА", C.lime, C.ink, { Defs.Evolve.FormCost, Defs.Evolve.FormAlloy }, false
	elseif opened then
		text, fill, fg, lock = evo.name, evo.color, C.ink, false
	elseif openWhy == "scrap" or openWhy == "alloy" then
		text, price, lock = "ЭВО", { Defs.Evolve.OpenCost, Defs.Evolve.OpenAlloy }, false
	end
	local pill = new("TextButton", {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = fill or C.ink,
		BackgroundTransparency = if fill then 0 else 0.3,
		Text = "",
		AutoButtonColor = false,
		Corner = UDim.new(1, 0),
		Stroke = { Color = evo.color, Transparency = if fill then 0.2 else 0.55, Thickness = 1.5 },
		ZIndex = 43,
		Parent = parent,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 5),
		},
	})
	icon(if lock then "lock" else "evolve", if phone then 14 else 16, if fill then fg else evo.color, {
		LayoutOrder = 1,
		ZIndex = 44,
		Parent = pill,
	})
	local tl = label(text, {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = F.head,
		TextSize = if phone then 12 else 13,
		TextColor3 = fg,
		LayoutOrder = 2,
		ZIndex = 44,
		Parent = pill,
	})
	if price then
		tl.Text = text .. "  ◆ " .. price[1]
		Xenite.inline(tl)
		icon(
			"core",
			if phone then 12 else 13,
			if fill then C.ink else C.orange,
			{ LayoutOrder = 3, ZIndex = 44, Parent = pill }
		)
		label(tostring(price[2]), {
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			FontFace = F.head,
			TextSize = if phone then 12 else 13,
			TextColor3 = fg,
			LayoutOrder = 4,
			ZIndex = 44,
			Parent = pill,
		})
	end
	pill.Activated:Connect(function()
		if canOpen then
			send("openEvolution", wid)
			Audio.play("evolve", 0.7, 1.2)
			ui.armoryNoteText = "«" .. evo.name .. "» открыт: " .. evo.text
		elseif made then
			send("equipForm", wid, if worn then "" else evo.id)
			Audio.play("equip", 0.7)
		elseif canForm then
			send("craftForm", evo.id)
			Audio.play("evolve", 0.8, 1)
			ui.armoryNoteText = "«" .. evo.name .. "» навсегда: бой начинается в форме."
		else
			ui.armoryNoteText = evoNote(wid, if opened then nil else openWhy)
			Audio.play(if opened then "ui" else "warn", 0.5)
		end
		Menus.refreshUpgrades()
	end)
end

local function refreshGun(wid: string)
	local body = ui.armoryBody
	local phone = ui.upgrades.phone == true
	local w = Defs.Weapons[wid]
	local kills = (profile.mastery or {})[wid] or 0
	local rank, into, need = Defs.masteryRank(wid, kills)
	local lo = (profile.loadout or {})[wid] or {}
	local W = (if phone then ui.upgrades.phoneSize.X else ui.upgrades.w) - 56
	local bodyH = body.Size.Y.Offset
	-- the mastery line: name, rank, bar, what is next
	local rowH = if phone then 30 else 40
	label(w.name, {
		Size = UDim2.fromOffset(if phone then 210 else 250, rowH),
		FontFace = F.display,
		TextSize = if phone then 17 else 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = w.color,
		ZIndex = 43,
		Parent = body,
	})
	local badge = new("Frame", {
		Position = UDim2.fromOffset(if phone then 214 else 254, (rowH - 26) / 2),
		Size = UDim2.fromOffset(52, 26),
		BackgroundColor3 = C.gold,
		Corner = UDim.new(1, 0),
		ZIndex = 43,
		Parent = body,
	})
	label("M" .. rank, {
		Size = UDim2.fromScale(1, 1),
		FontFace = F.numHeavy,
		TextSize = 15,
		TextColor3 = C.ink,
		ZIndex = 44,
		Parent = badge,
	})
	-- DD-112 stage 3: the evolution pill — open it, make the permanent form, wear it or not
	local evoW = if phone then 176 else 210
	local evoX = (if phone then 214 else 254) + 60
	evolutionPill(wid, body, evoX, (rowH - (if phone then 26 else 30)) / 2, evoW, if phone then 26 else 30, phone)
	local barX = evoX + evoW + 10
	local barBack = new("Frame", {
		Position = UDim2.fromOffset(barX, rowH / 2 - 5),
		Size = UDim2.fromOffset(math.max(60, W - barX - (if phone then 160 else 180)), 10),
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.85,
		Corner = UDim.new(1, 0),
		ZIndex = 43,
		Parent = body,
	})
	new("Frame", {
		Size = UDim2.fromScale(if need then math.clamp(into / need, 0, 1) else 1, 1),
		BackgroundColor3 = C.gold,
		Corner = UDim.new(1, 0),
		ZIndex = 44,
		Parent = barBack,
	})
	label(
		if need
			then string.format("до M%d — %d убийств", rank + 1, need - into)
			else "высшее мастерство",
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(if phone then 150 else 170, rowH),
			FontFace = F.bodyBold,
			TextSize = if phone then 13 else 14,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 43,
			Parent = body,
		}
	)
	-- the note line: the two slots, or why the tapped module cannot be made
	local core, adapter = Modules.get(lo.core), Modules.get(lo.adapter)
	local slots = string.format(
		'<font color="#%s">ЯДРО</font>  %s     <font color="#%s">АДАПТЕР</font>  %s',
		C.lime:ToHex(),
		if core then core.name else "—",
		C.cyan:ToHex(),
		if adapter then adapter.name else "— (модуль другой ветки, до II)"
	)
	local noteY = rowH + (if phone then 2 else 6)
	local noteH = if phone then 20 else 24
	ui.armoryNote = label(ui.armoryNoteText or slots, {
		Position = UDim2.fromOffset(0, noteY),
		Size = UDim2.new(1, 0, 0, noteH),
		FontFace = F.bodyBold,
		TextSize = if phone then 13 else 14,
		TextColor3 = if ui.armoryNoteText then C.orange else C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 43,
		Parent = body,
	})
	ui.armoryNoteText = nil
	-- three branches, three tiers
	local colY = noteY + noteH + (if phone then 6 else 12)
	local gap = if phone then 8 else 12
	local colW = (W - gap * 2) / 3
	local headH = if phone then 18 else 24
	local tileGap = if phone then 6 else 8
	local tileH = math.floor((bodyH - colY - headH - tileGap * 3) / 3)
	for bi, branch in Modules.Branches do
		local x = (bi - 1) * (colW + gap)
		local col = BRANCH_COLORS[branch]
		local first = Modules.get(Modules.id(wid, branch, 1))
		label(first and first.branchName or branch, {
			Position = UDim2.fromOffset(x + 4, colY),
			Size = UDim2.fromOffset(colW - 8, headH),
			FontFace = F.head,
			TextSize = if phone then 12 else 13,
			TextColor3 = col,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
			Parent = body,
		})
		for tier = 1, 3 do
			local id = Modules.id(wid, branch, tier)
			local m = Modules.get(id)
			if not m then
				continue
			end
			local owned = (profile.modules or {})[id] == true
			local inCore, inAdapter = lo.core == id, lo.adapter == id
			local can, why = Modules.craftable(profile, m, rank)
			local tile = new("TextButton", {
				Position = UDim2.fromOffset(x, colY + headH + tileGap + (tier - 1) * (tileH + tileGap)),
				Size = UDim2.fromOffset(colW, tileH),
				BackgroundColor3 = if inCore or inAdapter then C.panel2 else C.ink,
				BackgroundTransparency = if owned then 0.1 else 0.4,
				Text = "",
				AutoButtonColor = false,
				Corner = 14,
				Stroke = {
					Color = if inCore then C.lime elseif inAdapter then C.cyan elseif can then col else C.white,
					Transparency = if inCore or inAdapter then 0.1 elseif can then 0.35 else 0.88,
					Thickness = if inCore or inAdapter then 2 else 1,
				},
				ZIndex = 43,
				Parent = body,
			})
			local pad = if phone then 8 else 12
			label(m.name .. '  <font color="#' .. C.dim:ToHex() .. '">' .. Modules.Roman[tier] .. "</font>", {
				Position = UDim2.fromOffset(pad, if phone then 4 else 8),
				Size = UDim2.new(1, -pad * 2 - (if phone then 92 else 108), 0, if phone then 20 else 22),
				FontFace = F.display,
				TextSize = if phone then 13 else 14,
				TextColor3 = if owned then C.text else C.dim,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 44,
				Parent = tile,
			})
			-- DD-112: a tier keeps the ones below it, and each fitted module is raw damage by its tier
			local power = math.floor((Modules.Power[tier] or 0) * 100 + 0.5)
			label(m.text .. string.format('  <font color="#%s">+%d%% урона</font>', C.gold:ToHex(), power), {
				Position = UDim2.fromOffset(pad, if phone then 26 else 34),
				Size = UDim2.new(1, -pad * 2, 1, if phone then -28 else -40),
				FontFace = F.body,
				TextSize = if phone then 12 else 13,
				TextWrapped = true,
				TextColor3 = if owned then C.text else C.dim,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 44,
				Parent = tile,
			})
			-- the state, top right: in a slot / take / the price / the lock
			local stateText, stateColor, fill = "", C.dim, nil
			local price = false
			if inCore then
				stateText, stateColor, fill = "ЯДРО", C.ink, C.lime
			elseif inAdapter then
				stateText, stateColor, fill = "АДАПТЕР", C.ink, C.cyan
			elseif owned and (profile.modules or {})[Modules.id(wid, branch, tier + 1)] then
				stateText = "УЛУЧШЕН" -- its next tier is made: taking this one would be a step back
			elseif owned then
				stateText, stateColor = "ВЗЯТЬ", C.lime
			elseif why == "mastery" then
				stateText = "M" .. m.mastery
			elseif why == "prev" or why == "free" then
				stateText = "—"
			else
				price = true
				stateText = "◆ " .. m.cost
				stateColor = if can then C.ink else C.dim
				fill = if can then C.lime else nil
			end
			local chip = new("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, if phone then 4 else 6),
				Size = UDim2.fromOffset(0, if phone then 20 else 24),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = fill or C.white,
				BackgroundTransparency = if fill then 0 else 0.9,
				Corner = UDim.new(1, 0),
				ZIndex = 44,
				Parent = tile,
				List = {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 4),
				},
			})
			new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = chip })
			if why == "mastery" and not owned then
				icon("lock", 12, C.dim, { LayoutOrder = 1, ZIndex = 45, Parent = chip })
			end
			local sl = label(stateText, {
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				FontFace = F.head,
				TextSize = if phone then 11 else 12,
				TextColor3 = stateColor,
				LayoutOrder = 2,
				ZIndex = 45,
				Parent = chip,
			})
			if price then
				Xenite.inline(sl)
				if m.alloy > 0 then
					icon("core", 12, if can then C.ink else C.orange, { LayoutOrder = 3, ZIndex = 45, Parent = chip })
					label(tostring(m.alloy), {
						Size = UDim2.fromScale(0, 1),
						AutomaticSize = Enum.AutomaticSize.X,
						FontFace = F.head,
						TextSize = if phone then 11 else 12,
						TextColor3 = stateColor,
						LayoutOrder = 4,
						ZIndex = 45,
						Parent = chip,
					})
				end
			end
			tile.Activated:Connect(function()
				if inCore then
					Audio.play("ui", 0.6)
				elseif inAdapter then
					send("equipModule", wid, "adapter", "")
					Audio.play("equip", 0.6, 0.9)
				elseif owned then
					equip(wid, id)
					Audio.play("equip", 0.7)
				elseif can then
					send("craftModule", id)
					Audio.play("level", 0.8, 1.3)
				else
					ui.armoryNoteText = whyNot(wid, m, why)
					Audio.play("warn", 0.4)
					Menus.refreshUpgrades()
				end
			end)
		end
	end
end

function Menus.refreshUpgrades()
	if not ui.upgrades or not profile then
		return
	end
	ui.upgradesXeniteAmount.Text = Theme.commas(profile.scrap)
	ui.upgradesAlloyAmount.Text = Theme.commas(profile.alloy or 0)
	local owned = {}
	for _, wid in Defs.WeaponOrder do
		if (profile.weapons or {})[wid] then
			table.insert(owned, wid)
		end
	end
	if armoryTab ~= "HERO" and not (profile.weapons or {})[armoryTab or ""] then
		armoryTab = owned[1] or "HERO"
	end
	clear(ui.armoryTabs)
	local phone = ui.upgrades.phone == true
	local tabs = table.clone(owned)
	table.insert(tabs, "HERO")
	for i, key in tabs do
		local on = key == armoryTab
		local w = Defs.Weapons[key]
		local text = if w
			then w.short .. "  M" .. Defs.masteryRank(key, (profile.mastery or {})[key] or 0)
			else "ГЕРОЙ"
		local b, bl = Theme.button(text, {
			Size = UDim2.fromOffset(if phone then 126 else 140, if phone then 34 else 36),
			LayoutOrder = i,
			ZIndex = 43,
			TextSize = if phone then 13 else 14,
		}, if on then "primary" else "ghost")
		b.Parent = ui.armoryTabs
		bl.ZIndex = 44
		b.Activated:Connect(function()
			if armoryTab ~= key then
				armoryTab = key
				Audio.play("ui", 0.7)
				Menus.refreshUpgrades()
			end
		end)
	end
	clear(ui.armoryBody)
	clear(ui.upgradesGrid)
	ui.armoryBody.Visible = armoryTab ~= "HERO"
	ui.upgradesGrid.Visible = armoryTab == "HERO"
	if armoryTab == "HERO" then
		refreshPerks()
	else
		refreshGun(armoryTab)
	end
end

-- weapon: the tab to open on (default: the gun picked for the next sortie)
function Menus.showUpgrades(weapon: string?)
	local want = weapon or selectedWeapon
	if want and profile and (profile.weapons or {})[want] then
		armoryTab = want
	end
	ui.upgrades.show()
	Menus.refreshUpgrades()
end

-- Settings -----------------------------------------------------------------------------------------------
local function buildSettings()
	local m = modal("Settings", 520, if Settings.touch then 532 else 466, "НАСТРОЙКИ", nil)
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
			if Settings.touch
				then "Автоприцел из-за плеча"
				else "Помощь в прицеливании", -- (DD-103: the simple fight aims itself)
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
	-- DD-103: the phone's simple fight (still camera, the gun aims itself) or the over-the-shoulder one
	if Settings.touch then
		table.insert(rows, 4, {
			"Бой",
			"person",
			function()
				return if Settings.simpleCombat then "ПРОСТОЙ" else "ИЗ-ЗА ПЛЕЧА"
			end,
			function()
				Settings.set("simpleCombat", not Settings.simpleCombat)
			end,
		})
	end
	local built = {}
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
		local name = label(r[1], {
			Position = UDim2.fromOffset(54, 0),
			Size = UDim2.new(1, -200, 1, 0),
			FontFace = F.bodyBold,
			TextSize = 15,
			TextWrapped = true,
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
		built[i] = { row = row, name = name, button = b }
	end
	-- DD-107: on a phone the rows stand in two columns, the whole window on one screen
	local cols = 2
	-- (DD-109: the window reaches the screen's top: taller rows, easier to hit)
	m.phoneSize = Vector2.new(760, 76 + math.ceil(#rows / cols) * 78 + 8)
	function m.relayout(phone: boolean)
		for i, e in built do
			if phone then
				local c, r = (i - 1) % cols, (i - 1) // cols
				e.row.Position = UDim2.new(c / cols, 24 - c * 18, 0, 76 + r * 78) -- (12 between the columns)
				e.row.Size = UDim2.new(1 / cols, -30, 0, 66)
				e.name.Size = UDim2.new(1, -178, 1, 0)
				e.button.Size = UDim2.fromOffset(120, 44)
			else
				e.row.Position = UDim2.fromOffset(24, 84 + (i - 1) * 66)
				e.row.Size = UDim2.new(1, -48, 0, 56)
				e.name.Size = UDim2.new(1, -200, 1, 0)
				e.button.Size = UDim2.fromOffset(130, 38)
			end
		end
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
-- DD-108 (owner: «по итогам боя столько дофига карточек, текстов… у нас уже есть катсцены после победы,
-- где показываем, что открылось; достаточно показать, сколько ксенита добыли, кратко следующую цель и
-- небольшие итоги боя раскрывающимся элементом»). The screen is three things and the way out:
--   the verdict (one line under it: which sortie, why it ended);
--   the xenite card — the amount big, the shelter's total, what it was made of as chips;
--   the next goal (after a loss: how to come back stronger);
--   «ИТОГИ БОЯ» — a pill with the time and kills that opens the numbers, the build and the squad;
--   НА БАЗУ / В ЛАГЕРЬ.
-- What opened is told by the homecoming scenes, not by cards here. A monitor stacks it in one column; a
-- phone puts the verdict and the xenite on the left, the goal and the buttons on the right.
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
		Size = UDim2.fromOffset(RES_DESK.X, RES_DESK.Y),
		ZIndex = 21,
		Parent = r,
	})
	ui.resBody = body
	ui.resScale = new("UIScale", { Parent = body })
	ui.resTitle = label("", {
		Name = "Verdict",
		Size = UDim2.fromOffset(RES_DESK.X, 70),
		FontFace = F.display,
		TextSize = 64,
		ZIndex = 22,
		Parent = body,
	})
	new("UIStroke", { Color = C.ink, Thickness = 4, Transparency = 0.25, Parent = ui.resTitle })
	ui.resTitleScale = new("UIScale", { Parent = ui.resTitle })
	ui.resReason = label("", {
		Name = "Reason",
		Size = UDim2.fromOffset(RES_DESK.X, 22),
		FontFace = F.bodyBold,
		TextSize = 16,
		TextColor3 = C.dim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 22,
		Parent = body,
	})

	-- the xenite card ----------------------------------------------------------------------------------
	local rw = Theme.panel(
		{ Name = "Xenite", Size = UDim2.fromOffset(640, 132), CornerRadius = 22, ZIndex = 22, Parent = body },
		C.pink
	)
	ui.resReward = rw
	-- the crystal in its own light, left
	new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 62, 0.5, 0),
		Size = UDim2.fromOffset(160, 160),
		BackgroundTransparency = 1,
		Image = Icons.Tex.glow,
		ImageColor3 = C.pink,
		ImageTransparency = 0.5,
		ZIndex = 22,
		Parent = rw,
	})
	ui.resCrystal = Xenite.icon(84, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 62, 0.5, 0),
		ZIndex = 23,
		Parent = rw,
	})
	ui.resCrystalScale = new("UIScale", { Parent = ui.resCrystal })
	ui.resRewardHead = label("КСЕНИТ  ·  С БУРА ПО КАНАТКЕ", {
		Position = UDim2.fromOffset(124, 14),
		Size = UDim2.fromOffset(300, 14),
		FontFace = F.head,
		TextSize = 11,
		TextColor3 = C.pink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = rw,
	})
	ui.resRewardAmount = label("", {
		Position = UDim2.fromOffset(122, 26),
		Size = UDim2.fromOffset(300, 58),
		FontFace = F.numHeavy,
		TextSize = 54,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = rw,
	})
	new("UIStroke", { Color = C.ink, Thickness = 3, Transparency = 0.2, Parent = ui.resRewardAmount })
	-- where it went: the shelter's total, right
	ui.resBank = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 16),
		Size = UDim2.fromOffset(150, 50),
		ZIndex = 23,
		Parent = rw,
	})
	ui.resBankHead = label("ВСЕГО В УБЕЖИЩЕ", {
		Size = UDim2.new(1, 0, 0, 14),
		FontFace = F.head,
		TextSize = 10,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 23,
		Parent = ui.resBank,
	})
	ui.resBankAmount = label("", {
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 28),
		FontFace = F.numHeavy,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 23,
		Parent = ui.resBank,
	})
	-- what it was made of
	ui.resRewardLines = new("Frame", {
		Position = UDim2.fromOffset(124, 92),
		Size = UDim2.new(1, -140, 0, 26),
		ClipsDescendants = true,
		ZIndex = 23,
		Parent = rw,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			Wraps = true, -- (DD-110: a phone's narrower card puts the rest on a second row)
		},
	})

	-- the next goal ------------------------------------------------------------------------------------
	local g = Theme.panel(
		{ Name = "Goal", Size = UDim2.fromOffset(640, 84), CornerRadius = 18, ZIndex = 22, Parent = body },
		C.lime
	)
	ui.resGoal = g
	ui.resGoalBar = new("Frame", {
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(0, 4, 1, -32),
		BackgroundColor3 = C.lime,
		Corner = UDim.new(1, 0),
		ZIndex = 23,
		Parent = g,
	})
	ui.resGoalIcon = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 18, 0.5, 0),
		Size = UDim2.fromOffset(48, 48),
		ZIndex = 23,
		Parent = g,
	})
	ui.resGoalHead = label("ДАЛЬШЕ", {
		Position = UDim2.fromOffset(80, 12),
		Size = UDim2.new(1, -96, 0, 14),
		FontFace = F.head,
		TextSize = 11,
		TextColor3 = C.lime,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = g,
	})
	ui.resGoalTitle = label("", {
		Position = UDim2.fromOffset(80, 26),
		Size = UDim2.new(1, -96, 0, 22),
		FontFace = F.display,
		TextSize = 19,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = g,
	})
	ui.resGoalText = label("", {
		Position = UDim2.fromOffset(80, 50),
		Size = UDim2.new(1, -96, 0, 32),
		FontFace = F.body,
		TextSize = 13,
		TextColor3 = C.dim,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 23,
		Parent = g,
	})

	-- «ИТОГИ БОЯ»: a pill that opens the numbers -------------------------------------------------------
	ui.resMore = new("TextButton", {
		Name = "More",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.2,
		Text = "",
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.white, Transparency = 0.8 },
		ZIndex = 22,
		Parent = body,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		},
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 14), Parent = ui.resMore })
	label("ИТОГИ БОЯ", {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = F.head,
		TextSize = 13,
		LayoutOrder = 1,
		ZIndex = 23,
		Parent = ui.resMore,
	})
	ui.resMoreText = label("", {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = F.bodyBold,
		TextSize = 13,
		TextColor3 = C.dim,
		LayoutOrder = 2,
		ZIndex = 23,
		Parent = ui.resMore,
	})
	-- (the font has no ▾: a › turned down)
	ui.resMoreArrow = label("›", {
		Size = UDim2.fromOffset(16, 40),
		Rotation = 90,
		FontFace = F.bodyBold,
		TextSize = 22,
		TextColor3 = C.lime,
		LayoutOrder = 3,
		ZIndex = 23,
		Parent = ui.resMore,
	})
	-- opened: a panel over the screen — the numbers, the build, the squad
	ui.resStatsPanel = Theme.panel({
		Name = "Stats",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(660, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.03,
		CornerRadius = 20,
		Visible = false,
		ZIndex = 30,
		Parent = r, -- (beside the body, above the catcher that closes it; scaled like the body)
	})
	ui.resStatsScale = new("UIScale", { Parent = ui.resStatsPanel })
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 18),
		PaddingTop = UDim.new(0, 16),
		PaddingBottom = UDim.new(0, 18),
		Parent = ui.resStatsPanel,
	})
	new("UIListLayout", {
		Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.resStatsPanel,
	})
	label("ИТОГИ БОЯ", {
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 16),
		FontFace = F.head,
		TextSize = 12,
		TextColor3 = C.dim,
		ZIndex = 31,
		Parent = ui.resStatsPanel,
	})
	ui.resStats = new("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 58),
		ZIndex = 31,
		Parent = ui.resStatsPanel,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
		},
	})
	ui.resBuild = new("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 31,
		Parent = ui.resStatsPanel,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			Wraps = true,
		},
	})
	-- squad contribution: everyone's part, not just kills
	ui.resSquad = new("Frame", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 31,
		Visible = false,
		Parent = ui.resStatsPanel,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			Wraps = true,
		},
	})
	-- a tap anywhere outside the opened panel closes it (a screen-wide catcher behind it)
	local closer = new("TextButton", {
		Name = "CloseStats",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.5,
		Text = "",
		Visible = false,
		ZIndex = 29,
		Parent = r,
	})
	local function setOpen(open: boolean)
		ui.resStatsPanel.Visible = open
		closer.Visible = open
		ui.resMoreArrow.Rotation = if open then -90 else 90
		if open then
			local k = ui.resScale.Scale
			ui.resStatsScale.Scale = k * 0.9
			tween(ui.resStatsScale, 0.25, { Scale = k }, Enum.EasingStyle.Back)
		end
	end
	ui.resSetStatsOpen = setOpen
	ui.resMore.Activated:Connect(function()
		setOpen(not ui.resStatsPanel.Visible)
		Audio.play("ui")
	end)
	closer.Activated:Connect(function()
		setOpen(false)
	end)

	-- the way out --------------------------------------------------------------------------------------
	ui.resButton, ui.resButtonLabel = Theme.button("НА БАЗУ", {
		Name = "Continue",
		Size = UDim2.fromOffset(300, 64),
		ZIndex = 22,
		TextSize = 24,
	}, "primary")
	ui.resButton.Parent = body
	ui.resButtonLabel.ZIndex = 23
	-- DD-053: back to the public camp instead of the squad's base
	ui.resCamp, ui.resCampLabel = Theme.button("В ЛАГЕРЬ", {
		Name = "ToCamp",
		Size = UDim2.fromOffset(180, 64),
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
	ui.resVotes = label("", {
		Size = UDim2.fromOffset(300, 18),
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

-- Places the results for a monitor (one column) or a phone (two columns), with or without В ЛАГЕРЬ.
local function layoutResults(phone: boolean, camp: boolean)
	local size = if phone then RES_PHONE else RES_DESK
	ui.resBody.Size = UDim2.fromOffset(size.X, size.Y)
	local function at(o: GuiObject, x: number, y: number, w: number, h: number)
		o.AnchorPoint = Vector2.zero
		o.Position = UDim2.fromOffset(x, y)
		o.Size = UDim2.fromOffset(w, h)
	end
	-- DD-110: a phone's xenite card is taller, its chips wrap to a second row and its small words are
	-- bigger (they were 6 points on the owner's phone)
	ui.resRewardHead.TextSize = if phone then 13 else 11
	ui.resBankHead.TextSize = if phone then 12 else 10
	ui.resRewardLines.Size = UDim2.new(1, -140, 0, if phone then 62 else 26)
	ui.resRewardLines.UIListLayout.VerticalAlignment = if phone
		then Enum.VerticalAlignment.Top
		else Enum.VerticalAlignment.Center
	if phone then
		local lw, rx, rwid = 460, 484, 336
		ui.resTitle.TextSize = 48
		at(ui.resTitle, 0, 0, lw, 56)
		ui.resReason.TextSize = 16
		at(ui.resReason, 0, 58, lw, 22)
		at(ui.resReward, 0, 94, lw, 172)
		at(ui.resGoal, rx, 0, rwid, 122)
		ui.resGoalText.TextSize = 15
		ui.resGoalText.Size = UDim2.new(1, -96, 0, 66)
		ui.resMore.AnchorPoint = Vector2.zero
		ui.resMore.Position = UDim2.fromOffset(rx, 132)
		local bw = if camp then 196 else rwid
		at(ui.resButton, rx, 182, bw, 64)
		at(ui.resCamp, rx + bw + 10, 182, rwid - bw - 10, 64)
		at(ui.resVotes, rx, 250, rwid, 18)
		ui.resStatsPanel.Size = UDim2.fromOffset(680, 0)
	else
		ui.resTitle.TextSize = 64
		at(ui.resTitle, 0, 0, size.X, 70)
		ui.resReason.TextSize = 16
		at(ui.resReason, 0, 72, size.X, 22)
		at(ui.resReward, 60, 112, 640, 132)
		at(ui.resGoal, 60, 258, 640, 84)
		ui.resGoalText.TextSize = 13
		ui.resGoalText.Size = UDim2.new(1, -96, 0, 32)
		ui.resMore.AnchorPoint = Vector2.new(0.5, 0)
		ui.resMore.Position = UDim2.fromOffset(size.X / 2, 358)
		local total = 300 + (if camp then 190 else 0)
		local x0 = (size.X - total) / 2
		at(ui.resButton, x0, 416, 300, 64)
		at(ui.resCamp, x0 + 310, 416, 180, 64)
		at(ui.resVotes, size.X / 2 - 150, 490, 300, 18)
		ui.resStatsPanel.Size = UDim2.fromOffset(660, 0)
	end
	ui.resCamp.Visible = camp
	ui.resScale.Scale = resultsScale()
end

local function statTile(iconName: string, title: string, value: string, color: Color3, order: number)
	local t = Theme.panel({
		Size = UDim2.fromOffset(116, 58),
		CornerRadius = 14,
		LayoutOrder = order,
		ZIndex = 31,
		Parent = ui.resStats,
	})
	icon(iconName, 16, color, { Position = UDim2.fromOffset(10, 9), ZIndex = 32, Parent = t })
	label(title, {
		Position = UDim2.fromOffset(32, 9),
		Size = UDim2.new(1, -38, 0, 16),
		FontFace = F.head,
		TextSize = 9,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 32,
		Parent = t,
	})
	return label(value, {
		Position = UDim2.fromOffset(10, 28),
		Size = UDim2.new(1, -16, 0, 22),
		FontFace = F.display,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 32,
		Parent = t,
	})
end

-- A chip of the build (the weapon, every card with its rank) in the opened numbers.
local function buildChip(iconName: string, text: string, color: Color3, order: number)
	local chip = new("Frame", {
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.25,
		Corner = UDim.new(1, 0),
		Stroke = { Color = color, Transparency = 0.45, Thickness = 1.5 },
		LayoutOrder = order,
		ZIndex = 31,
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
		ZIndex = 32,
		Parent = chip,
	})
	icon(
		iconName,
		20,
		color,
		{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 33, Parent = disc }
	)
	if text ~= "" then
		label(text, {
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			FontFace = F.head,
			TextSize = 13,
			TextColor3 = color,
			LayoutOrder = 2,
			ZIndex = 32,
			Parent = chip,
		})
	end
end

-- A chip of what the xenite was made of, in the xenite card.
local function rewardChip(text: string, color: Color3?, order: number)
	local chip = new("Frame", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.35,
		Corner = UDim.new(1, 0),
		LayoutOrder = order,
		ZIndex = 24,
		Parent = ui.resRewardLines,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = chip })
	label(text, {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = F.bodyBold,
		TextSize = 12,
		TextColor3 = color or C.text,
		ZIndex = 25,
		Parent = chip,
	})
end

-- After a loss (DD-082): what would have helped, from what the player can do right now.
local function defeatTip(result): (string, string, string)
	local scrap = profile and profile.scrap or 0
	-- DD-112: the gun first — the module this gun can take now, else the nearest one and what it lacks
	local mine = nil
	for _, p in result.players or {} do
		if p.id == myId then
			mine = p
		end
	end
	local wid = mine and mine.weapon or selectedWeapon
	local w = Defs.Weapons[wid]
	if profile and w and (profile.weapons or {})[wid] then
		local rank = Defs.masteryRank(wid, (profile.mastery or {})[wid] or 0)
		local ready, near, nearWhy = nil, nil, nil
		for tier = 1, 3 do
			for _, branch in Modules.Branches do
				local m = Modules.get(Modules.id(wid, branch, tier))
				if m then
					local can, why = Modules.craftable(profile, m, rank)
					if can and (not ready or m.cost < ready.cost) then
						ready = m
					elseif not near and (why == "scrap" or why == "alloy" or why == "mastery") then
						near, nearWhy = m, why
					end
				end
			end
		end
		if ready then
			return "gear",
				"УЛУЧШИ ОРУЖИЕ",
				string.format(
					"«%s»: %s. Хватает ксенита (%d) — в оружейной, навсегда.",
					ready.name,
					ready.text,
					ready.cost
				)
		end
		-- DD-112 stage 3: the evolution, when it can be opened now
		local evo = Evolve.of(wid)
		if evo and Evolve.canOpen(profile, wid) then
			return "evolve",
				"ОТКРОЙ ЭВОЛЮЦИЮ",
				string.format(
					"«%s» в оружейной: %d ксенита и %d сплава. В долгом бою пушка превращается сама.",
					evo.name,
					Defs.Evolve.OpenCost,
					Defs.Evolve.OpenAlloy
				)
		end
		if near and nearWhy == "alloy" then
			return "gear",
				"НУЖЕН СПЛАВ",
				string.format(
					"«%s»: %d ксенита и %d сплава (у тебя %d). Сплав даёт оборона бура.",
					near.name,
					near.cost,
					near.alloy,
					profile.alloy or 0
				)
		elseif near and nearWhy == "scrap" then
			return "gear",
				"КОПИ НА МОДУЛЬ",
				string.format(
					"«%s»: %s. Нужно %d ксенита, у тебя %d.",
					near.name,
					near.text,
					near.cost,
					scrap
				)
		elseif near then
			local left = Defs.masteryNeed(wid, near.mastery) - ((profile.mastery or {})[wid] or 0)
			return "star",
				"НАБЕЙ МАСТЕРСТВО M" .. near.mastery,
				string.format(
					"Ещё %d убийств «%s» — откроется «%s»: %s.",
					math.max(1, left),
					w.short,
					near.name,
					near.text
				)
		end
	end
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
	layoutResults(Theme.phone(), canCamp == true)
	local op = Ops.get(result.op)
	if first then
		ui.resClicked = false
		ui.resSetStatsOpen(false)
		ui.resButtonLabel.Text = if n > 1 then "НА БАЗУ ОТРЯДА" else "НА БАЗУ"
		ui.resCampLabel.Text = "В ЛАГЕРЬ"
		ui.resTitleScale.Scale = 1.6
		tween(ui.resTitleScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
		ui.resShade.BackgroundTransparency = 1
		tween(ui.resShade, 0.5, { BackgroundTransparency = 0.3 })
		Audio.play(if result.victory then "evolve" else "warn", 0.7, if result.victory then 1.1 else 0.8)
	end
	-- the verdict and one line under it: which sortie, why it ended
	local mode = result.mode or "hunt"
	local tag
	if result.op == "STRIKE" then
		tag = "Оборона бура · первый натиск"
		ui.resTitle.Text = if result.victory then "НАТИСК ОТБИТ" else "БУР ПОВРЕЖДЁН"
	elseif mode == "siege" then
		tag = "Оборона бура · уровень " .. (result.siege or 1)
		ui.resTitle.Text = if result.victory then "БУР ВЫСТОЯЛ" else "БУР ПАЛ"
	elseif mode == "raid" then
		tag = "Вторжение" .. (if result.raid then " · " .. result.raid.name else "")
		ui.resTitle.Text = if result.victory
			then "ВТОРЖЕНИЕ УСПЕШНО"
			else "ОБОРОНА ВЫСТОЯЛА"
	else
		tag = (if op.code == "C-A01" then "Контракт" else "Вылазка " .. op.index)
			.. " · "
			.. op.name
			.. (if (result.threat or 1) > 1 then " · угроза " .. result.threat else "")
		ui.resTitle.Text = if result.victory then "ВЫЛАЗКА УДАЛАСЬ" else "ТЫ ПАЛ"
	end
	ui.resTitle.TextColor3 = if result.victory then C.lime else C.red
	local reason = if result.chapterEnd and result.victory
		then "Глава завершена. " .. result.reason
		else result.reason
	ui.resReason.Text = tag .. (if reason and reason ~= "" then "  —  " .. reason else "")

	-- the numbers (opened by «ИТОГИ БОЯ»), and the pill's short line
	local mine = nil
	for _, p in result.players do
		if p.id == id then
			mine = p
		end
	end
	local kills = if mine then mine.kills else result.kills
	ui.resMoreText.Text = string.format("%s  ·  %d убито", Theme.fmtTime(result.time), kills)
	clear(ui.resStats)
	statTile("timer", "ВРЕМЯ", Theme.fmtTime(result.time), C.cyan, 1)
	statTile("skull", if n > 1 then "ТВОИ УБИЙСТВА" else "УБИТО", Theme.commas(kills), C.orange, 2)
	statTile("boom", "УРОН", Theme.commas(if mine then mine.damage or 0 else 0), C.pink, 3)
	statTile(
		"burst",
		"ЛУЧШЕЕ КОМБО",
		if mine and (mine.bestCombo or 0) > 1 then "×" .. mine.bestCombo else "—",
		C.gold,
		4
	)
	statTile("level", "УРОВЕНЬ", tostring(result.level), C.lime, 5)
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
	-- squad contribution (DD-053): damage, kills and rescues of everyone
	clear(ui.resSquad)
	ui.resSquad.Visible = n > 1
	if n > 1 then
		local awards = Showcase.awards(result.players)
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
				ZIndex = 32,
				Parent = ui.resSquad,
				List = {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				},
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
			label(table.concat(parts, "  ·  "), {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 32),
				FontFace = F.bodyBold,
				TextSize = 13,
				ZIndex = 33,
				Parent = chip,
			})
			for k, a in awards[p.id] or {} do
				icon(a[1], 16, C.gold, { LayoutOrder = k * 2, ZIndex = 33, Parent = chip })
				label(a[2], {
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 32),
					FontFace = F.head,
					TextSize = 12,
					TextColor3 = C.gold,
					LayoutOrder = k * 2 + 1,
					ZIndex = 33,
					Parent = chip,
				})
			end
		end
	end

	-- the xenite: the amount, the shelter's total, what it was made of
	ui.resReward.Visible = reward ~= nil
	clear(ui.resRewardLines)
	if reward then
		local got = reward.total + (reward.grant or 0)
		countUp(ui.resRewardAmount, got, "+%s", 1.3)
		ui.resBankAmount.Text = Theme.commas(profile and profile.scrap or 0)
		if first then
			ui.resCrystalScale.Scale = 0.6
			tween(ui.resCrystalScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Elastic)
		end
		local names = {
			skull = "убийства",
			level = "уровни",
			crown = "победа",
			timer = "стойкость",
			hive = "ульи",
		}
		local order = 0
		local function chip(text: string, color: Color3?)
			order += 1
			rewardChip(text, color, order)
		end
		for _, line in reward.lines or {} do
			if line[2] > 0 then
				chip("+" .. line[2] .. " " .. (names[line[1]] or ""))
			end
		end
		if reward.grant then
			chip("+" .. reward.grant .. " первая победа", C.gold)
		end
		if (reward.alloy or 0) > 0 then
			chip("+" .. reward.alloy .. " сплава", C.orange) -- DD-112
		end
		local pr = reward.progress
		if pr and Defs.Weapons[pr.weapon] and (pr.added or 0) > 0 then
			-- DD-112: the gun's mastery, every fight (won or lost)
			chip(
				string.format(
					"%s M%d · +%d%s",
					Defs.Weapons[pr.weapon].short,
					pr.rank or 1,
					pr.added,
					if pr.need
						then string.format(" (до M%d — %d)", (pr.rank or 1) + 1, pr.need - (pr.into or 0))
						else ""
				),
				C.gold
			)
		end
		if reward.mult and reward.mult > 1.001 then
			chip(string.format("угроза ×%.2f", reward.mult), C.orange)
		end
		if reward.bonus and reward.bonus > 1.001 then
			chip(string.format("бонусы ×%.2f", reward.bonus), C.lime)
		end
		if reward.light and reward.light > 0 then
			chip(string.format("Свет Древа +%d%%", math.floor(reward.light * 5 + 0.5)), C.lime)
		end
		if type(reward.mentor) == "table" and #reward.mentor > 0 then
			chip("наставник", C.cyan) -- DD-088: a veteran who won beside a newcomer
		end
		-- a raid's own word on the reward (DD-108: these were cards)
		if reward.capped then
			chip(
				if reward.capped == "pair"
					then "этот бур уже приносил ксенит сегодня"
					else "лимит налётов на сегодня",
				C.dim
			)
		elseif reward.rating and not reward.rating.unrated then
			local d = reward.rating.delta
			chip(
				string.format("рейтинг %s%d → %d", if d >= 0 then "+" else "", d, reward.rating.now),
				if d >= 0 then C.gold else C.red
			)
		end
	end

	-- one nearest goal (DD-052); after a loss, how to come back stronger instead (DD-082)
	local g = if result.victory then Goals.next(profile) else nil
	ui.resGoal.Visible = g ~= nil or not result.victory
	ui.resGoalHead.Text = if result.victory then "ДАЛЬШЕ" else "КАК СТАТЬ СИЛЬНЕЕ"
	local goalColor = C.lime
	clear(ui.resGoalIcon)
	if not result.victory then
		local ic, title, text = defeatTip(result)
		goalColor = C.gold
		ui.resGoalTitle.Text = title
		ui.resGoalText.Text = text
		Icons.disc(ic, 48, goalColor, 23).Parent = ui.resGoalIcon
	elseif g then
		goalColor = if g.structure then Meta.Structures[g.structure].color else C.lime
		ui.resGoalTitle.Text = g.title
		ui.resGoalText.Text = g.text
		Icons.disc(g.icon, 48, goalColor, 23).Parent = ui.resGoalIcon
	end
	ui.resGoalHead.TextColor3 = goalColor
	ui.resGoalBar.BackgroundColor3 = goalColor
	local gs = ui.resGoal:FindFirstChildOfClass("UIStroke")
	if gs then
		gs.Color = goalColor
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
				fitModal(m)
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
