import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { handle } from "../src/index.js";
import { verifySignature } from "../src/verify.js";
import { deps, OFFICER, MEMBER, CODE } from "./helpers.js";

const G = "guild-1", CH = "chan-1";
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");

async function keys() {
  const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  return { pair, pub: hex(await crypto.subtle.exportKey("raw", pair.publicKey)) };
}
async function sign(pair, ts, body) {
  return hex(await crypto.subtle.sign({ name: "Ed25519" }, pair.privateKey, new TextEncoder().encode(ts + body)));
}

test("only requests signed by Discord are accepted", async () => {
  const { pair, pub } = await keys();
  const body = JSON.stringify({ type: 1 });
  const sig = await sign(pair, "123", body);
  assert.equal(await verifySignature(pub, sig, "123", body), true);
  assert.equal(await verifySignature(pub, sig, "124", body), false);
  assert.equal(await verifySignature(pub, sig, "123", body + " "), false);
  assert.equal(await verifySignature(pub, "zz", "123", body), false);
  assert.equal(await verifySignature("", sig, "123", body), false);

  const env = { DISCORD_PUBLIC_KEY: pub };
  const req = (s) => new Request("https://bot.example/", { method: "POST", body, headers: { "x-signature-ed25519": s, "x-signature-timestamp": "123" } });
  const ctx = { waitUntil() {} };
  assert.equal((await worker.fetch(req("00".repeat(64)), env, ctx)).status, 401);
  const ok = await worker.fetch(req(sig), env, ctx);
  assert.equal(ok.status, 200);
  assert.deepEqual(await ok.json(), { type: 1 });
});

const cmd = (name, member, options) => ({ type: 2, guild_id: G, channel_id: CH, member, data: { name, options } });
const modal = (member, value) => ({ type: 5, guild_id: G, channel_id: CH, member, token: "tok",
  data: { custom_id: "post", components: [{ type: 1, components: [{ type: 4, custom_id: "code", value }] }] } });
const press = (member, id, messageId) => ({ type: 3, guild_id: G, channel_id: CH, member, message: { id: messageId }, data: { custom_id: id } });

async function posted(d) {
  const r = await handle(modal(OFFICER, CODE), d);
  assert.equal(r.type, 5);
  await Promise.all(d.pending);
  return d.discord.calls.find((c) => c.op === "post");
}

test("only officers can post raids", async () => {
  const d = deps();
  assert.match((await handle(cmd("raid-post", MEMBER("u1")), d)).data.content, /Only officers/);
  assert.equal((await handle(cmd("raid-post", OFFICER), d)).type, 9);
  assert.match((await handle(modal(MEMBER("u1"), CODE), d)).data.content, /Only officers/);
  const roleOfficer = { user: { id: "u2" }, permissions: "0", roles: ["r-off"] };
  assert.equal((await handle(cmd("raid-post", roleOfficer), { ...d, env: { OFFICER_ROLES: "r-x, r-off" } })).type, 9);
  assert.match((await handle({ type: 2, data: { name: "link" } }, d)).data.content, /guild's Discord/);
});

test("a bad code is refused straight away", async () => {
  const d = deps();
  const r = await handle(modal(OFFICER, "not a code"), d);
  assert.equal(r.type, 4);
  assert.match(r.data.content, /isn't a code/);
  assert.equal(d.discord.calls.length, 0);
});

test("posting a code puts up the raid; posting again updates the same message", async () => {
  const d = deps();
  const post = await posted(d);
  assert.equal(post.channelId, CH);
  const embed = post.payload.embeds[0];
  assert.equal(embed.title, "Onyxia's Lair (40)");
  assert.deepEqual(embed.fields.map((f) => f.name), ["Tanks (1)", "Tentative (1)", "Can't come (1)"]);
  assert.match(d.discord.calls.find((c) => c.op === "reply").payload.content, /Posted/);

  d.pending.length = 0;
  await handle(modal(OFFICER, CODE), d);
  await Promise.all(d.pending);
  const edits = d.discord.calls.filter((c) => c.op === "edit");
  assert.equal(edits.length, 1);
  assert.equal(edits[0].messageId, "1000");
  assert.match(d.discord.calls.filter((c) => c.op === "reply")[1].payload.content, /Updated/);
});

test("when the bot can't post, the officer is told why", async () => {
  const d = deps();
  d.discord.failPost = true;
  await handle(modal(OFFICER, CODE), d);
  await Promise.all(d.pending);
  assert.match(d.discord.calls.find((c) => c.op === "reply").payload.content, /can't post in this channel/);
});

test("sign-up buttons need a linked character, then update the post", async () => {
  const d = deps();
  await posted(d);
  const r1 = await handle(press(MEMBER("u9"), "su:y:DPS", "1000"), d);
  assert.match(r1.data.content, /link your character/);

  const l = await handle(cmd("link", MEMBER("u9"), [{ name: "character", value: "  andreas   wlock " }]), d);
  assert.match(l.data.content, /Linked to \*\*andreas wlock\*\*/);
  const r2 = await handle(press(MEMBER("u9"), "su:y:DPS", "1000"), d);
  assert.equal(r2.type, 7);
  const f = Object.fromEntries(r2.data.embeds[0].fields.map((x) => [x.name, x.value]));
  assert.equal(f["DPS (1)"], "Andreas Wlock"); // the game's spelling; Discord's answer is newer
  assert.equal(f["Can't come (1)"], undefined);

  // Tentative keeps the role picked before.
  const r3 = await handle(press(MEMBER("u9"), "su:t", "1000"), d);
  const rows = d.db.sql.prepare("SELECT s, r FROM signups").all();
  assert.deepEqual({ ...rows[0] }, { s: "t", r: "DPS" });
  assert.match(r3.data.embeds[0].description, /Tentative 2/);
});

test("Copy for the addon lists the Discord sign-ups", async () => {
  const d = deps();
  await posted(d);
  assert.match((await handle(press(MEMBER("u1"), "copy", "1000"), d)).data.content, /Nobody has signed up/);
  await handle(cmd("link", MEMBER("u1"), [{ name: "character", value: "Jheri Ashur" }]), d);
  await handle(press(MEMBER("u1"), "su:y:HEALER", "1000"), d);
  const r = await handle(press(MEMBER("u1"), "copy", "1000"), d);
  assert.equal(r.data.flags, 64);
  assert.match(r.data.content, /```\nOnyxia's Lair sign-ups from Discord\nJheri Ashur signed up healer\n```/);
});

test("buttons on unknown or finished raids answer politely", async () => {
  const d = deps();
  assert.match((await handle(press(MEMBER("u1"), "su:n", "nope"), d)).data.content, /don't know this raid/);
  await posted(d);
  await handle(cmd("link", MEMBER("u1"), [{ name: "character", value: "Jheri Ashur" }]), d);
  const late = { ...d, now: 1796040000 + 4 * 3600 };
  assert.match((await handle(press(MEMBER("u1"), "su:n", "1000"), late)).data.content, /closed/);
  assert.match((await handle(press(MEMBER("u1"), "su:x", "1000"), d)).data.content, /don't know that button/);
});

test("short or empty names can't be linked", async () => {
  const d = deps();
  assert.match((await handle(cmd("link", MEMBER("u1"), [{ name: "character", value: "@#!" }]), d)).data.content, /Type your character/);
  assert.match((await handle(cmd("link", MEMBER("u1"), []), d)).data.content, /Type your character/);
});

test("old raids are deleted after 14 days", async () => {
  const d = deps();
  await posted(d);
  d.pending.length = 0;
  const later = { ...d, now: 1796040000 + 15 * 86400 };
  await handle(modal(OFFICER, CODE.replace("1796040000", "1797300000")), later);
  await Promise.all(d.pending);
  const ids = d.db.sql.prepare("SELECT at FROM raids").all().map((r) => r.at);
  assert.deepEqual(ids, [1797300000]);
});
