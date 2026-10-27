--!nonstrict
-- The grove's ground and daylight (DD-057 → DD-087). The settlement is a green grove far from the crater
-- (Meta.HomeOrigin = the old Tree): leafy grass, old concrete paths, low wooded hills closing the view.
-- Everything you walk past (the shelters, trees, ruins, the square's posts) is drawn by the clients
-- (client/Base for the own home, client/Settlement for the rest); the server only owns the terrain, the
-- light and the seats in the cabins (DD-093).
-- Lighting is per server: the home light while the squad is between runs, the arena's during a run.

local Lighting = game:GetService("Lighting")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Meta = require(Shared:WaitForChild("Meta"))
local Grove = require(Shared:WaitForChild("Grove"))
local Layout = require(Shared:WaitForChild("ShelterLayout"))
local Portal = require(script.Parent.Portal)

local Home = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local O = Meta.HomeOrigin

-- Terrain is wiped by every arena rebuild (Arena.paintTerrain clears it), so this runs after each one.
-- DD-087: the whole grove — the square under the Tree, a road from it to every plot's gate, each plot's
-- courtyard, a hill with the old metro's mouth between each two plots, wooded hills round the edge.
function Home.build()
	local terrain = workspace.Terrain
	-- materials the crater does not use, so their colours are ours
	terrain:SetMaterialColor(M.LeafyGrass, rgb(104, 160, 68))
	terrain:SetMaterialColor(M.Concrete, rgb(150, 146, 136))
	terrain:SetMaterialColor(M.Pavement, rgb(126, 122, 112))
	terrain:SetMaterialColor(M.Cobblestone, rgb(132, 124, 112))
	-- the grove floor: surface at Y = 0 (a half-filled top voxel, see DD-049)
	terrain:FillBlock(CFrame.new(O.X, -7, O.Z), Vector3.new(760, 10, 760), M.LeafyGrass)
	-- paving only recolours the grass (same ground, no steps): cell by cell under a turned rectangle
	local done = {}
	local function pave(f: CFrame, cx: number, cz: number, sx: number, sz: number, mat)
		for x = -sx / 2, sx / 2, 3 do
			for z = -sz / 2, sz / 2, 3 do
				local w = f:PointToWorldSpace(Vector3.new(cx + x, 0, cz + z))
				local gx, gz = math.floor(w.X / 4), math.floor(w.Z / 4)
				local key = gx * 100000 + gz
				if done[key] ~= mat then
					done[key] = mat
					local min = Vector3.new(gx * 4, -4, gz * 4)
					terrain:ReplaceMaterial(Region3.new(min, min + Vector3.new(4, 4, 4)), 4, M.LeafyGrass, mat)
					if mat ~= M.LeafyGrass then
						terrain:ReplaceMaterial(Region3.new(min, min + Vector3.new(4, 4, 4)), 4, M.Pavement, mat)
					end
				end
			end
		end
	end
	local centre = CFrame.new(O.X, 0, O.Z)
	-- the square: cobbles round the edge, flagstones inside
	for r = Grove.PlazaRadius + 3, 2, -3 do
		local mat = if r > Grove.PlazaRadius - 3 then M.Cobblestone else M.Pavement
		local n = math.max(8, math.floor(r * 2 * math.pi / 3))
		for k = 1, n do
			local a = k / n * math.pi * 2
			pave(centre, math.cos(a) * r, math.sin(a) * r, 1, 1, mat)
		end
	end
	for i = 1, Grove.Plots do
		local f = Grove.frame(i)
		-- the courtyard slab and the road out through the gate, then on to the square
		pave(f, 0, 4, 36, 28, M.Concrete)
		pave(f, 0, -40, 12, 56, M.Pavement)
		pave(f, -2, -16, 8, 12, M.Pavement)
		local toSquare = Grove.Radius - Grove.PlazaRadius - 66
		pave(f, 0, -68 - toSquare / 2, 10, toSquare + 6, M.Pavement)
		-- the hill with the metro's mouth (DD-091): the hill rises behind the portal, the shoulders
		-- flank a cutting in front of it, the bore runs in (server/Portal); the client stands the portal
		-- on it (client/Cableway.cave)
		local c = Layout.Cave
		Portal.dig(
			f:PointToWorldSpace(Vector3.new(c.x, 0, c.z)),
			f:VectorToWorldSpace(Vector3.new(c.fx, 0, c.fz)),
			true,
			M.LeafyGrass,
			M.LeafyGrass
		)
	end
	-- wooded hills close the grove on every side
	local rng = Random.new(31)
	for i = 1, 30 do
		local a = (i / 30) * math.pi * 2
		local r = rng:NextNumber(300, 336)
		local size = rng:NextNumber(36, 54)
		terrain:FillBall(Vector3.new(O.X + math.cos(a) * r, -size * 0.45, O.Z + math.sin(a) * r), size, M.LeafyGrass)
		if i % 3 == 0 then
			terrain:FillBall(
				Vector3.new(O.X + math.cos(a) * (r + 12), -size * 0.3, O.Z + math.sin(a) * (r + 12)),
				size * 0.6,
				M.Rock
			)
		end
	end
end

-- DD-093: the seats in every plot's cabin. Real Seats on the server, so a survivor sitting at the table
-- is seen sitting by everyone (a client's own Seat would sit nobody); invisible, under the chairs the
-- clients draw (client/Cabin). Touch is off — walking past a chair must not sit you down — a prompt sits.
function Home.furnish()
	if workspace:FindFirstChild("GroveSeats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "GroveSeats"
	for i = 1, Grove.Plots do
		local f = Grove.frame(i)
		for k, s in Layout.Cabin.seats do
			local seat = Instance.new("Seat")
			seat.Name = "Seat" .. i .. "_" .. k
			seat.Size = Vector3.new(1.8, 0.4, 1.8)
			seat.CFrame = f * Layout.cabinSeat(s)
			seat.Anchored = true
			seat.CanCollide = false
			seat.CanTouch = false
			seat.CanQuery = false
			seat.Transparency = 1
			seat.CastShadow = false
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Сесть"
			prompt.ObjectText = s[5]
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 5.5
			prompt.RequiresLineOfSight = false
			prompt.UIOffset = Vector2.new(0, 30)
			prompt.Parent = seat
			prompt.Triggered:Connect(function(player: Player)
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if not hum or not root or hum.Health <= 0 or seat.Occupant or hum.SeatPart then
					return
				end
				if (root.Position - seat.Position).Magnitude > 9 then
					return
				end
				seat:Sit(hum)
			end)
			seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				prompt.Enabled = seat.Occupant == nil
			end)
			seat.Parent = folder
		end
	end
	folder.Parent = workspace
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
