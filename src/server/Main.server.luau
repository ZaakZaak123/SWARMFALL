--!nonstrict
-- Server glue: camp -> squad base -> run -> results. Owns characters, validates every remote, feeds the pure
-- simulation (Sim/World), replicates its state (15 Hz packed snapshots) and events (batched),
-- and settles meta progression (Profile) at the end of each run.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local AnalyticsService = game:GetService("AnalyticsService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Codec = require(Shared:WaitForChild("Codec"))
local Maps = require(Shared:WaitForChild("Maps"))
local Ops = require(Shared:WaitForChild("Ops"))
local World = require(script.Parent.Sim.World)
local Arena = require(script.Parent.Arena)
local ArtLoader = require(script.Parent.ArtLoader)
local Profile = require(script.Parent.Profile)
local Outposts = require(script.Parent.Outposts)
local Home = require(script.Parent.Home)
local Meta = require(Shared:WaitForChild("Meta"))
local Showcase = require(Shared:WaitForChild("Showcase"))
local Squads = require(script.Parent.Squads)
local ShelterRooms = require(script.Parent.ShelterRooms)
local shelterRooms = ShelterRooms.new()
local PhysicsService = game:GetService("PhysicsService")
pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, "Survivors")
PhysicsService:CollisionGroupSetCollidable("Survivors", "Survivors", false)

Players.CharacterAutoLoads = false

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name: string)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local inputRemote = remote(Codec.Remotes.Input)
local stateRemote = remote(Codec.Remotes.State)
local eventsRemote = remote(Codec.Remotes.Events)
local profileRemote = remote(Codec.Remotes.Profile)
local socialRemote = remote(Codec.Remotes.Social)
remotes.Parent = ReplicatedStorage

local SNAPSHOT_RATE = 15
local SQUAD_GATHER = 25 -- others on the base are not ready yet: time to join in (DD-052)
local JOIN_GRACE = 15 -- a player who just arrived gets at least this long before the drop
local STRIKE_DELAY = 5 -- first turret built -> the swarm comes (the build animation plays meanwhile)
local RESULTS_TIMEOUT = 60

-- Server roles (DD-053) -------------------------------------------------------------------------------
-- Public servers are camps (HUB): everyone meets, shows off, forms squads; nobody fights there. A squad
-- that launches drops into its own reserved server — a session: the squad's base (LOBBY) and its runs
-- (RUN), exactly the old one-squad server. Studio has no teleports: the camp turns into the session in
-- place and back («В ЛАГЕРЬ»).
local IS_SESSION = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local TELEPORTS = not RunService:IsStudio()
local SESSION_WAIT = 20 -- a session waits this long for the whole squad before it starts anyway
local squads = Squads.new()
local hubSwap = nil -- the squad whose lobby a camp handler is acting on
local sessionHostId: number? = nil -- the squad host of a session (its base and turrets)
local sessionPlan = nil -- { members = {userId}, autostart, since } until the session's first run

-- Server state ----------------------------------------------------------------------------------------
local mode = if IS_SESSION then "LOBBY" else "HUB" -- HUB | LOBBY | RUN
ReplicatedStorage:SetAttribute("ServerRole", if IS_SESSION then "SESSION" else "HUB")
print(string.format("[SWARMFALL] role %s  place %d  job %s", if IS_SESSION then "SESSION" else "HUB", game.PlaceId, game.JobId))
-- mode: "hunt" (story operations) | "siege" (host's outpost) | "raid" (lobby.target, chosen by the host)
local lobby = {
	ready = {},
	weapon = {},
	countdown = nil :: number?,
	op = "O01",
	threat = 1,
	mode = "hunt",
	target = nil,
	candidates = nil,
	hold = false,
	strikeAt = nil :: number?,
}
local serverLobby = lobby -- `lobby` is swapped to a camp squad while its handlers run

-- Anomaly of the day (DD-041): hunts from the third one on, and sieges. First hunts stay readable.
local function todaysAnomaly()
	return Meta.anomalyFor(Meta.dayIndex(os.time()))
end
local joinOrder: { Player } = {}
local world = nil
local runId = ""
local participants: { [number]: Player } = {}
local tracking: { [Player]: { x: number, z: number, y: number } } = {}
local continueVotes: { [Player]: boolean } = {}
local rewards: { [number]: any } = {}
local settled = false
local resultsClock = 0
local snapshotClock = 0
local buckets: { [Player]: { tokens: number, t: number } } = {}
local rejected = 0
local seedCounter = os.time() % 100000
local builtMap = nil

Arena.onClear = Home.build
local function buildArena(mapId: string)
	if builtMap ~= mapId then
		builtMap = mapId
		Arena.build(Maps.get(mapId)) -- clears all terrain; Arena.onClear rebuilds the grove's at once
	end
end

-- One server, two lights (DD-057): the grove's afternoon between runs, the arena's during a run.
local function setLight(home: boolean)
	if home then
		Home.lighting()
	else
		Home.clearClouds()
		Arena.lighting(Maps.get(builtMap or "MAP_REACTOR_YARD").theme)
	end
end
-- Mesh art first (bounded wait): the arena prefers it and falls back to primitives per asset.
ArtLoader.load(15)
buildArena(Ops.get(lobby.op).map)
setLight(true)

-- Helpers ---------------------------------------------------------------------------------------------
local function finite(n): boolean
	return type(n) == "number" and n == n and n > -1e6 and n < 1e6
end

local function allow(player: Player): boolean
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { tokens = 60, t = now }
		buckets[player] = b
	end
	b.tokens = math.min(60, b.tokens + (now - b.t) * 45)
	b.t = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function host(): Player?
	if hubSwap then
		return hubSwap.host
	end
	if sessionHostId then
		local h = Players:GetPlayerByUserId(sessionHostId)
		if h then
			return h
		end
	end
	for _, p in joinOrder do
		if p.Parent then
			return p
		end
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function clearCharacter(player: Player)
	if player.Character then
		player.Character:Destroy()
		player.Character = nil
	end
end

local function pushProfile(player: Player)
	local pub = Profile.public(player)
	if pub and player.Parent then
		profileRemote:FireClient(player, pub)
	end
end
Profile.onChanged(pushProfile)
Profile.onChanged(function(player)
	Outposts.publish(player)
end)

local function prepareCharacter(player: Player, x: number, z: number, facing: number?)
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn("[SWARMFALL] LoadCharacter failed", err)
		return
	end
	local char = player.Character
	if not char then
		return
	end
	local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
	local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not hum or not root then
		return
	end
	local ff = char:FindFirstChildOfClass("ForceField")
	if ff then
		ff:Destroy()
	end
	hum.MaxHealth = 100
	hum.Health = 100
	hum.WalkSpeed = Defs.Player.Speed
	hum.UseJumpPower = true
	hum.JumpPower = 0
	hum.AutoRotate = false
	hum.BreakJointsOnDeath = true
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Survivors"
		end
	end
	char:PivotTo(CFrame.new(x, 3.2, z) * CFrame.Angles(0, facing or 0, 0))
	tracking[player] = { x = x, z = z, y = 3.2 }
end

-- Onboarding funnel (DD-052): where new players drop off, step by step, in the Creator Dashboard.
local FUNNEL = {
	"Вошёл",
	"Первая вылазка",
	"Первая карточка",
	"Первая победа",
	"Мастерская",
	"Первая оборона бура",
	"Вторая вылазка",
}
local funnel: { [Player]: { [number]: boolean } } = {}
local function funnelStep(player: Player, step: number)
	local done = funnel[player]
	if not done or done[step] then
		return
	end
	done[step] = true
	pcall(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, player, step, FUNNEL[step])
end

-- Run lifecycle ---------------------------------------------------------------------------------------
local function startRun()
	local infos = {}
	table.clear(participants)
	for _, player in Players:GetPlayers() do
		if lobby.ready[player] then
			local weapon = lobby.weapon[player] or "W_ARC_RIFLE"
			if not Profile.ownsWeapon(player, weapon) then
				weapon = "W_ARC_RIFLE"
			end
			local perks = {}
			local data = Profile.get(player)
			if data then
				for id, r in data.perks do
					perks[id] = r
				end
			end
			table.insert(infos, {
				id = player.UserId,
				name = player.DisplayName,
				weapon = weapon,
				perks = perks,
				s01 = data ~= nil and data.s01 == true,
				firstHunt = data ~= nil and ((data.wins_by_op or {}).O01 or 0) == 0,
				form = Profile.equippedForm(player, weapon),
				tech = if data then table.clone(data.tech) else {},
				loadout = Profile.loadoutFor(player, weapon),
				s01Spec = Profile.s01Spec(player),
			})
			participants[player.UserId] = player
			if lobby.mode == "hunt" and lobby.op == "O01" then
				funnelStep(player, 2)
			elseif lobby.mode == "hunt" and lobby.op == "O02" then
				funnelStep(player, 7)
			end
		end
	end
	if #infos == 0 then
		return
	end
	buildArena(Ops.get(lobby.op).map)
	seedCounter += 1
	runId = HttpService:GenerateGUID(false)
	-- Repeat variant when the host has already won this operation (story first attempt stays scripted).
	local hostPlayer = host()
	local hostData = hostPlayer and Profile.get(hostPlayer)
	local replay = hostData ~= nil and hostData.wins_by_op ~= nil and (hostData.wins_by_op[lobby.op] or 0) > 0
	local opts = { seed = seedCounter * 7919 + 13, players = infos, op = lobby.op, threat = lobby.threat, replay = replay }
	-- the first voluntary defence of the drill is the short lesson (DD-057: no longer forced)
	local firstDefence = lobby.mode == "strike" or (lobby.mode == "siege" and hostData and not hostData.tut.strike)
	if firstDefence and hostData then
		opts.opDef = Ops.makeFirstStrike()
		opts.structures = hostData.outpost.slots
		opts.threat = 1
	elseif lobby.mode == "siege" and hostData then
		local f = Profile.features(hostData)
		opts.opDef = Ops.makeSiege(if f.siegeLadder then hostData.outpost.siege else 1)
		opts.structures = hostData.outpost.slots
		opts.threat = 1
		opts.anomaly = todaysAnomaly()
	elseif lobby.mode == "raid" and lobby.target then
		opts.opDef = Ops.makeRaid(lobby.target)
		opts.threat = 1
	elseif Ops.get(lobby.op).index >= 3 then
		opts.anomaly = todaysAnomaly()
	end
	-- The outpost is in this crater: the host's turrets fight in hunts too (DD-052).
	if lobby.mode == "hunt" and hostData and Ops.get(lobby.op).map == "MAP_REACTOR_YARD" then
		opts.structures = hostData.outpost.slots
	end
	world = World.new(opts)
	setLight(false)
	mode = "RUN"
	lobby.countdown = nil
	lobby.hold = false
	lobby.strikeAt = nil
	if lobby.mode == "strike" then
		lobby.mode = "hunt"
	end
	table.clear(lobby.ready)
	table.clear(continueVotes)
	table.clear(rewards)
	settled = false
	resultsClock = 0
	for _, p in world.playerList do
		local player = participants[p.id]
		if player then
			task.spawn(prepareCharacter, player, p.x, p.z)
		end
	end
	print(string.format("[SWARMFALL] run start %s threat=%d seed=%d players=%d", world.op.id, lobby.threat, world.seed, #infos))
end

local function settle()
	if settled or not world or not world.result then
		return
	end
	settled = true
	local r = world.result
	print(string.format("[SWARMFALL] run end %s %s t=%.1f kills=%d", if r.victory then "VICTORY" else "DEFEAT", r.reason, r.time, r.kills))
	for userId, player in participants do
		if player.Parent then
			rewards[userId] = Profile.grantRun(player, runId, r, world.op.id, world.threat)
			if r.victory and world.op.id == "O01" then
				funnelStep(player, 4)
			elseif world.op.id == "STRIKE" then
				funnelStep(player, 6)
			end
		end
	end
	-- Raids: tell the owner what happened to their outpost (they may be offline), refresh targets.
	if r.mode == "raid" and world.op.target then
		local attackers = {}
		local delta = 0
		for userId, player in participants do
			table.insert(attackers, player)
			local rw = rewards[userId]
			if rw and rw.rating then
				delta = math.max(delta, rw.rating.delta)
			end
		end
		Outposts.report(world.op.target, attackers, r.victory, delta)
		lobby.target = nil
		lobby.candidates = nil
		lobby.mode = "hunt"
	end
	for _, player in participants do
		Outposts.publish(player, true)
	end
end

-- Between hunts the squad is on its base (DD-052): the yard between the dropship and the drill. They
-- arrive facing the drill, with the armory left, the launch pad behind and the outpost ahead.
-- (DD-057: now the shelter in the grove, Meta.HomeOrigin; coordinates below are relative to it)
local LOBBY_SPOTS = { { 0, -4 }, { -5, -6 }, { 5, -6 }, { 0, -9 } }
local HOME = Meta.HomeOrigin
local LOBBY_FACING = math.pi
local function toHub(player: Player)
	if (mode ~= "LOBBY" and mode ~= "HUB") or not player.Parent then
		return
	end
	local i = table.find(Players:GetPlayers(), player) or 1
	if mode == "HUB" then
		shelterRooms:add(player.UserId)
		-- the camp can hold a crowd: a loose ring in the yard
		local a = (i - 1) * 2.4
		local r = if i == 1 then 0 else 4 + (i % 3) * 3
		prepareCharacter(player, HOME.X + math.cos(a) * r, HOME.Z - 4 + math.sin(a) * r * 0.6, LOBBY_FACING)
		return
	end
	local spot = LOBBY_SPOTS[(i - 1) % #LOBBY_SPOTS + 1]
	prepareCharacter(player, HOME.X + spot[1], HOME.Z + spot[2], LOBBY_FACING)
end

local function backToLobby()
	settle()
	-- «Продолжить»: after a first win the lobby pre-selects the next story operation. Nothing starts
	-- until the squad presses В БОЙ again (GDD §3.2).
	if world and world.result and world.result.victory then
		local h = host()
		for _, nextId in world.op.unlocks do
			if Ops[nextId] and h and Profile.maxThreat(h, nextId) >= 1 and nextId ~= "CA01" then
				lobby.op = nextId
				lobby.threat = 1
				buildArena(Ops.get(nextId).map)
				break
			end
		end
	end
	world = nil
	mode = "LOBBY"
	setLight(true)
	table.clear(participants)
	table.clear(tracking)
	for _, player in Players:GetPlayers() do
		clearCharacter(player)
		task.spawn(toHub, player)
	end
end

-- Camp (DD-053) ---------------------------------------------------------------------------------------
local function social(player: Player, kind: string, data)
	if player.Parent then
		socialRemote:FireClient(player, kind, data)
	end
end

-- The hunt a hunter's own squad starts on: their next unwon story hunt.
local function nextOpFor(player: Player): string
	local d = Profile.get(player)
	if not d then
		return "O01"
	end
	local last = "O01"
	for _, id in Ops.Order do
		if id ~= "CA01" and (d.ops[id] or 0) >= 1 then
			last = id
			if ((d.wins_by_op or {})[id] or 0) == 0 then
				return id
			end
		end
	end
	return last
end

local function canPlay(player: Player, sq): boolean
	if sq.mode == "hunt" then
		return Profile.maxThreat(player, sq.op) >= 1
	end
	return Profile.get(player) ~= nil
end

local function teleportData(sq)
	local data = {
		v = 1,
		host = sq.host.UserId,
		op = sq.op,
		threat = sq.threat,
		mode = sq.mode,
		target = if sq.target then sq.target.uid else nil,
		members = {},
		weapons = {},
		autostart = true,
	}
	for _, m in sq.members do
		table.insert(data.members, m.UserId)
		data.weapons[tostring(m.UserId)] = sq.weapon[m] or "W_ARC_RIFLE"
	end
	return data
end

-- Studio: the camp becomes this squad's session in place.
local function enterSessionInPlace(sq)
	-- may run inside a swapped camp handler: write to the server's own lobby
	lobby = serverLobby
	hubSwap = nil
	lobby.op, lobby.threat, lobby.mode, lobby.target = sq.op, sq.threat, sq.mode, sq.target
	table.clear(lobby.ready)
	table.clear(lobby.weapon)
	for _, m in sq.members do
		lobby.ready[m] = true
		lobby.weapon[m] = sq.weapon[m] or "W_ARC_RIFLE"
	end
	sessionHostId = sq.host.UserId
	for _, m in table.clone(sq.members) do
		squads:remove(m)
	end
	mode = "LOBBY"
	startRun()
end

-- A squad drops into its own reserved server (or, in Studio, this one).
local function launch(sq)
	if sq.launching then
		return
	end
	-- whoever is not ready when the countdown ends stays in the camp
	for _, m in table.clone(sq.members) do
		if not sq.ready[m] then
			squads:solo(m, nextOpFor(m))
		end
	end
	if #sq.members == 0 then
		return
	end
	sq.launching = true
	sq.countdown = nil
	if not TELEPORTS then
		enterSessionInPlace(sq)
		return
	end
	local members = table.clone(sq.members)
	for _, m in members do
		social(m, "launch", Ops.get(sq.op).name)
	end
	print(string.format("[SWARMFALL] launch squad %d: %d hunters, %s %s", sq.id, #members, sq.mode, sq.op))
	task.spawn(function()
		local options = Instance.new("TeleportOptions")
		options.ShouldReserveServer = true
		options:SetTeleportData(teleportData(sq))
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, members, options)
		if not ok then
			warn("[SWARMFALL] launch failed", err)
			sq.launching = false
			table.clear(sq.ready)
			for _, m in members do
				social(m, "error", "Выход не удался — попробуй ещё раз")
			end
		end
	end)
end

TeleportService.TeleportInitFailed:Connect(function(player: Player, _result, message)
	warn("[SWARMFALL] teleport failed", player.Name, message)
	local sq = squads:squadOf(player)
	if sq then
		sq.launching = false
		table.clear(sq.ready)
	end
	social(player, "error", "Выход не удался — попробуй ещё раз")
end)

-- «В ЛАГЕРЬ»: back to a public camp server (live) or, in Studio, the whole server back to the camp.
local function toCamp(player: Player): boolean
	if TELEPORTS then
		if not IS_SESSION then
			return false
		end
		task.spawn(function()
			local ok = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player })
			if not ok then
				social(player, "error", "Не удалось вернуться в лагерь")
			end
		end)
		return true
	end
	if mode ~= "LOBBY" then
		return false
	end
	mode = "HUB"
	setLight(true)
	sessionHostId = nil
	table.clear(lobby.ready)
	lobby.countdown = nil
	lobby.strikeAt = nil
	buildArena("MAP_REACTOR_YARD")
	for _, pl in Players:GetPlayers() do
		squads:solo(pl, nextOpFor(pl))
		clearCharacter(pl)
		task.spawn(toHub, pl)
	end
	return true
end

-- Session: the squad arrives with a plan (teleport data). Only ids and choices travel; everything is
-- checked against the host's profile here (teleport data passes through clients).
local function sessionJoin(player: Player)
	if not IS_SESSION or sessionPlan then
		return
	end
	local ok, jd = pcall(player.GetJoinData, player)
	local data = ok and jd and jd.TeleportData
	if type(data) ~= "table" or not tonumber(data.host) then
		return
	end
	sessionHostId = tonumber(data.host)
	sessionPlan = { members = {}, since = os.clock(), data = data }
	print(string.format("[SWARMFALL] session plan from %s: host %d, %s %s", player.Name, sessionHostId, tostring(data.mode), tostring(data.op)))
	for _, uid in (if type(data.members) == "table" then data.members else {}) do
		if tonumber(uid) then
			table.insert(sessionPlan.members, tonumber(uid))
		end
	end
end

local function sessionStart()
	local plan = sessionPlan
	sessionPlan = nil
	local d = plan.data
	local h = host()
	if not h then
		return
	end
	local opId = if type(d.op) == "string" and table.find(Ops.Order, d.op) and Profile.maxThreat(h, d.op) >= 1 then d.op else "O01"
	lobby.op = opId
	lobby.threat = math.clamp(math.floor(tonumber(d.threat) or 1), 1, math.max(1, Profile.maxThreat(h, opId)))
	local f = Profile.features(Profile.get(h) or {})
	local m = d.mode
	lobby.mode = if m == "siege" and f.siege then "siege" elseif m == "strike" and f.outpost then "strike" elseif m == "raid" and f.raids then "raid" else "hunt"
	if lobby.mode == "raid" then
		lobby.target = if tonumber(d.target) then Outposts.find(tonumber(d.target)) else nil
		if not lobby.target then
			lobby.mode = "hunt"
		end
	end
	buildArena(Ops.get(lobby.op).map)
	for _, player in Players:GetPlayers() do
		local w = type(d.weapons) == "table" and d.weapons[tostring(player.UserId)]
		lobby.weapon[player] = if type(w) == "string" and Defs.Weapons[w] then w else "W_ARC_RIFLE"
		lobby.ready[player] = true
	end
	if d.autostart then
		startRun()
	end
end

-- A player who has never won O01 skips the lobby: seconds after joining they are already shooting
-- (DD-024). Only when nobody else is waiting in the lobby with other plans.
local function isNewcomer(player: Player): boolean
	local d = Profile.get(player)
	return d ~= nil and not (d.wins_by_op and (d.wins_by_op.O01 or 0) > 0) and (d.ops.O01 or 1) < 2
end

local function autoDeploy(player: Player)
	for _ = 1, 40 do
		if Profile.get(player) or not player.Parent then
			break
		end
		task.wait(0.25)
	end
	if not player.Parent or not isNewcomer(player) then
		return
	end
	if not funnel[player] then
		funnel[player] = {}
		funnelStep(player, 1)
	end
	if mode == "HUB" then
		local sq = squads:squadOf(player) or squads:solo(player, "O01")
		if #sq.members == 1 and not sq.launching then
			sq.op, sq.mode, sq.threat = "O01", "hunt", 1
			sq.weapon[player] = "W_ARC_RIFLE"
			sq.ready[player] = true
			launch(sq)
		end
		return
	end
	if mode ~= "LOBBY" or IS_SESSION then
		return
	end
	for _, other in Players:GetPlayers() do
		if other ~= player and not isNewcomer(other) then
			return
		end
	end
	lobby.op = "O01"
	lobby.threat = 1
	lobby.mode = "hunt"
	buildArena(Ops.get("O01").map)
	lobby.weapon[player] = "W_ARC_RIFLE"
	lobby.ready[player] = true
	lobby.countdown = math.min(lobby.countdown or 2, 2)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		for _ = 1, 40 do
			if Profile.get(player) or not player.Parent then
				break
			end
			task.wait(0.25)
		end
		if player.Parent and Profile.get(player) then
			Outposts.claim(player)
			local sq = squads:squadOf(player)
			if sq and #sq.members == 1 and not sq.launching then
				sq.op = nextOpFor(player)
			end
		end
	end)
	if mode == "HUB" then
		squads:solo(player, "O01")
	end
	sessionJoin(player)
	task.wait(1)
	if mode == "LOBBY" or mode == "HUB" then
		toHub(player)
		if lobby.countdown then
			lobby.countdown = math.max(lobby.countdown, JOIN_GRACE)
		end
		autoDeploy(player)
	end
end)
for _, player in Players:GetPlayers() do
	if mode == "HUB" then
		squads:solo(player, nextOpFor(player))
	end
	sessionJoin(player)
	task.spawn(function()
		toHub(player)
		autoDeploy(player)
	end)
end

-- Input -----------------------------------------------------------------------------------------------
local handlers = {}

local function lobbyOnly(): boolean
	return mode == "LOBBY" or mode == "HUB"
end

function handlers.ready(player: Player, weapon)
	if not lobbyOnly() or type(weapon) ~= "string" or not Defs.Weapons[weapon] or not Profile.ownsWeapon(player, weapon) then
		return false
	end
	lobby.weapon[player] = weapon
	lobby.ready[player] = true
	local all = true
	for _, p in (if mode == "HUB" then lobby.members else Players:GetPlayers()) do
		if not lobby.ready[p] then
			all = false
		end
	end
	if all then
		if mode == "HUB" then
			launch(lobby)
		else
			startRun()
		end
	elseif not lobby.countdown then
		lobby.countdown = SQUAD_GATHER
	end
	return true
end

function handlers.unready(player: Player)
	if not lobbyOnly() then
		return false
	end
	lobby.ready[player] = nil
	if next(lobby.ready) == nil then
		lobby.countdown = nil
	end
	return true
end

function handlers.weapon(player: Player, weapon)
	if not lobbyOnly() or type(weapon) ~= "string" or not Defs.Weapons[weapon] then
		return false
	end
	lobby.weapon[player] = weapon
	return true
end

function handlers.op(player: Player, opId)
	if not lobbyOnly() or player ~= host() or type(opId) ~= "string" or not table.find(Ops.Order, opId) then
		return false
	end
	if Profile.maxThreat(player, opId) < 1 then
		return false
	end
	lobby.op = opId
	lobby.threat = math.min(lobby.threat, Profile.maxThreat(player, opId))
	if mode ~= "HUB" then
		buildArena(Ops.get(opId).map)
	end
	return true
end

-- Meta (DD-037…DD-041) -------------------------------------------------------------------------------
local function hostOnly(player: Player): boolean
	return lobbyOnly() and player == host()
end

function handlers.mode(player: Player, m)
	if not hostOnly(player) or (m ~= "hunt" and m ~= "siege" and m ~= "raid") then
		return false
	end
	local f = Profile.features(Profile.get(player) or {})
	if (m == "siege" and not f.siege) or (m == "raid" and not f.raids) then
		return false
	end
	lobby.mode = m
	local L = lobby -- a camp squad: the async fill below must land in it, not in the server lobby
	if m == "raid" and not L.candidates then
		L.candidates = {}
		task.spawn(function()
			local list = Outposts.candidates(player)
			L.candidates = {}
			for i, c in list do
				L.candidates[i] = {
					name = c.name,
					rating = c.rating,
					power = Meta.outpostPower(c.slots),
					uid = c.uid,
					rival = c.rival,
				}
			end
			L.candidateData = list
			L.target = list[1]
		end)
	end
	return true
end

function handlers.raidPick(player: Player, index)
	if not hostOnly(player) or not finite(index) or not lobby.candidateData then
		return false
	end
	local c = lobby.candidateData[index]
	if c then
		lobby.target = c
	end
	return c ~= nil
end

function handlers.raidRefresh(player: Player)
	if not hostOnly(player) then
		return false
	end
	lobby.candidates = nil
	return handlers.mode(player, "raid")
end

function handlers.revenge(player: Player, uid)
	if not hostOnly(player) or not Codec.isUserId(uid, RunService:IsStudio()) then
		return false
	end
	local f = Profile.features(Profile.get(player) or {})
	local snap = Outposts.find(uid)
	if not f.raids or not snap then
		return false
	end
	lobby.mode = "raid"
	-- «Ответный вызов» (DD-061): a raid on the raider's snapshot pays the system bonus
	local target = table.clone(snap)
	target.revenge = true
	lobby.target = target
	return true
end

function handlers.tut(player: Player, key)
	return type(key) == "string" and Profile.markTut(player, key)
end

function handlers.hold(player: Player, on)
	if not hostOnly(player) or type(on) ~= "boolean" then
		return false
	end
	lobby.hold = on
	return true
end

function handlers.title(player: Player, id)
	return type(id) == "string" and Profile.setTitle(player, id)
end

function handlers.restore(player: Player, id)
	return lobbyOnly() and type(id) == "string" and Profile.restore(player, id)
end

function handlers.build(player: Player, slot, id)
	if lobbyOnly() and finite(slot) and type(id) == "string" and Profile.build(player, slot, id) then
		funnelStep(player, 5)
		return true
	end
	return false
end

function handlers.upgrade(player: Player, slot)
	return lobbyOnly() and finite(slot) and Profile.upgrade(player, slot)
end

function handlers.sell(player: Player, slot)
	return lobbyOnly() and finite(slot) and Profile.sell(player, slot)
end

function handlers.harvest(player: Player)
	return Profile.collectHarvest(player) > 0
end

function handlers.unlockSpecies(player: Player, kind)
	return type(kind) == "string" and Profile.unlockSpecies(player, kind)
end

function handlers.unlockMutation(player: Player, kind, mut)
	return type(kind) == "string" and type(mut) == "string" and Profile.unlockMutation(player, kind, mut)
end

function handlers.setStrain(player: Player, index, kind, muts)
	if not finite(index) or (kind ~= nil and type(kind) ~= "string") then
		return false
	end
	if muts ~= nil and type(muts) ~= "table" then
		return false
	end
	return Profile.setStrain(player, index, kind, muts)
end

function handlers.threat(player: Player, level)
	if not lobbyOnly() or player ~= host() or not finite(level) or level % 1 ~= 0 then
		return false
	end
	if level < 1 or level > Profile.maxThreat(player, lobby.op) then
		return false
	end
	lobby.threat = level
	return true
end

function handlers.buyPerk(player: Player, id)
	return lobbyOnly() and type(id) == "string" and Profile.buyPerk(player, id)
end

function handlers.buyWeapon(player: Player, id)
	return lobbyOnly() and type(id) == "string" and Profile.buyWeapon(player, id)
end

function handlers.craftModule(player: Player, id)
	return lobbyOnly() and type(id) == "string" and Profile.craftModule(player, id)
end

function handlers.equipModule(player: Player, weaponId, slot, id)
	return lobbyOnly() and type(weaponId) == "string" and type(slot) == "string" and type(id) == "string" and Profile.equipModule(player, weaponId, slot, id)
end

function handlers.s01Branch(player: Player, branch)
	return lobbyOnly() and type(branch) == "string" and Profile.setS01Branch(player, branch)
end

function handlers.buyTech(player: Player, id)
	return lobbyOnly() and type(id) == "string" and Profile.buyTech(player, id)
end

function handlers.craftForm(player: Player, evoId)
	return lobbyOnly() and type(evoId) == "string" and Profile.craftForm(player, evoId)
end

function handlers.equipForm(player: Player, weaponId, evoId)
	return lobbyOnly() and type(weaponId) == "string" and type(evoId) == "string" and Profile.equipForm(player, weaponId, evoId)
end

local function participant(player: Player)
	if mode ~= "RUN" or not world or participants[player.UserId] ~= player then
		return nil
	end
	return world.players[player.UserId]
end

function handlers.aim(player: Player, dx, dz, firing)
	local p = participant(player)
	if not p or not finite(dx) or not finite(dz) or type(firing) ~= "boolean" or dx * dx + dz * dz < 1e-6 then
		return false
	end
	world:setAim(p.id, dx, dz, firing)
	return true
end

function handlers.dash(player: Player, dx, dz)
	local p = participant(player)
	return p ~= nil and finite(dx) and finite(dz) and world:dash(p.id, dx, dz)
end

function handlers.reload(player: Player)
	local p = participant(player)
	if p then
		world:reload(p.id)
	end
	return p ~= nil
end

function handlers.s01(player: Player)
	local p = participant(player)
	return p ~= nil and world:gravihammer(p.id)
end

function handlers.evolve(player: Player)
	local p = participant(player)
	return p ~= nil and world:evolve(p.id)
end

function handlers.choose(player: Player, offerId, index)
	local p = participant(player)
	if p ~= nil and finite(offerId) and finite(index) and index % 1 == 0 and world:choose(p.id, offerId, index) then
		funnelStep(player, 3)
		return true
	end
	return false
end

function handlers.reroll(player: Player)
	local p = participant(player)
	return p ~= nil and world:reroll(p.id)
end

function handlers.banish(player: Player, offerId, index)
	local p = participant(player)
	return p ~= nil and finite(offerId) and finite(index) and index % 1 == 0 and world:banish(p.id, offerId, index)
end

function handlers.pause(player: Player, paused)
	local p = participant(player)
	if not p or type(paused) ~= "boolean" or not world.solo or world.phase ~= "ACTIVE" then
		return false
	end
	if paused and not world.paused then
		world.paused = "MENU"
		world.pauseClock = 0
	elseif not paused and world.paused == "MENU" then
		world.paused = nil
		world:openOffers()
	end
	return true
end

function handlers.continue(player: Player)
	if mode ~= "RUN" or not world or world.phase ~= "RESULTS" then
		return false
	end
	continueVotes[player] = true
	for _, pl in participants do
		if pl.Parent and not continueVotes[pl] then
			return true
		end
	end
	backToLobby()
	return true
end

-- Studio-only testing aid: grant scrap and unlock everything. Never available in live servers.
if RunService:IsStudio() then
	function handlers.devGrant(player: Player)
		local d = Profile.get(player)
		if not d then
			return false
		end
		d.scrap += 5000
		for _, id in Ops.Order do
			d.ops[id] = math.max(d.ops[id] or 0, 3)
		end
		pushProfile(player)
		return true
	end
	function handlers.devLevel(player: Player)
		local p = participant(player)
		if not p then
			return false
		end
		world:gainXp(world.xpNeed - world.xp)
		return true
	end
	function handlers.devGod(player: Player)
		local p = participant(player)
		if not p then
			return false
		end
		p.maxHp = 100000
		p.hp = 100000
		return true
	end
	function handlers.devSpawn(player: Player, kind, count)
		local p = participant(player)
		if not p or type(kind) ~= "string" or not Defs.Enemies[kind] then
			return false
		end
		for i = 1, math.clamp(tonumber(count) or 1, 1, 20) do
			local a = i * 2.4
			world:spawnEnemy(kind, p.x + math.cos(a) * 22, p.z + math.sin(a) * 22, 1)
		end
		return true
	end
	function handlers.devMeta(player: Player)
		local d = Profile.get(player)
		if not d then
			return false
		end
		d.wins_by_op = d.wins_by_op or {}
		for _, id in { "O01", "O02", "O03", "O04" } do
			d.wins_by_op[id] = math.max(1, d.wins_by_op[id] or 0)
			d.ops[id] = math.max(d.ops[id] or 0, 2)
		end
		d.ops.O05 = math.max(d.ops.O05 or 0, 1)
		d.scrap += 6000
		for _, k in Meta.SpeciesOrder do
			d.research[k] = (d.research[k] or 0) + 400
		end
		pushProfile(player)
		return true
	end
	-- the hero's fall (DD-082) without waiting for the swarm: no saving shield, one big hit
	function handlers.devDie(player: Player)
		local p = participant(player)
		if not p or not world then
			return false
		end
		p.newbie = false
		p.iframeUntil, p.graceUntil = 0, 0
		world.t = math.max(world.t, Defs.Run.SafeSeconds + 0.1)
		world:hurtPlayer(p, p.hp + p.maxHp * 10, p.x + 4, p.z, nil)
		return true
	end
	function handlers.devSkip(player: Player, seconds)
		if not world or not finite(seconds) then
			return false
		end
		world.t = math.max(world.t, seconds)
		return true
	end
end

-- Camp handlers (DD-053) ------------------------------------------------------------------------------
local function campOnly(): boolean
	return mode == "HUB"
end

function handlers.join(player: Player, id)
	if not campOnly() or not finite(id) then
		return false
	end
	local ok, why = squads:join(player, id)
	if not ok then
		social(player, "error", why or "Не получилось")
		return false
	end
	local sq = squads:squadOf(player)
	for _, m in sq.members do
		if m ~= player then
			social(m, "joined", player.DisplayName)
		end
	end
	return true
end

function handlers.leave(player: Player)
	if not campOnly() then
		return false
	end
	local sq = squads:squadOf(player)
	if not sq or #sq.members <= 1 or sq.launching then
		return false
	end
	squads:leave(player, nextOpFor(player))
	return true
end

function handlers.recruit(player: Player, on)
	local sq = campOnly() and squads:squadOf(player)
	if not sq or sq.host ~= player or type(on) ~= "boolean" then
		return false
	end
	sq.open = on
	return true
end

function handlers.invite(player: Player, uid)
	local sq = campOnly() and squads:squadOf(player)
	local target = Codec.isUserId(uid, RunService:IsStudio()) and Players:GetPlayerByUserId(uid)
	if not sq or not target or target == player or #sq.members >= Squads.Max then
		return false
	end
	if sq.host ~= player then
		-- a member asks: the invite still comes from the squad
		sq = squads:squadOf(player)
	end
	sq.invited[target.UserId] = true
	social(target, "invite", {
		from = player.DisplayName,
		squad = sq.id,
		title = Showcase.squadTitle(sq.mode, Ops.get(sq.op).name, Ops.get(sq.op).index, nil),
	})
	return true
end

function handlers.match(player: Player)
	if not campOnly() then
		return false
	end
	local result, sq = squads:match(player, canPlay)
	if result == "joined" and sq then
		for _, m in sq.members do
			if m ~= player then
				social(m, "joined", player.DisplayName)
			end
		end
	end
	social(player, "match", result)
	return true
end

function handlers.like(player: Player, uid)
	local owner = Codec.isUserId(uid, RunService:IsStudio()) and Players:GetPlayerByUserId(uid)
	if
		not campOnly()
		or not owner
		or shelterRooms:owner(player.UserId) ~= uid
		or not Profile.like(player, owner, Meta.dayIndex(os.time()))
	then
		return false
	end
	social(owner, "liked", player.DisplayName)
	return true
end

function handlers.visit(player: Player, uid)
	local owner = Codec.isUserId(uid, RunService:IsStudio()) and Players:GetPlayerByUserId(uid)
	local sq = squads:squadOf(player)
	local targetSquad = owner and squads:squadOf(owner)
	if
		not campOnly()
		or not owner
		or not Profile.get(owner)
		or not Profile.get(player)
		or (sq and sq.launching)
		or (targetSquad and targetSquad.launching)
	then
		return false
	end
	if shelterRooms:owner(player.UserId) == uid then
		return true
	end
	if not shelterRooms:visit(player.UserId, uid) then
		return false
	end
	local root = rootOf(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		player.Character:PivotTo(CFrame.new(HOME.X, 3.2, HOME.Z - 8) * CFrame.Angles(0, LOBBY_FACING, 0))
	end
	if owner ~= player then
		social(owner, "visitor", player.DisplayName)
	end
	return true
end

function handlers.camp(player: Player)
	if mode == "RUN" and world and world.phase == "RESULTS" then
		settle()
		if not TELEPORTS then
			backToLobby()
		end
	end
	return toCamp(player)
end

function handlers.profile(player: Player)
	pushProfile(player)
	return true
end

inputRemote.OnServerEvent:Connect(function(player: Player, action, ...)
	if not allow(player) or type(action) ~= "string" then
		rejected += 1
		return
	end
	local handler = handlers[action]
	if not handler or select("#", ...) > 3 then
		rejected += 1
		return
	end
	local ok, accepted
	if mode == "HUB" and squads:squadOf(player) then
		-- camp: lobby handlers act on the player's own squad
		local saved = lobby
		lobby = squads:squadOf(player)
		hubSwap = lobby
		ok, accepted = pcall(handler, player, ...)
		lobby = saved
		hubSwap = nil
	else
		ok, accepted = pcall(handler, player, ...)
	end
	if not ok then
		warn("[SWARMFALL] handler error", action, accepted)
		rejected += 1
	elseif accepted == false then
		rejected += 1
	end
end)

-- Movement authority --------------------------------------------------------------------------------
local function syncCharacters(dt: number)
	for userId, player in participants do
		local p = world.players[userId]
		local root = rootOf(player)
		local track = tracking[player]
		if not p or not root or not track then
			continue
		end
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			if not p.alive then
				if p.downedUntil then
					-- Downed: stays on the floor where the squad can reach them.
					hum.WalkSpeed = 0
					hum.Health = 1
				elseif hum.Health > 0 then
					hum.Health = 0
				end
				continue
			end
			if hum.WalkSpeed ~= Defs.Player.Speed then
				hum.WalkSpeed = Defs.Player.Speed
			end
			hum.MaxHealth = p.maxHp
			hum.Health = math.max(1, p.hp)
		end
		local pos = root.Position
		local dx, dz = pos.X - track.x, pos.Z - track.z
		local dist = math.sqrt(dx * dx + dz * dz)
		local allowed = Defs.Player.Speed * dt * 1.6 + 1
		if world.t <= p.dashUntil + 0.15 then
			allowed += Defs.Player.DashDistance / Defs.Player.DashTime * dt * 1.5 + 2
		end
		if world.paused then
			allowed = 1.5
		end
		if not (finite(pos.X) and finite(pos.Z)) or dist > allowed or pos.Y < -5 or pos.Y > 40 then
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.new(track.x, math.max(track.y, 3), track.z) * root.CFrame.Rotation
		else
			track.x, track.z, track.y = pos.X, pos.Z, pos.Y
			world:setPlayerPosition(userId, pos.X, pos.Z)
		end
	end
end

-- Replication ----------------------------------------------------------------------------------------
local function lobbyInfo(L, h, members, shared)
	L = L or lobby
	h = h or host()
	local list = {}
	for _, player in members or Players:GetPlayers() do
		table.insert(list, {
			id = player.UserId,
			name = player.DisplayName,
			ready = L.ready[player] == true,
			weapon = L.weapon[player] or "W_ARC_RIFLE",
		})
	end
	local lobby = L
	local hostData = h and Profile.get(h)
	shared = shared or { boards = Outposts.boards(), online = Outposts.online() }
	return {
		players = list,
		countdown = lobby.countdown,
		op = lobby.op,
		map = Ops.get(lobby.op).map,
		threat = lobby.threat,
		host = h and h.UserId or 0,
		mode = lobby.mode,
		siege = if hostData then hostData.outpost.siege else 1,
		outpost = if hostData then hostData.outpost.slots else nil,
		shelter = if mode == "LOBBY"
				and hostData
				and h
			then Showcase.build(
				h.UserId,
				h.DisplayName,
				hostData,
				lobby.weapon[h] or "W_ARC_RIFLE",
				Profile.equippedForm(h, lobby.weapon[h] or "W_ARC_RIFLE")
			)
			else nil,
		target = if lobby.target
			then {
				name = lobby.target.name,
				rating = lobby.target.rating,
				uid = lobby.target.uid,
				power = Meta.outpostPower(lobby.target.slots),
				slots = lobby.target.slots,
				brood = lobby.target.brood,
			}
			else nil,
		candidates = lobby.candidates,
		anomaly = todaysAnomaly().id,
		boards = shared.boards,
		online = shared.online,
		hold = lobby.hold,
		strike = if lobby.strikeAt then math.max(0, lobby.strikeAt - os.clock()) else nil,
		camp = mode == "LOBBY" and (IS_SESSION or not TELEPORTS), -- «В ЛАГЕРЬ» is possible
	}
end

-- The camp in one table: every squad (lobby-shaped, so the base UI reads it) and every hunter's showcase.
local function hubInfo()
	local shared = { boards = Outposts.boards(), online = Outposts.online() }
	local list = {}
	for _, sq in squads:all() do
		local info = lobbyInfo(sq, sq.host, sq.members, shared)
		local op = Ops.get(sq.op)
		info.id = sq.id
		info.open = sq.open
		info.launching = sq.launching
		info.title = Showcase.squadTitle(sq.mode, op.name, op.index, info.siege)
		info.outpost = nil -- the camp shows each hunter their own outpost
		table.insert(list, info)
	end
	local hunters = {}
	for _, player in Players:GetPlayers() do
		local d = Profile.get(player)
		if d then
			local sq = squads:squadOf(player)
			local weapon = (sq and sq.weapon[player]) or "W_ARC_RIFLE"
			if not Profile.ownsWeapon(player, weapon) then
				weapon = "W_ARC_RIFLE"
			end
			local entry = Showcase.build(player.UserId, player.DisplayName, d, weapon, Profile.equippedForm(player, weapon))
			entry.squad = sq and sq.id or 0
			entry.room = shelterRooms:owner(player.UserId)
			table.insert(hunters, entry)
		end
	end
	return { squads = list, hunters = hunters, featured = Showcase.featured(hunters, math.floor(os.time() / 120)) }
end

local function publish()
	if mode == "RUN" and world then
		local run = world:publicState()
		local votes = {}
		for player in continueVotes do
			table.insert(votes, player.UserId)
		end
		local myRewards = {}
		for id, r in rewards do
			myRewards[tostring(id)] = r
		end
		stateRemote:FireAllClients(world:encodeEnemies(), {
			mode = "RUN",
			run = run,
			votes = votes,
			rewards = myRewards,
			rejected = if RunService:IsStudio() then rejected else nil,
			camp = IS_SESSION or not TELEPORTS, -- results may offer «В ЛАГЕРЬ»
			simMs = world.stats.lastTickMs,
		})
	elseif mode == "HUB" then
		stateRemote:FireAllClients(nil, { mode = "HUB", hub = hubInfo() })
	else
		stateRemote:FireAllClients(nil, { mode = "LOBBY", lobby = lobbyInfo() })
	end
end

local fallClock = 0
RunService.Heartbeat:Connect(function(dt)
	-- safety net at home: anyone who drops under the shelter ground is put back in the yard
	fallClock += dt
	if fallClock > 1 and (mode == "HUB" or mode == "LOBBY") then
		fallClock = 0
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root and root.Position.Y < -30 then
				root.AssemblyLinearVelocity = Vector3.zero
				task.spawn(toHub, player)
			end
		end
	end
	if mode == "HUB" then
		for _, sq in squads:all() do
			if sq.launching then
				continue
			end
			if sq.strikeAt and os.clock() >= sq.strikeAt then
				sq.strikeAt = nil
				sq.mode = "strike"
				for _, m in sq.members do
					sq.ready[m] = true
				end
				launch(sq)
			elseif sq.countdown and not sq.hold then
				sq.countdown -= dt
				if sq.countdown <= 0 then
					launch(sq)
				end
			end
		end
	elseif mode == "LOBBY" and sessionPlan then
		-- a session waits for its squad (and their profiles), then drops
		local all = true
		for _, uid in sessionPlan.members do
			local pl = Players:GetPlayerByUserId(uid)
			if not pl or not Profile.get(pl) then
				all = false
			end
		end
		if (all and host() and Profile.get(host() :: Player)) or os.clock() - sessionPlan.since > SESSION_WAIT then
			sessionStart()
		end
	elseif mode == "LOBBY" then
		if lobby.strikeAt and os.clock() >= lobby.strikeAt then
			-- Everyone on the base defends: the whole server is pulled into «Первый натиск».
			lobby.mode = "strike"
			for _, player in Players:GetPlayers() do
				if Profile.get(player) then
					lobby.ready[player] = true
					lobby.weapon[player] = lobby.weapon[player] or "W_ARC_RIFLE"
				end
			end
			startRun()
		elseif lobby.countdown and not lobby.hold then
			lobby.countdown -= dt
			if lobby.countdown <= 0 then
				startRun()
			end
		end
	elseif world then
		if world.phase ~= "RESULTS" then
			syncCharacters(dt)
		end
		world:step(dt)
		local events = world:drainEvents()
		if #events > 0 then
			eventsRemote:FireAllClients(events)
		end
		if world.phase == "RESULTS" then
			settle()
			resultsClock += dt
			if resultsClock > RESULTS_TIMEOUT then
				backToLobby()
			end
		end
	end
	snapshotClock += dt
	local interval = if mode == "RUN" then 1 / SNAPSHOT_RATE else 0.25
	if snapshotClock >= interval then
		snapshotClock = 0
		publish()
	end
end)

Players.PlayerAdded:Connect(function(player)
	buckets[player] = nil
	table.insert(joinOrder, player)
end)
for _, player in Players:GetPlayers() do
	table.insert(joinOrder, player)
end

Players.PlayerRemoving:Connect(function(player)
	if sessionHostId == player.UserId then
		sessionHostId = nil
	end
	for _, uid in shelterRooms:remove(player.UserId) do
		local guest = Players:GetPlayerByUserId(uid)
		if guest then
			social(guest, "error", "Хозяин вышел. Ты вернулся в своё убежище.")
		end
	end
	funnel[player] = nil
	squads:remove(player)
	buckets[player] = nil
	lobby.ready[player] = nil
	lobby.weapon[player] = nil
	continueVotes[player] = nil
	tracking[player] = nil
	local idx = table.find(joinOrder, player)
	if idx then
		table.remove(joinOrder, idx)
	end
	if world and participants[player.UserId] == player then
		participants[player.UserId] = nil
		-- Settle what this player earned before they go (Profile saves on removal afterwards).
		if world.phase ~= "RESULTS" then
			local partial = world:leaveResult(player.UserId)
			if partial then
				pcall(Profile.grantRun, player, runId, partial, world.op.id, world.threat)
			end
		end
		world:removePlayer(player.UserId)
		if next(participants) == nil then
			backToLobby()
		end
	end
	if next(lobby.ready) == nil then
		lobby.countdown = nil
	end
	-- New host may not have the selected map/threat unlocked.
	local h = host()
	if h and mode == "LOBBY" then
		local max = Profile.maxThreat(h, lobby.op)
		if max < 1 then
			lobby.op = nextOpFor(h)
			max = Profile.maxThreat(h, lobby.op)
			buildArena(Ops.get(lobby.op).map)
		end
		lobby.threat = math.clamp(lobby.threat, 1, math.max(1, max))
	end
end)

print(string.format("[SWARMFALL] %s server ready", Defs.Version))
