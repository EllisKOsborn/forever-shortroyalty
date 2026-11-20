// A D1 stand-in on node:sqlite, and a Discord stand-in that records calls.
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";

export function fakeDB() {
  const sql = new DatabaseSync(":memory:");
  sql.exec(readFileSync(new URL("../migrations/0001_init.sql", import.meta.url), "utf8"));
  return {
    sql,
    prepare(q) {
      const stmt = sql.prepare(q);
      let args = [];
      const api = {
        bind(...a) { args = a; return api; },
        async first() { return stmt.get(...args) ?? null; },
        async all() { return { results: stmt.all(...args) }; },
        async run() { stmt.run(...args); return { success: true }; },
      };
      return api;
    },
  };
}

export function fakeDiscord() {
  const calls = [];
  let next = 1000;
  return {
    calls,
    failPost: false,
    async postMessage(channelId, payload) {
      calls.push({ op: "post", channelId, payload });
      if (this.failPost) return { ok: false, status: 403, data: null };
      return { ok: true, status: 200, data: { id: String(next++) } };
    },
    async editMessage(channelId, messageId, payload) {
      calls.push({ op: "edit", channelId, messageId, payload });
      return { ok: true, status: 200, data: { id: messageId } };
    },
    async editReply(token, payload) { calls.push({ op: "reply", token, payload }); return { ok: true }; },
  };
}

export function deps(over = {}) {
  const pending = [];
  return {
    db: fakeDB(), discord: fakeDiscord(), env: {}, now: 1796000000,
    waitUntil: (p) => pending.push(p), pending, ...over,
  };
}

export const OFFICER = { user: { id: "u-off" }, permissions: String(1n << 33n), roles: [] };
export const MEMBER = (id) => ({ user: { id }, permissions: "0", roles: [] });

export const CODE = [
  "In Discord: type /raid-post, paste all of this, press Submit.",
  "SR1;Player-6937-001743F0:1795990000;ony;Onyxia's Lair;40;1796040000;1795999000",
  "Pocus Hocus;y;TANK;;1795990100",
  "Jheri Ashur;t;HEALER;;1795990200",
  "Andreas Wlock;n;DPS;;1795990300",
].join("\n");

// A unique letters-only name part for i (names never contain digits).
export function letters(i) {
  let s = "";
  do { s = String.fromCharCode(97 + (i % 26)) + s; i = Math.floor(i / 26); } while (i > 0);
  return "X" + s;
}
