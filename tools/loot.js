// Builds Data/Loot.lua: the loot each raid can drop, for Reserve+ (v0.9.0),
// from warcraft.wiki.gg, checked against WoW Forever's own item data.
//
// Usage:
//   node tools/loot.js                    every raid in RAIDS below
//   node tools/loot.js --check            print what would change, write nothing
//
// How:
//   1. For each raid, find its loot page on warcraft.wiki.gg through the
//      wiki's public API (the pages listed in RAIDS, else a search). The
//      wiki's text may be reused with credit (CC BY-SA); we take only facts
//      (which items, their IDs). Wowhead is NOT read: its terms forbid it.
//   2. Take the items in the page's "Loot" section: every {{loot|...}}
//      template and every [[link]] in it.
//   3. Look each one up on the wiki: an item page links to its database
//      entry ("item=12345"): that's the item ID. Pages that don't are not
//      items (bosses, classes, tiers) and are dropped.
//   4. Check every ID against Forever's own ItemSparse (wago.tools, product
//      "wowf", newest build): same ID and name = "in Forever's data".
//      Items Forever's data doesn't hold yet (raid loot is often held back
//      until the raid opens) are kept, marked as such.
//   5. (v0.14.1) What the item looks like, for the Loot page: name, quality,
//      icon, slot and type, from the item page's tooltip box ({{#data:
//      Itemtip}}), with Forever's own name and quality winning when its data
//      has the item. The game can't name an item its data doesn't hold, so
//      without this the page showed "item 17068".
// A raid with no loot page yet keeps the list it has. The addon also learns
// every item that drops and officers can add items, so a wrong or missing
// list is never a dead end. Rerun this after a Forever patch or when the
// wiki gets a raid's loot (or let the weekly GitHub workflow do it).
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const OUT = path.join(ROOT, "Data", "Loot.lua");
const API = "https://warcraft.wiki.gg/api.php";
const AGENT = "ShortRoyaltyLootTool/1.0 (guild addon data script; github.com/EllisKOsborn/forever-shortroyalty)";

// Our raid keys (Data/Attunements.lua) -> wiki pages to try, in order, then
// a search. Forever pages first; Onyxia falls back to the original game's.
const RAIDS = {
  barrow: { name: "Barrow Deeps", pages: ["Barrow Deeps loot", "Barrow Deeps loot (Forever)", "Barrow Deeps (instance)"], search: "Barrow Deeps loot" },
  hyjal: { name: "Hyjal Summit", pages: ["Hyjal Summit loot (Forever)", "Hyjal Summit (Forever) loot", "Hyjal Summit (instance)"], search: "Hyjal Summit Forever loot" },
  ony: { name: "Onyxia's Lair", pages: ["Onyxia's Lair loot (Forever)", "Onyxia's Lair loot (Classic)"] },
};

// Links that are never items.
const NOT_ITEMS = /^(File|Category|Template|Special|Help|User|Image):|^(Priest|Warlock|Mage|Rogue|Druid|Hunter|Shaman|Warrior|Paladin|Tier \d+|Patch .*|World of Warcraft.*)$/;

function curl(url, file) {
  execFileSync("curl", ["-sSfL", "-m", "120", "-A", AGENT, "-o", file, url], { stdio: ["ignore", "ignore", "inherit"] });
}
function getJSON(params) {
  const q = Object.entries(Object.assign({ format: "json", formatversion: "2" }, params))
    .map(([k, v]) => k + "=" + encodeURIComponent(v)).join("&");
  const tmp = path.join(os.tmpdir(), "sr-wiki.json");
  curl(API + "?" + q, tmp);
  return JSON.parse(fs.readFileSync(tmp, "utf8"));
}
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); // be gentle with the wiki

// The wikitext of a page, or null.
function wikitext(title) {
  const d = getJSON({ action: "parse", page: title, prop: "wikitext", redirects: "1" });
  sleep(500);
  return d.parse ? { title: d.parse.title, text: d.parse.wikitext } : null;
}

function searchTitle(q) {
  const d = getJSON({ action: "query", list: "search", srsearch: q, srlimit: "5" });
  sleep(500);
  const hit = (d.query && d.query.search || []).find((s) => /loot/i.test(s.title));
  return hit ? hit.title : null;
}

// Item titles in the page's Loot section (everything if there's no such
// heading). The {{loot|quality|Title}} entries when the page has them
// (common and poor ones, like quest books, are left out); otherwise every
// [[link]] in the section (non-items are dropped later: they have no ID).
function itemTitles(text) {
  const m = text.match(/==\s*Loot\s*==([\s\S]*?)(\n==[^=]|$)/i);
  const section = m ? m[1] : text;
  const titles = new Set();
  for (const t of section.matchAll(/\{\{\s*loot\s*\|\s*([^|}]*)\|([^|}]+)/gi)) {
    if (!/^(common|poor|junk)$/i.test(t[1].trim())) titles.add(t[2].trim());
  }
  if (titles.size) return [...titles];
  for (const t of section.matchAll(/\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]/g)) {
    const title = t[1].trim();
    if (!NOT_ITEMS.test(title)) titles.add(title);
  }
  return [...titles];
}

// One ID per item: a Forever link wins; else IDs Forever's data holds;
// else the lowest (the original item, not a later copy such as Season of
// Discovery's 228xxx versions).
function pickIDs(ids, forever, foreverNames) {
  if (forever) return [forever];
  const known = ids.filter((id) => foreverNames[id]);
  if (known.length) return known;
  return ids.length ? [Math.min(...ids)] : [];
}

// title -> item IDs, from the external links on each item page.
function itemIDs(titles) {
  // -> { [title] = { ids, forever } }
  const out = {};
  for (let i = 0; i < titles.length; i += 40) {
    const batch = titles.slice(i, i + 40);
    const d = getJSON({ action: "query", prop: "extlinks", titles: batch.join("|"), ellimit: "max", redirects: "1" });
    sleep(500);
    const back = {}; // redirect target -> original title
    for (const r of (d.query && d.query.redirects) || []) back[r.to] = r.from;
    for (const n of (d.query && d.query.normalized) || []) back[n.to] = n.from;
    for (const p of (d.query && d.query.pages) || []) {
      const ids = new Set();
      let forever = null;
      for (const l of p.extlinks || []) {
        const url = l.url || l["*"] || "";
        const m = url.match(/wowhead\.com\/(?:([a-z-]+)\/)?item[=/](\d+)/i);
        if (m) {
          ids.add(Number(m[2]));
          if (m[1] === "forever") forever = Number(m[2]);
        }
      }
      if (ids.size) out[back[p.title] || p.title] = { ids: [...ids], forever };
    }
  }
  return out;
}

// What each item looks like: title -> [{ itemid, name, quality, icon, slot,
// type }], from the {{#data:Itemtip ...}} boxes on its wiki page (one per
// version of the item). Only plain facts are kept, cleaned for Lua.
const QUALITY = { poor: 0, common: 1, uncommon: 2, rare: 3, epic: 4, legendary: 5, artifact: 6, heirloom: 7 };
function clean(v, max) {
  if (typeof v !== "string") return undefined;
  v = v.replace(/\[\[(?:[^\]|]*\|)?([^\]]*)\]\]/g, "$1") // [[link|text]] -> text
    .replace(/<[^>]*>/g, "").replace(/'{2,}/g, "")          // html, bold/italic
    .replace(/[^\x20-\x7eÀ-ɏ]/g, "").trim();       // letters, digits, punctuation
  return v ? v.slice(0, max || 60) : undefined;
}
function itemTips(text) {
  const out = [];
  for (const m of text.matchAll(/\{\{\s*#data:Itemtip([\s\S]*?)\n\s*\}\}/gi)) {
    const f = {};
    for (const l of m[1].split("\n")) {
      const kv = l.match(/^\s*\|\s*(\w+)\s*=\s*(.*)$/);
      if (kv) f[kv[1].toLowerCase()] = kv[2];
    }
    const icon = (f.icon || "").trim().toLowerCase();
    out.push({
      itemid: Number(f.itemid) || null,
      name: clean(f.name, 80),
      quality: QUALITY[(f.quality || "").trim().toLowerCase()],
      icon: /^[a-z0-9_-]{3,80}$/.test(icon) ? icon : undefined,
      slot: clean(f.slot, 24),
      type: clean(f.type, 24),
    });
  }
  return out;
}
function itemPages(titles) {
  const out = {};
  for (let i = 0; i < titles.length; i += 40) {
    const batch = titles.slice(i, i + 40);
    const d = getJSON({ action: "query", prop: "revisions", rvprop: "content", rvslots: "main", titles: batch.join("|"), redirects: "1" });
    sleep(500);
    const back = {};
    for (const r of (d.query && d.query.redirects) || []) back[r.to] = r.from;
    for (const n of (d.query && d.query.normalized) || []) back[n.to] = n.from;
    for (const p of (d.query && d.query.pages) || []) {
      const rev = p.revisions && p.revisions[0];
      const text = rev && ((rev.slots && rev.slots.main && rev.slots.main.content) || rev.content);
      if (text) out[back[p.title] || p.title] = itemTips(text);
    }
  }
  return out;
}
// The look of one item: its own tooltip box (same item ID), else the
// page's first; Forever's name and quality win when its data has the item.
function lookOf(id, title, tips, forever) {
  const list = tips[title] || [];
  const t = list.find((x) => x.itemid === id) || list[0] || {};
  const info = { name: t.name || clean(title.replace(/ \((Classic|tier \d+|Forever)\)$/i, ""), 80), q: t.quality, icon: t.icon, slot: t.slot, type: t.type };
  if (forever.names[id]) {
    info.name = clean(forever.names[id], 80) || info.name;
    if (forever.quality[id] !== undefined) info.q = forever.quality[id];
    info.f = true;
  }
  return info;
}

// Forever's item data: id -> name, quality (newest build).
function foreverItems() {
  const tmp = path.join(os.tmpdir(), "sr-builds.json");
  curl("https://wago.tools/api/builds", tmp);
  const build = JSON.parse(fs.readFileSync(tmp, "utf8")).wowf[0].version;
  const csv = path.join(os.tmpdir(), "sr-itemsparse.csv");
  curl("https://wago.tools/db2/ItemSparse/csv?build=" + build, csv);
  const lines = fs.readFileSync(csv, "utf8").split(/\r?\n/);
  const head = lines[0].split(",");
  const iId = head.indexOf("ID"), iName = head.indexOf("Display_lang"), iQ = head.indexOf("OverallQualityID");
  const names = {}, quality = {};
  const last = Math.max(iId, iName, iQ);
  for (const line of lines.slice(1)) {
    // Names come before most commas we care about only when quoted; a small CSV reader is enough here.
    const cells = [];
    let cur = "", q = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (q) { if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; } else if (c === '"') q = false; else cur += c; }
      else if (c === '"') q = true;
      else if (c === ",") { cells.push(cur); cur = ""; if (cells.length > last) break; }
      else cur += c;
    }
    cells.push(cur);
    if (cells[iId]) {
      names[Number(cells[iId])] = cells[iName];
      if (iQ >= 0 && cells[iQ] !== undefined && cells[iQ] !== "") quality[Number(cells[iId])] = Number(cells[iQ]);
    }
  }
  return { build, names, quality };
}

// The current file's lists (kept for raids the wiki has nothing for yet).
function currentLists() {
  if (!fs.existsSync(OUT)) return {};
  const src = fs.readFileSync(OUT, "utf8");
  const out = {};
  for (const m of src.matchAll(/^\t(\w+) = \{\n([\s\S]*?)\n\t\},/gm)) {
    const ids = [...m[2].matchAll(/^\t\t\t(\d+),/gm)].map((x) => Number(x[1]));
    const st = (m[2].match(/status = "(\w+)"/) || [])[1];
    const src2 = (m[2].match(/source = "([^"]*)"/) || [])[1];
    out[m[1]] = { ids, status: st, source: src2, names: Object.fromEntries([...m[2].matchAll(/^\t\t\t(\d+), -- (.*?)(?: \(not in Forever's data yet\))?$/gm)].map((x) => [x[1], x[2]])), looks: {} };
  }
  // A kept list keeps its looks (the LOOT_ITEMS lines) and its "not in
  // Forever's data yet" marks (from f).
  const looks = {};
  for (const m of src.matchAll(/^\t\[(\d+)\] = \{ (.*) \},$/gm)) {
    const info = {};
    for (const f of m[2].matchAll(/(\w+) = ("(?:[^"\\]|\\.)*"|\d+|true)/g)) {
      info[f[1]] = f[2] === "true" ? true : /^\d+$/.test(f[2]) ? Number(f[2]) : JSON.parse(f[2]);
    }
    looks[m[1]] = info;
  }
  for (const r of Object.values(out)) {
    r.inForever = {};
    for (const id of r.ids) {
      if (looks[id]) r.looks[id] = looks[id];
      if (looks[id] && looks[id].f) r.inForever[id] = true;
    }
  }
  return out;
}

function main() {
  const check = process.argv.includes("--check");
  const forever = foreverItems();
  const old = currentLists();
  const result = {};
  for (const [key, raid] of Object.entries(RAIDS)) {
    let page = null;
    for (const t of raid.pages) { page = wikitext(t); if (page && /\{\{\s*loot\s*\|/i.test(page.text)) break; page = null; }
    if (!page && raid.search) {
      const t = searchTitle(raid.search);
      const p = t && wikitext(t);
      if (p && /\{\{\s*loot\s*\|/i.test(p.text)) page = p;
    }
    if (!page) {
      console.log(`${raid.name}: no loot page on the wiki yet; keeping ${old[key] ? old[key].ids.length : 0} items`);
      result[key] = old[key] || { ids: [], status: "todo", names: {} };
      continue;
    }
    const titles = itemTitles(page.text);
    const ids = itemIDs(titles);
    const tips = itemPages(titles.filter((t) => ids[t]));
    const items = [];
    const names = {};
    const looks = {};
    for (const t of titles) for (const id of (ids[t] ? pickIDs(ids[t].ids, ids[t].forever, forever.names) : [])) {
      if (!items.includes(id)) { items.push(id); looks[id] = lookOf(id, t, tips, forever); names[id] = looks[id].name; }
    }
    let inData = 0;
    const inForever = {};
    for (const id of items) if (forever.names[id]) { inData++; inForever[id] = true; }
    const status = /Forever/i.test(page.title) ? "forever" : "classic";
    console.log(`${raid.name}: ${page.title}: ${items.length} items, ${inData} in Forever's data (build ${forever.build})`);
    result[key] = { ids: items, status, source: page.title, names, inForever, looks, build: forever.build };
  }
  const lua = render(result, forever.build);
  const before = fs.existsSync(OUT) ? fs.readFileSync(OUT, "utf8") : "";
  const changed = strip(before) !== strip(lua);
  if (check) { console.log(changed ? "Data/Loot.lua would change" : "Data/Loot.lua is up to date"); process.exit(changed ? 2 : 0); }
  if (changed) { fs.writeFileSync(OUT, lua); console.log("wrote", OUT); } else console.log("no change");
}

// The header has the date and build; compare without it.
function strip(s) { return s.replace(/^-- Generated .*$/m, "").replace(/^-- Forever item data: .*$/m, ""); }

function render(result, build) {
  const L = [];
  L.push("-- Raid loot lists for Reserve+ (v0.9.0). GENERATED by tools/loot.js: don't edit by hand.");
  L.push("-- Generated " + new Date().toISOString().slice(0, 10) + " from warcraft.wiki.gg (CC BY-SA; facts only: which items, their IDs).");
  L.push("-- Forever item data: wago.tools build " + build + ".");
  L.push("--");
  L.push("-- status: \"forever\" = the wiki's page for Forever; \"classic\" = the original game's");
  L.push("-- loot (Forever may change it); \"todo\" = no loot page yet. Every item is");
  L.push("-- marked whether Forever's own item data holds it yet: raid loot is often");
  L.push("-- held back until the raid opens. The addon also learns every item that");
  L.push("-- drops, and officers can add items (Loot > Rules), so the lists fix");
  L.push("-- themselves after a kill.");
  L.push("local _, SK = ...");
  L.push("SK.Data = SK.Data or {}");
  L.push("");
  L.push("SK.Data.LOOT = {");
  for (const key of Object.keys(RAIDS)) {
    const r = result[key] || { ids: [], status: "todo", names: {} };
    L.push(`\t${key} = {`);
    L.push(`\t\tstatus = "${r.status || "todo"}",`);
    if (r.source) L.push(`\t\tsource = "${r.source.replace(/"/g, "'")}",`);
    L.push("\t\titems = {");
    for (const id of r.ids) {
      const name = (r.names && r.names[id]) || "";
      const note = r.inForever && !r.inForever[id] ? " (not in Forever's data yet)" : "";
      L.push(name || note ? `\t\t\t${id}, -- ${name}${note}` : `\t\t\t${id},`);
    }
    L.push("\t\t},");
    L.push("\t},");
  }
  L.push("}");
  L.push("");
  L.push("-- What each listed item looks like (v0.14.1), so the Loot page can show");
  L.push("-- items the game can't name yet: name, q = quality (0 poor .. 5");
  L.push("-- legendary), icon (a file in Interface\\Icons), slot and type, from the");
  L.push("-- item's wiki tooltip; f = Forever's own data has the item (its name and");
  L.push("-- quality are used then).");
  L.push("SK.Data.LOOT_ITEMS = {");
  const seen = new Set();
  for (const key of Object.keys(RAIDS)) {
    const r = result[key] || { ids: [] };
    for (const id of r.ids) {
      const info = r.looks && r.looks[id];
      if (seen.has(id) || !info || !info.name) continue;
      seen.add(id);
      // JSON's string escapes (\" and \\) are Lua's too; clean() left no control characters.
      const parts = [`name = ${JSON.stringify(info.name)}`];
      if (Number.isInteger(info.q) && info.q >= 0 && info.q <= 7) parts.push(`q = ${info.q}`);
      if (info.icon) parts.push(`icon = ${JSON.stringify(info.icon)}`);
      if (info.slot) parts.push(`slot = ${JSON.stringify(info.slot)}`);
      if (info.type) parts.push(`type = ${JSON.stringify(info.type)}`);
      if (info.f) parts.push("f = true");
      L.push(`\t[${id}] = { ${parts.join(", ")} },`);
    }
  }
  L.push("}");
  return L.join("\n") + "\n";
}

main();
