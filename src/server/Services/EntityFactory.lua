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
	model.PrimaryPart = rootPart

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
		{ rootPart, torso },
		{ torso, head },
		{ torso, leftArm },
		{ torso, rightArm },
		{ torso, leftLeg },
		{ torso, rightLeg },
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
	face.Texture = "rbxassetid://146727902" -- Angry face
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
	model.PrimaryPart = rootPart

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
	head.Parent = model

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
		{ rootPart, torso },
		{ torso, head },
		{ torso, leftArm },
		{ torso, rightArm },
		{ torso, leftLeg },
		{ torso, rightLeg },
	}

	for _, pair in welds do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pair[1]
		weld.Part1 = pair[2]
		weld.Parent = pair[1]
	end

	return model
end

function EntityFactory.createTank(): Model
	-- Create massive humanoid model for Tank
	local model = Instance.new("Model")
	model.Name = "Tank"

	-- Create parts (larger than normal)
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(4, 4, 2)
	rootPart.Material = Enum.Material.Plastic
	rootPart.BrickColor = BrickColor.new("Dark taupe")
	rootPart.Transparency = 1
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	-- Torso (massive)
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(5, 4, 3)
	torso.Material = Enum.Material.Plastic
	torso.BrickColor = BrickColor.new("Dark taupe")
	torso.Parent = model

	-- Head (small relative to body)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2.5, 1.5, 1.5)
	head.Material = Enum.Material.Plastic
	head.BrickColor = BrickColor.new("Dark taupe")
	head.Parent = model

	-- Arms (huge muscular arms)
	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(2.5, 5, 2)
	leftArm.Material = Enum.Material.Plastic
	leftArm.BrickColor = BrickColor.new("Dark taupe")
	leftArm.Parent = model

	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(2.5, 5, 2)
	rightArm.Material = Enum.Material.Plastic
	rightArm.BrickColor = BrickColor.new("Dark taupe")
	rightArm.Parent = model

	-- Legs (shorter but thick)
	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(2, 3, 2)
	leftLeg.Material = Enum.Material.Plastic
	leftLeg.BrickColor = BrickColor.new("Dark taupe")
	leftLeg.Parent = model

	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(2, 3, 2)
	rightLeg.Material = Enum.Material.Plastic
	rightLeg.BrickColor = BrickColor.new("Dark taupe")
	rightLeg.Parent = model

	-- Humanoid with Tank stats
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 6000
	humanoid.MaxHealth = 6000
	humanoid.WalkSpeed = 12
	humanoid.JumpPower = 30
	humanoid.Parent = model

	-- Position parts
	rootPart.CFrame = CFrame.new(0, 6, 0)
	torso.CFrame = rootPart.CFrame * CFrame.new(0, 0, 0)
	head.CFrame = torso.CFrame * CFrame.new(0, 2.5, 0)
	leftArm.CFrame = torso.CFrame * CFrame.new(-3.5, 0, 0)
	rightArm.CFrame = torso.CFrame * CFrame.new(3.5, 0, 0)
	leftLeg.CFrame = torso.CFrame * CFrame.new(-1, -3.5, 0)
	rightLeg.CFrame = torso.CFrame * CFrame.new(1, -3.5, 0)

	-- Weld parts
	local welds = {
		{ rootPart, torso },
		{ torso, head },
		{ torso, leftArm },
		{ torso, rightArm },
		{ torso, leftLeg },
		{ torso, rightLeg },
	}

	for _, pair in welds do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pair[1]
		weld.Part1 = pair[2]
		weld.Parent = pair[1]
	end

	-- Add angry face
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxassetid://146727902" -- Angry face
	face.Parent = head

	print("[EntityFactory] Created Tank model")
	return model
end

function EntityFactory.createSmoker(): Model
	-- Create tall, thin humanoid model for Smoker
	local model = Instance.new("Model")
	model.Name = "Smoker"

	-- Create parts (tall and gaunt)
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Material = Enum.Material.Plastic
	rootPart.BrickColor = BrickColor.new("Dark stone grey")
	rootPart.Transparency = 1
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	-- Torso (elongated)
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2.5, 1)
	torso.Material = Enum.Material.Plastic
	torso.BrickColor = BrickColor.new("Dark stone grey")
	torso.Parent = model

	-- Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Material = Enum.Material.Plastic
	head.BrickColor = BrickColor.new("Dark stone grey")
	head.Parent = model

	-- Arms (long)
	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(1, 2.5, 1)
	leftArm.Material = Enum.Material.Plastic
	leftArm.BrickColor = BrickColor.new("Dark stone grey")
	leftArm.Parent = model

	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(1, 2.5, 1)
	rightArm.Material = Enum.Material.Plastic
	rightArm.BrickColor = BrickColor.new("Dark stone grey")
	rightArm.Parent = model

	-- Legs
	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(1, 2.5, 1)
	leftLeg.Material = Enum.Material.Plastic
	leftLeg.BrickColor = BrickColor.new("Dark stone grey")
	leftLeg.Parent = model

	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(1, 2.5, 1)
	rightLeg.Material = Enum.Material.Plastic
	rightLeg.BrickColor = BrickColor.new("Dark stone grey")
	rightLeg.Parent = model

	-- Humanoid with Smoker stats
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 250
	humanoid.MaxHealth = 250
	humanoid.WalkSpeed = 12
	humanoid.JumpPower = 30
	humanoid.Parent = model

	-- Position parts
	rootPart.CFrame = CFrame.new(0, 5, 0)
	torso.CFrame = rootPart.CFrame * CFrame.new(0, 0, 0)
	head.CFrame = torso.CFrame * CFrame.new(0, 1.75, 0)
	leftArm.CFrame = torso.CFrame * CFrame.new(-1.5, 0.5, 0)
	rightArm.CFrame = torso.CFrame * CFrame.new(1.5, 0.5, 0)
	leftLeg.CFrame = torso.CFrame * CFrame.new(-0.5, -2.5, 0)
	rightLeg.CFrame = torso.CFrame * CFrame.new(0.5, -2.5, 0)

	-- Weld parts
	local welds = {
		{ rootPart, torso },
		{ torso, head },
		{ torso, leftArm },
		{ torso, rightArm },
		{ torso, leftLeg },
		{ torso, rightLeg },
	}

	for _, pair in welds do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pair[1]
		weld.Part1 = pair[2]
		weld.Parent = pair[1]
	end

	-- Add smoke particles
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "SmokeEffect"
	smoke.Texture = "rbxassetid://243660364"
	smoke.Color = ColorSequence.new(Color3.fromRGB(80, 80, 80))
	smoke.Size = NumberSequence.new(1, 3)
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.Lifetime = NumberRange.new(1, 2)
	smoke.Rate = 10
	smoke.Speed = NumberRange.new(1, 3)
	smoke.SpreadAngle = Vector2.new(30, 30)
	smoke.Parent = torso

	print("[EntityFactory] Created Smoker model")
	return model
end

function EntityFactory.createBoomer(): Model
	-- Create fat, bloated humanoid model for Boomer
	local model = Instance.new("Model")
	model.Name = "Boomer"

	-- Create parts (bloated proportions)
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(3, 2, 2)
	rootPart.Material = Enum.Material.Plastic
	rootPart.BrickColor = BrickColor.new("Bright green")
	rootPart.Transparency = 1
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	-- Torso (bloated belly)
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(3.5, 2.5, 2.5)
	torso.Material = Enum.Material.SmoothPlastic
	torso.BrickColor = BrickColor.new("Bright green")
	torso.Parent = model

	-- Head (small)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.5, 1, 1)
	head.Material = Enum.Material.SmoothPlastic
	head.BrickColor = BrickColor.new("Bright green")
	head.Parent = model

	-- Arms (short and stubby)
	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(1.2, 1.5, 1.2)
	leftArm.Material = Enum.Material.SmoothPlastic
	leftArm.BrickColor = BrickColor.new("Bright green")
	leftArm.Parent = model

	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(1.2, 1.5, 1.2)
	rightArm.Material = Enum.Material.SmoothPlastic
	rightArm.BrickColor = BrickColor.new("Bright green")
	rightArm.Parent = model

	-- Legs (short)
	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(1.2, 1.5, 1.2)
	leftLeg.Material = Enum.Material.SmoothPlastic
	leftLeg.BrickColor = BrickColor.new("Bright green")
	leftLeg.Parent = model

	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(1.2, 1.5, 1.2)
	rightLeg.Material = Enum.Material.SmoothPlastic
	rightLeg.BrickColor = BrickColor.new("Bright green")
	rightLeg.Parent = model

	-- Humanoid with Boomer stats
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 50
	humanoid.MaxHealth = 50
	humanoid.WalkSpeed = 8
	humanoid.JumpPower = 0
	humanoid.Parent = model

	-- Position parts
	rootPart.CFrame = CFrame.new(0, 5, 0)
	torso.CFrame = rootPart.CFrame * CFrame.new(0, 0, 0)
	head.CFrame = torso.CFrame * CFrame.new(0, 1.75, 0)
	leftArm.CFrame = torso.CFrame * CFrame.new(-2.3, 0, 0)
	rightArm.CFrame = torso.CFrame * CFrame.new(2.3, 0, 0)
	leftLeg.CFrame = torso.CFrame * CFrame.new(-0.8, -2, 0)
	rightLeg.CFrame = torso.CFrame * CFrame.new(0.8, -2, 0)

	-- Weld parts
	local welds = {
		{ rootPart, torso },
		{ torso, head },
		{ torso, leftArm },
		{ torso, rightArm },
		{ torso, leftLeg },
		{ torso, rightLeg },
	}

	for _, pair in welds do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pair[1]
		weld.Part1 = pair[2]
		weld.Parent = pair[1]
	end

	-- Add bile drip particles
	local bileDrip = Instance.new("ParticleEmitter")
	bileDrip.Name = "BileDrip"
	bileDrip.Color = ColorSequence.new(Color3.fromRGB(120, 180, 50))
	bileDrip.Size = NumberSequence.new(0.3, 0.1)
	bileDrip.Transparency = NumberSequence.new(0.2, 0.8)
	bileDrip.Lifetime = NumberRange.new(0.5, 1)
	bileDrip.Rate = 5
	bileDrip.Speed = NumberRange.new(1, 2)
	bileDrip.SpreadAngle = Vector2.new(10, 10)
	bileDrip.Acceleration = Vector3.new(0, -10, 0)
	bileDrip.Parent = head

	print("[EntityFactory] Created Boomer model")
	return model
end

function EntityFactory.createWitch(): Model
	-- Create thin, pale humanoid model for Witch
	local model = Instance.new("Model")
	model.Name = "Witch"

	-- Create parts (thin/gaunt proportions)
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Material = Enum.Material.Plastic
	rootPart.BrickColor = BrickColor.new("Pastel brown")
	rootPart.Transparency = 1
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	-- Torso (thin)
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(1.5, 2, 0.8)
	torso.Material = Enum.Material.SmoothPlastic
	torso.BrickColor = BrickColor.new("Pastel brown")
	torso.Parent = model

	-- Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.8, 1.2, 1)
	head.Material = Enum.Material.SmoothPlastic
	head.BrickColor = BrickColor.new("Pastel brown")
	head.Parent = model

	-- Arms (long and thin)
	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(0.6, 2.5, 0.6)
	leftArm.Material = Enum.Material.SmoothPlastic
	leftArm.BrickColor = BrickColor.new("Pastel brown")
	leftArm.Parent = model

	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(0.6, 2.5, 0.6)
	rightArm.Material = Enum.Material.SmoothPlastic
	rightArm.BrickColor = BrickColor.new("Pastel brown")
	rightArm.Parent = model

	-- Legs (thin)
	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(0.7, 2, 0.7)
	leftLeg.Material = Enum.Material.SmoothPlastic
	leftLeg.BrickColor = BrickColor.new("Pastel brown")
	leftLeg.Parent = model

	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(0.7, 2, 0.7)
	rightLeg.Material = Enum.Material.SmoothPlastic
	rightLeg.BrickColor = BrickColor.new("Pastel brown")
	rightLeg.Parent = model

	-- Humanoid with Witch stats
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 1000
	humanoid.MaxHealth = 1000
	humanoid.WalkSpeed = 0 -- Stationary by default
	humanoid.JumpPower = 0
	humanoid.Parent = model

	-- Position parts
	rootPart.CFrame = CFrame.new(0, 5, 0)
	torso.CFrame = rootPart.CFrame * CFrame.new(0, 0, 0)
	head.CFrame = torso.CFrame * CFrame.new(0, 1.5, 0)
	leftArm.CFrame = torso.CFrame * CFrame.new(-1.1, 0.2, 0)
	rightArm.CFrame = torso.CFrame * CFrame.new(1.1, 0.2, 0)
	leftLeg.CFrame = torso.CFrame * CFrame.new(-0.4, -2, 0)
	rightLeg.CFrame = torso.CFrame * CFrame.new(0.4, -2, 0)

	-- Weld parts
	local welds = {
		{ rootPart, torso },
		{ torso, head },
		{ torso, leftArm },
		{ torso, rightArm },
		{ torso, leftLeg },
		{ torso, rightLeg },
	}

	for _, pair in welds do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pair[1]
		weld.Part1 = pair[2]
		weld.Parent = pair[1]
	end

	-- Add crying face decal
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxassetid://3264361900" -- Sad/crying face
	face.Parent = head

	print("[EntityFactory] Created Witch model")
	return model
end

function EntityFactory.createCharger(): Model
	-- Create bulky, asymmetric humanoid model for Charger
	local model = Instance.new("Model")
	model.Name = "Charger"

	-- Create parts (bulky with one massive arm)
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(3, 3, 2)
	rootPart.Material = Enum.Material.Plastic
	rootPart.BrickColor = BrickColor.new("Dark stone grey")
	rootPart.Transparency = 1
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	-- Torso (bulky)
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(3.5, 3, 2)
	torso.Material = Enum.Material.SmoothPlastic
	torso.BrickColor = BrickColor.new("Dark stone grey")
	torso.Parent = model

	-- Head (hunched forward)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1.2, 1.2)
	head.Material = Enum.Material.SmoothPlastic
	head.BrickColor = BrickColor.new("Dark stone grey")
	head.Parent = model

	-- Right Arm (MASSIVE charging arm)
	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(2.5, 4, 2)
	rightArm.Material = Enum.Material.SmoothPlastic
	rightArm.BrickColor = BrickColor.new("Medium stone grey")
	rightArm.Parent = model

	-- Left Arm (withered/small)
	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(0.5, 1.5, 0.5)
	leftArm.Material = Enum.Material.SmoothPlastic
	leftArm.BrickColor = BrickColor.new("Dark stone grey")
	leftArm.Parent = model

	-- Legs (thick)
	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(1.5, 2.5, 1.5)
	leftLeg.Material = Enum.Material.SmoothPlastic
	leftLeg.BrickColor = BrickColor.new("Dark stone grey")
	leftLeg.Parent = model

	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(1.5, 2.5, 1.5)
	rightLeg.Material = Enum.Material.SmoothPlastic
	rightLeg.BrickColor = BrickColor.new("Dark stone grey")
	rightLeg.Parent = model

	-- Humanoid with Charger stats
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 600
	humanoid.MaxHealth = 600
	humanoid.WalkSpeed = 14
	humanoid.JumpPower = 30
	humanoid.Parent = model

	-- Position parts
	rootPart.CFrame = CFrame.new(0, 5, 0)
	torso.CFrame = rootPart.CFrame * CFrame.new(0, 0, 0)
	head.CFrame = torso.CFrame * CFrame.new(0, 2, 0.5) -- Hunched forward
	rightArm.CFrame = torso.CFrame * CFrame.new(2.8, 0, 0) -- Massive arm
	leftArm.CFrame = torso.CFrame * CFrame.new(-2, 0.5, 0) -- Withered arm
	leftLeg.CFrame = torso.CFrame * CFrame.new(-0.8, -2.7, 0)
	rightLeg.CFrame = torso.CFrame * CFrame.new(0.8, -2.7, 0)

	-- Weld parts
	local welds = {
		{ rootPart, torso },
		{ torso, head },
		{ torso, leftArm },
		{ torso, rightArm },
		{ torso, leftLeg },
		{ torso, rightLeg },
	}

	for _, pair in welds do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pair[1]
		weld.Part1 = pair[2]
		weld.Parent = pair[1]
	end

	-- Add angry face
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxassetid://146727902" -- Angry face
	face.Parent = head

	print("[EntityFactory] Created Charger model")
	return model
end

function EntityFactory.createSpitter(): Model
	-- Create thin, elongated humanoid model for Spitter
	local model = Instance.new("Model")
	model.Name = "Spitter"

	-- Create parts (thin with elongated neck)
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Material = Enum.Material.Plastic
	rootPart.BrickColor = BrickColor.new("Lime green")
	rootPart.Transparency = 1
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	-- Torso (thin)
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(1.6, 2.2, 0.7)
	torso.Material = Enum.Material.SmoothPlastic
	torso.BrickColor = BrickColor.new("Lime green")
	torso.Parent = model

	-- Head (elongated)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.8, 1.6, 1.2)
	head.Material = Enum.Material.SmoothPlastic
	head.BrickColor = BrickColor.new("Lime green")
	head.Parent = model

	-- Arms (thin)
	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(0.6, 2, 0.6)
	leftArm.Material = Enum.Material.SmoothPlastic
	leftArm.BrickColor = BrickColor.new("Lime green")
	leftArm.Parent = model

	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(0.6, 2, 0.6)
	rightArm.Material = Enum.Material.SmoothPlastic
	rightArm.BrickColor = BrickColor.new("Lime green")
	rightArm.Parent = model

	-- Legs (thin)
	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(0.6, 2, 0.6)
	leftLeg.Material = Enum.Material.SmoothPlastic
	leftLeg.BrickColor = BrickColor.new("Lime green")
	leftLeg.Parent = model

	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(0.6, 2, 0.6)
	rightLeg.Material = Enum.Material.SmoothPlastic
	rightLeg.BrickColor = BrickColor.new("Lime green")
	rightLeg.Parent = model

	-- Humanoid with Spitter stats
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.MaxHealth = 100
	humanoid.WalkSpeed = 12
	humanoid.JumpPower = 35
	humanoid.Parent = model

	-- Position parts
	rootPart.CFrame = CFrame.new(0, 5, 0)
	torso.CFrame = rootPart.CFrame * CFrame.new(0, 0, 0)
	head.CFrame = torso.CFrame * CFrame.new(0, 1.9, 0)
	leftArm.CFrame = torso.CFrame * CFrame.new(-1.1, 0.3, 0)
	rightArm.CFrame = torso.CFrame * CFrame.new(1.1, 0.3, 0)
	leftLeg.CFrame = torso.CFrame * CFrame.new(-0.4, -2.1, 0)
	rightLeg.CFrame = torso.CFrame * CFrame.new(0.4, -2.1, 0)

	-- Weld parts
	local welds = {
		{ rootPart, torso },
		{ torso, head },
		{ torso, leftArm },
		{ torso, rightArm },
		{ torso, leftLeg },
		{ torso, rightLeg },
	}

	for _, pair in welds do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pair[1]
		weld.Part1 = pair[2]
		weld.Parent = pair[1]
	end

	-- Add acid drip particles
	local acidDrip = Instance.new("ParticleEmitter")
	acidDrip.Name = "AcidDrip"
	acidDrip.Color = ColorSequence.new(Color3.fromRGB(0, 255, 0))
	acidDrip.Size = NumberSequence.new(0.4, 0.1)
	acidDrip.Transparency = NumberSequence.new(0.3, 0.8)
	acidDrip.Lifetime = NumberRange.new(0.5, 1)
	acidDrip.Rate = 8
	acidDrip.Speed = NumberRange.new(1, 3)
	acidDrip.SpreadAngle = Vector2.new(15, 15)
	acidDrip.Acceleration = Vector3.new(0, -15, 0)
	acidDrip.Parent = head

	print("[EntityFactory] Created Spitter model")
	return model
end

return EntityFactory
