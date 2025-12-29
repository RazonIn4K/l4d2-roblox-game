# Procedural Generation

## Table of Contents
1. [Room Generation System](#room-generation-system)
2. [Template-Based Selection](#template-based-selection)
3. [Item Distribution](#item-distribution)
4. [Enemy Spawn Points](#enemy-spawn-points)
5. [Path Variation](#path-variation)
6. [Safe Room Generation](#safe-room-generation)

---

## Room Generation System

DOORS-style approach: Generate rooms on-demand when doors open.

### Core Architecture

```lua
--!strict
local RoomGenerator = {}
RoomGenerator.__index = RoomGenerator

export type RoomType = "Corridor" | "Large" | "Safe" | "Boss" | "Transition"

export type RoomData = {
    template: Model,
    type: RoomType,
    rarity: number,  -- Weight for selection (higher = more common)
    minRoomNumber: number?,  -- Earliest room this can appear
    maxRoomNumber: number?,  -- Latest room this can appear
    requiredItems: {string}?,  -- Items that must spawn here
    forbiddenEntities: {string}?,  -- Entities that can't spawn here
}

function RoomGenerator.new()
    local self = setmetatable({}, RoomGenerator)
    
    self.Templates = {
        Corridor = {},
        Large = {},
        Safe = {},
        Boss = {},
        Transition = {},
    }
    
    self.CurrentRoomNumber = 0
    self.GeneratedRooms = {}
    self.MaxActiveRooms = 5  -- Memory management
    
    return self
end

function RoomGenerator:RegisterTemplate(roomType: RoomType, template: Model, config: {
    rarity: number?,
    minRoomNumber: number?,
    maxRoomNumber: number?,
    requiredItems: {string}?,
    forbiddenEntities: {string}?,
})
    local roomData: RoomData = {
        template = template,
        type = roomType,
        rarity = config.rarity or 1,
        minRoomNumber = config.minRoomNumber,
        maxRoomNumber = config.maxRoomNumber,
        requiredItems = config.requiredItems,
        forbiddenEntities = config.forbiddenEntities,
    }
    
    table.insert(self.Templates[roomType], roomData)
end

function RoomGenerator:LoadTemplates()
    local templateFolder = ServerStorage:WaitForChild("RoomTemplates")
    
    for _, typeFolder in templateFolder:GetChildren() do
        local roomType = typeFolder.Name
        
        for _, template in typeFolder:GetChildren() do
            self:RegisterTemplate(roomType, template, {
                rarity = template:GetAttribute("Rarity") or 1,
                minRoomNumber = template:GetAttribute("MinRoom"),
                maxRoomNumber = template:GetAttribute("MaxRoom"),
            })
        end
    end
end

return RoomGenerator
```

### On-Demand Generation

```lua
function RoomGenerator:GenerateNextRoom(doorCFrame: CFrame): Model?
    self.CurrentRoomNumber += 1
    
    -- Determine room type based on progression
    local roomType = self:DetermineRoomType()
    
    -- Select template
    local template = self:SelectTemplate(roomType)
    if not template then
        warn("No valid template for room type:", roomType)
        return nil
    end
    
    -- Clone and position
    local room = template.template:Clone()
    
    -- Find entry point in room template
    local entryPoint = room:FindFirstChild("EntryPoint")
    if entryPoint then
        -- Align room's entry with door's exit
        local offset = room.PrimaryPart.CFrame:ToObjectSpace(entryPoint.CFrame)
        room:PivotTo(doorCFrame * offset:Inverse())
    else
        room:PivotTo(doorCFrame)
    end
    
    room.Parent = workspace.Rooms
    
    -- Populate room
    self:PopulateRoom(room, template)
    
    -- Track for cleanup
    table.insert(self.GeneratedRooms, {
        model = room,
        number = self.CurrentRoomNumber,
        timestamp = os.clock(),
    })
    
    -- Cleanup distant rooms
    self:CleanupDistantRooms()
    
    return room
end

function RoomGenerator:DetermineRoomType(): RoomType
    local roomNum = self.CurrentRoomNumber
    
    -- Safe rooms every 10 rooms
    if roomNum % 10 == 0 then
        return "Safe"
    end
    
    -- Boss rooms at specific intervals
    if roomNum == 25 or roomNum == 50 or roomNum == 75 then
        return "Boss"
    end
    
    -- Transition rooms occasionally
    if math.random() < 0.15 then
        return "Transition"
    end
    
    -- Mix of corridor and large
    if math.random() < 0.7 then
        return "Corridor"
    else
        return "Large"
    end
end

function RoomGenerator:CleanupDistantRooms()
    while #self.GeneratedRooms > self.MaxActiveRooms do
        local oldest = table.remove(self.GeneratedRooms, 1)
        
        -- Check no players inside
        local playersInside = self:GetPlayersInRoom(oldest.model)
        if #playersInside == 0 then
            oldest.model:Destroy()
        else
            -- Re-add to queue, try again later
            table.insert(self.GeneratedRooms, 2, oldest)
            break
        end
    end
end
```

## Template-Based Selection

### Weighted Random Selection

```lua
function RoomGenerator:SelectTemplate(roomType: RoomType): RoomData?
    local validTemplates = {}
    local totalWeight = 0
    
    for _, roomData in self.Templates[roomType] do
        -- Check room number constraints
        if roomData.minRoomNumber and self.CurrentRoomNumber < roomData.minRoomNumber then
            continue
        end
        if roomData.maxRoomNumber and self.CurrentRoomNumber > roomData.maxRoomNumber then
            continue
        end
        
        table.insert(validTemplates, roomData)
        totalWeight += roomData.rarity
    end
    
    if #validTemplates == 0 then
        return nil
    end
    
    -- Weighted random selection
    local roll = math.random() * totalWeight
    local cumulative = 0
    
    for _, roomData in validTemplates do
        cumulative += roomData.rarity
        if roll <= cumulative then
            return roomData
        end
    end
    
    return validTemplates[#validTemplates]
end
```

### Rarity Tiers

```lua
local RARITY_TIERS = {
    Common = 10,      -- Very frequent
    Uncommon = 5,     -- Regular
    Rare = 2,         -- Occasional
    Epic = 0.5,       -- Rare
    Legendary = 0.1,  -- Very rare (secret rooms)
}

-- Example template setup
RoomGenerator:RegisterTemplate("Corridor", template, {
    rarity = RARITY_TIERS.Common,
})

RoomGenerator:RegisterTemplate("Large", bossArena, {
    rarity = RARITY_TIERS.Epic,
    minRoomNumber = 20,  -- Only after room 20
})
```

## Item Distribution

### Director-Controlled Item Spawning

```lua
local ItemSpawner = {}
ItemSpawner.__index = ItemSpawner

export type ItemType = "Medkit" | "Pills" | "Adrenaline" | "Ammo" | "PipeBomb" | "Molotov" | "Bile"

local ITEM_CONFIG = {
    Medkit = {baseChance = 0.3, priority = 1},
    Pills = {baseChance = 0.5, priority = 2},
    Adrenaline = {baseChance = 0.2, priority = 3},
    Ammo = {baseChance = 0.6, priority = 4},
    PipeBomb = {baseChance = 0.15, priority = 5},
    Molotov = {baseChance = 0.15, priority = 5},
    Bile = {baseChance = 0.1, priority = 5},
}

function ItemSpawner.new(director: AIDirector)
    local self = setmetatable({}, ItemSpawner)
    self.Director = director
    return self
end

function ItemSpawner:PopulateRoom(room: Model)
    local spawnPoints = self:GetSpawnPoints(room)
    local teamStats = self:GetTeamStats()
    
    for _, spawnPoint in spawnPoints do
        local itemType = spawnPoint:GetAttribute("ItemType")
        local item = self:DetermineItem(itemType, teamStats)
        
        if item then
            self:SpawnItem(item, spawnPoint.CFrame)
        end
    end
end

function ItemSpawner:DetermineItem(preferredType: ItemType?, teamStats: TeamStats): ItemType?
    -- Director influences: hurt team gets more health items
    local healthMultiplier = 1 + (1 - teamStats.avgHealthPercent) * 2
    local ammoMultiplier = 1 + (1 - teamStats.avgAmmoPercent)
    
    -- Calculate modified chances
    local chances = {}
    local totalChance = 0
    
    for itemType, config in ITEM_CONFIG do
        local chance = config.baseChance
        
        -- Apply multipliers
        if itemType == "Medkit" or itemType == "Pills" or itemType == "Adrenaline" then
            chance *= healthMultiplier
        elseif itemType == "Ammo" then
            chance *= ammoMultiplier
        end
        
        -- Preferred type bonus
        if preferredType and itemType == preferredType then
            chance *= 1.5
        end
        
        chances[itemType] = chance
        totalChance += chance
    end
    
    -- Check if any item spawns
    if math.random() > totalChance / 5 then  -- Base spawn rate
        return nil
    end
    
    -- Weighted selection
    local roll = math.random() * totalChance
    local cumulative = 0
    
    for itemType, chance in chances do
        cumulative += chance
        if roll <= cumulative then
            return itemType
        end
    end
    
    return nil
end

-- Director conversion: Pills → Medkit when team is hurt
function ItemSpawner:DirectorConversion(item: ItemType, teamStats: TeamStats): ItemType
    if item == "Pills" and teamStats.avgHealthPercent < 0.4 then
        if math.random() < 0.3 then
            return "Medkit"
        end
    end
    
    return item
end
```

### Spawn Point Configuration

```lua
-- In room template, add Parts named "ItemSpawn" with attributes:
-- ItemType: string (preferred item type)
-- Guaranteed: boolean (always spawns something)
-- Group: string (only one item per group)

function ItemSpawner:GetSpawnPoints(room: Model): {BasePart}
    local points = {}
    
    for _, child in room:GetDescendants() do
        if child.Name == "ItemSpawn" and child:IsA("BasePart") then
            table.insert(points, child)
        end
    end
    
    return points
end

function ItemSpawner:ProcessSpawnGroups(spawnPoints: {BasePart}): {BasePart}
    -- Group spawn points by Group attribute
    local groups = {}
    local ungrouped = {}
    
    for _, point in spawnPoints do
        local group = point:GetAttribute("Group")
        if group then
            groups[group] = groups[group] or {}
            table.insert(groups[group], point)
        else
            table.insert(ungrouped, point)
        end
    end
    
    -- Select one from each group
    local selected = {}
    
    for _, groupPoints in groups do
        local chosen = groupPoints[math.random(#groupPoints)]
        table.insert(selected, chosen)
    end
    
    -- Add all ungrouped
    for _, point in ungrouped do
        table.insert(selected, point)
    end
    
    return selected
end
```

## Enemy Spawn Points

### Spawn Point Types

```lua
export type SpawnPointType = "Common" | "Special" | "Ambient" | "Crescendo" | "Tank"

local EnemySpawner = {}
EnemySpawner.__index = EnemySpawner

function EnemySpawner:GetSpawnPoints(room: Model, pointType: SpawnPointType): {BasePart}
    local points = {}
    
    for _, child in room:GetDescendants() do
        if child.Name == "EnemySpawn" and child:IsA("BasePart") then
            if child:GetAttribute("Type") == pointType then
                -- Validate point is not visible to players
                if not self:IsVisibleToAnyPlayer(child.Position) then
                    table.insert(points, child)
                end
            end
        end
    end
    
    return points
end

function EnemySpawner:IsVisibleToAnyPlayer(position: Vector3): boolean
    for _, player in Players:GetPlayers() do
        local char = player.Character
        if not char then continue end
        
        local head = char:FindFirstChild("Head")
        if not head then continue end
        
        -- Check line of sight
        local direction = (position - head.Position)
        local distance = direction.Magnitude
        
        if distance > 100 then continue end  -- Too far to see anyway
        
        local result = workspace:Raycast(head.Position, direction)
        if not result then
            return true  -- Can see
        end
    end
    
    return false
end

function EnemySpawner:SpawnAtBestPoint(pointType: SpawnPointType, entityType: string): Model?
    -- Get all valid spawn points across active rooms
    local allPoints = {}
    
    for _, room in workspace.Rooms:GetChildren() do
        local points = self:GetSpawnPoints(room, pointType)
        for _, point in points do
            table.insert(allPoints, point)
        end
    end
    
    if #allPoints == 0 then
        warn("No valid spawn points for:", pointType)
        return nil
    end
    
    -- Prefer points behind players (75%)
    local behindPoints = {}
    local otherPoints = {}
    
    local avgPlayerFacing = self:GetAveragePlayerFacing()
    
    for _, point in allPoints do
        local avgPlayerPos = self:GetAveragePlayerPosition()
        local toPoint = (point.Position - avgPlayerPos).Unit
        local dot = avgPlayerFacing:Dot(toPoint)
        
        if dot < -0.3 then  -- Behind players
            table.insert(behindPoints, point)
        else
            table.insert(otherPoints, point)
        end
    end
    
    local selectedPoint
    if #behindPoints > 0 and math.random() < 0.75 then
        selectedPoint = behindPoints[math.random(#behindPoints)]
    else
        selectedPoint = allPoints[math.random(#allPoints)]
    end
    
    -- Spawn entity
    return self:SpawnEntity(entityType, selectedPoint.CFrame)
end
```

## Path Variation

### Branching Paths

```lua
local PathManager = {}
PathManager.__index = PathManager

export type PathBranch = {
    rooms: {number},  -- Room numbers in this branch
    difficulty: number,  -- 1-5
    reward: string?,  -- Special item at end
}

function PathManager:CreateBranch(startRoom: number, length: number, difficulty: number): PathBranch
    return {
        rooms = {},
        difficulty = difficulty,
        reward = difficulty >= 4 and "Medkit" or nil,  -- Hard paths have better rewards
    }
end

-- Room templates can have multiple exits
function RoomGenerator:GetExits(room: Model): {BasePart}
    local exits = {}
    
    for _, child in room:GetDescendants() do
        if child.Name == "Exit" and child:IsA("BasePart") then
            table.insert(exits, {
                part = child,
                type = child:GetAttribute("ExitType") or "Main",  -- Main, Branch, Secret
                targetRoomType = child:GetAttribute("TargetType"),
            })
        end
    end
    
    return exits
end

-- Generate side path from main route
function PathManager:GenerateSidePath(mainRoom: Model, length: number)
    local sideEntrance = mainRoom:FindFirstChild("SideExit")
    if not sideEntrance then return end
    
    local sideRooms = {}
    local currentCFrame = sideEntrance.CFrame
    
    for i = 1, length do
        local room = RoomGenerator:GenerateRoom("Corridor", currentCFrame)
        table.insert(sideRooms, room)
        
        local mainExit = room:FindFirstChild("MainExit")
        if mainExit then
            currentCFrame = mainExit.CFrame
        end
    end
    
    -- Dead end room with reward
    local rewardRoom = RoomGenerator:GenerateRoom("Reward", currentCFrame)
    table.insert(sideRooms, rewardRoom)
    
    return sideRooms
end
```

### Dynamic Events Per Room

```lua
local RoomEvents = {
    -- Events that can occur in any room
    Common = {
        {name = "LightFlicker", chance = 0.3},
        {name = "AmbientSound", chance = 0.5},
        {name = "WandererSpawn", chance = 0.2},
    },
    
    -- Events specific to room types
    Corridor = {
        {name = "CeilingDrop", chance = 0.1},
        {name = "WallBreak", chance = 0.15},
    },
    
    Large = {
        {name = "Ambush", chance = 0.25},
        {name = "AlarmTrigger", chance = 0.1},
    },
}

function RoomGenerator:PopulateRoom(room: Model, roomData: RoomData)
    -- Spawn items
    ItemSpawner:PopulateRoom(room)
    
    -- Setup events
    self:SetupRoomEvents(room, roomData.type)
    
    -- Setup interactables
    self:SetupInteractables(room)
end

function RoomGenerator:SetupRoomEvents(room: Model, roomType: RoomType)
    -- Common events
    for _, event in RoomEvents.Common do
        if math.random() < event.chance then
            self:AttachEvent(room, event.name)
        end
    end
    
    -- Type-specific events
    local typeEvents = RoomEvents[roomType]
    if typeEvents then
        for _, event in typeEvents do
            if math.random() < event.chance then
                self:AttachEvent(room, event.name)
            end
        end
    end
end
```

## Safe Room Generation

### Safe Room Configuration

```lua
local SafeRoomGenerator = {}
SafeRoomGenerator.__index = SafeRoomGenerator

export type SafeRoomConfig = {
    hasAmmoBox: boolean,
    hasMedCabinet: boolean,
    hasWeaponTable: boolean,
    weaponTier: number,  -- 1 = pistols, 2 = SMG/shotgun, 3 = rifles
    checkpointId: string,
}

function SafeRoomGenerator:Generate(roomNumber: number): Model
    local template = self:SelectSafeRoomTemplate()
    local room = template:Clone()
    
    -- Configure based on progression
    local config = self:GetConfigForProgression(roomNumber)
    
    -- Setup ammo box (infinite ammo)
    local ammoBox = room:FindFirstChild("AmmoBox")
    if ammoBox and config.hasAmmoBox then
        self:SetupAmmoBox(ammoBox)
    elseif ammoBox then
        ammoBox:Destroy()
    end
    
    -- Setup medical cabinet
    local medCabinet = room:FindFirstChild("MedCabinet")
    if medCabinet and config.hasMedCabinet then
        self:SetupMedCabinet(medCabinet)
    elseif medCabinet then
        medCabinet:Destroy()
    end
    
    -- Setup weapon table
    local weaponTable = room:FindFirstChild("WeaponTable")
    if weaponTable and config.hasWeaponTable then
        self:SetupWeaponTable(weaponTable, config.weaponTier)
    elseif weaponTable then
        weaponTable:Destroy()
    end
    
    -- Setup checkpoint trigger
    self:SetupCheckpoint(room, config.checkpointId)
    
    -- Setup safe room doors (require all players before opening)
    self:SetupSafeRoomDoors(room)
    
    return room
end

function SafeRoomGenerator:GetConfigForProgression(roomNumber: number): SafeRoomConfig
    local tier = math.floor(roomNumber / 25) + 1
    
    return {
        hasAmmoBox = true,
        hasMedCabinet = true,
        hasWeaponTable = roomNumber >= 10,
        weaponTier = math.min(tier, 3),
        checkpointId = "checkpoint_" .. roomNumber,
    }
end

function SafeRoomGenerator:SetupSafeRoomDoors(room: Model)
    local exitDoor = room:FindFirstChild("ExitDoor")
    if not exitDoor then return end
    
    exitDoor:SetAttribute("RequiresAllPlayers", true)
    exitDoor:SetAttribute("IsLocked", true)
    
    -- Setup trigger zone
    local triggerZone = room:FindFirstChild("AllPlayerZone")
    if triggerZone then
        local playersInZone = {}
        
        triggerZone.Touched:Connect(function(hit)
            local player = Players:GetPlayerFromCharacter(hit.Parent)
            if player then
                playersInZone[player] = true
                self:CheckAllPlayersReady(playersInZone, exitDoor)
            end
        end)
        
        triggerZone.TouchEnded:Connect(function(hit)
            local player = Players:GetPlayerFromCharacter(hit.Parent)
            if player then
                playersInZone[player] = nil
            end
        end)
    end
end

function SafeRoomGenerator:CheckAllPlayersReady(playersInZone: {[Player]: boolean}, door: Model)
    local allPlayers = Players:GetPlayers()
    local allReady = true
    
    for _, player in allPlayers do
        if not playersInZone[player] then
            allReady = false
            break
        end
    end
    
    if allReady then
        door:SetAttribute("IsLocked", false)
        -- Play unlock sound, show UI prompt
    end
end
```
