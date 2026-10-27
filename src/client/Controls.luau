--!nonstrict
-- Unified input: mouse/keyboard, touch (left = Roblox thumbstick, right = aim pad that fires while
-- dragged, big action buttons) and gamepad (right stick aim, R2 fire). Produces aim + fire intents.
-- DD-098 (owner on a phone: «еле попадаю в любом виде»): touch auto-aims by default. The gun turns to
-- the nearest enemy (the ones ahead count as nearer, the held target sticks) and fires by itself; a
-- ring under the target shows whom. The right pad still points the gun by hand (top view) or turns the
-- camera (third/first person); in third person the camera also swings in behind the run by itself.

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)
local Settings = require(script.Parent.Settings)
local EnemyView = require(script.Parent.EnemyView)
local Icons = require(script.Parent.Icons)
local CameraRig = require(script.Parent.CameraRig)

local new = Theme.new
local C = Theme.C

local Controls = {
	aimX = 0,
	aimZ = 1,
	firing = false,
	device = if Settings.touch
		then "touch"
		elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then "gamepad"
		else "pc",
	cursor = Vector2.new(0, 0),
	enabled = false,
	actions = {}, -- name -> callback
}

local mouseDown = false
local padFire = false
local touchAim: InputObject? = nil
local touchVec = Vector2.zero
local gui, pad, knob, buttons
local touchLayoutSize = Vector2.zero
local autoId = nil -- the enemy the touch auto-aim holds
local marker = nil -- the ring under it
local lastRoot = nil -- the hero's position last frame (his run turns the third-person camera)
local TURN = 16 -- radians per second the auto-aim swings the gun (quick, but a visible turn, not a snap)

local function turnToward(ax: number, az: number, tx: number, tz: number, dt: number): (number, number)
	local a, b = math.atan2(ax, az), math.atan2(tx, tz)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	local step = math.clamp(d, -TURN * dt, TURN * dt)
	return math.sin(a + step), math.cos(a + step)
end

local function showMarker(at: Vector3?)
	if not at then
		if marker then
			marker.Parent = nil
		end
		return
	end
	if not marker then
		marker = Instance.new("Part")
		marker.Name = "AutoAimMark"
		marker.Shape = Enum.PartType.Cylinder
		marker.Size = Vector3.new(0.12, 5, 5)
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.CastShadow = false
		marker.Material = Enum.Material.Neon
		marker.Color = C.lime
		marker.Transparency = 0.45
	end
	marker.CFrame = CFrame.new(at.X, at.Y, at.Z) * CFrame.Angles(0, os.clock() * 2, math.pi / 2)
	marker.Parent = workspace
end

-- The touch auto-aim: a target in range (in third person only one in front or close by), the gun
-- turned toward it. Returns the new aim and whether there is something to shoot.
local function autoAim(rootPos: Vector3, ax: number, az: number, range: number, front: boolean, dt: number)
	local id, tx, tz = EnemyView.autoTarget(rootPos.X, rootPos.Z, range, ax, az, autoId)
	if id and front then
		local cx, cz = tx - rootPos.X, tz - rootPos.Z
		local d = math.sqrt(cx * cx + cz * cz)
		local fx, fz = CameraRig.forward()
		if d > 14 and (cx * fx + cz * fz) / math.max(d, 0.1) < -0.2 then
			id = nil -- far behind the camera: not ours to turn round for
		end
	end
	autoId = id
	if not id then
		showMarker(nil)
		return ax, az, false
	end
	local cx, cz = tx - rootPos.X, tz - rootPos.Z
	local d = math.max(0.1, math.sqrt(cx * cx + cz * cz))
	local p = EnemyView.position(id)
	showMarker(Vector3.new(tx, (if p then p.Y else rootPos.Y) - 2.4, tz))
	local nx, nz = turnToward(ax, az, cx / d, cz / d, dt)
	return nx, nz, true
end

-- Keep the aim pad and abilities in the right thumb's corner on short landscape screens.
-- The original fixed offsets put Dash over the vitals/tutorial and Reload near the top edge.
local function layoutTouch()
	local size = workspace.CurrentCamera.ViewportSize
	if size == touchLayoutSize then
		return
	end
	touchLayoutSize = size
	local k = math.clamp(size.Y / 600, 0.68, 1)
	pad.Position = UDim2.new(1, -150 * k, 1, -150 * k)
	pad.Size = UDim2.fromOffset(200 * k, 200 * k)
	knob.Size = UDim2.fromOffset(74 * k, 74 * k)
	for _, b in buttons do
		local p = b.position
		b.button.Position = UDim2.new(p.X.Scale, p.X.Offset * k, p.Y.Scale, p.Y.Offset * k)
		local diameter = math.max(44, b.size * k)
		b.button.Size = UDim2.fromOffset(diameter, diameter)
		b.icon.Size = UDim2.fromOffset(diameter * 0.46, diameter * 0.46)
	end
end

local function act(name: string)
	local fn = Controls.actions[name]
	if fn then
		fn()
	end
end

local function makeButton(name: string, label: string, sub: string, pos: UDim2, size: number, color: Color3)
	local b = new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.3,
		Text = "",
		Corner = UDim.new(1, 0),
		Stroke = { Color = color, Thickness = 2.5, Transparency = 0.25 },
		Parent = gui,
	})
	local ic = Icons.new(label, math.floor(size * 0.46), color, C.ink)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.42)
	ic.Parent = b
	local subLabel = Theme.label(sub, {
		Name = "Sub",
		Size = UDim2.fromScale(1, 0.22),
		Position = UDim2.fromScale(0, 0.66),
		FontFace = Theme.F.num,
		TextScaled = true,
		TextColor3 = C.dim,
		Parent = b,
	})
	local fill = new("Frame", {
		Name = "Cooldown",
		Size = UDim2.fromScale(1, 0),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.75,
		Corner = UDim.new(1, 0),
		Parent = b,
	})
	return { button = b, sub = subLabel, fill = fill, color = color, size = size, position = pos, icon = ic }
end

function Controls.init(playerGui: PlayerGui)
	gui = new("ScreenGui", {
		Name = "SwarmTouch",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		Enabled = false,
		Parent = playerGui,
	})
	pad = new("Frame", {
		Name = "AimPad",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -150, 1, -150),
		Size = UDim2.fromOffset(200, 200),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.6,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.lime, Thickness = 2, Transparency = 0.5 },
		Parent = gui,
	})
	local cross = Icons.new("crosshair", 40, C.lime, C.ink)
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Position = UDim2.fromScale(0.5, 0.5)
	cross.Parent = pad
	knob = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(74, 74),
		BackgroundColor3 = C.lime,
		BackgroundTransparency = 0.45,
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.lime, Thickness = 2, Transparency = 0.1 },
		Parent = pad,
	})
	buttons = {
		dash = makeButton("Dash", "dash", "", UDim2.new(1, -300, 1, -90), 84, C.cyan),
		overdrive = makeButton("Gravihammer", "hammer", "", UDim2.new(1, -290, 1, -195), 76, C.lime),
		evolve = makeButton("Evolve", "evolve", "", UDim2.new(1, -150, 1, -300), 76, C.gold),
		reload = makeButton("Reload", "reload", "", UDim2.new(1, -60, 1, -290), 54, C.dim),
		view = makeButton("View", "topdown", "", UDim2.new(1, -60, 1, -370), 54, C.cyan),
	}
	-- DD-082: phones switch the view too (the first fight teaches the three views)
	buttons.dash.button.Activated:Connect(function()
		act("dash")
	end)
	buttons.overdrive.button.Activated:Connect(function()
		act("overdrive")
	end)
	buttons.evolve.button.Activated:Connect(function()
		act("evolve")
	end)
	buttons.reload.button.Activated:Connect(function()
		act("reload")
	end)
	buttons.view.button.Activated:Connect(function()
		act("view")
	end)
	pad.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not touchAim and Controls.enabled then
			touchAim = input
		end
	end)
	Controls.buttons = buttons
	Controls.gui = gui

	UserInputService.InputBegan:Connect(function(input, processed)
		local t = input.UserInputType
		-- Studio phone emulation keeps the touch layout while the developer's mouse moves around.
		if t == Enum.UserInputType.Touch or (Settings.touch and workspace:GetAttribute("DevTouch")) then
			Controls.device = "touch"
		elseif
			t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.MouseMovement
		then
			Controls.device = "pc"
		elseif t.Name:find("Gamepad") then
			Controls.device = "gamepad"
		end
		if processed then
			return
		end
		local key = input.KeyCode
		if t == Enum.UserInputType.MouseButton1 then
			mouseDown = true
		elseif
			key == Enum.KeyCode.Space
			or key == Enum.KeyCode.LeftShift
			or key == Enum.KeyCode.ButtonB
			or key == Enum.KeyCode.ButtonL2
		then
			act("dash")
		elseif key == Enum.KeyCode.Q or key == Enum.KeyCode.ButtonY then
			act("overdrive")
		elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonX then
			act("evolve")
		elseif key == Enum.KeyCode.R then
			act("reload")
		elseif key == Enum.KeyCode.One or key == Enum.KeyCode.KeypadOne then
			act("card1")
		elseif key == Enum.KeyCode.Two or key == Enum.KeyCode.KeypadTwo then
			act("card2")
		elseif key == Enum.KeyCode.Three or key == Enum.KeyCode.KeypadThree then
			act("card3")
		elseif key == Enum.KeyCode.Four or key == Enum.KeyCode.KeypadFour then
			act("card4")
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then
			act("confirm")
		elseif key == Enum.KeyCode.DPadLeft then
			act("left")
		elseif key == Enum.KeyCode.DPadRight then
			act("right")
		elseif key == Enum.KeyCode.ButtonR2 then
			padFire = true
		elseif key == Enum.KeyCode.V or key == Enum.KeyCode.DPadUp or key == Enum.KeyCode.ButtonR3 then
			act("view")
		elseif key == Enum.KeyCode.P or key == Enum.KeyCode.ButtonStart then
			act("pause")
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input == touchAim then
			local center = pad.AbsolutePosition + pad.AbsoluteSize / 2
			touchVec = Vector2.new(input.Position.X, input.Position.Y) - center
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local v = Vector2.new(input.Position.X, -input.Position.Y)
			if v.Magnitude > 0.3 then
				Controls.padAim = v.Unit
			else
				Controls.padAim = nil
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == touchAim then
			touchAim = nil
			touchVec = Vector2.zero
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDown = false
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			padFire = false
		end
	end)
	UserInputService.WindowFocusReleased:Connect(Controls.release)
	GuiService.MenuOpened:Connect(function()
		Controls.release()
		act("menuOpened")
	end)
	GuiService.MenuClosed:Connect(function()
		act("menuClosed")
	end)
end

function Controls.release()
	mouseDown = false
	padFire = false
	touchAim = nil
	touchVec = Vector2.zero
	Controls.firing = false
	autoId = nil
	showMarker(nil)
end

-- Converts a screen-space direction (dx right, dy down) to a world XZ direction for our camera.
local function screenToWorld(v: Vector2): (number, number)
	local cam = workspace.CurrentCamera
	local right = cam.CFrame.RightVector
	local fwd = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	if fwd.Magnitude < 1e-3 then
		fwd = Vector3.zAxis
	end
	fwd = fwd.Unit
	local w = right * v.X - fwd * v.Y
	local m = math.sqrt(w.X * w.X + w.Z * w.Z)
	if m < 1e-4 then
		return Controls.aimX, Controls.aimZ
	end
	return w.X / m, w.Z / m
end

-- Call every frame while playing. rootPos = character root.
-- immersive = third/first-person view: aim follows the camera (fwdX/fwdZ), sticks/drag turn the camera
-- via Controls.look (read by CameraRig.processInput).
function Controls.update(
	rootPos: Vector3,
	canFire: boolean,
	range: number,
	immersive: boolean?,
	fwdX: number?,
	fwdZ: number?
)
	local now = os.clock()
	local dt = math.min(0.1, now - (Controls.lastUpdate or now))
	Controls.lastUpdate = now
	if workspace:GetAttribute("DevTouch") and game:GetService("RunService"):IsStudio() then
		Controls.device = "touch" -- Studio checks: the phone layout without the device emulator
	end
	local device = Controls.device
	if device == "touch" then
		layoutTouch()
	end
	gui.Enabled = Controls.enabled and device == "touch"
	UserInputService.MouseIconEnabled = not Controls.enabled or (device ~= "pc") or false
	if immersive and device == "pc" and Controls.enabled then
		UserInputService.MouseIconEnabled = false
	end
	Controls.look = nil
	local auto = device == "touch" and Settings.autoAim
	if not Controls.enabled or not auto then
		showMarker(nil)
	end
	local moved = if lastRoot then rootPos - lastRoot else Vector3.zero
	lastRoot = rootPos
	if not Controls.enabled then
		Controls.firing = false
		lastRoot = nil
		return
	end
	if immersive then
		local ax, az = fwdX or Controls.aimX, fwdZ or Controls.aimZ
		local firing = false
		if device == "pc" then
			local vs = workspace.CurrentCamera.ViewportSize
			Controls.cursor = Vector2.new(vs.X / 2, vs.Y / 2)
			firing = mouseDown
		elseif device == "touch" then
			local radius = pad.AbsoluteSize.X * 0.4
			local v = touchVec
			local clamped = if v.Magnitude > radius then v.Unit * radius else v
			knob.Position = UDim2.new(0.5, clamped.X, 0.5, clamped.Y)
			local active = touchAim ~= nil and v.Magnitude > radius * 0.2
			if active then
				Controls.look = Vector2.new(clamped.X / radius, -clamped.Y / radius)
			end
			firing = active
			if auto then
				-- the camera swings in behind the run while the right thumb leaves it alone
				local run = Vector2.new(moved.X, moved.Z)
				if not active and run.Magnitude > 0.05 and dt > 0 then
					local d = (math.atan2(run.X, run.Y) - math.atan2(fwdX or 0, fwdZ or 1) + math.pi) % (2 * math.pi)
						- math.pi
					if math.abs(d) < math.rad(150) then
						CameraRig.look(-d * math.min(1, dt * 0.9), 0)
					end
				end
				local hit
				Controls.aimX, Controls.aimZ, hit = autoAim(rootPos, Controls.aimX, Controls.aimZ, range, true, dt)
				Controls.firing = hit and canFire
				return
			end
		else
			Controls.look = Controls.padAim
			firing = padFire or Controls.padAim ~= nil
		end
		-- Gentle aim assist toward enemies near the crosshair line (not on mouse).
		if device ~= "pc" and Settings.aimAssist then
			local bx, bz = EnemyView.nearestInCone(rootPos.X, rootPos.Z, ax, az, range, math.cos(math.rad(8)))
			if bx then
				ax, az = bx, bz
			end
		end
		Controls.aimX, Controls.aimZ = ax, az
		Controls.firing = firing and canFire
		return
	end
	if device == "pc" then
		local mouse = UserInputService:GetMouseLocation()
		Controls.cursor = mouse
		local cam = workspace.CurrentCamera
		local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
		if math.abs(ray.Direction.Y) > 1e-3 then
			local t = (rootPos.Y - ray.Origin.Y) / ray.Direction.Y
			local hit = ray.Origin + ray.Direction * t
			local dx, dz = hit.X - rootPos.X, hit.Z - rootPos.Z
			local m = math.sqrt(dx * dx + dz * dz)
			if m > 0.5 then
				Controls.aimX, Controls.aimZ = dx / m, dz / m
			end
		end
		Controls.firing = mouseDown and canFire
	elseif device == "touch" then
		local radius = pad.AbsoluteSize.X * 0.4
		local v = touchVec
		local clamped = if v.Magnitude > radius then v.Unit * radius else v
		knob.Position = UDim2.new(0.5, clamped.X, 0.5, clamped.Y)
		local active = touchAim ~= nil and v.Magnitude > radius * 0.2
		if auto and not active then
			local hit
			Controls.aimX, Controls.aimZ, hit = autoAim(rootPos, Controls.aimX, Controls.aimZ, range, false, dt)
			Controls.firing = hit and canFire
			return
		end
		showMarker(nil)
		autoId = nil
		if active then
			local ax, az = screenToWorld(v)
			if Settings.aimAssist then
				local bx, bz = EnemyView.nearestInCone(rootPos.X, rootPos.Z, ax, az, range, math.cos(math.rad(16)))
				if bx then
					ax, az = bx, bz
				end
			end
			Controls.aimX, Controls.aimZ = ax, az
		end
		Controls.firing = active and canFire
	else
		if Controls.padAim then
			local ax, az = screenToWorld(Vector2.new(Controls.padAim.X, -Controls.padAim.Y))
			if Settings.aimAssist then
				local bx, bz = EnemyView.nearestInCone(rootPos.X, rootPos.Z, ax, az, range, math.cos(math.rad(12)))
				if bx then
					ax, az = bx, bz
				end
			end
			Controls.aimX, Controls.aimZ = ax, az
		end
		Controls.firing = (padFire or Controls.padAim ~= nil) and canFire
	end
end

function Controls.setButton(name: string, visible: boolean, cooldownFrac: number?, sub: string?, ready: boolean?)
	local b = buttons and buttons[name]
	if not b then
		return
	end
	b.button.Visible = visible
	b.fill.Size = UDim2.fromScale(1, math.clamp(cooldownFrac or 0, 0, 1))
	b.sub.Text = sub or ""
	b.button.BackgroundTransparency = if ready then 0.1 else 0.45
end

function Controls.setViewIcon(name: string)
	local b = buttons and buttons.view
	if not b then
		return
	end
	local old = b.button:FindFirstChild("Icon_" .. (b.iconName or "topdown"))
	if old and b.iconName == name then
		return
	end
	if old then
		old:Destroy()
	end
	b.iconName = name
	local ic = Icons.new(name, 26, b.color, C.panel)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.42)
	ic.Parent = b.button
end

function Controls.hideJumpButton()
	task.defer(function()
		local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local touchGui = pg and pg:FindFirstChild("TouchGui")
		local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
		if jump then
			jump.Visible = false
		end
	end)
end

return Controls
