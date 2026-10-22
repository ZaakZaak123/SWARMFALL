--!nonstrict
-- Voice-pooled 2D audio with per-cue rate limits. Engine-bundled sounds plus Roblox-licensed Pro Sound
-- Effects library assets (free for use in Roblox experiences); cues can play a trimmed region of a file.

local SoundService = game:GetService("SoundService")

local Audio = {}

local S = "rbxasset://sounds/"
local PSE = "rbxassetid://" -- Pro Sound Effects (Roblox-licensed SFX library), verified to load in Studio
-- id, base volume, base pitch, pitch jitter, max plays per second, group, region {from, to} seconds
local CUES = {
	-- W01 arc rifle: zap crack + body thump + mechanism click; storm variant adds a thunder crack
	rifleZap = { PSE .. "9114277757", 0.32, 1.3, 0.07, 16, "sfx", { 0, 0.13 } },
	rifle = { S .. "impact_explosion_03.mp3", 0.12, 2.9, 0.12, 16, "sfx" },
	rifleClick = { S .. "volume_slider.ogg", 0.2, 0.75, 0.05, 16, "sfx" },
	rifleLow = { S .. "volume_slider.ogg", 0.16, 2.3, 0.02, 16, "sfx" },
	stormZap = { PSE .. "9114277757", 0.36, 0.95, 0.08, 16, "sfx", { 0, 0.16 } },
	thunder = { PSE .. "9126082854", 0.22, 1.35, 0.1, 5, "sfx", { 0.08, 0.6 } },
	dryFire = { PSE .. "9118138689", 0.4, 1.35, 0.03, 4, "sfx", { 0, 0.1 } },
	magOut = { PSE .. "9118138689", 0.45, 0.85, 0.03, 4, "sfx", { 0, 0.12 } },
	magIn = { PSE .. "9125656958", 0.6, 1.1, 0.03, 4, "sfx", { 0.48, 0.74 } },
	boltRack = { PSE .. "9114701864", 0.5, 1.25, 0.03, 4, "sfx", { 0.22, 0.42 } },
	equip = { PSE .. "9114701864", 0.4, 1.0, 0.03, 4, "sfx", { 0, 0.5 } },
	armorHit = { PSE .. "9119651975", 0.3, 1.15, 0.12, 10, "sfx", { 0, 0.3 } },
	wallHit = { PSE .. "9113632278", 0.18, 1.25, 0.12, 10, "sfx", { 0.08, 0.4 } },
	ricochet = { PSE .. "9113634061", 0.22, 1.2, 0.1, 6, "sfx", { 0.08, 0.5 } },
	evolveStorm = { PSE .. "9119841013", 0.8, 1.0, 0, 2, "sfx", { 0.3, 3.2 } },
	rail = { S .. "impact_explosion_03.mp3", 0.5, 0.9, 0.05, 4, "sfx" },
	shotgun = { S .. "impact_explosion_03.mp3", 0.42, 1.35, 0.08, 6, "sfx" },
	beamStart = { S .. "action_falling.ogg", 0.0, 1, 0, 4, "sfx" },
	hit = { S .. "action_jump_land.mp3", 0.2, 1.8, 0.25, 24, "sfx" },
	crit = { S .. "volume_slider.ogg", 0.3, 1.9, 0.1, 10, "sfx" },
	kill = { S .. "impact_water.mp3", 0.24, 1.6, 0.35, 18, "sfx" },
	killBig = { S .. "impact_explosion_03.mp3", 0.55, 0.75, 0.1, 6, "sfx" },
	boom = { S .. "impact_explosion_03.mp3", 0.4, 1.0, 0.15, 8, "sfx" },
	arc = { S .. "volume_slider.ogg", 0.1, 3.2, 0.4, 12, "sfx" },
	hurt = { S .. "action_jump_land.mp3", 0.8, 0.55, 0.05, 6, "sfx" },
	dash = { S .. "action_falling.ogg", 0.35, 2.4, 0.1, 4, "sfx" },
	reload = { S .. "action_get_up.mp3", 0.4, 1.5, 0.05, 3, "sfx" },
	orb = { S .. "volume_slider.ogg", 0.16, 1.6, 0, 24, "ui" },
	heal = { S .. "volume_slider.ogg", 0.4, 1.2, 0, 4, "ui" },
	level = { S .. "volume_slider.ogg", 0.5, 1.0, 0, 6, "ui" },
	ui = { S .. "volume_slider.ogg", 0.35, 1.25, 0, 20, "ui" },
	uiHover = { S .. "volume_slider.ogg", 0.12, 1.8, 0, 20, "ui" },
	warn = { S .. "volume_slider.ogg", 0.32, 0.5, 0, 6, "sfx" },
	spit = { S .. "impact_water.mp3", 0.3, 0.8, 0.1, 6, "sfx" },
	roar = { S .. "impact_explosion_03.mp3", 1, 0.32, 0, 2, "sfx" },
	evolve = { S .. "impact_explosion_03.mp3", 0.9, 0.45, 0, 2, "sfx" },
	coil = { S .. "impact_explosion_03.mp3", 0.6, 1.7, 0.05, 3, "sfx" },
	overdrive = { S .. "impact_explosion_03.mp3", 0.8, 0.6, 0, 2, "sfx" },
	banner = { S .. "volume_slider.ogg", 0.4, 0.7, 0, 4, "ui" },
	shell = { S .. "volume_slider.ogg", 0.1, 2.7, 0.2, 10, "sfx" },
	pump = { S .. "action_get_up.mp3", 0.3, 2.3, 0.05, 4, "sfx" },
	railCharge = { S .. "action_falling.ogg", 0.12, 3.2, 0.05, 4, "sfx" },
	step = { S .. "action_footsteps_plastic.mp3", 0.0, 1, 0, 1, "sfx" },
}

local groups = {}
local voices = {}
local VOICE_COUNT = 24
local voiceIndex = 0
local lastPlays: { [string]: { number } } = {}
local loops = {}

local function group(name: string): SoundGroup
	if groups[name] then
		return groups[name]
	end
	local g = Instance.new("SoundGroup")
	g.Name = "SWARMFALL_" .. name
	g.Volume = if name == "ui" then 0.8 else 1
	g.Parent = SoundService
	if name == "sfx" then
		local comp = Instance.new("CompressorSoundEffect")
		comp.Threshold = -14
		comp.Ratio = 4
		comp.Attack = 0.005
		comp.Release = 0.15
		comp.Parent = g
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = 3
		eq.MidGain = 0
		eq.HighGain = -1
		eq.Parent = g
	end
	groups[name] = g
	return g
end

function Audio.init()
	for i = 1, VOICE_COUNT do
		local s = Instance.new("Sound")
		s.Name = "Voice" .. i
		s.Parent = SoundService
		voices[i] = s
	end
	-- Preload ids
	local seen = {}
	for _, cue in CUES do
		if not seen[cue[1]] then
			seen[cue[1]] = true
			local s = Instance.new("Sound")
			s.SoundId = cue[1]
			s.Parent = SoundService
			task.delay(2, function()
				s:Destroy()
			end)
		end
	end
end

-- volume/pitch multipliers optional
function Audio.play(name: string, volume: number?, pitch: number?)
	local cue = CUES[name]
	if not cue or cue[2] <= 0 then
		return
	end
	local now = os.clock()
	local recent = lastPlays[name]
	if not recent then
		recent = {}
		lastPlays[name] = recent
	end
	-- sliding 1s window rate limit
	local n = 0
	for i = #recent, 1, -1 do
		if now - recent[i] < 1 then
			n += 1
		else
			table.remove(recent, i)
		end
	end
	if n >= cue[5] then
		return
	end
	table.insert(recent, now)
	voiceIndex = voiceIndex % VOICE_COUNT + 1
	local s = voices[voiceIndex]
	s:Stop()
	s.SoundId = cue[1]
	s.SoundGroup = group(cue[6])
	s.Volume = cue[2] * (volume or 1)
	s.PlaybackSpeed = cue[3] * (pitch or 1) * (1 + (math.random() * 2 - 1) * cue[4])
	local region = cue[7]
	s.PlaybackRegionsEnabled = region ~= nil
	if region then
		s.PlaybackRegion = NumberRange.new(region[1], region[2])
	end
	s.TimePosition = if region then region[1] else 0
	s:Play()
end

-- Positional helper: attenuates by distance from the listener focus point.
local focus = Vector3.zero
function Audio.setFocus(p: Vector3)
	focus = p
end
function Audio.at(name: string, pos: Vector3, volume: number?, pitch: number?)
	local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(focus.X, 0, focus.Z)).Magnitude
	local att = math.clamp(1 - (d - 25) / 110, 0.12, 1)
	Audio.play(name, (volume or 1) * att, pitch)
end

function Audio.loop(key: string, id: string, volume: number, pitch: number)
	local s = loops[key]
	if not s then
		s = Instance.new("Sound")
		s.Name = "Loop_" .. key
		s.Looped = true
		s.SoundId = id
		s.SoundGroup = group("sfx")
		s.Parent = SoundService
		loops[key] = s
	end
	s.Volume = volume
	s.PlaybackSpeed = pitch
	if volume > 0 and not s.IsPlaying then
		s:Play()
	elseif volume <= 0 and s.IsPlaying then
		s:Stop()
	end
end

Audio.Ids = { whoosh = S .. "action_falling.ogg", rumble = S .. "impact_explosion_03.mp3" }

return Audio
