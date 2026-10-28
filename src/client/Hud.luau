--!nonstrict
-- SPOREFALL combat HUD (DD-031). Rebuilt from scratch around one rule: during a fight the screen
-- belongs to the swarm. Everything sits on the edges, nothing repeats, every element has one job.
--
--   top-centre   level badge + XP bar, timer, one goal chip, boss / objective bar when it matters
--   top-left     the build: one small tile per card taken, rank pips
--   top-right    kills, kill streak, squad
--   bottom-centre health (big), ammo (thin), ability chips on PC — between the thumbs on a phone
--   centre       banners, multi-kill callouts, reticle and hit markers (PC), damage vignette

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Theme = require(script.Parent.Theme)
local Audio = require(script.Parent.Audio)
local Icons = require(script.Parent.Icons)
local Preview = require(script.Parent.Preview)
local Settings = require(script.Parent.Settings)

local new, label, tween = Theme.new, Theme.label, Theme.tween
local C, F = Theme.C, Theme.F

local Hud = {}

local gui, overlay
local ui = {}
Hud.ui = ui
local bannerQueue = {}
local bannerBusy = false
local hitT, hitKill = 0, false
local hurtT = 0
local arrows = {}
local comboShown = 0
local comboAt = 0
local shownBoss = nil
local lastLevel = 0
local lastHp = nil
local bloom = 0

local function icon(name: string, size: number, color: Color3, props)
	local i = Icons.new(name, size, color, C.ink)
	for k, v in props or {} do
		i[k] = v
	end
	return i
end

-- Rounded bar: back + fill (+ optional trailing "damage" fill under it).
local function bar(parent, props, color: Color3, trail: boolean?)
	local back = new("Frame", {
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.25,
		Corner = UDim.new(1, 0),
		ClipsDescendants = true,
		Parent = parent,
	})
	for k, v in props do
		back[k] = v
	end
	local tr
	if trail then
		tr = new("Frame", {
			Name = "Trail",
			BackgroundColor3 = C.white,
			BackgroundTransparency = 0.2,
			Size = UDim2.fromScale(1, 1),
			Corner = UDim.new(1, 0),
			ZIndex = back.ZIndex,
			Parent = back,
		})
	end
	local fill = new("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		Size = UDim2.fromScale(1, 1),
		Corner = UDim.new(1, 0),
		ZIndex = back.ZIndex + 1,
		Parent = back,
	})
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 200)),
		Parent = fill,
	})
	return back, fill, tr
end

-- Square-ish ability chip with a cooldown fill and a key cap (PC).
local function chip(parent, iconName: string, color: Color3, props)
	local f = new("Frame", {
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.25,
		Corner = 14,
		ClipsDescendants = true,
		Stroke = { Color = color, Transparency = 0.5, Thickness = 1.5 },
		Parent = parent,
	})
	for k, v in props or {} do
		f[k] = v
	end
	local fill = new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.72,
		Parent = f,
	})
	local ic = icon(
		iconName,
		28,
		color,
		{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), ZIndex = 3, Parent = f }
	)
	local key = label("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, 0, 0, 13),
		FontFace = F.num,
		TextSize = 10,
		TextColor3 = C.dim,
		ZIndex = 4,
		Parent = f,
	})
	return { frame = f, fill = fill, icon = ic, key = key, stroke = f:FindFirstChildOfClass("UIStroke"), color = color }
end

function Hud.init(playerGui: PlayerGui)
	gui = new("ScreenGui", {
		Name = "SporeHUD",
		ResetOnSpawn = false,
		-- (no IgnoreGuiInset beside ScreenInsets: set in no fixed order, it could undo the inset, DD-098)
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 2,
		Enabled = false,
		Parent = playerGui,
	})
	-- Full-screen layer (reticle, vignette, arrows) ignores safe insets.
	overlay = new("ScreenGui", {
		Name = "SporeHUDOverlay",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 1,
		Enabled = false,
		Parent = playerGui,
	})
	local root = new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), Parent = gui })
	ui.root = root
	ui.scale = new("UIScale", { Parent = root })

	-- Top centre: level + XP ------------------------------------------------------------------------
	local top = new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(520, 150),
		Parent = root,
	})
	ui.top = top
	ui.topScale = new("UIScale", { Parent = top })
	ui.xpBack, ui.xpFill = bar(top, { Position = UDim2.fromOffset(34, 12), Size = UDim2.new(1, -40, 0, 12) }, C.lime)
	new("UIStroke", { Color = C.white, Transparency = 0.85, Parent = ui.xpBack })
	ui.xpGlow = new("Frame", {
		Name = "Glow",
		BackgroundColor3 = C.white,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Corner = UDim.new(1, 0),
		ZIndex = 5,
		Parent = ui.xpBack,
	})
	ui.levelBadge = new("Frame", {
		Name = "Level",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(22, 18),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.05,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.lime, Thickness = 2.5 },
		ZIndex = 6,
		Parent = top,
	})
	ui.levelScale = new("UIScale", { Parent = ui.levelBadge })
	ui.level = label("1", {
		Size = UDim2.fromScale(1, 1),
		FontFace = F.numHeavy,
		TextSize = 20,
		TextColor3 = C.lime,
		ZIndex = 7,
		Parent = ui.levelBadge,
	})
	-- Timer + phase
	ui.timer = label("0:00", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 32),
		Size = UDim2.fromOffset(200, 34),
		FontFace = F.display,
		TextSize = 30,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = C.ink,
		Parent = top,
	})
	-- Goal chip
	ui.goal = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.3,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.white, Transparency = 0.85 },
		Parent = top,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14), Parent = ui.goal })
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.goal,
	})
	ui.goalDot = new("Frame", {
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = C.lime,
		Corner = UDim.new(1, 0),
		LayoutOrder = 1,
		Parent = ui.goal,
	})
	ui.goalText = label("", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 28),
		FontFace = F.bodyBold,
		TextSize = 14,
		LayoutOrder = 2,
		Parent = ui.goal,
	})
	-- Objective bar (the extractor, the pylon): appears only when there is something to defend.
	ui.obj = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 106),
		Size = UDim2.fromOffset(360, 30),
		Visible = false,
		Parent = top,
	})
	ui.objIcon = icon("reactor", 22, C.cyan, { Position = UDim2.fromOffset(0, 4), Parent = ui.obj })
	ui.objName = label("БУР", {
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.fromOffset(220, 14),
		FontFace = F.head,
		TextSize = 11,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ui.obj,
	})
	ui.objPct = label("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(120, 14),
		FontFace = F.head,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = ui.obj,
	})
	ui.objBack, ui.objFill =
		bar(ui.obj, { Position = UDim2.fromOffset(28, 17), Size = UDim2.new(1, -28, 0, 9) }, C.cyan)
	-- Boss bar
	ui.boss = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(520, 46),
		Visible = false,
		Parent = top,
	})
	ui.bossName = label("", {
		Size = UDim2.new(1, 0, 0, 18),
		FontFace = F.display,
		TextSize = 15,
		TextColor3 = C.text,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = C.ink,
		Parent = ui.boss,
	})
	ui.bossTag = label("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		Size = UDim2.fromOffset(160, 14),
		FontFace = F.head,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = ui.boss,
	})
	ui.bossBack, ui.bossFill, ui.bossTrail =
		bar(ui.boss, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 14) }, C.red, true)
	new("UIStroke", { Color = C.red, Transparency = 0.4, Thickness = 1.5, Parent = ui.bossBack })

	-- Top left: build tiles ---------------------------------------------------------------------------
	ui.build = new("Frame", {
		Name = "Build",
		Position = UDim2.fromOffset(14, 58),
		Size = UDim2.fromOffset(240, 120),
		Parent = root,
		List = { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 6) },
	})
	ui.slots = {}

	-- Top right: kills, streak, squad ------------------------------------------------------------------
	local tr = new("Frame", {
		Name = "TopRight",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 10),
		Size = UDim2.fromOffset(230, 300),
		Parent = root,
	})
	ui.topRight = tr
	ui.topRightScale = new("UIScale", { Parent = tr })
	ui.killsBox = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.3,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.white, Transparency = 0.85 },
		Parent = tr,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 14), Parent = ui.killsBox })
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.killsBox,
	})
	icon("skull", 20, C.orange, { LayoutOrder = 1, Parent = ui.killsBox })
	ui.kills = label("0", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		FontFace = F.numHeavy,
		TextSize = 18,
		LayoutOrder = 2,
		Parent = ui.killsBox,
	})
	ui.combo = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 44),
		Size = UDim2.fromOffset(180, 66),
		Visible = false,
		Parent = tr,
	})
	ui.comboScale = new("UIScale", { Parent = ui.combo })
	-- DD-084: the streak is a resource — a bar drains while no kill lands; a kill fills it back
	ui.comboBarBack = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 50),
		Size = UDim2.fromOffset(120, 5),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.3,
		Corner = UDim.new(1, 0),
		Parent = ui.combo,
	})
	ui.comboBar = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.gold,
		Corner = UDim.new(1, 0),
		Parent = ui.comboBarBack,
	})
	ui.comboNum = label("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, 0, 0, 34),
		FontFace = F.display,
		TextSize = 38,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.4,
		TextStrokeColor3 = C.ink,
		Parent = ui.combo,
	})
	label("СЕРИЯ", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 32),
		Size = UDim2.new(1, 0, 0, 14),
		FontFace = F.head,
		TextSize = 10,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = ui.combo,
	})
	ui.squad = new("Frame", {
		Name = "Squad",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 100),
		Size = UDim2.fromOffset(210, 160),
		Parent = tr,
		List = { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right },
	})

	-- Bottom centre: vitals ----------------------------------------------------------------------------
	local vit = new("Frame", {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(380, 64),
		Parent = root,
	})
	ui.vitals = vit
	ui.hpBack, ui.hpFill, ui.hpTrail =
		bar(vit, { Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 24) }, C.hp, true)
	ui.hpStroke = new("UIStroke", { Color = C.white, Transparency = 0.8, Thickness = 1.5, Parent = ui.hpBack })
	ui.shieldFill = new("Frame", {
		Name = "Shield",
		BackgroundColor3 = C.blue,
		Size = UDim2.fromScale(0, 0.3),
		Corner = UDim.new(1, 0),
		ZIndex = 4,
		Parent = ui.hpBack,
	})
	ui.heart = icon("heart", 18, C.white, { Position = UDim2.fromOffset(8, 3), ZIndex = 5, Parent = ui.hpBack })
	ui.hpText = label("100", {
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -40, 1, 0),
		FontFace = F.numHeavy,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = C.ink,
		ZIndex = 5,
		Parent = ui.hpBack,
	})
	-- Ammo: a thin bar under the health + the count on the right.
	ui.magBack, ui.magFill = bar(vit, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, -70, 0, 6) }, C.cyan)
	ui.ammo = label("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 38),
		Size = UDim2.fromOffset(66, 18),
		FontFace = F.numHeavy,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = vit,
	})
	ui.reloadText = label("", {
		Position = UDim2.fromOffset(0, -6),
		Size = UDim2.new(1, 0, 0, 18),
		FontFace = F.display,
		TextSize = 16,
		TextColor3 = C.gold,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = C.ink,
		Parent = vit,
	})
	-- Ability chips (PC / gamepad) to the right of the vitals
	ui.dash = chip(vit, "dash", C.cyan, { Position = UDim2.new(1, 14, 0, 6) })
	ui.od = chip(vit, "hammer", C.lime, { Position = UDim2.new(1, 72, 0, 6) })
	ui.super = chip(vit, "chain", C.gold, { Position = UDim2.new(1, 130, 0, 6) }) -- DD-105
	-- Prompt pill above the vitals (S01 lesson, legacy evolution)
	ui.evolve = new("TextButton", {
		Name = "Prompt",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -12),
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.lime,
		Text = "",
		Corner = UDim.new(1, 0),
		Visible = false,
		Parent = vit,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22), Parent = ui.evolve })
	ui.evolveText = label("", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		FontFace = F.display,
		TextSize = 16,
		TextColor3 = C.ink,
		Parent = ui.evolve,
	})
	ui.evolveScale = new("UIScale", { Parent = ui.evolve })
	-- First-seconds controls hint (replaced by nothing once the player is moving and shooting)
	ui.howTo = new("Frame", {
		Name = "HowTo",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -16),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.15,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.lime, Transparency = 0.4, Thickness = 1.5 },
		Visible = false,
		Parent = vit,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = ui.howTo })
	ui.howToText = label("", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		FontFace = F.bodyBold,
		TextSize = 19,
		Parent = ui.howTo,
	})
	-- The camera's three views (DD-082): a card the first fight shows once, and a short toast on a switch
	ui.viewToast = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromOffset(0, 58),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.15,
		Corner = UDim.new(0, 16),
		Stroke = { Color = C.cyan, Transparency = 0.35, Thickness = 2 },
		Visible = false,
		Parent = root,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22), Parent = ui.viewToast })
	ui.viewToastText = label("", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		FontFace = F.bodyBold,
		TextSize = 20,
		RichText = true,
		Parent = ui.viewToast,
	})
	-- View toggle (kept for the V key / gamepad; hidden in the minimal HUD)
	ui.view = new("TextButton", {
		Name = "View",
		Size = UDim2.fromOffset(1, 1),
		Text = "",
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})

	-- Centre: banner -------------------------------------------------------------------------------------
	ui.banner = new("Frame", {
		Name = "Banner",
		-- just under the top bar: the middle of the screen belongs to the hero and the swarm around them
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 166),
		Size = UDim2.fromOffset(760, 110),
		Visible = false,
		Parent = root,
	})
	ui.bannerScale = new("UIScale", { Parent = ui.banner })
	-- DD-082 (owner playtest: «тексты должно быть хорошо видно»): a dark band behind the words
	ui.bannerPlate = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1.3, 0, 0, 112),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = ui.banner,
	})
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.22, 0.15),
			NumberSequenceKeypoint.new(0.78, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = ui.bannerPlate,
	})
	-- the picture (an icon, or the creature turning) stands left of the title, not above it: above is
	-- the boss bar, below is the hero
	ui.bannerVisual = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -150, 0, 40),
		Size = UDim2.fromOffset(56, 56),
		Parent = ui.banner,
	})
	ui.bannerText = label("", {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 52),
		FontFace = F.display,
		TextSize = 40,
		TextStrokeTransparency = 0.35,
		TextStrokeColor3 = C.ink,
		Parent = ui.banner,
	})
	ui.bannerLine = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(0, 3),
		BackgroundColor3 = C.white,
		Corner = UDim.new(1, 0),
		Parent = ui.banner,
	})
	ui.bannerSub = label("", {
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 34),
		FontFace = F.bodyBold,
		TextSize = 22,
		TextWrapped = true,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = C.ink,
		Parent = ui.banner,
	})
	ui.burst = label("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.63), -- above the toasts at 0.74
		Size = UDim2.fromOffset(600, 50),
		FontFace = F.display,
		TextSize = 30,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		TextStrokeColor3 = C.ink,
		Parent = root,
	})
	ui.burstScale = new("UIScale", { Parent = ui.burst })

	-- Overlay: reticle, hit marker, reload ring, vignette, arrows ---------------------------------------
	ui.reticle = new(
		"Frame",
		{ Name = "Reticle", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(60, 60), Parent = overlay }
	)
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = C.white,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.ink, Thickness = 1.5, Transparency = 0.2 },
		Parent = ui.reticle,
	})
	ui.reticleTicks = {}
	for i = 0, 3 do
		local vertical = i % 2 == 1
		local t = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = if vertical then UDim2.fromOffset(3, 10) else UDim2.fromOffset(10, 3),
			BackgroundColor3 = C.white,
			Corner = UDim.new(1, 0),
			Stroke = { Color = C.ink, Thickness = 1.5, Transparency = 0.2 },
			Parent = ui.reticle,
		})
		table.insert(ui.reticleTicks, t)
	end
	ui.hit = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		Visible = false,
		Parent = ui.reticle,
	})
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(a) * 11, 0.5, math.sin(a) * 11),
			Size = UDim2.fromOffset(9, 3),
			Rotation = math.deg(a),
			BackgroundColor3 = C.white,
			Corner = UDim.new(1, 0),
			Parent = ui.hit,
		})
	end
	ui.reloadRing = icon("reload", 34, C.gold, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Visible = false,
		Parent = ui.reticle,
	})
	-- Vignette: soft red edges on hurt / low health
	ui.vignette = {}
	for i, spec in
		{
			{ UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0), 90 },
			{ UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0.86), -90 },
			{ UDim2.fromScale(0.1, 1), UDim2.fromScale(0, 0), 0 },
			{ UDim2.fromScale(0.1, 1), UDim2.fromScale(0.9, 0), 180 },
		}
	do
		local f = new("Frame", {
			Size = spec[1],
			Position = spec[2],
			BackgroundColor3 = C.red,
			BackgroundTransparency = 0,
			Visible = false,
			Parent = overlay,
		})
		new("UIGradient", {
			Rotation = spec[3],
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Parent = f,
		})
		ui.vignette[i] = f
	end
	-- Off-screen arrows
	for i = 1, 6 do
		local f = new(
			"Frame",
			{ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(120, 72), Visible = false, Parent = overlay }
		)
		local head = icon(
			"chevrons",
			36,
			C.red,
			{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.35), Parent = f }
		)
		local tag = label("", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.35, 21),
			Size = UDim2.fromOffset(120, 16),
			FontFace = F.display,
			TextSize = 14,
			TextStrokeTransparency = 0.4,
			TextStrokeColor3 = C.ink,
			Parent = f,
		})
		arrows[i] = { frame = f, head = head, tag = tag }
	end
	if game:GetService("RunService"):IsStudio() then
		ui.debug = label("", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -6),
			Size = UDim2.fromOffset(500, 14),
			FontFace = F.mono,
			TextSize = 11,
			TextColor3 = C.dim,
			TextTransparency = 0.3,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = overlay,
		})
	end
end

function Hud.setVisible(v: boolean)
	gui.Enabled = v
	overlay.Enabled = v
end

-- While a full-screen choice is open (cards, results) the combat HUD steps aside.
function Hud.setDimmed(dimmed: boolean)
	ui.root.Visible = not dimmed
end

-- Banners -------------------------------------------------------------------------------------------
local function setBannerVisual(visual: string?, color: Color3)
	for _, c in ui.bannerVisual:GetChildren() do
		c:Destroy()
	end
	if not visual or visual == "" then
		return
	end
	if visual:sub(1, 1) == "@" then
		local kind = tonumber(visual:sub(2))
		if kind then
			ui.bannerVisual.Size = UDim2.fromOffset(96, 96)
			Preview.creature(ui.bannerVisual, kind, { spin = true, zoom = 0.95 })
		end
	else
		ui.bannerVisual.Size = UDim2.fromOffset(52, 52)
		icon(visual, 52, color, { Parent = ui.bannerVisual })
	end
end

local function nextBanner()
	local b = table.remove(bannerQueue, 1)
	if not b then
		bannerBusy = false
		return
	end
	bannerBusy = true
	ui.banner.Visible = true
	ui.bannerText.Text = b.text
	ui.bannerText.TextColor3 = b.color
	ui.bannerLine.BackgroundColor3 = b.color
	-- DD-107 (owner, phone: «надписи Штурм: бур… никто не успевает прочитать, а на экране мельтешит»):
	-- on a phone a banner is only its title, small, on no band — a glance, not a sign over the fight
	local phone = Theme.phone()
	ui.bannerSub.Text = if phone then "" else b.sub
	ui.bannerText.TextSize = if phone then 30 else 40
	-- (DD-110: on a phone higher, between the goal row and the hero — it stood on the hero's head)
	ui.banner.Position = UDim2.new(0.5, 0, 0, if phone then 92 else 166)
	ui.bannerPlate.Visible = not phone
	ui.bannerLine.Visible = not phone
	setBannerVisual(if phone then nil else b.visual, b.color)
	if phone then
		ui.bannerText.TextTransparency = 1
		ui.bannerScale.Scale = 1.1
		tween(ui.bannerScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(ui.bannerText, 0.2, { TextTransparency = 0 })
		task.delay(1.8, function()
			tween(ui.bannerText, 0.3, { TextTransparency = 1 })
			task.wait(0.32)
			ui.banner.Visible = false
			nextBanner()
		end)
		return
	end
	-- the picture sits just left of the title, however long the title is
	ui.bannerVisual.Position = UDim2.new(0.5, -ui.bannerText.TextBounds.X / 2 - 14, 0, 34)
	ui.bannerText.TextTransparency = 1
	ui.bannerSub.TextTransparency = 1
	ui.bannerLine.Size = UDim2.fromOffset(0, 3)
	ui.bannerScale.Scale = 1.25
	Audio.play("banner")
	tween(ui.bannerScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(ui.bannerText, 0.2, { TextTransparency = 0 })
	tween(ui.bannerSub, 0.45, { TextTransparency = 0 })
	tween(ui.bannerLine, 0.5, { Size = UDim2.fromOffset(220, 3) })
	ui.bannerPlate.BackgroundTransparency = 1
	tween(ui.bannerPlate, 0.3, { BackgroundTransparency = 0.35 })
	-- long enough to be read: ~15 letters a second on top of a moment to notice it
	local read = 1.6 + ((utf8.len(b.text) or 0) + (utf8.len(b.sub) or 0)) / 15
	local hold = math.max(b.duration, read)
	if #bannerQueue > 0 then
		hold = math.min(hold, math.max(2.6, read * 0.8))
	end
	task.delay(hold, function()
		tween(ui.bannerPlate, 0.25, { BackgroundTransparency = 1 })
		tween(ui.bannerText, 0.25, { TextTransparency = 1 })
		tween(ui.bannerSub, 0.25, { TextTransparency = 1 })
		tween(ui.bannerLine, 0.25, { Size = UDim2.fromOffset(0, 3) })
		task.wait(0.27)
		ui.banner.Visible = false
		setBannerVisual(nil, C.text)
		nextBanner()
	end)
end

function Hud.banner(text: string, sub: string, color: Color3, duration: number, visual: string?)
	-- (a phone keeps only the newest one waiting: old news is no news)
	if #bannerQueue >= (if Theme.phone() then 1 else 3) then
		table.remove(bannerQueue, 1)
	end
	table.insert(bannerQueue, { text = text, sub = sub, color = color, duration = duration, visual = visual })
	if not bannerBusy then
		nextBanner()
	end
end

local toastToken = 0
local function toast(text: string, seconds: number)
	toastToken += 1
	local token = toastToken
	ui.viewToastText.Text = text
	ui.viewToast.Visible = true
	ui.viewToast.BackgroundTransparency = 1
	ui.viewToastText.TextTransparency = 1
	tween(ui.viewToast, 0.25, { BackgroundTransparency = 0.15 })
	tween(ui.viewToastText, 0.25, { TextTransparency = 0 })
	task.delay(seconds, function()
		if token == toastToken then
			tween(ui.viewToast, 0.3, { BackgroundTransparency = 1 })
			tween(ui.viewToastText, 0.3, { TextTransparency = 1 })
			task.delay(0.32, function()
				if token == toastToken then
					ui.viewToast.Visible = false
				end
			end)
		end
	end)
end

local VIEW_ORDER = { top = 1, third = 2, first = 3 }
local function viewKey(device: string): string
	return if device == "touch"
		then "кнопка вида справа"
		elseif device == "gamepad" then "крестовина ↑"
		else "клавиша V"
end

-- Called every frame; the minimal HUD shows no permanent view indicator.
function Hud.setView(_mode: string, _iconName: string, _caption: string?, _device: string) end

-- Camera view is switched with V / D-pad up / the view button: a toast names the view it went to.
-- DD-106: the super goes off — its name punches in over the fight, the screen's edges flash its colour.
local superFx = nil
function Hud.superCallout(name: string, color: Color3)
	if not superFx then
		local edge = new("ImageLabel", {
			Name = "SuperEdge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.6, 2.2),
			BackgroundTransparency = 1,
			Image = Icons.Tex.glow,
			ImageTransparency = 1,
			ZIndex = 1,
			Parent = overlay,
		})
		-- a glow turned inside out: bright at the rim, clear in the middle
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.25, 0.85),
				NumberSequenceKeypoint.new(0.75, 0.85),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Parent = edge,
		})
		local title = label("", {
			Name = "SuperName",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.22), -- (above the hero, under the level bar)
			Size = UDim2.fromOffset(600, 60),
			FontFace = F.display,
			TextSize = 40,
			TextTransparency = 1,
			ZIndex = 30,
			Parent = gui,
		})
		local stroke = new("UIStroke", { Color = C.ink, Thickness = 4, Transparency = 1, Parent = title })
		local scale = new("UIScale", { Parent = title })
		superFx = { edge = edge, title = title, stroke = stroke, scale = scale, token = 0 }
	end
	local fx = superFx
	fx.token += 1
	local my = fx.token
	fx.edge.ImageColor3 = color
	fx.edge.ImageTransparency = 0.15
	Theme.tween(fx.edge, 0.5, { ImageTransparency = 1 })
	fx.title.Text = name
	fx.title.TextColor3 = color
	fx.title.TextSize = if Theme.phone() then 24 else 40
	fx.title.TextTransparency = 0
	fx.stroke.Transparency = 0.1
	fx.scale.Scale = 1.6
	Theme.tween(fx.scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(0.75, function()
		if fx.token == my then
			Theme.tween(fx.title, 0.35, { TextTransparency = 1 })
			Theme.tween(fx.stroke, 0.35, { Transparency = 1 })
			Theme.tween(fx.scale, 0.35, { Scale = 0.9 })
		end
	end)
end

function Hud.viewSwitched(mode: string, caption: string?, device: string)
	toast(
		string.format(
			'<font color="#54EEFF">%s</font>  ·  вид %d из 3  ·  %s — дальше',
			caption or mode,
			VIEW_ORDER[mode] or 1,
			viewKey(device)
		),
		2.2
	)
end

-- The first fight teaches the views once (owner playtest: «подсказка по камере, что есть 3 режима»).
function Hud.cameraHint(device: string)
	toast(
		string.format(
			'<font color="#54EEFF">КАМЕРА · 3 ВИДА</font>  ·  сверху → из-за плеча → от первого лица  ·  %s',
			viewKey(device)
		),
		7
	)
end

-- Reticle bloom: each shot kicks the ticks outward (pixels); they settle back.
function Hud.recoil(amount: number)
	bloom = math.min(bloom + amount, 34)
end

function Hud.hitmarker(kill: boolean)
	hitT = os.clock()
	hitKill = kill
end

local BURST_WORDS =
	{ { 25, "ОПУСТОШЕНИЕ", C.red }, { 15, "МЯСОРУБКА", C.orange }, { 0, "РАЗГРОМ", C.gold } }
function Hud.burst(n: number)
	if Theme.phone() then
		return -- DD-107: on a phone the kill burst is the swarm bursting, not a word over it
	end
	for _, w in BURST_WORDS do
		if n >= w[1] then
			ui.burst.Text = string.format('%s  <font size="40">×%d</font>', w[2], n)
			ui.burst.TextColor3 = w[3]
			break
		end
	end
	ui.burst.TextTransparency = 0
	ui.burst.TextStrokeTransparency = 0.3
	ui.burstScale.Scale = 1.4
	tween(ui.burstScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(
		ui.burst,
		1,
		{ TextTransparency = 1, TextStrokeTransparency = 1 },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
end

-- A streak milestone (DD-084): the word big in the middle, under the hero.
function Hud.milestone(word: string, n: number, color: Color3)
	if Theme.phone() then
		return -- DD-108: the streak counter in the corner already says it; no word over the hero
	end
	ui.burst.Text = string.format('%s  <font size="46">×%d</font>', word, n)
	ui.burst.TextColor3 = color
	ui.burst.TextSize = 42
	ui.burst.TextTransparency = 0
	ui.burst.TextStrokeTransparency = 0.2
	ui.burstScale.Scale = 1.9
	tween(ui.burstScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(
		ui.burst,
		1.6,
		{ TextTransparency = 1, TextStrokeTransparency = 1 },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	task.delay(1.7, function()
		ui.burst.TextSize = 30
	end)
end

function Hud.hurt()
	hurtT = os.clock()
end

local function keyLabel(device: string, pc: string, pad: string): string
	return if device == "pc" then pc elseif device == "gamepad" then pad else ""
end

-- Build tiles: one per card family taken, in the order they were picked.
local buildOrder = {}
local function updateBuild(me)
	for _, id in Defs.UpgradeOrder do
		if me.ranks[id] and not table.find(buildOrder, id) then
			table.insert(buildOrder, id)
		end
	end
	for i, id in buildOrder do
		local def = Defs.Upgrades[id]
		local s = ui.slots[i]
		if not s then
			local f = new("Frame", {
				Size = UDim2.fromOffset(40, 46),
				BackgroundColor3 = C.ink,
				BackgroundTransparency = 0.25,
				Corner = 10,
				LayoutOrder = i,
				Parent = ui.build,
			})
			local stroke = new("UIStroke", { Color = def.color, Transparency = 0.45, Thickness = 1.5, Parent = f })
			local pips = {}
			for k = 1, 3 do
				pips[k] = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, (k - 2) * 8, 1, -4),
					Size = UDim2.fromOffset(6, 4),
					BackgroundColor3 = def.color,
					Corner = UDim.new(1, 0),
					Parent = f,
				})
			end
			s = { frame = f, stroke = stroke, pips = pips, scale = new("UIScale", { Parent = f }) }
			icon(
				def.icon,
				26,
				def.color,
				{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5), Parent = f }
			)
			ui.slots[i] = s
			s.scale.Scale = 1.6
			tween(s.scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		local rank = me.ranks[id] or 0
		if s.rank ~= rank then
			if s.rank then
				s.scale.Scale = 1.3
				tween(s.scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			s.rank = rank
			for k = 1, 3 do
				s.pips[k].BackgroundTransparency = if k <= rank then 0 else 0.75
			end
		end
	end
end

function Hud.reset()
	table.clear(buildOrder)
	for _, s in ui.slots do
		s.frame:Destroy()
	end
	table.clear(ui.slots)
	lastLevel = 0
	lastHp = nil
	shownBoss = nil
end

-- DD-110 (owner, the phone: «в бою верхнюю часть перекомпоновать»): on a phone Roblox's top bar holds one
-- row — the level, its bar, the timer — from Roblox's buttons to the kill count; the goal and the drill's
-- gauge share one row under it, the boss bar under that. A monitor keeps the centred column.
local topPhone = nil
local TOP_PHONE = 1.45
local function layoutTop(phone: boolean, k: number, stripLeft: number, stripH: number)
	local top = ui.top
	if phone then
		-- (drawn 1.45× the HUD's scale: at a phone's 0.52 the row was 7-point words in a 58-point bar)
		local s = TOP_PHONE
		local rootW = ui.root.AbsoluteSize.X / k
		local sh = stripH / k
		local left = (stripLeft + 10) / k
		local right = rootW - 14 - ui.killsBox.AbsoluteSize.X / k - 16
		local topY = -sh / 2 - 18 * s
		top.AnchorPoint = Vector2.zero
		top.Position = UDim2.fromOffset(left, topY)
		top.Size = UDim2.fromOffset(math.max(200, right - left) / s, 150)
		ui.topRight.Position = UDim2.new(1, -14, 0, topY)
		-- the goal and the drill side by side, centred on the screen just under the bar
		local cx, ty = (rootW / 2 - left) / s, (8 - topY) / s
		local obj = ui.obj.Visible
		ui.goal.AnchorPoint = Vector2.new(if obj then 1 else 0.5, 0)
		ui.goal.Position = UDim2.fromOffset(cx - (if obj then 6 else 0), ty)
		ui.obj.AnchorPoint = Vector2.new(if ui.goal.Visible then 0 else 0.5, 0)
		ui.obj.Position = UDim2.fromOffset(cx + (if ui.goal.Visible then 6 else 0), ty)
		ui.boss.Position = UDim2.fromOffset(cx, ty + 38)
		ui.boss.Size = UDim2.fromOffset(math.min(520, (rootW - 60) / s), 46)
		if topPhone == true then
			return
		end
		topPhone = true
		ui.topScale.Scale = s
		ui.topRightScale.Scale = s
		ui.xpBack.Size = UDim2.new(1, -40 - 86, 0, 12)
		ui.timer.AnchorPoint = Vector2.new(1, 0.5)
		ui.timer.Position = UDim2.new(1, 0, 0, 18)
		ui.timer.Size = UDim2.fromOffset(80, 30)
		ui.timer.TextSize = 26
		ui.timer.TextXAlignment = Enum.TextXAlignment.Right
		-- the drill as a gauge: its icon, the bar, the percent (the name was 6 points on a phone)
		ui.obj.Size = UDim2.fromOffset(220, 28)
		ui.objName.Visible = false
		ui.objIcon.Position = UDim2.fromOffset(0, 3)
		ui.objBack.Position = UDim2.fromOffset(28, 10)
		ui.objBack.Size = UDim2.new(1, -28 - 54, 0, 9)
		ui.objPct.Size = UDim2.fromOffset(50, 28)
		ui.objPct.TextSize = 14
		ui.boss.AnchorPoint = Vector2.new(0.5, 0)
		return
	end
	if topPhone == false then
		return
	end
	topPhone = false
	ui.topScale.Scale = 1
	ui.topRightScale.Scale = 1
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 10)
	top.Size = UDim2.fromOffset(520, 150)
	ui.xpBack.Size = UDim2.new(1, -40, 0, 12)
	ui.timer.AnchorPoint = Vector2.new(0.5, 0)
	ui.timer.Position = UDim2.new(0.5, 0, 0, 32)
	ui.timer.Size = UDim2.fromOffset(200, 34)
	ui.timer.TextSize = 30
	ui.timer.TextXAlignment = Enum.TextXAlignment.Center
	ui.goal.AnchorPoint = Vector2.new(0.5, 0)
	ui.goal.Position = UDim2.new(0.5, 0, 0, 70)
	ui.obj.AnchorPoint = Vector2.new(0.5, 0)
	ui.obj.Position = UDim2.new(0.5, 0, 0, 106)
	ui.obj.Size = UDim2.fromOffset(360, 30)
	ui.objName.Visible = true
	ui.objIcon.Position = UDim2.fromOffset(0, 4)
	ui.objBack.Position = UDim2.fromOffset(28, 17)
	ui.objBack.Size = UDim2.new(1, -28, 0, 9)
	ui.objPct.Size = UDim2.fromOffset(120, 14)
	ui.objPct.TextSize = 11
	ui.boss.AnchorPoint = Vector2.new(0.5, 0)
	ui.boss.Position = UDim2.new(0.5, 0, 0, 104)
	ui.boss.Size = UDim2.fromOffset(520, 46)
end

-- Frame update --------------------------------------------------------------------------------------
function Hud.update(run, me, extra, dt: number)
	local now = os.clock()
	local vs = workspace.CurrentCamera.ViewportSize
	-- DD-100: a phone (~390 points tall) may go further down than a small monitor: at the old floor of
	-- 0.72 the HUD took the whole screen
	local k = math.clamp(math.min(vs.Y / 820, vs.X / 1100), if Theme.phone() then 0.52 else 0.72, 1.2)
	ui.scale.Scale = k
	ui.root.Size = UDim2.fromScale(1 / k, 1 / k)
	-- DD-109: on a phone the level, its bar, the timer, the goal and the kill count stand in Roblox's top
	-- bar (right of its buttons, ~58 points that were empty): the fight gets the screen under it
	local stripLeft, _, stripH = Theme.topStrip()
	local up = if Theme.phone() and stripH > 0 then (stripH + 2) / k else 0
	ui.topRight.Position = UDim2.new(1, -14, 0, 10)
	ui.build.Position = UDim2.fromOffset(14, if up > 0 then 8 else 58)
	layoutTop(up > 0, k, stripLeft, stripH)
	local touch = extra.device == "touch"
	if run.t < 0.5 and lastLevel > 1 then
		Hud.reset()
	end
	-- Timer and goal
	ui.timer.Text = Theme.fmtTime(run.t)
	ui.timer.TextColor3 = if run.boss and run.boss.enraged then C.red else C.text
	local mission = run.mission
	local goal = mission and mission.goal or ""
	if mission and mission.finaleLeft then
		goal = goal .. "  ·  " .. mission.finaleLeft .. " с"
	elseif mission and mission.deadlineLeft and mission.deadlineLeft <= 120 then
		goal = goal .. "  ·  " .. Theme.fmtTime(mission.deadlineLeft)
	end
	if mission and mission.relay and mission.relay.alive and mission.state == "FIGHT" then
		goal = goal
			.. string.format(
				"  ·  вышка %d%%",
				math.ceil(mission.relay.hp / math.max(1, mission.relay.max) * 100)
			)
	end
	if run.hive then
		goal = string.format("Ульи %d/3  ·  %d с", run.hive, math.ceil(run.hiveEnds or 0))
	end
	if run.mode == "siege" and run.label then
		goal = run.label .. "  ·  " .. goal
	end
	ui.goal.Visible = goal ~= ""
	ui.goalText.Text = goal
	local urgent = mission and mission.deadlineLeft and mission.deadlineLeft <= 60
	ui.goalDot.BackgroundColor3 = if urgent
		then C.red
		elseif mission and mission.state == "FINALE" then C.gold
		else C.lime
	ui.goalDot.BackgroundTransparency = 0.5 + math.sin(now * 5) * 0.5
	ui.goalText.TextColor3 = if urgent then C.red else C.text
	-- Boss (or the enemy extractor in a raid)
	ui.boss.Visible = run.boss ~= nil or run.core ~= nil
	if run.core and not run.boss then
		ui.bossName.Text = run.core.name
		shownBoss = nil
		local frac = math.clamp(run.core.hp, 0, 1)
		ui.bossFill.Size = UDim2.fromScale(frac, 1)
		local trail = ui.bossTrail.Size.X.Scale
		ui.bossTrail.Size =
			UDim2.fromScale(if trail > frac then trail - (trail - frac) * math.min(1, dt * 2) else frac, 1)
		ui.bossTag.Text = "ВРАЖЕСКИЙ БУР"
		ui.bossTag.TextColor3 = C.orange
	end
	if run.boss then
		if shownBoss ~= run.boss.kind then
			shownBoss = run.boss.kind
			ui.bossName.Text = Defs.EnemyByIndex[run.boss.kind].name
		end
		local frac = math.clamp(run.boss.hp, 0, 1)
		ui.bossFill.Size = UDim2.fromScale(frac, 1)
		local trail = ui.bossTrail.Size.X.Scale
		ui.bossTrail.Size =
			UDim2.fromScale(if trail > frac then trail - (trail - frac) * math.min(1, dt * 2) else frac, 1)
		ui.bossTag.Text = if run.boss.invulnerable
			then "НЕУЯЗВИМ"
			elseif run.boss.exposed then "УЯЗВИМ ×1.8"
			elseif run.boss.enraged then "ЯРОСТЬ"
			else ""
		ui.bossTag.TextColor3 = if run.boss.exposed then C.lime else C.red
	end
	-- Objective under defence (extractor)
	local rc = mission and mission.reactor
	ui.obj.Visible = rc ~= nil and run.boss == nil
	if rc then
		local frac = math.clamp(rc.hp / math.max(1, rc.max), 0, 1)
		local col = if frac < 0.25 then C.red elseif frac < 0.5 then C.orange else C.cyan
		local flash = run.t - (rc.hitT or -99) < 0.35
		ui.objFill.Size = UDim2.fromScale(frac, 1)
		ui.objFill.BackgroundColor3 = if flash then C.white else col
		-- what the bar stands for, in the fight itself: the drill is the shelter's utility (DD-065)
		local rname = string.upper(rc.name or "БУР")
		ui.objName.Text = if rname == "БУР" then "БУР · КСЕНИТ ДЛЯ УБЕЖИЩА" else rname
		ui.objPct.Text = (if (rc.shield or 0) > 0 then "ЩИТ " .. rc.shield .. "  ·  " else "")
			.. math.ceil(frac * 100)
			.. "%"
		ui.objPct.TextColor3 = col
		Icons.recolor(ui.objIcon, if flash then C.red else col)
	end
	-- XP and level
	local xpFrac = if run.xpNeed <= 0 then 1 else math.clamp(run.xp / math.max(1, run.xpNeed), 0, 1)
	local cur = ui.xpFill.Size.X.Scale
	ui.xpFill.Size = UDim2.fromScale(if xpFrac < cur then xpFrac else cur + (xpFrac - cur) * math.min(1, dt * 10), 1)
	ui.level.Text = tostring(run.level)
	if run.level ~= lastLevel then
		if lastLevel > 0 then
			ui.levelScale.Scale = 1.5
			tween(ui.levelScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
			ui.xpGlow.BackgroundTransparency = 0
			tween(ui.xpGlow, 0.6, { BackgroundTransparency = 1 })
		end
		lastLevel = run.level
	end
	ui.kills.Text = Theme.commas(run.kills)
	-- Squad
	local squadCount = #run.players
	ui.squad.Visible = squadCount > 1
	if squadCount > 1 then
		local rows = {}
		for _, c in ui.squad:GetChildren() do
			if c:IsA("Frame") then
				rows[c.Name] = c
			end
		end
		for _, p in run.players do
			if not me or p.id ~= me.id then
				local k = tostring(p.id)
				local row = rows[k]
				if not row then
					row = new("Frame", {
						Name = k,
						Size = UDim2.fromOffset(200, 34),
						BackgroundColor3 = C.ink,
						BackgroundTransparency = 0.3,
						Corner = 10,
						Parent = ui.squad,
					})
					label(p.name, {
						Name = "N",
						Position = UDim2.fromOffset(12, 2),
						Size = UDim2.new(1, -20, 0, 16),
						FontFace = F.bodyBold,
						TextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						Parent = row,
					})
					local b, f = bar(row, { Position = UDim2.fromOffset(12, 21), Size = UDim2.new(1, -24, 0, 6) }, C.hp)
					b.Name = "B"
					f.Name = "HP"
				end
				rows[k] = nil
				row.B.HP.Size = UDim2.fromScale(math.clamp(p.hp / p.maxHp, 0, 1), 1)
				row.N.Text = p.name
					.. (
						if p.downed
							then string.format("  · РАНЕН %dс %d%%", p.bleed or 0, p.revive or 0)
							elseif not p.alive then "  · ВЫБЫЛ"
							elseif p.offer then "  · выбирает"
							else ""
					)
				row.N.TextColor3 = if p.alive then C.text else C.red
			end
		end
		for _, stale in rows do
			stale:Destroy()
		end
	end
	if me then
		local wdef = Defs.Weapons[me.weapon]
		updateBuild(me)
		-- Health
		local hpFrac = math.clamp(me.hp / me.maxHp, 0, 1)
		ui.hpFill.Size = UDim2.fromScale(hpFrac, 1)
		local trail = ui.hpTrail.Size.X.Scale
		ui.hpTrail.Size =
			UDim2.fromScale(if trail > hpFrac then trail - (trail - hpFrac) * math.min(1, dt * 3) else hpFrac, 1)
		ui.hpFill.BackgroundColor3 = if hpFrac < 0.3 then C.red else C.hp
		ui.shieldFill.Size = UDim2.fromScale(math.clamp(me.shield / me.maxHp, 0, 1), 0.3)
		ui.hpText.Text = string.format(
			'%d<font size="12" transparency="0.4"> / %d</font>%s',
			me.hp,
			me.maxHp,
			if me.shield > 0 then string.format('<font size="12" color="#78B0FF">  +%d</font>', me.shield) else ""
		)
		if lastHp and me.hp > lastHp + 4 then
			ui.hpStroke.Color = C.lime
			ui.hpStroke.Transparency = 0
			tween(ui.hpStroke, 0.6, { Transparency = 0.8 })
		end
		if lastHp and me.hp < lastHp then
			ui.hpStroke.Color = C.white
		end
		lastHp = me.hp
		local lowHp = hpFrac < 0.3 and me.alive
		Icons.recolor(ui.heart, if lowHp and math.sin(now * 8) > 0 then C.red else C.white)
		-- Ammo / heat
		if wdef.kind == "beam" then
			ui.ammo.Text = (100 - me.heat) .. "%"
			ui.magFill.Size = UDim2.fromScale(1 - me.heat / 100, 1)
			ui.magFill.BackgroundColor3 = if me.overheated then C.red elseif me.heat > 70 then C.orange else C.violet
			ui.reloadText.Text = if me.overheated then "ПЕРЕГРЕВ" else ""
			ui.reloadText.TextColor3 = C.red
		else
			ui.ammo.Text = string.format('%d<font size="11" transparency="0.45">/%d</font>', me.ammo, me.mag)
			ui.magFill.Size = UDim2.fromScale(if me.reload > 0 then me.reload else me.ammo / math.max(1, me.mag), 1)
			local low = me.ammo / math.max(1, me.mag) < 0.25
			ui.magFill.BackgroundColor3 = if me.reload > 0 then C.gold elseif low then C.orange else C.cyan
			ui.reloadText.Text = if me.reload > 0
				then "ПЕРЕЗАРЯДКА"
				elseif me.ammo == 0 then "ПУСТО"
				else ""
			ui.reloadText.TextColor3 = C.gold
		end
		ui.ammo.TextColor3 = if me.reload > 0 or me.overheated then C.dim else C.text
		-- Ability chips (PC / gamepad only; touch has its own buttons)
		local dashMax = me.dashMax or Defs.Player.DashCooldown
		ui.dash.frame.Visible = not touch
		ui.dash.fill.Size = UDim2.fromScale(1, 1 - math.clamp(me.dash / dashMax, 0, 1))
		ui.dash.key.Text = if me.dash > 0 then string.format("%.1f", me.dash) else keyLabel(extra.device, "SPACE", "B")
		ui.dash.stroke.Transparency = if me.dash > 0 then 0.75 else 0.3
		ui.od.frame.Visible = me.s01 and not touch
		local odReady = me.s01 and (me.s01Left <= 0 or me.s01Tutorial)
		ui.od.fill.Size = UDim2.fromScale(1, 1 - math.clamp(me.s01Left / math.max(1, me.s01Cd), 0, 1))
		ui.od.key.Text = if odReady then keyLabel(extra.device, "Q", "Y") else string.format("%.0f", me.s01Left)
		ui.od.stroke.Transparency = if odReady then 0.1 + math.sin(now * 6) * 0.1 else 0.7
		ui.od.stroke.Thickness = if me.s01Tutorial then 4 elseif odReady then 2 else 1
		-- DD-105: the weapon's super (E / right mouse button / R1), charging from damage dealt
		local sdef = Defs.Supers[me.weapon]
		local charge = me.super or 0
		ui.super.frame.Visible = sdef ~= nil and not touch
		if sdef then
			if ui.superIcon ~= sdef.icon then
				ui.superIcon = sdef.icon
				ui.super.icon = Icons.swap(ui.super.icon, sdef.icon, C.gold)
			end
			ui.super.fill.Size = UDim2.fromScale(1, math.clamp(charge, 0, 1))
			ui.super.key.Text = if charge >= 1
				then keyLabel(extra.device, "E", "RB")
				else string.format("%d%%", math.floor(charge * 100))
			ui.super.stroke.Transparency = if charge >= 1 then 0.1 + math.sin(now * 6) * 0.1 else 0.7
			ui.super.stroke.Thickness = if charge >= 1 then 2 else 1
		end
		-- First-run controls hint: only before the first input and in the first seconds of a run.
		-- DD-108: a touch screen needs none (the thumbstick is Roblox's own, the gun fires by itself)
		local howTo = run.op == "O01"
			and not touch
			and (run.waiting or (run.phase == "ACTIVE" and run.t < 16))
			and me.alive
		ui.howTo.Visible = howTo
		if howTo then
			ui.howToText.Text = if touch
				then (if Settings.simpleCombat
					then "Беги пальцем — герой стреляет сам"
					elseif
						Settings.autoAim
					then "Левый палец — бег   ·   оружие стреляет само"
					else "Левый палец — бег   ·   правый — огонь")
				elseif
					extra.device == "gamepad"
				then "Левый стик — бег   ·   правый стик — огонь   ·   B — рывок"
				else "WASD — бег   ·   мышь — огонь   ·   ПРОБЕЛ — рывок"
			local k = if run.waiting then 0 else math.clamp((run.t - 13) / 3, 0, 1)
			ui.howToText.TextTransparency = k
			ui.howTo.BackgroundTransparency = 0.15 + k * 0.85
		end
		-- Prompt pill (S01 lesson / legacy evolution)
		-- (on a phone the S01 lesson's pill shows too: one more thing to tap besides the hammer button)
		ui.evolve.Visible = (me.canEvolve and not touch) or me.s01Tutorial
		if me.s01Tutorial then
			ui.evolveScale.Scale = 1 + math.sin(now * 8) * 0.06
			ui.evolveText.Text = "ГРОМОБОЙ — УДАРЬ  " .. keyLabel(extra.device, "[Q]", "[Y]")
		elseif me.canEvolve then
			ui.evolveScale.Scale = 1 + math.sin(now * 6) * 0.04
			ui.evolveText.Text = "ЭВОЛЮЦИЯ — "
				.. Defs.Evolutions[wdef.evolution].name
				.. "  "
				.. keyLabel(extra.device, "[F]", "[X]")
		end
		-- Kill streak
		local combo = me.combo or 0
		if combo >= 5 then
			if combo ~= comboShown then
				comboShown = combo
				comboAt = now
				ui.comboScale.Scale = 1.25 + math.min(combo, 100) * 0.003
			end
			ui.comboNum.Text = "×" .. combo
			ui.combo.Visible = true
			ui.comboScale.Scale += (1 + math.min(combo, 150) / 300 - ui.comboScale.Scale) * math.min(1, dt * 12)
			local col = if combo >= 100 then C.red elseif combo >= 50 then C.orange else C.gold
			ui.comboNum.TextColor3 = col
			ui.comboBar.BackgroundColor3 = col
			ui.comboBar.Size = UDim2.fromScale(math.clamp(1 - (now - comboAt) / 2.5, 0, 1), 1)
		else
			ui.combo.Visible = false
			comboShown = 0
		end
		-- Vignette
		-- kept thin and soft: in a crowd hits land every frame and a strong flash tints the whole view
		local hurtK = math.max(0, 1 - (now - hurtT) / 0.3) * 0.6
		local low = if lowHp then (0.5 + math.sin(now * 3) * 0.5) * 0.8 else 0
		local v = math.max(hurtK, low)
		for _, f in ui.vignette do
			f.Visible = v > 0.01
			f.BackgroundTransparency = 1 - v * 0.45
		end
	end
	-- Reticle
	-- DD-098: with the phone's auto-aim the ring under the target shows where the gun points, not a cross
	ui.reticle.Visible = extra.showReticle
		and not (extra.device == "touch" and (Settings.autoAim or Settings.simpleCombat))
	if extra.cursor then
		ui.reticle.Position = UDim2.fromOffset(extra.cursor.X, extra.cursor.Y)
	end
	bloom *= math.exp(-dt * 9)
	local wdefR = me and Defs.Weapons[me.weapon]
	local cone = if wdefR and wdefR.spreadMin and extra.spread then (extra.spread - wdefR.spreadMin) * 5 else 0
	for i, tick in ui.reticleTicks do
		local ang = (i - 1) * math.pi / 2
		local r = 12 + bloom + cone
		tick.Position = UDim2.new(0.5, math.cos(ang) * r, 0.5, math.sin(ang) * r)
	end
	local hk = now - hitT
	ui.hit.Visible = hk < 0.14
	if ui.hit.Visible then
		for _, c in ui.hit:GetChildren() do
			c.BackgroundColor3 = if hitKill then C.gold else C.white
		end
		ui.hit.Size = UDim2.fromOffset(30 + hk * 90, 30 + hk * 90)
	end
	ui.reloadRing.Visible = me ~= nil and (me.reload > 0 or me.overheated)
	if ui.reloadRing.Visible then
		ui.reloadRing.Rotation = (me.reload or 0) * 360
	end
	-- Arrows
	for i, a in arrows do
		local info = extra.arrows[i]
		if info then
			a.frame.Visible = true
			a.frame.Position = UDim2.fromOffset(info.x, info.y)
			a.head.Rotation = info.rot
			Icons.recolor(a.head, info.color)
			a.tag.Text = info.text
			a.tag.TextColor3 = info.color
		else
			a.frame.Visible = false
		end
	end
	if ui.debug and extra.debug then
		ui.debug.Text = extra.debug
	end
end

return Hud
