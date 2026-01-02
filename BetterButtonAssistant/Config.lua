local ADDON_NAME, NS = ...

-- ---------------------------------------------------------------------
-- Settings Registration (Modern UI)
-- ---------------------------------------------------------------------

function NS.RegisterSettings()
	local category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)
	NS.SettingsCategory = category

	-- Helper to register settings
	local function Register(key, varType, name, defaultValue, description, callback)
		local setting =
			Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, NS.db, varType, name, defaultValue)
		if callback then
			setting:SetValueChangedCallback(callback)
		end
		return setting
	end

	-- General Toggle
	local enabledSetting = Register(
		"enabled",
		Settings.VarType.Boolean,
		"Enabled",
		true,
		"Enable or disable the addon.",
		function()
			if NS.UpdateNow then
				NS.UpdateNow()
			end
		end
	)
	Settings.CreateCheckbox(category, enabledSetting, "Toggle BetterAssistant on/off.")

	-- Lock Toggle
	local lockedSetting =
		Register("locked", Settings.VarType.Boolean, "Locked", false, "Lock the frame to prevent dragging.")
	Settings.CreateCheckbox(category, lockedSetting, "Lock the suggestion button in place.")

	-- Visual Settings Category
	local visualSubcat = Settings.RegisterVerticalLayoutSubcategory(category, "Visuals")

	-- The "Right" label is standard for showing values next to sliders
	local labelRight = (
		MinimalSliderWithSteppersMixin
		and MinimalSliderWithSteppersMixin.Label
		and MinimalSliderWithSteppersMixin.Label.Right
	) or 2

	-- Button Size
	local sizeSetting = Register("buttonSize", Settings.VarType.Number, "Button Size", 40, nil, function()
		if NS.UpdateLayout then
			NS.UpdateLayout()
		end
	end)
	local sizeOptions = Settings.CreateSliderOptions(20, 100, 2)
	sizeOptions:SetLabelFormatter(labelRight, function(value)
		return value .. "px"
	end)
	Settings.CreateSlider(visualSubcat, sizeSetting, sizeOptions, "Adjust the dimensions of the suggestion button.")

	-- Show Border
	local borderSetting = Register("showBorder", Settings.VarType.Boolean, "Show Border", true, nil, function()
		if NS.UpdateLayout then
			NS.UpdateLayout()
		end
	end)
	Settings.CreateCheckbox(visualSubcat, borderSetting, "Toggle the Blizzard-style border around the button.")

	-- Scale
	local scaleSetting = Register("scale", Settings.VarType.Number, "Scale", 1.0, nil, function()
		if NS.UpdateLayout then
			NS.UpdateLayout()
		end
	end)
	local scaleOptions = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
	scaleOptions:SetLabelFormatter(labelRight, function(value)
		return (NS.math_floor(value * 100)) .. "%"
	end)
	Settings.CreateSlider(visualSubcat, scaleSetting, scaleOptions, "Overall scale of the assistant UI.")

	-- Visibility Category
	local visibilitySubcat = Settings.RegisterVerticalLayoutSubcategory(category, "Visibility")

	local alphaCombatSetting = Register(
		"alphaCombat",
		Settings.VarType.Number,
		"Alpha (In Combat)",
		1.0,
		nil,
		function()
			if NS.UpdateVisibility then
				NS.UpdateVisibility()
			end
		end
	)
	local alphaCombatOptions = Settings.CreateSliderOptions(0.0, 1.0, 0.05)
	alphaCombatOptions:SetLabelFormatter(labelRight, function(value)
		return (NS.math_floor(value * 100)) .. "%"
	end)
	Settings.CreateSlider(
		visibilitySubcat,
		alphaCombatSetting,
		alphaCombatOptions,
		"Opacity of the frame when in combat."
	)

	local alphaOOCSetting = Register("alphaOOC", Settings.VarType.Number, "Alpha (Out of Combat)", 0.5, nil, function()
		if NS.UpdateVisibility then
			NS.UpdateVisibility()
		end
	end)
	local alphaOOCOptions = Settings.CreateSliderOptions(0.0, 1.0, 0.05)
	alphaOOCOptions:SetLabelFormatter(labelRight, function(value)
		return (NS.math_floor(value * 100)) .. "%"
	end)
	Settings.CreateSlider(
		visibilitySubcat,
		alphaOOCSetting,
		alphaOOCOptions,
		"Opacity of the frame when out of combat."
	)

	local onlyInCombatSetting = Register(
		"onlyInCombat",
		Settings.VarType.Boolean,
		"Only Show in Combat",
		false,
		nil,
		function()
			if NS.UpdateVisibility then
				NS.UpdateVisibility()
			end
		end
	)
	Settings.CreateCheckbox(visibilitySubcat, onlyInCombatSetting, "Hide the frame completely when not in combat.")

	local hideInVehicleSetting = Register(
		"hideInVehicle",
		Settings.VarType.Boolean,
		"Hide in Vehicle",
		true,
		nil,
		function()
			if NS.UpdateVisibility then
				NS.UpdateVisibility()
			end
		end
	)
	Settings.CreateCheckbox(visibilitySubcat, hideInVehicleSetting, "Hide the frame when in a vehicle.")

	-- Keybinds Category
	local keybindSubcat = Settings.RegisterVerticalLayoutSubcategory(category, "Keybinds & Cooldowns")

	-- Show Keybind
	local showKeybindSetting = Register("showKeybind", Settings.VarType.Boolean, "Show Keybinds", true, nil, function()
		if NS.UpdateNow then
			NS.UpdateNow()
		end
	end)
	Settings.CreateCheckbox(keybindSubcat, showKeybindSetting, "Show the keybind text on the button.")

	-- Keybind Font Size
	local fontSizeSetting = Register(
		"keybindFontSize",
		Settings.VarType.Number,
		"Keybind Font Size",
		12,
		nil,
		function()
			if NS.UpdateLayout then
				NS.UpdateLayout()
			end
		end
	)
	local fontOptions = Settings.CreateSliderOptions(6, 24, 1)
	fontOptions:SetLabelFormatter(labelRight, function(value)
		return value .. "pt"
	end)
	Settings.CreateSlider(keybindSubcat, fontSizeSetting, fontOptions, "Adjust the size of the keybind text.")

	-- Show Cooldown
	local showCooldownSetting = Register(
		"showCooldown",
		Settings.VarType.Boolean,
		"Show Cooldown",
		true,
		nil,
		function()
			if NS.UpdateNow then
				NS.UpdateNow()
			end
		end
	)
	Settings.CreateCheckbox(keybindSubcat, showCooldownSetting, "Show the cooldown animation.")

	-- Logic Category
	local logicSubcat = Settings.RegisterVerticalLayoutSubcategory(category, "Logic")

	-- Visible Button Check
	local visibleSetting = Register("checkVisibleButton", Settings.VarType.Boolean, "Check Visible Buttons", true)
	Settings.CreateCheckbox(
		logicSubcat,
		visibleSetting,
		"Only suggest spells that are currently visible on your action bars."
	)

	Settings.RegisterAddOnCategory(category)
	NS.SettingsCategory = category
end

-- ---------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------
SLASH_BETTERBUTTONASSISTANT1 = "/betterbuttonassistant"
SLASH_BETTERBUTTONASSISTANT2 = "/bba"
SLASH_BETTERBUTTONASSISTANT3 = "/betterassistant"
SLASH_BETTERBUTTONASSISTANT4 = "/ba"

SlashCmdList.BETTERBUTTONASSISTANT = function(msg)
	msg = msg and NS.string_lower(msg) or ""

	if msg == "toggle" then
		NS.db.enabled = not NS.db.enabled
		if NS.UpdateNow then
			NS.UpdateNow()
		end
		return
	end

	-- Open Settings Panel
	if Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(NS.SettingsCategory:GetID())
	end
end
