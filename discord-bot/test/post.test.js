import { test } from "node:test";
import assert from "node:assert/strict";
import { mergeRows, buildPost, addonText, fields } from "../src/post.js";
import { letters } from "./helpers.js";

const raid = { name: "Onyxia's Lair", size: 40, at: 1796040000, sent: 1795999000 };
const game = [
  { name: "Pocus Hocus", s: "y", r: "TANK", p: "", u: 100 },
  { name: "Jheri Ashur", s: "t", r: "HEALER", p: "", u: 100 },
];

test("the newest answer wins; In and Bench come only from the game", () => {
  const rows = mergeRows(game, [
    { character: "jheri ashur", s: "y", r: "", u: 200 },
    { character: "Pocus Hocus", s: "n", r: "", u: 50 },
    { character: "Andreas Wlock", s: "y", r: "DPS", u: 150 },
  ]);
  const by = Object.fromEntries(rows.map((r) => [r.name, r]));
  assert.equal(by["Jheri Ashur"].s, "y");
  assert.equal(by["Jheri Ashur"].r, "HEALER"); // kept: Discord gave no role
  assert.equal(by["Pocus Hocus"].s, "y"); // the game's answer is newer
  assert.equal(by["Andreas Wlock"].r, "DPS");
});

test("the post lists names by role, closes after the raid, and never mentions anyone", () => {
  const post = buildPost(raid, game, [], raid.at - 3600);
  assert.deepEqual(post.allowed_mentions, { parse: [] });
  const f = post.embeds[0].fields.map((x) => x.name);
  assert.deepEqual(f, ["Tanks (1)", "Tentative (1)"]);
  assert.match(post.embeds[0].description, /<t:1796040000:F>/);
  assert.equal(post.components[0].components.every((b) => !b.disabled), true);
  const late = buildPost(raid, game, [], raid.at + 4 * 3600);
  assert.equal(late.components[0].components.every((b) => b.disabled), true);
  assert.equal(late.components[1].components[0].disabled, false); // Copy for the addon stays
});

test("once officers pick, it shows In by role and the bench", () => {
  const rows = mergeRows([
    { name: "A One", s: "y", r: "TANK", p: "i", u: 1 }, { name: "B Two", s: "y", r: "DPS", p: "b", u: 1 },
    { name: "C Three", s: "y", r: "DPS", p: "", u: 1 },
  ], []);
  assert.deepEqual(fields(rows).map((x) => x.name), ["In, Tanks (1)", "Bench (1)", "Signed up, not picked yet (1)"]);
});

test("long lists are cut to fit Discord", () => {
  const many = [];
  for (let i = 0; i < 200; i++) many.push({ name: `Player ${letters(i)}`, s: "y", r: "DPS", p: "", u: 1 });
  const f = fields(mergeRows(many, []));
  assert.ok(f[0].value.length <= 1024);
  assert.match(f[0].value, /and \d+ more$/);
});

test("the list for the addon uses words its import understands", () => {
  const text = addonText(raid, [
    { character: "Pocus Hocus", s: "y", r: "TANK" }, { character: "Jheri Ashur", s: "t", r: "" },
    { character: "Andreas Wlock", s: "n", r: "DPS" },
  ]);
  assert.equal(text, "Onyxia's Lair sign-ups from Discord\nAndreas Wlock cant come dps\nJheri Ashur tentative\nPocus Hocus signed up tank");
});
