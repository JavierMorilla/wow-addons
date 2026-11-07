// Saves the zone rectangles and instance names from the last /devtest probe,
// and the zone grid from /devtest grid, into tools/forever-data/zones.json,
// instances.json and grid.json, which build.mjs reads.
//
//   node tools/forever-data/zones.mjs ["<client folder>"]
//
// In the game: /devtest probe and/or /devtest grid, then /reload, then run this.
// Whatever the report lacks is left as it is on disk.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const report = path.join(HERE, '..', 'devtest', 'report.mjs');
const db = JSON.parse(execFileSync(process.execPath, [report, ...process.argv.slice(2), '--json'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }));
const list = (t) => (Array.isArray(t) ? t : t ? Object.values(t) : []);
if (!db.probe && !db.grid) throw new Error('No probe and no grid in the report: run /devtest probe or /devtest grid, then /reload');

const probe = db.probe;
if (probe && list(probe.zoneRects).length) {
  // "mapID|mapType|continent|x1|y1|x2|y2|parent|continent2|name"
  const zones = list(probe.zoneRects).map((line) => {
    const [mapID, type, continent, x1, y1, x2, y2, parent, continent2, ...name] = line.split('|');
    return {
      mapID: Number(mapID), type: Number(type), continent: Number(continent),
      x1: Number(x1), y1: Number(y1), x2: Number(x2), y2: Number(y2),
      parent: Number(parent), name: name.join('|'), sameContinent: continent === continent2,
    };
  });
  fs.writeFileSync(path.join(HERE, 'zones.json'), JSON.stringify(zones, null, 1) + '\n');

  const instances = list(probe.instanceNames).map((line) => {
    const [id, ...name] = line.split('|');
    return { id: Number(id), name: name.join('|') };
  });
  fs.writeFileSync(path.join(HERE, 'instances.json'), JSON.stringify(instances, null, 1) + '\n');
  console.log(`zones.json: ${zones.length} maps (${zones.filter((z) => z.type === 3).length} zones) · instances.json: ${instances.length} names · probe of ${probe.at}`);
} else {
  console.log('No zone rectangles in the report; zones.json and instances.json left as they are.');
}

if (db.grid && db.grid.maps) {
  const maps = {};
  for (const [mapID, rows] of Object.entries(db.grid.maps)) maps[mapID] = list(rows);
  fs.writeFileSync(path.join(HERE, 'grid.json'), JSON.stringify({ size: db.grid.size, at: db.grid.at, maps }) + '\n');
  console.log(`grid.json: ${Object.keys(maps).length} continents, ${db.grid.size}x${db.grid.size}, ${db.grid.at}`);
} else {
  console.log('No zone grid in the report; grid.json left as it is.');
}
