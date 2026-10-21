--!strict
local Config = require(game.ReplicatedStorage.Shared.Config)
local Combat = {}
-- Analytic sphere entry distance; this uses SERVER positions, never a client hit ID.
function Combat.sphere(origin: Vector3, direction: Vector3, center: Vector3, radius: number): number?
	local offset = origin-center
	local b = offset:Dot(direction)
	local discriminant = b*b-offset:Dot(offset)+radius*radius
	if discriminant < 0 then return nil end
	local entry = -b-math.sqrt(discriminant)
	local exit = -b+math.sqrt(discriminant)
	if exit < 0 then return nil end
	return math.max(0,entry)
end
function Combat.query(origin: Vector3, direction: Vector3, enemies, geometry: Instance)
	local params=RaycastParams.new()
	params.FilterType=Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances={geometry}
	local wall=workspace:Raycast(origin,direction*Config.Weapon.Range,params)
	local distance=if wall then wall.Distance else Config.Weapon.Range
	local target=nil
	for _,e in pairs(enemies) do
		if e.hp>0 and e.state~="SPAWNING" then
			local hit=Combat.sphere(origin,direction,e.pos,Config.Enemies[e.kind].Radius)
			if hit and hit<distance then target=e distance=hit end
		end
	end
	return target, origin+direction*distance
end
return Combat
