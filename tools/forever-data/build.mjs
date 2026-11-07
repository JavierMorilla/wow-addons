// Builds TreasureTrail/ForeverData.lua: where vanilla mounts, pets and dungeon
// appearances come from, for WoW Forever, whose client has no source texts
// and no Adventure Guide.
//
//   node tools/forever-data/build.mjs <mangos.sqlite> [--zones tools/forever-data/zones.json]
//
// <mangos.sqlite> is the world database of the VMaNGOS project (release
// "db_latest", db-sqlite-*.zip, sqlite-dump/mangos.sqlite). Only facts are taken
// from it (ids, who drops or sells what, where creatures stand); the output is
// our own table. zones.json holds each zone's rectangle in world coordinates,
// read from the game with /devtest probe (see tools/forever-data/zones.mjs).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT = path.join(ROOT, 'TreasureTrail', 'ForeverData.lua');

const args = process.argv.slice(2);
const dbPath = args.find((a) => !a.startsWith('--'));
const zonesPath = args.includes('--zones') ? args[args.indexOf('--zones') + 1] : path.join(HERE, 'zones.json');
if (!dbPath) {
  console.error('usage: node tools/forever-data/build.mjs <mangos.sqlite> [--zones zones.json]');
  process.exit(1);
}

const LAST_PATCH = 10; // VMaNGOS patch index of 1.12
const MIN_BOSS_ITEM_CHANCE = 1; // percent: below this, an item is a world drop, not boss loot
const QUALITY_GREEN = 2;
const ALL_RACES = 0xff; // the eight vanilla playable races
// Inventory types that have an appearance (no rings, trinkets, necks, bags, ammo, relics).
const APPEARANCE_SLOTS = new Set([1, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 25, 26]);
const AURA_MOUNTED = 78;
const MIN_OWN_ITEM_CHANCE = 2; // percent: a single creature dropping a piece this often has loot of its own

// Bosses a script summons during the encounter: no fixed spawn in the database.
// Scourge Invasion and Alterac Valley bosses are left out on purpose.
const SCRIPTED_BOSSES = {
  643: 36, // Sneed, inside Sneed's Shredder (Deadmines)
  1853: 289, 10506: 289, 14516: 289, // Gandling, Kirtonos, Darkreaver (Scholomance)
  7273: 209, 7275: 209, // Gahz'rilla, Sezz'ziz (Zul'Farrak)
  7355: 129, 7356: 129, // Tuten'kash, Plaguemaw (Razorfen Downs)
  8443: 109, // Avatar of Hakkar (Sunken Temple)
  9027: 230, 9028: 230, 9029: 230, 9030: 230, 9031: 230, 9032: 230, // Ring of Law (Blackrock Depths)
  9537: 230, 10076: 230, // Hurley Blackbreath, High Priestess of Thaurissan
  9596: 229, 10263: 229, 10264: 229, 10268: 229, 10339: 229, 10584: 229, // Blackrock Spire
  10439: 329, 10516: 329, 10808: 329, 10813: 329, 11143: 329, // Stratholme
  11502: 409, // Ragnaros
  11583: 469, // Nefarian
  14506: 429, // Lord Hel'nurath (Dire Maul)
  14515: 309, 15082: 309, 15083: 309, 15084: 309, 15085: 309, // Arlokk, Edge of Madness (Zul'Gurub)
  15517: 531, // Ouro
  15989: 533, // Sapphiron
};
const EFFECT_SUMMON_CRITTER = 97;

const db = new DatabaseSync(dbPath, { readOnly: true });
const all = (sql, ...p) => db.prepare(sql).all(...p);

// Latest row of each patched template --------------------------------------------------------

function latest(table, cols) {
  const map = new Map();
  for (const r of all(`select ${cols}, patch from ${table} order by entry, patch`)) {
    const first = map.get(r.entry);
    map.set(r.entry, { ...r, firstPatch: first ? first.firstPatch : r.patch });
  }
  return map;
}

const items = latest('item_template', 'entry, class, quality, inventory_type, allowable_race, spellid_1, name');
const creatures = latest('creature_template', 'entry, name, rank, level_min, loot_id, vendor_id');
const objects = latest('gameobject_template', 'entry, name, type, data1');

const creatureES = new Map(all('select entry, name_loc6, name_loc7 from locales_creature').map((r) => [r.entry, r.name_loc6 || r.name_loc7]));
const objectES = new Map(all('select entry, name_loc6, name_loc7 from locales_gameobject').map((r) => [r.entry, r.name_loc6 || r.name_loc7]));
const questES = new Map(all('select entry, Title_loc6, Title_loc7 from locales_quest').map((r) => [r.entry, r.Title_loc6 || r.Title_loc7]));

// Collectibles ----------------------------------------------------------------------------------

const spellIs = (sql) => new Set(all(sql).map((r) => r.entry));
const mountSpells = spellIs(`select distinct entry from spell_template where effectApplyAuraName1 = ${AURA_MOUNTED} or effectApplyAuraName2 = ${AURA_MOUNTED} or effectApplyAuraName3 = ${AURA_MOUNTED}`);
const petSpells = spellIs(`select distinct entry from spell_template where effect1 = ${EFFECT_SUMMON_CRITTER}`);

function kindOf(itemID) {
  const it = items.get(itemID);
  if (!it) return null;
  if (it.class === 15 && mountSpells.has(it.spellid_1)) return 'mount';
  if (it.class === 15 && petSpells.has(it.spellid_1)) return 'pet';
  if (it.quality >= QUALITY_GREEN && APPEARANCE_SLOTS.has(it.inventory_type) && (it.class === 2 || it.class === 4)) return 'appearance';
  return null;
}
const isPetOrMount = (id) => {
  const k = kindOf(id);
  return k === 'mount' || k === 'pet';
};

// Loot, with reference tables expanded and an effective drop chance ---------------------------------

function lootRows(table, entry) {
  return all(`select item, ChanceOrQuestChance ch, groupid g, mincountOrRef ref, patch_min p from ${table} where entry = ? and patch_max >= ?`, entry, LAST_PATCH);
}

// Returns [{ item, chance, patch }]; chance in percent.
function loot(table, entry, scale = 100, depth = 0, patchFloor = 0) {
  const rows = lootRows(table, entry);
  const out = [];
  // Within a group, entries with chance 0 share what the explicit ones leave.
  const groups = new Map();
  for (const r of rows) {
    if (r.g > 0) {
      const g = groups.get(r.g) || { explicit: 0, equal: 0 };
      if (r.ch > 0) g.explicit += Math.abs(r.ch);
      else g.equal += 1;
      groups.set(r.g, g);
    }
  }
  for (const r of rows) {
    let ch = Math.abs(r.ch);
    if (ch === 0) {
      const g = r.g > 0 && groups.get(r.g);
      if (!g) continue;
      ch = Math.max(0, 100 - g.explicit) / g.equal;
    }
    const chance = (ch * scale) / 100;
    const patch = Math.max(patchFloor, r.p || 0);
    if (r.ref < 0) {
      if (depth < 3) out.push(...loot('reference_loot_template', -r.ref, chance, depth + 1, patch));
    } else {
      out.push({ item: r.item, chance, patch });
    }
  }
  return out;
}

// World geometry ------------------------------------------------------------------------------

const allMaps = JSON.parse(fs.readFileSync(zonesPath, 'utf8'));
const zones = allMaps.filter((z) => z.type === 3);

// The zone grid from /devtest grid: which zone covers each cell of a continent
// map, from the world map's own zone shapes. Rows are "zone*count,zone*count".
const CONTINENT_MAPS = { 0: 1415, 1: 1414 }; // world map id -> continent ui map
const gridPath = path.join(path.dirname(zonesPath), 'grid.json');
const grid = fs.existsSync(gridPath) ? JSON.parse(fs.readFileSync(gridPath, 'utf8')) : null;
const gridCells = {};
if (grid) {
  for (const [mapID, rows] of Object.entries(grid.maps)) {
    gridCells[mapID] = rows.map((row) => row.split(',').flatMap((run) => {
      const [id, count] = run.split('*').map(Number);
      return Array(count).fill(id);
    }));
  }
}

// Map (0,0) is the continent's top-left corner: world x falls from top to
// bottom, world y from left to right.
function zoneFromGrid(map, x, y) {
  const uiMap = CONTINENT_MAPS[map];
  const cells = gridCells[uiMap];
  const rect = allMaps.find((m) => m.mapID === uiMap);
  if (!cells || !rect) return undefined;
  const nx = (y - rect.y1) / (rect.y2 - rect.y1);
  const ny = (x - rect.x1) / (rect.x2 - rect.x1);
  if (nx < 0 || nx >= 1 || ny < 0 || ny >= 1) return null;
  const id = cells[Math.floor(ny * grid.size)][Math.floor(nx * grid.size)];
  return zones.some((z) => z.mapID === id) ? id : null;
}

// The zone around a point on a continent (0 Eastern Kingdoms, 1 Kalimdor): from
// the grid when it names one, else the smallest zone rectangle around it.
function zoneAt(map, x, y) {
  // The world map's zone shapes leave gaps (the north of Orgrimmar reads as
  // plain Kalimdor); there the rectangles decide.
  const fromGrid = zoneFromGrid(map, x, y);
  if (fromGrid) return fromGrid;
  let best = null;
  for (const z of zones) {
    if (z.continent !== map) continue;
    const [x1, x2] = [Math.min(z.x1, z.x2), Math.max(z.x1, z.x2)];
    const [y1, y2] = [Math.min(z.y1, z.y2), Math.max(z.y1, z.y2)];
    if (x < x1 || x > x2 || y < y1 || y > y2) continue;
    const area = (x2 - x1) * (y2 - y1);
    if (!best || area < best.area) best = { id: z.mapID, area };
  }
  return best && best.id;
}

const instances = new Map();
for (const r of all('select entry, map_type, map_name, patch from map_template where map_type in (1, 2) order by entry, patch')) {
  if (!instances.has(r.entry)) instances.set(r.entry, { id: r.entry, name: r.map_name, raid: r.map_type === 2, patch: r.patch, bosses: [] });
}

// Where each creature or object stands: [{ zone } | { instance }]
function placesOf(table, id) {
  if (table === 'creature' && SCRIPTED_BOSSES[id]) return [{ key: `i${SCRIPTED_BOSSES[id]}`, patch: 0, count: 1 }];
  const seen = new Map();
  for (const s of all(`select map, position_x x, position_y y, patch_min p from ${table} where id = ? and patch_max >= ?`, id, LAST_PATCH)) {
    let key;
    if (s.map === 0 || s.map === 1) {
      const zone = zoneAt(s.map, s.x, s.y);
      if (!zone) continue;
      key = `z${zone}`;
    } else if (instances.has(s.map)) {
      key = `i${s.map}`;
    } else continue;
    const prev = seen.get(key);
    seen.set(key, { key, patch: prev ? Math.min(prev.patch, s.p) : s.p, count: (prev ? prev.count : 0) + 1 });
  }
  return [...seen.values()];
}

// Output tables -----------------------------------------------------------------------------------

const npcNames = new Map();
const objectNames = new Map();
const questNames = new Map();
const zoneData = new Map(); // zone id -> { items: Map(itemID -> { kind, race, patch, src: [] }), entrances: Set }

function zoneEntry(zone) {
  if (!zoneData.has(zone)) zoneData.set(zone, { items: new Map(), entrances: new Set() });
  return zoneData.get(zone);
}

function addSource(zone, itemID, source, patch) {
  const z = zoneEntry(zone);
  let e = z.items.get(itemID);
  if (!e) {
    const it = items.get(itemID);
    e = { kind: kindOf(itemID), race: it.allowable_race, patch: Math.max(patch, it.firstPatch), src: [] };
    z.items.set(itemID, e);
  }
  e.patch = Math.min(e.patch, Math.max(patch, items.get(itemID).firstPatch));
  if (!e.src.some((s) => s.join() === source.join())) e.src.push(source);
}

const NPC = (c) => {
  npcNames.set(c.entry, [c.name, creatureES.get(c.entry) || '']);
  return c.entry;
};

// 1. Creature drops (open world) and boss loot (instances)
const bossItems = new Map(); // instance -> Map(creature -> items)
for (const c of creatures.values()) {
  if (!c.loot_id) continue;
  const places = placesOf('creature', c.entry);
  if (!places.length) continue;
  const drops = loot('creature_loot_template', c.loot_id);
  if (!drops.length) continue;
  const collectible = drops.filter((d) => isPetOrMount(d.item) && d.chance > 0);

  for (const place of places) {
    if (place.key[0] === 'z') {
      for (const d of collectible) addSource(Number(place.key.slice(1)), d.item, ['d', NPC(c), Math.round(d.chance * 100) / 100], Math.max(d.patch, place.patch));
      continue;
    }
    // Instances: bosses have a loot table of their own that always drops (a
    // reference at 100%, or a group of equal-chance items); trash only has
    // world drops at a fraction of a percent. Rares count too.
    const instance = Number(place.key.slice(1));
    const ownTable = lootRows('creature_loot_template', c.loot_id).some((r) => (r.ref < 0 && Math.abs(r.ch) >= 100) || (r.g > 0 && r.ch === 0));
    const ownPieces = c.rank >= 1 && drops.some((d) => kindOf(d.item) === 'appearance' && d.chance >= MIN_OWN_ITEM_CHANCE);
    const isBoss = place.count <= 2 && (ownTable || ownPieces);
    const list = drops.filter((d) => {
      const k = kindOf(d.item);
      if (k === 'mount' || k === 'pet') return d.chance > 0;
      return isBoss && k === 'appearance' && d.chance >= MIN_BOSS_ITEM_CHANCE;
    });
    if (!list.length) continue;
    if (!bossItems.has(instance)) bossItems.set(instance, new Map());
    const bosses = bossItems.get(instance);
    const b = bosses.get(c.entry) || { npc: NPC(c), level: c.level_min, boss: isBoss, items: new Map() };
    if (isBoss && !SCRIPTED_BOSSES[c.entry]) b.spawnPatch = Math.min(b.spawnPatch ?? LAST_PATCH, place.patch);
    for (const d of list) {
      const prev = b.items.get(d.item);
      if (prev === undefined || d.patch < prev) b.items.set(d.item, d.patch);
    }
    bosses.set(c.entry, b);
  }
}

// 2. Chests and other objects with loot: open-world sources, or boss loot inside instances
for (const o of objects.values()) {
  if (o.type !== 3 || !o.data1) continue; // 3 = chest; data1 = loot id
  const drops = loot('gameobject_loot_template', o.data1);
  const collectible = drops.filter((d) => isPetOrMount(d.item) && d.chance > 0);
  for (const place of placesOf('gameobject', o.entry)) {
    if (place.key[0] === 'z') {
      if (!collectible.length) continue;
      objectNames.set(o.entry, [o.name, objectES.get(o.entry) || '']);
      for (const d of collectible) addSource(Number(place.key.slice(1)), d.item, ['o', o.entry, Math.round(d.chance * 100) / 100], Math.max(d.patch, place.patch));
      continue;
    }
    if (place.count > 2) continue;
    const list = drops.filter((d) => {
      const k = kindOf(d.item);
      return ((k === 'mount' || k === 'pet') && d.chance > 0) || (k === 'appearance' && d.chance >= MIN_BOSS_ITEM_CHANCE);
    });
    if (!list.length) continue;
    const instance = Number(place.key.slice(1));
    objectNames.set(o.entry, [o.name, objectES.get(o.entry) || '']);
    if (!bossItems.has(instance)) bossItems.set(instance, new Map());
    const bosses = bossItems.get(instance);
    const key = -o.entry; // negative: an object, not a creature
    const b = bosses.get(key) || { npc: key, level: 99, boss: true, items: new Map() };
    for (const d of list) {
      const prev = b.items.get(d.item);
      if (prev === undefined || d.patch < prev) b.items.set(d.item, d.patch);
    }
    bosses.set(key, b);
  }
}

// 3. Vendors
const vendorItems = new Map();
for (const r of all('select entry, item from npc_vendor')) {
  if (!vendorItems.has(r.entry)) vendorItems.set(r.entry, []);
  vendorItems.get(r.entry).push(r.item);
}
const templateItems = new Map();
for (const r of all('select entry, item from npc_vendor_template')) {
  if (!templateItems.has(r.entry)) templateItems.set(r.entry, []);
  templateItems.get(r.entry).push(r.item);
}
for (const c of creatures.values()) {
  const sold = [...(vendorItems.get(c.entry) || []), ...(c.vendor_id ? templateItems.get(c.vendor_id) || [] : [])].filter(isPetOrMount);
  if (!sold.length) continue;
  for (const place of placesOf('creature', c.entry)) {
    if (place.key[0] !== 'z') continue;
    for (const item of sold) addSource(Number(place.key.slice(1)), item, ['v', NPC(c)], place.patch);
  }
}

// 4. Quest rewards, placed where the quest giver stands
const REWARD_COLS = ['RewItemId1', 'RewItemId2', 'RewItemId3', 'RewItemId4', 'RewChoiceItemId1', 'RewChoiceItemId2', 'RewChoiceItemId3', 'RewChoiceItemId4', 'RewChoiceItemId5', 'RewChoiceItemId6'];
const questGivers = new Map();
for (const r of all('select id, quest from creature_questrelation where patch_max >= ?', LAST_PATCH)) {
  if (!questGivers.has(r.quest)) questGivers.set(r.quest, []);
  questGivers.get(r.quest).push(r.id);
}
const quests = latest('quest_template', `entry, Title, RequiredRaces, ${REWARD_COLS.join(', ')}`);
for (const q of quests.values()) {
  const rewards = REWARD_COLS.map((c) => q[c]).filter((id) => id && isPetOrMount(id));
  if (!rewards.length) continue;
  for (const giver of questGivers.get(q.entry) || []) {
    for (const place of placesOf('creature', giver)) {
      if (place.key[0] !== 'z') continue;
      questNames.set(q.entry, [q.Title, questES.get(q.entry) || '', q.RequiredRaces || 0]);
      for (const item of rewards) addSource(Number(place.key.slice(1)), item, ['q', q.entry], Math.max(q.firstPatch, place.patch));
    }
  }
}

// 5. Dungeon and raid entrances, by where their teleport trigger stands
for (const t of all('select a.id, a.target_map, t.map_id, t.x, t.y from areatrigger_teleport a join areatrigger_template t on t.id = a.id')) {
  if (!instances.has(t.target_map) || (t.map_id !== 0 && t.map_id !== 1)) continue;
  const zone = zoneAt(t.map_id, t.x, t.y);
  if (zone) zoneEntry(zone).entrances.add(t.target_map);
}

// Lua output ---------------------------------------------------------------------------------------

const bossName = (id) => (id < 0 ? objectNames.get(-id) : npcNames.get(id))[0];
const lua = (v) => (typeof v === 'string' ? JSON.stringify(v) : String(v));
const lines = [];
const push = (s) => lines.push(s);

push('-- Generated by tools/forever-data/build.mjs; do not edit by hand.');
push('-- Where vanilla mounts, pets and dungeon appearances come from, for WoW Forever.');
push('-- Facts (ids, drops, vendors, quests, spawn zones) taken from the VMaNGOS world database.');
push('if select(4, GetBuildInfo()) >= 20000 then return end');
push('local _, ns = ...');
push('ns.ForeverData = {');

push('\tnpcs = {');
for (const [id, [en, es]] of [...npcNames].sort((a, b) => a[0] - b[0])) push(`\t\t[${id}] = { ${lua(en)}, ${lua(es)} },`);
push('\t},');
push('\tobjects = {');
for (const [id, [en, es]] of [...objectNames].sort((a, b) => a[0] - b[0])) push(`\t\t[${id}] = { ${lua(en)}, ${lua(es)} },`);
push('\t},');
push('\t-- [quest] = { title, Spanish title, required races mask (0 = any) }');
push('\tquests = {');
for (const [id, [en, es, races]] of [...questNames].sort((a, b) => a[0] - b[0])) push(`\t\t[${id}] = { ${lua(en)}, ${lua(es)}, ${races} },`);
push('\t},');

push('\t-- [ui map] = { items = { [item] = { kind, races mask, first patch, sources } }, entrances = { instance map ids } }');
push('\t-- sources: { "d", npc, chance } drop · { "o", object, chance } chest · { "v", npc } vendor · { "q", quest } quest reward');
push('\tzones = {');
let zoneItems = 0;
for (const [zone, z] of [...zoneData].sort((a, b) => a[0] - b[0])) {
  push(`\t\t[${zone}] = {`);
  push('\t\t\titems = {');
  for (const [item, e] of [...z.items].sort((a, b) => a[0] - b[0])) {
    const race = !e.race || e.race === -1 || (e.race & ALL_RACES) === ALL_RACES ? 0 : e.race & ALL_RACES;
    const src = e.src.map((s) => `{ ${s.map(lua).join(', ')} }`).join(', ');
    push(`\t\t\t\t[${item}] = { ${lua(e.kind)}, ${race}, ${e.patch}, { ${src} } }, -- ${items.get(item).name}`);
    zoneItems++;
  }
  push('\t\t\t},');
  push(`\t\t\tentrances = { ${[...z.entrances].sort((a, b) => a - b).join(', ')} },`);
  push('\t\t},');
}
push('\t},');

push('\t-- [instance map] = { name, raid, first patch, bosses = { { npc (negative: object), { item, first patch, ... } } } }');
push('\tinstances = {');
let instanceItems = 0;
for (const [id, inst] of [...instances].sort((a, b) => a[0] - b[0])) {
  const bosses = [...(bossItems.get(id) || new Map()).values()]
    .filter((b) => b.items.size)
    .sort((a, b) => a.level - b.level || bossName(a.npc).localeCompare(bossName(b.npc)));
  if (!bosses.length) continue;
  // An instance opens when its first boss appears (Zul'Gurub 1.7, Naxxramas 1.11...)
  let patch = LAST_PATCH;
  for (const b of bosses) if (b.spawnPatch !== undefined) patch = Math.min(patch, b.spawnPatch);
  push(`\t\t[${id}] = { ${lua(inst.name)}, ${inst.raid}, ${Math.max(inst.patch, patch)}, {`);
  for (const b of bosses) {
    const list = [...b.items].sort((x, y) => x[0] - y[0]).flatMap(([item, patch]) => [item, patch]);
    instanceItems += b.items.size;
    push(`\t\t\t{ ${b.npc}, { ${list.join(', ')} } }, -- ${bossName(b.npc)}`);
  }
  push('\t\t} },');
}
push('\t},');
push('}');

fs.writeFileSync(OUT, lines.join('\n') + '\n');
console.log(`${OUT}: ${zoneData.size} zones, ${zoneItems} zone items, ${instanceItems} instance items, ${npcNames.size} npcs, ${questNames.size} quests, ${(fs.statSync(OUT).size / 1024).toFixed(0)} KB`);
