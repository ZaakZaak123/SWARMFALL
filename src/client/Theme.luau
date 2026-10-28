--!nonstrict
-- SPOREFALL visual language (DD-031) + a tiny declarative UI builder.
--
-- Ink panels (deep plum, translucent, rounded) over a cool world. Colour has one job each:
--   lime  — action and growth (primary buttons, XP, "new")
--   pink  — xenite, the currency
--   gold  — rewards, level-up, rare
--   hp    — the hero's health
--   orange/red — the swarm and danger
-- Type: Builder Extended Heavy for display and numbers, Montserrat for reading. Both ship Cyrillic.

local TweenService = game:GetService("TweenService")

local rgb = Color3.fromRGB
local Theme = {}

Theme.C = {
	bg = rgb(12, 8, 22),
	panel = rgb(22, 14, 38),
	panel2 = rgb(38, 26, 62),
	line = rgb(98, 78, 140),
	text = rgb(250, 246, 255),
	dim = rgb(172, 158, 204),
	cyan = rgb(86, 238, 230),
	gold = rgb(255, 204, 70),
	red = rgb(255, 64, 92),
	lime = rgb(198, 255, 66),
	violet = rgb(182, 124, 255),
	orange = rgb(255, 138, 56),
	blue = rgb(120, 176, 255),
	white = rgb(255, 255, 255),
	pink = rgb(255, 86, 198),
	hp = rgb(255, 78, 112),
	ink = rgb(14, 9, 26),
}

-- Codec color codes -> colors (gameplay FX)
Theme.Code = {
	[1] = Theme.C.cyan,
	[2] = Theme.C.orange,
	[3] = Theme.C.violet,
	[4] = Theme.C.red,
	[5] = Theme.C.lime,
	[6] = rgb(255, 250, 230),
	[7] = Theme.C.gold,
	[8] = rgb(150, 210, 255),
	[9] = rgb(200, 245, 255), -- ICE: frost burst, shards, Ледолом
}

local BX = "rbxasset://fonts/families/BuilderExtended.json"
local MS = "rbxasset://fonts/families/Montserrat.json"
Theme.F = {
	display = Font.new(BX, Enum.FontWeight.Heavy),
	title = Font.new(BX, Enum.FontWeight.Heavy),
	head = Font.new(BX, Enum.FontWeight.Bold),
	num = Font.new(BX, Enum.FontWeight.Bold),
	numHeavy = Font.new(BX, Enum.FontWeight.Heavy),
	body = Font.new(MS, Enum.FontWeight.SemiBold),
	bodyBold = Font.new(MS, Enum.FontWeight.Bold),
	bodyHeavy = Font.new(MS, Enum.FontWeight.Heavy),
	mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular),
	tech = Font.new(BX, Enum.FontWeight.Bold),
}

-- new("Frame", {props..., children = {...}}) ; special keys: Corner, Stroke, Pad, Gradient, List, Aspect, MaxText
function Theme.new(class: string, props, children)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
		-- Containers are invisible unless they are given a fill colour.
		if
			(class == "Frame" or class == "TextLabel" or class == "ImageLabel")
			and not (props and props.BackgroundColor3)
		then
			inst.BackgroundTransparency = 1
		end
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.FontFace = Theme.F.body
		inst.TextColor3 = Theme.C.text
		inst.TextSize = 16
		inst.RichText = true
	end
	if inst:IsA("TextButton") or inst:IsA("ImageButton") then
		inst.AutoButtonColor = false
	end
	if inst:IsA("ScreenGui") then
		-- children always draw above their parent; ZIndex only orders siblings
		inst.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end
	local parent = nil
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		elseif k == "Corner" then
			local c = Instance.new("UICorner")
			c.CornerRadius = if typeof(v) == "UDim" then v else UDim.new(0, v)
			c.Parent = inst
		elseif k == "Stroke" then
			local s = Instance.new("UIStroke")
			s.Color = v.Color or Theme.C.line
			s.Thickness = v.Thickness or 1
			s.Transparency = v.Transparency or 0
			s.ApplyStrokeMode = v.Mode or Enum.ApplyStrokeMode.Border
			s.LineJoinMode = Enum.LineJoinMode.Round
			s.Parent = inst
		elseif k == "Pad" then
			local p = Instance.new("UIPadding")
			p.PaddingLeft = UDim.new(0, v)
			p.PaddingRight = UDim.new(0, v)
			p.PaddingTop = UDim.new(0, v)
			p.PaddingBottom = UDim.new(0, v)
			p.Parent = inst
		elseif k == "Gradient" then
			local g = Instance.new("UIGradient")
			for gk, gv in v do
				g[gk] = gv
			end
			g.Parent = inst
		elseif k == "List" then
			local l = Instance.new("UIListLayout")
			l.SortOrder = Enum.SortOrder.LayoutOrder
			for lk, lv in v do
				l[lk] = lv
			end
			l.Parent = inst
		elseif k == "Aspect" then
			local a = Instance.new("UIAspectRatioConstraint")
			a.AspectRatio = v
			a.Parent = inst
		elseif k == "MaxText" then
			local t = Instance.new("UITextSizeConstraint")
			t.MaxTextSize = v
			t.MinTextSize = 8
			t.Parent = inst
		else
			inst[k] = v
		end
	end
	for name, child in children or {} do
		if type(name) == "string" then
			child.Name = name
		end
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Theme.tween(inst: Instance, time: number, props, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

-- Ink panel: deep translucent plum, rounded, hairline light edge, soft top sheen.
function Theme.panel(props, accent: Color3?)
	local radius = props.CornerRadius or 12
	props.CornerRadius = nil
	local f = Theme.new("Frame", props)
	f.BackgroundTransparency = props.BackgroundTransparency or 0.22
	f.BackgroundColor3 = props.BackgroundColor3 or Theme.C.ink
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent or Theme.C.white
	stroke.Transparency = if accent then 0.35 else 0.88
	stroke.Thickness = if accent then 1.5 else 1
	stroke.Parent = f
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = f
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(rgb(255, 255, 255), rgb(200, 190, 220))
	g.Parent = f
	return f
end

function Theme.label(text: string, props)
	props = props or {}
	props.Text = text
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	return Theme.new("TextLabel", props)
end

-- Pill button with hover lift and press squash. kind: "primary" (lime), "ghost" (ink), "danger".
function Theme.button(text: string, props, kind: string?)
	kind = kind or "ghost"
	local fill = if kind == "primary" then Theme.C.lime elseif kind == "danger" then Theme.C.red else Theme.C.ink
	local fg = if kind == "primary" then Theme.C.ink else Theme.C.text
	local b = Theme.new("TextButton", {
		Text = "",
		BackgroundColor3 = fill,
		BackgroundTransparency = if kind == "ghost" then 0.2 else 0,
		Corner = UDim.new(1, 0),
		Stroke = {
			Color = if kind == "ghost" then Theme.C.white else fill,
			Transparency = if kind == "ghost" then 0.8 else 0.4,
			Thickness = if kind == "ghost" then 1 else 2,
		},
	})
	for k, v in props do
		if k ~= "TextSize" and k ~= "Icon" then
			b[k] = v
		end
	end
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local lbl = Theme.label(text, {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.F.display,
		TextSize = props.TextSize or 18,
		TextColor3 = fg,
		ZIndex = b.ZIndex + 1,
		Parent = b,
	})
	if kind == "primary" then
		Theme.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(rgb(255, 255, 255), rgb(214, 226, 200)),
			Parent = b,
		})
	end
	b.MouseEnter:Connect(function()
		Theme.tween(scale, 0.15, { Scale = 1.04 })
	end)
	b.MouseLeave:Connect(function()
		Theme.tween(scale, 0.2, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		Theme.tween(scale, 0.08, { Scale = 0.95 })
	end)
	b.MouseButton1Up:Connect(function()
		Theme.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	return b, lbl
end

-- Keycap chip ("SPACE", "Q") for PC hints.
function Theme.key(text: string, props)
	local k = Theme.new("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		BackgroundColor3 = Theme.C.white,
		BackgroundTransparency = 0.82,
		Corner = 6,
		Stroke = { Color = Theme.C.white, Transparency = 0.6 },
	})
	for kk, v in props or {} do
		k[kk] = v
	end
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = k })
	Theme.label(text, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		FontFace = Theme.F.num,
		TextSize = 12,
		ZIndex = k.ZIndex + 1,
		Parent = k,
	})
	return k
end

function Theme.hex(c: Color3): string
	return c:ToHex()
end

function Theme.fmtTime(t: number): string
	t = math.max(0, t)
	return string.format("%d:%02d", t // 60, math.floor(t % 60))
end

function Theme.commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	if out:sub(1, 1) == " " then
		out = out:sub(2)
	end
	return out
end

-- A phone in landscape (DD-085): a touch screen under ~560 points high. Screens built for 720+ get a
-- phone layout (bigger text, less beside the essentials) instead of being shrunk until unreadable.
-- Studio: the workspace attribute DevTouch counts as touch, so a Studio window sized like a phone shows
-- the phone layouts (DD-102).
local devTouch = game:GetService("RunService"):IsStudio() and workspace:GetAttribute("DevTouch") == true
function Theme.phone(): boolean
	local cam = workspace.CurrentCamera
	local touch = devTouch or game:GetService("UserInputService").TouchEnabled
	return touch and cam ~= nil and cam.ViewportSize.Y < 560
end

-- DD-109: the free part of Roblox's top bar — right of its own buttons (the logo, the menu, chat), in
-- screen points: left x, right x, height. A phone's screen is short; this strip is ~15% of it and was
-- empty. Height 0 when there is no top bar (then nothing goes up there).
function Theme.topStrip(): (number, number, number)
	local ok, r = pcall(function()
		return game:GetService("GuiService").TopbarInset
	end)
	if ok and r and r.Max.Y >= 36 and r.Max.X > r.Min.X then
		return r.Min.X, r.Max.X, r.Max.Y
	end
	local cam = workspace.CurrentCamera
	return 0, if cam then cam.ViewportSize.X else 0, 0
end

return Theme
