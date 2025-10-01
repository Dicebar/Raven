-- Raven is an addon to monitor auras and cooldowns, providing timer bars and icons plus helpful notifications.

-- Values.lua contains functions used by value bars.

local MOD = Raven
local SHIM = MOD.SHIM
local L = LibStub("AceLocale-3.0"):GetLocale("Raven")
local valueFunctions, colorFunctions
local mirrorIcons
local iconXP, iconMail, iconCurrency, iconClock, iconLatency, iconFramerate, iconMap, iconMapX, iconMapY, iconArrow, iconAzerite
local iconLevel, iconHealth, iconCombo, iconPower, iconHeals, iconAbsorb, iconStagger, iconThreat, iconDurability, iconCombat, iconRune, iconRested, iconResting
local iconChi, iconArcaneCharge, iconSoulShard, iconHonor, iconHonorHorde, iconHonorAlliance, iconReputation, iconClassification
local directionTable = { "S", "SSE", "SE", "ESE", "E", "ENE", "NE", "NNE", "N", "NNW", "NW", "WNW", "W", "WSW", "SW", "SSW" }
local rc = { r = 1, g = 0, b = 0 }
local channelColor = { r = 0.125, g = 0.25, b = 0.75 }
local castColor = { r = 1, g = 0.7, b = 0 }
local noInterruptColor = { r = 0.7, g = 0.7, b = 0.7 }
local startTime, startMoney
local timeTable = {}
local goldTable = {}
local xpTable = {}
local durabilityTable = {}
local monitorTable = {}
local networkTable = {}
local reputationTable = {}
local scanTooltip
local latency = {} -- track latencies for units with cast bars
local maximumLevel = 120 -- update with new expansions!

local function ColorHealth(h, hmax)
	if h and hmax and h <= hmax then
		local frac = h / hmax -- color goes from green to red depending on current health
		return MOD.Nest_IntermediateColor(1, 0, 0, 0, 1, 0, frac)
	end
	return 0, 1, 0 -- fall back is plain green but should never happen!
end

local function ColorPower(power, token, altR, altG, altB)
	if token then
		local c = PowerBarColor[token]
		if c then return c.r, c.g, c.b end
	elseif altR and altG and altB then
		return altR, altG, altB
	elseif power then
		local c = PowerBarColor[power]
		if c then return c.r, c.g, c.b end
	end
	local c = PowerBarColor["MANA"]
	if c then return c.r, c.g, c.b end
	return 0, 0, 1 -- fall back is plain blue but should never happen!
end

local function GetTimeText(zone, military, ampm)
	local t = ""
	local h, m = GetGameTime()
	if zone == "local" then local d = date("*t"); h = d.hour end
	if zone == "session" then
		local s = GetTime() - startTime; h = math.floor(s / 3600); m = math.floor((s - (h * 3600)) / 60)
		if h > 0 then t = string.format("%d:%02d:%02d", h, m, math.floor(s - (h * 3600) - (m * 60)))
		else t = string.format("%d:%02d", m, math.floor(s - (m * 60))) end
	else
		if military then
			t = string.format ("%02d:%02d", h, m)
		else
			if ampm then ampm = " AM" end
			if h >= 12 then h = h - 12; if ampm then ampm = " PM" end end
			if h == 0 then h = 12 end
			t = string.format ("%d:%02d%s", h, m, ampm or "")
		end
	end
	return t
end

-- Return a formatted string for an integer, shortening it as needed for big numbers.
local function GetFormattedInteger(x)
	if abs(x) > 1000000 then -- shorten big numbers
		x = math.floor(x / 100000) / 10 -- preserve one decimal place
		return string.format("%.1fM", x)
	end
	if abs(x) > 1000 then
		x = math.floor(x / 100) / 10 -- preserve one decimal place
		return string.format("%.1fK", x)
	end
	x = math.floor(x + 0.5) -- rounded to nearest integer
	return string.format("%d", x)
end

-- Return a formatted string for a possibly non-integer value, shortening it as needed for big numbers.
local function GetFormattedNumber(x, precision)
	if abs(x) > 1000 then return GetFormattedInteger(x) end
	if precision == 1 then
		x = math.floor((x * 10) + 0.5) / 10 -- rounded to nearest 1/10
		return string.format("%.1f", x)
	elseif precision == 2 then
		x = math.floor((x * 100) + 0.5) / 100 -- rounded to nearest 1/100
		return string.format("%.2f", x)
	end
	x = math.floor((x * 1000) + 0.5) / 1000 -- default, rounded to nearest 1/1000
	return string.format("%.3f", x)
end

-- Return a formatted string for the value, using the specified format: "i" = integer, "f1" = one decimal place,
-- "f2" = two decimal places, "pct" = percentage, "t" = minutes:seconds, "slash" = "number/max".
-- If format is anything else then return the value rounded to 3 decimal places.
local function GetFormattedText(textFormat, value, maxValue)
	local x, xmax = value, maxValue
	local s
	if textFormat == "i" then
		s = GetFormattedInteger(x)
	elseif textFormat == "f1" then
		s = GetFormattedNumber(x, 1) -- rounded to nearest 1/10
	elseif textFormat == "f2" then
		s = GetFormattedNumber(x, 2) -- rounded to nearest 1/10
	elseif textFormat == "pct" then
		x = math.floor((x / xmax) * 100 + 0.5)
		s = string.format("%.0f%%", x)
	elseif textFormat == "slash" then
		local xInt = (abs(x - math.floor(x)) < 0.01)
		local xmaxInt = (abs(xmax - math.floor(xmax)) < 0.01)
		local sx = xInt and GetFormattedInteger(x) or GetFormattedNumber(x, 1)
		local sxmax = xmaxInt and GetFormattedInteger(xmax) or GetFormattedNumber(xmax, 1)
		s = string.format("%s/%s", sx, sxmax)
	elseif textFormat == "t" then
		local seconds = math.floor(x + 0.5)
		local minutes = math.floor(seconds / 60)
		seconds = seconds - (minutes * 60)
		s = string.format("%d:%02d", minutes, seconds)
	else
		s = GetFormattedNumber(x, 3) -- rounded to nearest 1/1000
	end
	return s
end

local function GetTimerText(value) return GetFormattedText("t", value, 1) end

local function GetDurability()
	local durability, repairCost, totalCurrent, totalMaximum, itemCount = 1, 0, 0, 0, 0
	for slotID = 1, 18 do
		if GetInventoryItemID("player", slotID) then
			local currentDurability, maximumDurability = GetInventoryItemDurability(slotID)
			if currentDurability and maximumDurability > 0 and currentDurability < maximumDurability then
				local hasItem, _, cost = scanTooltip:SetInventoryItem("player", slotID)
				if hasItem and cost and (cost > 0) then repairCost = repairCost + cost end
				local itemDurability = currentDurability / maximumDurability
				if itemDurability < durability then durability = itemDurability end
				totalCurrent = totalCurrent + currentDurability
				totalMaximum = totalMaximum + maximumDurability
			end
		end
	end
	if totalCurrent == 0 then totalCurrent = 1 end
	if totalMaximum == 0 then totalMaximum = 1 end
	local dt = math.floor(durability * 100)
	local dm = math.floor(100 * totalCurrent / totalMaximum)
	return dt, dm, repairCost
end

-- Value functions receive input parameters: unit, textFormat, spell (name or spell id), and optionalText.
-- Functions return:
--     1. status - true if the unit exists (always true for functions with no unit)
--     2. value - current numeric value, depending on the selected function
--     3. maxValue - maximum value, used to calculate how much of a bar to fill, optionally override in bar settings
--     4. valueText - if not nil then this will be formatted to be shown instead of a numeric value in "timer text"
--     5. valueLabel - if not nil then this will be either appended to or replace "label text", depending on bar settings
--     6. icon - if not nil then this is the icon to show for the value bar, optionally overriden by spell icon in bar settings
--     7. ttType - type of tooltip to be displayed for the bar
--     8. ttID - data for the bar's tooltip, must be compatible with specified tooltip type
--     9. altR, altG, altB - if not nil then this is alternative color to use for value bar, selectable in bar settings
-- 10-12. hiR, hiG, hiB - if not nil then this is alternative color to use for value bar, selectable in bar settings
--    13. tick - if not nil then this is the offset % for showing optional tick mark on the bar

-- Class color might be a good option for all custom bars
-- Must update more frequently! Check out power bar delay on monk windwalker...

local function ValueUnitLevel(unit, fmt)
	if not unit or not UnitGUID(unit) then return false end
	local level = UnitLevel(unit)
	if level == -1 then return true, maximumLevel, maximumLevel, "|cFFFF0000??|r", nil, iconLevel, "text", "Level", 1, 0, 0 end -- boss
	local r, g, b = UnitSelectionColor(unit)
	local s = GetFormattedText(fmt, level, maximumLevel)
	return true, level, maximumLevel, s, nil, iconLevel, "text", "Level", r, g, b -- normal level player or NPC
end

local function ValueUnitHealth(unit, fmt)
	if not unit or not UnitGUID(unit) then return false end
	local h = UnitHealth(unit)
	local hmax = UnitHealthMax(unit)
	if not h or not hmax then return false end
	if hmax == 0 then hmax = 1 end -- avoid divide by zero
	local r, g, b = ColorHealth(h, hmax)
	local s = GetFormattedText(fmt, h, hmax)
	if UnitIsDead(unit) then s = L["Dead"]; h = 0 elseif UnitIsGhost(unit) then s = L["Ghost"]; h = 0 end
	return true, h, hmax, s, UnitName(unit), iconHealth, nil, nil, r, g, b
end

local function ValueUnitPower(unit, fmt)
	if not unit or not UnitGUID(unit) then return false end
	local power, token, altR, altG, altB = UnitPowerType(unit)
	local r, g, b = ColorPower(power, token, altR, altG, altB)
	local p = UnitPower(unit)
	local pmax = UnitPowerMax(unit)
	if not p or not pmax then return false end
	if pmax == 0 then pmax = 1 end -- avoid divide by zero
	local s = GetFormattedText(fmt, p, pmax)
	return true, p, pmax, s, _G[token], iconPower, nil, nil, r, g, b
end

local function ValueClassification(unit, fmt)
	if not unit or not UnitGUID(unit) then return false end
	local classification = UnitClassification(unit)
	if not classification then return false end
	if MOD.LibBossIDs and MOD.CheckLibBossIDs(UnitGUID(unit)) then classification = "worldboss" end
	local classificationList = { normal = L["Normal"], worldboss = L["Boss"], elite = L["Elite"], rare = L["Rare"], rlite = L["Rare Elite"], trivial = L["Trivial"], minus = L["Minus"] }
	local s = classificationList[classification]
	return true, 0, 0, s, nil, iconClassification
end

local function ValueChi(unit, fmt)
	local p = UnitPower("player", Enum.PowerType.Chi)
	local pmax = UnitPowerMax("player", Enum.PowerType.Chi)
	if not p or not pmax or (pmax == 0) then return false end
	local c = PowerBarColor["CHI"] or rc
	local s = GetFormattedText(fmt, p, pmax)
	return true, p, pmax, s, nil, iconChi, nil, nil, c.r, c.g, c.b
end

local function ValueComboPoints(unit, fmt)
	local p = UnitPower("player", Enum.PowerType.ComboPoints)
	local pmax = UnitPowerMax("player", Enum.PowerType.ComboPoints)
	if not p or not pmax or (pmax == 0) then return false end
	local c = PowerBarColor["COMBO_POINTS"] or rc
	local s = GetFormattedText(fmt, p, pmax)
	return true, p, pmax, s, nil, iconCombo, nil, nil, c.r, c.g, c.b
end

local function ValueHolyPower(unit, fmt)
	local p = UnitPower("player", Enum.PowerType.HolyPower)
	local pmax = UnitPowerMax("player", Enum.PowerType.HolyPower)
	if not p or not pmax or (pmax == 0) then return false end
	local c = PowerBarColor["HOLY_POWER"] or rc
	local s = GetFormattedText(fmt, p, pmax)
	return true, p, pmax, s, nil, nil, nil, nil, c.r, c.g, c.b
end

local function ValueEssence(unit, fmt)
	local p = UnitPower("player", Enum.PowerType.Essence)
	local pmax = UnitPowerMax("player", Enum.PowerType.Essence)
	if not p or not pmax or (pmax == 0) then return false end
	local c = PowerBarColor["ESSENCE"] or rc
	local s = GetFormattedText(fmt, p, pmax)
	return true, p, pmax, s, nil, nil, nil, nil, c.r, c.g, c.b
end

local function ValueSoulShards(unit, fmt)
	local p = UnitPower("player", Enum.PowerType.SoulShards)
	local pmax = UnitPowerMax("player", Enum.PowerType.SoulShards)
	if not p or not pmax or (pmax == 0) then return false end
	local c = PowerBarColor["SOUL_SHARDS"] or rc
	local s = GetFormattedText(fmt, p, pmax)
	return true, p, pmax, s, nil, iconSoulShard, nil, nil, c.r, c.g, c.b
end

local function ValueRune(id, fmt)
	if MOD.myClass ~= "DEATHKNIGHT" then return false end
	local start, duration, ready = GetRuneCooldown(id)
	if ready then
		local c = MOD.ClassColors[MOD.myClass]
		return true, 0, 0, "", nil, iconRune, nil, nil, c.r, c.g, c.b
	end
	local timeLeft = math.floor((duration - (GetTime() - start)) * 10) / 10
	if timeLeft > duration then timeLeft = duration end
	local t = timeLeft
	if fmt == "i" then t = math.floor(timeLeft); if t < 0 then t = 0 end end -- integer time is truncated instead of rounded
	local s = GetFormattedText(fmt, t, duration)
	return true, timeLeft, duration, s, nil, iconRune, nil, nil, 0.5, 0.5, 0.5
end

local function ValueRune1(unit, fmt) return ValueRune(1, fmt) end
local function ValueRune2(unit, fmt) return ValueRune(2, fmt) end
local function ValueRune3(unit, fmt) return ValueRune(3, fmt) end
local function ValueRune4(unit, fmt) return ValueRune(4, fmt) end
local function ValueRune5(unit, fmt) return ValueRune(5, fmt) end
local function ValueRune6(unit, fmt) return ValueRune(6, fmt) end

local function ValueArcaneCharges(unit, fmt)
	local p = UnitPower("player", Enum.PowerType.ArcaneCharges)
	local pmax = UnitPowerMax("player", Enum.PowerType.ArcaneCharges)
	if not p or not pmax or (pmax == 0) then return false end
	local c = PowerBarColor["ARCANE_CHARGES"] or rc
	local s = GetFormattedText(fmt, p, pmax)
	return true, p, pmax, s, nil, iconArcaneCharge, nil, nil, c.r, c.g, c.b
end

local function ValueUnitThreat(unit, fmt)
	if not unit or not UnitGUID(unit) then return false end
	local status = UnitThreatSituation(unit) or 0
	if status == 0 then return false end
	local r, g, b = 1, 0, 0
	if GetThreatStatusColor then
		r, g, b = GetThreatStatusColor(status)
	else
		if status == 0 then r = 0.69; g = 0.69; b = 0.69 end
		if status == 1 then g = 1; b = 0.47 end
		if status == 2 then g = 0.6 end
	end
	local s = GetFormattedText(fmt, status, 3)
	return true, status, 3, nil, nil, iconThreat, nil, nil, r, g, b
end

local function ValueUnitPVP(unit, fmt)
	if not unit or not UnitGUID(unit) then return false end
	local isPVP = UnitIsPVP(unit)
	if not isPVP then return false end
	local faction = UnitFactionGroup(unit)
	local icon = "Interface\\TargetingFrame\\UI-PVP-" .. (faction or "FFA")
	if unit == "player" then
		local timer = GetPVPTimer()
		if timer and (timer ~= -1) then
			if timer == 301000 then return true, 0, 0, "|cFFFF0000PvP|r", nil, icon end
			local s = "|cFFFF0000PvP " .. GetTimerText(timer / 1000) .. "|r"
			return true, 0, 0, s, nil, icon
		end
	end
	return true, 0, 0, "|cFFFF0000PvP|r", nil, icon
end

local function ValueUnitAbsorb(unit, fmt)
	if not unit or not UnitGUID(unit) then return false end
	local v = UnitGetTotalAbsorbs(unit) or 0
	local vm = UnitHealthMax(unit) or 1
	if vm < v then vm = v end
	local s = GetFormattedText(fmt, v, vm)
	return true, v, vm, s, L["Absorb"], iconAbsorb
end

local function ValueUnitIncomingHeals(unit, fmt)
	if not unit or not UnitGUID(unit) then return false end
	local h = UnitGetIncomingHeals(unit) or 0
	local hmax = UnitHealthMax(unit)
	local s = GetFormattedText(fmt, h, hmax)
	return true, h, hmax, s, L["Incoming Heals"], iconHeals, _, _, 0.5, 1, 0.5
end

local function ValueUnitHealthIncomingHeals(unit, fmt)
	if not unit or not UnitGUID(unit) then return false end
	local h = UnitHealth(unit)
	local hmax = UnitHealthMax(unit)
	if not h or not hmax then return false end
	local total = h + (UnitGetIncomingHeals(unit) or 0)
	if total > hmax then total = hmax end
	if hmax == 0 then hmax = 1 end -- avoid divide by zero
	local s = GetFormattedText(fmt, total, hmax)
	return true, total, hmax, s, nil, iconHeals
end

local function ValueUnitStagger(unit, fmt)
	if not unit or not UnitGUID(unit) then return false end
	local v = UnitStagger(unit) or 0
	local vm = UnitHealthMax(unit) or 1
	if vm < v then vm = v end
	local s = GetFormattedText(fmt, v, vm)
	return true, v, vm, s, L["Stagger"], iconStagger
end

local function ValuePlayerXP(unit, fmt)
	local xp = UnitXP("player")
	local xpmax = UnitXPMax("player")
	if not xp or not xpmax then return false end
	if xpmax == 0 then xpmax = 1 end -- avoid divide by zero
	local s = GetFormattedText(fmt, xp, xpmax)
	local rested = GetXPExhaustion() or 0
	xpTable[1] = "|cffffcc00Player XP|r"
	xpTable[2] = string.format("|cffffff00Percent XP|r %.0f%%", (xp / xpmax) * 100)
	xpTable[3] = string.format("|cffffff00Current XP|r %d", xp)
	xpTable[4] = string.format("|cffffff00Maximum XP|r %d", xpmax)
	xpTable[5] = string.format("|cffffff00Rested|r %.0f%%", (rested / xpmax) * 100)
	return true, xp, xpmax, s, nil, iconXP, "lines", xpTable
end

local function ValueRestedXP(unit, fmt)
	local xp = GetXPExhaustion()
	local xpmax = UnitXPMax("player")
	if not xp or not xpmax then return false end
	if xpmax == 0 then xpmax = 1 end -- avoid divide by zero
	local s = GetFormattedText(fmt, xp, xpmax)
	return true, xp, xpmax, s, nil, iconRested
end

local function ValueResting(unit, fmt)
	if not IsResting() then return false end
	return true, 0, 0, "Resting", nil, iconResting
end

local function ValueHonor(unit, fmt)
	local xp = UnitHonor("player")
	local xpmax = UnitHonorMax("player")
	if not xp or not xpmax then return false end
	if xpmax == 0 then xpmax = 1 end -- avoid divide by zero
	local s = GetFormattedText(fmt, xp, xpmax)
	local icon = iconHonor
	local myFaction = UnitFactionGroup("player")
	if myFaction == "Horde" then icon = iconHonorHorde elseif myFaction == "Alliance" then icon = iconHonorAlliance end
	local level = UnitHonorLevel("player")
	local t = L["Honor"]
	if level then t = t .. " [" .. tostring(level) .. "]" end
	return true, xp, xpmax, s, t, icon
end

local function ValueReputation(unit, fmt)
	local name, standing, barMin, barMax, barValue = GetWatchedFactionInfo()
	if name and standing and barMin and barMax and barValue then
		local xp = barValue - barMin
		local xpmax = barMax - barMin
		if xp < 0 then xp = 0 end
		if xpmax == 0 then xpmax = 1 end -- avoid divide by zero
		local s = GetFormattedText(fmt, xp, xpmax)
		local c = FACTION_BAR_COLORS[standing] or rc
		local label = _G['FACTION_STANDING_LABEL' .. standing]
		reputationTable[1] = "|cffffcc00Reputation|r"
		reputationTable[2] = string.format("|cffffff00%s:|r %s %d/%d (%.0f%%)", name, label, xp, xpmax, (xp / xpmax) * 100)
		return true, xp, xpmax, s, name, iconReputation, "lines", reputationTable, c.r, c.g, c.b
	end
	return false
end

local function ValueCombat(unit, fmt)
	if MOD.combatTimer == 0 then return false end
	return true, 0, 0, GetTimerText(GetTime() - MOD.combatTimer), "In Combat", iconCombat
end

local function ValueUnitRaidMarker(unit, fmt)
	if not unit or not UnitGUID(unit) then return false end
	local index = GetRaidTargetIndex(unit)
	if not index then return false end
	local icon = "Interface/TargetingFrame/UI-RaidTargetingIcon_" .. index
	return true, 0, 0, nil, nil, icon
end

local function ValueAzerite(unit, fmt)
	local azeriteItemLocation = C_AzeriteItem.FindActiveAzeriteItem()
	if not azeriteItemLocation then return false end
	local azeriteItem = Item:CreateFromItemLocation(azeriteItemLocation)
	local itemName = azeriteItem:GetItemName()
	if not itemName then return false end
	local xp, xpmax = C_AzeriteItem.GetAzeriteItemXPInfo(azeriteItemLocation)
	if not xp then xp = 0 end
	if not xpmax or xpmax <= 0 then xpmax = 1 end
	local currentLevel = C_AzeriteItem.GetPowerLevel(azeriteItemLocation)
	local t = itemName
	if currentLevel then t = t .. " [" .. tostring(currentLevel) .. "]" end
	local s = GetFormattedText(fmt, xp, xpmax)
	return true, xp, xpmax, s, t, iconAzerite
end

local function ValueMapX(unit, fmt)
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return false end
	local fx = 0
	local position = C_Map.GetPlayerMapPosition(mapID, "player") -- fraction of maximum position
	if position then fx = position.x * 100 end
	local s = GetFormattedText(fmt, fx, 100)
	return true, fx, 100, s, nil, iconMapX
end

local function ValueMapY(unit, fmt)
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return false end
	local fy = 0
	local position = C_Map.GetPlayerMapPosition(mapID, "player") -- fraction of maximum position
	if position then fy = position.y * 100 end
	local s = GetFormattedText(fmt, fy, 100)
	return true, fy, 100, s, nil, iconMapY
end

local function ValuePosition(unit, fmt)
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return false end
	local zone = C_Map.GetMapInfo(mapID).name
	local fx, fy = 0, 0
	local position = C_Map.GetPlayerMapPosition(mapID, "player") -- fraction of maximum position
	if position then fx = position.x; fy = position.y end
	fx = (math.floor((fx * 10000) + 0.5)) / 100
	fy = (math.floor((fy * 10000) + 0.5)) / 100
	local s = string.format("%0.2f, %0.2f", fx, fy)
	return true, 0, 0, s, zone, iconMap
end

local function ValueFacing(unit, fmt)
	local facing = GetPlayerFacing()
	if not facing then return false end
	local theta = 180 + (facing * 360 / (2 * math.pi))
	if theta > 360 then theta = theta - 360 end
	local angle = math.floor(theta + 0.5)
	if angle > 360 then angle = 0 end
	local s = GetFormattedText(fmt, angle, 360)
	local direction = math.floor((theta / 22.5) + 0.5) + 1
	if direction > 16 then direction = 1 end
	return true, theta, 360, s, directionTable[direction], iconArrow
end

local function ValueMirror(id, fmt)
	local timer, value, duration, fillRate, paused, label = GetMirrorTimerInfo(id)
	if (timer ~= "UNKNOWN") and value and value > 0 then
		local timeLeft = (GetMirrorTimerProgress(timer) or 0) / 1000
		duration = (duration or 0) / 1000
		local icon = mirrorIcons[timer]
		local c = MirrorTimerColors[timer] or rc
		local s = GetFormattedText(fmt, timeLeft, duration)
		return true, timeLeft, duration, s, label, icon, nil, nil, c.r, c.g, c.b
	end
	return false
end

local function ValueMirror1(unit, fmt) return ValueMirror(1, fmt) end
local function ValueMirror2(unit, fmt) return ValueMirror(2, fmt) end
local function ValueMirror3(unit, fmt) return ValueMirror(3, fmt) end

local function LatencyHandler(self, event, unit)
	if event == "CURRENT_SPELL_CAST_CHANGED" then
		latency.sentTime = GetTime()
		-- MOD.Debug("sent", event, latency.sentTime)
	elseif ((unit == "player") or (unit == "vehicle")) then
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			latency.sentTime = nil
			-- MOD.Debug("succeeded", event, latency.sentTime)
		elseif event == "UNIT_SPELLCAST_START" then
			if latency.sentTime then
				latency.lag = GetTime() - latency.sentTime -- lag in seconds between when a spell is sent and when it actually starts
				-- MOD.Debug("start", event, latency.sentTime, latency.lag)
				latency.sentTime = nil
			end
		end
	end
end

local function ValueCastBar(unit, fmt, spell, options)
	local checkUnit = unit
	local castingInfo, channelInfo = UnitCastingInfo, UnitChannelInfo

	if UnitHasVehicleUI("player") then
		if unit == "player" then checkUnit = "pet" elseif unit == "pet" then checkUnit = "player" end
	end

	castingInfo = CastingInfo; channelInfo = ChannelInfo

	if not unit or not UnitGUID(unit) then return false end
	if unit == "player" or unit == "vehicle" then
		if not latency.frame then -- check if need to start event tracking
			local f = CreateFrame("Frame")
			latency.frame = f
			f:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
			f:RegisterEvent("UNIT_SPELLCAST_START")
			f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
			f:SetScript("OnEvent", LatencyHandler)
			latency.sentTime = nil
			latency.lag = 0
		end
	end
	local channel = false
	local name, text, icon, startTime, endTime, trade, castID, noInterrupt, spellID = castingInfo(checkUnit)
	if not name then
		name, text, icon, startTime, endTime, trade, noInterrupt = channelInfo(checkUnit)
		channel = true
	end
	if name then
		local duration = (endTime - startTime) / 1000
		local timeLeft = (endTime / 1000) - GetTime()
		local c = castColor
		if channel then timeLeft = duration - timeLeft; c = channelColor end -- reverse direction for channel
		if noInterrupt then c = noInterruptColor end
		timeLeft = timeLeft - 0.02 -- fudge by about one update time for appearance's sake
		if timeLeft < 0 then timeLeft = 0 end
		local s = GetFormattedText(fmt, timeLeft, duration)
		local showLag = options and (unit == "player") and string.find(string.lower(options), "latency")
		local lag = (showLag and (latency.lag and (latency.lag > 0))) and latency.lag or nil
		local showX = options and string.find(string.lower(options), "interrupt")
		if showX and noInterrupt then text = "|cFFFF0000X|r " .. text end
		return true, timeLeft, duration, s, text, icon, nil, nil, c.r, c.g, c.b, lag
	end
	return false
end

local function ValueMonitor(unit, fmt)
	local frameRate = math.floor(GetFramerate() or 0)
	local w, h = MOD.Nest_ScreenResolution()
	local gamma = tonumber(GetCVar("Gamma"))
	local maxFPS = tonumber(GetCVar("maxFPS")) or 60
	monitorTable[1] = "|cffffcc00Monitor|r"
	monitorTable[2] = string.format("|cffffff00Frame Rate|r %d", frameRate)
	monitorTable[3] = string.format("|cffffff00Dimensions|r %d x %d", w, h)
	if gamma then gamma = math.floor(gamma * 100) / 100; monitorTable[4] = string.format("|cffffff00Gamma|r %0.2f", gamma) end
	local s = GetFormattedText(fmt, frameRate, maxFPS)
	return true, frameRate, maxFPS, nil, nil, iconFramerate, "lines", monitorTable
end

local function ValueNetwork(unit, fmt)
	local bwi, bwo, latencyHome, latencyWorld = GetNetStats()
	networkTable[1] = "|cffffcc00Network|r"
	networkTable[2] = string.format("|cffffff00Latency|r %d ms (Home)", math.floor(latencyHome or 0))
	networkTable[3] = string.format("|cffffff00Latency|r %d ms (World)", math.floor(latencyWorld or 0))
	networkTable[4] = string.format("|cffffff00Bandwidth|r %0.3f KB/s (In)", bwi)
	networkTable[5] = string.format("|cffffff00Bandwidth|r %0.3f KB/s (Out)", bwo)
	local latency = math.floor(latencyHome or 0)
	local s = GetFormattedText(fmt, latency, 100)
	return true, latency, 100, s, nil, iconLatency, "lines", networkTable
end

local function ValueGold(unit, fmt)
	local money = GetMoney()
	local gold = math.floor(money / 10000)
	local s = SHIM:GetCoinTextureString(money)
	local g = SHIM:GetCoinTextureString(gold * 10000)
	if gold <= 10 then g = s end -- only show rounded amount when get a bit of gold
	goldTable[1] = "|cffffcc00Gold|r"
	goldTable[2] = "|cffffff00Current|r " .. s
	local change = money - startMoney
	if change >= 0 then
		goldTable[3] = "|cffffff00Session Profit|r " .. SHIM:GetCoinTextureString(change)
	else
		goldTable[3] = "|cffffff00Session Loss|r " .. SHIM:GetCoinTextureString(-change)
	end
	return true, gold, gold, g, nil, iconCurrency, "lines", goldTable
end

local function ValueMail(unit, fmt)
	local status = HasNewMail()
	local mmm = status and 1 or 0
	return true, mmm, 1, status and L["You have mail!"] or L["No new mail"], nil, iconMail, "text", status
end

local function ValueClock(unit, fmt)
	local localTime = GetTimeText("local", false, true)
	local serverTime = GetTimeText("server", false, true)
	local sessionTime = GetTimeText("session", false, false)
	timeTable[1] = "|cffffff00Clock|r"
	timeTable[2] = string.format("%s |cffffff00(Date)|r", date("%m-%d-%Y"))
	timeTable[3] = string.format("%s |cffffff00(Local Time)|r", localTime)
	timeTable[4] = string.format("%s |cffffff00(Server Time)|r", serverTime)
	timeTable[5] = string.format("%s |cffffff00(Session Time)|r", sessionTime)
	return true, 0, 0, localTime, nil, iconClock, "lines", timeTable
end

local function ValueDurability(unit, fmt)
	local lowestDurability, averageDurability, repairCost = GetDurability()
	durabilityTable[1] = "|cffffff00Durability|r"
	durabilityTable[2] = string.format("|cffffff00Lowest Equipped|r %d%%", lowestDurability)
	durabilityTable[3] = string.format("|cffffff00Average Equipped|r %d%%", averageDurability)
	durabilityTable[4] = string.format("|cffffff00Repair Cost|r %s ", SHIM:GetCoinTextureString(repairCost))
	local s = GetFormattedText(fmt, lowestDurability, 100)
	return true, lowestDurability, 100, s, nil, iconDurability, "lines", durabilityTable
end

local function ValueTooltip(unit, fmt, spell, position)
	if spell and spell ~= "" then -- make sure valid spell is provided, could be spell name, number, or #number
		local id = nil
		if string.find(spell, "^#%d+") then id = tonumber(string.sub(spell, 2)) else id = tonumber(spell) end
		if not id then id = MOD:GetSpellID(spell) end
		local name, _, icon, _, _, _, spellID = SHIM:GetSpellInfo(id)
		if name and name ~= "" then
			local s = MOD:GetTooltipNumber("spell id", spellID, nil, tonumber(position))
			local c = MOD:GetColor(name, spellID)
			if c then
				return true, 0, 0, s, name, icon, "spell id", spellID, c.r, c.g, c.b
			else
				return true, 0, 0, s, name, icon, "spell id", spellID
			end
		end
	end
	return false
end

local onlyInteger = { ["i"] = true }
local onlyNumbers = { ["i"] = true, ["f1"] = true, ["f2"] = true }
local onlyCustom = { custom = true }
local onlyTime = { ["t"] = true }
local integerRange = { ["i"] = true, ["pct"] = true, ["slash"] = true }
local numberRange = { ["i"] = true, ["f1"] = true, ["f2"] = true, ["pct"] = true, ["slash"] = true }

local functionTable = {
	[L["Absorb"]] = { func = ValueUnitAbsorb, unit = true, fmt = "pct", fmts = integerRange},
	[L["Arcane Charges"]] = { func = ValueArcaneCharges, unit = false, frequent = true, segment = true, fmts = integerRange },
	[L["Azerite"]] = { func = ValueAzerite, unit = false, fmt = "pct", fmts = integerRange },
	[L["Cast Bar"]] = { func = ValueCastBar, unit = true, frequent = true, comment = L["Cast bar comment"], fmt = "f1", fmts = numberRange },
	[L["Chi"]] = { func = ValueChi, unit = false, frequent = true, segment = true, fmts = integerRange },
	[L["Classification"]] = { func = ValueClassification, unit = true, fmts = onlyCustom },
	[L["Clock"]] = { func = ValueClock, unit = false, fmts = onlyCustom },
	[L["Combo Points"]] = { func = ValueComboPoints, unit = false, frequent = true, segment = true, fmts = integerRange },
	[L["Durability"]] = { func = ValueDurability, unit = false, fmt = "pct", fmts = integerRange },
	[L["Essence"]] = { func = ValueEssence, unit = false, frequent = true, segment = true, fmts = integerRange },
	[L["Experience"]] = { func = ValuePlayerXP, unit = false, fmt = "pct", fmts = integerRange },
	[L["Facing"]] = { func = ValueFacing, unit = false, frequent = true },
	[L["Gold"]] = { func = ValueGold, unit = false, fmts = onlyCustom },
	[L["Level"]] = { func = ValueUnitLevel, unit = true, fmts = integerRange },
	[L["Health"]] = { func = ValueUnitHealth, unit = true, frequent = true, fmt = "pct", fmts = integerRange },
	[L["Health + Incoming"]] = { func = ValueUnitHealthIncomingHeals, unit = true, frequent = true, fmt = "pct", fmts = integerRange },
	[L["Holy Power"]] = { func = ValueHolyPower, unit = false, frequent = true, segment = true, fmts = integerRange },
	[L["Honor"]] = { func = ValueHonor, unit = false, fmt = "pct", fmts = integerRange },
	[L["In Combat"]] = { func = ValueCombat, unit = false, fmt = "t", fmts = onlyTime },
	[L["Incoming Heals"]] = { func = ValueUnitIncomingHeals, unit = true, frequent = true, fmt = "pct", fmts = integerRange },
	[L["Mail"]] = { func = ValueMail, unit = false, fmts = onlyCustom},
	[L["Map X"]] = { func = ValueMapX, unit = false, fmt = "f2", fmts = numberRange },
	[L["Map Y"]] = { func = ValueMapY, unit = false, fmt = "f2", fmts = numberRange },
	[L["Mirror Timers"]] = { unit = false, bars = { [1] = L["Mirror Timer 3"], [2] = L["Mirror Timer 2"], [3] = L["Mirror Timer 1"] }, },
	[L["Mirror Timer 1"]] = { func = ValueMirror1, unit = false, frequent = true, hidden = true, fmt = "t", fmts = onlyTime },
	[L["Mirror Timer 2"]] = { func = ValueMirror2, unit = false, frequent = true, hidden = true, fmt = "t", fmts = onlyTime },
	[L["Mirror Timer 3"]] = { func = ValueMirror3, unit = false, frequent = true, hidden = true, fmt = "t", fmts = onlyTime },
	[L["Monitor"]] = { func = ValueMonitor, unit = false, fmts = integerRange },
	[L["Network"]] = { func = ValueNetwork, unit = false, fmts = integerRange },
	[L["Position"]] = { func = ValuePosition, unit = false, fmts = onlyCustom },
	[L["Power"]] = { func = ValueUnitPower, unit = true, frequent = true, fmt = "pct", fmts = integerRange },
	[L["PVP"]] = { func = ValueUnitPVP, unit = true, fmt = "t", fmts = onlyTime },
	[L["Raid Marker"]] = { func = ValueUnitRaidMarker, unit = true, fmts = onlyCustom },
	[L["Reputation"]] = { func = ValueReputation, unit = false, comment = L["Reputation comment"], fmt = "pct", fmts = integerRange },
	[L["Rested"]] = { func = ValueRestedXP, unit = false, fmt = "pct", fmts = integerRange },
	[L["Resting"]] = { func = ValueResting, unit = false, fmts = onlyCustom },
	[L["Runes"]] = { unit = false, bars = { [1] = L["Rune 6"], [2] = L["Rune 5"], [3] = L["Rune 4"], [4] = L["Rune 3"], [5] = L["Rune 2"], [6] = L["Rune 1"] }, },
	[L["Rune 1"]] = { func = ValueRune1, unit = false, frequent = true, hidden = true, fmt = "i", fmts = numberRange },
	[L["Rune 2"]] = { func = ValueRune2, unit = false, frequent = true, hidden = true, fmt = "i", fmts = numberRange },
	[L["Rune 3"]] = { func = ValueRune3, unit = false, frequent = true, hidden = true, fmt = "i", fmts = numberRange },
	[L["Rune 4"]] = { func = ValueRune4, unit = false, frequent = true, hidden = true, fmt = "i", fmts = numberRange },
	[L["Rune 5"]] = { func = ValueRune5, unit = false, frequent = true, hidden = true, fmt = "i", fmts = numberRange },
	[L["Rune 6"]] = { func = ValueRune6, unit = false, frequent = true, hidden = true, fmt = "i", fmts = numberRange },
	[L["Soul Shards"]] = { func = ValueSoulShards, unit = false, frequent = true, segment = true, fmts = integerRange },
	[L["Spell Tooltip"]] = { func = ValueTooltip, unit = false, comment = L["Tooltip comment"], fmts = onlyCustom },
	[L["Stagger"]] = { func = ValueUnitStagger, unit = true, fmt = "pct", fmts = integerRange },
	[L["Threat"]] = { func = ValueUnitThreat, unit = true, fmts = integerRange },
}

-- Initialize functions and data used by this module
function MOD:InitializeValues()
	valueFunctions = MOD.CopyTable(functionTable)
	if MOD.ExpansionIsOrBelow(LE_EXPANSION_WRATH_OF_THE_LICH_KING) then -- remove unsupported value types
		valueFunctions[L["Absorb"]] = nil
		valueFunctions[L["Azerite"]] = nil
		valueFunctions[L["Chi"]] = nil
		valueFunctions[L["Arcane Charges"]] = nil
		valueFunctions[L["Holy Power"]] = nil
		valueFunctions[L["Essence"]] = nil
		valueFunctions[L["Soul Shards"]] = nil
		valueFunctions[L["Runes"]] = nil
		valueFunctions[L["Rune 1"]] = nil
		valueFunctions[L["Rune 2"]] = nil
		valueFunctions[L["Rune 3"]] = nil
		valueFunctions[L["Rune 4"]] = nil
		valueFunctions[L["Rune 5"]] = nil
		valueFunctions[L["Rune 6"]] = nil
		valueFunctions[L["Stagger"]] = nil
		valueFunctions[L["Honor"]] = nil
		valueFunctions[L["Health + Incoming"]] = nil
	end
	startMoney = GetMoney()
	startTime = GetTime()
	scanTooltip = CreateFrame("GameTooltip", "Puffin_ScanTip", nil, "GameTooltipTemplate")
	scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	mirrorIcons = { BREATH = SHIM:GetSpellTexture(5697), DEATH = SHIM:GetSpellTexture(10848), EXHAUSTION = SHIM:GetSpellTexture(9256), FEIGNDEATH = SHIM:GetSpellTexture(5384) }
	iconXP = SHIM:GetItemIconByID(122270)
	iconRested = SHIM:GetItemIconByID(10940)
	iconMail = SHIM:GetItemIconByID(9555)
	iconClock = SHIM:GetItemIconByID(134376)
	iconCurrency = SHIM:GetSpellTexture(2481)
	iconLatency = SHIM:GetSpellTexture(2006)
	iconFramerate = SHIM:GetItemIconByID(12947)
	iconMap = SHIM:GetItemIconByID(4851)
	iconMapX = SHIM:GetSpellTexture(87219) or iconMap
	iconMapY = SHIM:GetSpellTexture(74922) or iconMap
	iconArrow = SHIM:GetItemIconByID(11104)
	iconLevel = SHIM:GetItemIconByID(8545)
	iconHealth = SHIM:GetSpellTexture(150554) or SHIM:GetItemIconByID(19711)
	iconPower = SHIM:GetSpellTexture(334538) or SHIM:GetItemIconByID(19714)
	iconCombo = SHIM:GetItemIconByID(16040)
	iconChi = SHIM:GetSpellTexture(179126) or iconPower
	iconArcaneCharge = SHIM:GetSpellTexture(190427)
	iconSoulShard = SHIM:GetSpellTexture(138556)
	iconRune = [[Interface\PlayerFrame\UI-PlayerFrame-Deathknight-SingleRune]]
	iconHeals = SHIM:GetSpellTexture(25297)
	iconAbsorb = SHIM:GetSpellTexture(5102)
	iconStagger = SHIM:GetSpellTexture(25750)
	iconThreat = SHIM:GetSpellTexture(26658)
	iconDurability = SHIM:GetItemIconByID(14387)
	iconAzerite = SHIM:GetItemIconByID(1706)
	iconCombat = SHIM:GetSpellTexture(674)
	iconHonor = SHIM:GetItemIconByID(20560)
	iconHonorHorde = SHIM:GetItemIconByID(21438)
	iconHonorAlliance = SHIM:GetItemIconByID(21436)
	iconReputation = SHIM:GetItemIconByID(20077)
	iconClassification = SHIM:GetItemIconByID(17442)
	iconResting = [[Interface\Addons\Raven\Icons\ZZZ.tga]]
end

-- Return function with a given name or nil if not found
function MOD:GetValueFunction(name)
	local f = valueFunctions[name]
	if f then return f.func end
	return nil
end

-- Return whether a function with a given name takes unit as an argument
function MOD:IsUnitValue(name)
	local f = valueFunctions[name]
	if f then return f.unit end
	return nil
end

-- Return whether a function with a given name needs frequent updates
function MOD:IsFrequentValue(name)
	local f = valueFunctions[name]
	if f then return f.frequent end
	return nil
end

-- Return whether a function with a given name needs segment support
function MOD:IsSegmentValue(name)
	local f = valueFunctions[name]
	if f then return f.segment end
	return nil
end

-- Return an optional comment for a value function
function MOD:GetValueComment(name)
	local f = valueFunctions[name]
	if f then return f.comment end
	return nil
end

-- Return an optional list of value bar names indirectly specified by a value
function MOD:GetValueBars(name)
	local f = valueFunctions[name]
	if f then return f.bars end
	return nil
end

-- Return the value's default text format and table of valid text formats
function MOD:GetValueFormat(name)
	local f = valueFunctions[name]
	if f then return f.fmt or "i", f.fmts or onlyInteger end
	return "i" , onlyInteger
end

-- Return a list of available value functions
function MOD:GetValuesList()
	local i, t = 0, {}
	for name, value in pairs(valueFunctions) do
		if not value.hidden then
			i = i + 1
			t[i] = name
		end
	end
	table.sort(t)
	return t, i
end
