--!nonstrict
local TweenService=game:GetService("TweenService")
local Config=require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Visuals={}
local cyan=Color3.fromRGB(83,250,239)
local orange=Color3.fromRGB(255,132,59)
local function part(parent,name,size,color,cf,material)
	local p=Instance.new("Part") p.Name=name p.Size=size p.Color=color p.CFrame=cf or CFrame.new()
	p.Anchored=true p.CanCollide=false p.CanTouch=false p.CanQuery=false p.CastShadow=false
	p.Material=material or Enum.Material.SmoothPlastic p.Parent=parent return p
end
function Visuals.new()
	local self=setmetatable({models={},low=false,voices={},voiceIndex=0,effects=0}, {__index=Visuals})
	self.folder=Instance.new("Folder") self.folder.Name="ClientCombatVisuals" self.folder.Parent=workspace
	for i=1,12 do
		local emitter=part(self.folder,"SoundEmitter",Vector3.one,cyan) emitter.Transparency=1
		local sound=Instance.new("Sound") sound.RollOffMinDistance=12 sound.RollOffMaxDistance=180 sound.Parent=emitter
		self.voices[i]=sound
	end
	return self
end
function Visuals:sound(id,pos,volume,speed)
	self.voiceIndex=self.voiceIndex%#self.voices+1
	local sound=self.voices[self.voiceIndex]
	sound:Stop() sound.Parent.Position=pos sound.SoundId=id sound.Volume=volume sound.PlaybackSpeed=speed or 1 sound:Play()
end
function Visuals:flash(pos,color,size,duration)
	if self.effects>=80 then return end
	self.effects+=1
	local p=part(self.folder,"Pulse",Vector3.one*size,color,CFrame.new(pos),Enum.Material.Neon)
	p.Shape=Enum.PartType.Ball
	TweenService:Create(p,TweenInfo.new(duration),{Size=p.Size*2.4,Transparency=1}):Play()
	task.delay(duration,function() p:Destroy() self.effects-=1 end)
end
function Visuals:line(a,b,color,width,duration)
	local length=(b-a).Magnitude if length<.01 or self.effects>=80 then return end
	self.effects+=1
	local p=part(self.folder,"ArcTrace",Vector3.new(width,width,length),color,CFrame.lookAt((a+b)/2,b),Enum.Material.Neon)
	TweenService:Create(p,TweenInfo.new(duration),{Transparency=1}):Play()
	task.delay(duration,function() p:Destroy() self.effects-=1 end)
end
function Visuals:enemy(id,kind,pos)
	local model=Instance.new("Model") model.Name=kind.."_"..id model.Parent=self.folder
	local stalker=kind=="EN_STALKER"
	local color=if stalker then Color3.fromRGB(196,83,203) else Color3.fromRGB(225,104,53)
	local body=part(model,"Carapace",if stalker then Vector3.new(2.5,2.5,4.4) else Vector3.new(3.4,2,3.7),color)
	body.Shape=Enum.PartType.Ball model.PrimaryPart=body
	local pieces={{body,CFrame.new()}}
	local head=part(model,"Face",Vector3.new(2.1,1.1,1.3),Color3.fromRGB(43,25,36)) table.insert(pieces,{head,CFrame.new(0,0,-2)})
	local eye=part(model,"Eyes",Vector3.new(1.6,.28,.2),cyan,nil,Enum.Material.Neon) table.insert(pieces,{eye,CFrame.new(0,.2,-2.7)})
	for side=-1,1,2 do for index=1,2 do
		local leg=part(model,"Leg",Vector3.new(.6,.7,if stalker and index==2 then 3.3 else 2.2),Color3.fromRGB(75,43,57))
		table.insert(pieces,{leg,CFrame.new(side*1.9,-.8,(index-1.5)*2)*CFrame.Angles(0,side*.6,side*.3)})
	end end
	local warning=part(model,"LungeLane",Vector3.new(5,.1,18),Color3.fromRGB(255,68,58),nil,Enum.Material.Neon)
	warning.Transparency=1
	local e={model=model,body=body,pieces=pieces,pos=pos,target=pos,state="SPAWNING",kind=kind,color=color,aim=Vector3.zAxis,warning=warning,hitUntil=0,death=false}
	self.models[id]=e
	self:sound(Config.Sounds.Warning,pos,.15,.6)
	return e
end
function Visuals:snapshot(enemies)
	local seen={}
	for _,row in ipairs(enemies) do
		local id,kind,pos,hp,state,aim=row[1],row[2],row[3],row[4],row[5],row[6]
		seen[id]=true
		local e=self.models[id] or self:enemy(id,kind,pos)
		e.target=pos e.state=state e.aim=aim
	end
	for id,e in pairs(self.models) do
		if not seen[id] then
			if not e.death then e.model:Destroy() end
			self.models[id]=nil
		end
	end
end
function Visuals:hit(id,killed,dir)
	local e=self.models[id] if not e or e.death then return end
	e.hitUntil=os.clock()+.09
	self:flash(e.pos,if killed then orange else cyan,if killed then 2.2 else .8,.18)
	if killed then
		e.death=true e.warning:Destroy()
		for _,piece in ipairs(e.pieces) do
			local p=piece[1]
			local collapse=p.CFrame+dir*2-Vector3.yAxis*1.8
			TweenService:Create(p,TweenInfo.new(.32),{CFrame=collapse*CFrame.Angles(.8,0,.5),Transparency=1,Size=p.Size*.4}):Play()
		end
		task.delay(.35,function() e.model:Destroy() end)
	else e.pos-=dir*.6 end
end
function Visuals:update(dt)
	local clock=os.clock()
	for id,e in pairs(self.models) do
		if e.death then continue end
		local velocity=e.target-e.pos
		e.pos=e.pos:Lerp(e.target,math.min(1,dt*16))
		local direction=if e.state=="TELEGRAPH" or e.state=="ATTACK" then e.aim elseif velocity.Magnitude>.1 then velocity.Unit else e.aim
		local bob=if e.state=="APPROACH" then math.sin(clock*18+id)*.15 else 0
		local cf=CFrame.lookAt(e.pos+Vector3.yAxis*bob,e.pos+Vector3.yAxis*bob+direction)
		for _,piece in ipairs(e.pieces) do piece[1].CFrame=cf*piece[2] end
		e.body.Color=if clock<e.hitUntil then Color3.new(1,1,1) else e.color
		e.body.Transparency=if e.state=="SPAWNING" then .45 else 0
		local a=Vector3.new(e.pos.X,.12,e.pos.Z) local b=a+e.aim*18
		e.warning.CFrame=CFrame.lookAt((a+b)/2,b)
		e.warning.Transparency=if e.state=="TELEGRAPH" then .20 elseif e.state=="SPAWNING" then .65 else 1
	end
end
function Visuals:clear()
	for _,e in pairs(self.models) do e.model:Destroy() end self.models={}
end
function Visuals:gun(root,direction)
	if not self.weapon then
		self.weapon=part(self.folder,"W_ARC_RIFLE",Vector3.new(.85,.85,3.5),Color3.fromRGB(33,57,67))
		self.barrel=part(self.folder,"ArcBarrel",Vector3.new(.35,.35,1.4),cyan,nil,Enum.Material.Neon)
	end
	local base=Vector3.new(root.Position.X,2.4,root.Position.Z)
	local cf=CFrame.lookAt(base,base+direction)
	self.weapon.CFrame=cf*CFrame.new(.9,.1,-1.7) self.barrel.CFrame=cf*CFrame.new(.9,.1,-3.6)
	return self.barrel.Position+direction*.7
end
return Visuals
