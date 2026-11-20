// Short Royalty's Discord bot (Cloudflare Worker). Discord sends every
// slash command and button press here; there's no always-on server.
//
// Game → Discord: an officer copies a code from the addon (raid ··· menu)
// and pastes it into /raid-post; the bot posts (or updates) the raid with
// sign-up buttons. Discord → game: "Copy for the addon" gives the Discord
// sign-ups as text for the addon's "Import sign-ups from Discord".
// Addons can't reach the internet, so those two pastes are the bridge.
import { verifySignature } from "./verify.js";
import { parseGameCode, cleanName, nameKey } from "./code.js";
import { buildPost, addonText, isClosed } from "./post.js";
import { isOfficer } from "./commands.js";
import * as store from "./store.js";
import { discordClient } from "./discord.js";

const EPHEMERAL = 64;
const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
const say = (content) => ({ type: 4, data: { content, flags: EPHEMERAL, allowed_mentions: { parse: [] } } });

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "POST") return new Response("Short Royalty bot", { status: 200 });
    const body = await request.text();
    const ok = await verifySignature(env.DISCORD_PUBLIC_KEY, request.headers.get("x-signature-ed25519"),
      request.headers.get("x-signature-timestamp"), body);
    if (!ok) return new Response("Bad signature", { status: 401 });
    let interaction;
    try { interaction = JSON.parse(body); } catch { return new Response("Bad request", { status: 400 }); }
    const deps = { db: env.DB, discord: discordClient(env), env, now: Math.floor(Date.now() / 1000), waitUntil: (p) => ctx.waitUntil(p) };
    return json(await handle(interaction, deps));
  },
};

// Returns the interaction response. deps = { db, discord, env, now, waitUntil }.
export async function handle(i, deps) {
  if (i.type === 1) return { type: 1 }; // Discord checking we're here
  if (!i.guild_id) return say("Use this in the guild's Discord server.");
  const user = (i.member && i.member.user) || i.user || {};
  if (i.type === 2) {
    if (i.data.name === "link") return link(i, user, deps);
    if (i.data.name === "raid-post") {
      if (!isOfficer(i.member, deps.env)) return say("Only officers can post raids.");
      return {
        type: 9,
        data: {
          custom_id: "post",
          title: "Post a raid from the addon",
          components: [{ type: 1, components: [{
            type: 4, custom_id: "code", style: 2, label: "Code from the addon (raid ··· menu)",
            placeholder: "Paste everything the addon gave you", min_length: 10, max_length: 4000, required: true,
          }] }],
        },
      };
    }
    return say("I don't know that command.");
  }
  if (i.type === 5 && i.data.custom_id === "post") return postRaid(i, deps);
  if (i.type === 3) return button(i, user, deps);
  return say("I don't know what to do with that.");
}

async function link(i, user, deps) {
  const opt = (i.data.options || []).find((o) => o.name === "character");
  const character = cleanName(opt && opt.value);
  if (character.length < 2) return say("Type your character's name as it is in game, e.g. `/link Pocus Hocus`.");
  await store.saveLink(deps.db, i.guild_id, user.id, character, deps.now);
  return say(`Linked to **${character}**. The sign-up buttons now sign up ${character}. Use \`/link\` again to change it.`);
}

function modalValue(i, id) {
  for (const row of i.data.components || []) {
    for (const c of row.components || []) if (c.custom_id === id) return c.value;
  }
  return "";
}

async function postRaid(i, deps) {
  if (!isOfficer(i.member, deps.env)) return say("Only officers can post raids.");
  const parsed = parseGameCode(modalValue(i, "code"));
  if (!parsed.ok) return say(parsed.error);
  const { raid, entries } = parsed;
  const guildId = i.guild_id, channelId = i.channel_id || (i.channel && i.channel.id);
  const work = (async () => {
    let result;
    try {
      await store.prune(deps.db, deps.now);
      const old = await store.getRaid(deps.db, guildId, raid.id);
      await store.saveRaid(deps.db, guildId, raid, entries, deps.now);
      const signups = await store.getSignups(deps.db, guildId, raid.id);
      const payload = buildPost(raid, entries, signups, deps.now);
      let posted = null;
      if (old && old.message_id && old.channel_id === channelId) {
        const r = await deps.discord.editMessage(channelId, old.message_id, payload);
        if (r.ok) posted = old.message_id;
      }
      if (!posted) {
        const r = await deps.discord.postMessage(channelId, payload);
        if (!r.ok) throw new Error(r.status === 403 ? "I can't post in this channel (I need View Channel, Send Messages and Embed Links)." : `Discord said ${r.status}.`);
        posted = r.data.id;
        await store.setMessage(deps.db, guildId, raid.id, channelId, posted);
        result = `Posted ${raid.name}.`;
      } else {
        result = `Updated the ${raid.name} post.`;
      }
    } catch (e) {
      result = `Couldn't post it: ${e.message}`;
    }
    await deps.discord.editReply(i.token, { content: result, allowed_mentions: { parse: [] } });
  })();
  deps.waitUntil(work);
  return { type: 5, data: { flags: EPHEMERAL } }; // "thinking…", answered when the post is done
}

async function button(i, user, deps) {
  const guildId = i.guild_id;
  const raid = i.message && await store.getRaidByMessage(deps.db, guildId, i.message.id);
  if (!raid) return say("I don't know this raid any more (raids are kept 14 days). An officer can post it again with /raid-post.");
  const id = i.data.custom_id || "";
  const signups = await store.getSignups(deps.db, guildId, raid.id);
  if (id === "copy") {
    if (!signups.length) return say("Nobody has signed up in Discord yet.");
    return say("Copy this, then in game: the raid's ··· menu → *Import sign-ups from Discord* → paste → Import.\n```\n" +
      addonText(raid, signups) + "\n```");
  }
  const m = /^su:(y|t|n)(?::(TANK|HEALER|DPS))?$/.exec(id);
  if (!m) return say("I don't know that button.");
  if (isClosed(raid, deps.now)) return say("Sign-ups for this raid are closed.");
  const linked = await store.getLink(deps.db, guildId, user.id);
  if (!linked) return say("First link your character: type `/link` and your character's name as in game (e.g. `/link Pocus Hocus`), then press the button again.");
  const mine = signups.find((s) => s.user_id === user.id);
  const fromGame = raid.game.find((e) => nameKey(e.name) === nameKey(linked.character));
  const role = m[2] || (mine && mine.character === linked.character && mine.r) || (fromGame && fromGame.r) || "";
  await store.saveSignup(deps.db, guildId, raid.id, user.id, linked.character, m[1], role, deps.now);
  const after = await store.getSignups(deps.db, guildId, raid.id);
  return { type: 7, data: buildPost(raid, raid.game, after, deps.now) }; // update the post in place
}
