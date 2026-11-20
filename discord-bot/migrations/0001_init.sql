-- Raids posted from the addon (the game's list is kept as JSON), the
-- sign-ups made with the buttons, and who linked which character.
CREATE TABLE IF NOT EXISTS raids (
  guild_id TEXT NOT NULL,
  id TEXT NOT NULL,
  raid_key TEXT NOT NULL,
  name TEXT NOT NULL,
  size INTEGER NOT NULL,
  at INTEGER NOT NULL,
  sent INTEGER NOT NULL,
  game TEXT NOT NULL,
  channel_id TEXT,
  message_id TEXT,
  updated INTEGER NOT NULL,
  PRIMARY KEY (guild_id, id)
);
CREATE INDEX IF NOT EXISTS raids_message ON raids (message_id);

CREATE TABLE IF NOT EXISTS signups (
  guild_id TEXT NOT NULL,
  raid_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  character TEXT NOT NULL,
  s TEXT NOT NULL,
  r TEXT NOT NULL,
  u INTEGER NOT NULL,
  PRIMARY KEY (guild_id, raid_id, user_id)
);

CREATE TABLE IF NOT EXISTS links (
  guild_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  character TEXT NOT NULL,
  u INTEGER NOT NULL,
  PRIMARY KEY (guild_id, user_id)
);
