local MOD = Raven
local SHIM = MOD.SHIM

local NOP = function(...)
	return
end

do -- C_Container
	local GetContainerItemID, GetContainerNumSlots

	-- GetContainerItemID
	if C_Container and C_Container.GetContainerItemID then
		GetContainerItemID = C_Container.GetContainerItemID
	elseif _G.GetContainerItemID then
		GetContainerItemID = _G.GetContainerItemID
	end
	function SHIM:GetContainerItemID(bag, slot)
		return GetContainerItemID(bag, slot)
	end

	-- GetContainerNumSlots
	if C_Container and C_Container.GetContainerNumSlots then
		GetContainerNumSlots = C_Container.GetContainerNumSlots
	elseif _G.GetContainerNumSlots then
		GetContainerNumSlots = _G.GetContainerNumSlots
	end
	function SHIM:GetContainerNumSlots(bag)
		return GetContainerNumSlots(bag)
	end
end

do -- C_CurrencyInfo
	local GetCoinTextureString

	-- GetCoinTextureString
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString
	elseif _G.GetCoinTextureString then
		GetCoinTextureString = _G.GetCoinTextureString
	end
	function SHIM:GetCoinTextureString(amount)
		return GetCoinTextureString(amount)
	end
end

do -- C_Item/C_Container
	local GetItemCooldown, GetItemCount, GetItemIconByID, GetItemInfo, GetItemSpell, IsUsableItem

	-- GetItemCooldown
	if C_Item and C_Item.GetItemCooldown then
		GetItemCooldown = C_Item.GetItemCooldown
	elseif C_Container and C_Container.GetItemCooldown then
		GetItemCooldown = C_Container.GetItemCooldown
	elseif _G.GetItemCooldown then
		GetItemCooldown = _G.GetItemCooldown
	end
	function SHIM:GetItemCooldown(item)
		return GetItemCooldown(item)
	end

	-- GetItemCount
	if C_Item and C_Item.GetItemCount then
		GetItemCount = C_Item.GetItemCount
	elseif _G.GetItemCount then
		GetItemCount = _G.GetItemCount
	end
	function SHIM:GetItemCount(item, includeBank, includeCharges)
		return GetItemCount(item, includeBank, includeCharges)
	end

	-- GetItemIconByID
	if C_Item and C_Item.GetItemIconByID then
		GetItemIconByID = C_Item.GetItemIconByID
	elseif _G.GetItemIcon then
		GetItemIconByID = _G.GetItemIcon
	end
	function SHIM:GetItemIconByID(itemID)
		return GetItemIconByID(itemID)
	end

	-- GetItemInfo
	if C_Item and C_Item.GetItemInfo then
		GetItemInfo = C_Item.GetItemInfo
	elseif _G.GetItemInfo then
		GetItemInfo = _G.GetItemInfo
	end
	function SHIM:GetItemInfo(itemID)
		return GetItemInfo(itemID)
	end

	-- GetItemSpell
	if C_Item and C_Item.GetItemSpell then
		GetItemSpell = C_Item.GetItemSpell
	elseif _G.GetItemSpell then
		GetItemSpell = _G.GetItemSpell
	end
	function SHIM:GetItemSpell(itemID)
		return GetItemSpell(itemID)
	end

	-- IsUsableItem
	if C_Item and C_Item.IsUsableItem then
		IsUsableItem = C_Item.IsUsableItem
	elseif _G.IsUsableItem then
		IsUsableItem = _G.IsUsableItem
	end
	function SHIM:IsUsableItem(item)
		return IsUsableItem(item)
	end
end

do -- C_Spell
	local GetSpellInfo, GetSpellTexture, GetSpellCooldown, IsUsableSpell, GetSpellChargesByID

	-- GetSpellInfo
	if C_Spell and C_Spell.GetSpellInfo then
		GetSpellInfo = C_Spell.GetSpellInfo
		function SHIM:GetSpellInfo(spellID)
			local info = GetSpellInfo(spellID)
			if info then
				return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
			end
		end
	elseif _G.GetSpellInfo then
		GetSpellInfo = _G.GetSpellInfo
		function SHIM:GetSpellInfo(spellID)
			return GetSpellInfo(spellID)
		end
	end

	-- GetSpellTexture
	if C_Spell and C_Spell.GetSpellInfo then
		GetSpellTexture = C_Spell.GetSpellInfo
		function SHIM:GetSpellTexture(spellID)
			local info = GetSpellTexture(spellID)
			if info then
				return info.iconID
			end
		end
	elseif _G.GetSpellTexture then
		GetSpellTexture = _G.GetSpellTexture
		function SHIM:GetSpellTexture(spellID)
			return GetSpellTexture(spellID)
		end
	end

	-- GetSpellCooldown
	if C_Spell and C_Spell.GetSpellCooldown then
		GetSpellCooldown = C_Spell.GetSpellCooldown
		function SHIM:GetSpellCooldown(spellID)
			local info = GetSpellCooldown(spellID)
			if info then
				local isEnabled = info.isEnabled and 1 or 0
				return info.startTime, info.duration, isEnabled, info.modRate
			end
		end
	elseif _G.GetSpellCooldown then
		GetSpellCooldown = _G.GetSpellCooldown
		function SHIM:GetSpellCooldown(spellID)
			return GetSpellCooldown(spellID)
		end
	end

	-- IsUsableSpell
	if C_Spell and C_Spell.IsSpellUsable then
		IsUsableSpell = C_Spell.IsSpellUsable
	elseif _G.IsUsableSpell then
		IsUsableSpell = _G.IsUsableSpell
	end
	function SHIM:IsUsableSpell(spell)
		return IsUsableSpell(spell)
	end

	-- GetSpellChargesByID
	if C_Spell and C_Spell.GetSpellChargesByID then
		GetSpellChargesByID = C_Spell.GetSpellChargesByID
		function SHIM:GetSpellChargesByID(spellID)
			local info = GetSpellChargesByID(spellID)
			if info then
				return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration, info.chargeModRate
			end
		end
	elseif _G.GetSpellCharges then
		GetSpellChargesByID = _G.GetSpellCharges
		function SHIM:GetSpellChargesByID(spellID)
			return GetSpellChargesByID(spellID)
		end
	end
end

do -- C_SpellBook
	local GetNumSpellTabs, GetSpellTabInfo, GetSpellBookItemName, GetSpellBookItemInfo, HasPetSpells, GetSpellBookItemCooldown, GetSpellCharges

	-- GetNumSpellTabs
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
		GetNumSpellTabs = C_SpellBook.GetNumSpellBookSkillLines
	elseif _G.GetNumSpellTabs then
		GetNumSpellTabs = _G.GetNumSpellTabs
	end
	function SHIM:GetNumSpellTabs()
		return GetNumSpellTabs()
	end

	-- GetSpellTabInfo
	if C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo then
		GetSpellTabInfo = C_SpellBook.GetSpellBookSkillLineInfo
		function SHIM:GetSpellTabInfo(tabIndex)
			local info = GetSpellTabInfo(tabIndex)
			if info then
				return info.name, info.iconID, info.itemIndexOffset, info.numSpellBookItems, info.isGuild, info.shouldHide, info.specID, info.offSpecID
			end
		end
	elseif _G.GetSpellTabInfo then
		GetSpellTabInfo = _G.GetSpellTabInfo
		function SHIM:GetSpellTabInfo(tabIndex)
			return GetSpellTabInfo(tabIndex)
		end
	end

	-- GetSpellBookItemName
	if C_SpellBook and C_SpellBook.GetSpellBookItemName then
		GetSpellBookItemName = C_SpellBook.GetSpellBookItemName
		function SHIM:GetSpellBookItemName(index, bookType)
			if bookType == "spell" then
				bookType = Enum.SpellBookSpellBank.Player
			elseif bookType == "pet" then
				bookType = Enum.SpellBookSpellBank.Pet
			end
			return GetSpellBookItemName(index, bookType)
		end
	elseif _G.GetSpellBookItemName then
		GetSpellBookItemName = _G.GetSpellBookItemName
		function SHIM:GetSpellBookItemName(index, bookType)
			return GetSpellBookItemName(index, bookType)
		end
	end

	-- GetSpellBookItemInfo
	if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
		GetSpellBookItemInfo = C_SpellBook.GetSpellBookItemInfo
		function SHIM:GetSpellBookItemInfo(index, bookType)
			if bookType == "spell" then
				bookType = Enum.SpellBookSpellBank.Player
			elseif bookType == "pet" then
				bookType = Enum.SpellBookSpellBank.Pet
			end

			local info = GetSpellBookItemInfo(index, bookType)
			if info then
				local spellID = info.actionID

				local itemType = "UNKNOWN"
				if info.itemType == Enum.SpellBookItemType.Spell then
					itemType = "SPELL"
				elseif info.itemType == Enum.SpellBookItemType.None then
					itemType = "NONE"
				elseif info.itemType == Enum.SpellBookItemType.Flyout then
					itemType = "FLYOUT"
				elseif info.itemType == Enum.SpellBookItemType.FutureSpell then
					itemType = "FUTURESPELL"
				elseif info.itemType == Enum.SpellBookItemType.PetAction then
					itemType = "PETACTION"
					spellID = bit.band(0xFFFFFF, info.actionID)
				end

				local spellOverrideID
				if info.spellID ~= nil and info.spellID ~= spellID then
					spellOverrideID = info.spellID
				end

				return itemType, spellID, info.isPassive, spellOverrideID
			end
		end
	elseif _G.GetSpellBookItemInfo and _G.IsPassiveSpell then
		GetSpellBookItemInfo = _G.GetSpellBookItemInfo
		local IsPassiveSpell = _G.IsPassiveSpell
		function SHIM:GetSpellBookItemInfo(index, bookType)
			local itemType, spellID = GetSpellBookItemInfo(index, bookType)
			if itemType == "PETACTION" then
				spellID = bit.band(0xFFFFFF, spellID)
			end

			return itemType, spellID, IsPassiveSpell(spellID)
		end
	end

	-- HasPetSpells
	if C_SpellBook and C_SpellBook.HasPetSpells then
		HasPetSpells = C_SpellBook.HasPetSpells
	elseif _G.HasPetSpells then
		HasPetSpells = _G.HasPetSpells
	end
	function SHIM:HasPetSpells()
		return HasPetSpells()
	end

	-- GetSpellBookItemCooldown
	if C_SpellBook and C_SpellBook.GetSpellBookItemCooldown then
		GetSpellBookItemCooldown = C_SpellBook.GetSpellBookItemCooldown
		function SHIM:GetSpellBookItemCooldown(index, spellBank)
			if spellBank == "spell" then
				spellBank = Enum.SpellBookSpellBank.Player
			end
			local info = GetSpellBookItemCooldown(index, spellBank)
			if info then
				return info.startTime, info.duration, info.isEnabled, info.modRate
			end
		end
	elseif _G.GetSpellCooldown then
		GetSpellBookItemCooldown = _G.GetSpellCooldown
		function SHIM:GetSpellBookItemCooldown(index, spellBank)
			return GetSpellBookItemCooldown(index, spellBank)
		end
	end

	-- GetSpellCharges
	if C_SpellBook and C_SpellBook.GetSpellBookItemCharges then
		GetSpellCharges = C_SpellBook.GetSpellBookItemCharges
		function SHIM:GetSpellCharges(index, bookType)
			local info = GetSpellCharges(index, bookType)
			if info then
				return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration, info.chargeModRate
			end
		end
	elseif _G.GetSpellCharges then
		GetSpellCharges = _G.GetSpellCharges
		function SHIM:GetSpellCharges(index, bookType)
			return GetSpellCharges(index, bookType)
		end
	end
end

do -- C_SpecializationInfo
	local GetSpecialization, GetSpecializationInfo

	-- GetSpecialization
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		GetSpecialization = C_SpecializationInfo.GetSpecialization
	elseif _G.GetSpecialization then
		GetSpecialization = _G.GetSpecialization
	elseif _G.GetPrimaryTalentTree then
		GetSpecialization = _G.GetPrimaryTalentTree
	else
		GetSpecialization = function()
			return 1
		end
	end
	function SHIM:GetSpecialization()
		return GetSpecialization()
	end

	-- GetSpecializationInfo
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
		GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
	elseif _G.GetSpecializationInfo then
		GetSpecializationInfo = _G.GetSpecializationInfo
	end
	function SHIM:GetSpecializationInfo(specIndex)
		return GetSpecializationInfo(specIndex)
	end
end

setmetatable(SHIM, {
	__index = function(tab, key)
		return NOP
	end,
})
