-- Preserve Studio's native mesh serialization, including internal mesh data and bounds.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local bytes = fs.readFile("production/weapons/W01/assets/W01_native.rbxm")
local roots = roblox.deserializeModel(bytes)
assert(#roots == 1 and roots[1].Name == "W01", "Expected one W01 model")
local count = 0
for _, p in roots[1]:GetChildren() do
	assert(p:IsA("MeshPart"), "Unexpected W01 child")
	assert(p.MeshContent ~= nil and p.TextureContent ~= nil, "Missing imported asset reference")
	assert(p:GetAttribute("WeaponGroup") ~= nil, "Missing animation group")
	assert(not p.CanCollide and not p.CanTouch and not p.CanQuery, "Unsafe weapon collision")
	count += 1
end
assert(count == 6, "Expected six W01 meshes")
fs.writeFile("assets/weapon_models/W01.rbxm", bytes)
print("W01 native template: " .. count .. " meshes; original bytes preserved")
