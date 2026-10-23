--!nonstrict
-- Native Blender mesh template in weapon coordinates: right X, up Y, muzzle -Z.
local VulcanMesh = {}

function VulcanMesh.build(anchored: boolean, scale: number?): (Model, any)
	local k = scale or 1
	local template = game:GetService("ReplicatedStorage"):WaitForChild("WeaponAssets"):WaitForChild("W02")
	local model = Instance.new("Model")
	model.Name = "W_SCATTERGUN"
	model:SetAttribute("VisualAsset", "W02_Blender_optimized_v2")
	local function invisible(name)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.one * 0.05
		p.Transparency = 1
		p.Anchored = anchored
		p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
		p.CastShadow, p.Massless = false, true
		p.Parent = model
		return p
	end
	local root = invisible("Root")
	model.PrimaryPart = root
	local pump
	if not anchored then
		pump = invisible("Group_pump")
		local motor = Instance.new("Motor6D")
		motor.Name = "Motor_pump"
		motor.Part0, motor.Part1 = root, pump
		motor.Parent = root
	end
	local function weld(p, base)
		if not anchored then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = base, p
			w.Parent = p
		end
	end
	for _, source in template:GetChildren() do
		if source:IsA("MeshPart") then
			local mesh = source:Clone()
			mesh.Size = source.Size * k
			mesh.CFrame = CFrame.new(source.Position * k) * source.CFrame.Rotation
			mesh.Anchored = anchored
			mesh.CanCollide, mesh.CanTouch, mesh.CanQuery = false, false, false
			mesh.CastShadow, mesh.Massless = false, true
			mesh.Parent = model
			weld(mesh, if source:GetAttribute("WeaponGroup") == "pump" then pump else root)
		end
	end
	local muzzlePosition = Vector3.new(0, 0.47, -3.875)
	local muzzle = invisible("Muzzle")
	muzzle.CFrame = CFrame.new(muzzlePosition * k)
	weld(muzzle, root)
	return model,
		{
			grip = Vector3.new(0, -0.22, 0.1),
			fore = Vector3.new(0, -0.2, -1.65),
			eject = Vector3.new(0.44, 0.45, -0.55),
			mag = Vector3.new(0, -0.15, -1.0),
			muzzle = muzzlePosition,
		}
end

return VulcanMesh
