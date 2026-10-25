--!strict
-- Permanent field research. Only confirmed squad kills enter the profile; spending DNA cannot
-- empty a tank. The registry also bounds what may enter another survivor's public showcase.
local Defs = require(script.Parent.Defs)

local Collection = {}
Collection.Order = {
	"EN_RUNNER",
	"EN_STALKER",
	"EN_SPITTER",
	"EN_BULWARK",
	"EN_BOMBER",
	"ELITE_CARRIER",
	"ELITE_BULWARK",
	"HIVE",
	"NODE",
	"ACID_SOURCE",
	"BOSS_BROODMOTHER",
	"BOSS_DEVOURER",
}
Collection.Stages =
	{ "Не встречен", "Образцы", "Силуэт", "Полный экземпляр", "Эталон" }

function Collection.count(research, kind: string): number
	local n = research and research[kind]
	return if type(n) == "number" and n == n then math.clamp(math.floor(n), 0, 1e9) else 0
end

function Collection.progress(kind: string, n: number)
	local thresholds = assert(Defs.Research[kind], "unknown specimen " .. kind)
	n = Collection.count({ [kind] = n }, kind)
	local stage = if n == 0 then 0 else 1 + Defs.researchStage(kind, n)
	local stops = { 0.06, 0.32, 0.65, 1 }
	local fill, previous, nextNeed = 1, 0, nil
	for i, target in thresholds do
		if n < target then
			fill = stops[i] + (stops[i + 1] - stops[i]) * (n - previous) / (target - previous)
			nextNeed = target
			break
		end
		previous = target
	end
	return { stage = stage, fill = fill, nextNeed = nextNeed, count = n, name = Collection.Stages[stage + 1] }
end

function Collection.public(research)
	local out = {}
	for _, kind in Collection.Order do
		local n = Collection.count(research, kind)
		if n > 0 then
			out[kind] = n
		end
	end
	return out
end

function Collection.summary(research)
	local found, complete, exemplary = 0, 0, 0
	for _, kind in Collection.Order do
		local p = Collection.progress(kind, Collection.count(research, kind))
		if p.stage > 0 then
			found += 1
		end
		if p.stage >= 3 then
			complete += 1
		end
		if p.stage == 4 then
			exemplary += 1
		end
	end
	return { found = found, complete = complete, exemplary = exemplary, total = #Collection.Order }
end

return Collection
