--!nonstrict
-- Art pass for the funnel (DD-042): the drill, the pylons, xenite, boulders and the rim's ruins from the
-- generated mesh set. Each builder returns true when it built from meshes; Arena falls back to its
-- primitive builder otherwise. The rest of the place is ArenaScene (DD-091).
-- Yaw constants rotate each mesh so its "front" faces where the layout needs it (verified in Studio).

local ArtLoader = require(script.Parent.ArtLoader)
local Art = require(game.ReplicatedStorage.Shared.Art)

local ArenaArt = {}

local rgb = Color3.fromRGB
local YAW = { EXTRACTOR = 0 }

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

-- East: xenite growing out of the rubble (DD-091). Its glow stays on the crystals — a pool of pink light
-- on the floor read as a stain or a telegraph — and nothing of it stands beyond the rim.
function ArenaArt.grove(map, decor, H): boolean
	if not has("CRYSTALS") then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "Grove"
	model.Parent = decor
	local pink = rgb(255, 92, 190)
	for _, o in map.obstacles do
		if o.style == "crystal" then
			local p =
				put("CRYSTALS", model, Vector3.new(o.x, 0, o.z), fitScale("CRYSTALS", o.w * 1.35), H.rnd(0, 6.28), 0.05)
			H.fade(p)
			glowLight(p, Vector3.new(o.x, o.h * 0.6, o.z), pink, o.w * 0.9, 0.7)
			if has("RUBBLE") then
				for k = 1, 3 do
					local a = k / 3 * math.pi * 2 + H.rnd(-0.4, 0.4)
					local d = o.w * 0.55
					put(
						"RUBBLE",
						model,
						Vector3.new(o.x + math.cos(a) * d, 0, o.z + math.sin(a) * d),
						H.rnd(0.9, 1.4),
						H.rnd(0, 6.28),
						0.2
					)
				end
			end
		end
	end
	-- small clusters hug the east edge only; the floor itself stays clear (DD-047)
	for i = 1, 6 do
		local a = math.rad(H.rnd(-50, 50))
		local r = H.boundary(map, math.pi - a) - H.rnd(3, 8)
		local wx, z = -math.cos(a) * r, math.sin(a) * r
		if H.clearOf(map, wx, z, 3) then
			put("CRYSTALS", model, Vector3.new(wx, 0, z), H.rnd(0.16, 0.26), H.rnd(0, 6.28), 0.15)
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
		local deg = math.deg(a) % 360
		local entrance = math.abs((deg + 22.5) % 45 - 22.5) < 10
		if entrance or deg > 70 and deg < 110 or math.abs(deg - 145) < 12 then
			continue -- the swarm's drains, the breach and the cableway's portal stay clear (DD-091)
		end
		if i % 3 == 1 then
			put("CAR_WRECK", model, pos, H.rnd(1.3, 1.6), H.rnd(0, 6.28), 0.05)
		else
			-- walls stand along the rim, a little askew
			put("RUIN_WALL", model, pos, H.rnd(1.3, 1.8), -a + math.pi / 2 + H.rnd(-0.3, 0.3), 0.1)
		end
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
			p.Material = Enum.Material.Rock -- (Slate carries the retired violet variant, DD-091)
			p.Color = rgb(150, 140, 128)
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
