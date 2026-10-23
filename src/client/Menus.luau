--!nonstrict
-- Full-screen flows (RU, icon-first): lobby (В БОЙ / МАСТЕРСКАЯ), settings, upgrade cards with
-- reroll/banish, evolution splash with the evolved weapon model, results with scrap rewards.

local Lighting = game:GetService("Lighting")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Maps = require(Shared:WaitForChild("Maps"))
local Ops = require(Shared:WaitForChild("Ops"))
local Modules = require(Shared:WaitForChild("Modules"))
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
	local b = new("TextButton", {
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.05,
		Text = "",
		Corner = 4,
		AutoButtonColor = false,
		Parent = parent,
	})
	for k, v in props do
		b[k] = v
	end
	local z = (props.ZIndex or 1) + 1
	local l = label(text, {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		FontFace = F.head,
		TextSize = 20,
		TextColor3 = C.bg,
		ZIndex = z,
		Parent = b,
	})
	if iconName then
		local h = b.Size.Y.Offset
		icon(
			iconName,
			math.floor(h * 0.55),
			C.bg,
			{ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, math.floor(h * 0.3), 0.5, 0), ZIndex = z },
			accent
		).Parent =
			b
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
	local row = new("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 5),
		},
		Parent = parent,
	})
	for k, v in props or {} do
		row[k] = v
	end
	icon("xp", 18, color or C.gold, { LayoutOrder = 1, ZIndex = row.ZIndex }).Parent = row
	label(Theme.commas(amount), {
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		FontFace = F.num,
		TextSize = 20,
		TextColor3 = color or C.gold,
		ZIndex = row.ZIndex,
		Parent = row,
	})
	return row
end

local function fmt(n: number): string
	return if n % 1 == 0 then tostring(n) else string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", "")
end

-- Real numbers shown on the weapon card (one short value per stat bar).
local function cardValue(w, stat: string): string
	if stat == "power" then
		return if w.pellets > 1 then fmt(w.damage) .. "×" .. w.pellets else fmt(w.damage)
	elseif stat == "rate" then
		return if w.kind == "beam" then "ЛУЧ" else fmt(w.rate) .. "/с"
	elseif stat == "range" then
		return tostring(w.range)
	end
	return if w.pierce > 0 then "×" .. (w.pierce + 1) else ""
end

-- Dossier rows: { label, base value, evolved value? } from Defs (evolution mods where declared).
local function dossierRows(w, evolved: boolean)
	local evo = Defs.Evolutions[w.evolution]
	local m = evolved and evo.mods or {}
	local damage = w.damage + (m.damageAdd or 0)
	local rate = w.rate * (m.rateMult or 1)
	local mag = m.magazine or w.magazine
	local rows = {}
	local function row(name: string, value: string)
		table.insert(rows, { name, value })
	end
	row(
		"УРОН ЗА ПОПАДАНИЕ",
		if w.pellets > 1 then fmt(damage) .. " × " .. w.pellets .. " дробин" else fmt(damage)
	)
	if w.kind == "beam" then
		row("ТЕМП", "непрерывный луч · " .. fmt(rate) .. " тик/с")
		row("УРОН В СЕКУНДУ", fmt(math.floor(damage * rate + 0.5)))
		row("ОХЛАЖДЕНИЕ", "перегрев → " .. fmt(w.reload) .. " с")
	else
		row("ТЕМП", string.format("%.1f выстр/с", rate))
		row("УРОН В СЕКУНДУ", fmt(math.floor(damage * rate * w.pellets + 0.5)))
		row("ЯЧЕЙКА / МАГАЗИН", tostring(mag))
		row(
			"ПЕРЕЗАРЯДКА",
			if w.reloadEmpty
				then fmt(w.reload) .. " с · пустая " .. fmt(w.reloadEmpty) .. " с"
				else fmt(w.reload) .. " с"
		)
	end
	row("ДАЛЬНОСТЬ", tostring(w.range))
	row(
		"РАЗБРОС",
		if w.spreadMin
			then fmt(w.spreadMin) .. "° → " .. fmt(w.spreadMax) .. "° в очереди"
			else fmt(w.spread) .. "°"
	)
	row(
		"ПРОБИТИЕ",
		if w.pierce > 0
			then "насквозь " .. w.pierce .. " (−" .. math.floor((1 - w.falloff) * 100 + 0.5) .. "% за цель)"
			else "нет · улучшение ПРОБОЙ"
	)
	if evolved and m.forks then
		row("МОЛНИИ", #m.forks .. " цели · радиус " .. m.forkRadius)
	end
	return rows
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
		Gradient = {
			Rotation = 0,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(0.6, 0.45),
				NumberSequenceKeypoint.new(1, 0.7),
			}),
		},
		Parent = lobby,
	})
	local content = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1280, 720),
		Parent = lobby,
	})
	ui.lobbyScale = new("UIScale", { Parent = content })
	ui.lobbyContent = content

	-- Title (chromatic split)
	local title =
		new("Frame", { Position = UDim2.fromOffset(28, 14), Size = UDim2.fromOffset(470, 64), Parent = content })
	for i, spec in { { C.red, -3, 0.55 }, { C.cyan, 3, 0.55 }, { C.white, 0, 0 } } do
		local t = label("SWARMFALL", {
			Position = UDim2.fromOffset(spec[2], 0),
			Size = UDim2.fromScale(1, 1),
			FontFace = F.title,
			TextSize = 60,
			TextColor3 = spec[1],
			TextTransparency = spec[3],
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = i,
			Parent = title,
		})
		if i < 3 then
			t.Name = "Ghost"
		end
	end
	ui.title = title
	label("СДЕРЖИ РОЙ · РАЗВИВАЙ ОРУЖИЕ · ЗАЩИТИ РЕАКТОР", {
		Position = UDim2.fromOffset(32, 76),
		Size = UDim2.fromOffset(500, 18),
		FontFace = F.title,
		TextSize = 14,
		TextColor3 = C.cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})

	-- Scrap + settings (top-right)
	ui.scrapBox = Theme.panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(1196, 22),
		Size = UDim2.fromOffset(150, 44),
		Parent = content,
	}, C.gold)
	icon("xp", 26, C.gold, { Position = UDim2.fromOffset(12, 9) }).Parent = ui.scrapBox
	ui.scrap = label("0", {
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(1, -56, 1, 0),
		FontFace = F.num,
		TextSize = 26,
		TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = ui.scrapBox,
	})
	label("КСЕНИТ", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 2),
		Size = UDim2.fromOffset(60, 12),
		FontFace = F.title,
		TextSize = 10,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = ui.scrapBox,
	})
	-- Walk in Узел-7 (the physical base); the same menus open from its terminals.
	local walk, walkLabel = button(
		content,
		"УЗЕЛ-7 [H]",
		{ Position = UDim2.fromOffset(916, 22), Size = UDim2.fromOffset(120, 44) },
		C.panel2,
		"pin"
	)
	walkLabel.TextSize = 15
	walk.Activated:Connect(function()
		Audio.play("ui")
		if Menus.onWalk then
			Menus.onWalk()
		end
	end)
	local gear = button(
		content,
		"",
		{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(1252, 22), Size = UDim2.fromOffset(44, 44) },
		C.panel2
	)
	icon(
		"gear",
		28,
		C.text,
		{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 3 },
		C.panel2
	).Parent =
		gear
	gear.Activated:Connect(function()
		ui.settings.Visible = not ui.settings.Visible
		Audio.play("ui")
	end)

	-- Tabs
	ui.tabs = {}
	for i, t in { { "play", "В БОЙ", "swords" }, { "workshop", "РАЗВИТИЕ", "level" } } do
		local b, l = button(
			content,
			t[2],
			{ Position = UDim2.fromOffset(520 + (i - 1) * 200, 24), Size = UDim2.fromOffset(192, 40) },
			C.panel2,
			t[3]
		)
		l.TextColor3 = C.text
		b.Activated:Connect(function()
			tab = t[1]
			Audio.play("ui")
			Menus.refreshLobby()
		end)
		ui.tabs[t[1]] = { button = b, label = l }
	end

	-- PLAY tab -------------------------------------------------------------------------------------
	local play = new(
		"Frame",
		{ Name = "Play", Position = UDim2.fromOffset(0, 104), Size = UDim2.fromOffset(1280, 616), Parent = content }
	)
	ui.playTab = play
	-- Operations (left)
	label("ОПЕРАЦИЯ", {
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.fromOffset(300, 18),
		FontFace = F.title,
		TextSize = 13,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = play,
	})
	ui.opCards = {}
	for i, opId in Ops.Order do
		local op = Ops.get(opId)
		local map = Maps.get(op.map)
		local card = new("TextButton", {
			Position = UDim2.fromOffset(28, 24 + (i - 1) * 50),
			Size = UDim2.fromOffset(330, 46),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.1,
			Text = "",
			AutoButtonColor = false,
			Corner = 5,
			Stroke = { Color = C.line, Thickness = 1, Transparency = 0.3 },
			Parent = play,
		})
		local portrait = new("Frame", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(40, 38),
			BackgroundColor3 = if map.theme == "depths" then Color3.fromRGB(30, 16, 36) else Color3.fromRGB(12, 22, 34),
			BackgroundTransparency = 0,
			Corner = 4,
			ClipsDescendants = true,
			Parent = card,
		})
		local face = if op.objective == "boss" then Defs.Enemies[map.boss].index else Defs.Enemies.ELITE_BULWARK.index
		Preview.creature(portrait, face, { spin = true, zoom = 0.75, pitch = 0.3 })
		label(op.code, {
			Position = UDim2.fromOffset(52, 4),
			Size = UDim2.fromOffset(60, 16),
			FontFace = F.num,
			TextSize = 14,
			TextColor3 = if op.id == "CA01" then C.gold else C.cyan,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		label(op.name, {
			Position = UDim2.fromOffset(112, 3),
			Size = UDim2.fromOffset(212, 20),
			FontFace = F.head,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		label(map.name .. " · " .. op.goal, {
			Position = UDim2.fromOffset(52, 24),
			Size = UDim2.fromOffset(272, 18),
			FontFace = F.body,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		local lock = new("Frame", {
			Name = "Lock",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.bg,
			BackgroundTransparency = 0.25,
			Corner = 5,
			ZIndex = 5,
			Visible = false,
			Parent = card,
		})
		icon("lock", 22, C.dim, { Position = UDim2.fromOffset(14, 12), ZIndex = 6 }).Parent = lock
		local req = if op.requires then "Пройди " .. op.requires .. " · " .. Ops.get(op.requires).name else ""
		label(op.code .. " · " .. req, {
			Position = UDim2.fromOffset(46, 0),
			Size = UDim2.new(1, -52, 1, 0),
			FontFace = F.bodyBold,
			TextSize = 13,
			TextWrapped = true,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
			Parent = lock,
		})
		local scale = new("UIScale", { Parent = card })
		card.MouseEnter:Connect(function()
			tween(scale, 0.12, { Scale = 1.02 })
		end)
		card.MouseLeave:Connect(function()
			tween(scale, 0.12, { Scale = 1 })
		end)
		card.Activated:Connect(function()
			send("op", opId)
			Audio.play("ui")
		end)
		ui.opCards[opId] = { card = card, stroke = card:FindFirstChildOfClass("UIStroke"), lock = lock }
	end
	-- Threat selector
	label("УГРОЗА", {
		Position = UDim2.fromOffset(32, 384),
		Size = UDim2.fromOffset(300, 18),
		FontFace = F.title,
		TextSize = 13,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = play,
	})
	ui.threatPips = {}
	for t = 1, Defs.Threat.Max do
		local b = new("TextButton", {
			Position = UDim2.fromOffset(28 + (t - 1) * 66, 406),
			Size = UDim2.fromOffset(60, 60),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.1,
			Text = "",
			AutoButtonColor = false,
			Corner = 5,
			Stroke = { Color = C.line, Transparency = 0.3 },
			Parent = play,
		})
		local ic = icon("skull", 30, C.dim, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6) })
		ic.Parent = b
		label(tostring(t), {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -2),
			Size = UDim2.fromOffset(40, 18),
			FontFace = F.num,
			TextSize = 16,
			TextColor3 = C.dim,
			Name = "N",
			Parent = b,
		})
		b.Activated:Connect(function()
			send("threat", t)
			Audio.play("ui")
		end)
		ui.threatPips[t] = { button = b, icon = ic, stroke = b:FindFirstChildOfClass("UIStroke") }
	end
	ui.threatInfo = label("", {
		Position = UDim2.fromOffset(32, 472),
		Size = UDim2.fromOffset(330, 40),
		FontFace = F.bodyBold,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = play,
	})
	ui.hostNote = label("", {
		Position = UDim2.fromOffset(32, 512),
		Size = UDim2.fromOffset(330, 18),
		FontFace = F.body,
		TextSize = 12,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = play,
	})

	-- Weapons (center, 2×2)
	label("ОРУЖИЕ", {
		Position = UDim2.fromOffset(384, 0),
		Size = UDim2.fromOffset(300, 18),
		FontFace = F.title,
		TextSize = 13,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = play,
	})
	ui.cards = {}
	for i, id in Defs.WeaponOrder do
		local w = Defs.Weapons[id]
		local evo = Defs.Evolutions[w.evolution]
		local col, row = (i - 1) % 2, (i - 1) // 2
		local card = new("TextButton", {
			Position = UDim2.fromOffset(380 + col * 272, 24 + row * 252),
			Size = UDim2.fromOffset(262, 244),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.1,
			Text = "",
			AutoButtonColor = false,
			Corner = 5,
			Stroke = { Color = C.line, Thickness = 1, Transparency = 0.3 },
			Parent = play,
		})
		local scale = new("UIScale", { Parent = card })
		new(
			"Frame",
			{ Size = UDim2.new(1, 0, 0, 3), BackgroundTransparency = 0, BackgroundColor3 = w.color, Parent = card }
		)
		local view = new("Frame", {
			Position = UDim2.fromOffset(6, 8),
			Size = UDim2.new(1, -12, 0, 104),
			BackgroundColor3 = C.bg,
			BackgroundTransparency = 0.35,
			Corner = 4,
			Parent = card,
		})
		local vp = Preview.weapon(view, id, false, { spin = true, zoom = 0.62, pitch = 0.3 })
		label(w.name, {
			Position = UDim2.fromOffset(12, 114),
			Size = UDim2.new(1, -24, 0, 22),
			FontFace = F.head,
			TextSize = 19,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		-- stat icons with bars
		local k = 0
		for _, stat in { "power", "rate", "range", "control" } do
			local x = 12 + (k % 2) * 122
			local y = 140 + (k // 2) * 24
			icon(STAT_ICONS[stat], 16, w.color, { Position = UDim2.fromOffset(x, y + 2) }).Parent = card
			label(cardValue(w, stat), {
				Position = UDim2.fromOffset(x + 20, y),
				Size = UDim2.fromOffset(44, 20),
				FontFace = F.num,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = card,
			})
			local back = new("Frame", {
				Position = UDim2.fromOffset(x + 64, y + 8),
				Size = UDim2.fromOffset(50, 6),
				BackgroundTransparency = 0.5,
				BackgroundColor3 = Color3.new(0, 0, 0),
				Parent = card,
			})
			for s = 1, 5 do
				new("Frame", {
					Position = UDim2.fromScale((s - 1) / 5, 0),
					Size = UDim2.new(0.2, -2, 1, 0),
					BackgroundTransparency = if s / 5 <= w.stats[stat] + 0.05 then 0 else 0.85,
					BackgroundColor3 = w.color,
					Parent = back,
				})
			end
			k += 1
		end
		-- mastery (M1–M20) + permanent form: craft once (M10 + component + Ксенит), then equip/unequip
		local recipe = new("TextButton", {
			Position = UDim2.fromOffset(12, 190),
			Size = UDim2.new(1, -24, 0, 46),
			BackgroundColor3 = C.bg,
			BackgroundTransparency = 0.4,
			Text = "",
			AutoButtonColor = false,
			Corner = 4,
			Stroke = { Color = C.line, Transparency = 0.5 },
			Parent = card,
		})
		local mRank = label("M1", {
			Position = UDim2.fromOffset(6, 2),
			Size = UDim2.fromOffset(44, 24),
			FontFace = F.num,
			TextSize = 20,
			TextColor3 = w.color,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = recipe,
		})
		local mBack = new("Frame", {
			Position = UDim2.fromOffset(6, 30),
			Size = UDim2.fromOffset(44, 5),
			BackgroundTransparency = 0.4,
			BackgroundColor3 = Color3.new(0, 0, 0),
			Parent = recipe,
		})
		local mFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = w.color, Parent = mBack })
		local mKills = label("", {
			Position = UDim2.fromOffset(6, 35),
			Size = UDim2.fromOffset(60, 10),
			FontFace = F.num,
			TextSize = 9,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = recipe,
		})
		icon("evolve", 20, C.gold, { Position = UDim2.fromOffset(58, 12) }).Parent = recipe
		label(evo.name, {
			Position = UDim2.fromOffset(82, 3),
			Size = UDim2.new(1, -86, 0, 20),
			FontFace = F.head,
			TextSize = 14,
			TextColor3 = C.gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = recipe,
		})
		local formState = label("", {
			Position = UDim2.fromOffset(82, 23),
			Size = UDim2.new(1, -86, 0, 18),
			FontFace = F.title,
			TextSize = 11,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = recipe,
		})
		recipe.Activated:Connect(function()
			if not profile then
				return
			end
			local forms, equip = profile.forms or {}, profile.equip or {}
			if forms[evo.id] then
				send("equipForm", id, if equip[id] == evo.id then "" else evo.id)
				Audio.play("ui")
			elseif recipe:GetAttribute("Ready") then
				send("craftForm", evo.id)
				Audio.play("evolve")
			else
				Audio.play("warn")
			end
		end)
		-- dossier (full numbers + evolved form preview)
		local info = new("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 12),
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = 0.15,
			Text = "",
			AutoButtonColor = false,
			Corner = 4,
			ZIndex = 3,
			Stroke = { Color = w.color, Transparency = 0.4 },
			Parent = card,
		})
		icon(
			"eye",
			20,
			w.color,
			{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 4 },
			C.panel2
		).Parent =
			info
		info.Activated:Connect(function()
			Menus.dossier(id)
			Audio.play("ui")
		end)
		-- lock overlay
		local lock = new("Frame", {
			Name = "Lock",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.bg,
			BackgroundTransparency = 0.3,
			Corner = 5,
			ZIndex = 5,
			Visible = false,
			Parent = card,
		})
		icon(
			"lock",
			36,
			C.gold,
			{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), ZIndex = 6 }
		).Parent =
			lock
		local priceRow = scrapTag(
			lock,
			w.cost,
			{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 162), ZIndex = 6 }
		)
		priceRow.ZIndex = 6
		label("НАЖМИ, ЧТОБЫ КУПИТЬ", {
			Name = "Hint",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 192),
			Size = UDim2.new(1, 0, 0, 16),
			FontFace = F.title,
			TextSize = 11,
			TextColor3 = C.dim,
			ZIndex = 6,
			Parent = lock,
		})
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
		ui.cards[id] = {
			card = card,
			stroke = card:FindFirstChildOfClass("UIStroke"),
			color = w.color,
			lock = lock,
			price = priceRow,
			vp = vp,
			view = view,
			recipe = recipe,
			mRank = mRank,
			mFill = mFill,
			mKills = mKills,
			formState = formState,
			evo = evo,
		}
	end

	-- Squad + deploy (right)
	label("ОТРЯД", {
		Position = UDim2.fromOffset(940, 0),
		Size = UDim2.fromOffset(300, 18),
		FontFace = F.title,
		TextSize = 13,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = play,
	})
	ui.squadList = new("Frame", {
		Position = UDim2.fromOffset(936, 24),
		Size = UDim2.fromOffset(316, 300),
		List = { Padding = UDim.new(0, 6) },
		Parent = play,
	})
	ui.deploy, ui.deployLabel = button(
		play,
		"В БОЙ",
		{ Position = UDim2.fromOffset(936, 420), Size = UDim2.fromOffset(316, 76) },
		C.cyan,
		"play"
	)
	ui.deployLabel.TextSize = 28
	ui.deploy.Activated:Connect(function()
		Audio.play("ui", 1, 1.2)
		if ui.ready then
			send("unready")
		else
			send("ready", selectedWeapon)
		end
	end)
	ui.lobbyStatus = label("", {
		Position = UDim2.fromOffset(936, 500),
		Size = UDim2.fromOffset(316, 40),
		FontFace = F.bodyBold,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = C.dim,
		Parent = play,
	})
	ui.controlsHint = label("", {
		Position = UDim2.fromOffset(936, 548),
		Size = UDim2.fromOffset(316, 64),
		FontFace = F.mono,
		TextSize = 12,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = play,
	})

	-- WORKSHOP tab ---------------------------------------------------------------------------------
	local shop = new("Frame", {
		Name = "Workshop",
		Position = UDim2.fromOffset(0, 104),
		Size = UDim2.fromOffset(1280, 616),
		Visible = false,
		Parent = content,
	})
	ui.shopTab = shop
	label(
		"ПЕРКИ — действуют во всех забегах. Не огромная сила, а выбор.",
		{
			Position = UDim2.fromOffset(32, 0),
			Size = UDim2.fromOffset(800, 20),
			FontFace = F.body,
			TextSize = 15,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = shop,
		}
	)
	ui.perkCards = {}
	for i, id in Defs.PerkOrder do
		local def = Defs.Perks[id]
		local col, row = (i - 1) % 4, (i - 1) // 4
		local card = Theme.panel({
			Position = UDim2.fromOffset(28 + col * 202, 28 + row * 292),
			Size = UDim2.fromOffset(194, 284),
			Parent = shop,
		}, def.color)
		local badge = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 16),
			Size = UDim2.fromOffset(70, 70),
			BackgroundColor3 = C.bg,
			BackgroundTransparency = 0.2,
			Rotation = 45,
			Corner = 10,
			Stroke = { Color = def.color, Thickness = 2 },
			Parent = card,
		})
		icon(def.icon, 44, def.color, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 29) }, C.bg).Parent =
			card
		label(def.name, {
			Position = UDim2.fromOffset(0, 104),
			Size = UDim2.new(1, 0, 0, 24),
			FontFace = F.head,
			TextSize = 19,
			Parent = card,
		})
		local pips = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 134),
			Size = UDim2.fromOffset(180, 8),
			List = {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 5),
			},
			Parent = card,
		})
		local pipList = {}
		for r = 1, def.max do
			pipList[r] = new(
				"Frame",
				{ Size = UDim2.fromOffset(24, 8), BackgroundTransparency = 0, BackgroundColor3 = C.line, Parent = pips }
			)
		end
		local stat = label("", {
			Position = UDim2.fromOffset(10, 150),
			Size = UDim2.new(1, -20, 0, 64),
			FontFace = F.bodyBold,
			TextSize = 14,
			TextWrapped = true,
			Parent = card,
		})
		local buy, buyLabel = button(card, "", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.fromOffset(170, 40),
		}, def.color)
		buy.Activated:Connect(function()
			send("buyPerk", id)
			Audio.play("level", 1, 1.15)
		end)
		ui.perkCards[id] = { card = card, pips = pipList, stat = stat, buy = buy, buyLabel = buyLabel, def = def }
	end

	-- Laboratory: starter technologies (after the first O01 win)
	label("ЛАБОРАТОРИЯ", {
		Position = UDim2.fromOffset(852, 0),
		Size = UDim2.fromOffset(300, 20),
		FontFace = F.title,
		TextSize = 13,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = shop,
	})
	ui.techCards = {}
	for i, tid in Defs.TechOrder do
		local def = Defs.Tech[tid]
		local card = new("TextButton", {
			Position = UDim2.fromOffset(848, 26 + (i - 1) * 74),
			Size = UDim2.fromOffset(404, 68),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.1,
			Text = "",
			AutoButtonColor = false,
			Corner = 5,
			Stroke = { Color = C.line, Transparency = 0.3 },
			Parent = shop,
		})
		icon(
			if tid == "TECH_PIERCE_CORE" then "pierce" else "reactor",
			30,
			C.cyan,
			{ Position = UDim2.fromOffset(10, 19) }
		).Parent =
			card
		label(def.name, {
			Position = UDim2.fromOffset(50, 6),
			Size = UDim2.fromOffset(240, 20),
			FontFace = F.head,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		label(def.text, {
			Position = UDim2.fromOffset(50, 28),
			Size = UDim2.fromOffset(240, 36),
			FontFace = F.body,
			TextSize = 12,
			TextWrapped = true,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = card,
		})
		local state = label("", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.fromOffset(104, 68),
			FontFace = F.title,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
		card.Activated:Connect(function()
			send("buyTech", tid)
			Audio.play("level", 1, 1.15)
		end)
		ui.techCards[tid] = { card = card, state = state, stroke = card:FindFirstChildOfClass("UIStroke") }
	end

	-- Research: personal confirmed kills per species (stages I–III)
	label("ИССЛЕДОВАНИЯ ВИДОВ", {
		Position = UDim2.fromOffset(852, 180),
		Size = UDim2.fromOffset(300, 20),
		FontFace = F.title,
		TextSize = 13,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = shop,
	})
	ui.researchRows = {}
	local order = {
		"EN_RUNNER",
		"EN_SPITTER",
		"EN_STALKER",
		"EN_BULWARK",
		"EN_BOMBER",
		"ELITE_CARRIER",
		"ELITE_BULWARK",
		"HIVE",
		"BOSS_BROODMOTHER",
		"BOSS_DEVOURER",
	}
	for i, kind in order do
		local row = new("Frame", {
			Position = UDim2.fromOffset(848, 204 + (i - 1) * 31),
			Size = UDim2.fromOffset(404, 28),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.25,
			Corner = 4,
			Parent = shop,
		})
		local name = label("", {
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.fromOffset(190, 30),
			FontFace = F.head,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local stage = label("", {
			Position = UDim2.fromOffset(200, 0),
			Size = UDim2.fromOffset(40, 30),
			FontFace = F.num,
			TextSize = 14,
			TextColor3 = C.lime,
			Parent = row,
		})
		local back = new("Frame", {
			Position = UDim2.fromOffset(244, 12),
			Size = UDim2.fromOffset(84, 6),
			BackgroundTransparency = 0.4,
			BackgroundColor3 = Color3.new(0, 0, 0),
			Parent = row,
		})
		local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.lime, Parent = back })
		local count = label("", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.fromOffset(70, 30),
			FontFace = F.num,
			TextSize = 12,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		ui.researchRows[kind] = { name = name, stage = stage, fill = fill, count = count }
	end
	ui.s01Branches = {}
	for i, b in { "A", "B", "C" } do
		local def = Defs.S01Branches[b]
		local btn, lbl = button(
			shop,
			def.name,
			{ Position = UDim2.fromOffset(848 + (i - 1) * 136, 560), Size = UDim2.fromOffset(130, 34) },
			C.panel2
		)
		lbl.TextSize = 12
		btn.Activated:Connect(function()
			send("s01Branch", b)
			Audio.play("ui", 1, 1.1)
		end)
		ui.s01Branches[b] = { button = btn, label = lbl, def = def }
	end
	ui.s01Tier = label("", {
		Position = UDim2.fromOffset(852, 596),
		Size = UDim2.fromOffset(400, 18),
		FontFace = F.body,
		TextSize = 12,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = shop,
	})
	ui.s01Line = label("", {
		Position = UDim2.fromOffset(852, 518),
		Size = UDim2.fromOffset(400, 40),
		FontFace = F.bodyBold,
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = C.cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = shop,
	})

	Menus.selectWeapon(selectedWeapon)
end

local function buildSettings()
	local panel = Theme.panel({
		Name = "Settings",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 320),
		Visible = false,
		ZIndex = 50,
		Parent = gui,
	}, C.cyan)
	panel.BackgroundTransparency = 0.02
	ui.settings = panel
	icon("gear", 26, C.cyan, { Position = UDim2.fromOffset(18, 14), ZIndex = 51 }).Parent = panel
	label("НАСТРОЙКИ", {
		Position = UDim2.fromOffset(54, 14),
		Size = UDim2.fromOffset(300, 26),
		FontFace = F.head,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 51,
		Parent = panel,
	})
	local names = { "НИЗКО", "СРЕДНЕ", "ВЫСОКО" }
	local rows = {
		{
			"ГРАФИКА",
			"eye",
			function()
				return names[Settings.quality]
			end,
			function()
				Settings.set("quality", Settings.quality % 3 + 1)
			end,
		},
		{
			"ТРЯСКА ЭКРАНА",
			"boom",
			function()
				return if Settings.shake then "ВКЛ" else "ВЫКЛ"
			end,
			function()
				Settings.set("shake", not Settings.shake)
			end,
		},
		{
			"ЦИФРЫ УРОНА",
			"burst",
			function()
				return if Settings.numbers then "ВКЛ" else "ВЫКЛ"
			end,
			function()
				Settings.set("numbers", not Settings.numbers)
			end,
		},
		{
			"АВТОНАВЕДЕНИЕ",
			"crosshair",
			function()
				return if Settings.aimAssist then "ВКЛ" else "ВЫКЛ"
			end,
			function()
				Settings.set("aimAssist", not Settings.aimAssist)
			end,
		},
	}
	for i, r in rows do
		local y = 60 + (i - 1) * 54
		icon(r[2], 24, C.dim, { Position = UDim2.fromOffset(20, y + 6), ZIndex = 51 }).Parent = panel
		label(r[1], {
			Position = UDim2.fromOffset(54, y),
			Size = UDim2.fromOffset(220, 36),
			FontFace = F.title,
			TextSize = 14,
			TextColor3 = C.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 51,
			Parent = panel,
		})
		local b, l = button(
			panel,
			r[3](),
			{ Position = UDim2.fromOffset(300, y), Size = UDim2.fromOffset(140, 38), ZIndex = 51 },
			C.panel2
		)
		l.TextColor3 = C.cyan
		l.TextSize = 16
		b.Activated:Connect(function()
			r[4]()
			l.Text = r[3]()
			Audio.play("ui")
		end)
	end
	local close, cl = button(panel, "ЗАКРЫТЬ", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(180, 38),
		ZIndex = 51,
	}, C.cyan)
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

-- Weapon dossier: big preview (base / evolved), every real number, the evolution recipe.
local function buildDossier()
	local d = new("TextButton", {
		Name = "Dossier",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.25,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	ui.dossier = d
	local box = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(940, 540),
		ZIndex = 21,
		Parent = d,
	}, C.cyan)
	ui.dossierBox = box
	ui.dossierStroke = box:FindFirstChildOfClass("UIStroke")
	new("UIScale", { Name = "Fit", Parent = box })
	ui.dossierView = new("Frame", {
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(470, 380),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.3,
		Corner = 4,
		ZIndex = 22,
		Parent = box,
	})
	ui.dossierTabs = {}
	for i, t in { { "base", "БАЗОВАЯ" }, { "evo", "ЭВОЛЮЦИЯ" }, { "mods", "МОДУЛИ" } } do
		local b, l = button(
			box,
			t[2],
			{ Position = UDim2.fromOffset(16 + (i - 1) * 158, 404), Size = UDim2.fromOffset(152, 40), ZIndex = 22 },
			C.panel2
		)
		l.TextSize = 15
		b.Activated:Connect(function()
			Menus.dossier(ui.dossierWeapon, t[1])
			Audio.play("ui")
		end)
		ui.dossierTabs[t[1]] = { button = b, label = l }
	end
	ui.dossierRecipe = new("Frame", {
		Position = UDim2.fromOffset(16, 456),
		Size = UDim2.fromOffset(470, 68),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.4,
		Corner = 4,
		ZIndex = 22,
		Parent = box,
	})
	ui.dossierName = label("", {
		Position = UDim2.fromOffset(506, 14),
		Size = UDim2.fromOffset(410, 34),
		FontFace = F.head,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = box,
	})
	ui.dossierTag = label("", {
		Position = UDim2.fromOffset(506, 50),
		Size = UDim2.fromOffset(410, 40),
		FontFace = F.body,
		TextSize = 15,
		TextWrapped = true,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 22,
		Parent = box,
	})
	ui.dossierRows = new("Frame", {
		Position = UDim2.fromOffset(506, 96),
		Size = UDim2.fromOffset(410, 330),
		List = { Padding = UDim.new(0, 4) },
		ZIndex = 22,
		Parent = box,
	})
	-- M20 alternative form line (evolution tab): progress of its feat, craft or equip on click.
	ui.dossierM20, ui.dossierM20Label = button(
		box,
		"",
		{ Position = UDim2.fromOffset(506, 430), Size = UDim2.fromOffset(410, 32), ZIndex = 22 },
		C.panel2
	)
	ui.dossierM20Label.TextSize = 12
	ui.dossierM20Label.TextWrapped = true
	ui.dossierM20.Activated:Connect(function()
		local id = ui.dossierWeapon
		local formId = id and Defs.M20ByWeapon[id]
		if not formId or not profile then
			return
		end
		if profile.forms and profile.forms[formId] then
			send("equipForm", id, if profile.equip and profile.equip[id] == formId then "" else formId)
			Audio.play("ui")
		else
			send("craftForm", formId)
			Audio.play("evolve")
		end
	end)
	-- Modules: 3 branches (columns) × 3 tiers (rows). Click: craft, then cycle CORE → ADAPTER → off.
	ui.dossierMods = new("Frame", {
		Position = UDim2.fromOffset(506, 96),
		Size = UDim2.fromOffset(410, 360),
		Visible = false,
		ZIndex = 22,
		Parent = box,
	})
	ui.modCells = {}
	ui.modHeads = {}
	for col = 1, 3 do
		ui.modHeads[col] = label("", {
			Position = UDim2.fromOffset((col - 1) * 138, 0),
			Size = UDim2.fromOffset(132, 18),
			FontFace = F.title,
			TextSize = 11,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
			Parent = ui.dossierMods,
		})
		for row = 1, 3 do
			local cell = new("TextButton", {
				Position = UDim2.fromOffset((col - 1) * 138, 22 + (row - 1) * 106),
				Size = UDim2.fromOffset(132, 100),
				BackgroundColor3 = C.panel2,
				BackgroundTransparency = 0.25,
				Text = "",
				AutoButtonColor = false,
				Corner = 4,
				Stroke = { Color = C.line, Transparency = 0.4 },
				ZIndex = 23,
				Parent = ui.dossierMods,
			})
			local tier = label(Modules.Roman[row], {
				Position = UDim2.fromOffset(8, 4),
				Size = UDim2.fromOffset(40, 16),
				FontFace = F.num,
				TextSize = 14,
				TextColor3 = C.cyan,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 24,
				Parent = cell,
			})
			local name = label("", {
				Position = UDim2.fromOffset(8, 20),
				Size = UDim2.fromOffset(118, 34),
				FontFace = F.head,
				TextSize = 13,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 24,
				Parent = cell,
			})
			local text = label("", {
				Position = UDim2.fromOffset(8, 54),
				Size = UDim2.fromOffset(118, 26),
				FontFace = F.body,
				TextSize = 10,
				TextWrapped = true,
				TextColor3 = C.dim,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 24,
				Parent = cell,
			})
			local state = label("", {
				Position = UDim2.fromOffset(8, 80),
				Size = UDim2.fromOffset(118, 16),
				FontFace = F.title,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 24,
				Parent = cell,
			})
			local c = {
				cell = cell,
				tier = tier,
				name = name,
				text = text,
				state = state,
				stroke = cell:FindFirstChildOfClass("UIStroke"),
			}
			cell.Activated:Connect(function()
				local m = c.def
				if not m or not profile then
					return
				end
				local owned = profile.modules and profile.modules[m.id]
				if not owned then
					send("craftModule", m.id)
					Audio.play("level", 1, 1.1)
					return
				end
				local lo = profile.loadout and profile.loadout[m.weapon] or {}
				if lo.core == m.id then
					send("equipModule", m.weapon, "adapter", m.id)
				elseif lo.adapter == m.id then
					send("equipModule", m.weapon, "adapter", "")
				else
					send("equipModule", m.weapon, "core", m.id)
				end
				Audio.play("ui")
			end)
			ui.modCells[(col - 1) * 3 + row] = c
		end
	end
	local pick, pickLabel = button(
		box,
		"ВЫБРАТЬ",
		{ Position = UDim2.fromOffset(506, 470), Size = UDim2.fromOffset(250, 50), ZIndex = 22 },
		C.cyan,
		"play"
	)
	ui.dossierPick, ui.dossierPickLabel = pick, pickLabel
	pick.Activated:Connect(function()
		Menus.selectWeapon(ui.dossierWeapon)
		d.Visible = false
		Audio.play("ui", 1, 1.2)
	end)
	local close = button(
		box,
		"ЗАКРЫТЬ",
		{ Position = UDim2.fromOffset(766, 470), Size = UDim2.fromOffset(150, 50), ZIndex = 22 },
		C.panel2
	)
	close.Activated:Connect(function()
		d.Visible = false
		Audio.play("ui")
	end)
	d.Activated:Connect(function()
		d.Visible = false
	end)
end

local function refreshModules(id: string)
	local list = Modules.ByWeapon[id] or {}
	local mastery = Defs.masteryRank(id, profile and profile.mastery and profile.mastery[id] or 0)
	local owned = profile and profile.modules or {}
	local lo = profile and profile.loadout and profile.loadout[id] or {}
	local scrap = profile and profile.scrap or 0
	for _, m in list do
		local col = if m.branch == "A" then 1 elseif m.branch == "B" then 2 else 3
		ui.modHeads[col].Text = m.branch .. " · " .. string.upper(m.branchName)
		local c = ui.modCells[(col - 1) * 3 + m.tier]
		c.def = m
		c.name.Text = m.name
		c.text.Text = m.text
		local prevOwned = m.tier == 1 or owned[string.format("MOD_%s_%s%d", id:sub(3), m.branch, m.tier - 1)]
		local accent = C.line
		if lo.core == m.id then
			c.state.Text = "CORE · нажми → ADAPTER"
			c.state.TextColor3 = C.gold
			accent = C.gold
		elseif lo.adapter == m.id then
			c.state.Text = "ADAPTER · нажми → снять"
			c.state.TextColor3 = C.cyan
			accent = C.cyan
		elseif owned[m.id] then
			c.state.Text = "ИЗГОТОВЛЕН · нажми → CORE"
			c.state.TextColor3 = C.text
		elseif mastery < m.mastery then
			c.state.Text = "НУЖНО M" .. m.mastery
			c.state.TextColor3 = C.dim
		elseif not prevOwned then
			c.state.Text = "СНАЧАЛА " .. Modules.Roman[m.tier - 1]
			c.state.TextColor3 = C.dim
		else
			c.state.Text = "ИЗГОТОВИТЬ · " .. Theme.commas(m.cost)
			c.state.TextColor3 = if scrap >= m.cost then C.gold else C.dim
			if scrap >= m.cost then
				accent = C.gold
			end
		end
		c.stroke.Color = accent
		c.stroke.Transparency = if accent == C.line then 0.4 else 0.05
	end
end

function Menus.dossier(id: string, mode: any?)
	local w = Defs.Weapons[id]
	if not w then
		return
	end
	if mode == true then
		mode = "evo"
	elseif mode == nil or mode == false then
		mode = "base"
	end
	local evolved = mode == "evo"
	ui.dossierMode = mode
	if not ui.dossier then
		buildDossier()
	end
	local evo = Defs.Evolutions[w.evolution]
	ui.dossierWeapon = id
	ui.dossier.Visible = true
	ui.dossierBox.Fit.Scale =
		math.min(1, workspace.CurrentCamera.ViewportSize.X / 1000, workspace.CurrentCamera.ViewportSize.Y / 580)
	local accent = if evolved then evo.color else w.color
	ui.dossierStroke.Color = accent
	clear(ui.dossierView)
	Preview.weapon(ui.dossierView, id, evolved == true, { spin = true, zoom = 0.6, pitch = 0.32 }).ZIndex = 23
	ui.dossierName.Text = if evolved then evo.name else w.name
	ui.dossierName.TextColor3 = if evolved then C.gold else C.text
	ui.dossierTag.Text = if evolved then evo.text else w.tagline
	for key, t in ui.dossierTabs do
		local on = key == mode
		t.button.BackgroundColor3 = if on then accent else C.panel2
		t.label.TextColor3 = if on then C.bg else C.text
	end
	ui.dossierTabs.evo.label.Text = evo.name
	ui.dossierRows.Visible = mode ~= "mods"
	ui.dossierMods.Visible = mode == "mods"
	ui.dossierM20.Visible = mode == "evo"
	if mode == "evo" then
		local formId = Defs.M20ByWeapon[id]
		local form = Defs.Evolutions[formId]
		local f = profile and profile.feats and profile.feats[id] or {}
		local have = f[form.feat.counter] or 0
		local rank = Defs.masteryRank(id, profile and profile.mastery and profile.mastery[id] or 0)
		local crafted = profile and profile.forms and profile.forms[formId]
		local equipped = crafted and profile.equip and profile.equip[id] == formId
		local state = if equipped
			then "НАДЕТА · нажми, чтобы снять"
			elseif crafted then "ИЗГОТОВЛЕНА · нажми, чтобы надеть"
			elseif rank >= 20 and have >= form.feat.need then "ИЗГОТОВИТЬ · " .. Theme.commas(form.cost)
			else string.format(
				"M%d/20 · %s %s/%s",
				rank,
				form.feat.text,
				Theme.commas(math.min(have, form.feat.need)),
				Theme.commas(form.feat.need)
			)
		ui.dossierM20Label.Text = "M20 · " .. form.name .. " — " .. state
		ui.dossierM20Label.TextColor3 = if equipped then form.color else C.text
	end
	if mode == "mods" then
		ui.dossierName.Text = w.name .. " · МОДУЛИ"
		ui.dossierTag.Text =
			"1 CORE + 1 ADAPTER из другой ветки (ADAPTER до II). III — только CORE."
		refreshModules(id)
	end
	clear(ui.dossierRows)
	for i, r in dossierRows(w, evolved == true) do
		local line = new("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = if i % 2 == 0 then 0.6 else 0.35,
			Corner = 3,
			ZIndex = 22,
			Parent = ui.dossierRows,
		})
		label(r[1], {
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(0.48, -10, 1, 0),
			FontFace = F.title,
			TextSize = 12,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
			Parent = line,
		})
		label(r[2], {
			Position = UDim2.new(0.48, 0, 0, 0),
			Size = UDim2.new(0.52, -10, 1, 0),
			FontFace = F.bodyBold,
			TextSize = 15,
			TextColor3 = if evolved then C.gold else C.text,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 23,
			Parent = line,
		})
	end
	-- Permanent form requirements (crafted once in the arsenal; no in-run recipe).
	clear(ui.dossierRecipe)
	label("ПОСТОЯННАЯ ФОРМА · " .. evo.name, {
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.fromOffset(440, 14),
		FontFace = F.title,
		TextSize = 11,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = ui.dossierRecipe,
	})
	local comp = Defs.Components[evo.component]
	local x = 10
	for _, part in
		{
			{ "level", "M" .. Defs.FormMastery, C.cyan },
			{ "core", comp and comp.name or "", C.gold },
			{ "xp", Theme.commas(evo.cost) .. " КСЕНИТА", C.gold },
		}
	do
		icon(part[1], 26, part[3], { Position = UDim2.fromOffset(x, 28), ZIndex = 23 }).Parent = ui.dossierRecipe
		label(part[2], {
			Position = UDim2.fromOffset(x + 30, 30),
			Size = UDim2.fromOffset(120, 22),
			FontFace = F.bodyBold,
			TextSize = 13,
			TextColor3 = part[3],
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
			Parent = ui.dossierRecipe,
		})
		x += 150
	end
	local owned = profile == nil or profile.weapons[id] == true
	ui.dossierPick.Visible = owned
end

-- Opens a lobby tab directly (Узел-7 terminals): "play" | "workshop".
function Menus.profile()
	return profile
end

function Menus.dossierSelected(view: string)
	Menus.dossier(selectedWeapon, view)
end

function Menus.setTab(name: string)
	tab = name
	Menus.refreshLobby()
end

function Menus.setProfile(pub)
	profile = pub
	if ui.dossier and ui.dossier.Visible and ui.dossierMode == "mods" then
		refreshModules(ui.dossierWeapon)
	end
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
	-- weapons: lock / blueprint, mastery, permanent form
	for id, c in ui.cards do
		local owned = profile == nil or profile.weapons[id] == true
		c.lock.Visible = not owned
		if not owned then
			local blueprint = profile == nil or profile.blueprints == nil or profile.blueprints[id] ~= false
			local afford = scrap >= Defs.Weapons[id].cost
			c.price.Visible = blueprint
			if not blueprint then
				local opId = Defs.Blueprints[id]
				c.lock.Hint.Text = "ЧЕРТЁЖ: ПОБЕДА В " .. opId .. " · " .. Ops.get(opId).name
				c.lock.Hint.TextColor3 = C.dim
			else
				c.lock.Hint.Text = if afford
					then "НАЖМИ, ЧТОБЫ ИЗГОТОВИТЬ"
					else "НЕ ХВАТАЕТ КСЕНИТА"
				c.lock.Hint.TextColor3 = if afford then C.gold else C.dim
			end
		end
		local kills = profile and profile.mastery and profile.mastery[id] or 0
		local rank, into, need = Defs.masteryRank(id, kills)
		c.mRank.Text = "M" .. rank
		c.mFill.Size = UDim2.fromScale(if need then math.clamp(into / need, 0, 1) else 1, 1)
		c.mKills.Text = if need then Theme.commas(into) .. "/" .. Theme.commas(need) else "МАКС"
		local evo = c.evo
		local forms = profile and profile.forms or {}
		local equip = profile and profile.equip or {}
		local comps = profile and profile.components or {}
		local crafted = forms[evo.id] == true
		local equipped = crafted and equip[id] == evo.id
		local ready = false
		local stroke = c.recipe:FindFirstChildOfClass("UIStroke")
		if equipped then
			c.formState.Text = "ЭКИПИРОВАНА · НАЖМИ, ЧТОБЫ СНЯТЬ"
			c.formState.TextColor3 = C.gold
		elseif crafted then
			c.formState.Text = "ИЗГОТОВЛЕНА · НАЖМИ, ЧТОБЫ НАДЕТЬ"
			c.formState.TextColor3 = C.text
		else
			local needs = {}
			if rank < Defs.FormMastery then
				table.insert(needs, "M" .. Defs.FormMastery)
			end
			if not comps[evo.component] then
				table.insert(needs, Defs.Components[evo.component].name)
			end
			if #needs == 0 and owned then
				ready = scrap >= evo.cost
				c.formState.Text = "ИЗГОТОВИТЬ · " .. Theme.commas(evo.cost) .. " КСЕНИТА"
				c.formState.TextColor3 = if ready then C.gold else C.dim
			else
				c.formState.Text = "НУЖНО: " .. table.concat(needs, " · ")
				c.formState.TextColor3 = C.dim
			end
		end
		c.recipe:SetAttribute("Ready", ready)
		if stroke then
			stroke.Color = if equipped or ready then C.gold else C.line
			stroke.Transparency = if equipped or ready then 0.1 else 0.5
		end
		-- The card model shows the form you will actually fight with.
		if c.shownForm ~= equipped then
			c.shownForm = equipped
			if c.vp then
				c.vp:Destroy()
			end
			c.vp = Preview.weapon(c.view, id, equipped, { spin = true, zoom = 0.62, pitch = 0.3 })
		end
	end
	-- maps / threat
	local isHost = lobbyState and lobbyState.host == myId
	local opsProgress = profile and profile.ops or {}
	for opId, m in ui.opCards do
		local unlocked = profile == nil or (opsProgress[opId] or 0) >= 1
		m.lock.Visible = not unlocked
		local selected = lobbyState and lobbyState.op == opId
		m.stroke.Color = if selected then C.cyan else C.line
		m.stroke.Thickness = if selected then 3 else 1
		m.stroke.Transparency = if selected then 0 else 0.3
	end
	local opId = lobbyState and lobbyState.op or "O01"
	local threat = lobbyState and lobbyState.threat or 1
	local maxThreat = if profile then (opsProgress[opId] or 1) else 1
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
		else string.format(
			"Здоровье врагов +%d%%, урон +%d%% · награда ×%.2f",
			(Defs.Threat.hp(threat) - 1) * 100,
			(Defs.Threat.damage(threat) - 1) * 100,
			Defs.Threat.reward(threat)
		)
	ui.hostNote.Text = if isHost or not lobbyState
		then ""
		else "Операцию и угрозу выбирает лидер отряда"
	-- laboratory
	local won = profile and ((profile.ops and (profile.ops.O01 or 1) >= 2) or (profile.ops and profile.ops.O02 ~= nil))
	for tid, tc in ui.techCards or {} do
		local def = Defs.Tech[tid]
		local owned = profile and profile.tech and profile.tech[tid]
		if owned then
			tc.state.Text = "ИЗУЧЕНО"
			tc.state.TextColor3 = C.lime
		elseif not won then
			tc.state.Text = "ПОСЛЕ ПОБЕДЫ В O01"
			tc.state.TextColor3 = C.dim
		else
			tc.state.Text = "ИЗУЧИТЬ · " .. Theme.commas(def.cost)
			tc.state.TextColor3 = if scrap >= def.cost then C.gold else C.dim
		end
		tc.stroke.Color = if owned then C.lime elseif won and scrap >= def.cost then C.gold else C.line
	end
	-- research
	for kind, row in ui.researchRows or {} do
		local kills = profile and profile.research and profile.research[kind] or 0
		local st = Defs.researchStage(kind, kills)
		local th = Defs.Research[kind]
		local known = kills > 0
		row.name.Text = if known then Defs.Enemies[kind].name else "???"
		row.name.TextColor3 = if known then C.text else C.dim
		row.stage.Text = if st > 0 then string.rep("I", st) else "—"
		local nextNeed = th[math.min(st + 1, #th)]
		local prevNeed = if st > 0 then th[st] else 0
		row.fill.Size = UDim2.fromScale(
			if st >= #th then 1 else math.clamp((kills - prevNeed) / math.max(1, nextNeed - prevNeed), 0, 1),
			1
		)
		row.count.Text = if st >= #th then Theme.commas(kills) else Theme.commas(kills) .. "/" .. Theme.commas(nextNeed)
	end
	if ui.s01Line then
		local s = profile and profile.s01Stats
		local points = Defs.s01Points(s)
		local rank = Defs.s01Rank(points)
		local nextNeed = Defs.S01Mastery.Ladder[math.min(rank + 1, #Defs.S01Mastery.Ladder)]
		ui.s01Line.Text = if profile and profile.s01
			then string.format(
				"ГРАВИМОЛОТ S01 · M%d (%s/%s) · попаданий %s · убийств %s · массовых %s",
				rank,
				Theme.commas(points),
				Theme.commas(nextNeed),
				Theme.commas(s.hits),
				Theme.commas(s.kills),
				Theme.commas(s.crowds)
			)
			else "ГРАВИМОЛОТ S01 — откроется в O01"
		local open = profile and profile.s01 and rank >= Defs.S01Mastery.BranchAt
		local tier = Defs.s01Tier(rank)
		for b, ub in ui.s01Branches do
			local on = profile and profile.s01Branch == b
			ub.button.BackgroundColor3 = if on then ub.def.color elseif open then C.panel2 else C.bg
			ub.label.TextColor3 = if on then C.bg elseif open then C.text else C.dim
		end
		local chosen = profile and profile.s01Branch and Defs.S01Branches[profile.s01Branch]
		ui.s01Tier.Text = if not open
			then "Специализация откроется на M" .. Defs.S01Mastery.BranchAt
			elseif chosen then chosen.name .. " · " .. (if tier > 0 then chosen.tiers[tier] else "") .. (if tier
					< 3
				then "  (след. ступень на M" .. Defs.S01Mastery.TierAt[tier + 1] .. ")"
				else "")
			else "Выбери одну главную ветку"
	end
	-- perks
	for id, pc in ui.perkCards do
		local rank = profile and profile.perks[id] or 0
		local def = pc.def
		for r, pip in pc.pips do
			pip.BackgroundColor3 = if r <= rank then def.color else C.line
		end
		pc.stat.Text = if rank > 0
			then def.stat(rank) .. (if rank < def.max
				then '\n<font color="#7E95A6">след.: ' .. def.stat(rank + 1) .. "</font>"
				else "")
			else def.stat(1)
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
		then "Левый стик — движение\nПравая площадка — прицел и огонь\nКнопки справа — рывок и Гравимолот"
		elseif
			device == "gamepad"
		then "L-стик движение · R-стик прицел/огонь\nB рывок · Y Гравимолот · Start пауза\nA/X/B — выбор карты"
		else "WASD движение · МЫШЬ прицел · ЛКМ огонь\nПРОБЕЛ рывок · Q Гравимолот · V камера\nR перезарядка · 1-4 выбор улучшения"
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
		local row =
			Theme.panel({ Size = UDim2.fromOffset(316, 46), Parent = ui.squadList }, if p.ready then C.lime else C.line)
		local wbox = new("Frame", { Position = UDim2.fromOffset(4, 3), Size = UDim2.fromOffset(56, 40), Parent = row })
		Preview.weapon(wbox, p.weapon, false, { zoom = 0.6 })
		label(p.name, {
			Position = UDim2.fromOffset(66, 4),
			Size = UDim2.fromOffset(190, 20),
			FontFace = F.bodyBold,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		label(Defs.Weapons[p.weapon] and Defs.Weapons[p.weapon].short or "", {
			Position = UDim2.fromOffset(66, 24),
			Size = UDim2.fromOffset(190, 16),
			FontFace = F.title,
			TextSize = 11,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		if p.id == info.host then
			icon("crown", 20, C.gold, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0.5, 0) }).Parent =
				row
		end
		icon(
			if p.ready then "check" else "timer",
			22,
			if p.ready then C.lime else C.dim,
			{ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0) }
		).Parent =
			row
	end
	ui.ready = me and me.ready
	ui.deployLabel.Text = if ui.ready then "ГОТОВ · ОТМЕНА" else "В БОЙ"
	ui.deploy.BackgroundColor3 = if ui.ready then C.lime else C.cyan
	ui.lobbyStatus.Text = if info.countdown
		then string.format(
			"Готово %d/%d · высадка через %d",
			readyCount,
			#info.players,
			math.ceil(info.countdown)
		)
		elseif
			#info.players > 1
		then "Готовьтесь вместе или идите в бой — остальные подключатся в следующий раз"
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

local function synergyNote(me, id: string): string?
	local syn = synergyFor(me, id)
	return syn and "СИНЕРГИЯ: " .. syn.name
end

local CARD_W, CARD_GAP = 260, 18

local function buildOffer()
	local o = new("Frame", { Name = "Offer", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10, Parent = gui })
	ui.offer = o
	new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.35,
		BackgroundColor3 = C.bg,
		ZIndex = 10,
		Parent = o,
	})
	local content = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1140, 580),
		ZIndex = 10,
		Parent = o,
	})
	ui.offerScale = new("UIScale", { Parent = content })
	icon("level", 40, C.cyan, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), ZIndex = 11 }).Parent =
		content
	ui.offerTitle = label("НОВЫЙ УРОВЕНЬ", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 44),
		FontFace = F.head,
		TextSize = 40,
		TextColor3 = C.cyan,
		ZIndex = 11,
		Parent = content,
	})
	ui.offerSub = label("", {
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = F.title,
		TextSize = 14,
		TextColor3 = C.dim,
		ZIndex = 11,
		Parent = content,
	})
	ui.offerCards = {}
	for i = 1, 4 do
		local card = new("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 116),
			Size = UDim2.fromOffset(CARD_W, 360),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.04,
			Text = "",
			AutoButtonColor = false,
			Corner = 6,
			Stroke = { Color = C.line, Thickness = 2, Transparency = 0.2 },
			ZIndex = 11,
			Parent = content,
		})
		local scale = new("UIScale", { Parent = card })
		local band = new("Frame", {
			Size = UDim2.new(1, 0, 0, 150),
			BackgroundTransparency = 0.1,
			BackgroundColor3 = C.cyan,
			Corner = 6,
			ZIndex = 12,
			Parent = card,
		})
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 0.95), Parent = band })
		local badge = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(CARD_W / 2, 78),
			Size = UDim2.fromOffset(92, 92),
			Rotation = 45,
			BackgroundTransparency = 0,
			BackgroundColor3 = C.bg,
			Corner = 12,
			Stroke = { Color = C.cyan, Thickness = 3 },
			ZIndex = 13,
			Parent = card,
		})
		local iconHolder = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(CARD_W / 2, 78),
			Size = UDim2.fromOffset(64, 64),
			ZIndex = 14,
			Parent = card,
		})
		local key = label("1", {
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(28, 28),
			FontFace = F.numHeavy,
			TextSize = 18,
			TextColor3 = C.bg,
			BackgroundTransparency = 0.1,
			BackgroundColor3 = C.text,
			ZIndex = 14,
			Parent = card,
		})
		new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = key })
		local badgeTag = label("НОВОЕ", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 10),
			Size = UDim2.fromOffset(84, 22),
			FontFace = F.head,
			TextSize = 14,
			TextColor3 = C.bg,
			BackgroundTransparency = 0,
			BackgroundColor3 = C.lime,
			ZIndex = 14,
			Parent = card,
		})
		new("UICorner", { CornerRadius = UDim.new(0, 3), Parent = badgeTag })
		local name = label("", {
			Position = UDim2.fromOffset(10, 152),
			Size = UDim2.new(1, -20, 0, 28),
			FontFace = F.head,
			TextSize = 23,
			ZIndex = 12,
			Parent = card,
		})
		local pips = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 184),
			Size = UDim2.fromOffset(120, 8),
			List = {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			},
			ZIndex = 12,
			Parent = card,
		})
		local pipList = {}
		for k = 1, 3 do
			pipList[k] = new("Frame", {
				Size = UDim2.fromOffset(32, 8),
				BackgroundTransparency = 0,
				BackgroundColor3 = C.line,
				ZIndex = 12,
				Parent = pips,
			})
		end
		local stat = label("", {
			Position = UDim2.fromOffset(10, 200),
			Size = UDim2.new(1, -20, 0, 34),
			FontFace = F.num,
			TextSize = 26,
			ZIndex = 12,
			Parent = card,
		})
		local desc = label("", {
			Position = UDim2.fromOffset(16, 238),
			Size = UDim2.new(1, -32, 0, 62),
			FontFace = F.body,
			TextSize = 15,
			TextWrapped = true,
			RichText = true,
			TextColor3 = C.dim,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 12,
			Parent = card,
		})
		local tagRow = new("Frame", {
			Position = UDim2.new(0, 10, 1, -58),
			Size = UDim2.new(1, -20, 0, 22),
			List = {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
			},
			ZIndex = 12,
			Parent = card,
		})
		local tagIcon = icon("evolve", 18, C.gold, { LayoutOrder = 1, ZIndex = 12 })
		tagIcon.Parent = tagRow
		local tag = label("", {
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 22),
			FontFace = F.head,
			TextSize = 15,
			TextColor3 = C.gold,
			ZIndex = 12,
			Parent = tagRow,
		})
		local tag2 = label("", {
			Position = UDim2.new(0, 10, 1, -32),
			Size = UDim2.new(1, -20, 0, 20),
			FontFace = F.head,
			TextSize = 14,
			TextColor3 = C.violet,
			ZIndex = 12,
			Parent = card,
		})
		local banOverlay = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.red,
			BackgroundTransparency = 0.8,
			Corner = 6,
			ZIndex = 20,
			Visible = false,
			Parent = card,
		})
		icon(
			"banish",
			80,
			C.red,
			{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 21 }
		).Parent =
			banOverlay
		card.MouseEnter:Connect(function()
			offerFocus = i
			Audio.play("uiHover")
		end)
		card.Activated:Connect(function()
			Menus.pick(i)
		end)
		ui.offerCards[i] = {
			card = card,
			scale = scale,
			band = band,
			badge = badge,
			badgeStroke = badge:FindFirstChildOfClass("UIStroke"),
			iconHolder = iconHolder,
			key = key,
			badgeTag = badgeTag,
			name = name,
			pips = pipList,
			stat = stat,
			desc = desc,
			tag = tag,
			tagIcon = tagIcon,
			tagRow = tagRow,
			tag2 = tag2,
			stroke = card:FindFirstChildOfClass("UIStroke"),
			banOverlay = banOverlay,
		}
	end
	-- bottom bar: build + reroll/banish
	ui.offerBuild = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 500),
		Size = UDim2.fromOffset(330, 44),
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		},
		ZIndex = 11,
		Parent = content,
	})
	ui.rerollBtn, ui.rerollLabel = button(content, "", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.5, 190, 0, 500),
		Size = UDim2.fromOffset(150, 44),
		ZIndex = 11,
	}, C.gold, "reroll")
	ui.rerollBtn.Activated:Connect(function()
		if currentOfferId then
			send("reroll")
			Audio.play("ui", 1, 0.8)
		end
	end)
	ui.banishBtn, ui.banishLabel = button(content, "", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -190, 0, 500),
		Size = UDim2.fromOffset(150, 44),
		ZIndex = 11,
	}, C.red, "banish")
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
	ui.banishLabel.Text = (if banishMode then "ОТМЕНА" else "ИЗГНАТЬ ")
		.. (if banishMode then "" else tostring(me.banishes or 0))
	for i, c in ui.offerCards do
		local id = me.offer and me.offer.choices[i]
		local allowed = id
			and Defs.Upgrades[id]
			and not me.ranks[id]
			and not (me.evolved == "" and table.find(Defs.Evolutions[Defs.Weapons[me.weapon].evolution].keys, id))
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
	ui.offerSub.Text = if run.solo
		then "ВЫБЕРИ ОДНО · ВРЕМЯ ОСТАНОВЛЕНО"
		else string.format(
			"ВЫБЕРИ ОДНО · ОТРЯД ЖДЁТ · %d с",
			math.max(0, math.ceil(Defs.Run.ChoiceTimeoutCoop - run.pauseClock))
		)
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
	ui.offerTitle.Text = "УРОВЕНЬ "
		.. run.level
		.. (
			if me.pending > 1
				then string.format('  <font size="20" color="#7E95A6">ЕЩЁ +%d</font>', me.pending - 1)
				else ""
		)
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
			local isKey = run ~= nil
				and run.runEvolution == true
				and me.evolved == ""
				and table.find(evo.keys, id) ~= nil
			-- Style chip (DD-017) unless the card is a legacy evolution key.
			local style = Defs.Upgrades[id] and Defs.Styles[Defs.Upgrades[id].style]
			c.tag.Text = if isKey then "КЛЮЧ ЭВОЛЮЦИИ" elseif style then style.name else ""
			c.tag.TextColor3 = if isKey or not style then C.gold else style.color
			c.tagIcon.Visible = isKey
			c.tag2.Text = synergyNote(me, id) or ""
			local syn = synergyFor(me, id)
			if syn then
				c.desc.Text = text .. '\n<font color="#C9A2FF">+ ' .. syn.text .. "</font>"
			end
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
			local slot = new("Frame", {
				Size = UDim2.fromOffset(44, 44),
				BackgroundColor3 = C.panel2,
				BackgroundTransparency = 0.1,
				Corner = 4,
				Stroke = { Color = def.color, Transparency = 0.3 },
				ZIndex = 11,
				Parent = ui.offerBuild,
			})
			icon(
				def.icon,
				30,
				def.color,
				{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), ZIndex = 12 },
				C.panel2
			).Parent =
				slot
			label(tostring(me.ranks[id]), {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -2, 1, 0),
				Size = UDim2.fromOffset(14, 14),
				FontFace = F.num,
				TextSize = 13,
				TextColor3 = def.color,
				ZIndex = 12,
				Parent = slot,
			})
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
	ui.splashTag = label("ОРУЖИЕ ЭВОЛЮЦИОНИРОВАЛО", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.43),
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = F.title,
		TextSize = 16,
		TextColor3 = C.text,
		ZIndex = 31,
		Parent = s,
	})
	ui.splashTitle = label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.new(1, 0, 0, 80),
		FontFace = F.head,
		TextSize = 72,
		TextColor3 = C.gold,
		TextStrokeTransparency = 0.3,
		ZIndex = 31,
		Parent = s,
	})
	ui.splashSub = label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.58),
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
		ui.splashEvolving = false
	end)
end

function Menus.whiteFlash(amount: number)
	ui.splash.Visible = true
	if not ui.splashEvolving then
		-- A plain flash: hide the evolution splash captions that share this layer.
		ui.splashTag.TextTransparency = 1
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

-- Results ---------------------------------------------------------------------------------------------
local function buildResults()
	local r =
		new("Frame", { Name = "Results", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, Parent = gui })
	ui.results = r
	new(
		"Frame",
		{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.2, BackgroundColor3 = C.bg, ZIndex = 20, Parent = r }
	)
	local content = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1040, 660),
		ZIndex = 20,
		Parent = r,
	})
	ui.resultsScale = new("UIScale", { Parent = content })
	ui.resIcon = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(56, 56),
		ZIndex = 21,
		Parent = content,
	})
	ui.resTitle = label("", {
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 64),
		FontFace = F.head,
		TextSize = 60,
		ZIndex = 21,
		Parent = content,
	})
	ui.resReason = label("", {
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = F.title,
		TextSize = 15,
		TextColor3 = C.dim,
		ZIndex = 21,
		Parent = content,
	})
	ui.resStats = new("Frame", {
		Position = UDim2.fromOffset(0, 156),
		Size = UDim2.new(1, 0, 0, 96),
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 12),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		},
		ZIndex = 21,
		Parent = content,
	})
	ui.resReward = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 264),
		Size = UDim2.fromOffset(700, 74),
		ZIndex = 21,
		Parent = content,
	}, C.gold)
	ui.resProgress = label("", {
		Position = UDim2.fromOffset(0, 342),
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = F.head,
		TextSize = 16,
		TextColor3 = C.cyan,
		ZIndex = 21,
		Parent = content,
	})
	ui.resPlayers = new("Frame", {
		Position = UDim2.fromOffset(0, 370),
		Size = UDim2.new(1, 0, 0, 200),
		List = { Padding = UDim.new(0, 8) },
		ZIndex = 21,
		Parent = content,
	})
	ui.resButton, ui.resButtonLabel = button(content, "В ЛОББИ", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(360, 60),
		ZIndex = 22,
	}, C.cyan, "play")
	ui.resButtonLabel.TextSize = 24
	ui.resButton.Activated:Connect(function()
		send("continue")
		Audio.play("ui")
		ui.resButtonLabel.Text = "ЖДЁМ ОТРЯД"
	end)
end

local function statTile(parent, iconName: string, title: string, value: string, color: Color3)
	local t = Theme.panel({ Size = UDim2.fromOffset(160, 92), ZIndex = 21, Parent = parent }, color)
	icon(iconName, 24, color, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), ZIndex = 22 }).Parent =
		t
	label(value, {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 36),
		FontFace = F.num,
		TextSize = 34,
		TextColor3 = color,
		ZIndex = 22,
		Parent = t,
	})
	label(title, {
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 14),
		FontFace = F.title,
		TextSize = 10,
		TextColor3 = C.dim,
		ZIndex = 22,
		Parent = t,
	})
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
	icon(if result.victory then "crown" else "skull", 56, if result.victory then C.gold else C.red, { ZIndex = 22 }).Parent =
		ui.resIcon
	ui.resTitle.Text = if result.victory then "ЗОНА ЗАЧИЩЕНА" else "ПОРАЖЕНИЕ"
	ui.resTitle.TextColor3 = if result.victory then C.gold else C.red
	local op = Ops.get(result.op)
	ui.resReason.Text = result.reason
		.. "  ·  "
		.. op.code
		.. " "
		.. op.name
		.. (if (result.threat or 1) > 1 then "  ·  УГРОЗА " .. result.threat else "")
	-- Main permanent progress: the weapon's mastery, counted even on defeat.
	local pr = reward and reward.progress
	if pr then
		local w = Defs.Weapons[pr.weapon]
		ui.resProgress.Text = string.format(
			"+%s УБИЙСТВ · %s M%d%s",
			Theme.commas(pr.added),
			w and w.short or "",
			pr.rank,
			if pr.need then string.format("  (%s / %s)", Theme.commas(pr.into), Theme.commas(pr.need)) else "  МАКС"
		)
	else
		ui.resProgress.Text = ""
	end
	if result.chapterEnd and result.victory then
		ui.resProgress.Text = "ГЛАВА 1 ЗАВЕРШЕНА  ·  " .. ui.resProgress.Text
	end
	-- Build style of this run (DD-017): the style with the most card ranks.
	for _, p in result.players do
		if p.id == id and p.upgrades and #p.upgrades > 0 then
			local sum = {}
			for _, u in p.upgrades do
				local def = Defs.Upgrades[u[1]]
				if def then
					sum[def.style] = (sum[def.style] or 0) + u[2]
				end
			end
			local best, bv = nil, 0
			for _, st in Defs.StyleOrder do
				if (sum[st] or 0) > bv then
					best, bv = st, sum[st]
				end
			end
			if best then
				local s = Defs.Styles[best]
				ui.resProgress.Text ..= string.format(
					'  ·  <font color="#%s">СТИЛЬ: %s</font>',
					s.color:ToHex(),
					s.name
				)
			end
		end
	end
	clear(ui.resStats)
	statTile(ui.resStats, "timer", "ВРЕМЯ", Theme.fmtTime(result.time), C.text)
	statTile(ui.resStats, "level", "УРОВЕНЬ", tostring(result.level), C.cyan)
	statTile(ui.resStats, "skull", "УБИЙСТВ", Theme.commas(result.kills), C.orange)
	local best = 0
	for _, p in result.players do
		best = math.max(best, p.bestCombo)
	end
	statTile(ui.resStats, "boom", "ЛУЧШАЯ СЕРИЯ", "×" .. best, C.gold)
	if result.reactor then
		statTile(
			ui.resStats,
			"reactor",
			"РЕАКТОР",
			math.floor(result.reactor * 100 + 0.5) .. "%",
			if result.reactor > 0.5 then C.cyan elseif result.reactor > 0 then C.orange else C.red
		)
	else
		statTile(
			ui.resStats,
			"hive",
			"УЛЕЙ",
			if result.hive == "cleared" then "ЗАЧИЩЕН" elseif result.hive == "failed" then "УШЁЛ" else "—",
			C.lime
		)
	end
	-- reward strip
	clear(ui.resReward)
	local row = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		List = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 14),
		},
		ZIndex = 22,
		Parent = ui.resReward,
	})
	if reward then
		for i, l in reward.lines do
			local cell = new("Frame", {
				LayoutOrder = i,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 40),
				List = {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 4),
				},
				ZIndex = 22,
				Parent = row,
			})
			icon(l[1], 22, C.dim, { LayoutOrder = 1, ZIndex = 22 }).Parent = cell
			label("+" .. l[2], {
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 40),
				FontFace = F.num,
				TextSize = 20,
				TextColor3 = C.text,
				ZIndex = 22,
				Parent = cell,
			})
		end
		if reward.mult and reward.mult > 1.001 then
			label(string.format("×%.2f", reward.mult), {
				LayoutOrder = 50,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 40),
				FontFace = F.num,
				TextSize = 20,
				TextColor3 = C.red,
				ZIndex = 22,
				Parent = row,
			})
		end
		label("=", {
			LayoutOrder = 60,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
			FontFace = F.num,
			TextSize = 22,
			TextColor3 = C.dim,
			ZIndex = 22,
			Parent = row,
		})
		local total = scrapTag(row, reward.total, { LayoutOrder = 70, ZIndex = 22 })
		total.ZIndex = 22
		if reward.grant and reward.grant > 0 then
			label("+" .. reward.grant .. " ГРАНТ", {
				LayoutOrder = 75,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 40),
				FontFace = F.head,
				TextSize = 16,
				TextColor3 = C.gold,
				ZIndex = 22,
				Parent = row,
			})
		end
		-- One line per major unlock, most important first; at most three fit the strip.
		local PRIORITY = { op = 1, component = 2, s01 = 3, mastery = 4, threat = 5, research = 6 }
		local list = table.clone(reward.unlocked or {})
		table.sort(list, function(a, b)
			return (PRIORITY[a[1]] or 9) < (PRIORITY[b[1]] or 9)
		end)
		for k, u in list do
			if k > 3 then
				break
			end
			local cell = new("Frame", {
				LayoutOrder = 80 + k,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 40),
				List = {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 4),
				},
				ZIndex = 22,
				Parent = row,
			})
			local kind = u[1]
			local text = if kind == "op"
				then "ОТКРЫТО: " .. u[2] .. " · " .. Ops.get(u[2]).name
				elseif kind == "component" then (Defs.Components[u[2]] and Defs.Components[u[2]].name or u[2])
					.. " — В АРСЕНАЛЕ"
				elseif kind == "s01" then "ГРАВИМОЛОТ S01 НАВСЕГДА"
				elseif kind == "mastery" then (Defs.Weapons[u[2]] and Defs.Weapons[u[2]].short or u[2])
					.. " · M"
					.. u[3]
				elseif kind == "research" then "ИЗУЧЕН: "
					.. (Defs.Enemies[u[2]] and Defs.Enemies[u[2]].name or u[2])
					.. " "
					.. string.rep("I", u[3])
				else "УГРОЗА " .. u[2] .. " ОТКРЫТА"
			local iconName = if kind == "op"
				then "pin"
				elseif kind == "component" then "core"
				elseif kind == "s01" then "hammer"
				elseif kind == "mastery" then "level"
				elseif kind == "research" then "eye"
				else "threat"
			icon(iconName, 24, if kind == "component" then C.gold else C.lime, { LayoutOrder = 1, ZIndex = 22 }).Parent =
				cell
			label(text, {
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 40),
				FontFace = F.head,
				TextSize = 16,
				TextColor3 = C.lime,
				ZIndex = 22,
				Parent = cell,
			})
		end
	else
		label("Подсчёт награды…", {
			Size = UDim2.fromScale(1, 1),
			FontFace = F.title,
			TextSize = 14,
			TextColor3 = C.dim,
			ZIndex = 22,
			Parent = row,
		})
	end
	if not first then
		return
	end
	clear(ui.resPlayers)
	for _, p in result.players do
		local prow = Theme.panel(
			{ Size = UDim2.new(1, 0, 0, 64), ZIndex = 21, Parent = ui.resPlayers },
			if p.id == id then C.cyan else C.line
		)
		local wbox = new(
			"Frame",
			{ Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(84, 56), ZIndex = 22, Parent = prow }
		)
		Preview.weapon(wbox, p.weapon, p.evolved ~= "", { zoom = 0.6 }).ZIndex = 22
		label(p.name, {
			Position = UDim2.fromOffset(98, 6),
			Size = UDim2.fromOffset(220, 24),
			FontFace = F.bodyBold,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 22,
			Parent = prow,
		})
		local w = Defs.Weapons[p.weapon]
		label(if p.evolved ~= "" then Defs.Evolutions[p.evolved].name else w.name, {
			Position = UDim2.fromOffset(98, 32),
			Size = UDim2.fromOffset(220, 20),
			FontFace = F.head,
			TextSize = 14,
			TextColor3 = if p.evolved ~= "" then C.gold else C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 22,
			Parent = prow,
		})
		local ups = new("Frame", {
			Position = UDim2.fromOffset(330, 10),
			Size = UDim2.new(1, -560, 0, 44),
			List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) },
			ZIndex = 22,
			Parent = prow,
		})
		for _, u in p.upgrades do
			local def = Defs.Upgrades[u[1]]
			local slot = new("Frame", {
				Size = UDim2.fromOffset(44, 44),
				BackgroundColor3 = C.panel2,
				BackgroundTransparency = 0.1,
				Corner = 4,
				ZIndex = 22,
				Parent = ups,
			})
			icon(
				def.icon,
				30,
				def.color,
				{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), ZIndex = 23 },
				C.panel2
			).Parent =
				slot
			label(tostring(u[2]), {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -2, 1, 0),
				Size = UDim2.fromOffset(14, 14),
				FontFace = F.num,
				TextSize = 13,
				TextColor3 = def.color,
				ZIndex = 23,
				Parent = slot,
			})
		end
		local stats = new("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 6),
			Size = UDim2.fromOffset(210, 52),
			ZIndex = 22,
			Parent = prow,
		})
		icon("skull", 18, C.orange, { Position = UDim2.fromOffset(0, 4), ZIndex = 23 }).Parent = stats
		label(Theme.commas(p.kills), {
			Position = UDim2.fromOffset(24, 0),
			Size = UDim2.fromOffset(180, 24),
			FontFace = F.num,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
			Parent = stats,
		})
		icon("burst", 18, C.red, { Position = UDim2.fromOffset(0, 30), ZIndex = 23 }).Parent = stats
		label(Theme.commas(p.damage), {
			Position = UDim2.fromOffset(24, 26),
			Size = UDim2.fromOffset(180, 24),
			FontFace = F.num,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
			Parent = stats,
		})
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
	ui.note = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(500, 46),
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	}, C.gold)
	ui.noteText = label("", {
		Size = UDim2.fromScale(1, 1),
		FontFace = F.head,
		TextSize = 18,
		TextColor3 = C.gold,
		ZIndex = 6,
		Parent = ui.note,
	})
end

function Menus.note(text: string?)
	ui.note.Visible = text ~= nil
	if text then
		ui.noteText.Text = text
	end
end

function Menus.init(playerGui: PlayerGui, sender)
	send = sender
	gui = new("ScreenGui", {
		Name = "SwarmMenus",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
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
