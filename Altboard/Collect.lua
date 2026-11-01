local _, ns = ...

-- The War Within, Season 3 (11.2.x)
ns.CRESTS = { 3284, 3286, 3288, 3290 } -- Weathered, Carved, Runed, Gilded Ethereal Crest
ns.CREST_COLORS = { "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000" }
ns.VALORSTONES = 3008
ns.COFFER_KEYS = 3028 -- Restored Coffer Key
ns.TRACKED_CURRENCIES = { 3284, 3286, 3288, 3290, 3008, 3028 }

local T = Enum.WeeklyRewardChestThresholdType
ns.VAULT_TYPES = {
	{ type = T.Raid, key = "Raid" },
	{ type = T.Activities, key = "Dungeons" },
	{ type = T.World, key = "World" },
}

local REST_PER_8H = 0.05 -- fraction of a level gained per 8h resting in an inn or city
local REST_CAP = 1.5     -- rested pool caps at one and a half levels

local function Try(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and ns.debug then
		print("|cff66ccffAltboard|r", label, err)
	end
end

local function CollectBasics(rec)
	local className, classFile = UnitClass("player")
	rec.name = UnitName("player")
	rec.realm = GetRealmName()
	rec.className, rec.class = className, classFile
	rec.race = UnitRace("player")
	rec.faction = UnitFactionGroup("player")
	rec.level = UnitLevel("player")
	rec.maxLevel = GetMaxLevelForPlayerExpansion()
	rec.money = GetMoney()

	local overall, equipped = GetAverageItemLevel()
	rec.ilvl = equipped
	rec.ilvlOverall = overall

	-- The server sometimes reports spec 0 or no icon; keep what we had then.
	local spec = GetSpecialization()
	local specID, specName, icon, role, _
	if spec then
		specID, specName, _, icon, role = GetSpecializationInfo(spec)
	end
	if specID and specID > 0 then
		if (not icon or icon == 0) and GetSpecializationInfoByID then
			icon = select(4, GetSpecializationInfoByID(specID))
		end
		rec.specID, rec.specName, rec.role = specID, specName, role
		if icon and icon ~= 0 then rec.specIcon = icon end
	end
end

local function CollectXP(rec)
	rec.xp = UnitXP("player")
	rec.xpMax = UnitXPMax("player")
	rec.rested = GetXPExhaustion() or 0
	rec.resting = IsResting()
end

local function CollectCurrencies(rec)
	rec.currencies = rec.currencies or {}
	for _, id in ipairs(ns.TRACKED_CURRENCIES) do
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		if info and info.name and info.name ~= "" then
			rec.currencies[id] = {
				name = info.name,
				icon = info.iconFileID,
				quantity = info.quantity,
				max = info.maxQuantity,
				week = info.quantityEarnedThisWeek,
				weekMax = info.maxWeeklyQuantity,
				earned = info.totalEarned,
				seasonal = info.useTotalEarnedForMaxQty,
			}
		end
	end
end

local function RewardItemLevel(activityID)
	local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activityID)
	if link then
		return C_Item.GetDetailedItemLevelInfo(link)
	end
end

local function CollectVault(rec)
	local vault = {}
	for _, vt in ipairs(ns.VAULT_TYPES) do
		local slots = {}
		for _, a in ipairs(C_WeeklyRewards.GetActivities(vt.type)) do
			local slot = { progress = a.progress, threshold = a.threshold, level = a.level }
			if a.progress >= a.threshold then
				local ok, ilvl = pcall(RewardItemLevel, a.id)
				slot.ilvl = ok and ilvl or nil
			end
			slots[a.index] = slot
		end
		vault[vt.key] = slots
	end
	rec.vault = vault
	rec.vaultReward = C_WeeklyRewards.HasAvailableRewards() or false
end

local function CollectMythicPlus(rec)
	rec.score = C_ChallengeMode.GetOverallDungeonScore() or 0
	local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
	if mapID and mapID > 0 then
		rec.key = {
			mapID = mapID,
			level = C_MythicPlus.GetOwnedKeystoneLevel(),
			name = C_ChallengeMode.GetMapUIInfo(mapID),
		}
	else
		rec.key = nil
	end
end

local function CollectLockouts(rec)
	local now = time()
	local list = {}
	for i = 1, GetNumSavedInstances() do
		local name, _, reset, _, locked, extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
		if (locked or extended) and reset and reset > 0 then
			list[#list + 1] = {
				name = name,
				difficulty = difficultyName,
				progress = encounterProgress,
				total = numEncounters,
				isRaid = isRaid,
				resetAt = now + reset,
			}
		end
	end
	table.sort(list, function(a, b)
		if a.isRaid ~= b.isRaid then return a.isRaid end
		return a.name < b.name
	end)
	rec.lockouts = list
end

local function CollectProfessions(rec)
	local list = {}
	local prof1, prof2, _, fishing, cooking = GetProfessions()
	for _, index in ipairs({ prof1 or 0, prof2 or 0, cooking or 0, fishing or 0 }) do
		if index > 0 then
			local name, icon, rank, maxRank = GetProfessionInfo(index)
			list[#list + 1] = { name = name, icon = icon, rank = rank, max = maxRank }
		end
	end
	rec.professions = list
end

-- Snapshot the logged-in character. Each part is guarded so a missing server
-- feature cannot stop the rest from being recorded.
function ns.Collect(parts)
	local guid = UnitGUID("player")
	if not guid or not ns.db then return end
	local rec = ns.db.chars[guid] or {}
	ns.db.chars[guid] = rec
	rec.guid = guid

	Try("basics", CollectBasics, rec)
	if not parts or parts.xp then Try("xp", CollectXP, rec) end
	if not parts or parts.currency then Try("currency", CollectCurrencies, rec) end
	if not parts or parts.vault then Try("vault", CollectVault, rec) end
	if not parts or parts.mplus then Try("mplus", CollectMythicPlus, rec) end
	if not parts or parts.lockouts then Try("lockouts", CollectLockouts, rec) end
	if not parts or parts.professions then Try("professions", CollectProfessions, rec) end

	if C_Bank and C_Bank.FetchDepositedMoney and Enum.BankType then
		Try("warband", function()
			ns.db.warbandMoney = C_Bank.FetchDepositedMoney(Enum.BankType.Account)
		end)
	end

	rec.lastSeen = time()
	rec.weekResetAt = time() + C_DateAndTime.GetSecondsUntilWeeklyReset()
	ns.db.weekResetAt = rec.weekResetAt
	ns.currentGUID = guid
end

-- By PLAYER_LOGOUT money, item level, XP and spec already read as zero, so a
-- full snapshot would wipe the character; only note when and where it was left.
function ns.MarkLogout()
	local rec = ns.db and ns.currentGUID and ns.db.chars[ns.currentGUID]
	if not rec then return end
	rec.lastSeen = time()
	rec.resting = IsResting()
end

-- Views that account for time passing while a character is logged out.

function ns.IsStaleWeek(rec)
	return rec.weekResetAt and time() >= rec.weekResetAt
end

-- Slots unlocked last week turn into a reward to claim after the reset.
function ns.HasPendingReward(rec)
	if rec.vaultReward then return true end
	if not ns.IsStaleWeek(rec) or not rec.vault then return false end
	for _, slots in pairs(rec.vault) do
		for _, s in pairs(slots) do
			if s.progress >= s.threshold then return true end
		end
	end
	return false
end

function ns.ProjectedRested(rec)
	if not rec.xpMax or rec.xpMax == 0 or (rec.level and rec.maxLevel and rec.level >= rec.maxLevel) then
		return nil
	end
	local rested = rec.rested or 0
	if rec.guid ~= ns.currentGUID and rec.lastSeen then
		local hours = (time() - rec.lastSeen) / 3600
		local rate = rec.resting and 1 or 0.25
		rested = rested + hours / 8 * REST_PER_8H * rec.xpMax * rate
	end
	return math.min(rested, rec.xpMax * REST_CAP) / rec.xpMax
end

function ns.CurrencyWeek(rec, id)
	local c = rec.currencies and rec.currencies[id]
	if not c then return nil end
	if ns.IsStaleWeek(rec) then
		return 0, c.weekMax
	end
	return c.week, c.weekMax
end

function ns.ActiveLockouts(rec)
	local now, out = time(), {}
	for _, l in ipairs(rec.lockouts or {}) do
		if l.resetAt > now then out[#out + 1] = l end
	end
	return out
end
