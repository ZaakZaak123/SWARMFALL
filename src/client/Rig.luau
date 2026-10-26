--!nonstrict
-- Procedural character animator. Replaces Roblox's default Animate with a combat rig computed every
-- frame for every squad member (R15 and R6):
--   * the gun is a real part of the body (Motor6D on the root), held at the shoulder, aimed, swaying
--     with the stride, lagging on turns, dipping to low-ready when not firing;
--   * both arms are solved with two-bone IK onto the gun's grip and fore-grip (hands follow the pump,
--     the magazine, the breech during reloads);
--   * legs are IK'd onto procedurally planted feet: stride length/frequency match the real velocity in
--     any direction (strafe, backpedal), feet lift and plant, hips bob, the body leans into motion;
--   * recoil, flinch and torso response are damped springs fed by WeaponFeel profiles;
--   * weapon mechanisms (bolt, coils, prongs, energy cell windows, heat glow), the draw animation, the
--     reload choreography and the evolution transformation; timed beats are reported through
--     Rig.setEventHandler so sound / debris stay in sync with the animation for every squad member.
-- Motor6D.Transform is written in PreSimulation (after the Animator), so nothing fights it.

local RunService = game:GetService("RunService")
local Spring = require(script.Parent.Spring)

local Rig = {}

local rigs: { [Model]: any } = {}

local R15_JOINTS = {
	root = { "LowerTorso", "Root" },
	waist = { "UpperTorso", "Waist" },
	neck = { "Head", "Neck" },
	rShoulder = { "RightUpperArm", "RightShoulder" },
	rElbow = { "RightLowerArm", "RightElbow" },
	rWrist = { "RightHand", "RightWrist" },
	lShoulder = { "LeftUpperArm", "LeftShoulder" },
	lElbow = { "LeftLowerArm", "LeftElbow" },
	lWrist = { "LeftHand", "LeftWrist" },
	rHip = { "RightUpperLeg", "RightHip" },
	rKnee = { "RightLowerLeg", "RightKnee" },
	rAnkle = { "RightFoot", "RightAnkle" },
	lHip = { "LeftUpperLeg", "LeftHip" },
	lKnee = { "LeftLowerLeg", "LeftKnee" },
	lAnkle = { "LeftFoot", "LeftAnkle" },
}
local R6_JOINTS = {
	root = { "HumanoidRootPart", "RootJoint" },
	neck = { "Torso", "Neck" },
	rShoulder = { "Torso", "Right Shoulder" },
	lShoulder = { "Torso", "Left Shoulder" },
	rHip = { "Torso", "Right Hip" },
	lHip = { "Torso", "Left Hip" },
}

local ID = CFrame.identity
local X_AXIS = Vector3.xAxis

-- Math helpers ---------------------------------------------------------------------------------------
local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function window(t: number, a: number, b: number): number
	return smooth((t - a) / (b - a))
end

local function fromTo(a: Vector3, b: Vector3): CFrame
	local axis = a:Cross(b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if axis.Magnitude < 1e-6 then
		if dot > 0 then
			return ID
		end
		local perp = if math.abs(a.X) < 0.9 then a:Cross(X_AXIS) else a:Cross(Vector3.yAxis)
		return CFrame.fromAxisAngle(perp.Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Expresses a body-axes transform (X right, Y up, -Z forward) in a joint's own frame.
local function toJoint(j, cf: CFrame): CFrame
	return j.rot:Inverse() * cf * j.rot
end

-- Joints are either classic Motor6Ds or the physics avatar's AnimationConstraints (attachment pairs);
-- both expose Transform with the same Part1 = Part0 * C0 * Transform * C1^-1 convention.
local function motorInfo(m)
	local C0, C1
	if m:IsA("Motor6D") then
		C0, C1 = m.C0, m.C1
	else
		C0, C1 = m.Attachment0.CFrame, m.Attachment1.CFrame
	end
	return { motor = m, C0 = C0, C1 = C1, C1inv = C1:Inverse(), rot = C0.Rotation }
end

local function isJoint(m): boolean
	return m ~= nil
		and (m:IsA("Motor6D") or (m:IsA("AnimationConstraint") and m.Attachment0 ~= nil and m.Attachment1 ~= nil))
end

-- Two-bone IK. base = world CFrame of joint A's frame (Part0 * C0) before its Transform.
-- Joint B sits on A's Part1; endLocal is the effector in B's Part1 space. Hinge axis is in B's frame;
-- bendSign picks the natural bend (+1 elbows forward, -1 knees back). pole = world direction the
-- middle joint should point to. Returns TA, TB.
local function solve2(
	base: CFrame,
	a,
	b,
	endLocal: Vector3,
	target: Vector3,
	pole: Vector3,
	hinge: Vector3,
	bendSign: number
)
	local AB = a.C1inv * b.C0
	local v1 = AB.Position
	local v2 = b.C1inv * endLocal
	local t = base:PointToObjectSpace(target)
	local d = t.Magnitude
	local u = AB:VectorToObjectSpace(v1)
	local vpar = hinge * hinge:Dot(v2)
	local vperp = v2 - vpar
	local hx = hinge:Cross(vperp)
	local A0, B, C = u:Dot(vpar), u:Dot(vperp), u:Dot(hx)
	local R = math.sqrt(B * B + C * C)
	local K = (d * d - v1:Dot(v1) - v2:Dot(v2)) / 2
	local theta = 0
	if R > 1e-5 then
		local phi = math.atan2(C, B)
		local alpha = math.acos(math.clamp((K - A0) / R, -1, 1))
		local t1, t2 = wrap(phi + alpha), wrap(phi - alpha)
		local ok1, ok2 = t1 * bendSign >= -0.05, t2 * bendSign >= -0.05
		if ok1 and ok2 then
			theta = if math.abs(t1) < math.abs(t2) then t1 else t2
		elseif ok1 then
			theta = t1
		elseif ok2 then
			theta = t2
		else
			theta = 0
		end
	end
	local TB = CFrame.fromAxisAngle(hinge, theta)
	local e = v1 + AB:VectorToWorldSpace(TB:VectorToWorldSpace(v2))
	if d < 1e-4 or e.Magnitude < 1e-4 then
		return ID, TB
	end
	local axis = t / d
	local swing = fromTo(e.Unit, axis)
	local mid = swing:VectorToWorldSpace(v1)
	local p = base:VectorToObjectSpace(pole)
	local mp = mid - axis * axis:Dot(mid)
	local pp = p - axis * axis:Dot(p)
	local twist = ID
	if mp.Magnitude > 1e-4 and pp.Magnitude > 1e-4 then
		local ang = math.atan2(axis:Dot(mp:Cross(pp)), mp:Dot(pp))
		twist = CFrame.fromAxisAngle(axis, ang)
	end
	return twist * swing, TB
end

-- Single bone: rotate so the effector points at target.
local function aim1(base: CFrame, a, endLocal: Vector3, target: Vector3): CFrame
	local e = a.C1inv * endLocal
	local t = base:PointToObjectSpace(target)
	if t.Magnitude < 1e-4 or e.Magnitude < 1e-4 then
		return ID
	end
	return fromTo(e.Unit, t.Unit)
end

local function fk(part0: CFrame, j, T: CFrame): CFrame
	return part0 * j.C0 * T * j.C1inv
end

-- Build ------------------------------------------------------------------------------------------------
local function build(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return nil
	end
	local r15 = character:FindFirstChild("UpperTorso") ~= nil
	local spec = if r15 then R15_JOINTS else R6_JOINTS
	local j = {}
	for key, path in spec do
		local part = character:FindFirstChild(path[1])
		local m = part and part:FindFirstChild(path[2])
		if not isJoint(m) then
			return nil
		end
		j[key] = motorInfo(m)
	end
	local st = {
		character = character,
		hrp = hrp,
		hum = hum,
		r15 = r15,
		j = j,
		phase = 0,
		amp = 0,
		lastLook = hrp.CFrame.LookVector,
		yawRate = 0,
		vel = Vector3.zero,
		kickPos = Spring.new(8, 0.45, Vector3.zero),
		kickRot = Spring.new(8, 0.45, Vector3.zero),
		torso = Spring.new(4, 0.5, Vector3.zero),
		ready = Spring.new(3, 1, 0),
		dead = 0,
		dashUntil = 0,
		dashDir = Vector3.zAxis,
		lastShot = -10,
		actionT = -10,
		reload = 0,
		rl = 0,
		ammo = 1,
		reloadEmpty = false,
		beats = {},
		spin = 0,
		coilAng = 0,
		heat = 0,
		equipT = -10,
		evoT = -10,
		feel = nil,
		gun = nil,
		buzz = 0,
	}
	-- Rest-pose geometry in root space (all transforms identity).
	local rootCF = j.root.C0 * j.root.C1inv
	if r15 then
		local upper = rootCF * j.waist.C0 * j.waist.C1inv
		st.restShoulderR = (upper * j.rShoulder.C0).Position
		st.restShoulderL = (upper * j.lShoulder.C0).Position
		for _, side in { "r", "l" } do
			local hip, knee, ankle = j[side .. "Hip"], j[side .. "Knee"], j[side .. "Ankle"]
			local upperLeg = rootCF * hip.C0 * hip.C1inv
			local lowerLeg = upperLeg * knee.C0 * knee.C1inv
			st["restAnkle" .. side] = (lowerLeg * ankle.C0).Position
			st["restHip" .. side] = (rootCF * hip.C0).Position
		end
		st.legLen = (st.restHipr - st.restAnkler).Magnitude
		local rh = character:FindFirstChild("RightHand")
		local lh = character:FindFirstChild("LeftHand")
		local rg = rh and rh:FindFirstChild("RightGripAttachment")
		local lg = lh and lh:FindFirstChild("LeftGripAttachment")
		st.gripR = if rg then rg.Position else Vector3.new(0, -0.3, 0)
		st.gripL = if lg then lg.Position else Vector3.new(0, -0.3, 0)
	else
		st.restShoulderR = (rootCF * j.rShoulder.C0).Position
		st.restShoulderL = (rootCF * j.lShoulder.C0).Position
		for _, side in { "r", "l" } do
			local hip = j[side .. "Hip"]
			local leg = rootCF * hip.C0 * hip.C1inv
			st["restAnkle" .. side] = (leg * Vector3.new(0, -1, 0))
			st["restHip" .. side] = (rootCF * hip.C0).Position
		end
		st.legLen = 2
	end
	st.groundY = math.min(st.restAnkler.Y, st.restAnklel.Y)
	return st
end

local function valid(st): boolean
	for _, info in st.j do
		if not info.motor.Parent then
			return false
		end
	end
	-- avatar re-applied (scaling / appearance): joint frames changed, rebuild
	local probe = st.j.rShoulder
	if
		probe.motor:IsA("AnimationConstraint")
		and probe.motor.Attachment0
		and probe.motor.Attachment0.CFrame ~= probe.C0
	then
		return false
	end
	return st.hrp.Parent ~= nil
end

function Rig.get(character: Model)
	local st = rigs[character]
	if st and not valid(st) then
		st = nil
	end
	if not st then
		st = build(character)
		rigs[character] = st
	end
	return st
end

local onEvent = nil
-- fn(character, name, cframe?) for animation beats: equip, magOut, magIn, bolt, evolve.
function Rig.setEventHandler(fn)
	onEvent = fn
end
local function beat(st, name: string, cf: CFrame?)
	if onEvent then
		task.spawn(onEvent, st.character, name, cf, st.feel)
	end
end

local EVOLVE_TIME = 1.6

-- Weapon: gun model (unanchored, built by Models) + its hold metadata and feel profile.
function Rig.setWeapon(character: Model, gun: Model, meta, feel)
	local st = Rig.get(character)
	if not st then
		return
	end
	local s = feel.scale
	-- parts welded to each movable group (to hide the magazine while it is "away" during a reload)
	local groupParts = {}
	for _, d in gun:GetDescendants() do
		if d:IsA("WeldConstraint") and d.Part0 and d.Part0.Name:sub(1, 6) == "Group_" then
			local name = d.Part0.Name:sub(7)
			groupParts[name] = groupParts[name] or {}
			table.insert(groupParts[name], d.Part1)
		end
	end
	local pivots = {}
	for name, v in meta.pivots or {} do
		pivots[name] = v * s
	end
	local motor = Instance.new("Motor6D")
	motor.Name = "GunMotor"
	motor.Part0 = st.hrp
	motor.Part1 = gun.PrimaryPart
	motor.Parent = gun.PrimaryPart
	local groups = {}
	for _, m in gun.PrimaryPart:GetChildren() do
		if m:IsA("Motor6D") and m.Name:sub(1, 6) == "Motor_" then
			groups[m.Name:sub(7)] = m
		end
	end
	st.gun = {
		model = gun,
		motor = motor,
		groups = groups,
		grip = meta.grip * s,
		fore = meta.fore * s,
		eject = meta.eject * s,
		mag = meta.mag * s,
		muzzle = (meta.muzzle or Vector3.new(0, 0.4, -4.8)) * s,
		boltHandle = (meta.boltHandle or meta.eject) * s,
		prongTips = meta.prongTips and { meta.prongTips[1] * s, meta.prongTips[2] * s },
		charge = gun:FindFirstChild("Charge", true),
		groupParts = groupParts,
		pivots = pivots,
		cells = {
			gun:FindFirstChild("Cell1", true),
			gun:FindFirstChild("Cell2", true),
			gun:FindFirstChild("Cell3", true),
		},
		heatPart = gun:FindFirstChild("Heat", true),
		core = gun:FindFirstChild("Core", true),
	}
	for _, c in st.gun.cells do
		c:SetAttribute("Base", c.Color)
	end
	if st.gun.heatPart then
		st.gun.heatPart:SetAttribute("Base", st.gun.heatPart.Color)
	end
	local now = os.clock()
	-- draw the weapon (spawn, respawn, run start) unless it is being rebuilt mid-evolution
	if now - st.evoT > EVOLVE_TIME then
		st.equipT = now
		beat(st, "equip")
	end
	st.feel = feel
	local r = feel.recoil
	st.kickPos.f, st.kickPos.d = r.freq, r.damp
	st.kickRot.f, st.kickRot.d = r.freq, r.damp
	st.local_ = nil
end

function Rig.hasWeapon(character: Model): boolean
	local st = rigs[character]
	return st ~= nil and valid(st) and st.gun ~= nil and st.gun.model.Parent ~= nil
end

function Rig.clearWeapon(character: Model)
	local st = rigs[character]
	if st then
		st.gun = nil
	end
end

-- Events ----------------------------------------------------------------------------------------------
function Rig.fire(character: Model, strength: number?)
	local st = rigs[character]
	if not st or not st.feel then
		return
	end
	local r = st.feel.recoil
	local k = (strength or 1) * (1 + (r.build or 0) * st.heat)
	local rnd = function()
		return math.random() * 2 - 1
	end
	-- impulse = desired peak * omega (a damped spring peaks at ~0.6 * v0 / omega)
	local w = r.freq * 2 * math.pi
	st.kickPos:impulse(Vector3.new(rnd() * r.side, r.rise * 0.4, r.back) * (w * k))
	st.kickRot:impulse(Vector3.new(r.rise, rnd() * r.side, rnd() * r.roll) * (w * k))
	st.torso:impulse(
		Vector3.new(r.torso, rnd() * r.torso * 0.4, rnd() * r.torso * 0.3) * (st.torso.f * 2 * math.pi * 1.6 * k)
	)
	st.lastShot = os.clock()
	st.actionT = os.clock()
	st.ready.target = 1
end

-- Continuous fire (beam): vibration level 0..1.
function Rig.buzz(character: Model, level: number)
	local st = rigs[character]
	if st then
		st.buzz = level
		if level > 0 then
			st.lastShot = os.clock()
			st.ready.target = 1
		end
	end
end

function Rig.flinch(character: Model, fromX: number?, fromZ: number?, amount: number?)
	local st = rigs[character]
	if not st then
		return
	end
	local dir = Vector3.new(0, 0, 1)
	if fromX then
		local away = st.hrp.Position - Vector3.new(fromX, st.hrp.Position.Y, fromZ)
		if away.Magnitude > 0.01 then
			dir = st.hrp.CFrame:VectorToObjectSpace(away.Unit)
		end
	end
	local k = amount or 1
	-- pitch back when hit from the front, roll when hit from the side
	st.torso:impulse(Vector3.new(dir.Z * 9, 0, -dir.X * 9) * k)
	st.kickRot:impulse(Vector3.new(4, (math.random() - 0.5) * 6, 0) * k)
end

function Rig.dash(character: Model, dirX: number, dirZ: number, duration: number)
	local st = rigs[character]
	if st then
		st.dashUntil = os.clock() + duration
		st.dashStart = os.clock()
		st.dashDir = Vector3.new(dirX, 0, dirZ)
	end
end

function Rig.setState(character: Model, alive: boolean, reload: number, ammoFrac: number?, reloadEmpty: boolean?)
	local st = rigs[character]
	if st then
		st.alive = alive
		if reload <= 0 or st.reload <= 0 then
			st.rl = reload -- snap at the start / end of a reload, smooth in between
			if reload > 0 then
				table.clear(st.beats)
				st.reloadEmpty = reloadEmpty == true
			end
		end
		st.reload = reload
		st.ammo = ammoFrac or st.ammo
	end
end

-- Evolution transformation: raise the weapon, unfold the new parts, settle back (1.6 s).
function Rig.evolve(character: Model)
	local st = rigs[character]
	if st then
		st.evoT = os.clock()
		st.equipT = -10
		beat(st, "evolve")
	end
end

-- Current muzzle world position (no frame lag: uses the live root CFrame).
function Rig.muzzle(character: Model): Vector3?
	local st = rigs[character]
	if st and st.gun and st.gunLocal then
		return (st.hrp.CFrame * st.gunLocal * st.gun.muzzle)
	end
	return nil
end

function Rig.muzzleCFrame(character: Model): CFrame?
	local st = rigs[character]
	if st and st.gun and st.gunLocal then
		return st.hrp.CFrame * st.gunLocal * CFrame.new(st.gun.muzzle)
	end
	return nil
end

-- World positions of the emitter electrode tips (the muzzle arc jumps between them), if any.
function Rig.prongTips(character: Model): (Vector3?, Vector3?)
	local st = rigs[character]
	if st and st.gun and st.gun.prongTips and st.gunLocal then
		local cf = st.hrp.CFrame * st.gunLocal
		return cf * st.gun.prongTips[1], cf * st.gun.prongTips[2]
	end
	return nil, nil
end

function Rig.gunCFrame(character: Model): CFrame?
	local st = rigs[character]
	if st and st.gun and st.gunLocal then
		return st.hrp.CFrame * st.gunLocal
	end
	return nil
end

function Rig.ejectCFrame(character: Model): CFrame?
	local st = rigs[character]
	if st and st.gun and st.gunLocal then
		return st.hrp.CFrame * st.gunLocal * CFrame.new(st.gun.eject)
	end
	return nil
end

-- Per-frame solve -------------------------------------------------------------------------------------
local function reloadPose(st, r: number, style: string, s: number)
	-- Returns: gunRot (extra rotation), gunOff (aim space), left-hand override target (gun space) and
	-- blend, plus group transforms.
	local rot, off = ID, Vector3.zero
	local handGun, handBlend = nil, 0
	local groupCF = {}
	local inOut = window(r, 0, 0.14) * (1 - window(r, 0.86, 1))
	if style == "cell" then
		-- Energy cell swap: cant the rifle, strip the spent cell, fetch a fresh one from the belt, seat
		-- it with a slap; an empty reload also racks the bolt. Beats fire once per reload.
		rot = CFrame.Angles(-0.2 * inOut, 0.2 * inOut, 0.6 * inOut)
		off = Vector3.new(-0.18, 0.12, 0.22) * inOut
		local empty = st.reloadEmpty
		local e = if empty then 0.82 else 1 -- the cell part of the timeline (empty: bolt after it)
		local pull = window(r, 0.24 * e, 0.36 * e)
		local insert = window(r, 0.56 * e, 0.72 * e)
		local away = pull >= 1 and insert <= 0
		groupCF.mag = CFrame.new(0, -1.5 * s * (pull - insert * pull), 0.25 * s * (pull - insert * pull))
		local belt = st.gun.mag + Vector3.new(-0.35 * s, -1.6 * s, 0.9 * s)
		local magHand = st.gun.mag + Vector3.new(0, -0.25 * s, 0)
		if pull < 1 then
			handGun = magHand + Vector3.new(0, -1.5 * s * pull, 0.25 * s * pull)
		elseif insert <= 0 then
			handGun = (magHand + Vector3.new(0, -1.5 * s, 0.25 * s)):Lerp(belt, window(r, 0.38 * e, 0.47 * e))
			handGun = handGun:Lerp(magHand + Vector3.new(0, -1.5 * s, 0.25 * s), window(r, 0.47 * e, 0.56 * e))
		else
			handGun = magHand + Vector3.new(0, -1.5 * s * (1 - insert), 0.25 * s * (1 - insert))
		end
		handBlend = window(r, 0.08 * e, 0.22 * e) * (1 - window(r, 0.8 * e, 0.92 * e))
		st.magHidden = away
		if pull >= 0.4 and not st.beats.magOut then
			st.beats.magOut = true
			beat(st, "magOut", st.gunWorld and st.gunWorld * CFrame.new(st.gun.mag) * CFrame.new(0, -0.6 * s, 0))
		end
		if insert >= 1 and not st.beats.magIn then
			st.beats.magIn = true
			beat(st, "magIn")
			st.kickRot:impulse(Vector3.new(-1.5, 0, 0.8))
		end
		if empty then
			-- left hand to the charging handle, rack it back, let it slam home
			local rack = window(r, 0.84, 0.9) * (1 - window(r, 0.92, 0.95))
			groupCF.bolt = CFrame.new(0, 0, 0.32 * s * rack)
			local boltBlend = window(r, 0.76, 0.84) * (1 - window(r, 0.94, 0.99))
			if boltBlend > 0 then
				handGun = (handGun or magHand):Lerp(
					st.gun.boltHandle + Vector3.new(0.05 * s, 0, 0.32 * s * rack),
					boltBlend
				)
				handBlend = math.max(handBlend, boltBlend)
			end
			if r >= 0.92 and not st.beats.bolt then
				st.beats.bolt = true
				beat(st, "bolt")
				st.kickPos:impulse(Vector3.new(0, 0, 3))
			end
		end
	elseif style == "mag" then
		rot = CFrame.Angles(-0.25 * inOut, 0.15 * inOut, 0.55 * inOut)
		off = Vector3.new(-0.15, 0.1, 0.25) * inOut
		local drop = window(r, 0.3, 0.42) * (1 - window(r, 0.55, 0.72))
		groupCF.mag = CFrame.new(0, -1.3 * s * drop, 0.15 * s * drop)
		handGun = st.gun.mag + Vector3.new(0, -0.25 * s - 1.3 * s * drop, 0)
		handBlend = window(r, 0.12, 0.3) * (1 - window(r, 0.72, 0.88))
	elseif style == "shells" then
		rot = CFrame.Angles(-0.1 * inOut, 0.2 * inOut, -0.7 * inOut)
		off = Vector3.new(-0.1, 0.05, 0.2) * inOut
		-- three shells: pocket (below the gun) -> loading port
		local k = math.clamp((r - 0.12) / 0.62, 0, 1) * 3
		local cyc = k % 1
		local toPort = if k >= 3 then 1 else smooth(cyc / 0.55) * (1 - window(cyc, 0.7, 1))
		local pocket = st.gun.mag + Vector3.new(-0.2, -1.1 * s, 0.9 * s)
		handGun = pocket:Lerp(st.gun.mag, toPort)
		handBlend = window(r, 0.1, 0.18) * (1 - window(r, 0.76, 0.84))
		local pump = window(r, 0.84, 0.91) * (1 - window(r, 0.92, 0.99))
		groupCF.pump = CFrame.new(0, 0, 0.55 * s * pump)
		st.pumpHand = 0.55 * s * pump
	elseif style == "vent" then
		rot = CFrame.Angles(0.55 * inOut, 0, 0.2 * inOut)
		off = Vector3.new(0, 0.15, 0.15) * inOut
		local lift = window(r, 0.12, 0.3) * (1 - window(r, 0.72, 0.9))
		groupCF.crystal = CFrame.new(0, 0.45 * s * lift, 0) * CFrame.Angles(0, r * 30, 0)
	elseif style == "breech" then
		rot = CFrame.Angles(0.35 * inOut, 0, 0.25 * inOut)
		off = Vector3.new(-0.1, 0.05, 0.2) * inOut
		local open = window(r, 0.12, 0.25) * (1 - window(r, 0.68, 0.78))
		groupCF.barrel = CFrame.new(0, 0, -0.5 * s * open)
		local insert = window(r, 0.28, 0.42) * (1 - window(r, 0.58, 0.7))
		handGun = st.gun.mag + Vector3.new(-0.5 * s * (1 - insert), 0.2 * s, 0)
		handBlend = window(r, 0.2, 0.32) * (1 - window(r, 0.6, 0.72))
	end
	return rot, off, handGun, handBlend, groupCF
end

local function step(st, dt: number, now: number)
	local hrp = st.hrp
	local hrpCF = hrp.CFrame
	local j = st.j
	local feel = st.feel
	local alive = st.alive ~= false
	st.dead = math.clamp(st.dead + (if alive then -dt * 3 else dt * 2.2), 0, 1)
	local dead = smooth(st.dead)

	-- Velocity in root space (smoothed) and turn rate.
	local wv = hrp.AssemblyLinearVelocity
	local lv = hrpCF:VectorToObjectSpace(Vector3.new(wv.X, 0, wv.Z))
	st.vel = st.vel:Lerp(lv, 1 - math.exp(-dt * 14))
	local look = hrpCF.LookVector
	local yawDelta = math.atan2(st.lastLook:Cross(look).Y, st.lastLook:Dot(look))
	st.lastLook = look
	st.yawRate += (yawDelta / math.max(dt, 1e-3) - st.yawRate) * (1 - math.exp(-dt * 10))
	local dashing = now < st.dashUntil
	local speed = st.vel.Magnitude
	local moveDir = if speed > 0.3 then st.vel / speed else Vector3.zero
	if speed < 2 and math.abs(st.yawRate) > 2 and not dashing then
		-- turning in place: shuffle the feet sideways
		moveDir = Vector3.new(if st.yawRate > 0 then -1 else 1, 0, 0)
		speed = math.min(8, math.abs(st.yawRate) * 1.2)
	end
	if dashing or dead > 0.5 then
		speed = 0
	end
	local legLen = st.legLen
	local ampGoal = math.clamp(speed * 0.07, 0, legLen * 0.55)
	st.amp += (ampGoal - st.amp) * (1 - math.exp(-dt * 10))
	if st.amp > 0.04 then
		st.phase += dt * math.pi * math.max(speed, 2) / (2 * math.max(st.amp, 0.25))
	end
	st.moveDir = if moveDir.Magnitude > 0 then moveDir else (st.moveDir or Vector3.new(0, 0, -1))
	local moving = math.clamp(st.amp / 0.5, 0, 1)
	local ph = st.phase

	-- Springs.
	local kickP = st.kickPos:step(dt)
	local kickR = st.kickRot:step(dt)
	local torso = st.torso:step(dt)
	if now - st.lastShot > 0.9 then
		st.ready.target = 0
	end
	local ready = st.ready:step(dt)

	-- Root: bob, lean into motion, dash dive, death collapse.
	local bob = (0.5 - 0.5 * math.cos(2 * ph)) * 0.16 * moving
	local fwd, side = -st.vel.Z, st.vel.X
	local leanP = -math.clamp(fwd / 18, -1, 1) * 0.14 * (1 - dead)
	local leanR = -math.clamp(side / 18, -1, 1) * 0.1 * (1 - dead)
	local dashK = 0
	if dashing then
		local p = (now - (st.dashStart or now)) / math.max(0.01, st.dashUntil - (st.dashStart or now))
		dashK = math.sin(math.clamp(p, 0, 1) * math.pi)
		local dl = hrpCF:VectorToObjectSpace(st.dashDir)
		leanP += dl.Z * 0.45 * dashK
		leanR += -dl.X * 0.35 * dashK
	end
	local drop = bob + dead * legLen * 0.62 + dashK * 0.35
	-- Bladed shooting stance: left shoulder toward the target so both hands reach the gun.
	local blade = if st.gun then -0.5 * (1 - dead) * (1 - dashK * 0.5) else 0
	local rootTwist = if st.r15 then blade * 0.3 else blade * 0.7
	local rootBody = CFrame.new(0, -drop, 0)
		* CFrame.Angles(leanP - dead * 0.35, rootTwist, leanR + math.sin(ph) * 0.03 * moving)
	local Troot = toJoint(j.root, rootBody)

	-- FK down the spine.
	local rootPart = fk(hrpCF, j.root, Troot) -- LowerTorso (R15) / Torso (R6)
	local upper = rootPart
	if st.r15 then
		local breathe = math.sin(now * 1.6) * 0.012
		local waistBody = CFrame.Angles(
			torso.X * 0.6 + breathe - dead * 0.25,
			blade * 0.7 - math.sin(ph) * 0.06 * moving + torso.Y * 0.5,
			torso.Z * 0.5
		)
		local Twaist = toJoint(j.waist, waistBody)
		j.waist.motor.Transform = Twaist
		upper = fk(rootPart, j.waist, Twaist)
		-- keep the head level-ish against the lean, nod with recoil
		local neckBody = CFrame.Angles(-leanP * 0.6 - torso.X * 0.3 + dead * 0.4, -blade, -leanR * 0.5)
		j.neck.motor.Transform = toJoint(j.neck, neckBody)
	else
		local neckBody = CFrame.Angles(-leanP * 0.6 + dead * 0.4, -rootTwist, 0)
		j.neck.motor.Transform = toJoint(j.neck, neckBody)
	end
	j.root.motor.Transform = Troot

	-- Gun pose (aim space = root yaw).
	local yawRot = hrpCF.Rotation
	local gun = st.gun
	local rightTarget, leftTarget, handRot
	if gun and feel then
		local s = feel.scale
		local shoulderR = if st.r15 then upper * j.rShoulder.C0 else rootPart * j.rShoulder.C0
		local shoulderPos = shoulderR.Position
		local low = (1 - ready) * feel.lowReady + dead * 0.9 + dashK * 0.5
		local swayAmt = feel.sway * moving
		local turnLag = math.clamp(st.yawRate * 0.02, -0.18, 0.18)
		local sway = CFrame.new(math.sin(ph) * 0.05 * swayAmt, math.abs(math.cos(ph)) * 0.06 * swayAmt, 0)
			* CFrame.Angles(math.sin(now * 1.3) * 0.01, -turnLag * feel.sway, -turnLag * 0.8 * feel.sway)
		local buzz = st.buzz * (feel.recoil.buzz or 0)
		if buzz > 0 then
			sway *= CFrame.new((math.random() - 0.5) * buzz, (math.random() - 0.5) * buzz, (math.random() - 0.5) * buzz)
		end
		local rRot, rOff, handGun, handBlend, groupCF = ID, Vector3.zero, nil, 0, {}
		st.pumpHand = 0
		st.magHidden = false
		if st.reload > 0 and alive then
			-- server reload progress arrives at ~20 Hz: advance smoothly between updates
			st.rl = math.min(st.reload + 0.06, st.rl + (st.reload - st.rl) * math.min(1, dt * 12) + dt * 0.5)
			rRot, rOff, handGun, handBlend, groupCF = reloadPose(st, math.clamp(st.rl, 0, 1), feel.reload, s)
		end
		-- Draw: the rifle swings up from a low carry into the shoulder.
		local equip = smooth((now - st.equipT) / 0.55)
		if equip < 1 then
			rRot = rRot * CFrame.Angles(-1.1 * (1 - equip), 0.5 * (1 - equip), 0.9 * (1 - equip))
			rOff += Vector3.new(0.25, -0.45, 0.35) * (1 - equip)
		end
		-- Evolution: present the weapon, unfold its new parts, snap back to the shoulder.
		local evo = (now - st.evoT) / EVOLVE_TIME
		local present = 0
		if evo >= 0 and evo <= 1 then
			present = window(evo, 0, 0.16) * (1 - window(evo, 0.84, 1))
			rRot = rRot * CFrame.Angles(0.25 * present, 0.95 * present, 0.15 * present * math.sin(evo * 18))
			rOff += Vector3.new(0.5, 0.45, 0.35) * present
		end
		local hold = feel.hold + rOff + Vector3.new(-0.12 * (1 - ready), -0.12 * (1 - ready), 0.1 * (1 - ready))
		local gripWorld = shoulderPos + yawRot:VectorToWorldSpace(hold)
		local gunCF = CFrame.new(gripWorld)
			* yawRot
			* sway
			* CFrame.new(kickP.X, kickP.Y, kickP.Z)
			* CFrame.Angles(kickR.X - low, kickR.Y, kickR.Z)
			* rRot
		local gunRoot = gunCF * CFrame.new(-gun.grip)
		st.gunLocal = hrpCF:ToObjectSpace(gunRoot)
		st.gunWorld = gunRoot
		gun.motor.Transform = st.gunLocal

		-- Mechanisms.
		local since = now - st.actionT
		if feel.action == "pump" and since < (feel.actionTime or 0.4) and not groupCF.pump then
			local p = math.clamp((since - 0.07) / ((feel.actionTime or 0.4) - 0.07), 0, 1)
			local slide = math.sin(p * math.pi) * 0.55 * s
			groupCF.pump = CFrame.new(0, 0, slide)
			st.pumpHand = slide
		elseif feel.action == "slide" and not groupCF.barrel then
			local p = math.clamp(since / (feel.actionTime or 0.5), 0, 1)
			groupCF.barrel = CFrame.new(0, 0, 0.55 * s * (1 - p) ^ 2)
		elseif feel.action == "spin" and not groupCF.crystal then
			groupCF.crystal = CFrame.new(0, math.sin(now * 3) * 0.06 * s + st.buzz * 0.08 * s, 0)
		elseif feel.action == "coil" then
			-- bolt cycles with every shot; coils spin up with sustained fire; prongs flare
			local firing = since < 0.25
			st.spin += ((if firing then 22 else 0) - st.spin) * math.min(1, dt * (if firing then 6 else 1.5))
			st.coilAng = (st.coilAng + st.spin * dt) % (2 * math.pi)
			st.heat = math.clamp(st.heat + (if firing then dt * 0.45 else -dt * 0.5), 0, 1)
			if not groupCF.bolt then
				local cyc = if since < 0.025 then since / 0.025 else math.max(0, 1 - (since - 0.025) / 0.07)
				groupCF.bolt = CFrame.new(0, 0, 0.26 * s * cyc)
			end
			local pivot = gun.pivots.coil
			if pivot then
				groupCF.coil = CFrame.new(pivot) * CFrame.Angles(0, 0, st.coilAng) * CFrame.new(-pivot)
			end
			local flare = 0.06 * s * math.exp(-since * 28)
			groupCF.prongU = CFrame.new(0, flare, 0)
			groupCF.prongD = CFrame.new(0, -flare, 0)
			groupCF.prongL = CFrame.new(-flare, 0, 0)
			groupCF.prongR = CFrame.new(flare, 0, 0)
		end
		-- Evolution unfold: crown prongs slide out of the emitter, capacitors out of the handguard,
		-- the lightning rod rises from the sight.
		if present > 0 or (evo >= 0 and evo <= 1) then
			local u = window(evo, 0.3, 0.62)
			local v = window(evo, 0.45, 0.75)
			local w = window(evo, 0.55, 0.85)
			groupCF.prongL = (groupCF.prongL or ID) * CFrame.new(0.15 * s * (1 - u), 0, 0.7 * s * (1 - u))
			groupCF.prongR = (groupCF.prongR or ID) * CFrame.new(-0.15 * s * (1 - u), 0, 0.7 * s * (1 - u))
			groupCF.capL = CFrame.new(0.3 * s * (1 - v), 0, 0)
			groupCF.capR = CFrame.new(-0.3 * s * (1 - v), 0, 0)
			groupCF.rod = CFrame.new(0, -0.5 * s * (1 - w), 0)
		end
		for name, motor in gun.groups do
			motor.Transform = groupCF[name] or ID
		end
		local magParts = gun.groupParts.mag
		if magParts and st.magShown ~= not st.magHidden then
			st.magShown = not st.magHidden
			for _, part in magParts do
				part.LocalTransparencyModifier = if st.magHidden then 1 else 0
			end
		end
		-- Charge windows: lit by rounds left (dark while the cell is out, blink red when low).
		local cells = gun.cells
		if #cells > 0 then
			local frac = if st.reload > 0 then window(st.rl, 0.75, 0.95) else st.ammo
			local lowBlink = frac > 0 and frac < 0.2 and st.reload <= 0 and math.sin(now * 14) > 0
			for k, c in cells do
				local lit = frac > (k - 1) / 3 + 0.001
				c.Transparency = if lit then (if lowBlink then 0.6 else 0) else 0.85
				c.Color = if frac < 0.2 and st.reload <= 0 then Color3.fromRGB(255, 70, 60) else c:GetAttribute("Base")
			end
		end
		if gun.heatPart then
			local base = gun.heatPart:GetAttribute("Base")
			gun.heatPart.Transparency = 0.55 * (1 - st.heat)
			gun.heatPart.Color = base:Lerp(Color3.new(1, 1, 1), st.heat * 0.6)
		end
		if gun.core then
			gun.core.Transparency = 0.25 + 0.25 * math.sin(now * 9) - present * 0.25
		end
		if gun.charge and feel.charge then
			local c = math.clamp((now - st.lastShot) * 1.6, 0, 1)
			gun.charge.Transparency = 0.7 * (1 - c)
		end

		handRot = yawRot * sway * CFrame.Angles(kickR.X - low + 0.35, 0, 0) * rRot
		rightTarget = gunRoot * gun.grip
		local fore = gun.fore + Vector3.new(0, 0, st.pumpHand)
		leftTarget = gunRoot * fore
		if handGun and handBlend > 0 then
			leftTarget = leftTarget:Lerp(gunRoot * handGun, handBlend)
		end
	end

	-- Arms.
	local poleR = yawRot:VectorToWorldSpace(Vector3.new(0.7, -1, 0.6))
	local poleL = yawRot:VectorToWorldSpace(Vector3.new(-0.9, -1, 0.3))
	if st.r15 then
		for _, side in { "r", "l" } do
			local sh, el, wr = j[side .. "Shoulder"], j[side .. "Elbow"], j[side .. "Wrist"]
			local target = if side == "r" then rightTarget else leftTarget
			if target then
				local grip = if side == "r" then st.gripR else st.gripL
				local handCF = CFrame.new(target) * handRot * CFrame.new(-grip)
				local wristJ = handCF * wr.C1
				local base = upper * sh.C0
				local TA, TB = solve2(
					base,
					sh,
					el,
					wr.C0.Position,
					wristJ.Position,
					if side == "r" then poleR else poleL,
					X_AXIS,
					1
				)
				sh.motor.Transform = TA
				el.motor.Transform = TB
				local upperArm = base * TA * sh.C1inv
				local lowerArm = fk(upperArm, el, TB)
				wr.motor.Transform = ((lowerArm * wr.C0):Inverse() * wristJ).Rotation
			else
				-- no weapon: relaxed arms swinging with the stride
				local swing = math.sin(ph + (if side == "r" then math.pi else 0)) * 0.5 * moving
				sh.motor.Transform = toJoint(sh, CFrame.Angles(swing, 0, 0))
				el.motor.Transform = toJoint(el, CFrame.Angles(0.3 + 0.2 * moving, 0, 0))
				wr.motor.Transform = ID
			end
		end
	else
		for _, side in { "r", "l" } do
			local sh = j[side .. "Shoulder"]
			local target = if side == "r" then rightTarget else leftTarget
			if target then
				sh.motor.Transform = aim1(rootPart * sh.C0, sh, Vector3.new(0, -0.9, 0), target)
			else
				sh.motor.Transform =
					toJoint(sh, CFrame.Angles(math.sin(ph + (if side == "r" then math.pi else 0)) * 0.6 * moving, 0, 0))
			end
		end
	end

	-- Legs: planted feet driven by the stride.
	local kneePole = yawRot:VectorToWorldSpace(Vector3.new(0, 0.2, -1))
	for i, side in { "r", "l" } do
		local fph = ph + (if i == 1 then 0 else math.pi)
		local rest = st["restAnkle" .. side]
		local stride = -st.moveDir * st.amp * math.cos(fph)
		local lift = math.max(0, math.sin(fph)) * legLen * 0.24 * moving
		local foot = rest + Vector3.new(stride.X, lift, stride.Z)
		if dashK > 0 then
			local dl = hrpCF:VectorToObjectSpace(st.dashDir)
			foot = foot:Lerp(
				rest
					- Vector3.new(dl.X, 0, dl.Z) * legLen * (if i == 1 then 0.35 else 0.1)
					+ Vector3.new(0, legLen * (if i == 1 then 0.35 else 0.15), 0),
				dashK
			)
		end
		if dead > 0 then
			-- kneel: one foot forward, the other knee to the ground
			foot = foot:Lerp(rest + Vector3.new(0, 0, if i == 1 then -legLen * 0.45 else legLen * 0.35), dead)
		end
		local footWorld = hrpCF * foot
		local hip = j[side .. "Hip"]
		if st.r15 then
			local knee, ankle = j[side .. "Knee"], j[side .. "Ankle"]
			local base = rootPart * hip.C0
			local TA, TB = solve2(base, hip, knee, ankle.C0.Position, footWorld, kneePole, X_AXIS, -1)
			hip.motor.Transform = TA
			knee.motor.Transform = TB
			local upperLeg = base * TA * hip.C1inv
			local lowerLeg = fk(upperLeg, knee, TB)
			local toe = -math.sin(fph) * 0.35 * moving
			local footRot = yawRot * CFrame.Angles(toe, 0, 0)
			ankle.motor.Transform = ((lowerLeg * ankle.C0):Inverse() * footRot * ankle.C1).Rotation
		else
			hip.motor.Transform = aim1(rootPart * hip.C0, hip, Vector3.new(0, -1, 0), footWorld)
		end
	end
end

-- At home (DD-083) the body belongs to Roblox's own animations: the joints are let go and the gun is
-- slung across the back. A fight (or the range) takes the body back.
local SLUNG = CFrame.new(0.15, -0.35, 0.78) * CFrame.Angles(0, 0, math.rad(-38)) * CFrame.Angles(math.rad(90), 0, 0)
function Rig.setCalm(character: Model, on: boolean)
	local st = rigs[character]
	if not st or st.calm == on then
		return
	end
	st.calm = on
	if on then
		for _, info in st.j do
			if info.motor.Parent then
				info.motor.Transform = CFrame.identity
			end
		end
	end
end

function Rig.update(dt: number)
	local now = os.clock()
	for character, st in rigs do
		if st and st.calm and character.Parent then
			if st.gun and st.gun.motor.Parent then
				st.gun.motor.Transform = SLUNG
			end
			continue
		end
		if character.Parent and st and valid(st) then
			local ok, err = pcall(step, st, dt, now)
			if not ok and RunService:IsStudio() and not st.warned then
				st.warned = true
				warn("[SWARMFALL] rig", err)
			end
		else
			rigs[character] = nil
		end
	end
end

function Rig.track(character: Model)
	return Rig.get(character)
end

RunService.PreSimulation:Connect(Rig.update)

return Rig
