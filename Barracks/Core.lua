local addonName, ns = ...
local L = ns.L

-- WoW Forever (interface 16001) runs vanilla content on the retail client:
-- no Great Vault, Mythic+, crests or coffer keys to show.
ns.vanillaContent = select(4, GetBuildInfo()) < 20000

local DEFAULTS = {
	chars = {},
	hidden = {},
	sort = "ilvl",
	sortDesc = true,
	showHidden = false,
	scale = 1,
	minimapAngle = 200,
	minimapHide = false,
}

local function ApplyDefaults(db)
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then
			db[k] = type(v) == "table" and {} or v
		end
	end
	return db
end

-- Coalesce bursts of events (BAG_UPDATE, CURRENCY_DISPLAY_UPDATE...) into one snapshot.
local pending, timer = {}, nil
local function Queue(part)
	pending[part] = true
	if timer then return end
	timer = C_Timer.NewTimer(1, function()
		timer = nil
		local parts = pending
		pending = {}
		ns.Collect(parts)
		if ns.Refresh then ns.Refresh() end
	end)
end

local EVENT_PARTS = {
	PLAYER_MONEY = "basics",
	PLAYER_AVG_ITEM_LEVEL_UPDATE = "basics",
	PLAYER_SPECIALIZATION_CHANGED = "basics",
	PLAYER_LEVEL_UP = "xp",
	PLAYER_XP_UPDATE = "xp",
	UPDATE_EXHAUSTION = "xp",
	PLAYER_UPDATE_RESTING = "xp",
	CURRENCY_DISPLAY_UPDATE = "currency",
	WEEKLY_REWARDS_UPDATE = "vault",
	CHALLENGE_MODE_MAPS_UPDATE = "mplus",
	CHALLENGE_MODE_COMPLETED = "mplus",
	BAG_UPDATE_DELAYED = "mplus",
	UPDATE_INSTANCE_INFO = "lockouts",
	SKILL_LINES_CHANGED = "professions",
}

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LOGOUT")
for event in pairs(EVENT_PARTS) do
	f:RegisterEvent(event)
end

f:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then return end
		BarracksDB = ApplyDefaults(BarracksDB or {})
		ns.db = BarracksDB
		ns.CreateMinimapButton()
	elseif event == "PLAYER_ENTERING_WORLD" then
		if arg1 or arg2 then -- login or /reload
			RequestRaidInfo()
			C_MythicPlus.RequestMapInfo()
			C_MythicPlus.RequestRewards()
			C_Timer.After(3, function()
				ns.Collect()
				if ns.Refresh then ns.Refresh() end
			end)
			if arg1 then
				print("|cff66ccff" .. L.Title .. "|r " .. L.Loaded)
			end
		end
	elseif event == "PLAYER_LOGOUT" then
		ns.MarkLogout()
	elseif EVENT_PARTS[event] then
		Queue(EVENT_PARTS[event])
	end
end)

SLASH_BARRACKS1 = "/alts"
SLASH_BARRACKS2 = "/barracks"
SlashCmdList.BARRACKS = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "debug" then
		ns.debug = not ns.debug
		print("|cff66ccffBarracks|r debug", ns.debug and "on" or "off")
	elseif msg == "boton" or msg == "botón" or msg == "button" or msg == "minimap" then
		ns.SetMinimapHidden(not ns.db.minimapHide)
	elseif msg == "scan" then
		ns.Collect()
		if ns.Refresh then ns.Refresh() end
	else
		ns.Toggle()
	end
end

-- Minimap addon compartment (see the .toc)
function Barracks_OnAddonCompartmentClick()
	ns.Toggle()
end

BINDING_HEADER_BARRACKS = L.Title
BINDING_NAME_BARRACKS_TOGGLE = L.Title
function Barracks_Toggle()
	ns.Toggle()
end
