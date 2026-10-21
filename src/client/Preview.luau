--!nonstrict
-- ViewportFrame previews of weapon and creature models for menus/HUD, auto-framed and optionally
-- spinning. Only visible viewports are animated.

local Models = require(script.Parent.Models)

local Preview = {}

local active = {} -- vp -> {model, spin, yaw, pitch, base}

local function frameCamera(vp: ViewportFrame, model: Model, yaw: number, pitch: number, zoom: number)
	local cam = vp.CurrentCamera
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local fov = math.rad(cam.FieldOfView)
	local dist = radius / math.sin(fov / 2) * zoom
	local center = cf.Position
	local dir = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
	cam.CFrame = CFrame.lookAt(center + dir * dist, center)
end

-- opts: {spin = bool, yaw = rad, pitch = rad, zoom = number, ambient = Color3}
function Preview.new(parent: Instance, model: Model, opts)
	opts = opts or {}
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = opts.ambient or Color3.fromRGB(150, 160, 180)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.6)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	model.Parent = vp
	local entry = { model = model, spin = opts.spin, yaw = opts.yaw or 2.4, pitch = opts.pitch or 0.35, zoom = opts.zoom or 1.05, t = 0 }
	frameCamera(vp, model, entry.yaw, entry.pitch, entry.zoom)
	active[vp] = entry
	vp.Destroying:Connect(function()
		active[vp] = nil
	end)
	vp.Parent = parent
	return vp
end

function Preview.weapon(parent: Instance, id: string, evolved: boolean, opts)
	return Preview.new(parent, Models.weapon(id, evolved, true), opts)
end

function Preview.creature(parent: Instance, kind: number, opts)
	opts = opts or {}
	opts.yaw = opts.yaw or 3.6
	return Preview.new(parent, Models.creature(kind), opts)
end

-- Replace the model shown in an existing viewport.
function Preview.set(vp: ViewportFrame, model: Model)
	local entry = active[vp]
	if not entry then
		return
	end
	entry.model:Destroy()
	model.Parent = vp
	entry.model = model
	frameCamera(vp, model, entry.yaw, entry.pitch, entry.zoom)
end

local function isShown(inst: Instance): boolean
	local node = inst
	while node do
		if node:IsA("LayerCollector") then
			return (node :: any).Enabled
		elseif node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return false
end

function Preview.update(dt: number)
	for vp, e in active do
		if e.spin and isShown(vp) then
			e.t += dt
			e.yaw += dt * 0.6
			frameCamera(vp, e.model, e.yaw, e.pitch + math.sin(e.t * 0.8) * 0.05, e.zoom)
		end
	end
end

return Preview
