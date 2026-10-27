-- Extract native imported meshes from the local authoring place, preserving
-- InitialSize, MeshContent, UVs and the rest of Studio's mesh serialization.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local place = roblox.deserializePlace(fs.readFile("build/xenite/import-workspace.rbxlx"))
local folder = assert(place:GetService("ReplicatedStorage"):FindFirstChild("XeniteAssets"))
fs.writeDir("assets/xenite")
for _, name in { "Shard", "Cluster" } do
	local model = assert(folder:FindFirstChild(name))
	assert(model.PrimaryPart ~= nil, "Ground pivot missing")
	assert(#model:GetChildren() == 2, "Expected body and vein")
	for _, p in model:GetChildren() do
		assert(p:IsA("MeshPart") and p.MeshContent ~= nil)
		assert(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch)
	end
	fs.writeFile("assets/xenite/" .. name .. ".rbxm", roblox.serializeModel({ model }))
	print(name, model:GetAttribute("TriangleCount"), "triangles, 2 native MeshParts")
end
