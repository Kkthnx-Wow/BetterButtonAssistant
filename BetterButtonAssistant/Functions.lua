local _, NS = ...

-- File-level locals for hot-path performance (avoids NS.* table lookup overhead).
-- Constants.lua loads before this file, so the cached API refs already exist.
local math_floor = math.floor
local math_ceil = math.ceil
local C_Spell_GetOverrideSpell = NS.C_Spell_GetOverrideSpell
local C_Spell_IsSpellUsable = NS.C_Spell_IsSpellUsable
local C_Spell_IsSpellInRange = NS.C_Spell_IsSpellInRange
local FindSpellOverrideByID = NS.FindSpellOverrideByID
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
	local updatedKeys = NS.UpdatedHotkeys

	-- Hekili uses an 'action' string internally. We will map the ID directly.
	local action = NS.tostring(id)

	if aType == "item" then
		if NS.ItemToAbility[id] then
			action = NS.ItemToAbility[id]
		end
	end

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
			updatedKeys[act] = true
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
	local updatedKeys = NS.UpdatedHotkeys

	for k, v in NS.pairs(keys) do
		NS.wipe(v.console)
		NS.wipe(v.upper)
		NS.wipe(v.lower)
	end
	NS.wipe(updatedKeys)
	NS.wipe(NS.KeybindCache)
	NS.wipe(NS.ActionSlotCache)
	NS.wipe(NS.SpellVariantCache)
	NS.wipe(NS.KeybindTextCache)

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
			NS.StoreKeybindInfo(
				7 + math_floor((i - 73) / 12),
				NS.GetBindingKey("ACTIONBUTTON" .. 1 + (i - 73) % 12),
				NS.GetActionInfo(i)
			)
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
					NS.StoreKeybindInfo(
						math_ceil(i / 12),
						NS._G.ConsolePort:GetFormattedButtonCombination(key, mod),
						action,
						id,
						"cPort"
					)
				end
			end
		end
	end
end

function NS.GetBindingForAction(key, display, i)
	if not key then
		return ""
	end

	-- Map the key (action ID) to the hotkey string
	key = NS.tostring(key)

	if not NS.Hotkeys[key] then
		return ""
	end

	local keys = NS.Hotkeys

	local caps, console = true, false
	-- Simplified display/caps logic since we don't have the full display object here
	if display then
		local queued = (i or 1) > 1 and display.keybindings.separateQueueStyle
		caps = not (queued and display.keybindings.queuedLowercase or display.keybindings.lowercase)
		console = NS._G.ConsolePort ~= nil and display.keybindings.cPortOverride
	end

	local db = console and keys[key].console or (caps and keys[key].upper or keys[key].lower)

	local output, source
	local order = NS.BarOrder["DEFAULT"]

	-- Cache player class once per session; refreshed if class somehow changes.
	local _, class = NS.UnitClass("player")
	if class == "DRUID" then
		local form = NS._G.GetShapeshiftForm()
		if form == 1 then -- Bear
			order = NS.BarOrder["DRUID_BEAR"]
		elseif form == 2 then -- Cat
			if NS._G.IsStealthed() then
				order = NS.BarOrder["DRUID_PROWL"]
			else
				order = NS.BarOrder["DRUID_CAT"]
			end
		elseif form == 3 then -- Travel
			order = NS.BarOrder["DRUID_TRAVEL"]
		elseif form == 4 then -- Moonkin
			order = NS.BarOrder["DRUID_OWL"]
		elseif form == 5 then -- Tree/Resto
			order = NS.BarOrder["DRUID_TREE"]
		end
	elseif class == "ROGUE" then
		if NS._G.IsStealthed() then
			order = NS.BarOrder["ROGUE_STEALTH"]
		end
	end

	for _, n in NS.ipairs(order) do
		output = db[n]
		if output and output ~= "" then
			source = n
			break
		end
	end

	output = output or ""

	if output ~= "" and console then
		local size = output:match("Icons(%d%d)")
		size = NS.tonumber(size)
		if size then
			local margin = NS.math_floor(size * (display and display.keybindings.cPortZoom or 1) * 0.5)
			output = output:gsub(
				":0|t",
				":0:"
					.. size
					.. ":"
					.. size
					.. ":"
					.. margin
					.. ":"
					.. (size - margin)
					.. ":"
					.. margin
					.. ":"
					.. (size - margin)
					.. "|t"
			)
		end
	end

	return output
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

function NS.CollectNextSpell()
	local checkVisible = NS.db.checkVisibleButton and true or false

	-- 1. Main Recommendation (The "One-Punch" logic that worked before)
	if NS.C_AssistedCombat_GetNextCastSpell then
		local ok, sid = NS.SafeCallAssisted(NS.C_AssistedCombat_GetNextCastSpell, checkVisible)
		if ok and sid and sid ~= 0 then
			return sid
		end
	end

	-- 2. Highlights (Cyan highlights from the Assisted Combat menu)
	if NS.C_AssistedCombat_GetRotationSpells then
		local spells = NS.C_AssistedCombat_GetRotationSpells()
		if spells and spells[1] and spells[1] ~= 0 then
			return spells[1]
		end
	end

	-- 3. Last Resort (12.0.0 specific recommendation)
	if NS.C_AssistedCombat_GetActionSpell then
		local sid = NS.C_AssistedCombat_GetActionSpell()
		if sid and sid ~= 0 then
			return sid
		end
	end

	return nil
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
