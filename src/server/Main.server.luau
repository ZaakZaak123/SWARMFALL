--!nonstrict
-- Server glue: lobby -> run -> results. Owns characters, validates every remote, feeds the pure
-- simulation (Sim/World), replicates its state (15 Hz packed snapshots) and events (batched),
-- and settles meta progression (Profile) at the end of each run.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local Codec = require(Shared:WaitForChild("Codec"))
local Maps = require(Shared:WaitForChild("Maps"))
local Ops = require(Shared:WaitForChild("Ops"))
local World = require(script.Parent.Sim.World)
local Arena = require(script.Parent.Arena)
local Profile = require(script.Parent.Profile)

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
remotes.Parent = ReplicatedStorage

local SNAPSHOT_RATE = 15
local LOBBY_GATHER = 6
local RESULTS_TIMEOUT = 60

-- Server state ----------------------------------------------------------------------------------------
local mode = "LOBBY" -- LOBBY | RUN
local lobby = { ready = {}, weapon = {}, countdown = nil :: number?, op = "O01", threat = 1 }
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

local function buildArena(mapId: string)
	if builtMap ~= mapId then
		builtMap = mapId
		Arena.build(Maps.get(mapId))
	end
end
buildArena(Ops.get(lobby.op).map)

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

local function prepareCharacter(player: Player, x: number, z: number)
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
	char:PivotTo(CFrame.new(x, 3.2, z))
	tracking[player] = { x = x, z = z, y = 3.2 }
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
				form = Profile.equippedForm(player, weapon),
			})
			participants[player.UserId] = player
		end
	end
	if #infos == 0 then
		return
	end
	buildArena(Ops.get(lobby.op).map)
	seedCounter += 1
	runId = HttpService:GenerateGUID(false)
	world = World.new({ seed = seedCounter * 7919 + 13, players = infos, op = lobby.op, threat = lobby.threat })
	mode = "RUN"
	lobby.countdown = nil
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
	print(string.format("[SWARMFALL] run start %s threat=%d seed=%d players=%d", lobby.op, lobby.threat, world.seed, #infos))
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
		end
	end
end

local function backToLobby()
	settle()
	world = nil
	mode = "LOBBY"
	table.clear(participants)
	table.clear(tracking)
	for _, player in Players:GetPlayers() do
		clearCharacter(player)
	end
end

-- Input -----------------------------------------------------------------------------------------------
local handlers = {}

local function lobbyOnly(): boolean
	return mode == "LOBBY"
end

function handlers.ready(player: Player, weapon)
	if not lobbyOnly() or type(weapon) ~= "string" or not Defs.Weapons[weapon] or not Profile.ownsWeapon(player, weapon) then
		return false
	end
	lobby.weapon[player] = weapon
	lobby.ready[player] = true
	local all = true
	for _, p in Players:GetPlayers() do
		if not lobby.ready[p] then
			all = false
		end
	end
	if all then
		startRun()
	elseif not lobby.countdown then
		lobby.countdown = LOBBY_GATHER
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
	buildArena(Ops.get(opId).map)
	return true
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
	return p ~= nil and finite(offerId) and finite(index) and index % 1 == 0 and world:choose(p.id, offerId, index)
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
	function handlers.devSkip(player: Player, seconds)
		if not world or not finite(seconds) then
			return false
		end
		world.t = math.max(world.t, seconds)
		return true
	end
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
	local ok, accepted = pcall(handler, player, ...)
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
				if hum.Health > 0 then
					hum.Health = 0
				end
				continue
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
local function lobbyInfo()
	local list = {}
	for _, player in Players:GetPlayers() do
		table.insert(list, {
			id = player.UserId,
			name = player.DisplayName,
			ready = lobby.ready[player] == true,
			weapon = lobby.weapon[player] or "W_ARC_RIFLE",
		})
	end
	local h = host()
	return { players = list, countdown = lobby.countdown, op = lobby.op, map = Ops.get(lobby.op).map, threat = lobby.threat, host = h and h.UserId or 0 }
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
			simMs = world.stats.lastTickMs,
		})
	else
		stateRemote:FireAllClients(nil, { mode = "LOBBY", lobby = lobbyInfo() })
	end
end

RunService.Heartbeat:Connect(function(dt)
	if mode == "LOBBY" then
		if lobby.countdown then
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
		local max = Profile.maxThreat(h, lobby.map)
		if max < 1 then
			lobby.map = "MAP_REACTOR_YARD"
			max = Profile.maxThreat(h, lobby.map)
			buildArena(lobby.map)
		end
		lobby.threat = math.clamp(lobby.threat, 1, math.max(1, max))
	end
end)

print(string.format("[SWARMFALL] %s server ready", Defs.Version))
