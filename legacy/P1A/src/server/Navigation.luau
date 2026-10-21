--!strict
local Layout = require(game.ReplicatedStorage.Shared.Layout)
local Navigation = {}
local CELL, NX, NZ = 8, 44, 39
local function key(x, z) return z * NX + x + 1 end
local function position(x, z) return Vector3.new(-172 + x * CELL, 2.4, -152 + z * CELL) end
function Navigation.free(p: Vector3, radius: number): boolean
	if math.abs(p.X) > Layout.HalfX - radius - 2 or math.abs(p.Z) > Layout.HalfZ - radius - 2 then return false end
	for _, o in ipairs(Layout.Obstacles) do
		if math.abs(p.X-o[2]) < o[4]/2+radius and math.abs(p.Z-o[3]) < o[5]/2+radius then return false end
	end
	return true
end
-- Swept samples <= 0.75 studs prevent crossing even the narrowest solid.
function Navigation.clear(a: Vector3, b: Vector3, radius: number): boolean
	local count = math.max(1, math.ceil((b-a).Magnitude / 0.75))
	for i = 1, count do if not Navigation.free(a:Lerp(b, i/count), radius) then return false end end
	return true
end
function Navigation.move(a: Vector3, delta: Vector3, radius: number): Vector3
	if Navigation.clear(a, a+delta, radius) then return a+delta end
	local x = Vector3.new(delta.X, 0, 0)
	if Navigation.clear(a, a+x, radius) then return a+x end
	local z = Vector3.new(0, 0, delta.Z)
	if Navigation.clear(a, a+z, radius) then return a+z end
	return a
end
local walkable = {}
for z=0,NZ-1 do for x=0,NX-1 do walkable[key(x,z)] = Navigation.free(position(x,z), 3) end end
local offsets = {{1,0},{-1,0},{0,1},{0,-1}}
function Navigation.field(target: Vector3)
	local tx = math.clamp(math.floor((target.X+172)/CELL+0.5),0,NX-1)
	local tz = math.clamp(math.floor((target.Z+152)/CELL+0.5),0,NZ-1)
	local nearest, best = nil, math.huge
	for z=0,NZ-1 do for x=0,NX-1 do
		if walkable[key(x,z)] then
			local d=(x-tx)^2+(z-tz)^2
			if d<best then best=d nearest={x,z} end
		end
	end end
	if not nearest then return {} end
	local queue, distances = {nearest}, {[key(nearest[1],nearest[2])]=0}
	local head=1
	while head<=#queue do
		local c=queue[head] head+=1
		for _,o in ipairs(offsets) do
			local x,z=c[1]+o[1],c[2]+o[2]
			local k=key(x,z)
			if x>=0 and x<NX and z>=0 and z<NZ and walkable[k] and distances[k]==nil then
				distances[k]=distances[key(c[1],c[2])]+1 table.insert(queue,{x,z})
			end
		end
	end
	return distances
end
function Navigation.direction(p: Vector3, target: Vector3, field): Vector3
	local delta=Vector3.new(target.X-p.X,0,target.Z-p.Z)
	if delta.Magnitude<0.1 then return Vector3.zero end
	if Navigation.clear(p,p+delta,2.5) then return delta.Unit end
	local x=math.clamp(math.floor((p.X+172)/CELL+0.5),0,NX-1)
	local z=math.clamp(math.floor((p.Z+152)/CELL+0.5),0,NZ-1)
	local best, goal=math.huge,nil
	for dz=-1,1 do for dx=-1,1 do
		local cx,cz=x+dx,z+dz
		if cx>=0 and cx<NX and cz>=0 and cz<NZ then
			local candidate=position(cx,cz)
			local cost=field[key(cx,cz)]
			if cost and cost<best and (candidate-p).Magnitude>0.5 and Navigation.clear(p,candidate,2.5) then
				best=cost goal=candidate
			end
		end
	end end
	if goal then return (goal-p).Unit end
	return Vector3.zero
end
return Navigation
