# Quick Start Guide

## Setup (One-Time)

### 1. Install Dependencies
```bash
# Install Wally packages
wally install

# Install Rojo (if not already installed)
# macOS/Linux:
brew install rojo-rbxl

# Or download from: https://rojo.space/docs/installation
```

### 2. Start Rojo Server
```bash
rojo serve
```

Keep this terminal open - it syncs your code to Studio.

## Running the Game

### 1. Open Roblox Studio
- Create a new place or open existing one
- Make sure you're in Play mode (not Edit mode)

### 2. Connect Rojo
- In Studio, go to **Plugins** → **Rojo** → **Connect**
- Or use the Rojo plugin button
- Wait for "Connected" message

### 3. Verify Setup
Check the **Output** window for:
```
[Server] Initializing L4D2 Horror Game...
[Server] All services started successfully
[Server] Server ready!
```

### 4. Test Basic Functionality
Type in chat:
- `/test` - Should spawn 5 zombies
- `/heal` - Should heal you to full health

## First Test Session

### Quick Verification (2 minutes)
1. **Spawn Test**: Type `/test` - 5 zombies should appear
2. **Shoot Test**: Left-click to fire - ammo should decrease
3. **Special Test**: Type `/hunter` - Hunter should spawn
4. **Safe Room**: Walk to green floor area - should see console messages

### Full Test (10 minutes)
Follow the complete checklist in `TESTING_GUIDE.md`

## Troubleshooting

### "Services folder not found"
- Make sure Rojo is connected
- Check that files synced (look in ServerScriptService/Server/Services)
- Restart Rojo server

### "No zombies spawn"
- Check Output for errors
- Verify EntityService started
- Try `/kill` then `/test` again

### "Safe room not working"
- Check that TestEnvironment folder exists in workspace
- Look for SafeRoomZone part
- Check console for "[SafeRoomService] Found SafeRoomZone" message

### "Ammo not updating"
- Check WeaponService started
- Verify AmmoUpdate remote exists
- Check client connected to remotes

## Development Workflow

### Making Changes
1. Edit files in `src/` directory
2. Save files
3. Rojo auto-syncs to Studio
4. Test in Studio (no restart needed for most changes)

### Testing Changes
1. Use test commands (`/test`, `/hunter`, etc.)
2. Check Output window for errors
3. Monitor Performance tab for FPS
4. Test with multiple players if possible

### Committing Changes
```bash
git add .
git commit -m "Description of changes"
git push origin master
```

## File Structure Quick Reference

```
src/
├── server/
│   ├── Server.server.lua      # Main server entry
│   └── Services/               # All game services
│       ├── GameService.lua
│       ├── EntityService.lua
│       ├── DirectorService.lua
│       └── ...
├── client/
│   ├── Client.client.lua       # Main client entry
│   └── Controllers/            # UI and input controllers
└── shared/
    └── Constants/               # Game constants
```

## Next Steps

1. ✅ **Setup Complete** - You're ready to test!
2. 📋 **Run Tests** - Follow `TESTING_GUIDE.md`
3. 🐛 **Report Bugs** - Document any issues found
4. 🚀 **Start Playing** - Enjoy your L4D2 game!

## Need Help?

- Check `TESTING_GUIDE.md` for detailed test procedures
- Check `VERIFICATION_CHECKLIST.md` for system status
- Check `IMPLEMENTATION_STATUS.md` for feature completion
- Review `docs/` folder for architecture details
