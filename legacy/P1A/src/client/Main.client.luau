--!nonstrict
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local ContentProvider=game:GetService("ContentProvider")
local shared=game.ReplicatedStorage:WaitForChild("Shared")
local Config=require(shared:WaitForChild("Config"))
local Hud=require(script.Parent:WaitForChild("Hud"))
local Visuals=require(script.Parent:WaitForChild("Visuals"))
local player=Players.LocalPlayer
local net=game.ReplicatedStorage:WaitForChild("Remotes")
net:WaitForChild("Input") net:WaitForChild("Snapshot") net:WaitForChild("FX")
local hud=Hud.new()
local visuals=Visuals.new()
local state={phase="READY",runId="",enemies={}}
local sequence=0
local firing=false
local aimTouch=nil
local aim=Vector3.zAxis
local localShot=-100
local follow=nil
local frameTimes={}
local sampleIndex=0
local debugClock=0
local hitUntil=0
local hurtUntil=0
local faded={}
local menuOpen=false
local lastPacket=os.clock()
local touch=UIS.TouchEnabled and not UIS.MouseEnabled
local function resetInput()
	firing=false aimTouch=nil hud.knob.Position=UDim2.fromScale(.5,.5)
end
local function send(action,dir)
	sequence+=1 net.Input:FireServer(action,state.runId,sequence,dir)
end
local function character()
	local char=player.Character
	return char and char:FindFirstChild("HumanoidRootPart"),char and char:FindFirstChildOfClass("Humanoid")
end
local function dash()
	local root,hum=character()
	if state.phase~="ACTIVE" or not root or not hum then return end
	local dir=hum.MoveDirection
	if dir.Magnitude<.1 then dir=aim end
	send("DASH",Vector3.new(dir.X,0,dir.Z).Unit)
end
local function startOrResume()
	resetInput()
	if state.phase=="PAUSED" then send("PAUSE")
	elseif state.phase=="READY" or state.phase=="RESULTS" then net.Input:FireServer("START",state.runId,0) end
end
hud.start.Activated:Connect(startOrResume)
hud.pause.Activated:Connect(function() resetInput() send("PAUSE") end)
hud.dash.Activated:Connect(dash)
hud.ammo.Activated:Connect(function() send("RELOAD") end)
hud.quality.Activated:Connect(function() visuals.low=not visuals.low hud.quality.Text=if visuals.low then "FX LOW" else "FX HIGH" end)
local function updateTouch(input)
	local center=hud.aim.AbsolutePosition+hud.aim.AbsoluteSize/2
	local vector=Vector2.new(input.Position.X,input.Position.Y)-center
	local radius=hud.aim.AbsoluteSize.X*.36
	local offset=if vector.Magnitude>radius then vector.Unit*radius else vector
	hud.knob.Position=UDim2.new(.5,offset.X,.5,offset.Y)
	firing=vector.Magnitude>radius*.18 and state.phase=="ACTIVE"
	if firing then
		local camera=workspace.CurrentCamera
		local forward=Vector3.new(camera.CFrame.LookVector.X,0,camera.CFrame.LookVector.Z).Unit
		aim=(camera.CFrame.RightVector*vector.X-forward*vector.Y).Unit
	end
end
hud.aim.InputBegan:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.Touch and not aimTouch and state.phase=="ACTIVE" then
		aimTouch=input updateTouch(input)
	end
end)
UIS.InputChanged:Connect(function(input) if input==aimTouch then updateTouch(input) end end)
UIS.InputEnded:Connect(function(input)
	if input==aimTouch then resetInput() end
	if input.UserInputType==Enum.UserInputType.MouseButton1 then firing=false end
end)
UIS.InputBegan:Connect(function(input,processed)
	if processed or menuOpen then return end
	if input.KeyCode==Enum.KeyCode.Return and (state.phase=="READY" or state.phase=="RESULTS") then startOrResume() return end
	if input.KeyCode==Enum.KeyCode.P then resetInput() send("PAUSE") return end
	if state.phase~="ACTIVE" then return end
	if input.UserInputType==Enum.UserInputType.MouseButton1 and not touch then firing=true
	elseif input.KeyCode==Enum.KeyCode.Space then dash()
	elseif input.KeyCode==Enum.KeyCode.R then send("RELOAD") end
end)
UIS.LastInputTypeChanged:Connect(function(input)
	if input==Enum.UserInputType.Touch then touch=true
	elseif input==Enum.UserInputType.MouseMovement or input==Enum.UserInputType.Keyboard then touch=false end
end)
UIS.WindowFocusReleased:Connect(function()
	resetInput()
	if state.phase=="ACTIVE" and state.owner==player.UserId then send("PAUSE") end
end)
GuiService.MenuOpened:Connect(function()
	menuOpen=true resetInput()
	if state.phase=="ACTIVE" and state.owner==player.UserId then send("PAUSE") end
end)
GuiService.MenuClosed:Connect(function() menuOpen=false resetInput() end)
local function setupCharacter(char)
	follow=nil resetInput()
	local hum=char:WaitForChild("Humanoid")
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,false) hum.JumpPower=0 hum.JumpHeight=0 hum.AutoRotate=false
	-- Disable Roblox's default jump affordance, keeping the default left movement stick.
	task.defer(function()
		local touchGui=player.PlayerGui:FindFirstChild("TouchGui")
		if touchGui then local jump=touchGui:FindFirstChild("JumpButton",true) if jump then jump.Visible=false end end
	end)
end
player.CharacterAdded:Connect(setupCharacter)
if player.Character then task.spawn(setupCharacter,player.Character) end
net.Snapshot.OnClientEvent:Connect(function(s)
	lastPacket=os.clock()
	if s.runId~=state.runId then visuals:clear() resetInput() sequence=0 frameTimes={} sampleIndex=0 end
	if s.phase~=state.phase then resetInput() end
	state=s
	visuals:snapshot(s.enemies or {})
	hud:update(s,touch)
	if s.owner and s.owner~=player.UserId then
		hud.panel.Visible=true hud.title.Text="SPECTATOR" hud.summary.Text="P1A is solo. Another player owns this run."
		hud.start.Visible=false resetInput()
	else hud.start.Visible=true end
end)
net.FX.OnClientEvent:Connect(function(runId,kind,data)
	if runId~=state.runId then return end
	if kind=="SHOT" then
		visuals:line(data.origin,data.point,Color3.fromRGB(83,250,239),.13,.10)
		if data.hit then
			visuals:hit(data.hit,data.kill,data.direction)
			visuals:sound(if data.kill then Config.Sounds.Kill else Config.Sounds.Hit,data.point,if data.kill then .45 else .65,if data.kill then 1.8 else 1.3)
			hitUntil=os.clock()+.11 hud.hit.Text=if data.kill then "✦" else "×"
			hud.hit.TextColor3=if data.kill then Color3.fromRGB(255,166,71) else Color3.new(1,1,1)
		end
	elseif kind=="HURT" then hurtUntil=os.clock()+.25 visuals:sound(Config.Sounds.Warning,data.pos,.5,1.2)
	elseif kind=="RELOAD" then local root=character() if root then visuals:sound(Config.Sounds.Reload,root.Position,.45,1.2) end
	elseif kind=="TELEGRAPH" then visuals:sound(Config.Sounds.Warning,data.pos,.4,1.9)
	elseif kind=="DASH" then visuals:flash(data.pos,Color3.fromRGB(83,250,239),2,.2) end
end)
-- Actual packaged audio loading evidence; failed assets remain explicit warnings.
task.spawn(function()
	local sounds={}
	for _,id in pairs(Config.Sounds) do
		local sound=Instance.new("Sound") sound.SoundId=id sound.Parent=game:GetService("SoundService") table.insert(sounds,sound)
	end
	local ok,err=pcall(function()
		ContentProvider:PreloadAsync(sounds,function(id,status)
			if RunService:IsStudio() then print("[SWARMFALL AUDIO]",id,status.Name) end
		end)
	end)
	for _,sound in ipairs(sounds) do sound:Destroy() end
	if not ok then warn("[SWARMFALL AUDIO] preload failed",err) end
end)
RunService:BindToRenderStep("SWARMFALLCamera",Enum.RenderPriority.Camera.Value+1,function(dt)
	local camera=workspace.CurrentCamera
	local root,hum=character()
	local size=camera.ViewportSize
	hud.portrait.Visible=touch and size.Y>size.X
	if root then
		camera.CameraType=Enum.CameraType.Scriptable camera.FieldOfView=Config.Camera.FOV
		local target=root.Position+Vector3.new(0,0,5)
		follow=if follow then follow:Lerp(target,1-math.exp(-dt*18)) else target
		local distance=math.clamp(Config.Camera.Distance+(1.7-size.X/math.max(1,size.Y))*12,35,65)
		local pitch=math.rad(Config.Camera.Pitch)
		camera.CFrame=CFrame.lookAt(follow+Vector3.new(0,math.sin(pitch)*distance,-math.cos(pitch)*distance),follow)
		if not touch then
			local cursor=UIS:GetMouseLocation()
			local ray=camera:ScreenPointToRay(cursor.X,cursor.Y)
			if math.abs(ray.Direction.Y)>.001 then
				local t=(2.4-ray.Origin.Y)/ray.Direction.Y
				local point=ray.Origin+ray.Direction*t
				local direction=Vector3.new(point.X-root.Position.X,0,point.Z-root.Position.Z)
				if direction.Magnitude>.1 then aim=direction.Unit end
			end
			local inset=GuiService:GetGuiInset()
			hud.cross.Position=UDim2.fromOffset(cursor.X-inset.X,cursor.Y-inset.Y)
		else
			local projected=camera:WorldToScreenPoint(root.Position+aim*20)
			local inset=GuiService:GetGuiInset()
			hud.cross.Position=UDim2.fromOffset(projected.X-inset.X,projected.Y-inset.Y)
		end
		hud.hit.Position=hud.cross.Position
		if state.phase=="ACTIVE" then root.CFrame=CFrame.lookAt(root.Position,root.Position+aim) end
		local muzzle=visuals:gun(root,aim)
		if firing and state.phase=="ACTIVE" and not menuOpen and not hud.portrait.Visible and os.clock()-lastPacket<2
			and os.clock()-localShot>=1/Config.Weapon.Rate and (state.ammo or 0)>0 and (state.reload or 0)<=0 then
			localShot=os.clock() send("FIRE",aim)
			visuals:flash(muzzle,Color3.fromRGB(150,255,241),if visuals.low then .65 else 1,.07)
			visuals:line(muzzle,muzzle+aim*8,Color3.fromRGB(150,255,241),.14,.055)
			visuals:sound(Config.Sounds.Fire,muzzle,.25,2.2)
		end
		-- Fade only local view obstruction; never change server collisions.
		for _,p in ipairs(faded) do if p.Parent then p.LocalTransparencyModifier=0 end end
		faded=camera:GetPartsObscuringTarget({root.Position,root.Position+Vector3.yAxis*2},{player.Character,visuals.folder})
		for _,p in ipairs(faded) do p.LocalTransparencyModifier=.78 end
	elseif state.phase=="READY" then
		camera.CameraType=Enum.CameraType.Scriptable camera.CFrame=CFrame.lookAt(Vector3.new(0,65,-65),Vector3.zero)
	end
	visuals:update(dt)
	hud.hit.Visible=os.clock()<hitUntil
	hud.damage.Transparency=if os.clock()<hurtUntil then .05 else 1
	if os.clock()-lastPacket>3 then resetInput() hud.hint.Visible=true hud.hint.Text="CONNECTION DELAY — WAITING FOR SERVER" end
	if RunService:IsStudio() then
		sampleIndex=sampleIndex%600+1 frameTimes[sampleIndex]=dt*1000 debugClock+=dt
		if debugClock>=1 then
			debugClock=0
			local sorted=table.clone(frameTimes) table.sort(sorted)
			local total=0 for _,n in ipairs(sorted) do total+=n end
			local p95=sorted[math.max(1,math.ceil(#sorted*.95))] or 0
			local average=total/math.max(1,#sorted)
			local d=state.debug or {}
			hud.debug.Text=string.format("STUDIO  %.1f avg / %.1f p95 ms\nACTUAL %d / %d   SIM %.2f ms\nREJECT %d  PEAK %d  n=%d",average,p95,state.activeEnemyCount or 0,Config.MaxActiveEnemies,d.simMs or 0,d.rejected or 0,d.peak or 0,#sorted)
			hud.gui:SetAttribute("FrameP95Ms",p95) hud.gui:SetAttribute("FrameAverageMs",average)
			hud.gui:SetAttribute("FrameSampleCount",#sorted)
		end
	end
end)
