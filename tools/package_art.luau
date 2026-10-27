-- Bake the full art manifest into the place so publishing includes mesh AND texture dependencies.
-- Runtime servers clone these templates instead of depending on 101 yielding asset requests.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Art = require("../tests/harness").require("src/shared/Art")
local bounds = require("@lune/serde").decode("json", fs.readFile("production/environment/art-bounds.json"))
local folder = roblox.Instance.new("Folder")
folder.Name = "ArtAssets"
local count = 0
for key, def in Art.Meshes do
	local p = roblox.Instance.new("MeshPart")
	p.Name = key
	p.MeshId = def.mesh
	p.TextureID = def.tex
	p.Size = def.size
	local native = assert(bounds[key], "Missing Studio mesh bounds: " .. key)
	p.InitialSize = roblox.Vector3.new(table.unpack(native))
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder
	count += 1
end
fs.writeDir("assets/art")
fs.writeFile("assets/art/ArtAssets.rbxm", roblox.serializeModel({ folder }))
print("Packaged", count, "mesh and texture pairs")
