--!nonstrict
local Tests={}
function Tests.run()
	assert(game:GetService("RunService"):IsStudio(),"Studio-only tests")
	local Guard=require(script.Parent.Guard)
	local Nav=require(script.Parent.Navigation)
	local Combat=require(script.Parent.Combat)
	local passed=0
	local function check(name,fn)
		local ok,err=pcall(fn)
		if not ok then error("[SWARMFALL TEST FAIL] "..name..": "..tostring(err)) end
		passed+=1 print("[SWARMFALL TEST PASS] "..name)
	end
	check("reject fabricated direction/NaN/inf",function()
		for _,bad in ipairs({{},"damage",Vector3.zero,Vector3.new(0,1,0),Vector3.new(0/0,0,1),Vector3.new(math.huge,0,0),Vector3.new(2,0,0)}) do assert(not Guard.direction(bad)) end
		assert(Guard.direction(Vector3.zAxis))
	end)
	check("replay and sequence validation",function()
		assert(not Guard.sequence(1,1)) assert(not Guard.sequence(0/0,0)) assert(not Guard.sequence(1.1,0)) assert(Guard.sequence(2,1))
	end)
	check("bounded remote rate",function()
		local bucket={tokens=24,time=0} local n=0
		for _=1,1000 do if Guard.bucket(bucket,0,18,24) then n+=1 end end
		assert(n==24) assert(Guard.bucket(bucket,1,18,24))
	end)
	check("ray sphere front/back and range geometry",function()
		assert(math.abs(Combat.sphere(Vector3.zero,Vector3.zAxis,Vector3.new(0,0,10),2)-8)<.01)
		assert(Combat.sphere(Vector3.zero,Vector3.zAxis,Vector3.new(0,0,-10),2)==nil)
		local enemies={[1]={pos=Vector3.new(23,2.4,20),hp=24,state="APPROACH",kind="EN_RUNNER"}}
		local enemy=Combat.query(Vector3.new(23,2.4,-20),Vector3.zAxis,enemies,workspace.Level01.Geometry)
		assert(enemy==nil,"Shot crossed CoreCoverE")
	end)
	check("dash cannot cross solid or boundary",function()
		assert(not Nav.clear(Vector3.new(23,3,-20),Vector3.new(23,3,20),1.7))
		assert(not Nav.free(Vector3.new(180,3,0),1.7))
	end)
	check("spawn clusters and navigation",function()
		local layout=require(game.ReplicatedStorage.Shared.Layout)
		for _,spawn in ipairs(layout.Spawns) do assert(Nav.free(Vector3.new(spawn[2],2.4,spawn[3]),3)) end
		local target=Vector3.new(0,2.4,-12) local field=Nav.field(target)
		for _,spawn in ipairs(layout.Spawns) do
			local p=Vector3.new(spawn[2],2.4,spawn[3])
			for _=1,600 do if (p-target).Magnitude<5 then break end p=Nav.move(p,Nav.direction(p,target,field)*1.4,2.4) end
			assert((p-target).Magnitude<5,"Cannot reach center from "..spawn[1])
		end
	end)
	print("[SWARMFALL TEST SUMMARY] "..passed.." passed")
end
return Tests
