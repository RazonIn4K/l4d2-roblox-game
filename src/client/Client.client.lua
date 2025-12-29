--!strict
--[[
    Client Entry Point
    Initializes client-side controllers for UI, input, and effects
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Constants
local RESCUE_RANGE = 4  -- Must match server

-- State
local rescuePrompt: BillboardGui? = nil
local nearbyPinnedPlayer: Player? = nil

-- Create rescue prompt UI
local function createRescuePrompt(): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RescuePrompt"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	
	local frame = Instance.new("Frame")
	frame.Name = "Background"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0
	frame.Parent = billboard
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	
	local label = Instance.new("TextLabel")
	label.Name = "PromptText"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 16
	label.Font = Enum.Font.GothamBold
	label.Text = "Press E to rescue"
	label.Parent = frame
	
	billboard.Parent = player.PlayerGui
	return billboard
end

-- Find nearby pinned players
local function findNearbyPinnedPlayer(): Player?
	local character = player.Character
	if not character then return nil end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	
	local myPosition = hrp.Position
	
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player then continue end
		
		local otherChar = otherPlayer.Character
		if not otherChar then continue end
		
		-- Check if pinned
		local isPinned = otherChar:GetAttribute("IsPinned")
		if not isPinned then continue end
		
		local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
		if not otherHrp then continue end
		
		local distance = (myPosition - otherHrp.Position).Magnitude
		if distance <= RESCUE_RANGE then
			return otherPlayer
		end
	end
	
	return nil
end

-- Update rescue prompt visibility
local function updateRescuePrompt()
	if not rescuePrompt then
		rescuePrompt = createRescuePrompt()
	end
	
	nearbyPinnedPlayer = findNearbyPinnedPlayer()
	
	if nearbyPinnedPlayer then
		local pinnedChar = nearbyPinnedPlayer.Character
		if pinnedChar then
			rescuePrompt.Adornee = pinnedChar:FindFirstChild("Head") or pinnedChar.PrimaryPart
			rescuePrompt.Enabled = true
			
			local label = rescuePrompt:FindFirstChild("Background", true)
			if label then
				local textLabel = label:FindFirstChild("PromptText") :: TextLabel?
				if textLabel then
					textLabel.Text = string.format("Press E to rescue %s", nearbyPinnedPlayer.Name)
				end
			end
		end
	else
		rescuePrompt.Enabled = false
		rescuePrompt.Adornee = nil
	end
end

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

-- Rescue remote
local attemptRescueRemote = remotes:WaitForChild("AttemptRescue")
attemptRescueRemote.OnClientEvent:Connect(function(success: boolean, message: string)
	if success then
		print("[Client] Rescue successful!")
	else
		print("[Client] Rescue failed:", message)
	end
end)

-- Update loop for rescue prompt
RunService.Heartbeat:Connect(function()
	updateRescuePrompt()
end)

-- Input handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- E key for interaction/revive/rescue
	if input.KeyCode == Enum.KeyCode.E then
		-- Check for nearby pinned players first
		if nearbyPinnedPlayer then
			print(string.format("[Client] Attempting to rescue %s", nearbyPinnedPlayer.Name))
			attemptRescueRemote:FireServer(nearbyPinnedPlayer)
			return
		end
		
		-- TODO: Check for nearby interactables or incapped players
	end

	-- F key for flashlight
	if input.KeyCode == Enum.KeyCode.F then
		-- TODO: Toggle flashlight
	end
end)

print("[Client] Initialized")
