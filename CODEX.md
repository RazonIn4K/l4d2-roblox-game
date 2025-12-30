# Architecture Overview - L4D2 Roblox Game

## System Architecture Visual

```
                              ┌──────────────────────────────────────────────────────────────┐
                              │                      ROBLOX ENGINE                            │
                              └──────────────────────────────────────────────────────────────┘
                                                          │
                    ┌─────────────────────────────────────┴─────────────────────────────────────┐
                    │                                                                           │
           ┌────────▼────────┐                                                        ┌────────▼────────┐
           │     SERVER      │                                                        │     CLIENT      │
           │ ServerScript    │                                                        │ LocalScript     │
           │    Service      │                                                        │   Scripts       │
           └────────┬────────┘                                                        └────────┬────────┘
                    │                                                                          │
     ┌──────────────┴──────────────────────────────────────┐              ┌───────────────────┴──────────────────┐
     │                                                     │              │                                      │
┌────▼────┐                                          ┌─────▼─────┐  ┌─────▼─────┐                          ┌─────▼─────┐
│ Server  │                                          │  Remotes  │  │ Remotes   │                          │  Client   │
│ .server │                                          │   (TX)    │  │   (RX)    │                          │  .client  │
│  .lua   │                                          │           │  │           │                          │   .lua    │
└────┬────┘                                          └───────────┘  └───────────┘                          └─────┬─────┘
     │                                                                                                           │
     │  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────┐
     │  │                                        SERVICE LAYER                                                      │
     │  └───────────────────────────────────────────────────────────────────────────────────────────────────────────┘
     │                                                                                                           │
     ├──────────────────────────────────────────────────────────────────────┐                                   │
     │                                                                      │                                   │
┌────▼─────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌──────────▼───────┐              ┌─────────────▼─────────────┐
│   GameService    │  │ PlayerService   │  │  WeaponService  │  │   EntityService  │              │      UIController         │
│                  │  │                 │  │                 │  │                  │              │                           │
│ • State Machine  │  │ • Health/Incap  │  │ • Pistol Logic  │  │ • NPC Management │              │ • Health Bar              │
│ • Lobby→Playing  │  │ • Revival       │  │ • Hit Detection │  │ • Update Loop    │              │ • Teammate Cards          │
│ • SafeRoom Logic │  │ • Rescue        │  │ • Ammo System   │  │ • Single Script! │              │ • Incap Overlay           │
│ • Win/Lose       │  │ • DamagePlayer  │  │ • Fire Results  │  │ • 16Hz Throttle  │              │ • Revive Progress         │
└────────┬─────────┘  └────────┬────────┘  └────────┬────────┘  └────────┬─────────┘              │ • Death Screen            │
         │                     │                    │                    │                        │ • Game Notifications      │
         │                     │                    │                    │                        └─────────────┬─────────────┘
         │                     │                    │                    │                                      │
         │           ┌─────────┴───────┐            │                    │                        ┌─────────────┼─────────────┐
         │           │                 │            │                    │                        │             │             │
         │    ┌──────▼──────┐   ┌──────▼──────┐     │           ┌───────▼────────┐        ┌──────▼──────┐ ┌────▼────┐ ┌──────▼──────┐
         │    │SafeRoomSvc  │   │SpawnPointSvc│     │           │ EntityFactory  │        │AmbientSound │ │Damage   │ │HorrorLight │
         │    │             │   │             │     │           │                │        │Controller   │ │Feedback │ │Controller  │
         │    │ • Triggers  │   │ • Registers │     │           │ • createHunter │        │             │ │Ctrl     │ │            │
         │    │ • Healing   │   │ • GetSpawn  │     │           │ • createTank   │        │ • Ambient   │ │         │ │ • Fog      │
         │    │ • Incap Rst │   │ • Filtering │     │           │ • createBoomer │        │ • Heartbeat │ │ • Vign. │ │ • Color    │
         └────│─────────────│───│─────────────│─────│───────────│ • createSmoker │        │ • Horror    │ │ • Shake │ │ • Flicker  │
              └─────────────┘   └──────┬──────┘     │           │ • createWitch  │        │   Stings    │ │ • HitMk │ │ • Tint     │
                                       │           │           │ • createCharger│        └─────────────┘ └─────────┘ └────────────┘
                                       │           │           │ • createSpitter│
                                       │           │           │ • createCommon │
                                       │           │           └───────┬────────┘
                                       │           │                   │
                    ┌──────────────────┴───────────┴───────────────────┴───────────────────────────────────────────────┐
                    │                                      DirectorService                                             │
                    │                                                                                                  │
                    │   ┌─────────────┐    ┌─────────────────────────────────────────────────────────────────────┐     │
                    │   │  AI States  │    │                      ENTITY SPAWNING                                │     │
                    │   │             │    │                                                                     │     │
                    │   │  BuildUp    │    │  SpawnPoints ──► LOS Check ──► Behind Player (75%) ──► Spawn      │     │
                    │   │     │       │    │                                                                     │     │
                    │   │     ▼       │    │  ┌──────────────────────────────────────────────────────────────┐  │     │
                    │   │ SustainPeak │    │  │ SPAWN TIMERS & LIMITS                                        │  │     │
                    │   │  (3-5s)     │    │  │                                                              │  │     │
                    │   │     │       │    │  │  Common:  90-180s intervals, Max 30 active                  │  │     │
                    │   │     ▼       │    │  │  Hunter:  15-30s, Max 2                                     │  │     │
                    │   │  PeakFade   │    │  │  Smoker:  15-30s, Max 2                                     │  │     │
                    │   │     │       │    │  │  Boomer:  15-30s, Max 1                                     │  │     │
                    │   │     ▼       │    │  │  Tank:    120-180s, Max 1 (boss)                            │  │     │
                    │   │   Relax     │    │  │  Witch:   90-120s, Max 1 (ambient)                          │  │     │
                    │   │  (30-45s)   │    │  │  Charger: 15-30s, Max 2                                     │  │     │
                    │   │     │       │    │  │  Spitter: 15-30s, Max 2                                     │  │     │
                    │   │     ▼       │    │  └──────────────────────────────────────────────────────────────┘  │     │
                    │   │  (repeat)   │    │                                                                     │     │
                    │   └─────────────┘    └─────────────────────────────────────────────────────────────────────┘     │
                    │                                                                                                  │
                    │   ┌─────────────────────────────────────────────────────────────────────────────────────────┐    │
                    │   │ INTENSITY TRACKING                                                                      │    │
                    │   │   • Damage taken: +damage × 0.5    • Zombie killed: +3                                 │    │
                    │   │   • Incap: +15                     • Decay: -5/sec when not in combat                  │    │
                    │   │   • Peak threshold: 70             • Triggers BuildUp → SustainPeak transition         │    │
                    │   └─────────────────────────────────────────────────────────────────────────────────────────┘    │
                    └──────────────────────────────────────────────────────────────────────────────────────────────────┘


     ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
     │                                              ENTITY HIERARCHY                                                     │
     └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

                                              ┌────────────────────┐
                                              │     BaseEnemy      │
                                              │                    │
                                              │ • Update(dt)       │
                                              │ • TransitionTo()   │
                                              │ • DetectTarget()   │
                                              │ • MoveToTarget()   │
                                              │ • TakeDamage()     │
                                              │ • Die()            │
                                              │ • HasLineOfSight() │
                                              │ • Bile Attraction  │
                                              └─────────┬──────────┘
                                                        │
        ┌───────────────┬───────────────┬───────────────┼───────────────┬───────────────┬───────────────┐
        │               │               │               │               │               │               │
  ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐
  │  Hunter   │   │  Smoker   │   │  Boomer   │   │   Tank    │   │   Witch   │   │  Charger  │   │  Spitter  │
  │           │   │           │   │           │   │           │   │           │   │           │   │           │
  │ HP: 250   │   │ HP: 250   │   │ HP: 50    │   │ HP: 6000  │   │ HP: 1000  │   │ HP: 600   │   │ HP: 100   │
  │           │   │           │   │           │   │           │   │           │   │           │   │           │
  │ States:   │   │ States:   │   │ States:   │   │ States:   │   │ States:   │   │ States:   │   │ States:   │
  │ • Idle    │   │ • Idle    │   │ • Idle    │   │ • Idle    │   │ • Idle    │   │ • Idle    │   │ • Idle    │
  │ • Stalk   │   │ • Stalk   │   │ • Chase   │   │ • Chase   │   │ • Startled│   │ • Chase   │   │ • Chase   │
  │ • Crouch  │   │ • Aim     │   │ • Vomit   │   │ • Attack  │   │ • Attack  │   │ • WindUp  │   │ • Spit    │
  │ • Pounce  │   │ • Grab    │   │ • Attack  │   │ • RockThr │   │ • Dead    │   │ • Charge  │   │ • Flee    │
  │ • Pinning │   │ • Dragging│   │ • Stagger │   │ • Rage    │   │           │   │ • Slamming│   │ • Stagger │
  │ • Stagger │   │ • Stagger │   │ • Dead    │   │ • Stagger │   │ Mechanic: │   │ • Stagger │   │ • Dead    │
  │ • Dead    │   │ • Dead    │   │           │   │ • Dead    │   │ Startle & │   │ • Dead    │   │           │
  │           │   │           │   │ Mechanic: │   │           │   │ instant   │   │           │   │ Mechanic: │
  │ Mechanic: │   │ Mechanic: │   │ Explode   │   │ Mechanic: │   │ incap on  │   │ Mechanic: │   │ Acid spit │
  │ Pounce &  │   │ Tongue    │   │ on death, │   │ Rock thr, │   │ attacker  │   │ Charge &  │   │ creates   │
  │ pin until │   │ grab from │   │ bile attr │   │ rage mode │   │           │   │ grab, +   │   │ DOT pool  │
  │ rescued   │   │ distance  │   │ zombies   │   │ ground pd │   │           │   │ slam loop │   │ (8 dmg/s) │
  └───────────┘   └───────────┘   └───────────┘   └───────────┘   └───────────┘   └───────────┘   └───────────┘


     ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
     │                                          DATA FLOW: REMOTE EVENTS                                                │
     └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

                           SERVER                                              CLIENT

                    ┌─────────────────┐                                 ┌─────────────────┐
                    │  WeaponService  │◄────── FireWeapon ──────────────│  Input Handler  │
                    │                 │─────── FireResult ─────────────►│                 │
                    │                 │─────── AmmoUpdate ─────────────►│                 │
                    └─────────────────┘                                 └─────────────────┘

                    ┌─────────────────┐                                 ┌─────────────────┐
                    │  PlayerService  │◄────── AttemptRescue ───────────│  Rescue Prompt  │
                    │                 │─────── GameState ──────────────►│                 │
                    │                 │  (TeamHealth, Incap, Revived)   │  UIController   │
                    └─────────────────┘                                 └─────────────────┘

                    ┌─────────────────┐                                 ┌─────────────────┐
                    │  GameService    │─────── GameState ──────────────►│  State Display  │
                    │                 │  (Playing, SafeRoom, Victory)   │                 │
                    └─────────────────┘                                 └─────────────────┘

                    ┌─────────────────┐                                 ┌─────────────────┐
                    │ DirectorService │─────── GameState ──────────────►│  Lighting/Sound │
                    │                 │  (BuildUp, Crescendo)           │  Controllers    │
                    └─────────────────┘                                 └─────────────────┘


     ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
     │                                          FILE STRUCTURE                                                          │
     └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

     src/
     ├── server/                                    → ServerScriptService/Server
     │   ├── Server.server.lua                     # Entry point, collision groups, remotes, service init
     │   └── Services/
     │       ├── GameService.lua         (248 ln)  # Game state machine
     │       ├── PlayerService.lua       (589 ln)  # Health, incap, revival, rescue
     │       ├── EntityService.lua       (480 ln)  # NPC management, spawn functions
     │       ├── DirectorService.lua     (669 ln)  # AI Director, pacing, spawn logic
     │       ├── WeaponService.lua       (269 ln)  # Weapons, hit detection
     │       ├── SafeRoomService.lua     (165 ln)  # Safe room triggers/healing
     │       ├── SpawnPointService.lua   (169 ln)  # Spawn point registration
     │       ├── EntityFactory.lua       (865 ln)  # Model creation for all entities
     │       ├── BaseEnemy.lua           (312 ln)  # Base class for all NPCs
     │       └── Entities/
     │           ├── Hunter.lua          (487 ln)  # Pounce + pin mechanic
     │           ├── Smoker.lua          (502 ln)  # Tongue grab + drag
     │           ├── Boomer.lua          (511 ln)  # Explosion + bile attraction
     │           ├── Tank.lua            (698 ln)  # Boss, rock throw, rage
     │           ├── Witch.lua           (546 ln)  # Startle + instant incap
     │           ├── Charger.lua         (726 ln)  # Charge + grab + slam
     │           └── Spitter.lua         (559 ln)  # Acid projectile + DOT pool
     │
     ├── client/                                    → StarterPlayerScripts/Client
     │   ├── Client.client.lua           (484 ln)  # Entry, input, shooting, flashlight
     │   └── Controllers/
     │       ├── UIController.lua        (918 ln)  # All HUD elements
     │       ├── AmbientSoundController.lua (284 ln)  # Horror sounds, heartbeat
     │       ├── DamageFeedbackController.lua (488 ln) # Vignette, hit markers, shake
     │       └── HorrorLightingController.lua (406 ln) # Fog, color correction, flicker
     │
     └── shared/                                    → ReplicatedStorage/Shared
         └── Constants/
             └── GameConstants.lua        (52 ln)  # Shared constants

     Total: ~8,000 lines of Luau code


     ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
     │                                          GAME STATE MACHINE                                                      │
     └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

     ┌─────────┐     All players      ┌─────────┐    Map loaded     ┌─────────┐
     │  Lobby  │────────ready────────►│ Loading │──────────────────►│ Playing │
     └─────────┘                       └─────────┘                   └────┬────┘
                                                                          │
                                           ┌──────────────────────────────┤
                                           │                              │
                                           ▼                              ▼
                                    ┌───────────┐                   ┌───────────┐
                                    │  SafeRoom │                   │  Failed   │
                                    │           │                   │ (all dead)│
                                    └─────┬─────┘                   └───────────┘
                                          │
                      All players ready   │
                           ┌──────────────┴──────────────┐
                           ▼                              ▼
                    ┌───────────┐                   ┌───────────┐
                    │  Playing  │                   │  Finale   │──────►┌─────────┐
                    │(next map) │                   │           │       │ Victory │
                    └───────────┘                   └───────────┘       └─────────┘


     ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
     │                                          INCAPACITATION FLOW                                                     │
     └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

     ┌────────────┐     0 HP      ┌──────────────┐    Bleedout     ┌────────────┐
     │   Alive    │──────────────►│ Incapacitated│───────────────►│    Dead    │
     │  (100 HP)  │               │  (300 HP buf)│   (-1 HP/sec)   │            │
     └────────────┘               └───────┬──────┘                 └────────────┘
                                          │
                                     Revived (5s)
                                     +30 HP
                                          │
                                          ▼
                                   ┌────────────┐
                                   │   Alive    │
                                   │  (30 HP)   │
                                   │  Incaps++  │
                                   └────────────┘

     Max Incaps: 2 (3rd = permanent death)
     Safe Room: Resets incap count, heals to 50 HP minimum


     ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
     │                                      SPECIAL INFECTED COMPARISON                                                  │
     └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

     ┌──────────┬────────┬────────────────┬─────────────────────────────────────────────────────────────────────────────┐
     │ Infected │   HP   │  Role          │  Mechanic                                                                   │
     ├──────────┼────────┼────────────────┼─────────────────────────────────────────────────────────────────────────────┤
     │ Hunter   │   250  │ Assassin       │ Pounces from distance, pins and damages until teammate rescues             │
     │ Smoker   │   250  │ Crowd Control  │ Tongue grabs from 50 studs, drags victim toward it                         │
     │ Boomer   │    50  │ Disruptor      │ Explodes on death, bile attracts all common infected to covered players    │
     │ Tank     │  6000  │ Boss           │ Massive HP, throws rocks, enters rage mode when frustrated                 │
     │ Witch    │  1000  │ Avoidance      │ Stationary until startled, then instantly incapacitates the disturber      │
     │ Charger  │   600  │ Bruiser        │ Charges through group, grabs one, slams repeatedly                         │
     │ Spitter  │   100  │ Area Denial    │ Spits acid that creates damaging pool (8 dmg/sec for 8 sec)                │
     └──────────┴────────┴────────────────┴─────────────────────────────────────────────────────────────────────────────┘


## Implementation Status

### Completed Systems

| System | Status | File(s) | Notes |
|--------|--------|---------|-------|
| Server Entry | Done | Server.server.lua | Collision groups, remotes, service init |
| Game State | Done | GameService.lua | State machine with transitions |
| Player Health | Done | PlayerService.lua | Incap, revival, rescue, bleedout |
| Entity Management | Done | EntityService.lua | Single-script NPC updates at 16Hz |
| AI Director | Done | DirectorService.lua | Pacing states, spawn control |
| Weapons | Done | WeaponService.lua | Server-authoritative hit detection |
| Safe Rooms | Done | SafeRoomService.lua | Healing, incap reset |
| Spawn Points | Done | SpawnPointService.lua | Registration and filtering |
| Entity Factory | Done | EntityFactory.lua | Model creation for all 8 entity types |
| Hunter | Done | Hunter.lua | Full pounce/pin mechanic |
| Smoker | Done | Smoker.lua | Tongue grab + drag |
| Boomer | Done | Boomer.lua | Explosion + bile attraction |
| Tank | Done | Tank.lua | Rock throw + rage mode |
| Witch | Done | Witch.lua | Startle + instant incap |
| Charger | Done | Charger.lua | Charge + slam loop |
| Spitter | Done | Spitter.lua | Acid pools with DOT |
| Client Entry | Done | Client.client.lua | Input, shooting, flashlight |
| UI | Done | UIController.lua | Health, teammates, incap, notifications |
| Ambient Sound | Done | AmbientSoundController.lua | Horror atmosphere |
| Damage Feedback | Done | DamageFeedbackController.lua | Vignette, shake, hit markers |
| Horror Lighting | Done | HorrorLightingController.lua | Fog, color, flicker |

### Test Commands

| Command | Effect |
|---------|--------|
| `/test` | Spawn 5 common zombies around player |
| `/hunter` | Spawn Hunter 20 studs ahead |
| `/kill` | Kill all enemies |
| `/heal` | Heal to full HP |

### Verification

```bash
# Lint (0 errors, 1 warning in Tank.lua)
selene src/

# Build (success)
rojo build -o game.rbxl
```

## Key Design Decisions

1. **Single-Script NPC Management**: All NPCs managed by EntityService with one Heartbeat loop for performance
2. **Lazy-Loaded Services**: Entity files use `getPlayerService()` pattern to avoid circular dependencies
3. **State Machine Pattern**: Every special infected uses explicit state transitions with `TransitionTo()`
4. **Server Authority**: All damage, spawning, and game state controlled server-side
5. **16Hz Update Throttle**: AI logic runs at 16Hz instead of every frame for performance
6. **Bile Attraction**: BaseEnemy detects "IsBiled" attribute for Boomer synergy
