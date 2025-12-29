# Horror Atmosphere

## Table of Contents
1. [Lighting Configuration](#lighting-configuration)
2. [Post-Processing Effects](#post-processing-effects)
3. [Sound Design](#sound-design)
4. [Environmental Effects](#environmental-effects)
5. [Tension Systems](#tension-systems)
6. [Jump Scares](#jump-scares)

---

## Lighting Configuration

### Base Horror Settings

```lua
local Lighting = game:GetService("Lighting")

-- Core lighting (dark, oppressive)
Lighting.Ambient = Color3.fromRGB(10, 10, 15)
Lighting.Brightness = 0.5
Lighting.OutdoorAmbient = Color3.fromRGB(20, 20, 30)
Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
Lighting.ColorShift_Top = Color3.fromRGB(30, 30, 40)

-- Time of day
Lighting.ClockTime = 0  -- Midnight
Lighting.GeographicLatitude = 45

-- Shadows
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.2
```

### Dynamic Lighting Presets

```lua
local LightingPresets = {
    SafeRoom = {
        Ambient = Color3.fromRGB(40, 35, 30),
        Brightness = 1.2,
        atmosphereDensity = 0.1,
        saturation = -0.1,
    },
    
    Corridor = {
        Ambient = Color3.fromRGB(8, 8, 12),
        Brightness = 0.3,
        atmosphereDensity = 0.5,
        saturation = -0.4,
    },
    
    Danger = {
        Ambient = Color3.fromRGB(15, 5, 5),
        Brightness = 0.4,
        atmosphereDensity = 0.6,
        saturation = -0.5,
    },
    
    Crescendo = {
        Ambient = Color3.fromRGB(20, 10, 10),
        Brightness = 0.6,
        atmosphereDensity = 0.3,
        saturation = -0.2,
    },
}

function ApplyLightingPreset(presetName: string, duration: number)
    local preset = LightingPresets[presetName]
    if not preset then return end
    
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Sine)
    
    TweenService:Create(Lighting, tweenInfo, {
        Ambient = preset.Ambient,
        Brightness = preset.Brightness,
    }):Play()
    
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmosphere then
        TweenService:Create(atmosphere, tweenInfo, {
            Density = preset.atmosphereDensity,
        }):Play()
    end
    
    local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if colorCorrection then
        TweenService:Create(colorCorrection, tweenInfo, {
            Saturation = preset.saturation,
        }):Play()
    end
end
```

### Flashlight System

```lua
local Flashlight = {}
Flashlight.__index = Flashlight

function Flashlight.new(player: Player)
    local self = setmetatable({}, Flashlight)
    
    self.Player = player
    self.IsOn = false
    self.Battery = 100
    self.DrainRate = 2  -- Per second
    
    -- Create spotlight attached to character
    self.Light = Instance.new("SpotLight")
    self.Light.Brightness = 3
    self.Light.Range = 40
    self.Light.Angle = 45
    self.Light.Face = Enum.NormalId.Front
    self.Light.Shadows = true
    self.Light.Enabled = false
    
    return self
end

function Flashlight:Attach()
    local char = self.Player.Character
    if not char then return end
    
    local head = char:FindFirstChild("Head")
    if head then
        self.Light.Parent = head
    end
end

function Flashlight:Toggle()
    if self.Battery <= 0 then return end
    
    self.IsOn = not self.IsOn
    self.Light.Enabled = self.IsOn
    
    -- Notify server (for Witch aggro)
    local char = self.Player.Character
    if char then
        char:SetAttribute("FlashlightOn", self.IsOn)
    end
end

function Flashlight:Update(dt: number)
    if self.IsOn then
        self.Battery = math.max(0, self.Battery - self.DrainRate * dt)
        
        if self.Battery <= 0 then
            self:Toggle()  -- Auto turn off
        end
        
        -- Flicker when low
        if self.Battery < 20 then
            self.Light.Brightness = 3 * (0.5 + math.random() * 0.5)
        end
    end
end

function Flashlight:Recharge(amount: number)
    self.Battery = math.min(100, self.Battery + amount)
end

return Flashlight
```

### Light Flickering

```lua
local function flickerLight(light: PointLight | SpotLight, config: {
    duration: number?,
    minBrightness: number?,
    maxBrightness: number?,
    flickerSpeed: number?,
}?)
    config = config or {}
    local duration = config.duration or 2
    local minBrightness = config.minBrightness or 0
    local maxBrightness = config.maxBrightness or light.Brightness
    local flickerSpeed = config.flickerSpeed or 0.1
    
    local originalBrightness = light.Brightness
    local endTime = os.clock() + duration
    
    task.spawn(function()
        while os.clock() < endTime do
            light.Brightness = minBrightness + math.random() * (maxBrightness - minBrightness)
            task.wait(flickerSpeed * (0.5 + math.random()))
        end
        
        light.Brightness = originalBrightness
    end)
end

-- Pattern: Flicker before enemy spawn
local function preSpawnFlicker(room: Model)
    for _, light in room:GetDescendants() do
        if light:IsA("PointLight") or light:IsA("SpotLight") then
            flickerLight(light, {duration = 1.5, flickerSpeed = 0.05})
        end
    end
end
```

## Post-Processing Effects

### Core Horror Stack

```lua
local function setupPostProcessing()
    -- Remove existing
    for _, effect in Lighting:GetChildren() do
        if effect:IsA("PostEffect") then
            effect:Destroy()
        end
    end
    
    -- Atmosphere (fog)
    local atmosphere = Instance.new("Atmosphere")
    atmosphere.Density = 0.4
    atmosphere.Offset = 0.25
    atmosphere.Color = Color3.fromRGB(40, 40, 50)
    atmosphere.Decay = Color3.fromRGB(60, 60, 70)
    atmosphere.Glare = 0
    atmosphere.Haze = 2
    atmosphere.Parent = Lighting
    
    -- Color correction (desaturation, slight tint)
    local colorCorrection = Instance.new("ColorCorrectionEffect")
    colorCorrection.Brightness = -0.05
    colorCorrection.Contrast = 0.1
    colorCorrection.Saturation = -0.3
    colorCorrection.TintColor = Color3.fromRGB(200, 200, 220)
    colorCorrection.Parent = Lighting
    
    -- Depth of field (focus effect)
    local dof = Instance.new("DepthOfFieldEffect")
    dof.FarIntensity = 0.3
    dof.FocusDistance = 20
    dof.InFocusRadius = 30
    dof.NearIntensity = 0
    dof.Parent = Lighting
    
    -- Bloom (for light glow)
    local bloom = Instance.new("BloomEffect")
    bloom.Intensity = 0.5
    bloom.Size = 24
    bloom.Threshold = 0.9
    bloom.Parent = Lighting
    
    -- Sun rays (subtle)
    local sunRays = Instance.new("SunRaysEffect")
    sunRays.Intensity = 0.02
    sunRays.Spread = 0.5
    sunRays.Parent = Lighting
    
    return {
        atmosphere = atmosphere,
        colorCorrection = colorCorrection,
        dof = dof,
        bloom = bloom,
        sunRays = sunRays,
    }
end
```

### Dynamic Effect Transitions

```lua
local Effects = {}

function Effects:DangerPulse(intensity: number, duration: number)
    local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if not cc then return end
    
    local originalTint = cc.TintColor
    local dangerTint = Color3.fromRGB(255, 200, 200)
    
    -- Pulse in
    TweenService:Create(cc, TweenInfo.new(duration * 0.3), {
        TintColor = dangerTint,
        Saturation = -0.5,
    }):Play()
    
    task.delay(duration * 0.5, function()
        -- Pulse out
        TweenService:Create(cc, TweenInfo.new(duration * 0.5), {
            TintColor = originalTint,
            Saturation = -0.3,
        }):Play()
    end)
end

function Effects:LowHealthVignette(healthPercent: number)
    -- Use a ScreenGui with frame for vignette
    local vignette = self.VignetteFrame
    if not vignette then return end
    
    local alpha = math.clamp(1 - healthPercent, 0, 0.7)
    vignette.BackgroundTransparency = 1 - alpha
    
    -- Pulse when critical
    if healthPercent < 0.25 then
        local pulse = 0.5 + math.sin(os.clock() * 4) * 0.2
        vignette.BackgroundTransparency = 1 - (alpha * pulse)
    end
end

function Effects:BlackOut(duration: number)
    local black = Instance.new("Frame")
    black.Size = UDim2.new(1, 0, 1, 0)
    black.BackgroundColor3 = Color3.new(0, 0, 0)
    black.BackgroundTransparency = 1
    black.ZIndex = 100
    black.Parent = game.Players.LocalPlayer.PlayerGui.ScreenGui
    
    -- Fade in
    TweenService:Create(black, TweenInfo.new(duration * 0.3), {
        BackgroundTransparency = 0
    }):Play()
    
    task.delay(duration * 0.7, function()
        -- Fade out
        TweenService:Create(black, TweenInfo.new(duration * 0.3), {
            BackgroundTransparency = 1
        }):Play()
    end)
    
    task.delay(duration, function()
        black:Destroy()
    end)
end
```

## Sound Design

### Ambient Layer System

```lua
local SoundService = game:GetService("SoundService")

local AmbientSystem = {
    layers = {},
    masterVolume = 1,
}

function AmbientSystem:Initialize()
    -- Create sound group for ambient
    self.AmbientGroup = Instance.new("SoundGroup")
    self.AmbientGroup.Name = "Ambient"
    self.AmbientGroup.Volume = 0.7
    self.AmbientGroup.Parent = SoundService
end

function AmbientSystem:AddLayer(name: string, soundId: string, baseVolume: number)
    local sound = Instance.new("Sound")
    sound.Name = name
    sound.SoundId = soundId
    sound.Volume = 0  -- Start silent
    sound.Looped = true
    sound.SoundGroup = self.AmbientGroup
    sound.Parent = SoundService
    sound:Play()
    
    self.layers[name] = {
        sound = sound,
        baseVolume = baseVolume,
        targetVolume = 0,
    }
end

function AmbientSystem:SetLayerVolume(name: string, volume: number, fadeTime: number?)
    local layer = self.layers[name]
    if not layer then return end
    
    fadeTime = fadeTime or 1
    layer.targetVolume = volume * layer.baseVolume
    
    TweenService:Create(layer.sound, TweenInfo.new(fadeTime), {
        Volume = layer.targetVolume
    }):Play()
end

function AmbientSystem:SetupHorrorAmbient()
    -- Base layers
    self:AddLayer("BaseAmbient", "rbxassetid://ambient_base", 0.3)
    self:AddLayer("Wind", "rbxassetid://wind_loop", 0.2)
    self:AddLayer("Drones", "rbxassetid://horror_drone", 0.15)
    self:AddLayer("Heartbeat", "rbxassetid://heartbeat", 0.4)
    self:AddLayer("Whispers", "rbxassetid://whispers", 0.1)
    self:AddLayer("Stinger", "rbxassetid://tension_stinger", 0.6)
    
    -- Start base layers
    self:SetLayerVolume("BaseAmbient", 1, 0)
    self:SetLayerVolume("Wind", 0.5, 0)
end

function AmbientSystem:OnIntensityChanged(intensity: number)
    -- Scale ambient with intensity
    local tensionPercent = intensity / 100
    
    self:SetLayerVolume("Heartbeat", tensionPercent, 0.5)
    self:SetLayerVolume("Drones", tensionPercent * 0.7, 0.5)
    
    -- Whispers at high tension
    if tensionPercent > 0.7 then
        self:SetLayerVolume("Whispers", (tensionPercent - 0.7) * 3, 0.3)
    else
        self:SetLayerVolume("Whispers", 0, 0.3)
    end
end

return AmbientSystem
```

### 3D Positional Audio

```lua
local function play3DSound(config: {
    soundId: string,
    position: Vector3,
    volume: number?,
    rollOffMin: number?,
    rollOffMax: number?,
    pitch: number?,
})
    -- Create attachment at position
    local attachment = Instance.new("Attachment")
    attachment.WorldPosition = config.position
    attachment.Parent = workspace.Terrain
    
    local sound = Instance.new("Sound")
    sound.SoundId = config.soundId
    sound.Volume = config.volume or 1
    sound.RollOffMode = Enum.RollOffMode.InverseTapered
    sound.RollOffMinDistance = config.rollOffMin or 10
    sound.RollOffMaxDistance = config.rollOffMax or 100
    sound.PlaybackSpeed = config.pitch or 1
    sound.Parent = attachment
    
    sound:Play()
    
    sound.Ended:Connect(function()
        attachment:Destroy()
    end)
    
    return sound
end

-- Enemy growls with distance falloff
local function playZombieGrowl(position: Vector3)
    local growlIds = {
        "rbxassetid://growl_1",
        "rbxassetid://growl_2",
        "rbxassetid://growl_3",
    }
    
    play3DSound({
        soundId = growlIds[math.random(#growlIds)],
        position = position,
        volume = 0.8,
        rollOffMin = 5,
        rollOffMax = 40,
        pitch = 0.9 + math.random() * 0.2,
    })
end

-- Special infected sounds (louder, longer range)
local SpecialSounds = {
    Hunter = {
        spawn = "rbxassetid://hunter_spawn",
        pounce = "rbxassetid://hunter_pounce",
    },
    Tank = {
        spawn = "rbxassetid://tank_spawn",
        music = "rbxassetid://tank_music",
        roar = "rbxassetid://tank_roar",
    },
    Witch = {
        crying = "rbxassetid://witch_cry",
        startle = "rbxassetid://witch_startle",
    },
}
```

### Music System

```lua
local MusicSystem = {
    currentTrack = nil,
    combatMusic = nil,
    safeMusic = nil,
}

function MusicSystem:Initialize()
    self.combatMusic = Instance.new("Sound")
    self.combatMusic.SoundId = "rbxassetid://combat_music"
    self.combatMusic.Volume = 0
    self.combatMusic.Looped = true
    self.combatMusic.Parent = SoundService
    self.combatMusic:Play()
    
    self.safeMusic = Instance.new("Sound")
    self.safeMusic.SoundId = "rbxassetid://safe_room_music"
    self.safeMusic.Volume = 0
    self.safeMusic.Looped = true
    self.safeMusic.Parent = SoundService
    self.safeMusic:Play()
end

function MusicSystem:TransitionTo(trackName: string, duration: number)
    local tracks = {
        combat = self.combatMusic,
        safe = self.safeMusic,
    }
    
    local targetTrack = tracks[trackName]
    if not targetTrack then return end
    
    -- Fade out current
    if self.currentTrack and self.currentTrack ~= targetTrack then
        TweenService:Create(self.currentTrack, TweenInfo.new(duration), {
            Volume = 0
        }):Play()
    end
    
    -- Fade in target
    TweenService:Create(targetTrack, TweenInfo.new(duration), {
        Volume = 0.5
    }):Play()
    
    self.currentTrack = targetTrack
end

return MusicSystem
```

## Environmental Effects

### Particle Effects

```lua
local function createBloodSplatter(position: Vector3, direction: Vector3?)
    local attachment = Instance.new("Attachment")
    attachment.WorldPosition = position
    attachment.Parent = workspace.Terrain
    
    local particles = Instance.new("ParticleEmitter")
    particles.Texture = "rbxassetid://blood_texture"
    particles.Color = ColorSequence.new(Color3.fromRGB(139, 0, 0))
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 0.1),
    })
    particles.Lifetime = NumberRange.new(0.5, 1)
    particles.Speed = NumberRange.new(10, 30)
    particles.SpreadAngle = Vector2.new(45, 45)
    particles.Drag = 5
    particles.Rate = 0
    particles.Parent = attachment
    
    -- Burst
    particles:Emit(20)
    
    Debris:AddItem(attachment, 2)
end

local function createFogBank(position: Vector3, radius: number)
    local part = Instance.new("Part")
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(radius * 2, radius, radius * 2)
    part.Position = position
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Parent = workspace
    
    local attachment = Instance.new("Attachment")
    attachment.Parent = part
    
    local particles = Instance.new("ParticleEmitter")
    particles.Texture = "rbxassetid://fog_texture"
    particles.Color = ColorSequence.new(Color3.fromRGB(100, 100, 110))
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.2, 0.6),
        NumberSequenceKeypoint.new(0.8, 0.6),
        NumberSequenceKeypoint.new(1, 1),
    })
    particles.Size = NumberSequence.new(10, 20)
    particles.Lifetime = NumberRange.new(5, 10)
    particles.Speed = NumberRange.new(1, 3)
    particles.Rate = 5
    particles.Parent = attachment
    
    return part
end
```

### Screen Effects

```lua
local ScreenEffects = {}

function ScreenEffects:DamageFlash()
    local gui = game.Players.LocalPlayer.PlayerGui:FindFirstChild("ScreenEffects")
    if not gui then return end
    
    local flash = gui:FindFirstChild("DamageFlash")
    if not flash then
        flash = Instance.new("Frame")
        flash.Name = "DamageFlash"
        flash.Size = UDim2.new(1, 0, 1, 0)
        flash.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        flash.BackgroundTransparency = 1
        flash.ZIndex = 50
        flash.Parent = gui
    end
    
    flash.BackgroundTransparency = 0.5
    TweenService:Create(flash, TweenInfo.new(0.3), {
        BackgroundTransparency = 1
    }):Play()
end

function ScreenEffects:HealFlash()
    -- Similar, but green
end

function ScreenEffects:CameraShake(intensity: number, duration: number)
    local camera = workspace.CurrentCamera
    local originalCFrame = camera.CFrame
    local endTime = os.clock() + duration
    
    local connection
    connection = RunService.RenderStepped:Connect(function()
        if os.clock() >= endTime then
            camera.CFrame = originalCFrame
            connection:Disconnect()
            return
        end
        
        local remaining = (endTime - os.clock()) / duration
        local currentIntensity = intensity * remaining
        
        local offset = Vector3.new(
            (math.random() - 0.5) * currentIntensity,
            (math.random() - 0.5) * currentIntensity,
            (math.random() - 0.5) * currentIntensity * 0.5
        )
        
        camera.CFrame = originalCFrame * CFrame.new(offset)
    end)
end

return ScreenEffects
```

## Tension Systems

### Dynamic Tension Tracker

```lua
local TensionSystem = {
    tension = 0,  -- 0-100
    listeners = {},
}

function TensionSystem:AddTension(amount: number, source: string?)
    self.tension = math.clamp(self.tension + amount, 0, 100)
    self:NotifyListeners()
end

function TensionSystem:DecayTension(dt: number)
    self.tension = math.max(0, self.tension - dt * 3)
    self:NotifyListeners()
end

function TensionSystem:NotifyListeners()
    for _, listener in self.listeners do
        listener(self.tension)
    end
end

function TensionSystem:OnListen(callback: (number) -> ())
    table.insert(self.listeners, callback)
end

-- Connect to ambient system
TensionSystem:OnListen(function(tension)
    AmbientSystem:OnIntensityChanged(tension)
end)

-- Tension sources
local TensionSources = {
    EnemyNearby = 2,           -- Per enemy within 20 studs, per second
    SpecialSpotted = 15,       -- One-time when spotted
    Damaged = function(amount) return amount * 0.3 end,
    Incapacitated = 25,
    TeammateDown = 15,
    LowHealth = 10,            -- When below 30%
    InDarkness = 1,            -- Per second in dark area
}

return TensionSystem
```

## Jump Scares

### Jump Scare Controller

Jump scares should be **functional** (entity kills you) not gratuitous. Use sparingly.

```lua
local JumpScareSystem = {}

function JumpScareSystem:Execute(config: {
    type: "audio" | "visual" | "entity",
    soundId: string?,
    duration: number?,
    cameraLock: boolean?,
    entity: Model?,
})
    -- Audio stinger
    if config.soundId then
        local sound = Instance.new("Sound")
        sound.SoundId = config.soundId
        sound.Volume = 1.5
        sound.Parent = SoundService
        sound:Play()
        sound.Ended:Connect(function()
            sound:Destroy()
        end)
    end
    
    -- Screen flash
    ScreenEffects:BlackOut(0.1)
    ScreenEffects:CameraShake(0.5, 0.3)
    
    -- Camera lock (optional)
    if config.cameraLock and config.entity then
        self:LockCameraTo(config.entity, config.duration or 1)
    end
end

function JumpScareSystem:LockCameraTo(target: Model, duration: number)
    local camera = workspace.CurrentCamera
    local originalType = camera.CameraType
    camera.CameraType = Enum.CameraType.Scriptable
    
    local targetPart = target.PrimaryPart or target:FindFirstChild("Head")
    if not targetPart then return end
    
    local startTime = os.clock()
    local connection
    connection = RunService.RenderStepped:Connect(function()
        if os.clock() - startTime >= duration then
            camera.CameraType = originalType
            connection:Disconnect()
            return
        end
        
        local playerHead = game.Players.LocalPlayer.Character and 
            game.Players.LocalPlayer.Character:FindFirstChild("Head")
        if playerHead then
            camera.CFrame = CFrame.lookAt(playerHead.Position, targetPart.Position)
        end
    end)
end

-- Example: Entity appears when player looks away
function JumpScareSystem:SetupLookAwayTrigger(position: Vector3, entityToSpawn: Model)
    local triggered = false
    
    RunService.Heartbeat:Connect(function()
        if triggered then return end
        
        local camera = workspace.CurrentCamera
        local toPosition = (position - camera.CFrame.Position).Unit
        local lookVector = camera.CFrame.LookVector
        
        -- Check if player is looking away
        local dot = lookVector:Dot(toPosition)
        
        if dot < -0.5 then  -- Looking away
            triggered = true
            
            -- Spawn entity at position
            local entity = entityToSpawn:Clone()
            entity:PivotTo(CFrame.new(position))
            entity.Parent = workspace
            
            -- When player looks back...
            self:WaitForPlayerToLook(position, function()
                self:Execute({
                    type = "entity",
                    soundId = "rbxassetid://jumpscare_stinger",
                    entity = entity,
                    cameraLock = true,
                    duration = 0.5,
                })
            end)
        end
    end)
end

return JumpScareSystem
```

### Tension Building Before Scares

```lua
-- Never instant scares - build tension first
local function buildTensionSequence(duration: number, callback: () -> ())
    -- Phase 1: Audio cue
    task.spawn(function()
        AmbientSystem:SetLayerVolume("Stinger", 0.3, 1)
    end)
    
    -- Phase 2: Flicker lights
    task.delay(duration * 0.3, function()
        preSpawnFlicker(workspace.CurrentRoom)
    end)
    
    -- Phase 3: Sound proximity
    task.delay(duration * 0.6, function()
        play3DSound({
            soundId = "rbxassetid://footsteps_approach",
            position = game.Players.LocalPlayer.Character.HumanoidRootPart.Position + 
                Vector3.new(0, 0, -10),
            volume = 0.5,
        })
    end)
    
    -- Phase 4: Execute
    task.delay(duration, callback)
end
```
