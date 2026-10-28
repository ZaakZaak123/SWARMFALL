--!nonstrict
-- DD-106: one look for every touch button of the fight.
--   * a dark disc with the ability's icon;
--   * a ring round it that fills clockwise: the charge (the super) or the way back from cooldown;
--   * while it recovers the icon dims and the seconds left sit in the middle;
--   * ready: the ring is whole and bright, a soft halo breathes behind it (the super also shines and
--     says «ГОТОВ»); the moment it becomes ready it bounces once;
--   * pressed: it squashes; :fire() plays the big «used» burst (the super).
-- The ring is two clipped halves, each a circle stroke with a hard-edged gradient turned by the fill.

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local C, F = Theme.C, Theme.F
local new = Theme.new

local ActionButton = {}
ActionButton.__index = ActionButton

local HALF = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})

-- One half of the ring: a clip frame over the left or right half, holding a full circle stroke.
local function half(parent, right: boolean, color: Color3, z: number)
	local clip = new("Frame", {
		Name = if right then "RingR" else "RingL",
		Position = UDim2.fromScale(if right then 0.5 else 0, 0),
		Size = UDim2.fromScale(0.5, 1),
		ClipsDescendants = true,
		ZIndex = z,
		Parent = parent,
	})
	local ring = new("Frame", {
		Position = UDim2.fromScale(if right then -1 else 0, 0),
		Size = UDim2.fromScale(2, 1),
		Corner = UDim.new(1, 0),
		ZIndex = z,
		Parent = clip,
	})
	local stroke = new("UIStroke", {
		Color = color,
		Thickness = 4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = ring,
	})
	local grad = new("UIGradient", { Transparency = HALF, Parent = stroke })
	return { clip = clip, ring = ring, right = right, stroke = stroke, grad = grad }
end

-- opts: name, icon, color, caption, big (the super), parent
function ActionButton.new(opts)
	local self = setmetatable({}, ActionButton)
	self.color = opts.color
	self.big = opts.big == true
	self.ready = nil
	self.iconName = opts.icon
	local b = new("TextButton", {
		Name = opts.name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(60, 60),
		BackgroundTransparency = 1,
		Text = "",
		Parent = opts.parent,
	})
	self.button = b
	self.scale = new("UIScale", { Parent = b })
	-- the halo behind (ready)
	self.halo = new("ImageLabel", {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.9, 1.9),
		BackgroundTransparency = 1,
		Image = Icons.Tex.glow,
		ImageColor3 = opts.color,
		ImageTransparency = 1,
		ZIndex = 1,
		Parent = b,
	})
	-- the disc
	self.disc = new("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -8, 1, -8),
		BackgroundColor3 = Color3.fromRGB(14, 10, 26):Lerp(opts.color, 0.12),
		BackgroundTransparency = 0.12,
		Corner = UDim.new(1, 0),
		ZIndex = 2,
		Parent = b,
	})
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 140, 175)),
		Parent = self.disc,
	})
	-- the track under the ring and the ring itself
	self.track = new("Frame", {
		Name = "Track",
		Size = UDim2.fromScale(1, 1),
		Corner = UDim.new(1, 0),
		ZIndex = 3,
		Parent = b,
	})
	self.trackStroke = new("UIStroke", { Color = C.ink, Thickness = 4, Transparency = 0.25, Parent = self.track })
	self.right = half(b, true, opts.color, 4)
	self.left = half(b, false, opts.color, 4)
	-- the super's emblem glows from within (brighter when ready)
	if self.big then
		self.emblem = new("ImageLabel", {
			Name = "Emblem",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.9, 0.9),
			BackgroundTransparency = 1,
			Image = Icons.Tex.glow,
			ImageColor3 = opts.color,
			ImageTransparency = 0.7,
			ZIndex = 3,
			Parent = b,
		})
	end
	-- the super's shine: a light band sweeping the disc while it is ready
	if self.big then
		self.shine = new("UIGradient", {
			Rotation = 25,
			Color = ColorSequence.new(Color3.new(1, 1, 1)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.45, 1),
				NumberSequenceKeypoint.new(0.5, 0.55),
				NumberSequenceKeypoint.new(0.55, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		})
		self.gloss = new("Frame", {
			Name = "Gloss",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -8, 1, -8),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			Corner = UDim.new(1, 0),
			ZIndex = 6,
			Parent = b,
		})
		self.shine.Parent = self.gloss
	end
	self:setIcon(opts.icon)
	-- the seconds left / the charge, in the middle
	self.center = Theme.label("", {
		Name = "Count",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.4),
		FontFace = F.numHeavy,
		TextScaled = true,
		TextColor3 = C.text,
		ZIndex = 7,
		Parent = b,
	})
	new("UIStroke", { Color = C.ink, Thickness = 2, Transparency = 0.1, Parent = self.center })
	new("UITextSizeConstraint", { MaxTextSize = if self.big then 22 else 16, MinTextSize = 8, Parent = self.center })
	-- the name under it
	self.caption = Theme.label(opts.caption or "", {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 1),
		Size = UDim2.fromOffset(120, 13),
		FontFace = F.head,
		TextSize = if self.big then 11 else 10,
		TextColor3 = opts.color,
		ZIndex = 7,
		Parent = b,
	})
	new("UIStroke", { Color = C.ink, Thickness = 1.8, Transparency = 0.15, Parent = self.caption })
	-- press feel
	b.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			Theme.tween(self.scale, 0.08, { Scale = 0.9 })
		end
	end)
	b.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			Theme.tween(self.scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)
	self:setProgress(1)
	return self
end

function ActionButton:setIcon(name: string)
	if self.icon and self.iconName == name then
		return
	end
	if self.icon then
		self.icon:Destroy()
	end
	self.iconName = name
	self.dim = nil
	local ic = Icons.new(name, 48, self.color, C.ink, 5)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.Size = UDim2.fromScale(0.52, 0.52)
	ic.ZIndex = 5
	ic.Parent = self.button
	self.icon = ic
end

function ActionButton:setLayout(pos: UDim2, diameter: number)
	self.button.Position = pos
	self.button.Size = UDim2.fromOffset(diameter, diameter)
	local t = math.max(3, math.floor(diameter * (if self.big then 0.07 else 0.06) + 0.5))
	-- a stroke is drawn outward: every ring sits inset by its thickness, so its outer edge is the
	-- button's edge (the half clips would cut a stroke poking out of them)
	self.trackStroke.Thickness = t
	self.track.Position = UDim2.fromOffset(t, t)
	self.track.Size = UDim2.new(1, -2 * t, 1, -2 * t)
	for _, h in { self.right, self.left } do
		h.stroke.Thickness = t
		h.ring.Position = UDim2.new(if h.right then -1 else 0, t, 0, t)
		h.ring.Size = UDim2.new(2, -2 * t, 1, -2 * t)
	end
	self.disc.Size = UDim2.new(1, -2 * t, 1, -2 * t)
	if self.gloss then
		self.gloss.Size = self.disc.Size
	end
	self.ringT = t
end

-- 0..1 clockwise from the top.
function ActionButton:setProgress(p: number)
	p = math.clamp(p, 0, 1)
	if self.progress == p then
		return
	end
	self.progress = p
	local deg = p * 360
	-- the right half covers 0..180, the left 180..360: each gradient's opaque half turns clockwise
	-- into its clip (rotation 0 = opaque on the left, 90 = on top, 180 = on the right, 270 = below)
	self.right.grad.Rotation = math.clamp(deg, 0, 180)
	self.right.stroke.Enabled = deg > 0
	self.left.grad.Rotation = math.clamp(deg, 180, 360)
	self.left.stroke.Enabled = deg > 180
end

-- state: progress (0..1), count (text in the middle while not ready), ready
function ActionButton:set(progress: number, count: string?, ready: boolean)
	self:setProgress(progress)
	self.center.Text = if ready then "" else (count or "")
	-- recovering: the icon goes grey behind the seconds
	local dim = not ready and (count or "") ~= ""
	if dim ~= self.dim then
		self.dim = dim
		self.icon.Visible = not dim -- (the seconds alone read clearer than seconds over an icon)
	end
	if ready ~= self.ready then
		local was = self.ready
		self.ready = ready
		self.disc.BackgroundTransparency = if ready then 0.02 else 0.22
		-- ready, the disc takes on its colour (the super more)
		self.disc.BackgroundColor3 = Color3.fromRGB(14, 10, 26)
			:Lerp(self.color, if ready then (if self.big then 0.28 else 0.18) else 0.08)
		if ready and was == false then
			-- it just came back: one bounce
			self.scale.Scale = 1.18
			Theme.tween(self.scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
end

-- Per frame: the halo breathes and the super's shine sweeps while ready.
function ActionButton:step(now: number)
	if not self.button.Visible then
		return
	end
	if self.emblem then
		self.emblem.ImageTransparency = if self.ready then 0.15 + math.sin(now * 5) * 0.1 else 0.72
	end
	if self.ready then
		local s = math.sin(now * (if self.big then 5 else 3.5))
		self.halo.ImageTransparency = (if self.big then 0.25 else 0.6) - s * 0.15
		self.right.stroke.Transparency = 0.1 - 0.1 * s
		self.left.stroke.Transparency = self.right.stroke.Transparency
		if self.shine then
			self.shine.Offset = Vector2.new(((now * 0.7) % 1.6) - 0.8, 0)
		end
	else
		self.halo.ImageTransparency = 1
		if self.shine then
			self.shine.Offset = Vector2.new(-2, 0)
		end
	end
end

-- The super is used: a white flash on the disc, a ring flying out, a squash and back.
function ActionButton:fire()
	local b = self.button
	local flash = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -8, 1, -8),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.1,
		Corner = UDim.new(1, 0),
		ZIndex = 8,
		Parent = b,
	})
	Theme.tween(flash, 0.35, { BackgroundTransparency = 1 })
	local wave = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Corner = UDim.new(1, 0),
		ZIndex = 1,
		Parent = b,
	})
	local ws = new("UIStroke", { Color = self.color, Thickness = 6, Transparency = 0, Parent = wave })
	Theme.tween(wave, 0.45, { Size = UDim2.fromScale(2.6, 2.6) })
	Theme.tween(ws, 0.45, { Transparency = 1, Thickness = 1 })
	self.scale.Scale = 0.82
	Theme.tween(self.scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Elastic)
	task.delay(0.5, function()
		flash:Destroy()
		wave:Destroy()
	end)
end

return ActionButton
