# Londra - Roblox Lua Scripting UI Library

![Landra Logo](https://cdn.discordapp.com/attachments/XXXXX/XXXXX/logo.png)

**Landra** is a production-grade Roblox Luau UI library, built from scratch following a "Fog & Brass" design language. It provides a complete set of UI components, state management, theming, and key systems for Roblox experiences.

## Features

### Core Features
- **Window system** with drag, resize, minimize, maximize, close animations
- **Tab system** with section stacking, viewport clamping, persistent scroll positions
- **State management** via `Flags` system (single owner, deep equality, validation)
- **Theme system** with night/day themes, token-based coloring, contrast checking
- **Acrylic shell** with optional backdrop blur

### UI Components
- **Base components**: Toggle, Button, Label, Paragraph, Divider, Space, Badge
- **Input components**: Slider, Textbox, Dropdown, Keybind, ColorPicker, RangeSlider
- **Layout components**: Section, Tab, TabRail, Groupbox
- **Advanced components**: Progress, Table (DataGrid), Notification, Modal, ContextMenu, Tooltip, CommandPalette

### State & Configuration
- **Flags system**: Single owner of all control values, deep equality validation, type preservation
- **Config system**: Save/load JSON configs with migrations
- **Locale system**: Multi-language string tables with `t()` function
- **Key system**: Local/Http/Custom providers, HWID tracking, status machine

### Design Language
- **Fog & Brass**: Fog greys, single brass accent `#D4AF37`, hairline seam motif
- **Energy 2 / Rhythm 2 / Motion 2**: Dials controlling animation timing
- **Contrast aware**: All color combinations verified against WCAG AA standards

### Distribution
- Modular `src/` bundled to single `dist/londra.luau` by `tools/build.mjs`
- Deterministic: same input produces byte-identical output
- Topological order dependency resolution, cycles reported as errors
- Entry file: `src/Londra.luau`, exports `Londra:Window`, `Londra:SetTheme`, `Londra.Flags`

### Usage Example
```lua
local Londra = require("Londra")

local win = Londra:Window({
    Title = "Londra",
    Size = UDim2.fromOffset(760, 500),
    Theme = "night",
    Acrylic = true,
})

local tab = win:Tab({ Title = "Main" })
local section = tab:Section({ Title = "Settings", Description = "Control panel" })

local toggle = section:Toggle({ Key = "ui.enabled", Title = "Enabled", Default = true })
local slider = section:Slider({ Key = "fov", Title = "FOV", Min = 0, Max = 360, Step = 5 })
local color = section:ColorPicker({ Key = "esp.color", Title = "Renk", Default = Color3.fromRGB(212, 175, 55) })

win:Destroy()
```

## Installation

```lua
-- Via git
local Londra = loadstring(game:HttpGet("https://raw.githubusercontent.com/yusufprogamer100-ai/londra/main/src/Londra.luau"))()

-- Or use the bundled dist
local Londra = require("Londra") -- requires dist/londra.luau
```

## Requirements
- Roblox Luau executor (tested with `\temp\luau\luau.exe`)
- Roblox game environment for full functionality
- No external dependencies beyond Roblox services

## Documentation
- Full API documentation: [Plan.md](Plan.md)
- Component specifications in `src/components/`
- State system: `src/state/Flags.luau`, `src/state/Config.luau`, `src/state/Locale.luau`
- Theme system: `src/design/Theme.luau`, `src/design/Tokens.luau`

## Roadmap
- Key system with multiple providers (Local, Http, Custom)
- Advanced animation system with reduced motion support
- Localization expansions (CJK support)
- CI/CD workflow
- GitHub Pages documentation

## License
MIT - free for personal and commercial use

## Security Model
Landra's key system is **client-side convenience only**. It is NOT a security boundary:
- Users can `loadstring` code to bypass checks
- Users can `hookfunction` to bypass validation
- Real protection occurs on the **server**, where critical actions send signed requests
- See `SECURITY.md` for full threat model documentation

## Creator
Built by `yusufprogamer100-ai` as part of the Londra UI library project.