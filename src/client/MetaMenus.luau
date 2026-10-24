--!nonstrict
-- Meta screens (DD-037…DD-041), in the same visual language as Menus:
--   АВАНПОСТ  ten sockets around the extractor: build, upgrade, sell; the harvester's xenite
--   РОЙ       DNA per species, unlock species and mutations, assemble three strains
--   ЖУРНАЛ    raids on your outpost while you were away, with «Отомстить»
--   РЕЙТИНГ   raid rating and siege ladder boards
-- Helpers (modal, icon, pills) come from Menus so both share one look.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Meta = require(Shared:WaitForChild("Meta"))
local Ops = require(Shared:WaitForChild("Ops"))
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local Audio = require(script.Parent.Audio)
local Preview = require(script.Parent.Preview)
local Defs = require(Shared:WaitForChild("Defs"))

local new, label = Theme.new, Theme.label
local C, F = Theme.C, Theme.F

local MetaMenus = {}

local H -- helpers from Menus: { send, modal, icon, clear, xenitePill }
local profile = nil
local lobby = nil
local ui = {}
local selectedSocket = 1
local selectedSpecies = "EN_RUNNER"

local function z(inst: Instance, zi: number)
	if inst:IsA("GuiObject") then
		inst.ZIndex = zi
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = zi + 1
		end
	end
	return inst
end

local function pill(text: string, color: Color3, props)
	local f = new("Frame", {
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.82,
		Corner = UDim.new(1, 0),
		Stroke = { Color = color, Transparency = 0.4 },
	})
	for k, v in props or {} do
		f[k] = v
	end
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = f })
	label(text, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), FontFace = F.head, TextSize = 11, TextColor3 = color, Parent = f })
	return f
end

local function unlockedBy(def): boolean
	return profile ~= nil and profile.winsByOp and (profile.winsByOp[def.unlock] or 0) > 0
end

-- Outpost editor -----------------------------------------------------------------------------------------
local MAP_R = 196 -- px for the outer ring area
local K = 5.6 -- px per stud

local function buildOutpost()
	local m = H.modal("OutpostEditor", 960, 620, "МАСТЕРСКАЯ · ОБОРОНА БУРА", C.lime)
	ui.outpost = m
	ui.opSub = label("", {
		Position = UDim2.fromOffset(28, 60),
		Size = UDim2.new(1, -56, 0, 20),
		FontFace = F.body,
		TextSize = 14,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 42,
		Parent = m.panel,
	})
	-- schematic
	local map = new("Frame", {
		Position = UDim2.fromOffset(28, 96),
		Size = UDim2.fromOffset(MAP_R * 2 + 40, MAP_R * 2 + 40),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.3,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.white, Transparency = 0.88 },
		ZIndex = 42,
		Parent = m.panel,
	})
	ui.opMap = map
	for _, r in { 17, 30 } do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(r * K * 2, r * K * 2),
			BackgroundTransparency = 1,
			Corner = UDim.new(1, 0),
			Stroke = { Color = C.white, Transparency = 0.9 },
			ZIndex = 43,
			Parent = map,
		})
	end
	local core = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(66, 66),
		BackgroundColor3 = C.pink,
		BackgroundTransparency = 0.7,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.pink, Thickness = 2 },
		ZIndex = 43,
		Parent = map,
	})
	label("БУР", { Size = UDim2.fromScale(1, 1), FontFace = F.display, TextSize = 13, ZIndex = 44, Parent = core })
	label("СЕВЕР · ОТКУДА ИДЁТ РОЙ", { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 14), FontFace = F.head, TextSize = 9, TextColor3 = C.dim, ZIndex = 43, Parent = map })
	ui.sockets = {}
	for i, s in Meta.Sockets do
		local b = new("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			-- screen-right is world -X
			Position = UDim2.new(0.5, -s.x * K, 0.5, -s.z * K),
			Size = UDim2.fromOffset(62, 62),
			BackgroundColor3 = C.ink,
			BackgroundTransparency = 0.1,
			Text = "",
			Corner = UDim.new(1, 0),
			ZIndex = 44,
			Parent = map,
		})
		local stroke = new("UIStroke", { Color = C.white, Transparency = 0.7, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
		local holder = new("Frame", { Size = UDim2.fromScale(1, 1), ZIndex = 45, Parent = b })
		b.Activated:Connect(function()
			selectedSocket = i
			Audio.play("uiHover")
			MetaMenus.refreshOutpost()
		end)
		ui.sockets[i] = { button = b, stroke = stroke, holder = holder }
	end
	-- detail panel
	ui.opDetail = new("ScrollingFrame", {
		Position = UDim2.fromOffset(MAP_R * 2 + 92, 96),
		Size = UDim2.new(1, -(MAP_R * 2 + 120), 1, -120),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 42,
		Parent = m.panel,
	})
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = ui.opDetail })
end

local function costText(def, lvl: number): string
	local t = "◆ " .. def.cost[lvl]
	if def.dna[lvl] > 0 then
		t ..= "  ·  ДНК " .. def.dna[lvl]
	end
	return t
end

local function statLine(def, lvl: number): string
	if def.kind == "turret" then
		return string.format("%d урона · %.1f выстр/с · дальность %d", def.damage[lvl], 1 / def.every[lvl], def.range)
	elseif def.kind == "chain" then
		return string.format("%d урона · %d целей · раз в %.1f с", def.damage[lvl], def.targets[lvl], def.every[lvl])
	elseif def.kind == "mortar" then
		return string.format("%d урона по площади r%d · раз в %.1f с", def.damage[lvl], def.radius[lvl], def.every[lvl])
	elseif def.kind == "slow" then
		return string.format("замедление %d%% · радиус %d", def.slow[lvl] * 100, def.radius[lvl])
	elseif def.kind == "acid" then
		return string.format("%d урона/с · радиус %d", def.damage[lvl], def.radius[lvl])
	elseif def.kind == "shield" then
		return string.format("щит бура %d каждые %d с", def.shield[lvl], def.every[lvl])
	elseif def.kind == "harvest" then
		return string.format("%d утиля в час · до %d ч", def.perHour[lvl], Meta.HarvestCapHours)
	end
	return ""
end

local function row(parent, order: number, h: number)
	return new("Frame", {
		Size = UDim2.new(1, -8, 0, h),
		BackgroundColor3 = C.panel2,
		BackgroundTransparency = 0.4,
		Corner = 14,
		LayoutOrder = order,
		ZIndex = 43,
		Parent = parent,
	})
end

local function iconDisc(parent, iconName: string, color: Color3, size: number, pos: UDim2)
	local d = Icons.disc(iconName, size, color, 44)
	d.Position = pos
	d.Parent = parent
	return d
end

function MetaMenus.refreshOutpost()
	if not ui.outpost or not profile or not profile.outpost then
		return
	end
	local slots = profile.outpost.slots or {}
	ui.opSub.Text = string.format(
		"Собранное здесь стоит у бура в опасной зоне  ·  мощь %d  ·  ДНК %d  ·  утиль ◆ %s  ·  оборона: ур. %d",
		Meta.outpostPower(slots),
		profile.dna and profile.dna.EN_RUNNER or 0,
		Theme.commas(profile.scrap),
		profile.outpost.siege or 1
	)
	for i, s in ui.sockets do
		H.clear(s.holder)
		local slot = slots[i] or slots[tostring(i)]
		s.stroke.Color = if i == selectedSocket then C.lime elseif slot then Meta.Structures[slot.id].color else C.white
		s.stroke.Transparency = if i == selectedSocket then 0 elseif slot then 0.3 else 0.75
		if slot then
			local def = Meta.Structures[slot.id]
			H.icon(def.icon, 30, def.color, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), ZIndex = 46, Parent = s.holder })
			for k = 1, 3 do
				new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, (k - 2) * 9, 1, -14),
					Size = UDim2.fromOffset(7, 4),
					BackgroundColor3 = if k <= slot.lvl then def.color else C.white,
					BackgroundTransparency = if k <= slot.lvl then 0 else 0.8,
					Corner = UDim.new(1, 0),
					ZIndex = 46,
					Parent = s.holder,
				})
			end
		else
			label("+", { Size = UDim2.fromScale(1, 1), FontFace = F.display, TextSize = 26, TextColor3 = C.dim, ZIndex = 46, Parent = s.holder })
		end
	end
	-- detail
	H.clear(ui.opDetail)
	local slot = slots[selectedSocket] or slots[tostring(selectedSocket)]
	local sock = Meta.Sockets[selectedSocket]
	label((if sock.ring == 1 then "ВНУТРЕННЕЕ" else "ВНЕШНЕЕ") .. " ГНЕЗДО " .. selectedSocket, {
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = F.head,
		TextSize = 12,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
		ZIndex = 43,
		Parent = ui.opDetail,
	})
	if slot then
		local def = Meta.Structures[slot.id]
		local card = row(ui.opDetail, 1, 230)
		iconDisc(card, def.icon, def.color, 72, UDim2.fromOffset(16, 16))
		label(def.name, { Position = UDim2.fromOffset(104, 18), Size = UDim2.new(1, -120, 0, 28), FontFace = F.display, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 44, Parent = card })
		label("Уровень " .. slot.lvl .. " / 3  ·  " .. def.short, { Position = UDim2.fromOffset(104, 48), Size = UDim2.new(1, -120, 0, 18), FontFace = F.bodyBold, TextSize = 13, TextColor3 = def.color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 44, Parent = card })
		label(def.text .. "\n" .. statLine(def, slot.lvl), { Position = UDim2.fromOffset(16, 100), Size = UDim2.new(1, -32, 0, 44), FontFace = F.body, TextSize = 14, TextColor3 = C.dim, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 44, Parent = card })
		if slot.lvl < 3 then
			local nextLvl = slot.lvl + 1
			local can = profile.scrap >= def.cost[nextLvl] and (profile.dna.EN_RUNNER or 0) >= def.dna[nextLvl]
			local up, upl = Theme.button("УЛУЧШИТЬ  " .. costText(def, nextLvl), { Position = UDim2.fromOffset(16, 160), Size = UDim2.new(0.62, -20, 0, 50), TextSize = 14, ZIndex = 44 }, if can then "primary" else "ghost")
			up.Parent = card
			upl.ZIndex = 45
			if not can then
				upl.TextColor3 = C.dim
			end
			up.Activated:Connect(function()
				if can then
					H.send("upgrade", selectedSocket)
					Audio.play("level", 0.8, 1.2)
				else
					Audio.play("warn", 0.4)
				end
			end)
			label("Дальше: " .. statLine(def, nextLvl), { Position = UDim2.fromOffset(16, 214), Size = UDim2.new(1, -32, 0, 14), FontFace = F.body, TextSize = 11, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 44, Parent = card })
		end
		local refund = 0
		for l = 1, slot.lvl do
			refund += def.cost[l]
		end
		local sell, sl = Theme.button("ПРОДАТЬ  +" .. math.floor(refund * Meta.SellRefund), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 160), Size = UDim2.new(0.38, -12, 0, 50), TextSize = 13, ZIndex = 44 })
		sell.Parent = card
		sl.ZIndex = 45
		sell.Activated:Connect(function()
			H.send("sell", selectedSocket)
			Audio.play("ui", 0.8, 0.8)
		end)
	else
		for order, id in Meta.StructureOrder do
			local def = Meta.Structures[id]
			local open = unlockedBy(def)
			local can = open and profile.scrap >= def.cost[1]
			local r = row(ui.opDetail, order, 76)
			iconDisc(r, def.icon, if open then def.color else C.dim, 50, UDim2.fromOffset(12, 13))
			label(def.name, { Position = UDim2.fromOffset(74, 12), Size = UDim2.new(1, -230, 0, 22), FontFace = F.display, TextSize = 16, TextColor3 = if open then C.text else C.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 44, Parent = r })
			label(if open then statLine(def, 1) else "Откроется: победа в «" .. Ops.get(def.unlock).name .. "»", { Position = UDim2.fromOffset(74, 38), Size = UDim2.new(1, -230, 0, 28), FontFace = F.body, TextSize = 12, TextColor3 = C.dim, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 44, Parent = r })
			if open then
				local b, bl = Theme.button("◆ " .. def.cost[1], { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(130, 44), TextSize = 15, ZIndex = 44 }, if can then "primary" else "ghost")
				b.Parent = r
				bl.ZIndex = 45
				if not can then
					bl.TextColor3 = C.dim
				end
				b.Activated:Connect(function()
					if can then
						H.send("build", selectedSocket, id)
						Audio.play("level", 0.8, 1.1)
					else
						Audio.play("warn", 0.4)
					end
				end)
			else
				H.icon("lock", 22, C.dim, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0), ZIndex = 45, Parent = r })
			end
		end
	end
end

function MetaMenus.showOutpost(slot: number?)
	if slot and Meta.Sockets[slot] then
		selectedSocket = slot
	end
	MetaMenus.refreshOutpost()
	ui.outpost.show()
end

function MetaMenus.anyVisible(): boolean
	for _, m in { ui.outpost, ui.swarm, ui.log, ui.boards } do
		if m and m.shade.Visible then
			return true
		end
	end
	return false
end

-- Swarm -------------------------------------------------------------------------------------------------
local function buildSwarm()
	local m = H.modal("Swarm", 980, 640, "СВОЙ РОЙ", C.violet)
	ui.swarm = m
	label("Твой рой защищает бур, когда на него совершают налёт. ДНК даёт каждая убитая тварь отряда.", {
		Position = UDim2.fromOffset(28, 60),
		Size = UDim2.new(1, -56, 0, 20),
		FontFace = F.body,
		TextSize = 14,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 42,
		Parent = m.panel,
	})
	ui.swSpecies = new("Frame", { Position = UDim2.fromOffset(28, 92), Size = UDim2.fromOffset(420, 300), ZIndex = 42, Parent = m.panel, List = { Padding = UDim.new(0, 6) } })
	ui.swMuts = new("Frame", { Position = UDim2.fromOffset(28, 400), Size = UDim2.fromOffset(420, 220), ZIndex = 42, Parent = m.panel, List = { Padding = UDim.new(0, 6) } })
	label("ШТАММЫ ДЛЯ ОБОРОНЫ", { Position = UDim2.fromOffset(476, 92), Size = UDim2.fromOffset(460, 18), FontFace = F.head, TextSize = 12, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 42, Parent = m.panel })
	ui.swStrains = new("Frame", { Position = UDim2.fromOffset(476, 116), Size = UDim2.fromOffset(476, 430), ZIndex = 42, Parent = m.panel, List = { Padding = UDim.new(0, 10) } })
	ui.swWave = label("", { Position = UDim2.fromOffset(476, 560), Size = UDim2.fromOffset(476, 50), FontFace = F.body, TextSize = 13, TextColor3 = C.dim, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 42, Parent = m.panel })
end

local SPECIES_INDEX = { EN_RUNNER = 1, EN_STALKER = 2, EN_SPITTER = 3, EN_BOMBER = 8, EN_BULWARK = 4 }

local function speciesName(kind: string): string
	return Meta.Species[kind].name
end

local function mutationLabel(muts): string
	local names = {}
	for _, m in muts do
		table.insert(names, Meta.Mutations[m].name:lower())
	end
	return if #names > 0 then table.concat(names, ", ") else "без мутаций"
end

function MetaMenus.refreshSwarm()
	if not ui.swarm or not profile or not profile.dna then
		return
	end
	H.clear(ui.swSpecies)
	for order, kind in Meta.SpeciesOrder do
		local sp = Meta.Species[kind]
		local have = profile.species and profile.species[kind]
		local dna = profile.dna[kind] or 0
		local r = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = if kind == selectedSpecies then C.panel2 else C.ink,
			BackgroundTransparency = if kind == selectedSpecies then 0.1 else 0.45,
			Text = "",
			Corner = 14,
			LayoutOrder = order,
			ZIndex = 43,
			Stroke = { Color = if kind == selectedSpecies then C.violet else C.white, Transparency = if kind == selectedSpecies then 0.2 else 0.9 },
			Parent = ui.swSpecies,
		})
		local vp = new("Frame", { Position = UDim2.fromOffset(6, 2), Size = UDim2.fromOffset(50, 50), ZIndex = 44, Parent = r })
		Preview.creature(vp, SPECIES_INDEX[kind], { zoom = 0.8 }).ZIndex = 44
		label(sp.name, { Position = UDim2.fromOffset(64, 8), Size = UDim2.fromOffset(200, 20), FontFace = F.display, TextSize = 15, TextColor3 = if have then C.text else C.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 44, Parent = r })
		label("ДНК " .. dna .. "  ·  " .. sp.points .. " очк. за особь", { Position = UDim2.fromOffset(64, 30), Size = UDim2.fromOffset(220, 16), FontFace = F.body, TextSize = 12, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 44, Parent = r })
		if have then
			H.icon("check", 20, C.violet, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), ZIndex = 45, Parent = r })
		else
			local can = dna >= sp.unlock
			local b, bl = Theme.button("ВЫВЕСТИ · " .. sp.unlock, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(140, 38), TextSize = 12, ZIndex = 44 }, if can then "primary" else "ghost")
			b.Parent = r
			bl.ZIndex = 45
			if not can then
				bl.TextColor3 = C.dim
			end
			b.Activated:Connect(function()
				if can then
					H.send("unlockSpecies", kind)
					Audio.play("level", 0.8, 0.9)
				end
			end)
		end
		r.Activated:Connect(function()
			selectedSpecies = kind
			Audio.play("uiHover")
			MetaMenus.refreshSwarm()
		end)
	end
	-- mutations of the selected species
	H.clear(ui.swMuts)
	label("МУТАЦИИ: " .. speciesName(selectedSpecies), { Size = UDim2.new(1, 0, 0, 18), FontFace = F.head, TextSize = 12, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0, ZIndex = 43, Parent = ui.swMuts })
	local grid = new("Frame", { Size = UDim2.new(1, 0, 0, 190), LayoutOrder = 1, ZIndex = 43, Parent = ui.swMuts })
	new("UIGridLayout", { CellSize = UDim2.fromOffset(206, 58), CellPadding = UDim2.fromOffset(8, 6), Parent = grid })
	local haveSpecies = profile.species and profile.species[selectedSpecies]
	for _, mid in Meta.MutationOrder do
		local mdef = Meta.Mutations[mid]
		local key = selectedSpecies .. ":" .. mid
		local owned = profile.mutations and profile.mutations[key]
		local can = haveSpecies and not owned and (profile.dna[selectedSpecies] or 0) >= mdef.dna
		local cell = new("TextButton", {
			BackgroundColor3 = C.ink,
			BackgroundTransparency = 0.35,
			Text = "",
			Corner = 12,
			ZIndex = 44,
			Stroke = { Color = if owned then mdef.color else C.white, Transparency = if owned then 0.3 else 0.88 },
			Parent = grid,
		})
		H.icon(mdef.icon, 22, if owned or can then mdef.color else C.dim, { Position = UDim2.fromOffset(10, 8), ZIndex = 45, Parent = cell })
		label(mdef.name, { Position = UDim2.fromOffset(40, 6), Size = UDim2.new(1, -46, 0, 18), FontFace = F.head, TextSize = 11, TextColor3 = if owned then C.text else C.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 45, Parent = cell })
		label(if owned then mdef.text elseif haveSpecies then "ДНК " .. mdef.dna .. " — нажми, чтобы вывести" else "Сначала выведи вид", { Position = UDim2.fromOffset(40, 24), Size = UDim2.new(1, -46, 0, 30), FontFace = F.body, TextSize = 10, TextColor3 = C.dim, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 45, Parent = cell })
		cell.Activated:Connect(function()
			if can then
				H.send("unlockMutation", selectedSpecies, mid)
				Audio.play("level", 0.8, 1.3)
			end
		end)
	end
	-- strains
	H.clear(ui.swStrains)
	local brood = profile.brood or {}
	local species = {}
	for _, kind in Meta.SpeciesOrder do
		if profile.species and profile.species[kind] then
			table.insert(species, kind)
		end
	end
	local waveParts = {}
	for i = 1, Meta.MaxStrains do
		local strain = brood[i]
		local card = new("Frame", {
			Size = UDim2.new(1, 0, 0, 132),
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = 0.35,
			Corner = 16,
			LayoutOrder = i,
			ZIndex = 43,
			Stroke = { Color = if strain then C.violet else C.white, Transparency = if strain then 0.35 else 0.88 },
			Parent = ui.swStrains,
		})
		if strain then
			local vp = new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(110, 110), ZIndex = 44, Parent = card })
			Preview.creature(vp, SPECIES_INDEX[strain.kind], { spin = true, zoom = 0.75 }).ZIndex = 44
			local units = Meta.strainUnits(strain)
			table.insert(waveParts, units .. " × " .. speciesName(strain.kind):lower() .. (if #strain.muts > 0 then " (" .. mutationLabel(strain.muts) .. ")" else ""))
			label("ШТАММ " .. i .. "  ·  " .. units .. " особей в волне", { Position = UDim2.fromOffset(128, 10), Size = UDim2.new(1, -140, 0, 16), FontFace = F.head, TextSize = 10, TextColor3 = C.violet, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 44, Parent = card })
			-- species switch
			local sb, sbl = Theme.button(speciesName(strain.kind) .. "  ›", { Position = UDim2.fromOffset(128, 30), Size = UDim2.fromOffset(200, 40), TextSize = 14, ZIndex = 44 })
			sb.Parent = card
			sbl.ZIndex = 45
			sb.Activated:Connect(function()
				local idx = table.find(species, strain.kind) or 0
				local nextKind = species[idx % #species + 1]
				if nextKind then
					H.send("setStrain", i, nextKind, {})
					Audio.play("uiHover")
				end
			end)
			local del, dl = Theme.button("×", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 30), Size = UDim2.fromOffset(40, 40), TextSize = 20, ZIndex = 44 })
			del.Parent = card
			dl.ZIndex = 45
			dl.FontFace = F.bodyBold
			del.Activated:Connect(function()
				H.send("setStrain", i, nil, nil)
			end)
			-- mutation slots: click cycles through the species' unlocked mutations
			local owned = {}
			for _, mid in Meta.MutationOrder do
				if profile.mutations[strain.kind .. ":" .. mid] then
					table.insert(owned, mid)
				end
			end
			for k = 1, Meta.MaxMutationsPerStrain do
				local cur = strain.muts[k]
				local mdef = cur and Meta.Mutations[cur]
				local chip = new("TextButton", {
					Position = UDim2.fromOffset(128 + (k - 1) * 170, 80),
					Size = UDim2.fromOffset(162, 40),
					BackgroundColor3 = C.ink,
					BackgroundTransparency = 0.25,
					Text = "",
					Corner = UDim.new(1, 0),
					ZIndex = 44,
					Stroke = { Color = if mdef then mdef.color else C.white, Transparency = if mdef then 0.3 else 0.85 },
					Parent = card,
				})
				label(if mdef then mdef.name else (if #owned > 0 then "+ мутация" else "нет мутаций"), { Size = UDim2.fromScale(1, 1), FontFace = F.head, TextSize = 10, TextColor3 = if mdef then mdef.color else C.dim, ZIndex = 45, Parent = chip })
				chip.Activated:Connect(function()
					if #owned == 0 then
						return
					end
					local muts = table.clone(strain.muts)
					local idx = if cur then table.find(owned, cur) or 0 else 0
					local nextMut = owned[idx + 1]
					-- skip mutations already in the other slot
					while nextMut and table.find(muts, nextMut) and nextMut ~= cur do
						idx += 1
						nextMut = owned[idx + 1]
					end
					if nextMut then
						muts[k] = nextMut
					else
						table.remove(muts, k)
					end
					H.send("setStrain", i, strain.kind, muts)
					Audio.play("uiHover")
				end)
			end
		else
			local add, al = Theme.button(if #species > 0 then "+  ДОБАВИТЬ ШТАММ" else "Выведи вид слева", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(280, 50), TextSize = 14, ZIndex = 44 })
			add.Parent = card
			al.ZIndex = 45
			add.Activated:Connect(function()
				if #species > 0 then
					H.send("setStrain", i, species[1], {})
					Audio.play("level", 0.7, 1.2)
				end
			end)
		end
	end
	ui.swWave.Text = if #waveParts > 0 then "Одна волна твоего роя: " .. table.concat(waveParts, " + ") .. ". За вторжение — до 8 волн." else "Пока рой пуст: напавших встретят обычные бегуны."
end

function MetaMenus.showSwarm()
	MetaMenus.refreshSwarm()
	ui.swarm.show()
end

-- Raid log ----------------------------------------------------------------------------------------------
local function ago(t: number): string
	local d = os.time() - (t or os.time())
	if d < 3600 then
		return math.max(1, math.floor(d / 60)) .. " мин назад"
	elseif d < 86400 then
		return math.floor(d / 3600) .. " ч назад"
	end
	return math.floor(d / 86400) .. " дн назад"
end

local function buildLog()
	local m = H.modal("RaidLog", 760, 560, "ЖУРНАЛ НАЛЁТОВ", C.orange)
	ui.log = m
	ui.logSub = label("", { Position = UDim2.fromOffset(28, 60), Size = UDim2.new(1, -56, 0, 20), FontFace = F.body, TextSize = 14, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 42, Parent = m.panel })
	ui.logList = new("ScrollingFrame", {
		Position = UDim2.fromOffset(28, 92),
		Size = UDim2.new(1, -56, 1, -116),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
		ZIndex = 42,
		Parent = m.panel,
	})
	new("UIListLayout", { Padding = UDim.new(0, 8), Parent = ui.logList })
end

function MetaMenus.refreshLog()
	if not ui.log or not profile then
		return
	end
	local r = profile.raid or {}
	ui.logSub.Text = string.format(
		"Налётчик: рейтинг %d, атак %d/%d  ·  Защитник: отбито %d  ·  Налёты на тебя ничего у тебя не отнимают",
		r.attack or r.rating or 0,
		r.wins or 0,
		(r.wins or 0) + (r.losses or 0),
		r.held or r.defWins or 0
	)
	H.clear(ui.logList)
	local log = profile.raidLog or {}
	if #log == 0 then
		label("На твой бур ещё никто не нападал. Нападают на копию обороны: твоё убежище и утиль не трогают.", { Size = UDim2.new(1, 0, 0, 60), FontFace = F.body, TextSize = 15, TextColor3 = C.dim, TextWrapped = true, ZIndex = 43, Parent = ui.logList })
	end
	for i, entry in log do
		local rr = row(ui.logList, i, 70)
		local held = not entry.won
		iconDisc(rr, if held then "shield" else "skull", if held then C.lime else C.red, 46, UDim2.fromOffset(12, 12))
		label((entry.name or "Охотник") .. (if held then " — оборона выстояла" else " — прорвал оборону"), { Position = UDim2.fromOffset(70, 12), Size = UDim2.new(1, -230, 0, 22), FontFace = F.bodyBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 44, Parent = rr })
		label(ago(entry.t) .. (if held then "  ·  +" .. Meta.DefenseReward .. " утиля, +1 к рекорду обороны" else "  ·  ты ничего не потерял · ответный вызов даёт ×1.5"), { Position = UDim2.fromOffset(70, 38), Size = UDim2.new(1, -230, 0, 18), FontFace = F.body, TextSize = 12, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 44, Parent = rr })
		if (entry.attacker or 0) > 0 and profile.features and profile.features.raids then
			local b, bl = Theme.button("ОТВЕТНЫЙ ВЫЗОВ", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 42), TextSize = 13, ZIndex = 44 }, if held then "ghost" else "danger")
			b.Parent = rr
			bl.ZIndex = 45
			b.Activated:Connect(function()
				H.send("revenge", entry.attacker)
				Audio.play("warn", 0.6)
				ui.log.hide()
			end)
		end
	end
end

function MetaMenus.showLog()
	MetaMenus.refreshLog()
	ui.log.show()
end

-- Boards ------------------------------------------------------------------------------------------------
local function buildBoards()
	local m = H.modal("Boards", 760, 560, "РЕЙТИНГ", C.gold)
	ui.boards = m
	ui.boardCols = {}
	-- DD-061: raiders (a rating only from raids you chose), defenders (raids held — it never drops),
	-- and the drill defence record
	for i, title in { "НАЛЁТЧИКИ · РЕЙТИНГ", "ЗАЩИТНИКИ · ОТБИТО", "ОБОРОНА БУРА" } do
		label(title, { Position = UDim2.fromOffset(28 + (i - 1) * 236, 70), Size = UDim2.fromOffset(224, 18), FontFace = F.head, TextSize = 11, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 42, Parent = m.panel })
		ui.boardCols[i] = new("Frame", { Position = UDim2.fromOffset(28 + (i - 1) * 236, 96), Size = UDim2.fromOffset(224, 430), ZIndex = 42, Parent = m.panel, List = { Padding = UDim.new(0, 4) } })
	end
end

function MetaMenus.showBoards()
	local boards = lobby and lobby.boards or {}
	for i, key in { "rating", "held", "siege" } do
		local col = ui.boardCols[i]
		H.clear(col)
		local rows = boards[key] or {}
		if #rows == 0 then
			label(if lobby and lobby.online then "Пока пусто — стань первым." else "Рейтинги доступны на опубликованных серверах.", { Size = UDim2.new(1, 0, 0, 50), FontFace = F.body, TextSize = 14, TextColor3 = C.dim, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 43, Parent = col })
		end
		for k, r in rows do
			local f = row(col, k, 36)
			label(k .. ".", { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(30, 36), FontFace = F.numHeavy, TextSize = 14, TextColor3 = if k <= 3 then C.gold else C.dim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 44, Parent = f })
			label(r.name, { Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -130, 1, 0), FontFace = F.bodyBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 44, Parent = f })
			label(tostring(r.value), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(80, 36), FontFace = F.numHeavy, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 44, Parent = f })
		end
	end
	ui.boards.show()
end

-- Wiring ------------------------------------------------------------------------------------------------
function MetaMenus.init(helpers)
	H = helpers
	buildOutpost()
	buildSwarm()
	buildLog()
	buildBoards()
end

function MetaMenus.setProfile(pub)
	profile = pub
	if ui.outpost and ui.outpost.shade.Visible then
		MetaMenus.refreshOutpost()
	end
	if ui.swarm and ui.swarm.shade.Visible then
		MetaMenus.refreshSwarm()
	end
	if ui.log and ui.log.shade.Visible then
		MetaMenus.refreshLog()
	end
end

function MetaMenus.setLobby(info)
	lobby = info
end

function MetaMenus.hideAll()
	for _, m in { ui.outpost, ui.swarm, ui.log, ui.boards } do
		if m then
			m.shade.Visible = false
		end
	end
end

return MetaMenus
