-- BetterAssistant Namespace
local _, NS = ...
local _, buildNumber, _, buildVersion = GetBuildInfo()
NS.IS_MIDNIGHT = buildVersion >= 120000

-- Branded addon title for UI (settings tree, chat, etc.). Matches ## Title in .toc.
NS.ADDON_DISPLAY_NAME = "|cff4e84b1Better|r |cff4e84b1B|cff628db1u|cff7596b1t|cff899eb0t|cff9ca7b0o|cffb0b0b0n|r |cffb0b0b0Assistant|r"

-- Build 66562 (2026-03-24): Cooldown:SetCooldown no longer accepts secret
-- start/duration from tainted (addon) code, so the old passthrough hides the swipe
-- in combat. Blizzard's DurationObject cooldown APIs render the swipe secret-safely
-- instead. Gate on build number AND the API's existence so we degrade cleanly on
-- any client that predates it (falls back to the legacy SetCooldown path).
NS.IS_DURATION_COOLDOWNS = NS.IS_MIDNIGHT and (tonumber(buildNumber) or 0) >= 66562 and C_ActionBar ~= nil and C_ActionBar.GetActionCooldownDuration ~= nil

-- ---------------------------------------------------------------------
-- Global caching (performance)
-- ---------------------------------------------------------------------
NS._G = _G
NS.ipairs = ipairs
NS.pairs = pairs
NS.type = type
NS.tonumber = tonumber
NS.pcall = pcall
NS.math_floor = math.floor
NS.math_ceil = math.ceil
NS.string_lower = string.lower
NS.tostring = tostring
NS.wipe = wipe
-- Midnight (12.0) secret-value detector. Fetched via _G because it doesn't exist
-- on pre-Midnight clients (and isn't in the static API set); nil there is fine —
-- every `issecretvalue and ...` guard becomes a no-op on clients without Secrets.
NS.issecretvalue = rawget(_G, "issecretvalue")
NS.RunNextFrame = rawget(_G, "RunNextFrame")

-- WoW API locals
NS.CreateFrame = CreateFrame
NS.UIParent = UIParent
NS.InCombatLockdown = InCombatLockdown
NS.GetActionInfo = GetActionInfo
NS.GetActionCooldown = GetActionCooldown
NS.GetBindingKey = GetBindingKey
NS.UnitInVehicle = UnitInVehicle
NS.UnitAffectingCombat = UnitAffectingCombat
NS.FindBaseSpellByID = FindBaseSpellByID
NS.FindSpellOverrideByID = FindSpellOverrideByID
NS.GetMacroSpell = GetMacroSpell
NS.GetMacroItem = GetMacroItem

NS.C_Timer_NewTicker = C_Timer and C_Timer.NewTicker
NS.C_Timer_After = C_Timer and C_Timer.After
NS.C_AddOns_IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
NS.C_ActionBar_FindSpellActionButtons = C_ActionBar and C_ActionBar.FindSpellActionButtons
NS.C_AssistedCombat_GetNextCastSpell = C_AssistedCombat and C_AssistedCombat.GetNextCastSpell
NS.C_AssistedCombat_GetRotationSpells = C_AssistedCombat and C_AssistedCombat.GetRotationSpells
NS.C_AssistedCombat_GetActionSpell = C_AssistedCombat and C_AssistedCombat.GetActionSpell
NS.C_AssistedCombat_IsAvailable = C_AssistedCombat and C_AssistedCombat.IsAvailable
NS.C_Spell_GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
NS.C_Spell_IsExternalDefensive = C_Spell and C_Spell.IsExternalDefensive
NS.C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
-- Midnight (12.0, build 66562+) secret-safe cooldown swipe. The *Duration variants
-- return a DurationObject that Cooldown:SetCooldownFromDurationObject renders without
-- the addon ever reading the (secret) start/duration numbers. GetActionCooldown is
-- the struct form (has a NeverSecret .isActive) used to gate the swipe on/off.
NS.C_ActionBar_GetActionCooldown = C_ActionBar and C_ActionBar.GetActionCooldown
NS.C_ActionBar_GetActionCooldownDuration = C_ActionBar and C_ActionBar.GetActionCooldownDuration
NS.C_Spell_GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
NS.C_Spell_GetSpellCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration
-- Range / usability state (tullaRange-style coloring of the suggestion button).
NS.C_Spell_IsSpellUsable = C_Spell and C_Spell.IsSpellUsable
NS.C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
NS.UnitClass = UnitClass

-- Player cast/channel progress + Evoker empower staging. These describe the
-- player's own cast (GetTime-based ms), which is never secret, so the swipe can
-- mirror it safely. GetUnitEmpowerStageDuration is nil on pre-empower clients.
NS.UnitCastingInfo = UnitCastingInfo
NS.UnitChannelInfo = UnitChannelInfo
NS.GetUnitEmpowerStageDuration = rawget(_G, "GetUnitEmpowerStageDuration")
NS.GetTime = GetTime

-- Visibility conditions (showWhen) + mounted/form detection. None of these read
-- secret combat values: attackability, death, and combat flags on visible units
-- are public, and mount/shapeshift state is the player's own.
NS.UnitExists = UnitExists
NS.UnitCanAttack = UnitCanAttack
NS.UnitIsDead = UnitIsDead
NS.IsMounted = IsMounted
NS.GetShapeshiftFormID = GetShapeshiftFormID

-- Resource pooling tint. The player's own power is public (it drives the player's
-- resource bar), and GetSpellPowerCost is static spell data, so both are safe.
NS.UnitPower = UnitPower
NS.UnitPowerMax = UnitPowerMax
NS.C_Spell_GetSpellPowerCost = C_Spell and C_Spell.GetSpellPowerCost
NS.C_Spell_GetSpellInfo = C_Spell and C_Spell.GetSpellInfo
-- (NS.UnitClass already cached above with the range/usability APIs.)
NS.GetSpecialization = GetSpecialization
NS.GetSpecializationInfo = GetSpecializationInfo

-- Pixel-perfect (trueScale) rendering math.
NS.GetPhysicalScreenSize = GetPhysicalScreenSize

-- Interrupt indicator + nameplate counter. Spellbook membership and override
-- resolution are static/player-owned; nameplate tokens + attackability are public.
NS.C_SpellBook_IsSpellInSpellBook = C_SpellBook and C_SpellBook.IsSpellInSpellBook
NS.C_NamePlate = C_NamePlate

-- Range module (item-distance estimate). Item info/load are static data; item
-- range checks against a unit can be secret in combat (guarded at the call site).
NS.C_Item_GetItemInfo = C_Item and C_Item.GetItemInfo
NS.C_Item_IsItemInRange = C_Item and C_Item.IsItemInRange
NS.C_Item_RequestLoadItemDataByID = C_Item and C_Item.RequestLoadItemDataByID

-- Trinket tracker companion. An equipped item's on-use spell and its icon/itemID are
-- static/player-owned data; the trinket cooldown itself is read secret-safely at the
-- call site (DurationObject swipe + the NeverSecret action-slot isActive), never via
-- the raw start/duration numbers. C_Item.GetItemSpell is the modern namespaced form.
NS.GetItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
NS.GetInventoryItemID = GetInventoryItemID
NS.GetInventoryItemTexture = GetInventoryItemTexture

-- One interrupt per class line; the first one present in the spellbook wins, then
-- we resolve its active override (e.g. talented variants). Reimplemented as our
-- own table rather than copied — same well-known interrupt IDs any tracker uses.
NS.INTERRUPT_SPELLS = {
	47528, -- Mind Freeze (Death Knight)
	183752, -- Disrupt (Demon Hunter)
	106839, -- Skull Bash (Druid)
	78675, -- Solar Beam (Druid, Balance)
	147362, -- Counter Shot (Hunter)
	187707, -- Muzzle (Hunter, Survival)
	2139, -- Counterspell (Mage)
	116705, -- Spear Hand Strike (Monk)
	96231, -- Rebuke (Paladin)
	15487, -- Silence (Priest, Shadow)
	1766, -- Kick (Rogue)
	57994, -- Wind Shear (Shaman)
	19647, -- Spell Lock (Warlock, Felhunter)
	119910, -- Spell Lock (Command Demon)
	132409, -- Spell Lock (Grimoire of Sacrifice)
	6552, -- Pummel (Warrior)
	351338, -- Quell (Evoker)
}

-- Per-spell pooled-power-type memo (which power a spell pools on, or false for
-- none). Wiped with the other spell caches on bar/binding/form/spec changes.
NS.PoolPowerCache = {}

-- Tooltip on hover, and optional Masque skinning.
NS.GameTooltip = GameTooltip
NS.LibStub = LibStub
NS.LibCustomGlow = NS.LibStub and NS.LibStub("LibCustomGlow-1.0", true)

-- Per-spell keybind memoization. Wiped wholesale in NS.ReadKeybindings whenever
-- bindings / bars / forms / specs change, so cached strings can never go stale.
NS.KeybindCache = {}

-- Per-spell action-slot memoization for cooldown lookups. Avoids calling
-- C_ActionBar.FindSpellActionButtons (which allocates a table) every update tick.
-- Wiped alongside KeybindCache on the same bar/binding/form/spec events.
NS.ActionSlotCache = {}

-- Per-spell override/talent-transform memoization. Wiped with action/keybind caches
-- because form/spec/talent/bar changes can alter what spell an action resolves to.
NS.SpellVariantCache = {}

-- Raw keybind abbreviation cache. Keeps repeated gsub passes out of rebuild storms.
NS.KeybindTextCache = {}

-- Spell IDs currently showing Blizzard's proc/activation glow. Maintained from
-- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE so we can mirror the glow on our button.
NS.GlowingSpells = {}

-- Defaults for each per-spec advanced config row. Kept out of SavedVariables so
-- profile data stores only user intent, not re-queryable defaults.
NS.SpecDefaults = {
	movingOverrideEnabled = false,
	movingOverrideSpellID = 0,
	-- Comma-separated spell IDs whose range decides the target-range readout color
	-- for this spec (any listed spell in range => "in range"). Empty = neutral.
	spellRangeList = "",
	-- Per-spec personal defensives (comma-separated spell IDs). Shown as companion icons
	-- when enabled account-wide; glow when off cooldown, usable, and the health gate
	-- passes (threshold 0 = always when ready).
	defensiveSpellList = "",
	defensiveHealthThreshold = 0, -- percent; 0 disables the health gate
}

-- Per-spec parsed spell-range list memo (specKey -> { spellID, ... }). Wiped in
-- NS.ReadKeybindings since talents/spec changes can alter the active spec key.
NS.SpecSpellRangeCache = {}
NS.SpecDefensiveCache = {}
NS.TrinketBlacklistCache = {}

-- Max companion slots (pool size at creation; actual visible count comes from settings).
NS.MAX_QUEUE_SLOTS = 5
NS.MAX_DEFENSIVE_SLOTS = 4

-- Glow color presets
NS.GlowColorPresets = {
	gold = { 1, 0.8, 0.1 },
	green = { 0.2, 0.9, 0.2 },
	blue = { 0, 0.6, 1.0 },
	red = { 1, 0.2, 0.2 },
	purple = { 0.8, 0.2, 1.0 },
	white = { 1, 1, 1 },
}

-- ---------------------------------------------------------------------
-- SavedVariables + defaults
-- ---------------------------------------------------------------------
NS.SCHEMA_VERSION = 2

NS.defaults = {
	enabled = true,
	locked = false,

	buttonSize = 80,
	keybindFontSize = 12,

	alphaCombat = 1.0,
	alphaOOC = 0.5,
	hideInVehicle = true,
	hideWhenMounted = false, -- also hides in druid travel/flight form

	-- When the button is shown at all. "Always" keeps it up (faded per the alpha
	-- settings); the others hide it unless the condition holds.
	--   Always | HasTarget | InCombat | TargetInCombat
	showWhen = "Always",

	scale = 1.0,
	-- Pixel-perfect rendering: size the button in true screen pixels so the icon
	-- never sits on a half-pixel and blurs. Overrides the UI-scaled size.
	trueScale = false,
	-- Frame strata (draw order vs. the rest of the UI).
	strata = "MEDIUM",

	-- Resource pooling tint: when the suggested spell spends a builder-style
	-- resource and you're below the threshold, the icon is tinted to say "pool a
	-- bit more before spending". The pooled power type is auto-detected per spell.
	resourcePooling = false,
	resourcePoolThreshold = 40, -- percent of the resource to pool to (0-100)
	colorPool = { 0.4, 0.5, 1 }, -- tint while below the pooling threshold

	-- Interrupt indicator: a companion icon (right of the suggestion) that lights up
	-- when your target is casting an interruptible spell, your interrupt is in range,
	-- and (where the bar tells us) off cooldown. The interruptible flag is routed via
	-- SetAlphaFromBoolean so a secret value never has to be read in Lua.
	interruptEnabled = false,
	-- Which unit the indicator watches: "target" (default), "focus", or "auto"
	-- (prefers whichever of focus/target is currently casting, focus first).
	interruptUnit = "target",
	-- Show a proc-style glow while the watched unit has a publicly-known interruptible
	-- cast/channel up and your interrupt is ready. Secret interruptible flags do not
	-- drive the glow; alpha still routes through SetAlphaFromBoolean.
	interruptGlow = true,
	-- Gap (in pixels) between the main button's right edge and the interrupt icon.
	interruptSpacing = 4,

	-- Cooldown countdown numbers on companion cooldown swipes (interrupt/trinkets).
	-- Off by default to keep the compact icons clean.
	companionCooldownNumbers = false,

	-- Nameplate counter: shows how many attackable enemies have a nameplate up
	-- (a cheap "enemies near you" readout for AoE decisions).
	nameplateCounterEnabled = false,
	nameplateCounterCombatOnly = true,
	nameplateCounterMin = 1, -- only show once at least this many enemies are up

	-- Target range readout: an estimated distance (in yards) to the current target,
	-- shown below the button. The number comes from the item-distance module; its
	-- color comes from the per-spec spell-range list (in range = green, out = red).
	rangeReadoutEnabled = false,
	rangeReadoutCombatOnly = false,
	colorInRange = { 0.4, 1, 0.4 },
	colorOutRange = { 1, 0.4, 0.4 },

	-- Trinket tracker: shows your equipped on-use trinkets (slots 13/14) above the
	-- suggestion by default (horizontal row), each with a secret-safe cooldown swipe and a brief proc-style
	-- glow when it comes off cooldown. On-use-only filtering hides passive trinkets.
	trinketEnabled = false,
	trinketOnUseOnly = true, -- only show trinkets that have an on-use spell
	trinketCombatOnly = false,
	trinketSize = 36,
	trinketSpacing = 4, -- gap (px) between the main button and the trinket group
	trinketBlacklist = "",

	-- Companion group position presets.
	-- Each controls which side of the main button the group appears on:
	--   "right"  | "left"  : group is to the right/left, icons stack vertically
	--   "above"  | "below" : group is above/below the button, icons stack horizontally
	-- When trinketPosition == defensivePosition the two groups are merged into one
	-- combined vertical (or horizontal) stack on that side, preserving the order
	-- trinkets-then-defensives (current behaviour). When they differ they are
	-- positioned independently.
	interruptPosition  = "right",
	trinketPosition    = "above",
	defensivePosition  = "left",
	queuePosition      = "below",

	-- Per-spec advanced settings live under specSettings[<classID>-<specID>].
	-- This is the foundation for Moving Override now and defensives/range lists
	-- later, without flattening spec-specific combat choices into account-wide DB.
	specSettings = {},

	showKeybind = true,
	showCooldown = true,
	showBorder = true,

	-- Mirror the player's in-progress hardcast/channel as the button's swipe (using
	-- the player's own, non-secret cast timing). For Evoker empowered spells the
	-- swipe clears once the channel reaches the release stage below, signalling
	-- "let go now". Off by default so the button keeps its plain cooldown look.
	showCastProgress = false,
	empowerMinStage = 1, -- empowered spell counts as "ready to release" at this stage

	-- Proc glow: mirror Blizzard's spell-activation (proc) glow onto the suggestion
	-- when the recommended spell is procced/important.
	glowEnabled = true,
	glowColor = "gold",
	-- Proc-glow art: "actionbar" is Blizzard's standard action-button proc flipbook;
	-- "onebutton" is the dedicated assisted-combat ("One Button") glow Blizzard shows
	-- on the assisted rotation action (same 6x5/30-frame grid, just a different sheet).
	glowStyle = "actionbar",

	-- Show a spell tooltip on hover. Note: while the frame is locked, enabling this
	-- keeps the mouse active (so it can capture hover), otherwise a locked frame is
	-- fully click-through.
	showTooltip = false,

	-- Skin the button(s) with Masque if it's installed.
	useMasque = true,

	checkVisibleButton = true, -- affects GetNextCastSpell on some setups

	-- Rotation queue: preview upcoming Assisted Combat rotation spells below the
	-- main suggestion (from C_AssistedCombat.GetRotationSpells, skipping the current
	-- next-cast pick). Matches Blizzard's rotation list order (AssistedCombatManager).
	-- Default ON so new users see the feature; disable in Rotation settings if unwanted.
	queueEnabled = true,
	queueCount = 3,
	queueSize = 34,
	queueSpacing = 4,
	queueCombatOnly = false,
	queueAlignment = "left",
	queueLayoutDirection = "horizontal",

	-- Personal defensives: per-spec spell list (Advanced) shown as icons on the left.
	-- Glow when ready + health gate passes (secret health in combat = fail open).
	defensivesEnabled = false,
	defensiveSize = 32,
	defensiveSpacing = 4,
	defensiveGlow = true,
	defensiveGlowColor = "green",
	defensiveCombatOnly = false,

	updateRate = 0.12,
	updateRateOOC = 0.25, -- slower polling out of combat to cut idle CPU

	-- SavedVariables schema; bump NS.SCHEMA_VERSION when adding migrations.
	schemaVersion = 2,

	-- Range / usability coloring of the suggestion button (tullaRange-style).
	-- Each color is { r, g, b }; the suggestion icon is desaturated for the
	-- oor / oom states to match tullaRange's defaults.
	rangeColoring = true,
	colorNormal = { 1, 1, 1 }, -- castable & in range
	colorOOR = { 1, 0.3, 0.1 }, -- out of range
	colorOOM = { 0.1, 0.3, 1 }, -- not enough power (mana/rage/etc.)
	colorUnusable = { 0.4, 0.4, 0.4 }, -- otherwise unusable
}

-- Harvested keybind database: NS.Hotkeys[action] = { upper, lower, console } keyed
-- by the spell ID string the suggestion is looked up under (see Functions.lua).
NS.Hotkeys = {}

-- Bar priority orders for keybind lookup. When a spell's keybind is found on
-- a form-specific action bar, its bar is checked FIRST so the correct key shows.
-- GetBindingForAction resolves the active form via GetShapeshiftFormID() (stable
-- form spell/type ID) and Blizzard's named constants (DRUID_CAT_FORM etc.).
NS.BarOrder = {
	["DEFAULT"]      = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
	["DRUID_PROWL"]  = { 8, 7, 1, 2, 3, 4, 5, 6, 11, 12, 10,  9, 13, 14, 15 },
	["DRUID_CAT"]    = { 7, 8, 1, 2, 3, 4, 5, 6, 11, 12, 10,  9, 13, 14, 15 },
	["DRUID_BEAR"]   = { 9, 1, 2, 3, 4, 5, 6, 7,  8, 10, 11, 12, 13, 14, 15 },
	["ROGUE_STEALTH"] = { 7, 8, 1, 2, 3, 4, 5, 6,  9, 10, 11, 12, 13, 14, 15 },
}

-- Hekili-style Binding Substitutions
NS.BindingSubs = {
	{ "CTRL%-", "C" },
	{ "ALT%-", "A" },
	{ "SHIFT%-", "S" },
	{ "STRG%-", "ST" },
	{ "%s+", "" },
	{ "NUMPAD", "N" },
	{ "PLUS", "+" },
	{ "MINUS", "-" },
	{ "MULTIPLY", "*" },
	{ "DIVIDE", "/" },
	{ "BUTTON", "M" },
	{ "MOUSEWHEELUP", "MwU" },
	{ "MOUSEWHEELDOWN", "MwD" },
	{ "MOUSEWHEEL", "Mw" },
	{ "DOWN", "Dn" },
	{ "UP", "Up" },
	{ "PAGE", "Pg" },
	{ "BACKSPACE", "BkSp" },
	{ "DECIMAL", "." },
	{ "CAPSLOCK", "CAPS" },
}
