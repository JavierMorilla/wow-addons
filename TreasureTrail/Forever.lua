local _, ns = ...
local L = ns.L

-- WoW Forever: its client has no source texts for mounts or pets and no
-- Adventure Guide, so what each zone and boss offers comes from our own table
-- (ForeverData.lua). The game still says what the player owns.

local D = ns.ForeverData
if not D then return end

local F = {}
ns.Forever = F

local spanish = GetLocale() == "esES" or GetLocale() == "esMX"
local MAX_SOURCES = 3

-- Content patch: the VMaNGOS index (0 = 1.2 ... 10 = 1.12) from the client
-- version, read as 1.<digit> ("1.60.1" = patch 1.6). Content from a later
-- patch still shows, marked with the patch it arrives in.
local function ContentPatch()
	local minor = tonumber((GetBuildInfo()):match("^1%.(%d+)"))
	if not minor then return 10 end
	if minor >= 13 then minor = math.floor(minor / 10) end
	return math.max(0, math.min(10, minor - 2))
end
local CURRENT_PATCH = ContentPatch()

local function PatchName(index)
	return "1." .. (index + 2)
end

local function Localized(entry)
	if not entry then return "?" end
	if spanish and entry[2] and entry[2] ~= "" then return entry[2] end
	return entry[1]
end

local function NpcName(id) return Localized(D.npcs[id]) end

function F.InstanceName(id)
	local name = GetRealZoneText(id)
	if name and name ~= "" then return name end
	local inst = D.instances[id]
	return inst and inst[1] or "?"
end

local playerRaceBit
local function RaceAllowed(mask)
	if not mask or mask == 0 then return true end
	if not playerRaceBit then
		local raceID = select(3, UnitRace("player")) or 0
		playerRaceBit = raceID > 0 and bit.lshift(1, raceID - 1) or 0
	end
	return bit.band(mask, playerRaceBit) ~= 0
end

local function Chance(c)
	if not c or c <= 0 then return "" end
	if c >= 10 then return format(" (%d%%)", math.floor(c + 0.5)) end
	if c >= 1 then return format(" (%.1f%%)", c) end
	return format(" (%.2f%%)", c)
end

-- The lines for an item's sources, best first; nil if none applies to this character.
local function SourceText(sources)
	local lines = {}
	local sorted = {}
	for _, s in ipairs(sources) do
		local kind = s[1]
		if kind ~= "q" or RaceAllowed(D.quests[s[2]] and D.quests[s[2]][3]) then sorted[#sorted + 1] = s end
	end
	-- Vendors and quests first (certain), then drops by chance
	table.sort(sorted, function(a, b)
		local ca = (a[1] == "v" or a[1] == "q") and 1000 or (a[3] or 0)
		local cb = (b[1] == "v" or b[1] == "q") and 1000 or (b[3] or 0)
		return ca > cb
	end)
	for i, s in ipairs(sorted) do
		if i > MAX_SOURCES then
			lines[#lines + 1] = L.SrcMore:format(#sorted - MAX_SOURCES)
			break
		end
		local kind = s[1]
		if kind == "d" then
			lines[#lines + 1] = L.SrcDrop:format(NpcName(s[2])) .. Chance(s[3])
		elseif kind == "o" then
			lines[#lines + 1] = L.SrcObject:format(Localized(D.objects[s[2]])) .. Chance(s[3])
		elseif kind == "v" then
			lines[#lines + 1] = L.SrcVendor:format(NpcName(s[2]))
		elseif kind == "q" then
			lines[#lines + 1] = L.SrcQuest:format(Localized(D.quests[s[2]]))
		end
	end
	if #lines == 0 then return nil end
	return table.concat(lines, "\n")
end

local function PatchNote(patch)
	if patch and patch > CURRENT_PATCH then return L.FromPatch:format(PatchName(patch)) end
end

-- Mounts and pets of a zone that the player does not have yet. The journals
-- only match an item to its mount or pet once the item is cached, so uncached
-- items are requested and out.pending asks for another scan.
function F.ZoneItems(zoneMapID)
	local out = { mounts = {}, pets = {}, wild = {} }
	local zone = zoneMapID and D.zones[zoneMapID]
	if not zone then return out end
	for itemID, e in pairs(zone.items) do
		local kind, races, patch, sources = e[1], e[2], e[3], e[4]
		local source = RaceAllowed(races) and SourceText(sources)
		if source and not C_Item.IsItemDataCachedByID(itemID) then
			if C_Item.DoesItemExistByID(itemID) then
				C_Item.RequestLoadItemDataByID(itemID)
				out.pending = true
			end
		elseif source then
			local note = PatchNote(patch)
			if note then source = source .. "\n" .. note end
			if kind == "mount" then
				local mountID = C_MountJournal.GetMountFromItem(itemID)
				if mountID and mountID > 0 then
					local name, spellID, icon, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
					if name and not collected then
						table.insert(out.mounts, { kind = "mount", id = mountID, mountID = mountID, spellID = spellID, itemID = itemID, name = name, icon = icon, source = source })
					end
				end
			elseif kind == "pet" then
				local name, icon, _, _, _, _, _, _, _, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
				if speciesID and C_PetJournal.GetNumCollectedInfo(speciesID) == 0 then
					table.insert(out.pets, { kind = "pet", id = speciesID, speciesID = speciesID, itemID = itemID, name = name or "?", icon = icon, source = source })
				end
			end
		end
	end
	local function ByName(a, b) return a.name < b.name end
	table.sort(out.mounts, ByName)
	table.sort(out.pets, ByName)
	return out
end

-- Whether this class can collect an item's appearance. WoW Forever's client
-- answers "no" to every source, so the retail rules are applied here: weapons
-- the class could learn in vanilla, armor of its own type only, and cloaks,
-- shirts, tabards and held-in-hand items for everyone.
local W = { -- item subclasses of weapons (class 2) by class id
	[1] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, -- Warrior
	[2] = { 0, 1, 4, 5, 6, 7, 8 }, -- Paladin
	[3] = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, -- Hunter
	[4] = { 2, 3, 4, 7, 13, 15, 16, 18 }, -- Rogue
	[5] = { 4, 10, 15, 19 }, -- Priest
	[7] = { 0, 1, 4, 5, 10, 13, 15 }, -- Shaman
	[8] = { 7, 10, 15, 19 }, -- Mage
	[9] = { 7, 10, 15, 19 }, -- Warlock
	[11] = { 4, 5, 10, 13, 15 }, -- Druid
}
local ARMOR = { [1] = 4, [2] = 4, [3] = 3, [7] = 3, [4] = 2, [11] = 2, [5] = 1, [8] = 1, [9] = 1 }
local SHIELD = { [1] = true, [2] = true, [7] = true }
local weapons
function F.CanCollect(itemID)
	local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	local class = select(3, UnitClass("player"))
	if classID == 2 then
		if not weapons then
			weapons = {}
			for _, sub in ipairs(W[class] or {}) do weapons[sub] = true end
		end
		return weapons[subclassID] == true
	elseif classID == 4 then
		if equipLoc == "INVTYPE_CLOAK" or subclassID == 0 then return true end
		if subclassID == 6 then return SHIELD[class] == true end
		return ARMOR[class] == subclassID
	end
	return false
end

-- Dungeons and raids whose entrance is in this zone.
function F.Entrances(zoneMapID)
	local list = {}
	local zone = zoneMapID and D.zones[zoneMapID]
	if not zone then return list end
	for _, id in ipairs(zone.entrances) do
		local inst = D.instances[id]
		if inst then
			list[#list + 1] = {
				journalInstanceID = id,
				name = F.InstanceName(id),
				atlasName = inst[2] and "Raid" or "Dungeon",
				description = PatchNote(inst[3]) or "",
			}
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

-- The instance the player is in, by its map id, if we have its loot.
function F.InstanceForPlayer()
	local id = select(8, GetInstanceInfo())
	if id and D.instances[id] then return id end
end

-- Same result shape as ns.ScanInstance, from our boss lists.
function F.ScanInstance(id)
	local inst = D.instances[id]
	if not inst then return nil end
	local name = F.InstanceName(id)
	local bosses, pending, count = {}, false, 0
	for _, b in ipairs(inst[4]) do
		local boss = { name = b[1] < 0 and Localized(D.objects[-b[1]]) or NpcName(b[1]), items = {} }
		local list = b[2]
		for i = 1, #list, 2 do
			local itemID, patch = list[i], list[i + 1]
			if C_Item.DoesItemExistByID(itemID) then
				local itemName, link, _, _, _, _, _, _, equipLoc, icon = C_Item.GetItemInfo(itemID)
				if not link then
					C_Item.RequestLoadItemDataByID(itemID)
					pending = true
				else
					local kind, extra = ns.Collectible(itemID, link)
					if kind == "pending" then
						pending = true
					elseif kind then
						local item = extra or {}
						item.kind, item.itemID, item.link, item.name, item.icon = kind, itemID, link, itemName, icon
						local slot = equipLoc and _G[equipLoc] or ""
						local note = PatchNote(patch)
						item.slot = note and (slot ~= "" and (slot .. "  ·  " .. note) or note) or slot
						table.insert(boss.items, item)
						count = count + 1
					end
				end
			end
		end
		bosses[#bosses + 1] = boss
	end
	local killed = ns.KilledBosses(name)
	for _, boss in ipairs(bosses) do boss.killed = killed[boss.name] end
	return { id = id, name = name, difficulties = {}, bosses = bosses, count = count }, pending and "pending" or nil
end
