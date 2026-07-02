local ADDON_NAME, NS = ...

local math_floor = NS.math_floor

-- ---------------------------------------------------------------------
-- Shared setting callbacks. These are the handful of refresh routines every
-- control re-runs on change; defined once so the registrations below don't each
-- carry an identical closure. All are guarded because the NS.* update functions
-- live in BetterButtonAssistant.lua, which loads after this file.
-- ---------------------------------------------------------------------
local function cbNow()
	if NS.UpdateNow then
		NS.UpdateNow()
	end
end

local function cbLayout()
	if NS.UpdateLayout then
		NS.UpdateLayout()
	end
end

local function cbVisibility()
	if NS.UpdateVisibility then
		NS.UpdateVisibility()
	end
end

-- Update-rate sliders: drop the running ticker so UpdateVisibility restarts it at
-- the new rate.
local function cbRestartTicker()
	if NS.ticker then
		NS.ticker:Cancel()
		NS.ticker = nil
	end
	cbVisibility()
end

-- Slider label formatters (the "Right" value shown next to the slider).
local function fmtPx(v)
	return v .. "px"
end
local function fmtPt(v)
	return v .. "pt"
end
local function fmtPctRaw(v) -- the value is already a percent (0–100)
	return v .. "%"
end
local function fmtPct100(v) -- the value is a 0–1 fraction shown as a percent
	return math_floor(v * 100) .. "%"
end
local function fmtMs(v)
	return math_floor(v * 1000) .. "ms"
end
local function fmtNum(v)
	return tostring(v)
end

-- ---------------------------------------------------------------------
-- Settings Registration (Modern UI)
-- ---------------------------------------------------------------------

local function CreateSettingsEditBox(parent, width, height, numeric)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetAutoFocus(false)
	box:SetSize(width or 120, height or 24)
	-- Numeric for single-ID inputs; free text for comma-separated lists.
	box:SetNumeric(numeric ~= false)
	box:SetTextInsets(6, 6, 0, 0)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	return box
end

local function CreateSettingsButton(parent, text, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 70, 22)
	button:SetText(text)
	return button
end

local function ParseSpellList(raw)
	if NS.ParseSpellIDList then
		return NS.ParseSpellIDList(raw)
	end
	return {}, {}
end

local function FormatSpellList(ids)
	if NS.FormatSpellIDList then
		return NS.FormatSpellIDList(ids)
	end
	return ""
end

local function InvalidateRangeList()
	if NS.SpecSpellRangeCache then
		NS.wipe(NS.SpecSpellRangeCache)
	end
	if NS.UpdateNow then
		NS.UpdateNow()
	end
end

local function InvalidateDefensiveList()
	if NS.SpecDefensiveCache then
		NS.wipe(NS.SpecDefensiveCache)
	end
	if NS.UpdateDefensives then
		NS.UpdateDefensives()
	elseif NS.UpdateNow then
		NS.UpdateNow()
	end
end

local RefreshAdvancedCanvas

-- Modern MinimalScrollBar scroll container (ScrollFrameTemplate + ScrollFrame_OnLoad).
-- Falls back to the legacy UIPanelScrollFrameTemplate if the template is unavailable.
local function CreateModernScrollFrame(parent, inset)
	inset = inset or 4
	local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
	if not (scroll and scroll.ScrollBar and ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar) then
		scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	end
	scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
	scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
	if scroll.ScrollBar and scroll.ScrollBar.SetHideIfUnscrollable then
		scroll.ScrollBar:SetHideIfUnscrollable(true)
	end
	return scroll
end

local function SyncAdvancedContentWidth(canvas)
	if not (canvas and canvas.scroll and canvas.content) then
		return
	end
	local w = canvas.scroll:GetWidth()
	if w and w > 0 then
		canvas.content:SetWidth(math.max(w - 16, 480))
	end
end

local function UpdateAdvancedContentHeight(canvas)
	if not (canvas and canvas.content and canvas.layoutBottom) then
		return
	end
	local content = canvas.content
	local bottom = canvas.layoutBottom
	local top = content:GetTop()
	local low = bottom:GetBottom()
	if top and low then
		content:SetHeight(math.max(top - low + 32, 1))
	end
	local scroll = canvas.scroll
	if scroll and scroll.ScrollBar and scroll.ScrollBar.Update then
		scroll.ScrollBar:Update()
	end
end

local function UpdateSpellInputDisplay(widget, spellID)
	local id, text, valid, texture = NS.ValidateSpellID(spellID)
	widget.spellID = id
	widget.box:SetText(id > 0 and NS.tostring(id) or "")
	widget.status:SetText(text)
	if texture then
		widget.icon:SetTexture(texture)
		widget.icon:Show()
	else
		widget.icon:Hide()
	end
	if id <= 0 then
		widget.status:SetTextColor(0.65, 0.65, 0.65)
	elseif valid then
		widget.status:SetTextColor(0.4, 1, 0.4)
	else
		widget.status:SetTextColor(1, 0.4, 0.4)
	end
end

-- Reads a spell or item off the cursor and hands its ID to onDropped.
-- GetCursorInfo for a spell returns "spell", spellIndex, bookType, spellID.
-- GetCursorInfo for an item returns "item", itemID, itemLink.
local function HandleCursorDrop(onDropped, isItem)
	if not GetCursorInfo then
		return false
	end
	local kind, arg2, _, arg4 = GetCursorInfo()
	if isItem then
		if kind == "item" and arg2 then
			if ClearCursor then
				ClearCursor()
			end
			onDropped(math_floor(NS.tonumber(arg2) or 0))
			return true
		end
	else
		if kind == "spell" and arg4 then
			if ClearCursor then
				ClearCursor()
			end
			onDropped(math_floor(NS.tonumber(arg4) or 0))
			return true
		end
	end
	return false
end

-- Makes a frame a drop target for spells or items.
local function AddDropTarget(frame, onDropped, isItem, alsoMouseUp)
	frame:EnableMouse(true)
	frame:SetScript("OnReceiveDrag", function()
		HandleCursorDrop(onDropped, isItem)
	end)
	if alsoMouseUp then
		frame:HookScript("OnMouseUp", function()
			HandleCursorDrop(onDropped, isItem)
		end)
	end
end

local function AddSpellDropTarget(frame, onSpell, alsoMouseUp)
	return AddDropTarget(frame, onSpell, false, alsoMouseUp)
end

local function CreateSpellInput(parent, width, onApply)
	local widget = CreateFrame("Frame", nil, parent)
	widget:SetSize(width or 520, 28)

	widget.box = CreateSettingsEditBox(widget, 110, 24)
	widget.box:SetPoint("LEFT")

	widget.apply = CreateSettingsButton(widget, "Apply", 56)
	widget.apply:SetPoint("LEFT", widget.box, "RIGHT", 8, 0)

	widget.clear = CreateSettingsButton(widget, "Clear", 54)
	widget.clear:SetPoint("LEFT", widget.apply, "RIGHT", 6, 0)

	widget.icon = widget:CreateTexture(nil, "ARTWORK")
	widget.icon:SetSize(22, 22)
	widget.icon:SetPoint("LEFT", widget.clear, "RIGHT", 10, 0)
	widget.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	widget.icon:Hide()

	widget.status = widget:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	widget.status:SetPoint("LEFT", widget.icon, "RIGHT", 8, 0)
	widget.status:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
	widget.status:SetJustifyH("LEFT")
	widget.status:SetText("None")

	local function ApplyValue(value)
		local id = math_floor(NS.tonumber(value) or 0)
		onApply(id)
		UpdateSpellInputDisplay(widget, id)
	end

	-- Drag a spell onto the row (or its box) to fill the ID automatically.
	local function OnSpellDropped(id)
		ApplyValue(id)
		widget.box:SetText(tostring(id))
	end
	AddSpellDropTarget(widget, OnSpellDropped, true)
	AddSpellDropTarget(widget.box, OnSpellDropped)

	widget.box:SetScript("OnEnterPressed", function(self)
		ApplyValue(self:GetText())
		self:ClearFocus()
	end)
	widget.apply:SetScript("OnClick", function()
		ApplyValue(widget.box:GetText())
	end)
	widget.clear:SetScript("OnClick", function()
		ApplyValue(0)
	end)
	widget.SetSpellID = UpdateSpellInputDisplay

	return widget
end

local function SetRangeEditorStatus(editor, text, r, g, b)
	editor.status:SetText(text or "")
	editor.status:SetTextColor(r or 0.65, g or 0.65, b or 0.65)
end

local function CreateSpellRow(parent, editor, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(500, 26)
	row:SetPoint("TOPLEFT", 0, -((index - 1) * 28))

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(22, 22)
	row.icon:SetPoint("LEFT", 2, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -70, 0)
	row.text:SetJustifyH("LEFT")

	row.remove = CreateSettingsButton(row, "Remove", 64)
	row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.remove:SetScript("OnClick", function(self)
		editor:RemoveSpellID(self:GetParent().spellID)
	end)

	return row
end

local function CreateSpellListEditor(parent, width, specField, invalidateFn, emptyHint, configGetter, validateFn, isItem)
	specField = specField or "spellRangeList"
	invalidateFn = invalidateFn or InvalidateRangeList
	emptyHint = emptyHint or "Empty: uses the suggested spell. Drag a spell here to add one."
	configGetter = configGetter or function()
		return NS.GetSpecConfig and NS.GetSpecConfig()
	end
	validateFn = validateFn or NS.ValidateSpellID

	local editor = CreateFrame("Frame", nil, parent)
	-- Start compact; SetSpellList auto-resizes to fit content.
	editor:SetSize(width or 540, 35)
	editor.rows = {}

	editor.addBox = CreateSettingsEditBox(editor, 150, 24, false)
	editor.addBox:SetPoint("TOPLEFT", 0, 0)
	editor.addBox:SetScript("OnEnterPressed", function(self)
		editor:AddFromInput()
		self:ClearFocus()
	end)

	editor.addButton = CreateSettingsButton(editor, "Add", 54)
	editor.addButton:SetPoint("LEFT", editor.addBox, "RIGHT", 8, 0)
	editor.addButton:SetScript("OnClick", function()
		editor:AddFromInput()
	end)

	editor.clearButton = CreateSettingsButton(editor, "Clear List", 78)
	editor.clearButton:SetPoint("LEFT", editor.addButton, "RIGHT", 6, 0)
	editor.clearButton:SetScript("OnClick", function()
		local cfg = configGetter()
		if cfg then
			cfg[specField] = ""
			invalidateFn()
		end
		RefreshAdvancedCanvas(editor.canvas)
	end)

	editor.status = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	editor.status:SetPoint("LEFT", editor.clearButton, "RIGHT", 10, 0)
	editor.status:SetPoint("RIGHT", editor, "RIGHT", 0, 0)
	editor.status:SetJustifyH("LEFT")

	editor.scroll = CreateModernScrollFrame(editor, 0)
	editor.scroll:SetPoint("TOPLEFT", 0, -34)
	editor.scroll:SetPoint("BOTTOMRIGHT", 0, 0)

	editor.content = CreateFrame("Frame", nil, editor.scroll)
	editor.content:SetSize((width or 540) - 8, 1)
	editor.scroll:SetScrollChild(editor.content)

	function editor:SetSpellList(raw)
		local ids, invalid = ParseSpellList(raw)
		local rowH = 28
		self.content:SetHeight(math.max(1, #ids * rowH))
		-- Auto-resize the editor: compact when empty, up to 5 visible rows then scrolls.
		-- Layout: 34px for the input bar row + scroll area + 2px bottom pad.
		local visRows = #ids > 0 and math.min(#ids, 5) or 0
		self:SetHeight(34 + visRows * rowH + 2)

		for i = 1, #ids do
			local row = self.rows[i]
			if not row then
				row = CreateSpellRow(self.content, self, i)
				self.rows[i] = row
			end

			local id, text, valid, texture = validateFn(ids[i])
			row.spellID = id
			row.text:SetText(text)
			if valid then
				if text:find("not flagged as defensive", 1, true) then
					row.text:SetTextColor(1, 0.75, 0.3)
				else
					row.text:SetTextColor(1, 1, 1)
				end
			else
				row.text:SetTextColor(1, 0.45, 0.45)
			end
			if texture then
				row.icon:SetTexture(texture)
				row.icon:Show()
			else
				row.icon:Hide()
			end
			row:Show()
		end
		for i = #ids + 1, #self.rows do
			self.rows[i]:Hide()
		end

		if invalid and #invalid > 0 then
			SetRangeEditorStatus(self, "Ignored invalid token(s): " .. table.concat(invalid, ", "), 1, 0.45, 0.45)
		elseif #ids == 0 then
			SetRangeEditorStatus(self, emptyHint, 0.65, 0.65, 0.65)
		else
			local unitText = isItem and "item(s)" or "spell(s)"
			SetRangeEditorStatus(self, #ids .. " " .. unitText .. " configured.", 0.4, 1, 0.4)
		end
		if self.canvas then
			UpdateAdvancedContentHeight(self.canvas)
		end
		if self.scroll and self.scroll.ScrollBar and self.scroll.ScrollBar.Update then
			self.scroll.ScrollBar:Update()
		end
	end

	-- Merges ids into the current spec list (skipping duplicates) and refreshes.
	-- Returns the number of newly-added IDs.
	function editor:AddSpellIDs(ids)
		if not ids or #ids == 0 then
			return 0
		end

		local cfg = configGetter()
		if not cfg then
			return 0
		end

		local current = ParseSpellList(cfg[specField] or "")
		local seen = {}
		for i = 1, #current do
			seen[current[i]] = true
		end

		local added = 0
		for i = 1, #ids do
			if ids[i] and ids[i] > 0 and not seen[ids[i]] then
				current[#current + 1] = ids[i]
				seen[ids[i]] = true
				added = added + 1
			end
		end

		if added > 0 then
			cfg[specField] = FormatSpellList(current)
			invalidateFn()
			RefreshAdvancedCanvas(self.canvas)
		end
		return added
	end

	function editor:AddFromInput()
		local ids, invalid = ParseSpellList(self.addBox:GetText())
		if #ids == 0 then
			local dragText = isItem and "item" or "spell"
			SetRangeEditorStatus(self, "Enter " .. dragText .. " IDs, or drag an " .. dragText .. " here.", 1, 0.45, 0.45)
			return
		end

		self:AddSpellIDs(ids)
		self.addBox:SetText("")

		if invalid and #invalid > 0 then
			SetRangeEditorStatus(self, "Added valid IDs; ignored: " .. table.concat(invalid, ", "), 1, 0.65, 0.25)
		end
	end

	function editor:AddDroppedSpell(id)
		if not id or id <= 0 then
			return
		end
		if self:AddSpellIDs({ id }) > 0 then
			local _, text = validateFn(id)
			SetRangeEditorStatus(self, "Added " .. (text or id) .. ".", 0.4, 1, 0.4)
		else
			local labelText = isItem and "item" or "spell"
			SetRangeEditorStatus(self, "That " .. labelText .. " is already in the list.", 1, 0.65, 0.25)
		end
	end

	function editor:RemoveSpellID(spellID)
		local cfg = configGetter()
		if not cfg then
			return
		end

		local ids = ParseSpellList(cfg[specField] or "")
		local nextIDs = {}
		for i = 1, #ids do
			if ids[i] ~= spellID then
				nextIDs[#nextIDs + 1] = ids[i]
			end
		end
		cfg[specField] = FormatSpellList(nextIDs)
		invalidateFn()
		RefreshAdvancedCanvas(self.canvas)
	end

	-- Drag a spell or item from the spellbook/action bars onto any part of the editor to add it.
	local function OnDropped(id)
		editor:AddDroppedSpell(id)
	end
	AddDropTarget(editor, OnDropped, isItem, true)
	AddDropTarget(editor.scroll, OnDropped, isItem, true)
	AddDropTarget(editor.content, OnDropped, isItem, true)
	AddDropTarget(editor.addBox, OnDropped, isItem)

	return editor
end

local function GetAdvancedCanvasSpecText()
	local label = NS.GetSpecDisplayName and NS.GetSpecDisplayName()
	if not label then
		return "No active specialization."
	end
	return "Current spec: " .. label
end

RefreshAdvancedCanvas = function(canvas)
	if not canvas then
		return
	end

	local cfg = NS.GetSpecConfig and NS.GetSpecConfig()
	if canvas.specText then
		canvas.specText:SetText(GetAdvancedCanvasSpecText())
	end
	if canvas.movingEnabled then
		canvas.movingEnabled:SetChecked(cfg and cfg.movingOverrideEnabled or false)
	end
	if canvas.movingSpellInput then
		canvas.movingSpellInput:SetSpellID((cfg and cfg.movingOverrideSpellID) or 0)
	end
	if canvas.rangeEditor then
		canvas.rangeEditor:SetSpellList((cfg and cfg.spellRangeList) or "")
	end
	if canvas.defensiveEditor then
		canvas.defensiveEditor:SetSpellList((cfg and cfg.defensiveSpellList) or "")
	end
	if canvas.trinketBlacklistEditor then
		canvas.trinketBlacklistEditor:SetSpellList((NS.db and NS.db.trinketBlacklist) or "")
	end
	if canvas.defensiveThreshold then
		canvas.defensiveThreshold:SetValue((cfg and cfg.defensiveHealthThreshold) or 0)
	end
	SyncAdvancedContentWidth(canvas)
	UpdateAdvancedContentHeight(canvas)
end

local function RegisterAdvancedCanvas(category)
	if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
		return
	end

	local canvas = CreateFrame("Frame")
	canvas.scroll = CreateModernScrollFrame(canvas, 8)
	canvas.content = CreateFrame("Frame", nil, canvas.scroll)
	canvas.content:SetWidth(580)
	canvas.content:SetHeight(1)
	canvas.scroll:SetScrollChild(canvas.content)
	canvas.scroll:SetScript("OnSizeChanged", function()
		SyncAdvancedContentWidth(canvas)
	end)

	local content = canvas.content
	local MARGIN = 16   -- left edge indent

	-- ─── Shared layout helpers ───────────────────────────────────────────────

	-- Thin horizontal rule; drawn from the left margin to the right edge.
	local function Divider(anchor, yOff)
		local line = content:CreateTexture(nil, "ARTWORK")
		line:SetHeight(1)
		line:SetColorTexture(1, 1, 1, 0.08)
		line:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, yOff or -10)
		line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -MARGIN, yOff or -10)
		return line
	end

	-- Gold section header + optional one-line body note.
	local function Section(anchor, yOff, title, note)
		local hdr = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		hdr:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOff or -12)
		hdr:SetTextColor(0.93, 0.82, 0.35)
		hdr:SetText(title)
		if note then
			local body = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			body:SetPoint("TOPLEFT",  hdr, "BOTTOMLEFT", 0, -4)
			body:SetPoint("TOPRIGHT", content, "TOPRIGHT", -MARGIN, 0)
			body:SetJustifyH("LEFT")
			body:SetWordWrap(true)
			body:SetTextColor(0.65, 0.65, 0.65)
			body:SetText(note)
			return hdr, body
		end
		return hdr
	end

	-- ─── Title block ─────────────────────────────────────────────────────────

	local titleFS = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	titleFS:SetPoint("TOPLEFT", content, "TOPLEFT", MARGIN, -14)
	titleFS:SetTextColor(0.93, 0.82, 0.35)
	titleFS:SetText("Advanced")

	canvas.specText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	canvas.specText:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -4)
	canvas.specText:SetTextColor(0.55, 0.75, 1.0)

	local div0 = Divider(canvas.specText, -8)

	-- ─── Moving Override ──────────────────────────────────────────────────────

	local movHdr, movNote = Section(div0, -10,
		"MOVING OVERRIDE",
		"Replace cast-time suggestions with an instant fallback while you are moving. Instant suggestions are kept as-is.")

	canvas.movingEnabled = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	canvas.movingEnabled:SetPoint("TOPLEFT", movNote, "BOTTOMLEFT", -2, -8)
	canvas.movingEnabled.Text:SetText("Enable for this spec")
	canvas.movingEnabled:SetScript("OnClick", function(self)
		local cfg = NS.GetSpecConfig and NS.GetSpecConfig()
		if cfg then
			cfg.movingOverrideEnabled = self:GetChecked() and true or false
			if NS.UpdateNow then NS.UpdateNow() end
		end
	end)

	local spellLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	spellLabel:SetPoint("TOPLEFT", canvas.movingEnabled, "BOTTOMLEFT", 4, -10)
	spellLabel:SetText("Fallback Spell:")

	canvas.movingSpellInput = CreateSpellInput(content, 490, function(spellID)
		local cfg = NS.GetSpecConfig and NS.GetSpecConfig()
		if cfg then
			cfg.movingOverrideSpellID = spellID
			if NS.UpdateNow then NS.UpdateNow() end
		end
	end)
	canvas.movingSpellInput:SetPoint("LEFT", spellLabel, "RIGHT", 8, 0)

	local div1 = Divider(spellLabel, -8)

	-- ─── Spell Range List ─────────────────────────────────────────────────────

	local _, rangeNote = Section(div1, -10,
		"SPELL RANGE LIST  ·  Per Spec",
		"Overrides the Target Range readout color for this spec. Green = target in range of any listed spell; red = out of range. Leave empty to use the suggested spell automatically.")

	local rangeAddLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	rangeAddLabel:SetPoint("TOPLEFT", rangeNote, "BOTTOMLEFT", 0, -10)
	rangeAddLabel:SetText("Add Spell ID(s):")

	canvas.rangeEditor = CreateSpellListEditor(content, 560)
	canvas.rangeEditor.canvas = canvas
	canvas.rangeEditor:SetPoint("TOPLEFT", rangeAddLabel, "BOTTOMLEFT", 0, -6)

	local div2 = Divider(canvas.rangeEditor, -8)

	-- ─── Personal Defensives ─────────────────────────────────────────────────

	local _, defNote = Section(div2, -10,
		"PERSONAL DEFENSIVES  ·  Per Spec",
		"Defensive cooldowns shown as companion icons, in priority order (top = used first). Set a health threshold so the icon only glows when you are at or below that percent. 0 = always glow when ready. Secret health values in combat fail open (always glow).")

	local defAddLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	defAddLabel:SetPoint("TOPLEFT", defNote, "BOTTOMLEFT", 0, -10)
	defAddLabel:SetText("Defensive Spell IDs:")

	canvas.defensiveEditor = CreateSpellListEditor(
		content, 560,
		"defensiveSpellList", InvalidateDefensiveList,
		"Empty: drag or enter defensive spell IDs for this spec.",
		nil, NS.ValidateDefensiveSpellID
	)
	canvas.defensiveEditor.canvas = canvas
	canvas.defensiveEditor:SetPoint("TOPLEFT", defAddLabel, "BOTTOMLEFT", 0, -6)

	-- Threshold: single inline row — label | slider | live value label | hint
	local threshLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	threshLabel:SetPoint("TOPLEFT", canvas.defensiveEditor, "BOTTOMLEFT", 0, -12)
	threshLabel:SetText("Glow at health ≤")

	canvas.defensiveThreshold = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
	canvas.defensiveThreshold:SetPoint("LEFT", threshLabel, "RIGHT", 10, 2)
	canvas.defensiveThreshold:SetWidth(160)
	canvas.defensiveThreshold:SetMinMaxValues(0, 100)
	canvas.defensiveThreshold:SetValueStep(5)
	canvas.defensiveThreshold:SetObeyStepOnDrag(true)
	-- Hide the template's built-in Low/High/Value labels; we draw them inline.
	if canvas.defensiveThreshold.Low   then canvas.defensiveThreshold.Low:SetText("0")   end
	if canvas.defensiveThreshold.High  then canvas.defensiveThreshold.High:SetText("100") end

	local threshValueFS = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	threshValueFS:SetPoint("LEFT", canvas.defensiveThreshold, "RIGHT", 6, 0)
	threshValueFS:SetText("0")

	local threshPctFS = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	threshPctFS:SetPoint("LEFT", threshValueFS, "RIGHT", 2, 0)
	threshPctFS:SetText("% health  (0 = always glow)")
	threshPctFS:SetTextColor(0.6, 0.6, 0.6)

	canvas.defensiveThreshold:SetScript("OnValueChanged", function(self, value)
		local v = math_floor(value + 0.5)
		threshValueFS:SetText(v)
		local cfg = NS.GetSpecConfig and NS.GetSpecConfig()
		if cfg then
			cfg.defensiveHealthThreshold = v
			if NS.UpdateDefensives then NS.UpdateDefensives() end
		end
	end)

	local div3 = Divider(threshLabel, -14)

	-- ─── Trinket Blacklist ────────────────────────────────────────────────────

	local _, blNote = Section(div3, -10,
		"TRINKET BLACKLIST  ·  Account-wide",
		"Item IDs to hide from the Trinket Tracker — useful for passive trinkets, teleports, or utility items you don't want cluttering the companion. Drag a trinket here to add it.")

	local blAddLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	blAddLabel:SetPoint("TOPLEFT", blNote, "BOTTOMLEFT", 0, -10)
	blAddLabel:SetText("Blacklisted Item ID(s):")

	canvas.trinketBlacklistEditor = CreateSpellListEditor(
		content, 560,
		"trinketBlacklist",
		function()
			if NS.wipe then NS.wipe(NS.TrinketBlacklistCache) end
			if NS.UpdateTrinkets then NS.UpdateTrinkets()
			elseif NS.UpdateNow then NS.UpdateNow() end
		end,
		"Empty: no items blacklisted. Drag trinkets here to hide them.",
		function() return NS.db end,
		NS.ValidateItemID,
		true
	)
	canvas.trinketBlacklistEditor.canvas = canvas
	canvas.trinketBlacklistEditor:SetPoint("TOPLEFT", blAddLabel, "BOTTOMLEFT", 0, -6)

	local div4 = Divider(canvas.trinketBlacklistEditor, -8)

	-- ─── Reset ───────────────────────────────────────────────────────────────

	canvas.resetSpec = CreateSettingsButton(content, "Reset Current Spec", 140)
	canvas.resetSpec:SetPoint("TOPLEFT", div4, "BOTTOMLEFT", 0, -10)
	canvas.resetSpec:SetScript("OnClick", function()
		local specKey = NS.GetSpecKey and NS.GetSpecKey()
		if specKey and NS.db and NS.db.specSettings then
			NS.db.specSettings[specKey] = nil
			InvalidateRangeList()
			InvalidateDefensiveList()
			RefreshAdvancedCanvas(canvas)
		end
	end)

	local resetNote = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	resetNote:SetPoint("LEFT", canvas.resetSpec, "RIGHT", 10, 0)
	resetNote:SetText("Clears all per-spec settings for the current specialization.")
	resetNote:SetTextColor(0.6, 0.6, 0.6)

	canvas.layoutBottom = canvas.resetSpec

	canvas:SetScript("OnShow", function(self)
		SyncAdvancedContentWidth(self)
		RefreshAdvancedCanvas(self)
	end)

	Settings.RegisterCanvasLayoutSubcategory(category, canvas, "Advanced")
end

StaticPopupDialogs["BETTERBUTTONASSISTANT_RESET_CONFIRM"] = {
	text = "Are you sure you want to reset all BetterButtonAssistant settings? This will reload your UI.",
	button1 = "Yes",
	button2 = "No",
	OnAccept = function()
		BetterButtonAssistantDB = {}
		ReloadUI()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function NS.RegisterSettings()
	local category, layout = Settings.RegisterVerticalLayoutCategory(NS.ADDON_DISPLAY_NAME)
	NS.SettingsCategory = category

	local function AddSettingsButton(lyt, name, buttonText, onClick, tooltip)
		local init = rawget(_G, "CreateSettingsButtonInitializer")
		if lyt and init then
			lyt:AddInitializer(init(name, buttonText, onClick, tooltip, false))
		end
	end

	-- The "Right" label position shows the live value next to a slider.
	local labelRight = (MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and MinimalSliderWithSteppersMixin.Label.Right) or 2

	-- Registers a setting bound to NS.db[key] with an optional change callback.
	local function Register(key, varType, name, default, callback)
		local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, NS.db, varType, name, default)
		if callback then
			setting:SetValueChangedCallback(callback)
		end
		return setting
	end

	-- Boolean checkbox in one call.
	local function AddCheckbox(parent, key, name, default, tooltip, callback)
		local setting = Register(key, Settings.VarType.Boolean, name, default, callback)
		Settings.CreateCheckbox(parent, setting, tooltip)
		return setting
	end

	-- Numeric slider in one call (with optional value-label formatter).
	local function AddSlider(parent, key, name, default, minV, maxV, step, tooltip, callback, formatter)
		local setting = Register(key, Settings.VarType.Number, name, default, callback)
		local options = Settings.CreateSliderOptions(minV, maxV, step)
		if formatter then
			options:SetLabelFormatter(labelRight, formatter)
		end
		Settings.CreateSlider(parent, setting, options, tooltip)
		return setting
	end

	-- String dropdown in one call.
	local function AddDropdown(parent, key, name, default, optionsFn, tooltip, callback)
		local setting = Register(key, Settings.VarType.String, name, default, callback)
		Settings.CreateDropdown(parent, setting, optionsFn, tooltip)
		return setting
	end

	-- Section divider with a bold title (and a hover description) inside a vertical
	-- layout page, so a busy page reads as labelled groups instead of a flat list.
	-- Needs the page's layout object (2nd return of RegisterVerticalLayoutSubcategory).
	-- Guarded so a client missing the global degrades to an unsectioned (but working)
	-- page rather than erroring.
	local function AddSectionHeader(layout, title, description)
		if layout and CreateSettingsListSectionHeaderInitializer then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title, description))
		end
	end

	-- ---- General (root page) ----
	AddCheckbox(category, "enabled", "Enabled", true, "Toggle BetterAssistant on/off.", cbVisibility)
	AddCheckbox(category, "locked", "Locked", false, "Lock the suggestion button in place.", function()
		if NS.UpdateMouseState then
			NS.UpdateMouseState()
		end
	end)

	AddSettingsButton(layout, "Reset All Settings", "Reset All Settings", function()
		StaticPopup_Show("BETTERBUTTONASSISTANT_RESET_CONFIRM")
	end, "Restore all settings to their default values and reload the UI.")

	-- ---- Visuals (pure appearance of the button) ----
	local visualSubcat, visualLayout = Settings.RegisterVerticalLayoutSubcategory(category, "Visuals")

	AddSectionHeader(visualLayout, "Size & Placement", "How big the button is and where it sits in the UI draw order.")
	AddSlider(visualSubcat, "buttonSize", "Button Size", 80, 20, 100, 2, "Adjust the dimensions of the suggestion button.", cbLayout, fmtPx)
	AddSlider(visualSubcat, "scale", "Scale", 1.0, 0.5, 2.0, 0.05, "Overall scale of the assistant UI.", cbLayout, fmtPct100)
	AddCheckbox(visualSubcat, "trueScale", "Pixel-Perfect Scale", false, "Snap the button to whole physical pixels so the icon art stays crisp. The scale slider then multiplies on top of this.", cbLayout)
	AddDropdown(visualSubcat, "strata", "Frame Strata", "MEDIUM", function()
		local c = Settings.CreateControlTextContainer()
		c:Add("BACKGROUND", "Background")
		c:Add("LOW", "Low")
		c:Add("MEDIUM", "Medium")
		c:Add("HIGH", "High")
		c:Add("DIALOG", "Dialog")
		c:Add("FULLSCREEN", "Fullscreen")
		c:Add("FULLSCREEN_DIALOG", "Fullscreen Dialog")
		c:Add("TOOLTIP", "Tooltip")
		return c:GetData()
	end, "Draw order of the button relative to the rest of the UI. Raise it if other frames cover the suggestion.", cbLayout)

	AddSectionHeader(visualLayout, "Icon & Glow", "The button's border, proc glow, and range/usability tinting of the icon.")
	AddCheckbox(visualSubcat, "showBorder", "Show Border", true, "Toggle the Blizzard-style border around the button.", cbLayout)
	AddCheckbox(visualSubcat, "glowEnabled", "Proc Glow", true, "Glow the suggestion when the recommended spell is procced (mirrors Blizzard's action-button glow).", cbNow)
	AddDropdown(visualSubcat, "glowStyle", "Glow Style", "actionbar", function()
		local c = Settings.CreateControlTextContainer()
		c:Add("actionbar", "Action Bar")
		c:Add("onebutton", "Assisted (One Button)")
		return c:GetData()
	end, "Art used for the proc glow. 'Action Bar' is Blizzard's standard button glow; 'Assisted' is the dedicated One Button rotation glow Blizzard shows on the assisted-combat action.", cbLayout)
	AddDropdown(visualSubcat, "glowColor", "Proc Glow Color", "gold", function()
		local c = Settings.CreateControlTextContainer()
		c:Add("gold", "Gold")
		c:Add("green", "Green")
		c:Add("blue", "Blue")
		c:Add("red", "Red")
		c:Add("purple", "Purple")
		c:Add("white", "White (Blizzard)")
		return c:GetData()
	end, "Color tint of the suggestion's proc glow.", cbLayout)
	AddCheckbox(visualSubcat, "rangeColoring", "Range & Usability Coloring", true, "Tint the suggestion red when out of range, blue when out of power, and grey when unusable.", cbNow)

	AddSectionHeader(visualLayout, "Tooltip & Skinning", "Hover tooltip and Masque skin support.")
	AddCheckbox(visualSubcat, "showTooltip", "Show Tooltip", false, "Show the spell tooltip on hover. While the frame is locked this keeps the mouse active; otherwise a locked frame is click-through.", function()
		if NS.UpdateMouseState then
			NS.UpdateMouseState()
		end
	end)
	AddCheckbox(visualSubcat, "useMasque", "Use Masque", true, "Skin the button with Masque if it's installed. Requires a UI reload to apply.", function()
		if DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(NS.ADDON_DISPLAY_NAME .. ": Reload your UI (/reload) to apply the Masque change.")
		end
	end)

	-- ---- Visibility (when/how strongly the button shows) ----
	local visibilitySubcat = Settings.RegisterVerticalLayoutSubcategory(category, "Visibility")

	AddDropdown(visibilitySubcat, "showWhen", "Show When", "Always", function()
		local c = Settings.CreateControlTextContainer()
		c:Add("Always", "Always")
		c:Add("HasTarget", "Has Target")
		c:Add("InCombat", "In Combat")
		c:Add("TargetInCombat", "Target In Combat")
		return c:GetData()
	end, "When the button is shown at all: always, only with a target, only in combat, or only when your target is in combat.", cbVisibility)
	AddSlider(visibilitySubcat, "alphaCombat", "Alpha (In Combat)", 1.0, 0.0, 1.0, 0.05, "Opacity of the frame when in combat.", cbVisibility, fmtPct100)
	AddSlider(visibilitySubcat, "alphaOOC", "Alpha (Out of Combat)", 0.5, 0.0, 1.0, 0.05, "Opacity of the frame when out of combat.", cbVisibility, fmtPct100)
	AddCheckbox(visibilitySubcat, "hideInVehicle", "Hide in Vehicle", true, "Hide the frame when in a vehicle.", cbVisibility)
	AddCheckbox(visibilitySubcat, "hideWhenMounted", "Hide When Mounted", false, "Hide the frame while mounted (includes druid Travel and Flight Form).", cbVisibility)

	-- ---- Keybinds & Cooldowns ----
	local keybindSubcat, keybindLayout = Settings.RegisterVerticalLayoutSubcategory(category, "Keybinds & Cooldowns")

	AddSectionHeader(keybindLayout, "Keybinds", "The bound key shown on the button, and its text size.")
	AddCheckbox(keybindSubcat, "showKeybind", "Show Keybinds", true, "Show the keybind text on the button.", cbNow)
	AddSlider(keybindSubcat, "keybindFontSize", "Keybind Font Size", 12, 6, 24, 1, "Adjust the size of the keybind text.", cbLayout, fmtPt)

	AddSectionHeader(keybindLayout, "Cooldown & Cast", "The cooldown swipe and optional live cast/channel progress (including Evoker empower release).")
	AddCheckbox(keybindSubcat, "showCooldown", "Show Cooldown", true, "Show the cooldown swipe on the suggestion (where the client allows it; Midnight may mark cooldowns secret).", function()
		cbLayout()
		cbNow()
	end)
	AddCheckbox(keybindSubcat, "showCastProgress", "Show Cast Progress", false, "While casting or channeling, fill the swipe with your live cast progress. Evoker empowers clear the swipe once they reach the release stage below.", cbNow)
	AddSlider(keybindSubcat, "empowerMinStage", "Empower Release Stage", 1, 1, 4, 1, "Empowered spells read as 'ready to release' (swipe clears) once the channel reaches this stage.", cbNow, fmtNum)

	-- ---- Rotation (what gets suggested + resource hints) ----
	local rotationSubcat = Settings.RegisterVerticalLayoutSubcategory(category, "Rotation")

	AddCheckbox(rotationSubcat, "checkVisibleButton", "Check Visible Buttons", true, "Only suggest spells that are currently visible on your action bars.")
	AddCheckbox(rotationSubcat, "queueEnabled", "Rotation Queue Preview", true, "Show upcoming Assisted Combat rotation spells below the main suggestion (from Blizzard's rotation list, in order after the current pick).", function()
		if NS.InvalidateCompanionLayout then
			NS.InvalidateCompanionLayout()
		end
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
		if NS.UpdateNow then
			NS.UpdateNow()
		end
	end)
	AddSlider(rotationSubcat, "queueCount", "Queue Spell Count", 3, 1, 5, 1, "How many upcoming rotation spells to preview below the button.", function()
		if NS.UpdateNow then
			NS.UpdateNow()
		end
	end, fmtNum)
	AddSlider(rotationSubcat, "queueSize", "Queue Icon Size", 34, 16, 60, 2, "Size of each queue preview icon.", function()
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
	end, fmtPx)
	AddSlider(rotationSubcat, "queueSpacing", "Queue Icon Spacing", 4, 0, 20, 1, "Gap between queue preview icons.", function()
		if NS.UpdateNow then
			NS.UpdateNow()
		end
	end, fmtPx)
	AddCheckbox(rotationSubcat, "queueCombatOnly", "Queue: Combat Only", false, "Only show the rotation queue while you're in combat.", function()
		if NS.InvalidateCompanionLayout then
			NS.InvalidateCompanionLayout()
		end
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
		if NS.UpdateQueue then
			NS.UpdateQueue()
		end
		if NS.UpdateNow then
			NS.UpdateNow()
		end
	end)
	AddDropdown(rotationSubcat, "queueAlignment", "Queue Alignment", "left", function()
		local c = Settings.CreateControlTextContainer()
		c:Add("left", "Left-Aligned")
		c:Add("center", "Centered")
		return c:GetData()
	end, "Align the upcoming rotation queue to the left edge of the main button, or center it underneath.", cbLayout)
	AddDropdown(rotationSubcat, "queueLayoutDirection", "Queue Layout Direction", "horizontal", function()
		local c = Settings.CreateControlTextContainer()
		c:Add("horizontal", "Horizontal")
		c:Add("vertical", "Vertical")
		return c:GetData()
	end, "Stack the upcoming rotation queue horizontally or vertically.", cbLayout)
	AddDropdown(rotationSubcat, "queuePosition", "Queue Position", "below", function()
		local c = Settings.CreateControlTextContainer()
		c:Add("below",  "Below (default)")
		c:Add("above",  "Above")
		c:Add("right",  "Right")
		c:Add("left",   "Left")
		return c:GetData()
	end, "Which side of the main button the rotation queue appears on. Works alongside Queue Layout Direction.", function()
		if NS.InvalidateCompanionLayout then NS.InvalidateCompanionLayout() end
		if NS.LayoutCompanions then NS.LayoutCompanions() end
		if NS.UpdateNow then NS.UpdateNow() end
	end)
	AddCheckbox(rotationSubcat, "resourcePooling", "Resource Pooling Tint", false, "Tint the suggestion while you're below the pooling threshold for the resource it spends (energy, focus, rage, runic power, fury, ...). Tells you to bank a little more before spending. Mana is excluded.", cbNow)
	AddSlider(rotationSubcat, "resourcePoolThreshold", "Pooling Threshold", 40, 0, 100, 5, "The button is tinted while the spent resource is below this percent of its maximum.", cbNow, fmtPctRaw)

	-- ---- Performance (polling rates) ----
	local performanceSubcat = Settings.RegisterVerticalLayoutSubcategory(category, "Performance")

	AddSlider(performanceSubcat, "updateRate", "Update Rate", 0.12, 0.05, 0.5, 0.01, "How often (in seconds) the addon checks for a new spell suggestion. Lower = more responsive but higher CPU.", cbRestartTicker, fmtMs)
	AddSlider(performanceSubcat, "updateRateOOC", "Update Rate (Out of Combat)", 0.25, 0.05, 1.0, 0.01, "Polling rate when out of combat. Higher = lower idle CPU. The faster of this and the in-combat rate is used.", cbRestartTicker, fmtMs)

	-- ---- Companions (extra widgets around the button) ----
	-- One page, split into labelled sections (Interrupt / Nameplate Counter / Target
	-- Range / Trinkets) so each companion's controls read as their own group.
	local companionSubcat, companionLayout = Settings.RegisterVerticalLayoutSubcategory(category, "Companions")

	AddSectionHeader(companionLayout, "Shared Display", "Display options shared by the small companion icons around the main suggestion.")
	AddCheckbox(companionSubcat, "companionCooldownNumbers", "Companion Cooldown Numbers", false, "Show Blizzard cooldown countdown numbers on companion cooldown swipes (interrupt, defensives, trinkets, and rotation queue). Off by default to keep the icons clean.", function()
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
		if NS.UpdateNow then
			NS.UpdateNow()
		end
	end)

	-- Shared position-preset option list reused by all four companion groups.
	-- "right" / "left": icons stack vertically alongside the button.
	-- "above" / "below": icons stack horizontally above/below the button.
	local function positionOptions()
		local c = Settings.CreateControlTextContainer()
		c:Add("right",  "Right (vertical)")
		c:Add("left",   "Left (vertical)")
		c:Add("above",  "Above (horizontal)")
		c:Add("below",  "Below (horizontal)")
		return c:GetData()
	end

	AddSectionHeader(companionLayout, "Interrupt", "A companion icon that lights up when the watched unit is casting an interruptible spell and your interrupt is in range and ready.")
	AddCheckbox(companionSubcat, "interruptEnabled", "Interrupt Indicator", false, "Show a companion icon (right of the button) that lights up when the watched unit is casting an interruptible spell and your interrupt is in range and ready.", function()
		if NS.UpdateInterruptRegistration then
			NS.UpdateInterruptRegistration()
		end
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
	end)
	AddDropdown(companionSubcat, "interruptUnit", "Interrupt Watches", "target", function()
		local c = Settings.CreateControlTextContainer()
		c:Add("target", "Target")
		c:Add("focus", "Focus")
		c:Add("auto", "Auto (Focus or Target)")
		return c:GetData()
	end, "Which unit the interrupt indicator watches. 'Auto' follows whichever of your focus or target is currently casting (focus first) — ideal for Mythic+ focus-kicking.", function()
		if NS.UpdateInterruptRegistration then
			NS.UpdateInterruptRegistration()
		end
	end)
	AddCheckbox(companionSubcat, "interruptGlow", "Interrupt: Kick Now Glow", true, "Show a proc-style glow while the watched unit is casting or channeling and your interrupt is ready. Hides only when we can confirm the cast is not interruptible.", function()
		if NS.UpdateInterrupt then
			NS.UpdateInterrupt()
		end
	end)
	AddSlider(companionSubcat, "interruptSpacing", "Interrupt Icon Spacing", 4, 0, 50, 1, "Gap between the main button edge and the interrupt icon.", function()
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
	end, fmtPx)
	AddDropdown(companionSubcat, "interruptPosition", "Interrupt Position", "right", positionOptions,
		"Which side of the main button the interrupt icon appears on.", function()
		if NS.LayoutCompanions then NS.LayoutCompanions() end
	end)

	AddSectionHeader(companionLayout, "Nameplate Counter", "A count above the button of how many attackable enemies have a nameplate up — a quick read on how many things are on you for AoE decisions.")
	AddCheckbox(companionSubcat, "nameplateCounterEnabled", "Nameplate Enemy Counter", false, "Show a count above the button of how many attackable enemies have a nameplate up (handy for AoE decisions).", function()
		if NS.UpdateNameplateRegistration then
			NS.UpdateNameplateRegistration()
		end
	end)
	AddCheckbox(companionSubcat, "nameplateCounterCombatOnly", "Counter: Combat Only", true, "Only show the enemy counter while you're in combat.", function()
		if NS.UpdateNameplateCounter then
			NS.UpdateNameplateCounter()
		end
	end)
	AddSlider(companionSubcat, "nameplateCounterMin", "Counter: Minimum Enemies", 1, 1, 10, 1, "Only show the counter once at least this many enemies are up.", function()
		if NS.UpdateNameplateCounter then
			NS.UpdateNameplateCounter()
		end
	end, fmtNum)

	AddSectionHeader(companionLayout, "Target Range Readout", "An estimated distance (yards) to your target below the button, colored by whether the suggested spell is in range. Works with zero setup; optionally override the coloring per spec via the Advanced Spell Range List.")
	AddCheckbox(companionSubcat, "rangeReadoutEnabled", "Target Range Readout", false, "Show an estimated distance (yards) to your target below the button. It's colored green/red by whether the suggested spell is in range — no setup needed. (Optionally override this per spec with a Spell Range List in Advanced.)", function()
		if NS.UpdateRangeReadout then
			NS.UpdateRangeReadout()
		end
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
	end)
	AddCheckbox(companionSubcat, "rangeReadoutCombatOnly", "Range Readout: Combat Only", false, "Only show the target range readout while you're in combat.", function()
		if NS.UpdateRangeReadout then
			NS.UpdateRangeReadout()
		end
	end)

	AddSectionHeader(companionLayout, "Personal Defensives", "Per-spec defensive cooldowns (configured in Advanced) shown as companion icons. Glow when ready, usable, and your health is at or below the optional threshold.")
	AddCheckbox(companionSubcat, "defensivesEnabled", "Defensives Tracker", false, "Show your configured defensive spells for this spec. Add spell IDs in Advanced → Personal Defensives.", function()
		if NS.UpdateDefensiveRegistration then
			NS.UpdateDefensiveRegistration()
		end
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
	end)
	AddCheckbox(companionSubcat, "defensiveGlow", "Defensives: Ready Glow", true, "Proc-style glow when a defensive is off cooldown, usable, and the health gate passes.", function()
		if NS.UpdateDefensives then
			NS.UpdateDefensives()
		end
	end)
	AddDropdown(companionSubcat, "defensiveGlowColor", "Defensives: Glow Color", "green", function()
		local c = Settings.CreateControlTextContainer()
		c:Add("gold", "Gold")
		c:Add("green", "Green")
		c:Add("blue", "Blue")
		c:Add("red", "Red")
		c:Add("purple", "Purple")
		c:Add("white", "White (Blizzard)")
		return c:GetData()
	end, "Color tint of the defensive ready glow.", cbLayout)
	AddCheckbox(companionSubcat, "defensiveCombatOnly", "Defensives: Combat Only", false, "Only show defensive icons while you're in combat.", function()
		if NS.UpdateDefensives then
			NS.UpdateDefensives()
		end
	end)
	AddSlider(companionSubcat, "defensiveSize", "Defensive Icon Size", 32, 16, 64, 1, "Size (in pixels) of each defensive icon.", function()
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
	end, fmtPx)
	AddSlider(companionSubcat, "defensiveSpacing", "Defensive Icon Spacing", 4, 0, 50, 1, "Gap between the button and the defensive group, and between defensive icons.", function()
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
	end, fmtPx)
	AddDropdown(companionSubcat, "defensivePosition", "Defensive Position", "left", positionOptions,
		"Which side of the main button defensive icons appear on. When set to the same side as Trinkets, both groups stack together (defensives below trinkets).", function()
		if NS.LayoutCompanions then NS.LayoutCompanions() end
	end)

	AddSectionHeader(companionLayout, "Trinkets", "Your equipped trinkets with a cooldown swipe and a brief glow when one comes off cooldown. Optionally filter to on-use trinkets only and restrict to combat.")
	AddCheckbox(companionSubcat, "trinketEnabled", "Trinket Tracker", false, "Show your equipped trinkets with a cooldown swipe and a brief glow when one comes off cooldown.", function()
		if NS.UpdateTrinketRegistration then
			NS.UpdateTrinketRegistration()
		end
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
	end)
	AddCheckbox(companionSubcat, "trinketOnUseOnly", "Trinkets: On-Use Only", true, "Only show trinkets that have an on-use effect (hide passive/stat trinkets).", function()
		if NS.UpdateTrinkets then
			NS.UpdateTrinkets()
		end
	end)
	AddCheckbox(companionSubcat, "trinketCombatOnly", "Trinkets: Combat Only", false, "Only show the trinkets while you're in combat.", function()
		if NS.UpdateTrinkets then
			NS.UpdateTrinkets()
		end
	end)
	AddSlider(companionSubcat, "trinketSize", "Trinket Icon Size", 36, 16, 64, 1, "Size (in pixels) of the trinket icons.", function()
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
	end, fmtPx)
	AddSlider(companionSubcat, "trinketSpacing", "Trinket Icon Spacing", 4, 0, 50, 1, "Gap between the main button and the trinket group, and between the two trinket icons.", function()
		if NS.LayoutCompanions then
			NS.LayoutCompanions()
		end
	end, fmtPx)
	AddDropdown(companionSubcat, "trinketPosition", "Trinket Position", "above", positionOptions,
		"Which side of the main button the trinket icons appear on. When set to the same side as Defensives, both groups stack together (trinkets closer to the button).", function()
		if NS.LayoutCompanions then NS.LayoutCompanions() end
	end)

	RegisterAdvancedCanvas(category)

	Settings.RegisterAddOnCategory(category)
	NS.SettingsCategory = category
end

-- ---------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------
SLASH_BETTERBUTTONASSISTANT1 = "/betterbuttonassistant"
SLASH_BETTERBUTTONASSISTANT2 = "/bba"
SLASH_BETTERBUTTONASSISTANT3 = "/betterassistant"

SlashCmdList.BETTERBUTTONASSISTANT = function(msg)
	msg = msg and NS.string_lower(msg) or ""

	if msg == "toggle" then
		NS.db.enabled = not NS.db.enabled
		if NS.UpdateVisibility then
			NS.UpdateVisibility()
		end
		return
	end

	-- Open Settings Panel
	if Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(NS.SettingsCategory:GetID())
	end
end
