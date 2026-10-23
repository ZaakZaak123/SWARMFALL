--!nonstrict
-- Imported Blender W01. Template coordinates: right +X, up +Y, muzzle -Z.
-- Only the base rifle uses this asset; Thunderlord keeps its existing evolution model.
local ArcRifleMesh = {}

local function part(name, size, cf, anchored)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Transparency = 1
	p.Anchored = anchored
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	return p
end

function ArcRifleMesh.build(anchored: boolean, scale: number?): (Model, any)
	local k = scale or 1
	local assets = game:GetService("ReplicatedStorage"):WaitForChild("WeaponAssets")
	local template = assets:WaitForChild("W01")
	local model = Instance.new("Model")
	model.Name = "W_ARC_RIFLE"
	model:SetAttribute("VisualAsset", "W01_Blender_optimized_v2")
	local root = part("Root", Vector3.one * 0.2, CFrame.identity, anchored)
	root.Parent = model
	model.PrimaryPart = root
	local groups = {}
	local function attach(p, group)
		p.Anchored = anchored
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		if not anchored then
			local base = root
			if group and group ~= "body" then
				base = groups[group]
				if not base then
					base = part("Group_" .. group, Vector3.one * 0.2, CFrame.identity, false)
					base.Parent = model
					local motor = Instance.new("Motor6D")
					motor.Name = "Motor_" .. group
					motor.Part0, motor.Part1 = root, base
					motor.Parent = root
					groups[group] = base
				end
			end
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = base, p
			weld.Parent = p
		end
		p.Parent = model
	end
	for _, source in template:GetChildren() do
		if source:IsA("MeshPart") then
			local mesh = source:Clone()
			mesh.Size = source.Size * k
			mesh.CFrame = CFrame.new(source.Position * k) * source.CFrame.Rotation
			attach(mesh, source:GetAttribute("WeaponGroup"))
		end
	end
	-- Dynamic indicators cover the baked cyan windows. Dark backing keeps empty cells dark.
	local cyan = Color3.fromRGB(84, 238, 255)
	for index = 1, 3 do
		local cf = CFrame.new(0, -0.18 - (index - 1) * 0.13, -1.11)
		local backing = part("CellBacking" .. index, Vector3.new(0.465, 0.084, 0.20) * k, CFrame.new(cf.Position * k), anchored)
		backing.Transparency = 0
		backing.Color = Color3.fromRGB(8, 12, 18)
		backing.Material = Enum.Material.SmoothPlastic
		attach(backing, "mag")
		local light = part("Cell" .. index, Vector3.new(0.48, 0.075, 0.19) * k, CFrame.new(cf.Position * k), anchored)
		light.Transparency = 0
		light.Material = Enum.Material.Neon
		light.Color = cyan
		attach(light, "mag")
	end
	local heat = part("Heat", Vector3.new(0.065, 0.012, 1.25) * k, CFrame.new(Vector3.new(0, 0.912, -2.27) * k), anchored)
	heat.Transparency = 0.55
	heat.Material = Enum.Material.Neon
	heat.Color = cyan
	attach(heat)
	local muzzlePosition = Vector3.new(0, 0.5, -4.25)
	local muzzle = part("Muzzle", Vector3.one * 0.05, CFrame.new(muzzlePosition * k), anchored)
	attach(muzzle)
	return model, {
		grip = Vector3.new(0, -0.22, 0.1),
		fore = Vector3.new(0, 0, -1.99),
		eject = Vector3.new(0.46, 0.55, -0.2),
		mag = Vector3.new(0, -0.35, -1.11),
		boltHandle = Vector3.new(0.46, 0.55, -0.2),
		muzzle = muzzlePosition,
		pivots = { coil = Vector3.new(0, 0.5, -2.27) },
		prongTips = { Vector3.new(0, 0.64, -4.25), Vector3.new(0, 0.36, -4.25) },
	}
end

return ArcRifleMesh
