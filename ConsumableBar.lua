local ADDON, ns = ...

local CATEGORIES = { "food", "water", "bandage", "healthPotion", "manaPotion", "rejuvPotion", "healthstone" }
local LABELS = {
	food = "Food",
	water = "Water",
	bandage = "Bandage",
	healthPotion = "Healing Potion",
	manaPotion = "Mana Potion",
	rejuvPotion = "Rejuvenation Potion",
	healthstone = "Healthstone",
}
local EMPTY_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local DEFAULTS = {
	direction = "LTR", -- LTR: grows right, anchored on its left edge; RTL: grows left, anchored on its right edge
	size = 36,
	spacing = 4,
	scale = 1,
	locked = true,
	hideEmpty = true,
	showCount = true,
	showTooltip = true,
	preferMage = true, -- conjured food and water beat any other food and water
	show = { food = true, water = true, bandage = true, healthPotion = true, manaPotion = true, rejuvPotion = true, healthstone = true },
	pos = { 0, -200 }, -- anchor edge: x, y from the screen centre, in UIParent units
}

-- Healthstones, weakest to strongest (talent-improved ranks sit above their base rank)
local HEALTHSTONES = {
	5512, 19004, 19005,
	5511, 19006, 19007,
	5509, 19008, 19009,
	5510, 19010, 19011,
	9421, 19012, 19013,
	22103, 22104, 22105,
	36889, 36890, 36891, 36892,
}
local HEALTHSTONE_RANK = {}
for rank, id in ipairs(HEALTHSTONES) do HEALTHSTONE_RANK[id] = rank end

-- Warlock "Create Healthstone" ranks, strongest first (unknown ids are simply skipped)
local CREATE_HEALTHSTONE = { 47879, 47878, 27230, 11730, 11729, 5699, 6202, 6201 }
local CREATE_TINT = { 0.6, 0.45, 1 }
local IS_WARLOCK = select(2, UnitClass("player")) == "WARLOCK"

local CLASS_CONSUMABLE, SUB_POTION, SUB_FOOD, SUB_BANDAGE = 0, 1, 5, 7

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemCooldown = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
local function SpellTexture(id)
	return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id))
end
local function SpellKnown(id)
	if IsPlayerSpell then return IsPlayerSpell(id) end
	return IsSpellKnown and IsSpellKnown(id)
end
local function SpellCooldown(id)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(id)
		if info then return info.startTime, info.duration end
		return
	end
	return GetSpellCooldown(id)
end
local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local function SlotItemID(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		return info and info.itemID
	end
	return GetContainerItemID and GetContainerItemID(bag, slot)
end

local db
local bar
local buttons = {}
local slots = {} -- category -> itemID of the current best
local createSpell -- warlock fallback for the healthstone slot
local misses = {} -- itemID -> failed tooltip reads
local analysis = {} -- itemID -> { food=, water=, hp=, mp= } (false when not a candidate)
local needsLayout, needsRetry = false, false
local editMode = false

local function Movable() return editMode or not db.locked end

ns.CATEGORIES, ns.LABELS, ns.DEFAULTS = CATEGORIES, LABELS, DEFAULTS

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

---------------------------------------------------------------------------
-- Item analysis (tooltip based so every food, drink and potion tier works)
---------------------------------------------------------------------------
local scanTip = CreateFrame("GameTooltip", "ConsumableBarScanTip", UIParent, "GameTooltipTemplate")

local function ParseUseLine(text, subclass, out)
	if subclass == SUB_FOOD then
		local h, m = text:match("Restores (%d+) health and (%d+) mana over")
		if h then
			out.food, out.water = tonumber(h), tonumber(m)
			return
		end
		h = text:match("Restores (%d+) health over")
		m = text:match("Restores (%d+) mana over")
		if h then out.food = tonumber(h) end
		if m then out.water = tonumber(m) end
	elseif subclass == SUB_BANDAGE then
		local n = text:match("Heals (%d+) damage over")
		if n then out.bandage = tonumber(n) end
	elseif subclass == SUB_POTION and not text:find(" over ", 1, true) then
		local lo, hi = text:match("(%d+) to (%d+) health and mana")
		if lo then
			local avg = (tonumber(lo) + tonumber(hi)) / 2
			out.hp, out.mp = avg, avg
			return
		end
		lo, hi = text:match("(%d+) to (%d+) health")
		if lo then
			out.hp = (tonumber(lo) + tonumber(hi)) / 2
		else
			lo = text:match("Restores (%d+) health")
			if lo then out.hp = tonumber(lo) end
		end
		lo, hi = text:match("(%d+) to (%d+) mana")
		if lo then
			out.mp = (tonumber(lo) + tonumber(hi)) / 2
		else
			lo = text:match("Restores (%d+) mana")
			if lo then out.mp = tonumber(lo) end
		end
	end
end

local function Analyze(id)
	local cached = analysis[id]
	if cached ~= nil then return cached end

	local _, _, _, _, _, class, subclass = GetItemInfoInstant(id)
	if class == nil then
		needsRetry = true
		return false
	end
	if class ~= CLASS_CONSUMABLE or (subclass ~= SUB_POTION and subclass ~= SUB_FOOD and subclass ~= SUB_BANDAGE) then
		analysis[id] = false
		return false
	end

	-- At login the item cache is cold and the tooltip is only a placeholder. Don't
	-- analyse (or cache a "not a candidate" result) until the client has the item.
	if not GetItemInfo(id) then
		needsRetry = true
		return false
	end

	scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	scanTip:ClearLines()
	scanTip:SetHyperlink("item:" .. id)
	local lines = scanTip:NumLines()
	if lines == 0 then
		needsRetry = true
		return false
	end

	local out = {}
	for i = 2, lines do
		local fs = _G["ConsumableBarScanTipTextLeft" .. i]
		local text = fs and fs:GetText()
		if text then
			if text:find("^Use:") then
				ParseUseLine(text, subclass, out)
				if text:lower():find("well fed", 1, true) then out.wellFed = true end
			elseif text == "Conjured Item" then
				out.conjured = true
			end
		end
	end
	if not (out.food or out.water or out.bandage or out.hp or out.mp) then
		-- the tooltip may not be complete yet: only give up on the item after a few tries
		misses[id] = (misses[id] or 0) + 1
		if misses[id] < 4 then
			needsRetry = true
			return false
		end
		out = false
	end
	analysis[id] = out
	return out
end

local function Scan()
	local best = {}
	local function consider(cat, id, value)
		local cur = best[cat]
		if not cur or value > cur.value then best[cat] = { id = id, value = value } end
	end

	local playerLevel = UnitLevel("player")
	local seen = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (NumSlots(bag) or 0) do
			local id = SlotItemID(bag, slot)
			if id and not seen[id] then
				seen[id] = true
				local rank = HEALTHSTONE_RANK[id]
				local info = not rank and Analyze(id)
				if rank or info then
					local name, _, _, _, minLevel = GetItemInfo(id)
					if not name then needsRetry = true end
					if (minLevel or 0) <= playerLevel then
						if rank then
							consider("healthstone", id, rank)
						else
							-- conjured (mage) food and water outrank everything else when preferred
							local bonus = (db.preferMage and info.conjured) and 1e9 or 0
							-- the 0.5 only breaks ties: amounts are whole numbers, so Well Fed food never loses to equal food
							if info.food then consider("food", id, info.food + bonus + (info.wellFed and 0.5 or 0)) end
							if info.water then consider("water", id, info.water + bonus) end
							if info.bandage then consider("bandage", id, info.bandage) end
							if info.hp and info.mp then
								-- restores both: its own slot, not a healing or mana potion
								consider("rejuvPotion", id, info.hp + info.mp)
							elseif info.hp then
								consider("healthPotion", id, info.hp)
							elseif info.mp then
								consider("manaPotion", id, info.mp)
							end
						end
					end
				end
			end
		end
	end

	for _, cat in ipairs(CATEGORIES) do
		slots[cat] = best[cat] and best[cat].id or nil
	end

	createSpell = nil
	if IS_WARLOCK and not slots.healthstone then
		for _, id in ipairs(CREATE_HEALTHSTONE) do
			if SpellKnown(id) then
				createSpell = id
				break
			end
		end
	end
end

---------------------------------------------------------------------------
-- Bar
---------------------------------------------------------------------------
-- The bar is anchored by one edge (left when growing right, right when growing left)
-- so adding or removing buttons only extends the free side.
local function AnchorPoint() return db.direction == "RTL" and "RIGHT" or "LEFT" end

local function ApplyPosition()
	local x, y = db.pos[1], db.pos[2]
	local scale = bar:GetScale()
	bar:ClearAllPoints()
	bar:SetPoint(AnchorPoint(), UIParent, "CENTER", x / scale, y / scale)
end

-- Reads the anchor edge's current screen position into db.pos
local function CapturePosition()
	local edge = db.direction == "RTL" and bar:GetRight() or bar:GetLeft()
	local _, cy = bar:GetCenter()
	if not edge then return end
	local ratio = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
	db.pos = {
		edge * ratio - UIParent:GetWidth() / 2,
		cy * ratio - UIParent:GetHeight() / 2,
	}
end

local function SavePosition()
	CapturePosition()
	ApplyPosition()
end

local function CreateButton(cat)
	local b = CreateFrame("Button", "ConsumableBarButton" .. cat, bar, "SecureActionButtonTemplate")
	b.category = cat
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "item")

	b.icon = b:CreateTexture(nil, "BACKGROUND")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)

	b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints()

	-- same border, pressed and hover textures as the stock action buttons
	b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
	b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:GetPushedTexture():SetAllPoints()

	b:SetScript("OnEnter", function(self)
		if not db.showTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if self.itemID then
			GameTooltip:SetHyperlink("item:" .. self.itemID)
		elseif self.spellID then
			GameTooltip:SetSpellByID(self.spellID)
		else
			GameTooltip:SetText(LABELS[self.category])
			GameTooltip:AddLine("None in your bags.", 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function UpdateButton(b)
	local id = b.itemID
	if not id and b.spellID then
		b.icon:SetTexture(SpellTexture(b.spellID))
		b.icon:SetDesaturated(true)
		b.icon:SetVertexColor(unpack(CREATE_TINT))
		b.icon:SetAlpha(1)
		b.count:SetText("")
		local start, duration = SpellCooldown(b.spellID)
		if start and duration and duration > 0 then
			b.cooldown:SetCooldown(start, duration)
		else
			b.cooldown:Clear()
		end
		return
	end
	b.icon:SetVertexColor(1, 1, 1)
	if id then
		local _, _, _, _, icon = GetItemInfoInstant(id)
		b.icon:SetTexture(icon)
		b.icon:SetDesaturated(false)
		b.icon:SetAlpha(1)
		local n = GetItemCount(id) or 0
		b.count:SetText((db.showCount and n > 1) and n or "")
		local start, duration = GetItemCooldown(id)
		if start and duration and duration > 0 then
			b.cooldown:SetCooldown(start, duration)
		else
			b.cooldown:Clear()
		end
	else
		b.icon:SetTexture(EMPTY_ICON)
		b.icon:SetDesaturated(true)
		b.icon:SetAlpha(0.4)
		b.count:SetText("")
		b.cooldown:Clear()
	end
end

-- Resizes, repositions and re-targets the secure buttons. Protected, so never in combat.
local function Layout()
	if InCombatLockdown() then
		needsLayout = true
		return
	end
	needsLayout = false

	local size, spacing = db.size, db.spacing
	bar:SetScale(db.scale)
	ApplyPosition()

	local shown = 0
	for _, cat in ipairs(CATEGORIES) do
		local b = buttons[cat]
		b.itemID = slots[cat]
		b.spellID = (cat == "healthstone" and not b.itemID) and createSpell or nil
		local visible = db.show[cat] and (b.itemID or b.spellID or not db.hideEmpty)
		if visible then
			local offset = shown * (size + spacing)
			b:ClearAllPoints()
			if db.direction == "RTL" then
				b:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -offset, 0)
			else
				b:SetPoint("TOPLEFT", bar, "TOPLEFT", offset, 0)
			end
			b:SetSize(size, size)
			local border = b:GetNormalTexture()
			border:ClearAllPoints()
			border:SetPoint("CENTER", 0, -size / 36)
			border:SetSize(size * 64 / 36, size * 64 / 36)
			if b.spellID then
				b:SetAttribute("type", "spell")
				b:SetAttribute("spell", b.spellID)
				b:SetAttribute("item", nil)
			elseif cat == "bandage" then
				-- bandage a friendly target, otherwise yourself
				b:SetAttribute("type", "macro")
				b:SetAttribute("macrotext", b.itemID and ("/use [@target,help,nodead][@player] item:" .. b.itemID) or nil)
			else
				b:SetAttribute("type", "item")
				b:SetAttribute("spell", nil)
				b:SetAttribute("item", b.itemID and ("item:" .. b.itemID) or nil)
			end
			b:Show()
			shown = shown + 1
		else
			b:Hide()
			b:SetAttribute("item", nil)
			b:SetAttribute("macrotext", nil)
		end
		UpdateButton(b)
	end

	local n = math.max(shown, 1)
	bar:SetSize(n * size + (n - 1) * spacing, size)
	bar.overlay:SetShown(Movable())
	if not Movable() and selected then ns.SetSelected(false) end
	bar:SetShown(shown > 0 or Movable())
end

local retries = 0
local function Refresh()
	needsRetry = false
	Scan()
	Layout()
	if needsRetry and retries < 15 then
		retries = retries + 1
		C_Timer.After(1, ns.Refresh)
	elseif not needsRetry then
		retries = 0
	end
end

local pending
function ns.Refresh()
	if not db then return end
	if pending then return end
	pending = true
	C_Timer.After(0.1, function()
		pending = nil
		Refresh()
	end)
end

-- Settings changes: re-layout only, items stay the same
function ns.ApplySettings()
	if db then Layout() end
end

function ns.GetDB() return db end

-- Switches the growth direction without moving the bar on screen
function ns.SetDirection(dir)
	if db.direction == dir then return end
	if InCombatLockdown() then
		print("Consumable Bar: can't change direction in combat.")
		return
	end
	db.direction = dir
	CapturePosition()
	Layout()
end

function ns.ResetPosition()
	db.pos = { DEFAULTS.pos[1], DEFAULTS.pos[2] }
	if bar then ApplyPosition() end
end

function ns.SetLocked(locked)
	db.locked = locked and true or false
	Layout()
end

local function UpdateCooldowns()
	for _, cat in ipairs(CATEGORIES) do
		local b = buttons[cat]
		if b:IsShown() then UpdateButton(b) end
	end
end

-- Edit Mode style highlight: blue when available, gold when selected (opens the settings dialog)
local selected, ignoreClear = false, false

function ns.SetSelected(sel)
	selected = sel and true or false
	local o = bar.overlay
	local r, g, b = 0.4, 0.7, 1
	if selected then r, g, b = 1, 0.82, 0 end
	o.fill:SetColorTexture(0.25, 0.55, 1, selected and 0.45 or 0.3)
	for _, e in ipairs(o.edges) do e:SetColorTexture(r, g, b, 1) end
	if selected then
		if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
			ignoreClear = true
			pcall(EditModeManagerFrame.ClearSelectedSystem, EditModeManagerFrame)
			ignoreClear = false
		end
		if ns.ShowEditDialog then ns.ShowEditDialog(bar) end
	elseif ns.HideEditDialog then
		ns.HideEditDialog()
	end
end

local function Build()
	bar = CreateFrame("Frame", "ConsumableBarFrame", UIParent)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:SetFrameStrata("MEDIUM")

	-- Covers the buttons while the bar is movable so dragging never uses an item
	local o = CreateFrame("Frame", nil, bar)
	o:SetPoint("TOPLEFT", -3, 3)
	o:SetPoint("BOTTOMRIGHT", 3, -3)
	o:SetFrameLevel(bar:GetFrameLevel() + 20)
	o:EnableMouse(true)
	o:RegisterForDrag("LeftButton")
	o:Hide()
	o.fill = o:CreateTexture(nil, "OVERLAY")
	o.fill:SetAllPoints()
	o.edges = {}
	for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local e = o:CreateTexture(nil, "OVERLAY")
		e:SetPoint(p[1])
		e:SetPoint(p[2])
		if p[3] then e:SetHeight(2) else e:SetWidth(2) end
		o.edges[i] = e
	end
	local label = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	label:SetText("Consumable Bar")
	o:SetScript("OnMouseDown", function() ns.SetSelected(true) end)
	o:SetScript("OnDragStart", function()
		ns.SetSelected(true)
		if not InCombatLockdown() then bar:StartMoving() end
	end)
	o:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		if not InCombatLockdown() then SavePosition() end
	end)
	bar.overlay = o
	ns.SetSelected(false)

	for _, cat in ipairs(CATEGORIES) do buttons[cat] = CreateButton(cat) end
	ApplyPosition()

	-- Show the drag overlay whenever the game's Edit Mode is open
	if EditModeManagerFrame then
		local function sync(active)
			editMode = active
			Layout()
		end
		hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() sync(true) end)
		hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() sync(false) end)
		if EditModeManagerFrame.ClearSelectedSystem then
			-- another Edit Mode element was picked
			hooksecurefunc(EditModeManagerFrame, "ClearSelectedSystem", function()
				if selected and not ignoreClear then ns.SetSelected(false) end
			end)
		end
		if EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then editMode = true end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		ConsumableBarDB = ConsumableBarDB or {}
		db = ConsumableBarDB
		CopyDefaults(db, DEFAULTS)
		events:UnregisterEvent("ADDON_LOADED")
		Build()
		-- pcall: an event this client doesn't know must not stop the rest registering
		for _, e in ipairs({
			"PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED",
			"GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED",
			-- any way an item can arrive, leave or move
			"BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_PUSH", "BAG_NEW_ITEMS_UPDATED",
			"UNIT_INVENTORY_CHANGED", "ITEM_LOCK_CHANGED",
		}) do
			pcall(events.RegisterEvent, events, e)
		end
		if ns.BuildOptions then ns.BuildOptions() end
	elseif event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then
		return
	elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
		UpdateCooldowns()
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.Refresh()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		-- only matters while we are waiting on item data
		if needsRetry then ns.Refresh() end
	else
		if event == "PLAYER_ENTERING_WORLD" then
			-- bags and item data can still be filling in right after login
			C_Timer.After(3, ns.Refresh)
		end
		ns.Refresh()
	end
end)

function ns.Debug()
	local function p(...) print("|cff33ff99CBar:|r", ...) end
	p("retry pending:", tostring(needsRetry), "retries:", retries, "level:", UnitLevel("player"))
	for _, cat in ipairs(CATEGORIES) do
		p(cat, "->", tostring(slots[cat]), cat == "healthstone" and ("spell " .. tostring(createSpell)) or "")
	end
	local seen = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (NumSlots(bag) or 0) do
			local id = SlotItemID(bag, slot)
			if id and not seen[id] then
				seen[id] = true
				local _, _, _, _, _, class, sub = GetItemInfoInstant(id)
				if class == CLASS_CONSUMABLE or HEALTHSTONE_RANK[id] or class == nil then
					local a = analysis[id]
					local r = a == nil and "NOT ANALYSED" or (a == false and "rejected" or
						string.format("food=%s water=%s bandage=%s hp=%s mp=%s conj=%s wf=%s", tostring(a.food), tostring(a.water),
							tostring(a.bandage), tostring(a.hp), tostring(a.mp), tostring(a.conjured), tostring(a.wellFed)))
					local name, _, _, _, minLevel = GetItemInfo(id)
					p(id, name or "(name not loaded)", "class", tostring(class), "sub", tostring(sub), "minLvl", tostring(minLevel), r, "misses", misses[id] or 0)
				end
			end
		end
	end
end

SLASH_CONSUMABLEBAR1 = "/cbar"
SLASH_CONSUMABLEBAR2 = "/consumablebar"
SlashCmdList.CONSUMABLEBAR = function(input)
	if not db then return end
	input = (input or ""):lower():match("^%s*(.-)%s*$")
	if input == "lock" then
		ns.SetLocked(true)
	elseif input == "unlock" then
		ns.SetLocked(false)
	elseif input == "debug" then
		ns.Debug()
	elseif input == "reset" then
		ns.ResetPosition()
	elseif ns.OpenOptions then
		ns.OpenOptions()
	end
end
