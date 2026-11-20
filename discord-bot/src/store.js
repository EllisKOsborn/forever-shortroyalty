// The bot's storage: Cloudflare D1 (SQLite). Tests use node:sqlite behind
// the same small interface.
export const KEEP_DAYS = 14; // raids and their sign-ups are deleted 14 days after the start

export async function getRaid(db, guildId, id) {
  return toRaid(await db.prepare("SELECT * FROM raids WHERE guild_id = ? AND id = ?").bind(guildId, id).first());
}

export async function getRaidByMessage(db, guildId, messageId) {
  return toRaid(await db.prepare("SELECT * FROM raids WHERE guild_id = ? AND message_id = ?").bind(guildId, messageId).first());
}

function toRaid(row) {
  if (!row) return null;
  let game = [];
  try { game = JSON.parse(row.game); } catch { game = []; }
  return { ...row, game };
}

export async function saveRaid(db, guildId, raid, game, now) {
  await db.prepare(`INSERT INTO raids (guild_id, id, raid_key, name, size, at, sent, game, updated)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (guild_id, id) DO UPDATE SET raid_key = excluded.raid_key, name = excluded.name, size = excluded.size,
        at = excluded.at, sent = excluded.sent, game = excluded.game, updated = excluded.updated`)
    .bind(guildId, raid.id, raid.key, raid.name, raid.size, raid.at, raid.sent, JSON.stringify(game), now).run();
}

export async function setMessage(db, guildId, id, channelId, messageId) {
  await db.prepare("UPDATE raids SET channel_id = ?, message_id = ? WHERE guild_id = ? AND id = ?")
    .bind(channelId, messageId, guildId, id).run();
}

export async function getSignups(db, guildId, raidId) {
  const r = await db.prepare("SELECT user_id, character, s, r, u FROM signups WHERE guild_id = ? AND raid_id = ?").bind(guildId, raidId).all();
  return r.results || [];
}

export async function saveSignup(db, guildId, raidId, userId, character, s, r, u) {
  await db.prepare(`INSERT INTO signups (guild_id, raid_id, user_id, character, s, r, u) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (guild_id, raid_id, user_id) DO UPDATE SET character = excluded.character, s = excluded.s, r = excluded.r, u = excluded.u`)
    .bind(guildId, raidId, userId, character, s, r, u).run();
}

export async function getLink(db, guildId, userId) {
  return db.prepare("SELECT character FROM links WHERE guild_id = ? AND user_id = ?").bind(guildId, userId).first();
}

export async function saveLink(db, guildId, userId, character, now) {
  await db.prepare(`INSERT INTO links (guild_id, user_id, character, u) VALUES (?, ?, ?, ?)
      ON CONFLICT (guild_id, user_id) DO UPDATE SET character = excluded.character, u = excluded.u`)
    .bind(guildId, userId, character, now).run();
}

export async function prune(db, now) {
  const before = now - KEEP_DAYS * 86400;
  await db.prepare("DELETE FROM signups WHERE raid_id IN (SELECT id FROM raids WHERE at < ?)").bind(before).run();
  await db.prepare("DELETE FROM raids WHERE at < ?").bind(before).run();
}
