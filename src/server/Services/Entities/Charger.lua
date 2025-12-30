--!strict
--[[
    Charger Special Infected
    High HP bruiser that charges and grabs one survivor, slamming them repeatedly
    Knocks aside other survivors during charge

    States: Idle → Chase → WindUp → Charge → Slamming → Stagger → Dead
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

-- Charger extends BaseEnemy
local Charger = setmetatable({}, { __index = BaseEnemy })
Charger.__index = Charger

-- Types
export type ChargerState = "Idle" | "Chase" | "WindUp" | "Charge" | "Slamming" | "Stagger" | "Dead"

-- Configuration
Charger.Config = {
	health = 600,
	detectionRadius = 45,
	chargeRange = 40, -- Max distance to start charge
	chargeMinRange = 8, -- Minimum distance to charge
	chargeDamage = 10, -- Initial impact damage
	slamDamage = 15, -- Damage per slam
	knockbackDamage = 5, -- Damage to knocked-aside survivors
	moveSpeed = 14,
	chargeSpeed = 50, -- Speed during charge
	windUpDuration = 0.8, -- Telegraph time before charge
	slamInterval = 1.2, -- Time between slams
	maxChargeDistance = 60, -- Max distance for a single charge
	chargeCooldown = 5, -- Cooldown after charge ends
	knockbackForce = 40, -- Force applied to knocked survivors
}

function Charger.new(model: Model)
	local self = BaseEnemy.new(model)
	setmetatable(self, Charger)

	-- Entity type identifier
	self.Type = "Charger"

	-- Override state type
	self.State = "Idle" :: ChargerState
	self.Config = table.clone(Charger.Config)

	-- Charger-specific state
	self.GrabbedTarget = nil :: Player?
	self.WindUpStartTime = 0
	self.ChargeStartTime = 0
	self.ChargeStartPosition = Vector3.zero
	self.ChargeDirection = Vector3.zero
	self.LastSlam = 0
	self.LastCharge = 0
	self.IsCharging = false
	self.SlamLoop = nil :: RBXScriptConnection?
	self.ChargeConnection = nil :: RBXScriptConnection?
	self.HitPlayers = {} :: { [Player]: boolean } -- Track who was hit during this charge

	-- Set health
	self.Humanoid.MaxHealth = Charger.Config.health
	self.Humanoid.Health = Charger.Config.health
	self.Humanoid.WalkSpeed = Charger.Config.moveSpeed
	self.Humanoid.JumpPower = 30

	-- Make Charger bulky and gray with one large arm
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.BrickColor = BrickColor.new("Dark stone grey")
			part.Material = Enum.Material.SmoothPlastic

			-- Make right arm huge (the charging arm)
			if part.Name == "Right Arm" or part.Name == "RightUpperArm" or part.Name == "RightLowerArm" then
				part.Size = part.Size * Vector3.new(2, 1.3, 2)
				part.BrickColor = BrickColor.new("Medium stone grey")
			end

			-- Make left arm smaller/withered
			if part.Name == "Left Arm" or part.Name == "LeftUpperArm" or part.Name == "LeftLowerArm" then
				part.Size = part.Size * Vector3.new(0.5, 0.8, 0.5)
			end

			-- Bulkier torso
			if part.Name == "Torso" or part.Name == "UpperTorso" then
				part.Size = part.Size * Vector3.new(1.3, 1.1, 1.2)
			end
		end
	end

	-- Create charger sounds
	self:CreateChargerSounds()

	print("[Charger] Created new Charger entity - HP:", Charger.Config.health)
	return self
end

function Charger:CreateChargerSounds()
	-- Heavy breathing/growling
	local growl = Instance.new("Sound")
	growl.Name = "ChargerGrowl"
	growl.SoundId = "rbxassetid://131060197" -- Deep growl
	growl.Volume = 0.5
	growl.Looped = true
	growl.RollOffMaxDistance = 50
	growl.PlaybackSpeed = 0.6 -- Lower pitch
	growl.Parent = self.RootPart
	growl:Play()
	self.GrowlSound = growl
end

function Charger:Update(dt: number)
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
		WindUp = self.UpdateWindUp,
		Charge = self.UpdateCharge,
		Slamming = self.UpdateSlamming,
		Stagger = self.UpdateStagger,
	}

	local handler = handlers[self.State]
	if handler then
		handler(self, dt)
	end
end

function Charger:TransitionTo(newState: ChargerState)
	local oldState = self.State
	self.State = newState
	self.LastStateChange = os.clock()

	print(string.format("[Charger] State transition: %s → %s", oldState, newState))
	self:OnStateEnter(newState, oldState)
end

function Charger:OnStateEnter(newState: ChargerState, oldState: ChargerState)
	-- Cleanup old state
	if oldState == "Charge" then
		self.IsCharging = false
		if self.ChargeConnection then
			self.ChargeConnection:Disconnect()
			self.ChargeConnection = nil
		end
		table.clear(self.HitPlayers)
	end

	if oldState == "Slamming" and self.SlamLoop then
		self.SlamLoop:Disconnect()
		self.SlamLoop = nil
	end

	-- Initialize new state
	if newState == "Chase" then
		self.Humanoid.WalkSpeed = Charger.Config.moveSpeed
	elseif newState == "WindUp" then
		self.Humanoid.WalkSpeed = 0
		self.WindUpStartTime = os.clock()
		self:PlayWindUpSound()
	elseif newState == "Charge" then
		self:ExecuteCharge()
	elseif newState == "Slamming" then
		self.Humanoid.WalkSpeed = 0
		self:StartSlamLoop()
	elseif newState == "Stagger" then
		self.Humanoid.WalkSpeed = 0
		task.delay(1.5, function()
			if self.State == "Stagger" then
				self:TransitionTo("Chase")
			end
		end)
	elseif newState == "Dead" then
		self:CleanupGrab()
		self:Die()
	end
end

function Charger:UpdateIdle(_dt: number)
	self.Target = self:DetectTarget()

	if self.Target and self:IsTargetValid() then
		self:TransitionTo("Chase")
	end
end

function Charger:UpdateChase(_dt: number)
	if not self.Target or not self:IsTargetValid() then
		self.Target = nil
		self:TransitionTo("Idle")
		return
	end

	local distance = self:GetDistanceToTarget()
	local now = os.clock()

	-- Check if can charge
	if distance <= Charger.Config.chargeRange and distance >= Charger.Config.chargeMinRange then
		if now - self.LastCharge > Charger.Config.chargeCooldown then
			if self:HasLineOfSightToTarget() then
				self:TransitionTo("WindUp")
				return
			end
		end
	end

	-- Chase target
	self:MoveToTarget()
end

function Charger:UpdateWindUp(_dt: number)
	-- Telegraph wind-up
	local elapsed = os.clock() - self.WindUpStartTime

	-- Face target during wind-up
	if self.Target then
		local char = self.Target.Character
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

	if elapsed >= Charger.Config.windUpDuration then
		self:TransitionTo("Charge")
	end
end

function Charger:UpdateCharge(_dt: number)
	if not self.IsCharging then
		return
	end

	-- Check if charge should end
	local distanceTraveled = (self.RootPart.Position - self.ChargeStartPosition).Magnitude

	-- End charge if traveled max distance or hit a wall
	if distanceTraveled >= Charger.Config.maxChargeDistance then
		self:EndCharge()
		return
	end

	-- Timeout safety
	if os.clock() - self.ChargeStartTime > 3 then
		self:EndCharge()
	end
end

function Charger:UpdateSlamming(_dt: number)
	if not self.GrabbedTarget then
		self:TransitionTo("Stagger")
		return
	end

	-- Check if target is still valid
	local char = self.GrabbedTarget.Character
	if not char then
		self:CleanupGrab()
		self:TransitionTo("Stagger")
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		self:CleanupGrab()
		self:TransitionTo("Chase")
		return
	end

	-- Keep grabbed target in position
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		-- Hold target in front and slightly up
		local holdPosition = self.RootPart.Position + self.RootPart.CFrame.LookVector * 3 + Vector3.new(0, 2, 0)
		hrp.CFrame = CFrame.new(holdPosition)
	end
end

function Charger:UpdateStagger(_dt: number)
	-- Handled in OnStateEnter
end

function Charger:PlayWindUpSound()
	local roar = Instance.new("Sound")
	roar.Name = "ChargerRoar"
	roar.SoundId = "rbxassetid://131060197"
	roar.Volume = 1
	roar.PlaybackSpeed = 0.5
	roar.Parent = self.RootPart
	roar:Play()
	Debris:AddItem(roar, 2)

	print("[Charger] ROARING - Charge incoming!")
end

function Charger:ExecuteCharge()
	if not self.Target then
		self:TransitionTo("Idle")
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

	-- Calculate charge direction
	local direction = (targetHrp.Position - self.RootPart.Position)
	direction = Vector3.new(direction.X, 0, direction.Z).Unit

	self.ChargeDirection = direction
	self.ChargeStartPosition = self.RootPart.Position
	self.ChargeStartTime = os.clock()
	self.IsCharging = true
	self.LastCharge = os.clock()
	table.clear(self.HitPlayers)

	-- Face charge direction
	self.RootPart.CFrame = CFrame.lookAt(self.RootPart.Position, self.RootPart.Position + direction)

	-- Apply charge velocity
	self.RootPart.AssemblyLinearVelocity = direction * Charger.Config.chargeSpeed

	-- Play charge sound
	local chargeSound = Instance.new("Sound")
	chargeSound.SoundId = "rbxassetid://5153382847"
	chargeSound.Volume = 1
	chargeSound.PlaybackSpeed = 0.7
	chargeSound.Parent = self.RootPart
	chargeSound:Play()
	Debris:AddItem(chargeSound, 3)

	print("[Charger] CHARGING!")

	-- Setup collision detection
	self:SetupChargeHitDetection()
end

function Charger:SetupChargeHitDetection()
	self.ChargeConnection = self.RootPart.Touched:Connect(function(hit)
		if not self.IsCharging then
			return
		end

		-- Check if hit an obstacle
		if hit.Anchored and hit.CanCollide then
			-- Hit a wall - end charge
			print("[Charger] Hit obstacle during charge")
			self:EndCharge()
			return
		end

		-- Check if hit a player
		local hitModel = hit:FindFirstAncestorOfClass("Model")
		if not hitModel then
			return
		end

		local player = Players:GetPlayerFromCharacter(hitModel)
		if not player then
			return
		end

		-- Don't hit same player twice in one charge
		if self.HitPlayers[player] then
			return
		end
		self.HitPlayers[player] = true

		-- Check if this is our primary target
		if player == self.Target and not self.GrabbedTarget then
			-- Grab this player
			self:GrabTarget(player)
			self:EndCharge()
			self:TransitionTo("Slamming")
		else
			-- Knock aside other players
			self:KnockbackPlayer(player)
		end
	end)

	-- Timeout
	task.delay(3, function()
		if self.IsCharging then
			self:EndCharge()
		end
	end)
end

function Charger:GrabTarget(player: Player)
	self.GrabbedTarget = player

	local char = player.Character
	if not char then
		return
	end

	-- Disable player movement
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	-- Set attributes for rescue system
	char:SetAttribute("IsGrabbed", true)
	char:SetAttribute("GrabbedBy", self.Model:GetAttribute("EntityId"))

	-- Deal initial impact damage
	getPlayerService():DamagePlayer(player, Charger.Config.chargeDamage, self.RootPart.Position)

	print(string.format("[Charger] Grabbed player %s", player.Name))
end

function Charger:KnockbackPlayer(player: Player)
	local char = player.Character
	if not char then
		return
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Calculate knockback direction (sideways from charge direction)
	local toPlayer = (hrp.Position - self.RootPart.Position)
	local sideDirection = self.ChargeDirection:Cross(Vector3.new(0, 1, 0)).Unit

	-- Determine which side the player is on
	if toPlayer:Dot(sideDirection) < 0 then
		sideDirection = -sideDirection
	end

	-- Apply knockback
	local knockbackVelocity = (sideDirection + Vector3.new(0, 0.5, 0)) * Charger.Config.knockbackForce
	hrp.AssemblyLinearVelocity = knockbackVelocity

	-- Deal knockback damage
	getPlayerService():DamagePlayer(player, Charger.Config.knockbackDamage, self.RootPart.Position)

	print(string.format("[Charger] Knocked aside player %s", player.Name))
end

function Charger:EndCharge()
	self.IsCharging = false
	self.RootPart.AssemblyLinearVelocity = Vector3.zero

	if self.ChargeConnection then
		self.ChargeConnection:Disconnect()
		self.ChargeConnection = nil
	end

	-- If we didn't grab anyone, stagger
	if not self.GrabbedTarget and self.State == "Charge" then
		self:TransitionTo("Stagger")
	end
end

function Charger:StartSlamLoop()
	if not self.GrabbedTarget then
		return
	end

	self.LastSlam = os.clock()

	-- Do initial slam
	self:ExecuteSlam()

	-- Start slam loop
	self.SlamLoop = RunService.Heartbeat:Connect(function(_dt)
		if self.State ~= "Slamming" or not self.GrabbedTarget then
			return
		end

		local now = os.clock()
		if now - self.LastSlam >= Charger.Config.slamInterval then
			self:ExecuteSlam()
			self.LastSlam = now
		end
	end)
end

function Charger:ExecuteSlam()
	if not self.GrabbedTarget then
		return
	end

	local char = self.GrabbedTarget.Character
	if not char then
		return
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Slam animation: lift up then slam down
	local startPos = hrp.Position

	-- Lift
	hrp.CFrame = CFrame.new(startPos + Vector3.new(0, 5, 0))

	-- Slam down after short delay
	task.delay(0.3, function()
		if not self.GrabbedTarget or self.State ~= "Slamming" then
			return
		end

		local slamTarget = self.GrabbedTarget
		local slamChar = slamTarget.Character
		if not slamChar then
			return
		end

		local slamHrp = slamChar:FindFirstChild("HumanoidRootPart")
		if not slamHrp then
			return
		end

		-- Slam to ground
		local groundPos = self.RootPart.Position + self.RootPart.CFrame.LookVector * 3
		slamHrp.CFrame = CFrame.new(groundPos)

		-- Deal slam damage
		getPlayerService():DamagePlayer(slamTarget, Charger.Config.slamDamage, self.RootPart.Position)

		-- Ground impact effect
		self:CreateSlamEffect(groundPos)

		print(string.format("[Charger] Slammed %s for %d damage", slamTarget.Name, Charger.Config.slamDamage))
	end)
end

function Charger:CreateSlamEffect(position: Vector3)
	-- Ground crack visual
	local crack = Instance.new("Part")
	crack.Shape = Enum.PartType.Cylinder
	crack.Size = Vector3.new(0.5, 6, 6)
	crack.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	crack.Material = Enum.Material.Slate
	crack.BrickColor = BrickColor.new("Dark stone grey")
	crack.Anchored = true
	crack.CanCollide = false
	crack.Parent = workspace
	Debris:AddItem(crack, 2)

	-- Slam sound
	local slamSound = Instance.new("Sound")
	slamSound.SoundId = "rbxassetid://287390459"
	slamSound.Volume = 1
	slamSound.PlaybackSpeed = 0.6
	slamSound.Parent = self.RootPart
	slamSound:Play()
	Debris:AddItem(slamSound, 2)
end

function Charger:HasLineOfSightToTarget(): boolean
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

function Charger:CleanupGrab()
	if self.GrabbedTarget then
		local char = self.GrabbedTarget.Character
		if char then
			-- Restore player movement
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = 16
				humanoid.JumpPower = 50
			end

			-- Clear attributes
			char:SetAttribute("IsGrabbed", false)
			char:SetAttribute("GrabbedBy", nil)
		end

		print(string.format("[Charger] Released player %s", self.GrabbedTarget.Name))
		self.GrabbedTarget = nil
	end
end

function Charger:TakeDamage(amount: number, source: Player?)
	self.Humanoid.Health = self.Humanoid.Health - amount

	if self.Humanoid.Health <= 0 then
		self:TransitionTo("Dead")
	else
		-- Lower stagger chance for Charger (tankier)
		if math.random() < 0.15 then
			if self.State == "Slamming" then
				self:CleanupGrab()
			end
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

-- Rescue function - called by other players shooting the Charger
function Charger:Rescue()
	if self.State == "Slamming" then
		print("[Charger] Being rescued!")
		self:CleanupGrab()
		self:TransitionTo("Stagger")
	end
end

function Charger:Die()
	self:CleanupGrab()

	-- Stop sounds
	if self.GrowlSound then
		self.GrowlSound:Stop()
	end

	-- Ragdoll
	self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	print("[Charger] Died")

	task.delay(5, function()
		self:Destroy()
	end)
end

function Charger:Destroy()
	-- Cleanup grab state
	self:CleanupGrab()

	-- Stop charge
	if self.IsCharging and self.RootPart then
		self.RootPart.AssemblyLinearVelocity = Vector3.zero
		self.IsCharging = false
	end

	-- Disconnect charge detection
	if self.ChargeConnection then
		self.ChargeConnection:Disconnect()
		self.ChargeConnection = nil
	end

	-- Disconnect slam loop
	if self.SlamLoop then
		self.SlamLoop:Disconnect()
		self.SlamLoop = nil
	end

	-- Stop sounds
	if self.GrowlSound then
		self.GrowlSound:Destroy()
	end

	-- Destroy model
	if self.Model then
		self.Model:Destroy()
	end

	print("[Charger] Destroyed and cleaned up")
end

return Charger
