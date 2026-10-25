--!nonstrict
-- Character masking for settlement rooms. Gear outside the character (floor rings) is removed by
-- Main. Restore original modifiers on room exit, including accessories that were already hidden.
local Players = game:GetService("Players")
local Visibility = {}
local hidden = {} -- character -> saved local properties

local function restore(char)
	local saved = hidden[char]
	if not saved then
		return
	end
	for instance, value in saved do
		if instance.Parent then
			if instance:IsA("BasePart") then
				instance.LocalTransparencyModifier = value
			elseif instance:IsA("Decal") then
				instance.Transparency = value
			elseif instance:IsA("LayerCollector") then
				instance.Enabled = value
			end
			if instance:IsA("Sound") then
				instance.Volume = value
			elseif
				instance:IsA("ParticleEmitter")
				or instance:IsA("Trail")
				or instance:IsA("Beam")
				or instance:IsA("Light")
				or instance:IsA("Highlight")
			then
				instance.Enabled = value
			end
		end
	end
	hidden[char] = nil
end

function Visibility.update(visible)
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then
			continue
		end
		if visible == nil or visible[player.UserId] then
			restore(char)
		else
			local saved = hidden[char] or {}
			hidden[char] = saved
			for _, d in char:GetDescendants() do
				if d:IsA("BasePart") then
					if saved[d] == nil then
						saved[d] = d.LocalTransparencyModifier
					end
					d.LocalTransparencyModifier = 1
				elseif d:IsA("Decal") then
					if saved[d] == nil then
						saved[d] = d.Transparency
					end
					d.Transparency = 1
				elseif d:IsA("Sound") then
					if saved[d] == nil then
						saved[d] = d.Volume
					end
					d.Volume = 0
				elseif
					d:IsA("ParticleEmitter")
					or d:IsA("Trail")
					or d:IsA("Beam")
					or d:IsA("Light")
					or d:IsA("Highlight")
					or d:IsA("BillboardGui")
				then
					if saved[d] == nil then
						saved[d] = d.Enabled
					end
					d.Enabled = false
				end
			end
		end
	end
	for char in hidden do
		if not char.Parent then
			hidden[char] = nil
		end
	end
end

return Visibility
