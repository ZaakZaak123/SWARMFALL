--!nonstrict
-- Art pass for the Bloom Crater (DD-042): landmarks and dressing from the generated mesh set. Each
-- builder returns true when it built from meshes; Arena falls back to its primitive builder otherwise.
-- Yaw constants rotate each mesh so its "front" faces where the layout needs it (verified in Studio).

local ArtLoader = require(script.Parent.ArtLoader)
local Art = require(game.ReplicatedStorage.Shared.Art)

local ArenaArt = {}

local rgb = Color3.fromRGB
-- (the generated skull's snout points along its native -Z already)
local YAW = { SKULL = 0, DROPSHIP = math.pi / 2, RIB = 0, EXTRACTOR = 0 } -- the plane wreck lies along the rim (DD-062)

local function has(...)
	for _, key in { ... } do
		if not ArtLoader.get(key) then
			return false
		end
	end
	return true
end

-- Uniform scale so the mesh's largest horizontal side matches `width`.
local function fitScale(key: string, width: number): number
	local s = ArtLoader.get(key).Size
	return width / math.max(s.X, s.Z)
end

local function put(key: string, parent, pos: Vector3, scale, yaw: number?, sink: number?)
	local p = ArtLoader.place(key, parent, CFrame.new(pos) * CFrame.Angles(0, (yaw or 0) + (YAW[key] or 0), 0), scale)
	if p and sink then
		p.CFrame -= Vector3.new(0, sink * p.Size.Y, 0)
	end
	return p
end

local function glowLight(parent, pos: Vector3, color: Color3, range: number, brightness: number)
	-- An attachment only works under a BasePart, and WorldPosition only means world space once it is
	-- parented (before that it is the local offset, which put these lights in the middle of the bowl).
	if not parent:IsA("BasePart") then
		local holder = Instance.new("Part")
		holder.Name = "GlowHolder"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one * 0.2
		holder.CFrame = CFrame.new(pos)
		holder.Parent = parent
		parent = holder
	end
	local a = Instance.new("Attachment")
	a.Parent = parent
	a.WorldPosition = pos
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l:SetAttribute("Ambient", true) -- clients may switch it off on lower quality (DecorLod)
	l.Parent = a
	return l
end

-- North: the titan's skull in the rim, ribs arching over the approach, vertebrae leading to it.
function ArenaArt.titan(map, decor, H): boolean
	if not has("SKULL", "RIB") then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "Titan"
	model.Parent = decor
	-- the skull lies in a notch cut into the rim, jaws at the north spawn: the swarm pours out of its mouth
	workspace.Terrain:FillBlock(CFrame.new(0, 40, 166), Vector3.new(84, 80, 64), Enum.Material.Air)
	local skull = put("SKULL", model, H.W(0, 0, 160), 2.2, 0, 0.04)
	skull.CastShadow = true
	H.fade(skull)
	local sz = skull.Size
	for _, s in { -1, 1 } do
		local eye = skull.CFrame:PointToWorldSpace(Vector3.new(s * sz.X * 0.2, sz.Y * 0.1, -sz.Z * 0.2))
		glowLight(model, eye, rgb(60, 245, 210), 40, 3)
	end
	-- the wound under the jaw: an ember glow on the ground, spores boiling out
	local mouth = H.W(0, 0, 128)
	H.disc(model, mouth + Vector3.new(0, 0.05, 0), 24, 0.05, rgb(255, 90, 40), Enum.Material.Neon, 0.55)
	H.light(model, mouth + Vector3.new(0, 6, -4), rgb(255, 120, 50), 44, 3)
	local vent = H.part(model, {
		Name = "Wound",
		Size = Vector3.new(18, 1, 10),
		CFrame = CFrame.new(mouth + Vector3.new(0, 1, 4)),
		Transparency = 1,
	})
	H.spores(vent, rgb(255, 120, 50), 10, 0.8, 2)
	-- ribs: one arch per pair of feet, spanning the corridor
	for _, o in map.obstacles do
		if o.name:match("^RibW") then
			local span = math.abs(o.x) * 2 + 10
			local s = ArtLoader.get("RIB").Size
			local rib =
				put("RIB", model, Vector3.new(0, 0, o.z), Vector3.new(span / s.X, (30 + (110 - o.z) * 0.2) / s.Y, 1.3))
			H.fade(rib)
		end
	end
	if ArtLoader.get("VERTEBRA") then
		for k = 0, 8 do
			local z = 60 + k * 7.6
			put("VERTEBRA", model, H.W(H.rnd(-1, 1), 0, z), 1.1 - k * 0.02, H.rnd(-0.3, 0.3), 0.35)
		end
		for i = 1, 10 do
			local x, z = H.rnd(-60, 60), H.rnd(55, 128)
			if H.clearOf(map, -x, z, 5) and math.abs(x) > 8 then
				put("VERTEBRA", model, H.W(x, 0, z), H.rnd(0.5, 0.9), H.rnd(0, 6.28), 0.45)
			end
		end
	end
	return true
end

-- South: the dropship on its pad, ramp toward the crater.
function ArenaArt.dropship(map, decor, H): boolean
	if not has("DROPSHIP") then
		return false
	end
	local o
	for _, ob in map.obstacles do
		if ob.style == "dropship" then
			o = ob
		end
	end
	local model = Instance.new("Model")
	model.Name = "Dropship"
	model.Parent = decor
	-- set back from the nav box so the lobby spots and the hero camera stay clear of the hull; the south
	-- spawn (z -128) stays behind it
	local ship = put("DROPSHIP", model, Vector3.new(o.x, 0, o.z - 4), fitScale("DROPSHIP", 26))
	ship.CastShadow = true
	H.fade(ship)
	-- warm light spilling from the hold, floodlights over the landing zone
	H.light(model, Vector3.new(o.x, 5, o.z + 8), rgb(255, 210, 150), 22, 1.2, true)
	for _, s in { -1, 1 } do
		local base = Vector3.new(o.x + s * 22, 0, o.z + 12)
		H.rod(model, base, base + Vector3.new(0, 9, 0), 0.7, rgb(52, 56, 66), Enum.Material.Metal)
		local head = H.part(model, {
			Size = Vector3.new(2.4, 1.2, 1.2),
			CFrame = CFrame.lookAt(base + Vector3.new(0, 9.4, 0), Vector3.new(0, 0, o.z + 60)),
			Color = rgb(255, 235, 200),
			Material = Enum.Material.Neon,
		})
		local sl = Instance.new("SpotLight")
		sl.Angle = 60
		sl.Range = 60
		sl.Brightness = 1.4
		sl.Color = rgb(255, 225, 190)
		sl.Shadows = false
		sl.Parent = head
	end
	-- landing pad: a faint ring and a slightly darker floor (it sat under the old raised terrain, DD-049)
	H.disc(decor, Vector3.new(0, 0.03, o.z + 14), 30, 0.05, rgb(255, 150, 40), Enum.Material.Neon, 0.9)
	H.disc(decor, Vector3.new(0, 0.04, o.z + 14), 28, 0.05, rgb(70, 64, 92), Enum.Material.SmoothPlastic, 0.55)
	return true
end

-- Centre: the drill rig over the mother crystal. Keeps the names the client animates (HaloRing, Core).
function ArenaArt.extractor(o, decor, H): boolean
	local drill = Art.Industrial.DRILL
	if has("IND_DRILL_1", "IND_DRILL_2", "IND_DRILL_3") then
		local model = Instance.new("Model")
		model.Name = "Reactor"
		model.Parent = decor
		local c = Vector3.new(o.x, 0, o.z)
		-- Match the original collision footprint; keep the silhouette lower than the old rig.
		local k = 1.25
		for i, def in drill do
			local p = ArtLoader.place("IND_DRILL_" .. i, model, CFrame.new(c + def.pos * k), k, false)
			p.Name = if def.name == "auger" then "Auger" else def.name
			p.CastShadow = true
			H.fade(p)
		end
		local core = H.part(model, {
			Name = "Core",
			Size = Vector3.new(1.2, 0.35, 0.22),
			CFrame = CFrame.new(c + Vector3.new(0, 10, -6.15)),
			Color = rgb(255, 184, 70),
			Material = Enum.Material.Neon,
			Transparency = 0.12,
		})
		H.fade(core)
		H.light(model, c + Vector3.new(0, 5, 0), rgb(255, 196, 130), 12, 0.6, false)
		-- Low, subdued foundation: no airborne neon discs competing with attack telegraphs.
		H.disc(decor, c + Vector3.new(0, 0.025, 0), 25, 0.05, rgb(83, 76, 63), Enum.Material.Concrete, 0)
		return true
	end
	if not has("EXTRACTOR") then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "Reactor"
	model.Parent = decor
	local c = Vector3.new(o.x, 0, o.z)
	local rig = put("EXTRACTOR", model, c, fitScale("EXTRACTOR", 22), 0)
	rig.CastShadow = true
	H.fade(rig)
	-- an inner glow the client pulses: a working machine's warm amber, not the swarm's pink (DD-063)
	local core = H.part(model, {
		Name = "Core",
		Size = Vector3.new(3, 9, 3),
		CFrame = CFrame.new(c + Vector3.new(0, 5, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = rgb(255, 168, 64),
		Material = Enum.Material.Neon,
		Transparency = 0.6,
	})
	H.fade(core)
	H.light(model, c + Vector3.new(0, 7, 0), rgb(255, 196, 130), 14, 1, true)
	for i = 1, 3 do
		local ring = H.disc(
			model,
			c + Vector3.new(0, 3 + i * 4, 0),
			18 - i * 2.6,
			0.3,
			rgb(60, 245, 210),
			Enum.Material.Neon,
			0.62
		)
		ring.Name = "HaloRing" .. i
		H.fade(ring)
	end
	-- the plaza: a slightly darker floor and a faint ring marking the defend zone
	H.disc(decor, c + Vector3.new(0, 0.03, 0), 28, 0.06, rgb(210, 120, 36), Enum.Material.Neon, 0.84)
	H.disc(decor, c + Vector3.new(0, 0.05, 0), 25, 0.06, rgb(64, 54, 86), Enum.Material.SmoothPlastic, 0.45)
	return true
end

-- East: crystal clusters on each obstacle, loose shards across the grove, spires beyond the rim.
function ArenaArt.grove(map, decor, H): boolean
	if not has("CRYSTALS") then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "Grove"
	model.Parent = decor
	local pink = rgb(255, 70, 190)
	for _, o in map.obstacles do
		if o.style == "crystal" then
			local p =
				put("CRYSTALS", model, Vector3.new(o.x, 0, o.z), fitScale("CRYSTALS", o.w * 1.35), H.rnd(0, 6.28), 0.05)
			H.fade(p)
			glowLight(p, Vector3.new(o.x, o.h * 0.6, o.z), pink, o.h * 1.5, 1.3)
		end
	end
	-- small clusters hug the east edge only; the floor itself stays clear (DD-047)
	for i = 1, 10 do
		local a = math.rad(H.rnd(-50, 50))
		local r = H.boundary(map, math.pi - a) - H.rnd(3, 9)
		local wx, z = -math.cos(a) * r, math.sin(a) * r
		if H.clearOf(map, wx, z, 3) then
			put("CRYSTALS", model, Vector3.new(wx, 0, z), H.rnd(0.18, 0.32), H.rnd(0, 6.28), 0.1)
		end
	end
	for i = 1, 5 do
		local a = math.rad(H.rnd(-40, 40))
		local r = H.rnd(160, 190)
		local pos = H.W(math.cos(a) * r, 0, math.sin(a) * r)
		local p = put("CRYSTALS", model, pos, H.rnd(2.4, 3.6), H.rnd(0, 6.28), 0.05)
		glowLight(p, pos + Vector3.new(0, p.Size.Y * 0.6, 0), pink, 36, 1)
	end
	return true
end

-- West: giant mushrooms on their stems, clusters of small ones and coral underfoot.
function ArenaArt.forest(map, decor, H): boolean
	if not has("MUSHROOM") then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "Forest"
	model.Parent = decor
	local teal = rgb(60, 245, 210)
	for _, o in map.obstacles do
		if o.style == "mushroom" then
			local p = put(
				"MUSHROOM",
				model,
				Vector3.new(o.x, 0, o.z),
				o.h * 1.15 / ArtLoader.get("MUSHROOM").Size.Y,
				H.rnd(0, 6.28)
			)
			H.fade(p)
			glowLight(p, Vector3.new(o.x, p.Size.Y * 0.62, o.z), teal, p.Size.X * 1.1, 1.2)
		end
	end
	-- undergrowth hugs the west edge only; the floor itself stays clear (DD-047)
	for i = 1, 16 do
		local a = math.rad(H.rnd(-55, 55))
		local r = H.boundary(map, a) - H.rnd(3, 10)
		local wx, z = math.cos(a) * r, math.sin(a) * r
		if H.clearOf(map, wx, z, 3) then
			local key = if i % 3 == 0 and ArtLoader.get("CORAL") then "CORAL" else "SHROOMS"
			if ArtLoader.get(key) then
				put(key, model, Vector3.new(wx, 0, z), H.rnd(0.8, 1.6), H.rnd(0, 6.28), 0.05)
			end
		end
	end
	return true
end

-- The rim: rock spires, giant blooms and mushrooms beyond the walkable edge.
function ArenaArt.rim(map, decor, H): boolean
	if not has("SPIRE", "BLOOM") then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "RimArt"
	model.Parent = decor
	for i = 0, 27 do
		local a = i / 28 * math.pi * 2 + H.rnd(-0.06, 0.06)
		local r = H.boundary(map, a) + H.rnd(14, 34)
		put("SPIRE", model, Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), H.rnd(1.1, 2.0), H.rnd(0, 6.28), 0.12)
	end
	local blooms = {
		{ 112, 1.3 },
		{ 68, 1.6 },
		{ 128, 1.4 },
		{ 52, 1.2 },
		{ 236, 1.5 },
		{ 304, 1.3 },
		{ 298, 1.0 },
		{ 200, 1.2 },
		{ 340, 1.25 },
	}
	for _, b in blooms do
		local a = math.rad(b[1])
		local r = H.boundary(map, a) + H.rnd(26, 40)
		local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local p = put("BLOOM", model, pos, b[2], H.rnd(0, 6.28))
		glowLight(p, pos + Vector3.new(0, p.Size.Y * 0.85, 0), rgb(255, 180, 90), 36, 1.2)
	end
	if ArtLoader.get("MUSHROOM") then
		-- mostly behind the mushroom forest (world +X)
		for _, deg in { -30, -14, 2, 18, 34, 120, 240 } do
			local a = math.rad(deg + H.rnd(-5, 5))
			local r = H.boundary(map, a) + H.rnd(30, 46)
			local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local p = put("MUSHROOM", model, pos, H.rnd(1.8, 2.6), H.rnd(0, 6.28))
			glowLight(p, pos + Vector3.new(0, p.Size.Y * 0.6, 0), rgb(60, 245, 210), 36, 1)
		end
	end
	return true
end

-- DD-058: what is left of the old world on the rim — broken concrete walls and rusted cars just past
-- the edge of the fight, so the danger zone reads as ruined infrastructure the swarm has overgrown.
function ArenaArt.ruins(map, decor, H): boolean
	if not has("RUIN_WALL", "CAR_WRECK") then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "Ruins"
	model.Parent = decor
	-- between the swarm's entrances (they sit every 45°), right at the edge of the floor
	for i = 0, 15 do
		local a = (i + 0.5) / 16 * math.pi * 2 + math.rad(11.25) + H.rnd(-0.05, 0.05)
		local r = H.boundary(map, a) + H.rnd(-1, 3)
		local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if i % 3 == 1 then
			put("CAR_WRECK", model, pos, H.rnd(1.3, 1.6), H.rnd(0, 6.28), 0.05)
		else
			-- walls stand along the rim, a little askew
			put("RUIN_WALL", model, pos, H.rnd(1.3, 1.8), -a + math.pi / 2 + H.rnd(-0.3, 0.3), 0.1)
		end
	end
	return true
end

-- Spore wounds at every swarm entrance but the titan's jaw: a hive nest grown into the rim, ember glow
-- spilling onto the floor and veins creeping toward the bowl.
function ArenaArt.wounds(map, decor, H): boolean
	if not has("NEST") then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "Wounds"
	model.Parent = decor
	local ember = rgb(255, 120, 50)
	for key, s in map.spawns do
		if key == "N" then
			continue
		end
		local a = math.atan2(s.z, s.x)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local at = dir * (H.boundary(map, a) + 5)
		local nest = put("NEST", model, at, 1.5, H.rnd(0, 6.28), 0.15)
		H.fade(nest)
		local inner = at - dir * 6
		H.disc(model, inner + Vector3.new(0, 0.05, 0), 14, 0.05, rgb(255, 90, 40), Enum.Material.Neon, 0.6)
		H.light(model, inner + Vector3.new(0, 5, 0), ember, 26, 2.2)
		for _ = 1, 5 do
			local ang = H.rnd(-0.9, 0.9)
			local len = H.rnd(6, 14)
			local d2 = (-dir * math.cos(ang) + Vector3.new(-dir.Z, 0, dir.X) * math.sin(ang))
			local base = at - dir * 3
			H.part(model, {
				Size = Vector3.new(0.45, 0.08, len),
				CFrame = CFrame.lookAt(
					base + d2 * len / 2 + Vector3.new(0, 0.06, 0),
					base + d2 * len + Vector3.new(0, 0.06, 0)
				),
				Color = ember,
				Material = Enum.Material.Neon,
				Transparency = 0.35,
			})
		end
		local vent = H.part(
			model,
			{ Size = Vector3.new(6, 1, 6), CFrame = CFrame.new(inner + Vector3.new(0, 1, 0)), Transparency = 1 }
		)
		H.spores(vent, ember, 3, 0.6, 1.5)
	end
	return true
end

-- Boulders on their obstacles (the nav already blocks them).
function ArenaArt.boulders(map, decor, H): boolean
	if not has("BOULDER") then
		return false
	end
	for _, o in map.obstacles do
		if o.style == "boulder" then
			local p =
				put("BOULDER", decor, Vector3.new(o.x, 0, o.z), fitScale("BOULDER", o.w * 1.25), H.rnd(0, 6.28), 0.12)
			p.CastShadow = true
			-- DD-062: the generated rock is painted violet-crystal; the ruined world wants plain stone
			p.TextureID = ""
			p.Material = Enum.Material.Slate
			p.Color = rgb(150, 142, 132)
		end
	end
	return true
end

-- Spore pylons: the generated crystal flower + the named parts the client colours by cooldown.
function ArenaArt.pylon(o, decor, index: number, H, padRadius: number): boolean
	if not has("PYLON") then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "Coil" .. index
	model:SetAttribute("CoilIndex", index)
	model.Parent = decor
	local c = Vector3.new(o.x, 0, o.z)
	put("PYLON", model, c, o.h * 1.15 / ArtLoader.get("PYLON").Size.Y, H.rnd(0, 6.28))
	local orb = H.ball(model, c + Vector3.new(0, o.h * 1.05, 0), 1.6, rgb(60, 245, 210), Enum.Material.Neon)
	orb.Name = "Orb"
	local l = Instance.new("PointLight")
	l.Name = "Glow"
	l.Color = rgb(60, 245, 210)
	l.Range = 12 -- a halo on the pylon, not a pool across the lane
	l.Brightness = 1.1
	l.Parent = orb
	for k = 1, 2 do
		local ring = H.disc(
			model,
			c + Vector3.new(0, o.h * (0.35 + k * 0.22), 0),
			4.6 - k * 0.8,
			0.3,
			rgb(60, 245, 210),
			Enum.Material.Neon,
			0.25
		)
		ring.Name = "Ring"
	end
	local pad =
		H.disc(model, c + Vector3.new(0, 0.05, 0), padRadius * 2, 0.06, rgb(60, 245, 210), Enum.Material.Neon, 0.75)
	pad.Name = "Pad"
	return true
end

return ArenaArt
