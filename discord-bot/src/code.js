// The code the addon gives officers (raid ··· menu, "Post with the Discord
// bot"). Plain text, one raid:
//
//   SR1;<raid id>;<raid key>;<raid name>;<size>;<start, unix s>;<made, unix s>
//   <character>;<s y/t/n>;<role TANK/HEALER/DPS or empty>;<place i/b or empty>;<changed, unix s>
//
// (";" because the game's text boxes read "|" as the start of a colour code.)
//   ...
//
// Lines before the SR1 line (the addon's instructions) and lines that don't
// fit are skipped. Everything here comes from a paste, so it's checked.

export const MAX_ENTRIES = 150;
export const NAME_MAX = 40;
const ROLES = new Set(["TANK", "HEALER", "DPS", ""]);
const STATUS = new Set(["y", "t", "n"]);
const PLACES = new Set(["i", "b", ""]);

// A character name as typed or pasted: letters (any language), spaces,
// apostrophes and hyphens only; nothing Discord could turn into markup or
// a mention.
export function cleanName(text) {
  if (typeof text !== "string") return "";
  const s = text.normalize("NFC").replace(/[^\p{L}\p{M}' -]/gu, " ").replace(/\s+/g, " ").trim();
  return s.length > NAME_MAX ? s.slice(0, NAME_MAX).trim() : s;
}

export function nameKey(name) {
  return cleanName(name).toLocaleLowerCase("en");
}

function int(v, min, max) {
  if (!/^\d{1,12}$/.test(v)) return null;
  const n = Number(v);
  return n >= min && n <= max ? n : null;
}

export function parseGameCode(text) {
  if (typeof text !== "string") return { ok: false, error: "That's empty." };
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  const start = lines.findIndex((l) => l.startsWith("SR1;"));
  if (start < 0) return { ok: false, error: "That isn't a code from the addon. In game, open the raid's ··· menu and pick *Post with the Discord bot*." };
  const h = lines[start].split(";");
  if (h.length !== 7) return { ok: false, error: "The code's first line is cut off. Copy all of it again." };
  const [, id, key, rawName, rawSize, rawAt, rawSent] = h;
  const size = int(rawSize, 1, 40), at = int(rawAt, 1600000000, 4000000000), sent = int(rawSent, 1600000000, 4000000000);
  const name = rawName.replace(/[^\p{L}\p{M}\p{N}' :-]/gu, "").trim().slice(0, 40);
  if (!/^[\w:-]{3,80}$/.test(id) || !/^[a-z]{1,12}$/.test(key) || !name || size === null || at === null || sent === null) {
    return { ok: false, error: "The code doesn't look right. Copy it again from the addon." };
  }
  const entries = [];
  const seen = new Set();
  for (const line of lines.slice(start + 1)) {
    if (entries.length >= MAX_ENTRIES) break;
    const f = line.split(";");
    if (f.length !== 5) continue;
    const [n, s, r, p, u] = f;
    const character = cleanName(n);
    const changed = int(u, 0, 4000000000);
    if (!character || !STATUS.has(s) || !ROLES.has(r) || !PLACES.has(p) || changed === null) continue;
    const k = nameKey(character);
    if (seen.has(k)) continue;
    seen.add(k);
    entries.push({ name: character, s, r, p, u: changed });
  }
  return { ok: true, raid: { id, key, name, size, at, sent }, entries };
}
