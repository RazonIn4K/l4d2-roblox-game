--!strict
--[[
    AmbientSoundController
    Creates horror atmosphere through ambient sounds, distant infected noises,
    and dynamic audio based on game state
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- Constants
local AMBIENT_SOUNDS = {
	-- Distant infected sounds
	distantScream = {
		ids = { "rbxassetid://5152765415", "rbxassetid://5152765578" },
		volume = 0.3,
		minInterval = 30,
		maxInterval = 60,
	},
	distantGrowl = {
		ids = { "rbxassetid://5153382847", "rbxassetid://5153383038" },
		volume = 0.2,
		minInterval = 20,
		maxInterval = 45,
	},
	-- Environmental sounds
	wind = {
		ids = { "rbxassetid://5153053953" },
		volume = 0.15,
		minInterval = 45,
		maxInterval = 90,
	},
	metalCreak = {
		ids = { "rbxassetid://5153072658" },
		volume = 0.25,
		minInterval = 40,
		maxInterval = 80,
	},
	-- Horror stingers (played when intensity changes)
	horrorSting = {
		ids = { "rbxassetid://5153385438", "rbxassetid://5153385612" },
		volume = 0.4,
		minInterval = 60,
		maxInterval = 120,
	},
}

-- Heartbeat sound for low health
local HEARTBEAT_THRESHOLD = 0.25
local HEARTBEAT_SOUND_ID = "rbxassetid://142082166"

-- Module
local AmbientSoundController = {}
AmbientSoundController.__index = AmbientSoundController

local _instance = nil

function AmbientSoundController.new()
	if _instance then
		return _instance
	end

	local self = setmetatable({}, AmbientSoundController)

	-- State
	self.Enabled = true
	self.CurrentGameState = "Lobby"
	self.LastSoundTimes = {} :: { [string]: number }
	self.HeartbeatSound = nil
	self.IsHeartbeatPlaying = false

	-- Connections
	self._connections = {} :: { RBXScriptConnection }

	_instance = self
	return self
end

function AmbientSoundController:Get()
	return AmbientSoundController.new()
end

function AmbientSoundController:Start()
	-- Initialize timers
	for soundType, _ in AMBIENT_SOUNDS do
		self.LastSoundTimes[soundType] = os.clock()
	end

	-- Create heartbeat sound
	self:CreateHeartbeatSound()

	-- Main update loop
	table.insert(
		self._connections,
		RunService.Heartbeat:Connect(function(dt)
			self:Update(dt)
		end)
	)

	-- Listen for game state changes
	self:ConnectGameStateEvents()

	-- Connect to health for heartbeat
	self:ConnectHealthEvents()

	print("[AmbientSoundController] Started - Horror atmosphere active")
end

function AmbientSoundController:CreateHeartbeatSound()
	local heartbeat = Instance.new("Sound")
	heartbeat.Name = "Heartbeat"
	heartbeat.SoundId = HEARTBEAT_SOUND_ID
	heartbeat.Volume = 0.6
	heartbeat.Looped = true
	heartbeat.Parent = SoundService
	self.HeartbeatSound = heartbeat
end

function AmbientSoundController:Update(_dt: number)
	if not self.Enabled then
		return
	end

	-- Only play ambient sounds during active gameplay
	if self.CurrentGameState ~= "Playing" and self.CurrentGameState ~= "SafeRoom" then
		return
	end

	local now = os.clock()

	-- Check each ambient sound type
	for soundType, config in AMBIENT_SOUNDS do
		local lastTime = self.LastSoundTimes[soundType] or 0
		local interval = math.random(config.minInterval, config.maxInterval)

		if now - lastTime >= interval then
			self:PlayAmbientSound(soundType, config)
			self.LastSoundTimes[soundType] = now
		end
	end
end

function AmbientSoundController:PlayAmbientSound(
	soundType: string,
	config: {
		ids: { string },
		volume: number,
		minInterval: number,
		maxInterval: number,
	}
)
	-- Skip horror stings in SafeRoom
	if soundType == "horrorSting" and self.CurrentGameState == "SafeRoom" then
		return
	end

	-- Pick random sound from list
	local soundId = config.ids[math.random(1, #config.ids)]

	-- Create and play sound
	local sound = Instance.new("Sound")
	sound.Name = soundType
	sound.SoundId = soundId
	sound.Volume = config.volume * (0.8 + math.random() * 0.4) -- Slight volume variation
	sound.PlaybackSpeed = 0.9 + math.random() * 0.2 -- Slight pitch variation
	sound.Parent = SoundService

	sound:Play()
	Debris:AddItem(sound, 10)
end

function AmbientSoundController:PlaySpecialSound(soundType: string)
	local config = AMBIENT_SOUNDS[soundType]
	if config then
		self:PlayAmbientSound(soundType, config)
	end
end

function AmbientSoundController:ConnectGameStateEvents()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local gameStateRemote = remotes:WaitForChild("GameState")

	table.insert(
		self._connections,
		gameStateRemote.OnClientEvent:Connect(function(stateType, _data)
			-- Handle game state changes
			if
				stateType == "Playing"
				or stateType == "SafeRoom"
				or stateType == "Lobby"
				or stateType == "Victory"
				or stateType == "Failed"
			then
				self.CurrentGameState = stateType
			elseif stateType == "DirectorState" then
				-- Play horror sting when entering BuildUp
				if _data == "BuildUp" then
					self:PlaySpecialSound("horrorSting")
				end
			end
		end)
	)
end

function AmbientSoundController:ConnectHealthEvents()
	local function setupCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid

		table.insert(
			self._connections,
			humanoid.HealthChanged:Connect(function(health)
				local healthPercent = health / humanoid.MaxHealth
				self:UpdateHeartbeat(healthPercent)
			end)
		)

		-- Initial check
		self:UpdateHeartbeat(humanoid.Health / humanoid.MaxHealth)
	end

	-- Connect to current character
	if player.Character then
		setupCharacter(player.Character)
	end

	-- Connect to future characters
	table.insert(
		self._connections,
		player.CharacterAdded:Connect(function(character)
			setupCharacter(character)
		end)
	)
end

function AmbientSoundController:UpdateHeartbeat(healthPercent: number)
	if not self.HeartbeatSound then
		return
	end

	if healthPercent <= HEARTBEAT_THRESHOLD and healthPercent > 0 then
		if not self.IsHeartbeatPlaying then
			self.HeartbeatSound:Play()
			self.IsHeartbeatPlaying = true
		end

		-- Speed up heartbeat as health gets lower
		local intensity = 1 - (healthPercent / HEARTBEAT_THRESHOLD)
		self.HeartbeatSound.PlaybackSpeed = 1 + intensity * 0.5
		self.HeartbeatSound.Volume = 0.4 + intensity * 0.4
	else
		if self.IsHeartbeatPlaying then
			self.HeartbeatSound:Stop()
			self.IsHeartbeatPlaying = false
		end
	end
end

function AmbientSoundController:SetEnabled(enabled: boolean)
	self.Enabled = enabled

	if not enabled and self.IsHeartbeatPlaying then
		self.HeartbeatSound:Stop()
		self.IsHeartbeatPlaying = false
	end
end

function AmbientSoundController:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)

	if self.HeartbeatSound then
		self.HeartbeatSound:Destroy()
	end
end

return AmbientSoundController
