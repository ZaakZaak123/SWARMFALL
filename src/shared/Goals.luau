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
	station: string, -- "launch" | "build" | "armory": where on the base it happens
	slot: number?, -- build goals: the socket to light up
	structure: string?, -- a structure to show as a model (what is being bought or opened)
	op: string?, -- the hunt that gets you there
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
	local modes = { O02 = "осада аванпоста", O03 = "свой рой", O04 = "вторжения" }
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
	if not won(pub, "O01") then
		return {
			key = "hunt1",
			icon = "skull",
			title = "ПЕРВАЯ ОХОТА",
			text = "Убей Альфу — и кратер станет твоим аванпостом.",
			station = "launch",
			op = "O01",
		}
	end
	if builtCount(slots) == 0 then
		local cost = Meta.Structures.STING.cost[1]
		return {
			key = "sting",
			icon = "crosshair",
			title = "ПЕРВАЯ ТУРЕЛЬ",
			text = if scrap >= cost
				then "Добычи хватает на «Жало». Поставь его на подсвеченное гнездо."
				else string.format(
					"«Жало» стоит %d ксенита — ещё одна охота, и хватит.",
					cost
				),
			station = if scrap >= cost then "build" else "launch",
			slot = Meta.FirstSocket,
			structure = "STING",
		}
	end
	if not tut.strike then
		return {
			key = "strike",
			icon = "shield",
			title = "РОЙ ИДЁТ НА БУР",
			text = "Держись у турели — она стреляет вместе с тобой.",
			station = "build",
			structure = "STING",
		}
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
					text = def.text .. string.format(" Хватает ксенита (%d).", def.cost[1]),
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
					"Ещё одна охота — и откроется %s: %s",
					names[1],
					lowerFirst(structDef.text)
				)
				if #names > 1 then
					text ..= " Плюс " .. table.concat(names, ", ", 2) .. "."
				end
			elseif #names > 0 then
				text = "Ещё одна охота — и откроется: " .. table.concat(names, ", ") .. "."
			end
			return {
				key = "op_" .. opId,
				icon = if structure then Meta.Structures[structure].icon else "pin",
				title = "ОХОТА " .. op.index .. ": " .. op.name,
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
				"Хватает ксенита (%d) — турель станет сильнее в осадах и охотах.",
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
		title = "ОСАДА · УРОВЕНЬ " .. siege,
		text = "Сколько продержится твой аванпост? Каждая победа открывает уровень выше.",
		station = "launch",
	}
end

return Goals
