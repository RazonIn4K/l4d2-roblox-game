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

	local reviveRemote = remotes:WaitForChild("RevivePlayer")
	reviveRemote.OnServerEvent:Connect(function(player, targetPlayer, action)
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
	local Services = ServerScriptService.Server.Services
	local GameService = require(Services.GameService)
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
		local Services = ServerScriptService.Server.Services
		local GameService = require(Services.GameService)
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
	local Services = ServerScriptService.Server.Services
	local GameService = require(Services.GameService)
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

	local Services = ServerScriptService.Server.Services
	local GameService = require(Services.GameService)
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
	local Services = ServerScriptService.Server.Services
	local GameService = require(Services.GameService)
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

-- Rescue a player who is pinned by a Hunter
function PlayerService:RescuePinnedPlayer(rescuer: Player, victim: Player): boolean
	-- Check if rescuer is valid
	local rescuerChar = rescuer.Character
	if not rescuerChar then return false end
	
	local rescuerHumanoid = rescuerChar:FindFirstChildOfClass("Humanoid")
	if not rescuerHumanoid or rescuerHumanoid.Health <= 0 then return false end
	
	-- Check if victim is pinned
	local victimChar = victim.Character
	if not victimChar then return false end
	
	local isPinned = victimChar:GetAttribute("IsPinned")
	if not isPinned then return false end
	
	-- Check distance
	local rescuerHrp = rescuerChar:FindFirstChild("HumanoidRootPart")
	local victimHrp = victimChar:FindFirstChild("HumanoidRootPart")
	if not rescuerHrp or not victimHrp then return false end
	
	local distance = (rescuerHrp.Position - victimHrp.Position).Magnitude
	if distance > CONFIG.reviveRange then
		print(string.format("[PlayerService] %s too far to rescue %s (%.1f studs)", 
			rescuer.Name, victim.Name, distance))
		return false
	end
	
	-- Get EntityService and rescue
	local Services = script.Parent :: Instance
	local EntityService = require(Services:WaitForChild("EntityService") :: any)
	
	local success = EntityService:Get():RescuePinnedPlayer(rescuer, victim)
	if success then
		print(string.format("[PlayerService] %s rescued %s from Hunter!", rescuer.Name, victim.Name))
	end
	
	return success
end

-- Check if a player is pinned
function PlayerService:IsPlayerPinned(player: Player): boolean
	local char = player.Character
	if not char then return false end
	
	return char:GetAttribute("IsPinned") == true
end

-- Get the entity ID that is pinning a player
function PlayerService:GetPinningEntityId(player: Player): string?
	local char = player.Character
	if not char then return nil end
	
	return char:GetAttribute("PinnedBy")
end

return PlayerService
