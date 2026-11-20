// Calls to Discord's API, made with the bot's token. Every message turns
// mentions off, so nothing pasted can ping @everyone.
const API = "https://discord.com/api/v10";

export function discordClient(env, fetchImpl = fetch) {
  async function call(method, path, body, auth = true) {
    const headers = { "Content-Type": "application/json", "User-Agent": "DiscordBot (short-royalty, 1)" };
    if (auth) headers.Authorization = `Bot ${env.DISCORD_BOT_TOKEN}`;
    const res = await fetchImpl(API + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
    let data = null;
    try { data = await res.json(); } catch { data = null; }
    return { ok: res.ok, status: res.status, data };
  }
  return {
    postMessage: (channelId, payload) => call("POST", `/channels/${channelId}/messages`, payload),
    editMessage: (channelId, messageId, payload) => call("PATCH", `/channels/${channelId}/messages/${messageId}`, payload),
    editReply: (token, payload) => call("PATCH", `/webhooks/${env.DISCORD_APPLICATION_ID}/${token}/messages/@original`, payload, false),
  };
}
