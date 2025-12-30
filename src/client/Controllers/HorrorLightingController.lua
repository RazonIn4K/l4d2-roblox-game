--!strict
--[[
    HorrorLightingController
    Manages horror atmosphere lighting effects: fog, color correction, flickering
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- Types
export type HorrorLightingController = {
	ColorCorrection: ColorCorrectionEffect?,
	Bloom: BloomEffect?,
	Blur: BlurEffect?,
	Atmosphere: Atmosphere?,
	IsInSafeRoom: boolean,
	IntensityLevel: number,
	_connections: { RBXScriptConnection },
	new: () -> HorrorLightingController,
	Get: (self: HorrorLightingController) -> HorrorLightingController,
	Start: (self: HorrorLightingController) -> (),
	SetupLightingEffects: (self: HorrorLightingController) -> (),
	SetupFlickeringLights: (self: HorrorLightingController) -> (),
	UpdateAtmosphere: (self: HorrorLightingController, dt: number) -> (),
	SetIntensity: (self: HorrorLightingController, level: number) -> (),
	OnGameStateChanged: (self: HorrorLightingController, state: string) -> (),
	ConnectGameStateEvents: (self: HorrorLightingController) -> (),
	TransitionToSafeRoom: (self: HorrorLightingController) -> (),
	TransitionToHorror: (self: HorrorLightingController) -> (),
	Destroy: (self: HorrorLightingController) -> (),
}

-- Constants
local CONFIG = {
	-- Base atmosphere settings (horror mood)
	baseBrightness = 0.3,
	baseAmbient = Color3.fromRGB(20, 20, 30),
	baseFogColor = Color3.fromRGB(30, 30, 40),
	baseFogStart = 50,
	baseFogEnd = 300,

	-- Color correction for horror
	baseSaturation = -0.2,
	baseContrast = 0.1,
	baseTint = Color3.fromRGB(220, 230, 255), -- Slightly cold/blue

	-- Safe room (brighter, less oppressive)
	safeRoomBrightness = 1.0,
	safeRoomSaturation = 0,
	safeRoomFogStart = 100,
	safeRoomFogEnd = 500,

	-- High intensity (horde incoming)
	highIntensitySaturation = -0.4,
	highIntensityTint = Color3.fromRGB(255, 200, 200), -- Red tint

	-- Flicker settings
	flickerChance = 0.02,
	flickerDuration = 0.1,
}

-- Module
local HorrorLightingController = {} :: HorrorLightingController
HorrorLightingController.__index = HorrorLightingController

local _instance: HorrorLightingController? = nil

function HorrorLightingController.new(): HorrorLightingController
	if _instance then
		return _instance
	end

	local self = setmetatable({}, HorrorLightingController) :: HorrorLightingController

	-- Lighting effects
	self.ColorCorrection = nil
	self.Bloom = nil
	self.Blur = nil
	self.Atmosphere = nil

	-- State
	self.IsInSafeRoom = false
	self.IntensityLevel = 0 -- 0 = calm, 1 = max intensity

	-- Connections
	self._connections = {}

	_instance = self
	return self
end

function HorrorLightingController:Get(): HorrorLightingController
	return HorrorLightingController.new()
end

function HorrorLightingController:Start()
	-- Setup lighting effects
	self:SetupLightingEffects()

	-- Setup flickering lights in the world
	self:SetupFlickeringLights()

	-- Update loop for dynamic effects
	table.insert(
		self._connections,
		RunService.Heartbeat:Connect(function(dt)
			self:UpdateAtmosphere(dt)
		end)
	)

	-- Listen for game state changes
	self:ConnectGameStateEvents()

	print("[HorrorLightingController] Started")
end

function HorrorLightingController:SetupLightingEffects()
	-- Color correction for horror mood
	local existingCC = Lighting:FindFirstChild("HorrorColorCorrection")
	if existingCC then
		existingCC:Destroy()
	end

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "HorrorColorCorrection"
	colorCorrection.Brightness = 0
	colorCorrection.Contrast = CONFIG.baseContrast
	colorCorrection.Saturation = CONFIG.baseSaturation
	colorCorrection.TintColor = CONFIG.baseTint
	colorCorrection.Enabled = true
	colorCorrection.Parent = Lighting
	self.ColorCorrection = colorCorrection

	-- Subtle bloom for light glow
	local existingBloom = Lighting:FindFirstChild("HorrorBloom")
	if existingBloom then
		existingBloom:Destroy()
	end

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "HorrorBloom"
	bloom.Intensity = 0.3
	bloom.Size = 24
	bloom.Threshold = 0.8
	bloom.Enabled = true
	bloom.Parent = Lighting
	self.Bloom = bloom

	-- Depth of field blur for atmosphere
	local existingBlur = Lighting:FindFirstChild("HorrorBlur")
	if existingBlur then
		existingBlur:Destroy()
	end

	local blur = Instance.new("DepthOfFieldEffect")
	blur.Name = "HorrorBlur"
	blur.FarIntensity = 0.1
	blur.FocusDistance = 50
	blur.InFocusRadius = 30
	blur.NearIntensity = 0
	blur.Enabled = true
	blur.Parent = Lighting
	self.Blur = blur

	-- Fog atmosphere
	local existingAtmosphere = Lighting:FindFirstChild("HorrorAtmosphere")
	if existingAtmosphere then
		existingAtmosphere:Destroy()
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "HorrorAtmosphere"
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.25
	atmosphere.Color = CONFIG.baseFogColor
	atmosphere.Decay = Color3.fromRGB(50, 50, 60)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.5
	atmosphere.Parent = Lighting
	self.Atmosphere = atmosphere

	-- Set base lighting
	Lighting.Brightness = CONFIG.baseBrightness
	Lighting.Ambient = CONFIG.baseAmbient
	Lighting.OutdoorAmbient = CONFIG.baseAmbient
	Lighting.FogColor = CONFIG.baseFogColor
	Lighting.FogStart = CONFIG.baseFogStart
	Lighting.FogEnd = CONFIG.baseFogEnd
end

function HorrorLightingController:SetupFlickeringLights()
	-- Find all lights in the environment and make some flicker
	for _, light in workspace:GetDescendants() do
		if light:IsA("PointLight") or light:IsA("SpotLight") then
			-- 30% chance to be a flickering light
			if math.random() < 0.3 then
				-- Store original brightness
				local originalBrightness = light.Brightness

				-- Create flicker loop
				task.spawn(function()
					while light and light.Parent do
						-- Random flicker
						if math.random() < CONFIG.flickerChance then
							light.Brightness = originalBrightness * math.random(20, 80) / 100
							task.wait(CONFIG.flickerDuration)
							light.Brightness = originalBrightness
						end
						task.wait(0.1)
					end
				end)
			end
		end
	end
end

function HorrorLightingController:UpdateAtmosphere(_dt: number)
	if not self.ColorCorrection then
		return
	end

	-- Adjust effects based on player health
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local healthPercent = humanoid.Health / humanoid.MaxHealth

	-- Low health = more desaturated and darker
	if healthPercent < 0.25 then
		local lowHealthFactor = 1 - (healthPercent / 0.25) -- 0 at 25%, 1 at 0%

		-- Increase desaturation
		self.ColorCorrection.Saturation = CONFIG.baseSaturation - (lowHealthFactor * 0.4)

		-- Add slight vignette darkness (using brightness)
		self.ColorCorrection.Brightness = -lowHealthFactor * 0.1

		-- Pulse effect for very low health
		if healthPercent < 0.15 then
			local pulse = math.sin(os.clock() * 4) * 0.5 + 0.5
			self.ColorCorrection.TintColor = Color3.new(
				1 - (pulse * 0.1 * (1 - healthPercent / 0.15)),
				1 - (pulse * 0.2 * (1 - healthPercent / 0.15)),
				1 - (pulse * 0.2 * (1 - healthPercent / 0.15))
			)
		end
	else
		-- Normal health - use base or intensity-based settings
		if not self.IsInSafeRoom then
			self.ColorCorrection.Saturation = CONFIG.baseSaturation
				- (self.IntensityLevel * (CONFIG.highIntensitySaturation - CONFIG.baseSaturation))
			self.ColorCorrection.Brightness = 0
		end
	end
end

function HorrorLightingController:SetIntensity(level: number)
	self.IntensityLevel = math.clamp(level, 0, 1)

	if self.IsInSafeRoom then
		return -- Don't apply intensity effects in safe room
	end

	if not self.ColorCorrection then
		return
	end

	-- Lerp between base and high intensity
	local t = self.IntensityLevel

	-- Color correction
	local saturation = CONFIG.baseSaturation + (CONFIG.highIntensitySaturation - CONFIG.baseSaturation) * t
	local tintR = CONFIG.baseTint.R + (CONFIG.highIntensityTint.R - CONFIG.baseTint.R) * t
	local tintG = CONFIG.baseTint.G + (CONFIG.highIntensityTint.G - CONFIG.baseTint.G) * t
	local tintB = CONFIG.baseTint.B + (CONFIG.highIntensityTint.B - CONFIG.baseTint.B) * t

	TweenService:Create(self.ColorCorrection, TweenInfo.new(1), {
		Saturation = saturation,
		TintColor = Color3.new(tintR, tintG, tintB),
	}):Play()
end

function HorrorLightingController:OnGameStateChanged(state: string)
	if state == "SafeRoom" then
		self.IsInSafeRoom = true
		self:TransitionToSafeRoom()
	elseif state == "Playing" then
		self.IsInSafeRoom = false
		self:TransitionToHorror()
	elseif state == "BuildUp" then
		self:SetIntensity(0.5)
	elseif state == "Crescendo" then
		self:SetIntensity(1)
	end
end

function HorrorLightingController:TransitionToSafeRoom()
	-- Brighter, safer feeling
	TweenService:Create(Lighting, TweenInfo.new(2), {
		Brightness = CONFIG.safeRoomBrightness,
		FogStart = CONFIG.safeRoomFogStart,
		FogEnd = CONFIG.safeRoomFogEnd,
	}):Play()

	if self.ColorCorrection then
		TweenService:Create(self.ColorCorrection, TweenInfo.new(2), {
			Saturation = CONFIG.safeRoomSaturation,
			TintColor = Color3.new(1, 1, 1),
		}):Play()
	end

	if self.Atmosphere then
		TweenService:Create(self.Atmosphere, TweenInfo.new(2), {
			Density = 0.15,
			Haze = 0.5,
		}):Play()
	end

	print("[HorrorLightingController] Transitioned to Safe Room lighting")
end

function HorrorLightingController:TransitionToHorror()
	-- Dark, oppressive atmosphere
	TweenService:Create(Lighting, TweenInfo.new(2), {
		Brightness = CONFIG.baseBrightness,
		FogStart = CONFIG.baseFogStart,
		FogEnd = CONFIG.baseFogEnd,
	}):Play()

	if self.ColorCorrection then
		TweenService:Create(self.ColorCorrection, TweenInfo.new(2), {
			Saturation = CONFIG.baseSaturation,
			TintColor = CONFIG.baseTint,
		}):Play()
	end

	if self.Atmosphere then
		TweenService:Create(self.Atmosphere, TweenInfo.new(2), {
			Density = 0.3,
			Haze = 1.5,
		}):Play()
	end

	print("[HorrorLightingController] Transitioned to Horror lighting")
end

function HorrorLightingController:ConnectGameStateEvents()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local gameStateRemote = remotes:WaitForChild("GameState")

	table.insert(
		self._connections,
		gameStateRemote.OnClientEvent:Connect(function(stateType: string, data: any)
			if stateType == "DirectorState" then
				if data == "BuildUp" then
					self:OnGameStateChanged("BuildUp")
				elseif data == "Crescendo" then
					self:OnGameStateChanged("Crescendo")
				end
				return
			end

			-- Handle game state changes
			if stateType == "Playing" then
				self:OnGameStateChanged("Playing")
			elseif stateType == "SafeRoom" then
				self:OnGameStateChanged("SafeRoom")
			end
		end)
	)
end

function HorrorLightingController:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)

	if self.ColorCorrection then
		self.ColorCorrection:Destroy()
	end
	if self.Bloom then
		self.Bloom:Destroy()
	end
	if self.Blur then
		self.Blur:Destroy()
	end
	if self.Atmosphere then
		self.Atmosphere:Destroy()
	end
end

return HorrorLightingController
