function decodeBase64URL(value: string): Uint8Array {
  const padded = value
    .replaceAll("-", "+")
    .replaceAll("_", "/")
    .padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

function encodeBase64URL(value: Uint8Array): string {
  const encoded = btoa(String.fromCharCode(...value));
  return encoded.replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function importEncryptionKey(secret: string): Promise<CryptoKey> {
  const bytes = decodeBase64URL(secret);
  if (bytes.byteLength !== 32) {
    throw new Error("AGENT_KEY_ENCRYPTION_KEY must contain 32 base64url-encoded bytes.");
  }
  return crypto.subtle.importKey("raw", bytes, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

export async function encryptAgentKey(
  value: string,
  secret: string,
  agentId: string,
): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv,
      additionalData: new TextEncoder().encode(agentId),
    },
    await importEncryptionKey(secret),
    new TextEncoder().encode(value),
  );
  return `v1.${encodeBase64URL(iv)}.${encodeBase64URL(new Uint8Array(encrypted))}`;
}

export async function decryptAgentKey(
  value: string,
  secret: string,
  agentId: string,
): Promise<string> {
  const [version, encodedIV, encodedValue] = value.split(".");
  if (version !== "v1" || !encodedIV || !encodedValue) {
    throw new Error("The stored agent key is not valid.");
  }
  const decrypted = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: decodeBase64URL(encodedIV),
      additionalData: new TextEncoder().encode(agentId),
    },
    await importEncryptionKey(secret),
    decodeBase64URL(encodedValue),
  );
  return new TextDecoder().decode(decrypted);
}
