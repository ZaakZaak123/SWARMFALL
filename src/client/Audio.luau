--!nonstrict
-- Voice-pooled 2D audio with per-cue rate limits. Uses only engine-bundled sounds (no uploads needed),
-- shaped with pitch and effects. Swap any `id` for a licensed rbxassetid to upgrade a cue.

local SoundService = game:GetService("SoundService")

local Audio = {}

local S = "rbxasset://sounds/"
-- id, base volume, base pitch, pitch jitter, max plays per second, group
local CUES = {
	rifle = { S .. "impact_explosion_03.mp3", 0.16, 2.9, 0.12, 14, "sfx" },
	rifleClick = { S .. "volume_slider.ogg", 0.22, 0.75, 0.05, 14, "sfx" },
	thunder = { S .. "impact_explosion_03.mp3", 0.2, 2.2, 0.15, 14, "sfx" },
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
	s.TimePosition = 0
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
