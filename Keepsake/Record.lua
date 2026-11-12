local addonName, ns = ...
local L = ns.L

-- Entry types: colour of the timeline dot, fallback icon, and the filter they sit under.
ns.TYPES = {
	start = { color = { 0.75, 0.76, 0.82 }, icon = "Interface\\Icons\\INV_Misc_Book_09", group = "all" },
	level = { color = { 1, 0.82, 0.25 }, icon = "Interface\\Icons\\Achievement_Level_10", group = "level" },
	achievement = { color = { 1, 0.6, 0.2 }, group = "achievement" },
	boss = { color = { 0.95, 0.35, 0.3 }, icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", group = "boss" },
	mplus = { color = { 0.72, 0.48, 1 }, group = "boss" },
	loot = { color = { 0.64, 0.21, 0.93 }, group = "loot" },
	mount = { color = { 0.3, 0.85, 0.95 }, group = "collection" },
	pet = { color = { 0.4, 0.9, 0.5 }, group = "collection" },
	toy = { color = { 0.95, 0.5, 0.75 }, group = "collection" },
	renown = { color = { 0.4, 0.7, 1 }, icon = "Interface\\Icons\\Achievement_Reputation_01", group = "renown" },
	zone = { color = { 0.55, 0.78, 0.55 }, icon = "Interface\\Icons\\INV_Misc_Map_01", group = "zone" },
	note = { color = { 0.93, 0.9, 0.78 }, icon = "Interface\\Icons\\INV_Misc_Note_01", group = "note" },
}

-- WoW Forever (interface 16001) runs vanilla content on the retail client:
-- no renown, and a rare item is a milestone there the way an epic is later on.
ns.vanilla = select(4, GetBuildInfo()) < 20000

-- Lowest item quality written down as loot; the settings menu changes it.
function ns.LootQuality()
	return ns.db.lootQuality or (ns.vanilla and Enum.ItemQuality.Rare or Enum.ItemQuality.Epic)
end

-- Moments worth a screenshot when automatic screenshots are on.
local SHOT_TYPES = { level = true, achievement = true, boss = true, mplus = true, mount = true }
-- A boss kill can bring its achievement and its mount in the same second: one
-- screenshot covers them all.
local SHOT_GAP = 5
local lastShot

-- Bumped whenever entries are added, so the window knows its sorted list is stale.
ns.version = 0

local DEFAULTS = { chars = {}, screenshots = true, filter = "all" }

local function ZoneLabel()
	local zone, sub = GetRealZoneText() or "", GetSubZoneText() or ""
	if sub ~= "" and sub ~= zone then
		return sub .. ", " .. zone
	end
	return zone
end

local function Char()
	local guid = UnitGUID("player")
	local c = ns.db.chars[guid]
	if not c then
		local className, classFile = UnitClass("player")
		c = {
			name = UnitName("player"),
			realm = GetRealmName(),
			class = classFile,
			created = time(),
			entries = {},
			seen = { zones = {}, bosses = {}, ach = {} },
		}
		ns.db.chars[guid] = c
		ns.Add({
			type = "start",
			title = L.Started,
			detail = format("%s %s · %d", UnitRace("player") or "", className or "", UnitLevel("player")),
		}, c)
	end
	c.level = UnitLevel("player")
	return c
end
ns.Char = Char

function ns.Add(entry, c)
	c = c or Char()
	entry.t = entry.t or time()
	if not entry.imported then
		entry.zone = entry.zone or ZoneLabel()
	end
	table.insert(c.entries, entry)
	ns.version = ns.version + 1
	if ns.db.screenshots and SHOT_TYPES[entry.type] and not entry.imported then
		entry.shot = true
		local now = GetTime()
		if not lastShot or now - lastShot >= SHOT_GAP then
			lastShot = now
			C_Timer.After(1.5, Screenshot) -- let the level-up or achievement banner show first
		end
	end
	if ns.Refresh then ns.Refresh() end
end

-- Notes are the player's own entries.
function ns.AddNote(text)
	text = strtrim(text or "")
	if text == "" then return false end
	ns.Add({ type = "note", title = text })
	return true
end

function ns.DeleteEntry(char, entry)
	for i, e in ipairs(char.entries) do
		if e == entry then
			table.remove(char.entries, i)
			ns.version = ns.version + 1
			if ns.Refresh then ns.Refresh() end
			return true
		end
	end
	return false
end

-- Events ------------------------------------------------------------------------

local handlers = {}

function handlers.PLAYER_LEVEL_UP(level)
	ns.Add({ type = "level", level = level, title = L.ReachedLevel:format(level) })
end

function handlers.ACHIEVEMENT_EARNED(id)
	local _, name, points, _, _, _, _, _, _, icon, _, isGuild = GetAchievementInfo(id)
	local c = Char()
	if not name or isGuild or c.seen.ach[id] then return end
	c.seen.ach[id] = true
	ns.Add({ type = "achievement", id = id, title = name, icon = icon, detail = points > 0 and L.Points:format(points) or nil })
end

function handlers.ENCOUNTER_END(encounterID, encounterName, difficultyID, _, success)
	if success ~= 1 then return end
	local c = Char()
	local key = encounterID .. ":" .. difficultyID
	if c.seen.bosses[key] then return end
	c.seen.bosses[key] = true
	local instanceName, _, _, difficultyName = GetInstanceInfo()
	ns.Add({
		type = "boss",
		title = L.Defeated:format(encounterName),
		detail = difficultyName and difficultyName ~= "" and (instanceName .. " · " .. difficultyName) or instanceName,
	})
end

function handlers.CHALLENGE_MODE_COMPLETED()
	local info = C_ChallengeMode.GetChallengeCompletionInfo()
	if not info or info.practiceRun or not info.mapChallengeModeID then return end
	local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(info.mapChallengeModeID)
	local seconds = math.floor((info.time or 0) / 1000)
	local clock = format("%d:%02d", seconds / 60, seconds % 60)
	ns.Add({
		type = "mplus",
		title = L.MythicPlus:format(info.level, name or "?"),
		detail = info.onTime and L.InTime:format(info.keystoneUpgradeLevels or 0, clock) or L.Depleted:format(clock),
		icon = texture,
	})
end

-- The same drop can arrive twice: as a loot chat line and as a loot toast.
local recentLoot = {}

local function RecordLoot(link)
	-- Keyed by item ID: the two links may differ in their trailing fields
	local itemID, now = C_Item.GetItemInfoInstant(link), GetTime()
	if not itemID or (recentLoot[itemID] and now - recentLoot[itemID] < 10) then return end
	recentLoot[itemID] = now
	local quality = C_Item.GetItemQualityByID(link)
	if not quality or quality < ns.LootQuality() then return end
	if quality < Enum.ItemQuality.Legendary and not C_Item.IsEquippableItem(link) then return end
	local ilvl = C_Item.GetDetailedItemLevelInfo(link)
	ns.Add({
		type = "loot",
		link = link,
		title = link,
		icon = C_Item.GetItemIconByID(link),
		detail = ilvl and L.ItemLevel:format(ilvl) or nil,
	})
end

local function OnItemLoaded(link)
	local item = Item:CreateFromItemLink(link)
	if item:IsItemEmpty() then return end
	item:ContinueOnItemLoad(function() RecordLoot(link) end)
end

function handlers.CHAT_MSG_LOOT(text, playerName, _, _, _, _, _, _, _, _, _, guid)
	-- Since 12.0 chat text can be a secret value in instances; the loot toast covers that case
	if issecretvalue and (issecretvalue(text) or issecretvalue(playerName) or issecretvalue(guid)) then return end
	local me = UnitGUID("player")
	if guid ~= me and Ambiguate(playerName or "", "short") ~= UnitName("player") then return end
	local link = text and text:match("|c[^|]+|Hitem:.-|h|r")
	if link then OnItemLoaded(link) end
end

function handlers.SHOW_LOOT_TOAST(typeIdentifier, link)
	if typeIdentifier ~= "item" or not link or (issecretvalue and issecretvalue(link)) then return end
	OnItemLoaded(link)
end

function handlers.NEW_MOUNT_ADDED(mountID)
	local name, spellID, icon = C_MountJournal.GetMountInfoByID(mountID)
	if name then
		ns.Add({ type = "mount", title = name, icon = icon, spellID = spellID, detail = L.NewMount })
	end
end

function handlers.NEW_PET_ADDED(petGUID)
	local speciesID, _, _, _, _, _, _, name, icon = C_PetJournal.GetPetInfoByPetID(petGUID)
	-- Only the first of a species is a milestone
	if speciesID and C_PetJournal.GetNumCollectedInfo(speciesID) <= 1 then
		ns.Add({ type = "pet", title = name, icon = icon, speciesID = speciesID, detail = L.NewPet })
	end
end

function handlers.NEW_TOY_ADDED(itemID)
	local item = Item:CreateFromItemID(itemID)
	item:ContinueOnItemLoad(function()
		local _, name, icon = C_ToyBox.GetToyInfo(itemID)
		ns.Add({ type = "toy", title = name or item:GetItemName(), icon = icon, itemID = itemID, detail = L.NewToy })
	end)
end

function handlers.MAJOR_FACTION_RENOWN_LEVEL_CHANGED(factionID, newLevel, oldLevel)
	if not newLevel or (oldLevel and newLevel <= oldLevel) then return end
	local data = C_MajorFactions.GetMajorFactionData(factionID)
	if data then
		ns.Add({ type = "renown", title = L.RenownLevel:format(data.name, newLevel) })
	end
end

-- First visit to each zone, dungeon, raid, delve or scenario. Battlegrounds and
-- arenas repeat too often to be milestones.
local function CheckPlace()
	local c = Char()
	local key, name, kind
	local inInstance, instanceType = IsInInstance()
	if inInstance then
		if instanceType == "pvp" or instanceType == "arena" then return end
		local instanceName, _, _, difficultyName, _, _, _, instanceID = GetInstanceInfo()
		key, name, kind = "i" .. instanceID, instanceName, difficultyName
	else
		local mapID = C_Map.GetBestMapForUnit("player")
		local info = mapID and C_Map.GetMapInfo(mapID)
		while info and info.mapType > Enum.UIMapType.Zone and info.parentMapID and info.parentMapID > 0 do
			info = C_Map.GetMapInfo(info.parentMapID)
		end
		if not info or info.mapType ~= Enum.UIMapType.Zone then return end
		key, name = "z" .. info.mapID, info.name
		local parent = info.parentMapID and C_Map.GetMapInfo(info.parentMapID)
		kind = parent and parent.name
	end
	if not name or name == "" or c.seen.zones[key] then return end
	c.seen.zones[key] = true
	ns.Add({ type = "zone", title = name, detail = kind and kind ~= "" and (L.FirstVisit .. " · " .. kind) or L.FirstVisit, zone = name })
end

handlers.ZONE_CHANGED_NEW_AREA = function() C_Timer.After(2, CheckPlace) end

function handlers.PLAYER_ENTERING_WORLD(isLogin, isReload)
	Char()
	C_Timer.After(2, CheckPlace)
	if isLogin then
		print("|cffffc259" .. L.Title .. "|r " .. L.Loaded)
	end
end

-- Achievements earned before the addon existed: every completed one this
-- character earned, dated at noon of its day (the game keeps no time).
function ns.ImportAchievements(onProgress, onDone)
	local c = Char()
	local cats = GetCategoryList()
	local visited, added, index = {}, 0, 0

	local function Consider(id)
		if not id or visited[id] then return end
		visited[id] = true
		local _, name, points, completed, month, day, year, _, _, icon, _, isGuild, wasEarnedByMe = GetAchievementInfo(id)
		if completed and wasEarnedByMe and not isGuild and not c.seen.ach[id] and year then
			c.seen.ach[id] = true
			table.insert(c.entries, {
				type = "achievement", id = id, title = name, icon = icon, imported = true,
				detail = points > 0 and L.Points:format(points) or nil,
				t = time({ year = 2000 + year, month = month, day = day, hour = 12 }),
			})
			added = added + 1
		end
		Consider(GetPreviousAchievement(id))
	end

	local ticker
	ticker = C_Timer.NewTicker(0, function()
		for _ = 1, 4 do
			index = index + 1
			local cat = cats[index]
			if not cat then
				ticker:Cancel()
				c.imported = true
				ns.version = ns.version + 1
				onDone(added)
				if ns.Refresh then ns.Refresh() end
				return
			end
			for i = 1, GetCategoryNumAchievements(cat, true) do
				Consider((GetAchievementInfo(cat, i)))
			end
		end
		onProgress(added)
	end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
for event in pairs(handlers) do
	f:RegisterEvent(event)
end
f:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= addonName then return end
		KeepsakeDB = KeepsakeDB or {}
		for k, v in pairs(DEFAULTS) do
			if KeepsakeDB[k] == nil then KeepsakeDB[k] = type(v) == "table" and {} or v end
		end
		ns.db = KeepsakeDB
		ns.CreateMinimapButton({
			name = "KeepsakeMinimapButton",
			icon = "Interface\\Icons\\INV_Misc_Book_11",
			angle = 225,
			onClick = function() ns.Toggle() end,
			hiddenText = "|cffffc259" .. L.Title .. "|r " .. L.MinimapHidden,
			tooltip = function(tt)
				tt:AddLine(L.Title, 1, 0.76, 0.35)
				local c = ns.db.chars[UnitGUID("player") or ""]
				if c then tt:AddLine(L.Entries:format(#c.entries), 1, 1, 1) end
				tt:AddLine(" ")
				tt:AddLine(L.MinimapClick, 0.56, 0.59, 0.65)
				tt:AddLine(L.MinimapDrag, 0.56, 0.59, 0.65)
				tt:AddLine(L.MinimapRight, 0.56, 0.59, 0.65)
			end,
		})
		return
	end
	if not ns.db then return end
	local ok, err = pcall(handlers[event], ...)
	if ok then return end
	if ns.onError then ns.onError(event, err) end -- set by a test harness, if any
	if ns.debug then print("|cffffc259Keepsake|r", event, err) end
end)

SLASH_KEEPSAKE1 = "/keepsake"
SLASH_KEEPSAKE2 = "/cronica"
SLASH_KEEPSAKE3 = "/diario"
SlashCmdList.KEEPSAKE = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "debug" then
		ns.debug = not ns.debug
		print("|cffffc259Keepsake|r debug", ns.debug and "on" or "off")
	elseif cmd == "boton" or cmd == "botón" or cmd == "button" or cmd == "minimap" then
		ns.SetMinimapHidden(not ns.db.minimapHide)
	elseif cmd == "note" or cmd == "nota" then
		print("|cffffc259" .. L.Title .. "|r " .. (ns.AddNote(rest) and L.NoteAdded or L.NoteUsage))
	elseif cmd == "scale" or cmd == "escala" then
		local n = tonumber((rest:gsub("%%", ""))) or 1
		if n > 3 then n = n / 100 end
		ns.SetScale(n)
	else
		ns.Toggle()
	end
end

function Keepsake_OnAddonCompartmentClick()
	ns.Toggle()
end

BINDING_HEADER_KEEPSAKE = L.Title
BINDING_NAME_KEEPSAKE_TOGGLE = L.Title
function Keepsake_Toggle()
	ns.Toggle()
end
