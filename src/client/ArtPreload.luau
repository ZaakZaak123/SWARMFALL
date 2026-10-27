--!nonstrict
-- Server template readiness does not mean a phone has downloaded its meshes and textures.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Art = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Art"))
local ArtPreload = { ready = false }

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
	end)
end

return ArtPreload
