# Roblox Services Reference

## Table of Contents
1. [Core Services](#core-services)
2. [RunService](#runservice)
3. [PathfindingService](#pathfindingservice)
4. [TweenService](#tweenservice)
5. [CollisionGroups](#collisiongroups-physicsservice)
6. [Lighting & Atmosphere](#lighting--atmosphere)
7. [SoundService](#soundservice)
8. [Players & Characters](#players--characters)
9. [DataStoreService](#datastoreservice)
10. [Debris](#debris)

---

## Core Services

```lua
-- Always use GetService
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")  -- Client only
local ContextActionService = game:GetService("ContextActionService")  -- Client only
```

## RunService

Essential for game loops and frame-based updates.

```lua
local RunService = game:GetService("RunService")

-- Server: Physics simulation step (before physics)
RunService.Stepped:Connect(function(time, deltaTime)
    -- Pre-physics updates
end)

-- Server/Client: After physics (most common for game logic)
RunService.Heartbeat:Connect(function(deltaTime)
    -- Update all enemies
    for _, enemy in enemies do
        enemy:Update(deltaTime)
    end
end)

-- Client only: Before frame render
RunService.RenderStepped:Connect(function(deltaTime)
    -- Camera updates, visual effects
end)

-- Environment checks
if RunService:IsServer() then
    -- Server code
end

if RunService:IsClient() then
    -- Client code
end

if RunService:IsStudio() then
    -- Development only
end
```

## PathfindingService

For NPC navigation around obstacles.

```lua
local PathfindingService = game:GetService("PathfindingService")

-- Agent parameters for zombies
local agentParams = {
    AgentRadius = 2,           -- Character width
    AgentHeight = 5,           -- Character height
    AgentCanJump = true,       -- Can use jumps
    AgentCanClimb = false,     -- Can climb TrussParts
    WaypointSpacing = 4,       -- Distance between waypoints
    Costs = {
        Water = 20,            -- Avoid water
        DangerZone = math.huge -- Never enter
    }
}

-- Create path
local path = PathfindingService:CreatePath(agentParams)

-- Compute path
local function computePath(start: Vector3, goal: Vector3): boolean
    local success, errorMessage = pcall(function()
        path:ComputeAsync(start, goal)
    end)
    
    if success and path.Status == Enum.PathStatus.Success then
        return true
    end
    return false
end

-- Follow path
local function followPath(humanoid: Humanoid, path: Path)
    local waypoints = path:GetWaypoints()
    
    for i, waypoint in waypoints do
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        
        humanoid:MoveTo(waypoint.Position)
        
        local reached = humanoid.MoveToFinished:Wait()
        if not reached then
            break  -- Path blocked, recompute
        end
    end
end

-- Path blocked handler
path.Blocked:Connect(function(blockedWaypointIndex)
    -- Recompute from current position
end)
```

### Optimized Pathfinding for Hordes

```lua
-- Leader-follower pattern: Only leaders compute full paths
local LEADER_RATIO = 5  -- 1 leader per 5 zombies

local function updateHorde(zombies, target)
    local leaders = {}
    
    for i, zombie in zombies do
        if i % LEADER_RATIO == 1 then
            -- This zombie is a leader
            table.insert(leaders, zombie)
            zombie.IsLeader = true
            zombie:ComputePathTo(target)
        else
            -- Follower: find nearest leader
            local nearestLeader = findNearestLeader(zombie, leaders)
            zombie.Leader = nearestLeader
        end
    end
end

local function updateFollower(zombie)
    if zombie.Leader then
        local offset = Vector3.new(
            math.random(-3, 3),
            0,
            math.random(-3, 3)
        )
        zombie.Humanoid:MoveTo(zombie.Leader.Position + offset)
    end
end
```

## TweenService

Smooth animations for properties.

```lua
local TweenService = game:GetService("TweenService")

-- Basic tween
local tweenInfo = TweenInfo.new(
    1,                              -- Duration
    Enum.EasingStyle.Quad,          -- Easing style
    Enum.EasingDirection.Out,       -- Direction
    0,                              -- Repeat count (0 = no repeat)
    false,                          -- Reverses
    0                               -- Delay
)

local tween = TweenService:Create(part, tweenInfo, {
    Position = Vector3.new(0, 10, 0),
    Transparency = 0.5
})

tween:Play()
tween.Completed:Wait()

-- Flickering light (horror effect)
local function flickerLight(light: PointLight, duration: number)
    local originalBrightness = light.Brightness
    local endTime = os.clock() + duration
    
    while os.clock() < endTime do
        light.Brightness = originalBrightness * math.random()
        task.wait(math.random() * 0.1)
    end
    
    light.Brightness = originalBrightness
end

-- Smooth camera shake
local function shakeCamera(intensity: number, duration: number)
    local camera = workspace.CurrentCamera
    local originalCFrame = camera.CFrame
    local endTime = os.clock() + duration
    
    while os.clock() < endTime do
        local offset = Vector3.new(
            (math.random() - 0.5) * intensity,
            (math.random() - 0.5) * intensity,
            (math.random() - 0.5) * intensity
        )
        camera.CFrame = originalCFrame * CFrame.new(offset)
        task.wait()
    end
    
    camera.CFrame = originalCFrame
end
```

## CollisionGroups (PhysicsService)

Prevent zombies colliding with each other.

```lua
local PhysicsService = game:GetService("PhysicsService")

-- Register groups
PhysicsService:RegisterCollisionGroup("Players")
PhysicsService:RegisterCollisionGroup("Zombies")
PhysicsService:RegisterCollisionGroup("Projectiles")

-- Configure collisions
PhysicsService:CollisionGroupSetCollidable("Zombies", "Zombies", false)      -- Zombies pass through each other
PhysicsService:CollisionGroupSetCollidable("Projectiles", "Players", false)  -- Friendly fire off
PhysicsService:CollisionGroupSetCollidable("Projectiles", "Zombies", true)   -- Bullets hit zombies

-- Assign parts to groups
local function setCollisionGroup(model: Model, groupName: string)
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.CollisionGroup = groupName
        end
    end
end

-- Usage
setCollisionGroup(zombieModel, "Zombies")
```

## Lighting & Atmosphere

Critical for horror atmosphere.

```lua
local Lighting = game:GetService("Lighting")

-- Base horror lighting
Lighting.Ambient = Color3.fromRGB(10, 10, 15)
Lighting.Brightness = 0.5
Lighting.OutdoorAmbient = Color3.fromRGB(20, 20, 30)
Lighting.ClockTime = 0  -- Midnight
Lighting.GeographicLatitude = 45

-- Atmosphere (fog)
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.4
atmosphere.Offset = 0.25
atmosphere.Color = Color3.fromRGB(40, 40, 50)
atmosphere.Decay = Color3.fromRGB(60, 60, 70)
atmosphere.Glare = 0
atmosphere.Haze = 2
atmosphere.Parent = Lighting

-- Color correction (desaturation)
local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Brightness = -0.05
colorCorrection.Contrast = 0.1
colorCorrection.Saturation = -0.3
colorCorrection.TintColor = Color3.fromRGB(200, 200, 220)
colorCorrection.Parent = Lighting

-- Depth of field (focus effect)
local dof = Instance.new("DepthOfFieldEffect")
dof.FarIntensity = 0.3
dof.FocusDistance = 20
dof.InFocusRadius = 30
dof.NearIntensity = 0
dof.Parent = Lighting

-- Bloom (for flashlight glow)
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.5
bloom.Size = 24
bloom.Threshold = 0.9
bloom.Parent = Lighting

-- Dynamic lighting transitions
local function transitionToHorror(duration: number)
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Sine)
    
    TweenService:Create(Lighting, tweenInfo, {
        Ambient = Color3.fromRGB(5, 5, 10),
        Brightness = 0.2
    }):Play()
    
    TweenService:Create(atmosphere, tweenInfo, {
        Density = 0.6
    }):Play()
end
```

## SoundService

3D positional audio for horror.

```lua
local SoundService = game:GetService("SoundService")

-- Ambient sound group
local ambientGroup = Instance.new("SoundGroup")
ambientGroup.Name = "Ambient"
ambientGroup.Volume = 0.7
ambientGroup.Parent = SoundService

-- 3D positional sound
local function play3DSound(soundId: string, position: Vector3, config: {
    Volume: number?,
    RollOffMode: Enum.RollOffMode?,
    RollOffMinDistance: number?,
    RollOffMaxDistance: number?
}?)
    local attachment = Instance.new("Attachment")
    attachment.Position = position
    attachment.Parent = workspace.Terrain
    
    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.Volume = config and config.Volume or 1
    sound.RollOffMode = config and config.RollOffMode or Enum.RollOffMode.InverseTapered
    sound.RollOffMinDistance = config and config.RollOffMinDistance or 10
    sound.RollOffMaxDistance = config and config.RollOffMaxDistance or 100
    sound.Parent = attachment
    
    sound:Play()
    sound.Ended:Connect(function()
        attachment:Destroy()
    end)
    
    return sound
end

-- Zombie growl with distance falloff
play3DSound("rbxassetid://123456", zombiePosition, {
    Volume = 0.8,
    RollOffMinDistance = 5,
    RollOffMaxDistance = 50
})

-- Ambient layer system
local ambientLayers = {}

local function addAmbientLayer(name: string, soundId: string, volume: number)
    local sound = Instance.new("Sound")
    sound.Name = name
    sound.SoundId = soundId
    sound.Volume = volume
    sound.Looped = true
    sound.SoundGroup = ambientGroup
    sound.Parent = SoundService
    sound:Play()
    ambientLayers[name] = sound
end

-- Build tension by layering
addAmbientLayer("BaseAmbient", "rbxassetid://ambient_base", 0.3)
addAmbientLayer("Wind", "rbxassetid://wind_loop", 0.2)
addAmbientLayer("HeartbeatTension", "rbxassetid://heartbeat", 0)  -- Fade in during danger
```

## Players & Characters

```lua
local Players = game:GetService("Players")

-- Player added
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid")
        
        -- Setup character
        humanoid.MaxHealth = 100
        humanoid.Health = 100
        
        humanoid.Died:Connect(function()
            -- Handle death
        end)
    end)
end)

-- Get all players
for _, player in Players:GetPlayers() do
    print(player.Name)
end

-- Get character parts
local function getCharacterParts(character: Model)
    return {
        HumanoidRootPart = character:FindFirstChild("HumanoidRootPart"),
        Head = character:FindFirstChild("Head"),
        Humanoid = character:FindFirstChildOfClass("Humanoid")
    }
end

-- Distance to nearest player
local function getNearestPlayer(position: Vector3): (Player?, number)
    local nearest = nil
    local nearestDist = math.huge
    
    for _, player in Players:GetPlayers() do
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (hrp.Position - position).Magnitude
                if dist < nearestDist then
                    nearest = player
                    nearestDist = dist
                end
            end
        end
    end
    
    return nearest, nearestDist
end
```

## DataStoreService

For player progression persistence (use ProfileStore wrapper in production).

```lua
local DataStoreService = game:GetService("DataStoreService")
local playerStore = DataStoreService:GetDataStore("PlayerData_v1")

local function loadPlayerData(userId: number): {[string]: any}?
    local success, data = pcall(function()
        return playerStore:GetAsync("Player_" .. userId)
    end)
    
    if success and data then
        return data
    end
    
    -- Return default data
    return {
        level = 1,
        xp = 0,
        unlockedWeapons = {"Pistol"},
        completedCampaigns = {}
    }
end

local function savePlayerData(userId: number, data: {[string]: any})
    local success, err = pcall(function()
        playerStore:SetAsync("Player_" .. userId, data)
    end)
    
    if not success then
        warn("Failed to save:", err)
    end
end

-- Use UpdateAsync for safe concurrent updates
local function addXP(userId: number, amount: number)
    pcall(function()
        playerStore:UpdateAsync("Player_" .. userId, function(oldData)
            oldData = oldData or {xp = 0}
            oldData.xp = (oldData.xp or 0) + amount
            return oldData
        end)
    end)
end
```

## Debris

Auto-cleanup for temporary objects.

```lua
local Debris = game:GetService("Debris")

-- Auto-destroy after time
local bloodSplatter = createBloodEffect()
Debris:AddItem(bloodSplatter, 5)  -- Destroy after 5 seconds

-- Useful for:
-- - Blood/gore effects
-- - Shell casings
-- - Temporary particles
-- - Dead enemy bodies
-- - Projectiles

-- Pattern: Create and forget
local function spawnTemporaryEffect(position: Vector3, duration: number)
    local effect = Instance.new("Part")
    effect.Position = position
    effect.Anchored = true
    effect.Parent = workspace
    
    Debris:AddItem(effect, duration)  -- Automatic cleanup
end
```
