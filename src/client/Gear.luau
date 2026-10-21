--!nonstrict
-- Squad loadout visuals: builds each member's weapon model (scaled by its WeaponFeel profile) and
-- hands it to the procedural Rig, which holds and animates it; plus player rings, evolution outline,
-- overdrive & shield auras.

local Theme = require(script.Parent.Theme)
local rgb = Color3.fromRGB
local M = Enum.Material

local Gear = {}

local rigs: { [Model]: any } = {}

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))
local WEAPON_COLOR, EVO_COLOR = {}, {}
for id, w in Defs.Weapons do
	WEAPON_COLOR[id] = w.color
	EVO_COLOR[id] = Defs.Evolutions[w.evolution].color
end

local Models = require(script.Parent.Models)
local Rig = require(script.Parent.Rig)
local Feel = require(script.Parent.WeaponFeel)

local function buildGun(model: Model, character: Model, weapon: string, evolved: boolean)
	local accent = if evolved then EVO_COLOR[weapon] else WEAPON_COLOR[weapon]
	local feel = Feel.get(weapon, evolved)
	local gun, meta = Models.weapon(weapon, evolved, false, feel.scale)
	gun.Name = "Gun"
	for _, p in gun:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
	local muzzle = gun:FindFirstChild("Muzzle") or gun.PrimaryPart
	muzzle.Transparency = 1
	gun.Parent = model
	Rig.setWeapon(character, gun, meta, feel)
	return muzzle, accent
end

local function ringPart(color: Color3, diameter: number, transparency: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = M.Neon
	p.Shape = Enum.PartType.Cylinder
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.new(0.05, diameter, diameter)
	p.Parent = workspace
	return p
end

-- Ensures a rig for the character with the given loadout; rebuilds on evolution.
function Gear.ensure(character: Model, weapon: string, evolved: boolean, isLocal: boolean)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local rig = rigs[character]
	if rig and (rig.weapon ~= weapon or rig.evolved ~= evolved or rig.root ~= root or not Rig.hasWeapon(character)) then
		Gear.remove(character)
		rig = nil
	end
	if rig then
		return rig
	end
	if not Rig.get(character) then
		return nil -- body parts still streaming in
	end
	local model = Instance.new("Model")
	model.Name = "SwarmGear"
	model.Parent = character
	local muzzle, accent = buildGun(model, character, weapon, evolved)
	rig = {
		model = model,
		root = root,
		weapon = weapon,
		evolved = evolved,
		muzzle = muzzle,
		accent = accent,
		character = character,
		ring = ringPart(if isLocal then Theme.C.cyan else Theme.C.gold, 5.5, 0.35),
		ringInner = ringPart(rgb(10, 16, 24), 4.6, 0.3),
		aura = nil,
		isLocal = isLocal,
	}
	if evolved then
		local h = Instance.new("Highlight")
		h.FillTransparency = 1
		h.OutlineColor = accent
		h.OutlineTransparency = 0.3
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
	end
	rigs[character] = rig
	return rig
end

function Gear.remove(character: Model)
	local rig = rigs[character]
	if rig then
		Rig.clearWeapon(character)
		rig.model:Destroy()
		rig.ring:Destroy()
		rig.ringInner:Destroy()
		if rig.aura then
			rig.aura:Destroy()
		end
		if rig.shield then
			rig.shield:Destroy()
		end
		rigs[character] = nil
	end
end

-- Per-frame: rings, flash lights, overdrive aura, shield bubble.
function Gear.update(rig, od: boolean, shield: number, dead: boolean)
	if not rig.root.Parent then
		return
	end
	local pos = rig.root.Position
	local now = os.clock()
	local ringY = math.max(0.07, pos.Y - 2.95)
	local pulse = 1 + math.sin(now * 4) * 0.04
	rig.ring.Size = Vector3.new(0.05, 5.5 * pulse, 5.5 * pulse)
	rig.ring.CFrame = CFrame.new(pos.X, ringY, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
	rig.ringInner.CFrame = CFrame.new(pos.X, ringY + 0.01, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
	rig.ring.Transparency = if dead then 1 else 0.35
	rig.ringInner.Transparency = if dead then 1 else 0.3
	if od and not rig.aura then
		local a = Instance.new("Part")
		a.Anchored = true
		a.CanCollide = false
		a.CanQuery = false
		a.CastShadow = false
		a.Material = M.ForceField
		a.Shape = Enum.PartType.Ball
		a.Color = Theme.C.gold
		a.Size = Vector3.one * 8
		a.Parent = workspace
		rig.aura = a
	elseif not od and rig.aura then
		rig.aura:Destroy()
		rig.aura = nil
	end
	if rig.aura then
		rig.aura.CFrame = CFrame.new(pos) * CFrame.Angles(0, now * 3, 0)
	end
	if shield > 0 and not rig.shield then
		local s = Instance.new("Part")
		s.Anchored = true
		s.CanCollide = false
		s.CanQuery = false
		s.CastShadow = false
		s.Material = M.ForceField
		s.Shape = Enum.PartType.Ball
		s.Color = Theme.C.blue
		s.Size = Vector3.one * 7
		s.Parent = workspace
		rig.shield = s
	elseif shield <= 0 and rig.shield then
		rig.shield:Destroy()
		rig.shield = nil
	end
	if rig.shield then
		rig.shield.CFrame = CFrame.new(pos)
	end
end

function Gear.cleanup()
	for character, _ in rigs do
		if not character.Parent then
			Gear.remove(character)
		end
	end
end

return Gear
