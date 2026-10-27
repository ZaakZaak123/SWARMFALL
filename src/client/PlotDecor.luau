--!nonstrict
-- Seasonal decorations of a plot (DD-090): what a survivor brought home in a bright week of the Tree,
-- up in the yard for the neighbours to see. One builder for the own home (client/Base) and the
-- neighbours' (client/Settlement); everything in shelter coordinates through the plot's frame, light
-- and cheap (a few dozen parts, one emitter).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Settings = require(script.Parent.Settings)

local PlotDecor = {}

local rgb = Color3.fromRGB

local function part(parent: Instance, props): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- The runs the courtyard's string lights hang on (DD-057): bunker corners to the front lamps.
local RUNS = {
	{ Vector3.new(-7, 7.6, 21.5), Vector3.new(-32, 10.4, -20) },
	{ Vector3.new(7, 7.6, 21.5), Vector3.new(32, 10.4, -22) },
	{ Vector3.new(-32, 10.4, -20), Vector3.new(32, 10.4, -22) },
}

local function along(f: CFrame, a: Vector3, b: Vector3, step: number, sag: number, fn)
	local wa, wb = f:PointToWorldSpace(a), f:PointToWorldSpace(b)
	local n = math.max(2, math.floor((wb - wa).Magnitude / step))
	for k = 1, n - 1 do
		local t = k / n
		local p = wa:Lerp(wb, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
		fn(p, (wb - wa).Unit, k)
	end
end

local function wire(parent: Instance, f: CFrame, a: Vector3, b: Vector3, sag: number)
	local prev = nil
	along(f, a, b, 3, sag, function(p)
		if prev then
			part(parent, {
				Name = "Wire",
				Size = Vector3.new(0.06, 0.06, (p - prev).Magnitude),
				CFrame = CFrame.lookAt((p + prev) / 2, p),
				Color = rgb(36, 32, 28),
				Material = Enum.Material.SmoothPlastic,
			})
		end
		prev = p
	end)
end

local BUILD = {}

BUILD.LANTERNS = function(folder: Folder, f: CFrame)
	local colors = { rgb(255, 92, 70), rgb(255, 176, 64), rgb(255, 228, 120), rgb(255, 120, 160) }
	for r, run in RUNS do
		wire(folder, f, run[1], run[2], 2.4)
		along(f, run[1], run[2], 3.6, 2.4, function(p, _, k)
			local lamp = part(folder, {
				Name = "PaperLantern",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.1, 0.9, 0.9),
				CFrame = CFrame.new(p - Vector3.new(0, 0.75, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = colors[(k + r) % #colors + 1],
				Material = Enum.Material.Neon,
			})
			if k % 4 == 0 and Settings.quality > 1 then
				local l = Instance.new("PointLight")
				l.Color = lamp.Color
				l.Range = 9
				l.Brightness = 0.7
				l.Shadows = false
				l.Parent = lamp
			end
		end)
	end
end

BUILD.BUNTING = function(folder: Folder, f: CFrame)
	local colors = { rgb(255, 64, 92), rgb(255, 204, 70), rgb(86, 238, 230), rgb(198, 255, 66), rgb(182, 124, 255) }
	for r, run in RUNS do
		wire(folder, f, run[1], run[2], 2)
		along(f, run[1], run[2], 1.6, 2, function(p, dir, k)
			local w = Instance.new("WedgePart")
			w.Name = "Pennant"
			w.Anchored = true
			w.CanCollide = false
			w.CanQuery = false
			w.CanTouch = false
			w.CastShadow = false
			w.Size = Vector3.new(0.06, 1.1, 1)
			-- a downward triangle hanging off the line, broadside to the line's direction
			w.CFrame = CFrame.lookAt(p, p + dir) * CFrame.new(0, -0.55, 0) * CFrame.Angles(math.pi, 0, 0)
			w.Color = colors[(k + r) % #colors + 1]
			w.Material = Enum.Material.Fabric
			w.Parent = folder
		end)
	end
end

BUILD.FLOWERS = function(folder: Folder, f: CFrame)
	local petals = { rgb(255, 120, 160), rgb(255, 214, 90), rgb(190, 140, 255), rgb(255, 255, 255), rgb(255, 128, 60) }
	local rng = Random.new(5)
	-- beds along the road to the gate and by the bunker's door
	local beds = { { -8, -18 }, { 8, -20 }, { -8, -30 }, { 8, -32 }, { -6, 24 }, { 6, 24 } }
	for b, xz in beds do
		local base = f * CFrame.new(xz[1], 0.15, xz[2])
		part(folder, {
			Name = "Bed",
			Size = Vector3.new(3.4, 0.3, 5),
			CFrame = base,
			Color = rgb(92, 64, 44),
			Material = Enum.Material.Ground,
		})
		for k = 1, 12 do
			local p = base * CFrame.new(rng:NextNumber(-1.4, 1.4), 0.35, rng:NextNumber(-2.2, 2.2))
			part(folder, {
				Name = "Stem",
				Size = Vector3.new(0.12, 0.7, 0.12),
				CFrame = p * CFrame.new(0, 0.35, 0),
				Color = rgb(70, 140, 60),
				Material = Enum.Material.Grass,
			})
			part(folder, {
				Name = "Bloom",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * rng:NextNumber(0.45, 0.65),
				CFrame = p * CFrame.new(0, 0.75, 0),
				Color = petals[(k + b) % #petals + 1],
				Material = Enum.Material.SmoothPlastic,
			})
		end
	end
end

BUILD.FIREFLIES = function(folder: Folder, f: CFrame)
	for _, xz in { { -16, 6 }, { 16, 4 }, { 0, -18 } } do
		local anchor = part(folder, {
			Name = "Fireflies",
			Size = Vector3.new(16, 4, 16),
			CFrame = f * CFrame.new(xz[1], 4, xz[2]),
			Transparency = 1,
		})
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(rgb(214, 255, 120))
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Transparency = NumberSequence.new(0.1)
		e.Lifetime = NumberRange.new(3, 5)
		e.Rate = if Settings.quality > 1 then 6 else 2
		e.Speed = NumberRange.new(0.4, 1.2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, 0.15, 0)
		e.Parent = anchor
	end
end

-- Build decoration `id` for the plot frame `f` into a new folder under `parent` (nil when unknown).
function PlotDecor.build(id: string?, f: CFrame, parent: Instance): Folder?
	local fn = id and BUILD[id]
	if not fn then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "Decor_" .. id
	fn(folder, f)
	folder.Parent = parent
	return folder
end

local _ = Shared
return PlotDecor
