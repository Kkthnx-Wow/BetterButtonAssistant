# Changelog

All notable changes to **BetterButtonAssistant** are documented here.

This project follows [Semantic Versioning](https://semver.org/).

## [1.0.2]

### Added
- **Dedicated border overlay** — the Blizzard icon-frame art now lives on its own overlay frame layered above the icon *and* the cooldown swipe, so the border never sinks behind the icon when the out-of-combat alpha dims the button.

### Changed
- **Cast feedback simplified** — removed the white flash overlay (and its intensity/color options). Cast confirmation is now the clean Blizzard-style "press" pop, with the optional feedback sound retained.

### Fixed
- **Midnight cooldown swipe** — the swipe now renders in combat on the 12.0 client (build 66562+) using secret-safe duration objects, instead of being hidden by the Secret Values model.
- **Keybind accuracy** — assisted-combat placeholder action slots are skipped while scanning, preventing a transient or wrong keybind from being shown.
- **Spell variant matching** — keybind lookup and proc glow now resolve spell overrides/variants, so the correct bind and glow show for spells that change form.

### Performance
- Action-slot and keybind results are cached and invalidated on the relevant bar/binding/form/spec events, removing per-tick bar scans and table churn.

## [1.0.0]

### Added
- Initial release: a refined, customizable button for Blizzard's **Assisted Combat** suggestion.
- Modern Blizzard icon-frame styling (border, pressed, and slot atlases).
- Keybind text, cooldown swipe, and Blizzard-style proc/activation glow.
- tullaRange-style range & usability coloring.
- Movable/lockable frame with combat and vehicle visibility controls.
- Per-state alpha, scale, font size, and update-rate tuning.
- Optional **Masque** skinning support.
