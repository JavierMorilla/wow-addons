# wow-addons

Personal World of Warcraft addons for retail The War Within 11.2.5 (interface 110205).

## Altboard

Every alt at a glance, in one window: `/alts` (or `/altboard`, the minimap addon menu, or a key binding under Key Bindings > AddOns).

- Item level, gold (plus warband bank and an account total), spec and level
- Great Vault: three pips each for raid, dungeons and world; a "Reward!" flag once a slot from last week is waiting
- Keystone and Mythic+ rating
- Ethereal crests (Weathered, Carved, Runed, Gilded), Restored Coffer Keys and Valorstones, with weekly and season caps
- Raid and dungeon lockouts, professions
- Rested XP projected while the character is offline (faster when logged out in an inn or city)
- Weekly data is treated as reset after the weekly reset, even for characters you have not logged into since

Each character is recorded when you log in on it. Hover a row for details, click a column header to sort, right-click a row to hide or forget a character. `/alts scan` forces a refresh; `/alts debug` prints any API that fails on the server.

## Development

Each addon folder is linked into the game with a junction, so edits only need `/reload` (a new file needs a client restart):

```powershell
New-Item -ItemType Junction -Path "<World of Warcraft>\_retail_\Interface\AddOns\Altboard" -Target "<this repo>\Altboard"
```
