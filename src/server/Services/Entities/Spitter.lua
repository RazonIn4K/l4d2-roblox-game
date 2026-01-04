--!strict
--[[
    Spitter Special Infected
    Fragile, spits acid that creates damaging pools on the ground
    Flees after spitting, creates acid pool on death

    States: Idle → Chase → Spit → Flee → Stagger → Dead
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Import BaseEnemy
local BaseEnemy = require(script.Parent.Parent:WaitForChild("BaseEnemy"))

-- Lazy-loaded PlayerService for damage feedback
local PlayerService = nil
local function getPlayerService()
	if not PlayerService then
		local Services = script.Parent.Parent :: Instance
		PlayerService = require(Services:WaitForChild("PlayerService") :: any)
	end
	return PlayerService:Get()
end

-- Spitter extends BaseEnemy
local Spitter = setmetatable({}, { __index = BaseEnemy })
Spitter.__index = Spitter

-- Types
export type SpitterState = "Idle" | "Chase" | "Spit" | "Flee" | "Stagger" | "Dead"

-- Configuration
Spitter.Config = {
	health = 100,
	detectionRadius = 45,
	spitRange = 35, -- Range to start spitting
	spitMinRange = 10, -- Minimum range (too close)
	moveSpeed = 12,
	fleeSpeed = 16,
	spitCooldown = 6,
	acidPoolRadius = 8, -- Size of acid pool
	acidPoolDuration = 8, -- How long pool lasts
	acidDamagePerSecond = 8, -- Damage while standing in acid
	acidProjectileSpeed = 45,
	fleeDuration = 3, -- How long to flee after spitting
}

function Spitter.new(model: Model)
	local self = BaseEnemy.new(model)
	setmetatable(self, Spitter)

	-- Entity type identifier
	self.Type = "Spitter"

	-- Override state type
	self.State = "Idle" :: SpitterState
	self.Config = table.clone(Spitter.Config)

	-- Spitter-specific state
	self.LastSpit = 0
	self.FleeStartTime = 0
	self.HasCreatedDeathPool = false
	self.ActivePools = {} :: { Part }

	-- Set health
	self.Humanoid.MaxHealth = Spitter.Config.health
	self.Humanoid.Health = Spitter.Config.health
	self.Humanoid.WalkSpeed = Spitter.Config.moveSpeed
	self.Humanoid.JumpPower = 35

	-- Make Spitter thin and acid-green with elongated neck
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.BrickColor = BrickColor.new("Lime green")
			part.Material = Enum.Material.SmoothPlastic

			-- Elongated neck/head area
			if part.Name == "Head" then
				part.Size = part.Size * Vector3.new(0.9, 1.3, 0.9)
			end

			-- Thinner body
			if part.Name == "Torso" or part.Name == "UpperTorso" then
				part.Size = part.Size * Vector3.new(0.8, 1.1, 0.7)
			end

			-- Thin limbs
			if part.Name:find("Arm") or part.Name:find("Leg") or part.Name:find("Upper") or part.Name:find("Lower") then
				part.Size = part.Size * Vector3.new(0.7, 1, 0.7)
			end
		end
	end

	-- Create spitter sounds
	self:CreateSpitterSounds()

	print("[Spitter] Created new Spitter entity - HP:", Spitter.Config.health)
	return self
end

function Spitter:CreateSpitterSounds()
	-- Gurgling/hissing sound
	local hiss = Instance.new("Sound")
	hiss.Name = "SpitterHiss"
	hiss.SoundId = "rbxassetid://5153382847"
	hiss.Volume = 0.3
	hiss.Looped = true
	hiss.RollOffMaxDistance = 40
	hiss.PlaybackSpeed = 1.3 -- Higher pitch
	hiss.Parent = self.RootPart
	hiss:Play()
	self.HissSound = hiss
end

function Spitter:Update(dt: number)
	-- Throttle updates
	local now = os.clock()
	if now - self._lastUpdate < self._updateInterval then
		return
	end
	self._lastUpdate = now

	if self.State == "Dead" then
		return
	end

	-- State handlers
	local handlers = {
		Idle = self.UpdateIdle,
		Chase = self.UpdateChase,
		Spit = self.UpdateSpit,
		Flee = self.UpdateFlee,
		Stagger = self.UpdateStagger,
	}

	local handler = handlers[self.State]
	if handler then
		handler(self, dt)
	end
end

function Spitter:TransitionTo(newState: SpitterState)
	local oldState = self.State
	self.State = newState
	self.LastStateChange = os.clock()

	print(string.format("[Spitter] State transition: %s → %s", oldState, newState))
	self:OnStateEnter(newState, oldState)
end

function Spitter:OnStateEnter(newState: SpitterState, _oldState: SpitterState)
	if newState == "Chase" then
		self.Humanoid.WalkSpeed = Spitter.Config.moveSpeed
	elseif newState == "Spit" then
		self.Humanoid.WalkSpeed = 0
		self:ExecuteSpit()
	elseif newState == "Flee" then
		self.Humanoid.WalkSpeed = Spitter.Config.fleeSpeed
		self.FleeStartTime = os.clock()
	elseif newState == "Stagger" then
		self.Humanoid.WalkSpeed = 0
		task.delay(1, function()
			if self.State == "Stagger" then
				self:TransitionTo("Chase")
			end
		end)
	elseif newState == "Dead" then
		self:Die()
	end
end

function Spitter:UpdateIdle(_dt: number)
	self.Target = self:DetectTarget()

	if self.Target and self:IsTargetValid() then
		self:TransitionTo("Chase")
	end
end

function Spitter:UpdateChase(_dt: number)
	if not self.Target or not self:IsTargetValid() then
		self.Target = nil
		self:TransitionTo("Idle")
		return
	end

	local distance = self:GetDistanceToTarget()
	local now = os.clock()

	-- Check if should spit
	if distance <= Spitter.Config.spitRange and distance >= Spitter.Config.spitMinRange then
		if now - self.LastSpit > Spitter.Config.spitCooldown then
			if self:HasLineOfSightToTarget() then
				self:TransitionTo("Spit")
				return
			end
		end
	end

	-- If too close, flee
	if distance < Spitter.Config.spitMinRange then
		self:TransitionTo("Flee")
		return
	end

	-- Chase target
	self:MoveToTarget()
end

function Spitter:UpdateSpit(_dt: number)
	-- Spit handled in OnStateEnter, wait for completion
end

function Spitter:UpdateFlee(_dt: number)
	-- Flee from target
	if self.Target then
		self:FleeFromTarget()
	end

	-- Stop fleeing after duration
	if os.clock() - self.FleeStartTime > Spitter.Config.fleeDuration then
		self:TransitionTo("Chase")
	end
end

function Spitter:UpdateStagger(_dt: number)
	-- Handled in OnStateEnter
end

function Spitter:ExecuteSpit()
	if not self.Target then
		self:TransitionTo("Chase")
		return
	end

	local char = self.Target.Character
	if not char then
		self:TransitionTo("Chase")
		return
	end

	local targetHrp = char:FindFirstChild("HumanoidRootPart")
	if not targetHrp then
		self:TransitionTo("Chase")
		return
	end

	-- Face the target
	local direction = (targetHrp.Position - self.RootPart.Position)
	direction = Vector3.new(direction.X, 0, direction.Z).Unit
	if direction.Magnitude > 0.001 then
		self.RootPart.CFrame = CFrame.lookAt(self.RootPart.Position, self.RootPart.Position + direction)
	end

	-- Play spit sound
	local spitSound = Instance.new("Sound")
	spitSound.SoundId = "rbxassetid://287390459"
	spitSound.Volume = 0.8
	spitSound.PlaybackSpeed = 1.5
	spitSound.Parent = self.RootPart
	spitSound:Play()
	Debris:AddItem(spitSound, 2)

	-- Create acid projectile
	local projectile = Instance.new("Part")
	projectile.Name = "AcidSpit"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(2, 2, 2)
	projectile.Position = self.RootPart.Position + self.RootPart.CFrame.LookVector * 2 + Vector3.new(0, 2, 0)
	projectile.Material = Enum.Material.Neon
	projectile.BrickColor = BrickColor.new("Lime green")
	projectile.Transparency = 0.3
	projectile.CanCollide = false
	projectile.Parent = workspace

	-- Calculate arc trajectory
	local targetPos = targetHrp.Position
	local toTarget = targetPos - projectile.Position
	local distance = toTarget.Magnitude
	local flightTime = distance / Spitter.Config.acidProjectileSpeed

	-- Add arc
	local velocity = toTarget / flightTime + Vector3.new(0, workspace.Gravity * flightTime / 2.5, 0)
	projectile.AssemblyLinearVelocity = velocity

	-- Trail effect
	local trail = Instance.new("Trail")
	local attachment0 = Instance.new("Attachment")
	attachment0.Position = Vector3.new(0, 0.5, 0)
	attachment0.Parent = projectile
	local attachment1 = Instance.new("Attachment")
	attachment1.Position = Vector3.new(0, -0.5, 0)
	attachment1.Parent = projectile
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Color = ColorSequence.new(Color3.fromRGB(0, 255, 0))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Lifetime = 0.5
	trail.Parent = projectile

	-- Hit detection
	local hasHit = false
	projectile.Touched:Connect(function(hit)
		if hasHit then
			return
		end
		if hit:IsDescendantOf(self.Model) then
			return
		end

		hasHit = true

		-- Create acid pool at impact location
		self:CreateAcidPool(projectile.Position)

		projectile:Destroy()
	end)

	-- Cleanup if missed
	Debris:AddItem(projectile, 5)

	self.LastSpit = os.clock()

	print(string.format("[Spitter] Spat acid at %s", self.Target.Name))

	-- Transition to flee after spitting
	task.delay(0.5, function()
		if self.State == "Spit" then
			self:TransitionTo("Flee")
		end
	end)
end

function Spitter:CreateAcidPool(position: Vector3)
	-- Raycast down to find ground
	local rayResult = workspace:Raycast(position, Vector3.new(0, -50, 0))
	local groundPos = rayResult and rayResult.Position or position

	-- Create acid pool
	local pool = Instance.new("Part")
	pool.Name = "AcidPool"
	pool.Shape = Enum.PartType.Cylinder
	pool.Size = Vector3.new(1, Spitter.Config.acidPoolRadius * 2, Spitter.Config.acidPoolRadius * 2)
	pool.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pool.Material = Enum.Material.Neon
	pool.BrickColor = BrickColor.new("Lime green")
	pool.Transparency = 0.4
	pool.Anchored = true
	pool.CanCollide = false
	pool.Parent = workspace

	-- Bubbling particle effect
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Color = ColorSequence.new(Color3.fromRGB(0, 255, 0))
	bubbles.Size = NumberSequence.new(0.3, 0.1)
	bubbles.Lifetime = NumberRange.new(0.5, 1)
	bubbles.Rate = 20
	bubbles.Speed = NumberRange.new(2, 4)
	bubbles.SpreadAngle = Vector2.new(30, 30)
	bubbles.Parent = pool

	-- Acid sound
	local acidSound = Instance.new("Sound")
	acidSound.SoundId = "rbxassetid://5153382847"
	acidSound.Volume = 0.5
	acidSound.Looped = true
	acidSound.PlaybackSpeed = 1.2
	acidSound.Parent = pool
	acidSound:Play()

	table.insert(self.ActivePools, pool)

	print(string.format("[Spitter] Created acid pool at %s", tostring(groundPos)))

	-- Start damage loop for this pool
	self:StartPoolDamageLoop(pool, groundPos)

	-- Pool lifetime
	task.delay(Spitter.Config.acidPoolDuration, function()
		-- Fade out
		for i = 1, 10 do
			pool.Transparency = 0.4 + (i * 0.06)
			task.wait(0.1)
		end

		-- Remove from tracking
		local index = table.find(self.ActivePools, pool)
		if index then
			table.remove(self.ActivePools, index)
		end

		pool:Destroy()
	end)
end

function Spitter:StartPoolDamageLoop(pool: Part, poolPosition: Vector3)
	local poolRadius = Spitter.Config.acidPoolRadius
	local damagePerSecond = Spitter.Config.acidDamagePerSecond

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not pool or not pool.Parent then
			connection:Disconnect()
			return
		end

		-- Check all players
		for _, player in Players:GetPlayers() do
			local char = player.Character
			if not char then
				continue
			end

			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				continue
			end

			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				continue
			end

			-- Check horizontal distance (ignore Y for pool check)
			local playerPos = hrp.Position
			local horizontalDist = ((playerPos - poolPosition) * Vector3.new(1, 0, 1)).Magnitude

			if horizontalDist <= poolRadius then
				-- Player is in acid pool
				local damage = damagePerSecond * dt
				getPlayerService():DamagePlayer(player, damage, poolPosition)
			end
		end
	end)
end

function Spitter:FleeFromTarget()
	if not self.Target then
		return
	end

	local char = self.Target.Character
	if not char then
		return
	end

	local targetHrp = char:FindFirstChild("HumanoidRootPart")
	if not targetHrp then
		return
	end

	-- Move away from target
	local awayDirection = (self.RootPart.Position - targetHrp.Position).Unit
	local fleePosition = self.RootPart.Position + awayDirection * 20

	self.Humanoid:MoveTo(fleePosition)
end

function Spitter:HasLineOfSightToTarget(): boolean
	if not self.Target then
		return false
	end

	local char = self.Target.Character
	if not char then
		return false
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end

	return self:HasLineOfSight(self.RootPart.Position, hrp.Position, char)
end

function Spitter:TakeDamage(amount: number, source: Player?)
	self.Humanoid.Health = self.Humanoid.Health - amount

	if self.Humanoid.Health <= 0 then
		self:TransitionTo("Dead")
	else
		-- High stagger chance for Spitter (fragile)
		if math.random() < 0.4 then
			self:TransitionTo("Stagger")
		end

		-- Retarget to damage source
		if source and source ~= self.Target then
			local char = source.Character
			if char then
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					self.Target = source
				end
			end
		end
	end
end

function Spitter:Die()
	if self.HasCreatedDeathPool then
		return
	end
	self.HasCreatedDeathPool = true

	-- Stop sounds
	if self.HissSound then
		self.HissSound:Stop()
	end

	-- Create acid pool on death (like L4D2)
	print("[Spitter] Creating death acid pool")
	self:CreateAcidPool(self.RootPart.Position)

	-- Death sound
	local deathSound = Instance.new("Sound")
	deathSound.SoundId = "rbxassetid://287390459"
	deathSound.Volume = 1
	deathSound.PlaybackSpeed = 0.8
	deathSound.Parent = self.RootPart
	deathSound:Play()

	-- Ragdoll
	self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	print("[Spitter] Died")

	task.delay(5, function()
		self:Destroy()
	end)
end

function Spitter:Destroy()
	-- Stop sounds
	if self.HissSound then
		self.HissSound:Destroy()
	end

	-- Note: Active pools are NOT destroyed when Spitter dies
	-- They have their own lifetime and will clean themselves up
	table.clear(self.ActivePools)

	-- Destroy model
	if self.Model then
		self.Model:Destroy()
	end

	print("[Spitter] Destroyed and cleaned up")
end

return Spitter
