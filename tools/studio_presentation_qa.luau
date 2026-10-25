-- Run with execute_luau in Studio Client after ArtTemplates.Ready. This isolates the enemy renderer
-- from the running game's module, exercises pooled-ring lifecycle, then removes its test instances.
local client = game.Players.LocalPlayer.PlayerScripts.Client
local codec = require(game.ReplicatedStorage.Shared.Codec)
local clone = client.EnemyView:Clone()
clone.Name = "PresentationLifecycleQA"
clone.Parent = client
local ev = require(clone)
local folder
local checks = {}
local function check(name, condition)
	assert(condition, name)
	table.insert(checks, name)
end
local function row(id, x)
	return { id = id, kind = 2, x = x, z = 0, facing = 0, hp = 1, flags = 0, state = codec.State.IDLE }
end
local ok, err = xpcall(function()
	local art = game.ReplicatedStorage:WaitForChild("ArtTemplates", 20)
	assert(art and art:GetAttribute("Ready"), "Wait for art readiness before running QA")
	for _, key in
		{ "IND_DRILL_1", "IND_DRILL_2", "IND_DRILL_3", "IND_NODE_1", "IND_NODE_2", "IND_NODE_3", "SPECIMEN_FRAME" }
	do
		check("asset " .. key, art:FindFirstChild(key) ~= nil)
	end
	ev.init()
	task.wait(0.5) -- let the small warm-up batches complete before cleanup
	ev.snapshot({ row(65000, 0) }, 1)
	ev.update(1 / 60, Vector3.new(0, 30, 0))
	local model = ev.records[65000].model
	local ring = model.ring
	folder = ring.Parent
	check("live ring visible", ring.Position.Y > -100)
	ev.snapshot({}, 0)
	check("snapshot removal hides ring", ring.Position.Y < -100)
	ev.snapshot({ row(65001, 4) }, 1)
	ev.update(1 / 60, Vector3.new(0, 30, 0))
	check("pooled ring reused", ev.records[65001].model == model and ring.Position.Y > -100)
	ev.clear()
	check("return home hides ring", ring.Position.Y < -100)
	ev.snapshot({ row(65002, 8) }, 1)
	ev.update(1 / 60, Vector3.new(0, 30, 0))
	ev.kill(65002)
	check("death hides ring", ring.Position.Y < -100)
	ev.update(1, Vector3.new(0, 30, 0))
	ev.clear()
end, debug.traceback)
if folder then
	folder:Destroy()
end
clone:Destroy()
assert(ok, err)
return game:GetService("HttpService"):JSONEncode({ passed = #checks, checks = checks })
