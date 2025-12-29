--!strict
--[[
    EntityService
    CRITICAL: Manages ALL NPCs in a single script
    Never create individual scripts per enemy - this is the #1 performance requirement
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

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
}

export type EntityConfig = {
	detectionRadius: number,
	attackRange: number,
	attackDamage: number,
	attackCooldown: number,
	moveSpeed: number,
	updateRate: number,
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

	for id, entity in self.Entities do
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
end

function EntityService:UpdateEntity(entity: Entity, dt: number)
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
	-- Check still in range
	local distance = self:GetDistanceToTarget(entity)
	if distance > entity.config.attackRange * 1.2 then
		entity.state = "Chase"
		return
	end

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

function EntityService:UpdateStagger(entity: Entity)
	-- Stagger duration handled by timer set elsewhere
	-- This is a placeholder for stagger behavior
end

function EntityService:DetectTarget(entity: Entity): Player?
	local position = entity.rootPart.Position
	local nearestPlayer: Player? = nil
	local nearestDistance = entity.config.detectionRadius

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
		if distance < nearestDistance then
			-- Line of sight check
			if self:HasLineOfSight(entity, hrp.Position) then
				nearestPlayer = player
				nearestDistance = distance
			end
		end
	end

	return nearestPlayer
end

function EntityService:HasLineOfSight(entity: Entity, targetPosition: Vector3): boolean
	local origin = entity.rootPart.Position + Vector3.new(0, 2, 0)
	local direction = targetPosition - origin

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { entity.model }

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

function EntityService:SpawnEntity(model: Model, position: Vector3, config: EntityConfig?): Entity?
	if not model then
		warn("[EntityService] Cannot spawn nil model")
		return nil
	end

	local clone = model:Clone()
	clone:PivotTo(CFrame.new(position))
	clone.Parent = workspace.Enemies

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local rootPart = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart

	if not humanoid or not rootPart then
		clone:Destroy()
		warn("[EntityService] Model missing Humanoid or RootPart")
		return nil
	end

	-- Apply config
	local entityConfig = config or DEFAULT_CONFIG
	humanoid.WalkSpeed = entityConfig.moveSpeed

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
		health = entityConfig.attackDamage * 5, -- Placeholder health
		maxHealth = entityConfig.attackDamage * 5,
		config = entityConfig,
		_lastUpdate = 0,
	}

	clone:SetAttribute("EntityId", id)

	self.Entities[id] = entity
	self.OnEntitySpawned:Fire(entity)

	return entity
end

function EntityService:DamageEntity(id: string, damage: number, source: Player?)
	local entity = self.Entities[id]
	if not entity then
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

function EntityService:GetEntityById(id: string): Entity?
	return self.Entities[id]
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

return EntityService
