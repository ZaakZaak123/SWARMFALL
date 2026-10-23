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

return Settings
