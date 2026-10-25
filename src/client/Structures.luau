--!nonstrict
-- Outpost structure bodies (DD-037). One generator for every place a structure appears:
--   the lobby (your outpost around the extractor), sieges (your turrets fight beside you) and raids
--   (another player's turrets are enemies — EnemyView blueprints 13–17 come from here).
-- Ours: white hull, dark base, the structure's colour as accent. Hostile: the same bodies in red.
-- Spec format matches Creatures: { size, cf, color, mat, shape?, role? } (origin on the ground).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Meta = require(Shared:WaitForChild("Meta"))
local Models = require(script.Parent.Models)

local rgb = Color3.fromRGB
local M = Enum.Material
local P, A = CFrame.new, CFrame.Angles

local Structures = {}

local HULL = rgb(214, 218, 226)
local DARK = rgb(46, 42, 58)
local HOSTILE = rgb(255, 64, 92)

local function blk(s, size, cf, color, mat, role)
	table.insert(s, { size = size, cf = cf, color = color, mat = mat or M.SmoothPlastic, role = role })
end
local function ball(s, d, cf, color, mat, role)
	table.insert(s, {
		size = Vector3.one * d,
		cf = cf,
		color = color,
		mat = mat or M.SmoothPlastic,
		shape = Enum.PartType.Ball,
		role = role,
	})
end
-- vertical cylinder centred at y
local function cyl(s, d, h, x, y, z, color, mat, role)
	table.insert(s, {
		size = Vector3.new(h, d, d),
		cf = P(x, y, z) * A(0, 0, math.pi / 2),
		color = color,
		mat = mat or M.SmoothPlastic,
		shape = Enum.PartType.Cylinder,
		role = role,
	})
end
-- cylinder along local -Z (barrels)
local function barrel(s, d, len, x, y, z, color, mat)
	table.insert(s, {
		size = Vector3.new(len, d, d),
		cf = P(x, y, z - len / 2) * A(0, math.pi / 2, 0),
		color = color,
		mat = mat or M.Metal,
		shape = Enum.PartType.Cylinder,
	})
end

local function base(s, accent: Color3, d: number)
	cyl(s, d, 0.7, 0, 0.35, 0, DARK, M.Metal, "body")
	cyl(s, d + 0.3, 0.12, 0, 0.72, 0, accent, M.Neon)
end

-- Generated meshes (Shared.Art, DD-042): height at level 1, yaw that turns the mesh's muzzle to -Z
-- (the generated turrets already aim along their native -Z; checked top-down in Studio), and an
-- optional neon accent on top (fraction of the mesh height).
local MESHED = {
	STING = { h = 4.4, yaw = 0 },
	ARC = { h = 6.4, yaw = 0, orb = 0.86 },
	MORTAR = { h = 4.4, yaw = 0 },
	SHIELD = { h = 7.6, yaw = 0, orb = 0.95 },
	HARVEST = { h = 4.6, yaw = 0 },
}

-- Template for a structure mesh: the textured original, or for hostile structures an untextured copy
-- the builder tints red (a texture ignores Color). Nil until the server's ArtTemplates replicate.
local hostileCopies = {}
local function meshTemplate(key: string, hostile: boolean?): MeshPart?
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("ArtTemplates")
	local t = folder and folder:FindFirstChild(key)
	if not t or not hostile then
		return t
	end
	if not hostileCopies[key] then
		local c = t:Clone()
		c.TextureID = ""
		hostileCopies[key] = c
	end
	return hostileCopies[key]
end

function Structures.specs(id: string, lvl: number, hostile: boolean?)
	local def = Meta.Structures[id]
	local accent = if hostile then HOSTILE else def and def.color or HULL
	local hull = if hostile then rgb(150, 60, 70) else HULL
	local s = {}
	lvl = math.clamp(lvl or 1, 1, 3)
	if id == "CORE" then
		local industrial = require(Shared.Art).Industrial.DRILL
		local templates = game.ReplicatedStorage:FindFirstChild("ArtTemplates")
		local complete = templates ~= nil
		for i in industrial do
			complete = complete and templates:FindFirstChild("IND_DRILL_" .. i) ~= nil
		end
		if complete then
			for i, piece in industrial do
				local tpl = meshTemplate("IND_DRILL_" .. i, hostile)
				table.insert(s, {
					mesh = tpl,
					size = piece.size * 1.25,
					cf = P(piece.pos * 1.25),
					color = if hostile then HOSTILE else rgb(113, 127, 79),
					mat = M.Metal,
					role = "body",
				})
			end
			return s
		end
	end
	local meshed = MESHED[id]
	local tpl = meshed and meshTemplate(id, hostile)
	if tpl then
		base(s, accent, 4.4)
		local size = tpl.Size * (meshed.h * (0.9 + lvl * 0.1) / tpl.Size.Y)
		table.insert(s, {
			size = size,
			cf = P(0, 0.7 + size.Y / 2, 0) * A(0, meshed.yaw, 0),
			color = hull,
			mat = M.SmoothPlastic,
			mesh = tpl,
			role = "body",
		})
		if meshed.orb then
			ball(s, size.X * 0.32, P(0, 0.7 + size.Y * meshed.orb, 0), accent, M.Neon, "glow")
			s[#s].transparency = 0.45
		end
		-- level pips on the base plate
		for k = 1, lvl do
			local a = (k - (lvl + 1) / 2) * 0.5 + math.pi
			ball(s, 0.45, P(math.sin(a) * 2.05, 0.75, math.cos(a) * 2.05), accent, M.Neon)
		end
		return s
	end
	if id == "STING" then
		base(s, accent, 4.2)
		cyl(s, 1.3, 2.2, 0, 1.8, 0, DARK, M.Metal, "body")
		blk(s, Vector3.new(2.2, 1.3, 2.6), P(0, 3.2, 0.2), hull, M.SmoothPlastic, "body")
		blk(s, Vector3.new(2.25, 0.25, 2.65), P(0, 3.55, 0.2), accent, M.Neon)
		local n = if lvl >= 3 then 3 else 2
		for k = 1, n do
			local x = (k - (n + 1) / 2) * 0.6
			barrel(s, 0.38 + lvl * 0.04, 2.4, x, 3.15, -1.0, DARK)
			ball(s, 0.36, P(x, 3.15, -3.45), accent, M.Neon, "eye")
		end
		if lvl >= 2 then
			blk(s, Vector3.new(0.3, 1.0, 2.0), P(1.25, 3.2, 0.4), hull)
			blk(s, Vector3.new(0.3, 1.0, 2.0), P(-1.25, 3.2, 0.4), hull)
		end
	elseif id == "ARC" then
		base(s, accent, 4.2)
		cyl(s, 1.1, 4.6, 0, 2.9, 0, DARK, M.Metal, "body")
		for k = 1, 2 + lvl do
			cyl(s, 2.6 - k * 0.25, 0.28, 0, 1.4 + k * 1.1, 0, accent, M.Neon)
		end
		ball(s, 1.6 + lvl * 0.2, P(0, 5.6 + lvl * 0.4, 0), accent, M.Neon, "glow")
	elseif id == "MORTAR" then
		base(s, accent, 4.8)
		blk(s, Vector3.new(3, 1.2, 3), P(0, 1.3, 0), hull, M.SmoothPlastic, "body")
		table.insert(s, {
			size = Vector3.new(3.4, 1.5 + lvl * 0.15, 1.5 + lvl * 0.15),
			cf = P(0, 2.6, -0.6) * A(math.rad(55), 0, 0) * A(0, math.pi / 2, 0),
			color = DARK,
			mat = M.Metal,
			shape = Enum.PartType.Cylinder,
		})
		ball(s, 1.2, P(0, 3.6, -1.6), accent, M.Neon, "eye")
		for _, x in { -1.1, 1.1 } do
			blk(s, Vector3.new(0.3, 1.6, 1.8), P(x, 2.0, 0), accent, M.Metal)
		end
	elseif id == "SHIELD" then
		base(s, accent, 3.8)
		blk(s, Vector3.new(0.9, 6 + lvl, 0.9), P(0, 3.5 + lvl / 2, 0), hull, M.SmoothPlastic, "body")
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2
			blk(
				s,
				Vector3.new(0.2, 4 + lvl * 0.6, 1.4),
				P(math.cos(a) * 0.9, 3.4, math.sin(a) * 0.9) * A(0, -a, 0),
				accent,
				M.Neon
			)
		end
		table.insert(s, {
			size = Vector3.one * 1.6,
			cf = P(0, 7.5 + lvl, 0) * A(math.rad(45), 0, math.rad(45)),
			color = accent,
			mat = M.Neon,
			role = "glow",
		})
	elseif id == "CRYO" or id == "ACID" then
		local r = def.radius[lvl]
		cyl(s, r * 2, 0.08, 0, 0.06, 0, accent, M.Neon)
		s[#s].transparency = 0.78
		cyl(s, r * 2 + 0.6, 0.06, 0, 0.04, 0, DARK, M.SmoothPlastic)
		s[#s].transparency = 0.2
		for k = 0, 3 do
			local a = k / 4 * math.pi * 2 + math.pi / 4
			local x, z = math.cos(a) * r, math.sin(a) * r
			cyl(s, 0.8, 1.6, x, 0.8, z, DARK, M.Metal)
			ball(s, 0.7, P(x, 1.75, z), accent, M.Neon)
		end
		if id == "ACID" then
			cyl(s, 1.6, 1.2, 0, 0.6, 0, rgb(70, 90, 40), M.Slate)
			ball(s, 1.1, P(0, 1.3, 0), accent, M.Neon)
		else
			table.insert(s, {
				size = Vector3.new(1, 2.4, 1),
				cf = P(0, 1.2, 0) * A(0, math.rad(45), 0),
				color = accent,
				mat = M.Glass,
				transparency = 0.2,
			})
		end
	elseif id == "HARVEST" then
		base(s, accent, 4.4)
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2
			table.insert(s, {
				size = Vector3.new(0.5, 5.2, 0.5),
				cf = P(math.cos(a) * 1.4, 2.6, math.sin(a) * 1.4) * A(0, -a, 0) * A(0, 0, math.rad(15)),
				color = DARK,
				mat = M.Metal,
			})
		end
		blk(s, Vector3.new(1.8, 1, 1.8), P(0, 5.2, 0), hull)
		table.insert(s, {
			size = Vector3.new(1.3, 2.6 + lvl * 0.5, 1.3),
			cf = P(0, 1.8, 0) * A(0, math.rad(45), 0),
			color = accent,
			mat = M.Neon,
			role = "glow",
		})
	elseif id == "CORE" then
		-- an enemy extractor: our rig in hostile red over a crystal
		cyl(s, 15, 0.5, 0, 0.25, 0, DARK, M.Basalt, "body")
		table.insert(s, {
			size = Vector3.new(5, 15, 5),
			cf = P(0, 7.5, 0) * A(0, math.rad(45), math.rad(5)),
			color = rgb(255, 80, 120),
			mat = M.Neon,
			role = "body",
			transparency = 0.25,
		})
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2 + math.rad(30)
			table.insert(s, {
				size = Vector3.new(1.1, 20, 1.1),
				cf = P(math.cos(a) * 3.8, 9.6, math.sin(a) * 3.8) * A(0, -a, 0) * A(0, 0, math.rad(-20)),
				color = rgb(150, 60, 70),
				mat = M.Metal,
			})
		end
		blk(s, Vector3.new(4.5, 2.6, 4.5), P(0, 19, 0), HOSTILE, M.Metal)
		for k = 1, 3 do
			cyl(s, 15 - k * 2.4, 0.3, 0, 3 + k * 3.6, 0, HOSTILE, M.Neon, "glow")
			s[#s].transparency = 0.55
		end
	else
		base(s, accent, 4)
	end
	return s
end

-- An anchored model at a world position, facing -Z by default.
function Structures.model(id: string, lvl: number, hostile: boolean?): Model
	local specs = {}
	for _, sp in Structures.specs(id, lvl, hostile) do
		table.insert(specs, {
			shape = if sp.shape == Enum.PartType.Ball
				then "Ball"
				elseif sp.shape == Enum.PartType.Cylinder then "Cylinder"
				else "Block",
			size = sp.size,
			cf = sp.cf,
			color = sp.color,
			mat = sp.mat,
			transparency = sp.transparency,
			mesh = sp.mesh,
			name = if sp.role == "glow" or sp.role == "eye" then "Glow" else nil,
		})
	end
	local m = Models.build(specs, true)
	m.Name = "Structure_" .. id
	return m
end

return Structures
