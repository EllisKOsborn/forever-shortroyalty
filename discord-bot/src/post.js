// What the raid post looks like, and the list for the addon. Pure.
import { nameKey } from "./code.js";

export const ACCENT = 0xf06bb0; // the addon's pink accent
export const CLOSE_AFTER = 3 * 3600; // sign-up buttons close 3 hours after the start
export const ROLE_NAMES = { TANK: "Tanks", HEALER: "Healers", DPS: "DPS" };
const FIELD_MAX = 1024;
const NO_MENTIONS = { parse: [] };

// One row per character: the game's list (from the last code) and the
// Discord sign-ups. The newest answer wins; In / Bench only come from game.
export function mergeRows(gameEntries, signups) {
  const rows = new Map();
  for (const e of gameEntries || []) {
    rows.set(nameKey(e.name), { name: e.name, s: e.s, r: e.r || "", p: e.p || "", u: e.u, from: "game" });
  }
  for (const su of signups || []) {
    const k = nameKey(su.character);
    const have = rows.get(k);
    if (!have) rows.set(k, { name: su.character, s: su.s, r: su.r || "", p: "", u: su.u, from: "discord" });
    else if (su.u > have.u) Object.assign(have, { s: su.s, r: su.r || have.r, u: su.u, from: "discord" });
  }
  return [...rows.values()].sort((a, b) => a.name.localeCompare(b.name, "en"));
}

function list(rows) {
  let text = "";
  for (let i = 0; i < rows.length; i++) {
    const next = (text ? text + ", " : "") + rows[i].name;
    if (next.length > FIELD_MAX - 20) return `${text} and ${rows.length - i} more`;
    text = next;
  }
  return text;
}

export function fields(rows) {
  const out = [];
  const add = (title, rs) => { if (rs.length) out.push({ name: `${title} (${rs.length})`, value: list(rs), inline: false }); };
  const picked = rows.some((r) => r.p === "i");
  for (const role of ["TANK", "HEALER", "DPS"]) {
    add((picked ? "In, " : "") + ROLE_NAMES[role], rows.filter((r) => r.r === role && (picked ? r.p === "i" : r.s === "y")));
  }
  add(picked ? "In, role unknown" : "Role unknown", rows.filter((r) => !r.r && (picked ? r.p === "i" : r.s === "y")));
  if (picked) {
    add("Bench", rows.filter((r) => r.p === "b"));
    add("Signed up, not picked yet", rows.filter((r) => !r.p && r.s === "y"));
  }
  add("Tentative", rows.filter((r) => r.s === "t" && !r.p));
  add("Can't come", rows.filter((r) => r.s === "n" && !r.p));
  return out;
}

export function countsText(rows, size) {
  const n = (f) => rows.filter(f).length;
  if (rows.some((r) => r.p === "i")) {
    return `In ${n((r) => r.p === "i")} / ${size}  ·  Bench ${n((r) => r.p === "b")}`;
  }
  return `Signed up ${n((r) => r.s === "y")} / ${size}  ·  Tentative ${n((r) => r.s === "t")}  ·  Can't come ${n((r) => r.s === "n")}`;
}

export function isClosed(raid, now) {
  return now > raid.at + CLOSE_AFTER;
}

export function buildPost(raid, gameEntries, signups, now) {
  const rows = mergeRows(gameEntries, signups);
  const closed = isClosed(raid, now);
  const description = [
    `<t:${raid.at}:F> (<t:${raid.at}:R>)`,
    countsText(rows, raid.size),
    "",
    closed ? "Sign-ups are closed." : "Sign up with the buttons below (once: `/link` your character), or in game with `/sr raids`.",
  ].join("\n");
  const button = (label, id, style) => ({ type: 2, style, label, custom_id: id, disabled: closed && id !== "copy" });
  return {
    embeds: [{
      title: `${raid.name} (${raid.size})`,
      description,
      color: ACCENT,
      fields: fields(rows),
      footer: { text: "Short Royalty · game list updated" },
      timestamp: new Date(raid.sent * 1000).toISOString(),
    }],
    components: [
      { type: 1, components: [
        button("Tank", "su:y:TANK", 2), button("Healer", "su:y:HEALER", 2), button("DPS", "su:y:DPS", 2),
        button("Tentative", "su:t", 2), button("Can't come", "su:n", 4),
      ] },
      { type: 1, components: [button("Copy for the addon", "copy", 2)] },
    ],
    allowed_mentions: NO_MENTIONS,
  };
}

const STATUS_WORD = { y: "signed up", t: "tentative", n: "cant come" };
const ROLE_WORD = { TANK: "tank", HEALER: "healer", DPS: "dps" };

// The sign-ups made in Discord, as lines the addon's "Import sign-ups from
// Discord" reads: the name, then a status word and a role word.
export function addonText(raid, signups) {
  const lines = [...signups]
    .sort((a, b) => a.character.localeCompare(b.character, "en"))
    .map((su) => [su.character, STATUS_WORD[su.s] || "signed up", ROLE_WORD[su.r] || ""].join(" ").trim());
  return [`${raid.name} sign-ups from Discord`, ...lines].join("\n");
}
