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
- **Reads like a real action button** — Blizzard icon frame, keybind text, cooldown swipe, and proc glow.
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

---

## Features

### The Button

- **Authentic styling** — Blizzard's modern icon-frame and slot atlases (resolves to the correct 1x/2x art automatically).
- **Border over icon** — the frame art renders on a dedicated overlay above the icon and cooldown swipe, so it never sinks behind the icon as the alpha changes.
- **Keybind text** — shows the actual key bound to the suggested spell, with adjustable font size. Spell overrides/variants are resolved so the correct bind shows even when a spell changes form.
- **Cooldown swipe** — renders the suggestion's cooldown where the client allows it, using secret-safe duration objects on Midnight.
- **Proc glow** — Blizzard's authentic action-button proc effect (a start burst into a looping shimmer, from the stock flipbook atlases), with a configurable tint, shown when the recommended spell lights up.
- **Cast progress (opt-in)** — optionally fills the swipe with your live cast/channel progress; Evoker empowered spells clear the swipe at a configurable release stage to signal "let go now."
- **Range & usability coloring** — tullaRange-style tint: red when out of range, blue when out of power, grey when unusable.

### Placement & Visibility

- **Movable / lockable** — drag to position, lock to make it click-through.
- **Per-state alpha** — separate opacity for in-combat and out-of-combat.
- **Show When conditions** — show Always, only with a target, only in combat, or only while the target is in combat. Reacts instantly to target/combat changes.
- **Vehicle & mount rules** — hide while in a vehicle, and optionally while mounted (including druid Travel/Flight Form).
- **Size & scale** — independent button size, overall UI scale, optional pixel-perfect (true) scale, and frame strata.

### Rotation Helpers

- **Resource pooling tint** — tints the suggestion while you're below a configurable threshold of the resource it spends (energy, focus, rage, runic power, fury, …), nudging you to pool before spending. The resource is auto-detected per spell; mana is excluded.
- **Moving override** — per-spec instant fallback for movement. While moving, if the Assisted Combat pick has a cast time, the suggestion changes to your configured instant spell; instant picks stay unchanged. Advanced settings validate the spell ID and show the resolved spell name/icon.
- **Interrupt indicator** — an opt-in companion icon that auto-detects your interrupt and lights up when your target is casting an interruptible spell in range (dim while on cooldown or non-interruptible). Secret-value safe.
- **Nameplate enemy counter** — an opt-in count above the button of attackable enemies on screen, with combat-only and minimum-enemy options.
- **Target range readout** — an opt-in estimated distance (yards) to your target shown below the button. Out of the box it's colored green/red by whether the **suggested spell** is in range (no setup), and power users can override the coloring with a per-spec spell-range list in Advanced. The list editor supports adding/removing spell rows with resolved names/icons while keeping the saved value compact. Distance is estimated from item ranges, independent of your class, and is fully secret-value safe.
- **Trinket tracker** — an opt-in display of your equipped trinkets (left of the button) with a cooldown swipe and a brief glow when one comes off cooldown. Optionally filter to on-use trinkets only, restrict to combat, and adjust icon size/spacing. Skinned to match the button and fully secret-value safe (the trinket cooldown is never read as raw numbers).

### Built for the Current Client

- **Secret Value safe** — combat cooldown times that Midnight marks secret are detected and skipped before they can taint or error, with the swipe drawn via duration objects instead.
- **Low overhead** — action-slot and keybind results are cached and invalidated only on the relevant bar/binding/form/spec events; polling rate is configurable (with a slower idle rate out of combat).
- **Masque support** — registers its regions with Masque and steps aside for the skin's own frame art.

---

## Options Reference

| Category | Settings |
|----------|----------|
| **General** | Enabled, Locked, Reset All Settings |
| **Visuals** | Button Size, Scale, Pixel-Perfect Scale, Frame Strata, Show Border, Proc Glow, Glow Style, Glow Color, Range & Usability Coloring, Show Tooltip, Use Masque |
| **Visibility** | Show When, Alpha (In Combat), Alpha (Out of Combat), Hide in Vehicle, Hide When Mounted |
| **Keybinds & Cooldowns** | Show Keybinds, Keybind Font Size, Show Cooldown, Show Cast Progress, Empower Release Stage |
| **Rotation** | Check Visible Buttons, Rotation Queue Preview, Queue Count, Queue Icon Size, Queue Icon Spacing, Queue: Combat Only, Queue Alignment, Queue Layout Direction, **Queue Position**, Resource Pooling Tint, Pooling Threshold |
| **Performance** | Update Rate, Update Rate (Out of Combat) |
| **Companions** | Companion Cooldown Numbers, Interrupt Indicator, Interrupt Watches, Interrupt Glow, Interrupt Spacing, **Interrupt Position**, Nameplate Enemy Counter, Counter: Combat Only, Counter: Minimum Enemies, Target Range Readout, Range Readout: Combat Only, Defensives Tracker, Defensive Glow, Defensive Glow Color, Defensives: Combat Only, Defensive Icon Size, Defensive Spacing, **Defensive Position**, Trinket Tracker, Trinkets: On-Use Only, Trinkets: Combat Only, Trinket Icon Size, Trinket Spacing, **Trinket Position** |
| **Advanced** | Moving Override (per-spec enable + fallback spell), Spell Range List (per-spec, row editor), Personal Defensives (per-spec, row editor, health threshold), Trinket Blacklist (account-wide, item row editor), Reset Current Spec |

**Tips:**
- In **Advanced** you can drag a spell straight from your spellbook or action bars onto any spell list to add it without typing an ID. Same for trinkets on the Blacklist.
- Companion icons show a hover tooltip with the spell/item name and current status (ready, on cooldown, casting, etc.).
- The **Position** dropdowns for each companion let you move that group to any side of the main button. Right/Left stack icons vertically; Above/Below arranges them in a horizontal row.
- The Defensive health threshold only glows when your health is **at or below** the configured percent. 0 = always glow when ready.

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
