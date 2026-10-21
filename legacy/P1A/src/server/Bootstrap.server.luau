--!nonstrict
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")
local Config=require(game.ReplicatedStorage.Shared.Config)
local Layout=require(game.ReplicatedStorage.Shared.Layout)
local Nav=require(script.Parent.Navigation)
local Guard=require(script.Parent.Guard)
local Combat=require(script.Parent.Combat)
local net=game.ReplicatedStorage.Remotes
local input,snapshot,fx=net.Input,net.Snapshot,net.FX
Players.CharacterAutoLoads=false
local session=nil
local owner=nil
local buckets={}
local simAccumulator,snapshotAccumulator=0,0
local serverMs=0
local rejected=0
local function log(event, data)
	if RunService:IsStudio() then print("[SWARMFALL] "..event.." "..HttpService:JSONEncode(data)) end
end
local function effect(kind, data)
	if session then fx:FireAllClients(session.id,kind,data) end
end
local function finish(reason)
	local s=session
	if not s or s.phase=="RESULTS" then return end
	s.phase="RESULTS" s.result=reason s.enemies={} s.active=0 s.dashUntil=0
	if owner and owner.Character then
		local root=owner.Character:FindFirstChild("HumanoidRootPart")
		if root then root.AssemblyLinearVelocity=Vector3.zero root.Anchored=true end
	end
	log("run_end",{runId=s.id,elapsed=s.elapsed,result=reason,kills=s.kills,
		firstShot=s.firstShot,firstKill=s.firstKill,peak=s.peak,rejected=rejected})
end
local function newRun(player)
	if owner and owner~=player then return end
	if session and session.phase~="RESULTS" then return end
	owner=player
	simAccumulator=0
	local s={id=HttpService:GenerateGUID(false),phase="LOADING",elapsed=0,phaseTime=0,
		hp=Config.Player.Health,ammo=Config.Weapon.Magazine,reloadUntil=0,lastShot=-100,
		sequence=0,enemies={},active=0,nextId=0,kills=0,peak=0,spawnClock=0,
		dashUntil=0,dashReady=0,graceUntil=0,field={},fieldClock=0,moveTokens=8,
		rng=Random.new(Config.Seed),lastPos=Vector3.new(0,3,-12),firstShot=nil,firstKill=nil}
	session=s
	-- Load asynchronously so no RemoteEvent handler yields while owning an incomplete transition.
	task.spawn(function()
		local ok,err=pcall(function() player:LoadCharacterAsync() end)
		if session~=s or owner~=player then return end
		if not ok then warn(err) finish("CHARACTER LOAD FAILED") return end
		local char=player.Character
		local hum=char and char:FindFirstChildOfClass("Humanoid")
		local root=char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not root then finish("CHARACTER MISSING") return end
		char:PivotTo(CFrame.new(0,3,-12))
		hum.MaxHealth=Config.Player.Health hum.Health=s.hp hum.WalkSpeed=Config.Player.Speed
		hum.JumpPower=0 hum.JumpHeight=0 hum.AutoRotate=false
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,false)
		local force=char:FindFirstChildOfClass("ForceField") if force then force:Destroy() end
		root.Anchored=false
		s.root=root s.hum=hum s.lastPos=root.Position s.phase="COUNTDOWN"
		hum.Died:Once(function() if session==s then s.hp=0 finish("YOU WERE OVERRUN") end end)
		log("run_start",{runId=s.id,seed=Config.Seed,build=Config.Build})
	end)
end
local function hitPlayer(e,damage)
	local s=session
	if not s or s.phase~="ACTIVE" or s.elapsed<Config.Player.SafeSeconds or s.elapsed<s.graceUntil then return end
	if not Nav.clear(e.pos,Vector3.new(s.root.Position.X,2.4,s.root.Position.Z),0.1) then return end
	s.graceUntil=s.elapsed+Config.Player.Grace
	s.hp=math.max(0,s.hp-damage)
	s.hum.Health=s.hp
	effect("HURT",{pos=e.pos,hp=s.hp})
	if s.hp<=0 then finish("YOU WERE OVERRUN") end
end
local function startReload(s)
	if s.reloadUntil<=s.elapsed and s.ammo<Config.Weapon.Magazine then
		s.reloadUntil=s.elapsed+Config.Weapon.Reload effect("RELOAD",{})
	end
end
local function fire(s,direction)
	if s.elapsed-s.lastShot < 1/Config.Weapon.Rate-0.005 or s.reloadUntil>s.elapsed then return end
	if s.ammo<=0 then startReload(s) return end
	s.lastShot=s.elapsed s.ammo-=1
	if not s.firstShot then s.firstShot=s.elapsed log("first_shot",{elapsed=s.elapsed}) end
	local origin=Vector3.new(s.lastPos.X,2.4,s.lastPos.Z)
	local enemy,point=Combat.query(origin,direction,s.enemies,workspace.Level01.Geometry)
	local killed=false
	if enemy then
		enemy.hp-=Config.Weapon.Damage enemy.stagger=s.elapsed+0.09
		if enemy.hp<=0 then
			killed=true s.enemies[enemy.id]=nil s.active-=1 s.kills+=1
			if not s.firstKill then s.firstKill=s.elapsed log("first_kill",{elapsed=s.elapsed}) end
		end
	end
	effect("SHOT",{origin=origin,point=point,direction=direction,hit=enemy and enemy.id,
		kill=killed,kind=enemy and enemy.kind,sequence=s.sequence})
	if s.ammo==0 then startReload(s) end
end
input.OnServerEvent:Connect(function(player,action,runId,sequence,direction,...)
	local now=os.clock()
	local bucket=buckets[player]
	if not bucket then bucket={tokens=24,time=now} buckets[player]=bucket end
	if not Guard.bucket(bucket,now,18,24) then rejected+=1 return end
	if select("#",...)>0 or type(action)~="string" then rejected+=1 return end
	if action=="START" then
		if type(runId)~="string" or (session and runId~=session.id) then rejected+=1 return end
		newRun(player) return
	end
	local s=session
	if not s or owner~=player or runId~=s.id or not Guard.sequence(sequence,s.sequence) then rejected+=1 return end
	if action=="PAUSE" then
		if s.phase=="ACTIVE" then s.sequence=sequence s.phase="PAUSED" s.root.Anchored=true
		elseif s.phase=="PAUSED" then s.sequence=sequence s.phase="ACTIVE" s.root.Anchored=false end
		return
	end
	if s.phase~="ACTIVE" or not s.root or s.hp<=0 then rejected+=1 return end
	-- Never allow firing from an unvalidated replicated position between simulation ticks.
	if (s.root.Position-s.lastPos).Magnitude>9 or not Nav.free(s.root.Position,1.4) then rejected+=1 return end
	if action=="FIRE" or action=="DASH" then
		if not Guard.direction(direction) then rejected+=1 return end
	else
		if action~="RELOAD" then rejected+=1 return end
	end
	s.sequence=sequence
	if action=="FIRE" then fire(s,direction.Unit)
	elseif action=="RELOAD" then startReload(s)
	elseif action=="DASH" and s.elapsed>=s.dashReady then
		s.dashReady=s.elapsed+Config.Player.DashCooldown
		s.dashUntil=s.elapsed+Config.Player.DashDuration s.dashDirection=direction.Unit
		s.root:SetNetworkOwner(nil) effect("DASH",{pos=s.root.Position})
	end
end)
local function spawnEnemy(s)
	if s.active>=Config.MaxActiveEnemies then return end
	local choices=if s.elapsed<25 then {1,2} elseif s.elapsed<50 then {1,2,5} else {2,5,6}
	local p=s.root.Position
	for _=1,12 do
		local marker=Layout.Spawns[choices[s.rng:NextInteger(1,#choices)]]
		local pos=Vector3.new(marker[2]+s.rng:NextNumber(-7,7),2.4,marker[3]+s.rng:NextNumber(-7,7))
		if (pos-Vector3.new(p.X,2.4,p.Z)).Magnitude>=55 and Nav.free(pos,3) then
			local stalkers=0 for _,e in pairs(s.enemies) do if e.kind=="EN_STALKER" then stalkers+=1 end end
			local kind=if s.elapsed>15 and stalkers<math.floor((s.active+1)*0.2) and s.rng:NextNumber()<0.2 then "EN_STALKER" else "EN_RUNNER"
			s.nextId+=1
			s.enemies[s.nextId]={id=s.nextId,kind=kind,pos=pos,hp=Config.Enemies[kind].Health,
				state="SPAWNING",untilTime=s.elapsed+2,cooldown=0,aim=Vector3.zAxis,stagger=0}
			s.active+=1 s.peak=math.max(s.peak,s.active)
			return
		end
	end
end
local function enemyStep(s,dt)
	local target=Vector3.new(s.root.Position.X,2.4,s.root.Position.Z)
	s.fieldClock-=dt
	if s.fieldClock<=0 then s.field=Nav.field(target) s.fieldClock=0.5 end
	-- Spatial buckets for local separation, not all-pairs physics.
	local grid={}
	local function key(x,z) return x..":"..z end
	for _,e in pairs(s.enemies) do
		local k=key(math.floor(e.pos.X/8),math.floor(e.pos.Z/8))
		grid[k]=grid[k] or {} table.insert(grid[k],e)
	end
	for _,e in pairs(s.enemies) do
		if s.phase~="ACTIVE" then break end
		local def=Config.Enemies[e.kind]
		local delta=target-e.pos local distance=delta.Magnitude
		if e.state=="SPAWNING" then
			if s.elapsed>=e.untilTime then e.state="APPROACH" end
		elseif e.state=="TELEGRAPH" then
			if s.elapsed>=e.untilTime then e.state="ATTACK" e.untilTime=s.elapsed+def.LungeTime end
		elseif e.state=="ATTACK" then
			e.pos=Nav.move(e.pos,e.aim*def.LungeSpeed*dt,def.Radius)
			if (target-e.pos).Magnitude<4.8 then hitPlayer(e,def.Damage) e.state="RECOVER" e.untilTime=s.elapsed+0.65 end
			if s.elapsed>=e.untilTime then e.state="RECOVER" e.untilTime=s.elapsed+0.65 end
		elseif e.state=="RECOVER" then
			if s.elapsed>=e.untilTime then e.state="APPROACH" end
		elseif s.elapsed>=e.stagger then
			if e.kind=="EN_STALKER" and distance<22 and s.elapsed>=e.cooldown then
				e.state="TELEGRAPH" e.untilTime=s.elapsed+def.Windup e.cooldown=s.elapsed+def.Cooldown
				e.aim=if distance>0.1 then delta.Unit else Vector3.zAxis
				effect("TELEGRAPH",{id=e.id,pos=e.pos,direction=e.aim})
			else
				local direction=Nav.direction(e.pos,target,s.field)
				local separation=Vector3.zero
				local gx,gz=math.floor(e.pos.X/8),math.floor(e.pos.Z/8)
				for x=-1,1 do for z=-1,1 do for _,other in ipairs(grid[key(gx+x,gz+z)] or {}) do
					local d=e.pos-other.pos local m=d.Magnitude
					if other~=e and m>0.01 and m<5 then separation+=d.Unit*(5-m)/5 end
				end end end
				local move=direction+separation*0.65
				if move.Magnitude>0.01 and distance>2.8 then e.pos=Nav.move(e.pos,move.Unit*def.Speed*dt,def.Radius) end
				if e.kind=="EN_RUNNER" and distance<4.4 and s.elapsed>=e.cooldown then
					e.cooldown=s.elapsed+def.Cooldown hitPlayer(e,def.Damage)
				end
			end
		end
	end
end
local function movement(s,dt)
	local root=s.root
	if not root or not root.Parent then finish("CHARACTER LOST") return end
	local p=root.Position
	if not Guard.finite(p.X) or not Guard.finite(p.Y) or not Guard.finite(p.Z) then root.CFrame=CFrame.new(s.lastPos) return end
	if s.elapsed<s.dashUntil then
		local nextPos=Nav.move(s.lastPos,s.dashDirection*Config.Player.DashSpeed*dt,1.7)
		root.CFrame=CFrame.lookAt(nextPos,nextPos+s.dashDirection) root.AssemblyLinearVelocity=Vector3.zero
		s.lastPos=nextPos s.wasDash=true return
	elseif s.wasDash then s.wasDash=false root:SetNetworkOwnershipAuto() end
	s.moveTokens=math.min(8,s.moveTokens+22*dt)
	local travel=Vector3.new(p.X-s.lastPos.X,0,p.Z-s.lastPos.Z).Magnitude
	if travel>s.moveTokens or p.Y<0 or p.Y>9 or not Nav.clear(s.lastPos,p,1.3) then
		root.CFrame=CFrame.new(s.lastPos) root.AssemblyLinearVelocity=Vector3.zero
	else s.moveTokens-=travel s.lastPos=p end
end
local function sendSnapshot()
	local s=session
	if not s then snapshot:FireAllClients({phase="READY",runId="",enemies={},activeEnemyCount=0}) return end
	local enemies={} local actual=0
	for _,e in pairs(s.enemies) do
		actual+=1 table.insert(enemies,{e.id,e.kind,e.pos,e.hp,e.state,e.aim,e.untilTime})
	end
	s.active=actual
	local data={runId=s.id,phase=s.phase,elapsed=s.elapsed,remaining=math.max(0,Config.Duration-s.elapsed),
		countdown=math.max(0,Config.Countdown-s.phaseTime),hp=s.hp,ammo=s.ammo,kills=s.kills,
		reload=math.max(0,s.reloadUntil-s.elapsed),dash=math.max(0,s.dashReady-s.elapsed),
		enemies=enemies,activeEnemyCount=actual,owner=owner and owner.UserId,result=s.result,
		safe=math.max(0,Config.Player.SafeSeconds-s.elapsed)}
	if RunService:IsStudio() then data.debug={simMs=serverMs,rejected=rejected,peak=s.peak,firstShot=s.firstShot,firstKill=s.firstKill} end
	snapshot:FireAllClients(data)
	if RunService:IsStudio() then
		workspace:SetAttribute("ActiveEnemyCount",actual) workspace:SetAttribute("RunPhase",s.phase)
		workspace:SetAttribute("RejectedInputs",rejected) workspace:SetAttribute("Kills",s.kills)
		workspace:SetAttribute("Ammo",s.ammo) workspace:SetAttribute("Elapsed",s.elapsed)
		workspace:SetAttribute("RunId",s.id) workspace:SetAttribute("Health",s.hp)
	end
end
RunService.Heartbeat:Connect(function(dt)
	local begin=os.clock()
	local s=session
	if s then
		if s.phase=="COUNTDOWN" then s.phaseTime+=dt if s.phaseTime>=Config.Countdown then s.phase="ACTIVE" end end
		if s.phase=="ACTIVE" then
			-- Bounded simulation slowdown under a stall; gameplay clock follows effective dt.
			local step=math.min(dt,0.1) s.elapsed+=step movement(s,step)
			if s.reloadUntil>0 and s.elapsed>=s.reloadUntil then s.reloadUntil=0 s.ammo=Config.Weapon.Magazine end
			simAccumulator+=step
			if simAccumulator>=Config.SimStep then
				local simDt=simAccumulator simAccumulator=0 enemyStep(s,simDt)
				s.spawnClock+=simDt
				local interval=if s.elapsed<25 then 0.42 elseif s.elapsed<50 then 0.32 else 0.25
				if s.spawnClock>=interval then s.spawnClock=0 spawnEnemy(s) end
			end
			if s.elapsed>=Config.Duration then finish("YARD SECURED") end
		end
	end
	serverMs=(os.clock()-begin)*1000
	snapshotAccumulator+=dt
	if snapshotAccumulator>=Config.SnapshotStep then snapshotAccumulator=0 sendSnapshot() end
end)
Players.PlayerRemoving:Connect(function(player)
	buckets[player]=nil
	if player==owner then session=nil owner=nil simAccumulator=0 end
end)
if RunService:IsStudio() then
	task.defer(function() require(script.Parent.SmokeTests).run() end)
end
log("boot",{build=Config.Build,cap=Config.MaxActiveEnemies})
