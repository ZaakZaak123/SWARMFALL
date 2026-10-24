--!strict
-- The one next goal (DD-052): after every success the base and the results screen show a single, nearest
-- step — what to do, where on the base to do it, and what it opens. Pure function of the public profile
-- so the client can draw it and the tests can walk it. Order matters: the first match wins.

local Meta = require(script.Parent.Meta)
local Ops = require(script.Parent.Ops)

local Goals = {}

export type Goal = {
	key: string,
	icon: string,
	title: string, -- short, caps
	text: string, -- one sentence: what, and what it gives
	station: string, -- "launch" | "build" | "armory" | "home": where on the base it happens
	spot: string?, -- home goals: the shelter spot to restore (Meta.Home)
	slot: number?, -- build goals: the socket to light up
	structure: string?, -- a structure to show as a model (what is being bought or opened)
	op: string?, -- the hunt that gets you there
	mode: string?, -- launch goals for the drill defence ("siege")
}

-- Cyrillic-aware case helpers (string.lower is byte-wise and leaves Cyrillic alone).
local function lowerCode(c: number): number
	if c >= 0x410 and c <= 0x42F then
		return c + 0x20
	elseif c == 0x401 then
		return 0x451
	end
	return if c >= 65 and c <= 90 then c + 32 else c
end

-- «РАЗРЯДНИК» -> «Разрядник»
function Goals.titleCase(s: string): string
	local out = {}
	local i = 0
	for _, c in utf8.codes(s) do
		i += 1
		table.insert(out, utf8.char(if i == 1 then c else lowerCode(c)))
	end
	return table.concat(out)
end

local function lowerFirst(s: string): string
	local out = {}
	local i = 0
	for _, c in utf8.codes(s) do
		i += 1
		table.insert(out, utf8.char(if i == 1 then lowerCode(c) else c))
	end
	return table.concat(out)
end

local function won(pub, opId: string): boolean
	return ((pub.winsByOp or {})[opId] or 0) > 0
end

local function builtCount(slots): number
	local n = 0
	for _ in slots do
		n += 1
	end
	return n
end

local function hasStructure(slots, id: string): boolean
	for _, s in slots do
		if s.id == id then
			return true
		end
	end
	return false
end

-- First free socket, inner ring first (closest to the base spawn among equals).
function Goals.freeSocket(slots): number?
	if not slots[Meta.FirstSocket] and not slots[tostring(Meta.FirstSocket)] then
		return Meta.FirstSocket
	end
	for i = 1, Meta.SocketCount do
		if not slots[i] and not slots[tostring(i)] then
			return i
		end
	end
	return nil
end

-- What a hunt's first win opens, in words (structures and modes).
function Goals.opensWith(opId: string): ({ string }, string?)
	local names = {}
	local first = nil
	for _, id in Meta.StructureOrder do
		local def = Meta.Structures[id]
		if def.unlock == opId then
			table.insert(names, "«" .. Goals.titleCase(def.name) .. "»")
			first = first or id
		end
	end
	for _, id in Meta.HomeOrder do
		local h = Meta.Home[id]
		if h.unlock == opId and not h.free then
			table.insert(names, "«" .. Goals.titleCase(h.name) .. "»")
		end
	end
	local modes = { O04 = "вторжения" }
	if modes[opId] then
		table.insert(names, modes[opId])
	end
	return names, first
end

function Goals.next(pub): Goal?
	if not pub then
		return nil
	end
	local slots = (pub.outpost and pub.outpost.slots) or {}
	local scrap = pub.scrap or 0
	local tut = pub.tut or {}
	local home = pub.home or {}
	if not won(pub, "O01") then
		return {
			key = "hunt1",
			icon = "skull",
			title = "ВЫЛАЗКА ЗА ГЕНЕРАТОРОМ",
			text = "В руинах станции — генератор для убежища. Убей Альфу, что гнездится на нём.",
			station = "launch",
			op = "O01",
		}
	end
	local bench = Meta.Home.WORKBENCH
	if not home.WORKBENCH then
		return {
			key = "workbench",
			icon = bench.icon,
			title = "ПОЧИНИ МАСТЕРСКУЮ",
			text = if scrap >= bench.cost
				then string.format("Добычи хватает (%d утиля). На верстаке соберёшь оборону для бура.", bench.cost)
				else string.format("Нужно %d утиля — ещё одна вылазка, и хватит.", bench.cost),
			station = if scrap >= bench.cost then "home" else "launch",
			spot = "WORKBENCH",
		}
	end
	if builtCount(slots) == 0 then
		local cost = Meta.Structures.STING.cost[1]
		return {
			key = "sting",
			icon = "crosshair",
			title = "ПЕРВАЯ ТУРЕЛЬ ДЛЯ БУРА",
			text = if scrap >= cost
				then "Собери «Жало» на верстаке — оно встанет у бура в опасной зоне."
				else string.format("«Жало» стоит %d утиля — ещё одна вылазка, и хватит.", cost),
			station = if scrap >= cost then "build" else "launch",
			slot = Meta.FirstSocket,
			structure = "STING",
		}
	end
	if not tut.strike then
		return {
			key = "strike",
			icon = "shield",
			title = "ОБОРОНА БУРА",
			text = "Бур в опасной зоне. Когда будешь готов — выйди и отбей первый натиск вместе с турелью.",
			station = "launch",
			mode = "siege",
			structure = "STING",
		}
	end
	-- A shelter spot that is open and affordable: restore it (the home grows first).
	for _, id in Meta.HomeOrder do
		local h = Meta.Home[id]
		if not h.free and not home[id] and won(pub, h.unlock) and scrap >= h.cost then
			return {
				key = "home_" .. id,
				icon = h.icon,
				title = "ВОССТАНОВИ: " .. h.name,
				text = h.text .. string.format(" Хватает утиля (%d).", h.cost),
				station = "home",
				spot = id,
			}
		end
	end
	-- An opened structure the player can afford and has not built yet: build it.
	for _, id in Meta.StructureOrder do
		local def = Meta.Structures[id]
		if won(pub, def.unlock) and not hasStructure(slots, id) and scrap >= def.cost[1] and def.kind ~= "harvest" then
			local slot = Goals.freeSocket(slots)
			if slot then
				return {
					key = "build_" .. id,
					icon = def.icon,
					title = "ПОСТРОЙ " .. def.name,
					text = def.text .. string.format(" Хватает утиля (%d).", def.cost[1]),
					station = "build",
					slot = slot,
					structure = id,
				}
			end
		end
	end
	-- The next story hunt and what its first win opens.
	for _, opId in Ops.Order do
		if opId ~= "CA01" and not won(pub, opId) and ((pub.ops or {})[opId] or 0) >= 1 then
			local op = Ops.get(opId)
			local names, structure = Goals.opensWith(opId)
			local text = op.brief
			local structDef = structure and Meta.Structures[structure]
			if structDef then
				-- Lead with the headline structure, then the rest in one short tail.
				text = string.format(
					"Ещё одна вылазка — и откроется %s: %s",
					names[1],
					lowerFirst(structDef.text)
				)
				if #names > 1 then
					text ..= " Плюс " .. table.concat(names, ", ", 2) .. "."
				end
			elseif #names > 0 then
				text = "Ещё одна вылазка — и откроется: " .. table.concat(names, ", ") .. "."
			end
			return {
				key = "op_" .. opId,
				icon = if structure then Meta.Structures[structure].icon else "pin",
				title = "ВЫЛАЗКА " .. op.index .. ": " .. op.name,
				text = text,
				station = "launch",
				structure = structure,
				op = opId,
			}
		end
	end
	-- Upgrade the cheapest affordable structure.
	local best, bestSlot, bestCost = nil, nil, math.huge
	for slot, s in slots do
		local def = Meta.Structures[s.id]
		local cost = def and def.cost[s.lvl + 1]
		if cost and cost <= scrap and cost < bestCost then
			best, bestSlot, bestCost = def, tonumber(slot), cost
		end
	end
	if best then
		return {
			key = "upgrade",
			icon = "level",
			title = "УЛУЧШИ " .. best.name,
			text = string.format(
				"Хватает утиля (%d) — турель станет сильнее в обороне бура и вылазках.",
				bestCost
			),
			station = "build",
			slot = bestSlot,
			structure = best.id,
		}
	end
	local siege = pub.outpost and pub.outpost.siege or 1
	return {
		key = "siege",
		icon = "threat",
		title = "ОБОРОНА БУРА · УРОВЕНЬ " .. siege,
		text = "Сколько продержится бур? Каждая отбитая волна открывает уровень выше.",
		station = "launch",
	}
end

return Goals
