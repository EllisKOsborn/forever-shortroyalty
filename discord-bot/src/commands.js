// The slash commands (registered by scripts/register.js).
export const MANAGE_EVENTS = 1n << 33n;
export const MANAGE_GUILD = 1n << 5n;
export const ADMINISTRATOR = 1n << 3n;

export const COMMANDS = [
  {
    name: "link",
    description: "Link your Discord to your character, so the sign-up buttons use it",
    dm_permission: false,
    options: [{ type: 3, name: "character", description: "Your character's full name, as in game (e.g. Pocus Hocus)", required: true, max_length: 40 }],
  },
  {
    name: "raid-post",
    description: "Post or update a raid from the Short Royalty addon (officers)",
    dm_permission: false,
    // Officers by default (Manage Events); server admins can change who sees it
    // in Server Settings → Integrations.
    default_member_permissions: String(MANAGE_EVENTS),
  },
];

// Officers: Manage Events, Manage Server or Administrator, or one of the
// roles in OFFICER_ROLES (comma-separated role IDs, optional).
export function isOfficer(member, env) {
  if (!member) return false;
  let perms = 0n;
  try { perms = BigInt(member.permissions || "0"); } catch { perms = 0n; }
  if (perms & (MANAGE_EVENTS | MANAGE_GUILD | ADMINISTRATOR)) return true;
  const roles = String(env.OFFICER_ROLES || "").split(",").map((s) => s.trim()).filter(Boolean);
  return roles.some((r) => (member.roles || []).includes(r));
}
