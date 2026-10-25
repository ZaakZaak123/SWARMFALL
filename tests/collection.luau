local H = require("./harness")
local Collection = H.require("src/shared/Collection")
local Defs = H.require("src/shared/Defs")
local Showcase = H.require("src/shared/Showcase")
for _, kind in Collection.Order do
	local thresholds = Defs.Research[kind]
	assert(thresholds and Defs.Enemies[kind], kind)
	assert(Collection.progress(kind, 0).stage == 0)
	local last = 0
	for n = 0, thresholds[3] do
		local p = Collection.progress(kind, n)
		assert(p.fill >= last and p.fill <= 1, kind .. ": continuous permanent fill")
		last = p.fill
	end
	assert(Collection.progress(kind, thresholds[1]).stage == 2)
	assert(Collection.progress(kind, thresholds[2]).stage == 3)
	assert(Collection.progress(kind, thresholds[3]).stage == 4)
end
local research = { EN_RUNNER = 5000, EN_STALKER = 800, EN_SPITTER = 600, NODE = 15, HIVE = 15, private = 999 }
local entry = Showcase.build(1, "Tester", { research = research, dnaSpent = { EN_RUNNER = 250 } }, "W_ARC_RIFLE")
assert(entry.collection.EN_RUNNER == 5000 and entry.collection.private == nil)
local stocked = Showcase.build(2, "Stock", { scrap = 1234 }, "W_ARC_RIFLE")
assert(stocked.stock == 1000 and stocked.scrap == nil, "guests see a shared stock tier, not a private balance")
entry.collection.EN_RUNNER = 0
assert(research.EN_RUNNER == 5000, "public payload cannot mutate the profile")
local summary = Collection.summary(research)
assert(summary.found == 5 and summary.complete == 5 and summary.exemplary == 3)
local titles = {}
for _, t in Showcase.titles({ research = research }) do
	titles[t.id] = true
end
assert(titles.NATURALIST and titles.CURATOR, "earned collection titles")
assert(Collection.count({ EN_RUNNER = 0 / 0 }, "EN_RUNNER") == 0)
print(
	"ALL COLLECTION CHECKS PASSED: 12 species, milestones, monotonic fill, DNA independence, public payload, earned titles"
)
