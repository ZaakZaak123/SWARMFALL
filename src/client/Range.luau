--!nonstrict
-- The shooting range on the base (DD-055): step on the firing mark and the gun works — aim, fire, the
-- real muzzle, tracers, sounds and recoil — at three practice dummies that wobble, flash and count the
-- damage per second. Client-only: nothing is simulated or rewarded, it is a place to feel a gun (or a
-- freshly bought one) without starting a run. Uses the selected weapon's own numbers.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Theme = require(script.Parent.Theme)
local Fx = require(script.Parent.Fx)
local Audio = require(script.Parent.Audio)
local Shots = require(script.Parent.Shots)
local Models = require(script.Parent.Models)

local new, C, F = Theme.new, Theme.C, Theme.F

local Range = {}

local Layout = require(Shared:WaitForChild("ShelterLayout"))
local Grove = require(Shared:WaitForChild("Grove"))
-- The firing mark in the shelter; the dummies stand east (screen-left). DD-087: on the plot's frame.
local frame = Grove.frame(1)
local MARK, DUMMIES
local MARK_R = 5
local function place()
	MARK = frame:PointToWorldSpace(Vector3.new(Layout.RangeMark.x, 0, Layout.RangeMark.z))
	DUMMIES = {}
	for i, d in Layout.RangeDummies do
		DUMMIES[i] = frame:PointToWorldSpace(Vector3.new(d[1], 0, d[2]))
	end
end
place()
local DUMMY_R = 2.4

local folder
local dummies = {} -- { pos, model, wobble, flash, highlight }
local board, boardText, hint
local active = false
local fireAcc = 0
local log = {} -- { t, amount } for the last few seconds (DPS)
local lastHit = 0
local beamOn = false

local function part(props)
	local p = new("Part", props)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

function Range.init(parent: Instance)
	folder = new("Folder", { Name = "Range", Parent = parent })
	-- firing mark
	local mark =
		part({ Name = "Mark", Size = Vector3.new(MARK_R * 2, 0.05, MARK_R * 2), Transparency = 1, Parent = folder })
	mark.CFrame = CFrame.new(MARK + Vector3.new(0, 0.3, 0))
	new(
		"Decal",
		{ Face = Enum.NormalId.Top, Texture = Fx.Tex.ring, Color3 = C.red, Transparency = 0.25, Parent = mark }
	)
	hint = new("BillboardGui", {
		Size = UDim2.fromOffset(220, 44),
		StudsOffsetWorldSpace = Vector3.new(0, 6, 0),
		LightInfluence = 0,
		AlwaysOnTop = true,
		MaxDistance = 120,
		Adornee = mark,
		Parent = mark,
	})
	local t = Theme.label(
		"ТИР",
		{ Size = UDim2.new(1, 0, 0, 24), FontFace = F.display, TextSize = 22, TextColor3 = C.red, Parent = hint }
	)
	new("UIStroke", { Color = C.ink, Thickness = 2.5, Parent = t })
	local s = Theme.label("Встань в круг и стреляй", {
		Name = "Sub",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 16),
		FontFace = F.bodyBold,
		TextSize = 13,
		TextColor3 = C.dim,
		Parent = hint,
	})
	new("UIStroke", { Color = C.ink, Thickness = 2, Parent = s })
	-- dummies: a practice runner on a post
	for i, pos in DUMMIES do
		local holder = new("Model", { Name = "Dummy" .. i, Parent = folder })
		local post = part({
			Name = "Post",
			Size = Vector3.new(0.6, 2, 0.6),
			Color = Color3.fromRGB(60, 52, 74),
			Material = Enum.Material.Metal,
			Parent = holder,
		})
		post.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
		local ok, body = pcall(Models.creature, 1)
		if ok and body then
			for _, d in body:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.Color = d.Color:Lerp(Color3.fromRGB(170, 160, 190), 0.55)
				end
			end
			local _, size = body:GetBoundingBox()
			pcall(body.ScaleTo, body, body:GetScale() * (3.2 / math.max(size.Y, 0.1)))
			local cf, sz = body:GetBoundingBox()
			body.WorldPivot = CFrame.new(cf.X, cf.Y - sz.Y / 2, cf.Z)
			body.Parent = holder
		end
		local hl = new("Highlight", {
			FillColor = C.white,
			FillTransparency = 1,
			OutlineTransparency = 1,
			DepthMode = Enum.HighlightDepthMode.Occluded,
			Parent = holder,
		})
		dummies[i] = { pos = pos, model = body, wobble = 0, flash = 0, highlight = hl }
	end
	-- DPS board over the middle dummy
	local anchor = part({ Name = "Board", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Parent = folder })
	anchor.CFrame = CFrame.new(DUMMIES[2] + Vector3.new(0, 7.5, 0))
	board = new("BillboardGui", {
		Size = UDim2.fromOffset(180, 40),
		LightInfluence = 0,
		AlwaysOnTop = true,
		MaxDistance = 120,
		Enabled = false,
		Adornee = anchor,
		Parent = anchor,
	})
	boardText = Theme.label(
		"",
		{ Size = UDim2.fromScale(1, 1), FontFace = F.display, TextSize = 22, TextColor3 = C.gold, Parent = board }
	)
	new("UIStroke", { Color = C.ink, Thickness = 2.5, Parent = boardText })
end

-- The shelter moved to another plot (DD-087): the range moves with it.
function Range.setFrame(cf: CFrame)
	if cf == frame then
		return
	end
	frame = cf
	place()
	local parent = folder.Parent
	folder:Destroy()
	table.clear(dummies)
	Range.init(workspace)
	folder.Parent = parent
end

function Range.setVisible(on: boolean)
	local want = if on then workspace else nil
	if folder.Parent ~= want then
		folder.Parent = want
	end
end

function Range.isActive(): boolean
	return active
end

-- Is the hunter standing on the firing mark?
function Range.wants(root: Vector3?): boolean
	if not root then
		return false
	end
	local d = Vector3.new(root.X - MARK.X, 0, root.Z - MARK.Z).Magnitude
	return d < MARK_R + (if active then 2 else 0) -- a little hysteresis
end

-- First dummy along a ray in the ground plane (2D circle test).
local function trace(ox: number, oz: number, dx: number, dz: number, maxD: number)
	local best, bestD = nil, maxD
	for _, dm in dummies do
		local px, pz = dm.pos.X - ox, dm.pos.Z - oz
		local along = px * dx + pz * dz
		if along > 0 and along < bestD then
			local side = math.abs(px * dz - pz * dx)
			if side < DUMMY_R then
				local d = along - math.sqrt(DUMMY_R * DUMMY_R - side * side)
				if d < bestD then
					best, bestD = dm, d
				end
			end
		end
	end
	return best, bestD
end

local function hit(dm, amount: number, at: Vector3, dir: Vector3)
	dm.wobble = math.min(1, dm.wobble + 0.35)
	dm.flash = 1
	dm.dir = dir
	table.insert(log, { t = os.clock(), amount = amount })
	lastHit = os.clock()
	Fx.number(at + Vector3.new(0, 2.5, 0), amount, C.white, false)
end

-- Per frame. Returns whether the range is driving the gun this frame.
function Range.update(
	dt: number,
	root: Vector3?,
	character: Model?,
	weapon: string,
	aimX: number,
	aimZ: number,
	firing: boolean
): boolean
	local now = os.clock()
	-- DD-091: the range's sign only near it (from across the yard it was one more label over the intro)
	local away = if root then Vector3.new(root.X - MARK.X, 0, root.Z - MARK.Z).Magnitude else math.huge
	hint.Enabled = away < (if hint.Enabled then 32 else 26)
	local want = Range.wants(root)
	if want ~= active then
		active = want
		hint.Sub.Text = if active
			then "Огонь — ЛКМ / правый стик / кнопка"
			else "Встань в круг и стреляй"
		if not active then
			fireAcc = 0
			if beamOn then
				beamOn = false
				Shots.beamStop("range", character)
				Audio.loop("beam", Audio.Ids.beam, 0, 1)
			end
		end
	end
	-- dummies breathe back from hits
	for _, dm in dummies do
		dm.wobble = math.max(0, dm.wobble - dt * 2.2)
		dm.flash = math.max(0, dm.flash - dt * 8)
		dm.highlight.FillTransparency = 1 - dm.flash * 0.7
		if dm.model then
			local d = dm.dir or Vector3.xAxis
			local tilt = math.sin(now * 22) * dm.wobble * 0.25
			dm.model:PivotTo(
				CFrame.new(dm.pos + Vector3.new(0, 2, 0))
					* CFrame.Angles(d.Z * tilt, 0, -d.X * tilt)
					* frame.Rotation
					* CFrame.Angles(0, math.pi / 2, 0)
			)
		end
	end
	-- damage per second over the last 3 s
	local sum, t0 = 0, now - 3
	for i = #log, 1, -1 do
		if log[i].t < t0 then
			table.remove(log, i)
		else
			sum += log[i].amount
		end
	end
	board.Enabled = now - lastHit < 4
	boardText.Text = string.format("УРОН/С  %d", math.floor(sum / 3 + 0.5))
	if not active or not root then
		return false
	end
	local wdef = Defs.Weapons[weapon]
	if not wdef or not firing then
		fireAcc = math.max(0, fireAcc - dt)
		if beamOn then
			beamOn = false
			Shots.beamStop("range", character)
			Audio.loop("beam", Audio.Ids.beam, 0, 1)
		end
		return true
	end
	if wdef.kind == "beam" then
		-- a continuous beam: drawn every frame, damage ticks at the weapon's rate
		local origin = root + Vector3.new(aimX, 1.4, aimZ) * 1.5
		local dm, d = trace(origin.X, origin.Z, aimX, aimZ, wdef.range)
		local to = Vector3.new(origin.X + aimX * d, 1.6, origin.Z + aimZ * d)
		Shots.beam("range", character, weapon, false, origin, to, dm ~= nil, true)
		Audio.loop("beam", Audio.Ids.beam, 0.3, 1.05)
		beamOn = true
		fireAcc -= dt
		while fireAcc <= 0 do
			fireAcc += 1 / wdef.rate
			if dm then
				hit(dm, math.floor(wdef.damage + 0.5), to, Vector3.new(aimX, 0, aimZ))
			end
		end
		return true
	end
	fireAcc -= dt
	local guard = 0
	while fireAcc <= 0 and guard < 3 do
		guard += 1
		fireAcc += 1 / math.max(0.5, wdef.rate)
		local origin = root + Vector3.new(aimX, 1.4, aimZ) * 1.5
		local base = math.atan2(aimX, aimZ)
		local items = {}
		local pellets = if wdef.kind == "shotgun" then wdef.pellets else 1
		local half = math.rad(if wdef.kind == "shotgun" then wdef.spread else (wdef.spreadMin or 1)) / 2
		for _ = 1, pellets do
			local a = base + (math.random() * 2 - 1) * half
			local dx, dz = math.sin(a), math.cos(a)
			local dm, d = trace(origin.X, origin.Z, dx, dz, wdef.range)
			local to = Vector3.new(origin.X + dx * d, 1.6, origin.Z + dz * d)
			local item = { to = to }
			if dm then
				item.hits = { { pos = to } }
				hit(dm, math.floor(wdef.damage + 0.5), to, Vector3.new(dx, 0, dz))
			end
			table.insert(items, item)
		end
		Shots.fire(character, weapon, false, origin, items, true, false, 1)
	end
	return true
end

return Range
