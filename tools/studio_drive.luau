-- Dev-only Studio driver (Client DataModel): kites the hero in a circle and fires with a sweeping aim
-- through SwarmFrameHook (cards auto-picked). Run from MCP execute_luau:
--   loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8765/tools/studio_drive.luau"))()(90)
-- Call with 0 to stop.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

return function(seconds: number, radius: number?, cx: number?, cz: number?)
	local plr = Players.LocalPlayer
	pcall(function()
		RunService:UnbindFromRenderStep("SporeDrive")
	end)
	if seconds <= 0 then
		return "stopped"
	end
	local hook = plr.PlayerScripts.Client:WaitForChild("SwarmFrameHook")
	local controls = require(plr.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
	controls:Disable()
	local t0 = os.clock()
	local r = radius or 26
	local ox, oz = cx or 0, cz or -10
	RunService:BindToRenderStep("SporeDrive", Enum.RenderPriority.Input.Value + 1, function()
		local t = os.clock() - t0
		if t > seconds then
			RunService:UnbindFromRenderStep("SporeDrive")
			controls:Enable()
			return
		end
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if hum and root then
			local a = t * 0.35
			local goal = Vector3.new(ox + math.cos(a) * r, 0, oz + math.sin(a) * r)
			local d = goal - Vector3.new(root.Position.X, 0, root.Position.Z)
			hum:Move(if d.Magnitude > 1 then d.Unit else Vector3.zero, false)
		end
		local s = t * 2.2
		pcall(function()
			hook:Invoke(0.0001, math.cos(s), math.sin(s), true)
		end)
	end)
	return "driving " .. seconds .. "s"
end
