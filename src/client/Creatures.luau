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

-- Generated art meshes (Shared.Art, DD-042) replicated by the server; nil until they arrive.
local function art(key: string): MeshPart?
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("ArtTemplates")
	return folder and folder:FindFirstChild(key) or nil
end

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
	Shell = { rgb(255, 118, 52), M.SmoothPlastic, "body" },
	Flesh = { rgb(150, 46, 36), M.SmoothPlastic, "body" },
	Head = { rgb(178, 60, 38), M.SmoothPlastic, "body" },
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
		local spec = {
			mesh = mp,
			name = mp.Name,
			size = mp.Size * RUNNER_SCALE,
			cf = P(centre),
			color = info[1],
			mat = info[2],
			role = info[3],
		}
		if info[4] then
			local hip = info[4] * RUNNER_SCALE
			spec.role = "leg"
			spec.hip = P(hip)
			spec.loc = P(centre - hip)
			spec.phase = info[5]
		end
		table.insert(s, spec)
	end
	-- Spore nodules along the spine (DD-033): the swarm glows warm against the cold crater, so a runner
	-- reads at a glance from the top-down camera. The mesh itself is unchanged.
	for i, z in { -0.55, 0.25, 1.05 } do
		local n = ball(0.56 - i * 0.06, P(0, 2.34 - i * 0.05, z), rgb(255, 150, 54), M.Neon)
		n.name = "Nodule"
		table.insert(s, n)
	end
	return s
end

BLUEPRINT[1] = function() -- Runner
	-- the generated species first (DD-048): the Blender runner's mesh assets no longer render
	local gen = Creatures.species
		and Creatures.species("RUNNER", {
			scale = 1.6,
			colors = { default = rgb(235, 110, 50) },
			eyes = { piece = "body", color = rgb(255, 230, 90), size = 0.15, up = -0.05, apart = 0.14 },
		})
	if gen then
		return gen, 1.0
	end
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
		table.insert(s, {
			size = Vector3.one * 1.7,
			cf = P(0, 4.6, 1.4),
			color = trim,
			mat = M.Neon,
			shape = Enum.PartType.Ball,
			role = "glow",
		})
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
	-- the generated nest mesh (DD-042) when its template has replicated; glowing sacs on its flanks
	local art = game:GetService("ReplicatedStorage"):FindFirstChild("ArtTemplates")
	local nest = art and art:FindFirstChild("NEST")
	if nest then
		local size = nest.Size * (7.5 / nest.Size.Y)
		local s = {
			{
				size = size,
				cf = P(0, size.Y / 2 - 0.3, 0),
				color = flesh,
				mat = M.SmoothPlastic,
				mesh = nest,
				role = "body",
			},
		}
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			table.insert(s, {
				size = Vector3.one * 1.2,
				cf = P(math.cos(a) * size.X * 0.4, 1.6 + (i % 3) * 0.9, math.sin(a) * size.Z * 0.4),
				color = pore,
				mat = M.Neon,
				shape = Enum.PartType.Ball,
				role = "sac",
			})
		end
		return s, 0
	end
	local s = {
		ball(9, P(0, 1.5, 0), dark, M.Slate, "body"),
		ball(6, P(1.3, 4.6, 0.6), flesh, M.SmoothPlastic, "body"),
		ball(3.8, P(-1.2, 6.6, -0.6), flesh, M.SmoothPlastic),
		ball(2.2, P(0.3, 8.4, 0.2), dark, M.Slate),
	}
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		table.insert(s, {
			size = Vector3.one * 1.1,
			cf = P(math.cos(a) * 3.6, 3 + (i % 3), math.sin(a) * 3.6),
			color = pore,
			mat = M.Neon,
			shape = Enum.PartType.Ball,
			role = "sac",
		})
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
		table.insert(s, {
			size = Vector3.one * 2.4,
			cf = P(off[1], off[2], off[3]),
			color = glow,
			mat = M.Neon,
			shape = Enum.PartType.Ball,
			role = "node",
		})
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
	local head, ring = art("WORM_HEAD"), art("WORM_SEG")
	if head and ring then
		-- the generated maw; a red glow in the throat, the weak node on its crown
		local hs = head.Size * (13 / head.Size.X)
		local s = {
			{
				size = hs,
				cf = P(0, hs.Y / 2 - 0.4, -1),
				color = plate,
				mat = M.SmoothPlastic,
				mesh = head,
				role = "body",
			},
			blk(Vector3.new(4, 1.2, 0.3), P(0, hs.Y * 0.32, -1 - hs.Z * 0.36), eye, M.Neon, "eye"),
			{
				size = Vector3.one * 3,
				cf = P(0, hs.Y + 0.6, 2),
				color = glow,
				mat = M.Neon,
				shape = Enum.PartType.Ball,
				role = "node",
			},
		}
		-- armoured rings around a dark core, trailing along the path
		for i = 1, 7 do
			local d = 10.5 - i * 0.7
			local z = 6 + i * 6.5
			table.insert(s, {
				size = Vector3.one * d * 0.82,
				cf = P(0, d / 2 - 0.5, z),
				color = dark,
				mat = M.Slate,
				shape = Enum.PartType.Ball,
				seg = i,
			})
			local rs = ring.Size * (d / ring.Size.X)
			rs = Vector3.new(rs.X, rs.Y, rs.Z * 1.25)
			table.insert(
				s,
				{ size = rs, cf = P(0, d / 2 - 0.5, z), color = plate, mat = M.SmoothPlastic, mesh = ring, seg = i }
			)
			if i % 2 == 1 then
				table.insert(s, {
					size = Vector3.one * 1.4,
					cf = P(0, d + 0.2, z),
					color = glow,
					mat = M.Neon,
					shape = Enum.PartType.Ball,
					seg = i,
					role = "node",
				})
			end
		end
		return s, 0.5
	end
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
	table.insert(s, {
		size = Vector3.one * 3,
		cf = P(0, 11.5, 2),
		color = glow,
		mat = M.Neon,
		shape = Enum.PartType.Ball,
		role = "node",
	})
	for i = 1, 7 do
		local d = 10.5 - i * 0.7
		table.insert(s, {
			size = Vector3.one * d,
			cf = P(0, d / 2 - 0.5, 6 + i * 6.5),
			color = if i % 2 == 0 then plate else dark,
			mat = M.Slate,
			shape = Enum.PartType.Ball,
			seg = i,
		})
		table.insert(s, {
			size = Vector3.new(d * 0.9, 1.2, 2.2),
			cf = P(0, d - 0.6, 6 + i * 6.5),
			color = plate,
			mat = M.Slate,
			seg = i,
		})
		if i % 2 == 1 then
			table.insert(s, {
				size = Vector3.one * 1.4,
				cf = P(0, d + 0.4, 6 + i * 6.5),
				color = glow,
				mat = M.Neon,
				shape = Enum.PartType.Ball,
				seg = i,
				role = "node",
			})
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
	table.insert(s, {
		size = Vector3.one * 3.2,
		cf = P(0, 6.4, 1.6),
		color = rgb(160, 235, 255),
		mat = M.ForceField,
		shape = Enum.PartType.Ball,
		role = "node",
		transparency = 0.2,
	})
	for k = -1, 1, 2 do
		table.insert(
			s,
			blk(Vector3.new(0.35, 3.4, 0.35), P(k * 1.7, 5.6, 1.6) * A(0, 0, k * 0.5), rgb(84, 238, 255), M.Neon)
		)
	end
	return s, 0.6
end

BLUEPRINT[11] = function() -- Power node: a crystal pylon feeding the hive, pulsing violet
	local industrial = require(game.ReplicatedStorage.Shared.Art).Industrial.NODE
	if art("IND_NODE_1") and art("IND_NODE_2") and art("IND_NODE_3") then
		local specs = {}
		for i, def in industrial do
			table.insert(specs, {
				mesh = art("IND_NODE_" .. i),
				name = def.name,
				size = def.size * 1.3,
				cf = P(def.pos * 1.3),
				color = if i == 3 then rgb(175, 230, 90) else rgb(106, 121, 90),
				mat = M.SmoothPlastic,
				role = "body",
			})
		end
		-- A small living core at the cabinet opening, keeping the weak point clear from above.
		table.insert(specs, ball(1.6, P(0, 4.3, -1.6), rgb(190, 255, 85), M.Neon, "sac"))
		return specs, 0
	end
	local base, crystal, core = rgb(40, 30, 54), rgb(150, 90, 255), rgb(220, 170, 255)
	local node = art("NODE")
	if node then
		local ns = node.Size * (12 / node.Size.Y)
		local s = {
			{ size = ns, cf = P(0, ns.Y / 2, 0), color = crystal, mat = M.SmoothPlastic, mesh = node, role = "body" },
			-- the pulsing heart inside the crystals
			{
				size = Vector3.new(1.1, 7, 1.1),
				cf = P(0, 6, 0),
				color = core,
				mat = M.Neon,
				role = "sac",
				transparency = 0.35,
			},
		}
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2 + 0.4
			table.insert(
				s,
				blk(
					Vector3.new(0.4, 0.4, 5),
					P(math.cos(a) * 4.5, 0.25, math.sin(a) * 4.5) * A(0, -a + math.pi / 2, 0),
					core,
					M.Neon
				)
			)
		end
		return s, 0
	end
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
	local mound = art("ACID_MOUND")
	if mound then
		local ms = mound.Size * (10 / mound.Size.X)
		local s = {
			{
				size = ms,
				cf = P(0, ms.Y / 2 - 0.2, 0),
				color = rock,
				mat = M.SmoothPlastic,
				mesh = mound,
				role = "body",
			},
			-- the pool surface glows and pulses (sac), bubbles pop above it
			{
				size = Vector3.new(0.2, ms.X * 0.45, ms.Z * 0.45),
				cf = P(0, ms.Y * 0.86, 0) * A(0, 0, math.rad(90)),
				color = acid,
				mat = M.Neon,
				shape = Enum.PartType.Cylinder,
				role = "sac",
				transparency = 0.35,
			},
		}
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			table.insert(s, {
				size = Vector3.one * 0.9,
				cf = P(math.cos(a) * 1.6, ms.Y + 0.2 + (i % 2) * 0.5, math.sin(a) * 1.6),
				color = acid,
				mat = M.Neon,
				shape = Enum.PartType.Ball,
				role = "sac",
			})
		end
		return s, 0
	end
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
		table.insert(s, {
			size = Vector3.one * 1.2,
			cf = P(math.cos(a) * 3.3, 4.2 + (i % 2) * 0.8, math.sin(a) * 3.3),
			color = acid,
			mat = M.Neon,
			shape = Enum.PartType.Ball,
			role = "sac",
		})
	end
	for k = -1, 1, 2 do
		table.insert(s, blk(Vector3.new(0.9, 4, 0.9), P(k * 3.2, 3, 1.5) * A(0.3, 0, k * 0.4), rock, M.Slate))
	end
	return s, 0
end

-- The swarm family (DD-034) -------------------------------------------------------------------------------
-- Every species is the base monster (the Runner mesh) grown differently: stretched, swollen, armoured,
-- crowned. One silhouette language, so the swarm reads as one living thing; colour and extra growths say
-- who is who. Falls back to the old part blueprints when the mesh asset is missing.
local LEGACY = table.clone(BLUEPRINT)

local function scaled(cf: CFrame, k: Vector3): CFrame
	return CFrame.new(cf.Position * k) * cf.Rotation
end

-- o = { scale = Vector3, shell, flesh, head, legs, eyes, nodule (colour or false), noduleScale, extras }
local function variant(o)
	local s = runnerMesh()
	if not s then
		return nil
	end
	local k = o.scale
	local out = {}
	for _, spec in s do
		if spec.name == "Nodule" and o.nodule == false then
			continue
		end
		spec.cf = scaled(spec.cf, k)
		if spec.shape == Enum.PartType.Ball then
			spec.size = spec.size * math.min(k.X, k.Y, k.Z) * (o.noduleScale or 1)
		else
			spec.size = spec.size * k
		end
		if spec.hip then
			spec.hip = scaled(spec.hip, k)
			spec.loc = scaled(spec.loc, k)
		end
		local n = spec.name
		if n == "Shell" and o.shell then
			spec.color = o.shell
		elseif n == "Flesh" and o.flesh then
			spec.color = o.flesh
		elseif n == "Head" and o.head then
			spec.color = o.head
		elseif n == "Eyes" and o.eyes then
			spec.color = o.eyes
		elseif n == "Nodule" and o.nodule then
			spec.color = o.nodule
		elseif n and n:sub(1, 3) == "Leg" and o.legs then
			spec.color = o.legs
		end
		table.insert(out, spec)
	end
	for _, e in o.extras or {} do
		table.insert(out, e)
	end
	return out
end

local function glowBall(d: number, cf: CFrame, color: Color3, role: string?, transparency: number?)
	return {
		size = Vector3.one * d,
		cf = cf,
		color = color,
		mat = M.Neon,
		shape = Enum.PartType.Ball,
		role = role,
		transparency = transparency,
	}
end

BLUEPRINT[2] = function() -- Leaper: long, lean, crimson, with two glowing scythes
	local blade = rgb(255, 110, 200)
	local s = variant({
		scale = Vector3.new(0.85, 0.95, 1.3),
		shell = rgb(232, 48, 104),
		flesh = rgb(110, 20, 52),
		head = rgb(160, 32, 70),
		legs = rgb(90, 18, 46),
		nodule = rgb(255, 140, 210),
		extras = {
			leg(
				Vector3.new(0.22, 2.5, 0.34),
				P(0.75, 2.2, -1.6),
				P(0.35, -0.5, -0.9) * A(-0.95, 0, 0.3),
				blade,
				0,
				M.Neon
			),
			leg(
				Vector3.new(0.22, 2.5, 0.34),
				P(-0.75, 2.2, -1.6),
				P(-0.35, -0.5, -0.9) * A(-0.95, 0, -0.3),
				blade,
				math.pi,
				M.Neon
			),
		},
	})
	if s then
		return s, 1.1
	end
	return LEGACY[2]()
end

BLUEPRINT[3] = function() -- Spitter: swollen, mustard shell, a translucent acid sac on its back
	local acid = rgb(170, 255, 70)
	local s = variant({
		scale = Vector3.new(1.15, 1.1, 1.0),
		shell = rgb(206, 168, 52),
		flesh = rgb(96, 82, 26),
		head = rgb(150, 120, 36),
		legs = rgb(80, 66, 22),
		eyes = acid,
		nodule = false,
		extras = {
			{
				size = Vector3.one * 2.9,
				cf = P(0, 3.1, 0.8),
				color = acid,
				mat = M.Neon,
				shape = Enum.PartType.Ball,
				role = "sac",
				transparency = 0.25,
			},
		},
	})
	if s then
		return s, 1.0
	end
	return LEGACY[3]()
end

-- Bulwark: a runner grown huge and armoured; a front plate shows where bullets glance off.
local function bulwarkVariant(k: number, elite: boolean)
	local trim = if elite then rgb(255, 180, 60) else rgb(230, 100, 40)
	local plate = if elite then rgb(120, 92, 54) else rgb(92, 64, 76)
	local extras = {
		blk(
			Vector3.new(2.7 * k, 1.9 * k, 0.35 * k),
			P(0, 1.55 * k, -2.25 * k) * A(-0.25, 0, 0),
			plate,
			M.Metal,
			"body"
		),
		blk(Vector3.new(2.75 * k, 0.16 * k, 0.4 * k), P(0, 2.5 * k, -2.0 * k) * A(-0.25, 0, 0), trim, M.Neon),
	}
	for i = -1, 1 do
		table.insert(
			extras,
			blk(
				Vector3.new(0.3 * k, 0.9 * k, 0.3 * k),
				P(i * 0.55 * k, 2.6 * k, (0.2 + math.abs(i) * 0.3) * k) * A(0.4, 0, -i * 0.35),
				trim,
				M.Neon
			)
		)
	end
	if elite then
		table.insert(extras, glowBall(0.9 * k, P(0, 2.55 * k, 0.9 * k), trim, "glow"))
	end
	return variant({
		scale = Vector3.new(k, k * 0.95, k * 0.92),
		shell = if elite then rgb(196, 120, 52) else rgb(150, 70, 58),
		flesh = rgb(70, 30, 36),
		head = if elite then rgb(150, 86, 40) else rgb(110, 46, 46),
		legs = rgb(60, 28, 34),
		nodule = trim,
		noduleScale = 0.8,
		extras = extras,
	})
end

BLUEPRINT[4] = function()
	local s = bulwarkVariant(1.95, false)
	if s then
		return s, 0.7
	end
	return LEGACY[4]()
end

BLUEPRINT[5] = function()
	local s = bulwarkVariant(2.6, true)
	if s then
		return s, 0.6
	end
	return LEGACY[5]()
end

BLUEPRINT[7] = function() -- Broodmother: a colossal runner with a glowing brood abdomen and three weak nodes
	local k = 4.6
	local glow = rgb(255, 120, 200)
	local extras = {
		{
			size = Vector3.one * 8,
			cf = P(0, 6.2, 7.5),
			color = rgb(255, 90, 160),
			mat = M.Neon,
			shape = Enum.PartType.Ball,
			role = "sac",
			transparency = 0.35,
		},
	}
	for _, off in { { -2.6, 11.2, 1.5 }, { 2.6, 11.2, 1.5 }, { 0, 10.4, 7.2 } } do
		table.insert(extras, glowBall(2.4, P(off[1], off[2], off[3]), rgb(170, 255, 80), "node"))
	end
	for i = -2, 2 do
		table.insert(
			extras,
			blk(
				Vector3.new(0.8, 4.2, 0.8),
				P(i * 1.5, 10.6 - math.abs(i) * 0.5, -3.6) * A(-0.5, 0, -i * 0.22),
				glow,
				M.Neon
			)
		)
	end
	local s = variant({
		scale = Vector3.new(k, k * 0.92, k),
		shell = rgb(120, 36, 92),
		flesh = rgb(54, 14, 40),
		head = rgb(90, 24, 66),
		legs = rgb(44, 12, 34),
		eyes = rgb(255, 70, 80),
		nodule = glow,
		extras = extras,
	})
	if s then
		return s, 0.35
	end
	return LEGACY[7]()
end

BLUEPRINT[8] = function() -- Bomber: a runner carrying a bloated burning sac
	local sac = rgb(255, 150, 40)
	local s = variant({
		scale = Vector3.new(1.05, 1.0, 0.95),
		shell = rgb(170, 64, 30),
		flesh = rgb(70, 24, 14),
		head = rgb(120, 44, 22),
		legs = rgb(60, 22, 12),
		eyes = rgb(255, 230, 120),
		nodule = false,
		extras = {
			{
				size = Vector3.one * 3.1,
				cf = P(0, 2.9, 0.6),
				color = sac,
				mat = M.Neon,
				shape = Enum.PartType.Ball,
				role = "sac",
				transparency = 0.12,
			},
		},
	})
	if s then
		return s, 1.2
	end
	return LEGACY[8]()
end

BLUEPRINT[10] = function() -- The Alpha: leader of the pack — huge, gold, crowned, a xenite shard on its back
	local k = 2.6
	local gold = rgb(255, 176, 60)
	local extras = {
		{
			size = Vector3.new(1.5, 4, 1.5),
			cf = P(0, 4.2, 1.0) * A(0.25, math.rad(45), 0),
			color = rgb(255, 90, 200),
			mat = M.Neon,
			role = "node",
			transparency = 0.1,
		},
	}
	for i = -2, 2 do
		table.insert(
			extras,
			blk(
				Vector3.new(0.35, 1.6, 0.35),
				P(i * 0.45, 2.95, -2.6 + math.abs(i) * 0.2) * A(-0.35, 0, -i * 0.3),
				gold,
				M.Neon
			)
		)
	end
	local s = variant({
		scale = Vector3.new(k, k, k * 0.95),
		shell = rgb(255, 160, 56),
		flesh = rgb(130, 36, 30),
		head = rgb(200, 90, 40),
		legs = rgb(110, 34, 26),
		eyes = rgb(255, 250, 200),
		nodule = gold,
		noduleScale = 0.75,
		extras = extras,
	})
	if s then
		return s, 0.6
	end
	return LEGACY[10]()
end

-- Distinct species (DD-048) -------------------------------------------------------------------------------
-- Each species is its own generated creature (Shared.Art.Creatures): own anatomy, silhouette and size,
-- so the swarm reads by shape before colour. Pieces named leg/scythe/pincer swing on the gait (a tripod:
-- diagonal pairs in phase), sacs pulse, the rest is body. Two neon eyes on the head carry the wind-up
-- telegraph (they turn red). `color` is each piece's average tone: a texture ignores Color, so hit
-- flashes and status tints swap the texture out for that tone. Any missing piece -> the older blueprint.
local ArtDefs = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Art"))

local LIMB = { "leg", "scythe", "pincer", "claw" }
local SAC = { "sac", "bulb" }

local function has(name: string, words): boolean
	for _, w in words do
		if name:find(w) then
			return true
		end
	end
	return false
end

-- o = { scale, colors = { [piece name] = Color3, default = Color3 }, eyes = { piece, color, size }?,
--       glow = { piece, color, scale, transparency }? (a neon core inside a sac: textures do not glow), extras }
local function species(key: string, o)
	local parts = ArtDefs.Creatures[key]
	if not parts then
		return nil
	end
	local k = o.scale
	local s = {}
	local eyeAt
	for i, part in parts do
		local tpl = art("CR_" .. key .. "_" .. i)
		if not tpl then
			return nil
		end
		local size = part.size * k
		local pos = part.pos * k
		local spec = {
			mesh = tpl,
			name = part.name,
			size = size,
			cf = P(pos),
			color = o.colors[part.name] or o.colors.default,
			mat = M.SmoothPlastic,
			role = "body",
		}
		if has(part.name, LIMB) then
			-- hinge at the inner top of the piece, toward the body centre
			local side = if pos.X >= 0 then 1 else -1
			local hip = Vector3.new(pos.X - side * size.X * 0.3, pos.Y + size.Y * 0.3, pos.Z)
			spec.role = "leg"
			spec.hip = P(hip)
			spec.loc = P(pos - hip)
			-- tripod gait: diagonal pairs move together
			spec.phase = if (pos.X >= 0) == (pos.Z >= 0) then 0 else math.pi
		elseif has(part.name, SAC) and not o.glow then
			spec.role = "sac"
		end
		if o.glow and part.name == o.glow.piece then
			local d = math.min(size.X, size.Y, size.Z) * o.glow.scale
			table.insert(s, glowBall(d, P(pos), o.glow.color, "sac", o.glow.transparency))
		end
		if part.name == (o.eyes and o.eyes.piece) then
			eyeAt = { pos = pos, size = size }
		end
		table.insert(s, spec)
	end
	if eyeAt then
		local d = o.eyes.size * k
		local front = eyeAt.pos + Vector3.new(0, eyeAt.size.Y * (o.eyes.up or 0.1), -eyeAt.size.Z * 0.46)
		for _, side in { -1, 1 } do
			table.insert(
				s,
				glowBall(
					d,
					P(front + Vector3.new(side * eyeAt.size.X * (o.eyes.apart or 0.22), 0, 0)),
					o.eyes.color,
					"eye"
				)
			)
		end
	end
	for _, e in o.extras or {} do
		table.insert(s, e)
	end
	return s
end

Creatures.species = species

-- Sizes (native generation -> game): the leaper stands tall and thin, the spitter squat and wide, the
-- bomber is the smallest thing in the swarm, armour grows long and low, the elite towers, the Alpha
-- is long, the Broodmother dwarfs everything. Runner (base monster) stays the reference: ~5.5 long.
BLUEPRINT[2] = function() -- Leaper: a crimson mantis on jumping legs, scythes raised
	local s = species("STALKER", {
		scale = 1.45,
		colors = { default = rgb(200, 44, 92), body = rgb(170, 30, 70) },
		eyes = { piece = "head", color = rgb(255, 120, 230), size = 0.2, apart = 0.25 },
	})
	if s then
		return s, 1.2
	end
	return LEGACY[2]()
end

BLUEPRINT[3] = function() -- Spitter: a squat mustard toad-beetle with a glowing acid bubble
	local s = species("SPITTER", {
		scale = 1.2,
		colors = { default = rgb(170, 140, 50), sac = rgb(170, 255, 70) },
		eyes = { piece = "head", color = rgb(190, 255, 80), size = 0.24, up = 0.15 },
		glow = { piece = "sac", color = rgb(170, 255, 70), scale = 1.02, transparency = 0.45 },
	})
	if s then
		return s, 0.9
	end
	return LEGACY[3]()
end

BLUEPRINT[8] = function() -- Bomber: a small waddling beetle under a molten bulb (the fuse flashes it)
	local s = species("BOMBER", {
		scale = 1.05,
		colors = { default = rgb(96, 52, 30), bulb = rgb(255, 150, 40) },
		eyes = { piece = "head", color = rgb(255, 230, 120), size = 0.2 },
		glow = { piece = "bulb", color = rgb(255, 150, 40), scale = 1.05, transparency = 0.3 },
	})
	if s then
		return s, 1.4
	end
	return LEGACY[8]()
end

BLUEPRINT[4] = function() -- Bulwark: a slate-blue armoured rhino beetle behind a front shield
	local s = species("BULWARK", {
		scale = 1.75,
		colors = { default = rgb(84, 100, 136) },
		eyes = { piece = "body", color = rgb(255, 90, 50), size = 0.24, up = -0.05, apart = 0.16 },
	})
	if s then
		return s, 0.6
	end
	return LEGACY[4]()
end

BLUEPRINT[5] = function() -- Elite bulwark: a towering gold siege beetle with a horned crest
	local s = species("ELITE", {
		scale = 1.75,
		colors = { default = rgb(200, 150, 64) },
		eyes = { piece = "horn crest", color = rgb(255, 210, 90), size = 0.3, up = -0.35 },
	})
	if s then
		return s, 0.5
	end
	return LEGACY[5]()
end

BLUEPRINT[10] = function() -- The Alpha: an orange-gold scorpion with a xenite stinger (its weak node)
	local k = 1.6
	local s = species("ALPHA", {
		scale = k,
		colors = { default = rgb(230, 130, 50) },
		eyes = { piece = "body", color = rgb(255, 250, 200), size = 0.22, up = 0.22, apart = 0.16 },
		extras = { glowBall(0.9 * k, P(Vector3.new(0, 6.1, 2.4) * k), rgb(255, 90, 200), "node", 0.1) },
	})
	if s then
		return s, 0.6
	end
	return LEGACY[10]()
end

BLUEPRINT[7] = function() -- Broodmother: a colossal spider queen; three weak nodes on her back
	local k = 1.6
	local extras = {}
	for _, off in { { -1.3, 9.6, 3.4 }, { 1.3, 9.6, 3.4 }, { 0, 7.4, 3.7 } } do
		table.insert(extras, glowBall(1.5 * k, P(Vector3.new(off[1], off[2], off[3]) * k), rgb(170, 255, 80), "node"))
	end
	local s = species("BROOD", {
		scale = k,
		colors = { default = rgb(110, 44, 130) },
		eyes = { piece = "body", color = rgb(255, 60, 70), size = 0.35, up = 0.2, apart = 0.18 },
		extras = extras,
	})
	if s then
		return s, 0.3
	end
	return LEGACY[7]()
end

-- Raid outposts (DD-039): another player's turrets and extractor are enemies. Bodies come from the
-- shared structure generator (lazy require: Structures -> Models -> Creatures).
for index, id in { [13] = "STING", [14] = "ARC", [15] = "MORTAR", [16] = "SHIELD", [17] = "CORE" } do
	BLUEPRINT[index] = function()
		return require(script.Parent.Structures).specs(id, 2, true), 0
	end
end

return Creatures
