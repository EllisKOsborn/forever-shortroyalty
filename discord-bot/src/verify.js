// Discord signs every request it sends us (Ed25519). Anything that fails
// the check is refused before it is read.
// https://discord.com/developers/docs/interactions/overview#setting-up-an-endpoint-validating-security-request-headers

export function hexToBytes(hex) {
  if (typeof hex !== "string" || hex.length % 2 !== 0 || !/^[0-9a-f]*$/i.test(hex)) return null;
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

export async function verifySignature(publicKeyHex, signatureHex, timestamp, body) {
  const key = hexToBytes(publicKeyHex);
  const sig = hexToBytes(signatureHex);
  if (!key || key.length !== 32 || !sig || sig.length !== 64 || typeof timestamp !== "string" || !timestamp) return false;
  try {
    const k = await crypto.subtle.importKey("raw", key, { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify({ name: "Ed25519" }, k, sig, new TextEncoder().encode(timestamp + body));
  } catch {
    return false;
  }
}
