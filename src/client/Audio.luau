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
	-- Stage 12: the rest of the arsenal and the world moved to the Pro Sound Effects library too.
	-- Regions come from measured loudness envelopes (AudioAnalyzer), so each cue plays its hit, not silence.
	-- W02 «Вулкан»: 12-gauge body + a short close crack; pump clack; brass drop
	shotgun = { PSE .. "9112912106", 0.5, 1.0, 0.06, 6, "sfx", { 0, 0.85 } },
	shotgunCrack = { PSE .. "9112913564", 0.35, 1.15, 0.06, 6, "sfx" },
	pump = { PSE .. "9112910245", 0.45, 1.05, 0.04, 4, "sfx", { 0.78, 1.05 } },
	shell = { PSE .. "9113105142", 0.14, 1.2, 0.2, 10, "sfx", { 0, 0.6 } },
	-- W04 rail: laser crack + thruster body; capacitor charge between shots
	rail = { PSE .. "9116225257", 0.42, 0.85, 0.05, 4, "sfx", { 0.18, 1.2 } },
	railBody = { PSE .. "9120006514", 0.35, 0.8, 0.05, 4, "sfx", { 0, 1.0 } },
	railCharge = { PSE .. "9125980435", 0.16, 1.2, 0.05, 4, "sfx", { 0.15, 1.05 } },
	beamStart = { S .. "action_falling.ogg", 0.0, 1, 0, 4, "sfx" },
	-- Hits and deaths
	hit = { PSE .. "9113485720", 0.16, 1.35, 0.25, 24, "sfx", { 0, 0.35 } },
	crit = { PSE .. "9120146668", 0.22, 1.3, 0.1, 10, "sfx" },
	kill = { PSE .. "9114788214", 0.2, 1.25, 0.3, 18, "sfx", { 0, 0.6 } },
	killBig = { PSE .. "9119236757", 0.6, 0.85, 0.1, 6, "sfx", { 0.05, 0.7 } },
	boom = { PSE .. "9119236749", 0.45, 1.0, 0.15, 8, "sfx", { 0, 1.2 } },
	arc = { PSE .. "9114277757", 0.12, 1.6, 0.25, 12, "sfx", { 0, 0.08 } },
	ice = { PSE .. "9114856749", 0.4, 1.1, 0.12, 6, "sfx", { 0.38, 0.9 } },
	-- Player
	hurt = { PSE .. "9118167124", 0.7, 0.9, 0.08, 6, "sfx", { 0.25, 0.6 } },
	dash = { PSE .. "9126229255", 0.4, 1.15, 0.1, 4, "sfx", { 0.05, 0.45 } },
	reload = { PSE .. "9125656958", 0.5, 1.0, 0.05, 3, "sfx", { 0.48, 0.74 } },
	heal = { PSE .. "9117297453", 0.35, 1.2, 0, 4, "ui", { 0.3, 1.9 } },
	overdrive = { PSE .. "9113524242", 0.9, 0.7, 0.03, 2, "sfx", { 0.15, 0.6 } },
	-- Enemies
	spit = { PSE .. "9119473131", 0.32, 1.0, 0.12, 6, "sfx" },
	roar = { PSE .. "9113987603", 1, 0.85, 0, 2, "sfx", { 0.5, 3.0 } },
	-- UI and events
	orb = { PSE .. "9114381603", 0.18, 1.3, 0, 24, "ui" },
	level = { PSE .. "9116422179", 0.45, 1.0, 0, 6, "ui", { 0, 0.8 } },
	ui = { PSE .. "9118138693", 0.4, 1.1, 0, 20, "ui" },
	uiHover = { PSE .. "9118138906", 0.14, 1.4, 0, 20, "ui" },
	warn = { PSE .. "9120491370", 0.3, 1.0, 0, 6, "sfx", { 0.08, 0.45 } },
	evolve = { PSE .. "9116384485", 0.8, 0.9, 0, 2, "sfx", { 0.08, 1.6 } },
	coil = { PSE .. "9125446705", 0.5, 1.0, 0.05, 3, "sfx" },
	banner = { PSE .. "9113867372", 0.35, 1.0, 0, 4, "ui" },
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

Audio.Ids = { whoosh = S .. "action_falling.ogg", rumble = S .. "impact_explosion_03.mp3", beam = PSE .. "9114246115" }

return Audio
