# Luau Cheatsheet

## Table of Contents
1. [Variables and Types](#variables-and-types)
2. [Functions](#functions)
3. [Tables](#tables)
4. [Control Flow](#control-flow)
5. [Type Annotations](#type-annotations)
6. [Strict Mode](#strict-mode)
7. [Native Code Generation](#native-code-generation)
8. [Metatables](#metatables)
9. [Coroutines](#coroutines)

---

## Variables and Types

```lua
-- Local variables (always use local)
local name = "Player"
local health = 100
local isAlive = true
local position = Vector3.new(0, 5, 0)

-- Constants (convention: UPPER_CASE)
local MAX_HEALTH = 100
local SPAWN_INTERVAL = 30

-- Nil check
if value ~= nil then
    -- exists
end

-- Type coercion
local str = tostring(42)      -- "42"
local num = tonumber("42")    -- 42
```

## Functions

```lua
-- Basic function
local function damage(target, amount)
    target.Health = target.Health - amount
end

-- With return
local function getDistance(a, b)
    return (a.Position - b.Position).Magnitude
end

-- Multiple returns
local function getStats()
    return 100, 50, "Alive"
end
local health, armor, status = getStats()

-- Variadic
local function sum(...)
    local total = 0
    for _, v in {...} do
        total = total + v
    end
    return total
end

-- Anonymous/lambda
local onDeath = function(player)
    print(player.Name .. " died")
end

-- Method syntax (self)
function Enemy:TakeDamage(amount)
    self.Health = self.Health - amount
end
```

## Tables

```lua
-- Array (1-indexed!)
local items = {"Medkit", "Ammo", "Grenade"}
print(items[1])  -- "Medkit"
table.insert(items, "Pistol")
table.remove(items, 2)

-- Dictionary
local player = {
    name = "Survivor",
    health = 100,
    weapons = {"Shotgun", "Pistol"}
}
player.health = 80
player["name"] = "NewName"

-- Mixed
local config = {
    maxPlayers = 4,
    difficulty = "Normal",
    [1] = "First item"
}

-- Iteration
for i, item in ipairs(items) do      -- Array (ordered)
    print(i, item)
end

for key, value in pairs(player) do   -- Dictionary (unordered)
    print(key, value)
end

-- Generalized iteration (Luau)
for i, v in items do  -- No ipairs needed
    print(i, v)
end

-- Table operations
local count = #items                  -- Length
table.find(items, "Medkit")          -- Returns index or nil
table.clear(items)                    -- Empty table
table.clone(items)                    -- Shallow copy
table.freeze(config)                  -- Make immutable
```

## Control Flow

```lua
-- If/elseif/else
if health <= 0 then
    state = "Dead"
elseif health < 30 then
    state = "Critical"
else
    state = "Alive"
end

-- Ternary equivalent
local status = health > 0 and "Alive" or "Dead"

-- While
while isRunning do
    update()
    task.wait()
end

-- Repeat until
repeat
    attemptConnection()
until connected

-- Numeric for
for i = 1, 10 do
    print(i)
end

for i = 10, 1, -1 do  -- Countdown
    print(i)
end

-- Break and continue
for _, enemy in enemies do
    if enemy.IsDead then continue end
    if foundTarget then break end
    enemy:Update()
end
```

## Type Annotations

```lua
-- Basic types
local name: string = "Player"
local health: number = 100
local alive: boolean = true

-- Function signatures
local function damage(target: Humanoid, amount: number): number
    target.Health -= amount
    return target.Health
end

-- Optional parameters
local function spawn(position: Vector3, delay: number?)
    if delay then task.wait(delay) end
    -- spawn logic
end

-- Union types
local id: string | number = "player_1"

-- Type aliases
type State = "Idle" | "Chase" | "Attack" | "Dead"
local currentState: State = "Idle"

-- Table types
type PlayerData = {
    name: string,
    health: number,
    inventory: {string}
}

-- Export types (for ModuleScripts)
export type EnemyConfig = {
    health: number,
    speed: number,
    damage: number
}

-- Generic types
type Array<T> = {T}
local numbers: Array<number> = {1, 2, 3}
```

## Strict Mode

```lua
--!strict
-- Enables full type checking, catches more errors at edit-time

-- All variables must be typed or inferable
local count = 0  -- Inferred as number

-- Function parameters must be typed
local function process(data: {string}): number
    return #data
end

-- Catches type mismatches
local x: string = 42  -- Error!
```

## Native Code Generation

```lua
-- Mark performance-critical functions
--!native

-- Or per-function
local function calculatePath(start: Vector3, goal: Vector3)
    -- Complex math benefits from native compilation
    @native
    local function innerLoop()
        -- Hot code path
    end
end

-- Best for:
-- - Math-heavy operations
-- - Tight loops
-- - Vector calculations
-- - AI update loops
```

## Metatables

```lua
-- Class pattern
local Enemy = {}
Enemy.__index = Enemy

function Enemy.new(name: string)
    local self = setmetatable({}, Enemy)
    self.Name = name
    self.Health = 100
    return self
end

function Enemy:TakeDamage(amount: number)
    self.Health -= amount
    if self.Health <= 0 then
        self:Die()
    end
end

function Enemy:Die()
    print(self.Name .. " died")
end

-- Usage
local zombie = Enemy.new("Zombie")
zombie:TakeDamage(50)

-- Operator overloading
local Vector = {}
Vector.__index = Vector

function Vector.__add(a, b)
    return Vector.new(a.x + b.x, a.y + b.y)
end

function Vector.__eq(a, b)
    return a.x == b.x and a.y == b.y
end

-- __newindex for property interception
local Observed = {}
Observed.__newindex = function(t, k, v)
    print("Setting", k, "to", v)
    rawset(t, k, v)
end
```

## Coroutines

```lua
-- Task library (preferred in Roblox)
task.spawn(function()
    -- Runs immediately in new thread
end)

task.defer(function()
    -- Runs after current thread yields
end)

task.delay(5, function()
    -- Runs after 5 seconds
end)

task.wait(1)  -- Yields for 1 second

-- Cancel spawned tasks
local thread = task.spawn(function()
    while true do
        task.wait(1)
    end
end)
task.cancel(thread)

-- Raw coroutines (less common)
local co = coroutine.create(function()
    print("Started")
    coroutine.yield()
    print("Resumed")
end)

coroutine.resume(co)  -- "Started"
coroutine.resume(co)  -- "Resumed"
```

## Common Patterns

```lua
-- Debounce
local debounce = {}
local function onTouch(part)
    if debounce[part] then return end
    debounce[part] = true
    -- Handle touch
    task.delay(1, function()
        debounce[part] = nil
    end)
end

-- Event connection cleanup
local connections = {}
table.insert(connections, event:Connect(handler))

-- Cleanup all
for _, conn in connections do
    conn:Disconnect()
end
table.clear(connections)

-- Safe instance access
local humanoid = character:FindFirstChildOfClass("Humanoid")
if humanoid then
    humanoid.Health = 100
end

-- WaitForChild with timeout
local part = parent:WaitForChild("Part", 5)  -- 5 second timeout
if part then
    -- Found
end
```
