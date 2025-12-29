# Enemy Patterns & Special Infected

## Table of Contents
1. [Base Enemy FSM](#base-enemy-fsm)
2. [Detection Systems](#detection-systems)
3. [Common Infected (Horde)](#common-infected-horde)
4. [Special Infected](#special-infected)
   - [Hunter (Pounce)](#hunter-pounce)
   - [Smoker (Grab)](#smoker-grab)
   - [Boomer (Bile)](#boomer-bile)
   - [Tank (Boss)](#tank-boss)
   - [Witch (Avoidance)](#witch-avoidance)
   - [Charger](#charger)
   - [Spitter (Area Denial)](#spitter-area-denial)
5. [Optimization Patterns](#optimization-patterns)

---

## Base Enemy FSM

All enemies share a common finite state machine structure:

```lua
--!strict
export type EnemyState = "Idle" | "Patrol" | "Chase" | "Attack" | "Stagger" | "Dead"

local BaseEnemy = {}
BaseEnemy.__index = BaseEnemy

function BaseEnemy.new(model: Model)
    local self = setmetatable({}, BaseEnemy)
    
    self.Model = model
    self.Humanoid = model:FindFirstChildOfClass("Humanoid")
    self.RootPart = model:FindFirstChild("HumanoidRootPart")
    
    self.State = "Idle" :: EnemyState
    self.Target = nil :: Player?
    self.LastStateChange = os.clock()
    
    -- Performance throttling
    self._lastUpdate = 0
    self._updateInterval = 0.0625  -- 16 Hz
    
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
    if now - self._lastUpdate < self._updateInterval then return end
    self._lastUpdate = now
    
    if self.State == "Dead" then return end
    
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

function BaseEnemy:OnStateEnter(newState: EnemyState, oldState: EnemyState)
    -- Override in subclasses for state entry behavior
end

function BaseEnemy:UpdateIdle(dt: number)
    -- Look for targets
    local target = self:DetectTarget()
    if target then
        self.Target = target
        self:TransitionTo("Chase")
    end
end

function BaseEnemy:UpdateChase(dt: number)
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

function BaseEnemy:UpdateAttack(dt: number)
    -- Attack logic in subclasses
end

function BaseEnemy:TakeDamage(amount: number, source: Player?)
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
    
    -- Cleanup after delay
    task.delay(5, function()
        self.Model:Destroy()
    end)
end

return BaseEnemy
```

## Detection Systems

### Line of Sight Detection

```lua
local function hasLineOfSight(from: Vector3, to: Vector3, ignoreList: {Instance}?): boolean
    local direction = (to - from)
    local distance = direction.Magnitude
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = ignoreList or {}
    
    local result = workspace:Raycast(from, direction.Unit * distance, raycastParams)
    
    -- No hit means clear line of sight
    return result == nil
end
```

### Proximity Detection

```lua
local function getPlayersInRadius(position: Vector3, radius: number): {Player}
    local found = {}
    
    for _, player in Players:GetPlayers() do
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - position).Magnitude <= radius then
                table.insert(found, player)
            end
        end
    end
    
    return found
end
```

### Sound Detection (Velocity-based)

```lua
local function detectBySound(enemyPos: Vector3, radius: number): Player?
    local loudestPlayer = nil
    local loudestNoise = 0
    
    for _, player in Players:GetPlayers() do
        local char = player.Character
        if not char then continue end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        
        local distance = (hrp.Position - enemyPos).Magnitude
        if distance > radius then continue end
        
        -- Noise based on movement speed
        local velocity = hrp.AssemblyLinearVelocity
        local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
        
        -- Crouching reduces noise (check for attribute)
        local isCrouching = char:GetAttribute("IsCrouching")
        local noiseLevel = speed * (isCrouching and 0.3 or 1)
        
        -- Distance falloff
        noiseLevel = noiseLevel * (1 - distance / radius)
        
        if noiseLevel > loudestNoise then
            loudestNoise = noiseLevel
            loudestPlayer = player
        end
    end
    
    return loudestPlayer
end
```

### Combined Detection

```lua
function BaseEnemy:DetectTarget(): Player?
    local position = self.RootPart.Position
    local config = self.Config
    
    -- Priority 1: Line of sight
    for _, player in getPlayersInRadius(position, config.detectionRadius) do
        local char = player.Character
        if char then
            local head = char:FindFirstChild("Head")
            if head and hasLineOfSight(position, head.Position, {self.Model}) then
                return player
            end
        end
    end
    
    -- Priority 2: Sound
    local heardPlayer = detectBySound(position, config.detectionRadius * 0.7)
    if heardPlayer then
        return heardPlayer
    end
    
    return nil
end
```

## Common Infected (Horde)

Optimized for 50-150 simultaneous instances.

```lua
local CommonInfected = setmetatable({}, {__index = BaseEnemy})
CommonInfected.__index = CommonInfected

CommonInfected.Config = {
    detectionRadius = 30,
    attackRange = 2.5,
    attackDamage = 5,
    attackCooldown = 0.8,
    moveSpeed = 14,
    health = 50,
}

function CommonInfected.new(model: Model)
    local self = BaseEnemy.new(model)
    setmetatable(self, CommonInfected)
    
    -- Disable expensive Humanoid features
    self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
    self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
    self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    
    -- Set collision group
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.CollisionGroup = "Zombies"
        end
    end
    
    return self
end

function CommonInfected:MoveToTarget()
    if not self.Target then return end
    
    local char = self.Target.Character
    if not char then return end
    
    local targetPos = char:FindFirstChild("HumanoidRootPart")
    if not targetPos then return end
    
    -- Simple direct movement (no pathfinding for commons)
    self.Humanoid:MoveTo(targetPos.Position)
end

function CommonInfected:UpdateAttack(dt: number)
    if os.clock() - self.LastStateChange < self.Config.attackCooldown then
        return
    end
    
    local distance = self:GetDistanceToTarget()
    
    if distance > self.Config.attackRange then
        self:TransitionTo("Chase")
        return
    end
    
    -- Deal damage
    local char = self.Target.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:TakeDamage(self.Config.attackDamage)
        end
    end
    
    -- Animation trigger
    self:PlayAttackAnimation()
    
    self.LastStateChange = os.clock()
end

return CommonInfected
```

## Special Infected

### Hunter (Pounce)

High mobility, pins survivors until rescued.

```lua
local Hunter = setmetatable({}, {__index = BaseEnemy})
Hunter.__index = Hunter

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
}

export type HunterState = "Idle" | "Stalk" | "Crouch" | "Pounce" | "Pinning" | "Dead"

function Hunter.new(model: Model)
    local self = BaseEnemy.new(model)
    setmetatable(self, Hunter)
    
    self.State = "Idle" :: HunterState
    self.PinnedTarget = nil
    self.CrouchStartTime = 0
    
    return self
end

function Hunter:UpdateStalk(dt: number)
    if not self.Target then
        self:TransitionTo("Idle")
        return
    end
    
    local distance = self:GetDistanceToTarget()
    
    -- Get into pounce range
    if distance > self.Config.pounceRange then
        self:MoveToTarget()
    elseif distance >= self.Config.pounceMinRange then
        -- In range, start crouch wind-up
        self:TransitionTo("Crouch")
    else
        -- Too close, back up
        self:BackAwayFromTarget()
    end
end

function Hunter:UpdateCrouch(dt: number)
    -- Wind-up animation (telegraph to players)
    if os.clock() - self.CrouchStartTime >= self.Config.crouchDuration then
        self:ExecutePounce()
    end
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
    bodyVelocity.Velocity = direction * 80 + Vector3.new(0, 40, 0)
    bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bodyVelocity.Parent = self.RootPart
    
    self:TransitionTo("Pounce")
    
    -- Remove velocity after short duration
    task.delay(0.3, function()
        bodyVelocity:Destroy()
    end)
    
    -- Check for hit
    self:SetupPounceHitDetection()
end

function Hunter:SetupPounceHitDetection()
    local connection
    connection = self.RootPart.Touched:Connect(function(hit)
        local char = hit:FindFirstAncestorOfClass("Model")
        if char and char:FindFirstChild("Humanoid") then
            local player = Players:GetPlayerFromCharacter(char)
            if player and player == self.Target then
                self:PinTarget(player)
                connection:Disconnect()
            end
        end
    end)
    
    -- Timeout if miss
    task.delay(1, function()
        if self.State == "Pounce" then
            self:TransitionTo("Stalk")
        end
        connection:Disconnect()
    end)
end

function Hunter:PinTarget(player: Player)
    self.PinnedTarget = player
    self:TransitionTo("Pinning")
    
    local char = player.Character
    if not char then return end
    
    -- Disable player movement
    char:SetAttribute("IsPinned", true)
    char:SetAttribute("PinnedBy", self.Model:GetAttribute("EntityId"))
    
    -- Position hunter on top
    self.RootPart.CFrame = char.HumanoidRootPart.CFrame * CFrame.new(0, 2, 0)
    
    -- Start damage loop
    self:StartPinDamageLoop()
end

function Hunter:StartPinDamageLoop()
    task.spawn(function()
        while self.State == "Pinning" and self.PinnedTarget do
            local char = self.PinnedTarget.Character
            if char then
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid:TakeDamage(self.Config.pounceDamagePerSecond)
                end
            end
            task.wait(1)
        end
    end)
end

function Hunter:OnPinnedTargetRescued()
    if self.PinnedTarget then
        local char = self.PinnedTarget.Character
        if char then
            char:SetAttribute("IsPinned", false)
            char:SetAttribute("PinnedBy", nil)
        end
    end
    
    self.PinnedTarget = nil
    self:TransitionTo("Stalk")
end

return Hunter
```

### Smoker (Grab)

Long-range tongue grab, drags survivors.

```lua
local Smoker = setmetatable({}, {__index = BaseEnemy})
Smoker.__index = Smoker

Smoker.Config = {
    tongueRange = 50,
    tongueSpeed = 80,  -- Studs/second for projectile
    dragSpeed = 3,      -- Studs/second when dragging
    damagePerSecond = 3,
    health = 250,
    tongueCooldown = 15,
}

function Smoker:ShootTongue()
    if not self.Target then return end
    
    local char = self.Target.Character
    if not char then return end
    
    local targetPos = char:FindFirstChild("HumanoidRootPart")
    if not targetPos then return end
    
    -- Line of sight check
    if not hasLineOfSight(self.RootPart.Position, targetPos.Position, {self.Model}) then
        return
    end
    
    -- Create tongue visual (rope constraint or beam)
    local tongue = self:CreateTongueVisual(targetPos.Position)
    
    -- Raycast for hit
    local direction = (targetPos.Position - self.RootPart.Position).Unit
    local result = workspace:Raycast(self.RootPart.Position, direction * self.Config.tongueRange)
    
    if result and result.Instance then
        local hitChar = result.Instance:FindFirstAncestorOfClass("Model")
        if hitChar then
            local player = Players:GetPlayerFromCharacter(hitChar)
            if player then
                self:GrabTarget(player, tongue)
            end
        end
    end
end

function Smoker:GrabTarget(player: Player, tongue: Instance)
    self.GrabbedTarget = player
    self:TransitionTo("Dragging")
    
    local char = player.Character
    char:SetAttribute("IsGrabbed", true)
    char:SetAttribute("GrabbedBy", self.Model:GetAttribute("EntityId"))
    
    -- Start drag loop
    self:StartDragLoop(tongue)
end

function Smoker:StartDragLoop(tongue: Instance)
    task.spawn(function()
        while self.State == "Dragging" and self.GrabbedTarget do
            local char = self.GrabbedTarget.Character
            if not char then break end
            
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then break end
            
            -- Move toward smoker
            local direction = (self.RootPart.Position - hrp.Position).Unit
            hrp.CFrame = hrp.CFrame + direction * self.Config.dragSpeed * 0.1
            
            -- Damage
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:TakeDamage(self.Config.damagePerSecond * 0.1)
            end
            
            -- Update tongue visual
            self:UpdateTongueVisual(tongue, hrp.Position)
            
            -- Check if reached smoker
            if (self.RootPart.Position - hrp.Position).Magnitude < 5 then
                -- At smoker, start melee
                self:TransitionTo("Attack")
            end
            
            task.wait(0.1)
        end
        
        tongue:Destroy()
    end)
end

-- Tongue can be broken by teammates with melee
function Smoker:OnTongueBroken()
    if self.GrabbedTarget then
        local char = self.GrabbedTarget.Character
        if char then
            char:SetAttribute("IsGrabbed", false)
            char:SetAttribute("GrabbedBy", nil)
        end
    end
    
    self.GrabbedTarget = nil
    self:TransitionTo("Idle")
end

return Smoker
```

### Boomer (Bile)

Explosion attracts horde to bile-covered players.

```lua
local Boomer = setmetatable({}, {__index = BaseEnemy})
Boomer.__index = Boomer

Boomer.Config = {
    health = 50,  -- Very low HP
    explosionRadius = 15,
    bileRange = 8,
    bileDuration = 15,  -- Seconds players are covered
    moveSpeed = 8,  -- Slow
}

function Boomer:Die()
    -- Explode on death
    self:Explode()
    BaseEnemy.Die(self)
end

function Boomer:Explode()
    local position = self.RootPart.Position
    
    -- Visual effect
    local explosion = Instance.new("Part")
    explosion.Shape = Enum.PartType.Ball
    explosion.Size = Vector3.new(1, 1, 1)
    explosion.Position = position
    explosion.Anchored = true
    explosion.CanCollide = false
    explosion.BrickColor = BrickColor.new("Lime green")
    explosion.Material = Enum.Material.Neon
    explosion.Transparency = 0.5
    explosion.Parent = workspace
    
    -- Expand
    local tween = TweenService:Create(explosion, TweenInfo.new(0.3), {
        Size = Vector3.new(self.Config.explosionRadius * 2, self.Config.explosionRadius * 2, self.Config.explosionRadius * 2),
        Transparency = 1
    })
    tween:Play()
    tween.Completed:Connect(function()
        explosion:Destroy()
    end)
    
    -- Apply bile to nearby players
    for _, player in getPlayersInRadius(position, self.Config.explosionRadius) do
        self:ApplyBile(player)
    end
end

function Boomer:ApplyBile(player: Player)
    local char = player.Character
    if not char then return end
    
    char:SetAttribute("IsBiled", true)
    
    -- Visual effect on player (green tint)
    for _, part in char:GetDescendants() do
        if part:IsA("BasePart") then
            part:SetAttribute("OriginalColor", part.Color)
            part.Color = Color3.fromRGB(150, 200, 100)
        end
    end
    
    -- Notify AI Director to send horde
    local AIDirector = require(game.ServerScriptService.Services.DirectorService)
    AIDirector:OnPlayerBiled(player)
    
    -- Clear bile after duration
    task.delay(self.Config.bileDuration, function()
        self:ClearBile(player)
    end)
end

function Boomer:ClearBile(player: Player)
    local char = player.Character
    if not char then return end
    
    char:SetAttribute("IsBiled", false)
    
    -- Restore colors
    for _, part in char:GetDescendants() do
        if part:IsA("BasePart") then
            local original = part:GetAttribute("OriginalColor")
            if original then
                part.Color = original
            end
        end
    end
end

return Boomer
```

### Tank (Boss)

High HP boss enemy with rock throwing.

```lua
local Tank = setmetatable({}, {__index = BaseEnemy})
Tank.__index = Tank

Tank.Config = {
    health = 6000,
    punchDamage = 24,
    rockDamage = 30,
    rockCooldown = 6,
    moveSpeed = 12,
    attackRange = 4,
    rockRange = 60,
    frustrationDecay = 3,    -- Per second when not hitting
    maxFrustration = 100,    -- Transfers control or despawns
}

function Tank.new(model: Model)
    local self = BaseEnemy.new(model)
    setmetatable(self, Tank)
    
    self.Frustration = 0
    self.LastRockThrow = 0
    self.OnFire = false
    self.FireDamageRemaining = 0
    
    return self
end

function Tank:Update(dt: number)
    BaseEnemy.Update(self, dt)
    
    -- Frustration mechanic
    self:UpdateFrustration(dt)
    
    -- Fire damage over time
    if self.OnFire then
        self:UpdateFireDamage(dt)
    end
end

function Tank:UpdateFrustration(dt: number)
    -- Increase frustration when players kite without engaging
    local hitRecently = os.clock() - self.LastDamageDealt < 3
    
    if not hitRecently then
        self.Frustration += self.Config.frustrationDecay * dt
        
        if self.Frustration >= self.Config.maxFrustration then
            -- Transfer to new target or despawn
            self:OnMaxFrustration()
        end
    else
        self.Frustration = math.max(0, self.Frustration - dt * 5)
    end
end

function Tank:UpdateChase(dt: number)
    local distance = self:GetDistanceToTarget()
    
    -- Rock throw if far
    if distance > 15 and distance < self.Config.rockRange then
        if os.clock() - self.LastRockThrow > self.Config.rockCooldown then
            self:ThrowRock()
            return
        end
    end
    
    -- Otherwise chase
    if distance <= self.Config.attackRange then
        self:TransitionTo("Attack")
    else
        self:MoveToTarget()
    end
end

function Tank:ThrowRock()
    if not self.Target then return end
    
    local char = self.Target.Character
    if not char then return end
    
    local targetPos = char:FindFirstChild("HumanoidRootPart")
    if not targetPos then return end
    
    -- Create rock
    local rock = Instance.new("Part")
    rock.Shape = Enum.PartType.Ball
    rock.Size = Vector3.new(4, 4, 4)
    rock.Position = self.RootPart.Position + Vector3.new(0, 5, 0)
    rock.Material = Enum.Material.Rock
    rock.BrickColor = BrickColor.Gray()
    rock.Parent = workspace
    
    -- Calculate arc trajectory
    local direction = (targetPos.Position - rock.Position)
    local distance = direction.Magnitude
    local flightTime = distance / 60  -- Approximate
    
    local velocity = direction / flightTime + Vector3.new(0, workspace.Gravity * flightTime / 2, 0)
    rock.AssemblyLinearVelocity = velocity
    
    -- Hit detection
    rock.Touched:Connect(function(hit)
        if hit:IsDescendantOf(self.Model) then return end
        
        local hitChar = hit:FindFirstAncestorOfClass("Model")
        if hitChar then
            local humanoid = hitChar:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:TakeDamage(self.Config.rockDamage)
            end
        end
        
        rock:Destroy()
    end)
    
    -- Cleanup if miss
    Debris:AddItem(rock, 5)
    
    self.LastRockThrow = os.clock()
end

function Tank:SetOnFire()
    self.OnFire = true
    self.FireDamageRemaining = self.Config.health * 0.8  -- Fire kills over ~75 seconds
    
    -- Visual fire effect
    local fire = Instance.new("Fire")
    fire.Size = 10
    fire.Heat = 5
    fire.Parent = self.RootPart
end

function Tank:UpdateFireDamage(dt: number)
    local dps = self.Config.health * 0.8 / 75  -- Over 75 seconds
    local damage = dps * dt
    
    self:TakeDamage(damage, nil)
    self.FireDamageRemaining -= damage
    
    if self.FireDamageRemaining <= 0 then
        self.OnFire = false
    end
end

return Tank
```

### Witch (Avoidance)

Startles and one-shots if aggravated.

```lua
local Witch = setmetatable({}, {__index = BaseEnemy})
Witch.__index = Witch

Witch.Config = {
    health = 1000,
    attackDamage = 100,  -- One-shot on Expert
    detectionRadius = 15,
    aggroRadius = 5,
    flashlightAggroMultiplier = 2,
    aggroDecayRate = 5,
    aggroThreshold = 100,
}

export type WitchState = "Idle" | "Agitated" | "Rage" | "Attacking" | "Dead"

function Witch.new(model: Model)
    local self = BaseEnemy.new(model)
    setmetatable(self, Witch)
    
    self.State = "Idle" :: WitchState
    self.Aggro = 0
    self.AggroTarget = nil
    
    return self
end

function Witch:Update(dt: number)
    if self.State == "Dead" then return end
    
    if self.State == "Idle" or self.State == "Agitated" then
        self:UpdateAggroDetection(dt)
    elseif self.State == "Rage" then
        self:UpdateRage(dt)
    end
end

function Witch:UpdateAggroDetection(dt: number)
    local nearbyPlayers = getPlayersInRadius(self.RootPart.Position, self.Config.detectionRadius)
    
    local highestAggro = 0
    local aggroSource = nil
    
    for _, player in nearbyPlayers do
        local char = player.Character
        if not char then continue end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        
        local distance = (hrp.Position - self.RootPart.Position).Magnitude
        local baseAggro = 1 - (distance / self.Config.detectionRadius)
        
        -- Flashlight increases aggro
        local hasFlashlight = char:GetAttribute("FlashlightOn")
        if hasFlashlight then
            -- Check if flashlight is pointing at witch
            local lookVector = hrp.CFrame.LookVector
            local toWitch = (self.RootPart.Position - hrp.Position).Unit
            local dot = lookVector:Dot(toWitch)
            
            if dot > 0.7 then  -- Roughly facing witch
                baseAggro *= self.Config.flashlightAggroMultiplier
            end
        end
        
        -- Very close = instant aggro
        if distance < self.Config.aggroRadius then
            baseAggro = 50
        end
        
        if baseAggro > highestAggro then
            highestAggro = baseAggro
            aggroSource = player
        end
    end
    
    -- Update aggro
    if highestAggro > 0 then
        self.Aggro += highestAggro * dt * 20
        self.AggroTarget = aggroSource
        
        if self.State == "Idle" and self.Aggro > 30 then
            self:TransitionTo("Agitated")
        end
        
        if self.Aggro >= self.Config.aggroThreshold then
            self:TransitionTo("Rage")
        end
    else
        -- Decay aggro
        self.Aggro = math.max(0, self.Aggro - self.Config.aggroDecayRate * dt)
        
        if self.State == "Agitated" and self.Aggro < 20 then
            self:TransitionTo("Idle")
        end
    end
end

function Witch:UpdateRage(dt: number)
    -- Chase and attack the aggro target
    if not self.AggroTarget then
        self:TransitionTo("Idle")
        return
    end
    
    local char = self.AggroTarget.Character
    if not char then return end
    
    local distance = self:GetDistanceToTarget()
    
    if distance < 3 then
        self:PerformInstantKill()
    else
        self.Humanoid:MoveTo(char.HumanoidRootPart.Position)
    end
end

function Witch:PerformInstantKill()
    if not self.AggroTarget then return end
    
    local char = self.AggroTarget.Character
    if not char then return end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Health = 0
    end
    
    -- Witch continues attacking downed body briefly, then wanders off
    task.delay(3, function()
        self:TransitionTo("Idle")
        self.Aggro = 0
        self.AggroTarget = nil
    end)
end

return Witch
```

### Charger

Charges and slams survivors.

```lua
local Charger = setmetatable({}, {__index = BaseEnemy})
Charger.__index = Charger

Charger.Config = {
    health = 600,
    chargeDamage = 10,
    slamDamage = 25,
    poundDamagePerSecond = 15,
    chargeSpeed = 500,
    chargeCooldown = 10,
    chargeWindup = 0.5,
}

function Charger:ExecuteCharge()
    if not self.Target then return end
    
    local char = self.Target.Character
    if not char then return end
    
    local targetPos = char:FindFirstChild("HumanoidRootPart").Position
    local direction = (targetPos - self.RootPart.Position).Unit
    
    -- Wind-up (telegraph)
    self:TransitionTo("ChargeWindup")
    task.wait(self.Config.chargeWindup)
    
    -- Execute charge
    self:TransitionTo("Charging")
    
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Velocity = direction * self.Config.chargeSpeed
    bodyVelocity.MaxForce = Vector3.new(math.huge, 0, math.huge)
    bodyVelocity.Parent = self.RootPart
    
    -- Hit detection during charge
    local hitConnection
    hitConnection = self.RootPart.Touched:Connect(function(hit)
        if hit:IsDescendantOf(self.Model) then return end
        
        local hitChar = hit:FindFirstAncestorOfClass("Model")
        if hitChar then
            local player = Players:GetPlayerFromCharacter(hitChar)
            if player then
                self:GrabAndCarry(player)
                hitConnection:Disconnect()
                bodyVelocity:Destroy()
            end
        end
        
        -- Wall collision
        if hit.Anchored then
            self:SlamIntoWall()
            hitConnection:Disconnect()
            bodyVelocity:Destroy()
        end
    end)
    
    -- Timeout
    task.delay(2, function()
        hitConnection:Disconnect()
        bodyVelocity:Destroy()
        if self.State == "Charging" then
            self:TransitionTo("Chase")
        end
    end)
end

function Charger:GrabAndCarry(player: Player)
    self.CarriedTarget = player
    self:TransitionTo("Carrying")
    
    local char = player.Character
    char:SetAttribute("IsCarried", true)
    
    -- Continue charging until wall
end

function Charger:SlamIntoWall()
    if self.CarriedTarget then
        local char = self.CarriedTarget.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:TakeDamage(self.Config.slamDamage)
            end
        end
        
        -- Start pounding
        self:TransitionTo("Pounding")
        self:StartPoundLoop()
    end
end

return Charger
```

### Spitter (Area Denial)

Creates damaging acid pools.

```lua
local Spitter = setmetatable({}, {__index = BaseEnemy})
Spitter.__index = Spitter

Spitter.Config = {
    health = 100,
    spitRange = 40,
    poolDuration = 8,
    poolRadius = 8,
    initialDamage = 5,
    maxDamage = 25,  -- Escalates over time
    spitCooldown = 10,
}

function Spitter:SpitAcid()
    if not self.Target then return end
    
    local char = self.Target.Character
    if not char then return end
    
    local targetPos = char:FindFirstChild("HumanoidRootPart").Position
    
    -- Create acid projectile
    local acid = Instance.new("Part")
    acid.Shape = Enum.PartType.Ball
    acid.Size = Vector3.new(2, 2, 2)
    acid.Position = self.RootPart.Position + Vector3.new(0, 3, 0)
    acid.BrickColor = BrickColor.new("Lime green")
    acid.Material = Enum.Material.Neon
    acid.CanCollide = false
    acid.Parent = workspace
    
    -- Arc trajectory
    local direction = (targetPos - acid.Position)
    local distance = direction.Magnitude
    local flightTime = distance / 50
    
    acid.AssemblyLinearVelocity = direction / flightTime + Vector3.new(0, workspace.Gravity * flightTime / 2, 0)
    
    -- On impact, create pool
    acid.Touched:Connect(function(hit)
        if not hit:IsDescendantOf(self.Model) then
            self:CreateAcidPool(acid.Position)
            acid:Destroy()
        end
    end)
    
    Debris:AddItem(acid, 5)
end

function Spitter:CreateAcidPool(position: Vector3)
    local pool = Instance.new("Part")
    pool.Shape = Enum.PartType.Cylinder
    pool.Size = Vector3.new(1, self.Config.poolRadius * 2, self.Config.poolRadius * 2)
    pool.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
    pool.Anchored = true
    pool.CanCollide = false
    pool.BrickColor = BrickColor.new("Lime green")
    pool.Material = Enum.Material.Neon
    pool.Transparency = 0.3
    pool.Parent = workspace
    
    -- Damage players in pool
    local startTime = os.clock()
    local damageConnection
    
    damageConnection = RunService.Heartbeat:Connect(function(dt)
        local elapsed = os.clock() - startTime
        
        if elapsed >= self.Config.poolDuration then
            damageConnection:Disconnect()
            pool:Destroy()
            return
        end
        
        -- Escalating damage
        local damagePercent = elapsed / self.Config.poolDuration
        local currentDamage = self.Config.initialDamage + 
            (self.Config.maxDamage - self.Config.initialDamage) * damagePercent
        
        -- Damage nearby players
        for _, player in getPlayersInRadius(position, self.Config.poolRadius) do
            local char = player.Character
            if char then
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid:TakeDamage(currentDamage * dt)
                end
            end
        end
    end)
end

return Spitter
```

## Optimization Patterns

### Single-Script Entity Management

```lua
-- EntityService.lua - Manages ALL enemies in one place
local EntityService = {}
EntityService.Entities = {}

function EntityService:Update(dt: number)
    for id, entity in self.Entities do
        if entity.State ~= "Dead" then
            entity:Update(dt)
        else
            -- Cleanup dead entities
            self.Entities[id] = nil
        end
    end
end

RunService.Heartbeat:Connect(function(dt)
    EntityService:Update(dt)
end)
```

### Spatial Hashing for Detection

```lua
local CELL_SIZE = 20

local function getCell(position: Vector3): string
    local x = math.floor(position.X / CELL_SIZE)
    local z = math.floor(position.Z / CELL_SIZE)
    return x .. "," .. z
end

local spatialHash = {}

function updateSpatialHash(entities)
    table.clear(spatialHash)
    
    for _, entity in entities do
        local cell = getCell(entity.Position)
        spatialHash[cell] = spatialHash[cell] or {}
        table.insert(spatialHash[cell], entity)
    end
end

function getNearbyEntities(position: Vector3, radius: number): {Entity}
    local nearby = {}
    local cellRadius = math.ceil(radius / CELL_SIZE)
    local centerX = math.floor(position.X / CELL_SIZE)
    local centerZ = math.floor(position.Z / CELL_SIZE)
    
    for dx = -cellRadius, cellRadius do
        for dz = -cellRadius, cellRadius do
            local cell = (centerX + dx) .. "," .. (centerZ + dz)
            local entities = spatialHash[cell]
            if entities then
                for _, entity in entities do
                    if (entity.Position - position).Magnitude <= radius then
                        table.insert(nearby, entity)
                    end
                end
            end
        end
    end
    
    return nearby
end
```
