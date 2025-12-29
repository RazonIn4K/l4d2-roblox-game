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

-- Setup workspace folders
local function setupWorkspace()
	-- Create Enemies folder if it doesn't exist
	if not workspace:FindFirstChild("Enemies") then
		local enemies = Instance.new("Folder")
		enemies.Name = "Enemies"
		enemies.Parent = workspace
		print("[Server] Created Enemies folder")
	end
	
	-- Create some default spawn points for testing
	if not workspace:FindFirstChild("SpawnPoints") then
		local spawnPointsFolder = Instance.new("Folder")
		spawnPointsFolder.Name = "SpawnPoints"
		spawnPointsFolder.Parent = workspace
		
		local spawnPositions = {
			Vector3.new(50, 0, 0),
			Vector3.new(-50, 0, 0),
			Vector3.new(0, 0, 50),
			Vector3.new(0, 0, -50),
			Vector3.new(35, 0, 35),
			Vector3.new(-35, 0, -35),
			Vector3.new(50, 0, 25),
			Vector3.new(-50, 0, -25),
		}
		
		for i, pos in spawnPositions do
			local spawn = Instance.new("Part")
			spawn.Name = "CommonSpawn"
			spawn.Size = Vector3.new(2, 1, 2)
			spawn.Position = pos
			spawn.Material = Enum.Material.Neon
			spawn.BrickColor = BrickColor.new("Bright red")
			spawn.Anchored = true
			spawn.CanCollide = false
			spawn.Transparency = 0.7
			spawn.Parent = spawnPointsFolder
			
			-- Mark as Common spawn point for SpawnPointService
			spawn:SetAttribute("SpawnType", "Common")
		end
		
		print(string.format("[Server] Created %d spawn points with SpawnType='Common' attribute", #spawnPositions))
	end
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
