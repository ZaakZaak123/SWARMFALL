--!nonstrict
-- Per-client presentation settings. Never affect server damage.

local UserInputService = game:GetService("UserInputService")

local Settings = {
	quality = 3, -- 3 High, 2 Medium, 1 Low
	shake = true,
	numbers = true,
	touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
	aimAssist = true,
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

-- Low-end mobile starts on Medium.
if Settings.touch then
	Settings.quality = 2
end

return Settings
