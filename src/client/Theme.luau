--!nonstrict
-- Visual language + tiny declarative UI builder.

local TweenService = game:GetService("TweenService")

local rgb = Color3.fromRGB
local Theme = {}

Theme.C = {
	bg = rgb(7, 11, 18),
	panel = rgb(11, 18, 29),
	panel2 = rgb(17, 27, 42),
	line = rgb(48, 74, 96),
	text = rgb(230, 246, 250),
	dim = rgb(126, 149, 166),
	cyan = rgb(84, 238, 255),
	gold = rgb(255, 200, 60),
	red = rgb(255, 70, 80),
	lime = rgb(170, 255, 80),
	violet = rgb(180, 110, 255),
	orange = rgb(255, 140, 50),
	blue = rgb(120, 170, 255),
	white = rgb(255, 255, 255),
}

-- Codec color codes -> colors
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

Theme.F = {
	-- All faces below ship Cyrillic glyphs (Michroma/Sarpanch/BuilderSans do not).
	title = Font.new("rbxasset://fonts/families/Zekton.json", Enum.FontWeight.Regular),
	head = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
	num = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
	numHeavy = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy),
	body = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium),
	bodyBold = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold),
	mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular),
	tech = Font.new("rbxasset://fonts/families/Zekton.json", Enum.FontWeight.Regular),
}

-- new("Frame", {props..., children = {...}}) ; special keys: Corner, Stroke, Pad, Gradient, Children
function Theme.new(class: string, props, children)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
		if class == "Frame" or class == "TextLabel" or class == "ImageLabel" then
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

-- Angular sci-fi panel: dark fill, faint stroke and a bright corner accent.
function Theme.panel(props, accent: Color3?)
	local f = Theme.new("Frame", props)
	f.BackgroundTransparency = props.BackgroundTransparency or 0.18
	f.BackgroundColor3 = props.BackgroundColor3 or Theme.C.panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent or Theme.C.line
	stroke.Transparency = 0.45
	stroke.Parent = f
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = f
	local tick = Theme.new("Frame", {
		Name = "Accent",
		BackgroundTransparency = 0,
		BackgroundColor3 = accent or Theme.C.cyan,
		Size = UDim2.new(0, 18, 0, 2),
		Position = UDim2.new(0, 0, 0, 0),
		ZIndex = (props.ZIndex or 1) + 1,
		Parent = f,
	})
	tick.Name = "Accent"
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

function Theme.hex(c: Color3): string
	return c:ToHex()
end

function Theme.fmtTime(t: number): string
	t = math.max(0, t)
	return string.format("%d:%02d", t // 60, math.floor(t % 60))
end

function Theme.commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

return Theme
