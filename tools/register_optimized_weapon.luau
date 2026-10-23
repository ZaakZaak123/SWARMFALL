-- Run this preparation function in Studio Edit mode after importing the FBX.
-- Bounds come from tools/measure_weapon_bounds.py. Keep baseline until validation passes.
return function(imported, baseline, bounds, triangles)
	local model = Instance.new("Model")
	model.Name = baseline.Name
	local count, maxCorrection = 0, 0
	for _, b in bounds do
		local old = baseline:FindFirstChild(b.name)
		local source = imported:FindFirstChild(b.name, true)
		assert(old and old:IsA("MeshPart") and source and source:IsA("MeshPart"), b.name)
		local mesh = source:Clone()
		local a, c = b.original_center, b.optimized_center
		-- FBX mesh axes are (-Blender X, Blender Z, Blender Y).
		local delta = Vector3.new(-(c[1] - a[1]), c[3] - a[3], c[2] - a[2])
		mesh.CFrame = old.CFrame * CFrame.new(delta)
		local s, n = b.original_size, b.optimized_size
		mesh.Size = Vector3.new(old.Size.X * n[1] / s[1], old.Size.Y * n[3] / s[3], old.Size.Z * n[2] / s[2])
		maxCorrection = math.max(maxCorrection, (mesh.Position - old.Position).Magnitude)
		assert(maxCorrection < 0.01, "Unexpected registration drift")
		mesh.Color, mesh.Material, mesh.TextureID = old.Color, old.Material, old.TextureID
		mesh.Anchored, mesh.Massless = true, true
		mesh.CanCollide, mesh.CanQuery, mesh.CanTouch, mesh.CastShadow = false, false, false, false
		mesh.CollisionFidelity = old.CollisionFidelity
		mesh.RenderFidelity = Enum.RenderFidelity.Automatic
		for key, value in old:GetAttributes() do
			mesh:SetAttribute(key, value)
		end
		assert(mesh.MeshId ~= old.MeshId, "Expected newly uploaded geometry")
		mesh.Parent = model
		count += 1
	end
	assert(count == #baseline:GetChildren(), "Animation group lost")
	model.WorldPivot = CFrame.identity
	model:SetAttribute("OptimizationVersion", 2)
	model:SetAttribute("TriangleCount", triangles)
	return model, { meshes = count, triangles = triangles, maxCenterCorrection = maxCorrection }
end
