local _, NS = ...

-- ---------------------------------------------------------------------
-- Avada Configuration UI
-- ---------------------------------------------------------------------

local EMPTY_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local iconString = "|T%s:18:22:0:0:64:64:5:59:5:59:255:255:255|t"

function NS.SetupAvada()
	if NS.AvadaPanel then
		NS.AvadaPanel:SetShown(not NS.AvadaPanel:IsShown())
		return
	end

	local panel = NS.CreateFrame("Frame", "BetterAssistantAvadaConfig", NS.UIParent, "BackdropTemplate")
	panel:SetSize(720, 310)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("HIGH")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

	-- Simple Backdrop
	panel:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	panel:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
	panel:SetBackdropBorderColor(0.6, 0.6, 0.6)

	NS.AvadaPanel = panel

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 15, -14)
	title:SetText("Avada Tracker Configuration")

	local frame = NS.CreateFrame("Frame", nil, panel, "BackdropTemplate")
	frame:SetSize(710, 260)
	frame:SetPoint("BOTTOM", 0, 8)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
	frame:SetBackdropBorderColor(0.6, 0.6, 0.6)

	local profileButtons = {}
	local prevSpecID = 0
	local currentID = 1
	local currentSpecID
	local spellData = {}

	-- Helper to create button (Modern Atlas version)
	local function CreateAtlasButton(parent, width, height, atlas)
		local b = NS.CreateFrame("Button", nil, parent, "BackdropTemplate")
		b:SetSize(width, height)
		b:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		b:SetBackdropColor(0.09, 0.09, 0.09, 1)
		b:SetBackdropBorderColor(0.6, 0.6, 0.6)
		b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

		if atlas then
			b.Icon = b:CreateTexture(nil, "ARTWORK")
			b.Icon:SetAtlas(atlas)
			b.Icon:SetPoint("TOPLEFT", 4, -4)
			b.Icon:SetPoint("BOTTOMRIGHT", -4, 4)
		end

		return b
	end

	local function updateProfileButtons()
		local activeID = (NS.db.avadaIndices and NS.db.avadaIndices[currentSpecID]) or 1
		if currentSpecID ~= prevSpecID then
			currentID = activeID
			prevSpecID = currentSpecID
		end

		for i = 1, 10 do
			local bu = profileButtons[i]
			if activeID == i then
				bu:SetBackdropColor(0.2, 0.2, 0.2, 0.5)
			else
				bu:SetBackdropColor(0.09, 0.09, 0.09, 1)
			end

			if currentID == i then
				bu:SetBackdropBorderColor(1, 0.8, 0)
			else
				bu:SetBackdropBorderColor(0.6, 0.6, 0.6)
			end
		end
	end

	local function stringParserByIndex(index)
		NS.wipe(spellData)
		local str
		if index == 1 then
			str = NS.AvadaData[currentSpecID]
		else
			str = (NS.db.avadaProfiles[currentSpecID] and NS.db.avadaProfiles[currentSpecID][index]) or ""
		end

		for result in (str or ""):gmatch("[^N]+") do
			local iconIndex, unit, iconType, spellID = result:match("(%d+)Z(%w+)Z(%w+)Z(%d+)")
			if iconIndex then
				iconIndex = NS.tonumber(iconIndex)
				spellData[iconIndex] = { index = iconIndex, unit = unit, type = iconType, spellID = NS.tonumber(spellID) }
			end
		end
	end

	local function updateOptionGroup()
		for i = 1, 6 do
			local bu = frame.buttons[i]
			local data = spellData[i]
			bu.spellID = data and data.spellID
			local spellType = data and data.type

			local texture = EMPTY_ICON
			if bu.spellID then
				if spellType == "item" then
					texture = (NS.C_Item_GetItemIconByID and NS.C_Item_GetItemIconByID(bu.spellID)) or EMPTY_ICON
				else
					texture = (NS.C_Spell_GetSpellTexture and NS.C_Spell_GetSpellTexture(bu.spellID)) or EMPTY_ICON
				end
			end

			bu.spellType = spellType
			bu.Icon:SetTexture(texture or EMPTY_ICON)
			bu.options[1]:SetText(data and data.unit or "player")
			bu.options[2]:SetText(spellType or "buff")
			bu.options[3]:SetText(data and data.spellID or "")
		end
	end

	local function refreshAllFrames()
		local specIndex = NS.GetSpecialization()
		if not specIndex then
			return
		end
		if specIndex > 4 then
			specIndex = 1
		end
		currentSpecID = NS.GetSpecializationInfo(specIndex)

		if not panel:IsShown() then
			return
		end
		updateProfileButtons()
		stringParserByIndex(currentID)
		updateOptionGroup()
	end

	local function buttonSelected(self)
		currentID = self:GetID()
		refreshAllFrames()
	end

	for i = 1, 10 do
		local bu = NS.CreateFrame("Button", nil, panel, "BackdropTemplate")
		bu:SetSize(28, 28)
		bu:SetPoint("TOPLEFT", 210 + (i - 1) * 31, -11)
		bu:SetID(i)
		bu:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		bu:SetBackdropColor(0.09, 0.09, 0.09, 1)
		bu:SetBackdropBorderColor(0.6, 0.6, 0.6)
		bu:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

		local text = bu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("CENTER")
		text:SetText(i)

		bu:SetScript("OnClick", buttonSelected)
		profileButtons[i] = bu
	end

	local close = CreateAtlasButton(panel, 22, 22, "common-icon-redx")
	close:SetPoint("TOPRIGHT", -12, -14)
	close:SetScript("OnClick", function()
		panel:Hide()
	end)

	-- Action Buttons
	local undo = CreateAtlasButton(panel, 22, 22, "common-icon-undo")
	undo:SetPoint("RIGHT", close, "LEFT", -6, 0)

	local save = CreateAtlasButton(panel, 22, 22, "common-icon-checkmark")
	save:SetPoint("RIGHT", undo, "LEFT", -6, 0)

	local load = CreateAtlasButton(panel, 22, 22, "auctionhouse-icon-clock")
	load:SetPoint("RIGHT", save, "LEFT", -6, 0)

	local import = CreateAtlasButton(panel, 22, 22, "common-icon-rotateright")
	import.Icon:SetRotation(math.pi)
	import:SetPoint("RIGHT", load, "LEFT", -15, 0)

	local export = CreateAtlasButton(panel, 22, 22, "common-icon-rotateleft")
	export.Icon:SetRotation(math.pi)
	export:SetPoint("RIGHT", import, "LEFT", -6, 0)

	load:SetScript("OnClick", function()
		if currentID ~= 1 and NS.db.avadaProfiles[currentSpecID] and NS.db.avadaProfiles[currentSpecID][currentID] then
			NS.db.avadaIndices[currentSpecID] = currentID
		else
			NS.db.avadaIndices[currentSpecID] = nil
		end
		NS.RefreshAvadaCachedData()
		if NS.UpdateNow then
			NS.UpdateNow()
		end
		updateProfileButtons()
	end)

	save:SetScript("OnClick", function()
		if currentID == 1 then
			return
		end
		local str = ""
		for i = 1, 6 do
			local unitStr = frame.buttons[i].options[1]:GetText()
			local typeStr = frame.buttons[i].options[2]:GetText()
			local spellID = frame.buttons[i].options[3]:GetText()
			if unitStr ~= "" and typeStr ~= "" and spellID ~= "" then
				str = str .. i .. "Z" .. unitStr .. "Z" .. typeStr .. "Z" .. spellID .. "N"
			end
		end
		if not NS.db.avadaProfiles[currentSpecID] then
			NS.db.avadaProfiles[currentSpecID] = {}
		end
		NS.db.avadaProfiles[currentSpecID][currentID] = str ~= "" and str or nil

		if (NS.db.avadaIndices[currentSpecID] or 1) == currentID then
			NS.RefreshAvadaCachedData()
			if NS.UpdateNow then
				NS.UpdateNow()
			end
		end
	end)

	undo:SetScript("OnClick", function()
		if currentID == 1 then
			return
		end
		for i = 1, 6 do
			frame.buttons[i].Icon:SetTexture(EMPTY_ICON)
			frame.buttons[i].options[1]:SetText("player")
			frame.buttons[i].options[2]:SetText("buff")
			frame.buttons[i].options[3]:SetText("")
		end
	end)

	-- Popups
	StaticPopupDialogs["BETTERASSISTANT_AVADA_EXPORT"] = {
		text = "Avada Export (Ctrl+C to copy)",
		button1 = OKAY,
		OnShow = function(self)
			local text
			if currentID == 1 then
				text = NS.AvadaData[currentSpecID]
			else
				text = (NS.db.avadaProfiles[currentSpecID] and NS.db.avadaProfiles[currentSpecID][currentID]) or ""
			end
			self.EditBox:SetText(text or "")
			self.EditBox:HighlightText()
		end,
		hasEditBox = 1,
		editBoxWidth = 250,
		whileDead = 1,
		hideOnEscape = 1,
	}

	StaticPopupDialogs["BETTERASSISTANT_AVADA_IMPORT"] = {
		text = "Avada Import (Ctrl+V to paste)",
		button1 = OKAY,
		button2 = CANCEL,
		OnAccept = function(self)
			if currentID == 1 then
				return
			end
			local text = self.EditBox:GetText()
			if not text:match("(%d+)Z(%w+)Z(%w+)Z(%d+)") then
				return
			end

			if not NS.db.avadaProfiles[currentSpecID] then
				NS.db.avadaProfiles[currentSpecID] = {}
			end
			NS.db.avadaProfiles[currentSpecID][currentID] = text
			refreshAllFrames()
		end,
		hasEditBox = 1,
		editBoxWidth = 250,
		whileDead = 1,
		hideOnEscape = 1,
	}

	export:SetScript("OnClick", function()
		StaticPopup_Show("BETTERASSISTANT_AVADA_EXPORT")
	end)
	import:SetScript("OnClick", function()
		StaticPopup_Show("BETTERASSISTANT_AVADA_IMPORT")
	end)

	-- Tooltips
	local function AddTooltip(button, text)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(text)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	AddTooltip(load, "Load Profile")
	AddTooltip(save, "Save Profile")
	AddTooltip(undo, "Clear Slots")
	AddTooltip(export, "Export Profile")
	AddTooltip(import, "Import Profile")

	-- Options Components
	local function CreateSimpleDropdown(parent, title, options, width, height)
		local f = NS.CreateFrame("Frame", nil, parent, "BackdropTemplate")
		f:SetSize(width, height)
		f:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		f:SetBackdropColor(0.09, 0.09, 0.09, 1)
		f:SetBackdropBorderColor(0.6, 0.6, 0.6)

		local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("CENTER")
		f.Text = text

		local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("BOTTOM", f, "TOP", 0, 5)
		label:SetTextColor(1, 0.8, 0)
		label:SetText(title)

		f:SetScript("OnMouseDown", function()
			local current = text:GetText()
			local nextOpt = options[1]
			for i, v in NS.ipairs(options) do
				if v == current then
					nextOpt = options[i + 1] or options[1]
					break
				end
			end
			text:SetText(nextOpt)
		end)

		function f:SetText(t)
			text:SetText(t)
		end
		function f:GetText()
			return text:GetText()
		end

		return f
	end

	local function CreateSimpleEditbox(parent, title, width, height)
		local eb = NS.CreateFrame("EditBox", nil, parent, "BackdropTemplate")
		eb:SetSize(width, height)
		eb:SetAutoFocus(false)
		eb:SetFontObject("GameFontHighlightSmall")
		eb:SetJustifyH("CENTER")
		eb:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		eb:SetBackdropColor(0.09, 0.09, 0.09, 1)
		eb:SetBackdropBorderColor(0.6, 0.6, 0.6)
		eb:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
		end)
		eb:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
		end)

		local label = eb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("BOTTOM", eb, "TOP", 0, 5)
		label:SetTextColor(1, 0.8, 0)
		label:SetText(title)

		return eb
	end

	local unitOptions = { "player", "target", "pet" }
	local typeOptions = { "buff", "debuff", "cd", "item" }

	local function receiveCursor(button)
		if currentID == 1 then
			return
		end
		local infoType, itemID, _, spellID = GetCursorInfo()
		local id = infoType == "item" and itemID or infoType == "spell" and spellID
		if id then
			ClearCursor()
			button.spellID = id
			button.spellType = (infoType == "item") and "item" or "cd"
			button.Icon:SetTexture((infoType == "item") and (NS.C_Item_GetItemIconByID and NS.C_Item_GetItemIconByID(id)) or (NS.C_Spell_GetSpellTexture and NS.C_Spell_GetSpellTexture(id)))
			button.options[1]:SetText("player")
			button.options[2]:SetText(button.spellType)
			button.options[3]:SetText(id)
		end
	end

	frame.buttons = {}
	for i = 1, 6 do
		local bu = NS.CreateFrame("Button", nil, frame, "BackdropTemplate")
		bu:SetSize(50, 50)
		bu:SetPoint("TOPLEFT", 50 + (i - 1) * 112, -10)
		bu:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		bu:SetBackdropColor(0.09, 0.09, 0.09, 1)
		bu:SetBackdropBorderColor(0.6, 0.6, 0.6)

		bu.Icon = bu:CreateTexture(nil, "ARTWORK")
		bu.Icon:SetAllPoints()
		bu.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		bu.border = bu:CreateTexture(nil, "OVERLAY")
		bu.border:SetTexture("Interface/HUD/UIActionBar")
		bu.border:SetTexCoord(0.707031, 0.886719, 0.248047, 0.291992)
		bu.border:SetPoint("CENTER", bu.Icon, "CENTER", 0, 0)
		bu.border:SetSize(50 * 46 / 40, 50 * 45 / 40)

		bu:SetScript("OnMouseDown", receiveCursor)
		bu:SetScript("OnReceiveDrag", receiveCursor)

		bu.options = {}
		bu.options[1] = CreateSimpleDropdown(bu, "Unit", unitOptions, 80, 25)
		bu.options[1]:SetPoint("TOP", bu, "BOTTOM", 0, -32)

		bu.options[2] = CreateSimpleDropdown(bu, "Type", typeOptions, 80, 25)
		bu.options[2]:SetPoint("TOP", bu.options[1], "BOTTOM", 0, -32)

		bu.options[3] = CreateSimpleEditbox(bu, "ID", 80, 25)
		bu.options[3]:SetPoint("TOP", bu.options[2], "BOTTOM", 0, -32)

		frame.buttons[i] = bu
	end

	panel:SetScript("OnShow", refreshAllFrames)
	refreshAllFrames()
end
