--!strict
-- DD-112 stage 3: a gun's evolution is earned. Opening it (once, in the armory) lets it fire in the fight
-- (Combat.checkEvolve); the permanent form starts every fight evolved. One rule for the server, the
-- armory, the goals and the defeat tip. `d` is a profile or its public view (weapons, components,
-- mastery, scrap, alloy, evoOpen, forms).

local Defs = require(script.Parent.Defs)

local Evolve = {}

function Evolve.of(wid: string)
	local w = Defs.Weapons[wid]
	return if w then Defs.Evolutions[w.evolution] else nil
end

local function rank(d, wid: string): number
	return Defs.masteryRank(wid, (d.mastery or {})[wid] or 0)
end

-- (ok, why): why = "open" (done) | "weapon" | "component" | "mastery" | "scrap" | "alloy"
function Evolve.canOpen(d, wid: string): (boolean, string?)
	local evo = Evolve.of(wid)
	if not evo or not (d.weapons or {})[wid] then
		return false, "weapon"
	elseif (d.evoOpen or {})[wid] then
		return false, "open"
	elseif not (d.components or {})[evo.component] then
		return false, "component"
	elseif rank(d, wid) < Defs.Evolve.OpenMastery then
		return false, "mastery"
	elseif (d.scrap or 0) < Defs.Evolve.OpenCost then
		return false, "scrap"
	elseif (d.alloy or 0) < Defs.Evolve.OpenAlloy then
		return false, "alloy"
	end
	return true, nil
end

-- (ok, why): why = "made" | "weapon" | "closed" (the evolution is not opened) | "mastery" | "scrap" | "alloy"
function Evolve.canForm(d, wid: string): (boolean, string?)
	local evo = Evolve.of(wid)
	if not evo or not (d.weapons or {})[wid] then
		return false, "weapon"
	elseif (d.forms or {})[evo.id] then
		return false, "made"
	elseif not (d.evoOpen or {})[wid] then
		return false, "closed"
	elseif rank(d, wid) < Defs.FormMastery then
		return false, "mastery"
	elseif (d.scrap or 0) < Defs.Evolve.FormCost then
		return false, "scrap"
	elseif (d.alloy or 0) < Defs.Evolve.FormAlloy then
		return false, "alloy"
	end
	return true, nil
end

-- Where a gun's evolution component comes from, in words (the armory's hint when it is missing).
Evolve.ComponentFrom = {
	CMP_STORM_CORE = "Альфа в вылазке 1",
	CMP_FLAME_HEART = "первая победа в вылазке 6",
	CMP_VOID_HEART = "первая победа над Пожирателем",
	CMP_LINE_BREACH = "испытание рельсотрона: выстрелы насквозь",
}

return Evolve
