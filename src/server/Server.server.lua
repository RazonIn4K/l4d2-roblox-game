--!strict
--[[
    Server Entry Point
    Initializes all server-side services for the L4D2 horror game
]]

local _ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

-- Setup collision groups
local function setupCollisionGroups()
	PhysicsService:RegisterCollisionGroup("Players")
	PhysicsService:RegisterCollisionGroup("Zombies")
	PhysicsService:RegisterCollisionGroup("Projectiles")
	PhysicsService:RegisterCollisionGroup("Debris")

	-- Zombies don't collide with each other (huge performance gain)
	PhysicsService:CollisionGroupSetCollidable("Zombies", "Zombies", false)

	-- Debris doesn't collide with gameplay elements
	PhysicsService:CollisionGroupSetCollidable("Debris", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("Debris", "Zombies", false)
	PhysicsService:CollisionGroupSetCollidable("Debris", "Projectiles", false)

	print("[Server] Collision groups configured")
end

-- Setup remote events
local function setupRemotes()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	-- Create remotes if they don't exist
	local remoteNames = {
		"DealDamage",
		"PlayerAction",
		"EntityUpdate",
		"GameState",
		"RevivePlayer",
		"UseItem",
		"AttemptRescue",
		"FireWeapon",
		"FireResult",
		"AmmoUpdate",
	}

	for _, name in remoteNames do
		if not remotes:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = remotes
		end
	end

	print("[Server] Remote events configured")
end

-- Setup workspace folders and test environment
local function setupWorkspace()
	local Lighting = game:GetService("Lighting")
	
	-- Create Enemies folder if it doesn't exist
	if not workspace:FindFirstChild("Enemies") then
		local enemies = Instance.new("Folder")
		enemies.Name = "Enemies"
		enemies.Parent = workspace
		print("[Server] Created Enemies folder")
	end
	
	-- Skip if already created
	if workspace:FindFirstChild("TestEnvironment") then
		print("[Server] Test environment already exists")
		return
	end
	
	-- ============================================
	-- LIGHTING SETUP
	-- ============================================
	Lighting.Ambient = Color3.fromRGB(20, 20, 30)  -- Dark blue
	Lighting.Brightness = 0.3
	Lighting.OutdoorAmbient = Color3.fromRGB(20, 20, 30)
	Lighting.ClockTime = 0  -- Midnight
	print("[Server] Configured dark lighting")
	
	-- ============================================
	-- ROOM LAYOUT CONSTANTS
	-- ============================================
	local WALL_HEIGHT = 10
	local WALL_THICKNESS = 2
	local FLOOR_THICKNESS = 1
	
	-- Room positions (X axis layout)
	local START_ROOM_CENTER = Vector3.new(0, 0, 0)
	local START_ROOM_SIZE = Vector3.new(40, FLOOR_THICKNESS, 40)
	
	local CORRIDOR_CENTER = Vector3.new(50, 0, 0)  -- 40/2 + 60/2 - overlap
	local CORRIDOR_SIZE = Vector3.new(60, FLOOR_THICKNESS, 20)
	
	local SAFE_ROOM_CENTER = Vector3.new(95, 0, 0)  -- End of corridor + safe room
	local SAFE_ROOM_SIZE = Vector3.new(30, FLOOR_THICKNESS, 30)
	
	-- Materials and colors
	local FLOOR_COLOR = Color3.fromRGB(100, 100, 100)  -- Gray
	local WALL_COLOR = Color3.fromRGB(60, 60, 60)  -- Dark gray
	local SAFE_ROOM_FLOOR_COLOR = Color3.fromRGB(80, 120, 80)  -- Greenish
	
	-- ============================================
	-- CREATE ENVIRONMENT FOLDER
	-- ============================================
	local envFolder = Instance.new("Folder")
	envFolder.Name = "TestEnvironment"
	envFolder.Parent = workspace
	
	-- ============================================
	-- HELPER FUNCTIONS
	-- ============================================
	local function createFloor(name: string, position: Vector3, size: Vector3, color: Color3): Part
		local floor = Instance.new("Part")
		floor.Name = name
		floor.Size = size
		floor.Position = position
		floor.Anchored = true
		floor.Material = Enum.Material.Concrete
		floor.Color = color
		floor.Parent = envFolder
		return floor
	end
	
	local function createWall(name: string, position: Vector3, size: Vector3): Part
		local wall = Instance.new("Part")
		wall.Name = name
		wall.Size = size
		wall.Position = position
		wall.Anchored = true
		wall.Material = Enum.Material.Concrete
		wall.Color = WALL_COLOR
		wall.Parent = envFolder
		return wall
	end
	
	local function createPointLight(parent: Instance, brightness: number, range: number)
		local light = Instance.new("PointLight")
		light.Brightness = brightness
		light.Range = range
		light.Color = Color3.fromRGB(255, 200, 150)  -- Warm light
		light.Parent = parent
	end
	
	local function createSpawnPoint(name: string, position: Vector3, spawnType: string, folder: Folder)
		local spawn = Instance.new("Part")
		spawn.Name = name
		spawn.Size = Vector3.new(2, 0.5, 2)
		spawn.Position = position + Vector3.new(0, 0.5, 0)  -- Slightly above floor
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.Material = Enum.Material.Neon
		
		-- Color based on type
		if spawnType == "Common" then
			spawn.BrickColor = BrickColor.new("Bright red")
		else
			spawn.BrickColor = BrickColor.new("Bright orange")
		end
		
		spawn.Transparency = 0.5
		spawn:SetAttribute("SpawnType", spawnType)
		spawn.Parent = folder
		
		return spawn
	end
	
	-- ============================================
	-- START ROOM (40x40)
	-- ============================================
	print("[Server] Creating Start Room...")
	
	-- Floor
	createFloor("StartRoomFloor", START_ROOM_CENTER, START_ROOM_SIZE, FLOOR_COLOR)
	
	-- Walls (with door opening on +X side)
	-- North wall (full)
	createWall("StartRoom_NorthWall", 
		START_ROOM_CENTER + Vector3.new(0, WALL_HEIGHT/2, -20 - WALL_THICKNESS/2),
		Vector3.new(40, WALL_HEIGHT, WALL_THICKNESS))
	
	-- South wall (full)
	createWall("StartRoom_SouthWall",
		START_ROOM_CENTER + Vector3.new(0, WALL_HEIGHT/2, 20 + WALL_THICKNESS/2),
		Vector3.new(40, WALL_HEIGHT, WALL_THICKNESS))
	
	-- West wall (full)
	createWall("StartRoom_WestWall",
		START_ROOM_CENTER + Vector3.new(-20 - WALL_THICKNESS/2, WALL_HEIGHT/2, 0),
		Vector3.new(WALL_THICKNESS, WALL_HEIGHT, 40))
	
	-- East wall (with door opening - two segments)
	createWall("StartRoom_EastWall_Top",
		START_ROOM_CENTER + Vector3.new(20 + WALL_THICKNESS/2, WALL_HEIGHT/2, -15),
		Vector3.new(WALL_THICKNESS, WALL_HEIGHT, 10))
	createWall("StartRoom_EastWall_Bottom",
		START_ROOM_CENTER + Vector3.new(20 + WALL_THICKNESS/2, WALL_HEIGHT/2, 15),
		Vector3.new(WALL_THICKNESS, WALL_HEIGHT, 10))
	
	-- Light fixture
	local startLight = Instance.new("Part")
	startLight.Name = "StartRoom_Light"
	startLight.Size = Vector3.new(2, 1, 2)
	startLight.Position = START_ROOM_CENTER + Vector3.new(0, WALL_HEIGHT - 1, 0)
	startLight.Anchored = true
	startLight.Material = Enum.Material.Neon
	startLight.Color = Color3.fromRGB(255, 200, 150)
	startLight.Parent = envFolder
	createPointLight(startLight, 2, 40)
	
	-- Player spawn point (center)
	local playerSpawn = Instance.new("SpawnLocation")
	playerSpawn.Name = "PlayerSpawn"
	playerSpawn.Size = Vector3.new(6, 1, 6)
	playerSpawn.Position = START_ROOM_CENTER + Vector3.new(0, 0.5, 0)
	playerSpawn.Anchored = true
	playerSpawn.Material = Enum.Material.SmoothPlastic
	playerSpawn.Color = Color3.fromRGB(50, 100, 200)
	playerSpawn.Transparency = 0.5
	playerSpawn.Parent = envFolder
	
	-- ============================================
	-- CORRIDOR (20x60)
	-- ============================================
	print("[Server] Creating Corridor...")
	
	-- Floor
	createFloor("CorridorFloor", CORRIDOR_CENTER, CORRIDOR_SIZE, FLOOR_COLOR)
	
	-- North wall
	createWall("Corridor_NorthWall",
		CORRIDOR_CENTER + Vector3.new(0, WALL_HEIGHT/2, -10 - WALL_THICKNESS/2),
		Vector3.new(60, WALL_HEIGHT, WALL_THICKNESS))
	
	-- South wall
	createWall("Corridor_SouthWall",
		CORRIDOR_CENTER + Vector3.new(0, WALL_HEIGHT/2, 10 + WALL_THICKNESS/2),
		Vector3.new(60, WALL_HEIGHT, WALL_THICKNESS))
	
	-- Corridor light
	local corridorLight = Instance.new("Part")
	corridorLight.Name = "Corridor_Light"
	corridorLight.Size = Vector3.new(1, 0.5, 1)
	corridorLight.Position = CORRIDOR_CENTER + Vector3.new(0, WALL_HEIGHT - 1, 0)
	corridorLight.Anchored = true
	corridorLight.Material = Enum.Material.Neon
	corridorLight.Color = Color3.fromRGB(255, 200, 150)
	corridorLight.Parent = envFolder
	createPointLight(corridorLight, 1.5, 30)
	
	-- ============================================
	-- SAFE ROOM (30x30)
	-- ============================================
	print("[Server] Creating Safe Room...")
	
	-- Floor (greenish tint)
	createFloor("SafeRoomFloor", SAFE_ROOM_CENTER, SAFE_ROOM_SIZE, SAFE_ROOM_FLOOR_COLOR)
	
	-- Walls (with door opening on -X side)
	-- North wall
	createWall("SafeRoom_NorthWall",
		SAFE_ROOM_CENTER + Vector3.new(0, WALL_HEIGHT/2, -15 - WALL_THICKNESS/2),
		Vector3.new(30, WALL_HEIGHT, WALL_THICKNESS))
	
	-- South wall
	createWall("SafeRoom_SouthWall",
		SAFE_ROOM_CENTER + Vector3.new(0, WALL_HEIGHT/2, 15 + WALL_THICKNESS/2),
		Vector3.new(30, WALL_HEIGHT, WALL_THICKNESS))
	
	-- East wall (full)
	createWall("SafeRoom_EastWall",
		SAFE_ROOM_CENTER + Vector3.new(15 + WALL_THICKNESS/2, WALL_HEIGHT/2, 0),
		Vector3.new(WALL_THICKNESS, WALL_HEIGHT, 30))
	
	-- West wall (with door opening - two segments)
	createWall("SafeRoom_WestWall_Top",
		SAFE_ROOM_CENTER + Vector3.new(-15 - WALL_THICKNESS/2, WALL_HEIGHT/2, -10),
		Vector3.new(WALL_THICKNESS, WALL_HEIGHT, 10))
	createWall("SafeRoom_WestWall_Bottom",
		SAFE_ROOM_CENTER + Vector3.new(-15 - WALL_THICKNESS/2, WALL_HEIGHT/2, 10),
		Vector3.new(WALL_THICKNESS, WALL_HEIGHT, 10))
	
	-- Safe room light (brighter, green tint)
	local safeLight = Instance.new("Part")
	safeLight.Name = "SafeRoom_Light"
	safeLight.Size = Vector3.new(2, 1, 2)
	safeLight.Position = SAFE_ROOM_CENTER + Vector3.new(0, WALL_HEIGHT - 1, 0)
	safeLight.Anchored = true
	safeLight.Material = Enum.Material.Neon
	safeLight.Color = Color3.fromRGB(150, 255, 150)
	safeLight.Parent = envFolder
	
	local safePointLight = Instance.new("PointLight")
	safePointLight.Brightness = 3
	safePointLight.Range = 35
	safePointLight.Color = Color3.fromRGB(150, 255, 150)
	safePointLight.Parent = safeLight
	
	-- Safe Room Trigger Zone
	local safeZone = Instance.new("Part")
	safeZone.Name = "SafeRoomZone"
	safeZone.Size = SAFE_ROOM_SIZE + Vector3.new(0, WALL_HEIGHT, 0)
	safeZone.Position = SAFE_ROOM_CENTER + Vector3.new(0, WALL_HEIGHT/2, 0)
	safeZone.Anchored = true
	safeZone.CanCollide = false
	safeZone.Transparency = 1
	safeZone:SetAttribute("SafeRoomZone", true)
	safeZone.Parent = envFolder
	
	print("[Server] Created Safe Room with trigger zone")
	
	-- ============================================
	-- SPAWN POINTS
	-- ============================================
	local spawnPointsFolder = workspace:FindFirstChild("SpawnPoints")
	if not spawnPointsFolder then
		spawnPointsFolder = Instance.new("Folder")
		spawnPointsFolder.Name = "SpawnPoints"
		spawnPointsFolder.Parent = workspace
	end
	
	-- Clear existing spawn points
	for _, child in spawnPointsFolder:GetChildren() do
		child:Destroy()
	end
	
	-- Start Room corners (4 Common spawns)
	local startRoomSpawns = {
		{pos = START_ROOM_CENTER + Vector3.new(-15, 0, -15), name = "StartRoom_Spawn1"},
		{pos = START_ROOM_CENTER + Vector3.new(15, 0, -15), name = "StartRoom_Spawn2"},
		{pos = START_ROOM_CENTER + Vector3.new(-15, 0, 15), name = "StartRoom_Spawn3"},
		{pos = START_ROOM_CENTER + Vector3.new(15, 0, 15), name = "StartRoom_Spawn4"},
	}
	
	for _, data in startRoomSpawns do
		createSpawnPoint(data.name, data.pos, "Common", spawnPointsFolder)
	end
	
	-- Corridor spawns (2 Common)
	createSpawnPoint("Corridor_Spawn1", CORRIDOR_CENTER + Vector3.new(-15, 0, 0), "Common", spawnPointsFolder)
	createSpawnPoint("Corridor_Spawn2", CORRIDOR_CENTER + Vector3.new(15, 0, 0), "Common", spawnPointsFolder)
	
	-- Special spawn (1 in corridor, further from start)
	createSpawnPoint("Special_Spawn1", CORRIDOR_CENTER + Vector3.new(25, 0, 0), "Special", spawnPointsFolder)
	
	print("[Server] Created 7 spawn points (6 Common, 1 Special)")
	
	-- ============================================
	-- SAFE ROOM TRIGGER DETECTION
	-- ============================================
	local Players = game:GetService("Players")
	
	safeZone.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		
		-- Check if all players are in safe room
		local allInSafeRoom = true
		local playersInSafeRoom = 0
		local totalPlayers = #Players:GetPlayers()
		
		for _, p in Players:GetPlayers() do
			local char = p.Character
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then
					-- Check if inside safe room bounds
					local relPos = hrp.Position - SAFE_ROOM_CENTER
					if math.abs(relPos.X) <= 15 and math.abs(relPos.Z) <= 15 then
						playersInSafeRoom += 1
					else
						allInSafeRoom = false
					end
				end
			end
		end
		
		if allInSafeRoom and totalPlayers > 0 then
			-- Notify DirectorService
			local Services = script.Parent:FindFirstChild("Services")
			if Services then
				local DirectorService = require(Services:WaitForChild("DirectorService") :: any)
				if DirectorService:Get().State ~= "SafeRoom" then
					DirectorService:Get():EnterSafeRoom()
					print("[Server] All players in Safe Room! Entering safe state.")
				end
			end
		end
	end)
	
	print("[Server] Test environment created successfully!")
	print("[Server] Layout: Start Room (0,0,0) → Corridor → Safe Room (95,0,0)")
end

-- Setup chat commands
local function setupChatCommands()
	local Players = game:GetService("Players")
	
	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(message)
			if message == "/test" then
				-- Get services
				local Services = script.Parent:WaitForChild("Services") :: Instance
				local EntityService = require(Services:WaitForChild("EntityService") :: any)
				local DirectorService = require(Services:WaitForChild("DirectorService") :: any)
				
				-- Get zombie model
				local zombieModel = DirectorService:Get():GetOrCreateZombieModel()
				if not zombieModel then
					return
				end
				
				-- Spawn 5 zombies around the player
				local character = player.Character
				if not character then
					return
				end
				
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if not hrp then
					return
				end
				
				local spawnPositions = {}
				for i = 1, 5 do
					local angle = (i / 5) * math.pi * 2
					local offset = Vector3.new(
						math.cos(angle) * 15,
						0,
						math.sin(angle) * 15
					)
					table.insert(spawnPositions, hrp.Position + offset)
				end
				
				-- Spawn zombies
				for i, position in spawnPositions do
					local entity = EntityService:Get():SpawnEntity(zombieModel, position)
					if entity then
						print(string.format("[Test] Spawned zombie #%d for %s at (%.1f, %.1f, %.1f)", 
							i, player.Name, position.X, position.Y, position.Z))
					end
				end
				
				print(string.format("[Test] Spawned 5 zombies for player %s", player.Name))
			elseif message == "/hunter" then
				-- Spawn a Hunter near the player
				local Services = script.Parent:WaitForChild("Services") :: Instance
				local EntityService = require(Services:WaitForChild("EntityService") :: any)
				local DirectorService = require(Services:WaitForChild("DirectorService") :: any)
				
				local character = player.Character
				if not character then
					return
				end
				
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if not hrp then
					return
				end
				
				-- Get Hunter model
				local hunterModel = DirectorService:Get():GetOrCreateSpecialModel("Hunter")
				if not hunterModel then
					warn("[Test] Failed to create Hunter model")
					return
				end
				
				-- Spawn 20 studs in front of player
				local spawnPos = hrp.Position + hrp.CFrame.LookVector * 20
				local hunter = EntityService:Get():SpawnHunter(hunterModel, spawnPos)
				
				if hunter then
					print(string.format("[Test] Spawned Hunter for %s at (%.1f, %.1f, %.1f)", 
						player.Name, spawnPos.X, spawnPos.Y, spawnPos.Z))
				end
			elseif message == "/kill" then
				-- Kill all enemies
				local Services = script.Parent:WaitForChild("Services") :: Instance
				local EntityService = require(Services:WaitForChild("EntityService") :: any)
				
				local count = 0
				for id, entity in EntityService:Get().Entities do
					EntityService:Get():KillEntity(id)
					count += 1
				end
				
				-- Also kill special entities
				if EntityService:Get().SpecialEntities then
					for id, hunter in EntityService:Get().SpecialEntities do
						if hunter.Die then
							hunter:Die()
						end
						count += 1
					end
					EntityService:Get().SpecialEntities = {}
				end
				
				print(string.format("[Test] Killed %d enemies for %s", count, player.Name))
			elseif message == "/heal" then
				-- Heal the player
				local character = player.Character
				if character then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid.Health = humanoid.MaxHealth
						print(string.format("[Test] Healed %s to full health", player.Name))
					end
				end
			end
		end)
	end)
	
	print("[Server] Chat commands initialized")
end

-- Setup rescue remote handler
local function setupRescueHandler()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local attemptRescue = remotes:WaitForChild("AttemptRescue")
	
	attemptRescue.OnServerEvent:Connect(function(rescuer: Player, targetPlayer: Player)
		-- Validate target is a player
		if not targetPlayer or typeof(targetPlayer) ~= "Instance" then
			attemptRescue:FireClient(rescuer, false, "Invalid target")
			return
		end
		
		-- Get PlayerService
		local Services = script.Parent:WaitForChild("Services") :: Instance
		local PlayerService = require(Services:WaitForChild("PlayerService") :: any)
		
		-- Attempt rescue
		local success, message = PlayerService:Get():RescueFromPin(rescuer, targetPlayer)
		
		-- Send result back to client
		attemptRescue:FireClient(rescuer, success, message)
		
		if success then
			print(string.format("[Server] %s rescued %s", rescuer.Name, targetPlayer.Name))
		else
			print(string.format("[Server] Rescue failed: %s", message))
		end
	end)
	
	print("[Server] Rescue handler initialized")
end

-- Initialize services
local function initializeServices()
	local Server = script.Parent :: Instance
	local Services = Server:WaitForChild("Services") :: Instance
	if not Services then
		error("Services folder not found!")
		return
	end

	-- Import services
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local DirectorService = require(Services:WaitForChild("DirectorService") :: any)
	local EntityService = require(Services:WaitForChild("EntityService") :: any)
	local PlayerService = require(Services:WaitForChild("PlayerService") :: any)
	local SpawnPointService = require(Services:WaitForChild("SpawnPointService") :: any)
	local WeaponService = require(Services:WaitForChild("WeaponService") :: any)

	-- Start services in order
	print("[Server] Starting services...")

	GameService:Get():Start()
	PlayerService:Get():Start()
	SpawnPointService:Get():Start()  -- Must start before DirectorService
	EntityService:Get():Start()
	WeaponService:Get():Start()
	DirectorService:Get():Start()

	print("[Server] All services started successfully")
end

-- Main
print("[Server] Initializing L4D2 Horror Game...")

setupCollisionGroups()
setupRemotes()
setupWorkspace()
setupChatCommands()
setupRescueHandler()
initializeServices()

print("[Server] Server ready!")
