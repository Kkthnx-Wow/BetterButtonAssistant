local _, NS = ...

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
NS.BarAddonLoaded = false
NS.AddonLookupActionBySlot = {}
NS.AddonLookupButtonByAction = {}
NS.LookupActionBySlot = {}
NS.LookupButtonByAction = {}

NS.keybindCache = {}

function NS.IsRelevantAction(actionType, subType)
	return (actionType == "macro" and subType == "spell") or (actionType == "spell" and subType ~= "assistedcombat")
end

function NS.GetBindingForAction(action)
	if not action then
		return nil
	end

	local key = NS.GetBindingKey(action)
	if not key then
		return nil
	end

	local text = NS.GetBindingText(key, "KEY_")
	if not text or text == "" then
		return nil
	end

	text = text:gsub("Mouse Button ", "MB", 1)
	text = text:gsub("Middle Mouse", "MMB", 1)

	return text
end

function NS.GetButtonFrameByAction(addonAction, defaultAction)
	local buttonName

	if NS.BarAddonLoaded and addonAction then
		buttonName = NS.AddonLookupButtonByAction[addonAction]
		if buttonName and NS._G[buttonName] then
			return NS._G[buttonName]
		end
	end

	buttonName = NS.LookupButtonByAction[defaultAction]
	return buttonName and NS._G[buttonName] or nil
end

function NS.LoadActionSlotMap()
	if NS.C_AddOns_IsAddOnLoaded and NS.C_AddOns_IsAddOnLoaded("Dominos") then
		for slot = 1, 180 do
			local action = "CLICK DominosActionButton" .. slot .. ":HOTKEY"
			NS.AddonLookupActionBySlot[slot] = action
			NS.AddonLookupButtonByAction[action] = "DominosActionButton" .. slot
		end
		NS.BarAddonLoaded = true
	elseif NS.C_AddOns_IsAddOnLoaded and NS.C_AddOns_IsAddOnLoaded("Bartender4") then
		for slot = 1, 180 do
			local action = "CLICK BT4Button" .. slot .. ":Keybind"
			NS.AddonLookupActionBySlot[slot] = action
			NS.AddonLookupButtonByAction[action] = "BT4Button" .. slot
		end
		NS.BarAddonLoaded = true
	end

	for i = 1, #NS.DefaultActionSlotMap do
		local info = NS.DefaultActionSlotMap[i]
		for id = info.start, info.last do
			local index = id - info.start + 1
			local action = info.actionPrefix .. index
			NS.LookupActionBySlot[id] = action
			NS.LookupButtonByAction[action] = info.buttonPrefix .. index
		end
	end
end

function NS.GetKeyBindForSpellID(spellID)
	if not spellID or not NS.C_ActionBar_FindSpellActionButtons then
		return nil
	end

	local cached = NS.keybindCache[spellID]
	if cached ~= nil then
		return cached
	end

	local baseSpellID = NS.FindBaseSpellByID(spellID) or spellID
	local slots = NS.C_ActionBar_FindSpellActionButtons(baseSpellID)
	if not slots then
		NS.keybindCache[spellID] = nil
		return nil
	end

	for i = 1, #slots do
		local slot = slots[i]
		local actionType, _, subType = NS.GetActionInfo(slot)
		if NS.IsRelevantAction(actionType, subType) then
			local defaultAction = NS.LookupActionBySlot[slot]
			local addonAction = NS.BarAddonLoaded and NS.AddonLookupActionBySlot[slot] or nil

			local text = NS.GetBindingForAction(defaultAction)
			if not text and addonAction then
				text = NS.GetBindingForAction(addonAction)
			end

			local buttonFrame = NS.GetButtonFrameByAction(addonAction, defaultAction)
			if buttonFrame and buttonFrame.action == slot and text then
				NS.keybindCache[spellID] = text
				return text
			end
		end
	end

	NS.keybindCache[spellID] = nil
	return nil
end

function NS.WipeKeybindCache()
	for k in NS.pairs(NS.keybindCache) do
		NS.keybindCache[k] = nil
	end
end

-- ---------------------------------------------------------------------
-- Assisted Combat spell list
-- ---------------------------------------------------------------------
function NS.SafeCallAssisted(fn, arg)
	if not fn then
		return false
	end

	local ok, a, b, c, d, e = NS.pcall(fn, arg)
	if ok then
		return true, a, b, c, d, e
	end

	ok, a, b, c, d, e = NS.pcall(fn)
	if ok then
		return true, a, b, c, d, e
	end

	return false
end

function NS.CollectNextSpell()
	local checkVisible = NS.db.checkVisibleButton and true or false

	if NS.C_AssistedCombat_GetNextCastSpell then
		local ok, sid = NS.SafeCallAssisted(NS.C_AssistedCombat_GetNextCastSpell, checkVisible)
		if ok and sid and sid ~= 0 then
			return sid
		end
	end

	return nil
end
