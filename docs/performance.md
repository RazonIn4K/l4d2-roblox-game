# Performance Optimization

## Table of Contents
1. [NPC Optimization](#npc-optimization)
2. [Network Optimization](#network-optimization)
3. [Memory Management](#memory-management)
4. [Streaming & LOD](#streaming--lod)
5. [Profiling Tools](#profiling-tools)
6. [Performance Budgets](#performance-budgets)

---

## NPC Optimization

### Single-Script Architecture (Critical)

**NEVER** use one script per enemy. This is the #1 cause of performance issues.

```lua
-- BAD: Script per enemy (DON'T DO THIS)
-- Each zombie has its own Script that runs AI

-- GOOD: Single manager script
local EntityManager = {}
EntityManager.Entities = {}

function EntityManager:Update(dt: number)
    for id, entity in self.Entities do
        entity:Update(dt)
    end
end

RunService.Heartbeat:Connect(function(dt)
    EntityManager:Update(dt)
end)
```

### Update Throttling

Not every enemy needs to update every frame.

```lua
local UPDATE_RATES = {
    Close = 1/30,      -- 30 Hz for enemies within 30 studs
    Medium = 1/15,     -- 15 Hz for enemies 30-80 studs
    Far = 1/8,         -- 8 Hz for enemies 80-150 studs
    Dormant = 1/2,     -- 0.5 Hz for enemies beyond 150 studs
}

function Enemy:GetUpdateRate(): number
    local distance = self:GetDistanceToNearestPlayer()
    
    if distance < 30 then
        return UPDATE_RATES.Close
    elseif distance < 80 then
        return UPDATE_RATES.Medium
    elseif distance < 150 then
        return UPDATE_RATES.Far
    else
        return UPDATE_RATES.Dormant
    end
end

function Enemy:Update(dt: number)
    local now = os.clock()
    local updateRate = self:GetUpdateRate()
    
    if now - self._lastUpdate < updateRate then
        return  -- Skip this update
    end
    self._lastUpdate = now
    
    -- Actual AI logic
    self:ProcessAI()
end
```

### Humanoid Optimization

Disable unused Humanoid states for significant performance gains.

```lua
local function optimizeHumanoid(humanoid: Humanoid)
    -- Disable states we don't need
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
    
    -- Keep only essential states
    -- Running, RunningNoPhysics, Dead, Jumping (if needed), Physics (for ragdoll)
    
    -- Disable unnecessary properties
    humanoid.RequiresNeck = false
    humanoid.BreakJointsOnDeath = false
end
```

### Collision Group Optimization

Prevent zombie-on-zombie collisions (huge physics overhead).

```lua
local PhysicsService = game:GetService("PhysicsService")

-- Setup collision groups once at startup
local function setupCollisionGroups()
    PhysicsService:RegisterCollisionGroup("Players")
    PhysicsService:RegisterCollisionGroup("Zombies")
    PhysicsService:RegisterCollisionGroup("Projectiles")
    PhysicsService:RegisterCollisionGroup("Debris")
    
    -- Zombies don't collide with each other
    PhysicsService:CollisionGroupSetCollidable("Zombies", "Zombies", false)
    
    -- Debris doesn't collide with anything except world
    PhysicsService:CollisionGroupSetCollidable("Debris", "Players", false)
    PhysicsService:CollisionGroupSetCollidable("Debris", "Zombies", false)
    PhysicsService:CollisionGroupSetCollidable("Debris", "Projectiles", false)
    
    -- Projectiles pass through players (no friendly fire)
    PhysicsService:CollisionGroupSetCollidable("Projectiles", "Players", false)
end

-- Assign collision group to all parts in model
local function setCollisionGroup(model: Model, group: string)
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.CollisionGroup = group
        end
    end
end
```

### Leader-Follower Pathfinding

Only compute paths for 20% of zombies; the rest follow.

```lua
local LEADER_RATIO = 5  -- 1 leader per 5 zombies

function HordeManager:AssignLeaders()
    local zombies = self:GetAllZombies()
    local leaders = {}
    
    for i, zombie in ipairs(zombies) do
        if i % LEADER_RATIO == 1 then
            zombie.IsLeader = true
            table.insert(leaders, zombie)
        else
            zombie.IsLeader = false
            -- Find nearest leader
            local nearestLeader = self:FindNearestLeader(zombie, leaders)
            zombie.Leader = nearestLeader
        end
    end
end

function Zombie:UpdateMovement()
    if self.IsLeader then
        -- Full pathfinding
        self:ComputeAndFollowPath()
    else
        -- Simple follow with offset
        if self.Leader and self.Leader.Model then
            local offset = Vector3.new(
                (math.random() - 0.5) * 6,
                0,
                (math.random() - 0.5) * 6
            )
            self.Humanoid:MoveTo(self.Leader.Model.PrimaryPart.Position + offset)
        end
    end
end
```

### Network Ownership

Server must control NPC physics to prevent exploits.

```lua
local function setServerNetworkOwnership(model: Model)
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part:SetNetworkOwner(nil)  -- Server owns
        end
    end
end

-- Call when spawning any NPC
local function spawnZombie(position: Vector3)
    local zombie = ZombieTemplate:Clone()
    zombie:PivotTo(CFrame.new(position))
    zombie.Parent = workspace.Enemies
    
    -- Critical: Server controls physics
    setServerNetworkOwnership(zombie)
    
    -- Optimize humanoid
    optimizeHumanoid(zombie:FindFirstChildOfClass("Humanoid"))
    
    -- Set collision group
    setCollisionGroup(zombie, "Zombies")
    
    return zombie
end
```

## Network Optimization

### Target: <25 KB/s per player

```lua
local NetworkOptimizer = {}

-- Batch property changes
function NetworkOptimizer:BatchChanges(instance: Instance, properties: {[string]: any})
    local parent = instance.Parent
    instance.Parent = nil  -- Temporarily remove from hierarchy
    
    for property, value in properties do
        instance[property] = value
    end
    
    instance.Parent = parent  -- Re-add (sends single update)
end

-- Round position data
local function roundVector(v: Vector3, precision: number): Vector3
    local factor = 1 / precision
    return Vector3.new(
        math.round(v.X * factor) / factor,
        math.round(v.Y * factor) / factor,
        math.round(v.Z * factor) / factor
    )
end

-- Delta compression for entity updates
local lastSentPositions = {}

function NetworkOptimizer:ShouldSendUpdate(entityId: string, newPosition: Vector3): boolean
    local lastPosition = lastSentPositions[entityId]
    
    if not lastPosition then
        lastSentPositions[entityId] = newPosition
        return true
    end
    
    -- Only send if moved significantly
    local delta = (newPosition - lastPosition).Magnitude
    if delta > 0.5 then  -- 0.5 stud threshold
        lastSentPositions[entityId] = newPosition
        return true
    end
    
    return false
end
```

### Remote Event Optimization

```lua
-- DON'T: Separate events for every action
-- FireServer for position, rotation, state, target, etc.

-- DO: Batch related data
local EntityUpdateRemote = ReplicatedStorage.Remotes.EntityUpdate

-- Server sends batched updates
local function sendEntityUpdates()
    local updates = {}
    
    for id, entity in EntityManager.Entities do
        if entity.IsDirty then
            table.insert(updates, {
                id = id,
                pos = roundVector(entity.Position, 0.1),
                rot = math.round(entity.Rotation * 10) / 10,
                state = entity.State,
                health = math.round(entity.Health),
            })
            entity.IsDirty = false
        end
    end
    
    if #updates > 0 then
        EntityUpdateRemote:FireAllClients(updates)
    end
end

-- Send at fixed rate, not per-frame
RunService.Heartbeat:Connect(function()
    if os.clock() - lastNetworkUpdate > 0.05 then  -- 20 Hz max
        sendEntityUpdates()
        lastNetworkUpdate = os.clock()
    end
end)
```

### Client-Side Prediction

Visual effects should be client-side only.

```lua
-- Server: Only game logic
function EntityService:DamageEntity(entityId: string, damage: number, source: Player)
    local entity = self.Entities[entityId]
    if not entity then return end
    
    entity.Health -= damage
    entity.IsDirty = true
    
    -- Notify clients for visual effect
    DamageRemote:FireAllClients(entityId, damage, source)
end

-- Client: Visual effects only
DamageRemote.OnClientEvent:Connect(function(entityId, damage, source)
    local entity = ClientEntityManager:GetEntity(entityId)
    if not entity then return end
    
    -- Play hit animation
    entity:PlayHitAnimation()
    
    -- Spawn blood particles
    Effects:SpawnBlood(entity.Position)
    
    -- Play sound
    SoundManager:PlayHitSound(entity.Position)
end)
```

## Memory Management

### Object Pooling

Reuse objects instead of creating/destroying.

```lua
local ObjectPool = {}
ObjectPool.__index = ObjectPool

function ObjectPool.new(template: Instance, initialSize: number)
    local self = setmetatable({}, ObjectPool)
    
    self.Template = template
    self.Available = {}
    self.InUse = {}
    
    -- Pre-populate pool
    for i = 1, initialSize do
        local obj = template:Clone()
        obj.Parent = nil  -- Not in workspace
        table.insert(self.Available, obj)
    end
    
    return self
end

function ObjectPool:Get(): Instance
    local obj
    
    if #self.Available > 0 then
        obj = table.remove(self.Available)
    else
        -- Pool exhausted, create new
        obj = self.Template:Clone()
    end
    
    self.InUse[obj] = true
    return obj
end

function ObjectPool:Return(obj: Instance)
    if not self.InUse[obj] then return end
    
    self.InUse[obj] = nil
    obj.Parent = nil  -- Remove from workspace
    
    -- Reset object state
    self:ResetObject(obj)
    
    table.insert(self.Available, obj)
end

function ObjectPool:ResetObject(obj: Instance)
    -- Reset to default state
    if obj:IsA("Model") then
        local humanoid = obj:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.Health = humanoid.MaxHealth
        end
    end
end

-- Usage
local ZombiePool = ObjectPool.new(ZombieTemplate, 50)

function SpawnZombie(position)
    local zombie = ZombiePool:Get()
    zombie:PivotTo(CFrame.new(position))
    zombie.Parent = workspace.Enemies
    return zombie
end

function DespawnZombie(zombie)
    ZombiePool:Return(zombie)
end
```

### Table Reuse

Avoid creating new tables in hot paths.

```lua
-- BAD: Creates new table every frame
function Entity:GetNearbyTargets()
    local targets = {}  -- New table allocation
    for _, player in Players:GetPlayers() do
        if self:IsNearby(player) then
            table.insert(targets, player)
        end
    end
    return targets
end

-- GOOD: Reuse table
local _nearbyTargetsCache = {}

function Entity:GetNearbyTargets()
    table.clear(_nearbyTargetsCache)  -- Reuse existing table
    
    for _, player in Players:GetPlayers() do
        if self:IsNearby(player) then
            table.insert(_nearbyTargetsCache, player)
        end
    end
    
    return _nearbyTargetsCache
end
```

### Debris Cleanup

Auto-cleanup temporary objects.

```lua
local Debris = game:GetService("Debris")

-- Blood splatter cleanup
local function createBloodSplatter(position: Vector3)
    local blood = BloodTemplate:Clone()
    blood.Position = position
    blood.Parent = workspace.Effects
    
    Debris:AddItem(blood, 5)  -- Auto-destroy after 5 seconds
end

-- Shell casing cleanup
local function ejectShellCasing(position: Vector3, velocity: Vector3)
    local shell = ShellPool:Get()
    shell.Position = position
    shell.Velocity = velocity
    shell.Parent = workspace.Effects
    
    task.delay(3, function()
        ShellPool:Return(shell)
    end)
end
```

## Streaming & LOD

### StreamingEnabled Configuration

```lua
-- Workspace properties for horror game
workspace.StreamingEnabled = true
workspace.StreamingMinRadius = 128
workspace.StreamingTargetRadius = 512
workspace.StreamingIntegrityMode = Enum.StreamingIntegrityMode.Default
```

### Model Streaming Modes

```lua
-- PersistentPerPlayer: Always loaded for specific player
-- Persistent: Always loaded for everyone
-- Atomic: Loads/unloads together, important for NPCs
-- Default: Normal streaming behavior

-- Set on Model instances
zombieModel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

-- Safe room should always be loaded
safeRoom.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

-- Player's inventory UI elements
inventoryModel.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
```

### AI LOD System

```lua
export type AIDetailLevel = "Full" | "Reduced" | "Minimal" | "Dormant"

function Enemy:GetDetailLevel(): AIDetailLevel
    local distance = self:GetDistanceToNearestPlayer()
    
    if distance < 50 then
        return "Full"       -- Full pathfinding, animations, sounds
    elseif distance < 100 then
        return "Reduced"    -- Simpler pathfinding, basic animations
    elseif distance < 200 then
        return "Minimal"    -- Direct movement only, no animations
    else
        return "Dormant"    -- Anchor in place, minimal updates
    end
end

function Enemy:ApplyDetailLevel(level: AIDetailLevel)
    if level == "Full" then
        self._updateInterval = 1/30
        self.Humanoid.WalkSpeed = self.Config.moveSpeed
        -- Enable all features
        
    elseif level == "Reduced" then
        self._updateInterval = 1/15
        -- Disable ragdoll, reduce animation quality
        
    elseif level == "Minimal" then
        self._updateInterval = 1/8
        -- Disable animations entirely
        for _, track in self.Humanoid.Animator:GetPlayingAnimationTracks() do
            track:Stop()
        end
        
    elseif level == "Dormant" then
        self._updateInterval = 1/2
        self.Model.PrimaryPart.Anchored = true
    end
end
```

## Profiling Tools

### MicroProfiler

```lua
-- Press Ctrl+Alt+F6 in Studio to open MicroProfiler

-- Mark custom profiling regions
debug.profilebegin("AIDirector:Update")
    -- AI director logic
debug.profileend()

debug.profilebegin("EntityManager:UpdateAll")
    for _, entity in entities do
        debug.profilebegin("Entity:Update")
        entity:Update(dt)
        debug.profileend()
    end
debug.profileend()
```

### Performance Stats

```lua
local Stats = game:GetService("Stats")

local function logPerformanceStats()
    print("=== Performance Stats ===")
    print("Heartbeat: " .. Stats.HeartbeatTimeMs .. " ms")
    print("Physics: " .. Stats.PhysicsStepTimeMs .. " ms")
    print("Instances: " .. Stats.InstanceCount)
    print("Memory: " .. Stats:GetTotalMemoryUsageMb() .. " MB")
    print("Network Receive: " .. Stats.DataReceiveKbps .. " KB/s")
    print("Network Send: " .. Stats.DataSendKbps .. " KB/s")
end

-- Log every 5 seconds
while true do
    task.wait(5)
    logPerformanceStats()
end
```

### Custom Performance Monitor

```lua
local PerformanceMonitor = {
    samples = {},
    maxSamples = 100,
}

function PerformanceMonitor:StartSample(name: string)
    self._startTimes = self._startTimes or {}
    self._startTimes[name] = os.clock()
end

function PerformanceMonitor:EndSample(name: string)
    if not self._startTimes[name] then return end
    
    local duration = os.clock() - self._startTimes[name]
    self._startTimes[name] = nil
    
    self.samples[name] = self.samples[name] or {}
    table.insert(self.samples[name], duration)
    
    -- Keep only recent samples
    while #self.samples[name] > self.maxSamples do
        table.remove(self.samples[name], 1)
    end
end

function PerformanceMonitor:GetAverage(name: string): number
    local samples = self.samples[name]
    if not samples or #samples == 0 then return 0 end
    
    local sum = 0
    for _, sample in samples do
        sum += sample
    end
    return sum / #samples
end

function PerformanceMonitor:Report()
    print("=== Performance Report ===")
    for name, samples in self.samples do
        local avg = self:GetAverage(name) * 1000  -- Convert to ms
        print(string.format("%s: %.2f ms avg", name, avg))
    end
end

return PerformanceMonitor
```

## Performance Budgets

### Target Frame Rate: 60 FPS (16.67ms per frame)

| System | Budget | Notes |
|--------|--------|-------|
| Heartbeat total | <8 ms | Leave headroom |
| AI Director | <1 ms | State machine only |
| Entity updates (50) | <3 ms | 0.06ms per entity |
| Pathfinding | <2 ms | Throttled, leader-only |
| Physics | <4 ms | Engine managed |
| Rendering | <8 ms | Client-side |

### Entity Budget Guidelines

| Hardware | Max Active NPCs | Notes |
|----------|-----------------|-------|
| Low-end mobile | 20-30 | Aggressive LOD |
| Mid-range | 50-80 | Standard settings |
| High-end PC | 100-150 | Full features |

### Memory Budget

```lua
local MEMORY_BUDGET_MB = 512  -- Target max

local function checkMemoryBudget()
    local currentMB = Stats:GetTotalMemoryUsageMb()
    
    if currentMB > MEMORY_BUDGET_MB * 0.9 then
        warn("Memory warning: " .. currentMB .. "MB")
        -- Aggressive cleanup
        EntityManager:CullDistantEntities()
        RoomGenerator:CleanupDistantRooms()
        collectgarbage("collect")
    end
end
```

### Network Budget

```lua
-- Target: <25 KB/s per player
local NETWORK_BUDGET_KBPS = 25

local function checkNetworkBudget()
    local sendKbps = Stats.DataSendKbps / #Players:GetPlayers()
    
    if sendKbps > NETWORK_BUDGET_KBPS then
        warn("Network warning: " .. sendKbps .. " KB/s per player")
        -- Reduce update frequency
        NetworkManager:ReduceUpdateRate()
    end
end
```
