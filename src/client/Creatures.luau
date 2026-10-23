--!nonstrict
-- Creature blueprints: part specs for every enemy kind (by Defs index). Used by EnemyView (pooled,
-- animated, BulkMoveTo) and by Models.creature (static previews in UI viewports).
-- Spec: { size, cf (local to root, root faces -Z), color, mat, shape?, role?, hip?, loc?, phase?, transparency?, seg? }

local rgb = Color3.fromRGB
local M = Enum.Material

local Creatures = {}

-- Each spec: { size, offset CFrame, color, material, shape?, role?, hip?, side?, phase?, transparency? }
local function ball(d, cf, color, mat, role)
	return {
		size = Vector3.one * d,
		cf = cf,
		color = color,
		mat = mat or M.SmoothPlastic,
		shape = Enum.PartType.Ball,
		role = role,
	}
end
local function blk(size, cf, color, mat, role)
	return { size = size, cf = cf, color = color, mat = mat or M.SmoothPlastic, role = role }
end
local function leg(size, hip, local_, color, phase, mat)
	return {
		size = size,
		cf = hip * local_,
		hip = hip,
		loc = local_,
		color = color,
		mat = mat or M.SmoothPlastic,
		role = "leg",
		phase = phase,
	}
end
local A = CFrame.Angles
local P = CFrame.new

local BLUEPRINT = {}
Creatures.Blueprints = BLUEPRINT

-- Blender meshes (assets/enemy_models, built by assets/models/<kind>/build_*.py). Template coordinates
-- are the imported FBX: head -Z, feet at Y=0, creature origin at ROOT. Missing asset -> part blueprint.
local templates = nil
local function template(name: string): Model?
	if templates == nil then
		templates = game:GetService("ReplicatedStorage"):WaitForChild("EnemyAssets", 5) or false
	end
	return templates and templates:FindFirstChild(name) or nil
end

local RUNNER_ROOT = Vector3.new(0, 0, -4.8336)
local RUNNER_SCALE = 0.85
-- part -> colour, material, role; legs -> hip (template space, relative to ROOT) and gait phase
local RUNNER_MESH = {
	Shell = { rgb(245, 100, 50), M.SmoothPlastic, "body" },
	Flesh = { rgb(120, 38, 30), M.SmoothPlastic, "body" },
	Head = { rgb(150, 50, 32), M.SmoothPlastic, "body" },
	Mandibles = { rgb(235, 215, 170), M.SmoothPlastic },
	Eyes = { rgb(255, 230, 90), M.Neon, "eye" },
	LegFL = { rgb(95, 32, 26), M.SmoothPlastic, nil, Vector3.new(0.62, 1.4, -0.7), 0 },
	LegFR = { rgb(95, 32, 26), M.SmoothPlastic, nil, Vector3.new(-0.62, 1.4, -0.7), math.pi },
	LegBL = { rgb(95, 32, 26), M.SmoothPlastic, nil, Vector3.new(0.62, 1.4, 0.45), math.pi },
	LegBR = { rgb(95, 32, 26), M.SmoothPlastic, nil, Vector3.new(-0.62, 1.4, 0.45), 0 },
}

local function runnerMesh()
	local model = template("EN_RUNNER")
	if not model then
		return nil
	end
	local s = {}
	for _, mp in model:GetChildren() do
		local info = RUNNER_MESH[mp.Name]
		if not (info and mp:IsA("MeshPart")) then
			continue
		end
		local centre = (mp.Position - RUNNER_ROOT) * RUNNER_SCALE
		local spec =
			{ mesh = mp, size = mp.Size * RUNNER_SCALE, cf = P(centre), color = info[1], mat = info[2], role = info[3] }
		if info[4] then
			local hip = info[4] * RUNNER_SCALE
			spec.role = "leg"
			spec.hip = P(hip)
			spec.loc = P(centre - hip)
			spec.phase = info[5]
		end
		table.insert(s, spec)
	end
	return s
end

BLUEPRINT[1] = function() -- Runner
	local mesh = runnerMesh()
	if mesh then
		return mesh, 1.0
	end
	local shell, dark, eye = rgb(245, 100, 50), rgb(165, 55, 35), rgb(255, 230, 90)
	local s = {
		ball(2.5, P(0, 1.55, 0.9), dark, M.SmoothPlastic, "body"),
		ball(1.9, P(0, 1.7, -0.5), shell, M.SmoothPlastic, "body"),
		blk(Vector3.new(1.3, 0.8, 1.1), P(0, 1.55, -1.55), dark),
		blk(Vector3.new(1.1, 0.16, 0.12), P(0, 1.68, -2.12), eye, M.Neon, "eye"),
		blk(Vector3.new(0.18, 0.18, 0.9), P(0.35, 1.25, -2.2) * A(0.3, 0.3, 0), shell),
		blk(Vector3.new(0.18, 0.18, 0.9), P(-0.35, 1.25, -2.2) * A(0.3, -0.3, 0), shell),
	}
	for i, h in { { 1, -0.5, 0 }, { -1, -0.5, math.pi }, { 1, 0.6, math.pi }, { -1, 0.6, 0 } } do
		table.insert(
			s,
			leg(
				Vector3.new(0.22, 1.9, 0.22),
				P(h[1] * 0.7, 1.45, h[2]),
				P(h[1] * 0.75, -0.55, 0) * A(0, 0, h[1] * 0.85),
				dark,
				h[3]
			)
		)
	end
	return s, 1.0
end

BLUEPRINT[2] = function() -- Stalker
	local shell, dark, glow = rgb(175, 80, 230), rgb(90, 40, 120), rgb(255, 90, 220)
	local s = {
		blk(Vector3.new(1.3, 1.0, 3.4), P(0, 2.0, 0.3) * A(-0.12, 0, 0), shell, M.SmoothPlastic, "body"),
		blk(Vector3.new(0.3, 0.2, 3.0), P(0, 2.55, 0.3) * A(-0.12, 0, 0), glow, M.Neon, "eye"),
		blk(Vector3.new(1.0, 0.8, 1.2), P(0, 2.2, -1.8), dark),
		blk(Vector3.new(0.8, 0.14, 0.12), P(0, 2.3, -2.42), glow, M.Neon, "eye"),
	}
	-- front blades
	for _, side in { 1, -1 } do
		table.insert(
			s,
			leg(
				Vector3.new(0.18, 2.6, 0.3),
				P(side * 0.7, 2.1, -1.2),
				P(side * 0.4, -0.6, -0.9) * A(-0.9, 0, side * 0.3),
				glow,
				if side == 1 then 0 else math.pi,
				M.Neon
			)
		)
	end
	-- long hind legs
	for _, side in { 1, -1 } do
		table.insert(
			s,
			leg(
				Vector3.new(0.25, 3.2, 0.25),
				P(side * 0.7, 2.1, 1.1),
				P(side * 0.6, -0.9, 0.5) * A(0.5, 0, side * 0.45),
				dark,
				if side == 1 then math.pi else 0
			)
		)
	end
	return s, 1.0
end

BLUEPRINT[3] = function() -- Spitter
	local skin, dark, acid = rgb(120, 150, 75), rgb(70, 86, 46), rgb(160, 255, 70)
	local s = {
		ball(2.7, P(0, 1.9, -0.3), skin, M.SmoothPlastic, "body"),
		{
			size = Vector3.one * 3.3,
			cf = P(0, 2.6, 1.3),
			color = acid,
			mat = M.Neon,
			shape = Enum.PartType.Ball,
			role = "sac",
			transparency = 0.25,
		},
		blk(Vector3.new(1.2, 0.9, 1.0), P(0, 1.8, -1.8), dark),
		blk(Vector3.new(0.7, 0.35, 0.2), P(0, 1.65, -2.32), acid, M.Neon, "eye"),
	}
	for i, h in { { 1, -0.8, 0 }, { -1, -0.8, math.pi }, { 1, 0.6, math.pi }, { -1, 0.6, 0 } } do
		table.insert(
			s,
			leg(
				Vector3.new(0.3, 2.2, 0.3),
				P(h[1] * 0.9, 1.7, h[2]),
				P(h[1] * 0.85, -0.7, 0) * A(0, 0, h[1] * 0.8),
				dark,
				h[3]
			)
		)
	end
	return s, 1.0
end

local function bulwark(scale: number, elite: boolean)
	local shell = if elite then rgb(120, 100, 60) else rgb(95, 115, 145)
	local dark = rgb(55, 62, 78)
	local trim = if elite then rgb(255, 200, 60) else rgb(255, 140, 50)
	local s = {
		ball(4.4, P(0, 2.6, 0.6), shell, M.SmoothPlastic, "body"),
		blk(Vector3.new(6, 3.8, 0.9), P(0, 2.7, -1.9) * A(-0.1, 0, 0), dark, M.Metal, "body"),
		blk(Vector3.new(6.1, 0.3, 1.0), P(0, 4.65, -1.7) * A(-0.1, 0, 0), trim, M.Neon),
		blk(Vector3.new(0.4, 3.6, 1.0), P(2.95, 2.7, -1.9) * A(-0.1, 0, 0), trim, M.Metal),
		blk(Vector3.new(0.4, 3.6, 1.0), P(-2.95, 2.7, -1.9) * A(-0.1, 0, 0), trim, M.Metal),
		blk(Vector3.new(1.8, 0.3, 0.15), P(0, 3.3, -2.4), rgb(255, 60, 50), M.Neon, "eye"),
	}
	for i, h in
		{ { 1, -0.6, 0 }, { -1, -0.6, math.pi }, { 1, 0.8, math.pi }, { -1, 0.8, 0 }, { 1, 2, 0 }, { -1, 2, math.pi } }
	do
		table.insert(
			s,
			leg(
				Vector3.new(0.5, 2.0, 0.5),
				P(h[1] * 1.6, 1.6, h[2]),
				P(h[1] * 0.5, -0.7, 0) * A(0, 0, h[1] * 0.5),
				dark,
				h[3]
			)
		)
	end
	if elite then
		table.insert(
			s,
			{
				size = Vector3.one * 1.7,
				cf = P(0, 4.6, 1.4),
				color = trim,
				mat = M.Neon,
				shape = Enum.PartType.Ball,
				role = "glow",
			}
		)
		for k = -1, 1 do
			table.insert(s, blk(Vector3.new(0.5, 1.6, 0.5), P(k * 1.3, 5.3, -1.4) * A(0, 0, -k * 0.25), trim, M.Neon))
		end
	end
	for _, spec in s do
		spec.size *= scale
		spec.cf = CFrame.new(spec.cf.Position * scale) * spec.cf.Rotation
		if spec.hip then
			spec.hip = CFrame.new(spec.hip.Position * scale) * spec.hip.Rotation
			spec.loc = CFrame.new(spec.loc.Position * scale) * spec.loc.Rotation
		end
	end
	return s
end

BLUEPRINT[4] = function()
	return bulwark(0.78, false), 0.7
end

BLUEPRINT[5] = function()
	return bulwark(1.05, true), 0.6
end

BLUEPRINT[6] = function() -- Hive
	local flesh, dark, pore = rgb(88, 44, 98), rgb(44, 20, 52), rgb(170, 255, 80)
	local s = {
		ball(9, P(0, 1.5, 0), dark, M.Slate, "body"),
		ball(6, P(1.3, 4.6, 0.6), flesh, M.SmoothPlastic, "body"),
		ball(3.8, P(-1.2, 6.6, -0.6), flesh, M.SmoothPlastic),
		ball(2.2, P(0.3, 8.4, 0.2), dark, M.Slate),
	}
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		table.insert(
			s,
			{
				size = Vector3.one * 1.1,
				cf = P(math.cos(a) * 3.6, 3 + (i % 3), math.sin(a) * 3.6),
				color = pore,
				mat = M.Neon,
				shape = Enum.PartType.Ball,
				role = "sac",
			}
		)
	end
	return s, 0
end

BLUEPRINT[7] = function() -- Broodmother
	local carapace, dark, glow, eye = rgb(70, 34, 86), rgb(30, 14, 38), rgb(170, 255, 80), rgb(255, 60, 70)
	local s = {
		ball(13, P(0, 8, 1), carapace, M.SmoothPlastic, "body"),
		ball(11, P(0, 7.5, 9), dark, M.SmoothPlastic, "body"),
		blk(Vector3.new(7, 4.5, 6), P(0, 8.5, -6.5), dark, M.SmoothPlastic, "body"),
		blk(Vector3.new(5.2, 0.5, 0.3), P(0, 9.4, -9.6), eye, M.Neon, "eye"),
		blk(Vector3.new(3.8, 0.4, 0.3), P(0, 8.5, -9.6), eye, M.Neon, "eye"),
	}
	for k = -2, 2 do
		table.insert(
			s,
			blk(Vector3.new(0.9, 4.5, 0.9), P(k * 1.6, 12.3 - math.abs(k) * 0.5, -6) * A(-0.4, 0, -k * 0.2), carapace)
		)
	end
	-- weak nodes
	for k, off in { { -3, 13.5, 2 }, { 3, 13.5, 2 }, { 0, 12.5, 8 } } do
		table.insert(
			s,
			{
				size = Vector3.one * 2.4,
				cf = P(off[1], off[2], off[3]),
				color = glow,
				mat = M.Neon,
				shape = Enum.PartType.Ball,
				role = "node",
			}
		)
	end
	-- legs: two segments each
	for i, h in { { 1, -3, 0 }, { -1, -3, math.pi }, { 1, 4, math.pi }, { -1, 4, 0 } } do
		local hip = P(h[1] * 5.5, 8, h[2])
		table.insert(
			s,
			leg(Vector3.new(1.4, 9, 1.4), hip, P(h[1] * 2.6, 1.2, 0) * A(0, 0, h[1] * -1.0), carapace, h[3])
		)
		table.insert(s, leg(Vector3.new(1.1, 10, 1.1), hip, P(h[1] * 6.2, -3.4, 0) * A(0, 0, h[1] * 0.35), dark, h[3]))
	end
	-- mandible tentacles
	for _, side in { 1, -1 } do
		table.insert(
			s,
			leg(
				Vector3.new(0.9, 0.9, 7),
				P(side * 2.4, 7, -8.5),
				P(side * 0.6, -1, -3) * A(0.35, side * 0.25, 0),
				glow,
				if side == 1 then 0 else math.pi,
				M.Neon
			)
		)
	end
	return s, 0.35
end

BLUEPRINT[8] = function() -- Bomber: bloated orange sac on stubby legs, fuse-glow eyes
	local shell, dark, sac = rgb(150, 60, 30), rgb(60, 24, 16), rgb(255, 150, 40)
	local s = {
		ball(2.2, P(0, 1.5, -0.4), shell, M.SmoothPlastic, "body"),
		{
			size = Vector3.one * 3.0,
			cf = P(0, 2.2, 0.9),
			color = sac,
			mat = M.Neon,
			shape = Enum.PartType.Ball,
			role = "sac",
			transparency = 0.15,
		},
		blk(Vector3.new(1.0, 0.6, 0.8), P(0, 1.4, -1.5), dark),
		blk(Vector3.new(0.9, 0.16, 0.12), P(0, 1.55, -1.95), rgb(255, 230, 120), M.Neon, "eye"),
	}
	for k = 1, 5 do
		local a = k / 5 * math.pi * 2
		table.insert(
			s,
			blk(
				Vector3.new(0.25, 0.9, 0.25),
				P(math.cos(a) * 1.1, 3.4, 0.9 + math.sin(a) * 1.1) * A(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5),
				dark
			)
		)
	end
	for _, h in { { 1, -0.6, 0 }, { -1, -0.6, math.pi }, { 1, 0.6, math.pi }, { -1, 0.6, 0 } } do
		table.insert(
			s,
			leg(
				Vector3.new(0.3, 1.4, 0.3),
				P(h[1] * 0.7, 1.1, h[2]),
				P(h[1] * 0.5, -0.45, 0) * A(0, 0, h[1] * 0.7),
				dark,
				h[3]
			)
		)
	end
	return s, 1.2
end

BLUEPRINT[9] = function() -- Devourer: armored maw + 7 trailing segments (placed along a trail by EnemyView)
	local plate, dark, glow, eye = rgb(78, 52, 40), rgb(32, 20, 18), rgb(170, 255, 80), rgb(255, 70, 50)
	local s = {
		ball(12, P(0, 5, 0), dark, M.Slate, "body"),
		blk(Vector3.new(12, 3, 9), P(0, 9.5, 0.5), plate, M.Slate, "body"),
		blk(Vector3.new(6, 0.5, 0.3), P(0, 6.5, -5.9), eye, M.Neon, "eye"),
	}
	-- mandibles (animated like legs)
	for _, side in { 1, -1 } do
		table.insert(
			s,
			leg(
				Vector3.new(1.2, 1.2, 7),
				P(side * 3.5, 4, -4.5),
				P(side * 1.2, 0, -3) * A(0, side * 0.35, 0),
				plate,
				if side == 1 then 0 else math.pi
			)
		)
	end
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2
		table.insert(
			s,
			blk(Vector3.new(0.9, 0.9, 3.5), P(math.cos(a) * 4.2, 5 + math.sin(a) * 4.2, -5.6) * A(0, 0, a), dark)
		)
	end
	table.insert(
		s,
		{
			size = Vector3.one * 3,
			cf = P(0, 11.5, 2),
			color = glow,
			mat = M.Neon,
			shape = Enum.PartType.Ball,
			role = "node",
		}
	)
	for i = 1, 7 do
		local d = 10.5 - i * 0.7
		table.insert(
			s,
			{
				size = Vector3.one * d,
				cf = P(0, d / 2 - 0.5, 6 + i * 6.5),
				color = if i % 2 == 0 then plate else dark,
				mat = M.Slate,
				shape = Enum.PartType.Ball,
				seg = i,
			}
		)
		table.insert(
			s,
			{
				size = Vector3.new(d * 0.9, 1.2, 2.2),
				cf = P(0, d - 0.6, 6 + i * 6.5),
				color = plate,
				mat = M.Slate,
				seg = i,
			}
		)
		if i % 2 == 1 then
			table.insert(
				s,
				{
					size = Vector3.one * 1.4,
					cf = P(0, d + 0.4, 6 + i * 6.5),
					color = glow,
					mat = M.Neon,
					shape = Enum.PartType.Ball,
					seg = i,
					role = "node",
				}
			)
		end
	end
	return s, 0.5
end

BLUEPRINT[10] = function() -- Core Carrier: a steel-blue elite hauling a crackling storm core on its back
	local s = bulwark(1.05, true)
	for _, spec in s do
		if spec.role == "glow" then
			spec.color = rgb(140, 220, 255)
			spec.size *= 1.6
		elseif spec.mat == M.Neon and spec.role ~= "eye" then
			spec.color = rgb(84, 238, 255)
		elseif spec.role == "body" and spec.mat ~= M.Metal then
			spec.color = rgb(70, 92, 120)
		end
	end
	table.insert(
		s,
		{
			size = Vector3.one * 3.2,
			cf = P(0, 6.4, 1.6),
			color = rgb(160, 235, 255),
			mat = M.ForceField,
			shape = Enum.PartType.Ball,
			role = "node",
			transparency = 0.2,
		}
	)
	for k = -1, 1, 2 do
		table.insert(
			s,
			blk(Vector3.new(0.35, 3.4, 0.35), P(k * 1.7, 5.6, 1.6) * A(0, 0, k * 0.5), rgb(84, 238, 255), M.Neon)
		)
	end
	return s, 0.6
end

BLUEPRINT[11] = function() -- Power node: a crystal pylon feeding the hive, pulsing violet
	local base, crystal, core = rgb(40, 30, 54), rgb(150, 90, 255), rgb(220, 170, 255)
	local s = {
		blk(Vector3.new(8, 1.2, 8), P(0, 0.6, 0) * A(0, math.rad(45), 0), base, M.Slate, "body"),
		blk(Vector3.new(5, 1.6, 5), P(0, 1.8, 0), base, M.Slate, "body"),
		{
			size = Vector3.new(1.6, 9, 1.6),
			cf = P(0, 6.5, 0),
			color = core,
			mat = M.Neon,
			role = "sac",
			transparency = 0.1,
		},
	}
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2
		table.insert(
			s,
			blk(
				Vector3.new(1.4, 6.5, 1.4),
				P(math.cos(a) * 2.2, 5, math.sin(a) * 2.2) * A(math.sin(a) * 0.35, a, math.cos(a) * 0.35),
				crystal,
				M.Glass,
				"body"
			)
		)
	end
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + 0.4
		table.insert(
			s,
			blk(
				Vector3.new(0.4, 0.4, 5),
				P(math.cos(a) * 4.5, 0.4, math.sin(a) * 4.5) * A(0, -a + math.pi / 2, 0),
				core,
				M.Neon
			)
		)
	end
	return s, 0
end

BLUEPRINT[12] = function() -- Acid source: a cracked mound venting a bubbling green pool
	local rock, slime, acid = rgb(46, 58, 36), rgb(90, 130, 40), rgb(170, 255, 80)
	local s = {
		ball(8.5, P(0, 0.8, 0), rock, M.Slate, "body"),
		ball(5.5, P(1.4, 3.6, -0.8), slime, M.SmoothPlastic, "body"),
		{
			size = Vector3.new(0.3, 6, 6),
			cf = P(0, 4.7, 0) * A(0, 0, math.rad(90)),
			color = acid,
			mat = M.Neon,
			shape = Enum.PartType.Cylinder,
			role = "sac",
			transparency = 0.15,
		},
	}
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		table.insert(
			s,
			{
				size = Vector3.one * 1.2,
				cf = P(math.cos(a) * 3.3, 4.2 + (i % 2) * 0.8, math.sin(a) * 3.3),
				color = acid,
				mat = M.Neon,
				shape = Enum.PartType.Ball,
				role = "sac",
			}
		)
	end
	for k = -1, 1, 2 do
		table.insert(s, blk(Vector3.new(0.9, 4, 0.9), P(k * 3.2, 3, 1.5) * A(0.3, 0, k * 0.4), rock, M.Slate))
	end
	return s, 0
end

return Creatures
