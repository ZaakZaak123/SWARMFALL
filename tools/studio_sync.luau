-- Dev-only live sync for Studio (Edit DataModel): pulls changed source files from the local
-- `python -m http.server 8765` in the repo root and writes them into the matching scripts.
-- Usage from MCP execute_luau:
--   loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8765/tools/studio_sync.luau"))()({ "src/client/Hud.luau", ... })
local HttpService = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8765/"

local ROOTS = {
	{ "src/shared/", function() return game.ReplicatedStorage:FindFirstChild("Shared") end },
	{ "src/server/", function() return game.ServerScriptService:FindFirstChild("Server") end },
	{ "src/client/", function() return game.StarterPlayer.StarterPlayerScripts:FindFirstChild("Client") end },
	{ "src/startercharacter/", function() return game.StarterPlayer.StarterCharacterScripts end },
}

-- Every .luau under src/ (walks the http.server directory listings).
local function listAll(): { string }
	local out = {}
	local function walk(dir: string)
		local html = HttpService:GetAsync(BASE .. dir .. "?t=" .. os.clock(), true)
		for href in html:gmatch('href="([^"]+)"') do
			if href:sub(-1) == "/" then
				walk(dir .. href)
			elseif href:sub(-5) == ".luau" then
				table.insert(out, dir .. href)
			end
		end
	end
	walk("src/")
	return out
end

return function(files: { string }?)
	files = files or listAll()
	local done = {}
	for _, path in files do
		local parent, rel
		for _, r in ROOTS do
			if path:sub(1, #r[1]) == r[1] then
				parent, rel = r[2](), path:sub(#r[1] + 1)
			end
		end
		assert(parent, "no root for " .. path)
		local parts = string.split(rel, "/")
		for i = 1, #parts - 1 do
			local f = parent:FindFirstChild(parts[i])
			if not f then
				f = Instance.new("Folder")
				f.Name = parts[i]
				f.Parent = parent
			end
			parent = f
		end
		local file = parts[#parts]
		local name, class = file:match("^(.-)%.server%.luau$"), "Script"
		if not name then
			name, class = file:match("^(.-)%.client%.luau$"), "LocalScript"
		end
		if not name then
			name, class = file:match("^(.-)%.luau$"), "ModuleScript"
		end
		local src = HttpService:GetAsync(BASE .. path .. "?t=" .. os.clock(), true)
		local inst = parent:FindFirstChild(name)
		if inst and inst.ClassName ~= class then
			inst:Destroy()
			inst = nil
		end
		if not inst then
			inst = Instance.new(class)
			inst.Name = name
			inst.Parent = parent
		end
		inst.Source = src
		table.insert(done, name .. ":" .. #src)
	end
	return table.concat(done, " ")
end
