--!strict
-- DD-112 stage 4: what Robux buys — speed, style and stock, never power the game does not also give. No
-- random paid rewards. One catalogue for the server (Shop) and the armory's «МАГАЗИН» tab.
--
-- `id` is the Creator Hub id (a game pass id for Passes, a developer product id for Products); 0 = not made
-- yet: the item is hidden and cannot be bought. Prices are what to set in the Creator Hub (Robux). `icon`: an
-- Icons name, or "xenite" for the crystal the purse shows.

local Store = {}

-- DD-113: a card is read in a glance — `big` (the number), `small` (two words), the rarity colour, a `badge`.
-- `name` and `text` stay for the purchase's own words (the Roblox prompt shows the Creator Hub name).
export type Pass = {
	key: string,
	id: number,
	name: string,
	text: string,
	price: number,
	icon: string,
	big: string,
	small: string,
	rarity: number,
	badge: string?,
}
export type Product = {
	key: string,
	id: number,
	name: string,
	text: string,
	price: number,
	icon: string,
	kind: string, -- "scrap" | "alloy"
	amount: number,
	big: string,
	small: string,
	rarity: number,
	badge: string?,
}

Store.Passes = {
	DOUBLE_XENITE = {
		key = "DOUBLE_XENITE",
		id = 0,
		name = "ДВОЙНОЙ КСЕНИТ",
		text = "×2 ксенита за каждый бой. Сплав не удваивается.",
		price = 249,
		icon = "xenite",
		big = "×2",
		small = "КСЕНИТА ЗА БОЙ",
		rarity = 5,
		badge = "НАВСЕГДА",
	},
	ARMORER = {
		key = "ARMORER",
		id = 0,
		name = "ОРУЖЕЙНИК",
		text = "+50% мастерства: модули и эволюция откроются раньше.",
		price = 199,
		icon = "star",
		big = "+50%",
		small = "МАСТЕРСТВА",
		rarity = 5,
		badge = "НАВСЕГДА",
	},
} :: { [string]: Pass }
Store.PassOrder = { "DOUBLE_XENITE", "ARMORER" }

Store.Products = {
	XENITE_300 = {
		key = "XENITE_300",
		id = 0,
		name = "300 КСЕНИТА",
		text = "Горсть руды с чужого бура.",
		price = 49,
		icon = "xenite",
		kind = "scrap",
		amount = 300,
		big = "300",
		small = "КСЕНИТА",
		rarity = 2,
	},
	XENITE_1000 = {
		key = "XENITE_1000",
		id = 0,
		name = "1000 КСЕНИТА",
		text = "Ящик руды: модуль и ещё на постройку.",
		price = 149,
		icon = "xenite",
		kind = "scrap",
		amount = 1000,
		big = "1000",
		small = "КСЕНИТА",
		rarity = 3,
		badge = "ХИТ",
	},
	XENITE_3000 = {
		key = "XENITE_3000",
		id = 0,
		name = "3000 КСЕНИТА",
		text = "Вагонетка руды.",
		price = 399,
		icon = "xenite",
		kind = "scrap",
		amount = 3000,
		big = "3000",
		small = "КСЕНИТА",
		rarity = 4,
		badge = "ВЫГОДНО",
	},
	ALLOY_20 = {
		key = "ALLOY_20",
		id = 0,
		name = "20 СПЛАВА",
		text = "Слиток на модуль II.",
		price = 49,
		icon = "core",
		kind = "alloy",
		amount = 20,
		big = "20",
		small = "СПЛАВА",
		rarity = 3,
	},
	ALLOY_70 = {
		key = "ALLOY_70",
		id = 0,
		name = "70 СПЛАВА",
		text = "Слитки на модуль III.",
		price = 149,
		icon = "core",
		kind = "alloy",
		amount = 70,
		big = "70",
		small = "СПЛАВА",
		rarity = 4,
		badge = "ВЫГОДНО",
	},
} :: { [string]: Product }
Store.ProductOrder = { "XENITE_300", "XENITE_1000", "XENITE_3000", "ALLOY_20", "ALLOY_70" }

-- DD-112: what the passes do (Profile.grantRun)
Store.XeniteMult = 2
Store.MasteryMult = 1.5

function Store.configured(item: { id: number }?): boolean
	return item ~= nil and item.id > 0
end

-- Anything on sale at all (the armory shows its «МАГАЗИН» tab only then).
function Store.open(): boolean
	for _, key in Store.PassOrder do
		if Store.configured(Store.Passes[key]) then
			return true
		end
	end
	for _, key in Store.ProductOrder do
		if Store.configured(Store.Products[key]) then
			return true
		end
	end
	return false
end

function Store.productById(id: number): Product?
	for _, p in Store.Products do
		if p.id > 0 and p.id == id then
			return p
		end
	end
	return nil
end

return Store
