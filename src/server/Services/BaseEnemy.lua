--!strict
--[[
    Base Enemy Class
    Common functionality for all enemy types
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

-- Types
export type EnemyState = "Idle" | "Patrol" | "Chase" | "Attack" | "Stagger" | "Dead"

local BaseEnemy = {}
BaseEnemy.__index = BaseEnemy

function BaseEnemy.new(model: Model)
	local self = setmetatable({}, BaseEnemy)

	self.Model = model
	self.Humanoid = model:FindFirstChildOfClass("Humanoid")
	self.RootPart = model:FindFirstChild("HumanoidRootPart")

	if not self.Humanoid or not self.RootPart then
		error("Model missing Humanoid or HumanoidRootPart")
	end

	self.State = "Idle" :: EnemyState
	self.Target = nil :: Player?
	self.LastStateChange = os.clock()

	-- Performance throttling
	self._lastUpdate = 0
	self._updateInterval = 0.0625 -- 16 Hz

	-- Config (override in subclasses)
	self.Config = {
		detectionRadius = 40,
		attackRange = 3,
		attackDamage = 10,
		attackCooldown = 1,
		moveSpeed = 16,
		health = 50,
	}

	return self
end

function BaseEnemy:Update(dt: number)
	-- Throttle updates
	local now = os.clock()
	if now - self._lastUpdate < self._updateInterval then
		return
	end
	self._lastUpdate = now

	if self.State == "Dead" then
		return
	end

	-- State logic
	local handlers = {
		Idle = self.UpdateIdle,
		Patrol = self.UpdatePatrol,
		Chase = self.UpdateChase,
		Attack = self.UpdateAttack,
		Stagger = self.UpdateStagger,
	}

	local handler = handlers[self.State]
	if handler then
		handler(self, dt)
	end
end

function BaseEnemy:TransitionTo(newState: EnemyState)
	local oldState = self.State
	self.State = newState
	self.LastStateChange = os.clock()
	self:OnStateEnter(newState, oldState)
end

function BaseEnemy:OnStateEnter(_newState: EnemyState, _oldState: EnemyState)
	-- Override in subclasses for state entry behavior
end

function BaseEnemy:UpdateIdle(_dt: number)
	-- Look for targets
	local target = self:DetectTarget()
	if target then
		self.Target = target
		self:TransitionTo("Chase")
	end
end

function BaseEnemy:UpdatePatrol(_dt: number)
	-- Basic patrol - not used in current implementation
end

function BaseEnemy:UpdateChase(_dt: number)
	if not self.Target or not self:IsTargetValid() then
		self.Target = nil
		self:TransitionTo("Idle")
		return
	end

	local distance = self:GetDistanceToTarget()

	if distance <= self.Config.attackRange then
		self:TransitionTo("Attack")
	else
		self:MoveToTarget()
	end
end

function BaseEnemy:UpdateAttack(_dt: number)
	-- Attack logic in subclasses
end

function BaseEnemy:UpdateStagger(_dt: number)
	-- Stagger recovery
	if os.clock() - self.LastStateChange > 1 then
		self:TransitionTo("Chase")
	end
end

function BaseEnemy:DetectTarget(): Player?
	local position = self.RootPart.Position
	local config = self.Config

	-- Bile attraction: prioritize biled players
	local biledPlayers = {}
	local normalPlayers = {}

	-- Separate biled and normal players
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
		local isBiled = char:GetAttribute("IsBiled") == true

		if isBiled then
			-- Biled players detected from 2.5x farther, no LOS required
			local bileDetectionRadius = config.detectionRadius * 2.5
			if distance <= bileDetectionRadius then
				table.insert(biledPlayers, { player = player, distance = distance })
			end
		else
			-- Normal detection requires LOS
			if distance <= config.detectionRadius then
				if self:HasLineOfSight(position, hrp.Position, char) then
					table.insert(normalPlayers, { player = player, distance = distance })
				end
			end
		end
	end

	-- Prioritize biled players (closest first)
	if #biledPlayers > 0 then
		table.sort(biledPlayers, function(a, b)
			return a.distance < b.distance
		end)
		return biledPlayers[1].player
	end

	-- Fall back to normal players (closest first)
	if #normalPlayers > 0 then
		table.sort(normalPlayers, function(a, b)
			return a.distance < b.distance
		end)
		return normalPlayers[1].player
	end

	return nil
end

function BaseEnemy:HasLineOfSight(from: Vector3, to: Vector3, targetCharacter: Model): boolean
	local direction = (to - from)
	local distance = direction.Magnitude
	if distance == 0 then
		return true
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { self.Model, targetCharacter }

	local result = workspace:Raycast(from, direction.Unit * distance, raycastParams)

	-- No hit means clear line of sight
	return result == nil
end

function BaseEnemy:IsTargetValid(): boolean
	if not self.Target then
		return false
	end

	local char = self.Target.Character
	if not char then
		return false
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	return true
end

function BaseEnemy:GetDistanceToTarget(): number
	if not self.Target then
		return math.huge
	end

	local char = self.Target.Character
	if not char then
		return math.huge
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return math.huge
	end

	return (self.RootPart.Position - hrp.Position).Magnitude
end

function BaseEnemy:MoveToTarget()
	if not self.Target then
		return
	end

	local char = self.Target.Character
	if not char then
		return
	end

	local targetPos = char:FindFirstChild("HumanoidRootPart")
	if not targetPos then
		return
	end

	-- Use pathfinding for smarter movement
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
	})

	local success, _errorMessage = pcall(function()
		path:ComputeAsync(self.RootPart.Position, targetPos.Position)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		if #waypoints > 1 then
			self.Humanoid:MoveTo(waypoints[2].Position)
		end
	else
		-- Fallback to direct movement
		self.Humanoid:MoveTo(targetPos.Position)
	end
end

function BaseEnemy:TakeDamage(amount: number, _source: Player?)
	self.Humanoid.Health -= amount

	if self.Humanoid.Health <= 0 then
		self:TransitionTo("Dead")
		self:Die()
	else
		-- Stagger chance
		if math.random() < 0.2 then
			self:TransitionTo("Stagger")
		end
	end
end

function BaseEnemy:Die()
	-- Ragdoll
	self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Cleanup after delay (allows ragdoll to play out)
	task.delay(5, function()
		self:Destroy()
	end)
end

-- Proper cleanup for all resources
function BaseEnemy:Destroy()
	-- Destroy model
	if self.Model then
		self.Model:Destroy()
	end
end

return BaseEnemy
