--!nonstrict
-- The house in the shelter (DD-093, ex-the SHELTER mesh). Owner: «переработай модель домика, сделай его
-- доступным для входа … качественное чиловое место, чтоб захотелось туда заходить после боя и отдыхать и
-- собраться с друзьями». A timber cabin built from parts on a concrete plinth: plank walls patched with rusty
-- sheets, a tin gable roof, a brick chimney that smokes, a porch with a bench and a lantern, warm windows.
-- Inside (DD-093: roomy, ~32 × 22): a stove with a fire and two armchairs, a couch, a table for six,
-- a hanging and a standing lamp, fairy lights, a wind-up gramophone (the shelter's music on and off), a bookcase, a
-- guitar, a clock, and the owner's keepsakes: a cork board with a note for every sortie won, a cup on the
-- shelf for every boss beaten, a jar with the first xenite, the old photos, a child's drawing, a teddy bear.
-- The seats are the server's (server/Home.furnish at shared/ShelterLayout.Cabin) under the chairs drawn here.
-- Walk in and the roof and the walls between the camera and the hero fade out (a cutaway: the camera looks
-- in from where it was instead of popping to the hero's back).
--
-- Cabin.build(cf, parent, opts) -> cabin   cf: the floor centre on the ground, -Z = the door side
--   opts.detail   where the small things go (default the cabin's folder; the settlement shows them near)
--   opts.own      the gramophone answers here (the own shelter)
-- cabin:setEntry(entry)   the keepsakes of the owner's showcase entry (shared/Showcase)
-- cabin:setPower(on)      the electric lights (the generator)
-- cabin:step(dt, root)    cutaway, fire, clock, record

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Layout = require(Shared:WaitForChild("ShelterLayout"))
local Ops = require(Shared:WaitForChild("Ops"))
local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.Audio)
local Fx = require(script.Parent.Fx)

local Cabin = {}
Cabin.__index = Cabin

local rgb = Color3.fromRGB
local M = Enum.Material
local BLOCK, CYL, BALL = Enum.PartType.Block, Enum.PartType.Cylinder, Enum.PartType.Ball

local F = Layout.Cabin.floor -- the boards' top
local BASE = 1.4 -- the plinth's top: where the walls stand
local TOP = BASE + 12 -- the walls' top
local RIDGE = TOP + 7.5
local HX, HZ = 16.4, 11.6 -- the walls' centre lines (DD-093: a roomy house, ~32 × 22 inside)
local PITCH = math.atan2(RIDGE - TOP, HZ + 0.4)

local P = {
	plank = rgb(128, 94, 64),
	plankIn = rgb(150, 112, 76),
	trim = rgb(72, 52, 38),
	wood = rgb(104, 74, 50),
	dark = rgb(58, 42, 32),
	concrete = rgb(134, 130, 122),
	rust = rgb(124, 78, 52),
	tin = rgb(112, 108, 102),
	brick = rgb(136, 74, 56),
	soot = rgb(34, 30, 28),
	glass = rgb(255, 214, 160),
	fabric = rgb(76, 102, 90),
	cushion = rgb(92, 120, 104),
	rug = rgb(128, 52, 42),
	rugEdge = rgb(190, 148, 88),
	brass = rgb(196, 150, 72),
	gold = rgb(236, 190, 84),
	paper = rgb(236, 226, 200),
	warm = rgb(255, 196, 130),
	leaf = rgb(86, 132, 62),
}

local function mk(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat, props): BasePart
	local shape = props and props.Shape
	local p
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
		p.Shape = shape or BLOCK
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or M.SmoothPlastic
	if props then
		for k, v in props do
			if k ~= "Shape" then
				(p :: any)[k] = v
			end
		end
	end
	p.Parent = parent
	return p
end

-- A picture on a part's front face, drawn with frames (no images to upload): an old family photo, a
-- child's drawing.
local function canvas(part: BasePart, bg: Color3): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.CanvasSize = Vector2.new(200, 160)
	g.LightInfluence = 1
	g.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	g.Parent = part
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = bg
	f.BorderSizePixel = 0
	f.Parent = g
	return g
end
local function blob(
	parent: Instance,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	round: boolean?,
	rot: number?
)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = rot or 0
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end
local function text(
	parent: Instance,
	s: string,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	font,
	rot: number?
)
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(x, y)
	t.Size = UDim2.fromScale(w, h)
	t.BackgroundTransparency = 1
	t.Text = s
	t.TextScaled = true
	t.TextColor3 = color
	t.FontFace = font or Font.fromEnum(Enum.Font.GothamBold)
	t.Rotation = rot or 0
	t.Parent = parent
	return t
end

-- the family before the Fall: three figures and a child on a sepia print
local function familyPhoto(part: BasePart)
	local g = canvas(part, rgb(196, 168, 120))
	local f = g:GetChildren()[1]
	blob(f, 0.5, 0.78, 1, 0.44, rgb(160, 132, 92))
	local ink = rgb(84, 62, 44)
	for _, fig in { { 0.3, 0.42, 1 }, { 0.52, 0.4, 1.06 }, { 0.71, 0.56, 0.62 } } do
		local x, y, s = fig[1], fig[2], fig[3]
		blob(f, x, y, 0.1 * s, 0.13 * s, ink, true)
		blob(f, x, y + 0.26 * s, 0.17 * s, 0.34 * s, ink, true)
	end
	blob(f, 0.85, 0.2, 0.12, 0.15, rgb(232, 210, 160), true)
end
-- a crayon house, a sun and «возвращайся!»
local function childDrawing(part: BasePart)
	local g = canvas(part, rgb(246, 242, 230))
	local f = g:GetChildren()[1]
	blob(f, 0.8, 0.2, 0.18, 0.22, rgb(250, 196, 40), true)
	blob(f, 0.38, 0.62, 0.34, 0.3, rgb(214, 80, 60))
	blob(f, 0.38, 0.44, 0.3, 0.06, rgb(120, 70, 40), false, -24)
	blob(f, 0.38, 0.44, 0.3, 0.06, rgb(120, 70, 40), false, 24)
	blob(f, 0.38, 0.68, 0.08, 0.18, rgb(120, 70, 40))
	blob(f, 0.5, 0.86, 1, 0.08, rgb(90, 170, 70))
	blob(f, 0.76, 0.66, 0.06, 0.12, rgb(60, 60, 80), true)
	blob(f, 0.76, 0.76, 0.1, 0.16, rgb(60, 110, 200), true)
	text(f, "ВОЗВРАЩАЙСЯ!", 0.5, 0.1, 0.62, 0.14, rgb(60, 90, 200), Font.fromEnum(Enum.Font.Cartoon), -4)
end

function Cabin.build(cf: CFrame, parent: Instance, opts)
	opts = opts or {}
	local self = setmetatable({}, Cabin)
	local folder = Instance.new("Folder")
	folder.Name = "Cabin"
	local small = opts.detail or folder
	self.folder = folder
	self.cf = cf
	self.fade = { roof = {}, front = {}, back = {}, left = {}, right = {} } -- parts the cutaway fades
	self.guis = { front = {} }
	self.fadeK = 0
	self.power = nil
	self.bulbs = {}
	local function C(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function add(group: string?, p: BasePart): BasePart
		if group then
			table.insert(self.fade[group], p)
		end
		return p
	end
	local function face(yaw: number): CFrame
		return CFrame.Angles(0, yaw, 0)
	end
	local seats = Layout.Cabin.seats
	local W = HX + 0.4 -- half the outer length of the long walls
	local IX, IZ = HX - 0.4, HZ - 0.4 -- the room's inner faces

	-- the plinth, the floor ------------------------------------------------------------------------------
	mk(
		folder,
		Vector3.new(W * 2 + 1, BASE + 1, HZ * 2 + 1.6),
		C(0, (BASE - 1) / 2, 0),
		P.concrete,
		M.Concrete,
		{ CanCollide = true }
	)
	mk(folder, Vector3.new(IX * 2, 0.2, IZ * 2), C(0, F - 0.1, 0), P.plankIn, M.WoodPlanks, { CanCollide = true })

	-- the walls: a frame per side (local X along the wall, -Z out of the house), holes cut out ------------
	local sides = {
		front = { CFrame.new(0, 0, -HZ), W },
		back = { CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -HZ), W },
		left = { CFrame.Angles(0, -math.pi / 2, 0) * CFrame.new(0, 0, -HX), IZ }, -- +X, screen-left
		right = { CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, 0, -HX), IZ },
	}
	local function S(side: string, u: number, y: number, out: number): CFrame
		return cf * sides[side][1] * CFrame.new(u, y, -out)
	end
	local DOOR = 2.4
	-- windows { side, u0, u1, y0, y1, shutters } in the side's own u (back: u = -x, left: u = z, right: u = -z)
	local windows = {
		{ "front", -13, -9, F + 3.2, F + 7.8, true },
		{ "front", 9, 13, F + 3.2, F + 7.8, true },
		{ "back", 6, 11, F + 4.6, F + 8.6, false },
		{ "left", -6, -1, F + 4.4, F + 8.4, false },
		{ "right", -8, -5, F + 4.4, F + 8.4, false },
	}
	local holes = { front = { { -DOOR, DOOR, BASE, F + 8.8 } }, back = {}, left = {}, right = {} }
	for _, w in windows do
		table.insert(holes[w[1]], { w[2], w[3], w[4], w[5] })
	end
	for side, def in sides do
		local half = def[2]
		local cuts = { -half, half }
		for _, h in holes[side] do
			table.insert(cuts, h[1])
			table.insert(cuts, h[2])
		end
		table.sort(cuts)
		for i = 1, #cuts - 1 do
			local a, b = cuts[i], cuts[i + 1]
			if b - a > 0.01 then
				local spans = { { BASE, TOP } }
				for _, h in holes[side] do
					if h[1] <= a + 0.001 and h[2] >= b - 0.001 then
						spans = { { BASE, h[3] }, { h[4], TOP } }
					end
				end
				for _, sp in spans do
					if sp[2] - sp[1] > 0.01 then
						add(
							side,
							mk(
								folder,
								Vector3.new(b - a, sp[2] - sp[1], 0.8),
								S(side, (a + b) / 2, (sp[1] + sp[2]) / 2, 0),
								P.plank,
								M.WoodPlanks,
								{ CanCollide = true }
							)
						)
					end
				end
			end
		end
		-- a skirting board outside and a belt under the eaves
		add(side, mk(folder, Vector3.new(half * 2, 0.7, 0.2), S(side, 0, BASE + 0.35, 0.45), P.trim, M.Wood))
		add(side, mk(folder, Vector3.new(half * 2, 0.5, 0.2), S(side, 0, TOP - 0.25, 0.45), P.trim, M.Wood))
		-- the gable ends: a triangle of planks up to the ridge on the short sides
		if side == "left" or side == "right" then
			for _, s in { -1, 1 } do
				add(
					side,
					mk(
						folder,
						Vector3.new(0.8, RIDGE - TOP, HZ + 0.4),
						S(side, s * (HZ + 0.4) / 2, (TOP + RIDGE) / 2, 0) * CFrame.Angles(0, -s * math.pi / 2, 0),
						P.plank,
						M.WoodPlanks,
						{ Shape = "Wedge", CanCollide = true }
					)
				)
			end
		end
	end
	-- corner posts
	for _, x in { -HX, HX } do
		for _, z in { -HZ, HZ } do
			local grp = if z < 0 then "front" else "back"
			add(
				grp,
				mk(
					folder,
					Vector3.new(1.1, TOP - BASE + 0.2, 1.1),
					C(x, (BASE + TOP) / 2, z),
					P.trim,
					M.Wood,
					{ CanCollide = true }
				)
			)
		end
	end
	-- rusty sheets nailed over old holes
	for _, sh in
		{
			{ "back", -6, 4.6, 4.0, 4.2, P.rust, 0.06 },
			{ "back", 1.5, 3.6, 2.6, 3.0, P.tin, -0.04 },
			{ "left", 6, 5.4, 3.4, 4.6, P.rust, 0.05 },
			{ "right", 4.5, 4.6, 3.2, 3.6, P.tin, -0.05 },
			{ "front", -5.4, 3.6, 1.8, 2.2, P.rust, 0.08 },
			{ "front", 15, 6.4, 1.6, 3.2, P.tin, -0.03 },
		}
	do
		add(
			sh[1],
			mk(
				folder,
				Vector3.new(sh[4], sh[5], 0.08),
				S(sh[1], sh[2], sh[3], 0.45) * CFrame.Angles(0, 0, sh[7]),
				sh[6],
				M.CorrodedMetal
			)
		)
	end

	-- windows: glass, a frame with a cross, a sill; shutters and a flower box on the front ones; curtains in
	for _, w in windows do
		local side, u0, u1, y0, y1, shutters = w[1], w[2], w[3], w[4], w[5], w[6]
		local u, y, wd, ht = (u0 + u1) / 2, (y0 + y1) / 2, u1 - u0, y1 - y0
		add(
			side,
			mk(
				folder,
				Vector3.new(wd, ht, 0.15),
				S(side, u, y, 0),
				P.glass,
				M.Glass,
				{ Transparency = 0.45, CanCollide = true }
			)
		)
		for _, t in
			{
				{ wd + 0.7, 0.35, u, y1 + 0.17 },
				{ wd + 0.7, 0.35, u, y0 - 0.17 },
				{ 0.35, ht, u0 - 0.17, y },
				{ 0.35, ht, u1 + 0.17, y },
				{ 0.18, ht, u, y },
				{ wd, 0.18, u, y + ht * 0.08 },
			}
		do
			add(side, mk(folder, Vector3.new(t[1], t[2], 0.3), S(side, t[3], t[4], 0.1), P.trim, M.Wood))
		end
		add(side, mk(folder, Vector3.new(wd + 1, 0.25, 0.8), S(side, u, y0 - 0.45, 0.5), P.trim, M.Wood))
		if shutters then
			for _, s in { -1, 1 } do
				add(
					side,
					mk(
						folder,
						Vector3.new(wd / 2, ht + 0.2, 0.15),
						S(side, (if s < 0 then u0 else u1) + s * (wd / 4 + 0.25), y, 0.5)
							* CFrame.Angles(0, s * 0.12, 0),
						rgb(82, 104, 92),
						M.WoodPlanks
					)
				)
			end
			-- the flower box under the sill
			add(side, mk(small, Vector3.new(wd - 0.2, 0.8, 0.8), S(side, u, y0 - 1.1, 0.85), P.wood, M.WoodPlanks))
			for k = 0, 4 do
				local fu = u0 + 0.5 + k * (wd - 1) / 4
				add(
					side,
					mk(
						small,
						Vector3.new(0.7, 0.7, 0.7),
						S(side, fu, y0 - 0.45, 0.85),
						P.leaf,
						M.Grass,
						{ Shape = BALL }
					)
				)
				local bloom = if k % 2 == 0 then rgb(226, 92, 70) else rgb(240, 200, 80)
				add(
					side,
					mk(
						small,
						Vector3.new(0.38, 0.38, 0.38),
						S(side, fu + 0.1, y0 - 0.05, 0.9),
						bloom,
						M.SmoothPlastic,
						{ Shape = BALL, CastShadow = false }
					)
				)
			end
		end
		-- curtains, tied back on either side inside
		for _, s in { -1, 1 } do
			add(
				side,
				mk(
					small,
					Vector3.new(0.9, ht + 0.8, 0.15),
					S(side, (if s < 0 then u0 else u1) - s * 0.25, y + 0.2, -0.55),
					if side == "front" then rgb(176, 68, 52) else rgb(214, 196, 150),
					M.Fabric
				)
			)
		end
	end

	-- the door: open into the room along its jamb; its frame; a sign with the owner's name --------------
	for _, t in
		{
			{ 0.4, F + 9.2 - BASE, -DOOR - 0.2, (BASE + F + 9.2) / 2 },
			{ 0.4, F + 9.2 - BASE, DOOR + 0.2, (BASE + F + 9.2) / 2 },
			{ DOOR * 2 + 0.8, 0.45, 0, F + 9 },
		}
	do
		add("front", mk(folder, Vector3.new(t[1], t[2], 1.0), S("front", t[3], t[4], 0), P.trim, M.Wood))
	end
	-- the door leaf swings on its hinge (open into the room, or shut): the server keeps it open or shut for
	-- everyone (server/Home.furnish, a Door part with a prompt), step() follows it
	do
		local hinge = C(DOOR - 0.1, F + 4.3, -HZ + 0.4)
		local w = DOOR * 2 - 0.3
		local pieces = {}
		local function piece(p: BasePart, off: CFrame)
			table.insert(pieces, { p, off })
			return add("front", p)
		end
		local leaf = piece(mk(folder, Vector3.new(w, 8.6, 0.25), hinge, P.wood, M.WoodPlanks), CFrame.new(-w / 2, 0, 0))
		for _, y in { -2.8, 2.8 } do
			piece(mk(small, Vector3.new(w - 0.2, 0.35, 0.1), hinge, P.dark, M.Wood), CFrame.new(-w / 2, y, 0.15))
			piece(mk(small, Vector3.new(w - 0.2, 0.35, 0.1), hinge, P.dark, M.Wood), CFrame.new(-w / 2, y, -0.15))
		end
		for _, z in { -0.25, 0.25 } do
			piece(
				mk(small, Vector3.new(0.3, 0.3, 0.3), hinge, P.brass, M.Metal, { Shape = BALL }),
				CFrame.new(-w + 0.5, -0.2, z)
			)
		end
		self.door =
			{ hinge = hinge, pieces = pieces, leaf = leaf, angle = -1, open = true, at = C(0, F + 4.3, -HZ).Position }
	end
	local sign = add("front", mk(folder, Vector3.new(6.4, 1.0, 0.2), S("front", 0, F + 10.2, 0.6), P.dark, M.Wood))
	do
		local g = Instance.new("SurfaceGui")
		g.Face = Enum.NormalId.Front
		g.CanvasSize = Vector2.new(400, 64)
		g.LightInfluence = 1
		g.Parent = sign
		self.signText = text(g, "ДОМ", 0.5, 0.5, 0.94, 0.8, P.paper, Font.fromEnum(Enum.Font.Antique))
		table.insert(self.guis.front, g)
	end

	-- the porch: a deck, a step, posts with an awning, rails, a bench by the door, a lantern -----------
	local DZ = -HZ - 0.4 -- the front wall's face
	local PW, PD = 7, 5 -- the porch's half-width and depth
	mk(folder, Vector3.new(PW * 2, 0.4, PD), C(0, BASE - 0.2, DZ - PD / 2), P.wood, M.WoodPlanks, { CanCollide = true })
	mk(
		folder,
		Vector3.new(PW * 2 - 0.4, BASE + 0.6, PD - 0.2),
		C(0, (BASE - 0.6) / 2 - 0.2, DZ - PD / 2),
		P.dark,
		M.WoodPlanks,
		{ CanCollide = true }
	)
	mk(folder, Vector3.new(6, 1.4, 1.3), C(0, 0, DZ - PD - 0.65), P.wood, M.WoodPlanks, { CanCollide = true })
	local postZ = DZ - PD + 0.4
	for _, x in { -PW + 0.4, PW - 0.4 } do
		add(
			"front",
			mk(folder, Vector3.new(0.6, 10.4, 0.6), C(x, BASE + 5.2, postZ), P.trim, M.Wood, { CanCollide = true })
		)
	end
	add("front", mk(folder, Vector3.new(PW * 2 + 0.4, 0.5, 0.6), C(0, BASE + 10.2, postZ), P.trim, M.Wood))
	do
		local run, drop = PD + 0.6, 1.4
		local tilt = math.atan2(drop, run)
		add(
			"front",
			mk(
				folder,
				Vector3.new(PW * 2 + 1.4, 0.22, math.sqrt(run * run + drop * drop) + 0.3),
				C(0, TOP - 0.2 - drop / 2, DZ - run / 2) * CFrame.Angles(-tilt, 0, 0),
				P.rust,
				M.CorrodedMetal
			)
		)
	end
	for _, x in { -PW + 0.3, PW - 0.3 } do
		mk(folder, Vector3.new(0.25, 0.25, PD - 0.6), C(x, BASE + 3, DZ - PD / 2 + 0.1), P.trim, M.Wood)
		for k = 0, 2 do
			mk(small, Vector3.new(0.18, 3, 0.18), C(x, BASE + 1.5, DZ - 0.8 - k * 1.4), P.trim, M.Wood)
		end
	end
	for _, s in { -1, 1 } do
		mk(folder, Vector3.new(PW - 3.4, 0.25, 0.25), C(s * (PW + 3) / 2, BASE + 3, postZ), P.trim, M.Wood)
	end
	-- the bench (the porch seats of shared/ShelterLayout)
	do
		local b1, b2 = seats[12], seats[13]
		local bx, bz = (b1[1] + b2[1]) / 2, b1[2]
		mk(folder, Vector3.new(3.4, 0.25, 1.3), C(bx, BASE + 1.68, bz), P.wood, M.WoodPlanks, { CanCollide = true })
		for _, x in { -1.4, 1.4 } do
			mk(small, Vector3.new(0.3, 1.6, 1.1), C(bx + x, BASE + 0.8, bz), P.trim, M.Wood)
		end
	end
	mk(small, Vector3.new(3.6, 0.05, 1.8), C(0, BASE + 0.03, DZ - 1.4), rgb(120, 92, 60), M.Fabric)
	do
		local lantern = add(
			"front",
			mk(
				small,
				Vector3.new(0.7, 1.0, 0.7),
				C(-DOOR - 1.2, F + 6.8, DZ - 0.6),
				P.warm,
				M.Neon,
				{ CastShadow = false }
			)
		)
		add("front", mk(small, Vector3.new(0.9, 0.2, 0.9), C(-DOOR - 1.2, F + 7.4, DZ - 0.6), P.dark, M.Metal))
		add("front", mk(small, Vector3.new(0.15, 0.15, 0.7), C(-DOOR - 1.2, F + 7.4, DZ - 0.25), P.dark, M.Metal))
		local l = Instance.new("PointLight")
		l.Color = P.warm
		l.Range = 16
		l.Brightness = 1.2
		l.Parent = lantern
		self.lantern = { part = lantern, light = l }
	end

	-- the roof: two tin slopes with ribs on a timber lining, fascias, a ridge cap ------------------------
	local run = HZ + 1.8
	local slope = run / math.cos(PITCH)
	local RW = W * 2 + 2.8 -- with the overhang at the gables
	for _, s in { -1, 1 } do
		local base = C(0, RIDGE - run / 2 * math.tan(PITCH), s * run / 2) * CFrame.Angles(s * PITCH, 0, 0)
		add("roof", mk(folder, Vector3.new(RW, 0.4, slope), base * CFrame.new(0, 0.25, 0), P.rust, M.CorrodedMetal))
		add(
			"roof",
			mk(
				folder,
				Vector3.new(HX * 2 - 0.4, 0.15, slope - 2.2),
				base * CFrame.new(0, -0.02, -s * 0.9),
				P.plankIn,
				M.WoodPlanks
			)
		)
		for x = -RW / 2 + 0.6, RW / 2 - 0.5, 1.8 do
			add(
				"roof",
				mk(
					small,
					Vector3.new(0.22, 0.14, slope),
					base * CFrame.new(x, 0.5, 0),
					P.rust:Lerp(P.tin, 0.25),
					M.CorrodedMetal
				)
			)
		end
		add(
			"roof",
			mk(folder, Vector3.new(RW + 0.2, 0.7, 0.3), base * CFrame.new(0, 0.1, s * slope / 2), P.trim, M.Wood)
		)
		for _, x in { -RW / 2 - 0.05, RW / 2 + 0.05 } do
			add("roof", mk(folder, Vector3.new(0.3, 0.7, slope), base * CFrame.new(x, 0.15, 0), P.trim, M.Wood))
		end
	end
	add("roof", mk(folder, Vector3.new(RW + 0.4, 0.5, 1.6), C(0, RIDGE + 0.45, 0), P.tin, M.CorrodedMetal))
	-- the truss inside: tie beams, king posts, the ridge beam
	for _, x in { -10, 0, 10 } do
		add("roof", mk(folder, Vector3.new(0.7, 0.7, IZ * 2), C(x, TOP - 0.6, 0), P.dark, M.Wood))
		add(
			"roof",
			mk(folder, Vector3.new(0.5, RIDGE - TOP - 0.4, 0.5), C(x, (TOP + RIDGE) / 2 - 0.4, 0), P.dark, M.Wood)
		)
	end
	add("roof", mk(folder, Vector3.new(IX * 2, 0.7, 0.7), C(0, RIDGE - 0.5, 0), P.dark, M.Wood))

	-- the chimney on the right gable, the stove inside it -----------------------------------------------
	local SX, SZ = -IX, -1 -- the stove's back at the right wall's inner face
	local chim = add(
		"right",
		mk(
			folder,
			Vector3.new(2.8, RIDGE + 3, 3.2),
			C(-HX - 1.65, (RIDGE + 3) / 2 - 0.5, SZ),
			P.brick,
			M.Brick,
			{ CanCollide = true }
		)
	)
	add("right", mk(folder, Vector3.new(3.4, 0.5, 3.8), C(-HX - 1.65, RIDGE + 2.75, SZ), P.concrete, M.Concrete))
	do
		local a = Instance.new("Attachment")
		a.Position = Vector3.new(0, (RIDGE + 3) / 2 + 0.5, 0)
		a.Parent = chim
		local e = Instance.new("ParticleEmitter")
		e.Texture = Fx.Tex.smoke
		e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		e.Color = ColorSequence.new(rgb(176, 170, 162))
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 7) })
		e.Lifetime = NumberRange.new(5, 7)
		e.Rate = 2.2
		e.Speed = NumberRange.new(2, 3)
		e.SpreadAngle = Vector2.new(10, 10)
		e.Acceleration = Vector3.new(0.8, 0.3, 0.4)
		e.RotSpeed = NumberRange.new(-20, 20)
		e.Rotation = NumberRange.new(0, 360)
		e.LightInfluence = 1
		e.Parent = a
	end
	mk(folder, Vector3.new(3, 0.3, 7.6), C(SX + 1.5, F + 0.15, SZ), rgb(96, 90, 84), M.Concrete, { CanCollide = true })
	for _, s in { -1, 1 } do
		mk(folder, Vector3.new(2, 4.8, 1.4), C(SX + 1, F + 2.7, SZ + s * 2.8), P.brick, M.Brick, { CanCollide = true })
	end
	mk(folder, Vector3.new(0.3, 4.8, 4.2), C(SX + 0.15, F + 2.7, SZ), P.soot, M.Concrete)
	mk(folder, Vector3.new(2, 1.0, 7), C(SX + 1, F + 5.4, SZ), P.brick, M.Brick, { CanCollide = true })
	mk(folder, Vector3.new(1.5, TOP - F - 5.9, 5.4), C(SX + 0.75, (F + 5.9 + TOP) / 2, SZ), P.brick, M.Brick)
	mk(folder, Vector3.new(2.7, 0.35, 7.8), C(SX + 1.3, F + 6.05, SZ), P.dark, M.Wood)
	for k = -1, 1 do
		mk(
			small,
			Vector3.new(2.8, 0.55, 0.55),
			C(SX + 1.2, F + 0.65 + (if k == 0 then 0.38 else 0), SZ + k * 0.5) * CFrame.Angles(0, math.pi / 2, 0),
			rgb(92, 62, 40),
			M.Wood,
			{ Shape = CYL }
		)
	end
	local embers = mk(
		small,
		Vector3.new(1.5, 0.2, 3),
		C(SX + 1.2, F + 0.42, SZ),
		rgb(255, 120, 50),
		M.Neon,
		{ CastShadow = false }
	)
	do
		local fire = Instance.new("Fire")
		fire.Size = 3.6
		fire.Heat = 3
		fire.Color = rgb(255, 130, 50)
		fire.SecondaryColor = rgb(255, 214, 120)
		fire.Parent = embers
		local l = Instance.new("PointLight")
		l.Color = rgb(255, 150, 80)
		l.Range = 26
		l.Brightness = 2
		l.Shadows = true
		l.Parent =
			mk(small, Vector3.new(0.2, 0.2, 0.2), C(SX + 2.8, F + 2, SZ), P.warm, M.SmoothPlastic, { Transparency = 1 })
		self.fireLight = l
	end
	-- firewood stacked by the stove
	for row = 0, 2 do
		for k = 0, 2 - row do
			mk(
				small,
				Vector3.new(1.8, 0.55, 0.55),
				C(SX + 1.1, F + 0.3 + row * 0.48, SZ + 4.2 + (k - (2 - row) / 2) * 0.58),
				rgb(120, 86, 56):Lerp(rgb(84, 60, 40), (row + k) % 2 * 0.5),
				M.Wood,
				{ Shape = CYL }
			)
		end
	end
	-- a basket of logs on the other side
	mk(
		small,
		Vector3.new(1.4, 1.6, 1.6),
		C(SX + 1.2, F + 0.7, SZ - 4.4) * CFrame.Angles(0, 0, math.pi / 2),
		rgb(150, 116, 70),
		M.Fabric,
		{ Shape = CYL }
	)

	-- furniture -----------------------------------------------------------------------------------------
	local function chair(at: CFrame)
		for _, x in { -0.75, 0.75 } do
			for _, z in { -0.75, 0.75 } do
				mk(small, Vector3.new(0.25, 1.75, 0.25), at * CFrame.new(x, 0.875, z), P.wood, M.Wood)
			end
		end
		mk(
			folder,
			Vector3.new(1.9, 0.25, 1.9),
			at * CFrame.new(0, 1.78, 0),
			P.wood,
			M.WoodPlanks,
			{ CanCollide = true }
		)
		for _, x in { -0.75, 0.75 } do
			mk(folder, Vector3.new(0.25, 2.6, 0.25), at * CFrame.new(x, 3.1, 0.82), P.wood, M.Wood)
		end
		for _, y in { 2.7, 3.5 } do
			mk(small, Vector3.new(1.4, 0.35, 0.12), at * CFrame.new(0, y, 0.82), P.wood, M.Wood)
		end
		mk(folder, Vector3.new(1.95, 0.3, 0.28), at * CFrame.new(0, 4.35, 0.82), P.dark, M.Wood)
		mk(small, Vector3.new(1.6, 0.18, 1.6), at * CFrame.new(0, 1.99, 0), rgb(150, 70, 56), M.Fabric)
	end
	local function sofa(at: CFrame, width: number, n: number, color: Color3, cushion: Color3)
		mk(folder, Vector3.new(width, 1.1, 2.6), at * CFrame.new(0, 0.65, 0.1), color, M.Fabric, { CanCollide = true })
		mk(folder, Vector3.new(width, 2.3, 0.7), at * CFrame.new(0, 2.15, 1.05), color, M.Fabric, { CanCollide = true })
		for _, s in { -1, 1 } do
			mk(
				folder,
				Vector3.new(0.7, 1.9, 2.8),
				at * CFrame.new(s * (width / 2 - 0.35), 1.15, 0.05),
				color,
				M.Fabric,
				{ CanCollide = true }
			)
		end
		local inner = width - 1.4
		for k = 1, n do
			local x = -inner / 2 + (k - 0.5) * inner / n
			mk(small, Vector3.new(inner / n - 0.08, 0.5, 2.1), at * CFrame.new(x, 1.45, -0.15), cushion, M.Fabric)
			mk(
				small,
				Vector3.new(inner / n - 0.12, 1.5, 0.45),
				at * CFrame.new(x, 2.5, 0.55) * CFrame.Angles(-0.12, 0, 0),
				cushion,
				M.Fabric
			)
		end
		for _, x in { -width / 2 + 0.3, width / 2 - 0.3 } do
			for _, z in { -1, 1.2 } do
				mk(small, Vector3.new(0.35, 0.2, 0.35), at * CFrame.new(x, 0.1, z), P.dark, M.Wood)
			end
		end
	end
	-- the table and its six chairs (seats 1–6)
	local TX, TZ = 7, 2.5
	for k = 1, 6 do
		local s = seats[k]
		chair(C(s[1], F, s[2]) * face(s[3]))
	end
	mk(folder, Vector3.new(7.6, 0.35, 4.4), C(TX, F + 3.1, TZ), P.wood, M.WoodPlanks, { CanCollide = true })
	for _, x in { -3.4, 3.4 } do
		for _, z in { -1.8, 1.8 } do
			mk(folder, Vector3.new(0.4, 2.95, 0.4), C(TX + x, F + 1.47, TZ + z), P.dark, M.Wood, { CanCollide = true })
		end
	end
	local T = F + 3.28 -- the table's top
	for _, pl in { { -1.8, 1.4 }, { 1.8, 1.4 }, { -1.8, -1.4 }, { 1.8, -1.4 }, { -3, 0 }, { 3, 0 } } do
		mk(
			small,
			Vector3.new(0.06, 1.1, 1.1),
			C(TX + pl[1], T + 0.03, TZ + pl[2]) * CFrame.Angles(0, 0, math.pi / 2),
			rgb(214, 206, 188),
			M.SmoothPlastic,
			{ Shape = CYL }
		)
	end
	for _, mg in
		{
			{ -1, 1.0, rgb(150, 70, 52) },
			{ 1.1, 0.8, rgb(70, 96, 120) },
			{ 2.3, -0.7, rgb(200, 190, 170) },
			{ -2.4, -0.8, rgb(110, 130, 80) },
		}
	do
		mk(
			small,
			Vector3.new(0.6, 0.45, 0.45),
			C(TX + mg[1], T + 0.3, TZ + mg[2]) * CFrame.Angles(0, 0, math.pi / 2),
			mg[3],
			M.SmoothPlastic,
			{ Shape = CYL }
		)
	end
	-- an oil lamp, a bowl of apples, cards, a map under them
	mk(
		small,
		Vector3.new(2.6, 0.03, 1.8),
		C(TX - 0.6, T + 0.02, TZ - 0.3) * CFrame.Angles(0, 0.2, 0),
		rgb(212, 196, 150),
		M.SmoothPlastic
	)
	mk(
		small,
		Vector3.new(0.2, 0.9, 0.9),
		C(TX + 0.6, T + 0.1, TZ + 0.1) * CFrame.Angles(0, 0, math.pi / 2),
		P.brass,
		M.Metal,
		{ Shape = CYL }
	)
	local flame = mk(
		small,
		Vector3.new(0.5, 0.7, 0.5),
		C(TX + 0.6, T + 0.6, TZ + 0.1),
		rgb(255, 222, 160),
		M.Glass,
		{ Shape = BALL, Transparency = 0.25, CastShadow = false }
	)
	do
		local l = Instance.new("PointLight")
		l.Color = rgb(255, 196, 120)
		l.Range = 10
		l.Brightness = 0.8
		l.Parent = flame
		self.candle = l
	end
	mk(
		small,
		Vector3.new(0.4, 1.4, 1.4),
		C(TX - 1.6, T + 0.2, TZ + 0.3) * CFrame.Angles(0, 0, math.pi / 2),
		rgb(120, 86, 56),
		M.Wood,
		{ Shape = CYL }
	)
	for k, c in { rgb(196, 54, 44), rgb(150, 180, 60), rgb(208, 70, 50) } do
		mk(
			small,
			Vector3.new(0.45, 0.45, 0.45),
			C(TX - 1.9 + k * 0.3, T + 0.55, TZ + 0.3 + (k % 2) * 0.25),
			c,
			M.SmoothPlastic,
			{ Shape = BALL }
		)
	end
	for k = 0, 3 do
		mk(
			small,
			Vector3.new(0.5, 0.03, 0.7),
			C(TX + 1.8 + k * 0.08, T + 0.03 + k * 0.03, TZ - 0.4) * CFrame.Angles(0, k * 0.4, 0),
			P.paper,
			M.SmoothPlastic
		)
	end
	do
		mk(
			small,
			Vector3.new(0.08, TOP - F - 7.8, 0.08),
			C(TX, (F + 7.8 + TOP) / 2, TZ),
			P.soot,
			M.SmoothPlastic,
			{ CastShadow = false }
		)
		mk(
			small,
			Vector3.new(0.6, 1.4, 1.4),
			C(TX, F + 7.9, TZ) * CFrame.Angles(0, 0, math.pi / 2),
			rgb(70, 92, 78),
			M.Metal,
			{ Shape = CYL }
		)
		local bulb = mk(
			small,
			Vector3.new(0.45, 0.45, 0.45),
			C(TX, F + 7.6, TZ),
			P.warm,
			M.Neon,
			{ Shape = BALL, CastShadow = false }
		)
		local l = Instance.new("PointLight")
		l.Color = rgb(255, 200, 140)
		l.Range = 22
		l.Brightness = 1.4
		l.Shadows = true
		l.Parent = bulb
		self.lamp = { part = bulb, light = l }
	end
	-- the living corner: a couch at the back (7–9), two armchairs turned to the fire (10, 11), a crate
	sofa(C(-8, F, IZ - 1.6), 9.2, 3, P.fabric, P.cushion)
	for k = 10, 11 do
		local s = seats[k]
		sofa(C(s[1], F, s[2]) * face(s[3]), 3.2, 1, rgb(120, 70, 52), rgb(146, 88, 64))
	end
	mk(folder, Vector3.new(3.6, 1.3, 2), C(-8, F + 0.65, 5.4), P.wood, M.WoodPlanks, { CanCollide = true })
	mk(
		small,
		Vector3.new(1.2, 0.3, 0.9),
		C(-8.8, F + 1.45, 5.3) * CFrame.Angles(0, 0.3, 0),
		rgb(120, 40, 36),
		M.SmoothPlastic
	)
	mk(
		small,
		Vector3.new(0.6, 0.45, 0.45),
		C(-7, F + 1.52, 5.6) * CFrame.Angles(0, 0, math.pi / 2),
		rgb(214, 200, 170),
		M.SmoothPlastic,
		{ Shape = CYL }
	)
	mk(
		small,
		Vector3.new(0.6, 0.45, 0.45),
		C(-7.6, F + 1.52, 4.9) * CFrame.Angles(0, 0, math.pi / 2),
		rgb(150, 70, 52),
		M.SmoothPlastic,
		{ Shape = CYL }
	)
	-- a standing lamp in the couch's corner
	do
		local at = C(-IX + 1.1, F, IZ - 1.1)
		mk(
			small,
			Vector3.new(0.2, 1.2, 1.2),
			at * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2),
			P.dark,
			M.Metal,
			{ Shape = CYL }
		)
		mk(small, Vector3.new(0.18, 5.6, 0.18), at * CFrame.new(0, 2.9, 0), P.dark, M.Metal)
		mk(
			small,
			Vector3.new(1.3, 1.9, 1.9),
			at * CFrame.new(0, 5.9, 0) * CFrame.Angles(0, 0, math.pi / 2),
			rgb(226, 196, 150),
			M.Fabric,
			{ Shape = CYL, Transparency = 0.1 }
		)
		local bulb = mk(
			small,
			Vector3.new(0.4, 0.4, 0.4),
			at * CFrame.new(0, 5.6, 0),
			P.warm,
			M.Neon,
			{ Shape = BALL, CastShadow = false }
		)
		local l = Instance.new("PointLight")
		l.Color = rgb(255, 196, 140)
		l.Range = 14
		l.Brightness = 1
		l.Parent = bulb
		self.floorLamp = { part = bulb, light = l }
	end
	-- rugs: under the table, and before the fire
	for _, r in { { -9.2, 1.4, 9.6, 9.6 }, { TX, TZ, 11.4, 9.4 } } do
		mk(small, Vector3.new(r[3], 0.05, r[4]), C(r[1], F + 0.03, r[2]), P.rugEdge, M.Fabric, { CastShadow = false })
		mk(
			small,
			Vector3.new(r[3] - 0.7, 0.06, r[4] - 0.7),
			C(r[1], F + 0.04, r[2]),
			if r[1] < 0 then P.rug else rgb(70, 86, 110),
			M.Fabric,
			{ CastShadow = false }
		)
	end
	-- a teddy bear at the couch's end
	do
		local b = C(-12.25, F + 2.1, IZ - 1.5) * CFrame.Angles(0, 0.3, 0)
		local fur = rgb(150, 106, 66)
		mk(small, Vector3.new(0.9, 1.0, 0.8), b * CFrame.new(0, 0.5, 0), fur, M.Fabric, { Shape = BALL })
		mk(small, Vector3.new(0.75, 0.75, 0.75), b * CFrame.new(0, 1.25, -0.05), fur, M.Fabric, { Shape = BALL })
		for _, s in { -1, 1 } do
			mk(small, Vector3.new(0.28, 0.28, 0.2), b * CFrame.new(s * 0.28, 1.6, 0), fur, M.Fabric, { Shape = BALL })
			mk(small, Vector3.new(0.3, 0.3, 0.3), b * CFrame.new(s * 0.45, 0.6, -0.15), fur, M.Fabric, { Shape = BALL })
			mk(
				small,
				Vector3.new(0.32, 0.32, 0.32),
				b * CFrame.new(s * 0.25, 0.1, -0.35),
				fur,
				M.Fabric,
				{ Shape = BALL }
			)
		end
		mk(
			small,
			Vector3.new(0.25, 0.2, 0.2),
			b * CFrame.new(0, 1.18, -0.4),
			rgb(214, 180, 140),
			M.Fabric,
			{ Shape = BALL }
		)
		mk(small, Vector3.new(0.6, 0.12, 0.12), b * CFrame.new(0, 0.95, -0.35), rgb(170, 50, 46), M.Fabric)
	end

	-- the back wall: the gramophone on its cabinet, the shelf of cups over it, the cork board ----------
	local GX = 1.2
	local cab = mk(folder, Vector3.new(3, 2.6, 1.4), C(GX, F + 1.3, IZ - 0.75), P.dark, M.Wood, { CanCollide = true })
	for _, x in { -0.72, 0.72 } do
		mk(small, Vector3.new(1.3, 2.1, 0.06), C(GX + x, F + 1.3, IZ - 1.47), P.wood, M.Wood)
		mk(
			small,
			Vector3.new(0.12, 0.12, 0.12),
			C(GX + x * 0.3, F + 1.5, IZ - 1.53),
			P.brass,
			M.Metal,
			{ Shape = BALL }
		)
	end
	local G = C(GX + 0.1, F + 2.6, IZ - 0.8)
	mk(small, Vector3.new(1.5, 0.6, 1.4), G * CFrame.new(0, 0.3, 0), rgb(110, 66, 40), M.Wood)
	mk(
		small,
		Vector3.new(0.08, 1.25, 1.25),
		G * CFrame.new(0, 0.64, 0) * CFrame.Angles(0, 0, math.pi / 2),
		rgb(70, 66, 60),
		M.Metal,
		{ Shape = CYL }
	)
	local record = mk(
		small,
		Vector3.new(0.05, 1.12, 1.12),
		G * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.pi / 2),
		rgb(22, 20, 22),
		M.SmoothPlastic,
		{ Shape = CYL }
	)
	mk(
		small,
		Vector3.new(0.06, 0.4, 0.4),
		G * CFrame.new(0, 0.73, 0) * CFrame.Angles(0, 0, math.pi / 2),
		rgb(200, 60, 50),
		M.SmoothPlastic,
		{ Shape = CYL }
	)
	self.record = { part = record, cf = G * CFrame.new(0, 0.7, 0), spin = 0 }
	mk(small, Vector3.new(0.12, 0.12, 0.9), G * CFrame.new(0.55, 0.8, 0.1) * CFrame.Angles(0, 0.5, 0), P.brass, M.Metal)
	-- the horn: rings widening up and out of the back corner
	do
		local h = G * CFrame.new(-0.45, 0.7, 0.45)
		mk(
			small,
			Vector3.new(0.9, 0.22, 0.22),
			h * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2),
			P.brass,
			M.Metal,
			{ Shape = CYL }
		)
		local dir = CFrame.new(h.Position + h.UpVector * 0.9)
			* h.Rotation
			* CFrame.Angles(math.rad(-50), math.rad(-30), 0)
		for k = 1, 6 do
			local d = 0.25 + k * k * 0.06
			mk(
				small,
				Vector3.new(0.22, d, d),
				dir * CFrame.new(0, 0, -k * 0.22) * CFrame.Angles(0, math.pi / 2, 0),
				P.brass:Lerp(P.gold, k / 8),
				M.Metal,
				{ Shape = CYL }
			)
		end
	end
	mk(small, Vector3.new(0.5, 0.1, 0.1), G * CFrame.new(0.9, 0.35, 0), P.brass, M.Metal)
	mk(small, Vector3.new(0.12, 0.35, 0.12), G * CFrame.new(1.12, 0.5, 0), P.dark, M.Wood)
	for k = 0, 2 do
		mk(
			small,
			Vector3.new(0.08, 1.4, 1.4),
			C(GX + 1.85 + k * 0.1, F + 0.7, IZ - 0.9) * CFrame.Angles(0, 0, -0.08 - k * 0.04),
			({ rgb(160, 70, 50), rgb(60, 90, 120), rgb(200, 170, 90) })[k + 1],
			M.SmoothPlastic
		)
	end
	-- two floor cushions by the gramophone, to sit and listen
	for k, c in { rgb(170, 120, 60), rgb(90, 110, 130) } do
		mk(
			small,
			Vector3.new(0.6, 2, 2),
			C(GX - 4.4 + k * 2.2, F + 0.3, IZ - 3) * CFrame.Angles(0, 0, math.pi / 2),
			c,
			M.Fabric,
			{ Shape = CYL }
		)
	end
	if opts.own then
		local pr = Instance.new("ProximityPrompt")
		pr.ObjectText = "Граммофон"
		pr.KeyboardKeyCode = Enum.KeyCode.R -- not E: the seats round it answer E
		pr.GamepadKeyCode = Enum.KeyCode.ButtonY
		pr.HoldDuration = 0
		pr.MaxActivationDistance = 7
		pr.RequiresLineOfSight = false
		pr.Parent = cab
		local function label()
			pr.ActionText = if Settings.homeMusic
				then "Выключить музыку"
				else "Включить музыку"
		end
		label()
		Settings.onChanged(function(key)
			if key == "homeMusic" then
				label()
			end
		end)
		pr.Triggered:Connect(function()
			Settings.set("homeMusic", not Settings.homeMusic)
			Audio.play("ui", 0.6, if Settings.homeMusic then 1.1 else 0.8)
		end)
		self.prompt = pr
	end
	-- the shelf over the gramophone: the old photo; the boss cups come with the entry
	local shelfY = F + 6.4
	mk(folder, Vector3.new(5.0, 0.25, 1.0), C(GX - 0.2, shelfY, IZ - 0.5), P.dark, M.Wood)
	for _, x in { -2.4, 2.0 } do
		mk(small, Vector3.new(0.2, 0.8, 0.8), C(GX + x, shelfY - 0.5, IZ - 0.4), P.dark, M.Wood)
	end
	do
		local frame = mk(
			small,
			Vector3.new(1.6, 1.3, 0.12),
			C(GX - 1.9, shelfY + 0.78, IZ - 0.5) * CFrame.Angles(math.rad(-8), 0.15, 0),
			P.dark,
			M.Wood
		)
		familyPhoto(
			mk(small, Vector3.new(1.3, 1.0, 0.05), frame.CFrame * CFrame.new(0, 0, -0.07), P.paper, M.SmoothPlastic)
		)
	end
	self.shelf = { y = shelfY + 0.125, z = IZ - 0.5, xs = { GX - 0.6, GX + 0.5, GX + 1.6 } }
	-- the cork board over the table
	local BX = TX + 0.4
	local board = mk(folder, Vector3.new(5.8, 3.6, 0.15), C(BX, F + 7, IZ - 0.1), rgb(176, 130, 86), M.Fabric)
	for _, t in { { 6.2, 0.25, 0, 1.92 }, { 6.2, 0.25, 0, -1.92 }, { 0.25, 3.8, -3.0, 0 }, { 0.25, 3.8, 3.0, 0 } } do
		mk(small, Vector3.new(t[1], t[2], 0.2), C(BX + t[3], F + 7 + t[4], IZ - 0.12), P.dark, M.Wood)
	end
	do
		local g = Instance.new("SurfaceGui")
		g.Face = Enum.NormalId.Front
		g.CanvasSize = Vector2.new(580, 360)
		g.LightInfluence = 1
		g.Parent = board
		self.boardGui = g
		local d = mk(
			small,
			Vector3.new(1.5, 1.2, 0.04),
			C(BX + 2, F + 6.2, IZ - 0.2) * CFrame.Angles(0, 0, 0.06),
			P.paper,
			M.SmoothPlastic
		)
		childDrawing(d)
	end

	-- the left wall: the bookcase, the clock, the guitar, a plant ---------------------------------------
	mk(folder, Vector3.new(1.3, 7.2, 3.2), C(IX - 0.65, F + 3.6, 7.6), P.dark, M.Wood, { CanCollide = true })
	do
		local rng = Random.new(7)
		local colours = {
			rgb(140, 50, 44),
			rgb(60, 86, 110),
			rgb(84, 110, 64),
			rgb(176, 140, 70),
			rgb(110, 70, 96),
			rgb(196, 182, 150),
		}
		for row = 0, 3 do
			local y = F + 0.6 + row * 1.7
			mk(small, Vector3.new(1.1, 0.12, 3.0), C(IX - 0.7, y, 7.6), P.wood, M.Wood)
			local z = 6.25
			while z < 8.8 do
				local w = rng:NextNumber(0.18, 0.34)
				local h = rng:NextNumber(0.9, 1.35)
				mk(
					small,
					Vector3.new(0.85, h, w),
					C(IX - 0.75, y + 0.06 + h / 2, z + w / 2)
						* CFrame.Angles(if rng:NextNumber() < 0.1 then 0.2 else 0, 0, 0),
					colours[rng:NextInteger(1, #colours)],
					M.SmoothPlastic
				)
				z += w + 0.03
			end
		end
	end
	do
		local at = C(IX - 0.12, F + 8.2, 3.2)
		mk(small, Vector3.new(0.2, 2.1, 2.1), at, P.dark, M.Wood, { Shape = CYL })
		mk(
			small,
			Vector3.new(0.22, 1.8, 1.8),
			at * CFrame.new(-0.02, 0, 0),
			rgb(236, 228, 206),
			M.SmoothPlastic,
			{ Shape = CYL }
		)
		self.clock = { at = at * CFrame.new(-0.16, 0, 0) }
		self.clock.h = mk(small, Vector3.new(0.05, 0.5, 0.12), at, P.soot, M.SmoothPlastic, { CastShadow = false })
		self.clock.m = mk(small, Vector3.new(0.05, 0.75, 0.08), at, P.soot, M.SmoothPlastic, { CastShadow = false })
	end
	do
		local g = C(IX - 0.6, F, -8) * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(math.rad(-14), 0, 0)
		local body = rgb(170, 104, 50)
		mk(
			small,
			Vector3.new(0.45, 1.9, 1.9),
			g * CFrame.new(0, 1.15, 0) * CFrame.Angles(0, math.pi / 2, 0),
			body,
			M.Wood,
			{ Shape = CYL }
		)
		mk(
			small,
			Vector3.new(0.45, 1.5, 1.5),
			g * CFrame.new(0, 2.35, 0) * CFrame.Angles(0, math.pi / 2, 0),
			body,
			M.Wood,
			{ Shape = CYL }
		)
		mk(
			small,
			Vector3.new(0.47, 0.5, 0.5),
			g * CFrame.new(0, 1.55, 0) * CFrame.Angles(0, math.pi / 2, 0),
			P.soot,
			M.SmoothPlastic,
			{ Shape = CYL }
		)
		mk(small, Vector3.new(0.3, 2.4, 0.18), g * CFrame.new(0, 4.1, 0), P.dark, M.Wood)
		mk(small, Vector3.new(0.4, 0.7, 0.2), g * CFrame.new(0, 5.6, 0), P.dark, M.Wood)
	end
	for _, pz in { -IZ + 1.4, IZ - 1.4 } do
		local at = C(IX - 1.2, F, pz)
		if pz > 0 then
			at = C(-IX + 1.2, F, -IZ + 1.4) -- the second plant in the front right corner
		end
		mk(
			small,
			Vector3.new(1.0, 1.1, 1.1),
			at * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
			rgb(170, 90, 60),
			M.Concrete,
			{ Shape = CYL }
		)
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			mk(
				small,
				Vector3.new(0.9, 0.9, 0.9),
				at * CFrame.new(math.cos(a) * 0.35, 1.5 + (k % 2) * 0.5, math.sin(a) * 0.35),
				P.leaf:Lerp(rgb(120, 160, 70), (k % 3) / 3),
				M.Grass,
				{ Shape = BALL }
			)
		end
	end
	-- a backpack and a helmet dropped by the door
	do
		local at = C(-DOOR - 2, F, -IZ + 1.1) * CFrame.Angles(0, 0.4, 0)
		mk(small, Vector3.new(1.4, 1.8, 0.9), at * CFrame.new(0, 0.9, 0), rgb(92, 98, 70), M.Fabric)
		mk(small, Vector3.new(1.2, 0.7, 0.4), at * CFrame.new(0, 0.6, -0.6), rgb(80, 86, 60), M.Fabric)
		mk(
			small,
			Vector3.new(1.3, 1.0, 1.4),
			C(-DOOR - 3.6, F + 0.35, -IZ + 1.4) * CFrame.Angles(0.2, 0.8, 0),
			rgb(84, 92, 74),
			M.Metal,
			{ Shape = BALL }
		)
	end
	-- fairy lights along the back wall, sagging between nails
	do
		local n = 21
		local prev = nil
		for k = 0, n - 1 do
			local t = k / (n - 1)
			local x = -IX + 0.8 + t * (IX * 2 - 1.6)
			local sag = math.abs(math.sin(t * math.pi * 4)) * 0.6
			local pos = C(x, TOP - 1.3 - sag, IZ - 0.3).Position
			local bulb = mk(
				small,
				Vector3.new(0.32, 0.32, 0.32),
				CFrame.new(pos),
				P.warm,
				M.Neon,
				{ Shape = BALL, CastShadow = false }
			)
			table.insert(self.bulbs, bulb)
			if prev then
				local mid = (prev + pos) / 2
				mk(
					small,
					Vector3.new(0.05, 0.05, (pos - prev).Magnitude),
					CFrame.lookAt(mid, pos),
					P.soot,
					M.SmoothPlastic,
					{ CastShadow = false }
				)
			end
			prev = pos
		end
		local glow = Instance.new("PointLight")
		glow.Color = rgb(255, 206, 150)
		glow.Range = 18
		glow.Brightness = 0.7
		glow.Parent = self.bulbs[11]
		self.bulbGlow = glow
	end
	-- the mantel: a candle pair, dried flowers, the old photo; the jar for the first xenite comes later
	do
		local mx = SX + 1.5
		local my = F + 6.22
		for _, z in { SZ - 3.1, SZ - 2.5 } do
			mk(
				small,
				Vector3.new(0.7, 0.25, 0.25),
				C(mx, my + 0.35, z) * CFrame.Angles(0, 0, math.pi / 2),
				rgb(236, 226, 196),
				M.SmoothPlastic,
				{ Shape = CYL }
			)
			mk(
				small,
				Vector3.new(0.14, 0.2, 0.14),
				C(mx, my + 0.8, z),
				rgb(255, 210, 120),
				M.Neon,
				{ Shape = BALL, CastShadow = false }
			)
		end
		mk(
			small,
			Vector3.new(0.6, 0.6, 0.6),
			C(mx, my + 0.3, SZ + 2.9) * CFrame.Angles(0, 0, math.pi / 2),
			rgb(120, 140, 160),
			M.Glass,
			{ Shape = CYL, Transparency = 0.4 }
		)
		for k = 0, 3 do
			mk(
				small,
				Vector3.new(0.06, 1.3, 0.06),
				C(mx, my + 0.9, SZ + 2.9) * CFrame.Angles((k - 1.5) * 0.18, 0, (k % 2 - 0.5) * 0.3),
				rgb(150, 120, 70),
				M.Wood
			)
		end
		self.mantel = { x = mx, y = my, z = SZ }
		local photo = mk(
			small,
			Vector3.new(0.12, 1.3, 1.6),
			C(mx + 0.1, my + 0.7, SZ - 0.4) * CFrame.Angles(0, 0, math.rad(8)),
			P.dark,
			M.Wood
		)
		familyPhoto(
			mk(
				small,
				Vector3.new(1.3, 1.0, 0.05),
				photo.CFrame * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.new(0, 0, -0.07),
				P.paper,
				M.SmoothPlastic
			)
		)
	end

	self.keep = nil
	folder.Parent = parent
	self:setPower(true)
	return self
end

-- The owner's keepsakes from their showcase entry: a note on the cork board for every sortie won, a cup on
-- the shelf for every boss beaten, the first xenite in its jar; the owner's name over the door.
function Cabin:setEntry(entry)
	local key = if entry
		then table.concat({
			entry.name or "",
			entry.wins or 0,
			(function()
				local s = {}
				for _, id in Ops.Order do
					table.insert(s, if entry.won and entry.won[id] then "1" else "0")
				end
				return table.concat(s)
			end)(),
		}, "|")
		else "-"
	if key == self.entryKey then
		return
	end
	self.entryKey = key
	if self.keep then
		self.keep:Destroy()
	end
	local keep = Instance.new("Folder")
	keep.Name = "Keepsakes"
	self.keep = keep
	local won = entry and entry.won or {}
	self.signText.Text = if entry
			and entry.name
			and entry.name ~= ""
		then "ДОМ · " .. string.upper(entry.name)
		else "ДОМ"
	-- the cork board
	local g = self.boardGui
	for _, c in g:GetChildren() do
		c:Destroy()
	end
	local count = 0
	for _, id in Ops.Order do
		if won[id] then
			count += 1
		end
	end
	text(g, "НАШИ ВЫЛАЗКИ", 0.36, 0.09, 0.6, 0.12, rgb(250, 240, 214), Font.fromEnum(Enum.Font.Antique))
	if count == 0 then
		local n = blob(g, 0.36, 0.5, 0.42, 0.3, rgb(240, 232, 206), false, -3)
		text(
			n,
			"Первая вылазка\nещё впереди",
			0.5,
			0.5,
			0.9,
			0.7,
			rgb(70, 60, 50),
			Font.fromEnum(Enum.Font.Cartoon)
		)
	else
		local k = 0
		for _, id in Ops.Order do
			if won[id] then
				local op = Ops.get(id)
				local col, row = k % 3, k // 3
				k += 1
				local rot = ((k * 37) % 9) - 4
				local n = blob(
					g,
					0.13 + col * 0.23,
					0.32 + row * 0.27,
					0.21,
					0.23,
					rgb(242, 234, 210):Lerp(rgb(230, 214, 170), (k % 2) * 0.5),
					false,
					rot
				)
				text(
					n,
					(op and op.code) or id,
					0.5,
					0.24,
					0.8,
					0.3,
					rgb(160, 52, 40),
					Font.fromEnum(Enum.Font.GothamBlack)
				)
				text(
					n,
					(op and op.name) or "",
					0.5,
					0.58,
					0.92,
					0.26,
					rgb(60, 52, 44),
					Font.fromEnum(Enum.Font.GothamBold)
				)
				text(n, "✓", 0.82, 0.86, 0.2, 0.24, rgb(60, 130, 60), Font.fromEnum(Enum.Font.GothamBlack))
				blob(n, 0.5, 0.04, 0.09, 0.12, rgb(200, 50, 44), true)
			end
		end
	end
	if entry and (entry.wins or 0) > 0 then
		text(
			g,
			"побед: " .. entry.wins,
			0.84,
			0.09,
			0.26,
			0.09,
			rgb(250, 240, 214),
			Font.fromEnum(Enum.Font.Antique)
		)
	end
	-- the cups for the bosses (shared/ShelterLayout.Trophies)
	local cf = self.cf
	for i, t in Layout.Trophies do
		if won[t.op] then
			local x = self.shelf.xs[i] or 0
			local at = cf * CFrame.new(x, self.shelf.y, self.shelf.z)
			mk(keep, Vector3.new(0.7, 0.2, 0.7), at * CFrame.new(0, 0.1, 0), rgb(60, 44, 34), M.Wood)
			mk(
				keep,
				Vector3.new(0.5, 0.18, 0.18),
				at * CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0, math.pi / 2),
				rgb(236, 190, 84),
				M.Metal,
				{ Shape = CYL }
			)
			mk(
				keep,
				Vector3.new(0.75, 0.6, 0.75),
				at * CFrame.new(0, 0.85, 0),
				rgb(236, 190, 84),
				M.Metal,
				{ Shape = BALL }
			)
			mk(
				keep,
				Vector3.new(0.18, 0.8, 0.8),
				at * CFrame.new(0, 1.05, 0) * CFrame.Angles(0, 0, math.pi / 2),
				rgb(250, 210, 110),
				M.Metal,
				{ Shape = CYL }
			)
			for _, s in { -1, 1 } do
				mk(
					keep,
					Vector3.new(0.12, 0.4, 0.12),
					at * CFrame.new(s * 0.45, 0.95, 0) * CFrame.Angles(0, 0, s * 0.5),
					rgb(236, 190, 84),
					M.Metal
				)
			end
		end
	end
	-- the first xenite (O01: the generator's sortie) glows in a jar on the mantel
	if won.O01 then
		local m = self.mantel
		local at = cf * CFrame.new(m.x, m.y, m.z + 1.2)
		mk(
			keep,
			Vector3.new(0.8, 0.8, 0.8),
			at * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.pi / 2),
			rgb(200, 220, 230),
			M.Glass,
			{ Shape = CYL, Transparency = 0.6 }
		)
		local shard = mk(
			keep,
			Vector3.new(0.25, 0.55, 0.25),
			at * CFrame.new(0, 0.4, 0) * CFrame.Angles(0.3, 0.6, 0.2),
			rgb(255, 110, 190),
			M.Neon,
			{ CastShadow = false }
		)
		local l = Instance.new("PointLight")
		l.Color = rgb(255, 120, 200)
		l.Range = 5
		l.Brightness = 0.6
		l.Parent = shard
	end
	keep.Parent = self.folder
end

-- The electric lights: the hanging lamp, the fairy lights and the lantern run on the generator. The fire
-- and the oil lamp do not.
function Cabin:setPower(on: boolean)
	if self.power == on then
		return
	end
	self.power = on
	self.lamp.light.Enabled = on
	self.lamp.part.Material = if on then M.Neon else M.SmoothPlastic
	self.lamp.part.Color = if on then P.warm else rgb(90, 84, 76)
	self.lantern.light.Enabled = on
	self.lantern.part.Material = if on then M.Neon else M.Glass
	self.bulbGlow.Enabled = on
	self.floorLamp.light.Enabled = on
	self.floorLamp.part.Material = if on then M.Neon else M.SmoothPlastic
	for i, b in self.bulbs do
		b.Material = if on then M.Neon else M.SmoothPlastic
		b.Color = if not on
			then rgb(80, 74, 68)
			elseif i % 3 == 0 then rgb(255, 160, 90)
			elseif i % 3 == 1 then rgb(255, 214, 140)
			else rgb(200, 230, 150)
	end
end

local function setFade(parts, k: number)
	for _, p in parts do
		p.LocalTransparencyModifier = k
	end
end

-- Every frame while it is on screen. root: the hero (nil: no cutaway).
function Cabin:step(dt: number, root: Vector3?)
	local now = os.clock()
	if self.fireLight then
		self.fireLight.Brightness = 1.8 + math.noise(now * 3.1, 0.3) * 0.7 + math.sin(now * 17) * 0.12
		self.candle.Brightness = 0.75 + math.noise(now * 5, 2.2) * 0.2
	end
	-- the record turns while the music plays
	local r = self.record
	if Settings.homeMusic then
		r.spin += dt * 3.5
	end
	r.part.CFrame = r.cf * CFrame.Angles(0, r.spin, 0) * CFrame.Angles(0, 0, math.pi / 2)
	-- the clock tells the player's own time
	local c = self.clock
	local t = os.date("*t")
	local ha = ((t.hour % 12) + t.min / 60) / 12 * math.pi * 2
	local ma = (t.min + t.sec / 60) / 60 * math.pi * 2
	c.h.CFrame = c.at * CFrame.Angles(ha, 0, 0) * CFrame.new(0, 0.22, 0)
	c.m.CFrame = c.at * CFrame.Angles(ma, 0, 0) * CFrame.new(0, 0.34, 0)
	self:stepDoor(dt)
	-- the cutaway
	local inside = false
	if root then
		local l = self.cf:PointToObjectSpace(root)
		inside = math.abs(l.X) < HX + 0.2 and math.abs(l.Z) < HZ + 0.2 and l.Y < TOP + 2
	end
	local goal = if inside then 1 else 0
	local k = self.fadeK + (goal - self.fadeK) * math.min(1, dt * 6)
	if math.abs(k - goal) < 0.01 then
		k = goal
	end
	local cam = workspace.CurrentCamera
	local camL = if cam then self.cf:PointToObjectSpace(cam.CFrame.Position) else Vector3.new(0, 30, -40)
	-- a wall fades when the camera is on its outer side (it stands between the camera and the room)
	local walls = {
		front = camL.Z < -HZ,
		back = camL.Z > HZ,
		left = camL.X > HX,
		right = camL.X < -HX,
	}
	if
		k ~= self.fadeK
		or (
			k > 0
			and self.lastWalls
				~= (tostring(walls.front) .. tostring(walls.back) .. tostring(walls.left) .. tostring(walls.right))
		)
	then
		self.fadeK = k
		self.lastWalls = tostring(walls.front) .. tostring(walls.back) .. tostring(walls.left) .. tostring(walls.right)
		setFade(self.fade.roof, k)
		for side, on in walls do
			setFade(self.fade[side], if on then k * 0.92 else 0)
		end
		for _, g in self.guis.front do
			g.Enabled = not (walls.front and k > 0.4)
		end
	end
end

-- The door follows the server's Door part of this plot (found by place: the one in the doorway).
local DOOR_OPEN = math.rad(100)
function Cabin:stepDoor(dt: number)
	local d = self.door
	local srv = d.server
	if not (srv and srv.Parent) then
		d.server = nil
		local now = os.clock()
		if now >= (d.lookAt or 0) then
			d.lookAt = now + 1
			local seats = workspace:FindFirstChild("GroveSeats")
			for _, c in if seats then seats:GetChildren() else {} do
				if c:IsA("BasePart") and c.Name:sub(1, 4) == "Door" and (c.Position - d.at).Magnitude < 3 then
					d.server = c
				end
			end
		end
		srv = d.server
	end
	if srv then
		d.open = srv:GetAttribute("Open") ~= false
	end
	local goal = if d.open then DOOR_OPEN else 0
	local a = if d.angle < 0 then goal else d.angle + (goal - d.angle) * math.min(1, dt * 7)
	if math.abs(a - goal) < 0.002 then
		a = goal
	end
	if a ~= d.angle then
		d.angle = a
		local turn = d.hinge * CFrame.Angles(0, a, 0)
		for _, pc in d.pieces do
			pc[1].CFrame = turn * pc[2]
		end
		d.leaf.CanCollide = a < 0.15 -- shut, it keeps the room; open, it never snags anyone
	end
end

function Cabin:destroy()
	self.folder:Destroy()
end

return Cabin
