--!strict
--[[
    Client Entry Point
    Initializes client-side controllers for UI, input, and effects
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Import controllers
local AmbientSoundController = require(script.Parent:WaitForChild("Controllers"):WaitForChild("AmbientSoundController"))
local DamageFeedbackController =
	require(script.Parent:WaitForChild("Controllers"):WaitForChild("DamageFeedbackController"))
local HorrorLightingController =
	require(script.Parent:WaitForChild("Controllers"):WaitForChild("HorrorLightingController"))
local UIController = require(script.Parent:WaitForChild("Controllers"):WaitForChild("UIController"))

-- Constants
local RESCUE_RANGE = 4 -- Must match server

-- Unified Game State (consolidates all client state)
local GameState = {
	gameState = "Lobby", -- Lobby | Loading | Playing | SafeRoom | Finale | Victory | Failed
	playerHealth = {}, -- { [playerId] = health }
	entities = {}, -- { [entityId] = { pos, type, state } }
	ammo = { magazine = 15, reserve = math.huge, weapon = "Pistol" },
	-- Legacy state (kept for backward compatibility)
	rescuePrompt = nil :: BillboardGui?,
	nearbyPinnedPlayer = nil :: Player?,
	currentAmmo = { magazine = 15, reserve = math.huge, weapon = "Pistol" },
	ammoLabel = nil :: TextLabel?,
	flashlightEnabled = false,
	flashlight = nil :: SpotLight?,
}

-- Convenience aliases for backward compatibility (using GameState directly)
local currentAmmo = GameState.currentAmmo

-- ============================================
-- AMMO DISPLAY UI
-- ============================================

local function createAmmoDisplay(): TextLabel
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WeaponHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local ammoFrame = Instance.new("Frame")
	ammoFrame.Name = "AmmoFrame"
	ammoFrame.Size = UDim2.new(0, 200, 0, 60)
	ammoFrame.Position = UDim2.new(1, -220, 1, -80)
	ammoFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	ammoFrame.BackgroundTransparency = 0.5
	ammoFrame.BorderSizePixel = 0
	ammoFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = ammoFrame

	local label = Instance.new("TextLabel")
	label.Name = "AmmoText"
	label.Size = UDim2.new(1, -20, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 24
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.Text = "15 / ∞"
	label.Parent = ammoFrame

	return label
end

local function updateAmmoDisplay()
	if not GameState.ammoLabel then
		GameState.ammoLabel = createAmmoDisplay()
	end

	-- Use unified state
	local ammo = GameState.ammo
	local reserveText = ammo.reserve == math.huge and "∞" or tostring(ammo.reserve)
	if GameState.ammoLabel then
		GameState.ammoLabel.Text = string.format("%d / %s", ammo.magazine, reserveText)
	end
end

-- ============================================
-- FLASHLIGHT SYSTEM
-- ============================================

local function createFlashlight(): SpotLight?
	local character = player.Character
	if not character then
		return nil
	end

	local head = character:FindFirstChild("Head")
	if not head then
		return nil
	end

	-- Create spotlight attached to head
	local spotlight = Instance.new("SpotLight")
	spotlight.Name = "Flashlight"
	spotlight.Brightness = 2
	spotlight.Range = 60
	spotlight.Angle = 45
	spotlight.Face = Enum.NormalId.Front
	spotlight.Shadows = true
	spotlight.Enabled = false
	spotlight.Parent = head

	return spotlight
end

local function toggleFlashlight()
	local character = player.Character
	if not character then
		return
	end

	-- Create flashlight if it doesn't exist or was destroyed
	if not GameState.flashlight or not GameState.flashlight.Parent then
		GameState.flashlight = createFlashlight()
		if not GameState.flashlight then
			return
		end
	end

	-- Toggle state
	GameState.flashlightEnabled = not GameState.flashlightEnabled
	if GameState.flashlight then
		GameState.flashlight.Enabled = GameState.flashlightEnabled
	end

	-- Play click sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://156286438" -- Click sound
	sound.Volume = 0.3
	sound.Parent = character:FindFirstChild("Head") or character.PrimaryPart
	sound:Play()
	Debris:AddItem(sound, 1)

	print(string.format("[Client] Flashlight %s", GameState.flashlightEnabled and "ON" or "OFF"))
end

-- ============================================
-- MUZZLE FLASH EFFECT
-- ============================================

local function createMuzzleFlash()
	local character = player.Character
	if not character then
		return
	end

	-- Find right arm or hand for muzzle position
	local rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	if not rightArm then
		return
	end

	-- Create flash part
	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Size = Vector3.new(0.5, 0.5, 1)
	flash.Material = Enum.Material.Neon
	flash.BrickColor = BrickColor.new("Bright yellow")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CastShadow = false
	flash.CFrame = rightArm.CFrame * CFrame.new(0, 0, -1.5)
	flash.Parent = workspace

	-- Add point light
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 100)
	light.Brightness = 3
	light.Range = 10
	light.Parent = flash

	-- Remove after short duration
	Debris:AddItem(flash, 0.05)
end

-- ============================================
-- GUNSHOT SOUND
-- ============================================

local function playGunshotSound()
	local character = player.Character
	if not character then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://131070686" -- Placeholder gunshot sound
	sound.Volume = 0.5
	sound.PlaybackSpeed = 1 + (math.random() - 0.5) * 0.1 -- Slight variation
	sound.Parent = hrp
	sound:Play()

	Debris:AddItem(sound, 1)
end

-- ============================================
-- SHOOTING SYSTEM
-- ============================================

local function getTargetPosition(): Vector3?
	local mouse = player:GetMouse()
	if not mouse then
		return nil
	end

	-- Raycast from camera
	local origin = camera.CFrame.Position
	local direction = (mouse.Hit.Position - origin).Unit * 1000

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { player.Character }

	local result = workspace:Raycast(origin, direction, rayParams)

	if result then
		return result.Position
	else
		return origin + direction
	end
end

local function fireWeapon()
	-- Check if we have ammo (client-side prediction)
	if GameState.ammo.magazine <= 0 then
		-- Play empty click sound
		return
	end

	local targetPosition = getTargetPosition()
	if not targetPosition then
		return
	end

	-- Visual effects (immediate feedback)
	createMuzzleFlash()
	playGunshotSound()

	-- Client-side ammo prediction (optimistic update)
	local predictedMagazine = GameState.ammo.magazine - 1
	GameState.ammo.magazine = predictedMagazine
	currentAmmo.magazine = predictedMagazine -- Sync legacy state
	updateAmmoDisplay()

	-- Send to server (server will validate and reconcile)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local fireWeaponRemote = remotes:WaitForChild("FireWeapon")
	fireWeaponRemote:FireServer(targetPosition)
end

-- Create rescue prompt UI (uses unified state)
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
	if not character then
		return nil
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local myPosition = hrp.Position

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player then
			continue
		end

		local otherChar = otherPlayer.Character
		if not otherChar then
			continue
		end

		-- Check if pinned or grabbed
		local isPinned = otherChar:GetAttribute("IsPinned")
		local isGrabbed = otherChar:GetAttribute("IsGrabbed")
		if not isPinned and not isGrabbed then
			continue
		end

		local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
		if not otherHrp then
			continue
		end

		local distance = (myPosition - otherHrp.Position).Magnitude
		if distance <= RESCUE_RANGE then
			return otherPlayer
		end
	end

	return nil
end

-- Update rescue prompt visibility
local function updateRescuePrompt()
	if not GameState.rescuePrompt then
		GameState.rescuePrompt = createRescuePrompt()
	end

	GameState.nearbyPinnedPlayer = findNearbyPinnedPlayer()

	if GameState.nearbyPinnedPlayer and GameState.rescuePrompt then
		local pinnedChar = GameState.nearbyPinnedPlayer.Character
		if pinnedChar then
			local headOrPart: Instance? = pinnedChar:FindFirstChild("Head") or pinnedChar.PrimaryPart
			if headOrPart then
				GameState.rescuePrompt.Adornee = headOrPart :: Instance
			end
			GameState.rescuePrompt.Enabled = true

			local label = GameState.rescuePrompt:FindFirstChild("Background", true)
			if label then
				local textLabel = label:FindFirstChild("PromptText") :: TextLabel?
				if textLabel then
					textLabel.Text = string.format("Press E to rescue %s", GameState.nearbyPinnedPlayer.Name)
				end
			end
		end
	elseif GameState.rescuePrompt then
		GameState.rescuePrompt.Enabled = false
		-- Clear Adornee by setting to a dummy part (Roblox type system doesn't allow nil)
		-- The prompt will be hidden anyway since Enabled = false
	end
end

-- Wait for character
local function onCharacterAdded(character: Model)
	print("[Client] Character loaded")

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- Note: Health UI updates are handled by UIController
	-- UIController connects to HealthChanged in SetupCharacterHealth()

	-- Handle death
	humanoid.Died:Connect(function()
		print("[Client] Player died")
		UIController:Get():ShowDeathScreen()
	end)
end

-- Setup
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

-- Setup remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Unified State Update Handler (consolidates all state updates)
local function updateGameState(stateUpdate: { [string]: any })
	-- Update game state
	if stateUpdate.gameState then
		GameState.gameState = stateUpdate.gameState
		print("[Client] Game state:", stateUpdate.gameState)
		-- TODO: Update UI based on state
	end
	
	-- Update player health
	if stateUpdate.playerHealth then
		for playerId, health in pairs(stateUpdate.playerHealth) do
			GameState.playerHealth[playerId] = health
		end
	end
	
	-- Update entities
	if stateUpdate.entities then
		for entityId, entityData in pairs(stateUpdate.entities) do
			GameState.entities[entityId] = entityData
		end
		-- TODO: Update entity visuals
	end
	
	-- Update ammo (reconciles client prediction with server authority)
	if stateUpdate.ammo then
		GameState.ammo.magazine = stateUpdate.ammo.magazine or GameState.ammo.magazine
		GameState.ammo.reserve = stateUpdate.ammo.reserve or GameState.ammo.reserve
		GameState.ammo.weapon = stateUpdate.ammo.weapon or GameState.ammo.weapon
		-- Sync to legacy state
		currentAmmo.magazine = GameState.ammo.magazine
		currentAmmo.reserve = GameState.ammo.reserve
		currentAmmo.weapon = GameState.ammo.weapon
		updateAmmoDisplay()
	end
end

-- Game state updates (unified handler)
local gameStateRemote = remotes:WaitForChild("GameState")
gameStateRemote.OnClientEvent:Connect(function(state)
	updateGameState({ gameState = state })
end)

-- Entity updates (legacy - kept for backward compatibility)
local entityUpdateRemote = remotes:WaitForChild("EntityUpdate")
entityUpdateRemote.OnClientEvent:Connect(function(updates)
	if updates then
		updateGameState({ entities = updates })
	end
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

-- Ammo update remote (reconciles client prediction with server authority)
local ammoUpdateRemote = remotes:WaitForChild("AmmoUpdate")
ammoUpdateRemote.OnClientEvent:Connect(function(ammoData)
	if ammoData then
		updateGameState({ ammo = ammoData })
		print(string.format("[Client] Ammo reconciled: %d/%s", 
			ammoData.magazine or 0, 
			ammoData.reserve == math.huge and "∞" or tostring(ammoData.reserve)))
	end
end)

-- Fire result remote
local fireResultRemote = remotes:WaitForChild("FireResult")
fireResultRemote.OnClientEvent:Connect(function(success: boolean, result: string, _hitData)
	if success then
		if result == "Hit" then
			print("[Client] Hit target!")
		end
	else
		if result == "NoAmmo" then
			print("[Client] Out of ammo!")
		end
	end
end)

-- Update loop for rescue prompt
RunService.Heartbeat:Connect(function()
	updateRescuePrompt()
end)

-- Mouse click for shooting
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- Left mouse button for shooting
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		fireWeapon()
		return
	end

	-- E key for interaction/revive/rescue
	if input.KeyCode == Enum.KeyCode.E then
		-- Check for nearby pinned players first
		if GameState.nearbyPinnedPlayer then
			print(string.format("[Client] Attempting to rescue %s", GameState.nearbyPinnedPlayer.Name))
			attemptRescueRemote:FireServer(GameState.nearbyPinnedPlayer)
			return
		end

		-- TODO: Check for nearby interactables or incapped players
	end

	-- F key for flashlight
	if input.KeyCode == Enum.KeyCode.F then
		toggleFlashlight()
		return
	end
end)

-- Initialize controllers first
UIController:Get():Start()
AmbientSoundController:Get():Start()
DamageFeedbackController:Get():Start()
HorrorLightingController:Get():Start()

-- Initialize ammo display after controllers (ensures remotes are ready)
updateAmmoDisplay()

print("[Client] Initialized")
