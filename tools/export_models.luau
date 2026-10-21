-- Exports weapon + creature part specs as JSON for offline rendering: lune run tools/export_models
local serde = require("@lune/serde")
local H = require("../tests/harness")
local Models = H.require("src/client/Models")
local Defs = H.require("src/shared/Defs")

local function pack(specs)
	local out = {}
	for _, s in specs do
		local c = { s.cf:GetComponents() }
		table.insert(out, {
			shape = s.shape,
			size = { s.size.X, s.size.Y, s.size.Z },
			cf = c,
			color = { math.floor(s.color.R * 255), math.floor(s.color.G * 255), math.floor(s.color.B * 255) },
			neon = s.mat == H.Enum.Material.Neon,
			t = s.transparency or 0,
		})
	end
	return out
end

local result = { weapons = {}, creatures = {} }
for _, id in Defs.WeaponOrder do
	table.insert(result.weapons, { name = id, parts = pack(Models.weaponSpec(id, false)) })
	table.insert(result.weapons, { name = id .. " EVO", parts = pack(Models.weaponSpec(id, true)) })
end
for kind = 1, 9 do
	table.insert(result.creatures, { name = Defs.EnemyByIndex[kind].id, parts = pack(Models.creatureSpec(kind)) })
end
print(serde.encode("json", result))
