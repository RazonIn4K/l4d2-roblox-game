# AI Director Implementation

## Table of Contents
1. [Overview](#overview)
2. [Pacing State Machine](#pacing-state-machine)
3. [Intensity System](#intensity-system)
4. [Spawn Management](#spawn-management)
5. [Population Control](#population-control)
6. [Crescendo Events](#crescendo-events)
7. [Complete Implementation](#complete-implementation)

---

## Overview

The AI Director creates L4D2's signature gameplay rhythm: waves of intense combat followed by calm recovery periods. It tracks player stress ("intensity") and dynamically adjusts enemy spawns.

**Core Principles:**
- Terror is cheap, use it liberally
- Relief makes horror more impactful
- Punish players who stand still
- Reward players who push forward
- Never spawn enemies in player's view

## Pacing State Machine

The Director cycles through four states:

```
┌─────────┐     Intensity > Peak    ┌──────────────┐
│ BuildUp │ ───────────────────────▶│ SustainPeak  │
│ (spawn) │                         │ (max danger) │
└────┬────┘                         └──────┬───────┘
     │                                     │
     │                             Timer expires (3-5s)
     │                                     │
     │                                     ▼
     │                              ┌────────────┐
     │         Timer expires        │ Peak Fade  │
     │◀────────────────────────────│ (reduce)   │
     │         (30-45s)             └──────┬─────┘
┌────┴────┐                                │
│  Relax  │◀──────────────────────────────┘
│ (safe)  │     Intensity < Threshold
└─────────┘
```

| State | Spawning | Duration | Purpose |
|-------|----------|----------|---------|
| **BuildUp** | Full population | Until intensity peaks | Create tension |
| **SustainPeak** | Maintain | 3-5 seconds | Maximum pressure |
| **PeakFade** | Minimal | Until intensity drops | Transition |
| **Relax** | None | 30-45 seconds | Recovery period |

## Intensity System

Intensity represents current player stress level (0-100).

**Intensity Increases:**
| Event | Intensity Gain |
|-------|----------------|
| Damage taken | `damage × 0.5` |
| Player incapacitated | `+15` |
| Nearby zombie killed (<10 studs) | `+3` |
| Special infected spotted | `+5` |
| Teammate downed | `+10` |

**Intensity Decreases:**
- Decays at 5 points/second when NOT in active combat
- No decay during combat (enemies within 30 studs)
- Safe room entry sets to 0

```lua
function AIDirector:AddIntensity(event: string, value: number?)
    local gains = {
        damage = function(v) return v * 0.5 end,
        incap = function() return 15 end,
        nearbyKill = function() return 3 end,
        specialSpotted = function() return 5 end,
        teammateDowned = function() return 10 end,
    }
    
    local gain = gains[event]
    if gain then
        self.Intensity = math.min(100, self.Intensity + gain(value))
    end
end

function AIDirector:DecayIntensity(dt: number)
    if not self:IsInCombat() then
        self.Intensity = math.max(0, self.Intensity - dt * 5)
    end
end
```

## Spawn Management

### Active Area Set (AAS)

Only spawn enemies in areas players might encounter:

```lua
local AAS_RADIUS = 150  -- Studs from any player

function AIDirector:GetActiveAreas(): {SpawnArea}
    local active = {}
    local playerPositions = self:GetPlayerPositions()
    
    for _, area in self.SpawnAreas do
        for _, pos in playerPositions do
            if (area.Position - pos).Magnitude <= AAS_RADIUS then
                table.insert(active, area)
                break
            end
        end
    end
    
    return active
end
```

### Spawn Rules

1. **Never spawn in line of sight** - Raycast check required
2. **75% spawn behind players** - Check player facing direction
3. **Maintain minimum distances** - Commons 20+ studs, Specials 40+ studs
4. **Respect population caps** - Track active enemy counts

```lua
function AIDirector:IsValidSpawnPoint(point: Vector3): boolean
    for _, player in Players:GetPlayers() do
        local char = player.Character
        if not char then continue end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        
        local distance = (point - hrp.Position).Magnitude
        
        -- Too close
        if distance < 20 then return false end
        
        -- Line of sight check
        local ray = Ray.new(point, (hrp.Position - point).Unit * distance)
        local hit = workspace:Raycast(point, ray.Direction * distance)
        
        if not hit then
            -- Player can see this point
            return false
        end
    end
    
    return true
end

function AIDirector:GetSpawnBias(): Vector3
    -- 75% chance to spawn behind players
    if math.random() < 0.75 then
        local avgFacing = self:GetAveragePlayerFacing()
        return -avgFacing  -- Behind
    end
    return Vector3.new(0, 0, 0)  -- No bias
end
```

## Population Control

### Common Infected (Horde)

```lua
local COMMON_CONFIG = {
    maxPopulation = 30,          -- Max active at once
    spawnInterval = {90, 180},   -- Seconds between waves (Normal)
    waveSize = {10, 20},         -- Zombies per wave
    wanderersMax = 5,            -- Ambient zombies outside waves
}

-- Difficulty scaling
local DIFFICULTY_MULTIPLIERS = {
    Easy   = {population = 0.7, interval = 1.3, wave = 0.6},
    Normal = {population = 1.0, interval = 1.0, wave = 1.0},
    Hard   = {population = 1.2, interval = 0.8, wave = 1.3},
    Expert = {population = 1.5, interval = 0.6, wave = 1.5},
}
```

### Special Infected

Each special has independent spawn timers:

```lua
local SPECIAL_CONFIG = {
    Hunter  = {minInterval = 15, maxInterval = 30, maxActive = 2},
    Smoker  = {minInterval = 20, maxInterval = 40, maxActive = 1},
    Boomer  = {minInterval = 20, maxInterval = 35, maxActive = 1},
    Tank    = {minInterval = 180, maxInterval = 300, maxActive = 1},
    Witch   = {minInterval = 120, maxInterval = 240, maxActive = 2},
}

-- Expert mode: Stricter limits
local EXPERT_SPECIAL_LIMITS = {
    totalActive = 4,  -- Max specials at once
    huntingPack = 2,  -- Max of same type
}

function AIDirector:CanSpawnSpecial(specialType: string): boolean
    local config = SPECIAL_CONFIG[specialType]
    local activeCount = self:GetActiveSpecialCount(specialType)
    
    -- Type limit
    if activeCount >= config.maxActive then
        return false
    end
    
    -- Total limit
    if self:GetTotalSpecialCount() >= EXPERT_SPECIAL_LIMITS.totalActive then
        return false
    end
    
    -- Timer check
    if self.SpecialTimers[specialType] > 0 then
        return false
    end
    
    return true
end
```

## Crescendo Events

Scripted high-intensity moments (finales, alarm triggers).

```lua
export type CrescendoConfig = {
    duration: number,          -- How long the event lasts
    waveCount: number,         -- Number of waves
    waveSize: {number},        -- Min/max per wave
    waveInterval: number,      -- Seconds between waves
    specialWaves: {number},    -- Which waves include specials
    tankWave: number?,         -- Optional: which wave spawns Tank
}

local CRESCENDO_FINALE: CrescendoConfig = {
    duration = 180,
    waveCount = 5,
    waveSize = {20, 30},
    waveInterval = 30,
    specialWaves = {2, 3, 4, 5},
    tankWave = 4,
}

function AIDirector:StartCrescendo(config: CrescendoConfig)
    self.State = "Crescendo"
    self.CrescendoConfig = config
    self.CrescendoWave = 0
    self.CrescendoTimer = 0
    
    -- Override normal spawning
    self:SuspendNormalSpawning()
    
    -- Start first wave
    self:SpawnCrescendoWave()
end

function AIDirector:UpdateCrescendo(dt: number)
    self.CrescendoTimer += dt
    
    local config = self.CrescendoConfig
    local nextWaveTime = self.CrescendoWave * config.waveInterval
    
    if self.CrescendoTimer >= nextWaveTime and self.CrescendoWave < config.waveCount then
        self.CrescendoWave += 1
        self:SpawnCrescendoWave()
    end
    
    if self.CrescendoTimer >= config.duration then
        self:EndCrescendo()
    end
end

function AIDirector:SpawnCrescendoWave()
    local config = self.CrescendoConfig
    local wave = self.CrescendoWave
    local count = math.random(config.waveSize[1], config.waveSize[2])
    
    -- Spawn commons
    for i = 1, count do
        self:SpawnCommon()
    end
    
    -- Specials on designated waves
    if table.find(config.specialWaves, wave) then
        self:SpawnRandomSpecial()
    end
    
    -- Tank on designated wave
    if config.tankWave and wave == config.tankWave then
        self:SpawnTank()
    end
end
```

## Complete Implementation

```lua
--!strict
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

export type DirectorState = "BuildUp" | "SustainPeak" | "PeakFade" | "Relax" | "Crescendo" | "SafeRoom"

local AIDirector = {}
AIDirector.__index = AIDirector

-- Configuration
local CONFIG = {
    peakThreshold = 70,
    relaxDuration = {30, 45},
    sustainPeakDuration = {3, 5},
    intensityDecayRate = 5,
    combatRadius = 30,
}

function AIDirector.new()
    local self = setmetatable({}, AIDirector)
    
    -- State
    self.State = "BuildUp" :: DirectorState
    self.Intensity = 0
    self.StateTimer = 0
    
    -- Timers
    self.CommonSpawnTimer = 0
    self.SpecialTimers = {
        Hunter = 0,
        Smoker = 0,
        Boomer = 0,
        Tank = 0,
    }
    
    -- Population tracking
    self.ActiveCommons = {}
    self.ActiveSpecials = {}
    
    -- Events
    self.OnStateChanged = Instance.new("BindableEvent")
    self.OnWaveSpawned = Instance.new("BindableEvent")
    
    return self
end

function AIDirector:Start()
    RunService.Heartbeat:Connect(function(dt)
        self:Update(dt)
    end)
    
    -- Listen for game events
    self:ConnectGameEvents()
end

function AIDirector:Update(dt: number)
    -- Update timers
    self:UpdateTimers(dt)
    
    -- Decay intensity
    self:DecayIntensity(dt)
    
    -- State machine
    if self.State == "BuildUp" then
        self:UpdateBuildUp(dt)
    elseif self.State == "SustainPeak" then
        self:UpdateSustainPeak(dt)
    elseif self.State == "PeakFade" then
        self:UpdatePeakFade(dt)
    elseif self.State == "Relax" then
        self:UpdateRelax(dt)
    elseif self.State == "Crescendo" then
        self:UpdateCrescendo(dt)
    end
    
    -- Spawning (only in active states)
    if self.State == "BuildUp" or self.State == "SustainPeak" then
        self:ProcessSpawning(dt)
    end
end

function AIDirector:UpdateBuildUp(dt: number)
    if self.Intensity >= CONFIG.peakThreshold then
        self:TransitionTo("SustainPeak")
        self.StateTimer = math.random(CONFIG.sustainPeakDuration[1], CONFIG.sustainPeakDuration[2])
    end
end

function AIDirector:UpdateSustainPeak(dt: number)
    self.StateTimer -= dt
    if self.StateTimer <= 0 then
        self:TransitionTo("PeakFade")
    end
end

function AIDirector:UpdatePeakFade(dt: number)
    if self.Intensity < CONFIG.peakThreshold * 0.5 then
        self:TransitionTo("Relax")
        self.StateTimer = math.random(CONFIG.relaxDuration[1], CONFIG.relaxDuration[2])
    end
end

function AIDirector:UpdateRelax(dt: number)
    self.StateTimer -= dt
    if self.StateTimer <= 0 then
        self:TransitionTo("BuildUp")
    end
end

function AIDirector:TransitionTo(newState: DirectorState)
    local oldState = self.State
    self.State = newState
    self.OnStateChanged:Fire(oldState, newState)
    
    -- Debug
    print(string.format("[Director] %s -> %s (Intensity: %.1f)", oldState, newState, self.Intensity))
end

function AIDirector:ProcessSpawning(dt: number)
    -- Common infected
    self.CommonSpawnTimer -= dt
    if self.CommonSpawnTimer <= 0 and self:CanSpawnCommons() then
        self:SpawnCommonWave()
        self.CommonSpawnTimer = math.random(90, 180)
    end
    
    -- Special infected
    for specialType, timer in self.SpecialTimers do
        self.SpecialTimers[specialType] -= dt
        if timer <= 0 and self:CanSpawnSpecial(specialType) then
            self:SpawnSpecial(specialType)
            self.SpecialTimers[specialType] = math.random(20, 40)
        end
    end
end

function AIDirector:IsInCombat(): boolean
    local playerPositions = self:GetPlayerPositions()
    
    for _, enemy in self.ActiveCommons do
        if enemy and enemy.Model then
            for _, pos in playerPositions do
                if (enemy.Model.PrimaryPart.Position - pos).Magnitude < CONFIG.combatRadius then
                    return true
                end
            end
        end
    end
    
    return false
end

function AIDirector:GetPlayerPositions(): {Vector3}
    local positions = {}
    
    for _, player in Players:GetPlayers() do
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                table.insert(positions, hrp.Position)
            end
        end
    end
    
    return positions
end

function AIDirector:EnterSafeRoom()
    self:TransitionTo("SafeRoom")
    self.Intensity = 0
    
    -- Despawn all enemies outside safe room
    self:DespawnDistantEnemies()
end

function AIDirector:ExitSafeRoom()
    self:TransitionTo("Relax")
    self.StateTimer = 10  -- Brief grace period
end

-- Connect to entity service for spawning (implementation depends on your EntityService)
function AIDirector:SpawnCommon() end
function AIDirector:SpawnCommonWave() end
function AIDirector:SpawnSpecial(specialType: string) end
function AIDirector:CanSpawnCommons(): boolean return true end
function AIDirector:CanSpawnSpecial(specialType: string): boolean return true end
function AIDirector:DespawnDistantEnemies() end
function AIDirector:UpdateTimers(dt: number) end
function AIDirector:ConnectGameEvents() end

return AIDirector
```
