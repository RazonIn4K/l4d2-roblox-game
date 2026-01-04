--!strict
--[[
    SafeRoomService
    Manages safe room mechanics: healing, incap reset, director pause
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Module
local SafeRoomService = {}
SafeRoomService.__index = SafeRoomService

local _instance: SafeRoomService? = nil

-- Constants
local CONFIG = {
	healToMinimum = 50, -- Heal players to at least this HP
	healRate = 5, -- HP per second while in safe room
	checkInterval = 0.5, -- How often to check for players in zone
}

function SafeRoomService.new()
	if _instance then
		return _instance
	end

	local self = setmetatable({}, SafeRoomService)

	-- State
	self.IsActive = false
	self.PlayersInside = {} :: { [Player]: boolean }
	self.SafeRoomZone = nil :: BasePart?
	self.EntryDoor = nil :: BasePart?
	self.ExitDoor = nil :: BasePart?
	self._lastZoneCheck = 0

	-- Connections
	self._connections = {} :: { RBXScriptConnection }
	self._healingConnection = nil :: RBXScriptConnection?

	_instance = self
	return self
end

function SafeRoomService:Get(): SafeRoomService
	return SafeRoomService.new()
end

function SafeRoomService:Start()
	-- Find safe room zones in workspace
	self:FindSafeRoomZones()

	-- Main update loop for zone detection
	table.insert(
		self._connections,
		RunService.Heartbeat:Connect(function(_dt)
			self:UpdateZoneDetection()
		end)
	)

	print("[SafeRoomService] Started")
end

function SafeRoomService:FindSafeRoomZones()
	-- Look for safe room zone parts in workspace
	-- First check TestEnvironment folder (created by setupWorkspace)
	local testEnv = workspace:FindFirstChild("TestEnvironment")
	if testEnv then
		-- Look for part with SafeRoomZone attribute
		for _, child in testEnv:GetDescendants() do
			if child:IsA("BasePart") and child:GetAttribute("SafeRoomZone") == true then
				self.SafeRoomZone = child
				print("[SafeRoomService] Found SafeRoomZone in TestEnvironment")
				return
			end
		end
	end
	
	-- Fallback: Look for safe room folder
	local safeRoomFolder = workspace:FindFirstChild("SafeRoom")
	if not safeRoomFolder then
		-- Try to find a part named SafeRoomZone recursively
		local zone = workspace:FindFirstChild("SafeRoomZone", true)
		if zone and zone:IsA("BasePart") then
			self.SafeRoomZone = zone
			print("[SafeRoomService] Found SafeRoomZone (recursive search)")
			return
		end
		warn("[SafeRoomService] SafeRoomZone not found! Safe room features will not work.")
		return
	end

	-- Find zone, entry door, and exit door
	self.SafeRoomZone = safeRoomFolder:FindFirstChild("Zone") :: BasePart?
	self.EntryDoor = safeRoomFolder:FindFirstChild("EntryDoor") :: BasePart?
	self.ExitDoor = safeRoomFolder:FindFirstChild("ExitDoor") :: BasePart?

	if self.SafeRoomZone then
		print("[SafeRoomService] Found safe room zone in SafeRoom folder")
	else
		warn("[SafeRoomService] SafeRoomZone not found in SafeRoom folder!")
	end
end

function SafeRoomService:UpdateZoneDetection()
	if not self.SafeRoomZone then
		return
	end

	local now = os.clock()
	if now - self._lastZoneCheck < CONFIG.checkInterval then
		return
	end
	self._lastZoneCheck = now

	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local gameService = GameService:Get()

	-- Check which players are inside the safe room zone
	local playersNowInside: { [Player]: boolean } = {}
	local allInside = true
	local aliveCount = 0

	for _, playerData in pairs(gameService.PlayerData) do
		if playerData.state == "Alive" or playerData.state == "Incapacitated" then
			aliveCount += 1

			local player = playerData.player
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")

			if hrp and self:IsPositionInZone(hrp.Position) then
				playersNowInside[player] = true

				-- Player just entered
				if not self.PlayersInside[player] then
					self:OnPlayerEnterSafeRoom(player)
				end
			else
				-- Player just left
				if self.PlayersInside[player] then
					self:OnPlayerExitSafeRoom(player)
				end
				allInside = false
			end
		end
	end

	self.PlayersInside = playersNowInside

	if aliveCount == 0 then
		if self.IsActive then
			self:DeactivateSafeRoom()
		end
		return
	end

	if allInside and not self.IsActive then
		self:ActivateSafeRoom()
	elseif not allInside and self.IsActive then
		self:DeactivateSafeRoom()
	elseif allInside and self.IsActive then
		self:CheckAllPlayersReady()
	end
end

function SafeRoomService:IsPositionInZone(position: Vector3): boolean
	if not self.SafeRoomZone then
		return false
	end

	-- Get zone bounds
	local zoneCF = self.SafeRoomZone.CFrame
	local zoneSize = self.SafeRoomZone.Size

	-- Transform position to local space
	local localPos = zoneCF:PointToObjectSpace(position)

	-- Check if within bounds
	local halfSize = zoneSize / 2
	return math.abs(localPos.X) <= halfSize.X
		and math.abs(localPos.Y) <= halfSize.Y
		and math.abs(localPos.Z) <= halfSize.Z
end

function SafeRoomService:OnPlayerEnterSafeRoom(player: Player)
	print(string.format("[SafeRoomService] %s entered safe room", player.Name))

	-- Apply immediate benefits if safe room is active
	if self.IsActive then
		self:ApplySafeRoomBenefits(player)
	end
end

function SafeRoomService:OnPlayerExitSafeRoom(player: Player)
	print(string.format("[SafeRoomService] %s exited safe room", player.Name))
end

function SafeRoomService:ActivateSafeRoom()
	if self.IsActive then
		return
	end

	self.IsActive = true
	print("[SafeRoomService] Safe room ACTIVATED")

	-- Notify GameService
	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	GameService:Get():SetState("SafeRoom")

	-- Notify DirectorService to pause spawning
	local DirectorService = require(Services:WaitForChild("DirectorService") :: any)
	DirectorService:Get():EnterSafeRoom()

	-- Apply benefits to all players currently inside
	for player in pairs(self.PlayersInside) do
		self:ApplySafeRoomBenefits(player)
	end

	-- Start healing loop
	self:StartHealingLoop()
end

function SafeRoomService:DeactivateSafeRoom()
	if not self.IsActive then
		return
	end

	self.IsActive = false
	print("[SafeRoomService] Safe room DEACTIVATED")

	-- Stop healing
	self:StopHealingLoop()

	-- Notify DirectorService to resume spawning
	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local DirectorService = require(Services:WaitForChild("DirectorService") :: any)
	DirectorService:Get():ExitSafeRoom()

	if GameService:Get().State == "SafeRoom" then
		GameService:Get():SetState("Playing")
	end
end

function SafeRoomService:ApplySafeRoomBenefits(player: Player)
	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local PlayerService = require(Services:WaitForChild("PlayerService") :: any)

	local playerData = GameService:Get().PlayerData[player]
	if not playerData then
		return
	end

	-- Revive incapacitated players
	if playerData.state == "Incapacitated" then
		PlayerService:Get():CompleteRevive(player)
		playerData.incapCount = 0
	end

	-- Reset incap count
	if playerData.incapCount > 0 then
		playerData.incapCount = 0
		print(string.format("[SafeRoomService] Reset incap count for %s", player.Name))
	end

	-- Heal to minimum if below
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health < CONFIG.healToMinimum then
			humanoid.Health = math.min(CONFIG.healToMinimum, humanoid.MaxHealth)
			playerData.health = humanoid.Health
			print(string.format("[SafeRoomService] Healed %s to %d HP", player.Name, CONFIG.healToMinimum))
		end
	end

	-- Clear pinned/grabbed state if any
	if character then
		character:SetAttribute("IsPinned", false)
		character:SetAttribute("PinnedBy", nil)
		character:SetAttribute("IsGrabbed", false)
		character:SetAttribute("GrabbedBy", nil)
	end
end

function SafeRoomService:StartHealingLoop()
	if self._healingConnection then
		return
	end

	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local PlayerService = require(Services:WaitForChild("PlayerService") :: any)
	local gameService = GameService:Get()
	local playerService = PlayerService:Get()

	self._healingConnection = RunService.Heartbeat:Connect(function(dt)
		if not self.IsActive then
			return
		end

		-- Heal players inside safe room
		for player in pairs(self.PlayersInside) do
			local playerData = gameService.PlayerData[player]
			if not playerData then
				continue
			end

			if playerData.state == "Incapacitated" then
				playerService:CompleteRevive(player)
				playerData.incapCount = 0
			end

			if playerData.state ~= "Alive" then
				continue
			end

			local character = player.Character
			if not character then
				continue
			end

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				continue
			end

			-- Heal up to max health
			if humanoid.Health < humanoid.MaxHealth then
				local healAmount = CONFIG.healRate * dt
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healAmount)
				playerData.health = humanoid.Health
			end
		end
	end)
end

function SafeRoomService:StopHealingLoop()
	if self._healingConnection then
		self._healingConnection:Disconnect()
		self._healingConnection = nil
	end
end

function SafeRoomService:CheckAllPlayersReady()
	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)

	-- Check if all alive players are in safe room
	local allInside = true
	local aliveCount = 0

	for _, playerData in pairs(GameService:Get().PlayerData) do
		if playerData.state == "Alive" or playerData.state == "Incapacitated" then
			aliveCount += 1
			if not self.PlayersInside[playerData.player] then
				allInside = false
			end
		end
	end

	-- If all players are inside, they can proceed
	if allInside and aliveCount > 0 then
		-- All players are in the safe room - ready to proceed
		-- Future: Unlock exit door, show "Ready to proceed" UI
		print("[SafeRoomService] All players in safe room - ready to proceed")
	end
end

function SafeRoomService:BroadcastSafeRoomState(isActive: boolean)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		return
	end

	local gameStateRemote = remotes:FindFirstChild("GameState")
	if gameStateRemote then
		if isActive then
			gameStateRemote:FireAllClients("SafeRoom", { active = true })
		end
	end
end

-- Manually trigger safe room (for testing or scripted events)
function SafeRoomService:TriggerSafeRoom()
	-- Apply benefits to all players
	for _, player in Players:GetPlayers() do
		self:ApplySafeRoomBenefits(player)
	end

	self:ActivateSafeRoom()
end

-- Force exit safe room state
function SafeRoomService:ForceExit()
	self:DeactivateSafeRoom()

	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	GameService:Get():SetState("Playing")
end

function SafeRoomService:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)

	self:StopHealingLoop()
end

return SafeRoomService
