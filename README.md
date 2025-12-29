# L4D2 Roblox Horror Game

A Left 4 Dead 2-inspired cooperative horror/survival game built for Roblox.

## Features

- **AI Director**: Dynamic pacing system that creates tension-release cycles
- **4-Player Co-op**: Team-based survival with incapacitation and revival mechanics
- **Special Infected**: Hunter, Smoker, Boomer, Tank, Witch, Charger, Spitter
- **Procedural Generation**: DOORS-style room generation for replayability
- **Horror Atmosphere**: Dynamic lighting, ambient audio, and tension systems

## Quick Start

### Prerequisites

1. **Rokit** (Roblox toolchain manager)
   ```bash
   # Windows (PowerShell)
   irm https://github.com/rojo-rbx/rokit/releases/latest/download/rokit-windows-x86_64.zip -OutFile rokit.zip
   Expand-Archive rokit.zip -DestinationPath rokit
   ./rokit/rokit self-install

   # macOS/Linux
   curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
   ```

2. **Roblox Studio** with Rojo plugin installed

### Setup

```bash
# Clone the repository
git clone <your-repo-url>
cd l4d2-roblox-game

# Install tools (defined in rokit.toml)
rokit install

# Install Wally packages
wally install

# Start Rojo server
rojo serve
```

### Connect to Studio

1. Open Roblox Studio
2. Open the Rojo plugin panel
3. Click "Connect" to sync with the running Rojo server

## Project Structure

```
l4d2-roblox-game/
├── src/
│   ├── server/              # Server-side code
│   │   ├── Server.server.lua
│   │   └── Services/
│   │       ├── GameService.lua
│   │       ├── DirectorService.lua
│   │       ├── EntityService.lua
│   │       └── PlayerService.lua
│   ├── client/              # Client-side code
│   │   ├── Client.client.lua
│   │   └── Controllers/
│   └── shared/              # Shared code
│       ├── Constants/
│       └── Types/
├── docs/                    # Documentation
├── assets/                  # Game assets
├── default.project.json     # Rojo configuration
├── wally.toml              # Package dependencies
├── selene.toml             # Linter config
├── stylua.toml             # Formatter config
└── rokit.toml              # Tool versions
```

## Development with AI IDEs

This project includes configuration files for AI-powered IDEs:

| IDE | Config File | Description |
|-----|-------------|-------------|
| Cursor | `.cursorrules` | Project context and code standards |
| Windsurf | `.windsurf/rules.md` | AI assistant rules |
| Claude Code | `CLAUDE.md` | Comprehensive project context |
| VS Code | `.vscode/extensions.json` | Recommended extensions |

### Using AI Assistants

When working with AI coding assistants, they will automatically pick up:

1. **Architecture patterns** - Single-script NPC management, service singletons
2. **Code standards** - Type annotations, naming conventions
3. **Performance requirements** - Update throttling, collision groups
4. **Game mechanics** - AI Director, incap system, special infected

## Key Systems

### AI Director

Controls game pacing through a state machine:

```
BuildUp → SustainPeak (3-5s) → PeakFade → Relax (30-45s) → repeat
```

Intensity increases from damage, incaps, and kills. Spawning only occurs during active states.

### Entity Management

**Critical**: All NPCs are managed by a single EntityService script. Never create individual scripts per enemy.

```lua
-- EntityService updates all entities in one loop
RunService.Heartbeat:Connect(function(dt)
    for id, entity in EntityService.Entities do
        entity:Update(dt)
    end
end)
```

### Incapacitation System

- 0 HP → Incapacitated (not dead)
- 300 HP buffer with bleedout (1 HP/sec)
- Teammates can revive (5 seconds)
- 3rd incap = permanent death
- Safe rooms reset incap count

## Commands

```bash
# Start development server
rojo serve

# Install/update packages
wally install

# Lint code
selene src/

# Format code
stylua src/

# Build place file
rojo build -o game.rbxl
```

## Documentation

Detailed implementation guides in `/docs`:

- `ai-director.md` - Pacing system implementation
- `enemy-patterns.md` - Special infected behaviors
- `horror-atmosphere.md` - Lighting, sound, effects
- `multiplayer.md` - Co-op mechanics
- `performance.md` - Optimization patterns
- `procedural-generation.md` - Room system

## Contributing

1. Follow the code standards in `.cursorrules`
2. Run `selene src/` before committing
3. Run `stylua src/` for consistent formatting
4. Test in Roblox Studio with Rojo

## License

MIT
