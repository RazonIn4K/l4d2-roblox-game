--!strict
--[[
    Client Entry Point
    Initializes client-side controllers for UI, input, and effects
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Wait for character
local function onCharacterAdded(character: Model)
	print("[Client] Character loaded")

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- Handle health changes
	humanoid.HealthChanged:Connect(function(health)
		-- TODO: Update health UI
	end)

	-- Handle death
	humanoid.Died:Connect(function()
		print("[Client] Player died")
		-- TODO: Show death screen
	end)
end

-- Setup
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

-- Setup remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Game state updates
local gameStateRemote = remotes:WaitForChild("GameState")
gameStateRemote.OnClientEvent:Connect(function(state)
	print("[Client] Game state:", state)
	-- TODO: Update UI based on state
end)

-- Entity updates
local entityUpdateRemote = remotes:WaitForChild("EntityUpdate")
entityUpdateRemote.OnClientEvent:Connect(function(updates)
	-- TODO: Update entity visuals
end)

-- Input handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- E key for interaction/revive
	if input.KeyCode == Enum.KeyCode.E then
		-- TODO: Check for nearby interactables or incapped players
	end

	-- F key for flashlight
	if input.KeyCode == Enum.KeyCode.F then
		-- TODO: Toggle flashlight
	end
end)

print("[Client] Initialized")
