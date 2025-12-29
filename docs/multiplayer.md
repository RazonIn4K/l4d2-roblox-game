# Multiplayer & Co-op Systems

## Table of Contents
1. [4-Player Co-op Architecture](#4-player-co-op-architecture)
2. [Incapacitation & Revival](#incapacitation--revival)
3. [Safe Room Mechanics](#safe-room-mechanics)
4. [Weapon Systems](#weapon-systems)
5. [Shared Resources](#shared-resources)
6. [Network Security](#network-security)
7. [Player Synchronization](#player-synchronization)

---

## 4-Player Co-op Architecture

### Team Management

```lua
--!strict
local TeamManager = {}
TeamManager.__index = TeamManager

export type TeamState = "Lobby" | "Loading" | "Playing" | "SafeRoom" | "Finale" | "Failed" | "Victory"

export type PlayerState = "Alive" | "Incapacitated" | "Dead" | "Spectating"

export type PlayerData = {
    player: Player,
    state: PlayerState,
    health: number,
    maxHealth: number,
    incapCount: number,  -- Times downed this chapter
    reviveProgress: number,
    lastDamageTime: number,
    inventory: {string},
}

function TeamManager.new()
    local self = setmetatable({}, TeamManager)
    
    self.State = "Lobby" :: TeamState
    self.Players = {} :: {[Player]: PlayerData}
    self.MaxPlayers = 4
    self.MinPlayersToStart = 1
    
    -- Events
    self.OnStateChanged = Instance.new("BindableEvent")
    self.OnPlayerStateChanged = Instance.new("BindableEvent")
    
    return self
end

function TeamManager:AddPlayer(player: Player)
    if self:GetPlayerCount() >= self.MaxPlayers then
        return false, "Team is full"
    end
    
    self.Players[player] = {
        player = player,
        state = "Alive",
        health = 100,
        maxHealth = 100,
        incapCount = 0,
        reviveProgress = 0,
        lastDamageTime = 0,
        inventory = {"Pistol"},
    }
    
    return true
end

function TeamManager:GetPlayerCount(): number
    local count = 0
    for _ in self.Players do
        count += 1
    end
    return count
end

function TeamManager:GetAlivePlayers(): {PlayerData}
    local alive = {}
    for _, data in self.Players do
        if data.state == "Alive" or data.state == "Incapacitated" then
            table.insert(alive, data)
        end
    end
    return alive
end

function TeamManager:GetTeamHealth(): (number, number)  -- (current, max)
    local current, max = 0, 0
    for _, data in self.Players do
        if data.state ~= "Dead" and data.state ~= "Spectating" then
            current += data.health
            max += data.maxHealth
        end
    end
    return current, max
end

function TeamManager:IsTeamWiped(): boolean
    for _, data in self.Players do
        if data.state == "Alive" then
            return false
        end
    end
    return true
end

return TeamManager
```

### Game Flow Controller

```lua
local GameController = {}
GameController.__index = GameController

function GameController.new(teamManager: TeamManager, director: AIDirector)
    local self = setmetatable({}, GameController)
    
    self.Team = teamManager
    self.Director = director
    self.CurrentCheckpoint = nil
    self.ChapterNumber = 1
    
    return self
end

function GameController:StartChapter(chapterNumber: number)
    self.ChapterNumber = chapterNumber
    self.Team.State = "Playing"
    
    -- Reset player states
    for _, data in self.Team.Players do
        data.state = "Alive"
        data.health = data.maxHealth
        data.incapCount = 0
    end
    
    -- Start AI Director
    self.Director:Start()
    
    -- Begin spawning
    self.Director:TransitionTo("BuildUp")
end

function GameController:OnCheckpointReached(checkpointId: string)
    self.CurrentCheckpoint = checkpointId
    
    -- Save player states
    self:SaveCheckpointState()
end

function GameController:OnTeamWipe()
    self.Team.State = "Failed"
    self.Director:TransitionTo("Idle")
    
    -- Offer restart from checkpoint
    task.delay(3, function()
        self:PromptRestart()
    end)
end

function GameController:RestartFromCheckpoint()
    if not self.CurrentCheckpoint then
        self:RestartChapter()
        return
    end
    
    -- Restore checkpoint state
    self:LoadCheckpointState()
    
    -- Respawn players at checkpoint
    local spawnPoint = self:GetCheckpointSpawn(self.CurrentCheckpoint)
    for _, data in self.Team.Players do
        self:RespawnPlayer(data.player, spawnPoint)
    end
    
    self.Team.State = "Playing"
    self.Director:TransitionTo("Relax")  -- Grace period
end

return GameController
```

## Incapacitation & Revival

### L4D2-Style Incap System

```lua
local IncapSystem = {}
IncapSystem.__index = IncapSystem

-- Config
local INCAP_HEALTH = 300           -- Health buffer while incapped
local INCAP_BLEEDOUT_RATE = 1      -- HP/second lost while down
local REVIVE_TIME = 5              -- Seconds to revive
local REVIVE_HEALTH = 30           -- Health after revival
local MAX_INCAPS_BEFORE_DEATH = 2  -- Third down = death
local SELF_REVIVE_DELAY = 60       -- Seconds before self-revive available (with item)

function IncapSystem.new(teamManager: TeamManager)
    local self = setmetatable({}, IncapSystem)
    self.Team = teamManager
    self.ActiveRevives = {}  -- {[incappedPlayer]: {rescuer, progress}}
    return self
end

function IncapSystem:IncapacitatePlayer(playerData: PlayerData)
    playerData.incapCount += 1
    
    -- Check for death
    if playerData.incapCount > MAX_INCAPS_BEFORE_DEATH then
        self:KillPlayer(playerData)
        return
    end
    
    playerData.state = "Incapacitated"
    playerData.health = INCAP_HEALTH
    
    -- Apply incap effects
    local char = playerData.player.Character
    if char then
        -- Force prone/crawling state
        char:SetAttribute("IsIncapacitated", true)
        
        -- Disable normal movement
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 3  -- Slow crawl
            humanoid.JumpPower = 0
        end
        
        -- Allow pistol only
        self:RestrictToSidearm(playerData)
    end
    
    -- Start bleedout
    self:StartBleedout(playerData)
    
    -- Notify team
    self.Team.OnPlayerStateChanged:Fire(playerData.player, "Incapacitated")
end

function IncapSystem:StartBleedout(playerData: PlayerData)
    task.spawn(function()
        while playerData.state == "Incapacitated" do
            playerData.health -= INCAP_BLEEDOUT_RATE
            
            if playerData.health <= 0 then
                self:KillPlayer(playerData)
                break
            end
            
            task.wait(1)
        end
    end)
end

function IncapSystem:StartRevive(rescuer: Player, incapped: Player)
    local rescuerData = self.Team.Players[rescuer]
    local incappedData = self.Team.Players[incapped]
    
    if not rescuerData or not incappedData then return end
    if incappedData.state ~= "Incapacitated" then return end
    if rescuerData.state ~= "Alive" then return end
    
    -- Check distance
    local rescuerChar = rescuer.Character
    local incappedChar = incapped.Character
    if not rescuerChar or not incappedChar then return end
    
    local distance = (rescuerChar.PrimaryPart.Position - incappedChar.PrimaryPart.Position).Magnitude
    if distance > 5 then return end
    
    -- Start revive
    self.ActiveRevives[incapped] = {
        rescuer = rescuer,
        progress = 0,
        startTime = os.clock(),
    }
    
    -- Revive loop
    task.spawn(function()
        while self.ActiveRevives[incapped] do
            local reviveData = self.ActiveRevives[incapped]
            
            -- Check still in range
            local dist = (rescuerChar.PrimaryPart.Position - incappedChar.PrimaryPart.Position).Magnitude
            if dist > 6 then
                self:CancelRevive(incapped)
                break
            end
            
            -- Progress
            reviveData.progress += 1 / REVIVE_TIME
            
            if reviveData.progress >= 1 then
                self:CompleteRevive(incappedData)
                break
            end
            
            task.wait(1)
        end
    end)
end

function IncapSystem:CancelRevive(incapped: Player)
    self.ActiveRevives[incapped] = nil
end

function IncapSystem:CompleteRevive(playerData: PlayerData)
    self.ActiveRevives[playerData.player] = nil
    
    playerData.state = "Alive"
    playerData.health = REVIVE_HEALTH
    
    local char = playerData.player.Character
    if char then
        char:SetAttribute("IsIncapacitated", false)
        
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end
    
    self.Team.OnPlayerStateChanged:Fire(playerData.player, "Alive")
end

function IncapSystem:KillPlayer(playerData: PlayerData)
    playerData.state = "Dead"
    playerData.health = 0
    
    local char = playerData.player.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.Health = 0
        end
    end
    
    self.Team.OnPlayerStateChanged:Fire(playerData.player, "Dead")
    
    -- Check team wipe
    if self.Team:IsTeamWiped() then
        GameController:OnTeamWipe()
    end
end

return IncapSystem
```

### Rescue from Special Infected

```lua
function IncapSystem:OnPlayerPinned(player: Player, pinType: string, attacker: Model)
    local playerData = self.Team.Players[player]
    if not playerData then return end
    
    local char = player.Character
    if not char then return end
    
    char:SetAttribute("IsPinned", true)
    char:SetAttribute("PinType", pinType)
    char:SetAttribute("PinnedBy", attacker:GetAttribute("EntityId"))
    
    -- Disable all player actions
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
    end
end

function IncapSystem:RescueFromPin(rescuer: Player, pinned: Player)
    local pinnedChar = pinned.Character
    if not pinnedChar then return end
    
    if not pinnedChar:GetAttribute("IsPinned") then return end
    
    -- Check rescuer is close and has melee
    local rescuerChar = rescuer.Character
    if not rescuerChar then return end
    
    local distance = (rescuerChar.PrimaryPart.Position - pinnedChar.PrimaryPart.Position).Magnitude
    if distance > 4 then return end
    
    -- Get attacker and damage/stagger it
    local attackerId = pinnedChar:GetAttribute("PinnedBy")
    local attacker = EntityManager:GetEntityById(attackerId)
    if attacker then
        attacker:OnPinnedTargetRescued()
        attacker:TakeDamage(50, rescuer)  -- Shove damage
    end
    
    -- Free pinned player
    pinnedChar:SetAttribute("IsPinned", false)
    pinnedChar:SetAttribute("PinType", nil)
    pinnedChar:SetAttribute("PinnedBy", nil)
    
    local humanoid = pinnedChar:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 16
        humanoid.JumpPower = 50
    end
end
```

## Safe Room Mechanics

### Safe Room Controller

```lua
local SafeRoomController = {}
SafeRoomController.__index = SafeRoomController

function SafeRoomController.new(room: Model, teamManager: TeamManager)
    local self = setmetatable({}, SafeRoomController)
    
    self.Room = room
    self.Team = teamManager
    self.IsActive = false
    self.PlayersInside = {}
    self.EntryDoorClosed = false
    self.ExitDoorUnlocked = false
    
    self:SetupTriggers()
    
    return self
end

function SafeRoomController:SetupTriggers()
    -- Entry trigger
    local entryZone = self.Room:FindFirstChild("EntryZone")
    if entryZone then
        entryZone.Touched:Connect(function(hit)
            local player = Players:GetPlayerFromCharacter(hit.Parent)
            if player then
                self:OnPlayerEnter(player)
            end
        end)
    end
    
    -- Full room zone (for "all players ready" check)
    local fullZone = self.Room:FindFirstChild("FullZone")
    if fullZone then
        fullZone.Touched:Connect(function(hit)
            local player = Players:GetPlayerFromCharacter(hit.Parent)
            if player then
                self.PlayersInside[player] = true
                self:CheckAllPlayersReady()
            end
        end)
        
        fullZone.TouchEnded:Connect(function(hit)
            local player = Players:GetPlayerFromCharacter(hit.Parent)
            if player then
                self.PlayersInside[player] = nil
            end
        end)
    end
end

function SafeRoomController:OnPlayerEnter(player: Player)
    if self.IsActive then return end
    
    -- First player activates safe room
    self.IsActive = true
    self.Team.State = "SafeRoom"
    
    -- Notify AI Director
    AIDirector:EnterSafeRoom()
    
    -- Start safe room benefits
    self:StartHealing()
end

function SafeRoomController:StartHealing()
    -- Heal all players over time
    task.spawn(function()
        while self.IsActive do
            for _, playerData in self.Team.Players do
                if playerData.state == "Alive" then
                    -- Heal to 50 HP minimum
                    if playerData.health < 50 then
                        playerData.health = math.min(50, playerData.health + 5)
                    end
                end
                
                -- Reset incap count (fresh start)
                playerData.incapCount = 0
            end
            
            task.wait(1)
        end
    end)
end

function SafeRoomController:CheckAllPlayersReady()
    local allPlayers = self.Team:GetAlivePlayers()
    local allInside = true
    
    for _, playerData in allPlayers do
        if not self.PlayersInside[playerData.player] then
            allInside = false
            break
        end
    end
    
    if allInside then
        self:UnlockExitDoor()
    end
end

function SafeRoomController:UnlockExitDoor()
    if self.ExitDoorUnlocked then return end
    
    self.ExitDoorUnlocked = true
    
    local exitDoor = self.Room:FindFirstChild("ExitDoor")
    if exitDoor then
        exitDoor:SetAttribute("IsLocked", false)
        
        -- Visual/audio feedback
        -- Play unlock sound
        -- Show UI prompt
    end
end

function SafeRoomController:OnExitDoorOpened()
    self.IsActive = false
    self.Team.State = "Playing"
    
    -- Close entry door behind
    local entryDoor = self.Room:FindFirstChild("EntryDoor")
    if entryDoor then
        self:CloseDoor(entryDoor)
        self.EntryDoorClosed = true
    end
    
    -- Resume AI Director
    AIDirector:ExitSafeRoom()
end

return SafeRoomController
```

## Weapon Systems

### Weapon Manager

```lua
local WeaponManager = {}
WeaponManager.__index = WeaponManager

export type WeaponSlot = "Primary" | "Secondary" | "Throwable" | "Medical"

export type WeaponData = {
    name: string,
    slot: WeaponSlot,
    damage: number,
    fireRate: number,      -- Rounds per minute
    magazineSize: number,
    reserveAmmo: number,
    maxReserve: number,
    reloadTime: number,
    spread: number,
    range: number,
}

local WEAPONS: {[string]: WeaponData} = {
    -- Pistols (infinite ammo)
    Pistol = {
        name = "Pistol",
        slot = "Secondary",
        damage = 20,
        fireRate = 300,
        magazineSize = 15,
        reserveAmmo = math.huge,
        maxReserve = math.huge,
        reloadTime = 1.5,
        spread = 2,
        range = 100,
    },
    
    -- Primary weapons
    Shotgun = {
        name = "Shotgun",
        slot = "Primary",
        damage = 25,  -- Per pellet, 8 pellets
        fireRate = 60,
        magazineSize = 8,
        reserveAmmo = 56,
        maxReserve = 128,
        reloadTime = 0.5,  -- Per shell
        spread = 8,
        range = 30,
    },
    
    SMG = {
        name = "SMG",
        slot = "Primary",
        damage = 20,
        fireRate = 600,
        magazineSize = 50,
        reserveAmmo = 480,
        maxReserve = 650,
        reloadTime = 2.2,
        spread = 3,
        range = 80,
    },
    
    AssaultRifle = {
        name = "Assault Rifle",
        slot = "Primary",
        damage = 33,
        fireRate = 500,
        magazineSize = 50,
        reserveAmmo = 360,
        maxReserve = 360,
        reloadTime = 2.5,
        spread = 2,
        range = 120,
    },
    
    -- Throwables
    PipeBomb = {
        name = "Pipe Bomb",
        slot = "Throwable",
        damage = 0,  -- Attracts zombies, then explodes
        fireRate = 0,
        magazineSize = 1,
        reserveAmmo = 0,
        maxReserve = 1,
        reloadTime = 0,
        spread = 0,
        range = 50,
    },
    
    Molotov = {
        name = "Molotov",
        slot = "Throwable",
        damage = 10,  -- Per second in fire
        fireRate = 0,
        magazineSize = 1,
        reserveAmmo = 0,
        maxReserve = 1,
        reloadTime = 0,
        spread = 0,
        range = 40,
    },
    
    BileBomb = {
        name = "Bile Bomb",
        slot = "Throwable",
        damage = 0,  -- Attracts zombies to target
        fireRate = 0,
        magazineSize = 1,
        reserveAmmo = 0,
        maxReserve = 1,
        reloadTime = 0,
        spread = 0,
        range = 50,
    },
}

function WeaponManager.new(player: Player)
    local self = setmetatable({}, WeaponManager)
    
    self.Player = player
    self.Equipped = {
        Primary = nil,
        Secondary = "Pistol",
        Throwable = nil,
        Medical = nil,
    }
    self.CurrentSlot = "Secondary"
    self.AmmoReserves = {}
    
    return self
end

function WeaponManager:EquipWeapon(weaponName: string): boolean
    local weaponData = WEAPONS[weaponName]
    if not weaponData then return false end
    
    local slot = weaponData.slot
    
    -- Drop current weapon in slot (except pistol)
    if self.Equipped[slot] and self.Equipped[slot] ~= "Pistol" then
        self:DropWeapon(slot)
    end
    
    self.Equipped[slot] = weaponName
    self.AmmoReserves[weaponName] = weaponData.reserveAmmo
    
    return true
end

function WeaponManager:Fire(): (boolean, number?)
    local weaponName = self.Equipped[self.CurrentSlot]
    if not weaponName then return false, nil end
    
    local weaponData = WEAPONS[weaponName]
    if not weaponData then return false, nil end
    
    -- Check ammo
    local currentAmmo = self.AmmoReserves[weaponName] or 0
    if currentAmmo <= 0 and weaponData.reserveAmmo ~= math.huge then
        return false, nil  -- Out of ammo
    end
    
    -- Consume ammo
    if weaponData.reserveAmmo ~= math.huge then
        self.AmmoReserves[weaponName] = currentAmmo - 1
    end
    
    return true, weaponData.damage
end

function WeaponManager:AddAmmo(ammoType: string, amount: number)
    -- Find weapons that use this ammo type
    for weaponName, reserve in self.AmmoReserves do
        local weaponData = WEAPONS[weaponName]
        if weaponData and self:GetAmmoType(weaponName) == ammoType then
            self.AmmoReserves[weaponName] = math.min(
                reserve + amount,
                weaponData.maxReserve
            )
        end
    end
end

return WeaponManager
```

### Melee System

```lua
local MeleeSystem = {}

local MELEE_CONFIG = {
    damage = 250,              -- One-shots common infected
    range = 3,
    arc = 90,                  -- Degrees
    cooldown = 0.8,
    staminaCost = 15,
    maxStamina = 100,
    staminaRegen = 20,         -- Per second
    shoveDistance = 5,         -- Knockback
    shoveDamage = 50,
}

function MeleeSystem:PerformMelee(player: Player)
    local char = player.Character
    if not char then return end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    -- Get targets in arc
    local position = hrp.Position
    local lookVector = hrp.CFrame.LookVector
    
    local targets = self:GetTargetsInArc(position, lookVector, MELEE_CONFIG.range, MELEE_CONFIG.arc)
    
    for _, target in targets do
        if target:IsA("Model") then
            local humanoid = target:FindFirstChildOfClass("Humanoid")
            if humanoid then
                -- Damage
                humanoid:TakeDamage(MELEE_CONFIG.damage)
                
                -- Knockback
                local targetHRP = target:FindFirstChild("HumanoidRootPart")
                if targetHRP then
                    local direction = (targetHRP.Position - position).Unit
                    targetHRP.AssemblyLinearVelocity = direction * MELEE_CONFIG.shoveDistance * 10
                end
            end
        end
    end
    
    -- Free pinned teammates
    self:CheckRescueNearby(player, position)
end

function MeleeSystem:Shove(player: Player)
    -- Quick push with shorter cooldown, less damage
    -- Used to create space, not kill
    local char = player.Character
    if not char then return end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local targets = self:GetTargetsInArc(
        hrp.Position, 
        hrp.CFrame.LookVector, 
        MELEE_CONFIG.range * 0.7, 
        MELEE_CONFIG.arc * 0.5
    )
    
    for _, target in targets do
        local targetHRP = target:FindFirstChild("HumanoidRootPart")
        if targetHRP then
            local direction = (targetHRP.Position - hrp.Position).Unit
            targetHRP.AssemblyLinearVelocity = direction * 20 + Vector3.new(0, 5, 0)
            
            -- Stagger enemy
            local entity = EntityManager:GetEntityFromModel(target)
            if entity then
                entity:Stagger(0.5)
            end
        end
    end
end

return MeleeSystem
```

## Shared Resources

### Item Drop System

```lua
local ItemDropSystem = {}

function ItemDropSystem:DropItem(player: Player, itemName: string)
    local char = player.Character
    if not char then return end
    
    local position = char.PrimaryPart.Position + Vector3.new(0, 2, 0)
    
    local item = self:CreateDroppedItem(itemName, position)
    item.Parent = workspace.DroppedItems
    
    -- Remove from player inventory
    local inventory = InventoryManager:GetInventory(player)
    inventory:RemoveItem(itemName)
end

function ItemDropSystem:PickupItem(player: Player, item: Model)
    local itemName = item:GetAttribute("ItemName")
    if not itemName then return end
    
    local inventory = InventoryManager:GetInventory(player)
    
    -- Check if can pick up
    if not inventory:CanAddItem(itemName) then
        return false
    end
    
    inventory:AddItem(itemName)
    item:Destroy()
    
    return true
end

-- Give item to teammate
function ItemDropSystem:GiveItem(giver: Player, receiver: Player, itemName: string)
    local giverChar = giver.Character
    local receiverChar = receiver.Character
    
    if not giverChar or not receiverChar then return false end
    
    -- Check distance
    local distance = (giverChar.PrimaryPart.Position - receiverChar.PrimaryPart.Position).Magnitude
    if distance > 5 then return false end
    
    local giverInventory = InventoryManager:GetInventory(giver)
    local receiverInventory = InventoryManager:GetInventory(receiver)
    
    if not giverInventory:HasItem(itemName) then return false end
    if not receiverInventory:CanAddItem(itemName) then return false end
    
    giverInventory:RemoveItem(itemName)
    receiverInventory:AddItem(itemName)
    
    return true
end
```

### Medical Items

```lua
local MedicalSystem = {}

local MEDICAL_ITEMS = {
    Medkit = {
        healAmount = 80,
        useTime = 5,
        canHealOthers = true,
        clearsIncap = true,
    },
    
    Pills = {
        healAmount = 50,
        useTime = 1,
        canHealOthers = false,
        isTemporary = true,  -- Decays over time
        decayRate = 1,       -- Per second
    },
    
    Adrenaline = {
        healAmount = 25,
        useTime = 0.5,
        canHealOthers = false,
        speedBoost = 1.3,
        boostDuration = 15,
    },
    
    Defibrillator = {
        healAmount = 50,
        useTime = 3,
        canReviveDead = true,
    },
}

function MedicalSystem:UseMedical(user: Player, itemName: string, target: Player?)
    local config = MEDICAL_ITEMS[itemName]
    if not config then return false end
    
    target = target or user
    
    local userChar = user.Character
    local targetChar = target.Character
    if not userChar or not targetChar then return false end
    
    -- Check distance if healing others
    if target ~= user then
        if not config.canHealOthers then return false end
        
        local distance = (userChar.PrimaryPart.Position - targetChar.PrimaryPart.Position).Magnitude
        if distance > 3 then return false end
    end
    
    -- Start use animation/progress
    local success = self:PerformUse(user, target, config)
    
    if success then
        -- Apply heal
        local targetData = TeamManager.Players[target]
        if targetData then
            targetData.health = math.min(targetData.maxHealth, targetData.health + config.healAmount)
            
            -- Clear incap effects
            if config.clearsIncap then
                targetData.incapCount = math.max(0, targetData.incapCount - 1)
            end
        end
        
        -- Apply special effects
        if config.speedBoost then
            self:ApplySpeedBoost(target, config.speedBoost, config.boostDuration)
        end
        
        -- Remove item from inventory
        InventoryManager:GetInventory(user):RemoveItem(itemName)
    end
    
    return success
end

function MedicalSystem:PerformUse(user: Player, target: Player, config): boolean
    -- Channeled action - can be interrupted
    local startTime = os.clock()
    local userChar = user.Character
    
    while os.clock() - startTime < config.useTime do
        -- Check interruption conditions
        if not userChar or userChar:GetAttribute("IsStaggered") then
            return false
        end
        
        -- Check target still valid and in range
        if target ~= user then
            local targetChar = target.Character
            if not targetChar then return false end
            
            local distance = (userChar.PrimaryPart.Position - targetChar.PrimaryPart.Position).Magnitude
            if distance > 4 then return false end
        end
        
        task.wait(0.1)
    end
    
    return true
end

return MedicalSystem
```

## Network Security

### Server-Authoritative Validation

```lua
local RemoteValidator = {}

-- Rate limiting per player
local requestCounts = {}
local RATE_LIMIT = 20  -- Requests per second

function RemoteValidator:CheckRateLimit(player: Player): boolean
    local now = os.clock()
    
    if not requestCounts[player] then
        requestCounts[player] = {count = 0, resetTime = now + 1}
    end
    
    local data = requestCounts[player]
    
    if now > data.resetTime then
        data.count = 0
        data.resetTime = now + 1
    end
    
    data.count += 1
    
    return data.count <= RATE_LIMIT
end

-- Type validation
function RemoteValidator:ValidateTypes(args: {any}, schema: {string}): boolean
    if #args ~= #schema then return false end
    
    for i, expectedType in ipairs(schema) do
        if typeof(args[i]) ~= expectedType then
            return false
        end
    end
    
    return true
end

-- NaN check
function RemoteValidator:IsValidNumber(value: any): boolean
    return typeof(value) == "number" and value == value  -- NaN ~= NaN
end

-- Position sanity check
function RemoteValidator:IsValidPosition(player: Player, claimedPosition: Vector3): boolean
    local char = player.Character
    if not char then return false end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local actualPosition = hrp.Position
    local distance = (actualPosition - claimedPosition).Magnitude
    
    -- Allow some tolerance for network lag
    return distance < 10
end

-- Example: Damage remote validation
local DamageRemote = ReplicatedStorage.Remotes.DealDamage

DamageRemote.OnServerEvent:Connect(function(player, targetId, damage)
    -- Rate limit
    if not RemoteValidator:CheckRateLimit(player) then
        warn("Rate limit exceeded:", player.Name)
        return
    end
    
    -- Type validation
    if not RemoteValidator:ValidateTypes({targetId, damage}, {"number", "number"}) then
        warn("Invalid types from:", player.Name)
        return
    end
    
    -- NaN check
    if not RemoteValidator:IsValidNumber(damage) then
        warn("Invalid damage value from:", player.Name)
        return
    end
    
    -- Sanity check damage amount
    if damage < 0 or damage > 1000 then
        warn("Suspicious damage amount from:", player.Name)
        return
    end
    
    -- Verify player can actually deal this damage
    local weaponManager = WeaponManager:GetManager(player)
    local maxPossibleDamage = weaponManager:GetMaxDamage()
    
    if damage > maxPossibleDamage * 1.1 then  -- 10% tolerance
        warn("Damage exceeds weapon capability:", player.Name)
        return
    end
    
    -- Verify target exists and is in range
    local target = EntityManager:GetEntityById(targetId)
    if not target then return end
    
    local playerPos = player.Character and player.Character.PrimaryPart and player.Character.PrimaryPart.Position
    local targetPos = target.Model and target.Model.PrimaryPart and target.Model.PrimaryPart.Position
    
    if playerPos and targetPos then
        local distance = (playerPos - targetPos).Magnitude
        local maxRange = weaponManager:GetMaxRange()
        
        if distance > maxRange * 1.2 then  -- 20% tolerance
            warn("Target out of range:", player.Name)
            return
        end
    end
    
    -- All checks passed - apply damage
    target:TakeDamage(damage, player)
end)
```

## Player Synchronization

### State Replication

```lua
local StateReplicator = {}

-- Replicate player states to all clients
function StateReplicator:BroadcastPlayerStates()
    local states = {}
    
    for player, data in TeamManager.Players do
        states[player.UserId] = {
            state = data.state,
            health = math.round(data.health),
            incapCount = data.incapCount,
        }
    end
    
    PlayerStateRemote:FireAllClients(states)
end

-- Replicate at fixed interval
RunService.Heartbeat:Connect(function()
    if os.clock() - lastStateUpdate > 0.1 then  -- 10 Hz
        StateReplicator:BroadcastPlayerStates()
        lastStateUpdate = os.clock()
    end
end)

-- Client receives and updates UI
PlayerStateRemote.OnClientEvent:Connect(function(states)
    for userId, state in states do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            UI:UpdatePlayerCard(player, state)
        end
    end
end)
```

### Voice/Ping Communication

```lua
local PingSystem = {}

local PING_TYPES = {
    Look = {icon = "👁", duration = 5},
    Danger = {icon = "⚠", duration = 8},
    Item = {icon = "📦", duration = 10},
    Help = {icon = "🆘", duration = 15},
}

function PingSystem:CreatePing(player: Player, position: Vector3, pingType: string)
    local config = PING_TYPES[pingType]
    if not config then return end
    
    -- Create ping data
    local pingData = {
        id = HttpService:GenerateGUID(),
        creator = player,
        position = position,
        type = pingType,
        createdAt = os.clock(),
        expiresAt = os.clock() + config.duration,
    }
    
    -- Broadcast to all players
    PingRemote:FireAllClients(pingData)
    
    -- Auto-cleanup
    task.delay(config.duration, function()
        PingRemote:FireAllClients({id = pingData.id, remove = true})
    end)
end

-- Quick communication wheel
local QUICK_MESSAGES = {
    "Follow me!",
    "Need healing!",
    "Reloading!",
    "Watch out!",
    "Wait here.",
    "Let's go!",
    "I need ammo!",
    "Cover me!",
}

function PingSystem:SendQuickMessage(player: Player, messageIndex: number)
    local message = QUICK_MESSAGES[messageIndex]
    if not message then return end
    
    QuickMessageRemote:FireAllClients(player, message)
end

return PingSystem
```
