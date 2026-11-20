import { test } from "node:test";
import assert from "node:assert/strict";
import { parseGameCode, cleanName } from "../src/code.js";
import { CODE, letters } from "./helpers.js";

test("reads the addon's code, skipping the instructions before it", () => {
  const r = parseGameCode(CODE);
  assert.equal(r.ok, true);
  assert.deepEqual(r.raid, { id: "Player-6937-001743F0:1795990000", key: "ony", name: "Onyxia's Lair", size: 40, at: 1796040000, sent: 1795999000 });
  assert.equal(r.entries.length, 3);
  assert.deepEqual(r.entries[0], { name: "Pocus Hocus", s: "y", r: "TANK", p: "", u: 1795990100 });
});

test("refuses text that isn't a code", () => {
  assert.equal(parseGameCode("hello").ok, false);
  assert.equal(parseGameCode("SR1;x;ony").ok, false);
  assert.equal(parseGameCode("SR1;Player-1:2;ony;Onyxia;99;1796040000;1795999000").ok, false); // size
  assert.equal(parseGameCode("SR1;Player 1;ony;Onyxia;40;1796040000;1795999000").ok, false); // id
  assert.equal(parseGameCode(undefined).ok, false);
});

test("skips bad lines and repeats, and caps the list", () => {
  const head = "SR1;Player-1:2;ony;Onyxia's Lair;40;1796040000;1795999000";
  const lines = [head, "Pocus Hocus;x;TANK;;1", "Pocus Hocus;y;MAGE;;1", "Pocus Hocus;y;DPS;i;1", "pocus hocus;n;;b;1", "Nope|y|DPS"];
  for (let i = 0; i < 200; i++) lines.push(`Name ${letters(i)};y;DPS;;1`);
  const r = parseGameCode(lines.join("\n"));
  assert.equal(r.entries[0].p, "i");
  assert.equal(r.entries.filter((e) => e.name.toLowerCase() === "pocus hocus").length, 1);
  assert.equal(r.entries.length, 150);
});

test("names lose anything that could become markup or a mention", () => {
  assert.equal(cleanName("  @everyone **Pocus**  <@123> Hocus "), "everyone Pocus Hocus");
  assert.equal(cleanName("Zoë O'Neil-Smith"), "Zoë O'Neil-Smith");
  assert.equal(cleanName("x".repeat(60)).length, 40);
  assert.equal(cleanName(42), "");
});
