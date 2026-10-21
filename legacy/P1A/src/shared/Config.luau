--!strict
local Config = {
	Build = "P1A-20261021", Seed = 211026, Duration = 75, Countdown = 3,
	MaxActiveEnemies = 48, SimStep = 0.1, SnapshotStep = 0.1,
	Player = {Health = 100, Speed = 16, Grace = 0.4, SafeSeconds = 8,
		DashSpeed = 64, DashDuration = 0.25, DashCooldown = 5},
	Weapon = {Id = "W_ARC_RIFLE", Damage = 12, Rate = 6, Range = 85,
		Magazine = 36, Reload = 1.5},
	Enemies = {
		EN_RUNNER = {Health = 24, Speed = 14, Damage = 7, Cooldown = 1.2, Radius = 2.1},
		EN_STALKER = {Health = 38, Speed = 19, Damage = 9, Cooldown = 3,
			Radius = 2.4, Windup = 0.65, LungeSpeed = 42, LungeTime = 0.38},
	},
	Camera = {Pitch = 50, Distance = 55, FOV = 65},
	Sounds = {
		Fire = "rbxasset://sounds/impact_explosion_03.mp3",
		Hit = "rbxasset://sounds/action_jump_land.mp3",
		Kill = "rbxasset://sounds/impact_water.mp3",
		Reload = "rbxasset://sounds/action_get_up.mp3",
		Warning = "rbxasset://sounds/ouch.ogg",
	},
}
local function freeze(t)
	for _, v in pairs(t) do if type(v) == "table" then freeze(v) end end
	return table.freeze(t)
end
return freeze(Config)
