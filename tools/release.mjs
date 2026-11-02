#!/usr/bin/env node
// Packages one addon and publishes it: a GitHub release carrying the zip and,
// when CF_API_TOKEN is set and tools/curseforge.json has the addon's project
// id, the same zip on CurseForge.
//
//   node tools/release.mjs Altboard            package and publish
//   node tools/release.mjs Altboard --dry-run  only build dist/Altboard-<version>.zip
//
// The version comes from the addon's .toc, the release notes from the matching
// "## <version>" section of its CHANGELOG.md, and the CurseForge game versions
// from its "## Interface:" line.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CF_API = 'https://wow.curseforge.com/api';

function fail(msg) {
  console.error(`release: ${msg}`);
  process.exit(1);
}

function run(cmd, args, opts = {}) {
  return execFileSync(cmd, args, { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], ...opts }).trim();
}

function readToc(name) {
  const file = path.join(ROOT, name, `${name}.toc`);
  if (!fs.existsSync(file)) fail(`no ${name}/${name}.toc`);
  const toc = fs.readFileSync(file, 'utf8');
  const field = (key) => (toc.match(new RegExp(`^## ${key}:\\s*(.+)$`, 'm')) || [])[1]?.trim();
  const version = field('Version');
  if (!version) fail(`${name}.toc has no ## Version`);
  const interfaces = (field('Interface') || '').split(',').map((s) => Number(s.trim())).filter(Boolean);
  return { version, interfaces };
}

function changelogFor(name, version) {
  const file = path.join(ROOT, name, 'CHANGELOG.md');
  if (!fs.existsSync(file)) fail(`no ${name}/CHANGELOG.md`);
  const text = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
  const start = text.indexOf(`\n## ${version}\n`);
  if (start < 0) fail(`${name}/CHANGELOG.md has no "## ${version}" section`);
  const rest = text.slice(start + 1);
  const next = rest.indexOf('\n## ', 1);
  return (next < 0 ? rest : rest.slice(0, next)).trim();
}

// 110205 -> "11.2.5"
function interfaceToGameVersion(n) {
  return `${Math.floor(n / 10000)}.${Math.floor(n / 100) % 100}.${n % 100}`;
}

function buildZip(name, version) {
  const dist = path.join(ROOT, 'dist');
  fs.mkdirSync(dist, { recursive: true });
  const zip = path.join(dist, `${name}-${version}.zip`);
  fs.rmSync(zip, { force: true });
  // Windows' own bsdtar writes zips; Git's GNU tar (often first in PATH) cannot.
  const tar = process.platform === 'win32' ? path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'tar.exe') : 'zip';
  if (process.platform === 'win32') {
    run(tar, ['-a', '-c', '-f', zip, name]);
  } else {
    run(tar, ['-r', zip, name]);
  }
  return zip;
}

async function uploadToCurseForge(projectId, zip, { name, version, interfaces, notes }) {
  const token = process.env.CF_API_TOKEN;
  const headers = { 'X-Api-Token': token };
  const res = await fetch(`${CF_API}/game/versions`, { headers });
  if (!res.ok) fail(`CurseForge game versions: HTTP ${res.status}`);
  const all = await res.json();
  const wanted = interfaces.map(interfaceToGameVersion);
  const ids = all.filter((v) => wanted.includes(v.name)).map((v) => v.id);
  const found = all.filter((v) => wanted.includes(v.name)).map((v) => v.name);
  const missing = wanted.filter((w) => !found.includes(w));
  if (missing.length) console.warn(`release: CurseForge has no game version ${missing.join(', ')}; skipping it`);
  if (!ids.length) fail('none of the .toc interface versions exist on CurseForge');

  const metadata = {
    changelog: notes,
    changelogType: 'markdown',
    displayName: `${name} ${version}`,
    gameVersions: [...new Set(ids)],
    releaseType: 'release',
  };
  const form = new FormData();
  form.append('metadata', JSON.stringify(metadata));
  form.append('file', new Blob([fs.readFileSync(zip)]), path.basename(zip));
  const up = await fetch(`${CF_API}/projects/${projectId}/upload-file`, { method: 'POST', headers, body: form });
  const body = await up.text();
  if (!up.ok) fail(`CurseForge upload: HTTP ${up.status} ${body}`);
  console.log(`CurseForge: uploaded ${path.basename(zip)} for ${found.join(', ')} (${body})`);
}

async function main() {
  const name = process.argv[2];
  const dryRun = process.argv.includes('--dry-run');
  if (!name) fail('usage: node tools/release.mjs <AddonFolder> [--dry-run]');

  const { version, interfaces } = readToc(name);
  const notes = changelogFor(name, version);
  const zip = buildZip(name, version);
  console.log(`built ${path.relative(ROOT, zip)}`);
  if (dryRun) return;

  if (run('git', ['status', '--porcelain'])) fail('commit or stash your changes first');
  const tag = `${name.toLowerCase()}-v${version}`;
  if (run('git', ['tag', '--list', tag])) fail(`tag ${tag} already exists: bump ## Version in ${name}.toc`);

  const branch = run('git', ['rev-parse', '--abbrev-ref', 'HEAD']);
  run('git', ['push', 'origin', branch], { stdio: ['ignore', 'inherit', 'inherit'] });
  run('gh', ['release', 'create', tag, zip, '--title', `${name} ${version}`, '--notes', notes, '--target', branch]);
  run('git', ['fetch', '--tags', '--quiet']);
  console.log(`GitHub: released ${tag}`);

  const ids = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools', 'curseforge.json'), 'utf8'));
  if (!ids[name]) {
    console.log(`CurseForge: no project id for ${name} in tools/curseforge.json; skipped`);
  } else if (!process.env.CF_API_TOKEN) {
    console.log('CurseForge: CF_API_TOKEN is not set; skipped');
  } else {
    await uploadToCurseForge(ids[name], zip, { name, version, interfaces, notes });
  }
}

main().catch((e) => fail(e.stack || String(e)));
