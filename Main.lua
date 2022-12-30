-- Raven is an addon to monitor auras and cooldowns, providing timer bars and icons plus helpful notifications.
-- Author: Tomber
-- Copyright 2010-2019, All Rights Reserved

-- Main.lua contains initialization and update routines supporting Raven's core capability of tracking active auras and cooldowns.
-- It includes special cases for weapon buffs, stances, and trinkets.
-- It works primarily by tracking events that indicate when auras and spell casts occur. It maintains internal
-- tables of active auras to facilitate seamless tracking of auras, including casts that refresh ongoing auras.
-- In addition, it tracks combat log events in order to detect auras that the player has cast on multiple targets.
-- And, for cooldowns, it monitors events related to spells going onto cooldown.

-- Exported functions:
-- Raven:CheckAura(unit, name, isBuff) checks if an aura is active on a unit, returning detailed info if found
-- Raven:IterateAuras(unit, func, isBuff, p1, p2, p3) calls func for each active aura, parameters include a table with detailed aura info
-- Raven:CheckCooldown(name) checks if cooldown with the specified name is active, returning detailed info if found
-- Raven:IterateCooldowns(func, p1, p2, p3) calls func for each active cooldown, parameters include a table with detailed cooldown info
-- Raven:UnitHasBuff(unit, type) returns true and table with detailed info if unit has an active buff of the specified type (e.g., "Mainhand")
-- Raven:UnitHasDebuff(unit, type) returns true and table with detailed info if unit has an active debuff of the specified type (e.g., "Poison")

Raven = LibStub("AceAddon-3.0"):NewAddon("Raven", "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("Raven")
local media = LibStub("LibSharedMedia-3.0")
local MOD = Raven
local MOD_Options = "Raven_Options"
local _
local addonInitialized = false -- set when the addon is initialized
local addonEnabled = false -- set when the addon is enabled
local optionsLoaded = false -- set when the load-on-demand options panel module has been loaded
local optionsFailed = false -- set if loading the option panel module failed
local v, b, d, t = GetBuildInfo()
MOD.isWrathPTR = v == "3.4.1"
MOD.isModernAPI = true

if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
	MOD.isModernAPI = MOD.isWrathPTR
end

function MOD.ExpansionIsOrAbove(exp)
	if exp == nil then return false end --This is Vanilla
	return LE_EXPANSION_LEVEL_CURRENT >= exp
end

function MOD.ExpansionIsOrBelow(exp)
	if exp == nil then return true end --This is Vanilla
	return LE_EXPANSION_LEVEL_CURRENT <= exp
end

--MOD.isClassic = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) or (WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC) or (WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC)
MOD.updateOptions = false -- set this to cause the options panel to update (checked every half second)
MOD.LocalSpellNames = {} -- must be defined in first module loaded
local LSPELL = MOD.LocalSpellNames
MOD.frame = nil
MOD.db = nil
MOD.ldb = nil
MOD.ldbi = nil -- set when using DBIcon library
MOD.LibLDB = nil
MOD.myClass = nil; MOD.localClass = nil
MOD.myRace = nil; MOD.localRace = nil
MOD.lockoutSpells = {} -- spells for testing lock out of each school of magic for current player
MOD.classConditions = {} -- stores info about pre-defined conditions for each class
MOD.talents = {} -- table containing names and talent table location for each talent
MOD.talentList = {} -- table with list of talent names
MOD.runeSlots = {} -- cache information about each rune slot for DKs
MOD.runeCount = 0 -- current number of available runes
MOD.updateActions = true -- action bar changed
MOD.updateDispels = true -- need to update dispel types
MOD.knownBrokers = {} -- table of registered data brokers
MOD.brokerList = {} -- table of brokers suitable for a selection list
MOD.cooldownSpells = {} -- table of spell ids that have a cooldown to track, updated when spellbook changes
MOD.chargeSpells = {} -- table of spell ids with max charges
MOD.petSpells = {} -- table of pet spell ids with a cooldown to track
MOD.professionSpells = {} -- table of profession spell ids with a cooldown to track
MOD.bookSpells = {} -- table of spells currently available in the spell book
MOD.suppress = true -- this is set when certain special effects are to be disabled (e.g., at start up)
MOD.combatTimer = 0 -- if not 0 then this is set to the time when the player last entered combat
MOD.status = {} -- global status info cached by conditions module on every update



local doUpdate = true -- set by any event that can change bars (used to throttle major updates)
local forceUpdate = false -- set to cause immediate update (reserved for critical changes like to player's target or focus)
local suppressTime = nil -- set when addon code is loaded
local updateCooldowns = false -- set when actionbar or inventory slot cooldown starts or stops
local units = {} -- list of units to track
local mainUnits = { "player", "pet", "target", "focus", "targettarget", "focustarget", "pettarget", "mouseover" } -- ordered list of main units
local partyUnits = { "party1", "party2", "party3", "party4" } -- optional party units
local bossUnits = { "boss1", "boss2", "boss3", "boss4", "boss5" } -- optional boss units
local arenaUnits = { "arena1", "arena2", "arena3", "arena4", "arena5" } -- optional arena units
local nameplateUnits = {} -- cache of 40 nameplate unit ids
local eventUnits = { "targettarget", "focustarget", "pettarget", "mouseover" } -- can't count on events for these units
local tagUnits = { player = true, target = true, focus = true, pet = true, targettarget = true, focustarget = true, pettarget = true, mouseover = true } -- for hash tag generation
local unitUpdate = {} -- boolean for each unit that indicates need to update auras
local unitStatus = {} -- status of each unit set on every update (0 = no unit, 1 = unit exists, "unit" = unit is other unit)
local unitBuffs = {} -- indexed by GUID for tracking buffs cast by player
local unitDebuffs = {} -- indexed by GUID for tracking debuffs cast by player
local activeBuffs = {} -- active buffs for each unit
local activeDebuffs = {} -- active debuffs for each unit
local tagBuffs = {} -- cache of buff tags for each unit
local tagDebuffs = {} -- cache of debuff tags for each unit
local cacheBuffs = {} -- cache of active buff names
local cacheDebuffs = {} -- cache of active debuff names
local cacheUnits = {} -- cache of unit IDs, indexed by GUID
local refreshUnits = {} -- unit id cache used to optimize refresh
local tablePool = {} -- pool of available tables
local activeCooldowns = {} -- spells/items that are currently on cooldown
local internalCooldowns = {} -- tracking entries for internal cooldowns
local spellEffects = {} -- tracking entries for spell effects
local spellAlerts = {} -- tracking entries for spell alerts
local spellAlertCounter = 0 -- incremented with each spell alert
local spellAlertClassColors = nil -- set on first reference to table of class color hex strings
local lastTime = 0 -- time when last update happened
local lastTrackers = 0 -- time when last looked at trackers on major units
local lastWeapons = 0 -- time when last looked at weapon buffs
local elapsedTime = 0 -- time in seconds since last update
local updateCounter = 0 -- update counter included for testing
local refreshTime = 0 -- time since last animation refresh
local refreshCounter = 0 -- refresh counter included for testing
local throttleTime = 0 -- secondary throttle that resets once per second
local throttleCounter = 0 -- throttle counter included for testing
local throttleTracker = 0 -- throttle max count seen included for testing
local now = 0 -- refresh time value set at combat log and update events
local bufftooltip = nil -- used to store tooltip for scanning weapon buffs
local mhLastBuff = nil -- saves name of most recent main hand weapon buff
local ohLastBuff = nil -- saves name of most recent off hand weapon buff
local iconGCD = nil -- icon for global cooldown
local iconPotion = nil -- icon for shared potions cooldown
local iconElixir = nil -- icon for shared elixirs cooldown
local iconRune = nil -- icon for death knight runes
local lastTotems = {} -- cache last totems in each slot to see if changed
local lockedOut = false -- true if currently locked out of at least one spell school
local lockouts = {} -- schools of magic that we are currently locked out of
local lockstarts = {} -- start times for current school lockouts
local talentsInitialized = false -- set once talents have been initialized
local matchTable = {} -- passed from MOD:CheckAura with list of active auras
local startGCD, durationGCD = nil -- detect global cooldowns
local raidTargets = {} -- raid target to GUID
local petGUID = nil -- cache pet GUID so can properly remove trackers for them when dismissed
local enteredWorld = nil -- set by PLAYER_ENTERING_WORLD event
local trackerMarker = 0 -- used for mark/sweep in AddTrackers
local professions = {} -- temporary table for profession indices
local summonedCreatures = {} -- table of guids to expire time pairs used for tracking warlock creatures so they despawn properly
local minionTypes = {} -- temporary table for sorting minions by type
local minionCounts = {} -- temporary table for counting minions by type
local activeBrokers = {} -- table of brokers that trigger update events
local hiding = {} -- used to track elements of the UI so don't keep trying to show them
local bagCooldowns = {} -- table containing all the bag items with cooldowns
local inventoryCooldowns = {} -- table containing all the inventory items with cooldowns
local nullFunction = function() end -- used to disable Blizzard frames
local updateUIScale = false

local alertColors = { -- default colors for spell alerts
	EnemySpellCastAlerts = { r = 1, g = 0, b = 0, a = 1 },
	FriendSpellCastAlerts = { r = 0, g = 1, b = 0, a = 1 },
	EnemyBuffAlerts = { r = 1, g = 1, b = 0, a = 1 },
	FriendDebuffAlerts = { r = 1, g = 0, b = 1, a = 1 },
}

local UnitAura = UnitAura
MOD.LCD = nil
if MOD.ExpansionIsOrBelow(LE_EXPANSION_WRATH_OF_THE_LICH_KING) then
	MOD.LCD = LibStub("LibClassicDurations", true)
	if MOD.LCD then
		MOD.LCD:Register(Raven) -- tell library it's being used and should start working
		-- UnitAura = MOD.LCD.UnitAuraWrapper
		UnitAura = MOD.LCD.UnitAuraWithBuffs -- support buffs on enemy targets
	end
end

local band = bit.band -- shortcut for common bit logic operator

-- UnitAura no longer works with spell names in xxBfAxx so this function searches for them by scanning
-- While not the most efficient way to do this, it is generally used with a filter that should limit the depth of the search
-- This is only called for combat log events related to spell auras
function MOD.UnitAuraSpellName(unit, spellName, filter)
	local name, icon, count, btype, duration, expire, caster, isStealable, nameplateShowSelf, spellID, apply, boss
	if type(spellName) == "string" then -- sanity check only being called with a spell name
		for i = 1, 100 do
			name, icon, count, btype, duration, expire, caster, isStealable, nameplateShowSelf, spellID, apply, boss = UnitAura(unit, i, nil, filter)
			if name == spellName then break end
		end
	end
	return name, icon, count, btype, duration, expire, caster, isStealable, nameplateShowSelf, spellID, boss, apply
end

-- This table is used to fix the "not cast by player" bug for Jade Spirit, River's Song, and Dancing Steel introduced in 5.1
-- and the legendary meta gem procs Tempus Repit, Fortitude, Capacitance, and Lucidity added in 5.2
local fixEnchants = { [104993] = true, [120032] = true, [118334] = true, [118335] = true, [116660] = true,
					  [137590] = true, [137593] = true, [137331] = true, [137323] = true, [137247] = true, [137596] = true }

-- Initialization called when addon is loaded
function MOD:OnInitialize()
	if addonInitialized then return end -- only run this code once
	addonInitialized = true

	MOD.localClass, MOD.myClass = UnitClass("player") -- cache the player's class
	MOD.localRace, MOD.myRace = UnitRace("player") -- cache the player's race
	LoadAddOn("LibDataBroker-1.1")
	LoadAddOn("LibDBIcon-1.0")
	LoadAddOn("LibBossIDs-1.0", true)
	MOD.MSQ = LibStub("Masque", true)
	now = GetTime() -- start tracking time
	suppressTime = now -- start suppression period for certain special effects
end

-- Print debug messages with variable number of arguments in a useful format
function MOD.Debug(a, ...)
	if type(a) == "table" then
		for k, v in pairs(a) do print(tostring(k) .. " = " .. tostring(v)) end -- if first parameter is a table, print out its fields
	else
		local s = tostring(a) -- otherwise first argument is a string but just make sure
		local parm = {...}
		for i = 1, #parm do s = s .. " " .. tostring(parm[i]) end -- append remaining arguments converted to strings
		print(s)
	end
end

-- Hide or show a frame after checking settings
local function HideShow(key, frame, check, options)
	if not frame then return end -- added because not supported in classic but okay regardless

	local hideBlizz = MOD.db.profile.hideBlizz
	local hide, show = false, false
	local visible = frame:IsShown()
	if visible then
		if hideBlizz then hide = check end -- only hide if option for this frame is checked
	else
		if hideBlizz then show = not check and hiding[key] else show = hiding[key] end -- only show if Raven hid the frame
	end
	-- MOD.Debug("hide/show", key, "hide:", hide, "show:", show, "vis: ", visible)

	if not options then
		if hide then frame:Hide(); frame.Show = nullFunction; hiding[key] = true
		elseif show then frame.Show = nil; frame:Show(); hiding[key] = false end
	elseif options == "noshow" then
		if hide then frame:Hide(); frame.Show = nullFunction; hiding[key] = true
		elseif show then frame.Show = nil; hiding[key] = false end
	elseif options == "unreg" then
		if hide then frame:Hide(); frame.Show = nullFunction, frame:UnregisterAllEvents(); hiding[key] = true
		elseif show then frame.Show = nil; frame:RegisterAllEvents(); hiding[key] = false end
	elseif options == "buffs" then
		if hide then
			BuffFrame:Hide();

			if MOD.isModernAPI and MOD.ExpansionIsOrAbove(LE_EXPANSION_DRAGONFLIGHT) then
				DebuffFrame:Hide();
			end

			if TemporaryEnchantFrame then
				TemporaryEnchantFrame:Hide();
			end

			BuffFrame:UnregisterAllEvents();
			hiding[key] = true;
		elseif show then
			BuffFrame:Show();
			if MOD.isModernAPI and MOD.ExpansionIsOrAbove(LE_EXPANSION_DRAGONFLIGHT) then
				DebuffFrame:Show();
			end

			if TemporaryEnchantFrame then
				TemporaryEnchantFrame:Show();
			end

			BuffFrame:RegisterEvent("UNIT_AURA");
			hiding[key] = false;
		end
	end
end

-- Show or hide the blizzard frames, called during update so synched with other changes
local function CheckBlizzFrames()
	if MOD.ExpansionIsOrAbove(LE_EXPANSION_MISTS_OF_PANDARIA) and C_PetBattles.IsInBattle() then return end -- don't change visibility of any frame during pet battles

	local p = MOD.db.profile
	HideShow("buffs", _G.BuffFrame, p.hideBlizzBuffs, "buffs")

	if _G.TemporaryEnchantFrame then
		HideShow("enchants", _G.TemporaryEnchantFrame, p.hideBlizzBuffs, "enchants")
	end

	HideShow("player", _G.PlayerFrame, p.hideBlizzPlayer)
	HideShow("castbar", _G.PlayerCastingBarFrame, p.hideBlizzPlayerCastBar, "noshow")
	HideShow("mirror1", _G.MirrorTimer1, p.hideBlizzMirrors, "unreg")
	HideShow("mirror2", _G.MirrorTimer2, p.hideBlizzMirrors, "unreg")
	HideShow("mirror3", _G.MirrorTimer3, p.hideBlizzMirrors, "unreg")

	if MOD.myClass == "DEATHKNIGHT" then HideShow("runes", _G.RuneFrame, p.hideRunes) end

	local isDruid = (MOD.myClass == "DRUID")
	local isCat = isDruid and (GetShapeshiftForm(2) == 2)
	if isCat or (MOD.myClass == "ROGUE") then HideShow("combo", _G.ComboPointPlayerFrame, p.hideBlizzComboPoints) end
	if isDruid and not isCat then HideShow("combo", _G.ComboPointPlayerFrame, p.hideBlizzComboPoints, "noshow") end

	if MOD.myClass == "MONK" then
		HideShow("chi", _G.MonkHarmonyBarFrame, p.hideBlizzChi)
		if MOD.ExpansionIsOrAbove(LE_EXPANSION_MISTS_OF_PANDARIA) and GetSpecializationInfoByID(268) then HideShow("stagger", _G.MonkStaggerBar, p.hideBlizzStagger) end
	end

	if (MOD.myClass == "PRIEST") and (MOD.ExpansionIsOrAbove(LE_EXPANSION_MISTS_OF_PANDARIA) and GetSpecializationInfoByID(258)) then HideShow("insanity", _G.InsanityBarFrame, p.hideBlizzInsanity) end

	if MOD.myClass == "WARLOCK" then HideShow("shards", _G.WarlockPowerFrame, p.hideBlizzShards) end

	if MOD.myClass == "MAGE" then HideShow("arcane", _G.MageArcaneChargesFrame, p.hideBlizzArcane) end

	if MOD.myClass == "PALADIN" then HideShow("holy", _G.PaladinPowerBarFrame, p.hideBlizzHoly) end

	if MOD.myClass == "EVOKER" then HideShow("essence", _G.EvokerPowerBarFrame, p.hideBlizzEssence) end

	local totems = false; for i = 1, MAX_TOTEMS do if GetTotemInfo(i) then totems = true end end
	if totems then HideShow("totems", _G.TotemFrame, p.hideBlizzTotems) end
end

local function CheckCastBar(event, unit)
	if unit == "player" then HideShow("castbar", _G.PlayerCastingBarFrame, MOD.db.profile.hideBlizzPlayerCastBar, "noshow") end
end

local function CheckMirrorFrames()
	local p = MOD.db.profile
	HideShow("mirror1", _G.MirrorTimer1, p.hideBlizzMirrors, "unreg")
	HideShow("mirror2", _G.MirrorTimer2, p.hideBlizzMirrors, "unreg")
	HideShow("mirror23", _G.MirrorTimer3, p.hideBlizzMirrors, "unreg")
end

-- Functions called to trigger updates
local function TriggerPlayerUpdate() unitUpdate.player = true; updateCooldowns = true; doUpdate = true end
local function TriggerCooldownUpdate() updateCooldowns = true; doUpdate = true end
local function TriggerActionsUpdate() MOD.updateActions = true; doUpdate = true end
function MOD:ForceUpdate() doUpdate = true; forceUpdate = true end

-- Event called when the player changes talents or specialization
local function CheckTalentSpecialization() talentsInitialized = false; unitUpdate.player = true; doUpdate = true end

-- Function called to detect global cooldowns
local function CheckGCD(event, unit, spell)
	if unit == "player" and spell then
		local name = GetSpellInfo(spell) -- added verification of spell argument due to error seen while testing 1/1/2019
		if name and (name ~= "") then
			local start, duration = GetSpellCooldown(spell)
			if start and duration and (duration > 0) and (duration <= 1.5) then startGCD = start; durationGCD = duration; TriggerCooldownUpdate() end
		end
	end
	if event == "UNIT_SPELLCAST_START" then CheckCastBar(event, unit) end
end

-- Function called for successful spell cast
local function CheckSpellCasts(event, unit, lineID, spellID)
	CheckGCD(event, unit, spellID)
	local name = GetSpellInfo(spellID)
	if name and (name ~= "") and MOD.db.global.DetectSpellEffects then MOD:DetectSpellEffect(name, unit) end -- check if spell triggers a spell effect
end

-- Create and delete routines for managing tables, using a recycling pool to minimize garbage collection
local function AllocateTable() local b = next(tablePool); if b then tablePool[b] = nil else b = {} end return b end
local function ReleaseTable(b) table.wipe(b); tablePool[b] = true; return nil end

-- Compare unit and global ids, updating cache with latest info
local function CheckUnitIDs(uid, guid)
	local id = UnitGUID(uid)
	if id == guid then return uid end
	if id then cacheUnits[id] = uid end
	return nil
end

-- Add or update a tracker entry, including an optional marker useful for mark/sweep type garbage collection
local function AddTracker(dstGUID, dstName, isBuff, name, icon, count, btype, duration, expire, caster, isStealable, spellID, boss, apply, marker)
	doUpdate = true
	local tracker = isBuff and unitBuffs[dstGUID] or unitDebuffs[dstGUID] -- get or create the aura tracking table
	if not tracker then tracker = AllocateTable() if isBuff then unitBuffs[dstGUID] = tracker else unitDebuffs[dstGUID] = tracker end end
	local id = name .. tostring(spellID or "") -- append spellID if known to the tracker so can track multiple with same name (e.g., sacred shield)
	local t = tracker[id] -- get or create a tracker entry for the spell
	if not t then t = AllocateTable(); tracker[id] = t end -- create the tracker if necessary
	local vehicle = MOD.ExpansionIsOrAbove(LE_EXPANSION_CATACLYSM) and UnitHasVehicleUI("player")

	local tag = isBuff and "T-Buff:" or "T-Debuff:" -- build a unique tag for this aura (this is a bit simpler than the AddAura version)
	local guid = UnitGUID(caster)
	if guid then tag = tag .. guid .. ":" elseif caster then tag = tag .. caster .. ":" end -- include caster in unique tag, prefer guid when it is known
	if not tagUnits[caster or "unknown"] and expire and expire > 0 then tag = tag .. tostring(math.floor((expire * 100) + 0.5)) .. ":" end -- add expire time with 1/100s precision
	if spellID then tag = tag .. tostring(spellID) .. ":" end

	t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12], t[13], t[14], t[15], t[16], t[17], t[18], t[19], t[20], t[21], t[22] =
	true, 0, count, btype, duration, caster, isStealable, icon, tag, expire, "spell id", spellID, name, spellID,
	boss, UnitName("player"), apply, nil, vehicle, dstGUID, dstName, marker
end

-- Remove tracker entries for a unit, if marker is specified then only remove if tracker tag not equal
function MOD:RemoveTrackers(dstGUID, marker)
	doUpdate = true
	local tracker = unitBuffs[dstGUID] -- table of buffs currently applied to this GUID
	if tracker then
		for id, t in pairs(tracker) do if not marker or t[22] ~= marker then tracker[id] = ReleaseTable(t) end end
		if not next(tracker) then unitBuffs[dstGUID] = ReleaseTable(tracker) end -- release the debuffs associated with the GUID
	end
	local tracker = unitDebuffs[dstGUID] -- table of auras currently applied to this GUID
	if tracker then
		for id, t in pairs(tracker) do if not marker or t[22] ~= marker then tracker[id] = ReleaseTable(t) end end
		if not next(tracker) then unitDebuffs[dstGUID] = ReleaseTable(tracker) end -- release the table associated with the GUID
	end
end

-- Remove trackers for all units that match the name of the designated unit
function MOD:RemoveMatchingTrackers(dstGUID)
	local name = nil
	local tracker = unitBuffs[dstGUID] -- find name by looking at active trackers
	if tracker then for id, t in pairs(tracker) do name = t[21]; if name then break end end end
	if not name then
		tracker = unitDebuffs[dstGUID]
		if tracker then for id, t in pairs(tracker) do name = t[21]; if name then break end end end
	end
	MOD:RemoveTrackers(dstGUID) -- start by removing the trackers for the unit passed in
	if name then
		local guids = {} -- build list of guids to remove
		for id, tracker in pairs(unitBuffs) do
			if tracker then for _, t in pairs(tracker) do if t[21] == name then guids[id] = true break end end end
		end
		for id, tracker in pairs(unitDebuffs) do
			if tracker then for _, t in pairs(tracker) do if t[21] == name then guids[id] = true break end end end
		end
		for id in pairs(guids) do MOD:RemoveTrackers(id) end
	end
end

-- Check tracker entries for a unit to see if one already exists for a spell
local function CheckTrackers(isBuff, dstGUID, name, spellID)
	local tracker = isBuff and unitBuffs[dstGUID] or unitDebuffs[dstGUID] -- get the aura tracking table
	if tracker then
		local id = name .. tostring(spellID or "") -- append spellID if known
		local t = tracker[id]
		if t then
			if t[13] == name then return t end
		end
	end
	return nil
end

-- Add trackers for a unit
function MOD:AddTrackers(unit)
	local dstGUID, dstName = UnitGUID(unit), UnitName(unit)
	if dstGUID and dstName and not refreshUnits[dstGUID] then
		refreshUnits[dstGUID] = true
		local name, icon, count, btype, duration, expire, caster, isStealable, _, spellID, boss, apply
		trackerMarker = trackerMarker + 1 -- unique tag for this pass
		local i = 1
		repeat
			name, icon, count, btype, duration, expire, caster, isStealable, _, spellID, apply = UnitAura(unit, i, "HELPFUL|PLAYER")
			if name and caster == "player" then
				AddTracker(dstGUID, dstName, true, name, icon, count, btype, duration, expire, caster, isStealable, spellID, nil, apply, trackerMarker)
				MOD.SetDuration(name, spellID, duration)
				MOD.SetSpellType(spellID, btype)
			end
			i = i + 1
		until not name
		i = 1
		repeat
			name, icon, count, btype, duration, expire, caster, isStealable, _, spellID, apply, boss = UnitAura(unit, i, "HARMFUL|PLAYER")
			if name and caster == "player" then
				if spellID ~= 146739 or duration ~= 0 or InCombatLockdown() then -- don't add Corruption if out-of-combat
					AddTracker(dstGUID, dstName, false, name, icon, count, btype, duration, expire, caster, isStealable, spellID, boss, apply, trackerMarker)
					MOD.SetDuration(name, spellID, duration)
					MOD.SetSpellType(spellID, btype)
				end
			end
			i = i + 1
		until not name
		MOD:RemoveTrackers(dstGUID, trackerMarker) -- takes advantage of side-effect of saving current trackerMarker with each tracker
	end
end

-- Check if currently tracking a unit
local function IsBeingTracked(dstGUID) return unitBuffs[dstGUID] and unitDebuffs[dstGUID] end

-- Validate cached ids, garbage collect any that are out-of-date
local function ValidateUnitIDs()
	for guid, uid in pairs(cacheUnits) do if UnitGUID(uid) ~= guid then cacheUnits[guid] = nil end end
end

-- Get a unit id suitable for calling UnitAura from a GUID
local function GetUnitIDFromGUID(guid)
	if not guid then return nil end
	local uid = cacheUnits[guid] -- look up the guid in the cache and if it is there make sure it is still valid and then return it
	if uid then if guid == UnitGUID(uid) then return uid else uid = nil end end
	for _, unit in ipairs(units) do uid = CheckUnitIDs(unit, guid); if uid then break end end -- first check primary units
	local inRaid = IsInRaid()
	if not uid and not inRaid then -- check party, party pet, and party target units
		for i = 1, GetNumGroupMembers() do
			uid = CheckUnitIDs("party"..i, guid); if uid then break end
			uid = CheckUnitIDs("partypet"..i, guid); if uid then break end
			uid = CheckUnitIDs("party"..i.."target", guid); if uid then break end
		end
	end
	if not uid and inRaid then -- check raid, raid pet, and raid target units
		for i = 1, GetNumGroupMembers() do
			uid = CheckUnitIDs("raid"..i, guid); if uid then break end
			uid = CheckUnitIDs("raidpet"..i, guid); if uid then break end
			uid = CheckUnitIDs("raid"..i.."target", guid); if uid then break end
		end
	end
	if not uid then -- check nameplates as last resort
		for i = 1, 40 do
			local np = nameplateUnits[i]
			local id = UnitGUID(np)
			if not id then break end
			if id == guid then uid = np; break end
		end
	end
	cacheUnits[guid] = uid
	return uid
end

-- Parse a guid into fields and return them in a table
local parseTable = {}
local function ParseGUID(guid)
	table.wipe(parseTable) --  reused this since never nest calls to the function
	local start = 1
	local s = guid .. "-"
	local length = string.len(s)
	repeat
		local nextdash = string.find(s, "-", start)
		table.insert(parseTable, string.sub(s, start, nextdash - 1))
		start = nextdash + 1
	until start > length
	return parseTable
end

local function SpellAlertFilter(alerts, spellName, spellID, srcFlags, dstGUID)
	local spellNum = spellID and ("#" .. tostring(spellID)) -- string to look up the spell id in lists
	local list = alerts.spellList and MOD.db.global.SpellLists[alerts.spellList]
	local listed = list and (list[spellName] or (spellNum and list[spellNum])) -- check to see if spell is in the spell list
	if (alerts.blackList and listed) or (not alerts.blackList and not listed) then return false end

	local controlledBy = band(srcFlags, COMBATLOG_OBJECT_CONTROL_MASK)
	local byPlayer = (controlledBy == COMBATLOG_OBJECT_CONTROL_PLAYER)
	local byNPC = (controlledBy == COMBATLOG_OBJECT_CONTROL_NPC)
	local srcTarget = (band(srcFlags, COMBATLOG_OBJECT_TARGET) == COMBATLOG_OBJECT_TARGET)
	local srcFocus = (band(srcFlags, COMBATLOG_OBJECT_FOCUS) == COMBATLOG_OBJECT_FOCUS)
	local dstTarget, dstFocus, dstPlayer = false, false, false
	if dstGUID ~= "" then
		dstTarget = (dstGUID == UnitGUID("target"))
		dstFocus = (dstGUID == UnitGUID("focus"))
		dstPlayer = (dstGUID == UnitGUID("player"))
	end
	-- MOD.Debug("alert!", spellName, dstGUID, byPlayer, byNPC, srcTarget, srcFocus, dstTarget, dstFocus, dstPlayer)

	if alerts.include then
		local found = (alerts.isTarget and srcTarget) or (alerts.isFocus and srcFocus) or
				(alerts.isPlayer and byPlayer) or (alerts.isNPC and byNPC) or
				(alerts.includeTarget and dstTarget) or (alerts.includeFocus and dstFocus) or (alerts.includePlayer and dstPlayer)
		if not found then return false end
	end

	if alerts.exclude then
		local found = (alerts.notTarget and srcTarget) or (alerts.notFocus and srcFocus) or
				(alerts.notPlayer and byPlayer) or (alerts.notNPC and byNPC) or
				(alerts.excludeTarget and dstTarget) or (alerts.excludeFocus and dstFocus) or (alerts.excludePlayer and dstPlayer)
		if found then return false end
	end
	return true
end

local function AddSpellAlert(alertType, event, spellName, spellID, srcName, srcGUID, dstName, dstGUID)
	local alert = AllocateTable()
	alert.alertType = alertType; alert.event = event
	alert.start = now; alert.duration = MOD.db.global.SpellAlerts.duration or 3; alert.expire = now + alert.duration
	alert.spellName = spellName; alert.spellID = spellID; alert.icon = MOD:GetIcon(spellName, spellID)
	alert.srcName = srcName; alert.srcGUID = srcGUID; alert.srcUnit = GetUnitIDFromGUID(srcGUID)
	alert.dstName = dstName; alert.dstGUID = dstGUID; alert.dstUnit = GetUnitIDFromGUID(dstGUID)
	spellAlertCounter = spellAlertCounter + 1
	spellAlerts[spellAlertCounter] = alert
	-- MOD.Debug("alert", spellAlertCounter, alert.alertType, alert.event, alert.spellName, alert.icon, alert.srcName, alert.dstName)
	TriggerPlayerUpdate()
end

-- Remove any spell cast alerts for the guid
local function EndCastAlert(guid)
	for id, alert in pairs(spellAlerts) do
		if (alert.srcGUID == guid) and (alert.event == "SPELL_CAST_START") then spellAlerts[id] = ReleaseTable(alert); TriggerPlayerUpdate() end
	end
end

-- Remove any spell alert entries that have expired
local function CheckSpellAlerts()
	for id, alert in pairs(spellAlerts) do
		if now >= alert.expire then spellAlerts[id] = ReleaseTable(alert); TriggerPlayerUpdate() end
	end
end

-- Get label and color info for the spell alert
local function GetSpellAlertInfo(alert)
	local opts = MOD.db.global.SpellAlerts
	local label, spacer, showTarget, color = "", "", opts.labelTarget, alert.color
	local caster = alert.srcName
	local target = alert.dstName

	if not opts.showRealm then
		if caster then
			local i = string.find(caster, "-", 1, true)
			if i and (i > 1) then caster = string.sub(caster, 1, i - 1) end
		end
		if target then
			local i = string.find(target, "-", 1, true)
			if i and (i > 1) then target = string.sub(target, 1, i - 1) end
		end
	end

	if not spellAlertClassColors then
		spellAlertClassColors = {} -- generate table of class colors
		for class, c in pairs(RAID_CLASS_COLORS) do spellAlertClassColors[class] = string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
	end

	if opts.labelSpells then label = alert.spellName; spacer = " : " end

	if opts.labelCaster and caster then
		if alert.srcUnit then
			if opts.nameUnit then caster = alert.srcUnit end
			local _, class = UnitClass(alert.srcUnit)
			if class then
				local s = spellAlertClassColors[class]
				if s then caster = "|cff" .. s .. caster .. "|r" end
			end
		end
		label = label .. spacer .. caster
		spacer = " > "
		if opts.casterMatch and (alert.srcGUID == alert.dstGUID) then label = label .. " <<"; showTarget = false end
	end

	if opts.ignoreTargets and opts.ignoreList then
		local list = MOD.db.global.SpellLists[opts.ignoreList]
		local listed = list and (list[alert.spellName] or list[alert.spellID]) -- check to see if spell is in the ignore list
		if listed then showTarget = false end
	end

	if showTarget and target then
		if alert.dstUnit then
			if opts.nameUnit then target = alert.dstUnit end
			local _, class = UnitClass(alert.dstUnit)
			if class then
				local s = spellAlertClassColors[class]
				if s then target = "|cff" .. s .. target .. "|r" end
			end
		end
		label = label .. spacer .. target
	end

	if not color then color = alertColors[alert.alertType] end

	return color, label
end

local eventKill = { UNIT_DIED = true, UNIT_DESTROYED = true, UNIT_DISSIPATES = true, PARTY_KILL = true, SPELL_INSTAKILL = true, }
local eventAura = { SPELL_AURA_APPLIED = true, SPELL_AURA_APPLIED_DOSE = true, SPELL_AURA_REMOVED_DOSE = true, SPELL_AURA_REFRESH = true, }
local eventInternal = { SPELL_AURA_APPLIED = true, SPELL_AURA_APPLIED_DOSE = true, SPELL_AURA_REFRESH = true, SPELL_ENERGIZE = true, SPELL_HEAL = true, }
local eventEndCast = { SPELL_CAST_START = true, SPELL_CAST_SUCCESS = true, SPELL_CAST_FAILED = true, SPELL_MISSED = true }

-- Function called for combat log events to track hots and dots
local function CombatLogTracker() -- no longer passes in arguments with the event
	local timeStamp, e, hc, srcGUID, srcName, sf1, sf2, dstGUID, dstName, df1, df2, spellID, spellName, spellSchool, auraType, amount = CombatLogGetCurrentEventInfo()

	local isMine = band(sf1, COMBATLOG_OBJECT_AFFILIATION_MASK) == COMBATLOG_OBJECT_AFFILIATION_MINE
	if isMine then -- make sure event controlled by the player
		-- MOD.Debug(e, srcGUID, srcName, sf1, sf2, dstGUID, dstName, df1, df2, spellID, spellName, spellSchool, auraType, tostring(amount)) -- display all events
		doUpdate = true
		now = GetTime()
		if e == "SPELL_CAST_SUCCESS" or e == "SPELL_CAST_FAILED" then -- check for special cases involving spell casts
			if spellID == 104318 then
				local tyrant = false
				for guid, gt in pairs(summonedCreatures) do if gt.spell == 265187 then tyrant = true end end
				if not tyrant then -- if tyrant is not active then all imps reduce their energy by 1, if they reach 0 then remove them
					local gt = summonedCreatures[srcGUID]
					if gt and gt.energy then -- only imps have energy limit field defined
						gt.energy = gt.energy - 1
						if gt.energy <= 0 then summonedCreatures[srcGUID] = ReleaseTable(gt) end -- delete entry for this imp
					end
				end
			end
			if e == "SPELL_CAST_SUCCESS" then
				if spellID == 33763 then
					e = "SPELL_AURA_APPLIED"; auraType = "BUFF" -- Lifebloom refreshes don't always generate aura applied events
				elseif spellID == 265187 then -- summon demonic tyrant extends duration of all warlock minions
					for guid, gt in pairs(summonedCreatures) do
						gt.expire = gt.expire + 15; gt.duration = gt.duration + 15
					end
				elseif spellID == 196277 then -- implosion destroys all current warlock wild imps
					for guid, gt in pairs(summonedCreatures) do
						local pt = ParseGUID(guid)
						if pt[1] == "Creature" and ((pt[6] == "55659") or (pt[6] == "143622")) then -- found a wild imp!
							summonedCreatures[guid] = ReleaseTable(gt)
						end
					end
				elseif spellID == 980 then -- Agony refresh does not always generate aura refresh event, even if debuff just expired
					local t = CheckTrackers(false, dstGUID, spellName, spellID)
					if t then
						t[10] = now + t[5] -- extend the time on current tracker (preserves the dose amount)
					else
						e = "SPELL_AURA_REFRESH" -- event not generated automatically by Agony
					end
				end
			end
		elseif eventAura[e] then
			local name, icon, count, btype, duration, expire, caster, isStealable, boss, sid, apply, _
			local isBuff, dst = true, GetUnitIDFromGUID(dstGUID)
			if dst and UnitExists(dst) then
				name, icon, count, btype, duration, expire, caster, isStealable, _, sid, apply = MOD.UnitAuraSpellName(dst, spellName, "HELPFUL|PLAYER")
				if not name and (srcGUID ~= dstGUID) then -- don't get debuffs cast by player on self (e.g., Sated)
					isBuff = false
					name, icon, count, btype, duration, expire, caster, isStealable, _, sid, apply, boss = MOD.UnitAuraSpellName(dst, spellName, "HARMFUL|PLAYER")
				end
				if sid and spellID and spellID ~= sid then name = nil end -- not a match so must be a duplicate name
				if name then MOD.SetDuration(name, spellID, duration); MOD.SetSpellType(spellID, btype) end
			end
			if not spellID then spellID = MOD:GetSpellID(spellName) end
			if spellID and not icon then icon = MOD:GetIcon(spellName, spellID) end
			if not name then
				name = spellName; count = 1; btype = MOD.GetSpellType(spellID); duration = MOD.GetDuration(name, spellID); isBuff = (auraType == "BUFF")
				if duration > 0 then expire = now + duration else duration = 0; expire = 0 end
				if e == "SPELL_AURA_APPLIED_DOSE" or e == "SPELL_AURA_REMOVED_DOSE" then -- may be refresh of existing spell's stack count (e.g., Agony)
					count = amount
					local t = CheckTrackers(isBuff, dstGUID, name, spellID)
					if t then duration = t[5]; expire = t[10]; btype = t[4] end
				end
				caster = "player"; isStealable = nil; boss = nil; apply = nil
			end
			if name and caster == "player" and (isBuff or (srcGUID ~= dstGUID)) then
				AddTracker(dstGUID, dstName, isBuff, name, icon, count, btype, duration, expire, caster, isStealable, spellID, boss, apply, nil)
			end
			if dstGUID == UnitGUID("target") and not IsBeingTracked(dstGUID) then ValidateUnitIDs() end -- refresh all auras when target changes
			if MOD.db.global.DetectInternalCooldowns then MOD:DetectInternalCooldown(spellName, false) end -- check internal cooldowns
		elseif e == "SPELL_ENERGIZE" or e == "SPELL_HEAL" then
			if MOD.db.global.DetectInternalCooldowns then MOD:DetectInternalCooldown(spellName, false) end -- check internal cooldowns
		elseif e == "SPELL_AURA_REMOVED" then
			local tracker = unitBuffs[dstGUID] -- table of buffs currently applied to this GUID
			if tracker then
				local id = spellName .. tostring(spellID or "")
				local t = tracker[id] -- get tracker entry for the spell, if one exists
				if t then tracker[id] = ReleaseTable(t) end -- release the tracker entry
				if not next(tracker) then unitBuffs[dstGUID] = ReleaseTable(tracker) end -- release table when no more entries for this GUID
			end
			tracker = unitDebuffs[dstGUID] -- table of debuffs currently applied to this GUID
			if tracker then
				local id = spellName .. tostring(spellID or "")
				local t = tracker[id] -- get tracker entry for the spell, if one exists
				if t then tracker[id] = ReleaseTable(t) end -- release the tracker entry
				if not next(tracker) then unitDebuffs[dstGUID] = ReleaseTable(tracker) end -- release table when no more entries for this GUID
			end
		elseif e == "SPELL_SUMMON" then
			if MOD.myClass == "MAGE" and spellID == 99063 then -- special case for mage T12 2-piece
				local name = GetSpellInfo(99061) -- T12 bonus spell name
				if name and name ~= "" then
					if MOD.db.global.DetectInternalCooldowns then MOD:DetectInternalCooldown(name, false) end
					if MOD.db.global.DetectSpellEffects then MOD:DetectSpellEffect(name, "player") end
				end
			elseif MOD.myClass == "WARLOCK" and dstGUID and spellID then
				local duration = MOD.warlockCreatures[spellID]
				if duration then
					local gt = AllocateTable() -- use table pool for minion tracking
					gt.expire = duration + now; gt.duration = duration; gt.name = dstName; gt.icon = GetSpellTexture(spellID); gt.spell = spellID
					if duration == 22 then gt.energy = 5 end -- imps have 22 second duration and also are subject to energy limit for 5 casts
					summonedCreatures[dstGUID] = gt -- summoned creature table contains expire time, duration, name and icon
				end
			end
		end
	elseif dstGUID == UnitGUID("player") then
		if eventInternal[e] then
			if MOD.db.global.DetectInternalCooldowns then MOD:DetectInternalCooldown(spellName, true) end -- check aura triggers or cancels an internal cooldown
		end
	end

	if eventKill[e] then
		MOD:RemoveTrackers(dstGUID) -- remove the trackers currently associated with this GUID
		cacheUnits[dstGUID] = nil -- release the unit cache entry for this GUID
		local gt = summonedCreatures[dstGUID] -- remove GUID if on minion list for warlocks (probably only fires if someone kills a minion)
		if gt then summonedCreatures[dstGUID] = ReleaseTable(gt) end -- only release table when entry found
	end

	if MOD.db.global.DetectSpellAlerts and spellID and not isMine then -- check for spell alerts only if have a spell id and non-player event
		local stat, opts, pst = MOD.status, MOD.db.global.SpellAlerts, "solo"
		if GetNumGroupMembers() > 0 then if IsInRaid() then pst = "raid" else pst = "party" end end
		if ((stat.inArena and opts.showArena) or ((pst == "solo") and opts.showSolo) or ((pst == "party") and opts.showParty) or ((pst == "raid") and opts.showRaid)) and
				(stat.inInstance or opts.showNotInstance) then -- check if spell alerts are enabled given player's current status

			if eventEndCast[e] then EndCastAlert(srcGUID) elseif eventKill[e] then EndCastAlert(dstGUID) end -- end spell cast alerts when complete or interrupted
			if (e == "SPELL_CAST_SUCCESS") or ((e == "SPELL_CAST_START") and not MOD.db.global.SpellAlerts.hideCasting) then
				local reaction = band(sf1, COMBATLOG_OBJECT_REACTION_MASK)
				if MOD.db.global.EnemySpellCastAlerts.enabled and (reaction == COMBATLOG_OBJECT_REACTION_HOSTILE) then -- check for enemy spell casts
					if SpellAlertFilter(MOD.db.global.EnemySpellCastAlerts, spellName, spellID, sf1, dstGUID) then
						AddSpellAlert("EnemySpellCastAlerts", e, spellName, spellID, srcName, srcGUID, dstName, dstGUID)
					end
				end
				if MOD.db.global.FriendSpellCastAlerts.enabled and (reaction == COMBATLOG_OBJECT_REACTION_FRIENDLY) then -- check for friend spell casts
					if SpellAlertFilter(MOD.db.global.FriendSpellCastAlerts, spellName, spellID, sf1, dstGUID) then
						AddSpellAlert("FriendSpellCastAlerts", e, spellName, spellID, srcName, srcGUID, dstName, dstGUID)
					end
				end
			elseif e == "SPELL_AURA_APPLIED" then
				local reaction = band(df1, COMBATLOG_OBJECT_REACTION_MASK)
				if (auraType == "BUFF") and MOD.db.global.EnemyBuffAlerts.enabled and (reaction == COMBATLOG_OBJECT_REACTION_HOSTILE) then -- check for buffs on enemies
					if SpellAlertFilter(MOD.db.global.EnemyBuffAlerts, spellName, spellID, sf1, dstGUID) then
						AddSpellAlert("EnemyBuffAlerts", e, spellName, spellID, srcName, srcGUID, dstName, dstGUID)
					end
				end
				if (auraType == "DEBUFF") and MOD.db.global.FriendDebuffAlerts.enabled and (reaction == COMBATLOG_OBJECT_REACTION_FRIENDLY) then -- check for debuffs on friends
					if SpellAlertFilter(MOD.db.global.FriendDebuffAlerts, spellName, spellID, sf1, dstGUID) then
						AddSpellAlert("FriendDebuffAlerts", e, spellName, spellID, srcName, srcGUID, dstName, dstGUID)
					end
				end
			end
		end
	end
end

-- Check if there is a raid target on a unit
local function CheckRaidTarget(unit)
	local id = UnitGUID(unit)
	if id then
		local index = GetRaidTargetIndex(unit)
		for k, v in pairs(raidTargets) do if (v == id) and (k ~= index) then raidTargets[k] = nil end end
		if index then raidTargets[index] = id end
	end
end

-- Check raid targets on all addressable units
local function CheckRaidTargets()
	doUpdate = true
	for _, unit in pairs(units) do CheckRaidTarget(unit) end -- first check primary units
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do CheckRaidTarget("raid"..i); CheckRaidTarget("raidpet"..i); CheckRaidTarget("raid"..i.."target") end
	else
		for i = 1, GetNumGroupMembers() do CheckRaidTarget("party"..i); CheckRaidTarget("partypet"..i); CheckRaidTarget("party"..i.."target") end
	end
end

-- Check raid target on mouseover unit
local function CheckMouseoverRaidTarget() CheckRaidTarget("mouseover"); CheckRaidTarget("mouseovertarget"); doUpdate = true end

-- Return the raid target index for a GUID
function MOD:GetRaidTarget(id) for k, v in pairs(raidTargets) do if v == id then return k end end return nil end

-- When UI Scale changes need to recalculate pixel perfect settings and force a complete update
function UIScaleChanged() updateUIScale = true end

-- Event called when addon is enabled
function MOD:OnEnable()
	if addonEnabled then return end -- only run this code once
	addonEnabled = true

	MOD:InitializeProfile() -- initialize the profile database
	MOD:InitializeLDB() -- initialize the data broker
	MOD:RegisterChatCommand("raven", function() MOD:OptionsPanel() end)
	MOD.Nest_Initialize() -- initialize the graphics module
	MOD:InitializeConditions() -- initialize condition evaluation module
	MOD:InitializeValues() -- initialize functions used for value bars
	MOD:BAG_UPDATE("OnEnable") -- initialize bag cooldowns
	MOD:UNIT_INVENTORY_CHANGED("OnEnable", "player") -- initialize inventory cooldowns

	-- Create a frame so that updates can be registered
	MOD.frame = CreateFrame("Frame")
	-- Set frame level high so visible above other addons
	MOD.frame:SetFrameLevel(MOD.frame:GetFrameLevel() + 8)
	-- Register events called prior to starting play
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("UNIT_AURA")
	self:RegisterEvent("UNIT_POWER_UPDATE")
	self:RegisterEvent("UNIT_PET")
	self:RegisterEvent("UNIT_TARGET")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("SPELLS_CHANGED")
	self:RegisterEvent("BAG_UPDATE")
	self:RegisterEvent("UNIT_INVENTORY_CHANGED")
	self:RegisterEvent("RAID_TARGET_UPDATE", CheckRaidTargets)
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", CheckMouseoverRaidTarget)
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", TriggerPlayerUpdate)
	self:RegisterEvent("MINIMAP_UPDATE_TRACKING", TriggerPlayerUpdate)
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", TriggerCooldownUpdate)
	self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", TriggerCooldownUpdate)
	self:RegisterEvent("BAG_UPDATE_COOLDOWN", TriggerCooldownUpdate)
	self:RegisterEvent("PET_BAR_UPDATE_COOLDOWN", TriggerCooldownUpdate)
	self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", TriggerActionsUpdate)
	self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", TriggerActionsUpdate)
	self:RegisterEvent("PLAYER_TOTEM_UPDATE", TriggerPlayerUpdate)
	self:RegisterEvent("MIRROR_TIMER_START", CheckMirrorFrames)
	self:RegisterEvent("UNIT_SPELLCAST_START", CheckGCD)
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", CheckSpellCasts)
	self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", CheckCastBar)
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", CombatLogTracker)
	self:RegisterEvent("UI_SCALE_CHANGED", UIScaleChanged)

	if MOD.ExpansionIsOrBelow(LE_EXPANSION_WRATH_OF_THE_LICH_KING) then -- register events specific to classic
		if MOD.LCD then -- in classic, add library callback so target auras are handled correctly
			MOD.LCD.RegisterCallback(Raven, "UNIT_BUFF", function(e, unit)
				if unit ~= "target" then return end
				MOD:UNIT_AURA(e, unit)
			end)
		end
	else -- register events that are not implemented in classic
		self:RegisterEvent("PLAYER_FOCUS_CHANGED")
		self:RegisterEvent("PLAYER_TALENT_UPDATE", CheckTalentSpecialization)
		self:RegisterEvent("TRAIT_CONFIG_UPDATED", CheckTalentSpecialization)
		self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", CheckTalentSpecialization)
		self:RegisterEvent("VEHICLE_UPDATE")
		self:RegisterEvent("RUNE_POWER_UPDATE", TriggerCooldownUpdate)
	end

	MOD:InitializeBars() -- initialize routine that manages the bar library
	MOD:InitializeMedia(media) -- add sounds to LibSharedMedia
	MOD.LibBossIDs = LibStub("LibBossIDs-1.0", true)
	MOD.db.global.Version = "7" -- version number for database validation
end

-- Event called when addon is disabled but this is probably never called
function MOD:OnDisable() end

-- Cache icons for special purposes such as shared cooldowns
local function InitializeIcons()
	iconGCD = GetSpellTexture(28730) -- cached for global cooldown (using same icon as Arcane Torrent, must be valid)
	iconPotion = GetItemIcon(31677) -- icon for shared potions cooldown
	iconElixir = GetItemIcon(28104) -- icon for shared elixirs cooldown

	MOD:SetIcon(L["Rune"], GetSpellTexture(48266)) -- cached for death knight runes (this is for Frost Presence)
end

-- Updates will be driven by the new timer function, compute elapsed time since last update
local function UpdateHandler()
	now = GetTime()
	local elapsed = now - lastTime -- seconds since last call to update
	if elapsed > 1.0 then elapsed = 1.0 end -- should only happen during initialization
	MOD:Update(elapsed)
	lastTime = now
	C_Timer.After(0.001, UpdateHandler) -- register to be called for next frame
end

-- Initialize list of units that are tracked
function MOD:InitializeUnits()
	table.wipe(units)
	for i, k in pairs(mainUnits) do units[i] = k end
	if MOD.db.global.IncludePartyUnits then for _, k in pairs(partyUnits) do table.insert(units, k) end end
	if MOD.db.global.IncludeBossUnits then for _, k in pairs(bossUnits) do table.insert(units, k) end end
	if MOD.db.global.IncludeArenaUnits then for _, k in pairs(arenaUnits) do table.insert(units, k) end end
	for i = 1, 40 do nameplateUnits[i] = "nameplate"..i end
end

-- Initialize when play starts, deferred to allow system initialization to complete
function MOD:PLAYER_ENTERING_WORLD()
	if not enteredWorld then
		MOD:InitializeUnits() -- initialize list of units to track (this requires /reload to update)
		for _, k in pairs(units) do -- initialize tables used to track each unit's status and auras
			unitUpdate[k] = true; activeBuffs[k] = {} activeDebuffs[k] = {}
			tagBuffs[k] = {}; tagDebuffs[k] = {}; cacheBuffs[k] = {}; cacheDebuffs[k] = {}
		end
		updateCooldowns = true -- start tracking cooldowns
		MOD:InitializeBuffTooltip() -- initialize tooltip used to monitor weapon buffs
		InitializeIcons() -- cache special purpose icons
		MOD:InitializeOverlays() -- initialize overlays used to cancel player buffs
		MOD:InitializeInCombatBar() -- initialize special bar for cancelling buffs in combat
		MOD:UpdateAllBarGroups() -- final update before starting event-based updates
		CheckBlizzFrames() -- check blizz frames and hide the ones selected on the Defaults tab
		enteredWorld = true; doUpdate = true
		UpdateHandler() -- register for calls on every frame
	end
	if not InCombatLockdown() then collectgarbage("collect") end -- recover deleted preset data but not if in combat
end

-- Event called when an aura changes on a unit, returns the unit name
function MOD:UNIT_AURA(e, unit)
	if unit and (unitUpdate[unit] ~= nil) then
		if unit == "vehicle" then unitUpdate.player = true end -- any time vehicle updates, also update player
		unitUpdate[unit] = true; doUpdate = true
	end
end

-- Event called when a unit's power changes
function MOD:UNIT_POWER_UPDATE(e, unit) if unit == "player" then unitUpdate[unit] = true; doUpdate = true end end

-- Event for when vehicle info changes
function MOD:VEHICLE_UPDATE() TriggerPlayerUpdate() end

-- Event called with a unit's target changes
function MOD:UNIT_TARGET(e, unit)
	if unit == "player" then
		unitUpdate.target = true; doUpdate = true
	elseif unit == "target" then
		unitUpdate.targettarget = true; doUpdate = true
	elseif unit == "focus" then
		unitUpdate.focustarget = true; doUpdate = true
	elseif unit == "pet" then
		unitUpdate.pettarget = true; doUpdate = true
	end
end

-- Event called when a pet changes
function MOD:UNIT_PET() unitUpdate.pet = true; unitUpdate.pettarget = true; doUpdate = true end

-- Event called when the focus is changed
function MOD:PLAYER_FOCUS_CHANGED() unitUpdate.focus = true; unitUpdate.focustarget = true; doUpdate = true; forceUpdate = true end

-- Event called when the player's target is changed
function MOD:PLAYER_TARGET_CHANGED() unitUpdate.target = true; unitUpdate.targettarget = true; doUpdate = true; forceUpdate = true end

-- Event called when spells in spell book change
function MOD:SPELLS_CHANGED() MOD:SetCooldownDefaults(); updateCooldowns = true; doUpdate = true end

-- Event called when equipment in a unit's inventory changes
function MOD:UNIT_INVENTORY_CHANGED(e, unit)
	TriggerCooldownUpdate()
	if unit == "player" then
		-- update inventory cooldown table
		table.wipe(inventoryCooldowns) -- update inventory item cooldown table
		for slot = 0, 19 do -- check each inventory slot for usable items
			local itemID = GetInventoryItemID("player", slot)
			if itemID then
				local _, spellID = GetItemSpell(itemID)
				if spellID then inventoryCooldowns[itemID] = slot end
			end
		end
	end
	-- for k, v in pairs(inventoryCooldowns) do local name = GetItemInfo(k); MOD.Debug("slot", name, v) end
end

-- Event called when content of the player's bags changes
function MOD:BAG_UPDATE(e)
	TriggerCooldownUpdate()
	table.wipe(bagCooldowns) -- update bag item cooldown table
	for bag = 0, NUM_BAG_SLOTS do
		local numSlots
		if MOD.isModernAPI then
			numSlots = C_Container.GetContainerNumSlots(bag)
		else
			numSlots = GetContainerNumSlots(bag)
		end

		for slot = 1, numSlots do
			local itemID
			if MOD.isModernAPI then
				itemID = C_Container.GetContainerItemID(bag, slot)
			else
				itemID = GetContainerItemID(bag, slot)
			end
			if itemID then
				local _, spellID = GetItemSpell(itemID)
				if spellID then bagCooldowns[itemID] = spellID end
			end
		end
	end
	-- for k, v in pairs(bagCooldowns) do local name = GetItemInfo(k); MOD.Debug("bag", name, v) end
end

-- Create cache of talent info
local function InitializeTalents()
	if not MOD.ExpansionIsOrAbove(LE_EXPANSION_MISTS_OF_PANDARIA) then talentsInitialized = true; return end -- not supported in classic

	local tabs = GetNumSpecializations(false, false)
	if tabs == 0 then return end

	local currentSpec = GetSpecialization()
	talentsInitialized = true;
	doUpdate = true

	table.wipe(MOD.talents);
	table.wipe(MOD.talentList)

	activeConfigID = C_ClassTalents.GetActiveConfigID()
	if (activeConfigID) then
		configInfo = C_Traits.GetConfigInfo(activeConfigID);

		local select = 1
		for _, treeID in pairs(configInfo.treeIDs) do
			nodes = C_Traits.GetTreeNodes(treeID)

			for _, nodeID in pairs(nodes) do
				nodeInfo = C_Traits.GetNodeInfo(activeConfigID, nodeID)

				for _,entryID in pairs(nodeInfo.entryIDs) do
					entryInfo = C_Traits.GetEntryInfo(activeConfigID, entryID)

					definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
					name, rank, icon = GetSpellInfo(definitionInfo.spellID)

					if name then
						MOD.talents[name] = {
							tab = currentSpec,
							icon = icon,
							active = nodeInfo.currentRank > 0
						}
						MOD.talentList[select] = name
						select = select + 1
					end
				end
			end
		end

		table.sort(MOD.talentList)
		for i, t in pairs(MOD.talentList) do
			MOD.talents[t].select = i
		end
		MOD.updateDispels = true
	end
end

-- Check if the options panel is loaded, if not then get it loaded and ask it to toggle open/close status
function MOD:OptionsPanel()
	if not optionsLoaded then
		optionsLoaded = true
		local loaded, reason = LoadAddOn(MOD_Options)

		if not loaded then
			print(L["Failed to load "] .. tostring(MOD_Options) .. ": " .. tostring(reason))
			optionsFailed = true
		end
	end

	if not optionsFailed then MOD:ToggleOptions() end
end

-- If the options panel is loaded then update it so it reflects any changes made thru anchors, etc.
function MOD:UpdateOptionsPanel()
	if optionsLoaded and not optionsFailed and not IsMouseButtonDown("LeftButton") then MOD:UpdateOptions(); MOD.updateOptions = false end
	doUpdate = true
end

-- Add a registered data broker
local function RegisterDataBroker(event, name, broker)
	-- MOD.Debug("ldb_register", event, name, key, value)
	MOD.knownBrokers[name] = broker

	table.wipe(MOD.brokerList) -- recreate the broker list table
	local i = 1
	for k, v in pairs(MOD.knownBrokers) do MOD.brokerList[i] = k; i = i + 1 end
	table.sort(MOD.brokerList)
end

-- Update event handler for an activated data broker
local function UpdateDataBroker(event, name, key, value, dataobj)
	-- MOD.Debug("ldb_update", event, name, key, value)
	doUpdate = true
end

-- Activate a registered data broker when creating a custom bar reference (no need to deactivate since only used for updates)
function MOD:ActivateDataBroker(name)
	if not activeBrokers[name] then -- first time reference
		-- MOD.Debug("ldb_activate", name)
		activeBrokers[name] = true
		MOD.LibLDB.RegisterCallback("MyAnonCallback", "LibDataBroker_AttributeChanged_" .. name, UpdateDataBroker)
		doUpdate = true
	end
end

-- Tie into LibDataBroker
function MOD:InitializeLDB()
	MOD.LibLDB = LibStub("LibDataBroker-1.1", true)
	if not MOD.LibLDB then return end
	MOD.ldb = MOD.LibLDB:NewDataObject("Raven", {
		type = "launcher",
		text = "Raven",
		icon = "Interface\\Icons\\Spell_Nature_RavenForm",
		-- icon = [[Interface\AddOns\Raven\Raven]],
		OnClick = function(_, msg)
			if msg == "RightButton" then
				if IsShiftKeyDown() then
					MOD.db.profile.hideBlizz = not MOD.db.profile.hideBlizz
				else
					MOD:ToggleBarGroupLocks()
				end
			elseif msg == "LeftButton" then
				if IsShiftKeyDown() then
					MOD.db.profile.enabled = not MOD.db.profile.enabled
				else
					MOD:OptionsPanel()
				end
			end
			doUpdate = true
		end,
		OnTooltipShow = function(tooltip)
			if not tooltip or not tooltip.AddLine then return end
			tooltip:AddLine(L["Raven"])
			tooltip:AddLine(L["Raven left click"])
			tooltip:AddLine(L["Raven right click"])
			tooltip:AddLine(L["Raven shift left click"])
			tooltip:AddLine(L["Raven shift right click"])
		end,
	})
	MOD.ldbi = LibStub("LibDBIcon-1.0", true)
	if MOD.ldbi then MOD.ldbi:Register("Raven", MOD.ldb, MOD.db.global.Minimap) end

	for name, broker in MOD.LibLDB:DataObjectIterator() do RegisterDataBroker("register", name, broker) end
	MOD.LibLDB.RegisterCallback("MyAnonCallback", "LibDataBroker_DataObjectCreated", RegisterDataBroker)
end

-- See if totems have changed since last update because can't count on events for totems
local function CheckTotemUpdates()
	local cl = MOD.myClass
	if cl == "SHAMAN" or cl == "DRUID" or cl == "MAGE" then
		local changed = false
		for i = 1, MAX_TOTEMS do
			local haveTotem, name, startTime, duration = GetTotemInfo(i)
			if haveTotem and name and name ~= "" and now <= (startTime + duration) then
				if not lastTotems[i] or name ~= lastTotems[i] then changed = true end
				lastTotems[i] = name
			else
				if lastTotems[i] then changed = true end
				lastTotems[i] = nil
			end
		end
		if changed then updateCooldowns = true; unitUpdate.player = true; doUpdate = true; forceUpdate = true end
	end
end

-- Check for possess bar and vehicle updates which are not triggered by events
local function CheckMiscellaneousUpdates()
	if MOD.ExpansionIsOrAbove(LE_EXPANSION_CATACLYSM) then
		if IsPossessBarVisible() or UnitHasVehicleUI("player") then updateCooldowns = true; unitUpdate.player = true; doUpdate = true end
	end
end

-- Update routine called before each frame is displayed, throttled to minimize CPU usage
function MOD:Update(elapsed)
	local elapsedTarget = MOD.db.global.UpdateRate or 0.2
	local refreshTarget = MOD.db.global.AnimationRate or 0.03
	local throttleRate
	if InCombatLockdown() then
		throttleRate = MOD.db.global.CombatThrottleRate
		if MOD.combatTimer == 0 then MOD.combatTimer = now end
	else
		throttleRate = MOD.db.global.ThrottleRate
		MOD.combatTimer = 0
		if updateUIScale then
			updateUIScale = false -- updates are deferred while in combat and then happen after leaving combat
			MOD.Nest_UpdatePixelScale(false)
			MOD.Nest_DeleteAllBarGroups() -- delete existing display bar groups
			MOD:UpdateAllBarGroups() -- regenerate display bar groups
			forceUpdate = true
		end
	end
	local throttleTarget = elapsedTarget * (throttleRate or 5)

	if elapsedTime < 0 then elapsedTime = elapsed else elapsedTime = elapsedTime + elapsed end -- timer for update cycles
	if refreshTime < 0 then refreshTime = elapsed else refreshTime = refreshTime + elapsed end -- timer for refresh cycles
	throttleTime = throttleTime + elapsed -- timer for things that need to happen about once per second
	if throttleTime >= throttleTarget then -- equal to zero once per second
		throttleTime = 0; doUpdate = true
		if not suppressTime or ((now - suppressTime) > 3) then MOD.suppress = false end -- suppress special effects for several seconds at start
	end

	if MOD.db.profile.enabled then
		if forceUpdate or (elapsedTime >= elapsedTarget) then -- limit update rate
			if forceUpdate then doUpdate = true; forceUpdate = false; MOD.Nest_TriggerUpdate() end
			updateCounter = updateCounter + 1; refreshCounter = refreshCounter + 1; throttleCounter = throttleCounter + 1
			if throttleCounter > throttleTracker then throttleTracker = throttleCounter end -- tracker for actual throttle maximums
			if not talentsInitialized then InitializeTalents() end -- retry until talents initialized
			CheckTotemUpdates() -- check if totems have changed since last update
			CheckSpellAlerts() -- update spell alert timers
			CheckMiscellaneousUpdates() -- check for update requirements that don't have events
			MOD:UpdateInternalCooldowns() -- check for expiring internal cooldowns
			MOD:UpdateCooldownTimes() -- check for expiring normal cooldowns
			if doUpdate or MOD:CheckTimeEvents() then -- only do major updates when events warrant it (but at least once a second)
				MOD:UpdateSpellEffects() -- update spell effect timers
				MOD:UpdateAuras() -- update table containing current auras (actual processing is deferred until needed)
				MOD:UpdateTrackers() -- update aura trackers for multiple targets
				MOD:UpdateCooldowns() -- update table containing current cooldowns on spells and trinkets
				MOD:UpdateConditions() -- update table containing currently triggered conditions
				MOD.Nest_CheckDisplayDimensions() -- check display dimensions and update anchors if they have changed
				MOD:UpdateBars() -- update timer bars for auras and cooldowns
				MOD:UpdateInCombatBar() -- update the in-combat bar if necessary
				MOD.Nest_Update() -- update the display using the Nest graphics package
			else
				MOD:RefreshBars() -- update any value bars requiring frequent updates
				MOD:RefreshInCombatBar() -- update in-combat bar animations only
				MOD.Nest_Refresh() -- refresh bars in the Nest graphics package (helps smooth animations)
			end
			elapsedTime = elapsedTime - elapsedTarget; refreshTime = refreshTime - refreshTarget; doUpdate = false
		else
			if refreshTime >= refreshTarget then -- limit animation refesh rate
				MOD:RefreshBars() -- update any value bars requiring frequent updates
				MOD:RefreshInCombatBar() -- update in-combat bar animations only
				MOD.Nest_Refresh() -- refresh bars in the Nest graphics package (helps smooth animations)
				refreshTime = refreshTime - refreshTarget; refreshCounter = refreshCounter + 1
			end
		end
	else
		if throttleTime == 0 then -- check occasionally to make sure everything is in the right state
			elapsedTime = 0; refreshTime = 0 -- reset these counters once per second as well
			MOD:HideBars()
			MOD:HideInCombatBar()
		end
	end
	if throttleTime == 0 then
		-- if IsAltKeyDown() then MOD.Debug("update", updateCounter, "refresh", refreshCounter, "throttle", throttleTracker); throttleTracker = 0 end
		updateCounter = 0; refreshCounter = 0; throttleCounter = 0 -- these counters are only used for testing purposes
		if optionsLoaded and MOD:OptionsOpen() then -- check if options panel is open
			CheckBlizzFrames() -- need to check blizz settings occasionally when the options panel is open
			if MOD.updateOptions then MOD:UpdateOptionsPanel() end -- update the open option panel once per second, if requested
		end
	end
end

-- Aura tables have this structure:
-- b[1] = isBuff, b[2] = timeLeft, b[3] = stackCount, b[4] = auraType, b[5] = duration, b[6] = caster, b[7] = isStealable/effectCaster, b[8] = icon,
-- b[9] = hashTag, b[10] = expireTime, b[11] = tooltipType, b[12] = tooltipArgument, b[13] = name, b[14] = spellID, b[15] = isBoss, b[16] = casterName,
-- b[17] = castable, b[18] = casterIsNPC, b[19] = casterVehicle, b[20] = barColor, b[21] = barLabel

-- Calculate aura time left from expiration time and current time, this is always done before returning aura descriptors
-- If no duration or has expired then set to 0 (Blizzard may not yet have sent aura update event so could sit at 0 for a moment)
local function SetAuraTimeLeft(b) if b[5] > 0 then b[2] = b[10] - now if b[2] < 0 then b[2] = 0 end else b[2] = 0 end end

-- Check if a GUID belongs to a boss per LibBossIDs
function MOD.CheckLibBossIDs(guid)
	if type(guid) == "string" then
		local id
		_, _, _, _, _, id = string.match(guid, "(%a+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)")
		if id then
			id = tonumber(id)
			if id and MOD.LibBossIDs.BossIDs[id] then return true end
		end
	end
	return false
end

-- Add an active aura to the table for the specified unit
local function AddAura(unit, name, isBuff, spellID, count, btype, duration, caster, steal, boss, apply, icon, expire, tt_type, tt_arg, tt_color, tt_label)
	local auraTable = isBuff and activeBuffs[unit] or activeDebuffs[unit]
	local tagCache = isBuff and tagBuffs[unit] or tagDebuffs[unit]
	local auraCache = isBuff and cacheBuffs[unit] or cacheDebuffs[unit]
	if auraTable then
		local b = AllocateTable() -- get an empty aura descriptor
		local guid, cname, isNPC, vehicle = nil, nil, false, false
		if caster then
			guid = UnitGUID(caster); cname = UnitName(caster); vehicle = MOD.ExpansionIsOrAbove(LE_EXPANSION_CATACLYSM) and UnitHasVehicleUI(caster)
			if guid then
				local unitType = string.match(guid, "(%a+)%-")
				isNPC = (unitType == "Creature") or (unitType == "Vignette"); vehicle = vehicle or (unitType == "Vehicle")
				if isNPC and MOD.LibBossIDs then boss = boss or MOD.CheckLibBossIDs(guid) end
			end
		end
		local tag = isBuff and "Buff:" or "Debuff:" -- build a unique tag for this aura
		if guid then tag = tag .. guid .. ":" elseif caster then tag = tag .. caster .. ":" end -- include caster in unique tag, prefer guid when it is known
		if tt_type == "Minion" then tag = tag .. "Minion" .. tt_arg .. ":" end -- for warlock minions add the minion's guid to the tag
		if not tagUnits[caster or "unknown"] and expire and expire > 0 then tag = tag .. tostring(math.floor((expire * 100) + 0.5)) .. ":" end -- add expire time with 1/100s precision
		if spellID then tag = tag .. tostring(spellID) .. ":" elseif (tt_type == "weapon") or (tt_type == "tracking") then tag = tag .. tt_arg .. ":" end
		local n = (tagCache[tag] or 0) + 1; tagCache[tag] = n; tag = tag .. tostring(n) -- tag must be unique for multiples of same aura

		b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15], b[16], b[17], b[18], b[19], b[20], b[21] =
		isBuff, 0, count, btype, duration, caster, steal, icon, tag, expire, tt_type, tt_arg, name, spellID, boss, cname, apply, isNPC, vehicle, tt_color, tt_label

		auraTable[#auraTable + 1] = b
		if auraCache then auraCache[name] = true end
		if icon then MOD:SetIcon(name, icon) end -- cache icon for this aura
	end
end

-- Empty the aura tables for a unit by releasing all entries (except weapon buffs)
local function ReleaseAuras(unit)
	local buffTable, debuffTable, buffCache = activeBuffs[unit], activeDebuffs[unit], cacheBuffs[unit]
	table.wipe(buffCache); table.wipe(cacheDebuffs[unit]); table.wipe(tagBuffs[unit]); table.wipe(tagDebuffs[unit])
	if buffTable then for index, b in pairs(buffTable) do if b[11] ~= "weapon" then buffTable[index] = ReleaseTable(b) else buffCache[b[13]] = true end end end
	if debuffTable then for index, b in pairs(debuffTable) do debuffTable[index] = ReleaseTable(b) end end
end

-- Check if aura(s) with given name are active on the unit (if isBuff is true only check buffs, otherwise only debuff)
-- Return a table with matching aura descriptors, potentially empty if none are found
-- The returned table is only valid until the next call to MOD:CheckAura since it is reused each time
function MOD:CheckAura(unit, name, isBuff)
	table.wipe(matchTable)
	if unit and name then
		unit = MOD:UnitStatusUpdate(unit)
		if unit then
			local auraTable = isBuff and activeBuffs[unit] or activeDebuffs[unit]
			local auraCache = isBuff and cacheBuffs[unit] or cacheDebuffs[unit]
			if auraTable then
				if auraCache and auraCache[name] then
					for _, b in pairs(auraTable) do if b[13] == name then SetAuraTimeLeft(b); matchTable[#matchTable + 1] = b end end
				elseif string .find(name, "^#%d+") then -- check if name is in special format for specific spell id (i.e., #12345)
					local id = tonumber(string.sub(name, 2)) -- extract the spell id
					if id then for _, b in pairs(auraTable) do if b[14] == id then SetAuraTimeLeft(b); matchTable[#matchTable + 1] = b end end end
				end
			end
		end
	end
	return matchTable
end

-- For all active auras on a given unit (if isBuff is true only buffs, otherwise only debuff), call the function that
-- is passed in with the unit, aura name, aura descriptor table, isBuff, and two optional parameters passed in
function MOD:IterateAuras(unit, func, isBuff, p1, p2, p3)
	local auraTable
	if unit == "all" then -- special case to get auras cast by player on multiple targets
		auraTable = isBuff and unitBuffs or unitDebuffs
		for _, tracker in pairs(auraTable) do
			for _, t in pairs(tracker) do
				SetAuraTimeLeft(t) -- update timeLeft from current time
				if t[13] then func(unit, t[13], t, isBuff, p1, p2, p3) end
			end
		end
	else
		unit = MOD:UnitStatusUpdate(unit)
		if unit then
			auraTable = isBuff and activeBuffs[unit] or activeDebuffs[unit]
			if auraTable then
				for _, b in pairs(auraTable) do
					SetAuraTimeLeft(b) -- update timeLeft from current time
					if b[13] then func(unit, b[13], b, isBuff, p1, p2, p3) end
				end
			end
		end
	end
end

-- Release a particular player buff, including multiple copies, used for weapon buffs and tracking due to non-standard detection
local function ReleasePlayerBuff(name)
	local auraTable = activeBuffs.player
	if auraTable then
		for index, b in pairs(auraTable) do if b[13] == name then auraTable[index] = ReleaseTable(b) end end
	end
end

-- Check all buffs on the unit to see if the specified buff type is currently active, return true and the first found
function MOD:UnitHasBuff(unit, btype)
	unit = MOD:UnitStatusUpdate(unit)
	if unit then
		local auraTable = activeBuffs[unit]
		if auraTable then
			for _, b in pairs(auraTable) do if (btype == "Steal") and (b[7] == 1) or (b[4] == btype) then SetAuraTimeLeft(b); return true, b end end
		end
	end
	return false, nil
end

-- Check all debuffs on the unit to see if the specified debuff type is currently active, return true and the first found
function MOD:UnitHasDebuff(unit, btype)
	unit = MOD:UnitStatusUpdate(unit)
	if unit then
		local auraTable = activeDebuffs[unit]
		if auraTable then
			for _, b in pairs(activeDebuffs[unit]) do if (b[4] == btype) then SetAuraTimeLeft(b); return true, b end end
		end
	end
	return false, nil
end

-- Initialize tooltip to be used for determining weapon buffs
-- This code is based on the Pitbull implementation
function MOD:InitializeBuffTooltip()
	bufftooltip = CreateFrame("GameTooltip", "Raven_Weaponbuff_Tooltip", UIParent)
	bufftooltip:SetOwner(UIParent, "ANCHOR_NONE")
	local fs = bufftooltip:CreateFontString()
	fs:SetFontObject(_G.GameFontNormal)
	bufftooltip.tooltiplines = {} -- cache of font strings for each line in the tooltip
	for i = 1, 30 do
		local ls = bufftooltip:CreateFontString()
		ls:SetFontObject(_G.GameFontNormal)
		bufftooltip:AddFontStrings(ls, fs)
		bufftooltip.tooltiplines[i] = ls
	end
end

-- Return the temporary table for storing buff tooltips
function MOD:GetBuffTooltip()
	bufftooltip:ClearLines()

	if not bufftooltip:IsOwned(UIParent) then
		bufftooltip:SetOwner(UIParent, "ANCHOR_NONE")
	end

	return bufftooltip
end

-- No easy way to get this info, so scan item slot info for mainhand and offhand weapons using a tooltip
-- Weapon buffs are usually formatted in tooltips as name strings followed by remaining time in parentheses
-- This routine scans the tooltip for the first line that is in this format and extracts the weapon buff name without rank or time
local function GetWeaponBuffName(weaponSlot)
	local ttInfo = C_TooltipInfo.GetInventoryItem("player", weaponSlot, false)
	for i = 1, 30 do
		if ttInfo.lines[i] then
			if  ttInfo.lines[i].args[2] then
				local text = ttInfo.lines[i].args[2].stringVal
				if text then
					local name = text:match("^(.+) %(%d+ [^$)]+%)$") -- extract up to left paren if match weapon buff format
					if name then
						name = (name:match("^(.*) %d+$")) or name -- remove any trailing numbers
						return name
					end
				else
					break
				end
			end

		end

	end

	return nil
end

local function GetWeaponBuffNameOld(weaponSlot)
	local tt = MOD:GetBuffTooltip()
	tt:SetInventoryItem("player", weaponSlot)

	for i = 1, 30 do
		local text = tt.tooltiplines[i]:GetText()
		if text then
			local name = text:match("^(.+) %(%d+ [^$)]+%)$") -- extract up to left paren if match weapon buff format
			if name then
				name = (name:match("^(.*) %d+$")) or name -- remove any trailing numbers
				return name
			end
		else
			break
		end
	end

	return nil
end

-- Get weapon buff duration, since this is not supplied by Blizzard look at current detected duration
-- and compare it to longest previous duration for the given weapon buff in order to find maximum ever detected
local function GetWeaponBuffDuration(buff, duration)
	local maxd = MOD.db.profile.WeaponBuffDurations[buff]
	if not maxd then maxd = MOD.db.global.BuffDurations[buff] end -- backward compatibility
	if not maxd or (duration > maxd) then
		MOD.db.profile.WeaponBuffDurations[buff] = math.floor(duration + 0.5) -- round up
	else
		if maxd > duration then duration = maxd end
	end
	return duration
end

-- Reset the weapon buff duration cache since it will be restored when buff is cast again
local function ResetWeaponBuffDuration(buff) MOD.db.profile.WeaponBuffDurations[buff] = nil; MOD.db.global.BuffDurations[buff] = nil end

-- Add player weapon buffs for mainhand and offhand to the aura table
local function GetWeaponBuffs()
	-- old weapons buffs are now out-of-date so release them before regenerating
	if mhLastBuff then
		ReleasePlayerBuff(mhLastBuff)
	end

	if ohLastBuff then
		ReleasePlayerBuff(ohLastBuff)
	end

	-- first check if there are weapon auras then, only if necessary, use tooltip to scan for the buff names
	local mh, mhms, mhc, mx, oh, ohms, ohc, ox = GetWeaponEnchantInfo()
	if mh then -- add the mainhand buff, if any, to the table
		local islot = INVSLOT_MAINHAND
		local mhbuff
		if MOD.isModernAPI and not MOD.isWrathPTR then
			mhbuff = GetWeaponBuffName(islot)
		else
			mhbuff = GetWeaponBuffNameOld(islot)
		end
		local name, rank, icon, castTime, minRange, maxRange
		= GetSpellInfo(spellId or spellName or spellLink)

		if not mhbuff then -- if tooltip scan fails then use fallback of weapon name or slot name
			local weaponLink = GetInventoryItemLink("player", islot)
			if weaponLink then mhbuff = GetItemInfo(weaponLink) end
			if not mhbuff then mhbuff = L["Mainhand Weapon"] end
		end

		local icon = GetInventoryItemTexture("player", islot)
		local timeLeft = mhms / 1000
		local expire = now + timeLeft
		local duration = GetWeaponBuffDuration(mhbuff, timeLeft)

		AddAura("player", mhbuff, true, nil, mhc, "Mainhand", duration, "player", nil, nil, 1, icon, expire, "weapon", "MainHandSlot")
		mhLastBuff = mhbuff -- caches the name of the weapon buff so can clear it later
	elseif mhLastBuff then
		ResetWeaponBuffDuration(mhLastBuff);
		mhLastBuff = nil
	end

	if oh then -- add the offhand buff, if any, to the table
		local islot = INVSLOT_OFFHAND
		local ohbuff
		if MOD.isModernAPI and not MOD.isWrathPTR then
			ohbuff = GetWeaponBuffName(islot)
		else
			ohbuff = GetWeaponBuffNameOld(islot)
		end

		if not ohbuff then -- if tooltip scan fails then use fallback of weapon name or slot name
			local weaponLink = GetInventoryItemLink("player", islot)
			if weaponLink then ohbuff = GetItemInfo(weaponLink) end
			if not ohbuff then ohbuff = L["Offhand Weapon"] end
		end

		local icon = GetInventoryItemTexture("player", islot)
		local timeLeft = ohms / 1000
		local expire = now + timeLeft
		local duration = GetWeaponBuffDuration(ohbuff, timeLeft)

		AddAura("player", ohbuff, true, nil, ohc, "Offhand", duration, "player", nil, nil, 1, icon, expire, "weapon", "SecondaryHandSlot")
		ohLastBuff = ohbuff -- caches the name of the weapon buff so can clear it later
	elseif ohLastBuff then
		ResetWeaponBuffDuration(ohLastBuff);
		ohLastBuff = nil
	end
end

-- Add buffs for the specified unit to the active buffs table
local function GetBuffs(unit)
	local name, icon, count, btype, duration, expire, caster, isStealable, nameplatePersonal, spellID, apply, boss, castByPlayer, showOnNameplate
	local i = 1
	repeat
		name, icon, count, btype, duration, expire, caster, isStealable, nameplatePersonal, spellID, apply, boss, castByPlayer, showOnNameplate = UnitAura(unit, i, "HELPFUL")
		if name then
			if not caster then if spellID and fixEnchants[spellID] then caster = "player" else caster = "unknown" end -- fix Jade Spirit, Dancing Steel, River's Song
			elseif caster == "vehicle" then caster = "player" end -- vehicle buffs treated like player buffs
			if caster == "player" then MOD.SetDuration(name, spellID, duration); MOD.SetSpellType(spellID, btype) end
			AddAura(unit, name, true, spellID, count, btype, duration, caster, isStealable, boss, apply, icon, expire, "buff", i)
		end
		i = i + 1
	until not name

	if unit ~= "player" then return end -- done for all but player, players also need to add vehicle buffs
	if MOD.ExpansionIsOrBelow(LE_EXPANSION_WRATH_OF_THE_LICH_KING) or not UnitHasVehicleUI("player") then return end
	i = 1
	repeat
		name, icon, count, btype, duration, expire, caster, isStealable, _, spellID, apply, boss = UnitAura("vehicle", i, "HELPFUL")
		if name then
			if not caster then caster = "unknown" elseif caster == "vehicle" then caster = "player" end -- vehicle buffs treated like player buffs
			if caster == "player" then MOD.SetDuration(name, spellID, duration); MOD.SetSpellType(spellID, btype) end
			AddAura(unit, name, true, spellID, count, btype, duration, caster, isStealable, boss, apply, icon, expire, "vehicle buff", i)
		end
		i = i + 1
	until not name
end

-- Add debuffs for the specified unit to the active debuffs table
local function GetDebuffs(unit)
	local name, icon, count, btype, duration, expire, caster, isStealable, nameplatePersonal, spellID, apply, boss, castByPlayer, showOnNameplate
	local i = 1
	repeat
		name, icon, count, btype, duration, expire, caster, isStealable, nameplatePersonal, spellID, apply, boss, castByPlayer, showOnNameplate = UnitAura(unit, i, "HARMFUL")
		if name then
			if not caster then caster = "unknown" elseif caster == "vehicle" then caster = "player" end -- vehicle debuffs treated like player debuffs
			if caster == "player" then MOD.SetDuration(name, spellID, duration); MOD.SetSpellType(spellID, btype) end
			AddAura(unit, name, false, spellID, count, btype, duration, caster, isStealable, boss, apply, icon, expire, "debuff", i)
		end
		i = i + 1
	until not name

	if unit ~= "player" then return end -- done for all but player, players also need to add vehicle debuffs
	if MOD.ExpansionIsOrBelow(LE_EXPANSION_WRATH_OF_THE_LICH_KING) or not UnitHasVehicleUI("player") then return end
	i = 1
	repeat
		name, icon, count, btype, duration, expire, caster, isStealable, _, spellID, apply, boss = UnitAura("vehicle", i, "HARMFUL")
		if name then
			if not caster then caster = "unknown" elseif caster == "vehicle" then caster = "player" end -- vehicle debuffs treated like player debuffs
			if caster == "player" then MOD.SetDuration(name, spellID, duration); MOD.SetSpellType(spellID, btype) end
			AddAura(unit, name, false, spellID, count, btype, duration, caster, isStealable, boss, apply, icon, expire, "vehicle debuff", i)
		end
		i = i + 1
	until not name
end

-- Add tracking auras (updated for Cataclysm which allows multiple active tracking types)
local function GetTracking()
	local notTracking, notTrackingIcon, found = L["Not Tracking"], "Interface\\Minimap\\Tracking\\None", false
	local trackingTypes = nil
	if MOD.isModernAPI then
		trackingTypes = C_Minimap.GetNumTrackingTypes()
	else
		if MOD.ExpansionIsOrAbove(LE_EXPANSION_WRATH_OF_THE_LICH_KING) then
			trackingTypes = GetNumTrackingTypes()
		else
			return
		end
	end

	for i = 1, trackingTypes do
		local tracking
		local trackingIcon
		local active
		if MOD.isModernAPI then
			tracking, trackingIcon, active = C_Minimap.GetTrackingInfo(i)
		else
			tracking, trackingIcon, active = GetTrackingInfo(i)
		end

		if active then
			found = true
			AddAura("player", tracking, true, nil, 1, "Tracking", 0, "player", nil, nil, nil, trackingIcon, 0, "tracking", tracking)
		end
	end
	if not found then
		AddAura("player", notTracking, true, nil, 1, "Tracking", 0, "player", nil, nil, nil, notTrackingIcon, 0, "tracking", notTracking)
	end
end

-- Check if the spell triggers a spell effect
function MOD:DetectSpellEffect(name, caster)
	local ect = MOD.db.global.SpellEffects[name] -- check for new spell effect triggered by this spell
	if ect and not ect.disable and MOD:CheckCastBy(caster, ect.caster or "player") then
		local duration = ect.duration
		if not duration then return end -- safety check
		if ect.talent and not MOD.CheckTalent(ect.talent) then return end -- check required talent
		if ect.buff then local auraList = MOD:CheckAura("player", ect.buff, true); if #auraList == 0 then return end end -- check required buff
		if ect.optbuff and ect.optduration then -- check optional buff and test safety for the duration
			local auraList = MOD:CheckAura("player", ect.optbuff, true)
			if #auraList > 0 then duration = ect.optduration end
		end
		if ect.condition and not MOD:CheckCondition(ect.condition) then return end -- check required condition
		local ec = spellEffects[name]
		if ec and ect.renew then spellEffects[name] = ReleaseTable(ec); ec = nil end -- check if already active spell effect and optionally renew
		if not ec then ec = AllocateTable(); ec.start = now; ec.expire = ec.start + duration; ec.caster = caster;
			spellEffects[name] = ec; TriggerPlayerUpdate() end
	end
end

-- Remove any spell effect entries that have expired
function MOD:UpdateSpellEffects()
	for id, ec in pairs(spellEffects) do if now >= ec.expire then spellEffects[id] = ReleaseTable(ec); TriggerPlayerUpdate(); TriggerCooldownUpdate() end end
end

-- Check if any spell effects are active and add them to the player auras
local function GetSpellEffectAuras()
	for name, ec in pairs(spellEffects) do
		local ect = MOD.db.global.SpellEffects[name]
		if ect and not ect.disable and ect.kind ~= "cooldown" then
			local spell = ect.spell or name
			AddAura("player", spell, not ect.kind, ect.id, 1, nil, ect.duration, ec.caster, nil, nil, nil, ect.icon, ec.expire, "effect", name)
		end
	end
end

-- Automatically generate alert bars
local function GetSpellAlertAuras()
	for id, alert in pairs(spellAlerts) do
		local kind = MOD.db.global[alert.alertType].kind
		if kind ~= "cooldown" then
			local color, label = GetSpellAlertInfo(alert)
			-- MOD.Debug("alertaura", id, (kind == nil) and "buff" or kind, alert.alertType, alert.event, alert.spellName, alert.srcName, alert.dstName, label)
			AddAura("player", alert.spellName, not kind, alert.spellID, 1, nil, alert.duration, "player", nil, nil, nil, alert.icon, alert.expire, "alert", alert.spellID, color, label)
		end
	end
end

-- Create an aura for class-specific power buffs: soul shards, holy power, shadow orbs, etc.
local function GetPowerBuffs()
	local power, id = nil, nil
	local myClass = MOD.myClass
	if myClass == "PALADIN" and IsSpellKnown(35395) then power = UnitPower("player", Enum.PowerType.HolyPower); id = 85247
	elseif myClass == "EVOKER" and IsSpellKnown(361469) then power = UnitPower("player", Enum.PowerType.Essence); id = 359618
	elseif myClass == "PRIEST" and IsSpellKnown(8092) then power = UnitPower("player", Enum.PowerType.Insanity); id = 57496
	elseif myClass == "WARLOCK" then power = UnitPower("player", Enum.PowerType.SoulShards); id = 138556
	elseif myClass == "SHAMAN" and IsSpellKnown(193786) then power = UnitPower("player", Enum.PowerType.Maelstrom); id = 190185
	elseif myClass == "MAGE" then
		if IsSpellKnown(116011) then -- rune of power
			local haveTotem, name, startTime, duration, icon = GetTotemInfo(1)
			if haveTotem and name and name ~= "" and now <= (startTime + duration) then
				local sp = GetSpellInfo(52623)
				AddAura("player", sp, true, 52623, 1, "Power", duration, "player", nil, nil, 1, icon, startTime + duration, "text", sp)
			end
		end
		if IsSpellKnown(30451) then power = UnitPower("player", Enum.PowerType.ArcaneCharges); id = 190427 end
	elseif myClass == "DEMONHUNTER" then
		if IsSpellKnown(203720) then -- vengeanance
			power = UnitPower("player", Enum.PowerType.Pain); id = 185244
		else -- havoc
			power = UnitPower("player", Enum.PowerType.Fury); id = 67671
		end
	elseif myClass == "MONK" and IsSpellKnown(100780) then -- only windwalker has chi now
		local chi = UnitPower("player", Enum.PowerType.Chi)
		local _, pToken = UnitPowerType("player")
		local name = _G[pToken]
		local icon = GetSpellTexture(179126)
		if chi and chi > 0 then
			AddAura("player", name, true, nil, chi, "Power", 0, "player", nil, nil, nil, icon, 0, "text", name)
			return
		end
	elseif myClass == "DRUID" then
		if IsSpellKnown(145205) then -- restoration druid has one mushroom linked to Efflorescence
			local haveTotem, name, startTime, duration, icon = GetTotemInfo(1)
			if haveTotem and name and name ~= "" and now <= (startTime + duration) then
				AddAura("player", name, true, 145205, 1, nil, duration or 0, "player", nil, nil, nil, icon, (startTime or 0) + (duration or 0), "text", name)
				return
			end
		elseif IsSpellKnown(190984) then -- balance druid has astral power
			local ap = UnitPower("player", Enum.PowerType.LunarPower)
			local _, pToken = UnitPowerType("player")
			local name = _G[pToken]
			local icon = GetSpellTexture(164686) -- dark eclipse
			AddAura("player", name, true, nil, ap, "Power", 0, "player", nil, nil, nil, icon, 0, "text", name)
			return
		end
	end
	if power and power > 0 then
		local name, _, icon = GetSpellInfo(id)
		if name and (name ~= "") then
			AddAura("player", name, true, id, power, "Power", 0, "player", nil, nil, nil, icon, 0, "text", name)
		end
	end
end

-- Get buffs for shaman totems if option is selected
local function GetTotemBuffs()
	if MOD.myClass == "PALADIN" then -- consecration totem
		local haveTotem, name, startTime, duration, icon = GetTotemInfo(1)
		if haveTotem and name and name ~= nil and now <= (startTime + duration) then
			AddAura("player", name, true, nil, 1, "buff", duration, "player", nil, nil, nil, icon, startTime + duration, "totem", 1)
		end
	elseif MOD.myClass == "SHAMAN" then
		for i = 1, MAX_TOTEMS do
			local haveTotem, name, startTime, duration, icon = GetTotemInfo(i)
			if haveTotem and name and name ~= "" and now <= (startTime + duration) then -- generate buff for an active totem in the slot
				AddAura("player", name, true, nil, 1, "Totem", duration, "player", nil, nil, nil, icon, startTime + duration, "totem", i)
			end
		end
	end
end

-- Get buffs for warlock minions, verifying not already expired and sorted so only one per type of minion
local function GetMinionBuffs()
	if MOD.myClass == "WARLOCK" then -- minions are tracked in the summonedCreatures table by combat log events
		local mh = minionTypes -- temporary table for sorting minions by type
		local mc = minionCounts -- temporary table for counting minions by type
		table.wipe(mh) -- table entries are type->guid
		table.wipe(mc) -- table entries are type->count
		for guid, gt in pairs(summonedCreatures) do -- find soonest to expire for each type of minion
			if gt.expire and (now < gt.expire) then -- make sure has not expired already
				local mtype = gt.name -- name of creature is type
				mc[mtype] = (mc[mtype] or 0) + 1 -- increment count of this minion type
				local m = mh[mtype] -- get guid of currently soonest to expire of this minion type
				if not m or (gt.expire < summonedCreatures[m].expire) then mh[mtype] = guid end
			end
		end
		for name, guid in pairs(mh) do -- add a buff for each type of minion
			local gt = summonedCreatures[guid]
			if gt then
				AddAura("player", name, true, nil, mc[name], "Minion", gt.duration, "player", gt.energy, nil, nil, gt.icon, gt.expire, "minion", guid)
			end
		end
	end
end

-- Update unit auras if necessary (deferred until requested)
function MOD:UnitStatusUpdate(unit)
	local status = unitStatus[unit]
	if status ~= 0 then
		if status ~= 1 then unit = status end
		if unitUpdate[unit] then -- need to do an update for this unit
			ReleaseAuras(unit); GetBuffs(unit); GetDebuffs(unit)
			if unit == "player" then GetTracking(); GetSpellEffectAuras(); GetSpellAlertAuras(); GetPowerBuffs(); GetTotemBuffs(); GetMinionBuffs() end
			unitUpdate[unit] = false
		end
		return unit
	end
	return nil
end

-- Check unit status, return 0 if doesn't exist, 1 if valid unit, "unit" if mirroring another unit
function MOD:ValidateUnit(unit)
	if UnitExists(unit) then
		for _, k in pairs(units) do
			if unit == k then return 1 end -- found unique unit
			if UnitIsUnit(unit, k) then return k end -- found match to higher priority unit
		end
	end
	return 0 -- not a valid unit
end

-- Check all the tracker entries and remove any that have expired
function MOD:UpdateTrackers()
	for _, tracker in pairs(unitBuffs) do
		for k, t in pairs(tracker) do SetAuraTimeLeft(t); if (t[5] > 0) and (t[2] == 0) then tracker[k] = ReleaseTable(t) end end
	end
	for _, tracker in pairs(unitDebuffs) do
		for k, t in pairs(tracker) do SetAuraTimeLeft(t); if (t[5] > 0) and (t[2] == 0) then tracker[k] = ReleaseTable(t) end end
	end

	if MOD.myClass == "WARLOCK" then -- check if warlock's summoned creatures have expired
		for guid, gt in pairs(summonedCreatures) do
			if gt.expire and gt.expire <= now then
				MOD:RemoveTrackers(guid) -- remove the trackers currently associated with this GUID, if any
				cacheUnits[guid] = nil -- release the unit cache entry for this GUID too
				summonedCreatures[guid] = ReleaseTable(gt) -- release table back to pool
			end
		end
		if not InCombatLockdown() then -- if out of combat then release unlimited duration trackers for Corruption (needed for Absolute Corruption talent)
			local corruption = GetSpellInfo(172) -- use localized string for Corruption instead of spell id, in case multiple ids are involved
			for _, tracker in pairs(unitDebuffs) do
				for k, t in pairs(tracker) do if (t[13] == corruption) and (t[5] == 0) then tracker[k] = ReleaseTable(t) end end
			end
		end
	end

	if (lastTrackers == 0) or ((now - lastTrackers) > 0.5) then -- things to do every half second...
		lastTrackers = now
		ValidateUnitIDs()
		table.wipe(refreshUnits) -- table of guids to prevent refreshing multiple times
		MOD:AddTrackers("player"); MOD:AddTrackers("target");  MOD:AddTrackers("focus")
		if IsInRaid() then
			for i = 1, GetNumGroupMembers() do MOD:AddTrackers("raid"..i); MOD:AddTrackers("raidpet"..i); MOD:AddTrackers("raid"..i.."target") end
		else
			for i = 1, GetNumGroupMembers() do MOD:AddTrackers("party"..i); MOD:AddTrackers("partypet"..i); MOD:AddTrackers("party"..i.."target") end
		end
		local pgid = UnitGUID("pet")
		if petGUID and (petGUID ~= pgid) then MOD:RemoveTrackers(petGUID) end
		petGUID = pgid; if pgid then MOD:AddTrackers("pet") end
		for i = 1, 40 do -- nameplate scanning improves accuracy dramatically
			local np = nameplateUnits[i]
			if UnitExists(np) then MOD:AddTrackers(np) else break end
		end
	end
end

--[[
function MOD.DebugTrackers(whence)
	MOD.Debug("Trackers: ", whence)
	for id, tracker in pairs(unitBuffs) do for k, t in pairs(tracker) do MOD.Debug("buff", id, t[13]) end end
	for id, tracker in pairs(unitDebuffs) do for k, t in pairs(tracker) do MOD.Debug("debuff", id, t[13]) end end
end
]]--

-- Update aura table with current player, target and focus auras and debuffs, include player weapon buffs
function MOD:UpdateAuras()
	-- set current unit status, defer actual update until referenced
	for _, k in pairs(units) do
		unitStatus[k] = MOD:ValidateUnit(k)
	end

	-- can't count on events for these units
	for _, k in pairs(eventUnits) do
		unitUpdate[k] = (unitStatus[k] == 1)
	end

	if (lastWeapons == 0) or ((now - lastWeapons) > 1.0) then -- things to do every second...
		lastWeapons = now
		GetWeaponBuffs() -- get current weapon buffs, if any (less useful since WoD since no longer track shaman weapon enchants or rogue poisons)
	end
end

-- Cooldown tables have this structure (name of the cooldown is the index into the activeCooldowns table):
-- b[1] = timeLeft, b[2] = icon, b[3] = startTime, b[4] = duration, b[5] = tooltipType, b[6] = tooltipArgument, b[7] = unit, b[8] = id, b[9] = count

-- Check if valid cooldown table, if so then calculate time left from start time and duration and invalidate if cooldown has expired
-- Returns either the updated cooldown table or nil if not valid
local function ValidateCooldown(b)
	if b and b[1] ~= nil then
		b[1] = b[3] + b[4] - now -- calculate timeLeft from start time and duration
		if b[1] > 0 then return b end -- check if the cooldown has expired
		b[1] = nil -- this cooldown is no longer valid (what about if this cooldown has charges?)
		updateCooldowns = true; doUpdate = true
	end
	return nil
end

-- Add a cooldown to the current list of active cooldowns, cached info includes icon, start time, duration, tt_type, tt_arg, unit
local function AddCooldown(name, id, icon, start, duration, tt_type, tt_arg, unit, count, tt_color, tt_label)
	if lockedOut then -- check if this spell is on same cooldown as any lockout spell
		for ls, ld in pairs(lockouts) do if ld == duration and lockstarts[ls] == start then return end end
	end
	local t = activeCooldowns -- shared for player and pet cooldowns
	if not t[name] then
		MOD:SetIcon(name, icon) --  cache icon for this spell or item name
		t[name] = { 0, icon, start, duration, tt_type, tt_arg, unit, id, count }
	else
		local b = t[name]
		b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11] = 0, icon, start, duration, tt_type, tt_arg, unit, id, count, tt_color, tt_label
	end
end

-- Check if the named spell or item is on cooldown, return a cooldown table
function MOD:CheckCooldown(name)
	if name and name ~= "" then -- make sure valid name provided, could be spell name, number, or #number
		local id = nil
		if string.find(name, "^#%d+") then id = tonumber(string.sub(name, 2)) else id = tonumber(name) end
		if id then name = GetSpellInfo(id) end -- may need to convert from spell id to name
		if name and name ~= "" then return ValidateCooldown(activeCooldowns[name]) end -- make sure cooldown is still valid
	end
	return nil
end

-- Check if name is a spell in the spell book and, therefore, known to the player
-- If usable is true then verify it is not passive and has sufficient resources (e.g., mana, insanity, soul shards)
-- If ready is true then make sure it is not on cooldown or out of charges
function MOD:CheckSpellStatus(name, usable, ready)
	local result = false
	if name and name ~= "" then -- make sure valid name provided, could be spell name, number, or #number
		local id = nil
		if string.find(name, "^#%d+") then id = tonumber(string.sub(name, 2)) else id = tonumber(name) end
		if id then name = GetSpellInfo(id) end -- may need to convert from spell id to name
		if name and name ~= "" then
			local spellID = MOD.bookSpells[name]
			if spellID then -- spell is known by the player
				if usable then
					result = not IsPassiveSpell(spellID) and IsUsableSpell(name) -- check non-passive and has resources
				else
					result = true
				end
			end
		end
	end
	if result and ready then
		local cd = ValidateCooldown(activeCooldowns[name]) -- look up in the active cooldowns table
		result = not cd or (cd[1] == nil) or (cd[4] == nil) or (cd[9] and cd[9] > 0) -- check if ready
	end
	return result
end

-- Iterate over current cooldowns, calling the function with cooldown name, cooldown table, and optional parameters
function MOD:IterateCooldowns(func, p1, p2, p3)
	for n, cd in pairs(activeCooldowns) do
		if ValidateCooldown(cd) then
			func(n, cd, p1, p2, p3)
		end
	end
end

-- Release all spell cooldowns from active cooldowns table by setting first field to nil to indicate not active
local function ReleaseCooldowns() for _, cd in pairs(activeCooldowns) do cd[1] = nil end end

-- Update the expiration time for cooldowns, releasing any that have lapsed
function MOD:UpdateCooldownTimes() for _, b in pairs(activeCooldowns) do ValidateCooldown(b) end end

-- Get cooldown info for an inventory slot
local function CheckInventoryCooldown(itemID, slot)
	local start, duration, enable = GetInventoryItemCooldown("player", slot)
	if start and (start > 0) and (enable == 1) and (duration > 1.5) then
		local spell = GetItemSpell(itemID)
		local name, _, _, _, _, _, _, _, equipSlot, icon = GetItemInfo(itemID)
		if spell and equipSlot ~= "INVTYPE_TRINKET" then name = spell end
		if name and icon then AddCooldown(name, slot, icon, start, duration, "inventory", slot, "player") end
	end
end

-- Update info about the rune slots and add rune cooldowns
local function CheckRunes()
	local count = 0
	for i = 1, 6 do
		local rune = MOD.runeSlots[i]
		local start, duration, ready = GetRuneCooldown(i)
		if not rune then
			rune = { start = start, duration = duration, ready = ready }
			MOD.runeSlots[i] = rune
		else
			rune.start = start; rune.duration = duration; rune.ready = ready
		end
		if ready then count = count + 1 end
	end
	MOD.runeCount = count
end

-- Check if the spell is on cooldown because a rune is not available, return true only if on real cooldown
local function CheckRuneCooldown(name, duration)
	local runes = MOD.runeSpells[name]
	if runes and runes.count then
		if MOD.runeCount >= runes.count then return true end -- runes are available so real cooldown
		if duration <= 10 then return false end -- no spells that use runes have duration less than 10 seconds
	end
	return true
end

-- Check if an item is on cooldown
local function CheckItemCooldown(itemID)
	local start = 0
	local duration = 0
	local ignore = 0
	if MOD.isModernAPI then
		start, duration, ignore = C_Container.GetItemCooldown(itemID)
	else
		start, duration = GetItemCooldown(itemID)
	end
	if start == nil or duration == nil then
		return
	end
	if (start > 0) and (duration > 1.5) then -- don't include global cooldowns or really short cooldowns
		local name, link, _, _, _, itemType, itemSubType, _, _, icon = GetItemInfo(itemID)
		if name then
			local found = false
			if itemType == "Consumable" and (itemID ~= 86569) then -- check for shared cooldowns for potions/elixirs/flasks (special case Crystal of Insanity)
				if itemSubType == "Potion" then
					found = true
					if not ValidateCooldown(L["Potions"]) then
						AddCooldown(L["Potions"], nil, iconPotion, start, duration, "text", L["Shared Potion Cooldown"], "player")
					end
				elseif (itemSubType == "Elixir") or (itemSubType == "Flask") then
					found = true
					if not ValidateCooldown(L["Elixirs"]) then
						AddCooldown(L["Elixirs"], nil, iconElixir, start, duration, "text", L["Shared Elixir Cooldown"], "player")
					end
				end
			end
			if not found then
				AddCooldown(name, itemID, icon, start, duration, "item id", itemID, "player")
			end
		end
	end
end

-- Check if the aura either triggers or cancels an internal cooldown
-- Internal cooldown table indexed by aura that triggers the cooldown
function MOD:DetectInternalCooldown(name, caster)
	local up = false
	for id, cd in pairs(internalCooldowns) do -- check if cancels any active internal cooldowns
		if cd.cancel then
			for _, aura in pairs(cd.cancel) do if name == aura then internalCooldowns[id] = ReleaseTable(cd); up = true; break end end
		end
	end
	local ict = MOD.db.global.InternalCooldowns[name] -- check for new internal cooldown triggered by this aura
	if ict and not ict.disable and ((ict.caster == true) == caster) and (not ict.class or ict.class == MOD.myClass) and not internalCooldowns[name] then
		local cd = AllocateTable() -- get an empty tracker table
		cd.start = now; cd.expire = cd.start + ict.duration; cd.cancel = ict.cancel
		internalCooldowns[name] = cd
		up = true
	end
	if up then TriggerCooldownUpdate() end
end

-- Remove any internal cooldown entries that have expired
function MOD:UpdateInternalCooldowns()
	for name, cd in pairs(internalCooldowns) do if now >= cd.expire then internalCooldowns[name] = ReleaseTable(cd); TriggerCooldownUpdate() end end
end

-- Check for any internal cooldowns that are active
local function CheckInternalCooldowns()
	for name, cd in pairs(internalCooldowns) do
		local ict = MOD.db.global.InternalCooldowns[name]
		if ict and not ict.disable then AddCooldown(name, ict.id, ict.icon, cd.start, ict.duration, "internal", ict.id, "player") end
	end
end

-- Check for any internal cooldowns that are active
local function CheckSpellEffectCooldowns()
	for name, ec in pairs(spellEffects) do
		local ect = MOD.db.global.SpellEffects[name]
		if ect and not ect.disable and ect.kind == "cooldown" then
			local spell = ect.spell or name
			AddCooldown(spell, ect.id, ect.icon, ec.start, ec.expire - ec.start, "effect", name, "player")
		end
	end
end

-- Check for any active spell alert cooldowns
local function CheckSpellAlertCooldowns()
	for id, alert in pairs(spellAlerts) do
		local kind = MOD.db.global[alert.alertType].kind
		if kind == "cooldown" then
			-- MOD.Debug("alertcd", id, alert.spellName, alert.spellID, alert.expire - alert.duration, alert.duration)
			local color, label = GetSpellAlertInfo(alert)
			AddCooldown(alert.spellName, alert.spellID, alert.icon, alert.expire - alert.duration, alert.duration, "alert", alert.spellID, "player", nil, color, label)
		end
	end
end

-- Check for new and expiring cooldowns associated with all action bar slots plus trinkets (might want to add inventory slots someday)
function MOD:UpdateCooldowns()
	if updateCooldowns then
		ReleaseCooldowns() -- mark all cooldowns as not active

		if MOD.myClass == "DEATHKNIGHT" then CheckRunes() end
		lockedOut = false -- flag set if any lockout spells are found
		for school in pairs(lockouts) do lockouts[school] = 0 end -- clear any previous settings in lockout table
		if UnitLevel("player") >= 10 then -- don't detect lockouts for low-level characters, this allows more options for lockout detection spells
			for name, ls in pairs(MOD.lockoutSpells) do
				if not lockouts[ls.school] then lockouts[ls.school] = 0 end -- initialize when school seen for first time
				if ls.index and (lockouts[ls.school] == 0) then
					local start, duration = GetSpellCooldown(ls.index, "spell")
					if start and (start > 0) and (duration > 1.5) then -- locked out!
						lockouts[ls.school] = duration; lockstarts[ls.school] = start; lockedOut = true
						AddCooldown(ls.label, nil, iconGCD, start, duration, "spell", ls.text, "player")
					end
				end
			end
		end

		for spellID in pairs(MOD.cooldownSpells) do -- check all player spells with cooldowns (includes professions)
			local name, _, icon = GetSpellInfo(spellID)
			if name and name ~= "" and icon then -- make sure we have a valid spell name
				local start, duration, enable = GetSpellCooldown(spellID)
				if start and (start > 0) and (enable == 1) and (duration > 1.5) then -- don't include global cooldowns
					if (MOD.myClass ~= "DEATHKNIGHT") or CheckRuneCooldown(name, duration) then -- if death knight check rune cooldown
						AddCooldown(name, spellID, icon, start, duration, "spell id", spellID, "player")
					end
				end
			end
		end

		for spellID in pairs(MOD.chargeSpells) do -- check all player spells with charges
			local name, _, icon = GetSpellInfo(spellID)
			if name and name ~= "" and icon then -- make sure we have a valid spell name
				local count, charges, start, duration = GetSpellCharges(spellID)
				if count and charges and count < charges then
					if start and (start > 0) and (duration > 1.5) then -- don't include global cooldowns
						if (MOD.myClass ~= "DEATHKNIGHT") or CheckRuneCooldown(name, duration) then -- if death knight check rune cooldown
							AddCooldown(name, spellID, icon, start, duration, "spell id", spellID, "player", count)
						end
					end
				end
			end
		end

		if UnitExists("pet") then -- make sure you have a pet before check all pet spells with cooldowns
			for spellID in pairs(MOD.petSpells) do
				local name, _, icon = GetSpellInfo(spellID)
				if name and name ~= "" and icon then -- make sure we have a valid spell name
					local start, duration, enable = GetSpellCooldown(spellID)
					if start and (start > 0) and (enable == 1) and (duration > 1.5) then -- don't include global cooldowns
						AddCooldown(name, spellID, icon, start, duration, "spell id", spellID, "pet")
					end
				end
			end
		end

		local offset = nil -- check for override/vehicle bar actions on cooldown
		if MOD.ExpansionIsOrAbove(LE_EXPANSION_CATACLYSM) then
			if HasVehicleActionBar() then offset = 132 elseif HasOverrideActionBar() then offset = 156 end
		end
		if offset then
			for slot = 1, 6 do
				local actionType, spellID = GetActionInfo(slot + offset)
				if actionType == "spell" then
					local start, duration, enable = GetSpellCooldown(spellID)
					if start and (start > 0) and (enable == 1) and (duration > 1.5) then -- don't include global cooldowns
						local name, _, icon = GetSpellInfo(spellID)
						if name and name ~= "" and icon then
							AddCooldown(name, spellID, icon, start, duration, "spell id", spellID, "player")
						end
					end
				end
			end
		end

		if not MOD.isWrathPTR then
			for itemID in pairs(bagCooldowns) do CheckItemCooldown(itemID) end
		end
		for itemID, slot in pairs(inventoryCooldowns) do CheckInventoryCooldown(itemID, slot) end

		if startGCD and durationGCD then -- detect global cooldowns
			local timeLeft = startGCD + durationGCD - now -- calculate timeLeft from start and duration
			if timeLeft > 0 then
				AddCooldown(L["GCD"], nil, iconGCD, startGCD, durationGCD, "text", L["Global Cooldown"], "player")
			else
				startGCD = nil; durationGCD = nil -- this cooldown is no longer valid
			end
		end

		CheckInternalCooldowns()
		CheckSpellEffectCooldowns()
		CheckSpellAlertCooldowns()
		updateCooldowns = false
	end
end

function MOD:ReadRGBA(red, green, blue, alpha, default)
	local output = {
		1,
		1,
		1,
		1,
	}

	if default ~= nil then
		default = MOD:ReadRGBA(unpack(default))
	else
		default = output
	end

	if red == nil or green == nil or blue == nil or alpha == nil then
		return default
	end

	return {
		red,
		green,
		blue,
		alpha,
	}
end

function MOD:ReadRGB(r, g, b, default)
	local output = {
		1,
		1,
		1,
	}

	if default ~= nil then
		default = MOD:ReadRGB(unpack(default))
	else
		default = output
	end

	if red == nil or green == nil or blue == nil then
		return default
	end

	return {
		red,
		green,
		blue,
	}
end

function MOD:SetTextColor(element, r, g, b, a)
	local color = MOD:ReadRGBA(r, g, b, a)

	element:SetTextColor(unpack(color))
end
