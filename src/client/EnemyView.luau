--!nonstrict
-- Renders server enemies (packed snapshots) as pooled multi-part creatures moved with one BulkMoveTo
-- per frame. Snapshot interpolation plus a procedural "alive" layer: velocity-matched gait with leg
-- lift and body bob, banking into turns, idle breathing and blinking, anticipation crouch + tremble
-- on wind-ups, lunges, directional hit reactions (knock spring + flinch + fading white flash),
-- footstep dust for heavies, burrow-out dust on spawn and death scatter along the killing shot.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Codec = require(Shared:WaitForChild("Codec"))
local Settings = require(script.Parent.Settings)
local Fx = require(script.Parent.Fx)

local ST = Codec.State
local FLAG = Codec.Flag
local rgb = Color3.fromRGB
local M = Enum.Material
local HIDDEN = CFrame.new(0, -500, 0)
local SNAP_DT = 1 / 15

local EnemyView = {}

local folder: Folder
local pools: { [number]: { any } } = {}
local records: { [number]: any } = {}
local ignore: { [number]: number } = {}
local dying: { any } = {}
local bars = {}
local moveParts: { BasePart } = {}
local moveCFs: { CFrame } = {}

local STRIDE, HEAVY, WHITE
local Creatures = require(script.Parent.Creatures)
local BLUEPRINT = Creatures.Blueprints

-- Instances ----------------------------------------------------------------------------------------
local function buildModel(kind: number)
	local specs, gaitScale = BLUEPRINT[kind]()
	local model =
		{ kind = kind, parts = {}, specs = specs, gait = gaitScale, bodies = {}, eyes = {}, nodes = {}, sacs = {} }
	for _, sp in specs do
		if sp.seg then
			model.hasSegments = true
		end
	end
	for i, spec in specs do
		local p = if spec.mesh then spec.mesh:Clone() else Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = kind >= 4 and Settings.quality >= 3
		p.Size = spec.size
		p.Color = spec.color
		p.Material = spec.mat
		p.Transparency = spec.transparency or 0
		if spec.shape then
			p.Shape = spec.shape
		end
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = HIDDEN
		p.Parent = folder
		model.parts[i] = p
		if spec.role == "body" then
			table.insert(model.bodies, i)
		elseif spec.role == "eye" then
			table.insert(model.eyes, i)
		elseif spec.role == "node" then
			table.insert(model.nodes, i)
		elseif spec.role == "sac" then
			table.insert(model.sacs, i)
		end
	end
	return model
end

-- Places a Devourer body segment along the recorded head trail.
local function segmentCFrame(rec, spec, y)
	local trail = rec.trail
	local want = spec.cf.Position.Z
	local acc = 0
	local point, ahead = nil, nil
	if trail and #trail > 1 then
		for k = 2, #trail do
			local a, b = trail[k - 1], trail[k]
			local seg = (a - b).Magnitude
			if acc + seg >= want then
				local f = (want - acc) / math.max(seg, 1e-3)
				point = a:Lerp(b, f)
				ahead = a
				break
			end
			acc += seg
		end
		if not point then
			local last, prev = trail[#trail], trail[math.max(1, #trail - 1)]
			local dir = if (prev - last).Magnitude > 1e-3 then (prev - last).Unit else Vector3.zAxis
			point = last - dir * (want - acc)
			ahead = last
		end
	else
		local back = Vector3.new(math.sin(rec.face), 0, math.cos(rec.face))
		point = Vector3.new(rec.dx, 0, rec.dz) - back * want
		ahead = point + back
	end
	local look = ahead - point
	if look.Magnitude < 1e-3 then
		look = Vector3.zAxis
	end
	local sink = (rec.sink or 0) * (1 - math.clamp(spec.seg / 9, 0, 0.8))
	return CFrame.lookAt(point, point + look)
		* CFrame.new(spec.cf.Position.X, spec.cf.Position.Y + y * (1 - sink * 0.2), 0)
		* spec.cf.Rotation
end

local function acquire(kind: number)
	local pool = pools[kind]
	local m = pool and table.remove(pool)
	if m then
		return m
	end
	return buildModel(kind)
end

local function release(m)
	for i, p in m.parts do
		local spec = m.specs[i]
		p.CFrame = HIDDEN
		p.Transparency = spec.transparency or 0
		p.Color = spec.color
		p.Size = spec.size
		if spec.mesh and spec.mesh:IsA("MeshPart") and spec.mesh.TextureID ~= "" then
			p.TextureID = spec.mesh.TextureID -- a flash may have been cut short
		end
	end
	pools[m.kind] = pools[m.kind] or {}
	table.insert(pools[m.kind], m)
end

-- HP bars for elites & hives
local function attachBar(rec)
	local def = Defs.EnemyByIndex[rec.kind]
	local BAR = {
		[5] = "ЭЛИТА",
		[6] = "ГНЕЗДО",
		[10] = "НОСИТЕЛЬ ЯДРА",
		[11] = "ПИТАЮЩИЙ УЗЕЛ",
		[12] = "КИСЛОТНЫЙ ИСТОЧНИК",
	}
	if not BAR[rec.kind] then
		return
	end
	local elite = rec.kind == 5 or rec.kind == 10
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 14)
	gui.StudsOffsetWorldSpace = Vector3.new(0, if elite then 9 else 11, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = anchor
	gui.Parent = anchor
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(0, 0, 0)
	back.BackgroundTransparency = 0.35
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = if elite
		then rgb(255, 200, 60)
		elseif rec.kind == 11 then rgb(180, 120, 255)
		else rgb(170, 255, 80)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 14)
	label.Position = UDim2.fromOffset(0, -15)
	label.Text = BAR[rec.kind]
	label.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
	label.TextSize = 14
	label.TextColor3 = fill.BackgroundColor3
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	rec.bar = { anchor = anchor, fill = fill }
	bars[rec] = true
	return def
end

local function detachBar(rec)
	if rec.bar then
		rec.bar.anchor:Destroy()
		rec.bar = nil
		bars[rec] = nil
	end
end

-- API ---------------------------------------------------------------------------------------------
function EnemyView.init()
	folder = Instance.new("Folder")
	folder.Name = "SwarmView"
	folder.Parent = workspace
	-- Warm pools so the first waves never hitch, once the server's art templates have arrived: a body
	-- built before that is the fallback one and would stay in the pool for the whole session.
	task.spawn(function()
		local art = game:GetService("ReplicatedStorage"):WaitForChild("ArtTemplates", 20)
		local t0 = os.clock()
		while art and not art:GetAttribute("Ready") and os.clock() - t0 < 20 do
			task.wait(0.2)
		end
		local warm = { [1] = 40, [2] = 10, [3] = 8, [4] = 6 }
		for kind, n in warm do
			pools[kind] = pools[kind] or {}
			for _ = 1, n do
				table.insert(pools[kind], buildModel(kind))
			end
			task.wait()
		end
	end)
end

EnemyView.records = records

function EnemyView.clear()
	for id, rec in records do
		release(rec.model)
		detachBar(rec)
		records[id] = nil
	end
	for _, d in dying do
		release(d.model)
	end
	table.clear(dying)
	table.clear(ignore)
end

-- rows: decoded records, count: number
function EnemyView.snapshot(rows, count: number)
	local now = os.clock()
	local seen = {}
	for i = 1, count do
		local r = rows[i]
		local id = r.id
		if ignore[id] then
			continue
		end
		seen[id] = true
		local rec = records[id]
		if not rec then
			rec = {
				id = id,
				kind = r.kind,
				model = acquire(r.kind),
				px = r.x,
				pz = r.z,
				cx = r.x,
				cz = r.z,
				dx = r.x,
				dz = r.z,
				pf = r.facing,
				cfAngle = r.facing,
				face = r.facing,
				t0 = now,
				born = now,
				flash = 0,
				phase = math.random() * math.pi * 2,
				radius = Defs.EnemyByIndex[r.kind].radius,
				maxHp = Defs.EnemyByIndex[r.kind].hp,
				vx = 0,
				vz = 0,
				speed = 0,
				gait = math.random() * 10,
				yawRate = 0,
				kx = 0,
				kz = 0,
				kvx = 0,
				kvz = 0,
				tilt = 0,
				tiltV = 0,
				flashT = -1,
				blinkAt = now + math.random() * 4,
			}
			records[id] = rec
			attachBar(rec)
			if r.state == ST.SPAWN and Settings.quality >= 2 then
				local big = r.kind >= 4
				Fx.emit("dust", Vector3.new(r.x, 0.6, r.z), if big then 4 else 2)
			end
			-- A brood mutant (another player's strain, DD-039): toxic-lime glands, a sickly shell.
			if bit32.band(r.flags, 32) ~= 0 then
				local mutant = Color3.fromRGB(150, 255, 90)
				for i, p in rec.model.parts do
					local spec = rec.model.specs[i]
					if spec.name == "Nodule" or spec.role == "sac" or spec.role == "glow" then
						p.Color = mutant
					elseif spec.name == "Shell" then
						p.Color = spec.color:Lerp(Color3.fromRGB(120, 200, 70), 0.45)
					end
				end
			end
			if r.state == ST.SPAWN and EnemyView.onSpawn then
				EnemyView.onSpawn(r.x, r.z, r.kind)
			end
		else
			rec.vx = (r.x - rec.cx) / SNAP_DT
			rec.vz = (r.z - rec.cz) / SNAP_DT
			rec.px, rec.pz = rec.dx, rec.dz
			rec.pf = rec.face
			rec.cx, rec.cz = r.x, r.z
			rec.cfAngle = r.facing
			rec.t0 = now
		end
		if rec.state ~= r.state then
			rec.stateSince = now
		end
		rec.state = r.state
		rec.flags = r.flags
		rec.hp = r.hp
	end
	for id, rec in records do
		if not seen[id] then
			release(rec.model)
			detachBar(rec)
			records[id] = nil
		end
	end
end

-- Shove + flinch along a world direction (local hit prediction or server damage source).
local function push(rec, dx: number, dz: number, strength: number)
	local big = rec.kind >= 5
	local k = strength * (if big then 0.25 else if rec.kind == 4 then 0.55 else 1)
	rec.kvx += dx * 16 * k
	rec.kvz += dz * 16 * k
	rec.tiltV += 9 * k
	rec.lastHitDx, rec.lastHitDz = dx, dz
	rec.lastPush = os.clock()
end

function EnemyView.impulse(id: number, dx: number, dz: number, strength: number)
	local rec = records[id]
	if rec then
		push(rec, dx, dz, strength)
		if os.clock() - rec.flashT > 0.15 then
			rec.flashT = os.clock()
		end
	end
end

-- Server damage event: flash, and shove away from the source if no local shot already did.
function EnemyView.flash(id: number, fromX: number?, fromZ: number?, amount: number?)
	local rec = records[id]
	if not rec then
		return
	end
	local now = os.clock()
	-- short, rate-limited flash: continuous damage (beam, burn) must not keep bodies white
	if now - rec.flashT > 0.15 then
		rec.flashT = now
	end
	if fromX and (not rec.lastPush or now - rec.lastPush > 0.2) then
		local dx, dz = rec.dx - fromX, rec.dz - fromZ
		local m = math.sqrt(dx * dx + dz * dz)
		if m > 0.01 then
			local strength = math.clamp((amount or 10) / math.max(1, rec.maxHp) * 3, 0.15, 0.8)
			push(rec, dx / m, dz / m, strength)
		end
	end
end

-- Returns position of a live enemy (for FX), or nil.
function EnemyView.position(id: number): Vector3?
	local rec = records[id]
	if rec then
		return Vector3.new(rec.dx, Defs.EnemyByIndex[rec.kind].radius + 0.5, rec.dz)
	end
	return nil
end

function EnemyView.kill(id: number, dirX: number?, dirZ: number?)
	local rec = records[id]
	ignore[id] = os.clock() + 2
	if not rec then
		return nil
	end
	records[id] = nil
	detachBar(rec)
	if not dirX and rec.lastHitDx then
		dirX, dirZ = rec.lastHitDx, rec.lastHitDz
	end
	local m = rec.model
	local parts = {}
	local scatter = Settings.quality >= 2 and rec.kind ~= 7
	for i, p in m.parts do
		local v = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.5, math.random() - 0.5)
			* (if rec.kind >= 4 then 18 else 24)
		if dirX then
			v += Vector3.new(dirX, 0, dirZ) * (if rec.kind >= 4 then 10 else 22)
		end
		parts[i] = {
			p = p,
			v = v,
			spin = Vector3.new(math.random() * 12 - 6, math.random() * 12 - 6, math.random() * 12 - 6),
			cf = p.CFrame,
			color = m.specs[i].color,
		}
		p.Color = Color3.new(1, 1, 1)
		-- textured pieces drop the texture so the white flash and the darkening show (release restores it)
		if p:IsA("MeshPart") and p.TextureID ~= "" then
			p.TextureID = ""
		end
	end
	table.insert(
		dying,
		{
			model = m,
			parts = parts,
			t = 0,
			life = if rec.kind == 7 or rec.kind == 9 then 1.6 elseif rec.kind >= 4 then 0.8 else 0.6,
			scatter = scatter,
		}
	)
	return Vector3.new(rec.dx, 1, rec.dz)
end

-- Local hit prediction against rendered positions (2D). Returns distance to first enemy or nil.
function EnemyView.raycast(ox: number, oz: number, dx: number, dz: number, maxDist: number): (number?, any)
	local best, bestRec = nil, nil
	for _, rec in records do
		local rad = rec.radius + 0.45
		local cx, cz = rec.dx - ox, rec.dz - oz
		local along = cx * dx + cz * dz
		if along > 0 and along < maxDist + rad then
			local perp2 = cx * cx + cz * cz - along * along
			if perp2 < rad * rad then
				local entry = along - math.sqrt(rad * rad - perp2)
				if entry < (best or maxDist) then
					best, bestRec = entry, rec
				end
			end
		end
	end
	return best, bestRec
end

-- All enemies along a ray (sorted by entry distance), up to cap.
function EnemyView.raycastAll(ox: number, oz: number, dx: number, dz: number, maxDist: number, cap: number)
	local out = {}
	for _, rec in records do
		local rad = rec.radius + 0.45
		local cx, cz = rec.dx - ox, rec.dz - oz
		local along = cx * dx + cz * dz
		if along > 0 and along < maxDist + rad then
			local perp2 = cx * cx + cz * cz - along * along
			if perp2 < rad * rad then
				table.insert(out, { d = along - math.sqrt(rad * rad - perp2), rec = rec })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.d < b.d
	end)
	for i = #out, cap + 1, -1 do
		out[i] = nil
	end
	return out
end

function EnemyView.nearestInCone(ox: number, oz: number, dx: number, dz: number, maxDist: number, cosLimit: number)
	local best, bx, bz = math.huge, nil, nil
	for _, rec in records do
		local cx, cz = rec.dx - ox, rec.dz - oz
		local d = math.sqrt(cx * cx + cz * cz)
		if d > 0.1 and d < maxDist and (cx * dx + cz * dz) / d > cosLimit then
			local score = d * (2 - (cx * dx + cz * dz) / d)
			if score < best then
				best, bx, bz = score, cx / d, cz / d
			end
		end
	end
	return bx, bz
end

-- Gait radians per stud travelled, per enemy kind (small skitterers step fast, giants slow).
STRIDE = {
	[1] = 1.35,
	[2] = 0.9,
	[3] = 1.1,
	[4] = 0.75,
	[5] = 0.6,
	[6] = 0,
	[7] = 0.22,
	[8] = 1.6,
	[9] = 0.3,
	[10] = 0.6,
	[11] = 0,
	[12] = 0,
}
HEAVY = { [4] = true, [5] = true, [7] = true, [10] = true }
WHITE = Color3.new(1, 1, 1)

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

function EnemyView.update(dt: number, camPos: Vector3)
	local now = os.clock()
	local n = 0
	local animate = Settings.quality >= 2
	local farDist = Settings.Budget.animDistance[Settings.quality]
	for id, rec in records do
		local alpha = math.clamp((now - rec.t0) / SNAP_DT, 0, 1)
		rec.dx = rec.px + (rec.cx - rec.px) * alpha
		rec.dz = rec.pz + (rec.cz - rec.pz) * alpha
		rec.face = lerpAngle(rec.pf, rec.cfAngle, alpha)
		local m = rec.model
		local state = rec.state
		local y = 0
		local tilt = 0
		local shakeX = 0
		local life = now - rec.born
		if state == ST.SPAWN or state == ST.ENTER then
			y = math.min(0, -4 + life * 6)
		end
		if rec.kind == 9 then
			if state == ST.ENTER then
				y = math.min(0, -16 + life * 5)
			elseif state == ST.IDLE then
				rec.sink = math.min(1, (rec.sink or 0) + dt * 2.5)
				y = -16 * rec.sink
			elseif rec.sink and rec.sink > 0 then
				rec.sink = math.max(0, rec.sink - dt * 3)
				y = -16 * rec.sink
			end
		end
		-- Motion estimate: smoothed speed and turn rate drive gait and banking.
		local spdNow = math.sqrt(rec.vx * rec.vx + rec.vz * rec.vz)
		rec.speed += (spdNow - rec.speed) * (1 - math.exp(-dt * 8))
		local lastFace = rec.lastFace or rec.face
		local dFace = (rec.face - lastFace + math.pi) % (2 * math.pi) - math.pi
		rec.lastFace = rec.face
		rec.yawRate += (dFace / math.max(dt, 1e-3) - rec.yawRate) * (1 - math.exp(-dt * 6))
		local scale = math.max(0.6, rec.radius / 1.3)
		local sf = math.clamp(rec.speed / 6, 0, 1)
		rec.gait += dt * rec.speed * (STRIDE[rec.kind] or 1)
		local gait = rec.gait
		-- Hit reaction springs (world knock offset + flinch tilt).
		rec.kvx += (-rec.kx * 260 - rec.kvx * 16) * dt
		rec.kvz += (-rec.kz * 260 - rec.kvz * 16) * dt
		rec.kx += rec.kvx * dt
		rec.kz += rec.kvz * dt
		rec.tiltV += (-rec.tilt * 300 - rec.tiltV * 18) * dt
		rec.tilt += rec.tiltV * dt
		local pullZ = 0
		local roll = math.clamp(-rec.yawRate * 0.05, -0.3, 0.3) + math.sin(gait) * 0.05 * sf
		y += math.abs(math.sin(gait)) * 0.16 * scale * sf
		if sf < 0.3 then
			y += math.sin(now * 2.2 + rec.phase) * 0.06 * scale -- breathing
		end
		local since = now - (rec.stateSince or now)
		if state == ST.WINDUP then
			-- anticipation: rear back, crouch, tremble harder as the strike nears
			local k = math.clamp(since / 0.45, 0, 1)
			shakeX = math.sin(now * 70) * 0.07 * (0.4 + k) * scale
			pullZ = 0.45 * k * scale
			y -= 0.22 * k * scale
			tilt = 0.18 * k
		elseif state == ST.ATTACK then
			tilt = -0.22
			pullZ = -0.35 * scale
		elseif state == ST.RECOVER then
			tilt = 0.06 * math.max(0, 1 - since * 3)
		elseif state == ST.STUN then
			tilt = math.sin(now * 25) * 0.15
			roll += math.sin(now * 19) * 0.12
		end
		local base = CFrame.new(rec.dx + rec.kx, y, rec.dz + rec.kz)
			* CFrame.Angles(0, rec.face + math.pi, 0)
			* CFrame.new(shakeX, 0, pullZ)
			* CFrame.Angles(tilt + rec.tilt, 0, roll)
		-- gait
		local attacking = state == ST.ATTACK
		local far = (camPos - base.Position).Magnitude > farDist
		if m.hasSegments then
			-- Trail of head positions for the Devourer's body.
			local trail = rec.trail
			if not trail then
				trail = {}
				rec.trail = trail
			end
			local head = Vector3.new(rec.dx, 0, rec.dz)
			if #trail == 0 or (trail[1] - head).Magnitude > 0.8 then
				table.insert(trail, 1, head)
				if #trail > 140 then
					trail[#trail] = nil
				end
			end
		end
		local legAmp = 0.45 * m.gait * math.max(sf, if attacking then 1 else 0)
		local legT = if attacking then now * 30 else gait
		for i, p in m.parts do
			local spec = m.specs[i]
			local cf
			if spec.seg then
				cf = segmentCFrame(rec, spec, y)
			elseif spec.hip and animate and not far then
				local lp = legT + spec.phase
				local swing = math.sin(lp) * legAmp
				local lift = math.max(0, math.cos(lp)) * 0.25 * scale * math.min(1, legAmp * 3)
				cf = base * spec.hip * CFrame.new(0, lift, 0) * CFrame.Angles(swing, 0, 0) * spec.loc
			else
				cf = base * spec.cf
			end
			n += 1
			moveParts[n] = p
			moveCFs[n] = cf
		end
		-- Footstep dust for heavies.
		if HEAVY[rec.kind] and animate and not far and sf > 0.3 then
			local stepIndex = math.floor(gait / math.pi)
			if stepIndex ~= rec.stepIndex then
				rec.stepIndex = stepIndex
				Fx.emit("dust", Vector3.new(rec.dx, 0.4, rec.dz), if rec.kind == 7 then 3 else 1)
			end
		end
		-- Colors: fading white hit flash, status tint
		local flash = math.clamp(1 - (now - rec.flashT) / 0.09, 0, 1)
		if flash > 0 or rec.wasFlash or rec.flags ~= rec.lastFlags then
			rec.wasFlash = flash > 0
			rec.lastFlags = rec.flags
			local tint = nil
			if bit32.band(rec.flags, FLAG.BURN) ~= 0 then
				tint = rgb(255, 120, 40)
			elseif bit32.band(rec.flags, FLAG.SLOW) ~= 0 then
				tint = rgb(140, 210, 255)
			elseif bit32.band(rec.flags, FLAG.CORRODE) ~= 0 then
				tint = rgb(170, 255, 80)
			end
			for _, i in m.bodies do
				local spec = m.specs[i]
				local c = spec.color
				if tint then
					c = c:Lerp(tint, 0.45)
				end
				local p = m.parts[i]
				p.Color = if flash > 0 then c:Lerp(WHITE, 0.2 + 0.6 * flash) else c
				-- a texture ignores Color: textured art meshes (DD-042) drop it for the flash frames and
				-- while a status tints them (burning / frozen / corroded must read on every species)
				local tex = spec.mesh and spec.mesh:IsA("MeshPart") and spec.mesh.TextureID
				if tex and tex ~= "" then
					p.TextureID = if flash > 0 or tint then "" else tex
				end
			end
		end
		-- Blinking
		if #m.eyes > 0 and animate then
			local closed = now > rec.blinkAt and now < rec.blinkAt + 0.11
			if now > rec.blinkAt + 0.11 then
				rec.blinkAt = now + 1.5 + math.random() * 4
			end
			if closed ~= (rec.wasClosed == true) then
				rec.wasClosed = closed
				for _, i in m.eyes do
					m.parts[i].Transparency = if closed then 1 else (m.specs[i].transparency or 0)
				end
			end
		end
		local exposed = bit32.band(rec.flags, FLAG.EXPOSED) ~= 0
		if #m.eyes > 0 then
			local hot = state == ST.WINDUP or state == ST.ATTACK
			if hot ~= rec.wasHot then
				rec.wasHot = hot
				for _, i in m.eyes do
					m.parts[i].Color = if hot then rgb(255, 40, 40) else m.specs[i].color
				end
			end
		end
		for _, i in m.nodes do
			m.parts[i].Transparency = if exposed then 0 else 0.55 + math.sin(now * 3) * 0.2
			m.parts[i].Color = if exposed then rgb(255, 255, 140) else m.specs[i].color
		end
		if #m.sacs > 0 and (animate or rec.kind == 8) then
			local fuse = rec.kind == 8 and state == ST.WINDUP
			local pulse = if fuse then (math.sin(now * 40) + 1) / 2 else (math.sin(now * 4 + rec.phase) + 1) / 2
			for _, i in m.sacs do
				local p = m.parts[i]
				p.Transparency = if fuse then 0 else (m.specs[i].transparency or 0) + pulse * 0.3
				if rec.kind == 8 then
					local white = fuse and pulse > 0.5
					p.Color = if white then Color3.new(1, 1, 1) else m.specs[i].color
					p.Size = m.specs[i].size * (if fuse then 1 + pulse * 0.25 else 1)
					local tex = m.specs[i].mesh and m.specs[i].mesh.TextureID
					if tex and tex ~= "" then
						p.TextureID = if white then "" else tex
					end
				end
			end
		end
		if rec.bar then
			rec.bar.anchor.CFrame = CFrame.new(rec.dx, 0, rec.dz)
			rec.bar.fill.Size = UDim2.fromScale(math.clamp(rec.hp or 1, 0, 1), 1)
		end
	end
	-- Dying scatter
	local i = 1
	while i <= #dying do
		local d = dying[i]
		d.t += dt
		local k = d.t / d.life
		if k >= 1 then
			release(d.model)
			dying[i] = dying[#dying]
			dying[#dying] = nil
		else
			for _, piece in d.parts do
				if d.scatter then
					piece.v += Vector3.new(0, -90 * dt, 0)
					local pos = piece.cf.Position + piece.v * dt
					if pos.Y < 0.2 then
						pos = Vector3.new(pos.X, 0.2, pos.Z)
						piece.v = Vector3.new(piece.v.X * 0.5, -piece.v.Y * 0.3, piece.v.Z * 0.5)
					end
					piece.cf = CFrame.new(pos)
						* piece.cf.Rotation
						* CFrame.Angles(piece.spin.X * dt, piece.spin.Y * dt, piece.spin.Z * dt)
				else
					piece.cf = piece.cf - Vector3.new(0, dt * 6, 0)
				end
				if d.t < 0.2 then
					piece.p.Color = WHITE:Lerp(piece.color:Lerp(Color3.new(0, 0, 0), 0.35), d.t / 0.2)
				end
				n += 1
				moveParts[n] = piece.p
				moveCFs[n] = piece.cf
				if k > 0.45 then
					piece.p.Transparency = math.max(piece.p.Transparency, (k - 0.45) / 0.55)
				end
			end
			i += 1
		end
	end
	for k = #moveParts, n + 1, -1 do
		moveParts[k] = nil
		moveCFs[k] = nil
	end
	if n > 0 then
		workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	for id, untilT in ignore do
		if now > untilT then
			ignore[id] = nil
		end
	end
end

function EnemyView.count(): number
	local n = 0
	for _ in records do
		n += 1
	end
	return n
end

return EnemyView
