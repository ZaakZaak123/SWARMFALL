--!nonstrict
-- Combat camera with three views: "top" (elevated tactical, default), "third" (over-the-shoulder) and
-- "first". Views are parameter sets (distance, pitch, pivot height, shoulder, FOV, aim lead, follow
-- stiffness, yaw source). Switching blends the *parameters* with an ease-in-out curve, so the camera
-- flies along a natural arc — swooping down behind the player, sliding into the head, or rising back
-- into the sky — instead of cutting or lerping between two fixed CFrames.

local UserInputService = game:GetService("UserInputService")
local Settings = require(script.Parent.Settings)
local Spring = require(script.Parent.Spring)

local CameraRig = {}

CameraRig.Modes = { "top", "third", "first" }
CameraRig.ModeNames =
	{ top = "ВИД СВЕРХУ", third = "ОТ ТРЕТЬЕГО ЛИЦА", first = "ОТ ПЕРВОГО ЛИЦА" }
CameraRig.ModeIcons = { top = "topdown", third = "person", first = "eye" }

local transitionTime = 1.15
local BASE_DIST = 64

local mode = "top"
local fromP = nil -- parameter snapshot at transition start
local transT = 1 -- 0..1 progress
local current = nil -- live (blended) parameters
local camYaw = 0 -- player-controlled yaw for third/first (0 = looking toward +Z)
local camPitch = 0 -- player-controlled extra pitch (radians, + looks down)
local follow: Vector3? = nil
local trauma = 0
local fovKick = 0
local zoomT = 0
local zoomUntil = 0
local orbitAngle = 0
local seed = math.random() * 100
-- Weapon recoil response: view kick (pitch up, recovers) and positional push against the shot.
local kickSpring = Spring.new(5, 0.62, 0)
local pushSpring = Spring.new(6, 0.7, Vector3.zero)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function distanceFor(size: Vector2): number
	local aspect = size.X / math.max(1, size.Y)
	local dist = math.clamp(BASE_DIST + (1.78 - aspect) * 18, 48, 78)
	-- DD-085: a phone's small screen comes a little closer, or the hero and the swarm are specks
	local phone = game:GetService("UserInputService").TouchEnabled and size.Y < 560
	return if phone then dist * 0.86 else dist
end

-- Parameter targets per view. yawMix: 0 = fixed north (top), 1 = player yaw.
local function target(m: string)
	local cam = workspace.CurrentCamera
	if m == "third" then
		return {
			dist = 16,
			pitch = math.rad(21),
			height = 6,
			shoulder = 2.2,
			fov = 70,
			lead = 0,
			stiff = 16,
			yawMix = 1,
			look = 1,
		}
	elseif m == "first" then
		return {
			dist = 0.8,
			pitch = math.rad(4),
			height = 1.9,
			shoulder = 0,
			fov = 78,
			lead = 0,
			stiff = 40,
			yawMix = 1,
			look = 1,
		}
	end
	return {
		dist = distanceFor(cam.ViewportSize),
		pitch = math.rad(56),
		height = 0,
		shoulder = 0,
		fov = 60,
		lead = 1,
		stiff = 9,
		yawMix = 0,
		look = 0,
	}
end

local KEYS = { "dist", "pitch", "height", "shoulder", "fov", "lead", "stiff", "yawMix", "look" }

local function ease(t: number): number
	-- easeInOutSine: gentle start/stop with a low peak speed (π/2× average) — reads as a dolly move.
	return -(math.cos(math.pi * t) - 1) / 2
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

function CameraRig.mode(): string
	return mode
end

function CameraRig.transitioning(): boolean
	return transT < 1
end

-- Immersive views use mouse-look / stick-look for aiming.
function CameraRig.immersive(): boolean
	return mode ~= "top"
end

-- Switch to a view; aimX/aimZ seeds the yaw so the camera swings in behind where you face.
function CameraRig.setMode(m: string, aimX: number?, aimZ: number?)
	if m == mode or not table.find(CameraRig.Modes, m) then
		return
	end
	if mode == "top" and aimX then
		camYaw = math.atan2(aimX, aimZ)
		camPitch = 0
	end
	fromP = table.clone(current or target(mode))
	fromP.yaw = (current and current.yaw) or 0
	-- Long sweeps (to/from the sky) take longer than the short slide into the head.
	transitionTime = if m == "top" or fromP.dist > 30 then 1.25 else 0.8
	mode = m
	transT = 0
end

function CameraRig.cycle(aimX: number?, aimZ: number?): string
	local i = table.find(CameraRig.Modes, mode) or 1
	local nextMode = CameraRig.Modes[i % #CameraRig.Modes + 1]
	CameraRig.setMode(nextMode, aimX, aimZ)
	return nextMode
end

-- Look input: radians of yaw/pitch to add (mouse delta, stick, touch drag).
function CameraRig.look(dYaw: number, dPitch: number)
	camYaw -= dYaw
	camPitch = math.clamp(camPitch + dPitch, math.rad(-35), math.rad(40))
end

-- Horizontal aim direction for immersive views.
function CameraRig.forward(): (number, number)
	return math.sin(camYaw), math.cos(camYaw)
end

function CameraRig.shake(amount: number)
	trauma = math.min(1, trauma + amount * (if Settings.shake then 1 else 0.25))
end

function CameraRig.punch(amount: number)
	fovKick = math.max(fovKick, amount)
end

-- kickDeg: view pitch kick; dir: horizontal shot direction; push: studs the camera is shoved back.
function CameraRig.recoil(kickDeg: number, dir: Vector3, push: number, fov: number)
	local k = if Settings.shake then 1 else 0.4
	if kickDeg > 0 then
		kickSpring:impulse(math.rad(kickDeg) * kickSpring.f * 2 * math.pi * 1.6 * k)
	end
	if push > 0 and dir.Magnitude > 0.01 then
		pushSpring:impulse(-dir.Unit * push * pushSpring.f * 2 * math.pi * 1.6 * k)
	end
	if fov > 0 then
		fovKick = math.max(fovKick, fov)
	end
end

function CameraRig.closeUp(duration: number)
	zoomUntil = os.clock() + duration
end

local INTRO_TIME = 3.2
local introT = 1
function CameraRig.intro()
	introT = 0
end

function CameraRig.reset()
	follow = nil
	trauma = 0
end

function CameraRig.setCollision(folder: Instance?)
	rayParams.FilterDescendantsInstances = if folder then { folder } else {}
end

-- view: "play" | "lobby". focus = character root position (nil -> lobby orbit).
function CameraRig.update(
	dt: number,
	view: string,
	focus: Vector3?,
	aimX: number,
	aimZ: number,
	leadScale: number,
	forceTop: boolean?,
	hero: Vector3?
)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local now = os.clock()
	trauma = math.max(0, trauma - dt * 1.6)
	fovKick = math.max(0, fovKick - dt * 30)
	local shake = trauma * trauma
	local sx = (math.noise(now * 18, seed) * 2) * shake * 1.6
	local sy = (math.noise(seed, now * 18) * 2) * shake * 1.6
	local roll = math.noise(now * 12, seed + 5) * shake * 0.04

	if view == "lobby" or not focus then
		orbitAngle += dt * 0.05
		cam.FieldOfView = 50
		if hero then
			-- Lobby: over the hero's shoulder at the dropship ramp, the whole crater ahead and the titan's
			-- skull on the horizon. A slow breathing drift keeps the shot alive.
			local sway = math.sin(orbitAngle) * 3
			-- (camera stays in front of the dropship hull; the hero stands in the right third)
			local pos = hero + Vector3.new(6 + sway * 0.3, 3 + math.sin(orbitAngle * 0.7) * 0.5, -12)
			cam.CFrame = CFrame.lookAt(pos, hero + Vector3.new(-2 + sway * 0.2, 5, 40))
		else
			local center = Vector3.new(0, 6, 0)
			local pos = center + Vector3.new(math.cos(orbitAngle) * 112, 44, math.sin(orbitAngle) * 112)
			cam.CFrame = CFrame.lookAt(pos, center)
		end
		follow = nil
		current = nil
		return
	end

	-- Spectating / dead: fall back to the tactical view (smoothly).
	if forceTop and mode ~= "top" then
		CameraRig.setMode("top")
	end

	-- Blend parameters.
	local goal = target(mode)
	goal.yaw = lerpAngle(0, camYaw, goal.yawMix)
	if goal.yawMix > 0 then
		goal.yaw = camYaw
	end
	if not current then
		current = table.clone(goal)
		transT = 1
	end
	if transT < 1 then
		transT = math.min(1, transT + dt / transitionTime)
		local e = ease(transT)
		for _, k in KEYS do
			current[k] = fromP[k] + (goal[k] - fromP[k]) * e
		end
		current.yaw = lerpAngle(fromP.yaw, goal.yaw, e)
		-- Cinematic arc: lift the camera a bit mid-flight so it never dives through the player.
		current.arc = math.sin(transT * math.pi) * (if mode == "first" or (fromP.dist < 1) then 1.5 else 6)
	else
		for _, k in KEYS do
			current[k] = goal[k]
		end
		current.yaw = goal.yaw
		current.arc = 0
	end
	local p = current

	-- Evolution close-up (top view only feels needed; harmless elsewhere).
	local zooming = now < zoomUntil
	zoomT = math.clamp(zoomT + (if zooming then dt * 3 else -dt * 2), 0, 1)
	local z = zoomT * zoomT * (3 - 2 * zoomT)
	local dist = p.dist * (1 - 0.55 * z * (1 - p.look))

	-- Follow point: top view leads toward the aim; immersive views track tightly.
	local lead = Vector3.new(aimX, 0, aimZ) * 7 * leadScale * p.lead * (1 - z)
	local targetPos = Vector3.new(focus.X, 0, focus.Z) + lead + Vector3.new(0, 0, -3 * p.lead)
	if not follow then
		follow = targetPos
	else
		follow = follow:Lerp(targetPos, 1 - math.exp(-dt * p.stiff))
	end
	local pivot = follow + Vector3.new(0, focus.Y + p.height - (focus.Y * (1 - p.look)) + p.arc, 0)

	-- Orientation: base pitch from the view + player look pitch (only in immersive views).
	local kick = kickSpring:step(dt)
	local push = pushSpring:step(dt)
	local pitch = p.pitch + camPitch * p.look - kick * (0.35 + 0.65 * p.look)
	local yaw = p.yaw
	local forward = Vector3.new(math.sin(yaw) * math.cos(pitch), -math.sin(pitch), math.cos(yaw) * math.cos(pitch))
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	-- Roblox is right-handed: screen-right when looking along +Z is -X.
	right = -right
	local camPos = pivot - forward * dist + right * p.shoulder + push * (1 - p.look * 0.7)

	-- Keep the shoulder camera out of walls.
	if dist > 1 and p.look > 0.5 then
		local hit = workspace:Raycast(pivot, camPos - pivot, rayParams)
		if hit then
			camPos = hit.Position + (pivot - camPos).Unit * 0.6
		end
	end

	cam.CFrame = CFrame.lookAt(camPos, camPos + forward) * CFrame.new(sx, sy, 0) * CFrame.Angles(0, 0, roll)
	cam.FieldOfView = p.fov + fovKick - 8 * z
	-- Landing shot (DD-036): a hunt opens high over the crater and swoops down onto the hero.
	if introT < 1 then
		introT = math.min(1, introT + dt / INTRO_TIME)
		local k = ease(introT)
		local from = CFrame.lookAt(focus + Vector3.new(-40, 120, -150), focus + Vector3.new(0, 0, 60))
		cam.CFrame = from:Lerp(cam.CFrame, k)
		cam.FieldOfView = 70 + (cam.FieldOfView - 70) * k
	end
end

-- 0 (camera away from the head) .. 1 (camera inside the head): used to fade the own body out.
function CameraRig.firstPersonAmount(): number
	if not current then
		return 0
	end
	return math.clamp(1 - (current.dist - 0.9) / 3.5, 0, 1)
end

-- Per-frame look input for immersive views (mouse lock handled here).
function CameraRig.processInput(dt: number, device: string, active: boolean, stick: Vector2?)
	local wantLock = active and mode ~= "top" and device == "pc"
	UserInputService.MouseBehavior = if wantLock then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
	if not active or mode == "top" then
		return
	end
	if device == "pc" then
		local d = UserInputService:GetMouseDelta()
		local sens = 0.0042 * (if mode == "first" then 0.85 else 1)
		CameraRig.look(d.X * sens, d.Y * sens)
	elseif stick and stick.Magnitude > 0.08 then
		-- stick/touch: rate-based turning with a response curve for fine aim near center
		local m = stick.Magnitude
		local curve = (m ^ 1.6) / m
		CameraRig.look(stick.X * curve * 3.2 * dt, -stick.Y * curve * 1.4 * dt)
	end
end

return CameraRig
