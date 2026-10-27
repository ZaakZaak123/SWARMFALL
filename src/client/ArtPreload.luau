--!nonstrict
-- Server template readiness does not mean a phone has downloaded its meshes and textures.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Art = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Art"))
local ArtPreload = { ready = false }
local fails = {} -- "id status" of what the preload could not fetch

-- DD-100: the owner's phone has no developer console, so the game itself shows the creator what the
-- device managed to fetch: a small panel for a minute after the preload, refreshed every 2 s, with the
-- fetch status of every environment mesh and texture (and the failing ids). Only for the place's
-- creator (or in Studio); other players never see it.
local function fetchCounts()
	local counts = { mesh = {}, tex = {} }
	local bad = {}
	local seen = {}
	for key, def in Art.Meshes do
		for kind, id in { mesh = def.mesh, tex = def.tex } do
			if id and id ~= "" and not seen[id] then
				seen[id] = true
				local ok, st = pcall(ContentProvider.GetAssetFetchStatus, ContentProvider, id)
				local name = if ok then st.Name else "Error"
				counts[kind][name] = (counts[kind][name] or 0) + 1
				if name ~= "Success" and #bad < 6 then
					table.insert(bad, kind .. " " .. key .. " " .. id:match("%d+$") .. " " .. name)
				end
			end
		end
	end
	local function line(c)
		local t = {}
		for k, v in c do
			table.insert(t, k .. " " .. v)
		end
		table.sort(t)
		return table.concat(t, ", ")
	end
	return line(counts.mesh), line(counts.tex), bad
end

local function showReport()
	local Players = game:GetService("Players")
	local me = Players.LocalPlayer
	local creator = game.CreatorType == Enum.CreatorType.User and me.UserId == game.CreatorId
	if not (creator or game:GetService("RunService"):IsStudio()) then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "ArtReport"
	g.ResetOnSpawn = false
	g.DisplayOrder = 60
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local t = Instance.new("TextButton")
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0, 4)
	t.Size = UDim2.fromOffset(560, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.BackgroundColor3 = Color3.fromRGB(12, 10, 18)
	t.BackgroundTransparency = 0.15
	t.TextColor3 = Color3.fromRGB(230, 255, 200)
	t.Font = Enum.Font.Code
	t.TextSize = 12
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.AutoButtonColor = false
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	pad.Parent = t
	t.Parent = g
	t.Activated:Connect(function()
		g:Destroy()
	end)
	g.Parent = me:WaitForChild("PlayerGui")
	local t0 = os.clock()
	while g.Parent and os.clock() - t0 < 60 do
		local mesh, tex, bad = fetchCounts()
		local quality = "?"
		pcall(function()
			quality = UserSettings().GameSettings.SavedQualityLevel.Name
		end)
		local mem = math.floor(game:GetService("Stats"):GetTotalMemoryUsageMb())
		t.Text = string.format(
			"МОДЕЛИ (видно только создателю, тап — закрыть)\nпредзагрузка: %d ошибок %s\nмеши: %s\nтекстуры: %s\nграфика %s · память %d МБ\n%s",
			#fails,
			table.concat(fails, "; "):sub(1, 160),
			mesh,
			tex,
			quality,
			mem,
			table.concat(bad, "\n")
		)
		task.wait(2)
	end
	g:Destroy()
end

function ArtPreload.start()
	task.spawn(function()
		-- Raw URI strings are fetched as images; mesh URIs then fail with a type mismatch.
		-- Instances preserve the content type for both MeshContent and TextureContent.
		local folder = ReplicatedStorage:WaitForChild("ArtAssets", 10)
			or ReplicatedStorage:WaitForChild("ArtTemplates", 10)
		local ids = if folder then folder:GetChildren() else {}
		if folder and folder.Name == "ArtAssets" then
			-- A folder can replicate before its children, especially during a mobile join.
			local expected = 0
			for _ in Art.Meshes do
				expected += 1
			end
			local started = os.clock()
			while #folder:GetChildren() < expected and os.clock() - started < 15 do
				task.wait(0.1)
			end
			ids = folder:GetChildren()
		end
		if folder and folder.Name == "ArtTemplates" then
			local started = os.clock()
			while not folder:GetAttribute("Ready") and os.clock() - started < 15 do
				task.wait(0.1)
			end
			ids = folder:GetChildren()
		end
		local pending, failures = 0, 0
		for first = 1, #ids, 16 do
			local batch = {}
			for i = first, math.min(first + 15, #ids) do
				table.insert(batch, ids[i])
			end
			pending += 1
			task.spawn(function()
				local ok, err = pcall(function()
					ContentProvider:PreloadAsync(batch, function(id, status)
						if status ~= Enum.AssetFetchStatus.Success then
							failures += 1
							table.insert(fails, (tostring(id):match("%d+$") or tostring(id)) .. " " .. status.Name)
							warn("[SPOREFALL] client art fetch failed", id, status.Name)
						end
					end)
				end)
				if not ok then
					failures += #batch
					warn("[SPOREFALL] client art preload failed", err)
				end
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
		ArtPreload.ready = true
		ReplicatedStorage:SetAttribute("ClientArtReady", true)
		ReplicatedStorage:SetAttribute("ClientArtFailures", failures)
		print(string.format("[SPOREFALL] client art: %d assets, %d failures, %d pending", #ids, failures, pending))
		showReport()
	end)
end

return ArtPreload
