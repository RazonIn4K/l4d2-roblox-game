--!strict
--[[
    DirectorService
    AI Director for pacing - controls intensity, spawning, and game rhythm
    Based on L4D2's pacing system: BuildUp → SustainPeak → PeakFade → Relax
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

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
	local Services = ServerScriptService.Server.Services
	local GameService = require(Services.GameService)

	-- Listen for game state changes
	GameService:Get().OnStateChanged.Event:Connect(function(oldState, newState)
		if newState == "Playing" then
			self:TransitionTo("Relax") -- Grace period at start
			self.StateTimer = 10
		elseif newState == "SafeRoom" then
			self:TransitionTo("SafeRoom")
		elseif newState == "Failed" or newState == "Victory" then
			self:TransitionTo("Idle")
		end
	end)
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
	local Services = ServerScriptService.Server.Services
	local EntityService = require(Services.EntityService)

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

			local distance = (entity.rootPart.Position - hrp.Position).Magnitude
			if distance < CONFIG.combatRadius then
				self._inCombat = true
				return
			end
		end
	end
end

-- Spawning

-- Spawn point management
local spawnPoints = {} :: {BasePart}
local lastSpawnCheck = 0
local SPAWN_CHECK_INTERVAL = 10 -- seconds between spawn point refreshes

function DirectorService:UpdateTimers(dt: number)
	self.CommonSpawnTimer -= dt

	for specialType, timer in self.SpecialTimers do
		self.SpecialTimers[specialType] = timer - dt
	end
	
	-- Periodically refresh spawn points
	lastSpawnCheck += dt
	if lastSpawnCheck >= SPAWN_CHECK_INTERVAL then
		self:FindSpawnPoints()
		lastSpawnCheck = 0
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
	-- Find valid spawn points
	local validSpawns = self:GetValidSpawnPoints()
	if #validSpawns == 0 then
		warn("[Director] No valid spawn points found")
		return
	end
	
	-- Get EntityService
	local Services = ServerScriptService.Server.Services
	local EntityService = require(Services.EntityService)
	
	-- Create zombie model if needed
	local zombieModel = self:GetOrCreateZombieModel()
	if not zombieModel then
		warn("[Director] Failed to create zombie model")
		return
	end
	
	-- Spawn wave size based on intensity
	local waveSize = math.floor(3 + (self.Intensity / 100) * 5) -- 3-8 zombies
	waveSize = math.min(waveSize, #validSpawns)
	
	-- Spawn zombies at random valid points
	for i = 1, waveSize do
		local spawnIndex = math.random(1, #validSpawns)
		local spawnPoint = validSpawns[spawnIndex]
		
		-- Remove from list to avoid multiple spawns at same point
		table.remove(validSpawns, spawnIndex)
		
		-- Spawn the entity
		local entity = EntityService:Get():SpawnEntity(zombieModel, spawnPoint.Position)
		if entity then
			print(string.format("[Director] Spawned common zombie at %s", tostring(spawnPoint.Position)))
		end
	end
end

function DirectorService:CanSpawnSpecial(specialType: string): boolean
	-- TODO: Check active special count limits
	return true
end

function DirectorService:SpawnSpecial(specialType: string)
	-- Get EntityService
	local Services = ServerScriptService.Server.Services
	local EntityService = require(Services.EntityService)
	
	-- Find valid spawn points (prefer further away for specials)
	local validSpawns = self:GetValidSpawnPoints()
	if #validSpawns == 0 then
		warn("[Director] No valid spawn points for special")
		return
	end
	
	-- Create special model
	local specialModel = self:GetOrCreateSpecialModel(specialType)
	if not specialModel then
		warn("[Director] Failed to create special model:", specialType)
		return
	end
	
	-- Spawn at furthest valid point
	local spawnPoint = validSpawns[1]
	if #validSpawns > 1 then
		-- Prefer spawn points further from players for specials
		local bestScore = -math.huge
		for _, point in validSpawns do
			local score = self:GetSpawnPointScore(point)
			if score > bestScore then
				bestScore = score
				spawnPoint = point
			end
		end
	end
	
	-- Special configs
	local specialConfigs = {
		Hunter = { moveSpeed = 20, attackDamage = 15, detectionRadius = 50 },
		Smoker = { moveSpeed = 12, attackDamage = 5, detectionRadius = 45 },
		Boomer = { moveSpeed = 8, attackDamage = 1, detectionRadius = 30 },
		Tank = { moveSpeed = 10, attackDamage = 25, detectionRadius = 60 },
	}
	
	local config = specialConfigs[specialType] or {}
	
	-- Spawn the special
	local entity = EntityService:Get():SpawnEntity(specialModel, spawnPoint.Position, config)
	if entity then
		print(string.format("[Director] Spawned %s at %s", specialType, tostring(spawnPoint.Position)))
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

-- Spawn point management
function DirectorService:FindSpawnPoints()
	spawnPoints = {}
	
	-- Look for parts named "EnemySpawn" in workspace
	for _, obj in workspace:GetDescendants() do
		if obj:IsA("BasePart") and obj.Name == "EnemySpawn" then
			table.insert(spawnPoints, obj)
		end
	end
	
	print(string.format("[Director] Found %d spawn points", #spawnPoints))
end

function DirectorService:GetValidSpawnPoints(): {BasePart}
	local validSpawns = {}
	local now = os.clock()
	
	for _, spawnPoint in spawnPoints do
		if not spawnPoint or not spawnPoint.Parent then
			continue
		end
		
		-- Check if spawn point is in player line of sight
		if not self:IsSpawnPointVisible(spawnPoint) then
			table.insert(validSpawns, spawnPoint)
		end
	end
	
	return validSpawns
end

function DirectorService:IsSpawnPointVisible(spawnPoint: BasePart): boolean
	-- Check if any player can see this spawn point
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then
			continue
		end
		
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end
		
		-- Raycast from player to spawn point
		local origin = hrp.Position
		local direction = spawnPoint.Position - origin
		local distance = direction.Magnitude
		
		-- Only check if within reasonable viewing distance
		if distance > 50 then
			continue
		end
		
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		-- Filter out players and non-solid objects
		local filterDescendants = {}
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(filterDescendants, p.Character)
			end
		end
		rayParams.FilterDescendantsInstances = filterDescendants
		
		local result = workspace:Raycast(origin, direction, rayParams)
		if result == nil then
			-- Clear line of sight
			return true
		end
	end
	
	return false
end

function DirectorService:GetSpawnPointScore(spawnPoint: BasePart): number
	-- Score spawn points based on distance from players (higher = further)
	local minDistance = math.huge
	
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then
			continue
		end
		
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end
		
		local distance = (spawnPoint.Position - hrp.Position).Magnitude
		minDistance = math.min(minDistance, distance)
	end
	
	return minDistance
end

-- Model creation
local zombieModelCache = {} :: {[string]: Model}

function DirectorService:GetOrCreateZombieModel(): Model?
	if zombieModelCache["Common"] then
		return zombieModelCache["Common"]
	end
	
	-- Create a simple zombie model
	local zombie = Instance.new("Model")
	zombie.Name = "Zombie"
	
	-- Create parts
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(1, 1, 1)
	root.Material = Enum.Material.Metal
	root.BrickColor = BrickColor.new("Dark green")
	root.Parent = zombie
	
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Material = Enum.Material.Metal
	torso.BrickColor = BrickColor.new("Dark green")
	torso.Parent = zombie
	torso.CFrame = CFrame.new(0, 0, 0)
	
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Material = Enum.Material.Metal
	head.BrickColor = BrickColor.new("Dark green")
	head.Parent = zombie
	head.CFrame = CFrame.new(0, 1.5, 0)
	
	-- Create limbs
	local limbSize = Vector3.new(1, 2, 1)
	local limbPositions = {
		{ name = "Left Arm", pos = Vector3.new(1.5, 0, 0) },
		{ name = "Right Arm", pos = Vector3.new(-1.5, 0, 0) },
		{ name = "Left Leg", pos = Vector3.new(0.5, -2, 0) },
		{ name = "Right Leg", pos = Vector3.new(-0.5, -2, 0) },
	}
	
	for _, limb in limbPositions do
		local part = Instance.new("Part")
		part.Name = limb.name
		part.Size = limbSize
		part.Material = Enum.Material.Metal
		part.BrickColor = BrickColor.new("Dark green")
		part.Parent = zombie
		part.CFrame = CFrame.new(limb.pos)
	end
	
	-- Create humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 50
	humanoid.Health = 50
	humanoid.WalkSpeed = 14
	humanoid.Parent = zombie
	
	-- Weld parts together
	local welds = {
		{ part = torso, c0 = CFrame.new(0, 0, 0) },
		{ part = head, c0 = CFrame.new(0, 1.5, 0) },
		{ part = zombie:FindFirstChild("Left Arm"), c0 = CFrame.new(1.5, 0, 0) },
		{ part = zombie:FindFirstChild("Right Arm"), c0 = CFrame.new(-1.5, 0, 0) },
		{ part = zombie:FindFirstChild("Left Leg"), c0 = CFrame.new(0.5, -2, 0) },
		{ part = zombie:FindFirstChild("Right Leg"), c0 = CFrame.new(-0.5, -2, 0) },
	}
	
	for _, weld in welds do
		if weld.part then
			local weldConstraint = Instance.new("WeldConstraint")
			weldConstraint.Part0 = root
			weldConstraint.Part1 = weld.part
			weldConstraint.Parent = root
		end
	end
	
	-- Set primary part
	zombie.PrimaryPart = root
	
	zombieModelCache["Common"] = zombie
	return zombie
end

function DirectorService:GetOrCreateSpecialModel(specialType: string): Model?
	if zombieModelCache[specialType] then
		return zombieModelCache[specialType]
	end
	
	-- Create a colored variant for specials
	local baseModel = self:GetOrCreateZombieModel()
	if not baseModel then
		return nil
	end
	
	local specialModel = baseModel:Clone()
	specialModel.Name = specialType
	
	-- Color based on type
	local colors = {
		Hunter = "Bright orange",
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
			elseif specialType == "Hunter" then
				part.Size = part.Size * 0.9
			elseif specialType == "Boomer" then
				part.Size = part.Size * 1.2
			end
		end
	end
	
	-- Update humanoid stats
	local humanoid = specialModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local health = {
			Hunter = 75,
			Smoker = 100,
			Boomer = 50,
			Tank = 200,
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
