# Windsurf AI Rules - L4D2 Roblox Horror Game

## Project Overview
Left 4 Dead 2-style cooperative horror game for Roblox. 4-player co-op, AI Director pacing, special infected, procedural generation.

## Tech Stack
- Luau (Roblox's typed Lua)
- Rojo v7 (IDE ↔ Studio sync)
- Wally (package manager)
- Selene (linter)

## Critical Architecture Rules

### 1. Single-Script Entity Management (MANDATORY)
All NPCs managed in ONE script via EntityService. Never one script per enemy.

### 2. Server Authority
All game logic on server. Never trust client for health/damage/position.

### 3. Performance Targets
- 60 FPS with 50-100 NPCs
- 16 Hz AI updates (0.0625s throttle)
- Zombies: CollisionGroup that doesn't self-collide
- Server network ownership for all NPCs

## Code Patterns

### Services (Singleton)
```lua
--!strict
local Service = {}
Service.__index = Service
local _instance = nil

function Service.new()
    if _instance then return _instance end
    local self = setmetatable({}, Service)
    _instance = self
    return self
end

function Service:Get() return Service.new() end
```

### Entity FSM
```lua
export type EntityState = "Idle" | "Chase" | "Attack" | "Dead"

function Entity:Update(dt)
    if os.clock() - self._lastUpdate < 0.0625 then return end
    self._lastUpdate = os.clock()
    -- State logic
end
```

### Remote Validation
```lua
Remote.OnServerEvent:Connect(function(player, data)
    if typeof(data) ~= "number" then return end
    if data ~= data then return end  -- NaN check
    -- Process
end)
```

## Naming
- PascalCase: Classes, Services
- camelCase: variables, functions
- UPPER_SNAKE: CONSTANTS
- _prefix: private members

## File Locations
- Server code: src/server/
- Client code: src/client/
- Shared code: src/shared/
- Documentation: docs/

## Key Game Systems
1. AI Director: 4-state pacing (BuildUp→SustainPeak→PeakFade→Relax)
2. Special Infected: Hunter, Smoker, Boomer, Tank, Witch, Charger, Spitter
3. Incap System: 3 downs = death, 5s revive, bleedout timer
4. Safe Rooms: Heal to 50 HP, reset incap count, all-players-ready exit

## Always Do
- Add --!strict to files
- Type annotate function parameters
- Use game:GetService()
- Cleanup connections in :Destroy()
- Throttle AI updates
