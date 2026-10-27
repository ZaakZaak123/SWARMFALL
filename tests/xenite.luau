-- Native art contract: cheap meshes, stable ground pivot, safe decorations.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local manifest = serde.decode("json", fs.readFile("production/xenite/asset-manifest.json"))
local geometry = serde.decode("json", fs.readFile("production/xenite/geometry.json"))
for name, budget in { Shard = 160, Cluster = 600 } do
	local roots = roblox.deserializeModel(fs.readFile("assets/xenite/" .. name .. ".rbxm"))
	assert(#roots == 1 and roots[1].Name == name)
	local m = roots[1]
	assert(#m:GetChildren() == 2 and m.PrimaryPart == m:FindFirstChild("Body"))
	local pivot = m.PrimaryPart.CFrame * m.PrimaryPart.PivotOffset
	assert(pivot.Position.Magnitude < 1e-5, "Ground pivot drift")
	local count = 0
	for _, p in m:GetChildren() do
		local art = manifest.meshes[name .. p.Name]
		assert(p:IsA("MeshPart") and tostring(p.MeshContent):find(art.id, 1, true))
		assert(p.Anchored and p.Massless and not p.CanCollide and not p.CanTouch and not p.CanQuery)
		assert(p.Transparency == 0 and p.Size.Y < 4, "Import scale or opacity wrong")
		assert((p.InitialSize / p.Size - roblox.Vector3.one * 100).Magnitude < 0.01, "Native import bounds lost")
		assert(art.triangles == #geometry[name .. p.Name].triangles)
		count += art.triangles
	end
	assert(count <= budget and m:GetAttribute("TriangleCount") == count)
	assert(m.Body.Material == roblox.Enum.Material.SmoothPlastic)
	assert(tostring(m.Body.TextureContent):find(manifest.meshes[name .. "Body"].texture, 1, true))
	assert(m.Vein.Material == roblox.Enum.Material.Neon and m.Vein:FindFirstChildWhichIsA("PointLight"))
	print(name, count, "triangles: native assets, ground pivot and collision flags PASS")
end
