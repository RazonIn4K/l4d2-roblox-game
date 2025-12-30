--!strict
--[[
    EntityService
    CRITICAL: Manages ALL NPCs in a single script
    Never create individual scripts per enemy - this is the #1 performance requirement
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Import entity types (lazy loaded to avoid circular dependency)
local Hunter = nil
local Smoker = nil
local Boomer = nil
local Tank = nil
local Witch = nil

-- Types
export type EntityState = "Idle" | "Patrol" | "Chase" | "Attack" | "Stagger" | "Dead"

export type Entity = {
	id: string,
	model: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	state: EntityState,
	target: Player?,
	health: number,
	maxHealth: number,
	config: EntityConfig,
	_lastUpdate: number,
	_lastAttack: number,
}

export type EntityConfig = {
	detectionRadius: number,
	attackRange: number,
	attackDamage: number,
	attackCooldown: number,
	moveSpeed: number,
	updateRate: number,
}

export type EntityConfigOverrides = {
	detectionRadius: number?,
	attackRange: number?,
	attackDamage: number?,
	attackCooldown: number?,
	moveSpeed: number?,
	updateRate: number?,
}

-- Constants
local DEFAULT_CONFIG: EntityConfig = {
	detectionRadius = 40,
	attackRange = 3,
	attackDamage = 10,
	attackCooldown = 1,
	moveSpeed = 14,
	updateRate = 0.0625, -- 16 Hz
}

local function mergeConfig(overrides: EntityConfigOverrides?): EntityConfig
	local merged = table.clone(DEFAULT_CONFIG)
	if overrides then
		for key, value in overrides do
			merged[key] = value
		end
	end
	return merged
end

-- Module
local EntityService = {}
EntityService.__index = EntityService

local _instance: EntityService? = nil

function EntityService.new()
	if _instance then
		return _instance
	end

	local self = setmetatable({}, EntityService)

	-- Entity storage
	self.Entities = {} :: { [string]: Entity }
	self._nextId = 1

	-- Connections
	self._connections = {} :: { RBXScriptConnection }

	-- Events
	self.OnEntitySpawned = Instance.new("BindableEvent")
	self.OnEntityDied = Instance.new("BindableEvent")

	_instance = self
	return self
end

function EntityService:Get(): EntityService
	return EntityService.new()
end

function EntityService:Start()
	-- Main update loop - ALL entities updated here
	table.insert(
		self._connections,
		RunService.Heartbeat:Connect(function(dt)
			self:Update(dt)
		end)
	)

	print("[EntityService] Started - Single-script NPC management active")
end

function EntityService:Update(dt: number)
	local now = os.clock()

	for _, entity in self.Entities do
		-- Skip dead entities
		if entity.state == "Dead" then
			continue
		end

		-- Throttle updates based on config
		if now - entity._lastUpdate < entity.config.updateRate then
			continue
		end
		entity._lastUpdate = now

		-- Update entity based on state
		self:UpdateEntity(entity, dt)
	end

	-- Update special entities (Hunter, etc.)
	if self.SpecialEntities then
		for _, specialEntity in self.SpecialEntities do
			if specialEntity.Update then
				specialEntity:Update(dt)
			end
		end
	end
end

function EntityService:UpdateEntity(entity: Entity, _dt: number)
	if entity.state == "Idle" then
		self:UpdateIdle(entity)
	elseif entity.state == "Chase" then
		self:UpdateChase(entity)
	elseif entity.state == "Attack" then
		self:UpdateAttack(entity)
	elseif entity.state == "Stagger" then
		self:UpdateStagger(entity)
	end
end

function EntityService:UpdateIdle(entity: Entity)
	-- Look for targets
	local target = self:DetectTarget(entity)
	if target then
		entity.target = target
		entity.state = "Chase"
	end
end

function EntityService:UpdateChase(entity: Entity)
	-- Validate target
	if not entity.target or not self:IsTargetValid(entity.target) then
		entity.target = nil
		entity.state = "Idle"
		return
	end

	local distance = self:GetDistanceToTarget(entity)

	if distance <= entity.config.attackRange then
		entity.state = "Attack"
	else
		-- Move toward target
		local char = entity.target.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				entity.humanoid:MoveTo(hrp.Position)
			end
		end
	end
end

function EntityService:UpdateAttack(entity: Entity)
	-- Validate target
	if not entity.target or not self:IsTargetValid(entity.target) then
		entity.target = nil
		entity.state = "Idle"
		return
	end

	-- Check still in range
	local distance = self:GetDistanceToTarget(entity)
	if distance > entity.config.attackRange * 1.2 then
		entity.state = "Chase"
		return
	end

	-- Attack cooldown
	local now = os.clock()
	if now - entity._lastAttack < entity.config.attackCooldown then
		return
	end
	entity._lastAttack = now

	-- Deal damage
	if entity.target then
		local char = entity.target.Character
		if char then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:TakeDamage(entity.config.attackDamage)
			end
		end
	end
end

function EntityService:UpdateStagger(_entity: Entity)
	-- Stagger duration handled by timer set elsewhere
	-- This is a placeholder for stagger behavior
end

function EntityService:DetectTarget(entity: Entity): Player?
	local position = entity.rootPart.Position
	local nearestPlayer: Player? = nil
	local nearestDistance = entity.config.detectionRadius

	-- Bile attraction: biled players are detected from much farther away
	local BILE_DETECTION_MULTIPLIER = 2.5
	local biledDetectionRadius = entity.config.detectionRadius * BILE_DETECTION_MULTIPLIER

	-- First pass: look for biled players (highest priority)
	local nearestBiledPlayer: Player? = nil
	local nearestBiledDistance = biledDetectionRadius

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then
			continue
		end

		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end

		local distance = (hrp.Position - position).Magnitude

		-- Check if player is biled
		local isBiled = char:GetAttribute("IsBiled")
		if isBiled then
			-- Biled players are detected from farther and take priority
			if distance < nearestBiledDistance then
				-- No LOS check for biled - zombies can "smell" the bile
				nearestBiledPlayer = player
				nearestBiledDistance = distance
			end
		elseif distance < nearestDistance then
			-- Normal detection with LOS check
			if self:HasLineOfSight(entity, char, hrp.Position) then
				nearestPlayer = player
				nearestDistance = distance
			end
		end
	end

	-- Return biled player if found, otherwise nearest visible player
	return nearestBiledPlayer or nearestPlayer
end

function EntityService:HasLineOfSight(entity: Entity, targetCharacter: Model, targetPosition: Vector3): boolean
	local origin = entity.rootPart.Position + Vector3.new(0, 2, 0)
	local direction = targetPosition - origin

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { entity.model, targetCharacter }

	local result = workspace:Raycast(origin, direction, rayParams)
	return result == nil
end

function EntityService:IsTargetValid(target: Player): boolean
	local char = target.Character
	if not char then
		return false
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	return true
end

function EntityService:GetDistanceToTarget(entity: Entity): number
	if not entity.target then
		return math.huge
	end

	local char = entity.target.Character
	if not char then
		return math.huge
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return math.huge
	end

	return (hrp.Position - entity.rootPart.Position).Magnitude
end

-- Spawning

function EntityService:SpawnEntity(model: Model, position: Vector3, config: EntityConfigOverrides?): Entity?
	if not model then
		warn("[EntityService] Cannot spawn nil model")
		return nil
	end

	local clone = model:Clone()
	clone:PivotTo(CFrame.new(position))
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		enemiesFolder = Instance.new("Folder")
		enemiesFolder.Name = "Enemies"
		enemiesFolder.Parent = workspace
	end
	clone.Parent = enemiesFolder

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local rootPart = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart

	if not humanoid or not rootPart then
		clone:Destroy()
		warn("[EntityService] Model missing Humanoid or RootPart")
		return nil
	end

	-- Apply config
	local entityConfig = mergeConfig(config)
	humanoid.WalkSpeed = entityConfig.moveSpeed
	local maxHealth = humanoid.MaxHealth
	if maxHealth <= 0 then
		maxHealth = entityConfig.attackDamage * 5
	end
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth

	-- Optimize humanoid
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

	-- Set collision group
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Zombies"
		end
	end

	-- Set network ownership to server
	rootPart:SetNetworkOwner(nil)

	-- Create entity
	local id = tostring(self._nextId)
	self._nextId += 1

	local entity: Entity = {
		id = id,
		model = clone,
		humanoid = humanoid,
		rootPart = rootPart,
		state = "Idle",
		target = nil,
		health = maxHealth,
		maxHealth = maxHealth,
		config = entityConfig,
		_lastUpdate = 0,
		_lastAttack = 0,
	}

	clone:SetAttribute("EntityId", id)

	self.Entities[id] = entity
	self.OnEntitySpawned:Fire(entity)

	return entity
end

function EntityService:DamageEntity(id: string, damage: number, source: Player?)
	local entity = self.Entities[id]
	if not entity then
		if self.SpecialEntities then
			local special = self.SpecialEntities[id]
			if special and special.TakeDamage then
				special:TakeDamage(damage, source)
			end
		end
		return
	end

	entity.health -= damage

	if entity.health <= 0 then
		self:KillEntity(id)
	else
		-- Chance to stagger
		if math.random() < 0.2 then
			entity.state = "Stagger"
			task.delay(0.5, function()
				if entity.state == "Stagger" then
					entity.state = "Chase"
				end
			end)
		end
	end
end

function EntityService:KillEntity(id: string)
	local entity = self.Entities[id]
	if not entity then
		return
	end

	entity.state = "Dead"

	-- Ragdoll
	entity.humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Fire event
	self.OnEntityDied:Fire(entity)

	-- Cleanup after delay
	Debris:AddItem(entity.model, 5)

	-- Remove from tracking
	task.delay(5.1, function()
		self.Entities[id] = nil
	end)
end

function EntityService:GetEntityCount(): number
	local count = 0
	for _ in self.Entities do
		count += 1
	end
	return count
end

function EntityService:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)

	for _, entity in self.Entities do
		if entity.model then
			entity.model:Destroy()
		end
	end
	table.clear(self.Entities)
end

-- Special entity spawning for Hunter
function EntityService:SpawnHunter(model: Model, position: Vector3): any
	-- Lazy load Hunter class
	if not Hunter then
		Hunter = require(script.Parent.Entities:WaitForChild("Hunter"))
	end

	-- Clone and position model
	local clone = model:Clone()
	clone:PivotTo(CFrame.new(position))
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		enemiesFolder = Instance.new("Folder")
		enemiesFolder.Name = "Enemies"
		enemiesFolder.Parent = workspace
	end
	clone.Parent = enemiesFolder

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local rootPart = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart

	-- Optimize humanoid and network ownership
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	end
	if rootPart then
		rootPart:SetNetworkOwner(nil)
	end

	-- Set collision group
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Zombies"
		end
	end

	-- Create Hunter instance
	local hunter = Hunter.new(clone)

	-- Store reference
	local id = tostring(self._nextId)
	self._nextId += 1
	clone:SetAttribute("EntityId", id)
	clone:SetAttribute("EntityType", "Hunter")

	-- Store in special entities table
	if not self.SpecialEntities then
		self.SpecialEntities = {}
	end
	self.SpecialEntities[id] = hunter

	print(string.format("[EntityService] Spawned Hunter with ID %s at %s", id, tostring(position)))
	return hunter
end

function EntityService:SpawnSmoker(model: Model, position: Vector3): any
	-- Lazy load Smoker class
	if not Smoker then
		Smoker = require(script.Parent.Entities:WaitForChild("Smoker"))
	end

	-- Clone and position model
	local clone = model:Clone()
	clone:PivotTo(CFrame.new(position))
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		enemiesFolder = Instance.new("Folder")
		enemiesFolder.Name = "Enemies"
		enemiesFolder.Parent = workspace
	end
	clone.Parent = enemiesFolder

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local rootPart = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart

	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	end
	if rootPart then
		rootPart:SetNetworkOwner(nil)
	end

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Zombies"
		end
	end

	-- Create Smoker instance
	local smoker = Smoker.new(clone)

	-- Store reference
	local id = tostring(self._nextId)
	self._nextId += 1
	clone:SetAttribute("EntityId", id)
	clone:SetAttribute("EntityType", "Smoker")

	-- Store in special entities table
	if not self.SpecialEntities then
		self.SpecialEntities = {}
	end
	self.SpecialEntities[id] = smoker

	print(string.format("[EntityService] Spawned Smoker with ID %s at %s", id, tostring(position)))
	return smoker
end

function EntityService:SpawnBoomer(model: Model, position: Vector3): any
	-- Lazy load Boomer class
	if not Boomer then
		Boomer = require(script.Parent.Entities:WaitForChild("Boomer"))
	end

	-- Clone and position model
	local clone = model:Clone()
	clone:PivotTo(CFrame.new(position))
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		enemiesFolder = Instance.new("Folder")
		enemiesFolder.Name = "Enemies"
		enemiesFolder.Parent = workspace
	end
	clone.Parent = enemiesFolder

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local rootPart = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart

	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	end
	if rootPart then
		rootPart:SetNetworkOwner(nil)
	end

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Zombies"
		end
	end

	-- Create Boomer instance
	local boomer = Boomer.new(clone)

	-- Store reference
	local id = tostring(self._nextId)
	self._nextId += 1
	clone:SetAttribute("EntityId", id)
	clone:SetAttribute("EntityType", "Boomer")

	-- Store in special entities table
	if not self.SpecialEntities then
		self.SpecialEntities = {}
	end
	self.SpecialEntities[id] = boomer

	print(string.format("[EntityService] Spawned Boomer with ID %s at %s", id, tostring(position)))
	return boomer
end

function EntityService:SpawnTank(model: Model, position: Vector3): any
	-- Lazy load Tank class
	if not Tank then
		Tank = require(script.Parent.Entities:WaitForChild("Tank"))
	end

	-- Clone and position model
	local clone = model:Clone()
	clone:PivotTo(CFrame.new(position))
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		enemiesFolder = Instance.new("Folder")
		enemiesFolder.Name = "Enemies"
		enemiesFolder.Parent = workspace
	end
	clone.Parent = enemiesFolder

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local rootPart = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart

	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	end
	if rootPart then
		rootPart:SetNetworkOwner(nil)
	end

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Zombies"
		end
	end

	-- Create Tank instance
	local tank = Tank.new(clone)

	-- Store reference
	local id = tostring(self._nextId)
	self._nextId += 1
	clone:SetAttribute("EntityId", id)
	clone:SetAttribute("EntityType", "Tank")

	-- Store in special entities table
	if not self.SpecialEntities then
		self.SpecialEntities = {}
	end
	self.SpecialEntities[id] = tank

	print(string.format("[EntityService] Spawned Tank with ID %s at %s", id, tostring(position)))
	return tank
end

function EntityService:SpawnWitch(model: Model, position: Vector3): any
	-- Lazy load Witch class
	if not Witch then
		Witch = require(script.Parent.Entities:WaitForChild("Witch"))
	end

	-- Clone and position model
	local clone = model:Clone()
	clone:PivotTo(CFrame.new(position))
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		enemiesFolder = Instance.new("Folder")
		enemiesFolder.Name = "Enemies"
		enemiesFolder.Parent = workspace
	end
	clone.Parent = enemiesFolder

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local rootPart = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart

	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	end
	if rootPart then
		rootPart:SetNetworkOwner(nil)
	end

	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Zombies"
		end
	end

	-- Create Witch instance
	local witch = Witch.new(clone)

	-- Store reference
	local id = tostring(self._nextId)
	self._nextId += 1
	clone:SetAttribute("EntityId", id)
	clone:SetAttribute("EntityType", "Witch")

	-- Store in special entities table
	if not self.SpecialEntities then
		self.SpecialEntities = {}
	end
	self.SpecialEntities[id] = witch

	print(string.format("[EntityService] Spawned Witch with ID %s at %s", id, tostring(position)))
	return witch
end

-- Rescue a player from special infected (Hunter pin or Smoker grab)
function EntityService:RescuePinnedPlayer(rescuer: Player, victim: Player): boolean
	local victimChar = victim.Character
	if not victimChar then
		return false
	end

	-- Check for Hunter pin
	local pinnedBy = victimChar:GetAttribute("PinnedBy")
	if pinnedBy and self.SpecialEntities then
		local hunter = self.SpecialEntities[pinnedBy]
		if hunter and hunter.Rescue then
			hunter:Rescue()
			print(string.format("[EntityService] %s rescued %s from Hunter", rescuer.Name, victim.Name))
			return true
		end
	end

	-- Check for Smoker grab
	local grabbedBy = victimChar:GetAttribute("GrabbedBy")
	if grabbedBy and self.SpecialEntities then
		local smoker = self.SpecialEntities[grabbedBy]
		if smoker and smoker.Rescue then
			smoker:Rescue()
			print(string.format("[EntityService] %s rescued %s from Smoker", rescuer.Name, victim.Name))
			return true
		end
	end

	return false
end

-- Get entity by ID (works for both regular and special entities)
function EntityService:GetEntityById(id: string): any
	if self.Entities[id] then
		return self.Entities[id]
	end
	if self.SpecialEntities and self.SpecialEntities[id] then
		return self.SpecialEntities[id]
	end
	return nil
end

return EntityService
