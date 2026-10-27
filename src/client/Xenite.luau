--!nonstrict
-- Xenite (DD-096): one fractured mineral in the HUD and world.
-- Authored in Blender: 140 triangles per shard, 520 per ore cluster. Each
-- template has two MeshParts; only the narrow fracture is emissive.
-- icon / inline / stamp keep DD-095's UI integration; shard is the keepsake,
-- cluster is the raw ore at the terminal. The model pivot is its ground contact.

local TextService = game:GetService("TextService")
local templates = game:GetService("ReplicatedStorage"):WaitForChild("XeniteAssets")

local Xenite = {}

Xenite.IMAGE = "rbxassetid://113891813640404"
Xenite.COLOR = Color3.fromRGB(235, 54, 158)
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

-- Clone baked assets; no EditableMesh, import, or geometry generation at runtime.
local function mineral(name: string, parent: Instance, cf: CFrame, scale: number?)
	local k = scale or 1
	assert(k > 0, "Xenite scale must be positive")
	local m = templates:WaitForChild(name):Clone()
	m.Name = "Xenite"
	m:SetAttribute("XeniteForm", name)
	m:ScaleTo(k)
	m:PivotTo(cf)
	local light = m:FindFirstChildWhichIsA("PointLight", true)
	if light then
		light.Range = math.clamp(2 + 2 * k, 2, 5)
	end
	m.Parent = parent
	return m
end

function Xenite.shard(parent: Instance, cf: CFrame, scale: number?)
	return mineral("Shard", parent, cf, scale)
end

function Xenite.cluster(parent: Instance, cf: CFrame, scale: number?)
	return mineral("Cluster", parent, cf, scale)
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
