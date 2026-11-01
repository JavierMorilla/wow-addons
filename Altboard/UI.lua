local _, ns = ...
local L = ns.L

local ROW_H, MAX_ROWS, PAD = 40, 12, 14
local HEADER_H, COLS_H, FOOTER_H = 60, 24, 34
local FONT, FONT_NUM = "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF"
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"

local C = {
	bg = { 0.047, 0.051, 0.063, 0.97 },
	panel = { 0.075, 0.08, 0.098, 1 },
	border = { 0.18, 0.19, 0.23, 1 },
	accent = { 0.4, 0.8, 1 },
	text = { 0.93, 0.94, 0.96 },
	dim = { 0.56, 0.59, 0.65 },
	faint = { 0.3, 0.32, 0.38 },
	stripe = { 1, 1, 1, 0.022 },
	hover = { 0.4, 0.8, 1, 0.07 },
	pipEmpty = { 0.15, 0.16, 0.2 },
	rested = { 0.36, 0.62, 1 },
	good = { 0.35, 0.9, 0.5 },
	gold = { 1, 0.82, 0.25 },
}
local VAULT_COLORS = {
	Raid = { 1, 0.55, 0.2 },
	Dungeons = { 0.72, 0.48, 1 },
	World = { 0.3, 0.86, 0.55 },
}

local function Hex(c)
	return format("ff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

local function Font(name, path, size, color)
	local f = CreateFont(name)
	f:SetFont(path, size, "")
	f:SetShadowOffset(1, -1)
	f:SetShadowColor(0, 0, 0, 0.85)
	f:SetTextColor(unpack(color or C.text))
	return f
end
local F = {
	title = Font("AltboardFontTitle", FONT, 17, C.text),
	text = Font("AltboardFontText", FONT, 12, C.text),
	small = Font("AltboardFontSmall", FONT, 10, C.dim),
	header = Font("AltboardFontHeader", FONT, 10, C.dim),
	num = Font("AltboardFontNum", FONT_NUM, 15, C.text),
	numSmall = Font("AltboardFontNumSmall", FONT_NUM, 13, C.text),
}

local function Text(parent, font, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFontObject(font)
	fs:SetWordWrap(false)
	return fs
end

local function Backdrop(frame, bg, border)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	frame:SetBackdropColor(unpack(bg))
	frame:SetBackdropBorderColor(unpack(border))
end

-- Formatting ------------------------------------------------------------------

local function Money(copper)
	return BreakUpLargeNumbers(math.floor((copper or 0) / 10000)) .. " " .. GOLD_ICON
end

local function Duration(sec)
	sec = math.max(0, math.floor(sec))
	local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
	if d > 0 then return format("%dd %dh", d, h) end
	if h > 0 then return format("%dh %dm", h, m) end
	return format("%dm", m)
end

local function Ago(rec)
	if rec.guid == ns.currentGUID then
		return "|c" .. Hex(C.good) .. L.Now .. "|r"
	end
	if not rec.lastSeen then return L.Unknown end
	local sec = time() - rec.lastSeen
	if sec < 3600 then return format("%dm", math.max(1, math.floor(sec / 60))) end
	if sec < 86400 then return format("%dh", math.floor(sec / 3600)) end
	return format("%dd", math.floor(sec / 86400))
end

-- Season 3 upgrade tracks: Myth 707+, Hero 694+, Champion 681+, Veteran 668+
local function ItemLevelColor(ilvl)
	if not ilvl then return "ff808080" end
	if ilvl >= 707 then return "ffff8000" end
	if ilvl >= 694 then return "ffa335ee" end
	if ilvl >= 681 then return "ff0070dd" end
	if ilvl >= 668 then return "ff1eff00" end
	return "ffe6e6e6"
end

local function ClassColor(rec)
	local c = rec.class and C_ClassColor.GetClassColor(rec.class)
	if c then return c.r, c.g, c.b end
	return unpack(C.text)
end

local function ScoreText(score)
	score = math.floor(score or 0)
	local color = score > 0 and C_ChallengeMode.GetDungeonScoreRarityColor(score)
	return color and color:WrapTextInColorCode(score) or tostring(score)
end

local function VaultLevelText(key, level)
	if key == "Raid" then
		return GetDifficultyInfo(level) or L.Raid
	elseif key == "Dungeons" then
		return "+" .. level
	end
	return L.Tier:format(level)
end

local function VaultDone(rec)
	if not rec.vault or ns.IsStaleWeek(rec) then return 0 end
	local n = 0
	for _, slots in pairs(rec.vault) do
		for _, s in pairs(slots) do
			if s.progress >= s.threshold then n = n + 1 end
		end
	end
	return n
end

local function Qty(rec, id)
	local c = rec.currencies and rec.currencies[id]
	return c and c.quantity or 0
end

-- Columns ---------------------------------------------------------------------

local COLUMNS = {
	{ key = "name", label = L.Character, width = 214, align = "LEFT", value = function(r) return r.name or "" end },
	{ key = "ilvl", label = L.ItemLevel, width = 62, align = "CENTER", value = function(r) return r.ilvl or 0 end },
	{ key = "gold", label = L.Gold, width = 112, align = "RIGHT", value = function(r) return r.money or 0 end },
	{ key = "vault", label = L.Vault, width = 150, align = "CENTER", value = function(r)
		return (ns.HasPendingReward(r) and 100 or 0) + VaultDone(r)
	end },
	{ key = "key", label = L.Keystone, width = 150, align = "LEFT", value = function(r) return r.score or 0 end },
	{ key = "crests", label = L.Crests, width = 150, align = "CENTER", value = function(r)
		return Qty(r, ns.CRESTS[4]) * 1e6 + Qty(r, ns.CRESTS[3])
	end },
	{ key = "keys", label = L.Keys, width = 56, align = "CENTER", value = function(r) return Qty(r, ns.COFFER_KEYS) end },
	{ key = "rested", label = L.Rested, width = 80, align = "CENTER", value = function(r) return ns.ProjectedRested(r) or -1 end },
	{ key = "seen", label = L.LastSeen, width = 56, align = "RIGHT", value = function(r)
		return r.guid == ns.currentGUID and math.huge or (r.lastSeen or 0)
	end },
}
local TOTAL_W = PAD
for _, col in ipairs(COLUMNS) do
	col.x = TOTAL_W
	TOTAL_W = TOTAL_W + col.width + 8
end
TOTAL_W = TOTAL_W - 8 + PAD + 10 -- room for the scroll bar
local COL = {}
for _, col in ipairs(COLUMNS) do COL[col.key] = col end

-- Tooltip ---------------------------------------------------------------------

local function Section(tt, label)
	tt:AddLine(" ")
	tt:AddLine(label, unpack(C.accent))
end

local function ShowRowTooltip(row)
	local rec = row.rec
	local tt = GameTooltip
	tt:SetOwner(row, "ANCHOR_NONE")
	tt:SetPoint("TOPLEFT", row, "TOPRIGHT", 6, 0)
	tt:ClearLines()

	local r, g, b = ClassColor(rec)
	tt:AddDoubleLine(rec.name or "?", rec.realm or "", r, g, b, unpack(C.dim))
	tt:AddLine(format("%s %s · %s", rec.specName or "", rec.className or "", L.Level:format(rec.level or 0)), unpack(C.dim))
	if rec.ilvl then
		tt:AddDoubleLine(STAT_AVERAGE_ITEM_LEVEL or "Item level",
			format("|c%s%.1f|r  |cff808080(%.1f)|r", ItemLevelColor(rec.ilvl), rec.ilvl, rec.ilvlOverall or rec.ilvl), 0.85, 0.85, 0.85)
	end

	Section(tt, L.Vault)
	local stale = ns.IsStaleWeek(rec)
	if ns.HasPendingReward(rec) then
		tt:AddLine(L.RewardPendingLong, unpack(C.gold))
	end
	if stale then
		tt:AddLine(L.OutOfDate, unpack(C.dim))
	elseif rec.vault then
		for _, vt in ipairs(ns.VAULT_TYPES) do
			local parts, nextGoal = {}, nil
			for i = 1, 3 do
				local s = rec.vault[vt.key] and rec.vault[vt.key][i]
				if s then
					if s.progress >= s.threshold then
						local label = VaultLevelText(vt.key, s.level)
						if s.ilvl then label = label .. " " .. L.ItemLevelShort:format(s.ilvl) end
						parts[#parts + 1] = "|c" .. Hex(VAULT_COLORS[vt.key]) .. label .. "|r"
					elseif not nextGoal then
						nextGoal = format("%d/%d", s.progress, s.threshold)
					end
				end
			end
			if nextGoal then parts[#parts + 1] = "|cff808080" .. nextGoal .. "|r" end
			tt:AddDoubleLine(L[vt.key], table.concat(parts, "  "), 0.85, 0.85, 0.85)
		end
	end

	Section(tt, L.Keystone)
	if rec.key then
		local keyText = format("+%d %s", rec.key.level or 0, rec.key.name or "")
		if stale then keyText = keyText .. " |cff808080(" .. L.StaleWeek .. ")|r" end
		tt:AddLine(keyText, 1, 1, 1)
	else
		tt:AddLine(L.NoKey, unpack(C.dim))
	end
	tt:AddDoubleLine(L.Score, ScoreText(rec.score), 0.85, 0.85, 0.85)

	if rec.currencies then
		Section(tt, L.Currencies)
		for _, id in ipairs(ns.TRACKED_CURRENCIES) do
			local c = rec.currencies[id]
			if c then
				local detail = ""
				local week, weekMax = ns.CurrencyWeek(rec, id)
				if weekMax and weekMax > 0 then
					detail = format("  |cff808080%d/%d %s|r", week, weekMax, L.ThisWeek)
				elseif c.seasonal and c.max and c.max > 0 then
					detail = format("  |cff808080%d/%d %s|r", c.earned or 0, c.max, L.SeasonCap)
				end
				tt:AddDoubleLine(format("|T%d:14:14|t %s", c.icon or 134400, c.name), BreakUpLargeNumbers(c.quantity) .. detail,
					0.85, 0.85, 0.85, 1, 1, 1)
			end
		end
	end

	local lockouts = ns.ActiveLockouts(rec)
	if #lockouts > 0 then
		Section(tt, L.Lockouts)
		for _, l in ipairs(lockouts) do
			local done = l.progress >= l.total
			tt:AddDoubleLine(format("%s |cff808080(%s)|r", l.name, l.difficulty or ""),
				format("%d/%d  |cff808080%s|r", l.progress, l.total, Duration(l.resetAt - time())),
				0.85, 0.85, 0.85, done and 0.35 or 1, done and 0.9 or 1, done and 0.5 or 1)
		end
	end

	if rec.professions and #rec.professions > 0 then
		Section(tt, L.Professions)
		for _, p in ipairs(rec.professions) do
			tt:AddDoubleLine(format("|T%d:14:14|t %s", p.icon or 134400, p.name), format("%d/%d", p.rank, p.max), 0.85, 0.85, 0.85, 1, 1, 1)
		end
	end

	local rested = ns.ProjectedRested(rec)
	if rested then
		tt:AddLine(" ")
		tt:AddDoubleLine(L.Rested, format("%d%%%s", rested * 100, rec.resting and (" · " .. L.Resting) or ""), 0.85, 0.85, 0.85, unpack(C.rested))
	end

	tt:Show()
end

-- Rows ------------------------------------------------------------------------

local function AnchorCell(row, fs, col, yOffset, xInset)
	fs:SetPoint("LEFT", row, "LEFT", col.x + (xInset or 0), yOffset or 0)
	fs:SetWidth(col.width - (xInset or 0))
	fs:SetJustifyH(col.align)
end

local function OpenRowMenu(row)
	local rec, guid = row.rec, row.rec.guid
	local hidden = ns.db.hidden[guid]
	if not MenuUtil then
		ns.db.hidden[guid] = not hidden or nil
		ns.Refresh()
		return
	end
	MenuUtil.CreateContextMenu(row, function(_, root)
		root:CreateTitle(rec.name or "?")
		root:CreateButton(hidden and L.Unhide or L.Hide, function()
			ns.db.hidden[guid] = not hidden or nil
			ns.Refresh()
		end)
		if guid ~= ns.currentGUID then
			root:CreateButton("|cffff6060" .. L.Delete .. "|r", function()
				ns.db.chars[guid] = nil
				ns.db.hidden[guid] = nil
				print("|cff66ccffAltboard|r " .. L.Deleted:format(rec.name or "?"))
				ns.Refresh()
			end)
		end
	end)
end

local function BuildRow(row)
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(unpack(C.stripe))

	row.hl = row:CreateTexture(nil, "BORDER")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(unpack(C.hover))
	row.hl:Hide()

	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("TOPLEFT", 0, -1)
	row.bar:SetPoint("BOTTOMLEFT", 0, 1)
	row.bar:SetWidth(3)

	-- Character: spec icon framed in class colour, name and a detail line
	local x = COL.name.x
	row.iconBorder = row:CreateTexture(nil, "ARTWORK")
	row.iconBorder:SetSize(28, 28)
	row.iconBorder:SetPoint("LEFT", x, 0)
	row.icon = row:CreateTexture(nil, "OVERLAY")
	row.icon:SetPoint("TOPLEFT", row.iconBorder, 1, -1)
	row.icon:SetPoint("BOTTOMRIGHT", row.iconBorder, -1, 1)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.name = Text(row, F.text)
	AnchorCell(row, row.name, COL.name, 7, 38)
	row.sub = Text(row, F.small)
	AnchorCell(row, row.sub, COL.name, -8, 38)

	row.ilvl = Text(row, F.num)
	AnchorCell(row, row.ilvl, COL.ilvl)

	row.gold = Text(row, F.numSmall)
	AnchorCell(row, row.gold, COL.gold)

	-- Great Vault: three groups of three pips
	row.pips = {}
	local pipW, gap, groupGap = 11, 3, 12
	local groupW = pipW * 3 + gap * 2
	local startX = COL.vault.x + (COL.vault.width - (groupW * 3 + groupGap * 2)) / 2
	for g = 1, 3 do
		for s = 1, 3 do
			local pip = row:CreateTexture(nil, "ARTWORK")
			pip:SetSize(pipW, 11)
			pip:SetPoint("LEFT", row, "LEFT", startX + (g - 1) * (groupW + groupGap) + (s - 1) * (pipW + gap), 0)
			row.pips[(g - 1) * 3 + s] = pip
		end
	end
	row.vaultReward = Text(row, F.text)
	AnchorCell(row, row.vaultReward, COL.vault)
	row.vaultReward:SetTextColor(unpack(C.gold))

	row.key = Text(row, F.text)
	AnchorCell(row, row.key, COL.key, 7)
	row.score = Text(row, F.small)
	AnchorCell(row, row.score, COL.key, -8)

	row.crests = Text(row, F.numSmall)
	AnchorCell(row, row.crests, COL.crests)

	row.keys = Text(row, F.numSmall)
	AnchorCell(row, row.keys, COL.keys)

	-- Rested: percentage over a thin bar
	local rx = COL.rested.x + (COL.rested.width - 60) / 2
	row.restBg = row:CreateTexture(nil, "ARTWORK")
	row.restBg:SetSize(60, 4)
	row.restBg:SetPoint("LEFT", row, "LEFT", rx, -7)
	row.restBg:SetColorTexture(unpack(C.pipEmpty))
	row.restFill = row:CreateTexture(nil, "OVERLAY")
	row.restFill:SetHeight(4)
	row.restFill:SetPoint("LEFT", row.restBg, "LEFT")
	row.restFill:SetColorTexture(unpack(C.rested))
	row.rested = Text(row, F.numSmall)
	AnchorCell(row, row.rested, COL.rested)

	row.seen = Text(row, F.small)
	AnchorCell(row, row.seen, COL.seen)

	row:RegisterForClicks("RightButtonUp")
	row:SetScript("OnEnter", function(self)
		self.hl:Show()
		ShowRowTooltip(self)
	end)
	row:SetScript("OnLeave", function(self)
		self.hl:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", OpenRowMenu)
	row.built = true
end

local function UpdateRow(row, data)
	if not row.built then BuildRow(row) end
	local rec = data.rec
	row.rec = rec
	row.stripe:SetShown(data.index % 2 == 0)
	row:SetAlpha(ns.db.hidden[rec.guid] and 0.4 or 1)

	local r, g, b = ClassColor(rec)
	row.bar:SetColorTexture(r, g, b, 0.9)
	row.iconBorder:SetColorTexture(r, g, b, 0.85)
	local classAtlas = rec.class and "classicon-" .. rec.class:lower()
	if rec.specIcon then
		row.icon:SetTexture(rec.specIcon)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	elseif classAtlas and C_Texture.GetAtlasInfo(classAtlas) then
		row.icon:SetAtlas(classAtlas)
	else
		row.icon:SetTexture(134400)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	local leveling = rec.level and rec.maxLevel and rec.level < rec.maxLevel
	row.name:SetText(rec.name or "?")
	row.name:SetTextColor(r, g, b)
	row.sub:SetText(table.concat({ rec.specName or rec.className or "", leveling and L.Level:format(rec.level) or rec.realm or "" }, " · "))

	row.ilvl:SetText(rec.ilvl and rec.ilvl > 0 and format("|c%s%d|r", ItemLevelColor(rec.ilvl), math.floor(rec.ilvl)) or "–")
	row.gold:SetText(Money(rec.money))

	-- Vault
	local pending, stale = ns.HasPendingReward(rec), ns.IsStaleWeek(rec)
	row.vaultReward:SetShown(pending)
	row.vaultReward:SetText(L.RewardPending)
	for g, vt in ipairs(ns.VAULT_TYPES) do
		local slots = rec.vault and rec.vault[vt.key]
		for s = 1, 3 do
			local pip = row.pips[(g - 1) * 3 + s]
			pip:SetShown(not pending)
			pip:SetAlpha(leveling and 0.35 or 1)
			local slot = slots and slots[s]
			if slot and not stale and slot.progress >= slot.threshold then
				pip:SetColorTexture(unpack(VAULT_COLORS[vt.key]))
			else
				pip:SetColorTexture(unpack(C.pipEmpty))
			end
		end
	end

	-- Keystone and rating
	if rec.key then
		local name = rec.key.name or ""
		row.key:SetText(format("|cffffffff+%d|r %s", rec.key.level or 0, name))
		row.key:SetAlpha(stale and 0.45 or 1)
	else
		row.key:SetText("|cff606670" .. (leveling and "–" or L.NoKey) .. "|r")
		row.key:SetAlpha(1)
	end
	row.score:SetText((rec.score or 0) > 0 and ScoreText(rec.score) or "")

	-- Crests: Weathered, Carved, Runed, Gilded
	if leveling then
		row.crests:SetText("|cff606670–|r")
	else
		local crests = {}
		for i, id in ipairs(ns.CRESTS) do
			crests[i] = format("|c%s%d|r", ns.CREST_COLORS[i], Qty(rec, id))
		end
		row.crests:SetText(table.concat(crests, "  "))
	end

	local keys = rec.currencies and rec.currencies[ns.COFFER_KEYS]
	row.keys:SetText(keys and format("|T%d:13:13|t %d", keys.icon or 134400, keys.quantity) or "–")

	local rested = ns.ProjectedRested(rec)
	if rested then
		row.rested:SetPoint("LEFT", row, "LEFT", COL.rested.x, 5)
		row.rested:SetText(format("%d%%", rested * 100))
		row.restBg:Show()
		row.restFill:Show()
		row.restFill:SetWidth(math.max(1, 60 * math.min(rested / 1.5, 1)))
	else
		row.rested:SetPoint("LEFT", row, "LEFT", COL.rested.x, 0)
		row.rested:SetText("|cff606670" .. (leveling and "–" or L.MaxLevel) .. "|r")
		row.restBg:Hide()
		row.restFill:Hide()
	end

	row.seen:SetText(Ago(rec))
end

-- Window ----------------------------------------------------------------------

local frame

local function SortedList()
	local db, list = ns.db, {}
	for guid, rec in pairs(db.chars) do
		rec.guid = rec.guid or guid
		if db.showHidden or not db.hidden[guid] then
			list[#list + 1] = { rec = rec }
		end
	end
	local col = COL[db.sort] or COL.ilvl
	local desc = db.sortDesc
	table.sort(list, function(a, b)
		local va, vb = col.value(a.rec), col.value(b.rec)
		if va ~= vb then
			if desc then return va > vb end
			return va < vb
		end
		return (a.rec.name or "") < (b.rec.name or "")
	end)
	for i, d in ipairs(list) do d.index = i end
	return list
end

local function UpdateHeaders()
	for _, col in ipairs(COLUMNS) do
		local active = ns.db.sort == col.key
		col.button.label:SetTextColor(unpack(active and C.accent or C.dim))
		col.button.arrow:SetShown(active)
		if active then
			col.button.arrow:SetRotation(ns.db.sortDesc and math.pi or 0)
		end
	end
end

local function UpdateFooter()
	local reset = ns.db.weekResetAt
	if reset then
		frame.reset:SetText(format("%s |cffffffff%s|r", L.WeeklyReset, Duration(reset - time())))
	end
end

function ns.Refresh()
	if not frame or not frame:IsShown() then return end
	local list = SortedList()
	frame.scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)

	local rows = math.min(math.max(#list, 1), MAX_ROWS)
	frame:SetHeight(HEADER_H + COLS_H + rows * ROW_H + FOOTER_H)

	local total = 0
	for _, rec in pairs(ns.db.chars) do total = total + (rec.money or 0) end
	frame.total:SetText(Money(total + (ns.db.warbandMoney or 0)))
	frame.warband:SetText(ns.db.warbandMoney and format("%s: %s", L.WarbandBank, Money(ns.db.warbandMoney)) or "")
	frame.count:SetText(format("%s · %s", L.Characters:format(#list), L.ColNameHint))
	UpdateHeaders()
	UpdateFooter()
end

local function CreateHeaderButton(parent, col)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(col.width, COLS_H)
	b:SetPoint("LEFT", parent, "LEFT", col.x, 0)
	b.label = Text(b, F.header)
	b.label:SetText(col.label)
	b.label:SetJustifyH(col.align)
	b.label:SetAllPoints()
	b.arrow = b:CreateTexture(nil, "OVERLAY")
	b.arrow:SetAtlas("auctionhouse-ui-sortarrow")
	b.arrow:SetSize(9, 7)
	b.arrow:SetVertexColor(unpack(C.accent))
	local w = b.label:GetUnboundedStringWidth()
	if col.align == "RIGHT" then
		b.arrow:SetPoint("RIGHT", b, "RIGHT", -(w + 4), 0)
	elseif col.align == "CENTER" then
		b.arrow:SetPoint("LEFT", b, "CENTER", w / 2 + 4, 0)
	else
		b.arrow:SetPoint("LEFT", b, "LEFT", w + 4, 0)
	end
	b:SetScript("OnClick", function()
		if ns.db.sort == col.key then
			ns.db.sortDesc = not ns.db.sortDesc
		else
			ns.db.sort = col.key
			ns.db.sortDesc = col.key ~= "name"
		end
		ns.Refresh()
	end)
	b:SetScript("OnEnter", function(self)
		self.label:SetTextColor(unpack(C.text))
		if col.key == "vault" then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddLine(L.Vault, unpack(C.accent))
			for _, vt in ipairs(ns.VAULT_TYPES) do
				GameTooltip:AddLine(L[vt.key], unpack(VAULT_COLORS[vt.key]))
			end
			GameTooltip:Show()
		elseif col.key == "crests" then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			for i, id in ipairs(ns.CRESTS) do
				local info = C_CurrencyInfo.GetCurrencyInfo(id)
				if info then GameTooltip:AddLine("|c" .. ns.CREST_COLORS[i] .. info.name .. "|r") end
			end
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function()
		UpdateHeaders()
		GameTooltip:Hide()
	end)
	col.button = b
end

local function CreateWindow()
	local f = CreateFrame("Frame", "AltboardFrame", UIParent, "BackdropTemplate")
	f:SetSize(TOTAL_W, 400)
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
	f:SetScale(ns.db.scale or 1)
	if ns.db.point then
		local p = ns.db.point
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint("CENTER")
	end
	tinsert(UISpecialFrames, "AltboardFrame")

	-- A soft accent glow along the top edge
	local glow = f:CreateTexture(nil, "BORDER")
	glow:SetPoint("TOPLEFT", 1, -1)
	glow:SetPoint("TOPRIGHT", -1, -1)
	glow:SetHeight(HEADER_H)
	glow:SetColorTexture(1, 1, 1, 1)
	glow:SetGradient("VERTICAL", CreateColor(0.4, 0.8, 1, 0), CreateColor(0.4, 0.8, 1, 0.08))
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 1, -1)
	line:SetPoint("TOPRIGHT", -1, -1)
	line:SetHeight(2)
	line:SetColorTexture(0.4, 0.8, 1, 0.9)

	local title = Text(f, F.title)
	title:SetPoint("TOPLEFT", PAD + 2, -16)
	title:SetText(L.Title)
	f.count = Text(f, F.small)
	f.count:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	f.total = Text(f, F.num)
	f.total:SetPoint("TOPRIGHT", -40, -14)
	f.warband = Text(f, F.small)
	f.warband:SetPoint("TOPRIGHT", f.total, "BOTTOMRIGHT", 0, -5)
	local totalLabel = Text(f, F.small)
	totalLabel:SetPoint("RIGHT", f.total, "LEFT", -8, 0)
	totalLabel:SetText(L.TotalGold)

	-- Column headers
	local cols = CreateFrame("Frame", nil, f, "BackdropTemplate")
	cols:SetPoint("TOPLEFT", 1, -HEADER_H)
	cols:SetPoint("TOPRIGHT", -1, -HEADER_H)
	cols:SetHeight(COLS_H)
	cols:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	cols:SetBackdropColor(unpack(C.panel))
	for _, col in ipairs(COLUMNS) do
		CreateHeaderButton(cols, col)
	end

	-- Character list
	local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", cols, "BOTTOMLEFT", 0, 0)
	scrollBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, FOOTER_H)
	local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, -2)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 2)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_H)
	view:SetElementInitializer("Button", UpdateRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar)
	f.scrollBox = scrollBox

	-- Footer
	local footer = CreateFrame("Frame", nil, f, "BackdropTemplate")
	footer:SetPoint("BOTTOMLEFT", 1, 1)
	footer:SetPoint("BOTTOMRIGHT", -1, 1)
	footer:SetHeight(FOOTER_H - 1)
	footer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	footer:SetBackdropColor(unpack(C.panel))

	local check = CreateFrame("CheckButton", nil, footer, "UICheckButtonTemplate")
	check:SetSize(22, 22)
	check:SetPoint("LEFT", PAD - 4, 0)
	check:SetChecked(ns.db.showHidden)
	check:SetScript("OnClick", function(self)
		ns.db.showHidden = self:GetChecked()
		ns.Refresh()
	end)
	local checkLabel = Text(footer, F.small)
	checkLabel:SetPoint("LEFT", check, "RIGHT", 2, 0)
	checkLabel:SetText(L.ShowHidden)

	local hint = Text(footer, F.small)
	hint:SetPoint("LEFT", checkLabel, "RIGHT", 18, 0)
	hint:SetText(L.Hint)
	hint:SetTextColor(unpack(C.faint))

	f.reset = Text(footer, F.small)
	f.reset:SetPoint("RIGHT", -PAD, 0)

	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= 1 then
			elapsed = 0
			UpdateFooter()
		end
	end)
	f:SetScript("OnShow", ns.Refresh)
	f:Hide()
	return f
end

function ns.Toggle()
	if not ns.db then return end
	frame = frame or CreateWindow()
	frame:SetShown(not frame:IsShown())
end
