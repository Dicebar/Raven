# 7 October 2025
- Resolved issue with bars render frequency.

# 5 October 2025
- Lots of cleanups
- Fix tooltip value scanning for item
- Fix tooltip value scanning for Classic in general
- Optimized shims
- Many thanks to Road-Block for providing all of the above!

# 2 July 2025
- Added support for Mists of Pandaria Classic (thanks to Road-Block for providing a fix!)

# 20 September 2024
- Fixed bug with identifying spells by spell ID.

# 19 September 2024
- Fixed a bug with empty spellbook tabs.
- Fixed a bug where spell list entries with just integers caused the spell list to become inaccessible. 

# 12 September 2024
- Fixed the mounted condition not recognizing druids' flight and travel forms.

# 20 August 2024
- Fixed an error in aura cancellation (thanks Road-Block for providing the fix!)

# 15 August 2024
- Fixed namespace bugs for Raven_Options.

# 14 August 2024
- Fixed namespace changes. 

# 27 July 2024
- More bugfixes for The War Within.

# 25 July 2024
- More bugfixes for The War Within.
- Added support for cooldowns on Paladins' Flash of Light spell.

# 24 July 2024
- Various bugfixes for The War Within.

# 23 July 2024
- Fixed various new API changes for The War Within

# 13 May 2024
- Restored support for specialization tests in Cataclysm.
- Restored support for hiding bar groups while in a vehicle in Cataclysm.

# 02 May 2024
- Added Cataclysm TOCs.
- Fixed issues with Tooltip API.
- Added support for tracking weapon buffs on ranged weapons in Cataclysm.

# 03 April 2024
- Fixed new API changes thanks to @arnvid

# 24 March 2024
- Removed tracking from the player's auto group bars.
- Fixed enemy buffs in target auto group bars.

# 23 March 2024
- Fixed Cataclysm beta API bug.

# 22 February 2024
- Split hiding Blizzard's buffs and debuffs into separate configuration options.

# 9 February 2024
- Disabled the tracking type for auto buffs bars in Classic.

# 31 January 2024
- Fixed classic-only bug with target-of-target frames.

# 19 December 2023
- Added new time format that replicates the Blizzard's time format.
- Fixed bugs introduced with previous release.

# 18 December 2023
- Fixes for 10.2.5 API changes

# 18 November 2023
- Removed support for range checks in conditions. An unfortunate casualty of Blizzard preventing mods from telling players where to (not) stand during encounters.

# 16 November 2023
- Fixed bug caused by namespace changes in Classic WoW.

# 10 November 2023
- Fixed bug caused by Retail changing the addon management API.

# 24 August 2023
- Fixed bug caused by Classic Era now using part of the Dragonflight API for addons.

# 25 June 2023
- Fixed bug causing Apotheosis and Power Word: Salvation cooldowns to not be tracked properly.

# 18 May 2023
- Fixed bug causing Fire Elemental and Storm Elemental to not have their cooldowns tracked properly.

# 12 May 2023
- Fixed bug caused by tooltip API change.

# 3 May 2023
- Fixed bug caused by weapon buffs API having changed.

# 21 April 2023
- Fixed bug to active talent conditions not differentiating between choice talents.

# 16 March 2023
- Fixed a bug leading to cooldowns to not be cached properly in WotLK.

# 11 March 2023
- Fixed a bug causing cooldowns to be incorrectly cached.
- Fixed a bug causing Ignore Pain to not be testable as ready for non-Protection Warriors.

# 19 February 2023
- Fixed a cooldown bug for Arms Warriors, where Whirlwind would not properly trigger a cooldown.
- Fixed bug with item cooldowns no longer working in Dragonflight.

# 26 January 2023
- Optimized Weapon tooltip Scan for Temporary Weapon Enchants

# 14 January 2023
- Fixed bug causing Slam's cooldown, when combined with the Storm of Swords talent, to not be testable for conditions.

# 28 December 2022

- Fixed spelling for global cooldown in options menu, causing errors for some users
- Fixed bug with game version variation detection
- Improved check for TukUI/ElvUI fonts

# 27 December 2022

- Rewrite of basecode to better handle variations in game versions
- Extracted "Global Cooldown" from "Other" to it's own checkbox in the "Cooldowns" tab for bars
- Fixed issues with Wrath PTR

# 7 December 2022
- Added toc-file for Wrath of the Lich King.
