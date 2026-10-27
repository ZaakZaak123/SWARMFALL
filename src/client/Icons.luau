--!nonstrict
-- Icon set. Icons.new(name, sizePx, color, cutoutColor?) -> Frame. Recolor with Icons.recolor(frame, color).
-- Main path: a white, shaded, outlined atlas (tools/icons, 8×6 cells of 128 px) tinted with ImageColor3.
-- Names missing from the atlas fall back to the primitive vector specs below.
-- Primitive spec: {kind, ...} where kind is
--   L x1 y1 x2 y2 thick      line (rounded caps)
--   C x y r                   filled circle
--   R x y r thick             ring
--   B x y w h rot?            box (center-based)
--   D x y size                diamond (45° box)
--   O x y w h thick           outlined box
--   P x y w h                 pill (fully rounded box)
-- Kinds suffixed with "2" draw in the cutout color (holes, details).

local ContentProvider = game:GetService("ContentProvider")

local Icons = {}

local ATLAS = "rbxassetid://106607045724159"
local CELL, COLS = 128, 8
-- Same order as `node tools/icons/build.js` prints.
local ORDER = { "chain", "ricochet", "pierce", "fire", "burst", "drop", "snow", "fan", "chevrons", "crosshair", "dashbolt", "shield", "plus", "battery", "dash", "sun", "evolve", "reload", "heart", "skull", "timer", "level", "core", "hammer", "reactor", "hive", "crown", "elite", "coil", "gear", "threat", "pin", "reroll", "banish", "lock", "magnet", "eye", "xp", "star", "check", "swords", "boom", "play", "topdown", "person", "users" }
local CELLS = {}
for i, name in ORDER do
	CELLS[name] = Vector2.new((i - 1) % COLS * CELL, (i - 1) // COLS * CELL)
end

-- White textures for UI art (tinted by ImageColor3).
Icons.Tex = {
	glow = "rbxassetid://72977969815661", -- soft radial glow
	hex = "rbxassetid://98100621436240", -- hex-cell pattern fading downwards
}

task.defer(function()
	pcall(ContentProvider.PreloadAsync, ContentProvider, { ATLAS, Icons.Tex.glow, Icons.Tex.hex })
end)

local SPECS = {}

local function rays(cx, cy, r1, r2, n, thick, offset)
	local out = {}
	for i = 0, n - 1 do
		local a = (offset or 0) + i / n * math.pi * 2
		table.insert(out, { "L", cx + math.cos(a) * r1, cy + math.sin(a) * r1, cx + math.cos(a) * r2, cy + math.sin(a) * r2, thick })
	end
	return out
end

local function concat(...)
	local out = {}
	for _, list in { ... } do
		for _, v in list do
			table.insert(out, v)
		end
	end
	return out
end

SPECS.note = { { "C", 36, 74, 15 }, { "L", 48, 76, 48, 14, 9 }, { "L", 48, 16, 78, 32, 9 } }
SPECS.chain = { { "L", 60, 6, 34, 50, 11 }, { "L", 32, 50, 66, 50, 11 }, { "L", 66, 50, 40, 94, 11 } }
SPECS.ricochet = { { "L", 12, 84, 46, 30, 8 }, { "L", 46, 30, 86, 70, 8 }, { "C", 46, 30, 8 }, { "L", 88, 72, 70, 72, 8 }, { "L", 88, 72, 84, 54, 8 } }
SPECS.pierce = { { "R", 34, 50, 13, 6 }, { "R", 62, 50, 13, 6 }, { "L", 6, 50, 88, 50, 8 }, { "L", 92, 50, 76, 36, 8 }, { "L", 92, 50, 76, 64, 8 } }
SPECS.fire = { { "C", 50, 64, 27 }, { "D", 50, 42, 32 }, { "D", 64, 30, 14 }, { "C2", 50, 70, 13 }, { "C", 50, 76, 7 } }
SPECS.burst = concat({ { "C", 50, 50, 16 } }, rays(50, 50, 24, 44, 8, 8))
SPECS.drop = { { "D", 50, 42, 34 }, { "C", 50, 62, 25 }, { "C2", 42, 60, 6 }, { "C", 82, 20, 6 }, { "C", 20, 26, 4 } }
SPECS.snow = concat(rays(50, 50, -40, 40, 3, 8, math.pi / 2), { { "C", 50, 50, 9 }, { "C2", 50, 50, 4 } })
SPECS.fan = { { "L", 50, 88, 16, 22, 8 }, { "L", 50, 88, 50, 12, 8 }, { "L", 50, 88, 84, 22, 8 }, { "C", 16, 22, 8 }, { "C", 50, 12, 8 }, { "C", 84, 22, 8 } }
SPECS.chevrons = { { "L", 14, 18, 40, 50, 11 }, { "L", 40, 50, 14, 82, 11 }, { "L", 46, 18, 72, 50, 11 }, { "L", 72, 50, 46, 82, 11 }, { "L", 78, 30, 92, 50, 8 }, { "L", 92, 50, 78, 70, 8 } }
SPECS.crosshair = { { "R", 50, 50, 28, 7 }, { "L", 50, 6, 50, 30, 7 }, { "L", 50, 70, 50, 94, 7 }, { "L", 6, 50, 30, 50, 7 }, { "L", 70, 50, 94, 50, 7 }, { "C", 50, 50, 7 } }
SPECS.dashbolt = { { "L", 6, 30, 38, 30, 7 }, { "L", 2, 50, 34, 50, 7 }, { "L", 6, 70, 38, 70, 7 }, { "L", 72, 10, 52, 50, 10 }, { "L", 50, 50, 76, 50, 10 }, { "L", 76, 50, 56, 90, 10 } }
SPECS.shield = { { "B", 50, 30, 64, 32 }, { "D", 50, 50, 64 }, { "D2", 50, 46, 30 }, { "D", 50, 46, 14 } }
SPECS.plus = { { "B", 50, 50, 26, 76 }, { "B", 50, 50, 76, 26 } }
SPECS.battery = { { "O", 44, 50, 66, 42, 7 }, { "B", 83, 50, 8, 18 }, { "L", 50, 34, 38, 52, 7 }, { "L", 38, 52, 54, 50, 7 }, { "L", 54, 50, 44, 66, 7 } }
SPECS.dash = { { "L", 4, 50, 46, 50, 8 }, { "L", 36, 20, 64, 50, 11 }, { "L", 64, 50, 36, 80, 11 }, { "L", 60, 20, 88, 50, 11 }, { "L", 88, 50, 60, 80, 11 } }
SPECS.sun = concat({ { "C", 50, 50, 19 }, { "C2", 50, 50, 9 } }, rays(50, 50, 28, 45, 8, 8, math.pi / 8))
SPECS.evolve = { { "L", 18, 62, 50, 30, 11 }, { "L", 50, 30, 82, 62, 11 }, { "L", 18, 88, 50, 56, 11 }, { "L", 50, 56, 82, 88, 11 }, { "D", 50, 10, 14 } }
SPECS.reload = { { "R", 50, 52, 30, 9 }, { "C2", 76, 34, 10 }, { "L", 62, 16, 84, 18, 9 }, { "L", 84, 18, 80, 40, 9 } }
SPECS.heart = { { "C", 33, 40, 21 }, { "C", 67, 40, 21 }, { "D", 50, 58, 42 } }
SPECS.skull = { { "C", 50, 42, 33 }, { "B", 50, 74, 38, 22 }, { "C2", 37, 44, 10 }, { "C2", 63, 44, 10 }, { "B2", 42, 80, 4, 14 }, { "B2", 50, 80, 4, 14 }, { "B2", 58, 80, 4, 14 } }
SPECS.timer = { { "R", 50, 56, 34, 8 }, { "L", 50, 56, 50, 34, 7 }, { "L", 50, 56, 66, 64, 7 }, { "B", 50, 12, 18, 8 } }
SPECS.level = { { "L", 16, 52, 50, 20, 11 }, { "L", 50, 20, 84, 52, 11 }, { "L", 16, 82, 50, 50, 11 }, { "L", 50, 50, 84, 82, 11 } }
SPECS.core = { { "D", 50, 50, 62 }, { "D2", 50, 50, 36 }, { "C", 50, 50, 11 } }
SPECS.hammer = { { "B", 50, 30, 64, 30 }, { "B2", 50, 30, 46, 12 }, { "L", 50, 44, 50, 88, 12 }, { "L", 22, 92, 78, 92, 7 } }
SPECS.reactor = concat({ { "R", 50, 50, 30, 8 }, { "C", 50, 50, 14 }, { "C2", 50, 50, 6 } }, rays(50, 50, 36, 46, 6, 7, math.pi / 6))
SPECS.hive = { { "C", 50, 64, 26 }, { "C", 28, 40, 15 }, { "C", 72, 38, 17 }, { "C", 50, 22, 13 }, { "C2", 46, 62, 6 }, { "C2", 70, 38, 5 }, { "C2", 28, 42, 4 } }
SPECS.crown = { { "B", 50, 74, 74, 16 }, { "D", 18, 50, 24 }, { "D", 50, 40, 28 }, { "D", 82, 50, 24 }, { "B", 50, 62, 70, 14 }, { "C2", 50, 74, 5 }, { "C2", 30, 74, 4 }, { "C2", 70, 74, 4 } }
SPECS.elite = { { "B", 50, 50, 50, 50 }, { "D", 50, 50, 71 }, { "C2", 50, 50, 13 } }
SPECS.coil = { { "R", 50, 50, 36, 7 }, { "L", 58, 18, 40, 52, 10 }, { "L", 38, 52, 62, 50, 10 }, { "L", 62, 48, 44, 84, 10 } }
SPECS.gear = concat({ { "C", 50, 50, 30 } }, (function()
	local out = {}
	for i = 0, 7 do
		local a = i / 8 * 360
		local r = math.rad(a)
		table.insert(out, { "B", 50 + math.cos(r) * 34, 50 + math.sin(r) * 34, 16, 14, a })
	end
	return out
end)(), { { "C2", 50, 50, 12 } })
SPECS.threat = { { "D", 50, 52, 72 }, { "B2", 50, 42, 9, 28 }, { "C2", 50, 66, 6 } }
SPECS.pin = { { "C", 50, 38, 27 }, { "D", 50, 62, 32 }, { "C2", 50, 38, 11 } }
SPECS.reroll = { { "R", 50, 50, 30, 9 }, { "C2", 80, 50, 12 }, { "C2", 20, 50, 12 }, { "L", 70, 36, 82, 52, 8 }, { "L", 82, 52, 94, 38, 8 }, { "L", 30, 64, 18, 48, 8 }, { "L", 18, 48, 6, 62, 8 } }
SPECS.banish = { { "R", 50, 50, 34, 9 }, { "L", 26, 26, 74, 74, 9 } }
SPECS.lock = { { "R", 50, 36, 19, 9 }, { "B", 50, 66, 58, 42 }, { "C2", 50, 62, 7 }, { "B2", 50, 72, 5, 13 } }
SPECS.magnet = { { "R", 50, 50, 26, 14 }, { "B2", 50, 30, 74, 42 }, { "B", 26, 34, 14, 32 }, { "B", 74, 34, 14, 32 }, { "B2", 26, 26, 16, 4 }, { "B2", 74, 26, 16, 4 } }
SPECS.eye = { { "P", 50, 50, 86, 46 }, { "C2", 50, 50, 19 }, { "C", 50, 50, 10 }, { "C2", 46, 46, 3 } }
SPECS.xp = { { "D", 50, 50, 56 }, { "D2", 50, 50, 26 } }
SPECS.star = { { "B", 50, 50, 50, 50 }, { "D", 50, 50, 71 } }
SPECS.check = { { "L", 16, 52, 40, 76, 11 }, { "L", 40, 76, 86, 26, 11 } }
SPECS.swords = { { "L", 16, 16, 80, 80, 9 }, { "L", 84, 16, 20, 80, 9 }, { "L", 64, 82, 82, 64, 9 }, { "L", 18, 64, 36, 82, 9 } }
SPECS.boom = concat(rays(50, 50, 14, 46, 10, 9), { { "C", 50, 50, 18 } })
SPECS.play = { { "L", 30, 18, 30, 82, 12 }, { "L", 30, 18, 80, 50, 12 }, { "L", 80, 50, 30, 82, 12 }, { "B", 42, 50, 22, 34 }, { "B", 56, 50, 14, 18 } }
SPECS.topdown = { { "O", 50, 62, 74, 46, 6 }, { "L", 50, 42, 50, 82, 5 }, { "L", 16, 62, 84, 62, 5 }, { "L", 50, 4, 50, 26, 8 }, { "L", 38, 16, 50, 28, 8 }, { "L", 62, 16, 50, 28, 8 } }
SPECS.person = { { "C", 50, 26, 16 }, { "P", 50, 72, 50, 46 }, { "B2", 50, 92, 60, 10 }, { "L", 82, 22, 92, 40, 6 }, { "L", 92, 40, 82, 58, 6 } }
SPECS.users = { { "C", 34, 34, 14 }, { "C", 68, 34, 14 }, { "B", 34, 72, 34, 26 }, { "B", 68, 72, 34, 26 } }

-- Builders ------------------------------------------------------------------------------------------
local function frame(parent, color, z)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function round(f, scale)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = f
end

function Icons.new(name: string, size: number, color: Color3, cutout: Color3?, zIndex: number?)
	local holder = Instance.new("Frame")
	holder.Name = "Icon_" .. name
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder:SetAttribute("Icon", name)
	local z = zIndex or 1
	local cell = CELLS[name]
	if cell then
		-- the atlas cell has a margin for the outline and shadow: draw it a bit larger than the box
		local img = Instance.new("ImageLabel")
		img.Name = "Glyph"
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(1.28, 1.28)
		img.Image = ATLAS
		img.ImageRectOffset = cell
		img.ImageRectSize = Vector2.new(CELL, CELL)
		img.ImageColor3 = color
		img.ZIndex = z
		img.Parent = holder
		return holder
	end
	local spec = SPECS[name] or SPECS.xp
	local cut = cutout or Color3.fromRGB(11, 18, 29)
	local px = size / 100
	for _, s in spec do
		local kind = s[1]
		local alt = kind:sub(-1) == "2"
		if alt then
			kind = kind:sub(1, -2)
		end
		local c = if alt then cut else color
		local f
		if kind == "L" then
			local x1, y1, x2, y2, t = s[2], s[3], s[4], s[5], s[6]
			local dx, dy = x2 - x1, y2 - y1
			local len = math.sqrt(dx * dx + dy * dy)
			f = frame(holder, c, z)
			f.Position = UDim2.fromScale((x1 + x2) / 200, (y1 + y2) / 200)
			f.Size = UDim2.fromScale((len + t) / 100, t / 100)
			f.Rotation = math.deg(math.atan2(dy, dx))
			round(f, 0.5)
		elseif kind == "C" then
			f = frame(holder, c, z)
			f.Position = UDim2.fromScale(s[2] / 100, s[3] / 100)
			f.Size = UDim2.fromScale(s[4] / 50, s[4] / 50)
			round(f, 0.5)
		elseif kind == "R" then
			f = frame(holder, c, z)
			f.BackgroundTransparency = 1
			f.Position = UDim2.fromScale(s[2] / 100, s[3] / 100)
			f.Size = UDim2.fromScale((s[4] * 2 - s[5]) / 100, (s[4] * 2 - s[5]) / 100)
			round(f, 0.5)
			local st = Instance.new("UIStroke")
			st.Color = c
			st.Thickness = math.max(1, s[5] * px)
			st.Parent = f
		elseif kind == "B" then
			f = frame(holder, c, z)
			f.Position = UDim2.fromScale(s[2] / 100, s[3] / 100)
			f.Size = UDim2.fromScale(s[4] / 100, s[5] / 100)
			f.Rotation = s[6] or 0
			round(f, 0.12)
		elseif kind == "D" then
			f = frame(holder, c, z)
			f.Position = UDim2.fromScale(s[2] / 100, s[3] / 100)
			local side = s[4] / math.sqrt(2)
			f.Size = UDim2.fromScale(side / 100, side / 100)
			f.Rotation = 45
			round(f, 0.12)
		elseif kind == "P" then
			f = frame(holder, c, z)
			f.Position = UDim2.fromScale(s[2] / 100, s[3] / 100)
			f.Size = UDim2.fromScale(s[4] / 100, s[5] / 100)
			round(f, 0.5)
		elseif kind == "O" then
			f = frame(holder, c, z)
			f.BackgroundTransparency = 1
			f.Position = UDim2.fromScale(s[2] / 100, s[3] / 100)
			f.Size = UDim2.fromScale((s[4] - s[6]) / 100, (s[5] - s[6]) / 100)
			round(f, 0.15)
			local st = Instance.new("UIStroke")
			st.Color = c
			st.Thickness = math.max(1, s[6] * px)
			st.Parent = f
		end
		if f then
			f:SetAttribute("Cut", alt)
		end
	end
	return holder
end

function Icons.recolor(holder: Frame, color: Color3, cutout: Color3?)
	for _, f in holder:GetChildren() do
		if f:IsA("ImageLabel") then
			f.ImageColor3 = color
		elseif f:IsA("Frame") then
			local isCut = f:GetAttribute("Cut")
			local c = if isCut then (cutout or f.BackgroundColor3) else color
			f.BackgroundColor3 = c
			local st = f:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = c
			end
		end
	end
end

-- Replace an existing icon in-place (keeps parent, position, anchor).
function Icons.swap(old: Frame, name: string, color: Color3, cutout: Color3?)
	if old:GetAttribute("Icon") == name then
		Icons.recolor(old, color, cutout)
		return old
	end
	local size = old.AbsoluteSize.X > 0 and old.Size.X.Offset or 32
	local new = Icons.new(name, size, color, cutout, (old:FindFirstChildWhichIsA("GuiObject") or old).ZIndex)
	new.AnchorPoint = old.AnchorPoint
	new.Position = old.Position
	new.Size = old.Size
	new.LayoutOrder = old.LayoutOrder
	new.Name = old.Name
	new.Parent = old.Parent
	old:Destroy()
	return new
end

-- Icon medallion: dark disc, colour ring, inner glow, icon. Shared by cards, tiles and results.
function Icons.disc(name: string, size: number, color: Color3, zIndex: number?)
	local z = zIndex or 1
	local d = Instance.new("Frame")
	d.Name = "Disc_" .. name
	d.Size = UDim2.fromOffset(size, size)
	d.BackgroundColor3 = Color3.fromRGB(11, 8, 20):Lerp(color, 0.12)
	d.BorderSizePixel = 0
	d.ZIndex = z
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = d
	local ring = Instance.new("UIStroke")
	ring.Color = color
	ring.Thickness = math.max(1.5, size / 30)
	ring.Transparency = 0.25
	ring.Parent = d
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1, 1)
	glow.Image = Icons.Tex.glow
	glow.ImageColor3 = color
	glow.ImageTransparency = 0.35
	glow.ZIndex = z
	glow.Parent = d
	local ic = Icons.new(name, math.floor(size * 0.6), color, nil, z + 1)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.ZIndex = z + 1
	ic.Parent = d
	return d
end

Icons.Specs = SPECS

return Icons
