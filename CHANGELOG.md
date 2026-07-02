# Changelog

All notable changes to **BetterButtonAssistant** are documented here.

This project follows [Semantic Versioning](https://semver.org/).

## [1.1.0]

### Added
- **Rotation queue hover tooltips** — queue icons show spell name plus readiness / position in the rotation list (matches interrupt/trinket/defensive companions).
- **Event-driven cooldown refresh** — `SPELL_UPDATE_COOLDOWN` and `ACTIONBAR_UPDATE_COOLDOWN` coalesce into `NS.UpdateCooldownsOnly()` so CD swipes update without waiting for the full ticker pass.
- **SavedVariables schema** — `schemaVersion` (currently `2`) with `NS.MigrateDatabase()` before `CopyDefaults`; bump `NS.SCHEMA_VERSION` when adding migrations.
- **Module scaffold** — `Modules/Internal.lua`, `Modules/README.md`, and `MODULE:` section markers in the main file for the planned UI/Cooldown/Companions/Events split.

### Fixed
- **Show Keybinds toggle** — turning keybinds back on now repaints the hotkey text even when the suggested spell did not change (cache was cleared on disable).
- **Rotation queue toggle** — enabling/disabling the queue no longer errors (`ReanchorQueue` forward declaration).
- **Secret spell ID comparisons** — main button, queue, defensive icons, action-slot resolution, proc-glow registration, and cooldown-only refresh no longer use `~=` on IDs that may be secret in combat.
- **Companion overlap on shared sides** — interrupt, trinkets/defensives, and rotation queue now chain outward on the same side instead of all anchoring to the same offset (fixes queue-on-right overlapping interrupt).
- **Interrupt kick glow in combat** — when `notInterruptible` is secret but interrupt is ready, glow visibility routes through `SetAlphaFromBoolean` instead of fail-closed hide.
- **Cooldown countdown font** — fixed scaling path: resolve the real countdown `FontString` via `Cooldown:GetRegions()` (Platynator pattern; `GetCountdownFontString` alone was not enough), apply `SetTextScale` per icon size, re-apply deferred after each swipe show (engine spawns/resets text on `SetCooldownFromDurationObject`).
- **Queue layout crash** — horizontal/vertical queue rows no longer store `_queueSideOff` only on icon 1 (icons 2+ errored with nil arithmetic).
- **Companion tooltip secret safety** — queue/defensive hover titles no longer call `tostring()` / concatenate secret spell IDs; tooltips are `pcall`-guarded.
- **Resource pooling in combat** — `GetPooledPowerType` / `ShouldShowPoolingTint` guard secret spell IDs and power-cost fields before comparison.
- **Interrupt CD events** — `UpdateCooldownsOnly` now calls `NS.UpdateInterrupt()` so kick glow/alpha stay in sync with event-driven swipe updates.
- **Queue combat-only layout** — toggling combat-only queue visibility now invalidates companion layout like the queue enable toggle.
- **Proc glow** — embedded [LibCustomGlow](https://github.com/Stanzilla/LibCustomGlow) `ProcGlow_Start`/`Stop` replaces the hand-rolled flipbook (yellow-square bug on addon frames). `glowStyle` still swaps actionbar vs onebutton atlases. First glow after `/reload` defers one frame so host size is resolved before LCG's OnShow anim.
- **Defensive glow on cooldown** — event-driven CD refresh now re-runs `UpdateDefensiveIcon` so the green ready glow turns off when the defensive enters cooldown.

### Changed
- **Default layout & sizing** — fresh installs: 80px main button; trinkets above (horizontal, 36px, 4px gap); defensives left (vertical, 32px, 4px gap); queue below (horizontal, left-aligned, 34px icons, 4px gap); interrupt spacing 4px.
- **Branded settings title** — the addon options tree shows the gradient title matching the AddOns list (`NS.ADDON_DISPLAY_NAME`).
- **Trinket frames** cache `_useSpellID` for lightweight cooldown-event updates.
- Documented intentional product choices: `queueEnabled` default on, unlocked placeholder spell, nameplate/defensive secret fail-open.

## [1.0.5]

### Fixed
- **Defensive ready glow false positives** — glow now requires `readiness == true` (confirmed off cooldown), matching interrupt glow fail-closed semantics. Unknown cooldown state no longer triggers a ready pulse.
- **Secret spell ID safety** — rotation queue skip, proc-glow lookup, and interrupt override resolution no longer compare or branch on secret IDs (prevents Midnight combat errors).
- **Per-tick layout churn** — companion stacks (queue, trinkets, defensives) skip `ClearAllPoints`/`SetPoint` when visible count and position presets are unchanged between ticks.
- **Keybind text on hot path** — main button keybind is only re-resolved when the suggested spell changes, not every tick.
- **Moving override after login** — `NS.playerIsMoving` is seeded from `IsPlayerMoving()` on `PLAYER_ENTERING_WORLD` so the per-spec moving override works before the first move event.
- **Unit event teardown** — interrupt, trinket, and defensive handlers use `UnregisterUnitEvent` when available (symmetric with `RegisterUnitEvent`).

### Added
- **Defensive spell validation** — Advanced defensive list rows warn in orange when `C_Spell.IsExternalDefensive` returns false for a valid spell ID (12.0.7 API).

### Removed
- **Dead `CreateAdvancedSection` helper** in Config (unused after Advanced canvas redesign).

### Documentation
- Audit findings recorded in `.context/audit-2026-06-16.md` and engineering notes updated.

## [1.0.4]

### Added
- **Companion Position Presets** — Each companion group (Interrupt, Trinkets, Defensives) now has a "Position" dropdown in Companions settings: Right, Left, Above, or Below the main button. The rotation queue has the same option in Rotation settings. Defaults match the previous fixed layout so existing setups are unchanged.
- **Companion Hover Tooltips** — Hovering over the Interrupt, Trinket, or Defensive companion icons now shows a tooltip: the spell or item name plus a live status line (e.g. "Watching target (no cast)", "On cooldown", "Ready"). Identify your companions at a glance without opening the settings panel.
- **UNIT_HEALTH event for Defensive threshold** — When a per-spec defensive health threshold is set, the addon now registers `UNIT_HEALTH` on the player so the defensive glow responds immediately when your health drops, instead of waiting for the next polling tick.

### Fixed
- **Druid keybind form detection** — `GetShapeshiftForm()` was used to identify Druid forms by shapeshift-bar slot index, which is position-dependent and wrong. Switched to `GetShapeshiftFormID()` with Blizzard's stable named constants (`DRUID_CAT_FORM = 1`, `DRUID_BEAR_FORM = 5`, `DRUID_TRAVEL_FORM = 3`). Druids in Cat or Bear form were getting the wrong action-bar priority order for keybind lookups.
- **Defensive health threshold not re-evaluated on spec change** — `UpdateDefensiveRegistration` (which controls whether `UNIT_HEALTH` is registered) was only called at login. After a spec change the new spec's threshold was ignored, leaving the old registration state in place. Now called automatically in `DelayedUpdateKeybindings` on every spec/talent/keybind rebuild.
- **Range readout ignored `queuePosition` when offsetting** — The readout always left room for the queue below the button, even when the queue was moved to the left, right, or above. Now only offsets when `queuePosition == "below"`.
- **Queue left/right horizontal mode: icons top-aligned and in wrong order** — When the queue was positioned Left or Right with horizontal layout direction, icons were anchored at the button's top edge instead of centered, and icon 1 (most urgent) was placed farthest from the button. Both corrected: icons are now vertically centered on the button, and icon 1 is always closest.
- **Interrupt glow false positives — on cooldown and non-interruptible** — Two fail-open conditions caused the glow to fire when the interrupt was on cooldown (unknown state treated as "ready") and when the `notInterruptible` flag was secret (nil treated as "can kick"). Both changed to fail-closed: the glow now requires `readiness == true` (confirmed off cooldown) AND `canKick == true` (confirmed interruptible).
- **Cooldown swipe off-bar path returned nil when state was knowable** — `C_Spell.GetSpellCooldownDuration` has `MayReturnNothing = true`: nil = not on cooldown, non-nil DurationObject = on cooldown. The off-bar path now returns proper `true`/`false` readiness instead of always nil, eliminating false-positive interrupt glows when the cooldown swipe was visibly showing.
- **`interruptSpacing` tooltip still said "to its right"** — Stale text from before the position preset system was added.
- **`queuePosition` dropdown was in Companions instead of Rotation** — The setting was placed after Trinkets in the Companions page, disconnected from the other queue settings. Moved to the Rotation subcategory alongside Queue Count, Size, Spacing, and Layout Direction.
- **Advanced settings giant empty space** — `CreateSpellListEditor` had a fixed 190px height. When lists are empty, 156px of that was dead air that pushed sections far apart. Editors now auto-size: 34px for an empty list (input bar only), growing by 28px per row up to 5 visible rows, then scrolling.
- **Advanced settings redesign** — Replaced verbose paragraph descriptions with compact one-liners, added thin horizontal dividers between sections, and moved the "Glow Health Threshold" slider to sit directly below its defensive spell list. Section headers are gold uppercase labels. The "Reset Current Spec" button is now at the bottom with a note clarifying it only resets per-spec settings (not the account-wide trinket blacklist).

### Removed / Cleaned Up
- **Dead code in `GetBindingForAction`** — The `display`, `caps`, and `console` parameters were never passed by any caller (all call sites use one argument). Removed the dead conditional block and ConsolePort output-format transformation path. Function signature simplified to `GetBindingForAction(key)`.
- **Duplicate `BarOrder` entries** — `DRUID_TRAVEL` and `DRUID_TREE` were identical to `DEFAULT`. Removed; fallback to DEFAULT is now explicit in code rather than a separately-stored duplicate.

## [1.0.3]

### Added
- **Trinket Blacklist Filter** — Add an account-wide configuration list in the Advanced settings page to exclude specific item IDs (utility, passive, or teleport trinkets) from the Trinket Tracker. Allows item drag-and-drop directly into the list editor.
- **Out-of-the-Box LibEditMode Integration** — Bundled and embedded `LibEditMode` directly in the addon libraries. The suggestion button (`BetterAssistantFrame`) now integrates natively with Blizzard's Edit Mode out of the box, saving layout-specific coordinate data dynamically.
- **Horizontal vs. Vertical Queue Layouts** — Added a setting dropdown to stack upcoming rotation queue frames vertically downwards instead of only horizontally.
- **Yards Text Vertical Height Offset** — The Target Range Readout adjusts its vertical position dynamically based on the orientation and number of visible queue frames, ensuring there is no visual overlap.
- **Reset All Settings Action** — Added a "Reset All Settings" button in the General settings panel with a StaticPopup confirmation prompt to completely reset saved variables and reload the UI.

### Fixed
- **Unused Variables and Linter Cleanliness** — Removed redundant variables and loop parameters across `BetterButtonAssistant.lua`, `Constants.lua`, and `Functions.lua`, optimizing file performance and resolving multiple linter warnings.

## [1.6.0]

### Added
- **Rotation queue preview** — optional row of icons below the main suggestion showing upcoming Assisted Combat rotation spells (from `C_AssistedCombat.GetRotationSpells`, same order as Blizzard's `AssistedCombatManager`). Skips the current next-cast pick. Settings under **Rotation**: enable, count (1–5), icon size/spacing, combat-only.
- **Personal defensives engine** — per-spec defensive spell list in **Advanced** (priority order) with an optional health threshold (%). Account-wide **Companions → Defensives** shows icons on the left (above trinkets) with cooldown swipes and a ready glow when off cooldown, usable, and the health gate passes. Secret health in combat fails open.

### Fixed
- **Rotation queue / defensives crash** — `ApplyActionState` was defined below the queue and defensive update paths, so enabling range coloring hit `attempt to call a nil value` every tick. Forward-declared and assigned once so companions can tint safely.
- **Advanced settings overflow** — the Advanced canvas now scrolls inside the settings panel using Blizzard's `ScrollFrameTemplate` + `MinimalScrollBar` (same thin modern scrollbar as the rest of retail UI). Spell list sub-editors use the same scrollbar style.
- **Proc glow square artifact** — proc glow now uses Blizzard's `ActionButtonSpellAlertTemplate` from 12.0.7 (same flipbook + Alpha sequencing as action buttons). Custom flipbook code was forcing whole-atlas cells (`SetAtlas(..., true)` + manual cell sizing) which rendered as a solid yellow square. Template path: only resize the alert frame (1.4× button); never `Hide()` flipbook textures before `Play()`.
- **Companion cooldown swipes** — `RenderCooldownReadiness` now calls `Show()`/`Hide()` on the cooldown frame; `LayoutCompanionCooldown` insets the swipe to the icon and scales countdown font with icon size.

### Changed
- **Advanced spell list editor** — `CreateSpellListEditor` now supports both the spell-range list and the defensive list via a shared, configurable field key.

## [1.5.2]

### Fixed
- **Proc glow no longer pops in at the wrong size** — flipbook cell dimensions are set explicitly (matching Blizzard's 6×5 grid), the loop texture uses `SetAllPoints` on the glow host like `ActionButtonSpellAlertTemplate`, and the start animation defers one frame so sizes are committed before `Play()`. Proc glow events also trigger an immediate coalesced refresh instead of waiting for the next tick.
- **Interrupt kick-now glow works in combat** — the glow no longer requires a readable `notInterruptible` flag (`canKick == true`). It now shows whenever the watched unit is casting, the interrupt is ready, and we haven't confirmed the cast is *not* interruptible (secret flag = fail open). Previously the glow almost never appeared in combat because `notInterruptible` is secret there.
- **Visibility/ticker lifecycle** — disabling the addon, using `/bba toggle`, or hiding via vehicle/mounted/`showWhen` now stops the update ticker instead of leaving it running in the background. The Enabled checkbox uses the visibility refresh path.

### Changed
- **Interface bumped to 120007** for Midnight patch 12.0.7.

## [1.5.1]

### Changed
- **Target Range readout is tidier at the extremes** — it now hides entirely at point-blank (a "0 yd" reading carries no useful info) and clamps anything past 40 yd to `40+ yd` instead of printing a noisy, unactionable distance (40 yd is retail's standard ability-range ceiling; the cap is a one-line change if you want more headroom).
- **LibRangeCheck-3.0 is now embedded** instead of being an optional external dependency, so the finer, self-maintaining Target Range bracketing works for everyone out of the box — not only players who also run an addon (WeakAuras, Plater, Platynator, …) that ships the library. It loads from `Libs\` with its dependencies (LibStub, CallbackHandler-1.0); LibStub dedupes by version, so if another addon provides a newer copy there's no conflict. The existing item-distance fallback still applies if the library ever fails to load.

## [1.5.0]

### Added
- **Target Range readout now uses LibRangeCheck when available** — if any loaded addon provides LibRangeCheck-3.0/2.0 (it's embedded in many popular addons), the readout uses it for much finer, self-maintaining brackets. Detection is lazy and soft (no hard dependency); our own item-distance table remains the fallback when the lib isn't present.
- The readout now shows an **honest distance band** (`5-8 yd`, `<8 yd` in melee, `100+ yd` beyond the longest checker) instead of a single bracket-ceiling number that overstated the distance.

### Changed
- **Coherence pass** — audited every feature against the addon's purpose (helping with rotations and surfacing useful info) and verified the cooldown/cursor/range APIs against the live client source. All features earned their place, so the only changes are internal cleanup.
- **Unified icon construction** — the suggestion button, interrupt indicator, and trinket frames all share the same builders now. A new `BuildCompanionIcon` helper constructs the interrupt and trinket icons identically (icon + cooldown + skin + mask + proc glow + Masque), and the main button reuses `BuildIconFrameSkin` instead of re-inlining the slot/border art. Behavior is unchanged; the three icon builders that had drifted are now one code path, so future skin tweaks land everywhere at once.

### Removed
- **Vestigial Hekili import scaffolding** in the keybind harvester: the `UpdatedHotkeys` "what changed" table (written and wiped every rebuild but never read by anything) and the `ItemToAbility` item→ability map. Assisted Combat only ever suggests spells, so item keybinds were stored but never looked up. Removing them trims a table allocation and two writes from every keybind rebuild with zero behavior change.
- **Dead `NS` exports** `NS.ApplyGlowStyle` and `NS.IsEmpowerReady` — both were assigned but only ever called through their file-local versions.

## [1.4.9]

### Added
- **Interrupt: Kick Now Glow** — optional proc-style glow while the watched target/focus has a publicly-known interruptible cast/channel and your interrupt is ready. It reuses the same Blizzard flipbook glow system as the suggestion and trinket companions, and deliberately does not branch on secret interruptibility values.
- **Companion Cooldown Numbers** — new shared companion display toggle to show Blizzard cooldown countdown numbers on interrupt/trinket cooldown swipes. Off by default to keep the small icons clean.

## [1.4.8]

### Added
- **Interrupt: Focus support** — new *Companions → Interrupt → Interrupt Watches* dropdown lets the indicator watch your **Target**, your **Focus**, or **Auto** (follows whichever of focus/target is currently casting, focus first). Great for Mythic+ focus-kicking. Cast events register only for the unit(s) actually watched, so there's no extra overhead in the default Target mode; everything stays secret-value safe (the interruptible flag still routes through `SetAlphaFromBoolean`).

## [1.4.7]

### Added
- **Assisted (One Button) glow style** — new **Glow Style** option under *Visuals → Icon & Glow*. "Action Bar" keeps Blizzard's standard action-button proc glow; "Assisted (One Button)" uses the dedicated glow Blizzard shows on the assisted-combat rotation action — the most on-theme look for this addon. Both share the same flipbook animation, so switching is instant and applies to the suggestion button and the trinket companions alike.

### Changed
- **Snappier suggestions right after a cast** — the addon now listens for the assisted-combat action cast event and refreshes the suggestion immediately, instead of waiting for the next polling tick, so the next recommended spell appears with less delay. Safely ignored on clients that don't expose the event.

## [1.4.6]

### Fixed
- **Range & Usability Coloring now actually colors by range** — the out-of-range red tint / desaturation never fired because the suggestion icon's range check wasn't given a unit to measure against. It now checks against your current target (like the range readout), so the icon goes red/desaturated when the suggested spell is out of range. With no target it's a no-op (no false positives).
- **Companion readouts no longer start at the wrong size** — the nameplate counter and target-range readout could appear at the default font size and snap to the correct size on the next layout pass (the same class of bug as the 1.4.5 glow fix). They're now created and sized up front when their feature is enabled, matching how the interrupt and trinket companions are handled.

### Performance
- **Nameplate counter is fully event-driven** — the enemy count is now recomputed only when a nameplate is added or removed (the only time the set actually changes) and cached. The per-tick path just reads the cached number instead of looping over every nameplate (and calling `UnitCanAttack` on each) several times a second. No behavior change; lower idle/combat CPU when the counter is on.

### Internal
- **Shared secret-safe cooldown renderer** — the interrupt and trinket companions now share one `RenderCooldownReadiness` helper (NeverSecret action-slot `isActive` → DurationObject swipe → pre-Midnight public numbers), removing ~40 lines of near-duplicate cooldown logic and keeping all three secret-value rules in one place.
- Deduped the proc-glow SHOW/HIDE event handlers behind a single `MarkSpellGlow` helper, and removed dead code (`NS.FormatSpellDisplay`).

## [1.4.5]

### Fixed
- **Proc glow no longer pops in small** — the activation glow could render collapsed for the first frame of every proc and then snap to full size. The flipbook textures were sized via `SetAllPoints` (anchor-resolved on the next layout pass), but a flipbook derives each cell from the texture's size at the moment it plays — and the glow plays in the same frame it's shown. The textures are now sized explicitly (`SizeGlow`), so the burst is full size on its very first frame, every time. Applies to the suggestion button and the trinket companion.

## [1.4.4]

### Changed
- **Settings sections** — the busier settings pages are now split into labelled sections with a bold title and a hover description, so each group reads on its own instead of as one flat list: **Companions** (Interrupt / Nameplate Counter / Target Range Readout / Trinkets), **Visuals** (Size & Placement / Icon & Glow / Tooltip & Skinning), and **Keybinds & Cooldowns** (Keybinds / Cooldown & Cast). Uses Blizzard's native section-header element.

### Added
- **Trinket Tracker companion** — optionally shows your equipped trinkets (left of the suggestion button) with a cooldown swipe and a brief proc-style glow when one comes off cooldown. Options: enable, on-use-only filtering (hides passive/stat trinkets), combat-only, icon size, and spacing. Built on our existing companion system with the same icon-frame art/mask/Masque routing as the main button — no extra libraries.
  - **Secret-value safe:** unlike typical trackers, the trinket cooldown is never read as raw start/duration numbers. It uses the NeverSecret action-slot `isActive` when the trinket's on-use is on a tracked bar, otherwise the spell's DurationObject for the swipe (suppressing the ready glow rather than risking a secret read in combat).

### Internal
- Extracted the proc-glow builder into a shared `AttachProcGlow` helper so the suggestion button and the trinket companion glow identically (no duplicated flipbook setup).

## [1.4.3]

### Added
- **Drag spells into the Advanced editors** — you can now drag a spell straight from your spellbook or action bars onto the **Spell Range List** to add it (no need to look up the ID), or onto the **Moving Override** input to set it. Dropping a duplicate is ignored with a friendly status message.
- **Interrupt Icon Spacing slider** — control the gap between the interrupt companion icon and the main button (Companions group).

### Removed
- **Cast feedback** — removed the cast-confirmation "press pop" entirely, along with its options (Cast Feedback, Cast Feedback Sound, Feedback Press Depth), the `/bba test` preview command, the pressed-frame art, and the cast-tracking event hooks. This also drops the now-unused `Feedback` settings group.

### Changed
- **Advanced settings upgraded** — the raw spell ID text boxes are now small purpose-built editors inspired by Dashi's Settings/ScrollBox patterns (implemented locally, no dependency): Moving Override has apply/clear controls with live spell validation and icon/name preview, while Spell Range List is now a row-based add/remove editor that canonicalizes IDs and prevents duplicates.
- **Settings reorganized** — options are now grouped where they make the most sense:
  - **Interrupt Indicator** moved from *Rotation* to **Companions** (it's a companion widget alongside the nameplate counter and range readout).
  - **Logic** renamed to **Performance** (the polling-rate sliders); **Check Visible Buttons** moved into **Rotation** since it controls what gets suggested.
  - **Visuals** is now purely appearance (size, scale, strata, border, glow, coloring, tooltip, Masque), with the most-used controls ordered first.

### Internal
- Settings registration was consolidated behind shared `AddCheckbox` / `AddSlider` / `AddDropdown` helpers and reused callbacks/formatters, removing several hundred lines of duplicated boilerplate with no change to behavior.
- Added shared spell-list helpers (`ParseSpellIDList`, `FormatSpellIDList`, `ValidateSpellID`) so Advanced settings and range checks use the same parser/canonicalizer.
- Dropped the dead `onlyInCombat` default; the one-time migration into `showWhen` is preserved and now also clears the stale saved key.

## [1.4.2]

### Fixed
- **Combat crash from resource pooling** — reading the player's power for the pooling tint could hit a Midnight "secret" number in combat and error (`attempt to perform arithmetic on a secret number value`). Power values are now checked for secrecy before any math and the tint is skipped when they can't be read.
- **Keybind drawn under the frame** — the keybind text now renders on the icon-frame overlay, above the metal border art, so it's never partially hidden by the frame.
- **Icon not filling the frame** — the rounded mask is now combined with a slight icon trim and a small mask oversize so the art reaches the metal ring with no dark gap, while still rounding the corners.

### Performance
- The per-tick update no longer reformats or repaints the target-range readout or the nameplate counter unless their displayed value actually changes, removing per-frame string allocation on the tick path.

### Changed
- **Rounded icon mask** — the icon now uses Blizzard's own action-button mask atlas (`UI-HUD-ActionBar-IconFrame-Mask`) on a real mask texture anchored to the icon, so the icon's corners are rounded to match the metal frame's interior. The icon is still trimmed slightly (`SetTexCoord`) to crop the baked-in dark border so the art fills all the way to the frame, then the mask rounds the corners. The cooldown spiral is inset using Blizzard's scaled action-button offsets so it stays inside the rounded icon area. Applies to both the suggestion button and the interrupt companion. The mask setup is guarded so it can never break button setup, and when Masque is active its own icon/cooldown layout is used instead (ours is removed/skipped so they don't compound).

## [1.4.1]

### Fixed
- **Icon-frame skin sizing** — the metal border was drawn ~13% too large for the button (it used a 37/32 ratio, so a 40px button got the 46px frame meant for Blizzard's 45px button) and carried an odd offset, so the frame didn't hug the icon. It now matches Blizzard's real `BaseActionButtonMixin:UpdateButtonArt` ratio — `UI-HUD-ActionBar-IconFrame` at 46×45 around a 45px button (≈1.022× wide, 1.0× tall), centered — so the border sits tight against the icon at every size. The dark slot backing is matched to the frame footprint instead of flaring past it. Applies to both the suggestion button and the interrupt companion.

## [1.4.0]

### Added
- **Target range readout** — an opt-in estimate of the distance (in yards) to your current target, shown below the button. The number comes from a new self-contained range module (`Range.lua`) that binary-searches a yard→item table via `C_Item.IsItemInRange` for an upper-bound distance, independent of your class/spells. Item data is loaded lazily and retried on a `C_Timer` loop (no `OnUpdate` polling). Includes a "combat only" option.
- **Range readout coloring (zero-config)** — by default the readout is colored **green/red** by whether the currently-suggested spell is in range of your target, so it's useful immediately with no setup.
- **Per-spec spell-range list (optional override)** — in the Advanced canvas you can enter comma-separated spell IDs for the active spec to override the automatic coloring; the readout then turns green when the target is in range of any listed spell, red when out (neutral white when nothing can tell). Parsed list is memoized per spec and invalidated on spec/talent changes.

### Performance / safety
- The readout only does work while enabled and a live attackable target exists; the range estimate is a log2(n) search over a tiny presorted array. All range checks are secret-value safe — a secret result is treated as "no data" rather than compared.

### Notes
- Both pieces default **off** and reuse the existing per-spec settings foundation.

## [1.3.1]

### Fixed
- **Interrupt indicator skin** — the interrupt companion was a bare, unframed icon. It now wears the same Blizzard icon-frame skin as the suggestion button (slot backing + metal border on an overlay above the cooldown swipe), trims its icon identically, and registers with Masque when enabled.
- **Proc glow popping in small** — the glow could play its first frames at a collapsed size and then snap to full size on the next layout pass. The glow host now seeds a real size at creation and is re-sized to the current button immediately before the flipbook plays (mirroring how Blizzard re-anchors its proc overlay on every show).

### Changed
- Refactored the icon-frame skin (border + pressed frame + slot) into shared build/layout helpers so the suggestion button and interrupt companion are skinned and scaled with identical aspect math.

## [1.3.0]

### Added
- **Advanced Settings canvas** — a NexEnhance-style custom subpage inside Blizzard Settings for controls that need text input. This keeps simple toggles/sliders in the native Settings layout while giving per-spec combat tools a richer editor.
- **Moving Override** — per-specialization cast-while-moving fallback. While moving, if the Assisted Combat pick has a cast time, the suggestion is replaced with your configured instant spell ID; instant picks remain unchanged. The override updates immediately on `PLAYER_STARTED_MOVING` / `PLAYER_STOPPED_MOVING`.
- **Per-spec combat settings foundation** — added `specSettings[<classID>-<specID>]` with code-only defaults, ready for defensives and spell-range lists next.

### Performance
- Moving Override does no work unless enabled for the active spec and only reads static spell info for the current suggestion while the player is moving.

## [1.2.0]

### Added
- **Interrupt indicator** — an opt-in companion icon (right of the suggestion) that auto-detects your spec's interrupt and brightens when your target is casting an **interruptible** spell that's in range, dimming when your kick is on cooldown or the cast can't be interrupted. Fully secret-value safe: cast presence is tracked from public unit events, and the (possibly secret) `notInterruptible` flag is routed through `SetAlphaFromBoolean` rather than read in a Lua conditional. Its cast events are only registered while the feature is enabled.
- **Nameplate enemy counter** — an opt-in count above the button of how many attackable enemies have a nameplate up, with "combat only" and "minimum enemies" options. Reads only public nameplate tokens (with a secret-safe fallback for instanced attackability), and registers its nameplate events only while enabled.

### Notes
- Both features default **off** and add zero polling/event cost until you turn them on.

## [1.1.0]

### Added
- **Show When conditions** — a dropdown replaces the old "Only Show in Combat" checkbox: choose **Always**, **Has Target**, **In Combat**, or **Target In Combat**. Existing "only in combat" saves migrate automatically. Driven by target/combat events so a hidden button re-appears the instant its condition is met.
- **Hide When Mounted** — optionally hide the button while mounted, including druid Travel and Flight Form.
- **Pixel-Perfect Scale** — an optional true-scale mode that snaps the button to whole physical pixels so the icon art never blurs on a half-pixel; the scale slider multiplies on top of it.
- **Frame Strata** — pick the button's draw order (Background → Tooltip) so other frames can't cover it.
- **Resource Pooling Tint** — when the suggested spell spends a builder/spender resource (energy, focus, rage, runic power, fury, …) and you're below a configurable threshold, the icon is tinted to say "pool a little more before spending." The pooled resource is auto-detected per spell from its power cost; mana is excluded.

### Performance
- The pooled-power type is memoized per spell and the cache is cleared with the other spell caches on bar/spec/talent/form changes. Visibility conditions read only public, non-secret unit state.

## [1.0.2]

### Added
- **Authentic proc glow** — the proc/activation glow is now Blizzard's real action-button effect: a one-shot "start" burst that hands off to a looping shimmer, drawn from the stock `UI-HUD-ActionBar-Proc-*-Flipbook` atlases. It replaces the old additive pulse, is tintable via the glow color, and is suppressed while the button is faded out of combat.
- **Cast progress swipe (opt-in)** — an optional mode that fills the swipe with your live hardcast/channel progress. Evoker empowered spells clear the swipe once they reach a configurable release stage, reading as "let go now." Uses only the player's own (non-secret) cast timing. Off by default.
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
