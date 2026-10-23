-- Dev-only: sync Maps + Arena from the local http server and rebuild the crater in the Edit DataModel.
-- loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8765/tools/studio_arena.luau"))()("MAP_REACTOR_YARD")
local HttpService = game:GetService("HttpService")
return function(mapId: string?)
	local sync = loadstring(HttpService:GetAsync("http://127.0.0.1:8765/tools/studio_sync.luau?t=" .. os.clock(), true))()
	sync({ "src/shared/Maps.luau", "src/server/Arena.luau" })
	local server = game.ServerScriptService.Server
	local maps = require(game.ReplicatedStorage.Shared.Maps:Clone())
	local mod = server.Arena:Clone()
	mod.Parent = server
	local t = os.clock()
	local ok, err = pcall(function()
		require(mod).build(maps.get(mapId or "MAP_REACTOR_YARD"))
	end)
	mod:Destroy()
	local n = 0
	local arena = workspace:FindFirstChild("Arena")
	if arena then
		for _, d in arena:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
	end
	return string.format("%s %s %.2fs parts=%d", tostring(ok), tostring(err), os.clock() - t, n)
end
