--!strict
--[[
    SpawnPointService
    Manages spawn point discovery, validation, and selection with 75% behind-players bias
]]

local Players = game:GetService("Players")

-- Types
export type SpawnType = "Common" | "Special" | "Ambient"

-- Constants
local CONFIG = {
	minDistanceCommon = 20,
	minDistanceSpecial = 40,
	viewDistance = 50,
	spawnBiasBehind = 0.75, -- 75% spawn behind players
	refreshInterval = 10, -- seconds
}

-- Module
local SpawnPointService = {}
SpawnPointService.__index = SpawnPointService

local _instance: SpawnPointService? = nil

function SpawnPointService.new()
	if _instance then
		return _instance
	end

	local self = setmetatable({}, SpawnPointService)

	-- Cached spawn points by type
	self._spawnPoints = {
		Common = {} :: { BasePart },
		Special = {} :: { BasePart },
		Ambient = {} :: { BasePart },
	}

	-- Cache timestamp
	self._lastRefresh = 0

	-- Initial scan
	self:RefreshSpawnPoints()

	_instance = self
	return self
end

function SpawnPointService:Get(): SpawnPointService
	return SpawnPointService.new()
end

function SpawnPointService:RefreshSpawnPoints()
	-- Clear existing cache
	table.clear(self._spawnPoints.Common)
	table.clear(self._spawnPoints.Special)
	table.clear(self._spawnPoints.Ambient)

	-- Scan workspace for Parts with SpawnType attribute
	for _, obj in workspace:GetDescendants() do
		if not obj:IsA("BasePart") then
			continue
		end

		local spawnType = obj:GetAttribute("SpawnType")
		if not spawnType then
			continue
		end

		-- Validate spawn type
		if spawnType == "Common" then
			table.insert(self._spawnPoints.Common, obj)
		elseif spawnType == "Special" then
			table.insert(self._spawnPoints.Special, obj)
		elseif spawnType == "Ambient" then
			table.insert(self._spawnPoints.Ambient, obj)
		end
	end

	self._lastRefresh = os.clock()
	print(
		string.format(
			"[SpawnPointService] Found %d Common, %d Special, %d Ambient spawn points",
			#self._spawnPoints.Common,
			#self._spawnPoints.Special,
			#self._spawnPoints.Ambient
		)
	)
end

function SpawnPointService:IsPointVisible(spawnPoint: BasePart): boolean
	local position = spawnPoint.Position
	-- Check if any player can see this position
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then
			continue
		end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end

		local origin = hrp.Position
		local direction = position - origin
		local distance = direction.Magnitude

		-- Only check if within reasonable viewing distance
		if distance > CONFIG.viewDistance then
			continue
		end

		-- Raycast from player to spawn point
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		-- Filter out players and their characters
		local filterDescendants = {}
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(filterDescendants, p.Character)
			end
		end
		rayParams.FilterDescendantsInstances = filterDescendants

		local result = workspace:Raycast(origin, direction, rayParams)
		if result == nil then
			-- Clear line of sight - point is visible
			return true
		end
		if result.Instance == spawnPoint then
			-- Ray hit the spawn point itself
			return true
		end
	end

	-- No players can see this point
	return false
end

function SpawnPointService:GetAveragePlayerFacing(): Vector3
	-- Calculate average facing direction of all players
	local totalFacing = Vector3.new(0, 0, 0)
	local playerCount = 0

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then
			continue
		end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end

		-- Get facing direction from CFrame
		local facing = hrp.CFrame.LookVector
		totalFacing = totalFacing + facing
		playerCount += 1
	end

	if playerCount == 0 then
		return Vector3.new(0, 0, 1) -- Default forward
	end

	-- Normalize average facing
	return totalFacing / playerCount
end

function SpawnPointService:IsBehindPlayer(spawnPoint: BasePart, playerPosition: Vector3, playerFacing: Vector3): boolean
	-- Check if spawn point is behind player (dot product < 0)
	local toSpawn = (spawnPoint.Position - playerPosition)
	if toSpawn.Magnitude == 0 then
		return false
	end
	local normalized = toSpawn.Unit

	-- Dot product: negative means behind player
	return playerFacing:Dot(normalized) < 0
end

function SpawnPointService:GetValidSpawnPoints(spawnType: string, count: number): { Vector3 }
	-- Ensure cache is fresh
	if os.clock() - self._lastRefresh > CONFIG.refreshInterval then
		self:RefreshSpawnPoints()
	end

	-- Get spawn points of requested type
	local typePoints = self._spawnPoints[spawnType] or {}
	if #typePoints == 0 then
		warn(string.format("[SpawnPointService] No spawn points found for type: %s", spawnType))
		return {}
	end

	-- Get player positions and facing
	local playerPositions = {} :: { Vector3 }
	local playerFacings = {} :: { Vector3 }

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then
			continue
		end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end

		table.insert(playerPositions, hrp.Position)
		table.insert(playerFacings, hrp.CFrame.LookVector)
	end

	if #playerPositions == 0 then
		warn("[SpawnPointService] No valid players found")
		return {}
	end

	-- Determine minimum distance based on spawn type
	local minDistance = spawnType == "Special" and CONFIG.minDistanceSpecial or CONFIG.minDistanceCommon

	-- Filter valid spawn points
	local behindPoints = {} :: { BasePart }
	local frontPoints = {} :: { BasePart }

	for _, spawnPoint in typePoints do
		if not spawnPoint or not spawnPoint.Parent then
			continue
		end

		-- Check minimum distance from all players
		local tooClose = false
		for _, playerPos in playerPositions do
			local distance = (spawnPoint.Position - playerPos).Magnitude
			if distance < minDistance then
				tooClose = true
				break
			end
		end

		if tooClose then
			continue
		end

		-- Check line of sight
		if self:IsPointVisible(spawnPoint) then
			continue
		end

		-- Categorize by position relative to players
		local isBehind = false
		for i, playerPos in playerPositions do
			if self:IsBehindPlayer(spawnPoint, playerPos, playerFacings[i]) then
				isBehind = true
				break
			end
		end

		if isBehind then
			table.insert(behindPoints, spawnPoint)
		else
			table.insert(frontPoints, spawnPoint)
		end
	end

	-- Apply 75% behind-players bias
	local selectedPoints = {} :: { Vector3 }
	local totalNeeded = count
	local behindCount = math.floor(totalNeeded * CONFIG.spawnBiasBehind)
	local frontCount = totalNeeded - behindCount

	-- Select from behind points first (75%)
	for _ = 1, math.min(behindCount, #behindPoints) do
		local index = math.random(1, #behindPoints)
		local point = behindPoints[index]
		table.insert(selectedPoints, point.Position)
		table.remove(behindPoints, index)
	end

	-- Fill remaining from front points (25%)
	for _ = 1, math.min(frontCount, #frontPoints) do
		local index = math.random(1, #frontPoints)
		local point = frontPoints[index]
		table.insert(selectedPoints, point.Position)
		table.remove(frontPoints, index)
	end

	-- If we still need more and have points available, use any remaining valid points
	if #selectedPoints < totalNeeded then
		local remaining = {}
		for _, point in behindPoints do
			table.insert(remaining, point)
		end
		for _, point in frontPoints do
			table.insert(remaining, point)
		end

		while #selectedPoints < totalNeeded and #remaining > 0 do
			local index = math.random(1, #remaining)
			local point = remaining[index]
			table.insert(selectedPoints, point.Position)
			table.remove(remaining, index)
		end
	end

	return selectedPoints
end

function SpawnPointService:Destroy()
	table.clear(self._spawnPoints.Common)
	table.clear(self._spawnPoints.Special)
	table.clear(self._spawnPoints.Ambient)
end

return SpawnPointService
