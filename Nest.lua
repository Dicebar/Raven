-- Nest is a graphics package that is optimized to display Raven's bar groups.
-- Bar groups share layout and appearance options (dimensions, fonts, textures, colors, configuration, special effects).
-- Each bar has a fixed set of graphical components (icon, iconText, foreground bar, background bar, labelText, timeText, spark).

local MOD = Raven
local SHIM = MOD.SHIM
local L = LibStub("AceLocale-3.0"):GetLocale("Raven")

MOD.Nest_SupportedConfigurations = { -- table of configurations can be used in dialogs to select appropriate options
	[1] = { name = L["Right-to-left bars, label left, icon left"], iconOnly = false, bars = "r2l", label = "left", icon = "left" },
	[2] = { name = L["Left-to-right bars, label left, icon left"], iconOnly = false, bars = "l2r", label = "left", icon = "left" },
	[3] = { name = L["Right-to-left bars, label right, icon left"], iconOnly = false, bars = "r2l", label = "right", icon = "left" },
	[4] = { name = L["Left-to-right bars, label right, icon left"], iconOnly = false, bars = "l2r", label = "right", icon = "left" },
	[5] = { name = L["Right-to-left bars, label left, icon right"], iconOnly = false, bars = "r2l", label = "left", icon = "right" },
	[6] = { name = L["Left-to-right bars, label left, icon right"], iconOnly = false, bars = "l2r", label = "left", icon = "right" },
	[7] = { name = L["Right-to-left bars, label right, icon right"], iconOnly = false, bars = "r2l", label = "right", icon = "right" },
	[8] = { name = L["Left-to-right bars, label right, icon right"], iconOnly = false, bars = "l2r", label = "right", icon = "right" },
	[9] = { name = L["Icons in rows, with right-to-left mini-bars"], iconOnly = true, bars = "r2l", orientation = "horizontal" },
	[10] = { name = L["Icons in rows, with left-to-right mini-bars"], iconOnly = true, bars = "l2r", orientation = "horizontal" },
	[11] = { name = L["Icons in columns, right-to-left mini-bars"], iconOnly = true, bars = "r2l", orientation = "vertical" },
	[12] = { name = L["Icons in columns, left-to-right mini-bars"], iconOnly = true, bars = "l2r", orientation = "vertical" },
	[13] = { name = L["Icons on horizontal timeline, no mini-bars"], iconOnly = true, bars = "timeline", orientation = "horizontal" },
	[14] = { name = L["Icons on vertical timeline, no mini-bars"], iconOnly = true, bars = "timeline", orientation = "vertical" },
	[15] = { name = L["Icons with variable width on horizontal stripe"], iconOnly = true, bars = "stripe", orientation = "horizontal" },
}
MOD.Nest_MaxBarConfiguration = 8

local barGroups = {} -- current barGroups
local usedBarGroups = {} -- cache of recycled barGroups
local usedBars = {} -- cache of recycled bars
local update = false -- set whenever a global change has occured
local buttonName = 0 -- incremented for each button created
local callbacks = {} -- registered callback functions
local splashAnimationPool = {} -- pool of available bar animations
local splashAnimations = {} -- active bar animations
local shineEffectPool = {} -- pool of available shine animations
local sparkleEffectPool = {} -- pool of available sparkle animations
local pulseEffectPool = {} -- pool of available pulse animations
local glowEffectPool = {} -- pool of available glow animations
local displayWidth, displayHeight = UIParent:GetWidth(), UIParent:GetHeight()
local defaultBackdropColor = { r = 1, g = 1, b = 1, a = 1 }
local defaultGreen = { r = 0, g = 1, b = 0, a = 1 }
local defaultRed = { r = 1, g = 0, b = 0, a = 1 }
local defaultBlack = { r = 0, g = 0, b = 0, a = 1 }
local pixelScale = 1 -- adjusted by screen resolution and uiScale
local pixelPerfect -- global setting to enable pixel perfect size and position
local pixelWidth, pixelHeight = 0, 0 -- actual screen resolution
local rectIcons = false -- allow rectangular icons
local zoomIcons = false -- zoom rectangular icons
local inPetBattle = nil
local alignLeft = {} -- table of icons to be aligned left
local alignRight = {} -- table of icons to be aligned right
local alignCenter = {} -- table of icons to be aligned center
local customTimeFormatIndex = nil -- when defined, this is the index for custom time formats in the options list
local userDefinedTimeFormatFunction = nil -- this is the user-defined function for custom time formats

local MSQ = nil -- Masque support
local MSQ_ButtonData = nil
local CS = CreateFrame("ColorSelect")

local textures = {
	["circle"] = [[Interface\Addons\Raven\Icons\Circle.tga]],
	["diamond"] = [[Interface\Addons\Raven\Icons\Diamond.tga]],
	["triangle"] = [[Interface\Addons\Raven\Icons\Triangle.tga]],
	["trapezoid"] = [[Interface\Addons\Raven\Icons\Trapezoid.tga]],
}

local ANCHOR_TILESIZE, ANCHOR_EDGESIZE = 8, 6
local anchorDefaults = { -- backdrop initialization for bar group anchors
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = [[Interface\Addons\Raven\Borders\Rounded.tga]],
	tile = true, tileSize = ANCHOR_TILESIZE, edgeSize = ANCHOR_EDGESIZE, insets = { left = 0, right = 0, top = 0, bottom = 0 }
}

local iconBackdrop = { -- backdrop initialization for icons when using optional border customization
	bgFile = [[Interface\Addons\Raven\Statusbars\White.tga]],
	edgeFile = [[Interface\BUTTONS\WHITE8X8.blp]], edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 }
}

local bgTemplate = { -- these fields are preserved when a bar group is deleted
	attributes = 0, callbacks = 0, frame = 0, backdrop = 0, backdropTable = 0, borderTable = 0, anchor = 0, bars = 0,
	position = 0, sorter = 0, sortFunction = 0, locked = 0, moving = 0, count = 0,
}

local barTemplate = { -- these fields are preserved when a bar is deleted
	buttonName = 0, attributes = 0, callbacks = 0, frame = 0, container = 0, fgTexture = 0, bgTexture = 0, backdrop = 0, spark = 0, tick = 0,
	textFrame = 0, tipFrame = 0, labelText = 0, timeText = 0, icon = 0, iconTexture = 0, cooldown = 0, iconTextFrame = 0, iconText = 0, iconBorder = 0,
	tukbar = 0, tukcolor_r = 0, tukcolor_g = 0, tukcolor_b = 0, tukcolor_a = 0, buttonData = 0, segments = 0, segmentsAllocated = 0,
}

-- Check if using Tukui skin for icon and bar borders (which may require a reloadui)
local function UseTukui()
	if Raven.frame then
		return Raven.frame.CreateBackdrop and Raven.frame.SetOutside and Raven.db.global.TukuiSkin
	end
	return nil
end
local function GetTukuiFont(font) if Raven.db.global.TukuiFont and ChatFrame1 then return ChatFrame1:GetFont() else return font end end
local function PS(x) if pixelPerfect and type(x) == "number" then return pixelScale * math.floor(x / pixelScale + 0.5) else return x end end

local function PSetSize(frame, w, h)
	if pixelPerfect then
		if w then w = pixelScale * math.floor(w / pixelScale + 0.5) end
		if h then h = pixelScale * math.floor(h / pixelScale + 0.5) end
	end
	frame:SetSize(w, h)
end

local function PSetWidth(region, w) if pixelPerfect and w then w = pixelScale * math.floor(w / pixelScale + 0.5) end region:SetWidth(w) end
local function PSetHeight(region, h) if pixelPerfect and h then h = pixelScale * math.floor(h / pixelScale + 0.5) end region:SetHeight(h) end

local function PCSetPoint(frame, point, relativeFrame, relativePoint, x, y)
	frame:ClearAllPoints()
	if pixelPerfect then
		if x then x = pixelScale * math.floor(x / pixelScale + 0.5) end
		if y then y = pixelScale * math.floor(y / pixelScale + 0.5) end
	end
	frame:SetPoint(point, relativeFrame, relativePoint, x or 0, y or 0)
end

local function PSetPoint(frame, point, relativeFrame, relativePoint, x, y)
	if pixelPerfect then
		if x then x = pixelScale * math.floor(x / pixelScale + 0.5) end
		if y then y = pixelScale * math.floor(y / pixelScale + 0.5) end
	end
	frame:SetPoint(point, relativeFrame, relativePoint, x or 0, y or 0)
end

-- Trim and scale icon, including for optional rectangular dimensions
local function IconTextureTrim(tex, icon, trim, w, h)
	local left, right, top, bottom = 0, 1, 0, 1 -- default without trim
	if trim then left = 0.07; right = 0.93; top = 0.07; bottom = 0.93 end -- trim removes 7% of edges
	if zoomIcons then -- only true if both rectangular and zoom icons enabled
		if w > h then -- rectangular with width greater than height
			local crop = (bottom - top) * (w - h)/ w / 2 -- aspect ratio to reduce height by
			top = top + crop; bottom = bottom - crop
		elseif h > w then -- rectangular with height greater than width
			local crop = (right - left) * (h - w)/ h / 2 -- aspect ratio to reduce height by
			left = left + crop; right = right - crop
		end
	end
	tex:SetTexCoord(left, right, top, bottom) -- set the corner coordinates
	PSetSize(tex, w, h)
	PSetPoint(tex, "CENTER", icon, "CENTER") -- texture is always positioned in center of icon's frame
end

-- Calculate alpha for flashing bars, period is how long the total flash time should last
function MOD.Nest_FlashAlpha(maxAlpha, minAlpha, period)
	local frac = GetTime() / period
	frac = frac - math.floor(frac) -- get fractional part of current period
	if frac >= 0.5 then frac = 1 - frac end -- now goes from 0 to 0.5 then back to 0
	frac = frac * 2 -- adjust frac to range from 0 to 1
	local alpha = minAlpha + (frac * (maxAlpha - minAlpha)) -- adjust alpha within range from minAlpha to maxAlpha
	return alpha
end

-- Set and confirm frame level, working around potential bug when raising frame level above internal limits
local function SetFrameLevel(frame, level)
	local i = 0
	repeat
		frame:SetFrameLevel(level); local a = frame:GetFrameLevel()
		i = i + 1; if i > 10 then print("Raven: warning SetFrameLevel failed"); return end
	until level == a
end

-- Validate that have a valid font reference
local function ValidFont(name)
	local result = (name and (type(name) == "string") and (name ~= ""))
	return result
end

-- Initialize and return a bar splash-style animation based on the icon texture
-- If anchor info is not passed in then splash will be centered over the bar's icon
local function SplashEffect(bar, anchor1, frame, anchor2, xoffset, yoffset)
	local tex = bar.iconTexture:GetTexture(); if not tex then return end
	local w, h = bar.icon:GetSize()
	local b = next(splashAnimationPool)
	if b then splashAnimationPool[b] = nil else
		b = {} -- initialize a new animation
		b.frame = CreateFrame("Frame", nil, UIParent)
		b.frame:SetFrameLevel(bar.frame:GetFrameLevel() + 10)
		b.texture = b.frame:CreateTexture(nil, "ARTWORK") -- texture for the texture to be animated
		b.maskTexture = b.frame:CreateMaskTexture()
		b.maskTexture:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
		b.maskTexture:SetAllPoints(b.frame)
		b.masked = false
		b.anim = b.frame:CreateAnimationGroup()
		b.anim:SetLooping("NONE")
		local scale = b.anim:CreateAnimation("Scale")
		scale:SetScale(3, 3); scale:SetOrigin("CENTER", 0, 0); scale:SetDuration(0.65); scale:SetOrder(1)
		local alpha = b.anim:CreateAnimation("Alpha")
		alpha:SetFromAlpha(1); alpha:SetToAlpha(0) -- LEGION change
		alpha:SetDuration(0.65); alpha:SetSmoothing("IN"); alpha:SetEndDelay(5); alpha:SetOrder(1)
	end
	local w, h = bar.icon:GetSize()
	PSetSize(b.frame, w, h)
	if frame then
		PCSetPoint(b.frame, anchor1 or "CENTER", frame, anchor2 or "CENTER", xoffset or 0, yoffset or 0)
	else -- not provided a reference point so use position of bar's icon
		PCSetPoint(b.frame, "BOTTOMLEFT", nil, "BOTTOMLEFT", bar.icon:GetLeft(), bar.icon:GetBottom())
	end
	b.frame:Show()
	b.texture:SetTexture(tex)
	IconTextureTrim(b.texture, bar.icon, true, w - 2, h - 2)
	if MSQ and (bar.icon.__MSQ_Shape == "Circle") then
		if not b.masked then -- check if need a mask texture and not already masked
			b.texture:AddMaskTexture(b.maskTexture)
			PSetSize(b.maskTexture, w, h)
			b.masked = true
		end
	else
		if b.masked then -- check if need to remove a previously added mask texture
			b.texture:RemoveMaskTexture(b.maskTexture)
			b.masked = false
		end
	end
	b.texture:ClearAllPoints(); b.texture:SetAllPoints(b.frame); b.texture:Show()
	b.anim:Stop(); b.anim:Play()
	b.endTime = GetTime() + 1 -- stop after one second
	table.insert(splashAnimations, b)
end

-- Update active bar animations, recycling when they are complete
local function UpdateSplashAnimations()
	local now = GetTime()
	for k, b in pairs(splashAnimations) do
		if now > b.endTime then
			b.anim:Pause(); splashAnimations[k] = nil; splashAnimationPool[b] = true
			b.frame:ClearAllPoints(); b.texture:ClearAllPoints(); b.frame:Hide(); b.texture:Hide()
		end
	end
end

-- Show splash effect for a bar
function MOD.Nest_SplashEffect(bg, bar)
	SplashEffect(bar)
end

-- Pulse animation on the bar icon
local function PulseEffect(bar)
	local tex = bar.iconTexture:GetTexture(); if not tex then return end
	local w, h = bar.icon:GetSize()
	local a = bar.pulseEffect -- get an animation if one has already been allocated for this bar
	if not a then -- allocate an animation if necessary
		a = next(pulseEffectPool) -- get one from the recycling pool if available
		if a then pulseEffectPool[a] = nil else
			a = {} -- initialize a new animation for this pulse effect
			a.frame = CreateFrame("Frame", nil, UIParent)
			a.texture = a.frame:CreateTexture(nil, "ARTWORK") -- texture to be animated
			a.maskTexture = a.frame:CreateMaskTexture()
			a.maskTexture:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
			a.maskTexture:SetAllPoints(a.frame)
			a.masked = false
			a.anim = a.frame:CreateAnimationGroup()
			a.anim:SetLooping("NONE")
			local alpha1 = a.anim:CreateAnimation("Alpha")
			alpha1:SetFromAlpha(0); alpha1:SetToAlpha(1); alpha1:SetDuration(0.05); alpha1:SetOrder(1)
			local grow = a.anim:CreateAnimation("Scale")
			grow:SetScale(3, 3); grow:SetOrigin('CENTER', 0, 0); grow:SetDuration(0.25); grow:SetOrder(1)
			local shrink = a.anim:CreateAnimation("Scale")
			shrink:SetScale(-3, -3); shrink:SetOrigin('CENTER', 0, 0); shrink:SetDuration(0.25); shrink:SetOrder(2)
			local alpha2 = a.anim:CreateAnimation("Alpha")
			alpha2:SetFromAlpha(1); alpha2:SetToAlpha(0); alpha2:SetDuration(0.05); alpha2:SetOrder(3)
		end
		a.frame:ClearAllPoints()
		a.frame:SetFrameStrata(bar.frame:GetFrameStrata())
		a.frame:SetFrameLevel(bar.frame:GetFrameLevel() + 10)
		local w, h = bar.icon:GetSize()
		PSetSize(a.frame, w, h)
		PCSetPoint(a.frame, "CENTER", bar.icon, "CENTER", 0, 0)
		a.texture:SetAllPoints(a.frame)
		a.frame:SetAlpha(0)
		a.frame:Show(); a.texture:Show()
		bar.pulseEffect = a
	end
	if not a.anim:IsPlaying() then
		a.texture:SetTexture(tex)
		IconTextureTrim(a.texture, bar.icon, true, w - 2, h - 2)
		if MSQ and (bar.icon.__MSQ_Shape == "Circle") then
			if not a.masked then -- check if need a mask texture and not already masked
				a.texture:AddMaskTexture(a.maskTexture)
				PSetSize(a.maskTexture, w, h)
				a.masked = true
			end
		else
			if a.masked then -- check if need to remove a previously added mask texture
				a.texture:RemoveMaskTexture(a.maskTexture)
				a.masked = false
			end
		end
		a.anim:Stop(); a.anim:Play()
	end
end

local function ReleasePulseEffect(bar)
	local a = bar.pulseEffect -- get the pulse animation, if any, that is allocated for this bar
	if a then
		a.anim:Stop(); a.frame:ClearAllPoints(); a.texture:Hide(); a.frame:Hide()
		pulseEffectPool[a] = true
		bar.pulseEffect = nil
	end
end

-- Fader to change from current to a new alpha
local function FaderEffect(bar, toAlpha, fade)
	local anim = bar.frame.fader
	if not anim then
		anim = bar.frame:CreateAnimationGroup()
		anim:SetLooping("NONE")
		local alpha = anim:CreateAnimation("Alpha")
		alpha:SetFromAlpha(1); alpha:SetToAlpha(1); alpha:SetDuration(0.1); alpha:SetOrder(1)
		anim.alpha = alpha
		anim:SetToFinalAlpha(true)
		bar.frame.fader = anim
	end

	local isPlaying = anim:IsPlaying()
	local alpha = anim.alpha
	local current = bar.frame:GetAlpha() -- actual current alpha for the bar
	local fromAlpha = isPlaying and alpha:GetToAlpha() or current -- for comparison, check target alpha if animation is playing otherwise use current
	local delta = math.floor(math.abs(fromAlpha - toAlpha) * 100) -- zero if comparison is within 1% of same value

	if not fade then -- just go straight to the target alpha if fade is disabled
		if isPlaying then anim:Stop() end
		bar.frame:SetAlpha(toAlpha)
	else
		if delta > 0 then -- use fader animation to get to target alpha
			if isPlaying then anim:Stop() end -- need to restart the animation with new values if it is playing
			alpha:SetFromAlpha(current); alpha:SetToAlpha(toAlpha)
			anim:Play()
		elseif not isPlaying then
			bar.frame:SetAlpha(toAlpha) -- pretty close so just go straight there to finish up
		end
	end
end

local function ReleaseFaderEffect(bar)
	local anim = bar.frame.fader
	if anim then anim:Stop() end
end

local function FlashEffectAlphaOnUpdate(anim,elapsed)
	local bar = anim.bar
	if not bar then return end
	-- function to get current alpha for all flashing bars
	local newAlpha = MOD.Nest_FlashAlpha(bar.alpha,bar.minAlpha,bar.flashPeriod)
	bar.frame:SetAlpha(newAlpha)
end

-- Flash effect to change bar alpha in a noticeable way
local function FlashEffect(bar)
	local anim = bar.frame.flasher
	if not anim then
		anim = bar.frame:CreateAnimationGroup()
		anim:SetLooping("REPEAT")
		local a = anim:CreateAnimation("Animation") -- use animation to trigger associated OnUpdate script
		a:SetDuration(1); a:SetOrder(1) -- this is done so that flashing bars can be synchronized
		bar.frame.flasher = anim
		anim.bar = bar
	end

	if anim.maxAlpha ~= bar.alpha or anim.minAlpha ~= bar.minAlpha or anim.flashPeriod ~= bar.flashPeriod then
		anim:SetScript("OnUpdate", FlashEffectAlphaOnUpdate)
		anim.maxAlpha = bar.alpha; anim.minAlpha = bar.minAlpha; anim.flashPeriod = bar.flashPeriod
	end

	if not anim:IsPlaying() then anim:Stop(); anim:Play() end
end

local function ReleaseFlashEffect(bar)
	local anim = bar.frame.flasher
	if anim then anim:Stop() end
end

-- Add a shine effect over a bar's icon
-- If color is set then apply it to the animation
local function ShineEffect(bar, color)
	local a = bar.shineEffect -- get an animation if one has already been allocated for this bar
	if not a then -- allocate an animation if necessary
		a = next(shineEffectPool) -- get one from the recycling pool if available
		if a then shineEffectPool[a] = nil else
			a = {} -- initialize a new animation for this shine effect
			a.frame = CreateFrame("Frame", nil, UIParent)
			a.texture = a.frame:CreateTexture(nil, "ARTWORK") -- texture to be animated
			a.texture:SetTexture("Interface\\Cooldown\\star4")
			a.texture:SetBlendMode("ADD")
			a.anim = a.frame:CreateAnimationGroup()
			a.anim:SetLooping("NONE")
			local alpha1 = a.anim:CreateAnimation("Alpha")
			alpha1:SetFromAlpha(0); alpha1:SetToAlpha(1); alpha1:SetDuration(0.05); alpha1:SetOrder(1)
			local scale1 = a.anim:CreateAnimation("Scale")
			scale1:SetScale(2, 2); scale1:SetDuration(0.05); scale1:SetOrder(1)
			local scale2 = a.anim:CreateAnimation("Scale")
			scale2:SetScale(0.1, 0.1); scale2:SetDuration(0.5); scale2:SetOrder(2)
			local rotation = a.anim:CreateAnimation("Rotation")
			rotation:SetDegrees(135); rotation:SetDuration(0.5); rotation:SetOrder(2)
			local alpha2 = a.anim:CreateAnimation("Alpha")
			alpha2:SetFromAlpha(1); alpha2:SetToAlpha(0); alpha2:SetDuration(0.05); alpha2:SetOrder(3)
		end
		a.frame:ClearAllPoints()
		a.frame:SetFrameStrata(bar.frame:GetFrameStrata())
		a.frame:SetFrameLevel(bar.frame:GetFrameLevel() + 10)
		local w, h = bar.icon:GetSize()
		PSetSize(a.frame, w, h)
		PCSetPoint(a.frame, "CENTER", bar.icon, "CENTER", 0, 0)
		a.texture:SetAllPoints(a.frame)
		a.frame:SetAlpha(0)
		a.frame:Show(); a.texture:Show()
		bar.shineEffect = a
	end
	if not a.anim:IsPlaying() then
		local r, g, b = 1, 1, 1
		if color then r = color.r; g = color.g; b = color.b end
		a.texture:SetVertexColor(r, g, b, 1) -- add color to the texture
		a.anim:Stop(); a.anim:Play()
	end
end

-- When a bar is deleted then release allocated shine animation, if any
local function ReleaseShineEffect(bar)
	local a = bar.shineEffect -- get the shine animation, if any, that is allocated for this bar
	if a then
		a.anim:Stop(); a.frame:ClearAllPoints(); a.texture:Hide(); a.frame:Hide()
		shineEffectPool[a] = true
		bar.shineEffect = nil
	end
end

-- Configuration table for sparklers used in sparkle effect
local sparkleCount = 0
local sparkles = {
	[1] = { x = 0.9, y = 0.9, scale = 1, delay = 0, duration = 0.5 },
	[2] = { x = -0.9, y = -0.9, scale = 1, delay = 0, duration = 0.5 },
	[3] = { x = 1, y = -1, scale = 0.5, delay = 0.1, duration = 0.5 },
	[4] = { x = -1, y = 1, scale = 0.5, delay = 0.1, duration = 0.5 },
	[5] = { x = 0, y = 1.5, scale = 0.5, delay = 0.2, duration = 0.4 },
	[6] = { x = 0, y = -1.5, scale = 0.5, delay = 0.2, duration = 0.4 },
	[7] = { x = -1, y = 0, scale = 1, delay = 0.2, duration = 0.4 },
	[8] = { x = 1, y = 0, scale = 1, delay = 0.2, duration = 0.4 },
}

-- Add a sparkle effect over a bar's icon
-- If color is set then apply it to the animation
local function SparkleEffect(bar, color)
	local a = bar.sparkleEffect -- get an animation if one has already been allocated for this bar
	if not a then -- allocate an animation if necessary
		a = next(sparkleEffectPool) -- get one from the recycling pool if available
		if a then sparkleEffectPool[a] = nil else
			sparkleCount = sparkleCount + 1
			a = {} -- initialize a new animation for this sparkle effect
			a.frame = CreateFrame("Frame", nil, UIParent)
			a.texture = a.frame:CreateTexture(nil, "ARTWORK") -- texture to be animated
			a.texture:SetTexture("Interface\\Cooldown\\starburst")
			a.texture:SetBlendMode("ADD")
			a.sparkleTextures = {}
			a.sparkleTranslators = {}
			a.anim = a.frame:CreateAnimationGroup()
			a.anim:SetLooping("NONE")
			a.anim:SetToFinalAlpha(true)

			local x = a.anim:CreateAnimation("Alpha")
			x:SetFromAlpha(0); x:SetToAlpha(1); x:SetDuration(0.15); x:SetOrder(1)
			x = a.anim:CreateAnimation("Scale")
			x:SetScale(1, 1); x:SetDuration(0.33); x:SetOrder(1)
			x = a.anim:CreateAnimation("Alpha")
			x:SetFromAlpha(1); x:SetToAlpha(0); x:SetStartDelay(0.45); x:SetDuration(0.15); x:SetOrder(1)

			for i = 1, 8 do -- create sparklers
				local name = "Raven_Animation" .. tostring(sparkleCount) .. "_Spark" .. tostring(i)
				local animTarget = a.frame:CreateTexture(name, "ARTWORK") -- texture to be animated
				animTarget:SetTexture("Interface\\Cooldown\\star4")
				animTarget:SetBlendMode("ADD")
				a.sparkleTextures[i] = animTarget
				local s = sparkles[i]

				x = a.anim:CreateAnimation("Alpha")
				x:SetTarget(animTarget); x:SetFromAlpha(0); x:SetToAlpha(1); x:SetSmoothing("IN")
				x:SetStartDelay(s.delay); x:SetDuration(0.15); x:SetOrder(1)

				x = a.anim:CreateAnimation("Alpha")
				x:SetTarget(animTarget); x:SetFromAlpha(1); x:SetToAlpha(0.25); x:SetSmoothing("OUT")
				x:SetStartDelay(s.delay + s.duration - 0.15); x:SetDuration(0.15); x:SetOrder(1)

				x = a.anim:CreateAnimation("Rotation")
				x:SetTarget(animTarget); x:SetDegrees(60); x:SetStartDelay(s.delay); x:SetDuration(s.duration); x:SetOrder(1)

				x = a.anim:CreateAnimation("Scale")
				x:SetTarget(animTarget); x:SetScale(s.scale, s.scale); x:SetStartDelay(s.delay); x:SetDuration(0.25); x:SetOrder(1); x:SetSmoothing("IN")

				x = a.anim:CreateAnimation("Scale")
				x:SetTarget(animTarget); x:SetScale(0.1, 0.1); x:SetStartDelay(s.delay + s.duration - 0.25); x:SetDuration(0.25); x:SetOrder(1); x:SetSmoothing("OUT")

				x = a.anim:CreateAnimation("Translation")
				x:SetTarget(animTarget); x:SetOffset(s.x, s.y)
				x:SetStartDelay(s.delay); x:SetDuration(0.5); x:SetOrder(1)
				a.sparkleTranslators[i] = x -- save to set size
			end
		end
		a.frame:ClearAllPoints()
		a.frame:SetFrameStrata(bar.frame:GetFrameStrata())
		a.frame:SetFrameLevel(bar.frame:GetFrameLevel() + 10)
		local w, h = bar.icon:GetSize()
		PSetSize(a.frame, w, h)
		PCSetPoint(a.frame, "CENTER", bar.icon, "CENTER", 0, 0)
		a.texture:SetAllPoints(a.frame)
		a.frame:SetAlpha(0)
		a.frame:Show(); a.texture:Show()
		for i = 1, 8 do
			local x = a.sparkleTranslators[i]
			local s = sparkles[i]
			x:SetOffset(w * s.x * 0.75, h * s.y * 0.75)
			local tex = a.sparkleTextures[i]; tex:SetAllPoints(a.frame); tex:Show()
		end
		bar.sparkleEffect = a
	end
	if not a.anim:IsPlaying() then
		local r, g, b = 1, 1, 1
		if color then r = color.r; g = color.g; b = color.b end
		a.texture:SetVertexColor(r, g, b, 1) -- add color to the starburst texture
		for i = 1, 8 do
			local tex = a.sparkleTextures[i]; tex:SetVertexColor(r, g, b, 1) -- add color to each of the sparkle textures
		end
		a.anim:Stop(); a.anim:Play()
	end
end

-- When a bar is deleted then release allocated sparkle animation, if any
local function ReleaseSparkleEffect(bar)
	local a = bar.sparkleEffect -- get the sparkle animation, if any, that is allocated for this bar
	if a then
		a.anim:Stop(); a.frame:ClearAllPoints(); a.texture:Hide(); a.frame:Hide()
		for i = 1, 8 do a.sparkleTextures[i]:Hide() end
		sparkleEffectPool[a] = true
		bar.sparkleEffect = nil
	end
end

-- Initialize and return a glow effect behind a bar's icon
-- If color is set then apply it to the animation
local function GlowEffect(bar, color)
	local a = bar.glowEffect -- get a glow effect if one has already been allocated for this bar
	if not a then -- allocate an animation if necessary
		a = next(glowEffectPool) -- get one from the recycling pool if available
		if a then glowEffectPool[a] = nil else
			a = {} -- initialize a new table for this glow effect
			a.frame = CreateFrame("Frame", nil, UIParent)
			a.texture = a.frame:CreateTexture(nil, "BACKGROUND") -- texture to be animated
			a.texture:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
			a.texture:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)
			a.texture:SetBlendMode("ADD")
			a.circle = a.frame:CreateTexture(nil, "BACKGROUND") -- alternative circle texture
			a.circle:SetTexture("Interface\\Common\\GoldRing")
			a.circle:SetBlendMode("ADD")
		end
		a.frame:ClearAllPoints()
		a.frame:SetFrameStrata(bar.frame:GetFrameStrata())
		a.frame:SetFrameLevel(bar.frame:GetFrameLevel())
		a.frame:SetAlpha(0.5)
		bar.glowEffect = a
	end
	local w, h = bar.icon:GetSize()
	PSetSize(a.frame, w, h)
	PCSetPoint(a.frame, "CENTER", bar.icon, "CENTER", 0, 0)
	PSetSize(a.texture, (w - 2) * 2, (h - 2) * 2)
	PCSetPoint(a.texture, "CENTER", a.frame, "CENTER", -1, 0)
	PSetSize(a.circle, (w - 2) * 1.5, (h - 2) * 1.5)
	PCSetPoint(a.circle, "CENTER", a.frame, "CENTER", -1, 0)
	local r, g, b = 1, 1, 1
	if color then r = color.r; g = color.g; b = color.b end
	if MSQ and (bar.icon.__MSQ_Shape == "Circle") then
		a.circle:SetVertexColor(r, g, b, 1) -- add color to the circle texture
		a.texture:Hide(); a.circle:Show()
	else
		a.texture:SetVertexColor(r, g, b, 1) -- add color to the texture
		a.texture:Show(); a.circle:Hide()
	end
	a.frame:Show()
end

-- When a bar is deleted then release allocated glow animation, if any
local function ReleaseGlowEffect(bar)
	local a = bar.glowEffect -- get the glow animation, if any, that is allocated for this bar
	if a then
		a.texture:Hide(); a.circle:Hide(); a.frame:Hide()
		glowEffectPool[a] = true
		bar.glowEffect = nil
	end
end

-- Show the timeline specific frames for a bar group
local function ShowTimeline(bg)
	local back = bg.background
	if back then
		back:Show(); back.bar:ClearAllPoints(); back.bar:SetAllPoints(back); back.bar:Show()
		if bg.tlTexture then back.bar:SetTexture(bg.tlTexture) end
		local t = bg.tlColor; if t then back.bar:SetVertexColor(t.r, t.g, t.b, t.a) end
		if bg.borderTexture then
			PCSetPoint(back.backdrop, "CENTER", back, "CENTER", 0, 0)
			back.backdrop:Show()
		else
			back.backdrop:Hide()
		end
		for _, v in pairs(back.labels) do if v.hidden then v:Hide() else v:Show() end end
	end
end

-- Hide the timeline specific frames for a bar group (also works for horizontal stripe)
local function HideTimeline(bg)
	local back = bg.background
	if back then
		back:Hide(); back.bar:Hide(); back.backdrop:Hide()
		if back.labels then for _, v in pairs(back.labels) do v:Hide() end end
	end
end

-- Calculate the offset for a time value on a timeline
local function Timeline_Offset(bg, t)
	if t >= bg.tlDuration then return bg.tlWidth end
	if t <= 0 then return 0 end
	return bg.tlWidth * ((t / bg.tlDuration) ^ (1 / bg.tlScale))
end

-- Animate bars that are ending on a timeline
local function BarGroup_TimelineAnimation(bg, bar, config)
	local dir = bg.growDirection and 1 or -1 -- plus or minus depending on direction
	local isVertical = (config.orientation == "vertical")
	local w, h, edge
	if config.orientation == "horizontal" then
		w = bg.tlWidth; h = bg.tlHeight; edge = bg.growDirection and "RIGHT" or "LEFT"
	else
		w = bg.tlHeight; h = bg.tlWidth; edge = bg.growDirection and "TOP" or "BOTTOM"
	end
	local delta = Timeline_Offset(bg, 0)
	local x1 = isVertical and 0 or ((delta - w) * dir); local y1 = isVertical and ((delta - h) * dir) or 0
	SplashEffect(bar, edge, bg.background, edge, x1 + (bg.tlSplashX or 0), y1 + (bg.tlSplashY or 0))
end

-- Bar sorting functions: alphabetic, time left, duration, bar's start time
-- Values are assumed equal if difference less than 0.05 seconds
local function sortValues(a, b, f, up)
	if a.group ~= b.group then return a.group < b.group end
	if a.gname ~= b.gname then return a.gname < b.gname end
	if a.sortPlayer then if a.isMine ~= b.isMine then return a.isMine end end -- priority #1: optional isMine for cast by player detection
	if math.abs(a[f] - b[f]) >= 0.05 then if up then return a[f] < b[f] else return a[f] > b[f] end end -- priority #2: selected sort function
	if a.sortTime and (math.abs(a.timeLeft - b.timeLeft) >= 0.05) then return (a.timeLeft < b.timeLeft) end -- priority #3: optional increasing timeLeft
	return a.name < b.name -- priority #4: ascending alphabetic order
end

local function SortTimeDown(a, b) return sortValues(a, b, "timeLeft", false) end
local function SortTimeUp(a, b) return sortValues(a, b, "timeLeft", true) end
local function SortDurationDown(a, b) return sortValues(a, b, "duration", false) end
local function SortDurationUp(a, b) return sortValues(a, b, "duration", true) end
local function SortStartDown(a, b) return sortValues(a, b, "start", false) end
local function SortStartUp(a, b) return sortValues(a, b, "start", true) end

local function SortClassDown(a, b)
	if a.group ~= b.group then return a.group < b.group end
	if a.gname ~= b.gname then return a.gname < b.gname end
	if a.sortPlayer then if a.isMine ~= b.isMine then return a.isMine end end -- priority #1: optional isMine for cast by player detection
	if a.class ~= b.class then return a.class > b.class end -- priority #2: selected sort function
	if a.sortTime and (math.abs(a.timeLeft - b.timeLeft) >= 0.05) then return (a.timeLeft < b.timeLeft) end -- priority #3: optional increasing timeLeft
	return a.name < b.name -- priority #4: ascending alphabetic order
end

local function SortClassUp(a, b)
	if a.group ~= b.group then return a.group < b.group end
	if a.gname ~= b.gname then return a.gname < b.gname end
	if a.sortPlayer then if a.isMine ~= b.isMine then return a.isMine end end -- priority #1: optional isMine for cast by player detection
	if a.class ~= b.class then return a.class < b.class end -- priority #2: selected sort function
	if a.sortTime and (math.abs(a.timeLeft - b.timeLeft) >= 0.05) then return (a.timeLeft < b.timeLeft) end -- priority #3: optional increasing timeLeft
	return a.name < b.name -- priority #4: ascending alphabetic order
end

local function SortAlphaDown(a, b)
	if a.group ~= b.group then return a.group < b.group end
	if a.gname ~= b.gname then return a.gname < b.gname end
	if a.sortPlayer then if a.isMine ~= b.isMine then return a.isMine end end -- priority #1: optional isMine for cast by player detection
	if a.name ~= b.name then return a.name > b.name end -- priority #2: selected sort function
	if a.sortTime and (math.abs(a.timeLeft - b.timeLeft) >= 0.05) then return (a.timeLeft < b.timeLeft) end -- priority #3: optional increasing timeLeft
	return false -- priority #4: ascending alphabetic order (for alphabetic must be equal at this point)
end

local function SortAlphaUp(a, b)
	if a.group ~= b.group then return a.group < b.group end
	if a.gname ~= b.gname then return a.gname < b.gname end
	if a.sortPlayer then if a.isMine ~= b.isMine then return a.isMine end end -- priority #1: optional isMine for cast by player detection
	if a.name ~= b.name then return a.name < b.name end -- priority #2: selected sort function
	if a.sortTime and (math.abs(a.timeLeft - b.timeLeft) >= 0.05) then return (a.timeLeft < b.timeLeft) end -- priority #3: optional increasing timeLeft
	return false -- priority #4: ascending alphabetic order (for alphabetic must be equal at this point)
end

-- Register callbacks that can be used by internal functions to communicate in special cases
function MOD.Nest_RegisterCallbacks(cbs) if cbs then for k, v in pairs(cbs) do callbacks[k] = v end end end

-- Event handling functions for bar group anchors, pass both anchor and bar group
local function BarGroup_OnEvent(anchor, callback)
	local bg, bgName = nil, anchor.bgName
	-- MOD.Debug("BarGroup_OnEvent", anchor, bgName, callback)
	if bgName then bg = barGroups[bgName] end -- locate the bar group associated with the anchor
	if bg then
		local func = bg.callbacks[callback]
		if func then func(anchor, bgName) end
	end
end

local function BarGroup_OnEnter(anchor) BarGroup_OnEvent(anchor, "onEnter") end
local function BarGroup_OnLeave(anchor) BarGroup_OnEvent(anchor, "onLeave") end

-- OnClick does a callback (except for unmodified left click), passing bar group name and button
local function BarGroup_OnClick(anchor, button)
	local bg, bgName = nil, anchor.bgName
	if bgName then bg = barGroups[bgName] end -- locate the bar group associated with the anchor
	if ((button ~= "LeftButton") or IsModifierKeyDown()) and bg and not bg.locked then
		local func = bg.callbacks.onClick -- only pass left clicks if no modifier key is down
		if func then func(anchor, bgName, button) end
	end
end

-- OnMouseDown with no modifier key starts moving if frame unlocked and does callback, passing bar group name
local function BarGroup_OnMouseDown(anchor, button)
	local bg, bgName = nil, anchor.bgName
	if bgName then bg = barGroups[bgName] end -- locate the bar group associated with the anchor
	if (button == "LeftButton") and not IsModifierKeyDown() and bg and not bg.locked then
		bg.startX = PS(bg.frame:GetLeft()); bg.startY = PS(bg.frame:GetTop())
		bg.moving = true
		bg.frame:SetFrameStrata("HIGH")
		bg.frame:StartMoving()
		local func = bg.callbacks.onMove -- called to start movement as long as no modifier key is down
		if func then func(anchor, bgName) end
	end
end

-- OnMouseUp stops moving if frame is in motion and does a callback passing bar group name to indicate movement
local function BarGroup_OnMouseUp(anchor, button)
	local bg, bgName = nil, anchor.bgName
	if bgName then bg = barGroups[bgName] end -- locate the bar group associated with the anchor
	if bg and bg.moving then
		bg.frame:StopMovingOrSizing()
		bg.frame:SetFrameStrata(bg.strata or "MEDIUM")
		local func = bg.callbacks.onMove
		if func then
			local endX = PS(bg.frame:GetLeft()); local endY = PS(bg.frame:GetTop())
			-- MOD.Debug("moved", bgName, bg.startX, endX, bg.startY, endY)
			PCSetPoint(bg.frame, "TOPLEFT", UIParent, "BOTTOMLEFT", endX, endY)
			if bg.startX ~= endX or bg.startY ~= endY then func(anchor, bgName) end -- only fires if actually moved
		end
		bg.moving = false
	end
end

-- Initialize and return a new bar group containing either timer bars or enhanced icons
function MOD.Nest_CreateBarGroup(name)
	if barGroups[name] then return nil end -- already have one with that name
	local n, bg = next(usedBarGroups) -- get any available recycled bar group
	if n then
		usedBarGroups[n] = nil
	else
		bg = {}
		local xname = string.gsub(name, " ", "_")
		bg.frame = CreateFrame("Frame", "RavenBarGroup" .. xname, UIParent) -- add name for reference from other addons
		bg.frame:SetFrameLevel(bg.frame:GetFrameLevel() + 20) -- higher than other addons
		bg.frame:SetMovable(true); bg.frame:SetClampedToScreen(true)
		PCSetPoint(bg.frame, "CENTER", UIParent, "CENTER")
		bg.backdrop = CreateFrame("Frame", "RavenBarGroupBackdrop" .. xname, bg.frame, BackdropTemplateMixin and "BackdropTemplate")
		bg.backdropTable = { tile = false, insets = { left = 0, right = 0, top = 0, bottom = 0 }}
		bg.borderTable = { tile = false, insets = { left = 0, right = 0, top = 0, bottom = 0 }}
		bg.anchor = CreateFrame("Button", nil, bg.frame, BackdropTemplateMixin and "BackdropTemplate")

		anchorDefaults.tileSize = PS(ANCHOR_TILESIZE)
		anchorDefaults.edgeSize = PS(ANCHOR_EDGESIZE)
		bg.anchor:SetBackdrop(anchorDefaults)
		bg.anchor:SetBackdropColor(0.3, 0.3, 0.3, 0.9)
		bg.anchor:SetBackdropBorderColor(0, 0, 0, 0.9)
		bg.anchor:SetNormalFontObject(ChatFontSmall)
		bg.anchor:SetFrameLevel(bg.frame:GetFrameLevel() + 20) -- higher than the bar group frame
		bg.bars = {}
		bg.sorter = {}
		bg.attributes = {}
		bg.callbacks = {}
		bg.position = {}
		bg.sortFunction = SortAlphaUp
		bg.locked = false; bg.moving = false
		bg.count = 0
	end
	bg.anchor.bgName = name
	bg.anchor:SetScript("OnMouseDown", BarGroup_OnMouseDown)
	bg.anchor:SetScript("OnMouseUp", BarGroup_OnMouseUp)
	bg.anchor:SetScript("OnClick", BarGroup_OnClick)
	bg.anchor:SetScript("OnEnter", BarGroup_OnEnter)
	bg.anchor:SetScript("OnLeave", BarGroup_OnLeave)
	bg.anchor:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	bg.anchor:EnableMouse(true)
	table.wipe(bg.position)
	bg.name = name
	if MSQ then bg.MSQ_Group = MSQ:Group("Raven", name) end
	bg.update = true
	barGroups[name] = bg
	update = true
	return bg
end

-- Return the bar group with the specified name
function MOD.Nest_GetBarGroup(name) return barGroups[name] end

-- Return the table of bar groups
function MOD.Nest_GetBarGroups() return barGroups end

-- Delete a bar group and move it to the recycled bar group table
function MOD.Nest_DeleteBarGroup(bg)
	for _, bar in pairs(bg.bars) do MOD.Nest_DeleteBar(bg, bar) end -- empty out bars table
	PCSetPoint(bg.frame, "CENTER", UIParent, "CENTER") -- return to neutral position
	bg.anchor:SetScript("OnMouseDown", nil)
	bg.anchor:SetScript("OnMouseUp", nil)
	bg.anchor:SetScript("OnClick", nil)
	bg.anchor:SetScript("OnEnter", nil)
	bg.anchor:SetScript("OnLeave", nil)
	bg.anchor:EnableMouse(false)
	bg.anchor.bgName = nil
	for n in pairs(bg.sorter) do bg.sorter[n] = nil end -- empty the sorting table
	bg.sortFunction = SortAlphaUp; bg.sortTime = nil; bg.sortPlayer = nil
	bg.count = 0
	bg.locked = false; bg.moving = false
	if bg.MSQ_Group then bg.MSQ_Group:Delete() end
	bg.update = false
	bg.anchor:Hide(); bg.backdrop:Hide(); HideTimeline(bg)
	barGroups[bg.name] = nil
	bg.name = nil

	for n in pairs(bg.attributes) do bg.attributes[n] = nil end
	for n in pairs(bg.callbacks) do bg.callbacks[n] = nil end
	for n in pairs(bg) do if not bgTemplate[n] then bg[n] = nil end end -- remove all settings that don't belong
	table.insert(usedBarGroups, bg)
	update = true
end

-- Delete all bar groups (should trigger rebuild of existing bar groups in Bars.lua)
function MOD.Nest_DeleteAllBarGroups()
	for _, bg in pairs(barGroups) do MOD.Nest_DeleteBarGroup(bg) end
	update = true
end

-- Set layout options for a bar group
function MOD.Nest_SetBarGroupBarLayout(bg, barWidth, barHeight, iconSize, scale, spacingX, spacingY, iconOffsetX, iconOffsetY,
									   labelOffset, labelInset, labelWrap, labelAlign, labelCenter, labelAdjust, labelAuto, labelWidth,
									   timeOffset, timeInset, timeAlign, timeIcon, iconOffset, iconInset, iconHide, iconAlign,
									   configuration, growDirection, wrap, wrapDirection, snapCenter, fillBars, maxBars, strata)
	bg.barWidth = PS(barWidth); bg.barHeight = PS(barHeight); bg.iconSize = PS(iconSize); bg.scale = scale or 1
	bg.fillBars = fillBars; bg.maxBars = maxBars; bg.strata = strata
	bg.spacingX = PS(spacingX or 0); bg.spacingY = PS(spacingY or 0); bg.iconOffsetX = (iconOffsetX or 0); bg.iconOffsetY = PS(iconOffsetY or 0)
	bg.labelOffset = PS(labelOffset or 0); bg.labelInset = PS(labelInset or 0); bg.labelWrap = labelWrap;
	bg.labelCenter = labelCenter; bg.labelAlign = labelAlign or "MIDDLE"; bg.labelAdjust = labelAdjust; bg.labelAuto = labelAuto; bg.labelWidth = labelWidth
	bg.timeOffset = PS(timeOffset or 0); bg.timeInset = PS(timeInset or 0); bg.timeAlign = timeAlign or "normal"; bg.timeIcon = timeIcon
	bg.iconOffset = PS(iconOffset or 0); bg.iconInset = PS(iconInset or 0); bg.iconHide = iconHide; bg.iconAlign = iconAlign or "CENTER"
	bg.configuration = configuration or 1; bg.growDirection = growDirection; bg.wrap = wrap or 0; bg.wrapDirection = wrapDirection; bg.snapCenter = snapCenter
	bg.update = true
end

function MOD.Nest_SetBarGroupSegments(bg, count, override, spacing, hideEmpty, fadeAll, shrinkW, shrinkH, gradient, gradientAll, startColor, endColor,
									  borderColor, advanced, curve, rotate, texture)
	bg.segmentCount = count; bg.segmentOverride = override; bg.segmentSpacing = spacing; bg.segmentAdvanced = advanced
	bg.segmentHideEmpty = hideEmpty; bg.segmentFadePartial = fadeAll; bg.segmentShrinkWidth = shrinkW; bg.segmentShrinkHeight = shrinkH
	bg.segmentGradient = gradient; bg.segmentGradientAll = gradientAll; bg.segmentGradientStartColor = startColor; bg.segmentGradientEndColor = endColor
	bg.segmentBorderColor = borderColor; bg.segmentCurve = curve; bg.segmentRotate = rotate; bg.segmentTexture = texture
	bg.update = true
end

local function TextFlags(outline, thick, mono)
	local t = nil
	if not outline and not thick then mono = false end -- XXXX workaround for blizzard bugs caused by use of monochrome text flag by itself
	if mono then
		if outline then if thick then t = "MONOCHROME,OUTLINE,THICKOUTLINE" else t = "MONOCHROME,OUTLINE" end
		else if thick then t = "MONOCHROME,THICKOUTLINE" else t = "MONOCHROME" end end
	else
		if outline then if thick then t = "OUTLINE,THICKOUTLINE" else t = "OUTLINE" end
		else if thick then t = "THICKOUTLINE" end end
	end
	return t
end

-- Set label font options for a bar group
function MOD.Nest_SetBarGroupLabelFont(bg, font, fsize, alpha, color, outline, shadow, thick, mono, special)
	if not color then color = { r = 1, g = 1, b = 1, a = 1 } end
	if UseTukui() then font = GetTukuiFont(font) end
	bg.labelFont = font; bg.labelFSize = fsize or 9; bg.labelAlpha = alpha or 1; bg.labelColor = color
	bg.labelFlags = TextFlags(outline, thick, mono); bg.labelShadow = shadow; bg.labelSpecial = special
	bg.update = true
end

-- Set time text font options for a bar group
function MOD.Nest_SetBarGroupTimeFont(bg, font, fsize, alpha, color, outline, shadow, thick, mono, special)
	if not color then color = { r = 1, g = 1, b = 1, a = 1 } end
	if UseTukui() then font = GetTukuiFont(font) end
	bg.timeFont = font; bg.timeFSize = fsize or 9; bg.timeAlpha = alpha or 1; bg.timeColor = color
	bg.timeFlags = TextFlags(outline, thick, mono); bg.timeShadow = shadow; bg.timeSpecial = special
	bg.update = true
end

-- Set icon text font options for a bar group
function MOD.Nest_SetBarGroupIconFont(bg, font, fsize, alpha, color, outline, shadow, thick, mono, special)
	if not color then color = defaultBackdropColor end
	if UseTukui() then font = GetTukuiFont(font) end
	bg.iconFont = font; bg.iconFSize = fsize or 9; bg.iconAlpha = alpha or 1; bg.iconColor = color
	bg.iconFlags = TextFlags(outline, thick, mono); bg.iconShadow = shadow; bg.iconSpecial = special
	bg.update = true
end

-- Set bar border options for a bar group
function MOD.Nest_SetBarGroupBorder(bg, texture, width, offset, color)
	if not color then color = defaultBackdropColor end
	bg.borderTexture = texture; bg.borderWidth = PS(width or 0); bg.borderOffset = PS(offset or 0); bg.borderColor = color
	if bg.borderWidth == 0 then bg.borderWidth = PS(1) end -- don't let this be zero width
	bg.update = true
end

-- Set backdrop options for a bar group
function MOD.Nest_SetBarGroupBackdrop(bg, panel, texture, width, inset, padding, color, fill, offsetX, offsetY, padW, padH)
	if not color then color = { r = 1, g = 1, b = 1, a = 1 } end
	if not fill then fill = { r = 1, g = 1, b = 1, a = 1 } end
	bg.backdropPanel = panel; bg.backdropTexture = texture; bg.backdropWidth = PS(width or 0); bg.backdropInset = PS(inset or 0)
	if bg.backdropWidth == 0 then bg.backdropWidth = PS(1) end -- don't let this be zero width
	bg.backdropPadding = PS(padding or 0); bg.backdropColor = color; bg.backdropFill = fill
	bg.backdropOffsetX = PS(offsetX or 0); bg.backdropOffsetY = PS(offsetY or 0); bg.backdropPadW = PS(padW or 0); bg.backdropPadH = PS(padH or 0)
	bg.update = true
end

-- Set texture options for a bar group
function MOD.Nest_SetBarGroupTextures(bg, fgTexture, fgAlpha, bgTexture, bgAlpha, fgNotTimer, fgSaturation, fgBrightness, bgSaturation, bgBrightness)
	bg.fgTexture = fgTexture; bg.fgAlpha = fgAlpha; bg.bgTexture = bgTexture; bg.bgAlpha = bgAlpha; bg.fgNotTimer = fgNotTimer
	bg.fgSaturation = fgSaturation or 0; bg.fgBrightness = fgBrightness or 0; bg.bgSaturation = bgSaturation or 0; bg.bgBrightness = bgBrightness or 0
	bg.update = true
end

-- Select visible components for a bar group
function MOD.Nest_SetBarGroupVisibles(bg, icon, cooldown, bar, spark, labelText, timeText)
	bg.showIcon = icon; bg.showCooldown = cooldown; bg.showBar = bar; bg.showSpark = spark
	bg.showLabelText = labelText; bg.showTimeText = timeText
	bg.update = true
end

-- Set parameters related to timeline configurations
function MOD.Nest_SetBarGroupTimeline(bg, w, h, duration, scale, hide, alt, switch, percent, splash, x, y, offset, delta, tex, alpha, color, labels, btex, bw, bo, bc)
	bg.tlWidth = PS(w); bg.tlHeight = PS(h); bg.tlDuration = duration; bg.tlScale = scale; bg.tlHide = hide; bg.tlAlternate = alt
	bg.tlSwitch = switch; bg.tlPercent = percent; bg.tlSplash = splash; bg.tlSplashX = x; bg.tlSplashY = y; bg.tlOffset = offset; bg.tlDelta = delta
	bg.tlTexture = tex; bg.tlAlpha = alpha; bg.tlColor = color; bg.tlLabels = labels
	bg.tlBorderTexture = btex; bg.tlBorderWidth = PS(bw or 0); bg.tlBorderOffset = PS(bo or 0); bg.tlBorderColor = bc
	if bg.tlBorderWidth == 0 then bg.tlBorderWidth = PS(1) end -- don't let this be zero width
	bg.update = true
end

-- Set parameters related to horizontal stripe configurations
function MOD.Nest_SetBarGroupStripe(bg, fullWidth, w, h, inset, offset, barInset, barOffset, texture, color, btex, bw, bo, bc)
	if fullWidth then bg.stWidth = GetScreenWidth() else bg.stWidth = PS(w) end
	bg.stHeight = PS(h); bg.stInset = inset; bg.stOffset = offset; bg.stBarInset = barInset; bg.stBarOffset = barOffset; bg.stTexture = texture; bg.stColor = color
	bg.stBorderTexture = btex; bg.stBorderWidth = PS(bw or 0); bg.stBorderOffset = PS(bo or 0); bg.stBorderColor = bc; bg.stFullWidth = fullWidth
	if bg.stBorderWidth == 0 then bg.stBorderWidth = PS(1) end -- don't let this be zero width
	bg.update = true
end

-- Sort the bars in a bar group using the designated sort method and direction (default is sort by name alphabetically)
function MOD.Nest_BarGroupSortFunction(bg, sortMethod, sortDirection, sortTime, sortPlayer)
	if sortMethod == "time" then -- sort by time left on the bar
		if sortDirection then bg.sortFunction = SortTimeDown else bg.sortFunction = SortTimeUp end
	elseif sortMethod == "duration" then -- sort by bar duration
		if sortDirection then bg.sortFunction = SortDurationDown else bg.sortFunction = SortDurationUp end
	elseif sortMethod == "start" then -- sort by bar start time
		if sortDirection then bg.sortFunction = SortStartDown else bg.sortFunction = SortStartUp end
	elseif sortMethod == "class" then -- sort by bar class
		if sortDirection then bg.sortFunction = SortClassDown else bg.sortFunction = SortClassUp end
	else -- default is sort alphabetically by bar name
		if sortDirection then bg.sortFunction = SortAlphaDown else bg.sortFunction = SortAlphaUp end
	end
	bg.sortTime = sortTime; bg.sortPlayer = sortPlayer
	bg.update = true
end

-- Set the time format function for the bar group, if not set will use default
function MOD.Nest_SetBarGroupTimeFormat(bg, timeFormat, timeSpaces, timeCase)
	bg.timeFormat = timeFormat; bg.timeSpaces = timeSpaces; bg.timeCase = timeCase
	bg.update = true
end

-- If locked is true then lock the bar group anchor, otherwise unlock it
function MOD.Nest_SetBarGroupLock(bg, locked)
	bg.locked = locked
	bg.update = true
end

-- Return a bar group's display position as percentages of actual display size to edges of the anchor frame
-- Return values are descaled to match UIParent and include left, right, bottom and top plus descaled width and height
function MOD.Nest_GetAnchorPoint(bg)
	local scale = bg.scale or 1
	local dw, dh = displayWidth, displayHeight
	local w, h = bg.frame:GetWidth() * scale, bg.frame:GetHeight() * scale
	local left, bottom = bg.frame:GetLeft(), bg.frame:GetBottom() -- get scaled coordinates for frame's anchor
	if left and bottom then left = (left * scale); bottom = (bottom * scale) else left = dw / 2; bottom = dh / 2 end -- default to center
	local right, top = dw - (left + w), dh - (bottom + h)
	local p = bg.position; p.left, p.right, p.bottom, p.top, p.width, p.height = left / dw, right / dw, bottom / dh, top / dh, w, h
	return p.left, p.right, p.bottom, p.top, p.width, p.height
end

-- Set a bar group's scaled display position from left, right, bottom, top where left and bottom should always be valid
-- Use right, top, width and height only if valid and closer to that edge to fix position shift when UIParent dimensions change
function MOD.Nest_SetAnchorPoint(bg, left, right, bottom, top, scale, width, height)
	if left and bottom and width and height then -- make sure valid settings
		bg.scale = scale -- make sure save scale since may not have been initialized yet
		local p = bg.position; p.left, p.right, p.bottom, p.top, p.width, p.height = left, right, bottom, top, width, height
		local dw, dh = displayWidth, displayHeight
		local xoffset = left * dw
		local yoffset = bottom * dh
		if right and top and width and height then -- optionally set from other edges if closer to them
			if left > 0.5 then xoffset = dw - (right * dw) - width end
			if bottom > 0.5 then yoffset = dh - (top * dh) - height end
		end
		bg.frame:SetScale(scale); PSetSize(bg.frame, width, height)
		PCSetPoint(bg.frame, "BOTTOMLEFT", nil, "BOTTOMLEFT", xoffset / scale, yoffset / scale)
	end
end

-- Set a bar group's display position as relative to another bar group
function MOD.Nest_SetRelativeAnchorPoint(bg, rTo, rFrame, rPoint, rX, rY, rLB, rEmpty, rRow, rColumn)
	if rFrame and GetClickFrame(rFrame) then -- set relative to a specific frame
		PCSetPoint(bg.frame, rPoint or "CENTER", GetClickFrame(rFrame), rPoint or "CENTER", rX, rY)
		if pixelPerfect then -- have to re-align relative to bottom left since we can't be sure that anchor point itself is pixel aligned
			PCSetPoint(bg.frame, "BOTTOMLEFT", nil, "BOTTOMLEFT", bg.frame:GetLeft(), bg.frame:GetBottom())
		end
		bg.relativeTo = nil -- remove relative anchor point
	elseif bg.relativeTo and not rTo then -- removing a relative anchor point
		PCSetPoint(bg.frame, "BOTTOMLEFT", nil, "BOTTOMLEFT", bg.frame:GetLeft(), bg.frame:GetBottom())
		bg.relativeTo = nil -- remove relative anchor point
	else
		bg.relativeTo = rTo -- if relativeTo is nil then relative anchor point is not set
		bg.relativeX = rX; bg.relativeY = rY; bg.relativeLastBar = rLB; bg.relativeEmpty = rEmpty; bg.relativeRow = rRow; bg.relativeColumn = rColumn
	end
end

-- Set callbacks for a bar group
function MOD.Nest_SetBarGroupCallbacks(bg, onMove, onClick, onEnter, onLeave)
	bg.callbacks.onMove = onMove; bg.callbacks.onClick = onClick; bg.callbacks.onEnter = onEnter; bg.callbacks.onLeave = onLeave
end

-- Set opacity for a bar group, including mouseover override
function MOD.Nest_SetBarGroupAlpha(bg, alpha, mouseAlpha, disableAlpha) bg.alpha = alpha or 1; bg.mouseAlpha = mouseAlpha or 1; bg.disableAlpha = disableAlpha end

-- Set a bar group attribute. This is the mechanism to associate application-specific data with bar groups.
function MOD.Nest_SetBarGroupAttribute(bg, name, value) bg.attributes[name] = value end

-- Get a bar group attribute. This is the mechanism to associate application-specific data with bar groups.
function MOD.Nest_GetBarGroupAttribute(bg, name) return bg.attributes[name] end

-- Set an attribute for all bars in the bar group
function MOD.Nest_SetAllAttributes(bg, name, value)
	for _, bar in pairs(bg.bars) do bar.attributes[name] = value end
end

-- Delete all bars in the bar group with the specifed attribute value (useful for mark/sweep garbage collection)
function MOD.Nest_DeleteBarsWithAttribute(bg, name, value)
	for barName, bar in pairs(bg.bars) do
		if bar.attributes[name] == value then MOD.Nest_DeleteBar(bg, bar) end
	end
end

-- Event handling functions for bars with callback
local function Bar_OnEvent(frame, callback, value)
	local bg, bgName, name = nil, frame.bgName, frame.name
	-- MOD.Debug("Bar_OnEvent", frame, bgName, name, callback, value)
	if bgName then bg = barGroups[bgName] end -- locate the bar group associated with the anchor
	if bg then
		local bar = bg.bars[name]
		if bar then
			if not value then value = bar.tooltipAnchor end
			local func = bar.callbacks[callback]
			if func then func(frame, bgName, name, value) end
		end
	end
end

local function Bar_OnEnter(frame) Bar_OnEvent(frame, "onEnter") end
local function Bar_OnLeave(frame) Bar_OnEvent(frame, "onLeave") end
local function Bar_OnClick(frame, button) Bar_OnEvent(frame, "onClick", button) end

local function GetButtonName() buttonName = buttonName + 1; return "RavenButton" .. tostring(buttonName) end -- unique button name

-- Initialize and return a new bar
function MOD.Nest_CreateBar(bg, name)
	if bg.bars[name] then return nil end -- already have one with that name
	local n, bar = next(usedBars) -- get any available recycled bar
	if n then
		usedBars[n] = nil
		bar.frame:SetParent(bg.frame)
	else
		local bname = GetButtonName()
		bar = { buttonName = bname }
		bar.frame = CreateFrame("Button", bname .. "Frame", bg.frame)
		bar.container = CreateFrame("Frame", bname .. "Container", bar.frame)
		bar.fgTexture = bar.container:CreateTexture(nil, "BACKGROUND", nil, 2)
		bar.bgTexture = bar.container:CreateTexture(nil, "BACKGROUND", nil, 1)
		bar.backdrop = CreateFrame("Frame", bname .. "Backdrop", bar.container, BackdropTemplateMixin and "BackdropTemplate")
		bar.spark = bar.container:CreateTexture(nil, "OVERLAY")
		bar.spark:SetTexture([[Interface\CastingBar\UI-CastingBar-Spark]])
		bar.spark:SetSize(10, 10)
		bar.spark:SetBlendMode("ADD")
		bar.spark:SetTexCoord(0, 1, 0, 1)
		bar.tick = bar.container:CreateTexture(nil, "OVERLAY")
		bar.tipFrame = CreateFrame("Frame", bname .. "TipFrame", bar.container) -- used only for tooltips
		bar.textFrame = CreateFrame("Frame", bname .. "TextFrame", bar.container) -- used to assign texts in right level
		bar.labelText = bar.textFrame:CreateFontString(nil, "OVERLAY")
		bar.timeText = bar.textFrame:CreateFontString(nil, "OVERLAY")
		bar.icon = CreateFrame("Button", bname, bar.frame, BackdropTemplateMixin and "BackdropTemplate")
		bar.iconTexture = bar.icon:CreateTexture(bname .. "IconTexture", "ARTWORK") -- texture for the bar's icon
		bar.cooldown = CreateFrame("Cooldown", bname .. "Cooldown", bar.icon, "CooldownFrameTemplate") -- cooldown overlay to animate timer
		bar.cooldown.noCooldownCount = Raven.db.global.HideOmniCC
		bar.cooldown.noOCC = Raven.db.global.HideOmniCC -- added for Tukui
		bar.cooldown:SetHideCountdownNumbers(true); bar.cooldown:SetDrawBling(false); bar.cooldown:SetDrawEdge(Raven.db.global.IconClockEdge) -- added in WoD
		bar.iconTextFrame = CreateFrame("Frame", bname .. "IconTextFrame", bar.frame)
		bar.iconText = bar.iconTextFrame:CreateFontString(nil, "OVERLAY", nil, 4)
		bar.iconBorder = bar.iconTextFrame:CreateTexture(nil, "BACKGROUND", nil, 3)
		if UseTukui() then
			bar.tukbar = CreateFrame("Frame", bname .. "Tukbar", bar.container)
			bar.tukbar:CreateBackdrop("Transparent")
			local bdrop = bar.tukbar.backdrop or bar.tukbar.Backdrop
			if bdrop then bdrop:SetOutside(bar.tukbar) end
			if MOD.db.global.TukuiIcon then -- see if also skinning the icon
				bar.icon:CreateBackdrop("Transparent")
				bdrop = bar.icon.backdrop or bar.icon.Backdrop
				if bdrop then
					bdrop:SetFrameLevel(bar.icon:GetFrameLevel() - 2) -- drop backdrop frame level by one due to "hazy overlay" interaction with Masque
					bdrop:SetOutside(bar.icon)
					bar.tukcolor_r, bar.tukcolor_g, bar.tukcolor_b, bar.tukcolor_a = bdrop:GetBackdropBorderColor() -- save default icon border color
				end
			end
		end

		if MSQ then -- if using ButtonFacade, create and initialize a button data table
			bar.buttonData = {} -- only initialize once so no garbage collection issues
			for k, v in pairs(MSQ_ButtonData) do bar.buttonData[k] = v end
		end

		bar.segments = {}; bar.segmentsAllocated = false
		bar.attributes = {}
		bar.callbacks = {}
	end
	bar.frame:SetFrameLevel(bg.frame:GetFrameLevel() + 5)
	bar.frame.name = name
	bar.frame.bgName = bg.name
	bar.frame:SetScript("OnClick", Bar_OnClick)
	bar.frame:SetScript("OnEnter", Bar_OnEnter)
	bar.frame:SetScript("OnLeave", Bar_OnLeave)
	bar.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	bar.icon.name = name
	bar.icon.bgName = bg.name
	bar.icon:SetScript("OnClick", Bar_OnClick)
	bar.icon:SetScript("OnEnter", Bar_OnEnter)
	bar.icon:SetScript("OnLeave", Bar_OnLeave)
	bar.icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	bar.tipFrame.name = name
	bar.tipFrame.bgName = bg.name
	bar.tipFrame:SetScript("OnEnter", Bar_OnEnter)
	bar.tipFrame:SetScript("OnLeave", Bar_OnLeave)
	bar.startTime = GetTime()
	bar.name = name
	bar.update = true
	bar.includeBar = true; bar.includeOffset = 0
	bg.bars[name] = bar
	bg.count = bg.count + 1
	bg.sorter[bg.count] = { name = name }
	bg.update = true
	return bar
end

-- Create frames with foreground and background textures that can be used to show up to 10 bar segments
local function AllocateSegments(bar)
	local name = bar.buttonName .. "Segment"
	for i = 1, 10 do
		local f = CreateFrame("Frame", name .. tostring(i), bar.container, BackdropTemplateMixin and "BackdropTemplate")
		f.fgTexture = f:CreateTexture(nil, "BACKGROUND", nil, 2)
		f.bgTexture = f:CreateTexture(nil, "BACKGROUND", nil, 1)
		bar.segments[i] = f
	end
	bar.segmentsAllocated = true
end

-- Return the bar with the specified name
function MOD.Nest_GetBar(bg, name) return bg.bars[name] end

-- Return the bars table for a bar group
function MOD.Nest_GetBars(bg) return bg.bars end

-- Delete a bar from a bar group, moving it to recycled bar table
function MOD.Nest_DeleteBar(bg, bar)
	if MOD.tooltipBar == bar then -- disable tooltip update when bar is deleted
		MOD.tooltipBar = nil
		GameTooltip:Hide()
	end
	local config = MOD.Nest_SupportedConfigurations[bg.configuration]
	if config.bars == "timeline" and bg.tlSplash then BarGroup_TimelineAnimation(bg, bar, config) end

	ReleaseShineEffect(bar) -- stop animations for special effects and release any allocated resources
	ReleaseSparkleEffect(bar)
	ReleaseGlowEffect(bar)
	ReleasePulseEffect(bar)
	ReleaseFaderEffect(bar)
	ReleaseFlashEffect(bar)

	bar.icon:EnableMouse(false); bar.frame:EnableMouse(false)
	bar.frame:SetScript("OnMouseUp", nil)
	bar.frame:SetScript("OnEnter", nil)
	bar.frame:SetScript("OnLeave", nil)
	bar.frame.name = nil
	bar.frame.bgName = nil
	bar.icon:SetScript("OnMouseUp", nil)
	bar.icon:SetScript("OnEnter", nil)
	bar.icon:SetScript("OnLeave", nil)
	bar.icon.name = nil
	bar.icon.bgName = nil
	bar.tipFrame:SetScript("OnEnter", nil)
	bar.tipFrame:SetScript("OnLeave", nil)
	bar.tipFrame.name = nil
	bar.tipFrame.bgName = nil
	bar.cooldown:SetCooldown(0, 0)
	bar.iconPath = nil
	bar.update = false
	bar.backdrop:Hide(); bar.fgTexture:Hide(); bar.bgTexture:Hide(); bar.spark:Hide(); bar.icon:Hide(); bar.cooldown:Hide()
	bar.iconText:Hide(); bar.labelText:Hide(); bar.timeText:Hide(); bar.iconBorder:Hide(); bar.tick:Hide()
	if bar.segmentsAllocated then for _, f in pairs(bar.segments) do f:ClearAllPoints(); f:Hide() end end
	if bar.tukbar then bar.tukbar:Hide() end -- if skinning for elvui then hide this frame too
	bar.backdrop:ClearAllPoints(); bar.fgTexture:ClearAllPoints(); bar.bgTexture:ClearAllPoints(); bar.spark:ClearAllPoints()
	bar.icon:ClearAllPoints(); bar.cooldown:ClearAllPoints(); bar.iconText:ClearAllPoints(); bar.tick:ClearAllPoints()
	bar.labelText:ClearAllPoints(); bar.timeText:ClearAllPoints(); bar.iconBorder:ClearAllPoints()
	bar.frame:SetHitRectInsets(0, 0, 0, 0) -- used by stripe bar group
	if callbacks.release then callbacks.release(bar) end

	local i = 1
	while i <= bg.count do -- find and remove the corresponding entry in the sorting table
		if bg.sorter[i].name == bar.name then
			if i ~= bg.count then bg.sorter[i] = bg.sorter[bg.count] end -- copy last one to fill the hole
			bg.sorter[bg.count] = nil
			bg.count = bg.count - 1
			break
		end
		i = i + 1
	end
	bg.bars[bar.name] = nil
	bar.name = nil

	for n in pairs(bar) do if not barTemplate[n] then bar[n] = nil end end -- remove all settings that don't belong
	for n in pairs(bar.attributes) do bar.attributes[n] = nil end -- clear bar attributes
	for n in pairs(bar.callbacks) do bar.callbacks[n] = nil end -- reset bar callbacks
	table.insert(usedBars, bar)
	bg.update = true
end

-- Delete all bars in a bar group
function MOD.Nest_DeleteAllBars(bg)
	for barName, bar in pairs(bg.bars) do MOD.Nest_DeleteBar(bg, bar) end
end

-- Start (or restart) a timer bar, note that maxTime is the display maximum which may be less than duration
function MOD.Nest_StartTimer(bar, timeLeft, duration, maxTime)
	bar.startTime = GetTime() -- time the timer bar was started (or restarted, which counts as a new timer)
	bar.offsetTime = duration - timeLeft -- save offset since may be sent multiple times
	bar.timeLeft = timeLeft; bar.duration = duration; bar.maxTime = maxTime or duration
	bar.expireDone = nil; bar.warningDone = nil; bar.update = true
end

-- Return true if time parameters have been set for a bar
function MOD.Nest_IsTimer(bar) return bar.timeLeft ~= nil end

-- Get the time parameters for a bar, including adjusted timeLeft amount
function MOD.Nest_GetTimes(bar) return bar.timeLeft, bar.duration, bar.maxTime, bar.startTime, bar.offsetTime end

-- Set all bar colors, includes foreground, background and icon border codes
function MOD.Nest_SetColors(bar, cr, cg, cb, ca, br, bg, bb, ba, ibr, ibg, ibb, iba)
	bar.cr = cr; bar.cg = cg; bar.cb = cb; bar.ca = ca
	bar.br = br; bar.bg = bg; bar.bb = bb; bar.ba = ba
	bar.ibr = ibr; bar.ibg = ibg; bar.ibb = ibb; bar.iba = iba
end

-- Set bar foreground color
function MOD.Nest_SetForegroundColor(bar, cr, cg, cb)
	bar.cr = cr; bar.cg = cg; bar.cb = cb
end

-- Override bar background color
function MOD.Nest_SetBackgroundColor(bar, cr, cg, cb)
	bar.br = cr; bar.bg = cg; bar.bb = cb
end

-- Override label text color
function MOD.Nest_SetLabelColor(bar, cr, cg, cb)
	bar.label_r = cr; bar.label_g = cg; bar.label_b = cb
end

-- Override time text color
function MOD.Nest_SetTimeColor(bar, cr, cg, cb)
	bar.time_r = cr; bar.time_g = cg; bar.time_b = cb
end

-- Set tick offset (nil to hide tick, otherwise seconds after bar started to show tick) and color
function MOD.Nest_SetTick(bar, enable, offset, cr, cg, cb, ca)
	bar.tickEnable = enable; bar.tickOffset = offset; bar.tr = cr; bar.tg = cg; bar.tb = cb; bar.ta = ca
end

-- Set the overall alpha for a bar, this is last alpha adjustment made before bar is displayed
function MOD.Nest_SetAlpha(bar, alpha) bar.alpha = alpha end

-- Set whether the bar should flash or not
function MOD.Nest_SetFlash(bar, flash) bar.flash = flash end

-- Set whether the bar should have glow effect or not
function MOD.Nest_SetGlow(bar, glow) bar.glow = glow end

-- Set whether the bar should trigger a shine effect
function MOD.Nest_SetShine(bar, shine) bar.shine = shine end

-- Set whether the bar should trigger a sparkle effect
function MOD.Nest_SetSparkle(bar, sparkle) bar.sparkle = sparkle end

-- Set whether the bar should trigger a pulse effect
function MOD.Nest_SetPulse(bar, pulse) bar.pulse = pulse end

-- Set the label text for a bar
function MOD.Nest_SetLabel(bar, label) bar.label = label end

-- Set the value, maximum value, and an optional text for the value of a non-timer bar
function MOD.Nest_SetValue(bar, value, maxValue, valueText, valueLabel, include, offset)
	bar.value = value; bar.maxValue = maxValue; bar.valueText = valueText; bar.valueLabel = valueLabel
	bar.includeBar = include; bar.includeOffset = offset or 0
end

-- Set the icon texture for a bar
function MOD.Nest_SetIcon(bar, icon) bar.iconPath = icon end

-- Set the numeric value to display on the bar's icon
function MOD.Nest_SetCount(bar, iconCount) bar.iconCount = iconCount end

-- Set a bar attribute. This is the mechanism to associate application-specific data with bars.
function MOD.Nest_SetAttribute(bar, name, value) bar.attributes[name] = value end

-- Get a bar attribute. This is the mechanism to associate application-specific data with bars.
function MOD.Nest_GetAttribute(bar, name) return bar.attributes[name] end

-- Set callbacks for a bar
function MOD.Nest_SetCallbacks(bar, onClick, onEnter, onLeave)
	bar.callbacks.onClick = onClick; bar.callbacks.onEnter = onEnter; bar.callbacks.onLeave = onLeave
end

-- Set saturation and brightness of RGB colors by converting into HSL, adjusting saturation, then converting back to RGB
-- Input color RGB components are values between 0 to 1.0, saturation and brightness are values between -1.0 and 1.0
local function LevelAdjust(v, a) -- apply adjustment in range -1..+1 to either saturation or brightness
	if a ~= 0 then if a >= -1 and a < 0 then return v * (a + 1) elseif a > 0 and a <= 1 then return v + ((1 - v) * a) end end
	return v
end

function MOD.Nest_AdjustColor(r, g, b, saturation, brightness)
	if not r or not g or not b then return 0.5, 0.5, 0.5 end -- avoid errors if passed in nil values
	if not saturation then saturation = 0 end; if not brightness then brightness = 0 end -- set to default values
	if (saturation == 0) and (brightness == 0) then return r, g, b end

	CS:SetColorRGB(r, g, b)
	local ch, cs, cv = CS:GetColorHSV()

	if saturation < -1 then saturation = -1 elseif saturation > 1 then saturation = 1 end
	cs = LevelAdjust(cs, saturation) -- adjust the saturation, using original -1 .. +1 scale
	if brightness < -1 then brightness = -1 elseif brightness > 1 then brightness = 1 end
	cv = LevelAdjust(cv, brightness / 2) -- adjust the brightness, restricting the range to -0.5 to +0.5

	CS:SetColorHSV(ch, cs, cv)
	return CS:GetColorRGB()
end

-- Given two colors, find an intermediate color that is between them a given fraction of hue shift
function MOD.Nest_IntermediateColor(ar, ag, ab, br, bg, bb, frac)
	if not ar or not ag or not ab or not br or not bg or not bb then return 0.5, 0.5, 0.5 end -- avoid errors if passed in nil values

	CS:SetColorRGB(ar, ag, ab)
	local ah, as, av = CS:GetColorHSV()
	CS:SetColorRGB(br, bg, bb)
	local bh, bs, bv = CS:GetColorHSV()

	local ch -- credit Zork for this code
	if abs(ah - bh) > 180 then
		local angle = (360 - abs(ah - bh)) * frac
		if ah < bh then
			ch = floor(ah - angle)
			if ch < 0 then ch = 360 + ch end
		else
			ch = floor(ah + angle)
			if ch > 360 then ch = ch - 360 end
		end
	else
		ch = floor(ah - (ah - bh) * frac)
	end
	local cs = as - (as - bs) * frac
	local cv = av - (av - bv) * frac

	CS:SetColorHSV(ch, cs, cv)
	return CS:GetColorRGB()
end

-- Update a bar group's anchor, showing it only if the bar group is unlocked
local function BarGroup_UpdateAnchor(bg, config)
	local pFrame = bg.attributes.parentFrame

	if pFrame then
		local parentFrame = GetClickFrame(pFrame)

		if parentFrame then
			bg.frame:SetParent(parentFrame)
		else
			bg.frame:SetParent(UIParent)
		end
	else
		bg.frame:SetParent(UIParent)
	end

	bg.anchor:SetText(bg.name)
	local lw, lh = bg.width, bg.height
	if config.iconOnly then lw = rectIcons and bg.barWidth or bg.iconSize end -- anchors have same w and h as bars/icons, ignoring icon offsetX
	local cfg = config.bars
	if (cfg == "timeline") or (cfg == "stripe") then -- except timelines and stripes which use fixed size independent of icons being displayed
		if cfg == "timeline" then lh = bg.tlHeight else lh = bg.stHeight end
		lw = bg.anchor:GetFontString():GetStringWidth() + 8 -- minimum width so anchor not too skinny for the caption
	end
	PSetSize(bg.anchor, lw, lh)

	local align = "BOTTOMLEFT" -- select corner to attach based on configuration
	if config.iconOnly then -- icons can grow in any direction
		if config.orientation == "horizontal" then
			if bg.growDirection then align = "BOTTOMRIGHT" end -- align rights for going left (growDirection=true), lefts for right (growDirection=false)
		else -- must be "vertical"
			if not bg.growDirection then align = "TOPLEFT" end -- align bottoms for going up (growDirection=true), tops for down (growDirection=false)
		end
	else -- bars can grow either up are down
		if not bg.growDirection then align = "TOPLEFT" end -- align bottoms for going up (growDirection=true), tops for down (growDirection=false)
	end
	PCSetPoint(bg.anchor, align, bg.frame, align)
	if not bg.locked and not inPetBattle then bg.anchor:Show() else bg.anchor:Hide() end
end

-- Update a bar group's background image, currently only required for timeline and stripe backdrops
local function BarGroup_UpdateBackground(bg, config)
	if config.bars == "stripe" then -- check if drawing a horizontal stripe for icons
		local back = bg.background -- share background frame with timeline
		if not back then -- need to create the background frame
			back = CreateFrame("Frame", nil, bg.frame)
			back:SetFrameLevel(bg.frame:GetFrameLevel() + 2) -- higher than bar group's backdrop
			back.bar = back:CreateTexture(nil, "BACKGROUND")
			back.backdrop = CreateFrame("Frame", nil, back, BackdropTemplateMixin and "BackdropTemplate")
			bg.stBorderTable = { tile = false, insets = { left = 0, right = 0, top = 0, bottom = 0 }}
			bg.background = back
		end
		local w, h = bg.stWidth, bg.stHeight
		PSetSize(back, w, h); PSetSize(back.bar, w, h);
		back:Show(); back.bar:ClearAllPoints(); back.bar:SetAllPoints(back); back.bar:Show()
		back.anchorPoint = bg.growDirection and "BOTTOM" or "TOP"
		if bg.stTexture then back.bar:SetTexture(bg.stTexture) end
		local t = bg.stColor; if t then back.bar:SetVertexColor(t.r, t.g, t.b, t.a) end
		if bg.stBorderTexture then
			local offset = bg.stBorderOffset
			local d = bg.stBorderTable.insets; d.left = offset; d.right = offset; d.top = offset; d.bottom = offset
			bg.stBorderTable.edgeFile = bg.stBorderTexture; bg.stBorderTable.edgeSize = bg.stBorderWidth
			back.backdrop:SetBackdrop(bg.stBorderTable)
			local t = bg.stBorderColor; back.backdrop:SetBackdropBorderColor(t.r, t.g, t.b, t.a)
			PSetSize(back.backdrop, w + (2 * offset), h + (2 * offset))
			PCSetPoint(back.backdrop, "CENTER", back, "CENTER", 0, 0)
			back.backdrop:Show()
		else
			back.backdrop:Hide()
		end
	elseif config.bars == "timeline" then -- check if drawing the timeine backdrop with panel and numbers
		local back, dir = bg.background, 1
		if not back then -- need to create the background frame
			back = CreateFrame("Frame", nil, bg.frame)
			back:SetFrameLevel(bg.frame:GetFrameLevel() + 2) -- higher than bar group's backdrop
			back.bar = back:CreateTexture(nil, "BACKGROUND")
			back.backdrop = CreateFrame("Frame", nil, back, BackdropTemplateMixin and "BackdropTemplate")
			back.labels = {}; back.labelCount = 0
			bg.background = back
		end
		back.anchorPoint = "BOTTOMLEFT"
		local w, h, edge, offX, offY, justH, justV
		local iconWidth = rectIcons and bg.barWidth or bg.iconSize
		if config.orientation == "horizontal" then
			w = bg.tlWidth + iconWidth; h = bg.tlHeight; edge = "RIGHT"; justH = "RIGHT"; justV = "MIDDLE"
			if not bg.growDirection then back.anchorPoint = "BOTTOMRIGHT"; dir = -1; edge = "LEFT"; justH = "LEFT" end
			offX = -dir; offY = 0
		else
			w = bg.tlHeight; h = bg.tlWidth + bg.iconSize; edge = "TOP"; justH = "CENTER"; justV = "TOP"
			if not bg.growDirection then back.anchorPoint = "TOPLEFT"; dir = -1; edge = "BOTTOM"; justV = "BOTTOM" end
			offX = 0; offY = -dir
		end
		PSetSize(back, w, h); back:SetAlpha(bg.tlAlpha); PSetSize(back.bar, w, h);
		if bg.borderTexture then
			local offset = bg.tlBorderOffset
			local d = bg.borderTable.insets; d.left = offset; d.right = offset; d.top = offset; d.bottom = offset
			bg.borderTable.edgeFile = bg.tlBorderTexture; bg.borderTable.edgeSize = bg.tlBorderWidth
			back.backdrop:SetBackdrop(bg.borderTable)
			local t = bg.tlBorderColor; back.backdrop:SetBackdropBorderColor(t.r, t.g, t.b, t.a)
			PSetSize(back.backdrop, w + (2 * offset), h + (2 * offset))
		end
		if type(bg.tlLabels) == "table" then -- table of time values for labels
			local i = 1
			for _, v in pairs(bg.tlLabels) do
				local secs, hidem = tonumber(v), false
				if not secs then
					local start, m = string.find(v, "[%d%.]+m")
					if not start then start, m = string.find(v, "[%d%.]+M"); hidem = true end
					if start then
						local nv = string.sub(v, start, m - 1); secs = tonumber(nv); if secs then secs = secs * 60 end ; if hidem then v = nv end
					end
				end
				if secs and secs <= bg.tlDuration then
					if not back.labelCount then back.labelCount = 0 end
					if i > back.labelCount then back.labels[i] = back:CreateFontString(nil, "OVERLAY"); back.labelCount = back.labelCount + 1 end
					local fs = back.labels[i]
					fs:SetFontObject(ChatFontNormal); if ValidFont(bg.labelFont) then fs:SetFont(bg.labelFont, bg.labelFSize, bg.labelFlags) end
					local t = bg.labelColor; fs:SetTextColor(t.r, t.g, t.b, bg.labelAlpha); fs:SetShadowColor(0, 0, 0, bg.labelShadow and 1 or 0)
					fs:SetText(v); fs:SetJustifyH(justH); fs:SetJustifyV(justV); fs:ClearAllPoints()
					local delta = Timeline_Offset(bg, secs)
					local deltaX = delta + ((iconWidth + bg.labelFSize) / 2)
					local deltaY = delta + ((bg.iconSize + bg.labelFSize) / 2)
					local offsetX = (offX == 0) and 0 or ((deltaX - w) * dir)
					local offsetY = (offY == 0) and 0 or ((deltaY - h) * dir)
					PSetPoint(fs, edge, back, edge, offsetX + bg.labelInset, offsetY + bg.labelOffset)
					fs.hidden = false; i = i + 1
				end
			end
			while i <= back.labelCount do back.labels[i].hidden = true; i = i + 1 end
		end
	end
end

-- Set a bar's frame level, including that of all components it contains
local function SetBarFrameLevel(bar, level, isIcon)
	SetFrameLevel(bar.frame, level)
	if isIcon then
		SetFrameLevel(bar.container, level + 3)
		SetFrameLevel(bar.backdrop, level + 4)
		SetFrameLevel(bar.textFrame, level + 6)
		SetFrameLevel(bar.icon, level + 1)
		SetFrameLevel(bar.cooldown, level + 2)
		SetFrameLevel(bar.iconTextFrame, level + 5)
	else
		SetFrameLevel(bar.container, level + 1)
		SetFrameLevel(bar.backdrop, level + 2)
		SetFrameLevel(bar.textFrame, level + 8)
		SetFrameLevel(bar.icon, level + 5)
		SetFrameLevel(bar.cooldown, level + 6)
		SetFrameLevel(bar.iconTextFrame, level + 7)
	end
end

-- Update a bar's layout based on the bar group configuration and dimension settings.
-- Layout includes relative position of components plus mouse click rectangle and tooltip position.
-- Supports word wrap, label length (none, auto, manual), label horizontal alignment (left, right, center),
-- label vertical alignment (top, middle, bottom), time horizontal alignment (left and right for bars, center for icons),
-- timer vertical alignment (center for bars, below for icons), font size effects on all of the above,
-- label offset and inset, time offset and inset, default settings for bars and for icons, immediate response to changes.
local function Bar_UpdateLayout(bg, bar, config)
	local bl, bt, bi, bta, bf, bb = bar.labelText, bar.timeText, bar.iconText, bg.timeAlign, bar.fgTexture, bar.bgTexture
	local bat, bag = bar.attributes, bg.attributes

	bar.icon:ClearAllPoints(); bar.iconTexture:ClearAllPoints(); bar.spark:ClearAllPoints(); bar.cooldown:ClearAllPoints()
	bf:ClearAllPoints(); bb:ClearAllPoints(); bar.backdrop:ClearAllPoints(); bar.tick:ClearAllPoints()
	bl:ClearAllPoints(); bt:ClearAllPoints(); bi:ClearAllPoints()

	bl:SetFontObject(ChatFontNormal); bt:SetFontObject(ChatFontNormal); bi:SetFontObject(ChatFontNormal)
	bl:SetSize(0, 0); bl:SetWordWrap(bg.labelWrap); bt:SetJustifyV("MIDDLE")

	if ValidFont(bg.labelFont) then bl:SetFont(bg.labelFont, bg.labelFSize, bg.labelFlags) end
	if ValidFont(bg.timeFont) then bt:SetFont(bg.timeFont, bg.timeFSize, bg.timeFlags) end
	if ValidFont(bg.iconFont) then bi:SetFont(bg.iconFont, bg.iconFSize, bg.iconFlags) end

	bt:SetText("0:00:00") -- set to widest time string, note this is overwritten later with correct string!
	local timeMaxWidth = bt:GetStringWidth() -- get maximum text width using current font
	local iconWidth = (config.iconOnly and rectIcons) and bg.barWidth or bg.iconSize
	PSetSize(bar.icon, iconWidth or bg.iconSize, bg.iconSize)
	local w, h = bg.width, bg.height

	local isStripe = false
	if config.bars == "stripe" then isStripe = true end
	if config.iconOnly then -- icon only layouts
		PSetPoint(bar.icon, "TOPLEFT", bar.frame, "TOPLEFT", 0, 0)
		if (bg.barHeight > 0) and (bg.barWidth > 0) and config.bars ~= "timeline" then
			local offset = (w - bg.barWidth) / 2 -- how far bars start from edge of frame
			if config.bars == "r2l" or isStripe then
				PSetPoint(bf, "TOPLEFT", bar.icon, "BOTTOMLEFT", bg.iconOffsetX + offset + bar.includeOffset, -bg.iconOffsetY)
				PSetPoint(bb, "TOPRIGHT", bar.icon, "BOTTOMRIGHT", bg.iconOffsetX - offset + bar.includeOffset, -bg.iconOffsetY)
			elseif config.bars == "l2r" then
				PSetPoint(bf, "TOPRIGHT", bar.icon, "BOTTOMRIGHT", bg.iconOffsetX - offset, -bg.iconOffsetY)
				PSetPoint(bb, "TOPLEFT", bar.icon, "BOTTOMLEFT", bg.iconOffsetX + offset, -bg.iconOffsetY)
			end
			PSetHeight(bf, bg.barHeight); PSetHeight(bb, bg.barHeight)
		end

		local fr, fl = 0, 0
		if iconWidth < timeMaxWidth then -- make sure enough room for widest time string
			local dw = timeMaxWidth - iconWidth
			if bta == "LEFT" then fr = dw elseif bta == "RIGHT" then fl = dw else fr = dw / 2; fl = dw / 2 end
		end

		local padding = bg.barWidth - iconWidth -- if bar is wider than icon then increase time text width
		if padding > 0 then padding = padding / 2; fl = fl + padding; fr = fr + padding end

		PSetPoint(bt, "TOPRIGHT", bar.icon, "BOTTOMRIGHT", bg.timeInset + fr, bg.timeOffset) -- align top of time text with bottom of icon
		PSetPoint(bt, "BOTTOMLEFT", bar.icon, "BOTTOMLEFT", bg.timeInset - fl, bg.timeOffset - bg.timeFSize) -- set bottom so text doesn't jitter
		if bta == "normal" then bt:SetJustifyH("CENTER") else bt:SetJustifyH(bta) end

		if not isStripe then
			PSetPoint(bl, "LEFT", bar.icon, "LEFT", bg.labelInset, bg.labelOffset)
			bl:SetJustifyH("CENTER")
		end

		PSetPoint(bl, "RIGHT", bar.icon, "RIGHT", bg.labelInset + bg.barWidth, bg.labelOffset)
		bl:SetJustifyV(bg.labelAlign)
	else -- bar layouts
		local ti, offsetLeft, offsetRight, fudgeTime, fudgeLabel = bg.timeIcon and bg.showIcon, 0, 0, 0, 0
		if bta == "normal" then fudgeTime = PS(4) end
		if not bg.labelCenter then fudgeLabel = PS(4) end

		if bg.showIcon then
			if config.icon == "left" then
				PSetPoint(bar.icon, "TOPLEFT", bar.frame, "TOPLEFT", bg.iconOffsetX, bg.iconOffsetY)
				offsetLeft = bg.iconSize
			elseif config.icon == "right" then
				PSetPoint(bar.icon, "TOPRIGHT", bar.frame, "TOPRIGHT", bg.iconOffsetX, bg.iconOffsetY)
				offsetRight = bg.iconSize
			end
		end

		local labelWidth = bg.barWidth
		if bg.labelAdjust then -- bar groups can optionally adjust the label width
			if not bg.labelAuto then -- check if manual or auto adjustment
				labelWidth = (bg.barWidth * bg.labelWidth / 100) -- set label width as percentage of bar width
			elseif not bg.timeIcon then -- do not auto adjust if time is being shown on icon instead of bar
				labelWidth = bg.barWidth - timeMaxWidth -- set label width based on max time width using current font
			end
			if labelWidth < 30 then labelWidth = 30 end -- enforce minimum width for the label
		end

		if ti then
			PSetPoint(bt, "TOPLEFT", bar.icon, "TOPLEFT", bg.timeInset - PS(10), bg.timeOffset)
			PSetPoint(bt, "BOTTOMRIGHT", bar.icon, "BOTTOMRIGHT", bg.timeInset + PS(12), bg.timeOffset) -- pad right to center time text better
		end

		if config.label == "right" then
			if not ti then
				PSetPoint(bt, "TOPLEFT", bar.frame, "TOPLEFT", bg.timeInset + offsetLeft + fudgeTime, bg.timeOffset)
				PSetPoint(bt, "BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", bg.timeInset - offsetRight, bg.timeOffset)
			end
			local tx = bg.labelInset - offsetRight - fudgeLabel
			local pt, la, lc = "RIGHT", bg.labelAlign, bg.labelCenter
			if la == "TOP" then pt = "TOPRIGHT" elseif la == "BOTTOM" then pt = "BOTTOMRIGHT" end
			PSetPoint(bl, pt, bar.frame, pt, tx, bg.labelOffset)
			PSetWidth(bl, labelWidth)
			if lc then bl:SetJustifyH("CENTER") else bl:SetJustifyH("RIGHT") end
			if bta == "normal" then bt:SetJustifyH(ti and "CENTER" or "LEFT") else bt:SetJustifyH(bg.timeAlign) end
		elseif config.label == "left" then
			if not ti then
				PSetPoint(bt, "TOPLEFT", bar.frame, "TOPLEFT", bg.timeInset + offsetLeft, bg.timeOffset)
				PSetPoint(bt, "BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", bg.timeInset - offsetRight - fudgeTime, bg.timeOffset)
			end
			local tx = bg.labelInset + offsetLeft + fudgeLabel
			local pt, la, lc = "LEFT", bg.labelAlign, bg.labelCenter
			if la == "TOP" then pt = "TOPLEFT" elseif la == "BOTTOM" then pt = "BOTTOMLEFT" end
			PSetPoint(bl, pt, bar.frame, pt, tx, bg.labelOffset)
			PSetWidth(bl, labelWidth)
			if lc then bl:SetJustifyH("CENTER") else bl:SetJustifyH("LEFT") end
			if bta == "normal" then bt:SetJustifyH(ti and "CENTER" or "RIGHT") else bt:SetJustifyH(bg.timeAlign) end
		end

		local count = bg.segmentCount -- create, size and position segments on demand
		if bg.segmentOverride and bat.segmentCount then count = bat.segmentCount end -- override with bar setting
		if count and (count >= 1) and (count <= 10) then
			if not bar.segmentsAllocated then AllocateSegments(bar) end
			local segmentSpacing = PS((bg.segmentSpacing or 1) - 2) -- minimum is side-by-side with overlapping borders
			local bw, bh = bg.barWidth + PS(2), bg.barHeight
			local bc = bg.segmentBorderColor or defaultBlack
			local segmentWidth = PS((bw - (segmentSpacing * (count - 1))) / count)
			local totalWidth = (segmentWidth * count) + (segmentSpacing * (count - 1))
			local extraPixels = math.floor(((bw - totalWidth) / PS(1)) + 0.5) -- how many pixels too many or too few
			local deltaX, deltaY, curve, rotate, texture = 0, 0, 0, 0, false
			local curveChord, curveTheta, curveRadius, curveCX, curveCY, curveDir, rotateSin, rotateCos
			if bg.segmentAdvanced then
				rotate = math.pi * bg.segmentRotate / 180 -- amount of rotation to apply to segment arrangement
				rotateSin = math.sin(rotate)
				rotateCos = math.cos(rotate)
				texture = bg.segmentTexture
				curve = bg.segmentCurve
				if (curve ~= 0) and (count > 2) then
					curveChord = (count - 1) * (segmentWidth + segmentSpacing) -- length of chord connecting start and end points
					if curveChord > 0 then
						curveTheta = math.pi * math.abs(curve) / 360 -- interior angle for the arc between the two points in radians, varies by curvature
						curveRadius = curveChord / ( 2 * math.sin(curveTheta))
						local hmid = math.sqrt((curveRadius * curveRadius) - (curveChord * curveChord / 4))
						curveDir = (curve > 0) and 1 or -1
						curveCX = curveChord / 2
						curveCY = -curveDir * hmid
						-- if IsAltKeyDown() then MOD.Debug(curveChord, curveTheta, curveRadius, hmid, curveDir, curveCX, curveCY) end
					end
				end
			end

			for i = 1, 10 do
				local f = bar.segments[i]
				local sf, sb = f.fgTexture, f.bgTexture
				local fudge = 0
				if (extraPixels < 0) and (i <= -extraPixels) then fudge = PS(-1) elseif (extraPixels > 0) and (i <= extraPixels) then fudge = PS(1) end
				local sw = segmentWidth + fudge
				f:ClearAllPoints(); f:Hide(); sf:ClearAllPoints(); sb:ClearAllPoints()
				f.segmentHeight = bh -- save so available for shrink partial options
				if i <= count then
					if texture and textures[texture] then
						f.segmentWidth = bh
						PSetSize(f, bh, bh); PSetSize(sf, bh, bh); PSetSize(sb, bh, bh)
						f:SetBackdrop(nil) -- remove backdrop, if any
						sf:SetTexture(textures[texture])
						sb:SetTexture(textures[texture]); sb:SetAlpha(bg.bgAlpha)
					else
						f.segmentWidth = sw
						PSetSize(f, sw, bh); PSetSize(sf, sw, bh); PSetSize(sb, sw, bh)
						iconBackdrop.edgeSize = PS(1) -- used for single pixel backdrops
						f:SetBackdrop(iconBackdrop) -- add a backdrop for single pixel border around each segment
						f:SetBackdropColor(1, 1, 1, 0.5) -- backdrop is set to white, color is supplied by textures
						f:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a) -- backdrop border color defaults to black but can be set in options
						sf:SetTexture(bg.fgTexture)
						sb:SetTexture(bg.bgTexture); sb:SetAlpha(bg.bgAlpha)
					end
					local curveX, curveY = 0, 0
					if (curve ~= 0) and (count > 2) and (curveChord > 0) and (i ~= 1) and (i ~= count) then
						local angle = curveDir * 2 * (((i - 1) / (count - 1) * curveTheta) - (curveTheta / 2)) -- angle to current point on curve from midpoint of curve
						local cx = curveDir * curveRadius * math.sin(angle) -- distance to center of arc
						local cy = curveDir * curveRadius * math.cos(angle)
						curveX = PS(cx + curveCX - deltaX)
						curveY = PS(cy + curveCY - deltaY)
						-- if IsAltKeyDown() then MOD.Debug("point", i, angle, cx, cy, curveX, curveY) end
					end
					local dx = deltaX + curveX
					local dy = deltaY + curveY
					if rotate ~= 0 then
						local tx, ty = dx, dy
						dx = (tx * rotateCos) - (ty * rotateSin)
						dy = (ty * rotateCos) + (tx * rotateSin)
					end
					if config.bars == "r2l" then
						PSetPoint(f, "BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", -offsetRight - dx + PS(1), dy)
						PSetPoint(sf, "BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
						PSetPoint(sb, "BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
					elseif config.bars == "l2r" then
						PSetPoint(f, "BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offsetLeft + dx - PS(1), dy)
						PSetPoint(sf, "BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
						PSetPoint(sb, "BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
					end
					deltaX = deltaX + sw + segmentSpacing
				end
			end
		elseif bar.segmentsAllocated then
			for _, f in pairs(bar.segments) do f:ClearAllPoints(); f:Hide() end
		end

		if config.bars == "r2l" then
			PSetPoint(bf, "TOPLEFT", bar.frame, "TOPLEFT", offsetLeft, 0)
			PSetPoint(bb, "TOPRIGHT", bar.frame, "TOPRIGHT", -offsetRight, 0)
		elseif config.bars == "l2r" then
			PSetPoint(bf, "TOPRIGHT", bar.frame, "TOPRIGHT", -offsetRight, 0)
			PSetPoint(bb, "TOPLEFT", bar.frame, "TOPLEFT", offsetLeft, 0)
		end
		PSetHeight(bf, h); PSetHeight(bb, h)
	end

	if config.bars == "r2l" or isStripe then
		PSetPoint(bar.spark, "TOP", bf, "TOPRIGHT", 0, 4)
		PSetPoint(bar.spark, "BOTTOM", bf, "BOTTOMRIGHT", 0, -4)
	elseif config.bars == "l2r" then
		PSetPoint(bar.spark, "TOP", bf, "TOPLEFT", 0, 4)
		PSetPoint(bar.spark, "BOTTOM", bf, "BOTTOMLEFT", 0, -4)
	end

	PSetSize(bar.tick, 1, bg.barHeight - PS(4))
	bar.tooltipAnchor = bag.anchorTips

	if bg.labelSpecial then
		bl:SetTextColor(bar.ibr, bar.ibg, bar.ibb, bg.labelAlpha)
	else
		local t = bg.labelColor
		bl:SetTextColor(bar.label_r or t.r, bar.label_g or t.g, bar.label_b or t.b, bg.labelAlpha)
	end
	bl:SetShadowColor(0, 0, 0, bg.labelShadow and 1 or 0)

	if bg.timeSpecial then
		bt:SetTextColor(bar.ibr, bar.ibg, bar.ibb, bg.timeAlpha)
	else
		local t = bg.timeColor
		bt:SetTextColor(bar.time_r or t.r, bar.time_g or t.g, bar.time_b or t.b, bg.timeAlpha)
	end
	bt:SetShadowColor(0, 0, 0, bg.timeShadow and 1 or 0)
	bt:SetText(nil); bl:SetText(nil) -- forces update of properties, esp. alignment

	if bg.iconSpecial then
		bi:SetTextColor(bar.ibr, bar.ibg, bar.ibb, bg.iconAlpha)
	else
		local t = bg.iconColor
		bi:SetTextColor(t.r or 0, t.g or 0, t.b or 0, bg.iconAlpha)
	end
	bi:SetShadowColor(0, 0, 0, bg.iconShadow and 1 or 0)

	if config.bars ~= "timeline" then SetBarFrameLevel(bar, bg.frame:GetFrameLevel() + 5, config.iconOnly) end
	if bg.showIcon then
		PSetPoint(bi, "LEFT", bar.icon, "LEFT", bg.iconInset - PS(10), bg.iconOffset)
		PSetPoint(bi, "RIGHT", bar.icon, "RIGHT", bg.iconInset + PS(12), bg.iconOffset) -- pad right to center time text better
		bi:SetJustifyH(bg.iconAlign); bi:SetJustifyV("MIDDLE")
		if MSQ and bg.MSQ_Group and Raven.db.global.ButtonFacadeIcons then -- if using Masque, set custom fields in button data table and add to skinnning group
			PSetSize(bar.cooldown, iconWidth, bg.iconSize)
			PSetPoint(bar.cooldown, "CENTER", bar.icon, "CENTER")
			IconTextureTrim(bar.iconTexture, bar.icon, false, iconWidth, bg.iconSize) -- trim and zoom with support for rectangular icons
			local ulx, uly, llx, lly, urx, ury, lrx, lry = bar.iconTexture:GetTexCoord() -- save the tex coords because need to restore after masque does its thing
			bg.MSQ_Group:RemoveButton(bar.icon, true) -- needed so size changes work when icon is reused
			local bdata = bar.buttonData
			bdata.Icon = bar.iconTexture
			bdata.Normal = bar.icon:GetNormalTexture()
			bdata.Cooldown = bar.cooldown
			bdata.Border = bar.iconBorder
			bg.MSQ_Group:AddButton(bar.icon, bdata)
			if zoomIcons then -- only need to do this for rectangular icons with zoom enabled
				bar.iconTexture:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry) -- set to the saved tex coords since overwritten when masque adds the button
			end
		else -- if not then use a default button arrangment
			if bg.MSQ_Group then bg.MSQ_Group:RemoveButton(bar.icon) end -- remove skin, if any
			if not ((UseTukui() and MOD.db.global.TukuiIcon) or Raven.db.global.HideBorder) then
				local sliceWidth, sliceHeight = 0.91 * iconWidth, 0.91 * bg.iconSize
				PSetSize(bar.cooldown, sliceWidth, sliceHeight)
				PSetPoint(bar.cooldown, "CENTER", bar.icon, "CENTER")
				IconTextureTrim(bar.iconTexture, bar.icon, true, sliceWidth, sliceHeight)
				bar.iconBorder:SetTexture("Interface\\AddOns\\Raven\\Borders\\IconDefault")
				bar.icon:SetBackdrop(nil)
			elseif Raven.db.global.PixelIconBorder then -- optional custom pixel perfect border
				PSetSize(bar.cooldown, iconWidth, bg.iconSize)
				PSetPoint(bar.cooldown, "CENTER", bar.icon, "CENTER")
				IconTextureTrim(bar.iconTexture, bar.icon, Raven.db.global.TrimIcon, iconWidth - PS(2), bg.iconSize - PS(2))
				iconBackdrop.edgeSize = PS(1) -- used for single pixel backdrops
				bar.icon:SetBackdrop(iconBackdrop)
				local t = MOD.db.global.DefaultIconBackdropColor; bar.icon:SetBackdropColor(t.r, t.g, t.b, t.a)
				bar.iconBorder:SetColorTexture(0, 0, 0, 0)
			else
				bar.icon:SetBackdrop(nil)
				PSetSize(bar.cooldown, iconWidth, bg.iconSize)
				PSetPoint(bar.cooldown, "CENTER", bar.icon, "CENTER")
				IconTextureTrim(bar.iconTexture, bar.icon, (UseTukui() or Raven.db.global.TrimIcon), iconWidth, bg.iconSize)
				bar.iconBorder:SetColorTexture(0, 0, 0, 0)
			end
		end
	end

	PSetSize(bar.frame, w, h); PSetSize(bar.container, w, h); bar.container:SetAllPoints()

	if bg.showBar and bg.borderTexture and not bat.header and bar.includeBar then
		local offset = bg.borderOffset
		local d = bg.borderTable.insets; d.left = offset; d.right = offset; d.top = offset; d.bottom = offset
		bg.borderTable.edgeFile = bg.borderTexture; bg.borderTable.edgeSize = bg.borderWidth
		PSetSize(bar.backdrop, bg.barWidth + offset, bg.barHeight + offset)
		PSetPoint(bar.backdrop, "CENTER", bb, "CENTER")
		bar.backdrop:SetBackdrop(bg.borderTable)
		local t = bg.borderColor; bar.backdrop:SetBackdropBorderColor(t.r, t.g, t.b, t.a)
		bar.backdrop:Show()
	else
		bar.backdrop:SetBackdrop(nil); bar.backdrop:Hide()
	end
end

-- Convert a time value into a compact text string
MOD.Nest_TimeFormatOptions = {
	{ 1, 1, 1, 1, 1 }, { 1, 1, 1, 3, 5 }, { 1, 1, 1, 3, 4 }, { 2, 3, 1, 2, 3 }, -- 4
	{ 2, 3, 1, 2, 2 }, { 2, 3, 1, 3, 4 }, { 2, 3, 1, 3, 5 }, { 2, 2, 2, 2, 3 }, -- 8
	{ 2, 2, 2, 2, 2 }, { 2, 2, 2, 2, 4 }, { 2, 2, 2, 3, 4 }, { 2, 2, 2, 3, 5 }, -- 12
	{ 2, 3, 2, 2, 3 }, { 2, 3, 2, 2, 2 }, { 2, 3, 2, 2, 4 }, { 2, 3, 2, 3, 4 }, -- 16
	{ 2, 3, 2, 3, 5 }, { 2, 3, 3, 2, 3 }, { 2, 3, 3, 2, 2 }, { 2, 3, 3, 2, 4 }, -- 20
	{ 2, 3, 3, 3, 4 }, { 2, 3, 3, 3, 5 }, { 3, 3, 3, 2, 3 }, { 3, 3, 3, 3, 5 }, -- 24
	{ 4, 3, 1, 2, 3 }, { 4, 3, 1, 2, 2 }, { 4, 3, 1, 3, 4 }, { 4, 3, 1, 3, 5 }, -- 28
	{ 5, 1, 1, 2, 3 }, { 5, 1, 1, 2, 2 }, { 5, 1, 1, 3, 4 }, { 5, 1, 1, 3, 5 }, -- 32
	{ 3, 3, 3, 2, 2 }, { 3, 3, 3, 3, 4 }, { 6, 4, 4, 4, 6 }, -- 35
}

function MOD.Nest_FormatTime(t, timeFormat, timeSpaces, timeCase)
	if not timeFormat or (timeFormat > #MOD.Nest_TimeFormatOptions) then timeFormat = 24 end -- default to most compact
	timeFormat = math.floor(timeFormat)
	if timeFormat < 1 then timeFormat = 1 end
	local opt = MOD.Nest_TimeFormatOptions[timeFormat]
	local func = opt.custom
	local d, h, m, hplus, mplus, s, ts, f
	if func then -- check for custom time formatting options
		f = func(t)
	else
		local o1, o2, o3, o4, o5 = opt[1], opt[2], opt[3], opt[4], opt[5]
		if t >= 86400 then -- special case for more than one day which applies regardless of selected format
			d = math.floor(t / 86400); h = math.floor((t - (d * 86400)) / 3600)
			if (d >= 2) then f = string.format("%.0fd", d) else f = string.format("%.0fd %.0fh", d, h) end
		else
			h = math.floor(t / 3600); m = math.floor((t - (h * 3600)) / 60); s = math.floor(t - (h * 3600) - (m * 60))
			hplus = math.floor((t + 3599.99) / 3600); mplus = math.floor((t - (h * 3600) + 59.99) / 60) -- provides compatibility with tooltips
			ts = math.floor(t * 10) / 10 -- truncated to a tenth second
			if t >= 3600 then
				if o1 == 1 then
					f = string.format("%.0f:%02.0f:%02.0f", h, m, s)
				elseif o1 == 2 then
					f = string.format("%.0fh %.0fm", h, m)
				elseif o1 == 3 then
					f = string.format("%.0fh", hplus)
				elseif o1 == 6 then
					f = string.format("%.0f_h", hplus)
				elseif o1 == 4 then
					f = string.format("%.0fh %.0f", h, m)
				else
					f = string.format("%.0f:%02.0f", h, m)
				end
			elseif t >= 120 then
				if o2 == 1 then
					f = string.format("%.0f:%02.0f", m, s)
				elseif o2 == 2 then
					f = string.format("%.0fm %.0fs", m, s)
				elseif o2 == 4 then
					f = string.format("%.0f_m", mplus)
				else
					f = string.format("%.0fm", mplus)
				end
			elseif t >= 60 then
				if o3 == 1 then
					f = string.format("%.0f:%02.0f", m, s)
				elseif o3 == 2 then
					f = string.format("%.0fm %.0fs", m, s)
				elseif o3 == 4 then
					f = string.format("%.0f_m", mplus)
				else
					f = string.format("%.0fm", mplus)
				end
			elseif t >= 10 then
				if o4 == 1 then
					f = string.format(":%02.0f", s)
				elseif o4 == 2 then
					f = string.format("%.0fs", s)
				elseif o4 == 4 then
					f = string.format("%.0f_s", s)
				else
					f = string.format("%.0f", s)
				end
			else
				if o5 == 1 then
					f = string.format(":%02.0f", s)
				elseif o5 == 2 then
					f = string.format("%.1fs", ts)
				elseif o5 == 3 then
					f = string.format("%.0fs", s)
				elseif o5 == 4 then
					f = string.format("%.1f", ts)
				elseif o5 == 6 then
					f = string.format("%.0f_s", s)
				else
					f = string.format("%.0f", s)
				end
			end
		end
	end
	if not timeSpaces then f = string.gsub(f, " ", "") end
	f = string.gsub(f, "_", " ")
	if timeCase then f = string.upper(f) end
	return f
end

-- Validate a custom time format function and update sample output
function MOD.Nest_ValidateCustomTimeFormatFunction()
	local p = MOD.db.global
	local s = p.customTimeFunction
	userDefinedTimeFormatFunction = nil; p.userDefinedSample = nil; p.userDefinedMessage = L["User-defined function not valid"]
	if p.customTimeFormat and s and s ~= "" then -- maybe have a valid user-defined function
		local fstring = "return function(t)\n" .. s .. "\nend"
		local func, msg = loadstring(fstring) -- this will compile fstring into a function that returns the actual conversion function
		if not func then
			p.userDefinedMessage = msg -- loadstring returns nil and an error message if fails to create the function
		else
			local success, uf = pcall(func) -- this will call the function returned by loadstring to create the actual function
			if not success then
				p.userDefinedMessage = msg -- pcall returns a boolean for success and an error message if false
			elseif type(uf(1)) ~= "string" then
				p.userDefinedMessage = L["User-defined function does not return a string"] -- error if user-defined function has wrong return value
			else
				p.userDefinedSample = uf(8125.8) .. ", " .. uf(343.8) .. ", " .. uf(75.3) .. ", " .. uf(42.7) .. ", " .. uf(3.6)
				userDefinedTimeFormatFunction = uf
				p.userDefinedMessage = L["User-defined function is valid"]
				local index = customTimeFormatIndex
				if not index then
					index = #MOD.Nest_TimeFormatOptions
					index = index + 1
				end
				MOD.Nest_TimeFormatOptions[index] = { custom = uf } -- add the custom time format to the table
				customTimeFormatIndex = index
			end
		end
	end
	-- MOD.Debug(p.userDefinedMessage, p.userDefinedSample)
	if not userDefinedTimeFormatFunction then
		if customTimeFormatIndex then
			table.remove(MOD.Nest_TimeFormatOptions, customTimeFormatIndex) -- remove the custom format from the table
			customTimeFormatIndex = nil
		end
		return false
	end
	return true
end

-- Return string containing an example of a custom time format function
function MOD.Nest_SampleCustomTimeFormatFunction()
	return
	[[-- sample function that converts the value t in seconds to a custom formatted string and returns the string
    local h = math.floor(t / 3600) -- hours to use if also showing minutes
    local hplus = math.floor((t + 3599.99) / 3600) -- hours to use without minutes, compatible with tooltips
    local m = math.floor((t - (h * 3600)) / 60) -- minutes to use if also showing seconds
    local mplus = math.floor((t - (h * 3600) + 59.99) / 60) -- minutes to use without seconds, compatible with tooltips
    local s = math.floor(t - (h * 3600) - (m * 60)) -- seconds to use if only showing whole number of seconds
    local ts = math.floor(t * 10) / 10 -- seconds to use if including tenths
    if t >= 7200 then -- more than 2 hours
        return string.format('%.0fh', hplus)
    elseif t >= 3600 then -- more than 1 hour
        return string.format('%.0fh %.0fm', h, mplus)
    elseif t >= 120 then -- more than 2 minutes
        return string.format('%.0fm', mplus)
    elseif t >= 60 then -- more than 1 minute
        return string.format('%.0f:%02.0f', m, s)
    elseif t >= 10 then -- more than 10 seconds
        return string.format('%.0f', s)
    end
    return string.format('%.1f', ts) -- last 10 seconds include tenths]]
end

-- Add a formatting function to the table of time format options.
-- While it is possible to use both a registered time format function and a custom time format
-- entered on the Defaults tab, format index gets saved as an integer and could get out of sync
-- if one or the other is disabled.
function MOD.Nest_RegisterTimeFormat(func)
	local index = #MOD.Nest_TimeFormatOptions
	index = index + 1
	MOD.Nest_TimeFormatOptions[index] = { custom = func }
	return index
end

--[[
-- Example custom time formatting module for Raven.
if not Raven then return end
local MODULE_NAME = "Raven_Custom_Time"
local MOD = Raven
local module = MOD:NewModule(MODULE_NAME)

local function timeFunc(t)
	-- sample function that converts the value of t in seconds to a custom formatted string and then returns the string
	-- the string may contain escape sequences that to color the text
	local h = math.floor(t / 3600) -- hours to use if also showing minutes
	local hplus = math.floor((t + 3599.99) / 3600) -- hours to use without minutes, compatible with tooltips
	local m = math.floor((t - (h * 3600)) / 60) -- minutes to use if also showing seconds
	local mplus = math.floor((t - (h * 3600) + 59.99) / 60) -- minutes to use without seconds, compatible with tooltips
	local s = math.floor(t - (h * 3600) - (m * 60)) -- seconds to use if only showing whole number of seconds
	local ts = math.floor(t * 10) / 10 -- seconds to use if including tenths

	if t >= 7200 then -- more than 2 hours
		return string.format("%.0fh", hplus)
	elseif t >= 3600 then -- more than 1 hour
		return string.format("%.0fh %.0fm", h, mplus)
	elseif t >= 120 then -- more than 2 minutes
		return string.format("%.0fm", mplus)
	elseif t >= 60 then -- more than 1 minute
		return string.format("%.0f:%02.0f", m, s)
	elseif t >= 10 then -- more than 10 seconds
		return string.format("%.0f", s)
	end
	return string.format("%.1f", ts) -- last seconds show tenths
end

function module:OnInitialize()
	local index = Raven:RegisterTimeFormat(timeFunc)
	print("Registered custom time format with Raven, index #", index)
end
]]--

-- Update labels and colors plus for timer bars adjust bar length and formatted time text
local function Bar_UpdateSettings(bg, bar, config)
	local bat, bag = bar.attributes, bg.attributes
	local fill, sparky, ticky, hideBar, offsetX, showBorder = 1, false, false, true, 0, false -- fill is fraction of the bar to display, default to full bar
	local timeText, labelText = "", ""
	local bt, bl, bi, bf, bb, bx, btf = bar.timeText, bar.labelText, bar.iconText, bar.fgTexture, bar.bgTexture, bar.iconBorder, bar.tipFrame
	local isHeader = bat.header
	if not bat.hideLabel then labelText = bar.label end -- optionally suppress label for a custom bar
	if bar.timeLeft and bar.duration and bar.maxTime and bar.offsetTime then -- only update if key parameters are set
		local remaining = bar.duration - (GetTime() - bar.startTime + bar.offsetTime) -- remaining time in seconds
		if (remaining < 0) or bat.ghostTime then remaining = 0 end -- make sure no rounding funnies and make sure ghost bars show 0 time
		if remaining > bar.duration then remaining = bar.duration end -- and no inaccurate durations!
		bar.timeLeft = remaining -- update saved value
		if remaining < bar.maxTime then fill = remaining / bar.maxTime end -- calculate fraction of time remaining
		if bg.fillBars then fill = 1 - fill end -- optionally fill instead of empty bars
		timeText = MOD.Nest_FormatTime(remaining, bg.timeFormat, bg.timeSpaces, bg.timeCase) -- set timer text
	elseif bar.value and bar.maxValue then
		if bar.value < 0 then bar.value = 0 end -- no negative values
		if bar.value < bar.maxValue then fill = bar.value / bar.maxValue end -- adjust foreground bar width based on values
		if bg.fillBars then fill = 1 - fill end -- optionally fill instead of empty bars
		if bar.valueText then timeText = bar.valueText else timeText = tostring(bar.value) end -- set time text to value or override with value text
		if not bat.hideLabel and bar.valueLabel then labelText = bar.valueLabel end
		if bar.tickEnable and bar.tickOffset then bar.duration = bar.maxValue; bar.maxTime = bar.duration end -- if value has tick then maxValue is duration in seconds
	end

	if bg.showIcon and not isHeader then
		offsetX = bg.iconSize
		if bar.iconPath and not bar.hideIcon then bar.icon:Show(); bar.iconTexture:SetTexture(bar.iconPath) else bar.icon:Hide() end
		bar.iconTexture:SetDesaturated(bat.desaturate) -- optionally desaturate the bar's icon

		if bar.shine then ShineEffect(bar, bat.shineColor) end -- trigger shine animation
		if bar.sparkle then SparkleEffect(bar, bat.sparkleColor) end -- trigger sparkle animation
		if bar.pulse then PulseEffect(bar) end -- trigger pulse animation

		if MSQ and Raven.db.global.ButtonFacadeIcons then -- icon border coloring
			if Raven.db.global.ButtonFacadeIcons and Raven.db.global.ButtonFacadeBorder and bx and bx.SetVertexColor then
				bx:SetVertexColor(bar.ibr, bar.ibg, bar.ibb, bar.iba); showBorder = true
			end
			local nx = MSQ:GetNormal(bar.icon)
			if Raven.db.global.ButtonFacadeNormal and nx and nx.SetVertexColor then nx:SetVertexColor(bar.ibr, bar.ibg, bar.ibb, bar.iba) end
		else
			if UseTukui() and MOD.db.global.TukuiIcon then
				local bdrop = bar.icon.backdrop or bar.icon.Backdrop
				if bdrop then
					if bat.iconColors == "None" then
						bdrop:SetBackdropBorderColor(bar.tukcolor_r, bar.tukcolor_g, bar.tukcolor_b, bar.tukcolor_a)
					else
						bdrop:SetBackdropBorderColor(bar.ibr, bar.ibg, bar.ibb, bar.iba)
					end
				end
			elseif not Raven.db.global.HideBorder then
				bx:SetAllPoints(bar.icon); bx:SetVertexColor(bar.ibr, bar.ibg, bar.ibb, bar.iba); showBorder = true
			else
				if Raven.db.global.PixelIconBorder then -- optional custom pixel perfect border
					bar.icon:SetBackdropBorderColor(bar.ibr, bar.ibg, bar.ibb, bar.iba)
				end
				showBorder = false
			end
		end
	else
		bar.icon:Hide()
	end

	if showBorder and bar.iconPath then bx:Show() else bx:Hide() end
	if bg.showIcon and not bg.iconHide and not isHeader and bar.iconCount then bi:SetText(tostring(bar.iconCount)); bi:Show() else bi:Hide() end
	if bg.showIcon and not isHeader and bg.showCooldown and config.bars ~= "timeline" and bar.timeLeft and (bar.timeLeft >= 0) then
		bar.cooldown:SetReverse(bag.clockReverse)
		bar.cooldown:SetCooldown(bar.startTime - bar.offsetTime, bar.duration); bar.cooldown:Show()
	else
		bar.cooldown:Hide()
	end

	if bg.showTimeText then bt:SetText(timeText); bt:Show() else bt:Hide() end
	if (bg.showLabelText or isHeader) and bar.label then bl:SetText(labelText); bl:Show() else bl:Hide() end

	if bg.showBar and bar.includeBar and (config.bars ~= "timeline") then
		local w, h = bg.width - offsetX, bg.height; if config.iconOnly then w = bg.barWidth; h = bg.barHeight end
		local bf_r, bf_g, bf_b = MOD.Nest_AdjustColor(bar.cr, bar.cg, bar.cb, bg.fgSaturation or 0, bg.fgBrightness or 0)
		local bb_r, bb_g, bb_b = MOD.Nest_AdjustColor(bar.br, bar.bg, bar.bb, bg.bgSaturation or 0, bg.bgBrightness or 0)
		local count = bg.segmentCount -- create, size and position segments on demand
		if bg.segmentOverride and bat.segmentCount then count = bat.segmentCount end -- override with bar setting
		if count and (count >= 1) and (count <= 10) then
			local x = fill * count
			local fullSegments = math.floor(x) -- how many full segments to show
			local px = x - fullSegments -- how much is left over
			for i = 1, count do
				local f = bar.segments[i]
				local sf, sb = f.fgTexture, f.bgTexture
				if bg.segmentGradient and (count > 1) then -- override standard foreground color with gradient
					local sc = (i - 1) / (count - 1) -- for individual colors, select based on the segment number
					if bg.segmentGradientAll then sc = fill end -- for colors all together, select based on current value
					local c1, c2 = bg.segmentGradientStartColor or defaultGreen, bg.segmentGradientEndColor or defaultRed
					bf_r, bf_g, bf_b = MOD.Nest_IntermediateColor(c1.r, c1.g, c1.b, c2.r, c2.g, c2.b, sc)
				end
				sf:SetVertexColor(bf_r, bf_g, bf_b); sb:SetVertexColor(bb_r, bb_g, bb_b)
				if i <= (fullSegments + ((px >= (1 / f.segmentWidth)) and 1 or 0)) then -- configure all visible segments including partial
					sf:SetAlpha(bg.fgAlpha); PSetSize(sf, f.segmentWidth, f.segmentHeight) -- settings that might be changed for partial segments
					if i > fullSegments then -- partial segment
						if bg.segmentFadePartial then sf:SetAlpha(bg.fgAlpha * px) end
						if bg.segmentShrinkWidth then PSetWidth(sf, f.segmentWidth * px) end
						if bg.segmentShrinkHeight then PSetHeight(sf, f.segmentHeight * px) end
					end
					sf:Show(); sb:Show(); f:Show()
				else -- empty segment
					sf:Hide()
					if bg.segmentHideEmpty then sb:Hide(); f:Hide() else sb:Show(); f:Show() end
				end
			end
		elseif (w > 0) and (h > 0) then -- non-zero dimensions to fix the zombie bar bug
			bb:SetVertexColor(bb_r, bb_g, bb_b, 1); bb:SetTexture(bg.bgTexture); bb:SetAlpha(bg.bgAlpha)
			PSetWidth(bb, w); bb:SetTexCoord(0, 1, 0, 1); bb:Show()
			if bar.tukbar then bar.tukbar:SetAllPoints(bb); bar.tukbar:Show() end -- elvui backdrop is under the background texture
			hideBar = false

			local fillw = w * fill
			local showfg = bg.fgNotTimer
			if bat.fullReverse then showfg = not showfg end
			if (fillw > 0) and (showfg or bar.timeLeft) then
				bf:SetVertexColor(bf_r, bf_g, bf_b, 1); bf:SetTexture(bg.fgTexture); bf:SetAlpha(bg.fgAlpha)
				if fillw > 0 then bf:SetWidth(fillw) end -- doesn't get pixel perfect treatment
				if bg.showSpark and fill < 1 and fillw > 1 then sparky = true end
				if config.bars == "r2l" or config.bars == "stripe" then bf:SetTexCoord(0, 0, 0, 1, fill, 0, fill, 1) else bf:SetTexCoord(fill, 0, fill, 1, 0, 0, 0, 1) end
				bf:Show()
				if bar.tickEnable and bar.tickOffset and bar.tickOffset > 0 and bar.duration and bar.duration > 0 and bar.maxTime then -- show tick mark if enabled
					local tickFill = bar.tickOffset / bar.maxTime -- fraction of visible bar that represents the expire time
					if bg.fillBars then tickFill = 1 - tickFill end -- growDirection if filling instead of emptying bars
					local offset = w * tickFill -- calculate where the tick mark should be, avoiding the very ends of the bar
					if (offset > 1) and (offset < (w - 1)) then
						bar.tick:SetColorTexture(bar.tr, bar.tg, bar.tb, bar.ta)
						if config.bars == "r2l" then
							PSetPoint(bar.tick, "TOP", bar.fgTexture, "TOPLEFT", PS(offset), -PS(2))
							PSetPoint(bar.tick, "BOTTOM", bar.fgTexture, "BOTTOMLEFT", PS(offset), PS(2))
						elseif config.bars == "l2r" then
							PSetPoint(bar.tick, "TOP", bar.fgTexture, "TOPRIGHT", -PS(offset), -PS(2))
							PSetPoint(bar.tick, "BOTTOM", bar.fgTexture, "BOTTOMRIGHT", -PS(offset), PS(2))
						end
						ticky = true
					end
				end
			else bf:Hide() end
		end
	end

	if hideBar then bf:Hide(); bb:Hide() if bar.tukbar then bar.tukbar:Hide() end end
	if sparky then bar.spark:Show() else bar.spark:Hide() end
	if ticky then bar.tick:Show() else bar.tick:Hide() end
	if bar.glow then GlowEffect(bar, bat.glowColor) else ReleaseGlowEffect(bar) end -- enable or disable glow effect

	local alpha = bar.alpha or 1 -- adjust by bar alpha
	bar.alpha = alpha
	local fade = true
	if bat.header and bag.headerGaps then alpha = 0; fade = false end -- header bars can be made to disappear to create gaps

	if bar.flash then -- apply alpha adjustments, including flash and fade effects
		local minAlpha
		local pct = bat.flashPercent
		if pct and (pct >= 0) and (pct <= 100) then minAlpha = alpha * pct / 100 else minAlpha = alpha / 2 end
		bar.flashPeriod = bat.flashPeriod or 1.2
		bar.minAlpha = minAlpha
		FlashEffect(bar)
	else
		ReleaseFlashEffect(bar)
		FaderEffect(bar, alpha, fade)
	end

	btf:ClearAllPoints() -- frame used to enable interactivity with bars in icon configs

	if not isHeader and (bag.noMouse or (bag.iconMouse and not bg.showIcon)) then -- non-interactive or "only icon" but icon disabled
		bar.icon:EnableMouse(false); bar.frame:EnableMouse(false); btf:EnableMouse(false); if callbacks.deactivate then callbacks.deactivate(bar.overlay) end
	elseif not isHeader and bag.iconMouse then -- only icon is interactive
		bar.icon:EnableMouse(true); bar.frame:EnableMouse(false); btf:EnableMouse(false); if callbacks.activate then callbacks.activate(bar, bar.icon) end
	else -- entire bar is interactive
		if config.iconOnly and (bg.barWidth > 0) and (bg.barHeight > 0) then -- enable interactivity with potentially separated bars in icon configs
			PSetPoint(btf, "TOP", bar.icon, "BOTTOM", bg.iconOffsetX, -bg.iconOffsetY) -- adjust location and dimensions to match bar
			PSetSize(btf, bg.barWidth, bg.barHeight)
			bar.icon:EnableMouse(true); bar.frame:EnableMouse(false); btf:EnableMouse(true); if callbacks.activate then callbacks.activate(bar, bar.icon) end
		else
			bar.icon:EnableMouse(false); bar.frame:EnableMouse(true); btf:EnableMouse(false); if callbacks.activate then callbacks.activate(bar, bar.frame) end
		end
	end

	if bat.header and not bag.headerGaps then
		bf:SetAlpha(0); bb:SetAlpha(0)
		local id, tag = bat.tooltipUnit, ""
		if id == UnitGUID("mouseover") then tag = "|cFF73d216@|r" end
		if id == UnitGUID("target") then tag = tag .. " |cFFedd400target|r" end
		if id == UnitGUID("focus") then tag = tag .. " |cFFf57900focus|r" end
		if tag ~= "" then bt:SetText(tag); bt:Show() end
	end
end

-- Update the lengths of timer bars, spark positions, and alphas of flashing bars
local function Bar_RefreshAnimations(bg, bar, config)
	local bat, bag = bar.attributes, bg.attributes
	local fill, sparky, offsetX, now, forced = 1, false, 0, GetTime(), false
	if bar.timers then -- check special effect timers and force updates so that they happen on time
		for k, t in pairs(bar.timers) do if t <= now then MOD:ForceUpdate(); forced = true break end end
		if forced then for k, t in pairs(bar.timers) do if t <= (now + 0.01) then bar.timers[k] = nil end end end
	end

	local timeText = nil
	if bar.timeLeft and bar.duration and bar.maxTime and bar.offsetTime then -- only update if key parameters are set
		local remaining = bar.duration - (now - bar.startTime + bar.offsetTime) -- remaining time in seconds
		if (remaining < 0) or bat.ghostTime then remaining = 0 end -- make sure no rounding funnies and make sure ghost bars show 0 time
		if remaining > bar.duration then remaining = bar.duration end -- and no inaccurate durations!
		bar.timeLeft = remaining -- update saved value
		if remaining < bar.maxTime then fill = remaining / bar.maxTime end -- calculate fraction of time remaining
		if bg.fillBars then fill = 1 - fill end -- optionally fill instead of empty bars
		timeText = MOD.Nest_FormatTime(remaining, bg.timeFormat, bg.timeSpaces, bg.timeCase) -- get formatted timer text
	elseif bar.value and bar.maxValue then
		if bar.value < 0 then bar.value = 0 end -- no negative values
		if bar.value < bar.maxValue then fill = bar.value / bar.maxValue end -- adjust foreground bar width based on values
		if bg.fillBars then fill = 1 - fill end -- optionally fill instead of empty bars
		if bar.valueText then timeText = bar.valueText else timeText = tostring(bar.value) end -- set time text to value or override with value text
	end

	if not bat.header then
		if bg.showTimeText then bar.timeText:SetText(timeText) end
		if bg.showIcon then offsetX = bg.iconSize end
	end

	local showfg = bg.fgNotTimer
	if bat.fullReverse then showfg = not showfg end

	if bg.showBar and bar.includeBar and (config.bars ~= "timeline") then
		local count = bg.segmentCount -- create, size and position segments on demand
		if bg.segmentOverride and bat.segmentCount then count = bat.segmentCount end -- override with bar setting
		if count and (count >= 1) and (count <= 10) then
			local x = fill * count
			local fullSegments = math.floor(x) -- how many full segments to show
			local px = x - fullSegments -- how much is left over
			for i = 1, count do
				local f = bar.segments[i]
				local sf, sb = f.fgTexture, f.bgTexture
				if bg.segmentGradient and (count > 1) and bg.segmentGradientAll then -- override standard foreground color with gradient for dynamic case
					local c1, c2 = bg.segmentGradientStartColor or defaultGreen, bg.segmentGradientEndColor or defaultRed
					local bf_r, bf_g, bf_b = MOD.Nest_IntermediateColor(c1.r, c1.g, c1.b, c2.r, c2.g, c2.b, fill)
					sf:SetVertexColor(bf_r, bf_g, bf_b)
				end
				if i <= (fullSegments + ((px >= (1 / f.segmentWidth)) and 1 or 0)) then -- configure all visible segments including partial
					sf:SetAlpha(bg.fgAlpha); PSetSize(sf, f.segmentWidth, f.segmentHeight) -- settings that might be changed for partial segments
					if i > fullSegments then -- partial segment
						if bg.segmentFadePartial then sf:SetAlpha(bg.fgAlpha * px) end
						if bg.segmentShrinkWidth then PSetWidth(sf, f.segmentWidth * px) end
						if bg.segmentShrinkHeight then PSetHeight(sf, f.segmentHeight * px) end
					end
					sf:Show(); sb:Show(); f:Show()
				else -- empty segment
					sf:Hide()
					if bg.segmentHideEmpty then sb:Hide(); f:Hide() else sb:Show(); f:Show() end
				end
			end
		elseif (fill > 0) and (showfg or bar.timeLeft) then
			local bf, w, h = bar.fgTexture, bg.width - offsetX, bg.height; if config.iconOnly then w = bg.barWidth; h = bg.barHeight end
			if (w > 0) and (h > 0) then
				local fillw = w * fill
				if fillw > 0 then bf:SetWidth(fillw) end -- doesn't get pixel perfect treatment
				if bg.showSpark and fill < 1 and fillw > 1 then sparky = true end
				if config.bars == "r2l" or config.bars == "stripe" then bf:SetTexCoord(0, 0, 0, 1, fill, 0, fill, 1) else bf:SetTexCoord(fill, 0, fill, 1, 0, 0, 0, 1) end
				bf:Show()
			else bf:Hide() end
		end
		if sparky then bar.spark:Show() else bar.spark:Hide() end
	end
end

-- Update icon positions on timeline after animation refresh
local function BarGroup_RefreshTimeline(bg, config)
	local dir = bg.growDirection and 1 or -1 -- plus or minus depending on direction
	local isVertical = (config.orientation == "vertical")
	local maxBars = bg.maxBars; if not maxBars or (maxBars == 0) then maxBars = bg.count end
	local back, level, t, lastBar = bg.background, bg.frame:GetFrameLevel() + 5, GetTime(), nil
	local w, h, edge, lastDelta, lastBar, lastLevel
	if config.orientation == "horizontal" then
		w = bg.tlWidth; h = bg.tlHeight; edge = bg.growDirection and "RIGHT" or "LEFT"
	else
		w = bg.tlHeight; h = bg.tlWidth; edge = bg.growDirection and "TOP" or "BOTTOM"
	end
	local overlapCount, switchCount = 0, 0
	for i = 1, bg.count do
		local bar = bg.bars[bg.sorter[i].name]
		if i <= maxBars then
			local clevel = level + ((bg.count - i) * 10)
			local delta = Timeline_Offset(bg, bar.timeLeft or 0)
			local isOverlap = i > 1 and lastBar and math.abs(delta - lastDelta) < (bg.iconSize * (1 - ((bg.tlPercent or 50) / 100)))
			if isOverlap then overlapCount = overlapCount + 1 else overlapCount = 0 end -- number of overlapping icons
			if bg.tlAlternate and isOverlap then
				switchCount = switchCount + 1
				local phase = math.floor(t / (bg.tlSwitch or 2)) -- time between alternating overlapping icons
				if switchCount == 1 then
					if (phase % 2) == 1 then SetBarFrameLevel(lastBar, clevel, true); clevel = lastLevel end
				else
					local seed = phase % (switchCount + 1) -- 0, 1, ..., switchCount
					for k = 1, switchCount do
						local b = bg.bars[bg.sorter[i - k].name]
						SetBarFrameLevel(b, clevel + (((seed + k) % (switchCount + 1)) * 10), true)
					end
					clevel = clevel + (seed * 10)
				end
			else
				switchCount = 0
			end
			SetBarFrameLevel(bar, clevel, true)
			lastDelta = delta; lastBar = bar; lastLevel = clevel
			local x1 = isVertical and 0 or ((delta - w) * dir); local y1 = isVertical and ((delta - h) * dir) or 0
			y1 = y1 + (bg.tlOffset or 0) + (overlapCount * (bg.tlDelta or 0))
			PCSetPoint(bar.frame, edge, back, edge, x1, y1)
			bar.frame:Show()
		else
			lastBar = nil; bar.frame:Hide()
		end
	end
end

-- Refresh all the icons on the stripe, aligning left or middle or right, placing them side-by-side, with width
-- determined by whether or not icon is included and the width of the label with potential variable width override.
-- This is designed for brokers but should also work with other icons (default right alignment)
local function BarGroup_RefreshStripe(bg)
	local back = bg.background
	local bag = bg.attributes
	local leftWidth, centerWidth, rightWidth = 0, 0, 0
	local iw, tw, hw
	local sx, inset, offset, bw = bg.spacingX, bg.labelInset, bg.labelOffset, bg.width

	for i = 1, bg.count do -- build tables of icons for each alignment, preserving sort order and computing widths
		local bar = bg.bars[bg.sorter[i].name]
		local bat = bar.attributes
		local bl = bar.labelText
		local isCenter = false

		if bar.icon:IsShown() then iw = bar.icon:GetWidth() else iw = 0 end
		tw = bl:GetStringWidth() -- actual string width currently being displayed as text, will be 0 if not showing text
		if bat.minimumWidth and bat.maximumWidth then
			if tw < bat.minimumWidth then tw = bat.minimumWidth end
			if bat.maximumWidth > 0 and tw > bat.maximumWidth then tw = bat.maximumWidth end -- ignore max = 0
		end
		if tw > 0 then -- restructure the icon's parts depending on what is being shown
			if iw > 0 then -- anchor text and bar on right side of the icon with appropriate inset/offset
				PSetPoint(bl, "LEFT", bar.icon, "RIGHT", inset, bg.offset)
				PSetPoint(bl, "RIGHT", bar.icon, "RIGHT", inset + tw, bg.offset)
			else -- anchor text and bar on left side of the icon (which is not being shown) with appropriate inset/offset
				PSetPoint(bl, "LEFT", bar.icon, "LEFT", inset, bg.offset)
				PSetPoint(bl, "RIGHT", bar.icon, "LEFT", inset + tw, bg.offset)
			end
			bl:SetJustifyH("LEFT")
		end
		tw = tw + (inset > 0 and inset or 0)
		hw = tw; if iw == 0 and bw < tw then hw = hw - bw end -- compute interactive area width
		if not bag.noMouse and not bag.iconMouse then bar.frame:SetHitRectInsets(0, -hw, 0, 0) end
		tw = tw + iw -- width of icon plus text plus extra space
		if bat.horizontalAlign == "left" then
			table.insert(alignLeft, bar); leftWidth = leftWidth + tw
		elseif bat.horizontalAlign == "center" then
			table.insert(alignCenter, bar); centerWidth = centerWidth + tw
		else -- must be default right alignment
			table.insert(alignRight, bar); rightWidth = rightWidth + tw
		end
		bar.adjustedWidth = tw -- needed in later passes for each alignment
	end

	if #alignLeft > 1 then leftWidth = leftWidth + (sx * (#alignLeft - 1)) end -- include spacing between icons
	if #alignCenter > 1 then centerWidth = centerWidth + (sx * (#alignCenter - 1)) end
	if #alignRight > 1 then rightWidth = rightWidth + (sx * (#alignRight - 1)) end

	local x = bg.stBarInset -- horizontal offset for first left-aligned icon
	for _, bar in pairs(alignLeft) do -- position each icon within its alignment group
		bar.frame:ClearAllPoints()
		PSetPoint(bar.frame, "LEFT", back, "LEFT", x, bg.stBarOffset)
		bar.frame:Show()
		x = x + bar.adjustedWidth + sx
		bar.adjustedWidth = nil -- remove temporary width variable from the bar
	end

	x = -bg.stBarInset - rightWidth -- position them from left to right
	for _, bar in pairs(alignRight) do -- arrange all the right alignment icons
		bar.frame:ClearAllPoints()
		PSetPoint(bar.frame, "LEFT", back, "RIGHT", x, bg.stBarOffset)
		bar.frame:Show()
		x = x + bar.adjustedWidth + sx
		bar.adjustedWidth = nil -- remove temporary width variable from the bar
	end

	x = -centerWidth / 2 -- position them from left to right
	for _, bar in pairs(alignCenter) do -- arrange all the center alignment icons
		bar.frame:ClearAllPoints()
		PSetPoint(bar.frame, "LEFT", back, "CENTER", x, bg.stBarOffset)
		bar.frame:Show()
		x = x + bar.adjustedWidth + sx
		bar.adjustedWidth = nil -- remove temporary width variable from the bar
	end

	table.wipe(alignLeft); table.wipe(alignRight); table.wipe(alignCenter) -- clear the temporary tables
end

-- Update bar order and calculate offsets within the bar stack plus overall width and height of the frame
local function BarGroup_SortBars(bg, config)
	local tid = UnitGUID("target")
	local unlimited = bg.attributes.noDurationFirst and 0 or 100000 -- really big number sorts like infinite time
	for i = 1, bg.count do -- fill data into the sorting table
		local s = bg.sorter[i]
		local bar = bg.bars[s.name]
		if not bar.startTime or not bar.offsetTime then s.start = 0 else s.start = bar.startTime - bar.offsetTime end
		if not bar.timeLeft or not bar.duration then
			s.timeLeft = unlimited; s.duration = unlimited
		else
			s.timeLeft = bar.timeLeft; s.duration = bar.duration
		end
		local id = bar.attributes.group; if bg.attributes.targetFirst and id and tid and id == tid then id = "" end -- sorts to front of the list
		s.group = id or ""; s.gname = bar.attributes.groupName or (bg.growDirection and "zzzzzzzzzzzz" or "")
		s.isMine = bar.attributes.isMine; s.class = bar.attributes.class or ""; s.sortPlayer = bg.sortPlayer; s.sortTime = bg.sortTime
	end
	local isTimeline, isStripe = false, false
	if config.bars == "timeline" then bg.sortFunction = SortTimeUp; isTimeline = true end
	if config.bars == "stripe" then isStripe = true end
	table.sort(bg.sorter, bg.sortFunction)
	local wrap = 0 -- indicates default of not wrapping
	local dir = bg.growDirection and 1 or -1 -- plus or minus depending on direction
	local x0, y0, x1, y1 = 0, 0, 0, 0 -- starting position must be offset by dimensions of anchor if unlocked
	local dx, dy = dir * (bg.width + bg.spacingX), dir * (bg.height + bg.spacingY) -- offsets for each new bar
	local wx, wy = 0, 0 -- offsets from starting point when need to wrap
	local bw, bh = 0, 0 -- number of bar widths and heights in size of backdrop
	local xoffset, yoffset, xdir, ydir, wadjust = 0, 0, 1, dir, 0 -- position adjustments for backdrop
	local count, maxBars, cdir = bg.count, bg.maxBars, 0
	if not maxBars or (maxBars == 0) then maxBars = count end
	if not isStripe and count > maxBars then count = maxBars end
	local ac = count -- actual count before wrap adjustment
	if bg.wrap and not isTimeline then wrap = bg.wrap; if (wrap > 0) and (count > wrap) then count = wrap end end
	local anchorPoint = "BOTTOMLEFT"
	if config.iconOnly then -- icons can go any direction from anchor
		if config.orientation == "vertical" then
			wx = -dx; dx = 0; bh = count; if count > 0 then bw = math.ceil(ac / count) else bw = 1 end
			if not bg.locked then y0 = dy; bh = bh + 1 end
			if not bg.growDirection then anchorPoint = "TOPLEFT"; wx = -wx; cdir = -1 end
			if not bg.wrapDirection then xoffset = -(bw - 1) * (bg.width + bg.spacingX) end
			if bg.snapCenter and bg.locked then local z = (dy * (((count - dir) / 2) + cdir)); y0 = y0 - z; yoffset = yoffset - z end
			if bg.wrapDirection then wx = -wx end
			if wrap > 0 then -- attachment options differ when wrapping
				bg.lastRow = x0 + (wx * bw); bg.lastColumn = y0 + (dy * count); bg.lastX = nil; bg.lastY = nil
			else
				bg.lastX = x0; bg.lastY = y0 + (dy * count); bg.lastRow = nil; bg.lastColumn = nil
			end
		else -- horizontal
			wy = dy; dy = 0; bw = count; if count > 0 then bh = math.ceil(ac / count) else bh = 1 end
			if not bg.locked then x0 = dx; bw = bw + 1 end
			if bg.growDirection then anchorPoint = "BOTTOMRIGHT"; wy = -wy; cdir = -1 end
			if not bg.wrapDirection then yoffset = -(bh - 1) * (bg.height + bg.spacingY) end
			if dir < 0 then
				xoffset = dir * (bw - 1) * (bg.width + bg.spacingX); ydir = -ydir
			else
				xoffset = (bw - 1) * (bg.width + bg.spacingX); xdir = -1
			end
			if bg.snapCenter and bg.locked then local z = (dx * (((count + dir) / 2) + cdir)); x0 = x0 - z; xoffset = xoffset - z end
			if bg.wrapDirection then wy = -wy end
			if wrap > 0 then -- attachment options differ when wrapping
				bg.lastRow = x0 + (dx * count); bg.lastColumn = y0 + (wy * bh); bg.lastX = nil; bg.lastY = nil
			else
				bg.lastX = x0 + (dx * count); bg.lastY = y0; bg.lastRow = nil; bg.lastColumn = nil
			end
		end
	else -- bars just go up or down with anchor set to top or bottom
		wx = -dx; dx = 0; bh = count
		if count > 0 then bw = math.ceil(ac / count) else bw = 1 end
		if bg.showIcon then wadjust = bg.iconOffsetX end
		if bg.wrapDirection then xoffset = wadjust else xoffset = wadjust - (bw - 1) * (bg.width + bg.spacingX) end
		if not bg.locked then y0 = y0 + dy; bh = bh + 1 end
		if not bg.growDirection then anchorPoint = "TOPLEFT"; wx = -wx end
		if bg.wrapDirection then wx = -wx end
		if wrap > 0 then -- attachment options differ for wrapping bar groups
			bg.lastRow = x0 + (wx * bw); bg.lastColumn = y0 + (dy * count); bg.lastX = nil; bg.lastY = nil
		else
			bg.lastX = x0; bg.lastY = y0 + (dy * count); bg.lastRow = nil; bg.lastColumn = nil
		end
	end
	count = bg.count
	if isTimeline then
		BarGroup_RefreshTimeline(bg, config)
	elseif isStripe then
		BarGroup_RefreshStripe(bg)
	else
		for i = 1, count do
			local bar = bg.bars[bg.sorter[i].name]
			bar.frame:ClearAllPoints()
			if i <= maxBars then
				local w, skip = i - 1, 0; if wrap > 0 then skip = math.floor(w / wrap); w = w % wrap end
				x1 = x0 + (dx * w) + (wx * skip); y1 = y0 + (dy * w) + (wy * skip)
				PSetPoint(bar.frame, anchorPoint, bg.frame, anchorPoint, x1, y1)
				bar.frame:Show()
			else
				bar.frame:Hide()
			end
		end
	end
	PSetSize(bg.frame, bg.width, bg.height)
	bg.anchorPoint = anchorPoint -- reference position for attaching bar groups together
	local back = bg.background
	if back then
		if isTimeline and (not bg.tlHide or (count > 0)) and not inPetBattle then
			PCSetPoint(back, back.anchorPoint, bg.frame, back.anchorPoint, x0, y0)
			ShowTimeline(bg)
			count = 1 -- trigger drawing backdrop
		elseif isStripe then
			local a = (back.anchorPoint == "TOP") and "BOTTOM" or "TOP"
			local x = bg.stInset
			if bg.stFullWidth then x = bg.frame:GetCenter(); x = (GetScreenWidth() / 2) - x end -- keep full width bars centered
			PCSetPoint(back, back.anchorPoint, bg.frame, a, x, bg.stOffset)
			count = 1 -- trigger drawing backdrop
		else HideTimeline(bg) end
	end
	if count > 0 then
		local w, h
		if isTimeline then
			w, h = back:GetSize(); xoffset = 0; yoffset = 0
			if not bg.locked then if config.orientation == "horizontal" then w = w + bg.width + bg.spacingX else h = h + bg.height + bg.spacingY end end
			if config.orientation == "horizontal" then xdir = -xdir; if anchorPoint == "BOTTOMRIGHT" then anchorPoint = "BOTTOMLEFT" else anchorPoint = "BOTTOMRIGHT" end end
		else
			w = bw * bg.width; if bw > 1 then w = w + ((bw - 1) * bg.spacingX) end
			h = bh * bg.height; if bh > 1 then h = h + ((bh - 1) * bg.spacingY) end
		end
		local offset = 4
		if (bg.backdropTexture or bg.backdropPanel) then
			offset = bg.backdropPadding
			local x, d = bg.backdropInset, bg.backdropTable.insets; d.left = x; d.right = x; d.top = x; d.bottom = x
			bg.backdropTable.bgFile = bg.backdropPanel; bg.backdropTable.edgeFile = bg.backdropTexture; bg.backdropTable.edgeSize = bg.backdropWidth
			bg.backdrop:SetBackdrop(bg.backdropTable)
			local t = bg.backdropColor; bg.backdrop:SetBackdropBorderColor(t.r, t.g, t.b, t.a)
			t = bg.backdropFill; bg.backdrop:SetBackdropColor(t.r, t.g, t.b, t.a)
		else
			bg.backdrop:SetBackdrop(nil)
		end
		PSetSize(bg.backdrop, w + offset - wadjust + bg.backdropPadW, h + offset + bg.backdropPadH)
		xoffset = xoffset + bg.backdropOffsetX; yoffset = yoffset + bg.backdropOffsetY
		PCSetPoint(bg.backdrop, anchorPoint, bg.frame, anchorPoint, (-xdir * offset / 2) + xoffset, (-ydir * offset / 2) + yoffset)
		bg.backdrop:SetFrameStrata("BACKGROUND")
		bg.backdrop:Show()
	else
		bg.backdrop:Hide()
	end
	local scale = bg.frame:GetScale()
	if math.abs(bg.scale - scale) > 0.001 then -- only adjust scale if it has changed by a detectable amount
		if bg.relativeTo then -- if anchored to another bar group then just change the scale
			bg.frame:SetScale(bg.scale)
		else -- if not anchored make sure the position doesn't get changed
			scale = scale / bg.scale -- compute scaling factor
			x0 = bg.frame:GetLeft() * scale; y0 = bg.frame:GetBottom() * scale -- normalize by scale factor
			bg.frame:SetScale(bg.scale)
			PCSetPoint( bg.frame, "BOTTOMLEFT", nil, "BOTTOMLEFT", x0, y0)
		end
	end
end

-- Update relative positions between bar groups, has to be called on every update for the lastbar feature to work right
local function UpdateRelativePositions()
	for _, bg in pairs(barGroups) do
		if bg.configuration and bg.relativeTo then
			local rbg = barGroups[bg.relativeTo]
			if rbg then
				if rbg.count == 0 then
					local i = 0
					while (rbg.count == 0) and rbg.relativeEmpty and rbg.relativeTo do
						rbg = barGroups[rbg.relativeTo]
						i = i + 1; if i > 20 then break end -- safety check, never loop more than 20 deep
					end
				end
				local align, offsetX, offsetY = "BOTTOMLEFT", 0, 0
				if (rbg.count > 0) or not bg.relativeEmpty then
					offsetX, offsetY = bg.relativeX / bg.scale, bg.relativeY / bg.scale
					if bg.relativeLastBar then -- alternative is to attach to the last bar rendered back in the other bar group
						-- print(bg.name, rbg.name, rbg.lastX, rbg.lastY, rbg.lastRow, rbg.lastColumn, bg.relativeRow, bg.relativeColumn, offsetX, offsetY)
						align = rbg.anchorPoint
						if rbg.lastX and rbg.lastY then offsetX = offsetX + rbg.lastX; offsetY = offsetY + rbg.lastY
						elseif bg.relativeRow and rbg.lastRow then offsetX = offsetX + rbg.lastRow
						elseif bg.relativeColumn and rbg.lastColumn then offsetY = offsetY + rbg.lastColumn end
					end
				end
				PCSetPoint(bg.frame, align, rbg.frame, align, offsetX, offsetY)
			end
		end
	end
end

-- Check configuration and minimum values to determine frame width and height
local function SetBarGroupEffectiveDimensions(bg, config)
	local w, h, minimumWidth, minimumHeight = bg.barWidth or 10, bg.barHeight or 10, 5, 5
	if config.iconOnly then
		w = rectIcons and bg.barWidth or bg.iconSize; h = bg.iconSize -- icon configs start with icon size and add room for bar and time text, if they are displayed
		h = h + (bg.showBar and (bg.barHeight + math.max(0, bg.iconOffsetY)) or 0)
	else
		if bg.showIcon then w = w + bg.iconSize end -- bar config start with bar size and add room for icon if it is displayed
	end
	if h < minimumHeight then h = minimumHeight end -- enforce minimums for dimensions
	if w < minimumWidth then w = minimumWidth end
	bg.width = PS(w); bg.height = PS(h)
	if not bg.scale then bg.scale = 1 end
end

-- Check if display dimensions have changed and update bar group locations
function MOD.Nest_CheckDisplayDimensions()
	local dw, dh = UIParent:GetWidth(), UIParent:GetHeight()
	if (displayWidth ~= dw) or (displayHeight ~= dh) then
		displayWidth = dw; displayHeight = dh
		for _, bg in pairs(barGroups) do
			if bg.configuration then -- make sure configuration is valid
				local p = bg.position
				MOD.Nest_SetAnchorPoint(bg, p.left, p.right, p.bottom, p.top, bg.scale, p.width, p.height) -- restore cached position
			end
		end
	end
end

-- Force a global update
function MOD.Nest_TriggerUpdate()
	update = true
end

-- Update pixel perfect scaling settings
function MOD.Nest_UpdatePixelScale(displayReport)
	if MOD.db.global.AdjustUIScale then -- option to adjust "UIscale" for optimized pixel perfect alignment on monitor
		pixelWidth, pixelHeight = GetPhysicalScreenSize() -- size in pixels of display in full screen, otherwise window size in pixels
		pixelScale = GetScreenHeight() / pixelHeight -- figure out how big virtual pixels are versus screen pixels
		pixelPerfect = (not MOD.db.global.TukuiSkin and MOD.db.global.PixelPerfect) or (MOD.db.global.TukuiSkin and MOD.db.global.TukuiScale)

		local oscale = GetCVar("uiScale")
		local pscale = 768 / pixelHeight
		local x = MOD.db.global.SetUIScale
		if MOD.db.global.OverrideUIScale and x and (x >= 0.1) and (x <= 1) then pscale = x end
		if math.abs(oscale - pscale) > 0.0001 then -- only adjust if necessary, avoid feedback with other addons
			if GetCVar("useUiScale") ~= 1 then SetCVar("useUiScale", 1) end
			SetCVar("uiScale", pscale)
			-- UIParent:SetScale(pscale) -- this also works, it is how ElvUI does it, but we don't in order to be compatible with ElvUI
			displayReport = true
		end
		if not MOD.db.global.SilentUIScale and displayReport then
			print("Raven: detected display resolution " .. tostring(pixelWidth) .. "x" .. tostring(pixelHeight) ..
					", adjusted UI scale from " .. tostring(oscale) .. " to " .. tostring(pscale))
		end
	end
end

-- Initialize the module
function MOD.Nest_Initialize()
	if Raven.MSQ then
		MSQ = Raven.MSQ
		MSQ_ButtonData = { AutoCast = false, AutoCastable = false, Border = false, Checked = false, Cooldown = false, Count = false, Duration = false,
						   Disabled = false, Flash = false, Highlight = false, HotKey = false, Icon = false, Name = false, Normal = false, Pushed = false }
	end

	MOD.Nest_UpdatePixelScale(true)

	rectIcons = (MOD.db.global.RectIcons == true)
	zoomIcons = rectIcons and (MOD.db.global.ZoomIcons == true)
	MOD.Nest_ValidateCustomTimeFormatFunction() -- this will validate a custom time format and add it to the options list
end

-- Return the pixel perfect scaling factor
function MOD.Nest_PixelScale() return pixelScale end

-- Return the actual screen resolution expressed in pixels
function MOD.Nest_ScreenResolution() return pixelWidth, pixelHeight end

-- Adjust bar group's alpha after checking mouseover
local function BarGroup_Alpha(bg)
	local drop, back = bg.backdrop, bg.background
	local mouse = drop:IsShown() and drop:IsMouseOver(2, -2, -2, 2)
	if back and back:IsShown() then mouse = back:IsMouseOver(2, -2, -2, 2) end
	local alpha = mouse and bg.mouseAlpha or bg.alpha
	if not alpha or (alpha < 0) or (alpha > 1) then alpha = 1 end; bg.frame:SetAlpha(alpha)
end

-- Update routine does all the actual work of setting up and displaying bar groups.
function MOD.Nest_Update()
	if MOD.ExpansionIsOrAbove(LE_EXPANSION_MISTS_OF_PANDARIA) then
		if C_PetBattles.IsInBattle() then -- force update when entering or leaving pet battles to hide anchors and timeline
			if not inPetBattle then inPetBattle = true; update = true end
		else
			if inPetBattle then inPetBattle = false; update = true end
		end
	end

	-- pixelScale = GetScreenHeight() / pixelHeight -- not needed when tracking uiScale changes
	-- if IsAltKeyDown() then MOD.Debug("Raven uiScale", pixelScale, UIParent:GetEffectiveScale(), pixelWidth, pixelHeight, GetCVar("uiScale"), GetScreenWidth(), GetScreenHeight()) end
	-- if IsShiftKeyDown() then MOD.Debug("pixelScale", pixelScale, "UI scale", UIParent:GetScale(), "UI effscale", UIParent:GetEffectiveScale(), "UI size", UIParent:GetSize()) end

	for _, bg in pairs(barGroups) do
		if bg.configuration then -- make sure configuration is valid
			local config = MOD.Nest_SupportedConfigurations[bg.configuration]
			if not bg.disableAlpha then BarGroup_Alpha(bg) end
			if not bg.moving then bg.frame:SetFrameStrata(bg.strata or "MEDIUM") end
			SetBarGroupEffectiveDimensions(bg, config) -- stored in bg.width and bg.height
			if update or bg.update then BarGroup_UpdateAnchor(bg, config); BarGroup_UpdateBackground(bg, config) end
			for _, bar in pairs(bg.bars) do
				if update or bg.update or bar.update then -- see if any bar configurations need to be updated
					Bar_UpdateLayout(bg, bar, config) -- configure internal bar layout
				end
				Bar_UpdateSettings(bg, bar, config) -- update bar color, times, and texts plus activate buff buttons
				bar.update = false
			end
			BarGroup_SortBars(bg, config) -- update bar order and relative positions plus overall frame dimensions
			bg.update = false
		end
	end
	UpdateRelativePositions() -- has to be done every time to support relative positioning to last bar
	UpdateSplashAnimations() -- check for completed bar animations
	update = false
end

-- Just refresh timers and flashing bars without checking settings.
function MOD.Nest_Refresh()
	for _, bg in pairs(barGroups) do
		if bg.configuration then -- make sure configuration is valid
			local config = MOD.Nest_SupportedConfigurations[bg.configuration]
			SetBarGroupEffectiveDimensions(bg, config) -- stored in bg.width and bg.height
			for _, bar in pairs(bg.bars) do if not bar.update then Bar_RefreshAnimations(bg, bar, config) end end
			if config.bars == "timeline" then BarGroup_RefreshTimeline(bg, config) end
			if not bg.disableAlpha then BarGroup_Alpha(bg) end
		end
	end
	UpdateSplashAnimations() -- check for completed bar animations
end
