--!strict
--[[
    Tank Special Infected
    High health, heavy melee damage

    States: Idle → Chase → Attack → Stagger → Dead
]]

-- Import BaseEnemy
local BaseEnemy = require(script.Parent.Parent:WaitForChild("BaseEnemy"))

-- Tank extends BaseEnemy
local Tank = setmetatable({}, { __index = BaseEnemy })
Tank.__index = Tank

-- Types
export type TankState = "Idle" | "Chase" | "Attack" | "Stagger" | "Dead"

-- Configuration
Tank.Config = {
	detectionRadius = 60,
	attackRange = 6,
	attackDamage = 40,
	attackCooldown = 2,
	moveSpeed = 10,
	health = 6000,
}

function Tank.new(model: Model)
	local self = BaseEnemy.new(model)
	setmetatable(self, Tank)

	self.State = "Idle" :: TankState
	self.Config = table.clone(Tank.Config)
	self._lastAttack = 0

	-- Apply stats
	self.Humanoid.Health = Tank.Config.health
	self.Humanoid.MaxHealth = Tank.Config.health
	self.Humanoid.WalkSpeed = Tank.Config.moveSpeed
	self.Humanoid.JumpPower = 50

	-- Color for identification
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.BrickColor = BrickColor.new("Really red")
		end
	end

	print("[Tank] Created new Tank entity")
	return self
end

function Tank:UpdateAttack(_dt: number)
	if not self.Target or not self:IsTargetValid() then
		self.Target = nil
		self:TransitionTo("Idle")
		return
	end

	local distance = self:GetDistanceToTarget()
	if distance > self.Config.attackRange * 1.2 then
		self:TransitionTo("Chase")
		return
	end

	local now = os.clock()
	if now - self._lastAttack < self.Config.attackCooldown then
		return
	end
	self._lastAttack = now

	local char = self.Target.Character
	if char then
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(self.Config.attackDamage)
		end
	end
end

function Tank:Die()
	-- Ragdoll
	self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Cleanup after delay
	task.delay(8, function()
		self.Model:Destroy()
	end)
end

return Tank
