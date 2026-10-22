--!nonstrict
-- SWARMFALL client: wires remotes to presentation. Owns local feel (instant predicted shots, dash,
-- aim), while the server owns every outcome.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Codec = require(Shared:WaitForChild("Codec"))
local Maps = require(Shared:WaitForChild("Maps"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local Audio = require(script.Parent:WaitForChild("Audio"))
local EnemyView = require(script.Parent:WaitForChild("EnemyView"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Gear = require(script.Parent:WaitForChild("Gear"))
local CameraRig = require(script.Parent:WaitForChild("CameraRig"))
local Controls = require(script.Parent:WaitForChild("Controls"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local Preview = require(script.Parent:WaitForChild("Preview"))
local Menus = require(script.Parent:WaitForChild("Menus"))
local Rig = require(script.Parent:WaitForChild("Rig"))
local Shots = require(script.Parent:WaitForChild("Shots"))
local WeaponFeel = require(script.Parent:WaitForChild("WeaponFeel"))

local E, C = Codec.E, Theme.C
local player = Players.LocalPlayer
local myId = player.UserId
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inputRemote = remotes:WaitForChild(Codec.Remotes.Input)
local stateRemote = remotes:WaitForChild(Codec.Remotes.State)
local eventsRemote = remotes:WaitForChild(Codec.Remotes.Events)
local profileRemote = remotes:WaitForChild(Codec.Remotes.Profile)

local function send(action: string, ...)
	inputRemote:FireServer(action, ...)
end

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)
task.spawn(function()
	for _ = 1, 10 do
		if pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end) then
			break
		end
		task.wait(1)
	end
end)

Audio.init()
EnemyView.init()
Fx.init()
Hud.init(playerGui)
Controls.init(playerGui)
Menus.init(playerGui, send)
Shots.setHud(Hud)
Fx.setShellSound(function(pos, kind)
	if kind == "cellMag" then
		Audio.at("magOut", pos, 0.5, 0.6)
		return
	end
	Audio.at("shell", pos, if kind == "shell" then 0.6 else 0.9, if kind == "slug" then 0.7 else 1)
end)
-- Animation beats from the procedural rig (draw, cell out / in, bolt rack, evolution) -> sound + debris,
-- for every squad member, in sync with what the body is doing.
Rig.setEventHandler(function(character: Model, name: string, cf: CFrame?, feel)
	local cue = feel and feel.beats and feel.beats[name]
	if not cue then
		return
	end
	local isLocal = character == player.Character
	local root = character:FindFirstChild("HumanoidRootPart")
	if isLocal then
		Audio.play(cue)
	elseif root then
		Audio.at(cue, root.Position, 0.45)
	end
	if name == "magOut" and cf then
		Fx.shell(cf, "cellMag", Color3.new())
	end
end)

-- State -------------------------------------------------------------------------------------------
local mode = "LOBBY"
local run = nil
local me = nil
local votes = {}
local inRun = false
local decodeBuf = {}
local lastAimSent = { x = 0, z = 1, firing = false, t = 0 }
local fireAcc = 0
local lastLocalShot = 0
local dashUntil = 0
local dashDir = Vector3.zAxis
local linearVelocity: LinearVelocity? = nil
local orbCombo, orbComboT = 0, 0
local fps = 60
local debugExtra = {}
local pausedByMenu = false
local reactor = nil
local coilModels = {}
local lastCoilState = {}
local WEAPON_BY_INDEX = Defs.WeaponByIndex
local arenaMap = nil
local burrowDustT = 0
local lastFirstPerson = -1
local remoteBeams = {} -- pid -> { untilT, from, to, evolved }
local wasReloading = false
local localSpread = 0 -- predicted accuracy bloom (degrees), reconciled toward the server value
local dryClicked = false
-- Forearms and hands stay visible in first person (they hold the gun in front of the camera).
local FP_KEEP = { RightHand = true, LeftHand = true, RightLowerArm = true, LeftLowerArm = true, ["Right Arm"] = true, ["Left Arm"] = true }

local function findPlayerState(id: number)
	if not run then
		return nil
	end
	for _, p in run.players do
		if p.id == id then
			return p
		end
	end
	return nil
end

local function characterRoot(userId: number): BasePart?
	local pl = Players:GetPlayerByUserId(userId)
	local c = pl and pl.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function myRoot(): (BasePart?, Humanoid?)
	local c = player.Character
	if not c then
		return nil, nil
	end
	return c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

-- Character setup ---------------------------------------------------------------------------------
local function onCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid", 5)
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if not hum or not root then
		return
	end
	hum.AutoRotate = false
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	local att = Instance.new("Attachment")
	att.Name = "DashAttachment"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.MaxForce = 1e6
	lv.Enabled = false
	lv.Parent = root
	linearVelocity = lv
	lastFirstPerson = -1
	Controls.hideJumpButton()
	CameraRig.reset()
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- Actions -----------------------------------------------------------------------------------------
local function playing(): boolean
	return mode == "RUN" and run ~= nil and me ~= nil and me.alive and run.phase == "ACTIVE" and run.paused == ""
end

Controls.actions.dash = function()
	if not playing() or me.dash > 0 or os.clock() < dashUntil + 0.2 then
		return
	end
	local root, hum = myRoot()
	if not root or not hum then
		return
	end
	local dir = hum.MoveDirection
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(Controls.aimX, 0, Controls.aimZ)
	end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	dashDir = dir
	dashUntil = os.clock() + Defs.Player.DashTime
	send("dash", dir.X, dir.Z)
	if player.Character then
		Rig.dash(player.Character, dir.X, dir.Z, Defs.Player.DashTime)
	end
	Audio.play("dash")
	CameraRig.punch(6)
	for i = 0, 4 do
		local p = root.Position - dir * i * 1.5
		Fx.tracer(p - Vector3.yAxis, p - Vector3.yAxis + dir * 3, C.cyan, 0.6, 0.25)
	end
end
Controls.actions.overdrive = function()
	if playing() and me.od >= 100 then
		send("overdrive")
	end
end
Controls.actions.evolve = function()
	if playing() and me.canEvolve then
		send("evolve")
	end
end
Controls.actions.reload = function()
	if playing() then
		send("reload")
	end
end
Controls.actions.card1 = function()
	Menus.pick(1)
end
Controls.actions.card2 = function()
	Menus.pick(2)
end
Controls.actions.card3 = function()
	Menus.pick(3)
end
Controls.actions.card4 = function()
	Menus.pick(4)
end
Controls.actions.left = function()
	Menus.focusMove(-1)
end
Controls.actions.right = function()
	Menus.focusMove(1)
end
Controls.actions.confirm = function()
	Menus.confirm()
end
local function setPause(on: boolean)
	if mode == "RUN" and run and run.solo and me then
		pausedByMenu = on
		send("pause", on)
	end
end
Controls.actions.pause = function()
	if run and run.paused == "MENU" then
		setPause(false)
	elseif playing() then
		setPause(true)
	end
end
Controls.actions.menuOpened = function()
	if playing() then
		setPause(true)
	end
end
Controls.actions.menuClosed = function()
	if pausedByMenu then
		setPause(false)
	end
end
Hud.ui.evolve.Activated:Connect(Controls.actions.evolve)

-- Camera view cycling: top -> third person -> first person -> top, with a cinematic parameter blend.
Controls.actions.view = function()
	if mode ~= "RUN" or not me or not me.alive then
		return
	end
	local m = CameraRig.cycle(Controls.aimX, Controls.aimZ)
	Hud.setView(m, CameraRig.ModeIcons[m], CameraRig.ModeNames[m], Controls.device)
	Audio.play("dash", 0.6, 0.7)
end
Hud.ui.view.Activated:Connect(function()
	Controls.actions.view()
end)

-- Remotes -----------------------------------------------------------------------------------------
local function enterRun()
	inRun = true
	Menus.hideLobby()
	Menus.hideResults()
	Hud.setVisible(true)
	EnemyView.clear()
	Fx.clear()
	CameraRig.reset()
	table.clear(lastCoilState)
end

local function leaveRun()
	inRun = false
	run, me = nil, nil
	Hud.setVisible(false)
	Menus.hideOffer()
	Menus.hideResults()
	Menus.note(nil)
	EnemyView.clear()
	Fx.clear()
	table.clear(remoteBeams)
	Shots.beamStop("local", player.Character)
	Audio.loop("beam", Audio.Ids.whoosh, 0, 1)
	Controls.enabled = false
end

stateRemote.OnClientEvent:Connect(function(buf, info)
	if type(info) ~= "table" then
		return
	end
	if info.mode == "LOBBY" then
		if inRun then
			leaveRun()
		end
		mode = "LOBBY"
		Menus.showLobby(info.lobby, myId, Controls.device)
		return
	end
	mode = "RUN"
	if not inRun then
		enterRun()
	end
	run = info.run
	votes = info.votes or {}
	me = findPlayerState(myId)
	debugExtra.simMs = info.simMs
	debugExtra.rejected = info.rejected
	if typeof(buf) == "buffer" then
		local n = Codec.decodeEnemies(buf, decodeBuf)
		EnemyView.snapshot(decodeBuf, n)
	end
	if me and me.offer and me.alive and run.phase == "ACTIVE" then
		Menus.showOffer(me, run)
	else
		Menus.hideOffer()
	end
	if run.result then
		Menus.showResults(run.result, votes, myId, info.rewards and info.rewards[tostring(myId)])
		Hud.setVisible(false)
	end
	if run.phase == "COUNTDOWN" then
		Menus.note(string.format("ВЫСАДКА: %s  ·  %d", Maps.get(run.map).name, math.ceil(run.countdown)))
	elseif not me then
		Menus.note("НАБЛЮДЕНИЕ · ВЫ ВОЙДЁТЕ В СЛЕДУЮЩИЙ ЗАБЕГ")
	elseif not me.alive and not run.result then
		Menus.note("ВЫ ПОВЕРЖЕНЫ · НАБЛЮДАЕТЕ ЗА ОТРЯДОМ")
	elseif run.paused == "MENU" then
		Menus.note("ПАУЗА · НАЖМИТЕ P ИЛИ ЗАКРОЙТЕ МЕНЮ")
	elseif run.paused == "CHOOSE" and me and not me.offer then
		Menus.note("ОТРЯД ВЫБИРАЕТ УЛУЧШЕНИЯ…")
	else
		Menus.note(nil)
	end
end)

local function nearMe(pos: Vector3, radius: number): boolean
	local root = myRoot()
	return root ~= nil and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < radius
end

local KILL_GOO = { "goo1", "goo2", "goo3", "goo4", "goo5", "goo6", "goo7" }
local SPLAT_COLOR = {
	Color3.fromRGB(110, 40, 20),
	Color3.fromRGB(70, 30, 90),
	Color3.fromRGB(80, 120, 30),
	Color3.fromRGB(40, 50, 70),
	Color3.fromRGB(120, 90, 30),
	Color3.fromRGB(60, 30, 70),
	Color3.fromRGB(70, 110, 30),
}

local handlers = {}
local function characterOf(userId: number): Model?
	local pl = Players:GetPlayerByUserId(userId)
	return pl and pl.Character
end

handlers[E.SHOT] = function(pid, ox, oz, ex, ez, wIndex, evolved)
	if pid == myId then
		return
	end
	local weapon = WEAPON_BY_INDEX[wIndex] or "W_ARC_RIFLE"
	Shots.remote(pid, characterOf(pid), weapon, evolved == 1, ox, oz, ex, ez, Defs.Weapons[weapon].range)
end
handlers[E.DMG] = function(id, amount, flags, fromX, fromZ)
	EnemyView.flash(id, fromX, fromZ, amount)
	local pos = EnemyView.position(id)
	if not pos then
		return
	end
	local rec = EnemyView.records[id]
	if rec and fromX and amount >= 8 and Settings.quality >= 2 and math.random() < 0.6 then
		-- goo spatters out the far side of the wound
		local d = Vector3.new(pos.X - fromX, 0, pos.Z - fromZ)
		if d.Magnitude > 0.01 then
			Fx.emit(KILL_GOO[rec.kind] or "goo1", pos, 2, (d.Unit + Vector3.yAxis * 0.8).Unit)
		end
	end
	local crit = bit32.band(flags, Codec.DF.CRIT) ~= 0
	local armor = bit32.band(flags, Codec.DF.ARMOR) ~= 0
	local burn = bit32.band(flags, Codec.DF.BURN) ~= 0
	if crit or amount >= 8 or Settings.quality >= 3 then
		local color = if crit then C.gold elseif armor then C.dim elseif burn then C.orange else C.text
		Fx.number(pos, amount, color, crit)
	end
	if os.clock() - lastLocalShot < 0.3 then
		Hud.hitmarker(false)
	end
	if crit then
		Audio.at("crit", pos, 0.7)
	elseif armor then
		Audio.at("armorHit", pos, 0.8)
		if fromX and Settings.quality >= 2 then
			local back = Vector3.new(fromX - pos.X, 0, fromZ - pos.Z)
			if back.Magnitude > 0.01 then
				Fx.emit("hitOrange", pos + Vector3.yAxis, 4, (back.Unit + Vector3.yAxis * 0.7).Unit)
			end
		end
	else
		Audio.at("hit", pos, 0.6)
	end
	if burn and Settings.quality >= 3 and math.random() < 0.3 then
		Fx.emit("fire", pos, 1)
	end
end
handlers[E.KILL] = function(id, kind, x, z, killer, cause, fromX, fromZ)
	local dir = nil
	if fromX then
		local d = Vector3.new(x - fromX, 0, z - fromZ)
		if d.Magnitude > 0.01 then
			dir = d.Unit
		end
	end
	local pos = EnemyView.kill(id, dir and dir.X, dir and dir.Z) or Vector3.new(x, 1, z)
	if cause == 9 then
		Fx.emit("smoke", pos, 8)
		return
	end
	local spray = if dir then (dir + Vector3.yAxis * 1.1).Unit else nil
	Fx.emit(KILL_GOO[kind] or "goo1", pos + Vector3.yAxis, if kind >= 4 then 30 else 14, spray)
	if Settings.quality >= 2 then
		Fx.emit("dust", pos, if kind >= 4 then 4 else 1)
	end
	Fx.splat(pos, SPLAT_COLOR[kind] or SPLAT_COLOR[1], if kind >= 4 then 9 else 4.5)
	if kind >= 4 then
		Fx.boom(pos, if kind == 7 then 20 elseif kind == 5 then 12 else 7, Theme.Code[if kind == 6 then 5 else 2])
		Audio.at("killBig", pos, 1)
		if nearMe(pos, 60) then
			CameraRig.shake(if kind >= 5 then 0.6 else 0.3)
		end
	else
		Audio.at("kill", pos, 0.8)
	end
	if killer == myId then
		Hud.hitmarker(true)
	end
end
handlers[E.ARC] = function(x1, z1, x2, z2, color)
	local a, b = Vector3.new(x1, 2.6, z1), Vector3.new(x2, 2.6, z2)
	if color == Codec.C.WHITE then
		-- ricochet: a hot round zips off the first target into the next
		Fx.emit("hitWhite", a, 3, (b - a).Unit)
		Fx.projectile(a, b, Color3.fromRGB(255, 240, 200), 0.16, 260, 4, function()
			Fx.emit("hitWhite", b, 3, (a - b).Unit)
		end)
		Audio.at("ricochet", a, 0.5)
	else
		local c = Theme.Code[color] or C.cyan
		Fx.lightning(a, b, c, if color == Codec.C.BLUE then 0.32 else 0.22, 0.17)
		Fx.emit("hitCyan", b, 4)
		Fx.light(b, c, 12, 0.1)
		Audio.at("arc", a, 0.7)
	end
end
handlers[E.BOOM] = function(x, z, r, color)
	local pos = Vector3.new(x, 1, z)
	Fx.boom(pos, r, Theme.Code[color] or C.orange)
	Audio.at("boom", pos, math.clamp(r / 12, 0.4, 1))
	if nearMe(pos, r + 20) then
		CameraRig.shake(math.clamp(r / 40, 0.08, 0.4))
	end
end
handlers[E.TELE] = function(shape, x, z, dx, dz, a, b, duration, color, activeTime)
	Fx.telegraph(shape, x, z, dx, dz, a, b, duration, Theme.Code[color] or C.red, activeTime or 0)
	if nearMe(Vector3.new(x, 0, z), 45) then
		Audio.play("warn", 0.6)
	end
end
handlers[E.ORB] = function(id, x, z, kind, value)
	Fx.orb(id, x, z, kind, value)
end
handlers[E.ORB_GET] = function(id, pid)
	Fx.collectOrb(id, function()
		local r = characterRoot(pid)
		return r and r.Position
	end)
	if pid == myId then
		local now = os.clock()
		orbCombo = if now - orbComboT < 0.6 then math.min(orbCombo + 1, 14) else 0
		orbComboT = now
		Audio.play("orb", 1, 1 + orbCombo * 0.06)
	end
end
handlers[E.HURT] = function(pid, amount, fx, fz)
	local char = characterOf(pid)
	if char then
		Rig.flinch(char, fx, fz, math.clamp(amount / 15, 0.5, 1.5))
	end
	local root = characterRoot(pid)
	if root then
		Fx.number(root.Position + Vector3.yAxis * 2, amount, C.red, false)
	end
	if pid == myId then
		Hud.hurt()
		CameraRig.shake(0.35)
		Audio.play("hurt")
	end
end
handlers[E.BANNER] = function(text, sub, color, duration, visual)
	Hud.banner(text, sub, Theme.Code[color] or C.cyan, duration, visual)
end
handlers[E.DASH] = function(pid, x, z, dx, dz)
	if pid ~= myId then
		Audio.at("dash", Vector3.new(x, 0, z), 0.5)
		local char = characterOf(pid)
		if char then
			Rig.dash(char, dx, dz, Defs.Player.DashTime)
		end
	end
end
handlers[E.OVERDRIVE] = function(pid, x, z)
	local pos = Vector3.new(x, 1, z)
	Fx.shockwave(pos, Defs.Overdrive.BlastRadius, C.gold, 0.5)
	Audio.at("overdrive", pos, 1)
	if pid == myId then
		CameraRig.punch(14)
		CameraRig.shake(0.5)
		Menus.whiteFlash(0.25)
	end
end
handlers[E.EVOLVE] = function(pid, evoId)
	local char = characterOf(pid)
	if char then
		Rig.evolve(char)
	end
	local root = characterRoot(pid)
	if root then
		Fx.shockwave(root.Position, 22, C.gold, 0.8)
		Fx.emit("sparkGold", root.Position, 60)
	end
	Audio.play("evolve")
	if pid == myId then
		Menus.evolveSplash(evoId)
		CameraRig.closeUp(1.4)
		CameraRig.shake(0.6)
	end
end
handlers[E.CORE] = function(x, z, pid)
	local pos = Vector3.new(x, 2, z)
	Fx.emit("sparkGold", pos, 50)
	Fx.shockwave(pos, 14, C.gold, 0.6)
end
handlers[E.COIL] = function(index)
	local c = Maps.get(run and run.map).coils[index]
	if c then
		local pos = Vector3.new(c.x, 1, c.z)
		Fx.shockwave(pos, Defs.Coil.Range, C.cyan, 0.45)
		Audio.at("coil", pos, 1)
		Fx.light(pos + Vector3.yAxis * 10, C.cyan, 60, 0.4)
		if nearMe(pos, 60) then
			CameraRig.shake(0.3)
		end
	end
end
handlers[E.LEVEL] = function()
	local root = myRoot()
	if root then
		Fx.shockwave(root.Position, 10, C.cyan, 0.4)
	end
end
handlers[E.MAGNET] = function(pid)
	for id in Fx.orbIds() do
		Fx.collectOrb(id, function()
			local r = characterRoot(pid)
			return r and r.Position
		end)
	end
	if pid == myId then
		Audio.play("heal", 1, 1.6)
	end
end
handlers[E.HEAL] = function(pid, amount)
	local root = characterRoot(pid)
	if root then
		Fx.number(root.Position + Vector3.yAxis * 2, amount, C.lime, true)
	end
	if pid == myId then
		Audio.play("heal")
	end
end
handlers[E.SHIELD] = function(pid)
	if pid == myId then
		Audio.play("heal", 0.8, 0.8)
	end
end
handlers[E.BEAM] = function(pid, ox, oz, ex, ez, evolved)
	if pid ~= myId then
		remoteBeams[pid] = { untilT = os.clock() + 0.2, to = Vector3.new(ex, 3, ez), from = Vector3.new(ox, 3, oz), evolved = evolved == 1 }
	end
end
handlers[E.BOSS] = function(action)
	if action == 5 then
		Audio.play("roar", 0.7, 0.6)
		CameraRig.shake(0.5)
	elseif action == 1 or action == 3 then
		Audio.play("roar")
		CameraRig.shake(0.9)
	elseif action == 2 then
		Audio.play("crit", 1, 0.6)
	elseif action == 4 then
		Audio.play("roar", 1, 1.4)
		CameraRig.shake(1)
		Menus.whiteFlash(0.6)
	end
end
handlers[E.SPIT] = function(fx, fz, tx, tz, flight)
	Fx.spit(Vector3.new(fx, 3, fz), Vector3.new(tx, 0.5, tz), flight)
	Audio.at("spit", Vector3.new(fx, 0, fz), 0.7)
end

eventsRemote.OnClientEvent:Connect(function(list)
	if not inRun or type(list) ~= "table" then
		return
	end
	for _, ev in list do
		local h = handlers[ev[1]]
		if h then
			local ok, err = pcall(h, table.unpack(ev, 2))
			if not ok and RunService:IsStudio() then
				warn("[SWARMFALL] fx handler", ev[1], err)
			end
		end
	end
end)

profileRemote.OnClientEvent:Connect(function(pub)
	if type(pub) == "table" then
		Menus.setProfile(pub)
	end
end)
send("profile")

-- Local shot prediction ------------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
task.spawn(function()
	local arena = workspace:WaitForChild("Arena", 30)
	if arena then
		rayParams.FilterDescendantsInstances = { arena:WaitForChild("Solid") }
		CameraRig.setCollision(arena:WaitForChild("Solid"))
	end
end)

-- Predicts one round against rendered enemies + arena walls. pierce > 0 collects every enemy along
-- the line (railgun). Returns a Shots item: { to, hits = {{pos, id}}, wall, normal }.
local function predictShot(origin: Vector3, dx: number, dz: number, range: number, pierce: number)
	local wall = workspace:Raycast(Vector3.new(origin.X, 3, origin.Z), Vector3.new(dx, 0, dz) * range, rayParams)
	local maxD = if wall then wall.Distance else range
	local item = {}
	local d = maxD
	local hitList
	if pierce > 0 then
		hitList = EnemyView.raycastAll(origin.X, origin.Z, dx, dz, maxD, pierce + 1)
		if #hitList > pierce then
			d = hitList[#hitList].d
		end
	else
		local hitD, rec = EnemyView.raycast(origin.X, origin.Z, dx, dz, maxD)
		hitList = if hitD then { { d = hitD, rec = rec } } else {}
		if hitD then
			d = hitD
		end
	end
	if #hitList > 0 then
		item.hits = {}
		for _, h in hitList do
			local y = math.min(origin.Y, h.rec.radius + 0.8)
			table.insert(item.hits, { pos = Vector3.new(origin.X + dx * h.d, y, origin.Z + dz * h.d), id = h.rec.id })
		end
	end
	local endY = if item.hits and d < maxD then item.hits[#item.hits].pos.Y else origin.Y
	item.to = Vector3.new(origin.X + dx * d, endY, origin.Z + dz * d)
	if wall and d >= maxD - 0.01 then
		item.wall = true
		item.normal = wall.Normal
	end
	return item
end

local function localFire(dt: number)
	local char = player.Character
	local wdef = Defs.Weapons[me.weapon]
	local evolved = me.evolved ~= ""
	local root = myRoot()
	if not root then
		return
	end
	local muzzle = (char and Rig.muzzle(char)) or (root.Position + Vector3.new(Controls.aimX, 0.8, Controls.aimZ) * 3)
	local range = wdef.range * (if me.evolved == "EV_VOID_LANCE" then 1.4 else 1)
	if wdef.kind == "beam" then
		local active = Controls.firing and not me.overheated
		if active then
			local item = predictShot(muzzle, Controls.aimX, Controls.aimZ, range, 0)
			Shots.beam("local", char, me.weapon, evolved, muzzle, item.to, item.hits ~= nil, true)
			lastLocalShot = os.clock()
		else
			Shots.beamStop("local", char)
		end
		Audio.loop("beam", Audio.Ids.whoosh, if active then 0.28 else 0, if evolved then 1.3 else 1.8)
		return
	end
	local bloomy = wdef.bloom ~= nil
	if bloomy then
		-- mirror the server's accuracy bloom locally so the reticle and tracers react instantly
		local srv = me.spread or wdef.spreadMin
		if not Controls.firing or me.reload > 0 then
			localSpread = math.max(wdef.spreadMin, localSpread - wdef.recover * dt)
		end
		localSpread += (srv - localSpread) * math.min(1, dt * 2)
		localSpread = math.clamp(localSpread, wdef.spreadMin, wdef.spreadMax)
	end
	if Controls.firing and me.ammo <= 0 and me.reload <= 0 then
		local feel = WeaponFeel.get(me.weapon, evolved)
		if feel.dry and not dryClicked then
			dryClicked = true
			Audio.play(feel.dry)
		end
	elseif not Controls.firing then
		dryClicked = false
	end
	if not Controls.firing or me.reload > 0 or me.ammo <= 0 then
		fireAcc = math.max(0, fireAcc - dt)
		return
	end
	fireAcc -= dt
	local guard = 0
	local predictedAmmo = me.ammo
	while fireAcc <= 0 and guard < 3 do
		guard += 1
		fireAcc += 1 / math.max(0.5, me.rate)
		lastLocalShot = os.clock()
		local base = math.atan2(Controls.aimX, Controls.aimZ)
		local items = {}
		local multi = me.multi or 0
		if wdef.kind == "shotgun" then
			local pellets = wdef.pellets + (if me.evolved == "EV_INFERNO_GRINDER" then 4 else 0)
			local half = math.rad(wdef.spread) / 2
			for _ = 1, pellets do
				local a = base + (math.random() * 2 - 1) * half
				table.insert(items, predictShot(muzzle, math.sin(a), math.cos(a), range * (0.85 + math.random() * 0.15), 0))
			end
			for k = 1, multi do
				-- Расщепление: side clusters just outside the cone (same rule as the server)
				local side = if k % 2 == 1 then 1 else -1
				local center = base + side * (math.rad(wdef.spread) / 2 + math.rad(6))
				for _ = 1, 3 do
					local a = center + (math.random() * 2 - 1) * 0.12
					table.insert(items, predictShot(muzzle, math.sin(a), math.cos(a), range * 0.9, 0))
				end
			end
		else
			local cone = if bloomy then localSpread else wdef.spread
			local a = base + (math.random() * 2 - 1) * math.rad(cone) / 2
			local pierce = if wdef.kind == "rail" then wdef.pierce + (if evolved then 7 else 0) else (me.pierce or 0)
			table.insert(items, predictShot(muzzle, math.sin(a), math.cos(a), range, pierce))
			for k = 1, multi do
				-- Расщепление: side rounds at ±9° steps (same rule as the server)
				local side = if k % 2 == 1 then 1 else -1
				local sa = base + side * math.rad(9) * math.ceil(k / 2)
				table.insert(items, predictShot(muzzle, math.sin(sa), math.cos(sa), range * 0.9, pierce))
			end
			if bloomy then
				localSpread = math.min(wdef.spreadMax, localSpread + wdef.bloom)
			end
		end
		predictedAmmo -= 1
		Shots.fire(char, me.weapon, evolved, muzzle, items, true, false, predictedAmmo / math.max(1, me.mag))
	end
end

-- Arena animation -------------------------------------------------------------------------------------
local animated = nil -- { rings = {{part, baseCF, index}}, core = part?, heart = part? }
local function animateArena(now: number)
	local arena = workspace:FindFirstChild("Arena")
	local currentMap = arena and arena:GetAttribute("Map")
	if currentMap ~= arenaMap or not animated then
		local decor = arena and arena:FindFirstChild("Decor")
		if not decor then
			return
		end
		arenaMap = currentMap
		local solid = arena:FindFirstChild("Solid")
		if solid then
			rayParams.FilterDescendantsInstances = { solid }
			CameraRig.setCollision(solid)
		end
		table.clear(coilModels)
		table.clear(lastCoilState)
		animated = { rings = {} }
		local reactorModel = decor:FindFirstChild("Reactor")
		if reactorModel then
			for _, r in reactorModel:GetChildren() do
				if r.Name:find("HaloRing") then
					table.insert(animated.rings, { r, r.CFrame, tonumber(r.Name:sub(-1)) or 1 })
				elseif r.Name == "Core" then
					animated.core = r
				end
			end
		end
		animated.heart = decor:FindFirstChild("Heart")
		for i = 1, 4 do
			coilModels[i] = decor:FindFirstChild("Coil" .. i)
		end
	end
	for _, ring in animated.rings do
		local i = ring[3]
		ring[1].CFrame = ring[2] * CFrame.new(math.sin(now * 1.3 + i) * 0.4, 0, 0) * CFrame.Angles(now * (0.4 + i * 0.25) * (if i % 2 == 0 then -1 else 1), 0, 0)
	end
	if animated.core then
		animated.core.Transparency = 0.35 + (math.sin(now * 2.5) + 1) * 0.08
	end
	if animated.heart then
		local k = (math.sin(now * 3) + 1) / 2
		animated.heart.Size = Vector3.one * (4.6 + k * 0.9)
		animated.heart.Transparency = 0.05 + k * 0.2
	end
	if run then
		for i, model in coilModels do
			local cd = run.coils[i] or 0
			local ready = cd <= 0
			local state = if ready then "ready" else "cd"
			if lastCoilState[i] ~= state then
				lastCoilState[i] = state
				for _, p in model:GetDescendants() do
					if p:IsA("BasePart") and (p.Name == "Ring" or p.Name == "Orb" or p.Name == "Pad") then
						p.Color = if ready then C.cyan else Color3.fromRGB(60, 70, 85)
					elseif p:IsA("PointLight") then
						p.Enabled = ready
					end
				end
			end
			if ready then
				local pad = model:FindFirstChild("Pad")
				if pad then
					pad.Transparency = 0.55 + math.sin(now * 5 + i) * 0.2
				end
			end
		end
	end
end

-- Off-screen arrows -----------------------------------------------------------------------------------
local arrowList = {}
local function computeArrows(cam: Camera)
	table.clear(arrowList)
	local size = cam.ViewportSize
	local margin = 46
	local function add(pos: Vector3, color: Color3, text: string)
		if #arrowList >= 6 then
			return
		end
		local v, onScreen = cam:WorldToViewportPoint(pos)
		if onScreen and v.X > margin and v.X < size.X - margin and v.Y > margin and v.Y < size.Y - margin then
			return
		end
		local cx, cy = size.X / 2, size.Y / 2
		local dx, dy = v.X - cx, v.Y - cy
		if v.Z < 0 then
			dx, dy = -dx, -dy
		end
		local m = math.max(math.abs(dx) / (cx - margin), math.abs(dy) / (cy - margin), 1e-3)
		table.insert(arrowList, { x = cx + dx / m, y = cy + dy / m, rot = math.deg(math.atan2(dy, dx)) + 90, color = color, text = text })
	end
	for _, rec in EnemyView.records do
		if rec.kind == 7 or rec.kind == 9 then
			add(Vector3.new(rec.dx, 6, rec.dz), C.red, "БОСС")
		elseif rec.kind == 5 then
			add(Vector3.new(rec.dx, 4, rec.dz), C.gold, "ЭЛИТА")
		elseif rec.kind == 6 then
			add(Vector3.new(rec.dx, 4, rec.dz), C.lime, "ГНЕЗДО")
		end
	end
end

-- Main loop ---------------------------------------------------------------------------------------
Settings.onChanged(function(key, value)
	if key == "quality" then
		local bloom = Lighting:FindFirstChild("Bloom")
		if bloom then
			bloom.Enabled = value >= 2
		end
		Lighting.GlobalShadows = value >= 3
	end
end)

local function frame(dt: number)
	local now = os.clock()
	fps += (1 / math.max(dt, 1e-3) - fps) * 0.05
	local cam = workspace.CurrentCamera
	local root, hum = myRoot()
	local isPlaying = playing()
	local choosing = Menus.offerVisible()
	Controls.enabled = isPlaying and not choosing
	-- Camera look input first (mouse-look / stick-look in third & first person), then aim.
	CameraRig.processInput(dt, Controls.device, isPlaying and not choosing and mode == "RUN", Controls.look)
	local immersive = CameraRig.immersive() and isPlaying
	local fx, fz = CameraRig.forward()
	if root then
		local range = if me then Defs.Weapons[me.weapon].range else 60
		Controls.update(root.Position, isPlaying and not choosing, range, immersive, fx, fz)
	else
		Controls.update(Vector3.zero, false, 60)
	end

	-- Movement & facing
	if hum then
		local frozen = not isPlaying or choosing
		hum.WalkSpeed = if frozen then 0 else Defs.Player.Speed
	end
	if root and linearVelocity then
		local dashing = now < dashUntil and isPlaying
		linearVelocity.Enabled = dashing
		if dashing then
			linearVelocity.PlaneVelocity = Vector2.new(dashDir.X, dashDir.Z) * (Defs.Player.DashDistance / Defs.Player.DashTime)
		end
	end
	if root and isPlaying then
		local look = Vector3.new(Controls.aimX, 0, Controls.aimZ)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	end

	-- Aim replication (20 Hz or on change)
	if isPlaying or lastAimSent.firing then
		local firing = Controls.firing and isPlaying
		local dot = Controls.aimX * lastAimSent.x + Controls.aimZ * lastAimSent.z
		if firing ~= lastAimSent.firing or (now - lastAimSent.t > 0.05 and dot < 0.9995) or now - lastAimSent.t > 0.5 then
			send("aim", Controls.aimX, Controls.aimZ, firing)
			lastAimSent.x, lastAimSent.z, lastAimSent.firing, lastAimSent.t = Controls.aimX, Controls.aimZ, firing, now
		end
	end

	-- Gear for every squad member
	if run then
		for _, p in run.players do
			local pl = Players:GetPlayerByUserId(p.id)
			local char = pl and pl.Character
			if char then
				local rig = Gear.ensure(char, p.weapon, p.evolved ~= "", p.id == myId)
				if rig then
					Gear.update(rig, p.odT > 0, p.shield, not p.alive)
					local beamKind = Defs.Weapons[p.weapon].kind == "beam"
					Rig.setState(char, p.alive, if p.reload > 0 then p.reload elseif beamKind and p.overheated then 0.5 else 0, p.ammo / math.max(1, p.mag), p.reloadEmpty)
					if p.id == myId then
						local reloading = p.reload > 0
						if reloading and not wasReloading and not WeaponFeel.get(p.weapon, false).beats then
							Audio.play("reload") -- weapons with animation beats voice their own reload
						end
						wasReloading = reloading
						if isPlaying and not choosing then
							localFire(dt)
						else
							Shots.beamStop("local", char)
							Audio.loop("beam", Audio.Ids.whoosh, 0, 1)
						end
					else
						local rb = remoteBeams[p.id]
						if rb and now < rb.untilT and p.alive then
							Shots.beam(p.id, char, "W_PLASMA_BEAM", rb.evolved, rb.from, rb.to, false, false)
						elseif rb then
							remoteBeams[p.id] = nil
							Shots.beamStop(p.id, char)
						end
					end
				end
			end
		end
		Gear.cleanup()
	end

	-- Camera
	if mode == "RUN" and run then
		local focus = nil
		if root and me and me.alive then
			focus = root.Position
		else
			for _, p in run.players do
				if p.alive then
					local r = characterRoot(p.id)
					if r then
						focus = r.Position
						break
					end
				end
			end
		end
		local lead = if Controls.device == "pc" then 1 else 0.6
		local spectating = not (me and me.alive)
		CameraRig.update(dt, "play", focus, Controls.aimX, Controls.aimZ, if isPlaying then lead else 0, spectating)
		-- First person: fade the own body out as the camera slides into the head (gear stays visible).
		local fp = CameraRig.firstPersonAmount()
		-- Re-apply while in first person: accessories can stream in after the switch.
		if (fp ~= lastFirstPerson or fp > 0) and player.Character then
			lastFirstPerson = fp
			for _, d in player.Character:GetDescendants() do
				if d:IsA("BasePart") and not d:FindFirstAncestor("SwarmGear") then
					d.LocalTransparencyModifier = if FP_KEEP[d.Name] then 0 else fp
				end
			end
		end
		if focus then
			Audio.setFocus(focus)
		end
	else
		CameraRig.update(dt, "lobby", nil, 0, 1, 0)
	end

	-- Overdrive grade
	local grade = Lighting:FindFirstChild("Grade")
	if grade then
		local od = me and me.odT > 0
		local low = me and me.alive and me.hp / me.maxHp < 0.3
		grade.Saturation = if od then 0.45 elseif low then -0.25 else 0.12
		grade.TintColor = if od then Color3.fromRGB(255, 240, 215) else Color3.fromRGB(232, 244, 255)
	end

	animateArena(now)
	burrowDustT -= dt
	if burrowDustT <= 0 then
		burrowDustT = 0.08
		for _, rec in EnemyView.records do
			if rec.kind == 9 and rec.state == Codec.State.IDLE then
				Fx.emit("smoke", Vector3.new(rec.dx, 0.5, rec.dz), 2)
				Fx.emit("goo7", Vector3.new(rec.dx, 0.5, rec.dz), 2)
			end
		end
	end
	EnemyView.update(dt, cam.CFrame.Position)
	Fx.update(dt)
	Menus.update(dt)

	if run and me then
		computeArrows(cam)
		local extra = {
			arrows = arrowList,
			cursor = if immersive then Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2) elseif Controls.device == "pc" then Controls.cursor else nil,
			showReticle = (Controls.device == "pc" or immersive) and isPlaying and not choosing,
			device = Controls.device,
			spread = localSpread,
			debug = if RunService:IsStudio() then string.format("%.0f FPS  ·  %d ENEMIES  ·  SIM %.2fms  ·  REJ %s  ·  FX %d", fps, EnemyView.count(), debugExtra.simMs or 0, tostring(debugExtra.rejected or 0), Fx.stats().live) else nil,
		}
		Hud.update(run, me, extra, dt)
		Hud.setView(CameraRig.mode(), CameraRig.ModeIcons[CameraRig.mode()], nil, Controls.device)
		Controls.setViewIcon(CameraRig.ModeIcons[CameraRig.mode()])
		-- Touch buttons
		Controls.setButton("dash", true, me.dash / Defs.Player.DashCooldown, if me.dash > 0 then string.format("%.1f", me.dash) else "", me.dash <= 0)
		Controls.setButton("overdrive", true, 1 - me.od / 100, if me.odT > 0 then string.format("%.0f", me.odT) else me.od .. "%", me.od >= 100)
		Controls.setButton("evolve", me.canEvolve, 0, "READY", true)
		Controls.setButton("reload", Defs.Weapons[me.weapon].kind ~= "beam", 0, "", false)
	elseif run then
		local extra = { arrows = {}, showReticle = false, device = Controls.device }
		Hud.update(run, nil, extra, dt)
	end
end
RunService:BindToRenderStep("SwarmMain", Enum.RenderPriority.Camera.Value + 1, frame)
if RunService:IsStudio() then
	-- Lets automated Studio tests step a client frame when the viewport is not rendering.
	local hook = Instance.new("BindableFunction")
	hook.Name = "SwarmFrameHook"
	hook.OnInvoke = function(dt, aimX, aimY, autoPick, action)
		if aimX then
			Controls.device = "gamepad"
			Controls.padAim = Vector2.new(aimX, aimY)
		end
		if action and Controls.actions[action] then
			Controls.actions[action]()
		end
		if autoPick and Menus.offerVisible() then
			Menus.pick(1)
		end
		local ok, err = pcall(frame, dt)
		return if ok then "" else tostring(err), EnemyView.count()
	end
	hook.Parent = script.Parent
end

print("[SWARMFALL] client ready", Defs.Version)
