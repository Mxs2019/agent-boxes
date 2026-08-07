import type { CardUpdateMessage, DeviceRow } from "./types";

interface PushEnv extends Env {
  APNS_DEVELOPMENT_KEY_ID?: string;
  APNS_DEVELOPMENT_PRIVATE_KEY?: string;
  APNS_PRODUCTION_KEY_ID?: string;
  APNS_PRODUCTION_PRIVATE_KEY?: string;
  APNS_TEAM_ID?: string;
}

export interface PushConfiguration {
  keyId: string;
  privateKey: string;
  teamId: string;
  topic: string;
}

export interface PushAlert {
  body: string;
  cardId?: string;
  title: string;
}

interface ProviderToken {
  configurationKey: string;
  issuedAt: number;
  value: string;
}

const cachedProviderTokens = new Map<string, ProviderToken>();
const DEFAULT_PUSH_BODY = "A new card is ready.";
const DEFAULT_PUSH_TITLE = "Agent Box";
const PUSH_PREVIEW_LENGTH = 160;

function log(event: string, fields: Record<string, unknown>): void {
  console.log(JSON.stringify({ event, ...fields }));
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function encodeJson(value: Record<string, unknown>): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function decodePrivateKey(pem: string): Uint8Array {
  const encoded = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replaceAll(/\s/g, "");
  if (!encoded) throw new Error("APNS_PRIVATE_KEY is not a valid PKCS#8 private key.");

  try {
    return Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0));
  } catch {
    throw new Error("APNS_PRIVATE_KEY is not valid base64 data.");
  }
}

function readPushConfiguration(env: Env, device: DeviceRow): PushConfiguration | null {
  const pushEnv = env as PushEnv;
  const keyId =
    device.apns_environment === "development"
      ? pushEnv.APNS_DEVELOPMENT_KEY_ID?.trim()
      : pushEnv.APNS_PRODUCTION_KEY_ID?.trim();
  const privateKey =
    device.apns_environment === "development"
      ? pushEnv.APNS_DEVELOPMENT_PRIVATE_KEY?.trim()
      : pushEnv.APNS_PRODUCTION_PRIVATE_KEY?.trim();
  const teamId = pushEnv.APNS_TEAM_ID?.trim();
  const topic = env.APNS_TOPIC.trim();
  if (!keyId || !privateKey || !teamId || !topic) return null;
  return { keyId, privateKey, teamId, topic };
}

async function makeProviderToken(configuration: PushConfiguration): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const configurationKey = `${configuration.teamId}:${configuration.keyId}`;
  const cachedProviderToken = cachedProviderTokens.get(configurationKey);
  if (cachedProviderToken && now - cachedProviderToken.issuedAt < 50 * 60) {
    return cachedProviderToken.value;
  }

  const header = encodeJson({ alg: "ES256", kid: configuration.keyId });
  const claims = encodeJson({ iss: configuration.teamId, iat: now });
  const unsignedToken = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodePrivateKey(configuration.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsignedToken),
  );
  const value = `${unsignedToken}.${base64Url(new Uint8Array(signature))}`;
  cachedProviderTokens.set(configurationKey, { configurationKey, issuedAt: now, value });
  return value;
}

function endpoint(device: DeviceRow): string {
  const host =
    device.apns_environment === "development" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  return `https://${host}/3/device/${device.apns_token}`;
}

async function removeInvalidDevice(env: Env, device: DeviceRow): Promise<void> {
  await env.DB.prepare("DELETE FROM devices WHERE id = ?1 AND account_id = ?2 AND apns_token = ?3")
    .bind(device.id, device.account_id, device.apns_token)
    .run();
}

async function activeCardCount(env: Env, accountId: string): Promise<number> {
  const now = Math.floor(Date.now() / 1000);
  const result = await env.DB.prepare(
    `SELECT COUNT(*) AS card_count
     FROM cards
     WHERE account_id = ?1
       AND cleared_at IS NULL
       AND (show_at IS NULL OR show_at <= ?2)
       AND (expires_at IS NULL OR expires_at > ?2)`,
  )
    .bind(accountId, now)
    .first<{ card_count: number }>();
  return Math.max(result?.card_count ?? 0, 0);
}

async function sendToDevice(
  env: Env,
  configuration: PushConfiguration,
  providerToken: string,
  device: DeviceRow,
  alert: PushAlert,
  badgeCount: number,
  send: typeof fetch,
): Promise<void> {
  const expiration = Math.floor(Date.now() / 1000) + 60 * 60;
  const response = await send(endpoint(device), {
    method: "POST",
    headers: {
      authorization: `bearer ${providerToken}`,
      "apns-collapse-id": alert.cardId ?? "agent-box-cards",
      "apns-expiration": String(expiration),
      "apns-priority": "10",
      "apns-push-type": "alert",
      "apns-topic": configuration.topic,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: { body: alert.body, title: alert.title },
        badge: badgeCount,
        "content-available": 1,
        "thread-id": "agent-box-cards",
      },
      ...(alert.cardId ? { card_id: alert.cardId } : {}),
    }),
  });
  if (response.ok) return;

  const payload: { reason?: string } = await response.json<{ reason?: string }>().catch(() => ({}));
  const reason = payload.reason ?? "unknown";
  if (
    response.status === 410 ||
    reason === "BadDeviceToken" ||
    reason === "DeviceTokenNotForTopic" ||
    reason === "Unregistered"
  ) {
    await removeInvalidDevice(env, device);
    log("push_device_removed", {
      account_id: device.account_id,
      device_id: device.id,
      reason,
      status: response.status,
    });
    return;
  }

  throw new Error(`APNs returned ${response.status}: ${reason}`);
}

export async function sendAccountUpdate(
  env: Env,
  accountId: string,
  send: typeof fetch = fetch,
  configurationOverride?: PushConfiguration,
  alert: PushAlert = { body: DEFAULT_PUSH_BODY, title: DEFAULT_PUSH_TITLE },
): Promise<void> {
  const result = await env.DB.prepare(
    `SELECT id, account_id, apns_token, apns_environment, created_at, last_seen_at
     FROM devices
     WHERE account_id = ?1 AND apns_token IS NOT NULL`,
  )
    .bind(accountId)
    .all<DeviceRow>();
  if (result.results.length === 0) return;

  const configuredDevices = result.results.flatMap((device) => {
    const configuration = configurationOverride ?? readPushConfiguration(env, device);
    if (!configuration) {
      log("push_not_configured", {
        account_id: accountId,
        apns_environment: device.apns_environment,
      });
      return [];
    }
    return [{ configuration, device }];
  });
  if (configuredDevices.length === 0) {
    return;
  }

  const badgeCount = await activeCardCount(env, accountId);
  const providerTokens = new Map<string, string>();
  for (const { configuration } of configuredDevices) {
    if (!providerTokens.has(configuration.keyId)) {
      providerTokens.set(configuration.keyId, await makeProviderToken(configuration));
    }
  }
  const deliveries = await Promise.allSettled(
    configuredDevices.map(async ({ configuration, device }) => {
      const providerToken = providerTokens.get(configuration.keyId);
      if (!providerToken) throw new Error("The APNs provider token is not available.");
      await sendToDevice(env, configuration, providerToken, device, alert, badgeCount, send);
    }),
  );
  const failures = deliveries.filter((delivery) => delivery.status === "rejected");
  log("push_sent", {
    account_id: accountId,
    badge_count: badgeCount,
    device_count: configuredDevices.length,
    failure_count: failures.length,
  });
  if (failures.length > 0) throw failures[0].reason;
}

export function makePushPreview(value: string | undefined): string {
  const clean = value?.replaceAll(/\s+/g, " ").trim();
  if (!clean) return DEFAULT_PUSH_BODY;
  if (clean.length <= PUSH_PREVIEW_LENGTH) return clean;
  return `${clean.slice(0, PUSH_PREVIEW_LENGTH - 1).trimEnd()}…`;
}

export function alertsForMessages(messages: Array<Message<CardUpdateMessage>>): Array<PushAlert> {
  return messages.map((message) => ({
    body: makePushPreview(message.body?.preview),
    cardId: message.body?.card_id,
    title: message.body?.title?.trim() || DEFAULT_PUSH_TITLE,
  }));
}

export async function handleCardUpdateBatch(
  batch: MessageBatch<CardUpdateMessage>,
  env: Env,
): Promise<void> {
  const messagesByAccount = new Map<string, Array<Message<CardUpdateMessage>>>();
  for (const message of batch.messages) {
    const accountId = message.body?.account_id;
    if (typeof accountId !== "string" || !accountId) {
      message.ack();
      continue;
    }
    const messages = messagesByAccount.get(accountId) ?? [];
    messages.push(message);
    messagesByAccount.set(accountId, messages);
  }

  await Promise.all(
    Array.from(messagesByAccount, async ([accountId, messages]) => {
      const alerts = alertsForMessages(messages);
      await Promise.all(
        messages.map(async (message, index) => {
          try {
            await sendAccountUpdate(env, accountId, fetch, undefined, alerts[index]);
            message.ack();
          } catch (error) {
            console.error(error);
            message.retry({ delaySeconds: 60 });
          }
        }),
      );
    }),
  );
}
