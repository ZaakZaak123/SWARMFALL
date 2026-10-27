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
local characterLoads = require(script.Parent.CharacterLoads).new()
local Profile = require(script.Parent.Profile)
local Outposts = require(script.Parent.Outposts)
local Home = require(script.Parent.Home)
local Meta = require(Shared:WaitForChild("Meta"))
local Showcase = require(Shared:WaitForChild("Showcase"))
local Squads = require(script.Parent.Squads)
local Neighbors = require(script.Parent.Neighbors)
local Weekly = require(script.Parent.Weekly)
local Guestbook = require(script.Parent.Guestbook)
local TreeLight = require(script.Parent.TreeLight)
local Directory = require(script.Parent.Directory)
local Grove = require(Shared:WaitForChild("Grove"))
local Layout = require(Shared:WaitForChild("ShelterLayout"))
local Chronicle = require(Shared:WaitForChild("Chronicle"))
local Goals = require(Shared:WaitForChild("Goals"))
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
print(
	string.format(
		"[SWARMFALL] role %s  place %d  job %s",
		if IS_SESSION then "SESSION" else "HUB",
		game.PlaceId,
		game.JobId
	)
)
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
local joinQueue: { [Player]: string } = {} -- DD-088: hunters waiting for the next breather (their gun)
local rewards: { [number]: any } = {}
local settled = false
local resultsClock = 0
local snapshotClock = 0
local buckets: { [Player]: { tokens: number, t: number } } = {}
local rejected = 0
local seedCounter = os.time() % 100000
local builtMap = nil

Arena.onClear = Home.build
Home.furnish()
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
	characterLoads:cancel(player)
	tracking[player] = nil
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
	local spawnMode = mode
	-- Stop movement sync from copying a previous home position into the new run during the load.
	tracking[player] = nil
	characterLoads:run(player, function(current)
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			warn("[SWARMFALL] LoadCharacter failed", err)
			return
		end
		local char = player.Character
		if not char or not current() then
			return
		end
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
		local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if not hum or not root or not current() or player.Character ~= char then
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
		char:SetAttribute("SpawnReady", spawnMode)
	end)
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
-- A hunter as the simulation sees them (the gun they own, perks, technologies, form, modules).
local function runInfo(player: Player, weapon: string)
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
	return {
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
	}
end

local function startRun()
	local infos = {}
	table.clear(participants)
	for _, player in Players:GetPlayers() do
		if lobby.ready[player] then
			table.insert(infos, runInfo(player, lobby.weapon[player] or "W_ARC_RIFLE"))
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
	local opts =
		{ seed = seedCounter * 7919 + 13, players = infos, op = lobby.op, threat = lobby.threat, replay = replay }
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
	print(
		string.format(
			"[SWARMFALL] run start %s threat=%d seed=%d players=%d",
			world.op.id,
			lobby.threat,
			world.seed,
			#infos
		)
	)
end

local function settle()
	if settled or not world or not world.result then
		return
	end
	settled = true
	local r = world.result
	print(
		string.format(
			"[SWARMFALL] run end %s %s t=%.1f kills=%d",
			if r.victory then "VICTORY" else "DEFEAT",
			r.reason,
			r.time,
			r.kills
		)
	)
	-- DD-088: newcomers in a won fight; every veteran beside them is their mentor in it
	local newcomers = {}
	if r.victory then
		for uid, player in participants do
			local d = Profile.get(player)
			if player.Parent and d and Meta.isNewcomer(d) then
				newcomers[uid] = player.DisplayName
			end
		end
	end
	-- DD-089: every win in every grove lights the Tree; its light pays everyone this week
	local light = TreeLight.state().tier
	if r.victory then
		local n = 0
		for _, player in participants do
			if player.Parent then
				n += 1
			end
		end
		TreeLight.add(n)
	end
	for userId, player in participants do
		if player.Parent then
			local d = Profile.get(player)
			local extra = { light = light }
			if d and r.victory and Meta.isVeteran(d) then
				local names = {}
				for uid, name in newcomers do
					if uid ~= userId then
						table.insert(names, name)
					end
				end
				if #names > 0 then
					extra.mentor = names
				end
			end
			rewards[userId] = Profile.grantRun(player, runId, r, world.op.id, world.threat, extra)
			Weekly.push(player)
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

-- Between fights everyone is at home (DD-052 → DD-087): in the grove, each on their own plot, facing
-- the bunker; a squad's session server keeps the host's shelter on the host's plot (the grove they came
-- from). A lodger (no plot free) waits on the square under the Tree.
local LOBBY_SPOTS = Layout.Spawns
local sessionPlots: { [number]: number } = {} -- session: user id -> their plot in the grove they flew from
local sessionGrove = nil -- session: the neighbours' homes as they were at launch (for the ride home)
local sessionFrom: string? = nil -- session: the grove server to fly back to
local leavingFor: { [Player]: string } = {} -- off to a fight: the sortie's name (their plot waits)
local function facingOf(f: CFrame): number
	local look = f:VectorToWorldSpace(Vector3.new(0, 0, 1)) -- towards the bunker
	return math.atan2(-look.X, -look.Z)
end
local function toHub(player: Player)
	if (mode ~= "LOBBY" and mode ~= "HUB") or not player.Parent then
		return
	end
	local i = table.find(Players:GetPlayers(), player) or 1
	if mode == "HUB" then
		local plot = Neighbors.plotOf(player.UserId)
		if not plot then
			local a = i * 1.3
			local c = Grove.Center
			prepareCharacter(player, c.X + math.sin(a) * 22, c.Z - math.cos(a) * 22, a)
			return
		end
		local f = Grove.frame(plot)
		local w = f:PointToWorldSpace(Vector3.new(LOBBY_SPOTS[1][1], 0, LOBBY_SPOTS[1][2]))
		prepareCharacter(player, w.X, w.Z, facingOf(f))
		return
	end
	local f = Grove.frame(sessionPlots[sessionHostId or 0] or 1)
	local spot = LOBBY_SPOTS[(i - 1) % #LOBBY_SPOTS + 1]
	local w = f:PointToWorldSpace(Vector3.new(spot[1], 0, spot[2]))
	prepareCharacter(player, w.X, w.Z, facingOf(f))
end

local regroup, groveLook, toCamp, nextOpFor -- the grove and the camp (defined below)
local sessionSquad = nil -- session: { host, members, open } — the squad flies home as one (DD-087)
local homeBound: { [Player]: boolean } = {} -- session: on the way home (a failed hop retries any grove)
-- DD-090: where the squad flies home — its own grove while it has seats for all of them; else the
-- liveliest grove with room for the whole squad (all to the same one); else any.
local sessionDest: string? = nil
local sessionDestPicked = false
local function homeGrove(): string?
	if sessionDestPicked then
		return sessionDest
	end
	sessionDestPicked = true
	local need = if sessionSquad then #sessionSquad.members else #Players:GetPlayers()
	local seats = if sessionFrom then Directory.seats(sessionFrom, need) else false
	if sessionFrom and seats ~= false then
		sessionDest = sessionFrom -- known to have room, or nothing is known: try it
	else
		sessionDest = Directory.find(math.max(1, need), { sessionFrom or "" })
	end
	return sessionDest
end
local function flyHome(player: Player, anyGrove: boolean)
	local options = Instance.new("TeleportOptions")
	local dest = if anyGrove then nil else homeGrove()
	if dest then
		options.ServerInstanceId = dest
	end
	options:SetTeleportData({ v = 1, back = true, squad = sessionSquad })
	return pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
end
local fromCamp = nil -- Studio: the squad the camp turned into a session in place; it comes home to the grove
local function backToLobby()
	settle()
	table.clear(joinQueue)
	if IS_SESSION and TELEPORTS then
		-- DD-087: a session has no home of its own; everyone still here flies back to the grove (the
		-- squad base below is only the fallback while a hop fails)
		for _, player in Players:GetPlayers() do
			toCamp(player)
		end
	end
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
	if fromCamp then
		-- DD-087: home to the grove, each to their plot, the squad still a squad
		local back = fromCamp
		fromCamp = nil
		mode = "HUB"
		setLight(true)
		sessionHostId = nil
		table.clear(participants)
		table.clear(tracking)
		table.clear(lobby.ready)
		lobby.countdown = nil
		lobby.strikeAt = nil
		for _, player in Players:GetPlayers() do
			squads:solo(player, nextOpFor(player))
		end
		regroup(back.host, back.members, back.open)
		for _, player in Players:GetPlayers() do
			clearCharacter(player)
			task.spawn(toHub, player)
			groveLook(player)
		end
		return
	end
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

-- DD-088: whoever waits to join the drill defence comes in at the breather.
local function admitJoiners()
	if not world or not world:canJoin() then
		return
	end
	for player, weapon in joinQueue do
		joinQueue[player] = nil
		if player.Parent and not participants[player.UserId] then
			local p = world:addPlayer(runInfo(player, weapon))
			if p then
				participants[player.UserId] = player
				task.spawn(prepareCharacter, player, p.x, p.z)
				print(string.format("[SWARMFALL] %s joins the defence at %.0f s", player.Name, world.t))
			end
		end
		if not world:canJoin() then
			break
		end
	end
end

-- The hunt a hunter's own squad starts on: their next unwon story hunt.
function nextOpFor(player: Player): string
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

local hubInfo, groveInfo -- the camp state (defined with the replication below)
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
		-- DD-087: the way home — this grove, each member's plot, the neighbours' homes for the ride back
		from = game.JobId,
		open = sq.open,
		plots = {},
		grove = {},
	}
	local inSquad = {}
	for _, m in sq.members do
		table.insert(data.members, m.UserId)
		data.weapons[tostring(m.UserId)] = sq.weapon[m] or "W_ARC_RIFLE"
		data.plots[tostring(m.UserId)] = Neighbors.plotOf(m.UserId)
		inSquad[m.UserId] = true
	end
	for _, h in hubInfo().hunters do
		if h.plot and not inSquad[h.id] then
			local e = table.clone(h)
			e.slots, e.trophies = nil, nil
			data.grove[tostring(h.plot)] = e
		end
	end
	for plot, e in groveInfo().ghosts do
		data.grove[tostring(plot)] = data.grove[tostring(plot)] or e
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
	fromCamp = { host = sq.host.UserId, members = {}, open = sq.open }
	for _, m in sq.members do
		table.insert(fromCamp.members, m.UserId)
	end
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
	local fightName = if sq.mode == "siege"
		then "оборона бура"
		elseif sq.mode == "raid" then "налёт"
		else "«" .. Goals.titleCase(Ops.get(sq.op).name) .. "»"
	for _, m in members do
		social(m, "launch", Ops.get(sq.op).name)
		leavingFor[m] = fightName -- their plot waits for them (DD-087)
	end
	print(string.format("[SWARMFALL] launch squad %d: %d hunters, %s %s", sq.id, #members, sq.mode, sq.op))
	task.spawn(function()
		local options = Instance.new("TeleportOptions")
		options.ShouldReserveServer = true
		options:SetTeleportData(teleportData(sq))
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, members, options)
		if ok and typeof(err) == "Instance" and err:IsA("TeleportAsyncResult") then
			-- DD-088: the way in for a neighbour who wants to join this defence later
			Neighbors.launched(sq.host.UserId, err.ReservedServerAccessCode)
		end
		if not ok then
			warn("[SWARMFALL] launch failed", err)
			for _, m in members do
				leavingFor[m] = nil
			end
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
	leavingFor[player] = nil
	if homeBound[player] then
		-- the grove closed or filled up meanwhile: any grove (the home travels with the profile)
		homeBound[player] = nil
		task.spawn(flyHome, player, true)
		return
	end
	local sq = squads:squadOf(player)
	if sq then
		sq.launching = false
		table.clear(sq.ready)
	end
	social(player, "error", "Выход не удался — попробуй ещё раз")
end)

-- «В ЛАГЕРЬ»: back to a public camp server (live) or, in Studio, the whole server back to the camp.
function toCamp(player: Player): boolean
	if TELEPORTS then
		if not IS_SESSION then
			return false
		end
		task.spawn(function()
			-- DD-087: back to the grove the squad flew from (its plots are waiting), else any grove
			homeBound[player] = true
			local ok = flyHome(player, false)
			if not ok then
				ok = flyHome(player, true)
			end
			if not ok then
				homeBound[player] = nil
				social(player, "error", "Не удалось вернуться в рощу")
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
	if not IS_SESSION then
		return
	end
	local ok, jd = pcall(player.GetJoinData, player)
	local data = ok and jd and jd.TeleportData
	if type(data) ~= "table" or not tonumber(data.host) then
		return
	end
	if data.join == true then
		-- DD-088: a neighbour from the same grove comes to join the defence at the next breather
		if sessionFrom and data.from ~= sessionFrom then
			return
		end
		local plot = tonumber(data.plot)
		if plot and plot >= 1 and plot <= Grove.Plots then
			sessionPlots[player.UserId] = math.floor(plot)
		end
		if sessionSquad and not table.find(sessionSquad.members, player.UserId) then
			table.insert(sessionSquad.members, player.UserId)
		end
		joinQueue[player] = if type(data.weapon) == "string" and Defs.Weapons[data.weapon]
			then data.weapon
			else "W_ARC_RIFLE"
		return
	end
	if sessionHostId then
		return -- the plan came with the first of the squad
	end
	sessionHostId = tonumber(data.host)
	sessionPlan = { members = {}, since = os.clock(), data = data }
	sessionFrom = if type(data.from) == "string" and #data.from > 0 then data.from else nil
	for k, v in (if type(data.plots) == "table" then data.plots else {}) do
		local uid, plot = tonumber(k), tonumber(v)
		if uid and plot and plot >= 1 and plot <= Grove.Plots then
			sessionPlots[uid] = math.floor(plot)
		end
	end
	sessionGrove = if type(data.grove) == "table" then data.grove else nil
	print(
		string.format(
			"[SWARMFALL] session plan from %s: host %d, %s %s",
			player.Name,
			sessionHostId,
			tostring(data.mode),
			tostring(data.op)
		)
	)
	for _, uid in (if type(data.members) == "table" then data.members else {}) do
		if tonumber(uid) then
			table.insert(sessionPlan.members, tonumber(uid))
		end
	end
	sessionSquad = { host = sessionHostId, members = table.clone(sessionPlan.members), open = data.open == true }
end

-- Session clients: where each survivor's home stands in the grove they came from, and the neighbours'
-- homes around it (the ride home arrives there, DD-087).
local function sendGrove(player: Player)
	if not IS_SESSION or not player.Parent then
		return
	end
	local plots = {}
	for uid, plot in sessionPlots do
		plots[tostring(uid)] = plot
	end
	social(player, "grove", { plots = plots, grove = sessionGrove })
end

local function sessionStart()
	local plan = sessionPlan
	sessionPlan = nil
	local d = plan.data
	local h = host()
	if not h then
		return
	end
	local opId = if type(d.op) == "string"
			and table.find(Ops.Order, d.op)
			and Profile.maxThreat(h, d.op) >= 1
		then d.op
		else "O01"
	lobby.op = opId
	lobby.threat = math.clamp(math.floor(tonumber(d.threat) or 1), 1, math.max(1, Profile.maxThreat(h, opId)))
	local f = Profile.features(Profile.get(h) or {})
	local m = d.mode
	lobby.mode = if m == "siege" and f.siege
		then "siege"
		elseif m == "strike" and f.outpost then "strike"
		elseif m == "raid" and f.raids then "raid"
		else "hunt"
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

-- DD-087: the grove notices what a survivor has done since it last saw them (a chronicle line for all).
function groveLook(player: Player)
	local d = Profile.get(player)
	-- the first look is taken in any mode (a newcomer may be off to the first sortie at once); news is
	-- only told in the grove, so a fight's deeds come out when the hunter is home
	if not d or (mode ~= "HUB" and Neighbors.seen(player.UserId)) then
		return
	end
	for _, e in Neighbors.look(player, d) do
		for _, p in Players:GetPlayers() do
			social(p, "chronicle", e)
		end
	end
end

-- A squad back from a fight forms again round its host (who stays its host).
local function link(hostP: Player, memberP: Player)
	local hsq = squads:squadOf(hostP)
	if hsq and hsq.host == hostP and squads:squadOf(memberP) ~= hsq and #hsq.members < Squads.Max then
		hsq.invited[memberP.UserId] = true
		squads:join(memberP, hsq.id)
	end
end
function regroup(hostUid: number?, members, open: boolean?)
	local hostP = hostUid and Players:GetPlayerByUserId(hostUid)
	if not hostP then
		return
	end
	local sq = squads:squadOf(hostP)
	if sq and sq.host == hostP and open ~= nil then
		sq.open = open
	end
	for _, uid in members or {} do
		local m = tonumber(uid) and Players:GetPlayerByUserId(tonumber(uid) :: number)
		if m and m ~= hostP then
			link(hostP, m)
		end
	end
end
-- Live: whoever arrives back from a session brings the squad with them (teleport data); the first one
-- home waits for the rest as they land.
local function regroupFrom(player: Player)
	local ok, jd = pcall(player.GetJoinData, player)
	local data = ok and jd and jd.TeleportData
	if type(data) ~= "table" or data.back ~= true or type(data.squad) ~= "table" then
		return
	end
	local members = if type(data.squad.members) == "table" then data.squad.members else {}
	if data.moved == true and player.UserId == tonumber(data.squad.host) then
		-- DD-090: a squad moved in from another grove: the grove hears of its new neighbours
		local e = Neighbors.note(
			"users",
			if #members > 1
				then string.format("В рощу переехал отряд %s (%d)", player.DisplayName, #members)
				else "В рощу переехал житель: " .. player.DisplayName,
			player.UserId,
			true
		)
		for _, p in Players:GetPlayers() do
			social(p, "chronicle", e)
		end
	end
	regroup(
		tonumber(data.squad.host),
		members,
		if player.UserId == tonumber(data.squad.host) then data.squad.open == true else nil
	)
end

-- The favourite gun for a home seen from another grove: the most mastered one.
local function favouriteWeapon(d): string
	local best, kills = "W_ARC_RIFLE", -1
	for id, n in d.mastery or {} do
		if Defs.Weapons[id] and n > kills then
			best, kills = id, n
		end
	end
	return best
end
Profile.onChanged(function(player)
	groveLook(player)
	local d = Profile.get(player)
	if d and mode == "HUB" then
		local w = favouriteWeapon(d)
		Neighbors.publish(
			player,
			Showcase.build(player.UserId, player.DisplayName, d, w, Profile.equippedForm(player, w))
		)
	end
end)

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
			groveLook(player)
			if mode == "HUB" then
				-- DD-090: the Tree may have grown bright after their win this week
				Profile.earnDecor(player, TreeLight.state().tier)
				-- DD-089: what came while they were away (♥ and visits from other groves)
				local book = Guestbook.claim(player.UserId)
				if book and player.Parent then
					Profile.addLikes(player, book.likes or 0)
					social(
						player,
						"guestbook",
						{ likes = book.likes or 0, visits = book.visits or 0, names = book.names or {} }
					)
				end
				-- DD-088: last week's top three get their laurel (and the grove hears of it)
				for _, board in Weekly.laurels(player) do
					local e = Neighbors.note(
						"crown",
						player.DisplayName
							.. " — в тройке прошлой недели: "
							.. Meta.WeeklyWords[board],
						player.UserId,
						true
					)
					for _, p in Players:GetPlayers() do
						social(p, "chronicle", e)
					end
				end
			end
		end
	end)
	if mode == "HUB" then
		Neighbors.arrive(player)
		squads:solo(player, "O01")
		regroupFrom(player)
	end
	sessionJoin(player)
	task.wait(1)
	sendGrove(player)
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
		Neighbors.arrive(player)
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
	if
		not lobbyOnly()
		or type(weapon) ~= "string"
		or not Defs.Weapons[weapon]
		or not Profile.ownsWeapon(player, weapon)
	then
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
	return lobbyOnly()
		and type(weaponId) == "string"
		and type(slot) == "string"
		and type(id) == "string"
		and Profile.equipModule(player, weaponId, slot, id)
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
	return lobbyOnly()
		and type(weaponId) == "string"
		and type(evoId) == "string"
		and Profile.equipForm(player, weaponId, evoId)
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

-- A hunter watching a drill defence (they came to join it, or were here when it started) steps in at
-- the next breather.
function handlers.joinRun(player: Player, weapon)
	if mode ~= "RUN" or not world or world.result or participants[player.UserId] then
		return false
	end
	if (world.op.mode or "hunt") ~= "siege" or not Profile.get(player) then
		return false
	end
	joinQueue[player] = if type(weapon) == "string" and Defs.Weapons[weapon] then weapon else "W_ARC_RIFLE"
	admitJoiners()
	return true
end

function handlers.continue(player: Player)
	if mode ~= "RUN" or not world or world.phase ~= "RESULTS" then
		return false
	end
	if IS_SESSION and TELEPORTS then
		-- DD-087: «ДОМОЙ» — each flies home to the grove at once; the squad forms again there
		settle()
		return toCamp(player)
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
	-- every seasonal decoration at once, one put up (DD-090: a look at them without a bright week)
	function handlers.devDecor(player: Player, id)
		local d = Profile.get(player)
		if not d then
			return false
		end
		for _, def in Meta.Decor do
			d.decor[def.id] = Meta.weekIndex(os.time())
		end
		d.decorOn = if type(id) == "string" and Meta.decorById(id) then id else "LANTERNS"
		pushProfile(player)
		return true
	end
	-- the end of a sortie without fighting it (the way home, the chronicle, DD-087)
	function handlers.devWin(player: Player)
		if not world or world.result or not participant(player) then
			return false
		end
		world:finish(true, "dev")
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

-- DD-087: a survivor is «at» a plot when they stand in its area or by its sign on the road.
local function nearPlot(player: Player, plot: number?): boolean
	local root = rootOf(player)
	if not root or not plot then
		return false
	end
	local c = Grove.frame(plot).Position
	return Vector3.new(root.Position.X - c.X, 0, root.Position.Z - c.Z).Magnitude < Grove.Reach + 24
end

function handlers.like(player: Player, uid)
	if not campOnly() or not Codec.isUserId(uid, RunService:IsStudio()) or uid == player.UserId then
		return false
	end
	local owner = Players:GetPlayerByUserId(uid)
	local day = Meta.dayIndex(os.time())
	if owner and Neighbors.plotOf(uid) and not Neighbors.awayPlot(uid) then
		if not nearPlot(player, Neighbors.plotOf(uid)) or not Profile.like(player, owner, day) then
			return false
		end
		social(owner, "liked", player.DisplayName)
		social(player, "likeSent", owner.DisplayName)
		return true
	end
	-- DD-089: an absent owner's home (another grove, or out on a fight): the ♥ waits in their guestbook
	local plot = Neighbors.awayPlot(uid)
	if not plot or not nearPlot(player, plot) or not Profile.likeAway(player, uid, day) then
		return false
	end
	Guestbook.like(uid, player.DisplayName)
	social(player, "likeSent", "")
	return true
end

-- DD-090: the whole squad moves to another grove together (the host asks; homes travel with their
-- owners, plots here are freed). The directory picks a grove with room for all of them.
function handlers.moveSquad(player: Player)
	local sq = squads:squadOf(player)
	if not campOnly() or not sq or sq.host ~= player or sq.launching then
		return false
	end
	if not TELEPORTS then
		social(player, "error", "В Studio переезда между рощами нет")
		return false
	end
	local members = table.clone(sq.members)
	sq.launching = true
	local data = { v = 1, back = true, moved = true, squad = { host = player.UserId, members = {}, open = sq.open } }
	for _, m in members do
		table.insert(data.squad.members, m.UserId)
		social(m, "launch", "в другую рощу")
	end
	task.spawn(function()
		local options = Instance.new("TeleportOptions")
		local dest = Directory.find(#members, { game.JobId })
		if dest then
			options.ServerInstanceId = dest
		end
		options:SetTeleportData(data)
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, members, options)
		if not ok then
			warn("[SWARMFALL] squad move failed", err)
			sq.launching = false
			for _, m in members do
				social(m, "error", "Переезд не удался — попробуй ещё раз")
			end
		end
	end)
	return true
end

-- DD-090: the seasonal decoration up on the plot (an id kept in the profile, or false for none).
function handlers.decor(player: Player, id)
	return (id == false or type(id) == "string") and Profile.setDecor(player, id)
end

-- DD-089: the plot's flag (colour and an earned emblem).
function handlers.banner(player: Player, color, emblem)
	return finite(color) and type(emblem) == "string" and Profile.setBanner(player, color, emblem)
end

-- «Посетить» (the residents' list, a hunter's card): a quick way to a plot's sign, facing the gate. The
-- grove is open — walking there is the same thing, only longer.
function handlers.visit(player: Player, plot)
	if not campOnly() or not finite(plot) then
		return false
	end
	plot = math.floor(plot)
	if plot < 1 or plot > Grove.Plots then
		return false
	end
	local sq = squads:squadOf(player)
	local root = rootOf(player)
	if (sq and sq.launching) or not root then
		return false
	end
	local f = Grove.frame(plot)
	local w = f:PointToWorldSpace(Vector3.new(Layout.Arrive.x, 0, Layout.Arrive.z))
	root.AssemblyLinearVelocity = Vector3.zero
	player.Character:PivotTo(CFrame.new(w.X, 3.2, w.Z) * CFrame.Angles(0, facingOf(f), 0))
	local ownerUid = Neighbors.plots()[plot].uid
	local owner = ownerUid and Players:GetPlayerByUserId(ownerUid)
	if owner and owner ~= player then
		social(owner, "visitor", player.DisplayName)
	end
	return true
end

-- Quick signals (DD-087 §6): fixed phrases over the head, seen by everyone in the grove.
function handlers.say(player: Player, i)
	if not campOnly() or not finite(i) then
		return false
	end
	i = math.floor(i)
	if not Chronicle.Signals[i] or not Neighbors.canSay(player.UserId) then
		return false
	end
	for _, p in Players:GetPlayers() do
		social(p, "say", { uid = player.UserId, i = i })
	end
	return true
end

-- «Попроситься» at a neighbour's sign: a lit lantern (open squad) takes you at once; otherwise the owner
-- is asked and can «ВЗЯТЬ» you within a minute.
function handlers.ask(player: Player, uid)
	local owner = Codec.isUserId(uid, RunService:IsStudio()) and Players:GetPlayerByUserId(uid)
	local sq = owner and squads:squadOf(owner)
	if not campOnly() or not owner or owner == player or not sq then
		return false
	end
	if squads:squadOf(player) == sq then
		return false
	end
	if sq.open then
		return handlers.join(player, sq.id)
	end
	if #sq.members >= Squads.Max or sq.launching or not Neighbors.ask(player.UserId, owner.UserId) then
		return false
	end
	social(owner, "ask", { from = player.DisplayName, uid = player.UserId })
	social(player, "asked", owner.DisplayName)
	return true
end

-- DD-088: «Вступить в оборону» at the sign of a neighbour out defending their drill: fly into that
-- fight (the reserved server takes them at the next breather); the plot waits as for any fight.
function handlers.joinFight(player: Player, hostUid)
	if not campOnly() or not TELEPORTS or not Codec.isUserId(hostUid, RunService:IsStudio()) then
		return false
	end
	local code = Neighbors.wayIn(hostUid)
	local sq = squads:squadOf(player)
	if not code or leavingFor[player] or (sq and sq.launching) then
		social(player, "error", "В этот бой уже не войти")
		return false
	end
	local weapon = (sq and sq.weapon[player]) or "W_ARC_RIFLE"
	leavingFor[player] = "оборона бура"
	social(player, "launch", "оборона бура")
	task.spawn(function()
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData({
			v = 1,
			join = true,
			host = hostUid,
			from = game.JobId,
			plot = Neighbors.plotOf(player.UserId),
			weapon = weapon,
		})
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
		if not ok then
			warn("[SWARMFALL] join fight failed", err)
			leavingFor[player] = nil
			social(player, "error", "Не получилось вступить — попробуй ещё раз")
		end
	end)
	return true
end

function handlers.take(player: Player, uid)
	local asker = Codec.isUserId(uid, RunService:IsStudio()) and Players:GetPlayerByUserId(uid)
	local sq = squads:squadOf(player)
	if not campOnly() or not asker or not sq or not Neighbors.take(player.UserId, asker.UserId) then
		return false
	end
	sq.invited[asker.UserId] = true
	return handlers.join(asker, sq.id)
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

local groveCache, groveAt = nil, -1e9 -- the grove's slow part (groveInfo below)
-- What a survivor is up to, for their sign and nameplate (DD-087 §5).
local function statusOf(player: Player, sq): (string, string)
	local st = {}
	if sq then
		st.launching = sq.launching or (sq.countdown ~= nil and not sq.hold)
		st.ready = next(sq.ready) ~= nil
		st.open = sq.open
		if #sq.members > 1 then
			local other = if sq.members[1] == player then sq.members[2] else sq.members[1]
			st.squadWith = other.DisplayName
		end
	end
	local root = rootOf(player)
	if root then
		Neighbors.moved(player.UserId, root.Position)
		local at = Grove.plotAt(root.Position)
		if at and at ~= Neighbors.plotOf(player.UserId) then
			local ownerUid = Neighbors.plots()[at].uid
			st.guestOf = ownerUid and Neighbors.name(ownerUid)
			-- DD-089: walking round an absent owner's home is a visit in their guestbook
			local cached = groveCache
			local ghost = cached and cached.ghosts and cached.ghosts[at]
			local away = ownerUid and Neighbors.awayPlot(ownerUid) == at and ownerUid or (ghost and ghost.id)
			if away then
				Guestbook.visit(away, player.UserId, player.DisplayName)
			end
		end
		st.square = Grove.onSquare(root.Position)
	end
	st.idle = Neighbors.idle(player.UserId)
	return Chronicle.status(st)
end

-- The grove's static part (homes from other groves, held plots, the chronicle) changes slowly.
function groveInfo()
	if not groveCache or os.clock() - groveAt > 2 then
		groveAt = os.clock()
		groveCache = {
			ghosts = Neighbors.ghosts(),
			held = Neighbors.held(),
			feed = Neighbors.feed(),
			weekly = Weekly.boards(), -- DD-088
			light = TreeLight.state(), -- DD-089
			capacity = Players.MaxPlayers, -- DD-090
		}
	end
	return groveCache
end

-- The camp in one table: every squad (lobby-shaped, so the base UI reads it), every hunter's showcase
-- with their plot and status, and the grove around them (DD-087).
function hubInfo()
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
			local entry =
				Showcase.build(player.UserId, player.DisplayName, d, weapon, Profile.equippedForm(player, weapon))
			entry.squad = sq and sq.id or 0
			entry.plot = Neighbors.plotOf(player.UserId)
			entry.statusKey, entry.status = statusOf(player, sq)
			Neighbors.remember(player.UserId, entry)
			table.insert(hunters, entry)
		end
	end
	return {
		squads = list,
		hunters = hunters,
		featured = Showcase.featured(hunters, math.floor(os.time() / 120)),
		grove = groveInfo(),
	}
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

-- DD-088: a squad's server tells its grove how the fight goes (the host's sign shows it, a neighbour can
-- join a defence from there); the grove listens on its own topic. Live servers only.
local MessagingService = game:GetService("MessagingService")
local function groveTopic(job: string): string
	return "TLG_Grove_" .. string.sub(job, 1, 60)
end
if TELEPORTS and not IS_SESSION then
	task.spawn(function()
		local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, groveTopic(game.JobId), function(msg)
			Neighbors.progress(msg.Data)
		end)
		if not ok then
			warn("[SWARMFALL] grove topic", err)
		end
	end)
end
local reportClock, reportedEnd = 0, nil
local function reportFight(dt: number)
	if not (IS_SESSION and TELEPORTS and sessionFrom) or not world then
		return
	end
	reportClock += dt
	local ended = world.result ~= nil
	if ended and reportedEnd == world then
		return
	end
	if reportClock < 5 and not ended then
		return
	end
	reportClock = 0
	if ended then
		reportedEnd = world
	end
	local members = {}
	for uid in participants do
		table.insert(members, uid)
	end
	local opMode = world.op.mode or "hunt"
	local data = {
		host = sessionHostId,
		members = members,
		mode = opMode,
		name = if world.op.id == "STRIKE"
			then "Первый натиск"
			elseif opMode == "siege" then "Оборона бура · ур. " .. tostring(world.op.siege or 1)
			elseif opMode == "raid" then "Налёт"
			else "«" .. Goals.titleCase(world.op.name) .. "»",
		p = world:progress(),
		result = if ended then (if world.result.victory then "win" else "loss") else nil,
	}
	task.spawn(function()
		pcall(MessagingService.PublishAsync, MessagingService, groveTopic(sessionFrom :: string), data)
	end)
end

local fallClock = 0
local lastTier = nil -- the Tree's light tier last seen (DD-089)
local directoryClock = 29 -- DD-090: this grove in the directory every 30 s (the first at once)
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
			-- DD-087: standing at the gathering fire lights your lantern (an open squad) until you walk off
			local sq = mode == "HUB" and squads:squadOf(player)
			if root and sq and sq.host == player and not sq.launching then
				local near = Vector3.new(root.Position.X - Grove.Fire.X, 0, root.Position.Z - Grove.Fire.Z).Magnitude
					< 13
				if near and not sq.open then
					sq.open = true
					sq.byFire = true
				elseif not near and sq.byFire then
					sq.byFire = nil
					if #sq.members == 1 then
						sq.open = false
					end
				end
			end
		end
		if mode == "HUB" then
			Neighbors.tick()
			directoryClock += 1
			if directoryClock >= 30 then
				directoryClock = 0
				local free = 0
				for _, pl in Neighbors.plots() do
					if not pl.uid then
						free += 1
					end
				end
				Directory.publish(free)
			end
			-- DD-089: the Tree grew brighter (somewhere in the world a grove won): the grove hears of it
			local tier = TreeLight.state().tier
			if lastTier and tier > lastTier then
				local e = Neighbors.note(
					"sun",
					string.format(
						"Древо засветилось ярче: свет %d/%d, +%d%% ксенита всем до понедельника",
						tier,
						#Meta.TreeTiers,
						math.floor(tier * Meta.TreeBonus * 100 + 0.5)
					),
					nil,
					true
				)
				for _, p in Players:GetPlayers() do
					social(p, "chronicle", e)
					Profile.earnDecor(p, tier) -- DD-090: a win this week + the Tree bright enough
				end
			end
			lastTier = tier
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
		if next(joinQueue) then
			admitJoiners()
		end
		reportFight(dt)
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
	characterLoads:cancel(player)
	if sessionHostId == player.UserId then
		sessionHostId = nil
	end
	if mode == "HUB" or leavingFor[player] then
		Neighbors.leave(player, leavingFor[player])
	end
	leavingFor[player] = nil
	funnel[player] = nil
	squads:remove(player)
	buckets[player] = nil
	lobby.ready[player] = nil
	lobby.weapon[player] = nil
	continueVotes[player] = nil
	joinQueue[player] = nil
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
