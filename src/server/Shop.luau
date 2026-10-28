--!strict
-- DD-112 stage 4: Robux. Game passes (owned once, checked on join and on purchase) and developer products
-- (xenite and сплав packs, granted once per purchase id through Profile.grantProduct). The catalogue and the
-- Creator Hub ids live in shared/Store; an id of 0 is not on sale. Purchases are prompted by the server on
-- the client's request, so a client cannot name an arbitrary product.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Store = require(Shared:WaitForChild("Store"))
local Profile = require(script.Parent.Profile)

local Shop = {}

local owned: { [Player]: { [string]: boolean } } = {}
local onChange: ((Player) -> ())? = nil

function Shop.owns(player: Player, key: string): boolean
	local o = owned[player]
	return o ~= nil and o[key] == true
end

-- Tests and Studio checks: pretend a pass is owned.
function Shop._grant(player: Player, key: string, on: boolean?)
	owned[player] = owned[player] or {}
	owned[player][key] = on ~= false
end

local function refresh(player: Player)
	local o = owned[player] or {}
	owned[player] = o
	for _, key in Store.PassOrder do
		local pass = Store.Passes[key]
		if Store.configured(pass) and not o[key] then
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.id)
			o[key] = ok and has == true
		end
	end
	if onChange then
		onChange(player)
	end
end

-- The client asked to buy something by its catalogue key: the server prompts the real id.
function Shop.prompt(player: Player, key: string): boolean
	local pass = Store.Passes[key]
	if pass then
		if not Store.configured(pass) or Shop.owns(player, key) then
			return false
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
		return true
	end
	local product = Store.Products[key]
	if product and Store.configured(product) then
		MarketplaceService:PromptProductPurchase(player, product.id)
		return true
	end
	return false
end

-- Exposed for tests: the receipt decision without the engine callback.
function Shop.processReceipt(info): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local product = Store.productById(info.ProductId)
	if not player or not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local result = Profile.grantProduct(player, tostring(info.PurchaseId), product)
	if result == "granted" then
		if onChange then
			onChange(player)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- changed(player): push the profile (owned passes are part of its public view)
function Shop.init(changed: (Player) -> ())
	onChange = changed
	Profile.passHook = Shop.owns
	MarketplaceService.ProcessReceipt = Shop.processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, bought: boolean)
		if not bought then
			return
		end
		for _, key in Store.PassOrder do
			if Store.Passes[key].id == passId then
				owned[player] = owned[player] or {}
				owned[player][key] = true
			end
		end
		changed(player)
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(refresh, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(refresh, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		owned[player] = nil
	end)
end

return Shop
