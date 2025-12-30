--!strict
--[[
    DamageFeedbackController
    Handles visual feedback for damage: screen vignette, hit markers, camera shake
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Types
export type DamageFeedbackController = {
	ScreenGui: ScreenGui?,
	DamageVignette: ImageLabel?,
	HitMarker: Frame?,
	DirectionalIndicators: { [string]: Frame },
	LastHealth: number,
	ShakeOffset: Vector3,
	ShakeIntensity: number,
	_connections: { RBXScriptConnection },
	new: () -> DamageFeedbackController,
	Get: (self: DamageFeedbackController) -> DamageFeedbackController,
	Start: (self: DamageFeedbackController) -> (),
	CreateUI: (self: DamageFeedbackController) -> (),
	CreateDamageVignette: (self: DamageFeedbackController) -> (),
	CreateHitMarker: (self: DamageFeedbackController) -> (),
	CreateDirectionalIndicators: (self: DamageFeedbackController) -> (),
	ShowDamageVignette: (self: DamageFeedbackController, intensity: number) -> (),
	ShowHitMarker: (self: DamageFeedbackController, isHeadshot: boolean) -> (),
	ShowDirectionalDamage: (self: DamageFeedbackController, direction: Vector3) -> (),
	ApplyCameraShake: (self: DamageFeedbackController, intensity: number) -> (),
	UpdateCameraShake: (self: DamageFeedbackController, dt: number) -> (),
	OnDamageTaken: (self: DamageFeedbackController, damage: number, sourcePosition: Vector3?) -> (),
	OnHitConfirmed: (self: DamageFeedbackController, isHeadshot: boolean) -> (),
	ConnectEvents: (self: DamageFeedbackController) -> (),
	SetupCharacterDamageDetection: (self: DamageFeedbackController, character: Model) -> (),
	Destroy: (self: DamageFeedbackController) -> (),
}

-- Constants
local CONFIG = {
	vignetteFadeInTime = 0.05,
	vignetteFadeOutTime = 0.3,
	hitMarkerDuration = 0.15,
	hitMarkerSize = 40,
	directionalIndicatorDuration = 1.5,
	cameraShakeDecay = 8,
	heavyDamageThreshold = 30, -- Damage amount that triggers heavy effects
}

-- Module
local DamageFeedbackController = {} :: DamageFeedbackController
DamageFeedbackController.__index = DamageFeedbackController

local _instance: DamageFeedbackController? = nil

function DamageFeedbackController.new(): DamageFeedbackController
	if _instance then
		return _instance
	end

	local self = setmetatable({}, DamageFeedbackController) :: DamageFeedbackController

	-- UI References
	self.ScreenGui = nil
	self.DamageVignette = nil
	self.HitMarker = nil
	self.DirectionalIndicators = {}

	-- State
	self.LastHealth = 100
	self.ShakeOffset = Vector3.zero
	self.ShakeIntensity = 0

	-- Connections
	self._connections = {}

	_instance = self
	return self
end

function DamageFeedbackController:Get(): DamageFeedbackController
	return DamageFeedbackController.new()
end

function DamageFeedbackController:Start()
	-- Create UI elements
	self:CreateUI()

	-- Connect to events
	self:ConnectEvents()

	-- Camera shake update loop
	table.insert(
		self._connections,
		RunService.RenderStepped:Connect(function(dt)
			self:UpdateCameraShake(dt)
		end)
	)

	print("[DamageFeedbackController] Started")
end

-- ============================================
-- UI CREATION
-- ============================================

function DamageFeedbackController:CreateUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DamageFeedbackHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.Parent = player:WaitForChild("PlayerGui")
	self.ScreenGui = screenGui

	self:CreateDamageVignette()
	self:CreateHitMarker()
	self:CreateDirectionalIndicators()
end

function DamageFeedbackController:CreateDamageVignette()
	-- Red damage vignette around screen edges
	local vignette = Instance.new("ImageLabel")
	vignette.Name = "DamageVignette"
	vignette.Size = UDim2.new(1, 0, 1, 0)
	vignette.Position = UDim2.new(0, 0, 0, 0)
	vignette.BackgroundTransparency = 1
	vignette.ImageTransparency = 1
	vignette.Image = "rbxassetid://1260091161" -- Radial gradient vignette
	vignette.ImageColor3 = Color3.fromRGB(200, 0, 0)
	vignette.ScaleType = Enum.ScaleType.Stretch
	vignette.ZIndex = 5
	vignette.Parent = self.ScreenGui
	self.DamageVignette = vignette
end

function DamageFeedbackController:CreateHitMarker()
	-- Hit marker (X shape in center)
	local hitMarker = Instance.new("Frame")
	hitMarker.Name = "HitMarker"
	hitMarker.Size = UDim2.new(0, CONFIG.hitMarkerSize, 0, CONFIG.hitMarkerSize)
	hitMarker.Position = UDim2.new(0.5, -CONFIG.hitMarkerSize / 2, 0.5, -CONFIG.hitMarkerSize / 2)
	hitMarker.BackgroundTransparency = 1
	hitMarker.ZIndex = 10
	hitMarker.Visible = false
	hitMarker.Parent = self.ScreenGui
	self.HitMarker = hitMarker

	-- Create X shape using 4 lines
	local lineThickness = 3
	local lineLength = CONFIG.hitMarkerSize * 0.4
	local gapSize = 4

	-- Helper to create a line
	local function createLine(rotation: number, offset: Vector2)
		local line = Instance.new("Frame")
		line.Name = "Line"
		line.Size = UDim2.new(0, lineLength, 0, lineThickness)
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
		line.Rotation = rotation
		line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		line.BorderSizePixel = 0
		line.Parent = hitMarker

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 1)
		corner.Parent = line

		return line
	end

	-- Top-left to center gap
	createLine(45, Vector2.new(-gapSize - lineLength / 4, -gapSize - lineLength / 4))
	-- Top-right to center gap
	createLine(-45, Vector2.new(gapSize + lineLength / 4, -gapSize - lineLength / 4))
	-- Bottom-left to center gap
	createLine(-45, Vector2.new(-gapSize - lineLength / 4, gapSize + lineLength / 4))
	-- Bottom-right to center gap
	createLine(45, Vector2.new(gapSize + lineLength / 4, gapSize + lineLength / 4))
end

function DamageFeedbackController:CreateDirectionalIndicators()
	-- Directional damage indicators (arrows showing damage source)
	local directions = {
		{ name = "Top", rotation = 0, position = UDim2.new(0.5, 0, 0, 60) },
		{ name = "Bottom", rotation = 180, position = UDim2.new(0.5, 0, 1, -60) },
		{ name = "Left", rotation = -90, position = UDim2.new(0, 60, 0.5, 0) },
		{ name = "Right", rotation = 90, position = UDim2.new(1, -60, 0.5, 0) },
	}

	for _, dir in directions do
		local indicator = Instance.new("Frame")
		indicator.Name = dir.name .. "Indicator"
		indicator.Size = UDim2.new(0, 30, 0, 50)
		indicator.AnchorPoint = Vector2.new(0.5, 0.5)
		indicator.Position = dir.position
		indicator.Rotation = dir.rotation
		indicator.BackgroundTransparency = 1
		indicator.Visible = false
		indicator.ZIndex = 6
		indicator.Parent = self.ScreenGui

		-- Arrow shape using a triangle-like frame
		local arrow = Instance.new("ImageLabel")
		arrow.Name = "Arrow"
		arrow.Size = UDim2.new(1, 0, 1, 0)
		arrow.BackgroundTransparency = 1
		arrow.ImageTransparency = 0.3
		arrow.Image = "rbxassetid://6031094678" -- Triangle/arrow image
		arrow.ImageColor3 = Color3.fromRGB(255, 50, 50)
		arrow.Parent = indicator

		self.DirectionalIndicators[dir.name] = indicator
	end
end

-- ============================================
-- VISUAL EFFECTS
-- ============================================

function DamageFeedbackController:ShowDamageVignette(intensity: number)
	if not self.DamageVignette then
		return
	end

	-- Clamp intensity (0-1)
	local clampedIntensity = math.clamp(intensity, 0.3, 0.8)

	-- Flash in quickly
	self.DamageVignette.ImageTransparency = 1 - clampedIntensity

	-- Fade out
	local fadeOut = TweenService:Create(
		self.DamageVignette,
		TweenInfo.new(CONFIG.vignetteFadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ ImageTransparency = 1 }
	)
	fadeOut:Play()
end

function DamageFeedbackController:ShowHitMarker(isHeadshot: boolean)
	if not self.HitMarker then
		return
	end

	-- Set color based on headshot
	local color = isHeadshot and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 255, 255)

	for _, child in self.HitMarker:GetChildren() do
		if child:IsA("Frame") then
			child.BackgroundColor3 = color
		end
	end

	-- Show hit marker
	self.HitMarker.Visible = true

	-- Scale animation
	local startSize = CONFIG.hitMarkerSize * 1.3
	local endSize = CONFIG.hitMarkerSize

	self.HitMarker.Size = UDim2.new(0, startSize, 0, startSize)
	self.HitMarker.Position = UDim2.new(0.5, -startSize / 2, 0.5, -startSize / 2)

	local shrinkTween = TweenService:Create(
		self.HitMarker,
		TweenInfo.new(CONFIG.hitMarkerDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{
			Size = UDim2.new(0, endSize, 0, endSize),
			Position = UDim2.new(0.5, -endSize / 2, 0.5, -endSize / 2),
		}
	)
	shrinkTween:Play()

	-- Hide after duration
	task.delay(CONFIG.hitMarkerDuration, function()
		if self.HitMarker then
			self.HitMarker.Visible = false
		end
	end)
end

function DamageFeedbackController:ShowDirectionalDamage(direction: Vector3)
	-- Convert world direction to screen direction
	local character = player.Character
	if not character then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Get relative direction (in character's local space)
	local localDirection = hrp.CFrame:VectorToObjectSpace(direction)

	-- Determine which indicator to show based on direction
	local indicatorName: string?

	-- Check forward/backward (Z axis in local space)
	if math.abs(localDirection.Z) > math.abs(localDirection.X) then
		if localDirection.Z > 0 then
			indicatorName = "Bottom" -- Damage from behind
		else
			indicatorName = "Top" -- Damage from front
		end
	else
		if localDirection.X > 0 then
			indicatorName = "Right"
		else
			indicatorName = "Left"
		end
	end

	if not indicatorName then
		return
	end

	local indicator = self.DirectionalIndicators[indicatorName]
	if not indicator then
		return
	end

	-- Show indicator
	indicator.Visible = true

	-- Fade out
	local arrow = indicator:FindFirstChild("Arrow") :: ImageLabel?
	if arrow then
		arrow.ImageTransparency = 0.3

		local fadeOut = TweenService:Create(
			arrow,
			TweenInfo.new(CONFIG.directionalIndicatorDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ ImageTransparency = 1 }
		)
		fadeOut:Play()

		fadeOut.Completed:Connect(function()
			indicator.Visible = false
		end)
	end
end

function DamageFeedbackController:ApplyCameraShake(intensity: number)
	self.ShakeIntensity = math.max(self.ShakeIntensity, intensity)
end

function DamageFeedbackController:UpdateCameraShake(dt: number)
	if self.ShakeIntensity < 0.01 then
		self.ShakeIntensity = 0
		self.ShakeOffset = Vector3.zero
		return
	end

	-- Random offset based on intensity
	local offsetX = (math.random() - 0.5) * 2 * self.ShakeIntensity
	local offsetY = (math.random() - 0.5) * 2 * self.ShakeIntensity

	self.ShakeOffset = Vector3.new(offsetX, offsetY, 0)

	-- Apply to camera
	if camera then
		camera.CFrame = camera.CFrame * CFrame.new(self.ShakeOffset)
	end

	-- Decay intensity
	self.ShakeIntensity = self.ShakeIntensity - dt * CONFIG.cameraShakeDecay
end

-- ============================================
-- EVENT HANDLERS
-- ============================================

function DamageFeedbackController:OnDamageTaken(damage: number, sourcePosition: Vector3?)
	-- Calculate intensity based on damage amount
	local intensity = math.clamp(damage / 100, 0.2, 1)

	-- Show vignette
	self:ShowDamageVignette(intensity)

	-- Show directional indicator if we know the source
	if sourcePosition then
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local direction = (sourcePosition - hrp.Position).Unit
				self:ShowDirectionalDamage(direction)
			end
		end
	end

	-- Camera shake for heavy damage
	if damage >= CONFIG.heavyDamageThreshold then
		local shakeIntensity = math.clamp(damage / 50, 0.3, 1.5)
		self:ApplyCameraShake(shakeIntensity)
	end
end

function DamageFeedbackController:OnHitConfirmed(isHeadshot: boolean)
	self:ShowHitMarker(isHeadshot)
end

function DamageFeedbackController:ConnectEvents()
	-- Listen for fire result (hit confirmation)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local fireResultRemote = remotes:WaitForChild("FireResult")

	table.insert(
		self._connections,
		fireResultRemote.OnClientEvent:Connect(function(success: boolean, result: string, hitData: any)
			if success and result == "Hit" and hitData then
				local isHeadshot = hitData.isHeadshot or false
				self:OnHitConfirmed(isHeadshot)
			end
		end)
	)

	-- Listen for damage taken (via health change)
	local character = player.Character
	if character then
		self:SetupCharacterDamageDetection(character)
	end

	table.insert(
		self._connections,
		player.CharacterAdded:Connect(function(char)
			self:SetupCharacterDamageDetection(char)
		end)
	)

	-- Listen for damage events from server (with source position)
	local damageEventRemote = remotes:FindFirstChild("DamageEvent")
	if damageEventRemote then
		table.insert(
			self._connections,
			damageEventRemote.OnClientEvent:Connect(function(damage: number, sourcePosition: Vector3?)
				self:OnDamageTaken(damage, sourcePosition)
			end)
		)
	end
end

function DamageFeedbackController:SetupCharacterDamageDetection(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	self.LastHealth = humanoid.Health

	table.insert(
		self._connections,
		humanoid.HealthChanged:Connect(function(newHealth: number)
			if newHealth < self.LastHealth then
				local damage = self.LastHealth - newHealth
				-- Only show basic effects - detailed damage events come from server
				self:OnDamageTaken(damage, nil)
			end
			self.LastHealth = newHealth
		end)
	)
end

-- ============================================
-- CLEANUP
-- ============================================

function DamageFeedbackController:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)

	if self.ScreenGui then
		self.ScreenGui:Destroy()
	end

	table.clear(self.DirectionalIndicators)
end

return DamageFeedbackController
