--!nonstrict
-- Builds ReplicatedStorage.ArtTemplates from Shared.Art at server start (DD-042). Each template is an
-- anchored, non-colliding MeshPart at its native size, named by key. Loading runs in parallel and is
-- bounded by a timeout: a missing asset only means the procedural fallback is used for that key.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Art = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Art"))

local ArtLoader = {}

local folder = Instance.new("Folder")
folder.Name = "ArtTemplates"
folder.Parent = ReplicatedStorage

local loaded: { [string]: MeshPart } = {}

local function make(key: string, def)
	local ok, mp = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromUri(def.mesh))
	end)
	if not ok or not mp then
		warn("[SPOREFALL] art asset failed:", key, mp)
		return
	end
	pcall(function()
		mp.TextureID = def.tex
	end)
	mp.Name = key
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.CastShadow = false
	mp.Size = def.size
	mp.Parent = folder
	loaded[key] = mp
end

-- Terrain material variants live in the place file (default.project.json; game scripts can't author
-- them). Here they only become the base-material overrides.
local function materials()
	local ms = game:GetService("MaterialService")
	for _, def in Art.Materials do
		local ok, err = pcall(function()
			assert(ms:FindFirstChild(def.name), "variant missing from the place")
			ms:SetBaseMaterialOverride(def.base, def.name)
		end)
		if not ok then
			warn("[SPOREFALL] material variant failed:", def.name, err)
		end
	end
end

-- Loads every art asset (yields, up to `timeout` seconds overall).
function ArtLoader.load(timeout: number?)
	materials()
	local pending = 0
	for key, def in Art.Meshes do
		pending += 1
		task.spawn(function()
			make(key, def)
			pending -= 1
		end)
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < (timeout or 20) do
		task.wait(0.1)
	end
	local n = 0
	for _ in loaded do
		n += 1
	end
	print(string.format("[SPOREFALL] art: %d meshes ready in %.1fs", n, os.clock() - t0))
	return n
end

function ArtLoader.get(key: string): MeshPart?
	return loaded[key]
end

-- A clone scaled so its native size times `scale` (number or Vector3), placed at `cf` with its bottom
-- on cf's position (`ground` = true) or centred on it.
function ArtLoader.place(key: string, parent: Instance, cf: CFrame, scale, ground: boolean?): MeshPart?
	local t = loaded[key]
	if not t then
		return nil
	end
	local p = t:Clone()
	local k = if typeof(scale) == "Vector3" then scale else Vector3.one * (scale or 1)
	p.Size = t.Size * k
	p.CFrame = if ground == false then cf else cf * CFrame.new(0, p.Size.Y / 2, 0)
	p.Parent = parent
	return p
end

return ArtLoader
