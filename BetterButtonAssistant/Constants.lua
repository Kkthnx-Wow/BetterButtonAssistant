-- BetterAssistant Namespace
local ADDON_NAME, NS = ...
local _, buildNumber, _, buildVersion = GetBuildInfo()
NS.IS_MIDNIGHT = buildVersion >= 120000

-- Build 66562 (2026-03-24): Cooldown:SetCooldown no longer accepts secret
-- start/duration from tainted (addon) code, so the old passthrough hides the swipe
-- in combat. Blizzard's DurationObject cooldown APIs render the swipe secret-safely
-- instead. Gate on build number AND the API's existence so we degrade cleanly on
-- any client that predates it (falls back to the legacy SetCooldown path).
NS.IS_DURATION_COOLDOWNS = NS.IS_MIDNIGHT
	and (tonumber(buildNumber) or 0) >= 66562
	and C_ActionBar ~= nil
	and C_ActionBar.GetActionCooldownDuration ~= nil

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

-- Cast feedback extras (sound + tooltip) and optional Masque skinning.
NS.PlaySound = PlaySound
NS.SOUNDKIT = SOUNDKIT
NS.GameTooltip = GameTooltip
NS.LibStub = LibStub

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

-- ---------------------------------------------------------------------
-- SavedVariables + defaults
-- ---------------------------------------------------------------------
NS.defaults = {
	enabled = true,
	locked = false,

	buttonSize = 40,
	keybindFontSize = 12,

	alphaCombat = 1.0,
	alphaOOC = 0.5,
	onlyInCombat = false,
	hideInVehicle = true,

	scale = 1.0,

	showKeybind = true,
	showCooldown = true,
	showBorder = true,

	-- Press the suggestion button when the player casts the suggested spell, giving
	-- confirmation feedback that their press registered. Driven by cast events only
	-- (no secret values touched), standing in for the Midnight cooldown swipe.
	feedbackFlash = true,
	feedbackSound = false, -- also play a subtle sound on cast feedback
	feedbackPressDepth = 0.85, -- how far the button scales down on press (0.5–1.0)

	-- Proc glow: mirror Blizzard's spell-activation (proc) glow onto the suggestion
	-- when the recommended spell is procced/important.
	glowEnabled = true,
	glowColor = { 1, 0.8, 0.1 },

	-- Show a spell tooltip on hover. Note: while the frame is locked, enabling this
	-- keeps the mouse active (so it can capture hover), otherwise a locked frame is
	-- fully click-through.
	showTooltip = false,

	-- Skin the button(s) with Masque if it's installed.
	useMasque = true,

	checkVisibleButton = true, -- affects GetNextCastSpell on some setups
	updateRate = 0.12,
	updateRateOOC = 0.25, -- slower polling out of combat to cut idle CPU

	-- Range / usability coloring of the suggestion button (tullaRange-style).
	-- Each color is { r, g, b }; the suggestion icon is desaturated for the
	-- oor / oom states to match tullaRange's defaults.
	rangeColoring = true,
	colorNormal = { 1, 1, 1 }, -- castable & in range
	colorOOR = { 1, 0.3, 0.1 }, -- out of range
	colorOOM = { 0.1, 0.3, 1 }, -- not enough power (mana/rage/etc.)
	colorUnusable = { 0.4, 0.4, 0.4 }, -- otherwise unusable
}

-- Hekili-style Data Structures
NS.Hotkeys = {}
NS.UpdatedHotkeys = {}
NS.ItemToAbility = {
	[5512] = "healthstone",
	[177278] = "phial_of_serenity",
}

-- Default bar orders for binding lookup
NS.BarOrder = {
	["DEFAULT"] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
	["DRUID_PROWL"] = { 8, 7, 1, 2, 3, 4, 5, 6, 11, 12, 10, 9, 13, 14, 15 },
	["DRUID_CAT"] = { 7, 8, 1, 2, 3, 4, 5, 6, 11, 12, 10, 9, 13, 14, 15 },
	["DRUID_BEAR"] = { 9, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15 },
	["DRUID_OWL"] = { 10, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15 },
	["DRUID_TRAVEL"] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
	["DRUID_TREE"] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
	["ROGUE_STEALTH"] = { 7, 8, 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14, 15 },
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

