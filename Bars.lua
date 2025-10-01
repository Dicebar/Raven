-- Raven is an addon to monitor auras and cooldowns, providing timer bars and icons plus helpful notifications.

-- Bars.lua supports mapping auras to bars and grouping bars into multiple moveable frames.
-- It has special case code for tooltips, test bars, shaman totems, and death knight runes.
-- There are no exported functions at this time other than those called to initialize and update bars.

local MOD = Raven
local SHIM = MOD.SHIM
local L = LibStub("AceLocale-3.0"):GetLocale("Raven")
local LSPELL = MOD.LocalSpellNames
local media = LibStub("LibSharedMedia-3.0")
local wc = { r = 1, g = 1, b = 1, a = 1 }
local rc = { r = 1, g = 0, b = 0, a = 1 }
local vc = { r = 1, g = 0, b = 0, a = 0 }
local zc = { r = 1, g = 1, b = 1, a = 0 }
local gc = { r = 0.5, g = 0.5, b = 0.5, a = 0.5 }
local hidden = false
local detectedBar = {}
local headerBar = {}
local groupIDs = {}
local settingsTemplate = {} -- settings are initialized from default bar group template
local activeSpells = {} -- temporary table used for finding ghost bars
local defaultNotificationIcon = "Interface\\Icons\\Spell_Nature_WispSplode"
local defaultBrokerIcon = "Interface\\Icons\\Inv_Misc_Book_03"
local defaultValueIcon = "Interface\\Icons\\Inv_Jewelry_Ring_03"
local defaultTestIcon = "Interface\\Icons\\Spell_Nature_RavenForm"
local frequentBars = {} -- bars tagged for frequent updates
local prefixRaidTargetIcon = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_"
local testColors = { "Blue1", "Cyan", "Green1", "Yellow1", "Orange1", "Red1", "Pink", "Purple1", "Brown1", "Gray" }
local tabardIcon
local units = { player = true, target = true, focus = true, pet = true, targettarget = true, focustarget = true, pettarget = true, mouseover = true }

-- Saved variables don't handle being set to nil properly so need to use alternate value to indicate an option has been turned off
local Off = 0 -- value used to designate an option is turned off
local function IsOff(value) return value == nil or value == Off end -- return true if option is turned off
local function IsOn(value) return value ~= nil and value ~= Off end -- return true if option is turned on

local colorTemplate = { timeColor = 0, iconColor = 0, labelColor = 0, backdropColor = 0, backdropFill = 0, borderColor = 0, } -- colors in default fonts and textures
local function DefaultColor(c) return not c or not next(c) or ((c.r == 1) and (c.g == 1) and (c.b == 1) and (c.a == 1)) end
local defaultLabels = { 0, 1, 10, 30, "1m", "2m", "5m" }
function MOD:GetTimelineLabels() return defaultLabels end

MOD.BarGroupTemplate = { -- default bar group settings
	enabled = true, locked = true, merged = false, linkSettings = false, linkBars = false, checkCondition = false, noMouse = false, iconMouse = true,
	barColors = "Spell", bgColors = "Normal", iconColors = "None", combatTips = true,
	casterTips = true, spellTips = false, casterLabels = false, spellLabels = false, anchorTips = "DEFAULT",
	useDefaultDimensions = true, useDefaultFontsAndTextures = true, useDefaultColors = true, useDefaultTimeFormat = false, strata = "MEDIUM",
	sor = "A", reverseSort = false, timeSort = true, playerSort = false,
	configuration = 1, anchor = false, anchorX = 0, anchorY = 0, anchorLastBar = false, anchorRow = false, anchorColumn = true, anchorEmpty = false,
	growDirection = true, fillBars = false, segmentBars = false, wrap = 0, wrapDirection = false, snapCenter = false, maxBars = 0,
	segmentCount = 10, segmentOverride = false, segmentSpacing = 1, segmentHideEmpty = false,
	segmentAdvanced = false, segmentCurve = 0, segmentRotate = 0, segmentTexture = false,
	segmentFadePartial = false, segmentShrinkWidth = false, segmentShrinkHeight = false, segmentGradient = false, segmentGradientAll = false,
	disableBGSFX = false, customizeSFX = false,	shineColor = false, sparkleColor = false, glowColor = false,
	expireFGBG = false, flashPeriod = 1.2, flashPercent = 50, combatTextExcludesBG = false,
	shineStart = false, sparkleStart, pulseStart = false, glowStart = false, flashStart = false, desatStart = false,
	shineExpiring = false, sparkleExpiring = false, pulseExpiring = false, glowExpiring = false, flashExpiring = false, desatExpiring = false,
	startEffectTime = 5, endEffectTime = 5, delayTime = 0,
	combatStart = false, combatCriticalStart = false, expireMSBT = false, criticalMSBT = false,
	combatEnd = false, combatCriticalEnd = false, combatReady = false, combatCriticalReady = false,
	shineReady = false, sparkleReady = false, pulseReady = false, glowReady = false, flashReady = false, desaturateReadyIcon = false,
	shineEnd = false, sparkleEnd = false, pulseEnd = false, splash = false, ghost = false, hide = false, fade = false,
	bgNormalAlpha = 1, bgCombatAlpha = 1, mouseAlpha = 1, fadeAlpha = 1, testTimers = 10, testStatic = 0, testLoop = false,
	soundSpellStart = false, soundSpellEnd = false, soundSpellExpire = false, soundSpellReady = false,
	soundAltStart = "None", soundAltEnd = "None", soundAltExpire = "None", soundAltReady = "None",
	labelOffset = 0, labelInset = 0, labelWrap = false, labelCenter = false, labelAlign = "MIDDLE", labelAdjust = true, labelAuto = true, labelWidth = 100,
	timeOffset = 0, timeInset = 0, timeAlign = "normal", timeIcon = false, iconOffset = 0, iconInset = 0, iconHide = false, iconAlign = "CENTER",
	flashTime = 5, expirePercentage = 0, expireMinimum = 0, colorExpiring = false, clockReverse = true,
	expireColor = false, expireLabelColor = false, expireTimeColor = false, tickColor = false,
	combatColorStart = false, combatColorEnd = false, combatColorReady = false, colorMSBT = false,
	spellExpireTimes = false, spellExpireColors = false, desaturate = false, desaturateFriend = false, disableAlpha = false,
	timelineWidth = 225, timelineHeight = 25, timelineDuration = 300, timelineExp = 3, timelineHide = false, timelineAlternate = true,
	timelineSwitch = 2, timelineTexture = "Blizzard", timelineAlpha = 1, timelineColor = false, timelineLabels = false,
	timelineBorderTexture = "None", timelineBorderWidth = 4, timelineBorderOffset = 1, timelineBorderColor = false,
	timelineSplash = true, timelineSplashX = 0, timelineSplashY = 0, timelinePercent = 50, timelineOffset = 0, timelineDelta = 0,
	stripeFullWidth = false, stripeWidth = 500, stripeHeight = 30, stripeInset = 0, stripeOffset = 0, stripeTexture = "Blizzard",
	stripeBarInset = 4, stripeBarOffset = 0, stripeColor = false, stripeAltColor = false, stripeCheckCondition = false, stripeCondition = false,
	stripeBorderTexture = "None", stripeBorderWidth = 4, stripeBorderOffset = 1, stripeBorderColor = false,
	showSolo = true, showParty = true, showRaid = true, showCombat = true, showOOC = true, showStealth = true, showFocusTarget = true,
	showInstance = true, showNotInstance = true, showArena = true, showBattleground = true, showPetBattle = false, showOnTaxi = true, showSpecialization = "",
	showResting = true, showMounted = true, showVehicle = true, showFriend = true, showEnemy = true, showNeutral = true, showBlizz = true, showNotBlizz = true,
	detectBuffs = false, detectDebuffs = false, detectAllBuffs = false, detectAllDebuffs = false,
	filterDebuffTypes = false, detectDispellable = false, detectInflictable = false, detectNPCDebuffs = false, detectVehicleDebuffs = false, detectBossDebuffs = false,
	detectEffectDebuffs = false, detectAlertDebuffs = false, detectPoison = false, detectCurse = false, detectMagic = false, detectDisease = false, detectOtherDebuffs = false,
	excludeDebuffTypes = true, excludeDispellable = false, excludeInflictable = false, excludeNPCDebuffs = false, excludeVehicleDebuffs = false, excludeBossDebuffs = false,
	excludeEffectDebuffs = false, excludeAlertDebuffs = true, excludePoison = false, excludeCurse = false, excludeMagic = false, excludeDisease = false, excludeOtherDebuffs = false,
	noHeaders = false, noTargets = false, noLabels = false, headerGaps = false, targetFirst = false, targetAlpha = 1, replay = false, replayTime = 5,
	detectBuffTypes = false, detectCastable = false, detectStealable = false, detectMagicBuffs = false, detectEffectBuffs = false, detectAlertBuffs = false,
	detectWeaponBuffs = false, detectNPCBuffs = false, detectVehicleBuffs = false, detectBossBuffs = false, detectEnrageBuffs = false, detectTracking = false,
	detectResources = false, detectMountBuffs = false, detectTabardBuffs = false, detectMinionBuffs = false, detectOtherBuffs = false,
	excludeBuffTypes = true, excludeCastable = false, excludeStealable = false, excludeMagicBuffs = false, excludeEffectBuffs = false, excludeAlertBuffs = true,
	excludeWeaponBuffs = false, excludeNPCBuffs = false, excludeVehicleBuffs = false, excludeBossBuffs = false, excludeEnrageBuffs = false, excludeTracking = true,
	excludeResources = false, excludeMountBuffs = false, excludeTabardBuffs = false, excludeMinionBuffs = true, excludeOtherBuffs = false,
	detectCooldowns = false, detectBuffsMonitor = "player", detectBuffsCastBy = "player", detectDebuffsMonitor = "player",
	detectDebuffsCastBy = "player", detectCooldownsBy = "player",
	detectSpellCooldowns = true, detectTrinketCooldowns = true, detectInternalCooldowns = true, includeTotems = false,
	detectSpellEffectCooldowns = true, detectSpellAlertCooldowns = false, detectPotionCooldowns = true, detectOtherCooldowns = true, detectRuneCooldowns = false, detectGlobalCooldown = true,
	detectSharedGrimoires = true, detectSharedInfernals = true,
	setDuration = false, setOnlyLongDuration = false, uniformDuration = 120, checkDuration = false, minimumDuration = true, filterDuration = 120,
	checkTimeLeft = false, minimumTimeLeft = true, filterTimeLeft = 120, showNoDuration = false, showOnlyNoDuration = false,
	showNoDurationBackground = false, readyReverse = false, noDurationFirst = false, timeFormat = 6, timeSpaces = false, timeCase = false,
	filterBuff = true, filterBuffLink = true, filterBuffSpells = false, filterBuffTable = nil,
	filterBuffSpells2 = false, filterBuffTable2 = nil, filterBuffSpells3 = false, filterBuffTable3 = nil,
	filterBuffSpells4 = false, filterBuffTable4 = nil, filterBuffSpells5 = false, filterBuffTable5 = nil,
	filterDebuff = true, filterDebuffLink = true, filterDebuffSpells = false, filterDebuffTable = nil,
	filterDebuffSpells2 = false, filterDebuffTable2 = nil, filterDebuffSpells3 = false, filterDebuffTable3 = nil,
	filterDebuffSpells4 = false, filterDebuffTable4 = nil, filterDebuffSpells5 = false, filterDebuffTable5 = nil,
	filterCooldown = true, filterCooldownLink = true, filterCooldownSpells = false, filterCooldownTable = nil,
	filterCooldownSpells2 = false, filterCooldownTable2 = nil, filterCooldownSpells3 = false, filterCooldownTable3 = nil,
	filterCooldownSpells4 = false, filterCooldownTable4 = nil, filterCooldownSpells5 = false, filterCooldownTable5 = nil,
	showBuff = false, showDebuff = false, showCooldown = false, filterBuffBars = false, filterDebuffBars = false, filterCooldownBars = false,
	selectAll = true, selectPlayer = false, selectPet = false, selectBoss = false, selectDispel = false, selectSteal = false,
	selectPoison = false, selectCurse = false, selectMagic = false, selectDisease = false, selectEnrage = false,
}

MOD.BarGroupLayoutTemplate = { -- all the bar group settings involved in layout configuration
	barWidth = 0, barHeight = 0, iconSize = 0, scale = 0, spacingX = 0, spacingY = 0, iconOffsetX = 0, iconOffsetY = 0,
	useDefaultDimensions = 0, configuration = 0, growDirection = 0, wrap = 0, wrapDirection = 0, snapCenter = 0, segmentBars = 0, fillBars = 0, maxBars = 0,
	segmentCount = 0, segmentOverride = 0, segmentSpacing = 0, segmentHideEmpty = 0, segmentFadePartial = 0,
	segmentShrinkWidth = 0, segmentShrinkHeight = 0, segmentGradient = 0, segmentGradientAll = 0,
	segmentAdvanced = 0, segmentCurve = 0, segmentRotate = 0, segmentTexture = 0,
	labelOffset = 0, labelInset = 0, labelWrap = 0, labelCenter = 0, labelAlign = 0, labelAdjust = 0, labelAuto = 0, labelWidth = 0,
	timeOffset = 0, timeInset = 0, timeAlign = 0, timeIcon = 0, iconOffset = 0, iconInset = 0, iconHide = 0, iconAlign = 0,
	hideIcon = 0, hideClock = 0, hideBar = 0, hideSpark = 0, hideValue = 0, hideLabel = 0, hideCount = 0, showTooltips = 0,
	timelineWidth = 0, timelineHeight = 0, timelineDuration = 0, timelineExp = 0, timelineHide = 0, timelineAlternate = 0,
	timelineSwitch = 0, timelineTexture = 0, timelineAlpha = 0, timelineColor = 0, timelineLabels = 0,
	timelineBorderTexture = 0, timelineBorderWidth = 0, timelineBorderOffset = 0, timelineBorderColor = 0,
	timelineSplash = 0, timelineSplashX = 0, timelineSplashY = 0, timelinePercent = 0, timelineOffset = 0, timelineDelta = 0,
	stripeFullWidth = 0, stripeWidth = 0, stripeHeight = 0, stripeInset = 0, stripeOffset = 0, stripeTexture = 0,
	stripeBarInset = 0, stripeBarOffset = 0, stripeColor = 0, stripeAltColor = 0, stripeCheckCondition = 0, stripeCondition = 0,
	stripeBorderTexture = 0, stripeBorderWidth = 0, stripeBorderOffset = 0, stripeBorderColor = 0,
}

-- Check for active tooltip for a bar and update once per second
local function BarTooltipUpdate()
	if MOD.tooltipBar and MOD.Bar_OnUpdate then MOD.Bar_OnUpdate(MOD.tooltipBar) end
end

-- Initialize bar groups from those specified in the profile after, for example, a reloadUI or reset profile
function MOD:InitializeBars()
	local bgs = MOD.Nest_GetBarGroups()
	if bgs then for _, bg in pairs(bgs) do MOD.Nest_DeleteBarGroup(bg) end end -- first remove any bar groups represented in the graphics library

	for _, bg in pairs(MOD.db.profile.BarGroups) do -- then set up the ones specified in the profile
		if IsOn(bg) then
			for n, k in pairs(MOD.db.global.Defaults) do -- add default settings for layout, fonts and textures
				if bg[n] == nil then -- only add ones not already set in the bar group's profile
					if colorTemplate[n] then bg[n] = MOD.CopyColor(k) else bg[n] = k end -- colors must be handled specially
				end
			end
			for n, k in pairs(MOD.BarGroupTemplate) do if bg[n] == nil then bg[n] = k end end -- add additional default values from the bar group template
			MOD:InitializeBarGroup(bg, 0, 0)
			if not bg.auto then for _, bar in pairs(bg.bars) do bar.startReady = nil end end -- remove extra settings in custom bars
		end
	end
	MOD:UpdateAllBarGroups() -- this is done last to get all positions updated correctly
	MOD.tooltipBar = nil -- set when showing a tooltip for a bar
	C_Timer.NewTicker(0.5, BarTooltipUpdate) -- update tooltips for bars when hovering over them
end

-- Finalize bar groups prior to logout, stripping out all values that match current defaults
function MOD:FinalizeBars()
	for bn, bg in pairs(MOD.db.profile.BarGroups) do
		if IsOn(bg) then
			bg.cache = nil -- delete bar group cache contents
			for n, k in pairs(MOD.db.global.Defaults) do if bg[n] == k then bg[n] = nil end end -- remove default settings for layout, fonts and textures
			for n, k in pairs(MOD.BarGroupTemplate) do if bg[n] == k then bg[n] = nil end end -- remove defaults from the bar group template
			for n in pairs(colorTemplate) do if DefaultColor(bg[n]) then bg[n] = nil end end -- detect basic colors set to defaults
		else
			MOD.db.profile.BarGroups[bn] = nil -- okay to delete these since no default bar groups
		end
	end
end

-- Raven is disabled so hide all features
function MOD:HideBars()
	if not hidden then
		for _, bp in pairs(MOD.db.profile.BarGroups) do
			if IsOn(bp) then MOD:ReleaseBarGroup(bp) end
		end
		hidden = true
	end
end

-- Initialize bar group settings by adding default values if necessary
function MOD:InitializeSettings()
	for n, k in pairs(MOD.BarGroupTemplate) do settingsTemplate[n] = k end -- initialize the settings template from bar group defaults
	for n, k in pairs(MOD.db.global.Defaults) do settingsTemplate[n] = k end -- add default settings for layout-fonts-textures
	settingsTemplate.enabled = nil; settingsTemplate.locked = nil; settingsTemplate.merged = nil; settingsTemplate.linkSettings = nil; settingsTemplate.linkBars = nil
	for _, settings in pairs(MOD.db.global.Settings) do
		for n, k in pairs(settingsTemplate) do if settings[n] == nil then settings[n] = k end end -- add missing defaults from settings template
		for n in pairs(colorTemplate) do if settings[n] == nil then settings[n] = MOD.CopyColor(wc) end end -- default basic colors
	end
end

-- Remove default values from bar group settings
function MOD:FinalizeSettings()
	for _, settings in pairs(MOD.db.global.Settings) do
		for n, k in pairs(settingsTemplate) do if settings[n] == k then settings[n] = nil end end -- remove values still set to defaults
		for n in pairs(colorTemplate) do if DefaultColor(settings[n]) then settings[n] = nil end end -- detect basic colors set to defaults
	end
end

-- Show tooltip when entering a bar group anchor
local function Anchor_OnEnter(anchor, bgName)
	if GetCVar("UberTooltips") == "1" then
		GameTooltip_SetDefaultAnchor(GameTooltip, anchor)
	else
		GameTooltip:SetOwner(anchor, "ANCHOR_BOTTOMLEFT")
	end
	local bg, bgType, attachment = MOD.Nest_GetBarGroup(bgName), L["Custom Bar Group"], nil
	if bg then
		if MOD.Nest_GetBarGroupAttribute(bg, "isAuto") then bgType = L["Auto Bar Group"] end
		attachment = MOD.Nest_GetBarGroupAttribute(bg, "attachment")
	end
	GameTooltip:AddDoubleLine("Raven", bgType)
	if attachment then
		GameTooltip:AddLine(L["Anchor attached"] .. attachment .. '"')
		GameTooltip:AddLine(L["Anchor left click 1"])
	else
		GameTooltip:AddLine(L["Anchor left click 2"])
	end
	GameTooltip:AddLine(L["Anchor right click"])
	GameTooltip:AddLine(L["Anchor shift left click"])
	GameTooltip:AddLine(L["Anchor shift right click"])
	GameTooltip:AddLine(L["Anchor alt left click"])
	GameTooltip:AddLine(L["Anchor alt right click"])
	GameTooltip:Show()
end

-- Hide tooltip when leaving a bar group anchor
local function Anchor_OnLeave(anchor, bgName)
	GameTooltip:Hide()
end

-- Callback function for tracking location of the bar group
local function Anchor_Moved(anchor, bgName)
	local bp = MOD.db.profile.BarGroups[bgName]
	if IsOn(bp) then
		local bg = MOD.Nest_GetBarGroup(bgName)
		if bg then
			bp.pointX, bp.pointXR, bp.pointY, bp.pointYT, bp.pointW, bp.pointH = MOD.Nest_GetAnchorPoint(bg) -- returns fractions from display edge
			if bp.anchor then bp.anchor = false end -- no longer anchored to other bar groups
			if bp.linkSettings then
				local settings = MOD.db.global.Settings[bp.name] -- when updating a bar group with linked settings always overwrite position
				if settings then
					settings.pointX = bp.pointX; settings.pointXR = bp.pointXR; settings.pointY = bp.pointY; settings.pointYT = bp.pointYT
					settings.pointW = bp.pointW; settings.pointH = bp.pointH; settings.anchor = bp.anchor
				end
			end
			Anchor_OnLeave(anchor) -- turn off tooltip while moving the anchor
			MOD.updateOptions = true -- if options panel is open then update it in case viewing position info
		end
		return
	end
end

-- Callback function for when a bar group anchor is clicked with a modifier key down
-- Shift left click is test bars, right click is "toggle lock and hide",
local function Anchor_Clicked(anchor, bgName, button)
	local shiftLeftClick = (button == "LeftButton") and IsShiftKeyDown()
	local shiftRightClick = (button == "RightButton") and IsShiftKeyDown()
	local altLeftClick = (button == "LeftButton") and IsAltKeyDown()
	local altRightClick = (button == "RightButton") and IsAltKeyDown()
	local rightClick = (button == "RightButton")

	local bp = MOD.db.profile.BarGroups[bgName]
	if IsOn(bp) then
		if shiftLeftClick then -- test bars
			MOD:TestBarGroup(bp)
		elseif shiftRightClick then -- toggle grow up/down
			bp.growDirection = not bp.growDirection
		elseif altLeftClick then -- toggle options menu
			MOD:OptionsPanel()
		elseif altRightClick then -- cycle through configurations
			if bp.configuration > MOD.Nest_MaxBarConfiguration then -- special case order for cycling icon configurations
				local c, i = bp.configuration, MOD.Nest_MaxBarConfiguration + 1
				if c == i then c = i + 2 elseif c == (i + 1) then c = i + 3 elseif c == (i + 2) then c = i + 1 elseif c == (i + 3) then c = i
				elseif c == (i + 4) then c = i + 5 elseif c == (i + 5) then c = i + 4 end
				bp.configuration = c
			else
				bp.configuration = bp.configuration + 1
				if bp.configuration == (MOD.Nest_MaxBarConfiguration + 1) then bp.configuration = 1 end
			end
		elseif rightClick then -- lock and hide
			bp.locked = true
		end
		MOD:UpdateBarGroup(bp)
		MOD.updateOptions = true -- if options panel is open then update it in case viewing configuration info
		MOD:ForceUpdate()
		return
	end
end

-- Update linked settings. If dir is true then update the shared settings, otherwise update the bar group.
-- Also, if dir is true, create a linked settings table if one doesn't yet exist.
local function UpdateLinkedSettings(bp, dir)
	local settings = MOD.db.global.Settings[bp.name]
	if not settings then
		if not dir then return end
		settings = {}
		MOD.db.global.Settings[bp.name] = settings
	end
	local p, q = settings, bp
	if dir then p = q; q = settings end
	for n in pairs(settingsTemplate) do q[n] = p[n] end -- copy every setting in the template
	q.pointX = p.pointX; q.pointXR = p.pointXR; q.pointY = p.pointY; q.pointYT = p.pointYT -- always copy the location
	q.pointW = p.pointW; q.pointH = p.pointH
	if p.fgColor then q.fgColor = MOD.CopyColor(p.fgColor) else q.fgColor = nil end -- foreground and background custom colors must be hand copied
	if p.bgColor then q.bgColor = MOD.CopyColor(p.bgColor) else q.bgColor = nil end
	if p.iconBorderColor then q.iconBorderColor = MOD.CopyColor(p.iconBorderColor) else q.iconBorderColor = nil end
end

-- Update linked custom bars. If dir is true then update the shared bars, otherwise update the ones in the bar group.
-- Also, if dir is true, create a linked custom bars table if one doesn't yet exist.
local function UpdateLinkedBars(bp, dir)
	if bp.auto then return end -- only applies to custom bar groups
	local customBars = MOD.db.global.CustomBars[bp.name]
	if not customBars then
		if not dir then return end
		customBars = {}
		MOD.db.global.CustomBars[bp.name] = customBars
	end
	local p, q = customBars, bp.bars
	if dir then p = q; q = customBars end
	table.wipe(q) -- remove old bars from destination
	for k, b in pairs(p) do q[k] = MOD.CopyTable(b) end -- deep copy each bar in the source
end

-- Update a linked filter list. If dir is true then update the shared list, otherwise update the bar group's list.
-- Also, if dir is true, create a linked filter list if one doesn't yet exist.
local function UpdateLinkedFilter(bp, dir, filterType)
	local shared = MOD.db.global["Filter" .. filterType]
	local bgname = "filter" ..  filterType .. "List"

	if not shared[bp.name] then
		if not dir or not bp[bgname] or not next(bp[bgname], nil) then return end
		shared[bp.name] = {}
	end

	if not bp[bgname] then bp[bgname] = {} end

	local p, q = shared[bp.name], bp[bgname]
	if dir then p = bp[bgname]; q = shared[bp.name] end

	for _, v in pairs(q) do if not p[v] then q[v] = nil end end -- delete any keys in q not in p
	for _, v in pairs(p) do if not q[v] then q[v] = v end end -- copy everything from p to q
end

-- Initialize a bar group from a shared filter list, if any.
-- This function is called whenever filterLink is changed.
function MOD:InitializeFilterList(bp, filterType)
	if bp and bp["filter" .. filterType] and bp["filter" .. filterType .. "Link"] then
		UpdateLinkedFilter(bp, false, filterType) -- use the shared settings, if any, for a linked layout
	end
end

-- Get spell associated with a bar
function MOD:GetAssociatedSpellForBar(bar)
	local bt = bar.barType
	if bt == "Notification" then
		local sp = bar.notifySpell
		if not sp and not bar.unconditional and bar.action then sp = MOD:GetConditionSpell(bar.action) end
		return sp
	elseif bt == "Value" then
		return bar.spell
	end
	return bar.action
end

-- Get icon for the spell associated with a bar, returns nil if none found
function MOD:GetIconForBar(bar)
	local sp = MOD:GetAssociatedSpellForBar(bar)
	if sp then return MOD:GetIcon(sp) end
	return nil
end

-- Get color for the spell associated with a bar, returns nil if none found
function MOD:GetSpellColorForBar(bar)
	local c = bar.color -- get override if one is set
	local spc = nil
	local sp = MOD:GetAssociatedSpellForBar(bar)
	if sp then spc = MOD:GetColor(sp, bar.spellID) end -- associated spell's color, if any

	if bar.barType == "Notification" then -- special case for notifications which can use an associated spell color
		if bar.notColor then return c end -- not allowed to get color from associated spell
		return spc or c -- prefer the associated spell color instead of the override color
	end
	return c or spc -- all other bar types only use color from associated spell if no override is set
end

-- Set the bar's current spell color using an override if not linked (note bar.colorLink uses inverted value from expected)
function MOD:SetSpellColorForBar(bar, r, g, b, a)
	local c = bar.color -- check if using an override
	if c then c.r = r; c.g = g; c.b = b; c.a = a; return end
	local bt = bar.barType
	local typeCheck = (bt == "Buff") or (bt == "Debuff") or (bt == "Cooldown")
	if typeCheck and not bar.colorLink then -- set the shared color for bars with the same associated spell
		local sp = MOD:GetAssociatedSpellForBar(bar)
		if sp then c = MOD:GetColor(sp, bar.spellID) end
		if c then c.r = r; c.g = g; c.b = b; c.a = a; return end
		c = { r = r, g = g, b = b, a = a }
		if sp then MOD:SetColor(sp, c) else bar.color = c end
	else
		bar.color = { r = r, g = g, b = b, a = a } -- create an override
	end
end

-- Reset the bar's override color
function MOD:ResetSpellColorForBar(bar)
	bar.color = nil
	local bt = bar.barType
	local typeCheck = (bt == "Buff") or (bt == "Debuff") or (bt == "Cooldown")
	if typeCheck and not bar.colorLink then -- also reset the shared color for bars with the same associated spell
		local sp = MOD:GetAssociatedSpellForBar(bar)
		if sp then MOD:ResetColor(sp) end
	end
end

-- Either link or decouple the bar's color from the color cache for it's associated spell
function MOD:LinkSpellColorForBar(bar)
	local c = MOD:GetSpellColorForBar(bar)
	if not bar.colorLink then -- link to the color cache, copying current setting, if any, to the color cache
		if c and bar.color then local d = bar.color; c.r = d.r; c.g = d.g; c.b = d.b; c.a = d.a end
		bar.color = nil -- delete override to revert back to color cache or default for bar type
	else -- decouple from the color cached, copying current setting, if any, to a new override
		if c then bar.color = { r = c.r, g = c.g, b = c.b, a = c.a } end
	end
end

-- Get the right color for the bar based on bar group settings
local function GetColorForBar(bg, bar, btype)
	local bt, c = bar.barType, nil
	local scheme = bg.barColors
	if scheme == "Spell" then
		c = MOD:GetSpellColorForBar(bar)
	elseif scheme == "Class" then
		c = MOD.ClassColors[MOD.myClass] or wc
	elseif scheme == "Custom" then
		c = bg.fgColor or wc
	end
	if not c then -- get the best default color for this bar type
		local cc = not bg.useDefaultColors -- indicates the bar group has overrides for standard colors
		c = cc and bg.buffColor or MOD.db.global.DefaultBuffColor -- use this as default in case unrecognized bar type
		if bt == "Debuff" then
			c = cc and bg.debuffColor or MOD.db.global.DefaultDebuffColor
			if btype then
				if btype == "Poison" then c = cc and bg.poisonColor or MOD.db.global.DefaultPoisonColor end
				if btype == "Curse" then c = cc and bg.curseColor or MOD.db.global.DefaultCurseColor end
				if btype == "Magic" then c = cc and bg.magicColor or MOD.db.global.DefaultMagicColor end
				if btype == "Disease" then c = cc and bg.diseaseColor or MOD.db.global.DefaultDiseaseColor end
			end
		end
		if bt == "Cooldown" then c = cc and bg.cooldownColor or MOD.db.global.DefaultCooldownColor end
		if bt == "Notification" then c = cc and bg.notificationColor or MOD.db.global.DefaultNotificationColor end
		if bt == "Broker" then c = cc and bg.brokerColor or MOD.db.global.DefaultBrokerColor end
		if bt == "Value" then c = cc and bg.valueColor or MOD.db.global.DefaultValueColor end
	end
	c.a = 1 -- always set alpha to 1 for bar colors
	return c
end

-- Get the special debuff color for the bar
function MOD:GetSpecialColorForBar(bg, bar, btype)
	local cc = not bg.useDefaultColors -- indicates the bar group has overrides for standard colors
	local c = MOD.db.global.DefaultBorderColor -- no color applied if not a special type
	local bt = bar.barType
	if bt == "Debuff" then
		if btype == "Poison" then
			c = cc and bg.poisonColor or MOD.db.global.DefaultPoisonColor
		elseif btype == "Curse" then
			c = cc and bg.curseColor or MOD.db.global.DefaultCurseColor
		elseif btype == "Magic" then
			c = cc and bg.magicColor or MOD.db.global.DefaultMagicColor
		elseif btype == "Disease" then
			c = cc and bg.diseaseColor or MOD.db.global.DefaultDiseaseColor
		else
			c = cc and bg.debuffColor or MOD.db.global.DefaultDebuffColor
		end
	elseif bt == "Buff" then
		if bar.isStealable then
			c = cc and bg.stealColor or MOD.db.global.DefaultStealColor
		elseif bar.isMagic then
			c = cc and bg.magicColor or MOD.db.global.DefaultMagicColor
		elseif bar.isEnrage then
			c = cc and bg.enrageColor or MOD.db.global.DefaultEnrageColor
		else
			c = cc and bg.buffColor or MOD.db.global.DefaultBuffColor
		end
	end
	return c
end

-- Initialize bar group in graphics library and set default values from those set in profile
function MOD:InitializeBarGroup(bp, offsetX, offsetY)
	local bg = MOD.Nest_GetBarGroup(bp.name)
	if not bg then bg = MOD.Nest_CreateBarGroup(bp.name) end
	if bp.linkSettings then UpdateLinkedSettings(bp, false) end
	if bp.linkBars then UpdateLinkedBars(bp, false) end
	if bp.sor == "C" then bp.sor = "A" end -- fix out-dated sort setting
	if bp.auto then -- initialize the auto bar group filter lists
		if (bp.filterBuff or bp.showBuff) and bp.filterBuffLink then UpdateLinkedFilter(bp, false, "Buff") end -- shared settings for buffs
		if (bp.filterDebuff or bp.showDebuff) and bp.filterDebuffLink then UpdateLinkedFilter(bp, false, "Debuff") end -- shared settings for debuffs
		if (bp.filterCooldown or bp.showCooldown) and bp.filterCooldownLink then UpdateLinkedFilter(bp, false, "Cooldown") end -- shared settings for cooldowns
	end
	if not bp.pointX or not bp.pointY then bp.pointX = 0.5 + (offsetX / 600); bp.pointXR = nil; bp.pointY = 0.5 + (offsetY / 600); bp.pointYT = nil end
	if not bp.pointW or not bp.pointH then bp.pointW = MOD.db.global.Defaults.barWidth; bp.pointH = MOD.db.global.Defaults.barHeight end
	MOD:SetBarGroupPosition(bp)
	MOD.Nest_SetBarGroupCallbacks(bg, Anchor_Moved, Anchor_Clicked, Anchor_OnEnter, Anchor_OnLeave)
end

-- Initialize a bar group from linked settings, if any, and always update the bar group location.
-- This function is called whenever linkSettings is changed.
function MOD:InitializeBarGroupSettings(bp)
	if bp and bp.enabled then
		if bp.linkSettings then UpdateLinkedSettings(bp, false) end
		if bp.linkBars then UpdateLinkedBars(bp, false) end
		MOD:SetBarGroupPosition(bp)
	end
end

-- Load bar group settings from the linked settings.
function MOD:LoadBarGroupSettings(bp) UpdateLinkedSettings(bp, false) end

-- Save bar group settings into the linked settings.
function MOD:SaveBarGroupSettings(bp) UpdateLinkedSettings(bp, true) end

-- Load bar group settings from the linked settings.
function MOD:LoadCustomBars(bp) UpdateLinkedBars(bp, false) end

-- Save bar group settings into the linked settings.
function MOD:SaveCustomBars(bp) UpdateLinkedBars(bp, true) end

-- Validate and update a bar group's display position. If linked, also update the position in the linked settings.
function MOD:SetBarGroupPosition(bp)
	local scale = bp.useDefaultDimensions and MOD.db.global.Defaults.scale or bp.scale or 1
	local bg = MOD.Nest_GetBarGroup(bp.name)
	if bg then MOD.Nest_SetAnchorPoint(bg, bp.pointX, bp.pointXR, bp.pointY, bp.pointYT, scale, bp.pointW, bp.pointH) end
	if bp.linkSettings then
		local settings = MOD.db.global.Settings[bp.name] -- when updating a bar group with linked settings always overwrite position
		if settings then
			settings.pointX = bp.pointX; settings.pointXR = bp.pointXR; settings.pointY = bp.pointY; settings.pointYT = bp.pointYT
			settings.pointW = bp.pointW; settings.pointH = bp.pointH
		end
	end
end

-- Set an entry in a bar group cache block
local function SetCache(bg, block, name, value)
	if not bg.cache then bg.cache = {} end
	if not bg.cache.block then bg.cache.block = {} end
	bg.cache.block[name] = value
end

-- Get a value from a bar group cache block
local function GetCache(bg, block, name)
	if not bg.cache or not bg.cache.block then return nil end
	return bg.cache.block[name]
end

-- Reset a bar group cache block
local function ResetCache(bg, block)
	if bg.cache and bg.cache.block then table.wipe(bg.cache.block) end
end

-- Update a bar group with the current values in the profile
function MOD:UpdateBarGroup(bp)
	if bp.enabled then
		if bp.linkSettings then UpdateLinkedSettings(bp, true) end -- update shared settings in a linked bar group
		if bp.linkBars then UpdateLinkedBars(bp, true) end -- update shared settings in a linked bar group
		if bp.auto then -- update auto bar group filter lists
			if (bp.filterBuff or bp.showBuff) and bp.filterBuffLink then UpdateLinkedFilter(bp, true, "Buff") end -- shared settings for buffs
			if (bp.filterDebuff or bp.showDebuff) and bp.filterDebuffLink then UpdateLinkedFilter(bp, true, "Debuff") end -- shared settings for debuffs
			if (bp.filterCooldown or bp.showCooldown) and bp.filterCooldownLink then UpdateLinkedFilter(bp, true, "Cooldown") end -- shared settings for buffs
		end
		ResetCache(bp, "Buff"); ResetCache(bp, "Debuff"); ResetCache(bp, "Cooldown")
		if bp.bars then -- create caches for buff, debuff, cooldown actions
			for _, b in pairs(bp.bars) do
				local ba = b.action
				if ba then
					local bt = b.barType
					if (bt == "Buff") or (bt == "Debuff") then
						SetCache(bp, bt, ba, b.monitor)
					elseif bt == "Cooldown" then
						SetCache(bp, bt, ba, true)
					elseif bt == "Broker" then
						MOD:ActivateDataBroker(ba)
					end
				end
			end
		end

		local bg = MOD.Nest_GetBarGroup(bp.name)
		if not bg then MOD:InitializeBarGroup(bp); bg = MOD.Nest_GetBarGroup(bp.name) end

		if bp.useDefaultTimeFormat then MOD:CopyTimeFormat(MOD.db.global.Defaults, bp) end
		if bp.useDefaultDimensions then MOD:CopyDimensions(MOD.db.global.Defaults, bp) end
		if bp.useDefaultFontsAndTextures then MOD:CopyFontsAndTextures(MOD.db.global.Defaults, bp) end
		local panelTexture = bp.backdropEnable and media:Fetch("background", bp.backdropPanel) or nil
		local backdropTexture = (bp.backdropTexture ~= "None") and media:Fetch("border", bp.backdropTexture) or nil
		local borderTexture = (bp.borderTexture ~= "None") and media:Fetch("border", bp.borderTexture) or nil
		local fgtexture = media:Fetch("statusbar", bp.texture)
		local bgtexture = fgtexture
		if bp.bgtexture then bgtexture = media:Fetch("statusbar", bp.bgtexture) end
		MOD.Nest_SetBarGroupLock(bg, bp.locked)
		MOD.Nest_SetBarGroupAttribute(bg, "parentFrame", bp.parentFrame)
		MOD.Nest_SetBarGroupLabelFont(bg, media:Fetch("font", bp.labelFont), bp.labelFSize, bp.labelAlpha, bp.labelColor,
				bp.labelOutline, bp.labelShadow, bp.labelThick, bp.labelMono, bp.labelSpecial)
		MOD.Nest_SetBarGroupTimeFont(bg, media:Fetch("font", bp.timeFont), bp.timeFSize, bp.timeAlpha, bp.timeColor,
				bp.timeOutline, bp.timeShadow, bp.timeThick, bp.timeMono, bp.timeSpecial)
		MOD.Nest_SetBarGroupIconFont(bg, media:Fetch("font", bp.iconFont), bp.iconFSize, bp.iconAlpha, bp.iconColor,
				bp.iconOutline, bp.iconShadow, bp.iconThick, bp.iconMono, bp.iconSpecial)
		MOD.Nest_SetBarGroupBarLayout(bg, bp.barWidth, bp.barHeight, bp.iconSize, bp.scale, bp.spacingX, bp.spacingY,
				bp.iconOffsetX, bp.iconOffsetY, bp.labelOffset, bp.labelInset, bp.labelWrap, bp.labelAlign, bp.labelCenter, bp.labelAdjust, bp.labelAuto, bp.labelWidth,
				bp.timeOffset, bp.timeInset, bp.timeAlign, bp.timeIcon, bp.iconOffset, bp.iconInset, bp.iconHide, bp.iconAlign,
				bp.configuration, bp.growDirection, bp.wrap, bp.wrapDirection, bp.snapCenter, bp.fillBars, bp.maxBars, bp.strata)
		MOD.Nest_SetBarGroupBackdrop(bg, panelTexture, backdropTexture, bp.backdropWidth, bp.backdropInset, bp.backdropPadding, bp.backdropColor, bp.backdropFill,
				bp.backdropOffsetX, bp.backdropOffsetY, bp.backdropPadW, bp.backdropPadH)
		MOD.Nest_SetBarGroupBorder(bg, borderTexture, bp.borderWidth, bp.borderOffset, bp.borderColor)
		MOD.Nest_SetBarGroupTextures(bg, fgtexture, bp.fgAlpha, bgtexture, bp.bgAlpha, not bp.showNoDurationBackground,
				bp.fgSaturation, bp.fgBrightness, bp.bgSaturation, bp.bgBrightness)
		MOD.Nest_SetBarGroupVisibles(bg, not bp.hideIcon, not bp.hideClock, not bp.hideBar, not bp.hideSpark, not bp.hideLabel, not bp.hideValue)
		if bp.timelineTexture then bgtexture = media:Fetch("statusbar", bp.timelineTexture) else bgtexture = nil end
		if bp.timelineBorderTexture then fgtexture = (bp.timelineBorderTexture ~= "None") and media:Fetch("border", bp.timelineBorderTexture) or nil end
		MOD.Nest_SetBarGroupTimeline(bg, bp.timelineWidth, bp.timelineHeight, bp.timelineDuration, bp.timelineExp, bp.timelineHide, bp.timelineAlternate,
				bp.timelineSwitch, bp.timelinePercent, bp.timelineSplash, bp.timelineSplashX, bp.timelineSplashY, bp.timelineOffset, bp.timelineDelta,
				bgtexture, bp.timelineAlpha, bp.timelineColor or gc, bp.timelineLabels or defaultLabels,
				fgtexture, bp.timelineBorderWidth, bp.timelineBorderOffset, bp.timelineBorderColor or gc)
		MOD.Nest_SetBarGroupAttribute(bg, "targetFirst", bp.targetFirst) -- for multi-target tracking, sort target first
		MOD.Nest_SetBarGroupAttribute(bg, "noMouse", bp.noMouse) -- disable interactivity
		MOD.Nest_SetBarGroupAttribute(bg, "iconMouse", bp.iconMouse) -- mouse-only interactivity
		MOD.Nest_SetBarGroupAttribute(bg, "anchorTips", bp.anchorTips) -- manual tooltip anchor
		MOD.Nest_SetBarGroupAttribute(bg, "isAuto", bp.auto) -- save for tooltip
		MOD.Nest_SetBarGroupAttribute(bg, "attachment", bp.anchor) -- save for tooltip
		MOD.Nest_SetBarGroupAttribute(bg, "clockReverse", bp.clockReverse) -- save for clock animations
		MOD.Nest_SetBarGroupTimeFormat(bg, bp.timeFormat, bp.timeSpaces, bp.timeCase)
		MOD.Nest_SetBarGroupAttribute(bg, "headerGaps", bp.headerGaps and bp.noHeaders) -- convert headers into spaces for tracker bar groups
		local sf = "alpha"
		if bp.sor == "T" then sf = "time" elseif bp.sor == "D" then sf = "duration" elseif bp.sor == "S" then sf = "start" end
		MOD.Nest_BarGroupSortFunction(bg, sf, bp.reverseSort, bp.timeSort, bp.playerSort)
		MOD.Nest_SetBarGroupAttribute(bg, "noDurationFirst", bp.noDurationFirst) -- controls in no duration sorts first or last
		if bp.segmentBars then
			MOD.Nest_SetBarGroupSegments(bg, bp.segmentCount, bp.segmentOverride, bp.segmentSpacing, bp.segmentHideEmpty, bp.segmentFadePartial, bp.segmentShrinkWidth,
					bp.segmentShrinkHeight, bp.segmentGradient, bp.segmentGradientAll, bp.segmentGradientStartColor, bp.segmentGradientEndColor, bp.segmentBorderColor,
					bp.segmentAdvanced, bp.segmentCurve, bp.segmentRotate, bp.segmentTexture)
		else
			MOD.Nest_SetBarGroupSegments(bg, nil) -- segmentCount must be set for segments to be displayed so this disables them
		end
	else
		MOD:ReleaseBarGroup(bp)
	end
end

-- Setup graphics library to show a horizontal stripe
local function ShowStripe(bp, bg)
	local bgtexture = nil
	if bp.stripeTexture then bgtexture = media:Fetch("statusbar", bp.stripeTexture) end
	local sc = bp.stripeColor or gc
	if bp.stripeCheckCondition and bp.stripeCondition and MOD:CheckCondition(bp.stripeCondition) then sc = bp.stripeAltColor end
	local borderTexture = (bp.stripeBorderTexture ~= "None") and media:Fetch("border", bp.stripeBorderTexture) or nil
	MOD.Nest_SetBarGroupStripe(bg, bp.stripeFullWidth, bp.stripeWidth, bp.stripeHeight, bp.stripeInset, bp.stripeOffset,
			bp.stripeBarInset, bp.stripeBarOffset, bgtexture, sc, borderTexture, bp.stripeBorderWidth, bp.stripeBorderOffset, bp.stripeBorderColor or gc)
end

-- Update the positions of all anchored bar groups plus make sure valid positions in all bar groups
function MOD:UpdatePositions()
	for _, bp in pairs(MOD.db.profile.BarGroups) do -- update bar group positions including relative ones if anchored
		if IsOn(bp) then
			local bg = MOD.Nest_GetBarGroup(bp.name)
			if bg and bg.configuration then -- make sure already configured
				if not bp.pointX or not bp.pointY then -- if not valid then move to center
					bp.pointX = 0.5; bp.pointXR = nil; bp.pointY = 0.5; bp.pointYT = nil
					MOD.Nest_SetAnchorPoint(bg, bp.pointX, bp.pointXR, bp.pointY, bp.pointYT, bp.scale or 1, nil, nil)
				end
				if bp.anchorFrame then
					MOD.Nest_SetRelativeAnchorPoint(bg, nil, bp.anchorFrame, bp.anchorPoint, bp.anchorX, bp.anchorY)
				elseif bp.anchor then
					local abp = MOD.db.profile.BarGroups[bp.anchor]
					if IsOn(abp) and abp.enabled then -- make sure the anchor is actually around to attach
						MOD.Nest_SetRelativeAnchorPoint(bg, bp.anchor, nil, nil, bp.anchorX, bp.anchorY, bp.anchorLastBar, bp.anchorEmpty, bp.anchorRow, bp.anchorColumn)
					end
				else
					MOD.Nest_SetRelativeAnchorPoint(bg, nil) -- reset the relative anchor point if none set
				end
				bp.pointX, bp.pointXR, bp.pointY, bp.pointYT, bp.pointW, bp.pointH = MOD.Nest_GetAnchorPoint(bg) -- returns fractions from display edge
			end
		end
	end
end

-- Update all the bar groups, this is necessary when changing stuff that can affect bars in multiple groups (e.g., buff colors and labels)
function MOD:UpdateAllBarGroups()
	MOD:UpdateConditions() -- update in case these affect any bar groups and also to update option panel correctly when changing condition settings
	for _, bp in pairs(MOD.db.profile.BarGroups) do -- update for changed bar group settings
		if IsOn(bp) then MOD:UpdateBarGroup(bp) end
	end
	MOD:ForceUpdate() -- this forces an immediate update of bar group display
end

-- Lock or unlock all bar groups
function MOD:LockBarGroups(lock)
	for _, bp in pairs(MOD.db.profile.BarGroups) do if IsOn(bp) then bp.locked = lock end end
	MOD:UpdateAllBarGroups()
end

-- Toggle test mode for all bar groups
function MOD:TestBarGroups(lock)
	for _, bp in pairs(MOD.db.profile.BarGroups) do if IsOn(bp) then MOD:TestBarGroup(bp) end end
	MOD:UpdateAllBarGroups()
end

-- Toggle locking of bar groups
function MOD:ToggleBarGroupLocks()
	-- Look in the profile table to determine current state
	local anyLocked = false
	for _, bp in pairs(MOD.db.profile.BarGroups) do
		if IsOn(bp) and bp.locked then anyLocked = true break end
	end
	-- Now go back through and set all to same state (if any locked then unlock all)
	MOD:LockBarGroups(not anyLocked)
end

-- Release all the bars in the named bar group in the graphics library
function MOD:ReleaseBarGroup(bp)
	if bp then
		local bg = MOD.Nest_GetBarGroup(bp.name)
		if bg then MOD.Nest_DeleteBarGroup(bg) end
	end
end

-- Update a tooltip for a bar
local function Bar_OnUpdate(bar)
	local bat = bar.attributes
	local id = bat.tooltipID
	local unit = bat.tooltipUnit
	local spell = bat.tooltipSpell
	local caster = bat.caster
	local tt = bat.tooltipType
	if not tt then return end -- tooltipType set to nil suppresses tooltips

	GameTooltip:ClearLines() -- clear current tooltip contents
	-- MOD.Debug("tt", tt, id, unit, spell, caster)
	if tt == "text" then
		GameTooltip:SetText(tostring(id))
	elseif (tt == "inventory") then
		if id then GameTooltip:SetInventoryItem("player", id) end
	elseif (tt == "weapon") then
		local slotid = id
		if slotid == "MainHandSlot" then slotid = 16 end
		if slotid == "SecondaryHandSlot" then slotid = 17 end
		if slotid == "RangedSlot" then slotid = 18 end
		if (slotid == 16) or (slotid == 17) or (slotid == 18) then GameTooltip:SetInventoryItem("player", slotid) end
	elseif (tt == "spell id") or (tt == "internal") or (tt == "alert") then
		GameTooltip:SetSpellByID(id)
	elseif (tt == "item id") then
		GameTooltip:SetItemByID(id)
	elseif tt == "effect" then
		local ect = MOD.db.global.SpellEffects[id]
		if ect and ect.id then GameTooltip:SetSpellByID(ect.id) else GameTooltip:SetText(id) end
	elseif tt == "buff" then
		GameTooltip:SetUnitAura(unit, id, "HELPFUL")
	elseif tt == "debuff" then
		GameTooltip:SetUnitAura(unit, id, "HARMFUL")
	elseif tt == "vehicle buff" then
		GameTooltip:SetUnitAura("vehicle", id, "HELPFUL")
	elseif tt == "vehicle debuff" then
		GameTooltip:SetUnitAura("vehicle", id, "HARMFUL")
	elseif tt == "tracking" then
		GameTooltip:SetText(tostring(id)) -- id is localized name of tracking type
	elseif tt == "spell" then
		GameTooltip:SetText(tostring(id))
	elseif tt == "totem" then
		GameTooltip:SetTotem(id)
	elseif tt == "minion" then
		GameTooltip:SetText(tostring(bar.label))
	elseif tt == "notification" then
		GameTooltip:AddDoubleLine(id, "Notification")
		local ct = MOD.db.profile.Conditions[MOD.myClass]
		if ct then
			local c = ct[unit]
			if IsOn(c) and c.tooltip then GameTooltip:AddLine(MOD:GetConditionText(c.name), 1, 1, 1, true) end
		end
	elseif tt == "lines" then
		if type(id) == "table" then for k, v in ipairs(id) do GameTooltip:AddLine(v) end end
	elseif tt == "header" then
		GameTooltip:AddLine(id)
		GameTooltip:AddLine(L["Header click"], 1, 1, 1, true)
		GameTooltip:AddLine(L["Header shift click"], 1, 1, 1, true)
	elseif tt == "test" then
		if id == "timer" then
			GameTooltip:SetText(L["Timer Bar"] .. " " .. tostring(unit))
		else
			GameTooltip:SetText(L["Test Bar"] .. " " .. tostring(unit))
		end
	end
	if IsControlKeyDown() then
		if spell then GameTooltip:AddLine("<Spell #" .. tonumber(spell) .. ">", 0, 1, 0.2, false) end
		if bat.listID then GameTooltip:AddLine("<List #" .. tonumber(bat.listID) .. ">", 0, 1, 0.2, false) end
	end
	if caster and (caster ~= "") then GameTooltip:AddLine(L["<Applied by "] .. caster .. ">", 0, 0.8, 1, false) end
	GameTooltip:Show()
end
MOD.Bar_OnUpdate = Bar_OnUpdate -- saved for tooltip updating

-- Anchor the tooltip appropriately
local function Bar_AnchorTooltip(frame, tooltip, ttanchor)
	if not ttanchor then
		tooltip:ClearAllPoints()
		if type(tooltip.SetOwner) == "function" then tooltip:SetOwner(frame, "ANCHOR_NONE") end
		local _, fy = frame:GetCenter()
		local _, sy = UIParent:GetCenter()
		local frameAnchor, tooltipAnchor
		if sy > fy then frameAnchor = "TOP"; tooltipAnchor = "BOTTOM" else frameAnchor = "BOTTOM"; tooltipAnchor = "TOP" end
		tooltip:SetPoint(tooltipAnchor, frame, frameAnchor)
	elseif (ttanchor == "DEFAULT") and (GetCVar("UberTooltips") == "1") then
		GameTooltip_SetDefaultAnchor(tooltip, frame)
	else
		if not ttanchor or (ttanchor == "DEFAULT") then ttanchor = "ANCHOR_BOTTOMLEFT" else ttanchor = "ANCHOR_" .. ttanchor end
		tooltip:SetOwner(frame, ttanchor)
	end
end

-- Show tooltip when entering a bar
local function Bar_OnEnter(frame, bgName, barName, ttanchor)
	local bg = MOD.Nest_GetBarGroup(bgName)
	if not bg then return end
	local bar = MOD.Nest_GetBar(bg, barName)
	if not bar then return end
	local bat = bar.attributes
	local db = bat.tooltipID
	local tt = bat.tooltipType
	if not tt then return end -- tooltipType set to nil suppresses tooltips

	if tt == "broker" then
		if type(db) == "table" then
			if db.tooltip and type(db.tooltip) == "table" and type(db.tooltip.SetText) == "function" and type(db.tooltip.Show) == "function" then
				Bar_AnchorTooltip(frame, db.tooltip)
				if db.tooltiptext then db.tooltip:SetText(db.tooltiptext) end
				db.tooltip:Show()
			elseif type(db.OnTooltipShow) == "function" then
				Bar_AnchorTooltip(frame, GameTooltip)
				db.OnTooltipShow(GameTooltip)
				GameTooltip:Show()
			elseif db.tooltiptext then
				Bar_AnchorTooltip(frame, GameTooltip)
				GameTooltip:SetText(db.tooltiptext)
				GameTooltip:Show()
			elseif type(db.OnEnter) == "function" then
				db.OnEnter(frame)
			end
		end
	else
		Bar_AnchorTooltip(frame, GameTooltip, ttanchor)
		MOD.tooltipBar = bar
		Bar_OnUpdate(bar)
	end
end

-- Hide tooltip when leaving a bar
local function Bar_OnLeave(frame, bgName, barName, ttanchor)
	local bg = MOD.Nest_GetBarGroup(bgName)
	if not bg then return end
	local bar = MOD.Nest_GetBar(bg, barName)
	if not bar then return end
	local bat = bar.attributes
	local tt = bat.tooltipType
	local db = bat.tooltipID
	if tt == "broker" then
		if type(db) == "table" then
			if type(db.OnTooltipShow) == "function" then
				GameTooltip:Hide()
			end
			if type(db.OnLeave) == "function" then
				db.OnLeave(frame)
			elseif db.tooltip and type(db.tooltip) == "table" and type(db.tooltip.Hide) == "function" then
				db.tooltip:Hide()
			else
				GameTooltip:Hide()
			end
		end
	else
		MOD.tooltipBar = nil
		GameTooltip:Hide()
	end
end

-- Handle clicking on a bar for various purposes
local function Bar_OnClick(frame, bgName, barName, button)
	local bg = MOD.Nest_GetBarGroup(bgName)
	if not bg then return end
	local bar = MOD.Nest_GetBar(bg, barName)
	if not bar then return end
	local bat = bar.attributes
	local tt = bat.tooltipType
	local db = bat.tooltipID
	local unit = bat.tooltipUnit
	if (tt == "tracking") and (button == "LeftButton") and (unit == "player") then
		if GameTooltip:GetOwner() == frame then
			GameTooltip:Hide()
		end
		ToggleDropDownMenu(1, nil, MiniMapTrackingDropDown, frame, 0, 0)
	elseif (tt == "header") and (button == "RightButton") then
		if IsShiftKeyDown() then MOD:RemoveMatchingTrackers(unit) else MOD:RemoveTrackers(unit) end
	elseif (tt == "broker") then
		if type(db) == "table" and type(db.OnClick) == "function" then db.OnClick(frame, button) end
	end
end

-- Fire off test bars for this bar group, remove if any already exist
function MOD:TestBarGroup(bp)
	local bg = MOD.Nest_GetBarGroup(bp.name)
	if bg then
		local found = false
		local icon = defaultTestIcon
		local timers = bp.testTimers or 0; if timers == 0 then timers = 10 end
		local static = bp.testStatic or 0
		for i = 1, timers do
			local bar = MOD.Nest_GetBar(bg, ">>Timer<<" .. string.format("%02d", i))
			if bar then found = true; MOD.Nest_DeleteBar(bg, bar) end
		end
		for i = 1, static do
			local bar = MOD.Nest_GetBar(bg, ">>Test<<" .. string.format("%02d", i))
			if bar then found = true; MOD.Nest_DeleteBar(bg, bar) end
		end
		if not found then
			for i = 1, timers do
				local bar = MOD.Nest_CreateBar(bg, ">>Timer<<" .. string.format("%02d", i))
				if bar then
					local bat = bar.attributes
					local c = MOD.ColorPalette[testColors[(i % 10) + 1]]
					MOD.Nest_SetColors(bar, c.r, c.g, c.b, 1, c.r, c.g, c.b, 1, c.r, c.g, c.b, 1)
					MOD.Nest_SetLabel(bar, L["Timer Bar"] .. " " .. i); MOD.Nest_SetIcon(bar, icon); MOD.Nest_SetCount(bar, i)
					MOD.Nest_StartTimer(bar, i * 5, 60, 60)
					MOD.Nest_SetCallbacks(bar, nil, Bar_OnEnter, Bar_OnLeave)
					bat.tooltipType = "test"; bat.tooltipID = "timer"; bat.tooltipUnit = i
					bat.updated = true
				end
			end
			for i = 1, static do
				local bar = MOD.Nest_CreateBar(bg, ">>Test<<" .. string.format("%02d", i))
				if bar then
					local bat = bar.attributes
					local c = MOD.ColorPalette[testColors[(i % 10) + 1]]
					MOD.Nest_SetColors(bar, c.r, c.g, c.b, 1, c.r, c.g, c.b, 1, c.r, c.g, c.b, 1)
					MOD.Nest_SetLabel(bar, L["Test Bar"] .. " " .. i); MOD.Nest_SetIcon(bar, icon); MOD.Nest_SetCount(bar, i)
					MOD.Nest_SetCallbacks(bar, nil, Bar_OnEnter, Bar_OnLeave)
					bat.tooltipType = "test"; bat.tooltipID = "test"; bat.tooltipUnit = i
					bat.updated = true
				end
			end
		end
	end
end

-- Make sure not to delete any unexpired test bars
local function UpdateTestBars(bp, bg)
	local timers = bp.testTimers or 0; if timers == 0 then timers = 10 end
	local static = bp.testStatic or 0
	for i = 1, timers do
		local bar = MOD.Nest_GetBar(bg, ">>Timer<<" .. string.format("%02d", i))
		if bar then
			local timeLeft = MOD.Nest_GetTimes(bar)
			if timeLeft and (timeLeft > 0) then
				bar.attributes.updated = true
			elseif bp.testLoop then
				MOD.Nest_StartTimer(bar, i * 5, 60, 60)
				bar.attributes.updated = true
			end
		end
	end
	for i = 1, static do
		local bar = MOD.Nest_GetBar(bg, ">>Test<<" .. string.format("%02d", i))
		if bar then bar.attributes.updated = true end
	end
end

-- Return true if time and duration pass a bar group's filters
local function CheckTimeAndDuration(bp, timeLeft, duration)
	if (timeLeft == 0) and (duration == 0) then -- test for unlimited duration
		if not bp.showNoDuration then return false end
	else
		if bp.showNoDuration and bp.showOnlyNoDuration then return false end
		if bp.checkDuration and bp.filterDuration then
			if bp.minimumDuration then if duration < bp.filterDuration then return false end
			elseif duration >= bp.filterDuration then return false end
		end
		if bp.checkTimeLeft and bp.filterTimeLeft then
			if bp.minimumTimeLeft then if timeLeft < bp.filterTimeLeft then return false end
			elseif timeLeft >= bp.filterTimeLeft then return false end
		end
	end
	return true
end

local numberPatterns = { -- patterns for extracting up to 10 numbers from a string
	"(%d+%.?%d*)",
	"%d+%.?%d*%D+(%d+%.?%d*)",
	"%d+%.?%d*%D+%d+%.?%d*%D+(%d+%.?%d*)",
	"%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+(%d+%.?%d*)",
	"%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+(%d+%.?%d*)",
	"%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+(%d+%.?%d*)",
	"%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+(%d+%.?%d*)",
	"%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+(%d+%.?%d*)",
	"%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+(%d+%.?%d*)",
	"%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+%d+%.?%d*%D+(%d+%.?%d*)",
}

-- Remove color escape sequences from a string
local function uncolor(s)
	local t = string.gsub(s, "|c........", ""); t = string.gsub(t, "|r", "") -- remove color escape sequences from the text
	return t
end

-- Return a number found in a tooltip for auras and cooldowns
function MOD:GetTooltipNumber(ttType, ttID, ttUnit, ttOffset)
	if not ttOffset or ttOffset > #numberPatterns then ttOffset = 1 end -- determine offset into numberPatterns
	local tt = nil
	if ttType == "buff" then
		tt = C_TooltipInfo.GetUnitAura(ttUnit, ttID, "HELPFUL") -- fill in the tooltip for the buff
	elseif ttType == "debuff" then
		tt = C_TooltipInfo.GetUnitAura(ttUnit, ttID, "HARMFUL") -- fill in the tooltip for the debuff
	elseif (ttType == "spell id") or (ttType == "internal") or (ttType == "alert") then
		tt = C_TooltipInfo.GetSpellByID(ttID)
	elseif (tt == "item id") then
		tt = C_TooltipInfo.GetItemByID(ttID)
	elseif (ttType == "inventory") or (ttType == "weapon") then
		tt = C_TooltipInfo.GetInventoryItem("player", ttID)
	end
	if tt then
		local pattern = numberPatterns[ttOffset]
		local t = ""

		for i = 1, 30 do
			if tt.lines[i] and tt.lines[i].leftText then
				local s = tt.lines[i].leftText
				if s then t = t .. s else break end
			else
				break
			end
		end

		t = string.gsub(uncolor(t), ",", "") -- remove escape sequences and commas since they impact conversion of numbers

		return string.match(t, pattern) -- extract number from the tooltip, if one exists for the specified offset
	end

	return nil
end

-- Show combat text using either the MSBT addon or Blizzard's combat text
-- Other combat text addons may be added if they have a defined API
-- There is no support for Parrot and SCT since these no longer work in BfA
local function ShowCombatText(label, group, caption, icon, crit, ec)
	if MOD.suppress then return true end -- combat text is suppressed
	local t
	if group then t = string.format("%s [%s] %s", label, group, caption) else t = string.format("%s %s", label, caption) end

	if MikSBT then
		MikSBT.DisplayMessage(t, MikSBT.DISPLAYTYPE_NOTIFICATION, crit, ec.r * 255, ec.g * 255, ec.b * 255, nil, nil, nil, icon)
	elseif _G.SHOW_COMBAT_TEXT == "1" then
		CombatText_AddMessage(t, COMBAT_TEXT_SCROLL_FUNCTION, ec.r, ec.g, ec.b, crit and "crit")
	end
	return true
end

-- Play a sound after looking it up in SharedMedia
local function PlaySoundMedia(soundMedia)
	if soundMedia and not MOD.suppress then -- make sure sound is not suppressed
		local sound = media:Fetch("sound", soundMedia)
		if sound then PlaySoundFile(sound, Raven.db.global.SoundChannel) end
	end
end

-- Manage a bar, creating one if not currently active, otherwise updating as necessary
-- Use originating bar group (bp) for filtering, display bar group (vbp) for appearance options
local function UpdateBar(bp, vbp, bg, b, icon, timeLeft, duration, count, btype, ttType, ttID, ttUnit, ttCaster, isMine)
	local now = GetTime()
	if duration > 0 then -- check if timer bar
		local elapsed = duration - timeLeft
		if (b.hide and (elapsed >= (b.delayTime or 0))) or (bp.hide and (elapsed >= (bp.delayTime or 0))) then return end
	end

	local bar, barname, label, bt = nil, b.barLabel .. b.uniqueID, b.barLabel, b.barType
	if vbp.sor == "X" then barname = string.format("%05d ", b.sorder) .. barname end
	if bp.detectTotems then barname = b.uniqueID .. b.barLabel end -- use slot order for auto-generated totem bars

	local maxTime = duration
	if vbp.setDuration then -- override with uniform duration for all bars in group (optionally ignore shorter bars)
		if not vbp.setOnlyLongDuration or (duration > vbp.uniformDuration) then maxTime = vbp.uniformDuration end
	end

	if b.labelNumber then -- optionally get a number found in the tooltip and add it to the label
		local num = MOD:GetTooltipNumber(ttType, ttID, ttUnit, b.labelNumberOffset) -- returns number as a string
		if string.find(label, "TT#") then -- special case to just show the number without rest of label
			if num and not b.startReady then label = num else label = "" end
		else
			if num then label = string.format("%s: %s", label, num) end
		end
	end

	local c = ((ttType == "alert") and b.barColor) or GetColorForBar(vbp, b, btype)
	if b.colorBar then -- color may be overriden based on value of a condition
		local result = MOD:CheckCondition(b.colorCondition)
		if result then
			if b.colorTrue and b.colorTrue.a > 0 then c = b.colorTrue end
		else
			if b.colorFalse and b.colorFalse.a > 0 then c = b.colorFalse end
		end
	end

	local iconCount =nil
	if count then
		if type(count) ~= "number" then
			if not vbp.hideIcon and count ~= "" then iconCount = count end
		else
			count = math.floor(count + 0.001)
			if bt == "Cooldown" or (count > 1) then
				if not vbp.hideCount then label = string.format("%s (%d)", label, count) end
				if not vbp.hideIcon then iconCount = count end
			end
		end
	end

	bar = MOD.Nest_GetBar(bg, barname)
	if not (bp.showNoDuration and bp.showOnlyNoDuration) and not ((timeLeft == 0) and (duration == 0)) then -- bar with duration
		if bar and MOD.Nest_IsTimer(bar) then -- existing timer bar
			local oldTimeLeft, oldDuration, oldMaxTime = MOD.Nest_GetTimes(bar)
			if (duration ~= oldDuration) or maxTime ~= oldMaxTime or (math.abs(timeLeft - oldTimeLeft) > 0.5) then
				MOD.Nest_StartTimer(bar, timeLeft, duration, maxTime) -- update if the bar is out of sync
			end
		else
			if bar then MOD.Nest_DeleteBar(bg, bar); bar = nil end
			bar = MOD.Nest_CreateBar(bg, barname)
			if bar then MOD.Nest_StartTimer(bar, timeLeft, duration, maxTime); if b.ghost then bar.attributes.ghostDuration = b.endEffectTime or 5 end end
		end
	elseif bp.showNoDuration or (bt == "Notification") or (bt == "Broker") or (bt == "Value") or b.enableReady then -- bars without duration
		if bar and MOD.Nest_IsTimer(bar) then MOD.Nest_DeleteBar(bg, bar); bar = nil end
		if not bar then
			bar = MOD.Nest_CreateBar(bg, barname)
			if bar and bt == "Notification" then MOD.Nest_SetFlash(bar, b.flash) end
		end
	end
	if bar then
		local bat = bar.attributes -- lower overhead from setting a large number of bar attributes
		local _, _, _, startTime = MOD.Nest_GetTimes(bar) -- get time bar was created
		local elapsed = now - startTime -- how much time since bar was created
		local ticky = false
		if (bt == "Value") then
			if b.frequent then frequentBars[b] = bar else frequentBars[b] = nil end -- save in the frequent bar update table
			if b.segmentCount then bat.segmentCount = b.segmentCount else bat.segmentCount = nil end -- this will override bar group setting
		end
		bat.updated = true -- for mark/sweep bar deletion
		bat.ghostTime = nil -- delete in case was previously a ghost bar
		if b.barText then
			MOD.Nest_SetLabel(bar, b.barText)
		elseif label then
			if vbp.casterLabels and ttCaster then label = "[" .. ttCaster .. "] " .. label end
			if vbp.spellLabels and b.spellID then label = label .. " [#" .. b.spellID .. "]" end
			MOD.Nest_SetLabel(bar, label)
		else
			MOD.Nest_SetLabel(bar, nil)
		end
		bat.hideLabel = b.hideLabel -- suppress label setting for custom bars
		local tex = nil
		if b.action and MOD.db.global.SpellIcons[b.action] then tex = MOD:GetIcon(b.action) end -- check for override of the icon
		if tex then MOD.Nest_SetIcon(bar, tex) else MOD.Nest_SetIcon(bar, icon) end
		bat.customBackground = (vbp.bgColors == "Custom") -- check if using a custom background color
		local bc = bat.customBackground and vbp.bgColor or c
		local ibr, ibg, ibb, iba = 1, 1, 1, 1
		local ic = vbp.iconBorderColor
		if vbp.iconColors == "Normal" or (isMine and (vbp.iconColors == "Player")) then
			ibr, ibg, ibb, iba = c.r, c.g, c.b, c.a
		elseif not isMine and (vbp.iconColors == "Player") then
			ibr, ibg, ibb, iba = bc.r, bc.g, bc.b, bc.a
		elseif vbp.iconColors == "Debuffs" then -- special color for both buffs and debuffs
			local dc = MOD:GetSpecialColorForBar(vbp, b, btype)
			if dc then ibr, ibg, ibb, iba = dc.r, dc.g, dc.b, dc.a end
		elseif (vbp.iconColors == "Custom") and ic then
			ibr, ibg, ibb, iba = ic.r, ic.g, ic.b, ic.a
		elseif (vbp.iconColors == "None") then -- default border color only applies when not using Masque
			local dc = MOD.db.global.DefaultBorderColor
			if dc then ibr, ibg, ibb = dc.r, dc.g, dc.b end
		end
		ibr, ibg, ibb = MOD.Nest_AdjustColor(ibr, ibg, ibb, vbp.borderSaturation or 0, vbp.borderBrightness or 0)
		MOD.Nest_SetColors(bar, c.r, c.g, c.b, c.a, bc.r, bc.g, bc.b, bc.a, ibr, ibg, ibb, iba)
		MOD.Nest_SetCount(bar, iconCount) -- set the icon text to this count or blank if nil
		bat.iconColors = vbp.iconColors -- required in order to do right thing with "None"
		bat.isMine = (isMine == true) -- optional indication that bar action was cast by player
		local desat = vbp.desaturate and (not vbp.desaturateFriend or (UnitExists("target") and UnitIsFriend("player", "target")))
		bat.desaturate = (desat and not isMine) -- optionally desaturate if not player bar
		bat.group = b.group -- optional group sorting parameter
		bat.groupName = b.groupName -- optional group name
		bat.header = (b.group and not b.groupName) -- special effect of hiding bar and icon
		if vbp.showTooltips and (vbp.combatTips or not MOD.status.inCombat) then
			bat.tooltipType = ttType; bat.tooltipID = ttID; bat.tooltipUnit = ttUnit -- tooltip info passed from bar source
			if vbp.spellTips then bat.tooltipSpell = b.spellID else bat.tooltipSpell = nil end  -- for spell id in tooltip when control and alt keys are both down
		else
			bat.tooltipType = nil; bat.tooltipID = nil; bat.tooltipUnit = nil; bat.tooltipSpell = nil -- tooltip info passed from bar source
		end
		bat.listID = b.listID -- for tooltip to show if found in a spell list
		if vbp.casterTips then bat.caster = ttCaster else bat.caster = nil end
		bat.saveBar = b -- not valid in auto bar group since it then points to a local not a permanent table!
		bat.fullReverse = b.startReady and bp.readyReverse -- ready bar can use reverse setting of the Full Bars option

		if bt ~= "Notification" and bt ~= "Broker" and bt ~= "Value" then
			bat.saveBarGroup = vbp; bat.saveBarType = bt; bat.saveBarAction = b.action
		else
			bat.saveBarGroup = nil; bat.saveBarType = nil; bat.saveBarAction = nil
			if b.brokerVariable then -- support variable width brokers
				bat.minimumWidth = b.brokerMinimumWidth or 0; bat.maximumWidth = b.brokerMaximumWidth or 1000
			else
				bat.minimumWidth = nil; bat.maximumWidth = nil
			end
			bat.horizontalAlign = b.brokerAlign -- optional alignment on a horizontal bar
			bar.hideIcon = b.hideIcon
			MOD.Nest_SetValue(bar, b.value, b.maxValue, b.valueText, b.valueLabel, b.includeBar, b.includeOffset) -- used by broker and value bars
			if bt == "Value" then
				if b.tickOffset then MOD.Nest_SetTick(bar, true, b.tickOffset, 1, 0, 0, 1); ticky = true end
				if b.value_r and b.value_g and b.value_b then
					if not b.hideValueColorForeground then MOD.Nest_SetForegroundColor(bar, b.value_r, b.value_g, b.value_b) end
					if b.showValueColorBackground then MOD.Nest_SetBackgroundColor(bar, b.value_r, b.value_g, b.value_b) end
				end
			end
		end

		local click, onEnter, onLeave = Bar_OnClick, nil, nil
		if vbp.showTooltips and (vbp.combatTips or not MOD.status.inCombat) then onEnter = Bar_OnEnter; onLeave = Bar_OnLeave end
		MOD.Nest_SetCallbacks(bar, click, onEnter, onLeave)

		local sfxBG = (vbp.auto or not b.disableBGSFX) and not b.startReady and not vbp.disableBGSFX -- using bar group special effects
		local sfxBar = not vbp.auto and not b.disableBarSFX -- using custom bar special effects

		local expireBar, expireBG = nil, nil -- calculate expire times for bar group and/or custom bar
		if sfxBar and (duration > (b.expireMinimum or 0)) then
			expireBar = b.flashTime or 5
			local pt = duration * (b.expirePercentage or 0) / 100
			if pt > expireBar then expireBar = pt end -- percent setting is minimum so only override if longer
			if not b.spellExpireTimes then -- for some reason, this is set to false when using spell's expire times
				local st = MOD:GetSpellExpireTime(b.action, b.spellID)
				if st then expireBar = st end -- always override the expire time setting when set
			end
		end
		if sfxBG and (duration > (vbp.expireMinimum or 0)) then
			expireBG = vbp.flashTime or 5
			local pt = duration * (vbp.expirePercentage or 0) / 100
			if pt > expireBG then expireBG = pt end -- percent setting is minimum so only override if longer
			if not vbp.spellExpireTimes then -- for some reason, this is set to false when using spell's expire times
				local st = MOD:GetSpellExpireTime(b.action, b.spellID)
				if st then expireBG = st end -- always override the expire time setting when set
			end
		end

		local inStartBG = sfxBG and ((elapsed >= (vbp.delayTime or 0)) and ((vbp.startEffectTime == 0) or (elapsed <= ((vbp.delayTime or 0) + (vbp.startEffectTime or 5)))))
		local inStartBar = sfxBar and not b.startReady and ((elapsed >= (b.delayTime or 0)) and ((b.startEffectTime == 0) or (elapsed <= ((b.delayTime or 0) + (b.startEffectTime or 5)))))
		local inExpireBG = sfxBG and expireBG and (timeLeft <= expireBG) and (timeLeft > 0)
		local inExpireBar = sfxBar and not b.startReady and expireBar and (timeLeft <= expireBar) and (timeLeft > 0)
		local inFinish = (timeLeft <= 0.62) and (timeLeft > 0) -- let one or two frames show after shine and pulse finish
		local inFinishBG = inFinish and sfxBG
		local inFinishBar = inFinish and sfxBar and not b.startReady
		local inReadyBar = sfxBar and b.startReady
		local t

		if inStartBG and not vbp.selectAll then -- check filters for auto bar group start effects
			-- filters include: isPlayer, isPet, isBoss, isDispel, isStealable, isPoison, isCurse, isMagic, isDisease, isEnrage
			inStartBG = (b.isPlayer and vbp.selectPlayer) or (b.isPet and vbp.selectPet) or (b.isBoss and vbp.selectBoss) or
					(b.isDispel and vbp.selectDispel) or (b.isStealable and vbp.selectStealable) or
					(b.isPoison and vbp.selectPoison) or (b.isCurse and vbp.selectCurse) or (b.isMagic and vbp.selectMagic) or
					(b.isDisease and vbp.selectDisease) or (b.isEnrage and vbp.selectEnrage)
		end

		if elapsed == 0 then
			bar.shineStart = false; bar.sparkleStart = false; bar.pulseStart = false -- reset flags for when bars are started or restarted
			bar.shineExpiring = false; bar.sparkleExpiring = false; bar.pulseExpiring = false -- and for when bars are expiring
			bar.shineEnd = false; bar.sparkleEnd = false; bar.pulseEnd = false -- and for when bars are nearly finished
			bar.shineReady = false; bar.sparkleReady = false; bar.pulseReady = false -- and for ready bars
			bar.soundStart = false; bar.soundExpire = false; bar.soundEnd = false; bar.soundReady = false -- and for playing sounds
			bar.combatStart = false; bar.expireMSBT = false; bar.combatEnd = false; bar.combatReady = false -- and for combat text displays

			if not bar.timers then bar.timers = {} else table.wipe(bar.timers) end -- reset table used to set times for forced updates
			if sfxBG then
				t = now + (vbp.delayTime or 0); if t > now then bar.timers.inStartBG = t end
				if vbp.startEffectTime ~= 0 then t = t + (vbp.startEffectTime or 5); if t > now then bar.timers.effectBG = t end end
			end
			if sfxBar then
				t = now + (b.delayTime or 0); if t > now then bar.timers.inStartBar = t end
				if b.startEffectTime ~= 0 then t = t + (b.startEffectTime or 5); if t > now then bar.timers.effectBar = t end end
			end
			if (duration > 0) and (timeLeft > 0) then
				if sfxBG and not inExpireBG then bar.timers.inExpireBG = expireBG and (now + duration - expireBG) or nil end
				if sfxBar and not inExpireBar then bar.timers.inExpireBar = expireBar and (now + duration - expireBar) or nil end
				t = now + duration; if t > now then bar.timers.final = t end
				t = t - 0.62; if t > now then bar.timers.inFinish = t end
			end
		end

		if inExpireBar and b.colorExpiring then -- change bar, label and time colors when expiring
			t = (b.spellExpireColors and MOD:GetExpireColor(b.action, b.spellID)) or b.expireColor or rc; if t.a > 0 then
			MOD.Nest_SetForegroundColor(bar, t.r, t.g, t.b)
			if b.expireFGBG then MOD.Nest_SetBackgroundColor(bar, t.r, t.g, t.b) end
		end
			t = b.expireLabelColor or vc; if t.a > 0 then MOD.Nest_SetLabelColor(bar, t.r, t.g, t.b) end
			t = b.expireTimeColor or vc; if t.a > 0 then MOD.Nest_SetTimeColor(bar, t.r, t.g, t.b) end
		elseif inExpireBG and vbp.colorExpiring then
			t = (vbp.spellExpireColors and MOD:GetExpireColor(b.action, b.spellID)) or vbp.expireColor or rc; if t.a > 0 then
			MOD.Nest_SetForegroundColor(bar, t.r, t.g, t.b)
			if vbp.expireFGBG then MOD.Nest_SetBackgroundColor(bar, t.r, t.g, t.b) end
		end
			t = vbp.expireLabelColor or vc; if t.a > 0 then MOD.Nest_SetLabelColor(bar, t.r, t.g, t.b) end
			t = vbp.expireTimeColor or vc; if t.a > 0 then MOD.Nest_SetTimeColor(bar, t.r, t.g, t.b) end
		else
			MOD.Nest_SetLabelColor(bar) -- clear override of label text color
			MOD.Nest_SetTimeColor(bar) -- clear override of time text color
		end

		if duration > 0 then -- only timer bars of limited duration get ticks
			local offset = 0
			if sfxBar and b.colorExpiring then -- custom bar has precedence over bar group special effects if both are enabled
				t = b.tickColor or vc -- show or hide tick mark for custom bar
				if bar.timers.inExpireBar and bar.timers.final then offset = bar.timers.final - bar.timers.inExpireBar end
				if t.a > 0 then MOD.Nest_SetTick(bar, true, offset, t.r, t.g, t.b, t.a); ticky = true end
			elseif sfxBG and vbp.colorExpiring then
				t = vbp.tickColor or vc -- show or hide tick mark for bar group
				if bar.timers.inExpireBG and bar.timers.final then offset = bar.timers.final - bar.timers.inExpireBG end
				if t.a > 0 then MOD.Nest_SetTick(bar, true, offset, t.r, t.g, t.b, t.a); ticky = true end
			end
		end
		if not ticky then MOD.Nest_SetTick(bar, false, 0) end

		bat.shineColor = wc; bat.sparkleColor = wc; bat.glowColor = wc -- first set defaults for customization options
		bat.flashPeriod = 1.2; bat.flashPercent = 50

		if sfxBG and vbp.customizeSFX then -- second apply bar group sfx settings
			bat.shineColor = vbp.shineColor or bat.shineColor
			bat.sparkleColor = vbp.sparkleColor or bat.sparkleColor
			bat.glowColor = vbp.glowColor or bat.glowColor
			bat.flashPeriod = vbp.flashPeriod or bat.flashPeriod
			bat.flashPercent = vbp.flashPercent or bat.flashPercent
		end

		if sfxBar and b.customizeSFX then -- finally, override with sfx settings for custom bars, if any are set
			bat.shineColor = b.shineColor or bat.shineColor
			bat.sparkleColor = b.sparkleColor or bat.sparkleColor
			bat.glowColor = b.glowColor or bat.glowColor
			bat.flashPeriod = b.flashPeriod or bat.flashPeriod
			bat.flashPercent = b.flashPercent or bat.flashPercent
		end

		local shineStart = not bar.shineStart and ((vbp.shineStart and inStartBG) or (b.shineStart and inStartBar)) -- shine at start
		local shineExpiring = not bar.shineExpiring and ((vbp.shineExpiring and inExpireBG) or (b.shineExpiring and inExpireBar)) -- shine at expire time
		local shineEnd = not bar.shineEnd and ((vbp.shineEnd and inFinishBG) or (b.shineEnd and inFinishBar)) -- shine at finish
		local shineReady = not bar.shineReady and (b.shineReady and inReadyBar) -- shine when ready bar starts
		MOD.Nest_SetShine(bar, shineStart or shineReady or ((duration > 0) and (shineExpiring or shineEnd)))
		if shineStart then bar.shineStart = true end
		if shineExpiring then bar.shineExpiring = true end
		if shineEnd then bar.shineEnd = true end
		if shineReady then bar.shineReady = true end

		local sparkleStart = not bar.sparkleStart and ((vbp.sparkleStart and inStartBG) or (b.sparkleStart and inStartBar)) -- sparkle at start
		local sparkleExpiring = not bar.sparkleExpiring and ((vbp.sparkleExpiring and inExpireBG) or (b.sparkleExpiring and inExpireBar)) -- sparkle at expire time
		local sparkleEnd = not bar.sparkleEnd and ((vbp.sparkleEnd and inFinishBG) or (b.sparkleEnd and inFinishBar)) -- sparkle at finish
		local sparkleReady = not bar.sparkleReady and (b.sparkleReady and inReadyBar) -- sparkle when ready bar starts
		MOD.Nest_SetSparkle(bar, sparkleStart or sparkleReady or ((duration > 0) and (sparkleExpiring or sparkleEnd)))
		if sparkleStart then bar.sparkleStart = true end
		if sparkleExpiring then bar.sparkleExpiring = true end
		if sparkleEnd then bar.sparkleEnd = true end
		if sparkleReady then bar.sparkleReady = true end

		local pulseStart = not bar.pulseStart and ((vbp.pulseStart and inStartBG) or (b.pulseStart and inStartBar)) -- pulse at start
		local pulseExpiring = not bar.pulseExpiring and ((vbp.pulseExpiring and inExpireBG) or (b.pulseExpiring and inExpireBar)) -- pulse at expire time
		local pulseEnd = not bar.pulseEnd and ((vbp.pulseEnd and inFinishBG) or (b.pulseEnd and inFinishBar)) -- pulse at finish
		local pulseReady = not bar.pulseReady and (b.pulseReady and inReadyBar) -- pulse when ready bar starts
		MOD.Nest_SetPulse(bar, pulseStart or pulseReady or ((duration > 0) and (pulseExpiring or pulseEnd)))
		if pulseStart then bar.pulseStart = true end
		if pulseExpiring then bar.pulseExpiring = true end
		if pulseEnd then bar.pulseEnd = true end
		if pulseReady then bar.pulseReady = true end

		if (inFinishBG and vbp.splash) or (inFinishBar and b.splash) then bat.splash = true end --

		local isFlashing = (IsOn(b.flashBar) and (b.flashBar == MOD:CheckCondition(b.flashCondition))) or -- conditional flashing
				(vbp.flashStart and inStartBG) or (b.flashStart and inStartBar) or -- bar group or custom bar start effect
				(vbp.flashExpiring and inExpireBG) or (b.flashExpiring and inExpireBar) or -- bar group or custom bar expire effect
				(b.flashReady and b.startReady) -- ready bar flash option
		MOD.Nest_SetFlash(bar, isFlashing)

		local isGlowing = (IsOn(b.glowBar) and (b.glowBar == MOD:CheckCondition(b.glowCondition))) or -- conditional glow
				(vbp.glowStart and inStartBG) or (b.glowStart and inStartBar) or -- bar group or custom bar start effect
				(vbp.glowExpiring and inExpireBG) or (b.glowExpiring and inExpireBar) or -- bar group or custom bar expire effect
				(b.glowReady and inReadyBar) -- custom bar ready effect
		MOD.Nest_SetGlow(bar, isGlowing)

		local isDesaturated = (vbp.desatStart and inStartBG) or (b.desatStart and inStartBar) or -- bar group or custom bar start effect
				(vbp.desatExpiring and inExpireBG) or (b.desatExpiring and inExpireBar) or -- bar group or custom bar expire effect
				(b.desaturateReadyIcon and inReadyBar) -- custom bar ready effect
		if isDesaturated then bat.desaturate = true end -- desaturate icons (should not interfere with other desaturate settings)

		local isFaded = false
		local dft, gd = not vbp.useDefaultFontsAndTextures, MOD.db.global.Defaults -- indicates the bar group has overrides for fonts and textures
		local alpha = 1 -- adjust alpha based on bar group options and special effects
		if MOD.status.inCombat then alpha = (dft and vbp.combatAlpha or gd.combatAlpha) else alpha = (dft and vbp.alpha or gd.alpha) end
		if vbp.targetAlpha and ttUnit == "all" and b.group ~= UnitGUID("target") then alpha = alpha * vbp.targetAlpha end
		if IsOn(b.fadeBar) then -- conditional fade for bars is higher priority than bar group setting for delayed fade
			if (b.fadeBar == MOD:CheckCondition(b.fadeCondition)) and b.fadeAlpha then alpha = alpha * b.fadeAlpha; isFaded = true end
		elseif b.fade and b.fadeAlpha and not b.startReady then
			if inStartBar then alpha = alpha * b.fadeAlpha; isFaded = true end
		elseif vbp.fade and vbp.fadeAlpha and not b.startReady then
			if inStartBG then alpha = alpha * vbp.fadeAlpha; isFaded = true end
		end

		if not isFaded then -- fading is highest priority
			if b.startReady or (b.enableReady and b.readyCharges and count and (count >= 1)) then
				if b.readyAlpha then alpha = alpha * b.readyAlpha end -- adjust alpha for ready bars
			elseif b.normalAlpha then alpha = alpha * b.normalAlpha end
		end
		MOD.Nest_SetAlpha(bar, alpha)

		local tBar = not b.combatTextExcludesBG and bg.name or nil
		local tBG = not vbp.combatTextExcludesBG and bg.name or nil
		if not bar.combatStart then
			if inStartBar and b.combatStart then
				bar.combatStart = ShowCombatText(label, tBar, L["started"], icon, b.combatCriticalStart, b.combatColorStart or rc)
			elseif inStartBG and vbp.combatStart then
				bar.combatStart = ShowCombatText(label, tBG, L["started"], icon, vbp.combatCriticalStart, vbp.combatColorStart or rc)
			end
		end
		if not bar.expireMSBT then
			if inExpireBar and b.expireMSBT then
				bar.expireMSBT = ShowCombatText(label, tBar, L["expiring"], icon, b.criticalMSBT, b.colorMSBT or rc)
			elseif inExpireBG and vbp.expireMSBT then
				bar.expireMSBT = ShowCombatText(label, tBG, L["expiring"], icon, vbp.criticalMSBT, vbp.colorMSBT or rc)
			end
		end
		if not bar.combatEnd then
			if inFinishBar and b.combatEnd then
				bar.combatEnd = ShowCombatText(label, tBar, L["finished"], icon, b.combatCriticalEnd, b.combatColorEnd or rc)
			elseif inFinishBG and vbp.combatEnd then
				bar.combatEnd = ShowCombatText(label, tBG, L["finished"], icon, vbp.combatCriticalEnd, vbp.combatColorEnd or rc)
			end
		end
		if not bar.combatReady and inReadyBar and b.combatReady then
			bar.combatReady = ShowCombatText(label, tBar, L["ready"], icon, b.combatCriticalReady, b.combatColorReady or rc)
		end

		if not MOD.db.profile.muteSFX then -- make sure sounds are not muted
			if (inStartBG and (vbp.soundSpellStart or (vbp.soundAltStart ~= "None"))) or ((inStartBar and (b.soundSpellStart or (b.soundAltStart ~= "None")))) then
				local sound, sp, replay, replayTime = nil, nil, false, 5 -- play start sound effect
				if vbp.soundSpellStart or b.soundSpellStart then sp = MOD:GetAssociatedSpellForBar(b); if sp then sound = MOD:GetSound(sp, b.spellID) end end
				if not sound and b.soundAltStart ~= "None" then sound = b.soundAltStart end
				if not sound and vbp.soundAltStart ~= "None" then sound = vbp.soundAltStart end
				if vbp.replay then replay = true; replayTime = (vbp.replayTime or 5) elseif b.replay then replay = true; replayTime = (b.replayTime or 5) end
				if sound and (not bar.soundStart or (replay and (now > bar.replayTime))) then
					PlaySoundMedia(sound)
					bar.replayTime = now + replayTime
					bar.soundStart = true
				end
			end

			if not bar.soundExpire and ((inExpireBG and (vbp.soundSpellExpire or (vbp.soundAltExpire ~= "None"))) or
					(inExpireBar and (b.soundSpellExpire or (b.soundAltExpire ~= "None")))) then
				local sound, sp = nil, nil -- play expire sound effect
				if vbp.soundSpellExpire or b.soundSpellExpire then sp = MOD:GetAssociatedSpellForBar(b); if sp then sound = MOD:GetSound(sp, b.spellID) end end
				if not sound and b.soundAltExpire ~= "None" then sound = b.soundAltExpire end
				if not sound and vbp.soundAltExpire ~= "None" then sound = vbp.soundAltExpire end
				if sound then
					PlaySoundMedia(sound)
					bar.soundExpire = true
				end
			end

			if not bar.soundEnd and ((inFinishBG and (vbp.soundSpellEnd or (vbp.soundAltEnd ~= "None"))) or
					(inFinishBar and (b.soundSpellEnd or (b.soundAltEnd ~= "None")))) then
				local sound, sp = nil, nil -- play finish sound effect
				if vbp.soundSpellEnd or b.soundSpellEnd then sp = MOD:GetAssociatedSpellForBar(b); if sp then sound = MOD:GetSound(sp, b.spellID) end end
				if not sound and b.soundAltEnd ~= "None" then sound = b.soundAltEnd end
				if not sound and vbp.soundAltEnd ~= "None" then sound = vbp.soundAltEnd end
				if sound then
					PlaySoundMedia(sound)
					bar.soundEnd = true
				end
			end

			if not bar.soundReady and (inReadyBar and (b.soundSpellReady or (b.soundAltReady ~= "None"))) then
				local sound, sp = nil, nil -- play ready sound effect
				if b.soundSpellReady then sp = MOD:GetAssociatedSpellForBar(b); if sp then sound = MOD:GetSound(sp, b.spellID) end end
				if not sound and b.soundAltReady ~= "None" then sound = b.soundAltReady end
				if sound then
					PlaySoundMedia(sound)
					bar.soundReady = true
				end
			end
		end
	end
end

-- Compare caster to enforce "cast by" restrictions
function MOD:CheckCastBy(caster, cb)
	local isMine, isPet, isTarget, isFocus = false, false, false, false
	if not cb then cb = "player" else cb = string.lower(cb) end -- for backward compatibility
	if caster ~= "unknown" then
		isMine = UnitIsUnit("player", caster)
		isPet = UnitExists("pet") and UnitIsUnit("pet", caster)
		isTarget = UnitExists("target") and UnitIsUnit("target", caster)
		isFocus = UnitExists("focus") and UnitIsUnit("focus", caster)
	end
	local isOurs = isMine or isPet
	return ((cb == "player") and isMine) or (cb == "anyone") or ((cb == "pet") and isPet) or ((cb == "other") and not isOurs) or ((cb == "ours") and isOurs) or
			((cb == "nother") and not (isOurs or isTarget)) or ((cb == "target") and isTarget) or ((cb == "focus") and isFocus)
end

-- Check if an action is in the associated filter bar group
local function CheckFilterBarGroup(bgname, btype, action, value)
	if not bgname or not action then return false end
	local bg = MOD.db.profile.BarGroups[bgname]
	if IsOn(bg) then
		if bg.auto then -- auto bar groups look in the filter list (doesn't matter if black list or white list)
			if btype == "Buff" then
				if (bg.filterBuff or bg.showBuff) and bg.filterBuffList and bg.filterBuffList[action] then return true end
			elseif btype == "Debuff" then
				if (bg.filterDebuff or bg.showDebuff) and bg.filterDebuffList and bg.filterDebuffList[action] then return true end
			elseif btype == "Cooldown" then
				if (bg.filterCooldown or bg.showCooldown) and bg.filterCooldownList and bg.filterCooldownList[action] then return true end
			end
		else -- custom bar groups look at the cached info generated from the custom bar list
			local v = GetCache(bg, btype, action)
			if v == value then return true end -- for auras this is which unit is being monitored
		end
	end
	return false
end

-- For minion bars, generate pretty string to add energy to label for wild imps
local function MinionEnergy(count)
	if count == 1 then return " |cFF88c100*|r" end
	if count == 2 then return " |cFF88c100**|r" end
	if count == 3 then return " |cFF88c100***|r" end
	if count == 4 then return " |cFF88c100****|r" end
	if count == 5 then return " |cFF88c100*****|r" end
	-- local s = "";  for i = 1, count do s = s .. "|TInterface\\Icons\\Spell_Fel_Firebolt:16|t" end; return s
end

-- Check for detected buffs and create bars for them in the specified bar group
-- Detected auras that don't match current bar group settings may need to be added later if the settings change
local function DetectNewBuffs(unit, n, aura, isBuff, bp, vbp, bg)
	local listID = nil
	local spellID = aura[14]
	if bp.showBuff or bp.filterBuff then -- check black lists and white lists
		local spellNum = spellID and ("#" .. tostring(spellID)) -- string to look up the spell id in lists
		local listed = bp.filterBuffList and (bp.filterBuffList[n] or (spellNum and bp.filterBuffList[spellNum]))
		if not listed then -- not found in the bar group's filter list, so check spell lists
			local spellList = nil -- check the first spell list, if specified
			if bp.filterBuffSpells and bp.filterBuffTable then spellList = MOD.db.global.SpellLists[bp.filterBuffTable] end
			if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end -- check first spell list, if specified
			if not listed then
				spellList = nil -- check second spell list, if specified
				if bp.filterBuffSpells2 and bp.filterBuffTable2 then spellList = MOD.db.global.SpellLists[bp.filterBuffTable2] end
				if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
				if not listed then
					spellList = nil -- check third spell list, if specified
					if bp.filterBuffSpells3 and bp.filterBuffTable3 then spellList = MOD.db.global.SpellLists[bp.filterBuffTable3] end
					if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
					if not listed then
						spellList = nil -- check fourth spell list, if specified
						if bp.filterBuffSpells4 and bp.filterBuffTable4 then spellList = MOD.db.global.SpellLists[bp.filterBuffTable4] end
						if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
						if not listed then
							spellList = nil -- check fifth spell list, if specified
							if bp.filterBuffSpells5 and bp.filterBuffTable5 then spellList = MOD.db.global.SpellLists[bp.filterBuffTable5] end
							if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
						end
					end
				end
			end
			if listed then listID = listed end -- if found in a spell list then save for tooltip display
		end
		if (bp.filterBuff and listed) or (bp.showBuff and not listed) then return end
	end
	if bp.filterBuffBars and CheckFilterBarGroup(bp.filterBuffBarGroup, "Buff", n, bp.detectBuffsMonitor) then return end -- check if in filter bar group
	local label = MOD:GetLabel(n, spellID) -- check if there is a cached label for this action or spellid
	local tt, ta, tc, tsteal, ttype, icon = aura[11], aura[12], aura[6], aura[7], aura[4], aura[8]
	if (ttype == "Totem") and not bp.includeTotems then return end -- check if including totems
	if tt == "minion" and tsteal then label = label .. MinionEnergy(tsteal); tsteal = nil end -- -- add wild imp energy

	local isStealable = ((tsteal == 1) or (tsteal == true))
	local isNPC = aura[18]
	local isVehicle = aura[19]
	local isBoss = ((aura[15] == 1) or (aura[15] == true))
	local isEnrage = (ttype == "")
	local isMagic = (ttype == "Magic") and not isStealable
	local isEffect = (tt == "effect")
	local isAlert = (tt == "alert")
	local isWeapon = (tt == "weapon")
	local isTracking = (tt == "tracking")
	local isResource = (ttype == "Power")
	local isMinion = (ttype == "Minion")
	local isMount = MOD.ExpansionIsOrAbove(LE_EXPANSION_WARLORDS_OF_DRAENOR) and spellID and MOD.mountSpells[spellID] -- table contains all the mounts in the journal
	local isMine = (tc == "player")
	local isTabard = isMine and icon and (icon == tabardIcon) -- test if on player, same icon as equipped tabard, not cancellable
	local isCastable = aura[17] and not isWeapon
	local isOther = not isStealable and not isCastable and not isNPC and not isVehicle and not isMagic and not isEffect and
			not isWeapon and not isBoss and not isEnrage and not isTracking and not isResource and not isMount and not isTabard
	local id, gname = nil, nil
	local checkAll = (unit == "all")
	if checkAll then id = aura[20]; gname = aura[21] end -- these fields are only valid if unit == "all"
	local includeTypes = not bp.detectBuffTypes or (bp.detectStealable and isStealable) or (bp.detectCastable and isCastable)
			or (bp.detectNPCBuffs and isNPC) or (bp.detectVehicleBuffs and isVehicle) or (bp.detectBossBuffs and isBoss) or (bp.detectEnrageBuffs and isEnrage)
			or (bp.detectMagicBuffs and isMagic) or (bp.detectEffectBuffs and isEffect) or (bp.detectAlertBuffs and isAlert) or (bp.detectWeaponBuffs and isWeapon)
			or (bp.detectTracking and isTracking) or (bp.detectResources and isResource) or (bp.detectMountBuffs and isMount)
			or (bp.detectTabardBuffs and isTabard) or (bp.detectMinionBuffs and isMinion) or (bp.detectOtherBuffs and isOther)
	local excludeTypes = not bp.excludeBuffTypes or not ((bp.excludeStealable and isStealable) or (bp.excludeCastable and isCastable)
			or (bp.excludeNPCBuffs and isNPC) or (bp.excludeVehicleBuffs and isVehicle) or (bp.excludeBossBuffs and isBoss) or (bp.excludeEnrageBuffs and isEnrage)
			or (bp.excludeMagicBuffs and isMagic) or (bp.excludeEffectBuffs and isEffect) or (bp.excludeAlertBuffs and isAlert) or (bp.excludeWeaponBuffs and isWeapon)
			or (bp.excludeTracking and isTracking) or (bp.excludeResources and isResource) or (bp.excludeMountBuffs and isMount)
			or (bp.excludeTabardBuffs and isTabard) or (bp.excludeMinionBuffs and isMinion) or (bp.excludeOtherBuffs and isOther))
	if ((checkAll and not (bp.noPlayerBuffs and (id == UnitGUID("player"))) and not (bp.noPetBuffs and (id == UnitGUID("pet")))
			and not (bp.noTargetBuffs and (id == UnitGUID("target"))) and not (bp.noFocusBuffs and (id == UnitGUID("focus")))) or
			(not checkAll and not (bp.noPlayerBuffs and UnitIsUnit(unit, "player")) and not (bp.noPetBuffs and UnitIsUnit(unit, "pet"))
					and not (bp.noTargetBuffs and UnitIsUnit(unit, "target")) and not (bp.noFocusBuffs and UnitIsUnit(unit, "focus")) and
					MOD:CheckCastBy(tc, bp.detectBuffsCastBy))) and CheckTimeAndDuration(bp, aura[2], aura[5]) and includeTypes and excludeTypes then

		local b, tag = detectedBar, aura[9]
		table.wipe(b); b.enableBar = true; b.sorder = 0; b.action = n; b.spellID = spellID; b.barType = "Buff"
		if unit == "all" then
			tag = tag .. ":" .. id
			if vbp.noHeaders then label = (vbp.noLabels and "" or (label .. (vbp.noTargets and "" or " - "))) .. (vbp.noTargets and "" or gname) end
		end
		if isEffect and ta then
			local ect = MOD.db.global.SpellEffects[ta]
			if ect and ect.label then label = label .. " |cFF7adbf2[" .. (UnitName(tc) or tc) .. "]|r" end -- prefer caster's name if available
		end
		if isAlert then b.barColor = aura[20] if aura[21] then label = aura[21] end end

		b.group = id -- if unit is "all" then this is GUID of unit with buff, otherwise it is nil
		b.groupName = gname -- if unit is "all" then this is the name of the unit with buff, otherwise it is nil
		b.uniqueID = tag; b.listID = listID; b.barLabel = label
		b.isPlayer = isMine; b.isPet = (tc == "pet"); b.isBoss = isBoss
		b.isStealable = isStealable; b.isMagic = isMagic; b.isEnrage = isEnrage
		UpdateBar(bp, vbp, bg, b, icon, aura[2], aura[5], aura[3], ttype, tt, ta, unit, aura[16], isMine)
	end
end

-- Check for detected debuffs and create bars for them in the specified bar group
local function DetectNewDebuffs(unit, n, aura, isBuff, bp, vbp, bg)
	local listID = nil
	if bp.showDebuff or bp.filterDebuff then -- check black lists and white lists
		local spellNum = aura[14] and ("#" .. tostring(aura[14])) -- string to look up the spell id in lists
		local listed = bp.filterDebuffList and (bp.filterDebuffList[n] or (spellNum and bp.filterDebuffList[spellNum]))
		if not listed then -- not found in the bar group's filter list, so check spell lists
			local spellList = nil -- check the first spell list, if specified
			if bp.filterDebuffSpells and bp.filterDebuffTable then spellList = MOD.db.global.SpellLists[bp.filterDebuffTable] end
			if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end -- check first spell list, if specified
			if not listed then
				spellList = nil -- check second spell list, if specified
				if bp.filterDebuffSpells2 and bp.filterDebuffTable2 then spellList = MOD.db.global.SpellLists[bp.filterDebuffTable2] end
				if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
				if not listed then
					spellList = nil -- check third spell list, if specified
					if bp.filterDebuffSpells3 and bp.filterDebuffTable3 then spellList = MOD.db.global.SpellLists[bp.filterDebuffTable3] end
					if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
					if not listed then
						spellList = nil -- check fourth spell list, if specified
						if bp.filterDebuffSpells4 and bp.filterDebuffTable4 then spellList = MOD.db.global.SpellLists[bp.filterDebuffTable4] end
						if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
						if not listed then
							spellList = nil -- check fifth spell list, if specified
							if bp.filterDebuffSpells5 and bp.filterDebuffTable5 then spellList = MOD.db.global.SpellLists[bp.filterDebuffTable5] end
							if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
						end
					end
				end
			end
			if listed then listID = listed end -- if found in a spell list then save for tooltip display
		end
		if (bp.filterDebuff and listed) or (bp.showDebuff and not listed) then return end
	end
	if bp.filterDebuffBars and CheckFilterBarGroup(bp.filterDebuffBarGroup, "Debuff", n, bp.detectDebuffsMonitor) then return end -- check if in filter bar group
	local label = MOD:GetLabel(n, aura[14]) -- check if there is a cached label for this action or spellid
	local isDispel = MOD:IsDebuffDispellable(n, unit, aura[4])
	local isInflict = aura[17]
	local isNPC = aura[18]
	local isVehicle = aura[19]
	local tt, ta, tc = aura[11], aura[12], aura[6]
	local isBoss = aura[15]
	local isEffect = (tt == "effect")
	local isAlert = (tt == "alert")
	local isPoison, isCurse, isMagic, isDisease = (aura[4] == "Poison"), (aura[4] == "Curse"), (aura[4] == "Magic"), (aura[4] == "Disease")
	local isOther = not isBoss and not isEffect and not isPoison and not isCurse and not isMagic and not isDisease
			and not isDispel and not isInflict and not isNPC and not isVehicle
	local isMine = (tc == "player")
	local id, gname = aura[20], aura[21]
	local checkAll = (unit == "all")
	local includeTypes = not bp.filterDebuffTypes or (bp.detectDispellable and isDispel) or (bp.detectInflictable and isInflict)
			or (bp.detectNPCDebuffs and isNPC) or (bp.detectVehicleDebuffs and isVehicle) or (bp.detectBossDebuffs and isBoss)
			or (bp.detectPoison and isPoison) or (bp.detectCurse and isCurse) or (bp.detectMagic and isMagic) or (bp.detectDisease and isDisease)
			or (bp.detectEffectDebuffs and isEffect) or (bp.detectAlertDebuffs and isAlert) or (bp.detectOtherDebuffs and isOther)
	local excludeTypes = not bp.excludeDebuffTypes or not ((bp.excludeDispellable and isDispel) or (bp.excludeInflictable and isInflict)
			or (bp.excludeNPCDebuffs and isNPC) or (bp.excludeVehicleDebuffs and isVehicle) or (bp.excludeBossDebuffs and isBoss)
			or (bp.excludePoison and isPoison) or (bp.excludeCurse and isCurse) or (bp.excludeMagic and isMagic) or (bp.excludeDisease and isDisease)
			or (bp.excludeEffectDebuffs and isEffect) or (bp.excludeAlertDebuffs and isAlert) or (bp.excludeOtherDebuffs and isOther))
	if ((checkAll and not (bp.noPlayerDebuffs and (id == UnitGUID("player"))) and not (bp.noPetDebuffs and (id == UnitGUID("pet")))
			and not (bp.noTargetDebuffs and (id == UnitGUID("target"))) and not (bp.noFocusDebuffs and (id == UnitGUID("focus")))) or
			(not checkAll and not (bp.noPlayerDebuffs and UnitIsUnit(unit, "player")) and not (bp.noPetDebuffs and UnitIsUnit(unit, "pet"))
					and not (bp.noTargetDebuffs and UnitIsUnit(unit, "target")) and not (bp.noFocusDebuffs and UnitIsUnit(unit, "focus")) and
					MOD:CheckCastBy(tc, bp.detectDebuffsCastBy))) and CheckTimeAndDuration(bp, aura[2], aura[5]) and includeTypes and excludeTypes then

		local b, tag = detectedBar, aura[9]
		table.wipe(b); b.enableBar = true; b.sorder = 0; b.action = n; b.spellID = aura[14]; b.barType = "Debuff"
		-- if not tag then MOD.Debug("tag bug", n, b.spellID); tag = b.barType .. ":Fake:" .. (b.spellID or "bogus") end
		if unit == "all" then
			tag = tag .. ":" .. id
			if vbp.noHeaders then label = (vbp.noLabels and "" or (label .. (vbp.noTargets and "" or " - "))) .. (vbp.noTargets and "" or gname) end
		end
		if isEffect and ta then
			local ect = MOD.db.global.SpellEffects[ta]
			if ect and ect.label then label = label .. " |cFF7adbf2[" .. (UnitName(tc) or tc) .. "]|r" end -- prefer caster's name if available
		end
		if isAlert then b.barColor = aura[20] if aura[21] then label = aura[21] end end

		b.group = id -- if unit is "all" then this is GUID of unit with debuff, otherwise it is nil
		b.groupName = gname -- if unit is "all" then this is the name of the unit with buff, otherwise it is nil
		b.uniqueID = tag; b.listID = listID; b.barLabel = label
		b.isPlayer = isMine; b.isPet = (tc == "pet"); b.isBoss = isBoss
		b.isDispel = isDispel; b.isPoison = isPoison; b.isMagic = isMagic; b.isCurse = isCurse; b.isDisease = isDisease
		UpdateBar(bp, vbp, bg, b, aura[8], aura[2], aura[5], aura[3], aura[4], tt, ta, unit, aura[16], isMine)
	end
end

-- Check if a cooldown is of right type for the specified bar group
local function CheckCooldownType(coolDown, bp)
	local other, type, name = true, coolDown[5], coolDown[6]
	if (type == "spell") or (type == "spell id") then
		other = false; if bp.detectSpellCooldowns then return true end
	elseif (type == "inventory") and ((name == 13) or (name == 14)) then
		other = false; if bp.detectTrinketCooldowns then return true end
	elseif (type == "internal") then
		other = false; if bp.detectInternalCooldowns then return true end
	elseif type == "effect" then
		other = false; if bp.detectSpellEffectCooldowns then return true end
	elseif type == "alert" then
		other = false; if bp.detectSpellAlertCooldowns then return true end
	elseif type == "text" then -- might be a potion or elixir
		if (name == "Shared Potion Cooldown") or (name == "Shared Elixir Cooldown") then
			other = false; if bp.detectPotionCooldowns then return true end
		elseif name == "Global Cooldown" then
			other = false; if bp.detectGlobalCooldown then return true end
		end
	end
	if other and bp.detectOtherCooldowns then return true end
	return false
end

-- Return true if cooldown is not one of the special case shared ones
local function CheckSharedCooldowns(b, bp)
	local id = b.spellID
	if MOD.myClass == "WARLOCK" then
		if bp.detectSharedGrimoires then
			if id == 111895 or id == 111896 or id == 111897 or id == 111898 then return false end
			if id == 111859 then b.barLabel = SHIM:GetSpellInfo(216187); return true end
		end
		if bp.detectSharedInfernals then
			if id == 18540 then return false end
			if id == 1122 then b.barLabel = L["Summon Infernal/Doomguard"]; return true end
		end
	end
	return true
end

-- Automatically generate rune cooldown bars for all six rune slots
local runeSlotPrefix = { "(1)  ", "(2)  ", "(3)  ", "(4)  ",  "(5)  ", "(6)  " }
local function AutoRuneBars(bp, vbp, bg)
	if MOD.myClass ~= "DEATHKNIGHT" then return end
	for i = 1, 6 do
		local rune = MOD.runeSlots[i]
		local b = detectedBar
		table.wipe(b); b.enableBar = true; b.sorder = 0
		b.action = L["Rune"]; b.spellID = nil; b.barLabel = runeSlotPrefix[i] .. b.action
		b.barType = "Cooldown"; b.uniqueID = "Cooldown"; b.group = nil
		local icon = SHIM:GetSpellTexture(207321) -- icon for Spell Eater
		if rune.ready then -- generate ready bar with no duration
			if CheckTimeAndDuration(bp, 0, 0) then
				UpdateBar(bp, vbp, bg, b, icon, 0, 0, nil, nil, "text", b.action, nil, nil, true)
			end
		else -- generate cooldown timer bar
			local timeLeft = rune.duration - (GetTime() - rune.start)
			if CheckTimeAndDuration(bp, timeLeft, rune.duration) then
				UpdateBar(bp, vbp, bg, b, icon, timeLeft, rune.duration, nil, nil, "text", b.action, nil, nil, true)
			end
		end
	end
end

-- Automatically generate totem bars for the totem slots
local function AutoTotemBars(bp, vbp, bg)
	if MOD.myClass ~= "SHAMAN" then return end
	local now = GetTime()
	for i = 1, 4 do
		local b = detectedBar
		table.wipe(b); b.enableBar = true; b.sorder = 0
		b.barType = "Cooldown"; b.uniqueID = "Totem" .. i; b.group = nil
		local haveTotem, name, startTime, duration, icon = GetTotemInfo(i)
		if haveTotem and name and name ~= "" and now <= (startTime + duration) then -- generate timer bar for the totem in the slot
			local timeLeft = duration - (now - startTime)
			if CheckTimeAndDuration(bp, timeLeft, duration) then
				b.action = name; b.barLabel = MOD:GetLabel(name); b.spellID = nil
				UpdateBar(bp, vbp, bg, b, icon, timeLeft, duration, nil, nil, "totem", i, "player", nil, true)
			end
		end
	end
end

-- Check if there are detected cooldowns and conditionally create bars for them in the specified bar group
local function DetectNewCooldowns(n, cd, bp, vbp, bg)
	local listID = nil
	if bp.showCooldown or bp.filterCooldown then -- check black lists and white lists
		local spellNum = cd[8] and ("#" .. tostring(cd[8])) -- string to look up the spell id in lists
		local listed = bp.filterCooldownList and (bp.filterCooldownList[n] or (spellNum and bp.filterCooldownList[spellNum]))
		if not listed then -- not found in the bar group's filter list, so check up spell lists
			local spellList = nil -- check the first spell list, if specified
			if bp.filterCooldownSpells and bp.filterCooldownTable then spellList = MOD.db.global.SpellLists[bp.filterCooldownTable] end
			if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end -- check first spell list, if specified
			if not listed then
				spellList = nil -- check second spell list, if specified
				if bp.filterCooldownSpells2 and bp.filterCooldownTable2 then spellList = MOD.db.global.SpellLists[bp.filterCooldownTable2] end
				if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
				if not listed then
					spellList = nil -- check third spell list, if specified
					if bp.filterCooldownSpells3 and bp.filterCooldownTable3 then spellList = MOD.db.global.SpellLists[bp.filterCooldownTable3] end
					if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
					if not listed then
						spellList = nil -- check fourth spell list, if specified
						if bp.filterCooldownSpells4 and bp.filterCooldownTable4 then spellList = MOD.db.global.SpellLists[bp.filterCooldownTable4] end
						if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
						if not listed then
							spellList = nil -- check fifth spell list, if specified
							if bp.filterCooldownSpells5 and bp.filterCooldownTable5 then spellList = MOD.db.global.SpellLists[bp.filterCooldownTable5] end
							if spellList then listed = spellList[n] or (spellNum and spellList[spellNum]) end
						end
					end
				end
			end
			if listed then listID = listed end -- if found in a spell list then save for tooltip display
		end
		if (bp.filterCooldown and listed) or (bp.showCooldown and not listed) then return end
	end
	if bp.filterCooldownBars and CheckFilterBarGroup(bp.filterCooldownBarGroup, "Cooldown", n, true) then return end -- check if in filter bar group
	if MOD:CheckCastBy(cd[7], bp.detectCooldownsBy) and CheckCooldownType(cd, bp) and CheckTimeAndDuration(bp, cd[1], cd[4]) then
		local b = detectedBar
		local label = MOD:GetLabel(n, cd[8])
		local tt = cd[5]
		if (tt == "alert") then b.barColor = cd[10] if cd[11] then label = cd[11] end end
		table.wipe(b); b.enableBar = true; b.sorder = 0
		b.action = n; b.spellID = cd[8]; b.barType = "Cooldown"; b.barLabel = label; b.uniqueID = "Cooldown"; b.listID = listID; b.group = nil
		b.isPlayer = (cd[7] == "player"); b.isPet = (cd[7] == "pet")
		if CheckSharedCooldowns(b, bp) then
			UpdateBar(bp, vbp, bg, b, cd[2], cd[1], cd[4], cd[9], nil, cd[5], cd[6], nil, nil, true)
		end
	end
end

-- Check the "show when" conditions specified for a bar group
-- Each condition (e.g., "in combat") is checked and if true then that condition must be enabled for the bar group
local function CheckShow(bp)
	local stat, pst = MOD.status, "solo"
	if GetNumGroupMembers() > 0 then if IsInRaid() then pst = "raid" else pst = "party" end end

	if InCinematic() or (MOD.ExpansionIsOrAbove(LE_EXPANSION_MISTS_OF_PANDARIA) and C_PetBattles.IsInBattle() and not bp.showPetBattle) or (UnitOnTaxi("player") and not bp.showOnTaxi) or
			(pst == "solo" and not bp.showSolo) or (pst == "party" and not bp.showParty) or (pst == "raid" and not bp.showRaid) or
			(stat.inCombat and not bp.showCombat) or (not stat.inCombat and not bp.showOOC) or
			(not MOD.db.profile.hideBlizz and not bp.showBlizz) or (MOD.db.profile.hideBlizz and not bp.showNotBlizz) or
			(stat.isResting and not bp.showResting) or (stat.isStealthed and not bp.showStealth) or
			(stat.isMounted and not bp.showMounted) or (stat.inVehicle and not bp.showVehicle) or
			(stat.targetEnemy and not bp.showEnemy) or (stat.targetFriend and not bp.showFriend) or (stat.targetNeutral and not bp.showNeutral) or
			(stat.inInstance and not bp.showInstance) or (not stat.inInstance and not bp.showNotInstance) or
			(stat.inArena and not bp.showArena) or (stat.inBattleground and not bp.showBattleground) or
			(UnitIsUnit("focus", "target") and not bp.showFocusTarget) or
			(bp.showClasses and bp.showClasses[MOD.myClass]) or
			(bp.showSpecialization and bp.showSpecialization ~= "" and not MOD.CheckSpec(bp.showSpecialization, bp.specializationList)) or
			(bp.checkCondition and IsOn(bp.condition) and not MOD:CheckCondition(bp.condition)) then return false end
	return true
end

-- Update all bars in bar group (bp), causing them to appear in display bar group (bg) using appearance options (vbp)
-- The show/hide conditions are tested in this function so they are depending on the updating bar group
local function UpdateBarGroupBars(bp, vbp, bg)
	if CheckShow(bp) then
		if bp.auto then -- if auto bar group then detect new auras and cooldowns
			if bp.detectBuffs then MOD:IterateAuras(bp.detectAllBuffs and "all" or bp.detectBuffsMonitor, DetectNewBuffs, true, bp, vbp, bg) end
			if bp.detectDebuffs then MOD:IterateAuras(bp.detectAllDebuffs and "all" or bp.detectDebuffsMonitor, DetectNewDebuffs, false, bp, vbp, bg) end
			if bp.detectCooldowns then MOD:IterateCooldowns(DetectNewCooldowns, bp, vbp, bg) end
			if bp.detectRuneCooldowns then AutoRuneBars(bp, vbp, bg) end
			if bp.detectTotems then AutoTotemBars(bp, vbp, bg) end

			if (not vbp.noHeaders or vbp.headerGaps) and ((bp.detectBuffs and bp.detectAllBuffs) or (bp.detectDebuffs and bp.detectAllDebuffs)) then -- add group headers, if necessary
				table.wipe(groupIDs) -- cache for group ids
				for _, bar in pairs(MOD.Nest_GetBars(bg)) do
					local id = bar.attributes.group
					local gname = bar.attributes.groupName
					if id and gname and bar.attributes.updated then groupIDs[id] = gname end
				end
				for id, name in pairs(groupIDs) do -- create the header bars (these get added even if just want the header gaps)
					local b, label = headerBar, name
					local rti = MOD:GetRaidTarget(id)
					if rti then label = prefixRaidTargetIcon .. rti .. ":0|t " .. name end
					table.wipe(b); b.enableBar = true; b.sorder = 0
					b.action = ""; b.spellID = nil; b.barLabel = label; b.barType = "Notification"
					b.uniqueID = id; b.group = id
					UpdateBar(bp, vbp, bg, b, nil, 0, 0, nil, nil, "header", name, id, nil, nil)
				end
			end
		else
			for _, bar in pairs(bp.bars) do -- iterate over each bar in the bar group
				local classCheck = not (bar.showClasses and bar.showClasses[MOD.myClass]) -- true if class is enabled
				local specCheck = not (bar.showSpecialization and bar.showSpecialization ~= "" and not MOD.CheckSpec(bar.showSpecialization, bar.specializationList))
				local hideCheck = IsOff(bar.hideBar) or (bar.hideBar ~= MOD:CheckCondition(bar.hideCondition)) -- true if hide condition not met
				if bar.enableBar and hideCheck and classCheck and specCheck then
					local bt = bar.barType
					local found = false
					if (bt == "Buff")  or (bt == "Debuff") then
						local aname, cb, saveLabel, count = bar.action, string.lower(bar.castBy), bar.barLabel, 0
						local auraList = MOD:CheckAura(bar.monitor, aname, bt == "Buff")
						if #auraList > 0 then
							for _, aura in pairs(auraList) do
								local isMine, isPet = (aura[6] == "player"), (aura[6] == "pet") -- enforce optional castBy restrictions
								local mon = ((cb == "player") and isMine) or ((cb == "pet") and isPet) or ((cb == "other") and not isMine) or (cb == "anyone")
								if mon and CheckTimeAndDuration(bp, aura[2], aura[5]) then
									if aura[11] == "minion" and aura[7] then bar.barLabel = bar.barLabel .. MinionEnergy(aura[7]) end -- add wild imp energy
									count = count + 1
									if count > 1 then bar.barLabel = bar.barLabel .. " " end -- add space at end to make unique
									bar.startReady = nil; bar.spellID = aura[14]
									UpdateBar(bp, vbp, bg, bar, aura[8], aura[2], aura[5], aura[3], aura[4], aura[11], aura[12], bar.monitor, aura[16], isMine)
									found = true
								end
							end
							bar.barLabel = saveLabel -- restore in case of multiple bar copies
						end
						if not found and bar.enableReady and aname then -- see if need aura ready bar
							if (bar.readyNotUsable or MOD:CheckSpellStatus(aname, true, true) or SHIM:IsUsableItem(aname)) then -- check if really usable
								if not bar.readyTime then bar.readyTime = 0 end
								if bar.readyTime == 0 then bar.startReady = nil end
								if not bar.startReady or ((GetTime() - bar.startReady) < bar.readyTime) then
									if not bar.startReady then bar.startReady = GetTime() end
									UpdateBar(bp, vbp, bg, bar, MOD:GetIcon(aname), 0, 0, nil, nil, "text", aname, nil, nil, nil)
								end
							end
						end
					elseif bt == "Cooldown" then
						local aname = bar.action
						local cd = MOD:CheckCooldown(aname) -- look up in the active cooldowns table
						if cd and (cd[1] ~= nil) then
							if CheckTimeAndDuration(bp, cd[1], cd[4]) then
								bar.startReady = nil; bar.spellID = cd[8]
								UpdateBar(bp, vbp, bg, bar, cd[2], cd[1], cd[4], cd[9], nil, cd[5], cd[6], nil, nil, true)
								found = true
							end
						end
						if not found and bar.enableReady and aname and (bar.readyNotUsable or MOD:CheckSpellStatus(aname, true) or SHIM:IsUsableItem(aname)) then -- see if need cooldown ready bar
							if not bar.readyTime then bar.readyTime = 0 end
							if bar.readyTime == 0 then bar.startReady = nil end
							if not bar.startReady or ((GetTime() - bar.startReady) < bar.readyTime) then
								if not bar.startReady then bar.startReady = GetTime() end
								local iname, _, _, _, _, _, _, _, _, icon = SHIM:GetItemInfo(aname)
								if not iname then icon = MOD:GetIcon(aname) end
								local _, charges = SHIM:GetSpellChargesByID(aname); if charges and charges <= 1 then charges = nil end -- show max charges on ready bar
								UpdateBar(bp, vbp, bg, bar, icon, 0, 0, charges, nil, "text", aname, nil, nil, true)
							end
						end
					elseif bt == "Notification" then
						if bar.unconditional or MOD:CheckCondition(bar.action) then
							bar.spellID = nil; bar.includeBar = true
							local icon = MOD:GetIconForBar(bar)
							if not icon then icon = defaultNotificationIcon end
							UpdateBar(bp, vbp, bg, bar, icon, 0, 0, nil, nil, "notification", bar.barLabel, bar.action, nil, true)
						end
					elseif bt == "Value" then
						local icon = nil
						if not bar.hideIcon then
							icon = MOD:GetIconForBar(bar)
							if not icon then icon = defaultValueIcon end
						end
						local name = bar.valueSelect
						local status = false
						if name then
							local f = MOD:GetValueFunction(name)
							if f then
								local unit = MOD:IsUnitValue(name) and bar.monitor or nil
								local fmt = bar.valueFormat or MOD:GetValueFormat(name)
								local status, value, maxValue, valueText, valueLabel, valueIcon, ttType, ttID, cr, cg, cb, offset = f(unit, fmt, bar.spell, bar.optionalText)
								if status then
									local isEmpty, isFull = false, false
									if value and maxValue then
										isEmpty = (value == 0) and (maxValue > 0)
										isFull = (maxValue > 0) and (value == maxValue)
									end
									if not (bar.hideWhenEmpty and isEmpty) and not (bar.hideWhenFull and isFull) then
										if bp.segmentBars then -- check if segmented bar group
											bar.segmentCount = nil -- this is used for segmented bars when configured to adjust settings
											if bar.adjustSegments then -- see if the bar is allowed to adjust settings
												if bp.segmentOverride then -- see if bar group allows override with bar settings
													bar.segmentCount = maxValue
												else -- if can't override then adjust maxValue based on actual number of segments
													if maxValue < bp.segmentCount then maxValue = bp.segmentCount end
												end
											end
										end
										if not bar.hideValueIcon then icon = valueIcon end
										local noLabel = (bar.hideEmptyLabel and isEmpty) or (bar.hideFullLabel and isFull)
										if noLabel then valueLabel = "" elseif bar.hideValueLabel then valueLabel = nil end
										local noText = bar.hideFormatText or (bar.hideEmptyText and isEmpty) or (bar.hideFullText and isFull)
										if noText then valueText = "" elseif bar.hideValueText then valueText = nil end
										bar.value = value; bar.maxValue = maxValue; bar.valueText = valueText; bar.valueLabel = valueLabel
										bar.value_r = cr; bar.value_g = cg; bar.value_b = cb; bar.tickOffset = offset
										UpdateBar(bp, vbp, bg, bar, icon, 0, 0, nil, nil, ttType or "text", ttID or bar.barLabel, nil, nil, true)
									end
								end
							end
						end
					elseif bt == "Broker" and bar.action then
						local db = MOD.knownBrokers[bar.action] -- check in the registered brokers table
						if db then
							bar.spellID = nil
							local icon = nil
							if not bar.hideIcon then
								icon = db.icon
								if not icon then icon = defaultBrokerIcon end
							end
							bar.value = nil; bar.maxValue = nil; bar.valueText = nil
							local count = nil
							local s = db.text
							if bar.hideText or not s then
								if bar.brokerLabel then
									s = db.label
									if not s then s = MOD.LibLDB:GetNameByDataObject(db) end
									if bar.recolorText then s = uncolor(s) end
								else
									s = ""
								end
								bar.barText = s
							else
								if bar.recolorText then s = uncolor(s) end
								bar.barText = s
								if bar.brokerLabel then
									s = db.label
									if not s then s = MOD.LibLDB:GetNameByDataObject(db) end
									if bar.recolorText then s = uncolor(s) end
									if bar.barText == "" then bar.barText = s else bar.barText = s .. ": " .. bar.barText end
								end
							end
							local s = db.value or db.text
							if s then
								local n = string.gsub(uncolor(s), ",", "") -- remove escape sequences and commas
								n = string.match(n, "(%d+%.?%d*)") -- extract number from the string, if any
								if bar.brokerValue then
									if bar.brokerNumber then count = n else count = s end
								end
								if n then
									if bar.brokerPercentage then
										local pct = (tonumber(n) or 0) / 100
										bar.value = pct; bar.maxValue = 1
									elseif bar.brokerMaximum and bar.brokerMaxValue then
										local m = tonumber(bar.brokerMaxValue) or 0
										if m > 0 then
											bar.value = tonumber(n) or 0
											bar.maxValue = m
											bar.valueText = (bar.recolorText and "Max: " or "|cFF7adbf2Max:|r ") .. tostring(bar.maxValue)
										end
									end
								end
							end
							UpdateBar(bp, vbp, bg, bar, icon, 0, 0, count, nil, "broker", db, nil, nil, true)
						end
					end
				end
			end
		end
	end
end

-- Look for expired timer bars and show final effects (ghost bars, splash effects)
local function UpdateFinalEffects(bp, bg)
	local now = GetTime()
	table.wipe(activeSpells) -- this table will be used to track which spells have currently active timer bars so don't show effects for them
	for _, bar in pairs(MOD.Nest_GetBars(bg)) do -- first, find any elapsed timer bars and build table of active spells
		if MOD.Nest_IsTimer(bar) then
			local bat = bar.attributes
			if bat.updated then
				if bar.timeLeft == 0 then bat.updated = false elseif bat.tooltipSpell then activeSpells[bat.tooltipSpell] = true end
			end
		end
	end

	for _, bar in pairs(MOD.Nest_GetBars(bg)) do -- second, create ghost bars or trigger splash effects for expired timer bars
		if MOD.Nest_IsTimer(bar) then
			local bat = bar.attributes
			if not bp.auto then -- if custom bar group check for individual bar ghost option (overrides bar group option)
				if bat.ghostDuration and not bat.updated and not activeSpells[bat.tooltipSpell or 0] then -- check if candidate for ghost bar
					if not bat.ghostTime then MOD.Nest_SetCount(bar, nil); bat.ghostTime = now + bat.ghostDuration end
					if bat.ghostTime >= now then bat.updated = true end
				end
			elseif bp.ghost then -- for auto bars, if ghost enabled, any elapsed timer is a potential ghost bar
				if not bat.updated and not activeSpells[bat.tooltipSpell or 0] then
					if not bat.ghostTime then MOD.Nest_SetCount(bar, nil); bat.ghostTime = now + (bp.endEffectTime or 5) end
					if bat.ghostTime >= now then bat.updated = true end
				end
			end
			if bat.splash and not bat.updated and not activeSpells[bat.tooltipSpell or 0] then -- trigger splash effect
				MOD.Nest_SplashEffect(bg, bar)
			end
		end
	end
end

-- Update bars in all bar groups, checking for bar group visibility and removing expired bars
function MOD:UpdateBars()
	if hidden then -- if was hidden then need to re-initialize all bar groups
		hidden = false
		MOD:UpdateAllBarGroups()
	end

	-- cache the icon for the player's tabard, if any, to support filtering tabard spells
	local itemID = GetInventoryItemID("player", INVSLOT_TABARD)
	if itemID then tabardIcon = SHIM:GetItemIconByID(itemID) else tabardIcon = nil end

	table.wipe(frequentBars) -- clear the table of frequent bars, it will be rebuilt during update

	for _, bp in pairs(MOD.db.profile.BarGroups) do -- iterate through the all bar groups
		if IsOn(bp) then
			local bg = MOD.Nest_GetBarGroup(bp.name) -- match the profile bar group to the graphics library bar group
			if bg then
				if bp.enabled then -- check all the conditions under which the bar group might be hidden are not true
					MOD.Nest_SetAllAttributes(bg, "updated", false) -- first, mark all the bars in the group as not updated...
					if not bp.merged then
						UpdateBarGroupBars(bp, bp, bg) -- then update all the bars for the bar group into the display bar group
						for _, mbp in pairs(MOD.db.profile.BarGroups) do -- then look for bar groups merging into this bar group
							if IsOn(mbp) and mbp.enabled and mbp.merged and (mbp.mergeInto == bp.name) then
								UpdateBarGroupBars(mbp, bp, bg) -- update all bars for merged bar group into same display bar group
							end
						end
						MOD.Nest_SetBarGroupAlpha(bg, MOD.status.inCombat and bp.bgCombatAlpha or bp.bgNormalAlpha, bp.mouseAlpha, bp.disableAlpha)
						ShowStripe(bp, bg) -- deferred to make sure condition is valid
					end
					UpdateFinalEffects(bp, bg) -- create and/or update ghost bars in this bar group
					UpdateTestBars(bp, bg) -- update any unexpired test bars in this bar group
					MOD.Nest_DeleteBarsWithAttribute(bg, "updated", false) -- then, remove any bars in the group that weren't updated
				else -- if not then hide any bars that might be around
					MOD.Nest_DeleteAllBars(bg)
				end
			end
		end
	end
	MOD:UpdatePositions()
end

-- Refresh any value bars tagged for frequent updates
function MOD:RefreshBars()
	for b, bar in pairs(frequentBars) do -- special table with value bars flagged in previous update
		local name = b.valueSelect
		if name then
			local f = MOD:GetValueFunction(name)
			if f then
				local unit = MOD:IsUnitValue(name) and b.monitor or nil
				local fmt = b.valueFormat or MOD:GetValueFormat(name)
				local status, value, maxValue, valueText, valueLabel = f(unit and b.monitor or nil, fmt, b.spell, b.optionalText)
				if status then
					local isEmpty, isFull = false, false
					if value and maxValue then
						isEmpty = (value == 0) and (maxValue > 0)
						isFull = (maxValue > 0) and (value == maxValue)
					end
					if (value ~= b.value) and (value <= b.maxValue) then
						local noLabel = (b.hideEmptyLabel and isEmpty) or (b.hideFullLabel and isFull)
						if noLabel then valueLabel = "" elseif b.hideValueLabel then valueLabel = nil end
						local noText = b.hideFormatText or (b.hideEmptyText and isEmpty) or (b.hideFullText and isFull)
						if noText then valueText = "" elseif b.hideValueText then valueText = nil end
						b.value = value; b.valueText = valueText; b.valueLabel = valueLabel -- never update maxValue during refreshes
						MOD.Nest_SetValue(bar, value, b.maxValue, b.valueText, b.valueLabel, b.includeBar, 0) -- refresh value bars
					end
				end
			end
		end
	end
end
