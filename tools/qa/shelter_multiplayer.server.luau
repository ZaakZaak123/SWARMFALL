-- Development fixture: inject into an unpublished local build, then start ExecuteMultiplayerTestAsync.
-- Never installed by Rojo; never touches real profiles or runs against a published place.
local RunService = game:GetService("RunService")
local STS = game:GetService("StudioTestService")
local visual = STS:GetTestArgs() == "CodexShelterVisual"
local session = STS:GetTestArgs() == "CodexShelterSession"
if
	not RunService:IsStudio()
	or game.PlaceId ~= 0
	or (not visual and not session and STS:GetTestArgs() ~= "CodexShelterRooms")
then
	return
end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local event = Instance.new("RemoteEvent")
event.Name, event.Parent = "CodexShelterQA", RS
local Profile = require(game.ServerScriptService.Server.Profile)
local Collection = require(RS.Shared.Collection)
local Defs = require(RS.Shared.Defs)
local reports, checks = {}, {}
local function await(fn, seconds, message)
	local deadline = os.clock() + seconds
	repeat
		if fn() then
			return
		end
		task.wait(0.1)
	until os.clock() >= deadline
	error(message)
end
local function prepare(player)
	await(function()
		return Profile.get(player) ~= nil
	end, 40, "profile timeout")
	local d = Profile.get(player)
	d.ops.O01, d.scrap, d.runs = 2, 1234, 1
	d.wins_by_op = { O01 = 1, O02 = 1, O03 = 1, O04 = 1 }
	d.home = { GENERATOR = true, WORKBENCH = true, LAB = true }
	if visual or player.Name == "Player1" then
		for _, kind in Collection.Order do
			d.research[kind] = Defs.Research[kind][3]
		end
	else
		d.research = { EN_RUNNER = 10, EN_SPITTER = 10 }
	end
end
Players.PlayerAdded:Connect(function(p)
	task.spawn(prepare, p)
end)
for _, p in Players:GetPlayers() do
	task.spawn(prepare, p)
end
event.OnServerEvent:Connect(function(p, phase, data)
	reports[phase .. ":" .. p.Name] = data
end)
if visual then
	return
end
local function probe(phase, room, expectedTanks, visibility)
	for _, p in Players:GetPlayers() do
		event:FireClient(
			p,
			"probe",
			{ phase = phase, room = room[p.Name], tanks = expectedTanks[p.Name], visible = visibility }
		)
	end
	for _, p in Players:GetPlayers() do
		local key = phase .. ":" .. p.Name
		await(function()
			return reports[key] ~= nil
		end, 25, "client report timeout: " .. key)
		assert(reports[key].ok, key .. ": " .. tostring(reports[key].error))
		table.insert(checks, key)
	end
end
task.spawn(function()
	local ok, err = pcall(function()
		await(function()
			return #Players:GetPlayers() == 2
		end, 60, "two clients did not join")
		local owner = Players:FindFirstChild("Player1")
		local guest = Players:FindFirstChild("Player2")
		assert(owner and guest, "unexpected simulated client names")
		await(function()
			return reports["ready:Player1"] and reports["ready:Player2"]
		end, 70, "clients not ready")
		local ownerBefore, guestBefore = Profile.get(owner).scrap, Profile.get(guest).scrap
		if session then
			event:FireClient(owner, "open")
			await(function()
				return reports["open:Player1"] ~= nil
			end, 10, "squad did not open")
			event:FireClient(guest, "join", reports["open:Player1"].squad)
			await(function()
				return reports["joined:Player2"] ~= nil
			end, 10, "guest did not join")
			event:FireClient(owner, "ready", "W_ARC_RIFLE")
			event:FireClient(guest, "ready", "W_ARC_RIFLE")
			event:FireClient(owner, "waitRun")
			event:FireClient(guest, "waitRun")
			await(function()
				return reports["run:Player1"] and reports["run:Player2"]
			end, 40, "squad did not enter the run")
			table.insert(checks, "both clients entered one squad run")
			event:FireClient(owner, "devSkip", 500)
			event:FireClient(owner, "waitResults")
			event:FireClient(guest, "waitResults")
			await(function()
				return reports["results:Player1"] and reports["results:Player2"]
			end, 40, "squad did not reach results")
			event:FireClient(owner, "continue")
			event:FireClient(guest, "continue")
			probe(
				"squad_rest",
				{ Player1 = owner.UserId, Player2 = owner.UserId },
				{ Player1 = 12, Player2 = 12 },
				true
			)
			event:FireClient(owner, "leave")
			await(function()
				return #Players:GetPlayers() == 1
			end, 15, "host did not leave")
			probe("new_host", { Player2 = guest.UserId }, { Player2 = 2 }, false)
			event:FireClient(guest, "camp")
			probe("back_to_camp", { Player2 = guest.UserId }, { Player2 = 2 }, false)
			return
		end
		probe("separate", { Player1 = owner.UserId, Player2 = guest.UserId }, { Player1 = 12, Player2 = 2 }, false)
		event:FireClient(guest, "visit", owner.UserId)
		probe("together", { Player1 = owner.UserId, Player2 = owner.UserId }, { Player1 = 12, Player2 = 12 }, true)
		event:FireClient(guest, "like", owner.UserId)
		await(function()
			return Profile.get(owner).likes == 1
		end, 5, "visit like was not granted")
		event:FireClient(guest, "like", owner.UserId)
		task.wait(0.5)
		assert(Profile.get(owner).likes == 1, "duplicate like counted twice")
		table.insert(checks, "one like per visitor/day")
		event:FireClient(guest, "visit", guest.UserId)
		probe("home", { Player1 = owner.UserId, Player2 = guest.UserId }, { Player1 = 12, Player2 = 2 }, false)
		event:FireClient(guest, "visit", owner.UserId)
		probe("revisit", { Player1 = owner.UserId, Player2 = owner.UserId }, { Player1 = 12, Player2 = 12 }, true)
		assert(
			Profile.get(owner).scrap == ownerBefore and Profile.get(guest).scrap == guestBefore,
			"visits changed resource balances"
		)
		table.insert(checks, "no resource transfer or loss")
		event:FireClient(owner, "leave")
		await(function()
			return #Players:GetPlayers() == 1
		end, 15, "owner did not leave")
		probe("owner_left", { Player2 = guest.UserId }, { Player2 = 2 }, false)
		event:FireClient(guest, "visit", 999999)
		probe("absent_target", { Player2 = guest.UserId }, { Player2 = 2 }, false)
	end)
	STS:EndTest({ ok = ok, error = if ok then nil else tostring(err), checks = checks })
end)
