--!nonstrict
-- Combat HUD (RU, icon-first): 3D weapon portrait, vitals, build slots with upgrade icons, timer,
-- boss bar with 3D portrait, hive tracker, ammo/heat, ability tiles, XP bar, kill streak, banners
-- with icons/portraits, reticle + hit markers, damage vignette, off-screen threat arrows.

local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Theme = require(script.Parent.Theme)
local Audio = require(script.Parent.Audio)
local Icons = require(script.Parent.Icons)
local Preview = require(script.Parent.Preview)
local Models = require(script.Parent.Models)

local new, label, tween = Theme.new, Theme.label, Theme.tween
local C, F = Theme.C, Theme.F

local Hud = {}

local gui, root
local ui = {}
local bannerQueue = {}
local bannerBusy = false
local hitT, hitKill = 0, false
local hurtT = 0
local arrows = {}
local comboShown = 0
local shownWeapon = nil
local shownBoss = nil

local function bar(parent, props, color: Color3)
	local back = new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Corner = 2,
		ClipsDescendants = true,
		Parent = parent,
	})
	for k, v in props do
		back[k] = v
	end
	local fill = new("Frame", {
		Name = "Fill",
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		Size = UDim2.fromScale(1, 1),
		Corner = 2,
		Parent = back,
	})
	return back, fill
end

local function icon(name: string, size: number, color: Color3, props)
	local i = Icons.new(name, size, color, C.panel)
	for k, v in props or {} do
		i[k] = v
	end
	return i
end

local function tile(parent, iconName: string, color: Color3, props)
	local t = Theme.panel(props, color)
	t.Parent = parent
	local ic =
		icon(iconName, 26, color, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5), Parent = t })
	local key = label("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, 0, 0, 14),
		FontFace = F.num,
		TextSize = 13,
		TextColor3 = C.dim,
		Parent = t,
	})
	local fill = new("Frame", {
		Name = "Fill",
		BackgroundTransparency = 0.8,
		BackgroundColor3 = color,
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		ZIndex = 0,
		Parent = t,
	})
	return { frame = t, icon = ic, key = key, fill = fill, stroke = t:FindFirstChildOfClass("UIStroke") }
end

function Hud.init(playerGui: PlayerGui)
	gui = new("ScreenGui", {
		Name = "SwarmHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2,
		Enabled = false,
		Parent = playerGui,
	})
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	root = new("Frame", { Size = UDim2.fromScale(1, 1), Parent = gui })
	ui.overlay = new("ScreenGui", {
		Name = "SwarmOverlay",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 3,
		Enabled = false,
		Parent = playerGui,
	})
	ui.overlay.ScreenInsets = Enum.ScreenInsets.None
	ui.scale = new("UIScale", { Parent = root })

	-- Vitals (top-left) ---------------------------------------------------------------------------
	local vit = Theme.panel(
		{ Name = "Vitals", Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(372, 96), Parent = root },
		C.cyan
	)
	ui.vitalsStroke = vit:FindFirstChildOfClass("UIStroke")
	ui.weaponBox = new("Frame", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.3,
		Corner = 4,
		Parent = vit,
	})
	ui.levelBox = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 2, 1, -2),
		Size = UDim2.fromOffset(30, 24),
		BackgroundColor3 = C.cyan,
		BackgroundTransparency = 0,
		Corner = 3,
		ZIndex = 3,
		Parent = ui.weaponBox,
	})
	ui.level = label("1", {
		Size = UDim2.fromScale(1, 1),
		FontFace = F.numHeavy,
		TextSize = 18,
		TextColor3 = C.bg,
		ZIndex = 4,
		Parent = ui.levelBox,
	})
	ui.coreBadge = icon(
		"core",
		22,
		C.gold,
		{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -3, 0, 3), Visible = false, Parent = ui.weaponBox }
	)
	icon("heart", 18, C.red, { Position = UDim2.fromOffset(98, 9), Parent = vit })
	ui.hpBack, ui.hpFill = bar(vit, { Position = UDim2.fromOffset(122, 10), Size = UDim2.fromOffset(240, 18) }, C.cyan)
	ui.hpFill:FindFirstChildOfClass("UICorner"):Destroy()
	ui.hpTrail = new("Frame", {
		BackgroundTransparency = 0.3,
		BackgroundColor3 = C.red,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = ui.hpBack,
	})
	ui.hpFill.ZIndex = 2
	ui.shieldFill = new("Frame", {
		BackgroundTransparency = 0.15,
		BackgroundColor3 = C.blue,
		Size = UDim2.fromScale(0, 0.35),
		ZIndex = 3,
		Parent = ui.hpBack,
	})
	for i = 1, 9 do
		new("Frame", {
			BackgroundTransparency = 0.4,
			BackgroundColor3 = C.bg,
			Size = UDim2.new(0, 2, 1, 0),
			Position = UDim2.fromScale(i / 10, 0),
			ZIndex = 4,
			Parent = ui.hpBack,
		})
	end
	ui.hpText = label("100", {
		Position = UDim2.fromOffset(122, 28),
		Size = UDim2.fromOffset(150, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = F.num,
		TextSize = 19,
		Parent = vit,
	})
	ui.weaponName = label("", {
		Position = UDim2.fromOffset(212, 30),
		Size = UDim2.fromOffset(150, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = F.title,
		TextSize = 12,
		TextColor3 = C.dim,
		Parent = vit,
	})
	ui.slots = {}
	for i = 1, 6 do
		local s = new("Frame", {
			Position = UDim2.fromOffset(98 + (i - 1) * 44, 50),
			Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = 0.15,
			Corner = 4,
			Stroke = { Color = C.line, Transparency = 0.4 },
			Parent = vit,
		})
		local pips = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.new(1, -10, 0, 3),
			List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2) },
			Parent = s,
		})
		local pipList = {}
		for k = 1, 3 do
			pipList[k] = new(
				"Frame",
				{ Size = UDim2.new(0.31, 0, 1, 0), BackgroundTransparency = 1, BackgroundColor3 = C.dim, Parent = pips }
			)
		end
		ui.slots[i] = { frame = s, icon = nil, id = nil, pips = pipList, stroke = s:FindFirstChildOfClass("UIStroke") }
	end

	-- Evolution recipe tracker (under the vitals): key upgrades + core -> evolution name.
	ui.evoTrack = Theme.panel(
		{ Name = "EvoTrack", Position = UDim2.fromOffset(12, 110), Size = UDim2.fromOffset(250, 30), Parent = root },
		C.gold
	)
	ui.evoTrackStroke = ui.evoTrack:FindFirstChildOfClass("UIStroke")
	ui.evoIcons = {}
	ui.evoName = label("", {
		Position = UDim2.fromOffset(104, 0),
		Size = UDim2.new(1, -110, 1, 0),
		FontFace = F.head,
		TextSize = 15,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ui.evoTrack,
	})
	label("→", {
		Position = UDim2.fromOffset(84, 0),
		Size = UDim2.fromOffset(18, 30),
		FontFace = F.head,
		TextSize = 16,
		TextColor3 = C.dim,
		Parent = ui.evoTrack,
	})

	-- Camera view toggle (top-right)
	ui.view = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(58, 58),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.2,
		Text = "",
		AutoButtonColor = false,
		Corner = 4,
		Stroke = { Color = C.cyan, Transparency = 0.45 },
		Parent = root,
	})
	ui.viewIconName = nil
	ui.viewKey = label("V", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, 0, 0, 14),
		FontFace = F.num,
		TextSize = 13,
		TextColor3 = C.dim,
		Parent = ui.view,
	})
	ui.viewName = label("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -78, 0, 28),
		Size = UDim2.fromOffset(260, 22),
		FontFace = F.head,
		TextSize = 18,
		TextColor3 = C.cyan,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTransparency = 1,
		Parent = root,
	})

	-- Squad (coop)
	ui.squad = new("Frame", {
		Position = UDim2.fromOffset(12, 146),
		Size = UDim2.fromOffset(220, 120),
		List = { Padding = UDim.new(0, 4) },
		Parent = root,
	})

	-- Timer (top-center) -----------------------------------------------------------------------------
	local top = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(380, 84),
		Parent = root,
	})
	ui.timer = label(
		"0:00",
		{ Size = UDim2.new(1, 0, 0, 46), FontFace = F.num, TextSize = 46, TextStrokeTransparency = 0.15, Parent = top }
	)
	ui.phase = label("", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 16),
		FontFace = F.title,
		TextSize = 14,
		TextColor3 = C.cyan,
		Parent = top,
	})
	local killsRow = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(200, 18),
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		},
		Parent = top,
	})
	icon("skull", 15, C.dim, { LayoutOrder = 1, Parent = killsRow })
	ui.kills = label("0", {
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		FontFace = F.num,
		TextSize = 16,
		TextColor3 = C.dim,
		Parent = killsRow,
	})
	ui.threatIcon = icon("threat", 15, C.red, { LayoutOrder = 3, Parent = killsRow })
	ui.threat = label("", {
		LayoutOrder = 4,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		FontFace = F.num,
		TextSize = 16,
		TextColor3 = C.red,
		Parent = killsRow,
	})
	ui.timeLeft = label("", {
		LayoutOrder = 5,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		FontFace = F.num,
		TextSize = 16,
		TextColor3 = C.red,
		Parent = killsRow,
	})

	-- Boss bar with 3D portrait --------------------------------------------------------------------------
	ui.boss = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.new(0.5, 40, 0, 52),
		Visible = false,
		Parent = root,
	})
	ui.bossPortrait = new("Frame", {
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.25,
		Corner = 4,
		Stroke = { Color = C.red, Transparency = 0.2 },
		Parent = ui.boss,
	})
	ui.bossName = label("", {
		Position = UDim2.fromOffset(60, 4),
		Size = UDim2.new(1, -60, 0, 18),
		FontFace = F.head,
		TextSize = 18,
		TextColor3 = C.red,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ui.boss,
	})
	ui.bossTag = label("", {
		Position = UDim2.fromOffset(60, 4),
		Size = UDim2.new(1, -60, 0, 18),
		FontFace = F.title,
		TextSize = 13,
		TextColor3 = C.lime,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = ui.boss,
	})
	ui.bossBack, ui.bossFill =
		bar(ui.boss, { Position = UDim2.fromOffset(60, 26), Size = UDim2.new(1, -60, 0, 16) }, C.red)
	ui.bossFill.BackgroundColor3 = Color3.new(1, 1, 1)
	new(
		"UIGradient",
		{ Color = ColorSequence.new(Color3.fromRGB(255, 60, 80), Color3.fromRGB(190, 40, 140)), Parent = ui.bossFill }
	)
	for _, f in { 0.65, 0.3 } do
		new("Frame", {
			BackgroundTransparency = 0.2,
			BackgroundColor3 = C.bg,
			Size = UDim2.new(0, 2, 1, 0),
			Position = UDim2.fromScale(f, 0),
			ZIndex = 3,
			Parent = ui.bossBack,
		})
	end

	-- Hive tracker
	ui.hive = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 94),
		Size = UDim2.fromOffset(220, 34),
		Visible = false,
		Parent = root,
	}, C.lime)
	icon("hive", 22, C.lime, { Position = UDim2.fromOffset(10, 6), Parent = ui.hive })
	ui.hiveText = label("", {
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(0, 70, 1, 0),
		FontFace = F.num,
		TextSize = 20,
		TextColor3 = C.lime,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ui.hive,
	})
	icon("timer", 20, C.text, { Position = UDim2.fromOffset(120, 7), Parent = ui.hive })
	ui.hiveTime = label("", {
		Position = UDim2.fromOffset(146, 0),
		Size = UDim2.new(0, 60, 1, 0),
		FontFace = F.num,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ui.hive,
	})

	-- Reactor + objective (top-centre, operations with a reactor)
	ui.reactor = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 94),
		Size = UDim2.fromOffset(320, 46),
		Visible = false,
		Parent = root,
	}, C.cyan)
	ui.reactorStroke = ui.reactor:FindFirstChildOfClass("UIStroke")
	ui.reactorIcon = icon("reactor", 28, C.cyan, { Position = UDim2.fromOffset(8, 9), Parent = ui.reactor })
	ui.goal = label("", {
		Position = UDim2.fromOffset(44, 3),
		Size = UDim2.new(1, -52, 0, 18),
		FontFace = F.title,
		TextSize = 13,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ui.reactor,
	})
	ui.reactorBack, ui.reactorFill =
		bar(ui.reactor, { Position = UDim2.fromOffset(44, 25), Size = UDim2.new(1, -110, 0, 12) }, C.cyan)
	ui.reactorShield = label("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 3),
		Size = UDim2.fromOffset(80, 16),
		FontFace = F.num,
		TextSize = 13,
		TextColor3 = C.cyan,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = ui.reactor,
	})
	ui.reactorPct = label("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 19),
		Size = UDim2.fromOffset(56, 24),
		FontFace = F.num,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = ui.reactor,
	})

	-- Combo (right) -------------------------------------------------------------------------------------
	ui.combo = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.38, 0),
		Size = UDim2.fromOffset(200, 80),
		Parent = root,
	})
	ui.comboIcon = icon(
		"boom",
		34,
		C.gold,
		{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 62), Parent = ui.combo }
	)
	ui.comboNum = label("", {
		Size = UDim2.new(1, 0, 0, 60),
		FontFace = F.num,
		TextSize = 60,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.gold,
		TextStrokeTransparency = 0.5,
		Parent = ui.combo,
	})
	ui.comboScale = new("UIScale", { Parent = ui.combo })
	-- Multi-kill pop (a burst of kills inside half a second): the «перелом» moment made loud.
	ui.burst = label("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.27, 0),
		Size = UDim2.fromOffset(520, 64),
		FontFace = F.head,
		TextSize = 46,
		TextColor3 = C.gold,
		TextStrokeTransparency = 0.4,
		TextTransparency = 1,
		RichText = true,
		Parent = root,
	})
	ui.burstScale = new("UIScale", { Parent = ui.burst })

	-- Weapon / abilities (bottom-center) -------------------------------------------------------------
	local wp = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(460, 66),
		Parent = root,
	})
	ui.ammo = label("42", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -6, 0, -2),
		Size = UDim2.fromOffset(120, 44),
		FontFace = F.num,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = wp,
	})
	ui.ammoMax = label("/ 42", {
		Position = UDim2.new(0.5, -2, 0, 14),
		Size = UDim2.fromOffset(70, 22),
		FontFace = F.num,
		TextSize = 20,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = wp,
	})
	ui.magBack, ui.magFill = bar(
		wp,
		{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(230, 6) },
		C.cyan
	)
	ui.reloadText = label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 51),
		Size = UDim2.fromOffset(230, 14),
		FontFace = F.title,
		TextSize = 12,
		TextColor3 = C.gold,
		Parent = wp,
	})
	ui.dash = tile(
		wp,
		"dash",
		C.cyan,
		{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, -140, 0, 4), Size = UDim2.fromOffset(62, 58) }
	)
	ui.od = tile(wp, "hammer", C.cyan, { Position = UDim2.new(0.5, 140, 0, 4), Size = UDim2.fromOffset(62, 58) })
	ui.reroll = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -210, 0, 18),
		Size = UDim2.fromOffset(60, 40),
		Parent = wp,
	})

	-- Evolve prompt
	ui.evolve = new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		Size = UDim2.fromOffset(380, 50),
		BackgroundColor3 = C.gold,
		BackgroundTransparency = 0.05,
		Text = "",
		Corner = 4,
		Visible = false,
		Parent = root,
	})
	icon("evolve", 30, C.bg, { Position = UDim2.fromOffset(12, 10), Parent = ui.evolve })
	ui.evolveText = label("", {
		Position = UDim2.fromOffset(50, 0),
		Size = UDim2.new(1, -60, 1, 0),
		FontFace = F.head,
		TextSize = 20,
		TextColor3 = C.bg,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ui.evolve,
	})
	ui.evolveScale = new("UIScale", { Parent = ui.evolve })

	-- XP bar (bottom edge)
	ui.xpBack, ui.xpFill = bar(
		root,
		{ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 6) },
		C.cyan
	)
	ui.xpBack.BackgroundTransparency = 0.3
	new(
		"UIGradient",
		{ Color = ColorSequence.new(Color3.fromRGB(84, 238, 255), Color3.fromRGB(180, 110, 255)), Parent = ui.xpFill }
	)

	-- Banner with icon / portrait
	ui.banner = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromOffset(760, 110),
		Visible = false,
		Parent = root,
	})
	ui.bannerVisual = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -58),
		Size = UDim2.fromOffset(64, 64),
		Parent = ui.banner,
	})
	ui.bannerLine = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.new(0.6, 0, 0, 2),
		BackgroundTransparency = 0.2,
		BackgroundColor3 = C.cyan,
		Parent = ui.banner,
	})
	ui.bannerText = label("", {
		Size = UDim2.new(1, 0, 0, 56),
		FontFace = F.head,
		TextSize = 48,
		TextStrokeTransparency = 0.5,
		Parent = ui.banner,
	})
	ui.bannerSub = label("", {
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 24),
		FontFace = F.bodyBold,
		TextSize = 19,
		Parent = ui.banner,
	})

	-- First-run controls hint (DD-024): the first seconds of O01 say how to move and shoot, then fade.
	ui.howTo = label("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(760, 64),
		FontFace = F.head,
		TextSize = 26,
		TextWrapped = true,
		TextStrokeTransparency = 0.4,
		RichText = true,
		Visible = false,
		Parent = root,
	})

	-- Reticle
	ui.reticle = new(
		"Frame",
		{ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(36, 36), ZIndex = 20, Parent = ui.overlay }
	)
	ui.reticleTicks = {}
	for i = 0, 3 do
		local a = i * math.pi / 2
		ui.reticleTicks[i + 1] = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(a) * 11, 0.5, math.sin(a) * 11),
			Size = if i % 2 == 0 then UDim2.fromOffset(9, 2) else UDim2.fromOffset(2, 9),
			BackgroundTransparency = 0,
			BackgroundColor3 = C.cyan,
			ZIndex = 20,
			Parent = ui.reticle,
		})
	end
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(3, 3),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.white,
		ZIndex = 20,
		Parent = ui.reticle,
	})
	ui.hit = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		Rotation = 45,
		Visible = false,
		ZIndex = 21,
		Parent = ui.reticle,
	})
	for i = 0, 3 do
		local a = i * math.pi / 2
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(a) * 9, 0.5, math.sin(a) * 9),
			Size = if i % 2 == 0 then UDim2.fromOffset(8, 2) else UDim2.fromOffset(2, 8),
			BackgroundTransparency = 0,
			BackgroundColor3 = C.white,
			ZIndex = 21,
			Parent = ui.hit,
		})
	end
	ui.reloadRing = icon(
		"reload",
		16,
		C.gold,
		{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Visible = false, Parent = ui.reticle }
	)

	-- Vignette (edges)
	ui.vignette = {}
	for _, e in
		{
			{ UDim2.fromScale(0, 0), UDim2.new(1, 0, 0.18, 0), 90 },
			{ UDim2.new(0, 0, 0.82, 0), UDim2.new(1, 0, 0.18, 0), 270 },
			{ UDim2.fromScale(0, 0), UDim2.new(0.12, 0, 1, 0), 0 },
			{ UDim2.new(0.88, 0, 0, 0), UDim2.new(0.12, 0, 1, 0), 180 },
		}
	do
		local f = new("Frame", {
			Position = e[1],
			Size = e[2],
			BackgroundTransparency = 0,
			BackgroundColor3 = C.red,
			ZIndex = 0,
			Gradient = { Rotation = e[3], Transparency = NumberSequence.new(0, 1) },
			Parent = ui.overlay,
		})
		f.Visible = false
		table.insert(ui.vignette, f)
	end

	-- Off-screen arrows
	for i = 1, 6 do
		local a = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(44, 44),
			Visible = false,
			ZIndex = 15,
			Parent = ui.overlay,
		})
		local arrowHead = icon(
			"level",
			30,
			C.gold,
			{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = a }
		)
		local tag = label("", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, -2),
			Size = UDim2.fromOffset(90, 16),
			FontFace = F.head,
			TextSize = 14,
			TextStrokeTransparency = 0.4,
			ZIndex = 15,
			Parent = a,
		})
		arrows[i] = { frame = a, head = arrowHead, tag = tag }
	end

	if RunService:IsStudio() then
		ui.debug = label("", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -12),
			Size = UDim2.fromOffset(330, 34),
			FontFace = F.mono,
			TextSize = 11,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = root,
		})
	end
	Hud.ui = ui
	Hud.gui = gui
end

function Hud.setVisible(v: boolean)
	gui.Enabled = v
	ui.overlay.Enabled = v
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
			ui.bannerVisual.Size = UDim2.fromOffset(110, 110)
			ui.bannerVisual.Position = UDim2.new(0.5, 0, 0, -104)
			Preview.creature(ui.bannerVisual, kind, { spin = true, zoom = 0.95 })
		end
	else
		ui.bannerVisual.Size = UDim2.fromOffset(56, 56)
		ui.bannerVisual.Position = UDim2.new(0.5, 0, 0, -56)
		icon(visual, 56, color, { Parent = ui.bannerVisual })
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
	ui.bannerSub.Text = b.sub
	setBannerVisual(b.visual, b.color)
	ui.bannerText.TextTransparency = 1
	ui.bannerSub.TextTransparency = 1
	ui.bannerLine.Size = UDim2.new(0, 0, 0, 2)
	ui.banner.Position = UDim2.fromScale(0.5, 0.25)
	Audio.play("banner")
	tween(ui.bannerText, 0.25, { TextTransparency = 0 })
	tween(ui.bannerSub, 0.4, { TextTransparency = 0 })
	tween(ui.bannerLine, 0.5, { Size = UDim2.new(0.6, 0, 0, 2) })
	tween(ui.banner, 0.4, { Position = UDim2.fromScale(0.5, 0.27) })
	task.delay(math.min(b.duration, if #bannerQueue > 0 then 1.6 else b.duration), function()
		tween(ui.bannerText, 0.25, { TextTransparency = 1 })
		tween(ui.bannerSub, 0.25, { TextTransparency = 1 })
		tween(ui.bannerLine, 0.25, { Size = UDim2.new(0, 0, 0, 2) })
		task.wait(0.27)
		ui.banner.Visible = false
		setBannerVisual(nil, C.text)
		nextBanner()
	end)
end

function Hud.banner(text: string, sub: string, color: Color3, duration: number, visual: string?)
	if #bannerQueue >= 3 then
		table.remove(bannerQueue, 1)
	end
	table.insert(bannerQueue, { text = text, sub = sub, color = color, duration = duration, visual = visual })
	if not bannerBusy then
		nextBanner()
	end
end

-- Shows the active camera view on the toggle button (+ a short fading caption on change).
function Hud.setView(mode: string, iconName: string, caption: string?, device: string)
	if ui.viewIconName ~= iconName then
		local old = ui.view:FindFirstChild("Icon_" .. (ui.viewIconName or ""))
		if old then
			old:Destroy()
		end
		ui.viewIconName = iconName
		icon(
			iconName,
			30,
			C.cyan,
			{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 7), Parent = ui.view }
		)
	end
	ui.view.Visible = device ~= "touch"
	ui.viewKey.Text = if device == "gamepad" then "▲" else "V"
	if caption then
		ui.viewName.Text = caption
		ui.viewName.TextTransparency = 0
		tween(ui.viewName, 1.6, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
end

-- Reticle bloom: each shot kicks the ticks outward (pixels); they settle back.
local bloom = 0
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
	for _, w in BURST_WORDS do
		if n >= w[1] then
			ui.burst.Text = string.format('%s <font size="34">×%d</font>', w[2], n)
			ui.burst.TextColor3 = w[3]
			break
		end
	end
	ui.burst.TextTransparency = 0
	ui.burst.TextStrokeTransparency = 0.4
	ui.burstScale.Scale = 1.35
	tween(ui.burstScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(
		ui.burst,
		0.9,
		{ TextTransparency = 1, TextStrokeTransparency = 1 },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
end

function Hud.hurt()
	hurtT = os.clock()
end

local function keyLabel(device: string, pc: string, pad: string): string
	return if device == "pc" then pc elseif device == "gamepad" then pad else ""
end

-- Frame update --------------------------------------------------------------------------------------
function Hud.update(run, me, extra, dt: number)
	local now = os.clock()
	ui.scale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 900, 0.6, 1.15)
	local remaining = (run.hardLimit or Defs.Run.HardLimit) - run.t
	ui.timer.Text = Theme.fmtTime(run.t)
	ui.timer.TextColor3 = if run.boss and run.boss.enraged then C.red else C.text
	ui.phase.Text = run.label
	ui.kills.Text = Theme.commas(run.kills)
	ui.threat.Text = if (run.threat or 1) > 1 then tostring(run.threat) else ""
	ui.threatIcon.Visible = (run.threat or 1) > 1
	ui.timeLeft.Text = if run.boss and remaining < 120 then "· " .. Theme.fmtTime(remaining) else ""
	-- Boss
	ui.boss.Visible = run.boss ~= nil
	ui.hive.Visible = run.hive ~= nil and run.boss == nil
	if run.boss then
		if shownBoss ~= run.boss.kind then
			shownBoss = run.boss.kind
			for _, c in ui.bossPortrait:GetChildren() do
				if c:IsA("ViewportFrame") then
					c:Destroy()
				end
			end
			Preview.creature(ui.bossPortrait, run.boss.kind, { spin = false, zoom = 0.8 })
			ui.bossName.Text = Defs.EnemyByIndex[run.boss.kind].name
		end
		ui.bossFill.Size = UDim2.fromScale(math.clamp(run.boss.hp, 0, 1), 1)
		ui.bossTag.Text = if run.boss.invulnerable
			then "НЕУЯЗВИМ"
			elseif run.boss.exposed then "УЯЗВИМ  ×1.8"
			elseif run.boss.enraged then "ЯРОСТЬ"
			else ""
		ui.bossTag.TextColor3 = if run.boss.exposed then C.lime else C.red
	end
	local mission = run.mission
	local rc = mission and mission.reactor
	ui.reactor.Visible = rc ~= nil and run.boss == nil
	if rc then
		local frac = math.clamp(rc.hp / math.max(1, rc.max), 0, 1)
		local col = if frac < 0.25 then C.red elseif frac < 0.5 then C.orange else C.cyan
		local hitAgo = run.t - (rc.hitT or -99)
		local flash = hitAgo < 0.35
		ui.reactorFill.Size = UDim2.fromScale(frac, 1)
		ui.reactorFill.BackgroundColor3 = if flash then C.red else col
		ui.reactorPct.Text = math.ceil(frac * 100) .. "%"
		ui.reactorShield.Text = if (rc.shield or 0) > 0 then "ЩИТ " .. rc.shield else ""
		ui.reactorPct.TextColor3 = col
		ui.reactorStroke.Color = if hitAgo < 2 then C.red else col
		Icons.recolor(ui.reactorIcon, if flash then C.red else col)
		local goal = mission.goal or ""
		if mission.finaleLeft then
			goal = goal .. "  ·  " .. mission.finaleLeft .. " с"
		elseif mission.deadlineLeft and mission.deadlineLeft <= 120 then
			goal = goal .. "  ·  СРОК " .. Theme.fmtTime(mission.deadlineLeft)
		end
		local relay = mission.relay
		if relay and relay.alive and mission.state == "FIGHT" then
			goal = goal
				.. string.format("  ·  КАТУШКА %d%%", math.ceil(relay.hp / math.max(1, relay.max) * 100))
		end
		ui.goal.Text = string.upper(goal)
		ui.goal.TextColor3 = if mission.deadlineLeft and mission.deadlineLeft <= 60 then C.red else C.text
	end
	if run.hive then
		ui.hiveText.Text = string.format("%d/3", run.hive)
		ui.hiveTime.Text = tostring(math.ceil(run.hiveEnds or 0))
	end
	ui.xpFill.Size = UDim2.fromScale(math.clamp(run.xp / math.max(1, run.xpNeed), 0, 1), 1)
	ui.level.Text = tostring(run.level)
	if me then
		local wdef = Defs.Weapons[me.weapon]
		local evolved = me.evolved ~= ""
		-- Weapon portrait
		local key = me.weapon .. (if evolved then "+" else "")
		if shownWeapon ~= key then
			shownWeapon = key
			for _, c in ui.weaponBox:GetChildren() do
				if c:IsA("ViewportFrame") then
					c:Destroy()
				end
			end
			local vp = Preview.weapon(ui.weaponBox, me.weapon, evolved, { spin = true, zoom = 0.75, pitch = 0.25 })
			vp.ZIndex = 1
			ui.vitalsStroke.Color = if evolved then C.gold else wdef.color
		end
		local hpFrac = math.clamp(me.hp / me.maxHp, 0, 1)
		ui.hpFill.Size = UDim2.fromScale(hpFrac, 1)
		ui.hpFill.BackgroundColor3 = if hpFrac < 0.3 then C.red elseif hpFrac < 0.6 then C.gold else C.cyan
		local trail = ui.hpTrail.Size.X.Scale
		ui.hpTrail.Size =
			UDim2.fromScale(if trail > hpFrac then trail - (trail - hpFrac) * math.min(1, dt * 3) else hpFrac, 1)
		ui.shieldFill.Size = UDim2.fromScale(math.clamp(me.shield / me.maxHp, 0, 1), 0.35)
		ui.hpText.Text = string.format(
			'%d<font size="14" color="#7E95A6"> / %d</font>%s',
			me.hp,
			me.maxHp,
			if me.shield > 0 then string.format('<font size="14" color="#78AAFF">  +%d</font>', me.shield) else ""
		)
		ui.weaponName.Text = if evolved then Defs.Evolutions[me.evolved].name else wdef.short
		ui.weaponName.TextColor3 = if evolved then C.gold else wdef.color
		ui.coreBadge.Visible = me.core and not evolved
		-- Evolution recipe: lit icons for owned keys / the core; pulses gold when ready, hides once evolved
		local recipe = Defs.Evolutions[wdef.evolution]
		-- Only legacy runs still evolve from cards + core; permanent forms are crafted in the arsenal.
		local runEvo = run.runEvolution == true and not evolved
		ui.evoTrack.Visible = runEvo
		if runEvo then
			if ui.evoTrackFor ~= wdef.id then
				ui.evoTrackFor = wdef.id
				for _, ic in ui.evoIcons do
					ic.frame:Destroy()
				end
				table.clear(ui.evoIcons)
				local x = 6
				for _, key in recipe.keys do
					local def = Defs.Upgrades[key]
					table.insert(ui.evoIcons, {
						frame = icon(
							def.icon,
							22,
							def.color,
							{ Position = UDim2.fromOffset(x, 4), Parent = ui.evoTrack }
						),
						key = key,
						color = def.color,
					})
					x += 26
				end
				table.insert(ui.evoIcons, {
					frame = icon("core", 22, C.gold, { Position = UDim2.fromOffset(x, 4), Parent = ui.evoTrack }),
					core = true,
					color = C.gold,
				})
				ui.evoName.Text = recipe.name
			end
			for _, ic in ui.evoIcons do
				local have = if ic.core then me.core else (me.ranks[ic.key] or 0) > 0
				Icons.recolor(ic.frame, if have then ic.color else C.line)
			end
			ui.evoName.TextColor3 = if me.canEvolve then C.gold else C.dim
			ui.evoTrackStroke.Transparency = if me.canEvolve then 0.05 + math.sin(now * 8) * 0.1 else 0.6
		end
		-- Build slots
		local owned = {}
		for _, id in Defs.UpgradeOrder do
			if me.ranks[id] then
				table.insert(owned, id)
			end
		end
		local evo = Defs.Evolutions[wdef.evolution]
		for i, s in ui.slots do
			local id = owned[i]
			-- only filled slots and the next free one: no row of empty boxes before the first pick
			s.frame.Visible = id ~= nil or (i == #owned + 1 and #owned > 0)
			if s.id ~= id then
				s.id = id
				if s.icon then
					s.icon:Destroy()
					s.icon = nil
				end
				if id then
					local def = Defs.Upgrades[id]
					s.icon = icon(
						def.icon,
						28,
						def.color,
						{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), Parent = s.frame }
					)
				end
			end
			if id then
				local def = Defs.Upgrades[id]
				local isKey = table.find(evo.keys, id) and not evolved
				s.stroke.Color = if isKey then C.gold else def.color
				s.stroke.Transparency = 0.15
				s.stroke.Thickness = if isKey then 2 else 1
				for k = 1, 3 do
					s.pips[k].BackgroundTransparency = if k <= me.ranks[id] then 0 else 0.75
					s.pips[k].BackgroundColor3 = if k <= me.ranks[id] then def.color else C.dim
				end
			else
				s.stroke.Color = C.line
				s.stroke.Transparency = 0.6
				s.stroke.Thickness = 1
				for k = 1, 3 do
					s.pips[k].BackgroundTransparency = 1
				end
			end
		end
		-- Ammo / heat
		if wdef.kind == "beam" then
			ui.ammo.Text = tostring(100 - me.heat)
			ui.ammoMax.Text = "%"
			ui.magFill.Size = UDim2.fromScale(1 - me.heat / 100, 1)
			ui.magFill.BackgroundColor3 = if me.overheated then C.red elseif me.heat > 70 then C.orange else C.violet
			ui.reloadText.Text = if me.overheated then "ПЕРЕГРЕВ" else ""
			ui.reloadText.TextColor3 = C.red
		else
			ui.ammo.Text = tostring(me.ammo)
			ui.ammoMax.Text = "/ " .. me.mag
			ui.magFill.Size = UDim2.fromScale(if me.reload > 0 then me.reload else me.ammo / math.max(1, me.mag), 1)
			local low = me.ammo / math.max(1, me.mag) < 0.25
			ui.magFill.BackgroundColor3 = if me.reload > 0 then C.gold elseif low then C.orange else wdef.color
			local reloadLabel = if not wdef.reloadEmpty
				then "ПЕРЕЗАРЯДКА"
				elseif me.reloadEmpty then "ПУСТАЯ ЯЧЕЙКА · ЗАТВОР"
				else "СМЕНА ЯЧЕЙКИ"
			ui.reloadText.Text = if me.reload > 0
				then reloadLabel
				elseif me.ammo == 0 then "ПУСТО"
				elseif low then "ЗАРЯД НА ИСХОДЕ"
				else ""
			ui.reloadText.TextColor3 = if me.reload <= 0 and low then C.orange else C.gold
		end
		local lowAmmo = wdef.kind ~= "beam" and me.reload <= 0 and me.ammo / math.max(1, me.mag) < 0.25
		ui.ammo.TextColor3 = if me.overheated or me.reload > 0
			then C.dim
			elseif lowAmmo and math.sin(now * 10) > 0 then C.orange
			else C.text
		-- Dash tile
		local dashMax = me.dashMax or Defs.Player.DashCooldown
		ui.dash.fill.Size = UDim2.fromScale(1, 1 - math.clamp(me.dash / dashMax, 0, 1))
		ui.dash.key.Text = if me.dash > 0 then string.format("%.1f", me.dash) else keyLabel(extra.device, "SPACE", "B")
		ui.dash.fill.BackgroundTransparency = if me.dash > 0 then 0.85 else 0.6
		-- S01 Gravihammer tile (hidden until the skill is known)
		ui.od.frame.Visible = me.s01
		local odReady = me.s01 and (me.s01Left <= 0 or me.s01Tutorial)
		ui.od.fill.Size = UDim2.fromScale(1, 1 - math.clamp(me.s01Left / math.max(1, me.s01Cd), 0, 1))
		ui.od.key.Text = if odReady then keyLabel(extra.device, "Q", "Y") else string.format("%.0f", me.s01Left)
		ui.od.fill.BackgroundTransparency = if odReady then 0.45 else 0.8
		local pulse = if me.s01Tutorial then 10 else 8
		ui.od.stroke.Transparency = if odReady then 0.05 + math.sin(now * pulse) * 0.1 else 0.45
		ui.od.stroke.Thickness = if me.s01Tutorial then 4 elseif odReady then 2 else 1
		-- First-run controls hint
		local howTo = run.op == "O01" and (run.waiting or (run.phase == "ACTIVE" and run.t < 18)) and me.alive
		ui.howTo.Visible = howTo
		if howTo then
			ui.howTo.Text = if extra.device == "touch"
				then "ЛЕВЫЙ СТИК — БЕГ   ·   ПРАВАЯ ПЛОЩАДКА — ОГОНЬ\n<font size=\"20\">Не подпускай рой к реактору</font>"
				elseif extra.device == "gamepad" then "ЛЕВЫЙ СТИК — БЕГ   ·   ПРАВЫЙ СТИК — ОГОНЬ   ·   B — РЫВОК\n<font size=\"20\">Не подпускай рой к реактору</font>"
				else "WASD — БЕГ   ·   МЫШЬ — ПРИЦЕЛ И ОГОНЬ   ·   ПРОБЕЛ — РЫВОК\n<font size=\"20\">Не подпускай рой к реактору</font>"
			ui.howTo.TextTransparency = if run.waiting then 0 else math.clamp((run.t - 14) / 4, 0, 1)
		end
		ui.view.Visible = run.op ~= "O01" and extra.device ~= "touch"
		-- Evolve
		ui.evolve.Visible =(me.canEvolve or me.s01Tutorial) and extra.device ~= "touch"
		if me.s01Tutorial then
			ui.evolveScale.Scale = 1 + math.sin(now * 8) * 0.06
			ui.evolveText.Text = "ГРАВИМОЛОТ: УДАРЬ  " .. keyLabel(extra.device, "[Q]", "[Y]")
		elseif me.canEvolve then
			ui.evolveScale.Scale = 1 + math.sin(now * 6) * 0.04
			ui.evolveText.Text = "ЭВОЛЮЦИЯ: "
				.. Defs.Evolutions[wdef.evolution].name
				.. "  "
				.. keyLabel(extra.device, "[F]", "[X]")
		end
		-- Kill streak
		local combo = me.combo or 0
		if combo >= 10 then
			if combo ~= comboShown then
				comboShown = combo
				ui.comboScale.Scale = 1.18
			end
			ui.comboNum.Text = "×" .. combo
			ui.combo.Visible = true
			ui.comboScale.Scale += (1 - ui.comboScale.Scale) * math.min(1, dt * 12)
			local col = if combo >= 100 then C.red elseif combo >= 50 then C.orange else C.gold
			ui.comboNum.TextColor3 = col
			Icons.recolor(ui.comboIcon, col)
		else
			ui.combo.Visible = false
			comboShown = 0
		end
		-- Vignette
		local hurtK = math.max(0, 1 - (now - hurtT) / 0.35)
		local low = if hpFrac < 0.3 and me.alive then (0.5 + math.sin(now * 5) * 0.5) * 0.5 else 0
		local v = math.max(hurtK, low)
		for _, f in ui.vignette do
			f.Visible = v > 0.01
			f.BackgroundTransparency = 1 - v * 0.4
		end
	end
	-- Squad list
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
					row = Theme.panel({ Name = k, Size = UDim2.fromOffset(210, 34), Parent = ui.squad }, C.gold)
					local wbox = new(
						"Frame",
						{ Name = "W", Position = UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(30, 30), Parent = row }
					)
					Preview.weapon(wbox, p.weapon, false, { zoom = 0.7 })
					label(p.name, {
						Name = "N",
						Position = UDim2.fromOffset(38, 1),
						Size = UDim2.new(1, -46, 0, 16),
						FontFace = F.bodyBold,
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						Parent = row,
					})
					local b, f =
						bar(row, { Position = UDim2.fromOffset(38, 21), Size = UDim2.new(1, -46, 0, 6) }, C.gold)
					f.Name = "HP"
					b.Name = "B"
				end
				rows[k] = nil
				row.B.HP.Size = UDim2.fromScale(math.clamp(p.hp / p.maxHp, 0, 1), 1)
				row.N.Text = p.name
					.. (
						if p.downed
							then string.format("  · РАНЕН %dс  %d%%", p.bleed or 0, p.revive or 0)
							elseif not p.alive then "  · ПОВЕРЖЕН"
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
	-- Reticle
	ui.reticle.Visible = extra.showReticle
	if extra.cursor then
		ui.reticle.Position = UDim2.fromOffset(extra.cursor.X, extra.cursor.Y)
	end
	bloom *= math.exp(-dt * 9)
	-- weapons with accuracy bloom (W01) open the reticle with the real cone
	local wdefR = me and Defs.Weapons[me.weapon]
	local cone = if wdefR and wdefR.spreadMin and extra.spread then (extra.spread - wdefR.spreadMin) * 5 else 0
	for i, tick in ui.reticleTicks do
		local ang = (i - 1) * math.pi / 2
		local r = 11 + bloom + cone
		tick.Position = UDim2.new(0.5, math.cos(ang) * r, 0.5, math.sin(ang) * r)
	end
	local hk = now - hitT
	ui.hit.Visible = hk < 0.12
	if ui.hit.Visible then
		for _, c in ui.hit:GetChildren() do
			c.BackgroundColor3 = if hitKill then C.gold else C.white
		end
		ui.hit.Size = UDim2.fromOffset(30 + hk * 80, 30 + hk * 80)
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
