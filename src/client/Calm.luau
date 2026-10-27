--!nonstrict
-- The hero at home (DD-083, owner playtest: «на базе вернуть стандартную позу»): the procedural combat Rig
-- lets go of the body and Roblox's own idle / walk / run / jump / fall animations play, as in any Roblox
-- place. Only the local character is animated here; the Animator replicates it to everyone else.

local Calm = {}

local R15 = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
	sit = "rbxassetid://2506281703",
}
local R6 = {
	idle = "rbxassetid://180435571",
	walk = "rbxassetid://180426354",
	run = "rbxassetid://180426354",
	jump = "rbxassetid://125750702",
	fall = "rbxassetid://180436148",
	sit = "rbxassetid://178130996",
}

local state = nil -- { character, tracks = { name = AnimationTrack }, current }

local function load(character: Model)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local ids = if hum.RigType == Enum.HumanoidRigType.R15 then R15 else R6
	local tracks = {}
	for name, id in ids do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(a)
		end)
		if ok and track then
			track.Priority = if name == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
			track.Looped = name ~= "jump"
			tracks[name] = track
		end
	end
	return { character = character, hum = hum, tracks = tracks, current = nil }
end

local function play(name: string?)
	if state.current == name then
		return
	end
	if state.current and state.tracks[state.current] then
		state.tracks[state.current]:Stop(0.2)
	end
	state.current = name
	if name and state.tracks[name] then
		state.tracks[name]:Play(0.2)
	end
end

-- Every frame: on = the hero walks the shelter (not at the range, not in a fight or a scene).
function Calm.update(character: Model?, on: boolean)
	if state and state.character ~= character then
		play(nil)
		state = nil
	end
	if not character then
		return
	end
	if not on then
		if state then
			play(nil)
		end
		return
	end
	state = state or load(character)
	if not state then
		return
	end
	local hum = state.hum
	local st = hum:GetState()
	local v = hum.RootPart and hum.RootPart.AssemblyLinearVelocity or Vector3.zero
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if hum.Sit or st == Enum.HumanoidStateType.Seated then
		play("sit") -- DD-093: a chair in the cabin
	elseif st == Enum.HumanoidStateType.Jumping then
		play("jump")
	elseif st == Enum.HumanoidStateType.Freefall then
		play("fall")
	elseif speed > 0.6 then
		local name = if speed > 11 then "run" else "walk"
		play(name)
		local t = state.tracks[name]
		if t then
			t:AdjustSpeed(if name == "run" then speed / 16 else speed / 8)
		end
	else
		play("idle")
	end
end

return Calm
