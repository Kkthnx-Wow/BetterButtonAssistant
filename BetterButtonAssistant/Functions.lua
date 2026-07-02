local _, NS = ...

-- File-level locals for hot-path performance (avoids NS.* table lookup overhead).
-- Constants.lua loads before this file, so the cached API refs already exist.
local math_floor = math.floor
local math_ceil = math.ceil
local table_concat = table.concat
local C_Spell_GetOverrideSpell = NS.C_Spell_GetOverrideSpell
local C_Spell_GetSpellInfo = NS.C_Spell_GetSpellInfo
local C_Spell_GetSpellTexture = NS.C_Spell_GetSpellTexture
local C_Spell_IsSpellUsable = NS.C_Spell_IsSpellUsable
local C_Spell_IsSpellInRange = NS.C_Spell_IsSpellInRange
local FindSpellOverrideByID = NS.FindSpellOverrideByID
local UnitClass = NS.UnitClass
local GetSpecialization = NS.GetSpecialization
local GetSpecializationInfo = NS.GetSpecializationInfo
-- Midnight (12.0) secret-value detector; nil on pre-Midnight clients (no-op guard).
local issecretvalue = NS.issecretvalue

-- ---------------------------------------------------------------------
-- Utility Functions
-- ---------------------------------------------------------------------

function NS.CopyDefaults(dst, src)
	for k, v in NS.pairs(src) do
		if NS.type(v) == "table" then
			if NS.type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			NS.CopyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

-- Current specialization key for per-spec combat settings. The class ID makes the
-- key stable across classes even if spec IDs ever collide in future content.
function NS.GetSpecKey()
	if not UnitClass or not GetSpecialization or not GetSpecializationInfo then
		return nil
	end

	local _, _, classID = UnitClass("player")
	local specIndex = GetSpecialization()
	if not classID or not specIndex then
		return nil
	end

	local specID = GetSpecializationInfo(specIndex)
	if not specID then
		return nil
	end

	return classID .. "-" .. specID
end

-- Player-facing specialization label for settings UI (e.g. "Vengeance (Demon Hunter)").
-- The internal storage key remains GetSpecKey()'s "classID-specID" form.
function NS.GetSpecDisplayName()
	if not UnitClass or not GetSpecialization or not GetSpecializationInfo then
		return nil
	end

	local className = UnitClass("player")
	local specIndex = GetSpecialization()
	if not specIndex then
		return nil
	end

	local _, specName = GetSpecializationInfo(specIndex)
	if not specName or specName == "" then
		return className
	end
	if className and className ~= "" then
		return specName .. " (" .. className .. ")"
	end
	return specName
end

function NS.GetSpecConfig(specKey)
	if not NS.db then
		return nil
	end
	specKey = specKey or NS.GetSpecKey()
	if not specKey then
		return nil
	end

	local all = NS.db.specSettings
	if NS.type(all) ~= "table" then
		all = {}
		NS.db.specSettings = all
	end

	local cfg = all[specKey]
	if NS.type(cfg) ~= "table" then
		cfg = {}
		all[specKey] = cfg
	end
	NS.CopyDefaults(cfg, NS.SpecDefaults)
	return cfg
end

-- Run before NS.CopyDefaults on load. Bump NS.SCHEMA_VERSION when adding steps.
function NS.MigrateDatabase(db)
	if not db then
		return
	end
	local version = db.schemaVersion or 1
	if version < 2 then
		-- v1 -> v2: formal schemaVersion field (inline onlyInCombat migration stays in main).
		db.schemaVersion = 2
	end
end

function NS.ValidateSpellID(spellID)
	spellID = math_floor(NS.tonumber(spellID) or 0)
	if spellID <= 0 then
		return 0, "None", false, nil
	end

	local name
	if C_Spell_GetSpellInfo then
		local info = C_Spell_GetSpellInfo(spellID)
		name = info and info.name
	end

	local texture = C_Spell_GetSpellTexture and C_Spell_GetSpellTexture(spellID)
	if name and name ~= "" then
		return spellID, name .. " (" .. spellID .. ")", true, texture
	end
	return spellID, "Unknown spell (" .. spellID .. ")", false, texture
end

-- Defensive list editor: valid spells that Blizzard does not flag as external
-- defensives get an orange warning (still accepted — player may know better).
function NS.ValidateDefensiveSpellID(spellID)
	local id, text, valid, texture = NS.ValidateSpellID(spellID)
	if valid and NS.C_Spell_IsExternalDefensive then
		local ok, isDef = NS.pcall(NS.C_Spell_IsExternalDefensive, id)
		if ok and isDef == false then
			text = text .. " — not flagged as defensive"
		end
	end
	return id, text, valid, texture
end

function NS.ValidateItemID(itemID)
	itemID = math_floor(NS.tonumber(itemID) or 0)
	if itemID <= 0 then
		return 0, "None", false, nil
	end

	local name, texture
	if C_Item and C_Item.GetItemInfoInstant then
		local itemName, _, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfoInstant(itemID)
		name = itemName
		texture = itemTexture
	elseif GetItemInfoInstant then
		local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfoInstant(itemID)
		name = itemName
		texture = itemTexture
	end

	if name and name ~= "" then
		return itemID, name .. " (" .. itemID .. ")", true, texture
	end
	return itemID, "Unknown item (" .. itemID .. ")", false, texture
end

function NS.ParseSpellIDList(raw)
	local ids, invalid, seen = {}, {}, {}
	if NS.type(raw) ~= "string" or raw == "" then
		return ids, invalid
	end

	for token in raw:gmatch("[^,%s]+") do
		local id = NS.tonumber(token)
		if id and id > 0 and math_floor(id) == id then
			if not seen[id] then
				ids[#ids + 1] = id
				seen[id] = true
			end
		else
			invalid[#invalid + 1] = token
		end
	end

	return ids, invalid
end

function NS.FormatSpellIDList(ids)
	if NS.type(ids) ~= "table" or #ids == 0 then
		return ""
	end

	local out = {}
	for i = 1, #ids do
		out[i] = NS.tostring(ids[i])
	end
	return table_concat(out, ", ")
end

-- Parses (and memoizes per spec) the current spec's comma/space-separated
-- spell-range list into an array of numeric spell IDs. Returns an empty array
-- when unset. The cache is wiped on spec/talent changes via ReadKeybindings.
function NS.GetSpecSpellRangeList()
	local specKey = NS.GetSpecKey()
	if not specKey then
		return nil
	end

	local cache = NS.SpecSpellRangeCache
	local cached = cache[specKey]
	if cached then
		return cached
	end

	local list = {}
	local cfg = NS.GetSpecConfig(specKey)
	local raw = cfg and cfg.spellRangeList
	if NS.ParseSpellIDList then
		list = NS.ParseSpellIDList(raw)
	end

	cache[specKey] = list
	return list
end

-- Whether the target is within range of any spell in the spec's range list.
-- Returns true / false / nil (nil = no list, no usable info, or all secret), so
-- callers can show a neutral state when we genuinely can't tell. Secret-safe:
-- a secret IsSpellInRange result is never compared, just skipped.
function NS.IsTargetInSpecRange()
	if not C_Spell_IsSpellInRange then
		return nil
	end
	local list = NS.GetSpecSpellRangeList()
	if not list or #list == 0 then
		return nil
	end

	local sawInfo = false
	for i = 1, #list do
		local inRange = C_Spell_IsSpellInRange(list[i], "target")
		if not (issecretvalue and issecretvalue(inRange)) then
			if inRange == true then
				return true
			elseif inRange == false then
				sawInfo = true
			end
		end
	end

	if sawInfo then
		return false
	end
	return nil
end

-- ---------------------------------------------------------------------
-- Keybind lookup
-- ---------------------------------------------------------------------

function NS.improvedGetBindingText(binding)
	if not binding then
		return ""
	end

	local cache = NS.KeybindTextCache
	local cached = cache[binding]
	if cached then
		return cached
	end

	local original = binding
	for _, rep in NS.ipairs(NS.BindingSubs) do
		binding = binding:gsub(rep[1], rep[2])
	end

	cache[original] = binding
	return binding
end

-- Returns the spell currently displayed/executed for a base spell when Blizzard's
-- override systems are active (proc transforms, stance/form replacements, talent
-- replacements). Cached per rebuild window; callers must not compare secret IDs.
function NS.GetDisplaySpellID(spellID)
	if not spellID or spellID == 0 then
		return spellID
	end
	if issecretvalue and issecretvalue(spellID) then
		return spellID
	end

	local cache = NS.SpellVariantCache
	local cached = cache[spellID]
	if cached ~= nil then
		return cached or spellID
	end

	local overrideID
	if C_Spell_GetOverrideSpell then
		local ok, result = NS.pcall(C_Spell_GetOverrideSpell, spellID, 0, false)
		if ok and result and not (issecretvalue and issecretvalue(result)) and result ~= 0 and result ~= spellID then
			overrideID = result
		end
	end
	if not overrideID and FindSpellOverrideByID then
		local ok, result = NS.pcall(FindSpellOverrideByID, spellID)
		if ok and result and not (issecretvalue and issecretvalue(result)) and result ~= 0 and result ~= spellID then
			overrideID = result
		end
	end

	cache[spellID] = overrideID or false
	return overrideID or spellID
end

function NS.StoreKeybindInfo(page, key, aType, id, console)
	if not key or not aType or not id then
		return
	end

	-- Skip Blizzard's Assisted Combat placeholder action. On the default-bar path
	-- the 3rd GetActionInfo return (subType) arrives here as `console`, and an
	-- assisted-combat slot reports subType == "assistedcombat". Its resolved spell
	-- changes every GCD, so caching a binding for it would map whatever spell is
	-- currently suggested onto the one-button assist key (transient and wrong). The
	-- spell's real keybind on an actual bar slot is still captured separately.
	if console == "assistedcombat" or (aType == "spell" and id == "assistedcombat") then
		return
	end

	local keys = NS.Hotkeys

	-- We key the database by the action's ID string (the spell ID we later look the
	-- keybind up by). Items never get queried — the suggestion is always a spell —
	-- so item slots are only relevant when a macro resolves to a spell (handled below).
	local action = NS.tostring(id)

	if action then
		if aType == "macro" then
			local _, _, spellID = NS.GetMacroSpell(id)
			if spellID then
				action = NS.tostring(spellID)
			else
				local _, link = NS.GetMacroItem(id)
				if link then
					local itemID = link:match("item:(%d+)")
					if itemID then
						action = itemID
					end
				end
			end
		end

		local function save(act)
			keys[act] = keys[act] or {
				lower = {},
				upper = {},
				console = {},
			}

			if console == "cPort" then
				local newKey = key:gsub(":%d+:%d+:0:0", ":0:0:0:0")
				keys[act].console[page] = newKey
			else
				keys[act].upper[page] = NS.improvedGetBindingText(key)
				keys[act].lower[page] = NS.string_lower(keys[act].upper[page])
			end
		end

		save(action)

		-- If it's a spell, also store it under the base ID
		if aType == "spell" then
			local spellNum = NS.tonumber(action)
			if spellNum then
				local baseID = NS.FindBaseSpellByID(spellNum)
				if baseID and baseID ~= spellNum then
					save(NS.tostring(baseID))
				end
				local displayID = NS.GetDisplaySpellID(spellNum)
				if displayID and displayID ~= spellNum then
					save(NS.tostring(displayID))
				end
			end
		end
	end
end

function NS.ReadKeybindings(event)
	local keys = NS.Hotkeys

	for _, v in NS.pairs(keys) do
		NS.wipe(v.console)
		NS.wipe(v.upper)
		NS.wipe(v.lower)
	end
	NS.wipe(NS.KeybindCache)
	NS.wipe(NS.ActionSlotCache)
	NS.wipe(NS.SpellVariantCache)
	NS.wipe(NS.KeybindTextCache)
	-- Pooled-power type can change with talents/spec, so drop it on rebuilds too.
	if NS.PoolPowerCache then
		NS.wipe(NS.PoolPowerCache)
	end
	-- The active spec key can change here too, so drop the parsed range list memo.
	if NS.SpecSpellRangeCache then
		NS.wipe(NS.SpecSpellRangeCache)
	end
	if NS.SpecDefensiveCache then
		NS.wipe(NS.SpecDefensiveCache)
	end

	local slotsUsed = {}

	-- Bartender4 support
	if NS._G["Bartender4"] then
		for i = 1, 180 do
			local keybind = "CLICK BT4Button" .. i .. ":Keybind"
			local bar = math_floor((i - 1) / 12) + 1
			local key = NS.GetBindingKey(keybind)
			if key then
				NS.StoreKeybindInfo(bar, key, NS.GetActionInfo(i))
				slotsUsed[i] = true
			end
		end

	-- Dominos support
	elseif NS.C_AddOns_IsAddOnLoaded("Dominos") then
		for i = 1, 14 do
			local bar = NS._G["DominosFrame" .. i]
			if bar and bar.buttons then
				for b = 1, 12 do
					local btn = bar.buttons[b]
					if btn and btn.action then
						local keybind
						local action = btn.action
						if action <= 0 then
							keybind = "CLICK " .. btn:GetName() .. ":HOTKEY"
						elseif action <= 12 then
							keybind = "ACTIONBUTTON" .. action
						elseif action <= 24 then
							keybind = "CLICK " .. btn:GetName() .. ":HOTKEY"
						elseif action <= 36 then
							keybind = "MULTIACTIONBAR3BUTTON" .. (action - 24)
						elseif action <= 48 then
							keybind = "MULTIACTIONBAR4BUTTON" .. (action - 36)
						elseif action <= 60 then
							keybind = "MULTIACTIONBAR2BUTTON" .. (action - 48)
						elseif action <= 72 then
							keybind = "MULTIACTIONBAR1BUTTON" .. (action - 60)
						elseif action <= 132 then
							keybind = "CLICK " .. btn:GetName() .. ":HOTKEY"
						elseif action <= 144 then
							keybind = "MULTIACTIONBAR5BUTTON" .. (action - 132)
						elseif action <= 156 then
							keybind = "MULTIACTIONBAR6BUTTON" .. (action - 144)
						elseif action <= 168 then
							keybind = "MULTIACTIONBAR7BUTTON" .. (action - 156)
						end

						local key = keybind and NS.GetBindingKey(keybind)
						if key then
							NS.StoreKeybindInfo(i, key, NS.GetActionInfo(btn.action))
							slotsUsed[btn.action] = true
						end
					end
				end
			end
		end

	-- ElvUI support (Use ElvUI's actionbars only if they are actually enabled)
	elseif NS._G["ElvUI"] and NS._G["ElvUI_Bar1Button1"] then
		for i = 1, 15 do
			for b = 1, 12 do
				local btn = NS._G["ElvUI_Bar" .. i .. "Button" .. b]
				if btn then
					local binding = btn.bindstring or btn.keyBoundTarget or ("CLICK " .. btn:GetName() .. ":LeftButton")
					if i > 6 then
						local bar = NS._G["ElvUI_Bar" .. i]
						if not bar or not bar.db.enabled then
							binding = "ACTIONBUTTON" .. b
						end
					end

					local action = btn._state_action
					if action and NS.type(action) == "number" then
						slotsUsed[action] = true
						local key = NS.GetBindingKey(binding)
						local aType, id = NS.GetActionInfo(action)
						if key and aType then
							NS.StoreKeybindInfo(i, key, aType, id)
						end
					end
				end
			end
		end
	end

	-- Default Action Bar fallbacks
	for i = 1, 12 do
		if not slotsUsed[i] then
			NS.StoreKeybindInfo(1, NS.GetBindingKey("ACTIONBUTTON" .. i), NS.GetActionInfo(i))
		end
	end

	for i = 13, 24 do
		if not slotsUsed[i] then
			NS.StoreKeybindInfo(2, NS.GetBindingKey("ACTIONBUTTON" .. i - 12), NS.GetActionInfo(i))
		end
	end

	for i = 25, 36 do
		if not slotsUsed[i] then
			NS.StoreKeybindInfo(3, NS.GetBindingKey("MULTIACTIONBAR3BUTTON" .. i - 24), NS.GetActionInfo(i))
		end
	end

	for i = 37, 48 do
		if not slotsUsed[i] then
			NS.StoreKeybindInfo(4, NS.GetBindingKey("MULTIACTIONBAR4BUTTON" .. i - 36), NS.GetActionInfo(i))
		end
	end

	for i = 49, 60 do
		if not slotsUsed[i] then
			NS.StoreKeybindInfo(5, NS.GetBindingKey("MULTIACTIONBAR2BUTTON" .. i - 48), NS.GetActionInfo(i))
		end
	end

	for i = 61, 72 do
		if not slotsUsed[i] then
			NS.StoreKeybindInfo(6, NS.GetBindingKey("MULTIACTIONBAR1BUTTON" .. i - 60), NS.GetActionInfo(i))
		end
	end

	for i = 73, 144 do
		if not slotsUsed[i] then
			NS.StoreKeybindInfo(7 + math_floor((i - 73) / 12), NS.GetBindingKey("ACTIONBUTTON" .. 1 + (i - 73) % 12), NS.GetActionInfo(i))
			slotsUsed[i] = true
		end
	end

	for i = 145, 156 do
		if not slotsUsed[i] then
			NS.StoreKeybindInfo(13, NS.GetBindingKey("MULTIACTIONBAR5BUTTON" .. i - 144), NS.GetActionInfo(i))
		end
	end

	for i = 157, 168 do
		if not slotsUsed[i] then
			NS.StoreKeybindInfo(14, NS.GetBindingKey("MULTIACTIONBAR6BUTTON" .. i - 156), NS.GetActionInfo(i))
		end
	end

	for i = 169, 180 do
		if not slotsUsed[i] then
			NS.StoreKeybindInfo(15, NS.GetBindingKey("MULTIACTIONBAR7BUTTON" .. i - 168), NS.GetActionInfo(i))
		end
	end

	if NS._G.ConsolePort then
		for i = 1, 180 do
			local action, id = NS.GetActionInfo(i)
			if action and id then
				local bind = NS._G.ConsolePort:GetActionBinding(i)
				local key, mod = NS._G.ConsolePort:GetCurrentBindingOwner(bind)
				if key then
					NS.StoreKeybindInfo(math_ceil(i / 12), NS._G.ConsolePort:GetFormattedButtonCombination(key, mod), action, id, "cPort")
				end
			end
		end
	end
end

-- Returns the best keybind text for an action entry. Upper-case abbreviations
-- are always used (the "display" / "console" parameter path was dead code —
-- every caller passes one argument — and has been removed for clarity).
--
-- Bar priority order: Druid and Rogue form/stealth bar ordering is resolved via
-- GetShapeshiftFormID() (returns the stable form spell/type ID) so form
-- detection is correct regardless of which shapeshift button slot the form
-- occupies. Blizzard's own Midnight constants confirm:
--   DRUID_CAT_FORM = 1, DRUID_TRAVEL_FORM = 3, DRUID_BEAR_FORM = 5
function NS.GetBindingForAction(key)
	if not key then
		return ""
	end

	key = NS.tostring(key)

	local hotkey = NS.Hotkeys[key]
	if not hotkey then
		return ""
	end

	local db    = hotkey.upper
	local order = NS.BarOrder["DEFAULT"]

	local _, class = NS.UnitClass("player")
	if class == "DRUID" then
		-- Use GetShapeshiftFormID for stable form detection (returns form spell/type
		-- ID, not the shapeshift button slot index that GetShapeshiftForm returns).
		local formID = NS._G.GetShapeshiftFormID and NS._G.GetShapeshiftFormID() or 0
		local CAT    = NS._G.DRUID_CAT_FORM    or 1
		local TRAVEL = NS._G.DRUID_TRAVEL_FORM  or 3
		local BEAR   = NS._G.DRUID_BEAR_FORM    or 5

		if formID == CAT then
			order = NS._G.IsStealthed() and NS.BarOrder["DRUID_PROWL"] or NS.BarOrder["DRUID_CAT"]
		elseif formID == BEAR then
			order = NS.BarOrder["DRUID_BEAR"]
		elseif formID == TRAVEL then
			order = NS.BarOrder["DEFAULT"]  -- Travel uses the same bar as the main bar
		else
			-- Moonkin, Tree of Life, or any future form: default bar order.
			order = NS.BarOrder["DEFAULT"]
		end
	elseif class == "ROGUE" then
		if NS._G.IsStealthed() then
			order = NS.BarOrder["ROGUE_STEALTH"]
		end
	end

	for _, n in NS.ipairs(order) do
		local out = db[n]
		if out and out ~= "" then
			return out
		end
	end

	return ""
end

function NS.GetKeyBindForSpellID(identifier)
	if not identifier then
		return nil
	end
	if issecretvalue and issecretvalue(identifier) then
		return ""
	end

	-- Memoized: the cache is wiped in ReadKeybindings on any binding/bar/form/spec
	-- change, so a hit here is always current and skips the FindSpellActionButtons
	-- fallback scan on the hot path.
	local cache = NS.KeybindCache
	local cached = cache[identifier]
	if cached ~= nil then
		return cached
	end

	-- Instant lookup from the database. Try all spell variants JustAC taught us
	-- matter in practice: original ID, base ID, and current display/override ID.
	-- This catches proc/form/talent transforms without scanning action bars.
	local baseID = NS.FindBaseSpellByID(identifier) or identifier
	local displayID = NS.GetDisplaySpellID(identifier)
	local text = NS.GetBindingForAction(identifier)
	if not text or text == "" then
		text = NS.GetBindingForAction(baseID)
	end
	if (not text or text == "") and displayID and displayID ~= identifier and displayID ~= baseID then
		text = NS.GetBindingForAction(displayID)
	end

	-- Fallback: Use Retail API to find the spell on bars if cache missed or empty
	if (not text or text == "") and NS.C_ActionBar_FindSpellActionButtons then
		local slots = NS.C_ActionBar_FindSpellActionButtons(identifier)
		if not slots or #slots == 0 then
			slots = NS.C_ActionBar_FindSpellActionButtons(baseID)
		end
		if (not slots or #slots == 0) and displayID and displayID ~= identifier and displayID ~= baseID then
			slots = NS.C_ActionBar_FindSpellActionButtons(displayID)
		end

		if slots and #slots > 0 then
			for _, slot in NS.ipairs(slots) do
				local bName
				if slot <= 12 then
					bName = "ACTIONBUTTON" .. slot
				elseif slot <= 24 then
					bName = "ACTIONBUTTON" .. (slot - 12)
				elseif slot <= 36 then
					bName = "MULTIACTIONBAR3BUTTON" .. (slot - 24)
				elseif slot <= 48 then
					bName = "MULTIACTIONBAR4BUTTON" .. (slot - 36)
				elseif slot <= 60 then
					bName = "MULTIACTIONBAR2BUTTON" .. (slot - 48)
				elseif slot <= 72 then
					bName = "MULTIACTIONBAR1BUTTON" .. (slot - 60)
				elseif slot <= 144 then
					bName = "ACTIONBUTTON" .. (1 + (slot - 73) % 12)
				end

				if bName then
					local key = NS.GetBindingKey(bName)
					if key and key ~= "" then
						text = NS.improvedGetBindingText(key)
						break
					end
				end
			end
		end
	end

	-- Store under the identifier (never nil, so cache hits are unambiguous).
	cache[identifier] = text or ""
	return cache[identifier]
end

-- Keybind cache is wiped at the top of ReadKeybindings; no separate wipe function needed.

-- ---------------------------------------------------------------------
-- Assisted Combat spell list
-- ---------------------------------------------------------------------
function NS.SafeCallAssisted(fn, arg)
	if not fn then
		return false
	end

	-- Single protected call. GetNextCastSpell is a documented, stable API; the
	-- pcall is only here to swallow rare transient errors (e.g. mid spec swap)
	-- without breaking the ~8/sec update tick.
	local ok, a, b, c, d, e = NS.pcall(fn, arg)
	if ok then
		return true, a, b, c, d, e
	end

	return false
end

function NS.IsAssistedCombatAvailable()
	if NS.C_AssistedCombat_IsAvailable then
		return NS.C_AssistedCombat_IsAvailable()
	end
	-- Fallback for pre-12.0.0 (TWW/Live)
	-- We can't easily check 'availability' without specific spec checks,
	-- so we just assume it's available if the API exists.
	return NS.C_AssistedCombat_GetNextCastSpell ~= nil
end

local function ApplyMovingOverride(spellID)
	if not spellID or not NS.playerIsMoving then
		return spellID
	end

	local cfg = NS.GetSpecConfig and NS.GetSpecConfig()
	if not cfg or not cfg.movingOverrideEnabled then
		return spellID
	end

	local fallback = NS.tonumber(cfg.movingOverrideSpellID) or 0
	if fallback <= 0 then
		return spellID
	end

	if issecretvalue and (issecretvalue(spellID) or issecretvalue(fallback)) then
		return spellID
	end

	local castTime = 0
	if C_Spell_GetSpellInfo then
		local info = C_Spell_GetSpellInfo(spellID)
		castTime = (info and info.castTime) or 0
	end

	if castTime > 0 then
		return fallback
	end
	return spellID
end

function NS.CollectNextSpell()
	local checkVisible = NS.db.checkVisibleButton and true or false

	-- Returns sid when it's a usable spell ID: non-zero, or secret (can't compare to 0).
	local function AcceptSpellID(sid)
		return NS.AcceptSpellID and NS.AcceptSpellID(sid)
	end

	-- 1. Main Recommendation (The "One-Punch" logic that worked before)
	if NS.C_AssistedCombat_GetNextCastSpell then
		local ok, sid = NS.SafeCallAssisted(NS.C_AssistedCombat_GetNextCastSpell, checkVisible)
		if ok and AcceptSpellID(sid) then
			return ApplyMovingOverride(sid)
		end
	end

	-- 2. Highlights (Cyan highlights from the Assisted Combat menu)
	if NS.C_AssistedCombat_GetRotationSpells then
		local spells = NS.C_AssistedCombat_GetRotationSpells()
		if AcceptSpellID(spells and spells[1]) then
			return ApplyMovingOverride(spells[1])
		end
	end

	-- 3. Last Resort (12.0.0 specific recommendation)
	if NS.C_AssistedCombat_GetActionSpell then
		local sid = NS.C_AssistedCombat_GetActionSpell()
		if AcceptSpellID(sid) then
			return ApplyMovingOverride(sid)
		end
	end

	return nil
end

-- True when sid is a non-nil spell ID we can use (non-zero, or secret — can't compare).
function NS.AcceptSpellID(sid)
	if not sid then
		return false
	end
	if issecretvalue and issecretvalue(sid) then
		return true
	end
	return sid ~= 0
end

-- Upcoming rotation preview from Blizzard's assisted-combat list (same order as
-- AssistedCombatManager.rotationSpells / C_AssistedCombat.GetRotationSpells).
-- Starts after the current next-cast pick when it appears in the list; otherwise
-- skips the first entry (usually the same as the main suggestion).
function NS.CollectRotationQueue(maxCount, primarySpellID)
	maxCount = maxCount or 3
	if maxCount <= 0 or not NS.C_AssistedCombat_GetRotationSpells then
		return nil
	end

	local rotation = NS.C_AssistedCombat_GetRotationSpells()
	if not rotation or #rotation == 0 then
		return nil
	end

	local startIdx = 1
	if primarySpellID and NS.AcceptSpellID(primarySpellID) and not (issecretvalue and issecretvalue(primarySpellID)) then
		local displayPrimary = NS.GetDisplaySpellID and NS.GetDisplaySpellID(primarySpellID) or primarySpellID
		for i = 1, #rotation do
			local sid = rotation[i]
			if not (issecretvalue and issecretvalue(sid)) then
				if sid == primarySpellID or sid == displayPrimary then
					startIdx = i + 1
					break
				end
			end
		end
	else
		startIdx = 2
	end

	local out = {}
	for i = startIdx, #rotation do
		local sid = rotation[i]
		if NS.AcceptSpellID(sid) then
			out[#out + 1] = sid
			if #out >= maxCount then
				break
			end
		end
	end

	return #out > 0 and out or nil
end

-- Parsed per-spec defensive spell list (comma-separated IDs in Advanced settings).
function NS.GetSpecDefensiveList()
	local specKey = NS.GetSpecKey()
	if not specKey then
		return nil
	end

	local cache = NS.SpecDefensiveCache
	local cached = cache[specKey]
	if cached then
		return cached
	end

	local list = {}
	local cfg = NS.GetSpecConfig(specKey)
	local raw = cfg and cfg.defensiveSpellList
	if NS.ParseSpellIDList then
		list = NS.ParseSpellIDList(raw)
	end

	cache[specKey] = list
	return list
end

-- Health gate for defensives. threshold 0 = always pass. Secret health in combat
-- fails open (show readiness) — we cannot compare secret numbers in tainted code.
function NS.PlayerHealthAtOrBelowThreshold(threshold)
	threshold = threshold or 0
	if threshold <= 0 then
		return true
	end
	if not UnitHealth or not UnitHealthMax then
		return true
	end
	local hp = UnitHealth("player")
	local max = UnitHealthMax("player")
	if issecretvalue and (issecretvalue(hp) or issecretvalue(max)) then
		return true
	end
	if not max or max <= 0 then
		return false
	end
	return (hp / max) * 100 <= threshold
end

-- Whether a configured defensive should pulse the kick-now glow: off cooldown,
-- usable (not greyed unusable), and the per-spec health gate passes.
function NS.ShouldSuggestDefensive(spellID)
	if not spellID then
		return false
	end

	local cfg = NS.GetSpecConfig()
	local threshold = cfg and cfg.defensiveHealthThreshold or 0
	if not NS.PlayerHealthAtOrBelowThreshold(threshold) then
		return false
	end

	local state = NS.GetActionState(spellID, "player")
	if state == "unusable" then
		return false
	end

	return true
end

-- ---------------------------------------------------------------------
-- Action state (range / usability) – ported from tullaRange
--
-- tullaRange operates on action-bar SLOTS via IsUsableAction / IsActionInRange.
-- Our suggestion button is keyed off a spellID instead, so we use the spell
-- equivalents: C_Spell.IsSpellUsable (isUsable, insufficientPower) and
-- C_Spell.IsSpellInRange (true / false / nil). The returned state string maps
-- onto the same buckets tullaRange uses: "normal", "oor", "oom", "unusable".
-- ---------------------------------------------------------------------
function NS.GetActionState(spellID, unit)
	if not spellID then
		return "normal", true, false, false
	end

	-- Usability + power. Default to usable if the API is unavailable so we never
	-- grey out a perfectly castable suggestion on an older client.
	local isUsable, notEnoughMana = true, false
	if C_Spell_IsSpellUsable then
		isUsable, notEnoughMana = C_Spell_IsSpellUsable(spellID)
	end

	-- Range: IsSpellInRange returns true (in range), false (out of range), or nil
	-- (no valid range check – e.g. no target, or a spell with no range). Only an
	-- explicit false counts as out-of-range, exactly like tullaRange.
	local outOfRange = false
	if C_Spell_IsSpellInRange then
		local inRange = C_Spell_IsSpellInRange(spellID, unit)
		-- A secret range result can't be compared; treat it as "no info".
		if not (issecretvalue and issecretvalue(inRange)) then
			outOfRange = inRange == false
		end
	end

	-- Midnight can return secret booleans for usability in combat. Branching on a
	-- secret boolean errors, so when usability is secret we skip the usable/oom/
	-- unusable buckets and fall back to the plain "normal" tint (range still works).
	if issecretvalue and (issecretvalue(isUsable) or issecretvalue(notEnoughMana)) then
		return "normal", true, false, outOfRange
	end

	local state
	if isUsable then
		state = outOfRange and "oor" or "normal"
	else
		state = notEnoughMana and "oom" or "unusable"
	end

	return state, isUsable, notEnoughMana, outOfRange
end
