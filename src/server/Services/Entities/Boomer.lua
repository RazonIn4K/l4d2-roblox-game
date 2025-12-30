--!strict
--[[
    Boomer Special Infected
    Slow, fragile, explodes on death covering nearby players in bile
    Bile attracts common infected to the affected player

    States: Idle → Chase → Vomit → Attack → Stagger → Dead
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

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

-- Boomer extends BaseEnemy
local Boomer = setmetatable({}, { __index = BaseEnemy })
Boomer.__index = Boomer

-- Types
export type BoomerState = "Idle" | "Chase" | "Vomit" | "Attack" | "Stagger" | "Dead"

-- Configuration
Boomer.Config = {
	health = 50,
	detectionRadius = 30,
	attackRange = 3,
	vomitRange = 12,
	attackDamage = 5,
	moveSpeed = 8,
	vomitCooldown = 8,
	bileRadius = 15, -- Explosion bile radius
	bileDuration = 15, -- How long bile effect lasts
}

function Boomer.new(model: Model)
	local self = BaseEnemy.new(model)
	setmetatable(self, Boomer)

	-- Entity type identifier
	self.Type = "Boomer"

	-- Override state type
	self.State = "Idle" :: BoomerState
	self.Config = table.clone(Boomer.Config)

	-- Boomer-specific state
	self.LastVomit = 0
	self.HasExploded = false

	-- Set health
	self.Humanoid.MaxHealth = Boomer.Config.health
	self.Humanoid.Health = Boomer.Config.health
	self.Humanoid.WalkSpeed = Boomer.Config.moveSpeed
	self.Humanoid.JumpPower = 0

	-- Make Boomer fat and green
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.BrickColor = BrickColor.new("Bright green")
			part.Material = Enum.Material.SmoothPlastic

			-- Make torso fatter
			if part.Name == "Torso" or part.Name == "UpperTorso" then
				part.Size = part.Size * Vector3.new(1.5, 1.2, 1.5)
			end
		end
	end

	-- Create boomer sounds
	self:CreateBoomerSounds()

	print("[Boomer] Created new Boomer entity - HP:", Boomer.Config.health)
	return self
end

function Boomer:CreateBoomerSounds()
	-- Gurgling idle sound
	local gurgle = Instance.new("Sound")
	gurgle.Name = "BoomerGurgle"
	gurgle.SoundId = "rbxassetid://5153382847" -- Gurgling sound
	gurgle.Volume = 0.4
	gurgle.Looped = true
	gurgle.RollOffMaxDistance = 40
	gurgle.Parent = self.RootPart
	gurgle:Play()
	self.GurgleSound = gurgle
end

function Boomer:Update(dt: number)
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
		Vomit = self.UpdateVomit,
		Attack = self.UpdateAttack,
		Stagger = self.UpdateStagger,
	}

	local handler = handlers[self.State]
	if handler then
		handler(self, dt)
	end
end

function Boomer:TransitionTo(newState: BoomerState)
	local oldState = self.State
	self.State = newState
	self.LastStateChange = os.clock()

	print(string.format("[Boomer] State transition: %s → %s", oldState, newState))
	self:OnStateEnter(newState, oldState)
end

function Boomer:OnStateEnter(newState: BoomerState, _oldState: BoomerState)
	if newState == "Vomit" then
		self.Humanoid.WalkSpeed = 0
		self:ExecuteVomit()
	elseif newState == "Attack" then
		self.Humanoid.WalkSpeed = 0
	elseif newState == "Chase" then
		self.Humanoid.WalkSpeed = Boomer.Config.moveSpeed
	elseif newState == "Dead" then
		self:Die()
	end
end

function Boomer:UpdateIdle(_dt: number)
	self.Target = self:DetectTarget()

	if self.Target and self:IsTargetValid() then
		self:TransitionTo("Chase")
	end
end

function Boomer:UpdateChase(_dt: number)
	if not self.Target or not self:IsTargetValid() then
		self.Target = nil
		self:TransitionTo("Idle")
		return
	end

	local distance = self:GetDistanceToTarget()
	local now = os.clock()

	-- Check if should vomit (medium range attack)
	if distance <= Boomer.Config.vomitRange and distance > Boomer.Config.attackRange then
		if now - self.LastVomit > Boomer.Config.vomitCooldown then
			if self:HasLineOfSightToTarget() then
				self:TransitionTo("Vomit")
				return
			end
		end
	end

	-- Melee attack if very close
	if distance <= Boomer.Config.attackRange then
		self:TransitionTo("Attack")
		return
	end

	-- Chase target
	self:MoveToTarget()
end

function Boomer:UpdateVomit(_dt: number)
	-- Vomit handled in OnStateEnter, wait for completion
	-- Return to chase after vomit
end

function Boomer:UpdateAttack(_dt: number)
	if not self.Target or not self:IsTargetValid() then
		self.Target = nil
		self:TransitionTo("Idle")
		return
	end

	local distance = self:GetDistanceToTarget()
	if distance > Boomer.Config.attackRange * 1.2 then
		self:TransitionTo("Chase")
		return
	end

	-- Melee attack (weak, just slap)
	if self.Target then
		getPlayerService():DamagePlayer(self.Target, Boomer.Config.attackDamage, self.RootPart.Position)
	end

	-- Return to chase
	task.delay(1, function()
		if self.State == "Attack" then
			self:TransitionTo("Chase")
		end
	end)
end

function Boomer:UpdateStagger(_dt: number)
	-- Handled in base class
end

function Boomer:ExecuteVomit()
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

	-- Play vomit sound
	local vomitSound = Instance.new("Sound")
	vomitSound.SoundId = "rbxassetid://5153382847"
	vomitSound.Volume = 1
	vomitSound.PlaybackSpeed = 0.8
	vomitSound.Parent = self.RootPart
	vomitSound:Play()
	Debris:AddItem(vomitSound, 3)

	-- Create vomit projectile
	local vomit = Instance.new("Part")
	vomit.Name = "BoomerVomit"
	vomit.Shape = Enum.PartType.Ball
	vomit.Size = Vector3.new(2, 2, 2)
	vomit.Position = self.RootPart.Position + self.RootPart.CFrame.LookVector * 2 + Vector3.new(0, 1, 0)
	vomit.Material = Enum.Material.Neon
	vomit.BrickColor = BrickColor.new("Bright green")
	vomit.Transparency = 0.3
	vomit.CanCollide = false
	vomit.Parent = workspace

	-- Trajectory toward target
	local toTarget = (targetHrp.Position - vomit.Position)
	local distance = toTarget.Magnitude
	local flightTime = distance / 40

	vomit.AssemblyLinearVelocity = toTarget / flightTime + Vector3.new(0, workspace.Gravity * flightTime / 3, 0)

	-- Hit detection
	local hasHit = false
	vomit.Touched:Connect(function(hit)
		if hasHit then
			return
		end
		if hit:IsDescendantOf(self.Model) then
			return
		end

		-- Check if hit a player
		local hitChar = hit:FindFirstAncestorOfClass("Model")
		if hitChar then
			local hitPlayer = Players:GetPlayerFromCharacter(hitChar)
			if hitPlayer then
				self:ApplyBile(hitPlayer)
				hasHit = true
			end
		end

		-- Create splat effect
		self:CreateBileSplat(vomit.Position)
		vomit:Destroy()
	end)

	-- Cleanup if missed
	Debris:AddItem(vomit, 3)

	self.LastVomit = os.clock()

	-- Return to chase after vomit
	task.delay(1.5, function()
		if self.State == "Vomit" then
			self:TransitionTo("Chase")
		end
	end)

	print(string.format("[Boomer] Vomited at %s", self.Target.Name))
end

function Boomer:HasLineOfSightToTarget(): boolean
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

function Boomer:ApplyBile(player: Player)
	local char = player.Character
	if not char then
		return
	end

	-- Set bile attribute
	char:SetAttribute("IsBiled", true)

	-- Visual effect - green tint on character
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			-- Store original color
			if not part:GetAttribute("OriginalColor") then
				part:SetAttribute("OriginalColor", part.BrickColor.Name)
			end
			part.BrickColor = BrickColor.new("Bright green")
		end
	end

	-- Play bile hit sound
	local bileSound = Instance.new("Sound")
	bileSound.SoundId = "rbxassetid://287390459"
	bileSound.Volume = 0.8
	bileSound.Parent = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
	bileSound:Play()
	Debris:AddItem(bileSound, 2)

	print(string.format("[Boomer] %s is covered in bile!", player.Name))

	-- Clear bile after duration
	task.delay(Boomer.Config.bileDuration, function()
		if char and char.Parent then
			char:SetAttribute("IsBiled", false)

			-- Restore original colors
			for _, part in char:GetDescendants() do
				if part:IsA("BasePart") then
					local originalColor = part:GetAttribute("OriginalColor")
					if originalColor then
						part.BrickColor = BrickColor.new(originalColor)
						part:SetAttribute("OriginalColor", nil)
					end
				end
			end

			print(string.format("[Boomer] Bile wore off from %s", player.Name))
		end
	end)
end

function Boomer:CreateBileSplat(position: Vector3)
	-- Create green splat particles
	for _ = 1, 8 do
		local splat = Instance.new("Part")
		splat.Size = Vector3.new(0.5, 0.5, 0.5)
		splat.Shape = Enum.PartType.Ball
		splat.Position = position + Vector3.new(math.random(-2, 2), 0, math.random(-2, 2))
		splat.Material = Enum.Material.Neon
		splat.BrickColor = BrickColor.new("Bright green")
		splat.Transparency = 0.3
		splat.CanCollide = false
		splat.Parent = workspace

		splat.AssemblyLinearVelocity = Vector3.new(math.random(-15, 15), math.random(5, 15), math.random(-15, 15))

		Debris:AddItem(splat, 2)
	end
end

function Boomer:TakeDamage(amount: number, source: Player?)
	self.Humanoid.Health = self.Humanoid.Health - amount

	if self.Humanoid.Health <= 0 then
		self:TransitionTo("Dead")
	else
		-- High stagger chance for Boomer (fragile)
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

function Boomer:Die()
	if self.HasExploded then
		return
	end
	self.HasExploded = true

	-- Stop sounds
	if self.GurgleSound then
		self.GurgleSound:Stop()
	end

	-- EXPLOSION! Cover nearby players in bile
	print("[Boomer] EXPLODING!")

	-- Explosion sound
	local explosionSound = Instance.new("Sound")
	explosionSound.SoundId = "rbxassetid://287390459"
	explosionSound.Volume = 1.5
	explosionSound.Parent = self.RootPart
	explosionSound:Play()

	-- Visual explosion
	local explosion = Instance.new("Explosion")
	explosion.BlastRadius = 0 -- No damage, just visual
	explosion.BlastPressure = 0
	explosion.Position = self.RootPart.Position
	explosion.Parent = workspace
	Debris:AddItem(explosion, 2)

	-- Create bile splatter everywhere
	for _ = 1, 20 do
		local splat = Instance.new("Part")
		splat.Size = Vector3.new(0.8, 0.8, 0.8)
		splat.Shape = Enum.PartType.Ball
		splat.Position = self.RootPart.Position
		splat.Material = Enum.Material.Neon
		splat.BrickColor = BrickColor.new("Bright green")
		splat.Transparency = 0.3
		splat.CanCollide = false
		splat.Parent = workspace

		splat.AssemblyLinearVelocity = Vector3.new(math.random(-25, 25), math.random(10, 25), math.random(-25, 25))

		Debris:AddItem(splat, 3)
	end

	-- Apply bile to all nearby players
	local position = self.RootPart.Position
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then
			continue
		end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end

		local distance = (hrp.Position - position).Magnitude
		if distance <= Boomer.Config.bileRadius then
			self:ApplyBile(player)
		end
	end

	-- Ragdoll and cleanup
	self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	task.delay(3, function()
		self:Destroy()
	end)
end

function Boomer:Destroy()
	if self.GurgleSound then
		self.GurgleSound:Destroy()
	end
	if self.Model then
		self.Model:Destroy()
	end

	print("[Boomer] Destroyed and cleaned up")
end

return Boomer
