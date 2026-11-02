local _, ns = ...
local L = ns.L

local W, H, SIDE_W, PAD = 840, 580, 186, 14
local HEADER_H, TOOLS_H, FOOTER_H = 58, 40, 36
local ENTRY_H, DAY_H = 44, 32
local FONT = "Fonts\\FRIZQT__.TTF"
local ALL = "all"

local C = {
	bg = { 0.047, 0.051, 0.063, 0.97 },
	panel = { 0.075, 0.08, 0.098, 1 },
	border = { 0.18, 0.19, 0.23, 1 },
	accent = { 1, 0.76, 0.35 },
	text = { 0.93, 0.94, 0.96 },
	dim = { 0.56, 0.59, 0.65 },
	faint = { 0.3, 0.32, 0.38 },
	hover = { 1, 0.76, 0.35, 0.07 },
	line = { 0.2, 0.21, 0.26 },
}

local FILTERS = {
	{ key = "all", label = L.All },
	{ key = "level", label = L.Levels },
	{ key = "achievement", label = L.Achievements },
	{ key = "boss", label = L.Bosses },
	{ key = "loot", label = L.Loot },
	{ key = "collection", label = L.Collection },
	{ key = "renown", label = L.Renown },
	{ key = "zone", label = L.Zones },
}

local function Font(name, size, color)
	local f = CreateFont(name)
	f:SetFont(FONT, size, "")
	f:SetShadowOffset(1, -1)
	f:SetShadowColor(0, 0, 0, 0.85)
	f:SetTextColor(unpack(color))
	return f
end
local F = {
	title = Font("KeepsakeFontTitle", 17, C.text),
	text = Font("KeepsakeFontText", 12, C.text),
	small = Font("KeepsakeFontSmall", 10, C.dim),
	day = Font("KeepsakeFontDay", 12, C.accent),
}

local function Text(parent, font)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(font)
	fs:SetWordWrap(false)
	return fs
end

local function Fill(frame, color)
	local t = frame:CreateTexture(nil, "BACKGROUND")
	t:SetAllPoints()
	t:SetColorTexture(unpack(color))
	return t
end

local function ClassColor(class)
	local c = class and C_ClassColor.GetClassColor(class)
	if c then return c.r, c.g, c.b end
	return unpack(C.text)
end

local function Circle(parent, size, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetSize(size, size)
	t:SetTexture("Interface\\Buttons\\WHITE8x8")
	local mask = parent:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(t)
	t:AddMaskTexture(mask)
	return t
end

-- A flat button in the house style: dark fill, thin border, accent when active.
local function FlatButton(parent, label, width, height)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, height or 22)
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	b.text = Text(b, F.small)
	b.text:SetPoint("CENTER")
	b.text:SetText(label)
	function b:SetActive(active)
		self.active = active
		self:SetBackdropColor(unpack(active and { 1, 0.76, 0.35, 0.16 } or C.panel))
		self:SetBackdropBorderColor(unpack(active and C.accent or C.border))
		self.text:SetTextColor(unpack(active and C.accent or C.dim))
	end
	b:SetScript("OnEnter", function(self)
		if not self.active then self.text:SetTextColor(unpack(C.text)) end
	end)
	b:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
	b:SetActive(false)
	return b
end

-- State ---------------------------------------------------------------------------

local frame
local selected -- character GUID or ALL
local search = ""

local function Matches(e)
	local filter = ns.db.filter or "all"
	if filter ~= "all" and (ns.TYPES[e.type] and ns.TYPES[e.type].group) ~= filter then return false end
	if search ~= "" then
		local hay = ((e.title or "") .. " " .. (e.detail or "") .. " " .. (e.zone or "")):lower()
		hay = hay:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		if not hay:find(search, 1, true) then return false end
	end
	return true
end

local function DayLabel(t)
	local d = date("*t", t)
	local today = date("*t")
	if d.year == today.year and d.yday == today.yday then return L.Today .. " · " .. L.FormatDay(d) end
	local y = date("*t", time() - 86400)
	if d.year == y.year and d.yday == y.yday then return L.Yesterday .. " · " .. L.FormatDay(d) end
	return L.FormatDay(d)
end

local function BuildList()
	local items = {}
	for guid, c in pairs(ns.db.chars) do
		if selected == ALL or guid == selected then
			for _, e in ipairs(c.entries) do
				if Matches(e) then items[#items + 1] = { entry = e, char = c } end
			end
		end
	end
	table.sort(items, function(a, b) return a.entry.t > b.entry.t end)

	local list, lastDay = {}, nil
	for _, it in ipairs(items) do
		local day = date("%Y%m%d", it.entry.t)
		if day ~= lastDay then
			list[#list + 1] = { day = DayLabel(it.entry.t) }
			lastDay = day
		end
		list[#list + 1] = it
	end
	return list, #items
end

-- Timeline rows ---------------------------------------------------------------------

local function InsertLink(link)
	local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
	if insert and link then insert(link) end
end

local function EntryLink(e)
	if e.type == "achievement" and e.id then return GetAchievementLink(e.id) end
	if e.type == "loot" then return e.link end
	if e.type == "mount" and e.spellID then return C_Spell.GetSpellLink(e.spellID) end
	if e.type == "toy" and e.itemID then return select(2, C_Item.GetItemInfo(e.itemID)) end
end

local function ShowEntryTooltip(row)
	local e = row.data.entry
	local tt = GameTooltip
	tt:SetOwner(row, "ANCHOR_NONE")
	tt:SetPoint("TOPLEFT", row, "TOPRIGHT", 4, 0)
	if e.type == "achievement" and e.id then
		tt:SetHyperlink(GetAchievementLink(e.id))
	elseif e.type == "loot" and e.link then
		tt:SetHyperlink(e.link)
	elseif e.type == "mount" and e.spellID then
		tt:SetMountBySpellID(e.spellID)
	elseif e.type == "toy" and e.itemID then
		tt:SetToyByItemID(e.itemID)
	else
		tt:SetText(e.title or "", 1, 1, 1)
		if e.detail then tt:AddLine(e.detail, unpack(C.dim)) end
	end
	tt:AddLine(" ")
	if e.zone and e.zone ~= "" then tt:AddLine(e.zone, unpack(C.accent)) end
	tt:AddLine(e.imported and date("%d/%m/%Y", e.t) or date("%d/%m/%Y %H:%M", e.t), unpack(C.dim))
	if e.shot then tt:AddLine(L.ScreenshotSaved, unpack(C.dim)) end
	tt:Show()
end

local function BuildEntry(row)
	row.hl = row:CreateTexture(nil, "BACKGROUND")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(unpack(C.hover))
	row.hl:Hide()

	row.time = Text(row, F.small)
	row.time:SetPoint("RIGHT", row, "LEFT", 50, 0)
	row.time:SetJustifyH("RIGHT")

	row.line = row:CreateTexture(nil, "BORDER")
	row.line:SetWidth(2)
	row.line:SetPoint("TOP", row, "TOPLEFT", 64, 0)
	row.line:SetPoint("BOTTOM", row, "BOTTOMLEFT", 64, 0)
	row.line:SetColorTexture(unpack(C.line))
	row.dot = Circle(row, 9)
	row.dot:SetPoint("CENTER", row, "LEFT", 64, 0)

	row.iconBorder = row:CreateTexture(nil, "ARTWORK")
	row.iconBorder:SetSize(30, 30)
	row.iconBorder:SetPoint("LEFT", 80, 0)
	row.icon = row:CreateTexture(nil, "OVERLAY")
	row.icon:SetPoint("TOPLEFT", row.iconBorder, 1, -1)
	row.icon:SetPoint("BOTTOMRIGHT", row.iconBorder, -1, 1)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.title = Text(row, F.text)
	row.title:SetPoint("LEFT", row.iconBorder, "RIGHT", 10, 7)
	row.title:SetPoint("RIGHT", row, "RIGHT", -130, 7)
	row.title:SetJustifyH("LEFT")
	row.detail = Text(row, F.small)
	row.detail:SetPoint("LEFT", row.iconBorder, "RIGHT", 10, -8)
	row.detail:SetPoint("RIGHT", row, "RIGHT", -130, -8)
	row.detail:SetJustifyH("LEFT")

	row.who = Text(row, F.small)
	row.who:SetPoint("RIGHT", -12, 0)
	row.who:SetJustifyH("RIGHT")

	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnEnter", function(self)
		self.hl:Show()
		ShowEntryTooltip(self)
	end)
	row:SetScript("OnLeave", function(self)
		self.hl:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		local e = self.data.entry
		if IsModifiedClick("CHATLINK") then
			InsertLink(EntryLink(e))
		elseif e.type == "achievement" and e.id and OpenAchievementFrameToAchievement then
			OpenAchievementFrameToAchievement(e.id)
		elseif e.type == "loot" and e.link and IsModifiedClick("DRESSUP") and DressUpItemLink then
			DressUpItemLink(e.link)
		end
	end)
	row.built = true
end

local function InitEntry(row, data)
	if not row.built then BuildEntry(row) end
	row.data = data
	local e = data.entry
	local kind = ns.TYPES[e.type] or ns.TYPES.start
	row.time:SetText(e.imported and "" or date("%H:%M", e.t))
	row.dot:SetVertexColor(unpack(kind.color))
	row.iconBorder:SetColorTexture(kind.color[1], kind.color[2], kind.color[3], 0.8)
	row.icon:SetTexture(e.icon or kind.icon or 134400)
	row.title:SetText(e.title or "")
	local detail = e.detail or ""
	if e.zone and e.zone ~= "" and e.type ~= "zone" then
		detail = detail ~= "" and (detail .. "  ·  " .. e.zone) or e.zone
	end
	row.detail:SetText(detail)
	if selected == ALL then
		row.who:SetText(data.char.name or "")
		row.who:SetTextColor(ClassColor(data.char.class))
	else
		row.who:SetText("")
	end
end

local function InitDay(row, data)
	if not row.text then
		row.text = Text(row, F.day)
		row.text:SetPoint("BOTTOMLEFT", 16, 6)
		row.rule = row:CreateTexture(nil, "ARTWORK")
		row.rule:SetHeight(1)
		row.rule:SetColorTexture(unpack(C.line))
	end
	row.text:SetText(data.day)
	-- Placed from the measured text width: anchoring to the font string's edge
	-- left the rule missing on some recycled rows.
	local x = 16 + row.text:GetUnboundedStringWidth() + 10
	row.rule:ClearAllPoints()
	row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 12)
	row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -12, 12)
end

-- Window ------------------------------------------------------------------------------

local function UpdateSidebar()
	local chars = {}
	for guid, c in pairs(ns.db.chars) do chars[#chars + 1] = { guid = guid, c = c } end
	table.sort(chars, function(a, b) return (a.c.name or "") < (b.c.name or "") end)

	local buttons = frame.charButtons
	local function Set(i, key, label, count, r, g, b)
		local btn = buttons[i]
		if not btn then
			btn = CreateFrame("Button", nil, frame.sidebar)
			btn:SetSize(SIDE_W - 16, 30)
			btn:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 32)
			btn.bg = Fill(btn, { 1, 1, 1, 0 })
			btn.bar = btn:CreateTexture(nil, "ARTWORK")
			btn.bar:SetPoint("TOPLEFT")
			btn.bar:SetPoint("BOTTOMLEFT")
			btn.bar:SetWidth(2)
			btn.label = Text(btn, F.text)
			btn.label:SetPoint("LEFT", 10, 0)
			btn.label:SetPoint("RIGHT", -34, 0)
			btn.label:SetJustifyH("LEFT")
			btn.count = Text(btn, F.small)
			btn.count:SetPoint("RIGHT", -8, 0)
			btn:SetScript("OnClick", function(self)
				selected = self.key
				ns.Refresh()
			end)
			btn:SetScript("OnEnter", function(self) if selected ~= self.key then self.bg:SetColorTexture(1, 1, 1, 0.04) end end)
			btn:SetScript("OnLeave", function(self) if selected ~= self.key then self.bg:SetColorTexture(1, 1, 1, 0) end end)
			buttons[i] = btn
		end
		btn.key = key
		btn.label:SetText(label)
		btn.label:SetTextColor(r, g, b)
		btn.count:SetText(count)
		local active = selected == key
		btn.bg:SetColorTexture(1, 0.76, 0.35, active and 0.1 or 0)
		btn.bar:SetColorTexture(r, g, b, active and 1 or 0)
		btn:Show()
	end

	local total = 0
	for _, it in ipairs(chars) do total = total + #it.c.entries end
	Set(1, ALL, L.AllCharacters, total, unpack(C.accent))
	for i, it in ipairs(chars) do
		Set(i + 1, it.guid, it.c.name or "?", #it.c.entries, ClassColor(it.c.class))
	end
	for i = #chars + 2, #buttons do buttons[i]:Hide() end
end

function ns.Refresh()
	if not frame or not frame:IsShown() then return end
	if selected ~= ALL and not ns.db.chars[selected] then selected = ALL end

	UpdateSidebar()
	for _, chip in ipairs(frame.chips) do
		chip:SetActive(chip.key == (ns.db.filter or "all"))
	end

	local list, count = BuildList()
	frame.scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)
	frame.empty:SetShown(count == 0)

	if selected == ALL then
		frame.subtitle:SetText(L.Entries:format(count))
	else
		local c = ns.db.chars[selected]
		frame.subtitle:SetText(format("%s · %s · %s", c.name or "?", L.Entries:format(count), L.Since:format(date("%d/%m/%Y", c.created or time()))))
	end

	local c = ns.db.chars[UnitGUID("player")]
	frame.import:SetShown(not (c and c.imported))
	frame.shots:SetChecked(ns.db.screenshots)
end

local function CreateWindow()
	local f = CreateFrame("Frame", "KeepsakeFrame", UIParent, "BackdropTemplate")
	f:SetSize(W, H)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.db.point = { point, relPoint, x, y }
	end)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f:SetBackdropColor(unpack(C.bg))
	f:SetBackdropBorderColor(unpack(C.border))
	if ns.db.point then
		local p = ns.db.point
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint("CENTER")
	end
	tinsert(UISpecialFrames, "KeepsakeFrame")

	local glow = f:CreateTexture(nil, "BORDER")
	glow:SetPoint("TOPLEFT", 1, -1)
	glow:SetPoint("TOPRIGHT", -1, -1)
	glow:SetHeight(HEADER_H)
	glow:SetColorTexture(1, 1, 1, 1)
	glow:SetGradient("VERTICAL", CreateColor(1, 0.76, 0.35, 0), CreateColor(1, 0.76, 0.35, 0.08))
	local edge = f:CreateTexture(nil, "ARTWORK")
	edge:SetPoint("TOPLEFT", 1, -1)
	edge:SetPoint("TOPRIGHT", -1, -1)
	edge:SetHeight(2)
	edge:SetColorTexture(1, 0.76, 0.35, 0.9)

	local title = Text(f, F.title)
	title:SetPoint("TOPLEFT", PAD + 2, -16)
	title:SetText(L.Title)
	f.subtitle = Text(f, F.small)
	f.subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	-- Characters
	local sidebar = CreateFrame("Frame", nil, f)
	sidebar:SetPoint("TOPLEFT", 1, -HEADER_H)
	sidebar:SetPoint("BOTTOMLEFT", 1, FOOTER_H)
	sidebar:SetWidth(SIDE_W)
	Fill(sidebar, C.panel)
	f.sidebar = sidebar
	f.charButtons = {}

	-- Filters and search
	local tools = CreateFrame("Frame", nil, f)
	tools:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
	tools:SetPoint("RIGHT", f, "RIGHT", -1, 0)
	tools:SetHeight(TOOLS_H)
	f.chips = {}
	local x = 12
	for _, flt in ipairs(FILTERS) do
		local chip = FlatButton(tools, flt.label, 10, 22)
		chip:SetWidth(chip.text:GetUnboundedStringWidth() + 18)
		chip:SetPoint("LEFT", x, 0)
		x = x + chip:GetWidth() + 5
		chip.key = flt.key
		chip:SetScript("OnClick", function()
			ns.db.filter = flt.key
			ns.Refresh()
		end)
		f.chips[#f.chips + 1] = chip
	end

	local box = CreateFrame("EditBox", nil, tools, "BackdropTemplate")
	box:SetSize(W - SIDE_W - x - 22, 22)
	box:SetPoint("RIGHT", -12, 0)
	box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	box:SetBackdropColor(unpack(C.panel))
	box:SetBackdropBorderColor(unpack(C.border))
	box:SetFontObject(F.text)
	box:SetTextInsets(8, 8, 0, 0)
	box:SetAutoFocus(false)
	local hint = Text(box, F.small)
	hint:SetPoint("LEFT", 8, 0)
	hint:SetText(L.Search)
	box:SetScript("OnTextChanged", function(self)
		search = strtrim(self:GetText()):lower()
		hint:SetShown(self:GetText() == "")
		ns.Refresh()
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
	box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)

	-- Timeline
	local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 0, 0)
	scrollBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, FOOTER_H + 4)
	local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, -2)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 2)
	local view = CreateScrollBoxListLinearView()
	view:SetElementFactory(function(factory, data)
		if data.day then
			factory("Frame", InitDay)
		else
			factory("Button", InitEntry)
		end
	end)
	view:SetElementExtentCalculator(function(_, data)
		return data.day and DAY_H or ENTRY_H
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar)
	f.scrollBox = scrollBox

	f.empty = Text(f, F.text)
	f.empty:SetPoint("CENTER", scrollBox, "CENTER")
	f.empty:SetTextColor(unpack(C.dim))
	f.empty:SetText(L.Empty)

	-- Footer
	local footer = CreateFrame("Frame", nil, f)
	footer:SetPoint("BOTTOMLEFT", 1, 1)
	footer:SetPoint("BOTTOMRIGHT", -1, 1)
	footer:SetHeight(FOOTER_H - 1)
	Fill(footer, C.panel)

	local shots = CreateFrame("CheckButton", nil, footer, "UICheckButtonTemplate")
	shots:SetSize(22, 22)
	shots:SetPoint("LEFT", PAD - 4, 0)
	shots:SetScript("OnClick", function(self) ns.db.screenshots = self:GetChecked() end)
	local shotsLabel = Text(footer, F.small)
	shotsLabel:SetPoint("LEFT", shots, "RIGHT", 2, 0)
	shotsLabel:SetText(L.Screenshots)
	f.shots = shots

	local import = FlatButton(footer, L.Import, 10, 22)
	import:SetWidth(import.text:GetUnboundedStringWidth() + 24)
	import:SetPoint("RIGHT", -PAD, 0)
	import:SetScript("OnClick", function(self)
		self:Disable()
		ns.ImportAchievements(function(n)
			self.text:SetText(L.Importing:format(n))
		end, function(n)
			print("|cffffc259" .. L.Title .. "|r " .. L.Imported:format(n))
			self.text:SetText(L.Import)
			self:Enable()
		end)
	end)
	f.import = import

	f:SetScript("OnShow", ns.Refresh)
	f:Hide()
	return f
end

function ns.Toggle()
	if not ns.db then return end
	frame = frame or CreateWindow()
	selected = selected or UnitGUID("player")
	frame:SetShown(not frame:IsShown())
end
