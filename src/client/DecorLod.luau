--!nonstrict
-- Arena decor scaled by the client quality setting (DD-044). The server builds one crater for everyone;
-- each client trims what it can't afford:
--   High    everything as authored
--   Medium  every other ambient glow light off, spores at 60%, decor casts no shadows
--   Low     ambient glow lights off, spores at 30%, no decor shadows
-- (global shadows per quality stay with Main.client: Settings.Budget.shadows)
-- "Ambient" lights are the flora/crystal glows the server tags; gameplay lights (wounds, the rig, the
-- pylons) always stay on. Late-replicating decor is picked up as it arrives.

local Settings = require(script.Parent.Settings)

local DecorLod = {}

local RATE = { 0.3, 0.6, 1 }

local lights: { Light } = {}
local emitters: { [ParticleEmitter]: number } = {}
local casters: { BasePart } = {}
local conn: RBXScriptConnection? = nil

local function applyOne(d: Instance, q: number, index: number?)
	if d:IsA("Light") then
		d.Enabled = q >= 3 or (q == 2 and (index or 0) % 2 == 0)
	elseif d:IsA("ParticleEmitter") then
		d.Rate = (emitters[d] or d.Rate) * RATE[q]
	elseif d:IsA("BasePart") then
		d.CastShadow = q >= 3
	end
end

local function track(d: Instance)
	if d:IsA("Light") and d:GetAttribute("Ambient") then
		table.insert(lights, d)
		applyOne(d, Settings.quality, #lights)
	elseif d:IsA("ParticleEmitter") then
		emitters[d] = d.Rate
		applyOne(d, Settings.quality)
	elseif d:IsA("MeshPart") and d.CastShadow then
		table.insert(casters, d)
		applyOne(d, Settings.quality)
	end
end

local function applyAll()
	local q = Settings.quality
	for i, l in lights do
		applyOne(l, q, i)
	end
	for e in emitters do
		applyOne(e, q)
	end
	for _, p in casters do
		applyOne(p, q)
	end
end

-- Called whenever the arena's Decor folder is (re)built.
function DecorLod.scan(decor: Instance)
	table.clear(lights)
	table.clear(emitters)
	table.clear(casters)
	if conn then
		conn:Disconnect()
	end
	for _, d in decor:GetDescendants() do
		track(d)
	end
	conn = decor.DescendantAdded:Connect(track)
	applyAll()
end

Settings.onChanged(function(key)
	if key == "quality" then
		applyAll()
	end
end)

return DecorLod
