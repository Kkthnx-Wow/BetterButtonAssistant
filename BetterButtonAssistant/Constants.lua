-- BetterAssistant Namespace
local ADDON_NAME, NS = ...
local _, _, _, buildVersion = GetBuildInfo()
NS.IS_MIDNIGHT = buildVersion >= 120000

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
NS.wipe = wipe

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
NS.C_ActionBar_IsAssistedCombatAction = C_ActionBar and C_ActionBar.IsAssistedCombatAction
NS.C_Spell_GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
NS.C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
NS.C_Spell_GetSpellCharges = C_Spell and C_Spell.GetSpellCharges
NS.C_UnitAuras_GetAuraDataBySpellID = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID
NS.C_UnitAuras_GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
NS.GetSpecialization = GetSpecialization
NS.GetSpecializationInfo = GetSpecializationInfo
NS.UnitClass = UnitClass
NS.IsSpellKnown = C_SpellBook and C_SpellBook.IsSpellKnown or IsPlayerSpell
NS.C_Item_GetItemCooldown = C_Item and C_Item.GetItemCooldown
NS.C_Item_GetItemCount = C_Item and C_Item.GetItemCount
NS.C_Item_GetItemIconByID = C_Item and C_Item.GetItemIconByID

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

	-- Avada Tracker Defaults
	avadaEnabled = true,
	avadaSize = 16,
	avadaSpacing = 4,
	avadaOffsetY = -10,
	avadaShowBorder = true,
	avadaIndices = {}, -- Character specID -> profileIndex
	avadaProfiles = {}, -- Character/Account specID -> { [index] = "dataString" }
}

-- Hekili-style Data Structures
NS.Hotkeys = {}
NS.UpdatedHotkeys = {}
NS.WatchUnits = {}
NS.WatchTypes = {}
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

-- ---------------------------------------------------------------------
-- Avada Spell Data
-- Format: "IndexZUnitZTypeZSpellID"
-- Index: Display position (1-6)
-- Unit: player, target, pet
-- Type: buff, debuff, cd
-- ---------------------------------------------------------------------
NS.AvadaData = {
	-- HUNTER
	[253] = "1ZplayerZcdZ34026N2ZplayerZcdZ217200N3ZpetZbuffZ272790N4ZplayerZbuffZ268877N5ZplayerZcdZ19574N6ZplayerZcdZ359844", -- Beast Mastery
	[254] = "1ZplayerZcdZ19434N2ZplayerZcdZ257044N3ZplayerZbuffZ257622N4ZplayerZbuffZ474293N5ZplayerZbuffZ389020N6ZplayerZcdZ288613", -- Marksmanship
	[255] = "1ZplayerZcdZ259489N2ZplayerZcdZ259495N3ZplayerZcdZ212431N4ZplayerZcdZ212436N5ZplayerZcdZ203415N6ZplayerZcdZ360952", -- Survival
	-- DK
	[250] = "1ZplayerZbuffZ195181N2ZplayerZbuffZ77535N3ZplayerZcdZ50842N4ZplayerZcdZ43265N5ZplayerZcdZ48707N6ZplayerZcdZ55233N", -- Blood
	[251] = "1ZplayerZbuffZ51124N2ZplayerZcdZ196770N3ZplayerZcdZ43265N4ZplayerZcdZ343294N5ZplayerZcdZ51271N6ZplayerZcdZ279302N", -- Frost
	[252] = "1ZplayerZcdZ85948N2ZplayerZcdZ43265N3ZplayerZcdZ343294N4ZplayerZcdZ63560N5ZplayerZcdZ275699N6ZplayerZcdZ42650N", -- Unholy
	-- MAGE
	[62] = "1ZplayerZbuffZ263725N2ZplayerZcdZ153626N3ZplayerZcdZ321507N4ZplayerZcdZ382440N5ZplayerZcdZ365350N6ZplayerZcdZ110959N", -- Arcane
	[63] = "1ZplayerZbuffZ48107N2ZplayerZcdZ108853N3ZplayerZcdZ257541N4ZplayerZcdZ382440N5ZplayerZcdZ190319N6ZplayerZcdZ110959N", -- Fire
	[64] = "1ZplayerZcdZ44614N2ZplayerZcdZ157997N3ZplayerZcdZ153595N4ZplayerZcdZ84714N5ZplayerZcdZ382440N6ZplayerZcdZ12472N", -- Frost
	-- PALADIN
	[65] = "1ZplayerZcdZ20473N2ZplayerZcdZ35395N3ZplayerZcdZ275773N4ZplayerZcdZ114165N5ZplayerZcdZ31821N6ZplayerZcdZ642N", -- Holy
	[66] = "1ZplayerZcdZ204019N2ZplayerZcdZ275779N3ZplayerZcdZ31935N4ZplayerZcdZ387174N5ZplayerZcdZ31850N6ZplayerZcdZ86659N", -- Protection
	[70] = "1ZplayerZcdZ20271N2ZplayerZcdZ184575N3ZplayerZcdZ255937N4ZplayerZcdZ343721N5ZplayerZcdZ375576N6ZplayerZcdZ642N", -- Retribution
	-- PRIEST
	[256] = "1ZplayerZcdZ47540N2ZplayerZbuffZ390787N3ZplayerZcdZ194509N4ZplayerZcdZ62618N5ZplayerZcdZ33206N6ZplayerZcdZ421453N", -- Discipline
	[257] = "1ZplayerZcdZ34861N2ZplayerZcdZ2050N3ZplayerZcdZ64843N4ZplayerZcdZ64901N5ZplayerZcdZ47788N6ZplayerZcdZ10060N", -- Holy
	[258] = "1ZtargetZdebuffZ589N2ZtargetZdebuffZ34914N3ZtargetZdebuffZ335467N4ZplayerZcdZ8092N5ZplayerZcdZ228260N6ZplayerZcdZ10060N", -- Shadow
	-- ROGUE
	[259] = "1ZplayerZcdZ5938N2ZplayerZcdZ31224N3ZplayerZcdZ381623N4ZplayerZcdZ385627N5ZplayerZcdZ360194N6ZplayerZcdZ1856N", -- Assassination
	[260] = "1ZplayerZcdZ13877N2ZplayerZcdZ315508N3ZplayerZcdZ13750N4ZplayerZcdZ196937N5ZplayerZcdZ31224N6ZplayerZcdZ1856N", -- Outlaw
	[261] = "1ZplayerZcdZ212283N2ZplayerZcdZ121471N3ZplayerZcdZ384631N4ZplayerZcdZ185313N5ZplayerZcdZ31224N6ZplayerZcdZ1856N", -- Subtlety
	-- SHAMAN
	[262] = "1ZplayerZcdZ470411N2ZplayerZcdZ51505N3ZplayerZbuffZ191877N4ZplayerZcdZ192249N5ZplayerZcdZ114050N6ZplayerZcdZ108271N", -- Elemental
	[263] = "1ZplayerZcdZ17364N2ZplayerZcdZ60103N3ZplayerZcdZ470411N4ZplayerZcdZ51533N5ZplayerZcdZ384352N6ZplayerZcdZ108271N", -- Enhancement
	[264] = "1ZplayerZcdZ61295N2ZplayerZcdZ5394N3ZplayerZcdZ73920N4ZplayerZcdZ73685N5ZplayerZcdZ108280N6ZplayerZcdZ114052N", -- Restoration
	-- DH
	[577] = "1ZplayerZcdZ258920N2ZplayerZcdZ232893N3ZplayerZcdZ188499N4ZplayerZcdZ198013N5ZplayerZcdZ204596N6ZplayerZcdZ191427N", -- Havoc
	[581] = "1ZplayerZcdZ263642N2ZplayerZcdZ212084N3ZplayerZcdZ203720N4ZplayerZcdZ204021N5ZplayerZcdZ204596N6ZplayerZcdZ187827N", -- Vengeance
	-- DRUID
	[102] = "1ZplayerZbuffZ394050N2ZplayerZcdZ22812N3ZplayerZcdZ78675N4ZplayerZcdZ194223N5ZplayerZcdZ391528N6ZplayerZcdZ29166N", -- Balance
	[103] = "1ZtargetZdebuffZ1079N2ZplayerZcdZ22812N3ZplayerZcdZ391888N4ZplayerZcdZ61336N5ZplayerZcdZ391528N6ZplayerZcdZ106951N", -- Feral
	[104] = "1ZplayerZcdZ204066N2ZplayerZcdZ200851N3ZplayerZcdZ22812N4ZplayerZcdZ102558N5ZplayerZcdZ319454N6ZplayerZcdZ61336N", -- Guardian
	[105] = "1ZplayerZbuffZ33763N2ZplayerZbuffZ428737N3ZplayerZcdZ102342N4ZplayerZcdZ197721N5ZplayerZcdZ740N6ZplayerZcdZ391528N", -- Restoration
	-- WARLOCK
	[265] = "1ZtargetZdebuffZ316099N2ZtargetZdebuffZ980N3ZplayerZbuffZ264571N4ZplayerZcdZ48181N5ZplayerZcdZ205179N6ZplayerZcdZ386997N", -- Affliction
	[266] = "1ZplayerZbuffZ264173N2ZplayerZcdZ104316N3ZplayerZcdZ111898N4ZplayerZcdZ455465N5ZplayerZcdZ265187N6ZplayerZcdZ333889N", -- Demonology
	[267] = "1ZtargetZdebuffZ157736N2ZplayerZcdZ17962N3ZplayerZcdZ17877N4ZplayerZcdZ80240N5ZplayerZcdZ6353N6ZplayerZcdZ152108N", -- Destruction
	-- WARRIOR
	[71] = "1ZplayerZcdZ12294N2ZplayerZcdZ260708N3ZplayerZcdZ167105N4ZplayerZcdZ227847N5ZplayerZcdZ118038N6ZplayerZcdZ107574N", -- Arms
	[72] = "1ZplayerZcdZ23881N2ZplayerZcdZ85288N3ZplayerZcdZ227847N4ZplayerZcdZ384318N5ZplayerZcdZ184364N6ZplayerZcdZ107574N", -- Fury
	[73] = "1ZplayerZcdZ2565N2ZplayerZbuffZ190456N3ZplayerZcdZ228920N4ZplayerZcdZ871N5ZplayerZcdZ12975N6ZplayerZcdZ107574N", -- Protection
	-- EVOKER
	[1467] = "1ZplayerZcdZ356995N2ZplayerZcdZ382266N3ZplayerZcdZ382411N4ZplayerZcdZ370452N5ZplayerZcdZ374348N6ZplayerZcdZ375087N", -- Devastation
	[1468] = "1ZplayerZcdZ366155N2ZplayerZcdZ373861N3ZplayerZcdZ367226N4ZplayerZcdZ355936N5ZplayerZcdZ357208N6ZplayerZcdZ370553N", -- Preservation
	[1473] = "1ZplayerZcdZ409311N2ZplayerZcdZ396286N3ZplayerZcdZ357208N4ZplayerZcdZ360827N5ZplayerZcdZ363916N6ZplayerZcdZ370553N", -- Augmentation
	-- MONK
	[268] = "1ZplayerZbuffZ325092N2ZplayerZcdZ322101N3ZplayerZbuffZ215479N4ZplayerZbuffZ322507N5ZplayerZcdZ122278N6ZplayerZcdZ115203N", -- Brewmaster
	[269] = "1ZplayerZcdZ107428N2ZplayerZcdZ113656N3ZplayerZcdZ137639N4ZplayerZcdZ123904N5ZplayerZcdZ115203N6ZplayerZcdZ122783N", -- Windwalker
	[270] = "1ZplayerZbuffZ119611N2ZplayerZcdZ107428N3ZplayerZcdZ322101N4ZplayerZcdZ388193N5ZplayerZcdZ115203N6ZplayerZcdZ325197N", -- Mistweaver
}

NS.AvadaReplacedTexture = {
	[272790] = 106785, -- Barbed Shot buff icon
}

NS.AvadaValueSpells = {
	[77535] = true, -- Blood Shield
}

NS.AvadaGemini = {
	[5394] = 157153, -- Healing Stream Totem -> Cloudburst Totem
}
