-- DD-112 stage 4: the Robux catalogue and its server side — products granted once per purchase id, passes
-- doubling xenite (not сплав) and adding mastery, nothing on sale while the Creator Hub ids are 0.
-- Usage: lune run tests/store

local process = require("@lune/process")
local H = require("./harness")

local function signal()
	return { Connect = function() end }
end
local byId = {}
H.stubs.DataStoreService = {
	GetDataStore = function()
		error("no DataStore in tests")
	end,
}
H.stubs.Players = {
	PlayerAdded = signal(),
	PlayerRemoving = signal(),
	GetPlayers = function()
		return {}
	end,
	GetPlayerByUserId = function(_, id)
		return byId[id]
	end,
}
H.stubs.RunService = {
	IsStudio = function()
		return true
	end,
}
local prompts = {}
H.stubs.MarketplaceService = {
	PromptGamePassPurchaseFinished = signal(),
	PromptGamePassPurchase = function(_, _p, id)
		table.insert(prompts, "pass:" .. id)
	end,
	PromptProductPurchase = function(_, _p, id)
		table.insert(prompts, "product:" .. id)
	end,
	UserOwnsGamePassAsync = function()
		return false
	end,
}

local Store = H.require("src/shared/Store")
local Profile = H.require("src/server/Profile")
local Shop = H.require("src/server/Shop")
local Enum = H.Enum

local failures = 0
local function check(ok: boolean, msg: string)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

-- the catalogue
local keys = {}
for _, key in Store.PassOrder do
	local p = Store.Passes[key]
	check(p ~= nil and p.key == key and p.price > 0, "pass " .. key .. " is in the catalogue")
	keys[key] = true
end
for _, key in Store.ProductOrder do
	local p = Store.Products[key]
	check(
		p ~= nil and p.key == key and p.amount > 0 and (p.kind == "scrap" or p.kind == "alloy") and not keys[key],
		"product " .. key .. " grants xenite or сплав"
	)
	keys[key] = true
end
-- DD-113: every card reads in a glance — a short big number, two words at most, a rarity colour
for _, list in { Store.Passes, Store.Products } do
	for key, item in list do
		local words = select(2, item.small:gsub("%S+", ""))
		check(
			#item.big > 0 and utf8.len(item.big) <= 5 and words <= 3 and item.rarity >= 1 and item.rarity <= 6,
			key .. ": big «" .. item.big .. "», " .. words .. " words, rarity " .. item.rarity
		)
	end
end
check(not Store.open(), "nothing on sale while the Creator Hub ids are 0 (the armory hides its shop)")

local pl = { UserId = 901, Name = "T901", Parent = true }
byId[901] = pl
Profile.load(pl)
local d = Profile.get(pl)
check(not Shop.prompt(pl, "XENITE_300"), "an item with id 0 cannot be prompted")
check(not Shop.prompt(pl, "NOPE"), "an unknown key is refused")

-- products: a stand-in id, granted once per purchase id
Store.Products.XENITE_300.id = 111
Store.Products.ALLOY_20.id = 222
check(Store.open() and Store.productById(111) == Store.Products.XENITE_300, "an id puts the item on sale")
check(Shop.prompt(pl, "XENITE_300") and prompts[#prompts] == "product:111", "the server prompts the real id")
d.scrap, d.alloy = 0, 0
local r1 = Shop.processReceipt({ PlayerId = 901, ProductId = 111, PurchaseId = "p-1" })
local r2 = Shop.processReceipt({ PlayerId = 901, ProductId = 111, PurchaseId = "p-1" })
check(
	r1 == Enum.ProductPurchaseDecision.PurchaseGranted and r2 == Enum.ProductPurchaseDecision.PurchaseGranted,
	"a receipt is granted (and again when Roblox repeats it)"
)
check(d.scrap == 300, "…but its xenite only once (" .. d.scrap .. ")")
Shop.processReceipt({ PlayerId = 901, ProductId = 222, PurchaseId = "p-2" })
check(d.alloy == 20 and d.scrap == 300, "the сплав pack adds сплав")
check(
	Shop.processReceipt({ PlayerId = 999, ProductId = 111, PurchaseId = "p-3" })
		== Enum.ProductPurchaseDecision.NotProcessedYet,
	"a player not in the server: not processed yet (Roblox retries)"
)
check(
	Shop.processReceipt({ PlayerId = 901, ProductId = 333, PurchaseId = "p-4" })
		== Enum.ProductPurchaseDecision.NotProcessedYet,
	"an unknown product id: not processed yet"
)
-- live: a profile that failed to load from the DataStore never takes goods (they would be lost)
H.stubs.RunService.IsStudio = function()
	return false
end
check(
	Shop.processReceipt({ PlayerId = 901, ProductId = 111, PurchaseId = "p-5" })
			== Enum.ProductPurchaseDecision.NotProcessedYet
		and d.scrap == 300,
	"live: an offline profile does not take a purchase (Roblox retries next session)"
)
H.stubs.RunService.IsStudio = function()
	return true
end
for i = 1, 70 do
	Profile.grantProduct(pl, "bulk-" .. i, Store.Products.ALLOY_20)
end
local n = 0
for _ in d.receipts do
	n += 1
end
check(n <= 60, "the purchase log keeps the newest 60 ids (" .. n .. ")")

-- passes: ×2 xenite (not сплав) and +50% mastery
Profile.passHook = Shop.owns
local function siegeWin(runId: string)
	return Profile.grantRun(pl, runId, {
		victory = true,
		reason = "",
		time = 200,
		level = 6,
		kills = 300,
		hive = "idle",
		op = "SIEGE",
		mode = "siege",
		siege = 2,
		threat = 1,
		components = {},
		players = {
			{
				id = 901,
				name = "T",
				kills = 300,
				weapon = "W_ARC_RIFLE",
				weaponKills = 200,
				species = {},
				alive = true,
			},
		},
	}, "SIEGE", 1)
end
local plain = siegeWin("s-1")
local kills0 = d.mastery.W_ARC_RIFLE or 0
Shop._grant(pl, "DOUBLE_XENITE")
Shop._grant(pl, "ARMORER")
local doubled = siegeWin("s-2")
check(doubled.total == plain.total * 2 and doubled.pass == 2, "«ДВОЙНОЙ КСЕНИТ»: ×2 xenite")
check(doubled.alloy == plain.alloy, "…сплав is not doubled")
check((d.mastery.W_ARC_RIFLE or 0) - kills0 == 300, "«ОРУЖЕЙНИК»: 200 kills count as 300 mastery")
check(Profile.public(pl).passes.DOUBLE_XENITE == true, "the public profile shows the owned pass")
check(not Shop.prompt(pl, "DOUBLE_XENITE"), "an owned pass is not offered again")

if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL STORE CHECKS PASSED")
