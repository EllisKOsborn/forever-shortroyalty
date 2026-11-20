// Run by the "Discord bot" workflow after each deploy:
//  1. registers the slash commands (/link, /raid-post);
//  2. tells Discord where the bot lives (WORKER_URL), if given;
//  3. prints the link that adds the bot to a server.
// Needs DISCORD_APPLICATION_ID and DISCORD_BOT_TOKEN; DISCORD_GUILD_ID
// (optional) registers the commands for that server only (instant).
import { COMMANDS } from "../src/commands.js";

const { DISCORD_APPLICATION_ID: app, DISCORD_BOT_TOKEN: token, DISCORD_GUILD_ID: guild, WORKER_URL: url } = process.env;
if (!app || !token) {
  console.error("DISCORD_APPLICATION_ID and DISCORD_BOT_TOKEN are needed.");
  process.exit(1);
}
const API = "https://discord.com/api/v10";
const headers = { Authorization: `Bot ${token}`, "Content-Type": "application/json", "User-Agent": "DiscordBot (short-royalty, 1)" };

async function call(method, path, body) {
  const res = await fetch(API + path, { method, headers, body: JSON.stringify(body) });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path}: ${res.status} ${text.slice(0, 300)}`);
  return text;
}

const path = guild ? `/applications/${app}/guilds/${guild}/commands` : `/applications/${app}/commands`;
await call("PUT", path, COMMANDS);
console.log(`Commands registered (${guild ? "this server only" : "every server the bot is in"}).`);

if (url) {
  await call("PATCH", "/applications/@me", { interactions_endpoint_url: url });
  console.log(`Discord now sends commands and buttons to ${url}`);
}

// View Channel, Send Messages, Embed Links, Read Message History.
const permissions = 1024 + 2048 + 16384 + 65536;
console.log(`Add the bot to your server: https://discord.com/oauth2/authorize?client_id=${app}&scope=bot+applications.commands&permissions=${permissions}`);
