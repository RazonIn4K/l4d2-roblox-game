# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Summary
Building a Left 4 Dead 2-inspired cooperative horror/survival game in Roblox using Luau. The game features 4-player co-op, an AI Director pacing system, special infected enemies (Hunter, Smoker, Boomer, Tank, Witch, Charger, Spitter), incapacitation/revival mechanics, procedural room generation, and horror atmosphere systems.

## Development Environment

### Required Tools
```bash
# Install Rokit (Roblox toolchain manager)
# Then add tools:
rokit add rojo-rbx/rojo       # File sync (IDE ↔ Studio)
rokit add UpliftGames/wally   # Package manager
rokit add kampfkarren/selene  # Linter
rokit add JohnnyMorganz/StyLua # Formatter
```

### Commands
```bash
rokit install           # Install/update all tools (first time setup)
rojo serve              # Start file sync server
rojo build -o game.rbxl # Build place file
wally install           # Install dependencies
selene src/             # Lint code
stylua src/             # Format code
```

### IDE Setup
1. Install Rojo plugin in Roblox Studio
2. Run `rojo serve` in terminal
3. Connect via Rojo plugin in Studio

## Architecture Overview

### Directory Structure
```
src/
├── server/                    # Server-only → ServerScriptService/Server
│   ├── Server.server.lua     # Entry point (note: .server.lua suffix)
│   └── Services/
│       ├── EntityService.lua  # ALL NPC management (critical!)
│       ├── DirectorService.lua
│       ├── GameService.lua
│       ├── PlayerService.lua
│       ├── SpawnPointService.lua
│       ├── WeaponService.lua
│       └── Entities/
│           └── Hunter.lua
├── client/                    # Client-only → StarterPlayerScripts/Client
│   ├── Client.client.lua     # Entry point (note: .client.lua suffix)
│   └── Controllers/
│       └── UIController.lua
└── shared/                    # Shared → ReplicatedStorage/Shared
    └── Constants/
        └── GameConstants.lua
```

### Rojo Mapping (default.project.json)
- `src/server/` → `ServerScriptService/Server`
- `src/client/` → `StarterPlayerScripts/Client`
- `src/shared/` → `ReplicatedStorage/Shared`
- `Packages/` → `ReplicatedStorage/Packages`
- Remote events live in `ReplicatedStorage/Remotes`
- NPCs parent to `Workspace/Enemies`

### Core Services

#### EntityService (CRITICAL)
Manages ALL NPCs in a single script. This is the #1 performance requirement.
```lua
local EntityService = {}
EntityService.Entities = {}

RunService.Heartbeat:Connect(function(dt)
    for id, entity in EntityService.Entities do
        entity:Update(dt)
    end
end)
```

#### DirectorService (AI Director)
Controls game pacing through intensity tracking and spawn management.

**States:** BuildUp → SustainPeak (3-5s) → PeakFade → Relax (30-45s) → repeat

**Intensity Sources:**
- Damage taken: +damage × 0.5
- Player incapacitated: +15
- Nearby zombie killed: +3
- Decay: -5/second when not in combat

#### GameService
Manages game state machine: Lobby → Loading → Playing → SafeRoom → Finale → Victory/Failed

### Service Initialization Order
In Server.server.lua, services start in this order (dependencies matter):
1. GameService
2. PlayerService
3. SpawnPointService (must be before DirectorService)
4. EntityService
5. WeaponService
6. DirectorService

## Code Standards

### File Header
```lua
--!strict
--[[
    ModuleName
    Brief description
]]
```

### Naming Conventions
| Type | Convention | Example |
|------|------------|---------|
| Classes/Modules | PascalCase | `EntityService` |
| Functions/Variables | camelCase | `updateEnemy` |
| Constants | UPPER_SNAKE | `MAX_HEALTH` |
| Private members | _prefix | `_lastUpdate` |
| Types | PascalCase | `EntityState` |

### Required Patterns

**Always use GetService:**
```lua
local Players = game:GetService("Players")  -- Correct
local Players = game.Players                 -- Wrong
```

**Always type annotate parameters:**
```lua
function Enemy:TakeDamage(amount: number, source: Player?)
```

**Singleton Service Pattern:**
```lua
local Service = {}
Service.__index = Service
local _instance = nil

function Service.new()
    if _instance then return _instance end
    local self = setmetatable({}, Service)
    -- Initialize
    _instance = self
    return self
end

function Service:Get()
    return Service.new()
end
```

**Update Throttling:**
```lua
function Entity:Update(dt: number)
    local now = os.clock()
    if now - self._lastUpdate < 0.0625 then return end  -- 16 Hz
    self._lastUpdate = now
    -- AI logic
end
```

## Performance Requirements

### Targets
- 60 FPS with 50-100 active NPCs
- <25 KB/s network per player
- <512 MB memory

### Mandatory Optimizations

1. **Single-script NPC management** - Never one script per enemy
2. **Collision groups** - Zombies don't collide with zombies
3. **Disable unused Humanoid states:**
```lua
humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
```
4. **Server network ownership:**
```lua
part:SetNetworkOwner(nil)
```
5. **Leader-follower pathfinding** - Only 20% compute paths, rest follow

## Network Security

### Remote Event Validation (Server)
```lua
Remote.OnServerEvent:Connect(function(player, targetId, damage)
    -- Rate limit
    if not RateLimit:Check(player) then return end
    
    -- Type validation
    if typeof(targetId) ~= "number" then return end
    if typeof(damage) ~= "number" then return end
    
    -- NaN check
    if damage ~= damage then return end
    
    -- Sanity check
    if damage < 0 or damage > 1000 then return end
    
    -- Process...
end)
```

## Key Game Mechanics

### Incapacitation System
- 0 HP → Incapacitated (not dead)
- 300 HP buffer while incapped
- Bleedout: -1 HP/second
- Revival: 5 seconds, restores 30 HP
- 3rd incap → Death
- Safe room resets incap count

### AI Director Spawn Rules
- Never spawn in player line-of-sight
- 75% spawn behind players
- Commons: 90-180s wave interval
- Specials: Individual 15-30s timers
- Max 2-4 specials active

### Safe Room
- Heals players to 50 HP minimum
- Resets incap count
- Director pauses spawning
- Exit requires all players ready

## Documentation
Detailed implementation guides in `/docs/`:
- `ai-director.md` - Complete pacing system
- `enemy-patterns.md` - All special infected behaviors
- `horror-atmosphere.md` - Lighting, sound, effects
- `multiplayer.md` - Co-op, weapons, revival
- `performance.md` - Optimization patterns
- `procedural-generation.md` - Room system
- `luau-cheatsheet.md` - Luau language reference
- `roblox-services.md` - Roblox API reference

## When Generating Code

### Always Include
1. `--!strict` at file top
2. Type annotations on function parameters
3. Proper error handling
4. Connection cleanup in `:Destroy()`
5. Update throttling for AI

### Never Do
1. One script per NPC
2. Trust client data
3. Use `while true do` for game loops (use RunService)
4. Direct property access instead of GetService
5. Forget network ownership for NPCs

## Quick Reference

### Entity FSM States
`Idle | Patrol | Chase | Attack | Stagger | Dead`

Hunter-specific states: `Stalk | Crouch | Pounce | Pinning | Stunned`
Smoker-specific states: `Idle | Stalk | Aim | Grab | Dragging | Stagger | Dead`
Boomer-specific states: `Idle | Stalk | Approach | Vomit | Stagger | Dead`
Tank-specific states: `Idle | Chase | Attack | ThrowRock | Rage | Stagger | Dead`

### Special Infected
| Type | Mechanic | HP |
|------|----------|-----|
| Hunter | Pounce + Pin | 250 |
| Smoker | Tongue grab + Drag | 250 |
| Boomer | Explosion + Bile attract | 50 |
| Tank | Boss, rock throw | 6000 |
| Witch | Avoidance, 1-shot | 1000 |
| Charger | Charge + Slam | 600 |
| Spitter | Acid pool DOT | 100 |

### Collision Groups
Configured in Server.server.lua:
- `Players` - Player characters
- `Zombies` - All NPCs (self-collision disabled for performance)
- `Projectiles` - Bullets, etc.
- `Debris` - Non-gameplay elements

### Remote Events
Created in `ReplicatedStorage/Remotes`:
`DealDamage`, `PlayerAction`, `EntityUpdate`, `GameState`, `RevivePlayer`, `UseItem`, `AttemptRescue`, `FireWeapon`, `FireResult`, `AmmoUpdate`

### Weapon Slots
Primary, Secondary (Pistol, infinite), Throwable, Medical

## Test Commands (Chat)
| Command | Action |
|---------|--------|
| `/start` | Start the game (transitions from Lobby to Playing) |
| `/test` | Spawn 5 common zombies around player |
| `/hunter` | Spawn a Hunter 20 studs in front |
| `/smoker` | Spawn a Smoker 30 studs in front |
| `/boomer` | Spawn a Boomer 20 studs in front |
| `/tank` | Spawn a Tank 30 studs in front (boss!) |
| `/witch` | Spawn a Witch 20 studs in front (don't startle her!) |
| `/charger` | Spawn a Charger 25 studs in front (watch the charge!) |
| `/spitter` | Spawn a Spitter 30 studs in front (avoid the acid!) |
| `/saferoom` | Trigger safe room benefits (heal, reset incap) |
| `/kill` | Kill all enemies |
| `/heal` | Heal player to full health |

## Current Implementation Status

### Completed Systems
- **EntityService** - Single-script NPC management with update loop, bile attraction
- **DirectorService** - AI Director with pacing states and client notifications
- **WeaponService** - Pistol with server-authoritative hit detection
- **PlayerService** - Health, incap, revival, rescue from pin/grab, damage events
- **Hunter** - Full state machine (Stalk→Crouch→Pounce→Pinning)
- **Smoker** - Tongue grab, drag mechanics (Stalk→Aim→Grab→Dragging)
- **Boomer** - Explosion on death, bile vomit, bile attraction for common infected
- **Tank** - Boss enemy with rock throwing, rage mode, frustration mechanic (6000 HP)
- **Witch** - Avoidance enemy with startle mechanic, instant incap (1000 HP)
- **UIController** - Health bar, teammate cards, incap overlay, death screen, game state notifications
- **AmbientSoundController** - Horror atmosphere sounds, heartbeat on low health
- **DamageFeedbackController** - Damage vignette, hit markers, directional indicators, camera shake
- **HorrorLightingController** - Fog, color correction, flickering lights, intensity-based effects
- **SafeRoomService** - Safe room zone detection, healing to 50 HP, incap reset
- **Flashlight** - F key toggle for player flashlight
- **Test Environment** - 3-room layout with spawn points

### Test Environment Layout
```
Start Room (40x40) → Corridor (20x60) → Safe Room (30x30)
   (0,0,0)              (50,0,0)           (95,0,0)
```

### Spawn Points
- 4 Common in Start Room corners
- 2 Common in Corridor
- 1 Special in Corridor (for Hunter)
- None in Safe Room
