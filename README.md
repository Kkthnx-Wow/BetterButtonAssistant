<div align="center">

# BetterButtonAssistant

**A refined, customizable button for Blizzard's Assisted Combat — modern icon-frame styling, real keybind text, proc glow, and range coloring, with sensible defaults and deep options.**

[![CurseForge](https://img.shields.io/badge/CurseForge-Download-orange)](https://www.curseforge.com/wow/addons/betterbuttonassistant)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Overview

Blizzard's **Assisted Combat** tells you what to cast next, but the default suggestion is plain and disconnected from the rest of your UI. **BetterButtonAssistant** rebuilds it into a single, polished action-button: authentic Blizzard icon-frame art, the real keybind for the suggested spell, a cooldown swipe, a proc glow, and tullaRange-style range coloring — all configurable.

It stays out of your way with good defaults, but opens up a full options panel when you want to tune size, placement, visibility, and feel.

- **Drop-in polish** — works the moment it loads with a clean, modern look.
- **Reads like a real action button** — Blizzard icon frame, pressed state, keybind text, cooldown swipe, and proc glow.
- **Midnight-ready** — built for the current client, with defensive guards against the 12.0 Secret Values model so combat cooldowns can't throw errors.
- **Performance-first** — event-driven with cached action-slot and keybind lookups, so there are no per-tick bar scans.
- **Masque-friendly** — skins cleanly with Masque if you have it.

---

## Installation

**Via an addon manager (recommended)**
- [CurseForge](https://www.curseforge.com/wow/addons/betterbuttonassistant) — search for **BetterButtonAssistant** and install.

**Manual**
1. Download the latest release.
2. Extract the `BetterButtonAssistant` folder into `World of Warcraft\_retail_\Interface\AddOns`.
3. Restart the game (or `/reload` if already in-game).

---

## Getting Started

Once loaded, the suggestion button appears wherever you place it. Unlock the frame and drag it where you like, then lock it back down.

Open the options with `/bba` (or via **Game Menu → Options → AddOns → BetterButtonAssistant**) to tune the look and behavior.

### Slash Commands
- `/bba` (also `/betterbuttonassistant`, `/betterassistant`) — open the settings panel.
- `/bba toggle` — enable/disable the addon.
- `/bba test` — preview the cast-feedback animation without needing combat.

---

## Features

### The Button
- **Authentic styling** — Blizzard's modern icon-frame, pressed-frame, and slot atlases (resolves to the correct 1x/2x art automatically).
- **Border over icon** — the frame art renders on a dedicated overlay above the icon and cooldown swipe, so it never sinks behind the icon as the alpha changes.
- **Keybind text** — shows the actual key bound to the suggested spell, with adjustable font size. Spell overrides/variants are resolved so the correct bind shows even when a spell changes form.
- **Cooldown swipe** — renders the suggestion's cooldown where the client allows it, using secret-safe duration objects on Midnight.
- **Proc glow** — mirrors Blizzard's spell-activation (proc) glow when the recommended spell lights up, with a configurable color.
- **Range & usability coloring** — tullaRange-style tint: red when out of range, blue when out of power, grey when unusable.

### Cast Feedback
- **Press pop** — a quick Blizzard-style press animation confirms when you cast the suggested spell, standing in for the cooldown swipe on clients that can't draw it. Press depth is adjustable.
- **Optional sound** — play a subtle confirmation sound on cast.

### Placement & Visibility
- **Movable / lockable** — drag to position, lock to make it click-through.
- **Per-state alpha** — separate opacity for in-combat and out-of-combat.
- **Combat & vehicle rules** — optionally show only in combat, and hide while in a vehicle.
- **Size & scale** — independent button size and overall UI scale.

### Built for the Current Client
- **Secret Value safe** — combat cooldown times that Midnight marks secret are detected and skipped before they can taint or error, with the swipe drawn via duration objects instead.
- **Low overhead** — action-slot and keybind results are cached and invalidated only on the relevant bar/binding/form/spec events; polling rate is configurable (with a slower idle rate out of combat).
- **Masque support** — registers its regions with Masque and steps aside for the skin's own frame art.

---

## Options Reference

| Category | Settings |
|----------|----------|
| **General** | Enabled, Locked |
| **Visuals** | Button Size, Show Border, Range & Usability Coloring, Cast Feedback, Cast Feedback Sound, Feedback Press Depth, Proc Glow, Show Tooltip, Use Masque, Scale |
| **Visibility** | Alpha (In Combat), Alpha (Out of Combat), Only Show in Combat, Hide in Vehicle |
| **Keybinds & Cooldowns** | Show Keybinds, Show Cooldown, Keybind Font Size |
| **Logic** | Check Visible Buttons, Update Rate, Update Rate (Out of Combat) |

---

## Contributing

Contributions, bug reports, and ideas are welcome. When filing a bug, please include your client version, your class/spec, and a `/reload`-able repro — it helps a ton.

---

## Support

Appreciate the work that goes into BetterButtonAssistant? Consider showing your support:

- **PayPal** — [paypal.me/KkthnxTV](https://www.paypal.me/KkthnxTV)
- **Patreon** — [patreon.com/Kkthnx](https://www.patreon.com/Kkthnx)

---

## License

Released under the **MIT License**.

<div align="center">

Developed and maintained by **Josh "Kkthnx" Russell**. Built for a cleaner Assisted Combat.

</div>
