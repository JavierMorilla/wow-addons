# Treasure Trail

## 0.3.0

Treasure Trail now works on WoW Forever, tested in game.

- That client gives no source for mounts and pets and has no Adventure Guide, so Treasure Trail carries its own list of where every vanilla mount, pet and dungeon or raid item comes from, and checks your collections against it
- In a zone: the mounts and pets your race and faction can still get there, with their source (vendor, drop with its chance, container or quest), and the dungeons and raids whose entrance is in the zone
- In a dungeon or raid, or browsing one from its entrance: the mounts, pets and appearances your class can still collect, by boss
- Content from a later patch is marked with the patch it arrives in
- Items the game has not loaded yet are fetched and the list fills in on its own a moment later

## 0.2.0

Beta: runs on retail Midnight (12.1.5, 12.1.7) and WoW Forever as well as The War Within. Not yet tested in game on those clients; please report any error.

- The current dungeon or raid is found through the documented Adventure Guide API, with the older lookup kept as a fallback
- If a client lacks the boss kill lookup, bosses simply stop showing as killed instead of raising an error

## 0.1.0

First release.

- Mounts and pets you are still missing in the current zone, with wild battle pets listed apart
- Dungeons and raids whose entrance is in the zone: click one to see its missing mounts, pets, toys and appearances by boss and difficulty
- Inside a dungeon or raid: what your character can still collect from each boss, marking bosses already killed this lockout
- A small summary pill under the minimap; click opens the item in your collections, ctrl-click previews, shift-click links
- English and Spanish
