# Testing Guide for L4D2 Roblox Game

## Pre-Testing Setup

### 1. Start Rojo Server
```bash
rojo serve
```

### 2. Connect in Roblox Studio
- Open Roblox Studio
- Connect to Rojo server
- Wait for all files to sync

### 3. Verify Services Loaded
Check Output window for:
```
[Server] Initializing L4D2 Horror Game...
[Server] Starting services...
[GameService] Started
[PlayerService] Started
[SpawnPointService] Started
[EntityService] Started
[WeaponService] Started
[SafeRoomService] Started
[DirectorService] Started
[Server] All services started successfully
[Server] Server ready!
```

## Test Checklist

### ✅ Core Systems

#### Service Initialization
- [ ] All services print "Started" messages
- [ ] No errors in Output window
- [ ] TestEnvironment folder created in workspace
- [ ] SpawnPoints folder created with 7 spawn points

#### Test Environment
- [ ] Start Room visible (40x40 studs, gray floor)
- [ ] Corridor visible (20x60 studs)
- [ ] Safe Room visible (30x30 studs, green floor)
- [ ] Spawn points visible (neon red/orange parts)
- [ ] Lighting is dark (RGB 20,20,30, brightness 0.3)
- [ ] Point lights in each room

### ✅ Spawning System

#### Common Zombies
- [ ] Type `/test` in chat
- [ ] 5 zombies spawn around player
- [ ] Zombies appear at neon spawn points
- [ ] Zombies chase player
- [ ] Zombies attack when close

#### Special Infected
- [ ] Type `/hunter` - Hunter spawns 20 studs in front
- [ ] Type `/smoker` - Smoker spawns 30 studs in front
- [ ] Type `/boomer` - Boomer spawns 15 studs in front
- [ ] All special infected have correct models
- [ ] All special infected have correct behaviors

### ✅ Hunter Mechanics
- [ ] Hunter stalks player
- [ ] Hunter crouches before pouncing
- [ ] Hunter pounces and pins player
- [ ] Pinned player sees incap overlay
- [ ] Teammate can rescue pinned player (press E)
- [ ] Hunter takes damage when shot
- [ ] Hunter dies and ragdolls

### ✅ Smoker Mechanics
- [ ] Smoker stalks player
- [ ] Smoker extends tongue (beam visible)
- [ ] Tongue grabs player from 50 studs
- [ ] Player is dragged toward Smoker
- [ ] Player takes damage while grabbed
- [ ] Teammate can rescue grabbed player
- [ ] Smoker dies and ragdolls

### ✅ Boomer Mechanics
- [ ] Boomer chases player
- [ ] Boomer explodes on death
- [ ] Explosion applies bile to nearby players
- [ ] Biled players have green tint/effect
- [ ] Common zombies detect biled players from farther away
- [ ] DirectorService spawns extra horde when player biled
- [ ] Bile wears off after duration

### ✅ Weapon System
- [ ] Player spawns with pistol
- [ ] Ammo display shows "15 / ∞"
- [ ] Left-click fires weapon
- [ ] Muzzle flash appears
- [ ] Gunshot sound plays
- [ ] Ammo decreases on client (prediction)
- [ ] Server validates ammo
- [ ] Ammo updates reconcile with server
- [ ] Hits register on enemies
- [ ] Enemies take damage
- [ ] Headshots do extra damage

### ✅ Safe Room System
- [ ] Walk into Safe Room (green floor)
- [ ] Console shows "[SafeRoomService] [PlayerName] entered safe room"
- [ ] All players in safe room triggers activation
- [ ] Console shows "[SafeRoomService] All players in safe room! Entering safe state."
- [ ] DirectorService stops spawning
- [ ] Players heal at 5 HP/second
- [ ] Incapacitated players auto-revive
- [ ] Walk out of safe room
- [ ] Console shows "[SafeRoomService] [PlayerName] exited safe room"
- [ ] Spawning resumes

### ✅ Player Health System
- [ ] Player starts with 100 HP
- [ ] Health bar visible in UI
- [ ] Taking damage reduces health
- [ ] Health bar color changes (green → yellow → red)
- [ ] At 0 HP, player becomes incapacitated
- [ ] Incap overlay appears
- [ ] Player bleeds out at 1 HP/second
- [ ] Teammate can revive (hold E)
- [ ] Revive progress bar appears
- [ ] After 5 seconds, player revived with 30 HP
- [ ] 3rd incap = death

### ✅ Client-Server Communication
- [ ] All remote events created
- [ ] Client connects to remotes
- [ ] FireWeapon remote works
- [ ] AmmoUpdate remote works
- [ ] GameState remote works
- [ ] DamageEvent remote works
- [ ] No remote errors in Output

### ✅ Performance
- [ ] Game runs at 60 FPS with 10 zombies
- [ ] Game runs at 60 FPS with 50 zombies
- [ ] No memory leaks (check memory over 5 minutes)
- [ ] Entity cleanup works (dead entities removed)
- [ ] No orphaned references

## Test Commands Reference

| Command | Function | Expected Result |
|---------|----------|----------------|
| `/test` | Spawn 5 common zombies | Zombies appear at spawn points |
| `/hunter` | Spawn Hunter | Hunter spawns 20 studs in front |
| `/smoker` | Spawn Smoker | Smoker spawns 30 studs in front |
| `/boomer` | Spawn Boomer | Boomer spawns 15 studs in front |
| `/tank` | Spawn Tank | Tank spawns (if implemented) |
| `/kill` | Kill all enemies | All enemies die |
| `/heal` | Heal player | Player health = 100 |
| `/start` | Start game | Game state changes to "Playing" |
| `/saferoom` | Trigger safe room | Safe room activates |

## Common Issues & Solutions

### Issue: Services not starting
**Solution**: Check that all service files exist in `Server/Services/` folder

### Issue: Spawn points not visible
**Solution**: Check that `setupWorkspace()` ran successfully. Look for "[Server] Created 7 spawn points" message

### Issue: Safe room not working
**Solution**: 
1. Check that SafeRoomZone part exists in TestEnvironment
2. Check SafeRoomService found the zone (look for "[SafeRoomService] Found SafeRoomZone" message)
3. Verify all players are inside the zone bounds

### Issue: Ammo not updating
**Solution**:
1. Check that WeaponService started
2. Check AmmoUpdate remote exists
3. Check client connected to remote
4. Look for ammo reconciliation logs

### Issue: Special infected not spawning
**Solution**:
1. Check EntityService started
2. Check DirectorService started
3. Verify spawn command syntax (case-sensitive)
4. Check console for error messages

## Performance Benchmarks

### Target Performance
- **60 FPS** with 50-100 active NPCs
- **16 Hz** update rate for AI logic
- **<100ms** frame time
- **<500MB** memory usage

### Monitoring
- Use Roblox Studio's Performance tab
- Monitor FPS, memory, and network usage
- Check for memory leaks over extended play

## Multiplayer Testing

### 2-4 Player Testing
- [ ] All players spawn correctly
- [ ] Health synced across clients
- [ ] Damage applies correctly
- [ ] Special infected visible to all
- [ ] Safe room works with multiple players
- [ ] Revive system works between players
- [ ] No desync issues

## Next Steps After Testing

1. **Document Bugs**: Create issues for any bugs found
2. **Performance Tuning**: Optimize if FPS drops below 60
3. **Balance Adjustments**: Tune damage, health, spawn rates
4. **Feature Additions**: Implement missing features from TODO list

## Success Criteria

✅ **Game is ready for production if:**
- All core systems work
- No critical bugs
- Performance meets targets
- Multiplayer works correctly
- All test commands function
