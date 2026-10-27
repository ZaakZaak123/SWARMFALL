local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Art = require("./harness").require("src/shared/Art")
local bounds = require("@lune/serde").decode("json", fs.readFile("production/environment/art-bounds.json"))
local assets = roblox.deserializeModel(fs.readFile("assets/art/ArtAssets.rbxm"))[1]
local count = 0
for key, def in Art.Meshes do
	local p = assert(assets:FindFirstChild(key), "missing art template: " .. key)
	assert(
		p:IsA("MeshPart")
			and tostring(p.MeshContent):find(def.mesh, 1, true)
			and tostring(p.TextureContent):find(def.tex, 1, true),
		key .. ": wrong content"
	)
	assert(
		(p.Size - def.size).Magnitude < 0.001
			and (p.InitialSize - roblox.Vector3.new(table.unpack(bounds[key]))).Magnitude < 0.001,
		key .. ": wrong size"
	)
	assert(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery, key .. ": collision")
	count += 1
end
assert(#assets:GetChildren() == count, "unexpected obsolete art assets")
for _, project in { "default.project.json", "test.project.json" } do
	local json = require("@lune/serde").decode("json", fs.readFile(project))
	assert(json.tree.ReplicatedStorage.ArtAssets["$path"] == "assets/art/ArtAssets.rbxm", project .. ": missing art")
end
print("PASS", count, "packaged art templates, including all mesh and texture dependencies")
