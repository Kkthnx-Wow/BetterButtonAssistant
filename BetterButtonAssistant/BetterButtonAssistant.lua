-- BetterAssistant
-- Shows Blizzard Assisted Combat recommendations + keybinds (no Ace3)

local ADDON_NAME, NS = ...

-- ---------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------
local addonFrame = NS.CreateFrame("Frame", "BetterAssistantEventFrame")
local frame = NS.CreateFrame("Frame", "BetterAssistantFrame", NS.UIParent, "BackdropTemplate")
NS.frame = frame

frame:SetPoint("CENTER", NS.UIParent, "CENTER", 0, -120)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)

frame:SetScript("OnDragStart", function(self)
	if NS.db.locked then
		return
	end
	if NS.InCombatLockdown and NS.InCombatLockdown() then
		return
	end
	self:StartMoving()
end)

frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
end)

local function CreateSuggestionButton(parent)
	local b = NS.CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetSize(NS.db.buttonSize, NS.db.buttonSize)
	b:SetFrameLevel(parent:GetFrameLevel() + 2)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- Modern HUD Border
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetTexture("Interface/HUD/UIActionBar")
	b.border:SetTexCoord(0.707031, 0.886719, 0.248047, 0.291992)
	b.border:SetPoint("CENTER", b.icon, "CENTER", 0, 0)
	b.border:SetSize(46, 45) -- Default size relative to 40px button, scaler will handle resizing

	b.cooldown = NS.CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints(b.icon)
	b.cooldown:SetFrameLevel(b:GetFrameLevel())

	b.hotkey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall") -- Using a cleaner number font
	b.hotkey:SetPoint("TOPRIGHT", b.icon, "TOPRIGHT", -2, -2)
	b.hotkey:SetJustifyH("RIGHT")
	b.hotkey:SetDrawLayer("OVERLAY", 7)

	b.spellID = nil

	return b
end

local function CreateAvadaIcon(parent, index)
	local b = NS.CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetSize(NS.db.avadaSize, NS.db.avadaSize)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- Avada Border
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetTexture("Interface/HUD/UIActionBar")
	b.border:SetTexCoord(0.707031, 0.886719, 0.248047, 0.291992)
	b.border:SetPoint("CENTER", b.icon, "CENTER", 0, 0)
	b.border:SetSize(46, 45) -- Default size relative to 40px button, scaler will handle resizing

	b.cooldown = NS.CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints(b.icon)
	b.cooldown:SetHideCountdownNumbers(true)
	b.cooldown:SetFrameLevel(b:GetFrameLevel())

	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 0, 0)
	b.count:SetJustifyH("RIGHT")

	return b
end

function NS.UpdateAvadaLayout()
	if not frame.avada then
		frame.avada = NS.CreateFrame("Frame", "BetterAssistantAvadaFrame", frame)
		frame.avada.icons = {}
	end

	local f = frame.avada
	local size = NS.db.avadaSize or 16
	local spacing = NS.db.avadaSpacing or 4
	local offsetY = NS.db.avadaOffsetY or -10
	local showBorder = NS.db.avadaShowBorder

	f:ClearAllPoints()
	f:SetPoint("TOP", frame.button, "BOTTOM", 0, offsetY)
	f:SetSize((size + spacing) * 6 - spacing, size)

	if not f.value then
		f.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		f.value:SetPoint("RIGHT", frame.button, "LEFT", -10, 0)
	end

	for i = 1, 6 do
		local icon = f.icons[i]
		if not icon then
			icon = CreateAvadaIcon(f, i)
			f.icons[i] = icon
		end
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		icon:SetPoint("LEFT", f, "LEFT", (i - 1) * (size + spacing), 0)

		if icon.border then
			local borderSize = size * 46 / 40 -- Maintain same ratio as main button
			icon.border:SetSize(borderSize, borderSize)
			icon.border:SetShown(showBorder)
		end

		icon:SetShown(NS.db.avadaEnabled)
	end
	f:SetShown(NS.db.avadaEnabled)
end

function NS.UpdateAvada()
	if not NS.db.avadaEnabled or not frame.avada then
		if frame.avada then
			frame.avada:Hide()
		end
		return
	end

	local list = NS.GetAvadaTargetList()
	if not list then
		frame.avada:Hide()
		return
	end

	frame.avada:Show()
	local showValue = false
	local tracker = frame.avada

	for i = 1, 6 do
		local icon = tracker.icons[i]
		local data = list[i]
		if data and data.spellID then
			local unit = data.unit
			local aType = data.type
			local id = data.spellID

			local tex = NS.C_Spell_GetSpellTexture(NS.AvadaReplacedTexture[id] or id)
			if aType == "item" then
				tex = NS.C_Item_GetItemIconByID or NS.C_Spell_GetSpellTexture(id)
				if NS.C_Item_GetItemIconByID then
					tex = NS.C_Item_GetItemIconByID(id)
				end
			end
			icon.icon:SetTexture(tex or "Interface/Icons/INV_Misc_QuestionMark")

			local alpha = 1.0
			local countText = ""
			local startTime, duration = 0, 0
			local countColor = { 1, 1, 1 }
			local desaturated = false

			if aType == "buff" or aType == "debuff" then
				local filter = (aType == "debuff") and "HARMFUL" or "HELPFUL"
				local aura, value = NS.GetAuraInfo(unit, id, filter)
				if aura then
					countText = (aura.applications > 1) and aura.applications or ""
					if aura.expirationTime and aura.expirationTime > 0 then
						startTime = aura.expirationTime - aura.duration
						duration = aura.duration
					end
					if NS.AvadaValueSpells[id] and value then
						tracker.value:SetText(NS.FormatNumber(value))
						showValue = true
					end
				else
					desaturated = true
				end
			elseif aType == "cd" then
				local cd = NS.C_Spell_GetSpellCooldown(id)
				local start = cd and cd.startTime
				local dur = cd and cd.duration

				local chargesInfo = NS.C_Spell_GetSpellCharges(id)
				local charges = chargesInfo and chargesInfo.currentCharges
				local maxCharges = chargesInfo and chargesInfo.maxCharges
				local chargeStart = chargesInfo and chargesInfo.cooldownStartTime
				local chargeDur = chargesInfo and chargesInfo.cooldownDuration

				if charges and maxCharges > 1 then
					countText = charges
				end

				if charges and charges > 0 and charges < maxCharges then
					startTime, duration = chargeStart, chargeDur
					countColor = { 0, 1, 0 }
					desaturated = false
				elseif start and dur > 1.5 then
					startTime, duration = start, dur
					countColor = { 1, 1, 1 }
					desaturated = true
				else
					desaturated = false
					if charges and charges == maxCharges then
						countColor = { 1, 0, 0 }
					end
				end
			elseif aType == "item" then
				local count = NS.C_Item_GetItemCount(id)
				countText = (count and count > 1) and count or ""

				local start, dur = NS.C_Item_GetItemCooldown(id)
				if start and dur > 3 then
					startTime, duration = start, dur
					desaturated = true
				end
			end

			icon.icon:SetDesaturated(desaturated)
			icon.count:SetText(countText)
			icon.count:SetTextColor(unpack(countColor))

			if startTime and duration and duration > 0 then
				icon.cooldown:SetReverse(aType == "buff" or aType == "debuff")
				icon.cooldown:SetCooldown(startTime, duration)
				icon.cooldown:Show()
			else
				icon.cooldown:Hide()
			end
			icon:Show()
		else
			icon:Hide()
		end
	end

	if not showValue then
		tracker.value:SetText("")
	end
end

function NS.UpdateLayout()
	local size = NS.db.buttonSize or 40
	local b = frame.button
	if not b then
		b = CreateSuggestionButton(frame)
		frame.button = b
	end

	-- Update Size
	b:SetSize(size, size)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

	-- Update Border Size (approx 1.15 ratio to cover edges)
	if b.border then
		local borderSize = size * 46 / 40
		b.border:SetSize(borderSize, borderSize)
		-- Show/Hide border based on settings
		b.border:SetShown(NS.db.showBorder)
	end

	-- Update Font Size
	local fontPath, _, fontFlags = b.hotkey:GetFont()
	b.hotkey:SetFont(fontPath, NS.db.keybindFontSize or 12, fontFlags)

	-- Update Avada Layout
	NS.UpdateAvadaLayout()

	-- Update Frame properties
	frame:SetSize(size, size)
	frame:SetScale(NS.db.scale or 1.0)

	b:Show()
end

local function UpdateCooldownForSpell(b, spellID)
	if not NS.db.showCooldown or not NS.C_Spell_GetSpellCooldown then
		b.cooldown:Hide()
		return
	end

	local cd = NS.C_Spell_GetSpellCooldown(spellID)
	if cd and cd.startTime and cd.duration then
		b.cooldown:SetDrawEdge(false)
		b.cooldown:SetDrawBling(false)
		b.cooldown:SetHideCountdownNumbers(false)
		b.cooldown:SetCooldown(cd.startTime, cd.duration)
		b.cooldown:Show()
	else
		b.cooldown:Hide()
	end

	-- Update Keybind visibility
	if b.hotkey then
		b.hotkey:SetShown(NS.db.showKeybind)
	end

	-- Update Cooldown visibility
	if b.cooldown then
		b.cooldown:SetDrawBling(NS.db.showCooldown)
		b.cooldown:SetDrawEdge(NS.db.showCooldown)
		b.cooldown:SetSwipeColor(0, 0, 0, NS.db.showCooldown and 0.8 or 0)
	end
end

local ticker
local function StartTicker()
	if ticker then
		return
	end
	local rate = NS.db.updateRate or 0.12
	if rate < 0.05 then
		rate = 0.05
	end

	ticker = NS.C_Timer_NewTicker(rate, NS.UpdateNow)
end

function NS.UpdateVisibility()
	local f = NS.frame
	if not f then
		return
	end

	if not NS.db.enabled then
		f:Hide()
		return
	end

	local inCombat = NS.UnitAffectingCombat("player")
	local inVehicle = NS.UnitInVehicle("player")

	-- Hide in Vehicle check
	if inVehicle and NS.db.hideInVehicle then
		f:Hide()
		return
	end

	-- Only In Combat check
	if NS.db.onlyInCombat and not inCombat then
		f:Hide()
		return
	end

	-- Apply Alpha
	local targetAlpha = inCombat and NS.db.alphaCombat or NS.db.alphaOOC
	f:SetAlpha(targetAlpha)

	-- If we passed checks, show it (UpdateNow will determine if there's a spell to create/show sub-elements)
	f:Show()

	-- Check for availability to start/stop ticker
	if NS.IsAssistedCombatAvailable() then
		StartTicker()
	else
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
	end
end

local function UpdateButton(b, spellID)
	if not spellID then
		b.spellID = nil
		b.icon:SetTexture(nil)
		b.hotkey:SetText("")
		b.cooldown:Hide()
		b:Hide()
		return
	end

	b.spellID = spellID

	if NS.C_Spell_GetSpellTexture then
		b.icon:SetTexture(NS.C_Spell_GetSpellTexture(spellID))
	else
		b.icon:SetTexture(nil)
	end

	if NS.db.showKeybind then
		local text = NS.GetKeyBindForSpellID(spellID) or ""
		b.hotkey:SetText(text)
		b.hotkey:SetShown(text ~= "")
	else
		b.hotkey:SetText("")
		b.hotkey:Hide()
	end

	UpdateCooldownForSpell(b, spellID)
	b:Show()
end

function NS.UpdateNow()
	-- If the frame is hidden (e.g. by UpdateVisibility due to OOC/Vehicle/Disabled),
	-- we don't need to process anything.
	local f = NS.frame
	if not f or not f:IsVisible() then
		return
	end

	local spellID = NS.CollectNextSpell()
	UpdateButton(f.button, spellID)

	-- Update Avada Tracker
	NS.UpdateAvada()
end

local function OnAssistedCombatUpdate()
	if NS.UpdateNow then
		NS.UpdateNow()
	end
end

local function RegisterAssistedCombatEvents()
	if not EventRegistry or not EventRegistry.RegisterCallback then
		return
	end

	-- Blizzard's internal rotation manager events (Patch 11.1.7+)
	EventRegistry:RegisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", OnAssistedCombatUpdate, NS)
	EventRegistry:RegisterCallback("AssistedCombatManager.RotationSpellsUpdated", OnAssistedCombatUpdate, NS)
	EventRegistry:RegisterCallback("AssistedCombatManager.OnSetActionSpell", OnAssistedCombatUpdate, NS)
end

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("UPDATE_BINDINGS")
addonFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
addonFrame:RegisterEvent("SPELLS_CHANGED")
addonFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
addonFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
addonFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
addonFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
addonFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
addonFrame:RegisterEvent("ASSISTED_COMBAT_ACTION_SPELL_CAST")
addonFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
addonFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
addonFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
addonFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
addonFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
addonFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
addonFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
addonFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
addonFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
addonFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
addonFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
addonFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
addonFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
addonFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
addonFrame:RegisterEvent("UNIT_AURA")

local allTimer
local function DelayedUpdateKeybindings()
	if allTimer then
		allTimer:Cancel()
	end
	allTimer = NS.C_Timer_After(0.2, function()
		NS.ReadKeybindings()
		NS.UpdateNow()
		allTimer = nil
	end)
end

addonFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name ~= ADDON_NAME or NS.loaded then
			return
		end
		NS.loaded = true

		BetterButtonAssistantDB = BetterButtonAssistantDB or {}
		NS.db = BetterButtonAssistantDB
		NS.CopyDefaults(NS.db, NS.defaults)

		NS.RegisterSettings() -- Initialize Modern Settings Panel

		RegisterAssistedCombatEvents() -- Hook into Blizzard's internal events

		NS.UpdateLayout()
		NS.UpdateVisibility() -- Call UpdateVisibility after layout
		DelayedUpdateKeybindings() -- Ensure hotkeys are scanned after bars are ready
		return
	end

	-- Any binding/bar changes => wipe cache + refresh (debounced)
	if
		event == "UPDATE_BINDINGS"
		or event == "ACTIONBAR_SLOT_CHANGED"
		or event == "SPELLS_CHANGED"
		or event == "ACTIONBAR_PAGE_CHANGED"
		or event == "UPDATE_BONUS_ACTIONBAR"
		or event == "UPDATE_VEHICLE_ACTIONBAR"
		or event == "UPDATE_OVERRIDE_ACTIONBAR"
		or event == "ACTIONBAR_UPDATE_STATE"
		or event == "PLAYER_TALENT_UPDATE"
		or event == "PLAYER_SPECIALIZATION_CHANGED"
		or event == "UPDATE_SHAPESHIFT_FORM"
		or event == "TRAIT_CONFIG_UPDATED"
		or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
	then
		if
			event == "TRAIT_CONFIG_UPDATED"
			or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
			or event == "PLAYER_SPECIALIZATION_CHANGED"
			or event == "PLAYER_TALENT_UPDATE"
		then
			NS.RefreshAvadaCachedData()
			NS.UpdateAvadaLayout()
		end
		DelayedUpdateKeybindings()
	end

	-- Visibility changes (Combat/Vehicle/Target)
	if
		event == "PLAYER_REGEN_ENABLED"
		or event == "PLAYER_REGEN_DISABLED"
		or event == "UNIT_ENTERED_VEHICLE"
		or event == "UNIT_EXITED_VEHICLE"
		or event == "PLAYER_ENTERING_WORLD"
		or event == "PLAYER_TARGET_CHANGED"
		or event == "UNIT_AURA"
	then
		NS.UpdateVisibility()
		if event == "PLAYER_TARGET_CHANGED" then
			if not NS.WatchUnits["target"] then
				return
			end
			if not NS.WatchTypes["buff"] and not NS.WatchTypes["debuff"] then
				-- Optimization: Target changed only matters for auras if we track target auras
				return
			end
			NS.UpdateAvada()
		elseif event == "UNIT_AURA" then
			local unit = ...
			if unit and NS.WatchUnits[unit] then
				if NS.WatchTypes["buff"] or NS.WatchTypes["debuff"] then
					NS.UpdateAvada()
				end
			end
		elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
			if NS.WatchTypes["cd"] then
				NS.UpdateAvada()
			end
		elseif event == "BAG_UPDATE_COOLDOWN" then
			if NS.WatchTypes["item"] then
				NS.UpdateAvada()
			end
		end
	end
end)
