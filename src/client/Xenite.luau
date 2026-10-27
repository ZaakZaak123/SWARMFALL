--!nonstrict
-- Xenite (DD-095): the currency has one look everywhere. The emblem (tools/icons/xenite.js: three shards
-- out of one cleft, a tall hexagonal spire between two leaning ones, a white four-point heart glowing in
-- the spire) stands in every price, pill and reward; the same three shards are the crystal in the world
-- (the crates the cable brings are stamped with it, a cluster crowns the pile at the terminal, the first
-- xenite glows in its jar).
--
-- Xenite.icon(size, props?) -> ImageLabel           the emblem
-- Xenite.inline(label)                             «◆» in the label's text is drawn as the emblem (single
--                                                  line labels; follows later text changes and fades)
-- Xenite.cluster(parent, cf, scale?) -> Model      the crystal standing on `cf` (about 2.6 × scale tall)
-- Xenite.stamp(part, faces, k?)                    the emblem on a part's faces (k of the face height)

local TextService = game:GetService("TextService")

local Xenite = {}

Xenite.IMAGE = "rbxassetid://129211612455080"
Xenite.COLOR = Color3.fromRGB(255, 86, 198)
local LIGHT = Color3.fromRGB(255, 170, 228)
local HEART = Color3.fromRGB(255, 236, 248)
local GLYPH = "◆"
local GAP = utf8.char(0x2002, 0x2002) -- two en spaces: one em, the emblem sits in it

function Xenite.icon(size: number, props)
	local i = Instance.new("ImageLabel")
	i.Name = "Xenite"
	i.BackgroundTransparency = 1
	i.Image = Xenite.IMAGE
	i.ScaleType = Enum.ScaleType.Fit
	i.Size = UDim2.fromOffset(size, size)
	for k, v in props or {} do
		i[k] = v
	end
	return i
end

-- «◆» in a label's text becomes the emblem: the glyph is swapped for a gap and the image laid over it.
function Xenite.inline(label: TextLabel)
	if label:GetAttribute("XeniteInline") then
		return
	end
	label:SetAttribute("XeniteInline", true)
	local img = Xenite.icon(16, { Name = "XeniteGlyph", AnchorPoint = Vector2.new(0.5, 0.5), Visible = false })
	img.ZIndex = label.ZIndex + 1
	img.Parent = label
	local shown -- the text we put in (the glyph swapped out)
	local prefix -- the text before the glyph
	local token = 0
	local function place()
		token += 1
		local my = token
		if label.Text ~= shown or not prefix then
			img.Visible = false
			return
		end
		task.spawn(function()
			local size = label.TextSize
			local function width(s: string): number
				local p = Instance.new("GetTextBoundsParams")
				p.Text = s
				p.Font = label.FontFace
				p.Size = size
				p.Width = 1e5
				local ok, v = pcall(TextService.GetTextBoundsAsync, TextService, p)
				return if ok then v.X else 0
			end
			local before, gap, full = width(prefix), width(prefix .. GAP), width(shown)
			if my ~= token then
				return
			end
			-- AbsoluteSize and TextBounds are on-screen pixels (after any UIScale), the measures and the
			-- offsets are not: r converts between them
			local tb = label.TextBounds.X
			local r = if tb > 0 and full > 0 then tb / full else 1
			local pad = label:FindFirstChildOfClass("UIPadding")
			local pl = if pad then pad.PaddingLeft.Offset else 0
			local pr = if pad then pad.PaddingRight.Offset else 0
			local w = label.AbsoluteSize.X / r - pl - pr
			local x0 = pl
				+ (
					if label.TextXAlignment == Enum.TextXAlignment.Center
						then (w - full) / 2
						elseif label.TextXAlignment == Enum.TextXAlignment.Right then w - full
						else 0
				)
			local s = math.floor(size * 1.25)
			img.Size = UDim2.fromOffset(s, s)
			img.Position = UDim2.new(0, x0 + (before + gap) / 2, 0.5, 0)
			img.ImageTransparency = label.TextTransparency
			img.ZIndex = label.ZIndex + 1
			img.Visible = true
		end)
	end
	local function refresh()
		local t = label.Text
		local at = t:find(GLYPH, 1, true)
		if at then
			prefix = t:sub(1, at - 1)
			shown = prefix .. GAP .. t:sub(at + #GLYPH):gsub(GLYPH, "")
			label.Text = shown -- fires refresh again: no glyph left, so it only places
			return
		end
		place()
	end
	label:GetPropertyChangedSignal("Text"):Connect(refresh)
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	label:GetPropertyChangedSignal("TextSize"):Connect(place)
	label:GetPropertyChangedSignal("TextXAlignment"):Connect(place)
	label:GetPropertyChangedSignal("TextTransparency"):Connect(function()
		img.ImageTransparency = label.TextTransparency
	end)
	refresh()
end

local function part(parent: Instance, cls: string, size: Vector3, cf: CFrame, color: Color3, mat, alpha: number?)
	local p = Instance.new(cls)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Transparency = alpha or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- One shard on `base` (its foot): a square prism turned 45° (four facets to the eye), a roof tip, and a
-- glowing core inside the glass.
local function shard(m: Model, base: CFrame, w: number, h: number, t: number)
	local GLASS, NEON = Enum.Material.Glass, Enum.Material.Neon
	local body = base * CFrame.Angles(0, math.pi / 4, 0)
	part(m, "Part", Vector3.new(w, h, w), body * CFrame.new(0, h / 2, 0), Xenite.COLOR, GLASS, 0.1)
	part(m, "Part", Vector3.new(w * 0.55, h * 0.92, w * 0.55), body * CFrame.new(0, h / 2, 0), LIGHT, NEON, 0)
	-- the tip: two wedges back to back make a ridge over the prism
	for _, s in { 1, -1 } do
		part(
			m,
			"WedgePart",
			Vector3.new(w, t, w / 2),
			body * CFrame.new(0, h + t / 2, s * w / 4) * CFrame.Angles(0, if s > 0 then 0 else math.pi, 0),
			LIGHT,
			GLASS,
			0.1
		)
	end
end

function Xenite.cluster(parent: Instance, cf: CFrame, scale: number?)
	local k = scale or 1
	local m = Instance.new("Model")
	m.Name = "Xenite"
	-- the spire, then the two leaning shards either side (as on the emblem)
	shard(m, cf, 0.62 * k, 1.9 * k, 0.6 * k)
	shard(m, cf * CFrame.new(-0.45 * k, 0, 0) * CFrame.Angles(0, 0, math.rad(27)), 0.46 * k, 1.05 * k, 0.4 * k)
	shard(m, cf * CFrame.new(0.45 * k, 0, 0.1 * k) * CFrame.Angles(0.1, 0, math.rad(-27)), 0.46 * k, 1.05 * k, 0.4 * k)
	-- the cleft they grow from, and the heart glowing in the spire
	part(
		m,
		"Part",
		Vector3.new(0.5 * k, 1.5 * k, 1.5 * k),
		cf * CFrame.new(0, 0.05 * k, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(86, 74, 80),
		Enum.Material.Slate
	).Shape =
		Enum.PartType.Cylinder
	local heart = part(m, "Part", Vector3.one * 0.3 * k, cf * CFrame.new(0, 1.05 * k, 0), HEART, Enum.Material.Neon)
	heart.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = Xenite.COLOR
	light.Range = 4 + 4 * k
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = heart
	m.PrimaryPart = heart
	m.Parent = parent
	return m
end

-- A square emblem `k` of the face's height, centred on each face (not stretched as a Decal would be).
function Xenite.stamp(p: BasePart, faces: { Enum.NormalId }, k: number?)
	for _, f in faces do
		local g = Instance.new("SurfaceGui")
		g.Name = "XeniteStamp"
		g.Face = f
		g.LightInfluence = 1
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 40
		g.ClipsDescendants = false -- a medallion may stand taller than a thin band
		local i = Xenite.icon(0, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(k or 0.7, k or 0.7),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
		})
		i.Parent = g
		g.Parent = p
	end
end

return Xenite
