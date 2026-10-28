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
local ActionButton = require(script.Parent.ActionButton)

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
	range = false, -- set by Main: the hero stands on the base's shooting range (DD-107)
	actions = {}, -- name -> callback
}

local mouseDown = false
local padFire = false
local touchAim: InputObject? = nil
local touchVec = Vector2.zero
local gui, pad, knob, buttons, padName
local touchLayoutSize = Vector2.zero
local tipAnchor = nil -- DD-107: where the first-time tip stands (left of the cluster), set by layoutTouch
local autoId = nil -- the enemy the touch auto-aim holds
local marker = nil -- the ring under it
local lastRoot = nil -- the hero's position last frame (his run turns the third-person camera)
local padSimple = nil -- the aim pad's look last laid out (DD-103: smaller and quieter in the simple fight)
local superTouch: InputObject? = nil -- DD-105: the finger on the super button
local superFrom = Vector2.zero
local superLine = nil -- the dragged super's aim line on the ground
local superLook = nil -- the weapon the super button is dressed for
local function showSuperLine(from: Vector3?, dx: number?, dz: number?, len: number?)
	if not from then
		if superLine then
			superLine.Parent = nil
		end
		return
	end
	if not superLine then
		superLine = Instance.new("Part")
		superLine.Name = "SuperAim"
		superLine.Anchored = true
		superLine.CanCollide = false
		superLine.CanQuery = false
		superLine.CanTouch = false
		superLine.CastShadow = false
		superLine.Material = Enum.Material.Neon
		superLine.Color = C.gold
		superLine.Transparency = 0.35
	end
	local l = len or 30
	local a = Vector3.new(from.X, from.Y - 2.6, from.Z)
	superLine.Size = Vector3.new(1.2, 0.12, l)
	superLine.CFrame = CFrame.lookAt(a, a + Vector3.new(dx, 0, dz)) * CFrame.new(0, 0, -l / 2)
	superLine.Parent = workspace
end

-- A screen drag (dx right, dy down) as a world XZ direction for the current camera.
local function screenToWorldDir(v: Vector2): (number, number)
	local cf = workspace.CurrentCamera.CFrame
	local fwd = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	fwd = if fwd.Magnitude < 1e-3 then Vector3.zAxis else fwd.Unit
	local w = cf.RightVector * v.X - fwd * v.Y
	local m = math.sqrt(w.X * w.X + w.Z * w.Z)
	if m < 1e-4 then
		return Controls.aimX, Controls.aimZ
	end
	return w.X / m, w.Z / m
end
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
-- DD-103: in the simple fight each gun picks its own kind of target (EnemyView.autoTargetFor).
local function autoAim(rootPos: Vector3, ax: number, az: number, range: number, front: boolean, dt: number)
	local id, tx, tz
	if Settings.simpleCombat and Controls.weapon then
		id, tx, tz = EnemyView.autoTargetFor(Controls.weapon, rootPos.X, rootPos.Z, range, ax, az, autoId)
	else
		id, tx, tz = EnemyView.autoTarget(rootPos.X, rootPos.Z, range, ax, az, autoId)
	end
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
-- DD-104: the buttons stand in an arc round the corner one (left of it and above), each named under it.
-- DD-106: in the simple fight the corner belongs to the super — the attack the player decides on —
-- and the aim pad is gone (the gun aims itself; a drag on the super aims the super). Over the shoulder
-- the corner stays the aim-and-fire pad and the super is next to it. Offsets for a 600-point-high
-- screen: { x, y, diameter }.
-- DD-107 (owner, phone: «кнопки боя занимают почти пол экрана — ближе к углу, ближе по дуге, меньше
-- основную»): the cluster is built round the corner one like the shooters on phones do it — the main
-- button about a quarter of the screen's height (Roblox's own jump button is 70 points on a phone), the
-- others about two thirds of it on one tight arc round it (left, up-left, up), all within the thumb's
-- reach from the corner; nothing under 48 points (the platforms' touch minimum). Angles in degrees,
-- counter-clockwise from "right" (180 = straight left, 90 = straight up).
local ARC_SIMPLE = { dash = 196, overdrive = 143, evolve = 90 }
local ARC_SHOULDER = { super = 186, dash = 148, overdrive = 100 } -- round the aim pad
local OUTER_SHOULDER = { evolve = 172, reload = 135, view = 100 } -- the second ring
local function layoutTouch()
	local size = workspace.CurrentCamera.ViewportSize
	if size == touchLayoutSize then
		return
	end
	touchLayoutSize = size
	local H = math.min(size.Y, size.X)
	local main = math.clamp(H * 0.25, 76, 128) -- the corner button
	local small = math.clamp(H * 0.16, 52, 84)
	local margin = math.clamp(H * 0.03, 10, 22)
	local captionRoom = 13 -- (the corner one's name hangs under it)
	local cx, cy = -(margin + main / 2), -(margin + captionRoom + main / 2)
	local function place(b, angle: number, radius: number, d: number)
		local a = math.rad(angle)
		b:setLayout(UDim2.new(1, cx + math.cos(a) * radius, 1, cy - math.sin(a) * radius), d)
	end
	local ring1 = main / 2 + small / 2 + math.max(12, small * 0.24)
	local ring2 = ring1 + small + math.max(10, small * 0.2)
	pad.Visible = not padSimple
	pad.Position = UDim2.new(1, cx, 1, cy)
	pad.Size = UDim2.fromOffset(main * 1.2, main * 1.2)
	knob.Size = UDim2.fromOffset(main * 0.45, main * 0.45)
	padName.Text = "ПРИЦЕЛ И ОГОНЬ"
	-- the first-time tip stands left of the whole cluster, on the bottom line (it named its button anyway)
	tipAnchor = UDim2.new(1, cx + math.cos(math.rad(196)) * ring1 - small / 2 - 10, 1, -(margin + 4))
	if padSimple then
		buttons.super:setLayout(UDim2.new(1, cx, 1, cy), main)
		for name, angle in ARC_SIMPLE do
			place(buttons[name], angle, ring1, small)
		end
		place(buttons.reload, 150, ring2, small * 0.85) -- (shown only out of the chase camera)
		place(buttons.view, 112, ring2, small * 0.85)
	else
		local r = main * 0.6 + small / 2 + 10
		for name, angle in ARC_SHOULDER do
			place(buttons[name], angle, r, if name == "super" then small * 1.15 else small)
		end
		for name, angle in OUTER_SHOULDER do
			place(buttons[name], angle, r + small + 10, small * 0.85)
		end
	end
end

-- DD-104: the first time a button shows up, a bubble beside it says what it does (one at a time).
local TIPS = {
	super = "СУПЕРУДАР — копится от урона; нажми — по цели, потяни — куда укажешь",
	dash = "РЫВОК — проскочить сквозь рой, в рывке не ранят",
	overdrive = "ГРОМОБОЙ — удар по всем вокруг, отбрасывает рой",
	evolve = "ЭВОЛЮЦИЯ — оружие становится сильнее навсегда до конца вылазки",
	reload = "ПЕРЕЗАРЯДКА — зарядить заранее, пока рядом нет врагов",
	view = "ВИД — сверху, из-за плеча или от первого лица",
}
local tipShown = {}
local tipQueue = {}
local tipUntil = 0
local calmSince = nil -- when the fight last became tip-worthy (Controls.tipsOk, set by Main)
local tipBubble, tipText, tipFor
local function queueTip(name: string)
	if tipShown[name] or not TIPS[name] then
		return
	end
	tipShown[name] = true
	table.insert(tipQueue, name)
end
local function stepTips(now: number)
	if not tipBubble then
		return
	end
	if tipFor and now < tipUntil and buttons[tipFor].button.Visible and gui.Enabled then
		return
	end
	tipFor = nil
	tipBubble.Visible = false
	-- only in the fight itself (no scene, no cards), and not in its first seconds
	calmSince = if Controls.tipsOk then calmSince or now else nil
	local name = tipQueue[1]
	if name and calmSince and now - calmSince > 2.5 and gui.Enabled and buttons[name].button.Visible then
		table.remove(tipQueue, 1)
		tipFor = name
		tipUntil = now + 5
		tipText.Text = TIPS[name]
		tipBubble.Parent = gui
		if tipAnchor then
			tipBubble.Position = tipAnchor
		end
		tipBubble.Visible = true
	end
end

local function act(name: string)
	local fn = Controls.actions[name]
	if fn then
		fn()
	end
end

-- DD-104: every touch button says what it is
local NAMES = {
	Super = "СУПЕРУДАР",
	Dash = "РЫВОК",
	Gravihammer = "ГРОМОБОЙ",
	Evolve = "ЭВОЛЮЦИЯ",
	Reload = "ПЕРЕЗАРЯДКА",
	View = "ВИД",
}

-- DD-106: every touch button is an ActionButton (ring of charge / cooldown, icon, count, caption)
local function makeButton(name: string, icon: string, color: Color3, big: boolean?)
	return ActionButton.new({
		name = name,
		icon = icon,
		color = color,
		caption = NAMES[name],
		big = big,
		parent = gui,
	})
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
	padName = Theme.label("", {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(120, 13),
		FontFace = Theme.F.head,
		TextSize = 10,
		TextColor3 = C.lime,
		Parent = pad,
	})
	new("UIStroke", { Color = C.ink, Thickness = 1.6, Transparency = 0.2, Parent = padName })
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
		super = makeButton("Super", "chain", C.gold, true),
		dash = makeButton("Dash", "dash", C.cyan),
		overdrive = makeButton("Gravihammer", "hammer", C.lime),
		evolve = makeButton("Evolve", "evolve", C.gold),
		reload = makeButton("Reload", "reload", C.dim),
		view = makeButton("View", "topdown", C.cyan),
	}
	-- DD-105: the super — a tap fires it at the gun's own target, a drag aims it (the line shows where)
	buttons.super.button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not superTouch and Controls.enabled then
			superTouch = input
			superFrom = Vector2.new(input.Position.X, input.Position.Y)
			Controls.superDir = nil
		end
	end)
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
	-- the first-time bubble: left of its button, pointing at it
	tipBubble = Theme.panel({
		Name = "Tip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -260, 1, -14),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		ZIndex = 5,
		CornerRadius = 12,
	}, C.lime)
	tipBubble.Parent = gui
	-- DD-107: a small two-line note beside the button, not a bar across the fight
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 9),
		PaddingRight = UDim.new(0, 9),
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
		Parent = tipBubble,
	})
	tipText = Theme.label("", {
		Size = UDim2.fromOffset(190, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.F.bodyBold,
		TextSize = 11,
		ZIndex = 6,
		Parent = tipBubble,
	})

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
		elseif
			key == Enum.KeyCode.E
			or key == Enum.KeyCode.ButtonR1
			or (t == Enum.UserInputType.MouseButton2 and Controls.enabled) -- DD-105: where the gun points
		then
			Controls.superDir = nil
			act("super")
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
		if input == superTouch then
			local v = Vector2.new(input.Position.X, input.Position.Y) - superFrom
			if v.Magnitude > 24 then
				Controls.superDir = Vector2.new(screenToWorldDir(v))
			end
		elseif input == touchAim then
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
		if input == superTouch then
			superTouch = nil
			showSuperLine(nil)
			act("super") -- Controls.superDir: the dragged way, or nil (the gun's own target)
			Controls.superDir = nil
		elseif input == touchAim then
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
	local simple = device == "touch" and Settings.simpleCombat == true
	if superTouch and Controls.superDir and Controls.enabled then
		showSuperLine(rootPos, Controls.superDir.X, Controls.superDir.Y, 30)
	else
		showSuperLine(nil)
	end
	if device == "touch" then
		if padSimple ~= simple then
			-- DD-103: in the simple fight the pad is only for aiming by hand now and then: smaller
			padSimple = simple
			touchLayoutSize = Vector2.zero
		end
		layoutTouch()
		buttons.view.button.Visible = not simple and not Controls.range -- (chase: the simple fight's only view)
		stepTips(now)
		for _, b in buttons do
			b:step(now)
		end
	end
	gui.Enabled = Controls.enabled and device == "touch"
	UserInputService.MouseIconEnabled = not Controls.enabled or (device ~= "pc") or false
	if immersive and device == "pc" and Controls.enabled then
		UserInputService.MouseIconEnabled = false
	end
	Controls.look = nil
	local auto = device == "touch" and (Settings.autoAim or simple)
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
			firing = active
			if active and not auto then
				-- DD-100 (owner: the first version was better, improve it): the pad turns the camera as it
				-- always did and the gun fires down the crosshair, with two aids a phone shooter needs.
				-- Friction: with an enemy right on the crosshair the turn slows down, so a thumb stays on
				-- it. Pull: while firing, the camera drifts toward the enemy nearest the crosshair.
				local look = Vector2.new(clamped.X / radius, -clamped.Y / radius)
				local cx, cz = fwdX or 0, fwdZ or 1
				if Settings.aimAssist then
					if EnemyView.nearestInCone(rootPos.X, rootPos.Z, cx, cz, range, math.cos(math.rad(6))) then
						look *= 0.5
					end
					local tx, tz = EnemyView.nearestInCone(rootPos.X, rootPos.Z, cx, cz, range, math.cos(math.rad(14)))
					if tx and dt > 0 then
						local d = (math.atan2(tx, tz) - math.atan2(cx, cz) + math.pi) % (2 * math.pi) - math.pi
						CameraRig.look(-d * math.min(1, dt * 3), 0)
					end
				end
				Controls.look = look
			end
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
			local cone = if device == "touch" then 12 else 8 -- DD-100: a thumb is coarser than a stick
			local bx, bz = EnemyView.nearestInCone(rootPos.X, rootPos.Z, ax, az, range, math.cos(math.rad(cone)))
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

-- cooldownFrac: the cooldown still to go (0..1); for the super, its charge. sub: the seconds left.
function Controls.setButton(name: string, visible: boolean, cooldownFrac: number?, sub: string?, ready: boolean?)
	local b = buttons and buttons[name]
	if not b then
		return
	end
	-- DD-107: the base's shooting range is the gun alone (the shelter's buttons hold the corner there)
	visible = visible and not Controls.range
	b.button.Visible = visible
	if visible then
		queueTip(name)
	end
	local f = math.clamp(cooldownFrac or 0, 0, 1)
	if name == "super" then
		b:set(f, nil, ready == true) -- (the ring is the charge; no number over the emblem)
	else
		b:set(1 - f, if f > 0 then sub else nil, f <= 0)
	end
end

-- DD-105: the super button wears the weapon's super (icon, short name, what it does).
function Controls.setSuperLook(key: string, icon: string, short: string, tip: string)
	local b = buttons and buttons.super
	if not b or superLook == key then
		return
	end
	superLook = key
	b:setIcon(icon)
	b.caption.Text = short
	TIPS.super = short .. " — " .. tip
end

-- DD-106: the super went off: the button's burst.
function Controls.superFired()
	if buttons and buttons.super then
		buttons.super:fire()
	end
end

function Controls.setViewIcon(name: string)
	local b = buttons and buttons.view
	if b then
		b:setIcon(name)
	end
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
