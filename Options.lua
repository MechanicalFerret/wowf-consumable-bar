local ADDON, ns = ...

local panel, category
local refreshers = {}

local function Header(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

-- Hover explanations, keyed by the option's label (checkboxes), key (sliders, dropdowns) or category
local TIPS = {
	["Lock bar"] = "Unlocked, drag the bar with the left mouse button. It can always be moved in Edit Mode. Also /cbar lock and /cbar unlock.",
	["Hide empty buttons"] = "Hides buttons that have nothing in your bags. When off, empty buttons show dimmed.",
	["Show item counts"] = "Shows how many of each item you carry on its button.",
	["Show tooltips"] = "Shows the item or ability tooltip when you hover a button.",
	["Always use Mage items"] = "Conjured food and water are chosen before any other food or water, even if the others restore more.",
	["Prefer Well Fed food"] = "When two foods restore the same amount, the one that grants the Well Fed buff is chosen.",
	size = "Size of each button.",
	spacing = "Gap between buttons.",
	scale = "Scales the whole bar.",
	direction = "Which edge the bar is anchored to. Grow right keeps the left edge fixed, grow left keeps the right edge fixed, so buttons appearing or disappearing extend away from that edge.",
	stackPref = "When two items are otherwise equal, choose the one you have fewer of (use it up first) or more of.",
	reset = "Moves the bar back to its default position.",
}
local CATEGORY_TIPS = {
	food = "Shows the food that restores the most health.",
	water = "Shows the drink that restores the most mana.",
	bandage = "Shows the bandage that heals the most. Used on your friendly target, otherwise on you.",
	healthPotion = "Shows your strongest healing potion.",
	manaPotion = "Shows your strongest mana potion.",
	rejuvPotion = "Shows your strongest potion that restores both health and mana.",
	healthstone = "Shows your best Healthstone. Warlocks without one get a Create Healthstone button.",
	racial = "Shows Cannibalize (Forsaken) or Rapid Regeneration (Trolls) when you have it.",
}

local function Tip(frame, title, text)
	if not text then return end
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		GameTooltip:AddLine(text, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Checkbox(parent, label, x, y, get, set, tip)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetPoint("TOPLEFT", x, y)
	local text = c.text or c.Text or _G[c:GetName() and (c:GetName() .. "Text") or ""]
	if not text then
		text = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("LEFT", c, "RIGHT", 2, 1)
	end
	text:SetText(label)
	c:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		for _, fn in ipairs(refreshers) do fn() end
	end)
	refreshers[#refreshers + 1] = function() c:SetChecked(get()) end
	Tip(c, label, tip or TIPS[label])
	return c
end

local function Slider(parent, label, x, y, min, max, step, key, fmt)
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title:SetPoint("TOPLEFT", x, y)

	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(220, 16)
	s:SetPoint("TOPLEFT", x, y - 20)
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetColorTexture(0.25, 0.25, 0.25, 1)
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	s:GetThumbTexture():SetSize(20, 28)

	Tip(s, label, TIPS[key])

	local function show(v) title:SetText(label .. ": |cffffffff" .. string.format(fmt, v) .. "|r") end
	s:SetScript("OnValueChanged", function(self, v)
		if self.syncing then return end
		ns.GetDB()[key] = v
		show(v)
		ns.ApplySettings()
	end)
	refreshers[#refreshers + 1] = function()
		local v = ns.GetDB()[key]
		s.syncing = true
		s:SetValue(v)
		s.syncing = false
		show(v)
	end
	return s
end

local DROPDOWN_LABELS = { direction = "Direction", stackPref = "Stack tie-break" }
local ddCount = 0
-- choices: { { value =, text = }, ... }; the first one is the default for a missing/unknown value
local function Dropdown(parent, x, y, key, choices, set)
	local function current()
		local v = ns.GetDB()[key]
		for _, c in ipairs(choices) do
			if c.value == v then return c end
		end
		return choices[1]
	end
	ddCount = ddCount + 1
	local dd = CreateFrame("Frame", "ConsumableBarDropdown" .. ddCount, parent, "UIDropDownMenuTemplate")
	dd:SetPoint("TOPLEFT", x, y)
	UIDropDownMenu_SetWidth(dd, 180)
	UIDropDownMenu_Initialize(dd, function()
		for _, c in ipairs(choices) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = c.text
			info.checked = current() == c
			info.func = function()
				set(c.value)
				for _, fn in ipairs(refreshers) do fn() end
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
	refreshers[#refreshers + 1] = function() UIDropDownMenu_SetText(dd, current().text) end
	local name = dd:GetName()
	local button = dd.Button or (name and _G[name .. "Button"])
	Tip(button or dd, DROPDOWN_LABELS[key], TIPS[key])
	return dd
end

local DIRECTIONS = {
	{ value = "LTR", text = "Grow right" },
	{ value = "RTL", text = "Grow left" },
}
local STACK_CHOICES = {
	{ value = "SMALL", text = "Smaller stacks first" },
	{ value = "LARGE", text = "Larger stacks first" },
}

-- Appearance settings shown beside the bar while it is selected in Edit Mode
local dialog

function ns.ShowEditDialog(bar)
	local db = ns.GetDB()
	if not dialog then
		dialog = CreateFrame("Frame", "ConsumableBarEditDialog", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		dialog:SetSize(290, 290)
		dialog:SetFrameStrata("DIALOG")
		dialog:SetClampedToScreen(true)
		dialog:EnableMouse(true)
		dialog:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		local t = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		t:SetPoint("TOPLEFT", 20, -20)
		t:SetText("Consumable Bar")
		local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -4, -4)
		close:SetScript("OnClick", function() ns.SetSelected(false) end)

		Dropdown(dialog, 12, -44, "direction", DIRECTIONS, ns.SetDirection)
		Slider(dialog, "Button size", 28, -90, 20, 64, 1, "size", "%d")
		Slider(dialog, "Spacing", 28, -136, 0, 20, 1, "spacing", "%d")
		Slider(dialog, "Scale", 28, -182, 0.5, 2, 0.05, "scale", "%.2f")
		Checkbox(dialog, "Hide empty buttons", 20, -222,
			function() return db.hideEmpty end, function(v) db.hideEmpty = v; ns.ApplySettings() end)
		Checkbox(dialog, "Show item counts", 20, -248,
			function() return db.showCount end, function(v) db.showCount = v; ns.ApplySettings() end)
	end
	-- below the bar when it is in the top half of the screen, above otherwise
	local _, cy = bar:GetCenter()
	dialog:ClearAllPoints()
	if cy and cy > UIParent:GetHeight() / 2 / (bar:GetEffectiveScale() / UIParent:GetEffectiveScale()) then
		dialog:SetPoint("TOP", bar, "BOTTOM", 0, -12)
	else
		dialog:SetPoint("BOTTOM", bar, "TOP", 0, 12)
	end
	for _, fn in ipairs(refreshers) do fn() end
	dialog:Show()
end

function ns.HideEditDialog()
	if dialog then dialog:Hide() end
end

function ns.OpenOptions()
	if not category then return end
	if Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

-- Both bar addons share one "Adaptable Bars" settings category; whichever loads first creates it.
local PARENT_NAME = "Adaptable Bars"

local function RegisterPanel(panel)
	local parent = _G.AdaptableBarsCategory
	if not parent then
		local home = CreateFrame("Frame")
		home.name = PARENT_NAME
		local t = home:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
		t:SetPoint("TOPLEFT", 16, -16)
		t:SetText(PARENT_NAME)
		local d = home:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
		d:SetText("Pick a bar on the left.")
		if Settings and Settings.RegisterCanvasLayoutCategory then
			parent = Settings.RegisterCanvasLayoutCategory(home, PARENT_NAME)
			Settings.RegisterAddOnCategory(parent)
			_G.AdaptableBarsCategory = parent
		elseif InterfaceOptions_AddCategory then
			InterfaceOptions_AddCategory(home)
			_G.AdaptableBarsCategory = home
		end
	end

	if Settings and Settings.RegisterCanvasLayoutSubcategory and parent and parent.GetID then
		category = Settings.RegisterCanvasLayoutSubcategory(parent, panel, panel.name)
	elseif Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		panel.parent = PARENT_NAME
		InterfaceOptions_AddCategory(panel)
	end
end

function ns.BuildOptions()
	local db = ns.GetDB()
	panel = CreateFrame("Frame")
	panel.name = "Consumable Bar"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Consumable Bar")

	-- Layout
	Header(panel, "Layout", 16, -70)
	Dropdown(panel, 8, -98, "direction", DIRECTIONS, ns.SetDirection)

	Slider(panel, "Button size", 24, -160, 20, 64, 1, "size", "%d")
	Slider(panel, "Spacing", 24, -206, 0, 20, 1, "spacing", "%d")
	Slider(panel, "Scale", 24, -252, 0.5, 2, 0.05, "scale", "%.2f")

	-- Behaviour
	Header(panel, "Behaviour", 16, -300)
	Checkbox(panel, "Lock bar", 16, -326,
		function() return db.locked end, function(v) ns.SetLocked(v) end)
	Checkbox(panel, "Hide empty buttons", 16, -352,
		function() return db.hideEmpty end, function(v) db.hideEmpty = v; ns.ApplySettings() end)
	Checkbox(panel, "Show item counts", 16, -378,
		function() return db.showCount end, function(v) db.showCount = v; ns.ApplySettings() end)
	Checkbox(panel, "Show tooltips", 16, -404,
		function() return db.showTooltip end, function(v) db.showTooltip = v end)
	Checkbox(panel, "Always use Mage items", 16, -430,
		function() return db.preferMage end, function(v) db.preferMage = v; ns.Refresh(true, false) end)
	Checkbox(panel, "Prefer Well Fed food", 16, -456,
		function() return db.preferWellFed end, function(v) db.preferWellFed = v; ns.Refresh(true, false) end)
	Dropdown(panel, 8, -484, "stackPref", STACK_CHOICES, function(v) db.stackPref = v; ns.Refresh(true, false) end)

	-- Categories
	Header(panel, "Buttons", 330, -70)
	local row = 0
	for _, cat in ipairs(ns.CATEGORIES) do
		if not ns.HIDDEN[cat] then
			Checkbox(panel, ns.LABELS[cat], 330, -96 - row * 26,
				function() return db.show[cat] end,
				function(v) db.show[cat] = v; ns.ApplySettings() end,
				CATEGORY_TIPS[cat])
			row = row + 1
		end
	end

	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(140, 24)
	reset:SetPoint("TOPLEFT", 330, -330)
	reset:SetText("Reset position")
	Tip(reset, "Reset position", TIPS.reset)
	reset:SetScript("OnClick", function() ns.ResetPosition() end)

	-- The settings window can show the panel without a usable OnShow, so sync on
	-- every hook it offers and once up front.
	local function refresh()
		for _, fn in ipairs(refreshers) do fn() end
	end
	panel.OnRefresh = refresh
	panel:SetScript("OnShow", function()
		refresh()
		C_Timer.After(0, refresh)
	end)
	refresh()

	RegisterPanel(panel)
end
