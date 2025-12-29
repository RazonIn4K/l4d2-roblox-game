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
	-- TODO: Implement common wave spawning
	-- This will call EntityService to spawn zombies at valid spawn points
	print("[Director] Spawning common wave")
end

function DirectorService:CanSpawnSpecial(specialType: string): boolean
	-- TODO: Check active special count limits
	return true
end

function DirectorService:SpawnSpecial(specialType: string)
	-- TODO: Implement special infected spawning
	print("[Director] Spawning special:", specialType)
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

function DirectorService:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

return DirectorService
