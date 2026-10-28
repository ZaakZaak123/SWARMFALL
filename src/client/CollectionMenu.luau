--!nonstrict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Collection = require(Shared:WaitForChild("Collection"))
local Defs = require(Shared:WaitForChild("Defs"))
local Theme = require(script.Parent.Theme)
local Preview = require(script.Parent.Preview)
local Menu = {}
local C, F, new, label = Theme.C, Theme.F, Theme.new, Theme.label

function Menu.init(H, openSwarm)
	local modal = H.modal("Collection", 960, 640, "КОЛЛЕКЦИЯ РОЯ", C.lime)
	Menu.modal = modal
	local sub = label("", {
		Position = UDim2.fromOffset(28, 60),
		Size = UDim2.new(1, -56, 0, 42),
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.dim,
		ZIndex = 42,
		Parent = modal.panel,
	})
	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(28, 112),
		Size = UDim2.fromOffset(330, 438),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 42,
		Parent = modal.panel,
		List = { Padding = UDim.new(0, 7) },
	})
	local detail = new(
		"Frame",
		{ Position = UDim2.fromOffset(380, 112), Size = UDim2.fromOffset(552, 438), ZIndex = 42, Parent = modal.panel }
	)
	local footer = label(
		"Образцы получает весь отряд. Коллекция постоянная: ДНК тратится отдельно.",
		{
			Position = UDim2.fromOffset(28, 568),
			Size = UDim2.fromOffset(580, 46),
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.dim,
			ZIndex = 42,
			Parent = modal.panel,
		}
	)
	local brood, text = Theme.button(
		"СВОЙ РОЙ  ›",
		{ Position = UDim2.fromOffset(686, 566), Size = UDim2.fromOffset(246, 48), TextSize = 15, ZIndex = 43 },
		"primary"
	)
	brood.Parent, text.ZIndex = modal.panel, 44
	brood.Activated:Connect(function()
		modal.hide()
		openSwarm()
	end)
	local research, owner, selected, own, canSwarm = {}, nil, nil, true, true
	local widgets = {}
	local band = Theme.panel({ Name = "HeadBand", BackgroundTransparency = 0.06, CornerRadius = 18, ZIndex = 41 })
	band.Visible = false
	band.Parent = modal.panel
	modal.resize = function(size)
		-- DD-110: on a phone the window starts under Roblox's top bar (its buttons stood on the title);
		-- the title and × go up into the bar, right of those buttons
		local stripLeft, _, stripH = Theme.topStrip()
		local lift = Theme.phone() and stripH > 0
		local y0 = if lift then stripH + 4 else 0
		local w, h = math.min(960, size.X - 48), math.min(640, size.Y - 24 - y0)
		local compact = h < 500
		modal.scale.Scale = 1
		modal.panel.Size = UDim2.fromOffset(w, h)
		modal.panel.AnchorPoint = Vector2.new(0.5, if lift then 0 else 0.5)
		modal.panel.Position = if lift then UDim2.new(0.5, 0, 0, y0) else UDim2.fromScale(0.5, 0.5)
		local title, close = modal.panel.ModalTitle, modal.panel.ModalClose
		if lift then
			local x = math.max(20, stripLeft + 12 - (size.X - w) / 2)
			title.Position = UDim2.fromOffset(x, stripH / 2 - y0 - 15)
			title.Size = UDim2.new(1, -x - 70, 0, 30)
			close.Position = UDim2.new(1, -12, 0, stripH / 2 - y0 - 22)
			band.Position = UDim2.fromOffset(x - 14, 3 - y0)
			band.Size = UDim2.new(1, -x + 14, 0, stripH - 6)
		else
			title.Position = UDim2.fromOffset(20, if compact then 8 else 22)
			title.Size = UDim2.new(1, -120, 0, 36)
			close.Position = UDim2.new(1, -12, 0, if compact then 6 else 18)
		end
		band.Visible = lift
		title.TextSize = if compact then 22 else 28
		local subY = if lift then 12 elseif compact then 44 else 60
		sub.Position = UDim2.fromOffset(20, subY)
		sub.Size = UDim2.new(1, -92, 0, if compact then 28 else 42)
		sub.TextSize = if compact then 12 else 14
		local top = subY + (if compact then 36 else 52)
		local contentH = h - top - (if compact then 64 else 90)
		local listW = if compact then math.floor(w * 0.30) else 330
		list.Position, list.Size = UDim2.fromOffset(20, top), UDim2.fromOffset(listW, contentH)
		detail.Position, detail.Size = UDim2.fromOffset(listW + 40, top), UDim2.fromOffset(w - listW - 60, contentH)
		brood.Position = UDim2.new(1, -20, 1, -12)
		brood.AnchorPoint = Vector2.new(1, 1)
		brood.Size = UDim2.fromOffset(if compact then 180 else 246, 44)
		footer.Position, footer.Size = UDim2.new(0, 20, 1, -58), UDim2.new(1, if compact then -224 else -300, 0, 46)
		footer.TextSize = if compact then 12 else 13
		if widgets.preview and widgets.preview.Parent then
			local imageW = if compact then math.floor(detail.Size.X.Offset * 0.34) else detail.Size.X.Offset
			local tx = if compact then imageW + 10 else 0
			widgets.preview.Size = UDim2.new(0, imageW, 0, if compact then contentH else 260)
			widgets.name.Position, widgets.name.Size =
				UDim2.fromOffset(tx, if compact then 4 else 270), UDim2.new(1, -tx, 0, if compact then 40 else 26)
			widgets.name.TextSize, widgets.name.TextWrapped = if compact then 17 else 22, true
			widgets.stage.Position, widgets.stage.Size =
				UDim2.fromOffset(tx, if compact then 50 else 304), UDim2.new(1, -tx, 0, 24)
			widgets.stage.TextSize = if compact then 13 else 16
			widgets.bar.Position, widgets.bar.Size =
				UDim2.fromOffset(if compact then tx else 26, if compact then 86 else 340),
				UDim2.new(1, if compact then -tx else -52, 0, 9)
			widgets.next.Position, widgets.next.Size =
				UDim2.fromOffset(if compact then tx else 26, if compact then 108 else 366),
				UDim2.new(1, if compact then -tx else -52, 0, if compact then contentH - 108 else 60)
			widgets.next.TextSize = if compact then 13 else 15
		end
	end
	local function refresh()
		H.clear(list)
		H.clear(detail)
		local summary = Collection.summary(research)
		sub.Text = (if owner then owner .. " · " else "")
			.. string.format(
				"Встречено %d видов · полных %d · эталонов %d",
				summary.found,
				summary.complete,
				summary.exemplary
			)
		brood.Visible = own or canSwarm
		text.Text = if own then "СВОЙ РОЙ  ›" else "МОЙ РОЙ  ›"
		footer.Text = if own
			then "Образцы получает весь отряд. Коллекция постоянная: ДНК тратится отдельно."
			else "Достижения хозяина убежища. Собери свои экземпляры в вылазках с отрядом."
		if summary.found == 0 then
			label(
				"Первые образцы привезёшь из вылазки.\nКаждый встреченный вид получит свою пробирку.",
				{
					Size = UDim2.fromScale(1, 1),
					TextSize = 18,
					TextWrapped = true,
					TextColor3 = C.dim,
					ZIndex = 43,
					Parent = detail,
				}
			)
			return
		end
		for order, kind in Collection.Order do
			local n = Collection.count(research, kind)
			if n <= 0 then
				continue
			end
			local p = Collection.progress(kind, n)
			if not selected or Collection.count(research, selected) == 0 then
				selected = kind
			end
			local b = new("TextButton", {
				Size = UDim2.new(1, -8, 0, 62),
				Text = "",
				Corner = 12,
				BackgroundColor3 = if selected == kind then C.panel2 else C.ink,
				BackgroundTransparency = 0.2,
				LayoutOrder = order,
				ZIndex = 43,
				Parent = list,
			})
			label(Defs.Enemies[kind].name, {
				Position = UDim2.fromOffset(14, 8),
				Size = UDim2.new(1, -28, 0, 22),
				FontFace = F.head,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 44,
				Parent = b,
			})
			label(p.name .. " · " .. n .. (if p.nextNeed then "/" .. p.nextNeed else ""), {
				Position = UDim2.fromOffset(14, 34),
				Size = UDim2.new(1, -28, 0, 18),
				TextSize = 13,
				TextColor3 = if p.stage == 4 then C.gold else C.lime,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 44,
				Parent = b,
			})
			b.Activated:Connect(function()
				selected = kind
				refresh()
			end)
		end
		local p = Collection.progress(selected, Collection.count(research, selected))
		local vpHolder = new("Frame", { Size = UDim2.fromOffset(552, 260), ZIndex = 43, Parent = detail })
		widgets.preview = vpHolder
		Preview.creature(vpHolder, Defs.Enemies[selected].index, { spin = true, zoom = 0.95 }).ZIndex = 44
		widgets.name = label(Defs.Enemies[selected].name, {
			Position = UDim2.fromOffset(0, 270),
			Size = UDim2.new(1, 0, 0, 26),
			FontFace = F.display,
			TextSize = 22,
			ZIndex = 43,
			Parent = detail,
		})
		widgets.stage = label(p.name .. " · " .. p.count .. " образцов", {
			Position = UDim2.fromOffset(0, 304),
			Size = UDim2.new(1, 0, 0, 24),
			TextSize = 16,
			TextColor3 = if p.stage == 4 then C.gold else C.lime,
			ZIndex = 43,
			Parent = detail,
		})
		local bar = new("Frame", {
			Position = UDim2.fromOffset(26, 340),
			Size = UDim2.new(1, -52, 0, 9),
			BackgroundColor3 = C.panel2,
			Corner = 5,
			ZIndex = 43,
			Parent = detail,
		})
		widgets.bar = bar
		new("Frame", {
			Size = UDim2.fromScale(p.fill, 1),
			BackgroundColor3 = if p.stage == 4 then C.gold else C.lime,
			Corner = 5,
			ZIndex = 44,
			Parent = bar,
		})
		widgets.next = label(
			if p.nextNeed
				then "Следующая стадия: ещё "
					.. (p.nextNeed - p.count)
					.. " образцов этого вида."
				else "Эталон выращен. Золотые обручи на пробирке видны всем гостям.",
			{
				Position = UDim2.fromOffset(26, 366),
				Size = UDim2.new(1, -52, 0, 60),
				TextSize = 15,
				TextWrapped = true,
				TextColor3 = C.dim,
				ZIndex = 43,
				Parent = detail,
			}
		)
		modal.resize(modal.shade.AbsoluteSize)
	end
	Menu.show = function(data, name, kind, isOwn, canUseSwarm)
		research, owner, selected, own = data or {}, name, kind, isOwn ~= false
		canSwarm = canUseSwarm == true
		refresh()
		modal.show()
	end
end

return Menu
