--!strict
-- What other hunters see of you in the camp (DD-053): a title with a clear origin, the gun in your
-- hands and its mastery, a few trophies, the outpost. Built by the server from the profile (only these
-- fields leave the server), formatted by the client. Pure: tests read it in Lune.

local Defs = require(script.Parent.Defs)
local Meta = require(script.Parent.Meta)
local Collection = require(script.Parent.Collection)

local Showcase = {}

export type Entry = {
	id: number,
	name: string,
	weapon: string,
	form: string?, -- equipped M20 form of that weapon
	mastery: number, -- weapon mastery rank (M1–M20)
	title: string,
	titleIcon: string,
	trophies: { { string } }, -- { icon, text }
	siege: number, -- best siege level held (0 = none)
	wins: number,
	likes: number,
	power: number, -- outpost defence power
	slots: { [string]: { id: string, lvl: number } }, -- string keys: socket index (remote-safe)
	newbie: boolean,
	won: { [string]: boolean },
	home: { [string]: boolean },
	sample: number,
	collection: { [string]: number },
	stock: number, -- coarse display tier, never the exact balance
	saves: number,
	trophyKey: string,
}

local function won(d, opId: string): boolean
	return ((d.wins_by_op or {})[opId] or 0) > 0
end

-- The single headline title: the hardest thing done, said plainly.
-- Every title a survivor has earned, each with where it came from (DD-060). The player picks one to
-- wear; the default is the hardest deed.
function Showcase.titles(d): { { id: string, name: string, icon: string, why: string } }
	local best = d.outpost and d.outpost.best or 0
	local out = {
		{
			id = "NEWBIE",
			name = "Новобранец",
			icon = "star",
			why = "Каждый с чего-то начинал",
		},
	}
	local function add(id, name, icon, why)
		table.insert(out, { id = id, name = name, icon = icon, why = why })
	end
	if won(d, "O01") then
		add(
			"SHELTER",
			"Запустил убежище",
			"pin",
			"Добыл генератор в первой вылазке"
		)
	end
	if (d.saves or 0) >= 10 then
		add("SAVIOR", "Спаситель", "heart", "Поднял союзников " .. (d.saves or 0) .. " раз")
	end
	local specimens = Collection.summary(d.research)
	if specimens.complete >= 5 then
		add(
			"NATURALIST",
			"Исследователь роя",
			"hive",
			"Собрал полные экземпляры " .. specimens.complete .. " видов"
		)
	end
	if specimens.exemplary >= 3 then
		add(
			"CURATOR",
			"Хранитель коллекции",
			"star",
			"Вырастил эталоны " .. specimens.exemplary .. " видов"
		)
	end
	if won(d, "O03") then
		add("SCOURGE", "Гроза роя", "crosshair", "Отстоял поющий пилон")
	end
	local home = d.home or {}
	local all = true
	for _, id in Meta.HomeOrder do
		if not home[id] then
			all = false
		end
	end
	if all then
		add("KEEPER", "Хозяин убежища", "heart", "Восстановил всё убежище")
	end
	if best >= 3 then
		add(
			"SIEGE",
			"Удержал бур · " .. best,
			"shield",
			"Отбил оборону бура уровня " .. best
		)
	end
	if won(d, "O05") then
		add("BROOD", "Победил Мать роя", "skull", "Убил королеву роя в вылазке 5")
	end
	if won(d, "O07") then
		add("DEVOURER", "Пожиратель повержен", "crown", "Финал первой главы")
	end
	return out
end

function Showcase.title(d): (string, string)
	-- a title the player chose and still holds
	if d.title then
		for _, t in Showcase.titles(d) do
			if t.id == d.title then
				return t.name, t.icon
			end
		end
	end
	local best = d.outpost and d.outpost.best or 0
	if won(d, "O07") then
		return "Пожиратель повержен", "crown"
	elseif best >= 10 then
		return "Удержал бур · " .. best, "shield"
	elseif won(d, "O05") then
		return "Победил Мать роя", "skull"
	elseif best >= 3 then
		return "Удержал бур · " .. best, "shield"
	elseif won(d, "O03") then
		return "Гроза роя", "crosshair"
	elseif won(d, "O01") then
		return "Запустил убежище", "pin"
	end
	return "Новобранец", "star"
end

function Showcase.trophies(d, weapon: string, mastery: number): { { string } }
	local out = {}
	if won(d, "O07") then
		table.insert(out, { "crown", "Пожиратель" })
	end
	if won(d, "O05") then
		table.insert(out, { "skull", "Мать роя" })
	end
	local best = d.outpost and d.outpost.best or 0
	if best > 0 then
		table.insert(out, { "shield", "Оборона бура " .. best })
	end
	if mastery >= 5 then
		table.insert(
			out,
			{ "star", (Defs.Weapons[weapon] and Defs.Weapons[weapon].name or "Оружие") .. " M" .. mastery }
		)
	end
	local raid = d.raid and (d.raid.attack or d.raid.rating) or 0
	if (d.raid and d.raid.wins or 0) > 0 then
		table.insert(out, { "swords", "Налётчик " .. raid })
	end
	local held = d.raid and (d.raid.held or 0) or 0
	if held > 0 then
		table.insert(out, { "shield", "Отбито налётов: " .. held })
	end
	local specimens = Collection.summary(d.research)
	if specimens.complete > 0 then
		table.insert(out, {
			"hive",
			"Коллекция: "
				.. specimens.complete
				.. " полных · "
				.. specimens.exemplary
				.. " эталонов",
		})
	end
	return out
end

function Showcase.build(userId: number, name: string, d, weapon: string, form: string?): Entry
	local mastery = Defs.masteryRank(weapon, (d.mastery or {})[weapon] or 0)
	local title, icon = Showcase.title(d)
	local why = ""
	for _, t in Showcase.titles(d) do
		if t.name == title then
			why = t.why
		end
	end
	local slots = {}
	for slot, s in (d.outpost and d.outpost.slots) or {} do
		slots[tostring(slot)] = { id = s.id, lvl = s.lvl }
	end
	return {
		id = userId,
		name = name,
		weapon = weapon,
		form = form,
		mastery = mastery,
		title = title,
		titleIcon = icon,
		titleWhy = why, -- where the title came from, said on the card
		trophies = Showcase.trophies(d, weapon, mastery),
		siege = d.outpost and d.outpost.best or 0,
		wins = d.wins or 0,
		likes = d.likes or 0,
		power = Meta.outpostPower((d.outpost and d.outpost.slots) or {}),
		slots = slots,
		newbie = not won(d, "O01"),
		saves = d.saves or 0, -- allies raised, lifetime (DD-060)
		won = { O01 = won(d, "O01"), O05 = won(d, "O05"), O07 = won(d, "O07") }, -- trophy pedestals
		home = table.clone(d.home or {}), -- restored shelter spots (a visit draws them)
		sample = (d.research or {}).EN_SPITTER or 0, -- the lab tank's species research (DD-059)
		collection = Collection.public(d.research),
		stock = if (d.scrap or 0) >= 3000
			then 3000
			elseif (d.scrap or 0) >= 1000 then 1000
			elseif (d.scrap or 0) >= 300 then 300
			elseif (d.scrap or 0) > 0 then 1
			else 0,
		trophyKey = (if won(d, "O01") then "a" else "") .. (if won(d, "O05") then "b" else "") .. (if won(d, "O07")
			then "c"
			else ""),
	}
end

-- Squad awards on the results screen (DD-054): every member is noticed for something — the help that
-- a kill count hides (guarding the drill, carrying the big targets, rescues) comes first. Returns
-- user id -> { { icon, title } } (at most two each). Solo runs get none.
function Showcase.awards(players): { [number]: { { string } } }
	local out = {}
	if #players < 2 then
		return out
	end
	local function give(p, icon: string, title: string)
		out[p.id] = out[p.id] or {}
		if #out[p.id] < 2 then
			table.insert(out[p.id], { icon, title })
		end
	end
	local function best(field: string, min: number)
		local top, value = nil, min
		for _, p in players do
			local v = p[field] or 0
			if v > value then
				top, value = p, v
			end
		end
		return top, value
	end
	local rescuer, saves = best("revives", 0)
	if rescuer then
		give(rescuer, "heart", "Спаситель · " .. saves)
	end
	local guard = best("guardKills", 9)
	if guard then
		give(guard, "shield", "Защитник бура")
	end
	local hunter = best("bigDamage", 0)
	if hunter then
		give(hunter, "elite", "Охотник на крупных")
	end
	local gun = best("damage", 0)
	if gun then
		give(gun, "boom", "Главный калибр")
	end
	local combo = best("bestCombo", 4)
	if combo then
		give(combo, "burst", "Мастер комбо")
	end
	for _, p in players do
		if not out[p.id] then
			give(
				p,
				if p.alive then "check" else "users",
				if p.alive then "В строю до конца" else "Плечом к плечу"
			)
		end
	end
	return out
end

-- Squad board line: what the squad goes for, in the owner's words.
function Showcase.squadTitle(mode: string, opName: string, opIndex: number, siege: number?): string
	if mode == "siege" then
		return string.format("Защитить мой бур · оборона %d", siege or 1)
	elseif mode == "raid" then
		return "Вторжение на чужой бур"
	end
	return string.format("Вылазка %d · %s", opIndex, opName)
end

-- Discovery rather than a second wealth leaderboard: rotate every two minutes, alternating
-- newcomers and the whole settlement. Stable id order means every online survivor gets a turn.
function Showcase.featured(hunters, rotation: number): number?
	local pool = {}
	for _, h in hunters do
		if rotation % 2 == 1 or h.newbie then
			table.insert(pool, h.id)
		end
	end
	if #pool == 0 then
		for _, h in hunters do
			table.insert(pool, h.id)
		end
	end
	if #pool == 0 then
		return nil
	end
	table.sort(pool)
	return pool[math.floor(rotation / 2) % #pool + 1]
end

return Showcase
