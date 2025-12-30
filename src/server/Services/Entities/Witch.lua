--!strict
--[[
    Witch Special Infected
    Avoidance-based threat that stays stationary and cries
    Startles when players get too close, use flashlight, or shoot her
    Instantly incapacitates the player who startled her

    States: Idle (Crying) → Startled → Attack → Dead
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

-- Witch extends BaseEnemy
local Witch = setmetatable({}, { __index = BaseEnemy })
Witch.__index = Witch

-- Types
export type WitchState = "Idle" | "Startled" | "Attack" | "Dead"

-- Configuration
Witch.Config = {
	health = 1000,
	damage = 100, -- Instant incap
	moveSpeed = 0, -- Stationary when idle
	attackSpeed = 22, -- Very fast when attacking
	startleRadius = 8, -- Distance that startles her
	flashlightStartleRadius = 15, -- Larger radius for flashlight
	attackRange = 3,
	startleDuration = 1.5, -- Time before she attacks after being startled
}

function Witch.new(model: Model)
	local self = BaseEnemy.new(model)
	setmetatable(self, Witch)

	-- Entity type identifier
	self.Type = "Witch"

	-- Override state type
	self.State = "Idle" :: WitchState

	-- Witch-specific state
	self.StartledBy = nil :: Player?
	self.StartledAt = 0
	self.CryingSound = nil :: Sound?
	self.WarnSound = nil :: Sound?

	-- Set health
	self.Humanoid.MaxHealth = Witch.Config.health
	self.Humanoid.Health = Witch.Config.health
	self.Humanoid.WalkSpeed = Witch.Config.moveSpeed

	-- Visual appearance - pale, thin, glowing eyes
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.BrickColor = BrickColor.new("Pastel brown")
			part.Material = Enum.Material.SmoothPlastic

			-- Make her thin
			if part.Name ~= "Head" and part.Name ~= "HumanoidRootPart" then
				part.Size = part.Size * Vector3.new(0.7, 1, 0.7)
			end
		end
	end

	-- Add glowing red eyes
	local head = model:FindFirstChild("Head")
	if head then
		local leftEye = Instance.new("Part")
		leftEye.Name = "LeftEye"
		leftEye.Size = Vector3.new(0.2, 0.2, 0.1)
		leftEye.BrickColor = BrickColor.new("Really red")
		leftEye.Material = Enum.Material.Neon
		leftEye.CanCollide = false

		local leftWeld = Instance.new("Weld")
		leftWeld.Part0 = head
		leftWeld.Part1 = leftEye
		leftWeld.C0 = CFrame.new(-0.3, 0.2, -0.5)
		leftWeld.Parent = leftEye

		leftEye.Parent = head

		local rightEye = leftEye:Clone()
		rightEye.Name = "RightEye"
		local rightWeld = rightEye:FindFirstChild("Weld") :: Weld
		if rightWeld then
			rightWeld.C0 = CFrame.new(0.3, 0.2, -0.5)
		end
		rightEye.Parent = head
	end

	-- Create witch sounds
	self:CreateWitchSounds()

	-- Start in sitting/crying pose
	self.Humanoid.Sit = true

	print("[Witch] Created new Witch entity - HP:", Witch.Config.health)
	return self
end

function Witch:CreateWitchSounds()
	-- Crying sound (continuous)
	local crying = Instance.new("Sound")
	crying.Name = "WitchCrying"
	crying.SoundId = "rbxassetid://5196820083" -- Creepy crying/sobbing
	crying.Volume = 0.6
	crying.Looped = true
	crying.RollOffMaxDistance = 50
	crying.Parent = self.RootPart
	crying:Play()
	self.CryingSound = crying

	-- Warning growl (when agitated)
	local warn = Instance.new("Sound")
	warn.Name = "WitchWarn"
	warn.SoundId = "rbxassetid://5153382847" -- Agitated growl
	warn.Volume = 0.8
	warn.RollOffMaxDistance = 40
	warn.Parent = self.RootPart
	self.WarnSound = warn
end

function Witch:Update(dt: number)
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
		Startled = self.UpdateStartled,
		Attack = self.UpdateAttack,
	}

	local handler = handlers[self.State]
	if handler then
		handler(self, dt)
	end
end

function Witch:TransitionTo(newState: WitchState)
	local oldState = self.State
	self.State = newState
	self.LastStateChange = os.clock()

	print(string.format("[Witch] State transition: %s → %s", oldState, newState))
	self:OnStateEnter(newState, oldState)
end

function Witch:OnStateEnter(newState: WitchState, _oldState: WitchState)
	if newState == "Idle" then
		self.Humanoid.WalkSpeed = Witch.Config.moveSpeed
		self.Humanoid.Sit = true
		if self.CryingSound then
			self.CryingSound:Play()
		end
	elseif newState == "Startled" then
		self.StartledAt = os.clock()
		self.Humanoid.Sit = false
		self.Humanoid.WalkSpeed = 0

		-- Stop crying, start warning growl
		if self.CryingSound then
			self.CryingSound:Stop()
		end
		if self.WarnSound then
			self.WarnSound:Play()
		end

		-- Visual startle effect - eyes glow brighter
		self:PlayStartleEffect()

		print(string.format("[Witch] STARTLED by %s!", self.StartledBy and self.StartledBy.Name or "unknown"))
	elseif newState == "Attack" then
		self.Humanoid.WalkSpeed = Witch.Config.attackSpeed

		-- Scream sound
		local scream = Instance.new("Sound")
		scream.SoundId = "rbxassetid://5152765415" -- Angry scream
		scream.Volume = 1.5
		scream.RollOffMaxDistance = 100
		scream.Parent = self.RootPart
		scream:Play()
		Debris:AddItem(scream, 3)

		-- Eyes turn full red
		self:PlayAttackEffect()

		print("[Witch] ATTACKING!")
	elseif newState == "Dead" then
		self:Die()
	end
end

function Witch:UpdateIdle(_dt: number)
	-- Check for players who might startle her
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

		local distance = (hrp.Position - self.RootPart.Position).Magnitude

		-- Check proximity startle
		if distance <= Witch.Config.startleRadius then
			self:Startle(player, "proximity")
			return
		end

		-- Check flashlight startle (larger radius)
		if distance <= Witch.Config.flashlightStartleRadius then
			local head = char:FindFirstChild("Head")
			if head then
				local flashlight = head:FindFirstChild("Flashlight")
				if flashlight and flashlight:IsA("SpotLight") and flashlight.Enabled then
					-- Check if flashlight is pointing at the Witch
					local toWitch = (self.RootPart.Position - head.Position).Unit
					local lookVector = head.CFrame.LookVector

					local dotProduct = toWitch:Dot(lookVector)
					if dotProduct > 0.7 then -- Within ~45 degrees
						self:Startle(player, "flashlight")
						return
					end
				end
			end
		end
	end
end

function Witch:UpdateStartled(_dt: number)
	local timeSinceStartle = os.clock() - self.StartledAt

	-- After startle duration, attack
	if timeSinceStartle >= Witch.Config.startleDuration then
		self:TransitionTo("Attack")
		return
	end

	-- Face the player who startled her
	if self.StartledBy then
		local char = self.StartledBy.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local direction = (hrp.Position - self.RootPart.Position)
				direction = Vector3.new(direction.X, 0, direction.Z).Unit

				if direction.Magnitude > 0.001 then
					self.RootPart.CFrame = CFrame.lookAt(self.RootPart.Position, self.RootPart.Position + direction)
				end
			end
		end
	end
end

function Witch:UpdateAttack(_dt: number)
	if not self.StartledBy then
		-- No target, return to idle (shouldn't happen)
		self:TransitionTo("Idle")
		return
	end

	local char = self.StartledBy.Character
	if not char then
		-- Target left, find new target
		self.StartledBy = self:FindNearestPlayer()
		if not self.StartledBy then
			self:TransitionTo("Idle")
		end
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		-- Target dead, find new one
		self.StartledBy = self:FindNearestPlayer()
		if not self.StartledBy then
			self:TransitionTo("Idle")
		end
		return
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local distance = (hrp.Position - self.RootPart.Position).Magnitude

	-- Attack if in range
	if distance <= Witch.Config.attackRange then
		self:ExecuteAttack()
		return
	end

	-- Chase the target
	self.Humanoid:MoveTo(hrp.Position)
end

function Witch:ExecuteAttack()
	if not self.StartledBy then
		return
	end

	local char = self.StartledBy.Character
	if not char then
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Deal massive damage with feedback
	getPlayerService():DamagePlayer(self.StartledBy, Witch.Config.damage, self.RootPart.Position)

	-- Force incapacitation if still alive
	if humanoid.Health > 0 then
		getPlayerService():IncapacitatePlayer(self.StartledBy)
	end

	-- Attack sound
	local slashSound = Instance.new("Sound")
	slashSound.SoundId = "rbxassetid://5153072658"
	slashSound.Volume = 1
	slashSound.Parent = self.RootPart
	slashSound:Play()
	Debris:AddItem(slashSound, 2)

	print(string.format("[Witch] INCAPACITATED %s!", self.StartledBy.Name))

	-- After attacking, find another target or calm down
	task.delay(1, function()
		if self.State == "Attack" then
			local newTarget = self:FindNearestPlayer()
			if newTarget then
				self.StartledBy = newTarget
			else
				-- No more targets, return to idle after a delay
				task.delay(5, function()
					if self.State == "Attack" then
						self.StartledBy = nil
						self:TransitionTo("Idle")
					end
				end)
			end
		end
	end)
end

function Witch:Startle(player: Player, reason: string)
	if self.State ~= "Idle" then
		return -- Already startled
	end

	self.StartledBy = player
	self:TransitionTo("Startled")

	print(string.format("[Witch] Startled by %s (%s)", player.Name, reason))
end

-- Called when Witch is shot
function Witch:TakeDamage(amount: number, source: Player?)
	self.Humanoid.Health = self.Humanoid.Health - amount

	-- Shooting her always startles/angers her
	if self.State == "Idle" then
		self:Startle(source or self:FindNearestPlayer() or Players:GetPlayers()[1], "damage")
	elseif self.State == "Startled" then
		-- If already startled, skip to attack immediately
		self:TransitionTo("Attack")
	end

	-- Retarget to shooter if different
	if source and source ~= self.StartledBy and self.State == "Attack" then
		self.StartledBy = source
		print(string.format("[Witch] Retargeting to %s (shooter)", source.Name))
	end

	if self.Humanoid.Health <= 0 then
		self:TransitionTo("Dead")
	end

	print(string.format("[Witch] Took %.0f damage, HP: %.0f", amount, self.Humanoid.Health))
end

function Witch:FindNearestPlayer(): Player?
	local position = self.RootPart.Position
	local nearest: Player? = nil
	local nearestDistance = math.huge

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
			nearest = player
			nearestDistance = distance
		end
	end

	return nearest
end

function Witch:PlayStartleEffect()
	-- Intensify eye glow
	for _, part in self.Model:GetDescendants() do
		if part.Name == "LeftEye" or part.Name == "RightEye" then
			if part:IsA("BasePart") then
				part.Size = part.Size * 1.5
			end
		end
	end

	-- Add point light to eyes
	local head = self.Model:FindFirstChild("Head")
	if head then
		local light = Instance.new("PointLight")
		light.Name = "StartleLight"
		light.Color = Color3.fromRGB(255, 0, 0)
		light.Brightness = 2
		light.Range = 10
		light.Parent = head
	end
end

function Witch:PlayAttackEffect()
	-- Make eyes larger and brighter
	for _, part in self.Model:GetDescendants() do
		if part.Name == "LeftEye" or part.Name == "RightEye" then
			if part:IsA("BasePart") then
				part.BrickColor = BrickColor.new("Bright red")

				-- Add stronger glow
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 50, 50)
				light.Brightness = 3
				light.Range = 8
				light.Parent = part
			end
		end
	end

	-- Darken body slightly
	for _, part in self.Model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "LeftEye" and part.Name ~= "RightEye" then
			part.BrickColor = BrickColor.new("Dusty Rose")
		end
	end
end

function Witch:Die()
	-- Stop all sounds
	if self.CryingSound then
		self.CryingSound:Stop()
	end
	if self.WarnSound then
		self.WarnSound:Stop()
	end

	-- Death sound
	local deathSound = Instance.new("Sound")
	deathSound.SoundId = "rbxassetid://5196820083" -- Final cry
	deathSound.Volume = 1
	deathSound.Parent = self.RootPart
	deathSound:Play()

	-- Ragdoll
	self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	print("[Witch] KILLED!")

	-- Cleanup after delay
	task.delay(6, function()
		self:Destroy()
	end)
end

function Witch:Destroy()
	if self.CryingSound then
		self.CryingSound:Destroy()
	end
	if self.WarnSound then
		self.WarnSound:Destroy()
	end
	if self.Model then
		self.Model:Destroy()
	end

	print("[Witch] Destroyed and cleaned up")
end

-- Suppress unused variable warning for RunService (reserved for future animation)
local _ = RunService

return Witch
