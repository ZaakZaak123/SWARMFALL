--!nonstrict
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Hud={}
local bg=Color3.fromRGB(13,25,37)
local cyan=Color3.fromRGB(84,238,225)
function Hud.new()
	local self=setmetatable({}, {__index=Hud})
	local gui=Instance.new("ScreenGui") gui.Name="SWARMFALL" gui.ResetOnSpawn=false
	gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
	gui.Parent=Players.LocalPlayer:WaitForChild("PlayerGui") self.gui=gui
	local function box(class,name,pos,size,text,parent)
		local v=Instance.new(class) v.Name=name v.Position=pos v.Size=size v.BackgroundColor3=bg
		v.BackgroundTransparency=0.12 v.BorderSizePixel=0 v.Parent=parent or gui
		if v:IsA("TextLabel") or v:IsA("TextButton") then
			v.Text=text or "" v.TextColor3=Color3.fromRGB(230,246,249) v.Font=Enum.Font.GothamBold
			v.TextScaled=true
			local limit=Instance.new("UITextSizeConstraint") limit.MinTextSize=12 limit.MaxTextSize=24 limit.Parent=v
		end
		local corner=Instance.new("UICorner") corner.CornerRadius=UDim.new(0,10) corner.Parent=v
		return v
	end
	self.health=box("TextLabel","Health",UDim2.fromScale(.02,.025),UDim2.fromScale(.22,.065),"HP 100")
	self.phase=box("TextLabel","Phase",UDim2.fromScale(.34,.025),UDim2.fromScale(.32,.065),"REACTOR YARD")
	self.pause=box("TextButton","Pause",UDim2.fromScale(.80,.025),UDim2.fromScale(.085,.075),"II")
	self.quality=box("TextButton","Quality",UDim2.fromScale(.89,.025),UDim2.fromScale(.09,.075),"FX HIGH")
	self.ammo=box("TextButton","Reload",UDim2.fromScale(.38,.89),UDim2.fromScale(.24,.075),"ARC 36 / 36")
	self.hint=box("TextLabel","Hint",UDim2.fromScale(.25,.105),UDim2.fromScale(.5,.06),"")
	self.hint.BackgroundTransparency=.35
	self.aim=box("TextButton","AimStick",UDim2.fromScale(.84,.73),UDim2.fromScale(.23,.29),"AIM\nHOLD TO FIRE")
	self.aim.AnchorPoint=Vector2.new(.5,.5)
	local aspect=Instance.new("UIAspectRatioConstraint") aspect.AspectRatio=1 aspect.Parent=self.aim
	local size=Instance.new("UISizeConstraint") size.MinSize=Vector2.new(112,112) size.MaxSize=Vector2.new(190,190) size.Parent=self.aim
	self.knob=box("Frame","Knob",UDim2.fromScale(.5,.5),UDim2.fromScale(.22,.22),nil,self.aim)
	self.knob.AnchorPoint=Vector2.new(.5,.5) self.knob.BackgroundColor3=cyan self.knob.BackgroundTransparency=.25
	self.dash=box("TextButton","Dash",UDim2.fromScale(.69,.77),UDim2.fromScale(.1,.12),"DASH")
	local dashSize=Instance.new("UISizeConstraint") dashSize.MinSize=Vector2.new(56,56) dashSize.Parent=self.dash
	self.cross=box("TextLabel","Reticle",UDim2.fromOffset(0,0),UDim2.fromOffset(26,26),"+")
	self.cross.AnchorPoint=Vector2.new(.5,.5) self.cross.BackgroundTransparency=1 self.cross.TextColor3=cyan
	self.hit=box("TextLabel","ConfirmedHit",UDim2.fromScale(.5,.45),UDim2.fromOffset(50,40),"×")
	self.hit.AnchorPoint=Vector2.new(.5,.5) self.hit.BackgroundTransparency=1 self.hit.Visible=false
	self.damage=Instance.new("UIStroke") self.damage.Color=Color3.fromRGB(255,75,64) self.damage.Thickness=4
	self.damage.Transparency=1 self.damage.Parent=self.health
	self.panel=box("Frame","Panel",UDim2.fromScale(.5,.48),UDim2.fromScale(.60,.49)) self.panel.AnchorPoint=Vector2.new(.5,.5)
	self.title=box("TextLabel","Title",UDim2.fromScale(.05,.08),UDim2.fromScale(.9,.20),"SWARMFALL",self.panel)
	self.title.BackgroundTransparency=1 self.title.TextColor3=cyan
	self.summary=box("TextLabel","Summary",UDim2.fromScale(.07,.33),UDim2.fromScale(.86,.29),"REACTOR YARD / 75 SECONDS\nMove. Aim. Hold fire. Survive.",self.panel)
	self.summary.BackgroundTransparency=1
	self.start=box("TextButton","Start",UDim2.fromScale(.20,.72),UDim2.fromScale(.60,.19),"DEPLOY",self.panel)
	self.start.BackgroundColor3=Color3.fromRGB(19,101,111)
	self.portrait=box("TextLabel","RotateDevice",UDim2.fromScale(.15,.3),UDim2.fromScale(.7,.3),"ROTATE YOUR DEVICE\nLandscape recommended")
	self.portrait.ZIndex=20 self.portrait.Visible=false
	if RunService:IsStudio() then
		self.debug=box("TextLabel","StudioMetrics",UDim2.fromScale(.02,.19),UDim2.fromScale(.31,.16),"STUDIO / collecting frames")
		self.debug.TextXAlignment=Enum.TextXAlignment.Left self.debug.Font=Enum.Font.Code
	end
	return self
end
function Hud:update(s,touch)
	local phase=s.phase
	self.aim.Visible=touch and phase=="ACTIVE" self.dash.Visible=phase=="ACTIVE"
	self.pause.Visible=phase=="ACTIVE" or phase=="PAUSED"
	self.ammo.Visible=phase=="ACTIVE" or phase=="COUNTDOWN"
	self.health.Text=string.format("HP %03d   /   100",s.hp or 100)
	self.health.TextColor3=if (s.hp or 100)<30 then Color3.fromRGB(255,122,92) else Color3.fromRGB(230,246,249)
	self.phase.Text=string.format("%s  %02d:%02d   •   %d",phase,math.floor((s.remaining or 75)/60),math.floor((s.remaining or 75)%60),s.kills or 0)
	self.ammo.Text=if (s.reload or 0)>0 then string.format("RELOADING  %.1fs",s.reload) else string.format("ARC  %02d / 36   [R]",s.ammo or 36)
	self.dash.Text=if (s.dash or 0)>0 then string.format("%.1fs",s.dash) else (if touch then "DASH" else "SPACE\nDASH")
	self.panel.Visible=phase=="READY" or phase=="RESULTS" or phase=="PAUSED" or phase=="LOADING"
	if phase=="RESULTS" then
		self.title.Text=s.result or "RUN COMPLETE" self.summary.Text=string.format("%d ELIMINATED  /  %.1f SECONDS\nTry another route. Keep moving.",s.kills or 0,s.elapsed or 0)
		self.start.Text="REDEPLOY"
	elseif phase=="PAUSED" then self.title.Text="PAUSED" self.summary.Text="Simulation stopped\nPress Resume to continue" self.start.Text="RESUME"
	elseif phase=="LOADING" then self.title.Text="DEPLOYING" self.summary.Text="Loading your character…" self.start.Text="PLEASE WAIT"
	else self.title.Text="SWARMFALL" self.summary.Text=if touch then "75 SECONDS / REACTOR YARD\nLeft stick: move • Right stick: aim + fire" else "75 SECONDS / REACTOR YARD\nWASD: move • Mouse + LMB: fire • Space: dash" self.start.Text="DEPLOY" end
	self.hint.Visible=phase=="ACTIVE" or phase=="COUNTDOWN"
	if phase=="COUNTDOWN" then self.hint.Text="GET READY  "..math.ceil(s.countdown or 0)
	elseif (s.safe or 0)>0 then self.hint.Text="SPAWN SHIELD  "..math.ceil(s.safe).."s • SIGNALS: NORTH + EAST"
	elseif (s.elapsed or 0)<25 then self.hint.Text=if touch then "DRAG RIGHT STICK TO FIRE" else "HOLD LMB TO FIRE • KEEP MOVING"
	elseif (s.elapsed or 0)<50 then self.hint.Text="SOUTH BREACH • WATCH FOR LUNGE LINES"
	else self.hint.Text="FINAL SURGE • EAST / SOUTH / WEST" end
end
return Hud
