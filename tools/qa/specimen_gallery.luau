-- Install as a temporary ModuleScript in ReplicatedStorage; require it from the client after art
-- loading. Tests its own isolated gallery, never the player's real profile or home.
return function()
	local Players = game:GetService("Players")
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local Collection = require(Shared.Collection)
	local Defs = require(Shared.Defs)
	local Gallery = require(Players.LocalPlayer.PlayerScripts.Client.SpecimenGallery)
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "CodexGalleryQA", workspace
	local g = Gallery.new(CFrame.new(0, 0, 2200), folder, function()
		return nil
	end, function() end)
	local checks = {}
	local function check(ok, text)
		assert(ok, text)
		table.insert(checks, text)
	end
	local ok, err = pcall(function()
		g:update({}, true)
		check(next(g.tanks) == nil and g.deck.Transparency == 1, "no undiscovered tanks or empty platform")
		g:update({ EN_SPITTER = 60 }, true)
		local spitter = g.tanks.EN_SPITTER
		check(spitter and spitter.stage == 2, "silhouette stage")
		local content, height = spitter.content, spitter.liquid.Size.X
		g:update({ EN_SPITTER = 100 }, true)
		check(spitter.content == content and spitter.liquid.Size.X > height, "fill grows without rebuilding a specimen")
		g:update({ EN_SPITTER = 140 }, true)
		check(spitter.stage == 3 and spitter.content ~= content, "full specimen at milestone")
		local all = {}
		for _, kind in Collection.Order do
			all[kind] = Defs.Research[kind][3]
		end
		g:update(all, true)
		local count = 0
		for _, t in g.tanks do
			count += 1
			check(t.stage == 4 and math.abs(t.liquid.Size.X - 4.9) < 1e-5, "exemplary " .. t.model.Name)
		end
		check(count == 12, "all twelve species instantiate")
		g:update({ EN_RUNNER = 10 }, true)
		check(
			g.tanks.EN_SPITTER == nil and g.tanks.EN_RUNNER.stage == 1 and g.tanks.EN_RUNNER.specimen == nil,
			"owner switch removes old specimens"
		)
		g:update({}, true)
		check(next(g.tanks) == nil and #folder:GetChildren() == 1, "clear leaves only the reusable deck")
	end)
	folder:Destroy()
	assert(ok, err)
	return { ok = true, checks = checks }
end
