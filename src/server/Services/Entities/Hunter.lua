--!strict
--[[
    Hunter Special Infected
    High mobility, pins survivors until rescued
    
    States: Idle → Stalk → Crouch → Pounce → Pinning → Stagger → Dead
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

-- Import BaseEnemy
local BaseEnemy = require(script.Parent.Parent:WaitForChild("BaseEnemy"))

-- Hunter extends BaseEnemy
local Hunter = setmetatable({}, {__index = BaseEnemy})
Hunter.__index = Hunter

-- Types
export type HunterState = "Idle" | "Stalk" | "Crouch" | "Pounce" | "Pinning" | "Dead"

-- Configuration
Hunter.Config = {
    detectionRadius = 50,
    pounceRange = 35,
    pounceMinRange = 8,
    attackDamage = 10,
    pounceDamagePerSecond = 5,
    moveSpeed = 20,
    health = 250,
    pounceCooldown = 3,
    crouchDuration = 0.5,  -- Wind-up time
    stalkSpeed = 10,  -- Slower speed when stalking
    pounceSpeed = 60,  -- Speed during pounce
}

function Hunter.new(model: Model)
    local self = BaseEnemy.new(model)
    setmetatable(self, Hunter)
    
    -- Override state type
    self.State = "Idle" :: HunterState
    self.PinnedTarget = nil :: Player?
    self.CrouchStartTime = 0
    self.PounceVelocity = nil :: BodyVelocity?
    self.PinDamageLoop = nil
    self.PounceConnection = nil
    
    -- Set health
    self.Humanoid.Health = Hunter.Config.health
    self.Humanoid.MaxHealth = Hunter.Config.health
    
    -- Create orange color
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.BrickColor = BrickColor.new("Deep orange")
        end
    end
    
    print("[Hunter] Created new Hunter entity")
    return self
end

function Hunter:Update(dt: number)
    -- Throttle updates
    local now = os.clock()
    if now - self._lastUpdate < self._updateInterval then return end
    self._lastUpdate = now
    
    if self.State == "Dead" then return end
    
    -- State handlers
    local handlers = {
        Idle = self.UpdateIdle,
        Stalk = self.UpdateStalk,
        Crouch = self.UpdateCrouch,
        Pounce = self.UpdatePounce,
        Pinning = self.UpdatePinning,
        Stagger = self.UpdateStagger,
    }
    
    local handler = handlers[self.State]
    if handler then
        handler(self, dt)
    end
end

function Hunter:TransitionTo(newState: HunterState)
    local oldState = self.State
    self.State = newState
    self.LastStateChange = os.clock()
    
    print(string.format("[Hunter] State transition: %s → %s", oldState, newState))
    self:OnStateEnter(newState, oldState)
end

function Hunter:OnStateEnter(newState: HunterState, oldState: HunterState)
    -- Cleanup old state
    if oldState == "Pounce" and self.PounceVelocity then
        self.PounceVelocity:Destroy()
        self.PounceVelocity = nil
    end
    
    if oldState == "Pounce" and self.PounceConnection then
        self.PounceConnection:Disconnect()
        self.PounceConnection = nil
    end
    
    if oldState == "Pinning" and self.PinDamageLoop then
        self.PinDamageLoop:Disconnect()
        self.PinDamageLoop = nil
    end
    
    -- Initialize new state
    if newState == "Stalk" then
        self.Humanoid.WalkSpeed = Hunter.Config.stalkSpeed
    elseif newState == "Crouch" then
        self.Humanoid.WalkSpeed = 0
        self.CrouchStartTime = os.clock()
        
        -- Play growl sound
        local growl = Instance.new("Sound")
        growl.SoundId = "rbxassetid://131060197"  -- Placeholder growl sound
        growl.Volume = 0.5
        growl.Parent = self.RootPart
        growl:Play()
        Debris:AddItem(growl, 1)
        
        print("[Hunter] Crouching - telegraphing pounce")
    elseif newState == "Pounce" then
        self:ExecutePounce()
    elseif newState == "Pinning" then
        self:StartPinDamageLoop()
    elseif newState == "Stagger" then
        self.Humanoid.WalkSpeed = Hunter.Config.moveSpeed
        task.delay(1, function()
            if self.State == "Stagger" then
                self:TransitionTo("Stalk")
            end
        end)
    elseif newState == "Dead" then
        self:CleanupPinning()
        self:Die()
    end
end

function Hunter:UpdateIdle(dt: number)
    -- Look for targets
    local target = self:DetectTarget()
    if target then
        self.Target = target
        self:TransitionTo("Stalk")
    end
end

function Hunter:UpdateStalk(dt: number)
    if not self.Target then
        self:TransitionTo("Idle")
        return
    end
    
    local distance = self:GetDistanceToTarget()
    
    -- Get into pounce range
    if distance > Hunter.Config.pounceRange then
        self:MoveToTarget()
    elseif distance >= Hunter.Config.pounceMinRange then
        -- In range, start crouch wind-up
        self:TransitionTo("Crouch")
    else
        -- Too close, back up
        self:BackAwayFromTarget()
    end
end

function Hunter:UpdateCrouch(dt: number)
    -- Wind-up animation (telegraph to players)
    if os.clock() - self.CrouchStartTime >= Hunter.Config.crouchDuration then
        self:TransitionTo("Pounce")
    end
end

function Hunter:UpdatePounce(dt: number)
    -- Pounce is handled by physics, just check timeout
    if os.clock() - self.LastStateChange > 1.5 then
        -- Missed - transition back to stalk
        if self.State == "Pounce" then
            self:TransitionTo("Stalk")
        end
    end
end

function Hunter:UpdatePinning(dt: number)
    if not self.PinnedTarget then
        self:TransitionTo("Stalk")
        return
    end
    
    -- Check if target is still valid
    local char = self.PinnedTarget.Character
    if not char or char:FindFirstChildOfClass("Humanoid").Health <= 0 then
        self:CleanupPinning()
        self:TransitionTo("Stalk")
        return
    end
    
    -- Stay attached to target
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        self.RootPart.CFrame = hrp.CFrame * CFrame.new(0, 2, 0)
    end
end

function Hunter:UpdateStagger(dt: number)
    -- Handled in OnStateEnter
end

function Hunter:ExecutePounce()
    if not self.Target then
        self:TransitionTo("Idle")
        return
    end
    
    local char = self.Target.Character
    if not char then return end
    
    local targetPos = char:FindFirstChild("HumanoidRootPart")
    if not targetPos then return end
    
    -- Calculate pounce trajectory
    local direction = (targetPos.Position - self.RootPart.Position).Unit
    local distance = self:GetDistanceToTarget()
    
    -- Apply velocity for pounce
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Velocity = direction * Hunter.Config.pounceSpeed + Vector3.new(0, 30, 0)  -- Arc upward
    bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bodyVelocity.Parent = self.RootPart
    self.PounceVelocity = bodyVelocity
    
    print(string.format("[Hunter] Pouncing at target with velocity: %s", tostring(bodyVelocity.Velocity)))
    
    -- Setup hit detection
    self:SetupPounceHitDetection()
end

function Hunter:SetupPounceHitDetection()
    local hitCount = 0
    
    self.PounceConnection = self.RootPart.Touched:Connect(function(hit)
        if self.State ~= "Pounce" then return end
        
        local hitModel = hit:FindFirstAncestorOfClass("Model")
        if not hitModel then return end
        
        -- Check if hit a player
        local player = Players:GetPlayerFromCharacter(hitModel)
        if player and player == self.Target then
            hitCount += 1
            if hitCount == 1 then  -- Only process first hit
                print("[Hunter] Pounce hit target!")
                self:PinTarget(player)
                self:TransitionTo("Pinning")
            end
        elseif hit.Anchored then
            -- Hit wall or obstacle
            print("[Hunter] Pounce hit obstacle")
            self:TransitionTo("Stagger")
        end
    end)
    
    -- Timeout if miss
    task.delay(1.5, function()
        if self.State == "Pounce" then
            print("[Hunter] Pounce timed out")
            self:TransitionTo("Stalk")
        end
    end)
end

function Hunter:PinTarget(player: Player)
    self.PinnedTarget = player
    
    local char = player.Character
    if not char then return end
    
    -- Disable player movement
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
    end
    
    -- Set attributes for rescue system
    char:SetAttribute("IsPinned", true)
    char:SetAttribute("PinnedBy", self.Model:GetAttribute("EntityId"))
    
    -- Position hunter on top
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        self.RootPart.CFrame = hrp.CFrame * CFrame.new(0, 2, 0)
    end
    
    print(string.format("[Hunter] Pinned player %s", player.Name))
end

function Hunter:StartPinDamageLoop()
    if not self.PinnedTarget then return end
    
    self.PinDamageLoop = RunService.Heartbeat:Connect(function()
        if self.State ~= "Pinning" or not self.PinnedTarget then return end
        
        local char = self.PinnedTarget.Character
        if not char then return end
        
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            humanoid:TakeDamage(Hunter.Config.pounceDamagePerSecond)
        end
    end)
end

function Hunter:CleanupPinning()
    if self.PinnedTarget then
        local char = self.PinnedTarget.Character
        if char then
            -- Restore player movement
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.WalkSpeed = 16
                humanoid.JumpPower = 50
            end
            
            -- Clear attributes
            char:SetAttribute("IsPinned", false)
            char:SetAttribute("PinnedBy", nil)
        end
        
        print(string.format("[Hunter] Released player %s", self.PinnedTarget.Name))
        self.PinnedTarget = nil
    end
end

function Hunter:BackAwayFromTarget()
    if not self.Target then return end
    
    local char = self.Target.Character
    if not char then return end
    
    local targetPos = char:FindFirstChild("HumanoidRootPart")
    if not targetPos then return end
    
    -- Move away from target
    local awayDirection = (self.RootPart.Position - targetPos.Position).Unit
    local targetPosition = self.RootPart.Position + awayDirection * 10
    
    self.Humanoid:MoveTo(targetPosition)
end

function Hunter:TakeDamage(amount: number, source: Player?)
    self.Humanoid.Health -= amount
    
    if self.Humanoid.Health <= 0 then
        self:TransitionTo("Dead")
    else
        -- Stagger chance
        if math.random() < 0.3 then
            self:TransitionTo("Stagger")
        end
        
        -- Release pin if taking damage while pinning
        if self.State == "Pinning" then
            self:CleanupPinning()
            self:TransitionTo("Stagger")
        end
    end
end

function Hunter:Die()
    self:CleanupPinning()
    
    -- Ragdoll
    self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    
    print("[Hunter] Died")
    
    -- Cleanup after delay
    task.delay(5, function()
        self.Model:Destroy()
    end)
end

-- Rescue function - called by other players
function Hunter:Rescue()
    if self.State == "Pinning" then
        print("[Hunter] Being rescued!")
        self:CleanupPinning()
        self:TransitionTo("Stagger")
    end
end

return Hunter
