--!nonstrict
-- The shelter's ground and daylight (DD-057). The home is a green grove far from the crater
-- (Meta.HomeOrigin): leafy grass, old concrete paths, low wooded hills closing the view. Everything you
-- walk past (the shelter, trees, ruins, the restored spots) is drawn by the client (client/Base) so it
-- can show each hunter their own home; the server only owns the terrain and the light.
-- Lighting is per server: the home light while the squad is between runs, the arena's during a run.

local Lighting = game:GetService("Lighting")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Meta = require(Shared:WaitForChild("Meta"))

local Home = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local O = Meta.HomeOrigin

-- Terrain is wiped by every arena rebuild (Arena.paintTerrain clears it), so this runs after each one.
function Home.build()
	local terrain = workspace.Terrain
	-- materials the crater does not use, so their colours are ours
	terrain:SetMaterialColor(M.LeafyGrass, rgb(104, 160, 68))
	terrain:SetMaterialColor(M.Concrete, rgb(150, 146, 136))
	terrain:SetMaterialColor(M.Pavement, rgb(126, 122, 112))
	terrain:SetMaterialColor(M.Rock, rgb(96, 98, 92))
	-- the grove floor: surface at Y = 0 (a half-filled top voxel, see DD-049)
	terrain:FillBlock(CFrame.new(O.X, -7, O.Z), Vector3.new(320, 10, 320), M.LeafyGrass)
	-- old concrete: the courtyard slab and the road out through the gate (south)
	local function slab(cx: number, cz: number, sx: number, sz: number, mat)
		local min = Vector3.new(O.X + cx - sx / 2, -4, O.Z + cz - sz / 2)
		local max = Vector3.new(O.X + cx + sx / 2, 0, O.Z + cz + sz / 2)
		terrain:ReplaceMaterial(Region3.new(min, max):ExpandToGrid(4), 4, M.LeafyGrass, mat)
	end
	slab(0, 4, 36, 28, M.Concrete)
	slab(0, -40, 12, 56, M.Pavement)
	slab(-2, -16, 8, 12, M.Pavement)
	-- wooded hills close the grove on every side but the road
	local rng = Random.new(31)
	for i = 1, 26 do
		local a = (i / 26) * math.pi * 2
		local south = math.abs(a - math.pi * 1.5) < 0.22
		local r = rng:NextNumber(98, 126) + (if south then 40 else 0)
		local size = rng:NextNumber(30, 46)
		terrain:FillBall(Vector3.new(O.X + math.cos(a) * r, -size * 0.45, O.Z + math.sin(a) * r), size, M.LeafyGrass)
		if i % 3 == 0 then
			terrain:FillBall(Vector3.new(O.X + math.cos(a) * (r + 10), -size * 0.3, O.Z + math.sin(a) * (r + 10)), size * 0.6, M.Rock)
		end
	end
end

-- Clouds live under Terrain; the arena's lighting pass does not know about them.
function Home.clearClouds()
	for _, c in workspace.Terrain:GetChildren() do
		if c:IsA("Clouds") then
			c:Destroy()
		end
	end
end

-- Afternoon sun over the grove: warm light, soft blue haze, the plain sky of our own world.
function Home.lighting()
	Home.clearClouds()
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 3.2
	Lighting.Ambient = rgb(112, 108, 98)
	Lighting.OutdoorAmbient = rgb(150, 152, 138)
	Lighting.ColorShift_Top = rgb(255, 238, 205)
	Lighting.ColorShift_Bottom = rgb(40, 50, 30)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ExposureCompensation = 0.1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") or c:IsA("Clouds") then
			c:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.1
	atmosphere.Color = rgb(200, 216, 226)
	atmosphere.Decay = rgb(110, 140, 120)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.Parent = Lighting
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Color = rgb(255, 252, 245)
	clouds.Parent = workspace.Terrain
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	bloom.Intensity = 0.4
	bloom.Size = 20
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Brightness = 0.02
	cc.Contrast = 0.08
	cc.Saturation = 0.12
	cc.TintColor = rgb(255, 248, 236)
	cc.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.08
	rays.Spread = 0.5
	rays.Parent = Lighting
end

return Home
