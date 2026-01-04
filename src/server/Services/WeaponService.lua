--!strict
--[[
    WeaponService
    Handles weapon firing, hit detection, and ammo management
    Server-authoritative - all damage is validated server-side
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Weapon definitions
local WEAPONS = {
	Pistol = {
		damage = 20,
		fireRate = 0.2, -- seconds between shots
		range = 100,
		magazineSize = 15,
		reserveAmmo = math.huge, -- infinite for pistol
		headshotMultiplier = 2,
	},
	Shotgun = {
		damage = 8, -- per pellet
		pellets = 8,
		fireRate = 0.8,
		range = 30,
		magazineSize = 8,
		reserveAmmo = 128,
		spread = 5, -- degrees
		headshotMultiplier = 1.5,
	},
	SMG = {
		damage = 15,
		fireRate = 0.08,
		range = 80,
		magazineSize = 50,
		reserveAmmo = 500,
		headshotMultiplier = 1.5,
	},
}

-- Types
export type WeaponData = {
	damage: number,
	fireRate: number,
	range: number,
	magazineSize: number,
	reserveAmmo: number,
	headshotMultiplier: number?,
	pellets: number?,
	spread: number?,
}

export type PlayerWeaponState = {
	currentWeapon: string,
	magazine: number,
	reserve: number,
	lastFireTime: number,
}

-- Module
local WeaponService = {}
WeaponService.__index = WeaponService

local _instance = nil

local function isValidVector3(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	if value.X ~= value.X or value.Y ~= value.Y or value.Z ~= value.Z then
		return false
	end
	return true
end

function WeaponService.new()
	if _instance then
		return _instance
	end

	local self = setmetatable({}, WeaponService)

	-- Player weapon states
	self.PlayerWeapons = {} :: { [Player]: PlayerWeaponState }

	-- Connections
	self._connections = {} :: { RBXScriptConnection }

	_instance = self
	return self
end

function WeaponService:Get()
	return WeaponService.new()
end

function WeaponService:Start()
	-- Setup remote event listener
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local fireWeaponRemote = remotes:WaitForChild("FireWeapon")

	table.insert(
		self._connections,
		fireWeaponRemote.OnServerEvent:Connect(function(player, targetPosition)
			self:OnFireWeapon(player, targetPosition)
		end)
	)

	-- Initialize weapons for existing players
	for _, player in Players:GetPlayers() do
		self:InitializePlayerWeapon(player)
	end

	-- Initialize weapons for new players
	table.insert(
		self._connections,
		Players.PlayerAdded:Connect(function(player)
			self:InitializePlayerWeapon(player)
		end)
	)

	-- Cleanup on player leave
	table.insert(
		self._connections,
		Players.PlayerRemoving:Connect(function(player)
			self.PlayerWeapons[player] = nil
		end)
	)

	print("[WeaponService] Started - Weapon system active")
end

function WeaponService:InitializePlayerWeapon(player: Player)
	local weaponData = WEAPONS.Pistol

	self.PlayerWeapons[player] = {
		currentWeapon = "Pistol",
		magazine = weaponData.magazineSize,
		reserve = weaponData.reserveAmmo,
		lastFireTime = 0,
	}

	-- Send initial ammo state to client
	self:SendAmmoUpdate(player)

	print(string.format("[WeaponService] Initialized %s with Pistol", player.Name))
end

function WeaponService:OnFireWeapon(player: Player, targetPosition: Vector3)
	if not isValidVector3(targetPosition) then
		warn("[WeaponService] Invalid target position from:", player.Name)
		return
	end

	-- Get player weapon state
	local weaponState = self.PlayerWeapons[player]
	if not weaponState then
		warn("[WeaponService] No weapon state for player:", player.Name)
		return
	end

	-- Get weapon data
	local weaponData = WEAPONS[weaponState.currentWeapon]
	if not weaponData then
		warn("[WeaponService] Unknown weapon:", weaponState.currentWeapon)
		return
	end

	-- Validate player state
	local isValid, reason = self:ValidatePlayerCanFire(player)
	if not isValid then
		print(string.format("[WeaponService] %s cannot fire: %s", player.Name, reason))
		return
	end

	-- Rate limit check
	local now = os.clock()
	if now - weaponState.lastFireTime < weaponData.fireRate then
		return -- Silent reject - too fast
	end

	-- Check ammo (server-authoritative validation)
	if weaponState.magazine <= 0 then
		-- Send empty click feedback
		print(string.format("[WeaponService] %s attempted to fire with no ammo (magazine: %d, reserve: %d)", 
			player.Name, weaponState.magazine, weaponState.reserve))
		self:SendFireResult(player, false, "NoAmmo")
		-- Send current ammo state to reconcile client prediction
		self:SendAmmoUpdate(player)
		return
	end

	-- Update fire time and ammo
	weaponState.lastFireTime = now
	local previousMagazine = weaponState.magazine
	weaponState.magazine -= 1
	
	-- Log ammo consumption for debugging
	print(string.format("[WeaponService] %s fired %s (ammo: %d/%d -> %d/%d)", 
		player.Name, weaponState.currentWeapon, previousMagazine, weaponState.reserve, 
		weaponState.magazine, weaponState.reserve))

	-- Perform server-side raycast
	local hitResult = self:PerformRaycast(player, targetPosition, weaponData)

	-- Process hit
	if hitResult.hit then
		self:ProcessHit(player, hitResult, weaponData)
	end

	-- Send result to client
	self:SendFireResult(player, true, hitResult.hit and "Hit" or "Miss", hitResult)

	-- Send ammo update
	self:SendAmmoUpdate(player)
end

function WeaponService:ValidatePlayerCanFire(player: Player): (boolean, string)
	local character = player.Character
	if not character then
		return false, "No character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "Dead"
	end

	-- Check if pinned
	local isPinned = character:GetAttribute("IsPinned")
	if isPinned then
		return false, "Pinned"
	end

	-- Check if incapped (via GameService)
	local Services = script.Parent :: Instance
	local GameService = require(Services:WaitForChild("GameService") :: any)
	local gameService = GameService:Get()

	local playerData = gameService.PlayerData[player]
	if playerData and playerData.state == "Incapacitated" then
		return false, "Incapacitated"
	end

	return true, "OK"
end

function WeaponService:PerformRaycast(
	player: Player,
	targetPosition: Vector3,
	weaponData: WeaponData
): { [string]: any }
	local character = player.Character
	if not character then
		return { hit = false }
	end

	-- Get origin from player's head (approximating camera position)
	local head = character:FindFirstChild("Head")
	if not head then
		return { hit = false }
	end

	local origin = head.Position
	local rawDirection = targetPosition - origin
	if rawDirection.Magnitude < 0.001 then
		return { hit = false }
	end
	local direction = rawDirection.Unit * weaponData.range

	-- Setup raycast params
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	-- Perform raycast
	local result = workspace:Raycast(origin, direction, rayParams)

	if result then
		local hitPart = result.Instance
		local hitPosition = result.Position
		local hitNormal = result.Normal

		-- Check if hit an entity
		local entityModel = hitPart:FindFirstAncestorOfClass("Model")
		local entityId = nil
		local isHeadshot = false

		if entityModel then
			entityId = entityModel:GetAttribute("EntityId")

			-- Check for headshot
			if hitPart.Name == "Head" then
				isHeadshot = true
			end
		end

		return {
			hit = true,
			hitPart = hitPart,
			hitPosition = hitPosition,
			hitNormal = hitNormal,
			entityId = entityId,
			isHeadshot = isHeadshot,
		}
	end

	return { hit = false }
end

function WeaponService:ProcessHit(player: Player, hitResult: { [string]: any }, weaponData: WeaponData)
	if not hitResult.entityId then
		return -- Hit world geometry, not an entity
	end

	-- Calculate damage
	local damage = weaponData.damage
	if hitResult.isHeadshot and weaponData.headshotMultiplier then
		damage = damage * weaponData.headshotMultiplier
		print(string.format("[WeaponService] HEADSHOT! %s dealt %.0f damage", player.Name, damage))
	else
		print(string.format("[WeaponService] %s dealt %.0f damage", player.Name, damage))
	end

	-- Get EntityService and apply damage
	local Services = script.Parent :: Instance
	local EntityService = require(Services:WaitForChild("EntityService") :: any)

	EntityService:Get():DamageEntity(hitResult.entityId, damage, player)
end

function WeaponService:SendFireResult(player: Player, success: boolean, result: string, hitData: { [string]: any }?)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local fireResultRemote = remotes:FindFirstChild("FireResult")

	if fireResultRemote then
		fireResultRemote:FireClient(player, success, result, hitData)
	end
end

function WeaponService:SendAmmoUpdate(player: Player)
	local weaponState = self.PlayerWeapons[player]
	if not weaponState then
		return
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ammoUpdateRemote = remotes:FindFirstChild("AmmoUpdate")

	if ammoUpdateRemote then
		ammoUpdateRemote:FireClient(player, {
			weapon = weaponState.currentWeapon,
			magazine = weaponState.magazine,
			reserve = weaponState.reserve,
		})
	end
end

function WeaponService:GetPlayerWeaponState(player: Player): PlayerWeaponState?
	return self.PlayerWeapons[player]
end

function WeaponService:Reload(player: Player)
	local weaponState = self.PlayerWeapons[player]
	if not weaponState then
		return
	end

	local weaponData = WEAPONS[weaponState.currentWeapon]
	if not weaponData then
		return
	end

	local needed = weaponData.magazineSize - weaponState.magazine
	local available = math.min(needed, weaponState.reserve)

	if available > 0 then
		weaponState.magazine += available
		if weaponState.reserve ~= math.huge then
			weaponState.reserve -= available
		end

		self:SendAmmoUpdate(player)
		print(string.format("[WeaponService] %s reloaded %s", player.Name, weaponState.currentWeapon))
	end
end

function WeaponService:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	table.clear(self.PlayerWeapons)
end

return WeaponService
