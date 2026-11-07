// Reads the DevTest report from the game's SavedVariables and prints it.
//
//   node tools/devtest/report.mjs                    WoW Forever (default)
//   node tools/devtest/report.mjs "<client folder>"  any other client
//   node tools/devtest/report.mjs --json             the raw report as JSON
//   node tools/devtest/report.mjs --all              every step, not only the failed ones
//   node tools/devtest/report.mjs --probe            the collections probe (/devtest probe)
//
// The game writes SavedVariables on /reload or logout, so run /devtest, then /reload.

import fs from 'node:fs';
import path from 'node:path';

const DEFAULT_CLIENT = 'F:\\World of Warcraft\\_forever_';
const args = process.argv.slice(2);
const client = args.find((a) => !a.startsWith('--')) || DEFAULT_CLIENT;
const asJson = args.includes('--json');
const showAll = args.includes('--all');

// SavedVariables ------------------------------------------------------------------------

function findSavedVariables() {
  const accounts = path.join(client, 'WTF', 'Account');
  const files = [];
  for (const account of fs.readdirSync(accounts)) {
    const file = path.join(accounts, account, 'SavedVariables', '!MorigollDevTest.lua');
    if (fs.existsSync(file)) files.push(file);
  }
  if (!files.length) throw new Error(`No !MorigollDevTest.lua under ${accounts} (has the game done a /reload with the harness?)`);
  return files.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
}

// A parser for the subset of Lua the game writes into SavedVariables.
function parseSavedVariables(text) {
  let i = 0;
  const out = {};
  const ws = () => {
    for (;;) {
      while (i < text.length && /\s/.test(text[i])) i++;
      if (text.startsWith('--', i)) {
        while (i < text.length && text[i] !== '\n') i++;
      } else return;
    }
  };
  const fail = (msg) => { throw new Error(`${msg} at ${i}: ${JSON.stringify(text.slice(i, i + 40))}`); };
  const ESC = { n: '\n', t: '\t', r: '\r', '\\': '\\', '"': '"', "'": "'", a: '\x07', b: '\b', f: '\f', v: '\v' };
  function str() {
    const q = text[i++];
    let s = '';
    while (text[i] !== q) {
      if (i >= text.length) fail('unterminated string');
      if (text[i] === '\\') {
        const c = text[i + 1];
        if (c === '\n') { s += '\n'; i += 2; continue; }
        if (/\d/.test(c)) {
          const m = /^\d{1,3}/.exec(text.slice(i + 1));
          s += String.fromCharCode(Number(m[0]));
          i += 1 + m[0].length;
          continue;
        }
        s += ESC[c] ?? c;
        i += 2;
      } else s += text[i++];
    }
    i++;
    return s;
  }
  function value() {
    ws();
    const c = text[i];
    if (c === '{') return table();
    if (c === '"' || c === "'") return str();
    const m = /^(?:-?(?:\d+\.?\d*(?:[eE][-+]?\d+)?|0x[\da-fA-F]+)|-?inf|-?nan|true|false|nil)/.exec(text.slice(i));
    if (!m) fail('unexpected value');
    i += m[0].length;
    if (m[0] === 'true') return true;
    if (m[0] === 'false') return false;
    if (m[0] === 'nil') return null;
    return Number(m[0].replace(/inf/, 'Infinity'));
  }
  function table() {
    i++; // {
    const arr = [];
    const obj = {};
    let isArr = true;
    for (;;) {
      ws();
      if (text[i] === '}') { i++; break; }
      if (text[i] === '[') {
        i++;
        const key = value();
        ws(); if (text[i] !== ']') fail('expected ]'); i++;
        ws(); if (text[i] !== '=') fail('expected ='); i++;
        obj[key] = value();
        isArr = false;
      } else {
        arr.push(value());
      }
      ws();
      if (text[i] === ',' || text[i] === ';') i++;
    }
    if (isArr) return arr;
    arr.forEach((v, k) => { obj[k + 1] = v; });
    return obj;
  }
  for (;;) {
    ws();
    if (i >= text.length) break;
    const m = /^[A-Za-z_]\w*/.exec(text.slice(i));
    if (!m) fail('expected a name');
    i += m[0].length;
    ws(); if (text[i] !== '=') fail('expected ='); i++;
    out[m[0]] = value();
  }
  return out;
}

const list = (t) => (Array.isArray(t) ? t : t ? Object.keys(t).sort((a, b) => a - b).map((k) => t[k]) : []);

// Screenshots -----------------------------------------------------------------------------

function screenshots() {
  const dir = path.join(client, 'Screenshots');
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .map((name) => {
      const m = /_(\d\d)(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)\./.exec(name);
      return m && { name, file: path.join(dir, name), date: `20${m[3]}-${m[1]}-${m[2]}`, time: `${m[4]}:${m[5]}:${m[6]}` };
    })
    .filter(Boolean);
}

function secs(hms) {
  const [h, m, s] = hms.split(':').map(Number);
  return h * 3600 + m * 60 + s;
}

// Report ----------------------------------------------------------------------------------

const file = findSavedVariables();
const db = parseSavedVariables(fs.readFileSync(file, 'utf8')).MorigollDevTestDB;
if (!db) throw new Error(`No MorigollDevTestDB in ${file}`);
if (asJson) {
  console.log(JSON.stringify(db, null, 2));
  process.exit(0);
}

if (args.includes('--probe')) {
  if (!db.probe) throw new Error('No probe in the report: run /devtest probe, then /reload');
  console.log(JSON.stringify(db.probe, null, 1));
  process.exit(0);
}

const run = db.run;
const session = db.session || {};
const line = (s = '') => console.log(s);
const indent = (text, pad = '      ') => String(text).trim().split('\n').map((l) => pad + l).join('\n');

line(`Report: ${file} (saved ${fs.statSync(file).mtime.toLocaleString()})`);
const env = (run && run.env) || session.env || {};
line(`Client: ${env.version} build ${env.build} (toc ${env.toc}) ${env.locale} · ${env.char} lvl ${env.level} ${env.class} · ${env.zone}${env.subzone ? ' / ' + env.subzone : ''} (map ${env.mapID}) · screen ${env.screen} · ui scale ${env.uiScale}`);

const addons = (run && run.addons) || session.addons || {};
for (const [name, a] of Object.entries(addons)) {
  line(`  ${name.padEnd(14)} loaded=${a.loaded} loadable=${a.loadable}${a.reason ? ' reason=' + a.reason : ''} v${a.version} toc=${a.interface} tableAccess=${a.localTable}${a.memoryKB != null ? ' mem=' + Math.round(a.memoryKB) + 'KB' : ''}${a.loadError ? ' LOAD ERROR' : ''}`);
}
line(`Error handler installed: session=${session.handlerInstalled} run=${run && run.handlerInstalled}`);

function dump(title, entries) {
  entries = list(entries);
  line();
  line(`${title}: ${entries.length ? entries.reduce((n, e) => n + (e.count || 1), 0) : 'none'}`);
  for (const e of entries) {
    line(`  [${e.addon || '?'}] x${e.count} at ${e.at}s${e.step ? ' during "' + e.step + '"' : ''}${e.where ? ' in ' + e.where : ''}`);
    line(indent(e.msg));
    if (e.stack) line(indent(e.stack.split('\n').slice(0, 6).join('\n'), '        | '));
  }
}
dump('Lua errors this session', session.errors);
dump('Errors caught inside the addons (pcall)', session.caught);
dump('Blocked actions', session.blocked);
dump('Lua warnings', session.warnings);

if (!run) {
  line();
  line('No /devtest run in this report.');
  process.exit(0);
}

const s = run.summary || {};
line();
line(`/devtest ${run.startedAt} -> ${run.finishedAt || '(did not finish: no /reload after it ended?)'}${run.aborted ? ' ABORTED: ' + run.aborted : ''}`);
line(`  ${s.passed}/${s.steps} steps OK, ${s.checks} checks, ${s.newErrors} Lua errors, ${s.newCaught} caught, ${s.newBlocked} blocked, ${s.shots} screenshots`);

const shots = screenshots();
const day = run.startedAt && run.startedAt.slice(0, 10);
function shotFor(time) {
  let best = null;
  for (const sh of shots) {
    if (sh.date !== day) continue;
    const d = secs(sh.time) - secs(time);
    if (d >= -1 && d <= 3 && (!best || Math.abs(d) < Math.abs(best.d))) best = { ...sh, d };
  }
  return best;
}

for (const st of list(run.steps)) {
  const failed = !st.ok;
  if (!showAll && !failed && !st.shot && !st.data && !st.tooltip) continue;
  line();
  line(`${failed ? 'FAIL' : ' ok '} #${st.n} [${st.addon}] ${st.label}${st.errors ? `  (${st.errors} Lua errors)` : ''}${st.caught ? `  (${st.caught} caught)` : ''}${st.blocked ? `  (${st.blocked} blocked)` : ''}`);
  for (const f of list(st.fails)) line(`      x ${f}`);
  for (const b of list(st.bad)) line(`      suspicious text: ${JSON.stringify(b)}`);
  if (st.data) line(indent(JSON.stringify(st.data)));
  if (st.tooltip) line(`      tooltip: ${list(st.tooltip).join(' / ')}`);
  if (st.texts && (failed || showAll)) line(`      texts: ${list(st.texts).slice(0, 40).join(' / ')}`);
  if (st.shot) {
    const sh = shotFor(st.shot);
    line(`      screenshot ${st.shot}: ${sh ? sh.file : '(file not found)'}`);
  }
}
