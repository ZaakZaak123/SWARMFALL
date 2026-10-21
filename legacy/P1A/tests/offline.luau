-- Run from repository root: lune run tests/offline.luau
local fs=require("@lune/fs")
local luau=require("@lune/luau")
local roblox=require("@lune/roblox")
local count=0
for _,dir in {"shared","server","client","startercharacter"} do
	for _,name in fs.readDir("src/"..dir) do
		if name:sub(-5)==".luau" then
			luau.compile(fs.readFile("src/"..dir.."/"..name)) count+=1
		end
	end
end
print("PASS compile",count,"Luau files")
local game=roblox.deserializePlace(fs.readFile("build/SWARMFALL_P1A.rbxlx"))
assert(game:GetService("Workspace").Level01.Geometry.ArenaFloor.Size==roblox.Vector3.new(360,2,320))
assert(game:GetService("ReplicatedStorage").Remotes.Input.ClassName=="RemoteEvent")
print("PASS native place deserialization and arena dimensions")
local layout=luau.load(fs.readFile("src/shared/Layout.luau"))()
local env={Vector3=roblox.Vector3,game={ReplicatedStorage={Shared={Layout=layout}}},require=function(value) return value end}
local nav=luau.load(fs.readFile("src/server/Navigation.luau"),{environment=env})()
local V=roblox.Vector3
local paths=0
for _,target in {V.new(0,2.4,-12),V.new(0,2.4,82),V.new(100,2.4,0),V.new(0,2.4,-85),V.new(-92,2.4,0)} do
	local field=nav.field(target)
	for _,spawn in layout.Spawns do
		local p=V.new(spawn[2],2.4,spawn[3])
		for _=1,900 do
			if (p-target).Magnitude<5 then break end
			p=nav.move(p,nav.direction(p,target,field)*1.4,2.4)
		end
		assert((p-target).Magnitude<5,"Blocked route "..spawn[1].." -> "..tostring(target)) paths+=1
	end
end
print("PASS",paths,"actual navigation routes to all five sectors")
-- Full inner and outer loops preserve >=14-stud clearance, without Dash.
for _,span in {44,144} do
	for n=-span,span,2 do
		for _,point in {V.new(n,2.4,span),V.new(n,2.4,-span),V.new(span,2.4,n),V.new(-span,2.4,n)} do
			assert(nav.free(point,7),"Loop width <14 at "..tostring(point))
		end
	end
end
print("PASS two continuous loops, 14-stud clearance")
