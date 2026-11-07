-- Morigoll DevTest: a development-only harness, never shipped.
--
-- Loads before the other addons (the "!" in the folder name) and records every
-- Lua error, blocked action and Lua warning of the session. /devtest then opens
-- Barracks, Keepsake and Treasure Trail, clicks and hovers their controls,
-- checks their data against the game, takes a screenshot of the key steps and
-- keeps a report in MorigollDevTestDB. /reload writes the report to disk, where
-- tools/devtest/report.mjs reads it.

local ADDON = ...
local TARGETS = { "Barracks", "Keepsake", "TreasureTrail" }
local FRAMES = { Barracks = "BarracksFrame", Keepsake = "KeepsakeFrame", TreasureTrail = "TreasureTrailFrame" }
local SLASH = { Barracks = "BARRACKS", Keepsake = "KEEPSAKE", TreasureTrail = "TREASURETRAIL" }
local SHOTS_PER_ADDON = 14
local MAX_LIST = 200

local t0 = debugprofilestop()
local function Now() return floor(debugprofilestop() - t0) / 1000 end

local session = { errors = {}, caught = {}, blocked = {}, warnings = {}, loaded = {}, startedAt = date("%Y-%m-%d %H:%M:%S") }
local nsOf = {}
local run, current
local queue = {}

-- Helpers ------------------------------------------------------------------------------

local function Str(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<?>"
end

-- Calls fn and returns all its results, or nothing if it fails.
local function PassResults(ok, ...)
	if ok then return ... end
end
local function Safe(fn, ...)
	return PassResults(pcall(fn, ...))
end

local function AddonFromText(s)
	for _, name in ipairs(TARGETS) do
		if s:find("AddOns[/\\]" .. name .. "[/\\]") then return name end
	end
	return s:match("AddOns[/\\]([^/\\]+)[/\\]") or "?"
end

local function Total(list)
	local n = 0
	for _, e in ipairs(list) do n = n + e.count end
	return n
end

local function Record(list, entry)
	for _, e in ipairs(list) do
		if e.msg == entry.msg then
			e.count = e.count + 1
			return
		end
	end
	if #list >= MAX_LIST then return end
	entry.count = 1
	entry.at = Now()
	entry.step = current and current.label
	list[#list + 1] = entry
end

-- Error capture ------------------------------------------------------------------------

local handler, previous
local busy = false
handler = function(msg, ...)
	if not busy then
		busy = true
		pcall(function()
			local text = Str(msg)
			Record(session.errors, { msg = text, addon = AddonFromText(text), stack = debugstack(3, 12, 0) })
		end)
		busy = false
	end
	if previous then return previous(msg, ...) end
end

local function InstallHandler()
	local ok = pcall(function()
		local h = geterrorhandler()
		if h ~= handler then
			previous = h
			seterrorhandler(handler)
		end
	end)
	session.handlerInstalled = ok and geterrorhandler() == handler
end
InstallHandler()
-- Blizzard's error frame sets its own handler when it loads; keep ours in front.
pcall(hooksecurefunc, "seterrorhandler", function(h)
	if h ~= handler then
		previous = h
		seterrorhandler(handler)
	end
end)

-- Environment ------------------------------------------------------------------------

local function Env()
	local version, build, buildDate, toc = GetBuildInfo()
	local inInstance, instanceType = IsInInstance()
	local w, h = Safe(GetPhysicalScreenSize)
	return {
		version = version, build = build, buildDate = buildDate, toc = toc,
		locale = GetLocale(),
		realm = Safe(GetRealmName),
		char = Safe(UnitName, "player"),
		level = Safe(UnitLevel, "player"),
		class = select(2, UnitClass("player")),
		zone = Safe(GetRealZoneText),
		subzone = Safe(GetSubZoneText),
		mapID = Safe(C_Map.GetBestMapForUnit, "player"),
		inInstance = inInstance, instanceType = instanceType,
		screen = w and (w .. "x" .. h),
		uiScale = Safe(function() return UIParent:GetEffectiveScale() end),
		time = date("%Y-%m-%d %H:%M:%S"),
	}
end

local function AddonStatus(name)
	local s = {}
	s.loaded = Safe(C_AddOns.IsAddOnLoaded, name)
	local _, title, _, loadable, reason = Safe(C_AddOns.GetAddOnInfo, name)
	s.loadable, s.reason = loadable, reason
	s.version = Safe(C_AddOns.GetAddOnMetadata, name, "Version")
	s.interface = Safe(C_AddOns.GetAddOnInterfaceVersion, name)
	s.loadError = Safe(C_AddOns.DoesAddOnHaveLoadError, name)
	s.localTable = nsOf[name] ~= nil
	if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		Safe(UpdateAddOnMemoryUsage)
		s.memoryKB = Safe(GetAddOnMemoryUsage, name)
	end
	return s
end

-- Events -----------------------------------------------------------------------------

local events = CreateFrame("Frame")
local function Listen(event) pcall(events.RegisterEvent, events, event) end
Listen("ADDON_LOADED")
Listen("PLAYER_LOGIN")
Listen("ADDON_ACTION_BLOCKED")
Listen("ADDON_ACTION_FORBIDDEN")
Listen("LUA_WARNING")

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name == ADDON then
			local old = MorigollDevTestDB
			MorigollDevTestDB = { session = session, run = old and old.run, probe = old and old.probe, grid = old and old.grid }
			return
		end
		for _, target in ipairs(TARGETS) do
			if name == target then
				session.loaded[name] = Now()
				-- Opt-in through AllowAddOnTableAccess in the addon's toc.
				local ns = Safe(C_AddOns.GetAddOnLocalTable, name)
				if type(ns) == "table" then
					nsOf[name] = ns
					ns.onError = function(where, err)
						Record(session.caught, { msg = Str(err), addon = name, where = Str(where) })
					end
				end
			end
		end
	elseif event == "PLAYER_LOGIN" then
		InstallHandler()
		session.env = Env()
		session.addons = {}
		for _, name in ipairs(TARGETS) do session.addons[name] = AddonStatus(name) end
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		local addon, func = ...
		Record(session.blocked, { msg = event .. ": " .. Str(addon) .. " -> " .. Str(func), addon = Str(addon), stack = debugstack(2, 8, 0) })
	elseif event == "LUA_WARNING" then
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = Str((select(i, ...))) end
		local text = table.concat(parts, " | ")
		Record(session.warnings, { msg = text, addon = AddonFromText(text) })
	end
end)

-- Banner ----------------------------------------------------------------------------

local banner = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
banner:SetFrameStrata("TOOLTIP")
banner:SetSize(640, 30)
banner:SetPoint("TOP", 0, -8)
banner:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
banner:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
banner:SetBackdropBorderColor(1, 0.37, 0.77, 1)
banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
banner.text:SetPoint("CENTER")
banner:Hide()

local function Banner(text, r, g, b)
	banner.text:SetText(text)
	banner.text:SetTextColor(r or 1, g or 1, b or 1)
	banner:SetWidth(math.max(320, banner.text:GetUnboundedStringWidth() + 40))
	banner:Show()
end

-- Frame inspection --------------------------------------------------------------------

local function IsScrollPart(f)
	return f.ScrollTarget ~= nil or f.Track ~= nil
end

local function Label(c)
	local fs = c.text or c.label or (c.GetFontString and c:GetFontString())
	local t = fs and fs.GetText and fs:GetText()
	if not t or t == "" then
		for _, r in ipairs({ c:GetRegions() }) do
			if r:GetObjectType() == "FontString" and r:GetText() and r:GetText() ~= "" then
				t = r:GetText()
				break
			end
		end
	end
	t = t and Str(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or nil
	return (c:GetObjectType() == "CheckButton" and "[check] " or "") .. (t or ("<" .. (c:GetDebugName() or "?") .. ">"))
end

local function Texts(frame, out)
	out = out or {}
	for _, r in ipairs({ frame:GetRegions() }) do
		if #out >= 150 then return out end
		if r:GetObjectType() == "FontString" and r:IsVisible() then
			local t = r:GetText()
			if t ~= nil then
				t = Str(t)
				if t ~= "" then out[#out + 1] = t end
			end
		end
	end
	for _, c in ipairs({ frame:GetChildren() }) do
		if c:IsVisible() then Texts(c, out) end
	end
	return out
end

-- Text that suggests a formatting or data bug.
local BAD = { "%f[%a]nil%f[%A]", "%%[sdfi]", "%f[%a]NaN%f[%A]", "%f[%a]inf%f[%A]", "<secret>", "ERROR", "%?%?" }
local function BadTexts(texts)
	local bad = {}
	for _, t in ipairs(texts) do
		for _, p in ipairs(BAD) do
			if t:find(p) then
				bad[#bad + 1] = t
				break
			end
		end
	end
	return bad
end

local function Controls(root, skip)
	local list = {}
	local function Walk(f)
		for _, c in ipairs({ f:GetChildren() }) do
			if not IsScrollPart(c) and not (skip and skip[c]) then
				local kind = c:GetObjectType()
				if (kind == "Button" or kind == "CheckButton") and c:IsVisible() and c:GetScript("OnClick") then
					list[#list + 1] = c
				end
				Walk(c)
			end
		end
	end
	Walk(root)
	return list
end

local function EditBoxes(root)
	local list = {}
	local function Walk(f)
		for _, c in ipairs({ f:GetChildren() }) do
			if c:GetObjectType() == "EditBox" and c:IsVisible() then list[#list + 1] = c end
			if not IsScrollPart(c) then Walk(c) end
		end
	end
	Walk(root)
	return list
end

local function Rows(root, predicate, max)
	local list = {}
	local box = root.scrollBox
	if not box or not box.GetFrames then return list end
	local frames = {}
	for _, row in ipairs(box:GetFrames() or {}) do frames[#frames + 1] = row end
	table.sort(frames, function(a, b) return (a:GetTop() or 0) > (b:GetTop() or 0) end)
	for _, row in ipairs(frames) do
		if row:IsVisible() and (not predicate or predicate(row)) then
			list[#list + 1] = row
			if #list >= (max or 6) then break end
		end
	end
	return list
end

local function RowData(row)
	return row.data or row.rec or (row.GetElementData and Safe(row.GetElementData, row))
end

local function TooltipLines(owner)
	if not GameTooltip:IsVisible() then return nil end
	if owner and GameTooltip:GetOwner() ~= owner then return nil end
	local out = {}
	for i = 1, math.min(GameTooltip:NumLines() or 0, 30) do
		local l, r = _G["GameTooltipTextLeft" .. i], _G["GameTooltipTextRight" .. i]
		local lt = l and l:GetText()
		local rt = r and r:IsShown() and r:GetText()
		if lt or rt then
			out[#out + 1] = Str(lt or "") .. (rt and ("  ||  " .. Str(rt)) or "")
		end
	end
	return out
end

local function OnScreen(frame)
	local l, b, w, h = frame:GetRect()
	if not l then return false end
	local s, us = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
	local W, H = UIParent:GetWidth() * us, UIParent:GetHeight() * us
	return l * s >= -1 and b * s >= -1 and (l + w) * s <= W + 1 and (b + h) * s <= H + 1
end

local function Hover(frame, step)
	if step then step.hovered = frame end
	local enter = frame:GetScript("OnEnter")
	if enter then enter(frame) end
end

local function Unhover(frame)
	local leave = frame:GetScript("OnLeave")
	if leave then leave(frame) end
	GameTooltip:Hide()
end

-- Steps -------------------------------------------------------------------------------

local function Expect(step, cond, what)
	step.checks = (step.checks or 0) + 1
	if not cond then
		step.fails = step.fails or {}
		step.fails[#step.fails + 1] = what
	end
	return cond
end

local function Note(step, key, value)
	step.data = step.data or {}
	step.data[key] = value
end

local function Step(addon, label, fn, opts)
	opts = opts or {}
	return { addon = addon, label = label, fn = fn, after = opts.after, wait = opts.wait or 0.6, shot = opts.shot, tooltip = opts.tooltip, texts = opts.texts }
end

local function Push(steps)
	for i = #steps, 1, -1 do table.insert(queue, 1, steps[i]) end
end

local function Window(addon) return _G[FRAMES[addon]] end

local function Open(addon)
	local f = Window(addon)
	if not (f and f:IsShown()) then SlashCmdList[SLASH[addon]]("") end
	return Window(addon)
end

local function Close(addon)
	local f = Window(addon)
	if f and f:IsShown() then f:Hide() end
end

-- Remember the settings a click may change (sort, filters, checkboxes) and put them back.
local function SnapshotDB(addon)
	local ns = nsOf[addon]
	if not (ns and ns.db) then return end
	local snap = {}
	for k, v in pairs(ns.db) do
		if type(v) ~= "table" then snap[k] = v end
	end
	run.snapshots[addon] = snap
end

local function RestoreDB(addon)
	local ns, snap = nsOf[addon], run.snapshots[addon]
	if not (ns and ns.db and snap) then return end
	for k, v in pairs(ns.db) do
		local t = type(v)
		if (t == "string" or t == "number" or t == "boolean") and snap[k] == nil then ns.db[k] = nil end
	end
	for k, v in pairs(snap) do ns.db[k] = v end
	if ns.Refresh then pcall(ns.Refresh) end
	if ns.UpdatePill then pcall(ns.UpdatePill) end
end

-- The click, hover and screenshot steps for every control in a window.
local function ControlSteps(addon, root, skip, waitAfterClick)
	local steps = {}
	for _, c in ipairs(Controls(root, skip)) do
		local label = Label(c)
		if c:GetScript("OnEnter") then
			steps[#steps + 1] = Step(addon, "hover " .. label, function(step) Hover(c, step) end, {
				wait = 0.4, tooltip = true,
				after = function() Unhover(c) end,
			})
		end
		if c:GetObjectType() == "CheckButton" then
			steps[#steps + 1] = Step(addon, "toggle " .. label, function(step)
				local before = c:GetChecked()
				c:Click()
				Expect(step, c:GetChecked() ~= before, "checkbox did not change")
				c:Click()
				Expect(step, c:GetChecked() == before, "checkbox did not go back")
			end, { wait = 0.5 })
		else
			steps[#steps + 1] = Step(addon, "click " .. label, function() c:Click("LeftButton") end, {
				wait = waitAfterClick or 0.6, shot = true, texts = true,
				after = function(step)
					if not root:IsShown() then
						Note(step, "closedWindow", true)
						Open(addon)
					end
				end,
			})
		end
	end
	return steps
end

local function RowSteps(addon, root, predicate, max)
	local steps = {}
	for i, row in ipairs(Rows(root, predicate, max)) do
		steps[#steps + 1] = Step(addon, "hover row " .. i, function(step)
			local d = RowData(row)
			if type(d) == "table" then
				local summary = {}
				for k, v in pairs(d) do
					if type(v) ~= "table" and type(v) ~= "function" then summary[k] = Str(v) end
				end
				Note(step, "row", summary)
			end
			Hover(row, step)
		end, { wait = 0.5, tooltip = true, shot = i == 1, after = function() Unhover(row) end })
	end
	return steps
end

local function OpenStep(addon, wait, check)
	return Step(addon, "open with /" .. SLASH[addon]:lower(), function(step)
		SnapshotDB(addon)
		Close(addon)
		Open(addon)
	end, {
		wait = wait or 1, shot = true, texts = true,
		after = function(step)
			local f = Window(addon)
			if Expect(step, f and f:IsShown(), "window did not open") then
				Expect(step, OnScreen(f), "window is partly off screen")
				if f.scrollBox and f.scrollBox.GetDataProviderSize then
					Note(step, "listRows", Safe(f.scrollBox.GetDataProviderSize, f.scrollBox))
				end
			end
			if check then check(step) end
		end,
	})
end

local function CloseStep(addon)
	return Step(addon, "close and restore settings", function(step)
		RestoreDB(addon)
		Close(addon)
	end, {
		wait = 0.5,
		after = function(step)
			local f = Window(addon)
			Expect(step, not (f and f:IsShown()), "window did not close")
		end,
	})
end

-- Barracks --------------------------------------------------------------------------------

local function CheckBarracksData(step)
	local ns = nsOf.Barracks
	if not Expect(step, ns and ns.db, "no access to Barracks' addon table") then return end
	local rec = ns.db.chars[UnitGUID("player")]
	if not Expect(step, rec, "no record for the current character") then return end
	Expect(step, rec.name == UnitName("player"), "name differs")
	Expect(step, rec.level == UnitLevel("player"), "level differs: " .. Str(rec.level) .. " vs " .. UnitLevel("player"))
	Expect(step, rec.money == GetMoney(), "money differs: " .. Str(rec.money) .. " vs " .. GetMoney())
	Expect(step, rec.class == select(2, UnitClass("player")), "class differs")
	local toc = select(4, GetBuildInfo())
	Expect(step, ns.vanillaContent == (toc < 20000), "vanillaContent is " .. Str(ns.vanillaContent) .. " on toc " .. toc)
	local chars = 0
	for _ in pairs(ns.db.chars) do chars = chars + 1 end
	local snapshot = {}
	for k, v in pairs(rec) do
		if type(v) ~= "table" then snapshot[k] = v end
	end
	snapshot.professions = rec.professions and #rec.professions
	Note(step, "characters", chars)
	Note(step, "record", snapshot)

	local f = Window("Barracks")
	if not (f and f:IsShown()) then return end
	if ns.vanillaContent and ns.L then
		local shown = {}
		for _, t in ipairs(Texts(f)) do shown[t] = true end
		for _, key in ipairs({ "Vault", "Keystone", "Crests", "Keys" }) do
			local label = ns.L[key]
			Expect(step, not (label and shown[label]), "column for modern content shown on vanilla content: " .. Str(label))
		end
	end
	for _, row in ipairs(Rows(f, nil, 12)) do
		if row.rec and row.rec.guid == rec.guid and row.gold then
			local text = Str(row.gold:GetText())
			Note(step, "goldText", text)
			Expect(step, (rec.money or 0) == 0 or not text:find("^0 "), "money shows 0 for " .. Str(rec.money) .. " copper: " .. text)
		end
	end
end

local function BarracksSteps()
	local addon = "Barracks"
	local steps = { OpenStep(addon, 1.2, CheckBarracksData) }
	steps[#steps + 1] = Step(addon, "build control steps", function()
		local root = Window(addon)
		local more = ControlSteps(addon, root)
		for _, s in ipairs(RowSteps(addon, root, nil, 3)) do more[#more + 1] = s end
		local first = Rows(root, nil, 1)[1]
		if first then
			more[#more + 1] = Step(addon, "right-click menu on first row", function() first:Click("RightButton") end, {
				wait = 0.6, shot = true,
				after = function(step)
					local manager = Menu and Menu.GetManager and Menu.GetManager()
					local menu = manager and manager.GetOpenMenu and manager:GetOpenMenu()
					Expect(step, menu ~= nil, "no context menu opened")
					if manager then manager:CloseMenus() end
				end,
			})
		end
		local mm = BarracksMinimapButton
		if mm and mm:IsVisible() then
			more[#more + 1] = Step(addon, "hover minimap button", function(step) Hover(mm, step) end, { wait = 0.4, tooltip = true, shot = true, after = function() Unhover(mm) end })
			more[#more + 1] = Step(addon, "minimap button closes the window", function()
				mm:GetScript("OnClick")(mm, "LeftButton")
			end, { wait = 0.4, after = function(step) Expect(step, not root:IsShown(), "window still open") end })
			more[#more + 1] = Step(addon, "minimap button opens the window", function()
				mm:GetScript("OnClick")(mm, "LeftButton")
			end, { wait = 0.6, after = function(step) Expect(step, root:IsShown(), "window did not open") end })
		end
		more[#more + 1] = Step(addon, "/alts scan", function() SlashCmdList.BARRACKS("scan") end, { wait = 1.5, after = CheckBarracksData })
		more[#more + 1] = CloseStep(addon)
		Push(more)
	end, { wait = 0 })
	return steps
end

-- Keepsake --------------------------------------------------------------------------------

local function CheckKeepsakeData(step)
	local ns = nsOf.Keepsake
	if not Expect(step, ns and ns.db, "no access to Keepsake's addon table") then return end
	local c = ns.db.chars and ns.db.chars[UnitGUID("player")]
	if not Expect(step, c, "no journal for the current character") then return end
	Expect(step, type(c.entries) == "table" and #c.entries > 0, "journal has no entries")
	Expect(step, c.level == UnitLevel("player"), "level differs: " .. Str(c.level))
	local last = {}
	for i = math.max(1, #c.entries - 4), #c.entries do
		local e, flat = c.entries[i], {}
		for k, v in pairs(e) do
			if type(v) ~= "table" then flat[k] = v end
		end
		last[#last + 1] = flat
	end
	Note(step, "entries", #c.entries)
	Note(step, "lastEntries", last)
end

local function KeepsakeSteps()
	local addon = "Keepsake"
	local steps = { OpenStep(addon, 1, CheckKeepsakeData) }
	steps[#steps + 1] = Step(addon, "build control steps", function()
		local root = Window(addon)
		-- Importing achievements writes to the journal; leave it alone.
		local more = ControlSteps(addon, root, { [root.import or false] = true })
		for _, box in ipairs(EditBoxes(root)) do
			more[#more + 1] = Step(addon, "search 'a'", function() box:SetText("a") end, { wait = 0.6, shot = true, texts = true })
			more[#more + 1] = Step(addon, "clear search", function()
				box:SetText("")
				box:ClearFocus()
			end, { wait = 0.4 })
		end
		for _, s in ipairs(RowSteps(addon, root, function(row)
			local d = RowData(row)
			return type(d) == "table" and not d.day
		end, 4)) do
			more[#more + 1] = s
		end
		more[#more + 1] = CloseStep(addon)
		Push(more)
	end, { wait = 0 })
	return steps
end

-- Treasure Trail ----------------------------------------------------------------------------

local function CheckTrailData(step)
	local ns = nsOf.TreasureTrail
	if not Expect(step, ns, "no access to Treasure Trail's addon table") then return end
	local s = ns.state
	if not Expect(step, s, "no scan result") then return end
	Note(step, "state", {
		zoneName = s.zoneName, zoneMapID = s.zoneMapID, total = s.total,
		mounts = s.mounts and #s.mounts, pets = s.pets and #s.pets, wild = s.wild and #s.wild,
		entrances = s.entrances and #s.entrances,
		instance = s.instance and s.instance.name, instanceStatus = s.instanceStatus,
		playerMapID = Safe(C_Map.GetBestMapForUnit, "player"),
	})

	local probe = { maps = {} }
	local id = Safe(C_Map.GetBestMapForUnit, "player")
	for _ = 1, 5 do
		if not id or id == 0 then break end
		local info = Safe(C_Map.GetMapInfo, id)
		local ok, res = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, id)
		local text
		if not ok then
			text = "error " .. Str(res)
		elseif type(res) == "table" then
			local names = {}
			for i = 1, math.min(#res, 4) do names[i] = Str(res[i].name) end
			text = #res .. " entrances " .. table.concat(names, ", ")
		else
			text = Str(res)
		end
		probe.maps[#probe.maps + 1] = format("%d %s (type %s): %s", id, info and Str(info.name) or "?", info and Str(info.mapType) or "?", text)
		id = info and info.parentMapID
	end
	probe.ejTiers = EJ_GetNumTiers and Safe(EJ_GetNumTiers)
	probe.ejCurrentTier = EJ_GetCurrentTier and Safe(EJ_GetCurrentTier)

	local zone = s.zoneName or ""
	local mountIDs = Safe(C_MountJournal.GetMountIDs) or {}
	local mountsHere, mountSources = 0, 0
	for _, mid in ipairs(mountIDs) do
		local _, _, source = Safe(C_MountJournal.GetMountInfoExtraByID, mid)
		if source and source ~= "" then
			mountSources = mountSources + 1
			if zone ~= "" and source:find(zone, 1, true) then mountsHere = mountsHere + 1 end
		end
	end
	local species, petsHere, petExample = 0, 0, nil
	for sid = 1, 6000 do
		local name, _, _, _, source, _, _, _, _, _, obtainable = Safe(C_PetJournal.GetPetInfoBySpeciesID, sid)
		if name and obtainable and source and source ~= "" then
			species = species + 1
			if zone ~= "" and source:find(zone, 1, true) then
				petsHere = petsHere + 1
				petExample = petExample or name
			end
		end
	end
	probe.mountsInJournal = #mountIDs
	probe.mountsWithSource = mountSources
	probe.mountSourcesNamingZone = mountsHere
	probe.petSpeciesObtainable = species
	probe.petSourcesNamingZone = petsHere
	probe.petExample = petExample
	Note(step, "probe", probe)

	-- WoW Forever with our own data: check every entry against the client.
	if ns.Forever and ns.ForeverData then
		Expect(step, not s.noData, "Forever data is loaded but state.noData is set")
		local D = ns.ForeverData
		local audit = { zoneItems = 0, instanceItems = 0, missingItems = {}, unresolved = {}, uncoveredMounts = {} }
		local covered = {}
		audit.uncached = 0
		local function Check(itemID, kind)
			if not C_Item.DoesItemExistByID(itemID) then
				if #audit.missingItems < 100 then audit.missingItems[#audit.missingItems + 1] = itemID end
				return
			end
			if not C_Item.IsItemDataCachedByID(itemID) then
				audit.uncached = audit.uncached + 1
				return
			end
			local mountID = C_MountJournal.GetMountFromItem(itemID)
			if mountID and mountID > 0 then covered[mountID] = true end
			local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(itemID))
			if (kind == "mount" and not (mountID and mountID > 0)) or (kind == "pet" and not speciesID) then
				audit.unresolved[#audit.unresolved + 1] = kind .. " " .. itemID
			end
		end
		for _, z in pairs(D.zones) do
			for itemID, e in pairs(z.items) do
				audit.zoneItems = audit.zoneItems + 1
				Check(itemID, e[1])
			end
		end
		for _, inst in pairs(D.instances) do
			for _, b in ipairs(inst[4]) do
				for i = 1, #b[2], 2 do
					audit.instanceItems = audit.instanceItems + 1
					Check(b[2][i])
				end
			end
		end
		for _, mountID in ipairs(Safe(C_MountJournal.GetMountIDs) or {}) do
			if not covered[mountID] then
				local name, _, _, _, _, _, _, factionSpecific, faction, hide = C_MountJournal.GetMountInfoByID(mountID)
				audit.uncoveredMounts[#audit.uncoveredMounts + 1] = format("%d %s%s", mountID, Str(name), hide and " (hidden)" or "")
			end
		end
		Note(step, "foreverAudit", audit)
		Expect(step, #audit.missingItems == 0, #audit.missingItems .. " items of our data do not exist in this client")
		Expect(step, #audit.unresolved == 0, #audit.unresolved .. " mounts or pets the client does not recognise")
	end

	-- No source data at all (WoW Forever): the window must not claim everything is collected.
	if not ns.Forever and mountSources == 0 and species == 0 and (probe.ejTiers or 0) == 0 then
		Expect(step, s.noData == true, "client has no collection data but state.noData is " .. Str(s.noData))
		local f = Window("TreasureTrail")
		if f and f:IsShown() and ns.L then
			for _, t in ipairs(Texts(f)) do
				Expect(step, t ~= ns.L.NothingMissing, "claims everything is collected without data")
			end
		end
	end
end

-- What each collection API says about the first items of one of our instances.
local function TrailItemDiag(instanceID)
	local ns = nsOf.TreasureTrail
	local inst = ns and ns.ForeverData and ns.ForeverData.instances[instanceID]
	if not inst then return nil end
	local out = {}
	for _, b in ipairs(inst[4]) do
		for i = 1, #b[2], 2 do
			if #out >= 12 then return out end
			local itemID = b[2][i]
			local _, link, quality, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(itemID)
			local parts = { tostring(itemID), Str(equipLoc), "cached=" .. Str(C_Item.IsItemDataCachedByID(itemID)) }
			parts[#parts + 1] = "mount=" .. Str(C_MountJournal.GetMountFromItem(itemID))
			parts[#parts + 1] = "pet13=" .. Str((select(13, C_PetJournal.GetPetInfoByItemID(itemID))))
			parts[#parts + 1] = "toy=" .. Str((C_ToyBox.GetToyInfo(itemID)))
			if link then
				local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(link)
				parts[#parts + 1] = "appearance=" .. Str(appearanceID) .. "/" .. Str(sourceID)
				if sourceID then
					local info = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
					parts[#parts + 1] = "collected=" .. Str(info and info.appearanceIsCollected)
					local hasData, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
					parts[#parts + 1] = "canCollect=" .. Str(hasData) .. "/" .. Str(canCollect)
					if ns.Forever and ns.Forever.CanCollect then parts[#parts + 1] = "ours=" .. Str(ns.Forever.CanCollect(itemID)) end
				end
				local ok, kind = pcall(ns.Collectible, itemID, link)
				parts[#parts + 1] = "Collectible=" .. (ok and Str(kind) or ("error " .. Str(kind)))
			end
			out[#out + 1] = table.concat(parts, " ")
		end
	end
	return out
end

local function IsEntrance(row)
	local d = RowData(row)
	return type(d) == "table" and d.entrance ~= nil
end

local function IsItem(row)
	local d = RowData(row)
	return type(d) == "table" and (d.item ~= nil or d.entrance ~= nil)
end

local function TrailSteps()
	local addon = "TreasureTrail"
	local steps = { OpenStep(addon, 4, CheckTrailData) }
	steps[#steps + 1] = Step(addon, "build control steps", function()
		local root = Window(addon)
		local more = ControlSteps(addon, root)
		for _, s in ipairs(RowSteps(addon, root, IsItem, 4)) do more[#more + 1] = s end
		local entrance = Rows(root, IsEntrance, 1)[1]
		if entrance then
			more[#more + 1] = Step(addon, "browse first dungeon entrance", function(step)
				Note(step, "entrance", Str(RowData(entrance).entrance.name))
				step.instanceID = RowData(entrance).entrance.journalInstanceID
				entrance:Click("LeftButton")
			end, {
				wait = 4, shot = true, texts = true,
				after = function(step)
					Note(step, "itemDiag", TrailItemDiag(step.instanceID))
					Expect(step, root.back and root.back:IsShown(), "back button not shown in browse mode")
					local browse = RowSteps(addon, root, IsItem, 3)
					for _, s in ipairs(ControlSteps(addon, root, nil, 3)) do
						-- Only the difficulty chips and the back button are new here.
						if not s.label:find("^hover") and not s.label:find("%[check%]") then browse[#browse + 1] = s end
					end
					Push(browse)
				end,
			})
		end
		local pill = TreasureTrailPill
		if pill and pill:IsVisible() then
			more[#more + 1] = Step(addon, "hover the pill", function(step) Hover(pill, step) end, { wait = 0.4, tooltip = true, shot = true, after = function() Unhover(pill) end })
		end
		more[#more + 1] = CloseStep(addon)
		Push(more)
	end, { wait = 0 })
	return steps
end

local BUILDERS = { Barracks = BarracksSteps, Keepsake = KeepsakeSteps, TreasureTrail = TrailSteps }

-- Runner --------------------------------------------------------------------------------

local RunNext

local function Summarize()
	local s = { steps = #run.steps, passed = 0, failed = 0, checks = 0, shots = 0 }
	for _, st in ipairs(run.steps) do
		s.checks = s.checks + (st.checks or 0)
		if st.ok then s.passed = s.passed + 1 else s.failed = s.failed + 1 end
		if st.shot then s.shots = s.shots + 1 end
	end
	s.newErrors = Total(session.errors) - run.base.errors
	s.newCaught = Total(session.caught) - run.base.caught
	s.newBlocked = Total(session.blocked) - run.base.blocked
	s.sessionErrors = Total(session.errors)
	return s
end

local function Complete(reason)
	queue = {}
	current = nil
	run.finishedAt = date("%Y-%m-%d %H:%M:%S")
	run.aborted = reason
	run.summary = Summarize()
	MorigollDevTestDB.run = run
	local s = run.summary
	local ok = s.failed == 0 and s.newErrors == 0 and s.newBlocked == 0 and not reason
	local text = reason and ("DevTest parado: " .. reason .. ". Haz /reload para guardar el informe.")
		or format("DevTest terminado: %d/%d pasos OK, %d errores Lua, %d capturados, %d bloqueos. Haz /reload para guardar el informe.", s.passed, s.steps, s.newErrors, s.newCaught, s.newBlocked)
	Banner(text, ok and 0.45 or 1, ok and 0.9 or 0.4, ok and 0.6 or 0.4)
	print("|cffff5ec4DevTest|r " .. text)
	C_Timer.After(20, function() if not current then banner:Hide() end end)
end

local function Finish(step)
	local err, caught, blocked = Total(session.errors), Total(session.caught), Total(session.blocked)
	local result = {
		n = step.n, addon = step.addon, label = step.label,
		errors = err - step.base.errors, caught = caught - step.base.caught, blocked = blocked - step.base.blocked,
		checks = step.checks, fails = step.fails, data = step.data, shot = step.shotAt,
		tooltip = step.tooltipLines, texts = step.textList, bad = step.bad,
	}
	result.ok = not step.fails and result.errors == 0 and result.blocked == 0 and not (step.bad and #step.bad > 0)
	run.steps[#run.steps + 1] = result
end

local function Protected(step, fn)
	local ok, err = xpcall(function() fn(step) end, function(e) return Str(e) .. "\n" .. debugstack(2, 8, 0) end)
	if not ok then Expect(step, false, "exception: " .. err) end
end

RunNext = function()
	local step = table.remove(queue, 1)
	if not step then return Complete() end
	if InCombatLockdown() then return Complete("has entrado en combate") end
	run.count = run.count + 1
	step.n = run.count
	step.base = { errors = Total(session.errors), caught = Total(session.caught), blocked = Total(session.blocked) }
	current = step
	Banner(format("DevTest %d · %s · %s   no toques nada ni muevas el ratón", step.n, step.addon or "", step.label), 1, 0.85, 0.95)
	Protected(step, step.fn)
	C_Timer.After(step.wait, function()
		if step.tooltip then
			step.tooltipLines = TooltipLines(step.hovered)
			if not step.tooltipLines then Note(step, "tooltip", "none from this control") end
		end
		local root = step.addon and Window(step.addon)
		if step.texts and root and root:IsShown() then
			step.textList = Texts(root)
			step.bad = BadTexts(step.textList)
		end
		if step.tooltipLines then
			local bad = BadTexts(step.tooltipLines)
			if #bad > 0 then step.bad = bad end
		end
		local function Done()
			if step.after then Protected(step, step.after) end
			Finish(step)
			RunNext()
		end
		local budget = run.shotsLeft[step.addon or ""] or 0
		if step.shot and budget > 0 and Screenshot then
			run.shotsLeft[step.addon] = budget - 1
			step.shotAt = date("%H:%M:%S")
			Screenshot()
			C_Timer.After(0.9, Done)
		else
			Done()
		end
	end)
end

local function Start(only)
	if current then
		print("|cffff5ec4DevTest|r ya está en marcha")
		return
	end
	if InCombatLockdown() then
		print("|cffff5ec4DevTest|r no se puede en combate")
		return
	end
	InstallHandler()
	run = {
		startedAt = date("%Y-%m-%d %H:%M:%S"),
		env = Env(), addons = {}, steps = {}, count = 0, snapshots = {}, shotsLeft = {},
		base = { errors = Total(session.errors), caught = Total(session.caught), blocked = Total(session.blocked) },
		handlerInstalled = geterrorhandler() == handler,
	}
	queue = {}
	for _, name in ipairs(TARGETS) do
		run.addons[name] = AddonStatus(name)
		if not only or name:lower():find(only, 1, true) then
			run.shotsLeft[name] = SHOTS_PER_ADDON
			if run.addons[name].loaded then
				for _, s in ipairs(BUILDERS[name]()) do queue[#queue + 1] = s end
			end
		end
	end
	run.shotsLeft[""] = 0
	MorigollDevTestDB.run = run
	-- Our Forever data: have the client load every item while the other addons are tested.
	local D = nsOf.TreasureTrail and nsOf.TreasureTrail.ForeverData
	if D then
		for _, z in pairs(D.zones) do
			for itemID in pairs(z.items) do Safe(C_Item.RequestLoadItemDataByID, itemID) end
		end
		for _, inst in pairs(D.instances) do
			for _, b in ipairs(inst[4]) do
				for i = 1, #b[2], 2 do Safe(C_Item.RequestLoadItemDataByID, b[2][i]) end
			end
		end
	end
	RunNext()
end

-- Collections probe (/devtest probe) ----------------------------------------------------
-- What this client can tell about collections, to plan data of our own: which
-- APIs answer, whether known items exist, and the map ids of zones and instances.

-- Well-known vanilla collectibles (item ids), to see whether they exist and resolve.
local PROBE_MOUNT_ITEMS = {
	13335, -- Deathcharger's Reins (Baron Rivendare, Stratholme)
	19872, -- Swift Razzashi Raptor (Bloodlord Mandokir, Zul'Gurub)
	19902, -- Swift Zulian Tiger (High Priest Thekal, Zul'Gurub)
	21321, -- Red Qiraji Resonating Crystal (Ahn'Qiraj)
	13086, -- Reins of the Winterspring Frostsaber (quest)
	5665,  -- Horn of the Dire Wolf (orc vendor)
	13334, -- Green Skeletal Warhorse (undead vendor)
}
local PROBE_PET_ITEMS = {
	8494,  -- Parrot Cage (Hyacinth Macaw), pirates
	8485,  -- Cat Carrier (Bombay), vendor
	10822, -- Dark Whelpling
	8499,  -- Tiny Crimson Whelpling
	11474, -- Sprite Darter Egg
	11026, -- Tree Frog Box
	10398, -- Mechanical Chicken (quest)
}

local function ItemProbe(itemID)
	local r = { id = itemID }
	local name, link, quality, ilvl, minLevel, itemType, subType, _, equipLoc, icon, _, classID, subclassID = Safe(C_Item.GetItemInfo, itemID)
	r.name, r.quality, r.classID, r.subclassID, r.equipLoc = name, quality, classID, subclassID, equipLoc
	r.exists = Safe(C_Item.DoesItemExistByID, itemID)
	local spellName, spellID = Safe(C_Item.GetItemSpell, itemID)
	r.spell, r.spellID = spellName, spellID
	if C_MountJournal.GetMountFromItem then r.mountID = Safe(C_MountJournal.GetMountFromItem, itemID) end
	if r.mountID then
		local _, _, _, _, _, _, _, _, _, _, collected = Safe(C_MountJournal.GetMountInfoByID, r.mountID)
		r.mountCollected = collected
	end
	if C_PetJournal.GetPetInfoByItemID then
		local petName, _, _, _, _, _, _, _, _, _, _, _, speciesID = Safe(C_PetJournal.GetPetInfoByItemID, itemID)
		r.petName, r.speciesID = petName, speciesID
		if speciesID then r.petOwned = Safe(C_PetJournal.GetNumCollectedInfo, speciesID) end
	end
	if C_ToyBox and C_ToyBox.GetToyInfo then r.toy = Safe(C_ToyBox.GetToyInfo, itemID) ~= nil end
	if C_TransmogCollection and C_TransmogCollection.GetItemInfo then
		r.appearanceID, r.sourceID = Safe(C_TransmogCollection.GetItemInfo, itemID)
	end
	r.count = Safe(C_Item.GetItemCount, itemID, true)
	return r
end

local function BuildProbe()
	local probe = { at = date("%Y-%m-%d %H:%M:%S"), env = Env() }

	probe.expansion = { level = Safe(GetExpansionLevel), server = Safe(GetServerExpansionLevel), maxLevel = Safe(GetMaxLevelForPlayerExpansion) }

	-- Mount journal: the client's own list, with spell ids to match items against.
	local mounts, collected = {}, 0
	for _, id in ipairs(Safe(C_MountJournal.GetMountIDs) or {}) do
		local name, spellID, _, _, usable, sourceType, _, factionSpecific, faction, hide, isCollected = Safe(C_MountJournal.GetMountInfoByID, id)
		local _, description, source = Safe(C_MountJournal.GetMountInfoExtraByID, id)
		if isCollected then collected = collected + 1 end
		mounts[#mounts + 1] = format("%d|%s|%s|src%s|fac%s|%s|%s%s", id, Str(spellID), Str(name), Str(sourceType),
			factionSpecific and Str(faction) or "-", isCollected and "HAVE" or "no", hide and "hidden" or "shown",
			(source and source ~= "") and ("|" .. source) or "")
	end
	probe.mounts = { count = #mounts, collected = collected, list = mounts }

	-- Pets: journal counts, species that exist at all, and the old companion API.
	local pets = {}
	pets.numPets, pets.numOwned = Safe(C_PetJournal.GetNumPets)
	local species, examples = 0, {}
	for sid = 1, 6000 do
		local name, _, petType, _, source, _, _, _, _, _, obtainable = Safe(C_PetJournal.GetPetInfoBySpeciesID, sid)
		if name then
			species = species + 1
			if #examples < 12 then examples[#examples + 1] = format("%d %s obtainable=%s source=%s", sid, Str(name), Str(obtainable), Str(source)) end
		end
	end
	pets.speciesWithName = species
	pets.examples = examples
	if GetNumCompanions then
		pets.companions = Safe(GetNumCompanions, "CRITTER")
		pets.companionMounts = Safe(GetNumCompanions, "MOUNT")
	end
	probe.pets = pets

	-- Transmog: does the collection answer for what the player wears?
	local tm = { api = C_TransmogCollection ~= nil }
	if C_TransmogCollection then
		tm.slots = {}
		for slot = 1, 19 do
			local itemID = GetInventoryItemID("player", slot)
			if itemID then
				local appearanceID, sourceID = Safe(C_TransmogCollection.GetItemInfo, itemID)
				local has = Safe(C_TransmogCollection.PlayerHasTransmog, itemID)
				local hasSource = sourceID and Safe(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
				tm.slots[#tm.slots + 1] = format("slot %d item %d appearance %s source %s hasItem %s hasSource %s", slot, itemID, Str(appearanceID), Str(sourceID), Str(has), Str(hasSource))
			end
		end
	end
	probe.transmog = tm

	-- Toys
	if C_ToyBox then
		probe.toys = { num = Safe(C_ToyBox.GetNumToys), learned = Safe(C_ToyBox.GetNumLearnedDisplayedToys), total = Safe(C_ToyBox.GetNumTotalDisplayedToys) }
	end

	probe.mountItems, probe.petItems = {}, {}
	for _, id in ipairs(PROBE_MOUNT_ITEMS) do probe.mountItems[#probe.mountItems + 1] = ItemProbe(id) end
	for _, id in ipairs(PROBE_PET_ITEMS) do probe.petItems[#probe.petItems + 1] = ItemProbe(id) end

	-- Zones and instances under Azeroth, with their ui map ids.
	local function Children(mapType)
		local out = {}
		local list = Safe(C_Map.GetMapChildrenInfo, 947, mapType, true) or {}
		for _, info in ipairs(list) do
			local parent = Safe(C_Map.GetMapInfo, info.parentMapID)
			out[#out + 1] = format("%d|%s|parent %d %s", info.mapID, Str(info.name), info.parentMapID or 0, parent and Str(parent.name) or "?")
		end
		table.sort(out)
		return out
	end
	probe.zones = Children(Enum.UIMapType.Zone)
	probe.dungeons = Children(Enum.UIMapType.Dungeon)
	probe.instanceNow = { Safe(GetInstanceInfo) }

	-- Each zone's rectangle in world coordinates: maps creature spawns to zones.
	probe.zoneRects = {}
	for _, mapType in ipairs({ Enum.UIMapType.Continent, Enum.UIMapType.Zone }) do
		for _, info in ipairs(Safe(C_Map.GetMapChildrenInfo, 947, mapType, true) or {}) do
			local c1, p1 = Safe(C_Map.GetWorldPosFromMapPos, info.mapID, CreateVector2D(0, 0))
			local c2, p2 = Safe(C_Map.GetWorldPosFromMapPos, info.mapID, CreateVector2D(1, 1))
			if p1 and p2 then
				probe.zoneRects[#probe.zoneRects + 1] = format("%d|%d|%s|%s|%s|%s|%s|%d|%d", info.mapID, info.mapType,
					Str(c1), Str(p1.x), Str(p1.y), Str(p2.x), Str(p2.y), info.parentMapID or 0, c2 or -1) .. "|" .. Str(info.name)
			end
		end
	end

	-- Instance names by instance map id (what GetInstanceInfo returns inside).
	probe.instanceNames = {}
	for id = 1, 1000 do
		local name = Safe(GetRealZoneText, id)
		if name and name ~= "" then probe.instanceNames[#probe.instanceNames + 1] = id .. "|" .. name end
	end
	return probe
end

local function Probe()
	for _, id in ipairs(PROBE_MOUNT_ITEMS) do Safe(C_Item.RequestLoadItemDataByID, id) end
	for _, id in ipairs(PROBE_PET_ITEMS) do Safe(C_Item.RequestLoadItemDataByID, id) end
	Banner("DevTest · sonda de colecciones…", 1, 0.85, 0.95)
	C_Timer.After(3, function()
		local ok, result = xpcall(BuildProbe, function(e) return Str(e) .. "\n" .. debugstack(2, 8, 0) end)
		MorigollDevTestDB.probe = ok and result or { error = result }
		local text = ok and format("Sonda hecha: %d monturas (%d tuyas), %d especies de mascota. Haz /reload para guardarla.", result.mounts.count, result.mounts.collected, result.pets.speciesWithName)
			or "La sonda falló; haz /reload igualmente para guardar el error."
		Banner(text, 0.45, 0.9, 0.6)
		print("|cffff5ec4DevTest|r " .. text)
		C_Timer.After(20, function() if not current then banner:Hide() end end)
	end)
end

-- Zone grid (/devtest grid) --------------------------------------------------------------
-- Which zone covers each point of the two continent maps, read from the world
-- map's own zone shapes. Rows are run-length encoded: "zone*count,zone*count".
-- One row per frame, so the game does not freeze.

local GRID_SIZE = 400
local GRID_CONTINENTS = { 1414, 1415 } -- Kalimdor, Eastern Kingdoms

local function Grid()
	if current then return end
	local grid = { size = GRID_SIZE, at = date("%Y-%m-%d %H:%M:%S"), maps = {} }
	local c, row = 1, 0
	local rows = {}
	local ticker
	ticker = C_Timer.NewTicker(0, function()
		local mapID = GRID_CONTINENTS[c]
		local parts, last, count = {}, nil, 0
		local y = (row + 0.5) / GRID_SIZE
		for col = 0, GRID_SIZE - 1 do
			local info = Safe(C_Map.GetMapInfoAtPosition, mapID, (col + 0.5) / GRID_SIZE, y)
			local id = info and info.mapID or 0
			if id == last then
				count = count + 1
			else
				if last then parts[#parts + 1] = last .. "*" .. count end
				last, count = id, 1
			end
		end
		parts[#parts + 1] = last .. "*" .. count
		rows[#rows + 1] = table.concat(parts, ",")
		row = row + 1
		if row % 20 == 0 then Banner(format("DevTest · cuadrícula de zonas %d/%d · fila %d/%d", c, #GRID_CONTINENTS, row, GRID_SIZE), 1, 0.85, 0.95) end
		if row >= GRID_SIZE then
			grid.maps[mapID] = rows
			rows, row, c = {}, 0, c + 1
			if c > #GRID_CONTINENTS then
				ticker:Cancel()
				MorigollDevTestDB.grid = grid
				local text = "Cuadrícula hecha. Haz /reload para guardarla."
				Banner(text, 0.45, 0.9, 0.6)
				print("|cffff5ec4DevTest|r " .. text)
				C_Timer.After(20, function() if not current then banner:Hide() end end)
			end
		end
	end)
end

SLASH_MORIGOLLDEVTEST1 = "/devtest"
SlashCmdList.MORIGOLLDEVTEST = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "status" then
		print(format("|cffff5ec4DevTest|r session: %d Lua errors, %d caught, %d blocked, %d warnings; handler %s",
			Total(session.errors), Total(session.caught), Total(session.blocked), Total(session.warnings),
			geterrorhandler() == handler and "installed" or "NOT installed"))
	elseif msg == "probe" or msg == "sonda" then
		Probe()
	elseif msg == "grid" then
		Grid()
	elseif msg == "stop" then
		if current then Complete("parado a mano") end
	else
		Start(msg ~= "" and msg or nil)
	end
end
