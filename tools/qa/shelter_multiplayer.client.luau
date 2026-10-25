-- Companion for shelter_multiplayer.server.luau; injected only into a local Studio test.
if not game:GetService("RunService"):IsStudio() or game.PlaceId ~= 0 then
	return
end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local event = RS:WaitForChild("CodexShelterQA", 60)
if not event then
	return
end
local state, input, last = RS:WaitForChild("Remotes"):WaitForChild("State"), RS.Remotes.Input, nil
state.OnClientEvent:Connect(function(_, info)
	last = info
end)
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
local function myRoom()
	if last and last.mode == "LOBBY" and last.lobby.shelter then
		return last.lobby.shelter.id
	end
	if last and last.hub then
		for _, h in last.hub.hunters do
			if h.id == player.UserId then
				return h.room
			end
		end
	end
	return nil
end
event.OnClientEvent:Connect(function(action, data)
	if
		action == "visit"
		or action == "like"
		or action == "ready"
		or action == "continue"
		or action == "camp"
		or action == "devSkip"
	then
		input:FireServer(action, data)
	elseif action == "open" then
		input:FireServer("recruit", true)
		local sq
		await(function()
			if not last or not last.hub then
				return false
			end
			for _, s in last.hub.squads do
				if s.host == player.UserId and s.open then
					sq = s
					return true
				end
			end
			return false
		end, 8, "no open squad")
		event:FireServer("open", { squad = sq.id })
	elseif action == "join" then
		input:FireServer("join", data)
		await(function()
			if not last or not last.hub then
				return false
			end
			for _, s in last.hub.squads do
				if s.id == data then
					for _, member in s.players do
						if member.id == player.UserId then
							return true
						end
					end
				end
			end
			return false
		end, 8, "did not join squad")
		event:FireServer("joined", { ok = true })
	elseif action == "waitRun" then
		await(function()
			return last and last.run and last.run.phase == "ACTIVE"
		end, 35, "run not active")
		event:FireServer("run", { ok = true })
	elseif action == "waitResults" then
		await(function()
			return last and last.run and last.run.phase == "RESULTS"
		end, 35, "no results")
		event:FireServer("results", { ok = true })
	elseif action == "leave" then
		game:GetService("StudioTestService"):LeaveTest()
	elseif action == "probe" then
		local ok, err = pcall(function()
			await(function()
				return myRoom() == data.room
			end, 15, "wrong authoritative room")
			task.wait(0.5)
			local lab = workspace:FindFirstChild("BaseView") and workspace.BaseView:FindFirstChild("Spot_LAB")
			local tanks = 0
			if lab then
				for _, d in lab:GetDescendants() do
					if d:IsA("Model") and d.Name:sub(1, 5) == "Tank_" then
						tanks += 1
					end
				end
			end
			assert(tanks == data.tanks, "tank count " .. tanks)
			for _, other in Players:GetPlayers() do
				if other == player then
					continue
				end
				local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				assert(root, "other avatar missing")
				local torso = other.Character:FindFirstChild("UpperTorso") or other.Character:FindFirstChild("Torso")
				assert(torso and (torso.LocalTransparencyModifier < 0.9) == data.visible, "other avatar visibility")
				assert((other.Character:FindFirstChild("SwarmGear") ~= nil) == data.visible, "other weapon visibility")
			end
		end)
		event:FireServer(data.phase, { ok = ok, error = if ok then nil else tostring(err) })
	end
end)
await(function()
	return myRoom() ~= nil and player.PlayerGui:FindFirstChild("SporeBase") ~= nil
end, 60, "client did not reach shelter")
input:FireServer("profile")
task.wait(2)
event:FireServer("ready", { ok = true })
