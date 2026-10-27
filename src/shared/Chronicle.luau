--!strict
-- The grove's chronicle and signs (DD-087), as pure rules: what a survivor's deeds look like to the
-- neighbours (a line in the chronicle when something new is done), the status on their sign, and the
-- fixed quick signals. The server keeps the state (server/Neighbors); tests/grove walks these.

local Collection = require(script.Parent.Collection)
local Defs = require(script.Parent.Defs)
local Goals = require(script.Parent.Goals)
local Meta = require(script.Parent.Meta)
local Ops = require(script.Parent.Ops)

local Chronicle = {}

-- Fixed phrases (no player text: everyone can see them, chat on or off). wave = the hero waves.
Chronicle.Signals = {
	{ text = "Привет!", icon = "users", wave = true },
	{ text = "Пойдём вместе?", icon = "swords" },
	{ text = "Круто!", icon = "star" },
	{ text = "Спасибо!", icon = "heart" },
	{ text = "Подожди минутку", icon = "timer" },
	{ text = "Иду!", icon = "play" },
	{ text = "Ого, как у тебя!", icon = "eye" },
	{ text = "Пока!", icon = "pin", wave = true },
}
Chronicle.SignalGap = 2.5 -- seconds between two signals of one survivor

-- What the chronicle compares between two looks at a profile.
export type Summary = {
	won: { [string]: boolean },
	stages: { [string]: number }, -- specimen stage per kind (Collection.progress)
	siege: number,
	home: { [string]: boolean },
	mentor: number,
}

function Chronicle.summary(d): Summary
	local won = {}
	for op, n in (d.wins_by_op or {}) do
		if (n or 0) > 0 then
			won[op] = true
		end
	end
	local stages = {}
	for _, kind in Collection.Order do
		stages[kind] = Collection.progress(kind, Collection.count(d.research, kind)).stage
	end
	return {
		won = won,
		stages = stages,
		siege = (d.outpost and d.outpost.best) or 0,
		home = table.clone(d.home or {}),
		mentor = d.mentor or 0,
	}
end

-- New deeds between `before` and `after`, as chronicle lines { icon, text, big } (big = a boss, a
-- milestone: worth a toast for everyone). newcomer: this was their first win at all.
function Chronicle.diff(before: Summary, after: Summary, name: string): { { icon: string, text: string, big: boolean } }
	local out = {}
	local function add(icon: string, text: string, big: boolean)
		table.insert(out, { icon = icon, text = text, big = big })
	end
	for _, op in Ops.Order do
		if after.won[op] and not before.won[op] then
			local def = Ops.get(op)
			if op == "O01" then
				add("skull", name .. " — первая Альфа повержена", true)
			elseif op == "O05" then
				add("skull", name .. " — Мать роя повержена", true)
			elseif op == "O07" then
				add("crown", name .. " — Пожиратель повержен, глава пройдена", true)
			elseif op ~= "CA01" then
				add(
					"pin",
					string.format(
						"%s — вылазка %d «%s» пройдена",
						name,
						def.index,
						Goals.titleCase(def.name)
					),
					false
				)
			end
		end
	end
	if after.siege > before.siege and after.siege >= 2 then
		add(
			"shield",
			string.format("%s — бур удержан на уровне %d", name, after.siege),
			after.siege % 5 == 0
		)
	end
	for _, kind in Collection.Order do
		local was, now = before.stages[kind] or 0, after.stages[kind] or 0
		local enemy = Defs.Enemies[kind]
		local species = if enemy then Goals.titleCase(enemy.name) else kind
		if now >= 4 and was < 4 then
			add("star", string.format("%s — эталон в коллекции: %s", name, species), true)
		elseif now >= 3 and was < 3 then
			add("hive", string.format("%s — полный образец: %s", name, species), false)
		end
	end
	-- DD-088: a veteran won beside a newcomer
	local was, now = before.mentor or 0, after.mentor or 0
	if now >= Meta.MentorTitle and was < Meta.MentorTitle then
		add("users", name .. " — теперь Наставник рощи", true)
	elseif now > was then
		add("users", name .. " — победа вместе с новичком", false)
	end
	for _, id in Meta.HomeOrder do
		if after.home[id] and not before.home[id] and not Meta.Home[id].free then
			add(
				Meta.Home[id].icon,
				string.format("%s — восстановлено: %s", name, Goals.titleCase(Meta.Home[id].name)),
				false
			)
		end
	end
	return out
end

-- The line on a survivor's sign and under their name (DD-087 §5), by priority.
-- s: { away = op name?, launching = bool, ready = bool, open = bool, squadWith = name?, guestOf = name?,
--      square = bool, idle = bool, fire = bool }
function Chronicle.status(s): (string, string)
	if s.away then
		return "away", "В вылазке · " .. s.away
	elseif s.launching then
		return "go", "Выходит в бой"
	elseif s.ready then
		return "ready", "Собирается в бой"
	elseif s.open then
		return "open", "Ищет напарника"
	elseif s.squadWith then
		return "squad", "В отряде с " .. s.squadWith
	elseif s.guestOf then
		return "guest", "В гостях у " .. s.guestOf
	elseif s.idle then
		return "idle", "Отошёл"
	elseif s.square then
		return "square", "На площади"
	end
	return "home", "Дома"
end

-- When a trophy was won, said on its plaque (DD-087 §8). log: { t, threat, team, with = { names } }.
function Chronicle.provenance(log, now: number): string
	if type(log) ~= "table" or type(log.t) ~= "number" then
		return "Трофей добыт"
	end
	local months = {
		"янв.",
		"февр.",
		"марта",
		"апр.",
		"мая",
		"июня",
		"июля",
		"авг.",
		"сент.",
		"окт.",
		"нояб.",
		"дек.",
	}
	local date = os.date("!*t", log.t) :: any
	local when = string.format("%d %s", date.day, months[date.month])
	if now - log.t < 86400 and now >= log.t then
		when = "сегодня"
	end
	local who = "в одиночку"
	local with = if type(log.with) == "table" then log.with else {}
	if #with > 0 then
		who = "в отряде: " .. table.concat(with, ", ", 1, math.min(#with, 3))
	elseif (log.team or 1) > 1 then
		who = "в отряде из " .. tostring(log.team)
	end
	return string.format("Добыт %s · %s", when, who)
end

return Chronicle
