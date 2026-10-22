-- W01 model sheet: base + evolved arc rifle from the camera angles the game actually uses.
-- lune run tools/w01_views > build/w01_views.json ; python tools/render_scene.py build/w01_views.json build/previews/w01_model.png
local serde = require("@lune/serde")
local H = require("../tests/harness")
local Models = H.require("src/client/Models")

local function pack(specs)
	local out = {}
	for _, s in specs do
		table.insert(out, {
			shape = s.shape,
			size = { s.size.X, s.size.Y, s.size.Z },
			cf = { s.cf:GetComponents() },
			color = { math.floor(s.color.R * 255), math.floor(s.color.G * 255), math.floor(s.color.B * 255) },
			neon = s.mat == H.Enum.Material.Neon,
			t = s.transparency or 0,
		})
	end
	return out
end

local ANGLES = {
	{ "правый бок", -math.pi / 2, -0.05 },
	{ "левый бок", math.pi / 2, -0.05 },
	{ "3/4 (вид от 3-го лица)", -2.3, -0.35 },
	{ "сверху (тактическая камера)", -math.pi / 2, -1.45 },
}
local views = {}
for _, evolved in { false, true } do
	local parts = pack((Models.weaponSpec("W_ARC_RIFLE", evolved)))
	for _, a in ANGLES do
		table.insert(views, {
			name = (if evolved then "ГРОМОВЕРЖЕЦ · " else "ДУГА · ") .. a[1] .. " · " .. #parts .. " дет.",
			parts = parts,
			yaw = a[2],
			pitch = a[3],
		})
	end
end
print(serde.encode("json", { views = views, cols = 4, cell = 420 }))
