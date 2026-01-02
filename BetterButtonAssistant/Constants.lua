-- BetterAssistant Namespace
local ADDON_NAME, NS = ...

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
NS.string_lower = string.lower
NS.tostring = tostring

-- WoW API locals
NS.CreateFrame = CreateFrame
NS.UIParent = UIParent
NS.InCombatLockdown = InCombatLockdown
NS.GetActionInfo = GetActionInfo
NS.GetBindingKey = GetBindingKey
NS.GetBindingText = GetBindingText
NS.UnitInVehicle = UnitInVehicle
NS.UnitAffectingCombat = UnitAffectingCombat
NS.FindBaseSpellByID = FindBaseSpellByID

NS.C_Timer_NewTicker = C_Timer and C_Timer.NewTicker
NS.C_AddOns_IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
NS.C_ActionBar_FindSpellActionButtons = C_ActionBar and C_ActionBar.FindSpellActionButtons
NS.C_AssistedCombat_GetNextCastSpell = C_AssistedCombat and C_AssistedCombat.GetNextCastSpell
NS.C_AssistedCombat_GetRotationSpells = C_AssistedCombat and C_AssistedCombat.GetRotationSpells
NS.C_Spell_GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
NS.C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown

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

	checkVisibleButton = true, -- affects GetNextCastSpell on some setups
	updateRate = 0.12,
}

NS.DefaultActionSlotMap = {
	{ actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 1, last = 12 },
	{ actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 13, last = 24 },
	{ actionPrefix = "MULTIACTIONBAR3BUTTON", buttonPrefix = "MultiBarRightButton", start = 25, last = 36 },
	{ actionPrefix = "MULTIACTIONBAR4BUTTON", buttonPrefix = "MultiBarLeftButton", start = 37, last = 48 },
	{ actionPrefix = "MULTIACTIONBAR2BUTTON", buttonPrefix = "MultiBarBottomRightButton", start = 49, last = 60 },
	{ actionPrefix = "MULTIACTIONBAR1BUTTON", buttonPrefix = "MultiBarBottomLeftButton", start = 61, last = 72 },
	{ actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 73, last = 84 },
	{ actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 85, last = 96 },
	{ actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 97, last = 108 },
	{ actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 109, last = 120 },
	{ actionPrefix = "ACTIONBUTTON", buttonPrefix = "ActionButton", start = 121, last = 132 },
	{ actionPrefix = "MULTIACTIONBAR5BUTTON", buttonPrefix = "MultiBar5Button", start = 145, last = 156 },
	{ actionPrefix = "MULTIACTIONBAR6BUTTON", buttonPrefix = "MultiBar6Button", start = 157, last = 168 },
	{ actionPrefix = "MULTIACTIONBAR7BUTTON", buttonPrefix = "MultiBar7Button", start = 169, last = 180 },
}
