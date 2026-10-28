--!nonstrict
-- The shelter on a phone (DD-102): its own layout, not the monitor's shrunk.
-- The owner's phone (about 800×360 points) showed the monitor layout at half size: a goal card, a row
-- of six station buttons, the title, a signal button and the big go button covered most of the world,
-- and their words were too small to read. Here, at real size:
--   top left   — the goal as one line (icon, title, its action); a tap opens what to do, and a new goal
--                opens it by itself for a few seconds;
--   top right  — xenite, the harvest when there is one, settings;
--   right edge — МЕНЮ: a sheet from the right with every station, the squads, inviting a friend, the
--                signals and your card, as big tiles (they were six tiny pills);
--   bottom     — the go button left of Roblox's jump button, the squad's status above it.
-- Base builds it (BasePhone.build), feeds it each refresh (BasePhone.set) and shows it on a phone
-- instead of the monitor layout.

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local Audio = require(script.Parent.Audio)
local Xenite = require(script.Parent.Xenite)

local C, F = Theme.C, Theme.F
local new, label = Theme.new, Theme.label

local BasePhone = {}

local ui = {}
local onTap: (key: string) -> () = function(_key: string) end
local detailUntil = 0 -- the goal's words stay open until then (math.huge: opened by a tap)
local lastGoal = nil
local sheetOpen = false

local TILES = {
	{ "armory", "ОРУЖЕЙНАЯ", "swords", C.gold },
	{ "build", "МАСТЕРСКАЯ", "gear", C.cyan },
	{ "launch", "ВЫЛАЗКИ", "play", C.lime },
	{ "swarm", "ЛАБОРАТОРИЯ", "hive", C.violet },
	{ "board", "ОТРЯДЫ", "users", C.orange },
	{ "outposts", "ЖИТЕЛИ", "eye", C.pink },
	{ "invite", "ПОЗВАТЬ ДРУГА", "plus", C.lime },
	{ "signals", "СИГНАЛ СОСЕДЯМ", "pin", C.lime },
	{ "card", "МОЯ КАРТОЧКА", "person", C.blue },
	{ "camp", "В ЛАГЕРЬ", "chevrons", C.blue },
}

local function tap(key: string)
	Audio.play("ui")
	onTap(key)
end

local function outline(l: TextLabel, thick: number?)
	new("UIStroke", { Color = C.ink, Thickness = thick or 1.6, Transparency = 0.25, Parent = l })
end

local function roundButton(name: string, icon: string, size: number, accent: Color3, parent)
	local b = new("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.15,
		Text = "",
		Corner = UDim.new(1, 0),
		Stroke = { Color = accent, Thickness = 1.5, Transparency = 0.45 },
		Parent = parent,
	})
	local ic = Icons.new(icon, math.floor(size * 0.52), C.text)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.ZIndex = 2
	ic.Parent = b
	return b
end

local function setSheet(open: boolean)
	if sheetOpen == open then
		return
	end
	sheetOpen = open
	if open then
		ui.overlay.Visible = true
		ui.sheet.Position = UDim2.new(1, 500, 0, 0)
		ui.backdrop.BackgroundTransparency = 1
		Theme.tween(ui.sheet, 0.28, { Position = UDim2.new(1, 0, 0, 0) })
		Theme.tween(ui.backdrop, 0.2, { BackgroundTransparency = 0.5 })
		Audio.play("ui", 0.5, 1.15)
	else
		Theme.tween(
			ui.sheet,
			0.2,
			{ Position = UDim2.new(1, 500, 0, 0) },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		Theme.tween(ui.backdrop, 0.2, { BackgroundTransparency = 1 })
		task.delay(0.21, function()
			if not sheetOpen then
				ui.overlay.Visible = false
			end
		end)
	end
end

local function buildSheet(gui: ScreenGui)
	ui.overlay =
		new("Frame", { Name = "PhoneSheet", Size = UDim2.fromScale(1, 1), ZIndex = 5, Visible = false, Parent = gui })
	ui.backdrop = new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		Parent = ui.overlay,
	})
	ui.backdrop.Activated:Connect(function()
		setSheet(false)
	end)
	local sheet = Theme.panel({
		Name = "Sheet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 474, 1, 0), -- DD-107: three columns, every tile on one screen
		BackgroundTransparency = 0.04,
		CornerRadius = 18,
	}, C.lime)
	sheet.ZIndex = 2
	sheet.Parent = ui.overlay
	ui.sheet = sheet
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		Parent = sheet,
	})
	ui.sheetTag = label("", {
		Size = UDim2.new(1, -48, 0, 13),
		FontFace = F.head,
		TextSize = 10,
		TextColor3 = C.lime,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = sheet,
	})
	ui.sheetTitle = label("", {
		Position = UDim2.fromOffset(0, 13),
		Size = UDim2.new(1, -48, 0, 24),
		FontFace = F.display,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = sheet,
	})
	local close = roundButton("Close", "close", 38, C.white, sheet)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.ZIndex = 3
	close.Activated:Connect(function()
		setSheet(false)
	end)
	local list = new("ScrollingFrame", {
		Name = "Tiles",
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.dim,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 3,
		Parent = sheet,
	})
	new("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -6, 0, 52),
		CellPadding = UDim2.fromOffset(8, 7),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	ui.tiles = {}
	for i, t in TILES do
		local key, text, icon, color = t[1], t[2], t[3], t[4]
		local b = new("TextButton", {
			Name = key,
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = 0.25,
			Text = "",
			LayoutOrder = i,
			Corner = 14,
			Stroke = { Color = color, Transparency = 0.6, Thickness = 1.2 },
			ZIndex = 4,
			Parent = list,
		})
		local d = Icons.disc(icon, 34, color, 5)
		d.AnchorPoint = Vector2.new(0, 0.5)
		d.Position = UDim2.new(0, 8, 0.5, 0)
		d.Parent = b
		label(text, {
			Position = UDim2.fromOffset(48, 0),
			Size = UDim2.new(1, -54, 1, 0),
			FontFace = F.head,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
			Parent = b,
		})
		b.Activated:Connect(function()
			setSheet(false)
			tap(key)
		end)
		ui.tiles[key] = b
	end
end

function BasePhone.build(gui: ScreenGui, on: (key: string) -> ())
	onTap = on
	local root = new("Frame", { Name = "Phone", Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	ui.root = root
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 8),
		Parent = root,
	})

	-- top left: the goal in one line
	local chip = new("TextButton", {
		Name = "Goal",
		Size = UDim2.fromOffset(340, 50),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.18,
		Text = "",
		Corner = 16,
		Stroke = { Color = C.lime, Transparency = 0.45, Thickness = 1.5 },
		Parent = root,
	})
	ui.goal = chip
	ui.goalIcon = new("Frame", { Position = UDim2.fromOffset(7, 7), Size = UDim2.fromOffset(36, 36), Parent = chip })
	label("ЦЕЛЬ  ·  нажми — подробнее", {
		Name = "Tag",
		Position = UDim2.fromOffset(50, 6),
		Size = UDim2.new(1, -60, 0, 12),
		FontFace = F.head,
		TextSize = 9,
		TextColor3 = C.lime,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = chip,
	})
	ui.goalTitle = label("", {
		Position = UDim2.fromOffset(50, 19),
		Size = UDim2.new(1, -60, 0, 24),
		FontFace = F.display,
		TextSize = 15,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = chip,
	})
	new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 10, Parent = ui.goalTitle })
	ui.goalBtn, ui.goalBtnLabel = Theme.button("", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -7, 0.5, 0),
		Size = UDim2.fromOffset(108, 36),
		TextSize = 12,
	}, "primary")
	ui.goalBtn.Parent = chip
	ui.goalBtn.Activated:Connect(function()
		tap("goal")
	end)
	ui.detail = Theme.panel({
		Name = "GoalText",
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		CornerRadius = 14,
	})
	ui.detail.Parent = root
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 9),
		Parent = ui.detail,
	})
	ui.goalText = label("", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		FontFace = F.bodyBold,
		TextSize = 14,
		TextColor3 = C.text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = ui.detail,
	})
	chip.Activated:Connect(function()
		Audio.play("ui", 0.4, 1.2)
		detailUntil = if ui.detail.Visible then 0 else math.huge
	end)

	-- top right: xenite, settings, the harvest
	ui.gear = roundButton("Settings", "gear", 40, C.white, root)
	ui.gear.AnchorPoint = Vector2.new(1, 0)
	ui.gear.Position = UDim2.new(1, 0, 0, 0)
	ui.gear.Activated:Connect(function()
		tap("settings")
	end)
	ui.xenite = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -48, 0, 2),
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.18,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.pink, Transparency = 0.5, Thickness = 1.5 },
		Parent = root,
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		},
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 12), Parent = ui.xenite })
	Xenite.icon(30, { LayoutOrder = 1, Parent = ui.xenite })
	ui.xeniteAmount = label("0", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		FontFace = F.numHeavy,
		TextSize = 17,
		LayoutOrder = 2,
		Parent = ui.xenite,
	})
	ui.harvest = Theme.button("", {
		Name = "Harvest",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 46),
		Size = UDim2.fromOffset(150, 36),
		TextSize = 13,
	}, "primary")
	ui.harvest.Parent = root
	ui.harvest.Visible = false
	ui.harvest.Activated:Connect(function()
		tap("harvest")
	end)

	-- right edge: the menu
	ui.menu = roundButton("Menu", "menu", 54, C.lime, root)
	ui.menu.AnchorPoint = Vector2.new(1, 0.5)
	ui.menu.Position = UDim2.new(1, -2, 0.42, 0)
	local ml = label("МЕНЮ", {
		Position = UDim2.new(0, -14, 1, 2),
		Size = UDim2.new(1, 28, 0, 13),
		FontFace = F.head,
		TextSize = 10,
		TextColor3 = C.text,
		Parent = ui.menu,
	})
	outline(ml, 1.5)
	ui.menu.Activated:Connect(function()
		setSheet(not sheetOpen)
	end)

	-- bottom right, left of Roblox's jump button: go
	ui.play, ui.playLabel = Theme.button("В БОЙ", {
		Name = "Play",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -104, 1, -2),
		Size = UDim2.fromOffset(200, 58),
		TextSize = 22,
	}, "primary")
	ui.play.Parent = root
	ui.playLabel.Position = UDim2.fromOffset(16, -7)
	ui.playIcon = Icons.new("play", 22, C.ink)
	ui.playIcon.AnchorPoint = Vector2.new(0, 0.5)
	ui.playIcon.Position = UDim2.new(0, 18, 0.5, 0)
	ui.playIcon.ZIndex = 3
	ui.playIcon.Parent = ui.play
	ui.playSub = label("", {
		Position = UDim2.new(0, 46, 1, -22),
		Size = UDim2.new(1, -58, 0, 14),
		FontFace = F.head,
		TextSize = 10,
		TextColor3 = C.ink,
		TextTransparency = 0.2,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = ui.play,
	})
	Xenite.inline(ui.playSub)
	ui.playGlow = new("UIStroke", {
		Color = C.lime,
		Thickness = 4,
		Transparency = 0.6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = ui.play,
	})
	ui.play.Activated:Connect(function()
		onTap("play")
	end)
	ui.status = label("", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -108, 1, -64),
		Size = UDim2.fromOffset(300, 16),
		FontFace = F.bodyBold,
		TextSize = 12,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	})
	outline(ui.status)
	ui.hold, ui.holdLabel = Theme.button("ЖДАТЬ ДРУЗЕЙ", {
		Name = "Hold",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -104, 1, -84),
		Size = UDim2.fromOffset(160, 36),
		TextSize = 12,
	})
	ui.hold.Parent = root
	ui.hold.Visible = false
	ui.hold.Activated:Connect(function()
		tap("hold")
	end)

	buildSheet(gui)
end

function BasePhone.setVisible(on: boolean)
	if ui.root then
		ui.root.Visible = on
		if not on then
			sheetOpen = false
			ui.overlay.Visible = false
		end
	end
end

function BasePhone.closeSheet()
	if ui.root then
		setSheet(false)
	end
end

-- state: { tag, title, goal = { key, title, text, icon, color, btn }?, xenite, showXenite, harvest,
-- play = { label, sub, ready }, status, statusColor, hold = { visible, label }, tiles = { [key] = bool } }
function BasePhone.set(s)
	if not ui.root then
		return
	end
	ui.sheetTag.Text = s.tag or ""
	ui.sheetTitle.Text = s.title or ""
	local g = s.goal
	ui.goal.Visible = g ~= nil
	if g then
		ui.goalTitle.Text = g.title
		ui.goalText.Text = g.text
		-- the big button already says it (the first turret): one button for one thing
		local btn = if g.btn ~= s.play.label then g.btn else nil
		ui.goalBtn.Visible = btn ~= nil
		ui.goalBtnLabel.Text = btn or ""
		ui.goalTitle.Size = UDim2.new(1, if btn then -170 else -60, 0, 24)
		ui.goal:FindFirstChild("Tag").Size = ui.goalTitle.Size
		if lastGoal ~= g.key .. g.title then
			lastGoal = g.key .. g.title
			for _, c in ui.goalIcon:GetChildren() do
				c:Destroy()
			end
			Icons.disc(g.icon, 36, g.color, 2).Parent = ui.goalIcon
			ui.goal:FindFirstChildOfClass("UIStroke").Color = g.color
			detailUntil = os.clock() + 7 -- a new goal says what to do by itself, then folds
		end
	else
		detailUntil = 0
	end
	ui.xenite.Visible = s.showXenite == true
	ui.xeniteAmount.Text = Theme.commas(s.xenite or 0)
	ui.harvest.Visible = (s.harvest or 0) > 0
	ui.harvest.Label.Text = "СОБРАТЬ  +" .. (s.harvest or 0)
	local p = s.play
	ui.playLabel.Text = p.label
	ui.playSub.Text = p.sub or ""
	ui.play.BackgroundColor3 = if p.ready then C.ink else C.lime
	ui.playLabel.TextColor3 = if p.ready then C.text else C.ink
	ui.playSub.TextColor3 = if p.ready then C.dim else C.ink
	Icons.recolor(ui.playIcon, if p.ready then C.text else C.ink)
	ui.status.Text = s.status or ""
	ui.status.TextColor3 = s.statusColor or C.dim
	ui.hold.Visible = s.hold and s.hold.visible == true
	ui.holdLabel.Text = s.hold and s.hold.label or ""
	for key, b in ui.tiles do
		b.Visible = s.tiles[key] == true
	end
end

function BasePhone.step(now: number)
	if not (ui.root and ui.root.Visible) then
		return
	end
	ui.playGlow.Transparency = 0.45 + math.sin(now * 3) * 0.25
	ui.playGlow.Thickness = 2.5 + math.sin(now * 3) * 1.5
	local open = ui.goal.Visible and os.clock() < detailUntil and not sheetOpen
	if ui.detail.Visible ~= open then
		ui.detail.Visible = open
	end
end

return BasePhone
