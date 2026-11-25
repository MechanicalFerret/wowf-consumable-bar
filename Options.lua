local ADDON, ns = ...

local panel, category
local refreshers = {}

-- Section title with a thin rule under it
local function Header(parent, text, x, y, width)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.15)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", x, y - 22)
	line:SetWidth(width or 280)
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

-- Every option is one row: the label on the left, its control (checkbox, slider, dropdown or
-- button) on the right. parent.labelW is the width of the label column.
local function RowLabel(parent, text, x, y, labelW)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("TOPLEFT", x, y - 5)
	fs:SetWidth(labelW - 8)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs:SetText(text)
	return fs
end

local function ResetButton(parent, x, y)
	local labelW = parent.labelW
	RowLabel(parent, "Position", x, y, labelW)
	local reset = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	reset:SetSize(110, 22)
	reset:SetPoint("TOPLEFT", x + labelW, y - 1)
	reset:SetText("Reset")
	Tip(reset, "Reset position", TIPS.reset)
	reset:SetScript("OnClick", function() ns.ResetPosition() end)
	return reset
end

-- The label is part of the hit area, so clicking it toggles the box too
local function Checkbox(parent, label, x, y, get, set, tip, labelW)
	labelW = labelW or parent.labelW
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetPoint("TOPLEFT", x + labelW, y)
	c:SetHitRectInsets(-labelW, 0, 0, 0)
	local text = c.text or c.Text or _G[c:GetName() and (c:GetName() .. "Text") or ""]
	if text then text:SetText("") end
	c.label = RowLabel(parent, label, x, y, labelW)
	c:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		for _, fn in ipairs(refreshers) do fn() end
	end)
	refreshers[#refreshers + 1] = function() c:SetChecked(get()) end
	Tip(c, label, tip or TIPS[label])
	return c
end

local function Slider(parent, label, x, y, min, max, step, key, fmt)
	local labelW = parent.labelW
	local title = RowLabel(parent, label, x, y, labelW)

	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(parent.controlW, 16)
	s:SetPoint("TOPLEFT", x + labelW + 4, y - 5)
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
local function Dropdown(parent, x, y, key, choices, set, get, labelW)
	labelW = labelW or parent.labelW
	local function current()
		local v
		if get then v = get() else v = ns.GetDB()[key] end
		for _, c in ipairs(choices) do
			if c.value == v then return c end
		end
		return choices[1]
	end
	RowLabel(parent, DROPDOWN_LABELS[key], x, y - 3, labelW)
	ddCount = ddCount + 1
	local dd = CreateFrame("Frame", "ConsumableBarDropdown" .. ddCount, parent, "UIDropDownMenuTemplate")
	-- the template has about 16px of padding on its left edge
	dd:SetPoint("TOPLEFT", x + labelW - 16, y + 2)
	UIDropDownMenu_SetWidth(dd, parent.controlW - 10)
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
	{ value = "SMALL", text = "Smaller first" },
	{ value = "LARGE", text = "Larger first" },
}

-- Appearance settings shown beside the bar while it is selected in Edit Mode
local dialog

function ns.ShowEditDialog(bar)
	local db = ns.GetDB()
	if not dialog then
		dialog = CreateFrame("Frame", "ConsumableBarEditDialog", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		dialog:SetSize(290, 270)
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

		dialog.labelW, dialog.controlW = 125, 110
		local y = -48
		Dropdown(dialog, 20, y, "direction", DIRECTIONS, ns.SetDirection)
		y = y - 32
		Slider(dialog, "Button size", 20, y, 20, 64, 1, "size", "%d")
		Slider(dialog, "Spacing", 20, y - 28, 0, 20, 1, "spacing", "%d")
		Slider(dialog, "Scale", 20, y - 56, 0.5, 2, 0.05, "scale", "%.2f")
		y = y - 90
		Checkbox(dialog, "Hide empty buttons", 20, y,
			function() return db.hideEmpty end, function(v) db.hideEmpty = v; ns.ApplySettings() end)
		Checkbox(dialog, "Show item counts", 20, y - 26,
			function() return db.showCount end, function(v) db.showCount = v; ns.ApplySettings() end)
		ResetButton(dialog, 20, y - 58)
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

	-- Left column: Layout, then Behaviour. Right column: Buttons (and class buffs).
	panel.labelW, panel.controlW = 150, 110
	Header(panel, "Layout", 16, -64)
	local y = -96
	Dropdown(panel, 16, y, "direction", DIRECTIONS, ns.SetDirection)
	Slider(panel, "Button size", 16, y - 34, 20, 64, 1, "size", "%d")
	Slider(panel, "Spacing", 16, y - 62, 0, 20, 1, "spacing", "%d")
	Slider(panel, "Scale", 16, y - 90, 0.5, 2, 0.05, "scale", "%.2f")
	ResetButton(panel, 16, y - 122)

	Header(panel, "Behaviour", 16, -250)
	y = -282
	local function check(label, get, set, tip)
		Checkbox(panel, label, 16, y, get, set, tip)
		y = y - 26
	end
	check("Lock bar", function() return db.locked end, function(v) ns.SetLocked(v) end)
	check("Hide empty buttons", function() return db.hideEmpty end, function(v) db.hideEmpty = v; ns.ApplySettings() end)
	check("Show item counts", function() return db.showCount end, function(v) db.showCount = v; ns.ApplySettings() end)
	check("Show tooltips", function() return db.showTooltip end, function(v) db.showTooltip = v end)
	check("Always use Mage items", function() return db.preferMage end, function(v) db.preferMage = v; ns.Refresh(true, false) end)
	check("Prefer Well Fed food", function() return db.preferWellFed end, function(v) db.preferWellFed = v; ns.Refresh(true, false) end)
	Dropdown(panel, 16, y, "stackPref", STACK_CHOICES, function(v) db.stackPref = v; ns.Refresh(true, false) end)

	-- Right column: which buttons show
	Header(panel, "Buttons", 330, -64, 270)
	local row = 0
	for _, cat in ipairs(ns.CATEGORIES) do
		if not ns.HIDDEN[cat] then
			Checkbox(panel, ns.LABELS[cat], 330, -96 - row * 24,
				function() return db.show[cat] end,
				function(v) db.show[cat] = v; ns.ApplySettings() end,
				CATEGORY_TIPS[cat], 170)
			row = row + 1
		end
	end

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
