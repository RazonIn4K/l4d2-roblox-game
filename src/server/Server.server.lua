--!strict
--[[
    Server Entry Point
    Initializes all server-side services for the L4D2 horror game
]]

local ServerScriptService = game:GetService("ServerScriptService")
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
	if #workspace:GetDescendants() == 0 or not workspace:FindFirstChild("EnemySpawn", true) then
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
			spawn.Name = "EnemySpawn"
			spawn.Size = Vector3.new(2, 1, 2)
			spawn.Position = pos
			spawn.Material = Enum.Material.Neon
			spawn.BrickColor = BrickColor.new("Bright red")
			spawn.Anchored = true
			spawn.CanCollide = false
			spawn.Transparency = 0.7
			spawn.Parent = workspace
		end
		
		print(string.format("[Server] Created %d default spawn points", #spawnPositions))
	end
end

-- Initialize services
local function initializeServices()
	local Services = ServerScriptService.Server.Services

	-- Import services
	local GameService = require(Services.GameService)
	local DirectorService = require(Services.DirectorService)
	local EntityService = require(Services.EntityService)
	local PlayerService = require(Services.PlayerService)

	-- Start services in order
	print("[Server] Starting services...")

	GameService:Get():Start()
	PlayerService:Get():Start()
	EntityService:Get():Start()
	DirectorService:Get():Start()

	print("[Server] All services started successfully")
end

-- Main
print("[Server] Initializing L4D2 Horror Game...")

setupCollisionGroups()
setupRemotes()
setupWorkspace()
initializeServices()

print("[Server] Server ready!")
