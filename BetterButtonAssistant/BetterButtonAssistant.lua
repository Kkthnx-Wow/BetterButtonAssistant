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
		Pushed = b.pushed,
	})

	-- Masque draws its own backdrop/frame, so drop our slot backing to avoid
	-- doubling it up. UpdateLayout honors this flag when toggling the slot.
	b.masqued = true
	if b.slot then
		b.slot:Hide()
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
	if
		issecretvalue and (issecretvalue(startTime) or issecretvalue(duration) or (modRate and issecretvalue(modRate)))
	then
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
		if (not slots or #slots == 0) and baseID ~= spellID then
			slots = NS.C_ActionBar_FindSpellActionButtons(spellID)
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

local function CreateSuggestionButton(parent)
	local b = NS.CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetSize(NS.db.buttonSize, NS.db.buttonSize)
	b:SetFrameLevel(parent:GetFrameLevel() + 2)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- Slot/backing: the dark frame slot the icon sits in. The modern action button
	-- has no separate drop-shadow region (Masque's Modern skin sets Shadow = Hidden);
	-- its depth comes from this slot plus the IconFrame border art. Sized a touch
	-- larger than the icon so its edge reads as a subtle shadow ring behind the icon.
	-- Using SetAtlas (not a hand-coded SetTexCoord) so the engine picks the right
	-- region and the hi-res Interface/HUD/UIActionBar2x file automatically.
	-- Centered on the button; the actual size is set in UpdateLayout.
	b.slot = b:CreateTexture(nil, "BACKGROUND")
	b.slot:SetAtlas("UI-HUD-ActionBar-IconFrame-Slot")
	b.slot:SetPoint("CENTER", b, "CENTER", 0, 0)

	b.cooldown = NS.CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints(b.icon)
	b.cooldown:SetFrameLevel(b:GetFrameLevel())

	-- Dedicated frame for the metal border art, kept a few levels above the button
	-- (and crucially above the cooldown frame). Child frames always draw on top of
	-- their parent's own textures, so a border texture placed directly on the button
	-- would be covered by the cooldown swipe and look like it's sinking behind the
	-- icon once the out-of-combat alpha dims everything. Hosting it here guarantees
	-- the frame always renders last, on top of the icon and the swipe.
	b.frameOverlay = NS.CreateFrame("Frame", nil, b)
	b.frameOverlay:SetAllPoints(b)
	b.frameOverlay:SetFrameLevel(b:GetFrameLevel() + 4)

	-- Border: Blizzard's modern icon frame (metal border + baked shadow). Atlas-based
	-- so it resolves to the correct 1x/2x texture.
	b.border = b.frameOverlay:CreateTexture(nil, "OVERLAY", nil, 0)
	b.border:SetAtlas("UI-HUD-ActionBar-IconFrame")
	b.border:SetPoint("CENTER", b, "CENTER", 0, 0)

	b.hotkey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall") -- Using a cleaner number font
	b.hotkey:SetPoint("TOPRIGHT", b.icon, "TOPRIGHT", -2, -2)
	b.hotkey:SetJustifyH("RIGHT")
	b.hotkey:SetDrawLayer("OVERLAY", 7)

	-- Pushed frame: Blizzard's real pressed icon-frame art, shown during the press so
	-- it reads like a genuine keypress (stands in for the cooldown swipe, which
	-- Midnight can't draw). Sits just above the normal border and tracks its rect.
	b.pushed = b.frameOverlay:CreateTexture(nil, "OVERLAY", nil, 1)
	b.pushed:SetAtlas("UI-HUD-ActionBar-IconFrame-Down")
	b.pushed:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.pushed:Hide()

	-- Press "pop": scale the whole button down then back up, around its center.
	-- The scale amounts are set by NS.ApplyFeedbackSettings (feedbackPressDepth).
	b.pressAnim = b:CreateAnimationGroup()
	local pressDown = b.pressAnim:CreateAnimation("Scale")
	pressDown:SetOrder(1)
	pressDown:SetDuration(0.07)
	pressDown:SetOrigin("CENTER", 0, 0)
	pressDown:SetSmoothing("IN")
	b.pressDownAnim = pressDown
	local pressUp = b.pressAnim:CreateAnimation("Scale")
	pressUp:SetOrder(2)
	pressUp:SetDuration(0.12)
	pressUp:SetOrigin("CENTER", 0, 0)
	pressUp:SetSmoothing("OUT")
	b.pressUpAnim = pressUp
	-- Swap the normal frame for the pressed frame during the down-phase, mirroring
	-- how Blizzard swaps Normal->Pushed on button state. Restoring just re-shows the
	-- normal border (honoring the showBorder option). When the border is off, the
	-- press is only the scale "pop", with no orphaned frame appearing.
	local function ShowPressed()
		if NS.db.showBorder then
			b.border:Hide()
			b.pushed:Show()
		end
	end
	local function RestoreFrame()
		b.pushed:Hide()
		b.border:SetShown(NS.db.showBorder)
	end
	b.pressAnim:SetScript("OnPlay", ShowPressed)
	-- Release the press as soon as the down-phase finishes (the up-phase is recovery).
	pressDown:SetScript("OnFinished", RestoreFrame)
	b.pressAnim:SetScript("OnFinished", RestoreFrame)
	b.pressAnim:SetScript("OnStop", RestoreFrame)

	-- Proc/activation glow: an additive ring that pulses while the suggested spell
	-- is procced (mirrors Blizzard's action-button glow). Shown via ShowGlow below.
	-- Additive highlight that fills the icon (with a tiny bleed past the edges) and
	-- pulses. Anchored to the icon so it tracks size automatically. We use a filling
	-- highlight texture rather than UI-ActionButton-Border, whose art is a hollow
	-- frame with transparent padding that left a gap inside the icon edges.
	b.glow = b:CreateTexture(nil, "OVERLAY", nil, 3)
	b.glow:SetTexture("Interface/Buttons/CheckButtonHilight")
	b.glow:SetBlendMode("ADD")
	b.glow:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -2, 2)
	b.glow:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 2, -2)
	b.glow:SetAlpha(0)
	b.glow:Hide()

	b.glowAnim = b.glow:CreateAnimationGroup()
	b.glowAnim:SetLooping("BOUNCE")
	local pulse = b.glowAnim:CreateAnimation("Alpha")
	pulse:SetFromAlpha(0.35)
	pulse:SetToAlpha(0.9)
	pulse:SetDuration(0.5)
	pulse:SetSmoothing("IN_OUT")

	-- Whenever the button hides (no suggestion, combat ends with "only in combat",
	-- vehicle, etc.) stop any in-flight feedback. Animations freeze on a hidden
	-- frame instead of finishing, which would otherwise leave the press stuck
	-- and pop a stray frame the next time the button is shown. OnHide also fires when
	-- the parent frame hides, so this one hook covers every hide path.
	b:SetScript("OnHide", function(self)
		if self.pressAnim then
			self.pressAnim:Stop()
		end
	end)

	b.spellID = nil

	NS.ApplyFeedbackSettings(b)
	SkinButton(b)

	return b
end

-- Applies the tunable feedback values (press depth) to a button's animations.
-- Safe to call repeatedly; the settings UI calls it live.
function NS.ApplyFeedbackSettings(b)
	if not b then
		return
	end

	local depth = NS.db.feedbackPressDepth or 0.85
	if b.pressDownAnim then
		b.pressDownAnim:SetScaleFrom(1, 1)
		b.pressDownAnim:SetScaleTo(depth, depth)
	end
	if b.pressUpAnim then
		b.pressUpAnim:SetScaleFrom(depth, depth)
		b.pressUpAnim:SetScaleTo(1, 1)
	end

	if b.glow then
		local g = NS.db.glowColor or { 1, 0.8, 0.1 }
		b.glow:SetVertexColor(g[1], g[2], g[3])
	end
end

-- Re-applies feedback tuning to the live suggestion button (used by the options UI).
function NS.RefreshFeedbackSettings()
	if frame.button then
		NS.ApplyFeedbackSettings(frame.button)
	end
end

-- Shows/hides the proc glow on a button, starting/stopping its pulse.
local function SetGlowShown(b, shown)
	if not b or not b.glow then
		return
	end
	if shown then
		if not b.glow:IsShown() then
			b.glow:Show()
			b.glowAnim:Play()
		end
	else
		if b.glow:IsShown() then
			b.glowAnim:Stop()
			b.glow:Hide()
		end
	end
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
	local displayID = NS.GetDisplaySpellID and NS.GetDisplaySpellID(spellID)
	if displayID and displayID ~= spellID and glowing[displayID] then
		return true
	end
	local base = NS.FindBaseSpellByID and NS.FindBaseSpellByID(spellID)
	return base ~= nil and glowing[base] == true
end

-- Plays the cast-confirmation feedback on the suggestion button: a quick "press"
-- (scale down/up). Triggered when the player casts the suggested spell
-- (UNIT_SPELLCAST_SUCCEEDED) or fires the assisted-combat action
-- (ASSISTED_COMBAT_ACTION_SPELL_CAST). It never inspects secret spell data,
-- so it stands in safely for the cooldown swipe, which Midnight can't draw.
local function PlayCastFeedback()
	if not NS.db.feedbackFlash then
		return
	end

	local b = frame.button
	if not b or not b.pressAnim then
		return
	end

	-- Only animate a button that's actually on screen. Playing while hidden would
	-- freeze the animation (it can't advance) and leave it to fire when reshown.
	if not b:IsVisible() then
		return
	end

	if b.pressAnim:IsPlaying() then
		b.pressAnim:Stop()
	end
	b.pressAnim:Play()

	if NS.db.feedbackSound and NS.PlaySound and NS.SOUNDKIT then
		NS.PlaySound(NS.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "SFX")
	end
end

-- Exposed so the `/bba test` slash command can preview the feedback animation.
NS.PlayCastFeedback = PlayCastFeedback

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

	-- Modern Blizzard action-button atlases are not square art. Masque's Modern
	-- reference treats IconFrame as 37x36 with a tiny +X nudge around a 32px icon.
	-- Keep that aspect/offset when scaling, otherwise the metal lip drifts against
	-- the icon (visible as uneven top/bottom or left/right padding).
	local borderWidth = size * 37 / 32
	local borderHeight = size * 36 / 32
	local borderOffsetX = size * 0.5 / 32 + 1
	local borderOffsetY = -2
	if b.border then
		b.border:ClearAllPoints()
		b.border:SetPoint("CENTER", b, "CENTER", borderOffsetX, borderOffsetY)
		b.border:SetSize(borderWidth, borderHeight)
		b.border:SetShown(NS.db.showBorder)
	end
	if b.pushed then
		b.pushed:ClearAllPoints()
		b.pushed:SetPoint("CENTER", b, "CENTER", borderOffsetX, borderOffsetY)
		b.pushed:SetSize(borderWidth, borderHeight)
	end
	if b.slot then
		b.slot:ClearAllPoints()
		b.slot:SetPoint("CENTER", b, "CENTER", borderOffsetX, borderOffsetY)
		b.slot:SetSize(size * 39 / 32, size * 38 / 32)
		b.slot:SetShown(NS.db.showBorder and not b.masqued)
	end

	-- Update Font Size
	local fontPath, _, fontFlags = b.hotkey:GetFont()
	b.hotkey:SetFont(fontPath, NS.db.keybindFontSize or 12, fontFlags)

	-- Update Frame properties
	frame:SetSize(size, size)
	frame:SetScale(NS.db.scale or 1.0)

	NS.ApplyFeedbackSettings(b)
	NS.ApplyCooldownStyle(b)
	NS.UpdateMouseState()

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

local function UpdateCooldownForSpell(b, spellID)
	if not NS.db.showCooldown then
		b.cooldown:Clear()
		b.cooldown:Hide()
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
	else
		b.cooldown:Hide()
	end
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
		if NS.ticker then
			NS.ticker:Cancel()
			NS.ticker = nil
			NS.tickerRate = nil
		end
	end
end

-- Maps the tullaRange-style state string to the configurable color in the DB.
local STATE_COLOR_KEY = {
	normal = "colorNormal",
	oor = "colorOOR",
	oom = "colorOOM",
	unusable = "colorUnusable",
}

-- Colors the suggestion icon/keybind by range & usability (tullaRange behavior).
local function ApplyActionState(b, spellID)
	-- Coloring disabled: ensure we don't leave the icon stuck in a tinted state.
	if not NS.db.rangeColoring then
		b.icon:SetVertexColor(1, 1, 1)
		b.icon:SetDesaturated(false)
		if b.hotkey then
			b.hotkey:SetVertexColor(1, 1, 1)
		end
		return
	end

	local state, _, _, outOfRange = NS.GetActionState(spellID)

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

	-- Hot path: only re-fetch the icon texture when the suggestion actually changes.
	-- Keybind text stays out of this guard but is memoized, so it's cheap per tick.
	local spellChanged = spellID ~= b.spellID
	b.spellID = spellID

	if spellChanged then
		if NS.C_Spell_GetSpellTexture then
			b.icon:SetTexture(NS.C_Spell_GetSpellTexture(spellID))
		else
			b.icon:SetTexture(nil)
		end
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
	ApplyActionState(b, spellID)

	if NS.db.glowEnabled then
		SetGlowShown(b, IsSpellGlowing(spellID))
	else
		SetGlowShown(b, false)
	end

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
-- Events
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
addonFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
addonFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")

-- Cast feedback: fires for every spell the player completes, so we can react
-- whenever they cast the spell we're currently suggesting (works regardless of
-- whether they used Blizzard's one-button action or their own keybind).
addonFrame:RegisterEvent("ASSISTED_COMBAT_ACTION_SPELL_CAST")
addonFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

-- Proc/activation glow tracking, so we can mirror it on the suggestion button.
addonFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
addonFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

-- Compares a cast spell against the suggested spell (incl. base-spell forms).
-- Hoisted to a module-level function so we don't allocate a closure per cast.
local function CompareSpellIDs(castSpellID, suggestedID)
	if castSpellID == suggestedID then
		return true
	end
	local castBase = NS.FindBaseSpellByID and NS.FindBaseSpellByID(castSpellID)
	local sugBase = NS.FindBaseSpellByID and NS.FindBaseSpellByID(suggestedID)
	if castBase ~= nil and castBase == sugBase then
		return true
	end
	local castDisplay = NS.GetDisplaySpellID and NS.GetDisplaySpellID(castSpellID)
	local sugDisplay = NS.GetDisplaySpellID and NS.GetDisplaySpellID(suggestedID)
	return (castDisplay ~= nil and castDisplay == suggestedID)
		or (sugDisplay ~= nil and sugDisplay == castSpellID)
		or (castDisplay ~= nil and castDisplay == sugDisplay)
end

-- True if the just-cast spell is the one we're currently suggesting. Spell IDs can
-- be secret values in Midnight (comparing them would error during tainted
-- execution), so detect first and bail out rather than risk the comparison.
local function CastMatchesSuggestion(castSpellID)
	local b = frame.button
	if not b or not b.spellID or not castSpellID then
		return false
	end

	if issecretvalue and (issecretvalue(castSpellID) or issecretvalue(b.spellID)) then
		return false
	end

	return CompareSpellIDs(castSpellID, b.spellID) == true
end

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

local function OnAddonLoaded(name)
	if name ~= ADDON_NAME or NS.loaded then
		return
	end
	NS.loaded = true
	-- One-shot: no longer needed once our SavedVariables are initialized.
	addonFrame:UnregisterEvent("ADDON_LOADED")

	BetterButtonAssistantDB = BetterButtonAssistantDB or {}
	NS.db = BetterButtonAssistantDB
	NS.CopyDefaults(NS.db, NS.defaults)

	NS.RegisterSettings() -- Initialize Modern Settings Panel

	RegisterAssistedCombatEvents() -- Hook into Blizzard's internal events

	-- Restore saved frame position if available.
	if NS.db.framePoint then
		frame:ClearAllPoints()
		frame:SetPoint(NS.db.framePoint, NS.UIParent, NS.db.frameRelPoint, NS.db.frameX, NS.db.frameY)
	end

	NS.UpdateLayout()
	NS.UpdateVisibility() -- Call UpdateVisibility after layout
	DelayedUpdateKeybindings() -- Ensure hotkeys are scanned after bars are ready
end

local function OnSpellcastSucceeded(_, _, spellID)
	if CastMatchesSuggestion(spellID) then
		PlayCastFeedback()
	end
end

local function OnGlowShow(spellID)
	if spellID then
		NS.GlowingSpells[spellID] = true
		local displayID = NS.GetDisplaySpellID and NS.GetDisplaySpellID(spellID)
		if displayID and displayID ~= spellID then
			NS.GlowingSpells[displayID] = true
		end
	end
end

local function OnGlowHide(spellID)
	if spellID then
		NS.GlowingSpells[spellID] = nil
		local displayID = NS.GetDisplaySpellID and NS.GetDisplaySpellID(spellID)
		if displayID and displayID ~= spellID then
			NS.GlowingSpells[displayID] = nil
		end
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
	UPDATE_SHAPESHIFT_FORM = DelayedUpdateKeybindings,
	UPDATE_STEALTH = DelayedUpdateKeybindings,
	PLAYER_TALENT_UPDATE = DelayedUpdateKeybindings,
	PLAYER_SPECIALIZATION_CHANGED = DelayedUpdateKeybindings,
	TRAIT_CONFIG_UPDATED = DelayedUpdateKeybindings,
	ACTIVE_PLAYER_SPECIALIZATION_CHANGED = DelayedUpdateKeybindings,

	-- Visibility drivers (combat / vehicle / world entry).
	PLAYER_REGEN_ENABLED = NS.UpdateVisibility,
	PLAYER_REGEN_DISABLED = NS.UpdateVisibility,
	UNIT_ENTERED_VEHICLE = NS.UpdateVisibility,
	UNIT_EXITED_VEHICLE = NS.UpdateVisibility,
	PLAYER_ENTERING_WORLD = NS.UpdateVisibility,

	-- Cast feedback.
	ASSISTED_COMBAT_ACTION_SPELL_CAST = PlayCastFeedback,
	UNIT_SPELLCAST_SUCCEEDED = OnSpellcastSucceeded,

	-- Proc/activation glow tracking.
	SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = OnGlowShow,
	SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = OnGlowHide,
}

addonFrame:SetScript("OnEvent", function(self, event, ...)
	local handler = eventHandlers[event]
	if handler then
		handler(...)
	end
end)
