local addonName, ns = ...
local L = ns.L

-- Mounts that never come from the world: promotions, trading card game, shop, trading post.
local EXCLUDED_MOUNT_SOURCES = { [8] = true, [9] = true, [10] = true, [12] = true }
local MAX_SPECIES = 6000
-- Difficulties the Adventure Guide lists, most rewarding first.
local DIFFICULTIES = { 16, 15, 14, 17, 23, 2, 1, 6, 5, 4, 3, 9, 33 }

local function Clean(s)
	s = (s or ""):gsub("|c%x%x%x%x%x%x%x%x", "")
	s = s:gsub("|r", ""):gsub("|n", "\n")
	return strtrim(s)
end

-- Collection index ----------------------------------------------------------------
-- Source texts never change during a session, so they are read once; whether
-- something is collected is checked again on every scan.

local index = {}

local function BuildMounts()
	local mounts = {}
	for _, id in ipairs(C_MountJournal.GetMountIDs()) do
		local name, spellID, icon, _, _, sourceType, _, _, _, hide = C_MountJournal.GetMountInfoByID(id)
		if name and not hide and not EXCLUDED_MOUNT_SOURCES[sourceType] then
			local _, _, source = C_MountJournal.GetMountInfoExtraByID(id)
			source = Clean(source)
			if source ~= "" then
				mounts[#mounts + 1] = { kind = "mount", id = id, name = name, spellID = spellID, icon = icon, source = source }
			end
		end
	end
	return mounts
end

function ns.BuildIndex(done)
	if index.pets then return done() end
	if index.waiting then
		table.insert(index.waiting, done)
		return
	end
	index.waiting = { done }
	index.mounts = BuildMounts()

	-- Species ids are sparse; walk them a few hundred per frame.
	local pets, species = {}, 0
	local ticker
	ticker = C_Timer.NewTicker(0, function()
		for _ = 1, 400 do
			species = species + 1
			local name, icon, _, _, source, _, isWild, _, _, _, obtainable = C_PetJournal.GetPetInfoBySpeciesID(species)
			if name and obtainable and source and source ~= "" then
				pets[#pets + 1] = { kind = "pet", id = species, name = name, icon = icon, source = Clean(source), wild = isWild }
			end
			if species >= MAX_SPECIES then
				ticker:Cancel()
				index.pets = pets
				local waiting = index.waiting
				index.waiting = nil
				for _, cb in ipairs(waiting) do cb() end
				return
			end
		end
	end)
end

-- Where am I --------------------------------------------------------------------------

function ns.CurrentZone()
	local mapID = C_Map.GetBestMapForUnit("player")
	local info = mapID and C_Map.GetMapInfo(mapID)
	while info and info.mapType > Enum.UIMapType.Zone and info.parentMapID and info.parentMapID > 0 do
		info = C_Map.GetMapInfo(info.parentMapID)
	end
	return info, mapID
end

-- The Adventure Guide instance for the map the player stands on: from the
-- instance's game map, else walking up the UI maps (a raid wing's map may not
-- be linked itself) where the older EJ_GetInstanceForMap still exists.
local function JournalInstanceForPlayer(mapID)
	local gameMapID = select(8, GetInstanceInfo())
	local id = gameMapID and C_EncounterJournal.GetInstanceForGameMap and C_EncounterJournal.GetInstanceForGameMap(gameMapID)
	if id and id > 0 then return id end
	if not EJ_GetInstanceForMap then return end
	while mapID and mapID > 0 do
		local id = EJ_GetInstanceForMap(mapID)
		if id and id > 0 then return id end
		local info = C_Map.GetMapInfo(mapID)
		if not info or info.mapType <= Enum.UIMapType.Zone then return end
		mapID = info.parentMapID
	end
end

-- Open-world collectibles ---------------------------------------------------------------

local function ByName(a, b) return a.name < b.name end

function ns.ScanZone(zoneName)
	local out = { mounts = {}, pets = {}, wild = {} }
	if not zoneName or zoneName == "" or not index.pets then return out end
	for _, m in ipairs(index.mounts) do
		if m.source:find(zoneName, 1, true) then
			local collected = select(11, C_MountJournal.GetMountInfoByID(m.id))
			if not collected then table.insert(out.mounts, m) end
		end
	end
	for _, p in ipairs(index.pets) do
		if p.source:find(zoneName, 1, true) and C_PetJournal.GetNumCollectedInfo(p.id) == 0 then
			table.insert(p.wild and out.wild or out.pets, p)
		end
	end
	table.sort(out.mounts, ByName)
	table.sort(out.pets, ByName)
	table.sort(out.wild, ByName)
	return out
end

-- Instance loot -----------------------------------------------------------------------------

-- What a loot item would add to the collection, or nil when it adds nothing.
-- Returns "pending" while the item's data is not cached yet.
local function Collectible(itemID, link)
	local mountID = C_MountJournal.GetMountFromItem(itemID)
	if mountID and mountID > 0 then
		local _, spellID, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
		if not collected then return "mount", { mountID = mountID, spellID = spellID } end
		return
	end
	local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(itemID))
	if speciesID then
		if C_PetJournal.GetNumCollectedInfo(speciesID) == 0 then return "pet", { speciesID = speciesID } end
		return
	end
	local toyID, toyName = C_ToyBox.GetToyInfo(itemID)
	if toyID and toyName then
		if not PlayerHasToy(itemID) then return "toy", { itemID = itemID } end
		return
	end
	local _, sourceID = C_TransmogCollection.GetItemInfo(link)
	if not sourceID then
		return C_Item.IsItemDataCachedByID(itemID) and nil or "pending"
	end
	local info = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
	if not info and ns.Forever then
		-- WoW Forever often has no appearance info for a source; ask about the source itself
		info = { appearanceIsCollected = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID) }
	end
	if info and not info.appearanceIsCollected then
		local hasData, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
		if not hasData then return "pending" end
		if ns.Forever then canCollect = ns.Forever.CanCollect(itemID) end
		if canCollect then return "appearance", { sourceID = sourceID } end
	end
end
ns.Collectible = Collectible

-- Boss names killed this lockout, from the saved-instance list; any
-- difficulty when difficultyID is nil.
local function KilledBosses(instanceName, difficultyID)
	local killed = {}
	-- Undocumented; if a client drops it, bosses just stop showing as killed
	if not GetSavedInstanceEncounterInfo then return killed end
	for i = 1, GetNumSavedInstances() do
		local name, _, reset, diff, locked, _, _, _, _, _, numEncounters = GetSavedInstanceInfo(i)
		if locked and reset > 0 and name == instanceName and (not difficultyID or diff == difficultyID) then
			for e = 1, numEncounters do
				local bossName, _, isKilled = GetSavedInstanceEncounterInfo(i, e)
				if isKilled and bossName then killed[bossName] = true end
			end
		end
	end
	return killed
end
ns.KilledBosses = KilledBosses

-- Reads an instance's loot through the Adventure Guide API. The guide's own
-- filters are put back afterwards so the Adventure Guide window is unaffected.
function ns.ScanInstance(journalInstanceID, difficultyID)
	if ns.Forever then return ns.Forever.ScanInstance(journalInstanceID) end
	if EncounterJournal and EncounterJournal:IsShown() then
		return nil, "busy"
	end
	local prevClass, prevSpec = EJ_GetLootFilter()
	local prevSlot = C_EncounterJournal.GetSlotFilter()
	local prevDifficulty = EJ_GetDifficulty()

	EJ_SelectInstance(journalInstanceID)
	local instanceName = EJ_GetInstanceInfo(journalInstanceID)
	local difficulties = {}
	for _, d in ipairs(DIFFICULTIES) do
		if EJ_IsValidInstanceDifficulty(d) then difficulties[#difficulties + 1] = d end
	end
	if not difficultyID or not EJ_IsValidInstanceDifficulty(difficultyID) then
		difficultyID = difficulties[1]
	end
	if difficultyID then EJ_SetDifficulty(difficultyID) end
	local _, _, classID = UnitClass("player")
	EJ_SetLootFilter(classID, 0)
	C_EncounterJournal.SetSlotFilter(Enum.ItemSlotFilterType.NoFilter)

	-- Bosses in journal order
	local bosses, byEncounter = {}, {}
	local i = 1
	while true do
		local name, _, encounterID = EJ_GetEncounterInfoByIndex(i, journalInstanceID)
		if not name then break end
		local boss = { name = name, items = {} }
		bosses[#bosses + 1] = boss
		byEncounter[encounterID] = boss
		i = i + 1
	end

	local pending, count = false, 0
	for n = 1, EJ_GetNumLoot() do
		local info = C_EncounterJournal.GetLootInfoByIndex(n)
		if info and info.itemID then
			local kind, extra
			if info.link then
				kind, extra = Collectible(info.itemID, info.link)
			else
				kind = "pending"
			end
			if kind == "pending" then
				pending = true
			elseif kind then
				local boss = byEncounter[info.encounterID]
				if boss then
					local item = extra or {}
					item.kind, item.itemID, item.link, item.name, item.icon = kind, info.itemID, info.link, info.name, info.icon
					item.slot = info.slot
					table.insert(boss.items, item)
					count = count + 1
				end
			end
		end
	end

	EJ_SetLootFilter(prevClass or 0, prevSpec or 0)
	if prevSlot then C_EncounterJournal.SetSlotFilter(prevSlot) end
	if prevDifficulty and EJ_IsValidInstanceDifficulty(prevDifficulty) then EJ_SetDifficulty(prevDifficulty) end

	local killed = KilledBosses(instanceName, difficultyID)
	for _, boss in ipairs(bosses) do boss.killed = killed[boss.name] end

	return {
		id = journalInstanceID,
		name = instanceName,
		difficultyID = difficultyID,
		difficulties = difficulties,
		bosses = bosses,
		count = count,
	}, pending and "pending" or nil
end

-- The whole picture for where the player stands -----------------------------------------------

function ns.Scan()
	local zone, mapID = ns.CurrentZone()
	local state = {
		zoneName = zone and zone.name or GetRealZoneText(),
		zoneMapID = zone and zone.mapID,
	}
	local inInstance = IsInInstance()
	if inInstance then
		-- Sources name the instance ("Zone: Icecrown Citadel"), not the zone outside
		state.zoneName = GetInstanceInfo()
		local journalID
		if ns.Forever then
			journalID = ns.Forever.InstanceForPlayer()
		else
			journalID = JournalInstanceForPlayer(mapID)
		end
		if journalID then
			local _, _, difficultyID = GetInstanceInfo()
			state.instance, state.instanceStatus = ns.ScanInstance(journalID, difficultyID)
		end
	end

	local found = ns.Forever and ns.Forever.ZoneItems(not inInstance and state.zoneMapID) or ns.ScanZone(state.zoneName)
	state.mounts, state.pets, state.wild = found.mounts, found.pets, found.wild
	state.zonePending = found.pending

	-- A boss mount shows under its boss; drop it from the zone list
	if state.instance then
		local fromBosses = {}
		for _, boss in ipairs(state.instance.bosses) do
			for _, item in ipairs(boss.items) do
				if item.mountID then fromBosses[item.mountID] = true end
			end
		end
		for i = #state.mounts, 1, -1 do
			if fromBosses[state.mounts[i].id] then table.remove(state.mounts, i) end
		end
	end

	state.total = #state.mounts + #state.pets + #state.wild + (state.instance and state.instance.count or 0)

	-- WoW Forever's client has no mount or pet source texts and an empty
	-- Adventure Guide: an empty list there means "unknown", not "all collected".
	-- (Unless our own data for it is loaded: see Forever.lua.)
	local tiers = EJ_GetNumTiers and EJ_GetNumTiers() or 0
	state.noData = not ns.Forever and index.pets ~= nil and #index.mounts == 0 and #index.pets == 0 and tiers == 0

	if not inInstance and state.zoneMapID and ns.Forever then
		state.entrances = ns.Forever.Entrances(state.zoneMapID)
	elseif not inInstance and state.zoneMapID then
		local ok, entrances = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, state.zoneMapID)
		state.entrances = ok and entrances or {}
	end
	return state
end
