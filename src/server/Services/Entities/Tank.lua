--!strict
--[[
    Tank Special Infected
    Boss-tier infected with massive health and devastating attacks
    Can throw rocks at distant targets, enters rage mode when frustrated

    States: Idle → Chase → Attack → RockThrow → Rage → Stagger → Dead
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

-- Tank extends BaseEnemy
local Tank = setmetatable({}, { __index = BaseEnemy })
Tank.__index = Tank

-- Types
export type TankState = "Idle" | "Chase" | "Attack" | "RockThrow" | "Rage" | "Stagger" | "Dead"

-- Configuration
Tank.Config = {
	health = 6000,
	detectionRadius = 80,
	attackRange = 6,
	rockThrowRange = 50,
	rockThrowMinRange = 15,
	attackDamage = 40,
	rockDamage = 25,
	moveSpeed = 10,
	rageSpeed = 14,
	attackCooldown = 1.5,
	rockThrowCooldown = 5,
	frustrationBuildRate = 1, -- Per second when can't reach target
	frustrationDecayRate = 2, -- Per second when hitting target
	rageThreshold = 15, -- Frustration needed to enter rage
	rageDuration = 10, -- How long rage lasts
	knockbackForce = 80,
}

function Tank.new(model: Model)
	local self = BaseEnemy.new(model)
	setmetatable(self, Tank)

	-- Entity type identifier
	self.Type = "Tank"

	-- Override state type
	self.State = "Idle" :: TankState
	self.Config = table.clone(Tank.Config)

	-- Tank-specific state
	self._lastAttack = 0
	self._lastRockThrow = 0
	self.Frustration = 0
	self.IsRaging = false
	self.RageStartTime = 0
	self.LastHitTime = 0
	self.GroundPoundCooldown = 0

	-- Set health
	self.Humanoid.MaxHealth = Tank.Config.health
	self.Humanoid.Health = Tank.Config.health
	self.Humanoid.WalkSpeed = Tank.Config.moveSpeed
	self.Humanoid.JumpPower = 60

	-- Make Tank massive and red
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.BrickColor = BrickColor.new("Really red")
			part.Material = Enum.Material.SmoothPlastic

			-- Make Tank bigger
			if part.Name == "Torso" or part.Name == "UpperTorso" then
				part.Size = part.Size * Vector3.new(2.5, 2, 2.5)
			elseif part.Name == "Head" then
				part.Size = part.Size * Vector3.new(1.5, 1.5, 1.5)
			elseif part.Name:find("Arm") or part.Name:find("arm") then
				part.Size = part.Size * Vector3.new(2, 1.5, 2)
			elseif part.Name:find("Leg") or part.Name:find("leg") then
				part.Size = part.Size * Vector3.new(1.8, 1.2, 1.8)
			end
		end
	end

	-- Create Tank sounds
	self:CreateTankSounds()

	print("[Tank] Created new Tank entity - HP:", Tank.Config.health)
	return self
end

function Tank:CreateTankSounds()
	-- Roaring/breathing sound
	local roar = Instance.new("Sound")
	roar.Name = "TankRoar"
	roar.SoundId = "rbxassetid://5153382847" -- Deep growling
	roar.Volume = 0.8
	roar.Looped = true
	roar.RollOffMaxDistance = 80
	roar.PlaybackSpeed = 0.5
	roar.Parent = self.RootPart
	roar:Play()
	self.RoarSound = roar

	-- Footstep sounds (heavy)
	local footstep = Instance.new("Sound")
	footstep.Name = "TankFootstep"
	footstep.SoundId = "rbxassetid://5153072658"
	footstep.Volume = 0.6
	footstep.PlaybackSpeed = 0.6
	footstep.RollOffMaxDistance = 60
	footstep.Parent = self.RootPart
	self.FootstepSound = footstep
end

function Tank:Update(dt: number)
	-- Throttle updates
	local now = os.clock()
	if now - self._lastUpdate < self._updateInterval then
		return
	end
	self._lastUpdate = now

	if self.State == "Dead" then
		return
	end

	-- Update frustration
	self:UpdateFrustration(dt)

	-- Check rage timeout
	if self.IsRaging and now - self.RageStartTime > Tank.Config.rageDuration then
		self:EndRage()
	end

	-- State handlers
	local handlers = {
		Idle = self.UpdateIdle,
		Chase = self.UpdateChase,
		Attack = self.UpdateAttack,
		RockThrow = self.UpdateRockThrow,
		Rage = self.UpdateRage,
		Stagger = self.UpdateStagger,
	}

	local handler = handlers[self.State]
	if handler then
		handler(self, dt)
	end
end

function Tank:TransitionTo(newState: TankState)
	local oldState = self.State
	self.State = newState
	self.LastStateChange = os.clock()

	print(string.format("[Tank] State transition: %s → %s", oldState, newState))
	self:OnStateEnter(newState, oldState)
end

function Tank:OnStateEnter(newState: TankState, _oldState: TankState)
	if newState == "Idle" then
		self.Humanoid.WalkSpeed = 0
	elseif newState == "Chase" then
		local speed = self.IsRaging and Tank.Config.rageSpeed or Tank.Config.moveSpeed
		self.Humanoid.WalkSpeed = speed
	elseif newState == "Attack" then
		self.Humanoid.WalkSpeed = 0
	elseif newState == "RockThrow" then
		self.Humanoid.WalkSpeed = 0
		self:ExecuteRockThrow()
	elseif newState == "Rage" then
		self:EnterRage()
	elseif newState == "Stagger" then
		self.Humanoid.WalkSpeed = 0
		task.delay(0.8, function()
			if self.State == "Stagger" then
				self:TransitionTo("Chase")
			end
		end)
	elseif newState == "Dead" then
		self:Die()
	end
end

function Tank:UpdateIdle(_dt: number)
	self.Target = self:DetectTarget()

	if self.Target and self:IsTargetValid() then
		-- Play roar sound when spotting target
		local spotSound = Instance.new("Sound")
		spotSound.SoundId = "rbxassetid://5152765415"
		spotSound.Volume = 1.5
		spotSound.PlaybackSpeed = 0.7
		spotSound.RollOffMaxDistance = 100
		spotSound.Parent = self.RootPart
		spotSound:Play()
		Debris:AddItem(spotSound, 3)

		self:TransitionTo("Chase")
	end
end

function Tank:UpdateChase(_dt: number)
	if not self.Target or not self:IsTargetValid() then
		self.Target = nil
		self:TransitionTo("Idle")
		return
	end

	local distance = self:GetDistanceToTarget()
	local now = os.clock()

	-- Check if should enter rage from frustration
	if self.Frustration >= Tank.Config.rageThreshold and not self.IsRaging then
		self:TransitionTo("Rage")
		return
	end

	-- Melee attack if close enough
	if distance <= Tank.Config.attackRange then
		self:TransitionTo("Attack")
		return
	end

	-- Rock throw if target is far but within rock range
	if distance > Tank.Config.rockThrowMinRange and distance <= Tank.Config.rockThrowRange then
		if now - self._lastRockThrow > Tank.Config.rockThrowCooldown then
			if self:HasLineOfSightToTarget() then
				self:TransitionTo("RockThrow")
				return
			end
		end
	end

	-- Chase target
	self:MoveToTarget()

	-- Play footstep occasionally
	if self.FootstepSound and math.random() < 0.1 then
		self.FootstepSound:Play()
	end
end

function Tank:UpdateAttack(_dt: number)
	if not self.Target or not self:IsTargetValid() then
		self.Target = nil
		self:TransitionTo("Idle")
		return
	end

	local distance = self:GetDistanceToTarget()
	if distance > Tank.Config.attackRange * 1.2 then
		self:TransitionTo("Chase")
		return
	end

	local now = os.clock()
	if now - self._lastAttack < Tank.Config.attackCooldown then
		return
	end
	self._lastAttack = now

	-- Execute melee attack
	self:ExecuteMeleeAttack()

	-- Reset frustration when hitting
	self.Frustration = math.max(0, self.Frustration - 5)
	self.LastHitTime = now
end

function Tank:ExecuteMeleeAttack()
	if not self.Target then
		return
	end

	local char = self.Target.Character
	if not char then
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Deal damage with feedback
	local damage = self.IsRaging and Tank.Config.attackDamage * 1.5 or Tank.Config.attackDamage
	getPlayerService():DamagePlayer(self.Target, damage, self.RootPart.Position)

	-- Knockback
	local knockbackDir = (hrp.Position - self.RootPart.Position).Unit
	local knockbackForce = self.IsRaging and Tank.Config.knockbackForce * 1.5 or Tank.Config.knockbackForce
	hrp.AssemblyLinearVelocity = knockbackDir * knockbackForce + Vector3.new(0, 30, 0)

	-- Attack sound
	local attackSound = Instance.new("Sound")
	attackSound.SoundId = "rbxassetid://5153072658"
	attackSound.Volume = 1
	attackSound.PlaybackSpeed = 0.8
	attackSound.Parent = self.RootPart
	attackSound:Play()
	Debris:AddItem(attackSound, 2)

	print(string.format("[Tank] Melee hit %s for %.0f damage", self.Target.Name, damage))
end

function Tank:UpdateRockThrow(_dt: number)
	-- Rock throw is handled in ExecuteRockThrow
	-- Wait for throw animation/timing
end

function Tank:ExecuteRockThrow()
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

	-- Wind-up grunt
	local gruntSound = Instance.new("Sound")
	gruntSound.SoundId = "rbxassetid://5153382847"
	gruntSound.Volume = 1
	gruntSound.PlaybackSpeed = 0.6
	gruntSound.Parent = self.RootPart
	gruntSound:Play()
	Debris:AddItem(gruntSound, 2)

	-- Create rock after wind-up
	task.delay(0.5, function()
		if self.State ~= "RockThrow" then
			return
		end

		self:SpawnRock(targetHrp.Position)
		self._lastRockThrow = os.clock()

		-- Return to chase
		task.delay(0.5, function()
			if self.State == "RockThrow" then
				self:TransitionTo("Chase")
			end
		end)
	end)

	print(string.format("[Tank] Throwing rock at %s", self.Target.Name))
end

function Tank:SpawnRock(targetPosition: Vector3)
	-- Create rock
	local rock = Instance.new("Part")
	rock.Name = "TankRock"
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(4, 4, 4)
	rock.Position = self.RootPart.Position + Vector3.new(0, 3, 0) + self.RootPart.CFrame.LookVector * 3
	rock.Material = Enum.Material.Slate
	rock.BrickColor = BrickColor.new("Dark stone grey")
	rock.CanCollide = true
	rock.Parent = workspace

	-- Calculate trajectory
	local toTarget = targetPosition - rock.Position
	local distance = toTarget.Magnitude
	local flightTime = distance / 60

	-- Apply velocity with arc
	rock.AssemblyLinearVelocity = toTarget / flightTime + Vector3.new(0, workspace.Gravity * flightTime / 2.5, 0)

	-- Add spin
	rock.AssemblyAngularVelocity = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))

	-- Hit detection
	local hasHit = false
	local touchConnection: RBXScriptConnection?
	touchConnection = rock.Touched:Connect(function(hit)
		if hasHit then
			return
		end
		if hit:IsDescendantOf(self.Model) then
			return
		end

		-- Check if hit a player
		local hitModel = hit:FindFirstAncestorOfClass("Model")
		if hitModel then
			local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
			if hitPlayer then
				hasHit = true
				getPlayerService():DamagePlayer(hitPlayer, Tank.Config.rockDamage, rock.Position)

				-- Knockback
				local hrp = hitModel:FindFirstChild("HumanoidRootPart")
				if hrp then
					local knockDir = (hrp.Position - rock.Position).Unit
					hrp.AssemblyLinearVelocity = knockDir * 40 + Vector3.new(0, 20, 0)
				end

				print(string.format("[Tank] Rock hit %s!", hitPlayer.Name))
			end
		end

		-- Create debris effect on impact
		self:CreateRockDebris(rock.Position)

		-- Impact sound
		local impactSound = Instance.new("Sound")
		impactSound.SoundId = "rbxassetid://5153072658"
		impactSound.Volume = 0.8
		impactSound.Parent = rock
		impactSound:Play()

		-- Cleanup
		if touchConnection then
			touchConnection:Disconnect()
		end
		task.delay(0.5, function()
			rock:Destroy()
		end)
	end)

	-- Cleanup if never hit anything
	Debris:AddItem(rock, 5)
end

function Tank:CreateRockDebris(position: Vector3)
	-- Create small rock fragments
	for _ = 1, 6 do
		local debris = Instance.new("Part")
		debris.Size = Vector3.new(0.5, 0.5, 0.5)
		debris.Position = position + Vector3.new(math.random(-2, 2), 0, math.random(-2, 2))
		debris.Material = Enum.Material.Slate
		debris.BrickColor = BrickColor.new("Dark stone grey")
		debris.CanCollide = false
		debris.Parent = workspace

		debris.AssemblyLinearVelocity = Vector3.new(math.random(-20, 20), math.random(10, 25), math.random(-20, 20))

		Debris:AddItem(debris, 2)
	end
end

function Tank:UpdateRage(_dt: number)
	-- Rage mode - relentless pursuit
	if not self.Target or not self:IsTargetValid() then
		self.Target = self:DetectTarget()
		if not self.Target then
			self:EndRage()
			self:TransitionTo("Idle")
			return
		end
	end

	local distance = self:GetDistanceToTarget()

	-- Attack if close
	if distance <= Tank.Config.attackRange then
		self:ExecuteMeleeAttack()
		self._lastAttack = os.clock()
	end

	-- Always chase in rage mode
	self:MoveToTarget()

	-- Rage sounds
	if math.random() < 0.05 then
		local rageSound = Instance.new("Sound")
		rageSound.SoundId = "rbxassetid://5152765415"
		rageSound.Volume = 1
		rageSound.PlaybackSpeed = 0.8
		rageSound.Parent = self.RootPart
		rageSound:Play()
		Debris:AddItem(rageSound, 2)
	end
end

function Tank:UpdateStagger(_dt: number)
	-- Handled in OnStateEnter
end

function Tank:UpdateFrustration(dt: number)
	if not self.Target then
		self.Frustration = math.max(0, self.Frustration - Tank.Config.frustrationDecayRate * dt)
		return
	end

	local now = os.clock()
	local distance = self:GetDistanceToTarget()

	-- Build frustration if can't reach target
	if distance > Tank.Config.attackRange and now - self.LastHitTime > 3 then
		self.Frustration = self.Frustration + Tank.Config.frustrationBuildRate * dt
	else
		-- Decay frustration when close or recently hit
		self.Frustration = math.max(0, self.Frustration - Tank.Config.frustrationDecayRate * dt)
	end
end

function Tank:EnterRage()
	self.IsRaging = true
	self.RageStartTime = os.clock()
	self.Frustration = 0

	-- Speed boost
	self.Humanoid.WalkSpeed = Tank.Config.rageSpeed

	-- Visual effect - make Tank glow red
	for _, part in self.Model:GetDescendants() do
		if part:IsA("BasePart") then
			part.BrickColor = BrickColor.new("Bright red")

			-- Add glow
			local light = Instance.new("PointLight")
			light.Name = "RageGlow"
			light.Color = Color3.fromRGB(255, 50, 50)
			light.Brightness = 2
			light.Range = 8
			light.Parent = part
		end
	end

	-- Rage roar
	local rageRoar = Instance.new("Sound")
	rageRoar.SoundId = "rbxassetid://5152765415"
	rageRoar.Volume = 2
	rageRoar.PlaybackSpeed = 0.6
	rageRoar.RollOffMaxDistance = 120
	rageRoar.Parent = self.RootPart
	rageRoar:Play()
	Debris:AddItem(rageRoar, 4)

	print("[Tank] ENTERED RAGE MODE!")

	-- Return to Chase behavior but with rage speed
	self:TransitionTo("Chase")
end

function Tank:EndRage()
	self.IsRaging = false

	-- Restore normal speed
	self.Humanoid.WalkSpeed = Tank.Config.moveSpeed

	-- Remove visual effects
	for _, part in self.Model:GetDescendants() do
		if part:IsA("BasePart") then
			part.BrickColor = BrickColor.new("Really red")

			-- Remove glow
			local light = part:FindFirstChild("RageGlow")
			if light then
				light:Destroy()
			end
		end
	end

	print("[Tank] Rage mode ended")
end

function Tank:HasLineOfSightToTarget(): boolean
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

function Tank:TakeDamage(amount: number, source: Player?)
	self.Humanoid.Health = self.Humanoid.Health - amount

	if self.Humanoid.Health <= 0 then
		self:TransitionTo("Dead")
	else
		-- Tank has very low stagger chance
		if math.random() < 0.05 then
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

		-- Damage increases frustration
		self.Frustration = self.Frustration + 2
	end

	print(
		string.format(
			"[Tank] Took %.0f damage, HP: %.0f, Frustration: %.1f",
			amount,
			self.Humanoid.Health,
			self.Frustration
		)
	)
end

function Tank:Die()
	-- Stop sounds
	if self.RoarSound then
		self.RoarSound:Stop()
	end

	-- End rage if active
	if self.IsRaging then
		self:EndRage()
	end

	-- Death roar
	local deathSound = Instance.new("Sound")
	deathSound.SoundId = "rbxassetid://5152765415"
	deathSound.Volume = 2
	deathSound.PlaybackSpeed = 0.4
	deathSound.RollOffMaxDistance = 150
	deathSound.Parent = self.RootPart
	deathSound:Play()

	-- Ragdoll
	self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	print("[Tank] KILLED!")

	-- Cleanup after delay (longer for boss)
	task.delay(10, function()
		self:Destroy()
	end)
end

function Tank:Destroy()
	if self.RoarSound then
		self.RoarSound:Destroy()
	end
	if self.FootstepSound then
		self.FootstepSound:Destroy()
	end
	if self.Model then
		self.Model:Destroy()
	end

	print("[Tank] Destroyed and cleaned up")
end

-- Suppress unused variable warning
local _ = RunService

return Tank
