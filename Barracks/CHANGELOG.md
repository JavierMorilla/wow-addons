# Barracks

## 0.3.0

Tested in game on WoW Forever.

- A gear button in the header: window size (80% to 130%) and the minimap button on or off. `/alts scale 110` does the same from chat
- A filter box: type part of a name, realm or class
- Hover the gold total for the split by realm and faction
- Forgetting a character asks for confirmation first
- On Midnight the crest and coffer key columns are hidden and item level is not coloured by track until that season's data is in; on WoW Forever the addon no longer asks the game for Mythic+ and vault data that does not exist there

## 0.2.1

Tested in game on WoW Forever.

- On WoW Forever the Great Vault, keystone, crest and coffer key columns are now really hidden (0.2.0 meant to, but they still showed)
- Gold under 100 also shows silver, and under 1 gold silver and copper, instead of reading "0"
- The tooltip only shows the currencies section when the character has any of them, and the warband bank line only when it holds gold

## 0.2.0

Beta: runs on retail Midnight (12.1.5, 12.1.7) and WoW Forever as well as The War Within. Not yet tested in game on those clients; please report any error.

- On WoW Forever the Great Vault, keystone, crest and coffer key columns are hidden, since that content does not exist there
- Specialization is read through the current API instead of the deprecated one

## 0.1.0

First release.

- One window with every character: item level, gold, Great Vault, keystone and Mythic+ rating, Ethereal crests, Restored Coffer Keys, rested XP and when you last played them
- Hover a character for lockouts, currencies with weekly and season caps, professions and the Great Vault in detail
- Weekly data resets on its own after the weekly reset, and a "Reward!" flag shows when the Great Vault has something waiting
- Rested XP keeps counting while a character is logged out
- Minimap button with a quick summary, addon compartment entry, key binding and `/alts`
- English and Spanish
