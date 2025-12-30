--!strict
--[[
    Smoker Special Infected
    Tongue grab from distance, drags survivors toward it

    States: Idle → Stalk → Aim → Grab → Dragging → Stagger → Dead
]]

local Debris = game:GetService("Debris")
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

-- Smoker extends BaseEnemy
local Smoker = setmetatable({}, { __index = BaseEnemy })
Smoker.__index = Smoker

-- Types
export type SmokerState = "Idle" | "Stalk" | "Aim" | "Grab" | "Dragging" | "Stagger" | "Dead"

-- Configuration
Smoker.Config = {
	detectionRadius = 60,
	tongueRange = 50,
	tongueMinRange = 15,
	attackDamage = 3,
	dragDamagePerSecond = 3,
	moveSpeed = 12,
	health = 250,
	tongueSpeed = 80,
	aimDuration = 0.8, -- Wind-up time before tongue
	stalkSpeed = 8,
}

function Smoker.new(model: Model)
	local self = BaseEnemy.new(model)
	setmetatable(self, Smoker)

	-- Entity type identifier
	self.Type = "Smoker"

	-- Override state type
	self.State = "Idle" :: SmokerState
	self.Config = table.clone(Smoker.Config)
	self.GrabbedTarget = nil :: Player?
	self.AimStartTime = 0
	self.TongueBeam = nil :: Beam?
	self.TongueAttachment0 = nil :: Attachment?
	self.TongueAttachment1 = nil :: Attachment?
	self.DragDamageLoop = nil :: RBXScriptConnection?
	self.DragConnection = nil :: RBXScriptConnection?

	-- Set health
	self.Humanoid.Health = Smoker.Config.health
	self.Humanoid.MaxHealth = Smoker.Config.health

	-- Create dark gray color (smoky appearance)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.BrickColor = BrickColor.new("Dark stone grey")
		end
	end

	print("[Smoker] Created new Smoker entity")
	return self
end

function Smoker:Update(dt: number)
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
		Stalk = self.UpdateStalk,
		Aim = self.UpdateAim,
		Grab = self.UpdateGrab,
		Dragging = self.UpdateDragging,
		Stagger = self.UpdateStagger,
	}

	local handler = handlers[self.State]
	if handler then
		handler(self, dt)
	end
end

function Smoker:TransitionTo(newState: SmokerState)
	local oldState = self.State
	self.State = newState
	self.LastStateChange = os.clock()

	print(string.format("[Smoker] State transition: %s → %s", oldState, newState))
	self:OnStateEnter(newState, oldState)
end

function Smoker:OnStateEnter(newState: SmokerState, oldState: SmokerState)
	-- Cleanup old state
	if oldState == "Grab" or oldState == "Dragging" then
		self:CleanupTongue()
	end

	-- Initialize new state
	if newState == "Stalk" then
		self.Humanoid.WalkSpeed = Smoker.Config.stalkSpeed
	elseif newState == "Aim" then
		self.Humanoid.WalkSpeed = 0
		self.AimStartTime = os.clock()

		-- Play cough/wheeze sound
		local cough = Instance.new("Sound")
		cough.SoundId = "rbxassetid://5982661617" -- Placeholder cough sound
		cough.Volume = 0.6
		cough.Parent = self.RootPart
		cough:Play()
		Debris:AddItem(cough, 2)

		print("[Smoker] Aiming tongue - telegraphing attack")
	elseif newState == "Grab" then
		self:ExecuteTongueGrab()
	elseif newState == "Dragging" then
		self:StartDragDamageLoop()
	elseif newState == "Stagger" then
		self.Humanoid.WalkSpeed = Smoker.Config.moveSpeed
		task.delay(1.5, function()
			if self.State == "Stagger" then
				self:TransitionTo("Stalk")
			end
		end)
	elseif newState == "Dead" then
		self:CleanupTongue()
		self:Die()
	end
end

function Smoker:UpdateIdle(_dt: number)
	-- Look for targets
	self.Target = self:DetectTarget()

	if self.Target and self:IsTargetValid() then
		self:TransitionTo("Stalk")
	end
end

function Smoker:UpdateStalk(_dt: number)
	-- Move toward target but maintain distance for tongue grab
	if not self.Target or not self:IsTargetValid() then
		self.Target = nil
		self:TransitionTo("Idle")
		return
	end

	local distance = self:GetDistanceToTarget()

	-- Check if in optimal tongue range
	if distance <= Smoker.Config.tongueRange and distance >= Smoker.Config.tongueMinRange then
		-- Check line of sight
		if self:HasLineOfSightToTarget() then
			self:TransitionTo("Aim")
			return
		end
	end

	-- Move toward target if too far
	if distance > Smoker.Config.tongueRange then
		self:MoveToTarget()
	elseif distance < Smoker.Config.tongueMinRange then
		-- Back away if too close
		self:BackAwayFromTarget()
	end
end

function Smoker:UpdateAim(_dt: number)
	-- Wind-up before tongue grab
	local elapsed = os.clock() - self.AimStartTime

	if elapsed >= Smoker.Config.aimDuration then
		self:TransitionTo("Grab")
	end

	-- Lose target if they move out of range or break LOS
	if not self.Target or not self:IsTargetValid() then
		self.Target = nil
		self:TransitionTo("Stalk")
		return
	end

	local distance = self:GetDistanceToTarget()
	if distance > Smoker.Config.tongueRange or not self:HasLineOfSightToTarget() then
		self:TransitionTo("Stalk")
	end
end

function Smoker:HasLineOfSightToTarget(): boolean
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

function Smoker:UpdateGrab(_dt: number)
	-- Tongue is extending - handled by ExecuteTongueGrab
end

function Smoker:UpdateDragging(_dt: number)
	-- Check if target is still valid
	if not self.GrabbedTarget then
		self:TransitionTo("Stalk")
		return
	end

	local char = self.GrabbedTarget.Character
	if not char then
		self:ReleaseTarget()
		self:TransitionTo("Stalk")
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		self:ReleaseTarget()
		self:TransitionTo("Stalk")
		return
	end

	-- Pull target toward Smoker
	local targetHRP = char:FindFirstChild("HumanoidRootPart")
	if targetHRP then
		local direction = (self.RootPart.Position - targetHRP.Position).Unit
		local pullForce = direction * 15 -- Pull speed

		-- Apply movement toward Smoker
		targetHRP.AssemblyLinearVelocity = Vector3.new(pullForce.X, 0, pullForce.Z)

		-- Check if target reached Smoker (grab complete)
		local distance = (self.RootPart.Position - targetHRP.Position).Magnitude
		if distance < 5 then
			-- Target reached, continue damage but stop pull
			targetHRP.AssemblyLinearVelocity = Vector3.zero
		end
	end

	-- Update tongue beam
	self:UpdateTongueBeam()
end

function Smoker:UpdateStagger(_dt: number)
	-- Handled in OnStateEnter
end

function Smoker:ExecuteTongueGrab()
	if not self.Target then
		self:TransitionTo("Idle")
		return
	end

	local char = self.Target.Character
	if not char then
		return
	end

	local targetHRP = char:FindFirstChild("HumanoidRootPart")
	if not targetHRP then
		return
	end

	-- Create tongue visual (beam)
	self:CreateTongueBeam(targetHRP)

	-- Set grabbed target
	self.GrabbedTarget = self.Target

	-- Disable player movement
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	-- Set grabbed attributes
	char:SetAttribute("IsGrabbed", true)
	char:SetAttribute("GrabbedBy", self.Model:GetAttribute("EntityId"))

	print(string.format("[Smoker] Grabbed player %s", self.GrabbedTarget.Name))
	self:TransitionTo("Dragging")
end

function Smoker:CreateTongueBeam(targetPart: BasePart)
	-- Create attachments
	self.TongueAttachment0 = Instance.new("Attachment")
	self.TongueAttachment0.Name = "TongueAttachment"
	self.TongueAttachment0.Position = Vector3.new(0, 0.5, -1) -- Mouth position
	self.TongueAttachment0.Parent = self.RootPart

	self.TongueAttachment1 = Instance.new("Attachment")
	self.TongueAttachment1.Name = "TongueTargetAttachment"
	self.TongueAttachment1.Parent = targetPart

	-- Create beam
	self.TongueBeam = Instance.new("Beam")
	self.TongueBeam.Name = "TongueBeam"
	self.TongueBeam.Attachment0 = self.TongueAttachment0
	self.TongueBeam.Attachment1 = self.TongueAttachment1
	self.TongueBeam.Color = ColorSequence.new(Color3.fromRGB(139, 90, 43)) -- Brown tongue color
	self.TongueBeam.Width0 = 0.3
	self.TongueBeam.Width1 = 0.2
	self.TongueBeam.FaceCamera = true
	self.TongueBeam.Parent = self.RootPart
end

function Smoker:UpdateTongueBeam()
	-- Beam updates automatically via attachments
end

function Smoker:CleanupTongue()
	if self.TongueBeam then
		self.TongueBeam:Destroy()
		self.TongueBeam = nil
	end

	if self.TongueAttachment0 then
		self.TongueAttachment0:Destroy()
		self.TongueAttachment0 = nil
	end

	if self.TongueAttachment1 then
		self.TongueAttachment1:Destroy()
		self.TongueAttachment1 = nil
	end

	if self.DragDamageLoop then
		self.DragDamageLoop:Disconnect()
		self.DragDamageLoop = nil
	end

	self:ReleaseTarget()
end

function Smoker:ReleaseTarget()
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

			-- Stop any velocity
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.AssemblyLinearVelocity = Vector3.zero
			end
		end

		print(string.format("[Smoker] Released player %s", self.GrabbedTarget.Name))
		self.GrabbedTarget = nil
	end
end

function Smoker:StartDragDamageLoop()
	self.DragDamageLoop = RunService.Heartbeat:Connect(function(dt)
		if self.State ~= "Dragging" or not self.GrabbedTarget then
			return
		end

		local char = self.GrabbedTarget.Character
		if not char then
			return
		end

		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			-- Use PlayerService for damage feedback
			getPlayerService():DamagePlayer(
				self.GrabbedTarget,
				Smoker.Config.dragDamagePerSecond * dt,
				self.RootPart.Position
			)
		end
	end)
end

function Smoker:BackAwayFromTarget()
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

	-- Move away from target
	local awayDirection = (self.RootPart.Position - targetPos.Position).Unit
	local targetPosition = self.RootPart.Position + awayDirection * 10

	self.Humanoid:MoveTo(targetPosition)
end

function Smoker:TakeDamage(amount: number, _source: Player?)
	self.Humanoid.Health -= amount

	if self.Humanoid.Health <= 0 then
		self:TransitionTo("Dead")
	else
		-- Stagger chance (higher than Hunter since Smoker is more vulnerable)
		if math.random() < 0.4 then
			self:TransitionTo("Stagger")
		end

		-- Release grab if taking damage while dragging
		if self.State == "Dragging" then
			self:CleanupTongue()
			self:TransitionTo("Stagger")
		end
	end
end

function Smoker:Die()
	self:CleanupTongue()

	-- Ragdoll
	self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	print("[Smoker] Died")

	-- Cleanup after delay
	task.delay(5, function()
		self:Destroy()
	end)
end

-- Rescue function - called by other players
function Smoker:Rescue()
	if self.State == "Dragging" then
		print("[Smoker] Being rescued!")
		self:CleanupTongue()
		self:TransitionTo("Stagger")
	end
end

-- Proper cleanup for all connections and resources
function Smoker:Destroy()
	-- Cleanup tongue
	self:CleanupTongue()

	-- Disconnect drag damage loop
	if self.DragDamageLoop then
		self.DragDamageLoop:Disconnect()
		self.DragDamageLoop = nil
	end

	-- Destroy model
	if self.Model then
		self.Model:Destroy()
	end

	print("[Smoker] Destroyed and cleaned up")
end

return Smoker
