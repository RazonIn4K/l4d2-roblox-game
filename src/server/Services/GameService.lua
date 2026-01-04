--!strict
--[[
    GameService
    Manages game state, rounds, and player teams
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Types
export type GameState = "Lobby" | "Loading" | "Playing" | "SafeRoom" | "Finale" | "Victory" | "Failed"
export type PlayerState = "Alive" | "Incapacitated" | "Dead" | "Spectating"

export type PlayerData = {
	player: Player,
	state: PlayerState,
	health: number,
	maxHealth: number,
	incapCount: number,
	reviveProgress: number,
}

-- Constants
local MAX_PLAYERS = 4
local MIN_PLAYERS_TO_START = 1
local MAX_HEALTH = 100

-- Module
local GameService = {}
GameService.__index = GameService

local _instance: GameService? = nil

function GameService.new()
	if _instance then
		return _instance
	end

	local self = setmetatable({}, GameService)

	-- State
	self.State = "Lobby" :: GameState
	self.PlayerData = {} :: { [Player]: PlayerData }
	self.CurrentCheckpoint = nil :: string?
	self.ChapterNumber = 1

	-- Connections
	self._connections = {} :: { RBXScriptConnection }

	-- Events
	self.OnStateChanged = Instance.new("BindableEvent")
	self.OnPlayerStateChanged = Instance.new("BindableEvent")

	_instance = self
	return self
end

function GameService:Get(): GameService
	return GameService.new()
end

function GameService:Start()
	-- Player connections
	table.insert(
		self._connections,
		Players.PlayerAdded:Connect(function(player)
			self:OnPlayerAdded(player)
		end)
	)

	table.insert(
		self._connections,
		Players.PlayerRemoving:Connect(function(player)
			self:OnPlayerRemoving(player)
		end)
	)

	-- Handle existing players
	for _, player in Players:GetPlayers() do
		self:OnPlayerAdded(player)
	end

	print("[GameService] Started")
end

function GameService:OnPlayerAdded(player: Player)
	if self:GetPlayerCount() >= MAX_PLAYERS then
		player:Kick("Server is full")
		return
	end

	self.PlayerData[player] = {
		player = player,
		state = "Alive",
		health = MAX_HEALTH,
		maxHealth = MAX_HEALTH,
		incapCount = 0,
		reviveProgress = 0,
	}

	-- Wait for character
	player.CharacterAdded:Connect(function(character)
		self:OnCharacterAdded(player, character)
	end)

	if player.Character then
		self:OnCharacterAdded(player, player.Character)
	end

	print("[GameService] Player joined:", player.Name)
end

function GameService:OnCharacterAdded(player: Player, character: Model)
	local data = self.PlayerData[player]
	if not data then
		return
	end

	-- Setup character
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.MaxHealth = data.maxHealth
	humanoid.Health = data.health

	-- Set collision group
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end

	-- Incapacitation check (intercepts lethal damage)
	humanoid.HealthChanged:Connect(function(health)
		local currentData = self.PlayerData[player]
		if not currentData then
			return
		end
		if currentData.state ~= "Alive" then
			return
		end
		if health > 0 then
			return
		end

		local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
		local PlayerService = require(Services:WaitForChild("PlayerService") :: any)
		PlayerService:Get():IncapacitatePlayer(player)
	end)

	-- Death handler
	humanoid.Died:Connect(function()
		self:OnPlayerDied(player)
	end)
end

function GameService:OnPlayerRemoving(player: Player)
	self.PlayerData[player] = nil
	print("[GameService] Player left:", player.Name)

	-- Check if game should end
	if self.State == "Playing" and self:GetAlivePlayerCount() == 0 then
		self:SetState("Failed")
	end
end

function GameService:OnPlayerDied(player: Player)
	local data = self.PlayerData[player]
	if not data then
		return
	end
	if data.state == "Incapacitated" or data.state == "Dead" then
		return
	end

	data.state = "Dead"
	self.OnPlayerStateChanged:Fire(player, "Dead")

	-- Check team wipe
	if self:IsTeamWiped() then
		self:SetState("Failed")
	end
end

function GameService:SetState(newState: GameState)
	local oldState = self.State
	self.State = newState
	self.OnStateChanged:Fire(oldState, newState)
	print("[GameService] State:", oldState, "->", newState)

	-- Broadcast to all clients for UI notifications
	self:BroadcastGameState(newState)
end

function GameService:BroadcastGameState(state: GameState)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		return
	end

	local gameStateRemote = remotes:FindFirstChild("GameState")
	if not gameStateRemote then
		return
	end

	-- Fire to all clients
	gameStateRemote:FireAllClients(state)
	print("[GameService] Broadcasted game state:", state)
end

function GameService:GetPlayerCount(): number
	local count = 0
	for _ in self.PlayerData do
		count += 1
	end
	return count
end

function GameService:GetAlivePlayerCount(): number
	local count = 0
	for _, data in self.PlayerData do
		if data.state == "Alive" or data.state == "Incapacitated" then
			count += 1
		end
	end
	return count
end

function GameService:IsTeamWiped(): boolean
	for _, data in self.PlayerData do
		if data.state == "Alive" then
			return false
		end
	end
	return true
end

function GameService:GetTeamHealth(): (number, number)
	local current, max = 0, 0
	for _, data in self.PlayerData do
		if data.state ~= "Dead" and data.state ~= "Spectating" then
			current += data.health
			max += data.maxHealth
		end
	end
	return current, max
end

function GameService:StartGame()
	if self.State ~= "Lobby" then
		return
	end

	if self:GetPlayerCount() < MIN_PLAYERS_TO_START then
		warn("[GameService] Not enough players to start")
		return
	end

	self:SetState("Loading")

	-- Reset all players
	for _, data in self.PlayerData do
		data.state = "Alive"
		data.health = data.maxHealth
		data.incapCount = 0
	end

	-- Transition to playing
	task.delay(2, function()
		self:SetState("Playing")
	end)
end

function GameService:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

return GameService
