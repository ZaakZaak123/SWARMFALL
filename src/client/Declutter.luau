--!nonstrict
-- World labels on a phone (DD-098). Owner's phone screenshots: the plot signs, station boards, the
-- grove's tree and the campfire all hang over the HUD and each other, unreadable. Billboards are sized in
-- screen pixels, so a small screen gets them as big as a monitor does.
-- On a touch screen, five times a second:
--   * every label billboard (AlwaysOnTop, at least 140 px wide) shrinks with the screen (UIScale and
--     its own Size, so it stays centred on its anchor);
--   * the labels are placed nearest-to-the-hero first; one that would land on a label already placed or
--     on a HUD panel (the goal card, the station row, the buttons) waits hidden until there is room.
-- Hiding goes through MaxDistance, never Enabled: the owners of the labels switch Enabled themselves
-- (near-only boards, the goal's board) and keep doing so.
-- Declutter.start() once on the client.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Settings = require(script.Parent.Settings)

local Declutter = {}

local MIN_WIDTH = 140
local MARGIN = 6
local HIDDEN = 0.001 -- MaxDistance that hides a label
local SKIP_GUIS = { TouchGui = true, Freecam = true, BubbleChat = true }

local tracked: { [BillboardGui]: { base: UDim2, max: number, scale: UIScale, shown: boolean } } = {}

local function track(g: Instance)
	if not g:IsA("BillboardGui") or tracked[g] then
		return
	end
	-- labels only: damage numbers, health bars and small markers stay as they are
	if not g.AlwaysOnTop or g.Size.X.Offset < MIN_WIDTH then
		return
	end
	local s = Instance.new("UIScale")
	s.Name = "Declutter"
	s.Parent = g
	tracked[g] = { base = g.Size, max = g.MaxDistance, scale = s, shown = true }
	g.Destroying:Connect(function()
		tracked[g] = nil
	end)
end

local function anchorPoint(g: BillboardGui): Vector3?
	local a = g.Adornee or g.Parent
	local p
	if a and a:IsA("BasePart") then
		p = a.Position
	elseif a and a:IsA("Attachment") then
		p = a.WorldPosition
	elseif a and a:IsA("Model") then
		p = a:GetPivot().Position
	else
		return nil
	end
	return p + g.StudsOffsetWorldSpace
end

-- The share of rect `a` that `b` covers (0..1).
local function covered(a, b): number
	local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
	local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
	if w <= 0 or h <= 0 then
		return 0
	end
	return w * h / math.max(1, (a[3] - a[1]) * (a[4] - a[2]))
end
-- A label grazing a panel stays (the HUD draws over it); one mostly under a panel or another label waits.
local HUD_COVER, LABEL_COVER = 0.3, 0.2

-- HUD panels in screen pixels: visible, solid-ish GuiObjects in the first levels of our ScreenGuis
local function keepOut(vp: Vector2)
	local out = {}
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return out
	end
	for _, sg in pg:GetChildren() do
		if sg:IsA("ScreenGui") and sg.Enabled and not SKIP_GUIS[sg.Name] then
			local origin = sg.AbsolutePosition
			local function visit(node: Instance, depth: number)
				for _, c in node:GetChildren() do
					if c:IsA("GuiObject") and c.Visible then
						local size = c.AbsoluteSize
						local big = size.X > vp.X * 0.6 and size.Y > vp.Y * 0.6 -- a full-screen holder
						local solid = c.BackgroundTransparency < 0.9 or c:IsA("GuiButton")
						if not big and solid and size.X * size.Y > 1500 then
							local p = c.AbsolutePosition + origin
							table.insert(
								out,
								{ p.X - MARGIN, p.Y - MARGIN, p.X + size.X + MARGIN, p.Y + size.Y + MARGIN }
							)
						elseif depth < 3 then
							visit(c, depth + 1)
						end
					end
				end
			end
			visit(sg, 1)
		end
	end
	return out
end

local function setShown(g: BillboardGui, t, on: boolean)
	if t.shown ~= on then
		t.shown = on
		g.MaxDistance = if on then t.max else HIDDEN
	end
end

local function step()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local active = Settings.touch
	local vp = cam.ViewportSize
	local k = if active then math.clamp(vp.Y / 800, 0.45, 1) else 1 -- (DD-101: was /700, ≥ 0.6)
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local from = if root then root.Position else cam.CFrame.Position
	local list = {}
	for g, t in tracked do
		if t.scale.Scale ~= k then
			t.scale.Scale = k
			g.Size = UDim2.new(t.base.X.Scale, t.base.X.Offset * k, t.base.Y.Scale, t.base.Y.Offset * k)
		end
		if not active then
			setShown(g, t, true)
		elseif g.Enabled and g:IsDescendantOf(workspace) then
			local at = anchorPoint(g)
			local camDist = at and (at - cam.CFrame.Position).Magnitude
			if at and camDist < t.max then
				local sp, onScreen = cam:WorldToViewportPoint(at)
				if onScreen then
					local w, h = t.base.X.Offset * k, t.base.Y.Offset * k
					local d = (at - from).Magnitude * (if t.shown then 0.8 else 1) -- shown ones hold their place
					table.insert(
						list,
						{ g = g, t = t, d = d, rect = { sp.X - w / 2, sp.Y - h / 2, sp.X + w / 2, sp.Y + h / 2 } }
					)
				else
					setShown(g, t, true) -- off screen: nothing to collide with
				end
			end
		end
	end
	if not active then
		return
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local placed = keepOut(vp)
	local hud = #placed
	local report = if RunService:IsStudio() then {} else nil
	for _, e in list do
		local free, by = true, nil
		for i, r in placed do
			if covered(e.rect, r) > (if i <= hud then HUD_COVER else LABEL_COVER) then
				free, by = false, i
				break
			end
		end
		setShown(e.g, e.t, free)
		if free then
			table.insert(placed, e.rect)
		end
		if report then
			local l = e.g.Adornee or e.g.Parent -- (names, not texts: a cut Cyrillic text breaks the report)
			table.insert(
				report,
				string.format(
					"%s %s%s",
					if free then "+" else "-",
					l and l.Name or "?",
					if by then (if by <= hud then " [hud]" else " [label]") else ""
				)
			)
		end
	end
	if report then
		workspace:SetAttribute("DeclutterReport", table.concat(report, " | "))
	end
end

local started = false
function Declutter.start()
	if started then
		return
	end
	started = true
	for _, d in workspace:GetDescendants() do
		track(d)
	end
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("BillboardGui") then
			-- the creator sets Size and AlwaysOnTop right after parenting: look once it has
			task.defer(track, d)
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			step()
		end
	end)
end

return Declutter
