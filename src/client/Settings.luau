--!nonstrict
-- Per-client presentation settings. Never affect server damage.

local UserInputService = game:GetService("UserInputService")

local Settings = {
	quality = 3, -- 3 High, 2 Medium, 1 Low
	shake = true,
	numbers = true,
	touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
	aimAssist = true,
	autoQuality = true, -- drop/raise quality from the measured frame rate during runs
	homeMusic = true, -- DD-093: the shelter's music (the cabin's gramophone or the settings turn it off)
}

-- Per-quality presentation budgets (index = quality 1..3).
Settings.Budget = {
	fxParts = { 160, 280, 420 }, -- pooled FX parts alive at once
	animDistance = { 70, 115, 160 }, -- enemies farther than this skip gait / blink animation
	shadows = { false, false, true },
}

Settings.QualityNames = { "LOW", "MEDIUM", "HIGH" }

local listeners = {}
function Settings.onChanged(fn)
	table.insert(listeners, fn)
end
function Settings.set(key: string, value)
	Settings[key] = value
	for _, fn in listeners do
		task.spawn(fn, key, value)
	end
end

-- Studio-only: workspace attribute DevTouch emulates a phone (touch layout) for screenshots.
if game:GetService("RunService"):IsStudio() and workspace:GetAttribute("DevTouch") then
	Settings.touch = true
end

-- Low-end mobile starts on Medium.
if Settings.touch then
	Settings.quality = 2
end

-- DD-098: on a phone the gun can aim and fire by itself at the nearest enemy. DD-099 (owner: «атака
-- стала ещё хуже»): off by default, the manual aim pad is back; the settings still turn it on.
Settings.autoAim = false

-- DD-103 (prototype): the phone's simple fight. The camera stands still behind and above the hero (it
-- never turns), the gun picks its target and fires by itself, the left thumb only runs; the right pad
-- stays for those who want to aim by hand. On by default on a touch screen; the settings switch back to
-- the over-the-shoulder fight.
Settings.simpleCombat = Settings.touch
-- Studio-only: workspace attribute DevShoulder starts in the over-the-shoulder fight (layout checks)
if game:GetService("RunService"):IsStudio() and workspace:GetAttribute("DevShoulder") then
	Settings.simpleCombat = false
end

return Settings
