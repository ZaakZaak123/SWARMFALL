--!nonstrict
-- SWARMFALL client: wires remotes to presentation. Owns local feel (instant predicted shots, dash,
-- aim), while the server owns every outcome.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Codec = require(Shared:WaitForChild("Codec"))
local Maps = require(Shared:WaitForChild("Maps"))
local Meta = require(Shared:WaitForChild("Meta"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local Audio = require(script.Parent:WaitForChild("Audio"))
local EnemyView = require(script.Parent:WaitForChild("EnemyView"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Gear = require(script.Parent:WaitForChild("Gear"))
local CameraRig = require(script.Parent:WaitForChild("CameraRig"))
local DecorLod = require(script.Parent:WaitForChild("DecorLod"))
local Controls = require(script.Parent:WaitForChild("Controls"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local Preview = require(script.Parent:WaitForChild("Preview"))
local Menus = require(script.Parent:WaitForChild("Menus"))
local MetaMenus = require(script.Parent:WaitForChild("MetaMenus"))
local Base = require(script.Parent:WaitForChild("Base"))
local Story = require(script.Parent:WaitForChild("Story"))
local HubMenus = require(script.Parent:WaitForChild("HubMenus"))
local Range = require(script.Parent:WaitForChild("Range"))
local Cableway = require(script.Parent:WaitForChild("Cableway"))
local ShelterVisibility = require(script.Parent:WaitForChild("ShelterVisibility"))
Range.init(workspace)
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
Audio.preloadStings()
EnemyView.init()
Fx.init()
-- DD-075: a black title card from the very first frame; a newcomer's stays up until the intro starts
Story.init(playerGui, {
	base = Base,
	profile = function()
		return Menus.profile()
	end,
})
Story.cover(true)
pcall(function()
	game:GetService("TeleportService"):SetTeleportGui(Story.teleportGui())
end)
Hud.init(playerGui)
Controls.init(playerGui)
Menus.init(playerGui, send)
local ownShowcase -- our own showcase entry (defined with the showcase below)

-- The base between sorties (DD-052): the stations open the same windows as the HUD buttons.
local function goalAction()
	local g = Base.goal()
	if not g then
		return
	end
	local prof = Menus.profile()
	if g.station == "build" then
		local def = g.structure and Meta.Structures[g.structure]
		if g.key == "upgrade" and g.slot then
			send("upgrade", g.slot)
		elseif def and g.slot and g.key ~= "strike" and prof and (prof.scrap or 0) >= def.cost[1] then
			send("build", g.slot, g.structure)
		else
			MetaMenus.showOutpost(g.slot)
		end
	elseif g.station == "launch" then
		if g.mode == "siege" then
			send("mode", "siege")
		end
		Menus.openLaunch()
	elseif g.station == "home" and g.spot then
		send("restore", g.spot)
	elseif g.station == "armory" then
		Menus.showUpgrades()
	elseif g.station == "swarm" then
		MetaMenus.showSwarm()
	end
end
Base.init(playerGui, send, {
	armory = function()
		Menus.showUpgrades()
	end,
	build = function()
		MetaMenus.showOutpost()
	end,
	socket = function(i)
		MetaMenus.showOutpost(i)
	end,
	launch = function()
		Menus.openLaunch()
	end,
	swarm = function()
		MetaMenus.showCollection(Base.collection())
	end,
	collection = function(research, owner, kind, isOwn)
		MetaMenus.showCollection(research, owner, kind, isOwn)
	end,
	settings = function()
		Menus.showSettings()
	end,
	goal = goalAction,
	card = function()
		local e = ownShowcase and ownShowcase()
		if e then
			HubMenus.showCard(myId, e)
		end
	end,
	-- a prepared spot of the shelter: restore it, or use what it became (DD-057)
	spot = function(id: string)
		local prof = Menus.profile()
		local home = prof and prof.home or {}
		if not home[id] then
			local def = Meta.Home[id]
			if def and (prof.scrap or 0) < def.cost then
				HubMenus.toast(
					string.format(
						"Не хватает утиля: нужно %d, у тебя %d. Утиль приносят вылазки.",
						def.cost,
						prof.scrap or 0
					),
					C.orange
				)
				Audio.play("warn", 0.4)
				return
			end
			send("restore", id)
		elseif id == "WORKBENCH" then
			MetaMenus.showOutpost()
		elseif id == "RADIO" then
			send("mode", "siege")
			Menus.openLaunch()
		elseif id == "LAB" then
			MetaMenus.showCollection()
		end
	end,
	radio = function()
		send("mode", "siege")
		Menus.openLaunch()
	end,
	board = function()
		HubMenus.showBoard()
	end,
	outposts = function()
		HubMenus.showOutposts()
	end,
	camp = function()
		send("camp")
	end,
	play = function()
		local g = Base.goal()
		if Base.ready() then
			send("unready")
			Audio.play("ui", 0.8, 0.85)
		elseif g and g.key == "sting" and g.station == "build" then
			-- DD-075: the first steps lead the big button (the turret, then the first defence)
			goalAction()
		elseif g and g.key == "strike" then
			send("mode", "siege")
			send("ready", Menus.selectedWeapon())
			Audio.play("level", 0.7, 1.1)
		else
			send("ready", Menus.selectedWeapon())
			Audio.play("level", 0.7, 1.1)
		end
	end,
})
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
local burstN, burstT, burstShown = 0, 0, 0 -- own kills inside a rolling 0.5 s window
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
local heroOutline: Highlight? = nil
local remoteBeams = {} -- pid -> { untilT, from, to, evolved }
local wasReloading = false
local localSpread = 0 -- predicted accuracy bloom (degrees), reconciled toward the server value
local dryClicked = false
-- Forearms and hands stay visible in first person (they hold the gun in front of the camera).
local FP_KEEP = {
	RightHand = true,
	LeftHand = true,
	RightLowerArm = true,
	LeftLowerArm = true,
	["Right Arm"] = true,
	["Left Arm"] = true,
}

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
	if heroOutline then
		heroOutline:Destroy()
	end
	heroOutline = Instance.new("Highlight")
	heroOutline.Name = "SurvivorOutline"
	heroOutline.Adornee = char
	heroOutline.FillTransparency = 1
	heroOutline.OutlineColor = C.cyan
	heroOutline.OutlineTransparency = 0.25
	heroOutline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	heroOutline.Enabled = false
	heroOutline.Parent = char
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
	if not (mode == "RUN" and run ~= nil and me ~= nil and me.alive and run.paused == "") or Story.active() then
		return false
	end
	-- A newcomer's first hunt waits for their first move or shot (DD-024): that input must be possible.
	return run.phase == "ACTIVE" or (run.phase == "COUNTDOWN" and run.waiting == true)
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
	-- S01 Gravihammer (the Q / Y / touch skill button). The tutorial pause accepts only this press.
	local ready = playing() and me.s01 and me.s01Left <= 0 and not me.s01Casting
	if (me and me.s01Tutorial) or ready then
		send("s01")
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
Hud.ui.evolve.Activated:Connect(function()
	if me and me.s01Tutorial then
		Controls.actions.overdrive()
	else
		Controls.actions.evolve()
	end
end)

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

-- Objective markers (relay zone ring, beacons over nests / nodes / acid sources) --------------------
local objectiveFolder = Instance.new("Folder")
objectiveFolder.Name = "Objectives"
objectiveFolder.Parent = workspace
local relayRing = nil

local function clearObjectives()
	objectiveFolder:ClearAllChildren()
	relayRing = nil
end

local function zoneRing(x: number, z: number, radius: number, color: Color3)
	local ring = Instance.new("Part")
	ring.Name = "RelayZone"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.82
	ring.Size = Vector3.new(0.15, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(x, 0.12, z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = objectiveFolder
	return ring
end

local function beacon(x: number, z: number, color: Color3)
	local p = Instance.new("Part")
	p.Name = "Beacon"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.55
	p.Size = Vector3.new(1.2, 60, 1.2)
	p.CFrame = CFrame.new(x, 30, z)
	p.Parent = objectiveFolder
	return p
end

-- Remotes -----------------------------------------------------------------------------------------
local storyChecked = false -- this run's opening scene (intro / arrival) was decided (DD-075)
local function enterRun()
	inRun = true
	storyChecked = false
	Hud.reset()
	Menus.hideLobby()
	Menus.hideResults()
	Hud.setVisible(true)
	EnemyView.clear()
	Fx.clear()
	clearObjectives()
	CameraRig.reset()
	CameraRig.intro()
	table.clear(lastCoilState)
	-- The sky opens: a rain of spore pods over the crater while the camera comes down.
	task.spawn(function()
		local rng = Random.new()
		for i = 1, 12 do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(60, 120)
			Fx.pod(math.cos(a) * r, math.sin(a) * r, i % 5 == 0)
			task.wait(rng:NextNumber(0.12, 0.3))
		end
	end)
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
	clearObjectives()
	table.clear(remoteBeams)
	Shots.beamStop("local", player.Character)
	Audio.loop("beam", Audio.Ids.beam, 0, 1)
	Controls.enabled = false
end

local showOutpost, outpostKeyOf -- outpost views (defined with the turret handlers below)
local sceneSeen = {} -- op -> its homecoming scene played this session (once at most)
local updateShowcase -- camp/base gear, nameplates and inspection (defined below)
local campState = nil -- camp (public server) state: squads + hunters' showcases (DD-053)
local visitingUid = nil -- whose outpost the camp shows instead of ours
local sessionShelter = nil -- the squad's shared rest stop between runs
stateRemote.OnClientEvent:Connect(function(buf, info)
	if type(info) ~= "table" then
		return
	end
	if info.mode == "HUB" then
		if inRun then
			leaveRun()
		end
		if mode ~= "HUB" then
			Base.resetCamera()
		end
		mode = "HUB"
		sessionShelter = nil
		campState = info.hub
		local mine = nil
		for _, sq in info.hub.squads do
			for _, p in sq.players do
				if p.id == myId then
					mine = sq
				end
			end
		end
		HubMenus.setHub(info.hub, myId)
		Base.setCamp(info.hub)
		-- A visit changes authoritative room membership. Everyone in this room sees the same
		-- owner's restoration, tanks and trophies; a client request alone cannot change the view.
		local room = myId
		for _, h in info.hub.hunters do
			if h.id == myId then
				room = h.room or myId
			end
		end
		local nextVisit = if room ~= myId then room else nil
		if visitingUid ~= nextVisit then
			Base.resetCamera()
		end
		visitingUid = nextVisit
		HubMenus.setVisiting(visitingUid)
		local visible = {}
		for _, h in info.hub.hunters do
			if (h.room or h.id) == room then
				visible[h.id] = true
			end
		end
		ShelterVisibility.update(visible)
		if mine then
			Menus.showLobby(mine, myId, Controls.device)
			Base.setLobby(mine, myId)
		end
		local visit = visitingUid and HubMenus.hunter(visitingUid)
		if visitingUid and not visit then
			visitingUid = nil
			HubMenus.setVisiting(nil)
		end
		Base.setVisitHome(
			if visit then visit.home else nil,
			if visit then visit.slots else nil,
			if visit then visit.stock else nil
		)
		if visit then
			showOutpost(visit.slots, "V" .. visitingUid .. outpostKeyOf(visit.slots))
		else
			local prof = Menus.profile()
			local slots = prof and prof.outpost and prof.outpost.slots or {}
			showOutpost(slots, "L" .. outpostKeyOf(slots))
		end
		return
	end
	campState = nil
	ShelterVisibility.update(nil)
	if visitingUid then
		visitingUid = nil
		HubMenus.setVisiting(nil)
		Base.setVisitHome(nil)
	end
	Base.setCamp(nil)
	if info.mode == "LOBBY" then
		if inRun then
			leaveRun()
		end
		if mode ~= "LOBBY" then
			Base.resetCamera()
		end
		mode = "LOBBY"
		sessionShelter = info.lobby and info.lobby.shelter
		local guest = sessionShelter and sessionShelter.id ~= myId
		Base.setVisitHome(
			if guest then sessionShelter.home else nil,
			if guest then sessionShelter.slots else nil,
			if guest then sessionShelter.stock else nil
		)
		Menus.showLobby(info.lobby, myId, Controls.device)
		Base.setLobby(info.lobby, myId)
		local slots = info.lobby and info.lobby.outpost
		showOutpost(slots, "L" .. outpostKeyOf(slots))
		return
	end
	Base.leaveLobby()
	sessionShelter = nil
	if mode ~= "RUN" then
		Base.setVisitHome(nil)
	end
	mode = "RUN"
	if not inRun then
		enterRun()
	end
	run = info.run
	votes = info.votes or {}
	if run and run.structures then
		local slots = {}
		for _, row in run.structures do
			slots[row[1]] = { id = row[2], lvl = row[3] }
		end
		showOutpost(slots, "R" .. outpostKeyOf(slots))
	else
		showOutpost(nil, "none")
	end
	me = findPlayerState(myId)
	-- DD-075: the newcomer's first sortie opens with the ride out to the drill; the first defence with a
	-- look at the new turret. Both play while the run waits for the first move.
	if not storyChecked and run and run.phase == "COUNTDOWN" and not run.result then
		local prof = Menus.profile()
		local function back()
			if inRun and run and not run.result then
				Hud.setVisible(true)
				CameraRig.intro()
			end
		end
		if run.op == "O01" and run.solo and prof then
			storyChecked = true
			local newcomer = ((prof.winsByOp or {}).O01 or 0) == 0 and not (prof.tut and prof.tut.intro)
			if newcomer then
				Hud.setVisible(false)
				Story.intro(back)
				send("tut", "intro")
			else
				Story.cover(false)
			end
		elseif
			Story.hasDeparture(run.op)
			and run.solo
			and prof
			and ((prof.winsByOp or {})[run.op] or 0) == 0
			and not (prof.tut and prof.tut["go_" .. run.op])
		then
			storyChecked = true
			Hud.setVisible(false)
			Story.depart(run.op, back)
			send("tut", "go_" .. run.op)
		elseif run.op == "STRIKE" and run.solo then
			storyChecked = true
			local at = nil
			for _, row in run.structures or {} do
				local sock = Meta.Sockets[row[1]]
				if sock and (not at or row[1] == Meta.FirstSocket) then
					at = Vector3.new(sock.x, 0, sock.z)
				end
			end
			if at then
				Hud.setVisible(false)
				Story.arrival(at, back)
			end
		elseif run.op ~= "O01" or not run.solo then
			storyChecked = true
			Story.cover(false)
		end
	end
	debugExtra.simMs = info.simMs
	debugExtra.rejected = info.rejected
	if typeof(buf) == "buffer" then
		local n = Codec.decodeEnemies(buf, decodeBuf)
		if not Base.sceneActive() then
			EnemyView.snapshot(decodeBuf, n)
		end
	end
	if me and me.offer and me.alive and run.phase == "ACTIVE" then
		Menus.showOffer(me, run)
	else
		Menus.hideOffer()
	end
	if run.result then
		Hud.setVisible(false)
		-- DD-075/076: a story sortie won for the first time rides home on the cable before the results.
		local prof = Menus.profile()
		local opId = run.result.op
		local tutKey = if opId == "O01" then "drill" else "home_" .. tostring(opId)
		if
			run.result.victory
			and Story.hasHomecoming(opId)
			and run.solo
			and prof
			and not (prof.tut and prof.tut[tutKey])
			and not sceneSeen[opId]
		then
			sceneSeen[opId] = true
			Menus.hideOffer()
			EnemyView.clear()
			Story.returnHome(opId, function()
				send("tut", tutKey)
			end)
		end
		if not Base.sceneActive() and not Story.active() then
			Menus.showResults(run.result, votes, myId, info.rewards and info.rewards[tostring(myId)], info.camp)
		end
	end
	local scened = Story.active() or Story.covered() -- a scene or the title card: no prompts over it
	if not scened and run.phase == "COUNTDOWN" and run.waiting then
		Menus.note("ДВИГАЙСЯ ИЛИ СТРЕЛЯЙ — И В БОЙ")
	elseif not scened and run.phase == "COUNTDOWN" then
		Menus.note(string.format("ВЫХОД  ·  %d", math.ceil(run.countdown)))
	elseif not scened and run.phase ~= "COUNTDOWN" and not me then
		Menus.note("НАБЛЮДЕНИЕ  ·  ТЫ ВОЙДЁШЬ В СЛЕДУЮЩУЮ ВЫЛАЗКУ")
	elseif not scened and me and not me.alive and not run.result and me.downed then
		Menus.note(
			string.format(
				"ТЫ РАНЕН  ·  НАПАРНИК ПОДНИМЕТ  ·  %d с  ·  %d%%",
				me.bleed or 0,
				me.revive or 0
			)
		)
	elseif not scened and me and not me.alive and not run.result then
		Menus.note("ТЫ ВЫБЫЛ  ·  СЛЕДИ ЗА ОТРЯДОМ")
	elseif not scened and run.paused == "MENU" then
		Menus.note("ПАУЗА  ·  P — ПРОДОЛЖИТЬ")
	elseif not scened and run.paused == "CHOOSE" and me and not me.offer then
		Menus.note("ОТРЯД ВЫБИРАЕТ УЛУЧШЕНИЯ…")
	else
		Menus.note(nil)
	end
end)

-- Test place only (test.project.json): which server am I on — camp or a squad's server.
if ReplicatedStorage:GetAttribute("TestPlace") then
	local g = Instance.new("ScreenGui")
	g.Name = "SporeTestTag"
	g.ResetOnSpawn = false
	g.DisplayOrder = 50
	g.Parent = playerGui
	local tag = Theme.label("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.fromOffset(520, 18),
		FontFace = Theme.F.head,
		TextSize = 12,
		TextColor3 = C.gold,
		Parent = g,
	})
	task.spawn(function()
		while g.Parent do
			local role = ReplicatedStorage:GetAttribute("ServerRole")
			tag.Text = string.format(
				"ТЕСТОВОЕ МЕСТО  ·  %s  ·  сервер %s  ·  игроков %d",
				if role == "SESSION" then "СЕРВЕР ОТРЯДА" else "ЛАГЕРЬ",
				string.sub(game.JobId, 1, 6),
				#Players:GetPlayers()
			)
			task.wait(1)
		end
	end)
end

-- Camp (DD-053) ------------------------------------------------------------------------------------------
-- The server selects the shelter room; visitors share its home, exhibits and visible hunters.
HubMenus.init(Menus.helpers(), {
	ownTitles = function()
		local prof = Menus.profile()
		if not prof then
			return {}
		end
		return require(Shared:WaitForChild("Showcase")).titles({
			wins_by_op = prof.winsByOp,
			outpost = prof.outpost,
			home = prof.home,
			saves = prof.saves,
			research = prof.research,
		})
	end,
	visit = function(uid: number)
		send("visit", uid)
	end,
	home = function()
		send("visit", myId)
	end,
})
remotes:WaitForChild(Codec.Remotes.Social).OnClientEvent:Connect(function(kind, data)
	if type(kind) == "string" then
		HubMenus.onSocial(kind, data)
	end
end)

-- Nameplate (title over the head) and «Осмотреть» on every other hunter, between runs.
local plates = {} -- character -> { gui, title, prompt, uid }
local function plateFor(char: Model, uid: number)
	local rec = plates[char]
	if rec then
		return rec
	end
	local head = char:FindFirstChild("Head")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not head or not root then
		return nil
	end
	local g = Instance.new("BillboardGui")
	g.Name = "SporePlate"
	g.Size = UDim2.fromOffset(220, 46)
	g.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	g.LightInfluence = 0
	g.MaxDistance = 90
	g.AlwaysOnTop = true
	g.Adornee = head
	local name =
		Theme.label("", { Size = UDim2.new(1, 0, 0, 24), FontFace = Theme.F.display, TextSize = 18, Parent = g })
	local st = Instance.new("UIStroke")
	st.Thickness = 2.5
	st.Color = C.ink
	st.Parent = name
	local title = Theme.label("", {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 18),
		FontFace = Theme.F.head,
		TextSize = 12,
		TextColor3 = C.gold,
		Parent = g,
	})
	local st2 = Instance.new("UIStroke")
	st2.Thickness = 2
	st2.Color = C.ink
	st2.Parent = title
	g.Parent = head
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Осмотреть"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function()
		HubMenus.showCard(uid)
	end)
	rec = { gui = g, name = name, title = title, prompt = prompt, uid = uid }
	plates[char] = rec
	return rec
end

-- The showcase row on the base: the visited hunter's, else our own (built from the profile).
local Showcase = require(Shared:WaitForChild("Showcase"))
ownShowcase = function()
	local prof = Menus.profile()
	if not prof then
		return nil
	end
	local d = {
		wins_by_op = prof.winsByOp,
		mastery = prof.mastery,
		outpost = prof.outpost,
		raid = prof.raid,
		wins = prof.wins,
		home = prof.home,
		research = prof.research,
		saves = prof.saves,
		title = prof.title,
	}
	local weapon = Menus.selectedWeapon()
	return Showcase.build(myId, player.DisplayName, d, weapon, prof.equip and prof.equip[weapon])
end

updateShowcase = function()
	local shown = nil
	if mode == "HUB" and campState and visitingUid then
		shown = HubMenus.hunter(visitingUid)
	elseif mode == "LOBBY" then
		shown = sessionShelter
	end
	Base.setShowcase(shown or ownShowcase())
	local list = {}
	if mode == "HUB" and campState then
		local room = visitingUid or myId
		for _, h in campState.hunters do
			if (h.room or h.id) == room then
				list[h.id] = { weapon = h.weapon, form = h.form, name = h.name, title = h.title }
			else
				local p = Players:GetPlayerByUserId(h.id)
				if p and p.Character then
					Gear.remove(p.Character)
				end
			end
		end
	elseif mode == "LOBBY" then
		local info = Menus.lobbyState()
		for _, p in (info and info.players) or {} do
			list[p.id] = { weapon = p.weapon, name = p.name, title = "" }
		end
	end
	for uid, e in list do
		local pl = Players:GetPlayerByUserId(uid)
		local char = pl and pl.Character
		if char and Defs.Weapons[e.weapon] then
			local rig = Gear.ensure(char, e.weapon, e.form ~= nil, uid == myId)
			if rig then
				Gear.update(rig, false, 0, false)
				Rig.setState(char, true, 0, 1, false)
			end
			if uid ~= myId then
				local rec = plateFor(char, uid)
				if rec then
					rec.name.Text = e.name
					rec.title.Text = e.title
					rec.prompt.Enabled = mode == "HUB" and Base.isActive()
				end
			end
		end
	end
	for char, rec in plates do
		if not char.Parent or not list[rec.uid] then
			rec.gui:Destroy()
			rec.prompt:Destroy()
			plates[char] = nil
		end
	end
	Gear.cleanup()
end

local function nearMe(pos: Vector3, radius: number): boolean
	local root = myRoot()
	return root ~= nil
		and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < radius
end

-- Ichor of each species (DD-050): droplets, streaks and the splat left on the floor.
local BLOOD = {
	Color3.fromRGB(255, 110, 40), -- runner
	Color3.fromRGB(230, 60, 150), -- leaper
	Color3.fromRGB(170, 255, 70), -- spitter
	Color3.fromRGB(90, 200, 255), -- bulwark
	Color3.fromRGB(255, 190, 70), -- elite
	Color3.fromRGB(170, 255, 80), -- hive
	Color3.fromRGB(255, 90, 170), -- broodmother
	Color3.fromRGB(255, 150, 40), -- bomber
	Color3.fromRGB(170, 255, 80), -- devourer
	Color3.fromRGB(255, 170, 60), -- alpha
	Color3.fromRGB(200, 140, 255), -- node
	Color3.fromRGB(170, 255, 80), -- acid source
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
			Fx.emitWith("gooBlob", pos, 2, 0.7, BLOOD[rec.kind] or BLOOD[1], (d.Unit + Vector3.yAxis * 0.8).Unit)
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
	local big = kind >= 4 and kind ~= 8
	local blood = BLOOD[kind] or BLOOD[1]
	local size = if kind == 7 or kind == 9 then 2.2 elseif kind == 5 or kind >= 10 then 1.6 elseif big then 1.2 else 0.9
	Fx.gore(pos, size, blood, dir, big)
	if Settings.quality >= 2 then
		Fx.emit("dust", pos, if big then 4 else 1)
	end
	if big then
		Fx.light(pos + Vector3.yAxis * 3, blood, size * 10, 0.25)
		if kind == 7 or kind == 9 then
			Fx.debris(pos + Vector3.yAxis * 3, 10, blood:Lerp(Color3.new(0, 0, 0), 0.6), 26)
		end
		Audio.at("killBig", pos, 1)
		if nearMe(pos, 60) then
			CameraRig.shake(if kind >= 5 then 0.6 else 0.3)
		end
	else
		Audio.at("kill", pos, 0.8)
	end
	if killer == myId then
		Hud.hitmarker(true)
		local now = os.clock()
		burstN = if now - burstT < 0.5 then burstN + 1 else 1
		burstT = now
		if burstN == 1 then
			burstShown = 0
		end
		-- A wave of kills at once (chain, blast, hammer, a pierced column): pop once, then grow.
		if burstN >= 8 and burstN >= burstShown + 4 then
			burstShown = burstN
			Hud.burst(burstN)
			Audio.play("killBig", 0.7, 0.75 + math.min(burstN, 30) * 0.01)
			CameraRig.punch(math.min(0.6, 0.2 + burstN * 0.015))
		end
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
		Fx.lightning(a, b, c, if color == Codec.C.BLUE or color == Codec.C.ICE then 0.32 else 0.22, 0.17)
		Fx.emit("hitCyan", b, 4)
		Fx.light(b, c, 12, 0.1)
		if color == Codec.C.ICE then
			Audio.at("ice", b, 0.45, 1.3) -- ice shards / shatter (Крио, Ледолом)
		else
			Audio.at("arc", a, 0.7)
		end
	end
end
handlers[E.BOOM] = function(x, z, r, color)
	local pos = Vector3.new(x, 1, z)
	if color == Codec.C.ICE then
		-- «Ледяной панцирь»: a frost ring and ice glints, not a fireball.
		Fx.shockwave(pos, r, C.cyan, 0.45)
		Fx.shockwave(pos, r * 0.6, Color3.fromRGB(220, 250, 255), 0.3)
		Fx.emit("hitCyan", pos + Vector3.yAxis, math.floor(r * 2))
		Fx.light(pos + Vector3.yAxis * 3, C.cyan, r * 2.5, 0.25)
		Audio.at("ice", pos, 1)
		return
	end
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
handlers[E.HAMMER] = function(pid, x, z, radius, phase, emergency, hits)
	local pos = Vector3.new(x, 1, z)
	local big = emergency == 1
	if phase == 0 then
		-- Granted: a reactor beam lances into the player.
		Fx.lightning(Vector3.new(0, 14, 0), pos + Vector3.yAxis * 3, C.cyan, 0.6, 0.6)
		Audio.play("coil", 1, 0.8)
		return
	end
	local char = characterOf(pid)
	if phase == 1 then
		if char then
			Rig.flinch(char, 0, 1, 0.6)
		end
		Fx.telegraph(Codec.Shape.CIRCLE, x, z, 0, 1, radius, 0, Defs.S01.Windup, C.cyan, 0)
		Fx.light(pos + Vector3.yAxis * 10, C.violet, 30, Defs.S01.Windup + 0.2)
		Audio.at("railCharge", pos, 1, if big then 0.7 else 0.9)
		return
	end
	if phase == 3 then
		-- Specialization follow-up wave.
		Fx.shockwave(pos, radius, C.violet, 0.5)
		Fx.emit("sparkCyan", pos + Vector3.yAxis, 24)
		Audio.at("overdrive", pos, 0.6, 1.2)
		return
	end
	Fx.boom(pos, radius, C.cyan)
	Fx.shockwave(pos, radius * 1.15, C.cyan, 0.45)
	Fx.shockwave(pos, radius * (if big then 1.45 else 1.25), C.violet, 0.75)
	Fx.emit("sparkCyan", pos + Vector3.yAxis, if big then 90 else 45)
	Fx.light(pos + Vector3.yAxis * 6, C.cyan, radius * 4, 0.5)
	Audio.at("overdrive", pos, 1, if big then 0.75 else 0.9)
	if pid == myId then
		CameraRig.punch(if big then 18 else 10)
		CameraRig.shake(if big then 0.9 else 0.5)
		if big then
			Menus.whiteFlash(0.3)
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
local reactorHitClock = 0
handlers[E.REACTOR] = function(action, amount, fx, fz)
	local centre = Vector3.new(0, 6, 0)
	if action == 1 then
		local now = os.clock()
		if now - reactorHitClock > 0.25 then
			reactorHitClock = now
			local dir = Vector3.new((fx or 0), 0, (fz or 1))
			dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.zAxis
			local rim = centre + dir * (Defs.Reactor.Radius + 0.5)
			Fx.emit("sparkGold", rim, 10, dir)
			Fx.number(rim + Vector3.yAxis * 3, amount, C.orange, false)
			Audio.at("hurt", rim, 0.6)
		end
	elseif action == 2 then
		Audio.play("crit", 1, 0.5)
		Fx.shockwave(Vector3.new(0, 1, 0), 18, C.red, 0.5)
	elseif action == 4 then
		-- Relay coil under attack.
		local now = os.clock()
		if now - reactorHitClock > 0.3 then
			reactorHitClock = now
			local pos = Vector3.new(fx or 0, 4, fz or 0)
			Fx.emit("sparkGold", pos, 8)
		end
	elseif action == 6 then
		-- «Барьер» shields the reactor: a quick cyan pulse over the hull.
		Fx.shockwave(Vector3.new(0, 1, 0), Defs.Reactor.Radius + 4, C.cyan, 0.4)
	elseif action == 3 then
		Fx.boom(centre, 26, C.red)
		Fx.shockwave(Vector3.new(0, 1, 0), 40, C.red, 0.8)
		CameraRig.shake(1)
		Menus.whiteFlash(0.5)
	end
end
handlers[E.ASSAULT] = function(sx, sz, count, eta, tx, tz)
	if count == 0 then
		-- Objective ping (e.g. the relay coming online): a light column, no lane.
		Fx.light(Vector3.new(sx, 10, sz), C.cyan, 70, 2)
		Fx.shockwave(Vector3.new(sx, 1, sz), 30, C.cyan, 0.8)
		return
	end
	-- Ground lane from the breach toward the target: readable in every camera before contact.
	local dx, dz = (tx or 0) - sx, (tz or 0) - sz
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1 then
		return
	end
	Fx.telegraph(
		Codec.Shape.LINE,
		sx,
		sz,
		dx / len,
		dz / len,
		len - Defs.Reactor.Radius - 4,
		6,
		math.max(2, eta or 6),
		C.orange,
		0
	)
	Fx.light(Vector3.new(sx, 8, sz), C.orange, 50, 1.2)
	Audio.play("roar", 0.5, 0.7)
end
handlers[E.OBJECTIVE] = function(action, x, z, a)
	local pos = Vector3.new(x, 1, z)
	if action == 1 then
		if relayRing then
			relayRing:Destroy()
		end
		relayRing = zoneRing(x, z, a, C.cyan)
		beacon(x, z, C.cyan).Name = "RelayBeacon"
		Fx.shockwave(pos, a, C.cyan, 0.8)
		Audio.play("coil", 1, 0.9)
	elseif action == 2 then
		local b = beacon(x, z, C.lime)
		b.Name = "Target" .. tostring(a)
		Fx.shockwave(pos, 12, C.lime, 0.6)
	elseif action == 3 then
		if relayRing then
			relayRing.Color = C.gold
			relayRing.Transparency = 0.7
		end
		Fx.shockwave(pos, 34, C.gold, 1)
		Fx.light(pos + Vector3.yAxis * 12, C.gold, 80, 1.5)
		Audio.play("evolve")
	elseif action == 4 then
		local b = objectiveFolder:FindFirstChild("Target" .. tostring(a))
		if b then
			b:Destroy()
		end
		Fx.boom(Vector3.new(x, 3, z), 14, C.lime)
		Fx.shockwave(pos, 22, C.lime, 0.7)
		CameraRig.shake(0.5)
	end
end
handlers[E.COMPONENT] = function(x, z)
	local pos = Vector3.new(x, 2, z)
	Fx.emit("sparkGold", pos, 80)
	Fx.shockwave(pos, 18, C.gold, 0.8)
	Fx.light(pos + Vector3.yAxis * 6, C.gold, 40, 1.2)
	Audio.play("evolve")
	CameraRig.shake(0.4)
end
-- Outpost structures (DD-037/038): your turrets in sieges and in the lobby; enemy turrets in raids are
-- EnemyView records (negative refs). One shot handler for both sides.
local Structures = require(script.Parent:WaitForChild("Structures"))
local outpostFolder = Instance.new("Folder")
outpostFolder.Name = "OutpostView"
outpostFolder.Parent = workspace
local outpostModels = {} -- slot -> model
local outpostKey = nil
local lastLobbySlots = nil -- what stood on the base last time: new pieces rise out of the ground
showOutpost = function(slots, key: string?)
	if key == outpostKey then
		return
	end
	local inLobby = key ~= nil and key:sub(1, 1) == "L"
	local before = if inLobby and outpostKey and outpostKey:sub(1, 1) == "L" then lastLobbySlots else nil
	outpostKey = key
	outpostFolder:ClearAllChildren()
	table.clear(outpostModels)
	local seen = {}
	for slot, s in slots or {} do
		local sock = Meta.Sockets[tonumber(slot)]
		local id, lvl = s.id or s[2], s.lvl or s[3]
		if sock and id then
			local m = Structures.model(id, lvl, false)
			local face = math.atan2(sock.x, sock.z) -- look outward, at the swarm
			local cf = CFrame.new(sock.x, 0, sock.z) * CFrame.Angles(0, face + math.pi, 0)
			m:PivotTo(cf)
			m.Parent = outpostFolder
			outpostModels[tonumber(slot)] = m
			local tag = tostring(slot) .. id .. tostring(lvl)
			seen[tag] = true
			if before and not before[tag] then
				-- built on the workbench in the shelter; it stands at the drill (DD-057)
				Base.crafted(Meta.Structures[id].color)
			end
		end
	end
	if inLobby then
		lastLobbySlots = seen
	end
end
outpostKeyOf = function(slots): string
	local parts = {}
	for slot, s in slots or {} do
		table.insert(parts, tostring(slot) .. (s.id or s[2] or "") .. (s.lvl or s[3] or 0))
	end
	table.sort(parts)
	return table.concat(parts, ",")
end
local TURRET_COLOR = { [1] = Color3.fromRGB(255, 196, 70), [2] = C.cyan, [3] = C.orange, [4] = C.blue }
handlers[E.TURRET] = function(ref, fx, fz, tx, tz, kind)
	local hostile = ref < 0
	local color = if hostile then C.red else TURRET_COLOR[kind] or C.gold
	local from = Vector3.new(fx, 3.2, fz)
	local to = Vector3.new(tx, 1.4, tz)
	if not hostile then
		local m = outpostModels[ref]
		if m and kind ~= 4 then
			local yaw = math.atan2(-(tx - fx), -(tz - fz))
			m:PivotTo(CFrame.new(fx, 0, fz) * CFrame.Angles(0, yaw, 0))
		end
	end
	if kind == 1 then
		Fx.tracer(from, to, color, 0.35, 0.08)
		Fx.light(from, color, 10, 0.08)
		Audio.at("rifleClick", from, 0.5, 1.4)
	elseif kind == 2 then
		Fx.light(from + Vector3.yAxis * 2, color, 16, 0.2)
		Audio.at("arc", from, 0.6, 0.9)
	elseif kind == 3 then
		Fx.projectile(from + Vector3.yAxis, to, color, 0.9, 70, 3, function() end)
		Audio.at("boom", from, 0.25, 1.6)
	elseif kind == 4 then
		Fx.shockwave(Vector3.new(fx, 1, fz), 10, C.blue, 0.6)
		Fx.lightning(Vector3.new(fx, 7, fz), Vector3.new(tx, 6, tz), C.blue, 0.4, 0.3)
	end
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
		remoteBeams[pid] = {
			untilT = os.clock() + 0.2,
			to = Vector3.new(ex, 3, ez),
			from = Vector3.new(ox, 3, oz),
			evolved = evolved == 1,
		}
	end
end
-- DD-075: the leader of the first fights falls — the run ends here. A golden blast where it fell, the
-- leaderless swarm blown apart by the shockwave (the server kills it), a white flash, the camera leaning
-- in, a warm grade and the fanfare.
local victoryGlow = 0
-- DD-077: the charged pylon's song ends O03 the same way, in the pylon's cyan.
local function leaderDown(x: number, z: number, song: boolean?)
	local at = Vector3.new(x, 0, z)
	local gold = if song then Color3.fromRGB(110, 236, 255) else Color3.fromRGB(255, 204, 70)
	Audio.play(if song then "evolveStorm" else "roar", 1, if song then 1.1 else 1.4)
	Audio.play("killBig", 1, 0.7)
	Audio.sting("victory", 12)
	Menus.whiteFlash(0.85)
	CameraRig.shake(1)
	CameraRig.punch(14)
	CameraRig.closeUp(1.8)
	victoryGlow = 2.6
	Fx.boom(at, 12, gold)
	Fx.light(at + Vector3.new(0, 6, 0), gold, 90, 1.6)
	Fx.debris(at + Vector3.new(0, 3, 0), 12, Color3.fromRGB(60, 44, 30), 34)
	for i = 1, 4 do
		task.delay(i * 0.16, function()
			Fx.ring(at + Vector3.new(0, 0.4, 0), 14 + i * 22, gold, 0.55 + i * 0.12)
		end)
	end
	for i = 1, 8 do
		task.delay(0.1 + i * 0.07, function()
			local a = i / 8 * math.pi * 2
			Fx.boom(
				at + Vector3.new(math.cos(a), 0, math.sin(a)) * (6 + i),
				4,
				if song then Color3.fromRGB(190, 250, 255) else Color3.fromRGB(255, 226, 140)
			)
		end)
	end
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		Fx.emitWith("streak", at + Vector3.new(0, 2, 0), 4, 1.4, gold, Vector3.new(math.cos(a), 0.9, math.sin(a)).Unit)
	end
end

handlers[E.BOSS] = function(action, x, z)
	if action == 6 or action == 7 then
		leaderDown(x or 0, z or 0, action == 7)
	elseif action == 5 then
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
		Base.setProfile(pub)
		Story.profile(pub)
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
		Audio.loop("beam", Audio.Ids.beam, if active then 0.3 else 0, if evolved then 0.85 else 1.05)
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
				table.insert(
					items,
					predictShot(muzzle, math.sin(a), math.cos(a), range * (0.85 + math.random() * 0.15), 0)
				)
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

-- Spore pods (DD-033): where the swarm surfaces, pods keep falling from the sky. One pod per breach
-- every few seconds (and always for big enemies), so the sky shows where the next wave comes from.
local podClock = {}
EnemyView.onSpawn = function(x: number, z: number, kind: number)
	if mode ~= "RUN" then
		return
	end
	local big = kind == 5 or kind == 7 or kind == 9 or kind == 10
	local cell = math.floor(x / 24) .. ":" .. math.floor(z / 24)
	local now = os.clock()
	if big or now - (podClock[cell] or 0) > 2.4 then
		podClock[cell] = now
		Fx.pod(x + math.random(-3, 3), z + math.random(-3, 3), big)
	end
end

-- Tall decor between the camera and the hero fades out (ribs, mushroom caps, the drill rig).
local fadeParts = {}
local fadeClock = 0
local function updateFade(dt: number, cam: Camera, focus: Vector3?)
	fadeClock += dt
	if fadeClock < 0.05 then
		return
	end
	local step = fadeClock
	fadeClock = 0
	local c = cam.CFrame.Position
	for _, f in fadeParts do
		local p = f.part
		local want = 0
		if focus then
			-- distance from the part to the camera->hero segment, and the hero is not in front of it
			local seg = focus + Vector3.new(0, 2, 0) - c
			local len = seg.Magnitude
			local dir = seg / len
			local rel = p.Position - c
			local t = math.clamp(rel:Dot(dir), 0, len)
			local d = (rel - dir * t).Magnitude
			if d < f.r and t < len - 1 then
				-- glowing parts still bloom through a partial fade: they go almost all the way
				want = if p.Material == Enum.Material.Neon then 0.95 else 0.72
			end
		end
		local cur = p.LocalTransparencyModifier
		if cur ~= want then
			p.LocalTransparencyModifier = cur + (want - cur) * math.min(1, step * 8)
			if math.abs(p.LocalTransparencyModifier - want) < 0.02 then
				p.LocalTransparencyModifier = want
			end
		end
	end
end

-- Arena animation -------------------------------------------------------------------------------------
local animated = nil -- { rings = {{part, baseCF, index}}, core = part?, heart = part? }
local arenaCable = nil -- the cableway from the drill over the south rim, towards the shelter (DD-065)
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
				elseif r.Name == "Auger" then
					animated.auger = { r, r.CFrame }
				end
			end
		end
		animated.heart = decor:FindFirstChild("Heart")
		-- the drill sends its utility home: crates leave its top along the cable over the south rim, the
		-- same line that ends at the shelter's gate
		if arenaCable then
			arenaCable:destroy()
			arenaCable = nil
		end
		if reactorModel then
			local cf, size = reactorModel:GetBoundingBox()
			local top = cf.Position + Vector3.new(0, size.Y * 0.3, -2)
			-- Freight goes along the west edge (not through the hero's lane under the top-down camera)
			-- and over the north-west rim: the shelter lies that way, up the same cable (DD-075).
			local side = Cableway.ARENA_SIDE
			local rim = Cableway.ARENA_RIM
			arenaCable = Cableway.new(
				decor,
				{ top, side, rim },
				{ posts = { [2] = Vector3.new(side.X, 0, side.Z), [3] = Vector3.new(rim.X, 0, rim.Z) }, every = 4.5 }
			)
		end
		DecorLod.scan(decor)
		table.clear(fadeParts)
		for _, d in decor:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Fade") then
				-- a tall piece covers more of the screen than its footprint (the drill rig leans over half
				-- the view from the hero's side), so its reach grows with its height
				table.insert(fadeParts, { part = d, r = math.max(d.Size.X, d.Size.Z) * 0.5 + 3 + d.Size.Y * 0.45 })
			end
		end
		-- the drill fades as a whole: its glowing rings go with the rig, not on their own (other decor
		-- models hold many scattered pieces, which fade one by one)
		local reach = 0
		for _, f in fadeParts do
			if f.part.Parent == reactorModel then
				reach = math.max(reach, f.r)
			end
		end
		for _, f in fadeParts do
			if f.part.Parent == reactorModel then
				f.r = reach
			end
		end
		animated.rings2 = {}
		for i = 1, 4 do
			local coil = decor:FindFirstChild("Coil" .. i)
			if coil then
				for _, r in coil:GetChildren() do
					if r.Name == "Ring" and r.Shape == Enum.PartType.Cylinder then
						table.insert(animated.rings2, { r, r.CFrame, i })
					end
				end
			end
		end
		for i = 1, 4 do
			coilModels[i] = decor:FindFirstChild("Coil" .. i)
		end
	end
	for _, ring in animated.rings do
		local i = ring[3]
		ring[1].CFrame = ring[2]
			* CFrame.new(math.sin(now * 1.3 + i) * 0.4, 0, 0)
			* CFrame.Angles(now * (0.4 + i * 0.25) * (if i % 2 == 0 then -1 else 1), 0, 0)
	end
	for _, ring in animated.rings2 do
		ring[1].CFrame = ring[2]
			* CFrame.new(math.sin(now * 2 + ring[3]) * 0.4, 0, 0)
			* CFrame.Angles(0, math.sin(now * 1.3 + ring[3]) * 0.18, math.sin(now * 1.7 + ring[3] * 2) * 0.18)
	end
	if animated.auger then
		animated.auger[1].CFrame = animated.auger[2] * CFrame.Angles(0, now * 2.4, 0)
	end
	if animated.core then
		animated.core.Transparency = 0.45 + (math.sin(now * 2.5) + 1) * 0.08
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
					pad.Transparency = 0.6 + math.sin(now * 2.4 + i) * 0.12
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
	local margin = 64 -- the arrow and its tag stay fully on screen
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
		table.insert(
			arrowList,
			{ x = cx + dx / m, y = cy + dy / m, rot = math.deg(math.atan2(dy, dx)) + 90, color = color, text = text }
		)
	end
	for _, rec in EnemyView.records do
		if rec.kind == 7 or rec.kind == 9 then
			add(Vector3.new(rec.dx, 6, rec.dz), C.red, "БОСС")
		elseif rec.kind == 5 or rec.kind == 10 then
			add(Vector3.new(rec.dx, 4, rec.dz), C.gold, if rec.kind == 10 then "АЛЬФА" else "ЭЛИТА")
		elseif rec.kind == 6 then
			add(Vector3.new(rec.dx, 4, rec.dz), C.lime, "ГНЕЗДО")
		elseif rec.kind == 11 then
			add(Vector3.new(rec.dx, 4, rec.dz), C.lime, "УЗЕЛ")
		elseif rec.kind == 12 then
			add(Vector3.new(rec.dx, 4, rec.dz), C.lime, "ИСТОЧНИК")
		elseif rec.kind == 17 then
			add(Vector3.new(rec.dx, 6, rec.dz), C.red, "БУР")
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

-- Adaptive quality: a sustained low frame rate during a run steps quality down; a long stretch of
-- headroom steps it back up to where the player (or device default) set it. Hysteresis avoids flapping.
local perf = { low = 0, high = 0, ceiling = Settings.quality }
Settings.onChanged(function(key, value)
	if key == "quality" then
		if not perf.auto then
			perf.ceiling = value
		end
		Lighting.GlobalShadows = Settings.Budget.shadows[value]
	end
end)
Lighting.GlobalShadows = Settings.Budget.shadows[Settings.quality]

local function adaptQuality(dt: number, measuredFps: number)
	if not Settings.autoQuality or mode ~= "RUN" then
		perf.low, perf.high = 0, 0
		return
	end
	if measuredFps < 38 and Settings.quality > 1 then
		perf.low += dt
		perf.high = 0
		if perf.low > 4 then
			perf.low = 0
			perf.auto = true
			Settings.set("quality", Settings.quality - 1)
			perf.auto = false
		end
	elseif measuredFps > 57 and Settings.quality < perf.ceiling then
		perf.high += dt
		perf.low = 0
		if perf.high > 25 then
			perf.high = 0
			perf.auto = true
			Settings.set("quality", Settings.quality + 1)
			perf.auto = false
		end
	else
		perf.low = math.max(0, perf.low - dt)
		perf.high = math.max(0, perf.high - dt)
	end
end

local function frame(dt: number)
	local now = os.clock()
	fps += (1 / math.max(dt, 1e-3) - fps) * 0.05
	adaptQuality(dt, fps)
	local cam = workspace.CurrentCamera
	local root, hum = myRoot()
	local isPlaying = playing()
	if heroOutline then
		heroOutline.Enabled = isPlaying and CameraRig.mode() == "top"
	end
	local choosing = Menus.offerVisible()
	-- the shooting range on the base drives the gun while the hunter stands on its mark (DD-055)
	local ranging = (mode == "LOBBY" or mode == "HUB") and Base.isActive() and Range.wants(root and root.Position)
	Controls.enabled = (isPlaying and not choosing) or ranging
	-- Camera look input first (mouse-look / stick-look in third & first person), then aim.
	CameraRig.processInput(dt, Controls.device, isPlaying and not choosing and mode == "RUN", Controls.look)
	local immersive = CameraRig.immersive() and isPlaying
	local fx, fz = CameraRig.forward()
	if root then
		local range = if me then Defs.Weapons[me.weapon].range else 60
		Controls.update(root.Position, (isPlaying and not choosing) or ranging, range, immersive, fx, fz)
	else
		Controls.update(Vector3.zero, false, 60)
	end

	-- Movement & facing
	local walkingBase = (mode == "LOBBY" or mode == "HUB") and Base.isActive()
	if hum then
		local frozen = not isPlaying or choosing
		local slow = if me and me.slow then me.slow else 0
		hum.WalkSpeed = if walkingBase then Defs.Player.Speed elseif frozen then 0 else Defs.Player.Speed * (1 - slow)
		hum.AutoRotate = walkingBase and not ranging
	end
	if root and linearVelocity then
		local dashing = now < dashUntil and isPlaying
		linearVelocity.Enabled = dashing
		if dashing then
			linearVelocity.PlaneVelocity = Vector2.new(dashDir.X, dashDir.Z)
				* (Defs.Player.DashDistance / Defs.Player.DashTime)
		end
	end
	if mode == "LOBBY" or mode == "HUB" then
		Range.update(
			dt,
			if root then root.Position else nil,
			player.Character,
			Menus.selectedWeapon(),
			Controls.aimX,
			Controls.aimZ,
			Controls.firing and ranging
		)
	end
	if root and (isPlaying or ranging) then
		local look = Vector3.new(Controls.aimX, 0, Controls.aimZ)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	end

	-- Aim replication (20 Hz or on change)
	if isPlaying or lastAimSent.firing then
		local firing = Controls.firing and isPlaying
		local dot = Controls.aimX * lastAimSent.x + Controls.aimZ * lastAimSent.z
		if
			firing ~= lastAimSent.firing
			or (now - lastAimSent.t > 0.05 and dot < 0.9995)
			or now - lastAimSent.t > 0.5
		then
			send("aim", Controls.aimX, Controls.aimZ, firing)
			lastAimSent.x, lastAimSent.z, lastAimSent.firing, lastAimSent.t = Controls.aimX, Controls.aimZ, firing, now
		end
	end

	-- Between runs: everyone carries their gun, a nameplate with their title, and can be inspected.
	if not run then
		updateShowcase()
	end
	-- Gear for every squad member
	if run then
		for _, p in run.players do
			local pl = Players:GetPlayerByUserId(p.id)
			local char = pl and pl.Character
			if char then
				local rig = Gear.ensure(char, p.weapon, p.evolved ~= "", p.id == myId)
				if rig then
					Gear.update(rig, p.s01Casting, p.shield, not p.alive)
					local beamKind = Defs.Weapons[p.weapon].kind == "beam"
					Rig.setState(
						char,
						p.alive,
						if p.reload > 0 then p.reload elseif beamKind and p.overheated then 0.5 else 0,
						p.ammo / math.max(1, p.mag),
						p.reloadEmpty
					)
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
							Audio.loop("beam", Audio.Ids.beam, 0, 1)
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
		updateFade(dt, workspace.CurrentCamera, focus)
		if arenaCable then
			arenaCable:update(dt)
		end
	else
		local lroot = myRoot()
		if Menus.lobbyVisible() or not lroot then
			CameraRig.update(dt, "lobby", nil, 0, 1, 0, nil, if lroot then lroot.Position else nil)
		else
			-- walking the base
			cam.CameraType = Enum.CameraType.Scriptable
			cam.FieldOfView = 55
			cam.CFrame = Base.camera(dt, lroot.Position)
		end
	end
	Story.update()
	local sceneCf = Story.camera(dt) or Base.sceneCamera(dt)
	if sceneCf then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = sceneCf
	end
	local baseWorld = mode ~= "RUN" or Base.sceneActive()
	Base.setWorldVisible(baseWorld)
	Range.setVisible(mode ~= "RUN")
	local onBase = (mode == "LOBBY" or mode == "HUB")
		and not Menus.modalOpen()
		and not HubMenus.anyVisible()
		and not Base.sceneActive()
	Base.setActive(onBase)
	Base.update(dt, if root then root.Position else nil)

	-- Overdrive grade
	local grade = Lighting:FindFirstChild("Grade")
	if grade then
		local od = me and me.s01Casting
		local low = me and me.alive and me.hp / me.maxHp < 0.3
		grade.Saturation = if od then 0.45 elseif low then -0.25 else 0.2
		grade.TintColor = if od then Color3.fromRGB(255, 240, 215) else Color3.fromRGB(255, 238, 250)
		if victoryGlow > 0 then
			victoryGlow = math.max(0, victoryGlow - dt)
			local k = math.min(1, victoryGlow / 1.2)
			grade.TintColor = grade.TintColor:Lerp(Color3.fromRGB(255, 214, 150), k)
			grade.Saturation = grade.Saturation + 0.25 * k
			grade.Brightness = 0.02 + 0.08 * k
		end
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
	Audio.setMusic(if mode ~= "RUN" or not run or run.result then "lobby" elseif run.boss then "boss" else "run")
	Audio.updateMusic(dt)

	if run and me then
		computeArrows(cam)
		local extra = {
			arrows = arrowList,
			cursor = if immersive
				then Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
				elseif Controls.device == "pc" then Controls.cursor
				else nil,
			showReticle = (Controls.device == "pc" or immersive) and isPlaying and not choosing,
			device = Controls.device,
			spread = localSpread,
			debug = if RunService:IsStudio()
				then string.format(
					"%.0f FPS  ·  %d ENEMIES  ·  SIM %.2fms  ·  REJ %s  ·  FX %d",
					fps,
					EnemyView.count(),
					debugExtra.simMs or 0,
					tostring(debugExtra.rejected or 0),
					Fx.stats().live
				)
				else nil,
		}
		Hud.setDimmed(choosing)
		Hud.update(run, me, extra, dt)
		Hud.setView(CameraRig.mode(), CameraRig.ModeIcons[CameraRig.mode()], nil, Controls.device)
		Controls.setViewIcon(CameraRig.ModeIcons[CameraRig.mode()])
		-- Touch buttons
		Controls.setButton(
			"dash",
			true,
			me.dash / Defs.Player.DashCooldown,
			if me.dash > 0 then string.format("%.1f", me.dash) else "",
			me.dash <= 0
		)
		Controls.setButton(
			"overdrive",
			me.s01,
			me.s01Left / math.max(1, me.s01Cd),
			if me.s01Left > 0 then string.format("%.0f", me.s01Left) else "",
			me.s01Left <= 0 or me.s01Tutorial
		)
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
			Menus.confirm()
		end
		local ok, err = pcall(frame, dt)
		return if ok then "" else tostring(err), EnemyView.count()
	end
	hook.Parent = script.Parent
	-- Story scenes on demand (DD-075): play one, or hold it at a moment to look at the frame.
	local storyHook = Instance.new("BindableFunction")
	storyHook.Name = "SwarmStoryHook"
	storyHook.OnInvoke = function(what, t)
		if what == "intro" then
			Story.intro(function() end)
		elseif what == "home" then
			Story.returnHome(t or "O01", function() end)
		elseif what == "depart" then
			Story.depart(t or "O02", function() end)
		elseif what == "arrival" then
			Story.arrival(Vector3.new(12, 0, -12), function() end)
		elseif what == "seek" then
			Story.seek(t)
		elseif what == "skip" then
			Story.seek(nil)
		end
		return Story.active()
	end
	storyHook.Parent = script.Parent
end

print("[SWARMFALL] client ready", Defs.Version)
