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
	trophyLog: { [string]: any },
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
		add("SHELTER", "Первый свет", "pin", "Генератор добыт в первой вылазке")
	end
	if (d.saves or 0) >= 10 then
		add("SAVIOR", "Спаситель", "heart", "Союзников поднято: " .. (d.saves or 0))
	end
	local specimens = Collection.summary(d.research)
	if specimens.complete >= 5 then
		add(
			"NATURALIST",
			"Исследователь роя",
			"hive",
			"Полных экземпляров в коллекции: " .. specimens.complete
		)
	end
	if specimens.exemplary >= 3 then
		add(
			"CURATOR",
			"Хранитель коллекции",
			"star",
			"Эталонов в коллекции: " .. specimens.exemplary
		)
	end
	if won(d, "O03") then
		add("SCOURGE", "Гроза роя", "crosshair", "Тесла-вышка разряжена")
	end
	local home = d.home or {}
	local all = true
	for _, id in Meta.HomeOrder do
		if not home[id] then
			all = false
		end
	end
	if all then
		add("KEEPER", "Хозяин убежища", "heart", "Всё убежище восстановлено")
	end
	if best >= 3 then
		add(
			"SIEGE",
			"Страж бура · " .. best,
			"shield",
			"Оборона бура уровня " .. best .. " отбита"
		)
	end
	-- DD-088: the grove's mentors and the week's best
	if (d.mentor or 0) >= Meta.MentorTitle then
		add(
			"MENTOR",
			"Наставник рощи",
			"users",
			"Победы вместе с новичками: " .. (d.mentor or 0)
		)
	end
	local laurelTitles = {
		defense = { "WEEK_DEFENSE", "Защитник недели", "shield" },
		research = { "WEEK_RESEARCH", "Исследователь недели", "hive" },
		help = { "WEEK_HELP", "Помощник недели", "heart" },
	}
	for _, board in Meta.WeeklyBoards do
		local l = (d.laurels or {})[board]
		if type(l) == "table" and (l.n or 0) > 0 then
			local t = laurelTitles[board]
			add(
				t[1],
				t[2],
				t[3],
				"В тройке недели рощи: " .. Meta.WeeklyWords[board] .. " · " .. l.n .. " раз"
			)
		end
	end
	if won(d, "O05") then
		add(
			"BROOD",
			"Гроза Матери роя",
			"skull",
			"Мать роя повержена в вылазке 5"
		)
	end
	if won(d, "O07") then
		add("DEVOURER", "Пожиратель повержен", "crown", "Финал первой главы")
	end
	return out
end

-- The emblems a survivor may fly on the plot's flag (DD-089): each says something they did.
function Showcase.emblems(d): { { id: string, name: string, why: string, ok: boolean } }
	local specimens = Collection.summary(d.research)
	local laurel = false
	for _, l in d.laurels or {} do
		if type(l) == "table" and (l.n or 0) > 0 then
			laurel = true
		end
	end
	return {
		{ id = "pin", name = "Житель", why = "Есть у каждого", ok = true },
		{ id = "skull", name = "Альфа", why = "Победи Альфу в вылазке 1", ok = won(d, "O01") },
		{ id = "coil", name = "Тесла", why = "Пройди вылазку 3", ok = won(d, "O03") },
		{
			id = "hive",
			name = "Коллекция",
			why = "Собери 3 полных образца",
			ok = specimens.complete >= 3,
		},
		{
			id = "shield",
			name = "Бур",
			why = "Удержи бур на уровне 5",
			ok = ((d.outpost and d.outpost.best) or 0) >= 5,
		},
		{
			id = "heart",
			name = "Спаситель",
			why = "Подними союзников 10 раз",
			ok = (d.saves or 0) >= 10,
		},
		{
			id = "users",
			name = "Наставник",
			why = "Выиграй бой вместе с новичком",
			ok = (d.mentor or 0) >= 1,
		},
		{ id = "star", name = "Лавр", why = "Попади в тройку недели", ok = laurel },
		{ id = "crown", name = "Пожиратель", why = "Пройди главу 1", ok = won(d, "O07") },
	}
end

-- The flag as shown: a colour index and an earned emblem (an unearned one falls back to «Житель»).
function Showcase.banner(d): { color: number, emblem: string }
	local b = if type(d.banner) == "table" then d.banner else {}
	local color = math.clamp(math.floor(tonumber(b.color) or 1), 1, #Meta.BannerColors)
	local emblem = "pin"
	for _, e in Showcase.emblems(d) do
		if e.id == b.emblem and e.ok then
			emblem = e.id
		end
	end
	return { color = color, emblem = emblem }
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
		return "Страж бура · " .. best, "shield"
	elseif won(d, "O05") then
		return "Гроза Матери роя", "skull"
	elseif best >= 3 then
		return "Страж бура · " .. best, "shield"
	elseif won(d, "O03") then
		return "Гроза роя", "crosshair"
	elseif won(d, "O01") then
		return "Первый свет", "pin"
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
	if (d.mentor or 0) > 0 then
		table.insert(out, { "users", "Наставник · " .. d.mentor })
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
		trophyLog = (function() -- DD-087: when and with whom each boss fell (the plaque says it)
			local out = {}
			for op, log in d.trophyLog or {} do
				if type(log) == "table" and won(d, op) then
					out[op] = { t = log.t, team = log.team, with = log.with }
				end
			end
			return out
		end)(),
		banner = Showcase.banner(d), -- DD-089: the plot's flag
		decor = if d.decorOn and (d.decor or {})[d.decorOn] then d.decorOn else nil, -- DD-090: up on the plot
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
