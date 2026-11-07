local addonName, ns = ...
local L = ns.L

local W, H, PAD = 500, 580, 14
local HEADER_H, FOOTER_H = 58, 34
local ITEM_H, ENTRANCE_H, HEADER_ROW_H, BOSS_H = 40, 34, 32, 24
local FONT = "Fonts\\FRIZQT__.TTF"
local MAX_RETRIES = 6

local C = {
	bg = { 0.047, 0.051, 0.063, 0.97 },
	panel = { 0.075, 0.08, 0.098, 1 },
	border = { 0.18, 0.19, 0.23, 1 },
	accent = { 0.45, 0.9, 0.6 },
	text = { 0.93, 0.94, 0.96 },
	dim = { 0.56, 0.59, 0.65 },
	faint = { 0.3, 0.32, 0.38 },
	hover = { 0.45, 0.9, 0.6, 0.07 },
	line = { 0.2, 0.21, 0.26 },
}
local KIND = {
	mount = { label = L.Mount, color = { 0.3, 0.85, 0.95 } },
	pet = { label = L.Pet, color = { 0.4, 0.9, 0.5 } },
	wild = { label = L.Wild, color = { 0.75, 0.9, 0.4 } },
	toy = { label = L.Toy, color = { 0.95, 0.5, 0.75 } },
	appearance = { label = L.Appearance, color = { 0.72, 0.48, 1 } },
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
	title = Font("TreasureTrailFontTitle", 17, C.text),
	text = Font("TreasureTrailFontText", 12, C.text),
	small = Font("TreasureTrailFontSmall", 10, C.dim),
	header = Font("TreasureTrailFontHeader", 12, C.accent),
	pill = Font("TreasureTrailFontPill", 11, C.text),
}

local function Text(parent, font)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(font)
	fs:SetWordWrap(false)
	return fs
end

local function Hex(c) return format("ff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

local function Backdrop(frame, bg, border)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	frame:SetBackdropColor(unpack(bg))
	frame:SetBackdropBorderColor(unpack(border))
end

local function FlatButton(parent, label, height)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetHeight(height or 22)
	Backdrop(b, C.panel, C.border)
	b.text = Text(b, F.small)
	b.text:SetPoint("CENTER")
	function b:SetLabel(text)
		self.text:SetText(text)
		self:SetWidth(self.text:GetUnboundedStringWidth() + 18)
	end
	function b:SetActive(active)
		self.active = active
		self:SetBackdropColor(unpack(active and { 0.45, 0.9, 0.6, 0.16 } or C.panel))
		self:SetBackdropBorderColor(unpack(active and C.accent or C.border))
		self.text:SetTextColor(unpack(active and C.accent or C.dim))
	end
	b:SetScript("OnEnter", function(self) if not self.active then self.text:SetTextColor(unpack(C.text)) end end)
	b:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
	b:SetLabel(label)
	b:SetActive(false)
	return b
end

local frame, pill
local browse -- { id = journalInstanceID, difficultyID = n, result = ScanInstance result }

-- Actions ------------------------------------------------------------------------------

local function OpenCollections(tab)
	if InCombatLockdown() then return false end
	if not CollectionsJournal then C_AddOns.LoadAddOn("Blizzard_Collections") end
	if not CollectionsJournal then return false end
	if CollectionsJournal:IsShown() then
		CollectionsJournal_SetTab(CollectionsJournal, tab)
	else
		ToggleCollectionsJournal(tab)
	end
	return true
end

local function ItemLink(item)
	if item.link then return item.link end
	if item.spellID then return C_Spell.GetSpellLink(item.spellID) end
end

local function OnItemClick(row)
	local d = row.data
	local item = d.item
	if d.entrance then
		browse = { id = d.entrance.journalInstanceID }
		ns.Refresh()
		ns.Rescan(0)
		return
	end
	if IsModifiedClick("CHATLINK") then
		local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
		local link = ItemLink(item)
		if insert and link then insert(link) end
	elseif IsModifiedClick("DRESSUP") or item.kind == "appearance" then
		if item.link and DressUpItemLink then
			DressUpItemLink(item.link)
		elseif item.kind == "mount" and DressUpMount then
			DressUpMount(item.mountID or item.id)
		end
	elseif item.kind == "mount" then
		if OpenCollections(1) and MountJournal_SelectByMountID then
			MountJournal_SelectByMountID(item.mountID or item.id)
		end
	elseif item.kind == "pet" then
		if OpenCollections(2) and PetJournal_SelectSpecies and PetJournal then
			PetJournal_SelectSpecies(PetJournal, item.speciesID or item.id)
		end
	elseif item.kind == "toy" then
		OpenCollections(3)
	end
end

local function ShowItemTooltip(row)
	local d = row.data
	local tt = GameTooltip
	tt:SetOwner(row, "ANCHOR_NONE")
	tt:SetPoint("TOPLEFT", row, "TOPRIGHT", 4, 0)
	if d.entrance then
		tt:SetText(d.entrance.name, 1, 1, 1)
		if d.entrance.description and d.entrance.description ~= "" then
			tt:AddLine(d.entrance.description, 0.85, 0.85, 0.85, true)
		end
		tt:AddLine(L.EntranceMissing, unpack(C.accent))
		tt:Show()
		return
	end
	local item = d.item
	if item.link then
		tt:SetHyperlink(item.link)
	elseif item.kind == "mount" and item.spellID then
		tt:SetMountBySpellID(item.spellID)
	else
		tt:SetText(item.name, 1, 1, 1)
	end
	if item.source then
		tt:AddLine(" ")
		for line in item.source:gmatch("[^\n]+") do
			tt:AddLine(line, 0.85, 0.85, 0.85, true)
		end
	end
	tt:AddLine(" ")
	tt:AddLine(L.Hints, unpack(C.dim))
	tt:Show()
end

-- Rows ------------------------------------------------------------------------------------
-- The list pools frames by type, so one initializer per frame type handles every
-- kind of row that type is used for.

local function InitFrameRow(row, data)
	if not row.text then
		row.text = Text(row, F.header)
		row.count = Text(row, F.small)
		row.rule = row:CreateTexture(nil, "ARTWORK")
		row.rule:SetHeight(1)
		row.rule:SetColorTexture(unpack(C.line))
	end
	row.text:ClearAllPoints()
	row.count:ClearAllPoints()
	row.rule:ClearAllPoints()
	if data.header then
		row.text:SetFontObject(F.header)
		row.text:SetPoint("BOTTOMLEFT", 14, 7)
		row.text:SetText(data.header)
		row.count:SetPoint("LEFT", row.text, "RIGHT", 8, 0)
		row.count:SetText(data.count and data.count > 0 and data.count or "")
		-- Placed from measured widths: anchoring to the font strings' edges
		-- left the rule missing on some recycled rows.
		local x = 14 + row.text:GetUnboundedStringWidth() + 8 + row.count:GetUnboundedStringWidth() + 10
		row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 13)
		row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -12, 13)
		row.rule:Show()
	else -- boss
		row.text:SetFontObject(F.text)
		row.text:SetPoint("LEFT", 22, 0)
		row.text:SetText(data.boss)
		row.text:SetTextColor(unpack(data.killed and C.dim or C.text))
		row.count:SetPoint("LEFT", row.text, "RIGHT", 8, 0)
		row.count:SetText(data.killed and ("|cff59e68a" .. L.Killed .. "|r") or "")
		row.rule:Hide()
	end
end

local function InitButtonRow(row, data)
	if not row.built then
		row.hl = row:CreateTexture(nil, "BACKGROUND")
		row.hl:SetAllPoints()
		row.hl:SetColorTexture(unpack(C.hover))
		row.hl:Hide()
		row.iconBorder = row:CreateTexture(nil, "ARTWORK")
		row.iconBorder:SetSize(28, 28)
		row.iconBorder:SetPoint("LEFT", 16, 0)
		row.icon = row:CreateTexture(nil, "OVERLAY")
		row.icon:SetPoint("TOPLEFT", row.iconBorder, 1, -1)
		row.icon:SetPoint("BOTTOMRIGHT", row.iconBorder, -1, 1)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.name = Text(row, F.text)
		row.name:SetJustifyH("LEFT")
		row.sub = Text(row, F.small)
		row.sub:SetJustifyH("LEFT")
		row.tag = Text(row, F.small)
		row.tag:SetPoint("RIGHT", -14, 0)
		row:RegisterForClicks("LeftButtonUp")
		row:SetScript("OnEnter", function(self)
			self.hl:Show()
			ShowItemTooltip(self)
		end)
		row:SetScript("OnLeave", function(self)
			self.hl:Hide()
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", OnItemClick)
		row.built = true
	end
	row.data = data
	row.name:ClearAllPoints()
	row.sub:ClearAllPoints()

	if data.entrance then
		row.iconBorder:SetPoint("LEFT", 16, 0)
		row.iconBorder:SetColorTexture(unpack(C.border))
		row.icon:SetAtlas(data.entrance.atlasName or "Dungeon")
		row.name:SetPoint("LEFT", row.iconBorder, "RIGHT", 10, 0)
		row.name:SetPoint("RIGHT", -190, 0)
		row.name:SetText(data.entrance.name)
		row.sub:SetText("")
		row.tag:SetText("|c" .. Hex(C.accent) .. L.EntranceMissing .. "|r")
		return
	end

	local item = data.item
	local kind = KIND[item.kind == "pet" and item.wild and "wild" or item.kind] or KIND.appearance
	row.iconBorder:SetColorTexture(kind.color[1], kind.color[2], kind.color[3], 0.75)
	row.icon:SetTexture(item.icon or 134400)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local x = data.indent and 22 or 0
	row.iconBorder:SetPoint("LEFT", 16 + x, 0)
	row.name:SetPoint("LEFT", row.iconBorder, "RIGHT", 10, 7)
	row.name:SetPoint("RIGHT", -96, 7)
	row.sub:SetPoint("LEFT", row.iconBorder, "RIGHT", 10, -8)
	row.sub:SetPoint("RIGHT", -96, -8)

	local name = item.name or "?"
	if item.link then
		local quality = C_Item.GetItemQualityByID(item.link)
		local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		if color and color.hex then name = color.hex .. name .. "|r" end
	end
	row.name:SetText(name)
	if item.source then
		row.sub:SetText((item.source:gsub("\n", "  ·  ")))
	else
		row.sub:SetText(item.slot or "")
	end
	row.tag:SetText("|c" .. Hex(kind.color) .. kind.label .. "|r")
end

-- List ----------------------------------------------------------------------------------------

local function AddInstance(list, inst)
	local difficulty = inst.difficultyID and GetDifficultyInfo(inst.difficultyID)
	local header = difficulty and difficulty ~= "" and L.InstanceLoot:format(inst.name or "?", difficulty) or (inst.name or "?")
	list[#list + 1] = { header = header, count = inst.count }
	for _, boss in ipairs(inst.bosses) do
		if #boss.items > 0 then
			list[#list + 1] = { boss = boss.name, killed = boss.killed }
			for _, item in ipairs(boss.items) do
				list[#list + 1] = { item = item, indent = true }
			end
		end
	end
end

local function AddSection(list, title, items)
	if #items == 0 then return end
	list[#list + 1] = { header = title, count = #items }
	for _, item in ipairs(items) do list[#list + 1] = { item = item } end
end

local function BuildList()
	local list, state = {}, ns.state
	if browse then
		if browse.result then AddInstance(list, browse.result) end
		return list
	end
	if not state then return list end
	if state.instance then AddInstance(list, state.instance) end
	AddSection(list, L.Mounts, state.mounts)
	AddSection(list, L.Pets, state.pets)
	AddSection(list, L.WildPets, state.wild)
	if state.entrances and #state.entrances > 0 then
		list[#list + 1] = { header = L.Entrances, count = #state.entrances }
		for _, e in ipairs(state.entrances) do list[#list + 1] = { entrance = e } end
	end
	return list
end

local function UpdateDifficulties(inst)
	local chips = frame.chips
	for _, chip in ipairs(chips) do chip:Hide() end
	if not (browse and inst and inst.difficulties) then return end
	local prev
	for i, d in ipairs(inst.difficulties) do
		local chip = chips[i]
		if not chip then
			chip = FlatButton(frame.tools, "")
			chip:SetScript("OnClick", function(self)
				browse.difficultyID = self.difficultyID
				browse.result = nil
				ns.Rescan()
			end)
			chips[i] = chip
		end
		chip.difficultyID = d
		chip:SetLabel(GetDifficultyInfo(d) or tostring(d))
		chip:SetActive(d == inst.difficultyID)
		chip:ClearAllPoints()
		if prev then chip:SetPoint("LEFT", prev, "RIGHT", 5, 0) else chip:SetPoint("LEFT", 12, 0) end
		chip:Show()
		prev = chip
	end
end

function ns.Refresh()
	if not frame or not frame:IsShown() then return end
	local state = ns.state
	local list = BuildList()
	frame.scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)

	local inst = browse and browse.result
	frame.back:SetShown(browse ~= nil)
	frame.tools:SetShown(browse ~= nil)
	frame.scrollBox:SetPoint("TOPLEFT", 1, -(HEADER_H + (browse and 34 or 0)))
	UpdateDifficulties(inst)

	local status
	if browse then
		frame.title:SetText(inst and inst.name or L.Title)
		frame.subtitle:SetText(inst and L.Missing:format(inst.count) or "")
		status = browse.status
	elseif state then
		frame.title:SetText(L.Title .. "  |cff8f96a6·|r  " .. (state.zoneName or ""))
		frame.subtitle:SetText(state.noData and L.NoDataShort or L.Missing:format(state.total))
		status = state.instanceStatus or (state.zonePending and "pending")
	else
		frame.title:SetText(L.Title)
		frame.subtitle:SetText(L.Scanning)
	end

	local message
	if status == "busy" then
		message = L.Busy
	elseif #list == 0 then
		message = not state and L.Scanning or (state.noData and not browse) and L.NoData or L.NothingMissing
	end
	frame.empty:SetText(message or "")
	frame.empty:SetShown(message ~= nil)
	frame.loading:SetShown(status == "pending")
	frame.pillCheck:SetChecked(ns.db.pill)
end

local function CreateWindow()
	local f = CreateFrame("Frame", "TreasureTrailFrame", UIParent, "BackdropTemplate")
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
	Backdrop(f, C.bg, C.border)
	if ns.db.point then
		local p = ns.db.point
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint("RIGHT", -260, 0)
	end
	tinsert(UISpecialFrames, "TreasureTrailFrame")

	local glow = f:CreateTexture(nil, "BORDER")
	glow:SetPoint("TOPLEFT", 1, -1)
	glow:SetPoint("TOPRIGHT", -1, -1)
	glow:SetHeight(HEADER_H)
	glow:SetColorTexture(1, 1, 1, 1)
	glow:SetGradient("VERTICAL", CreateColor(0.45, 0.9, 0.6, 0), CreateColor(0.45, 0.9, 0.6, 0.08))
	local edge = f:CreateTexture(nil, "ARTWORK")
	edge:SetPoint("TOPLEFT", 1, -1)
	edge:SetPoint("TOPRIGHT", -1, -1)
	edge:SetHeight(2)
	edge:SetColorTexture(0.45, 0.9, 0.6, 0.9)

	f.back = FlatButton(f, L.Back)
	f.back:SetPoint("TOPLEFT", PAD, -18)
	f.back:SetScript("OnClick", function()
		browse = nil
		ns.Refresh()
	end)

	f.title = Text(f, F.title)
	f.title:SetPoint("TOPLEFT", PAD + 2, -16)
	f.title:SetPoint("RIGHT", -40, 0)
	f.title:SetJustifyH("LEFT")
	f.subtitle = Text(f, F.small)
	f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
	f.back:HookScript("OnShow", function()
		f.title:SetPoint("TOPLEFT", f.back, "TOPRIGHT", 10, 2)
	end)
	f.back:HookScript("OnHide", function()
		f.title:SetPoint("TOPLEFT", PAD + 2, -16)
	end)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	f.tools = CreateFrame("Frame", nil, f)
	f.tools:SetPoint("TOPLEFT", 1, -HEADER_H)
	f.tools:SetPoint("TOPRIGHT", -1, -HEADER_H)
	f.tools:SetHeight(34)
	f.chips = {}

	local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", 1, -HEADER_H)
	scrollBox:SetPoint("BOTTOMRIGHT", -14, FOOTER_H + 4)
	local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, -2)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 2)
	local view = CreateScrollBoxListLinearView()
	view:SetElementFactory(function(factory, data)
		if data.header or data.boss then
			factory("Frame", InitFrameRow)
		else
			factory("Button", InitButtonRow)
		end
	end)
	view:SetElementExtentCalculator(function(_, data)
		if data.header then return HEADER_ROW_H end
		if data.boss then return BOSS_H end
		if data.entrance then return ENTRANCE_H end
		return ITEM_H
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar)
	f.scrollBox = scrollBox

	f.empty = Text(f, F.text)
	f.empty:SetPoint("CENTER", scrollBox, "CENTER")
	f.empty:SetWidth(W - 60)
	f.empty:SetWordWrap(true)
	f.empty:SetTextColor(unpack(C.dim))

	local footer = CreateFrame("Frame", nil, f, "BackdropTemplate")
	footer:SetPoint("BOTTOMLEFT", 1, 1)
	footer:SetPoint("BOTTOMRIGHT", -1, 1)
	footer:SetHeight(FOOTER_H - 1)
	footer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	footer:SetBackdropColor(unpack(C.panel))
	local check = CreateFrame("CheckButton", nil, footer, "UICheckButtonTemplate")
	check:SetSize(22, 22)
	check:SetPoint("LEFT", PAD - 4, 0)
	check:SetScript("OnClick", function(self)
		ns.db.pill = self:GetChecked()
		ns.UpdatePill()
	end)
	local checkLabel = Text(footer, F.small)
	checkLabel:SetPoint("LEFT", check, "RIGHT", 2, 0)
	checkLabel:SetText(L.ShowPill)
	f.pillCheck = check
	f.loading = Text(footer, F.small)
	f.loading:SetPoint("RIGHT", -PAD, 0)
	f.loading:SetText(L.Loading)
	f.loading:SetTextColor(unpack(C.accent))

	f:SetScript("OnShow", function() ns.Rescan() end)
	f:Hide()
	return f
end

function ns.Toggle()
	if not ns.db then return end
	frame = frame or CreateWindow()
	frame:SetShown(not frame:IsShown())
end

-- The pill: a small summary under the minimap ---------------------------------------------------

function ns.UpdatePill()
	if not pill then return end
	local state = ns.state
	if not ns.db.pill or not state or state.total == 0 then
		pill:Hide()
		return
	end
	local parts = {}
	if #state.mounts > 0 then parts[#parts + 1] = L.PillMounts:format(#state.mounts) end
	local pets = #state.pets + #state.wild
	if pets > 0 then parts[#parts + 1] = L.PillPets:format(pets) end
	if state.instance and state.instance.count > 0 then parts[#parts + 1] = L.PillLoot:format(state.instance.count) end
	pill.text:SetText("|c" .. Hex(C.accent) .. L.Title .. "|r  " .. table.concat(parts, "  ·  "))
	pill:SetWidth(pill.text:GetUnboundedStringWidth() + 20)
	pill:Show()
end

local function CreatePill()
	local p = CreateFrame("Button", "TreasureTrailPill", UIParent, "BackdropTemplate")
	p:SetHeight(22)
	p:SetFrameStrata("MEDIUM")
	Backdrop(p, { 0.047, 0.051, 0.063, 0.88 }, C.border)
	p.text = Text(p, F.pill)
	p.text:SetPoint("CENTER")
	p:SetClampedToScreen(true)
	p:SetMovable(true)
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
	p:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.db.pillPoint = { point, relPoint, x, y }
	end)
	p:SetScript("OnClick", ns.Toggle)
	p:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(unpack(C.accent))
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L.Title, unpack(C.accent))
		GameTooltip:AddLine(L.Missing:format(ns.state and ns.state.total or 0), 1, 1, 1)
		GameTooltip:AddLine(L.PillDrag, unpack(C.dim))
		GameTooltip:Show()
	end)
	p:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(unpack(C.border))
		GameTooltip:Hide()
	end)
	if ns.db.pillPoint then
		local pt = ns.db.pillPoint
		p:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
	else
		p:SetPoint("TOP", Minimap, "BOTTOM", 0, -34)
	end
	p:Hide()
	return p
end

-- Scanning ----------------------------------------------------------------------------------------

local scanTimer, retries, deferred = nil, 0, false

local function DoScan()
	scanTimer = nil
	if InCombatLockdown() then
		deferred = true
		return
	end
	ns.BuildIndex(function()
		ns.state = ns.Scan()
		local pending = ns.state.instanceStatus == "pending" or ns.state.zonePending
		if browse then
			local result, status = ns.ScanInstance(browse.id, browse.difficultyID)
			browse.result = result or browse.result
			browse.status = status
			if result then browse.difficultyID = result.difficultyID end
			pending = pending or status == "pending"
		end
		-- Item data arrives a moment after it is first asked for; some never
		-- does, so stop waiting (and stop saying so) after a few tries.
		if pending and retries < MAX_RETRIES then
			retries = retries + 1
			ns.Rescan(1.5)
		else
			retries = 0
			if ns.state.instanceStatus == "pending" then ns.state.instanceStatus = nil end
			ns.state.zonePending = nil
			if browse and browse.status == "pending" then browse.status = nil end
		end
		ns.UpdatePill()
		ns.Refresh()
	end)
end

function ns.Rescan(delay)
	if not ns.db then return end
	if scanTimer then scanTimer:Cancel() end
	scanTimer = C_Timer.NewTimer(delay or 0.3, DoScan)
end

local RESCAN_EVENTS = {
	ZONE_CHANGED_NEW_AREA = 1,
	NEW_MOUNT_ADDED = 2,
	NEW_PET_ADDED = 2,
	NEW_TOY_ADDED = 2,
	TRANSMOG_COLLECTION_UPDATED = 2,
	UPDATE_INSTANCE_INFO = 2,
	PLAYER_DIFFICULTY_CHANGED = 1,
	BOSS_KILL = 3,
}

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
for event in pairs(RESCAN_EVENTS) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then return end
		TreasureTrailDB = TreasureTrailDB or {}
		if TreasureTrailDB.pill == nil then TreasureTrailDB.pill = true end
		ns.db = TreasureTrailDB
		pill = CreatePill()
	elseif event == "PLAYER_ENTERING_WORLD" then
		browse = nil
		retries = 0
		ns.Rescan(3)
		if arg1 then print("|cff73e699" .. L.Title .. "|r " .. L.Loaded) end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if deferred then
			deferred = false
			ns.Rescan(1)
		end
	else
		ns.Rescan(RESCAN_EVENTS[event])
	end
end)

SLASH_TREASURETRAIL1 = "/trail"
SLASH_TREASURETRAIL2 = "/treasuretrail"
SLASH_TREASURETRAIL3 = "/rastro"
SlashCmdList.TREASURETRAIL = function() ns.Toggle() end

function TreasureTrail_OnAddonCompartmentClick()
	ns.Toggle()
end

BINDING_HEADER_TREASURETRAIL = L.Title
BINDING_NAME_TREASURETRAIL_TOGGLE = L.Title
function TreasureTrail_Toggle()
	ns.Toggle()
end
