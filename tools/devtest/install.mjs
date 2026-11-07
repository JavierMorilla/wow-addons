// Copies the addons and the DevTest harness into a game client's AddOns folder.
//
//   node tools/devtest/install.mjs                       WoW Forever (default)
//   node tools/devtest/install.mjs "<client folder>"     any other client
//   node tools/devtest/install.mjs --no-harness          only the addons
//
// The game only sees new files after a full restart; changed files after /reload.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const ADDONS = ['Barracks', 'Keepsake', 'TreasureTrail'];
const HARNESS = '!MorigollDevTest';
const DEFAULT_CLIENT = 'F:\\World of Warcraft\\_forever_';

const args = process.argv.slice(2);
const noHarness = args.includes('--no-harness');
const client = args.find((a) => !a.startsWith('--')) || DEFAULT_CLIENT;
const target = path.join(client, 'Interface', 'AddOns');
if (!fs.existsSync(target)) {
  console.error(`No AddOns folder at ${target}`);
  process.exit(1);
}

function copy(src, name) {
  const dest = path.join(target, name);
  const stat = fs.lstatSync(dest, { throwIfNoEntry: false });
  if (stat?.isSymbolicLink()) {
    console.log(`${name}: linked, left as is`);
    return;
  }
  fs.rmSync(dest, { recursive: true, force: true });
  fs.cpSync(src, dest, { recursive: true });
  console.log(`${name}: copied`);
}

for (const name of ADDONS) copy(path.join(ROOT, name), name);
if (!noHarness) copy(path.join(HERE, HARNESS), HARNESS);
console.log(`-> ${target}`);
