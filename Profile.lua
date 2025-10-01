-- Raven is an addon to monitor auras and cooldowns, providing timer bars and icons plus helpful notifications.

-- Profile.lua contains the default profile for initializing the player's selected profile.
-- It includes routines to process preset aura and cooldown info for all classes and races.
-- Profile settings are accessed by reference to MOD.db.global or MOD.db.profile.
-- It also maintains a persistent database that caches icons, colors and labels for auras and spells.

-- Exported functions for looking up aura and spell-related info:
-- Raven:SetIcon(name, icon) save icon in cache
-- Raven:GetIcon(name) returns cached icon for spell with the specified name, nil if not found
-- Raven:SetColor(name, color) save color in cache
-- Raven:GetColor(name) returns cached color for spell with the specified name, nil if not found
-- Raven:SetLabel(name, label) save label in cache
-- Raven:GetLabel(name) returns cached label for spell with the specified name, nil if not found
-- Raven:SetSound(name, sound) save sound in cache
-- Raven:GetSound(name) returns cached sound for spell with the specified name, nil if not found
-- Raven:SetSpellExpireTime(name, sound) save expire time for a spell in cache
-- Raven:GetSpellExpireTime(name) returns expire time for spell with the specified name, nil if not found
-- Raven:FormatTime(time, index, spaces, upperCase) returns time in seconds converted into a text string
-- Raven:RegisterTimeFormat(func) adds a custom time format and returns its assigned index
-- Raven:ResetBarGroupFilter(barGroupName, "Buff"|"Debuff"|"Cooldown")
-- Raven:RegisterBarGroupFilter(barGroupName, "Buff"|"Debuff"|"Cooldown", spellNameOrID)

local MOD = Raven
local SHIM = MOD.SHIM
local L = LibStub("AceLocale-3.0"):GetLocale("Raven")
local LSPELL = MOD.LocalSpellNames

local dispelTypes = {} -- table of debuff types that the character can dispel
local spellColors = {} -- table of default spell colors
local spellIDs = {} -- table of cached spell name and id pairs (id = 0 indicates invalid spell name)
local maxSpellID = 400000 -- set to maximum actual spell id during initialization
local iconCache = {} -- table of icons intialized from spell table, with entries added when icon cache is accessed
local professions = {} -- temporary table for profession indices
local badSpellIDs = { [230747] = true, [238630] = true, [238631] = true, [238632] = true } -- "doug tests"

-- Saved variables don't handle being set to nil properly so need to use alternate value to indicate an option has been turned off
local Off = 0 -- value used to designate an option is turned off
local function IsOff(value) return value == nil or value == Off end -- return true if option is turned off
local function IsOn(value) return value ~= nil and value ~= Off end -- return true if option is turned on

-- Convert color codes from hex number to array with r, g, b, a fields (alpha set to 1.0)
function MOD.HexColor(hex)
	local n = tonumber(hex, 16)
	local red = math.floor(n / (256 * 256))
	local green = math.floor(n / 256) % 256
	local blue = n % 256

	return { r = red/255, g = green/255, b = blue/255, a = 1.0 }
	-- return CreateColor(red/255, green/255, blue/255, 1)
end

-- Return a copy of a color, if c is nil then return nil
function MOD.CopyColor(c)
	if not c then return nil end
	-- return CreateColor(c.r, c.g, c.b, c.a)
	return { r = c.r, g = c.g, b = c.b, a = c.a }
end

-- Copy a table, including its metatable
function MOD.CopyTable(object)
	local lookup_table = {}
	local function _copy(object)
		if type(object) ~= "table" then
			return object
		elseif lookup_table[object] then
			return lookup_table[object]
		end
		local new_table = {}
		lookup_table[object] = new_table
		for index, value in pairs(object) do
			new_table[_copy(index)] = _copy(value)
		end
		return setmetatable(new_table, getmetatable(object))
	end
	return _copy(object)
end

-- Global color palette containing the standard colors for this addon
MOD.ColorPalette = {
	Yellow1=MOD.HexColor("fce94f"), Yellow2=MOD.HexColor("edd400"), Yellow3=MOD.HexColor("c4a000"),
	Orange1=MOD.HexColor("fcaf3e"), Orange2=MOD.HexColor("f57900"), Orange3=MOD.HexColor("ce5c00"),
	Brown1=MOD.HexColor("e9b96e"), Brown2=MOD.HexColor("c17d11"), Brown3=MOD.HexColor("8f5902"),
	Green1=MOD.HexColor("8ae234"), Green2=MOD.HexColor("73d216"), Green3=MOD.HexColor("4e9a06"),
	Blue1=MOD.HexColor("729fcf"), Blue2=MOD.HexColor("3465a4"), Blue3=MOD.HexColor("204a87"),
	Purple1=MOD.HexColor("ad7fa8"), Purple2=MOD.HexColor("75507b"), Purple3=MOD.HexColor("5c3566"),
	Red1=MOD.HexColor("ef2929"), Red2=MOD.HexColor("cc0000"), Red3=MOD.HexColor("a40000"),
	Pink=MOD.HexColor("ff6eb4"), Cyan=MOD.HexColor("7adbf2"), Gray=MOD.HexColor("888a85"),
	None=MOD.HexColor("ffffff")
}

-- Global palette of class colors
MOD.ClassColors = {
	DEATHKNIGHT = MOD.HexColor("C41F3B"),
	DRUID = MOD.HexColor("FF7D0A"),
	EVOKER = MOD.HexColor("33937F"),
	HUNTER = MOD.HexColor("ABD473"),
	MAGE = MOD.HexColor("40C7EB"),
	PALADIN = MOD.HexColor("F58CBA"),
	PRIEST = MOD.HexColor("FFFFFF"),
	ROGUE = MOD.HexColor("FFF569"),
	SHAMAN = MOD.HexColor("0070DE"),
	WARLOCK = MOD.HexColor("8787ED"),
	WARRIOR = MOD.HexColor("C79C6E"),
	MONK = MOD.HexColor("00FF96"),
	DEMONHUNTER = MOD.HexColor("A330C9"),
}

-- Remove unneeded variables from the profile before logout
local function OnProfileShutDown()
	MOD:FinalizeSpellIDs() -- save cached spell ids
	MOD:FinalizeBars() -- strip out all default values to significantly reduce profile file size
	MOD:FinalizeConditions() -- strip out temporary values from conditions
	MOD:FinalizeSettings() -- strip default values from layouts
	MOD:FinalizeInCombatBar() -- save linked settings
end

-- Initialize profile used to customize the addon
function MOD:InitializeProfile()
	MOD:SetSpellDefaults()
	MOD:SetCooldownDefaults()
	MOD:SetInternalCooldownDefaults()
	MOD:SetSpellEffectDefaults()
	MOD:SetSpellAlertDefaults()
	MOD:SetConditionDefaults()
	MOD:SetSpellNameDefaults()
	MOD:SetDimensionDefaults(MOD.DefaultProfile.global.Defaults)
	MOD:SetFontTextureDefaults(MOD.DefaultProfile.global.Defaults)
	MOD:SetTimeFormatDefaults(MOD.DefaultProfile.global.Defaults)
	MOD:SetInCombatBarDefaults()

	-- Get profile from database, providing default profile for initialization
	MOD.db = LibStub("AceDB-3.0"):New("RavenDB", MOD.DefaultProfile)
	MOD.db.RegisterCallback(MOD, "OnDatabaseShutdown", OnProfileShutDown)
	MOD:MigrateDB()

	MOD:InitializeSpellIDs() -- restore cached spell ids
	MOD:InitializeSettings() -- initialize bar group settings with default values
end

function MOD:MigrateDB()
	if (MOD.db.profile.version == 0) then
		MOD.db.profile.hideBlizzDebuffs = MOD.db.profile.hideBlizzBuffs
		MOD.db.profile.version = 1
	end
end

-- Initialize spell id info and restore saved cache from the profile
function MOD:InitializeSpellIDs()
	local sids = MOD.db.global.SpellIDs
	if sids then
		for n, k in pairs(sids) do spellIDs[n] = k end -- restore spell id cache from profile
	end
end

-- Finalize spell id info by saving the cache into the profile
function MOD:FinalizeSpellIDs()
	local sids = MOD.db.global.SpellIDs
	if not sids then sids = {}; MOD.db.global.SpellIDs = sids end
	for n, k in pairs(spellIDs) do if k == 0 then sids[n] = nil else sids[n] = k end end -- save updated spell id cache to profile
end

-- Initialize spells for class auras and cooldowns, also scan other classes for group buffs and cooldowns
-- Buffs, debuffs and cooldowns are tracked in tables containing name, color, class, race
function MOD:SetSpellDefaults()
	local id = maxSpellID
	while id > 1 do -- find the highest actual spell id by scanning down from a really big number
		id = id - 1
		local n = SHIM:GetSpellInfo(id)
		if n then break end
	end
	maxSpellID = id + 1

	for id, hex in pairs(MOD.defaultColors) do -- add spell colors with localized names to the profile
		local c = MOD.HexColor(hex) -- convert from hex coded string
		local name = SHIM:GetSpellInfo(id) -- get localized name from the spell id
		if name and c then MOD.DefaultProfile.global.SpellColors[name] = c end-- sets default color in the shared color table
	end

	for name, hex in pairs(MOD.generalSpells) do -- add some general purpose localized colors
		local c = MOD.HexColor(hex) -- convert from hex coded string
		local ln = L[name] -- get localized name
		if ln and c then MOD.DefaultProfile.global.SpellColors[ln] = c end -- add to the shared color table
	end

	MOD.defaultColors = nil -- not used again after initialization so okay to delete
	MOD.generalSpells = nil

	spellColors = MOD.CopyTable(MOD.DefaultProfile.global.SpellColors) -- save for restoring defaults later

	if MOD.myClass == "DEATHKNIGHT" then -- localize rune spell names
		local t = {}
		for k, p in pairs(MOD.runeSpells) do if p.id then local name = SHIM:GetSpellInfo(p.id); if name and name ~= "" then t[name] = p end end end
		MOD.runeSpells = t
	end

	MOD.mountSpells = {}
	if MOD.ExpansionIsOrAbove(LE_EXPANSION_WARLORDS_OF_DRAENOR) then
		local mountIDs = C_MountJournal.GetMountIDs()
		for i, id in ipairs(mountIDs) do
			local creatureName, spellID = C_MountJournal.GetMountInfoByID(id)
			MOD.mountSpells[spellID] = true -- used to check if a buff is for a mount (this includes all mounts in journal, not the player's own mounts)
		end
	end
end

-- Initialize cooldown info from spellbook, should be called whenever spell book changes
-- This builds a cache of spells with cooldowns and initializes info related to spell school lockouts
function MOD:SetCooldownDefaults()
	local cds = MOD.cooldownSpells -- table of spells to be checked for cooldowns, entries are spellID->baseCooldown
	local chs = MOD.chargeSpells -- table of spells with charges, entries are spellID->maxCharges
	local cpet = MOD.petSpells -- table of pets spells to be checked for cooldowns, entries are spellID->baseCooldown
	local book = "spell" -- scanning player's spell book
	local cls = MOD.lockoutSpells -- table of spells used to detect spell school lockouts
	local bst = MOD.bookSpells -- table of spells in spell book (player and profession), entries are name->spellID

	table.wipe(cpet) -- pet cooldown spells should be reset each time the tables are rebuilt
	table.wipe(cls) -- lockout spells should be completely reset each time the tables are rebuilt
	table.wipe(bst) -- table of all spell names and ids in spell book (player and profession only)
	table.wipe(MOD.spellOverrides) -- table of all overridden spells

	-- Only remove special spells which show up dynamically in player's cooldown spells
	if MOD.myClass == "HUNTER" then
		cds[272678] = nil; cds[272679] = nil; cds[272682] = nil -- Command Pet spells
	elseif MOD.myClass == "WARLOCK" then
		cds[119914] = nil; cds[119909] = nil; cds[119910] = nil; cds[119907] = nil; cds[119905] = nil -- Command Demon spells
	end

	for _, p in pairs(MOD.lockSpells) do -- add in all known spells from the table of spells used to test for lockouts
		local name = SHIM:GetSpellInfo(p.id)
		if name and name ~= "" then cls[name] = { school = p.school, id = p.id } end
	end

	local openTabs = 3 -- on live first two tabs are open to all specializations and the third is current spec
	openTabs = SHIM:GetNumSpellTabs()

	for tab = 1, openTabs do -- scan first two tabs of player spell book (general and current spec) for player spells on cooldown
        local spellLine, spellIcon, offset, numSpells = SHIM:GetSpellTabInfo(tab)
        for i = 1, numSpells do
            local index = i + offset
            local spellName = SHIM:GetSpellBookItemName(index, book)
            if not spellName then
                break
            end

            local stype, id, isPassive, overrideID = SHIM:GetSpellBookItemInfo(index, book)
            if id then -- Only index valid spells
                if stype == "SPELL" then -- in this case, id is not always the spell id despite what online docs say
                    local name, _, icon, _, _, _, spellID = SHIM:GetSpellInfo(id)
                    if overrideID ~= nil then
                    	  local overridingName,overridingIcon
                        overridingName, _, overridingIcon, _, _, _, overrideID = SHIM:GetSpellInfo(overrideID)
                        MOD.spellOverrides[name] = overridingName
                        bst[overridingName] = overrideID
                    end

                    if name and name ~= "" and icon and spellID and not isPassive then -- don't index passive spells as they have no cooldown
                        bst[name] = overrideID or spellID
                        iconCache[name] = icon
                        local _, charges = SHIM:GetSpellCharges(index, book)

                        if charges and charges > 0 then
                            chs[overrideID or spellID] = charges
                        else
                            local duration = GetSpellBaseCooldown(overrideID or spellID) -- duration is in milliseconds
                            if duration and duration > 1500 then
                                cds[overrideID or spellID] = duration / 1000
                            end -- don't include spells with global cooldowns
                        end
                        local ls = cls[name] -- doesn't account for "FLYOUT" spellbook entries, but not an issue currently
                        if ls then -- found a lockout spell so add fields for the spell book index plus localized text
                            ls.index = index
                            if ls.school == "Frost" then ls.label = L["Frost School"]; ls.text = L["Locked out of Frost school of magic."]
                            elseif ls.school == "Fire" then ls.label = L["Fire School"]; ls.text = L["Locked out of Fire school of magic."]
                            elseif ls.school == "Nature" then ls.label = L["Nature School"]; ls.text = L["Locked out of Nature school of magic."]
                            elseif ls.school == "Shadow" then ls.label = L["Shadow School"]; ls.text = L["Locked out of Shadow school of magic."]
                            elseif ls.school == "Arcane" then ls.label = L["Arcane School"]; ls.text = L["Locked out of Arcane school of magic."]
                            elseif ls.school == "Holy" then ls.label = L["Holy School"]; ls.text = L["Locked out of Holy school of magic."]
                            elseif ls.school == "Physical" then ls.label = L["Physical School"]; ls.text = L["Locked out of Physical school of magic."]
                            end
                        end
                    end
                elseif stype == "FLYOUT" then -- in this case, id is flyout id
                    local _, _, numSlots, known = GetFlyoutInfo(id)
                    if known then
                        for slot = 1, numSlots do
                            local spellID, _, _, name = GetFlyoutSlotInfo(id, slot)
                            if spellID then
                                local name, _, icon = SHIM:GetSpellInfo(spellID)
                                if name and name ~= "" and icon then -- make sure we have a valid spell
                                    bst[name] = spellID
                                    iconCache[name] = icon
                                    local duration = GetSpellBaseCooldown(spellID) -- duration is in milliseconds
                                    if duration and duration > 1500 then -- don't include spells with global cooldowns
                                        cds[spellID] = duration / 1000
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

	local tabs = SHIM:GetNumSpellTabs()
	if tabs and tabs > 3 then
		for tab = 4, tabs do -- scan inactive tabs of player spell book for icons
			local spellLine, spellIcon, offset, numSpells = SHIM:GetSpellTabInfo(tab)
			for i = 1, numSpells do
				local index = i + offset
				local spellName = SHIM:GetSpellBookItemName(index, book)
				if not spellName then break end
				local stype, id = SHIM:GetSpellBookItemInfo(index, book)
				if id then -- make sure valid spell book item
					if stype == "SPELL" then -- in this case, id is not the spell id despite what online docs say
						local name, _, icon = SHIM:GetSpellInfo(id)
						if name and name ~= "" and icon then iconCache[name] = icon end
					elseif stype == "FLYOUT" then -- in this case, id is flyout id
						local _, _, numSlots, known = GetFlyoutInfo(id)
						if known then
							for slot = 1, numSlots do
								local spellID, _, _, name = GetFlyoutSlotInfo(id, slot)
								if spellID then
									local name, _, icon = SHIM:GetSpellInfo(spellID)
									if name and name ~= "" and icon then iconCache[name] = icon end
								end
							end
						end
					end
				end
			end
		end
	end

	if MOD.ExpansionIsOrAbove(LE_EXPANSION_CATACLYSM) then
		local p = professions -- scan professions for spells on cooldown
		p[1], p[2], p[3], p[4], p[5], p[6] = GetProfessions()
		for index = 1, 6 do
			if p[index] then
				local prof, _, _, _, numSpells, offset = GetProfessionInfo(p[index])
				for i = 1, numSpells do
					local stype = SHIM:GetSpellBookItemInfo(i + offset, book)
					if stype == "SPELL" then
						local name, _, icon, _, _, _, spellID = SHIM:GetSpellInfo(i + offset, book)
						if name and name ~= "" and icon and spellID then -- make sure valid spell
							bst[name] = spellID
							iconCache[name] = icon
							local duration = GetSpellBaseCooldown(spellID) -- duration is in milliseconds
							if duration and duration > 1500 then cds[spellID] = duration / 1000 end -- don't include spells with global cooldowns
						end
					end
				end
			end
		end
	end

	local petSpells = SHIM:HasPetSpells() -- get number of pet spells
	if petSpells and UnitExists("pet") then -- this works because SPELLS_CHANGED fires when pets are called and dismissed
		book = "pet" -- switch to scanning the spellbook for pet spells with cooldowns, no need to look for charges
		for i = 1, petSpells do
			local stype, id = SHIM:GetSpellBookItemInfo(i, book) -- verify this is a pet action
			if stype == "PETACTION" then
				local name, _, icon, _, _, _, spellID = SHIM:GetSpellInfo(id)
				if name and name ~= "" and icon and spellID then
					iconCache[name] = icon
					local duration = GetSpellBaseCooldown(spellID) -- duration is in milliseconds
					if duration and duration > 1500 then cpet[spellID] = duration / 1000 end -- don't include spells with global cooldowns
				end
			end
		end
	end

	-- Add special spells which either share spellbook entries or show up dynamically
	if MOD.myClass == "HUNTER" then
		-- Mend Pet
		MOD:RegisterCooldownDefault(136, 10)
	end
	if MOD.myClass == "PRIEST" then
		-- Power Word: Shield
		MOD:RegisterCooldownDefault(17, 10)
	end
	if MOD.myClass == "PALADIN" then
		-- Flash of Light can gain a cooldown through the Light's Celerity talent:
		-- https://www.wowhead.com/spell=403698/lights-celerity
		MOD:RegisterCooldownDefault(19750, 6)
	end

	iconCache[L["GCD"]] = SHIM:GetSpellTexture(61304) -- cache special spell with GCD cooldown, must be valid

	-- local function getn(t) local count = 0; if t then for _ in pairs(t) do count = count + 1 end end return count end
	-- local function getl(t) local count = 0; if t then for k, v in pairs(t) do if v.index then count = count + 1 end end end return count end
	-- MOD.Debug("spell and icon caches, cooldowns: ", getn(cds), " charges: ", getn(chs), " pet: ", getn(cpet), " locks: ", getl(cls), " icons: ", getn(iconCache))
	-- for k, v in pairs(cds) do local name = SHIM:GetSpellInfo(k); MOD.Debug("cooldown", name, k, v) end
	-- for k, v in pairs(chs) do local name = SHIM:GetSpellInfo(k); MOD.Debug("charge", name, k, v) end
	-- for k, v in pairs(cpet) do local name = SHIM:GetSpellInfo(k); MOD.Debug("pet", name, k, v) end
	-- for k, v in pairs(cls) do if v.index then MOD.Debug("lock", k, v.index, v.label) end end
	-- for k, v in pairs(iconCache) do MOD.Debug("icons", k, v) end
end

function MOD:RegisterCooldownDefaultBySpellID(spellID)
	local cooldown = GetSpellBaseCooldown(spellID)

	if not cooldown then
		return
	end

	MOD:RegisterCooldownDefault(spellID, cooldown / 1000)
end

function MOD:RegisterCooldownDefault(spellID, cooldown)
	local name = SHIM:GetSpellInfo(spellID)

	if not name then
		return
	end

	MOD.cooldownSpells[spellID] = cooldown
	MOD.bookSpells[name] = spellID
end

-- Initialize internal cooldown info from presets, table fields include id, duration, cancel, item
-- This function translates ids into spell names and looks up the icon
function MOD:SetInternalCooldownDefaults()
	local ict = MOD.DefaultProfile.global.InternalCooldowns
	for _, cd in pairs(MOD.internalCooldowns) do
		local name, _, icon = SHIM:GetSpellInfo(cd.id)
		if name and (name ~= "") and icon and (not ict[name] or not cd.item or SHIM:IsUsableItem(cd.item)) then
			local t = { id = cd.id, duration = cd.duration, icon = icon, item = cd.item, class = cd.class }
			if cd.cancel then
				t.cancel = {}
				for k, c in pairs(cd.cancel) do local n = SHIM:GetSpellInfo(c); if n and n ~= "" then t.cancel[k] = n end end
			end
			ict[name] = t
		end
	end
	MOD.internalCooldowns = nil -- release the preset table memory
end

-- Initialize spell effect info from presets, table fields include id, duration, associated spell, talent
-- This function translates ids into spell names and looks up the icon
function MOD:SetSpellEffectDefaults()
	local ect = MOD.DefaultProfile.global.SpellEffects
	for _, ec in pairs(MOD.spellEffects) do
		local name, _, icon = SHIM:GetSpellInfo(ec.id)
		if name and name ~= "" then
			local id, spell, talent = ec.id, nil, nil
			if ec.spell then spell = SHIM:GetSpellInfo(ec.spell); id = ec.spell end -- must be valid
			if ec.talent then talent = SHIM:GetSpellInfo(ec.talent) end -- must be valid
			local t = { duration = ec.duration, icon = icon, spell = spell, id = id, renew = ec.renew, talent = talent, kind = ec.kind }
			ect[name] = t
		end
	end
	MOD.spellEffects = nil -- release the preset table memory
end

-- Initialize defaults for spell alerts
function MOD:SetSpellAlertDefaults()
	local t = MOD.DefaultProfile.global.SpellAlerts
	t.labelSpells = true
	t.labelCaster = true
	t.labelTarget = true
	t.casterMatch = true
	t.showRealm = true
	t.ignoreTargets = false
	t.hideCasting = false
	t.duration = 3
end

-- Check if a spell color has changed from its default
function MOD:CheckColorDefault(name)
	if name then
		local t = spellColors[name]
		local s = MOD.db.global.SpellColors[name]
		if s and t then if t.r == s.r and t.g == s.g and t.b == s.b and t.a == s.a then return true end end
	end
	return false
end

-- Reset a particular spell color to its default value
function MOD:ResetColorDefault(name)
	if name then
		local dct = spellColors
		local sct = MOD.db.global.SpellColors
		local c = dct[name]
		if not c then
			sct[name] = nil -- if not default value then just clear the spell color
		else
			local t = sct[name]
			if t then
				t.r, t.g, t.b, t.a = c.r, c.g, c.b, c.a
			else
				sct[name] = MOD.CopyColor(c)
			end
		end
	end
end

-- Reset all colors to default values
function MOD:ResetColorDefaults()
	local dct = spellColors
	local sct = MOD.db.global.SpellColors
	for n, c in pairs(dct) do -- copy all original values from the default color table
		local t = sct[n]
		if t then
			t.r, t.g, t.b, t.a = c.r, c.g, c.b, c.a
		else
			sct[n] = MOD.CopyColor(c)
		end
	end
	for n in pairs(sct) do if not dct[n] then sct[n] = nil end end -- remove any extras
end

-- Initialize dimension defaults
function MOD:SetDimensionDefaults(p)
	p.barWidth = 150; p.barHeight = 15; p.iconSize = 15; p.scale = 1; p.spacingX = 0; p.spacingY = 0; p.iconOffsetX = 0; p.iconOffsetY = 0
	p.hideIcon = false; p.hideClock = false; p.hideBar = false; p.hideSpark = false
	p.hideLabel = false; p.hideCount = true; p.hideValue = false; p.showTooltips = true
	p.i_barWidth = 20; p.i_barHeight = 5; p.i_iconSize = 25; p.i_scale = 1; p.i_spacingX = 2; p.i_spacingY = 15; p.i_iconOffsetX = 0; p.i_iconOffsetY = 0
	p.i_hideIcon = false; p.i_hideClock = false; p.i_hideBar = true; p.i_hideSpark = false
	p.i_hideLabel = true; p.i_hideCount = true; p.i_hideValue = false; p.i_showTooltips = true
end

-- Initialize time format defaults
function MOD:SetTimeFormatDefaults(p)
	p.timeFormat = 6; p.timeSpaces = false; p.timeCase = false
end

-- Copy dimensions, destination is always a bar group, check which configuration type and copy either bar or icon defaults
function MOD:CopyDimensions(s, d)
	local iconOnly = d.configuration and MOD.Nest_SupportedConfigurations[d.configuration].iconOnly or false
	if iconOnly then
		d.barWidth = s.i_barWidth; d.barHeight = s.i_barHeight; d.iconSize = s.i_iconSize; d.scale = s.i_scale
		d.spacingX = s.i_spacingX; d.spacingY = s.i_spacingY; d.iconOffsetX = s.i_iconOffsetX; d.iconOffsetY = s.i_iconOffsetY
		d.hideIcon = s.i_hideIcon; d.hideClock = s.i_hideClock; d.hideBar = s.i_hideBar; d.hideSpark = s.i_hideSpark
		d.hideLabel = s.i_hideLabel; d.hideCount = s.i_hideCount; d.hideValue = s.i_hideValue; d.showTooltips = s.i_showTooltips
	else
		d.barWidth = s.barWidth; d.barHeight = s.barHeight; d.iconSize = s.iconSize; d.scale = s.scale
		d.spacingX = s.spacingX; d.spacingY = s.spacingY; d.iconOffsetX = s.iconOffsetX; d.iconOffsetY = s.iconOffsetY
		d.hideIcon = s.hideIcon; d.hideClock = s.hideClock; d.hideBar = s.hideBar; d.hideSpark = s.hideSpark
		d.hideLabel = s.hideLabel; d.hideCount = s.hideCount; d.hideValue = s.hideValue; d.showTooltips = s.showTooltips
	end
end

-- Initialize default fonts and textures
function MOD:SetFontTextureDefaults(p)
	p.labelFont = "Arial Narrow"; p.labelFSize = 10; p.labelAlpha = 1; p.labelColor = { r = 1, g = 1, b = 1, a = 1 }
	p.labelOutline = false; p.labelShadow = true; p.labelThick = false; p.labelMono = false; p.labelSpecial = false
	p.timeFont = "Arial Narrow"; p.timeFSize = 10; p.timeAlpha = 1; p.timeColor = { r = 1, g = 1, b = 1, a = 1 }
	p.timeOutline = false; p.timeShadow = true; p.timeThick = false; p.timeMono = false; p.timeSpecial = false
	p.iconFont = "Arial Narrow"; p.iconFSize = 10; p.iconAlpha = 1; p.iconColor = { r = 1, g = 1, b = 1, a = 1 }
	p.iconOutline = true; p.iconShadow = true; p.iconThick = false; p.iconMono = false; p.iconSpecial = false
	p.texture = "Blizzard"; p.bgtexture = "Blizzard"; p.alpha = 1; p.combatAlpha = 1; p.fgAlpha = 1; p.bgAlpha = 0.65
	p.backdropEnable = false; p.backdropTexture = "None"; p.backdropWidth = 16; p.backdropInset = 4; p.backdropPadding = 16; p.backdropPanel = "None"
	p.backdropColor = { r = 1, g = 1, b = 1, a = 1 }; p.backdropFill = { r = 1, g = 1, b = 1, a = 1 }
	p.backdropOffsetX = 0; p.backdropOffsetY = 0; p.backdropPadW = 0; p.backdropPadH = 0
	p.borderTexture = "None"; p.borderWidth = 8; p.borderOffset = 2; p.borderColor = { r = 1, g = 1, b = 1, a = 1 }
	p.fgSaturation = 0; p.fgBrightness = 0; p.bgSaturation = 0; p.bgBrightness = 0; p.borderSaturation = 0; p.borderBrightness = 0
end

-- Copy fonts and textures between tables
function MOD:CopyFontsAndTextures(s, d)
	if s and d and (s ~= d) then
		d.labelFont = s.labelFont; d.labelFSize = s.labelFSize; d.labelAlpha = s.labelAlpha; d.labelColor = MOD.CopyColor(s.labelColor)
		d.labelOutline = s.labelOutline; d.labelShadow = s.labelShadow; d.labelThick = s.labelThick; d.labelMono = s.labelMono; d.labelSpecial = s.labelSpecial
		d.timeFont = s.timeFont; d.timeFSize = s.timeFSize; d.timeAlpha = s.timeAlpha; d.timeColor = MOD.CopyColor(s.timeColor)
		d.timeOutline = s.timeOutline; d.timeShadow = s.timeShadow; d.timeThick = s.timeThick; d.timeMono = s.timeMono; d.timeSpecial = s.timeSpecial
		d.iconFont = s.iconFont; d.iconFSize = s.iconFSize; d.iconAlpha = s.iconAlpha; d.iconColor = MOD.CopyColor(s.iconColor)
		d.iconOutline = s.iconOutline; d.iconShadow = s.iconShadow; d.iconThick = s.iconThick; d.iconMono = s.iconMono; d.iconSpecial = s.iconSpecial
		d.texture = s.texture; d.bgtexture = s.bgtexture; d.alpha = s.alpha; d.combatAlpha = s.combatAlpha; d.fgAlpha = s.fgAlpha; d.bgAlpha = s.bgAlpha
		d.fgSaturation = s.fgSaturation; d.fgBrightness = s.fgBrightness; d.bgSaturation = s.bgSaturation; d.bgBrightness = s.bgBrightness;
		d.backdropTexture = s.backdropTexture; d.backdropWidth = s.backdropWidth; d.backdropInset = s.backdropInset
		d.backdropPadding = s.backdropPadding; d.backdropPanel = s.backdropPanel; d.backdropEnable = s.backdropEnable
		d.backdropColor = MOD.CopyColor(s.backdropColor); d.backdropFill = MOD.CopyColor(s.backdropFill)
		d.backdropOffsetX = s.backdropOffsetX; d.backdropOffsetY = s.backdropOffsetY; d.backdropPadW = s.backdropPadW; d.backdropPadH = s.backdropPadH
		d.borderTexture = s.borderTexture; d.borderWidth = s.borderWidth; d.borderOffset = s.borderOffset
		d.borderColor = MOD.CopyColor(s.borderColor); d.borderFill = MOD.CopyColor(s.borderFill)
		d.borderSaturation = s.borderSaturation; d.borderBrightness = s.borderBrightness
	end
end

-- Copy standard colors between tables
function MOD:CopyStandardColors(s, d)
	if s and d and (s ~= d) then
		d.buffColor = MOD.CopyColor(s.buffColor); d.debuffColor = MOD.CopyColor(s.debuffColor)
		d.cooldownColor = MOD.CopyColor(s.cooldownColor); d.notificationColor = MOD.CopyColor(s.notificationColor)
		d.poisonColor = MOD.CopyColor(s.poisonColor); d.curseColor = MOD.CopyColor(s.curseColor)
		d.magicColor = MOD.CopyColor(s.magicColor); d.diseaseColor = MOD.CopyColor(s.diseaseColor)
		d.stealColor = MOD.CopyColor(s.stealColor); d.enrageColor = MOD.CopyColor(s.enrageColor);
		d.brokerColor = MOD.CopyColor(s.brokerColor); d.valueColor = MOD.CopyColor(s.valueColor)
	end
end

-- Copy time format settings between tables
function MOD:CopyTimeFormat(s, d)
	if s and d and (s ~= d) then
		d.timeFormat = s.timeFormat; d.timeSpaces = s.timeSpaces; d.timeCase = s.timeCase
	end
end

-- Find and cache spell ids (this should be used rarely, primarily when entering spell names manually
function MOD:GetSpellID(name)
	if not name then return nil end -- prevent parameter error
	if string.find(name, "^#%d+") then return tonumber(string.sub(name, 2)) end -- check if name is in special format for specific spell id (i.e., #12345)

	local id = spellIDs[name]
	if id then
		if (id == 0) then return nil end -- only scan invalid ones once in a session
		if (name ~= SHIM:GetSpellInfo(id)) then id = nil end -- verify it is still valid
	end
	if not id and not InCombatLockdown() then -- disallow the search when in combat due to script time limit
		local sid = 1 -- scan all possible spell ids (time consuming so cache the result)
		spellIDs[name] = 0 -- initialize cache to 0 to indicate invalid spell name to avoid searching again
		while sid < maxSpellID do -- determined during initialization
			sid = sid + 1
			if not badSpellIDs[sid] then -- bogus spell ids that trigger a (recoverable) crash report in Shadowlands beta
				if (name == SHIM:GetSpellInfo(sid)) then -- found the name!
					spellIDs[name] = sid -- remember valid spell name and id pairs
					return sid
				end
			end
		end
	end
	return id
end

-- Add a texture to the icons cache
function MOD:SetIcon(name, texture)
	if name and texture then iconCache[name] = texture end -- add to the in-memory icon cache
end

-- Get a texture from the icons cache, if not there try to get by spell name and cache if found.
-- If not found then look up spell identifier and use it to locate a texture.
function MOD:GetIcon(name, spellID)
	if not name or (name == "none") or (name == "") then return nil end -- make sure valid name string

	local override = MOD.db.global.SpellIcons[name] -- check the spell icon override cache for an overriding spell name or numeric id
	if override and (override ~= "none") and (override ~= "") then name = override end -- make sure it is valid too

	local id = nil -- next check if the name is a numeric spell id (with or without preceding # sign)
	if string.find(name, "^#%d+") then id = tonumber(string.sub(name, 2)) else id = tonumber(name) end
	if id then return SHIM:GetSpellTexture(id) end -- found what is supposed to be a spell id number

	local tex = iconCache[name] -- check the in-memory icon cache which is initialized from player's spell book
	if not tex then -- if not found then try to look it up through spell API
		tex = SHIM:GetSpellTexture(name)
		if tex and tex ~= "" then
			iconCache[name] = tex -- only cache textures found by looking up the name
		else
			id = spellID or MOD:GetSpellID(name)
			if id then
				tex = SHIM:GetSpellTexture(id) -- then try based on id
				if tex == "" then tex = nil end
			end
		end
	end
	return tex
end

-- Add a color to the cache, update values in case they have changed
function MOD:SetColor(name, c)
	if name and c then
		local t = MOD.db.global.SpellColors[name]
		if t then
			t.r, t.g, t.b, t.a = c.r, c.g, c.b, c.a
		else
			MOD.db.global.SpellColors[name] = MOD.CopyColor(c)
		end
	end
end

-- Get a color from the cache of given name, but if not in cache then return nil
function MOD:GetColor(name, spellID)
	local c = nil
	if spellID then c = MOD.db.global.SpellColors["#" .. tostring(spellID)] end -- allow names stored as #spellid
	if not c then c = MOD.db.global.SpellColors[name] end
	return c
end

-- Reset a color in the cache
function MOD:ResetColor(name)
	if name then MOD.db.global.SpellColors[name] = nil end
end

-- Add a color to the cache, update values in case they have changed
function MOD:SetExpireColor(name, c)
	if name and c then
		local t = MOD.db.global.ExpireColors[name]
		if t then
			t.r, t.g, t.b, t.a = c.r, c.g, c.b, c.a or 1
		else
			MOD.db.global.ExpireColors[name] = MOD.CopyColor(c)
		end
	end
end

-- Get a color from the cache of given name, but if not in cache then return nil
function MOD:GetExpireColor(name, spellID)
	local c = nil
	if spellID then c = MOD.db.global.ExpireColors["#" .. tostring(spellID)] end -- allow names stored as #spellid
	if not c then c = MOD.db.global.ExpireColors[name] end
	return c
end

-- Reset a color in the cache
function MOD:ResetExpireColor(name)
	if name then MOD.db.global.ExpireColors[name] = nil end
end

-- Add a label to the cache but only if different from name
function MOD:SetLabel(name, label)
	if name and label then
		if name == label then MOD.db.global.Labels[name] = nil else MOD.db.global.Labels[name] = label end
	end
end

-- Get a label from the cache, but if not in the cache then return the name
function MOD:GetLabel(name, spellID)
	local label = nil
	if spellID then label = MOD.db.global.Labels["#" .. tostring(spellID)] end -- allow names stored as #spellid
	if not label then label = MOD.db.global.Labels[name] end
	if not label and name and string.find(name, "^#%d+") then
		local id = tonumber(string.sub(name, 2))
		if id then
			local t = SHIM:GetSpellInfo(id)
			if t then label = t .. " (" .. name .. ")" end -- special case format: spellname (#spellid)
		end
	end
	if not label then label = name end
	return label
end

-- Reset all labels to default values
function MOD:ResetLabelDefaults() table.wipe(MOD.db.global.Labels) end

-- Reset all icons to default values
function MOD:ResetIconDefaults() table.wipe(MOD.db.global.SpellIcons) end

-- Add a sound to the cache
function MOD:SetSound(name, sound) if name then MOD.db.global.Sounds[name] = sound end end

-- Get a sound from the cache, return nil if none specified
function MOD:GetSound(name, spellID)
	local sound = nil
	if spellID then sound = MOD.db.global.Sounds["#" .. tostring(spellID)] end -- allow names stored as #spellid
	if name and not sound then sound = MOD.db.global.Sounds[name] end
	return sound
end

-- Reset all sounds to default values
function MOD:ResetSoundDefaults() table.wipe(MOD.db.global.Sounds) end

-- Add an expire time to the cache
function MOD:SetSpellExpireTime(name, t) if name then MOD.db.global.ExpireTimes[name] = t end end

-- Get an expire time from the cache, return nil if none specified
function MOD:GetSpellExpireTime(name, spellID)
	local t = nil
	if spellID then t = MOD.db.global.ExpireTimes["#" .. tostring(spellID)] end -- allow names stored as #spellid
	if name and not t then t = MOD.db.global.ExpireTimes[name] end
	return t
end

-- Reset all expire times to default values
function MOD:ResetExpireTimeDefaults() table.wipe(MOD.db.global.ExpireTimes) end

-- Reset all expire colors to default values
function MOD:ResetExpireColorDefaults() table.wipe(MOD.db.global.ExpireColors) end

-- Add a spell duration to the per-profile cache, always save latest value since could change with haste
-- When the spell id is known, save duration indexed by spell id; otherwise save indexed by name
function MOD.SetDuration(name, spellID, duration)
	if duration == 0 then duration = nil end -- remove cache entry if duration is 0
	if spellID then MOD.db.profile.Durations[spellID] = duration else MOD.db.profile.Durations[name] = duration end
end

-- Get a duration from the cache, but if not in the cache then return 0
function MOD.GetDuration(name, spellID)
	local duration = 0
	if spellID then duration = MOD.db.profile.Durations[spellID] end -- first look for durations indexed by spell id
	if not duration then duration = MOD.db.profile.Durations[name] end -- second look at durations indexed by just name
	if not duration then duration = 0 end
	return duration
end

-- Get a spell type from the cache, but if not in the cache then return nil
function MOD.GetSpellType(id)
	if id then return MOD.db.global.SpellTypes[id] end
	return nil
end

-- Add a spell type to the cache
function MOD.SetSpellType(id, btype)
	if id then MOD.db.global.SpellTypes[id] = btype end
end

-- Get localized names for all spells used internally or in built-in conditions, spell ids must be valid
function MOD:SetSpellNameDefaults()
	LSPELL["Freezing Trap"] = SHIM:GetSpellInfo(1499)
	LSPELL["Ice Trap"] = SHIM:GetSpellInfo(13809)
	LSPELL["Immolation Trap"] = SHIM:GetSpellInfo(13795)
	LSPELL["Explosive Trap"] = SHIM:GetSpellInfo(13813)
	LSPELL["Black Arrow"] = SHIM:GetSpellInfo(3674)
	LSPELL["Frost Shock"] = SHIM:GetSpellInfo(8056)
	LSPELL["Flame Shock"] = SHIM:GetSpellInfo(8050)
	LSPELL["Earth Shock"] = SHIM:GetSpellInfo(8042)
	LSPELL["Defensive Stance"] = SHIM:GetSpellInfo(71)
	LSPELL["Berserker Stance"] = SHIM:GetSpellInfo(2458)
	LSPELL["Battle Stance"] = SHIM:GetSpellInfo(2457)
	LSPELL["Battle Shout"] = SHIM:GetSpellInfo(6673)
	LSPELL["Commanding Shout"] = SHIM:GetSpellInfo(469)
	LSPELL["Flight Form"] = SHIM:GetSpellInfo(33943)
	LSPELL["Swift Flight Form"] = SHIM:GetSpellInfo(40120)
	LSPELL["Earthliving Weapon"] = SHIM:GetSpellInfo(51730)
	LSPELL["Flametongue Weapon"] = SHIM:GetSpellInfo(8024)
	LSPELL["Frostbrand Weapon"] = SHIM:GetSpellInfo(8033)
	LSPELL["Rockbiter Weapon"] = SHIM:GetSpellInfo(8017)
	LSPELL["Windfury Weapon"] = SHIM:GetSpellInfo(8232)
	LSPELL["Crusader Strike"] = SHIM:GetSpellInfo(35395)
	LSPELL["Hammer of the Righteous"] = SHIM:GetSpellInfo(53595)
	LSPELL["Combustion"] = SHIM:GetSpellInfo(83853)
	LSPELL["Pyroblast"] = SHIM:GetSpellInfo(11366)
	LSPELL["Living Bomb"] = SHIM:GetSpellInfo(44457)
	LSPELL["Ignite"] = SHIM:GetSpellInfo(12654)
end

-- Check if a spell id is available to the player (i.e., in the active spell book)
local function RavenCheckSpellKnown(spellID)
	local name = SHIM:GetSpellInfo(spellID)
	if not name or name == "" then return false end
	return MOD.bookSpells[name]
end

-- Initialize the dispel table which lists what types of debuffs the player can dispel
-- This needs to be updated when the player changes talent specs or learns new spells
function MOD:SetDispelDefaults()
	dispelTypes.Poison = false; dispelTypes.Curse = false; dispelTypes.Magic = false; dispelTypes.Disease = false
	if MOD.myClass == "DRUID" then
		if RavenCheckSpellKnown(88423) then -- Nature's Cure
			dispelTypes.Poison = true; dispelTypes.Curse = true; dispelTypes.Magic = true
		elseif RavenCheckSpellKnown(2782) then -- Remove Corruption
			dispelTypes.Poison = true; dispelTypes.Curse = true
		end
	elseif MOD.myClass == "EVOKER" then
		if RavenCheckSpellKnown(360823) then -- Naturalize
			dispelTypes.Poison = true; dispelTypes.Magic = true
		elseif RavenCheckSpellKnown(365585) then
			dispelTypes.Poison = true -- Expunge
		end
	elseif MOD.myClass == "MONK" then
		if RavenCheckSpellKnown(115450) then -- Detox (healer)
			dispelTypes.Poison = true; dispelTypes.Disease = true; dispelTypes.Magic = true
		elseif RavenCheckSpellKnown(218164) then -- Detox
			dispelTypes.Poison = true; dispelTypes.Disease = true
		end
	elseif MOD.myClass == "PRIEST" then
		if RavenCheckSpellKnown(527) then -- Purify
			dispelTypes.Magic = true; dispelTypes.Disease = true
		elseif RavenCheckSpellKnown(32375) then -- Mass Dispel
			dispelTypes.Magic = true
		end
	elseif MOD.myClass == "PALADIN" then
		if RavenCheckSpellKnown(4987) then -- Cleanse
			dispelTypes.Poison = true; dispelTypes.Disease = true; dispelTypes.Magic = true
		elseif RavenCheckSpellKnown(213644) then
			dispelTypes.Poison = true; dispelTypes.Disease = true -- Cleanse Toxins
		end
	elseif MOD.myClass == "SHAMAN" then
		if RavenCheckSpellKnown(77130) then -- Purify Spirit
			dispelTypes.Curse = true; dispelTypes.Magic = true
		elseif RavenCheckSpellKnown(51886) then -- Cleanse Spirit
			dispelTypes.Curse = true
		end
	elseif MOD.myClass == "MAGE" then
		if RavenCheckSpellKnown(475) then -- Remove Curse
			dispelTypes.Curse = true
		end
	end
	MOD.updateDispels = false
end

-- Return true if the player can dispel the type of debuff on the unit
function MOD:IsDebuffDispellable(n, unit, debuffType)
	if not debuffType then return false end
	if MOD.updateDispels == true then MOD:SetDispelDefaults() end
	local t = dispelTypes[debuffType]
	if not t then return false end
	if (t == "player") and (unit ~= "player") then return false end -- special case for self-only dispels
	if unit == "player" then return true end -- always can dispel debuffs on self
	if UnitIsFriend("player", unit) then return true end -- only can dispel on friendly units
	return false
end

-- Format a time value in seconds, return converted string or nil if invalid index
function MOD:FormatTime(t, index, spaces, upperCase)
	if (index > 0) and (index <= #MOD.Nest_TimeFormatOptions) then
		return MOD.Nest_FormatTime(t, index, spaces, upperCase)
	end
	return nil
end

-- Register a new time format option and return its assigned index
function MOD:RegisterTimeFormat(func) return MOD.Nest_RegisterTimeFormat(func) end

-- Reset the spells in a bar group list filter (should be called during OnEnable, not during OnInitialize)
-- Particularly useful if you are changing localization and need to register spells in a new language
function Raven:ResetBarGroupFilter(bgName, list)
	local listName = nil
	if list == "Buff" then listName = "filterBuffList"
	elseif list == "Debuff" then listName = "filterDebuffList"
	elseif list == "Cooldown" then listName = "filterCooldownList" end

	if bgName and listName then
		local bg = MOD.db.profile.BarGroups[bgName]
		if bg then bg[listName] = nil end
	end
end

-- Register a spell in a bar group filter (must be called during OnEnable, not OnInitialize)
-- Raven:RegisterBarGroupFilter(barGroupName, "Buff"|"Debuff"|"Cooldown", spellNameOrID)
-- Note that if the bar group's filter list is linked then the entries will also be added to the associated shared filter list.
function MOD:RegisterBarGroupFilter(bgName, list, spell)
	local listName = nil
	if list == "Buff" then listName = "filterBuffList"
	elseif list == "Debuff" then listName = "filterDebuffList"
	elseif list == "Cooldown" then listName = "filterCooldownList" end

	local id = tonumber(spell) -- convert to spell name if provided a number
	if id then spell = SHIM:GetSpellInfo(id); if spell == "" then spell = nil end end

	if bgName and listName and spell then
		local bg = MOD.db.profile.BarGroups[bgName]
		if bg then
			local filterList = bg[listName]
			if not filterList then filterList = {}; bg[listName] = filterList end
			filterList[spell] = spell
		end
	end
end

-- Register a spell table (must be called during OnEnable, not OnInitialize)
-- Table should contain a list of spell names or numeric identifiers (prefered for localization)
-- Return number of unique spells successfully registered.
function MOD:RegisterSpellList(name, spellList, reset)
	local slt, count = MOD.db.global.SpellLists[name], 0
	if not slt then slt = {}; MOD.db.global.SpellLists[name] = slt end
	if reset then table.wipe(slt) end
	for _, spell in pairs(spellList) do
		local n, id = spell, tonumber(spell) -- convert to spell name if provided a number
		if string.find(n, "^#%d+") then
			id = tonumber(string.sub(n, 2)); if id and SHIM:GetSpellInfo(id) == "" then id = nil end -- support #12345 format for spell ids
		else
			if id then -- otherwise look up the id
				n = SHIM:GetSpellInfo(id)
				if n == "" then n = nil end -- make sure valid return
			else
				id = MOD:GetSpellID(n)
			end
		end
		if n and id then -- only spells with valid name and id
			if not slt[n] then count = count + 1 end
			slt[n] = id
		else
			if spell and MOD.db.profile.spellDebug then print(L["Not valid string"](spell)) end
		end
	end
	return count
end

-- Register Raven's media entries to LibSharedMedia
function MOD:InitializeMedia(media)
	local mt = media.MediaType.SOUND
	media:Register(mt, "Raven Alert", [[Interface\Addons\Raven\Sounds\alert.ogg]])
	media:Register(mt, "Raven Bell", [[Interface\Addons\Raven\Sounds\bell.ogg]])
	media:Register(mt, "Raven Boom", [[Interface\Addons\Raven\Sounds\boom.ogg]])
	media:Register(mt, "Raven Buzzer", [[Interface\Addons\Raven\Sounds\buzzer.ogg]])
	media:Register(mt, "Raven Chimes", [[Interface\Addons\Raven\Sounds\chime.ogg]])
	media:Register(mt, "Raven Clong", [[Interface\Addons\Raven\Sounds\clong.ogg]])
	media:Register(mt, "Raven Coin", [[Interface\Addons\Raven\Sounds\coin.ogg]])
	media:Register(mt, "Raven Coocoo", [[Interface\Addons\Raven\Sounds\coocoo.ogg]])
	media:Register(mt, "Raven Creak", [[Interface\Addons\Raven\Sounds\creak.ogg]])
	media:Register(mt, "Raven Drill", [[Interface\Addons\Raven\Sounds\drill.ogg]])
	media:Register(mt, "Raven Elephant", [[Interface\Addons\Raven\Sounds\elephant.ogg]])
	media:Register(mt, "Raven Flute", [[Interface\Addons\Raven\Sounds\flute.ogg]])
	media:Register(mt, "Raven Honk", [[Interface\Addons\Raven\Sounds\honk.ogg]])
	media:Register(mt, "Raven Knock", [[Interface\Addons\Raven\Sounds\knock.ogg]])
	media:Register(mt, "Raven Laser", [[Interface\Addons\Raven\Sounds\laser.ogg]])
	media:Register(mt, "Raven Rub", [[Interface\Addons\Raven\Sounds\rubbing.ogg]])
	media:Register(mt, "Raven Slide", [[Interface\Addons\Raven\Sounds\slide.ogg]])
	media:Register(mt, "Raven Squeaky", [[Interface\Addons\Raven\Sounds\squeaky.ogg]])
	media:Register(mt, "Raven Whistle", [[Interface\Addons\Raven\Sounds\whistle.ogg]])
	media:Register(mt, "Raven Zoing", [[Interface\Addons\Raven\Sounds\zoing.ogg]])

	mt = media.MediaType.STATUSBAR
	media:Register(mt, "Raven Black", [[Interface\Addons\Raven\Statusbars\Black.tga]])
	media:Register(mt, "Raven CrossHatch", [[Interface\Addons\Raven\Statusbars\CrossHatch.tga]])
	media:Register(mt, "Raven DarkAbove", [[Interface\Addons\Raven\Statusbars\DarkAbove.tga]])
	media:Register(mt, "Raven DarkBelow", [[Interface\Addons\Raven\Statusbars\DarkBelow.tga]])
	media:Register(mt, "Raven Deco", [[Interface\Addons\Raven\Statusbars\Deco.tga]])
	media:Register(mt, "Raven Foggy", [[Interface\Addons\Raven\Statusbars\Foggy.tga]])
	media:Register(mt, "Raven Glassy", [[Interface\Addons\Raven\Statusbars\Glassy.tga]])
	media:Register(mt, "Raven Glossy", [[Interface\Addons\Raven\Statusbars\Glossy.tga]])
	media:Register(mt, "Raven Gray", [[Interface\Addons\Raven\Statusbars\Gray.tga]])
	media:Register(mt, "Raven Linear", [[Interface\Addons\Raven\Statusbars\Linear.tga]])
	media:Register(mt, "Raven Mesh", [[Interface\Addons\Raven\Statusbars\Mesh.tga]])
	media:Register(mt, "Raven Minimal", [[Interface\Addons\Raven\Statusbars\Minimal.tga]])
	media:Register(mt, "Raven Paper", [[Interface\Addons\Raven\Statusbars\Paper.tga]])
	media:Register(mt, "Raven Reticulate", [[Interface\Addons\Raven\Statusbars\Reticulate.tga]])
	media:Register(mt, "Raven Reverso", [[Interface\Addons\Raven\Statusbars\Reverso.tga]])
	media:Register(mt, "Raven Sleet", [[Interface\Addons\Raven\Statusbars\Sleet.tga]])
	media:Register(mt, "Raven Smoke", [[Interface\Addons\Raven\Statusbars\Smoke.tga]])
	media:Register(mt, "Raven Smudge", [[Interface\Addons\Raven\Statusbars\Smudge.tga]])
	media:Register(mt, "Raven StepIn", [[Interface\Addons\Raven\Statusbars\StepIn.tga]])
	media:Register(mt, "Raven StepOut", [[Interface\Addons\Raven\Statusbars\StepOut.tga]])
	media:Register(mt, "Raven Strip", [[Interface\Addons\Raven\Statusbars\Strip.tga]])
	media:Register(mt, "Raven Stripes", [[Interface\Addons\Raven\Statusbars\Stripes.tga]])
	media:Register(mt, "Raven Sunrise", [[Interface\Addons\Raven\Statusbars\Sunrise.tga]])
	media:Register(mt, "Raven White", [[Interface\Addons\Raven\Statusbars\White.tga]])

	mt = media.MediaType.BORDER
	media:Register(mt, "Raven SingleWhite", [[Interface\Addons\Raven\Borders\SingleWhite.tga]])
	media:Register(mt, "Raven SingleGray", [[Interface\Addons\Raven\Borders\SingleGray.tga]])
	media:Register(mt, "Raven DoubleWhite", [[Interface\Addons\Raven\Borders\DoubleWhite.tga]])
	media:Register(mt, "Raven DoubleGray", [[Interface\Addons\Raven\Borders\DoubleGray.tga]])
	media:Register(mt, "Raven Rounded", [[Interface\Addons\Raven\Borders\Rounded.tga]])
	media:Register(mt, "Raven White8x8", [[Interface\BUTTONS\WHITE8X8.blp]])
end

-- Default profile description used to initialize the SavedVariables persistent database
MOD.DefaultProfile = {
	global = {
		Labels = {},					-- cache of labels for actions and spells
		Sounds = {},					-- cache of sounds for actions and spells
		ExpireTimes = {},				-- cache of expire times for actions and spells
		SpellColors = {},				-- cache of colors for actions and spells
		ExpireColors = {},				-- cache of expire colors for actions and spells
		SpellIcons = {},				-- cache of spell icons that override default icons
		SpellIDs = {},					-- cache of spell ids that had to be looked up
		SpellTypes = {},				-- cache of spell types (indexed by spell id)
		Settings = {},					-- settings table indexed by bar group names
		CustomBars = {},				-- custom bar table indexed by bar group names
		Defaults = {},					-- default settings for bar group layout, fonts and textures
		FilterBuff = {},				-- shared table of buff filters
		FilterDebuff = {},				-- shared table of debuff filters
		FilterCooldown = {},			-- shared table of cooldown filters
		SharedConditions = {},			-- shared condition settings
		BuffDurations = {},				-- cache of buff durations used for weapon buffs
		DetectInternalCooldowns = true,	-- enable detecting internal cooldowns
		InternalCooldowns = {},			-- descriptors for internal cooldowns
		DetectSpellAlerts = false,		-- enable detecting spell alerts
		SpellAlerts = {},				-- general settings for spell alerts
		EnemySpellCastAlerts = {},		-- settings for enemy spell cast alerts
		FriendSpellCastAlerts = {},		-- settings for friend spell cast alerts
		EnemyBuffAlerts = {},			-- settings for enemy buff alerts
		FriendDebuffAlerts = {},		-- settings for friend debuff alerts
		DetectSpellEffects = true,		-- enable detecting spell effects
		SpellEffects = {},				-- descriptors for spell effects
		SpellLists = {},				-- spell lists
		DefaultBuffColor = MOD.HexColor("8ae234"), -- Green1
		DefaultDebuffColor = MOD.HexColor("fcaf3e"), -- Orange1
		DefaultCooldownColor = MOD.HexColor("fce94f"), -- Yellow1
		DefaultNotificationColor = MOD.HexColor("729fcf"), -- Blue1
		DefaultBrokerColor = MOD.HexColor("888a85"), -- Gray
		DefaultValueColor = MOD.HexColor("d0756c"), -- Pink-ish
		DefaultPoisonColor = MOD.CopyColor(DebuffTypeColor["Poison"]),
		DefaultCurseColor = MOD.CopyColor(DebuffTypeColor["Curse"]),
		DefaultMagicColor = MOD.CopyColor(DebuffTypeColor["Magic"]),
		DefaultDiseaseColor = MOD.CopyColor(DebuffTypeColor["Disease"]),
		DefaultStealColor = MOD.HexColor("ef2929"), -- Red1
		DefaultEnrageColor = MOD.HexColor("ffb249"), -- Brown-Orange
		ButtonFacadeIcons = true,		-- enable use of ButtonFacade for icons
		ButtonFacadeNormal = true,		-- enable color of normal texture in ButtonFacade
		ButtonFacadeBorder = false,		-- enable color of border texture in ButtonFacade
		SoundChannel = "Master",		-- by default, use the Master sound channel
		HideOmniCC = false,				-- hide OmniCC counts on all bar group icons
		HideBorder = true,				-- hide custom border in all bar groups
		TukuiSkin = true,				-- skin bars with Tukui borders
		TukuiFont = true,				-- skin with Tukui fonts
		TukuiIcon = true,				-- skin icons also with Tukui borders
		TukuiScale = true,				-- skin Tukui with pixel perfect size and position
		PixelPerfect = false,			-- enable pixel perfect size and position
		AdustUIScale = false,			-- enable adjustment of the UI scale during initialization
		SilentUIScale = false,			-- enable reporting the UI scale during initialization
		OverrideUIScale = false,			-- enable setting the UI scale during initialization to specified value
		SetUIScale = 0,			-- value to set the UI scale during initialization (0 is adjusted to current value)
		PixelIconBorder = false,		-- enable a single pixel color border for icons
		RectIcons = false,				-- enable rectangular icons
		ZoomIcons = false,				-- enable zoomed rectangular icons
		IconClockEdge = false,			-- enable edge for icon clock overlays
		GridLines = 40,					-- number of lines in overlay grid
		GridCenterColor = MOD.HexColor("ff0000"), -- color of center lines in overlay grid
		GridLineColor = MOD.HexColor("00ff00"), -- color of other lines in overlay grid
		GridAlpha = 0.5,				-- transparency of overlay grid
		IncludePartyUnits = false,		-- track party units for buffs and debuffs
		IncludeBossUnits = false,		-- track boss units for buffs and debuffs
		IncludeArenaUnits = false,		-- track arena units for buffs and debuffs
		UpdateRate = 0.2,				-- 1 / target number of bar group updates per second
		AnimationRate = 0.03333,		-- 1 / target number of animation refresh cycles per second
		ThrottleRate = 5,				-- target for maximum count of updates to skip when no events detected
		CombatThrottleRate = 5,			-- target for maximum count of updates to skip when no events detected and in combat
		DefaultBorderColor = MOD.HexColor("ffffff"), -- icon border color when "None" is selected
		DefaultIconBackdropColor = MOD.HexColor("3f3f3f"), -- icon backdrop color when using one pixel wide borders
		Minimap = { hide = false, minimapPos = 180, radius = 80, }, -- saved DBIcon minimap settings
		InCombatBar = {},				-- shared settings for the in-combat bar
	},
	profile = {
		enabled = true,					-- enable Raven
		hideBlizz = true,				-- hide Blizzard UI parts
		hideBlizzBuffs = true,			-- hide Blizzard buff and temp enchant frames
		hideBlizzDebuffs = true,		-- hide Blizzard debuff frame
		hideBlizzMirrors = false,		-- hide Blizzard mirror bars
		hideBlizzXP = false,			-- hide Blizzard XP and reputation bars
		hideBlizzAzerite = false,		-- hide Blizzard Azerite bar
		hideBlizzComboPoints = false,	-- hide Blizzard combo points
		hideBlizzChi = false,			-- hide Blizzard combo points
		hideBlizzArcane = false,		-- hide Blizzard arcane charges
		hideBlizzHoly = false,			-- hide Blizzard holy power
		hideBlizzEssence = false,		-- hide Blizzard essence
		hideBlizzShards = false,		-- hide Blizzard soul shards
		hideBlizzInsanity = false,		-- hide Blizzard insanity
		hideBlizzTotems = false,		-- hide Blizzard totems
		hideBlizzStagger = false,		-- hide Blizzard stagger bar
		hideRunes = false,				-- hide Blizzard runes frame
		hideBlizzPlayer = false,		-- hide Blizzard player unit frame
		hideBlizzPet = false,			-- hide Blizzard pet unit frame
		hideBlizzTarget = false,		-- hide Blizzard target unit frame
		hideBlizzFocus = false,			-- hide Blizzard focus unit frame
		hideBlizzTargetTarget = false,	-- hide Blizzard target's target unit frame
		hideBlizzFocusTarget = false,	-- hide Blizzard focus's target unit frame
		muteSFX = false,				-- enable muting of Raven's sound effects
		spellDebug = false,				-- enable invalid spell warnings
		Durations = {},					-- spell durations (use profile instead of global for better per-character info)
		BarGroups = {},					-- bar group options to be filled in and saved between sessions
		Conditions = {}, 				-- conditions for the player's class
		ButtonFacadeSkin = {},			-- skin settings from ButtonFacade
		InCombatBar = {},				-- settings for the in-combat bar used to cancel buffs in combat
		InCombatBuffs = {},				-- list of buffs that can be cancelled in-combat
		WeaponBuffDurations = {},		-- cache of buff durations used for weapon buffs
		version = 0,					-- allows step-by-step migrations to support splitting options while preserving backwards compatibility
	},
}
