--!strict
--[[
    Entity Factory
    Creates different types of enemy models
]]

local EntityFactory = {}

function EntityFactory.createHunter(): Model
    -- Create basic humanoid model
    local model = Instance.new("Model")
    model.Name = "Hunter"
    
    -- Create parts
    local rootPart = Instance.new("Part")
    rootPart.Name = "HumanoidRootPart"
    rootPart.Size = Vector3.new(2, 2, 1)
    rootPart.Material = Enum.Material.Neon
    rootPart.BrickColor = BrickColor.new("Deep orange")
    rootPart.Transparency = 0.2
    rootPart.Parent = model
    
    -- Torso
    local torso = Instance.new("Part")
    torso.Name = "Torso"
    torso.Size = Vector3.new(2, 2, 1)
    torso.Material = Enum.Material.Plastic
    torso.BrickColor = BrickColor.new("Deep orange")
    torso.Parent = model
    
    -- Head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(2, 1, 1)
    head.Material = Enum.Material.Plastic
    head.BrickColor = BrickColor.new("Deep orange")
    head.Parent = model
    
    -- Arms
    local leftArm = Instance.new("Part")
    leftArm.Name = "Left Arm"
    leftArm.Size = Vector3.new(1, 2, 1)
    leftArm.Material = Enum.Material.Plastic
    leftArm.BrickColor = BrickColor.new("Deep orange")
    leftArm.Parent = model
    
    local rightArm = Instance.new("Part")
    rightArm.Name = "Right Arm"
    rightArm.Size = Vector3.new(1, 2, 1)
    rightArm.Material = Enum.Material.Plastic
    rightArm.BrickColor = BrickColor.new("Deep orange")
    rightArm.Parent = model
    
    -- Legs
    local leftLeg = Instance.new("Part")
    leftLeg.Name = "Left Leg"
    leftLeg.Size = Vector3.new(1, 2, 1)
    leftLeg.Material = Enum.Material.Plastic
    leftLeg.BrickColor = BrickColor.new("Deep orange")
    leftLeg.Parent = model
    
    local rightLeg = Instance.new("Part")
    rightLeg.Name = "Right Leg"
    rightLeg.Size = Vector3.new(1, 2, 1)
    rightLeg.Material = Enum.Material.Plastic
    rightLeg.BrickColor = BrickColor.new("Deep orange")
    rightLeg.Parent = model
    
    -- Assemble model
    local humanoid = Instance.new("Humanoid")
    humanoid.Health = 250
    humanoid.MaxHealth = 250
    humanoid.WalkSpeed = 20
    humanoid.JumpPower = 50
    humanoid.Parent = model
    
    -- Position parts
    rootPart.CFrame = CFrame.new(0, 5, 0)
    torso.CFrame = rootPart.CFrame * CFrame.new(0, 0, 0)
    head.CFrame = torso.CFrame * CFrame.new(0, 1.5, 0)
    leftArm.CFrame = torso.CFrame * CFrame.new(-1.5, 0.5, 0)
    rightArm.CFrame = torso.CFrame * CFrame.new(1.5, 0.5, 0)
    leftLeg.CFrame = torso.CFrame * CFrame.new(-0.5, -2, 0)
    rightLeg.CFrame = torso.CFrame * CFrame.new(0.5, -2, 0)
    
    -- Weld parts together
    local welds = {
        {rootPart, torso},
        {torso, head},
        {torso, leftArm},
        {torso, rightArm},
        {torso, leftLeg},
        {torso, rightLeg},
    }
    
    for _, pair in welds do
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = pair[1]
        weld.Part1 = pair[2]
        weld.Parent = pair[1]
    end
    
    -- Add face for visual identification
    local face = Instance.new("Decal")
    face.Name = "face"
    face.Texture = "rbxassetid://146727902"  -- Angry face
    face.Parent = head
    
    print("[EntityFactory] Created Hunter model")
    return model
end

function EntityFactory.createCommon(): Model
    -- Create basic zombie model
    local model = Instance.new("Model")
    model.Name = "CommonInfected"
    
    -- Create parts
    local rootPart = Instance.new("Part")
    rootPart.Name = "HumanoidRootPart"
    rootPart.Size = Vector3.new(2, 2, 1)
    rootPart.Material = Enum.Material.Plastic
    rootPart.BrickColor = BrickColor.new("Dark stone grey")
    rootPart.Transparency = 1
    rootPart.Parent = model
    
    -- Torso
    local torso = Instance.new("Part")
    torso.Name = "Torso"
    torso.Size = Vector3.new(2, 2, 1)
    torso.Material = Enum.Material.Plastic
    torso.BrickColor = BrickColor.new("Dark stone grey")
    torso.Parent = model
    
    -- Head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(2, 1, 1)
    head.Material = Enum.Material.Plastic
    head.BrickColor = BrickColor.new("Dark stone grey")
    torso.Parent = model
    
    -- Arms
    local leftArm = Instance.new("Part")
    leftArm.Name = "Left Arm"
    leftArm.Size = Vector3.new(1, 2, 1)
    leftArm.Material = Enum.Material.Plastic
    leftArm.BrickColor = BrickColor.new("Dark stone grey")
    leftArm.Parent = model
    
    local rightArm = Instance.new("Part")
    rightArm.Name = "Right Arm"
    rightArm.Size = Vector3.new(1, 2, 1)
    rightArm.Material = Enum.Material.Plastic
    rightArm.BrickColor = BrickColor.new("Dark stone grey")
    rightArm.Parent = model
    
    -- Legs
    local leftLeg = Instance.new("Part")
    leftLeg.Name = "Left Leg"
    leftLeg.Size = Vector3.new(1, 2, 1)
    leftLeg.Material = Enum.Material.Plastic
    leftLeg.BrickColor = BrickColor.new("Dark stone grey")
    leftLeg.Parent = model
    
    local rightLeg = Instance.new("Part")
    rightLeg.Name = "Right Leg"
    rightLeg.Size = Vector3.new(1, 2, 1)
    rightLeg.Material = Enum.Material.Plastic
    rightLeg.BrickColor = BrickColor.new("Dark stone grey")
    rightLeg.Parent = model
    
    -- Humanoid
    local humanoid = Instance.new("Humanoid")
    humanoid.Health = 50
    humanoid.MaxHealth = 50
    humanoid.WalkSpeed = 14
    humanoid.JumpPower = 0
    humanoid.Parent = model
    
    -- Position parts
    rootPart.CFrame = CFrame.new(0, 5, 0)
    torso.CFrame = rootPart.CFrame * CFrame.new(0, 0, 0)
    head.CFrame = torso.CFrame * CFrame.new(0, 1.5, 0)
    leftArm.CFrame = torso.CFrame * CFrame.new(-1.5, 0.5, 0)
    rightArm.CFrame = torso.CFrame * CFrame.new(1.5, 0.5, 0)
    leftLeg.CFrame = torso.CFrame * CFrame.new(-0.5, -2, 0)
    rightLeg.CFrame = torso.CFrame * CFrame.new(0.5, -2, 0)
    
    -- Weld parts
    local welds = {
        {rootPart, torso},
        {torso, head},
        {torso, leftArm},
        {torso, rightArm},
        {torso, leftLeg},
        {torso, rightLeg},
    }
    
    for _, pair in welds do
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = pair[1]
        weld.Part1 = pair[2]
        weld.Parent = pair[1]
    end
    
    return model
end

return EntityFactory
