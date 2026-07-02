-- BetterAssistant
-- Shows Blizzard Assisted Combat recommendations + keybinds (no Ace3)

local ADDON_NAME, NS = ...

-- Midnight (12.0) secret-value detector. nil on pre-Midnight clients, where no
-- value is ever secret, so every `issecretvalue and ...` guard is a no-op there.
local issecretvalue = NS.issecretvalue

-- Midnight build 66562+ secret-safe cooldown APIs (cached for the per-tick path).
-- These are nil on older clients; the cooldown code falls back to SetCooldown there.
local IS_DURATION_COOLDOWNS = NS.IS_DURATION_COOLDOWNS
local C_ActionBar_GetActionCooldown = NS.C_ActionBar_GetActionCooldown
local C_ActionBar_GetActionCooldownDuration = NS.C_ActionBar_GetActionCooldownDuration
local C_Spell_GetSpellCooldownDuration = NS.C_Spell_GetSpellCooldownDuration

-- Player cast/channel progress + empower staging (for the optional cast-progress
-- swipe). These read only the player's own cast timing, which is never secret.
local UnitCastingInfo = NS.UnitCastingInfo
local UnitChannelInfo = NS.UnitChannelInfo
local GetUnitEmpowerStageDuration = NS.GetUnitEmpowerStageDuration
local GetTime = NS.GetTime

-- Visibility / mounted / pooling hot-path globals (cached per the optimization
-- guide so the per-tick update never does a global hash lookup for them).
local UnitExists = NS.UnitExists
local UnitCanAttack = NS.UnitCanAttack
local IsMounted = NS.IsMounted
local GetShapeshiftFormID = NS.GetShapeshiftFormID
local UnitPower = NS.UnitPower
local UnitPowerMax = NS.UnitPowerMax
local C_Spell_GetSpellPowerCost = NS.C_Spell_GetSpellPowerCost

-- Interrupt indicator + nameplate counter helpers (player-owned / public data).
local C_SpellBook_IsSpellInSpellBook = NS.C_SpellBook_IsSpellInSpellBook
local C_Spell_GetOverrideSpell = NS.C_Spell_GetOverrideSpell
local C_Spell_GetSpellTexture = NS.C_Spell_GetSpellTexture
local C_Spell_IsSpellInRange = NS.C_Spell_IsSpellInRange
local C_NamePlate = NS.C_NamePlate
local INTERRUPT_SPELLS = NS.INTERRUPT_SPELLS

-- Trinket tracker companion (equipped on-use trinket icons + secret-safe cooldown).
local GetItemSpell = NS.GetItemSpell
local GetInventoryItemID = NS.GetInventoryItemID
local GetInventoryItemTexture = NS.GetInventoryItemTexture

-- Druid Travel Form (3) and Flight Form (27) read as "mounted" for hide purposes.
local TRAVEL_FORM_IDS = { [3] = true, [27] = true }

-- Companion widgets, created lazily the first time their feature is enabled.
local interruptFrame
local interruptSpellID
local interruptCastMode = {}
local counterText
local rangeReadout
local trinketFrames
local TRINKET_SLOTS = { 13, 14 }
local queueFrames
local defensiveFrames
local sideUsed
local DEFENSIVE_DIM = 0.55
local ApplyActionState
local math_floor = NS.math_floor

local lastCounterText
local lastRangeText
local lastRangeColor
local lastCompanionLayoutSig
local string_format = string.format

-- Secret spell IDs cannot be compared with ==; use this instead of `a ~= b` on hot paths.
local function SpellIDChanged(prev, cur)
	if prev == nil and cur == nil then
		return false
	end
	if prev == nil or cur == nil then
		return true
	end
	if issecretvalue then
		if issecretvalue(prev) or issecretvalue(cur) then
			if issecretvalue(prev) and issecretvalue(cur) then
				return false
			end
			return true
		end
	end
	return prev ~= cur
end

-- Range readout display bounds. In retail nothing combat-relevant reaches past ~40yd
-- (the standard ability-range ceiling), so anything beyond is clamped to "40+ yd"
-- rather than printing a noisy, unactionable distance.
local RANGE_READOUT_CAP = 40

-- ---------------------------------------------------------------------
-- UI  (MODULE: UI — candidate for Modules/UI.lua)
-- ---------------------------------------------------------------------
local addonFrame = NS.CreateFrame("Frame", "BetterAssistantEventFrame")
local frame = NS.CreateFrame("Frame", "BetterAssistantFrame", NS.UIParent, "BackdropTemplate")
NS.frame = frame
NS.addonFrame = addonFrame

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
	-- Persist position to DB so it survives reloads.
	local point, _, relPoint, x, y = self:GetPoint()
	if point then
		NS.db.framePoint = point
		NS.db.frameRelPoint = relPoint
		NS.db.frameX = x
		NS.db.frameY = y
	end
end)

-- Hover tooltip for the current suggestion. Only fires when the frame has mouse
-- enabled (see UpdateMouseState): always while unlocked, and while locked only if
-- the tooltip option is on.
frame:SetScript("OnEnter", function(self)
	if not NS.db.showTooltip then
		return
	end
	local b = self.button
	if not b or not b.spellID then
		return
	end
	local tip = NS.GameTooltip
	if not tip then
		return
	end
	tip:SetOwner(self, "ANCHOR_RIGHT")
	if tip.SetSpellByID then
		NS.pcall(tip.SetSpellByID, tip, b.spellID)
	end
	tip:Show()
end)

frame:SetScript("OnLeave", function()
	if NS.GameTooltip then
		NS.GameTooltip:Hide()
	end
end)

-- Enables/disables mouse on the frame. Unlocked => mouse on (needed to drag).
-- Locked => mouse only if the tooltip is wanted; otherwise the frame is fully
-- click-through so it never eats clicks meant for whatever sits behind it.
function NS.UpdateMouseState()
	local f = NS.frame
	if not f then
		return
	end
	local wantMouse = (not NS.db.locked) or NS.db.showTooltip
	f:EnableMouse(wantMouse and true or false)
end

-- ---------------------------------------------------------------------
-- Masque skinning (optional)
-- ---------------------------------------------------------------------
local Masque = NS.LibStub and NS.LibStub("Masque", true)
local masqueGroup
if Masque then
	masqueGroup = Masque:Group("BetterButtonAssistant")
end

-- Registers a button's regions with Masque so users' skins apply. No-op if Masque
-- isn't installed or the option is off.
local function SkinButton(b)
	if not masqueGroup or not NS.db.useMasque then
		return
	end
	masqueGroup:AddButton(b, {
		Icon = b.icon,
		Cooldown = b.cooldown,
		HotKey = b.hotkey,
		Normal = b.border,
	})

	-- Masque draws its own backdrop/frame, so drop our slot backing to avoid
	-- doubling it up. UpdateLayout honors this flag when toggling the slot.
	b.masqued = true
	if b.slot then
		b.slot:Hide()
	end
	-- Masque applies its own icon mask (per its skin); remove ours so the two don't
	-- compound into a smaller intersection shape.
	if b.iconMask then
		b.icon:RemoveMaskTexture(b.iconMask)
		b.iconMask:Hide()
		b.iconMask = nil
	end
end

local updateDriver = NS.CreateFrame("Frame")
local pendingUpdate = false
updateDriver:Hide()
updateDriver:SetScript("OnUpdate", function(self, elapsed)
	if pendingUpdate then
		pendingUpdate = false
		self:Hide()
		NS.UpdateNow()
	end
end)

local function SafeSetCooldown(cooldown, startTime, duration, modRate)
	if not startTime or not duration then
		cooldown:Hide()
		return false
	end

	-- Midnight marks combat cooldown times secret. Cooldown:SetCooldown rejects
	-- secret args from tainted code, so detect-and-skip up front: this is the
	-- primary guard the secret-values guide recommends over a per-tick pcall.
	-- (Out of combat the values aren't secret, so the swipe still draws normally.)
	if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration) or (modRate and issecretvalue(modRate))) then
		cooldown:Hide()
		return false
	end

	if modRate then
		cooldown:SetCooldown(startTime, duration, modRate)
	else
		cooldown:SetCooldown(startTime, duration)
	end
	cooldown:Show()
	return true
end

-- Resolves (and memoizes) an action-bar slot holding the given spell. The slot is
-- cached in NS.ActionSlotCache (false = "not on a bar") so the per-tick cooldown
-- path never re-scans bars or allocates the FindSpellActionButtons result table.
-- The cache is wiped on the same bar/binding/form/spec events as the keybind cache.
local function ResolveActionSlot(spellID)
	local cache = NS.ActionSlotCache
	local cached = cache[spellID]
	if cached ~= nil then
		return cached or nil
	end

	local slot = false
	if NS.C_ActionBar_FindSpellActionButtons then
		local baseID = NS.FindBaseSpellByID(spellID) or spellID
		local slots = NS.C_ActionBar_FindSpellActionButtons(baseID)
		if (not slots or #slots == 0) then
			local canCompare = not (issecretvalue and (issecretvalue(baseID) or issecretvalue(spellID)))
			if canCompare and baseID ~= spellID then
				slots = NS.C_ActionBar_FindSpellActionButtons(spellID)
			end
		end
		if slots and slots[1] then
			slot = slots[1]
		end
	end

	cache[spellID] = slot
	return slot or nil
end

local function GetActionCooldownForSpell(spellID)
	if not NS.GetActionCooldown then
		return
	end

	local slot = ResolveActionSlot(spellID)
	if not slot then
		return
	end

	return NS.GetActionCooldown(slot)
end

local function GetSpellCooldownForDisplay(spellID)
	local startTime, duration, enable, modRate = GetActionCooldownForSpell(spellID)
	if duration then
		return startTime, duration, enable, modRate
	end

	-- Midnight can return secret C_Spell cooldown values from assisted-combat
	-- spell IDs; passing those to Cooldown:SetCooldown taints and errors.
	if NS.IS_MIDNIGHT or not NS.C_Spell_GetSpellCooldown then
		return
	end

	local cd = NS.C_Spell_GetSpellCooldown(spellID)
	if cd and cd.duration and cd.duration > 0 then
		return cd.startTime, cd.duration, cd.isEnabled, cd.modRate
	end
end

-- Shared secret-safe cooldown swipe renderer for the companion icons (interrupt +
-- trinket/queue/defensive). Renders the swipe onto `cd` and returns readiness:
--   true  = ready (off cooldown)
--   false = on cooldown
--   nil   = unknown (off-bar on Midnight, where reading the number isn't secret-safe)
local RefreshCompanionCooldownFont

local function RenderCooldownReadiness(cd, spellID)
	if not cd then
		return nil
	end
	if not spellID then
		cd:Clear()
		cd:Hide()
		return nil
	end

	local slot = ResolveActionSlot(spellID)
	if slot and C_ActionBar_GetActionCooldown then
		local info = C_ActionBar_GetActionCooldown(slot)
		if info then
			if info.isActive then
				if C_ActionBar_GetActionCooldownDuration then
					cd:SetCooldownFromDurationObject(C_ActionBar_GetActionCooldownDuration(slot))
				end
				cd:Show()
				RefreshCompanionCooldownFont(cd:GetParent())
				return false
			end
			cd:Clear()
			cd:Hide()
			return true
		end
	end

	-- Spell-based path (Midnight): GetSpellCooldownDuration has MayReturnNothing=true:
	-- nil = spell is NOT on cooldown (ready); non-nil DurationObject = on cooldown.
	-- This lets us return confirmed true/false readiness from the off-bar path instead
	-- of the previous nil-always fallback that caused false-positive interrupt glows
	-- when the spell was clearly on CD (swipe showed) but readiness was reported unknown.
	if C_Spell_GetSpellCooldownDuration then
		local ok, durObj = NS.pcall(C_Spell_GetSpellCooldownDuration, spellID)
		if ok then
			if durObj ~= nil then
				-- Non-nil DurationObject = spell IS on cooldown.
				cd:SetCooldownFromDurationObject(durObj)
				cd:Show()
				RefreshCompanionCooldownFont(cd:GetParent())
				return false
			else
				-- nil = no active cooldown = spell is ready.
				cd:Clear()
				cd:Hide()
				return true
			end
		end
	end

	-- Pre-Midnight only: cooldown numbers are never secret, so off-bar readiness is
	-- safe to compute. On Midnight we deliberately don't read them (see Constants).
	if not NS.IS_MIDNIGHT and NS.C_Spell_GetSpellCooldown then
		local sc = NS.C_Spell_GetSpellCooldown(spellID)
		if sc and sc.duration ~= nil then
			local onCd = sc.duration > 1.5 and (sc.startTime or 0) > 0
			if onCd then
				if sc.startTime and sc.duration then
					SafeSetCooldown(cd, sc.startTime, sc.duration, sc.modRate)
				end
				return false
			end
			cd:Clear()
			cd:Hide()
			return true
		end
	end

	return nil
end

-- Positions Blizzard's icon-frame art (metal border + slot backing) for a square
-- icon of the given size. The ratios come straight from
-- Blizzard's BaseActionButtonMixin:UpdateButtonArt: a 45px action button draws its
-- UI-HUD-ActionBar-IconFrame at 46x45 (so the frame is ~1.022x wide, 1.0x tall and
-- barely overlaps the icon), centered. Matching that ratio makes the metal lip hug
-- the icon at any size. Shared by the suggestion button and interrupt companion so
-- both skins line up identically.
local FRAME_W_RATIO = 46 / 45 -- IconFrame width vs button
local FRAME_H_RATIO = 45 / 45 -- IconFrame height vs button
local COOLDOWN_INSET_LEFT_RATIO = 1.7 / 45 -- SmallActionButtonMixin cooldown top-left inset
local COOLDOWN_INSET_RIGHT_RATIO = 1 / 45 -- SmallActionButtonMixin cooldown bottom-right inset
-- Blizzard ~45px action buttons use ~15pt companion digits; the main suggestion
-- button gets a larger ratio so countdown text stays readable on big icons.
local COOLDOWN_REF_ICON = 45
local COOLDOWN_COMP_FONT = 15
local COOLDOWN_MAIN_FONT = 20
local COOLDOWN_FONT_MAX = 48
local cooldownFontBySize = {}

local function CooldownFontSizeForIcon(iconSize, isMain)
	iconSize = iconSize or 40
	local ref = isMain and COOLDOWN_MAIN_FONT or COOLDOWN_COMP_FONT
	return math.max(8, math.min(COOLDOWN_FONT_MAX, math_floor(ref * iconSize / COOLDOWN_REF_ICON + 0.5)))
end

-- Platynator scales countdown text with SetTextScale on top of a base font object.
local function CooldownTextScaleForIcon(iconSize, isMain)
	iconSize = iconSize or 40
	local scale = iconSize / COOLDOWN_REF_ICON
	if isMain then
		scale = scale * (COOLDOWN_MAIN_FONT / COOLDOWN_COMP_FONT)
	end
	return math.max(0.55, math.min(3.5, scale))
end

local function GetCooldownFontName(fontSize)
	if not cooldownFontBySize[fontSize] then
		local globalName = "BetterAssistantCDFont" .. fontSize
		local fo = CreateFont(globalName)
		local path, _, flags = NumberFontNormal:GetFont()
		if not path then
			path, _, flags = GameFontHighlightSmallOutline:GetFont()
		end
		if not path then
			path = "Fonts\\FRIZQT__.TTF"
			flags = "OUTLINE"
		end
		fo:SetFont(path, fontSize, flags or "OUTLINE")
		fo:SetShadowOffset(1, -1)
		fo:SetShadowColor(0, 0, 0, 0.8)
		cooldownFontBySize[fontSize] = globalName
	end
	return cooldownFontBySize[fontSize]
end

-- Midnight cooldown digits may live on GetRegions(), not GetCountdownFontString().
-- Platynator caches Cooldown.Text = Cooldown:GetRegions() at frame build time.
local function ResolveCooldownText(cooldown)
	if not cooldown then
		return nil
	end
	if cooldown._bbaCooldownText then
		return cooldown._bbaCooldownText
	end
	if cooldown.Text then
		cooldown._bbaCooldownText = cooldown.Text
		return cooldown.Text
	end
	if cooldown.GetCountdownFontString then
		local fs = cooldown:GetCountdownFontString()
		if fs then
			cooldown._bbaCooldownText = fs
			cooldown.Text = fs
			return fs
		end
	end
	if cooldown.GetRegions then
		local num = cooldown.GetNumRegions and cooldown:GetNumRegions() or 0
		if num > 0 then
			for i = 1, num do
				local r = select(i, cooldown:GetRegions())
				if r and r.GetObjectType and r:GetObjectType() == "FontString" then
					cooldown._bbaCooldownText = r
					cooldown.Text = r
					return r
				end
			end
		end
		local fs = cooldown:GetRegions()
		if fs and fs.GetObjectType and fs:GetObjectType() == "FontString" then
			cooldown._bbaCooldownText = fs
			cooldown.Text = fs
			return fs
		end
	end
	return nil
end

local function BindCooldownText(cooldown)
	ResolveCooldownText(cooldown)
end

local function ApplyCooldownTextAppearance(cooldown, iconSize, opts)
	if not cooldown then
		return
	end
	opts = opts or {}
	iconSize = iconSize or 40
	local isMain = opts.isMain
	local textScale = CooldownTextScaleForIcon(iconSize, isMain)
	local fontSize = CooldownFontSizeForIcon(iconSize, isMain)
	local cacheKey = fontSize .. ":" .. textScale
	if not opts.force and cooldown._bbaCooldownTextKey == cacheKey then
		return
	end

	local function applyNow()
		local fs = ResolveCooldownText(cooldown)
		if not fs then
			cooldown._bbaCooldownTextKey = nil
			return
		end

		cooldown._bbaCooldownTextKey = cacheKey
		local fontName = GetCooldownFontName(fontSize)
		if cooldown.SetCountdownFont then
			cooldown:SetCountdownFont(fontName)
		end
		if fs.SetFontObject then
			fs:SetFontObject(fontName)
		else
			local path, _, flags = NumberFontNormal:GetFont()
			if not path then
				path, _, flags = GameFontHighlightSmallOutline:GetFont()
			end
			fs:SetFont(path or "Fonts\\FRIZQT__.TTF", fontSize, flags or "OUTLINE")
		end
		if fs.SetTextScale then
			fs:SetTextScale(textScale)
		end
		if fs.SetScale then
			fs:SetScale(1)
		end
		if fs.SetSmoothScaling then
			fs:SetSmoothScaling(false)
		end
	end

	if opts.defer then
		NS.C_Timer_After(0, applyNow)
	else
		applyNow()
		if not cooldown._bbaCooldownText then
			NS.C_Timer_After(0, applyNow)
		end
	end
end

local function RefreshCooldownFontForFrame(frame, isMain)
	if not frame or not frame.cooldown or not frame.cooldown:IsShown() then
		return
	end
	if not isMain and not (NS.db and NS.db.companionCooldownNumbers) then
		return
	end
	ApplyCooldownTextAppearance(frame.cooldown, frame:GetWidth() or (NS.db and NS.db.buttonSize) or 40, {
		isMain = isMain,
		force = true,
		defer = true,
	})
end

local function RefreshMainCooldownFont(b)
	RefreshCooldownFontForFrame(b, true)
end

RefreshCompanionCooldownFont = function(frame)
	RefreshCooldownFontForFrame(frame, false)
end
-- Blizzard's recipe (BaseActionButtonMixin): the icon is shown full-bleed and the
-- IconMask is the atlas-native 64px centered over the 45px button (76 over the 52px
-- Extra Action button) -- i.e. ~1.42x the button. The oversized mask's solid centre
-- fills the frame while its feathered/rounded corners tuck under the metal ring.
local ICON_MASK_FILL_RATIO = 64 / 45
local function LayoutIconFrameSkin(b, size, showBorder)
	local borderWidth = size * FRAME_W_RATIO
	local borderHeight = size * FRAME_H_RATIO
	if b.border then
		b.border:ClearAllPoints()
		b.border:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.border:SetSize(borderWidth, borderHeight)
		b.border:SetShown(showBorder)
	end
	if b.slot then
		-- Dark slot backing sits centered just under the frame, matched to the frame
		-- footprint so its recessed edge reads under the metal lip (not flaring past).
		b.slot:ClearAllPoints()
		b.slot:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.slot:SetSize(borderWidth, borderHeight)
		b.slot:SetShown(showBorder and not b.masqued)
	end
	if b.iconMask and b.icon then
		-- Oversize the mask slightly past the icon. The rounded-square mask atlas, sized
		-- exactly to the icon, pulls the visible art in a hair (corners cut + edge
		-- padding), so the dark slot shows as a ring between the art and the metal frame.
		-- Growing the mask pushes its solid area out under the metal ring (whose own
		-- rounded corners hide the mask's cut corners), so the art fills with no gap.
		local maskSize = size * ICON_MASK_FILL_RATIO
		b.iconMask:ClearAllPoints()
		b.iconMask:SetPoint("CENTER", b.icon, "CENTER", 0, 0)
		b.iconMask:SetSize(maskSize, maskSize)
	end
	if b.cooldown and b.icon and not b.masqued then
		-- Cooldown swipes are not normal textures we can safely mask. Blizzard keeps
		-- the spiral inside the rounded icon by insetting it slightly from the icon
		-- bounds; scale those exact 45px-button offsets with our button size.
		local insetLeft = size * COOLDOWN_INSET_LEFT_RATIO
		local insetRight = size * COOLDOWN_INSET_RIGHT_RATIO
		b.cooldown:ClearAllPoints()
		b.cooldown:SetPoint("TOPLEFT", b.icon, "TOPLEFT", insetLeft, -insetLeft)
		b.cooldown:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -insetRight, insetRight)
		ApplyCooldownTextAppearance(b.cooldown, size, { isMain = b.isMainSuggestion })
	end
end

-- Blizzard's CooldownFrameTemplate ships a fixed small countdown font; scale it with
-- the icon so large buttons don't show tiny "12.3" text lost in the swipe.
local function ApplyCooldownFontSize(cooldown, size, isMain)
	ApplyCooldownTextAppearance(cooldown, size, { isMain = isMain })
end

-- Scales the companion cooldown swipe inset + countdown font to the icon size.
local function LayoutCompanionCooldown(f, size)
	if not f or not f.cooldown then
		return
	end
	size = size or f:GetWidth() or 40
	local skinDirty = f._cooldownLayoutSize ~= size
	if skinDirty then
		f._cooldownLayoutSize = size
		LayoutIconFrameSkin(f, size, NS.db and NS.db.showBorder)
	end
	if NS.db and NS.db.companionCooldownNumbers then
		ApplyCooldownFontSize(f.cooldown, size)
	end
end

-- Rounds the icon's corners with Blizzard's own action-button mask atlas
-- (UI-HUD-ActionBar-IconFrame-Mask), exactly like BaseActionButtonMixin. Blizzard
-- never trims the action icon -- it is shown full-bleed (0,1) and shaped purely by
-- the mask, which LayoutIconFrameSkin sizes to ~1.42x the button so its solid centre
-- fills the frame while the feathered corners tuck under the metal ring. No-op if
-- already applied.
local function ApplyIconMask(b)
	if not b.icon or b.iconMask then
		return
	end
	-- Match Blizzard: full icon, shaped only by the mask (no texcoord trim).
	b.icon:SetTexCoord(0, 1, 0, 1)
	-- Mask APIs (CreateMaskTexture / atlas-on-mask / AddMaskTexture) vary across
	-- client builds, and a thrown error here would abort the whole button setup —
	-- which breaks layout/sizing and the settings callbacks. Top priority is to
	-- never break, so guard the mask setup and fall back to the unmasked icon.
	local mask
	local ok = pcall(function()
		mask = b:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
		-- Seed it onto the icon; LayoutIconFrameSkin re-sizes it to ~1.42x so the art
		-- fills out under the metal ring (no dark slot ring at the edges).
		mask:SetAllPoints(b.icon)
		b.icon:AddMaskTexture(mask)
	end)
	if ok and mask then
		b.iconMask = mask
	else
		if mask then
			pcall(function()
				b.icon:RemoveMaskTexture(mask)
			end)
		end
		b.iconMask = nil
	end
end

-- Builds Blizzard's modern icon-frame skin on `b`: a dark slot backing (drawn
-- behind the icon) plus the metal border, the border hosted on a dedicated overlay
-- frame a few levels up so it always renders above the cooldown swipe rather than
-- sinking behind it. The caller is responsible for sizing via LayoutIconFrameSkin.
-- Shared so the suggestion button and the interrupt companion are skinned the same.
local function BuildIconFrameSkin(b)
	b.slot = b:CreateTexture(nil, "BACKGROUND")
	b.slot:SetAtlas("UI-HUD-ActionBar-IconFrame-Slot")
	b.slot:SetPoint("CENTER", b, "CENTER", 0, 0)

	b.frameOverlay = NS.CreateFrame("Frame", nil, b)
	b.frameOverlay:SetAllPoints(b)
	b.frameOverlay:SetFrameLevel(b:GetFrameLevel() + 4)

	b.border = b.frameOverlay:CreateTexture(nil, "OVERLAY", nil, 0)
	b.border:SetAtlas("UI-HUD-ActionBar-IconFrame")
	b.border:SetPoint("CENTER", b, "CENTER", 0, 0)
end

-- Proc glow via embedded LibCustomGlow (ProcGlow_Start/Stop). The hand-rolled flipbook
-- path was unreliable on addon frames; LCG handles sizing, OnShow, and anim wiring.
local LCG_GLOW_KEY = "BBA"

local function GetProcGlowFrame(b)
	return b and b["_ProcGlow" .. LCG_GLOW_KEY]
end

local function ResolveGlowColor(b)
	local preset
	if b.isDefensive then
		preset = NS.db.defensiveGlowColor or "green"
	else
		preset = NS.db.glowColor or "gold"
	end
	-- nil keeps Blizzard's stock proc art (undesaturated).
	if preset == "white" or preset == "gold" then
		return nil
	end
	if type(preset) == "table" then
		return { preset[1], preset[2], preset[3], 1 }
	end
	local g = NS.GlowColorPresets and NS.GlowColorPresets[preset]
	if g then
		return { g[1], g[2], g[3], 1 }
	end
	return nil
end

local function ApplyOneButtonProcAtlases(b)
	local f = GetProcGlowFrame(b)
	if f and f.ProcStart and f.ProcLoop then
		f.ProcStart:SetAtlas("OneButton_ProcStart_Flipbook")
		f.ProcLoop:SetAtlas("OneButton_ProcLoop_Flipbook")
	end
end

-- Re-run LCG's OnShow anim path after a live atlas swap (onebutton style).
local function RestartProcGlowAnim(b)
	local f = GetProcGlowFrame(b)
	if not f or not f:IsShown() then
		return
	end
	if f.ProcStartAnim then
		f.ProcStartAnim:Stop()
	end
	if f.ProcLoopAnim then
		f.ProcLoopAnim:Stop()
	end
	if f.startAnim then
		local width, height = f:GetSize()
		f.ProcStart:SetSize((width / 42 * 150) / 1.4, (height / 42 * 150) / 1.4)
		f.ProcStart:Show()
		f.ProcLoop:Hide()
		f.ProcStartAnim:Play()
	else
		f.ProcStart:Hide()
		f.ProcLoop:Show()
		f.ProcLoopAnim:Play()
	end
end

local function ProcGlowStop(b)
	local lcg = NS.LibCustomGlow
	b._glowStartGen = (b._glowStartGen or 0) + 1
	if lcg and lcg.ProcGlow_Stop then
		lcg.ProcGlow_Stop(b, LCG_GLOW_KEY)
	end
	b._glowActive = false
end

local function DefaultGlowHostSize(b)
	if b.isDefensive then
		return (NS.db and NS.db.defensiveSize) or 32
	end
	if b.slotID then
		return (NS.db and NS.db.trinketSize) or 36
	end
	return (NS.db and NS.db.buttonSize) or 80
end

-- LCG ProcGlow sizes from the host frame on Show(). After /reload the first Start can
-- run before layout resolves, so flipbook cells sample a zero/wrong rect (giant square).
local function EnsureGlowHostSized(b)
	local w, h = b:GetSize()
	if not w or w <= 0 or not h or h <= 0 then
		w = DefaultGlowHostSize(b)
		b:SetSize(w, w)
	end
	return w
end

local function ProcGlowStartImpl(b)
	local lcg = NS.LibCustomGlow
	if not lcg or not lcg.ProcGlow_Start or not b._glowActive then
		return false
	end
	EnsureGlowHostSized(b)
	lcg.ProcGlow_Stop(b, LCG_GLOW_KEY)
	lcg.ProcGlow_Start(b, {
		key = LCG_GLOW_KEY,
		color = ResolveGlowColor(b),
		startAnim = true,
		frameLevel = 6,
	})
	if NS.db and NS.db.glowStyle == "onebutton" then
		ApplyOneButtonProcAtlases(b)
		RestartProcGlowAnim(b)
	end
	return true
end

local function ProcGlowStart(b)
	local lcg = NS.LibCustomGlow
	if not lcg or not lcg.ProcGlow_Start then
		return false
	end
	b._glowActive = true
	b._glowStartGen = (b._glowStartGen or 0) + 1
	local gen = b._glowStartGen

	local function Begin()
		if not b._glowActive or b._glowStartGen ~= gen then
			return
		end
		ProcGlowStartImpl(b)
	end

	-- Always defer one frame so anchor/size are committed before LCG's OnShow anim.
	if NS.RunNextFrame then
		NS.RunNextFrame(Begin)
	elseif NS.C_Timer_After then
		NS.C_Timer_After(0, Begin)
	else
		ProcGlowStartImpl(b)
	end
	return true
end

local function AttachProcGlow(b)
	b:HookScript("OnHide", function(self)
		ProcGlowStop(self)
		self._glowActive = false
	end)
end

local function ApplyGlowStyle(b)
	if b and b._glowActive then
		ProcGlowStart(b)
	end
end

local function CreateSuggestionButton(parent)
	local b = NS.CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b.isMainSuggestion = true
	b:SetSize(NS.db.buttonSize, NS.db.buttonSize)
	b:SetFrameLevel(parent:GetFrameLevel() + 2)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()

	b.cooldown = NS.CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints(b.icon)
	b.cooldown:SetFrameLevel(b:GetFrameLevel())
	BindCooldownText(b.cooldown)
	b.cooldown:HookScript("OnShow", function()
		RefreshMainCooldownFont(b)
	end)

	-- Blizzard icon-frame art (dark slot backing + metal border on a dedicated overlay
	-- a few levels up, so the border always draws above the cooldown swipe instead of
	-- sinking behind it). Shared with the companion icons via BuildIconFrameSkin so
	-- every icon in the addon is framed identically. Built after the cooldown so the
	-- overlay's frame level lands above the swipe; sized in LayoutIconFrameSkin.
	BuildIconFrameSkin(b)

	-- Round the icon corners with Blizzard's own mask so it matches the frame's
	-- rounded interior (sized in LayoutIconFrameSkin).
	ApplyIconMask(b)

	-- Keybind lives on the frame overlay (above the metal border) so it's never
	-- covered by the IconFrame art. The border is a child-frame region, which always
	-- draws above the button's own regions, so a hotkey on `b` would sit under it.
	b.hotkey = b.frameOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall") -- Using a cleaner number font
	b.hotkey:SetPoint("TOPRIGHT", b.icon, "TOPRIGHT", -6, -6)
	b.hotkey:SetJustifyH("RIGHT")
	b.hotkey:SetDrawLayer("OVERLAY", 7)

	-- Proc/activation glow via LibCustomGlow (shared by suggestion + companions).
	AttachProcGlow(b)

	b.spellID = nil

	NS.ApplyGlowColor(b)
	SkinButton(b)

	return b
end

-- Tints the proc glow from settings. LibCustomGlow desaturates when color is set.
function NS.ApplyGlowColor(b)
	if b and b._glowActive then
		ProcGlowStart(b)
	end
end

local function SetGlowShown(b, shown)
	if not b then
		return
	end
	shown = not not shown
	if b._glowActive == shown then
		return
	end
	if shown then
		if not ProcGlowStart(b) then
			b._glowActive = false
		end
	else
		ProcGlowStop(b)
	end
end

-- Companion cooldown numbers are opt-in. Keep this out of the tick path unless a
-- companion is being created or relaid out from settings.
local function ApplyCompanionCooldownNumbers(f)
	if f and f.cooldown then
		f.cooldown:SetHideCountdownNumbers(not (NS.db and NS.db.companionCooldownNumbers))
	end
end

-- Builds a companion icon button: icon + cooldown swipe + the shared Blizzard
-- icon-frame skin (slot backing + metal border) + rounded icon mask + proc glow +
-- Masque routing, sized and laid out. Shared by the interrupt indicator and the
-- trinket frames so every companion is built and skinned exactly like the main
-- button. The caller positions it and sets any per-companion data (slotID, alpha).
-- Attaches a lightweight GameTooltip hover to a companion icon frame.
-- `titleFn()` returns the first tooltip line (spell/item name).
-- `bodyFn()` optionally returns a second status line. Both are evaluated lazily
-- on hover so they always reflect the current state.
local function CompanionSpellTooltipTitle(spellID, fallback)
	if not spellID then
		return fallback
	end
	if issecretvalue and issecretvalue(spellID) then
		return fallback
	end
	if NS.C_Spell_GetSpellInfo then
		local info = NS.C_Spell_GetSpellInfo(spellID)
		local name = info and info.name
		if name and not (issecretvalue and issecretvalue(name)) then
			return name
		end
	end
	return fallback
end

local function SetupCompanionTooltip(f, titleFn, bodyFn)
	f:EnableMouse(true)
	f:SetScript("OnEnter", function(self)
		local tip = NS.GameTooltip
		if not tip or tip:IsForbidden() then return end
		tip:SetOwner(self, "ANCHOR_RIGHT")
		local ok = NS.pcall(function()
			local title = titleFn and titleFn()
			if title and title ~= "" then
				tip:AddLine(title, 1, 1, 1)
			end
			local body = bodyFn and bodyFn()
			if body and body ~= "" then
				tip:AddLine(body, 0.7, 0.7, 0.7, true)
			end
		end)
		if ok then
			tip:Show()
		end
	end)
	f:SetScript("OnLeave", function()
		local tip = NS.GameTooltip
		if tip and not tip:IsForbidden() then tip:Hide() end
	end)
end

local function BuildCompanionIcon(parent, size)
	local f = NS.CreateFrame("Frame", nil, parent)
	-- Size before the skin/glow so their seed sizes are correct even if the per-tick
	-- path creates the frame before the next LayoutCompanions/LayoutTrinkets pass.
	f:SetSize(size, size)

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()

	f.cooldown = NS.CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cooldown:SetAllPoints()
	f.cooldown:SetDrawEdge(false)
	f.cooldown:SetDrawBling(false)
	BindCooldownText(f.cooldown)
	f.cooldown:HookScript("OnShow", function()
		RefreshCompanionCooldownFont(f)
	end)
	ApplyCompanionCooldownNumbers(f)

	-- BuildIconFrameSkin must precede AttachProcGlow (LCG anchors to frameOverlay level).
	BuildIconFrameSkin(f)
	ApplyIconMask(f)
	AttachProcGlow(f)
	SkinButton(f)
	NS.ApplyGlowColor(f)
	LayoutCompanionCooldown(f, size)

	f:Hide()
	return f
end

-- True if the given spell (or its base form) currently has an active proc glow.
local function IsSpellGlowing(spellID)
	if not spellID then
		return false
	end
	local glowing = NS.GlowingSpells
	if glowing[spellID] then
		return true
	end
	-- Secret IDs cannot be compared or resolved to display/base variants.
	if issecretvalue and issecretvalue(spellID) then
		return false
	end
	local displayID = NS.GetDisplaySpellID and NS.GetDisplaySpellID(spellID)
	if displayID and displayID ~= spellID and glowing[displayID] then
		return true
	end
	local base = NS.FindBaseSpellByID and NS.FindBaseSpellByID(spellID)
	return base ~= nil and glowing[base] == true
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

	-- Blizzard's modern IconFrame is 46x45 around a 45px button (see
	-- LayoutIconFrameSkin); applying that ratio keeps the metal lip hugging the icon
	-- at every button size instead of flaring out.
	LayoutIconFrameSkin(b, size, NS.db.showBorder)
	if b._glowActive then
		ApplyGlowStyle(b)
	end

	-- Update Font Size
	local fontPath, _, fontFlags = b.hotkey:GetFont()
	b.hotkey:SetFont(fontPath, NS.db.keybindFontSize or 12, fontFlags)

	-- Update Frame properties
	frame:SetSize(size, size)

	-- Frame strata (draw order vs. the rest of the UI).
	if NS.db.strata then
		frame:SetFrameStrata(NS.db.strata)
	end

	-- Scale. trueScale snaps the button to whole physical pixels (768 / physical
	-- screen height / UIParent scale) so the icon art never lands on a half-pixel
	-- and blurs; the user scale then multiplies on top of that pixel-perfect base.
	local userScale = NS.db.scale or 1.0
	if NS.db.trueScale and NS.GetPhysicalScreenSize then
		local _, physH = NS.GetPhysicalScreenSize()
		local uiScale = NS.UIParent:GetScale()
		if physH and physH > 0 and uiScale and uiScale > 0 then
			frame:SetScale(userScale * (768 / physH / uiScale))
		else
			frame:SetScale(userScale)
		end
	else
		frame:SetScale(userScale)
	end

	NS.ApplyGlowColor(b)
	NS.ApplyCooldownStyle(b)
	NS.UpdateMouseState()

	-- Size/position the interrupt icon + nameplate counter alongside the button.
	if NS.LayoutCompanions then
		NS.LayoutCompanions()
	end

	b:Show()
end

-- Applies the cooldown swipe draw style from settings. This only changes when the
-- user toggles the option, so it lives at layout time rather than on the hot tick.
function NS.ApplyCooldownStyle(b)
	if not b.cooldown then
		return
	end
	local showCD = NS.db.showCooldown
	b.cooldown:SetDrawBling(showCD)
	b.cooldown:SetDrawEdge(showCD)
	b.cooldown:SetSwipeColor(0, 0, 0, showCD and 0.8 or 0)
	b.cooldown:SetHideCountdownNumbers(false)
	local size = b:GetWidth() or (NS.db and NS.db.buttonSize) or 40
	ApplyCooldownFontSize(b.cooldown, size, true)
end

-- Midnight (build 66562+) secret-safe swipe. Returns a DurationObject the Cooldown
-- widget can render without us ever reading the secret start/duration, or nil when
-- the spell isn't on cooldown / can't be resolved.
--   * Prefer the action-bar slot: GetActionCooldown(slot).isActive is NeverSecret,
--     so we can gate the swipe on/off, and GetActionCooldownDuration is slot-based
--     and fully secret-safe.
--   * Off-bar fallback (assisted-combat-only spells): the spell DurationObject,
--     which self-describes its active state (a ready spell renders no swipe).
local function GetCooldownDurationObject(spellID)
	local slot = ResolveActionSlot(spellID)
	if slot and C_ActionBar_GetActionCooldownDuration then
		local info = C_ActionBar_GetActionCooldown and C_ActionBar_GetActionCooldown(slot)
		if info and info.isActive then
			return C_ActionBar_GetActionCooldownDuration(slot)
		end
		return nil
	end

	if C_Spell_GetSpellCooldownDuration then
		local ok, durObj = NS.pcall(C_Spell_GetSpellCooldownDuration, spellID)
		if ok then
			return durObj
		end
	end

	return nil
end

-- Evoker empower staging. An empowered spell is a channel reporting numStages > 0;
-- the player advances through stages over time. We walk the per-stage durations
-- (all GetTime-based, never secret) to find the current stage, and call it "ready
-- to release" once it reaches the configured minimum. Returns false for any other
-- class/spell so callers can fall through to normal cooldown handling.
local function IsEmpowerReady()
	if not UnitChannelInfo or not GetUnitEmpowerStageDuration then
		return false
	end

	local _, _, _, startMS, _, _, _, _, _, numStages = UnitChannelInfo("player")
	if not numStages or numStages <= 0 or not startMS then
		return false
	end

	local elapsed = GetTime() - startMS / 1000
	local cumulative, currentStage = 0, 0
	for i = 0, numStages - 1 do
		cumulative = cumulative + GetUnitEmpowerStageDuration("player", i) / 1000
		if elapsed >= cumulative then
			currentStage = i + 1
		end
	end

	local minStage = NS.db.empowerMinStage or 1
	return minStage > 0 and currentStage >= minStage
end

-- Optionally mirrors the player's in-progress hardcast/channel as the swipe. The
-- timing comes from the player's own cast (UnitCastingInfo/UnitChannelInfo), which
-- is never secret. Empowered channels are special-cased: once the release stage is
-- reached the swipe is cleared, reading as "let go now" rather than a filling bar.
-- Returns true when it took over the swipe so the caller skips the cooldown path.
local function TryShowCastProgress(b)
	if not UnitCastingInfo or not UnitChannelInfo then
		return false
	end

	local now = GetTime()

	-- Channels (includes empowered spells, which report numStages > 0).
	local name, _, _, startMS, endMS, _, _, _, _, numStages = UnitChannelInfo("player")
	if name and startMS and endMS and endMS / 1000 > now then
		if numStages and numStages > 0 and IsEmpowerReady() then
			b.cooldown:Clear()
			b.cooldown:Hide()
			return true
		end
		if SafeSetCooldown(b.cooldown, startMS / 1000, (endMS - startMS) / 1000) then
			RefreshMainCooldownFont(b)
			return true
		end
	end

	-- Hardcasts.
	name, _, _, startMS, endMS = UnitCastingInfo("player")
	if name and startMS and endMS and endMS / 1000 > now then
		if SafeSetCooldown(b.cooldown, startMS / 1000, (endMS - startMS) / 1000) then
			RefreshMainCooldownFont(b)
			return true
		end
	end

	return false
end

local function UpdateCooldownForSpell(b, spellID)
	if not NS.db.showCooldown then
		b.cooldown:Clear()
		b.cooldown:Hide()
		return
	end

	-- A live cast/channel takes precedence over the resting cooldown swipe so the
	-- button reflects what the player is doing right now (opt-in via showCastProgress).
	if NS.db.showCastProgress and TryShowCastProgress(b) then
		return
	end

	-- Midnight: SetCooldown rejects secret start/duration, so drive the swipe from a
	-- DurationObject instead. This finally shows the cooldown in combat (the legacy
	-- path could only hide it once the values went secret).
	if IS_DURATION_COOLDOWNS then
		local durObj = GetCooldownDurationObject(spellID)
		if durObj then
			b.cooldown:SetCooldownFromDurationObject(durObj)
			b.cooldown:Show()
			RefreshMainCooldownFont(b)
		else
			b.cooldown:Clear()
			b.cooldown:Hide()
		end
		return
	end

	-- Pre-66562 / pre-Midnight: classic start/duration passthrough.
	local startTime, duration, _, modRate = GetSpellCooldownForDisplay(spellID)
	if duration then
		SafeSetCooldown(b.cooldown, startTime, duration, modRate)
		RefreshMainCooldownFont(b)
	else
		b.cooldown:Hide()
	end
end

-- =====================================================================
-- Interrupt indicator  (MODULE: Companions — Modules/Companions.lua)
-- =====================================================================
local INTERRUPT_DIM = 0.25 -- nothing to kick / out of range / on cooldown-ish
local INTERRUPT_ON_CD = 0.5 -- castable target but our interrupt is down
local INTERRUPT_READY = 1.0 -- kick it now

local function EnsureInterruptFrame()
	if interruptFrame then
		return interruptFrame
	end
	-- Shared companion-icon builder (icon-frame skin + rounded mask + proc "kick now"
	-- glow + Masque), sized to the main button so the interrupt matches it exactly.
	local f = BuildCompanionIcon(frame, NS.db.buttonSize or 40)
	f.isInterrupt = true
	f:SetAlpha(INTERRUPT_DIM)

	-- Hover tooltip: spell name + live cast/cooldown status so the user can
	-- confirm what the icon is tracking and why it's dim/bright/glowing.
	SetupCompanionTooltip(f,
		function()
			if not interruptSpellID then return "Interrupt" end
			local name
			if NS.C_Spell_GetSpellInfo then
				local info = NS.C_Spell_GetSpellInfo(interruptSpellID)
				name = info and info.name
			end
			return name or ("Interrupt (spell " .. interruptSpellID .. ")")
		end,
		function()
			-- NOTE: cannot call ActiveInterruptUnit() here — it is declared
			-- later in the file, so Lua 5.1 resolves it as a global (nil).
			-- Inline the essential watch-unit resolution directly instead.
			local setting = (NS.db and NS.db.interruptUnit) or "target"
			local unit
			if setting == "auto" then
				if interruptCastMode.focus and UnitExists("focus") then
					unit = "focus"
				elseif interruptCastMode.target and UnitExists("target") then
					unit = "target"
				elseif UnitExists("focus") then
					unit = "focus"
				else
					unit = "target"
				end
			else
				unit = setting
			end

			local castMode = interruptCastMode[unit]
			local uName    = UnitExists(unit) and UnitName(unit)
			if uName and NS.issecretvalue and NS.issecretvalue(uName) then
				uName = nil
			end
			local unitLabel = uName or unit
			if castMode then
				return unitLabel .. " is casting — interrupt!"
			elseif UnitExists(unit) then
				return "Watching " .. unitLabel .. " (no cast)"
			end
			return "No target"
		end
	)

	interruptFrame = f
	return f
end

-- Picks the player's interrupt for the current spec: first known line in the table,
-- resolved through its active override (talented variants). Player-owned data only.
function NS.DetectInterruptSpell()
	interruptSpellID = nil
	if not C_SpellBook_IsSpellInSpellBook or not INTERRUPT_SPELLS then
		return
	end

	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	for i = 1, #INTERRUPT_SPELLS do
		local id = INTERRUPT_SPELLS[i]
		-- The API signature has varied across builds; try with the bank, then without.
		local known
		if bank ~= nil then
			local ok, res = NS.pcall(C_SpellBook_IsSpellInSpellBook, id, bank)
			known = ok and res
		end
		if known == nil then
			local ok, res = NS.pcall(C_SpellBook_IsSpellInSpellBook, id)
			known = ok and res
		end

		if known == true then
			local resolved = id
			if C_Spell_GetOverrideSpell then
				local ok, ov = NS.pcall(C_Spell_GetOverrideSpell, id, 0, false)
				if ok and ov and not (issecretvalue and issecretvalue(ov)) then
					resolved = ov
				end
			end
			interruptSpellID = resolved
			local f = EnsureInterruptFrame()
			if C_Spell_GetSpellTexture then
				f.icon:SetTexture(C_Spell_GetSpellTexture(resolved))
			end
			return
		end
	end
end

-- Routes the (possibly secret) notInterruptible flag to alpha without ever reading
-- it in a conditional. SetAlphaFromBoolean is the Blizzard-sanctioned secret sink;
-- fall back gracefully on older clients, and fail open if we somehow can't read it.
local function SetInterruptActiveAlpha(f, notInterruptible, activeAlpha)
	-- Secret flag: route it through the sanctioned sink (never branch on it). Fail
	-- open to "kickable" on clients without the method so we never hide a needed kick.
	-- Return nil because the glow is a Show/Hide decision, not a secret sink.
	if issecretvalue and issecretvalue(notInterruptible) then
		if f.SetAlphaFromBoolean then
			f:SetAlphaFromBoolean(notInterruptible, INTERRUPT_DIM, activeAlpha)
		else
			f:SetAlpha(activeAlpha)
		end
		return nil
	end

	-- Non-secret (including nil/false/true): safe to read directly.
	if notInterruptible then
		f:SetAlpha(INTERRUPT_DIM)
		return false
	else
		f:SetAlpha(activeAlpha)
		return true
	end
end

-- Returns tri-state cooldown readiness for the player's interrupt spell:
--   true  = confirmed off cooldown (ready to kick)
--   false = confirmed on cooldown  (can't kick)
--   nil   = unknown                (no bar slot, no API data)
-- Now that GetSpellCooldownDuration nil=ready / non-nil=on-CD is confirmed by
-- API docs (MayReturnNothing=true), RenderCooldownReadiness returns a proper
-- tri-state instead of always-nil for the off-bar path.
local function GetInterruptReadiness(f)
	return RenderCooldownReadiness(f.cooldown, interruptSpellID)
end

-- Resolves which unit the indicator reflects, per the interruptUnit setting.
--   "target"/"focus": that unit, always.
--   "auto": prefer a focus that's mid-cast, else a target that's mid-cast, else a
--           focus if one exists (so a focus-kicker still sees range/CD at rest),
--           else the target. This makes the single icon track whatever is actually
--           interruptible without the player having to pick.
local function ActiveInterruptUnit()
	local mode = (NS.db and NS.db.interruptUnit) or "target"
	if mode == "target" or mode == "focus" then
		return mode
	end
	if interruptCastMode.focus and UnitExists("focus") then
		return "focus"
	end
	if interruptCastMode.target and UnitExists("target") then
		return "target"
	end
	if UnitExists("focus") then
		return "focus"
	end
	return "target"
end

function NS.UpdateInterrupt()
	if not NS.db or not NS.db.interruptEnabled then
		if interruptFrame then
			interruptFrame:Hide()
		end
		return
	end

	local f = EnsureInterruptFrame()
	f:Show()

	if not interruptSpellID then
		NS.DetectInterruptSpell()
	end

	local unit = ActiveInterruptUnit()
	local mode = interruptCastMode[unit]

	-- Nothing to kick: dim and clear.
	if not interruptSpellID or not mode or not UnitExists(unit) or not UnitCanAttack("player", unit) then
		f:SetAlpha(INTERRUPT_DIM)
		f.cooldown:Clear()
		SetGlowShown(f, false)
		return
	end

	-- Range gate (fail open when the result is secret or unknown).
	if C_Spell_IsSpellInRange then
		local inRange = C_Spell_IsSpellInRange(interruptSpellID, unit)
		if not (issecretvalue and issecretvalue(inRange)) and inRange == false then
			f:SetAlpha(INTERRUPT_DIM)
			f.cooldown:Clear()
			SetGlowShown(f, false)
			return
		end
	end

	-- Tri-state: true=confirmed ready, false=confirmed on-CD, nil=unknown.
	-- Using tri-state instead of the old boolean lets the glow require positive
	-- confirmation on BOTH conditions, eliminating false positives.
	local readiness = GetInterruptReadiness(f)
	local onCd = readiness == false  -- true only when we can confirm the CD is active
	local activeAlpha = onCd and INTERRUPT_ON_CD or INTERRUPT_READY

	local notInterruptible
	if mode == "channel" then
		notInterruptible = select(7, UnitChannelInfo(unit))
	else
		notInterruptible = select(8, UnitCastingInfo(unit))
	end

	local canKick = SetInterruptActiveAlpha(f, notInterruptible, activeAlpha)

	-- Glow only when BOTH conditions are positively confirmed (fail-closed):
	--   readiness == true : we KNOW the interrupt is off cooldown (not just "unknown")
	--   canKick == true   : we KNOW the target's cast IS interruptible (not secret/nil)
	-- Previously the glow used `not onCd and canKick ~= false` (fail-open): unknown
	-- cooldown (nil) counted as "ready" and secret notInterruptible (nil) counted as
	-- "interruptible", causing the glow to fire when the interrupt was on CD or the
	-- spell was immune. The strict == true check removes both false-positive paths.
	local wantGlow = false
	if NS.db.interruptGlow and readiness == true then
		if issecretvalue and issecretvalue(notInterruptible) then
			-- Secret interruptibility: drive glow visibility via the sanctioned sink
			-- (visible when cast IS interruptible) instead of fail-closed Show/Hide.
			wantGlow = true
		elseif canKick == true then
			wantGlow = true
		end
	end
	SetGlowShown(f, wantGlow)

	if wantGlow and issecretvalue and issecretvalue(notInterruptible) then
		local glowFrame = GetProcGlowFrame(f)
		if glowFrame and glowFrame.SetAlphaFromBoolean then
			glowFrame:SetAlphaFromBoolean(notInterruptible, 0, 1)
		end
	elseif wantGlow then
		local glowFrame = GetProcGlowFrame(f)
		if glowFrame then
			glowFrame:SetAlpha(1)
		end
	end
end

-- True if this unit's cast events should drive the interrupt indicator under the
-- current interruptUnit setting (target / focus / auto = both). Cast events for the
-- non-watched unit are filtered out cheaply so a target cast can't drive a focus-only
-- indicator and vice-versa.
local function IsWatchedInterruptUnit(unit)
	local mode = (NS.db and NS.db.interruptUnit) or "target"
	if mode == "auto" then
		return unit == "target" or unit == "focus"
	end
	return unit == mode
end

-- Target/focus cast/channel tracking. The event *firing* is public even when its
-- payload is secret, so the per-unit mode flag is always safe to set here. The unit
-- arrives as the event's first arg (RegisterUnitEvent guarantees it's one we watch).
local function OnTargetCastStart(unit)
	if not IsWatchedInterruptUnit(unit) then
		return
	end
	interruptCastMode[unit] = "cast"
	NS.UpdateInterrupt()
end

local function OnTargetChannelStart(unit)
	if not IsWatchedInterruptUnit(unit) then
		return
	end
	interruptCastMode[unit] = "channel"
	NS.UpdateInterrupt()
end

local function OnTargetCastStop(unit)
	if unit ~= "target" and unit ~= "focus" then
		return
	end
	interruptCastMode[unit] = nil
	NS.UpdateInterrupt()
end

-- On a target/focus swap the in-progress cast won't re-fire its START event, so probe
-- once. Guarded: if the cast name is secret we can't read it, and just wait for the
-- next START event instead of risking a conditional on a secret value.
local function PollInterruptUnit(unit)
	interruptCastMode[unit] = nil
	if not UnitExists(unit) then
		return
	end
	local castName = UnitCastingInfo(unit)
	if not (issecretvalue and issecretvalue(castName)) then
		if castName then
			interruptCastMode[unit] = "cast"
			return
		end
	end
	local channelName = UnitChannelInfo(unit)
	if not (issecretvalue and issecretvalue(channelName)) then
		if channelName then
			interruptCastMode[unit] = "channel"
		end
	end
end

local function PollAllInterruptUnits()
	PollInterruptUnit("target")
	PollInterruptUnit("focus")
end

local INTERRUPT_TARGET_EVENTS = {
	"UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTED",
}

-- Conditional event registration: the cast events only wake us up while the interrupt
-- indicator is enabled (optimization-guide §5), and only for the unit(s) the current
-- interruptUnit setting actually watches (target / focus / both for auto). The
-- focus-changed event is registered only when a focus is involved.
function NS.UpdateInterruptRegistration()
	local on = NS.db and NS.db.interruptEnabled
	local mode = (NS.db and NS.db.interruptUnit) or "target"
	local watchFocus = on and (mode == "focus" or mode == "auto")
	for i = 1, #INTERRUPT_TARGET_EVENTS do
		local ev = INTERRUPT_TARGET_EVENTS[i]
		if on then
			if mode == "focus" then
				addonFrame:RegisterUnitEvent(ev, "focus")
			elseif mode == "auto" then
				addonFrame:RegisterUnitEvent(ev, "target", "focus")
			else
				addonFrame:RegisterUnitEvent(ev, "target")
			end
		else
			if addonFrame.UnregisterUnitEvent then
				addonFrame:UnregisterUnitEvent(ev)
			else
				addonFrame:UnregisterEvent(ev)
			end
		end
	end
	if watchFocus then
		addonFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
	else
		addonFrame:UnregisterEvent("PLAYER_FOCUS_CHANGED")
	end
	if on then
		NS.DetectInterruptSpell()
		PollAllInterruptUnits()
	end
	NS.UpdateInterrupt()
end

-- =====================================================================
-- Nameplate enemy counter
-- A small count above the button of how many attackable enemies have a nameplate
-- up — a cheap "how many things are on me" readout for AoE decisions.
-- =====================================================================
local function EnsureCounter()
	if counterText then
		return counterText
	end
	counterText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	counterText:SetPoint("BOTTOM", frame, "TOP", 0, 3)
	counterText:Hide()
	return counterText
end

-- Cached enemy-nameplate count. The set of plates only changes on NAME_PLATE_UNIT
-- ADDED/REMOVED, so we recount only there (NS.RefreshNameplateCount) and the spammy
-- per-tick render just reads this O(1) — no per-tick loop over every plate.
local nameplateEnemyCount = 0

local function CountEnemyNameplates()
	if not C_NamePlate or not C_NamePlate.GetNamePlates then
		return 0
	end
	local plates = C_NamePlate.GetNamePlates()
	local n = 0
	for i = 1, #plates do
		local plate = plates[i]
		local token = plate and plate.namePlateUnitToken
		if token then
			local attackable = UnitCanAttack("player", token)
			-- In instances attackability can be secret; counting the plate anyway is
			-- intentional fail-open (friendly nameplates are off by default).
			if issecretvalue and issecretvalue(attackable) then
				n = n + 1
			elseif attackable then
				n = n + 1
			end
		end
	end
	return n
end

-- Renders the cached count. Cheap enough to run on the per-tick path (it only
-- touches the font string when the displayed value actually changes).
function NS.UpdateNameplateCounter()
	if not NS.db or not NS.db.nameplateCounterEnabled then
		if counterText then
			counterText:Hide()
		end
		return
	end

	local t = EnsureCounter()
	if NS.db.nameplateCounterCombatOnly and not NS.UnitAffectingCombat("player") then
		t:Hide()
		lastCounterText = nil
		return
	end

	local count = nameplateEnemyCount
	if count >= (NS.db.nameplateCounterMin or 1) then
		-- Only repaint the font string when the count actually changes.
		if count ~= lastCounterText then
			t:SetText(count)
			lastCounterText = count
		end
		t:Show()
	else
		t:Hide()
		lastCounterText = nil
	end
end

-- Recount (only on plate add/remove) then render. This is the event handler; the
-- per-tick path uses the cached count via NS.UpdateNameplateCounter above.
function NS.RefreshNameplateCount()
	nameplateEnemyCount = CountEnemyNameplates()
	NS.UpdateNameplateCounter()
end

function NS.UpdateNameplateRegistration()
	local on = NS.db and NS.db.nameplateCounterEnabled
	if on then
		addonFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
		addonFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
		-- Seed the cached count immediately so the readout is correct without waiting
		-- for the next plate add/remove.
		NS.RefreshNameplateCount()
	else
		addonFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
		addonFrame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
		NS.UpdateNameplateCounter()
	end
end

-- =====================================================================
-- Target range readout
-- An estimated distance (yards) to the current target, drawn below the button.
-- The number comes from the item-distance module (NS.Range); the color reflects
-- whether the target is in range of the spec's spell-range list. Both inputs are
-- secret-safe (they return nil when they can't measure), so this never branches
-- on a secret value.
-- =====================================================================
local function UpdateRangeReadoutAnchor()
	if not rangeReadout then
		return
	end
	rangeReadout:ClearAllPoints()

	-- Use the chained below-side extent (interrupt + queue + stacks on "below").
	local belowUsed = sideUsed.below or 0
	if belowUsed > 0 then
		rangeReadout:SetPoint("TOP", frame, "BOTTOM", 0, -(belowUsed + 2))
	else
		rangeReadout:SetPoint("TOP", frame, "BOTTOM", 0, -2)
	end
end

-- =====================================================================
-- Target range readout
-- An estimated distance (yards) to the current target, drawn below the button.
-- The number comes from the item-distance module (NS.Range); the color reflects
-- whether the target is in range of the spec's spell-range list. Both inputs are
-- secret-safe (they return nil when they can't measure), so this never branches
-- on a secret value.
-- =====================================================================
local function EnsureRangeReadout()
	if rangeReadout then
		return rangeReadout
	end
	rangeReadout = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rangeReadout:SetPoint("TOP", frame, "BOTTOM", 0, -2)
	rangeReadout:SetJustifyH("CENTER")
	rangeReadout:SetWordWrap(false)
	rangeReadout:Hide()
	if NS.Range and NS.Range.Init then
		NS.Range.Init()
	end
	return rangeReadout
end

function NS.UpdateRangeReadout()
	if not NS.db or not NS.db.rangeReadoutEnabled then
		if rangeReadout then
			rangeReadout:Hide()
		end
		return
	end

	local t = EnsureRangeReadout()
	if NS.db.rangeReadoutCombatOnly and not NS.UnitAffectingCombat("player") then
		t:Hide()
		lastRangeText = nil
		return
	end

	local minR, maxR
	if NS.Range and NS.Range.GetTargetRange then
		minR, maxR = NS.Range.GetTargetRange()
	end
	if not minR then
		t:Hide()
		lastRangeText = nil
		return
	end

	-- Point-blank reads carry no useful distance, so don't show anything: this is the
	-- "0 yd" case (band collapses to zero, or an open-ended band whose floor is 0).
	if (maxR and maxR <= 0) or (not maxR and minR <= 0) then
		t:Hide()
		lastRangeText = nil
		return
	end

	-- Honest band: "n-m yd", "<m yd" for the melee bracket (lower bound 0), or "n+ yd"
	-- when the target is beyond our longest checker. Past the cap the exact distance is
	-- unactionable, so clamp to "<cap>+ yd". Only repaint when the text actually changes
	-- (the tick runs many times a second; the band rarely moves between reads).
	local text
	if minR >= RANGE_READOUT_CAP then
		text = string_format("%d+ yd", RANGE_READOUT_CAP)
	elseif not maxR then
		text = string_format("%d+ yd", minR)
	elseif minR <= 0 then
		text = string_format("<%d yd", maxR)
	else
		text = string_format("%d-%d yd", minR, maxR)
	end
	if text ~= lastRangeText then
		t:SetText(text)
		lastRangeText = text
	end

	-- Color the readout in/out of range. Default (zero-config) source is the
	-- currently-suggested spell's own range, so it's useful for everyone out of the
	-- box. A per-spec spell-range list (Advanced) overrides this when filled in, for
	-- players who want it keyed off specific abilities. Both are secret-safe and
	-- return nil ("can't tell") rather than guessing, in which case we stay neutral.
	local inRange = NS.IsTargetInSpecRange and NS.IsTargetInSpecRange()
	if inRange == nil then
		local b = frame.button
		local sid = b and b.spellID
		if sid and C_Spell_IsSpellInRange then
			local r = C_Spell_IsSpellInRange(sid, "target")
			if not (issecretvalue and issecretvalue(r)) then
				if r == true then
					inRange = true
				elseif r == false then
					inRange = false
				end
			end
		end
	end

	-- Repaint the color only when the in/out/neutral state flips.
	local colorState = (inRange == true and "in") or (inRange == false and "out") or "neutral"
	if colorState ~= lastRangeColor then
		if colorState == "in" then
			local c = NS.db.colorInRange
			t:SetTextColor(c[1], c[2], c[3])
		elseif colorState == "out" then
			local c = NS.db.colorOutRange
			t:SetTextColor(c[1], c[2], c[3])
		else
			t:SetTextColor(1, 1, 1)
		end
		lastRangeColor = colorState
	end
	t:Show()
	UpdateRangeReadoutAnchor()
end

-- =====================================================================
-- Trinket tracker
-- Shows your equipped trinkets (slots 13/14) to the LEFT of the suggestion as
-- icon-framed buttons with a cooldown swipe, plus a brief proc-style glow when one
-- comes off cooldown. On-use-only filtering hides passive trinkets. The cooldown is
-- read secret-safely: the NeverSecret action-slot isActive when the trinket's on-use
-- is on a tracked bar, otherwise the spell's DurationObject for the swipe (with the
-- ready-glow suppressed rather than risking a read of a secret cooldown number).
-- =====================================================================
local function EnsureTrinketFrames()
	if trinketFrames then
		return trinketFrames
	end
	trinketFrames = {}
	local size = (NS.db and NS.db.trinketSize) or 36
	for i = 1, #TRINKET_SLOTS do
		-- Same shared companion-icon builder as the interrupt, so trinkets are skinned
		-- and glow identically; only the equipment slot differs.
		local f = BuildCompanionIcon(frame, size)
		f.slotID = TRINKET_SLOTS[i]
		f.isTrinket = true

		-- Hover tooltip: item name + on-use spell (if any). Captured by closure.
		local slotID = TRINKET_SLOTS[i]
		SetupCompanionTooltip(f,
			function()
				local itemID = GetInventoryItemID and GetInventoryItemID("player", slotID)
				if not itemID then return "Trinket (empty)" end
				local name
				if C_Item and C_Item.GetItemNameByID then
					name = C_Item.GetItemNameByID(itemID)
				elseif GetItemInfo then
					name = GetItemInfo(itemID)
				end
				return name or ("Trinket (item " .. itemID .. ")")
			end,
			function()
				local itemID = GetInventoryItemID and GetInventoryItemID("player", slotID)
				if not itemID then return "" end
				local useSpellID
				if NS.GetItemSpell then
					local _, sid = NS.GetItemSpell(itemID)
					useSpellID = sid
				end
				if not useSpellID then return "Passive" end
				-- Report cooldown readiness if we can
				local slot = ResolveActionSlot(useSpellID)
				if slot and C_ActionBar_GetActionCooldown then
					local info = C_ActionBar_GetActionCooldown(slot)
					if info then
						return info.isActive and "On cooldown" or "Ready"
					end
				end
				return "On-use trinket"
			end
		)

		trinketFrames[i] = f
	end
	return trinketFrames
end

-- Drives the trinket's cooldown swipe and reports readiness: true (ready), false (on
-- cooldown), or nil (can't tell without reading a possibly-secret value -> no glow).
-- Shares RenderCooldownReadiness with the interrupt; the tri-state maps straight onto
-- the trinket's ready-glow transition (nil = skip the glow rather than guess).
local function UpdateTrinketCooldown(f, useSpellID)
	return RenderCooldownReadiness(f.cooldown, useSpellID)
end

local function HideTrinket(f)
	f._wasReady = nil
	if f._glowTimer then
		f._glowTimer:Cancel()
		f._glowTimer = nil
	end
	SetGlowShown(f, false)
	f:Hide()
end

function NS.GetTrinketBlacklist()
	if not NS.TrinketBlacklistCache or not NS.TrinketBlacklistCache._parsed then
		local raw = NS.db and NS.db.trinketBlacklist or ""
		local ids, _ = NS.ParseSpellIDList(raw)
		if not NS.TrinketBlacklistCache then
			NS.TrinketBlacklistCache = {}
		end
		NS.wipe(NS.TrinketBlacklistCache)
		for i = 1, #ids do
			NS.TrinketBlacklistCache[ids[i]] = true
		end
		NS.TrinketBlacklistCache._parsed = true
	end
	return NS.TrinketBlacklistCache
end

local function UpdateTrinketFrame(f)
	local slotID = f.slotID
	local itemID = GetInventoryItemID and GetInventoryItemID("player", slotID)
	if not itemID then
		f._tex = nil
		HideTrinket(f)
		return
	end

	if NS.GetTrinketBlacklist()[itemID] then
		HideTrinket(f)
		return
	end

	-- On-use detection: GetItemSpell returns (name, spellID) for items with a usable
	-- spell. nil spellID => passive trinket.
	local useSpellID
	if GetItemSpell then
		local _, sid = GetItemSpell(itemID)
		useSpellID = sid
	end

	if NS.db.trinketOnUseOnly and not useSpellID then
		HideTrinket(f)
		return
	end

	if NS.db.trinketCombatOnly and not NS.UnitAffectingCombat("player") then
		HideTrinket(f)
		return
	end

	local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", slotID)
	if not tex then
		f._tex = nil
		HideTrinket(f)
		return
	end
	-- Only re-set the texture when the equipped trinket actually changes.
	if f._tex ~= tex then
		f.icon:SetTexture(tex)
		f._tex = tex
	end

	local isReady = UpdateTrinketCooldown(f, useSpellID)
	f._useSpellID = useSpellID
	if isReady == nil then
		-- Readiness unknown (secret cooldown): don't track a transition.
		f._wasReady = nil
	else
		-- Pulse the ready glow on the on-cooldown -> ready transition (auto-clears).
		if f._wasReady == false and isReady == true then
			SetGlowShown(f, true)
			if f._glowTimer then
				f._glowTimer:Cancel()
			end
			f._glowTimer = NS.C_Timer_After(3, function()
				SetGlowShown(f, false)
				f._glowTimer = nil
			end)
		end
		f._wasReady = isReady
	end

	f:Show()
end

-- Shared companion group stacker (trinkets, defensives).
-- Positions a list of companion frames as a centered stack on any side of the main
-- button. Multiple groups on the same side are chained outward via AllocateSide
-- (interrupt → trinkets/defensives → queue) so nothing overlaps.
--
-- Vertical stack (left / right) — centered on the button's Y midpoint.
-- Horizontal row (above / below) — centered on the button's X midpoint.
sideUsed = { left = 0, right = 0, above = 0, below = 0 }

local function ResetSideLayout()
	sideUsed.left = 0
	sideUsed.right = 0
	sideUsed.above = 0
	sideUsed.below = 0
end

local function CompanionBaseGap()
	local size = (NS.db and NS.db.buttonSize) or 40
	local spacing = NS.db and NS.db.interruptSpacing
	if spacing == nil then
		spacing = math.max(2, size * 0.1)
	end
	return spacing
end

-- Returns the near-edge offset (px from the button) for a group occupying `extent`
-- on that axis, and advances the side counter so the next group chains outward.
local function AllocateSide(side, extent)
	local gap = CompanionBaseGap()
	local used = sideUsed[side] or 0
	local start = used == 0 and gap or (used + gap)
	sideUsed[side] = start + extent
	return start
end

local function AnchorInterruptFrame()
	if not interruptFrame or not NS.db or not NS.db.interruptEnabled or not frame then
		return
	end
	local size = NS.db.buttonSize or 40
	local iPos = NS.db.interruptPosition or "right"
	interruptFrame:ClearAllPoints()
	if iPos == "left" or iPos == "right" then
		local off = AllocateSide(iPos, size)
		if iPos == "left" then
			interruptFrame:SetPoint("RIGHT", frame, "LEFT", -off, 0)
		else
			interruptFrame:SetPoint("LEFT", frame, "RIGHT", off, 0)
		end
	elseif iPos == "above" then
		local off = AllocateSide("above", size)
		interruptFrame:SetPoint("BOTTOM", frame, "TOP", 0, off)
	else
		local off = AllocateSide("below", size)
		interruptFrame:SetPoint("TOP", frame, "BOTTOM", 0, -off)
	end
end

local function PositionCompanionGroup(items, position)
	if #items == 0 then return end
	local btnSize = (NS.db and NS.db.buttonSize) or 40

	if position == "left" or position == "right" then
		local totalH = 0
		local colW = 0
		for i = 1, #items do
			totalH = totalH + items[i].size
			if i > 1 then totalH = totalH + items[i].gap end
			if items[i].size > colW then colW = items[i].size end
		end
		local off = AllocateSide(position, colW)
		local y = totalH / 2 - btnSize / 2
		for i = 1, #items do
			items[i].f:ClearAllPoints()
			if position == "left" then
				items[i].f:SetPoint("TOPRIGHT", frame, "TOPLEFT", -off, y)
			else
				items[i].f:SetPoint("TOPLEFT", frame, "TOPRIGHT", off, y)
			end
			local nextGap = (i < #items) and items[i + 1].gap or 0
			y = y - items[i].size - nextGap
		end

	else
		local totalW = 0
		local rowH = 0
		for i = 1, #items do
			totalW = totalW + items[i].size
			if i > 1 then totalW = totalW + items[i].gap end
			if items[i].size > rowH then rowH = items[i].size end
		end
		local off = AllocateSide(position, rowH)
		local x = (btnSize - totalW) / 2
		for i = 1, #items do
			items[i].f:ClearAllPoints()
			if position == "above" then
				items[i].f:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", x, off)
			else
				items[i].f:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", x, -off)
			end
			local nextGap = (i < #items) and items[i + 1].gap or 0
			x = x + items[i].size + nextGap
		end
	end
end

-- Positions trinket and defensive companion frames.
-- When both groups share the same position they are merged into one combined stack
-- (trinkets first, then defensives) — this is the default left-side behaviour.
-- When they differ each group is positioned independently on its own side.
local function ReanchorLeftStack()
	if not frame then return end

	local trinketPos  = (NS.db and NS.db.trinketPosition)   or "above"
	local defPos      = (NS.db and NS.db.defensivePosition) or "left"
	local trinketSize = (NS.db and NS.db.trinketSize)       or 36
	local trinketGap  = (NS.db and NS.db.trinketSpacing)    or 6
	local defSize     = (NS.db and NS.db.defensiveSize)     or 32
	local defGap      = (NS.db and NS.db.defensiveSpacing)  or 4

	local trinketItems = {}
	if trinketFrames and NS.db and NS.db.trinketEnabled then
		for i = 1, #trinketFrames do
			if trinketFrames[i]:IsShown() then
				trinketItems[#trinketItems + 1] = { f = trinketFrames[i], size = trinketSize, gap = trinketGap }
			end
		end
	end

	local defItems = {}
	if defensiveFrames and NS.db and NS.db.defensivesEnabled then
		for i = 1, #defensiveFrames do
			if defensiveFrames[i]:IsShown() then
				defItems[#defItems + 1] = { f = defensiveFrames[i], size = defSize, gap = defGap }
			end
		end
	end

	if trinketPos == defPos then
		-- Same side: merge into one combined stack (trinkets then defensives).
		local combined = {}
		for _, item in ipairs(trinketItems) do combined[#combined + 1] = item end
		for _, item in ipairs(defItems)     do combined[#combined + 1] = item end
		if #combined > 0 then
			PositionCompanionGroup(combined, trinketPos)
		end
	else
		if #trinketItems > 0 then
			PositionCompanionGroup(trinketItems, trinketPos)
		end
		if #defItems > 0 then
			PositionCompanionGroup(defItems, defPos)
		end
	end
end

-- Legacy name used by trinket layout paths.
local function ReanchorTrinkets()
	NS.RelayoutCompanionAnchorsIfNeeded()
end

function NS.InvalidateCompanionLayout()
	lastCompanionLayoutSig = nil
end

local ReanchorQueue

local function ComputeCompanionLayoutSig()
	if not frame or not NS.db then
		return ""
	end
	local qv, tv, dv = 0, 0, 0
	if queueFrames and NS.db.queueEnabled then
		for i = 1, #queueFrames do
			if queueFrames[i]:IsShown() then
				qv = qv + 1
			end
		end
	end
	if trinketFrames and NS.db.trinketEnabled then
		for i = 1, #trinketFrames do
			if trinketFrames[i]:IsShown() then
				tv = tv + 1
			end
		end
	end
	if defensiveFrames and NS.db.defensivesEnabled then
		for i = 1, #defensiveFrames do
			if defensiveFrames[i]:IsShown() then
				dv = dv + 1
			end
		end
	end
	return string_format(
		"%d:%s:%d:%d:%d:%d:%s:%s:%s:%s:%d:%d:%d:%d:%d:%d:%d",
		NS.db.interruptEnabled and 1 or 0,
		NS.db.interruptPosition or "right",
		NS.db.buttonSize or 80,
		tv,
		dv,
		qv,
		NS.db.trinketPosition or "above",
		NS.db.defensivePosition or "left",
		NS.db.queuePosition or "below",
		NS.db.queueLayoutDirection or "horizontal",
		NS.db.queueAlignment or "left",
		NS.db.queueSize or 34,
		NS.db.queueSpacing or 4,
		NS.db.trinketSize or 36,
		NS.db.trinketSpacing or 4,
		NS.db.defensiveSize or 32,
		NS.db.defensiveSpacing or 4
	)
end

function NS.RelayoutCompanionAnchors()
	if not frame then
		return
	end
	ResetSideLayout()
	AnchorInterruptFrame()
	ReanchorLeftStack()
	ReanchorQueue()
	UpdateRangeReadoutAnchor()
end

function NS.RelayoutCompanionAnchorsIfNeeded()
	local sig = ComputeCompanionLayoutSig()
	if sig == lastCompanionLayoutSig then
		return
	end
	lastCompanionLayoutSig = sig
	NS.RelayoutCompanionAnchors()
end

local function ReanchorQueueIfNeeded()
	NS.RelayoutCompanionAnchorsIfNeeded()
end

local function ReanchorLeftStackIfNeeded()
	NS.RelayoutCompanionAnchorsIfNeeded()
end

-- Sizing pass (settings/layout only, not per tick) so the trinket-size slider and
-- border toggle take effect; then reanchor.
function NS.LayoutTrinkets()
	if not trinketFrames then
		return
	end
	local size = NS.db.trinketSize or 36
	for i = 1, #trinketFrames do
		local f = trinketFrames[i]
		f:SetSize(size, size)
		LayoutCompanionCooldown(f, size)
		ApplyGlowStyle(f)
		ApplyCompanionCooldownNumbers(f)
		if NS.db.strata then
			f:SetFrameStrata(NS.db.strata)
		end
	end
	lastCompanionLayoutSig = nil
end

function NS.UpdateTrinkets()
	if not NS.db or not NS.db.trinketEnabled or not NS.frame or not NS.frame:IsVisible() then
		if trinketFrames then
			for i = 1, #trinketFrames do
				HideTrinket(trinketFrames[i])
			end
		end
		return
	end

	local frames = EnsureTrinketFrames()
	for i = 1, #frames do
		UpdateTrinketFrame(frames[i])
	end
end

function NS.UpdateTrinketRegistration()
	local on = NS.db and NS.db.trinketEnabled
	if on then
		-- Equip changes swap which trinkets/icons to show; refresh immediately rather
		-- than waiting for the next tick. The cooldown swipe itself is driven by the
		-- per-tick UpdateNow, so we don't need BAG_UPDATE_COOLDOWN here.
		addonFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	else
		if addonFrame.UnregisterUnitEvent then
			addonFrame:UnregisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
		else
			addonFrame:UnregisterEvent("UNIT_INVENTORY_CHANGED")
		end
	end
	NS.UpdateTrinkets()
end

-- =====================================================================
-- Rotation queue — upcoming Assisted Combat spells from GetRotationSpells
-- (Blizzard AssistedCombatManager rotation list), shown in order below the
-- main suggestion after the current next-cast pick.
-- =====================================================================
local function UpdateQueueIcon(f, spellID)
	if not spellID then
		f.spellID = nil
		f.cooldown:Clear()
		f.cooldown:Hide()
		SetGlowShown(f, false)
		f:Hide()
		return
	end

	local changed = SpellIDChanged(f.spellID, spellID)
	f.spellID = spellID
	if changed and C_Spell_GetSpellTexture then
		f.icon:SetTexture(C_Spell_GetSpellTexture(spellID))
	end

	local readiness = RenderCooldownReadiness(f.cooldown, spellID)
	local onCd = readiness == false
	if NS.db.rangeColoring then
		ApplyActionState(f, spellID)
	else
		f.icon:SetVertexColor(1, 1, 1)
		f.icon:SetDesaturated(false)
	end
	SetGlowShown(f, false)
	-- Dim only when CD is confirmed active; unknown (nil) stays full alpha.
	f:SetAlpha(onCd and 0.65 or 1)
	if NS.db.companionCooldownNumbers then
		ApplyCooldownFontSize(f.cooldown, f:GetWidth() or (NS.db.queueSize or 28), false)
	end
	f:Show()
end

local function EnsureQueueFrames()
	if queueFrames then
		return queueFrames
	end
	queueFrames = {}
	local maxSlots = NS.MAX_QUEUE_SLOTS or 5
	local size = (NS.db and NS.db.queueSize) or 28
	for i = 1, maxSlots do
		local f = BuildCompanionIcon(frame, size)
		f.queueIndex = i
		SetupCompanionTooltip(f,
			function()
				local sid = f.spellID
				return CompanionSpellTooltipTitle(sid, sid and "Rotation spell" or "Rotation queue")
			end,
			function()
				local sid = f.spellID
				if not sid then
					return ""
				end
				local readiness = RenderCooldownReadiness(f.cooldown, sid)
				if readiness == true then
					return "Ready"
				elseif readiness == false then
					return "On cooldown"
				end
				local idx = f.queueIndex or 0
				if idx == 1 then
					return "Next in rotation"
				end
				return "Upcoming in rotation"
			end
		)
		queueFrames[i] = f
	end
	return queueFrames
end

-- Position the rotation queue relative to the main button.
-- `queuePosition` ("below" | "above" | "left" | "right") controls WHICH SIDE.
-- `queueLayoutDirection` ("horizontal" | "vertical") controls HOW icons are arranged
-- within the group — the two settings are independent so you can have a vertical
-- column to the right, a horizontal row above, etc.
function ReanchorQueue()
	if not queueFrames or not frame or not frame.button then
		return
	end
	local size    = NS.db.queueSize     or 28
	local spacing = NS.db.queueSpacing  or 4
	local btnSize = NS.db.buttonSize    or 40
	local pos     = NS.db.queuePosition or "below"
	if pos ~= "below" and pos ~= "above" and pos ~= "right" and pos ~= "left" then
		pos = "below"
	end
	local dir     = NS.db.queueLayoutDirection or "horizontal"
	local align   = NS.db.queueAlignment      or "left"

	local visible = {}
	for i = 1, #queueFrames do
		if queueFrames[i]:IsShown() then
			visible[#visible + 1] = queueFrames[i]
		end
	end
	local count = #visible

	if count > 0 then
		-- Centered offset helpers.
		local totalW = count * size + (count - 1) * spacing
		local centerOffH = (align == "center") and math_floor((btnSize - totalW) / 2 + 0.5) or 0
		local centerOffV = (align == "center") and math_floor((btnSize - size)   / 2 + 0.5) or 0
		local totalH     = count * size + (count - 1) * spacing
		local centerLeftY = totalH / 2 - btnSize / 2

		-- Chain outward on this side once per group (not per icon).
		local queueOff
		if pos == "below" then
			queueOff = AllocateSide("below", dir == "vertical" and totalH or size)
		elseif pos == "above" then
			queueOff = AllocateSide("above", dir == "vertical" and totalH or size)
		elseif pos == "right" then
			queueOff = AllocateSide("right", dir == "vertical" and size or totalW)
		elseif pos == "left" then
			queueOff = AllocateSide("left", dir == "vertical" and size or totalW)
		end
		if not queueOff then
			return
		end

		for i = 1, count do
			local f = visible[i]
			f:ClearAllPoints()

			if pos == "below" then
				if dir == "vertical" then
					f:SetPoint("TOPLEFT", frame.button, "BOTTOMLEFT", centerOffV, -queueOff - (i - 1) * (size + spacing))
				else
					f:SetPoint("TOPLEFT", frame.button, "BOTTOMLEFT", centerOffH + (i - 1) * (size + spacing), -queueOff)
				end

			elseif pos == "above" then
				if dir == "vertical" then
					f:SetPoint("BOTTOMLEFT", frame.button, "TOPLEFT", centerOffV, queueOff + (i - 1) * (size + spacing))
				else
					f:SetPoint("BOTTOMLEFT", frame.button, "TOPLEFT", centerOffH + (i - 1) * (size + spacing), queueOff)
				end

			elseif pos == "right" then
				if dir == "vertical" then
					local y = centerLeftY - (i - 1) * (size + spacing)
					f:SetPoint("TOPLEFT", frame, "TOPRIGHT", queueOff, y)
				else
					local centerY = -(btnSize / 2 - size / 2)
					f:SetPoint("TOPLEFT", frame, "TOPRIGHT", queueOff + (i - 1) * (size + spacing), centerY)
				end

			elseif pos == "left" then
				if dir == "vertical" then
					local y = centerLeftY - (i - 1) * (size + spacing)
					f:SetPoint("TOPRIGHT", frame, "TOPLEFT", -queueOff, y)
				else
					local centerY = -(btnSize / 2 - size / 2)
					local x = -queueOff - size - (i - 1) * (size + spacing)
					f:SetPoint("TOPLEFT", frame, "TOPLEFT", x, centerY)
				end
			end
		end
	end
end

function NS.LayoutQueue()
	if not queueFrames then
		return
	end
	local size = NS.db.queueSize or 28
	for i = 1, #queueFrames do
		local f = queueFrames[i]
		f:SetSize(size, size)
		LayoutCompanionCooldown(f, size)
		ApplyGlowStyle(f)
		ApplyCompanionCooldownNumbers(f)
		if NS.db.strata then
			f:SetFrameStrata(NS.db.strata)
		end
	end
	lastCompanionLayoutSig = nil
end

function NS.UpdateQueue(primarySpellID)
	if not NS.db or not NS.db.queueEnabled or not frame or not frame:IsVisible() then
		if queueFrames then
			for i = 1, #queueFrames do
				queueFrames[i]:Hide()
			end
		end
		return
	end
	if NS.db.queueCombatOnly and not NS.UnitAffectingCombat("player") then
		if queueFrames then
			for i = 1, #queueFrames do
				queueFrames[i]:Hide()
			end
		end
		return
	end

	local maxCount = NS.db.queueCount or 3
	if maxCount < 1 then
		maxCount = 1
	end
	local maxSlots = NS.MAX_QUEUE_SLOTS or 5
	if maxCount > maxSlots then
		maxCount = maxSlots
	end

	local spells = NS.CollectRotationQueue and NS.CollectRotationQueue(maxCount, primarySpellID)
	local frames = EnsureQueueFrames()
	for i = 1, #frames do
		local sid = spells and spells[i]
		if sid then
			UpdateQueueIcon(frames[i], sid)
		else
			frames[i]:Hide()
		end
	end
end

-- =====================================================================
-- Personal defensives — per-spec spell list (Advanced) with optional health
-- threshold; glow when ready, usable, and the health gate passes.
-- =====================================================================
local function UpdateDefensiveIcon(f, spellID)
	if not spellID then
		f.spellID = nil
		f.cooldown:Clear()
		f.cooldown:Hide()
		SetGlowShown(f, false)
		f:Hide()
		return
	end

	local changed = SpellIDChanged(f.spellID, spellID)
	f.spellID = spellID
	if changed and C_Spell_GetSpellTexture then
		f.icon:SetTexture(C_Spell_GetSpellTexture(spellID))
	end

	local readiness = RenderCooldownReadiness(f.cooldown, spellID)
	local onCd = readiness == false
	if NS.db.rangeColoring then
		ApplyActionState(f, spellID)
	else
		f.icon:SetVertexColor(1, 1, 1)
		f.icon:SetDesaturated(false)
	end

	local wantGlow = NS.db.defensiveGlow
		and readiness == true
		and NS.ShouldSuggestDefensive
		and NS.ShouldSuggestDefensive(spellID)
	SetGlowShown(f, wantGlow)
	f:SetAlpha(onCd and DEFENSIVE_DIM or 1)
	f:Show()
end

local function EnsureDefensiveFrames()
	if defensiveFrames then
		return defensiveFrames
	end
	defensiveFrames = {}
	local maxSlots = NS.MAX_DEFENSIVE_SLOTS or 4
	local size = (NS.db and NS.db.defensiveSize) or 32
	for i = 1, maxSlots do
		local f = BuildCompanionIcon(frame, size)
		f.isDefensive = true

		-- Hover tooltip: spell name + cooldown readiness.
		SetupCompanionTooltip(f,
			function()
				return CompanionSpellTooltipTitle(f.spellID, "Defensive")
			end,
			function()
				local sid = f.spellID
				if not sid then return "" end
				local slot = ResolveActionSlot(sid)
				if slot and C_ActionBar_GetActionCooldown then
					local info = C_ActionBar_GetActionCooldown(slot)
					if info then
						return info.isActive and "On cooldown" or "Ready"
					end
				end
				return "Defensive cooldown"
			end
		)

		defensiveFrames[i] = f
	end
	return defensiveFrames
end

function NS.LayoutDefensives()
	if not defensiveFrames then
		return
	end
	local size = NS.db.defensiveSize or 32
	for i = 1, #defensiveFrames do
		local f = defensiveFrames[i]
		f:SetSize(size, size)
		LayoutCompanionCooldown(f, size)
		ApplyGlowStyle(f)
		ApplyCompanionCooldownNumbers(f)
		if NS.db.strata then
			f:SetFrameStrata(NS.db.strata)
		end
	end
	lastCompanionLayoutSig = nil
end

function NS.UpdateDefensives()
	if not NS.db or not NS.db.defensivesEnabled or not frame or not frame:IsVisible() then
		if defensiveFrames then
			for i = 1, #defensiveFrames do
				defensiveFrames[i]:Hide()
			end
		end
		return
	end
	if NS.db.defensiveCombatOnly and not NS.UnitAffectingCombat("player") then
		if defensiveFrames then
			for i = 1, #defensiveFrames do
				defensiveFrames[i]:Hide()
			end
		end
		return
	end

	local list = NS.GetSpecDefensiveList and NS.GetSpecDefensiveList()
	if not list or #list == 0 then
		if defensiveFrames then
			for i = 1, #defensiveFrames do
				defensiveFrames[i]:Hide()
			end
		end
		return
	end

	local frames = EnsureDefensiveFrames()
	local maxSlots = NS.MAX_DEFENSIVE_SLOTS or 4
	local maxShow = #list
	if maxShow > maxSlots then
		maxShow = maxSlots
	end
	if maxShow > #frames then
		maxShow = #frames
	end

	for i = 1, #frames do
		if i <= maxShow then
			UpdateDefensiveIcon(frames[i], list[i])
		else
			frames[i]:Hide()
		end
	end
end

function NS.UpdateDefensiveRegistration()
	-- Register UNIT_HEALTH for the player when a health threshold is configured so
	-- the defensive glow reacts immediately when health drops (rather than waiting
	-- for the next 8Hz tick). Unregister it when threshold is 0 (always-glow) since
	-- health changes don't affect the glow decision and the event fires constantly.
	local cfg = NS.GetSpecConfig and NS.GetSpecConfig()
	local threshold = cfg and cfg.defensiveHealthThreshold or 0
	if NS.db and NS.db.defensivesEnabled and threshold > 0 then
		addonFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
	else
		if addonFrame.UnregisterUnitEvent then
			addonFrame:UnregisterUnitEvent("UNIT_HEALTH", "player")
		else
			addonFrame:UnregisterEvent("UNIT_HEALTH")
		end
	end
	NS.UpdateDefensives()
end

-- Sizes/positions the companion widgets. Called from UpdateLayout via NS late-bind,
-- so it can live here (after EnsureInterruptFrame) without forward-declaration churn.
function NS.LayoutCompanions()
	local size = NS.db.buttonSize or 80

	if NS.db.interruptEnabled then
		local f = EnsureInterruptFrame()
		f:SetSize(size, size)
		LayoutCompanionCooldown(f, size)
		ApplyGlowStyle(f)
		ApplyCompanionCooldownNumbers(f)
		if NS.db.strata then
			f:SetFrameStrata(NS.db.strata)
		end
	elseif interruptFrame then
		interruptFrame:Hide()
	end

	-- Create the counter/range readout up front when their feature is on (mirroring
	-- the interrupt/trinket handling above) so they're sized correctly from first
	-- show instead of appearing at the default font size and snapping on the next
	-- layout pass.
	if NS.db.nameplateCounterEnabled then
		EnsureCounter()
	end
	if counterText then
		local fontPath, _, fontFlags = counterText:GetFont()
		counterText:SetFont(fontPath, math.max(10, size * 0.45), fontFlags)
	end

	if NS.db.rangeReadoutEnabled then
		EnsureRangeReadout()
	end
	if rangeReadout then
		local fontPath, _, fontFlags = rangeReadout:GetFont()
		rangeReadout:SetFont(fontPath, math.max(9, size * 0.34), fontFlags)
		-- Give the range text a stable centered box so a changing band ("5-8"/"85-100"/
		-- "100+ yd") doesn't look like the readout is resizing or sliding around.
		rangeReadout:SetWidth(math.max(size * 2.4, 92))
	end

	if NS.db.trinketEnabled then
		EnsureTrinketFrames()
		NS.LayoutTrinkets()
	elseif trinketFrames then
		for i = 1, #trinketFrames do
			trinketFrames[i]:Hide()
		end
	end

	if NS.db.queueEnabled then
		EnsureQueueFrames()
		NS.LayoutQueue()
	elseif queueFrames then
		for i = 1, #queueFrames do
			queueFrames[i]:Hide()
		end
	end

	if NS.db.defensivesEnabled then
		EnsureDefensiveFrames()
		NS.LayoutDefensives()
	elseif defensiveFrames then
		for i = 1, #defensiveFrames do
			defensiveFrames[i]:Hide()
		end
	end

	NS.RelayoutCompanionAnchors()
end

-- Polling rate for the current combat state: the fast rate in combat, a slower
-- rate out of combat to cut idle CPU. Floored at 0.05s.
local function DesiredTickRate()
	local rate = NS.db.updateRate or 0.12
	if not NS.UnitAffectingCombat("player") then
		local ooc = NS.db.updateRateOOC or 0.25
		if ooc > rate then
			rate = ooc
		end
	end
	if rate < 0.05 then
		rate = 0.05
	end
	return rate
end

-- Starts/refreshes the ticker, restarting it only when the desired rate changed
-- (e.g. on entering/leaving combat) so we don't churn timers needlessly.
local function StopTicker()
	if NS.ticker then
		NS.ticker:Cancel()
		NS.ticker = nil
		NS.tickerRate = nil
	end
end

local function StartTicker()
	local rate = DesiredTickRate()
	if NS.ticker then
		if NS.tickerRate == rate then
			return
		end
		NS.ticker:Cancel()
		NS.ticker = nil
	end

	NS.tickerRate = rate
	NS.ticker = NS.C_Timer_NewTicker(rate, NS.UpdateNow)
end

-- True while mounted, or in a druid travel/flight form (treated as mounted travel
-- for the hide-when-mounted option). All inputs are the player's own state.
local function IsEffectivelyMounted()
	if IsMounted and IsMounted() then
		return true
	end
	if GetShapeshiftFormID then
		local form = GetShapeshiftFormID()
		if form and TRAVEL_FORM_IDS[form] then
			return true
		end
	end
	return false
end

function NS.UpdateVisibility()
	local f = NS.frame
	if not f then
		return
	end

	local function HideFrame()
		f:Hide()
		StopTicker()
		if NS.UpdateCooldownEventRegistration then
			NS.UpdateCooldownEventRegistration()
		end
	end

	if not NS.db.enabled then
		HideFrame()
		return
	end

	local inCombat = NS.UnitAffectingCombat("player")
	local inVehicle = NS.UnitInVehicle("player")

	-- Ignore visibility conditions when unlocked so the user can see and place the button.
	if NS.db.locked then
		-- Hide in Vehicle check
		if inVehicle and NS.db.hideInVehicle then
			HideFrame()
			return
		end

		-- Hide while mounted (druid Travel/Flight Form counts as mounted travel).
		if NS.db.hideWhenMounted and IsEffectivelyMounted() then
			HideFrame()
			return
		end

		-- showWhen visibility condition.
		local showWhen = NS.db.showWhen or "Always"
		if showWhen == "InCombat" then
			if not inCombat then
				HideFrame()
				return
			end
		elseif showWhen == "HasTarget" then
			if not UnitExists("target") then
				HideFrame()
				return
			end
		elseif showWhen == "TargetInCombat" then
			if not (UnitExists("target") and NS.UnitAffectingCombat("target")) then
				HideFrame()
				return
			end
		end
	end

	-- Apply Alpha (force 1.0 when unlocked so it's clearly visible)
	local targetAlpha = 1.0
	if NS.db.locked then
		targetAlpha = inCombat and NS.db.alphaCombat or NS.db.alphaOOC
	end
	f:SetAlpha(targetAlpha)

	-- If we passed checks, show it (UpdateNow will determine if there's a spell to create/show sub-elements)
	f:Show()

	-- Check for availability to start/stop ticker
	if not NS.db.locked or NS.IsAssistedCombatAvailable() then
		StartTicker()
	else
		StopTicker()
	end
	if NS.UpdateCooldownEventRegistration then
		NS.UpdateCooldownEventRegistration()
	end
end

-- Maps the tullaRange-style state string to the configurable color in the DB.
local STATE_COLOR_KEY = {
	normal = "colorNormal",
	oor = "colorOOR",
	oom = "colorOOM",
	unusable = "colorUnusable",
}

-- Mana is excluded from pooling: "wait until X% mana before casting" is the wrong
-- mental model for healers/casters, whereas builder/spender pools (energy, focus,
-- rage, runic power, fury, maelstrom, ...) are exactly what pooling is about.
local POOL_EXCLUDED_POWER = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

-- Returns the numeric power type a spell pools on (its main spendable resource),
-- or false when it spends nothing poolable. Memoized per spell ID; the cache is
-- wiped alongside the other spell caches on bar/spec/form changes.
local function GetPooledPowerType(spellID)
	if issecretvalue and issecretvalue(spellID) then
		return false
	end

	local cached = NS.PoolPowerCache[spellID]
	if cached ~= nil then
		return cached
	end

	local result = false
	if C_Spell_GetSpellPowerCost then
		local costs = C_Spell_GetSpellPowerCost(spellID)
		if type(costs) == "table" then
			for i = 1, #costs do
				local entry = costs[i]
				local ptype = entry and entry.type
				local cost = entry and entry.cost
				-- Midnight: power cost fields can be secret in combat — never compare.
				if ptype and not (issecretvalue and issecretvalue(ptype))
					and ptype >= 0 and ptype ~= POOL_EXCLUDED_POWER
					and cost and not (issecretvalue and issecretvalue(cost)) and cost > 0 then
					result = ptype
					break
				end
			end
		end
	end

	NS.PoolPowerCache[spellID] = result
	return result
end

-- True when the suggested spell spends a poolable resource and the player is below
-- the configured pooling threshold (i.e. "bank a little more before spending").
local function ShouldShowPoolingTint(spellID)
	if issecretvalue and issecretvalue(spellID) then
		return false
	end
	local ptype = GetPooledPowerType(spellID)
	if not ptype then
		return false
	end
	local max = UnitPowerMax("player", ptype)
	local cur = UnitPower("player", ptype)
	-- Midnight: UnitPower/UnitPowerMax can be secret numbers in combat. Doing any
	-- arithmetic or comparison on a secret taints us, so detect-and-skip up front
	-- (treat as "no info" → no pooling tint) rather than branching on the value.
	if issecretvalue and (issecretvalue(cur) or issecretvalue(max)) then
		return false
	end
	if not max or max <= 0 then
		return false
	end
	local pct = (cur / max) * 100
	return pct < (NS.db.resourcePoolThreshold or 40)
end

-- Colors the suggestion icon/keybind by range & usability (tullaRange behavior).
ApplyActionState = function(b, spellID)
	-- Coloring disabled: still honor pooling tint if it's on, otherwise reset.
	if not NS.db.rangeColoring then
		if NS.db.resourcePooling and ShouldShowPoolingTint(spellID) then
			local pool = NS.db.colorPool
			b.icon:SetVertexColor(pool[1], pool[2], pool[3])
		else
			b.icon:SetVertexColor(1, 1, 1)
		end
		b.icon:SetDesaturated(false)
		if b.hotkey then
			b.hotkey:SetVertexColor(1, 1, 1)
		end
		return
	end

	-- Check range against the current target (matching the range readout). With no
	-- target IsSpellInRange returns nil ("no info"), so this is a no-op out of combat
	-- / untargeted and only tints red/desaturates when the target is genuinely OOR.
	local state, _, _, outOfRange = NS.GetActionState(spellID, "target")

	-- Pooling tint takes precedence over the plain "castable" color: when the spell
	-- is otherwise ready but you're below the pooling threshold, say "wait".
	if state == "normal" and NS.db.resourcePooling and ShouldShowPoolingTint(spellID) then
		local pool = NS.db.colorPool
		b.icon:SetVertexColor(pool[1], pool[2], pool[3])
		b.icon:SetDesaturated(false)
		if b.hotkey then
			b.hotkey:SetVertexColor(1, 1, 1)
		end
		return
	end

	local color = NS.db[STATE_COLOR_KEY[state] or "colorNormal"]
	if color then
		b.icon:SetVertexColor(color[1], color[2], color[3])
	end
	-- Desaturate for out-of-range / out-of-power, matching tullaRange defaults.
	b.icon:SetDesaturated(state == "oor" or state == "oom")

	if b.hotkey then
		if outOfRange then
			local oor = NS.db.colorOOR
			b.hotkey:SetVertexColor(oor[1], oor[2], oor[3])
		else
			b.hotkey:SetVertexColor(1, 1, 1)
		end
	end
end

local function UpdateButton(b, spellID)
	if not spellID then
		b.spellID = nil
		b.icon:SetTexture(nil)
		b.hotkey:SetText("")
		b.cooldown:Clear()
		b.cooldown:Hide()
		SetGlowShown(b, false)
		b:Hide()
		return
	end

	if spellID == "placeholder" then
		-- Unlocked placement aid only: drag the frame without a live assisted-combat pick.
		b.spellID = "placeholder"
		b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		b.hotkey:SetText("Drag")
		b.hotkey:Show()
		b.cooldown:Clear()
		b.cooldown:Hide()
		SetGlowShown(b, false)
		b:Show()
		return
	end

	-- Hot path: only re-fetch the icon texture when the suggestion actually changes.
	-- Keybind text stays out of this guard but is memoized, so it's cheap per tick.
	local spellChanged = SpellIDChanged(b.spellID, spellID)
	b.spellID = spellID

	if spellChanged then
		if NS.C_Spell_GetSpellTexture then
			b.icon:SetTexture(NS.C_Spell_GetSpellTexture(spellID))
		else
			b.icon:SetTexture(nil)
		end
	end

	if NS.db.showKeybind then
		-- Refetch when the spell changes or cache was cleared (e.g. showKeybind toggled off).
		if spellChanged or b._hotkeyText == nil then
			b._hotkeyText = NS.GetKeyBindForSpellID(spellID) or ""
		end
		local text = b._hotkeyText or ""
		b.hotkey:SetText(text)
		b.hotkey:SetShown(text ~= "")
	else
		b._hotkeyText = nil
		b.hotkey:SetText("")
		b.hotkey:Hide()
	end

	UpdateCooldownForSpell(b, spellID)
	ApplyActionState(b, spellID)

	-- Only glow a clearly-visible button: suppress it once the frame is faded (e.g.
	-- the out-of-combat alpha), matching how Blizzard hides proc art on dimmed bars
	-- so a near-transparent button doesn't flash a full-strength shimmer.
	local visibleEnough = (NS.frame:GetAlpha() or 1) > 0.5
	if NS.db.glowEnabled and visibleEnough then
		SetGlowShown(b, IsSpellGlowing(spellID))
	else
		SetGlowShown(b, false)
	end

	b:Show()
end

-- Lightweight cooldown-only refresh (SPELL_UPDATE_COOLDOWN / ACTIONBAR_UPDATE_COOLDOWN).
-- Skips spell collection, layout, range readout, and glow logic — only updates swipes.
function NS.UpdateCooldownsOnly()
	local f = NS.frame
	if not f or not f:IsVisible() then
		return
	end
	local b = f.button
	if b and b.spellID then
		local sid = b.spellID
		if issecretvalue and issecretvalue(sid) then
			UpdateCooldownForSpell(b, sid)
		elseif sid ~= "placeholder" then
			UpdateCooldownForSpell(b, sid)
		end
	end
	if NS.db.queueEnabled and queueFrames then
		for i = 1, #queueFrames do
			local qf = queueFrames[i]
			if qf:IsShown() and qf.spellID then
				local readiness = RenderCooldownReadiness(qf.cooldown, qf.spellID)
				qf:SetAlpha(readiness == false and 0.65 or 1)
			end
		end
	end
	if NS.db.interruptEnabled and interruptFrame and interruptFrame:IsShown() then
		NS.UpdateInterrupt()
	end
	if NS.db.trinketEnabled and trinketFrames then
		for i = 1, #trinketFrames do
			local tf = trinketFrames[i]
			if tf:IsShown() and tf._useSpellID then
				UpdateTrinketCooldown(tf, tf._useSpellID)
			end
		end
	end
	if NS.db.defensivesEnabled and defensiveFrames then
		for i = 1, #defensiveFrames do
			local df = defensiveFrames[i]
			if df:IsShown() and df.spellID then
				UpdateDefensiveIcon(df, df.spellID)
			end
		end
	end
end

function NS.NeedsCooldownEvents()
	if not NS.db or not NS.db.enabled then
		return false
	end
	return true
end

function NS.UpdateCooldownEventRegistration()
	local on = NS.NeedsCooldownEvents()
	if on then
		addonFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
		addonFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
	else
		addonFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
		addonFrame:UnregisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
	end
end

local cooldownRefreshPending = false
local function ScheduleCooldownRefresh()
	if cooldownRefreshPending then
		return
	end
	cooldownRefreshPending = true
	NS.C_Timer_After(0, function()
		cooldownRefreshPending = false
		NS.UpdateCooldownsOnly()
	end)
end

function NS.UpdateNow()
	-- If the frame is hidden (e.g. by UpdateVisibility due to OOC/Vehicle/Disabled),
	-- we don't need to process anything.
	local f = NS.frame
	if not f or not f:IsVisible() then
		return
	end

	local spellID = NS.CollectNextSpell()
	-- Unlocked + no suggestion: show placeholder so the user can position the frame.
	if not spellID and not NS.db.locked then
		spellID = "placeholder"
	end
	UpdateButton(f.button, spellID)

	if NS.db.queueEnabled then
		NS.UpdateQueue(spellID)
	end

	if NS.db.interruptEnabled then
		NS.UpdateInterrupt()
	end
	if NS.db.trinketEnabled then
		NS.UpdateTrinkets()
	end
	if NS.db.defensivesEnabled then
		NS.UpdateDefensives()
	end
	NS.RelayoutCompanionAnchorsIfNeeded()

	if NS.db.nameplateCounterEnabled then
		NS.UpdateNameplateCounter()
	end
	if NS.db.rangeReadoutEnabled then
		NS.UpdateRangeReadout()
	end
end

local function OnAssistedCombatUpdate()
	if NS.UpdateNow then
		pendingUpdate = true
		updateDriver:Show()
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
-- Events  (MODULE: Events — Modules/Events.lua)
-- ---------------------------------------------------------------------
addonFrame:RegisterEvent("ADDON_LOADED")

-- Binding / bar / spec / form changes => rebuild the (memoized) keybind cache.
-- UPDATE_STEALTH is required because stealth & druid prowl remap which action bar
-- the keybind comes from, and that mapping is otherwise only re-evaluated lazily.
addonFrame:RegisterEvent("UPDATE_BINDINGS")
addonFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
addonFrame:RegisterEvent("SPELLS_CHANGED")
addonFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
addonFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
addonFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
addonFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
addonFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
addonFrame:RegisterEvent("UPDATE_STEALTH")
addonFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
addonFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
addonFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
-- PLAYER_SPECIALIZATION_CHANGED is a unit event; only the player's matters.
addonFrame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")

-- Visibility drivers. Vehicle events are unit events, so filter to the player to
-- avoid waking up for every party/raid member's vehicle transitions.
addonFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
addonFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
addonFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
addonFrame:RegisterEvent("PLAYER_STARTED_MOVING")
addonFrame:RegisterEvent("PLAYER_STOPPED_MOVING")
addonFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
addonFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
-- showWhen (HasTarget / TargetInCombat) + hideWhenMounted drivers. A hidden frame
-- can't re-show itself from the ticker, so these must re-run UpdateVisibility.
addonFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
addonFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
addonFrame:RegisterUnitEvent("UNIT_FLAGS", "target")

-- Proc/activation glow tracking, so we can mirror it on the suggestion button.
addonFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
addonFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

-- The assisted-combat action spell firing means the recommended spell almost
-- certainly just advanced; refresh immediately for a snappier suggestion instead of
-- waiting for the next tick. This is the synchronous ASSISTED_COMBAT_ACTION_SPELL_CAST
-- event (12.0+); pcall-guarded so registering it is a no-op on clients without it.
NS.pcall(addonFrame.RegisterEvent, addonFrame, "ASSISTED_COMBAT_ACTION_SPELL_CAST")

local allTimer
local function DelayedUpdateKeybindings()
	if allTimer then
		allTimer:Cancel()
	end
	allTimer = NS.C_Timer_After(0.2, function()
		NS.ReadKeybindings()
		-- Spec/talent/spellbook may have changed the active interrupt; re-detect.
		if NS.db and NS.db.interruptEnabled and NS.DetectInterruptSpell then
			NS.DetectInterruptSpell()
		end
		-- Spec changes can alter the per-spec defensive threshold, which controls
		-- whether UNIT_HEALTH is registered. Re-evaluate on every spec/keybind rebuild.
		if NS.UpdateDefensiveRegistration then
			NS.UpdateDefensiveRegistration()
		end
		NS.UpdateNow()
		allTimer = nil
	end)
end

local function OnAddonLoaded(name)
	if name ~= ADDON_NAME or NS.loaded then
		return
	end
	NS.loaded = true
	-- One-shot: no longer needed once our SavedVariables are initialized.
	addonFrame:UnregisterEvent("ADDON_LOADED")

	BetterButtonAssistantDB = BetterButtonAssistantDB or {}
	NS.db = BetterButtonAssistantDB

	-- Migrate the legacy onlyInCombat checkbox into the richer showWhen dropdown
	-- (only for existing saves that predate showWhen). Runs before defaults fill in.
	-- onlyInCombat is no longer a default, so drop the stale key once migrated.
	if NS.db.onlyInCombat ~= nil then
		if NS.db.showWhen == nil and NS.db.onlyInCombat == true then
			NS.db.showWhen = "InCombat"
		end
		NS.db.onlyInCombat = nil
	end

	NS.MigrateDatabase(NS.db)

	NS.CopyDefaults(NS.db, NS.defaults)

	NS.RegisterSettings() -- Initialize Modern Settings Panel

	RegisterAssistedCombatEvents() -- Hook into Blizzard's internal events

	-- Restore saved frame position if available (or use LibEditMode if loaded).
	local LEM = LibStub and LibStub("LibEditMode", true)
	if LEM then
		local function onPositionChanged(frameObj, layoutName, point, x, y)
			if not NS.db.layouts then
				NS.db.layouts = {}
			end
			if not NS.db.layouts[layoutName] then
				NS.db.layouts[layoutName] = {}
			end
			NS.db.layouts[layoutName].point = point
			NS.db.layouts[layoutName].x = x
			NS.db.layouts[layoutName].y = y
		end

		local defaultPosition = {
			point = NS.db.framePoint or "CENTER",
			x = NS.db.frameX or 0,
			y = NS.db.frameY or -120,
		}

		LEM:RegisterCallback("layout", function(layoutName)
			if not NS.db.layouts then
				NS.db.layouts = {}
			end
			if not NS.db.layouts[layoutName] then
				NS.db.layouts[layoutName] = {
					point = NS.db.framePoint or "CENTER",
					x = NS.db.frameX or 0,
					y = NS.db.frameY or -120,
				}
			end
			frame:ClearAllPoints()
			frame:SetPoint(
				NS.db.layouts[layoutName].point or "CENTER",
				NS.UIParent,
				NS.db.layouts[layoutName].point or "CENTER",
				NS.db.layouts[layoutName].x or 0,
				NS.db.layouts[layoutName].y or -120
			)
		end)

		LEM:AddFrame(frame, onPositionChanged, defaultPosition)
	else
		if NS.db.framePoint then
			frame:ClearAllPoints()
			frame:SetPoint(NS.db.framePoint, NS.UIParent, NS.db.frameRelPoint, NS.db.frameX, NS.db.frameY)
		end
	end

	NS.UpdateLayout()
	NS.UpdateVisibility() -- Call UpdateVisibility after layout

	-- Companion features: register their (conditional) events and lay them out.
	NS.UpdateInterruptRegistration()
	NS.UpdateNameplateRegistration()
	NS.UpdateTrinketRegistration()
	NS.UpdateDefensiveRegistration()

	if NS.UpdateCooldownEventRegistration then
		NS.UpdateCooldownEventRegistration()
	end

	DelayedUpdateKeybindings() -- Ensure hotkeys are scanned after bars are ready
end

-- Marks/unmarks a spell (and its current display/override variant) as glowing.
-- Shared by the SHOW/HIDE handlers so the variant-tracking logic lives in one place.
local function MarkSpellGlow(spellID, on)
	if not spellID then
		return
	end
	local v = on or nil
	NS.GlowingSpells[spellID] = v
	if issecretvalue and issecretvalue(spellID) then
		return
	end
	local displayID = NS.GetDisplaySpellID and NS.GetDisplaySpellID(spellID)
	if displayID and not (issecretvalue and issecretvalue(displayID)) and displayID ~= spellID then
		NS.GlowingSpells[displayID] = v
	end
end

local function OnGlowShow(spellID)
	MarkSpellGlow(spellID, true)
	if NS.db and NS.db.glowEnabled then
		pendingUpdate = true
		updateDriver:Show()
	end
end

local function OnGlowHide(spellID)
	MarkSpellGlow(spellID, false)
	if NS.db and NS.db.glowEnabled then
		pendingUpdate = true
		updateDriver:Show()
	end
end

-- Event dispatch table (preferred over a long if-elseif chain). Several events map
-- to the same handler: keybind-cache rebuilds and visibility refreshes.
local eventHandlers = {
	ADDON_LOADED = OnAddonLoaded,

	-- Binding / bar / spec / form / stealth changes => rebuild keybind cache.
	UPDATE_BINDINGS = DelayedUpdateKeybindings,
	ACTIONBAR_SLOT_CHANGED = DelayedUpdateKeybindings,
	SPELLS_CHANGED = DelayedUpdateKeybindings,
	ACTIONBAR_PAGE_CHANGED = DelayedUpdateKeybindings,
	UPDATE_BONUS_ACTIONBAR = DelayedUpdateKeybindings,
	UPDATE_VEHICLE_ACTIONBAR = DelayedUpdateKeybindings,
	UPDATE_OVERRIDE_ACTIONBAR = DelayedUpdateKeybindings,
	-- Shapeshift changes both keybinds and (travel-form) visibility.
	UPDATE_SHAPESHIFT_FORM = function()
		DelayedUpdateKeybindings()
		NS.UpdateVisibility()
	end,
	UPDATE_STEALTH = DelayedUpdateKeybindings,
	PLAYER_TALENT_UPDATE = DelayedUpdateKeybindings,
	PLAYER_SPECIALIZATION_CHANGED = DelayedUpdateKeybindings,
	TRAIT_CONFIG_UPDATED = DelayedUpdateKeybindings,
	ACTIVE_PLAYER_SPECIALIZATION_CHANGED = DelayedUpdateKeybindings,

	-- Cooldown swipes: coalesced refresh so the ticker does not need to poll CDs.
	SPELL_UPDATE_COOLDOWN = ScheduleCooldownRefresh,
	ACTIONBAR_UPDATE_COOLDOWN = ScheduleCooldownRefresh,

	-- Visibility drivers (combat / vehicle / world entry / target / mount).
	PLAYER_REGEN_ENABLED = NS.UpdateVisibility,
	PLAYER_REGEN_DISABLED = NS.UpdateVisibility,
	UNIT_ENTERED_VEHICLE = NS.UpdateVisibility,
	UNIT_EXITED_VEHICLE = NS.UpdateVisibility,
	PLAYER_ENTERING_WORLD = function()
		NS.UpdateVisibility()
		if IsPlayerMoving then
			NS.playerIsMoving = IsPlayerMoving()
		end
	end,
	PLAYER_MOUNT_DISPLAY_CHANGED = NS.UpdateVisibility,
	UNIT_FLAGS = NS.UpdateVisibility,
	PLAYER_STARTED_MOVING = function()
		NS.playerIsMoving = true
		NS.UpdateNow()
	end,
	PLAYER_STOPPED_MOVING = function()
		NS.playerIsMoving = false
		NS.UpdateNow()
	end,
	-- Target change drives visibility (HasTarget/TargetInCombat) and re-probes the
	-- target's in-progress cast for the interrupt indicator.
	PLAYER_TARGET_CHANGED = function()
		NS.UpdateVisibility()
		if NS.db and NS.db.interruptEnabled then
			PollInterruptUnit("target")
			NS.UpdateInterrupt()
		end
	end,

	-- Focus swap re-probes the focus's in-progress cast (registered only while the
	-- interrupt watches focus/auto).
	PLAYER_FOCUS_CHANGED = function()
		if NS.db and NS.db.interruptEnabled then
			PollInterruptUnit("focus")
			NS.UpdateInterrupt()
		end
	end,

	-- Interrupt: target cast/channel start/stop (registered only while enabled).
	UNIT_SPELLCAST_START = OnTargetCastStart,
	UNIT_SPELLCAST_CHANNEL_START = OnTargetChannelStart,
	UNIT_SPELLCAST_STOP = OnTargetCastStop,
	UNIT_SPELLCAST_CHANNEL_STOP = OnTargetCastStop,
	UNIT_SPELLCAST_INTERRUPTED = OnTargetCastStop,

	-- Nameplate counter (registered only while enabled). The plate set only changes
	-- here, so this is where we recount; the per-tick path reads the cached count.
	NAME_PLATE_UNIT_ADDED = NS.RefreshNameplateCount,
	NAME_PLATE_UNIT_REMOVED = NS.RefreshNameplateCount,

	-- Trinket tracker: equipment swaps change which trinkets/icons to show
	-- (registered only while enabled).
	UNIT_INVENTORY_CHANGED = function()
		NS.UpdateTrinkets()
	end,

	-- Defensive health gate: registered only when threshold > 0 so the glow reacts
	-- immediately when player health changes rather than waiting for the next tick.
	UNIT_HEALTH = function()
		if NS.db and NS.db.defensivesEnabled then
			NS.UpdateDefensives()
		end
	end,

	-- Proc/activation glow tracking.
	SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = OnGlowShow,
	SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = OnGlowHide,

	-- Assisted-combat action cast -> the next recommended spell likely changed, so
	-- coalesce an immediate refresh (handler is a no-op if the event never fires).
	ASSISTED_COMBAT_ACTION_SPELL_CAST = OnAssistedCombatUpdate,
}

addonFrame:SetScript("OnEvent", function(self, event, ...)
	local handler = eventHandlers[event]
	if handler then
		handler(...)
	end
end)
