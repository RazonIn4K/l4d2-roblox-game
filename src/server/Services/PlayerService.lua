--!strict
--[[
    PlayerService
    Manages player health, incapacitation, and revival mechanics
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Constants
local CONFIG = {
	maxHealth = 100,
	incapHealth = 300,
	incapBleedoutRate = 1,
	reviveTime = 5,
	reviveHealth = 30,
	maxIncapsBeforeDeath = 2,
	reviveRange = 5,
}

-- Types
export type ReviveData = {
	rescuer: Player,
	progress: number,
	startTime: number,
}

-- Module
local PlayerService = {}
PlayerService.__index = PlayerService

local _instance: PlayerService? = nil

function PlayerService.new()
	if _instance then
		return _instance
	end

	local self = setmetatable({}, PlayerService)

	-- Active revives
	self.ActiveRevives = {} :: { [Player]: ReviveData }

	-- Bleedout tracking
	self.BleedoutTasks = {} :: { [Player]: thread }

	-- Connections
	self._connections = {} :: { RBXScriptConnection }

	_instance = self
	return self
end

function PlayerService:Get(): PlayerService
	return PlayerService.new()
end

function PlayerService:Start()
	-- Setup remote handlers
	self:SetupRemotes()

	-- Update loop for revive progress
	table.insert(
		self._connections,
		RunService.Heartbeat:Connect(function(dt)
			self:Update(dt)
		end)
	)

	print("[PlayerService] Started")
end

function PlayerService:SetupRemotes()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	-- Rate limiting for revive requests
	local REVIVE_COOLDOWN = 0.25 -- seconds between revive requests
	local lastReviveRequest: { [Player]: number } = {}

	-- Cleanup on player leave
	table.insert(
		self._connections,
		Players.PlayerRemoving:Connect(function(player)
			lastReviveRequest[player] = nil
		end)
	)

	local reviveRemote = remotes:WaitForChild("RevivePlayer")
	reviveRemote.OnServerEvent:Connect(function(player, targetPlayer, action)
		-- Rate limit check
		local now = os.clock()
		local lastRequest = lastReviveRequest[player] or 0
		if now - lastRequest < REVIVE_COOLDOWN then
			return -- Silent reject - too fast
		end
		lastReviveRequest[player] = now

		if typeof(action) ~= "string" then
			return
		end
		if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then
			return
		end
		if targetPlayer == player then
			return
		end

		if action == "start" then
			self:StartRevive(player, targetPlayer)
		elseif action == "cancel" then
			self:CancelRevive(targetPlayer)
		end
	end)
end

function PlayerService:Update(dt: number)
	-- Update active revives
	for incappedPlayer, reviveData in self.ActiveRevives do
		self:UpdateRevive(incappedPlayer, reviveData, dt)
	end
end

function PlayerService:IncapacitatePlayer(player: Player)
	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local gameService = GameService:Get()

	local data = gameService.PlayerData[player]
	if not data then
		return
	end

	data.incapCount += 1

	-- Check for death
	if data.incapCount > CONFIG.maxIncapsBeforeDeath then
		self:KillPlayer(player)
		return
	end

	data.state = "Incapacitated"
	data.health = CONFIG.incapHealth

	-- Apply incap effects
	local char = player.Character
	if char then
		char:SetAttribute("IsIncapacitated", true)

		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 3 -- Slow crawl
			humanoid.JumpPower = 0
			humanoid.Health = CONFIG.incapHealth
			humanoid.MaxHealth = CONFIG.incapHealth
		end
	end

	-- Start bleedout
	self:StartBleedout(player)

	-- Notify
	gameService.OnPlayerStateChanged:Fire(player, "Incapacitated")
	print("[PlayerService] Player incapacitated:", player.Name)
end

function PlayerService:StartBleedout(player: Player)
	-- Cancel existing bleedout if any
	if self.BleedoutTasks[player] then
		task.cancel(self.BleedoutTasks[player])
	end

	self.BleedoutTasks[player] = task.spawn(function()
		local Services = script.Parent :: Instance
		local GameService = require(Services:WaitForChild("GameService") :: any)
		local gameService = GameService:Get()

		while true do
			local data = gameService.PlayerData[player]
			if not data or data.state ~= "Incapacitated" then
				break
			end

			data.health -= CONFIG.incapBleedoutRate

			-- Update humanoid
			local char = player.Character
			if char then
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.Health = data.health
				end
			end

			if data.health <= 0 then
				self:KillPlayer(player)
				break
			end

			task.wait(1)
		end

		self.BleedoutTasks[player] = nil
	end)
end

function PlayerService:StartRevive(rescuer: Player, incapped: Player)
	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local gameService = GameService:Get()

	local rescuerData = gameService.PlayerData[rescuer]
	local incappedData = gameService.PlayerData[incapped]

	if not rescuerData or not incappedData then
		return
	end

	if incappedData.state ~= "Incapacitated" then
		return
	end

	if rescuerData.state ~= "Alive" then
		return
	end

	-- Check distance
	local rescuerChar = rescuer.Character
	local incappedChar = incapped.Character
	if not rescuerChar or not incappedChar then
		return
	end

	local rescuerHRP = rescuerChar:FindFirstChild("HumanoidRootPart")
	local incappedHRP = incappedChar:FindFirstChild("HumanoidRootPart")
	if not rescuerHRP or not incappedHRP then
		return
	end

	local distance = (rescuerHRP.Position - incappedHRP.Position).Magnitude
	if distance > CONFIG.reviveRange then
		return
	end

	-- Start revive
	self.ActiveRevives[incapped] = {
		rescuer = rescuer,
		progress = 0,
		startTime = os.clock(),
	}

	print("[PlayerService] Revive started:", rescuer.Name, "->", incapped.Name)
end

function PlayerService:UpdateRevive(incapped: Player, reviveData: ReviveData, dt: number)
	local rescuer = reviveData.rescuer

	-- Validate both players still valid
	local rescuerChar = rescuer.Character
	local incappedChar = incapped.Character
	if not rescuerChar or not incappedChar then
		self:CancelRevive(incapped)
		return
	end

	-- Check still in range
	local rescuerHRP = rescuerChar:FindFirstChild("HumanoidRootPart")
	local incappedHRP = incappedChar:FindFirstChild("HumanoidRootPart")
	if not rescuerHRP or not incappedHRP then
		self:CancelRevive(incapped)
		return
	end

	local distance = (rescuerHRP.Position - incappedHRP.Position).Magnitude
	if distance > CONFIG.reviveRange + 1 then -- Small tolerance
		self:CancelRevive(incapped)
		return
	end

	-- Progress
	reviveData.progress += dt / CONFIG.reviveTime

	if reviveData.progress >= 1 then
		self:CompleteRevive(incapped)
	end
end

function PlayerService:CancelRevive(incapped: Player)
	self.ActiveRevives[incapped] = nil
	print("[PlayerService] Revive cancelled for:", incapped.Name)
end

function PlayerService:CompleteRevive(player: Player)
	self.ActiveRevives[player] = nil

	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local gameService = GameService:Get()

	local data = gameService.PlayerData[player]
	if not data then
		return
	end

	-- Stop bleedout
	if self.BleedoutTasks[player] then
		task.cancel(self.BleedoutTasks[player])
		self.BleedoutTasks[player] = nil
	end

	-- Restore player
	data.state = "Alive"
	data.health = CONFIG.reviveHealth

	local char = player.Character
	if char then
		char:SetAttribute("IsIncapacitated", false)

		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 16
			humanoid.JumpPower = 50
			humanoid.MaxHealth = CONFIG.maxHealth
			humanoid.Health = CONFIG.reviveHealth
		end
	end

	gameService.OnPlayerStateChanged:Fire(player, "Alive")
	print("[PlayerService] Player revived:", player.Name)
end

function PlayerService:KillPlayer(player: Player)
	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local gameService = GameService:Get()

	local data = gameService.PlayerData[player]
	if not data then
		return
	end

	-- Stop bleedout
	if self.BleedoutTasks[player] then
		task.cancel(self.BleedoutTasks[player])
		self.BleedoutTasks[player] = nil
	end

	-- Cancel any active revive
	self:CancelRevive(player)

	data.state = "Dead"
	data.health = 0

	local char = player.Character
	if char then
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end

	gameService.OnPlayerStateChanged:Fire(player, "Dead")
	print("[PlayerService] Player died:", player.Name)
end

function PlayerService:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)

	for _, bleedoutTask in self.BleedoutTasks do
		task.cancel(bleedoutTask)
	end
	table.clear(self.BleedoutTasks)
end

-- ============================================
-- PINNED STATE MANAGEMENT
-- ============================================

-- Track when a player gets pinned by a Hunter
function PlayerService:OnPlayerPinned(player: Player, attackerEntityId: string)
	local char = player.Character
	if not char then
		return
	end

	-- Set pinned attributes
	char:SetAttribute("IsPinned", true)
	char:SetAttribute("PinnedBy", attackerEntityId)

	-- Track in service
	if not self.PinnedPlayers then
		self.PinnedPlayers = {}
	end
	self.PinnedPlayers[player] = {
		entityId = attackerEntityId,
		pinnedAt = os.clock(),
	}

	print(string.format("[PlayerService] %s pinned by entity %s", player.Name, attackerEntityId))
end

-- Get list of all currently pinned players
function PlayerService:GetPinnedPlayers(): { Player }
	local pinned = {}

	for _, player in Players:GetPlayers() do
		if self:IsPlayerPinned(player) or self:IsPlayerGrabbed(player) then
			table.insert(pinned, player)
		end
	end

	return pinned
end

-- Check if a player is pinned
function PlayerService:IsPlayerPinned(player: Player): boolean
	local char = player.Character
	if not char then
		return false
	end

	return char:GetAttribute("IsPinned") == true
end

-- Check if a player is grabbed (Smoker)
function PlayerService:IsPlayerGrabbed(player: Player): boolean
	local char = player.Character
	if not char then
		return false
	end

	return char:GetAttribute("IsGrabbed") == true
end

-- Get the entity ID that is pinning a player
function PlayerService:GetPinningEntityId(player: Player): string?
	local char = player.Character
	if not char then
		return nil
	end

	local pinnedBy = char:GetAttribute("PinnedBy")
	if pinnedBy then
		return tostring(pinnedBy)
	end
	return nil
end

-- Get the entity ID that is grabbing a player (Smoker)
function PlayerService:GetGrabbingEntityId(player: Player): string?
	local char = player.Character
	if not char then
		return nil
	end

	local grabbedBy = char:GetAttribute("GrabbedBy")
	if grabbedBy then
		return tostring(grabbedBy)
	end
	return nil
end

-- ============================================
-- RESCUE SYSTEM
-- ============================================

local RESCUE_RANGE = 4 -- studs
local RESCUE_SHOVE_TIME = 0.5 -- seconds
local RESCUE_DAMAGE_TO_HUNTER = 50

-- Validate and perform rescue from pin
function PlayerService:RescueFromPin(rescuer: Player, pinnedPlayer: Player): (boolean, string)
	-- Validate rescuer exists and is alive
	local rescuerChar = rescuer.Character
	if not rescuerChar then
		return false, "Rescuer has no character"
	end

	local rescuerHumanoid = rescuerChar:FindFirstChildOfClass("Humanoid")
	if not rescuerHumanoid or rescuerHumanoid.Health <= 0 then
		return false, "Rescuer is dead"
	end

	-- Check rescuer state (must be Alive, not incapped)
	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local gameService = GameService:Get()

	local rescuerData = gameService.PlayerData[rescuer]
	if not rescuerData or rescuerData.state ~= "Alive" then
		return false, "Rescuer is not in Alive state"
	end

	-- Validate pinned player
	local pinnedChar = pinnedPlayer.Character
	if not pinnedChar then
		return false, "Pinned player has no character"
	end

	if not self:IsPlayerPinned(pinnedPlayer) and not self:IsPlayerGrabbed(pinnedPlayer) then
		return false, "Player is not pinned or grabbed"
	end

	-- Check distance
	local rescuerHrp = rescuerChar:FindFirstChild("HumanoidRootPart")
	local pinnedHrp = pinnedChar:FindFirstChild("HumanoidRootPart")
	if not rescuerHrp or not pinnedHrp then
		return false, "Missing HumanoidRootPart"
	end

	local distance = (rescuerHrp.Position - pinnedHrp.Position).Magnitude
	if distance > RESCUE_RANGE then
		return false, string.format("Too far (%.1f studs, need %.1f)", distance, RESCUE_RANGE)
	end

	-- Perform melee shove (0.5s action)
	print(string.format("[PlayerService] %s performing rescue shove on Hunter...", rescuer.Name))
	task.wait(RESCUE_SHOVE_TIME)

	local EntityService = require(Services:WaitForChild("EntityService") :: any)

	-- Get the Hunter entity and damage/stagger it
	local pinnedBy = self:GetPinningEntityId(pinnedPlayer)
	if pinnedBy then
		local hunter = EntityService:Get():GetEntityById(pinnedBy)

		if hunter then
			if hunter.TakeDamage then
				hunter:TakeDamage(RESCUE_DAMAGE_TO_HUNTER, rescuer)
				print(string.format("[PlayerService] Hunter took %d damage from rescue shove", RESCUE_DAMAGE_TO_HUNTER))
			end

			if hunter.TransitionTo then
				hunter:TransitionTo("Stagger")
			end

			if hunter.Rescue then
				hunter:Rescue()
			end
		end

		self:ClearPinnedState(pinnedPlayer)
		print(string.format("[PlayerService] %s successfully rescued %s!", rescuer.Name, pinnedPlayer.Name))
		return true, "Rescue successful"
	end

	-- Smoker rescue
	local grabbedBy = self:GetGrabbingEntityId(pinnedPlayer)
	if grabbedBy then
		local smoker = EntityService:Get():GetEntityById(grabbedBy)
		if smoker and smoker.Rescue then
			smoker:Rescue()
		end

		print(string.format("[PlayerService] %s successfully rescued %s!", rescuer.Name, pinnedPlayer.Name))
		return true, "Rescue successful"
	end

	return false, "Rescue failed"
end

-- Clear pinned state from a player
function PlayerService:ClearPinnedState(player: Player)
	local char = player.Character
	if not char then
		return
	end

	-- Clear attributes
	char:SetAttribute("IsPinned", false)
	char:SetAttribute("PinnedBy", nil)

	-- Restore movement
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
	end

	-- Remove from tracking
	if self.PinnedPlayers then
		self.PinnedPlayers[player] = nil
	end

	print(string.format("[PlayerService] Cleared pinned state for %s", player.Name))
end

-- Legacy function for compatibility
function PlayerService:RescuePinnedPlayer(rescuer: Player, victim: Player): boolean
	local success, message = self:RescueFromPin(rescuer, victim)
	if not success then
		print(string.format("[PlayerService] Rescue failed: %s", message))
	end
	return success
end

-- ============================================
-- DAMAGE FEEDBACK
-- ============================================

-- Send damage feedback to client with source position for directional indicators
function PlayerService:SendDamageEvent(player: Player, damage: number, sourcePosition: Vector3?)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		return
	end

	local damageEvent = remotes:FindFirstChild("DamageEvent")
	if damageEvent then
		damageEvent:FireClient(player, damage, sourcePosition)
	end
end

-- Apply damage to player from an entity (with source tracking for feedback)
function PlayerService:DamagePlayer(player: Player, damage: number, sourcePosition: Vector3?)
	local char = player.Character
	if not char then
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Apply damage
	humanoid:TakeDamage(damage)

	-- Send damage event to client for visual feedback
	self:SendDamageEvent(player, damage, sourcePosition)

	-- Update GameService player data
	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local playerData = GameService:Get().PlayerData[player]
	if playerData then
		playerData.health = humanoid.Health
	end

	print(string.format("[PlayerService] %s took %.0f damage", player.Name, damage))
end

return PlayerService
