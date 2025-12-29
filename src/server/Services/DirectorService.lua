--!strict
--[[
    DirectorService
    AI Director for pacing - controls intensity, spawning, and game rhythm
    Based on L4D2's pacing system: BuildUp → SustainPeak → PeakFade → Relax
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local _ServerScriptService = game:GetService("ServerScriptService")

-- Import EntityFactory
local EntityFactory = require(script.Parent:WaitForChild("EntityFactory"))

-- Types
export type DirectorState = "Idle" | "BuildUp" | "SustainPeak" | "PeakFade" | "Relax" | "Crescendo" | "SafeRoom"

-- Constants
local CONFIG = {
	peakThreshold = 70,
	relaxDurationMin = 30,
	relaxDurationMax = 45,
	sustainPeakDurationMin = 3,
	sustainPeakDurationMax = 5,
	intensityDecayRate = 5,
	combatRadius = 30,
	commonSpawnIntervalMin = 90,
	commonSpawnIntervalMax = 180,
	specialSpawnIntervalMin = 20,
	specialSpawnIntervalMax = 40,
}

-- Module
local DirectorService = {}
DirectorService.__index = DirectorService

local _instance: DirectorService? = nil

function DirectorService.new()
	if _instance then
		return _instance
	end

	local self = setmetatable({}, DirectorService)

	-- State
	self.State = "Idle" :: DirectorState
	self.Intensity = 0
	self.StateTimer = 0

	-- Spawn timers
	self.CommonSpawnTimer = 0
	self.SpecialTimers = {
		Hunter = 0,
		Smoker = 0,
		Boomer = 0,
		Tank = 0,
	}

	-- Tracking
	self._inCombat = false
	self._lastUpdate = 0

	-- Connections
	self._connections = {} :: { RBXScriptConnection }

	-- Events
	self.OnStateChanged = Instance.new("BindableEvent")
	self.OnIntensityChanged = Instance.new("BindableEvent")

	_instance = self
	return self
end

function DirectorService:Get(): DirectorService
	return DirectorService.new()
end

function DirectorService:Start()
	-- Main update loop
	table.insert(
		self._connections,
		RunService.Heartbeat:Connect(function(dt)
			self:Update(dt)
		end)
	)

	-- Listen for game events
	self:ConnectGameEvents()

	print("[DirectorService] Started - AI Director active")
end

function DirectorService:ConnectGameEvents()
	-- Get GameService reference
	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)

	-- Listen for game state changes
	GameService:Get().OnStateChanged.Event:Connect(function(oldState, newState)
		if newState == "Playing" then
			self:TransitionTo("Relax") -- Grace period at start
			self.StateTimer = 5 -- 5-second timer for testing
			print("[Director] Game started, entering Relax state for 5 seconds")
		elseif newState == "SafeRoom" then
			self:TransitionTo("SafeRoom")
		elseif newState == "Failed" or newState == "Victory" then
			self:TransitionTo("Idle")
		end
	end)
	
	-- Test trigger: Automatically transition to Playing state after 2 seconds
	task.wait(2)
	print("[Director] Test trigger: Transitioning to Playing state...")
	GameService:Get():SetState("Playing")
end

function DirectorService:Update(dt: number)
	if self.State == "Idle" or self.State == "SafeRoom" then
		return
	end

	-- Update combat status
	self:UpdateCombatStatus()

	-- Decay intensity
	self:DecayIntensity(dt)

	-- Update state timers
	self:UpdateTimers(dt)

	-- State machine
	if self.State == "BuildUp" then
		self:UpdateBuildUp(dt)
	elseif self.State == "SustainPeak" then
		self:UpdateSustainPeak(dt)
	elseif self.State == "PeakFade" then
		self:UpdatePeakFade(dt)
	elseif self.State == "Relax" then
		self:UpdateRelax(dt)
	elseif self.State == "Crescendo" then
		self:UpdateCrescendo(dt)
	end

	-- Process spawning (only in active states)
	if self.State == "BuildUp" or self.State == "SustainPeak" then
		self:ProcessSpawning(dt)
	end
end

-- State Updates

function DirectorService:UpdateBuildUp(dt: number)
	if self.Intensity >= CONFIG.peakThreshold then
		self:TransitionTo("SustainPeak")
		self.StateTimer = math.random(CONFIG.sustainPeakDurationMin, CONFIG.sustainPeakDurationMax)
	end
end

function DirectorService:UpdateSustainPeak(dt: number)
	self.StateTimer -= dt
	if self.StateTimer <= 0 then
		self:TransitionTo("PeakFade")
	end
end

function DirectorService:UpdatePeakFade(dt: number)
	if self.Intensity < CONFIG.peakThreshold * 0.5 then
		self:TransitionTo("Relax")
		self.StateTimer = math.random(CONFIG.relaxDurationMin, CONFIG.relaxDurationMax)
	end
end

function DirectorService:UpdateRelax(dt: number)
	self.StateTimer -= dt
	if self.StateTimer <= 0 then
		self:TransitionTo("BuildUp")
	end
end

function DirectorService:UpdateCrescendo(dt: number)
	-- Crescendo events are handled separately
	-- This is for finale sequences
end

function DirectorService:TransitionTo(newState: DirectorState)
	local oldState = self.State
	self.State = newState
	self.OnStateChanged:Fire(oldState, newState)
	print(string.format("[Director] %s -> %s (Intensity: %.1f)", oldState, newState, self.Intensity))
end

-- Intensity System

function DirectorService:AddIntensity(event: string, value: number?)
	local gains = {
		damage = function(v: number)
			return v * 0.5
		end,
		incap = function()
			return 15
		end,
		nearbyKill = function()
			return 3
		end,
		specialSpotted = function()
			return 5
		end,
		teammateDowned = function()
			return 10
		end,
	}

	local gainFunc = gains[event]
	if gainFunc then
		local gain = gainFunc(value or 0)
		self.Intensity = math.min(100, self.Intensity + gain)
		self.OnIntensityChanged:Fire(self.Intensity)
	end
end

function DirectorService:DecayIntensity(dt: number)
	if not self._inCombat then
		local oldIntensity = self.Intensity
		self.Intensity = math.max(0, self.Intensity - dt * CONFIG.intensityDecayRate)

		if math.abs(oldIntensity - self.Intensity) > 1 then
			self.OnIntensityChanged:Fire(self.Intensity)
		end
	end
end

function DirectorService:UpdateCombatStatus()
	-- Check if any enemies are near players
	local Services = script.Parent :: Instance
	local EntityService = require(Services:WaitForChild("EntityService") :: any)

	self._inCombat = false

	for _, entity in EntityService:Get().Entities do
		if entity.state == "Dead" then
			continue
		end

		for _, player in Players:GetPlayers() do
			local char = player.Character
			if not char then
				continue
			end

			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				continue
			end

			local rootPart = entity.rootPart :: BasePart
			local distance = (rootPart.Position - hrp.Position).Magnitude
			if distance < CONFIG.combatRadius then
				self._inCombat = true
				return
			end
		end
	end
end

-- Spawning

function DirectorService:UpdateTimers(dt: number)
	self.CommonSpawnTimer -= dt

	for specialType, timer in self.SpecialTimers do
		self.SpecialTimers[specialType] = timer - dt
	end
end

function DirectorService:ProcessSpawning(dt: number)
	-- Common infected waves
	if self.CommonSpawnTimer <= 0 then
		self:SpawnCommonWave()
		self.CommonSpawnTimer = math.random(CONFIG.commonSpawnIntervalMin, CONFIG.commonSpawnIntervalMax)
	end

	-- Special infected
	for specialType, timer in self.SpecialTimers do
		if timer <= 0 and self:CanSpawnSpecial(specialType) then
			self:SpawnSpecial(specialType)
			self.SpecialTimers[specialType] = math.random(CONFIG.specialSpawnIntervalMin, CONFIG.specialSpawnIntervalMax)
		end
	end
end

function DirectorService:SpawnCommonWave()
	-- Get services
	local Services = script.Parent :: Instance
	local EntityService = require(Services:WaitForChild("EntityService") :: any)
	local SpawnPointService = require(Services:WaitForChild("SpawnPointService") :: any)
	
	-- Get valid spawn points with 75% behind-players bias
	local spawnPositions = SpawnPointService:Get():GetValidSpawnPoints("Common", 8)
	
	print(string.format("[Director] Found %d valid spawn points", #spawnPositions))
	
	if #spawnPositions == 0 then
		warn("[Director] No valid spawn points found for common wave")
		return
	end
	
	-- Determine wave size: 5-10 zombies for BuildUp state
	local waveSize = math.min(#spawnPositions, math.random(5, 10))
	
	print(string.format("[Director] Spawning wave of %d zombies", waveSize))
	
	-- Create zombie model once
	local zombieModel = self:GetOrCreateZombieModel()
	if not zombieModel then
		warn("[Director] Failed to create zombie model")
		return
	end
	
	-- Spawn zombies at selected valid points
	for i = 1, waveSize do
		if i > #spawnPositions then
			break
		end
		
		local position = spawnPositions[i]
		local entity = EntityService:Get():SpawnEntity(zombieModel, position)
		
		if entity then
			print(string.format("[Entity] Spawned zombie #%d at position (%.1f, %.1f, %.1f)", 
				i, position.X, position.Y, position.Z))
		else
			warn(string.format("[Director] Failed to spawn zombie at position", tostring(position)))
		end
	end
end

function DirectorService:CanSpawnSpecial(specialType: string): boolean
	-- TODO: Check active special count limits
	return true
end

function DirectorService:SpawnSpecial(specialType: string)
	-- Get services
	local Services = script.Parent :: Instance
	local EntityService = require(Services:WaitForChild("EntityService") :: any)
	local SpawnPointService = require(Services:WaitForChild("SpawnPointService") :: any)
	
	-- Create special model
	local specialModel = self:GetOrCreateSpecialModel(specialType)
	if not specialModel then
		warn("[Director] Failed to create special model:", specialType)
		return
	end
	
	-- Get valid spawn points (specials use "Special" type, minimum 40 studs away)
	local spawnPositions = SpawnPointService:Get():GetValidSpawnPoints("Special", 1)
	if #spawnPositions == 0 then
		warn("[Director] No valid spawn points for special:", specialType)
		return
	end
	
	-- Use first valid position (already filtered for distance and visibility)
	local spawnPosition = spawnPositions[1]
	
	-- Use specialized spawning for Hunter
	if specialType == "Hunter" then
		local hunter = EntityService:Get():SpawnHunter(specialModel, spawnPosition)
		if hunter then
			print(string.format("[Director] Spawned Hunter at %s", tostring(spawnPosition)))
		end
		return
	end
	
	-- Special configs for other types
	local specialConfigs = {
		Smoker = { moveSpeed = 12, attackDamage = 5, detectionRadius = 45 },
		Boomer = { moveSpeed = 8, attackDamage = 1, detectionRadius = 30 },
		Tank = { moveSpeed = 10, attackDamage = 25, detectionRadius = 60 },
	}
	
	local config = specialConfigs[specialType] or {}
	
	-- Spawn the special
	local entity = EntityService:Get():SpawnEntity(specialModel, spawnPosition, config)
	if entity then
		print(string.format("[Director] Spawned %s at %s", specialType, tostring(spawnPosition)))
	end
end

-- Safe Room

function DirectorService:EnterSafeRoom()
	self:TransitionTo("SafeRoom")
	self.Intensity = 0
end

function DirectorService:ExitSafeRoom()
	self:TransitionTo("Relax")
	self.StateTimer = 10 -- Grace period
end

-- Cleanup

-- Model creation
local zombieModelCache = {} :: {[string]: Model}

function DirectorService:GetOrCreateZombieModel(): Model?
	if zombieModelCache["Common"] then
		return zombieModelCache["Common"]
	end
	
	-- Use EntityFactory to create model
	local zombie = EntityFactory.createCommon()
	zombieModelCache["Common"] = zombie
	
	print("[Director] Created common zombie model")
	return zombie
end

function DirectorService:GetOrCreateSpecialModel(specialType: string): Model?
	if zombieModelCache[specialType] then
		return zombieModelCache[specialType]
	end
	
	-- Use EntityFactory for Hunter
	if specialType == "Hunter" then
		local hunterModel = EntityFactory.createHunter()
		zombieModelCache["Hunter"] = hunterModel
		print("[Director] Created Hunter model via EntityFactory")
		return hunterModel
	end
	
	-- Create a colored variant for other specials
	local baseModel = self:GetOrCreateZombieModel()
	if not baseModel then
		return nil
	end
	
	local specialModel = baseModel:Clone()
	specialModel.Name = specialType
	
	-- Color based on type
	local colors = {
		Smoker = "Dark gray",
		Boomer = "Bright green",
		Tank = "Bright red",
	}
	
	local color = colors[specialType] or "White"
	for _, part in specialModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.BrickColor = BrickColor.new(color)
			-- Make specials larger
			if specialType == "Tank" then
				part.Size = part.Size * 1.5
			elseif specialType == "Boomer" then
				part.Size = part.Size * 1.2
			end
		end
	end
	
	-- Update humanoid stats
	local humanoid = specialModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local health = {
			Smoker = 250,
			Boomer = 50,
			Tank = 6000,
		}
		
		humanoid.MaxHealth = health[specialType] or 100
		humanoid.Health = health[specialType] or 100
	end
	
	zombieModelCache[specialType] = specialModel
	return specialModel
end

function DirectorService:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	
	-- Clean up cached models
	for _, model in zombieModelCache do
		if model then
			model:Destroy()
		end
	end
	table.clear(zombieModelCache)
end

return DirectorService
