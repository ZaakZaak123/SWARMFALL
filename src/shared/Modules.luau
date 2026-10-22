--!strict
-- Permanent weapon modules (D03 §3, 03_GAME_DATA module branches): 4 weapons × 3 branches A/B/C × tiers
-- I/II/III = 36 modules. Before a run a weapon takes 1 CORE + up to 1 ADAPTER from another branch; the
-- ADAPTER is at most tier II; tier III is CORE only. Owning a module does nothing until it is equipped.
--
-- Effects reuse the tested card system (DD-010): `ranks` add virtual card ranks capped by the shared rank
-- limit III (no slot used, no double procs — the same proc budget applies), `mods` are small stat tweaks.

local Modules = {}

export type ModuleDef = {
	id: string,
	weapon: string,
	branch: string, -- "A" | "B" | "C"
	branchName: string,
	tier: number, -- 1..3
	name: string,
	text: string,
	cost: number,
	mastery: number, -- weapon mastery rank needed to craft
	ranks: { [string]: number },
	mods: { [string]: number },
}

Modules.All = {} :: { [string]: ModuleDef }
Modules.ByWeapon = {} :: { [string]: { ModuleDef } }

local COST = { 160, 400, 700 }
local MASTERY = { 2, 8, 15 }
local ROMAN = { "I", "II", "III" }
Modules.Roman = ROMAN

local function add(weapon: string, branch: string, branchName: string, tiers)
	for tier, t in tiers do
		local id = string.format("MOD_%s_%s%d", weapon:sub(3), branch, tier)
		local def: ModuleDef = {
			id = id,
			weapon = weapon,
			branch = branch,
			branchName = branchName,
			tier = tier,
			name = t[1],
			text = t[2],
			cost = t.cost or COST[tier],
			mastery = t.mastery or MASTERY[tier],
			ranks = t.ranks or {},
			mods = t.mods or {},
		}
		Modules.All[id] = def
		Modules.ByWeapon[weapon] = Modules.ByWeapon[weapon] or {}
		table.insert(Modules.ByWeapon[weapon], def)
	end
end

-- Дуговая винтовка
add("W_ARC_RIFLE", "A", "Расщепление", {
	{ "Двойная катушка", "Второй слабый разряд рядом с основным", ranks = { UPG_MULTISHOT = 1 }, cost = 260, mastery = 4 },
	{ "Фокусировка", "Кучнее и сильнее каждый разряд", mods = { spreadMult = 0.7, damageMult = 1.1 } },
	{ "Тройной резонанс", "Два дополнительных разряда", ranks = { UPG_MULTISHOT = 2 } },
})
add("W_ARC_RIFLE", "B", "Проводимость", {
	{ "Искровая цепь", "Попадания перескакивают на соседей", ranks = { UPG_CHAIN = 1 } },
	{ "Живая сеть", "Цепь длиннее и чаще", ranks = { UPG_CHAIN = 2 } },
	{ "Грозовая связка", "Цепь + рикошет разрядов", ranks = { UPG_CHAIN = 2, UPG_RICOCHET = 1 } },
})
add("W_ARC_RIFLE", "C", "Конденсатор", {
	{ "Заряд от попаданий", "+10% скорострельность", mods = { rateMult = 1.1 } },
	{ "Разрядная остановка", "Попадания замедляют врагов", ranks = { UPG_FREEZE = 1 }, mods = { rateMult = 1.1 } },
	{ "Выпуск энергии", "Серии убийств детонируют", ranks = { UPG_DETONATE = 1 }, mods = { rateMult = 1.1 } },
})
-- Вулкан
add("W_SCATTERGUN", "A", "Широкий залп", {
	{ "Шире сектор", "+1 дробина, шире конус", mods = { pelletsAdd = 1, spreadMult = 1.2 } },
	{ "Распределение дробин", "+2 дробины", mods = { pelletsAdd = 2 } },
	{ "Второй конус", "Боковой залп + 2 дробины", ranks = { UPG_MULTISHOT = 1 }, mods = { pelletsAdd = 2 } },
})
add("W_SCATTERGUN", "B", "Кинетика", {
	{ "Реакция слабых целей", "Сильнее отбрасывание", mods = { knockMult = 1.6 } },
	{ "Контролируемое отбрасывание", "Отброс + шоковый рывок", ranks = { UPG_DASH_SHOCK = 1 }, mods = { knockMult = 1.8 } },
	{ "Силовая волна", "Сильный шоковый рывок", ranks = { UPG_DASH_SHOCK = 2 }, mods = { knockMult = 2 } },
})
add("W_SCATTERGUN", "C", "Термокамера", {
	{ "Поджог вблизи", "Дробь поджигает", ranks = { UPG_IGNITE = 1 } },
	{ "Локальная детонация", "Поджог + детонация", ranks = { UPG_IGNITE = 1, UPG_DETONATE = 1 } },
	{ "Огненная полоса", "Сильный поджог + детонация", ranks = { UPG_IGNITE = 2, UPG_DETONATE = 1 } },
})
-- Лучемёт «Разлом»
add("W_PLASMA_BEAM", "A", "Копьё", {
	{ "Длинная линия", "Луч пробивает ещё одну цель", mods = { pierceAdd = 1 } },
	{ "Эффективная линия", "+2 пробития, +5% урона", mods = { pierceAdd = 2, damageMult = 1.05 } },
	{ "Продольный импульс", "Пробитие + дальность", ranks = { UPG_PIERCE = 2 }, mods = { rangeMult = 1.15 } },
})
add("W_PLASMA_BEAM", "B", "Призма", {
	{ "Боковой луч", "Слабый второй луч", ranks = { UPG_MULTISHOT = 1 } },
	{ "Конфигурация", "Второй луч + дальность", ranks = { UPG_MULTISHOT = 1 }, mods = { rangeMult = 1.1 } },
	{ "Разделение", "Два боковых луча", ranks = { UPG_MULTISHOT = 2 } },
})
add("W_PLASMA_BEAM", "C", "Теплоконтур", {
	{ "Управляемый перегрев", "−20% нагрев", mods = { heatMult = 0.8 } },
	{ "Сброс энергии", "−30% нагрев, коррозия", ranks = { UPG_CORRODE = 1 }, mods = { heatMult = 0.7 } },
	{ "Импульс остывания", "−30% нагрев, сильная коррозия", ranks = { UPG_CORRODE = 2 }, mods = { heatMult = 0.7 } },
})
-- Рельсотрон
add("W_RAILGUN", "A", "Прошивка", {
	{ "Ещё одна цель", "+1 пробитие", mods = { pierceAdd = 1 } },
	{ "Меньше потерь", "+1 пробитие, меньше потерь урона", mods = { pierceAdd = 1, falloffAdd = 0.08 } },
	{ "Линейный заряд", "Сильное пробитие", ranks = { UPG_PIERCE = 2 } },
})
add("W_RAILGUN", "B", "Прицельный удар", {
	{ "Слабые зоны", "Критические попадания", ranks = { UPG_CRIT = 1 } },
	{ "Частичный заряд", "Криты + скорострельность", ranks = { UPG_CRIT = 1 }, mods = { rateMult = 1.1 } },
	{ "Точный заряд", "Сильные криты", ranks = { UPG_CRIT = 2 } },
})
add("W_RAILGUN", "C", "Разлом брони", {
	{ "Снижение брони", "Попадания разъедают броню", ranks = { UPG_CORRODE = 1 } },
	{ "Срыв подготовки", "Коррозия + замедление", ranks = { UPG_CORRODE = 1, UPG_FREEZE = 1 } },
	{ "Тыловой импульс", "Сильная коррозия + замедление", ranks = { UPG_CORRODE = 2, UPG_FREEZE = 1 } },
})

function Modules.get(id: string?): ModuleDef?
	return if id then Modules.All[id] else nil
end

-- Loadout rules: CORE any tier; ADAPTER tier <= II from a different branch of the same weapon.
function Modules.validLoadout(weapon: string, core: string?, adapter: string?): boolean
	local c, a = Modules.get(core), Modules.get(adapter)
	if core and (not c or c.weapon ~= weapon) then
		return false
	end
	if adapter then
		if not a or a.weapon ~= weapon or a.tier > 2 then
			return false
		end
		if c and c.branch == a.branch then
			return false
		end
	end
	return true
end

-- Merges the virtual card ranks of an equipped loadout (each family capped at III by Combat).
function Modules.ranksFor(core: string?, adapter: string?): { [string]: number }
	local out = {}
	for _, id in { core, adapter } do
		local m = Modules.get(id)
		if m then
			for k, v in m.ranks do
				out[k] = (out[k] or 0) + v
			end
		end
	end
	return out
end

return Modules
