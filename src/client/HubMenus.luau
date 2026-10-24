--!nonstrict
-- Camp windows (DD-053): the squad board, the outposts of the hunters on this server, a hunter's card,
-- the banner while visiting someone's outpost, and the camp toasts (invites, likes, launch errors).
-- Everything here reads the camp state the server sends 4×/s (squads + hunters' showcases).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Meta = require(Shared:WaitForChild("Meta"))
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local Audio = require(script.Parent.Audio)

local new, C, F = Theme.new, Theme.C, Theme.F
local label, tween = Theme.label, Theme.tween

local HubMenus = {}

local H -- helpers from Menus: send, modal, clear, gui
local acts -- visit(uid), home()
local ui = {}
local hub = nil
local myId = 0
local visiting = nil -- user id of the outpost being visited
local cardUid = nil

local function hunter(uid: number)
	for _, h in (hub and hub.hunters) or {} do
		if h.id == uid then
			return h
		end
	end
	return nil
end

local function mySquad()
	for _, sq in (hub and hub.squads) or {} do
		for _, p in sq.players do
			if p.id == myId then
				return sq
			end
		end
	end
	return nil
end

local function row(parent, order: number, h: number)
	return new("Frame", {
		Size = UDim2.new(1, -8, 0, h),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.25,
		Corner = 14,
		Stroke = { Color = C.white, Transparency = 0.9 },
		LayoutOrder = order,
		ZIndex = 43,
		Parent = parent,
	})
end

local function disc(parent, iconName: string, color: Color3, size: number, pos: UDim2)
	local d = Icons.disc(iconName, size, color, 44)
	d.Position = pos
	d.Parent = parent
	return d
end

local function button(parent, text: string, kind: string?, w: number, onClick)
	local b, bl = Theme.button(
		text,
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(w, 40),
			TextSize = 12,
			ZIndex = 44,
		},
		kind
	)
	b.Parent = parent
	bl.ZIndex = 45
	b.Activated:Connect(function()
		Audio.play("ui")
		onClick()
	end)
	return b, bl
end

local function scrollList(panel, y: number)
	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(28, y),
		Size = UDim2.new(1, -56, 1, -(y + 24)),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
		ZIndex = 42,
		Parent = panel,
	})
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	return list
end

-- Board ------------------------------------------------------------------------------------------------------
local function buildBoard()
	local m = H.modal("SquadBoard", 760, 560, "ДОСКА ОТРЯДОВ", C.lime)
	ui.board = m
	ui.boardSub = label(
		"Вступай в открытый отряд одной кнопкой или собери свой.",
		{
			Position = UDim2.fromOffset(28, 62),
			Size = UDim2.new(1, -56, 0, 20),
			FontFace = F.body,
			TextSize = 14,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 42,
			Parent = m.panel,
		}
	)
	local bar = new(
		"Frame",
		{
			Position = UDim2.fromOffset(28, 92),
			Size = UDim2.new(1, -56, 0, 44),
			ZIndex = 42,
			Parent = m.panel,
			List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) },
		}
	)
	local match, _ = Theme.button(
		"ПОДОБРАТЬ ОТРЯД",
		{ Size = UDim2.fromOffset(230, 44), TextSize = 13, ZIndex = 43, LayoutOrder = 1 },
		"primary"
	)
	match.Parent = bar
	match.Label.ZIndex = 44
	match.Activated:Connect(function()
		Audio.play("level", 0.6, 1.2)
		H.send("match")
	end)
	ui.recruit, ui.recruitLabel = Theme.button(
		"ОТКРЫТЬ НАБОР",
		{ Size = UDim2.fromOffset(220, 44), TextSize = 13, ZIndex = 43, LayoutOrder = 2 }
	)
	ui.recruit.Parent = bar
	ui.recruitLabel.ZIndex = 44
	ui.recruit.Activated:Connect(function()
		local sq = mySquad()
		Audio.play("ui")
		H.send("recruit", not (sq and sq.open))
	end)
	ui.leave, ui.leaveLabel = Theme.button(
		"ПОКИНУТЬ ОТРЯД",
		{ Size = UDim2.fromOffset(200, 44), TextSize = 13, ZIndex = 43, LayoutOrder = 3 },
		"danger"
	)
	ui.leave.Parent = bar
	ui.leaveLabel.ZIndex = 44
	ui.leave.Activated:Connect(function()
		Audio.play("ui", 0.8, 0.9)
		H.send("leave")
	end)
	ui.boardList = scrollList(m.panel, 150)
end

function HubMenus.refreshBoard()
	if not ui.board or not ui.board.shade.Visible then
		return
	end
	local mine = mySquad()
	local isHost = mine ~= nil and mine.host == myId
	ui.recruit.Visible = isHost
	ui.recruitLabel.Text = if mine and mine.open then "ЗАКРЫТЬ НАБОР" else "ОТКРЫТЬ НАБОР"
	ui.leave.Visible = mine ~= nil and #mine.players > 1
	local key = ""
	for _, sq in (hub and hub.squads) or {} do
		key ..= string.format(
			"%d:%d:%s:%s:%s:%s|",
			sq.id,
			#sq.players,
			tostring(sq.open),
			sq.title,
			tostring(sq.launching),
			tostring(sq.countdown and math.ceil(sq.countdown))
		)
	end
	key ..= tostring(mine and mine.id)
	if key == ui.boardKey then
		return
	end
	ui.boardKey = key
	H.clear(ui.boardList)
	local order = 0
	for _, sq in (hub and hub.squads) or {} do
		local listed = (sq.open and not sq.launching and #sq.players < 4) or sq == mine
		if listed then
			order += 1
			local r = row(ui.boardList, if sq == mine then 0 else order, 76)
			if sq == mine then
				r.BackgroundColor3 = C.ink:Lerp(C.lime, 0.12)
			end
			local hostName = ""
			for _, p in sq.players do
				if p.id == sq.host then
					hostName = p.name
				end
			end
			disc(
				r,
				if sq.mode == "siege" then "shield" elseif sq.mode == "raid" then "swords" else "skull",
				if sq.mode == "siege" then C.cyan elseif sq.mode == "raid" then C.red else C.lime,
				48,
				UDim2.fromOffset(12, 14)
			)
			label(
				sq.title,
				{
					Position = UDim2.fromOffset(72, 12),
					Size = UDim2.new(1, -250, 0, 22),
					FontFace = F.bodyHeavy,
					TextSize = 16,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 44,
					Parent = r,
				}
			)
			local need = 4 - #sq.players
			local sub = string.format(
				"%s  ·  %d/4%s",
				hostName,
				#sq.players,
				if need > 0 and sq.open then string.format("  ·  нужно ещё %d", need) else ""
			)
			if sq.countdown then
				sub ..= string.format("  ·  вылет через %d", math.ceil(sq.countdown))
			end
			label(
				sub,
				{
					Position = UDim2.fromOffset(72, 40),
					Size = UDim2.new(1, -250, 0, 18),
					FontFace = F.body,
					TextSize = 13,
					TextColor3 = C.dim,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 44,
					Parent = r,
				}
			)
			if sq == mine then
				label(
					if sq.open then "ТВОЙ ОТРЯД · НАБОР ОТКРЫТ" else "ТВОЙ ОТРЯД",
					{
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -16, 0.5, 0),
						Size = UDim2.fromOffset(200, 20),
						FontFace = F.head,
						TextSize = 11,
						TextColor3 = C.lime,
						TextXAlignment = Enum.TextXAlignment.Right,
						ZIndex = 44,
						Parent = r,
					}
				)
			else
				button(r, "ВСТУПИТЬ", "primary", 150, function()
					H.send("join", sq.id)
				end)
			end
		end
	end
	if order == 0 then
		label(
			"Открытых отрядов пока нет. Нажми «Подобрать отряд» — твой набор появится здесь для других.",
			{
				Size = UDim2.new(1, -8, 0, 50),
				FontFace = F.body,
				TextSize = 14,
				TextColor3 = C.dim,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 99,
				ZIndex = 43,
				Parent = ui.boardList,
			}
		)
	end
end

function HubMenus.showBoard()
	ui.boardKey = nil
	ui.board.show()
	HubMenus.refreshBoard()
end

-- Outposts terminal ---------------------------------------------------------------------------------------
local function buildOutposts()
	local m = H.modal("CampOutposts", 760, 560, "УБЕЖИЩА ВЫЖИВШИХ", C.cyan)
	ui.outposts = m
	label(
		"Убежища всех, кто сейчас в поселении. Заглянуть — значит увидеть его дом у себя на экране.",
		{
			Position = UDim2.fromOffset(28, 62),
			Size = UDim2.new(1, -56, 0, 20),
			FontFace = F.body,
			TextSize = 14,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 42,
			Parent = m.panel,
		}
	)
	ui.outpostList = scrollList(m.panel, 96)
end

function HubMenus.refreshOutposts()
	if not ui.outposts or not ui.outposts.shade.Visible then
		return
	end
	local list = table.clone((hub and hub.hunters) or {})
	table.sort(list, function(a, b)
		if a.power ~= b.power then
			return a.power > b.power
		end
		return a.id < b.id
	end)
	local key = ""
	for _, h in list do
		key ..= h.id .. ":" .. h.power .. ":" .. h.likes .. "|"
	end
	if key == ui.outKey then
		return
	end
	ui.outKey = key
	H.clear(ui.outpostList)
	for i, h in list do
		local r = row(ui.outpostList, i, 72)
		local built = 0
		for _ in h.slots do
			built += 1
		end
		disc(r, h.titleIcon, C.cyan, 46, UDim2.fromOffset(12, 13))
		label(
			h.name .. (if h.id == myId then "  (ты)" else ""),
			{
				Position = UDim2.fromOffset(70, 12),
				Size = UDim2.new(1, -330, 0, 22),
				FontFace = F.bodyHeavy,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 44,
				Parent = r,
			}
		)
		label(
			string.format(
				"Мощь обороны %d  ·  построек %d/%d  ·  осада %s  ·  ♥ %d",
				h.power,
				built,
				Meta.SocketCount,
				if h.siege > 0 then tostring(h.siege) else "—",
				h.likes
			),
			{
				Position = UDim2.fromOffset(70, 38),
				Size = UDim2.new(1, -330, 0, 18),
				FontFace = F.body,
				TextSize = 12,
				TextColor3 = C.dim,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 44,
				Parent = r,
			}
		)
		local b = button(r, "ПОСЕТИТЬ", "primary", 130, function()
			ui.outposts.hide()
			acts.visit(h.id)
		end)
		b.Visible = h.id ~= myId and built > 0
		local c = button(r, "КАРТОЧКА", nil, 120, function()
			HubMenus.showCard(h.id)
		end)
		c.Position = UDim2.new(1, -150, 0.5, 0)
	end
end

function HubMenus.showOutposts()
	ui.outKey = nil
	ui.outposts.show()
	HubMenus.refreshOutposts()
end

-- Hunter card -----------------------------------------------------------------------------------------------
local function buildCard()
	local m = H.modal("HunterCard", 560, 480, "ВЫЖИВШИЙ", C.gold)
	ui.card = m
	ui.cardBody = new(
		"Frame",
		{ Position = UDim2.fromOffset(28, 66), Size = UDim2.new(1, -56, 1, -150), ZIndex = 42, Parent = m.panel }
	)
	local bar = new(
		"Frame",
		{
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 28, 1, -22),
			Size = UDim2.new(1, -56, 0, 46),
			ZIndex = 42,
			Parent = m.panel,
			List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) },
		}
	)
	ui.cardVisit, ui.cardVisitLabel = Theme.button(
		"ОСМОТРЕТЬ БАЗУ",
		{ Size = UDim2.fromOffset(240, 46), TextSize = 13, ZIndex = 43, LayoutOrder = 1 },
		"primary"
	)
	ui.cardVisit.Parent = bar
	ui.cardVisitLabel.ZIndex = 44
	ui.cardVisit.Activated:Connect(function()
		if cardUid then
			ui.card.hide()
			acts.visit(cardUid)
		end
	end)
	ui.cardInvite, ui.cardInviteLabel = Theme.button(
		"ПОЗВАТЬ В ОТРЯД",
		{ Size = UDim2.fromOffset(240, 46), TextSize = 13, ZIndex = 43, LayoutOrder = 2 }
	)
	ui.cardInvite.Parent = bar
	ui.cardInviteLabel.ZIndex = 44
	ui.cardInvite.Activated:Connect(function()
		if cardUid then
			H.send("invite", cardUid)
			Audio.play("level", 0.5, 1.3)
			ui.cardInviteLabel.Text = "ПРИГЛАШЕНИЕ ОТПРАВЛЕНО"
		end
	end)
end

function HubMenus.showCard(uid: number)
	local h = hunter(uid)
	if not h then
		return
	end
	cardUid = uid
	H.clear(ui.cardBody)
	local b = ui.cardBody
	disc(b, h.titleIcon, C.gold, 72, UDim2.fromOffset(0, 0))
	label(
		h.name,
		{
			Position = UDim2.fromOffset(88, 0),
			Size = UDim2.new(1, -88, 0, 34),
			FontFace = F.display,
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 43,
			Parent = b,
		}
	)
	label(
		h.title,
		{
			Position = UDim2.fromOffset(88, 36),
			Size = UDim2.new(1, -88, 0, 22),
			FontFace = F.head,
			TextSize = 15,
			TextColor3 = C.gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
			Parent = b,
		}
	)
	local w = Defs.Weapons[h.weapon]
	local form = h.form and Defs.Evolutions[h.form]
	local wr = row(b, 0, 64)
	wr.Position = UDim2.fromOffset(0, 88)
	wr.Size = UDim2.new(1, 0, 0, 64)
	disc(wr, "crosshair", C.cyan, 44, UDim2.fromOffset(10, 10))
	label(
		if form then form.name else (w and w.name or "Оружие"),
		{
			Position = UDim2.fromOffset(64, 10),
			Size = UDim2.new(1, -80, 0, 22),
			FontFace = F.bodyHeavy,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 44,
			Parent = wr,
		}
	)
	label(
		string.format(
			"Любимое оружие  ·  мастерство M%d%s",
			h.mastery,
			if form then "  ·  форма" else ""
		),
		{
			Position = UDim2.fromOffset(64, 34),
			Size = UDim2.new(1, -80, 0, 18),
			FontFace = F.body,
			TextSize = 13,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 44,
			Parent = wr,
		}
	)
	local stats = new(
		"Frame",
		{
			Position = UDim2.fromOffset(0, 164),
			Size = UDim2.new(1, 0, 0, 64),
			ZIndex = 43,
			Parent = b,
			List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) },
		}
	)
	for i, st in
		{
			{ "Побед", tostring(h.wins) },
			{ "Осада", if h.siege > 0 then tostring(h.siege) else "—" },
			{ "Оборона", tostring(h.power) },
			{ "♥", tostring(h.likes) },
		}
	do
		local t = Theme.panel({
			Size = UDim2.fromOffset(112, 64),
			CornerRadius = 14,
			LayoutOrder = i,
			ZIndex = 43,
			Parent = stats,
		})
		label(
			st[2],
			{
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.new(1, 0, 0, 28),
				FontFace = F.display,
				TextSize = 22,
				ZIndex = 44,
				Parent = t,
			}
		)
		label(
			st[1],
			{
				Position = UDim2.fromOffset(0, 38),
				Size = UDim2.new(1, 0, 0, 16),
				FontFace = F.head,
				TextSize = 10,
				TextColor3 = C.dim,
				ZIndex = 44,
				Parent = t,
			}
		)
	end
	local tro = new(
		"Frame",
		{
			Position = UDim2.fromOffset(0, 240),
			Size = UDim2.new(1, 0, 0, 36),
			ZIndex = 43,
			Parent = b,
			List = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) },
		}
	)
	if #h.trophies == 0 then
		label(
			if h.newbie
				then "Новичок в пустоши — позови его с собой, вместе проще."
				else "Трофеев пока нет.",
			{
				Size = UDim2.new(1, 0, 1, 0),
				FontFace = F.body,
				TextSize = 13,
				TextColor3 = C.dim,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 44,
				Parent = tro,
			}
		)
	end
	for i, t in h.trophies do
		local chip = new(
			"Frame",
			{
				Size = UDim2.fromOffset(0, 32),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = C.ink,
				BackgroundTransparency = 0.2,
				Corner = UDim.new(1, 0),
				Stroke = { Color = C.gold, Transparency = 0.5 },
				LayoutOrder = i,
				ZIndex = 44,
				Parent = tro,
				List = {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 6),
				},
			}
		)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 12), Parent = chip })
		local ic = Icons.new(t[1], 18, C.gold)
		ic.ZIndex = 45
		ic.Parent = chip
		label(
			t[2],
			{
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 32),
				FontFace = F.bodyBold,
				TextSize = 13,
				ZIndex = 45,
				Parent = chip,
			}
		)
	end
	local built = 0
	for _ in h.slots do
		built += 1
	end
	ui.cardVisit.Visible = uid ~= myId and built > 0
	ui.cardInvite.Visible = uid ~= myId
	ui.cardInviteLabel.Text = "ПОЗВАТЬ В ОТРЯД"
	ui.card.show()
end

-- Visit banner -------------------------------------------------------------------------------------------------
local function buildBanner()
	local b = Theme.panel(
		{
			Name = "VisitBanner",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 14),
			Size = UDim2.fromOffset(620, 64),
			CornerRadius = 32,
			Visible = false,
			ZIndex = 30,
			Parent = H.gui,
		},
		C.cyan
	)
	ui.banner = b
	ui.bannerTitle = label(
		"",
		{
			Position = UDim2.fromOffset(26, 8),
			Size = UDim2.new(1, -330, 0, 26),
			FontFace = F.display,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 31,
			Parent = b,
		}
	)
	ui.bannerSub = label(
		"",
		{
			Position = UDim2.fromOffset(26, 34),
			Size = UDim2.new(1, -330, 0, 18),
			FontFace = F.body,
			TextSize = 12,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 31,
			Parent = b,
		}
	)
	ui.like, ui.likeLabel = Theme.button(
		"♥ УЮТНОЕ УБЕЖИЩЕ",
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -150, 0.5, 0),
			Size = UDim2.fromOffset(170, 42),
			TextSize = 11,
			ZIndex = 31,
		},
		"primary"
	)
	ui.like.Parent = b
	ui.likeLabel.ZIndex = 32
	ui.like.Activated:Connect(function()
		if visiting then
			H.send("like", visiting)
			Audio.play("level", 0.6, 1.5)
			ui.likeLabel.Text = "♥ ОЦЕНЕНО"
			ui.liked = visiting
		end
	end)
	local back, bl = Theme.button(
		"ДОМОЙ",
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(126, 42),
			TextSize = 12,
			ZIndex = 31,
		}
	)
	back.Parent = b
	bl.ZIndex = 32
	back.Activated:Connect(function()
		Audio.play("ui", 0.8, 0.9)
		acts.home()
	end)
end

function HubMenus.setVisiting(uid: number?)
	visiting = uid
	ui.banner.Visible = uid ~= nil
	if uid then
		local h = hunter(uid)
		ui.bannerTitle.Text = "УБЕЖИЩЕ " .. (if h then h.name:upper() else "") .. " · ВИД У ТЕБЯ"
		ui.bannerSub.Text = if h
			then string.format("%s  ·  мощь обороны %d  ·  ♥ %d", h.title, h.power, h.likes)
			else ""
		ui.likeLabel.Text = if ui.liked == uid then "♥ ОЦЕНЕНО" else "♥ УЮТНОЕ УБЕЖИЩЕ"
	end
end

-- Toasts -----------------------------------------------------------------------------------------------------
local function buildToast()
	local t = Theme.panel(
		{
			Name = "CampToast",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 92),
			Size = UDim2.fromOffset(560, 64),
			CornerRadius = 20,
			Visible = false,
			ZIndex = 35,
			Parent = H.gui,
		},
		C.lime
	)
	ui.toast = t
	ui.toastText = label(
		"",
		{
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -200, 1, 0),
			FontFace = F.bodyBold,
			TextSize = 15,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 36,
			Parent = t,
		}
	)
	ui.toastBtn, ui.toastBtnLabel = Theme.button(
		"",
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(160, 42),
			TextSize = 12,
			ZIndex = 36,
		},
		"primary"
	)
	ui.toastBtn.Parent = t
	ui.toastBtnLabel.ZIndex = 37
	ui.toastBtn.Activated:Connect(function()
		if ui.toastAction then
			ui.toastAction()
		end
		t.Visible = false
	end)
end

function HubMenus.toast(text: string, color: Color3?, btn: string?, action)
	ui.toastSeq = (ui.toastSeq or 0) + 1
	local seq = ui.toastSeq
	ui.toast.Visible = true
	ui.toast:FindFirstChildOfClass("UIStroke").Color = color or C.lime
	ui.toastText.Text = text
	ui.toastText.Size = UDim2.new(1, if btn then -200 else -44, 1, 0)
	ui.toastBtn.Visible = btn ~= nil
	ui.toastBtnLabel.Text = btn or ""
	ui.toastAction = action
	ui.toast.Position = UDim2.new(0.5, 0, 0, 70)
	tween(ui.toast, 0.3, { Position = UDim2.new(0.5, 0, 0, 92) }, Enum.EasingStyle.Back)
	task.delay(if btn then 12 else 5, function()
		if ui.toastSeq == seq then
			ui.toast.Visible = false
		end
	end)
end

function HubMenus.onSocial(kind: string, data)
	if kind == "invite" and type(data) == "table" then
		Audio.play("level", 0.7, 1.2)
		HubMenus.toast(
			string.format("%s зовёт в отряд: %s", tostring(data.from), tostring(data.title)),
			C.lime,
			"ВСТУПИТЬ",
			function()
				H.send("join", data.squad)
			end
		)
	elseif kind == "joined" then
		Audio.play("level", 0.5, 1.4)
		HubMenus.toast(tostring(data) .. " в твоём отряде", C.lime)
	elseif kind == "liked" then
		Audio.play("orb", 0.8, 1.2)
		HubMenus.toast(tostring(data) .. " оценил твоё убежище ♥", C.pink)
	elseif kind == "match" then
		HubMenus.toast(
			if data == "joined"
				then "Нашёлся отряд — ты в деле"
				else "Свободных отрядов нет — твой набор открыт на доске",
			C.lime
		)
	elseif kind == "launch" then
		HubMenus.toast("Выходим: " .. tostring(data) .. "…", C.lime)
	elseif kind == "error" then
		Audio.play("warn", 0.5)
		HubMenus.toast(tostring(data), C.red)
	end
end

-- API ----------------------------------------------------------------------------------------------------------
function HubMenus.init(helpers, actions)
	H = helpers
	acts = actions
	buildBoard()
	buildOutposts()
	buildCard()
	buildBanner()
	buildToast()
end

function HubMenus.setHub(info, id: number)
	hub = info
	myId = id
	HubMenus.refreshBoard()
	HubMenus.refreshOutposts()
	if visiting then
		HubMenus.setVisiting(visiting)
	end
end

function HubMenus.hunter(uid: number)
	return hunter(uid)
end

function HubMenus.mySquad()
	return mySquad()
end

function HubMenus.anyVisible(): boolean
	for _, m in { ui.board, ui.outposts, ui.card } do
		if m and m.shade.Visible then
			return true
		end
	end
	return false
end

function HubMenus.hideAll()
	for _, m in { ui.board, ui.outposts, ui.card } do
		if m then
			m.shade.Visible = false
		end
	end
end

return HubMenus
