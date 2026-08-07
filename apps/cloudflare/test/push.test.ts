import { env } from "cloudflare:workers";
import { applyD1Migrations, type D1Migration } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { alertsForMessages, sendAccountUpdate, type PushConfiguration } from "../src/push";
import type { CardUpdateMessage } from "../src/types";

const testEnv = env as Env & { TEST_MIGRATIONS: D1Migration[] };
const deviceToken = "ab".repeat(32);

async function privateKeyPem(): Promise<string> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  const exported = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const bytes = new Uint8Array(exported as ArrayBuffer);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`;
}

beforeAll(async () => {
  await applyD1Migrations(testEnv.DB, testEnv.TEST_MIGRATIONS);
  await testEnv.DB.prepare(
    "INSERT INTO accounts (id, account_key_hash, created_at) VALUES (?1, ?2, ?3)",
  )
    .bind("account_push", "push-hash", Math.floor(Date.now() / 1000))
    .run();
  await testEnv.DB.prepare(
    `INSERT INTO cards (
       id, account_id, title, html, plain_text, source, created_at, metadata_json, content_trust
     ) VALUES (?1, ?2, ?3, ?4, ?5, 'email', ?6, '{}', 'untrusted')`,
  )
    .bind(
      "card_push",
      "account_push",
      "Push test",
      "<p>Push test</p>",
      "Push test",
      Math.floor(Date.now() / 1000),
    )
    .run();
});

describe("APNs delivery", () => {
  it("puts the card title and a one-line preview in the queued alert", () => {
    const messages = [
      {
        body: {
          account_id: "account_push",
          card_id: "card_private",
          preview: "First line.\n\nSecond   line.",
          source_name: "Private agent",
          title: "Private card title",
        },
      },
    ] as unknown as Array<Message<CardUpdateMessage>>;

    expect(alertsForMessages(messages)).toEqual([
      {
        body: "First line. Second line.",
        cardId: "card_private",
        title: "Private card title",
      },
    ]);
  });

  it("uses generic text when an older queued message has no card text", () => {
    const messages = [
      {
        body: {
          account_id: "account_push",
          card_id: "card_legacy",
        },
      },
    ] as unknown as Array<Message<CardUpdateMessage>>;

    expect(alertsForMessages(messages)).toEqual([
      {
        body: "A new card is ready.",
        cardId: "card_legacy",
        title: "Agent Box",
      },
    ]);
  });

  it("truncates a long card preview", () => {
    const messages = [
      {
        body: {
          account_id: "account_push",
          preview: "a".repeat(200),
          title: "Long card",
        },
      },
    ] as unknown as Array<Message<CardUpdateMessage>>;

    const [alert] = alertsForMessages(messages);
    expect(alert).toBeDefined();
    if (!alert) throw new Error("The push alert is missing.");
    expect(alert.body).toHaveLength(160);
    expect(alert.body.endsWith("…")).toBe(true);
  });

  it("makes one alert for each card in a queue batch", () => {
    const messages = [
      {
        body: {
          account_id: "account_push",
          card_id: "card_first",
          preview: "First preview",
          title: "First card",
        },
      },
      {
        body: {
          account_id: "account_push",
          card_id: "card_second",
          preview: "Second preview",
          title: "Second card",
        },
      },
    ] as unknown as Array<Message<CardUpdateMessage>>;

    expect(alertsForMessages(messages)).toEqual([
      { body: "First preview", cardId: "card_first", title: "First card" },
      { body: "Second preview", cardId: "card_second", title: "Second card" },
    ]);
  });

  it("sends a visible new-card alert with token authentication", async () => {
    await testEnv.DB.prepare(
      `INSERT INTO devices (
         id, account_id, apns_token, apns_environment, created_at, last_seen_at
       ) VALUES (?1, ?2, ?3, 'development', ?4, ?4)`,
    )
      .bind("device_push", "account_push", deviceToken, Math.floor(Date.now() / 1000))
      .run();

    const configuration: PushConfiguration = {
      keyId: "TESTKEY123",
      privateKey: await privateKeyPem(),
      teamId: "TESTTEAM12",
      topic: "cc.agentboxes",
    };
    let receivedURL = "";
    let receivedInit: RequestInit | undefined;
    let sendCount = 0;
    const send = (async (input: RequestInfo | URL, init?: RequestInit) => {
      sendCount += 1;
      receivedURL = String(input);
      receivedInit = init;
      return new Response(null, { status: 200 });
    }) as typeof fetch;

    await sendAccountUpdate(testEnv, "account_push", send, configuration, {
      body: "Background refresh test · 3",
      cardId: "card_test",
      title: "Codex",
    });

    expect(receivedURL).toBe(`https://api.sandbox.push.apple.com/3/device/${deviceToken}`);
    const headers = new Headers(receivedInit?.headers);
    expect(headers.get("apns-push-type")).toBe("alert");
    expect(headers.get("apns-priority")).toBe("10");
    expect(headers.get("apns-topic")).toBe("cc.agentboxes");
    expect(headers.get("apns-collapse-id")).toBe("card_test");
    expect(Number(headers.get("apns-expiration"))).toBeGreaterThan(Math.floor(Date.now() / 1000));
    expect(JSON.parse(String(receivedInit?.body))).toEqual({
      aps: {
        alert: { body: "Background refresh test · 3", title: "Codex" },
        badge: 1,
        "content-available": 1,
        "thread-id": "agent-box-cards",
      },
      card_id: "card_test",
    });
    expect(headers.get("authorization")).toMatch(/^bearer [^.]+\.[^.]+\.[^.]+$/);
    expect(sendCount).toBe(1);
  });

  it("removes a token that APNs reports as unregistered", async () => {
    const configuration: PushConfiguration = {
      keyId: "TESTKEY123",
      privateKey: await privateKeyPem(),
      teamId: "TESTTEAM12",
      topic: "cc.agentboxes",
    };
    const send = (async () =>
      Response.json({ reason: "Unregistered" }, { status: 410 })) as typeof fetch;

    await sendAccountUpdate(testEnv, "account_push", send, configuration);

    const device = await testEnv.DB.prepare("SELECT id FROM devices WHERE id = ?1")
      .bind("device_push")
      .first();
    expect(device).toBeNull();
  });
});
