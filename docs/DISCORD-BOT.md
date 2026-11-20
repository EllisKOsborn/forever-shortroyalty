# Short Royalty's Discord bot

Our own bot (code in `discord-bot/`). It runs on **Cloudflare Workers'
free plan**, so there's no PC program and no server to keep switched on.
Discord sends each command and button press to it. GitHub deploys it.

## What it does

- **`/raid-post`** (officers): in game, open the raid's **···** menu and pick
  **Post with the Discord bot**, then copy everything. In Discord, type
  `/raid-post`, paste it into the box and press Submit. The bot posts the
  raid with its time (shown in each reader's own time zone), who's coming by
  role, and In / Bench once officers have picked. Run it again later (same
  channel) and it **updates the same post**.
- **Sign-up buttons** on the post: **Tank, Healer, DPS, Tentative, Can't
  come**. The post updates straight away. Buttons close 3 hours after the
  start.
- **`/link`** (everyone, once): `/link Pocus Hocus` tells the bot which
  character your buttons sign up. Use it again to change.
- **Copy for the addon** (button): the Discord sign-ups as a list. In game:
  the raid's ··· menu → **Import sign-ups from Discord** → paste → Import.
  A sign-up someone made in game themselves is never overwritten.

## What it can't do

**WoW addons can't use the internet**, so the game and the bot never talk
directly. The two pastes above (game → Discord, Discord → game) are the
bridge. Making it fully automatic would need a program running on
someone's PC, and we ruled that out.

## Setting it up (once, about 15 minutes, easier on a computer)

You need three free accounts: Discord (you have one), Cloudflare and GitHub
(you have one).

### A. The Discord app

1. Open <https://discord.com/developers/applications> → **New Application**
   → name it **Short Royalty** → Create.
2. On **General Information**, copy the **Application ID** and the **Public
   Key** (keep them for step 7).
3. Left menu **Bot** → **Reset Token** → copy the token. Treat it like a
   password. On the same page, turn **Public Bot** off.

### B. Cloudflare (where the bot runs)

4. Sign up at <https://dash.cloudflare.com/sign-up> (free plan). Open
   **Workers & Pages** once. If it asks you to pick a `workers.dev`
   subdomain, pick any name.
5. On the Workers & Pages page, copy your **Account ID** (right-hand side).
6. Top right, your profile → **My Profile** → **API Tokens** → **Create
   Token** → template **Edit Cloudflare Workers** → **Use template**. Under
   Permissions, **+ Add more**: *Account · D1 · Edit*. Then **Continue to
   summary** → **Create Token** → copy it.

### C. GitHub

7. The repo → **Settings** → **Secrets and variables** → **Actions** →
   **New repository secret**. Add these five, one at a time:

   | Name | Value |
   |---|---|
   | `DISCORD_APPLICATION_ID` | step 2 |
   | `DISCORD_PUBLIC_KEY` | step 2 |
   | `DISCORD_BOT_TOKEN` | step 3 |
   | `CLOUDFLARE_ACCOUNT_ID` | step 5 |
   | `CLOUDFLARE_API_TOKEN` | step 6 |

8. **Actions** tab → **Discord bot** → **Run workflow** (branch `main`).
   Wait about 2 minutes for the green tick. If it's red, send me the error.
9. Open that run → the **deploy** job → the last step (*Slash commands…*).
   Its last line is a link: open it, pick the guild's server, **Authorise**.

### D. In the Discord server

10. `/raid-post` shows for anyone with **Manage Events**. To choose who else
    can use it instead: Server Settings → **Integrations** → Short Royalty →
    `/raid-post` → add the Officer role.
11. Give the bot's role **View Channel, Send Messages, Embed Links** in the
    raid channel (it asks for these when you add it).

Optional (Settings → Secrets and variables → Actions → **Variables**):
`OFFICER_ROLES` = role IDs (comma-separated) who count as officers in the
bot, and `DISCORD_GUILD_ID` = your server's ID (commands appear instantly
in that server only).

## Good to know

- **Cost:** free. The free plan allows 100,000 requests a day; the guild
  will use a few hundred.
- **What it stores** (in your Cloudflare account only): raids posted, the
  Discord sign-ups (Discord user ID, character name, answer, role) and who
  linked which character. Raids and their sign-ups are deleted 14 days after
  the start.
- **Updates:** any change to `discord-bot/` pushed to `main` redeploys it.
- **Security:** Discord signs every request, and the bot refuses anything
  unsigned. Pasted text is checked line by line, names are stripped of
  anything that could become a mention or markup, and the bot's messages
  can't ping anyone.
