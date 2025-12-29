--!strict
--[[
    UIController
    Manages all player HUD elements: health, teammates, revive progress
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer

-- Constants
local HEALTH_COLORS = {
    high = Color3.fromRGB(76, 209, 55),      -- Green (>50%)
    medium = Color3.fromRGB(251, 197, 49),   -- Yellow (25-50%)
    low = Color3.fromRGB(232, 65, 24),       -- Red (<25%)
}

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Module
local UIController = {}
UIController.__index = UIController

local _instance = nil

function UIController.new()
    if _instance then
        return _instance
    end

    local self = setmetatable({}, UIController)

    -- UI References
    self.ScreenGui = nil
    self.HealthFrame = nil
    self.HealthBar = nil
    self.HealthText = nil
    self.IncapOverlay = nil
    self.TeammateFrame = nil
    self.ReviveProgress = nil
    self.ReviveBar = nil
    self.ReviveText = nil
    self.ColorCorrection = nil

    -- State
    self.LastHealth = 100
    self.IsIncapacitated = false
    self.TeammateCards = {}

    -- Connections
    self._connections = {}

    _instance = self
    return self
end

function UIController:Get()
    return UIController.new()
end

function UIController:Start()
    -- Create all UI elements
    self:CreateUI()

    -- Connect to local player health
    self:ConnectHealthEvents()

    -- Connect to game state updates
    self:ConnectGameStateEvents()

    print("[UIController] Started - HUD active")
end

-- ============================================
-- UI CREATION
-- ============================================

function UIController:CreateUI()
    -- Main ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "GameHUD"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = player:WaitForChild("PlayerGui")
    self.ScreenGui = screenGui

    -- Create components
    self:CreateHealthFrame()
    self:CreateTeammateFrame()
    self:CreateReviveProgress()
    self:CreateIncapOverlay()
    self:CreateColorCorrection()
end

function UIController:CreateHealthFrame()
    -- Health Frame (bottom-left)
    local healthFrame = Instance.new("Frame")
    healthFrame.Name = "HealthFrame"
    healthFrame.Size = UDim2.new(0, 250, 0, 60)
    healthFrame.Position = UDim2.new(0, 20, 1, -80)
    healthFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    healthFrame.BackgroundTransparency = 0.5
    healthFrame.BorderSizePixel = 0
    healthFrame.Parent = self.ScreenGui
    self.HealthFrame = healthFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = healthFrame

    -- Health bar background
    local barBg = Instance.new("Frame")
    barBg.Name = "BarBackground"
    barBg.Size = UDim2.new(1, -20, 0, 20)
    barBg.Position = UDim2.new(0, 10, 0, 10)
    barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    barBg.BorderSizePixel = 0
    barBg.Parent = healthFrame

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 4)
    barCorner.Parent = barBg

    -- Health bar fill
    local healthBar = Instance.new("Frame")
    healthBar.Name = "HealthBar"
    healthBar.Size = UDim2.new(1, 0, 1, 0)
    healthBar.BackgroundColor3 = HEALTH_COLORS.high
    healthBar.BorderSizePixel = 0
    healthBar.Parent = barBg
    self.HealthBar = healthBar

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = healthBar

    -- Health text
    local healthText = Instance.new("TextLabel")
    healthText.Name = "HealthText"
    healthText.Size = UDim2.new(1, -20, 0, 20)
    healthText.Position = UDim2.new(0, 10, 0, 35)
    healthText.BackgroundTransparency = 1
    healthText.TextColor3 = Color3.fromRGB(255, 255, 255)
    healthText.TextSize = 16
    healthText.Font = Enum.Font.GothamBold
    healthText.Text = "100 / 100"
    healthText.TextXAlignment = Enum.TextXAlignment.Left
    healthText.Parent = healthFrame
    self.HealthText = healthText
end

function UIController:CreateTeammateFrame()
    -- Teammate Frame (left side, vertical list)
    local teammateFrame = Instance.new("Frame")
    teammateFrame.Name = "TeammateFrame"
    teammateFrame.Size = UDim2.new(0, 180, 0, 200)
    teammateFrame.Position = UDim2.new(0, 20, 0, 100)
    teammateFrame.BackgroundTransparency = 1
    teammateFrame.Parent = self.ScreenGui
    self.TeammateFrame = teammateFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 5)
    listLayout.Parent = teammateFrame
end

function UIController:CreateReviveProgress()
    -- Revive Progress (center, hidden by default)
    local reviveFrame = Instance.new("Frame")
    reviveFrame.Name = "ReviveProgress"
    reviveFrame.Size = UDim2.new(0, 300, 0, 80)
    reviveFrame.Position = UDim2.new(0.5, -150, 0.6, 0)
    reviveFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    reviveFrame.BackgroundTransparency = 0.5
    reviveFrame.BorderSizePixel = 0
    reviveFrame.Visible = false
    reviveFrame.Parent = self.ScreenGui
    self.ReviveProgress = reviveFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = reviveFrame

    -- Revive text
    local reviveText = Instance.new("TextLabel")
    reviveText.Name = "ReviveText"
    reviveText.Size = UDim2.new(1, -20, 0, 25)
    reviveText.Position = UDim2.new(0, 10, 0, 10)
    reviveText.BackgroundTransparency = 1
    reviveText.TextColor3 = Color3.fromRGB(255, 255, 255)
    reviveText.TextSize = 16
    reviveText.Font = Enum.Font.GothamBold
    reviveText.Text = "Being revived by..."
    reviveText.TextXAlignment = Enum.TextXAlignment.Center
    reviveText.Parent = reviveFrame
    self.ReviveText = reviveText

    -- Progress bar background
    local barBg = Instance.new("Frame")
    barBg.Name = "BarBackground"
    barBg.Size = UDim2.new(1, -20, 0, 20)
    barBg.Position = UDim2.new(0, 10, 0, 45)
    barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    barBg.BorderSizePixel = 0
    barBg.Parent = reviveFrame

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 4)
    barCorner.Parent = barBg

    -- Progress bar fill
    local reviveBar = Instance.new("Frame")
    reviveBar.Name = "ReviveBar"
    reviveBar.Size = UDim2.new(0, 0, 1, 0)
    reviveBar.BackgroundColor3 = Color3.fromRGB(76, 209, 55)
    reviveBar.BorderSizePixel = 0
    reviveBar.Parent = barBg
    self.ReviveBar = reviveBar

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = reviveBar
end

function UIController:CreateIncapOverlay()
    -- Incap Overlay (red, hidden by default)
    local incapOverlay = Instance.new("Frame")
    incapOverlay.Name = "IncapOverlay"
    incapOverlay.Size = UDim2.new(1, 0, 1, 0)
    incapOverlay.BackgroundColor3 = Color3.fromRGB(139, 0, 0)
    incapOverlay.BackgroundTransparency = 0.85
    incapOverlay.BorderSizePixel = 0
    incapOverlay.Visible = false
    incapOverlay.Parent = self.ScreenGui
    self.IncapOverlay = incapOverlay

    -- INCAPACITATED text
    local incapText = Instance.new("TextLabel")
    incapText.Name = "IncapText"
    incapText.Size = UDim2.new(1, 0, 0, 60)
    incapText.Position = UDim2.new(0, 0, 0.3, 0)
    incapText.BackgroundTransparency = 1
    incapText.TextColor3 = Color3.fromRGB(255, 50, 50)
    incapText.TextSize = 48
    incapText.Font = Enum.Font.GothamBlack
    incapText.Text = "INCAPACITATED"
    incapText.TextXAlignment = Enum.TextXAlignment.Center
    incapText.Parent = incapOverlay

    -- Bleedout timer
    local bleedoutText = Instance.new("TextLabel")
    bleedoutText.Name = "BleedoutText"
    bleedoutText.Size = UDim2.new(1, 0, 0, 30)
    bleedoutText.Position = UDim2.new(0, 0, 0.3, 70)
    bleedoutText.BackgroundTransparency = 1
    bleedoutText.TextColor3 = Color3.fromRGB(255, 255, 255)
    bleedoutText.TextSize = 24
    bleedoutText.Font = Enum.Font.GothamBold
    bleedoutText.Text = "Bleedout: 300"
    bleedoutText.TextXAlignment = Enum.TextXAlignment.Center
    bleedoutText.Parent = incapOverlay
end

function UIController:CreateColorCorrection()
    -- Color correction for incap state
    local colorCorrection = Instance.new("ColorCorrectionEffect")
    colorCorrection.Name = "IncapColorCorrection"
    colorCorrection.Saturation = 0
    colorCorrection.Brightness = 0
    colorCorrection.Contrast = 0
    colorCorrection.TintColor = Color3.new(1, 1, 1)
    colorCorrection.Enabled = false
    colorCorrection.Parent = Lighting
    self.ColorCorrection = colorCorrection
end

-- ============================================
-- HEALTH BAR LOGIC
-- ============================================

function UIController:ConnectHealthEvents()
    local character = player.Character
    if character then
        self:SetupCharacterHealth(character)
    end

    table.insert(self._connections, player.CharacterAdded:Connect(function(char)
        self:SetupCharacterHealth(char)
    end))
end

function UIController:SetupCharacterHealth(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid

    -- Initial update
    self:UpdateHealthBar(humanoid.Health, humanoid.MaxHealth)

    -- Connect to health changes
    table.insert(self._connections, humanoid.HealthChanged:Connect(function(health)
        local maxHealth = humanoid.MaxHealth

        -- Check if taking damage (for flash effect)
        if health < self.LastHealth then
            self:FlashDamage()
        end

        self:UpdateHealthBar(health, maxHealth)
        self.LastHealth = health
    end))
end

function UIController:UpdateHealthBar(health: number, maxHealth: number)
    if not self.HealthBar or not self.HealthText then return end

    local healthPercent = math.clamp(health / maxHealth, 0, 1)

    -- Determine color based on health percentage
    local color
    if healthPercent > 0.5 then
        color = HEALTH_COLORS.high
    elseif healthPercent > 0.25 then
        color = HEALTH_COLORS.medium
    else
        color = HEALTH_COLORS.low
    end

    -- Tween the health bar
    local tween = TweenService:Create(self.HealthBar, TWEEN_INFO, {
        Size = UDim2.new(healthPercent, 0, 1, 0),
        BackgroundColor3 = color,
    })
    tween:Play()

    -- Update text
    self.HealthText.Text = string.format("%d / %d", math.floor(health), math.floor(maxHealth))
end

function UIController:FlashDamage()
    if not self.HealthBar then return end

    -- Flash red
    local originalColor = self.HealthBar.BackgroundColor3
    self.HealthBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)

    -- Tween back
    local tween = TweenService:Create(self.HealthBar, FLASH_TWEEN_INFO, {
        BackgroundColor3 = originalColor,
    })
    task.delay(0.05, function()
        tween:Play()
    end)
end

-- ============================================
-- INCAPACITATED STATE
-- ============================================

function UIController:SetIncapacitated(isIncapped: boolean, bleedoutTime: number?)
    self.IsIncapacitated = isIncapped

    if self.IncapOverlay then
        self.IncapOverlay.Visible = isIncapped
    end

    if self.ColorCorrection then
        if isIncapped then
            self.ColorCorrection.Enabled = true
            TweenService:Create(self.ColorCorrection, TWEEN_INFO, {
                Saturation = -0.8,
                Brightness = -0.1,
            }):Play()
        else
            TweenService:Create(self.ColorCorrection, TWEEN_INFO, {
                Saturation = 0,
                Brightness = 0,
            }):Play()
            task.delay(0.3, function()
                if not self.IsIncapacitated then
                    self.ColorCorrection.Enabled = false
                end
            end)
        end
    end

    if isIncapped and bleedoutTime then
        self:StartBleedoutTimer(bleedoutTime)
    end
end

function UIController:StartBleedoutTimer(startTime: number)
    local bleedoutText = self.IncapOverlay and self.IncapOverlay:FindFirstChild("BleedoutText")
    if not bleedoutText then return end

    -- Update timer every second
    task.spawn(function()
        local remaining = startTime
        while remaining > 0 and self.IsIncapacitated do
            bleedoutText.Text = string.format("Bleedout: %d", math.floor(remaining))
            task.wait(1)
            remaining -= 1
        end
    end)
end

-- ============================================
-- REVIVAL PROGRESS
-- ============================================

function UIController:ShowReviveProgress(rescuerName: string)
    if not self.ReviveProgress or not self.ReviveText or not self.ReviveBar then return end

    self.ReviveProgress.Visible = true
    self.ReviveText.Text = string.format("Being revived by %s", rescuerName)
    self.ReviveBar.Size = UDim2.new(0, 0, 1, 0)
end

function UIController:UpdateReviveProgress(progress: number)
    if not self.ReviveBar then return end

    local tween = TweenService:Create(self.ReviveBar, TweenInfo.new(0.1), {
        Size = UDim2.new(progress, 0, 1, 0),
    })
    tween:Play()
end

function UIController:HideReviveProgress()
    if self.ReviveProgress then
        self.ReviveProgress.Visible = false
    end
end

-- ============================================
-- TEAMMATE CARDS
-- ============================================

function UIController:CreateTeammateCard(playerData: {name: string, health: number, maxHealth: number, state: string}): Frame
    local card = Instance.new("Frame")
    card.Name = playerData.name
    card.Size = UDim2.new(1, 0, 0, 40)
    card.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    card.BackgroundTransparency = 0.5
    card.BorderSizePixel = 0

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = card

    -- Border for incap/dead state
    local stroke = Instance.new("UIStroke")
    stroke.Name = "StateBorder"
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 1
    stroke.Parent = card

    -- Player name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, -10, 0, 18)
    nameLabel.Position = UDim2.new(0, 5, 0, 2)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextSize = 12
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Text = playerData.name
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = card

    -- Mini health bar background
    local barBg = Instance.new("Frame")
    barBg.Name = "BarBackground"
    barBg.Size = UDim2.new(1, -10, 0, 10)
    barBg.Position = UDim2.new(0, 5, 0, 24)
    barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    barBg.BorderSizePixel = 0
    barBg.Parent = card

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 3)
    barCorner.Parent = barBg

    -- Mini health bar fill
    local healthBar = Instance.new("Frame")
    healthBar.Name = "HealthBar"
    healthBar.Size = UDim2.new(1, 0, 1, 0)
    healthBar.BackgroundColor3 = HEALTH_COLORS.high
    healthBar.BorderSizePixel = 0
    healthBar.Parent = barBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 3)
    fillCorner.Parent = healthBar

    -- Dead icon (hidden by default)
    local deadIcon = Instance.new("TextLabel")
    deadIcon.Name = "DeadIcon"
    deadIcon.Size = UDim2.new(0, 20, 0, 20)
    deadIcon.Position = UDim2.new(1, -25, 0, 2)
    deadIcon.BackgroundTransparency = 1
    deadIcon.TextColor3 = Color3.fromRGB(255, 50, 50)
    deadIcon.TextSize = 16
    deadIcon.Font = Enum.Font.GothamBold
    deadIcon.Text = "💀"
    deadIcon.Visible = false
    deadIcon.Parent = card

    -- Update initial state
    self:UpdateTeammateCard(card, playerData)

    return card
end

function UIController:UpdateTeammateCard(card: Frame, playerData: {name: string, health: number, maxHealth: number, state: string})
    local healthBar = card:FindFirstChild("BarBackground") and card.BarBackground:FindFirstChild("HealthBar")
    local stroke = card:FindFirstChild("StateBorder")
    local deadIcon = card:FindFirstChild("DeadIcon")

    if healthBar then
        local healthPercent = math.clamp(playerData.health / playerData.maxHealth, 0, 1)

        local color
        if healthPercent > 0.5 then
            color = HEALTH_COLORS.high
        elseif healthPercent > 0.25 then
            color = HEALTH_COLORS.medium
        else
            color = HEALTH_COLORS.low
        end

        healthBar.Size = UDim2.new(healthPercent, 0, 1, 0)
        healthBar.BackgroundColor3 = color
    end

    if stroke then
        if playerData.state == "Incapacitated" then
            stroke.Transparency = 0
            stroke.Color = Color3.fromRGB(255, 100, 100)
        elseif playerData.state == "Dead" then
            stroke.Transparency = 0
            stroke.Color = Color3.fromRGB(100, 100, 100)
        else
            stroke.Transparency = 1
        end
    end

    if deadIcon then
        deadIcon.Visible = playerData.state == "Dead"
    end
end

function UIController:UpdateTeammates(teamData: {{name: string, health: number, maxHealth: number, state: string}})
    if not self.TeammateFrame then return end

    -- Clear existing cards for players not in team
    for playerName, card in self.TeammateCards do
        local found = false
        for _, data in teamData do
            if data.name == playerName then
                found = true
                break
            end
        end
        if not found then
            card:Destroy()
            self.TeammateCards[playerName] = nil
        end
    end

    -- Update or create cards
    for i, data in teamData do
        if data.name == player.Name then continue end  -- Skip local player

        local card = self.TeammateCards[data.name]
        if card then
            self:UpdateTeammateCard(card, data)
        else
            card = self:CreateTeammateCard(data)
            card.LayoutOrder = i
            card.Parent = self.TeammateFrame
            self.TeammateCards[data.name] = card
        end
    end
end

-- ============================================
-- GAME STATE EVENTS
-- ============================================

function UIController:ConnectGameStateEvents()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")

    -- Listen for team health updates
    local gameStateRemote = remotes:WaitForChild("GameState")
    table.insert(self._connections, gameStateRemote.OnClientEvent:Connect(function(stateType, data)
        if stateType == "TeamHealth" then
            self:UpdateTeammates(data)
        elseif stateType == "Incapacitated" then
            self:SetIncapacitated(true, data.bleedoutTime)
        elseif stateType == "Revived" then
            self:SetIncapacitated(false)
            self:HideReviveProgress()
        elseif stateType == "BeingRevived" then
            self:ShowReviveProgress(data.rescuerName)
        elseif stateType == "ReviveProgress" then
            self:UpdateReviveProgress(data.progress)
        elseif stateType == "ReviveCancelled" then
            self:HideReviveProgress()
        end
    end))
end

-- ============================================
-- CLEANUP
-- ============================================

function UIController:Destroy()
    for _, connection in self._connections do
        connection:Disconnect()
    end
    table.clear(self._connections)

    if self.ScreenGui then
        self.ScreenGui:Destroy()
    end

    if self.ColorCorrection then
        self.ColorCorrection:Destroy()
    end

    table.clear(self.TeammateCards)
end

return UIController
