-- Studio QA (Client datamodel): shut out the gamepad for a test session. The owner plays other games on a
-- second monitor with a gamepad that Studio also hears: the hero walks off, prompts fire (ButtonX sits on a
-- chair, ButtonY opens a card), menus pop up. Paste this file whole into MCP execute_luau (Client) before
-- driving the game (the client cannot fetch it over HTTP).
-- Keyboard and mouse input from MCP still work. Undone by stopping Play.
local CAS = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local pads = {}
for i = 1, 8 do
	table.insert(pads, Enum.UserInputType["Gamepad" .. i])
end
CAS:BindActionAtPriority("SwarmNoPad", function()
	return Enum.ContextActionResult.Sink
end, false, 1e6, table.unpack(pads))
pcall(function()
	GuiService.AutoSelectGuiEnabled = false
	GuiService.GuiNavigationEnabled = false
	GuiService.SelectedObject = nil
end)
-- ProximityPrompts read the pad on their own (ButtonX sat the hero down past the sink): no pad key on any
local function unpad(d: Instance)
	if d:IsA("ProximityPrompt") then
		d.GamepadKeyCode = Enum.KeyCode.Unknown
	end
end
for _, d in workspace:GetDescendants() do
	unpad(d)
end
workspace.DescendantAdded:Connect(unpad)
return "gamepad input sunk"
