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
	b.border:SetAtlas("UI-HUD-ActionBar-IconFrame")
	b.border:SetPoint("CENTER")
	b.border:SetSize(46, 46) -- Default size relative to 40px button, scaler will handle resizing

	b.cooldown = NS.CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints()
	b.cooldown:SetFrameLevel(b:GetFrameLevel() + 1)

	b.hotkey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall") -- Using a cleaner number font
	b.hotkey:SetPoint("TOPRIGHT", -2, -2)
	b.hotkey:SetJustifyH("RIGHT")
	b.hotkey:SetDrawLayer("OVERLAY", 7)

	b.spellID = nil
	return b
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
		b.border:SetShown(NS.db.showBorder)
	end

	-- Update Font Size
	local fontPath, _, fontFlags = b.hotkey:GetFont()
	b.hotkey:SetFont(fontPath, NS.db.keybindFontSize or 12, fontFlags)

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

function NS.UpdateVisibility(source)
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
	if not frame:IsVisible() then
		return
	end

	local spellID = NS.CollectNextSpell()
	UpdateButton(frame.button, spellID)
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
addonFrame:RegisterEvent("SPELLS_CHANGED")
addonFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
addonFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
addonFrame:RegisterEvent("UNIT_EXITED_VEHICLE")

addonFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name ~= ADDON_NAME then
			return
		end

		BetterButtonAssistantDB = BetterButtonAssistantDB or {}
		NS.db = BetterButtonAssistantDB
		NS.CopyDefaults(NS.db, NS.defaults)

		NS.LoadActionSlotMap()
		NS.RegisterSettings() -- Initialize Modern Settings Panel

		NS.UpdateLayout()
		NS.UpdateVisibility() -- Call UpdateVisibility after layout
		StartTicker()
		return
	end

	-- Any binding/bar changes => wipe cache + refresh
	if event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" or event == "SPELLS_CHANGED" then
		NS.WipeKeybindCache()
		NS.UpdateNow()
	end

	-- Visibility changes (Combat/Vehicle)
	if
		event == "PLAYER_REGEN_ENABLED"
		or event == "PLAYER_REGEN_DISABLED"
		or event == "UNIT_ENTERED_VEHICLE"
		or event == "UNIT_EXITED_VEHICLE"
		or event == "PLAYER_ENTERING_WORLD"
	then
		NS.UpdateVisibility("Event: " .. event)
	end
end)

addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("UPDATE_BINDINGS")
addonFrame:RegisterEvent("SPELLS_CHANGED")
